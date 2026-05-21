--[[
	AdminHandler
	------------
	Stub for server-side admin commands and privilege checks.

	Add admin user IDs to ADMIN_USER_IDS below. Replace the hardcoded list with
	a DataStore lookup or group-rank check if you need dynamic admin lists.

	Bridge pattern: the client fires an AdminCommand bridge with a payload of
	{ command = "string", args = {...} }. The handler validates the sender is an
	admin before executing anything.
]]

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(ServerStorage.ServerUtilities.DataService)

local AdminHandler = {}

-- TODO: add the UserId of each admin. Never expose this list to the client.
local ADMIN_USER_IDS: {[number]: boolean} = {
	-- [123456789] = true,
}

-- ---------------------------------------------------------------------------
-- Public helpers
-- ---------------------------------------------------------------------------

-- Returns true if the player is on the admin list.
function AdminHandler.IsAdmin(player: Player): boolean
	return ADMIN_USER_IDS[player.UserId] == true
end

-- ---------------------------------------------------------------------------
-- Command dispatch
-- ---------------------------------------------------------------------------

-- Extend this table with command → handler mappings.
-- Each handler receives (adminPlayer, args: {any}).
local commands: {[string]: (player: Player, args: {any}) -> ()} = {
	-- Example: /givecash <targetName> <amount>
	-- ["givecash"] = function(admin, args)
	--     local targetName = args[1]
	--     local amount = tonumber(args[2]) or 0
	--     local target = Players:FindFirstChild(targetName)
	--     if target then DataService.Increment(target, "cash", amount) end
	-- end,

	-- TODO: add your commands here
}

local function handleCommand(player: Player, payload: {command: string, args: {any}})
	if not AdminHandler.IsAdmin(player) then
		warn("[AdminHandler] Non-admin attempted command:", player.Name, payload.command)
		return
	end
	local handler = commands[payload.command]
	if handler then
		local ok, err = pcall(handler, player, payload.args or {})
		if not ok then
			warn("[AdminHandler] Command error:", payload.command, err)
		end
	else
		warn("[AdminHandler] Unknown command:", payload.command)
	end
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function AdminHandler:Initialize()
	print("[AdminHandler] initialized.")

	-- TODO: connect the AdminCommand bridge here once it's defined.
	-- Example (requires networking-specialist to create the bridge first):
	--
	-- local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
	-- Bridges.AdminCommand:Connect(function(player, payload)
	--     -- Validate payload shape before dispatch (never trust client input).
	--     if type(payload) ~= "table" or type(payload.command) ~= "string" then return end
	--     task.spawn(handleCommand, player, payload)
	-- end)
end

return AdminHandler
