--[[
	JANITOR
	-------
	Re-export of the loleris Janitor Wally package.

	Provides a stable require path so handlers and controllers can use:
	    local Janitor = require(ReplicatedStorage.Utility.Janitor)
	instead of the full Wally package path.
--]]

return require(game:GetService("ReplicatedStorage").Packages.Janitor)
