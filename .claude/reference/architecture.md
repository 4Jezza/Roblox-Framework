# Architecture Reference

> Agents: read this file when you need folder mappings, require paths, or file naming rules.
> This is the single source of truth for import paths and project structure.

---

## Framework

**Knit** (SSA — Single Script Architecture) + **split sync**: Argon for scripts, Roblox Studio MCP for asset instances. `src/` mirrors the script side of the DataModel via `default.project.json`; asset roots (StarterGui, Workspace, `ReplicatedStorage.Assets`, `ServerStorage.Assets`) live in-Studio only — see `.claude/reference/asset-discovery.md` and `filestructure/`.

The boilerplate uses **Mad Studio Replica** for state replication, wrapped by `DataService.luau` to expose a stable API surface (Get / Set / Update / SetPath / Increment / OnDataLoaded / OnBeforeSave / OnProfileSave). Handler code that calls `DataService.X` is portable across projects regardless of the underlying replica engine. Mad Studio Replica is VENDORED directly into `src/` (it is not on Wally) — see `src/Server/ReplicaServer.luau`, `src/Shared/ReplicaClient.luau`, and `src/Shared/ReplicaShared/`.

---

## Where to find things

Task-oriented quick-find. Path-mapping detail (local ↔ Studio) lives in the next section.

| Need                              | Path                                                                                            |
|---                                |---                                                                                              |
| Server handlers                   | `src/Server/Server/Modules/*Handler.luau`                                                       |
| Knit service (handler registry)   | `src/Server/Server/Services/GameService.luau`                                                   |
| Client controllers                | `src/Client/Client/Controllers/*Controller.luau`                                                |
| Per-feature UI bindings (stateful)| `src/Client/Client/<Feature>Bindings/*.luau`                                                    |
| Stateless UI primitives           | `src/Client/Client/UI/*.luau`                                                                   |
| Client modules                    | `src/Client/Client/Modules/*.luau` (UIClient, NotificationClient, ChatClient)                   |
| Configs (numbers, IDs, formulas)  | `src/Shared/DataModules/*Config.luau`                                                           |
| Shared utilities                  | `src/Shared/Utility/*.luau` — `Format`, `Janitor`, `Spring`, `PlayerData`, `Sequence`           |
| Networking (Bridges registry)     | `src/Shared/Shared/Bridges.luau`                                                                |
| Type definitions                  | `src/Shared/Shared/Types.luau`                                                                  |
| Data layer (server)               | `src/ServerStorage/ServerUtilities/DataService.luau`                                            |
| Sound playback (client)           | `src/Client/Client/Controllers/SoundController/` — `init.luau` + `Presets.luau` + `Layered.luau` + `Counting.luau` |
| Player state machine (client)     | `src/Client/Client/Controllers/PlayerStateController.luau`                                     |
| Player state types (shared)       | `src/Shared/Utility/PlayerState.luau`                                                          |
| World entity replicas (server)    | `src/Server/Server/Modules/WorldEntityHandler.luau`                                            |
| Purchase effects (client)         | `src/Client/Client/Controllers/PurchaseEffectsController.luau`                                 |
| Loading screen (client)           | `src/Client/Client/Controllers/LoadingScreenController.luau`                                   |
| UIAnimator presets (client)       | `src/Client/Client/Controllers/UIAnimator/Presets/*.luau`                                      |
| WorldAnimator presets (client)    | `src/Client/Client/Controllers/WorldAnimator/Presets/*.luau`                                   |
| Studio asset snapshots (cache)    | `filestructure/*.md` — verify against MCP before acting                                         |
| Vendored libraries (READ-ONLY)    | `Packages/`, `src/Server/Server/Packages/`, `src/Client/Client/Packages/`, `Replica*`           |
| Agent definitions (domain routing)| `.claude/agents/*.md`                                                                           |
| Asset discovery protocol          | `.claude/reference/asset-discovery.md`                                                          |

---

## Folder → Studio Mapping

Split sync: scripts via Argon, asset instances via Roblox Studio MCP.

| Local path                           | Studio location                          | Sync        |
|--------------------------------------|------------------------------------------|-------------|
| `src/Server/`                        | `ServerScriptService`                    | Argon       |
| `src/Client/`                        | `StarterPlayer.StarterPlayerScripts`     | Argon       |
| `src/Shared/`                        | `ReplicatedStorage` (code children)      | Argon       |
| `src/ServerStorage/ServerUtilities/` | `ServerStorage.ServerUtilities`          | Argon       |
| `Packages/`                          | `ReplicatedStorage.Packages`             | Argon       |
| `src/Server/Server/Packages/`        | `ServerScriptService.Server.Packages`    | Argon       |
| — (in-Studio only)                   | `StarterGui.*`                           | **MCP**     |
| — (in-Studio only)                   | `Workspace.*`                            | **MCP**     |
| — (in-Studio only)                   | `ReplicatedStorage.Assets`               | **MCP**     |
| — (in-Studio only)                   | `ServerStorage.Assets`                   | **MCP**     |

**`src/StarterGui/` and `src/Workspace/Map/` are archived under `src/_archive/` — do not read them for live instance paths.** Use `mcp__Roblox_Studio__search_game_tree` plus `filestructure/*.md` instead. Full asset-discovery rule: `.claude/reference/asset-discovery.md`.

Wally outputs shared packages to `Packages/` at the project root and server packages to `ServerPackages/` (which must be moved into `src/Server/Server/Packages/` after install — see the post-install move command in `wally.toml`). These locations are gitignored and re-generated by `wally install`.

---

## Snapshot refresh protocol (assets only)

Asset roots are snapshotted under `filestructure/` as MD files. Protocol:

1. Before a task touches any asset path, read the matching `filestructure/<root>.md`.
2. Before writing code that references a path, verify with `mcp__Roblox_Studio__inspect_instance`.
3. After `search_game_tree` / `inspect_instance` reveals new/changed nodes, rewrite the matching MD and bump the timestamp in `filestructure/last-updated.json`.
4. If `mcp__Roblox_Studio__list_roblox_studios` is empty, stop. Never fabricate paths from stale MD.

See `filestructure/README.md` for the format spec and `.claude/reference/asset-discovery.md` for worked examples.

---

## File Naming

| Suffix             | Roblox class                                |
|--------------------|---------------------------------------------|
| `*.server.luau`    | Script                                      |
| `*.client.luau`    | LocalScript                                 |
| `*.luau` (plain)   | ModuleScript                                |
| `init.luau`        | ModuleScript (parent folder = instance)     |
| `init.server.luau` | Script (parent folder = instance)           |
| `init.client.luau` | LocalScript (parent folder = instance)      |
| `init.meta.json`   | sets className/properties on the parent dir |

Convention:
- `*Handler.luau` — server module under `Server/Modules/`
- `*Client.luau` — client module under `Client/Modules/`
- `*Service.luau` — Knit service under `Server/Services/`
- `*Controller.luau` — Knit controller under `Client/Controllers/`
- `*Config.luau` — shared data table under `Shared/DataModules/`

---

## Module-as-folder convention (rule_16)

Helpers for a parent module live as **children** of a folder named after the parent, NOT as flat `Parent_Child.luau` siblings. Argon/Rojo treats a folder whose `init.luau` sits inside as a single ModuleScript; children of the folder become children of that ModuleScript in Studio. External require paths stay stable when a flat module is later promoted to a folder.

```
src/Server/Server/Modules/
├─ MyHandler.luau                ← flat — fine while small
└─ DataHandler/                  ← folder — once helpers exist
   ├─ init.luau                  (parent body)
   ├─ Save.luau
   └─ Migration/                 (further nesting if needed)
      ├─ init.luau
      └─ Steps.luau
```

**Internal require paths:**
- From `Foo/init.luau` to a child: `require(script.Child)`
- From `Foo/Child.luau` to a sibling: `require(script.Parent.OtherChild)`
- From `Foo/Sub/Leaf.luau` to a grandparent's child: `require(script.Parent.Parent.Cousin)`
- Cross-group / external references: use the canonical `ReplicatedStorage.X` or `script.Parent.OtherModule` path — folder ModuleScripts behave identically to flat ModuleScripts in Studio.

**Knit controller `Name = "..."` strings are runtime identifiers** unrelated to the filesystem layout. Don't rename them when promoting a controller to a folder unless every `Knit.GetController("...")` caller is updated too.

**Three use cases trigger the folder pattern:**
- **(a) Helper splits** — module hits rule_9's soft cap or has tightly-coupled helpers. **When NOT to use:** the helper has multiple unrelated callers — put it in `src/Shared/Utility/` instead.
- **(b) Sequence / state-machine states** — a controller driven by `Sequence` with N states exposes each state as a child ModuleScript. Pattern: `MyFlowController/{init, Lobby, InZone, BetweenZones, Dead}.luau`, where init assembles the Sequence and each child returns the state body. Applies to any multi-state flow (boot sequences, multi-step setup, cinematics).
- **(c) Top-level category folders** — promote a category like `Combat/` only when scale warrants (heuristic ≥6 modules + clear bounded context). Small clusters stay floating.

**Forbidden:** new flat `Parent_Child.luau` siblings — that pattern is fully retired.

---

## Require Paths

```lua
-- Wally packages (ReplicatedStorage.Packages)
local Knit         = require(game.ReplicatedStorage.Packages.Knit)
local Loader       = require(game.ReplicatedStorage.Packages.Loader)
local Signal       = require(game.ReplicatedStorage.Packages.Signal)
local Janitor      = require(game.ReplicatedStorage.Packages.Janitor)
local Spring       = require(game.ReplicatedStorage.Packages.Spring)        -- 3D animation
local TableUtil    = require(game.ReplicatedStorage.Packages.TableUtil)
local Sift         = require(game.ReplicatedStorage.Packages.Sift)
local BridgeNet2   = require(game.ReplicatedStorage.Packages.BridgeNet2)
local Trove        = require(game.ReplicatedStorage.Packages.Trove)          -- UIAnimator internal dep
local Timer        = require(game.ReplicatedStorage.Packages.Timer)
local WaitFor      = require(game.ReplicatedStorage.Packages.WaitFor)
local ZonePlus     = require(game.ReplicatedStorage.Packages.Zone)           -- ZonePlus
local TopbarPlus   = require(game.ReplicatedStorage.Packages.TopbarPlus)
local EZVisualz    = require(game.ReplicatedStorage.Packages.EZVisualz)
local ExpressivePrompts = require(game.ReplicatedStorage.Packages.ExpressivePrompts)

-- Server-only packages (ServerScriptService.Server.Packages)
local ProfileStore   = require(game.ServerScriptService.Server.Packages.ProfileStore)

-- Mad Studio Replica (VENDORED, not a Wally package)
--   Server:  src/Server/ReplicaServer.luau  -> ServerScriptService.ReplicaServer
--   Client:  src/Shared/ReplicaClient.luau  -> ReplicatedStorage.ReplicaClient
--   Shared:  src/Shared/ReplicaShared/       -> ReplicatedStorage.ReplicaShared
local Replica        = require(game.ServerScriptService.ReplicaServer) -- server-side
-- local ReplicaClient = require(game.ReplicatedStorage.ReplicaClient)  -- client-side

-- Server utilities (ServerStorage.ServerUtilities)
local DataService     = require(game.ServerStorage.ServerUtilities.DataService)
local SignalBank      = require(game.ServerStorage.ServerUtilities.SignalBank)
local ServerUtilities = require(game.ServerStorage.ServerUtilities.ServerUtilities)

-- Shared utilities (ReplicatedStorage.Utility)
local PlayerData = require(game.ReplicatedStorage.Utility.PlayerData)  -- client-only (wraps ReplicaClient)
local Format     = require(game.ReplicatedStorage.Utility.Format)
local SharedJanitor = require(game.ReplicatedStorage.Utility.Janitor)  -- thin re-export of Wally Janitor
local SharedSpring  = require(game.ReplicatedStorage.Utility.Spring)   -- thin re-export of Wally Spring
local Sequence   = require(game.ReplicatedStorage.Utility.Sequence)    -- chainable async sequencer (see api-reference.md § 3.9)

-- Shared modules (ReplicatedStorage.Shared)
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
local Types   = require(game.ReplicatedStorage.Shared.Types)

-- Configs (ReplicatedStorage.DataModules)
local ProductConfig = require(game.ReplicatedStorage.DataModules.ProductConfig)

-- Client packages (from a Client controller/module context)
local UIAnimator    = require(script.Parent.Parent.Packages.UIAnimator)     -- DEFAULT for all UI transitions
local ReplicaClient = require(game.ReplicatedStorage.ReplicaClient)          -- Mad Studio Replica client

-- Project Knit controllers / shared types (fetch via Knit.GetController in KnitStart, not directly required)
local SoundController        = Knit.GetController("SoundController")          -- Play("UI.Hover"), pooling + categories
local PlayerStateController  = Knit.GetController("PlayerStateController")    -- :Set / :IsAllowed gate
local UIAnimatorCtrl         = Knit.GetController("UIAnimator")               -- preset library (Notify, BindNumberLabel, ...)
local WorldAnimator          = Knit.GetController("WorldAnimator")            -- world preset library (HoverBob, SpringGrow, ...)
local PlayerState            = require(game.ReplicatedStorage.Utility.PlayerState)  -- shared PlayerState type definitions
```

Knit controllers (`SoundController`, `PlayerStateController`, the project's `UIAnimator` Knit controller, `WorldAnimator`) are fetched via `Knit.GetController("Name")` from inside another controller's `KnitStart` — never via `require(...)`. The wally `UIAnimator` package (Twinkle, vendored at `src/Client/Client/Packages/UIAnimator/`) is distinct from the project-level `UIAnimator` Knit controller at `src/Client/Client/Controllers/UIAnimator/` which adds the preset library + `Notify` / `BindNumberLabel*` helpers on top.

---

## Critical Bans (NEVER violate)

- **DataStore key `'BoilerplateData_LIVE_1'`** — never rename. Renaming wipes all player data. Set this to your own immutable key when you fork the boilerplate, then never touch it again.
- **UIAnimator (Twinkle) is client-only.** Never require it on the server or in any Shared module the server loads.
- **ExpressivePrompts replaces the default proximity prompt UI** — already initialized in `ProximityController.luau`. Don't manually set `Prompt.Style = Default`.
- **Replica API:** the boilerplate uses **Mad Studio Replica** (vendored — NOT a Wally package). It lives at `src/Server/ReplicaServer.luau`, `src/Shared/ReplicaClient.luau`, and `src/Shared/ReplicaShared/`. `DataService.luau` wraps it.
  - Server: use `DataService.Get/Set/Update/SetPath/Increment/OnDataLoaded`. Never call `Replica.New` directly outside `DataService.luau`.
  - The raw Replica API uses `Replica.Token(name)` then `Replica.New({Token, Tags, Data})`; mutate via `replica:Set({path}, value)` or `replica:SetValues({path}, {...})`.
  - Client: use `replica:OnSet(path, listener)` or `replica:OnChange(listener)` — both are exported by Mad Studio Replica's client module. The client's `PlayerData.OnSet` helper delegates to `replica:OnSet`.
- **Springs over TweenService** for 3D animations (part movement, scale, highlights). TweenService is only acceptable for one-shot fire-and-forget cases where spring polling would be wasteful (e.g., a single transparency fade on a temporary instance).
- **No yield in bridge handlers.** Wrap bodies in `task.spawn` so the BridgeNet2 dispatch loop is never blocked. The `DataService.Set` call yields internally (ProfileStore save) — wrap any bridge listener that calls it.
- **Per-player mutex on bridge handlers that mutate data.** Pattern:
  ```lua
  local lock: { [number]: boolean } = {}
  Bridges.MyBridge:Connect(function(player)
      local uid = player.UserId
      if lock[uid] then return end
      lock[uid] = true
      task.spawn(function()
          local ok, err = pcall(function()
              -- ... mutating logic ...
          end)
          lock[uid] = nil
          if not ok then warn("[MyHandler]", err) end
      end)
  end)
  Players.PlayerRemoving:Connect(function(player)
      lock[player.UserId] = nil
  end)
  ```
- **Per-player table cleanup.** Every per-player table (keyed by `UserId`) MUST have a `Players.PlayerRemoving` cleanup or it's a memory leak.
- **Capture state into locals BEFORE `task.delay` callbacks.** Module/table state may be nil by the time the delay fires.
- **Never use `local X = X or default`** where X should come from a config module — it reads an undefined global (always nil). Use `ConfigModule.Field or default` instead.
- **Raw `tostring(n)` for client display is forbidden.** All client-visible numeric output must pass through `Format.Suffix` (default) or `Format.Commas` — see § Client-visible numbers below.

---

## Client-visible numbers

All client-visible numeric output — currency, scores, counts, balances, leaderboards,
popups, anything a player reads — MUST be passed through `Format.Suffix` (default)
or `Format.Commas`. Raw `tostring(n)` for client display is forbidden.

```lua
local Format = require(game.ReplicatedStorage.Utility.Format)

-- Default form  → "1.5M", "40K", "139B"
Format.Suffix(1500000)       -- "1.5M"
Format.Suffix(40000)         -- "40K"

-- Comma form    → "1,500,000"
Format.Commas(1500000)       -- "1,500,000"

-- Convenience wrapper (mode defaults to "suffix")
Format.Number(1500000)               -- "1.5M"
Format.Number(1500000, "commas")     -- "1,500,000"
```

See `src/Shared/Utility/Format.luau` and `api-reference.md § Project — Format`.

**Animated/changing numbers (preferred path for any label whose value updates over time)** — bind the label to a value source via the project `UIAnimator` Knit controller. Every binding springs the displayed number and pipes it through `Format` automatically:

```lua
local UIAnimator = Knit.GetController("UIAnimator")

-- Pure getter (recomputed each frame the spring ticks):
UIAnimator:BindNumberLabel(label, function() return localScore end)

-- Local player's replica path (auto-resubscribes via PlayerData):
UIAnimator:BindPlayerDataNumber(label, { "cash" })

-- Arbitrary world replica + data path (BillboardGui labels driven by WorldEntity etc.):
UIAnimator:BindReplicaNumber(label, replica, { "points" })

-- All three accept opts = { format = "suffix" | "commas" | function, prefix, suffix, springSpeed, springDamper }
```

Raw `label.Text = tostring(n)` for changing values is forbidden — it bypasses both `Format` and the spring. See `api-reference.md § Project — UIAnimator` (NumberLabel/PlayerData/Replica preset family).

---

## Visual / Animation Policy

Visuals and animations are **client-first**: the client plays the effect immediately on local input or on replica subscription without waiting for a round-trip. The server is the source of truth; it validates every action and publishes authoritative state via Replica. The client receives that authoritative state and reconciles its visuals (snap, correct, or smooth-blend) if they diverged.

- Never block visual feedback waiting on a server response.
- Never let a client visual flag drive a server-side rule.

Canonical implementations: `src/Client/Client/Controllers/ReplicaController.luau` (non-PlayerData replica subscriptions) and `WorldAnimator/init.luau` (world animation consumer that calls `ReplicaController:OnReplicaNew`).

### Preset registry

Future agents must reach for an existing preset before authoring bespoke tween/spring code. Both registries hang off Knit controllers — fetch with `Knit.GetController("UIAnimator")` / `Knit.GetController("WorldAnimator")` from a sibling controller's `KnitStart`.

- **UIAnimator presets** (`src/Client/Client/Controllers/UIAnimator/Presets/`): `Confetti`, `ShiningButton`, `RotateOscillate`, `NumberLabel` (Explicit / PlayerData / Replica variants), `Countdown`, `Enlargen`, `Shrink`, `Notification`. Full method signatures: `api-reference.md § Project — UIAnimator`.
- **WorldAnimator presets** (`src/Client/Client/Controllers/WorldAnimator/Presets/`): `HoverBob`, `SpringGrow`, `SpringShrink`, `SpringVanish`, `SpringMaterialize`, `ExplodeBounce`, `MagnetToPlayer`, `BezierMove`, `LinearSpring`. Full method signatures: `api-reference.md § Project — WorldAnimator`.

If a preset doesn't fit, extend the matching `Presets/` folder rather than rolling raw `TweenService`/`Spring` calls at the call site — keeps motion characteristics consistent across the game.

---

## Sound runtime path

`SoundService` has pre-declared `Folder` children at `default.project.json`:
- `SoundService.Events`
- `SoundService.Music`
- `SoundService.SFX`

At runtime, sounds live UNDER one of those folders, NOT as direct children of `SoundService`. Lookup pattern:
```lua
local SoundService = game:GetService("SoundService")
local sfx = SoundService:FindFirstChild("SFX")
local mySound = sfx and sfx:FindFirstChild("MySound")
if mySound then mySound:Play() end
```

Never `WaitForChild` at module require time — use `FindFirstChild` and gracefully no-op if missing.

---

## Sound playback

Future agents must play sound via `Knit.GetController("SoundController"):Play("UI.Hover")` (or `"SFX.Coin"`, `"Music.Lobby"`, etc. — dotted-path resolution under `SoundService.SFX` / `.Music` / `.Events`). Direct `Sound:Play()` is forbidden — the controller owns pooling, category volume mixing, name resolution, and the layered/counting presets (`SoundController/Layered.luau`, `SoundController/Counting.luau`, `SoundController/Presets.luau`). See `api-reference.md § Project — SoundController`.

```lua
local Sound = Knit.GetController("SoundController")
Sound:Play("UI.Hover")              -- pooled one-shot; no manual cloning
Sound:Play("SFX.Coin", { volume = 0.6, pitch = 1.1 })
```

The runtime folder convention (`SoundService.SFX/.Music/.Events`) still applies — `SoundController` is the only consumer that should walk those folders directly.

---

## Notifications

Future agents must surface notifications via the project `UIAnimator` Knit controller — never clone the notification templates manually, never build a bespoke notification frame. Templates live at `PlayerGui.Ui.HUD.Notification.<TemplateName>` and are hidden at boot; the controller clones, animates (entry + exit via the `Notification` preset), and plays the default sound (`SoundService.SFX.UI.Notification`).

```lua
local UIAnimator = Knit.GetController("UIAnimator")
UIAnimator:Notify("Reward claimed")           -- default template
UIAnimator:NotifyError("Not enough cash")     -- error template
UIAnimator:NotifyTutorial("Hold E to grab")   -- tutorial template
UIAnimator:NotifySpecial("Boss defeated!")    -- special template
```

`NotificationClient.Show` / `.Success` / `.Error` / `.ShowTutorial` are kept as thin backwards-compatible wrappers that delegate to these methods — new code should call `UIAnimator:Notify*` directly. See `api-reference.md § Project — UIAnimator` for the full notification preset surface.

---

## Player State

Client-side state machine that gates UI/input across the boilerplate's runtime modes. Future agents must check `PlayerStateController:IsAllowed("frame", frameName)` (or `"input"`, `"hud"`, etc.) before opening UI or accepting input — never read or mutate `state` ad-hoc on the local player.

Built-in states: `Idle`, `InMenu`, `InGame`, `InCutscene`, `Loading`. Register additional states via `:Register(def)` where `def` describes which surfaces are allowed in that state. Type definitions live in `src/Shared/Utility/PlayerState.luau` (shared so server-driven transitions can use the same identifiers).

```lua
local PS = Knit.GetController("PlayerStateController")

-- Transition (caller is responsible for the legality of the transition)
PS:Set("InGame")

-- Gate before opening any frame
if PS:IsAllowed("frame", "Shop") then
    -- open the Shop frame
end

-- Custom state
PS:Register({
    name = "Spectating",
    allowed = { frame = { "Spectator" }, input = { "camera" } },
})
```

See `api-reference.md § Project — PlayerStateController`.

---

## Mobile force-landscape

The project `UIAnimator` Knit controller (`src/Client/Client/Controllers/UIAnimator/init.luau`) detects mobile at `KnitStart` (`UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled`) and, after a 1-second settle, forces the device to `Enum.ScreenOrientation.LandscapeRight`. This applies to every game built on this framework — there is no per-game opt-in.

**Opt out**: edit `UIAnimator/init.luau` and remove (or guard) the orientation block in `:KnitStart`. Don't try to override the orientation from a sibling controller — `UIAnimator`'s `KnitStart` writes after a `task.wait(1)` and will clobber your value. Document the opt-out per fork in CLAUDE.md § Game Overview if landscape is undesired.

---

## DataService API

`src/ServerStorage/ServerUtilities/DataService.luau` is the single entry point for player data on the server. It wraps ProfileStore + Mad Studio Replica (vendored).

| Method | Description |
|---|---|
| `DataService.Init()` | Called once from `GameService:KnitStart`. Hooks PlayerAdded/PlayerRemoving. |
| `DataService.Get(player, key)` | Reads from `profile.Data[key]`. |
| `DataService.GetData(player)` | Returns the entire `profile.Data` table. |
| `DataService.Set(player, key, value)` | Writes via `replica:SetValue`, with leaving-race fallback to `profile.Data[key] = value` if the replica is gone. Fires per-key signals. |
| `DataService.Update(player, key, callback)` | Reads old value, calls callback, writes the result. Same fallback. |
| `DataService.Increment(player, key, amount)` | Delegates to Update. |
| `DataService.SetPath(player, path, value)` | For nested paths like `{"slots", "1", "level"}`. Same fallback that walks `profile.Data` and creates intermediate tables if missing. |
| `DataService.WaitForData(player)` | Yields until `profiles[player]` exists. |
| `DataService.OnDataLoaded(callback)` | Connect a callback that fires when each player's profile finishes loading. |
| `DataService.OnBeforeSave(callback)` | Append a callback that runs before every ProfileStore save (including the leaving-player final save). |
| `DataService.OnProfileSave(callback)` | Append a callback that runs INSIDE the `profile.OnSave` connection. |

The leaving-race fallback fixes a real bug: `OnPlayerRemoving` clears `playerReplicas[player]` BEFORE `profile:EndSession()` runs. If a `Set` fires during that window, the replica path returns false silently. The fallback writes directly to `profile.Data` so the value is included in the next ProfileStore save.

---

## RemoteConfigHandler — bridge from Roblox ConfigService to a workspace attribute

`src/Server/Server/Modules/RemoteConfigHandler.luau` reads a Roblox Creator Hub Config (via `ConfigService:GetConfigAsync()`) and mirrors the value into a `workspace:SetAttribute(name, value)` so clients can read it (Roblox auto-replicates Workspace attributes).

Pattern:
1. Sets a synchronous default (`false`) immediately on Initialize
2. `task.spawn`s the async ConfigService fetch
3. Connects `snapshot.UpdateAvailable` to refresh on live config flips from the dashboard
4. All ConfigService calls are wrapped in `pcall` (defensive against network errors / older Studio versions)

Use this pattern for any value you want to flip from outside the game without republishing (e.g., A/B test toggles, holiday event flags, kill-switches).

---

## Limitations & Gotchas

### Critical (NEVER violate — see Critical Bans above)
- DataStore key never rename
- Replica API: OnChange not ListenToChange, DataService wraps both sides

### Info
- `$className` and `$path` cannot be on the same node in `default.project.json`
- Two-way sync off by default in Argon — enable in the Argon plugin settings inside Studio
- `sourcemap.json` is gitignored — regenerate with `argon sourcemap --output sourcemap.json` after adding new scripts
- ProfileStore is server-only — never require it from a client script
- Mad Studio Replica's server module (`ReplicatedStorage` ... actually `ServerScriptService.ReplicaServer`) is server-only; clients require `ReplicatedStorage.ReplicaClient` instead
- `Trove` from Wally is installed only as a UIAnimator internal dependency — never use it directly. Use `Janitor` instead.

### Luau "Ambiguous syntax" parser trap

Luau errors with `Ambiguous syntax: this looks like an argument list for a function call, but could also be a start of new statement` when a line begins with `(` or `[` and the previous line ended with a function call. The parser interprets the new line as a continuation call/index of the previous expression.

```lua
-- BAD — parsed as `pcall(function() ... end)(usernameLabel :: TextLabel).Text = ...`
local nameOk, nameResult = pcall(function()
    return Players:GetNameFromUserIdAsync(uid)
end)
(usernameLabel :: TextLabel).Text = "@" .. nameResult
```

Two fixes — prefer the second:

```lua
-- OK — leading semicolon terminates the prior statement
end)
;(usernameLabel :: TextLabel).Text = "@" .. nameResult
```

```lua
-- BETTER — bind to a local first; the parenthesised cast is gone entirely
local usernameText = usernameLabel :: TextLabel
usernameText.Text = "@" .. nameResult
```

Same trap fires for table indexing — `[1] = ...` after a function call. Same fix: bind to a local. The pattern is especially common right after a `pcall(function() ... end)` block followed by a typed cast (`(x :: T).Field = ...`). Audit any such snippet before committing.

### Luau "Expected identifier, got '{'" — inline type annotation on table-field assignment

Luau does NOT support type annotations on table-field assignments. The parser sees `Table.field:` as the start of a method-call (`Table.field:methodName(...)`) and errors with `Expected identifier when parsing method name, got '{'` on the next character.

```lua
-- BAD — parsed as the start of a method call `Module._runs:{...}(...)`
Module._runs: { [Player]: RunState } = {}
Module._owner: { [Model]: number }   = {}
```

Two fixes — prefer the first:

```lua
-- OK — cast the rvalue; annotation lives on the right of `=`
Module._runs   = {} :: { [Player]: RunState }
Module._owner  = {} :: { [Model]: number }
```

```lua
-- OR — declare types separately at the top of the file and assign untyped
export type RunsMap = { [Player]: RunState }
Module._runs = {}  -- inferred from later writes, or explicitly typed via the module's `type Module = ...` block
```

Annotations are only legal on **local variable declarations** (`local x: T = ...`), **function parameters/returns**, and **type aliases** — never on `Table.field = value` lines. Same applies to `script.Parent.Foo:` and `self.Bar:` left-of-equals positions.

### Luau "Expected identifier, got ';'" — orphan leading `;` inside a function body

The leading-`;` fix for the ambiguous-syntax trap above is **only valid at file/block scope** where it terminates a real preceding statement. Inside a function body that only contains the one statement, the `;` has nothing to terminate and is a parse error.

```lua
-- BAD — inside a pcall'd function, the leading `;` is unparseable
pcall(function()
    ;(inst :: any)[snap.prop] = snap.value
end)
```

```lua
-- OK — bind the typed cast to a local OUTSIDE the function, then index it inside
local target = inst :: any
pcall(function()
    target[snap.prop] = snap.value
end)
```

Rule of thumb: if the function body is one statement, never start it with `;`. The ambiguous-syntax workaround belongs at outer scope, not inside a single-statement callback.

### Luau "Expected identifier when parsing expression, got ']'" — nested block comments

Luau block comments (`--[[ ... ]]`) **do not nest**. The first `]]` (or `--]]`) closes the outer block — any subsequent `]]` becomes orphan code and the parser errors at it. Cascades into `Requested module experienced an error while loading` → Knit boot failure. `argon sourcemap` does not detect it.

```luau
-- BREAKS — outer `--[[` (line 1) is closed by the FIRST `--]]` (line 4).
-- The `]]` on line 5 is orphan → parse error.
--[[
    Example:
    --[[ HoverBob = function(...) ... end, --]]
]]
```

**Fix** — use the long-form bracket count (`--[==[ ... ]==]`) on the outer comment. Any text containing `--[[` or `]]` becomes safe content inside it:

```luau
--[==[
    Example:
    --[[ HoverBob = function(...) ... end, --]]
]==]
```

Use `=` count as needed (`--[===[ ... ]===]` etc.) if the inner content also contains `]==]`. Most docstrings only need one level beyond default.

This bites hardest when authoring docstrings that embed a code example using block comments — the embedded example's `--]]` closes the outer docstring. The fix is mechanical; prefer long-form for any docstring that includes block-comment markers in its example code.

---

## How to add a new handler (cookbook)

1. Create `src/Server/Server/Modules/MyHandler.luau`:
   ```lua
   local Players = game:GetService("Players")
   local ReplicatedStorage = game:GetService("ReplicatedStorage")
   local ServerStorage = game:GetService("ServerStorage")

   local Bridges = require(ReplicatedStorage.Shared.Bridges)
   local DataService = require(ServerStorage.ServerUtilities.DataService)

   local MyHandler = {}

   local lock: { [number]: boolean } = {}

   function MyHandler:Initialize()
       Bridges.SomeBridge:Connect(function(player, data)
           local uid = player.UserId
           if lock[uid] then return end
           lock[uid] = true
           task.spawn(function()
               local ok, err = pcall(function()
                   -- mutating logic here
                   local current = DataService.Get(player, "myField") or 0
                   DataService.Set(player, "myField", current + 1)
               end)
               lock[uid] = nil
               if not ok then warn("[MyHandler]", err) end
           end)
       end)

       Players.PlayerRemoving:Connect(function(player)
           lock[player.UserId] = nil
       end)
   end

   return MyHandler
   ```
2. Register in `src/Server/Server/Services/GameService.luau`:
   - Add `self._MyHandler = require(script.Parent.Parent.Modules.MyHandler)` to `KnitInit`
   - Add `self._MyHandler:Initialize()` to `KnitStart`
3. Spawn `bug-investigator` to review the new file once you've written non-trivial logic.
