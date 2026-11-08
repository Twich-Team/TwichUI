# Action bar glows

Your action bar buttons glow when one of them is the one to press: a buff of yours is missing (on you, or out of combat on
group members in range), a weapon buff, seal or tracking is off, a reagent or an item you chose runs low, an important
cooldown comes back, a proc can be used, or a button holds a lower rank than you know. The behaviour was modelled on the
GlowingBars addon (`../reference_addons/GlowingBars`, which carries no licence): only what it does was used, as a
specification. None of its code, tables or texts were copied.

Code: `!!!TwichUI/glows/`. Settings: `TwichUI_Settings/pages/BarGlows.lua` (the General tab) and `BarGlowsSpells.lua`
(the Spells and looks tab). Tests: `tests/test_bar_glows.lua`, `tests/test_bar_glows_settings.lua`.

It only reads and draws. It never casts, uses, targets or clicks anything, never moves an item and says nothing in chat.
Messages are small cards on screen, only for the reminders whose message is on (see "Messages").

Nothing here has been seen in the game. "Verified" means read from the Forever UI source (`../wow-ui-source`, branch
`forever`) or exercised by the offline tests and the simulator lab against stand-ins for the game.

## Files

| File | Does |
|---|---|
| `Catalog.lua` | The built-in list: each kind's spells and items per class (pure data) |
| `Config.lua` | What is stored and how it is checked; looks resolved; the per-character record |
| `Logic.lua` | What is due, from an observation and the choices (pure) |
| `State.lua` | Reads the game into that observation; a secret or missing answer is unknown |
| `Buttons.lua` | Finds Blizzard's and EllesmereUI's buttons and what each holds |
| `Draw.lua` | The glows (AnimationGroups only), faded bars |
| `Notice.lua` | The message cards, in the zone arrival card's look |
| `Controller.lua` | Events, coalescing, timing (glow time, repeat), messages and sounds, on/off |

## The kinds

| Kind | Due when | Shipped |
|---|---|---|
| Missing buff | none of the buff's names is on you (any rank; its group version counts) | Fortitude, Inner Fire, Divine Spirit, Arcane Intellect, the armors, the Mark, Omen of Clarity, the blessings and auras, Battle Shout (in combat), the aspects, Trueshot Aura, Lightning Shield. Shadow Protection, Thorns, Righteous Fury and Shield Block ship off |
| (group) | out of combat in a party or raid: members in range of the spell lack it | the group version glows instead once enough are missing (counting you, never you alone) and its reagent is carried. A paladin's blessings by class: the one you last gave each class |
| Weapon buff | a weapon hand has no temporary enchant | shaman imbues (main hand), rogue poisons (either hand, while carried); "Automatic" is the one you put on that hand last |
| Missing seal | no seal is up | in combat by default |
| Missing tracking | no spell tracking is on | profession, racial and class tracking |
| Low reagent | a spell that needs it is on your bars and you carry fewer than the limit | per class (Soul Shards 3, Symbols of Kings 20, ...) |
| Low stock | an item you added is below its limit | none until added |
| Ready cooldown | a listed cooldown comes back | per class and every racial (only those you know glow), in combat, for 3 seconds |
| Proc | the game says the spell can be cast now, or its moment came another way | Overpower, Revenge (after a block, dodge or parry for 5 s), Execute, Riposte, Counterattack, Mongoose Bite, Hammer of Wrath |
| Old rank | a button holds a spell placed directly at a lower rank than your spellbook's highest | a macro names its rank on purpose and is never counted |

Exclusive groups (an armor, an aspect, a paladin aura, a blessing on yourself, a seal, a tracking): any of them is enough,
and when none is up the one you used last glows, else the first you know that is on. Every kind and every spell can be
turned off; you can add spells and items by ID, link or drag (at most 60).

## A look

Each kind has a look and each row can have its own: art (the game's spell alert, marching ants, a soft frame, a pixel
border), color, strength (10-100%), size (70-170%), speed (25-300%), motion (moving, breathing, still), thickness (pixel
border), when (always, in combat, out of combat, enemy targeted; Alert in town for reagents and stock), glow time (until
done or 1-30 s), repeat (off or 5-60 s), message, sound (TwichUI's and LibSharedMedia's). A ready cooldown is a moment:
it glows as it comes back, not merely because a fight started ("also at the start of a fight" changes that; so does a
glow time of "until done"). "Stay quiet in towns" holds back everything while resting out of combat, except Alert in town.

## Messages

A reminder whose message is on shows a small card as it starts (and again with each repeat): an optional icon of the
spell or item beside its name in the arrival card's title face, the bronze rule, and a line saying what is wanted
("Missing buff", "Missing on Anna, Cy", "Running low: 3 left", "Weapon buff, off hand", "Cooldown ready" ...). It is
drawn with `Arrival.lua`'s `A.Typeset`, `A.Rule`, `A.PaintRule` and `A.Backdrop`, so it follows the zone arrival card's
look under Notifications > Notification appearance (fonts, size, colors, outline, opacity, accent, divider, backdrop),
redraws when that changes, and rises only without Reduced motion.

It does not go through the notification coordinator (`modules/Notify.lua`): that one gives the top of the screen to one
card at a time and holds cards back in combat, and these come in combat, several at once. The cards stack under the
arrival card's place (from 282 below the top of the screen; the arrival card ends at 270), at most three, the newest on
top; a repeat moves its own card back to the top rather than adding one.

General settings: `noticeIcon` (show the icon, on), `noticeFade` (fade out, on) and `noticeSeconds` (2-30, 5). With
fading off a card stays until its reminder is no longer due. Either way a card fades at once when its reminder is done.
"Sample message" shows a made-up card above the settings window for a few seconds.

## What the client provides

| Fact | Evidence |
|---|---|
| Spell alert art `UI-HUD-ActionBar-Proc-Loop-Flipbook` (6 x 5, 30 pictures, 1 s), drawn 1.4 times the button | `Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml`, `.lua` |
| Ants `rotationhelper_ants_flipbook` (6 x 5, 30, 1 s), 66 on a 45 button | `Blizzard_ActionBar/Shared/ActionButtonComponentTemplate.xml` |
| `C_Spell.GetSpellCooldown` -> `isActive`, `isOnGCD` never secret; `startTime`/`duration` secret when cooldowns are restricted | `SpellSharedDocumentation.lua`, `SpellDocumentation.lua` |
| `C_Spell.IsSpellUsable` (usable, insufficient power), `C_Spell.IsSpellInRange(id, unit)` (nil when invalid) | `SpellDocumentation.lua` |
| `C_UnitAuras.GetAuraDataByIndex` (secret when auras are restricted) | `UnitAuraDocumentation.lua` |
| Weapon enchants: `C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot)` (a list with `hasEnchant`), as the buff frame reads them; `C_PaperDollInfo.GetTemporaryEnchantmentInfo` as a fallback. The global `GetWeaponEnchantInfo` is a compatibility wrapper (`Blizzard_Deprecated/Shared/Deprecated_12_1_0.lua`) and is called guarded | `Blizzard_BuffFrame/BuffFrame.lua`, `ItemDocumentation.lua`, `PaperDollInfoDocumentation.lua` |
| `C_Minimap.GetNumTrackingTypes` / `GetTrackingInfo` (`type`, `active`), `MINIMAP_UPDATE_TRACKING` | `MinimapDocumentation.lua`, `Blizzard_Minimap/Mainline/Minimap.lua` |
| `C_SpellBook.GetSpellBookItemInfo` (`spellID`, `name`, `subName` "Rank n"), `IsSpellKnown` | `SpellBookDocumentation.lua` |
| EllesmereUI buttons `EABButton<first slot of its bar + i>`, slot in the `action` attribute; stance bar reuses `StanceButton` | `../reference_addons/EllesmereUIActionBars/EUI_ActionBars_Secure.lua` (`BAR_SLOT_OFFSETS`, `GetOrCreateButton`) |

Spell IDs: trained spells checked against WhatsTraining's class lists (`../reference_addons/WhatsTraining`, data only);
Sense Undead (quest-learned) against two other reference addons; talents and racials from the Classic Era spell data,
not checked against a second source. Poison and reagent item IDs checked against Manners' and RXPGuides' item tables.

**Not confirmed in the game:** that `ACTIONBAR_UPDATE_USABLE` / `SPELL_UPDATE_USABLE` fire as Overpower, Revenge or
Execute become usable; that a warrior's Overpower moment shows as a combo point (Classic's behaviour, used as a second
signal); `UNIT_COMBAT`'s words for a block, dodge or parry; that `C_SpellBook` lists every rank with a "Rank n" subtext;
that `C_Spell.IsSpellInRange` answers for party and raid units; that EllesmereUI's paging fires
`ACTIONBAR_PAGE_CHANGED`, `UPDATE_BONUS_ACTIONBAR` or `UPDATE_SHAPESHIFT_FORM` (buttons are read again only on events: a
page change that fires none of them is caught at the next bar event); the Well Fed buff for a food added as a missing
buff (give its buff ID when adding it).

## Performance

Events are gathered and looked at once, 0.05 s after the first (`glows.evaluate`); what an event made stale is read
again, the rest kept. The buttons are read again only after a bar, page, form, macro or spell change (`glows.map`). A
cooldown's end is a timer at that moment; one whose end is secret is looked at once a second until it is ready. Group
members are looked at every 2 seconds, only out of combat in a group with group buffs on; their auras are kept until
their own `UNIT_AURA`, and that event is listened for only then (`glows.group`). Glows are AnimationGroups: no OnUpdate
and no Lua per frame. A glow frame is made the first time a button glows and kept (`glows.overlays`). Gauges:
`glows.events`, `glows.overlays`, `glows.glowing`, `glows.buttons`, `glows.active` (`TwichUI_Diagnostics/Gauges.lua`).

## Saved data

`TwichUIDB.ui.barGlows` (the profile in use): the settings, `bars`, `faded`, `types`, `spells`, `added`, `weapon`; only
what differs from a default is stored. `TwichUIDB.ui.barGlowsMemory["Name - Realm"]` (`Profiles.lua` `ACCOUNT`: never in
a profile; at most 60 characters): `last[group]` and `blessings[class]`, a record of what you did. The switch
`modules.barGlows` is on by default and shared in a TwichUI setup; the choices and the record stay local
(`setup/TwichConfig.lua` `LOCAL`). Reset puts back every setting and look; what you added and the record are kept.

## In-game checks still to make

1. A mage without Arcane Intellect: its button glows on Blizzard's bar and on EllesmereUI's; casting it stops the glow.
2. In a party out of combat with two members missing it and Arcane Powder carried: Arcane Brilliance glows; in combat only your own.
3. Warrior: Overpower glows after the target dodges, Revenge after a block or dodge, Execute below 20%.
4. A cooldown (Evocation) glows for 3 s as it comes back in combat, not as a fight starts.
5. A rogue's off-hand poison wears off: the poison glows; a shaman's imbue the same.
6. Each look (spell alert, ants, soft frame, pixel border) with each motion, on square and round EllesmereUI buttons; the
   sample on the Spells and looks tab.
6b. A message card next to a real zone arrival card: same fonts and rule, no overlap, the icon's size against the title,
   the backdrop around icon and text when Notification appearance gives one; fading off keeps it until the buff is cast.
7. Faded bars put back exactly on turning the switch off, with EllesmereUI's mouseover fading on.
8. In a dungeon fight where auras or cooldowns are restricted: nothing glows on a guess and no Lua error appears.
9. A diagnostics capture in a raid out of combat: `glows.evaluate` and `glows.group` stay small.
