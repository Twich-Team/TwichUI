# Recipe: add an on/off switch (a checkbox)

Use this when the checkbox turns a feature, or one part of it, on or off, and the rows near it on its page are made
with `Toggle(`. If they are made with `Proxy`, `ProxyToggle`, `Slider` or `Choice`, use
`docs/recipes/add-feature-setting.md` instead.
A switch is saved in `TwichUIDB.modules[key]`. Use a camelCase key that starts with its feature's prefix
(`foodDrink...`, `qol...`, `chronicle...`). A released key never changes.

## Steps (one file at a time; run `luac5.1 -p` on each file after editing it)
Find where the feature's existing switches sit in all four files at once (here for the `foodDrink` prefix):
`grep -n 'foodDrink' '!!!TwichUI/Core.lua' '!!!TwichUI/Switches.lua' '!!!TwichUI/setup/TwichConfig.lua' 'TwichUI_Settings/pages/FoodDrink.lua'`
1. `!!!TwichUI/Core.lua`, table `DEFAULT_MODULES`: add `key = false,  -- what it does` next to its feature's keys.
   New behavior is opt-in (`false`) unless the user says otherwise.
2. `!!!TwichUI/Switches.lua`: add a `Define` next to its feature's lines. It says what a change does:
   `Define("key", { apply = Refresh("FoodDrink") })` calls `R.FoodDrink.Refresh()` after every change.
   A QoL feature: `Define("key", QoL("QoLName"))`, using the name its file sets (`R.QoLDuels = D` gives
   `QoL("QoLDuels")`). Works only after a /reload: `Define("key", { reload = true })`.
3. `TwichUI_Settings/pages/<Page>.lua`, inside `build`, under the right `K.Header(...)`:
   `local row = K.Toggle("key", "Short label", "Tooltip: what happens, in plain sentences.")`
   The tooltip is required. If the row only matters while another switch is on:
   `K.Under(row, parentRow, function() return R:Enabled("parentKey") end)` (`parentRow` = what that `K.Toggle` returned).
   Many pages alias these at the top of `build`: `local Toggle, Under = K.Toggle, K.Under`.
4. `!!!TwichUI/setup/TwichConfig.lua`: every switch is either shared or kept local.
   - Shared: add the key to its page's `Switches(g, { ... })` list inside `local function Define()`.
   - Kept local: add `["modules.key"] = "acts",` to `TC.LOCAL`. Codes: `acts` (does something for the player:
     accepts, sells, declines, places a waypoint), `network` (talks to other players), `place` (a position), `other`.
   - A brand-new feature with no group yet: ask the user which one it should be.
5. `tests/test_settings_defaults.lua`: `assert(n == 54, "every module has a toggle: " .. n)` counts all toggles.
   Run that test and set the number to the N it prints (`every module has a toggle: N`).
6. Run `./tests/run.sh`. `test_settings_contract.lua` fails until its fixture is regenerated. Ask the user, then run
   `(cd tests && TWICHUI_GENERATE_CONTRACT=1 lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_settings_contract.lua)`
   then show `git diff --stat tests/fixtures/settings_contract.lua` and run `./tests/run.sh` again.

Read a switch with `R:Enabled("key")`. Change it from code only with `R:SetEnabled("key", on)`.
Settings search finds the row by its label and tooltip. Extra search words: `ALIASES` in `TwichUI_Settings/Search.lua`.

## Worked example: `foodDrinkFood` ("Show the Food button")
`!!!TwichUI/Core.lua` (`DEFAULT_MODULES`):
```lua
    foodDrink = false,       -- Food and Drink buttons: you click, they eat or drink the best food or drink in your bags (opt-in)
    foodDrinkFood = true,    -- ... the Food button
```
`!!!TwichUI/Switches.lua`:
```lua
Define("foodDrinkFood", { apply = Refresh("FoodDrink") })
```
`TwichUI_Settings/pages/FoodDrink.lua` (`foodDrink` is the row that `Toggle("foodDrink", ...)` returned just above):
```lua
        local function FoodDrinkOn() return R:Enabled("foodDrink") end
        Under(Toggle("foodDrinkFood", "Show the Food button",
            "Off: only the Drink button is shown."), foodDrink, FoodDrinkOn)
```
`!!!TwichUI/setup/TwichConfig.lua`:
```lua
    g = Group("food", "Food and drink", { page = "food" })
    Switches(g, { "foodDrink", "foodDrinkFood", "foodDrinkDrink" })
```
The feature reads it in `Update()` of `!!!TwichUI/modules/FoodDrink.lua`: `if R:Enabled(kind.setting) then`, where
`KINDS` gives the food button `setting = "foodDrinkFood"`.
