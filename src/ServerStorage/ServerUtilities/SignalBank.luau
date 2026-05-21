-- SignalBank
-- ----------
-- Central registry of server-internal signals used for cross-handler
-- communication. Fire and connect to these instead of using RemoteEvents
-- for server-to-server messaging.
--
-- Add new signals here as your game grows. Import this module anywhere on
-- the server; never require it on the client.

local Signal = require(game:GetService("ReplicatedStorage").Packages.Signal)

return {
	-- Fired by DataService after a player's profile has fully loaded.
	-- Payload: (player: Player, data: {[string]: any})
	DataLoaded     = Signal.new(),

	-- Fired when a player is about to leave (before EndSession).
	-- Payload: (player: Player)
	PlayerLeaving  = Signal.new(),

	-- Fired when a player first joins and their character is ready.
	-- Payload: (player: Player)
	PlayerJoined   = Signal.new(),

	-- TODO: Add game-specific signals here, e.g.:
	--   CashChanged   = Signal.new(),   -- (player, newAmount)
	--   WinsChanged   = Signal.new(),   -- (player, newAmount)
}
