# Healer Watch

An opt-in panel showing one healer's measured mana, confirmed drinking, and recent mana-related chat. Code:
`!!!TwichUI/healer/`. Settings: `TwichUI_Settings/pages/HealerWatch.lua`. Diagnostics: `!!!TwichUI/diag/HealerWatch.lua`.
Art: `tools/make_healer_watch_art.py`. Tests: `tests/test_healer_watch.lua`, `tests/test_healer_watch_settings.lua`.

It informs and nothing more. It never sends a chat or addon message, never says whether the group is ready or safe to
pull, and never casts, targets or acts. It is off until turned on, and it applies in five-player dungeons unless you
choose otherwise.

Nothing here has been seen in the game. "Verified" below means either read from the Forever UI source
(`../wow-ui-source`, branch `forever`, `Blizzard_APIDocumentationGenerated`) or exercised by the offline tests against a
stand-in for the game. The checks still to make in a real client are at the end.

## Three signals, kept apart

| Signal | Source | What it never is |
|---|---|---|
| Measured mana | `UnitPower` / `UnitPowerMax` with `Enum.PowerType.Mana` | A chat message. Unknown mana is "--", never 0%. |
| Confirmed drinking | A drink aura on the watched healer (`Drinks.lua`) | Sitting, rising mana, food, potions, or chat |
| Recent mana chat | One of your phrases, said by the watched healer | A mana reading, or confirmed drinking. "drinking" in chat is shown as said. |

Each observation has an explicit "can't tell" state: mana `unknown`, `none` (no mana pool reported) or `secret`;
drinking `hidden` or `unknown`. None of these is ever shown as a value it isn't.

## What the client provides (and restricts)

| Fact | Evidence |
|---|---|
| Assigned roles: `UnitGroupRolesAssigned(unit)` returns `"HEALER"`, `"TANK"`, `"DAMAGER"` or `"NONE"`. Forever sets them through the role poll, the unit menu's set-role and the group finder. | `UnitDocumentation.lua`; `Blizzard_FrameXML/Mainline/RolePoll.lua`; `UnitPopupSharedButtonMixins.lua` (`UnitSetRoleEnum`); `Blizzard_GroupFinder_VanillaStyle` |
| Mana by type, whatever the unit's current power: `UnitPower(unit, powerType)`, `UnitPowerMax`. Both are `SecretWhenUnitPowerRestricted`: "secret values for power types not explicitly flagged as being never secret". `C_Secrets.GetPowerTypeSecrecy` reports which applies. | `UnitDocumentation.lua`, `SecretPredicatesDocumentation.lua`, `SecretPredicateAPIDocumentation.lua` |
| Drawing a restricted value: `StatusBar:SetValue` / `SetMinMaxValues` and `FontString:SetFormattedText` accept secret arguments from addon code (`AllowedWhenTainted`). `UnitPowerPercent(unit, type, false, curve)` with a `C_CurveUtil` curve gives the percentage. | `SimpleStatusBarAPIDocumentation.lua`, `SimpleFontStringAPIDocumentation.lua`, `UnitDocumentation.lua`, `CurveUtilDocumentation.lua` |
| Auras: `C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")`, which is `SecretWhenUnitAuraRestricted` (combat, encounters). `C_Secrets.ShouldAurasBeSecret()` says when. `UNIT_AURA` carries `updateInfo`. | `UnitAuraDocumentation.lua`, `SecretPredicatesDocumentation.lua` |
| Chat: `CHAT_MSG_PARTY` and the others carry the text first and the sender's GUID twelfth. Both are `SecretInChatMessagingLockdown`: secret during encounters, challenge modes, PvP, and "when the player is on a communication-restricted map such as a dungeon or raid". `C_ChatInfo.InChatMessagingLockdown()` says when. | `ChatInfoDocumentation.lua`, `SecretPredicatesDocumentation.lua` |
| Where you are: `IsInInstance()` returns `"party"` for a five-player dungeon and `"raid"` for a raid. | `InstanceDocumentation.lua` |
| Life: `UnitIsConnected`, `UnitIsDeadOrGhost`, plus `UNIT_CONNECTION`, `UNIT_FLAGS` and `UNIT_HEALTH`. | `UnitDocumentation.lua` |

**The big limitation.** The client documents group chat as hidden from addons inside dungeons and raids. If Forever
applies that, mana messages cannot be read in the default scope at all. Such messages are counted as "unreadable" in the
diagnostics and are never matched by name instead. Mana may be restricted too. If it is, the bar and number still show,
but low and critical can't be worked out, and the diagnostics say so. Auras are hidden in combat, so drinking shows as a
faded cup then ("can't be seen").

**Reference addon, read only.** `../reference_addons/NaowhForever_QoL/Combat/HealerMana.lua` is a Forever healer-mana
display (all rights reserved, so nothing is copied). Its use of spell 430's name for drinking, of
`C_Secrets.ShouldAurasBeSecret`, and of `UnitPowerPercent` with a curve for restricted mana is evidence of what the client
does. It isn't proof.

## Who is watched

1. **Your choice.** It is kept by GUID for the session, and ended by a reload or by leaving the group (unless you chose
   yourself). Nothing is saved.
2. **Otherwise, the one member with the Healer role.** If no one, or more than one, has that role, it asks you to choose.
   Class, spells and gear are never used.
3. **Identity is the GUID; the unit token is looked up again on every roster change.** A player who moves to another
   party slot keeps their chat signal, and their mana, life and auras are read again for the new slot. A different person
   (or nobody) clears everything observed, and their timers do nothing.
4. **A chosen player who leaves.** The panel says "<name> isn't in your group", and nobody else is watched in their place.
5. **Senders are matched by GUID only.** A message with no GUID, or a secret one, is skipped. A namesake from another
   realm is listed as "Name-Realm" and is never confused with the healer.

In a raid the candidates are `raid1..raidN`; in a party, `player` and `party1..4`.

## Mana thresholds

There are four settings: low below 30% (clears at 35%) and critical below 15% (clears at 20%). A band begins strictly
below its threshold and ends only at or above its clear point, so mana hovering at a threshold doesn't flicker.

They are normalized in use, never rewritten in storage:
- critical is at most low;
- each clear point is at or above its threshold;
- the critical clear point is at most the low one.

The settings rows show "In use: ..." when an adjustment applies. Only a measured `ok` reading has a band.

## Drinking

`Drinks.lua` checks:
1. the aura's spell ID against `IDS`, seeded with 430;
2. failing that, an exact match of the aura's name with the client's own name for spell 430 (`C_Spell.GetSpellName`:
   "Drink" in English, localized elsewhere).

It is never a substring match, so "Drinking Horn" doesn't count. Limits of the name fallback: an effect with another
name (a Mage table's "Refreshment", a food-and-drink buff) isn't recognized unless its ID is registered.

### Adding a drink aura

When an aura is confirmed in the game to be a Forever drinking effect, add it to `IDS` in `healer/Drinks.lua`
(`[id] = "what it is"`), or call `R.HealerDrinks.Register(id, "what it is")` from code that loads after it. Add an
offline test beside section 5 of `tests/test_healer_watch.lua`. Don't add IDs from retail or classic lists without
checking them in the Forever client.

## Chat phrases

Phrases are literal text, never a Lua pattern. Each has a mode:
- **Whole words** (the default): no letter or digit may touch the phrase on either side, so "oom" matches "oom!" and
  "going oom" but not "boom" or "ooms".
- **Whole message**: the message equals the phrase, apart from case and the spaces and ASCII punctuation at its ends.

Case folding covers ASCII letters only; bytes of other alphabets count as letters at a word boundary.

The defaults are "oom", "out of mana" and "need mana". "mana" is offered as a labelled broad keyword and is never on by
default. Nothing understands meaning: "not oom" matches "oom".

The list holds at most 12 phrases, each up to 32 characters. Phrases are English by default, so add your group's own
words for other languages.

### Channels and timing

- **Channels:** party, raid and their leaders, and instance chat by default. /say and the watched healer's whispers to
  you are optional. Public channels and the combat log are never registered.
- **Signal:** a match makes a signal that lasts for the expiry (10 s by default) and then goes. A later message is never
  read as "ready".
- **Repeats:** the same message from the same healer within 4 s is the same signal.
- **Sound** (off by default): plays once when a signal begins while the panel is shown, at most every 15 s.
- **Excerpt:** colors, links, textures and atlases are stripped, any leftover "|" is dropped, and it's capped at 40
  characters.
- **Retention:** nothing outlives the signal.

## Showing it

**Gates, in order:** the switch, where it applies (5-player dungeons / dungeons and raids / anywhere in a group /
anywhere), and combat (show in combat, show out of combat).

**When nobody can be watched,** the panel is hidden during play unless "Keep 'Choose a healer' on screen" is on. The
settings page says it instead.

**Visibility mode:**
- **Always** (the default): shown whenever it applies.
- **Only when something needs attention:** shown when *any* ticked condition is true: low (which includes critical),
  critical, confirmed drinking, or a current chat signal. Unknown or restricted mana never counts as low. Drinking or
  chat can still show the panel when mana can't be read.

**The status line** joins every true state, most important first: a selection problem, then offline or dead (which hide
stale mana and drinking), then drinking, then the chat signal, then low or critical mana, then "Mana not readable". The
words "ready", "safe" and "pull" never appear, and a test checks every scenario for them.

**Layouts:**
- **Compact:** flask, name, number, bar and status line.
- **Minimal:** number and marks. Its status line carries only problems and mana states, since drinking and chat have
  their marks.
- **Artwork:** a larger flask with the number below and the marks beside it.

Choosing a layout writes its values, and you can change them afterwards. The flask is an emblem: its painted liquid
never moves.

## Appearance

The mana bar has its own fill texture (`barTexture`: flat, EllesmereUI's, or any LibSharedMedia status bar texture) and an
optional border (`barBorder`) whose texture, thickness, color and opacity are the shared MenuStyle look
`HW.BarLook` (`ui.healerWatchBarLook`, shared in its own group). The fill is inset by `ApplyInset`, how far the line reaches
in, and the border is drawn again after any scale change, as the repo's EllesmereUI border notes require.

Defaults:
- a muted mana blue, ivory text and warm-grey secondary text;
- a thin blackened-bronze frame and a faint inner shadow on the bar;
- no panel background and no motion.

The panel takes no clicks, with two exceptions: the handle in **Move it**, and a click on the panel while it reads "Choose a healer", which opens a quick-select menu (`MenuUtil.CreateContextMenu`: Automatic, you, and each group member). Choosing only changes who is watched. The moment a healer is watched, it is click-through again. The fade and the three-breath pulse on
entering critical are opt-in and are turned off by Notifications' Reduced motion.

## Preview, scenarios and diagnostics

- **Inline preview:** the panel's own layout code on a stage in the settings window, drawn from the scenario chosen there.
- **On screen:** the real frame at its place and size, marked "Preview", with a move handle in Move it. It replaces the
  live drawing (never two panels), ends on closing settings (unless moving), on combat, on a profile change or when
  switched off, and needs the switch on.
- **Scenarios** are built fresh by `Logic.Scenario` each time. They never touch the live selection or readings and are
  never saved.
- **The phrase tester** runs `Logic.Match` on what you type. Nothing is sent.
- **Live diagnostics** (settings, opt-in, local) show the identity and unit token, how the healer was chosen, each
  reading and its validity, the drinking evidence, the chat signal and its time left, what the game restricts now, and why
  the panel is shown or hidden.
- **The troubleshooting report** (`/tui diagnostics`) has counts and states only: no names, GUIDs, values or text.

## What is stored

`TwichUIDB.ui.healerWatch` (the profile in use) holds the settings in `Config.lua`'s `DEFAULTS`, `phrases`, and the place
(`point`, `x`, `y`). `TwichUIDB.modules.healerWatch` is the switch.

Never stored: the healer choice, readings, chat, timestamps, previews or scenarios. An unusable value reads as its default
and is left in place.

Configuration sharing (`setup/TwichConfig.lua`) carries two groups:
- **Healer Watch:** the switch and every setting except the place, which stays on this computer.
- **Healer Watch chat phrases:** merged by text, nothing removed; Undo restores the exact list.

Who is watched is never part of either.

## Performance

- **Off:** nothing registered.
- **Out of scope:** `PLAYER_ENTERING_WORLD`, `GROUP_ROSTER_UPDATE` and `PLAYER_ROLES_ASSIGNED` only.
- **Watching:** the watched unit's events via `RegisterUnitEvent`. Power events other than `"MANA"` are dropped before
  any work. `UNIT_AURA` is filtered by `updateInfo` before any look, and a look reads at most 40 auras of one unit. Roster
  and aura bursts are coalesced (0.1 s). The panel is redrawn only when a signature of what it shows changes.
- **Timers:** the chat expiry, and a one-second tick only while elapsed time is shown on a visible signal. All timers are
  token-guarded.
- **Never:** an `OnUpdate`, polling, or the combat log.

## Adding artwork

Put the sheet in `assets/` and add its name to `NAMES` in `tools/make_healer_watch_art.py` (left to right). Its shape is
checked against `TALL`. Run `python3 tools/make_healer_watch_art.py --contact-sheet /tmp/hw.png` and inspect the contact
sheet, then add a line to `HW.ART` in `healer/Config.lua`.

The tool finds the paintings by their solid parts (no fixed coordinates), clears the alpha-1..5 haze by shape, balances
their visual weight, and writes 256, 64 and 32 px uncompressed 32-bit TGAs. Runtime files are
`media/healerwatch/<name>{-large,,-small}.tga`. The source is `assets/healer-watch-source.png`, a byte-identical copy of
`../assets/healer watch.png`.

## Checks to make in the game

1. In a five-player dungeon with roles set by the group finder: the healer is found, the unit events arrive, and mana
   moves.
2. `C_Secrets.GetPowerTypeSecrecy(Enum.PowerType.Mana)`, and whether `UnitPower(party1, 0)` is secret in a dungeon, in
   combat, or not at all. If it is secret: whether the restricted bar and number draw (`D.UpdateSecret`).
3. Whether `C_ChatInfo.InChatMessagingLockdown()` is true inside a Forever dungeon, and whether party chat text and GUID
   arrive as secret there. Then whether a party message outside an instance (scope "Anywhere in a group") matches.
4. That the twelfth chat payload value is the sender's GUID for party, instance, say and whisper on Forever.
5. That a drinking healer's aura is spell 430 or another rank named "Drink". Note the IDs of other ranks and of conjured
   water, and register the confirmed ones.
6. Whether auras are hidden in combat (the faded cup) and readable again afterwards.
7. A druid healer in a form: whether `UnitPower(unit, 0)` still reports mana, or "Mana not readable" shows.
8. Roles changed mid-run, a slot reorder, a healer leaving and returning, a party converted to a raid.
9. The panel at 50% and 200% scale, each layout, a long name, and the move handle. Check that the panel never takes a
   click outside Move it.
10. The artwork at each size on the real UI, and the faded cup's legibility.

## Attention flash

Optional, off by default, one checkbox per trigger: they say something (a mana message begins), mana becomes critical
(a measured reading entering critical, never a restricted one), drinking is confirmed (an aura appears after "no" or
"can't be seen", not at the first look at a player). The flash is a wash and outline over the panel in that trigger's
color (text, critical, mana), twice, about 1.3 s in all, with at least two seconds between flashes. It is alpha animation
only (no OnUpdate), and never with Notifications' Reduced motion. It plays on the live panel only; "Try the flash" in the
settings plays it once in the on-screen preview whether or not the triggers are on. It is separate from the critical
"pulse".
