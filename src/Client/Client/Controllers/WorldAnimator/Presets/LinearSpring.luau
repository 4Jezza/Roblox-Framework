--[[
	LinearSpring
	------------
	Moves the target to a given position via a plain critically-damped spring.
	The simplest "move to here" preset — use when no arc or bounce is needed.

	opts = {
	    to:         Vector3 -- destination position (required)
	    smoothTime: number? -- approach speed (default 0.4)
	}

	Completes when the anchor is within 0.05 studs of the destination.

	Per api-reference.md § 5.1 Spring — smoothTime 0.4 for smooth deliberate motion.
	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" on connections.
	Per api-reference.md § 3.2 Signal — lowercase Signal.new().
]]

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spring = require(ReplicatedStorage.Packages.Spring)
local Signal = require(ReplicatedStorage.Packages.Signal)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SPRING_MAX_DT = 1 / 30
local DONE_EPS      = 0.05

-- ---------------------------------------------------------------------------
-- Resolver
-- ---------------------------------------------------------------------------

local function resolveAnchor(target: Instance): (BasePart?, string?)
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
			warn("[WorldAnimator/LinearSpring] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/LinearSpring] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o          = opts or {}
	local toPos      = o.to :: Vector3
	local smoothTime = o.smoothTime or 0.4

	local completed = Signal.new()
	local running   = true

	if not toPos then
		warn("[WorldAnimator/LinearSpring] opts.to is required — aborting")
		completed:Fire()
		return {
			Cancel    = function() end,
			Completed = completed,
			IsRunning = function() return false end,
		}
	end

	local anchor, anchorType = resolveAnchor(target)
	if not anchor then
		completed:Fire()
		return {
			Cancel    = function() end,
			Completed = completed,
			IsRunning = function() return false end,
		}
	end

	local isModel = anchorType == "PrimaryPart"
	local spr     = Spring.new(anchor.Position, smoothTime)
	spr.Target    = toPos

	local conn = RunService.Heartbeat:Connect(function(dt)
		local newPos = spr:Update(math.min(dt, SPRING_MAX_DT))
		if isModel then
			local m = target :: Model
			m:PivotTo(CFrame.new(newPos) * m:GetPivot().Rotation)
		else
			anchor.CFrame = CFrame.new(newPos) * anchor.CFrame.Rotation
		end

		if running and (newPos - toPos).Magnitude < DONE_EPS then
			running = false
			if isModel then
				local m = target :: Model
				m:PivotTo(CFrame.new(toPos) * m:GetPivot().Rotation)
			else
				anchor.CFrame = CFrame.new(toPos) * anchor.CFrame.Rotation
			end
			completed:Fire()
		end
	end)
	janitor:Add(conn, "Disconnect")

	local function cancel()
		if not running then
			return
		end
		running = false
		local ok = pcall(conn.Disconnect, conn)
		if not ok then
			warn("[WorldAnimator/LinearSpring] Disconnect error on cancel")
		end
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
