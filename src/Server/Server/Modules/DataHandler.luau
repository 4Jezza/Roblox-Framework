--[[
	DataHandler
	-----------
	Creates and refreshes player leaderstats. Exposes helpers for reading and
	mutating common player data keys (cash, wins).

	To add more stats:
	  1. Add the field to DataService's DATA_TEMPLATE
	  2. Create a stat Value instance in createLeaderstats()
	  3. Update updateStats() to refresh it
	  4. Add Get/Give/Set helpers below if other handlers need them
]]

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(ServerStorage.ServerUtilities.DataService)

local DataHandler = {}

-- ---------------------------------------------------------------------------
-- Leaderstats
-- ---------------------------------------------------------------------------

local function createLeaderstats(player: Player)
	local data = DataService.GetData(player)
	if not data then return end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- Wins — placeholder primary stat. Replace with your game's main ranking key.
	local winsStat = Instance.new("IntValue")
	winsStat.Name  = "Wins"
	winsStat.Value = data.wins or 0
	winsStat.Parent = leaderstats

	-- TODO: Add more stats here, e.g.:
	-- local cashStat = Instance.new("IntValue")
	-- cashStat.Name  = "Cash"
	-- cashStat.Value = data.cash or 0
	-- cashStat.Parent = leaderstats

	-- Refresh loop — lightweight polling every 2 seconds.
	-- Replace with SignalBank signal listeners if you want immediate updates.
	local function updateStats()
		local d = DataService.GetData(player)
		if not d then return end
		winsStat.Value = d.wins or 0
		-- TODO: update additional stats here
	end

	task.spawn(function()
		while player.Parent do
			task.wait(2)
			updateStats()
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public helpers
-- ---------------------------------------------------------------------------

function DataHandler.GetWins(player: Player): number
	return DataService.Get(player, "wins") or 0
end

function DataHandler.AddWin(player: Player)
	return DataService.Increment(player, "wins", 1)
end

function DataHandler.GetCash(player: Player): number
	return DataService.Get(player, "cash") or 0
end

function DataHandler.GiveCash(player: Player, amount: number)
	-- TODO: apply rebirth multiplier or other modifiers here
	return DataService.Increment(player, "cash", amount)
end

function DataHandler.TakeCash(player: Player, amount: number)
	return DataService.Increment(player, "cash", -amount)
end

function DataHandler.HasEnoughCash(player: Player, amount: number): boolean
	return DataHandler.GetCash(player) >= amount
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function DataHandler:Initialize()
	-- Create leaderstats as soon as each player's data is ready.
	DataService.OnDataLoaded(function(player: Player, _data)
		createLeaderstats(player)
	end)

	-- TODO: connect to Players.PlayerRemoving here if you need to clean up
	-- any per-player tables maintained by DataHandler.
end

return DataHandler
