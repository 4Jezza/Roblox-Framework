--!strict
--[[
	NotificationClient
	------------------
	Displays transient notification banners to the local player by delegating
	to UIAnimator:ShowNotification, which drives the HUD.Notification template
	cloning + Enlargen/Shrink lifecycle.

	Public API
	----------
	NotificationClient.Show(msg, templateName?, color?, duration?)
	    Delegates to UIAnimator:ShowNotification. The color parameter is
	    accepted for backward compatibility but is currently ignored — template
	    styling is handled by the Studio frames themselves.

	NotificationClient.Success(msg, color?)   → Show with "Notification" template
	NotificationClient.Error(msg)             → Show with "Error" template
	NotificationClient.ShowTutorial(msg)      → persistent tutorial banner; returns dismiss()

	UIAnimator lookup is lazy (via Knit.GetController) so load order is safe.
	Falls back to print when UIAnimator is not yet ready (rule_8).

	Per architecture.md § Require Paths.
	Per api-reference.md § 1.1 Knit — Knit.GetController (lazy).
	Per CLAUDE.md rule_8 — defensive logging + fallback on nil controller.
	Per conventions.md § Module file structure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(game.ReplicatedStorage.Packages.Knit)
local Bridges = require(ReplicatedStorage.Shared.Bridges)

local NotificationClient = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local DISPLAY_TIME = 3.5

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Lazy getter — Knit.GetController is only valid after Knit.Start() resolves.
local _uianim: any = nil
local function getUIAnimator(): any?
	if _uianim then return _uianim end
	local ok, ctrl = pcall(function()
		return Knit.GetController("UIAnimator")
	end)
	if ok and ctrl then
		_uianim = ctrl
	end
	return _uianim
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Show a notification banner.
	templateName: "Notification" | "Error" | "SpecialNotification" | "Tutorial"
	color:        kept for backward-compat; ignored (templates carry their own style).
	duration:     override display seconds.
]]
function NotificationClient.Show(msg: string, templateName: string?, color: Color3?, duration: number?)
	local ua = getUIAnimator()
	if not ua then
		warn("[NotificationClient] UIAnimator not ready — printing instead: " .. tostring(msg))
		print(string.format("[NotificationClient] [%s] %s", templateName or "Notification", msg))
		return
	end
	ua:ShowNotification({
		message  = msg,
		template = templateName or "Notification",
		duration = duration or DISPLAY_TIME,
		-- color is currently ignored — templates carry their own styling.
	})
end

--[[
	Shorthand for a success-themed notification (uses default "Notification" template).
]]
function NotificationClient.Success(msg: string, color: Color3?)
	NotificationClient.Show(msg, "Notification", color)
end

--[[
	Shorthand for an error-themed notification.
]]
function NotificationClient.Error(msg: string)
	NotificationClient.Show(msg, "Error", Color3.fromRGB(255, 80, 80))
end

--[[
	Show a persistent tutorial notification.
	Returns a dismiss function — call it to remove the banner when the step ends.
]]
function NotificationClient.ShowTutorial(msg: string): () -> ()
	local ua = getUIAnimator()
	if not ua then
		warn("[NotificationClient] UIAnimator not ready — printing instead: " .. tostring(msg))
		print(string.format("[NotificationClient] [Tutorial] %s", msg))
		local dismissed = false
		return function()
			if dismissed then return end
			dismissed = true
		end
	end

	local handle = ua:ShowNotification({
		message  = msg,
		template = "Tutorial",
		duration = 999, -- persistent until explicitly dismissed
	})

	local dismissed = false
	return function()
		if dismissed or not handle then return end
		dismissed = true
		-- Dismiss is a plain function field ( () -> () ), NOT a method —
		-- colon-call would silently pass `handle` as the discarded first arg.
		handle.Dismiss()
	end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function NotificationClient:Initialize()
	-- Wire server-pushed notifications.
	-- Capture fields into locals before task.spawn — architecture.md § Critical Bans
	-- (no yield in bridge handlers; ShowNotification yields via task.wait(duration)).
	Bridges.Notify:Connect(function(data: { type: string, message: string, duration: number? })
		if not data or type(data) ~= "table" then
			warn("[NotificationClient] Notify: malformed payload —", data)
			return
		end
		local msg = data.message
		local dur = data.duration
		-- Map semantic type (Success/Error/Info) to actual template name.
		-- Notify payload types are semantic; HUD templates are Notification/Error/etc.
		local TYPE_TO_TEMPLATE: { [string]: string } = {
			Success  = "Notification",
			Error    = "Error",
			Info     = "Notification",
			Special  = "SpecialNotification",
			Tutorial = "Tutorial",
		}
		local template = TYPE_TO_TEMPLATE[data.type] or "Notification"
		task.spawn(function()
			NotificationClient.Show(msg, template, nil, dur)
		end)
	end)

	print("[NotificationClient] Initialized.")
end

return NotificationClient
