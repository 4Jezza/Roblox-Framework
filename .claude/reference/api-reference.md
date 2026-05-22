# API Reference — Packages

> Single-stop reference for every package available in the project. Read this file before calling any library API — signatures here come straight from the package source. If a method isn't in this file, treat it as **not part of the public API** until you've re-verified it in source.

This file is the **gotcha collector**. Add any version mismatch, API quirk, or anti-pattern you discover under the affected package.

---

## Conventions used in this file

- Require paths point at the public `Packages/<Name>.lua` thunk (or the vendored path for non-Wally libs). They are written for the **client require root** (`ReplicatedStorage.Packages`) unless flagged `(server-only)`.
- "Source" gives the underlying file you should read when this doc is ambiguous. The code wins over this doc; if you find a discrepancy, fix this doc.
- Method tables use the form `Class:Method` for colon-call (passes `self` implicitly) and `Class.Func` for dot-call.
- Signatures show parameter names + types and the return type. `?` means optional. `...` means tuple/varargs.
- `[banned]` next to a method means it exists but is forbidden by project rules (see CLAUDE.md).

---

## File Authoring Rules (apply to EVERY `.luau` / `.lua` edit)

### Encoding: UTF-8 **without BOM**

Luau's parser rejects a leading UTF-8 BOM (bytes `EF BB BF`) with:
```
ReplicatedStorage.Shared.<X>:1: Expected identifier when parsing expression, got Unicode character U+feff
Requested module experienced an error while loading
```
The error cascades into `Knit.Start():catch` Promise rejection. `argon sourcemap` does NOT detect it.

**Forbidden tooling** (Windows): `Set-Content -Encoding UTF8`, `Out-File -Encoding UTF8` in PowerShell 5.1 — both write WITH BOM silently.

**Safe tooling**: Claude Code's Edit / Write tools; `Set-Content -Encoding ASCII` (ASCII-only content); explicit `$utf8NoBom = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)`; PowerShell 7+ `-Encoding utf8NoBOM`.

**BOM sweep** — run after any bulk-write tool:
```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
Get-ChildItem -Recurse -Include *.luau,*.lua -File src/ | ForEach-Object {
    $b = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        [System.IO.File]::WriteAllBytes($_.FullName, $b[3..($b.Length-1)])
        Write-Output "stripped: $($_.FullName)"
    }
}
```

After bulk edits: BOM sweep → `argon sourcemap` → open Studio and confirm console is clean.

### Luau Parser Pitfalls

Luau is statement-terminator-free (no required `;`). The parser greedily merges across lines when a line starts with a token that COULD be a continuation. Three patterns reliably bite:

**1. Ambiguous syntax: leading `(` after an expression-value line.**

```luau
-- BREAKS — parser reads `looped(track :: AnimationTrack)` as a call,
-- then `.Priority = priority` is a parse error.
(track :: AnimationTrack).Looped   = looped
(track :: AnimationTrack).Priority = priority
```

Error: `Ambiguous syntax: this looks like an argument list for a function call, but could also be a start of new statement; use ';' to separate statements`. Cascades into `Requested module experienced an error while loading` → Knit boot failure (`Promise.Error(ExecutionError)` from `KnitServer.Start`). Not caught by `argon sourcemap`.

**Fix** — bind to a local; subsequent statements then start with an identifier, not `(`:

```luau
local t = track :: AnimationTrack
t.Looped   = looped
t.Priority = priority
```

Less-good alternative: explicit `;` at end of the prior line. Local-binding is cleaner because it also removes the repeated cast.

**2. Function call wrapped onto next line.**

```luau
-- BREAKS — `(otherFn)()` glues to `someValue`.
local x = someValue
(otherFn)()
```

**Fix** — explicit `;` after the expression, or one-line it.

**3. Method chaining starting with `(`.** Same root cause as case 1; same fix (local binding).

## Quick index

| Package              | Require path                                                       | Purpose |
|----------------------|---------------------------------------------------------------------|---------|
| Knit                 | `require(game.ReplicatedStorage.Packages.Knit)`                     | Service / Controller framework. Bootstraps shared code on both runtimes. |
| BridgeNet2           | `require(game.ReplicatedStorage.Packages.BridgeNet2)`               | Fast remote-event abstraction (use for ALL client-server messaging). |
| Loader               | `require(game.ReplicatedStorage.Packages.Loader)`                   | Bulk `require` of children/descendants. |
| ProfileStore         | `require(game.ServerScriptService.Server.Packages.ProfileStore)`    | Session-locked DataStore profiles. Server-only. Wrap via `DataService`. |
| ReplicaServer        | `require(game.ServerScriptService.Server.ReplicaServer)`            | Server-side replicated state. Server-only. Wrap via `DataService`. |
| ReplicaClient        | `require(game.ReplicatedStorage.ReplicaClient)`                     | Client-side replica observation. |
| ReplicaShared        | `require(game.ReplicatedStorage.ReplicaShared.<Module>)`            | Maid, Signal, Remote, RateLimit primitives used by Replica. |
| Janitor              | `require(game.ReplicatedStorage.Packages.Janitor)`                  | Cleanup container. Project default. |
| Signal               | `require(game.ReplicatedStorage.Packages.Signal)`                   | GoodSignal-based Signal class. |
| Trove                | `require(game.ReplicatedStorage.Packages.Trove)`                    | Cleanup container — used internally by UIAnimator. Prefer Janitor. |
| Promise (evaera)     | `require(game.ReplicatedStorage.Packages.Promise)` *(via Knit)*     | A+ promises. Used by Knit. |
| Concur               | `require(game.ReplicatedStorage.Packages.Concur)`                   | Thread / cooperative-task primitive. |
| TaskQueue            | `require(game.ReplicatedStorage.Packages.TaskQueue)`                | Batches objects, flushes once per Heartbeat. |
| Timer                | `require(game.ReplicatedStorage.Packages.Timer)`                    | Periodic Tick event. |
| WaitFor              | `require(game.ReplicatedStorage.Packages.WaitFor)`                  | Promise-returning child/descendant waiters. |
| Sift                 | `require(game.ReplicatedStorage.Packages.Sift)`                     | Immutable Array / Dictionary / Set helpers. |
| TableUtil            | `require(game.ReplicatedStorage.Packages.TableUtil)`                | Sleitnick table helpers (copy, reconcile, sync, etc). |
| Option               | `require(game.ReplicatedStorage.Packages.Option)`                   | Optional value monad. |
| Symbol               | `require(game.ReplicatedStorage.Packages.Symbol)`                   | Unique sentinel values for table keys. |
| EnumList             | `require(game.ReplicatedStorage.Packages.EnumList)`                 | Typed enum constructor. |
| Tree                 | `require(game.ReplicatedStorage.Packages.Tree)`                     | Path-style Instance lookup helper. |
| Ser                  | `require(game.ReplicatedStorage.Packages.Ser)`                      | Knit serialization for Option-like classes. |
| Spring (sleitnick)   | `require(game.ReplicatedStorage.Packages.Spring)`                   | Critically-damped spring (numbers/Vec/CFrame). |
| Shake                | `require(game.ReplicatedStorage.Packages.Shake)`                    | Perlin-noise shake generator (camera, parts). |
| Streamable           | `require(game.ReplicatedStorage.Packages.Streamable)`               | Observable wrapper for streaming-enabled instances. |
| UIAnimator (Twinkle) | `require(game.ReplicatedStorage.Client.Packages.UIAnimator)`        | UI animations. **Default** for all UI motion. Client-only. |
| UIUtil               | `require(game.ReplicatedStorage.Client.Packages.UIUtil)`            | `centerAnchor` helper. UIAnimator presets depend on it. |
| ExpressivePrompts    | `require(game.ReplicatedStorage.Packages.ExpressivePrompts)`        | Replacement ProximityPrompt UI. Project default. |
| TopbarPlus           | `require(game.ReplicatedStorage.Packages.TopbarPlus)`               | Topbar icons. |
| EZVisualz            | `require(game.ReplicatedStorage.Packages.EZVisualz)`                | UIGradient / UIStroke / Dropshadow presets. |
| Emitter2D            | `require(game.ReplicatedStorage.Client.Packages.Emitter2D)`         | 2D GUI particle emitter. Client-only. Plugin-driven. |
| ZonePlus             | `require(game.ReplicatedStorage.Packages.ZonePlus)`                 | Volumetric zone detection. |

> Asset roots, script require root rules, and other env wiring live in `architecture.md` — do not duplicate that here.

---

## 1. Networking & Service Framework

### 1.1 Knit

**Require:** `local Knit = require(game.ReplicatedStorage.Packages.Knit)`
**Source:** `Packages/_Index/sleitnick_knit@1.7.0/knit/{init,KnitServer,KnitClient}.lua`
**Wally:** `sleitnick/knit@1.7.0` (lockfile resolved past wally.toml's `1.5.1`)
**Purpose:** Service/Controller framework. Same require returns `KnitServer` on the server and `KnitClient` on the client.

**Server API (`KnitServer`):**

| Method | Signature | Description |
|---|---|---|
| `Knit.CreateService` | `(def: {Name: string, Client: table?, Middleware: Middleware?, [any]: any}) -> Service` | Register a service. Must run before `Knit.Start()`. |
| `Knit.AddServices` | `(parent: Instance) -> {Service}` | `require` every immediate `ModuleScript` child. |
| `Knit.AddServicesDeep` | `(parent: Instance) -> {Service}` | `require` every descendant ModuleScript. |
| `Knit.GetService` | `(name: string) -> Service` | Throws after `Start`. |
| `Knit.GetServices` | `() -> {[string]: Service}` | All registered services. |
| `Knit.CreateSignal` | `() -> Marker` | Use inside `Client` table to mark a RemoteSignal slot. |
| `Knit.CreateUnreliableSignal` | `() -> Marker` | UnreliableRemoteEvent variant. |
| `Knit.CreateProperty` | `(initialValue: any) -> Marker` | RemoteProperty slot. |
| `Knit.Start` | `(opts: {Middleware: Middleware?}?) -> Promise` | Boot. Returns a Promise; call once. |
| `Knit.OnStart` | `() -> Promise` | Promise that resolves after `Start` finishes. |
| `Knit.Util` | `Folder` | Sibling util folder (Promise/Comm) — leave alone. |

**Client API (`KnitClient`):**

| Method | Signature | Description |
|---|---|---|
| `Knit.CreateController` | `(def: {Name: string, [any]: any}) -> Controller` | Register a controller. |
| `Knit.AddControllers` | `(parent: Instance) -> {Controller}` | `require` ModuleScript children. |
| `Knit.AddControllersDeep` | `(parent: Instance) -> {Controller}` | `require` ModuleScript descendants. |
| `Knit.GetService` | `(name: string) -> Service` | Reflection of server's `Client` table (lazy-build). Server methods return Promises by default. |
| `Knit.GetController` | `(name: string) -> Controller` | Local controller lookup. |
| `Knit.Start` | `(opts: {ServicePromises: boolean?, Middleware: Middleware?, PerServiceMiddleware: ...}?) -> Promise` | Set `ServicePromises = false` to make service methods return values directly. |
| `Knit.OnStart` | `() -> Promise` | Resolves after `Start`. |
| `Knit.Player` | `Player` | Shortcut for `Players.LocalPlayer`. |

**Service shape:**

```luau
local MyService = Knit.CreateService({
    Name = "MyService",
    Client = {
        Bumped   = Knit.CreateSignal(),         -- becomes RemoteSignal on Start
        Score    = Knit.CreateProperty(0),      -- becomes RemoteProperty
        Greet    = function(self, player, msg)  -- becomes invokable RemoteFunction
            return ("hi %s, %s"):format(player.Name, msg)
        end,
    },
})

function MyService:KnitInit() end    -- runs in parallel before all Start hooks
function MyService:KnitStart() end   -- runs after all Inits resolve
```

**Controller shape:** same lifecycle hooks (`KnitInit`, `KnitStart`); no `Client` table.

**Usage:**

```luau
Knit.AddServices(ServerScriptService.Server.Services)
Knit.Start():catch(warn)
```

**Gotchas:**

- This project supersedes Knit's `RemoteSignal` with **BridgeNet2 bridges**. Do **not** add `Knit.CreateSignal()` to new services — register a bridge in `Bridges.luau` instead. Service `Client` tables should stay limited to existing patterns or be left empty.
- Once you call `Knit.Start()`, the services table is frozen. Creating services post-start throws.
- `Knit.GetService` on the **client** only returns objects when the service exposed remote content. If `Client` is empty, the service is invisible.
- `Knit.Util` points at the `Packages/_Index/sleitnick_knit@1.7.0` folder which contains Knit's bundled `Promise` and `Comm`. Don't `require` those directly — use the top-level `Packages.Promise` if you need promises.

---

### 1.2 BridgeNet2

**Require:** `local Bridges = require(game.ReplicatedStorage.Packages.BridgeNet2)`
**Source:** `Packages/_Index/ffrostflame_bridgenet2@1.0.0/bridgenet2/src/{init,PublicTypes}.luau`
**Wally:** `ffrostflame/bridgenet2@1.0.0`
**Purpose:** Project's **only** allowed client-server remote layer. All bridges should be declared centrally in `src/Shared/Shared/Bridges.luau`.

**Top-level API:**

| Method | Signature | Description |
|---|---|---|
| `ReferenceBridge` | `(name: string) -> Bridge` | Get/create a bridge. Works identically on client and server. |
| `ServerBridge` | `(name: string) -> ServerBridge` | Server-only typed view (nil on client). |
| `ClientBridge` | `(name: string) -> ClientBridge` | Client-only typed view (nil on server). |
| `ReferenceIdentifier` | `(name: string, maxWaitTime: number?) -> Identifier` | Compresses string-like keys for the wire. |
| `Serialize` / `Deserialize` | `(s: string) -> Identifier` / `(c: string) -> Identifier` | Identifier transport helpers. |
| `Players(players: {Player})` | `-> SetPlayerContainer` | Send to a subset. |
| `AllPlayers()` | `-> AllPlayerContainer` | Send to everyone. |
| `PlayersExcept(excluded: {Player})` | `-> ExceptPlayerContainer` | Send to all minus list. |
| `ToHex` / `FromHex` / `ToReadableHex` | `(s) -> s` | Bit/byte helpers. |
| `CreateUUID` | `() -> string` | UUID v4 minus dashes. |
| `HandleInvalidPlayer` | `(handler: (player) -> ()) -> ()` | Server-only. Hook when packet validation rejects a player. |

**Bridge methods (server view):**

| Method | Signature | Description |
|---|---|---|
| `:Fire` | `(target: Player \| AllPlayerContainer \| SetPlayerContainer, content: any) -> ()` | Send to one player or to a player container. |
| `:Connect` | `(cb: (player: Player, content) -> (), name: string?) -> Connection` | Listen to client-fired payloads. |
| `:Once` | `(cb: (player, content) -> ()) -> ()` | Single-shot. |
| `:Wait` | `() -> (Player, content)` | Yields until next packet. |
| `OnServerInvoke` | `((player, content) -> ...any)?` | Field — assign a function to expose request/response RemoteFunction-style. |
| `RateLimitActive` | `boolean` | Toggle internal rate limit. |
| `Logging` | `boolean` | Per-bridge verbose logging. |

**Bridge methods (client view):**

| Method | Signature | Description |
|---|---|---|
| `:Fire` | `(content: any) -> ()` | Send to server. |
| `:Connect` | `(cb: (content) -> (), name: string?) -> Connection` | Listen to server payloads. |
| `:Once` | `(cb: (content) -> ()) -> ()` | Single-shot. |
| `:Wait` | `(cb: ...) -> content` | Yields. |
| `:InvokeServerAsync` | `(content) -> content` | Request/response. |

**Convenience server fan-out (via containers):**

```luau
bridge:Fire(Bridges.AllPlayers(), payload)
bridge:Fire(Bridges.PlayersExcept({attacker}), payload)
bridge:Fire(Bridges.Players({p1, p2}), payload)
```

**Usage:**

```luau
-- Shared (Bridges.luau)
local Bridges = require(game.ReplicatedStorage.Packages.BridgeNet2)
return {
    GiveCash = Bridges.ReferenceBridge("GiveCash"),
}

-- Server
Bridges.GiveCash:Connect(function(player, payload)
    task.spawn(function()
        -- ... mutate data, then ...
        Bridges.GiveCash:Fire(player, { ok = true, amount = payload.amount })
    end)
end)

-- Client
Bridges.GiveCash:Connect(function(payload) ... end)
Bridges.GiveCash:Fire({ amount = 100 })
```

**Gotchas:**

- **Single-table payload convention** for this project. ALWAYS pass a single table (e.g. `{ amount = 100 }`), never positional varargs. Keeps payload shape grep-able across the codebase.
- **No yield in handlers.** `:Connect` callbacks must not yield — wrap any DataStore/Replica work in `task.spawn`. Acquire per-player mutexes **outside** the spawn, release **inside** (see CLAUDE.md).
- Identifiers count toward Roblox's 4096-string-identifier cap. Use bridges over identifiers for high-volume channels.
- Studio mock mode: BridgeNet2 silently swaps bridges with a `MockBridge` in edit mode (see `init.luau` line 126). Do not rely on production behavior from edit-mode play.
- `OnServerInvoke` is a field assignment, not a `:Connect` — overwriting it replaces the handler.

---

### 1.3 Loader

**Require:** `local Loader = require(game.ReplicatedStorage.Packages.Loader)`
**Source:** `Packages/_Index/sleitnick_loader@2.0.0/loader/init.lua`
**Wally:** `sleitnick/loader@2.0.0`
**Purpose:** Bulk-load module children. Used to seed Knit services/controllers folders.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Loader.LoadChildren` | `(parent: Instance, predicate: ((m: ModuleScript) -> boolean)?) -> {[string]: any}` | `require` each immediate ModuleScript child. |
| `Loader.LoadDescendants` | `(parent: Instance, predicate?) -> {[string]: any}` | Same, recursive. |
| `Loader.MatchesName` | `(matchName: string) -> (m: ModuleScript) -> boolean` | Returns a name-suffix predicate. |
| `Loader.SpawnAll` | `(loaded: {[string]: any}, methodName: string) -> ()` | Calls `obj[methodName]()` on each loaded module in a fresh thread. |

**Usage:**

```luau
local handlers = Loader.LoadDescendants(ServerStorage.Server.Modules, Loader.MatchesName("Handler"))
Loader.SpawnAll(handlers, "Init")
```

**Gotchas:**

- `Knit.AddServices*` already does what `LoadChildren` does — don't double-load.

---

## 2. Data & Persistence

### 2.1 ProfileStore (server-only)

**Require:** `local ProfileStore = require(game.ServerScriptService.Server.Packages.ProfileStore)`
**Source:** `src/Server/Server/Packages/_Index/lm-loleris_profilestore@1.0.3/profilestore/ProfileStore.luau`
**Wally:** `lm-loleris/profilestore@1.0.3` (server-dependencies)
**Purpose:** Session-locked DataStore profile management. **Do not use directly** — go through `DataService.luau`.

**Module API:**

| Method | Signature | Description |
|---|---|---|
| `ProfileStore.New` | `<T>(store_name: string, template: T?) -> ProfileStore<T>` | Build a store. `template` is auto-`Reconcile`d on load. |
| `ProfileStore.SetConstant` | `(name, value) -> ()` | Tune `AUTO_SAVE_PERIOD`, `SESSION_STEAL`, `ASSUME_DEAD`, etc. |
| `IsClosing` / `IsCriticalState` | `boolean` | Module-level health flags. |
| `OnError` / `OnOverwrite` / `OnCriticalToggle` | `Signal-like {Connect = ...}` | Diagnostics signals. |
| `DataStoreState` | `"NotReady" \| "NoInternet" \| "NoAccess" \| "Access"` | DataStore reachability state. |

**ProfileStore instance:**

| Method | Signature | Description |
|---|---|---|
| `:StartSessionAsync` | `(profile_key: string, params: {Steal: boolean?}) -> Profile<T>?` | Acquire session lock. Returns `nil` on failure. |
| `:GetAsync` | `(profile_key: string, version: string?) -> Profile<T>?` | Read-only snapshot — no session lock. |
| `:MessageAsync` | `(profile_key: string, message: any) -> boolean` | Deliver a message to the profile owner. |
| `:RemoveAsync` | `(profile_key: string) -> boolean` | GDPR-safe wipe. |
| `:VersionQuery` | `(profile_key, sort?, min_date?, max_date?) -> VersionQuery` | Iterate historical versions. |
| `.Mock` | `ProfileStore<T>` | Mirror store used in Studio. |

**Profile instance:**

| Method / Field | Signature / Type | Description |
|---|---|---|
| `Data` | `T` | Mutable session data. |
| `LastSavedData` | `T` | Last successful save snapshot. |
| `Session` | `{PlaceId, JobId}?` | Active session info. |
| `RobloxMetaData` | `any` | DataStore metadata. |
| `UserIds` | `{number}` | Associated user ids. |
| `KeyInfo` | `DataStoreKeyInfo` | Underlying key info. |
| `OnSave` / `OnLastSave` / `OnSessionEnd` / `OnAfterSave` | `Signal-like` | Lifecycle hooks. |
| `:IsActive` | `() -> boolean` | Session still owned by this server? |
| `:Reconcile` | `() -> ()` | Sync template keys into `Data`. |
| `:EndSession` | `() -> ()` | Release lock + final save. |
| `:Save` | `() -> ()` | Manual save (rate-limited). |
| `:SetAsync` | `() -> ()` | Save AND release session lock immediately. |
| `:AddUserId` / `:RemoveUserId` | `(id: number) -> ()` | GDPR association. |
| `:MessageHandler` | `(fn: (message, processed: () -> ()) -> ()) -> ()` | Handle `MessageAsync` payloads. |

**Usage (via DataService):** see `architecture.md § DataService API`. **Never** call `:Save()` from gameplay code — use `DataService.Set` / `DataService.SetPath` / `DataService.Update` which handle the no-yield-in-bridge rule.

**Gotchas:**

- DataStore key is `'BoilerplateData_LIVE_1'`. **NEVER rename** — wipes all player data (CLAUDE.md rule).
- `:StartSessionAsync` returning `nil` means another server holds the lock. Apply the `SESSION_STEAL` constant only in a launch-day migration.
- All `Async` methods yield. Wrap in `task.spawn` if invoked from a bridge handler.
- Profile data must be JSON-serializable — no Instances, functions, or mixed-key tables.

---

### 2.2 Mad Studio Replica (vendored) — Server

**Require:** `local Replica = require(game.ServerScriptService.Server.ReplicaServer)` *(NOTE: actual path is `script.Parent.ReplicaServer` in `Server/init.server.luau`; do not assume top-level ServerScriptService.)*
**Source:** `src/Server/ReplicaServer.luau`
**Vendored — not on Wally.**
**Purpose:** Server-side authoritative replicated state. **Do not use directly** outside `DataService.luau`. Stable wrapper lives in `DataService`.

**Module API:**

| Method | Signature | Description |
|---|---|---|
| `Replica.Token` | `(name: string) -> Token` | Declare a token. Tokens are duplicate-checked; declare them ONCE in module top-level. |
| `Replica.New` | `(params: {Token, Tags: {}?, Data: {}?, WriteLib: ModuleScript?}) -> Replica` | Construct. Returns inactive until `:Replicate()` is called. |
| `Replica.FromId` | `(id: number) -> Replica` | Lookup. |
| `Replica.ReadyPlayers` | `{[Player]: true}` | Active set of ready players. |
| `Replica.NewReadyPlayer` / `RemovingReadyPlayer` | `Signal` | Player session lifecycle. |

**Replica instance:**

| Method / Field | Signature | Description |
|---|---|---|
| `Tags` / `Data` / `Id` / `Token` / `Parent` / `Children` / `BoundInstance` | fields | State containers. |
| `OnServerEvent` | `Signal {Connect = ...}` | Receives `:FireServer` from clients. |
| `Maid` | `Maid` | Auto-cleaned on destroy. |
| `:Set` | `(path: {string}, value: any) -> ()` | Replace value at path. |
| `:SetValues` | `(path: {string}, values: {[string]: any}) -> ()` | Patch multiple keys at path. |
| `:TableInsert` | `(path: {string}, value: any, index: number?) -> number` | Array insert; returns index. |
| `:TableRemove` | `(path: {string}, index: number) -> any` | Removes and returns. |
| `:Write` | `(function_name: string, ...) -> ...any` | Run a WriteLib function (replicates to clients). |
| `:FireClient` / `:FireAllClients` | `(player?, ...) -> ()` | Reliable replica events. |
| `:UFireClient` / `:UFireAllClients` | `(player?, ...) -> ()` | Unreliable variant. |
| `:SetParent` | `(new_parent: Replica) -> ()` | Reparent. |
| `:BindToInstance` | `(instance: Instance) -> ()` | Auto-destroy when instance is gone. |
| `:Replicate` | `() -> ()` | Open replication to all ready players. |
| `:DontReplicate` | `() -> ()` | Close replication. |
| `:Subscribe` / `:Unsubscribe` | `(player: Player) -> ()` | Selective replication. |
| `:Identify` | `() -> string` | Debug label. |
| `:IsActive` | `() -> boolean` | Not destroyed. |
| `:Destroy` | `() -> ()` | Tears down + notifies clients. |

**Usage:** see `DataService.luau`. The standard pattern is one player replica per session keyed by UserId, plus token-scoped replicas for shared world state.

**Gotchas:**

- **Do not call these directly outside `DataService.luau`.** Wrapping centralizes the leaving-race fallback that writes to `profile.Data[key]` when the player has already left.
- Tokens must be globally unique per server lifetime. `Replica.Token("X")` twice throws.
- `WriteFlag` is a module-private gate — `:Write` calls fan out to clients automatically; do NOT manually `:Set` and `:Write` for the same change.
- Bind to an instance only when the lifetime of the data matches that instance.

---

### 2.3 Mad Studio Replica (vendored) — Client

**Require:** `local Replica = require(game.ReplicatedStorage.ReplicaClient)`
**Source:** `src/Shared/ReplicaClient.luau`
**Vendored — not on Wally.**
**Purpose:** Client-side observer for server-driven replicas.

**Module API:**

| Method | Signature | Description |
|---|---|---|
| `Replica.IsReady` | `boolean` | True after server has flushed initial data. |
| `Replica.OnLocalReady` | `Signal` | Fires once when ready. |
| `Replica.RequestData` | `() -> ()` | Idempotent. Asks server for initial state. Usually called by `PlayerData`. |
| `Replica.OnNew` | `(token: string, listener: (replica) -> ()) -> Connection` | Fires for every replica of the token, including existing ones (deferred). |
| `Replica.FromId` | `(id: number) -> Replica?` | Lookup. |
| `Replica.Test` | `() -> table` | Debug snapshot. |

**Replica instance:**

| Method / Field | Signature | Description |
|---|---|---|
| `Tags` / `Data` / `Id` / `Token` / `Parent` / `Children` / `BoundInstance` | fields | Read-only mirror of server state. |
| `OnClientEvent` | `Signal {Connect}` | Receives `:FireClient` from server. |
| `Maid` | `Maid` | Auto-cleaned when replica destroyed. |
| `:OnSet` | `(path: {}, listener: () -> ()) -> Connection` | Listens for `:Set`/`:SetValues` at the given path. |
| `:OnWrite` | `(function_name: string, listener: (...) -> ()) -> Connection` | Listens for `:Write` calls. |
| `:OnChange` | `(listener: (action: "Set"\|"SetValues"\|"TableInsert"\|"TableRemove", path, p1, p2?) -> ()) -> Connection` | Catch-all change listener. |
| `:GetChild` | `(token: string) -> Replica?` | Child lookup. |
| `:FireServer` / `:UFireServer` | `(...) -> ()` | Reliable / unreliable client->server event. |
| `:Identify` | `() -> string` | Debug label. |
| `:IsActive` | `() -> boolean` | Not destroyed. |

**Usage:**

```luau
local Replica = require(game.ReplicatedStorage.ReplicaClient)

Replica.OnNew("PlayerData", function(replica)
    print("got", replica:Identify(), replica.Data)
    replica:OnSet({"Coins"}, function()
        updateCoinsHUD(replica.Data.Coins)
    end)
end)

Replica.RequestData()
```

**Gotchas:**

- **Use `:OnSet` for specific paths and `:OnChange` for catch-all.** `ListenToChange` does NOT exist — older Mad Studio doc references use a different name. The code is the source of truth.
- `:OnSet({})` (empty path) fires on top-level changes only.
- Listeners are batched per yielded thread (see `RunEventHandlerInFreeThread`). Don't yield inside them.
- Project standard: consume via `PlayerData` (client wrapper around the local-player replica) instead of touching `Replica.OnNew` everywhere.

---

### 2.4 Mad Studio Replica (vendored) — ReplicaShared

**Require:** `local Maid = require(game.ReplicatedStorage.ReplicaShared.Maid)` (etc.)
**Source:** `src/Shared/ReplicaShared/{Maid,Signal,Remote,RateLimit}.luau`
**Vendored — not on Wally.**
**Purpose:** Primitive deps the Replica modules need. Available for general use but most code should prefer the top-level `Packages` equivalents.

**Maid.luau:**

| Method | Signature | Description |
|---|---|---|
| `Maid.New` | `(key: any) -> Maid` | New maid; pass an opaque lock token to gate `:Unlock`. |
| `:Add` | `(object: any) -> MaidToken` | Adds. Returns token you can `:Destroy()` to drop just that entry. |
| `:Cleanup` | `(...) -> ()` | Tear down everything. |
| `:Unlock` | `(key) -> ()` | Re-enable adds (called internally). |
| `:IsActive` | `() -> boolean` | Not torn down. |

**Signal.luau:**

| Method | Signature | Description |
|---|---|---|
| `Signal.New<T...>()` | `-> Signal<T...>` | Construct. Note capital `N`. |
| `:Connect` | `(listener: (...) -> ()) -> Connection` | Connect. |
| `:Fire` | `(...) -> ()` | Dispatch. |
| `:Wait` | `() -> ...` | Yields. |
| `:FireUntil` | `(continue_cb: () -> boolean, ...) -> ()` | Fires until predicate is false. |

**Remote.luau:**

| Method | Signature | Description |
|---|---|---|
| `Remote.New` | `(name: string, is_unreliable: boolean?) -> Remote` | Wraps RemoteEvent or UnreliableRemoteEvent under `ReplicatedStorage`. |
| `:FireServer` / `:FireClient` / `:FireAllClients` | `(player?, ...) -> ()` | Same shape as RemoteEvent. |

**RateLimit.luau:**

| Method | Signature | Description |
|---|---|---|
| `RateLimit.New` | `(rate: number, is_full_wait: boolean?) -> RateLimit` | Constructor. |
| `:CheckRate` | `(source) -> boolean` | True if event should be processed. |
| `:CleanSource` | `(source) -> ()` | Forget a source. |
| `:Cleanup` | `() -> ()` | Forget all. |
| `:Destroy` | `() -> ()` | Drop the rate limiter. |

**Gotchas:**

- Two `Signal` modules exist: top-level `Packages.Signal` (sleitnick, `.new()`) and `ReplicaShared.Signal` (Mad Studio, `.New()`). Mind capitalization.
- Do not import `ReplicaShared.Signal` for general use — prefer `Packages.Signal` for new code.

---

## 3. Cleanup, Signals & Async

### 3.1 Janitor

**Require:** `local Janitor = require(game.ReplicatedStorage.Packages.Janitor)`
**Source:** `Packages/_Index/howmanysmall_janitor@1.18.3/janitor/src/init.luau`
**Wally:** `howmanysmall/janitor@1.18.3`
**Purpose:** Project's **default cleanup container**.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Janitor.new` | `() -> Janitor` | Construct. |
| `Janitor.Is` / `Janitor.instanceof` | `(obj) -> boolean` | Type check. |
| `:Add` | `<T>(object: T, methodName: boolean\|string?, index: any?) -> T` | Track. Returns the object. `methodName` (`true` = call as function, string = call `object[methodName]`); `nil` auto-detects (`Destroy` / `Disconnect`). `index` allows later `:Remove(index)`. |
| `:AddObject` | `<T,A...>(ctor: {new: (A...) -> T}, methodName?, index?, A...) -> T` | Construct via `ctor.new(...)` and track. |
| `:AddPromise` | `<T...>(promise, index?) -> Promise` | Cancel promise on cleanup. |
| `:Remove` | `(index) -> Janitor` | Clean and drop the indexed object. |
| `:RemoveNoClean` | `(index) -> Janitor` | Drop without cleaning. |
| `:RemoveList` | `(...indexes) -> Janitor` | Bulk remove + clean. |
| `:RemoveListNoClean` | `(...indexes) -> Janitor` | Bulk drop. |
| `:Get` | `(index) -> any?` | Look up. |
| `:GetAll` | `() -> {[any]: any}` | All entries. |
| `:Cleanup` | `() -> ()` | Tear down all tracked objects. |
| `:Destroy` | `() -> ()` | `Cleanup` + permanently kill the janitor. |
| `:LinkToInstance` | `(instance, allowMultiple: boolean?) -> RBXScriptConnection` | Auto-clean when the instance is destroyed. |
| `:LinkToInstances` | `(...Instance) -> Janitor` | Multi-link variant. |

**Usage:**

```luau
local janitor = Janitor.new()
janitor:Add(part.Touched:Connect(onTouch))          -- auto :Disconnect
janitor:Add(workspace.NewPart, "Destroy", "part")   -- explicit method + index
janitor:LinkToInstance(part)                         -- destroy when part is gone

-- later
janitor:Remove("part")
```

**Gotchas:**

- Cleanup order is LIFO. Order matters when freeing resources that hold references.
- `:Add(thread)` schedules `task.cancel` (unless `UnsafeThreadCleanup` is set), which can race if the thread is already finished.
- Use Janitor over Trove in new project code. Trove only exists here because UIAnimator vendors it internally.
- **Auto-detect probes `obj.Destroy` first, then `obj.Disconnect`.** This is safe for Instances, RBXScriptConnection, and most custom signals — but **not** for objects whose metatable's `__index` THROWS on unknown members (e.g. **ZonePlus signal Connections** from `mattschrubb_zoneplus@3.2.0.zoneplus.Signal`). The probe accesses `conn.Destroy`, the `__index` throws `"Connection::Destroy (not a valid member)"`, and `Janitor:Add` blows up. **Fix: pass the method name explicitly** so Janitor never probes:
  ```luau
  -- BAD — Janitor probes :Destroy → ZonePlus Signal __index throws
  janitor:Add(zone.playerEntered:Connect(onEnter))

  -- OK — explicit method name, no probe
  janitor:Add(zone.playerEntered:Connect(onEnter), "Disconnect")
  ```
  Same pattern applies to `Zone` itself: use `janitor:Add(zone, "destroy")` (lowercase `destroy` — ZonePlus's destructor) so Janitor doesn't probe `Destroy` capital-D.

---

### 3.2 Signal

**Require:** `local Signal = require(game.ReplicatedStorage.Packages.Signal)`
**Source:** `Packages/_Index/sleitnick_signal@2.0.3/signal/init.luau`
**Wally:** `sleitnick/signal@2.0.0` (lockfile pinned to `2.0.3`)
**Purpose:** GoodSignal-derived deferrable signal. Lowercase `.new()`.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Signal.new<T...>()` | `-> Signal<T...>` | Construct. |
| `Signal.Wrap` | `(rbxScriptSignal) -> Signal` | Wrap an RBXScriptSignal. |
| `Signal.Is` | `(obj) -> boolean` | Type check. |
| `:Connect` | `(fn: (T...) -> ()) -> Connection` | Subscribe. |
| `:Once` | `(fn) -> Connection` | One-shot subscribe (auto-disconnects). |
| `:Fire` | `(T...) -> ()` | Dispatch on a recycled coroutine. |
| `:FireDeferred` | `(T...) -> ()` | Dispatch on `task.defer`. |
| `:DisconnectAll` | `() -> ()` | Drop every connection (also cancels yielded `:Wait` threads with a traceback warn). |
| `:Wait` | `() -> T...` | Yields. |
| `:GetConnections` | `() -> {Connection}` | Snapshot. |
| `:Destroy` | `() -> ()` | Permanent disconnect. |

Connection: `{Connected: boolean, Disconnect(self), Destroy(self)}`. `Destroy = Disconnect`.

**Usage:**

```luau
local s = Signal.new()
local conn = s:Connect(function(x) print(x) end)
s:Fire(42)
conn:Disconnect()
```

**Gotchas:**

- Lowercase `Signal.new` — contrast Mad Studio `Signal.New`. Two libs, two casings.
- `:DisconnectAll` warns + cancels yielded `:Wait` threads. This is loud on purpose; expect it in logs only when you actually wanted to tear down.
- Connections are strict-readonly — assigning to unknown keys throws.

---

### 3.3 Trove

**Require:** `local Trove = require(game.ReplicatedStorage.Packages.Trove)`
**Source:** `Packages/_Index/sleitnick_trove@1.8.0/trove/init.luau`
**Wally:** `sleitnick/trove@1.8.0`
**Purpose:** Cleanup container used **only** as UIAnimator's internal dependency.

**API (use Janitor instead — listed for completeness):**

| Method | Signature | Description |
|---|---|---|
| `Trove.new()` | `-> Trove` | Construct. |
| `:Add` | `(object, cleanupMethod: string?) -> object` | Track. |
| `:Clone` | `(instance) -> Instance` | Clone + auto-destroy. |
| `:Construct` | `<T,A...>(class, ...) -> T` | `class.new(...)` and track. |
| `:Connect` | `(signal, fn) -> RBXScriptConnection` | Connect + auto-disconnect. |
| `:Once` | `(signal, fn) -> RBXScriptConnection` | Single-shot. |
| `:BindToRenderStep` | `(name, priority, fn) -> ()` | Auto-unbind. |
| `:AddPromise` | `(promise) -> promise` | Cancel on clean. |
| `:Remove` / `:Pop` | `(object) -> boolean` | Drop. |
| `:Extend` | `() -> Trove` | Child trove cleaned with parent. |
| `:Clean` | `() -> ()` | Tear down all. |
| `:WrapClean` | `() -> () -> ()` | Returns a function that calls `Clean`. |
| `:AttachToInstance` | `(instance) -> ()` | Auto-clean when instance dies. |
| `:Destroy` | `() -> ()` | Permanent. |

**Gotchas:**

- **Use Janitor for new code.** Trove only lives in `wally.toml` because UIAnimator (Twinkle) requires it.

---

### 3.4 Promise (evaera)

**Require:** `local Promise = require(<Knit>.Util.Promise)` (Knit ships it under `Packages/_Index/sleitnick_knit@1.7.0/Promise.lua`). If you need promises in non-Knit code, use the `evaera_promise@4.0.0` index directly.
**Source:** `Packages/_Index/evaera_promise@4.0.0/promise/lib/init.lua`
**Wally:** `evaera/promise@4.0.0`
**Purpose:** A+ promises. Used internally by Knit's lifecycle and remote-method shims.

**Constructors:**

| Method | Signature | Description |
|---|---|---|
| `Promise.new(executor)` | `((resolve, reject, onCancel) -> ()) -> Promise` | Standard. |
| `Promise.defer(executor)` | `... -> Promise` | Same but runs executor on `task.defer`. Aliased `Promise.async`. |
| `Promise.resolve(...)` | `-> Promise` | Already-fulfilled. |
| `Promise.reject(...)` | `-> Promise` | Already-rejected. |
| `Promise.try(callback, ...)` | `-> Promise` | Resolves to return value; rejects if `callback` throws. |
| `Promise.promisify(callback)` | `-> (...) -> Promise` | Turn a yielding fn into a promise factory. |
| `Promise.fromEvent(event, predicate?)` | `-> Promise` | Resolves on next `event:Fire` matching predicate. |

**Aggregators:**

| Method | Signature | Description |
|---|---|---|
| `Promise.all({Promise})` | `-> Promise<{T}>` | Resolve when all resolve; reject on first reject. |
| `Promise.allSettled({Promise})` | `-> Promise<{PromiseStatus}>` | Never rejects. |
| `Promise.race({Promise})` | `-> Promise` | First to settle wins. |
| `Promise.any({Promise})` | `-> Promise` | First to resolve; rejects only if all reject. |
| `Promise.some({Promise}, count)` | `-> Promise` | Resolves once `count` resolve. |
| `Promise.each(list, predicate)` | `-> Promise` | Sequential map (awaiting each). |
| `Promise.fold(list, reducer, initial)` | `-> Promise` | Sequential reduce. |
| `Promise.retry(cb, times, ...)` / `Promise.retryWithDelay(cb, times, seconds, ...)` | `-> Promise` | Retry until success. |

**Instance methods:**

| Method | Signature | Description |
|---|---|---|
| `:andThen(success, failure?)` | `-> Promise` | Chain. |
| `:catch(failure)` | `-> Promise` | Failure handler. |
| `:tap(handler)` | `-> Promise` | Side effect. |
| `:andThenCall(cb, ...)` / `:andThenReturn(...)` | `-> Promise` | Sugar. |
| `:finally(handler)` | `-> Promise` | Always runs; `handler(status: PromiseStatus)`. |
| `:finallyCall(cb, ...)` / `:finallyReturn(...)` | `-> Promise` | Sugar. |
| `:timeout(seconds, rejectionValue?)` | `-> Promise` | Reject after timeout. |
| `:cancel()` | `() -> ()` | Cancel (propagates if no other consumers). |
| `:getStatus()` | `() -> "Started" \| "Resolved" \| "Rejected" \| "Cancelled"` | Status. |
| `:await()` / `:awaitStatus()` | yields | Block. |
| `:expect()` | yields | Block; throws on reject. |
| `:now(rejectionValue?)` | `-> Promise` | Immediate resolved/rejected snapshot. |
| `Promise.onUnhandledRejection(cb)` | static | Global hook. |

**Usage:**

```luau
Promise.new(function(resolve, reject, onCancel)
    local conn = part.Touched:Connect(function() resolve("touched") end)
    onCancel(function() conn:Disconnect() end)
end):timeout(5):andThen(print):catch(warn)
```

**Gotchas:**

- `:await()` returns `ok, value...` — check the first return.
- Forgotten `:catch` produces "unhandled rejection" warnings via `onUnhandledRejection`.
- A cancelled promise calls registered `onCancel` callbacks; ensure side effects are reversible.

---

### 3.5 Concur

**Require:** `local Concur = require(game.ReplicatedStorage.Packages.Concur)`
**Source:** `Packages/_Index/sleitnick_concur@0.1.2/concur/init.lua`
**Wally:** `sleitnick/concur@0.1.2`
**Purpose:** Lightweight thread-tracker — fire-and-await without Promise semantics.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Concur.spawn(fn, ...)` | `-> Concur` | Run via `task.spawn`. |
| `Concur.defer(fn, ...)` | `-> Concur` | Run via `task.defer`. |
| `Concur.delay(t, fn, ...)` | `-> Concur` | Run via `task.delay`. |
| `Concur.value(value)` | `-> Concur` | Completed-with-value sentinel. |
| `Concur.event(event, predicate?)` | `-> Concur` | Completes on next matching signal fire. |
| `Concur.all({Concur})` | `-> Concur` | Waits for every. |
| `Concur.first({Concur})` | `-> Concur` | Waits for first to complete. |
| `:Stop` | `() -> ()` | Cancel. |
| `:IsCompleted` | `() -> boolean` | Status. |
| `:Await(timeout?)` | `-> (Error?, ...?)` | Yields. |
| `:OnCompleted(fn, timeout?)` | `-> () -> ()` | Returns disconnect fn. |

**Errors enum:** `Concur.Errors = {...}` — inspect at runtime.

**Usage:**

```luau
local c = Concur.spawn(function()
    task.wait(2)
    return "done"
end)
local err, value = c:Await()
```

---

### 3.6 TaskQueue

**Require:** `local TaskQueue = require(game.ReplicatedStorage.Packages.TaskQueue)`
**Source:** `Packages/_Index/sleitnick_task-queue@1.0.0/task-queue/init.lua`
**Wally:** `sleitnick/task-queue@1.0.0`
**Purpose:** Defer items and flush them on next Heartbeat.

**API:**

| Method | Signature | Description |
|---|---|---|
| `TaskQueue.new` | `<T>(onFlush: ({T}) -> ()) -> TaskQueue` | Construct with batch handler. |
| `:Add` | `<T>(object: T) -> ()` | Enqueue. |
| `:Clear` | `() -> ()` | Drop pending without flushing. |
| `:Destroy` | `() -> ()` | Tear down. |

**Usage:**

```luau
local q = TaskQueue.new(function(batch) saveAll(batch) end)
q:Add(playerData)
```

---

### 3.7 Timer

**Require:** `local Timer = require(game.ReplicatedStorage.Packages.Timer)`
**Source:** `Packages/_Index/sleitnick_timer@2.0.0/timer/init.luau`
**Wally:** `sleitnick/timer@2.0.0`
**Purpose:** Periodic `Tick` signal.

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `Timer.new` | `(interval: number) -> Timer` | Construct. |
| `Timer.simple` | `(interval, callback, startNow?, updateSignal?, timeFn?) -> RBXScriptConnection` | One-liner timer. |
| `Timer.is` | `(obj) -> boolean` | Type check. |
| `.Interval` | `number` | Period. |
| `.UpdateSignal` | `RBXScriptSignal \| Signal` | Defaults to `Heartbeat`. |
| `.TimeFunction` | `() -> number` | Defaults to `time`. |
| `.AllowDrift` | `boolean` | Default `true`. Set before `:Start`. |
| `.Tick` | `Signal<>` | Fires every interval. |
| `:Start` | `() -> ()` | Start. |
| `:StartNow` | `() -> ()` | Start and fire `Tick` immediately. |
| `:Stop` | `() -> ()` | Stop. |
| `:IsRunning` | `() -> boolean` | Status. |
| `:Destroy` | `() -> ()` | Tear down. |

---

### 3.8 WaitFor

**Require:** `local WaitFor = require(game.ReplicatedStorage.Packages.WaitFor)`
**Source:** `Packages/_Index/sleitnick_wait-for@1.0.0/wait-for/init.lua`
**Wally:** `sleitnick/wait-for@1.0.0`
**Purpose:** Promise-returning replacements for `WaitForChild`.

**API:**

| Method | Signature | Description |
|---|---|---|
| `WaitFor.Child(parent, childName, timeout?)` | `-> Promise<Instance>` | Resolves with child. |
| `WaitFor.Children(parent, names: {string}, timeout?)` | `-> Promise<{Instance}>` | Resolves with array. |
| `WaitFor.Descendant(parent, name, timeout?)` | `-> Promise<Instance>` | Recursive. |
| `WaitFor.Descendants(parent, names, timeout?)` | `-> Promise<{Instance}>` | Bulk recursive. |
| `WaitFor.PrimaryPart(model, timeout?)` | `-> Promise<BasePart>` | Wait for `PrimaryPart`. |
| `WaitFor.ObjectValue(objVal, timeout?)` | `-> Promise<Instance>` | Wait for `.Value` to populate. |
| `WaitFor.Custom(predicate, timeout?)` | `-> Promise<T>` | Wait until predicate returns truthy. |
| `WaitFor.Error` | `{Unknown, Timeout, Cancelled, ...}` | Rejection codes. |

---

### 3.9 Sequence (project utility)

**Require:** `local Sequence = require(game.ReplicatedStorage.Utility.Sequence)`
**Source:** `src/Shared/Utility/Sequence.luau`
**Purpose:** Chainable async sequencer. Composes ordered yielding steps, parallel/race groups, and event waits into one `:Run()` flow with Janitor-bound cancellation. Replaces ad-hoc `task.spawn` + `task.delay` + `task.cancel` chains. Zero new Wally deps — uses `Packages.Signal` internally.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Sequence.new()` | `-> Sequence` | Empty builder. |
| `:Step(fn)` | `(() -> ()) -> Sequence` | Append a step; `fn` may yield. Wrapped in `pcall`. |
| `:Wait(seconds)` | `(number) -> Sequence` | `task.wait(seconds)` step. Cancellable. |
| `:WaitFor(connectable)` | `(any) -> Sequence` | Yield until a BridgeNet2 bridge / sleitnick Signal / RBXScriptSignal fires. Uses `:Once` if present, else `:Connect` + manual disconnect. |
| `:WaitForCondition(predicate, pollInterval?)` | `(() -> boolean, number?) -> Sequence` | Poll-based wait; default interval 0.1s. Escape hatch for non-event-driven conditions. |
| `:Parallel(fns)` | `({() -> ()}) -> Sequence` | Spawn all; step completes when ALL finish. Each fn pcall'd. |
| `:Race(fns)` | `({() -> ()}) -> Sequence` | Spawn all; step completes when FIRST finishes. |
| `:Bind(janitor)` | `(Janitor) -> Sequence` | `janitor:Add(self, "Cancel")`. MUST be called before `:Run` (warns + ignored otherwise). |
| `:OnComplete(fn)` | `(() -> ()) -> Sequence` | Callback fired when sequence finishes cleanly (not cancelled). Append-only; multiple allowed. |
| `:OnError(fn)` | `((err) -> boolean?) -> Sequence` | Step-error callback. Return `true` to continue; default halts. |
| `:Run()` | `() -> Sequence` | Spawn the runner coroutine. Idempotent (second call warns). |
| `:Cancel()` | `() -> ()` | Set cancel flag + `task.cancel` runner. Idempotent. |
| `:IsRunning() / :IsCancelled() / :IsComplete()` | `() -> boolean` | State checks. |
| `:Await()` | `() -> ()` | Safe completion-wait. Returns immediately if already complete; otherwise yields on `Completed`. **Use this instead of `seq.Completed:Wait()`** — synchronous sequences finish inside `:Run()` before any external `:Wait()` can register, so direct `Completed:Wait()` hangs forever. |
| `.Completed` | `Signal` | Fires `(success: boolean, errOrNil)` exactly once when the sequence ends. |

**Usage — UI animation chain (yielding UIAnimator calls):**

```luau
local Sequence   = require(game.ReplicatedStorage.Utility.Sequence)
local UIAnimator = require(script.Parent.Parent.Packages.UIAnimator)

Sequence.new()
    :Step(function() UIAnimator.FrameZoom(frame1, true, 0.25) end)  -- yields
    :Wait(0.2)
    :Step(function() UIAnimator.FrameZoom(frame2, true, 0.25) end)
    :Bind(_janitor)
    :Run()
```

**Usage — wait on a bridge then notify:**

```luau
local Sequence = require(game.ReplicatedStorage.Utility.Sequence)
local Bridges  = require(game.ReplicatedStorage.Shared.Bridges)
local NotificationClient = require(script.Parent.Parent.Modules.NotificationClient)

Sequence.new()
    :WaitFor(Bridges.RebirthGranted)
    :Step(function() NotificationClient.Success("Rebirth complete!") end)
    :OnError(function(err) warn("[seq]", err) end)
    :Run()
```

**Gotchas:**

- **No rollback on cancel.** If step 3 of 5 mutated state before cancellation, that state stays mutated. Attach cleanup via `:OnError` or `:Bind(janitor)`.
- **`:Race` does not cancel losing branches.** The other coroutines stay alive; their work is discarded. Avoid side effects you can't tolerate running twice.
- **`:Bind` must precede `:Run`.** Calling it after `:Run` warns and is ignored — the janitor is not wired.
- **`:WaitFor` requires `:Once` or `:Connect`.** Unrecognised targets warn + skip the step (the sequence still continues).
- **Step error halts by default.** Return `true` from an `:OnError` handler to swallow and continue.

See also: § 3.1 Janitor, § 3.2 Signal.

---

### Project — Format

**Require:** `local Format = require(game.ReplicatedStorage.Utility.Format)`
**Source:** `src/Shared/Utility/Format.luau`
**Purpose:** Number and string formatting utilities. **MANDATORY for all client-visible numbers** — see `architecture.md § Client-visible numbers`. Raw `tostring(n)` for client display is forbidden.

**Client-visible number API (new — use these for all player-facing output):**

| Method | Signature | Description |
|---|---|---|
| `Format.Suffix` | `(n: number, decimals: number?) -> string` | **Default.** Compact suffix form. Suffixes: K=1e3 M=1e6 B=1e9 T=1e12 Qa=1e15 Qi=1e18. `decimals` defaults to 1. Trailing `.0` stripped. Negative prefix preserved. Below 1 000 returns integer string. |
| `Format.Commas` | `(n: number) -> string` | Thousands-comma form. Handles negatives and decimals. |
| `Format.Number` | `(n: number, mode: ("suffix" \| "commas")?) -> string` | Convenience wrapper. `mode` defaults to `"suffix"`. |

**Usage:**

```luau
local Format = require(game.ReplicatedStorage.Utility.Format)

-- Suffix (default for all player-facing numbers)
Format.Suffix(40000)          -- "40K"
Format.Suffix(1500000)        -- "1.5M"
Format.Suffix(1200000000)     -- "1.2B"
Format.Suffix(500000, 0)      -- "500K"  (0 decimal places)
Format.Suffix(-40000)         -- "-40K"
Format.Suffix(999)            -- "999"   (below 1 000 → integer)

-- Commas
Format.Commas(1500000)        -- "1,500,000"
Format.Commas(-3200)          -- "-3,200"

-- Number convenience
Format.Number(1500000)                -- "1.5M"
Format.Number(1500000, "commas")      -- "1,500,000"
```

**Legacy / other functions (pre-existing — do not duplicate):**

| Method | Description |
|---|---|
| `Format.abbreviateNumber(x, precision?)` | Number with suffix, positive-only, no negative handling. Prefer `Format.Suffix`. |
| `Format.abbreviateCash(x, precision?)` | Cash abbreviation (delegates to `formatCash` below 1 000). |
| `Format.formatCash(amount)` | Full precision cash with commas: "1,000.15". |
| `Format.formatWithCommas(num)` | Same as `Format.Commas` under the hood. |
| `Format.formatTime(seconds, minUnit?)` | Duration string: "2:05", "1:00:05". |
| `Format.formatTimeWithMilliseconds(s, precision, minUnit?)` | Duration + ms: "2:05.356". |
| `Format.cash(amount)` | "$" + abbreviateCash. |
| `Format.number(amount)` | abbreviateNumber (no "$"). |
| `Format.getPossessiveName(name)` | "Steve" → "Steve's". |
| `Format.getAttributeSafeString(input)` | Strip non-word chars. |
| `Format.removeRichTextTags(input)` | Strip `<...>` tags. |
| `Format.removeTags(str)` | Strip tags + convert `<br />` to `\n`. |
| `Format.toPascalCase(input)` | "hello_world" → "HelloWorld". |
| `Format.getOrdinalString(input)` | 1 → "1st", 22 → "22nd". |
| `Format.addSpaceBeforeUpperCase(input)` | "HelloWorld" → "Hello World". |
| `Format.splitByUppercase(input)` | "HelloWorld" → `{"Hello", "World"}`. |

**Gotchas:**

- `Format.Suffix` caps at Qi (1e18). Numbers above 1e18 still render in Qi form (e.g. "1500Qi") rather than falling back to raw `tostring`. If you need higher denominations extend `_suffixThresholds` in the source.
- `Format.abbreviateNumber` and `Format.abbreviateCash` do not handle negative numbers — use `Format.Suffix` for any value that can go negative.
- `Format.formatCash` rounds to 2 decimal places — appropriate for actual currency display ("$1,000.50"), not for large integer scores (use `Format.Suffix`).

---

## 4. Table & Functional Utilities

### 4.1 Sift

**Require:** `local Sift = require(game.ReplicatedStorage.Packages.Sift)`
**Source:** `Packages/_Index/csqrl_sift@0.0.10/sift/src/{init,Array/init,Dictionary/init,Set/init}.lua`
**Wally:** `csqrl/sift@0.0.10`
**Purpose:** Immutable Array/Dictionary/Set helpers. Almost every function returns a **new** table — operands are untouched.

**Top level:** `Sift.Array` (alias `Sift.List`), `Sift.Dictionary`, `Sift.Set`, `Sift.None` (sentinel value), `Sift.Types`, `Sift.equalObjects`, `Sift.isEmpty`.

**Sift.Array (heavy hitters):**

`at, concat (alias join, merge), concatDeep, copy, copyDeep, count, create, difference, differenceSymmetric, equals, equalsDeep, every, filter, find (alias indexOf), findLast, findWhere, findWhereLast, first, flatten, freeze, freezeDeep, includes (alias has, contains), insert, is (alias isArray), last, map, pop, push (alias append), reduce, reduceRight, removeIndex, removeIndices, removeValue, removeValues, reverse, set, shift, shuffle, slice, some, sort, splice, toSet, unshift (alias prepend), update, zip, zipAll`

**Sift.Dictionary:**

`copy, copyDeep, count, entries, equals, equalsDeep, every, filter, flatten, flip, freeze, freezeDeep, fromArrays, fromEntries, has, includes, keys, map, merge (alias join), mergeDeep (alias joinDeep), removeKey, removeKeys, removeValue, removeValues, set, some, update, values, withKeys`

**Sift.Set:**

`add, copy, count, delete (alias subtract), difference, differenceSymmetric, filter, fromArray (alias fromList), has, intersection, isSubset, isSuperset, map, merge (alias join, union), toArray`

**Usage:**

```luau
local Dict = Sift.Dictionary
local next = Dict.merge(playerData, { Coins = playerData.Coins + 10 })

local Arr = Sift.Array
local odds = Arr.filter({1,2,3,4,5}, function(v) return v % 2 == 1 end)
```

**Gotchas:**

- `Sift.None` is a sentinel that **removes** the key in `merge`/`mergeDeep`. Setting a key to plain `nil` keeps the existing value because `nil` doesn't survive table iteration.
- Use `Sift.Dictionary.merge` for player-data patches — pairs cleanly with Replica `:SetValues`.
- Sift treats `{}` ambiguously — `Array.is` returns `true` for empty tables. Use intent-revealing constructors (`Set.fromArray`, `Array.create(0)`) when shape matters.

---

### 4.2 TableUtil

**Require:** `local TableUtil = require(game.ReplicatedStorage.Packages.TableUtil)`
**Source:** `Packages/_Index/sleitnick_table-util@1.2.1/table-util/init.lua`
**Wally:** `sleitnick/table-util@1.2.1`
**Purpose:** Sleitnick's table helpers (immutable except `SwapRemove*` and `Lock`).

**API:**

| Method | Signature | Description |
|---|---|---|
| `Copy(t, deep?)` | `-> t` | Shallow by default. **No cyclic guard** with `deep=true`. |
| `Sync(src, template)` | `-> template-shaped` | Two-way sync (removes extras). Destructive for data. |
| `Reconcile(src, template)` | `-> src ∪ template` | One-way fill-in. Use for player data. |
| `SwapRemove(t, i)` | `-> ()` | In-place O(1) remove (breaks order). |
| `SwapRemoveFirstValue(t, v)` | `-> number?` | Find + SwapRemove. |
| `Map(t, f)` | `-> {f(v)}` | |
| `Filter(t, predicate)` | `-> {v}` | |
| `Reduce(t, predicate, init?)` | `-> any` | |
| `Assign(target, ...)` | `-> table` | Like JS `Object.assign`. |
| `Extend(target, extension)` | `-> array` | Array concat. |
| `Reverse(t)` | `-> array` | |
| `Shuffle(t, rng?)` | `-> array` | |
| `Sample(t, size, rng?)` | `-> array` | Random sample. |
| `Flat(t, depth?)` | `-> array` | Flatten (default depth 1). |
| `FlatMap(t, callback)` | `-> array` | Map then flatten. |
| `Keys(t)` | `-> array` | |
| `Values(t)` | `-> array` | |
| `Find(t, callback)` | `-> (value?, key?)` | First match. |
| `Every(t, callback)` | `-> boolean` | |
| `Some(t, callback)` | `-> boolean` | |
| `Truncate(t, len)` | `-> array` | |
| `Zip(...)` | `-> iterator, table, startKey` | for-loop friendly. |
| `Lock(t)` | `-> t` | Deep `table.freeze`. |
| `IsEmpty(t)` | `-> boolean` | |
| `EncodeJSON(v)` / `DecodeJSON(s)` | `-> string/any` | Proxies for `HttpService`. |

**Gotchas:**

- `Sync` removes keys not in the template — never use it on profile data; use `Reconcile`.
- `Copy(t, true)` stack-overflows on cycles.

---

### 4.3 Option

**Require:** `local Option = require(game.ReplicatedStorage.Packages.Option)`
**Source:** `Packages/_Index/sleitnick_option@1.0.5/option/init.lua`
**Wally:** `sleitnick/option@1.0.5`
**Purpose:** Optional-value monad (Rust-style).

**API:**

| Method | Signature | Description |
|---|---|---|
| `Option.Some(value)` | `-> Option` | Wrap non-nil. |
| `Option.Wrap(value)` | `-> Option` | `Some` if not nil, else `None`. |
| `Option.None` | `Option` | Sentinel. |
| `Option.Is(obj)` | `-> boolean` | Type check. |
| `Option.Assert(obj)` | throws if not Option | Guard. |
| `Option.Serialize / Option.Deserialize` | `(any) -> data / data -> Option` | Round-trip across remotes. |
| `:Match({Some, None})` | `-> any` | Pattern match. |
| `:IsSome` / `:IsNone` | `-> boolean` | |
| `:Expect(msg)` / `:ExpectNone(msg)` | `-> value or throws` | |
| `:Unwrap` / `:UnwrapOr(default)` / `:UnwrapOrElse(fn)` | `-> value` | |
| `:And(other)` / `:AndThen(fn)` | `-> Option` | Chain on Some. |
| `:Or(other)` / `:OrElse(fn)` | `-> Option` | Chain on None. |
| `:XOr(other)` | `-> Option` | XOR. |
| `:Filter(predicate)` | `-> Option` | |
| `:Contains(value)` | `-> boolean` | |

---

### 4.4 Symbol

**Require:** `local Symbol = require(game.ReplicatedStorage.Packages.Symbol)`
**Source:** `Packages/_Index/sleitnick_symbol@2.0.1/symbol/init.lua`
**Wally:** `sleitnick/symbol@2.0.1`
**Purpose:** Unique sentinel values (for keys, markers, etc).

**API:** `Symbol(name: string?) -> Symbol`. Every call returns a NEW symbol even with identical names. Tostrings as `Symbol(name)`.

```luau
local DATA = Symbol("Data")
local t = { [DATA] = {} }
```

---

### 4.5 EnumList

**Require:** `local EnumList = require(game.ReplicatedStorage.Packages.EnumList)`
**Source:** `Packages/_Index/sleitnick_enum-list@2.1.0/enum-list/init.lua`
**Wally:** `sleitnick/enum-list@2.1.0`
**Purpose:** Frozen enum table.

**API:**

| Method | Signature | Description |
|---|---|---|
| `EnumList.new(name, {string})` | `-> EnumList` | Construct. |
| `:BelongsTo(obj)` | `-> boolean` | Membership test. |
| `:GetEnumItems()` | `-> {EnumItem}` | All. |
| `:GetName()` | `-> string` | Original name. |

Each EnumItem has `{Name, Value, EnumType}`.

```luau
local Dirs = EnumList.new("Dirs", {"Up", "Down"})
print(Dirs.Up.Value) --> 1
```

---

### 4.6 Tree

**Require:** `local Tree = require(game.ReplicatedStorage.Packages.Tree)`
**Source:** `Packages/_Index/sleitnick_tree@1.1.0/tree/init.lua`
**Wally:** `sleitnick/tree@1.1.0`
**Purpose:** Path-like instance traversal with class assertion.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Tree.Find(parent, path, assertIsA?)` | `-> Instance` (throws) | Slash-delimited path. |
| `Tree.Exists(parent, path, assertIsA?)` | `-> boolean` | |
| `Tree.Await(parent, path, timeout?, assertIsA?)` | `-> Instance` (yields, throws on timeout) | |

```luau
local frame = Tree.Find(PlayerGui, "HUD/StatsFrame", "Frame") :: Frame
```

**Gotchas:**

- `Tree.Await` with no timeout yields **indefinitely** — always pass a timeout in production code.

---

### 4.7 Ser

**Require:** `local Ser = require(game.ReplicatedStorage.Packages.Ser)`
**Source:** `Packages/_Index/sleitnick_ser@1.0.5/ser/init.lua`
**Wally:** `sleitnick/ser@1.0.5`
**Purpose:** Class-aware serialization used by Knit. Maps tables by `ClassName` to (de)serialize functions.

**API:**

| Method | Signature | Description |
|---|---|---|
| `Ser.Classes` | `{[ClassName] = {Serialize, Deserialize}}` | Extension hook. Ships with `Option`. |
| `Ser.Serialize(v)` / `Ser.Deserialize(v)` | `-> v` | Single value. |
| `Ser.SerializeArgs(...)` / `Ser.DeserializeArgs(...)` | `-> Args` | Pack n-args. |
| `Ser.SerializeArgsAndUnpack(...)` / `Ser.DeserializeArgsAndUnpack(...)` | `-> ...any` | Pack + unpack. |
| `Ser.UnpackArgs(args)` | `-> ...any` | Unpack args result. |

Rarely used directly — Knit consumes it internally.

---

## 5. Animation, Motion & Physics

### 5.1 Spring (sleitnick — 3D / numeric)

**Require:** `local Spring = require(game.ReplicatedStorage.Packages.Spring)`
**Source:** `Packages/_Index/sleitnick_spring@1.0.0/spring/init.luau`
**Wally:** `sleitnick/spring@1.0.0`
**Purpose:** Critically-damped spring wrapping `TweenService:SmoothDamp`. Supports `number`, `Vector2`, `Vector3`, `CFrame`.

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `Spring.new<T>(initial, smoothTime, maxSpeed?)` | `-> Spring<T>` | `smoothTime` ~= time to reach target. `maxSpeed` defaults to `math.huge`. |
| `.Current` | `T` | Current value (read after `:Update`). |
| `.Target` | `T` | Mutate to retarget. |
| `.Velocity` | `T` | Read-only state, may write to zero. |
| `.SmoothTime` | `number` | Adjustable at runtime. |
| `.MaxSpeed` | `number` | Adjustable. |
| `:Update(dt)` | `-> T` | Advance one step; returns new `Current`. |
| `:Impulse(velocity)` | `-> ()` | Add to velocity. |
| `:Reset(value)` | `-> ()` | Snap both Current and Target. |

**Usage:**

```luau
local s = Spring.new(Vector3.zero, 0.2)
RunService.RenderStepped:Connect(function(dt)
    s.Target = mouseWorldPos
    part.Position = s:Update(dt)
end)
```

**Gotchas:**

- **Use Spring over TweenService for 3D / numeric motion** (CLAUDE.md). TweenService is fine only for one-shot transparency fades on temporary instances.
- Spring requires polling every frame. For one-off discrete tweens, TweenService still wins.
- `CFrame` springs interpolate position AND rotation — `:Reset` to a `CFrame` to clear both.

---

### 5.2 Shake

**Require:** `local Shake = require(game.ReplicatedStorage.Packages.Shake)`
**Source:** `Packages/_Index/sleitnick_shake@1.1.0/shake/init.lua`
**Wally:** `sleitnick/shake@1.1.0`
**Purpose:** Perlin-noise shake (camera, part, gui).

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `Shake.new()` | `-> Shake` | Construct (all props at defaults). |
| `Shake.InverseSquare(vector, distance)` | `-> Vector3` | Scale shake by `1/d^2`. |
| `Shake.NextRenderName()` | `-> string` | Unique `__shake_NNNN__`. |
| `.Amplitude` | `number = 1` | Magnitude scale. |
| `.Frequency` | `number = 1` | Noise frequency. |
| `.FadeInTime` / `.FadeOutTime` | `number = 1` | Ramp seconds. |
| `.SustainTime` | `number = 0` | Plateau seconds (after fade-in). |
| `.Sustain` | `boolean = false` | Hold indefinitely until `:StopSustain`. |
| `.PositionInfluence` | `Vector3 = Vector3.one` | Multiplier on positional output. |
| `.RotationInfluence` | `Vector3 = (0.1,0.1,0.1)` | Multiplier on rotational output. |
| `.TimeFunction` | `() -> number` | `time` in-game, `os.clock` in tests. |
| `:Start()` | `-> ()` | Begin. Must be called before `:Update` / signals. |
| `:Stop()` | `-> ()` | Stop + unbind all bound steps / signals. |
| `:StopSustain()` | `-> ()` | Triggers fade-out for sustain-mode shakes. |
| `:IsShaking()` | `-> boolean` | Status. |
| `:Update()` | `-> (Vector3 pos, Vector3 rot, boolean isDone)` | Compute one frame. |
| `:OnSignal(signal, cb)` | `-> connection` | `cb(pos, rot, isDone)` per fire. |
| `:BindToRenderStep(name, priority, cb)` | `-> ()` | `cb(pos, rot, isDone)` per step. |
| `:Clone()` | `-> Shake` | New Shake with same config (not running). |
| `:Destroy()` | `-> ()` | Stop + clean. |

**Usage:**

```luau
local s = Shake.new()
s.Amplitude = 2
s.FadeInTime = 0.1
s.SustainTime = 0.3
s.FadeOutTime = 0.5
s:BindToRenderStep(Shake.NextRenderName(), Enum.RenderPriority.Camera.Value, function(pos, rot)
    camera.CFrame = camera.CFrame * CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
end)
s:Start()
```

**Gotchas:**

- `:Update` returns `isDone` — once true, the shake is over and you should `:Stop`.
- `:Stop` unbinds everything bound through `:OnSignal` / `:BindToRenderStep`. Reconnect after starting again.

---

### 5.3 Streamable

**Require:** `local Streamable = require(game.ReplicatedStorage.Packages.Streamable).Streamable` (the package returns `{Streamable, StreamableUtil}`).
**Source:** `Packages/_Index/sleitnick_streamable@1.2.4/streamable/{Streamable,StreamableUtil}.lua`
**Wally:** `sleitnick/streamable@1.2.4`
**Purpose:** Observe an instance whose existence is intermittent (StreamingEnabled, dynamically created children).

**Streamable API:**

| Method | Signature | Description |
|---|---|---|
| `Streamable.new(parent: Instance, childName: string)` | `-> Streamable` | Watch `parent:FindFirstChild(childName)`. |
| `Streamable.primary(parent: Model)` | `-> Streamable` | Watch `parent.PrimaryPart`. |
| `:Observe(handler: (instance, janitor) -> ())` | `-> Connection` | Called every time the instance becomes available; janitor is cleaned when it goes away. |
| `:Destroy()` | `-> ()` | Tear down. |

**StreamableUtil:**

| Method | Signature | Description |
|---|---|---|
| `StreamableUtil.Compound(streamables: {Streamable}, handler: (instances, janitor) -> ())` | `-> ()` | Calls handler only when ALL listed streamables resolve simultaneously. |

**Usage:**

```luau
local s = Streamable.new(workspace, "Sword")
s:Observe(function(sword, janitor)
    janitor:Add(sword.Touched:Connect(onTouched))
end)
```

---

## 6. UI Libraries (client-only)

### 6.1 UIAnimator (Twinkle) — vendored

**Require:** `local UIAnimator = require(game.ReplicatedStorage.Client.Packages.UIAnimator)`
**Source:** `src/Client/Client/Packages/UIAnimator/{init,Presets/Hover/*,Presets/Press/*,Presets/Text/*,GradientTemplates/*}.luau`
**Vendored — not on Wally. Internal dep: Trove (Wally) + EZVisualz (Wally).**
**Purpose:** **Default UI animation library.** Drives hover/press, slide/zoom/fade panels, text effects, ambient effects (blur, camera tween, ripple).

**Important: client-only — never `require` on the server.**

**Functions (public):**

| Method | Signature | Description |
|---|---|---|
| `UIAnimator.SetButtonStyle(element, {hoverType, pressType, scalePercent})` | hoverType in `"Lift" \| "Bounce" \| "Grow"`; pressType in `"Shrink" \| "Punch"` | Override defaults on a single button. Re-runs `animateHover` immediately. |
| `UIAnimator.FrameZoom(element, show, speed?, blur?, hideOtherUi?, startSize?, customEndPosition?)` | `boolean show` | Zooms element to/from `startSize` (default zero UDim2). Honors `OriginalSize`/`PreservePosition`/`CustomStartSize`/`CustomEndSize` attributes. |
| `UIAnimator.Fade(element, show, speed?, blur?, hideOtherUi?, customTweenInfo?)` | fades self + descendants | Caches original transparencies as attributes. |
| `UIAnimator.FrameSlide(element, show, speed?, fadeIn?, blur?, hideOtherUi?, resetOgPos?, customStartPos?, customEndPos?, customTweenInfo?)` | slide | Honors `CustomStartPos`/`CustomEndPos` attributes. |
| `UIAnimator.FrameBounce(element, speed?, bouncePercent?)` | scale up then back down | Caches `OriginalSize` attribute. |
| `UIAnimator.FadeSlideRunoff(element, speed?, blur?, hideOtherUi?, runOffAtEnd?, customStartPos?, customEndPos?, customTweenInfo?)` | show, slide in, slide further off | One-shot announce animation. |
| `UIAnimator.Sequence(steps, options?)` | `steps: {{fn, args} \| {wait = n} \| {parallel = true}}`, `options: {parallel?, onComplete?}` | Chain animations. Append `{parallel = true}` after a step to run it without blocking next step. |
| `UIAnimator.ShowText(container, label, text?, options?)` | `options: {effect?, interval?, speed?, intensity?, onComplete?}` | Animate text reveal char-by-char. |
| `UIAnimator.SetCameraProps({fovIn?, position?, rotation?})` | configure | Camera zoom that runs when `applyEntryEffects` fires (every `Frame*` animation triggers this). |
| `UIAnimator.SetBlurSize(size?)` | `number` | Default 15. |
| `UIAnimator.RegisterIcon(icon, frameName)` | bookkeeping | TopbarPlus icon registry. |

**Hover presets:** Bounce, Grow, Lift, Shine, Tilt (`Presets/Hover/`).
**Press presets:** Punch, Shrink (`Presets/Press/`).
**Text effects:** Typewriter (default), Jitter, PlopIn, Bubbly, Glitch, FadeIn (`Presets/Text/`).

**Tag-driven automatic behaviors (configured via `CollectionService`):**

- `"Animatable"` — wires hover + press presets on the tagged button.
- `"HideableUI"` — toggled when `hideOtherUi=true` is passed.
- `"SpecialEffects"` — applies `EZVisualz.new(item, EffectType, EffectSpeed, EffectSize, EffectReversed, EffectColor)` using element attributes.
- `"SpinUI"` — endlessly rotates the element via TweenService.
- `"SpinGradient"` — rotates a UIGradient continuously by `RotateSpeed` attribute.
- `"ResponsiveText"` — clamps `TextSize` to viewport scale, listens for ViewportSize changes.

**Element attributes consumed:**

`HoverType, PressType, HoverIntensity, PressIntensity, ScalePercent, Speed, Blur, HideUI, OriginalSize, OriginalBGTransparency, OriginalTextTransparency, OriginalImageTransparency, OriginalStrokeTransparency, CustomStartPos, CustomEndPos, CustomStartSize, CustomEndSize, PreservePosition, EffectType, EffectSpeed, EffectSize, EffectColor, EffectReversed, MinTextSize, MaxTextSize, RotateSpeed`.

**Sounds:** Automatically plays `SoundService.SFX.UI_Hover` / `UI_Click` on buttons under PlayerGui. Adds `AudioConnected` attribute.

**Module-level attributes:** `RippleEnabled`, `RippleColor`, `RippleSize`, `RippleFadeTime` on the UIAnimator script (set in Studio to tune the click ripple).

**Usage:**

```luau
local UIAnimator = require(game.ReplicatedStorage.Client.Packages.UIAnimator)

-- Show
UIAnimator.FrameZoom(panel, true, 0.4, true)

-- Hide
UIAnimator.FrameZoom(panel, false, 0.3)

-- Sequence
UIAnimator.Sequence({
    { fn = UIAnimator.Fade,        args = { hud, false, 0.2 } },
    { wait = 0.5 },
    { fn = UIAnimator.FrameZoom,   args = { popup, true, 0.4 } },
}, { onComplete = function() print("done") end })

-- Style button (instead of CollectionService tag)
UIAnimator.SetButtonStyle(button, { hoverType = "Bounce", pressType = "Punch" })

-- Text reveal
UIAnimator.ShowText(container, label, "Welcome!", { effect = "Typewriter", interval = 0.04 })
```

**Gotchas:**

- **Client only.** Requiring on the server crashes — UIAnimator references `Players.LocalPlayer:WaitForChild("PlayerGui")` at module load.
- The module **prints** a vanity message on load (`This game uses the Twinkle (UI animator) module...`). It is intentional; do not remove.
- The hover preset modules call `UIUtil.centerAnchor(element)` — without `Packages.UIUtil.luau` present this throws. The shim is included; do not delete.
- `Fade` / `FrameSlide` etc. **call `:Wait` on their final tween** — they yield. Wrap in `task.spawn` for fire-and-forget.
- `applyEntryEffects` always runs the camera tween (FOV->60 or `cameraProps.fovIn`). To disable, call `UIAnimator.SetCameraProps({})` or omit the side-effect call (currently no toggle — pass through `Fade` with `blurEnabled=false` and accept the FOV change). If undesired, edit `setCamera`.
- `Sequence` uses `{parallel}` AFTER a `{fn, args}` step to fire-and-forget that prior step. Standalone `{parallel}` does nothing.

---

### 6.2 UIUtil — shim (centerAnchor helper)

**Require:** `local UIUtil = require(game.ReplicatedStorage.Client.Packages.UIUtil)`
**Source:** `src/Client/Client/Packages/UIUtil.luau`
**Vendored — not on Wally.**
**Purpose:** Tiny utility for the vendored UIAnimator presets.

**API:**

| Method | Signature | Description |
|---|---|---|
| `UIUtil.centerAnchor(element: GuiObject)` | `-> ()` | Sets `AnchorPoint` to `(0.5, 0.5)` and shifts `Position` so visual location is unchanged. No-op if already centered. |

**Gotchas:**

- Required by UIAnimator's hover/press presets — never delete or rename.

---

### 6.3 ExpressivePrompts

**Require:** `local ExpressivePrompts = require(game.ReplicatedStorage.Packages.ExpressivePrompts)`
**Source:** `Packages/_Index/miagobble_expressive-prompts@1.1.4/expressive-prompts/init.luau`
**Wally:** `miagobble/expressive-prompts@1.1.4` (lockfile bump from wally.toml's `1.0.0`)
**Purpose:** Replace the default ProximityPrompt UI with a custom, animated one. **Project default** — never use the built-in prompt UI.

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `ExpressivePrompts.Init()` | `-> ()` | Call **once** (typically from a top-level client controller). Subscribes to `ProximityPromptService.PromptShown`. |
| `ExpressivePrompts.Config` | table of Seam `Value(...)` reactive states | Mutate `.Value` on any entry to retune at runtime. |

**Reactive config (set via `.Value`):**

| Key | Default | Purpose |
|---|---|---|
| `BackgroundTransparency` | `0.5` | Main frame transparency |
| `BackgroundColor` | dark grey | |
| `TextColor` / `SubTextColor` | white / mid-grey | |
| `CornerRadius` | `16` (UDim offset units used by source) | |
| `MainSizeSpringSpeed` / `MainSizeSpringDampening` | `20 / 0.4` | Main frame size spring |
| `MainRotationSpringSpeed` / `MainRotationSpringDampening` / `MainRotationStrength` | `30 / 0.1 / 5` | Wiggle |
| `AspectRatioSpringSpeed` / `AspectRatioSpringDampening` | `20 / 0.4` | |
| `ProgressBarYScale` | `0.1` | |
| `ProgressBarColor` / `ProgressBarTransparency` | white / `0.5` | |
| `ShowShimmer` | `true` | |
| `GuiOffsetSpringSpeed` / `GuiOffsetSpringDampening` | `15 / 0.5` | StudsOffset animation |
| `PromptHeight` / `PromptWidth` | `72 / 72` | |
| `TextPaddingLeft` | `72` | |
| `ActionTextSize` / `ObjectTextSize` | `19 / 14` | |
| `ActionTextFont` / `ObjectTextFont` | `Gotham Medium` | |
| `ActionTextYOffset` | `9` | |
| `MiddlePadding` | `24` | |
| `AppearSoundId` / `ClickSoundId` / `HoldSoundId` / `TriggerSoundId` / `SoundVolume` | from `SoundData` module | Pre-bound sounds |

**Usage:**

```luau
local Prompts = require(game.ReplicatedStorage.Packages.ExpressivePrompts)
Prompts.Init()
Prompts.Config.BackgroundColor.Value = Color3.fromRGB(20, 30, 60)
```

**Gotchas:**

- `Init` warns and no-ops on repeat calls — safe to call from multiple controllers but only the first wins.
- Config values are Seam-reactive — set `.Value`, do not reassign the key on the table.
- ExpressivePrompts requires prompts to have `Style = Enum.ProximityPromptStyle.Custom`. The init swaps `Default` style to `Custom` on first show — but explicitly use `Custom` upstream for predictability.

---

### 6.4 TopbarPlus

**Require:** `local Icon = require(game.ReplicatedStorage.Packages.TopbarPlus)`
**Source:** `Packages/_Index/1foreverhd_topbarplus@3.4.0/topbarplus/src/init.lua`
**Wally:** `1foreverhd/topbarplus@3.4.0`
**Purpose:** Topbar icon system (Roblox new-style menus).

**Module API (selected):**

| Method | Signature | Description |
|---|---|---|
| `Icon.new()` | `-> Icon` | Construct. |
| `Icon.getIcons()` | `-> {Icon}` | All. |
| `Icon.getIcon(nameOrUID)` | `-> Icon?` | Lookup. |
| `Icon.setTopbarEnabled(bool)` | `-> ()` | Global toggle. |
| `Icon.modifyBaseTheme(modifications)` | `-> ()` | Apply theme override to every Icon created after. |
| `Icon.setDisplayOrder(int)` | `-> ()` | Topbar ScreenGui DisplayOrder. |

**Icon instance methods (high-traffic ones):**

| Method | Signature | Description |
|---|---|---|
| `:setName(name)` | name | Identifier. |
| `:setLabel(text, iconState?)` | text | Caption text. |
| `:setImage(imageId, iconState?)` | id | Icon image. |
| `:setOrder(int, iconState?)` | n | Horizontal order. |
| `:setCornerRadius(udim, iconState?)` | udim | Radius. |
| `:align("Left" \| "Center" \| "Right")` / `:setLeft()` / `:setMid()` / `:setRight()` | | Alignment helper. |
| `:setEnabled(bool)` | | Toggle. |
| `:select()` / `:deselect()` | | Programmatic toggle. |
| `:notify(customClearSignal?, noticeId?)` | | Notification badge. |
| `:clearNotices()` | | Drop all badges. |
| `:setCaption(text)` / `:setCaptionHint(keyCodeEnum)` | | Hover tooltip. |
| `:bindToggleItem(guiObject)` | | Auto-show/hide a GUI on select/deselect. |
| `:bindToggleKey(keyCode)` | | Keyboard shortcut. |
| `:bindEvent(eventName, fn)` | | Hook events (`selected`, `deselected`, `toggled`, `viewingStarted`, `viewingEnded`, `notified`, ...). |
| `:setMenu(arrayOfIcons)` / `:setDropdown(arrayOfIcons)` | | Submenu. |
| `:joinMenu(parentIcon)` / `:joinDropdown(parentIcon)` | | Add to existing menu. |
| `:oneClick(bool)` / `:autoDeselect(bool)` / `:debounce(seconds)` | | Behavior toggles. |
| `:lock()` / `:unlock()` | | Disable interaction. |
| `:destroy()` | | Cleanup. |

**Icon signals (subscribe via `.selected:Connect(fn)` or `:bindEvent`):**

`selected, deselected, toggled, viewingStarted, viewingEnded, stateChanged, notified, noticeStarted, noticeChanged, endNotices, toggleKeyAdded, fakeToggleKeyChanged, alignmentChanged, updateSize, resizingComplete, joinedParent, menuSet, dropdownSet, updateMenu, startMenuUpdate, childThemeModified, indicatorSet, dropdownChildAdded, menuChildAdded`.

**Usage:**

```luau
local Icon = require(game.ReplicatedStorage.Packages.TopbarPlus)
local shop = Icon.new()
    :setName("Shop")
    :setImage(123456789)
    :setLabel("Shop")
    :bindToggleKey(Enum.KeyCode.B)
    :bindToggleItem(playerGui.ShopGui)

shop.selected:Connect(function() print("opened") end)
```

**Gotchas:**

- Icons are Roblox `Janitor`-backed; call `:destroy()` to free them.
- Theme/modification IDs need to be unique strings if you want to remove specific overrides via `:removeModification`.

---

## 7. VFX & Particles

### 7.1 EZVisualz

**Require:** `local EZVisualz = require(game.ReplicatedStorage.Packages.EZVisualz)`
**Source:** `Packages/_Index/arxkdev_ezvisualz@0.0.6/ezvisualz/init.luau`
**Wally:** `arxkdev/ezvisualz@0.0.6`
**Purpose:** UI visual effects (animated UIGradient / UIStroke / Dropshadow combos) applied to a GuiObject.

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `EZVisualz.new(uiInstance, effectType, speed?, size?, saveInstanceObjects?, customColor?, customTransparency?, resumesOnVisible?)` | `-> Effect` | Construct. `effectType` is a preset name (see list below). |
| `EZVisualz.Gradient` | module | Direct-construct primitives. |
| `EZVisualz.Stroke` | module | Direct-construct primitives. |
| `EZVisualz.Dropshadow` | module | Direct-construct primitives. |
| `EZVisualz.Templates` | table | Preset gradient sequences. |
| `EZVisualz.CurrentEffects` | table | Bookkeeping. |
| `:Pause()` / `:Resume()` / `:Destroy()` | `-> ()` | Effect lifecycle. |

**Effect presets (`effectType`):**

`Bubblegum, ChromeStroke, DeathStroke, FireStroke, Ghost, GhostStroke, Gold, GoldStroke, GreenOutline, IceStroke, Lava, LavaStroke, Matrix, OceanicStroke, Rainbow, RainbowOutline, RainbowStroke, Shine, ShineOutline, Silver, SilverStroke, WaveStroke, Zebra`.

**Default args:** `speed = 0.007`, `size = 1`, `resumesOnVisible = true`.

**Usage:**

```luau
local fx = EZVisualz.new(label, "Rainbow", 0.01, 1.5)
-- later
fx:Destroy()
```

**Gotchas:**

- `saveInstanceObjects = true` removes preexisting `UIGradient`/`UIStroke` children before applying the effect; original instances are restored on `:Destroy`.
- The effect auto-destroys when the target leaves the DataModel.
- UIAnimator's `SpecialEffects` tag (via `EffectType` attribute) calls into this — don't double-apply.

---

### 7.2 Emitter2D — vendored

**Require:** `local Emitter2D = require(game.ReplicatedStorage.Client.Packages.Emitter2D)`
**Source:** `src/Client/Client/Packages/Emitter2D/Emitter2D.luau` + `script.Emitter` child Instance template.
**Vendored — plugin-driven, not Wally. Client-only.**
**Purpose:** GUI-space 2D particle emitter.

**API:**

| Method / Field | Signature | Description |
|---|---|---|
| `Emitter2D.new()` | `-> Emitter` | Construct empty emitter. |
| `:Initiate(Config: Configuration)` | `-> ()` | Hook to a Configuration child (from the plugin). `Config:GetAttribute("Version")` must be <= installed module version. |
| `:Update(Delta)` | `-> ()` | Advance one frame (called automatically via RenderStepped). |
| `:SpawnParticle(Position, Velocity)` | `-> ParticleData` | Force-spawn one. |
| `:RemoveParticle(ParticleData, NoCache?)` | `-> ()` | Manual remove. |
| `:ClearAllParticles(NoCache?)` | `-> ()` | Wipe. |
| `:Destroy()` | `-> ()` | Tear down. |
| `Emitter2D.disconnectGlobalEvents()` | `-> ()` | Stops the module's global RunService binding. |
| `Emitter2D.PlayerGui` | Instance | Where particle GUIs are parented; overridable in plugin/edit mode. |
| `Emitter2D.GlobalEnabled` | `boolean` | Toggle. |
| `Emitter2D.Particles` / `Emitter2D.ParticleFolders` | tables | Live bookkeeping. |

**Usage:**

```luau
local Emitter2D = require(game.ReplicatedStorage.Client.Packages.Emitter2D)
local emitter = Emitter2D.new()
emitter:Initiate(workspace.Sparkles_Config)        -- Configuration Instance
emitter:SpawnParticle(UDim2.fromScale(0.5, 0.5), Vector2.new(0, -300))
```

**Gotchas:**

- Requires `ReplicatedStorage:GetAttribute("Emitter2D_Version")` to be a `number` — the boilerplate's `init.client.luau` sets it. If missing, the module **yields indefinitely** waiting for the attribute. Make sure your client boot path runs after that init script.
- The template Instance `script.Emitter` must exist — do not delete it.
- Config Instances are usually created via the Emitter2D Roblox Studio plugin.
- Version mismatch (Emitter Config attribute > installed module version) **errors**. Reinstall the plugin to upgrade.

---

## 8. World / Region Detection

### 8.1 ZonePlus

**Require:** `local Zone = require(game.ReplicatedStorage.Packages.ZonePlus)`
**Source:** `Packages/_Index/mattschrubb_zoneplus@3.2.0/zoneplus/init.lua`
**Wally:** `mattschrubb/zoneplus@3.2.0`
**Purpose:** Region detection for parts, players, items.

**Module API:**

| Method | Signature | Description |
|---|---|---|
| `Zone.new(container: Model \| Folder \| BasePart \| {Instance})` | `-> Zone` | Construct. |
| `Zone.fromRegion(cframe, size)` | `-> Zone` | Build a temporary container model for an arbitrary cuboid. |
| `Zone.enum` | `{Accuracy, Detection}` | EnumLike sets. |

**Zone instance fields:**

| Field | Type / Default | Description |
|---|---|---|
| `.accuracy` | `enum.Accuracy.High` | High/Medium/Low/Precise. |
| `.autoUpdate` | `true` | Recompute on container change. |
| `.respectUpdateQueue` | `true` | Batch updates. |
| `.enterDetection` / `.exitDetection` | `enum.Detection.Centre` | Centre/WholeBody. |
| `.zoneParts` | `{BasePart}` | Resolved zone parts. |
| `.overlapParams` | `{OverlapParams}` | Internal. |
| `.updated` | `Signal` | Fired on recompute. |
| `.playerEntered` / `.playerExited` | `Signal<Player>` | Server/Client. |
| `.partEntered` / `.partExited` | `Signal<BasePart>` | |
| `.localPlayerEntered` / `.localPlayerExited` | `Signal<>` | Client-only. |
| `.itemEntered` / `.itemExited` | `Signal<Instance>` | For `:trackItem`'d items. |

**Methods (selected):**

| Method | Signature | Description |
|---|---|---|
| `:findLocalPlayer()` | `-> boolean` | Client-only. |
| `:findPlayer(player)` | `-> boolean` | |
| `:findItem(item)` | `-> boolean` | |
| `:findPart(part)` | `-> (boolean, parts?)` | |
| `:findPoint(positionOrCFrame)` | `-> (boolean, parts?)` | |
| `:getPlayers()` / `:getItems()` / `:getParts()` | `-> {...}` | Snapshot. |
| `:getRandomPoint()` | `-> Vector3` | |
| `:setAccuracy(enumIdOrName)` | `-> ()` | |
| `:setDetection(enumIdOrName)` | `-> ()` | |
| `:trackItem(instance)` | `-> ()` | Enables item entered/exit signals. |
| `:untrackItem(instance)` | `-> ()` | |
| `:bindToGroup(name)` / `:unbindFromGroup()` | `-> ()` | Cross-zone exclusivity groups. |
| `:relocate()` | `-> ()` | Move container to a hidden world model (used by `fromRegion`). |
| `:onItemEnter(...)` / `:onItemExit(...)` | `-> ()` | Convenience hooks. |
| `:destroy()` | `-> ()` | Cleanup. |

**Usage:**

```luau
local zone = Zone.new(workspace.SafeZone)
zone:setDetection(zone.enum.Detection.WholeBody)
zone.localPlayerEntered:Connect(function() print("in safe zone") end)
zone.localPlayerExited:Connect(function() print("left") end)
```

**Gotchas:**

- `.localPlayerEntered` errors if connected from a server context — `:findLocalPlayer` also throws server-side.
- Signals fire as soon as the first `:Connect` exists (a checker loop starts then). Connecting and disconnecting repeatedly is wasteful — keep a stable connection per zone.
- `Zone.fromRegion` creates a Model parented to nil; call `zone:relocate()` to move it out of workspace if you need physics neutrality.

---

## 9. Project Surfaces (cross-reference only — full docs in architecture.md)

### 9.1 DataService

The stable public API for both ProfileStore and Mad Studio Replica. **Always go through DataService** when you need to read/mutate player data. See `architecture.md § DataService API` for full method list and the no-yield-in-bridge enforcement pattern.

### 9.2 Bridges registry

Bridges live in `src/Shared/Shared/Bridges.luau`. Read its header comment for the action-name and payload-shape conventions before adding a bridge.

### 9.3 PlayerData (client wrapper)

Client wrapper around the local player's replica. See `architecture.md § Require Paths`.

### 9.4 Sequence (async sequencer)

Project's canonical chainable async sequencer. Compose ordered/parallel/event-wait steps with one `:Run()`; cancel via `:Bind(janitor)` or `:Cancel()`. Full method table + examples in § 3.9 Sequence. Use this instead of rolling your own `task.spawn`/`task.delay`/`task.cancel` chain.

---

### 9.5 Project — ReplicaController (Knit controller)

**Location:** `src/Client/Client/Controllers/ReplicaController.luau`
**NOT a package** — this is a project Knit controller under `Client/Controllers/`.
**Require (other controllers only):** `local RC = Knit.GetController("ReplicaController")`
**Purpose:** Centralises client-side subscriptions to **non-PlayerData** replicas (world state, entity state, shared multiplayer state). The local player's replica is already handled by `PlayerData.luau` — use `ReplicaController` for every other token.

Wraps `Replica.OnNew(token, ...)` from Mad Studio Replica client (§ 2.3). Internally maintains a `_replicasByToken` cache populated on arrival and pruned via `replica.Maid:Add` on destroy. One Janitor per token, nested under a controller-scope Janitor.

**Public API:**

| Method | Signature | Description |
|---|---|---|
| `:OnReplicaNew` | `(token: string, listener: (replica) -> ()) -> {Disconnect: () -> ()}` | Register a listener for all replicas of `token`. Fires for already-existing replicas (deferred replay). Returns a disconnectable connection. No yield in `listener` — `task.spawn` async work. |
| `:GetReplicasByToken` | `(token: string) -> {Replica}` | Live snapshot (shallow copy) of all currently-active replicas for the token. |
| `:CleanupToken` | `(token: string) -> ()` | Drop all listeners and cached refs for a token. Idempotent. |

**Usage (WorldAnimator-style binding):**

```luau
-- Inside WorldAnimator/init.luau (KnitStart or after KnitStart resolves)
local Knit = require(game.ReplicatedStorage.Packages.Knit)

local WorldAnimator = {}

function WorldAnimator:Initialize()
    local RC = Knit.GetController("ReplicaController")

    RC:OnReplicaNew("WorldEntity", function(replica)
        -- replica.Data is the initial server state
        local model = workspace:FindFirstChild(replica.Tags.ModelName)
        if not model then
            warn("[WorldAnimator] no model for WorldEntity:", replica.Tags.ModelName, "— skipping")
            return
        end

        -- React to authoritative state changes; no yield permitted here
        replica:OnSet({"animating"}, function()
            task.spawn(function()
                -- play hover / glow animation on `model`
            end)
        end)

        -- Prune UI/animation state when the entity is removed
        replica.Maid:Add(function()
            -- tear down model highlights, etc.
        end)
    end)
end

return WorldAnimator
```

**Gotchas:**

- `listener` passed to `:OnReplicaNew` MUST NOT yield. Fire a `Signal` or `task.spawn` if the callback body needs to yield.
- `:CleanupToken` disconnects ALL `:OnReplicaNew` connections registered for that token. Call it only when you truly want to drop every subscriber (e.g. on a round reset).
- `KnitStart` calls `Replica.RequestData()` (idempotent — safe even if `PlayerData.Init()` already called it).
- Use `replica:OnSet(path, cb)` for specific-path changes and `replica:OnChange(cb)` for catch-all. `ListenToChange` does NOT exist in Mad Studio Replica (§ 2.3 Gotchas).

---

### 9.6 Project — SoundController (Knit controller)

**Location:** `src/Client/Client/Controllers/SoundController/` (init.luau + Layered.luau, Counting.luau, Presets.luau).
**NOT a package** — this is a project Knit controller under `Client/Controllers/`.
**Require (other controllers only):** `local SC = Knit.GetController("SoundController")`
**Purpose:** **MANDATORY canonical client sound entry point.** Every client-side audio call MUST go through this controller — never `:Play()` a Sound instance directly, never duplicate the dot-path resolver, never roll your own clone pool. The controller centralises sound resolution, clone pooling, category volume scaling, layered playback, and pitched count sequences.

**Name resolver (`resolveSound`):** dot-path supported. Lookup priority for `name`:

1. `SoundService.SFX.<a>.<b>.<name>` — full dot-path under SFX (deepest match wins).
2. `SoundService.SFX.<name>` — last segment only under SFX root (fallback when a sub-folder miss occurred).
3. `SoundService.Music.<a>.<b>.<name>` — full path under Music.
4. `SoundService.Events.<a>.<b>.<name>` — full path under Events.

A miss returns `(nil, nil)` and `:Play` returns a no-op `SoundHandle` (warns once per miss per rule_8). See `architecture.md § Sound runtime path` for the runtime layout.

**Public API:**

| Method | Signature | Description |
|---|---|---|
| `:Play` | `(name: string, opts: PlayOpts?) -> SoundHandle` | Resolves `name`, clones the source Sound (clones come from a per-category, per-template idle pool of cap 8), applies opts, plays, and returns a SoundHandle. Returns a no-op handle on resolver miss. |
| `:PlayLayered` | `(names: {string}, opts: PlayOpts?) -> {SoundHandle}` | Plays N sounds simultaneously via `Layered.luau`. Returns `{ groupHandle, h1, h2, ... }` — index `[1]` is a wrapper whose `Stop()`/`SetPitch()`/`SetVolume()` fans out to all constituents; indices `[2..N+1]` are the per-sound handles. |
| `:StopAll` | `(category: ("SFX" \| "Music" \| "Events")?) -> ()` | Stops every active clone. If `category` is provided, only stops handles in that category. |
| `:GetCategoryVolume` | `(category: "SFX" \| "Music" \| "Events") -> number` | Returns the current volume multiplier (clamped 0–10). |
| `:SetCategoryVolume` | `(category: "SFX" \| "Music" \| "Events", value: number) -> ()` | Sets the multiplier. Does NOT retroactively re-scale currently-playing clones; takes effect on the next `:Play`. |
| `:CountTo` | `(opts: CountOpts) -> CountHandle` | Spawns a pitched tick sequence via `Counting.luau`. See cadence + pitch maths below. |

**Type shapes:**

```luau
type PlayOpts = {
    volume: number?,    -- 0..1 scale; overrides source.Volume before category multiplier
    pitch:  number?,    -- defaults to source.Pitch
    looped: boolean?,   -- defaults to source.Looped
    parent: Instance?,  -- optional reparent (for 3D positional sounds — clone is destroyed instead of pooled when parent set)
}

type SoundHandle = {
    Stop:      () -> (),
    SetPitch:  (p: number) -> (),
    SetVolume: (v: number) -> (),
    Instance:  Sound?,                 -- the active clone; nil on miss
    OnEnded:   (() -> ())?,            -- assignable callback fired on Sound.Ended
}

type CountOpts = {
    from:         number,
    to:           number,
    totalSeconds: number,
    soundName:    string?,                  -- defaults "UI.Counting"
    basePitch:    number?,                  -- defaults 1.0
    easing:       ("Slow" | "Fast")?,       -- defaults "Slow"
}

type CountHandle = {
    Cancel:      () -> (),
    IsPlaying:   () -> boolean,
    SetProgress: (t: number) -> (),         -- 0..1; aligns next tick to ratio (used by Countdown pairing)
}
```

**CountTo cadence + pitch maths:**

- `totalTicks = math.max(2, math.floor(totalSeconds / 0.06))` (~16 ticks/sec base).
- Cadence (per-tick interval, lerped over `MIN=0.04s` ↔ `MAX=0.18s` against tick ratio `t = i/totalTicks`):
  - `easing = "Slow"` (default, count-down feel): `interval = lerp(MIN, MAX, t)` — starts fast, slows toward target.
  - `easing = "Fast"` (count-up feel): `interval = lerp(MAX, MIN, t)` — starts slow, accelerates.
- Pitch ramp (`basePitch * pitchScale`):
  - count-up (`from < to`): `pitchScale = lerp(0.7, 1.5, t)` — low → high.
  - count-down (`from > to`): `pitchScale = lerp(1.5, 0.7, t)` — high → low.
  - flat (`from == to`): `pitchScale = 1.0`.
- `SetProgress(t)` clamps `t` to 0..1 and snaps the internal tick index to `math.floor(t * totalTicks)` on the next loop iteration (`Countdown.luau` uses this to keep CountTo's pitch tracking the displayed number, not elapsed time).

**Usage:**

```luau
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local SC   = Knit.GetController("SoundController")

-- One-shot SFX with overrides.
local h = SC:Play("UI.Click", { volume = 0.6, pitch = 1.1 })

-- Listen for natural end.
h.OnEnded = function() print("click done") end

-- Layered SFX — stop the whole group together.
local handles = SC:PlayLayered({ "UI.Click", "Reward.Sparkle" }, { volume = 0.8 })
task.delay(2, function() handles[1].Stop() end)

-- Category volume duck.
SC:SetCategoryVolume("Music", 0.3)

-- Pitched tick sequence paired with a UIAnimator:Countdown.
local count = SC:CountTo({
    from = 10, to = 0,
    totalSeconds = 3,
    soundName = "HeavyCountdown",
    easing = "Slow",
})
-- Later: count.SetProgress(0.5)
```

**Gotchas:**

- **NEVER `:Play()` a Sound instance directly.** All client audio goes through `SoundController:Play`. The pool, category scaling, and category-wide `:StopAll` all depend on it.
- The clone pool keys on `source:GetFullName()`. If you reparent a template Sound at runtime, you'll fragment the pool — don't.
- `:Play` with `opts.parent` set bypasses the pool's return path — the clone is destroyed on Ended instead of pooled. Use `parent` only for 3D positional one-shots.
- `:SetCategoryVolume` does not retro-scale active clones (intentional — avoids zipper-like artefacts mid-play). Call it before triggering the next category-heavy burst.
- `OnEnded` is an ASSIGNABLE field on the handle, not a signal — set it before the sound finishes or you'll miss it. Looped sounds never fire it.
- `Presets.luau` ships intentionally empty — add entries as the project accretes sounds. Do not add presets whose Sound assets don't yet exist in Studio.
- Resolution is silent on partial-path hits — `"UI.Click"` matches `SFX/UI/Click` AND `SFX/Click` (fallback 2). If two sounds with the same leaf name exist under different folders, the SFX-sub-path match (1) wins. Audit your Studio tree before relying on the fallback.

See also: § 6.1 UIAnimator (Twinkle package — distinct from § 9.8 below), § 9.9 WorldAnimator, § 3.1 Janitor.

---

### 9.7 Project — PlayerStateController (Knit controller)

**Location:** `src/Client/Client/Controllers/PlayerStateController.luau` (runtime) + `src/Shared/Utility/PlayerState.luau` (shared types + validator).
**NOT a package** — this is a project Knit controller plus a paired shared utility.
**Require (other controllers only):** `local PSC = Knit.GetController("PlayerStateController")`
**Purpose:** **MANDATORY single source of truth** for the local player's coarse-grained state. UI bindings and gameplay code MUST consult this controller (or pass `force = true` through UIClient) before opening a frame or running an action — **never invent ad-hoc booleans** for "is the player in a cutscene", "is the menu open", etc. Each *state* is one named bucket of allow/deny rules for two `kind`s: `"frame"` (UI surfaces) and `"action"` (gameplay verbs).

**Rule resolution (`:IsAllowed(kind, id)`):**

1. `id` listed in DeniedX → `false` (deny wins).
2. AllowedX is `nil` → `true` (nil = wildcard).
3. AllowedX listed → membership check on the list.
4. AllowedX is `{}` → `false` (explicit lock-everything).

Unknown `kind` and unknown `id` types fail closed (`false` + warn per rule_8).

**Public API:**

| Method / Field | Signature | Description |
|---|---|---|
| `:Register` | `(def: StateDef) -> ()` | Register a state def. Throws on duplicate `Name` or malformed def — programmer error, intentionally loud. Validation goes through `PlayerState.ValidateDef`. |
| `:Set` | `(stateName: string) -> ()` | Transition. Calls outgoing `OnExit(next)`, swaps current, fires `Changed`, calls incoming `OnEnter(prev)`. No-op when already in that state. Unregistered name warns + stays put. **Fully synchronous — never yields.** |
| `:Get` | `() -> string` | Current state name (always populated post-KnitInit). |
| `:IsAllowed` | `(kind: "frame" \| "action", id: string) -> boolean` | Apply the rule-resolution table above. Unknown kinds fail closed. |
| `.Changed` | `Signal<prev: string, next: string>` | Fires after current swap, before `OnEnter`. Sleitnick `Signal.new()` per § 3.2. |

**StateDef shape** (from `src/Shared/Utility/PlayerState.luau`):

```luau
export type StateDef = {
    Name:           string,                                   -- unique key
    AllowedFrames:  { string }?,                              -- nil = allow all; {} = lock all
    DeniedFrames:   { string }?,                              -- deny wins over allow
    AllowedActions: { string }?,
    DeniedActions:  { string }?,
    OnEnter:        ((prev: string?) -> ())?,                 -- synchronous; must not yield
    OnExit:         ((next: string?) -> ())?,                 -- synchronous; must not yield
}
```

`PlayerState.ValidateDef(def)` returns `(true, nil)` on success or `(false, errMessage)` on the first structural problem found.

**Built-in states (registered in `KnitInit`):**

| Name | Allow / Deny | Intent |
|---|---|---|
| `Idle` | (no restrictions) | Default after boot. Everything allowed. `DEFAULT_STATE`. |
| `InMenu` | `DeniedActions = { "OpenContainer" }` | Player paging menus. UI surfaces unrestricted; in-world gameplay actions are gated case-by-case. |
| `InGame` | `DeniedFrames = { "Shop", "Settings" }` | Actively playing. Menu-type frames stay closed; gameplay actions unrestricted. |
| `InCutscene` | `AllowedFrames = {}`, `AllowedActions = {}` | Cinematic. Lock everything (empty whitelists are explicit "deny all"). |
| `Loading` | `AllowedFrames = {}`, `AllowedActions = {}` | Initial loading screen. Locked until the loading-screen flow explicitly `:Set("Idle")`. |

Extend these built-ins as the project accretes features. New ad-hoc states must be registered via `:Register` from another controller's `KnitInit` (not at module top-level — `Knit.GetController` only resolves post-Init).

**Sequence integration:** `:Set` is synchronous and never yields, so it composes cleanly inside a `Sequence:Step(...)` (§ 3.9):

```luau
Sequence.new()
    :Step(function() PSC:Set("InCutscene") end)
    :Wait(2)
    :Step(function() PSC:Set("Idle") end)
    :Run()
```

**UIClient integration:** `UIClient:OpenFrame(frame, { force = true })` bypasses the `IsAllowed("frame", ...)` gate — used for system-mandated frames (loading screens, post-mortem panels) that must surface regardless of state. Default `force = false` requires a passing `IsAllowed` check.

**Usage:**

```luau
local Knit  = require(game.ReplicatedStorage.Packages.Knit)
local PSC   = Knit.GetController("PlayerStateController")

-- Gate an opener.
local function tryOpenShop()
    if not PSC:IsAllowed("frame", "Shop") then
        warn("[ShopBinding] Shop blocked in state '" .. PSC:Get() .. "'")
        return
    end
    UIClient:OpenFrame(playerGui.ShopFrame)
end

-- Subscribe to transitions.
PSC.Changed:Connect(function(prev, next)
    print(("[hud] state %s -> %s"):format(prev, next))
end)

-- Register a feature-specific state from a controller's KnitInit (NOT KnitStart —
-- callers should not depend on registration timing).
function MyController:KnitInit()
    PSC:Register({
        Name = "InCombat",
        DeniedFrames  = { "Shop", "Settings", "Inventory" },
        DeniedActions = { "OpenContainer" },
        OnEnter = function(prev) print("entered combat from", prev) end,
    })
end
```

**Gotchas:**

- **`OnEnter` / `OnExit` MUST NOT yield.** Both are pcall'd synchronously inside `:Set`; a yield inside one of them defers transitions and breaks the Sequence-friendliness contract.
- `:Register` throws on duplicates by design (programmer error). Don't wrap it in `pcall` to "make it idempotent" — fix the duplicate registration instead.
- `:Set` to an unregistered name warns and stays in the current state — it does NOT throw. Callers that depend on transitions completing should check `PSC:Get() == expectedName` after.
- An empty list (`{}`) is meaningfully different from `nil` — `{}` means "deny everything of this kind", `nil` means "allow everything of this kind". Don't confuse the two.
- `Changed` fires AFTER the current swap but BEFORE `OnEnter` runs. Listeners observing `PSC:Get()` inside Changed see the new state.

See also: § 3.2 Signal, § 3.9 Sequence, § 9.8 UIAnimator (frame gating via `OpenFrame`).

---

### 9.8 Project — UIAnimator (Knit controller) — preset library

**Location:** `src/Client/Client/Controllers/UIAnimator/` (init.luau + HoverEffects.luau, FrameTransitions.luau, StrokeScaler.luau, Presets/{Confetti, ShiningButton, RotateOscillate, NumberLabel, Countdown, Enlargen, Shrink, Notification}.luau).
**NOT a package** — this is a project Knit controller that sits ABOVE the vendored Twinkle package (§ 6.1). Different parent, different `Knit Name = "UIAnimator"`. Call-sites use this controller; never reach for `Packages.UIAnimator` directly.
**Require (other controllers only):** `local UIA = Knit.GetController("UIAnimator")`

**KnitStart side-effects:**

- Boots `HoverEffects`, `FrameTransitions`, `StrokeScaler`, and `Presets` (which currently boots only `ShiningButton` — `RotateOscillate.Start` is exported but not auto-booted; explicit `:RotateOscillate(obj, opts)` is the preferred path).
- **Mobile force-landscape**: on touch-only devices (`UserInputService.TouchEnabled` AND not `KeyboardEnabled` AND not `GamepadEnabled`), waits 1s post-KnitStart then sets `PlayerGui.ScreenOrientation = LandscapeRight`. Wrapped in `task.spawn` so KnitStart dispatch is never blocked.
- Hides the four notification templates (`Notification`, `Error`, `SpecialNotification`, `Tutorial`) under `PlayerGui.Ui.HUD.Notification` so they don't render in their default visible state.

**Public API — frame management:**

| Method | Signature | Description |
|---|---|---|
| `:OpenFrame` | `(frame: Frame, duration: number?) -> ()` | Zoom entrance via `FrameTransitions.Open`. `duration` defaults to 0.4s (S1 Duration Playbook — standard modal open). nil-frame warns + returns. |
| `:CloseFrame` | `(frame: Frame, duration: number?) -> ()` | Zoom exit. `duration` defaults to 0.25s (S1 — exits ≈62% of entry). |
| `:TagButton` | `(button: GuiButton) -> ()` | Manually wire hover/press effects on a button not yet tagged with the `"Animatable"` CollectionService tag. Tagged buttons are auto-wired by `HoverEffects.Start`. |

**Public API — Presets:**

| Method | Signature | Description |
|---|---|---|
| `:Confetti` | `(opts: ConfettiOpts?) -> ()` | Screen-space confetti burst. Delegates to `Presets.Confetti.Emit`. |
| `:TagShiny` | `(button: GuiButton) -> ()` | Apply the periodic gradient-shine flash. Equivalent to runtime-tagging `"ShiningButton"` via CollectionService. |
| `:RotateOscillate` | `(obj: GuiObject, opts: RotateOpts?) -> Handle` | Slow spring-driven back-and-forth rotation. CS tag `"RotateOscillate"` triggers auto-wire. |
| `:BindNumberLabel` | `(label: TextLabel, getValue: () -> number, opts: NumberOpts?) -> NumberHandle` | Spring-driven animated counter bound to an explicit getter. |
| `:BindPlayerDataNumber` | `(label: TextLabel, dataPath: {string}, opts: NumberOpts?) -> NumberHandle` | Same engine, reactive via `PlayerData.OnSet(dataPath)`. |
| `:BindReplicaNumber` | `(label: TextLabel, replica: any, dataPath: {string}, opts: NumberOpts?) -> NumberHandle` | Same engine, reactive via `replica:OnSet`. **Auto-cleans via `replica.Maid`** on replica destroy (§ 2.3). |
| `:Countdown` | `(label: TextLabel, opts: CountdownOpts) -> CountdownHandle` | Animated countdown/countup with whole-number sound + UIScale pop + one-shot rotation flash. |
| `:Enlargen` | `(obj: GuiObject, opts: EnlargenOpts?) -> Handle` | Spring scale-up via UIScale. |
| `:Shrink` | `(obj: GuiObject, opts: ShrinkOpts?) -> Handle` | Spring scale-down via UIScale (mirror of Enlargen). |
| `:ShowNotification` | `(messageOrOpts: string \| NotificationOpts) -> NotificationHandle?` | Clone a template from `HUD.Notification`, play Enlargen entrance, hold, Shrink exit. Returns nil if container/template missing. |
| `:Notify` | `(message: string) -> ()` | Convenience: default-template notification, all defaults. |
| `:NotifyError` | `(message: string) -> ()` | Convenience: `Error` template. |
| `:NotifyTutorial` | `(message: string) -> ()` | Convenience: `Tutorial` template, `duration = 999` (persistent). |
| `:NotifySpecial` | `(message: string) -> ()` | Convenience: `SpecialNotification` template. |

**Preset details:**

**Confetti** (`Presets.Confetti`)

- Maintains ONE persistent `ScreenGui` named `"ConfettiGui"` under PlayerGui; reused across emits; auto-destroyed when `_activePieces == 0` and `_activeEmitters == 0`.
- Sound: pass `opts.sound = nil` (or omit) for default `"UI.Reward.Fireworks"`; pass `opts.sound = Confetti.NoSound` (unique table sentinel) to suppress; pass `opts.sound = "<name>"` for an override.
- Shapes randomised over `{Square, Circle, Diamond, Triangle}`; colours from a fixed 6-entry palette; physics is raw RenderStepped with gravity (600 px/s²), spawn cascade staggered over ~0.8s, despawn at scale-Y > 1.3.
- `ConfettiOpts = { amount: number? = 250, spawnPos: UDim2? = randomised top strip, sound: any? }`.

**ShiningButton** (`Presets.ShiningButton`, CS tag `"ShiningButton"`)

- `Tag(button)` / `Untag(button)` — manual runtime wiring (CS tag does the same).
- `Start()` — boots the CollectionService watcher; called from `Presets.Start` at KnitStart.
- Pulse cycle: 0.4s resume + 1.5s pause via `EZVisualz.new(button, "Shine", 0.007, 1)` (§ 7.1). One Janitor per tagged button, `LinkToInstance(button)` so cleanup is automatic on Destroy.

**RotateOscillate** (`Presets.RotateOscillate`, CS tag `"RotateOscillate"`)

- `Apply(obj, opts?) -> Handle = { Cancel, IsRunning }`.
- Default `opts = { angle = 5, period = 1.6, smoothTime = 0.25 }` — spring on the Rotation property, target toggles every half-period.
- Resets `obj.Rotation = 0` on Cancel.

**NumberLabel** (`Presets.NumberLabel`) — three entry points sharing one engine

- `BindExplicit(label, getValue, opts?)` — caller drives via `handle.Refresh()` or `opts.poll` (seconds).
- `BindPlayerData(label, dataPath, opts?)` — subscribes to `PlayerData.OnSet(dataPath)`; initial render fires via `PlayerData.OnReady`.
- `BindReplica(label, replica, dataPath, opts?)` — subscribes to `replica:OnSet(dataPath)`; **`replica.Maid:Add(handle.Unbind)`** so the binding tears down on replica destroy (§ 2.3 auto-clean pattern).
- Shared `NumberOpts = { format = "suffix" | "commas", smoothTime = 0.25, impulseOnDelta = 0.08, poll = nil }`. `format` defaults to `"suffix"` per `architecture.md § Client-visible numbers` — `Format.Suffix` / `Format.Commas` (§ Project — Format).
- Engine: number spring + UIScale "pop" spring (smoothTime 0.12). When `|new - oldTarget| >= |new| * impulseOnDelta`, the UIScale spring gets `Impulse(0.15)`. Heartbeat loop re-arms only while motion is in flight; settle threshold disconnects to save frame budget.
- Shared `NumberHandle = { Refresh: () -> (), Unbind: () -> (), GetDisplayed: () -> number }`.
- `j:LinkToInstance(label)` — auto-clean on label destroy.

**Countdown** (`Presets.Countdown`)

- `Start(label, opts) -> CountdownHandle = { Cancel, IsRunning, GetCurrent }`.
- `opts.from` required. Defaults: `to = 0`, `tickInterval = 0.1`, `soundName = "HeavyCountdown"`, `onWholeNumber = nil`, `onComplete = nil`, `pairSound = nil`.
- Direction inferred from `from > to`; step magnitude = `tickInterval`. Renders one decimal: `string.format("%.1f", current)`.
- On every whole-number hit: plays `soundName` via `SoundController:Play` (§ 9.6), spring-impulses the UIScale (`IMPULSE_STRENGTH = 0.35`, smoothTime 0.12), and triggers a fire-and-forget TweenService rotation flash (15° tilt over 0.075s + return — explicitly documented exemption to rule_7 for one-shot label rotation; cannot conflict with UIAnimator since UIAnimator never touches `.Rotation` on TextLabels outside RotateOscillate).
- `opts.pairSound` — pass any handle with `:SetProgress(t)` (typically the `CountHandle` from `SoundController:CountTo`) and Countdown will call `pairSound:SetProgress(elapsed / duration)` on every tick. Keeps an external sound's pitch tracking the displayed number.

**Enlargen / Shrink** (`Presets.Enlargen`, `Presets.Shrink`)

- `Apply(obj, opts?) -> Handle = { Cancel, Completed: Signal<>, IsRunning }`. `Completed` is sleitnick `Signal.new()` (§ 3.2).
- Defaults: Enlargen `{ fromScale = 0.6, toScale = 1.0, smoothTime = 0.18 }`. Shrink `{ fromScale = 1.0, toScale = 0.0, smoothTime = 0.18 }`. Optional `completedFn` is also fired on completion (in addition to the signal).
- Engine: Spring on a UIScale child (created if absent). Settle = `|current - target| < 0.002` AND `|velocity| < 0.01`. `MAX_DT = 1/30` clamp to avoid lag-spike overshoot.

**Notification** (`Presets.Notification`)

- `Show(messageOrOpts) -> NotificationHandle? = { Dismiss, IsActive }`. Returns nil if the container `PlayerGui.Ui.HUD.Notification` or the requested template is missing.
- `NotificationOpts = { message, template = "Notification" | "Error" | "SpecialNotification" | "Tutorial", duration = 4, sound = nil | string | false, onDismissed }`.
- Lifecycle: resolve container → resolve template (FindFirstChild on the template name) → clone → set `Label.Text = message` (fallback: any `TextLabel` descendant) → play sound (`SoundController:Play` of `sound` or `"UI.Notification"`; pass `sound = false` to suppress) → `Enlargen.Apply(clone)` entrance → `task.wait(duration)` → `Shrink.Apply(clone, { toScale = 0 })` exit → destroy clone → fire `onDismissed`.
- `Dismiss()` is safe to call mid-flight: cancels an in-flight Enlargen, runs the Shrink exit. Idempotent.
- Templates are hidden at KnitStart by `UIAnimator/init.luau`'s template-hide spawn so they don't render before first use.

**Usage:**

```luau
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local UIA  = Knit.GetController("UIAnimator")

-- Frame transitions.
UIA:OpenFrame(playerGui.ShopFrame)               -- 0.4s default
UIA:CloseFrame(playerGui.ShopFrame, 0.2)         -- override

-- Number label bound to PlayerData (reactive, no polling).
local cashHandle = UIA:BindPlayerDataNumber(hud.CashLabel, { "cash" })
-- Later: cashHandle.Unbind()

-- Countdown paired with SoundController's CountTo for synchronised pitch.
local SC = Knit.GetController("SoundController")
local soundCount = SC:CountTo({ from = 10, to = 0, totalSeconds = 5 })
local visualCount = UIA:Countdown(hud.TimerLabel, {
    from = 10, to = 0,
    tickInterval = 0.1,
    pairSound    = soundCount,
})

-- Notifications.
UIA:Notify("Quest complete!")
UIA:NotifyError("Not enough coins")
UIA:NotifyTutorial("Press E to interact")        -- duration = 999

-- One-shot confetti suppressing the default sound.
local Presets = require(playerScripts.Client.Controllers.UIAnimator.Presets)
UIA:Confetti({ amount = 400, sound = Presets.Confetti.NoSound })
```

**Gotchas:**

- This controller is DISTINCT from the vendored `Packages.UIAnimator` (Twinkle, § 6.1). The Twinkle package is a transitive dependency — call-sites should use this controller's API surface, never `require` the package directly.
- `:Confetti`, `:Countdown`, and `:Notification` all consume `SoundController` via `Knit.GetController("SoundController")` — load order matters; reach for the audio controller lazily (these presets already do via pcall'd getters).
- `Notification.Show` requires templates at `PlayerGui.Ui.HUD.Notification.<TemplateName>`. Missing template warns and returns nil; check the return.
- `BindReplicaNumber` auto-cleans via `replica.Maid` — callers don't need a separate Janitor for the binding. But if you want to unbind earlier (e.g. on UI close), call `handle.Unbind()` explicitly.
- `Countdown`'s one-shot rotation flash uses TweenService — that's the documented rule_7 exemption (fire-and-forget on a non-temporary instance is acceptable because UIAnimator never touches `.Rotation` on TextLabels outside `RotateOscillate`).
- `RotateOscillate.Start` exists but is NOT auto-booted by `Presets.Start` — wire it explicitly from `UIAnimator/init.luau:KnitStart` if you want CS-tag-driven auto-wiring. Manual `:RotateOscillate` calls work either way.
- Mobile force-landscape fires only on touch-only devices and only once at KnitStart — it does NOT re-fire if input devices change at runtime.

See also: § 6.1 UIAnimator (vendored Twinkle package), § 5.1 Spring, § 3.1 Janitor, § 3.2 Signal, § 7.1 EZVisualz, § Project — Format, § 9.6 SoundController, § 9.7 PlayerStateController.

---

### 9.9 Project — WorldAnimator (Knit controller)

**Location:** `src/Client/Client/Controllers/WorldAnimator/` (init.luau + Presets/{HoverBob, SpringGrow, SpringShrink, SpringVanish, SpringMaterialize, ExplodeBounce, MagnetToPlayer, BezierMove, LinearSpring}.luau).
**NOT a package** — this is a project Knit controller. **Knit Name:** `"WorldAnimator"`.
**Require (other controllers only):** `local WA = Knit.GetController("WorldAnimator")`
**Purpose:** World-space animation orchestrator. Maps named presets to either a one-shot `Instance` (`:Apply`) or to a Replica `Token` (`:Bind`), where every replica of that token gets its preset run on `replica.BoundInstance` with `Cancel` automatically tied to `replica.Maid`. This is the canonical client-side world-animation flow — pair with `WorldEntityHandler` (§ 9.11) on the server.

**Universal target resolver** (`_resolveAnchor`): every preset accepts ANY `Instance`. The resolver returns a position-bearing `BasePart`:

- `BasePart` → itself (kind `"BasePart"`).
- `Model` with `PrimaryPart` set → `model.PrimaryPart` (kind `"PrimaryPart"` — preset uses `PivotTo` for the model).
- `Model` without `PrimaryPart` → `model:FindFirstChildWhichIsA("BasePart", true)` with a warn (kind `"Model-noPrimary"`).
- Otherwise → warns + returns `(nil, nil)` and `:Apply` returns a no-op `Handle`.

**Public API:**

| Method / Field | Signature | Description |
|---|---|---|
| `:Apply` | `(presetName: string, target: Instance, opts: any?) -> Handle` | One-shot. Resolves the preset, calls it with a fresh Janitor, returns the `Handle` augmented so `Cancel()` also tears down the janitor. Missing preset / unresolvable target → no-op Handle with already-fired `Completed`. |
| `:Bind` | `(token: string, presetName: string, opts: any?) -> { Disconnect: () -> () }` | Subscribe via `ReplicaController:OnReplicaNew(token)` (§ 9.5). For every replica that arrives, calls `:Apply(presetName, replica.BoundInstance, opts)` and `replica.Maid:Add(handle.Cancel)` so the animation stops automatically when the replica is destroyed. Double-bind on the same token warns + no-ops. |
| `:Unbind` | `(token: string) -> ()` | Cancel all in-flight handles for `token`, drop the binding. Idempotent — no-op + warn if no active binding. |
| `.Presets` | `{ [string]: PresetFn }` | Read-only reference to the preset registry. `PresetFn = (target: Instance, opts: any?, janitor: Janitor) -> Handle`. |

`Handle = { Cancel: () -> (), Completed: Signal<>, IsRunning: () -> boolean }`. All `Completed` signals are sleitnick `Signal.new()` (§ 3.2).

**Presets** (one line each):

| Name | Opts | Behaviour |
|---|---|---|
| `HoverBob` | `{ amplitude = 0.5, period = 2.0, axis = Vector3.yAxis }` | Sine oscillation along an axis driven by a Spring (smoothTime 0.4) so motion settles gracefully when cancelled. Atmospheric idle effect. |
| `SpringGrow` | `{ factor = 1.3, impulseSeconds = 0.18 }` | Spring impulse on size outward, settles back to original. "I'm here" arrival pop. |
| `SpringShrink` | `{ factor = 0.8, impulseSeconds = 0.18 }` | Mirror of SpringGrow with negative impulse — hit / retreat squash. |
| `SpringVanish` | `{ smoothTime = 0.25 }` | Spring size down to near-zero. Caller destroys after `Completed`. Pickup / consumed / despawn. |
| `SpringMaterialize` | `{ smoothTime = 0.25 }` | Inverse of Vanish — captures `originalSize`, drops to near-zero, springs to full. Spawn / reward drop. |
| `ExplodeBounce` | `{ spread = 8, height = 12, settleSeconds = 2.0 }` | Phase 1: quadratic Bezier arc over `settleSeconds * 0.7`. Phase 2: Spring at end position with downward impulse settle (smoothTime 0.4). Coin / loot / ejected part. |
| `MagnetToPlayer` | `{ player = LocalPlayer, speed = 40, touchKill = true, smoothTime = 0.4 }` | Speed-capped spring (`Spring.new(initial, smoothTime, maxSpeed)` — third arg to Spring.new per § 5.1) chases HRP; fires `Completed` on touch with any character part; sets `CanCollide = false` during flight and restores on Cancel. |
| `BezierMove` | `{ from, control, to, seconds = 1.0, ease = "quad" }` (linear/quad/cubic) | Quadratic Bezier curve traversal. Fires `Completed` at `t = 1`. |
| `LinearSpring` | `{ to: Vector3, smoothTime = 0.4 }` | Plain critically-damped spring move to `to`. Settle ≤ 0.05 studs. The simplest "move here". |

All presets register every connection with explicit `"Disconnect"` per § 3.1 (ZonePlus-gotcha rule applies broadly — explicit is always safe).

**Canonical world-animation flow** (`:Bind` → ReplicaController → `replica.Maid` auto-clean):

```luau
local Knit = require(game.ReplicatedStorage.Packages.Knit)

local WorldVisualsController = {}

function WorldVisualsController:KnitStart()
    local WA = Knit.GetController("WorldAnimator")

    -- Every "WorldEntity" replica of Tag.Kind = "Coin" hovers + materialises.
    WA:Bind("WorldEntity", "HoverBob", { amplitude = 0.6, period = 1.8 })
    -- The handle Cancel is auto-attached to replica.Maid — when the server
    -- destroys the replica (e.g. coin picked up), the hover stops automatically.
end

return WorldVisualsController
```

**One-shot usage:**

```luau
local WA = Knit.GetController("WorldAnimator")

-- Materialise a freshly-cloned model.
local h = WA:Apply("SpringMaterialize", spawnedModel, { smoothTime = 0.3 })
h.Completed:Connect(function() print("appeared") end)

-- Magnet a coin to the player on pickup, then destroy.
local magnet = WA:Apply("MagnetToPlayer", coinModel, { speed = 60, touchKill = true })
magnet.Completed:Connect(function() coinModel:Destroy() end)

-- Cancel mid-flight.
task.delay(1, function() magnet.Cancel() end)
```

**Gotchas:**

- `:Bind` called before `KnitStart` warns + returns a no-op disconnect — `_replicaController` is fetched in `KnitStart` (per § 1.1 Knit Client, `GetController` is only safe post-Init).
- `:Bind` is per-token-singleton — double-binding the same token warns + no-ops. Call `:Unbind(token)` first if you need to swap presets.
- `MagnetToPlayer` sets `CanCollide = false` during flight; if you Cancel mid-flight the connections restore the prior `CanCollide` state. Don't manually toggle `CanCollide` while a magnet is in flight.
- `SpringVanish` leaves the target at near-zero size — caller is responsible for `Destroy()` (typically wired off `Completed`).
- The resolver's `Model` → `PrimaryPart` path uses `PivotTo` for the model translation. If you've set a non-trivial pivot, motion respects that. Presets that anchor on `Size` (SpringGrow/Shrink/Vanish/Materialize) operate on the anchor BasePart's `Size` — they do NOT scale every child of a Model.
- Presets are functions, not classes — accessing `WA.Presets.HoverBob` and calling it directly bypasses the janitor wiring (`Apply` adds the janitor + cancel augmentation). Always go through `:Apply` / `:Bind`.

See also: § 9.5 ReplicaController (the `OnReplicaNew` flow that `:Bind` consumes), § 9.11 WorldEntityHandler (the server-side replica producer), § 5.1 Spring, § 3.1 Janitor, § 3.2 Signal.

---

### 9.10 Project — AutoRejoinController (Knit controller)

**Location:** `src/Client/Client/Controllers/AutoRejoinController.luau`.
**NOT a package** — project Knit controller. **Knit Name:** `"AutoRejoinController"`.
**Require (other controllers only):** `local AR = Knit.GetController("AutoRejoinController")`
**Purpose:** Automatically teleport the local player back to the same place on a network-loss disconnect. Listens to `GuiService` for disconnect-style error dialogs, debounces, and calls `TeleportService:Teleport(game.PlaceId, LocalPlayer)`.

**Detection pattern (DevForum-standard):**

- Hook `GuiService:GetPropertyChangedSignal("ErrorMessageChanged")` — fires whenever the client surfaces an error / kick dialog. No RemoteEvent, no polling.
- On each fire, read `GuiService.ErrorMessageText` and match (case-insensitive) against `DISCONNECT_PATTERNS = { "lost", "disconnect", "could not", "27[7-9]", "timed out" }`. Patterns cover network timeout, Roblox kick codes 277/278/279, and generic drop messages.
- On match: 15s debounce flag, then `_attemptRejoin`.

**Public API (`:_TestTrigger` is the only public method — `_` prefix reflects dev-only intent):**

| Method | Signature | Description |
|---|---|---|
| `:_TestTrigger` | `(simulatedMessage: string?) -> ()` | Dev-only. Runs the full detection chain against a simulated `ErrorMessageText` WITHOUT actually calling `TeleportService:Teleport`. Default message: `"Lost connection — Error code 277"`. **No-op outside Studio** (warn + return). |

**Studio dry-run gate:** `_attemptRejoin` checks `RunService:IsStudio()` and warns + returns instead of calling `TeleportService:Teleport`. The listener itself binds in ALL environments (including Studio) so `:_TestTrigger` can exercise the full chain; only the teleport call is gated. This means production builds run the real teleport, Studio runs the dry-run, with one code path.

**Captured-state pattern:** `task.delay(DEBOUNCE_SECONDS, ...)` captures `self` into a local `ctrl` BEFORE the delay fires (per architecture.md § Capture state into locals BEFORE `task.delay` callbacks). The callback nil-checks `ctrl` before clearing the debounce.

**Usage:**

```luau
-- From a dev panel or debug binding (Studio only):
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local AR   = Knit.GetController("AutoRejoinController")

AR:_TestTrigger("Connection timed out")   -- exercises the chain dry-run
AR:_TestTrigger()                          -- uses the default message
```

**Gotchas:**

- `:_TestTrigger` is dev-only by design — calling it from a live binding in production warns + no-ops. Wire it only from a Studio-gated panel.
- `DISCONNECT_PATTERNS` is intentionally broad. If you see false-positive teleports on a non-disconnect error, narrow the patterns rather than disabling the controller.
- The listener fires on EVERY error dialog (kicks, custom kicks from `Player:Kick`, network drops). If you want to suppress rejoin for custom kicks, prefix your kick message with something the patterns won't match (e.g. `"[KICK]"`).
- `TeleportService:Teleport` throws in edit/run mode — that's why the Studio gate exists. Never remove the gate or you'll break the test harness.
- Debounce is per-controller-instance — there's only one `AutoRejoinController` so it's effectively global. 15s is the right window for transient network blips; do not lower it (you'll thrash on a sustained outage).

See also: § 1.1 Knit, § 3.1 Janitor, architecture.md § Capture state.

---

### 9.11 Project — WorldEntityHandler (server module)

**Location:** `src/Server/Server/Modules/WorldEntityHandler.luau`.
**NOT a package** — project server module under `Server/Modules/`. Registered + initialised by `GameService` per architecture.md § How to add a new handler.
**Require (server only):** `local WEH = require(game.ServerScriptService.Server.Modules.WorldEntityHandler)`
**Purpose:** Create and manage **non-PlayerData** Replica instances ("WorldEntity" replicas) that represent world state — items, props, dynamic objects whose state the client mirrors via `ReplicaController` (§ 9.5) and animates via `WorldAnimator` (§ 9.9). Pair this with `WorldAnimator:Bind("WorldEntity", ...)` on the client.

**Token name:** `"WorldEntity"` (declared once in `:Initialize` per § 2.2 — duplicate `Replica.Token` calls throw). All replicas this handler produces share this token; differentiate by `Tags.Kind` (the `kind` argument to `:Spawn`).

**Replica direct-use note:** unlike `DataService` (which wraps Replica for PER-PLAYER profile state), this handler calls `Replica.New` / `:BindToInstance` / `:Replicate` / `:Set` directly. That's intentional — these are WORLD replicas, not per-player, so the leaving-race fallback in DataService doesn't apply. Per architecture.md § Critical Bans, the "never call `Replica.New` outside DataService" rule applies to **player data only**. World replicas live here.

**Public API:**

| Method | Signature | Description |
|---|---|---|
| `:Initialize` | `() -> ()` | Called from `GameService:KnitStart`. Declares `TOKEN = Replica.Token("WorldEntity")` (must run once). Hooks `Players.PlayerRemoving` for forward-compatible per-player cleanup (currently a no-op placeholder). |
| `.Spawn` | `(instance: Instance, kind: string, data: {}?) -> Replica` | Create a replica bound to `instance` with `Tags = { Kind = kind }` and initial `Data = data or {}`. Calls `:BindToInstance(instance)` + `:Replicate()`. **Idempotent** — re-spawning an already-tracked instance warns + returns the existing replica. Auto-despawn wired via `instance.Destroying`. Throws on non-Instance `instance` or empty `kind`. |
| `.Despawn` | `(instance: Instance) -> ()` | Destroy the replica bound to `instance` and remove it from tracking. No-op + warn if `instance` was never spawned. |
| `.Update` | `(instance: Instance, path: {string}, value: any) -> ()` | Mutate via `replica:Set(path, value)` (§ 2.2). No-op + warn if `instance` was never spawned (warn includes the path joined by `.` for diagnostics). |

`.Spawn` / `.Despawn` / `.Update` are dot-call (no `self`); only `:Initialize` is colon-call (mirrors the lifecycle convention).

**Server usage (paired with WorldAnimator on the client):**

```luau
local WEH = require(script.Parent.Modules.WorldEntityHandler)

-- Spawn a coin replica bound to a workspace model.
local coin = workspace.Coins.Coin1
local replica = WEH.Spawn(coin, "Coin", { sparkle = true })

-- Push state changes — clients see them via replica:OnSet.
WEH.Update(coin, { "sparkle" }, false)

-- Despawn explicitly (or just :Destroy() the model — Destroying auto-cleans).
WEH.Despawn(coin)
```

**Client side** (`WorldAnimator:Bind` already documented in § 9.9):

```luau
local WA = Knit.GetController("WorldAnimator")
WA:Bind("WorldEntity", "HoverBob", { amplitude = 0.6 })
-- Each WorldEntity replica's BoundInstance gets a HoverBob applied;
-- replica.Maid carries the Cancel so picking up the coin (server-side Despawn)
-- stops the hover automatically.
```

**Gotchas:**

- **Idempotent `.Spawn`** — re-spawn warns and returns the existing replica rather than throwing or stacking replicas. Useful for "ensure this instance has a replica" flows, but means you can't silently re-template by calling Spawn again. Despawn first if you need fresh `Data`.
- **`instance.Destroying` auto-despawn** — if you Destroy the bound model in workspace, the replica is auto-destroyed via the connection inside `.Spawn`. You generally do NOT need to call `.Despawn` explicitly unless the instance lives on (e.g. you parented it to nil but kept it alive).
- **`TOKEN` is module-private + typed `any`** — declared once in `:Initialize` to dodge the "duplicate `Replica.Token` throws" gotcha (§ 2.2). Don't move the declaration to module top-level — it would fire on module require, before `GameService` is ready.
- **`Tags.Kind` is the discriminator** — clients should consume via `replica.Tags.Kind` to switch on entity type. Using one token + tags is cheaper than one-token-per-kind (each token is a globally-unique server-lifetime registration).
- **Bridge handlers calling `.Spawn`/`.Update`** must apply the per-player mutex pattern (architecture.md § Critical Bans) — `Replica.New` / `:Set` do not yield, but the surrounding business logic (DataService.Set, ProfileStore saves) often does. Wrap bridge bodies in `task.spawn`.
- **No per-player entity cleanup today** — the `Players.PlayerRemoving` hook is wired as a forward-compatible placeholder. If you add per-player WorldEntity variants (entities keyed by player), sweep them in that handler.

See also: § 2.2 Mad Studio Replica — Server, § 9.5 ReplicaController, § 9.9 WorldAnimator, architecture.md § How to add a new handler.

---

## Appendix A — Transitive / not-for-direct-use

- **Trove** — installed only as a UIAnimator internal dep. Prefer Janitor for new code.
- **Two `signal` packages** are in `_Index` (`sleitnick_signal@1.5.0` AND `sleitnick_signal@2.0.3`) because Knit / TopbarPlus pin different versions. Only `Packages.Signal` (which resolves to 2.0.3) is what you require directly.
- **Two `trove` packages** are in `_Index` (`0.4.2` is a TopbarPlus internal; `1.8.0` is the wally-toml entry). Only `Packages.Trove` (1.8.0) is the public route.
- **`sleitnick_comm@1.0.1`**, **`pysephwasntavailable_remotepacketsizecounter@2.4.1`**, **`ffrostflame_tablekit@0.2.4`**, **`miagobble_seam@0.5.6`**, **`ffrostflame_wally-instance-manager@0.1.0`**, **`howmanysmall_typed-promise@4.0.6`** — these are transitive deps. There is **no public `Packages/<X>.lua` thunk** for them. If you need their APIs, require their `_Index` paths directly (e.g. `Packages/_Index/miagobble_seam@0.5.6/seam`). Most code should never need to.
- **`sleitnick_signal@1.5.0`** — transitive dep of ZonePlus / Streamable / older sleitnick packages. Don't require it directly.

---

## How to keep this file fresh

**Trigger an update when:**

- A new package is added to `wally.toml` or vendored into `src/`.
- A package is upgraded and its public API changed (run `grep -n "^function" <init>` on the new source to diff).
- A bug or anti-pattern is discovered for any documented package — add it under that package's **Gotchas** section.
- A documented signature drifts from what the code actually does. The code wins.

**Responsibility:**

- After feature work that touches a new library: spawn the **game-knowledge** agent (see CLAUDE.md `Self-Improvement Protocol`) with the prompt _"Update `.claude/reference/api-reference.md`: <package> <what changed>"_. The agent should re-read the package source, not paraphrase from memory.
- For a Wally upgrade, also re-run `npx wally install` then update the `Wally:` line and any signature changes.
- Never let this file diverge from `wally.toml` and `wally.lock` — when in doubt, run `grep -n "^function" Packages/_Index/<pkg>/.../init.luau` and reconcile.
