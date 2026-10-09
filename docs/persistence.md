# Saved data: schema, upgrades and recovery

For anyone changing what TwichUI stores. The code is `Persist.lua`; each owner module checks its own part (see
"Who checks what"). Nothing here is verified in the game yet; see "Manual acceptance test" for what still has to be
done there.

## What is stored, and who owns it

All six variables are account-wide (declared in the `.toc`; there is no per-character variable). Per-character data
is keyed by `"Name - Realm"` inside an account-wide variable.

| Variable | Kind | Owner | Version | Holds |
|---|---|---|---|---|
| `TwichUIDB` | configuration | `Persist.lua`, `Core.lua`, each feature | `schema` (integer) | `modules` (on/off switches), `ui` (places, text choices, `qol`, `foodDrink`, `brokerMenu`), `gear` (preferences, stat weights, per-character tree choice), `shareTransport`, `whisperProbe`, `storedData` (addon-data scan notes), `setup` (see below) |
| `TwichUIDB.setup` | sharing records | `setup/Setups.lua`, `Share.lua`, `Ellesmere.lua` | covered by `schema` | `detected`/`selection` (last "find settings" result), `received` (setups friends sent), `trusted`, `recommend`, and the one-shot hand-offs `pending`, `scanNext`, `restoreNext`, `lastScan`, `eui` |
| `TwichUIShareDB` | your shareable setup | `setup/Setups.lua` | `pack.format = 2` | `pack` |
| `TwichUIBackupDB` | undo snapshots | `setup/Setups.lua` | none | one `[character]` snapshot per character that applied a setup |
| `TwichUIRestoreDB` | restore points ("Backups") | `setup/Restore.lua` | none | `points[]` |
| `TwichUIChronicleDB` | feature data (the Journey Chronicle) | `chronicle/Data.lua` | `version` (integer) | `chars["Name - Realm"]` records: entries, notes, tracking state |
| `TwichUINavigationDB` | learned data (navigation) | `nav/Data.lua` | `version` (integer, `NavData.VERSION` = 1) | `routes["from:to"]` (a flight's stops, from a flight master's map) and `times["a-b-c"]` (measured flight times), shared by every character; `chars["Name - Realm"].known` (the flight points a flight master's map has listed as that character's). Kept within 3000 routes, 1000 times, 400 flight points per character and 60 characters, oldest first. Unreadable entries are dropped one at a time (`nav-entry-dropped`, not a loss: it is learned again); a copy from a newer TwichUI is set aside like the Chronicle's (`nav-future`). Never shared, exported or backed up (its name starts with `TwichUI`) |

Kept apart on purpose: configuration (`TwichUIDB`) is small and safe to reset; sharing records and restore points are
other addons' tables kept verbatim; the Chronicle is the player's own writing. The Chronicle is never part of
sharing, setups, backups or exports (names beginning `TwichUI` are refused everywhere; a test checks it).

Profiles: **TwichUI has none.** Profiles exist only inside other addons (EllesmereUI, AceDB-style tables). When a setup
is applied, `PointProfiles` points this character's `profileKeys` at a profile that exists in the data it just
applied, falls back to `Default`, and otherwise leaves the reference empty. It never rewrites a profile.

Not stored (runtime only): the notification queue and which card owns which lane, previews and their sample data,
diagnostic traces and timers, pending transfers, acknowledgments and timeouts (`Share.incoming`/`outgoing`), frames,
callbacks, animations and event registrations. A test saves a session that used all of these and checks that no
variable holds anything but plain data, that only declared fields exist, and that none of it returns after a reload.

## Versions and upgrade paths

Two numbers, separate from the release version (`## Version:` in the `.toc`):

- `TwichUIDB.schema`, currently **1** (`Persist.SCHEMA`). A missing number means **0**: every release before schemas.
- `TwichUIChronicleDB.version`, currently **1** (`Persist.CHRONICLE_VERSION`).

The other variables carry no number. They hold other addons' tables as they were saved, and are checked for shape on
load. A change to their layout has to add a number first.

Supported upgrade: **schema 0 → 1**, for the layouts of releases 3.0.4 to 3.0.8. The tests load what each of those
releases actually wrote (`tests/fixtures/saved_v3.0.*.lua`, produced by running that release's own code for a made-up
character), not hand-written approximations. Earlier releases than 3.0.4 and anything not listed are not claimed.

Step 1 (`Persist.STEPS[1]`) does what used to run on every load:

1. `shareTransport` is derived from the old switches (`shareGroup` → Party, `shareGuild` → Guild, both → Party, else
   Direct). A valid `shareTransport` is never overwritten. The old keys stay.
2. The removed combo points display's keys are removed (`modules.comboPoints`, `comboPointsHideGame`,
   `ui.comboPoints`, `comboPointsPosition`).
3. Leftovers of earlier addon-data scans are removed (`storedData.scanMode`, top-level `svTest`).

Releases 3.0.4 and 3.0.5 also wrote `TwichUIDB.migrated = 301`, a one-time marker for a change since reversed. Nothing
reads it; it is left alone.

### How an upgrade runs

`Persist.LoadMain` runs once from `Core.lua` as soon as the saved variables are in, before any module starts:

1. Make sure the roots are tables. Look for a set-aside copy (below).
2. Empty → new install: defaults, schema written, nothing announced.
3. Stored schema higher than this build → newer data (below).
4. Lower → `Persist.Migrate` runs the steps on a **working copy**: it shares the live tables until a step takes a
   private copy with `ctx.own(key)`, so a step cannot change live data by accident. The result is validated
   (`schema` set, groups are tables, transport valid). Only then `Persist.Commit` assigns it into the live table.
5. A step that errors, or a result that fails validation, **changes nothing**: the schema is not advanced, the session
   runs on what is stored (every reader tolerates the old layout), one notice is shown, and the next load tries again.
6. `Persist.Normalize` fills what is missing and fixes what cannot be used (below). It is repeatable.

Migrations do not draw, play sounds, register game events or touch the game. Profile and setting changes at runtime
are separate from all of this and keep their combat rules.

### Adding a schema 2

Add `STEPS[2]` (it must be repeatable and must take `ctx.own(key)` before changing anything), raise `Persist.SCHEMA`,
add a fixture of schema 1 data to `tests/fixtures`, and add the cases to `tests/test_persist.lua` (upgrade from 0 and
from 1, repeat, injected failure). Document the step here. Never reuse or reorder a number.

## Defaults and validation

- **Defaults** fill only what is missing (`nil`). `false`, `0`, `""` and empty tables are values and stay. Defaults
  are scalars copied into the live table; no default table is shared with anything.
- **Switches** (`modules.*` that TwichUI defines) must be booleans. `Enabled()` treats anything but `false` as on, so a
  stray number or text would switch a feature on; it is put back to its default and counted (`module-not-boolean`).
  Switches TwichUI does not define are left untouched.
- **Groups** must be tables (`modules`, `ui`, `setup`, `gear`, `storedData`, `whisperProbe`, and `ui.qol`,
  `ui.foodDrink`, `ui.brokerMenu`). One that is not is dropped and rebuilt by its owner (`container-not-table`); its
  neighbours are untouched.
- **Values** (ranges, texts, textures, positions) are judged by the feature that reads them, every time it reads
  them (for example `FoodDrink.Get`, `MenuStyle.Get`, `Position()`), and an unusable one falls back to the default
  **without being erased**. A texture whose media pack is absent today stays chosen for when it returns. Persist does
  not duplicate those rules.
- **Unknown fields** are kept everywhere (including inside the Chronicle's `journey` and records), so a downgrade or a
  hand edit does not lose a newer version's data.
- One bad value never resets a whole table or profile.

## First run: the welcome marker

`TwichUIDB.welcome = { state = "pending" | "seen" }`, written by `Persist.Normalize`.

- A load that finds **no saved settings at all** (`next(TwichUIDB) == nil`, the same test that says `outcome = "fresh"`)
  writes `pending`. Nothing else ever does: not a missing marker, not a schema upgrade, not a failed upgrade, not a
  damaged marker, not a newer save's stand-in. Those write or leave `seen`, so an upgrade can never start onboarding.
- `modules/Welcome.lua` changes `pending` to `seen` once the dialog is really on screen. A `/reload` before that keeps
  `pending`; the dialog is tried again. Showing it by hand (`/tui about`) while `pending` also counts as seen.
- The marker is account-wide, like the rest of `TwichUIDB`: other characters, other addons' profiles, the options'
  **Defaults** button and the feature-level **Reset** buttons never touch it (it is not one of `modules`).
- **Full reset:** TwichUI has no "reset everything" command. Deleting `!!!TwichUI.lua` from `SavedVariables` (see the
  manual test) is a new installation again and shows the dialog once more. Restoring an older copy of that file brings
  its marker back with it.
- An unreadable marker is quietly `seen`, and is not counted as a loss (`Report().lost` stays 0): nothing the player
  stored is gone.

## Newer data is never touched

If `TwichUIDB.schema` or `TwichUIChronicleDB.version` is higher than this build understands, TwichUI does not read,
change or downgrade it. The client saves a variable's *global* at logout, so the stored table is **set aside**: a
stand-in with defaults is installed for the session and the original is put back on `PLAYER_LOGOUT` (a documented
synchronous event in the Forever API documentation, fired for a reload too). The stand-in also carries the original
(`heldStored`), so if the client ever saved without that event having run, the next load finds the original there and
restores it (`held-recovered`). Cost: the session starts from defaults (or an empty Chronicle) and what changes in it
is not saved; one notice says so and to update TwichUI.

The one thing this relies on that is not verifiable offline is that the client writes saved variables *after*
`PLAYER_LOGOUT`. The documentation lists the event as synchronous; the order of the write is not documented in the
UI source, and it is exactly the case to check in the game.

## Who checks what

| Where | Check | When |
|---|---|---|
| `Persist.lua` | roots, schema, upgrade, groups, switches, `shareTransport` | every load |
| `setup/Setups.lua` `NormalizeDb`/`NormalizeStores` | the shape of `setup.*`, received setups, your setup, undo snapshots, `pending`, hand-off flags | every load |
| `setup/Restore.lua` `Normalize` | restore points: id, name, date, unreadable tables | every load |
| `chronicle/Data.lua` | version, records, entries (below) | every load |
| `gear/Prefs.lua` | the groups inside `gear` | first use |
| `setup/StoredData.lua` | `storedData.found` | every load |
| every feature | its own values, on every read | at use |

Load-time checks are about **shape** (so the windows and the apply code cannot fail on it) and cost one pass over the
structure, not the contents; they do not walk the data inside received setups. Contents are checked where they come
in, and again where they are applied (next section).

## Imports, received setups and restore points: one set of rules

A table of an addon's settings can reach `ApplyOne` from a friend, a pasted backup, a restore point, a file or an
earlier save. The same rules apply at each door:

| Rule | Friend's setup | Pasted backup | Restore point | At apply time |
|---|---|---|---|---|
| Name is an identifier ≤ 128, not `TwichUI…`, not `_G`/`_ENV` (`ST.ValidName`) | on arrival | on check | when restored | yes |
| Entry is `{ owner = text, data = table }` (`ST.ValidEntry`) | on arrival | on check | when restored | yes |
| Data is plain (text/number/boolean/table), depth ≤ 64, ≤ 3,000,000 values, text ≤ 2 MB, no cycles (`ST.CheckData`) | on arrival | on check | — | yes |
| Name is not a table that holds code (`ST.SafeName`: `string`, `SlashCmdList`…) | — | preview shows "won't apply" | — | yes |
| Whole thing refused if any part fails | yes | yes | n/a | the one table is skipped and reported |
| Preview and confirm before applying | yes | importing only stores it | yes | — |

Before this pass `SafeName` accepted any existing table, so a setup naming `_G` would have passed every check; applying
it would have wiped the global environment and, at logout, every addon's saved variables. That is closed.

Nothing is executed: data is decoded with LibDeflate and LibSerialize and walked, never loaded as Lua. Exports hold
only the backup's chosen tables, never `TwichUI…` data, Chronicle entries, notes or transient state.

Isolation: a restore point, your shareable setup and the search results are separate copies (`DeepCopy` at creation).
Applying copies again. `Portable.Commit` hands the checked tables over to the stored backup and gives them up (no
24 MB second copy), so a second click imports nothing; the count and size limits are checked again at that moment.

**Export string format:** unchanged (`TUIBK1`, format 1). The `ST.ValidName` rule is the one the importer already
enforced (identifier, ≤ 128, not `TwichUI…`) plus `_G`/`_ENV`. A backup string made by an earlier version imports the
same way.

## The Chronicle

- `version` is no longer rewritten on every load; a higher one sets the whole Chronicle aside (above).
- A **note is kept whenever it has any text**. A repeated or missing id gets a fresh one, a missing title becomes
  "Note", and a missing or unreadable date stays missing (shown as "Date unknown", sorted first; nothing is invented).
- An entry of a kind this version does not know is moved **unchanged** to `rec.unreadable`, which a later version that
  knows the kind can read back. It is not shown, counted or trimmed.
- Dropped: a row that is not a table, an entry with nothing readable, and an automatic entry missing its title or
  time. Nothing the player wrote is in those.
- Unchanged and by design: text over the limits is shortened on load (notes at 240 characters, titles at 120). The
  window will not produce one; it can only happen with a hand-edited file or if a limit is lowered. **Decision for
  you:** whether notes should be exempt from shortening on load, since they are the player's own text.
- Automatic entries beyond 500 are removed oldest first, zone arrivals first; notes are never removed, and the 500th
  note makes new notes refuse (existing behaviour).
- Unknown fields on records and inside `journey` are carried over.

## Growth and retention

Nothing is pruned by this pass. Findings:

| Collection | Growth | Rule today | Player control | Proposed safeguard |
|---|---|---|---|---|
| Chronicle entries, per character | up to 500 | automatic entries go first; notes never | none | none needed |
| Chronicle records | one per character ever played; never removed | none | none | **needs approval:** a "forget this character's Chronicle" action in Saved data. It deletes the player's writing, so it must be explicit and per character |
| `rec.unreadable` (new) | only entries a newer version wrote | none | none | none until it is seen to matter |
| Restore points | unbounded when you create them; imports stop at 20 points or 32 MB in total | imports capped | delete in Backups / Saved data | a size note in Backups once the total passes a threshold; no automatic deletion |
| Undo snapshots | one per character, replaced by the next apply, kept when the character is gone | replace | delete in Saved data | list which are for characters this account no longer has |
| Received setups | one per sender | replace | delete in Saved data | none |
| Your shareable setup | one | replace | delete in Saved data | none |
| `setup.pending` | one slot, **no expiry**: a load-on-demand addon that never loads keeps it queued | cleared when done | none | **needs approval:** an expiry (it would change when a queued apply happens) |
| `setup.eui.imports`/`ids` | one entry per EllesmereUI profile imported or shared | none | none | small; leave |
| `gear.*`, `ui.*`, positions, `trusted`, `recommend` | bounded by the settings that exist, plus one entry per character/class/sender | none | settings and Defaults | none |

The game itself warns (`SAVED_VARIABLES_TOO_LARGE`, a popup from the client) when a saved file is too large; TwichUI
does not duplicate that. There is no recurring copy of saved data anywhere; restore points are made only when asked.

## Recovery and diagnostics

`/tui diagnostics` has a **Saved data** section: the stored and current schema and Chronicle version, the outcome
(new, current, upgraded, newer-and-left-alone, failed), and a count for each repair by a stable code. It never holds
setting values, setup contents, character names, notes or dumps.

| Code | Meaning | Counts as "reset or set aside" |
|---|---|---|
| `defaults-added`, `legacy-key-removed`, `schema-invalid`, `held-recovered`, `list-entry-dropped`, `pack-field-reset`, `apply-entry-rejected`, `chronicle-entry-set-aside`, `chronicle-entry-repaired`, `chronicle-trimmed`, `restore-point-repaired` | ordinary: something filled, tidied or kept | no |
| `root-not-table`, `container-not-table`, `module-not-boolean`, `received-pack-dropped`, `setup-table-dropped`, `pending-dropped`, `share-pack-dropped`, `backup-dropped`, `restore-point-dropped`, `chronicle-record-dropped`, `chronicle-entry-dropped`, `migration-failed`, `future-schema` | a stored value was reset, dropped or set aside | yes |

One login notice, only when something in the second group happened: newer data (and how to fix it), a failed upgrade,
or "reset or set aside N saved items it could not read"; always ending with where to look. It is never shown for an
ordinary upgrade or a new install.

What can and cannot be recovered:

- **Can:** upgrade older layouts; fill defaults; repair a group, a switch or an entry without touching its neighbours;
  keep a newer version's data intact; recover a set-aside copy that was saved by mistake.
- **Cannot:** anything missing or too damaged to read (a setup whose tables are not tables, a backup with nothing in
  it). Dropped received setups can be sent again; your own shareable setup can be saved again; backups and notes
  cannot be rebuilt, so they are kept whenever any of them can be used.
- **Outside TwichUI's control:** whether the client writes the files at all (a crash or kill before logout writes
  nothing, and the previous file stays), file corruption on disk, a full disk, saved files too large, and another addon
  or program changing the files. TwichUI makes no claim to be crash-proof and adds no workaround.

## Tests

`./tests/run.sh` (Lua 5.1 + luabitop). `tests/test_persist.lua` covers: a new install; complete current data; partial
data; `false`/`0`/empty values; wrong types and non-table roots; each supported older layout (5 real-writer fixtures
plus a synthetic one); repeating a load, a step and `Normalize`; an injected failing step and an unusable result with
no change to live data; newer data and its return at logout (and after a "crash"); newer Chronicle; profile keys when
applying; isolation between defaults, search, restore points, your setup and live data; imports and received
setups, valid and refused (`_G`, `TwichUI…`, too deep, cycles, code in data, no owner); damaged setups, backups and
restore points; transient state excluded and not replayed; the Chronicle's notes, ids, dates, unknown kinds and
limits; and that the diagnostics report holds codes but no contents.

These simulate the game closely enough to exercise the code paths; they are not the game. Lua here is 5.1 with a
stand-in WoW API; behaviour that depends on the client (event order, what the client writes and when) is the
manual part.

## Manual acceptance test (in the game)

Needs: the candidate package, a package of the previous release (CurseForge or `git archive v3.0.8`), and the game
closed whenever files are copied. **Never replace a file while the client is running.**

SavedVariables for TwichUI are in
`<game folder>/WTF/Account/<ACCOUNT>/SavedVariables/!!!TwichUI.lua` (the file is named for the addon folder, and
holds all six variables; the client also keeps `!!!TwichUI.lua.bak`). `python3 tools/sv_inspect.py show '!!!TwichUI'`
lists what is in it without running it (read-only; add `--redact` to share a report).

1. **Back up.** Close the game. Copy the whole `WTF` folder somewhere safe (or at least the `SavedVariables` folder and
   each character's `SavedVariables`). Keep that copy until the end.
2. **Fresh install, isolated.** With the game closed, *move* (do not delete) `!!!TwichUI.lua` and its `.bak` out of
   `SavedVariables`. Other addons' files stay. Start the game with the candidate package installed. Expect: no
   TwichUI notice in chat, and the **Welcome to TwichUI** dialog appears once a few seconds after the world loads; `/tui options` shows the defaults; `/tui diagnostics` → **Saved data** says "new, nothing
   saved before" and "stored values reset or set aside: 0". Log out normally.
3. **Configure.** Back in: switch several features on and off (include some you turn *off* that default on, such as
   Welcome Back), set a Food and Drink size and border, move the New Training, Friend Login and Welcome Back cards in
   Edit Mode, pick a Mage menu texture if a Mage, choose a sending method, change two Gear preferences, write two
   Chronicle notes. Create a **Backup** in `/tui restore` and note its name.
4. **Restore point.** Change one addon's settings (any addon you are willing to change), then restore the backup,
   accept the reload, and check the addon went back and that **Undo** is offered. Restore Undo too.
5. **Profiles.** TwichUI has none; if you use EllesmereUI, switch its profile and confirm TwichUI's settings did not
   move, and that EllesmereUI's profiles are unchanged after TwichUI applied or restored anything.
6. **Reload, then log out and in.** `/reload`, check everything from step 3 is as you left it. Then log out
   normally, quit the game, start it, and check again.
7. **Upgrade from a supported version.** Close the game. Restore the moved `!!!TwichUI.lua` from step 2's backup (or,
   better, use a copy of a save made by the *previous release*: install the previous release, configure it as in step
   3, log out, quit). Install the candidate over it. Start the game. Expect: your settings and notes are all there;
   `/tui diagnostics` shows "settings schema: stored none … upgraded at this load"; **no** notice appears in chat
   unless something was actually unreadable.
8. **Nothing resumes.** Before logging out in step 3 or 6, start `/tui diagnostics start`, trigger a preview from
   the Notifications page and leave a card queued, and open a share window with a transfer in progress (a
   `/tui share test` to yourself). After the next login: no card appears by itself, tracing is off, no transfer is
   shown as running.
9. **Diagnostics.** Open `/tui diagnostics` after steps 2, 6 and 7. Read the **Saved data** section: stored and
   current versions, outcome, and repair codes. Confirm the report contains no setting values, character names, notes
   or setup contents before sharing it.
10. **Newer data (needs a separate copy).** Close the game, make a copy of your save, and in the *copy* change the
    `["schema"] = 1,` line inside `TwichUIDB = {` to `["schema"] = 99,`. Install that copy as `!!!TwichUI.lua` with the
    candidate, and start the game. Expect: a notice that the saved settings were made by a newer TwichUI, a default session, and after a
    normal logout the file still says `["schema"] = 99` with the rest intact. This is the check for the one thing
    the tests cannot prove: that the client writes saved variables after `PLAYER_LOGOUT`.

Steps 2, 7 and 10 need a separate save (or a spare account/install); the rest can use your normal one after the backup.
Record what actually happened for each step; none of this has been run yet.
