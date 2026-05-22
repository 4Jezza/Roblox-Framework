--!strict
--[[
	ShiningButton
	-------------
	Applies a persistent, always-on swipe-shine to every GuiButton tagged with
	"ShiningButton" via CollectionService. Each tagged button gets one permanent
	ShineOverlay Frame (parented to the button) that lives for the entire time
	the tag is active — the overlay is never removed between cycles.

	Cycle timing (1.5 s total period):
	  - Sweep duration : 0.4 s (fast diagonal pass via TweenService UIGradient offset)
	  - Idle wait      : 1.1 s (gradient reset to off-screen left, overlay remains)
	  - Total period   : 1.5 s

	Overlay shape:
	  - Frame "ShineOverlay", Size (1,0,1,0), ZIndex = button.ZIndex + 5.
	  - Active = false so clicks pass through to the button.
	  - UICorner cloned from the button (if present) so shine respects rounded corners.
	  - UIGradient: white Color, 5-keypoint Transparency (peak 0.35 at centre band),
	    Rotation 20°, Offset animated from (-1,0) to (1,0) per sweep.

	Why TweenService (rule_7 exemption documented inline):
	  The sweep is a one-shot fire-and-forget tween on a UIGradient.Offset property
	  once per cycle, on a temporary (overlay-owned) UIGradient. This falls under the
	  documented rule_7 exemption: "one-shot fire-and-forget tweens on temporary
	  instances". A Heartbeat Spring loop would be wasteful for a fixed-duration
	  linear property slide where no spring dynamics are needed.

	The loop exits automatically when the overlay or button is destroyed — no explicit
	Heartbeat connection; purely task.spawn-driven (janitor-lifecycle rule).

	Public API:
	  ShiningButton.Tag(button)    -- manually tag a button (no CS required)
	  ShiningButton.Untag(button)  -- stop shimmer + clean up the button
	  ShiningButton.Start()        -- called from Presets.Start (KnitStart)

	Internals:
	  One Janitor per tagged button (stored in _buttonJanitors).
	  A running-flag (not coroutine) governs the pulse loop so cleanup is
	  synchronous and race-free.

	Per conventions.md § Module file structure.
	Per api-reference.md § 3.1 Janitor.
	Per CLAUDE.md rule_7 (TweenService exemption), rule_8 (defensive logging).
	Per architecture.md § Critical Bans (capture state before task.spawn).
]]

local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")

local Janitor = require(game.ReplicatedStorage.Packages.Janitor)

local ShiningButton = {}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local TAG  = "ShiningButton"

-- Cycle timing: 0.4 s sweep + 1.1 s idle = 1.5 s total period.
local SWEEP = 0.4  -- TweenService duration for one gradient pass
local IDLE  = 1.1  -- wait between sweeps (overlay stays parented, gradient at rest)

-- [GuiButton] → Janitor
local _buttonJanitors: { [GuiButton]: any } = {}

-- Module-scope janitor for the CollectionService signal connections.
local _moduleJanitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function teardownButton(button: GuiButton)
	local j = _buttonJanitors[button]
	if j then
		j:Destroy()
		_buttonJanitors[button] = nil
	end
end

local function wireButton(button: GuiButton)
	if not button:IsA("GuiButton") then
		warn("[UIAnimator/ShiningButton] wireButton: not a GuiButton —", button:GetFullName())
		return
	end

	-- Idempotent: tear down any prior wiring first.
	teardownButton(button)

	local buttonJanitor = Janitor.new()
	_buttonJanitors[button] = buttonJanitor

	-- -----------------------------------------------------------------------
	-- Build the persistent ShineOverlay (Brainrot pattern).
	-- The overlay lives for the full tag lifetime; it is never removed between
	-- cycles — the UIGradient Offset is reset to (-1, 0) between sweeps instead.
	-- -----------------------------------------------------------------------

	local shineOverlay = Instance.new("Frame")
	shineOverlay.Name              = "ShineOverlay"
	shineOverlay.Size              = UDim2.new(1, 0, 1, 0)
	shineOverlay.Position          = UDim2.fromScale(0, 0)
	shineOverlay.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
	shineOverlay.BackgroundTransparency = 0  -- gradient controls all visibility
	shineOverlay.BorderSizePixel   = 0
	shineOverlay.ZIndex            = button.ZIndex + 5
	shineOverlay.Active            = false  -- clicks pass through to the button
	shineOverlay.Parent            = button

	-- Clone UICorner so the shine respects rounded buttons.
	local btnCorner = button:FindFirstChildOfClass("UICorner")
	if btnCorner then
		local shineCorner = btnCorner:Clone()
		shineCorner.Parent = shineOverlay
	end

	-- Narrow opaque band at the centre, fully transparent everywhere else.
	-- Peak transparency 0.35 = the band is ~65% opaque white at its brightest,
	-- which reads as a clear shine without washing out the button colour.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    1),
		NumberSequenceKeypoint.new(0.40, 1),
		NumberSequenceKeypoint.new(0.50, 0.35),
		NumberSequenceKeypoint.new(0.60, 1),
		NumberSequenceKeypoint.new(1,    1),
	})
	gradient.Rotation = 20               -- diagonal sweep angle
	gradient.Offset   = Vector2.new(-1, 0)  -- start off-screen left
	gradient.Parent   = shineOverlay

	-- Register overlay with the button's janitor so cleanup on untag destroys it.
	buttonJanitor:Add(shineOverlay, "Destroy", "shineOverlay")

	-- Running flag — set false on janitor cleanup to stop the pulse loop.
	local running = true
	buttonJanitor:Add(function()
		running = false
	end, true, "shineLoopCancel")

	buttonJanitor:LinkToInstance(button)
	buttonJanitor:Add(function()
		_buttonJanitors[button] = nil
	end, true)

	-- Capture state into locals before task.spawn (architecture.md § Critical Bans).
	local capturedBtn      = button
	local capturedOverlay  = shineOverlay
	local capturedGradient = gradient

	-- -----------------------------------------------------------------------
	-- Sweep loop.
	-- One TweenInfo created outside the loop; reused each iteration so no
	-- allocation on each cycle (identical to Brainrot ShineEffect pattern).
	-- rule_7 exemption: one-shot fire-and-forget tween on a UIGradient.Offset
	-- property, per cycle. Not a persistent TweenService usage — the tween
	-- completes in 0.4 s and is replaced each cycle; no Heartbeat polling needed.
	-- -----------------------------------------------------------------------
	local tweenInfo = TweenInfo.new(SWEEP, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	task.spawn(function()
		while running and capturedOverlay.Parent and capturedBtn.Parent do
			-- rule_7 exemption: fire-and-forget UIGradient Offset tween (one per cycle).
			local sweep = TweenService:Create(capturedGradient, tweenInfo, { Offset = Vector2.new(1, 0) })
			sweep:Play()
			task.wait(SWEEP)

			-- Reset offset instantly so the next sweep starts from the left.
			if capturedGradient.Parent then
				capturedGradient.Offset = Vector2.new(-1, 0)
			end

			task.wait(IDLE)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Manually tag a button for the shine effect. Equivalent to adding the
	"ShiningButton" CS tag but callable at runtime without CS access.
]]
function ShiningButton.Tag(button: GuiButton)
	if not button then
		warn("[UIAnimator/ShiningButton] Tag called with nil button")
		return
	end
	wireButton(button)
end

--[[
	Stop and remove the shine effect from a button.
]]
function ShiningButton.Untag(button: GuiButton)
	if not button then
		warn("[UIAnimator/ShiningButton] Untag called with nil button")
		return
	end
	teardownButton(button)
end

--[[
	Boot the CollectionService watcher. Called once from Presets.Start (KnitStart).
]]
function ShiningButton.Start()
	-- Wire already-tagged buttons.
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("GuiButton") then
			wireButton(inst :: GuiButton)
		end
	end

	-- Watch for new tags.
	_moduleJanitor:Add(
		CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
			if inst:IsA("GuiButton") then
				wireButton(inst :: GuiButton)
			end
		end)
	)

	-- Watch for tag removal.
	_moduleJanitor:Add(
		CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
			if inst:IsA("GuiButton") then
				teardownButton(inst :: GuiButton)
			end
		end)
	)
end

return ShiningButton
