--[[
	SpringGrow
	----------
	Kicks the target's size outward via a Spring impulse, then settles back to
	the original size. Communicates weight and readiness ("I'm here!").

	Supports both BasePart (drives .Size) and Model (drives Model:ScaleTo() via
	the universally-supported method-based uniform-scale API). Falls back to
	BasePart anchor scaling for Models without ScaleTo support.

	opts = {
	    factor:         number? -- peak scale multiplier (default 1.5)
	    impulseSeconds: number? -- spread the impulse over this window (default 0.18)
	}

	Per api-reference.md § 5.1 Spring — scalar number spring; smoothTime 0.3.
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

local SPRING_MAX_DT      = 1 / 30
local SETTLE_FACTOR_EPS  = 0.005   -- |factor - 1.0| threshold
local SETTLE_VEL_EPS     = 0.05    -- |velocity| threshold

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
			warn("[WorldAnimator/SpringGrow] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/SpringGrow] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o              = opts or {}
	local factor         = o.factor or 1.5
	local impulseSeconds = o.impulseSeconds or 0.18

	local completed = Signal.new()
	local running   = true

	-- Branch: Model with ScaleTo support vs BasePart anchor.
	-- Method-based detection: ScaleTo is the universally-supported uniform-scale API.
	-- `(target :: any).ScaleTo` is a method check; works regardless of Roblox build.
	local isModelTarget = target:IsA("Model") and type((target :: any).ScaleTo) == "function"
	local baselineModelScale: number = 1
	local baselineSize: Vector3      = Vector3.one
	local anchor: BasePart?          = nil

	if isModelTarget then
		baselineModelScale = (target :: Model):GetScale()
	else
		local resolved, _ = resolveAnchor(target)
		if not resolved then
			completed:Fire()
			return {
				Cancel    = function() end,
				Completed = completed,
				IsRunning = function() return false end,
			}
		end
		anchor    = resolved
		baselineSize = anchor.Size
	end

	local function applyScale(f: number)
		if isModelTarget then
			local m = target :: Model
			m:ScaleTo(baselineModelScale * f)
		else
			local a = anchor :: BasePart
			a.Size = baselineSize * f
		end
	end

	-- Scalar spring starting at factor 1.0, impulse toward peak.
	local spr    = Spring.new(1.0, 0.3)
	spr.Target   = 1.0
	spr:Impulse((factor - 1.0) / impulseSeconds)

	local conn = RunService.Heartbeat:Connect(function(dt)
		local f   = spr:Update(math.min(dt, SPRING_MAX_DT))
		applyScale(f)

		local velMag  = math.abs(spr.Velocity)
		local diffMag = math.abs(spr.Current - spr.Target)
		if running and velMag < SETTLE_VEL_EPS and diffMag < SETTLE_FACTOR_EPS then
			running = false
			applyScale(1.0)
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
			warn("[WorldAnimator/SpringGrow] Disconnect error on cancel")
		end
		applyScale(1.0)
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
