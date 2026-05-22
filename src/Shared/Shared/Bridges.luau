--[[
	BRIDGES
	-------
	Central registry for all BridgeNet2 bridges in this project.

	Add new bridges here:
	  1. Declare a local variable with BridgeNet2.ReferenceBridge("Name")
	  2. Place it in the correct direction section below
	  3. Export it in the return table

	Import from both server and client:
	    local Bridges = require(game.ReplicatedStorage.Shared.Bridges)

	Rules:
	- All Bridge:Fire() calls take a SINGLE TABLE argument — no multi-param
	- Never create raw RemoteEvents elsewhere in the codebase

	Server firing to client:
	    Bridges.Notify:Fire(player, { type = "Success", message = "Hello!" })

	Server listening to client:
	    Bridges.OpenContainer:Connect(function(player, data) end)

	Client firing to server:
	    Bridges.OpenContainer:Fire({ })

	Client listening to server:
	    Bridges.Notify:Connect(function(data) end)

	Broadcast to all players (server side):
	    for _, player in game:GetService("Players"):GetPlayers() do
	        Bridges.Notify:Fire(player, { type = "Info", message = "Hello!" })
	    end
--]]

local BridgeNet2 = require(game.ReplicatedStorage.Packages.BridgeNet2)

-- ============================================================
-- SERVER → CLIENT
-- ============================================================

-- Generic toast/notification push
-- { type: "Success" | "Error" | "Info", message: string, data: any? }
local Notify = BridgeNet2.ReferenceBridge("Notify")

-- Server notifies recipient that a gift was received
-- { fromUserId: number, productId: number }
local GiftReceived = BridgeNet2.ReferenceBridge("GiftReceived")

-- Server triggers confetti effect on a specific client
-- { amount: number?, spawnPos: any? }
local EmitConfetti = BridgeNet2.ReferenceBridge("EmitConfetti")

-- Server notifies client of purchase outcome after PromptProductPurchaseFinished
-- { kind: "Success" | "Failure" }
local PurchaseEffect = BridgeNet2.ReferenceBridge("PurchaseEffect")

-- ============================================================
-- CLIENT → SERVER
-- ============================================================

-- Player opened a container / triggered a spin (generic example)
-- { }
local OpenContainer = BridgeNet2.ReferenceBridge("OpenContainer")

-- Admin command relay (for AdminHandler)
-- { action: string, [string]: any }
local AdminCommand = BridgeNet2.ReferenceBridge("AdminCommand")

-- Player requests to send a gift to another player
-- { targetUserId: number, productId: number }
local GiftPurchase = BridgeNet2.ReferenceBridge("GiftPurchase")

-- ============================================================

return {
	-- Server → Client
	Notify           = Notify,
	GiftReceived     = GiftReceived,
	EmitConfetti     = EmitConfetti,
	PurchaseEffect   = PurchaseEffect,

	-- Client → Server
	OpenContainer    = OpenContainer,
	AdminCommand     = AdminCommand,
	GiftPurchase     = GiftPurchase,
}
