--!strict
--[[
	Enlargen
	--------
	Scales a GuiObject from a small starting scale up to a target scale using
	a critically-damped Spring (S4 — sleitnick/spring@1.0.0). Creates or
	reuses a UIScale on the target element, making it composable with other
	layout-based sizing.

	Public API:
	  Enlargen.Apply(guiObject, opts?) -> Handle

	Handle: { Cancel: () -> (), Completed: Signal, IsRunning: () -> boolean }

	Default opts:
	  fromScale  = 0.6
	  toScale    = 1.0
	  smoothTime = 0.18
	  completedFn (optional callback, also fired on Completed signal)

	Per api-reference.md § 5.1 Spring — Spring.new(initial, smoothTime).
	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" per gotcha.
	Per api-reference.md § 3.2 Signal — lowercase Signal.new().
	Per CLAUDE.md rule_8 — defensive logging.
	Per conventions.md § Module file structure.
]]

local RunService = game:GetService("RunService")

local Janitor = require(game.ReplicatedStorage.Packages.Janitor)
local Signal  = require(game.ReplicatedStorage.Packages.Signal)
local Spring  = require(game.ReplicatedStorage.Utility.Spring)

local Enlargen = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type EnlargenOpts = {
	fromScale:   number?,
	toScale:     number?,
	smoothTime:  number?,
	completedFn: (() -> ())?,
}

export type Handle = {
	Cancel:    () -> (),
	Completed: any,     -- Signal<>
	IsRunning: () -> boolean,
}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local DEFAULT_FROM       = 0.6
local DEFAULT_TO         = 1.0
local DEFAULT_SMOOTH     = 0.18
local MAX_DT             = 1 / 30  -- clamp dt to avoid lag-spike overshoot (S4)
local SETTLE_DIST        = 0.002
local SETTLE_VEL         = 0.01

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function getOrCreateUIScale(obj: GuiObject): UIScale
	local existing = obj:FindFirstChildOfClass("UIScale")
	if existing then
		return existing :: UIScale
	end
	local s = Instance.new("UIScale")
	s.Parent = obj
	return s
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Apply a scale-up animation to guiObject.
	Returns a Handle with Cancel / Completed / IsRunning.
]]
function Enlargen.Apply(guiObject: GuiObject, opts: EnlargenOpts?): Handle
	if not guiObject then
		warn("[UIAnimator/Enlargen] Apply called with nil guiObject — returning no-op handle")
		local noop: Handle = {
			Cancel    = function() end,
			Completed = Signal.new(),
			IsRunning = function() return false end,
		}
		return noop
	end

	local o          = opts or {}
	local fromScale  = o.fromScale  or DEFAULT_FROM
	local toScale    = o.toScale    or DEFAULT_TO
	local smoothTime = o.smoothTime or DEFAULT_SMOOTH
	local cbFn       = o.completedFn

	-- Capture into locals before any async work (architecture.md § Capture state).
	local capturedTo  = toScale
	local capturedCb  = cbFn

	local completed   = Signal.new()
	local running     = true
	local j           = Janitor.new()

	-- Wire Janitor cleanup: disconnects the Heartbeat connection.
	local conn: RBXScriptConnection? = nil
	j:Add(function()
		running = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end, true)

	-- Set starting scale immediately so the guiObject doesn't flash at toScale.
	local uiScale    = getOrCreateUIScale(guiObject)
	uiScale.Scale    = fromScale

	local spring     = Spring.new(fromScale, smoothTime)
	spring.Target    = capturedTo

	conn = RunService.Heartbeat:Connect(function(dt)
		if not running then return end
		local clamped = math.min(dt, MAX_DT)
		local current = spring:Update(clamped)
		uiScale.Scale = current

		local vel = spring.Velocity
		local velMag = typeof(vel) == "number" and math.abs(vel) or 0
		if math.abs(current - capturedTo) < SETTLE_DIST and velMag < SETTLE_VEL then
			-- Snap to target, clean up, fire completion.
			uiScale.Scale = capturedTo
			running = false
			if conn then
				conn:Disconnect()
				conn = nil
			end
			completed:Fire()
			if capturedCb then
				task.spawn(capturedCb)
			end
		end
	end)

	local handle: Handle = {
		Cancel = function()
			j:Destroy()
		end,
		Completed = completed,
		IsRunning = function()
			return running
		end,
	}

	return handle
end

return Enlargen
