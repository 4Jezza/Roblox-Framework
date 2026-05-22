--!strict
--[[
	Notification
	------------
	Lifecycle preset that clones a template from HUD.Notification, plays an
	Enlargen entrance, waits, plays a Shrink exit, then destroys the clone.

	Templates (all children of PlayerGui.Ui.HUD.Notification):
	  "Notification"       — default
	  "Error"
	  "SpecialNotification"
	  "Tutorial"

	Each template must contain a TextLabel named "Label" (or any TextLabel
	descendant — fallback searches recursively).

	Public API:
	  Notification.Show(messageOrOpts) -> NotificationHandle?

	NotificationHandle: { Dismiss: () -> (), IsActive: () -> boolean }

	Per api-reference.md § 3.1 Janitor — explicit "Disconnect".
	Per api-reference.md § 3.2 Signal — lowercase Signal.new().
	Per CLAUDE.md rule_8 — defensive logging on all nil lookups.
	Per architecture.md § Capture state before task.wait.
	Per conventions.md § Module file structure.
]]

local Players = game:GetService("Players")
local Knit    = require(game.ReplicatedStorage.Packages.Knit)
local Janitor = require(game.ReplicatedStorage.Packages.Janitor)

local Enlargen = require(script.Parent.Enlargen)
local Shrink   = require(script.Parent.Shrink)

local Notification = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type NotificationOpts = {
	message:     string,
	template:    ("Notification" | "Error" | "SpecialNotification" | "Tutorial")?,
	duration:    number?,
	sound:       (string | boolean)?,
	onDismissed: (() -> ())?,
}

export type NotificationHandle = {
	Dismiss:  () -> (),
	IsActive: () -> boolean,
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local DEFAULT_TEMPLATE  = "Notification"
local DEFAULT_DURATION  = 4
local DEFAULT_SOUND     = "UI.Notification"
-- Appear (Enlargen) settle window. Spring smoothTime tuned to 0.08 so the
-- "snappy pop" visually settles in ~0.18s (per api-reference.md § 5.1 Spring +
-- § Project — UIAnimator Enlargen). We then task.wait(APPEAR_SECONDS) so the
-- hold duration that follows is deterministic regardless of spring damping.
local APPEAR_SECONDS    = 0.18  -- was 0.4; faster appear per user request
local APPEAR_SMOOTHTIME = 0.08  -- was 0.18; snappier spring matches the shorter wait

-- Lazy SoundController getter — deferred so load order doesn't matter.
local _soundController: any = nil
local function getSoundController(): any?
	if _soundController then return _soundController end
	local ok, ctrl = pcall(function()
		return Knit.GetController("SoundController")
	end)
	if ok and ctrl then
		_soundController = ctrl
	end
	return _soundController
end

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function resolveContainer(): Frame?
	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/Notification] resolveContainer: LocalPlayer missing — cannot show notification")
		return nil
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/Notification] resolveContainer: PlayerGui missing — cannot show notification")
		return nil
	end
	local ui = playerGui:FindFirstChild("Ui")
	local hud = ui and ui:FindFirstChild("HUD")
	local container = hud and hud:FindFirstChild("Notification")
	if not container then
		warn("[UIAnimator/Notification] resolveContainer: PlayerGui.Ui.HUD.Notification not found — cannot show notification")
		return nil
	end
	return container :: Frame
end

local function findLabel(clone: Frame): TextLabel?
	-- Prefer child named "Label"; fall back to any TextLabel descendant.
	local byName = clone:FindFirstChild("Label")
	if byName and byName:IsA("TextLabel") then
		return byName :: TextLabel
	end
	local byClass = clone:FindFirstChildWhichIsA("TextLabel", true)
	if byClass then
		return byClass :: TextLabel
	end
	return nil
end

local function playSound(soundOpt: (string | boolean)?)
	-- soundOpt nil or string → play; false → suppress.
	if soundOpt == false then return end
	local name = (typeof(soundOpt) == "string") and (soundOpt :: string) or DEFAULT_SOUND
	local ctrl = getSoundController()
	if ctrl then
		local ok, err = pcall(function()
			ctrl:Play(name)
		end)
		if not ok then
			warn("[UIAnimator/Notification] sound play failed:", err)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Show a notification. Accepts a plain string (uses all defaults) or a
	NotificationOpts table.
	Returns a NotificationHandle, or nil if the container/template is missing.
]]
function Notification.Show(messageOrOpts: string | NotificationOpts): NotificationHandle?
	-- Normalise input.
	local opts: NotificationOpts
	if typeof(messageOrOpts) == "string" then
		opts = { message = messageOrOpts }
	else
		opts = messageOrOpts :: NotificationOpts
	end

	-- Capture opts fields into locals before any yield (architecture.md § Capture state).
	local message      = opts.message
	local templateName = opts.template    or DEFAULT_TEMPLATE
	local duration     = opts.duration    or DEFAULT_DURATION
	local soundOpt     = opts.sound       -- nil, string, or false
	local onDismissed  = opts.onDismissed

	-- Step 1 — resolve the container.
	local container = resolveContainer()
	if not container then
		return nil
	end

	-- Step 2 — resolve the template.
	local template = container:FindFirstChild(templateName)
	if not template or not template:IsA("GuiObject") then
		warn("[UIAnimator/Notification] template '" .. templateName .. "' not found in HUD.Notification — cannot show notification")
		return nil
	end

	-- Step 3 — clone and configure.
	local clone = (template :: Frame):Clone()
	clone.Name = "Active_" .. templateName

	local label = findLabel(clone)
	if not label then
		warn("[UIAnimator/Notification] no Label TextLabel found in template '" .. templateName .. "' — text will be empty")
	else
		label.Text = message
	end

	-- Step 4 — make visible and parent into the container.
	clone.Visible = true
	clone.Parent = container

	-- Per-call janitor owns all cleanup for this notification lifecycle.
	local j       = Janitor.new()
	local active  = true

	-- Dismiss function shared between the handle and the internal lifecycle.
	-- We store it in a local so the lifecycle can call it on natural expiry too.
	local dismissed = false
	local enlargeHandle: Enlargen.Handle? = nil
	local shrinkHandle:  Shrink.Handle?   = nil

	local function runDismiss()
		if dismissed then return end
		dismissed = true
		active = false

		-- Cancel whichever animation is in flight, then immediately shrink.
		if enlargeHandle and enlargeHandle.IsRunning() then
			enlargeHandle.Cancel()
		end
		if shrinkHandle and shrinkHandle.IsRunning() then
			-- already running — let it finish; don't double-Shrink
			return
		end

		-- Run shrink then destroy.
		shrinkHandle = Shrink.Apply(clone, { toScale = 0.0 })
		shrinkHandle.Completed:Connect(function()
			if clone and clone.Parent then
				clone:Destroy()
			end
			j:Destroy()
			if onDismissed then
				task.spawn(onDismissed)
			end
		end)
	end

	-- Build handle before spawning the lifecycle so callers can call Dismiss()
	-- even if the clone wasn't fully set up yet.
	local handle: NotificationHandle = {
		Dismiss  = runDismiss,
		IsActive = function()
			return active
		end,
	}

	-- Lifecycle runs in its own thread.
	task.spawn(function()
		-- Step 5 — play sound.
		playSound(soundOpt)

		-- Step 6 — entrance animation.
		-- Deterministic appear: spring-enlargen with smoothTime tuned so the
		-- pop settles in ~0.4s, then a fixed task.wait(APPEAR_SECONDS) so the
		-- hold/exit timing that follows is predictable. Per api-reference.md
		-- § 5.1 Spring (smoothTime ~= time to reach target) + § Project —
		-- UIAnimator Enlargen ("snappy pop" tuning).
		enlargeHandle = Enlargen.Apply(clone, { smoothTime = APPEAR_SMOOTHTIME })
		task.wait(APPEAR_SECONDS)

		-- Step 7 — hold for duration.
		-- Capture active before wait; Dismiss() may fire during this gap.
		local capturedDuration = duration
		task.wait(capturedDuration)

		-- Guard: if Dismiss was called during the wait, bail out.
		if dismissed then return end

		-- Step 8 — exit animation.
		active = false
		shrinkHandle = Shrink.Apply(clone, { toScale = 0.0 })
		shrinkHandle.Completed:Connect(function()
			-- Step 9 — destroy clone.
			if clone and clone.Parent then
				clone:Destroy()
			end
			j:Destroy()
			-- Step 10 — fire dismissed callback.
			if onDismissed and not dismissed then
				task.spawn(onDismissed)
			end
			dismissed = true
		end)
	end)

	return handle
end

return Notification
