--[[
	WorldEntityHandler
	------------------
	Creates and manages "WorldEntity" replicas — non-PlayerData world state that
	ReplicaController + WorldAnimator consume on the client.

	Public API:
	  WorldEntityHandler:Initialize()
	  WorldEntityHandler.Spawn(instance, kind, data?)  -> Replica
	  WorldEntityHandler.Despawn(instance)
	  WorldEntityHandler.Update(instance, path, value)

	Per architecture.md § Critical Bans:
	  - Replica.Token declared once at module scope.
	  - No direct ProfileStore / Replica calls outside DataService for player data.
	    These replicas are WORLD state, not player-profile state, so direct
	    Replica.New is intentional here (the DataService wrapper is per-player only).
	  - Per api-reference.md § 2.2: Replica.New -> :BindToInstance -> :Replicate.
]]

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Mad Studio Replica (vendored). Server-side only.
-- Path per architecture.md § Require Paths + DataService.luau precedent.
local Replica = require(ServerScriptService.ReplicaServer)

local WorldEntityHandler = {}

-- ---------------------------------------------------------------------------
-- Module-private token — declared once (duplicate Token() throws per api-reference.md § 2.2).
-- Typed as `any` to avoid calling Replica.Token("") at type-check time, which would
-- register an empty-string token and potentially interfere with runtime registration.
-- ---------------------------------------------------------------------------
local TOKEN: any = nil

-- ---------------------------------------------------------------------------
-- Instance -> Replica map
-- Keyed by world Instance, not by UserId — no per-player cleanup needed here.
-- Players.PlayerRemoving is hooked below with a TODO for future per-player entities.
-- ---------------------------------------------------------------------------
local entities: { [Instance]: any } = {}

-- ---------------------------------------------------------------------------
-- Instance -> Destroying connection map
-- Tracked so public Despawn() can disconnect the listener and not leak the
-- RBXScriptConnection if Despawn is called before Instance.Destroying fires.
-- ---------------------------------------------------------------------------
local destroyingConns: { [Instance]: RBXScriptConnection } = {}

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

--- Creates a WorldEntity replica bound to `instance`.
--- Idempotent: if a replica already exists for `instance`, warns and returns it.
---@param instance Instance  The world instance to bind the replica to.
---@param kind     string    Token tag passed as Tags.Kind — used by ReplicaController.
---@param data     table?    Initial data table. Defaults to {}.
---@return Replica
function WorldEntityHandler.Spawn(instance: Instance, kind: string, data: {}?): any
	-- Guard: idempotent
	if entities[instance] then
		warn(
			"[WorldEntityHandler] Spawn called on already-tracked instance '"
				.. instance.Name
				.. "' — returning existing replica"
		)
		return entities[instance]
	end

	-- Structural validation — both callers on the server are trusted, but we
	-- still gate on basic types so a future bridge-driven path fails loudly.
	if typeof(instance) ~= "Instance" then
		error("[WorldEntityHandler] Spawn: `instance` must be an Instance, got " .. typeof(instance))
	end
	if type(kind) ~= "string" or kind == "" then
		error("[WorldEntityHandler] Spawn: `kind` must be a non-empty string")
	end

	-- Per api-reference.md § 2.2: Token -> New -> BindToInstance -> Replicate.
	local replica = Replica.New({
		Token = TOKEN,
		Tags  = { Kind = kind },
		Data  = data or {},
	})

	replica:BindToInstance(instance)
	replica:Replicate()

	entities[instance] = replica

	-- Auto-despawn when the instance is destroyed (e.g. model removed from workspace).
	-- Track the connection so public Despawn() can disconnect it (Approach A — per api-reference.md § 3.1).
	destroyingConns[instance] = instance.Destroying:Connect(function()
		if entities[instance] then
			entities[instance]:Destroy()
			entities[instance] = nil
		end
		destroyingConns[instance] = nil
	end)

	return replica
end

-- ---------------------------------------------------------------------------
-- Despawn
-- ---------------------------------------------------------------------------

--- Destroys the replica bound to `instance` and removes it from tracking.
--- No-op with a warn if `instance` was never spawned.
function WorldEntityHandler.Despawn(instance: Instance)
	local replica = entities[instance]
	if not replica then
		warn(
			"[WorldEntityHandler] Despawn: no replica found for instance '"
				.. tostring(instance)
				.. "' — ignoring"
		)
		return
	end

	replica:Destroy()
	entities[instance] = nil

	-- Disconnect the Destroying listener if it hasn't fired yet (Approach A).
	local conn = destroyingConns[instance]
	if conn then
		conn:Disconnect()
		destroyingConns[instance] = nil
	end
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------

--- Mutates a path on the bound replica via replica:Set.
--- Per api-reference.md § 2.2: replica:Set(path, value).
function WorldEntityHandler.Update(instance: Instance, path: { string }, value: any)
	local replica = entities[instance]
	if not replica then
		warn(
			"[WorldEntityHandler] Update: no replica found for instance '"
				.. tostring(instance)
				.. "' — ignoring (path="
				.. table.concat(path, ".")
				.. ")"
		)
		return
	end

	replica:Set(path, value)
end

-- ---------------------------------------------------------------------------
-- Initialize
-- ---------------------------------------------------------------------------

function WorldEntityHandler:Initialize()
	-- Declare token once — per api-reference.md § 2.2 duplicate tokens throw.
	TOKEN = Replica.Token("WorldEntity")

	-- Per architecture.md § Critical Bans (per-player table cleanup):
	-- No per-player entity state exists today, but this hook is intentionally
	-- wired so future per-player WorldEntity variants have a cleanup path.
	-- TODO: if per-player entities are added (e.g. entities keyed by player),
	--       sweep them here on PlayerRemoving.
	Players.PlayerRemoving:Connect(function(_player: Player)
		-- no-op placeholder
	end)
end

return WorldEntityHandler
