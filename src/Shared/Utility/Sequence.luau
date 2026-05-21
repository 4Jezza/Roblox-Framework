--!strict
--[[
	SEQUENCE
	--------
	Chainable async sequencing primitive. Ordered, parallel, and event-driven
	steps with one `:Run()`. Janitor-aware via `:Bind(janitor)`.

	Import:
	    local Sequence = require(game.ReplicatedStorage.Utility.Sequence)

	See `.claude/reference/api-reference.md § 3.4 Sequence` for the full method
	table, examples, and gotchas.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

type StepKind = "fn" | "wait" | "waitFor" | "waitForCondition" | "parallel" | "race"
type Step = {
	kind: StepKind, fn: (() -> ())?, seconds: number?, connectable: any?,
	predicate: (() -> boolean)?, pollInterval: number?, fns: { () -> () }?,
}

local Sequence = {}
Sequence.__index = Sequence

export type Sequence = typeof(setmetatable(
	{} :: {
		_steps: { Step }, _cancelled: boolean, _running: boolean, _complete: boolean,
		_runner: thread?, _janitor: any?, _onComplete: { () -> () },
		_onError: { (err: any) -> boolean? }, _completedFired: boolean, Completed: any,
		_activeWaitForCleanup: (() -> ())?, _activeParallelCleanup: (() -> ())?,
	},
	Sequence
))

function Sequence.new(): Sequence
	return setmetatable({
		_steps = {}, _cancelled = false, _running = false, _complete = false,
		_runner = nil, _janitor = nil, _onComplete = {}, _onError = {},
		_completedFired = false, Completed = Signal.new(),
		_activeWaitForCleanup = nil, _activeParallelCleanup = nil,
	}, Sequence) :: any
end

function Sequence:Step(fn: () -> ()): Sequence
	assert(typeof(fn) == "function", "[Sequence] :Step expects a function")
	table.insert(self._steps, { kind = "fn", fn = fn } :: Step); return self
end
function Sequence:Wait(seconds: number): Sequence
	assert(typeof(seconds) == "number" and seconds >= 0, "[Sequence] :Wait expects a non-negative number")
	table.insert(self._steps, { kind = "wait", seconds = seconds } :: Step); return self
end
function Sequence:WaitFor(connectable: any): Sequence
	table.insert(self._steps, { kind = "waitFor", connectable = connectable } :: Step); return self
end
function Sequence:WaitForCondition(predicate: () -> boolean, pollInterval: number?): Sequence
	assert(typeof(predicate) == "function", "[Sequence] :WaitForCondition expects a function predicate")
	table.insert(self._steps, { kind = "waitForCondition", predicate = predicate, pollInterval = pollInterval or 0.1 } :: Step)
	return self
end
function Sequence:Parallel(fns: { () -> () }): Sequence
	assert(typeof(fns) == "table", "[Sequence] :Parallel expects a table of functions")
	table.insert(self._steps, { kind = "parallel", fns = fns } :: Step); return self
end
function Sequence:Race(fns: { () -> () }): Sequence
	assert(typeof(fns) == "table", "[Sequence] :Race expects a table of functions")
	table.insert(self._steps, { kind = "race", fns = fns } :: Step); return self
end
function Sequence:Bind(janitor: any): Sequence
	if self._running or self._complete then
		warn("[Sequence] :Bind called after :Run — janitor cancellation not wired")
		return self
	end
	if typeof(janitor) ~= "table" or typeof(janitor.Add) ~= "function" then
		warn("[Sequence] :Bind target has no :Add method — skipping bind"); return self
	end
	self._janitor = janitor; janitor:Add(self, "Cancel"); return self
end
function Sequence:OnComplete(fn: () -> ()): Sequence
	assert(typeof(fn) == "function", "[Sequence] :OnComplete expects a function")
	table.insert(self._onComplete, fn); return self
end
function Sequence:OnError(fn: (err: any) -> boolean?): Sequence
	assert(typeof(fn) == "function", "[Sequence] :OnError expects a function")
	table.insert(self._onError, fn); return self
end

function Sequence:_runWaitFor(target: any)
	if typeof(target) ~= "table" and typeof(target) ~= "userdata" then
		warn("[Sequence] :WaitFor target has no :Once or :Connect — skipping step"); return
	end
	local done, connection = Signal.new(), nil :: any
	if typeof(target.Once) == "function" then connection = target:Once(function() done:Fire() end)
	elseif typeof(target.Connect) == "function" then connection = target:Connect(function() done:Fire() end)
	else warn("[Sequence] :WaitFor target has no :Once or :Connect — skipping step"); done:Destroy(); return end
	local cleanup = function()
		if connection then pcall(function() connection:Disconnect() end) end
		pcall(function() done:Destroy() end)
	end
	self._activeWaitForCleanup = cleanup; done:Wait(); self._activeWaitForCleanup = nil; cleanup()
end

function Sequence:_runParallel(fns: { () -> () }, raceMode: boolean)
	if #fns == 0 then return end
	local done, remaining, finished, threads = Signal.new(), #fns, false, {} :: { thread }
	for _, fn in ipairs(fns) do
		table.insert(threads, task.spawn(function()
			local ok, err = pcall(fn)
			if not ok then warn("[Sequence] parallel/race step errored: " .. tostring(err)) end
			if finished then return end
			if raceMode then finished = true; done:Fire()
			else remaining -= 1; if remaining <= 0 then finished = true; done:Fire() end end
		end))
	end
	local cleanup = function()
		for _, t in ipairs(threads) do pcall(task.cancel, t) end
		pcall(function() done:Destroy() end)
	end
	self._activeParallelCleanup = cleanup; done:Wait(); self._activeParallelCleanup = nil
	if raceMode then for _, t in ipairs(threads) do pcall(task.cancel, t) end end
	pcall(function() done:Destroy() end)
end

function Sequence:_executeSteps()
	local lastError: any = nil
	for i, step in ipairs(self._steps) do
		if self._cancelled then break end
		local ok, err = pcall(function()
			if step.kind == "fn" then (step.fn :: () -> ())()
			elseif step.kind == "wait" then task.wait(step.seconds :: number)
			elseif step.kind == "waitFor" then self:_runWaitFor(step.connectable)
			elseif step.kind == "waitForCondition" then
				local p, iv = step.predicate :: () -> boolean, step.pollInterval :: number
				while not p() and not self._cancelled do task.wait(iv) end
			elseif step.kind == "parallel" then self:_runParallel(step.fns :: { () -> () }, false)
			elseif step.kind == "race" then self:_runParallel(step.fns :: { () -> () }, true)
			end
		end)
		if not ok then
			lastError = err
			local continueRun = false
			for _, handler in ipairs(self._onError) do
				local hOk, ret = pcall(handler, err)
				if hOk and ret == true then continueRun = true end
			end
			if continueRun then
				warn("[Sequence] step " .. i .. " errored but OnError handler recovered: " .. tostring(err))
			else
				warn("[Sequence] step " .. i .. " errored — halting: " .. tostring(err))
				self._cancelled = true; break
			end
		end
	end
	self._running = false; self._complete = true
	if not self._cancelled then
		for _, fn in ipairs(self._onComplete) do
			local ok, err = pcall(fn)
			if not ok then warn("[Sequence] OnComplete handler errored: " .. tostring(err)) end
		end
	end
	if not self._completedFired then
		self._completedFired = true
		self.Completed:Fire(not self._cancelled, lastError)
	end
end

function Sequence:Run(): Sequence
	if self._running or self._complete then
		warn("[Sequence] :Run called on sequence that is already running or complete — ignored"); return self
	end
	self._running = true
	self._runner = task.spawn(function() self:_executeSteps() end)
	return self
end

function Sequence:Cancel()
	if self._complete or self._cancelled then return end
	self._cancelled = true
	if self._activeWaitForCleanup then pcall(self._activeWaitForCleanup); self._activeWaitForCleanup = nil end
	if self._activeParallelCleanup then pcall(self._activeParallelCleanup); self._activeParallelCleanup = nil end
	if self._runner then pcall(task.cancel, self._runner) end
	self._running = false; self._complete = true
	if not self._completedFired then
		self._completedFired = true
		self.Completed:Fire(false, "cancelled")
	end
end

function Sequence:IsRunning(): boolean return self._running end
function Sequence:IsCancelled(): boolean return self._cancelled end
function Sequence:IsComplete(): boolean return self._complete end

-- Safe completion-wait. Use instead of `seq.Completed:Wait()` since synchronous
-- sequences finish inside :Run() before any external :Wait() can register.
function Sequence:Await(): () if not self._complete then self.Completed:Wait() end end

return Sequence
