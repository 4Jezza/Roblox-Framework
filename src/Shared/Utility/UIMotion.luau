--!strict
--[[
	UIMOTION
	--------
	Re-exports every UIAnimator method as a passthrough AND adds Spring-based
	helpers for the gaps UIAnimator doesn't cover: number tickers, position /
	size motion, and color lerps.

	Client-only (UIAnimator depends on PlayerScripts). Composable with Sequence
	— every helper returns a Handle with :Await() that Sequence steps can call.

	Import:
	    local UIMotion = require(game.ReplicatedStorage.Utility.UIMotion)

	Spring internals use sleitnick/spring (`Packages.Spring`), which wraps
	`TweenService:SmoothDamp`. `smoothTime` ≈ seconds to reach the target.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

assert(RunService:IsClient(), "[UIMotion] client-only — UIAnimator dependency requires PlayerScripts")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Spring = require(ReplicatedStorage.Packages.Spring)
local Format = require(ReplicatedStorage.Utility.Format)

local LocalPlayer = Players.LocalPlayer
local UIAnimator = require(
	LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Packages"):WaitForChild("UIAnimator")
)

local UIMotion = {}

-- ─── Passthrough every UIAnimator public function ───────────────────────────
for k, v in pairs(UIAnimator) do
	if type(v) == "function" and UIMotion[k] == nil then
		UIMotion[k] = v
	end
end

-- ─── Handle (composable with Sequence) ──────────────────────────────────────
local function newHandle()
	local h: any = {
		_cancelled = false, _complete = false, _conn = nil :: RBXScriptConnection?,
		_completeFired = false, _extraCleanup = nil :: (() -> ())?,
		Completed = Signal.new(),
	}
	function h:_finish(success: boolean)
		if self._complete then return end
		if self._conn then self._conn:Disconnect(); self._conn = nil end
		if self._extraCleanup then pcall(self._extraCleanup); self._extraCleanup = nil end
		self._complete = true
		if not self._completeFired then
			self._completeFired = true
			self.Completed:Fire(success)
		end
	end
	function h:Cancel()
		if self._complete then return end
		self._cancelled = true
		self:_finish(false)
	end
	function h:IsComplete() return self._complete end
	function h:Await() if not self._complete then self.Completed:Wait() end end
	return h
end

local DEFAULT_SMOOTH = 0.35

-- ─── TweenNumber ────────────────────────────────────────────────────────────
function UIMotion.TweenNumber(label: Instance, fromValue: number, toValue: number, opts: any?): any
	local h = newHandle()
	if not (label and (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox"))) then
		warn("[UIMotion] TweenNumber target is not a Text*; got " .. tostring(label and label.ClassName))
		h:_finish(false); return h
	end
	opts = opts or {}
	local smoothTime = opts.smoothTime or opts.duration or DEFAULT_SMOOTH
	local format = opts.format or Format.abbreviateNumber
	local spring = Spring.new(fromValue, smoothTime)
	spring.Target = toValue
	;(label :: any).Text = format(fromValue)
	h._conn = RunService.Heartbeat:Connect(function(dt)
		if h._cancelled or not label.Parent then h:_finish(false); return end
		local current = spring:Update(dt)
		;(label :: any).Text = format(current)
		if math.abs(spring.Velocity) < 0.05 and math.abs(current - toValue) < 0.5 then
			;(label :: any).Text = format(toValue)
			h:_finish(true)
		end
	end)
	if opts.janitor then opts.janitor:Add(h, "Cancel") end
	return h
end

-- ─── Internal: 4-number-spring on a UDim2 property ──────────────────────────
local function springUDim2(element: Instance, prop: string, goal: UDim2, opts: any?): any
	local h = newHandle()
	if not (element and element:IsA("GuiObject")) then
		warn("[UIMotion] Spring" .. prop .. " target is not a GuiObject; got " .. tostring(element and element.ClassName))
		h:_finish(false); return h
	end
	opts = opts or {}
	local smoothTime = opts.smoothTime or DEFAULT_SMOOTH
	local cur: UDim2 = (element :: any)[prop]
	local sxS = Spring.new(cur.X.Scale, smoothTime); sxS.Target = goal.X.Scale
	local sxO = Spring.new(cur.X.Offset, smoothTime); sxO.Target = goal.X.Offset
	local syS = Spring.new(cur.Y.Scale, smoothTime); syS.Target = goal.Y.Scale
	local syO = Spring.new(cur.Y.Offset, smoothTime); syO.Target = goal.Y.Offset
	h._conn = RunService.Heartbeat:Connect(function(dt)
		if h._cancelled or not element.Parent then h:_finish(false); return end
		local v = UDim2.new(sxS:Update(dt), sxO:Update(dt), syS:Update(dt), syO:Update(dt))
		;(element :: any)[prop] = v
		if math.abs(sxS.Velocity) < 0.001 and math.abs(syS.Velocity) < 0.001
			and math.abs(sxO.Velocity) < 0.1 and math.abs(syO.Velocity) < 0.1
			and math.abs(v.X.Scale - goal.X.Scale) < 0.0005
			and math.abs(v.Y.Scale - goal.Y.Scale) < 0.0005
			and math.abs(v.X.Offset - goal.X.Offset) < 0.5
			and math.abs(v.Y.Offset - goal.Y.Offset) < 0.5 then
			;(element :: any)[prop] = goal
			h:_finish(true)
		end
	end)
	if opts.janitor then opts.janitor:Add(h, "Cancel") end
	return h
end

function UIMotion.SpringPosition(element: Instance, goalPos: UDim2, opts: any?): any
	return springUDim2(element, "Position", goalPos, opts)
end
function UIMotion.SpringSize(element: Instance, goalSize: UDim2, opts: any?): any
	return springUDim2(element, "Size", goalSize, opts)
end

-- ─── TweenColor (TweenService — Color3 lerps fine without spring physics) ──
function UIMotion.TweenColor(element: Instance, property: string, goalColor: Color3, opts: any?): any
	local h = newHandle()
	local probeOk = pcall(function() return (element :: any)[property] end)
	if not probeOk then
		warn("[UIMotion] TweenColor: property '" .. property .. "' not accessible on " .. tostring(element and element.ClassName))
		h:_finish(false); return h
	end
	opts = opts or {}
	local info = TweenInfo.new(opts.duration or 0.3, opts.easingStyle or Enum.EasingStyle.Sine, opts.easingDirection or Enum.EasingDirection.Out)
	local tween = TweenService:Create(element, info, { [property] = goalColor })
	h._extraCleanup = function() tween:Cancel() end
	h._conn = tween.Completed:Connect(function(state)
		h:_finish(state == Enum.PlaybackState.Completed)
	end)
	tween:Play()
	if opts.janitor then opts.janitor:Add(h, "Cancel") end
	return h
end

return UIMotion
