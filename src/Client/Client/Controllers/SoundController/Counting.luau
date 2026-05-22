--[[
	SoundController/Counting
	------------------------
	Implements CountTo: a pitched tick sequence that sonically represents a
	number counting up or down over a fixed duration.

	Cadence and pitch maths
	-----------------------
	Total ticks  = math.max(2, math.floor(totalSeconds / 0.06))   (~16 ticks/sec base)

	Cadence easing  — tick intervals grow from MIN_INTERVAL → MAX_INTERVAL
	  "Slow" (default, count-down feel):
	      interval(i) = MIN + (MAX - MIN) * t^3   (t = i/totalTicks)
	      stays fast for most of the duration, slows sharply at the end
	  "Fast" (count-up feel):
	      interval(i) = MAX - (MAX - MIN) * t^3   (t = i/totalTicks)
	      stays slow for most of the duration, speeds up sharply near the end
	  MIN_INTERVAL = 0.04s   MAX_INTERVAL = 0.18s

	Pitch ramp
	  count-up  (from < to):  pitch = basePitch * lerp(0.7, 1.5, i/totalTicks)
	  count-down (from > to): pitch = basePitch * lerp(1.5, 0.7, i/totalTicks)
	  Flat (from == to):      pitch = basePitch * 1.0

	SetProgress(t)  — 0..1; lets external callers (UIAnimator:Countdown) jump the
	internal tick index so pitch tracks the displayed value rather than elapsed time.

	Called exclusively by SoundController:CountTo — do not require this module
	from outside SoundController.

	Per architecture.md § Sound runtime path — plays via SoundController:Play.
	Per api-reference.md § 3.1 Janitor — per-tick cleanup via single thread cancel.
]]

local MIN_INTERVAL = 0.04
local MAX_INTERVAL = 0.18

local Counting = {}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	CountTo(controller, opts) -> CountHandle
	Spawns a coroutine that fires timed :Play calls on `opts.soundName`
	(default "UI.Counting") with cadence + pitch ramp logic.

	CountHandle:
	  Cancel()           — stop immediately
	  IsPlaying()        — true while the tick loop is alive
	  SetProgress(t)     — 0..1; aligns internal tick index to match `t`
]]
function Counting.CountTo(controller: any, opts: any): any
	local from         = opts.from         or 0
	local to           = opts.to           or 0
	local totalSeconds = opts.totalSeconds or 1
	local soundName    = opts.soundName    or "UI.Counting"
	local basePitch    = opts.basePitch    or 1.0
	local easing       = opts.easing       or "Slow"

	local totalTicks = math.max(2, math.floor(totalSeconds / 0.06))

	-- Determine direction for pitch ramp.
	local countingUp = from < to

	-- State shared between the coroutine and the handle.
	local currentTick: number   = 0
	local cancelled:   boolean  = false
	local running:     boolean  = true

	-- External progress override: when set, the next tick aligns to this ratio.
	local pendingProgress: number? = nil

	-- ---------------------------------------------------------------------------
	-- Handle (returned immediately; coroutine started below)
	-- ---------------------------------------------------------------------------

	local handle = {
		Cancel = function()
			cancelled = true
			running   = false
		end,
		IsPlaying = function(): boolean
			return running
		end,
		SetProgress = function(t: number)
			-- Clamp and map to tick index; applied on next loop iteration.
			pendingProgress = math.clamp(t, 0, 1)
		end,
	}

	-- ---------------------------------------------------------------------------
	-- Tick coroutine
	-- ---------------------------------------------------------------------------

	task.spawn(function()
		for i = 1, totalTicks do
			if cancelled then break end

			-- Apply external progress override if set.
			if pendingProgress ~= nil then
				currentTick   = math.floor(pendingProgress * totalTicks)
				pendingProgress = nil
			else
				currentTick = i
			end

			-- Normalised progress for this tick (0..1).
			local t = (totalTicks > 1) and ((currentTick - 1) / (totalTicks - 1)) or 0
			t = math.clamp(t, 0, 1)

			-- Pitch ramp.
			local pitchScale: number
			if from == to then
				pitchScale = 1.0
			elseif countingUp then
				-- count-up: low → high
				pitchScale = lerp(0.7, 1.5, t)
			else
				-- count-down: high → low
				pitchScale = lerp(1.5, 0.7, t)
			end
			local tickPitch = basePitch * pitchScale

			-- Play the tick sound with computed pitch.
			controller:Play(soundName, {
				volume = 0.6,
				pitch  = tickPitch,
			})

			-- Cadence easing — compute interval for this tick index.
			-- t^3 back-loads the slowdown: cadence stays near its starting rate
			-- for most of the count and changes sharply only in the final stretch.
			local tCubed = t * t * t
			local interval: number
			if easing == "Fast" then
				-- Starts slow (MAX), accelerates sharply near the end (MIN).
				interval = lerp(MAX_INTERVAL, MIN_INTERVAL, tCubed)
			else
				-- "Slow" default: starts fast (MIN), slows sharply near the end.
				interval = lerp(MIN_INTERVAL, MAX_INTERVAL, tCubed)
			end

			-- Wait the computed interval. Check cancel after wait.
			task.wait(interval)
			if cancelled then break end
		end

		running = false
	end)

	return handle
end

return Counting
