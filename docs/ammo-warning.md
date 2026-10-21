# Hunter ammunition warning

An opt-in line of text near the middle of the screen when a Hunter's ranged weapon has no usable ammunition. Code:
`!!!TwichUI/ammo/`; settings: `TwichUI_Settings/pages/Ammo.lua` and `AmmoItems.lua`; tests: `tests/test_ammo.lua`,
`tests/test_ammo_settings.lua`.

It only reads what is equipped and carried. It never equips, moves, buys, uses or destroys anything, prints nothing in
chat and sends nothing to a group. It is off until turned on, never runs for another class, and nothing it decides is
saved.

Nothing here has been seen in the game. "Verified" below means read from the Forever UI source (`../wow-ui-source`,
branch `forever`) or exercised by the offline tests against a stand-in for the game. The checks still to make in a real
client are at the end.

## What the client provides

| Fact | Evidence |
|---|---|
| Ammunition is a slot of its own, `INVSLOT_AMMO` = 0; the ranged weapon is `INVSLOT_RANGED` = 18 | `Blizzard_FrameXMLBase/Constants.lua` |
| Whether the weapon takes ammunition is the client's own answer, `UnitUsesAmmo("player")`; the character sheet shows or hides the ammo slot with it, and `C_PaperDollInfo.AmmoNeeded()` is the same question | `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua` (`CharacterAmmoSlot:SetShown(UnitUsesAmmo("player"))`), `UnitDocumentation.lua`, `PaperDollInfoDocumentation.lua` |
| What is selected and its count: `GetInventoryItemID` / `GetInventoryItemCount("player", INVSLOT_AMMO)`. The sheet prints that count on the slot; an empty slot is shown as the slot's empty background | `PaperDollFrame.lua` (`PaperDollItemSlotButton_Update`) |
| The class token: `UnitClassBase("player") == "HUNTER"` | `HostileTargetingActionBar.lua` |
| Item class and subclass without waiting for the cache: `C_Item.GetItemInfoInstant` (class, subclass) | `ItemDocumentation.lua` |
| Projectiles are `Enum.ItemClass.Projectile` (6); weapons `Weapon` (2) with `Bows` 2, `Guns` 3, `Crossbow` 18 (`Thrown` 16 and `Wand` 19 take none) | `ItemConstantsDocumentation.lua` |
| Events: `PLAYER_EQUIPMENT_CHANGED` (slot, hasCurrent), `BAG_UPDATE_DELAYED`, `UNIT_INVENTORY_CHANGED` (unit), `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED/ENABLED` | the same documentation |

**Not in the Forever source, so taken from outside and flagged:** the projectile subclasses (arrows = 2, bullets = 3).
The source names the class but has no enumeration for its subclasses. The values are the item database's, and the RXP
reference addon (`../reference_addons/RXPGuides/InventoryManager.lua`, read for ideas only) uses the same ones. Any other
projectile subclass is treated as "another kind": it is never called wrong and never counted as a supply.

**Taken from a reference addon, not from the source:** that the ammo slot's count covers every carried stack of the
selected item (`EllesmereUIDataBars/Blocks/Supplies.lua`: "the ammo slot already counts the selected item across carried
stacks"). The warning relies on it: when ammunition is selected it does not add up the bags.

## Decisions the client's design forced

* **"No ammo equipped" and "out of ammo" cannot be told apart from the slot.** The client shows an empty slot for both and
  has no separate depleted state. So the split is by what the bags hold: nothing selected and compatible ammunition
  carried is **NO AMMO EQUIPPED** (select it); nothing selected and none that fits is **OUT OF AMMO**. A selected item with
  a count of zero is **OUT OF AMMO** too. This is a statement about supplies, not about history.
* **Compatible** is judged only when the weapon's type is known: a Bow or Crossbow takes arrows, a Gun bullets. For a
  weapon of any other type, any recognized ammunition counts as compatible and **WRONG AMMO EQUIPPED** is never concluded.
* **"Needs ammunition" is the client's word**, not a table of weapons. A bow that `UnitUsesAmmo` says takes none shows
  nothing.
* **No weapon override exists.** Nothing in the source shows a need for one (the client already says whether the weapon
  takes ammunition), so none was added.
* **Unknown is not a problem.** If `UnitUsesAmmo` has no answer, the ammo count has not arrived or the bags cannot be
  read, nothing is concluded. What is on screen stays, the look is repeated up to three times a second apart, and then it
  gives up and shows nothing.

## States

| State | Meaning | Shown |
|---|---|---|
| inactive | no ranged weapon, or the client says it takes no ammunition | nothing |
| unknown | data not there (yet) | nothing new; see above |
| ok | compatible ammunition is selected and some is left | nothing |
| noAmmo | `NO AMMO EQUIPPED` | yes |
| outOfAmmo | `OUT OF AMMO` | yes |
| wrong | `WRONG AMMO EQUIPPED`: arrows selected for a gun or bullets for a bow, both known for certain | yes |

Bank, mail and the auction house are never counted: only the backpack and the equipped bags (quivers and pouches
included) are read, and only when nothing is selected, stopping at the first stack that fits.

## Known and custom ammunition

`ammo/Items.lua`. `AI.Kind(itemID)`: the player's own registration first, then the client's classification (above). No
list of known IDs exists, so nothing iterates one.

**Custom ammunition** (Ammunition warning › Custom ammunition): an item ID, a pasted item link or an item dropped from the
bags, registered as arrows or bullets. Stored as `ui.ammoCustom.items = { { id, kind }, ... }` (profile-scoped, at most
40). Registering says only what an ID is. It does not say the item is equipped, carried, compatible or consumed; the
warning still reads the character each time. The registration wins over the client's classification, so a wrong one can
be corrected (and the page says whose word decides when they differ). Removing it forgets the registration and nothing
else.

An item the client has no data for (a server item) is still registered: its details are requested at most twice while the
tab is open, it shows as loading, and if the game says there is no such item it says so and keeps the entry. The warning
itself never requests item data; classification uses the instant lookup.

No other ammunition type is offered: none is present in the Forever source.

## Events and lifecycle

| Moment | What happens |
|---|---|
| Off, or any class but Hunter | no frame, no timer, no ammunition event. A class that cannot be read yet listens for `PLAYER_ENTERING_WORLD` only |
| A Hunter with it on | `PLAYER_ENTERING_WORLD`, `PLAYER_EQUIPMENT_CHANGED` (ammo and ranged slots only; others are dropped before any work), `BAG_UPDATE_DELAYED`, `UNIT_INVENTORY_CHANGED` (registered for the player only), plus `PLAYER_REGEN_DISABLED/ENABLED` while "Only in combat" is chosen. They only note that a look is due |
| A look | one 0.15 s timer however many events arrive; at most six reads of the character, and the bags only when nothing is selected. No `OnUpdate` exists, anywhere |
| Setting, profile or custom-list change | one refresh; `quiet` (no sound) |
| Switching off, a profile without it | everything unregistered, hidden and forgotten at once; timers from before do nothing |
| Settings closed | the preview ends. An unlocked (moving) warning stays until locked or combat starts |

Event bursts are judged once, after they settle, so an ammunition swap or a flurry of bag updates does not flash a
warning. A swap that drags the ammunition out of the slot and holds it on the cursor for longer than the 0.15 s will
show NO AMMO EQUIPPED, which is true while it is out.

## Visibility

`ui.ammo.show`: **Whenever my ranged weapon needs ammunition** (the default: shown as soon as a problem is found, in or
out of combat, so it can be fixed before a pull) or **Only in combat**. With "Only in combat" a problem found earlier
appears when combat starts and goes when it ends. With no ranged weapon, or a weapon that takes none, nothing shows
either way. Low-ammunition thresholds are out of scope.

## The frame

A plain frame near the centre (default 140 above it, kept on this computer, clamped to the screen), strata HIGH, mouse
disabled: it is click-through. Text only by default; the optional icon is the item's own (what is selected, what could be
selected, or what was last selected). No background or border is drawn until chosen (`ui.ammoLook`, a MenuStyle look: the
same textures, LibSharedMedia and EllesmereUI choices as the other frames; it is built the first time something is shown,
so an EllesmereUI border is never drawn before every addon has loaded). Font, size, outline and color are settings; so are
scale and opacity. Nothing animates, so there is nothing for reduced motion to reduce.

**Preview**: a sample of the frame for any class (Hunter or not), cycling the three messages. It uses none of the real
state, plays no sound and ends when settings close, combat starts or the feature is turned off. **Unlock/Lock**: the
sample with a handle that takes the mouse; drag it, right-click or press Lock to finish; it locks by itself in combat.
**Reset position** puts the default back.

## Sound

Off by default. When on: one sound (any TwichUI or LibSharedMedia sound, on a chosen volume channel) when a problem
**begins** while it is visible. Not on the first look after login, a refresh or switching on; not when one problem becomes
another; not again while it persists; at least 5 seconds between two sounds; never in the preview (a separate "Play the
sound" button plays it once on request). Nothing is printed.

## Storage and sharing

| Key | Holds |
|---|---|
| `modules.ammoWarning` | the switch (false until turned on) |
| `ui.ammo` | `show`, `icon`, `scale`, `opacity`, `font`, `fontSize`, `fontOutline`, `textColor`, `sound`, `soundName`, `soundChannel`. Ranges in `Config.LIMITS` |
| `ui.ammoLook` | background and border (none by default) |
| `ui.ammoPosition` | `{ x, y }` from the screen centre. Never shared |
| `ui.ammoCustom` | `{ items = { { id, kind } } }` |

Values are validated on the way in and out (an invalid stored value reads as its default and is not erased; `false` and
`0` are values). Warning state, counts, pending timers and the preview are runtime only. Sharing: the switch, `ui.ammo`,
`ui.ammoLook` and the custom list (merged by item ID, checked entry by entry, undoable); not the place. See
`docs/twichui-sharing.md`.

## Limits

* The slot's count covering all stacks, the last stack emptying the slot (rather than leaving a count of zero) and the
  events raised when it does are the client's behaviour, unconfirmed here. If the count did not cover all stacks, a
  second stack in the bags would be missed only while the selected stack ran low; if the slot did not empty, a count of
  zero would show OUT OF AMMO, which is also right.
* Projectile subclasses 2 and 3 (above).
* A weapon type the source does not list for ammunition (a custom ranged weapon) gets no wrong-ammunition judgement.
* Reagent bags are scanned along with the others (they cannot hold ammunition); the bank is not.

## In-game checklist

1. Hunter, bow, arrows selected: no warning. Turn it on (Ammunition warning) and use Preview and Unlock to place it.
2. Drag the arrows out of the ammo slot with more in the bags: NO AMMO EQUIPPED, with the arrows' icon. Put them back: gone.
3. Shoot the selected stack down to nothing with none left anywhere: OUT OF AMMO at the moment the last one goes; note
   whether the slot is empty or shows 0.
4. With two stacks in different bags, shoot the first away: does the slot keep showing the total, and does the warning
   stay off until the last arrow?
5. Equip bullets for a bow, then arrows for a gun: WRONG AMMO EQUIPPED each time; swap weapon or ammunition to clear it.
6. Take off the ranged weapon; equip a wand or thrown weapon: nothing shows.
7. Combat only: unselect the ammunition out of combat (nothing), pull (it appears), leave combat (it goes).
8. `/reload` and log in with a problem present: it appears without a sound; with the sound on, create a problem in play:
   one sound, not repeated by bag changes.
9. Register a server item as arrows/bullets and check it counts when selected and carried, and `/reload` keeps the list.
10. Another class: nothing happens (`/tui diagnostics` shows no events registered); Preview still works.
