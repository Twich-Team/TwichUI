# Reminders

Artwork, an icon or a few words on screen while conditions the player chooses are true, and nothing the rest of the
time. The first uses are a missing-shield reminder and an ammunition reminder; nothing in the design is about a class.
Code: `!!!TwichUI/reminders/`; settings: `TwichUI_Settings/pages/Reminders.lua`, `RemindersEditor.lua` and `AmmoItems.lua`
(the Known ammunition tab); tests: `tests/test_reminders.lua`, `tests/test_reminders_ammunition.lua`,
`tests/test_reminders_settings.lua`, `tests/test_reminders_enchant_sound.lua`, `tests/test_reminders_wellfed.lua`, `tests/test_ammo_items_settings.lua`; art: `tools/make_reminder_art.py`,
`tools/make_settings_icons.py` (sheet 4).

A reminder only reads. It never equips, uses, moves or casts anything, prints nothing in chat and sends nothing to
anyone. None exists until the player makes one, and each starts turned off.

Supplied client screenshots show earlier revisions. This agent has not exercised the WoW client. Evidence below is
identified as repository-inspected, unit-tested, simulator handler-tested or screenshot-reviewed; client checks remain
at the end.

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
| Whether a weapon has a temporary enchant (a weapon oil, sharpening stone, poison, a shaman's imbue): `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot)` answers a list of `{ hasEnchant, enchantType, timeLeft, charges, enchantID, enchantIconID }` for `MainHand` 0, `OffHand` 1 (and `Ranged` 2); `C_PaperDollInfo.GetTemporaryEnchantmentInfo(inventorySlot)` is the older form. Changes: `WEAPON_ENCHANT_CHANGED`, `WEAPON_SLOT_CHANGED`. The game's own buff frame reads it this way. The client says whether one is on, **not which**, so the condition cannot tell a wizard oil from a sharpening stone | `ItemDocumentation.lua`, `ItemConstantsDocumentation.lua`, `PaperDollInfoDocumentation.lua`, `Blizzard_BuffFrame/BuffFrame.lua`, `Blizzard_AuraContainer.lua`; the same reading is used by `glows/State.lua` |
| Whether you have a Well Fed buff: the helpful auras on `player` listed with `C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")` (called protected: while auras are hidden from addons it errors or answers secret, which is **unknown**, and `C_Secrets.ShouldAurasBeSecret()` is asked first), `UNIT_AURA` for `player` only (`RegisterUnitEvent`; an update that only moves a timer is skipped). Every food has a buff spell of its own, so the buff is told by its **name** as the client gives it for the Well Fed spell (`C_Spell.GetSpellName(19705)`, the English "Well Fed" when the client gives none) or by that spell ID. 19705 and the "each food has an ID of its own, go by the name" note come from the GlowingBars reference addon (data only, nothing copied); **not confirmed on a real client** | `UnitAuraDocumentation.lua`, `SecretPredicateAPIDocumentation.lua`, `SpellDocumentation.lua`; `buffback/Watch.lua` and `glows/State.lua` read auras the same way |
| `IsResting()` (true in an inn or a capital city); `PLAYER_UPDATE_RESTING` | `PlayerScriptDocumentation.lua`, `UnitDocumentation.lua`; the player frame, experience bar and honor system register the event |
| `IsInInstance()` answers `isInInstance, instanceType` ("party" a dungeon, "raid" a raid, "pvp" a battleground, "arena", "scenario", "none" the open world); the kind of place changes only across a loading screen, so it is read on `PLAYER_ENTERING_WORLD` | `InstanceDocumentation.lua`; project use in `qol/GuideAutoHide.lua`, `healer/Watch.lua` |
| `PLAYER_EQUIPMENT_CHANGED` (slot, hasCurrent) | `PaperDollInfoDocumentation.lua` |
| `BAG_UPDATE_DELAYED`; `UNIT_INVENTORY_CHANGED` (unit) | `ContainerDocumentation.lua`; `UnitDocumentation.lua` |

**Not confirmed in the game:** that `PLAYER_UPDATE_RESTING` fires on Forever when entering and leaving an inn or city (a look after entering the world catches the rest), that `IsInInstance` answers "party" / "raid" for Forever's instances, that `PLAYER_MOUNT_DISPLAY_CHANGED` fires on Forever whenever mounting or dismounting
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
| `player` | `state`, `negate` | `combat` (in combat), `dead` (dead **or a ghost**), `ghost` (only the released spirit), `mounted` (offered only while the client has `IsMounted`), `resting` (in an inn or a capital city; needs `IsResting`), `dungeon` (inside a five-player instance), `raid` (inside a raid instance); the last two need `IsInInstance`. A battleground, arena or scenario is neither a dungeon nor a raid. "Player is not resting" is how a reminder is kept from showing while resting |
| `class` | `class` (a class token: `WARRIOR`, `PALADIN`, ... never a translated name), `negate` | the classes this client lists (`CLASS_SORT_ORDER`, nine in `Blizzard_FrameXMLBase/Camelot/Constants.lua`; TwichUI's own list of the same nine when the client gives none). New ones start with no class chosen: unfinished until one is |
| `weaponEnchant` | `hand` (`mainHand` or `offHand`), `what` (no `negate`: it reads as a sentence) | `missing` (a weapon is held in that hand and has no temporary enchant) or `applied` (a weapon there has one). A hand with nothing that can take an enchant (empty, a shield, an item held in the off hand, a fishing pole) is **never** `missing` or `applied`. An item the game has not described yet, or an answer that cannot be read, is **unknown**, never `missing` |
| `wellFed` | `what` (no `negate`: it reads as a sentence) | `missing` (the game listed your helpful auras and none is Well Fed) or `applied` (one is). Auras hidden from addons, or a list longer than the 40 looked at with no Well Fed in it, are **unknown**, never `missing` |
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
    place = { preset = "belowCenter" },
    sound = "TwichUI Notification" } } }   -- optional; absent means none
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
separate from how it looks (`display`). The optional `sound` is a sound's **name** (TwichUI's own, or any other
LibSharedMedia sound), never a file path: it is looked up when it plays (`R:ResolveSound`), so a sound that has gone plays
nothing, and a stored value that is not a usable name reads as none and is left as saved. Nothing about a decision, an observation, a timer or a preview is saved.
Configuration sharing keeps both keys on this computer (`TwichConfig.LOCAL`, "other": a reminder can name characters).
The one exception is the ammunition you registered, `ui.ammoCustom` (above), which is a shared list of its own.

## Making and editing (settings > Everyday > Reminders)

The card holds the switch. Under it: **Your reminders** (thumbnail, name, the rule as a sentence or what is wrong, what it
is doing now, and its own switch) and **New reminder**, which opens the template catalog (below). The templates are **Missing shield** (name "Shield reminder", "Off hand is not
Shield", the shield artwork with "Equip your shield", no sound, no pulse, below the middle, this character only),
**Ammunition** (name "Ammunition reminder", "Ranged ammunition has a problem", the arrows artwork with "Check your
ammunition", the same place and scope; it does nothing for a weapon that takes no ammunition),
**Well Fed ran out** (name "Well Fed reminder", "You are not Well Fed", the plate-and-cutlery artwork at size 48 with
"Eat something", the same place and scope; when the buff
runs out it appears, and it goes within a moment of eating), **Missing weapon enchant** (name "Weapon enchant reminder", "Main hand weapon has no temporary enchant", the bell icon with
"Apply your weapon oil", the same place and scope; change the hand, or add a second condition for the off hand, in
When), **Missing equipment or item** (any slot is not an item you choose; shows that item's icon; unfinished until the item is
chosen) and **Custom reminder** (your words; needs a condition). Each is an ordinary reminder once made: nothing about
the template is remembered.

### The preview companion (`pages/RemindersPreview.lua`)

The editor companion has one visibility predicate: Settings is open, Reminders is the active page (not search),
the hosted editor is visible, Live preview is enabled for this session, the selected reminder still exists, and
neither When nor the catalog owns the companion slot. A gameplay/configuration refresh cannot bypass it.
`PV.Update` updates content and placement without showing a hidden frame. Only guarded editor reconciliation can
show it. Closing or leaving invalidates queued page refreshes, hides immediately and clears the held view.

**Live preview**, beside Duplicate/Delete, enables the companion for this session without changing the reminder or
profile. The companion's minus control still minimizes it. Artwork/text clicks reveal the corresponding setting;
Actual size/Fit never changes saved scale. The window follows taller Settings geometry through one resize hook,
which only updates an existing visible preview and uses the same visibility guard. There is no continuous polling.

**Show on screen** remains the independent explicit temporary world preview. It does not enable the editing
companion. Closing Settings or entering combat ends the temporary world preview through its existing lifecycle.
When and catalog replace the companion exclusively; cancel/close restores it only for an active enabled editor.
Reopening uses the current selection and the same pooled frame.

Evidence: **unit-tested** with an individually shown host under inactive Settings, repeated subsequent subscriptions,
configuration changes, equipment/zone events, direct Update/Show calls, stale deferred work, other-page navigation,
exclusive companion transitions, disable/re-enable, repeated close/reopen and explicit world-preview separation.
**Simulator handler-tested** for closed refresh attempts, navigation, disable/re-enable, Save/Cancel and taller window
updates. **Not real-client-tested:** sustained gameplay after close, actual pointer delivery, installed fonts and UI scale.

### The template catalog (`pages/RemindersCatalog.lua`)

**New reminder** opens a frame beside the settings window (`R.SettingsAnchor`, as the sample previews do; centred if the
window isn't up): the templates as cards (existing artwork or the feature's icon, name, one line, **Use template**; the
long description is its tooltip) and **Custom reminder** under them. Choosing goes through the page's `P.Create`, so the
reminder is made by `RM.Create`, the one checked path: a fresh table each time (two uses are independent copies, with
their own ids), turned off, named by the template; the catalog then goes away, the new reminder is selected and its editor
is open. A refusal (24 reminders in a profile, a newer-format profile) leaves the catalog open with the reason in its own
line and creates nothing. The close box, Esc, the settings closing, or leaving the Reminders page closes it and changes
nothing. Every template here already used a supported condition; none was added. A preview already on screen is not
touched by making another reminder. Not yet: search and category filters, per-template artwork beyond what exists.

Evidence: **unit-tested** (`tests/test_reminders_settings.lua` section 10: cards, independent copies and ids, starts off,
selection and editor, cancel, limit refusal, preview kept, page hide); **simulator-tested** only for construction
(`tools/simlab/smoke.sh`). **Not tested**: how it looks and is placed in the real client, Esc, the close box, tooltips.

The chosen reminder: its name, its switch (refused, with the reason, while it has problems), **Duplicate** (a fresh id,
turned off, right after it; the original is untouched) and **Delete** (asks, names it; its frame goes at once). Then:

- **Show**: Display (artwork with text, artwork, icon with text, icon, text only); Artwork (the gallery); Icon from (a
  TwichUI icon, or an item's icon by ID, link or a drop from the bags: the item needn't be equipped); Words.
- **When**: the condition designer, in three blocks (`TwichUI_Settings/pages/RemindersDesigner.lua`; the words are
  `RemindersPlain.lua`; see "The When designer" below).
- **Placement**: Position (below the middle, above the middle, middle, top, bottom, where I put it); Size; Opacity; Text size; Words go (below, above, right, left). **More placement and appearance options**
  (closed at first, for the session): keep proportions or width and height; font, outline, text color; background
  (none, soft shade, framed panel); anchor point and x / y offsets (typed values follow drags and the reverse); layer
  (low, medium, high); fade in and out; pulse; wait before showing; keep up at least.
- **Sound**: an optional sound for when it appears (a dropdown of None, TwichUI's own sounds and every LibSharedMedia
  sound) and **Play** to hear it. A chosen sound that is not installed stays chosen, is said so, and plays nothing.
- **Preview** (no longer a section of the page): see "The preview companion" below.
- **Diagnostics**: overall Showing / Hidden / Needs attention / Unknown result, a concise reason, then illustrated
  condition-result rows with Met / Not met / Unknown and separate observed values. All/Any groups retain their order
  and indentation. **Technical details** discloses full troubleshooting information. **Try a situation** is a separate
  disclosure with clearly labelled SIMULATED sample inputs and results; shared observations still use one consistent
  input. Neither disclosure changes the live rule or the game's observations.

Words carry every state; colour only agrees.

The Appearance artwork and Choose control share an inset group. Text color and the existing numeric Size slider sit
in one quieter row; the slider still edits the original size value. List width grows within bounds when the workspace
widens, preserving minimum editor width. The preview's inset sizing well, eye status and rounded rims are cosmetic:
Actual size/Fit still changes presentation only, and the active-editor visibility guard remains authoritative.

Reusable opt-in artwork components live in `SettingsCraft` (`Craft.lua`): fixed-corner `Sheet`/`Frame`, native-control
state paint through `Control`, and the painted slider `Thumb`. Runtime art is under `media/style-v2/craft/`; original
standalone frame/button/selection sources are `assets/craft-*-source.png`, prepared with `tools/make_craft_art.py`.
Button states share identical alpha silhouettes; selected surfaces use their own painted source, and chips retain
capsule geometry. Primary, normal/secondary, hover, depressed, disabled and restrained destructive treatments are distinct.
The generic helpers own no reminder state or callbacks. `SettingsMaterial` remains the surface/font/scrollbar facade:
`Rim`, `ReminderControl`, `PanelFace`, `HeaderBand`, `ScrollRail`, `ReminderFont`. Its quiet large-area grain is retained.
The source references are design specifications, never runtime backgrounds.

Only Reminders opts into the new shared shell/header/search. Search keeps its geometry while typing, while the active-editor
predicate still suppresses the companion during search. Ordinary pages restore their original rails, fonts, emblem/search
dimensions and control materials. The list well aligns with the primary editing stack, capped for long diagnostics.
Adoption on other Settings pages can be incremental; standalone windows need a later load-owner decision because these
helpers currently load with Settings. Wider rollout and real-client visual acceptance remain pending.


## The When designer

The When builder edits the existing reminder tree through a private draft. It stores the same rule and targeting
fields as before. It uses the same condition providers, All/Any evaluation and three evaluation outcomes.
Opening When shows a dedicated reminder rail and rule panel joined by a bronze hinge. The main Settings page stays
mounted beneath the workspace, preserving its selection, scroll position and open sections. Its frame moves below the modal for input isolation; Save or Cancel restores its prior strata and opacity. Tooltips, popup menus and the centered drag ghost follow the workspace effective scale.
The workspace fits the screen at the current UI scale. The rail holds a scrollable reminder list, selected reminder,
concise When summary and an isolated appearance sample.

- **Show a reminder when** presents the first condition of a flat All rule. **Only while** presents the other
  conditions in the same conjunction. The card fields use the condition's own subjects and values. A mounted
  check offers mounted and not mounted. An equipment check offers valid equipment slots and their supported
  values. A specific item can be chosen by item ID or link.
- **Location chips** present Dungeon and Raid selections. Adding an alternative creates an ordinary Any group through
  the existing rule APIs. Removing a token removes its predicate. A single remaining alternative retains its group.
  Duplicate values, negated alternatives, mixed groups and nested structures use Advanced logic. The adapter reads
  the original structure without converting existing rules on opening.
- **Advanced logic** opens for a root Any, other grouped rules or unsupported predicates. All/Any controls, folding,
  grouping and contextual editing use the original tree. Imported predicates this version cannot read can be moved or removed. A reminder with an unreadable
  predicate cannot be enabled.
- **For** changes character scope independently of the conditions. The header offers every character, this character
  and a chosen character list. Targeting options provide list and class settings. A class condition inside the tree
  remains an ordinary predicate.
- **Search...** and the category filter narrow the palette. Click or drag an entry to set it up. Drag cards or
  groups to a highlighted insertion position. A drag outside a valid target leaves the draft alone. Right-click a
  card or hover to reveal the compact contextual menu. It offers removal, duplication and movement through ordinary controls.
  Location has one default catalog entry with both alternatives available in its editor. Searching Raid can also find
  the corresponding predicate directly. Well Fed is in Other.
- **Current visibility** reflects the saved reminder. Card states and Details can inspect the draft. **Try a situation**
  tests the draft against chosen inputs without changing the live observations or displaying a reminder. Details and
  situation inputs expand in their own scrollable bottom region, above the persistent footer.
- **Save** validates and applies conditions and targeting together. **Undo** and **Redo** operate on the draft
  and cover changes such as edits, moves, additions, removals and targeting. **Cancel** discards the draft.
  The close button, Escape after closing menus or drags, switching reminders and opening the template catalog
  ask before discarding unsaved work.
  Leaving the settings page or closing settings discards the draft. A rule changed elsewhere while the builder was open
  must be reopened before it can be edited again.

The saved schema is unchanged. Draft changes retain a node's data and identify it by table while dragging.
The tree and palette reuse bounded frame pools. The designer reports layout work through
`reminders.designer.layout` and counts its pools in Diagnostics.

## Display

Defaults: artwork with text, 64 units on the longer side, the picture's own proportions, opacity 100, text 18 with an
outline in ivory below the picture, no panel, medium layer, no fade, no pulse, no delay or minimum, `CENTER` 0, -200
(below the character, above the action bars). Click-through; only the move handle takes the mouse, only while moving.
Text is plain (no `|`, no control characters, up to 120 characters), wraps at 420 units, and is never read as markup or
an expression. A missing item icon shows a question mark while the game is asked for it (at most twice).

Artwork gallery: `RM.ART` in `reminders/Config.lua`, files in `media/reminders/`: `shield.tga` and `ammo.tga` (a bundle of arrows; 256 px canvas, shield 180 x 254
used) and `shield-small.tga` (64 px canvas, 44 x 62 used) for 64 units and under. Uncompressed 32-bit TGA, bottom-left
origin; only the used part is drawn. `wellfed.tga` / `wellfed-small.tga` (a plate with crumbs, a fork and a knife; 256 x 186 and
64 x 47 used) is the Well Fed template's artwork, built by `tools/make_reminder_art.py` from `assets/reminder-art-wellfed-source.png`.
There is no in-game image import.

## Sound

Each reminder can name one sound (`RM.SetSound`, default none). The controller plays it once, with `PlaySoundFile` on the
sound-effects (`SFX`) channel, **when the reminder appears** (after its delay, if it has one), and:

- not again while it stays up, and not when a loading screen, a settings change or a refresh merely hid and restored it;
- again after its conditions stopped matching (status "hidden") and came back, but a reminder that comes and goes is held to
  one sound every 2 seconds (`SOUND_GAP`);
- not when the conditions become unknown (the game not having said) and then known again within the same stretch;
- again when the reminder is turned off and on, Reminders is switched off and on, or after a reload, if the conditions are
  true;
- never for a preview, and never for a reminder that is off, invalid or for another character.

`PlaySoundFile` has no volume of its own: it follows the game's sound-effects volume. Nothing is written in chat. A sound
that is not installed plays nothing and is counted in `/tui diagnostics` (sounds played, held back, not installed, refused).

## Preview, moving, diagnostics

An on-screen preview shows one reminder where it sits, marked "Preview: <name>", whatever its rules say, without a
second live frame. It changes no enable state, rule, observation or decision. Closing settings, combat, deletion,
disabling Reminders or a profile change ends temporary previews.

**Place on screen** beside Live preview in the selected-reminder header, or **Place…** in the companion, enters the
same explicit placement transaction. Advanced retains presets, offsets and effects, without a duplicate placement row. Settings and its companions hide completely;
a small toolbar remains. Dragging changes private coordinates. **Finish** (or right-clicking the handle) validates
and saves the position once; **Cancel / Esc** keeps the original position. Both restore the prior page, selection,
scroll position and current window dimensions. Combat or deletion cancels. Closing settings while placing cancels
and stays closed. A changed source identity or a newer external position prevents a stale Finish from overwriting it;
a late drag-stop callback after cancellation cannot save anything.

The editing companion remains separately guarded by the active Reminders context and session preview toggle.
Its **Background** menu offers Dark, Transparent, Landscape and Parchment for this session only. Transparent removes
the entire well's fill, including the shell underneath it; it is not a checkerboard. Actual size/Fit and background
switching do not change display values. Artwork/text hover has a painted rim; clicking reveals and briefly highlights
the corresponding field without editing it. The builder's parchment sample uses the isolated renderer with ink for
presentation; it does not change the saved reminder background or text color.

A reminder that isn't running (disabled or for another character) can be inspected through `State.Peek` without adding
to what live reminders read or listen for.
The Test section's simulations go through the same `Evaluate.Run` on a table built from the scenarios
(`Evaluate.Simulate`) and never see the live one. `/tui diagnostics` has a Reminders section with counts only (including the sound counts, never a sound's name).

## Events and performance

| Moment | What happens |
|---|---|
| Switched off | no event, every frame hidden, every timer stale |
| On, no reminder turned on for this character | `PLAYER_ENTERING_WORLD` only |
| On, reminders running | the observation keys their conditions read, in every branch of every group, once each (`slot:17`, `combat`, `life`, `mounted`, `class`, `ammo`, `enchant`, `wellFed`), and only those sources' events (`class` has none: it is read when wanted and on entering the world): `PLAYER_EQUIPMENT_CHANGED` for equipment, `WEAPON_ENCHANT_CHANGED`, `WEAPON_SLOT_CHANGED` (and a change of slot 16 or 17) for weapon enchants, the regen events for combat, the three life events, the mount event, for ammunition `PLAYER_EQUIPMENT_CHANGED`, `BAG_UPDATE_DELAYED` and `UNIT_INVENTORY_CHANGED`, and for Well Fed `UNIT_AURA` for the player only |
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
- Weapon enchants: only whether a hand has one, not which, and not how long it has left (the game does give the time and
  charges; a condition on them is not built). The off hand and the main hand only; no ranged slot. A fishing pole counts as
  nothing to enchant.
- Well Fed: only whether the buff is there, not how long it has left (a condition on the time left is not built) and not
  which food gave it. It is unknown, so nothing shows, while the game hides your buffs from addons.
- Not in this release: Lua, dynamic clones, a volume or channel per sound, sharing, buff/cooldown/health/inventory/target
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
7. Show on screen, then Place / Move on screen. Drag and Cancel: old coordinates remain. Repeat and Finish: the new
   position survives reload. Esc restores settings; closing settings stays closed. Combat cancels without saving.
   Repeat with each preset and UI scale; release the mouse after cancellation to check stale drag cleanup.
8. Every display mode, both proportions, a long text on the right, the framed panel, each layer, at UI scale 0.64 and
   1.15. Fade and pulse on: short and calm; Notifications > Reduced motion: neither.
9. Delay 5 with a quick swap: nothing shows; a minimum of 10: it stays, then goes; turn it off during the minimum: gone.
10. Duplicate, rename, delete (asks; gone at once). Switch profile: the other profile's reminders, nothing stale.
11. Reminders off: nothing shows, `/tui diagnostics` shows no events registered.
12. **Missing weapon enchant**: with no oil on your main hand it shows; apply one (the icon appears in the buff area): it goes
    within a moment; let it expire or cancel it: it comes back. Note whether it comes back when the oil *runs out* without
    you doing anything (this depends on `WEAPON_ENCHANT_CHANGED` firing on expiry; if it does not, it only returns at the next
    equipment change or loading screen). A fishing pole, a shield and an empty hand never show it. `/reload` with an oil on:
    no flash of the reminder; with none: it shows. A dual-wielder: add an off-hand condition, each hand answers on its own.
    Test > Right now says "No temporary enchant" / "Has a temporary enchant".
    **Well Fed**: from the templates, "Well Fed ran out" shows while you have no Well Fed buff; eat buff food (sit for the full
    ten seconds): it goes within a moment; cancel the buff or let it expire: it comes back (unlike an oil, a buff expiring
    sends `UNIT_AURA`). Test > Right now says "Well Fed" / "Not Well Fed". Check the buff really is named "Well Fed" on your
    client (hover it): if the reminder stays up while you are fed, send the exact name and its spell ID. In a fight where
    buffs are hidden, expect no change either way. `/reload` while fed: no flash of the reminder.
13. **Sound**: choose a sound and press Play (you hear it; with the sound-effects volume at zero you will not). Turn the
    reminder on with its conditions true: one sound as it appears; none while it stays up, none on a loading screen; take the
    condition away and bring it back: one more (not twice inside 2 seconds). Show on screen (preview): silent. Pick a sound
    from another addon, then turn that addon off and reload: the editor says it is not available, nothing plays and nothing
    errors. Check a chosen sound is not too loud over combat sound.
14. Look for errors with Display Lua Errors on throughout; check the icons in the editor at small UI scales.
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
24. **The When designer.** At normal and higher UI scale, check visible field edges and centers, help anchors and
    dropdown rows against the actual cursor; no invisible Settings row should react. Check that the centered drag ghost
    and insertion markers agree with the pointer. Check smaller wheel steps, scrollbar thumb dragging and typed size values.
    In a flat All rule, edit a card field and change For. Cancel and reopen to verify both original
    values. Change them again, exercise Undo/Redo, Save, and verify the result after `/reload`. Add from the search and
    category-filtered palette. Drag a card to an insertion edge and into an Any group. Drop outside to cancel. Try the
    same movements with the contextual menu, fold the group, then remove it and Undo. At high UI scale verify the footer,
    menus and both scrollbars remain reachable with the mouse and keyboard.
25. **Current visibility.** With a disabled reminder whose conditions match, the card can say Met while visibility says
    Hidden now. With an enabled reminder, check showing, hidden and unknown outcomes. Use Details and Try a situation
    and verify the live display is unchanged. On a client without `UnitUsesAmmo`, check that the capability message
    appears and the unusable reminder cannot be enabled.
26. Open the settings with the When designer's picker or an editor open, close and reopen the window: nothing is left open.
    `/tui perf` with the Settings window shown lists `reminders.designer.layout` and the designer's pools; they stay level
    over repeated opening.
27. Settings > Reminders > **New reminder**: the catalog opens beside the window. Close box, Esc and closing the settings
    each shut it and make nothing. **Use template** twice on one card: two reminders, both "Off", the editor open on the
    second; rename one, the other is unchanged. With a preview showing, use a template: the preview stays. With 24
    reminders, **Use template** and **Custom reminder** say the limit in the catalog and it stays open. Check the cards'
    pictures, the text fitting, and that the catalog doesn't cover the window or fall off the screen.
28. Edit a reminder with the page scrolled anywhere: the preview stays beside the window and follows the selection, the
    name, the picture, the words and the place. A turned-off reminder previews and stays off. **Show on screen** and **Hide
    preview** work as before. **New reminder** swaps the preview for the catalog; the close box or Esc brings the preview
    back for the same reminder; **Use template** shows it for the new one. Drag the window to the right edge of the screen
    and at a larger window scale: the companion flips to the left or stays on screen, and never overlaps the window.
    Close the settings and reopen: one preview, none left behind.


Condition-type art is resolved centrally by `RemindersPlain.ApplyArt`: enchanted blade for weapon enchant, separate
crossed dark-steel swords for combat, and the existing painted NPC horse head for Mounted. These identities are reused
in the palette, cards, summaries, diagnostics and drag ghosts, and are independent of the reminder's selected artwork
and template illustration. New source/prompts and preparation are `assets/reminder-condition-*` and
`tools/make_reminder_condition_art.py`; 64/32-pixel TGAs live under `media/reminders/conditions/`.
