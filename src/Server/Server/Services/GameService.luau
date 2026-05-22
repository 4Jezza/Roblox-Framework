--[[
	GameService
	-----------
	Single Knit Service that owns all server-side handler modules.

	KnitInit  — require modules only. No inter-service calls, no yields.
	KnitStart — safe to call other services. Initialize handlers in dependency order:
	            DataService first, then all handlers.

	To add a new handler:
	  1. Create src/Server/Server/Modules/YourHandler.luau
	  2. require() it in KnitInit (marked with "Add your new handler here")
	  3. Call YourHandler:Initialize() in KnitStart (marked similarly)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local GameService = Knit.CreateService {
	Name   = "GameService",
	Client = {},
}

function GameService:KnitInit()
	-- Shared data layer (not a handler — initialize it first in KnitStart)
	self._DataService = require(ServerStorage.ServerUtilities.DataService)

	-- Handler modules (order here is just require-time; init order is in KnitStart)
	self._DataHandler         = require(script.Parent.Parent.Modules.DataHandler)
	self._ProductHandler      = require(script.Parent.Parent.Modules.ProductHandler)
	self._RemoteConfigHandler = require(script.Parent.Parent.Modules.RemoteConfigHandler)
	self._AnalyticsHandler    = require(script.Parent.Parent.Modules.AnalyticsHandler)
	self._InventoryHandler    = require(script.Parent.Parent.Modules.InventoryHandler)
	self._AdminHandler        = require(script.Parent.Parent.Modules.AdminHandler)
	self._WorldEntityHandler  = require(script.Parent.Parent.Modules.WorldEntityHandler)

	-- TODO: Add your new handler here (require step)
	-- self._YourHandler = require(script.Parent.Parent.Modules.YourHandler)
end

function GameService:KnitStart()
	-- Data layer must initialize before any handler reads/writes player profiles.
	self._DataService.Init()

	-- RemoteConfigHandler sets workspace attributes early so other handlers and
	-- client modules see correct config values from the first frame.
	self._RemoteConfigHandler:Initialize()

	-- Remaining handlers (order within this block is generally safe to reorder).
	self._DataHandler:Initialize()
	self._InventoryHandler:Initialize()
	self._AdminHandler:Initialize()
	self._AnalyticsHandler:Initialize()
	self._ProductHandler:Initialize()
	self._WorldEntityHandler:Initialize()

	-- TODO: Add your new handler here (initialize step)
	-- self._YourHandler:Initialize()

	print("[GameService] All modules initialized.")
end

return GameService
