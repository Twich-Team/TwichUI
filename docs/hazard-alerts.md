# Hazard alerts

An optional TwichUI feature: the game plays a sound of your choosing when an aura you listed is put on you, grows on you
or fades from you. Off until you turn it on (**TwichUI settings > Everyday > Hazard alerts**). Nothing is automated, said
in chat or drawn on screen.

## What it is, and what it cannot be

The brief for this feature was a GTFO-like system that reacts to avoidable damage. The Forever client does not allow that:

| Fact | Evidence |
| --- | --- |
| Addons cannot read combat-log payloads | `C_CombatLogSecure.GetCurrentEventInfo` is `Environment = "SecureOnly"` (`Blizzard_APIDocumentationGenerated/CombatLogSecureDocumentation.lua`). `COMBAT_LOG_EVENT_UNFILTERED` is `HasRestrictions` and documents no payload (`CombatLogDocumentation.lua`). `CombatLogGetCurrentEventInfo` only aliases the secure function (`Blizzard_DeprecatedCombatLog`). |
| The client offers aura sounds | `C_UnitAuras.AddAuraSound(trigger, UnitAuraSoundInfo)` and `RemoveAuraSound` (`UnitAuraDocumentation.lua`, `UnitConstantsDocumentation.lua`): triggers Added, ApplicationsIncreased, Removed; fields unitToken, spellID, soundFileName or soundFileID, outputChannel, throttleSeconds (0 to 5). The game plays the sound and stops it after five seconds. |
| GTFO itself works this way on Forever | `reference_addons/GTFO/GTFO.lua:122` detects the client by build; `Retail/GTFO_Retail.lua` registers aura sounds and never reads the combat log; its Forever spell lists (`Spells/GTFO_Spells_Forever.lua`, `GTFO_Fail_Forever.lua`) are empty stubs. |

So TwichUI cannot see damage, who caused it, whether it was friendly, or where you stand. Hazard alerts are therefore **aura
sounds for the spell IDs you list**, registered for the player only. A rule says "this aura happened to me", never "this hit
was avoidable".

Not possible on this client, and so not offered: damage thresholds, friendly-fire detection, minimum stacks, per-rule
priority or arbitration between sounds, per-category volume, cooldowns over five seconds, any on-screen alert tied to a real
hazard (the game gives no callback when a sound plays), ground-area detection.

## What it does

- **Switch** `modules.hazardAlerts`, default off. Importing a configuration never plays anything by itself.
- **Categories** (`hazard/Config.lua`): Urgent danger (`high`), Warning (`low`), Failed mechanic (`fail`). A category is how
  urgent a rule is and picks the sound; it says nothing about damage. Per category: on/off and a sound (TwichUI's own, any
  LibSharedMedia sound, or None). One volume channel (SFX, Master, Dialog, Ambience). Friendly fire is not offered.
- **Rules**: an enabled rule is one registration: spell ID + trigger (applied, stacks grow, fades) + category + the game's
  own cooldown (0 to 5 s), for unit `player` only. `hazard/Rules.lua` decides what is registered from plain values;
  `hazard/Alerts.lua` registers it.
- **Your rules** (Rules tab): add, edit, copy (to a free trigger, switched off), enable, test, remove. Up to 40. Spell ID must
  be a whole number of at least 1; an ID the client has no name for is accepted. The editor keeps three things apart: a rule
  being configured, the game knowing the spell (`C_Spell.GetSpellName`), and the aura actually happening to you (which cannot
  be checked).
- **Built-in rules**: the structure exists (`HR.BUILTIN`, validated by `HR.Load`) and the list is empty, see Provenance.
  Turning one off is stored by its stable id in `ui.hazardBuiltin.off`, separate from the shipped data.
- **Precedence**: an enabled custom rule replaces a built-in one with the same spell and trigger; one registration per spell
  and trigger, so an event cannot sound twice. A custom rule that cannot play (its category off or silent) hides nothing.
- **Anti-spam** is the game's: `throttleSeconds` per registration (default 2 s, 0 to 5 s) and the five-second playback cut.
  TwichUI has no queue, no global throttle and no arbitration, because it never sees an alert happen.
- **Restrictions**: registering and removing wait while any `AddOnRestrictionType` is active, then happen on
  `ADDON_RESTRICTION_STATE_CHANGED`. Whether the game actually refuses registration in those states is unverified.
- **Preview**: each category and each rule has a test that calls `PlaySoundFile` once on the chosen channel. It registers
  nothing, uses no rule, changes no cooldown, works on any class and out of combat, and plays nothing for None.
- **Standalone GTFO**: if `C_AddOns.IsAddOnLoaded("GTFO")`, the switch shows a note that both can sound for the same hazard.
  Nothing of GTFO is inspected, changed or disabled, and nothing of ours changes because of it.
- **Storage**: `ui.hazard` (categories, sounds, channel), `ui.hazardCustom` (rules), `ui.hazardBuiltin` (turned-off built-in
  ids), all per profile; the switch is in `modules`. Nothing runtime is saved. Shared in configuration sharing as the groups
  "Hazard alerts" and "Hazard alert rules" (rules merge by spell and trigger; nothing is removed; Undo restores).

## Performance

No combat-log handler, no `OnUpdate`, no timer. Once registered the game plays the sounds, so nothing of TwichUI runs when a
hazard happens. While on it listens to `ADDON_RESTRICTION_STATE_CHANGED`, and once to `PLAYER_ENTERING_WORLD` (sounds other
addons add to LibSharedMedia appear later than TwichUI loads). Off, nothing is registered or listened for. A refresh that
changes nothing makes no game call (signature compare). No measurements were taken; none are claimed.

## Provenance

- **Code**: independent. Nothing is copied from GTFO; GTFO was read for its approach (aura sounds on Forever, an empty
  Forever list) only.
- **Data**: GTFO has no licence file or notice, so under this project's rule its spell tables are not reused. Its Classic list
  (`Spells/GTFO_Spells_Classic.lua`, 20 entries; more in the Generic and Vanilla files) is written for combat-log damage events, and
  only 2 of those 20 are marked `applicationOnly` (an aura applying), so most of it cannot be expressed as aura sounds. No Forever spell IDs are shipped, because none has been confirmed on this client. Built-in rules need a
  confirmed ID, a trigger, a category and a source (`HR.Check`).
- **Sounds**: no GTFO sound is bundled or used by default. Defaults are TwichUI's own `TwichUI_Drums.mp3`,
  `TwichUI_Notification.mp3` and the existing `Single_Knell.ogg`. Note for review: `media/sounds` already holds
  `GTFO_High.ogg`, `GTFO_Low.ogg` and `GTFO_Fail.ogg` (registered in `modules/Media.lua`); their provenance is not recorded
  in `licenses/` and they were not touched or used here.

## Checks to run in the game

1. Turn on **Hazard alerts**, add a rule for a harmless aura you can apply to yourself (a buff of your own, trigger "Aura
   applied to me"), cast it: the sound should play. This also confirms ordinary (non-private) auras work and that the mp3
   defaults are accepted as `soundFileName`. If nothing plays, `/tui diagnostics` shows how many registrations the game refused.
2. Same with "Stacks grow" on a stacking buff and "Fades from me" on any buff.
3. Test each category and each rule's **Test**; set a category to None; mute the chosen channel and confirm it goes silent.
4. Turn the switch off: casting the same aura should be silent.
5. Change a sound, a rule or the channel in combat: it should apply after combat (Troubleshooting shows "waiting").
6. Check whether registering is refused inside a dungeon, an encounter, a battleground or a restricted map.
7. With standalone GTFO loaded, confirm the notice appears and nothing of GTFO changed.
8. Switch profiles and import a configuration with rules: the rules follow, and nothing plays until the switch is on.
9. Confirm a spell ID the client does not know is saved and shows "no name yet", and that a bad ID is refused.
10. `/reload` with the switch on: the sounds are registered again once the world loads.

## Tests

`tests/test_hazard.lua` (settings, rule validation and bounds, resolution and precedence, registration with a fake
`C_UnitAuras`, refusals, a missing API, restrictions, the preview, profiles, GTFO, sharing and Undo, bounded state) and
`tests/test_hazard_settings.lua` (the page, the Rules tab, the notice, Reset). A fake game stands in, so they check our logic
and not the game.
