--[[
	ReplicaController
	-----------------
	Knit Controller. Centralises client-side subscriptions to NON-PlayerData replicas
	(world state, entity state, shared multiplayer state). The local player's PlayerData
	replica is already handled by src/Shared/Utility/PlayerData.luau — do not use this
	controller for that token.

	Public API
	----------
	ReplicaController:OnReplicaNew(token, listener) -> {Disconnect}
	    Register a listener that fires whenever a replica of `token` arrives.
	    Also fires for replicas that already exist (deferred, per Replica.OnNew semantics).

	ReplicaController:GetReplicasByToken(token) -> {Replica}
	    Live snapshot of all currently-active replicas for the given token.

	ReplicaController:CleanupToken(token)
	    Drop all per-token listeners and cached replica references for `token`.

	VISUAL / ANIMATION POLICY (canonical reference: architecture.md § Visual/Animation Policy)
	Visuals + animations are CLIENT-FIRST.
	- Client plays the effect/animation immediately on local input AND on Replica
	  subscription. No round-trip wait for "looks good".
	- Server is the source of TRUTH. It validates every action and publishes the
	  authoritative state via Replica.
	- Client receives the authoritative state and reconciles its local visuals
	  (snap, correct, or smooth-blend) if they diverged.
	- NEVER block visual feedback waiting on a server response.
	- NEVER let a client visual flag drive a server-side rule.

	WorldAnimator consumes this controller's :OnReplicaNew to drive world
	animations (hovering models, glowing parts, etc.) — see WorldAnimator/init.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Replica = require(ReplicatedStorage.ReplicaClient)

-- Per api-reference.md § 2.3: use Replica.OnNew / replica:OnSet / replica:OnChange.
-- "ListenToChange" does NOT exist in Mad Studio Replica client.

local ReplicaController = Knit.CreateController {
	Name = "ReplicaController",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Map: token string -> array of active Replica objects
ReplicaController._replicasByToken = {} :: { [string]: { any } }

-- Map: token string -> Janitor that owns all listener connections for that token
ReplicaController._tokenJanitors = {} :: { [string]: any }

-- Controller-scope janitor; cleaned if the controller is ever torn down
ReplicaController._janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

--- Ensure the internal tables for `token` exist, return the Janitor for that token.
local function _ensureToken(self, token: string): any
	if not self._replicasByToken[token] then
		self._replicasByToken[token] = {}
	end

	if not self._tokenJanitors[token] then
		local tj = Janitor.new()
		self._tokenJanitors[token] = tj
		-- Register the token janitor as a child of the controller janitor so a
		-- full controller teardown also cleans every token.
		self._janitor:Add(tj, "Destroy", "token_" .. token)
	end

	return self._tokenJanitors[token]
end

--- Remove a replica from the _replicasByToken array for `token`.
local function _pruneReplica(self, token: string, replica: any)
	local arr = self._replicasByToken[token]
	if not arr then
		return
	end
	for i = #arr, 1, -1 do
		if arr[i] == replica then
			table.remove(arr, i)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Register a listener that fires whenever a new replica of `token` arrives.
--- Fires for replicas that already exist (deferred replay, per Replica.OnNew).
--- Returns a connection table with a Disconnect() method.
--- No yield inside `listener` — fire a Signal or task.spawn for async work.
function ReplicaController:OnReplicaNew(token: string, listener: (replica: any) -> ()): { Disconnect: () -> () }
	if type(token) ~= "string" or #token == 0 then
		warn("[ReplicaController] OnReplicaNew — token must be a non-empty string; got: " .. tostring(token))
		return { Disconnect = function() end }
	end

	if type(listener) ~= "function" then
		warn("[ReplicaController] OnReplicaNew — listener must be a function for token: " .. token)
		return { Disconnect = function() end }
	end

	local tokenJanitor = _ensureToken(self, token)

	-- Replica.OnNew returns a Connection per api-reference.md § 2.3
	local conn = Replica.OnNew(token, function(replica)
		-- Track the replica while it is alive
		local arr = self._replicasByToken[token]
		if not arr then
			warn("[ReplicaController] _replicasByToken missing for token: " .. token .. " — skipping cache")
		else
			table.insert(arr, replica)

			-- Prune when the Maid cleans up (replica destroyed)
			-- Per api-reference.md § 2.3: replica.Maid is the auto-cleaned Maid.
			local maidOk = pcall(function()
				replica.Maid:Add(function()
					_pruneReplica(self, token, replica)
				end)
			end)
			if not maidOk then
				warn("[ReplicaController] Could not bind Maid cleanup for token: " .. token .. " — replica will not be pruned on destroy")
			end
		end

		-- Invoke the caller's listener; no yield permitted here.
		local ok, err = pcall(listener, replica)
		if not ok then
			warn("[ReplicaController] Listener error for token: " .. token .. " — " .. tostring(err))
		end
	end)

	if not conn then
		warn("[ReplicaController] Replica.OnNew returned nil for token: " .. token .. " — ReplicaClient may not be ready; call RequestData first")
		return { Disconnect = function() end }
	end

	-- Track the Replica.OnNew connection under this token's janitor
	tokenJanitor:Add(conn, "Disconnect", conn)

	return {
		Disconnect = function()
			local ok = pcall(function() conn:Disconnect() end)
			if not ok then
				warn("[ReplicaController] Disconnect error for token: " .. token)
			end
			tokenJanitor:RemoveNoClean(conn)
		end,
	}
end

--- Returns a live snapshot (copy) of all currently-active replicas for `token`.
--- The returned array is a shallow copy — mutating it does not affect internal state.
function ReplicaController:GetReplicasByToken(token: string): { any }
	if type(token) ~= "string" or #token == 0 then
		warn("[ReplicaController] GetReplicasByToken — token must be a non-empty string; got: " .. tostring(token))
		return {}
	end

	local arr = self._replicasByToken[token]
	if not arr then
		return {}
	end

	-- Return a shallow copy so the caller cannot accidentally mutate the live array.
	local snapshot = table.create(#arr)
	for i, v in ipairs(arr) do
		snapshot[i] = v
	end
	return snapshot
end

--- Drop all listeners and cached replica references for `token`.
--- After this call, existing :OnReplicaNew connections for this token are dead.
function ReplicaController:CleanupToken(token: string)
	if type(token) ~= "string" or #token == 0 then
		warn("[ReplicaController] CleanupToken — token must be a non-empty string; got: " .. tostring(token))
		return
	end

	local tj = self._tokenJanitors[token]
	if tj then
		tj:Destroy()
		self._janitor:RemoveNoClean("token_" .. token)
		self._tokenJanitors[token] = nil
	end

	self._replicasByToken[token] = nil
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function ReplicaController:KnitInit()
	-- Nothing to initialise before Start; tables are already allocated above.
end

function ReplicaController:KnitStart()
	-- Replica.RequestData() is idempotent (per api-reference.md § 2.3) — safe to call
	-- even if PlayerData.Init() already called it.
	local ok, err = pcall(function()
		Replica.RequestData()
	end)
	if not ok then
		warn("[ReplicaController] Replica.RequestData() failed — " .. tostring(err) .. " — world-state replicas may not arrive until the next data flush")
	end
end

return ReplicaController
