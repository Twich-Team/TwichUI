# Profiles

For anyone changing what TwichUI saves or adding an option. The code is `Profiles.lua` (operations, choosing at load,
telling the addon), `Persist.lua` (schema 2, names, the shape checked at load) and `settings/Profiles.lua` (the
options page). Nothing here has been checked in the game yet; see "In-game checks".

## What a profile is

A named set of TwichUI's own options. Any character on the account can use any profile. Each character remembers
its choice. Characters that choose the same profile share it on purpose: a change made on one is a change for all of
them. **Duplicate current** makes an independent copy. No profile is ever duplicated or switched without the player
asking. Exception: a character whose chosen profile is gone falls back to the profile for new characters, and says so
once at login.

Profiles hold configuration only. Map pins, the Chronicle, backups and other addons' settings are never in one.

## How it is stored

All in `TwichUIDB` (account-wide), schema 2:

| Field | Holds |
|---|---|
| `modules`, `ui`, `gear` | the profile **in use**, where every feature and the options panel already read and write |
| `profiles[name]` | every other profile: `{ modules = {}, ui = {}, gear = {} }`, a copy of its own |
| `profileState.live` | the name of the profile `modules`/`ui`/`gear` hold |
| `profileState.newCharacters` | the profile a character without a choice uses (at first "Default") |
| `profileKeys["Name - Realm"]` | each character's choice (the same key the Chronicle and Undo copies use) |

Why the profile in use stays in `modules`/`ui`/`gear`:

- The options' checkboxes are bound to `TwichUIDB.modules` itself. `Settings.RegisterAddOnSetting` keeps the table
  it is given (`Blizzard_Setting.lua`, `AddOnSettingMixin:Init`, Forever 1.60.1). So those tables stay the same for
  the whole session, and a profile change replaces what is *in* them.
- Every feature already reads `TwichUIDB.ui.<key>` when it needs it, so no reader had to change.
- The profile in use is never stored twice.
- No two saved tables are the same table, so nothing depends on how the client writes shared tables.

AceDB was considered and not used. It would have meant rewriting every settings read and every checkbox binding, a
second defaults system, and AceDB's removal of values equal to their defaults.

## Which fields belong to a profile

| Scope | Fields |
|---|---|
| **Profile** | every `modules.*` switch except `restedxpSkin` |
| **Profile** | `ui`: `arrivalHold`, `brokerMenu`, `chronicleAppearance`, `chronicleClock`, `chronicleLook`, `foodDrink`, `foodDrinkPosition`, `friendLoginChannel`, `friendLoginChime`, `friendLoginPlace`, `mageConjureText`, `mageTravelText`, `partyPins` (clicks, labels, minimap, `/way`, the pin window's place), `pinsAppearance`, `pinsBroker`, `pinsBrokerMenu`, `pinsEditorLook`, `pinsMapText`, `pinsSound`, `previewSounds`, `qol`, `refreshments` (amounts and the panel's place), `refreshmentsStyle`, `refreshmentsText`, `refreshmentsTradeGives`, `restedxpSkin`, `restedxpSkinText`, `restedxpTimerLook`, `restedxpTimerText` (the skin's look and its timer bars), `speakstoneSkin`, `speakstoneSkinStyle`, `trainingPosition`, `welcomeBackPlace`, and any `ui` key added later |
| **Profile** | `gear`: `glancePossible`, `futureLevels`, `reveal`, `strictness`, `bagStyle` |
| **Account, every profile** | `modules.restedxpSkin`: turning it on or off sets RestedXP's own chosen theme (`RXP.settings.profile.activeTheme`), and a profile change must never write another addon's settings |
| **Account, every profile** | `ui.showAdvanced`: how the options panel itself looks |
| **Account, every profile** | `ui.restedxpSkinState`: the RestedXP theme to go back to (a record of RestedXP's setting) |
| **Account, every profile** | `ui.mageSell`: the never-sell list, a protection no profile change may lift |
| **Account, every profile** | `gear.weights`, `gear.priority`, `gear.usePriority`: stat weights and priorities, already kept per class and talent tree |
| **Per character** | `gear.trees[char]`, `ui.guideWaypoint[guid]` |
| **Never in a profile** | `pins` (pins, kept state, ids, the party session), `setup.*`, `shareTransport`, `whisperProbe`, `storedData`, `welcome`, `schema`, `migrated`, `heldStored`, and the other saved variables (`TwichUIChronicleDB`, `TwichUIBackupDB`, `TwichUIShareDB`, `TwichUIRestoreDB`) |

The lists are `Profiles.ACCOUNT` and `Profiles.GEAR`. A new option in `modules` or `ui` belongs to the profile unless
it is added to `ACCOUNT`. Add it there only for a protection, a record or another addon's setting, never just for
convenience.

## Upgrading (schema 1 → 2)

`Persist.STEPS[2]` adds the three profile fields and moves nothing. The settings every character has shared until
now become the profile "Default", where they already are. No character has a choice yet, so each one uses the profile
for new characters ("Default") when it next logs in, exactly as before. The step is repeatable. It runs on Persist's
working copy and is validated before it replaces anything. A failed upgrade changes nothing, leaves no half-made
profiles, and is tried again next load; profiles are unavailable for that session.

A schema-1 save without a usable sending method gets one derived, as step 1 does, so the upgraded copy is valid.

**Downgrade.** A release that writes schema 1 (3.0.12 and earlier) finds schema 2, which is newer than it understands. As for any newer save, it
sets the data aside, runs that session on defaults with a notice, and hands the data back unchanged at logout. Nothing
is lost, but that session doesn't use your settings.

Load-time checks (`Persist.NormalizeProfiles`, every load from schema 2):

- A stored profile that is not a table is dropped (`profile-dropped`, counted as lost).
- In a stored profile, a group that is not a table, or a switch that is not a boolean, is removed and takes its
  default when the profile is used. Its neighbours are kept.
- A key that is not a usable name (a number, untrimmed text) is kept as it is and never offered.
- A stored copy with the same name as the profile in use is kept under a free name, `Name (2)` (`profile-renamed`).
- A missing `live` becomes "Default". A `newCharacters` that names nothing becomes the profile in use
  (`profile-state-repaired`).
- A choice whose key or value is not text is dropped. A choice naming a profile that is gone is left until that
  character logs in. It then uses the profile for new characters and says so once (`profile-selection-missing`).

## Choosing at load

`Profiles.Load` runs from `Core.lua` right after `Persist.LoadMain`, before any feature starts. If the character's
choice is not the profile in use, the two are swapped. This is data only, and the features read the result when they
start, as on any load, so it is safe at a load in combat too.

It needs `UnitName("player")` and `GetRealmName()` at `ADDON_LOADED`. AceDB relies on the same thing, but it is
**not verified in Forever**. If no name is given, the session starts on the profile in use and profile actions wait.
At `PLAYER_LOGIN` the choice is made like any switch, after combat if need be.

## Operations

All in `Profiles.lua`. Each returns `true, what, info` or `false, code` (`Profiles.Explain(code)` gives the words).

| Operation | Changes the options in use | In combat |
|---|---|---|
| Switch | yes | refused |
| New profile (defaults, then switch) | yes | refused |
| Duplicate current (independent copy, then switch; nothing is applied, since no option changes) | no | refused, as approved: anything that changes which profile you use waits |
| Copy settings from… (the profile in use takes a copy and keeps its name and users) | yes | refused |
| Reset current profile… | yes | refused |
| Rename (every character's choice and the new-character pointer follow) | no | allowed |
| Delete profile… | no | allowed |

The combat check is in each operation, so it applies again when a confirmation is accepted after combat started. The
options page only adds an early message.

**Names.** Spaces around a name are trimmed. A name is 1–32 characters, counted as characters (UTF-8), not bytes.
`|`, where the game's color and texture codes start, and control characters are refused. Names compare without regard
to case, so "raid" is taken when "Raid" exists; a rename may change only the case. Names are plain text everywhere:
dialogs show them as text, never as a format string.

**Delete** refuses the profile in use, the profile for new characters, and any profile a character has chosen, and
names those characters. Limitation: a character deleted from the account keeps its choice in `profileKeys`, and there
is no way yet to forget it. A profile it chose can't be deleted until a "forget this character" action exists (future
work).

**Copies.** `Extract` and `Prepare` copy with `Persist.DeepCopy`, which copies plain data only. A profile never shares
a table with another profile, the live tables or the defaults; a test walks every profile to check this. TwichUI has
no defaults metatables, so a copy is the stored values. What a profile leaves out takes its default when it is used
(`R.DEFAULT_MODULES`, `GearPrefs.DEFAULTS`; a missing `ui` key is each feature's default, as on a new installation).

## Telling the addon (one pass per change)

After the values are in place (every copy is made first, then plain assignments), `Apply` does the following:

1. **Switches**, through the options (`SettingsKit.SyncSwitches`). `NotifyUpdate` on each, in the order registered.
   A switch that changed runs its feature's own update once, an unchanged one does nothing, and one that needs a
   reload asks as it does when clicked. Those are custom fonts and sounds, quiet login, configuration sharing, the
   version check and the four EllesmereUI skins.
2. **Phases**, each feature having registered once with `Profiles.OnApply(phase, name, fn)`:
   - `look`: every MenuStyle look (Mage menus, refreshments panel, Chronicle, pin window, pin menus, RestedXP window
     and timers, SpeakStone frame), the Chronicle appearance, the RestedXP text and layout, the RestedXP timer bars,
     the SpeakStone style, and the pins' map text, data bar entry and click and label choices.
   - `layout`: Food and Drink (size, layout, look, place), the three cards' places and their Edit Mode outlines, and
     an open refreshments panel's place.
   - `views`: an open Chronicle (clock), the Mage launchers' and refreshments' data bar texts, the refreshments plan
     and Refreshment shares, and gear hints and bag marks.
3. **Options panel**: `SettingsKit.RefreshValues` has every option show its value again, and the Profiles page and
   overview update.

A part that errors is reported to the error handler and named in the result. The others are still told, and the
player is asked to reload to finish. Nothing is hidden behind a blanket `pcall`, and success is not claimed after a
partial application.

Nothing is rebuilt wholesale. No event, hook, timer or setting is registered by a profile change (a test switches
back and forth and compares). Features keep no stale table: the live tables never change identity, and the few
modules that cache one (`gear/Prefs.lua`, Setups, StoredData) cache tables that stay the same or are not in a
profile. Delayed work in each feature reads the settings when it runs.

Not moved live (by design or by the game):

- The pin window and the refreshments panel open at the new profile's place next time; an open refreshments panel
  moves at once.
- A card already on screen keeps its place until it closes.
- RestedXP's own settings, SpeakStone's and EllesmereUI's are never changed. The RestedXP skin's switch is
  account-wide for that reason.

## Options page

**Esc > Options > AddOns > TwichUI > Profiles** (`settings/Profiles.lua`, order 105, with a row on the overview):

- Current profile (switches at once)
- A line saying who else uses it, with the names in its tooltip and in the Current profile tooltip: "Changes to this
  profile also affect other characters using it. Duplicate it for an independent configuration."
- **Make a profile**: New profile…, Duplicate current…, Copy settings from…, Rename…
- **Delete or reset**: Delete profile…, Reset current profile…

These use Blizzard's controls and dialogs (`StaticPopup_Show` with an edit box, `dialog:GetEditBox()` as in Forever's
`GameDialogDefs.lua`) and are not skinned. The three dropdowns have **no default**, so the panel's Defaults button
never switches, copies into or deletes a profile. Copy and Delete only choose what to ask about, and act after the
confirmation, which names the profiles exactly. Results are one line in chat, only after the player acted.

Known limit of the game's panel: row labels are drawn when the page is shown. The shared-with line is rewritten after
every change but may show its old text until the page is drawn again. Its tooltip and the Current profile tooltip are
read when shown, so they are always current.

## Import, export, backups and restore points

None of them include TwichUI's own settings, and that is unchanged. Names beginning `TwichUI` are refused by sharing,
backups, restore points and the portable export. So no restore or import can overwrite a profile, and none can get
around the combat rule. There is no profile import or export yet; that is future work, and it should import into a new
profile, never over the one in use. The Saved Data Explorer shows profiles read-only as part of TwichUI's settings.

## Diagnostics

`/tui diagnostics` → Saved data: how many profiles, how many other characters share this character's, how many
profile changes this session, or why profiles are unavailable. It shows counts only, never profile or character
names. Repair codes are listed above. `profile-apply-failed` is counted under Start-up and lifecycle when a part
couldn't follow a change.

## Future specialization switching (not built)

A character's choice is one name in `profileKeys`. A per-tree choice could live beside it (for example
`profileTreeKeys[char][skillLine]`) and call `Profiles.Switch` out of combat on a talent change. Nothing here assumes
one choice forever, but nothing switches by itself today.

## Tests

`./tests/run.sh`; profiles are in `tests/test_profiles.lua` (plus `test_persist.lua` for schema 2). The upgrade test
loads `tests/fixtures/saved_v3.0.12.lua`, which is made by running release v3.0.12's own code for a made-up character.

Covered:
- the upgrade with every value, pin, kept pin and Chronicle note checked, a repeated step, and a reload;
- each operation, names, and independent copies, with every profile walked for shared tables;
- that account-wide, per-character, sharing, backup and Chronicle data are untouched by every operation;
- combat refusal, including a confirmation accepted after combat started;
- each part told once, the same events after switching back, and the reload question only when a reload switch
  changed;
- the options page's flows;
- two characters sharing and not sharing across sessions, a new character, a missing choice, a character named only
  at login, newer and failed data, and damaged profile data.

These simulate the client. They don't prove what the game does.

## In-game checks (none done yet)

Turn on Display Lua Errors. Test with TwichUI alone, then with EllesmereUI, RestedXP and SpeakStone. Back up `WTF`
first (see `docs/persistence.md`).

1. **Upgrade.** Install over a 3.0.12 save. Every option is as it was. The Profiles page says "Default", used only by
   this character. `/tui diagnostics` shows schema 2 and "upgraded at this load", with no notice in chat.
2. **Fresh install.** Profile "Default", the default options.
3. **New, Duplicate, Copy from, Rename, Delete, Reset.** Each does what its confirmation says. Names: trimmed, a long
   name refused, `|` refused, "default" refused while "Default" exists.
4. **Live switch.** Between two profiles that differ in Chronicle colors, Food and Drink size and place, map pin text,
   the zone card hold, a Mage menu look and gear strictness: each changes once, with no Lua error and no flicker of
   other windows. The options page shows the new values. Switch with the options panel open, close it, `/reload`:
   the new profile's values stay (the panel does not put back the values it opened with).
5. **Reload switches.** Switch to a profile where custom fonts or an EllesmereUI skin differs: one reload question;
   reload, and it applies.
6. **Reload and relog.** The choice is kept.
7. **Two characters.** A and B both on "Main". Change something on B, log in A: A has the change. Duplicate on A,
   change it, log in B: B is unaffected.
8. **New character.** It starts on the profile for new characters, also after that profile was renamed.
9. **Missing choice.** Delete a profile another character uses by editing the saved file (game closed). That
   character falls back and says so once.
10. **Combat.** Each refused action says "Profile changes are unavailable during combat." Open Copy settings from,
    enter combat, then accept: refused and nothing changes. No "action blocked" and no taint message.
11. **RestedXP.** With the skin on, switch between profiles with different window colors: the look changes, and
    RestedXP's own Look and Feel theme setting does not change. The skin's on/off switch is the same in every profile.
12. **SpeakStone.** A profile with the skin off and one with it on: switching turns the look off and on.
    SpeakStone's own settings are unchanged.
13. **Pins.** With local, party and kept pins, do every operation: all pins stay, and kept pins stay kept.
14. **Optional addons absent.** Without EllesmereUI, RestedXP, SpeakStone or a data bar: switching works with no
    error.
15. **Different UI scales.** At the smallest and largest UI scale, Food and Drink and the cards go to each profile's
    place.
16. **Defaults button.** On the Profiles page and with "all settings": no profile is switched, copied or deleted.
17. **Downgrade.** A 3.0.12 build on a schema 2 save gives the "newer TwichUI" notice, and the save is unchanged
    after logout.
18. **`UnitName` at load.** The first two lines of `/tui diagnostics` Saved data after a fresh login show profiles
    available. If they say "not available (loading)" for long, the name wasn't known at load (report it).
