--[[
	WorldAnimator/Presets
	---------------------
	Registry of named world-animation presets. Each entry is a function with
	signature:

	    function(target: Instance, opts: any?, janitor: Janitor) -> Handle

	where Handle = { Cancel: () -> (), Completed: Signal<>, IsRunning: () -> boolean }.

	All connections must be registered into `janitor` with explicit "Disconnect" per
	api-reference.md § 3.1 (ZonePlus-gotcha rule).

	Per architecture.md § Module-as-folder convention (rule_16a) — this init
	assembles the registry from child ModuleScripts.
]]

return {
	HoverBob          = require(script.HoverBob),
	SpringGrow        = require(script.SpringGrow),
	SpringShrink      = require(script.SpringShrink),
	SpringVanish      = require(script.SpringVanish),
	SpringMaterialize = require(script.SpringMaterialize),
	ExplodeBounce     = require(script.ExplodeBounce),
	MagnetToPlayer    = require(script.MagnetToPlayer),
	BezierMove        = require(script.BezierMove),
	LinearSpring      = require(script.LinearSpring),
}
