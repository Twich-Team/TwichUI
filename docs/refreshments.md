# Mage refreshments

For anyone changing the refreshments feature. Code: `modules/Refreshments.lua` (shares, roster, session, plan),
`modules/RefreshmentsPanel.lua` (the window and its secure buttons), `modules/RefreshmentsShares.lua` (the shares page
in Options), `diag/Refreshments.lua`, `Bindings.xml`. Tests: `tests/test_refreshments.lua`. **Nothing here has been
verified in the game yet**; see "Manual acceptance test".

This is milestone 1: plan, conjure by click or key, manual checklist. Trade assistance (a "Fill trade" button and
delivery tracking) is milestone 2 and is not built; see the end of this file.

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
  settings, moving bag items, trading, whispering or chat, sounds.

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
`refreshments-reset-left-group`.

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

## Milestone 2 (not built): trade assistance

Planned, pending the in-game checks above and these: whether `C_Container.PickupContainerItem`,
`C_Container.SplitContainerItem` and `ClickTradeButton` work from one click without a click per step (the docs don't
say; Conjurer and Water Dispenser do it from timers), and whether `UI_INFO_MESSAGE` carries a "trade complete"
message on Forever (no such constant is in the local UI source). A trade strip under the trade window with **Fill
trade** (on a click only, never on opening, never accepting), only empty slots 1 to 6, never with something on the
cursor or in combat, bounded and cancelled when the trade closes. Delivery counted only on a recognised completion;
otherwise "offered, unconfirmed" with a click to confirm.
