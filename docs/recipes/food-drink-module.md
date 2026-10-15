# Recipe: work in the Food and Drink buttons (`!!!TwichUI/modules/FoodDrink.lua`)

The file is about 900 lines (43 KB). Never read it whole. List its functions with their line numbers, then read
only the range you need:
`grep -n '^local function \|^function F\.\|^F\.[A-Z]* = \|^local KINDS' '!!!TwichUI/modules/FoodDrink.lua'`
then, with the line numbers grep printed (for example 558 to 603 for `Update`):
`sed -n '558,603p' '!!!TwichUI/modules/FoodDrink.lua'`

## Map (by name: line numbers change, so grep for them)
| Name | What it does |
|---|---|
| `F.CONJURED`, `KINDS` | conjured item IDs; the two buttons: `food` (switch `foodDrinkFood`), `drink` (`foodDrinkDrink`) |
| `F.Pick`, `F.Classify`, `F.IsFoodAndDrink`, `F.Inspect`, `Candidate`, `Scan` | which bag items qualify, and the best of each kind |
| `F.DEFAULTS`, `F.LIMITS`, `Valid`, `F.Get`, `F.Set`, `F.ResetLook` | the saved look, `TwichUIDB.ui.foodDrink` |
| `BuildButton`, `Style`, `Fill`, `Build` | the secure buttons; `Fill` sets which item a button uses |
| `Update` | shows each button whose switch is on, fills it, sizes and places the set |
| `Look` | runs `Update` only when the feature is on, the player is in the world and out of combat; in combat it sets `dirty` |
| `Schedule`, `OnRegenEnabled`, `OnDataLoaded` | one look per burst of events; the deferred look after combat |
| `F.Changed` | what a setting change redraws |
| `F.Refresh` | listens to events only while `foodDrink` is on; hides everything when it is off |
| `F.Snapshot`, `F.Brief` | read-only state for `/tui diagnostics` |

## Where things are decided
- Which buttons show: the loop over `KINDS` in `Update` (`R:Enabled(kind.setting)`); the set shows if any does.
  An empty button (nothing to eat or drink) still shows and says so in its tooltip.
- When a look runs: `F.Refresh` events (`BAG_UPDATE_DELAYED`, `GET_ITEM_INFO_RECEIVED`, `SPELL_TEXT_UPDATE`,
  `PLAYER_REGEN_ENABLED`, `PLAYER_LEVEL_UP`, `PLAYER_ENTERING_WORLD`) call `Schedule`, then `Look`, then `Update`.
  To look again on another event, add one line in `F.Refresh`: `Want("EVENT_NAME", Schedule, on)` (check the event
  first with `docs/recipes/wow-api-lookup.md`).
- Which item a button holds: `Scan`, then `F.Pick`.

## Rules in this file
- A button's item, size and place are secure: change them only out of combat. Keep the `InCombat()` check and
  the `dirty` flag in `Look`; never call `Fill` or `Style` during combat.
- Bags and item text are not ready at login: `Look` waits for `R.Life.InWorld()`, and `PLAYER_ENTERING_WORLD`
  asks for another look.
- Items are recognized by IDs and class numbers (`C_Item.GetItemInfoInstant`), never by English item text.
- TwichUI never uses an item itself: the player's click does, through the secure button.

## Worked example: the show/hide loop in `Update`
```lua
    for _, kind in ipairs(KINDS) do
        local button = buttons[kind.key]
        if R:Enabled(kind.setting) then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", container, "TOPLEFT", vertical and 0 or shown * step, vertical and -shown * step or 0)
            button:Show()
            Fill(button, best[kind.key])
            RefreshTooltip(button)
            shown = shown + 1
        else
            button:Hide()
        end
    end
    container:SetSize(F.FootprintFor(shown, size, F.Get("spacing"), vertical))
    Place(container)
    moveWaiting = false
    if F.Unlock then F.Unlock.Sync() end
    container:SetShown(shown > 0)
```

## Related files
Settings page: `TwichUI_Settings/pages/FoodDrink.lua` (page key `food`). `!!!TwichUI/modules/FoodDrinkUnlock.lua`
(EllesmereUI Unlock Mode), `!!!TwichUI/modules/FoodDrinkProbe.lua` (`/tui probe`), `!!!TwichUI/diag/Food.lua`.
Notes: `docs/food-drink-unlock.md`, `docs/lifecycle.md` (combat policy table). Tests, from the repo root:
`(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_food_drink.lua)`
(and the same with `test_food_drink_unlock.lua`), then `./tests/run.sh`.
