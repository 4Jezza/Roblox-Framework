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
