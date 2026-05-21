--[[
	PLAYERDATA (client)
	-------------------
	Client-side wrapper around Mad Studio ReplicaClient (vendored at
	src/Shared/ReplicaClient.luau).

	Call PlayerData.Init() once at client startup (e.g. in GameController.KnitStart).
	All other helpers are safe to call immediately after Init().

	Public API
	----------
	PlayerData.Init()                     -- wire up ReplicaClient; call once
	PlayerData.GetData() -> table?        -- synchronous snapshot of replica.Data
	PlayerData.GetReplica() -> replica?   -- raw Replica object (advanced use)
	PlayerData.IsReady() -> boolean       -- true once the replica has arrived
	PlayerData.OnReady(callback)          -- fires immediately if already ready
	PlayerData.WaitForReady() -> replica  -- yields until ready, returns replica
	PlayerData.OnSet(path, callback)      -- listens to a nested key change
	PlayerData.Get(key) -> any            -- shorthand for GetData()[key]
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicaClient = require(ReplicatedStorage.ReplicaClient)

local PlayerData = {}

local playerReplica: any = nil
local readyCallbacks: { (replica: any) -> () } = {}
local isReady = false

-- Wire up the ReplicaClient listener. Call this once before the server starts
-- sending replica data (i.e. before KnitStart yields complete).
function PlayerData.Init()
	ReplicaClient.RequestData()
	ReplicaClient.OnNew("PlayerData", function(replica)
		playerReplica = replica
		isReady = true
		for _, callback in readyCallbacks do
			task.spawn(callback, replica)
		end
		table.clear(readyCallbacks)
	end)
end

-- Synchronous snapshot. Returns nil if the replica has not yet arrived.
function PlayerData.GetData(): { [string]: any }?
	return playerReplica and playerReplica.Data
end

-- Shorthand key lookup.
function PlayerData.Get(key: string): any
	return playerReplica and playerReplica.Data[key]
end

-- Returns the raw Replica object for advanced use.
function PlayerData.GetReplica(): any?
	return playerReplica
end

-- Non-blocking ready check.
function PlayerData.IsReady(): boolean
	return isReady
end

-- Fires `callback(replica)` once the replica is ready.
-- If already ready, fires immediately via task.spawn.
function PlayerData.OnReady(callback: (replica: any) -> ())
	if isReady and playerReplica then
		task.spawn(callback, playerReplica)
	else
		table.insert(readyCallbacks, callback)
	end
end

-- Yields until the replica is ready, then returns it.
function PlayerData.WaitForReady(): any
	if isReady then
		return playerReplica
	end
	repeat
		task.wait(0.05)
	until isReady
	return playerReplica
end

-- Listens to a nested path inside replica.Data via Mad Studio Replica's OnSet.
-- path: array of string keys, e.g. {"cash"} or {"inventory", "slot1"}
-- callback: function(newValue, oldValue)
--
-- Returns the underlying ScriptConnection so the caller can track it in a Janitor.
-- If the replica isn't ready yet, returns nil (the listener is deferred via OnReady).
-- To get a trackable connection in that case, call OnSet from inside an OnReady callback.
function PlayerData.OnSet(path: { string }, callback: (newValue: any, oldValue: any) -> ()): any?
	if not playerReplica then
		PlayerData.OnReady(function(replica)
			replica:OnSet(path, callback)
		end)
		return nil
	end
	return playerReplica:OnSet(path, callback)
end

return PlayerData
