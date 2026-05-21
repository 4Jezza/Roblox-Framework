--[[
    GameController
    --------------
    Knit Controller wrapper. Initializes all client-side game modules.

    To add a new client module:
    1. Create src/Client/Client/Modules/MyModule.luau as a plain table with :Initialize()
    2. Add below in KnitInit:   self._MyModule = require(script.Parent.Parent.Modules.MyModule)
    3. Add below in KnitStart:  self._MyModule:Initialize()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit       = require(ReplicatedStorage.Packages.Knit)
local PlayerData = require(ReplicatedStorage.Utility.PlayerData)

local GameController = Knit.CreateController {
	Name = "GameController",
}

function GameController:KnitInit()
	-- Platform stubs
	self._UIClient           = require(script.Parent.Parent.Modules.UIClient)
	self._NotificationClient = require(script.Parent.Parent.Modules.NotificationClient)
	self._ChatClient         = require(script.Parent.Parent.Modules.ChatClient)

	-- Add your new client module requires here:
	-- self._MyModule = require(script.Parent.Parent.Modules.MyModule)
end

function GameController:KnitStart()
	-- Initialize Replica-backed player data FIRST so modules can read it
	PlayerData.Init()

	-- Initialize platform modules in dependency order
	self._UIClient:Initialize()
	self._NotificationClient:Initialize()
	self._ChatClient:Initialize()

	-- Initialize your new modules here:
	-- self._MyModule:Initialize()

	print("[GameController] All modules initialized.")
end

return GameController
