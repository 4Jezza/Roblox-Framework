--!strict
--[==[
	UIAnimator Controller
	---------------------
	Higher-level orchestrator that sits above the vendored Twinkle package
	(src/Client/Client/Packages/UIAnimator). Twinkle remains the underlying
	primitive; this controller exposes a stable, project-flavoured API so
	call-sites never reach for Twinkle directly.

	Knit Name: "UIAnimator"
	Studio path: StarterPlayer.StarterPlayerScripts.Client.Controllers.UIAnimator
	Does NOT collide with Packages.UIAnimator (different parent).

	KnitStart also forces landscape orientation on touch-only mobile devices
	(no keyboard, no gamepad) — deferred 1s so the boot screen settles first.

	Per architecture.md § Require Paths — Knit from ReplicatedStorage.Packages.Knit.
	Per api-reference.md § 6.1 Twinkle UIAnimator and § 3.1 Janitor.

	Public API additions (Presets):
	  :Confetti(opts?)
	  :TagShiny(button)
	  :RotateOscillate(guiObject, opts?) -> Handle
	  :BindNumberLabel(label, getValue, opts?) -> NumberHandle
	  :BindPlayerDataNumber(label, dataPath, opts?) -> NumberHandle
	  :BindReplicaNumber(label, replica, dataPath, opts?) -> NumberHandle
	  :Countdown(label, opts) -> CountdownHandle
	  :Enlargen(guiObject, opts?) -> Handle
	  :Shrink(guiObject, opts?) -> Handle
	  :ShowNotification(messageOrOpts) -> NotificationHandle?
	  :Notify(message)
	  :NotifyError(message)
	  :NotifyTutorial(message)
	  :NotifySpecial(message)
]==]

local Players         = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Knit = require(game.ReplicatedStorage.Packages.Knit)

-- Children (module-as-folder pattern per architecture.md § Module-as-folder)
local HoverEffects     = require(script.HoverEffects)
local FrameTransitions = require(script.FrameTransitions)
local StrokeScaler     = require(script.StrokeScaler)
local Presets          = require(script.Presets)

local UIAnimatorController = Knit.CreateController { Name = "UIAnimator" }

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function UIAnimatorController:KnitStart()
	-- Boot all sub-modules. Each owns its own Janitor; init.luau does not hold
	-- connections directly so no top-level janitor is needed here.
	HoverEffects.Start()
	FrameTransitions.Start()
	StrokeScaler.Start()
	Presets.Start()

	-- Mobile force-landscape: touch-only devices (no keyboard, no gamepad).
	-- Wrapped in task.spawn so we never block KnitStart's dispatch thread.
	task.spawn(function()
		local isMobile = UserInputService.TouchEnabled
			and not UserInputService.KeyboardEnabled
			and not UserInputService.GamepadEnabled
		if isMobile then
			-- Wait 1s so any boot ScreenGui has time to settle before we flip
			-- orientation (avoids a one-frame layout flash on slower devices).
			task.wait(1)
			local player = Players.LocalPlayer
			if not player then
				warn("[UIAnimator/init] mobile landscape: LocalPlayer missing — orientation not forced")
				return
			end
			local playerGui = player:WaitForChild("PlayerGui", 10)
			if playerGui then
				local pg = playerGui :: PlayerGui
				pg.ScreenOrientation = Enum.ScreenOrientation.LandscapeRight
			else
				warn("[UIAnimator/init] mobile landscape: PlayerGui missing after 10s — orientation not forced")
			end
		end
	end)

	-- Hide notification templates so they don't render in their default state.
	-- Done in a separate spawn so a missing HUD never delays KnitStart dispatch.
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
		if not playerGui then
			warn("[UIAnimator/init] HUD.Notification: PlayerGui missing after 10s — templates not hidden")
			return
		end
		local ui     = playerGui:FindFirstChild("Ui")
		local hud    = ui and ui:FindFirstChild("HUD")
		local notif  = hud and hud:FindFirstChild("Notification")
		if not notif then
			warn("[UIAnimator/init] HUD.Notification container not found — notification templates not hidden")
			return
		end
		for _, name in {"Notification", "Error", "SpecialNotification", "Tutorial"} do
			local tpl = notif:FindFirstChild(name)
			if tpl and tpl:IsA("GuiObject") then
				local go = tpl :: GuiObject
				go.Visible = false
			end
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public API — frame management (existing)
-- ---------------------------------------------------------------------------

--[[
	Open a frame with a zoom entrance.
	Delegates to FrameTransitions which drives UIScale + optional blur.
	duration: default 0.4s (S1 Duration Playbook — standard modal open).
]]
function UIAnimatorController:OpenFrame(frame: Frame, duration: number?)
	if not frame then
		warn("[UIAnimator/init] OpenFrame called with nil frame")
		return
	end
	FrameTransitions.Open(frame, duration or 0.4)
end

--[[
	Close a frame with a zoom exit.
	duration: default 0.25s (S1 — all exits ≈ 62% of entry; never 0.4s).
]]
function UIAnimatorController:CloseFrame(frame: Frame, duration: number?)
	if not frame then
		warn("[UIAnimator/init] CloseFrame called with nil frame")
		return
	end
	FrameTransitions.Close(frame, duration or 0.25)
end

--[[
	Manually wire hover/press effects onto a button that is NOT yet
	tagged with the "Animatable" CollectionService tag.
	(Tagged buttons are handled automatically by HoverEffects.Start.)
]]
function UIAnimatorController:TagButton(button: GuiButton)
	if not button then
		warn("[UIAnimator/init] TagButton called with nil button")
		return
	end
	HoverEffects.WireButton(button)
end

-- ---------------------------------------------------------------------------
-- Public API — Presets
-- ---------------------------------------------------------------------------

--[[
	Fire a screen-space confetti burst.
	opts.amount   default 250
	opts.spawnPos default nil (randomised top strip)
	opts.sound    default "UI.Reward.Fireworks"; pass Presets.Confetti.NoSound
	              to suppress.
]]
function UIAnimatorController:Confetti(opts: any?)
	Presets.Confetti.Emit(opts)
end

--[[
	Apply the periodic gradient-shine flash to a specific GuiButton.
	Equivalent to adding the "ShiningButton" CS tag at runtime.
]]
function UIAnimatorController:TagShiny(button: GuiButton)
	if not button then
		warn("[UIAnimator/init] TagShiny called with nil button")
		return
	end
	Presets.ShiningButton.Tag(button)
end

--[[
	Apply slow back-and-forth rotation to a GuiObject.
	Returns Handle: { Cancel, IsRunning }.
	opts: { angle=5, period=1.6, smoothTime=0.25 }
]]
function UIAnimatorController:RotateOscillate(guiObject: GuiObject, opts: any?): any
	if not guiObject then
		warn("[UIAnimator/init] RotateOscillate called with nil GuiObject")
		return { Cancel = function() end, IsRunning = function() return false end }
	end
	return Presets.RotateOscillate.Apply(guiObject, opts)
end

--[[
	Bind a TextLabel to an explicit getter function.
	The label text is driven by a critically-damped spring (S4).
	Returns NumberHandle: { Refresh, Unbind, GetDisplayed }.
	opts: { format="suffix"|"commas", smoothTime=0.25, impulseOnDelta=0.08, poll=nil }
]]
function UIAnimatorController:BindNumberLabel(
	label:    TextLabel,
	getValue: () -> number,
	opts:     any?
): any
	if not label then
		warn("[UIAnimator/init] BindNumberLabel called with nil label")
		return { Refresh = function() end, Unbind = function() end, GetDisplayed = function() return 0 end }
	end
	return Presets.NumberLabel.BindExplicit(label, getValue, opts)
end

--[[
	Bind a TextLabel to a PlayerData path.
	Reactive — subscribes to PlayerData.OnSet(dataPath).
	dataPath example: {"cash"}
]]
function UIAnimatorController:BindPlayerDataNumber(
	label:    TextLabel,
	dataPath: {string},
	opts:     any?
): any
	if not label then
		warn("[UIAnimator/init] BindPlayerDataNumber called with nil label")
		return { Refresh = function() end, Unbind = function() end, GetDisplayed = function() return 0 end }
	end
	return Presets.NumberLabel.BindPlayerData(label, dataPath, opts)
end

--[[
	Bind a TextLabel to a Mad Studio Replica path.
	Reactive — subscribes to replica:OnSet(dataPath).
	Auto-cleans via replica.Maid on replica destroy.
]]
function UIAnimatorController:BindReplicaNumber(
	label:    TextLabel,
	replica:  any,
	dataPath: {string},
	opts:     any?
): any
	if not label then
		warn("[UIAnimator/init] BindReplicaNumber called with nil label")
		return { Refresh = function() end, Unbind = function() end, GetDisplayed = function() return 0 end }
	end
	return Presets.NumberLabel.BindReplica(label, replica, dataPath, opts)
end

--[[
	Start a countdown/countup on a TextLabel.
	opts.from    (required)
	opts.to      default 0
	opts.tickInterval default 0.1
	opts.onWholeNumber  optional callback(n)
	opts.onComplete     optional callback()
	opts.soundName      default "HeavyCountdown"
	opts.pairSound      optional handle with :SetProgress(t)
	Returns CountdownHandle: { Cancel, IsRunning, GetCurrent }.
]]
function UIAnimatorController:Countdown(label: TextLabel, opts: any): any
	if not label then
		warn("[UIAnimator/init] Countdown called with nil label")
		return { Cancel = function() end, IsRunning = function() return false end, GetCurrent = function() return 0 end }
	end
	return Presets.Countdown.Start(label, opts)
end

-- ---------------------------------------------------------------------------
-- Public API — Notification presets
-- ---------------------------------------------------------------------------

--[[
	Scale a GuiObject up from fromScale → toScale via Spring.
	Returns Handle: { Cancel, Completed, IsRunning }.
	opts: { fromScale=0.6, toScale=1.0, smoothTime=0.18, completedFn? }
]]
function UIAnimatorController:Enlargen(guiObject: GuiObject, opts: any?): any
	if not guiObject then
		warn("[UIAnimator/init] Enlargen called with nil GuiObject")
		return { Cancel = function() end, Completed = { Connect = function() end }, IsRunning = function() return false end }
	end
	return Presets.Enlargen.Apply(guiObject, opts)
end

--[[
	Scale a GuiObject down from fromScale → toScale via Spring.
	Returns Handle: { Cancel, Completed, IsRunning }.
	opts: { fromScale=1.0, toScale=0.0, smoothTime=0.18, completedFn? }
]]
function UIAnimatorController:Shrink(guiObject: GuiObject, opts: any?): any
	if not guiObject then
		warn("[UIAnimator/init] Shrink called with nil GuiObject")
		return { Cancel = function() end, Completed = { Connect = function() end }, IsRunning = function() return false end }
	end
	return Presets.Shrink.Apply(guiObject, opts)
end

--[[
	Show a notification banner. Accepts a string or NotificationOpts table.
	Returns NotificationHandle: { Dismiss, IsActive } or nil if the
	HUD.Notification container or template is missing.
]]
function UIAnimatorController:ShowNotification(messageOrOpts: any): any?
	return Presets.Notification.Show(messageOrOpts)
end

--[[
	Convenience: show a default-template notification with all defaults.
]]
function UIAnimatorController:Notify(message: string): ()
	Presets.Notification.Show(message)
end

--[[
	Convenience: show an Error-template notification.
]]
function UIAnimatorController:NotifyError(message: string): ()
	Presets.Notification.Show({ message = message, template = "Error" })
end

--[[
	Convenience: show a Tutorial-template notification (persistent, duration=999).
]]
function UIAnimatorController:NotifyTutorial(message: string): ()
	Presets.Notification.Show({ message = message, template = "Tutorial", duration = 999 })
end

--[[
	Convenience: show a SpecialNotification-template notification.
]]
function UIAnimatorController:NotifySpecial(message: string): ()
	Presets.Notification.Show({ message = message, template = "SpecialNotification" })
end

return UIAnimatorController
