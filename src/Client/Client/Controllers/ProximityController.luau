--[[
    ProximityController
    -------------------
    Initialises ExpressivePrompts — replaces default Roblox proximity prompt UI
    with animated BillboardGui prompts that avoid the Pesto Professional
    CircularProgressBar.Progress NumberValue bug.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ProximityController = Knit.CreateController {
	Name = "ProximityController",
}

function ProximityController:KnitStart()
	-- Defer to next frame to avoid yield-across-metamethod errors.
	-- ExpressivePrompts.Init() calls game.Loaded:Wait() internally which
	-- can conflict with Knit's Promise chain and ProximityPrompt metamethods.
	task.defer(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
		local ExpressivePrompts = require(ReplicatedStorage.Packages.ExpressivePrompts)
		-- Darken background so prompts are readable over scenery (set BEFORE Init to avoid race)
		ExpressivePrompts.Config.BackgroundTransparency.Value = 0.15
		ExpressivePrompts.Init()
		print("[ProximityController] ExpressivePrompts initialized.")
	end)
end

return ProximityController
