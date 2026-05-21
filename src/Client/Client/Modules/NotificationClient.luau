--[[
    NotificationClient
    ------------------
    Displays transient notification banners to the local player.

    Public API
    ----------
    NotificationClient.Show(msg, templateName?, color?, duration?)
        Main entry point. Clones a template from Ui.Notification.Templates.<templateName>
        and parents it into the Ui.Notification container.
        De-duplicates by msg key — calling Show() with an already-visible message
        bumps the counter and resets the dismiss timer.

    NotificationClient.Success(msg, color?)   → Show with 'Success' template
    NotificationClient.Error(msg)             → Show with 'Error' template + red tint
    NotificationClient.ShowTutorial(msg)      → persistent tutorial banner; returns dismiss()

    TODO: Replace print stubs with real clone/tween logic once StarterGui
          Ui.Notification container and Templates exist (see Brainrot NotificationClient
          for the full TweenService fade-in/out pattern and activeNotifications map).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridges = require(ReplicatedStorage.Shared.Bridges)

local NotificationClient = {}

local DISPLAY_TIME = 3.5

-- ========== STUB INTERNALS ==========

--- Show a notification banner.
--- @param msg          The text to display.
--- @param templateName Template key ('Notification' | 'Success' | 'Error' | 'Tutorial'). Defaults to 'Notification'.
--- @param color        Optional text color override.
--- @param duration     Override display duration in seconds.
function NotificationClient.Show(msg: string, templateName: string?, color: Color3?, duration: number?)
	local tplName     = templateName or "Notification"
	local displayTime = duration or DISPLAY_TIME
	-- TODO: Clone Ui.Notification.Templates.<tplName>, set label text + color,
	--       parent into Ui.Notification container, tween size in (Back, Out),
	--       task.delay(displayTime, fadeOut), de-duplicate by msg key.
	print(string.format("[NotificationClient] [%s] %s (%.1fs)", tplName, msg, displayTime))
end

--- Shorthand for a success-themed notification.
function NotificationClient.Success(msg: string, color: Color3?)
	NotificationClient.Show(msg, "Success", color)
end

--- Shorthand for an error-themed notification (red tint).
function NotificationClient.Error(msg: string)
	NotificationClient.Show(msg, "Error", Color3.fromRGB(255, 80, 80))
end

--- Show a persistent tutorial notification at the top of the stack.
--- Returns a dismiss function — call it to remove the banner when the step ends.
--- Only one tutorial notification is active at a time; a new call dismisses the previous.
function NotificationClient.ShowTutorial(msg: string): () -> ()
	-- TODO: Clone Ui.Notification.Templates.Tutorial, set LayoutOrder = -1,
	--       parent into container, store dismiss callback, return it.
	print(string.format("[NotificationClient] [Tutorial] %s", msg))
	local dismissed = false
	return function()
		if dismissed then return end
		dismissed = true
		print(string.format("[NotificationClient] [Tutorial] dismissed: %s", msg))
	end
end

-- ========== INITIALIZATION ==========

function NotificationClient:Initialize()
	-- Hide all template frames so they don't render as-is
	-- TODO: walk Ui.Notification.Templates children and set Visible = false
	--       (see Brainrot pattern: for _, tpl in TEMPLATES do tpl.Visible = false end)

	-- Wire server-pushed notifications
	Bridges.Notify:Connect(function(data: { type: string, message: string, duration: number? })
		NotificationClient.Show(data.message, data.type, nil, data.duration)
	end)

	print("[NotificationClient] Initialized.")
end

return NotificationClient
