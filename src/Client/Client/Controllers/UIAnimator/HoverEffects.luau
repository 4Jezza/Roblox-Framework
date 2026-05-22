--!strict
--[[
	HoverEffects
	------------
	Wires hover + press animations, plus UI sound feedback, onto GuiButtons.

	Two sources feed buttons into wireButton:
	  1. Boot discovery: every GuiButton already in PlayerGui at KnitStart.
	  2. DescendantAdded listener: any GuiButton that appears later at runtime.

	Opt-out: tag a button with CollectionService tag "NoAutoButton" to skip
	auto-wiring (use for slider grips, playground-internal noise, etc.).

	The legacy CollectionService "Animatable" tag wiring is preserved so
	non-PlayerGui buttons (generated ScreenGuis, world-space GUIs) can still
	be wired via HoverEffects.WireButton or by tagging.

	Twinkle.SetButtonStyle is the unconditional rewire path — never guard with
	_animatableTagged (S3 anti-pattern). SetButtonStyle re-fires every time so
	re-calling it on an already-wired button is intentional and correct.

	Per api-reference.md § 6.1 Twinkle UIAnimator — SetButtonStyle signature.
	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" for all signal
	    connections added to Janitor (required for non-Instance objects).
	Per CLAUDE.md rule_7 — no raw TweenService for UI.
	Per CLAUDE.md rule_8 — defensive logging on every failable lookup.

	Sound:
	  SoundController:Play("UI.Hover")  on MouseEnter
	  SoundController:Play("UI.Click")  on MouseButton1Click
	  Lazy-loaded via Knit.GetController (same pattern as Confetti.luau).
	  pcall-wrapped so nil SoundController during early boot never crashes.
]]

local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")
local Knit              = require(game.ReplicatedStorage.Packages.Knit)

-- Twinkle: script = HoverEffects → .Parent = UIAnimator folder
-- → .Parent.Parent = Controllers → .Parent.Parent.Parent = Client (Packages/)
local Twinkle = require(script.Parent.Parent.Parent.Packages.UIAnimator)
local Janitor  = require(game.ReplicatedStorage.Packages.Janitor)

local HoverEffects = {}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- [button] -> Janitor (one per wired button)
local _wiredButtons: { [GuiButton]: any } = {}

-- Module-scope janitor for the PlayerGui.DescendantAdded/Removing + CS signals.
local _moduleJanitor = Janitor.new()

-- Lazy SoundController getter — same pattern as Confetti.luau.
-- Cached on first successful resolution so Knit.GetController is not hit every event.
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

local function unwireButton(button: GuiButton)
	local j = _wiredButtons[button]
	if j then
		j:Destroy()
		_wiredButtons[button] = nil
	end
end

-- Wire Twinkle hover/press + sound events onto a single GuiButton.
local function wireButton(button: GuiButton)
	-- Already wired — skip (idempotency guard).
	if _wiredButtons[button] then return end

	-- Opt-out: "NoAutoButton" tag skips auto-wiring (escape hatch per spec).
	if CollectionService:HasTag(button, "NoAutoButton") then
		print("[UIAnimator/HoverEffects] skipping NoAutoButton:", button:GetFullName())
		return
	end

	local j = Janitor.new()
	_wiredButtons[button] = j

	-- Twinkle wires its own hover/press Trove internally.
	-- Default style: Grow + Shrink (quiet, consistent — S3 "everything else").
	Twinkle.SetButtonStyle(button, {
		hoverType = "Grow",
		pressType = "Shrink",
	})

	-- UI.Hover sound on MouseEnter.
	-- pcall guard: SoundController may be nil during early boot.
	j:Add(button.MouseEnter:Connect(function()
		local ok, err = pcall(function()
			local ctrl = getSoundController()
			if ctrl then ctrl:Play("UI.Hover") end
		end)
		if not ok then
			warn("[UIAnimator/HoverEffects] UI.Hover play error:", err)
		end
	end), "Disconnect")

	-- UI.Click sound on MouseButton1Click.
	-- Using Click (not Down) so released-outside-button does not fire.
	j:Add(button.MouseButton1Click:Connect(function()
		local ok, err = pcall(function()
			local ctrl = getSoundController()
			if ctrl then ctrl:Play("UI.Click") end
		end)
		if not ok then
			warn("[UIAnimator/HoverEffects] UI.Click play error:", err)
		end
	end), "Disconnect")

	-- Auto-cleanup: when the button is destroyed, destroy its per-button janitor
	-- and remove it from the map. We use AncestryChanged because LinkToInstance
	-- does not fire on reparent-to-nil in all situations.
	j:Add(button.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			-- Cannot call j:Destroy() here (would recurse into its own destructor
			-- while it is already cleaning up in Janitor). Use unwireButton which
			-- is safe to call from inside a callback because it only destroys the
			-- Janitor once and clears the map.
			unwireButton(button)
		end
	end), "Disconnect")

	-- Additionally link to the instance for Roblox-managed cleanup on Destroy.
	j:LinkToInstance(button)

	-- On janitor teardown, purge map entry (covers non-AncestryChanged paths).
	j:Add(function()
		_wiredButtons[button] = nil
	end, true)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Called by UIAnimator/init.luau:KnitStart.
function HoverEffects.Start()
	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/HoverEffects] Start: LocalPlayer missing — boot discovery skipped")
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/HoverEffects] Start: PlayerGui missing — boot discovery skipped")
		return
	end

	-- 1. One-shot walk: wire every GuiButton already in PlayerGui.
	for _, desc in playerGui:GetDescendants() do
		if desc:IsA("GuiButton") then
			wireButton(desc :: GuiButton)
		end
	end

	-- 2. Watch for new GuiButtons added at runtime (dynamically created frames,
	--    cloned templates, late-loaded ScreenGuis, etc.).
	_moduleJanitor:Add(playerGui.DescendantAdded:Connect(function(desc)
		if desc:IsA("GuiButton") then
			wireButton(desc :: GuiButton)
		end
	end), "Disconnect")

	-- 3. When a GuiButton is removed from PlayerGui, clean up its per-button janitor.
	_moduleJanitor:Add(playerGui.DescendantRemoving:Connect(function(desc)
		if desc:IsA("GuiButton") then
			local btn = desc :: GuiButton
			if _wiredButtons[btn] then
				unwireButton(btn)
			end
		end
	end), "Disconnect")

	-- Legacy: wire buttons tagged with "Animatable" that may NOT be under PlayerGui
	-- (e.g., world-space GUIs, generated ScreenGuis outside the normal tree).
	for _, instance in CollectionService:GetTagged("Animatable") do
		if instance:IsA("GuiButton") then
			wireButton(instance :: GuiButton)
		end
	end

	_moduleJanitor:Add(
		CollectionService:GetInstanceAddedSignal("Animatable"):Connect(function(instance)
			if instance:IsA("GuiButton") then
				wireButton(instance :: GuiButton)
			end
		end),
		"Disconnect"
	)

	_moduleJanitor:Add(
		CollectionService:GetInstanceRemovedSignal("Animatable"):Connect(function(instance)
			if instance:IsA("GuiButton") then
				unwireButton(instance :: GuiButton)
			end
		end),
		"Disconnect"
	)

	-- Safety: clean all button janitors when the local player leaves.
	_moduleJanitor:Add(player.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for button in _wiredButtons do
				unwireButton(button)
			end
			_moduleJanitor:Cleanup()
		end
	end), "Disconnect")
end

-- Exposed so UIAnimator/init.luau:TagButton can wire a button that is not
-- under PlayerGui and was never CS-tagged (e.g., custom viewport frames).
function HoverEffects.WireButton(button: GuiButton)
	if not button then
		warn("[UIAnimator/HoverEffects] WireButton called with nil")
		return
	end
	wireButton(button)
end

return HoverEffects
