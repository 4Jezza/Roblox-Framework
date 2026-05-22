--!strict
--[[
	PurchaseEffectsController
	--------------------------
	Listens to Bridges.PurchaseEffect (server → client) and runs the
	purchase-celebration pipeline:
	  1. Sound — SoundController:Play("UI.RBXPurchase")
	  2. BuyTransition frame — UIAnimator:OpenFrame (FrameZoom open)
	  3. Confetti — Confetti.Emit({ amount = 100 })
	  4. UIAnimator:CloseFrame after a beat

	Public API:
	  PurchaseEffectsController:PlaySuccess()  -- replay from any controller
	  PurchaseEffectsController:PlayFailure()  -- placeholder shake

	Per architecture.md § Require Paths, § Critical Bans (no yield in bridge,
	capture locals before task.spawn).
	Per api-reference.md § 1.1 Knit, § 1.2 BridgeNet2, § 3.1 Janitor,
	§ 6.1 UIAnimator Twinkle (FrameZoom yields — task.spawn required).
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Bridges = require(ReplicatedStorage.Shared.Bridges)

-- Confetti is a project-level preset, not part of the Twinkle package.
-- Path: Controllers/UIAnimator/Presets/Confetti (sibling folder).
local Confetti = require(script.Parent.UIAnimator.Presets.Confetti)

local PurchaseEffectsController = Knit.CreateController {
	Name = "PurchaseEffectsController",
}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- Holds the bridge connection for the lifetime of the controller.
local _connJanitor: Janitor.Janitor = Janitor.new()

-- Per-play janitor: Cleanup'd and rebuilt each time PlaySuccess fires so
-- any in-flight animation thread is cancelled before a new run starts.
-- Does NOT hold the bridge connection — that lives in _connJanitor.
local _playJanitor: Janitor.Janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PurchaseEffectsController:KnitStart()
	-- Lazy controller refs — GetController is safe after KnitStart.
	self._sound    = Knit.GetController("SoundController")
	self._uianim   = Knit.GetController("UIAnimator")

	if not self._sound then
		warn("[PurchaseEffectsController] SoundController not found — sound will be skipped")
	end
	if not self._uianim then
		warn("[PurchaseEffectsController] UIAnimator controller not found — frame transitions will be skipped")
	end

	-- Resolve PlayerGui.Purchase ScreenGui and BuyTransition frame.
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
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

	self._buyTransition = buyTransition
	buyTransition.Visible = false

	-- Bridge: server → client; no player arg on client side (api-reference.md § 1.2).
	-- Wrap in task.spawn — bridge handlers must never yield (architecture.md Critical Bans).
	local conn = Bridges.PurchaseEffect:Connect(function(data)
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
	-- conn goes in _connJanitor (persistent), NOT _playJanitor (per-play).
	_connJanitor:Add(conn, "Disconnect")
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Play the full purchase success celebration:
	  1. Show BuyTransition, play sound.
	  2. Open frame via UIAnimator (FrameZoom 0.35s).
	  3. Wait 1.2s to let the animation breathe.
	  4. Drop confetti.
	  5. Wait 1.5s.
	  6. Close frame (FrameZoom 0.25s).
	  7. Hide BuyTransition.

	A second call while one play is in-flight cancels the prior run and
	begins fresh (per-play Janitor swap).
]]
function PurchaseEffectsController:PlaySuccess()
	-- Capture locals before any yields (architecture.md Critical Bans).
	local frame     = self._buyTransition
	local sound     = self._sound
	local uianim    = self._uianim

	if not frame then
		warn("[PurchaseEffectsController] PlaySuccess: BuyTransition not resolved — skipping")
		return
	end

	-- Cancel any in-flight run and start fresh.
	_playJanitor:Cleanup()

	-- Capture the thread so Janitor can cancel it if another PlaySuccess arrives.
	local thread: thread
	thread = task.spawn(function()
		frame.Visible = true

		if sound then
			sound:Play("UI.RBXPurchase")
		end

		if uianim then
			uianim:OpenFrame(frame, 0.35)
		end

		task.wait(1.2)

		Confetti.Emit({ amount = 100 })

		task.wait(1.5)

		if uianim then
			uianim:CloseFrame(frame, 0.25)
			-- CloseFrame (FrameZoom) yields for the tween duration.
			task.wait(0.25)
		end

		frame.Visible = false
	end)
	_playJanitor:Add(thread)
end

--[[
	Placeholder failure response: brief error sound + quick visibility pulse.
	Kept minimal — flesh out when a failure design is finalised.
]]
function PurchaseEffectsController:PlayFailure()
	local frame = self._buyTransition
	local sound = self._sound

	if sound then
		sound:Play("UI.Error")
	end

	if not frame then return end

	-- Quick visible flash as a placeholder shake affordance.
	task.spawn(function()
		frame.Visible = true
		task.wait(0.4)
		frame.Visible = false
	end)
end

return PurchaseEffectsController
