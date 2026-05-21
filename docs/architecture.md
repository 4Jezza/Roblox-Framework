# Architecture overview

A human-readable walkthrough of the boilerplate's architecture. For the deep-dive reference with every require path and gotcha, see [`.claude/reference/architecture.md`](../.claude/reference/architecture.md).

---

## High level

```
┌────────────────────────────────────────────────────────────────┐
│                        ROBLOX DATASTORE                         │
│                     (ProfileStore-backed)                       │
└───────────────────────┬────────────────────────────────────────┘
                        │  profile.Data (shared reference)
                        ▼
┌────────────────────────────────────────────────────────────────┐
│                          SERVER                                 │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              DataService.luau (wrapper)                 │    │
│  │   Get / Set / Update / SetPath / Increment              │    │
│  │   OnDataLoaded / OnBeforeSave / OnProfileSave           │    │
│  │   Leaving-race fallback → profile.Data[key] direct      │    │
│  └───┬────────────────────────────┬────────────────────────┘    │
│      │                            │                              │
│  ┌───▼──────┐            ┌────────▼──────────┐                  │
│  │ ProfileStore │        │ ReplicaService    │                  │
│  │ (persistence)│        │ (state sync)      │                  │
│  └──────────┘            └────────┬──────────┘                  │
│                                   │ replicated                   │
│  ┌──────────────────────────────┐ │                              │
│  │   GameService.luau (Knit)    │ │                              │
│  │   KnitInit: require handlers │ │                              │
│  │   KnitStart: Initialize()    │ │                              │
│  └──────────────────────────────┘ │                              │
│                                   │                              │
│  ┌──────────────────────────────┐ │                              │
│  │ Handlers (Server/Modules/)   │ │                              │
│  │ DataHandler, ProductHandler, │ │                              │
│  │ RemoteConfigHandler, ...     │ │                              │
│  │ - read/write DataService     │ │                              │
│  │ - fire/listen Bridges        │ │                              │
│  │ - per-player mutex pattern   │ │                              │
│  └───────────┬──────────────────┘ │                              │
│              │                     │                              │
└──────────────┼─────────────────────┼──────────────────────────────┘
               │ BridgeNet2          │
               ▼                     ▼
┌────────────────────────────────────────────────────────────────┐
│                          CLIENT                                  │
│                                                                  │
│  ┌──────────────────────────────┐  ┌────────────────────────┐  │
│  │  GameController.luau (Knit)  │  │  ReplicaController     │  │
│  │  KnitInit: require modules   │  │  (loleris client)      │  │
│  │  KnitStart: Initialize()     │  └─────────┬──────────────┘  │
│  └───────────┬──────────────────┘            │                  │
│              │                                │                  │
│  ┌───────────▼──────────────────┐ ┌──────────▼──────────────┐  │
│  │  Client/Modules/             │ │  Utility/PlayerData     │  │
│  │  UIClient, NotificationClient│ │  GetData, OnReady,      │  │
│  │  ChatClient                  │ │  OnSet, OnChange        │  │
│  └──────────────────────────────┘ └─────────────────────────┘  │
│                                                                  │
│  Controllers/ProximityController → initializes ExpressivePrompts │
└────────────────────────────────────────────────────────────────┘
```

---

## Boot order

### Server (`src/Server/Server/init.server.luau`)
1. `require` Knit + Loader
2. `Loader.LoadDescendants(script.Services)` — requires all `*Service.luau` files under `Server/Services/`
3. `Knit.Start():andThen(...)` — triggers `KnitInit` on all services, then `KnitStart`
4. Inside `GameService:KnitStart`:
   - `DataService.Init()` FIRST — initializes ProfileStore and hooks PlayerAdded/PlayerRemoving
   - `RemoteConfigHandler:Initialize()` second — sets workspace attribute defaults before any handler reads them
   - All other handler `Initialize()` calls
5. `print("[Server] Knit started")`

### Client (`src/Client/Client/init.client.luau`)
1. `require` Knit + Loader
2. `Loader.LoadDescendants(script.Controllers)` — requires all `*Controller.luau` files
3. `Knit.Start({ ServicePromises = false }):andThen(...)`
4. Inside `GameController:KnitStart`:
   - `PlayerData.Init()` FIRST — wires up `ReplicaController` for client-side replica reads
   - All client module `Initialize()` calls (UIClient, NotificationClient, ChatClient, ...)
5. `print("[Client] Knit started")`

---

## Data lifecycle

1. **Player joins** → `DataService.OnPlayerAdded` fires
2. `ProfileStore:StartSessionAsync("BoilerplateData_LIVE_1", ...)` — acquires a session-locked profile
3. `profile:Reconcile()` — fills in any missing template fields without overwriting existing values
4. `profile.OnSessionEnd:Connect(...)` — handles mid-session session loss (kicks the player)
5. `ReplicaService.NewReplica({ ClassToken = ..., Data = profile.Data, Replication = player })` — creates a replica with the profile data as a shared reference
6. `DataService.OnDataLoaded` signal fires — handlers (DataHandler → leaderstats) subscribe to this
7. Gameplay mutates data via `DataService.Set/Update/Increment` — writes go through the replica (which mutates the shared `profile.Data` table)
8. **Player leaves** → `DataService.OnPlayerRemoving` fires
9. `beforeSaveCallbacks` run — each handler's `OnBeforeSave` does its final mutation
10. `replica:Destroy()` and `playerReplicas[player] = nil`
11. `profile:EndSession()` — ProfileStore writes `profile.Data` to the DataStore

**Critical race**: between step 10 and step 11, any `DataService.Set` call sees `playerReplicas[player] == nil` and hits the leaving-race fallback, which writes directly to `profile.Data[key]`. Without that fallback, writes during `beforeSaveCallbacks` would be silently lost.

---

## Networking (BridgeNet2)

All client↔server remotes are declared in a single file: `src/Shared/Shared/Bridges.luau`.

Pattern:
```lua
local BridgeNet2 = require(game.ReplicatedStorage.Packages.BridgeNet2)

-- SERVER → CLIENT
local Notify = BridgeNet2.ReferenceBridge("Notify")

-- CLIENT → SERVER
local OpenContainer = BridgeNet2.ReferenceBridge("OpenContainer")

return {
    Notify = Notify,
    OpenContainer = OpenContainer,
}
```

Server listens:
```lua
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
Bridges.OpenContainer:Connect(function(player, data)
    -- mutex + task.spawn pattern — see CLAUDE.md Critical Bans
end)
```

Server fires:
```lua
Bridges.Notify:Fire(player, { type = "Success", message = "Hello" })
```

Client listens:
```lua
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
Bridges.Notify:Connect(function(data)
    NotificationClient.Show(data.message)
end)
```

Client fires:
```lua
Bridges.OpenContainer:Fire({ containerId = 1 })
```

---

## Per-player mutex pattern (MANDATORY on mutating bridges)

Every bridge listener that mutates data needs a per-player lock to prevent rapid-fire duplicate grants:

```lua
local lock: { [number]: boolean } = {}

Bridges.Claim:Connect(function(player)
    local uid = player.UserId
    if lock[uid] then return end  -- gate is synchronous, outside task.spawn
    lock[uid] = true

    task.spawn(function()           -- body is async, inside task.spawn (no yield in bridge callback)
        local ok, err = pcall(function()
            -- do the mutation: DataService.Set, tool grants, etc.
        end)
        lock[uid] = nil              -- release is INSIDE the spawn (so it stays held during async work)
        if not ok then warn("[MyHandler]", err) end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    lock[player.UserId] = nil        -- cleanup to prevent memory leak
end)
```

See `docs/conventions.md` for the full style rules.

---

## UI

- **Framework**: native Roblox `ScreenGui` + `Frame` + `ImageButton` + `TextLabel`, with **UIAnimator (Twinkle)** for all transitions (NEVER raw TweenService for UI).
- **Frame registry**: all visible frames live under `StarterGui.Ui.Frames.<FrameName>`. Access from client code via `UIClient.GetFrame("FrameName")`. The `Ui` ScreenGui is built in Studio (StarterGui is NOT Argon-synced) — reference `filestructure/starter-gui.md` and verify with `mcp__Roblox_Studio__inspect_instance` before writing code that references a frame path.
- **Opening a frame**: `UIClient.OpenFrame(frame)` sets `frame.Visible = true`, plays `UIAnimator.FrameZoom(frame, true, 0.4)`, and calls `updateQuickPlayVisibility()` (which hides the persistent QuickPlay button when any frame is open).
- **Closing a frame**: `UIClient.CloseFrame(frame)` plays the reverse animation and restores QuickPlay.
- **Proximity prompts**: `ProximityController.luau` initializes `ExpressivePrompts` once at client startup. After that, every `ProximityPrompt` in the game automatically gets the custom UI. You only need to set attributes (e.g., `prompt:SetAttribute("BackgroundColor", Color3.fromRGB(...))` for per-prompt color overrides if your fork extends ExpressivePrompts).

---

## Dynamic config (Roblox ConfigService)

`RemoteConfigHandler.luau` bridges Creator Hub Configs into workspace attributes so the client can read them.

Flow:
1. Create a Config in Creator Hub → Configs (e.g. key `Uses_Cheap_Main_Product`, type boolean)
2. RemoteConfigHandler reads it on server boot via `ConfigService:GetConfigAsync()` and mirrors into `workspace:SetAttribute("Uses_Cheap_Main_Product", value)`
3. Client code (and server code) reads `workspace:GetAttribute("Uses_Cheap_Main_Product") == true` to branch behavior
4. `ProductConfig.GetActiveMainProductId()` is the canonical example — returns either the main or alt product ID based on the workspace attribute
5. When you flip the Config in the dashboard, `UpdateAvailable` fires on the server, RemoteConfigHandler re-reads, and the workspace attribute updates → clients see the change within seconds (no republish)

---

## Further reading

- [`.claude/reference/architecture.md`](../.claude/reference/architecture.md) — full require-path and gotcha reference
- [`docs/cookbook.md`](cookbook.md) — concrete recipes for common tasks
- [`docs/conventions.md`](conventions.md) — style guide
- [`docs/repo-map.md`](repo-map.md) — folder-by-folder repo map
- [`CLAUDE.md`](../CLAUDE.md) — orchestrator rules for Claude Code agents
