# Knit Boilerplate

An opinionated Roblox game starter built around **Knit**, **ProfileStore**, **ReplicaService**, **BridgeNet2**, **ExpressivePrompts**, and **UIAnimator (Twinkle)**. The architecture, file layout, naming conventions, agent automation, and platform infrastructure are extracted from a production game so a new project can pick them up wholesale.

The boilerplate ships with **only platform pieces** — there is no gameplay. Add your game's handlers under `src/Server/Server/Modules/` and your client modules under `src/Client/Client/Modules/`, following the conventions established by the existing stubs.

---

## Stack

| Layer | Library | Purpose |
|---|---|---|
| Service framework | **Knit** (`sleitnick/knit`) | Server services + client controllers, KnitInit/KnitStart lifecycle |
| Networking | **BridgeNet2** (`ffrostflame/bridgenet2`) | All client↔server remotes through one central registry (`Shared/Bridges.luau`) |
| Persistent data | **ProfileStore** (`lm-loleris/profilestore`) | Session-locked DataStore with reconcile + leaving-race fallback |
| State replication | **ReplicaService** (`lm-loleris/replicaservice`) | Reactive server-side state, mirrored to clients |
| Cleanup | **Janitor** (`howmanysmall/janitor`) | Connection lifecycle management |
| Events | **Signal** (`sleitnick/signal`) | Module-internal events |
| Animation | **UIAnimator** (Twinkle) — vendored | Default UI animation library (FrameZoom, Hover/Press/Text presets) |
| 3D animation | **Spring** (`sleitnick/spring`) | Spring-based 3D motion (parts, scale, highlights) — preferred over TweenService |
| Proximity prompts | **ExpressivePrompts** (`miagobble/expressive-prompts`) | Replaces default Roblox proximity prompt UI |
| UI effects | **EZVisualz** (`eztolauz/ezvisualz`) | UIGradient/UIStroke animation effects |
| Region detection | **ZonePlus** (`ego-moosey/zoneplus`) | Trigger volumes |
| Topbar icons | **TopbarPlus** (`1ferret/topbarplus`) | Topbar buttons + dropdowns |
| Tooling | **selene**, **stylua**, **luau-lsp** | Lint, format, type-check |
| Sync | **Argon** | Studio ↔ filesystem two-way sync via `default.project.json` |

---

## Quick start

### Prerequisites
- [Wally](https://github.com/UpliftGames/wally/releases) (Lua package manager)
- [Argon](https://argon.wiki/) (Studio sync)
- [VS Code](https://code.visualstudio.com/) with `JohnnyMorganz.luau-lsp` and `JohnnyMorganz.stylua`

### Install
```bash
wally install
argon serve
```

Open the place file in Studio, click **Argon → Connect**, and press **Test → Play**. You should see in the Output window:
```
[Server] Knit started
[Client] Knit started
```

If both prints appear, the boilerplate is wired correctly. You can now add your first handler / client module / bridge.

---

## Project structure

```
knit-boilerplate/
├── default.project.json           ← Argon mapping (folder → DataModel)
├── wally.toml                     ← package dependencies
├── selene.toml                    ← linter
├── stylua.toml                    ← formatter
├── .luaurc                        ← Luau strict mode + path aliases
├── .gitignore                     ← ignores Packages/, src/Server/Server/Packages/, sourcemap.json
│
├── CLAUDE.md                      ← orchestrator rules + agent routing for Claude Code
├── README.md                      ← (this file)
│
├── .claude/
│   ├── agents/                    ← 12 domain agent definitions (server-handler, ui-controller, etc.)
│   ├── reference/architecture.md  ← canonical architecture reference for agents
│   └── settings.json              ← Claude Code project settings (permissions)
│
├── docs/
│   ├── architecture.md            ← human-readable architecture overview
│   ├── cookbook.md                ← step-by-step recipes for common tasks
│   ├── conventions.md             ← style guide
│   └── repo-map.md                ← folder-by-folder repo map
│
├── src/
│   ├── Client/Client/
│   │   ├── init.client.luau       ← Knit client boot
│   │   ├── Controllers/
│   │   │   ├── GameController.luau     ← requires + initializes all client modules
│   │   │   └── ProximityController.luau ← initializes ExpressivePrompts
│   │   └── Modules/
│   │       ├── UIClient.luau           ← OpenFrame/CloseFrame, GetFrame, QuickPlay loop
│   │       ├── NotificationClient.luau ← Show/Success/Error/Tutorial helpers
│   │       └── ChatClient.luau         ← TextChatService customization stub
│   │
│   ├── Server/
│   │   ├── ReplicaServer.luau     ← thin re-export of loleris ReplicaService
│   │   └── Server/
│   │       ├── init.server.luau   ← Knit server boot
│   │       ├── Services/
│   │       │   └── GameService.luau    ← requires + initializes all handlers
│   │       └── Modules/
│   │           ├── DataHandler.luau         ← creates leaderstats, OnDataLoaded
│   │           ├── ProductHandler.luau      ← MarketplaceService.ProcessReceipt
│   │           ├── RemoteConfigHandler.luau ← Roblox ConfigService → workspace attribute
│   │           ├── AnalyticsHandler.luau    ← analytics SDK wrapper stub
│   │           ├── InventoryHandler.luau    ← player inventory mutation stub
│   │           └── AdminHandler.luau        ← admin command dispatcher stub
│   │
│   ├── ServerStorage/
│   │   └── ServerUtilities/
│   │       ├── DataService.luau   ← ProfileStore + ReplicaService wrapper
│   │       ├── SignalBank.luau    ← cross-handler signal hub
│   │       └── ServerUtilities.luau ← misc helpers
│   │
│   ├── Shared/
│   │   ├── Shared/
│   │   │   ├── Bridges.luau       ← central BridgeNet2 registry (Notify, OpenContainer, AdminCommand)
│   │   │   └── Types.luau         ← Luau type exports
│   │   ├── DataModules/
│   │   │   └── ProductConfig.luau ← dev product IDs + A/B test getter (GetActiveMainProductId)
│   │   └── Utility/
│   │       ├── PlayerData.luau    ← client-side ReplicaController wrapper
│   │       ├── Format.luau        ← cash/number/duration formatting
│   │       ├── Janitor.luau       ← re-export of Wally Janitor
│   │       └── Spring.luau        ← re-export of Wally Spring
│   │
│   └── _archive/                  ← deprecated scaffolds (StarterGui, Workspace-Map); see below
│
filestructure/                     ← MD snapshots of in-Studio asset trees
├── starter-gui.md                 ← StarterGui.Ui.Frames tree
├── workspace.md
├── replicated-storage-assets.md
└── server-storage-assets.md
```

> **Assets live in-Studio, not in `src/`.** StarterGui, Workspace, `ReplicatedStorage.Assets`, and `ServerStorage.Assets` are Argon-excluded — you build them in Studio and reference them via Roblox MCP (`mcp__Roblox_Studio__search_game_tree` / `inspect_instance`). Snapshots live in `filestructure/*.md`. Scripts stay on Argon. See `CLAUDE.md` rules 12-14 and `.claude/reference/asset-discovery.md`.

---

## Cookbook

### Adding a new server handler
1. Create `src/Server/Server/Modules/MyHandler.luau` with the same shape as the existing stubs (DataHandler, ProductHandler, etc.)
2. Add `self._MyHandler = require(script.Parent.Parent.Modules.MyHandler)` to `GameService:KnitInit`
3. Add `self._MyHandler:Initialize()` to `GameService:KnitStart`
4. Inside `Initialize()`, connect to `Bridges.X:Connect(...)` for any client→server messages, wrap mutating bodies in `task.spawn` with the per-player mutex pattern
5. Use `DataService.Get/Set` for any persistent state

### Adding a new client module
1. Create `src/Client/Client/Modules/MyClient.luau`
2. Add `self._MyClient = require(script.Parent.Parent.Modules.MyClient)` to `GameController:KnitInit`
3. Add `self._MyClient:Initialize()` to `GameController:KnitStart`
4. Use `Bridges.X:Fire(...)` for client→server messages and `Bridges.X:Connect(...)` for server→client
5. Use `PlayerData.GetData()` / `PlayerData.OnReady()` for replicated player state

### Adding a new bridge
1. Open `src/Shared/Shared/Bridges.luau`
2. Declare a new local: `local MyBridge = BridgeNet2.ReferenceBridge("MyBridge")`
3. Add it under the appropriate `-- CLIENT → SERVER` or `-- SERVER → CLIENT` section
4. Export it in the return table at the bottom: `MyBridge = MyBridge,`

### Adding a new persistent data field
1. Open `src/ServerStorage/ServerUtilities/DataService.luau`
2. Add the field to `DATA_TEMPLATE` with a sensible default
3. ProfileStore's `Reconcile()` will automatically add the field to existing player profiles on next load
4. Read with `DataService.Get(player, "myField")`, write with `DataService.Set(player, "myField", value)`

### Adding a new dev product
1. Create the product on the [Roblox Creator Hub](https://create.roblox.com/) → Monetization → Developer Products
2. Add the product ID to `src/Shared/DataModules/ProductConfig.luau`
3. Add a receipt branch in `src/Server/Server/Modules/ProductHandler.luau` with the dual-ID recognition pattern (so A/B variants both grant correctly)
4. Wire the purchase prompt in your client UI: `MarketplaceService:PromptProductPurchase(LocalPlayer, ProductConfig.MyProduct)`

### A/B testing values from the Creator Hub
1. Create a Config in Creator Hub → Configs (key: `Uses_Cheap_Main_Product`, type: boolean)
2. The boilerplate's `RemoteConfigHandler.luau` already bridges this config into a workspace attribute of the same name
3. `ProductConfig.GetActiveMainProductId()` reads the workspace attribute and returns either the main or alt product ID
4. To add more configs, edit `RemoteConfigHandler.luau` and add another `applyConfig` call for the new key

### Hiding a UI button when any frame is open
The boilerplate's `UIClient.updateQuickPlayVisibility()` already iterates `ui.Frames` and hides a designated button when any frame is visible. Wire your hide-on-frame-open button by uncommenting the `quickPlayBtn` reference in `UIClient.luau` and pointing it at your button instance.

### Granting a tool to the player
Inside a server handler, after a successful purchase or grant:
```lua
InventoryHandler.AddItem(player, "MyTool")
local backpack = player:FindFirstChild("Backpack")
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
if backpack and humanoid then
    -- create tool, parent to backpack, then equip
    humanoid:EquipTool(tool)
end
```

---

## `.claude/` automation

This boilerplate ships with a multi-agent Claude Code workflow:

- **`CLAUDE.md`** — orchestrator rules. Behavioral checklist + agent routing table + STOP-CHECK pattern.
- **`.claude/agents/`** — 12 domain specialists (server-handler, client-controller, networking-specialist, ui-controller, animation-vfx, sound-specialist, replication-specialist, janitor-lifecycle, config-balancer, bug-investigator, architecture-reviewer, game-knowledge). The orchestrator routes work to the right specialist based on which domain the task touches.
- **`.claude/reference/architecture.md`** — single source of truth for require paths, folder mappings, and gotchas. Agents read this before writing code.
- **`.claude/settings.json`** — Claude Code project permissions (intentionally minimal — add hooks under `.claude/helpers/` if you want pre/post-tool automation).

The pattern: when you give Claude Code a task, it spawns specialized agents in parallel rather than writing code directly. After all agents return, a `bug-investigator` reviews the diff in a loop until clean. This keeps each agent's context narrow and makes large multi-file features reliable.

---

## Key rules (TL;DR)

| Rule | Detail |
|---|---|
| KnitInit | State setup only — no cross-service calls |
| KnitStart | All services ready — inter-service calls go here |
| BridgeNet2 | Single table arg always: `Bridge:Fire({ key = val })` |
| ProfileStore key | **Never rename** (`BoilerplateData_LIVE_1` is the placeholder — set your own immutable key when you fork) |
| Profile.Data | No Instances, no Vector3/CFrame/Color3 — serialize to primitives |
| Marketplace | Always server-authoritative via `MarketplaceService.ProcessReceipt`. Never grant on client `PromptProductPurchaseFinished`. |
| Per-player mutex | Required on bridge handlers that mutate data |
| No yield in bridge | Wrap bodies in `task.spawn` |
| Per-player table cleanup | Required in `Players.PlayerRemoving` |
| Replica API | `replica:OnChange()` on the client, NOT `ListenToChange()` |
| Springs over TweenService | For 3D animations (part movement, scale, highlights) |
| UIAnimator over TweenService | For UI transitions |
| Pract | Banned. The Wally version of Pract is not installed. |
| `local X = X or default` | Don't — reads an undefined global. Use `Config.Field or default` instead. |

See `docs/conventions.md` for the full style guide.

---

## License

MIT — see `wally.toml` for the package metadata. Adapt freely for your own project.
