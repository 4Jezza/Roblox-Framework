# Conventions

Style guide for code in this boilerplate. Agents reference this file when writing new code. Keep it short — long style guides rot. Add rules as you discover patterns.

---

## File naming

| Suffix           | Purpose                                     | Example                          |
|------------------|---------------------------------------------|----------------------------------|
| `*Handler.luau`  | Server module under `Server/Modules/`       | `DataHandler.luau`               |
| `*Service.luau`  | Knit service under `Server/Services/`       | `GameService.luau`               |
| `*Client.luau`   | Client module under `Client/Modules/`       | `UIClient.luau`                  |
| `*Controller.luau` | Knit controller under `Client/Controllers/` | `GameController.luau`          |
| `*Config.luau`   | Data table under `Shared/DataModules/`      | `ProductConfig.luau`             |

One concern per file. PascalCase names. Keep folder depth shallow (max 2-3 levels inside `src/`).

---

## Indentation

Tabs in Luau files. 4 spaces in JSON (`default.project.json`, `.luaurc`, `init.meta.json`). Configured in `stylua.toml`.

Do NOT mix tabs and spaces in the same file.

---

## Module file structure (canonical layout — every `.luau` follows this)

```luau
--[[
	ModuleName
	----------
	One-paragraph description: purpose, key contracts, gotchas.
	Wrap lines around ~80 chars.

	(Optional) Public API:
	  Mod.Foo(x) → R
	  Mod:Bar()  → R

	(Optional) TODOs.
]]

local Service1 = game:GetService("Service1")
local Service2 = game:GetService("Service2")

local Package1 = require(game.ReplicatedStorage.Packages.Pkg1)
local Sibling  = require(script.Parent.Sibling)

local ModuleName = {}                                -- plain module
-- OR
local ModuleName = Knit.CreateController {           -- Knit controller / service
	Name = "ModuleName",
}

-- ---------------------------------------------------------------------------
-- Constants / state
-- ---------------------------------------------------------------------------

local CONSTANT = 5
local stateTable: {[number]: boolean} = {}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

local function privateHelper() end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ModuleName.Foo(x: T): R end                 -- dot for free functions
function ModuleName:Bar() end                        -- colon for methods that take self

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function ModuleName:Initialize() end                 -- plain modules (called by GameController)
-- OR
function ModuleName:KnitInit() end                   -- Knit controllers/services
function ModuleName:KnitStart() end

return ModuleName
```

Hard rules:
- **Header opens with `--[[`**, body is **tab-indented**, closes with **bare `]]`** (no `--` prefix). Use `--[==[ ... ]==]` only when the body contains nested `--[[`/`]]` markers (Luau block comments don't nest — see `.claude/reference/architecture.md` § Luau "Expected identifier ... got ']'").
- **Section dividers** are a long dash line: `-- ---------------------------------------------------------------------------`, followed by the section label on the next line. Never use `========` dividers.
- **`Knit.CreateController { ... }`** — brace style, no surrounding parens. Same for `CreateService`.
- **`warn("[Module] missing <what> at <where> — <recovery>")`** — string format, not comma-separated args, with the `[Module]` or `[Module/Sub]` prefix.
- **Declaration order** matches the template above; never interleave constants between functions.
- Module-as-folder children (rule_16) follow the same template — the `init.luau` is the parent module.

---

## Naming within files

- Module tables: `PascalCase`. Export with `return ModuleName`.
- Local functions: `camelCase` for private helpers, `PascalCase` for public methods on the module table.
- Constants (magic numbers, product IDs, DataStore keys): `UPPER_SNAKE_CASE` as module-level `local`.
- Bridge names: `PascalCase` verb-first — `OpenContainer`, `ClaimReward`, `Notify`.
- Attribute names on Instances: `PascalCase` — `PlotNumber`, `SlotNum`, `BackgroundColor`. Exception: Roblox Config keys use `snake_case` matching the Creator Hub convention.
- Signal names (SignalBank): `PascalCase` past-tense — `PlayerJoined`, `DataLoaded`, `GameEnded`.

---

## `Format` helpers over inline formatting

Use `Format.cash(1234567)` → `"$1.23M"`, `Format.duration(90)` → `"1m 30s"`, etc. Never write inline string concatenation for user-facing numbers. See `src/Shared/Utility/Format.luau` for the full API.

---

## Per-player mutex pattern (MANDATORY on mutating bridges)

Every bridge listener that mutates player data needs this:

```lua
local lock: { [number]: boolean } = {}

Bridges.MyBridge:Connect(function(player, data)
    local uid = player.UserId
    if lock[uid] then return end       -- gate OUTSIDE task.spawn
    lock[uid] = true

    task.spawn(function()              -- body INSIDE task.spawn (no yield in bridge dispatch)
        local ok, err = pcall(function()
            -- mutation (DataService.Set etc.)
        end)
        lock[uid] = nil                -- release INSIDE task.spawn, after pcall
        if not ok then warn("[MyHandler]", err) end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    lock[player.UserId] = nil          -- mandatory cleanup
end)
```

Why each piece:
- **Gate outside spawn**: so rapid re-fires are rejected synchronously before the async body kicks off
- **Body inside spawn**: because `DataService.Set` yields (ProfileStore) and bridge callbacks must not yield the dispatch loop
- **Release inside spawn, after pcall**: so the lock stays held throughout the async work
- **PlayerRemoving cleanup**: otherwise the `lock` table grows unbounded across sessions → memory leak

---

## Animation rules

- **UI transitions** → `UIAnimator` (Twinkle). Never raw `TweenService` for UI.
- **3D animations** (part movement, scale, highlights) → `Spring` (Wally). TweenService is only acceptable for one-shot fire-and-forget cases where spring polling would be wasteful (e.g. a single transparency fade on a temporary instance).
- **UI effects** (animated gradients, strokes) → `EZVisualz` (client-only — uses RunService.Heartbeat). Always destroy existing `UIStroke`/`UIGradient` before applying EZVisualz to avoid conflicts.

---

## Sound paths

At runtime, sounds live under `SoundService.SFX.<name>`, `SoundService.Music.<name>`, or `SoundService.Events.<name>` — never as direct children of `SoundService`.

```lua
local SoundService = game:GetService("SoundService")
local sfx = SoundService:FindFirstChild("SFX")
local mySound = sfx and sfx:FindFirstChild("MySound")
if mySound then mySound:Play() end
```

Always use `FindFirstChild` (nil-safe) — never `WaitForChild` at module require time, which can hang forever if the asset is missing.

---

## Defensive patterns

### `pcall` around external service calls

Always wrap these in `pcall`:
- `MarketplaceService:PromptProductPurchase` / `ProcessReceipt`
- `ProfileStore` async calls (`StartSessionAsync`, `:EndSession`)
- `ConfigService:GetConfigAsync` and `snapshot:GetValue`
- `HttpService` calls
- Any `UserService` / `GroupService` / `LocalizationService` call that hits the network

### Capture state into locals BEFORE `task.delay` callbacks

```lua
-- BAD — slotNum may be nil by the time the delay fires
task.delay(2, function()
    slotHandler.RefreshSlot(slotNum)
end)

-- GOOD — capture the value NOW
local capturedSlotNum = slotNum
task.delay(2, function()
    slotHandler.RefreshSlot(capturedSlotNum)
end)
```

Module/table state can change during the delay — always capture what you need into a local first.

### Never use `local X = X or default`

```lua
-- BAD — reads an undefined global, always nil → always default
local multiplier = multiplier or 1

-- GOOD — read from a config module
local multiplier = EconomyConfig.Multiplier or 1
```

---

## Replica API

The boilerplate uses **Mad Studio Replica** (vendored, NOT a Wally package — see `.claude/reference/api-reference.md` § 2.2-2.4) wrapped by `DataService.luau`.

### Server
Use the `DataService` wrapper. Never call `Replica.New` directly outside `DataService.luau`.

```lua
-- Read
local cash = DataService.Get(player, "cash")
-- Write
DataService.Set(player, "cash", cash + 100)
-- Read-modify-write
DataService.Update(player, "cash", function(old) return (old or 0) + 100 end)
-- Nested write
DataService.SetPath(player, { "inventory", "coins" }, 50)
```

### Client
Use `PlayerData` + `replica:OnSet(path, fn)` for specific paths or `replica:OnChange(fn)` for catch-all. Never call `ListenToChange()` — it doesn't exist on Mad Studio Replica.

```lua
local PlayerData = require(game.ReplicatedStorage.Utility.PlayerData)

PlayerData.OnReady(function()
    local data = PlayerData.GetData()
    -- initial render
end)

PlayerData.OnSet({ "cash" }, function(newValue)
    -- live update
end)
```

---

## Ban list

| Ban | Why |
|---|---|
| **Pract** | Declarative UI reconciler — not installed. Use native `Frame`/`TextLabel` + UIAnimator. |
| **Raw `TweenService` for UI** | Use `UIAnimator` (Twinkle) instead. Consistent styling + Spring-based feel. |
| **Raw `TweenService` for 3D animations** | Use `Spring` (Wally) — natural, bouncy motion that's cheaper in some cases than tweens. |
| **`WaitForChild` at module require time** | Can hang the whole script. Use `FindFirstChild` with nil guards. |
| **`ListenToChange`** | Not part of loleris ReplicaController API. Use `OnChange()` instead. |
| **`local X = X or default`** | Reads an undefined global (always nil). Use `Config.Field or default`. |
| **`Trove` (RbxUtil)** | Installed only as a UIAnimator internal dep. Use `Janitor` instead. |
| **Yielding inside a BridgeNet2 `:Connect` callback** | Blocks the bridge dispatch loop. Wrap in `task.spawn`. |
| **Creating tools in `OnDataLoaded`** | `LoadCharacter()` runs after and destroys the Backpack. Defer to `CharacterAdded`. |
| **Renaming the DataStore key** | Wipes all player data. Never. |

---

## Currency labels

Every `TextLabel` that displays a changing number (currency, score, count, balance, timer, level, etc.) MUST be driven through one of the project `UIAnimator` bindings. Raw `label.Text = tostring(n)` for changing values is forbidden — it bypasses both the number spring and `Format`. See `.claude/reference/architecture.md § Client-visible numbers` and `.claude/reference/api-reference.md § Project — UIAnimator`.

```lua
local UIAnimator = Knit.GetController("UIAnimator")

-- (a) Pure getter — for client-only / computed values
UIAnimator:BindNumberLabel(label, function() return localScore end)

-- (b) Local player's replica path — auto-resubscribes via PlayerData
UIAnimator:BindPlayerDataNumber(label, { "cash" })

-- (c) Arbitrary world replica path — BillboardGui labels on WorldEntity replicas
UIAnimator:BindReplicaNumber(label, replica, { "points" })
```

All three accept `opts = { format = "suffix" | "commas" | function, prefix, suffix, springSpeed, springDamper }`. Format defaults to `Format.Suffix`. Static one-off numbers (rendered once, never updated) may use `label.Text = Format.Suffix(n)` directly.

---

## Mobile orientation

The project `UIAnimator` Knit controller force-applies `Enum.ScreenOrientation.LandscapeRight` on detected mobile devices at `KnitStart` (after a 1-second settle). This is global to every game built on the framework — there is no per-game toggle. See `.claude/reference/architecture.md § Mobile force-landscape`.

```lua
-- Opt out: edit src/Client/Client/Controllers/UIAnimator/init.luau and remove
-- (or guard) the orientation block in :KnitStart. Don't try to override from
-- a sibling controller — UIAnimator's task.wait(1) will clobber your write.
```

---

## Gamepasses-as-dev-products

This framework does NOT use Roblox gamepasses for purchasable benefits. "Gamepass-like" benefits are modelled as **developer products** whose `Reward(player)` writes to a PlayerData ownership table (e.g. `PlayerData.ownedPasses[passKey] = true`). Runtime checks read that table — never `MarketplaceService:UserOwnsGamePassAsync`. This unlocks gifting via the existing `Bridges.GiftPurchase` flow (gamepasses cannot be gifted by Roblox; dev products can).

```lua
-- ProductConfig.luau
[1234567] = {
    Name = "VIP",
    Reward = function(player)
        DataService.SetPath(player, { "ownedPasses", "VIP" }, true)
    end,
},

-- Anywhere a check is needed:
local owned = DataService.Get(player, "ownedPasses") or {}
if owned.VIP then ... end
```

---

## Playground convention

Test surfaces use a leading underscore (`_PlaygroundHandler`, `_Playground/`, etc.) to mark them as autoremovable. Removal at fork time is mechanical:

```bash
rm -rf src/Server/Server/Modules/_PlaygroundHandler.luau
rm -rf src/Client/Client/Controllers/_Playground/
# Then delete the two `__PlaygroundHandler` lines in GameService.
```

The double-underscore field name on `GameService` (`self.__PlaygroundHandler`) is a stylistic marker that the registration line is removable as a unit — no `Initialize` call elsewhere references it. Don't use `__`-prefixed fields for anything else.

---

## Notifications

Use the project `UIAnimator` Knit controller's notification helpers — never clone the notification templates manually, never build a bespoke notification frame. Templates live at `PlayerGui.Ui.HUD.Notification.<TemplateName>` (hidden at boot); the four template names are `Default`, `Error`, `Tutorial`, and `Special`. Default sound: `SoundService.SFX.UI.Notification`. See `.claude/reference/architecture.md § Notifications` and `.claude/reference/api-reference.md § Project — UIAnimator`.

```lua
local UIAnimator = Knit.GetController("UIAnimator")
UIAnimator:Notify("Reward claimed")
UIAnimator:NotifyError("Not enough cash")
UIAnimator:NotifyTutorial("Hold E to grab")
UIAnimator:NotifySpecial("Boss defeated!")
```

`NotificationClient.Show` / `.Success` / `.Error` / `.ShowTutorial` remain as thin backwards-compatible wrappers that delegate to the above. New code should call `UIAnimator:Notify*` directly.

---

## Sound playback

Use the `SoundController` Knit controller — never `Sound:Play()` directly, never `:Clone()` a Sound instance by hand. The controller owns pooling, category volume mixing, dotted-path name resolution (`"UI.Hover"` → `SoundService.SFX.UI.Hover`), and the layered/counting presets. See `.claude/reference/architecture.md § Sound playback` and `.claude/reference/api-reference.md § Project — SoundController`.

```lua
local Sound = Knit.GetController("SoundController")
Sound:Play("UI.Hover")
Sound:Play("SFX.Coin", { volume = 0.6, pitch = 1.1 })
```
