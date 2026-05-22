--!strict
--[[
	FrameTransitions
	----------------
	Open / close panels with UIScale animation + optional Lighting.Blur ramp.
	Also auto-watches every Folder named "Frames" anywhere in PlayerGui and
	animates + mutually-excludes their direct Frame children.

	Open:  UIScale 0.8 → 1.0  +  Blur ramp in   (0.4s default — S1 modal open)
	Close: UIScale 1.0 → 0.8  +  Blur ramp out   (0.25s default — S1 all exits)
	       Visibility set to false AFTER the close tween completes.

	Auto-watcher (watchFramesFolder / watchFrame):
	  Any direct-child Frame of a "Frames" Folder in PlayerGui is watched.
	  When frame.Visible flips to true  → Open animation runs.
	  When frame.Visible flips to false → Close animation runs.
	  Mutual exclusion: when a frame becomes visible, every OTHER direct-child
	  Frame in the same "Frames" folder has its Visible set to false (which
	  cascades through their own watchers to play the Close animation).

	Re-entrancy guard:
	  A per-frame flag (_animating[frame]) is set for the duration of each
	  animation. If Visible flips again while an animation is running, a new
	  task.spawn is deferred until the previous animation concludes (the flag
	  clears), then re-evaluates the current Visible state. This prevents
	  stacked/ghost animations on rapid Visible toggles.

	Public API (thin wrappers — callers should prefer setting frame.Visible):
	  FrameTransitions.Open(frame, duration?)   -- sets Visible=true → watcher runs
	  FrameTransitions.Close(frame, duration?)  -- sets Visible=false → watcher runs

	Twinkle (vendored UIAnimator) is used for all tweens — no raw TweenService
	for UI (CLAUDE.md rule_7). Lighting.Blur ramp uses TweenService because it
	is a one-shot fire-and-forget tween on a Lighting instance, which is the
	documented exception.

	Per api-reference.md § 6.1 UIAnimator.FrameZoom signature.
	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" on all signal
	    connections added to Janitor.
	Per CLAUDE.md rule_8 — defensive logging on every failable lookup.
]]

local Lighting      = game:GetService("Lighting")
local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")

-- Twinkle path: script = FrameTransitions → .Parent = UIAnimator folder
-- → .Parent.Parent = Controllers → .Parent.Parent.Parent = Client (Packages/)
local Twinkle = require(script.Parent.Parent.Parent.Packages.UIAnimator)
local Janitor  = require(game.ReplicatedStorage.Packages.Janitor)

local FrameTransitions = {}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Module-scope janitor: owns the blur Instance + all PlayerGui watchers.
local _moduleJanitor = Janitor.new()
local _ownedBlur: BlurEffect? = nil

-- Per-frame per-folder watcher janitors: [frame] -> Janitor
-- Cleaned when the frame is removed from the folder.
local _frameJanitors: { [Frame]: any } = {}

-- Per-folder watcher janitors: [folder] -> Janitor
-- Cleaned when the folder is removed from PlayerGui.
local _folderJanitors: { [Folder]: any } = {}

-- Re-entrancy guard: [frame] -> boolean
-- True while an Open or Close animation is in flight for that frame.
local _animating: { [Frame]: boolean } = {}

-- ---------------------------------------------------------------------------
-- Private: Blur helpers
-- ---------------------------------------------------------------------------

local function getOrCreateBlur(): BlurEffect
	local existing = Lighting:FindFirstChildOfClass("BlurEffect")
	if existing then
		return existing :: BlurEffect
	end

	if _ownedBlur and _ownedBlur.Parent then
		return _ownedBlur
	end

	local blur = Instance.new("BlurEffect")
	blur.Size  = 0
	blur.Parent = Lighting
	_ownedBlur = blur

	_moduleJanitor:Add(blur, "Destroy", "ownedBlur")
	return blur
end

-- TweenService is permitted here: one-shot fire-and-forget on a Lighting
-- instance — not a UI element (CLAUDE.md rule_7 documented exception).
local function tweenBlur(targetSize: number, duration: number)
	local blur = getOrCreateBlur()
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(blur, info, { Size = targetSize })
	tween:Play()
end

-- ---------------------------------------------------------------------------
-- Private: core open / close animation (no Visible mutation — callers do that)
-- ---------------------------------------------------------------------------

local function runOpen(frame: Frame, duration: number)
	-- Mark animating before spawn so any re-entrant Visible flip sees the flag.
	_animating[frame] = true
	task.spawn(function()
		-- FrameZoom(element, show=true, speed, blur=false, hideOtherUi=false)
		Twinkle.FrameZoom(frame, true, duration, false, false)
		-- Secondary: blur ramp in (0 → 8). Simultaneous is correct here —
		-- blur is ambient ambience, not a competing primary motion (S6).
		tweenBlur(8, duration)
		_animating[frame] = nil
	end)
end

local function runClose(frame: Frame, duration: number)
	_animating[frame] = true
	task.spawn(function()
		-- FrameZoom with show=false sets Visible=false after the tween completes.
		Twinkle.FrameZoom(frame, false, duration, false, false)
		tweenBlur(0, duration)
		_animating[frame] = nil
	end)
end

-- ---------------------------------------------------------------------------
-- Private: per-frame Visible watcher
-- ---------------------------------------------------------------------------

-- Schedule an animation for `frame` after any in-flight animation settles.
-- Re-entrancy guard: if already animating, defer one frame then re-check.
local function scheduleAnimation(frame: Frame, folder: Folder, duration: number?)
	if _animating[frame] then
		-- Defer until next frame; by then the current animation should be done
		-- (Twinkle.FrameZoom yields inside task.spawn — it won't block us, but
		-- the flag is still set while it runs). A single-frame defer is enough
		-- because we check the flag again on resume.
		task.defer(function()
			scheduleAnimation(frame, folder, duration)
		end)
		return
	end

	local openDur  = duration or 0.4
	local closeDur = duration or 0.25

	if frame.Visible then
		-- Mutual exclusion: set every OTHER direct-child Frame in the same folder
		-- to Visible = false. Their own watchers will play Close animations.
		for _, sibling in folder:GetChildren() do
			if sibling ~= frame and sibling:IsA("Frame") then
				local sib = sibling :: Frame
				if sib.Visible then
					sib.Visible = false
					-- Note: the sibling's own GetPropertyChangedSignal("Visible")
					-- handler fires here and calls runClose on the sibling.
				end
			end
		end
		runOpen(frame, openDur)
	else
		runClose(frame, closeDur)
	end
end

local function watchFrame(frame: Frame, folder: Folder)
	if _frameJanitors[frame] then return end  -- already watched

	local j = Janitor.new()
	_frameJanitors[frame] = j

	j:Add(frame:GetPropertyChangedSignal("Visible"):Connect(function()
		scheduleAnimation(frame, folder)
	end), "Disconnect")

	-- When the frame is removed / destroyed, clean up.
	j:Add(frame.AncestryChanged:Connect(function(_, parent)
		if parent == nil or not parent:IsDescendantOf(folder) then
			local fj = _frameJanitors[frame]
			if fj then
				fj:Destroy()
				_frameJanitors[frame] = nil
			end
		end
	end), "Disconnect")

	j:LinkToInstance(frame)

	j:Add(function()
		_frameJanitors[frame] = nil
		_animating[frame]     = nil
	end, true)
end

-- ---------------------------------------------------------------------------
-- Private: per-folder watcher
-- ---------------------------------------------------------------------------

local function watchFramesFolder(folder: Folder)
	if _folderJanitors[folder] then return end  -- already watched

	local j = Janitor.new()
	_folderJanitors[folder] = j

	-- Wire all existing direct-child Frames.
	for _, child in folder:GetChildren() do
		if child:IsA("Frame") then
			watchFrame(child :: Frame, folder)
		end
	end

	-- Watch for new direct-child Frames added at runtime (e.g., lazy-cloned panels).
	j:Add(folder.ChildAdded:Connect(function(child)
		if child:IsA("Frame") then
			watchFrame(child :: Frame, folder)
		end
	end), "Disconnect")

	-- Unwatch removed child frames.
	j:Add(folder.ChildRemoved:Connect(function(child)
		if child:IsA("Frame") then
			local frame = child :: Frame
			local fj = _frameJanitors[frame]
			if fj then
				fj:Destroy()
				_frameJanitors[frame] = nil
			end
		end
	end), "Disconnect")

	-- When the folder itself is removed, destroy this folder janitor.
	j:Add(folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			local foldJ = _folderJanitors[folder]
			if foldJ then
				foldJ:Destroy()
				_folderJanitors[folder] = nil
			end
		end
	end), "Disconnect")

	j:LinkToInstance(folder)

	j:Add(function()
		_folderJanitors[folder] = nil
	end, true)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Boot-time initialization — called from UIAnimator/init.luau:KnitStart.
	Discovers every Folder named "Frames" in PlayerGui and watches it.
	Also watches for Folders added later (lazy ScreenGuis, etc.).
]]
function FrameTransitions.Start()
	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/FrameTransitions] Start: LocalPlayer missing — watcher not started")
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/FrameTransitions] Start: PlayerGui missing — watcher not started")
		return
	end

	-- One-shot walk: find every existing "Frames" Folder in the entire PlayerGui tree.
	for _, desc in playerGui:GetDescendants() do
		if desc:IsA("Folder") and desc.Name == "Frames" then
			watchFramesFolder(desc :: Folder)
		end
	end

	-- Watch for new "Frames" Folders added at runtime.
	_moduleJanitor:Add(playerGui.DescendantAdded:Connect(function(desc)
		if desc:IsA("Folder") and desc.Name == "Frames" then
			watchFramesFolder(desc :: Folder)
		end
	end), "Disconnect")

	-- Safety: clean up when the local player leaves.
	_moduleJanitor:Add(player.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			for _, fj in _folderJanitors do fj:Destroy() end
			for _, fj in _frameJanitors do fj:Destroy() end
			table.clear(_folderJanitors)
			table.clear(_frameJanitors)
			table.clear(_animating)
			_moduleJanitor:Cleanup()
		end
	end), "Disconnect")
end

--[[
	Open a frame explicitly.
	Preferred usage: set frame.Visible = true (the watcher handles animation).
	This method is a thin wrapper for callers that prefer imperative control.
	duration: default 0.4s (S1 — standard modal open).
]]
function FrameTransitions.Open(frame: Frame, duration: number?)
	if not frame then
		warn("[UIAnimator/FrameTransitions] Open called with nil frame")
		return
	end
	-- Setting Visible triggers the watcher. If the frame is not in a watched
	-- folder (i.e., it was opened imperatively via the public API), run the
	-- animation directly so the caller still gets the expected behaviour.
	local d = duration or 0.4
	frame.Visible = true
	-- If no watcher caught this (frame not in a "Frames" folder), animate now.
	if not _frameJanitors[frame] then
		runOpen(frame, d)
		tweenBlur(8, d)
	end
end

--[[
	Close a frame explicitly.
	Preferred usage: set frame.Visible = false (the watcher handles animation).
	duration: default 0.25s (S1 — all exits ≈ 62% of entry; never 0.4s).
]]
function FrameTransitions.Close(frame: Frame, duration: number?)
	if not frame then
		warn("[UIAnimator/FrameTransitions] Close called with nil frame")
		return
	end
	local d = duration or 0.25
	frame.Visible = false
	-- If no watcher caught this (frame not in a "Frames" folder), animate now.
	if not _frameJanitors[frame] then
		runClose(frame, d)
		tweenBlur(0, d)
	end
end

return FrameTransitions
