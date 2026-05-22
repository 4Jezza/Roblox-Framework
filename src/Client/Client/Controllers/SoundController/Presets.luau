--[==[
	SoundController/Presets
	-----------------------
	Registry of named sound presets for SoundController.

	Each preset is a table of PlayOpts and/or a wrapper function keyed by a
	short name. Future agents should add entries here rather than hardcoding
	opts at call sites.

	Shape (for new authors):
	  presetName = {
	    volume:  number?,   -- 0..1 scale applied on top of category volume
	    pitch:   number?,   -- default 1.0
	    looped:  boolean?,  -- default false
	  }

	  OR a function:
	  presetName = function(controller: SoundController): SoundHandle
	    -- compose multiple :Play or :PlayLayered calls
	  end

	Usage example (once entries are added):
	  -- local Presets = require(script.Parent.Presets)
	  -- SoundController:Play("UI.Click", Presets.Click)

	This table intentionally ships empty. Add entries as the project accretes
	sounds — do NOT add entries whose Sound assets don't yet exist in Studio.

	Mirrors the shape of WorldAnimator/Presets.luau (empty registry + doc comment
	for future authors).
]==]

return {} :: {
	[string]: { volume: number?, pitch: number?, looped: boolean? }
		| (controller: any) -> any,
}
