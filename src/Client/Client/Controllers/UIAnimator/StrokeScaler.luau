--!strict
--[[
	StrokeScaler
	------------
	Keeps every UIStroke in PlayerGui at a consistent visual weight across
	screen sizes. At 1080p base, strokes render at their authored thickness.
	Above / below 1080p the thickness scales proportionally so a 2px stroke
	at 1080p never looks like a hairline at 4K or a thick slab at 720p.

	Algorithm:
	    Thickness = BaseThickness * (ViewportSize.Y / 1080)

	BaseThickness is stored as a UIStroke attribute ("BaseThickness") so it
	survives repeated recompute calls without drift. It is written ONCE on
	first bind, from the stroke's current Thickness value.

	Lifecycle:
	    • Start() walks existing PlayerGui descendants.
	    • DescendantAdded catches new strokes added at runtime.
	    • Camera.ViewportSize change triggers a full recompute.
	    • All connections are tracked on a single module-scope Janitor.

	Per api-reference.md § 3.1 Janitor — explicit "Disconnect" where needed.
	Per CLAUDE.md rule_8 — defensive logging on every failable lookup.
]]

local Players    = game:GetService("Players")
local workspace  = game:GetService("Workspace")

local Janitor = require(game.ReplicatedStorage.Packages.Janitor)

local StrokeScaler = {}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local _janitor = Janitor.new()

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Ensure the stroke has a BaseThickness attribute.
-- Written from current Thickness on first call; never overwritten thereafter.
local function ensureBase(stroke: UIStroke)
	if stroke:GetAttribute("BaseThickness") == nil then
		stroke:SetAttribute("BaseThickness", stroke.Thickness)
	end
end

-- Recompute a single stroke's Thickness from its BaseThickness and the
-- current viewport height.
local function rescaleStroke(stroke: UIStroke, viewportY: number)
	local base = stroke:GetAttribute("BaseThickness")
	if typeof(base) ~= "number" then
		warn("[UIAnimator/StrokeScaler] BaseThickness attribute is not a number on", stroke:GetFullName(), "— skipping")
		return
	end
	stroke.Thickness = base * (viewportY / 1080)
end

-- Walk every UIStroke currently in the PlayerGui and rescale.
local function rescaleAll(viewportY: number)
	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/StrokeScaler] rescaleAll: LocalPlayer not found — skipping")
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/StrokeScaler] rescaleAll: PlayerGui not found — skipping")
		return
	end

	for _, desc in playerGui:GetDescendants() do
		if desc:IsA("UIStroke") then
			local stroke = desc :: UIStroke
			ensureBase(stroke)
			rescaleStroke(stroke, viewportY)
		end
	end
end

-- Bind a single newly-found UIStroke (called from DescendantAdded).
local function bindNewStroke(stroke: UIStroke)
	local camera = workspace.CurrentCamera
	if not camera then
		warn("[UIAnimator/StrokeScaler] bindNewStroke: CurrentCamera is nil — stroke not scaled yet:", stroke:GetFullName())
		return
	end
	ensureBase(stroke)
	rescaleStroke(stroke, camera.ViewportSize.Y)
end

-- ---------------------------------------------------------------------------
-- Camera watcher
-- ---------------------------------------------------------------------------

-- Arm the ViewportSize listener once a camera is available.
-- Re-entrant safe: explicitly :Remove indexed connections before :Add so a
-- camera-thrash sequence (CurrentCamera nil → set → nil → set) cannot leak
-- stale connections (api-reference.md § 3.1 Janitor).
local function armCameraListener()
	-- Idempotent reset of any prior cycle's connections.
	_janitor:Remove("workspaceCameraChangedConn")
	_janitor:Remove("viewportConn")

	local camera = workspace.CurrentCamera
	if not camera then
		warn("[UIAnimator/StrokeScaler] armCameraListener: CurrentCamera is nil — deferring until workspace property changes")

		-- Defer: wait for CurrentCamera to be set.
		_janitor:Add(
			workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				local cam = workspace.CurrentCamera
				if cam then
					armCameraListener()
				end
			end),
			"Disconnect",
			"workspaceCameraChangedConn"
		)
		return
	end

	-- Listen to ViewportSize changes and rescale everything.
	_janitor:Add(
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			local cam = workspace.CurrentCamera
			if cam then
				rescaleAll(cam.ViewportSize.Y)
			end
		end),
		"Disconnect",
		"viewportConn"
	)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function StrokeScaler.Start()
	local player = Players.LocalPlayer
	if not player then
		warn("[UIAnimator/StrokeScaler] Start: LocalPlayer not found — StrokeScaler inactive")
		return
	end

	-- PlayerGui is reliably present for LocalScripts by the time KnitStart runs.
	-- Avoid WaitForChild here — it would yield the Knit dispatch thread
	-- (architecture.md § Critical Bans / Limitations).
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		warn("[UIAnimator/StrokeScaler] PlayerGui not present at KnitStart — stroke scaling disabled for this session")
		return
	end

	-- Bind existing strokes.
	local camera = workspace.CurrentCamera
	local initY = camera and camera.ViewportSize.Y or 1080
	for _, desc in playerGui:GetDescendants() do
		if desc:IsA("UIStroke") then
			local stroke = desc :: UIStroke
			ensureBase(stroke)
			rescaleStroke(stroke, initY)
		end
	end

	-- Watch for new strokes added after boot.
	_janitor:Add(
		playerGui.DescendantAdded:Connect(function(desc)
			if desc:IsA("UIStroke") then
				bindNewStroke(desc :: UIStroke)
			end
		end),
		"Disconnect",
		"descendantConn"
	)

	-- Arm the camera viewport listener.
	armCameraListener()
end

return StrokeScaler
