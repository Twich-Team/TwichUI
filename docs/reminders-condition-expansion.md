# Reminders: condition library expansion (RC-001 to RC-020)

Tracker for the proposed condition backlog (`TwichUI-Reminders-Recommended-Conditions.md`, 2026-11-11, outside the
repository). The backlog is a proposal, not a list of facts: each entry below records what the source actually had, what
was built, and what is still owed. Branch `feature/reminders-conditions`, based on the settings modernization
(`feature/style` at 81f789fe). Feature doc: [reminders.md](reminders.md).

Evidence labels follow CLAUDE.md. **Nothing in this file is real-client-tested.** "API" rows cite the Forever UI source
(`../wow-ui-source`, branch `forever`, `Blizzard_APIDocumentationGenerated` unless noted); a documented API is not proof
that a Forever server fills it in.

## Shared decisions

- **Three answers.** Every new kind returns Match, No match or Unknown; Unknown never shows, and negation leaves it
  Unknown (`C.Negate`). Data that can't be read (secret, hidden, more than is looked at, not given) is Unknown, never
  "absent" or zero.
- **Inapplicable is No match, both ways.** Where a predicate has nothing to judge, it never matches, whichever way it is
  asked: no mana pool (neither "below" nor "at least"), no target (neither "friendly" nor "not friendly"), a spell you
  don't know (neither "ready" nor "cooling"), an aura that isn't on you (neither "running out" nor any stack count). The
  absent case is a choice of its own ("missing", "You have no target"), combined in an Any group when wanted.
- **Thresholds.** "below" / "fewer than" is strictly less than; "at least" includes the number (`C.Compare`). Exactly
  30% mana is "at least 30%", never "below 30%". A time "less than 60 seconds left" is not met at exactly 60.
- **Identity.** Spells, buffs and forms by spell ID, items by item ID, places by uiMapID or instance ID, resources by
  power token. Names are only labels, looked up when shown; nothing is matched by name. Each rank of a spell is its own ID,
  so a buff condition holds an explicit list of up to 8 IDs.
- **Time.** A decision is made at `obs.now`. A provider whose answer can change with time alone has `NextChange`; the
  controller keeps at most one timer per running reminder for the soonest boundary (never sooner than 0.25 s), reads its
  observations again then (so an expiry with no event is still seen) and decides again. No OnUpdate, no polling.
- **Events.** Each kind's source registers only while an enabled reminder for this character uses it (`ST.Want`); kinds
  nobody uses read nothing and listen for nothing (unit-tested).
- **Sound.** Unchanged: once per appearance. A value changing while the reminder stays up (mana regenerating, a buff
  ticking down) plays nothing (unit-tested).
- **Client capability.** A kind whose API this client lacks (`Supported`) is kept, said so, and its reminder can't be
  turned on (the existing ammunition / player-state behaviour, made generic in `C.Check`).
- **Compatibility.** No migration. New kinds, the new `player` states and the weapon enchant's new choice are new values; a
  build from before reads them as a kind / value it doesn't know, keeps them as saved and refuses to run that reminder
  (docs/reminders.md, "Groups need no migration"). Stored `version` stays 1.
- **Cross-class.** Nothing is remapped. A Bear Form condition on a mage is "not in Bear Form"; a mana condition on a warrior
  never matches; a talent tree of another class is never the leading tree.

## Existing conditions (capability matrix, from source)

| Kind | Player-facing | Operators / choices | Stored fields | Data source and events | Tests | Simulator | Builder | RC |
|---|---|---|---|---|---|---|---|---|
| `equipment` | Your off hand is not a shield | is / is not; empty, shield, weapon, two-hand, holdable, fishing pole, item | `slot`, `what`, `negate`, `item` | `GetInventoryItemID`, `C_Item.GetItemInfoInstant`; `PLAYER_EQUIPMENT_CHANGED`, item-data events | `test_reminders.lua` | `reminders.sh` (several views) | card, item box | RC-014 |
| `weaponEnchant` | Your main hand weapon has no temporary enchant | missing, applied, **expiring** (new) | `hand`, `what`, `seconds` | `C_Item.GetWeaponEnchantInfo`; `WEAPON_ENCHANT_CHANGED`, `WEAPON_SLOT_CHANGED` | `test_reminders_enchant_sound.lua`, `test_reminders_library.lua` | `reminders.sh` editor views | card | RC-006 |
| `wellFed` | You are not well fed | missing, applied | `what` | `C_UnitAuras.GetAuraDataByIndex` (HELPFUL); `UNIT_AURA` player | `test_reminders_wellfed.lua` | `reminders.sh wellfed` | card | RC-003 (special case) |
| `player` | You are in combat | is / is not; combat, dead, ghost, mounted, resting, dungeon, raid, **moving**, **taxi** (new) | `state`, `negate` | `UnitAffectingCombat`, `UnitIsDeadOrGhost`, `IsMounted`, `IsResting`, `IsInInstance`, `IsPlayerMoving`, `UnitOnTaxi` | `test_reminders.lua`, `test_reminders_library.lua` | `reminders.sh` | card, location chips | RC-012 (place only), RC-020 |
| `class` | Your class is Warrior | is / is not; nine classes | `class`, `negate` | `UnitClassBase` | `test_reminders_groups.lua` | — | card | — |
| `talent` | Talent specialization is Protection (Warrior) | is / is not; a tree, tied, no points | `class` + `tree` or `state` | `gear/Data.lua` `TalentSpent`; talent events | `test_reminders_talent.lua` | — | card | RC-001 |
| `ammunition` | Ranged ammunition needs attention | problem, noAmmo, outOfAmmo, wrong | `what` | `UnitUsesAmmo`, ammo slot, bags | `test_reminders_ammunition.lua` | — | card | RC-005 (ammo only) |
| `group` (node) | All of these / At least one | all, any | `match`, `conditions` | — | `test_reminders_groups.lua` | `reminders.sh nested`, `drag` | Advanced logic | — |

## RC status

Status words: **Existing** (already in source before this work), **Built**, **Extended** (an existing kind gained a
choice), **Redundant**, **Deferred** (feasible, not built), **Blocked** (the client doesn't give what it needs).

| RC | Status | Condition ID | Operators | API / data | Tests | Simulator | Artwork | Limitations | Real-client acceptance |
|---|---|---|---|---|---|---|---|---|---|
| RC-001 Talent specialization | **Existing** (verified) | `talent` | is / is not a tree, tied, no points | `C_Traits` tree point totals via `gear/Data.lua` | unique winner, ties, zero, unreadable, negation, events, cross-class (`test_reminders_talent.lua`) | not in a scenario | `classResources` icon | the value list shows every class's trees, labelled with the class | spend / reset points, swap talent group: Test shows the leader at once |
| RC-002 Talent learned / rank | **Deferred** | — | — | would need `C_Traits.GetTreeNodes` / `GetNodeInfo` per node; the project reads only per-tree totals today, and node identity across a respec is unverified | — | — | — | needs a talent-node probe in the client and a talent picker | — |
| RC-003 Buff / debuff presence | **Built** | `aura` (`what` present / missing; `harmful`) | on you / missing | `C_UnitAuras.GetAuraDataByIndex("player", i, HELPFUL/HARMFUL)`, `C_Secrets.ShouldAurasBeSecret`, `UNIT_AURA` player | presence, absence, hidden, >40, secret ID, ranks, negation-free choices, events (`test_reminders_library.lua` 1, 7) | `reminders.sh conditions` | `mage` icon (buff), `hazardAlerts` (debuff) | self only; IDs, not names | add a buff's ranks; cast it, let it drop, cancel it; in a hidden-aura fight it stays unknown |
| RC-004 Aura remaining duration | **Built** | `aura` `what = expiring`, `seconds` | less than N seconds left | `expirationTime`, `duration` (0 = never runs out, as the buff frame reads it) | boundary, equality, permanent, unknown, absent, two instances, timer boundary (1, 7) | `reminders.sh conditions` | as RC-003 | the longest-lasting instance counts | a buff with 1 min threshold appears at 59 s; renewing it hides it |
| RC-005 Item quantity | **Built** | `itemCount` | fewer than / at least N | `C_Item.GetItemCount(item, false)`: carried bags only; `BAG_UPDATE_DELAYED` | boundaries, zero vs unknown, validation, events (3, 7) | `reminders.sh conditions` | NPC reagent pouch | bank never counted; an ID the game has no item for counts 0 (the editor shows "no item details") | count drops on use; buy/destroy updates; does `GetItemCount` include equipped items on Forever? |
| RC-006 Weapon enchant remaining | **Extended** | `weaponEnchant` `what = expiring`, `seconds` | less than N seconds left | `GetWeaponEnchantInfo` `timeLeft` (ms) | boundary, bare/no weapon, unknown end, no-event expiry via boundary (2, 7) | `reminders.sh conditions` | existing enchant art | charges not offered: 0 can't be told from "no charges" | apply an oil: reminder at the threshold, gone after renewing; expiry without an event is caught |
| RC-007 Health threshold | **Blocked** | — | — | `UnitHealth` / `UnitHealthPercent` are documented `SecretReturns = true` (UnitDocumentation.lua): never comparable by addon code | — | — | — | — | a probe: is `issecretvalue(UnitHealth("player"))` false out of combat on Forever? Only then reconsider |
| RC-008 Resource threshold | **Built** | `power` | below / at least N% | `UnitPower` / `UnitPowerMax` (`SecretWhenUnitPowerRestricted`), `UNIT_POWER_UPDATE` / `UNIT_MAXPOWER` / `UNIT_DISPLAYPOWER` player | boundary, no pool, secret, other resource's event, no repeated sound (4, 7) | `reminders.sh conditions` | Healer Watch vessel | mana, rage, energy only (combo points are the class bars' own) | drink: hides at the threshold; a druid in bear form still reads mana; in a restricted fight it stays unknown |
| RC-009 Spell known | **Built** | `spellKnown` | know / don't know | `C_SpellBook.IsSpellKnown`, `IsPlayerSpell`, `IsSpellKnown`; `C_Spell.DoesSpellExist`; `SPELLS_CHANGED` | known, not known, invalid under negation (4, 7) | — | NPC sealed scroll | each rank its own ID | learn a rank at a trainer: it changes without a reload |
| RC-010 Form / stance | **Built** | `form` | in / not in a form, or no form | `GetShapeshiftForm`, `GetShapeshiftFormInfo` (4th return the spell ID), `UPDATE_SHAPESHIFT_FORM(S)` | form, none, cross-class, unknown (4, 7) | — | NPC paw | choices list this character's forms; another class's stored form is kept, never mapped | shift in and out; stealth and stances report as forms? |
| RC-011 Level | **Built** | `level` | below / at least N | `UnitLevel`, `PLAYER_LEVEL_UP` payload, `PLAYER_LEVEL_CHANGED` | boundary, no cap, event payload (4, 7) | — | NPC hooded trainer | 1 to 999 accepted | ding: changes at once |
| RC-012 Group context | **Built** | `groupType` | is / is not solo, party, raid group, any group | `IsInRaid`, `IsInGroup`, `GROUP_ROSTER_UPDATE` | raid group ≠ party ≠ raid instance (5, 7) | — | profiles medallions | instance groups count as grouped | join, convert to raid, leave |
| RC-013 Zone / instance | **Built** | `zone` | in / not in a map (and maps inside it) or an instance | `C_Map.GetBestMapForUnit`, `C_Map.GetMapInfo` parents, `IsInInstance` + `GetInstanceInfo` instanceID, `GetRealZoneText(id)`; zone events | chain, instance, unknown, negation (5, 7) | — | map toolbar | chosen where you are (no search of all maps); dungeon floors may have the outside zone as a parent | choose Elwynn in Goldshire: true in Fargodeep Mine, false in Stormwind; inside the Deadmines choose the instance |
| RC-014 Equipment attributes | **Redundant** | `equipment` | (existing) | (existing) | existing | existing | existing | named equipment sets not offered (none supported) | — |
| RC-015 Durability | **Built** | `durability` | broken; below N% | `GetInventoryItemDurability(slot)`, `UPDATE_INVENTORY_DURABILITY`, `PLAYER_EQUIPMENT_CHANGED` | one broken among nine full, equality, nothing to repair (3, 7) | `reminders.sh conditions` | NPC hammer | equipped items only | die a few times: worn, then broken; repair: gone |
| RC-016 Bag space | **Built** | `bagSpace` | fewer than / at least N free | `C_Container.GetContainerNumFreeSlots` bags 0..`NUM_BAG_SLOTS`, family 0 only; `BAG_UPDATE_DELAYED` | boundary, special bags excluded (3, 7) | `reminders.sh conditions` | NPC leather backpack | reagent bag and special bags not counted | fill bags; a quiver's free room doesn't count |
| RC-017 Cooldown | **Built** | `cooldown` | ready; cooling; ready within N s | `C_Spell.GetSpellCooldown` (`isActive`, `isOnGCD` NeverSecret), `SPELL_UPDATE_COOLDOWN`, `SPELLS_CHANGED` | GCD, unknown spell, held, within boundary, no-event end (4, 7) | — | diagnostics hourglass | an end that is secret is unknown for "within" | cast a long cooldown; the reminder for "ready" comes back when it ends |
| RC-018 Aura stack count | **Built** | `aura` `what = stacks`, `compare`, `stacks` | at least / fewer than N | `applications` | equality, non-stacking counts 1, absent, unknown (1) | — | as RC-003 | the most stacks of several instances | a stacking buff or debuff at the threshold |
| RC-019 Target context | **Built** | `target` | has a target; can be attacked; friendly; dead (is / is not) | `UnitExists`, `UnitCanAttack`, `UnitIsFriend`, `UnitIsDeadOrGhost`; `PLAYER_TARGET_CHANGED`, `UNIT_FLAGS`/`UNIT_FACTION` target, `UNIT_HEALTH` target (dead only) | no target never satisfies negation, unread (5, 7) | — | target dragon frame | current target only | target, clear, kill a target |
| RC-020 Mounted / movement / travel | **Extended** (mounted existing) | `player` `state = moving`, `taxi` | is / is not | `IsPlayerMoving`, `PLAYER_STARTED/STOPPED_MOVING`; `UnitOnTaxi`, `PLAYER_CONTROL_LOST/GAINED` | events, unknown (5, 7) | — | compass (moving), NPC wing (flight path) | **swimming blocked**: `IsSwimming` has no event, so it would need polling; moving flips with every step | use a short "wait before showing" with "standing still"; take a flight path |

## Builder integration

`TwichUI_Settings/pages/RemindersPlain.lua`: sentences (`KIND`), card titles, palette entries (`MORE`) under the new
categories Buffs, Supplies and Places and group (existing entries keep theirs; Well Fed stays in Other), artwork
(`CONDITION_ART`, `ICON`), and the fields of each new kind (`FIELDS`: at most three per card, each with its own `set`).
Numbers: the card offers quick choices and "Other amount..."; the editor has a box for any whole number in range. IDs:
`NeedsId` is "item" or "spell"; the editor's box takes an ID, a link, a dropped item or a spell dragged from the
spellbook, and a buff takes several IDs separated by commas. `RemindersDesigner.lua` draws them with the existing controls;
no second editor.

**Drag and drop (no lookup needed).** An item from the bags or a spell from the spellbook can be dropped on a condition
card that asks for one (`Dz.TakeDrop`, the pure rules in `Pl.Drop`), on the open editor, or anywhere in the rule panel
while an editor is open; a click with it on the cursor counts too. With an editor open the drop goes into it; otherwise
it replaces the card's ID through the same checked path as Done (into the draft; nothing is saved until Save). A buff
*adds* the spell to its list (never twice, at most 8), so a rank is one drop; every other kind replaces. The wrong kind
(a spell on an item condition), a condition with no ID, a duplicate and an unreadable answer are refused with a reason
and the thing stays on the cursor. A dropped spell's ID is `GetCursorInfo`'s fourth answer (the second is the
spellbook slot). Typing and pasting still work. **Unit-tested** (`test_reminders_library.lua`); **simulator
handler-tested** with a faked cursor (`reminders.sh conditionsDrop`, `conditionsDropHint`); **not real-client-tested**:
that a real drag from the bags and spellbook reaches these frames, and that `GetCursorInfo` answers as documented on
Forever.

## Artwork

No new paintings were made in this work (no image generator was available). Each new kind uses an existing TwichUI
painting, one per kind: NPC art (`media/npcs/`: reagent pouch, leather backpack, hammer, sealed scroll, paw, hooded trainer,
wing) and settings icons (`R.Icons`: mage, hazardAlerts, healerWatch, diagTimeline, profilesSharing, mapToolbar,
targetArt, navigation). Bespoke condition paintings would suit buffs/debuffs, resources, cooldowns and target best.

## Remaining

- RC-002 needs a probe of the talent-node API in the client before a design.
- RC-007 needs the secrecy probe above; without it, no health condition.
- Swimming (RC-020) needs an event; without one, it isn't offered.
- Weapon enchant charges (RC-006) need a way to tell "no charges" from "none left".
- A zone search over all maps (RC-013) is not built: places are chosen where you stand.
- Real-client checks: every row's last column, plus the in-game checklist in docs/reminders.md. Drag and drop: drag a
  spell from the spellbook onto a Buff card (it is added), an item from the bags onto an Item count card, and each onto
  the open editor; a wrong kind says what it wants and stays on the cursor; a drag released outside does nothing.
