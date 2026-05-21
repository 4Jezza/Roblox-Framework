--[[
	AnalyticsHandler
	----------------
	Stub for game analytics. Wire up your analytics provider (e.g. GameAnalytics,
	Roblox AnalyticsService, or a custom HTTP backend) in the TODO sections below.

	Other handlers should call AnalyticsHandler functions rather than calling the
	analytics SDK directly, so you can swap providers without touching handler code.
]]

local AnalyticsHandler = {}

-- TODO: require your analytics SDK here, e.g.:
-- local GameAnalytics = require(...)

function AnalyticsHandler:Initialize()
	print("[AnalyticsHandler] initialized.")
	-- TODO: initialize your analytics SDK, set up session tracking, etc.
end

-- Called when a player joins.
-- Extend with actual analytics calls: session start, device info, etc.
function AnalyticsHandler.OnPlayerJoined(player: Player)
	-- TODO: analytics SDK session-start call
	print("[AnalyticsHandler] player joined:", player.Name)
end

-- Called when a player leaves.
function AnalyticsHandler.OnPlayerLeft(player: Player)
	-- TODO: analytics SDK session-end call
	print("[AnalyticsHandler] player left:", player.Name)
end

-- Called when a player completes a purchase or earns a reward.
-- eventName: short slug, e.g. "win_round", "buy_cash_pack"
-- amount:    numeric value associated with the event (optional)
function AnalyticsHandler.LogEvent(player: Player, eventName: string, amount: number?)
	-- TODO: analytics SDK event call
	print(string.format("[AnalyticsHandler] %s — %s (amount=%s)", player.Name, eventName, tostring(amount)))
end

return AnalyticsHandler
