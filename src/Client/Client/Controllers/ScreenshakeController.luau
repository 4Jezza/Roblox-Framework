--[[
	ScreenshakeController
	----------------------
	Applies Perlin-noise camera shake presets via the sleitnick Shake package.
	Maintains an active-shakes list; sums pos/rot offsets each frame.
	Binds via RunService:BindToRenderStep at Enum.RenderPriority.Camera.Value + 1
	so the offset is applied AFTER Roblox's own camera update each frame — Roblox
	resets camera.CFrame to the "true" follow pose, then we layer our shake on top.
	Using RenderStepped:Connect (priority < Camera) caused drift: the nudge was
	applied before Roblox read camera.CFrame and could accumulate across frames.
	Unbinds the render step when the list is empty to avoid idle CPU cost.

	Presets:
	    TinyIntense — small, buzzier snap.    Amplitude 1.0,  Freq 28, FadeIn 0.02, Sustain 0.05, FadeOut 0.15
	                                          PositionInfluence (0.6,0.6,0.6), RotationInfluence (0.4,0.4,0.4)
	    LongRumble  — sustained position rumble. Amplitude 2.5, Freq 18, FadeIn 0.05, Sustain 0.5, FadeOut 0.6
	                                          PositionInfluence (1.2,1.2,1.2), RotationInfluence (0.25,0.25,0.25)
	    Hit         — sharp impactful punch.  Amplitude 4.0,  Freq 22, FadeIn 0.02, Sustain 0.15, FadeOut 0.30
	                                          PositionInfluence (2.0,2.0,2.0), RotationInfluence (0.3,0.3,0.3)

	PositionInfluence / RotationInfluence are set natively on the Shake instance
	(sleitnick_shake@1.1.0 defaults: PositionInfluence = Vector3.one, RotationInfluence = Vector3.one).
	High PositionInfluence × high Amplitude = strong positional rumble.
	Low RotationInfluence keeps the camera from spinning.

	Public API:
	    ScreenshakeController:Play(presetName)
	    ScreenshakeController:Stop()
	    ScreenshakeController.Presets  (read-only)

	Per architecture.md § Require Paths — Knit, Janitor, Shake.
	Per api-reference.md § 5.2 Shake — :BindToRenderStep / :Start / :Stop / :Destroy.
	Per api-reference.md § 3.1 Janitor — function cleanup registered with true for unbind.
]]

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- Per api-reference.md § 5.2 Shake — require path from quick-index.
local ShakeOk, Shake = pcall(function()
	return require(ReplicatedStorage.Packages.Shake)
end)

if not ShakeOk then
	warn("[ScreenshakeController] Packages.Shake not found — falling back to math.noise implementation")
end

local ScreenshakeController = Knit.CreateController {
	Name = "ScreenshakeController",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Preset definitions used when Shake package is available.
-- Fields map directly to Shake instance properties.
-- PositionInfluence / RotationInfluence are first-class Shake properties
-- (sleitnick_shake@1.1.0 defaults both to Vector3.one).
-- High Amplitude × high PositionInfluence = strong positional rumble.
-- Low RotationInfluence suppresses camera spin on large amplitudes.
-- Per api-reference.md § 5.2 Shake.
ScreenshakeController.Presets = {
	TinyIntense = {
		Amplitude         = 1.0,
		Frequency         = 28,
		FadeInTime        = 0.02,
		SustainTime       = 0.05,
		FadeOutTime       = 0.15,
		PositionInfluence = Vector3.new(0.6, 0.6, 0.6),
		RotationInfluence = Vector3.new(0.4, 0.4, 0.4),
	},
	LongRumble = {
		Amplitude         = 2.5,
		Frequency         = 18,
		FadeInTime        = 0.05,
		SustainTime       = 0.5,
		FadeOutTime       = 0.6,
		PositionInfluence = Vector3.new(1.2, 1.2, 1.2),
		RotationInfluence = Vector3.new(0.25, 0.25, 0.25),
	},
	Hit = {
		Amplitude         = 4.0,
		Frequency         = 22,
		FadeInTime        = 0.02,
		SustainTime       = 0.15,
		FadeOutTime       = 0.30,
		PositionInfluence = Vector3.new(2.0, 2.0, 2.0),
		RotationInfluence = Vector3.new(0.3, 0.3, 0.3),
	},
}

-- Active-shakes list: each entry holds a Shake instance and its unique render name.
-- PositionInfluence / RotationInfluence are set directly on the Shake instance
-- so no per-entry multiplier is needed here.
-- type entry = { shake: Shake, name: string }
local _activeShakes: { { shake: any, name: string } } = {}

-- Single Janitor owns the render-step bind + tracks active shakes.
local _janitor = Janitor.new()

-- Bind name for RunService:BindToRenderStep (nil when no shakes are running).
-- Using BindToRenderStep at Camera+1 instead of RenderStepped:Connect so the
-- shake offset is applied AFTER Roblox resets camera.CFrame each frame, which
-- prevents per-frame drift accumulation (per api-reference.md § 5.2 Shake).
local SHAKE_BIND_NAME        = "ScreenshakeController_Apply"
local _renderBoundName: string? = nil

-- Fallback noise state (used when Shake package is unavailable).
local _fallbackTimer: number   = 0
local _fallbackDuration: number = 0
local _fallbackAmplitude: number = 0

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function _removeShake(name: string)
	for i = #_activeShakes, 1, -1 do
		if _activeShakes[i].name == name then
			table.remove(_activeShakes, i)
			break
		end
	end
end

local function _tryUnbind()
	if #_activeShakes == 0 and _fallbackTimer <= 0 and _renderBoundName then
		pcall(RunService.UnbindFromRenderStep, RunService, _renderBoundName)
		_renderBoundName = nil
		-- Drop the janitor entry so controller-scope cleanup doesn't double-unbind.
		_janitor:RemoveNoClean("renderUnbind")
	end
end

local function _ensureRenderBound()
	if _renderBoundName then
		return
	end

	_renderBoundName = SHAKE_BIND_NAME

	-- Camera.Value + 1 ensures we run AFTER Roblox's own camera update each frame.
	-- Roblox resets camera.CFrame to the true follow pose at Camera priority, then
	-- we layer the shake offset on top — preventing drift accumulation.
	-- Per api-reference.md § 5.2 Shake and the task spec (BindToRenderStep pattern).
	RunService:BindToRenderStep(SHAKE_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			warn("[ScreenshakeController] workspace.CurrentCamera is nil — skipping shake frame")
			return
		end

		local totalPos = Vector3.zero
		local totalRot = Vector3.zero

		if ShakeOk then
			-- Sum contributions from all active Shake instances.
			-- RotationInfluence is already set on each Shake instance so
			-- no additional per-entry multiplier is needed here.
			local completed: { string } = {}
			for _, entry in _activeShakes do
				local pos, rot, isDone = entry.shake:Update()
				totalPos = totalPos + pos
				totalRot = totalRot + rot
				if isDone then
					table.insert(completed, entry.name)
				end
			end
			-- Clean up completed shakes outside the loop.
			for _, name in completed do
				for _, entry in _activeShakes do
					if entry.name == name then
						entry.shake:Stop()
						entry.shake:Destroy()
						break
					end
				end
				_removeShake(name)
			end
		else
			-- Fallback: simple math.noise-based decay shake using actual dt.
			if _fallbackTimer > 0 then
				_fallbackTimer = math.max(0, _fallbackTimer - dt)
				local t = time()
				local decay = _fallbackTimer / _fallbackDuration
				local noiseX = math.noise(t * 8,  0, 0) * 2 - 1
				local noiseY = math.noise(0, t * 8,  0) * 2 - 1
				local noiseZ = math.noise(0, 0, t * 8)  * 2 - 1
				totalPos = Vector3.new(noiseX, noiseY, noiseZ) * (_fallbackAmplitude * decay)
			end
		end

		-- Apply summed offset as an additive CFrame nudge on top of Roblox's
		-- already-settled camera pose (safe because we run at Camera.Value + 1).
		if totalPos.Magnitude > 0 or totalRot.Magnitude > 0 then
			camera.CFrame = camera.CFrame
				* CFrame.new(totalPos)
				* CFrame.Angles(totalRot.X, totalRot.Y, totalRot.Z)
		end

		_tryUnbind()
	end)

	-- Register cleanup as a function (true = call as function) per api-reference.md § 3.1.
	-- Janitor:Add with a function + true calls it directly on cleanup.
	_janitor:Add(function()
		if _renderBoundName then
			pcall(RunService.UnbindFromRenderStep, RunService, _renderBoundName)
			_renderBoundName = nil
		end
	end, true, "renderUnbind")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ScreenshakeController:Play(presetName: string)
	local preset = self.Presets[presetName]
	if not preset then
		warn(
			"[ScreenshakeController] unknown preset '"
				.. tostring(presetName)
				.. "' — no shake applied"
		)
		return
	end

	if ShakeOk then
		local shake = Shake.new()
		shake.Amplitude         = preset.Amplitude
		shake.Frequency         = preset.Frequency
		shake.FadeInTime        = preset.FadeInTime
		shake.SustainTime       = preset.SustainTime
		shake.FadeOutTime       = preset.FadeOutTime
		shake.PositionInfluence = preset.PositionInfluence
		shake.RotationInfluence = preset.RotationInfluence

		-- Use manual :Update() calls from our RenderStepped loop instead of
		-- :BindToRenderStep so we can sum multiple simultaneous shakes.
		shake:Start()

		local name = Shake.NextRenderName()
		table.insert(_activeShakes, {
			shake = shake,
			name  = name,
		})
	else
		-- Fallback: drive noise shake for the total duration of the preset.
		_fallbackDuration  = (preset.FadeInTime or 0) + (preset.SustainTime or 0) + (preset.FadeOutTime or 0)
		_fallbackTimer     = _fallbackDuration
		_fallbackAmplitude = preset.Amplitude
	end

	_ensureRenderBound()
end

function ScreenshakeController:Stop()
	if ShakeOk then
		for _, entry in _activeShakes do
			entry.shake:Stop()
			entry.shake:Destroy()
		end
	end
	table.clear(_activeShakes)
	_fallbackTimer = 0

	if _renderBoundName then
		pcall(RunService.UnbindFromRenderStep, RunService, _renderBoundName)
		_renderBoundName = nil
		_janitor:RemoveNoClean("renderUnbind")
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function ScreenshakeController:KnitInit()
	-- Nothing at KnitInit time.
end

function ScreenshakeController:KnitStart()
	-- Nothing at KnitStart time.
end

return ScreenshakeController
