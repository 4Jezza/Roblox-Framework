--!strict
--[[
	Countdown
	---------
	Animated countdown/countup label. Ticks at opts.tickInterval (default
	0.1s), renders one decimal place, and plays a sound + UIScale pop + label
	rotation impulse on every whole-number hit.

	Direction is inferred: if from > to, counts down; otherwise up.
	Step magnitude always equals tickInterval.

	Whole-number flair (per Words! TableClient.luau:2612-2660, S4, S6):
	  One persistent UIScale on the label. Two persistent springs (scaleSpring,
	  rotSpring) created ONCE at countdown start and alive for the entire
	  countdown duration. One persistent Heartbeat connection drives both springs
	  in lockstep — it runs continuously for the whole countdown, never
	  reconnected. On each whole-number boundary _kickSprings() writes
	  Velocity directly (no :Impulse), resetting Targets to rest so the springs
	  always damp back. The Heartbeat is registered into _janitor so it is
	  reaped on Cancel, natural completion, or label destruction.

	CountdownHandle: { Cancel: () -> (), IsRunning: () -> boolean, GetCurrent: () -> number }

	Default opts:
	  from          (required)
	  to            = 0
	  tickInterval  = 0.1
	  onWholeNumber = nil
	  onComplete    = nil
	  soundName     = "HeavyCountdown"
	  pairSound     = nil

	Per Words! TableClient.luau:2612-2660 — persistent spring + persistent Heartbeat pattern.
	Per api-reference.md § 5.1 Spring — Spring.new(initial, smoothTime), .Velocity, .Target.
	Per api-reference.md § 3.1 Janitor.
	Per CLAUDE.md rule_8 — defensive logging.
	Per conventions.md § Module file structure.
]]

local RunService = game:GetService("RunService")
local Knit       = require(game.ReplicatedStorage.Packages.Knit)
local Janitor    = require(game.ReplicatedStorage.Packages.Janitor)
local Spring     = require(game.ReplicatedStorage.Utility.Spring)

local Countdown = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type CountdownOpts = {
	from:          number,
	to:            number?,
	tickInterval:  number?,
	onWholeNumber: ((n: number) -> ())?,
	onComplete:    (() -> ())?,
	soundName:     string?,
	pairSound:     any?,
}

export type CountdownHandle = {
	Cancel:     () -> (),
	IsRunning:  () -> boolean,
	GetCurrent: () -> number,
}

-- ---------------------------------------------------------------------------
-- Constants (per Words! TableClient.luau:2629/2654/2658)
-- ---------------------------------------------------------------------------

local MAX_DT           = 1 / 30     -- clamp dt to avoid lag-spike overshoot (Spring.MAX_DT not exposed by sleitnick/spring@1.0.0)
local SPRING_SMOOTHTIME = 0.25      -- per Words! TableClient:2629 (both springs share one smoothTime)
local SCALE_KICK_VEL   = 0.9       -- per Words! TableClient:2654 — direct Velocity write, springs damp back to Target 1.0
local ROT_KICK_VEL     = 120       -- per Words! TableClient:2658 (degrees/sec)
local SCALE_MIN        = 0.5
local SCALE_MAX        = 2.0
local DEFAULT_INTERVAL = 0.1
local DEFAULT_SOUND    = "HeavyCountdown"

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Lazy SoundController getter — deferred so load order doesn't matter.
local _soundController: any = nil
local function getSoundController(): any?
	if _soundController then return _soundController end
	local ok, ctrl = pcall(function()
		return Knit.GetController("SoundController")
	end)
	if ok and ctrl then
		_soundController = ctrl
		return ctrl
	end
	return nil
end

-- Ensure a single named UIScale lives on the label (per Words! TableClient:2618-2628).
-- Named "CountdownTimerScale" to avoid collisions with other presets.
local function ensureUIScale(label: TextLabel): UIScale
	local existing = label:FindFirstChild("CountdownTimerScale")
	if existing and existing:IsA("UIScale") then
		return existing :: UIScale
	end
	local scale = Instance.new("UIScale")
	scale.Name  = "CountdownTimerScale"
	scale.Scale = 1.0
	scale.Parent = label
	return scale
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Start a countdown/countup on the given TextLabel.
	Returns a CountdownHandle with Cancel / IsRunning / GetCurrent.
]]
function Countdown.Start(label: TextLabel, opts: CountdownOpts): CountdownHandle
	if not label then
		warn("[UIAnimator/Countdown] Start: label is nil — aborting")
		return {
			Cancel     = function() end,
			IsRunning  = function() return false end,
			GetCurrent = function() return 0 end,
		}
	end

	-- Capture opts into locals before task.spawn (architecture.md § Capture state).
	local from          = opts.from
	local target        = opts.to or 0
	local interval      = opts.tickInterval or DEFAULT_INTERVAL
	local onWhole       = opts.onWholeNumber
	local onComplete    = opts.onComplete
	local soundName     = opts.soundName or DEFAULT_SOUND
	local pairSound     = opts.pairSound
	local capturedLabel = label

	local countingDown = from > target
	local step         = countingDown and -interval or interval

	local current  = from
	local running  = true

	-- _janitor owns: the Heartbeat spring connection, the LinkToInstance binding.
	local _janitor = Janitor.new()

	-- ONE persistent UIScale on the label (per Words! TableClient:2618-2628).
	local uiScale = ensureUIScale(label)

	-- TWO persistent springs created ONCE, alive through the whole countdown
	-- (per Words! TableClient:2629-2633).
	local scaleSpring = Spring.new(1.0, SPRING_SMOOTHTIME)
	scaleSpring.Target = 1.0

	local rotSpring = Spring.new(0, SPRING_SMOOTHTIME)
	rotSpring.Target = 0

	-- _kickSprings: write Velocity directly (no :Impulse) and reset Targets
	-- so springs always damp back to rest (per Words! TableClient:2651-2659).
	-- Called once at countdown launch (initial pop) and on every whole-number boundary.
	local function _kickSprings()
		scaleSpring.Target   = 1.0
		scaleSpring.Velocity = SCALE_KICK_VEL
		rotSpring.Target     = 0
		rotSpring.Velocity   = ROT_KICK_VEL
	end

	-- ONE persistent Heartbeat — connected ONCE at countdown start, runs
	-- continuously for the full countdown duration (per Words! TableClient:2641-2648).
	-- Registered into _janitor so it is reaped on Cancel / complete / label destroy.
	local hbConn = RunService.Heartbeat:Connect(function(dt: number)
		if not running then return end
		local sv = scaleSpring:Update(math.min(dt, MAX_DT))
		local rv = rotSpring:Update(math.min(dt, MAX_DT))
		uiScale.Scale          = math.clamp(sv, SCALE_MIN, SCALE_MAX)
		capturedLabel.Rotation = rv
	end)
	_janitor:Add(hbConn, "Disconnect", "spring")

	-- "Next whole number to fire at" tracking. Start one below the initial
	-- whole-number floor so the FIRST kick fires when `current` reaches that
	-- integer exactly (not when it crosses a 0.5 boundary). Round-to-nearest
	-- `math.floor(current + 0.5)` would transition at 4.5/3.5/2.5 — too early.
	-- This pattern fires AT 4.0, 3.0, 2.0, 1.0 (the moment the label reads the
	-- whole number) per the Words! TableClient:2672-2678 convention.
	local nextWholeKick: number = math.floor(from) - 1

	local function onTick()
		-- Advance.
		current = current + step

		-- Clamp to target.
		if countingDown and current < target then
			current = target
		elseif not countingDown and current > target then
			current = target
		end

		-- Render.
		capturedLabel.Text = string.format("%.1f", current)

		-- Notify pairSound if provided.
		if pairSound and type(pairSound) == "table" and pairSound.SetProgress then
			local duration = math.abs(from - target)
			local elapsed  = math.abs(from - current)
			local t = duration > 0 and (elapsed / duration) or 1
			pcall(function() pairSound:SetProgress(t) end)
		end

		-- Whole-number detection — fire AT the integer, not when crossing a
		-- 0.5 boundary. We watch `current` and trigger the moment it reaches
		-- nextWholeKick (e.g., when 4.1 ticks down to 4.0 the label reads "4.0"
		-- and the kick fires; nextWholeKick then decrements to 3 to wait for "3.0").
		if current <= nextWholeKick + 1e-4 then
			local kickedAt = nextWholeKick
			nextWholeKick = nextWholeKick - 1

			-- Springs kick FIRST, then sound, then log, then caller callback
			-- (S6: layered reaction — primary motion before secondary feedback).
			_kickSprings()

			-- Sound.
			local ctrl = getSoundController()
			if ctrl then
				pcall(function() ctrl:Play(soundName) end)
			end

			print("[Countdown] whole-number hit:", kickedAt)

			-- Caller callback.
			if onWhole then
				task.spawn(onWhole, kickedAt)
			end
		end

		-- Completion check.
		if current == target then
			running = false
			if onComplete then
				task.spawn(onComplete)
			end
		end
	end

	-- Initial render + initial kick (pop on countdown launch, per Words! TableClient:2665-2666).
	capturedLabel.Text = string.format("%.1f", current)
	_kickSprings()

	-- Link _janitor to the label BEFORE the tick loop starts so that if the
	-- label is destroyed at any point (including mid-loop), _janitor cleans up
	-- and running=false is set via the Cancel path.
	-- Per api-reference.md § 3.1 Janitor :LinkToInstance.
	_janitor:LinkToInstance(label)

	-- Tick loop.
	-- _janitor:Destroy() here is valid: _janitor is Janitor.new() above — not the
	-- handle table. This call is the lifecycle close after the loop exits naturally.
	-- On destroy: hbConn is disconnected (index "spring"), then label.Rotation and
	-- uiScale.Scale are reset to clean visual rest state.
	task.spawn(function()
		while running do
			task.wait(interval)
			if not running then break end
			onTick()
		end
		-- Clean visual rest state before janitor tears down.
		capturedLabel.Rotation = 0
		uiScale.Scale          = 1.0
		_janitor:Destroy()
	end)

	local handle: CountdownHandle = {
		Cancel = function()
			running = false
			capturedLabel.Rotation = 0
			uiScale.Scale          = 1.0
			_janitor:Destroy()
		end,
		IsRunning = function()
			return running
		end,
		GetCurrent = function()
			return current
		end,
	}

	return handle
end

return Countdown
