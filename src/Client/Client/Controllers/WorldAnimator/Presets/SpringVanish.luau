--[[
	SpringVanish
	------------
	Shrinks a target to near-zero size via a critically-damped spring. Useful
	for "picked up", "consumed", or "despawn" moments.

	Supports both BasePart (drives .Size) and Model (drives Model:ScaleTo() via
	the universally-supported method-based uniform-scale API). Scale floor is
	0.01 — zero is invalid. Falls back to BasePart anchor scaling for Models
	without ScaleTo support.

	opts = {
	    smoothTime: number? -- seconds to approach near-zero (default 0.12)
	}

	Leaves the target at near-zero; caller is responsible for destroying it.

	Per api-reference.md § 5.1 Spring — scalar number spring; smoothTime drives speed.
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

local SPRING_MAX_DT   = 1 / 30
local NEAR_ZERO_SCALE = 0.01   -- Model.Scale floor (> 0)
local DONE_THRESHOLD  = 0.05   -- factor below this = complete

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
			warn("[WorldAnimator/SpringVanish] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/SpringVanish] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o          = opts or {}
	local smoothTime = o.smoothTime or 0.12

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
		anchor       = resolved
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

	-- Scalar spring from 1.0 toward near-zero.
	local spr    = Spring.new(1.0, smoothTime)
	spr.Target   = NEAR_ZERO_SCALE

	local conn = RunService.Heartbeat:Connect(function(dt)
		local f = spr:Update(math.min(dt, SPRING_MAX_DT))
		applyScale(f)

		if running and f < DONE_THRESHOLD then
			running = false
			applyScale(NEAR_ZERO_SCALE)
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
			warn("[WorldAnimator/SpringVanish] Disconnect error on cancel")
		end
		-- Restore to baseline on cancel (caller decided not to vanish).
		applyScale(1.0)
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
