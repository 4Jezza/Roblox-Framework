--[[
    WordHuntClient
    --------------
    Client-side state machine for the Word Hunt minigame.

    States:  "idle" | "active" | "results"

    Responsibilities
    ----------------
    - Listen to server bridges: WordHunt_RoundStart, WordHunt_WordResult,
      WordHunt_RoundEnd.
    - Forward selected-word intents to the server via WordHunt_SubmitWord.
    - Drive the WordHuntGridUI HUD (score, timer, result panel) — never touches
      UI properties directly; all display calls go through WordHuntGridUI.
    - Auto-play: defers a StartGame() call at the end of Initialize() so the
      first round begins without manual interaction.
    - Auto-restart: after a round ends, waits 5 s then restarts (unless the
      player already manually restarted).

    DO NOT require UIAnimator here — delegate all display changes to WordHuntGridUI.
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bridges       = require(ReplicatedStorage.Shared.Bridges)
local Janitor       = require(ReplicatedStorage.Packages.Janitor)
local WordHuntConfig = require(ReplicatedStorage.DataModules.WordHuntConfig)
local WordHuntGridUI = require(script.Parent.WordHuntGridUI)

-- ============================================================
-- Module
-- ============================================================

local WordHuntClient = {}

-- ========== STATE ==========

--- "idle" | "active" | "results"
local state: string = "idle"

local totalScore: number = 0
local roundEndsAt: number = 0
local lastRoundResult: { [string]: any }? = nil

local timerConnection: RBXScriptConnection? = nil
local restartDelayThread: thread? = nil

local janitor: typeof(Janitor.new())? = nil

-- ========== HELPERS ==========

local function setState(newState: string)
    state = newState
end

local function disconnectTimer()
    if timerConnection then
        timerConnection:Disconnect()
        timerConnection = nil
    end
end

-- ============================================================
-- Round lifecycle handlers
-- ============================================================

local function onRoundStart(payload: { endsAt: number })
    -- Cancel any pending auto-restart (player already restarted manually or
    -- the server fired a new round while the delay was counting down).
    if restartDelayThread then
        task.cancel(restartDelayThread)
        restartDelayThread = nil
    end

    disconnectTimer()
    setState("active")

    totalScore   = 0
    roundEndsAt  = payload.endsAt

    -- Reset HUD immediately so labels are never stale for a frame.
    WordHuntGridUI.SetScore(0)
    WordHuntGridUI.SetTimer(WordHuntConfig.RoundSeconds)
    WordHuntGridUI.ShowResult(false)
    WordHuntGridUI.SetInteractive(true)

    -- Start live countdown via Heartbeat.
    -- Capture roundEndsAt into a local so the closure is stable even if the
    -- module-level variable is reassigned before the callback fires.
    local capturedEndsAt = roundEndsAt
    timerConnection = RunService.Heartbeat:Connect(function()
        local remaining = math.max(0, capturedEndsAt - workspace:GetServerTimeNow())
        WordHuntGridUI.SetTimer(remaining)
        if remaining <= 0 then
            disconnectTimer()
        end
    end)

    print("[WordHuntClient] Round started. Ends at:", roundEndsAt)
end

local function onWordResult(payload: {
    word: string,
    accepted: boolean,
    score: number,
    totalScore: number,
    path: { { row: number, col: number } }?,
})
    if payload.accepted then
        totalScore = payload.totalScore
        WordHuntGridUI.SetScore(payload.totalScore)
        print(string.format("[WordHuntClient] Word accepted: %q +%d (total %d)",
            payload.word, payload.score, payload.totalScore))
    else
        print(string.format("[WordHuntClient] Word rejected: %q", payload.word))
    end
end

local function onRoundEnd(payload: {
    finalScore: number,
    highScore: number,
    isNewHighScore: boolean,
})
    -- 1. Disconnect the Heartbeat timer.
    disconnectTimer()

    -- 2. Transition to results state.
    setState("results")

    -- 3. Stash result for external readers.
    lastRoundResult = payload

    -- 4 & 5. Freeze grid and show 0:00.
    WordHuntGridUI.SetInteractive(false)
    WordHuntGridUI.SetTimer(0)

    -- 6 & 7. Build and display result text.
    local resultText = string.format(
        "Final: %d\nBest: %d%s",
        payload.finalScore,
        payload.highScore,
        payload.isNewHighScore and "  NEW!" or ""
    )
    WordHuntGridUI.SetResult(resultText)
    WordHuntGridUI.ShowResult(true)

    -- 8. Summary log.
    print(string.format("[WordHuntClient] Round ended. Score=%d  Best=%d  NewHigh=%s",
        payload.finalScore, payload.highScore, tostring(payload.isNewHighScore)))

    -- 9. Schedule auto-restart in 5 seconds.
    -- Capture state-sensitive values before the delay so the closure is safe.
    local capturedStartGame = function()
        WordHuntClient.StartGame()
    end

    restartDelayThread = task.delay(5, function()
        restartDelayThread = nil
        -- Guard: only restart if state hasn't already moved on (e.g., manual
        -- StartGame call during the countdown would have set state to "active").
        if state ~= "results" then
            return
        end
        -- Transition to idle BEFORE calling StartGame so StartGame's own
        -- "idle" guard lets it fire rather than early-returning.
        setState("idle")
        WordHuntGridUI.ShowResult(false)
        WordHuntGridUI.Reset()
        capturedStartGame()
    end)
end

-- ============================================================
-- Public API
-- ============================================================

--- Fire the WordHunt_StartGame bridge to request a new round from the server.
--- No-ops if a round is already active.
function WordHuntClient.StartGame()
    if state == "active" then
        warn("[WordHuntClient] StartGame called while already active — ignored.")
        return
    end

    -- Cancel any pending auto-restart so we don't double-start.
    if restartDelayThread then
        task.cancel(restartDelayThread)
        restartDelayThread = nil
    end

    Bridges.WordHunt_StartGame:Fire({})
    print("[WordHuntClient] StartGame sent to server.")
end

--- Submit a selected word path to the server.
--- path is cloned before sending to avoid mutating the caller's table.
function WordHuntClient.SubmitWord(word: string, path: { { row: number, col: number } })
    if state ~= "active" then return end
    -- Clone the path so the caller can safely reuse/clear it without affecting
    -- the payload in-flight through BridgeNet2's internal queue.
    local pathCopy = table.clone(path)
    Bridges.WordHunt_SubmitWord:Fire({ word = word, path = pathCopy })
end

--- Returns the current state string.
function WordHuntClient.GetState(): string
    return state
end

--- Returns the last round result payload (nil while idle/active).
function WordHuntClient.GetLastResult(): { [string]: any }?
    return lastRoundResult
end

-- ============================================================
-- Initialize
-- ============================================================

function WordHuntClient:Initialize()
    -- Defensive re-init: tear down any previous janitor and cancel pending
    -- timers so a second Initialize() call is safe (hot-reload or test re-entry).
    if janitor then
        janitor:Destroy()
        janitor = nil
    end
    disconnectTimer()
    if restartDelayThread then
        task.cancel(restartDelayThread)
        restartDelayThread = nil
    end

    -- Reset local state.
    setState("idle")
    totalScore      = 0
    roundEndsAt     = 0
    lastRoundResult = nil

    janitor = Janitor.new()

    -- ---- Server → Client bridge listeners ----

    janitor:Add(Bridges.WordHunt_RoundStart:Connect(function(payload)
        onRoundStart(payload)
    end), "Disconnect")

    janitor:Add(Bridges.WordHunt_WordResult:Connect(function(payload)
        onWordResult(payload)
    end), "Disconnect")

    janitor:Add(Bridges.WordHunt_RoundEnd:Connect(function(payload)
        onRoundEnd(payload)
    end), "Disconnect")

    -- Clean up on player leaving (no memory leaks from connections or closures).
    janitor:Add(Players.PlayerRemoving:Connect(function(player)
        if player == Players.LocalPlayer then
            disconnectTimer()
            if restartDelayThread then
                task.cancel(restartDelayThread)
                restartDelayThread = nil
            end
            if janitor then
                janitor:Destroy()
                janitor = nil
            end
        end
    end), "Disconnect")

    print("[WordHuntClient] Initialized.")

    -- Auto-start the first round once all listeners are connected.
    -- task.defer avoids a same-frame race where BridgeNet2 may not have
    -- fully primed the WordHunt_RoundStart listener yet.
    task.defer(function()
        WordHuntClient.StartGame()
    end)
end

return WordHuntClient
