--[==[
	ExplodeBounce
	-------------
	Real ballistic physics -- initial random outward velocity + gravity + raycast-based
	floor bounces with damping + horizontal friction + optional Y-axis tumble.
	Multiple bounces until settled or maxLifetime reached.

	opts = {
	    launchSpeedMin: number? -- horizontal kick (studs/sec); default 18
	    launchSpeedMax: number? -- default 28
	    upSpeedMin:     number? -- vertical kick (studs/sec); default 25
	    upSpeedMax:     number? -- default 38
	    bounceDamp:     number? -- vertical velocity multiplier per bounce (0=dead, 1=elastic); default 0.45
	    horizFriction:  number? -- horizontal velocity multiplier per bounce; default 0.7
	    settleVelVert:  number? -- |vel.Y| threshold for settling; default 3.5
	    settleVelHoriz: number? -- XZ speed threshold for settling; default 1.0
	    maxLifetime:    number? -- hard physics cap in seconds; default 8
	    spin:           boolean? -- random angular tumble; default true
	}

	Per api-reference.md § 3.1 Janitor -- explicit "Disconnect" on connections.
	Per api-reference.md § 3.2 Signal  -- lowercase Signal.new().
]==]

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local SPRING_MAX_DT = 1 / 30   -- clamp integration step to avoid oversized jumps
local RAY_LEN       = 200      -- max studs to search for floor below

-- ---------------------------------------------------------------------------
-- Helpers
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
			warn("[WorldAnimator/ExplodeBounce] " .. target:GetFullName() .. " has no PrimaryPart — using " .. first.Name)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/ExplodeBounce] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o              = opts or {}
	local launchSpeedMin = o.launchSpeedMin or 18
	local launchSpeedMax = o.launchSpeedMax or 28
	local upSpeedMin     = o.upSpeedMin     or 25
	local upSpeedMax     = o.upSpeedMax     or 38
	local bounceDamp     = o.bounceDamp     or 0.45
	local horizFriction  = o.horizFriction  or 0.70
	local settleVelVert  = o.settleVelVert  or 3.5
	local settleVelHoriz = o.settleVelHoriz or 1.0
	local maxLifetime    = o.maxLifetime    or 8.0
	local doSpin         = (o.spin ~= false) -- default true

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

	local isModel    = anchorType == "PrimaryPart"
	local halfHeight = anchor:IsA("BasePart") and (anchor.Size.Y * 0.5) or 0.5

	-- Initial impulse: random horizontal direction + random sideways and vertical magnitudes.
	local angle      = math.random() * math.pi * 2
	local launchMag  = launchSpeedMin + math.random() * (launchSpeedMax - launchSpeedMin)
	local upMag      = upSpeedMin     + math.random() * (upSpeedMax     - upSpeedMin)
	local vel        = Vector3.new(
		math.cos(angle) * launchMag,
		upMag,
		math.sin(angle) * launchMag
	)

	-- Optional spin: tumble around all axes while flying.
	local rotVel = Vector3.zero
	if doSpin then
		rotVel = Vector3.new(
			(math.random() - 0.5) * 6,
			(math.random() - 0.5) * 8,
			(math.random() - 0.5) * 6
		)
	end

	local pos     = anchor.Position
	local elapsed = 0
	local accRot  = CFrame.new()

	-- Floor raycast params -- constructed once; excludes the target so self-intersection is ignored.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { target }
	rayParams.IgnoreWater = true

	local function floorYAt(p: Vector3): number?
		local result = workspace:Raycast(
			Vector3.new(p.X, p.Y + halfHeight + 5, p.Z),
			Vector3.new(0, -RAY_LEN, 0),
			rayParams
		)
		return result and result.Position.Y or nil
	end

	-- Apply the part's transform: accumulate rotation each frame if doSpin, else keep identity.
	local function applyTransform(dt: number)
		if doSpin then
			accRot = accRot * CFrame.Angles(rotVel.X * dt, rotVel.Y * dt, rotVel.Z * dt)
		end
		local cf = CFrame.new(pos) * accRot
		if isModel then
			local m = target :: Model
			m:PivotTo(cf)
		else
			anchor.CFrame = cf
		end
	end

	local conn = RunService.Heartbeat:Connect(function(dt)
		if not running then
			return
		end

		local clampedDt = math.min(dt, SPRING_MAX_DT)
		elapsed += clampedDt

		-- Hard timeout safety net.
		if elapsed > maxLifetime then
			running = false
			completed:Fire()
			return
		end

		-- Integrate gravity into vertical velocity, then advance position.
		vel = Vector3.new(vel.X, vel.Y - workspace.Gravity * clampedDt, vel.Z)
		pos = pos + vel * clampedDt

		-- Floor collision check.
		local floorY = floorYAt(pos)
		if floorY and (pos.Y - halfHeight) <= floorY then
			-- Snap onto the surface.
			pos = Vector3.new(pos.X, floorY + halfHeight, pos.Z)

			-- Reverse + dampen vertical; apply horizontal friction.
			vel = Vector3.new(vel.X * horizFriction, -vel.Y * bounceDamp, vel.Z * horizFriction)

			-- Dampen angular velocity on each bounce -- each impact kills spin.
			if doSpin then
				rotVel = rotVel * 0.5
			end

			-- Settle: low vertical bounce AND low horizontal speed -> done.
			local horizSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
			if math.abs(vel.Y) < settleVelVert and horizSpeed < settleVelHoriz then
				vel    = Vector3.zero
				rotVel = Vector3.zero
				applyTransform(0)
				running = false
				completed:Fire()
				return
			end
		end

		applyTransform(clampedDt)
	end)
	janitor:Add(conn, "Disconnect")

	local function cancel()
		if not running then
			return
		end
		running = false
		local ok = pcall(conn.Disconnect, conn)
		if not ok then
			warn("[WorldAnimator/ExplodeBounce] Disconnect error on cancel")
		end
		completed:Fire()
	end

	return {
		Cancel    = cancel,
		Completed = completed,
		IsRunning = function() return running end,
	}
end
