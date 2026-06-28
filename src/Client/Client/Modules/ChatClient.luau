--[[
	ChatClient
	----------
	Sends periodic tip messages and custom announcements into the local
	player's RBXGeneral chat channel via TextChatService:DisplaySystemMessage.

	TODO: Replace TIPS table with game-specific tip strings.
	TODO: Add custom chat events (timed warnings, server announcements, etc.)
	      in the "Add custom chat events here" section below.
]]

local TextChatService   = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridges = require(ReplicatedStorage.Shared.Bridges)
local Janitor  = require(ReplicatedStorage.Packages.Janitor)

local ChatClient = {}

-- Tracks bridge connections so they can be cleaned up if the module is torn down.
local _janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local TIP_INTERVAL = 120 -- seconds between tips (2 minutes)

-- Roblox Private Use Area codepoint for the Robux coin glyph.
-- *** IMPLEMENTER: confirm "\u{E002}" renders in :DisplaySystemMessage before shipping.
-- If it shows as a box/unknown, replace with the fallback string "R$". ***
local ROBUX_ICON = "\u{E002}"

-- TODO: Replace with game-specific tip strings
local TIPS = {
	"[TIP]: This is a placeholder tip. Replace me!",
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

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

	-- Purchase/gift broadcast: display a coloured announcement in RBXGeneral.
	-- Robux icon uses the Roblox Private Use Area glyph (no img tag needed).
	-- per api/networking.md § 1.2 — client :Connect returns a Connection; track it
	-- so the bridge listener is cleaned up if the module is torn down.
	local _purchaseBroadcastConn = Bridges.PurchaseBroadcast:Connect(function(data)
		if not data or type(data) ~= "table" then return end
		-- No yield in the bridge body (architecture.md § Critical Bans) — spawn the rest.
		task.spawn(function()
			-- Bounded wait: don't spin forever if the channel never resolves
			-- (e.g. TextChatService not in TextChatEnabled mode).
			local deadline = os.clock() + 10
			while not generalChannel and os.clock() < deadline do
				task.wait(0.5)
			end
			-- Defensive guard: warn and drop if channel is still nil (rule_8).
			if not generalChannel then
				warn("[ChatClient] PurchaseBroadcast — generalChannel unavailable after 10s, dropping message")
				return
			end
			local msg
			if data.isGift then
				msg = string.format(
					'<font color="#FFD700"><b>%s</b> GIFTED <b>%s</b> TO <b>%s</b> FOR %s%d!</font>',
					tostring(data.playerName),
					tostring(data.productName),
					tostring(data.recipientName or "?"),
					ROBUX_ICON,
					data.priceInRobux or 0
				)
			else
				msg = string.format(
					'<font color="#FFD700"><b>%s</b> PURCHASED <b>%s</b> FOR %s%d!</font>',
					tostring(data.playerName),
					tostring(data.productName),
					ROBUX_ICON,
					data.priceInRobux or 0
				)
			end
			generalChannel:DisplaySystemMessage(msg)
		end)
	end)
	-- Explicit "Disconnect" — Janitor:Add auto-probes :Destroy which does not
	-- exist on BridgeNet2 Connections (api-reference.md § Janitor gotchas).
	_janitor:Add(_purchaseBroadcastConn, "Disconnect")

	print("[ChatClient] Initialized.")
end

return ChatClient
