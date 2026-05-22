--[[
	PlayerStateController
	---------------------
	Single-source-of-truth singleton for the current player's coarse-grained
	state. UI bindings and gameplay code MUST consult this controller before
	opening a frame or running an action — never invent ad-hoc booleans.

	A *state* is one named bucket of allow/deny rules for two kinds of ids:
	    "frame"  — a UI surface (e.g. "Shop", "Settings").
	    "action" — a gameplay verb (e.g. "OpenContainer", "Jump").

	Rule resolution:
	    1. DeniedX listed   -> false (deny wins).
	    2. AllowedX is nil  -> true  (nil = wildcard).
	    3. AllowedX listed  -> membership check.
	    4. AllowedX = {}    -> false (explicit lock-everything).

	Public API:
	    PlayerStateController:Register(def: StateDef)
	    PlayerStateController:Set(stateName: string)
	    PlayerStateController:Get() -> string
	    PlayerStateController:IsAllowed(kind: "frame"|"action", id: string) -> boolean
	    PlayerStateController.Changed: Signal<prev: string, next: string>

	Sequence integration:
	    `:Set` is fully synchronous — no yields, no Janitor wiring at this layer.
	    That means it composes cleanly inside a `Sequence:Step(...)`:
	        Sequence.new()
	            :Step(function() PlayerStateController:Set("InCutscene") end)
	            :Wait(2)
	            :Step(function() PlayerStateController:Set("Idle") end)
	            :Run()

	Per `.claude/reference/architecture.md` § Require Paths (Knit, Signal).
	Per `.claude/reference/api-reference.md` § 3.2 Signal — lowercase `Signal.new()`.
	Per `.claude/reference/api-reference.md` § 3.9 Sequence — synchronous-step composition.
	Per `docs/conventions.md` § Module file structure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local PlayerState = require(ReplicatedStorage.Utility.PlayerState)

type StateDef = PlayerState.StateDef
type AllowKind = "frame" | "action"

local PlayerStateController = Knit.CreateController({
	Name = "PlayerStateController",
})

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local DEFAULT_STATE = "Idle"

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Linear membership check on a string list. Lists are tiny (state defs in
-- practice list <10 entries) so a hash table is overkill.
local function listContains(list: { string }?, id: string): boolean
	if list == nil then
		return false
	end
	for _, entry in ipairs(list) do
		if entry == id then
			return true
		end
	end
	return false
end

-- Resolves whether `id` is allowed given a (allowed, denied) pair.
-- See header rule resolution table.
local function resolveAllow(allowed: { string }?, denied: { string }?, id: string): boolean
	if listContains(denied, id) then
		return false
	end
	if allowed == nil then
		return true
	end
	return listContains(allowed, id)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	PlayerStateController:Register(def)
	    Registers a StateDef. Throws on duplicate Name or malformed def — this
	    is a programmer error, not a runtime condition, so it should be loud.
]]
function PlayerStateController:Register(def: StateDef)
	local ok, err = PlayerState.ValidateDef(def)
	if not ok then
		error("[PlayerStateController] invalid StateDef — " .. tostring(err), 2)
	end
	if self._states[def.Name] then
		error("[PlayerStateController] duplicate state '" .. def.Name .. "' — Register called twice", 2)
	end
	self._states[def.Name] = def
end

--[[
	PlayerStateController:Set(stateName)
	    Transitions to `stateName`. No-op if already in that state. Otherwise:
	        1. Call current state's OnExit(prev = current).
	        2. Swap self._current to the new name.
	        3. Fire self.Changed:Fire(prevName, newName).
	        4. Call new state's OnEnter(prev = oldName).
	    All synchronous — never yields. If `stateName` is unregistered, warn
	    and ignore (per rule_8 defensive logging).
]]
function PlayerStateController:Set(stateName: string)
	if typeof(stateName) ~= "string" then
		warn("[PlayerStateController] missing valid state name at :Set — ignored")
		return
	end

	local nextDef = self._states[stateName]
	if not nextDef then
		warn("[PlayerStateController] missing state '" .. stateName .. "' at :Set — ignored, staying in '" .. self._current .. "'")
		return
	end

	local prevName = self._current
	if prevName == stateName then
		return
	end

	local prevDef = self._states[prevName]

	-- 1. Exit hook on outgoing state.
	if prevDef and prevDef.OnExit then
		local exitOk, exitErr = pcall(prevDef.OnExit, stateName)
		if not exitOk then
			warn("[PlayerStateController] OnExit threw for state '" .. prevName .. "' — " .. tostring(exitErr))
		end
	end

	-- 2. Swap current.
	self._current = stateName

	-- 3. Fire Changed signal so external observers can react.
	self.Changed:Fire(prevName, stateName)

	-- 4. Enter hook on incoming state.
	if nextDef.OnEnter then
		local enterOk, enterErr = pcall(nextDef.OnEnter, prevName)
		if not enterOk then
			warn("[PlayerStateController] OnEnter threw for state '" .. stateName .. "' — " .. tostring(enterErr))
		end
	end
end

--[[
	PlayerStateController:Get()
	    Returns the current state name. Always populated post-KnitInit.
]]
function PlayerStateController:Get(): string
	return self._current
end

--[[
	PlayerStateController:IsAllowed(kind, id)
	    Returns whether the given `id` is allowed under the current state's
	    rules. `kind` must be "frame" or "action". Unknown kinds warn + return
	    false (fail closed — better to block a feature than to leak one open).
]]
function PlayerStateController:IsAllowed(kind: AllowKind, id: string): boolean
	if typeof(id) ~= "string" then
		warn("[PlayerStateController] missing valid id at :IsAllowed — returning false")
		return false
	end

	local def = self._states[self._current]
	if not def then
		-- Should never happen — current is always a registered state. Log and
		-- fail closed.
		warn("[PlayerStateController] missing def for current state '" .. self._current .. "' — returning false")
		return false
	end

	if kind == "frame" then
		return resolveAllow(def.AllowedFrames, def.DeniedFrames, id)
	elseif kind == "action" then
		return resolveAllow(def.AllowedActions, def.DeniedActions, id)
	end

	warn("[PlayerStateController] unknown kind '" .. tostring(kind) .. "' at :IsAllowed — returning false")
	return false
end

-- ---------------------------------------------------------------------------
-- Built-in states
-- ---------------------------------------------------------------------------

-- Registered in KnitInit so the controller boots in a known state. Conventions
-- documented per state below — future features extend AllowedFrames /
-- DeniedActions on these as they land.
local function registerBuiltInStates(self)
	-- Default after boot. No restrictions — everything is allowed.
	self:Register({
		Name = "Idle",
	})

	-- Player is paging through menus. Gameplay actions involving in-world
	-- containers should be gated; UI surfaces are unrestricted.
	self:Register({
		Name = "InMenu",
		DeniedActions = { "OpenContainer" },
	})

	-- Player is actively playing. Menu-type frames stay closed; gameplay
	-- actions are unrestricted.
	self:Register({
		Name = "InGame",
		DeniedFrames = { "Shop", "Settings" },
	})

	-- Cinematic playing. Lock everything — empty whitelists are explicit
	-- "deny all" per the rule resolution table.
	self:Register({
		Name = "InCutscene",
		AllowedFrames = {},
		AllowedActions = {},
	})

	-- Initial loading screen. Locked until LoadingScreen explicitly transitions
	-- to Idle on completion.
	self:Register({
		Name = "Loading",
		AllowedFrames = {},
		AllowedActions = {},
	})
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function PlayerStateController:KnitInit()
	self._states = {} :: { [string]: StateDef }
	self._current = DEFAULT_STATE
	self.Changed = Signal.new()

	registerBuiltInStates(self)

	-- Sanity: DEFAULT_STATE must exist after built-in registration.
	if not self._states[DEFAULT_STATE] then
		error("[PlayerStateController] default state '" .. DEFAULT_STATE .. "' missing after built-in registration", 2)
	end
end

function PlayerStateController:KnitStart()
	print("[PlayerStateController] initialised, current state: " .. self._current)
end

return PlayerStateController
