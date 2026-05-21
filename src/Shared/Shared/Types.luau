--[[
	TYPES
	-----
	Luau type exports for the boilerplate.

	Import:
	    local Types = require(game.ReplicatedStorage.Shared.Types)
--]]

-- Shape of every player's persisted profile data.
-- Extend this to match your DataTemplate in DataHandler.
export type ProfileData = {
	cash: number,
	wins: number,
	inventory: { [string]: any },
}

-- Payload shape for the Notify bridge (Server → Client).
export type NotifyPayload = {
	type: "Success" | "Error" | "Info",
	message: string,
	data: any?,
}

-- Generic catch-all bridge payload type.
export type BridgePayload = {
	action: string?,
	[string]: any,
}

return {}
