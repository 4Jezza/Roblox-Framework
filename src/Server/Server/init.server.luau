--[[
	SERVER BOOT
	-----------
	Location in Studio: ServerScriptService.Server

	Boots Knit and auto-loads all services from the Services/ folder via Loader.
	Handler modules are required and initialized inside GameService:KnitStart().
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Knit   = require(ReplicatedStorage.Packages.Knit)
local Loader = require(ReplicatedStorage.Packages.Loader)

-- Auto-discover and register all Knit Services under Services/
Loader.LoadDescendants(ServerScriptService.Server.Services)

Knit.Start():catch(warn):await()
print("[Server] Knit started.")
