--[[
    ChatClient
    ----------
    Sends periodic tip messages and custom announcements into the local
    player's RBXGeneral chat channel via TextChatService:DisplaySystemMessage.

    TODO: Replace TIPS table with game-specific tip strings.
    TODO: Add custom chat events (timed warnings, server announcements, etc.)
          in the "Add custom chat events here" section below.
--]]

local TextChatService   = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridges = require(ReplicatedStorage.Shared.Bridges)

local ChatClient = {}

local TIP_INTERVAL = 120 -- seconds between tips (2 minutes)

-- TODO: Replace with game-specific tip strings
local TIPS = {
	"[TIP]: This is a placeholder tip. Replace me!",
	"[TIP]: Another placeholder tip. Add your own.",
	"[TIP]: Visit the wiki for more information.",
}

function ChatClient:Initialize()
	-- Acquire the RBXGeneral channel once; reuse for all messages
	local generalChannel: TextChannel? = nil
	task.spawn(function()
		while not generalChannel do
			local channels = TextChatService:FindFirstChild("TextChannels")
			generalChannel = channels and channels:FindFirstChild("RBXGeneral")
			if not generalChannel then task.wait(1) end
		end
	end)

	-- Periodic tip loop
	task.spawn(function()
		while not generalChannel do task.wait(0.5) end
		local tipIndex = 0
		while true do
			task.wait(TIP_INTERVAL)
			tipIndex = (tipIndex % #TIPS) + 1
			generalChannel:DisplaySystemMessage(
				'<font color="#00FF00">' .. TIPS[tipIndex] .. "</font>"
			)
		end
	end)

	-- Add custom chat events here, e.g., timed warnings, server announcements:
	-- task.spawn(function()
	--     while not generalChannel do task.wait(0.5) end
	--     while true do
	--         task.wait(1)
	--         -- TODO: check conditions and call generalChannel:DisplaySystemMessage(...)
	--     end
	-- end)

	-- Example: broadcast server purchase events to chat
	-- TODO: Remove or replace once real purchase broadcast bridge exists
	-- Bridges.PurchaseBroadcast:Connect(function(data)
	--     if not data or type(data) ~= "table" then return end
	--     local msg = data.playerName .. " bought " .. data.productName .. "!"
	--     local channels = TextChatService:FindFirstChild("TextChannels")
	--     local general = channels and channels:FindFirstChild("RBXGeneral")
	--     if general then
	--         general:DisplaySystemMessage('<font color="#00FF00">' .. msg .. "</font>")
	--     end
	-- end)

	print("[ChatClient] Initialized.")
end

return ChatClient
