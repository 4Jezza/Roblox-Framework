--[[
	DataService
	-----------
	Wrapper around Mad Studio Replica (vendored, see src/Server/ReplicaServer.luau)
	+ ProfileStore that exposes a stable API surface. Handler code that calls
	DataService.X is portable between projects regardless of the underlying
	replica engine.

	The underlying Replica library is NOT on Wally — it's vendored directly into
	src/Shared/ReplicaShared, src/Shared/ReplicaClient.luau, and
	src/Server/ReplicaServer.luau. See wally.toml for the provenance note.

	Public API:
	  DataService.Init()
	  DataService.GetData(player)
	  DataService.Get(player, key)
	  DataService.Set(player, key, value)
	  DataService.Update(player, key, callback)
	  DataService.Increment(player, key, amount)
	  DataService.SetPath(player, path, value)
	  DataService.WaitForData(player)
	  DataService.OnDataLoaded(callback)
	  DataService.OnBeforeSave(callback)
	  DataService.OnProfileSave(callback)
	  DataService.SyncPlayerData(player)
	  DataService.GetProfile(player)
	  DataService.GetReplica(player)

	Leaving-race fallback
	---------------------
	OnPlayerRemoving clears playerReplicas[player] BEFORE profile:EndSession() runs.
	If a Set/Update/SetPath fires during that window, the replica path would silently
	return false. The fallback writes directly into profile.Data so the value lands
	in the next ProfileStore save.
--]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage      = game:GetService("ServerStorage")

local ProfileStore = require(ServerScriptService.Server.Packages.ProfileStore)
local Signal       = require(ReplicatedStorage.Packages.Signal)
local SignalBank   = require(ServerStorage.ServerUtilities.SignalBank)

-- Mad Studio Replica (vendored at src/Server/ReplicaServer.luau).
local Replica = require(ServerScriptService.ReplicaServer)

-- ---------------------------------------------------------------------------
-- IMPORTANT: NEVER rename this key — it controls which DataStore is used.
-- Renaming it is equivalent to wiping all player data.
-- ---------------------------------------------------------------------------
local DATASTORE_NAME = "BoilerplateData_LIVE_1"

-- Minimal starting template. Add fields here as your game grows.
-- Rules for values: serializable only — no Instances, no Vector3/CFrame,
-- no userdata, no gaps in arrays.
local DATA_TEMPLATE = {
	cash      = 0,
	wins      = 0,
	inventory = {},
	-- TODO: add more fields as your game grows (e.g. level, experience, settings).
}

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------
local DataService = {}

-- Mad Studio Replica uses a Token object (not a string class name).
local PlayerDataToken = Replica.Token("PlayerData")

local PlayerStore          = nil          -- set in Init()
local profiles             = {}           -- [Player] = Profile
local playerReplicas       = {}           -- [Player] = Replica
local pendingReadyConns    = {}           -- [Player] = Signal.Connection waiting on NewReadyPlayer
local dataLoadedSignal     = Signal.new() -- fired after profile + replica ready
local beforeSaveCallbacks  = {}           -- [(player) -> ()] run before every save
local profileSaveCallbacks = {}           -- [(player) -> ()] run on ProfileStore OnSave
local removingPlayers      = {}           -- [Player] = true (de-dup guard)
local savedPlayers         = {}           -- [UserId] = true (beforeSave ran during removing)

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Fire per-key signals so other handlers can react to data changes.
-- Add more keys here as SignalBank grows.
local function fireSignals(_player: Player, _key: string, _value: any)
	-- Add mappings like:
	--   if key == "cash" then SignalBank.CashChanged:Fire(player, value) end
	-- once the corresponding SignalBank entries exist.
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DataService.Init()
	PlayerStore = ProfileStore.New(DATASTORE_NAME, DATA_TEMPLATE)

	Players.PlayerAdded:Connect(function(player)
		DataService.OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.OnPlayerRemoving(player)
	end)

	-- Handle players already in-game (Studio play-test).
	for _, player in Players:GetPlayers() do
		task.spawn(DataService.OnPlayerAdded, player)
	end

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(DataService.OnPlayerRemoving, player)
		end
		-- Wait up to 25 seconds for profiles to release before shutdown.
		local timeout = os.clock() + 25
		while next(profiles) ~= nil and os.clock() < timeout do
			task.wait(0.1)
		end
	end)
end

function DataService.OnPlayerAdded(player: Player)
	local profile = PlayerStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if not profile then
		player:Kick("Failed to load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player]           = nil
		savedPlayers[player.UserId] = nil
		removingPlayers[player]    = nil
		-- Safety net: also drop any pending NewReadyPlayer conn here in case
		-- OnPlayerRemoving never ran (shouldn't normally happen).
		local pendingConn = pendingReadyConns[player]
		if pendingConn then
			pendingConn:Disconnect()
			pendingReadyConns[player] = nil
		end
		if player.Parent then
			player:Kick("Data session ended. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	-- Create the Mad Studio Replica. Selective replication happens after we
	-- know the owning player is ready (RequestData has arrived).
	local replica = Replica.New({
		Token = PlayerDataToken,
		Tags  = { UserId = player.UserId },
		Data  = profile.Data,
	})
	playerReplicas[player] = replica

	if Replica.ReadyPlayers[player] then
		replica:Subscribe(player)
	else
		local conn
		conn = Replica.NewReadyPlayer:Connect(function(readyPlayer)
			if readyPlayer == player then
				conn:Disconnect()
				pendingReadyConns[player] = nil
				-- Double-check the replica hasn't been destroyed between
				-- creation and the player's data request arriving.
				if playerReplicas[player] == replica then
					replica:Subscribe(player)
				end
			end
		end)
		-- Track so OnPlayerRemoving can disconnect if the player leaves
		-- before their RequestData remote ever fires (connection leak fix).
		pendingReadyConns[player] = conn
	end

	profile.OnSave:Connect(function()
		-- Skip if OnPlayerRemoving already ran beforeSaveCallbacks for this session.
		if not savedPlayers[player.UserId] then
			for _, callback in ipairs(beforeSaveCallbacks) do
				local ok, err = pcall(callback, player)
				if not ok then
					warn("[DataService] OnBeforeSave callback error (OnSave):", err)
				end
			end
		end
		for _, callback in ipairs(profileSaveCallbacks) do
			local ok, err = pcall(callback, player)
			if not ok then
				warn("[DataService] OnProfileSave callback error:", err)
			end
		end
	end)

	profiles[player] = profile
	SignalBank.DataLoaded:Fire(player, profile.Data)
	dataLoadedSignal:Fire(player, profile.Data)
end

function DataService.OnPlayerRemoving(player: Player)
	if removingPlayers[player] then return end
	removingPlayers[player] = true

	if profiles[player] then
		for _, callback in ipairs(beforeSaveCallbacks) do
			local ok, err = pcall(callback, player)
			if not ok then
				warn("[DataService] OnBeforeSave callback error (removing):", err)
			end
		end
		savedPlayers[player.UserId] = true
	end

	-- Clean up any pending NewReadyPlayer subscription for this player to
	-- prevent a connection leak on the module-wide NewReadyPlayer signal.
	local pendingConn = pendingReadyConns[player]
	if pendingConn then
		pendingConn:Disconnect()
		pendingReadyConns[player] = nil
	end

	local replica = playerReplicas[player]
	if replica then
		replica:Destroy()
		playerReplicas[player] = nil
	end

	local profile = profiles[player]
	if profile then
		profile:EndSession()
		-- profiles[player] is cleared by OnSessionEnd, not here, to avoid races.
	end
end

function DataService.SyncPlayerData(player: Player)
	for _, callback in ipairs(beforeSaveCallbacks) do
		local ok, err = pcall(callback, player)
		if not ok then
			warn("[DataService] OnBeforeSave callback error (sync):", err)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Readers
-- ---------------------------------------------------------------------------

function DataService.GetProfile(player: Player)
	return profiles[player]
end

function DataService.GetData(player: Player): { [string]: any }?
	local profile = profiles[player]
	if profile then return profile.Data end
	return nil
end

function DataService.Get(player: Player, key: string): any
	local data = DataService.GetData(player)
	if data then return data[key] end
	return nil
end

function DataService.GetReplica(player: Player): any?
	return playerReplicas[player]
end

-- Yield until the player's profile is loaded, then return their data table.
-- Returns nil if the player leaves before their data loads.
function DataService.WaitForData(player: Player): { [string]: any }?
	if profiles[player] then
		return profiles[player].Data
	end
	repeat
		task.wait(0.1)
	until profiles[player] or not player.Parent
	if profiles[player] then
		return profiles[player].Data
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Writers
-- ---------------------------------------------------------------------------

function DataService.Set(player: Player, key: string, value: any): boolean
	local replica = playerReplicas[player]
	if replica then
		-- Mad Studio Replica takes a path array, even for single keys.
		replica:Set({ key }, value)
		fireSignals(player, key, value)
		return true
	end
	-- Leaving-race fallback: replica is destroyed but profile may still be live.
	local profile = profiles[player]
	if profile then
		profile.Data[key] = value
		fireSignals(player, key, value)
		return true
	end
	return false
end

function DataService.Update(player: Player, key: string, callback: (old: any) -> any): any
	local replica = playerReplicas[player]
	if replica then
		local newValue = callback(replica.Data[key])
		replica:Set({ key }, newValue)
		fireSignals(player, key, newValue)
		return newValue
	end
	local profile = profiles[player]
	if profile then
		local newValue = callback(profile.Data[key])
		profile.Data[key] = newValue
		fireSignals(player, key, newValue)
		return newValue
	end
	return nil
end

function DataService.Increment(player: Player, key: string, amount: number): number?
	return DataService.Update(player, key, function(old)
		return (old or 0) + amount
	end)
end

-- SetPath writes a value at an arbitrary nested path inside the player's data.
-- path: array of string keys, e.g. {"inventory", "slot1"}
function DataService.SetPath(player: Player, path: { string }, value: any): boolean
	local replica = playerReplicas[player]
	if replica then
		replica:Set(path, value)
		return true
	end
	-- Leaving-race fallback: walk profile.Data creating intermediate tables as needed.
	local profile = profiles[player]
	if profile then
		local pointer = profile.Data
		for i = 1, #path - 1 do
			if pointer[path[i]] == nil then
				pointer[path[i]] = {}
			end
			pointer = pointer[path[i]]
		end
		pointer[path[#path]] = value
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Callback registration
-- ---------------------------------------------------------------------------

function DataService.OnDataLoaded(callback: (player: Player, data: { [string]: any }) -> ())
	return dataLoadedSignal:Connect(callback)
end

function DataService.OnBeforeSave(callback: (player: Player) -> ())
	table.insert(beforeSaveCallbacks, callback)
end

function DataService.OnProfileSave(callback: (player: Player) -> ())
	table.insert(profileSaveCallbacks, callback)
end

return DataService
