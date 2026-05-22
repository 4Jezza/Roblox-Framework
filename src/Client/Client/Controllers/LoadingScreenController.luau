--[[
	LoadingScreenController
	-----------------------
	Drives the LoadingScreen ScreenGui animation lifecycle. Replaces the
	inline Animation LocalScript that ships inside the ScreenGui.

	On KnitStart:
	  1. Sets PlayerStateController state to "Loading".
	  2. screen.Enabled = true immediately (guards Studio drift from project.json).
	  3. Disables any inline Animation LocalScript to prevent animation conflicts.
	  4. Ensures Background is fully opaque (BackgroundTransparency = 0, no fade-in).
	  5. Springs Container UIScale 0.85 -> 1.0 (smoothTime 0.12 -- snappy pop).
	  6. Starts a dot-JUMPING loop: each dot's UIScale follows a clamped-sine wave
	     (peak 1.15, rest 1.0, period 1.0s, rolling phase offsets across all 6
	     dots). Each dot also hops upward up to ~6px from its captured base
	     Position on the same wave for a subtle "jump" feel.
	     A per-dot popMultipliers table is also initialised here; the jump loop
	     multiplies its base jump scale by the dot's current pop multiplier so
	     the Dismiss white-fill phase can layer a concurrent pop spring without
	     fighting the jump loop.
	  7. Starts an icon rotation oscillation: Container/PlaceImage (fallback
	     Container/ImageLabel) rotates +-8 degrees at period 1.6s via sine wave.
	  8. Auto-dismisses after a fixed 3-second hold. PlayerData is intentionally
	     not awaited here -- the 3s loop duration is the only gate.

	On :Dismiss(holdSeconds?):
	  1. Waits `holdSeconds` (default 0; KnitStart auto-dismiss passes 0 after 3s).
	  2. Does NOT remove dotsConn / dotsReset -- dots keep jumping through the
	     entire white-fill phase. rotateConn and scaleConn also continue running.
	     The final _janitor:Cleanup() at the end of Dismiss reaps everything.
	  3. Sequential white-fill: each dot springs from its original BackgroundColor3
	     toward white (Color3.fromRGB(255, 255, 255)) with a 1.0s gap between
	     consecutive starts. Spring smoothTime 0.18s (~0.4s settle). Concurrently,
	     a per-dot pop spring (Target=0, Impulse=0.4) enlarges the dot at the
	     moment it begins whitening; the jump loop reads popMultipliers[dot] and
	     multiplies its base scale by the pop multiplier, so both motions coexist.
	  4. 1.0s after the last dot starts -> per-descendant transparency lerp over
	     1.0s fades every GuiObject + UIStroke under the ScreenGui to fully
	     transparent, replacing the former Twinkle Fade call.
	  5. Disable + Destroy screen; set PlayerStateController to "Idle".

	Timing (6 dots, DOT_GAP=1.0s):
	  t=0  : dismiss called; dot 1 starts whitening + popping (dots still bouncing).
	  t=1  : dot 2 starts; ... t=5: dot 6 starts.
	  t=6  : 1.0s trailing wait expires.
	  t=6-7: per-descendant fade (1.0s).
	  t=7  : screen destroyed.
	  From KnitStart auto-dismiss: 3s loop + ~7s dismiss = ~10s total.

	Public API:
	  LoadingScreenController:Dismiss(holdSeconds: number?)
	  LoadingScreenController:IsActive() -> boolean

	Per .claude/reference/architecture.md § Require Paths (Knit, Janitor, Spring).
	Per .claude/reference/api-reference.md § 6.1 UIAnimator (Twinkle), § 5.1 Spring.
	Per .claude/reference/api-reference.md § 3.1 Janitor -- explicit "Disconnect" for Heartbeat.
	Per docs/conventions.md § Module file structure.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Janitor    = require(ReplicatedStorage.Packages.Janitor)
local Spring     = require(ReplicatedStorage.Packages.Spring)

local LoadingScreenController = Knit.CreateController {
	Name = "LoadingScreenController",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local TWO_PI    = math.pi * 2
local DOT_COUNT = 6
local MAX_DT    = 1 / 30  -- clamp against lag-spike overshoot in Spring updates

-- Dot jump animation constants.
local DOT_PERIOD       = 1.0  -- full wave cycle in seconds (slower, more subtle)
local DOT_PEAK         = 1.15 -- UIScale.Scale at jump peak (subtle enlargement)
local DOT_REST         = 1.0  -- UIScale.Scale at rest
local DOT_JUMP_PIXELS  = 6    -- max upward Y-offset (pixels) at wave peak

-- Icon rotation oscillation constants.
local ROT_PERIOD    = 1.6   -- full oscillation cycle in seconds
local ROT_AMPLITUDE = 8     -- degrees either side

-- Spring smoothTime for the container scale-in.
-- 0.12 = snappy pop per S4 smoothTime reference table.
local SCALE_SMOOTH_TIME = 0.12

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Lazy getter for PlayerStateController (same pattern as UIClient.getPlayerState).
-- Returns nil during KnitInit if the controller hasn't resolved yet.
local _playerState = nil
local function getPlayerState()
	if _playerState then
		return _playerState
	end
	local ok, ctrl = pcall(function()
		return Knit.GetController("PlayerStateController")
	end)
	if ok and ctrl then
		_playerState = ctrl
		return ctrl
	end
	return nil
end

-- Resolve the LoadingScreen ScreenGui from PlayerGui.
-- Returns nil if not found and emits a rule_8-compliant warning.
local function resolveLoadingScreen(): ScreenGui?
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		warn("[LoadingScreenController] missing LocalPlayer at resolveLoadingScreen — skipping")
		return nil
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		warn("[LoadingScreenController] missing PlayerGui after 10s — skipping")
		return nil
	end
	local screen = playerGui:FindFirstChild("LoadingScreen") :: ScreenGui?
	if not screen then
		warn("[LoadingScreenController] StarterGui.LoadingScreen not present — skipping")
	end
	return screen
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function LoadingScreenController:KnitInit()
	self._janitor = Janitor.new()
	self._active  = false
end

function LoadingScreenController:KnitStart()
	local screen = resolveLoadingScreen()
	if not screen then
		return
	end

	-- Step 1: transition state machine to Loading.
	local ps = getPlayerState()
	if ps then
		ps:Set("Loading")
	else
		warn("[LoadingScreenController] PlayerStateController unavailable at KnitStart — Loading state not set")
	end

	-- Step 2: ensure the ScreenGui is visible immediately.
	-- project.json now defaults Enabled=true, but this guards against Studio drift.
	screen.Enabled = true

	self._active = true
	self._screen = screen

	-- Step 3: disable any inline Animation LocalScript to prevent conflicts.
	local oldAnim = screen:FindFirstChild("Animation")
	if oldAnim and oldAnim:IsA("LocalScript") then
		oldAnim.Disabled = true
	end

	-- Resolve key instances (nil-guard per rule_8).
	local background = screen:FindFirstChild("Background") :: Frame?
	if not background then
		warn("[LoadingScreenController] missing Background at LoadingScreen.Background — animation aborted")
		return
	end
	local container = background:FindFirstChild("Container") :: Frame?
	if not container then
		warn("[LoadingScreenController] missing Container at LoadingScreen.Background.Container — animation aborted")
		return
	end

	-- Also disable any LocalScript embedded under ImageLabel.
	local imageLabel = container:FindFirstChild("ImageLabel")
	if imageLabel then
		for _, child in imageLabel:GetChildren() do
			if child:IsA("LocalScript") then
				child.Disabled = true
			end
		end
	end

	local dotsFolder = container:FindFirstChild("Dots")
	if not dotsFolder then
		warn("[LoadingScreenController] missing Dots folder at LoadingScreen.Background.Container.Dots — dots loop skipped")
	end

	-- Step 4: background is immediately fully opaque (no fade-in — must be
	-- visible from frame 0). Do NOT call UIAnimator.Fade here.
	background.BackgroundTransparency = 0

	-- Step 5: spring Container scale from 0.85 -> 1.0.
	-- Create UIScale child if absent so the spring has an anchor.
	local uiScale = container:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 0.85
		uiScale.Parent = container
		self._janitor:Add(uiScale, "Destroy", "uiScale")
	else
		uiScale.Scale = 0.85
	end

	local scaleSpring = Spring.new(0.85, SCALE_SMOOTH_TIME)
	scaleSpring.Target = 1.0

	-- Capture locals before async boundary (architecture.md Critical Bans).
	local capturedScale  = uiScale
	local capturedSpring = scaleSpring
	local scaleConn
	scaleConn = RunService.Heartbeat:Connect(function(dt)
		local clamped = math.min(dt, MAX_DT)
		local current = capturedSpring:Update(clamped)
		capturedScale.Scale = current
		if math.abs(current - capturedSpring.Target) < 0.001 then
			capturedScale.Scale = 1.0
			scaleConn:Disconnect()
			scaleConn = nil
		end
	end)
	-- Register cleanup under a named key so Dismiss can remove it explicitly.
	-- Explicit "Disconnect" per api-reference.md § 3.1 Janitor gotchas.
	self._janitor:Add(function()
		if scaleConn then
			scaleConn:Disconnect()
			scaleConn = nil
		end
	end, true, "scaleConn")

	-- Step 6: dot-JUMPING animation.
	-- Each dot[i] gets a UIScale (created if missing). A clamped-sine wave drives
	-- Scale (subtle): positive half of sin maps to [DOT_REST, DOT_PEAK], negative
	-- half clamps to DOT_REST so dots "rest" between jumps. The same wave also
	-- offsets the dot's Y position upward up to DOT_JUMP_PIXELS for a small
	-- "hop". basePositions captures the rest Position of each dot ONCE at start
	-- (architecture.md Critical Bans — capture locals before async boundary) so
	-- we can both drive the offset and restore the resting layout on cleanup.
	-- Phase offsets produce a rolling wave across the row.
	--
	-- popMultipliers: per-dot multiplicative scale factor defaulting to 1.0.
	-- The jump loop multiplies its base jump scale by popMultipliers[dot] so
	-- that the white-fill pop springs in :Dismiss can enlarge a dot concurrently
	-- without overwriting or fighting the jump oscillation.
	local popMultipliers: { [Instance]: number } = {}
	self._popMultipliers = popMultipliers

	if dotsFolder then
		local dots       = {} :: { Frame }
		local dotScales  = {} :: { UIScale }
		local basePositions = {} :: { [Frame]: UDim2 }

		for i = 1, DOT_COUNT do
			local dot = dotsFolder:FindFirstChild(tostring(i)) :: Frame?
			if dot then
				dots[i] = dot
				basePositions[dot] = dot.Position
				popMultipliers[dot] = 1.0  -- initialise pop multiplier to neutral
				local ds = dot:FindFirstChildOfClass("UIScale")
				if not ds then
					ds = Instance.new("UIScale")
					ds.Scale = DOT_REST
					ds.Parent = dot
					self._janitor:Add(ds, "Destroy", "dotScale_" .. i)
				end
				dotScales[i] = ds
			else
				warn("[LoadingScreenController] missing dot " .. i .. " at Dots/" .. i .. " — wave will skip it")
			end
		end

		local elapsed = 0
		local dotsConn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			for i = 1, DOT_COUNT do
				local ds  = dotScales[i]
				local dot = dots[i]
				if ds and dot then
					local phase = (i - 1) * (TWO_PI / DOT_COUNT)
					-- Clamp negative half of sine to 0 so dots rest between jumps.
					local wave  = math.max(0, math.sin(elapsed * (TWO_PI / DOT_PERIOD) - phase))
					-- Multiply base jump scale by the dot's current pop multiplier.
					-- popMultipliers[dot] is 1.0 normally; Dismiss white-fill springs
					-- it toward ~1.4 then back to 1.0 for a concurrent pop effect.
					local jumpScale = DOT_REST + wave * (DOT_PEAK - DOT_REST)
					local popScale  = popMultipliers[dot] or 1.0
					ds.Scale = jumpScale * popScale
					local basePos = basePositions[dot]
					if basePos then
						-- Negative Y = upward in GUI space. Round to whole pixels
						-- so the dot doesn't jitter on sub-pixel offsets.
						dot.Position = basePos + UDim2.fromOffset(0, -math.floor(wave * DOT_JUMP_PIXELS + 0.5))
					end
				end
			end
		end)
		-- Explicit "Disconnect" per api-reference.md § 3.1 Janitor gotchas.
		self._janitor:Add(dotsConn, "Disconnect", "dotsConn")

		-- Janitor restore: snap each dot back to its captured base Position
		-- (and UIScale back to rest) when the janitor finally tears down.
		-- true -> call as function (api-reference.md § 3.1).
		self._janitor:Add(function()
			for dot, base in basePositions do
				if dot and dot.Parent then
					dot.Position = base
				end
				local s = dot:FindFirstChildOfClass("UIScale")
				if s then
					s.Scale = DOT_REST
				end
			end
		end, true, "dotsReset")
	end

	-- Step 7: icon side-to-side rotation oscillation.
	-- Try Container/PlaceImage first; fall back to Container/ImageLabel.
	local imageInstance = container:FindFirstChild("PlaceImage")
	if not imageInstance then
		imageInstance = container:FindFirstChild("ImageLabel")
	end
	if imageInstance then
		local rotElapsed = 0
		local capturedImg = imageInstance
		local rotateConn = RunService.Heartbeat:Connect(function(dt)
			rotElapsed += dt
			capturedImg.Rotation = math.sin(rotElapsed * (TWO_PI / ROT_PERIOD)) * ROT_AMPLITUDE
		end)
		-- Explicit "Disconnect" per api-reference.md § 3.1 Janitor gotchas.
		self._janitor:Add(rotateConn, "Disconnect", "rotateConn")
	else
		warn("[LoadingScreenController] no PlaceImage or ImageLabel found in Container — rotation loop skipped")
	end

	print("[LoadingScreenController] showing loading screen — auto-dismiss in 3s")

	-- Step 8: auto-dismiss after a fixed 3-second loop hold.
	-- PlayerData is intentionally NOT awaited -- the 3s duration is the only gate.
	-- Capture state into locals before task.spawn (architecture.md Critical Bans).
	local capturedSelf = self
	task.spawn(function()
		task.wait(3.0)  -- loop the dots for at least 3 seconds before the dismiss sequence
		capturedSelf:Dismiss(0)
	end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	LoadingScreenController:Dismiss(holdSeconds?)
	    Plays the exit animation and tears down the loading screen.
	    holdSeconds: additional minimum wait before dismissing (default 0).
	    The auto-dismiss path calls this with 0 after its own 3s loop hold.
	    Safe to call from KnitStart of any other controller via task.spawn.
]]
function LoadingScreenController:Dismiss(holdSeconds: number?)
	if not self._active then
		return
	end
	self._active = false

	local hold = holdSeconds or 0
	if hold > 0 then
		task.wait(hold)
	end

	-- Change 1: do NOT remove dotsConn / dotsReset here. The jump loop keeps
	-- driving dot Position + UIScale (via popMultipliers too) through the entire
	-- white-fill phase. rotateConn and scaleConn were already left running.
	-- Final _janitor:Cleanup() at the end of this function reaps everything.

	local screen = self._screen
	if not screen then
		self._janitor:Cleanup()
		return
	end

	local background = screen:FindFirstChild("Background") :: Frame?
	local container  = background and background:FindFirstChild("Container") :: Frame?
	local dotsFolder = container and container:FindFirstChild("Dots")

	-- Capture popMultipliers reference before async boundaries.
	local capturedPopMultipliers = self._popMultipliers

	if dotsFolder then
		-- Spawn one whitening thread per dot, each delayed by (i-1) seconds.
		-- Spring smoothTime 0.18 -> ~0.4s settle (per S4 "snappy pop" range).
		-- Per api-reference.md § 5.1 Spring API: Spring.new(initial, smoothTime).
		local DOT_GAP    = 1.0   -- seconds between consecutive dot starts
		local DOT_SMOOTH = 0.18  -- Spring smoothTime for the color lerp

		-- Change 2: pop spring constants. One impulse kick per dot at whitening start.
		local POP_PEAK   = 0.4   -- additional multiplier above 1.0 at impulse moment
		local POP_SMOOTH = 0.18  -- ~0.4s settle (matches the color spring feel)

		for i = 1, DOT_COUNT do
			local dot = dotsFolder:FindFirstChild(tostring(i))
			if not (dot and dot:IsA("Frame")) then
				warn("[LoadingScreenController] missing dot " .. i .. " at Dots/" .. i .. " during white-fill — skipping")
				continue
			end

			-- Capture every animatable property BEFORE the async boundary
			-- (architecture.md Critical Bans). Dots are outlined ring frames --
			-- BackgroundTransparency = 1 with the visible ring drawn by UIStroke --
			-- so we must drive transparency, fill color, AND stroke color together
			-- off the same spring `t`, or the white-fill is invisible.
			local capturedDot          = dot
			local capturedColor        = dot.BackgroundColor3
			local capturedTransparency = dot.BackgroundTransparency
			local capturedStroke       = dot:FindFirstChildOfClass("UIStroke")
			local capturedStrokeColor  = capturedStroke and capturedStroke.Color or nil
			local startDelay           = (i - 1) * DOT_GAP

			task.spawn(function()
				if startDelay > 0 then
					task.wait(startDelay)
				end

				-- Color/transparency spring (existing behavior -- keep).
				-- Per api-reference.md § 5.1 Spring: Spring.new(initial, smoothTime).
				local colorSpring = Spring.new(0, DOT_SMOOTH)
				colorSpring.Target = 1

				-- Change 2: pop spring. Target=0 (decays back to no extra scale).
				-- Impulse kicks velocity upward by POP_PEAK so the spring overshoots
				-- positively then damps to 0. The jump loop reads popMultipliers[dot]
				-- and multiplies by (1.0 + popSpring.Current) each Heartbeat.
				-- Per api-reference.md § 5.1 Spring: Spring:Impulse(velocity) adds
				-- to Velocity; this lib is critically damped so there is no natural
				-- overshoot -- the impulse IS the overshoot.
				local popSpring = Spring.new(0, POP_SMOOTH)
				popSpring.Target = 0
				popSpring:Impulse(POP_PEAK)

				local conn
				conn = RunService.Heartbeat:Connect(function(dt)
					local clampedDt = math.min(dt, MAX_DT)

					-- Drive color/transparency/stroke (existing logic -- keep all three).
					local v = colorSpring:Update(clampedDt)
					local t = math.clamp(v, 0, 1)
					capturedDot.BackgroundTransparency = capturedTransparency * (1 - t)
					capturedDot.BackgroundColor3 = capturedColor:Lerp(Color3.fromRGB(255, 255, 255), t)
					if capturedStroke and capturedStrokeColor then
						capturedStroke.Color = capturedStrokeColor:Lerp(Color3.fromRGB(255, 255, 255), t)
					end

					-- Drive the pop multiplier -- current value is read each frame by
					-- the jump Heartbeat loop in KnitStart. 1.0 + p gives a neutral
					-- multiplier when p=0 (decayed) and >1.0 at impulse peak.
					local p = popSpring:Update(clampedDt)
					if capturedPopMultipliers then
						capturedPopMultipliers[capturedDot] = 1.0 + p
					end

					-- Settle: both color and pop back near their resting values.
					if math.abs(v - 1) < 0.005 and math.abs(p) < 0.005 then
						capturedDot.BackgroundTransparency = 0
						capturedDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
						if capturedStroke then
							capturedStroke.Color = Color3.fromRGB(255, 255, 255)
						end
						if capturedPopMultipliers then
							capturedPopMultipliers[capturedDot] = 1.0
						end
						conn:Disconnect()
					end
				end)
			end)
		end

		-- Change 3: trailing wait is 1.0s (was 0.5s).
		-- Dot DOT_COUNT starts at (DOT_COUNT - 1) * DOT_GAP seconds from now.
		-- The spring settles in ~0.4s; 1.0s gives visible hold in the all-white state.
		task.wait((DOT_COUNT - 1) * DOT_GAP + 1.0)
	end

	-- Change 4: per-descendant transparency lerp over 1.0s.
	-- Replaces the former UIAnimator.Fade(background, false, 0.3) + spin-wait.
	-- Every GuiObject (BackgroundTransparency, TextTransparency, ImageTransparency)
	-- and every UIStroke (Transparency) under the ScreenGui is lerped from its
	-- current value to fully transparent simultaneously over FADE_DURATION seconds.
	-- Snapshot is taken before the loop so mid-fade mutations don't skew the lerp.
	if screen then
		local FADE_DURATION = 1.0

		type FadeEntry = {
			inst     : Instance,
			startBT  : number?,
			startTT  : number?,
			startIT  : number?,
			startST  : number?,
			isGui    : boolean,
			isText   : boolean,
			isImage  : boolean,
			isStroke : boolean,
		}
		local entries: { FadeEntry } = {}

		for _, desc in screen:GetDescendants() do
			local entry: FadeEntry? = nil
			if desc:IsA("GuiObject") then
				local isText  = desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox")
				local isImage = desc:IsA("ImageLabel") or desc:IsA("ImageButton")
				local startTT: number? = nil
				local startIT: number? = nil
				if isText then
					local asText = desc :: TextLabel
					startTT = asText.TextTransparency
				end
				if isImage then
					local asImage = desc :: ImageLabel
					startIT = asImage.ImageTransparency
				end
				local asGui = desc :: GuiObject
				entry = {
					inst     = desc,
					startBT  = asGui.BackgroundTransparency,
					startTT  = startTT,
					startIT  = startIT,
					startST  = nil,
					isGui    = true,
					isText   = isText,
					isImage  = isImage,
					isStroke = false,
				}
			elseif desc:IsA("UIStroke") then
				local asStroke = desc :: UIStroke
				entry = {
					inst     = desc,
					startBT  = nil,
					startTT  = nil,
					startIT  = nil,
					startST  = asStroke.Transparency,
					isGui    = false,
					isText   = false,
					isImage  = false,
					isStroke = true,
				}
			end
			if entry then
				table.insert(entries, entry)
			end
		end

		local function lerpTransparency(start: number, t: number): number
			return start + (1 - start) * t
		end

		local startClock = os.clock()
		local fadeConn
		-- fadeConn self-disconnects at t=1 -- no janitor registration needed.
		fadeConn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - startClock
			local t = math.clamp(elapsed / FADE_DURATION, 0, 1)
			for _, e in entries do
				if not e.inst.Parent then
					continue
				end
				if e.isStroke then
					local asStroke = e.inst :: UIStroke
					asStroke.Transparency = lerpTransparency(e.startST :: number, t)
				else
					local gui = e.inst :: GuiObject
					if e.startBT then
						gui.BackgroundTransparency = lerpTransparency(e.startBT, t)
					end
					if e.isText and e.startTT then
						local asText = e.inst :: TextLabel
						asText.TextTransparency = lerpTransparency(e.startTT, t)
					end
					if e.isImage and e.startIT then
						local asImage = e.inst :: ImageLabel
						asImage.ImageTransparency = lerpTransparency(e.startIT, t)
					end
				end
			end
			if t >= 1 then
				fadeConn:Disconnect()
			end
		end)

		-- Block until the fade has finished (plus a small buffer for the final
		-- Heartbeat frame to write the t=1 values).
		task.wait(FADE_DURATION + 0.05)
	end

	screen.Enabled = false
	screen:Destroy()
	self._screen = nil

	-- Transition state machine back to Idle.
	local ps = getPlayerState()
	if ps then
		ps:Set("Idle")
	else
		warn("[LoadingScreenController] PlayerStateController unavailable at Dismiss — Idle not set")
	end

	-- Reap everything: dotsConn, dotsReset, rotateConn, scaleConn, uiScale, dotScales.
	self._janitor:Cleanup()
end

--[[
	LoadingScreenController:IsActive() -> boolean
	    Returns true while the loading screen is visible and has not been dismissed.
]]
function LoadingScreenController:IsActive(): boolean
	return self._active == true
end

return LoadingScreenController
