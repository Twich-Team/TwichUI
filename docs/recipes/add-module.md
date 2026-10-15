# Recipe: add a feature module and listen to game events

Every Lua file starts with `local R = TwichUI` and keeps everything `local`. A module publishes one table on `R`
(`R.QoLDuels = D`); that name is how `Switches.lua`, other files and the tests reach it.

## Steps
1. Create the file. A small opt-in convenience: `!!!TwichUI/qol/<Name>.lua` (shape A). A bigger feature:
   `!!!TwichUI/modules/<Name>.lua` (shape B). Start with a comment saying what it does and which game APIs and
   events it uses, each one checked with `docs/recipes/wow-api-lookup.md`.
2. List it in `!!!TwichUI/!!!TwichUI.toc` in its section, below every file it uses (`qol\<Name>.lua` goes below
   `qol\QoL.lua`), with backslashes like the lines around it. A file not in the .toc never loads.
3. Give it a switch: `docs/recipes/add-switch.md`. A QoL feature's line is `Define("qolX", QoL("QoLX"))`.
4. `luac5.1 -p` the file, check the globals it reads (`docs/recipes/wow-api-lookup.md` step 5), `./tests/run.sh`.

## Events
- `R:On("EVENT_NAME", fn)` and `R:Off("EVENT_NAME", fn)` (`!!!TwichUI/Core.lua`) share one frame: never create a
  frame just for events. `R:Off` needs the same function `R:On` got, so use named `local function`s.
- `fn` receives only the event's payload, in the order the API docs list it: `local function OnDuel(requester)`.
  There is no `self` and no event name argument.
- Listen only while the feature's switch is on, and stop when it turns off (shape A does this for you).
- `R:OnInit(fn)` runs once, after saved settings load and BEFORE the player is in the world. Bags, zone and level
  are not ready then: listen for `PLAYER_ENTERING_WORLD`, or check `R.Life.InWorld()` first.
- Many events at once (bag updates): set a flag and run once with `C_Timer.After(0.2, fn)`.

## Combat
Secure buttons and protected actions cannot change in combat. Check `InCombatLockdown()`; if true, set a `dirty`
flag and redo the work on `PLAYER_REGEN_ENABLED` (`Look` and `OnRegenEnabled` in `!!!TwichUI/modules/FoodDrink.lua`).
Never cast, use items, accept or sell for the player from a timer or an event.

## Shape A, worked example: `!!!TwichUI/qol/Duels.lua` (the whole file below its header comment)
```lua
local R = TwichUI
local Q = R.QoL
local D = {}
R.QoLDuels = D

local function Decline(requester, popups)
    if Q.Allowed(requester, Q.Get("duelsFrom")) then return end
    CancelDuel()
    for _, which in ipairs(popups) do StaticPopup_Hide(which) end
end

local ORDINARY = { "DUEL_REQUESTED" }
local LETHAL = { "DUEL_TO_THE_DEATH_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED_CONFIRM" }

local function OnDuel(requester) Decline(requester, ORDINARY) end
local function OnLethalDuel(requester) Decline(requester, LETHAL) end

D.feature = Q.Add({
    key = "qolDuels",
    guild = true,
    Events = function()
        local events = { DUEL_REQUESTED = OnDuel }
        if R:Enabled("qolDuelsToDeath") then events.DUEL_TO_THE_DEATH_REQUESTED = OnLethalDuel end
        return events
    end,
})
D.OnDuel, D.OnLethalDuel = OnDuel, OnLethalDuel
```
`Q.Add` (`!!!TwichUI/qol/QoL.lua`) takes `key` (its switch), `Events` (returns `{ EVENT = handler }` for now),
optional `Stop` (cancel pending work when it turns off) and `guild` (it reads the guild roster).

## Shape B: a module that turns its own listening on and off
Copy `local function Want` and `function F.Refresh` from `!!!TwichUI/modules/FoodDrink.lua`
(`grep -n 'local function Want\|^function F.Refresh' '!!!TwichUI/modules/FoodDrink.lua'`): `Refresh` calls
`Want(event, handler, R:Enabled("key"))` per event, is safe to call any time, and is wired with `R:OnInit(M.Refresh)`
and `Define("key", { apply = Refresh("ModuleName") })` in `Switches.lua`. Colors and fonts: reuse `R.Look`
(`!!!TwichUI/Look.lua`) or `R.ChronicleStyle` (`!!!TwichUI/chronicle/Style.lua`), never new color literals.
