--[[
	PlayerState
	-----------
	Shared types + lightweight helpers for the client-side PlayerState system.

	The runtime singleton lives at
	    src/Client/Client/Controllers/PlayerStateController.luau
	and is the only authority on the *current* state. This module is pure: it
	defines the StateDef shape, provides a registration-time validator, and
	leaves all runtime concerns to the controller. Server code can later mirror
	the same StateDef type by requiring this module.

	A state is a single named bucket of frame/action allow/deny rules. Future
	feature code MUST gate UI opens and gameplay actions through the controller
	rather than inventing ad-hoc booleans.

	Public API:
	    PlayerState.ValidateDef(def: StateDef) -> (ok: boolean, err: string?)

	Per `.claude/reference/architecture.md` § Folder Mapping
	(`src/Shared/Utility/` -> `ReplicatedStorage.Utility`).
	Per `docs/conventions.md` § Module file structure.
]]

local PlayerState = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

--[[
	StateDef
	    Name           — unique identifier, used as the controller key.
	    AllowedFrames  — whitelist of frame ids. nil = allow all frames.
	    DeniedFrames   — blacklist of frame ids. Takes precedence over AllowedFrames.
	    AllowedActions — whitelist of action ids. nil = allow all actions.
	    DeniedActions  — blacklist of action ids. Takes precedence over AllowedActions.
	    OnEnter        — fires after the controller transitions INTO this state
	                     (prev = previous state name or nil for first set).
	    OnExit         — fires before the controller transitions OUT of this state
	                     (next = name we are entering).

	Both hooks are synchronous — never yield inside them.
]]
export type StateDef = {
	Name: string,
	AllowedFrames: { string }?,
	DeniedFrames: { string }?,
	AllowedActions: { string }?,
	DeniedActions: { string }?,
	OnEnter: ((prev: string?) -> ())?,
	OnExit: ((next: string?) -> ())?,
}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Validates a list field is a {string} (or nil). Returns (ok, errMessage).
local function validateStringList(fieldName: string, value: any): (boolean, string?)
	if value == nil then
		return true, nil
	end
	if typeof(value) ~= "table" then
		return false, ("StateDef." .. fieldName .. " must be a table of strings or nil")
	end
	for index, entry in ipairs(value) do
		if typeof(entry) ~= "string" then
			return false,
				("StateDef." .. fieldName .. "[" .. tostring(index) .. "] must be a string, got " .. typeof(entry))
		end
	end
	return true, nil
end

-- Validates a hook field is a function (or nil).
local function validateHook(fieldName: string, value: any): (boolean, string?)
	if value == nil then
		return true, nil
	end
	if typeof(value) ~= "function" then
		return false, ("StateDef." .. fieldName .. " must be a function or nil, got " .. typeof(value))
	end
	return true, nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	PlayerState.ValidateDef(def)
	    Cheap structural validation for a StateDef. Call this at registration
	    time so the controller fails loudly on misshapen definitions instead of
	    silently misbehaving at runtime.

	    Returns:
	        (true, nil)         on success
	        (false, errMessage) describing the first problem found
]]
function PlayerState.ValidateDef(def: StateDef): (boolean, string?)
	if typeof(def) ~= "table" then
		return false, "StateDef must be a table"
	end
	if typeof(def.Name) ~= "string" or #def.Name == 0 then
		return false, "StateDef.Name must be a non-empty string"
	end

	local checks: { { name: string, value: any, kind: string } } = {
		{ name = "AllowedFrames", value = def.AllowedFrames, kind = "list" },
		{ name = "DeniedFrames", value = def.DeniedFrames, kind = "list" },
		{ name = "AllowedActions", value = def.AllowedActions, kind = "list" },
		{ name = "DeniedActions", value = def.DeniedActions, kind = "list" },
		{ name = "OnEnter", value = def.OnEnter, kind = "hook" },
		{ name = "OnExit", value = def.OnExit, kind = "hook" },
	}

	for _, check in ipairs(checks) do
		local ok, err
		if check.kind == "list" then
			ok, err = validateStringList(check.name, check.value)
		else
			ok, err = validateHook(check.name, check.value)
		end
		if not ok then
			return false, err
		end
	end

	return true, nil
end

return PlayerState
