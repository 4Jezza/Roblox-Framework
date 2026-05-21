--[[
	RemoteConfigHandler
	-------------------
	Example: bridges Roblox's ConfigService (server-only) into a workspace
	attribute that clients can read. The user controls config values from the
	Creator Hub dashboard → Configs page; this handler reads them at server
	start and on every UpdateAvailable event, mirroring them into workspace
	attributes that Roblox auto-replicates to all clients.

	Change CONFIG_KEY and add more keys as you create configs in the Creator Hub.

	Currently bridges:
	  Example_Bool_Config (boolean) → workspace attribute of the same name
]]

local ConfigService = game:GetService("ConfigService")
local Workspace     = game:GetService("Workspace")

local RemoteConfigHandler = {}

-- TODO: change this to match the config key you created in the Creator Hub.
local CONFIG_KEY = "Example_Bool_Config"

local function applyConfig(snapshot)
	local ok, value = pcall(function()
		return snapshot:GetValue(CONFIG_KEY)
	end)
	if not ok then
		warn("[RemoteConfigHandler] Failed to read", CONFIG_KEY, "from snapshot:", value)
		return
	end
	-- Coerce to strict boolean: nil/false/non-true → false, true → true
	Workspace:SetAttribute(CONFIG_KEY, value == true)
end

function RemoteConfigHandler:Initialize()
	-- Default the attribute IMMEDIATELY so any client/server code that reads
	-- it during the async ConfigService fetch sees a sensible value.
	Workspace:SetAttribute(CONFIG_KEY, false)

	-- ConfigService:GetConfigAsync() yields, so wrap in task.spawn so it doesn't
	-- block GameService:KnitStart from initializing other handlers.
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return ConfigService:GetConfigAsync()
		end)
		if not ok or not snapshot then
			warn("[RemoteConfigHandler] ConfigService:GetConfigAsync failed:", snapshot)
			return
		end

		-- Apply the initial value
		applyConfig(snapshot)

		-- Re-apply whenever the underlying config changes (Creator Hub edits
		-- propagate to live servers within ~5 minutes).
		local updateOk, updateSignal = pcall(function()
			return snapshot.UpdateAvailable
		end)
		if updateOk and updateSignal then
			updateSignal:Connect(function()
				local refreshOk = pcall(function()
					snapshot:Refresh()
				end)
				if refreshOk then
					applyConfig(snapshot)
				end
			end)
		end
	end)
end

return RemoteConfigHandler
