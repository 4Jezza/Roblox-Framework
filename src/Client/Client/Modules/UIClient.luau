--[[
    UIClient
    --------
    Client-side UI management. Owns frame open/close lifecycle, QuickPlay
    button visibility, and the inTableGame state flag.

    All frames live under PlayerGui.Ui.Frames.<FrameName>.
    Use UIClient.GetFrame(name) to retrieve a frame by name.
    Use UIClient.OpenFrame / CloseFrame to animate frames in/out via UIAnimator.

    TODO: Populate ui.BottomMiddle.QuickPlay reference once StarterGui is built.
    TODO: Wire reactive listeners (PlayerData.OnChange, Bridges events) per game.
--]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIAnimator = require(script.Parent.Parent.Packages.UIAnimator)

local UIClient    = {}
local LocalPlayer = Players.LocalPlayer
local playerGui   = LocalPlayer:WaitForChild("PlayerGui")
local ui          = playerGui:WaitForChild("Ui")

-- QuickPlay button — comment back in once StarterGui.Ui.BottomMiddle.QuickPlay exists
-- local quickPlayBtn = ui:FindFirstChild("BottomMiddle") and ui.BottomMiddle:FindFirstChild("QuickPlay")
local quickPlayBtn = nil -- TODO: assign once UI hierarchy is built

-- ========== TABLE GAME STATE ==========
local inTableGame = false

-- ========== QUICK PLAY VISIBILITY ==========

local function updateQuickPlayVisibility()
	if not quickPlayBtn then return end
	-- Hide while in a table game
	if inTableGame then
		quickPlayBtn.Visible = false
		return
	end
	-- Hide while ANY frame in the Frames folder is open
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

-- ========== FRAME ANIMATION HELPERS ==========

local function openFrame(frame: Frame)
	if not frame then return end
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
	local framesFolder = ui:FindFirstChild("Frames")
	if framesFolder then
		for _, frame in framesFolder:GetChildren() do
			if frame:IsA("Frame") and frame.Visible then
				frame.Visible = false
			end
		end
	end
end

-- ========== PUBLIC API ==========

-- Expose frame helpers so other modules can call them directly
UIClient.OpenFrame    = openFrame
UIClient.CloseFrame   = closeFrame
UIClient.CloseAllFrames = closeAllFrames

--- Retrieve a frame by name from PlayerGui.Ui.Frames.<name>
function UIClient.GetFrame(name: string): Frame?
	local framesFolder = ui:FindFirstChild("Frames")
	if not framesFolder then return nil end
	return framesFolder:FindFirstChild(name) :: Frame?
end

--- Return the root Ui ScreenGui
function UIClient.GetUi(): ScreenGui
	return ui :: ScreenGui
end

--- Mark whether the local player is inside a table minigame.
--- While true, QuickPlay is hidden and certain UI elements are suppressed.
function UIClient.SetInTableGame(value: boolean)
	inTableGame = value
	updateQuickPlayVisibility()
end

--- Returns the current inTableGame state.
function UIClient.IsInTableGame(): boolean
	return inTableGame
end

-- ========== INITIALIZATION ==========

function UIClient:Initialize()
	-- TODO: Set up PlayerData.OnChange listeners to update cash/stat labels
	-- TODO: Wire Bridges events (e.g., Bridges.Notify) if needed at this layer
	-- TODO: Tag sidebar/top buttons with CollectionService "Animatable" for UIAnimator hover effects
	-- TODO: Assign quickPlayBtn once StarterGui hierarchy is in place
	print("[UIClient] Initialized.")
end

return UIClient
