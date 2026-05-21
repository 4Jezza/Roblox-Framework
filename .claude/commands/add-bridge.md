---
name: add-bridge
description: Scaffold a new BridgeNet2 bridge with server and client patterns
disable-model-invocation: true
---
Add a new BridgeNet2 bridge: $ARGUMENTS

## Steps

1. **Check existing bridges** in `sync/ReplicatedStorage/Shared/Bridges.luau`.

2. **Add bridge definition**:
```lua
-- Server → Client (or Client → Server)
Bridges.BridgeName = BridgeNet2.ReferenceBridge("BridgeName")
```

3. **Server-side pattern**:
```lua
Bridges.BridgeName:Connect(function(player, data)
    assert(typeof(data) == "table")
    -- validate + process
end)
Bridges.BridgeName:Fire(player, { key = value })
```

4. **Client-side pattern**:
```lua
Bridges.BridgeName:Connect(function(data) end)
Bridges.BridgeName:Fire({ key = value })
```

5. **Warn** if existing bridge covers this use case.
6. Single table argument — never multi-param.
