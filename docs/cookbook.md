# Cookbook

Concrete step-by-step recipes for common tasks in the boilerplate.

---

## 1. Add a new persistent data field

**File:** `src/ServerStorage/ServerUtilities/DataService.luau`

Find the `DATA_TEMPLATE` table and add your field with a sensible default:

```lua
local DATA_TEMPLATE = {
    cash = 0,
    wins = 0,
    inventory = {},
    myNewField = 0,  -- ← add here
}
```

ProfileStore's `profile:Reconcile()` automatically adds missing fields to existing player profiles on their next join. No migration script needed.

**Read it** from any server handler:
```lua
local value = DataService.Get(player, "myNewField")
```

**Write it**:
```lua
DataService.Set(player, "myNewField", 42)
```

If you want the field replicated to the client, that's already handled — `ReplicaService.NewReplica` is created with `Data = profile.Data`, so the client's `PlayerData.GetData().myNewField` returns the current value.

---

## 2. Add a Client→Server bridge

**File:** `src/Shared/Shared/Bridges.luau`

1. Declare the local near the other Client→Server bridges:
   ```lua
   -- Player did a thing
   -- { thingId: number }
   local DoThing = BridgeNet2.ReferenceBridge("DoThing")
   ```

2. Export it in the return table:
   ```lua
   return {
       -- ...
       DoThing = DoThing,
   }
   ```

**Server listener** (in a handler):
```lua
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)

local lock: { [number]: boolean } = {}

Bridges.DoThing:Connect(function(player, data)
    local uid = player.UserId
    if lock[uid] then return end
    lock[uid] = true
    task.spawn(function()
        local ok, err = pcall(function()
            -- validate data.thingId, mutate state, etc.
        end)
        lock[uid] = nil
        if not ok then warn("[MyHandler]", err) end
    end)
end)
```

**Client fire** (in a module):
```lua
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
Bridges.DoThing:Fire({ thingId = 5 })
```

---

## 3. Add a Server→Client notification

The `Notify` bridge is already wired. From any server handler:
```lua
local Bridges = require(game.ReplicatedStorage.Shared.Bridges)
Bridges.Notify:Fire(player, { type = "Success", message = "You earned 100 coins!" })
```

The client's `NotificationClient:Initialize()` already listens for `Notify` and calls `NotificationClient.Show(data.message, "Success")`. Nothing else to wire.

---

## 4. Persist a flag across sessions

Same pattern as recipe #1:

1. Add `myFlagClaimed = false` to `DATA_TEMPLATE` in `DataService.luau`
2. Set it from a server handler after the player earns whatever the flag represents:
   ```lua
   DataService.Set(player, "myFlagClaimed", true)
   ```
3. Read it to gate UI or handler logic:
   ```lua
   if DataService.Get(player, "myFlagClaimed") then return end  -- already claimed
   ```

On rejoin, ProfileStore loads the existing profile with the flag set — your gate still fires correctly.

---

## 5. Read a Roblox config from Creator Hub (A/B test pattern)

**Step 1: Create the config**

Go to Creator Hub → your experience → **Configs** → create a new config with:
- Key: `Uses_Cheap_Main_Product` (snake_case convention)
- Type: Boolean
- Value: `false` (default)

**Step 2: Add it to `RemoteConfigHandler.luau`**

The boilerplate's `RemoteConfigHandler.luau` already bridges `Uses_Cheap_Main_Product` by default. To add another config, copy the `applyConfig` pattern:

```lua
local CONFIG_KEYS = {
    "Uses_Cheap_Main_Product",
    "Enable_Holiday_Event",   -- ← new config
}

local function applyConfig(snapshot, key)
    local ok, value = pcall(function()
        return snapshot:GetValue(key)
    end)
    if not ok then return end
    Workspace:SetAttribute(key, value == true)
end

-- inside Initialize / UpdateAvailable handler:
for _, key in CONFIG_KEYS do
    applyConfig(snapshot, key)
end
```

**Step 3: Read from anywhere (server OR client)**

```lua
if workspace:GetAttribute("Enable_Holiday_Event") == true then
    -- show holiday UI / grant bonus / etc.
end
```

The `== true` strict check guards against nil during the ~1-5 second async fetch window before the server finishes reading the config.

**Step 4: Flip the toggle**

In the Creator Hub dashboard, flip the config value. Live servers see the change via `snapshot.UpdateAvailable` within ~5 minutes. No republish.

---

## 6. Hide a UI button when any frame is open

The `UIClient.updateQuickPlayVisibility()` function already iterates `ui.Frames` and hides a button when any frame inside is visible. To wire your own button:

1. Uncomment the `local quickPlayBtn = ...` line in `UIClient.luau`
2. Point it at your button: `local quickPlayBtn = ui.BottomMiddle:FindFirstChild("QuickPlay")` (or wherever your button lives)
3. That's it — every `OpenFrame`/`CloseFrame` call automatically re-runs `updateQuickPlayVisibility()` which hides/shows the button.

---

## 7. Grant a tool to the player's hands

From a server handler, after a successful purchase or grant:

```lua
local ToolConverter = require(game.ReplicatedStorage.Modules.ToolConverter)  -- if you add one

local function grantTool(player, itemName)
    InventoryHandler.AddItem(player, itemName)
    local tool = ToolConverter.CreateItemTool(itemName)
    if not tool then return end
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        tool.Parent = backpack
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(tool)
        end
    else
        tool:Destroy()
    end
end
```

**Important:** NEVER create tools inside `DataService.OnDataLoaded`. The boilerplate's handler boot order typically calls `player:LoadCharacter()` AFTER `OnDataLoaded`, which replaces the Backpack. Tools created during `OnDataLoaded` get destroyed by the character replacement. Instead, defer to a `CharacterAdded` listener or a bridge-fired grant.

---

## 8. Add a new dev product

**Step 1: Create the product on the Roblox Creator Hub**

Creator Hub → your experience → Monetization → Developer Products → Create. Note the product ID.

**Step 2: Add it to `ProductConfig.luau`**

```lua
ProductConfig.MyProduct = 1234567890  -- paste the real ID
```

**Step 3: Add a receipt branch in `ProductHandler.luau`**

```lua
local MY_PRODUCT_ID = ProductConfig.MyProduct

-- inside ProcessReceipt:
if receiptInfo.ProductId == MY_PRODUCT_ID then
    -- grant the thing
    DataService.Update(player, "cash", function(old) return (old or 0) + 100 end)
    return Enum.ProductPurchaseDecision.PurchaseGranted
end
```

**Step 4: Prompt the purchase from the client**

```lua
local MarketplaceService = game:GetService("MarketplaceService")
local ProductConfig = require(game.ReplicatedStorage.DataModules.ProductConfig)

MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, ProductConfig.MyProduct)
```

**Step 5 (optional): A/B test the price**

1. Create a SECOND dev product with a different price
2. Add `ProductConfig.MyProductAlt = <secondID>` and a getter:
   ```lua
   function ProductConfig.GetActiveMyProductId(): number
       if workspace:GetAttribute("Uses_Cheap_My_Product") == true and ProductConfig.MyProductAlt ~= 0 then
           return ProductConfig.MyProductAlt
       end
       return ProductConfig.MyProduct
   end
   ```
3. In ProductHandler, recognize BOTH IDs in the receipt branch (so pending purchases of either variant still grant):
   ```lua
   if receiptInfo.ProductId == MY_PRODUCT_ID or receiptInfo.ProductId == MY_PRODUCT_ALT_ID then
       -- grant
   end
   ```
4. On the client, use the getter for the prompt:
   ```lua
   MarketplaceService:PromptProductPurchase(LocalPlayer, ProductConfig.GetActiveMyProductId())
   ```
5. Add a new Config in Creator Hub (`Uses_Cheap_My_Product`, boolean) and extend `RemoteConfigHandler` to mirror it
6. Flip the config in the dashboard to switch between variants without republishing
