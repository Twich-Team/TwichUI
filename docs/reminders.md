# Reminders

Artwork, an icon or a few words on screen while conditions the player chooses are true, and nothing the rest of the
time. The first uses are a missing-shield reminder and an ammunition reminder; nothing in the design is about a class.
Code: `!!!TwichUI/reminders/`; settings: `TwichUI_Settings/pages/Reminders.lua`, `RemindersEditor.lua` and `AmmoItems.lua`
(the Known ammunition tab); tests: `tests/test_reminders.lua`, `tests/test_reminders_ammunition.lua`,
`tests/test_reminders_settings.lua`, `tests/test_ammo_items_settings.lua`; art: `tools/make_reminder_art.py`,
`tools/make_settings_icons.py` (sheet 4).

A reminder only reads. It never equips, uses, moves or casts anything, prints nothing in chat and sends nothing to
anyone. None exists until the player makes one, and each starts turned off.

Nothing here has been seen in the game. "Verified" below means read from the Forever UI source (`../wow-ui-source`,
branch `forever`) or exercised by the offline tests against a stand-in for the game. The checks still to make in a real
client are at the end.

## What the client provides

| Fact | Evidence |
|---|---|
| Equipment slots `INVSLOT_HEAD` (1) to `INVSLOT_TABARD` (19); off hand 17, main hand 16, ranged 18 | `Blizzard_FrameXMLBase/Constants.lua` |
| What is equipped: `GetInventoryItemID("player", slot)` (nil when empty) | used the same way by the character sheet |
| Ammunition is a slot of its own, `INVSLOT_AMMO` = 0; the ranged weapon is `INVSLOT_RANGED` = 18 | `Blizzard_FrameXMLBase/Constants.lua` |
| Whether the weapon takes ammunition is the client's own answer, `UnitUsesAmmo("player")`; the character sheet shows or hides the ammo slot with it (`C_PaperDollInfo.AmmoNeeded()` is the same question) | `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua` (`CharacterAmmoSlot:SetShown(UnitUsesAmmo("player"))`), `UnitDocumentation.lua`, `PaperDollInfoDocumentation.lua` |
| What is selected as ammunition and its count: `GetInventoryItemID` / `GetInventoryItemCount("player", INVSLOT_AMMO)`. The sheet prints that count on the slot; an empty slot is shown as the slot's empty background | `PaperDollFrame.lua` (`PaperDollItemSlotButton_Update`) |
| Projectiles are `Enum.ItemClass.Projectile` (6); weapons `Weapon` (2) with `Bows` 2, `Guns` 3, `Crossbow` 18 (`Thrown` 16 and `Wand` 19 take none) | `ItemConstantsDocumentation.lua` |
| The carried bags: `C_Container.GetContainerNumSlots` / `GetContainerItemID`, bags 0 to `NUM_TOTAL_EQUIPPED_BAG_SLOTS` (the backpack and the equipped bags, quivers, pouches and the reagent bag included; never the bank, mail or the auction house) | `ContainerDocumentation.lua`, `Blizzard_FrameXMLBase/Constants.lua` |
| An item's class, subclass and equip location without waiting for the cache: `C_Item.GetItemInfoInstant` (may return nothing) | `ItemDocumentation.lua` |
| Shield = `Enum.ItemClass.Armor` (4) with `Enum.ItemArmorSubclass.Shield` (6); weapon = `Enum.ItemClass.Weapon` (2); fishing pole = `Enum.ItemWeaponSubclass.Fishingpole` (20) | `ItemConstantsDocumentation.lua` |
| Two-handed and held-in-off-hand are the equip locations `INVTYPE_2HWEAPON` and `INVTYPE_HOLDABLE` | the game's own `DressUpModelFrameMixin.lua`, `Blizzard_HeirloomCollection.lua` |
| Item data on request: `C_Item.RequestLoadItemDataByID`; answers `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` (itemID, success) | `ItemDocumentation.lua` |
| `UnitAffectingCombat`, `PLAYER_REGEN_DISABLED/ENABLED`; `UnitIsDeadOrGhost`, `UnitIsGhost`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | `UnitDocumentation.lua`, `DeathInfoDocumentation.lua` |
| `IsMounted()`; `PLAYER_MOUNT_DISPLAY_CHANGED` | `PlayerScriptDocumentation.lua`, `UnitDocumentation.lua`; the shared action bar code registers the event |
| Talent specialization: Forever has none, so it is the tree with the most spent points. Points per tree come from `gear/Data.lua` `TalentSpent` (`C_SpecializationInfo.IsInitialized` / `GetActiveSpecGroup` / `GetCombatConfigIDForSpecGroup`, `C_Traits.GetGroupDisplayInfoByTreeID` / `GetGroupCurrencyInfo`, trees identified by `skillLineID`; the class's trees and their ids are `gear/Weights.lua` `W.CLASSES`). Re-read on `PLAYER_TALENT_UPDATE`, `CHARACTER_POINTS_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`, `TRAIT_CONFIG_UPDATED`. Stored as `{ class, tree = skillLine }` or `{ state = "tied" \| "none" }`; unspent points never count; unreadable data is unknown | `SpecializationInfoDocumentation.lua`, `PaperDollInfoDocumentation.lua`, `Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua`; project use in `gear/Data.lua`, `gear/Hints.lua` |
| `PLAYER_EQUIPMENT_CHANGED` (slot, hasCurrent) | `PaperDollInfoDocumentation.lua` |
| `BAG_UPDATE_DELAYED`; `UNIT_INVENTORY_CHANGED` (unit) | `ContainerDocumentation.lua`; `UnitDocumentation.lua` |

**Not confirmed in the game:** that `PLAYER_MOUNT_DISPLAY_CHANGED` fires on Forever whenever mounting or dismounting
(the class resource bars rely on it too), that an empty slot reads nil from the first look in the world, and that
server-added items answer `GetItemInfoInstant`. For ammunition also: the projectile subclasses (arrows = 2, bullets = 3) are
not in the Forever source, which names the class but has no enumeration for its subclasses; they are the item database's
values, and the RXP reference addon (`../reference_addons/RXPGuides/InventoryManager.lua`, read for ideas only) uses the same
ones. Any other projectile subclass is "another kind": never called wrong, never counted as a supply. And that the ammo
slot's count covers every carried stack of the selected item (taken from `EllesmereUIDataBars/Blocks/Supplies.lua`, not from
the source): the condition relies on it, and does not add up the bags when ammunition is selected. Nothing reads localized item names to decide anything; names appear only
as labels in the settings window and never in what is stored.

## Conditions (first release)

| Kind (`type`) | Stored fields | Choices |
|---|---|---|
| `equipment` | `slot` (a stable key: `offHand`, `mainHand`, `ranged`, `head` ... `trinket2`, or `any`), `what`, `negate`, `item` | `empty`; a category the slot can hold (off hand: `shield`, `weapon`, `holdable`; main hand: `weapon`, `twoHand`, `fishingPole`; ranged: `weapon`); `item` (a specific item ID; `any` slot offers only this) |
| `player` | `state`, `negate` | `combat` (in combat), `dead` (dead **or a ghost**), `ghost` (only the released spirit), `mounted` (offered only while the client has `IsMounted`) |
| `class` | `class` (a class token: `WARRIOR`, `PALADIN`, ... never a translated name), `negate` | the classes this client lists (`CLASS_SORT_ORDER`, nine in `Blizzard_FrameXMLBase/Camelot/Constants.lua`; TwichUI's own list of the same nine when the client gives none). New ones start with no class chosen: unfinished until one is |
| `ammunition` | `what` (no `negate`: it reads as a sentence) | `problem` (any of the next three), `noAmmo` (nothing selected, some carried), `outOfAmmo` (nothing selected and none carried, or the selected stack is empty), `wrong` (arrows for a gun, bullets for a bow). Offered only while the client has `UnitUsesAmmo` |

`negate` is "is not". "Player is not dead or a ghost" reads as "Player is alive". Categories are judged from the item's
class, subclass and equip location only; an item with no details is **unknown**, never a match. For the shield example:
shield in the off hand, "Off hand is not Shield" is no match; empty, a match; an off-hand weapon, a match; no details,
unknown.

### Three answers, groups and composition

Each condition is Match, No match or Unknown. A list of them is combined by **All** (AND): any no match is no match,
otherwise any unknown is unknown, otherwise match; or **Any** (OR): any match is match, otherwise any unknown is unknown,
otherwise no match. Unknown never shows.

The rule is a tree. The reminder's own list (`match` + `conditions`) is the top level; a **group** is a condition that
holds such a list and its own All / Any, and counts as one Match, No match or Unknown in the list around it. So
"(Warrior OR Hunter OR Rogue) AND in combat AND no shield" is an All list of: a group matching Any (three class
conditions), "Player is in combat" and "Off hand is not Shield". Every condition is read, none is skipped because another
settled the answer, so Test can show them all.

* **Limits.** Three levels of list, the top level counting as the first (a group, and a group inside it). At most 6 groups and
  16 conditions in a reminder, the conditions counted across all its groups (a group is not a condition). Reading stops at the
  limit and says so; the editor stops offering "Add" and gives the reason.
* **Not accepted, and never ignored.** An empty group, a group whose All / Any is missing or unknown, a group nested deeper
  than allowed, a group that contains itself, and an unfinished or unknown condition anywhere in the tree are problems. The
  reminder is *invalid*: it can't be turned on, and one already on stops showing, rather than the rest being evaluated
  without the part that is wrong. A group with one condition is that condition. The top level with no conditions is no match
  and, like before, can't be turned on.
* **Words.** The rule's sentence is made from the same tree (`Evaluate.RuleSentence`): a group inside another is in
  parentheses, and several conditions of a kind that can say them together do (`Player class is Warrior, Hunter or Rogue`;
  in a group matching All, `Player class is none of ...`). "is not" is kept: it is never merged with "is".

### Status, most important first

`invalid` (its problems are listed, a group's or condition's place given as "Condition 1.2"; it never shows) · `disabled` · `notApplicable` (another character or class) ·
`waiting` (the game hasn't given enough, or who is playing isn't known yet) · `showing` / `hidden`. The controller adds
`off` (Reminders switched off), `world` (not in the world yet), `pending` (waiting out its delay) and `holding` (kept up
for its minimum).

## Ammunition

The `ammunition` condition replaces the Hunter ammunition warning of earlier versions (its settings are removed on load; see
"What the warning did that reminders do not" below). It reads what the character has and what the client says about it,
and never equips, moves, buys, uses or destroys anything. Judgement: `reminders/Ammunition.lua` (pure); the reading:
`reminders/State.lua` (the `ammo` source); what counts as ammunition: `reminders/AmmoItems.lua`.

**The facts** (`obs.ammo`): whether the weapon takes ammunition (`UnitUsesAmmo`), whether there is a ranged weapon, which
ammunition its type takes (a Bow or Crossbow arrows, a Gun bullets, from `C_Item.GetItemInfoInstant`), what is selected in
the ammo slot with its kind and count, and, only when nothing is selected, whether the carried bags hold ammunition the
weapon can use (stopping at the first stack that fits).

| State | Meaning | Matches |
|---|---|---|
| inactive | no ranged weapon, or the client says it takes no ammunition | nothing, ever |
| unknown | the data isn't there (yet): the weapon question unanswered, a count that hasn't arrived, bags unreadable | nothing: the reminder waits |
| ok | compatible ammunition is selected and some is left | nothing |
| noAmmo | nothing selected, but compatible ammunition is carried | `problem`, `noAmmo` |
| outOfAmmo | nothing selected and none that fits is carried, or the selected stack's count is zero | `problem`, `outOfAmmo` |
| wrong | arrows selected for a gun or bullets for a bow, both known for certain | `problem`, `wrong` |

**Decisions the client's design forced.**

* "Not equipped" and "used up" can't be told apart from the slot: the client shows an empty slot for both and has no
  separate depleted state. So the split is by what the bags hold, and it is a statement about supplies, not about history.
* "Compatible" is judged only when the weapon's type is known. For a weapon of any other type, any recognized ammunition
  counts as compatible and `wrong` is never concluded.
* "Needs ammunition" is the client's word, not a table of weapons. A bow that `UnitUsesAmmo` says takes none shows nothing.
* Unknown is not a problem. The look is repeated up to three times, a second apart, when the weapon question or a count
  isn't answered; then it waits for the next event. A reminder that was showing hides when its data goes missing.
* "Only in combat" is a second condition ("Player is in combat", all), not an option of this one.
* Which problem is a choice of the condition: one reminder for any problem, or one per problem with its own words.

**Known ammunition** (Reminders > Known ammunition). An item ID, a pasted link or an item dropped from the bags, registered as
arrows or bullets, for a server item the client doesn't classify (or classifies differently). Stored as
`ui.ammoCustom.items = { { id, kind }, ... }` (profile-scoped, at most 40; the key is the old warning's, so a list made
there is kept). `AI.Kind(itemID)`: your registration first, then the client's classification (class Projectile, subclass
2 arrows / 3 bullets). Registering says only what an ID is; it doesn't say the item is equipped, carried or compatible.
Removing it forgets the registration and nothing else. An item the client has no data for is still registered: its details
are requested at most twice while the tab is open. A change is told to the running reminders at once, and the list follows
a profile change or an import. It is shared like other lists (merged by item ID; see `docs/twichui-sharing.md`); the
reminders that use it are not.

**What the warning did that reminders do not.** The sound when a problem began, the "RPG Notification" presentation, a
different line for each problem within one frame (make one reminder per problem instead), the item's own icon in the frame
(a reminder shows artwork, a TwichUI icon, or an item you choose), and its own position (each reminder has one). The old
settings (`modules.ammoWarning`, `ui.ammo`, `ui.ammoLook`, `ui.ammoPosition`) are deleted on load, quietly; nothing is
migrated into a reminder, so anyone who had the warning on makes one with the **Ammunition** template.

## Saved data

`TwichUIDB.ui.reminders` (the profile in use) and the switch `modules.reminders` (on by default: with no reminder turned
on nothing is listened for).

```
{ version = 1, nextId = n, list = {
  { id = "r1", name = "Shield reminder", enabled = false,
    scope = { who = "all" | "characters", characters = { "Name - Realm", ... }, class = nil | "WARRIOR" ... },
    match = "all" | "any",
    conditions = { { type = "equipment", slot = "offHand", what = "shield", negate = true } },
    -- or, with a group (a condition of type "group" holding the same two fields):
    -- conditions = { { type = "group", match = "any", conditions = { { type = "class", class = "WARRIOR", negate = false }, ... } },
    --                { type = "player", state = "combat", negate = false } },
    display = { mode = "artworkText", art = "shield", text = "Equip your shield", ... },
    place = { preset = "belowCenter" } } } }
```

**Groups need no migration.** A list with no group is read exactly as it always was, and the stored `version` stays 1: the
top level was already "a list and how it matches", and a group is one more kind of entry in it. Nothing is rewritten when
a reminder is read, so there is nothing to repeat or to undo. The compatibility rule: a build from before groups reads a group as a
condition of a kind it doesn't know. It keeps it, lists it as a problem and doesn't run the reminder (it never rewrites it);
turning such a reminder on again needs the group removed or a build that knows groups. Anything that renames fields
of conditions or groups, or changes what an existing value means, is a new `version`.

Ids are never reused within a profile (`nextId`). `version` is this table's own shape: a table from a newer TwichUI is
read but never written or shown. Reading never writes: an unusable stored value reads as its default and is left as it
is; an unknown condition kind, an unknown artwork id or an unfinished condition (no item yet) is kept and listed as a
problem, and the reminder can't be turned on (or, already on, doesn't show) until it is fixed. Display and place values
are checked on the way in and out (`Config.lua`'s `DISPLAY_DEFAULTS`, `LIMITS`, `CHOICES`). Who it is for (`scope`) is
separate from how it looks (`display`). Nothing about a decision, an observation, a timer or a preview is saved.
Configuration sharing keeps both keys on this computer (`TwichConfig.LOCAL`, "other": a reminder can name characters).
The one exception is the ammunition you registered, `ui.ammoCustom` (above), which is a shared list of its own.

## Making and editing (settings > Everyday > Reminders)

The card holds the switch. Under it: **Your reminders** (thumbnail, name, the rule as a sentence or what is wrong, what it
is doing now, and its own switch) and **Start a new one**: **Missing shield** (name "Shield reminder", "Off hand is not
Shield", the shield artwork with "Equip your shield", no sound, no pulse, below the middle, this character only),
**Ammunition** (name "Ammunition reminder", "Ranged ammunition has a problem", the arrows artwork with "Check your
ammunition", the same place and scope; it does nothing for a weapon that takes no ammunition),
**Missing equipment or item** (any slot is not an item you choose; shows that item's icon; unfinished until the item is
chosen) and **Custom reminder** (your words; needs a condition). Each is an ordinary reminder once made: nothing about
the template is remembered.

The chosen reminder: its name, its switch (refused, with the reason, while it has problems), **Duplicate** (a fresh id,
turned off, right after it; the original is untouched) and **Delete** (asks, names it; its frame goes at once). Then:

- **Show**: Display (artwork with text, artwork, icon with text, icon, text only); Artwork (the gallery); Icon from (a
  TwichUI icon, or an item's icon by ID, link or a drop from the bags: the item needn't be equipped); Words.
- **When**: the condition designer, in three blocks (`TwichUI_Settings/pages/RemindersDesigner.lua`; the words are
  `RemindersPlain.lua`; see "The When designer" below).
- **Placement**: Position (below the middle, above the middle, middle, top, bottom, where I put it); Move on screen /
  Done; Size; Opacity; Text size; Words go (below, above, right, left). **More placement and appearance options**
  (closed at first, for the session): keep proportions or width and height; font, outline, text color; background
  (none, soft shade, framed panel); anchor point and x / y offsets (typed values follow drags and the reverse); layer
  (low, medium, high); fade in and out; pulse; wait before showing; keep up at least.
- **Preview appearance**: the reminder drawn in the page by its own layout code, scaled to fit, marked PREVIEW; **Show on screen**.
- **Test**: **Right now** (each group and condition, a group before what is in it and what is in it a step in: summary,
  Match / No match / Unavailable / Invalid, what was observed, and why when unavailable; then the result and why; every one
  is read, so none says "not evaluated"). **Try a situation** (SIMULATED): a choice per thing asked about, generated by
  its provider; conditions that ask about the same thing share one choice ("Player class (3 conditions)"), so made-up facts
  can't contradict each other (for the shield: Shield equipped, Empty off hand, Off-hand weapon equipped, Equipment information
  unavailable; for combat: In combat, Out of combat, Not read yet), and the simulated decision. **Check it in the game**.

Words carry every state; colour only agrees.


## The When designer

A structured designer for the rule, not a node graph. It draws and edits the same tree the evaluator reads; it keeps no
rule of its own and adds nothing to what is saved (`version` stays 1, no new keys).

- **Who is this for?** One line (Every character, This character only, 2 chosen characters, ", only for Hunters") and
  **Edit**: chips for every character / this character only / characters I choose, Add or Remove this character, and the
  class. Who it is for is applied as you choose (like every setting in this window) and is kept apart from the rule: a
  "Your class is Warrior" condition is a condition and is never moved up into who it is for, and one class in who it is for
  never becomes a condition. Several classes are therefore several conditions in a group where at least one must be true,
  because the stored scope holds one class.
- **Show this reminder when...** The tree. A group is a bounded box (a rail on its left, teal for "any", bronze for
  "all") headed **All of these must be true** or **At least one of these must be true**, with a compact All / Any choice
  (the tooltip says AND / OR), a fold button (the folded line says everything in it) and **More** (Duplicate group, Move up,
  Move down, Move into another group, Remove). A condition is a **card**: a sentence ("You are in combat", "Your off hand
  is not a shield", "Ranged ammunition needs attention"), an icon, **Edit** and **More** (Edit, Duplicate, Move up, Move
  down, Move into..., Remove). Quiet "and" / "or" words separate siblings; the group's heading already says which. Each
  group has its own **Add a condition**.
  - **Edit** opens one editor under the card. It works on a copy: Done writes it (and writes nothing if nothing changed),
    Cancel leaves the saved condition as it was; one that isn't finished or can't be used is not written and says why.
  - **Add a condition** opens one picker for that group: a search box, categories (Combat, Character, Equipment, Other)
    and a choice per kind, from the registry (the player's combat, dead, ghost and mounted states one each), each with a
    line saying what it checks, an icon and, where this client can't report it, a note. Choosing one opens the same editor
    with only the values it needs; nothing is added until **Add condition**. The picker's title says what it means for the
    group: "Require another condition" in a group where all must be true, "Allow another condition" where one is enough.
    Adding never changes a group's all or any.
  - **Create a condition group** (at the foot of the picker) says where the group will go and what it starts as, and asks
    whether its conditions combine as "Allow either condition" or "Require several together"; the depth and group limits are
    said in words when they stop it.
  - **Moving.** Move up / down reorders inside a list and never changes what the rule says. **Move into** another group
    changes what a condition is combined with, so each destination is named as the group it is ("Any of: Your class is
    Warrior or Hunter", "the whole rule: All of these must be true") and the page says what changed afterwards. A group
    can't go into itself or what is in it, nor deeper than the limit. Nothing is lost by a move: the same stored table
    moves, and a refusal leaves the rule exactly as it was.
  - **Removing** a group that holds conditions asks first; every removal says what was removed and offers **Undo**, which
    puts back the same stored table in the same place (until the group it was in is gone or the page is left).
  - **Unsupported conditions** (a kind this version doesn't know, from an import or a newer version) are a card that says
    "Unsupported condition", with the kind in its detail line; they are kept exactly as saved, can be moved, copied and
    removed, and are never edited or rewritten. The reminder can't be turned on while one is there, as before.
  - **Over the limits** (more conditions or groups than are read) the rest are kept as saved and a line says they aren't shown.
- **Why would it show?** The rule as short lines, never leaving a condition out ("Shows when all of these are true:" and a
  line each; a run of classes said once; a group with one thing says that thing), and **Would this show now?**, closed
  until asked for (nothing is read for it while it is closed). Open, it reads the rule against the game's current facts
  through the same `Evaluate.Run` the live reminder uses (`Controller.Inspect`, which never changes the live decision):
  a headline (**Would show now**, **Conditions match now** when it isn't on screen, **Would stay hidden**, **Cannot
  determine**), whether it is for this character, what it is doing (showing, turned off, waiting out a delay...), and on
  each card and group Met / Not met / Cannot check yet / Needs attention with a mark (a check, a dash, ?, !), what was
  seen, and for a group which condition decided it. Unknown is shown as unknown: a group where one condition decides the
  answer says that another that can't be checked yet doesn't change it. A limit of the client is a short line ("Cannot
  check ammunition on this client."), with the longer explanation on the mark's tooltip; the runtime treats such a reminder
  as it always did (it can't be turned on). Nothing is shown on screen and no preview is started by looking.

Decisions:

- **Stable ids.** The saved tree has none and gets none. A node is held by its stored table (`RM.NodeByRaw`), which stays
  the same through moves, folds and edits of other nodes; paths are only used for the call that follows. A fold is
  remembered for the session by that table.
- **Drag and drop is deferred.** There is no list-drag infrastructure to reuse, and a hand-made framework would be fragile
  with pooled frames and a scrolling window. Move up / down and Move into do everything it would, with the meaning of each
  move named. It can be added later on the same `RM.MoveNode`.
- **No second engine.** `Plain.Explain` only phrases the `Evaluate.Run` nodes; the three answers and the group rules are the
  evaluator's.
- **Frames.** One card per condition a reminder can have (16), one box per group (6) and the top level, one editor, one
  picker (its rows grow once, to the number of kinds), one targeting panel; reopening makes nothing new, and a hidden page
  puts away what was open. Diagnostics: scope `reminders.designer.layout`, gauges for the pools and whether one is open.
- **The emblem** (`reminderDesigner`, a bronze ring with a check mark) heads the section where its files are; otherwise
  the three-nodes icon does.

## Display

Defaults: artwork with text, 64 units on the longer side, the picture's own proportions, opacity 100, text 18 with an
outline in ivory below the picture, no panel, medium layer, no fade, no pulse, no delay or minimum, `CENTER` 0, -200
(below the character, above the action bars). Click-through; only the move handle takes the mouse, only while moving.
Text is plain (no `|`, no control characters, up to 120 characters), wraps at 420 units, and is never read as markup or
an expression. A missing item icon shows a question mark while the game is asked for it (at most twice).

Artwork gallery: `RM.ART` in `reminders/Config.lua`, files in `media/reminders/`: `shield.tga` and `ammo.tga` (a bundle of arrows; 256 px canvas, shield 180 x 254
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
| On, reminders running | the observation keys their conditions read, in every branch of every group, once each (`slot:17`, `combat`, `life`, `mounted`, `class`, `ammo`), and only those sources' events (`class` has none: it is read when wanted and on entering the world): `PLAYER_EQUIPMENT_CHANGED` for equipment, the regen events for combat, the three life events, the mount event, and for ammunition `PLAYER_EQUIPMENT_CHANGED`, `BAG_UPDATE_DELAYED` and `UNIT_INVENTORY_CHANGED` |
| An ammunition reminder, weapon takes none (or none equipped) | only a change of the ranged or ammo slot is acted on; bag and inventory events are dropped before any read. A look is up to six values from the character, and the bags only when nothing is selected |
| An item without details in a wanted slot | asked for at most twice; `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` only while that lasts |
| An event | marks its key; one 0.1 s timer reads each marked key once; only keys whose facts changed re-decide, and only the reminders that read them (an index by key) |
| Entering the world (login, reload, any loading screen: dungeon doors too) | everything wanted is read and decided at once, then read again 1 s and 3 s later through the usual marking (`State.lua` `SETTLE`), because the game is still settling just after the event and not every change has an event; only what differs re-decides. A newer entry or switching Reminders off makes older looks do nothing |
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
only the observations table). Optional: `Subject(cond)` (conditions that ask about the same thing share one simulation
choice) and `Merge(match, conds)` (say a run of them in one phrase in the rule's sentence). `class` is the worked example. For each observation key `Needs` names, a source in `State.lua`:
`ST.Source(kind, { events = { EVENT = handler }, Read = function(arg, obs) ... end })`. Then the editor's subject and
value choices (`Subjects`, `ValueChoices`, `WithSubject` in `TwichUI_Settings/pages/RemindersPlain.lua`), its sentence
(`KIND` there; without one the picker offers it under Other and the provider's own `Summary` is the card's sentence), a
test in `tests/test_reminders.lua`, and its facts and checks here. The `ammunition` kind (`reminders/Ammunition.lua` and State.lua's `ammo` source) is the worked
example of a kind with a file of its own. Buff, cooldown, health, inventory-count and target conditions are not in this release.

**A new picture.** Put the PNG (real transparency) in `assets/`, add a line to `ART` in `tools/make_reminder_art.py`, run
`python3 tools/make_reminder_art.py` (it prints the numbers), and add that line, with a label, to `RM.ART` and
`RM.ART_ORDER` in `reminders/Config.lua`. `media/` is packaged; `assets/` and `tools/` are not.

## Limits

- Mounted, the first look after login and server items: see "Not confirmed" above.
- `any` slot reads all nineteen slots for an item condition; no bank or inventory count is read, and the bags only for
  ammunition (when nothing is selected).
- Ammunition: the projectile subclasses 2 and 3, the slot's count covering all stacks, the last stack emptying the slot
  rather than leaving a count of zero, and the events raised when it does are unconfirmed (see "Not confirmed"). If the
  count did not cover all stacks, a second stack in the bags would be missed only while the selected stack ran low; if the
  slot did not empty, a count of zero would be `outOfAmmo`, which is also right. A weapon type the source lists for no
  ammunition (a custom ranged weapon) gets no `wrong` judgement. Reagent bags are scanned with the others (they can't hold
  ammunition).
- A character listed by name and realm: a renamed character, or one moved to another realm, has to be added again.
- Groups: three levels, 6 groups, 16 conditions (see "Three answers, groups and composition"). No drag and drop (Move up,
  Move down and Move into instead), no typed expressions. Who it is for holds one class, so several classes are conditions.
- Not in this release: Lua, dynamic clones, sounds, sharing, buff/cooldown/health/inventory/target
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
13. **Ammunition**, Hunter with a bow and arrows selected: Test > Right now says "Ammunition selected and some left"; turn it
    on: nothing shows. Drag the arrows out of the ammo slot with more in the bags: it shows; put them back: gone.
14. Shoot the selected stack down to nothing with none left anywhere: it shows when the last one goes. Note whether the slot is
    empty or shows 0. With two stacks in different bags, shoot the first away: does the slot keep showing the total, and does
    the reminder stay off until the last arrow?
15. Equip bullets for a bow, then arrows for a gun: a reminder for "the wrong kind" shows each time; swap weapon or ammunition
    to clear it. Take off the ranged weapon, or equip a wand or thrown weapon: nothing shows.
16. Add "Player is in combat" (all): unselect the ammunition out of combat (nothing), pull (it appears), leave combat (gone).
17. `/reload` and log in with a problem present: it appears without a flash of "waiting"; `/tui diagnostics` on another class
    with no ammunition reminder shows no events registered.
18. Known ammunition: register a server item as arrows or bullets, check it counts when selected and carried, that changing
    its kind takes effect without another event, and that `/reload` keeps the list.
19. **Groups and class.** Add **Your class** from the picker, choose Warrior; Create a condition group > Allow either condition
    (it says it is empty); **Add a condition** in that group three times: Warrior, Hunter, Rogue. The summary reads "Your class
    is Warrior, Hunter or Rogue".
    Turn it on: it shows on those classes only, not on a Mage. Check Test > Right now shows the group and each class
    condition, and Try a situation offers one choice for the three classes.
20. Put that group with "Player is in combat" (All): it shows for those classes in combat only; leaving combat hides it. Add
    "Off hand is not Shield": a shield hides it. Reload with the reminder on: it appears without a flash of "waiting".
21. Edit during a delay: set "wait before showing" to 5, start matching, then change the rule in the editor before it ends:
    it still shows five seconds after the edit (or not at all, if the rule no longer matches), never stuck on "waiting out
    its delay". The same for a minimum: edit while it is kept up and it still goes when the minimum ends.
22. Remove a group that holds conditions (it asks, naming how many), a group inside a group, then try a group inside that
    (refused with a reason). Open the settings with a large UI scale and a long list: the rows and buttons stay inside the page.
23. `/tui diagnostics`: the Reminders section lists how many conditions and groups run; with no reminder turned on nothing is
    listened for.
24. **The When designer.** Open a reminder's When: a card per condition, groups as boxes with their own heading. Edit a card:
    change it, press Cancel (nothing changes), then change and press Done. Add a condition from the picker: search, filter
    by category, choose "You are in combat"; Cancel adds nothing, Add condition adds it to that group. Make "Warrior or
    Hunter" with Create a condition group > Allow either condition, and put the ammunition condition above it in an All
    group: the page reads "Shows when all of these are true: Ranged ammunition needs attention, Your class is Warrior or
    Hunter". Move up, Move down, Move into another group (the message says what it is combined with now), fold a group,
    remove a group and press Undo. At a large UI scale and a small window check that nothing is clipped, the More menus open
    inside the window, and Tab and the mouse reach every button.
25. **Would this show now?** Open it with a reminder turned on and off: "Would show now" only while it is on screen,
    "Conditions match now" with the reason when it is turned off or waiting out a delay. On a client with no `UnitUsesAmmo`,
    an ammunition condition says "Cannot check ammunition on this client." and the reminder can't be turned on. Close it:
    the marks on the cards go. Hover the mark on a card for the longer explanation.
26. Open the settings with the When designer's picker or an editor open, close and reopen the window: nothing is left open.
    `/tui perf` with the Settings window shown lists `reminders.designer.layout` and the designer's pools; they stay level
    over repeated opening.
