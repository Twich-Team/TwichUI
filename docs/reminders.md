# Reminders

Artwork, an icon or a few words on screen while conditions the player chooses are true, and nothing the rest of the
time. The first use is a missing-shield reminder; nothing in the design is about a class. Code: `!!!TwichUI/reminders/`;
settings: `TwichUI_Settings/pages/Reminders.lua` and `RemindersEditor.lua`; tests: `tests/test_reminders.lua`,
`tests/test_reminders_settings.lua`; art: `tools/make_reminder_art.py`, `tools/make_settings_icons.py` (sheet 4).

A reminder only reads. It never equips, uses, moves or casts anything, prints nothing in chat and sends nothing to
anyone. None exists until the player makes one, and each starts turned off.

Nothing here has been seen in the game. "Verified" below means read from the Forever UI source (`../wow-ui-source`,
branch `forever`) or exercised by the offline tests against a stand-in for the game. The checks still to make in a real
client are at the end.

## What the client provides

| Fact | Evidence |
|---|---|
| Equipment slots `INVSLOT_HEAD` (1) to `INVSLOT_TABARD` (19); off hand 17, main hand 16, ranged 18 | `Blizzard_FrameXMLBase/Constants.lua` |
| What is equipped: `GetInventoryItemID("player", slot)` (nil when empty) | used the same way by `ammo/` and the character sheet |
| An item's class, subclass and equip location without waiting for the cache: `C_Item.GetItemInfoInstant` (may return nothing) | `ItemDocumentation.lua` |
| Shield = `Enum.ItemClass.Armor` (4) with `Enum.ItemArmorSubclass.Shield` (6); weapon = `Enum.ItemClass.Weapon` (2); fishing pole = `Enum.ItemWeaponSubclass.Fishingpole` (20) | `ItemConstantsDocumentation.lua` |
| Two-handed and held-in-off-hand are the equip locations `INVTYPE_2HWEAPON` and `INVTYPE_HOLDABLE` | the game's own `DressUpModelFrameMixin.lua`, `Blizzard_HeirloomCollection.lua` |
| Item data on request: `C_Item.RequestLoadItemDataByID`; answers `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` (itemID, success) | `ItemDocumentation.lua` |
| `UnitAffectingCombat`, `PLAYER_REGEN_DISABLED/ENABLED`; `UnitIsDeadOrGhost`, `UnitIsGhost`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | `UnitDocumentation.lua`, `DeathInfoDocumentation.lua` |
| `IsMounted()`; `PLAYER_MOUNT_DISPLAY_CHANGED` | `PlayerScriptDocumentation.lua`, `UnitDocumentation.lua`; the shared action bar code registers the event |
| `PLAYER_EQUIPMENT_CHANGED` (slot, hasCurrent) | `PaperDollInfoDocumentation.lua` |

**Not confirmed in the game:** that `PLAYER_MOUNT_DISPLAY_CHANGED` fires on Forever whenever mounting or dismounting
(the class resource bars rely on it too), that an empty slot reads nil from the first look in the world, and that
server-added items answer `GetItemInfoInstant`. Nothing reads localized item names to decide anything; names appear only
as labels in the settings window and never in what is stored.

## Conditions (first release)

| Kind (`type`) | Stored fields | Choices |
|---|---|---|
| `equipment` | `slot` (a stable key: `offHand`, `mainHand`, `ranged`, `head` ... `trinket2`, or `any`), `what`, `negate`, `item` | `empty`; a category the slot can hold (off hand: `shield`, `weapon`, `holdable`; main hand: `weapon`, `twoHand`, `fishingPole`; ranged: `weapon`); `item` (a specific item ID; `any` slot offers only this) |
| `player` | `state`, `negate` | `combat` (in combat), `dead` (dead **or a ghost**), `ghost` (only the released spirit), `mounted` (offered only while the client has `IsMounted`) |

`negate` is "is not". "Player is not dead or a ghost" reads as "Player is alive". Categories are judged from the item's
class, subclass and equip location only; an item with no details is **unknown**, never a match. For the shield example:
shield in the off hand, "Off hand is not Shield" is no match; empty, a match; an off-hand weapon, a match; no details,
unknown.

### Three answers and composition

Each condition is Match, No match or Unknown. **All**: any no match is no match, otherwise any unknown is unknown,
otherwise match. **Any**: any match is match, otherwise any unknown is unknown, otherwise no match. No conditions is no
match, and a reminder can't be turned on without one. Unknown never shows.

### Status, most important first

`invalid` (its problems are listed; it never shows) · `disabled` · `notApplicable` (another character or class) ·
`waiting` (the game hasn't given enough, or who is playing isn't known yet) · `showing` / `hidden`. The controller adds
`off` (Reminders switched off), `world` (not in the world yet), `pending` (waiting out its delay) and `holding` (kept up
for its minimum).

## Saved data

`TwichUIDB.ui.reminders` (the profile in use) and the switch `modules.reminders` (on by default: with no reminder turned
on nothing is listened for).

```
{ version = 1, nextId = n, list = {
  { id = "r1", name = "Shield reminder", enabled = false,
    scope = { who = "all" | "characters", characters = { "Name - Realm", ... }, class = nil | "WARRIOR" ... },
    match = "all" | "any",
    conditions = { { type = "equipment", slot = "offHand", what = "shield", negate = true } },
    display = { mode = "artworkText", art = "shield", text = "Equip your shield", ... },
    place = { preset = "belowCenter" } } } }
```

Ids are never reused within a profile (`nextId`). `version` is this table's own shape: a table from a newer TwichUI is
read but never written or shown. Reading never writes: an unusable stored value reads as its default and is left as it
is; an unknown condition kind, an unknown artwork id or an unfinished condition (no item yet) is kept and listed as a
problem, and the reminder can't be turned on (or, already on, doesn't show) until it is fixed. Display and place values
are checked on the way in and out (`Config.lua`'s `DISPLAY_DEFAULTS`, `LIMITS`, `CHOICES`). Who it is for (`scope`) is
separate from how it looks (`display`). Nothing about a decision, an observation, a timer or a preview is saved.
Configuration sharing keeps both keys on this computer (`TwichConfig.LOCAL`, "other": a reminder can name characters).

## Making and editing (settings > Everyday > Reminders)

The card holds the switch. Under it: **Your reminders** (thumbnail, name, the rule as a sentence or what is wrong, what it
is doing now, and its own switch) and **Start a new one**: **Missing shield** (name "Shield reminder", "Off hand is not
Shield", the shield artwork with "Equip your shield", no sound, no pulse, below the middle, this character only),
**Missing equipment or item** (any slot is not an item you choose; shows that item's icon; unfinished until the item is
chosen) and **Custom reminder** (your words; needs a condition). Each is an ordinary reminder once made: nothing about
the template is remembered.

The chosen reminder: its name, its switch (refused, with the reason, while it has problems), **Duplicate** (a fresh id,
turned off, right after it; the original is untouched) and **Delete** (asks, names it; its frame goes at once). Then:

- **Show**: Display (artwork with text, artwork, icon with text, icon, text only); Artwork (the gallery); Icon from (a
  TwichUI icon, or an item's icon by ID, link or a drop from the bags: the item needn't be equipped); Words.
- **When**: For (every character, this character only, characters I choose: added from each character); Class (any, or
  one: independent of the equipment conditions); "Show when [All conditions match]" with two or more; one row per
  condition, `[Off hand] [is not] [Shield]`, where the subject decides the choices offered; Add an equipment condition /
  a condition about you; the rule and the scope as sentences; the shield template's note, "This reminder appears whenever
  you are not using a shield. Add a condition to limit when it appears.", while its condition is the template's.
- **Placement**: Position (below the middle, above the middle, middle, top, bottom, where I put it); Move on screen /
  Done; Size; Opacity; Text size; Words go (below, above, right, left). **More placement and appearance options**
  (closed at first, for the session): keep proportions or width and height; font, outline, text color; background
  (none, soft shade, framed panel); anchor point and x / y offsets (typed values follow drags and the reverse); layer
  (low, medium, high); fade in and out; pulse; wait before showing; keep up at least.
- **Preview**: the reminder drawn in the page by its own layout code, scaled to fit, marked PREVIEW; **Show on screen**.
- **Test**: **Right now** (each condition: summary, Match / No match / Unavailable / Invalid, what was observed, and
  why when unavailable; then the result and why). **Try a situation** (SIMULATED): a choice per condition, generated by
  its provider (for the shield: Shield equipped, Empty off hand, Off-hand weapon equipped, Equipment information
  unavailable; for combat: In combat, Out of combat, Not read yet), and the simulated decision. **Check it in the game**.

Words carry every state; colour only agrees.

## Display

Defaults: artwork with text, 64 units on the longer side, the picture's own proportions, opacity 100, text 18 with an
outline in ivory below the picture, no panel, medium layer, no fade, no pulse, no delay or minimum, `CENTER` 0, -200
(below the character, above the action bars). Click-through; only the move handle takes the mouse, only while moving.
Text is plain (no `|`, no control characters, up to 120 characters), wraps at 420 units, and is never read as markup or
an expression. A missing item icon shows a question mark while the game is asked for it (at most twice).

Artwork gallery: `RM.ART` in `reminders/Config.lua`, files in `media/reminders/`: `shield.tga` (256 px canvas, 180 x 254
used) and `shield-small.tga` (64 px canvas, 44 x 62 used) for 64 units and under. Uncompressed 32-bit TGA, bottom-left
origin; only the used part is drawn. There is no in-game image import.

## Preview, moving, diagnostics

An on-screen preview shows one reminder where it sits, marked "Preview: <name>", whatever its rules say, with no
duplicate (it is the reminder's own frame). It changes no rule, observation or decision, and ends when the settings
close (unless moving), in combat, when the reminder is deleted or Reminders is switched off, or on a profile change.
Moving adds a drag handle; the place is saved as "Where I put it" with offsets from the chosen anchor point; right-click
or Done ends it. A reminder that isn't running (a draft, for another character) is inspected by reading what its
conditions need into a table of its own (`State.Peek`): nothing is added to what the live reminders read or listen for.
The Test section's simulations go through the same `Evaluate.Run` on a table built from the scenarios
(`Evaluate.Simulate`) and never see the live one. `/tui diagnostics` has a Reminders section with counts only.

## Events and performance

| Moment | What happens |
|---|---|
| Switched off | no event, every frame hidden, every timer stale |
| On, no reminder turned on for this character | `PLAYER_ENTERING_WORLD` only |
| On, reminders running | the observation keys their conditions read (`slot:17`, `combat`, `life`, `mounted`), and only those sources' events: `PLAYER_EQUIPMENT_CHANGED` for equipment, the regen events for combat, the three life events, the mount event |
| An item without details in a wanted slot | asked for at most twice; `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` only while that lasts |
| An event | marks its key; one 0.1 s timer reads each marked key once; only keys whose facts changed re-decide, and only the reminders that read them (an index by key) |
| A setting changes | look or place: that frame is drawn again; rules, switch, list or profile: the index is built again |
| Delay / minimum | one `C_Timer.After` per waiting reminder, with a token: cancelled by anything that changes its course |

No `OnUpdate` anywhere; fades and pulses are animation groups the game runs, short and bounded (a pulse is three
breaths). One frame per reminder id, made the first time it shows and reused when a reminder is deleted and another made;
redraws only when its settings changed.

**Timing.** A delay starts when the conditions start matching; if they stop first, nothing shows. A minimum starts when
it shows; it stays up that long even if the conditions stop matching (and goes when that ends, unless they match again).
Turning it off, deleting it, a different character or class, Reminders switched off and a profile change hide it at once.

## Extending

**A new kind of condition.** In `reminders/Conditions.lua` (or a file of its own listed after it), `C.Register{ type,
label, New, Check, Needs, Evaluate, Summary, Observed, Scenarios }` (the header says what each does; `Evaluate` reads
only the observations table). For each observation key `Needs` names, a source in `State.lua`:
`ST.Source(kind, { events = { EVENT = handler }, Read = function(arg, obs) ... end })`. Then the editor's subject and
value choices in `RemindersEditor.lua` (`Subjects`, `ValueChoices`), a test in `tests/test_reminders.lua`, and its
facts and checks here. Buff, cooldown, health, inventory-count and target conditions are not in this release.

**A new picture.** Put the PNG (real transparency) in `assets/`, add a line to `ART` in `tools/make_reminder_art.py`, run
`python3 tools/make_reminder_art.py` (it prints the numbers), and add that line, with a label, to `RM.ART` and
`RM.ART_ORDER` in `reminders/Config.lua`. `media/` is packaged; `assets/` and `tools/` are not.

## Limits

- Mounted, the first look after login and server items: see "Not confirmed" above.
- `any` slot reads all nineteen slots for an item condition; no bag, bank or inventory count is read.
- A character listed by name and realm: a renamed character, or one moved to another realm, has to be added again.
- Not in this release: nested groups, Lua, dynamic clones, sounds, sharing, buff/cooldown/health/inventory/target
  conditions, automation of any kind.

## In-game checklist

1. Settings > Reminders: the card says On; the list is empty. **Missing shield**: a draft, "Off" in the list; Test >
   Right now says what the off hand holds. Turn it on.
2. Take the shield off: the shield and "Equip your shield" appear below your character within a moment; put it on: gone.
   Equip an off-hand weapon, then nothing: it shows each time. `/reload` with no shield: it shows without a flash of
   "waiting"; with one: nothing.
3. Log in on another character: nothing (not for that character). **For** > Characters I choose > Add this character.
4. Add a condition about you, In combat, All: it shows only in combat without a shield; Any: either.
5. Dead and a ghost, mounted and dismounted (note whether the mount event fires on Forever).
6. **Missing equipment or item**: paste an item link (shift-click into the box), drop an item, type an ID; the icon shows
   that item; a server item that the game has no details for shows a question mark and says so.
7. Preview, Show on screen, Move on screen, drag, Done; the offsets follow; reload: the place is kept. Each preset.
   Close the settings during a preview: it ends; during a move: it stays until Done. Enter combat: both end.
8. Every display mode, both proportions, a long text on the right, the framed panel, each layer, at UI scale 0.64 and
   1.15. Fade and pulse on: short and calm; Notifications > Reduced motion: neither.
9. Delay 5 with a quick swap: nothing shows; a minimum of 10: it stays, then goes; turn it off during the minimum: gone.
10. Duplicate, rename, delete (asks; gone at once). Switch profile: the other profile's reminders, nothing stale.
11. Reminders off: nothing shows, `/tui diagnostics` shows no events registered.
12. Look for errors with Display Lua Errors on throughout; check the icons in the editor at small UI scales.
