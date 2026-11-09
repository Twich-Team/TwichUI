# Camping bar

A bar of buttons for WoW: Forever's camping. It fills itself from what the character knows and carries: the campfire kit you
hold, the camp objects your professions make (held ones, and ones you know the recipe for), and the Cozy Sleeping Bag once you
have it. Off until turned on (**Settings › Camping bar**). Move it in Edit Mode (drag; right-click puts it back).

## Files
`camping/Data.lua` (the facts; no game calls) · `camping/State.lua` (the rules; pure) · `camping/Bar.lua` (the buttons, events,
settings, look) · `camping/Rest.lua` (the sleeping bag's progress bar) · `camping/Unlock.lua` (the optional place in EllesmereUI's Unlock Mode) · `TwichUI_Settings/pages/Camping.lua`
(the page; its icon is `camping`, see `docs/settings-icons.md`). Tests: `tests/test_camping.lua`.

## What a click does
- Item in your bags (a kit, a camp object, the sleeping bag): the game's own secure button uses it, as the Food and Drink buttons do.
  TwichUI never uses an item itself.
- No kit in your bags but the Basic Campfire spell (818) known: the button casts that spell.
- A recipe you know with none made: the button is dimmed; a click opens the recipe in the professions window
  (`C_TradeSkillUI.OpenRecipe`). It crafts nothing.
Nothing is placed, crafted or cast except by your click.

## What is on the bar (`State.Plan`)
Order: the campfire, then professions in `D.GROUPS` order (lowest tier first), then the Cozy Sleeping Bag.
- **Campfire**: the largest kit held; else the spell; else a dimmed button for the largest kit recipe known (skill allowing).
- **Object**: held (count > 0) is `have`; otherwise `craft` if the recipe is known **and**, when the skill is readable, the skill is
  at least the recipe's. Only an explicit `true` from the game counts as "known": no answer, or `false`, offers nothing.
- **Only the best object of each profession**: what you hold beats what you could make, then the higher tier; ties (the two tier-1
  Tailoring banners) both stay.
- **Only what is in my bags**: drops the dimmed `craft` buttons (the Basic Campfire spell stays; it needs no kit).
- Each profession can be left out, and each object on its own (`obj_<itemID>`, under its profession's switch); the campfire and the
  bag can be left out.
- **Eat button** (off by default): see below.

## The eat button
One more button, last on the bar, for buff food in your bags ("Show an eat button"). A click eats the food and sits you down.
- **Which food** (`State.ChooseFood`): "the best buff food I have" (the most restored, then the smaller stack, then the lower item ID,
  the Food button's rule), or "the food I choose" (a list of the buff food in your bags when the page is opened; saved as
  `eatItem`, kept on this computer). A chosen food that isn't in the bags shows no button; nothing else is substituted.
- **What counts as buff food** is `FoodDrink.Inspect` with buff food let in: the item's own text, never a list. Nothing is read
  while the button is off.
- **The click** is a secure macro button: `/use <item name>` then `/sit` (`State.EatMacro`; a name with a control character is
  refused, so it can't carry a second command). "Sit down after eating" off makes it a plain item use. The button is a named frame,
  `TwichUICampingEat`, so Key Bindings has "Eat buff food and sit (Camping bar)" (`Bindings.xml`); no key is bound until you choose one.
- While on it also listens for `SPELL_TEXT_UPDATE` (food text still loading).

## The sleeping bag bar (`camping/Rest.lua`)
A progress bar to three minutes with a notch at each minute and a timer, shown while you lie in the Cozy Sleeping Bag (a minute is
+1% experience, to +3%). Part of the camping bar: on only while the camping bar is, with its own switch (`restShow`, on by default).
A plain frame: no clicks, nothing protected, shows in combat. It never uses the bag, plays a sound or speaks.
- **The rules** are pure, in `State.lua` (`RestStep`, `RestView`, `RestClock`, `RestTimerText`); `Rest.lua` reads the game and draws.
- **How it knows you are in the bag.** The game gives no buff during the first minute, so the clock can't start from an aura. It
  starts when `IsResting()` is true within 5 minutes (`D.REST_WINDOW`) of using the bag (the item's cooldown start, or its use spell
  succeeding) and a stack is still to be earned. Once the Well-Rested aura (`D.REST_AURA`, 429959, from a guide's link) exists, its
  stack count moves the clock forward to match, never back. Resting stopping for 2 s ends the clock; the bar stays `restLinger`
  seconds, then goes. A bag whose three minutes finished starts no new clock until it is used again.
- **Known weakness:** resting in an inn or city within 5 minutes of using the bag would also start it (the bag can't be used in a rested
  area, so the use itself is outside one).
- **Look** (all in `ui.campingBar`, `rest*` keys; a tab of its own on the Camping bar page, `TwichUI_Settings/pages/CampingRest.lua`).
  The bar: width, height, icon, "smooth" (off by default: the clock ticks 30 times a second instead of 5, and the fill's width isn't rounded to whole pixels; the game is still read every 0.2 s, the bar runs on the clock in between), fill texture (`MenuStyle.StatusBars`: flat, EllesmereUI's, LibSharedMedia's; a gone one draws flat and
  stays chosen), fill / "full" / background colour, opacity. Notches: colour and width. Border: texture (`Borders`: solid,
  EllesmereUI's, LibSharedMedia's; choosing one reseeds a thickness and colour that suit it unless you set your own), thickness 0-32,
  class colour, colour, opacity. Text: font (`MenuStyle.Fonts`, same fallback rule), outline (none / outline / thick), and for the label
  and the timer each its own size and colour; timer (time left / time in the bag / time to the next minute / none), the label on or off.
  Then seconds to stay when done. "Show a sample" runs the whole bar at 15x speed; Edit Mode shows it at 1:30
  with an outline to drag (right-click puts it back). **Three ways to move it:** the settings' "Move the sleeping bag bar" button
  (the same sample and outline without Edit Mode; Done, closing the settings or Edit Mode ends it), Edit Mode, or, with "Use EllesmereUI
  Unlock Mode" on, the "TwichUI Sleeping bag bar" anchor in `/unlock` (one stand-in, same machinery as the camping bar's, made by
  `Make` in `camping/Unlock.lua`; this bar is a plain frame, so it follows the stand-in in combat too). Its place is
  `ui.campingRestPosition { x, y }` (kept on this computer by sharing).
- **Cost.** Events only while on: `PLAYER_UPDATE_RESTING`, `PLAYER_ENTERING_WORLD`, `BAG_UPDATE_COOLDOWN`, and the player's own
  `UNIT_AURA` and `UNIT_SPELLCAST_SUCCEEDED`; a look while nothing is showing and you are not resting reads one API call. A 0.2 s
  ticker (1/30 s with "smooth" on) runs only while the bar is on screen. Scope `camping.rest`; gauges `camping.rest.events`, `camping.rest.ticks`.
- **`/tui camp probe`** prints what the client says now: resting, the aura's stacks, when the bag was used, the bag's use spell, the
  bar's state and your buffs (name, ID, stacks, seconds). `probe watch` records 6 minutes of resting/aura/cooldown/cast events (80 at
  most, kept in memory only), `probe show` prints them with a snapshot, `probe stop` ends it.
- **Unverified (none of it read from a Forever client):** that `IsResting()` turns true while lying in the bag and false when you leave;
  that using the bag starts a cooldown or a use spell that is readable (`C_Container.GetItemCooldown`, `C_Item.GetItemSpell`); that the
  buff is spell 429959, is one aura with stacks (not three spells) and appears at the one-minute mark; what a stop in the middle does
  to the stacks (the guides don't say).

## When it shows (`State.Visible`)
Hide in dungeons / raids / battlegrounds and arenas / rested areas / combat, and "only near a campfire". The bar is a plain frame
holding the secure buttons, so showing, hiding and fading work in combat. "Near a campfire" reads the `Campfire Nearby` aura
(1283391); the game may not answer in combat, and then the bar stays as it was. Not knowing never hides. While Edit Mode is open the
bar is shown so it can be placed.

## Where it sits
Edit Mode: an outline over the bar (drag; right-click puts it back). Or, with "Use EllesmereUI Unlock Mode" (`unlockMode`, off by
default, kept on this computer) and EllesmereUI installed, a "TwichUI Camping bar" anchor in `/unlock`, through EllesmereUI's public
registration calls only. EllesmereUI moves a plain stand-in frame as big as the bar; the secure buttons never hang from it, and the
bar follows out of combat only (in combat it waits). The place is still `ui.campingBarPosition`. Registered once per session and never
unregistered (that would delete your anchor links there). Modelled on `buffback/Unlock.lua`.

## Look
Button size, spacing, buttons per row, rows or columns, border (texture, thickness, colour or class colour, opacity; EllesmereUI's
textures through `modules/Borders.lua`), icon zoom, count, bar opacity and fade-until-mouse-over (as the Food and Drink buttons).
Secure buttons can't change in combat: a change waits for it to end; opacity and visibility apply at once.

## Saved
Profile: switch `campingBar`; `ui.campingBar` (`C.DEFAULTS`: look, what is on it, `grp_<profession>`, `obj_<itemID>`, the eat button's
`eat`/`eatMode`/`eatSit`, when it shows); place `ui.campingBarPosition { x, y }`. Kept on this computer by configuration sharing:
the place and `unlockMode` (class "place"), the chosen food `eatItem` (class "other"). Nothing about what is
shown now is saved.

## Cost and diagnostics
Events only while on (the eat button adds a read of the bags' food text, once per look): `BAG_UPDATE_DELAYED`, `SKILL_LINES_CHANGED`, `SPELLS_CHANGED`, `NEW_RECIPE_LEARNED`,
`PLAYER_ENTERING_WORLD`, `GET_ITEM_INFO_RECEIVED`, `PLAYER_REGEN_ENABLED`, `BAG_UPDATE_COOLDOWN`; plus
`PLAYER_REGEN_DISABLED` / `PLAYER_UPDATE_RESTING` / `UNIT_AURA` only while a visibility choice needs them, and `SPELL_TEXT_UPDATE` only
with the eat button on. A look (about 40 item counts,
40 recipe reads, the skill list) is coalesced for 0.2 s. No `OnUpdate`. Scope `camping.look`; gauges `camping.events`,
`camping.buttons`, `camping.looks`. A failed item load (`GET_ITEM_INFO_RECEIVED` with `success == false`) is not asked for again.

## Where the data comes from, and what is not established
No camping data is in the Forever UI source. Item IDs and names come from EllesmereUI's bag categories; craft spells and skills from
NaowhForever's recipe data; Herbalism and Skinning craft spells from a public camping guide. Both addons are all rights reserved:
only the facts (IDs, names, skill numbers) are used, and nothing of them is loaded or called. **None of it has been read from a
Forever client.** A wrong ID can only make a button missing, never a wrong action. Unverified, in particular:
- the six Herbalism and Skinning craft spell IDs and their pairing with items; the skill line IDs 182 (Herbalism) and 393 (Skinning);
- which of the two tier-1 Tailoring banners belongs to which faction (the recipe you know decides);
- whether an object is used up when placed (affects only the "in my bags" wording);
- whether tier 2/3 objects keep the tier-1 buff (the guides say so; "best" relies on it);
- that Basic Campfire is still spell 818 (EllesmereUI casts it), and that the kit recipes' skills (90 and 200) are the learn levels
  (a guide says they can be used at 140 and 220).

## Not built (decided, not forgotten)
- A real macro in your macro list: the eat button is a button (and a key binding), which needs no macro slot and can be updated by
  the bar; a macro can't be changed while you're in combat.

## In-game checks (none done yet)
- The sleeping bag bar: place and use the bag, walk onto it, and lie in it for three minutes with `/tui camp probe watch` running, then
  `/tui camp probe show`. Does `resting` turn true when you lie down (and how long after), and false when you leave? Does the
  Well-Rested aura (429959) appear at 1:00 with one stack, and do the stacks reach 3? Is the bag's use readable ("bag used" and the
  use spell)? Does the bar start, fill, notch and finish together with the real buff? Does a sample (settings) look right; does
  the Move button, Edit Mode, and (with EllesmereUI) the Unlock Mode anchor move the bar? Does it show in combat?
- Does `C_SpellBook.IsSpellKnown(<craft spell>)` or `C_TradeSkillUI.GetRecipeInfo(<spell>).learned` say true for a recipe the
  character knows, without the professions window open? If neither does, only held objects appear.
- `C_SkillInfo.GetSkillLineInfo` lists the profession lines with `skillID` and `rank`; the IDs match `D.GROUPS`.
- A held kit and object: click uses them (secure item by name); an object held with the name not yet cached becomes usable once loaded.
- A known recipe with none made: dimmed; the click opens that recipe in the professions window.
- The shared one-hour cooldown shows on held objects (`C_Container.GetItemCooldown`).
- Basic Campfire spell (818): the button casts it when no kit is held.
- Hide in dungeon / raid / battleground / rested / combat; near-a-campfire with the real aura; fade until the mouse is over it.
- Edit Mode: the outline appears, drags, right-click resets; after combat the bar moves.
- Leaving the settings page and `/reload` keep every choice; a profile change redraws the bar.
- Eat button: `/use <food>` then `/sit` run from a secure macro button (is `/sit`, an emote, allowed there? If not, turn "Sit down
  after eating" off); the key binding clicks it; "the food I choose" lists the buff food in the bags; a food whose text hasn't
  loaded appears after it does.
- Unlock Mode with EllesmereUI: the anchor appears, dragging/nudging/anchoring moves the bar (after combat if in combat), Reset
  position puts both back.
- Left-off objects (a profession's and an individual one) stay off after `/reload`.

