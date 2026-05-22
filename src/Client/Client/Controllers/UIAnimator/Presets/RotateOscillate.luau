--!strict
--[[
	RotateOscillate
	---------------
	Drives a slow back-and-forth rotation on any GuiObject, using a
	critically-damped Spring on the Rotation property. The result is an
	organic pendulum that never overshoots — appropriate for idle-state
	attention effects (e.g. a reward arrow, a store icon, an alert badge).

	CollectionService tag "RotateOscillate" fires automatic wiring at boot;
	explicit UIAnimator:RotateOscillate(obj, opts) also works and returns a
	Handle for programmatic cancel.

	Default opts:
	  angle       = 5     (degrees from centre, each side)
	  period      = 2.2   (seconds for one full swing cycle — relaxed pendulum feel)
	  smoothTime  = 0.45  (longer spring acceleration; spring takes more time to reach
	                       +angle then more time to settle before reversing — natural
	                       deceleration at the rotation extremes)

	Handle: { Cancel: () -> (), IsRunning: () -> boolean }

	Per api-reference.md § 5.1 Spring — Spring.new(initial, smoothTime).
	Per api-reference.md § 3.1 Janitor.
	Per CLAUDE.md rule_8 — defensive logging.
	Per conventions.md § Module file structure.
]]

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Janitor = require(game.ReplicatedStorage.Packages.Janitor)
local Spring  = require(game.ReplicatedStorage.Utility.Spring)

local RotateOscillate = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type RotateOpts = {
	angle:      number?,
	period:     number?,
	smoothTime: number?,
}

export type Handle = {
	Cancel:    () -> (),
	IsRunning: () -> boolean,
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local TAG            = "RotateOscillate"
local DEFAULT_ANGLE  = 5
local DEFAULT_PERIOD = 2.2   -- relaxed pendulum feel (slightly tighter than 2.5)
local DEFAULT_SMOOTH = 0.45  -- longer spring acceleration → natural deceleration at extremes
local MAX_DT         = 1 / 30   -- clamp dt to avoid lag-spike overshoot (S4)

-- [GuiObject] → Handle  (for CS-tagged instances)
local _tagHandles: { [GuiObject]: Handle } = {}
local _moduleJanitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Private: core animation engine
-- ---------------------------------------------------------------------------

local function applyOscillate(obj: GuiObject, opts: RotateOpts?): Handle
	local o        = opts or {}
	local angle    = o.angle      or DEFAULT_ANGLE
	local period   = o.period     or DEFAULT_PERIOD
	local smooth   = o.smoothTime or DEFAULT_SMOOTH

	-- Capture into locals before any spawning (architecture.md § Capture state).
	local capturedAngle  = angle
	local capturedPeriod = period

	local spring   = Spring.new(0, smooth)
	spring.Target  = capturedAngle   -- start by swinging to +angle

	local running  = true
	local j        = Janitor.new()
	local conn: RBXScriptConnection

	-- Toggle target every half-period.
	local function scheduleToggle()
		local halfPeriod = capturedPeriod / 2
		task.delay(halfPeriod, function()
			if not running then return end
			spring.Target = -spring.Target
			scheduleToggle()
		end)
	end
	scheduleToggle()

	-- Poll spring every frame and write Rotation.
	conn = RunService.RenderStepped:Connect(function(dt)
		local clamped = math.min(dt, MAX_DT)
		local val = spring:Update(clamped)
		obj.Rotation = val
	end)

	j:Add(conn, "Disconnect")
	j:Add(function()
		running = false
		-- Reset rotation on cancel so the element doesn't stay tilted.
		obj.Rotation = 0
	end, true)

	local handle: Handle = {
		Cancel = function()
			j:Destroy()
		end,
		IsRunning = function()
			return running
		end,
	}

	return handle
end

-- ---------------------------------------------------------------------------
-- Private: CollectionService wiring
-- ---------------------------------------------------------------------------

local function teardownTagged(obj: GuiObject)
	local h = _tagHandles[obj]
	if h then
		h.Cancel()
		_tagHandles[obj] = nil
	end
end

local function wireTagged(obj: GuiObject)
	teardownTagged(obj)
	local h = applyOscillate(obj, nil)
	_tagHandles[obj] = h
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Apply oscillation to an explicit GuiObject.
	Returns a Handle with Cancel / IsRunning.
]]
function RotateOscillate.Apply(obj: GuiObject, opts: RotateOpts?): Handle
	if not obj then
		warn("[UIAnimator/RotateOscillate] Apply called with nil GuiObject")
		return {
			Cancel    = function() end,
			IsRunning = function() return false end,
		}
	end
	return applyOscillate(obj, opts)
end

--[[
	Boot the CollectionService watcher. Called from Presets.Start.
	(Not called by default from Presets.Start — caller wires it via
	UIAnimator/init.luau:KnitStart if desired. Exposed here for parity
	with ShiningButton.Start pattern.)
]]
function RotateOscillate.Start()
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("GuiObject") then
			wireTagged(inst :: GuiObject)
		end
	end

	_moduleJanitor:Add(
		CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
			if inst:IsA("GuiObject") then
				wireTagged(inst :: GuiObject)
			end
		end)
	)

	_moduleJanitor:Add(
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
			if inst:IsA("GuiObject") then
				teardownTagged(inst :: GuiObject)
			end
		end)
	)
end

return RotateOscillate
