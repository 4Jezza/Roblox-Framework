--[[
	PRODUCT CONFIG
	--------------
	Central registry for all Roblox developer product IDs.

	Replace the placeholder 0 values with your real product IDs from the
	Roblox Creator Dashboard before shipping.

	A/B test pattern
	----------------
	"Uses_Cheap_Main_Product" is a Roblox ConfigService config value.
	The server (RemoteConfigHandler) reads it and mirrors the value into a
	workspace attribute so this helper works on both server and client without
	any extra remotes.  Flip it in Creator Hub → Configs to switch the active
	product at runtime without republishing.
--]]

local ProductConfig = {}

-- ============================================================
-- Main product (example — replace 0 with your real product ID)
-- ============================================================

-- Primary variant
ProductConfig.MainProduct = 0
-- A/B test alternate: set to the new dev product ID, then flip the
-- "Uses_Cheap_Main_Product" workspace attribute (via RemoteConfigHandler) to
-- switch the active product at runtime without republishing.
ProductConfig.MainProductAlt = 0

-- Add more dev products here, e.g.:
-- ProductConfig.SecondProduct = 0
-- ProductConfig.ThirdProduct  = 0

-- ============================================================
-- A/B helpers
-- ============================================================

-- Returns the product ID currently active for the main product A/B test.
-- Toggle is controlled by a Roblox ConfigService config named
-- "Uses_Cheap_Main_Product". The server (RemoteConfigHandler) mirrors that
-- value into a workspace attribute that this helper reads.
function ProductConfig.GetActiveMainProductId(): number
	if workspace:GetAttribute("Uses_Cheap_Main_Product") == true and ProductConfig.MainProductAlt ~= 0 then
		return ProductConfig.MainProductAlt
	end
	return ProductConfig.MainProduct
end

return ProductConfig
