--[[
	HoverBob
	--------
	Oscillates a target up and down along an axis using a Spring for organic
	motion feel. Uses the spring target to drive a sine wave so the motion
	settles gracefully when interrupted.

	opts = {
	    amplitude: number?  -- studs above/below base (default 0.5)
	    period:    number?  -- seconds per full cycle (default 6.0)
	    axis:      Vector3? -- direction of oscillation (default Vector3.yAxis)
	}

	Per architecture.md § Visual / Animation Policy — client-only cosmetic.
	Per api-reference.md § 5.1 Spring — smoothTime 0.4 for lazy/atmospheric hover.
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
local TWO_PI        = 2 * math.pi

-- ---------------------------------------------------------------------------
-- Resolver (shared logic; also found in init.luau)
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
			warn("[WorldAnimator/HoverBob] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/HoverBob] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o         = opts or {}
	local amplitude = o.amplitude or 1.5
	-- NOTE: `period` is the FULL sin cycle. The visual "up-then-down" the user sees
	-- is HALF a period (peak → trough). period=6 → 3s perceived up-and-down.
	local period    = o.period or 6.0
	local axis      = o.axis or Vector3.yAxis

	local completed = Signal.new()
	local running   = true

	local anchor, anchorType = resolveAnchor(target)
	if not anchor then
		completed:Fire()
		return {
			Cancel    = function() end,
			Completed = completed,
			IsRunning = function() return false end,
		}
	end

	local isModel      = anchorType == "PrimaryPart"
	local basePos      = anchor.Position
	local t            = 0
	local spr          = Spring.new(basePos, 0.4)
	spr.Target         = basePos

	local conn = RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		local offset = axis * amplitude * math.sin(t * TWO_PI / period)
		spr.Target = basePos + offset
		local newPos = spr:Update(math.min(dt, SPRING_MAX_DT))
		if isModel then
			local m = target :: Model
			m:PivotTo(CFrame.new(newPos) * m:GetPivot().Rotation)
		else
			anchor.CFrame = CFrame.new(newPos) * anchor.CFrame.Rotation
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
			warn("[WorldAnimator/HoverBob] Disconnect error on cancel")
		end
		-- restore base position
		if isModel then
			local m = target :: Model
			m:PivotTo(CFrame.new(basePos) * m:GetPivot().Rotation)
		else
			anchor.CFrame = CFrame.new(basePos) * anchor.CFrame.Rotation
		end
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
