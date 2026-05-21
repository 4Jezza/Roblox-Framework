--[[
	SPRING
	------
	Re-export of the Spring Wally package.

	Provides a stable require path so handlers and controllers can use:
	    local Spring = require(ReplicatedStorage.Utility.Spring)
	instead of the full Wally package path.

	Use Springs for all 3D animations (part movement, scale, highlights).
	Only fall back to TweenService for one-shot fire-and-forget cases where
	spring polling would be wasteful (e.g. a single transparency fade on a
	temporary instance).
--]]

return require(game:GetService("ReplicatedStorage").Packages.Spring)
