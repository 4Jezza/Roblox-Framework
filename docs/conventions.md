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

The boilerplate uses **loleris ReplicaService** (Wally) wrapped by `DataService.luau`.

### Server
Use the `DataService` wrapper. Never call `ReplicaService.NewReplica` directly outside `DataService.luau`.

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
Use `PlayerData` + `replica:OnChange()`. Never call `ListenToChange()` — it doesn't exist.

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
