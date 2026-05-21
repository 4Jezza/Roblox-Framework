# filestructure/ — asset tree snapshots

This folder holds committed snapshots of each Roblox asset tree that is NOT synced by Argon. Agents read these MD files as a cheap first pass before calling Roblox Studio MCP, and refresh them whenever MCP reveals new or changed instances.

> **Rule (see `CLAUDE.md` rules 12–14):** Assets are MCP-only. Scripts stay on Argon. Never edit Instance structure in the local `src/` — those roots are not synced.

---

## What each file covers

| File | Roblox root | MCP call to refresh |
|---|---|---|
| `starter-gui.md` | `StarterGui.*` | `mcp__Roblox_Studio__search_game_tree(path: "StarterGui", max_depth: 6)` |
| `workspace.md` | `Workspace.*` | `mcp__Roblox_Studio__search_game_tree(path: "Workspace", max_depth: 6)` |
| `replicated-storage-assets.md` | `ReplicatedStorage.Assets` | `mcp__Roblox_Studio__search_game_tree(path: "ReplicatedStorage.Assets", max_depth: 6)` |
| `server-storage-assets.md` | `ServerStorage.Assets` | `mcp__Roblox_Studio__search_game_tree(path: "ServerStorage.Assets", max_depth: 6)` |
| `last-updated.json` | (metadata) | Bump the matching key when you refresh an MD. |

---

## Format spec

- Two-space-indented bullets, one instance per line: `- Name (ClassName)`.
- Nest children by indentation.
- **No properties, attributes, asset IDs, or script bodies.** Just the tree.
- Depth cap: **6 levels**. Beyond that, write `- Name (ClassName) [...N descendants — inspect via MCP]` to keep context bounded.
- One file per asset root. Never merge roots.

Example:

```md
- StarterGui (StarterGui)
  - MainGui (ScreenGui)
    - TopBar (Frame)
      - WinsLabel (TextLabel)
      - CoinsLabel (TextLabel)
    - Notifications (Frame)
      - Template (Frame)
```

---

## Refresh protocol

1. **Before a task touches any asset path**, read the matching MD in this folder. Cheap, keeps instance names fresh in context.
2. **Before acting on a path** (editing a script to reference it, writing new code), verify with `mcp__Roblox_Studio__inspect_instance(path: "...")` — the MD is a cache, not truth.
3. **After** `search_game_tree` or `inspect_instance` returns new/changed nodes: rewrite the matching MD and bump the timestamp in `last-updated.json`.
4. **If `mcp__Roblox_Studio__list_roblox_studios` returns empty**, STOP. Tell the user Studio isn't connected. Do NOT fabricate paths from stale MD.

---

## Asset vs Script split (one-liner)

| Target | Tool | Reason |
|---|---|---|
| UI, Workspace parts/models, `ReplicatedStorage.Assets`, `ServerStorage.Assets` | **MCP** | Not Argon-synced — these roots live in-Studio only |
| Scripts, LocalScripts, ModuleScripts, `DataModules/*.luau` | **Argon** (Read/Edit/Write) | Text files — reliable sync |

Full rule set: `CLAUDE.md` → rules 12–14 and `.claude/reference/asset-discovery.md`.

---

## When you fork the boilerplate

1. Open the game in Studio. Drag in your UI, Workspace models, and any pre-baked `ReplicatedStorage.Assets` / `ServerStorage.Assets` content.
2. Run one `mcp__Roblox_Studio__search_game_tree` per root and rewrite the corresponding MD.
3. Bump every key in `last-updated.json` to the current ISO timestamp.
4. Commit `filestructure/` so future sessions start warm.
