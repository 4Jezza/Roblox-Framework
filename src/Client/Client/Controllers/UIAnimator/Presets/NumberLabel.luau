--!strict
-- NOTE: 347 lines — exceeds rule_9 soft cap. Splitting is worse for
-- findability: all three entry points (BindExplicit/BindPlayerData/BindReplica)
-- share one spring engine and one handle factory. A reader debugging a counter
-- bug needs all three visible together. Splitting would force grep across siblings
-- with no gain in cohesion. Per rule_9: modularity for findability beats line count.
--[[
	NumberLabel
	-----------
	Spring-driven animated number counter for TextLabels. Single internal
	engine, three entry points matching different data sources:

	  BindExplicit(label, getValue, opts)          -> NumberHandle
	  BindPlayerData(label, dataPath, opts)        -> NumberHandle
	  BindReplica(label, replica, dataPath, opts)  -> NumberHandle

	On each data update the spring target is set to the new value. A
	Heartbeat loop drives the label text. On a large delta (>= opts.impulseOnDelta
	fraction of the new value) a UIScale sibling is impulse-pushed for a
	satisfying "pop" (S6 Juice Stack secondary).

	NumberHandle: { Refresh: () -> (), Unbind: () -> (), GetDisplayed: () -> number }

	Default opts:
	  format          = "suffix"   -- "suffix" → Format.Suffix; "commas" → Format.Commas
	  smoothTime      = 0.25       -- Spring.new smoothTime (S4 table — snappy)
	  impulseOnDelta  = 0.08       -- impulse when |delta| >= 8% of new value
	  poll            = nil        -- if set (seconds), poll getValue on this interval

	Per api-reference.md § 5.1 Spring — Spring.new(initial, smoothTime).
	Per api-reference.md § 3.1 Janitor.
	Per api-reference.md § 2.3 Replica client OnSet.
	Per api-reference.md — Format.Suffix / Format.Commas (mandatory for
	  all client-visible numbers — architecture.md § Client-visible numbers).
	Per CLAUDE.md rule_8 — defensive logging.
	Per conventions.md § Module file structure.
]]

local RunService = game:GetService("RunService")

local Janitor     = require(game.ReplicatedStorage.Packages.Janitor)
local Spring      = require(game.ReplicatedStorage.Utility.Spring)
local Format      = require(game.ReplicatedStorage.Utility.Format)

local NumberLabel = {}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type NumberOpts = {
	format:         ("suffix" | "commas")?,
	smoothTime:     number?,
	impulseOnDelta: number?,
	poll:           number?,
}

export type NumberHandle = {
	Refresh:      () -> (),
	Unbind:       () -> (),
	GetDisplayed: () -> number,
}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local MAX_DT           = 1 / 30
local IMPULSE_STRENGTH = 0.15   -- UIScale impulse velocity added on large delta

-- ---------------------------------------------------------------------------
-- Private: shared engine
-- ---------------------------------------------------------------------------

local function getFormatter(fmt: ("suffix" | "commas")?): (number) -> string
	if fmt == "commas" then
		return Format.Commas
	end
	return Format.Suffix  -- default per architecture.md § Client-visible numbers
end

-- Ensure a UIScale exists inside the label; return it.
-- If the label is a TextLabel we place the UIScale as a child.
local function ensureUIScale(label: TextLabel): UIScale
	local existing = label:FindFirstChildOfClass("UIScale")
	if existing then
		return existing :: UIScale
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = label
	return scale
end

local function createHandle(
	label: TextLabel,
	getValue: () -> number,
	opts: NumberOpts?
): NumberHandle
	local o            = opts or {}
	local fmt          = o.format         or "suffix"
	local smoothTime   = o.smoothTime     or 0.25
	local impThreshold = o.impulseOnDelta or 0.08
	local pollInterval = o.poll

	local formatter  = getFormatter(fmt)
	local j          = Janitor.new()
	local uiScale    = ensureUIScale(label)

	-- Spring for the displayed number.
	local initial     = getValue() or 0
	local numSpring   = Spring.new(initial, smoothTime)
	numSpring.Target  = initial

	-- Spring for the UIScale pop (smoothTime 0.12 — snappy pop per S4).
	local scaleSpring  = Spring.new(1, 0.12)
	scaleSpring.Target = 1

	local displayed    = initial
	local heartConn: RBXScriptConnection?

	-- Arm / re-arm Heartbeat loop (only while spring has motion to render).
	local function armLoop()
		if heartConn then return end
		heartConn = RunService.Heartbeat:Connect(function(dt)
			local clamped = math.min(dt, MAX_DT)
			displayed = numSpring:Update(clamped)
			label.Text = formatter(math.floor(displayed + 0.5))

			-- Update UIScale spring.
			local sv = scaleSpring:Update(clamped)
			uiScale.Scale = sv

			-- Settle check: within 0.5 of target AND UIScale within 0.001 of 1.
			local numSettled   = math.abs(numSpring.Current - numSpring.Target) < 0.5
			local scaleSettled = math.abs(scaleSpring.Current - 1) < 0.001

			if numSettled and scaleSettled then
				if heartConn then
					heartConn:Disconnect()
					heartConn = nil
				end
			end
		end)
		j:Add(function()
			if heartConn then
				heartConn:Disconnect()
				heartConn = nil
			end
		end, true, "heartConnCleanup")
	end

	-- Called whenever the source value updates.
	local function onNewValue(newVal: number)
		local delta = math.abs(newVal - numSpring.Target)
		local threshold = math.abs(newVal) * impThreshold
		if delta >= threshold and newVal ~= 0 then
			scaleSpring:Impulse(IMPULSE_STRENGTH)
		end
		numSpring.Target = newVal
		armLoop()
	end

	-- Poll path (explicit poll interval).
	if pollInterval then
		local elapsed = 0
		local pollConn = RunService.Heartbeat:Connect(function(dt)
			elapsed = elapsed + dt
			if elapsed >= pollInterval then
				elapsed = 0
				local v = getValue()
				if v ~= numSpring.Target then
					onNewValue(v)
				end
			end
		end)
		j:Add(pollConn, "Disconnect")
	end

	j:LinkToInstance(label)

	-- Initial text render (no animation — just set immediately).
	label.Text = formatter(math.floor(initial + 0.5))

	local handle: NumberHandle = {
		Refresh = function()
			local v = getValue()
			onNewValue(v)
		end,
		Unbind = function()
			j:Destroy()
		end,
		GetDisplayed = function()
			return math.floor(displayed + 0.5)
		end,
	}

	-- Expose onNewValue so BindPlayerData / BindReplica can fire it.
	-- We stash it in the janitor's closure via a module-local alias below.
	-- (Returned as a second value, not part of the public Handle type.)
	return handle, onNewValue
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	Bind to an explicit getter function.
	opts.poll (seconds) activates a polling loop; otherwise caller must
	call handle:Refresh() when the value changes.
]]
function NumberLabel.BindExplicit(
	label:    TextLabel,
	getValue: () -> number,
	opts:     NumberOpts?
): NumberHandle
	if not label then
		warn("[UIAnimator/NumberLabel] BindExplicit: label is nil — aborting")
		return {
			Refresh      = function() end,
			Unbind       = function() end,
			GetDisplayed = function() return 0 end,
		}
	end
	local handle = createHandle(label, getValue, opts)
	return handle
end

--[[
	Bind to a PlayerData path. Subscribes via PlayerData.OnSet so updates
	are reactive without polling.
	dataPath example: {"cash"}
]]
function NumberLabel.BindPlayerData(
	label:    TextLabel,
	dataPath: {string},
	opts:     NumberOpts?
): NumberHandle
	if not label then
		warn("[UIAnimator/NumberLabel] BindPlayerData: label is nil — aborting")
		return {
			Refresh      = function() end,
			Unbind       = function() end,
			GetDisplayed = function() return 0 end,
		}
	end

	local PlayerData = require(game.ReplicatedStorage.Utility.PlayerData)

	-- Build getter from PlayerData.GetData() walking the path.
	local function getValue(): number
		local data = PlayerData.GetData()
		if not data then return 0 end
		local node: any = data
		for _, key in dataPath do
			if type(node) ~= "table" then return 0 end
			node = node[key]
		end
		return (type(node) == "number") and node or 0
	end

	local handle: NumberHandle, onNewValue = createHandle(label, getValue, opts)

	-- Subscribe to reactive updates.
	local conn = PlayerData.OnSet(dataPath, function(newVal)
		onNewValue((type(newVal) == "number") and newVal or 0)
	end)

	-- Wrap janitor around the PlayerData connection.
	-- Patch Unbind to also disconnect the PlayerData listener.
	local originalUnbind = handle.Unbind
	handle.Unbind = function()
		if conn and conn.Disconnect then
			pcall(function() conn:Disconnect() end)
		end
		originalUnbind()
	end

	-- Kick an initial render when PlayerData is ready.
	PlayerData.OnReady(function()
		onNewValue(getValue())
	end)

	return handle
end

--[[
	Bind to a Mad Studio Replica path. Subscribes via replica:OnSet so
	updates are reactive. Also cleans up automatically via replica.Maid
	(api-reference.md § 2.3 — auto-clean on replica destroy).
	dataPath example: {"stats", "xp"}
]]
function NumberLabel.BindReplica(
	label:    TextLabel,
	replica:  any,
	dataPath: {string},
	opts:     NumberOpts?
): NumberHandle
	if not label then
		warn("[UIAnimator/NumberLabel] BindReplica: label is nil — aborting")
		return {
			Refresh      = function() end,
			Unbind       = function() end,
			GetDisplayed = function() return 0 end,
		}
	end
	if not replica then
		warn("[UIAnimator/NumberLabel] BindReplica: replica is nil — aborting")
		return {
			Refresh      = function() end,
			Unbind       = function() end,
			GetDisplayed = function() return 0 end,
		}
	end

	-- Build getter walking the replica.Data table.
	local function getValue(): number
		local node: any = replica.Data
		if not node then return 0 end
		for _, key in dataPath do
			if type(node) ~= "table" then return 0 end
			node = node[key]
		end
		return (type(node) == "number") and node or 0
	end

	local handle: NumberHandle, onNewValue = createHandle(label, getValue, opts)

	-- Subscribe to replica OnSet (api-reference.md § 2.3).
	local conn = replica:OnSet(dataPath, function()
		onNewValue(getValue())
	end)

	-- Auto-clean when replica is destroyed (replica.Maid per api-reference.md § 2.3).
	replica.Maid:Add(function()
		handle.Unbind()
	end)

	-- Patch Unbind to also disconnect the replica listener.
	local originalUnbind = handle.Unbind
	handle.Unbind = function()
		if conn and conn.Disconnect then
			pcall(function() conn:Disconnect() end)
		end
		originalUnbind()
	end

	return handle
end

return NumberLabel
