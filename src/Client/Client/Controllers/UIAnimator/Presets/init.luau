--!strict
--[[
	Presets
	-------
	Assembly point for all UIAnimator preset sub-modules. Returns a
	registry table so UIAnimator/init.luau can call a single
	Presets.Start() that boots every sub-system.

	Public API (consumed only by UIAnimator/init.luau):
	  Presets.Confetti        -- Confetti.Emit(opts?)
	  Presets.ShiningButton   -- ShiningButton.Tag / Untag / Start
	  Presets.RotateOscillate -- RotateOscillate.Apply(obj, opts?) -> Handle
	  Presets.NumberLabel     -- BindExplicit / BindPlayerData / BindReplica
	  Presets.Countdown       -- Countdown.Start(label, opts) -> Handle
	  Presets.Enlargen        -- Enlargen.Apply(obj, opts?) -> Handle
	  Presets.Shrink          -- Shrink.Apply(obj, opts?) -> Handle
	  Presets.Notification    -- Notification.Show(msgOrOpts) -> NotificationHandle?

	Per architecture.md § Module-as-folder convention (rule_16).
	Per api-reference.md § 3.1 Janitor.
]]

local Confetti        = require(script.Confetti)
local ShiningButton   = require(script.ShiningButton)
local RotateOscillate = require(script.RotateOscillate)
local NumberLabel     = require(script.NumberLabel)
local Countdown       = require(script.Countdown)
local Enlargen        = require(script.Enlargen)
local Shrink          = require(script.Shrink)
local Notification    = require(script.Notification)

-- ---------------------------------------------------------------------------
-- Assembly
-- ---------------------------------------------------------------------------

local Presets = {
	Confetti        = Confetti,
	ShiningButton   = ShiningButton,
	RotateOscillate = RotateOscillate,
	NumberLabel     = NumberLabel,
	Countdown       = Countdown,
	Enlargen        = Enlargen,
	Shrink          = Shrink,
	Notification    = Notification,
}

-- Called from UIAnimator/init.luau:KnitStart so every preset that needs
-- a CollectionService watcher boots at the same time as the rest of the
-- controller (after all KnitInit passes have run).
function Presets.Start()
	ShiningButton.Start()
end

return Presets
