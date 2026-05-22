--!strict
--[[
	Confetti
	--------
	Screen-space confetti burst. Maintains ONE persistent ConfettiGui
	ScreenGui under PlayerGui, reused across emits. Auto-destroys the gui
	when both active-piece count AND active-emitter count reach zero.

	Sound convention:
	  Pass opts.sound = nil (or omit the field) to play the default sound.
	  Pass opts.sound = Confetti.NoSound  to suppress sound for this emit.
	  Confetti.NoSound is a unique table sentinel — using it (rather than
	  plain false/nil) keeps the caller's intent explicit and grep-able.

	Per api-reference.md § 3.1 Janitor — one Janitor per emit burst.
	Per api-reference.md § 5.1 Spring — not used here (particle is raw
	  RenderStepped with velocity + gravity — see notes below).
	Per CLAUDE.md rule_7 — raw TweenService NOT used for UI; particle
	  motion is computed per-frame via RenderStepped, which is the
	  canonical approach for fire-and-forget moving GUI frames.
	Per CLAUDE.md rule_8 — defensive logging on all failable lookups.
	Per conventions.md § Module file structure.

	Public API:
	  Confetti.NoSound : table   (sentinel — pass as opts.sound to skip sfx)
	  Confetti.Emit(opts?)       (fire and forget)
]]

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService") -- unused but kept for future SpinUI tagging
local Knit          = require(game.ReplicatedStorage.Packages.Knit)
local Janitor       = require(game.ReplicatedStorage.Packages.Janitor)

local Confetti = {}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Unique sentinel: pass as opts.sound to suppress the reward sound this emit.
Confetti.NoSound = {} :: any

local DEFAULT_AMOUNT    = 250
local DEFAULT_SOUND     = "Reward.Fireworks"  -- resolves to SoundService.SFX.Reward.Fireworks
local GRAVITY           = 1600  -- pixels/s²  (screen-scale) — high so pieces fall snappily
local BASE_SPEED_MIN    = 250   -- horizontal spread velocity range
local BASE_SPEED_MAX    = 600
local INITIAL_VY_MIN    = 80    -- pixels/s DOWNWARD (positive) — pieces drop immediately
local INITIAL_VY_MAX    = 260   -- gives a snappy onset; gravity does the rest
local SPIN_SPEED_MIN    = 90    -- deg/s
local SPIN_SPEED_MAX    = 360

local BASE_COLORS = {
	Color3.fromRGB(255, 80,  80),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(60,  200, 100),
	Color3.fromRGB(60,  120, 255),
	Color3.fromRGB(200, 60,  255),
	Color3.fromRGB(255, 140, 40),
}

local SHAPES = { "Square", "Circle", "Diamond", "Triangle" }

-- Global state for the shared ScreenGui lifetime management.
local _confettiGui: ScreenGui?  = nil
local _activePieces: number     = 0
local _activeEmitters: number   = 0

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

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function getOrCreateGui(): ScreenGui
	if _confettiGui and _confettiGui.Parent then
		return _confettiGui
	end

	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/Confetti] getOrCreateGui: LocalPlayer missing — cannot emit")
		error("no LocalPlayer")
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/Confetti] getOrCreateGui: PlayerGui missing — skipping emit")
		error("no PlayerGui")
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ConfettiGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	_confettiGui = gui
	return gui
end

local function tryDestroyGui()
	if _activePieces <= 0 and _activeEmitters <= 0 then
		if _confettiGui and _confettiGui.Parent then
			_confettiGui:Destroy()
		end
		_confettiGui = nil
	end
end

local function makeShape(shape: string, parent: Frame, color: Color3)
	if shape == "Circle" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = parent
	elseif shape == "Diamond" then
		parent.Rotation = 45
	elseif shape == "Triangle" then
		-- Approximate triangle with heavy UICorner on one side only (best-effort).
		parent.Rotation = 45
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.1, 0)
		corner.Parent = parent
	end
	-- Square needs no decorator.
	parent.BackgroundColor3 = color
	parent.BackgroundTransparency = 0
end

local function spawnPiece(gui: ScreenGui, spawnPos: UDim2?, j: any)
	local size = math.random(22, 40)  -- bigger pieces — old 8..16 was nearly invisible on 1080p
	local piece = Instance.new("Frame")
	piece.Size = UDim2.fromOffset(size, size)
	piece.BorderSizePixel = 0
	piece.BackgroundTransparency = 0
	piece.ZIndex = 10
	piece.AnchorPoint = Vector2.new(0.5, 0.5)

	local color = BASE_COLORS[math.random(1, #BASE_COLORS)]
	local shape = SHAPES[math.random(1, #SHAPES)]
	makeShape(shape, piece, color)

	-- Starting position: randomised top strip or explicit spawn pos.
	-- startY at 0.02 — pieces appear just at the top edge of the visible area
	-- so they're VISIBLE the instant they spawn. Previous -0.05 + upward velocity
	-- caused pieces to shoot off-screen first, producing a ~0.5-1s perceived delay.
	local startX = spawnPos and spawnPos.X.Scale or math.random()
	local startY = spawnPos and spawnPos.Y.Scale or 0.02
	piece.Position = UDim2.fromScale(startX, startY)
	piece.Parent = gui

	-- Physics state (captured into locals — architecture.md § Capture state).
	-- vy is DOWNWARD (positive) so pieces start falling immediately. Combined with
	-- the high GRAVITY they reach the bottom in <1.5s — feels responsive.
	local vx = (math.random() - 0.5) * 2 * (BASE_SPEED_MAX - BASE_SPEED_MIN) + BASE_SPEED_MIN * (math.random() < 0.5 and -1 or 1)
	local vy = INITIAL_VY_MIN + math.random() * (INITIAL_VY_MAX - INITIAL_VY_MIN)
	local spin = (math.random() * (SPIN_SPEED_MAX - SPIN_SPEED_MIN) + SPIN_SPEED_MIN) * (math.random() < 0.5 and -1 or 1)
	local rotation = 0

	-- Use viewport size to convert from scale to px for velocity application.
	-- We read Camera.ViewportSize once per piece spawn (cheap).
	local camera = workspace.CurrentCamera
	local vpX = camera and camera.ViewportSize.X or 1920
	local vpY = camera and camera.ViewportSize.Y or 1080
	local posX = startX * vpX  -- px
	local posY = startY * vpY  -- px

	_activePieces += 1

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		vy = vy + GRAVITY * dt
		posX = posX + vx * dt
		posY = posY + vy * dt
		rotation = rotation + spin * dt

		piece.Position = UDim2.fromScale(posX / vpX, posY / vpY)
		piece.Rotation = rotation

		-- Destroy once below visible area (1.3 gives a generous offscreen buffer).
		if (posY / vpY) > 1.3 then
			conn:Disconnect()
			j:Remove(piece)
			piece:Destroy()
			_activePieces -= 1
			tryDestroyGui()
		end
	end)

	-- Track connection so Janitor can clean it on forced teardown.
	-- Index by the piece Instance itself (unique per call) — tostring(piece)
	-- returns "Frame" for every Instance.new("Frame") so a string key collided
	-- across pieces and overwrote earlier slots (silently disconnecting them).
	j:Add(conn, "Disconnect", piece)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

export type ConfettiOpts = {
	amount:   number?,
	spawnPos: UDim2?,
	sound:    any?,    -- nil = default sound; Confetti.NoSound = suppress
}

--[[
	Fire a confetti burst.
	  amount:   how many pieces (default 250).
	  spawnPos: UDim2 scale-based origin; nil = randomised top strip.
	  sound:    sound name string, nil = default, Confetti.NoSound = muted.
]]
function Confetti.Emit(opts: ConfettiOpts?)
	local o = opts or {}
	local amount   = o.amount   or DEFAULT_AMOUNT
	local spawnPos = o.spawnPos
	local soundKey = o.sound

	task.spawn(function()
		-- Get or create the shared gui.
		local ok, gui = pcall(getOrCreateGui)
		if not ok or not gui then
			warn("[UIAnimator/Confetti] Emit: could not obtain ConfettiGui — aborting")
			return
		end

		_activeEmitters += 1

		-- Play sound unless sentinel suppression is active.
		if soundKey ~= Confetti.NoSound then
			local name = (typeof(soundKey) == "string") and soundKey or DEFAULT_SOUND
			local ctrl = getSoundController()
			if ctrl then
				local playOk, playErr = pcall(function()
					ctrl:Play(name)
				end)
				if not playOk then
					warn("[UIAnimator/Confetti] sound play failed:", playErr)
				end
			end
		end

		-- One Janitor per emit burst owns all piece RenderStepped connections.
		local j = Janitor.new()

		-- Spawn the burst all at once for an instant explosion (no stagger).
		-- Yield once every 60 pieces ONLY to avoid hitching the frame on huge
		-- amounts; the wait is a single frame (task.wait() ~= 1/60s) so the
		-- whole burst still lands within 1-2 frames for typical amounts.
		for i = 1, amount do
			spawnPiece(gui, spawnPos, j)
			if i % 60 == 0 then
				task.wait()
			end
		end

		_activeEmitters -= 1
		tryDestroyGui()

		-- DO NOT j:Destroy() here. Spawning takes ~0.8s but pieces stay in the
		-- air for several seconds after that. Destroying the Janitor mid-flight
		-- would disconnect every active RenderStepped and freeze pieces where
		-- they sit. Each piece self-removes from j on Y > 1.3; the Janitor
		-- itself is a local that gets GC'd once the closure returns.
	end)
end

return Confetti
