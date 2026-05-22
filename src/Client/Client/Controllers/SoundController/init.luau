-- NOTE: Splitting resolver/pool/handle into sub-files would isolate single-caller
-- utilities and fragment the "how does play work" story that a future audio engineer
-- must read top-to-bottom. Findability wins over line count (rule_9).

--[[
	SoundController
	---------------
	Knit controller that centralises ALL client-side audio. Every other controller
	and binding should reach for this module rather than calling :Play() directly
	on a Sound instance.

	Architecture:
	  • Sound resolution  — dot-path names ("UI.Hover") resolve through SFX then Music
	                        in priority order (see resolveSound). Never crashes on miss.
	  • Cloning pool      — each :Play() clones the template Sound so concurrent plays
	                        don't interrupt one another. Clones are returned to the pool
	                        on Ended (or destroyed if the pool is full).
	  • Category volumes  — SFX / Music volumes scale every played clone.
	  • PlayLayered       — delegates to Layered.luau (plays N sounds simultaneously).
	  • CountTo           — delegates to Counting.luau (pitched tick sequence).

	Public API:
	  SoundController:Play(name, opts?)          → SoundHandle
	  SoundController:PlayLayered(names, opts?)  → {SoundHandle}
	  SoundController:StopAll(category?)
	  SoundController:GetCategoryVolume(cat)     → number
	  SoundController:SetCategoryVolume(cat, v)
	  SoundController:CountTo(opts)              → CountHandle

	Per architecture.md § Sound runtime path — sounds live under SoundService.SFX/Music.
	Per api-reference.md § 3.1 Janitor — :Add(conn, "Disconnect") for all connections.
	Per conventions.md § Module file structure — canonical header + section dividers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local Knit    = require(ReplicatedStorage.Packages.Knit)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

local Layered  = require(script.Layered)
local Counting = require(script.Counting)

local SoundController = Knit.CreateController {
	Name = "SoundController",
}

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

export type PlayOpts = {
	volume:  number?,
	pitch:   number?,
	looped:  boolean?,
	parent:  Instance?,
}

export type SoundHandle = {
	Stop:      () -> (),
	SetPitch:  (p: number) -> (),
	SetVolume: (v: number) -> (),
	Instance:  Sound?,
	OnEnded:   (() -> ())?,
}

export type CountOpts = {
	from:         number,
	to:           number,
	totalSeconds: number,
	soundName:    string?,
	basePitch:    number?,
	easing:       ("Slow" | "Fast")?,
}

export type CountHandle = {
	Cancel:      () -> (),
	IsPlaying:   () -> boolean,
	SetProgress: (t: number) -> (),
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

-- Pool cap per template path — reuse idle clones before creating new ones.
local POOL_CAP = 8

-- Category volume multipliers. Applied at play time as:
--   clone.Volume = source.Volume * _volumes[category]
local _volumes: { [string]: number } = {
	SFX   = 1,
	Music = 1,
}

-- Active handles keyed by clone instance — used by StopAll.
-- _activeHandles[clone] = { handle, category }
local _activeHandles: { [Sound]: { handle: SoundHandle, category: string } } = {}

-- Per-category idle pool: _pool[category][templatePath] = { Sound }
local _pool: { [string]: { [string]: { Sound } } } = {
	SFX   = {},
	Music = {},
}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- resolveSound: walks SoundService looking for `name` (dot-path supported).
-- Priority: SFX sub-path → SFX root → Music.
-- Returns (Sound, category) or (nil, nil).
local function resolveSound(name: string): (Sound?, string?)
	-- Split on "." to get sub-folder path segments.
	local segments: { string } = {}
	for seg in name:gmatch("[^%.]+") do
		table.insert(segments, seg)
	end

	-- Walk a category folder using the segments.
	local function walkCategory(folder: Folder?, segs: { string }): Sound?
		if not folder then return nil end
		local node: Instance = folder
		for i, seg in ipairs(segs) do
			local child = node:FindFirstChild(seg)
			if not child then return nil end
			node = child
			if i == #segs then
				if node:IsA("Sound") then
					return node :: Sound
				end
				return nil
			end
		end
		return nil
	end

	local sfxFolder   = SoundService:FindFirstChild("SFX")
	local musicFolder = SoundService:FindFirstChild("Music")

	-- 1. SFX sub-path (full dot-path under SFX).
	local found = walkCategory(sfxFolder, segments)
	if found then return found, "SFX" end

	-- 2. SFX root fallback (last segment only).
	if #segments > 1 then
		local lastName = segments[#segments]
		found = sfxFolder and sfxFolder:FindFirstChild(lastName)
		if found and found:IsA("Sound") then return found :: Sound, "SFX" end
	end

	-- 3. Music fallback.
	found = walkCategory(musicFolder, segments)
	if found then return found, "Music" end

	return nil, nil
end

-- Borrow an idle clone from the pool, or create a new one.
local function acquireClone(source: Sound, category: string): Sound
	local catPool = _pool[category]
	local key     = source:GetFullName()
	local bucket  = catPool[key]
	if bucket and #bucket > 0 then
		return table.remove(bucket) :: Sound
	end
	local clone = source:Clone()
	clone.Parent = source.Parent
	return clone
end

-- Return a clone to the pool (or destroy if over cap).
local function releaseClone(clone: Sound, category: string)
	local catPool = _pool[category]
	local key     = clone:GetFullName()
	-- Key should match the source's full name; clones share the parent path.
	local bucket  = catPool[key]
	if not bucket then
		bucket = {}
		catPool[key] = bucket
	end
	if #bucket < POOL_CAP then
		-- Reset state before pooling.
		clone.Playing = false
		clone.Pitch   = 1
		table.insert(bucket, clone)
	else
		clone:Destroy()
	end
end

-- Build a no-op SoundHandle for when a sound is missing (rule_8).
local function noopHandle(): SoundHandle
	return {
		Stop      = function() end,
		SetPitch  = function(_p) end,
		SetVolume = function(_v) end,
		Instance  = nil,
		OnEnded   = nil,
	}
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	:Play(name, opts?)
	Resolves `name`, clones the Sound, applies opts, plays it, and returns a
	SoundHandle for external control. Returns a no-op handle on miss.
	OnEnded is an assignable callback — set it before the sound ends.
]]
function SoundController:Play(name: string, opts: PlayOpts?): SoundHandle
	local source, category = resolveSound(name)
	if not source or not category then
		warn("[SoundController] sound not found: " .. name .. " — skipping play")
		return noopHandle()
	end

	local o = opts or {}
	local clone = acquireClone(source, category)

	-- Apply volume (category scale × optional override).
	local baseVol = (o.volume ~= nil) and o.volume or source.Volume
	clone.Volume  = baseVol * (_volumes[category] or 1)

	-- Apply pitch.
	clone.Pitch  = (o.pitch ~= nil) and o.pitch or source.Pitch

	-- Apply loop.
	clone.Looped = (o.looped ~= nil) and o.looped or source.Looped

	-- Optional reparent (3D positional sounds).
	if o.parent then
		clone.Parent = o.parent
	end

	-- Per-handle Janitor owns the Ended connection + cleanup.
	local handleJanitor = Janitor.new()
	local handle: SoundHandle = {
		Stop      = function() end,
		SetPitch  = function(_p) end,
		SetVolume = function(_v) end,
		Instance  = clone,
		OnEnded   = nil,
	}

	handle.Stop = function()
		clone:Stop()
		handleJanitor:Destroy()
		_activeHandles[clone] = nil
		if not o.parent then
			releaseClone(clone, category)
		else
			clone:Destroy()
		end
	end

	handle.SetPitch = function(p: number)
		clone.Pitch = p
	end

	handle.SetVolume = function(v: number)
		clone.Volume = v * (_volumes[category] or 1)
	end

	-- Wire Ended — fire OnEnded callback then return clone to pool.
	handleJanitor:Add(clone.Ended:Connect(function()
		_activeHandles[clone] = nil
		if handle.OnEnded then
			handle.OnEnded()
		end
		handleJanitor:Destroy()
		if not o.parent then
			releaseClone(clone, category)
		else
			clone:Destroy()
		end
	end), "Disconnect")

	_activeHandles[clone] = { handle = handle, category = category }
	clone:Play()
	return handle
end

--[[
	:PlayLayered(names, opts?)
	Delegates to Layered.luau. Returns an array of SoundHandles with a combined
	Stop that halts all simultaneously.
]]
function SoundController:PlayLayered(names: { string }, opts: PlayOpts?): { SoundHandle }
	return Layered.PlayLayered(self, names, opts)
end

--[[
	:StopAll(category?)
	Stops every active clone. If `category` is provided, only stops that category.
]]
function SoundController:StopAll(category: ("SFX" | "Music")?)
	for clone, entry in pairs(_activeHandles) do
		if not category or entry.category == category then
			entry.handle.Stop()
		end
	end
end

--[[
	:GetCategoryVolume(category)
	Returns the current volume multiplier for the given category (0–1+).
]]
function SoundController:GetCategoryVolume(category: "SFX" | "Music"): number
	return _volumes[category] or 1
end

--[[
	:SetCategoryVolume(category, value)
	Sets the volume multiplier for the given category. Does not retroactively
	change currently-playing clones (applies on next :Play call).
]]
function SoundController:SetCategoryVolume(category: "SFX" | "Music", value: number)
	_volumes[category] = math.clamp(value, 0, 10)
end

--[[
	:CountTo(opts)
	Delegates to Counting.luau. Returns a CountHandle with Cancel / IsPlaying /
	SetProgress.
]]
function SoundController:CountTo(opts: CountOpts): CountHandle
	return Counting.CountTo(self, opts)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function SoundController:KnitInit()
	-- Nothing async needed here.
end

function SoundController:KnitStart()
	-- Warm-verify category folders exist; warn if missing.
	local sfxFolder = SoundService:FindFirstChild("SFX")
	if not sfxFolder then
		warn("[SoundController] SoundService.SFX folder missing — "
			.. "all SFX plays will no-op until the folder is present")
	end
	local musicFolder = SoundService:FindFirstChild("Music")
	if not musicFolder then
		warn("[SoundController] SoundService.Music folder missing — "
			.. "Music plays will no-op")
	end
end

return SoundController
