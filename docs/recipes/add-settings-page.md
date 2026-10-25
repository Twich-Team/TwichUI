# Recipe: add a settings page

Most new options belong on an existing page: add them there with `docs/recipes/add-switch.md` or
`docs/recipes/add-feature-setting.md`. Make a page only for a new feature with several options.
The settings window is its own load-on-demand addon, `TwichUI_Settings/`. Files in `!!!TwichUI/` never call into
it; its pages call the core (`R:Enabled`, a feature's `Get`/`Set`).

## Existing pages (`TwichUI_Settings/pages/`): key for `R:OpenSettings(key)`, (order), group
| File | Key (order) | Group |
|---|---|---|
| `Overview.lua` | `overview` (0) | `home` |
| `Notifications.lua` | `notifications` (20), tab `notificationsLook` (21) | `everyday` |
| `QoL.lua`, `Markers.lua` | `qol` (30), tabs `markersTarget` (31), `markersWorld` (32), `markersBar` (33) | `everyday` |
| `FoodDrink.lua` | `food` (40) | `everyday` |
| `Restock.lua`, `RestockItems.lua` | `restock` (45), tab `restockItems` (46) | `everyday` |
| `Auction.lua` | `auction` (80) | `everyday` |
| `Chronicle.lua` | `chronicle` (60), tab `chronicleLook` (61) | `journey` |
| `Pins.lua` | `pins` (70), tabs `pings` (71), `pinsLook` (72) | `map` |
| `MapToolbar.lua` | `mapToolbar` (71) | `map` |
| `Gear.lua` | `gear` (10), tab `statWeights` (11) | `class` |
| `Mage.lua` | `mage` (50), tab `refreshmentShares` (51) | `class` |
| `Ammo.lua`, `AmmoItems.lua` | `ammo` (52), tab `ammoCustom` (53) | `class` |
| `ClassBars.lua` | `classBars` (55), tabs `classBarsLayout` (56), `classBarsLook` (57), `classBarsEffects` (58) | `class` |
| `Skins.lua`, `SpeakStone.lua` | `skins` (90), tab `speakstone` (96) | `addons` |
| `RestedXP.lua` | `restedxp` (95) | `restedxp` |
| `Sharing.lua`, `Profiles.lua`, `Troubleshooting.lua` | `sharing` (100), `profiles` (105), `troubleshooting` (110) | `config` |

## Steps
1. Create `TwichUI_Settings/pages/<Name>.lua` from the worked example below. Give it a new `key`, a `name`, a
   `group` and an `order` not used in that group. A tab of another page sets `parent = "<key>"` instead of `group`.
2. List it in `TwichUI_Settings/TwichUI_Settings.toc` with the other `pages\...` lines, above `Search.lua`.
   `tests/test_settings_package.lua` fails when a Lua file in `TwichUI_Settings/` is not listed exactly once.
3. Add its rows with the switch and feature-setting recipes. `when = function() return R.X ~= nil end` hides the
   page in a session where its feature `R.X` is missing (the QoL page does this).
4. `luac5.1 -p` the page, run `./tests/run.sh`, and regenerate the contract fixture as in
   `docs/recipes/add-switch.md` step 6. A page with `parent` also needs its pair in the `under` table at the top of
   `tests/test_settings_defaults.lua` (`["<page name>"] = "<parent page name>"`).
5. To open it from code or a command: `R:OpenSettings("key")`, or `R:OpenSettings("key", "variable")` to show a row.

Page rules: `description` is one line; every tooltip is full sentences; a status shown on Home is a function
(`overview.status`), read when shown, never polled.

## Worked example: `TwichUI_Settings/pages/Auction.lua` (the whole file)
```lua
-- TwichUI settings: Auction House (auction/: the Sell from Bags tab).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "auction", name = "Auction House", order = 80, group = "everyday",
    description = "A Sell from Bags tab for listing items from your bags, one at a time.",
    keywords = "ah auction sell post price listing bags",
    overview = {
        label = "Auction House", tip = "A Sell from Bags tab for listing items one at a time.",
        status = function() return K.OnOff(R:Enabled("auctionPosting")) end,
    },
    build = function()
        K.Header("Sell from Bags", "A tab in the Auction House for listing items from your bags, one at a time.")
        K.Toggle("auctionPosting", "Add a Sell from Bags tab to the Auction House",
            "Lists the items in your bags that the auction house will take. Picking one searches its current listings (that item only, never the whole auction house) and suggests a price that matches the lowest comparable listing, with what it's based on. You set the quantity, price and duration; nothing is posted until you press Post. Results aren't saved.")
    end,
})
```
