---
name: add-service
description: Scaffold a new Knit Service with proper patterns and wiring
disable-model-invocation: true
---
Add a new Knit Service: $ARGUMENTS

## Steps

1. **Create service** at `sync/ServerScriptService/Server/Services/<Name>Service.luau`:
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NameService = Knit.CreateService {
    Name = "NameService",
    Client = {},
}

function NameService:KnitInit()
    -- Setup state only. No inter-service calls.
end

function NameService:KnitStart()
    -- Safe to call other services here.
end

return NameService
```

2. **Loader auto-discovers** — no manual require needed (SSA + Loader).

3. **Add config** in `sync/ReplicatedStorage/Shared/<Name>Config.luau` if needed.

4. **Add types** in `sync/ReplicatedStorage/Shared/<Name>Types.luau` if needed.

5. **Add bridges** in `Bridges.luau` if client communication needed.

6. **Use Option** for methods that may return nil:
```lua
local Option = require(ReplicatedStorage.Packages.Option)
function NameService:GetThing(id)
    return Option.Wrap(self._things[id])
end
```
