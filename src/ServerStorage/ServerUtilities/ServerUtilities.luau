-- ServerUtilities
-- ---------------
-- Grab-bag of small server-side helper functions shared across handlers.
-- Keep this file thin. Domain-specific logic belongs in its own handler.

local ServerUtilities = {}

-- Returns true if the value is a plain (non-mixed) array (no string keys, no gaps).
-- Useful before inserting data into ProfileStore — arrays must be clean.
function ServerUtilities.IsArray(t: {any}): boolean
	if type(t) ~= "table" then return false end
	local count = 0
	for _ in pairs(t) do count += 1 end
	return count == #t
end

-- Shallow-copies a table. Does not recurse into nested tables.
function ServerUtilities.ShallowCopy(t: {any}): {any}
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	return copy
end

-- TODO: add project-specific utilities here

return ServerUtilities
