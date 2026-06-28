--!strict
--[==[
	PurchaseEffectsController
	--------------------------
	ScreenGui.Enabled / Frame.Visible lifecycle:

	  Boot          : Purchase.Enabled=false, MonoUI.Visible=false,
	                  BuyTransition.Visible=false
	  PromptPurchase: Purchase.Enabled=true, MonoUI.Visible=true
	                  BuyTransition.Visible=true (direct, no OpenFrame zoom —
	                  entrance IS the shadow fade + Enlargen below)
	                  CO-INCIDENT entrance (same frame):
	                    • Shadow.ImageTransparency snapped to 1, then one-shot tween → 0.5
	                      (Quad Out 0.3s; rule_7 fire-and-forget exemption)
	                    • uianim:Enlargen(Icon) — spring scale 0.6→1.0, smoothTime 0.18
	                    • uianim:Enlargen(Loading) — same
	                  Idle (continuous, stored in _idleJanitor):
	                    • Shadow.UIGradient spins at 90 deg/s (user-requested)
	                    • Icon RotateOscillate (gentle pendulum, [off-script])
	                    • Loading dots cycle (task.wait loop, [off-script])
	  Cancel        : _idleJanitor:Cleanup() stops all idle anims
	                  CO-INCIDENT exit (same frame):
	                    • Shadow.ImageTransparency tween → 1 (Quad Out 0.2s)
	                    • uianim:Shrink(Icon), uianim:Shrink(Loading)
	                  task.wait(0.2) → if not re-opened: MonoUI.Visible=false,
	                  Purchase.Enabled=false
	  Success (PlaySuccess):
	                  Ensure Purchase.Enabled=true + MonoUI.Visible=true + frame.Visible=true
	                  (handles server-gift path with no preceding PromptPurchase)
	                  _idleJanitor:Cleanup() stops idle anims
	                  CO-INCIDENT (same frame): shadow exit tween + Shrink icon/loading +
	                    Confetti.Emit + sound:Play
	                  task.wait(0.2) → MonoUI.Visible=false, Purchase.Enabled=false
	                  (Confetti is in its own ScreenGui — disabling Purchase is safe)

	Public API:
	  :PromptPurchase(productId: number) — enable ScreenGui + entrance + idle + native prompt
	  :PlaySuccess()                     — enable ScreenGui + exit + confetti + sound + disable
	  :PlayFailure()                     — placeholder error response (no frame state)

	Janitor layout:
	  _connJanitor  (module-scope, persistent) — PurchaseEffect bridge conn +
	                PromptProductPurchaseFinished conn
	  _idleJanitor  (module-scope) — Enlargen icon handle + Enlargen loading handle +
	                Shadow.UIGradient spin conn + rotation reset fn +
	                RotateOscillate handle + dots loop thread;
	                Cleanup'd on close/finish so idle anims never run behind closed frame
	  _playJanitor  (module-scope, per-play) — celebration thread; swapped each PlaySuccess

	KNOWN CAVEAT: Roblox's native purchase dialog is a CoreGui modal that renders
	ABOVE PlayerGui. BuyTransition is partially obscured while the native prompt is
	displayed. It is most visible during the brief server-processing gap after "OK"
	and at the confetti completion beat. Confirm this design intent before shipping.

	Per architecture.md § Require Paths, § Critical Bans (no yield in bridge/event
	handlers; capture locals before task.spawn/task.delay).
	Per api-reference.md § 1.1 Knit, § 1.2 BridgeNet2, § 3.1 Janitor,
	§ 6.1 UIAnimator Twinkle (FrameZoom yields — task.spawn required),
	§ 9.8 UIAnimator controller (Enlargen/Shrink/RotateOscillate → Handle.Cancel()).
	Per juice-and-animation.md § 5a (RotateOscillate idle), § 4 (co-incident channels),
	§ 6 (cancel path = silent; only Success kind gets juice).
]==]

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Bridges = require(ReplicatedStorage.Shared.Bridges)

-- Confetti is a project-level preset (module-as-folder sibling — rule_16).
local Confetti = require(script.Parent.UIAnimator.Presets.Confetti)

-- Shared TweenInfo constants (one-shot fire-and-forget — rule_7 exemption).
local ENTRANCE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXIT_TWEEN     = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXIT_DURATION  = 0.2  -- match EXIT_TWEEN duration; wait before disabling ScreenGui

local PurchaseEffectsController = Knit.CreateController {
	Name = "PurchaseEffectsController",
}

-- ---------------------------------------------------------------------------
-- Module-scope janitors
-- ---------------------------------------------------------------------------

-- Persistent: bridge conn + PromptProductPurchaseFinished conn.
local _connJanitor: Janitor.Janitor = Janitor.new()

-- Idle animations while frame is open. Cleanup'd on close (success OR cancel)
-- so all idles (spin, rock, dots) never run behind a closed frame.
local _idleJanitor: Janitor.Janitor = Janitor.new()

-- Per-play celebration thread. Swapped on each PlaySuccess call.
local _playJanitor: Janitor.Janitor = Janitor.new()

-- Exit Shrink handles (Icon + Loading scale-down). Cleaned at the top of both
-- PromptPurchase and PlaySuccess so an orphaned Shrink spring can never fight a
-- re-open Enlargen over the shared UIScale (both presets write the same UIScale
-- each Heartbeat — last writer wins, which would snap the element to Scale=0).
local _exitJanitor: Janitor.Janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Fire the co-incident exit animations: shadow fade-out + Shrink icon + Shrink loading.
-- Called from both cancel and success paths. All three fire on the SAME call (co-incident).
-- Per juice-and-animation.md § 4: channels of the same moment fire on the same frame.
local function _playExit(
	shadow:     ImageLabel?,
	iconEl:     GuiObject?,
	loadingEl:  GuiObject?,
	uianim:     any
)
	if shadow then
		-- One-shot tween: brisk ~0.2s Quad Out back to fully transparent.
		-- rule_7 fire-and-forget exemption (same as entrance tween).
		TweenService:Create(shadow, EXIT_TWEEN, { ImageTransparency = 1 }):Play()
	end
	-- Track the Shrink handles in _exitJanitor so a rapid re-open (PromptPurchase
	-- within the ~0.3s settle window) cancels them before its Enlargen starts —
	-- otherwise both springs write the shared UIScale and the element snaps to 0.
	if iconEl and uianim then
		local sh = uianim:Shrink(iconEl)
		_exitJanitor:Add(function() sh.Cancel() end, true)
	end
	if loadingEl and uianim then
		local sh = uianim:Shrink(loadingEl)
		_exitJanitor:Add(function() sh.Cancel() end, true)
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PurchaseEffectsController:KnitStart()
	self._sound      = Knit.GetController("SoundController")
	self._uianim     = Knit.GetController("UIAnimator")
	self._processing = false   -- true while a PromptPurchase is in flight

	if not self._sound then
		warn("[PurchaseEffectsController] SoundController not found — sound will be skipped")
	end
	if not self._uianim then
		warn("[PurchaseEffectsController] UIAnimator controller not found — frame transitions will be skipped")
	end

	-- Resolve PlayerGui.Purchase.MonoUI.BuyTransition.
	-- WaitForChild is safe here — KnitStart runs in a Knit-managed coroutine.
	local localPlayer = Players.LocalPlayer
	local playerGui   = localPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
	if not playerGui then
		warn("[PurchaseEffectsController] PlayerGui not found after 10s — purchase effects disabled")
		return
	end

	local purchaseGui = playerGui:WaitForChild("Purchase", 10) :: ScreenGui?
	if not purchaseGui then
		warn("[PurchaseEffectsController] PlayerGui.Purchase ScreenGui not found — purchase effects disabled")
		return
	end

	local monoUI = purchaseGui:FindFirstChild("MonoUI")
	if not monoUI then
		warn("[PurchaseEffectsController] Purchase.MonoUI not found — purchase effects disabled")
		return
	end

	local buyTransition = monoUI:FindFirstChild("BuyTransition") :: Frame?
	if not buyTransition then
		warn("[PurchaseEffectsController] Purchase.MonoUI.BuyTransition not found — purchase effects disabled")
		return
	end

	-- Store references; set clean initial state (disabled by default).
	self._purchaseGui   = purchaseGui
	self._monoUI        = monoUI
	self._buyTransition = buyTransition

	purchaseGui.Enabled   = false   -- enabled only while a purchase effect is on screen
	monoUI.Visible        = false
	buyTransition.Visible = false

	-- Resolve Shadow ImageLabel + UIGradient.
	-- Per rule_8: warn on each miss; effects no-op if either is absent.
	local shadow = buyTransition:FindFirstChild("Shadow") :: ImageLabel?
	if not shadow then
		warn("[PurchaseEffectsController] BuyTransition.Shadow not found — shadow effects will be skipped")
	else
		self._shadow = shadow   -- stored for entrance/exit ImageTransparency tweens
		local shadowGrad = shadow:FindFirstChild("UIGradient")
		if not shadowGrad then
			warn("[PurchaseEffectsController] BuyTransition.Shadow.UIGradient not found — gradient spin will be skipped")
		else
			self._shadowGradient = shadowGrad
		end
	end

	-- Bridge: server → client PurchaseEffect (no player arg on client — api-reference.md § 1.2).
	-- task.spawn required — bridge handlers must never yield (architecture.md Critical Bans).
	local bridgeConn = Bridges.PurchaseEffect:Connect(function(data)
		task.spawn(function()
			if data and data.kind == "Success" then
				self:PlaySuccess()
			elseif data and data.kind == "Failure" then
				self:PlayFailure()
			else
				warn("[PurchaseEffectsController] Unknown PurchaseEffect kind:", data and data.kind or "nil")
			end
		end)
	end)
	_connJanitor:Add(bridgeConn, "Disconnect")

	-- Bridge: server → client GiftReceived (payload: { fromUserId: number, productId: number }).
	-- Validate before spawn — bridge handler body must not yield (architecture.md § Critical Bans).
	-- Per CLAUDE.md rule_8: warn on malformed payload.
	-- Per api-reference.md § 1.2 BridgeNet2: client Connect receives (content) only, no player arg.
	local giftReceivedConn = Bridges.GiftReceived:Connect(function(data)
		if type(data) ~= "table"
			or type(data.fromUserId) ~= "number"
			or type(data.productId) ~= "number"
		then
			warn("[PurchaseEffectsController] GiftReceived: malformed payload —", data)
			return
		end
		local fromUserId = data.fromUserId
		local productId  = data.productId
		task.spawn(function()
			-- Resolve gifter display name (may yield — inside task.spawn, safe).
			-- Players is already required at file scope — do not re-require.
			local gifterName = "Someone"
			local nameOk, nameResult = pcall(function()
				return Players:GetNameFromUserIdAsync(fromUserId)
			end)
			if nameOk then
				gifterName = nameResult :: string
			else
				warn("[PurchaseEffectsController] GiftReceived: GetNameFromUserIdAsync failed —", nameResult)
			end

			-- Resolve product name (may yield).
			-- MarketplaceService is already required at file scope.
			local productName = "a gift"
			local infoOk, infoResult = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if not infoOk then
				warn("[PurchaseEffectsController] GiftReceived: GetProductInfo failed —", infoResult)
			else
				local info = infoResult :: any
				if type(info) == "table" and type(info.Name) == "string" then
					productName = info.Name
				end
			end

			-- Celebration: confetti + sound + BuyTransition exit (same as self-purchase).
			-- PlaySuccess self-enables the Purchase ScreenGui (server-gift / no-prior-prompt path).
			-- Per juice-and-animation.md § 6: Purchase success → confetti + BigBump + sound.
			self:PlaySuccess()

			-- Special notification: who gifted and what they sent.
			-- Per api-reference.md § 9.8: ShowNotification accepts NotificationOpts
			-- = { message, template = "Notification"|"Error"|"SpecialNotification"|"Tutorial", ... }.
			-- "SpecialNotification" confirmed as real template (hidden at KnitStart by UIAnimator init).
			if self._uianim then
				self._uianim:ShowNotification({
					message  = gifterName .. " GIFTED YOU " .. productName .. "!",
					template = "SpecialNotification",
				})
			else
				warn("[PurchaseEffectsController] GiftReceived: UIAnimator nil — gift notification skipped")
			end
		end)
	end)
	-- Explicit "Disconnect" — Janitor auto-detect probes :Destroy first, which throws on
	-- BridgeNet2 connections. Per api-reference.md § 3.1 Janitor gotcha.
	_connJanitor:Add(giftReceivedConn, "Disconnect")

	-- Client-side PromptProductPurchaseFinished listener.
	-- Fires when the native Roblox purchase prompt is dismissed (success OR cancel).
	-- Only act on prompts WE initiated via PromptPurchase (self._processing guard).
	-- Capture locals BEFORE task.spawn — state may change by the time spawn runs
	-- (architecture.md § Critical Bans: capture state before task.delay callbacks).
	local ppfConn = MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(_userId: number, _productId: number, isPurchased: boolean)
			local wasProcessing = self._processing
			local frame         = self._buyTransition
			local uianim        = self._uianim
			local monoUI_cap    = self._monoUI
			local purchGui_cap  = self._purchaseGui
			local shadow_cap    = self._shadow

			task.spawn(function()
				if not wasProcessing then return end   -- not a prompt we showed — ignore

				self._processing = false
				_idleJanitor:Cleanup()   -- stop all idle anims (spin + rock + dots)

				if isPurchased then
					-- Leave the frame open — PlaySuccess (from the server bridge
					-- PurchaseEffect{kind="Success"}) owns the exit + confetti + sound.
					-- Reacting here would double-fire exit before PlaySuccess can run.
					-- Per juice-and-animation.md § 5g: only the "Success" kind gets juice.
					return
				end

				-- Cancel / failure path: exit silently, no confetti, no sound.
				-- Per juice-and-animation.md § 6: "Purchase failure/cancel: No effect."
				local iconEl    = frame and frame:FindFirstChild("Icon") :: ImageLabel?
				local loadingEl = frame and frame:FindFirstChild("Loading") :: TextLabel?

				-- CO-INCIDENT exit: shadow fade-out + Shrink icon + Shrink loading.
				-- All fire on the same call per juice-and-animation.md § 4.
				_playExit(shadow_cap, iconEl, loadingEl, uianim)

				-- Wait for exit to finish, then disable ScreenGui.
				-- Guard: if a new PromptPurchase fired during the wait, skip the disable
				-- to avoid clobbering the freshly-opened state.
				task.wait(EXIT_DURATION)
				if not self._processing then
					if monoUI_cap then monoUI_cap.Visible = false end
					if purchGui_cap then
						purchGui_cap.Enabled = false
					end
				end
			end)
		end
	)
	_connJanitor:Add(ppfConn, "Disconnect")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[==[
	Enable ScreenGui, play entrance animation, start idle anims, show native prompt.

	The frame remains active until the purchase concludes:
	  • Success → PlaySuccess fires exit + confetti + sound.
	  • Cancel  → PromptProductPurchaseFinished fires exit silently.

	Guard: if BuyTransition was not resolved, warns and still fires the native
	prompt so the purchase is never silently blocked.
]==]
function PurchaseEffectsController:PromptPurchase(productId: number)
	-- Capture locals before any async work (architecture.md § Critical Bans).
	local frame          = self._buyTransition
	local uianim         = self._uianim
	local lp             = Players.LocalPlayer
	local purchaseGui    = self._purchaseGui
	local monoUI         = self._monoUI
	local shadow         = self._shadow
	local shadowGradient = self._shadowGradient

	if not frame then
		warn("[PurchaseEffectsController] PromptPurchase: BuyTransition not resolved — effects skipped, still prompting")
		if lp then
			task.spawn(function()
				MarketplaceService:PromptProductPurchase(lp, productId)
			end)
		end
		return
	end

	-- Cancel any in-flight PlaySuccess celebration thread BEFORE reopening the
	-- frame. Without this, a prior thread sleeping in task.wait(EXIT_DURATION)
	-- could resume and disable the ScreenGui, clobbering this freshly-opened state.
	_playJanitor:Cleanup()

	self._processing = true

	-- Enable ScreenGui and container. Per rule_8: warn on nil.
	if purchaseGui then
		purchaseGui.Enabled = true
	else
		warn("[PurchaseEffectsController] PromptPurchase: _purchaseGui nil — ScreenGui not enabled, falling back to frame.Visible")
	end
	if monoUI then
		monoUI.Visible = true
	else
		warn("[PurchaseEffectsController] PromptPurchase: _monoUI nil — container not shown")
	end

	-- Snap shadow invisible BEFORE frame.Visible=true to prevent a flash at
	-- its authored resting value (0.5). The entrance tween then fades it back in.
	if shadow then
		shadow.ImageTransparency = 1
	end

	-- Entrance IS the shadow-fade + Enlargen; NO OpenFrame zoom (would double-scale
	-- on top of Enlargen's UIScale — they'd conflict on the frame's visual size).
	frame.Visible = true

	-- Reset idle state — cleans any Enlargen handles, spin, rock, dots from a prior open.
	_idleJanitor:Cleanup()

	-- Cancel any still-running exit Shrink from a just-finished close, so it can't
	-- fight the entrance Enlargen below over the shared UIScale (audit-confirmed race).
	_exitJanitor:Cleanup()

	-- Find Icon and Loading once; used for entrance Enlargen and idle RotateOscillate/dots.
	local iconInst    = frame:FindFirstChild("Icon") :: ImageLabel?
	local loadingInst = frame:FindFirstChild("Loading") :: TextLabel?
	if not iconInst then
		warn("[PurchaseEffectsController] PromptPurchase: Icon not found in BuyTransition — Icon entrance/idle skipped")
	end
	if not loadingInst then
		warn("[PurchaseEffectsController] PromptPurchase: Loading not found in BuyTransition — Loading entrance/idle skipped")
	end

	-- ── ENTRANCE (user-requested) ──────────────────────────────────────────────
	-- All three channels fire CO-INCIDENT (same synchronous call) per
	-- juice-and-animation.md § 4 — no inter-layer delay for same-moment channels.

	-- Shadow fade-in: one-shot Quad Out tween 1→0.5 over 0.3s.
	-- rule_7 fire-and-forget exemption (no spring polling after complete).
	if shadow then
		TweenService:Create(shadow, ENTRANCE_TWEEN, { ImageTransparency = 0.5 }):Play()
	end

	-- Enlargen Icon + Loading: spring scale 0.6→1.0, smoothTime=0.18.
	-- Handles stored in _idleJanitor so rapid re-open cancels mid-flight springs.
	-- Per api-reference.md § 9.8: handle.Cancel() (property fn, not method).
	if iconInst and uianim then
		local iconEl = iconInst  -- local binding — avoids leading-( ambiguity (architecture.md)
		local eh = uianim:Enlargen(iconEl)
		_idleJanitor:Add(function() eh.Cancel() end, true)
	end
	if loadingInst and uianim then
		local loadEl = loadingInst :: TextLabel
		local eh = uianim:Enlargen(loadEl :: GuiObject)
		_idleJanitor:Add(function() eh.Cancel() end, true)
	end

	-- ── IDLE (user-requested: gradient spin; [off-script]: rock + dots) ───────
	-- These run continuously while the purchase is in flight. All stored in
	-- _idleJanitor so they stop atomically when the frame closes.

	-- Gradient spin: 90 deg/s continuous rotation on Shadow.UIGradient.
	-- Per-frame RenderStepped is correct for a continuous loop (same engine as RotateOscillate).
	-- "Disconnect" explicit so Janitor never probes :Destroy (api-reference.md § 3.1 gotcha).
	local SPIN_SPEED = 90  -- deg/s; ~4s/revolution — smooth, not dizzying
	if shadowGradient then
		shadowGradient.Rotation = 0   -- clean start each open
		local spinConn = RunService.RenderStepped:Connect(function(dt: number)
			shadowGradient.Rotation = (shadowGradient.Rotation + SPIN_SPEED * dt) % 360
		end)
		_idleJanitor:Add(spinConn, "Disconnect")
		-- Reset rotation on cleanup (LIFO: this fires before disconnect, which is correct).
		_idleJanitor:Add(function()
			if shadowGradient.Parent then
				shadowGradient.Rotation = 0
			end
		end, true)
	end

	-- RotateOscillate on Icon: slow pendulum rock while the player decides.
	-- [off-script] Draws the eye to the product icon; communicates "active / loading".
	-- angle=4 (subtler than default 5), period=2.0 (relaxed pendulum feel).
	-- RotateOscillate uses Rotation; Enlargen uses UIScale — no conflict on the same element.
	-- Per juice-and-animation.md § 5a: RotateOscillate is the canonical idle-attention tool.
	if iconInst and uianim then
		local iconEl = iconInst
		local rocHandle = uianim:RotateOscillate(iconEl, {
			angle      = 4,
			period     = 2.0,
			smoothTime = 0.45,
		})
		_idleJanitor:Add(function()
			rocHandle.Cancel()
		end, true)
	end

	-- "Loading…" dots cycle on Loading TextLabel (~0.3s/step).
	-- [off-script] Communicates that something is happening while player waits.
	-- Throttled loop (task.wait, not per-frame) per architecture.md no-per-frame rule.
	if loadingInst then
		local loadEl    = loadingInst :: TextLabel
		local origText  = loadEl.Text
		local dotStates = { ".", "..", "..." }

		local dotsThread = task.spawn(function()
			local i = 1
			while true do
				loadEl.Text = "Loading" .. dotStates[i]
				i = (i % #dotStates) + 1
				task.wait(0.3)
			end
		end)

		_idleJanitor:Add(function()
			task.cancel(dotsThread)
			if loadEl.Parent then
				loadEl.Text = origText
			end
		end, true)
	end

	-- ── NATIVE PROMPT ─────────────────────────────────────────────────────────
	-- PromptProductPurchase yields — must be spawned.
	-- Per architecture.md § Critical Bans: no yield in event handlers.
	if lp then
		task.spawn(function()
			MarketplaceService:PromptProductPurchase(lp, productId)
		end)
	else
		warn("[PurchaseEffectsController] PromptPurchase: LocalPlayer nil — cannot prompt")
	end
end

--[==[
	Play the full purchase success celebration.

	Can be triggered two ways:
	  1. Via server bridge PurchaseEffect{kind="Success"} — may have NO preceding
	     PromptPurchase (e.g. gift purchase). PlaySuccess ensures the ScreenGui is
	     enabled and frame is visible before playing effects.
	  2. After a PromptPurchase — ScreenGui already enabled; normal path.

	All celebration channels fire CO-INCIDENT (same frame, per juice-and-animation.md § 4):
	  • Shadow fade-out tween (0.2s Quad Out) — brisk exit
	  • Shrink Icon + Loading                 — spring scale-down
	  • Confetti.Emit({amount=100})            — burst + Reward sound + BigBump shake
	  • sound:Play("UI.RBXPurchase")          — cha-ching layers with Reward sfx

	After EXIT_DURATION (0.2s), MonoUI and ScreenGui are disabled.
	Confetti lives in its own ScreenGui — disabling Purchase does NOT cut it off.
]==]
function PurchaseEffectsController:PlaySuccess()
	-- Capture locals before any yields (architecture.md § Critical Bans).
	local frame       = self._buyTransition
	local sound       = self._sound
	local uianim      = self._uianim
	local monoUI      = self._monoUI
	local purchaseGui = self._purchaseGui
	local shadow      = self._shadow

	if not frame then
		warn("[PurchaseEffectsController] PlaySuccess: BuyTransition not resolved — skipping")
		return
	end

	-- Ensure ScreenGui is enabled before playing effects. PlaySuccess can fire
	-- directly from the server bridge (gift path) without a preceding PromptPurchase;
	-- the ScreenGui may still be disabled in that case. We enable now so the exit
	-- animation is actually visible.
	if purchaseGui then
		purchaseGui.Enabled = true
	else
		warn("[PurchaseEffectsController] PlaySuccess: _purchaseGui nil — effects may not render")
	end
	if monoUI then
		monoUI.Visible = true
	end

	-- Stop idle anims. Idempotent — safe if PromptProductPurchaseFinished already
	-- cleaned up when isPurchased=true.
	self._processing = false
	_idleJanitor:Cleanup()

	-- Cancel any prior exit Shrink before this success's own _playExit adds fresh
	-- handles, so overlapping successes never stack two Shrinks on one UIScale.
	_exitJanitor:Cleanup()

	-- Cancel any in-flight celebration thread and start fresh.
	_playJanitor:Cleanup()

	local thread: thread
	thread = task.spawn(function()
		-- Ensure frame is visible for exit animation. May be false if PlaySuccess
		-- fired without a preceding PromptPurchase (server-gift path).
		frame.Visible = true

		-- Find Icon + Loading for exit Shrink (captured inside thread — frame is safe
		-- to index; it's a module-scope field resolved at KnitStart and never nil here).
		local iconEl    = frame:FindFirstChild("Icon") :: ImageLabel?
		local loadingEl = frame:FindFirstChild("Loading") :: TextLabel?

		-- CO-INCIDENT celebration beat: ALL channels fire on the SAME frame.
		-- Per juice-and-animation.md § 4: no inter-layer wait for same-moment channels.
		-- Exit (shadow + Shrink) fires co-incident WITH confetti + sound — the exit
		-- and the celebration are the same moment, not sequential.
		_playExit(shadow, iconEl, loadingEl, uianim)
		Confetti.Emit({ amount = 100 })
		if sound then
			sound:Play("UI.RBXPurchase")   -- purchase cha-ching layers with Reward sfx
		end

		-- Wait for exit tween, then disable ScreenGui.
		-- Confetti is in its own ScreenGui — this does NOT cut it off.
		task.wait(EXIT_DURATION)
		if monoUI then monoUI.Visible = false end
		if purchaseGui then
			purchaseGui.Enabled = false
		else
			frame.Visible = false   -- fallback if ScreenGui ref is nil
		end
	end)
	_playJanitor:Add(thread)
end

--[[
	Placeholder failure response: error sound only.
	Kept minimal — flesh out when a failure design is finalised.
	The cancel path (player closes the Robux prompt) is silent and handled by
	PromptProductPurchaseFinished — PlayFailure is for explicit server-driven
	"Failure" kind notifications only.
]]
function PurchaseEffectsController:PlayFailure()
	local sound = self._sound
	if sound then
		sound:Play("UI.Error")
	end
end

return PurchaseEffectsController
