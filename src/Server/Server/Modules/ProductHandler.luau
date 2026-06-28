--[[
	ProductHandler
	--------------
	Handles MarketplaceService developer-product purchases, including gifting
	(a buyer purchases a product on behalf of an online recipient).

	Pattern:
	  - Each product branch validates the player, applies the grant, and returns
	    PurchaseGranted immediately. Never return NotProcessedYet after granting.
	  - Use the dual-ID pattern (PRODUCT_ID + PRODUCT_ID_ALT) for A/B pricing tests.
	  - Use passLock for one-time grants (game-passes disguised as dev products) to
	    prevent double-processing if the receipt fires more than once.
	  - Any yielding work (broadcasts, async operations) must be wrapped in task.spawn.

	To add a new product:
	  1. Add a constant for its product ID at the top of this file
	  2. Add an elseif branch in ProcessReceipt
	  3. Add cleanup for any per-player state in Players.PlayerRemoving
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local ServerStorage      = game:GetService("ServerStorage")

local BridgeNet2  = require(ReplicatedStorage.Packages.BridgeNet2)
local Bridges     = require(ReplicatedStorage.Shared.Bridges)
local DataService = require(ServerStorage.ServerUtilities.DataService)

local ProductHandler = {}

-- ---------------------------------------------------------------------------
-- Product ID constants (set in the Creator Dashboard → Developer Products)
-- ---------------------------------------------------------------------------

-- Dual-ID pattern: set both IDs to the same value unless you're running an
-- A/B price test. The receipt handler accepts either.
local EXAMPLE_PRODUCT_ID     = 0  -- TODO: replace with your dev product ID
local EXAMPLE_PRODUCT_ID_ALT = 0  -- TODO: set to alternate-price variant, or same as above

-- Add more product constants here:
-- local CASH_PACK_SMALL_ID = 0
-- local CASH_PACK_LARGE_ID = 0

-- ---------------------------------------------------------------------------
-- Per-player state tables (all keyed by UserId)
-- ---------------------------------------------------------------------------

-- Per-player mutex: prevents double-processing one-time grants.
-- Key format: "userId_productId" so separate products don't block each other.
local passLock: {[string]: boolean} = {}

-- Example queue: store pending per-player rewards that need a character to exist.
-- Pattern: set to true on purchase, consume when character is ready.
local exampleQueued: {[number]: boolean} = {}

-- ---------------------------------------------------------------------------
-- Gifting state
-- ---------------------------------------------------------------------------
-- pendingGifts[buyerUserId][productId] = targetUserId
-- Records gift intent between GiftPurchase bridge fire and ProcessReceipt callback.
-- Inner table is initialised lazily on first gift attempt per buyer.
-- Splitting this into a separate module would obscure the receipt→intent lookup
-- that lives right next to it in Initialize; keeping it flat preserves that
-- audit trail for whoever investigates a double-grant or stale-intent bug.
local pendingGifts: {[number]: {[number]: number}} = {}

-- Per-buyer mutex for the GiftPurchase bridge listener.
-- Prevents the same buyer from queuing two concurrent gift prompts.
local giftLock: {[number]: boolean} = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

function ProductHandler.HasExampleQueued(player: Player): boolean
	return exampleQueued[player.UserId] == true
end

function ProductHandler.ConsumeExample(player: Player)
	exampleQueued[player.UserId] = nil
end

-- ---------------------------------------------------------------------------
-- Public: TryGift
-- ---------------------------------------------------------------------------
-- Shared gift-prompt path. Called by the GiftPurchase bridge listener below
-- (client-initiated) and available for any future server-initiated callers.
-- Per api-reference.md § 1.2: never call Bridges.GiftPurchase:Fire from the
-- server to reach this listener — that fires TO the client, not to ourselves.
-- Server-internal callers must invoke ProductHandler.TryGift directly.
--
-- Validates target / not-self / recipient-online, records pending-gift intent,
-- then PromptProductPurchase on the buyer. Returns true if the prompt was
-- actually triggered, false if validation failed.
--
-- This function YIELDS (PromptProductPurchase is wrapped in task.spawn) — it
-- itself is non-yielding, but the caller is responsible for the no-yield-in-
-- bridge rule when invoking from a bridge handler.
function ProductHandler.TryGift(buyer: Player, targetUserId: number, productId: number): boolean
	local uid = buyer.UserId

	-- Semantic sanity: a player cannot gift to themselves in production.
	-- In Studio, allow self-gifting so the full purchase → receipt path can be
	-- exercised with a single player. Per CLAUDE.md rule_8 — warn on fallback.
	if targetUserId == uid then
		if RunService:IsStudio() then
			warn("[ProductHandler/Gifting] Studio: allowing self-gift for testing — buyer "
				.. buyer.Name .. " (userId=" .. uid .. ")")
			-- Fall through to proceed with the gift prompt.
		else
			warn("[ProductHandler/Gifting] self-gift rejected — buyer "
				.. buyer.Name .. " (userId=" .. uid .. ")")
			return false
		end
	end

	-- Verify the recipient is currently online; no point prompting the buyer
	-- for someone who isn't here to receive it.
	local recipient = Players:GetPlayerByUserId(targetUserId)
	if not recipient then
		warn("[ProductHandler/Gifting] recipient offline (uid=" .. targetUserId
			.. ") at prompt time — aborting gift for buyer", buyer.Name)
		return false
	end

	-- Record intent: receipt handler will look this up when Roblox fires
	-- ProcessReceipt for the buyer.
	if not pendingGifts[uid] then
		pendingGifts[uid] = {}
	end
	pendingGifts[uid][productId] = targetUserId

	-- Prompt the buyer (yields — must be inside task.spawn so callers in a
	-- bridge dispatch context don't block the dispatch loop).
	task.spawn(function()
		MarketplaceService:PromptProductPurchase(buyer, productId)
	end)

	return true
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function ProductHandler:Initialize()

	-- ---------------------------------------------------------------------------
	-- Gifting bridge
	-- ---------------------------------------------------------------------------
	-- Bridge: client fires when a player wants to gift a product to another player.
	-- Payload: { targetUserId: number, productId: number }
	-- Per-architecture.md § Critical Bans: mutex gate OUTSIDE task.spawn,
	-- body INSIDE, release INSIDE after pcall.
	-- Per-api-reference.md § 1.2: single-table payload; no yield in :Connect callback.
	-- Body delegates to ProductHandler.TryGift so any server-side callers can
	-- share the same path without firing the bridge from the wrong direction.
	Bridges.GiftPurchase:Connect(function(buyer, data)
		local uid = buyer.UserId

		-- Structural validation: reject malformed payloads before touching any state.
		if type(data) ~= "table" then
			warn("[ProductHandler/Gifting] invalid payload from " .. buyer.Name .. " — expected table, got " .. type(data))
			return
		end
		if type(data.targetUserId) ~= "number" or type(data.productId) ~= "number" then
			warn("[ProductHandler/Gifting] invalid payload from " .. buyer.Name
				.. " — targetUserId and productId must be numbers. Got: "
				.. type(data.targetUserId) .. " " .. type(data.productId))
			return
		end

		-- Capture payload fields into locals before task.spawn
		-- (per architecture.md § Critical Bans — state may be nil by the time the spawn runs).
		local targetUserId = data.targetUserId
		local productId    = data.productId

		-- Per-buyer mutex gate OUTSIDE task.spawn.
		if giftLock[uid] then
			warn("[ProductHandler/Gifting] concurrent gift attempt from " .. buyer.Name
				.. " (userId=" .. uid .. ") — ignored (lock held)")
			return
		end
		giftLock[uid] = true

		task.spawn(function()
			local ok, err = pcall(function()
				ProductHandler.TryGift(buyer, targetUserId, productId)
			end)

			-- Release INSIDE task.spawn, after pcall.
			giftLock[uid] = nil

			if not ok then
				warn("[ProductHandler/Gifting] error during gift prompt for " .. buyer.Name .. " — " .. tostring(err))
			end
		end)
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			-- Player left before receipt processed; retry later.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Wait for data to be loaded before granting anything.
		if not DataService.GetData(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if RunService:IsStudio() then
			-- Dev/test stub: log + treat as granted so the playground can exercise gifting without spending Robux.
			warn("[ProductHandler] Studio stub — granting receipt without charge: productId=" .. tostring(receiptInfo.ProductId))
			-- Still execute the gifting branch + reward path:
			-- (the existing pendingGifts check + example branch will run below as normal,
			--  but real production would have charged Robux first).
		end

		-- Check whether this purchase was a gift intent recorded by GiftPurchase.
		-- Evaluated BEFORE the regular product branches so a gifted product ID is
		-- never double-granted to the buyer.
		do
			local buyerPending = pendingGifts[receiptInfo.PlayerId]
			local targetUserId = buyerPending and buyerPending[receiptInfo.ProductId]

			if targetUserId then
				local recipient = Players:GetPlayerByUserId(targetUserId)
				if not recipient then
					-- Recipient logged off between the prompt and the receipt.
					-- Return NotProcessedYet so Roblox retries on the buyer's next session.
					-- The pending intent is kept so the retry can resolve it if the
					-- recipient rejoins before the retry window expires.
					warn("[ProductHandler/Gifting] recipient offline at receipt time"
						.. " (uid=" .. targetUserId .. ") — returning NotProcessedYet")
					return Enum.ProductPurchaseDecision.NotProcessedYet
				end

				-- TODO: apply reward to `recipient` for productId = receiptInfo.ProductId
				-- (mirror the existing example branch style, e.g.):
				-- DataService.Increment(recipient, "cash", GIFT_REWARD_AMOUNT)

				-- Notify the recipient.
				Bridges.GiftReceived:Fire(recipient, {
					fromUserId = receiptInfo.PlayerId,
					productId  = receiptInfo.ProductId,
				})

				-- Broadcast the gift to all players for chat display.
				local buyerName   = player and player.Name or "Unknown"
				local recpName    = recipient.Name
				local giftProdId  = receiptInfo.ProductId
				task.spawn(function()
					local ok, info = pcall(function()
						return MarketplaceService:GetProductInfo(giftProdId, Enum.InfoType.Product)
					end)
					-- rule_8: warn on every failable lookup so silent failures don't hide bugs.
					if not ok then
						warn("[ProductHandler/Gifting] GetProductInfo failed for productId="
							.. tostring(giftProdId) .. " — using fallback name/price. Error: " .. tostring(info))
					end
					local productName = (ok and info) and info.Name or ("Product " .. tostring(giftProdId))
					local price       = (ok and info) and info.PriceInRobux or 0
					-- Per api-reference.md § networking: AllPlayers() fan-out fires a single
					-- batched packet rather than N individual Fire calls (Change 3).
					Bridges.PurchaseBroadcast:Fire(BridgeNet2.AllPlayers(), {
						playerName    = buyerName,
						productName   = productName,
						priceInRobux  = price,
						isGift        = true,
						recipientName = recpName,
					})
				end)

				-- Clear the pending intent so a retry doesn't double-grant.
				buyerPending[receiptInfo.ProductId] = nil

				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
		end

		-- ---------------------------------------------------------------
		-- Example dual-ID product branch
		-- ---------------------------------------------------------------
		if receiptInfo.ProductId == EXAMPLE_PRODUCT_ID
			or receiptInfo.ProductId == EXAMPLE_PRODUCT_ID_ALT then

			-- TODO: grant the product here, e.g.:
			-- exampleQueued[player.UserId] = true
			-- DataService.Increment(player, "cash", 1000)

			return Enum.ProductPurchaseDecision.PurchaseGranted

		-- ---------------------------------------------------------------
		-- Example one-time grant (game-pass-style dev product)
		-- ---------------------------------------------------------------
		-- elseif receiptInfo.ProductId == SOME_PASS_ID then
		--     local lockKey = player.UserId .. "_" .. receiptInfo.ProductId
		--     if passLock[lockKey] then return Enum.ProductPurchaseDecision.PurchaseGranted end
		--     passLock[lockKey] = true
		--
		--     local grantedPasses = DataService.Get(player, "grantedPasses") or {}
		--     if grantedPasses.SomePass then
		--         passLock[lockKey] = nil
		--         return Enum.ProductPurchaseDecision.PurchaseGranted
		--     end
		--     DataService.SetPath(player, {"grantedPasses", "SomePass"}, true)
		--     -- TODO: apply pass effects
		--     passLock[lockKey] = nil
		--     return Enum.ProductPurchaseDecision.PurchaseGranted

		-- ---------------------------------------------------------------
		-- TODO: add more product branches above this comment
		-- ---------------------------------------------------------------
		end

		-- Unknown product — do not grant.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Fire PurchaseEffect to the client whenever a product prompt is accepted.
	-- This is independent of ProcessReceipt — it fires on every successful prompt
	-- regardless of receipt processing, which is what the UI animation needs.
	-- Per api-reference.md § 1.2: :Fire takes a single table payload.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
		if not wasPurchased then
			-- Clear stale gift intent so a later self-purchase of the same product
			-- is not accidentally routed as a gift.
			local pending = pendingGifts[userId]
			if pending then pending[productId] = nil end
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			warn("[ProductHandler] PromptProductPurchaseFinished: player not found for userId=" .. tostring(userId))
			return
		end
		Bridges.PurchaseEffect:Fire(player, { kind = "Success" })
		-- Broadcast to chat. Skip gift purchases — ProcessReceipt broadcasts those instead.
		-- At this point pendingGifts[userId][productId] is still populated for gifts
		-- (ProcessReceipt hasn't run yet), so we use it as the guard.
		local buyerPending = pendingGifts[userId]
		if not (buyerPending and buyerPending[productId]) then
			local broadcastPlayer = player
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				-- rule_8: warn on every failable lookup so silent failures don't hide bugs.
				if not ok then
					warn("[ProductHandler] GetProductInfo failed for productId="
						.. tostring(productId) .. " — using fallback name/price. Error: " .. tostring(info))
				end
				local productName = (ok and info) and info.Name or ("Product " .. tostring(productId))
				local price       = (ok and info) and info.PriceInRobux or 0
				-- Per api-reference.md § networking: AllPlayers() fan-out fires a single
				-- batched packet rather than N individual Fire calls (Change 2).
				Bridges.PurchaseBroadcast:Fire(BridgeNet2.AllPlayers(), {
					playerName   = broadcastPlayer.Name,
					productName  = productName,
					priceInRobux = price,
					isGift       = false,
				})
			end)
		end
	end)

	-- Clean up per-player tables when the player leaves.
	-- Per architecture.md § Critical Bans (per-player table cleanup): every
	-- per-player table keyed by UserId (directly OR via composite-string keys
	-- prefixed by UserId) MUST be swept here or it's a memory leak.
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		exampleQueued[uid] = nil
		pendingGifts[uid] = nil
		giftLock[uid]     = nil

		-- Sweep passLock entries: keys are "userId_productId" composite strings,
		-- so walk and drop everything with the leaving player's UID prefix.
		local uidPrefix = tostring(uid) .. "_"
		for key in pairs(passLock) do
			if string.sub(key, 1, #uidPrefix) == uidPrefix then
				passLock[key] = nil
			end
		end
	end)
end

return ProductHandler
