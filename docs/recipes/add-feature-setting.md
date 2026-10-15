# Recipe: add a setting a feature stores (option checkbox, slider, dropdown, color)

Use this when the rows near the new one are made with `Proxy`, `ProxyToggle`, `Slider`, `Choice`, `Dropdown` or
`Swatch`. The value lives in the feature's own table, `TwichUIDB.ui.<table>`, and only the feature's `Set` writes
it; a page never writes `TwichUIDB`. Turning a whole feature on or off is a switch: `docs/recipes/add-switch.md`.

## Steps (one file at a time; run `luac5.1 -p` on each file after editing it)
1. The feature file (find its store: `grep -n 'DEFAULTS\|Valid\|\.Get(\|\.Set(' '<feature file>'`): add the key
   and its default to `DEFAULTS` (number ranges also to `LIMITS`), accept it in the validity check (`BR.Valid`
   below, `Valid` in `modules/FoodDrink.lua`, `Q.CHOICES` in `qol/QoL.lua`), and read it only through `Get("key")`.
   FoodDrink only: also place it in `F.Changed(key)` (`ALPHA_KEYS`, `LOOK_KEYS`, else a full refresh).
2. `TwichUI_Settings/pages/<Page>.lua`: add one row (shapes below). Its first argument is a new variable name,
   feature prefix + key in camelCase (`pinsBarIcon`). A name used twice stops the window with an error.
3. `!!!TwichUI/setup/TwichConfig.lua`: add the key to the feature's `Table(g, { "ui", "<table>" }, ..., { keys })`
   list (shared), or add `["ui.<table>.<key>"] = "place",` (or another code) to `TC.LOCAL` (kept local).
   `tests/test_twichui_share.lua` fails for a `DEFAULTS` key that is in neither.
4. Run `./tests/run.sh`, then regenerate the contract fixture exactly as in `docs/recipes/add-switch.md` step 6.

## Row shapes (`TwichUI_Settings/Kit.lua`)
- Checkbox: `K.ProxyToggle(variable, label, tooltip, default, get, set)`
- Slider: `K.Slider(K.Proxy(variable, K.NUMBER, label, default, get, set), min, max, tooltip)`; round in `set`.
- Dropdown: `K.Choice(variable, label, tooltip, K.STRING, default, get, set, { { "value", "Label" } })`
- Color, saved as `"AARRGGBB"` text: `K.Swatch(K.Proxy(variable, K.STRING, label, default, get, set), tooltip)`
Wrap a row in `K.Under(row, parentRow, isOn)` when it only matters while a switch is on.

## Worked example: Party pins, "Show the icon on the data bar" (`icon` in `TwichUIDB.ui.pinsBroker`)
`!!!TwichUI/pins/Look.lua` (`BR` is `R.PinsLook.Bar`; `BAR_TEXT` and `BarChanged` are locals of that file):
```lua
BR.DEFAULTS = { text = "count", icon = true, customColor = false, color = "ffc9a34a",
    flash = true, flashSeconds = 8, flashColor = "ffe8b64a" }
function BR.Valid(key, value)
    if key == "text" then return type(value) == "string" and BAR_TEXT[value] == true end
    if key == "icon" or key == "customColor" or key == "flash" then return type(value) == "boolean" end
    if key == "color" or key == "flashColor" then return Valid("accentColor", value) end
    if key == "flashSeconds" then
        local l = BR.LIMITS.flashSeconds
        return type(value) == "number" and value == value and value % 1 == 0 and value >= l[1] and value <= l[2]
    end
    return false
end
function BR.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.pinsBroker
    local value
    if type(t) == "table" then value = t[key] end   -- not "and ... or": a saved false is a value
    if BR.Valid(key, value) then return value end
    return BR.DEFAULTS[key]
end
function BR.Set(key, value)
    if BR.DEFAULTS[key] == nil or not BR.Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.pinsBroker) ~= "table" then TwichUIDB.ui.pinsBroker = {} end
    if TwichUIDB.ui.pinsBroker[key] == value then return true end   -- unchanged: nothing to redraw
    TwichUIDB.ui.pinsBroker[key] = value
    BarChanged()
    return true
end
```
`TwichUI_Settings/pages/Pins.lua` (`local BR = PL.Bar`; `pinsToggle` is the Party pins switch row):
```lua
        Under(ProxyToggle("pinsBarIcon", "Show the icon on the data bar",
            "The small map icon beside the text. Off leaves just the text. It always shows while the text is set to None, so the entry is never empty.",
            BR.DEFAULTS.icon, function() return BR.Get("icon") end, function(value) BR.Set("icon", value and true or false) end),
            pinsToggle, PinsOn)
```
`!!!TwichUI/setup/TwichConfig.lua` (shared):
```lua
        Table(g, { "ui", "pinsBroker" }, PL and PL.Bar, { "text", "icon", "customColor", "color", "flash", "flashSeconds", "flashColor" },
            { text = ENUM.barText })
```
