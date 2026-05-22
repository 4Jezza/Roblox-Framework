--[[
	CLIENT BOOT
	-----------
	Location in Studio: StarterPlayer.StarterPlayerScripts.Client

	Auto-loads all Knit Controllers from Controllers/ then starts Knit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit   = require(ReplicatedStorage.Packages.Knit)
local Loader = require(ReplicatedStorage.Packages.Loader)

-- Auto-load all Knit Controllers from Controllers/ folder
Loader.LoadDescendants(script.Controllers)

Knit.Start({ ServicePromises = false }):catch(warn):await()
print("[Client] Knit started.")
