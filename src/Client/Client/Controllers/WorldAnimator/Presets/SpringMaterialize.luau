--[[
	SpringMaterialize
	-----------------
	Inverse of SpringVanish: starts the target at near-zero size and springs
	it to its original size. Used for "spawn", "appear", or "reward drop" moments.

	Supports both BasePart (drives .Size) and Model (drives Model:ScaleTo() via
	the universally-supported method-based uniform-scale API). Falls back to
	BasePart anchor scaling for Models without ScaleTo support.

	opts = {
	    smoothTime: number? -- seconds to grow to full size (default 0.12)
	}

	Snaps to near-zero immediately on Apply, then springs to factor 1.0.
	Completes when factor >= 0.99.

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
local NEAR_ZERO_SCALE = 0.01   -- starting scale (> 0; Model.Scale must not be 0)
local DONE_THRESHOLD  = 0.99   -- factor >= this = complete

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
			warn("[WorldAnimator/SpringMaterialize] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/SpringMaterialize] no anchor for " .. target:GetFullName())
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
		-- Capture current scale as baseline (caller may have pre-set it to 0.01).
		baselineModelScale = (target :: Model):GetScale()
		-- If already at near-zero, baseline is still used as the reference for
		-- applyScale(1.0) = restore. We normalise: if it's already ≤ near-zero,
		-- treat baseline as 1.0 (full size) so the target springs to Scale = 1.
		if baselineModelScale <= NEAR_ZERO_SCALE then
			baselineModelScale = 1.0
		end
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

	-- Immediately snap to near-zero so the spring starts from tiny.
	applyScale(NEAR_ZERO_SCALE)

	-- Scalar spring from near-zero toward 1.0.
	local spr    = Spring.new(NEAR_ZERO_SCALE, smoothTime)
	spr.Target   = 1.0

	local conn = RunService.Heartbeat:Connect(function(dt)
		local f = spr:Update(math.min(dt, SPRING_MAX_DT))
		applyScale(f)

		if running and f >= DONE_THRESHOLD then
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
			warn("[WorldAnimator/SpringMaterialize] Disconnect error on cancel")
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
