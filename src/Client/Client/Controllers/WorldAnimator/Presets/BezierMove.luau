--[[
	BezierMove
	----------
	Moves the target along a quadratic Bezier curve from `from` through
	`control` to `to` over `seconds`. Supports linear, quadratic, and cubic
	ease functions.

	opts = {
	    from:    Vector3              -- start position
	    control: Vector3              -- curve control point
	    to:      Vector3              -- end position
	    seconds: number?              -- duration (default 1.0)
	    ease:    ("linear"|"quad"|"cubic")? -- easing (default "quad")
	}

	Completes at t=1 (end of arc). Fires Completed immediately after placing
	the target at the final position.

	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" on connections.
	Per api-reference.md § 3.2 Signal — lowercase Signal.new().
]]

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

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
			warn("[WorldAnimator/BezierMove] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/BezierMove] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function applyEase(t: number, ease: string): number
	if ease == "cubic" then
		return t * t * t
	elseif ease == "quad" then
		return t * t
	else
		return t -- linear
	end
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local s = 1 - t
	return (s * s) * p0 + (2 * s * t) * p1 + (t * t) * p2
end

local function setCF(anchor: BasePart, isModel: boolean, target: Instance, pos: Vector3)
	if isModel then
		local m = target :: Model
		m:PivotTo(CFrame.new(pos) * m:GetPivot().Rotation)
	else
		anchor.CFrame = CFrame.new(pos) * anchor.CFrame.Rotation
	end
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o       = opts or {}
	local fromPos = o.from :: Vector3
	local control = o.control :: Vector3
	local toPos   = o.to :: Vector3
	local seconds = o.seconds or 0.5
	local ease    = o.ease or "quad"

	local completed = Signal.new()
	local running   = true

	if not fromPos or not control or not toPos then
		warn("[WorldAnimator/BezierMove] opts.from / opts.control / opts.to are required — aborting")
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
	local elapsed = 0

	local conn = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		local raw = math.clamp(elapsed / seconds, 0, 1)
		local t   = applyEase(raw, ease)
		local pos = bezier(fromPos, control, toPos, t)
		setCF(anchor, isModel, target, pos)

		if running and raw >= 1 then
			running = false
			setCF(anchor, isModel, target, toPos)
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
			warn("[WorldAnimator/BezierMove] Disconnect error on cancel")
		end
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
