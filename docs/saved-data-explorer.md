# Saved Data Explorer

For anyone changing it or testing it. Code: `setup/Explorer.lua` (sources, tree, search, copies, the share
preview) and `setup/ExplorerWindow.lua` (the window). Nothing here has been run in the game yet; see "Manual test".

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
| Current configuration | **TwichUI settings** (`TwichUIDB`) | Account-wide. TwichUI has no profiles; a few entries are kept per character inside (by name or character id). |
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
- There is no edit, apply, restore or delete control. Clicking or double-clicking a backup only opens it.
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
