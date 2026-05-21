# Knit Boilerplate — Claude Instructions

> Behavioral rules, game briefing, and agent routing live here.
> Adapt the **Game Overview** and **Project Registry** sections when you fork this boilerplate for a specific game.

---

## Required Reading (open these BEFORE any code work)

Three reference files are mandatory context for every coding task. They are the single source of truth for folder layout, require paths, instance locations, and library API surface. Forgetting them produces wrong require paths, fabricated asset paths, broken syncs, and incorrect API calls — **always open them first.**

| File | Open when... |
|---|---|
| **`.claude/reference/architecture.md`** | ANY edit under `src/`. Covers: folder → Studio mapping, require paths for every Wally + vendored package, file naming, `DataService` API, `Bridges` registry rules, Critical Bans, handler cookbook. |
| **`.claude/reference/asset-discovery.md`** | ANY task touching `StarterGui`, `Workspace`, `ReplicatedStorage.Assets`, or `ServerStorage.Assets`. Covers: MCP tool list, `filestructure/*.md` cache protocol, snapshot refresh + staleness rules. |
| **`.claude/reference/api-reference.md`** | **MANDATORY for ANY edit under `src/` that imports a Wally/vendored package** (Knit, BridgeNet2, Janitor, Signal, ProfileStore, Replica, UIAnimator, EZVisualz, Sift, Spring, ZonePlus, TopbarPlus, ExpressivePrompts, Emitter2D, FastCast, Sequence, etc.). Covers every public method with signature, common usage snippets, and gotchas (e.g. Replica `OnSet`/`OnChange` vs the non-existent `ListenToChange`; `Janitor:Add(conn)` auto-probes `:Destroy` which throws on ZonePlus signal Connections — pass `"Disconnect"` explicitly; Signal lowercase `.new()` vs Mad Studio `.New()`). **One wrong API call wastes more time than reading this file ever will.** |

**Agent-spawn requirement (HARD ENFORCEMENT)**: every agent prompt MUST include `"Read .claude/reference/architecture.md first"` ALWAYS, plus `"and .claude/reference/api-reference.md"` if the file the agent will touch imports ANY package (grep the target file's `require(...)` lines — if any path contains `Packages.` or `ReplicaServer`/`ReplicaClient`, api-reference.md is mandatory), plus `asset-discovery.md` if the task touches `StarterGui`/`Workspace`/`*.Assets`. **Default to including api-reference.md** — false positives (agent reads a doc unnecessarily) are cheap; false negatives (agent invents a wrong API) cost hours.

When you apply guidance from any reference file, cite it (e.g. *"per architecture.md § Require Paths"*, *"per asset-discovery.md § Protocol"*, *"per api-reference.md § Janitor"*) — citation proves the file was in context. **Agents that produce code calling a package API without a citation are presumed to have NOT read api-reference.md and their output should be re-audited.**

---

<behavioral_rules>
  <rule_1>NEVER rename the DataStore key — it wipes every player save. Current key lives in `src/ServerStorage/ServerUtilities/DataService.luau`.</rule_1>
  <rule_2>NEVER create RemoteEvent / RemoteFunction / UnreliableRemoteEvent. ALL client↔server traffic goes through BridgeNet2 via `src/Shared/Shared/Bridges.luau`. Vendored library internals (e.g. Mad Studio Replica) are the only exemption — do not touch their transport.</rule_2>
  <rule_3>Asset/script split: scripts → Argon (Read/Edit/Write in `src/`). Studio-only roots (`StarterGui`, `Workspace`, `*.Assets`) → Roblox MCP. Read `filestructure/<root>.md` BEFORE any MCP lookup; verify any path via `inspect_instance` before referencing it in code; refresh the MD + bump `last-updated.json` after discovery. STOP if `list_roblox_studios` is empty — never fabricate paths from stale snapshots. **Full protocol with worked examples lives in `.claude/reference/asset-discovery.md` — read it before any asset-touching task.** Require paths and folder mappings for `src/` code live in `.claude/reference/architecture.md` — read it before any code edit.</rule_3>
  <rule_4>Packages are READ-ONLY: `Packages/`, `src/Server/Server/Packages/`, `src/Client/Client/Packages/{UIAnimator,Emitter2D}/`, `src/Shared/ReplicaShared/`, `src/Server/ReplicaServer.luau`, `src/Shared/ReplicaClient.luau`. Read for API surface only. Work around bugs via sibling shims (e.g. `src/Client/Client/Packages/UIUtil.luau`). Rule_9 line cap does not apply here.</rule_4>
  <rule_5>You orchestrate; agents implement. Default to delegation — spawn parallel agents for independent work, NEVER write 2+ files sequentially yourself. Direct edits allowed only for: single-file <30 lines, reading/explaining, single config-value tweak in `DataModules/`, or MCP/Studio commands. ALWAYS delegate VFX, visuals, and UI work.</rule_5>
  <rule_6>ALWAYS read a file before editing. Before creating a utility, grep `src/` for existing equivalents — canonical homes: `Format` (numbers/strings), `Janitor` (cleanup), `Signal` (events), `Sift` / `TableUtil` (tables), `Sequence` (sequencing/chaining). Extend existing modules; don't duplicate. If unsure, surface 2-3 candidate locations with grep match counts before deciding.</rule_6>
  <rule_7>UI uses UIAnimator (Twinkle) only. NEVER raw TweenService for UI transitions. Exception: one-shot fire-and-forget tweens on temporary instances (e.g. a floating "+N" frame destroyed after ~1s).</rule_7>
  <rule_8>Defensive logging — every failable lookup MUST `warn` on miss with module + target + recovery action. Covers `FindFirstChild`, `WaitForChild` timeouts, `CollectionService:GetTagged` empty when ≥1 expected, `MarketplaceService:UserOwnsGamePassAsync` failures, `DataService.Get(player, key)` nil for required fields, `:GetAttribute` nil where expected, bridge handlers with malformed payloads, pcall failure branches. Format: `warn("[Module] missing <what> at <where> — <recovery>")`. NEVER a bare `pcall` with no `warn` on the failure branch.</rule_8>
  <rule_9>SOFT line cap: aim to keep `src/` files under 300 lines (Packages exempt — rule_4). This is a heuristic, not a hard ban — exceed it when splitting would HURT modularity (e.g. a tight state machine that reads top-to-bottom, an ordered cookbook of cases where the next reader needs all branches visible together). **Priority order: (1) modularity for findability — a future reader should be able to predict which file holds a bug from the symptom alone, without grepping siblings; (2) line count.** When you do split: group by domain not by size — extract reusable logic to `src/Shared/Utility/` (cross-cutting) or per-feature binding folders (`src/Client/Client/<Feature>Bindings/`); split configs by domain (`SpeedConfig` + `GamepassConfig`, not one `Config`); entry-point modules re-export public APIs so callers' require paths stay stable. If a file goes over 300, add a one-line header comment explaining why splitting would worsen findability — the comment is the audit trail.</rule_9>
  <rule_10>UI hierarchy. STATELESS primitives (`LabelledButton`, `ProgressBar`, etc.) live at `src/Client/Client/UI/`, accept `(parent, props)`, and MUST NOT call `PlayerData.*` / `Bridges.*` / `DataService.*`. STATEFUL feature controllers and bindings live at `Controllers/` and `<Feature>Bindings/`; they compose primitives, read PlayerData, fire bridges, own the Janitor.</rule_10>
  <rule_11>For changes touching >2 `src/` files (excluding Packages), output a modularity plan FIRST: every file you'll touch with a one-line gains/loses note, shared abstractions + their locations, per-file line budgets (rule_9). Get user sign-off if you'd add a new top-level folder OR move >100 lines between files. No plan = no multi-file edit.</rule_11>
  <rule_12>After any non-trivial edit (>5 lines or logic), spawn `bug-investigator` to audit changed files (nil refs, race conditions, mutex violations, leaks, forward decls). After ALL task work, loop bug-investigator until a pass returns "NO BUGS FOUND". Never present results without the final clean pass.</rule_12>
  <rule_13>Verification before declaring done: `selene src/` (lint), `stylua --check src/` (format), `argon sourcemap --output sourcemap.json` (sync sanity). For runtime changes, smoke test via `argon exec <one-shot.luau>`. Fix all errors. If a tool is missing, surface the install command (`aftman install`, `cargo install selene` / `stylua`) — never skip verification silently.</rule_13>
  <rule_14>Output: terse markdown bullets over prose. Keep responses under 150 lines unless detail is genuinely necessary. Code blocks for code; bullets for everything else.</rule_14>
  <rule_15>Reference docs are LIVING documents — update them in the same task that introduces the change, not as a follow-up. Doc drift is treated as a bug; `bug-investigator` may flag stale references. Update map: (a) Studio asset tree changed (MCP revealed new/changed instances) → refresh the matching `filestructure/<root>.md` + bump `filestructure/last-updated.json`; (b) new or upgraded Wally / vendored package → add/update its section in `.claude/reference/api-reference.md` AND the Require Paths block in `.claude/reference/architecture.md`; (c) new handler / controller / binding / config / bridge → append to `CLAUDE.md § Project Registry`; (d) new system or rebalanced mechanic → spawn `game-knowledge` to refresh `CLAUDE.md § Game Overview`; (e) new architectural convention discovered → add to `.claude/reference/architecture.md § Critical Bans` or Limitations & Gotchas. Never close a task that introduced one of the above without also updating the matching doc.</rule_15>
  <rule_17>**File encoding: UTF-8 WITHOUT BOM.** Luau's parser rejects a leading UTF-8 BOM (bytes `EF BB BF`) with `Expected identifier when parsing expression, got Unicode character U+feff` at line 1, cascading into `Requested module experienced an error while loading` and Knit boot failure. **Forbidden tooling**: Windows PowerShell 5.1's `Set-Content -Encoding UTF8` and `Out-File -Encoding UTF8` BOTH silently write WITH BOM. Never use them for `.luau` / `.lua` writes. **Safe tooling**: Claude Code Edit / Write tools; `Set-Content -Encoding ASCII` when content is ASCII-only; explicit `$utf8NoBom = New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)`; PowerShell 7+ `-Encoding utf8NoBOM`. **After ANY bulk-write tool run**, run a BOM-sweep before declaring done — `argon sourcemap` does NOT detect BOM corruption. Open Studio and let it parse one rewritten file to confirm.</rule_17>
  <rule_16>**Module-as-folder convention.** Three use cases trigger the folder-with-`init.luau` pattern; flat `Parent_Child.luau` siblings are FORBIDDEN.
**(a) Helper splits.** A module past rule_9's soft cap (or with tightly-coupled helpers) becomes `Foo/init.luau` + `Foo/Child.luau`. Further-nest as `Foo/Sub/init.luau` + `Foo/Sub/Leaf.luau` when a child itself splits. External require paths stay stable (`require(...Foo)` resolves to the folder via Rojo init-script semantics).
**(b) Sequence / state-machine states.** A controller driven by `Sequence` (chainable async state machine) with N distinct states should expose each state as a child ModuleScript — e.g. `MyFlowController/{init, Lobby, InZone, BetweenZones, Dead}.luau`, where the init builds the Sequence and each child returns a `function(player, signals, deps) ... end` state body. Same for any other multi-state flow (boot sequences, multi-step setup, choreographed cinematics). **Why:** state files become independently scannable; a future reader predicts which file holds a bug from the state name alone.
**(c) Top-level category folders for LARGE systems only.** Promote a category to its own top-level folder (e.g. `Combat/`) ONLY when it owns a significant slice of the codebase — heuristic: ≥6 modules + clear bounded context. Small clusters stay floating at the root. Don't fragment further without scale.
**How to apply (require paths):** from `Foo/init.luau` to a child use `script.Child`; from `Foo/Child.luau` to a sibling use `script.Parent.OtherChild`; from `Foo/Sub/Leaf.luau` to a grandparent's child use `script.Parent.Parent.Cousin`; cross-group references use the canonical `ReplicatedStorage.X` or `script.Parent.OtherFolder` path. Knit controller `Name = "..."` strings remain stable across restructures — changing them breaks every `Knit.GetController("...")` caller.
**UI:** one ModuleScript per frame / flow under the bindings folder. Promote to `Frame/{init, Sub}` only when a frame grows internal helpers.
**Forbidden:** new `Foo_Bar.luau` flat siblings; new category folders for systems that don't meet the scale heuristic.</rule_16>
</behavioral_rules>

---

## Game Overview

> Brief for every agent: this is what the game is. Keep current — spawn `game-knowledge` to update when a system materially changes.

> **TODO when you fork the boilerplate:** Replace this section with a 1-3 paragraph description of your game's mechanics, core loop, monetization, hazards, and persistence model. The boilerplate is intentionally generic — fill this in so future agents can route correctly without re-reading the whole codebase.

This is a Knit + ProfileStore + ReplicaService + BridgeNet2 boilerplate scaffold. It contains platform infrastructure (data persistence, networking, dev-product receipts, leaderstats, dynamic Roblox configs) but no gameplay. Add your game's systems under `src/Server/Server/Modules/` (handlers) and `src/Client/Client/` (controllers, bindings, modules) following the conventions established in the platform stubs.

---

## Project Registry

> Append when files are added/removed/renamed. Bridges are the contract surface — change those carefully and update both sides.

- **Server Handlers** (`src/Server/Server/Modules/`): `DataHandler`, `ProductHandler`, `RemoteConfigHandler`, `AnalyticsHandler`, `InventoryHandler`, `AdminHandler`
- **Client Controllers** (`src/Client/Client/Controllers/`): `GameController`, `ProximityController`
- **Client Modules** (`src/Client/Client/Modules/`): `UIClient`, `NotificationClient`, `ChatClient`
- **Configs** (`src/Shared/DataModules/`): `ProductConfig`
- **Shared utilities** (`src/Shared/Utility/`): `Format`, `Janitor`, `Spring`, `PlayerData`, `Sequence`
- **Bridges** (`src/Shared/Shared/Bridges.luau`): `Notify`, `OpenContainer`, `AdminCommand`

> **TODO when you fork the boilerplate:** Add new handlers/modules/controllers/configs/bridges to the lists above as you build them. Keep this registry up to date so agents can route work correctly.

---

## Agent Routing

Pipeline: plan task → spawn agent (background) → plan next task → spawn next. Never wait idle. Agents self-discover by reading architecture.md, `Bridges.luau`, and `GameService.luau`.

### Domain → Agent

| Task involves...                                | Agent                     |
|-------------------------------------------------|---------------------------|
| ScreenGui, frames, buttons, text labels         | **ui-controller**         |
| Tweens, particles, camera effects, VFX models   | **animation-vfx**         |
| Sound playback, audio feedback, SoundService    | **sound-specialist**      |
| `src/Server/`, handlers, services, data mutation| **server-handler**        |
| `src/Client/`, controllers, client game logic   | **client-controller**     |
| Bridges, remotes, client↔server payloads        | **networking-specialist** |
| Replica, OnChange, PlayerData                   | **replication-specialist**|
| Janitor, cleanup, connection leaks              | **janitor-lifecycle**     |
| `DataModules/`, balance numbers, config tables  | **config-balancer**       |
| Game overview outdated or new system landed     | **game-knowledge**        |
| "X is broken" / post-edit review                | **bug-investigator**      |

### Dependency rules
- **Independent tasks** (no shared bridges/data): spawn all in parallel.
- **Dependent tasks** (client consumes a NEW bridge): spawn server first, wait for its bridge contract, then spawn client agent.
- **Already-existing bridges**: full parallel.

### Cross-cutting auto-spawns
- New connection/event? → also spawn **janitor-lifecycle**.
- New bridge or remote? → also spawn **networking-specialist** to register in `Bridges.luau`.
- Data template change? → also spawn **server-handler** + **replication-specialist**.

### Agent spawn template
Every prompt MUST include — in this order, non-negotiable:
1. **"Read `.claude/reference/architecture.md` first"** — require paths, folder mapping, DataService/Bridges API, Critical Bans. Add **"and `.claude/reference/asset-discovery.md`"** if the task touches `StarterGui`/`Workspace`/`*.Assets`. Add **"and `.claude/reference/api-reference.md` for any package API call"** if the task calls Knit/BridgeNet2/Janitor/Signal/Replica/UIAnimator/ProfileStore/etc.
2. Data contract (bridge names + payload shapes) if applicable.
3. Files to READ before editing.
4. Files the agent OWNS vs must NOT touch.
5. Relevant bug patterns (mutex, no-yield-in-bridge, defensive logging per rule_8).
6. Verification commands the agent must run before reporting done (per rule_13).

---

## Self-Improvement Protocol

- After every task, correction, or detected mistake: review what went wrong and formulate a concise rule to prevent recurrence.
- Append it under **Learned Rules** below.
- If no new rule is needed, state "No CLAUDE.md update required."

---

## Learned Rules

<!-- Append game-specific patterns/anti-patterns as you discover them. Format: "NEVER/ALWAYS [rule] — [reason or commit/PR reference]" -->
