# Workspace

**Last refreshed:** NEVER — populate on first session with Studio connected.
**Refresh command:** `mcp__Roblox_Studio__search_game_tree(path: "Workspace", max_depth: 6)`

## Tree

<!--
Populate from MCP. Format:
- Two-space-indented bullets
- `- Name (ClassName)` per line
- No properties, attributes, or asset IDs
- Depth cap: 6 levels. Beyond that: `- Name (ClassName) [...N descendants — inspect via MCP]`

Skip the default Roblox-generated children that are never gameplay-relevant
(`Camera`, `Terrain`) unless a descendant matters. Keep `Baseplate`, `SpawnLocation`,
and anything custom.
-->

- Workspace (Workspace)
  <!-- children go here -->

---

After refreshing, bump `last-updated.json` → `"workspace"` to the current ISO timestamp.
