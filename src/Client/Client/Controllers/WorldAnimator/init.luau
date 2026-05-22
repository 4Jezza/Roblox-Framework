--[[
	WorldAnimator
	-------------
	Knit Controller. Drives world-space animations by mapping named presets to
	Replica tokens (via ReplicaController:OnReplicaNew) or to arbitrary
	Instances (via :Apply for one-shots).

	Public API
	----------
	WorldAnimator:Apply(presetName, target, opts?) -> Handle
	    One-shot: run `presetName` on `target` immediately.
	    Handle = { Cancel() -> (), Completed: Signal<>, IsRunning() -> boolean }

	WorldAnimator:Bind(token, presetName, opts?) -> { Disconnect() -> () }
	    For every replica of `token` that arrives, calls :Apply on
	    replica.BoundInstance. Ties the preset's Cancel to replica.Maid so the
	    animation stops when the replica is destroyed.

	WorldAnimator:Unbind(token)
	    Cancels all in-flight handles for `token` and removes the binding.

	WorldAnimator.Presets  (read-only reference to the Presets registry)

	Per architecture.md § Visual / Animation Policy — client-only cosmetic.
	Per architecture.md § Require Paths — Knit, Janitor, script.Presets.
	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" on connections.
	Per api-reference.md § 2.3 Replica client — replica.BoundInstance, replica.Maid.
	Per api-reference.md § 1.1 Knit — GetController only safe in KnitStart.
	Per conventions.md § Module file structure — section dividers, header, warn format.
]]

-- Convention: all preset opts tables use lowercase keys (e.g. amplitude, period, axis, smoothTime).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local Presets = require(script.Presets)

local WorldAnimator = Knit.CreateController {
	Name = "WorldAnimator",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- _bindings[token] = {
--     presetName : string,
--     opts       : any?,
--     janitor    : Janitor,  -- owns the OnReplicaNew conn + per-handle sub-janitors
--     disconnect : () -> (), -- revoke the OnReplicaNew subscription
-- }
WorldAnimator._bindings = {} :: {
	[string]: {
		presetName: string,
		opts: any,
		janitor: any,
		disconnect: () -> (),
	},
}

WorldAnimator.Presets = Presets

-- Obtained in KnitStart — GetController is only safe after all controllers register.
WorldAnimator._replicaController = nil :: any

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

--- Resolve the position-bearing BasePart from any Instance.
--- Returns (anchor, kind) or (nil, nil) on failure.
--- kind = "BasePart" | "PrimaryPart" | "Model-noPrimary"
local function _resolveAnchor(target: Instance): (BasePart?, string?)
	if target:IsA("BasePart") then
		return target :: BasePart, "BasePart"
	end
	if target:IsA("Model") then
		local m = target :: Model
		if m.PrimaryPart then
			return m.PrimaryPart, "PrimaryPart"
		end
		local first = m:FindFirstChildWhichIsA("BasePart", true)
		if first then
			warn(
				"[WorldAnimator] "
					.. target:GetFullName()
					.. " has no PrimaryPart — using "
					.. first.Name
			)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator] _resolveAnchor: no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- One-shot: run `presetName` on `target` immediately.
--- Creates a fresh Janitor, calls the preset, returns the Handle augmented so
--- Handle.Cancel() also cleans the janitor.
function WorldAnimator:Apply(presetName: string, target: Instance, opts: any?): any
	local preset = Presets[presetName]
	if not preset then
		warn("[WorldAnimator] :Apply — preset '" .. tostring(presetName) .. "' not found — skipping")
		local Signal = require(ReplicatedStorage.Packages.Signal)
		local dummy  = Signal.new()
		dummy:Fire()
		return {
			Cancel    = function() end,
			Completed = dummy,
			IsRunning = function() return false end,
		}
	end

	local anchor = _resolveAnchor(target)
	if not anchor then
		-- _resolveAnchor already warned; return a no-op handle
		local Signal = require(ReplicatedStorage.Packages.Signal)
		local dummy  = Signal.new()
		dummy:Fire()
		return {
			Cancel    = function() end,
			Completed = dummy,
			IsRunning = function() return false end,
		}
	end

	local presetJanitor = Janitor.new()
	local handle        = preset(target, opts, presetJanitor)

	-- Augment Cancel so it also tears down the janitor
	local originalCancel = handle.Cancel
	handle.Cancel = function()
		originalCancel()
		presetJanitor:Destroy()
	end

	return handle
end

--- Subscribe: for every replica of `token` that arrives, run `presetName` on
--- replica.BoundInstance. The handle's Cancel is tied to replica.Maid so the
--- animation stops automatically when the replica is destroyed.
--- Returns { Disconnect() } — call to revoke this binding without affecting others.
function WorldAnimator:Bind(token: string, presetName: string, opts: any?): { Disconnect: () -> () }
	if self._bindings[token] then
		warn("[WorldAnimator] :Bind — token '" .. token .. "' already bound — call :Unbind first")
		return { Disconnect = function() end }
	end

	if not Presets[presetName] then
		warn("[WorldAnimator] :Bind — preset '" .. tostring(presetName) .. "' not found — bind skipped")
		return { Disconnect = function() end }
	end

	local rc = self._replicaController
	if not rc then
		warn(
			"[WorldAnimator] :Bind called before KnitStart — ReplicaController unavailable; "
				.. "bind for token '"
				.. token
				.. "' will not activate"
		)
		return { Disconnect = function() end }
	end

	local bindJanitor = Janitor.new()

	local replicaConn = rc:OnReplicaNew(token, function(replica)
		local boundInst = replica.BoundInstance
		if not boundInst then
			warn(
				"[WorldAnimator] :Bind — replica for token '"
					.. token
					.. "' has no BoundInstance — animation skipped"
			)
			return
		end

		local handle = self:Apply(presetName, boundInst, opts)

		-- Tie Cancel to replica.Maid so animation stops when replica is destroyed
		local maidOk = pcall(function()
			replica.Maid:Add(function()
				handle.Cancel()
			end)
		end)
		if not maidOk then
			warn(
				"[WorldAnimator] :Bind — could not attach Cancel to replica.Maid for token '"
					.. token
					.. "' — handle will not auto-cancel on replica destroy"
			)
		end

		-- Also register Cancel under the binding janitor so :Unbind cleans it
		bindJanitor:Add(function()
			handle.Cancel()
		end, true)
	end)

	bindJanitor:Add(function()
		replicaConn.Disconnect()
	end, true)

	self._bindings[token] = {
		presetName = presetName,
		opts       = opts,
		janitor    = bindJanitor,
		disconnect = function()
			replicaConn.Disconnect()
		end,
	}

	return {
		Disconnect = function()
			local binding = self._bindings[token]
			if binding then
				binding.janitor:Destroy()
				self._bindings[token] = nil
			end
		end,
	}
end

--- Remove the binding for `token` and cancel all in-flight handles registered
--- under it. Does not affect bindings for other tokens.
function WorldAnimator:Unbind(token: string)
	local binding = self._bindings[token]
	if not binding then
		warn("[WorldAnimator] :Unbind('" .. tostring(token) .. "') — no active binding found — no-op")
		return
	end
	binding.janitor:Destroy()
	self._bindings[token] = nil
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function WorldAnimator:KnitInit()
	-- Nothing blocking here; _replicaController obtained in KnitStart.
end

function WorldAnimator:KnitStart()
	-- Per api-reference.md § 1.1 Knit Client — GetController safe in KnitStart.
	local ok, ctrl = pcall(function()
		return Knit.GetController("ReplicaController")
	end)
	if ok and ctrl then
		self._replicaController = ctrl
	else
		warn(
			"[WorldAnimator] ReplicaController not found — "
				.. ":Bind calls will no-op until it is registered"
		)
	end
end

return WorldAnimator
