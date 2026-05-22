--[[
	HapticsController
	-----------------
	Wraps Roblox HapticService with named presets for gamepad vibration feedback.
	Gamepad-less players receive silent no-ops.

	Presets:
	    Small  — short tap.    Small motor 0.4 amp, 80ms.
	    Strong — sharp bump.   Both motors 0.7 amp, 120ms.
	    Rumble — sustained.    Large 0.5 + Small 0.3, 600ms.

	Public API:
	    HapticsController:Play(presetName, gamepad?)
	    HapticsController:Stop(gamepad?)
	    HapticsController.Presets  (read-only)

	Per architecture.md § Require Paths — Knit + Janitor.
	Per api-reference.md § 3.1 Janitor — :Add(conn, "Disconnect") explicit method.
	Per architecture.md § Critical Bans — capture state into locals before task.delay.
]]

local HapticService = game:GetService("HapticService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit   = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local HapticsController = Knit.CreateController {
	Name = "HapticsController",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Vibration motor references
local Large = Enum.VibrationMotor.Large
local Small = Enum.VibrationMotor.Small

-- Preset definitions: { large: number, small: number, duration: number }
HapticsController.Presets = {
	Small = {
		large    = 0,
		small    = 0.4,
		duration = 0.080,
	},
	Strong = {
		large    = 0.7,
		small    = 0.7,
		duration = 0.120,
	},
	Rumble = {
		large    = 0.5,
		small    = 0.3,
		duration = 0.600,
	},
}

-- Per api-reference.md § 3.1 Janitor — one controller-scope janitor for per-play tasks.
local _janitor = Janitor.new()

-- Track whether we have already warned about no motor support (warn once per session).
local _warnedNoSupport: { [string]: boolean } = {}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Internal: zero both motors on a gamepad immediately.
local function _stopMotors(gamepad: Enum.UserInputType)
	HapticService:SetMotor(gamepad, Large, 0)
	HapticService:SetMotor(gamepad, Small, 0)
end

-- Internal: play a single motor if supported.
-- Returns true if at least one motor fired.
local function _trySetMotor(gamepad: Enum.UserInputType, motor: Enum.VibrationMotor, amplitude: number): boolean
	local ok, supported = pcall(function()
		return HapticService:IsMotorSupported(gamepad, motor)
	end)
	if not ok then
		warn("[HapticsController] IsMotorSupported errored — " .. tostring(supported))
		return false
	end
	if not supported then
		return false
	end
	HapticService:SetMotor(gamepad, motor, amplitude)
	return true
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	HapticsController:Play(presetName, gamepad?)
	Plays a named vibration preset. Silently no-ops if motors are not supported.
	gamepad defaults to Enum.UserInputType.Gamepad1.
]]
function HapticsController:Play(presetName: string, gamepad: Enum.UserInputType?)
	local resolvedGamepad = gamepad or Enum.UserInputType.Gamepad1
	local preset = self.Presets[presetName]
	if not preset then
		warn("[HapticsController] unknown preset '" .. tostring(presetName) .. "' — no vibration played")
		return
	end

	-- Capture into locals BEFORE any delay (architecture.md Critical Bans).
	local largAmp: number   = preset.large
	local smallAmp: number  = preset.small
	local duration: number  = preset.duration

	-- Gate: at least one motor must be supported.
	local largeOk = _trySetMotor(resolvedGamepad, Large, largAmp)
	local smallOk = _trySetMotor(resolvedGamepad, Small, smallAmp)

	if not largeOk and not smallOk then
		local warnKey = tostring(resolvedGamepad)
		if not _warnedNoSupport[warnKey] then
			_warnedNoSupport[warnKey] = true
			warn(
				"[HapticsController] no VibrationMotor supported on "
					.. warnKey
					.. " — haptics disabled for this gamepad"
			)
		end
		return
	end

	-- Zero the motors after the preset duration.
	-- Capture gamepad into a local so the delay closure sees the value at call time.
	local capturedGamepad: Enum.UserInputType = resolvedGamepad
	local thread = task.delay(duration, function()
		_stopMotors(capturedGamepad)
	end)

	-- Track the thread so :Stop() can cancel it via the janitor.
	_janitor:Add(function()
		task.cancel(thread)
		_stopMotors(capturedGamepad)
	end, true, "activePlay_" .. presetName .. tostring(os.clock()))
end

--[[
	HapticsController:Stop(gamepad?)
	Zeros both motors immediately and cancels any pending auto-stop.
]]
function HapticsController:Stop(gamepad: Enum.UserInputType?)
	local resolvedGamepad = gamepad or Enum.UserInputType.Gamepad1
	_janitor:Cleanup()
	_stopMotors(resolvedGamepad)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function HapticsController:KnitInit()
	-- Nothing to initialize at KnitInit time.
end

function HapticsController:KnitStart()
	-- Nothing to start at KnitStart time.
end

return HapticsController
