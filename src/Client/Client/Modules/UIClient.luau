--[[
	UIClient
	--------
	Client-side UI management. Owns frame open/close lifecycle, QuickPlay
	button visibility, and the inTableGame state flag.

	All frames live under PlayerGui.Ui.Frames.<FrameName>.
	Use UIClient.GetFrame(name) to retrieve a frame by name.
	Use UIClient.OpenFrame(frame, opts?) / CloseFrame to animate frames
	in/out via UIAnimator.

	OpenFrame gates on PlayerStateController.IsAllowed("frame", frame.Name).
	Pass opts.force = true to bypass the gate (e.g. server-forced opens).

	SetInTableGame / IsInTableGame delegate to PlayerStateController so that
	the legacy inTableGame boolean is fully replaced by state-machine authority.

	Public API:
	  UIClient.OpenFrame(frame, opts?)  → void   (opts: { force: boolean? })
	  UIClient.CloseFrame(frame)        → void
	  UIClient.CloseAllFrames()         → void
	  UIClient.GetFrame(name)           → Frame?
	  UIClient.GetUi()                  → ScreenGui?
	  UIClient.SetInTableGame(value)    → void   (delegates to PlayerStateController)
	  UIClient.IsInTableGame()          → boolean (delegates to PlayerStateController)

	TODO: Populate ui.BottomMiddle.QuickPlay reference once StarterGui is built.
	TODO: Wire reactive listeners (PlayerData.OnChange, Bridges events) per game.

	Per .claude/reference/architecture.md § Require Paths (Knit).
	Per docs/conventions.md § Module file structure.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local UIAnimator = require(script.Parent.Parent.Packages.UIAnimator)

local UIClient    = {}
local LocalPlayer = Players.LocalPlayer
local playerGui   = LocalPlayer:WaitForChild("PlayerGui")
-- Bounded wait — the boilerplate ships without a built StarterGui.Ui ScreenGui.
-- Helper functions below nil-guard `ui` so the module no-ops gracefully until
-- the ScreenGui is authored in Studio (see filestructure/starter-gui.md).
local ui          = playerGui:WaitForChild("Ui", 10) :: ScreenGui?
if not ui then
	warn("[UIClient] PlayerGui.Ui not present after 10s — UI helpers will no-op until StarterGui.Ui is added")
end

-- QuickPlay button — comment back in once StarterGui.Ui.BottomMiddle.QuickPlay exists
-- local quickPlayBtn = ui:FindFirstChild("BottomMiddle") and ui.BottomMiddle:FindFirstChild("QuickPlay")
local quickPlayBtn = nil -- TODO: assign once UI hierarchy is built

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Emitted once per boot when PlayerStateController is not yet ready.
-- Prevents log spam on rapid open attempts during early load.
local _stateControllerWarnedOnce = false

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Lazy getter for PlayerStateController. Returns nil if Knit hasn't finished
-- starting (e.g. called during KnitInit). Callers must nil-guard.
local _playerState = nil
local function getPlayerState()
	if _playerState then
		return _playerState
	end
	local ok, controller = pcall(function()
		return Knit.GetController("PlayerStateController")
	end)
	if ok and controller then
		_playerState = controller
		return controller
	end
	return nil
end

local function updateQuickPlayVisibility()
	if not quickPlayBtn then return end
	-- Hide while in-game state is active
	local ps = getPlayerState()
	if ps and ps:Get() == "InGame" then
		quickPlayBtn.Visible = false
		return
	end
	-- Hide while ANY frame in the Frames folder is open
	if not ui then return end
	local framesFolder = ui:FindFirstChild("Frames")
	if framesFolder then
		for _, child in framesFolder:GetChildren() do
			if child:IsA("Frame") and child.Visible then
				quickPlayBtn.Visible = false
				return
			end
		end
	end
	quickPlayBtn.Visible = true
end

-- opts: { force: boolean? }
local function openFrame(frame: Frame, opts: { force: boolean? }?)
	if not frame then return end

	-- Gate on PlayerStateController unless opts.force is true.
	local resolvedOpts = opts or {}
	if not resolvedOpts.force then
		local ps = getPlayerState()
		if ps then
			if not ps:IsAllowed("frame", frame.Name) then
				warn(
					"[UIClient] OpenFrame blocked by state: "
						.. frame.Name
						.. " (state="
						.. ps:Get()
						.. ")"
				)
				return
			end
		else
			-- Controller not yet available — proceed without gating but warn once.
			if not _stateControllerWarnedOnce then
				_stateControllerWarnedOnce = true
				warn("[UIClient] PlayerStateController unavailable at OpenFrame — skipping gate until controller is ready")
			end
		end
	end

	frame.Visible = true
	task.spawn(UIAnimator.FrameZoom, frame, true, 0.4)
	updateQuickPlayVisibility()
end

local function closeFrame(frame: Frame)
	if not frame then return end
	task.spawn(function()
		UIAnimator.FrameZoom(frame, false, 0.25)
		task.wait(0.25)
		frame.Visible = false
		updateQuickPlayVisibility()
	end)
end

-- Close every frame in the Frames folder
local function closeAllFrames()
	if not ui then return end
	local framesFolder = ui:FindFirstChild("Frames")
	if framesFolder then
		for _, frame in framesFolder:GetChildren() do
			if frame:IsA("Frame") and frame.Visible then
				frame.Visible = false
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Expose frame helpers so other modules can call them directly.
-- OpenFrame accepts an optional second argument: opts = { force = boolean? }.
-- Pass opts.force = true to bypass the PlayerStateController gate (e.g. for
-- server-initiated forced opens or loading-screen dismiss).
UIClient.OpenFrame      = openFrame
UIClient.CloseFrame     = closeFrame
UIClient.CloseAllFrames = closeAllFrames

--- Retrieve a frame by name from PlayerGui.Ui.Frames.<name>
function UIClient.GetFrame(name: string): Frame?
	if not ui then return nil end
	local framesFolder = ui:FindFirstChild("Frames")
	if not framesFolder then return nil end
	return framesFolder:FindFirstChild(name) :: Frame?
end

--- Return the root Ui ScreenGui (nil if StarterGui.Ui hasn't been authored yet)
function UIClient.GetUi(): ScreenGui?
	return ui
end

--- Mark whether the local player is inside a table minigame.
--- Delegates to PlayerStateController:Set("InGame" | "Idle") — the
--- inTableGame boolean is fully replaced by the state-machine.
function UIClient.SetInTableGame(value: boolean)
	local ps = getPlayerState()
	if not ps then
		warn("[UIClient] missing PlayerStateController at SetInTableGame — state not changed")
		return
	end
	ps:Set(value and "InGame" or "Idle")
	updateQuickPlayVisibility()
end

--- Returns whether the local player is currently in-game.
--- Delegates to PlayerStateController:Get() == "InGame".
function UIClient.IsInTableGame(): boolean
	local ps = getPlayerState()
	if not ps then
		return false
	end
	return ps:Get() == "InGame"
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function UIClient:Initialize()
	-- TODO: Set up PlayerData.OnChange listeners to update cash/stat labels
	-- TODO: Wire Bridges events (e.g., Bridges.Notify) if needed at this layer
	-- TODO: Tag sidebar/top buttons with CollectionService "Animatable" for UIAnimator hover effects
	-- TODO: Assign quickPlayBtn once StarterGui hierarchy is in place
	print("[UIClient] Initialized.")
end

return UIClient
