# Mage refreshments

For anyone changing the refreshments feature. Code: `modules/Refreshments.lua` (shares, roster, session, plan),
`modules/RefreshmentsPanel.lua` (the window and its secure buttons), `modules/RefreshmentsShares.lua` (the shares page
in Options), `modules/RefreshmentsBroker.lua` (the data bar plugin), `diag/Refreshments.lua`, `Bindings.xml`. Tests: `tests/test_refreshments.lua`. **Nothing here has been
verified in the game yet**; see "Manual acceptance test".

Milestone 1: plan, conjure by click or key, checklist. Milestone 2: trade assistance (a **Fill trade** button and
delivery tracking), at the end of this file.

## What it does, and what it never does

- Mages only, off by default (`modules.mageRefreshments`). On another class nothing is registered and the command
  and key say it is for Mages. Off, nothing listens and the conjure keys do nothing (their buttons are emptied).
- **Shares**: single items (never stacks) per class, one table for a party and one for a raid, plus what the Mage
  keeps. Starting amounts are a guess for the player to change, not a claim about what a class needs.
- **Plan**: each group member's share at the best rank the Mage knows that the member's level can use, less what
  was marked handed over; summed per item with the Mage's reserve (at the Mage's own best rank), against the bags.
  Nothing is inferred about what anyone else carries. An unread level plans the best rank and says so; an unread
  class gets no share.
- **Conjure buttons**: the game's own secure buttons, one cast per click or key press, on the release (so a drag
  never casts). Each holds the best rank still short of the plan, else the best rank known. Their spell changes only
  out of combat; a change in combat waits for it to end. They exist whenever the feature is on, so their keys work
  with the panel shut.
- **Checklist**: by GUID, marked by hand (Supplied, Clear, plus or minus a stack). The first member not yet supplied
  (and online) is marked "next".
- Never: casting by itself, repeating or stopping a cast, editing action bars or key bindings, changing game
  settings, moving bag items except inside a Fill trade click, opening or accepting trades, whispering or chat,
  sounds.

## Appearance

The panel and its trade strip share a look the player sets on the Mage page (**Refreshments panel appearance**):
background texture, color and opacity; border texture, thickness (screen pixels, 0 to 16), color and opacity; a
**Preview** (the real panel, opened beside the Options window) and a **Reset**. It is a second instance of the
broker menus' look (`R.MenuStyle.New("refreshmentsStyle", defaults)` in `modules/MenuStyle.lua`), so it offers the
same textures. Backgrounds: the game's own, the textures EllesmereUI offers for its own backgrounds (read from its
`EllesmereUI.BuildBarTextureTables`, while it is installed), and LibSharedMedia's background and status bar textures
(EllesmereUI offers status bars as backgrounds too); EllesmereUI's and the status bar ones are stretched and tinted, as
EllesmereUI draws them. Borders: the game's own, EllesmereUI's own border textures (drawn by its `ApplyBorderStyle` on a
frame of TwichUI's), and LibSharedMedia's. Nothing of EllesmereUI's is copied. Saved apart from
the menus' look, in `TwichUIDB.ui.refreshmentsStyle`, only the values changed; checked on every read. The defaults are
the Chronicle's umber with a 1-pixel bronze line.

The look is drawn on the outer frame; the content sits in a fixed-size frame inside it, and the outer frame grows by
the border's thickness on each side, so a thick border never covers anything. The panel holds secure buttons, so it
is redrawn only out of combat (a change made in combat waits for it to end); it is redrawn when it opens, at once
while open, and on a UI scale change. The trade strip has no secure parts and follows at once.

## Data bar plugin

"TwichUI Mage Refreshments", a LibDataBroker data source for any data bar that lists them (EllesmereUI's Broker
Plugin block follows its text as it changes). Made for a Mage once the feature is on, at login or when it is turned
on, without a reload; never for another class. Text (`TwichUIDB.ui.refreshmentsText`): `progress` ("3/5 supplied",
"Refreshments" on your own), `label`, or `none`; "Off" once turned off, until a reload (a data object can't be
removed). Tooltip: water and food prepared against the plan, who is supplied, who is next, trades to confirm. Click
toggles the panel (refused in combat like the panel); right-click opens the Mage options page. It only reads the plan.

## Why there is no hold-to-cast from TwichUI's buttons

From `../wow-ui-source` (branch `forever`, 1.60.1.70170):

- The game repeats a held cast only for `UseAction(slot, unit, button, isKeyPress)` with `isKeyPress` true
  (`SecureTemplates.lua`, `SECURE_ACTIONS.action` and `SecureActionButton_OnClick`).
- Only Blizzard's action-bar key handlers pass it: `ActionButtonDown` / `MultiActionButtonDown` →
  `TryUseActionButton` (`ActionButton.lua`, `MultiActionBars.lua`).
- `SecureTemplates.xml` says addon buttons "won't be able to have isKeyPress … set", and `SECURE_ACTIONS.spell`
  casts with `CastSpellByID` and no key-press flag. A mouse press never repeats.

So a TwichUI button (or a key bound to it) casts once per press, and nothing TwichUI does can stop a held cast at a
target. The supported way to hold a key is the player's own action bar: dragging a conjure button puts the spell
on the cursor (`C_Spell.PickupSpell`, out of combat) to drop there, with Options > Combat > Press and Hold Casting
on. The panel's bar turns green, and one line in the error-message area says "Enough water prepared." once, when a
kind reaches the plan within ten seconds of a conjure. Letting go is the player's. A last cast may overshoot by up to
one cast's worth.

Not done, on purpose: borrowing a slot on the player's action bars and pointing their key at it (what Conjurer does
to get a hold that stops at the target). It edits the player's bars and relies on client behaviour that is not
documented.

## Data and its provenance

- Ranks: `MageConjure.SPELLS` (What's Training?'s Forever data, six ranks each).
- Items and the level each needs (`RF.ITEMS`, `RF.USE_LEVEL`): the Classic-era game's, the same IDs as
  `FoodDrink.CONJURED` (a test checks they agree). **Not read from the Forever client.** Conjurer and Water Dispenser
  both list a seventh rank for Forever (spells 10140 and 28612, items 8079 and 22895, usable from 55) that TwichUI's
  training data does not have; it is left out until seen in the game.
- Items per cast: learned while playing from the bags (the gain in that item's count by the next conjure or after
  three seconds), per spell and level, in memory only, values outside 1 to 60 ignored. Shown as "about".
- Stack size: `C_Item.GetItemMaxStackSizeByID`; bag room counts ordinary bags only.

## Saved and not saved

- Saved: `TwichUIDB.ui.refreshments = { party = { [CLASS] = { water, food } }, raid = { ... }, reserve = { water,
  food }, position = { x, y } }`. Only changed values are stored; a value is checked each time it is read (whole
  number 0 to 200) and an unusable one falls back to the default without being erased. Reset shares keeps the
  position. `Persist.lua` checks that the group is a table.
- Not saved: the session (who was handed what), roster, names, items-per-cast, pending work. A reload, leaving the
  group (`GROUP_LEFT`, or finding yourself out of a group) or **Reset session** starts it again. Up to 40 people who
  left are remembered for the session in case they come back.

## Lifecycle

| Situation | Behaviour |
|---|---|
| Login, reload | Listens only if a Mage with the switch on, from `PLAYER_LOGIN`; looks once in the world |
| Roster, level, connection, bags, spells | One look per burst (0.2 s); a look whose generation is stale does nothing |
| Combat | Panel won't open; closes at `PLAYER_REGEN_DISABLED` (or when combat ends if too late); button spells wait; a roster that can't be read in combat is kept until it ends |
| Turned on in combat | Secure buttons are made when combat ends |
| Switch off | Events unregistered, session and learned yields wiped, panel closed, buttons emptied |
| Left the group | Session reset |
| Party to raid | Same records by GUID; raid shares |

Reason codes: `deferred-combat`, `waiting-for-world`, `cancelled-stale-refreshments`, `refreshments-reset-manual`,
`refreshments-reset-left-group`, `trade-place-not-shown`, `trade-split-not-seen`, `trade-not-completed`,
`trade-move-blocked`.

## Manual acceptance test

Turn on **Display Lua Errors**. After each step check `/tui diagnostics` (Mage refreshments) and that no Lua error or
"action blocked" message appeared. Test TwichUI alone, then with EllesmereUI and with Conjurer or Water Dispenser
installed.

1. **Non-Mage.** Switch it on in a Mage's settings, log a warrior: no Mage page, `/tui refreshments` and the key
   say it is for Mages; diagnostics "for Mages only".
2. **Off.** On a Mage with it off: the keys do nothing; no menu entry in Mage Conjuring.
3. **Solo.** Turn it on: the panel shows only what you keep. Shares page edits (0, 200, 201 refused, Esc reverts).
4. **Party.** With a low-level and a high-level member: each row's rank fits their level; totals per rank in the
   tooltip; the next marker; Supplied, Clear, plus and minus a stack; Reset session asks first.
5. **Click and key.** Click Water: one cast. Bind Key Bindings > TwichUI > Conjure water; hold it: **expect one cast
   per press** (record whether it repeats). With "Cast on key down" on and off.
6. **Drag and hold.** Drag Water to an action bar, turn on Press and Hold Casting, hold its key: repeats; the bar goes
   green and "Enough water prepared." shows once; record by how many items it overshot after letting go.
7. **Items per cast.** After two casts the detail says "about N casts of M"; compare M with the bags.
8. **Bags.** Nearly full bags: "bags hold only N more". Full bags: the game's own refusal.
9. **Mana and interruption.** Run out of mana; interrupt a cast by moving: counts stay right, nothing stuck.
10. **Combat.** Enter combat with the panel open: it closes. Try to open in combat: refused. Change bags in combat:
    the button keeps its spell, diagnostics "deferred"; after combat it updates once. Press the conjure key in
    combat: whatever the game allows for that spell.
11. **Party to raid, leave and rejoin, roster order.** Records follow the person, not the name or position.
12. **Leaving the group, reload, switching off.** Each starts a fresh checklist; nothing returns after a reload.
13. **Screen.** Smallest window and largest UI scale: the panel fits; long names are cut and readable in the tooltip.
14. **Data.** Record the item IDs your conjures make (`/tui probe`) and whether a seventh rank exists on Forever.
15. **Trade opens.** Trade a group member: the strip appears under the trade window; nothing moves by itself. With
    Conjurer or Water Dispenser filling automatically, Fill counts what they put in.
16. **Fill, whole stacks.** Owed 40, two full stacks: one click puts both in; record any "action blocked" message.
17. **Fill, a split.** Owed 25 with two full stacks: one click puts 20 in and splits 5 into a bag slot; the button
    waits, then a second click adds the 5. Record whether the split reads on the cursor at once (if the strip says
    "didn't split", it doesn't).
18. **No bag slot.** Full bags with a part stack owed: "Free a bag slot", nothing over-given.
19. **Your own items.** Put linen and some water in first: they stay where they are; the water counts.
20. **Cursor, combat.** Hold an item and click Fill: refused. Fill in combat: refused.
21. **Completed.** Both accept: the row becomes Supplied and one line says what was handed over. Check
    `/tui diagnostics`: which trade-complete constant exists, and the message code seen.
22. **Cancelled.** Accept, then the other side cancels: nothing counted (or "Offered?" if no completion message
    has ever been recognised); Confirm and Dismiss work.
23. **Outside the group, unreadable partner, switch off.** No Fill; the strip explains, or doesn't appear when off.
24. **Data bar.** Turn the feature on without reloading: "TwichUI Mage Refreshments" appears in EllesmereUI's Broker
    Plugin list; its text follows marking someone supplied; click and right-click; the three text choices; "Off"
    after turning the feature off.
25. **Appearance.** With the panel open (Preview), change each control: it follows at once. Pick EllesmereUI's Pixels
    Textured border and the thickest size: nothing inside is covered, and the trade strip matches. Change it in
    combat (with the panel shut): it applies when next opened. Without EllesmereUI the choice falls back to a line.

## Trade assistance (milestone 2)

`modules/RefreshmentsTrade.lua`, switch `modules.mageRefreshmentsTrade` (on, but only active while refreshments are
on). Tests: `tests/test_refreshments_trade.lua`.

- **When:** while trading with a group member (by GUID from the trade unit, `"NPC"`), a plain strip under Blizzard's
  trade window shows what their share still asks for and a **Fill trade** button. Nothing moves when the trade opens.
  Someone outside the group, or a partner whose GUID can't be read, gets an explanation and no button.
- **Every move is inside the click.** No timer or event ever moves an item, so it doesn't matter whether Forever
  allows timer-driven moves. One click: whole stacks of the planned rank (full, or exactly what is left, largest
  first) go into empty slots 1 to 6 (`C_Container.PickupContainerItem` then `ClickTradeButton`); what is left is
  split from the smallest bigger stack into an empty ordinary bag slot (`C_Container.SplitContainerItem`, then a
  pickup on the empty slot). The **next click**, once the game has shown the split stack unlocked, puts it in. One
  split per click. With no stack big enough to split, loose stacks go as they are; with no empty bag slot, nothing is
  split and the strip says so (it never sends a whole stack for part of one).
- **Never:** the seventh slot, a slot already in use, any item but the planned rank of conjured food or water, taking
  anything out of the window, accepting, acting with something on the cursor (it asks you to put it down) or in
  combat. Each move is checked: the cursor must hold the expected item after a pickup and be empty after placing; the
  first refusal stops the click and puts anything on the cursor back.
- **Already in the window:** conjured food or water of any rank (put in by hand or an earlier click) counts towards
  the share. A placement the game hasn't shown yet counts too, and the button waits ("Waiting for the game...") until
  `TRADE_PLAYER_ITEM_CHANGED` (or three seconds), so a second click can't add a second stack.
- **Blocked:** if `ADDON_ACTION_BLOCKED` names TwichUI during a trade, filling stops for that trade.

### What counts as handed over

- **Planned:** the plan's remaining share. **Placed:** the click's own record until the game shows it. **Offered:**
  your side of the window at the moment you accept (`TRADE_ACCEPT_UPDATE` with yours 1; cleared when it resets).
  **Delivered:** the offer, credited only when `UI_INFO_MESSAGE` matches `LE_GAME_ERR_TRADE_COMPLETE` or
  `ERR_TRADE_COMPLETE`, during the trade or within three seconds of `TRADE_CLOSED`. Accepting alone never counts.
- Neither constant is in the local Forever UI source, so they are looked up at run time. If no completion message is
  seen and none has ever been recognised this session, the offer is kept as **"Offered?"** in the panel to
  **Confirm** or **Dismiss** (and counts towards the share in later trades until then, so it isn't given twice).
  Once a completion message has been recognised this session, a trade closed without one is taken as not completed.
- Only group members' records change; nothing is saved.
- Diagnostics list which of the two constants the client defines and the message codes seen during trades, to check
  which one Forever uses.

