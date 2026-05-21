--[[
	ProductHandler
	--------------
	Handles MarketplaceService developer-product purchases.

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
local ServerStorage      = game:GetService("ServerStorage")

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
-- Helpers
-- ---------------------------------------------------------------------------

function ProductHandler.HasExampleQueued(player: Player): boolean
	return exampleQueued[player.UserId] == true
end

function ProductHandler.ConsumeExample(player: Player)
	exampleQueued[player.UserId] = nil
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function ProductHandler:Initialize()
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

	-- Clean up per-player tables when the player leaves.
	Players.PlayerRemoving:Connect(function(player)
		exampleQueued[player.UserId] = nil
		-- TODO: nil out additional per-player keys here
	end)
end

return ProductHandler
