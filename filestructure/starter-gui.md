# StarterGui

**Last refreshed:** 2026-05-22T00:13:27Z
**Refresh command:** `mcp__Roblox_Studio__search_game_tree(path: "StarterGui", max_depth: 6)`

## Tree

- StarterGui (StarterGui)
  - Ui (ScreenGui)
    - HUD (Frame)
      - Notification (Frame)
        - UIAspectRatioConstraint (UIAspectRatioConstraint)
        - UIListLayout (UIListLayout)
        - Tutorial (Frame)
          - UIGradient (UIGradient)
          - Label (TextLabel) [...UIStroke, UIGradient — inspect via MCP]
        - SpecialNotification (Frame)
          - UIGradient (UIGradient)
          - Label (TextLabel) [...LocalScript, UIStroke, UIGradient — inspect via MCP]
        - Notification (Frame)
          - UIGradient (UIGradient)
          - Label (TextLabel) [...UIStroke — inspect via MCP]
        - Error (Frame)
          - UIGradient (UIGradient)
          - Label (TextLabel) [...UIStroke, UIGradient — inspect via MCP]
      - SidebarRight (Frame)
        - UIListLayout (UIListLayout)
        - Starterpack (TextButton)
        - SpecialBrainrot (Frame)
        - RandomLuckyBlock (Frame)
    - Frames (Folder)
  - Purchase (ScreenGui)
    - MonoUI (Frame)
      - BuyTransition (Frame)
        - Shadow (ImageLabel) [...UIGradient — inspect via MCP]
        - Icon (ImageLabel) [...UIAspectRatioConstraint — inspect via MCP]
        - Loading (TextLabel) [...UITextSizeConstraint — inspect via MCP]
  - LoadingScreen (ScreenGui)
    - Background (Frame) [...UIGradient — inspect via MCP]
      - Container (Frame) [...UIAspectRatioConstraint — inspect via MCP]
        - PlaceImage (ImageLabel) [...UICorner, UIStroke — inspect via MCP]
        - Dots (Folder) [...6 Frame children — inspect via MCP]
        - GameName (TextLabel) [...UIStroke — inspect via MCP]
        - ImageLabel (ImageLabel) [...LocalScript — inspect via MCP]
    - Animation (LocalScript)

---

After refreshing, bump `last-updated.json` → `"starter-gui"` to the current ISO timestamp.
