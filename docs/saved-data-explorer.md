# Saved Data Explorer

For anyone changing it or testing it. Code: `setup/Explorer.lua` (sources, tree, search, copies, the share
preview), `setup/Cleanup.lua` (advanced cleanup: policy, review, removal, recovery, candidates) and
`setup/ExplorerWindow.lua` (the window). Nothing here has been run in the game yet; see "Manual test".

Open it with `/tui saved`, Options > Configuration sharing > **Saved Data Explorer**, **Review** beside your saved
setup in `/tui share`, **Look inside** in the sharing window's Saved data list, or TwichUI's entry in Addon data
(`/tui data`), which now opens this instead of a second raw view of the same tables.

## What "saved" means here

The explorer reads the tables the game loaded from TwichUI's five saved variables at login, **as they are in memory
now**. An addon cannot read the SavedVariables file; what changed this session reaches the file when you reload or log
out. The window says so, and shows when it read the chosen source ("Read at ..."); **Refresh** reads it again. Nothing
forces a reload, a logout or a write.

| Kind | Shown as | Notes |
|---|---|---|
| Current configuration | **TwichUI settings** (`TwichUIDB`) | Account-wide. `modules`, `ui` and `gear` are the profile this character uses; `profiles` holds the others and `profileKeys` each character's choice (see `profiles.md`). A few entries are kept per character inside (by name or character id). |
| Stored snapshots | **Backups**: each restore point (`TwichUIRestoreDB.points[i]`) and each **Undo copy** (`TwichUIBackupDB[character]`) | The stored record, never the live settings. Restore points carry no version number; created/imported dates and the maker are shown when recorded. Sizes are estimates of the data, not the file. |
| Prepared outgoing data | **Outgoing share**, and **Your saved setup** (`TwichUIShareDB.pack`) | TwichUI has no share presets: Send always sends the one saved setup. The outgoing share is built on request (below) and is not saved. |
| Received data | **From ...** (`TwichUIDB.setup.received[sender]`) | A friend's setup kept on this computer. |
| Feature data | **Journey Chronicle** (`TwichUIChronicleDB`) | Personal, per character; never part of sharing, backups or exports. |
| Whole variables | `TwichUIRestoreDB`, `TwichUIBackupDB`, `TwichUIShareDB` | Everything in them, including fields nothing above lists. |

Not listed, because it is not saved: transfers in progress, acknowledgments and timers, diagnostics traces, previews,
scan captures, frames and callbacks. Other addons' saved variables are not sources (that is Addon data's job), and no
globals are scanned.

## Read-only

- Tables are walked with `next` and `rawget`; nothing calls `pairs` on them, `tostring` on a table, or compares tables
  with `==` (`rawequal`), so no metatable code runs. A test fills a table with metamethods that fail if run, and walks,
  dumps, searches and shows it.
- Functions, game objects and coroutines are shown by type ("Code, not data ... never run"); secret values as
  `<secret>`; a table the game hides as hidden.
- No defaults, normalization or repair is applied to what is shown: a missing key has no row, `false`, `0`, `""` and
  `{}` are shown as stored, and the details say a `false` or `""` is a stored value, not a missing one.
- By default there is no edit, apply, restore or delete control. Clicking or double-clicking a backup only opens it.
  Deleting exists only behind **Advanced cleanup** (below), which is off whenever the window opens.
- A test fingerprints all five variables (with `next`/`rawget`) before and after opening, expanding, searching,
  dumping, previewing and the window, and they are identical; nothing of the explorer is written to saved variables.

Keys: numbers first (in order), then text (case-insensitive), then `true`/`false`, then anything else; over 20,000
keys are shown in stored order and the tooltip says so. Paths are exact: `.name`, `["two words"]`, `["1"]` (text) vs
`[1]` (number), `[true]`, `[2.5]`. Tables are described as a list, numbered with gaps, keyed, or numbered and keyed.
Loops ("contains itself") are not opened again; a table seen twice says where it was first seen.

## The share preview matches the real send

Sending used to build its two messages inline. They are now pure functions in `setup/Share.lua`, and **sending
calls them** (behaviour unchanged; the full test suite passes):

- `SH.BuildOffer(mine, id)`: the offer message (`SendTo`).
- `SH.BuildData(mine, id, want, wantEM)`: the data message (`SendData`).
- `SH.EncodeData(payload, done, fail)`: the same packing (`EncodeBig`), cancellable, queued **behind** any transfer's
  own packing or unpacking so a preview never delays a send.
- `SH.LanePieces(id, encoded)`: the same split over data lanes (`SendLanes`).

The preview (`EX.BuildPreview`) calls those with your saved setup, every table name as the wanted list (a friend who
has none of it yet) and the Edit Mode layout if saved. Its id is fourteen zeros, the same length as a real one, so
sizes match closely; a real id is drawn only when you send. It shows the messages **before** packing, so they can be
read, and separately: the offer's packed size (plus the recipient's name, which `Send` adds as `to`), the data's packed
size, the number of lanes and the number of addon messages AceComm will send (255-byte limit, 254-byte parts).

A test sends for real to a second client, decodes both messages off the wire, and compares them field by field with
the preview (only `to` and `id` differ), and compares lanes and packed size.

Opening or refreshing the preview sends nothing, starts no transfer, sets no timer, draws no transfer id, stores
nothing, applies nothing and makes no backup (a test checks the send log, the network queue, timers, `SH.outgoing`,
`SH.incoming` and the saved variables).

**Stale:** the preview remembers which saved setup, version and date it was built from. If you save again, update the
recommended addons, or delete the setup, the window says it is stale and Refresh rebuilds it. It does not rebuild by
itself. It also lists tables ticked in Share setup but not saved (and the reverse), because Send uses the saved setup
until you press Save setup.

**Send is unchanged.** It always sends the current saved setup; there is no new confirmation. The preview cannot drift
from what Send sends because both read the same saved record through the same functions, and the record is only ever
replaced (with a new version), never edited in place.

Lifetime: the preview exists while the Outgoing share is the chosen source. It references your saved setup's tables
(no copy) and keeps only sizes, not the packed text. Choosing another source or closing the window drops it and
cancels its packing and personal-data check.

## Included and excluded (by the code's actual rules)

Shown for the preview: each addon's tables and approximate size; the EllesmereUI profile (exported by EllesmereUI
itself) and the Edit Mode layout, if saved; the number of recommended addons; the three fields that identify you; and
what is left out, with the reason taken from the same tests `SaveMine` uses (not ticked, ticked after saving, too big,
EllesmereUI's whole table). Rules that always apply: TwichUI's own data is never captured (the scan skips `TwichUI*`)
and is refused by receivers; non-plain values are dropped on save; transient state is never in a setup.

## Findings about what a share contains

Checked against the code and the preview test. None of these was changed: each is either intended or a change to the
sharing format that needs your decision.

1. **Your character's identity is sent on purpose:** `offer.from` (your name), `data.meta.source` (`Name - Realm`) and
   `data.meta.sourceName`. The receiver sees who sent it anyway; `source` is what lets their addons point this
   character at the right profile (`PointProfiles`).
2. **Other characters' names inside addon settings are sent.** A shared table goes whole, as the addon saved it.
   AceDB-style tables keep `profileKeys` for **every** character on the account (`["Alt - Realm"] = "Default"`), and
   many addons keep per-character sections. The receiver uses only `profileKeys[source]`. The explorer flags these
   in the preview ("Looks personal"), and the share view says hidden values are still sent. **Decision for you:**
   whether to trim other characters' `profileKeys` entries (and possibly `char` sections) when saving a setup. It would
   change what friends receive and what applying replaces on their side, so it was not done here.
3. **Recommended addons** carry folder names, titles, versions and download links. Intended; you choose the list.
4. **EllesmereUI profile** is EllesmereUI's own export string; the explorer shows its length, not its contents (that
   is EllesmereUI's format). EllesmereUI keeps its per-character data out of it.
5. **Party and Guild sending** deliver the same messages to everyone in the group (already explained in Sending
   options).
6. Not about Send: a **portable backup export** (`TUIBK1`) includes the restore point's `source` and `sourceName`
   (your character's name). That is existing behaviour and worth knowing before pasting one publicly.

Nothing of the Chronicle, TwichUI's settings, diagnostics, pending transfers, other backups or received setups was
found in the outgoing messages.

## Advanced cleanup

Opt-in removal of entries from TwichUI's own saved data, and suggestions for what to look at. Code:
`setup/Cleanup.lua` (all decisions) and the cleanup controls in `setup/ExplorerWindow.lua` (asking, showing,
confirming). Nothing here has been run in the game; see "Manual test".

### What it is and is not

- **Off by default and after every close.** The mode lives in memory only: opening the explorer, searching,
  copying, finding candidates or changing any setting never turns it on. Closing the window ends it (and drops
  the suggestions, picks and any open review). It is never saved.
- **Turning it on** takes the left-hand **Enable advanced cleanup...** button, a warning ("Advanced cleanup can
  remove saved data and affect settings or features. Only delete entries you understand. Suggested candidates are
  not proof that data is unused."), a tick on the acknowledgment and the confirm button. Cancel (and Escape)
  leave it off. While it is on, a rust **ADVANCED CLEANUP ENABLED** chip replaces "read-only" in the header, a rust
  line runs under the title band, and **Return to read-only** takes the left button's place.
- **Finding candidates works in read-only mode.** It only looks. Picking suggestions, deleting and Undo need the
  mode.
- **No shortcut deletes anything.** Escape cancels a dialog (and is not a confirm); no key confirms; the confirm
  button is asked again when pressed (it checks the review is finished and the acknowledgment is ticked).

### What can be removed, and how (`CL.Policy`)

Decided in one function by the saved variable and the exact path of keys, never by how a row looks. A removal is
done by the owning module's own function where there is one; the rest is a small allow-list of entries nothing
depends on. Everything else is protected and says why. Data a newer TwichUI wrote (a variable the persistence code
set aside for the session) is protected whole.

| Entry | Removal | Why it is allowed, and what is refused |
|---|---|---|
| `TwichUIRestoreDB.points[i]` (a backup) | `Restore:Delete(id)` | Refused while a restore of it is queued. Never edited inside. |
| `TwichUIBackupDB[character]` (Undo copy) | `Setups:DeleteBackup` | Refused while a queued apply for that character needs it. |
| `TwichUIShareDB.pack` (your saved setup) | `Setups:DeleteMine` | Send has nothing to send until saved again. |
| `TwichUIDB.setup.received[sender]` | `Setups:RemoveReceived` | Refused while applying it is queued. |
| `TwichUIDB.setup.trusted[sender]` | direct (one `true`) | Stops accepting from that friend automatically. |
| `TwichUIDB.setup.detected` / `selection` | `Setups:ClearSearch` (both lists, one operation) | A cache, rebuilt by searching; also holds the ticks. |
| `TwichUIDB.profiles[name]` | `Profiles.Delete` | Refused for the profile in use, the one for new characters, and any a character chose. |
| `TwichUIDB.profileKeys[character]` | `Profiles.Forget` (new) | Refused for this character. It then uses the new-character profile. |
| `TwichUIDB.pins.list[i]` (a local pin) | `Pins.RemoveLocal(id)` | Refused for a kept pin and for a pin TwichUI can't read (may be newer). |
| `TwichUIChronicleDB.chars[character]` | `Chronicle.Forget` (new) | Another character only. Names the notes that go with it. |
| `TwichUIDB.whisperProbe` | direct | A cache of one test result. |
| `TwichUIDB.migrated` | direct | A marker written by 3.0.4/3.0.5 that nothing reads. |
| `TwichUIDB.storedData.found[name]` | `StoredData.Forget` (new) | A note about another addon's variable; its data is untouched. |

Protected, with the reason shown in the details and the **Delete...** tooltip: the variables themselves, `schema`,
`welcome`, `profileState`, the containers (`profiles`, `profileKeys`, `pins`, `setup`, `storedData`), `modules`,
`ui` and `gear` (the options of the profile in use: use the settings window), `shareTransport`, `pins.nextId` and
`pins.session`, `setup.pending`, `scanNext`, `restoreNext`, `lastScan`, `eui` and `recommend`, anything inside a
backup, setup or profile (these are removed whole), this character's Chronicle record and every Chronicle entry
(the Chronicle window has their controls), unknown top-level keys (they may belong to a newer version), and the
share preview (runtime only, not saved).

Targets are paths of keys resolved with `rawget` one step at a time with their types kept (`[1]` and `["1"]`
differ). No text is ever evaluated or turned into code.

### The review and the confirmation

**Delete...** (or **Review picked (n)...**) opens a dialog showing, for every target: its dataset, the exact path
and key (personal names hidden until Reveal is on), whether it is saved or runtime-only, what it holds, how many
values and nested tables go with it ("this entry and everything under it"; "at least" when counting stopped at
the bound), which function removes it, what follows, whether it can be undone, and whether a reload is needed
(never: TwichUI reads each of these when it uses it; the change reaches the file on reload or logout). Counting
is a sliced job with progress; **Delete** stays disabled until it finishes. If any target cannot be undone, an
extra acknowledgment is required.

Just before removing, every target is checked again as a batch: resolved afresh, its policy asked again (a
profile that became the one in use is refused), and fingerprinted again (identity of the entry and its parent,
structure, every key and a sample of each text; a change detector, not a checksum: a same-length edit to a text
between its sampled bytes is the one change it can miss). If any target differs, **nothing** is removed and the
dialog says what changed and offers **Review again**. Parents and children selected together, and the two lists of
the last settings search, are removed once. After removal each result is verified (the entry is gone), so a
function that answers "yes" and removes nothing is reported as a failure, and a partial result says exactly which
entries were not removed and why.

### Recovery

One in-memory copy of the last cleanup, taken (by `Persist.DeepCopy`, sharing nothing with the original) just
before each removal, only for targets whose whole subtree was counted (not cut, nothing hidden) and within
50,000 values in total. **Undo last cleanup** (advanced mode only) puts each back where it was, and only where
nothing new has taken its place; what cannot be put back stays to try again. The copy is replaced by the next
cleanup, used up by Undo, and gone with a reload or logout. It is never written to a saved variable (a test
searches all five for a removed value). Larger targets say **CAN'T BE UNDONE** and need the extra
acknowledgment. Restore points cover only other addons' settings tables, not TwichUI's own data, so they are not
used for this.

### Candidates (what the saved data itself shows)

Three tiers, none called "safe": **Evidence-backed** (TwichUI's own code can't use it; the evidence is stated),
**Worth a look** (with why it might still matter), **For your information** (a fact, not a recommendation).
Each shows the entry, category, reason, evidence, what is not known, a date only where one is genuinely recorded
(and what that date means), and **Inspect in explorer**. Everything starts unpicked.

| Rule | Tier | Evidence |
|---|---|---|
| Backup with no table TwichUI can restore | Evidence-backed | The same check `Restore:Restore` makes ("nothing TwichUI can restore"). |
| Your saved setup with no tables and no EllesmereUI profile | Evidence-backed | Send has nothing to send (the preview's own message). |
| Undo copy holding no settings | Evidence-backed | Undo is only offered when a table is held. |
| Received setup with nothing to apply | Evidence-backed | No table passes `ValidEntry` and no EllesmereUI profile. |
| Profile choice naming a profile that is gone | Evidence-backed | Login already treats it as no choice. |
| Chronicle record identical to a new one | Evidence-backed | `Chronicle.Record` makes exactly that. |
| Direct-message check from another game build | Evidence-backed | `Group.lua` only uses a result whose build matches. |
| `migrated` marker | Evidence-backed | Nothing reads it (docs/persistence.md). |
| Profile no character uses | Worth a look | `profileKeys` checked; may be kept to switch to. |
| Scan notes for an addon the game says is not installed | Worth a look | `C_AddOns.DoesAddOnExist`; they are how leftovers are listed. |
| Last settings search | Worth a look | Rebuildable; also holds the ticks. |
| Another character's Undo copy / Chronicle record | For your information | Kept under that character's name; says nothing about use. |

### What cannot be reliably detected

- Whether another character still exists or will be played again. "Not the current character" is information
  only, never a reason.
- Whether anything is used by another addon or another version of TwichUI.
- How long ago anything was used. The saved dates are when something was made (`created`), received
  (`received`), taken, checked (`at`) or seen (`seen`), never last used, so no entry is flagged for its age and a
  missing date implies nothing. No tracking was added to pretend otherwise. If "last used" were wanted, it would
  need a bounded timestamp written when each record is read or applied; that is a separate decision.
- Anything in the options of the profile in use, map pins and kept pins, and Chronicle entries and notes: these
  are yours, so they are never suggested (a pin or note is removed only by an explicit delete, and a kept pin not
  at all).

### Performance and lifecycle (cleanup)

On demand only: nothing runs while the explorer is closed or while the mode is merely on. Counting and scanning
are sliced jobs in the explorer's runner (4 ms per frame), cancellable (closing, **Back to tree**, Cancel,
Escape), with progress shown and nothing kept after they stop. A count or fingerprint walks at most 100,000
entries (the final recheck does the same, synchronously, once); the scan lists at most 400 suggestions plus 150
facts and counts the rest. Walks use `next` and `rawget` and descend each table once to 64 levels, so loops,
shared tables and tables with metatables are safe. Suggestions are a snapshot: each is resolved again (a backup
by its id, never its position) when reviewed, and one already gone is shown as such.

## Privacy

- Hidden by default, on screen and in copies, until **Reveal personal values** is turned on (for that window only; it
  turns off when the window closes): names where TwichUI and addons store them (`source`, `sourceName`, `sender`,
  `from`, `to`; keys under `profileKeys`, `chars`, `received`, `trusted`), anything equal to this character's name,
  full name, `Name - Realm` key or id, `Name - Realm`-shaped text, character ids (`Player-...`), Battle.net tags, and
  your Chronicle notes (their text and title). These are signs, not a guarantee.
- The share view never hides data silently: it counts what is hidden and says it **is** sent.
- Copies: **Path** and **Value** are exact when revealed; **Readable** is exact when revealed, and otherwise says how
  many values it hid; **Support** is always sanitized, labelled as such, and says it is not the exact data and not
  what Send sends. Every readable copy starts with a line saying it is not an importable configuration.
- Copying goes through a selectable text box (Ctrl+C). `CopyToClipboard` is marked restricted in the Forever API
  documentation, so it is not used, and no button claims to copy.
- Nothing is printed to chat, sent or uploaded, included in `/tui diagnostics`, or saved. Received setups and Undo
  copies are named "Received setup" and "for one character" until revealed.

## Performance and lifecycle

Closed, it does nothing: the window is built on first open; there is no `OnUpdate` unless a search, a personal-data
check or the preview's packing is running (4 ms per frame for the explorer's own jobs; the packing uses the sharing
code's job runner).

- Tables open a level at a time, 200 entries per page ("Show more"); only rows on screen exist (ScrollBox).
- **Expand all** opens at most 2,000 tables (first pages) and says when it stopped. Nothing deeper than 64 levels is
  opened, searched or written.
- Search waits for typing to pause (0.3 s), runs a slice per frame, stops at 300 results or 300,000 entries and says
  which; a new search, another source or closing cancels the old one.
- Readable copies stop at 200 KB, values at 64 KB, and say so.
- Summary sizes walk the source once per read, not per redraw. Transfer progress redraws only the text around the
  tree, at most five times a second, and keeps the details box where you scrolled it.
- Closing drops the tree, the preview, searches, copied text and Reveal.
- A source deleted or replaced while open (a backup deleted, a setup saved again, a received setup replaced) is noticed
  through the functions that change it (`SaveMine`, `DeleteMine`, `RemoveReceived`, `DeleteBackup`,
  `UpdateSavedAddonList`, `ClearSearch`, `Restore.Delete`, `Restore.AddImported`, and the sharing code's change
  notices): the window reads it again, or shows that it is not there any more. Clicking anything checks first, too.
- Changes made elsewhere to TwichUI's settings are not announced; the tree shows them after Refresh.
- Nothing touches protected frames or acts in the game; it works in combat.

## Tests

`./tests/run.sh` runs `tests/test_explorer.lua` with the rest (synthetic data only). It covers: no change to any saved
variable and no metatable code run; `false`, `0`, `""`, `{}` and missing; mixed key types, their order and paths;
exact numbers; large, nested, deep, cyclic and shared tables; functions, game objects, coroutines and table keys; a
damaged record's summary; a backup showing its stored value after the live setting changed; the preview against the
decoded wire messages, lane count and size; no transfer side effects; stale previews; hiding, revealing and the support
copy; a name in a source's own path or in a shared reference; and the window: every source, the preview, Reveal and its
reset on close, a search through the box, an Undo copy, a backup deleted while shown, and the saved setup replaced
while shown.

`tests/test_cleanup.lua` covers advanced cleanup: off by default and after close; the acknowledgment and
confirmation flow (no key confirms, Escape cancels); every protected and allowed path of the policy, including
pending applies, kept and unreadable pins and set-aside data; key-typed path resolution with metatables that fail
if run; subtree removal through the owners' functions and Undo; stale reviews (replaced, changed inside, policy
changed, mode off); all-or-nothing checking, partial failure and a function that lies; the recovery bound;
overlap and one-operation removal; each candidate rule, what is not flagged (an old restorable backup, anything
in use, this character), no invented dates; sliced counting and scanning and their cancellation; the window's
review text, name hiding and result; and that nothing of it reaches a saved variable.

These are Lua 5.1 with a stand-in game API. Layout, fonts, the scroll bar tint and the copy box are not tested.

## Manual test (in the game)

Use a character with a saved setup and at least two backups. Record what happens at each step.

1. `/tui saved`. The window opens on TwichUI settings; heading, path, summary and "Read at" are shown. Nothing in chat.
2. Open several groups in the tree; open a long list and use **Show more**. Hover a row: the tooltip shows its path.
   Click entries of each type and read Details (path, type, key, value). Check a `false` and an empty text.
3. Open two backups in turn: each shows its own name, date and contents, not your current settings. Change one addon
   setting, then compare a backup's value with the live one.
4. Open **Outgoing share**. Within a second or two the packed size, lanes and message count appear; Details lists
   Included, About you, Looks personal, Not included and Sending. Compare Included with Share setup.
5. In `/tui share`, change what is ticked and **Save setup**. Back in the explorer: the preview says it is stale;
   **Refresh** rebuilds it. Tick something without saving: Details lists it under Your ticks.
6. Send to a friend (or **Test on myself**) right after reviewing; confirm it arrives as before. Opening the preview
   must not have sent anything or shown a transfer bar.
7. **Reveal personal values** on and off: names in `profileKeys`, the Undo copy's character and your Chronicle notes
   appear and hide. Close and reopen: Reveal is off again.
8. Copy: **Path**, **Value**, **Readable** and **Support** for an entry and for a whole source; Ctrl+C and paste
   outside the game. Check whether a `|` in a value pastes as `|` or `||` (unknown: the box doubles it so codes are
   shown, not used). Check the support copy has no names.
9. Search a key and a value in a large source (the Chronicle or a big backup): results appear, clicking one opens the
   tree there; **Results** goes back. Type quickly: no stutter. Search something with many matches: it says it stopped.
10. With a backup open, delete it in the sharing window's Backups: the explorer says it isn't there any more. Save the
    setup again while Your saved setup is open: the new one is shown.
11. Close and reopen the explorer, `/reload`, reopen: everything reads again; nothing was kept.
12. After all of the above, check the settings, Chronicle, backups and received setups are unchanged, and
    `/tui diagnostics` holds nothing from the explorer.
13. UI scale at its largest and smallest, and a small game window: the window fits (it scales down), text is readable,
    long values cut with "...", scroll bars work and are tinted bronze without EllesmereUI. With EllesmereUI on,
    nothing in the window changes look.
14. Open it in combat: it works, and nothing else is affected.

## Manual test: advanced cleanup (in the game)

Use a character with a saved setup, two or more backups, a second character on the account that has played, and
at least one extra profile. Record what happens at each step. Take a copy of the `WTF` folder first.

1. `/tui saved`. The header says "read-only"; **Enable advanced cleanup...** and **Find cleanup candidates** are on
   the left; there is no Delete button anywhere.
2. **Find cleanup candidates**. A list appears within a moment, grouped Evidence-backed / Worth a look / For your
   information, nothing ticked, no pick boxes. Click rows: reason, evidence, what is not known, a date only where
   one exists. **Inspect in explorer** opens the entry. Nothing in the saved data changed (Refresh, compare).
3. **Enable advanced cleanup...**: the warning appears; confirming without the tick does nothing; Escape cancels;
   with the tick, confirming turns it on. The rust chip and line stay visible, pick boxes appear, **Return to
   read-only** turns it off again and the picks go.
4. Close and reopen the explorer with it on: it is off again.
5. Choose a backup you don't need, **Delete...**: read the review (path, key, nested count, "saved data", what
   follows). Cancel. Again and confirm: it leaves Backups in `/tui share` too without a reload. **Undo last
   cleanup** puts it back (same name and date).
6. Try **Delete...** on: `ui`, `profileState`, this character's Chronicle record, a kept pin, the profile in use,
   a profile another character chose. Each is refused with a reason.
7. Delete an unused profile; check `/tui options` > Profiles no longer lists it. Undo; it is listed again.
8. Delete a local pin that isn't kept; the map redraws. Undo; it is back.
9. Review a deletion, then (before confirming) change the same thing elsewhere (rename the backup, switch the
   profile): confirming removes nothing and asks for a fresh review.
10. Pick two or three suggestions, **Review picked (n)...**: every target is listed; confirm; the result lists each.
    Check a suggestion for another character's Chronicle record names the notes that go with it.
11. `/reload`: deleted entries are still gone; **Undo** is no longer available (the copy was in memory only).
12. With UI scale at its largest and smallest, check the dialog fits, the long review scrolls, the buttons are
    visible and the chip does not overlap the Reveal toggle.
13. In combat, open the explorer and delete a backup: it works; profile and pin removals follow their own rules.
