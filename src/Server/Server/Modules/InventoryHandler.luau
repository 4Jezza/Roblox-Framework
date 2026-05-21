--[[
	InventoryHandler
	----------------
	Stub for player inventory management. Inventory is stored as an array in
	profile.Data.inventory (serializable strings or numeric IDs).

	Mutex pattern: every bridge listener that mutates inventory should hold a
	per-player lock (see commented template below) to prevent race conditions
	from double-taps.
]]

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(ServerStorage.ServerUtilities.DataService)

local InventoryHandler = {}

-- Per-player mutex: prevents concurrent writes to the inventory array.
local lock: {[number]: boolean} = {}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Returns the player's inventory array, or an empty table if not loaded.
function InventoryHandler.GetInventory(player: Player): {any}
	return DataService.Get(player, "inventory") or {}
end

-- Adds an item identifier to the player's inventory and persists via SetPath.
-- Returns false if the player's data is not loaded or a lock is held.
function InventoryHandler.AddItem(player: Player, itemId: any): boolean
	local userId = player.UserId
	if lock[userId] then return false end
	lock[userId] = true

	local inventory = DataService.Get(player, "inventory") or {}
	table.insert(inventory, itemId)
	DataService.Set(player, "inventory", inventory)

	lock[userId] = nil
	return true
end

-- Removes the first occurrence of itemId from the player's inventory.
-- Returns true if the item was found and removed.
function InventoryHandler.RemoveItem(player: Player, itemId: any): boolean
	local userId = player.UserId
	if lock[userId] then return false end
	lock[userId] = true

	local inventory = DataService.Get(player, "inventory") or {}
	local index = table.find(inventory, itemId)
	if index then
		table.remove(inventory, index)
		DataService.Set(player, "inventory", inventory)
		lock[userId] = nil
		return true
	end

	lock[userId] = nil
	return false
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function InventoryHandler:Initialize()
	print("[InventoryHandler] initialized.")

	-- TODO: connect bridge listeners here (see networking-specialist agent for
	-- bridge definitions). Example pattern with mutex:
	--
	-- local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
	-- Bridges.UseItem:Connect(function(player, payload)
	--     local userId = player.UserId
	--     if lock[userId] then return end
	--     lock[userId] = true
	--     task.spawn(function()
	--         -- validate payload, apply effect
	--         lock[userId] = nil
	--     end)
	-- end)

	-- Clean up lock table when player leaves.
	Players.PlayerRemoving:Connect(function(player)
		lock[player.UserId] = nil
	end)
end

return InventoryHandler
