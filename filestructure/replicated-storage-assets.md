# ReplicatedStorage.Assets

**Last refreshed:** NEVER — populate on first session with Studio connected.
**Refresh command:** `mcp__Roblox_Studio__search_game_tree(path: "ReplicatedStorage.Assets", max_depth: 6)`

## Tree

<!--
Populate from MCP. Format:
- Two-space-indented bullets
- `- Name (ClassName)` per line
- No properties, attributes, or asset IDs
- Depth cap: 6 levels. Beyond that: `- Name (ClassName) [...N descendants — inspect via MCP]`

This root is intentionally absent from `default.project.json` — it lives
in-Studio only. Create the `Assets` folder under `ReplicatedStorage` inside
Studio when your fork needs client-visible VFX/model assets.
-->

- Assets (Folder) [`ReplicatedStorage.Assets`]
  <!-- children go here; create the folder in Studio first -->

---

After refreshing, bump `last-updated.json` → `"replicated-storage-assets"` to the current ISO timestamp.
