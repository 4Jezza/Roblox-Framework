--[[
	AutoRejoinController
	--------------------
	Automatically teleports the local player back to the same place when a
	network-loss disconnect is detected.

	Pattern (DevForum-standard):
	  • Hook GuiService.ErrorMessageChanged — fires whenever the client surfaces
	    an error / kick dialog. No RemoteEvent or polling needed.
	  • Match the error string against well-known connection-loss patterns
	    (codes 277-279, "lost connection", "timed out", etc.).
	  • On match, call TeleportService:Teleport(game.PlaceId, LocalPlayer).
	  • 15-second debounce: capture the flag into a LOCAL before task.delay fires
	    (architecture.md Critical Bans — module state may be nil by then).
	  • Studio listener: KnitStart still binds the listener in Studio so that
	    :_TestTrigger() works. The teleport itself is dry-run gated in
	    _attemptRejoin — TeleportService:Teleport is never called in Studio.

	Capability note (Roblox 2024+): GuiService.ErrorMessageChanged requires the
	RobloxScript script capability, which regular LocalScripts lack — connecting
	from a LocalScript throws "lacking capability RobloxScript". The KnitStart
	binding is pcall-guarded: if the connect fails the controller logs a warn
	and remains dormant. :_TestTrigger() still works in Studio for simulating
	the disconnect-detection path. There is no in-LocalScript signal that
	reliably detects a real disconnect (by then scripts are frozen), so this
	framework can't truly auto-rejoin from a LocalScript — honest about it.

	Public API:
	  :_TestTrigger(simulatedMessage?: string)
	    Dev-only. Runs the full disconnect-detection chain against a simulated
	    message without calling TeleportService. No-op outside Studio.
]]

local GuiService      = game:GetService("GuiService")
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Patterns matched (case-insensitive) against GuiService.ErrorMessageText.
-- Covers network timeout, kick codes 277/278/279, and generic drop messages.
local DISCONNECT_PATTERNS: { string } = {
	"lost",       -- "Lost connection to the game"
	"disconnect", -- "Disconnected from the server"
	"could not",  -- "Could not connect to the game"
	"27[7-9]",    -- Roblox error codes 277 / 278 / 279
	"timed out",  -- "Connection timed out"
}

local DEBOUNCE_SECONDS = 15

-- ---------------------------------------------------------------------------
-- Module table
-- ---------------------------------------------------------------------------

local AutoRejoinController = Knit.CreateController { Name = "AutoRejoinController" }

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function AutoRejoinController:KnitInit()
	self._janitor   = Janitor.new()
	self._debounced = false
end

function AutoRejoinController:KnitStart()
	-- GuiService.ErrorMessageChanged requires the RobloxScript script capability —
	-- regular LocalScripts can't connect to it (Studio surfaces:
	-- "The current thread cannot connect 'ErrorMessageChanged' (lacking capability
	-- RobloxScript)"). Wrap defensively: if the connect succeeds we listen,
	-- otherwise we no-op (the controller's :_TestTrigger still works for Studio
	-- dry-runs against a simulated message).
	-- GuiService has no `ErrorMessageText` property in current Roblox API. The
	-- ErrorMessageChanged event is the canonical signal — its callback receives
	-- the new error string as the first argument.
	local ok, conn = pcall(function()
		return GuiService.ErrorMessageChanged:Connect(function(message: string)
			self:_onErrorMessageChanged(message)
		end)
	end)

	if ok and conn then
		self._janitor:Add(conn, "Disconnect")
		print("[AutoRejoinController] Listening for disconnect events.")
	else
		warn("[AutoRejoinController] ErrorMessageChanged unavailable (RobloxScript capability required) — auto-rejoin disabled. Use :_TestTrigger() for Studio simulation.")
	end
end

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

function AutoRejoinController:_onErrorMessageChanged(message: string?)
	local msg: string = message or ""
	if msg == "" then
		return
	end

	-- Check for any disconnect pattern (case-insensitive).
	local matched = false
	for _, pattern in DISCONNECT_PATTERNS do
		if msg:lower():find(pattern) then
			matched = true
			break
		end
	end

	if not matched then
		return
	end

	warn(("[AutoRejoinController] Disconnect detected — message: %q"):format(msg))

	-- Capture debounce flag into a local BEFORE task.delay (Critical Bans —
	-- module state may be nil/collected by the time the delay fires).
	if self._debounced then
		warn("[AutoRejoinController] Debounce active — skipping rejoin attempt.")
		return
	end

	self._debounced = true
	-- Capture self into a local BEFORE task.delay (architecture.md § Critical Bans —
	-- module/table state may be nil by the time the delay fires).
	local ctrl = self
	task.delay(DEBOUNCE_SECONDS, function()
		if ctrl then
			ctrl._debounced = false
		end
	end)

	self:_attemptRejoin()
end

function AutoRejoinController:_attemptRejoin()
	local player = Players.LocalPlayer
	if not player then
		warn("[AutoRejoinController] LocalPlayer missing — cannot rejoin.")
		return
	end

	local placeId = game.PlaceId

	-- Studio dry-run: log the would-be teleport without calling TeleportService,
	-- which throws in edit/run mode.
	if RunService:IsStudio() then
		warn("[AutoRejoinController] Studio dry-run — would teleport to PlaceId " .. tostring(placeId))
		return
	end

	warn(("[AutoRejoinController] Teleporting player %s to PlaceId %d…"):format(
		player.Name, placeId
	))

	local ok, err = pcall(function()
		TeleportService:Teleport(placeId, player)
	end)

	if not ok then
		warn(("[AutoRejoinController] Teleport failed — %s. Player must rejoin manually."):format(
			tostring(err)
		))
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Dev-only test trigger. Runs the disconnect-detection chain against a
--- simulated message WITHOUT actually calling TeleportService.
--- No-op outside Studio.
function AutoRejoinController:_TestTrigger(simulatedMessage: string?)
	if not RunService:IsStudio() then
		warn("[AutoRejoinController] :_TestTrigger called outside Studio — ignoring")
		return
	end
	local msg = simulatedMessage or "Lost connection — Error code 277"
	self:_onErrorMessageChanged(msg)
end

return AutoRejoinController
