--[[
	MagnetToPlayer
	--------------
	Distance-based magnetic attraction. Outside `range` (default 20 studs) the
	part idles. Inside, attraction force quadratically ramps from `minForce` at
	the boundary to `maxForce` at distance 0; an `innerBoostMult` (default 8x)
	kicks in below `innerBoostRange` (default 5 studs) to make the final
	approach unstoppable. Part is absorbed on touch with the player's
	HumanoidRootPart OR when within 1.5 studs.

	Anchors the target during magnetism. We drive CFrame directly so physics
	gravity must be suppressed — anchoring is the cleanest path (no BodyMovers
	needed). Original Anchored state is captured and restored on Cancel / absorb
	/ lifetime expiry. For Model targets, every BasePart descendant is anchored
	and individually restored so stray loose parts cannot fall.

	opts = {
	    player:           Player?  -- default Players.LocalPlayer
	    range:            number?  -- max activation distance in studs (default 20)
	    minForce:         number?  -- attraction force at the boundary (default 80)
	    maxForce:         number?  -- attraction force at distance 0 (default 1500)
	    innerBoostRange:  number?  -- below this studs, force x innerBoostMult (default 5)
	    innerBoostMult:   number?  -- multiplier inside inner radius (default 8)
	    touchKill:        boolean? -- destroy on HRP touch (default true)
	    dragOutsideRange: number?  -- velocity damping per frame outside range (default 0.92)
	    maxLifetime:      number?  -- hard timeout in seconds (default 12)
	}

	Returns { Cancel, Completed, IsRunning, OnAbsorbed }.
	OnAbsorbed fires when the part is absorbed by the player.

	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" on connections.
	Per api-reference.md § 3.2 Signal — lowercase Signal.new().
]]

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local ABSORB_DISTANCE = 1.5

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
			warn(
				"[WorldAnimator/MagnetToPlayer] "
					.. target:GetFullName()
					.. " has no PrimaryPart — using "
					.. first.Name
			)
			return first :: BasePart, "Model-noPrimary"
		end
	end
	warn("[WorldAnimator/MagnetToPlayer] no anchor for " .. target:GetFullName())
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Preset
-- ---------------------------------------------------------------------------

return function(target: Instance, opts: any?, janitor: any)
	local o                = opts or {}
	local player           = o.player           or Players.LocalPlayer
	local range            = o.range            or 20
	local minForce         = o.minForce         or 80
	local maxForce         = o.maxForce         or 1500
	local innerBoostRange  = o.innerBoostRange  or 5
	local innerBoostMult   = o.innerBoostMult   or 8
	local touchKill        = (o.touchKill ~= false)
	local dragOutsideRange = o.dragOutsideRange or 0.92
	local maxLifetime      = o.maxLifetime      or 12

	local completed  = Signal.new()
	local onAbsorbed = Signal.new()
	local running    = true

	local anchor, anchorType = resolveAnchor(target)
	if not anchor then
		warn("[WorldAnimator/MagnetToPlayer] resolveAnchor returned nil — aborting magnet")
		completed:Fire()
		return {
			Cancel     = function() end,
			Completed  = completed,
			OnAbsorbed = onAbsorbed,
			IsRunning  = function() return false end,
		}
	end

	if not player then
		warn("[WorldAnimator/MagnetToPlayer] opts.player is nil — magnet aborted")
		completed:Fire()
		return {
			Cancel     = function() end,
			Completed  = completed,
			OnAbsorbed = onAbsorbed,
			IsRunning  = function() return false end,
		}
	end

	local isModel        = anchorType == "PrimaryPart"
	local origCanCollide = anchor.CanCollide
	anchor.CanCollide    = false

	-- Anchor the target so Roblox physics cannot apply gravity while we drive
	-- CFrame manually. For Model targets, anchor every BasePart descendant so
	-- stray loose parts in the model hierarchy also cannot fall.
	-- Per architecture.md Critical Bans — capture state into locals before any
	-- async boundary so teardown closures read the captured snapshot.
	local origAnchored: boolean = anchor.Anchored
	local modelAnchorRestore: { [BasePart]: boolean }? = nil

	if isModel then
		modelAnchorRestore = {}
		for _, desc in (target :: Model):GetDescendants() do
			if desc:IsA("BasePart") then
				local part = desc :: BasePart
				modelAnchorRestore[part] = part.Anchored
				part.Anchored = true
			end
		end
		-- PrimaryPart itself is also a descendant and captured above.
	else
		anchor.Anchored = true
	end

	local velocity = Vector3.zero
	local elapsed  = 0
	local absorbed = false

	-- ---------------------------------------------------------------------------
	-- Helpers
	-- ---------------------------------------------------------------------------

	-- Restores CanCollide and Anchored to their captured pre-magnet values.
	-- Called from every teardown path (cancel / absorb / maxLifetime).
	local function restorePhysicsState()
		anchor.CanCollide = origCanCollide
		if modelAnchorRestore then
			for part, wasAnchored in modelAnchorRestore do
				if part.Parent then
					part.Anchored = wasAnchored
				end
			end
		else
			anchor.Anchored = origAnchored
		end
	end

	local function applyPos(pos: Vector3)
		if isModel then
			local m = target :: Model
			m:PivotTo(CFrame.new(pos) * m:GetPivot().Rotation)
		else
			anchor.CFrame = CFrame.new(pos) * anchor.CFrame.Rotation
		end
	end

	local function doAbsorb()
		if absorbed then
			return
		end
		absorbed = true
		running  = false
		onAbsorbed:Fire()
		completed:Fire()
		restorePhysicsState()
		if touchKill and target.Parent then
			local capturedTarget = target
			task.defer(function()
				local ok, err = pcall(function()
					capturedTarget:Destroy()
				end)
				if not ok then
					warn("[WorldAnimator/MagnetToPlayer] destroy failed — " .. tostring(err))
				end
			end)
		end
	end

	-- ---------------------------------------------------------------------------
	-- Touch detector (fires absorb instantly on HRP contact)
	-- ---------------------------------------------------------------------------

	if touchKill then
		local touchConn = anchor.Touched:Connect(function(hit: BasePart)
			if not running then
				return
			end
			local char = player and player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				return
			end
			if hit == hrp or hit:IsDescendantOf(char) then
				doAbsorb()
			end
		end)
		janitor:Add(touchConn, "Disconnect")
	end

	-- ---------------------------------------------------------------------------
	-- Heartbeat — velocity integration
	-- ---------------------------------------------------------------------------

	local hbConn = RunService.Heartbeat:Connect(function(dt: number)
		if not running then
			return
		end

		elapsed += dt
		if elapsed > maxLifetime then
			running = false
			restorePhysicsState()
			completed:Fire()
			return
		end

		-- Resolve HRP this frame; bail (decay only) if character not ready.
		local char = player and player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			velocity = velocity * dragOutsideRange
			applyPos(anchor.Position + velocity * dt)
			return
		end

		local currentPos = anchor.Position
		local toPlayer   = hrp.Position - currentPos
		local distance   = toPlayer.Magnitude

		if distance > range then
			-- Outside activation range — drag only, no attraction.
			velocity = velocity * dragOutsideRange
		else
			-- Quadratic proximity ramp: 0 at boundary, 1 at distance 0.
			local proximity = math.clamp(1 - (distance / range), 0, 1)
			local forceMag  = minForce + (maxForce - minForce) * (proximity * proximity)

			-- Inner unstoppable boost below innerBoostRange.
			if distance < innerBoostRange then
				forceMag = forceMag * innerBoostMult
			end

			local direction = if distance > 0.01 then toPlayer / distance else Vector3.zero
			velocity = velocity + direction * forceMag * dt
		end

		-- Integrate position.
		local newPos = currentPos + velocity * dt
		applyPos(newPos)

		-- Fallback absorb: handles fast pass-through that Touched may miss.
		if distance < ABSORB_DISTANCE then
			doAbsorb()
		end
	end)
	janitor:Add(hbConn, "Disconnect")

	-- ---------------------------------------------------------------------------
	-- Cancel
	-- ---------------------------------------------------------------------------

	local function cancel()
		if not running then
			return
		end
		running = false
		local ok = pcall(hbConn.Disconnect, hbConn)
		if not ok then
			warn("[WorldAnimator/MagnetToPlayer] Disconnect error on cancel")
		end
		restorePhysicsState()
		completed:Fire()
	end

	return {
		Cancel     = cancel,
		Completed  = completed,
		OnAbsorbed = onAbsorbed,
		IsRunning  = function() return running end,
	}
end
