--[[
	SoundController/Layered
	-----------------------
	Implements PlayLayered: plays N named sounds simultaneously with shared opts
	and returns an array of SoundHandles plus a combined wrapper handle whose
	:Stop() halts all of them at once.

	Called exclusively by SoundController:PlayLayered — do not require this
	module from outside SoundController.

	Per architecture.md § Sound runtime path — resolution delegated back to
	SoundController:Play so the single canonical resolver is never duplicated.
	Per api-reference.md § 3.1 Janitor — wrapping Janitor owns sub-handles.
]]

local Layered = {}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--[[
	PlayLayered(controller, names, opts?)
	`controller` is the SoundController instance (passed from init.luau).
	Returns a flat array of SoundHandles; the first element is a combined
	"group handle" whose Stop() halts all, and elements 2..N+1 are the
	individual per-sound handles.

	Layout: { groupHandle, handle1, handle2, ... }
	Callers that only need to stop the whole group use result[1].Stop().
	Callers that need per-sound pitch/volume control index into result[2+].
]]
function Layered.PlayLayered(controller: any, names: { string }, opts: any?): { any }
	if #names == 0 then
		return {}
	end

	local handles: { any } = {}

	-- Play each sound individually via the canonical :Play path.
	for _, name in ipairs(names) do
		local h = controller:Play(name, opts)
		table.insert(handles, h)
	end

	-- Build a group handle that stops all constituent handles.
	local groupStopped = false
	local groupHandle = {
		Stop = function()
			if groupStopped then return end
			groupStopped = true
			for _, h in ipairs(handles) do
				h.Stop()
			end
		end,
		SetPitch = function(p: number)
			for _, h in ipairs(handles) do
				h.SetPitch(p)
			end
		end,
		SetVolume = function(v: number)
			for _, h in ipairs(handles) do
				h.SetVolume(v)
			end
		end,
		Instance = nil, -- group has no single Instance
		OnEnded  = nil,
	}

	-- Return groupHandle first, then individual handles.
	local result: { any } = { groupHandle }
	for _, h in ipairs(handles) do
		table.insert(result, h)
	end
	return result
end

return Layered
