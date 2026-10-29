# Publishing and sharing layout packages

Built in Phase 6 (2026-10-27) and hardened in RH-1 (2026-10-28); `architecture.md` §10 is the contract. It lets the person who makes a layout capture
their own settings, review what changed, decide which changes are shared by every layout and which belong to one, check the
result the way a recipient's TwichUI will, publish an unchangeable snapshot, and send it through TwichUI's existing sharing
transport. The recipient stores it, reviews who sent it and whether their game can use it, and installs it with the setup
wizard they already have. Nothing in this was run on WoW: Forever; the checks that remain are at the end.

Contents: the author's workflow; the package's envelope; what travels and how; safety limits; the recipient's workflow;
what was left out; tests; the manual send and receive checklist; the Phase 7 handoff.

## The author's workflow

To change the layouts that ship *inside* TwichUI for everyone, see `updating-the-bundled-layout.md` (`tools/update_bundled_layout.sh`);
this workspace publishes and sends a package to named players.

`/tui layout author` opens the authoring workspace. It is not linked from the setup wizard (the wizard is for people who
install a layout) and is built only when asked for. It is in `TwichUI_LayoutWizard/` (`Author.lua`, the model with no frames;
`AuthorWindow.lua`, the window), because it needs the wizard's styling and the package source; it adds about 36 KB of Lua to
that addon, which loads on demand anyway. Closing it drops the session. Published packages are kept.

| Step | What it does | What it never does |
|---|---|---|
| 1. Start from | The package to build on: the one included with TwichUI, or one this player published earlier. The layout being edited (Classic or Compact Adventure) | |
| 2. Capture | Reads one EllesmereUI profile and one TwichUI profile, named by the author (the ones in use to start with). The kept parts are decided by `LY.Capture.Read`, the same function the offline tool `tools/layout_capture.lua` now calls | Write, switch, rename or reset any profile. Capture a feature's on/off switch, a per-character record, custom colours, spec overrides or anything the adapters do not manage. Keep anything if a character's name, GUID, link or BattleTag is found in it (counts only are kept) |
| 3. Review the changes | A table of the structured diff against the starting package (see **The review table** below): each setting that was **changed**, **added**, **removed** (named by the layout and absent from the profile), or **back at TwichUI's default** (a TwichUI setting the layout sets that the profile leaves at the default). Each change can be left out and can be kept **in this layout only** or **shared** (promoted to the base); the table says which layouts that really changes | Share by default (a change starts in this layout only). Include a removal, or a setting back at the default, by default: the author decides what players who have the layout get (**Reset to default**, package format 4: they go back to TwichUI's default unless they changed it; or **Stop managing**: they keep what they have). Offer a setting a wizard choice sets (the accent colour; tooltip placement and friendly plates are the bundled package's own). Let a layout stop naming something only the base names. Include one value of a module on its own (a module is one unit) |
| 3b. TwichUI presets | The package's helper presets as a draft of their own (`presets.md`): capture a profile's settings into a preset (its scope kept), create, duplicate, rename, describe, reorder, make default, remove (its id retired), choose what each manages; a pending edit reaches the draft only through Save to draft | Write, switch or rename a profile. Name a place, another addon's setting, anything in `TwichConfig.LOCAL`, an account-wide setting or a list. Reuse a removed option's id |
| 4. Check | Builds the draft from the included changes and checks it the way a recipient's TwichUI will: the package (`Pub.Strict`), both layouts resolved for the package's own canvas and this screen, the media it points at, the personal-data scan, the revision. A path into another addon's folder is offered TwichUI's own copy when TwichUI bundles that file (the included package points at the author's private `MyFonts` folder, so this is the first thing it finds) | Publish anything |
| 5. Release | The package id (a new id is a new package, revision 1), title, revision (higher than the starting one and than any already published), an optional label and release notes | Put the author's character name in the package |
| 6. Publish | A confirmation, then the immutable snapshot (see below), kept in the published list | Send anything, write any profile |
| 7. Send | A published package to a named player, by the route chosen in Sending options, after a confirmation that names the recipient and the route. "Test on myself" sends it to this character | Send without being asked, or to anyone but the name typed |

The draft is rebuilt from the items every time, so editing afterwards cannot change what was published. Promoting a change
to the base writes it in the base and removes this layout's own copy, so this layout takes the shared value; a layout that
has its own value for the same setting keeps it, which is exactly what the "Effects" lines say. A removal of something the
base names can only be made in the base, and the look (`root` keys) only lives in the base; the window says so rather than
offering the choice.

Files, not images: a package never contains a file. It names paths, and the recipient's game finds them. The checks classify
every path: TwichUI's own media folder (fonts, sounds and borders are checked against the lists in `modules/Media.lua`),
EllesmereUI's, the game's own, or "another addon's" (refused: it cannot be sent), or "outside the game's folders" (a drive
letter, a web address, `..`; refused).

## The review table

Step 3 is one table, not pages of blocks. `AuthorReview.lua` is its model (no frames); `AuthorReviewWindow.lua` draws it. A **change** is a
proposed publishing unit (a module, a TwichUI setting, a place, a look key); a **detail** is a leaf-level difference inside it;
**needs review** is an explainable flag; **reviewed** is the author's own acknowledgment; **blocked** is a failure of the last Check.

- **Summary and toolbar.** `8 changes · 6 included · 2 need review · 0 blocked` (plus `· N reviewed`), then "Changes stay in this draft until
  you publish." Search (Enter to apply), Status (All, Included, Excluded, Needs review, Blocked, Reviewed), Type (Added, Changed, Removed, Reset),
  Affects (a layout), Sort (Attention, Name, Change, Details, Destination), Clear filters. "Showing 8 of 38 changes. Filters are on." is shown
  whenever a filter hides anything. Needs review counts only included changes; a change left out is not "reviewed" and needs no review.
- **Columns.** Include (the box changes inclusion only), Setting (friendly name: Chat, Bags, Unit frames ...; the canonical id is in the
  tooltip and the details), Change, Details ("25 fields"), Destination (**This layout** or **Shared base**: where the change will be written;
  the details also say where it is stored now), Affects (**Classic**, **Compact**, **Both**, **None**, **Unknown**: the effective result),
  Attention (**Blocked**, **Review**, **Review again**, **Reviewed**, **Note**, **Excluded**, or a dash; a coloured left-edge marker only for
  Blocked and unreviewed Review). Clicking a row opens its details; the box and the destination button are their own controls and never
  select the row. Sharing a change that would newly change another layout asks first.
- **Order.** Default: blocked, then included changes with an unreviewed Review flag, then other included, then left out; ties by name then id.
  The order is frozen when a filter or the sort changes, after a capture, and when the author clears filters; including, leaving out,
  marking or moving a change does not reorder it. Paging keeps everything. Rows are identified by the unit id, never by position. Page sizes
  10, 15, 20; the page is clamped after any filter or capture.
- **Bulk.** "Include / Leave out N filtered changes" (or "all N changes" with no filter) acts on exactly the changes in the current order, on every
  page, never on anything hidden by a filter. Including removals or resets asks first. There is no bulk destination change and no bulk "reviewed".
- **Details** open under the table (the window is too narrow for a side pane): name, id, kind and field counts, storage and destination, a line
  per layout ("Compact Adventure: unchanged: its own value wins"), the attention reasons with evidence, and a **Setting / Before / After** table
  (8 rows a page, "Show raw paths" for the stored path, swatches for colours, file names for media with the whole path in the tooltip, text
  escaped so a pipe is never a colour code, values cut at 80 characters and the list at 400 rows with "only the first 400 are listed").
  Missing, default, false, zero and empty text read differently. A module says it is **included and replaced as a whole**: the leaf list is
  for inspection and there is no way to include one value of it.
- **Impact** is `LY.Compose` run over that unit's layers (with its parent blob) before and after the change as `A.Draft` would write it, once per
  layout, cached on the change by destination. A test checks it against `LY.Resolve` on the real draft for every layout. It describes the
  authored package; it says nothing about a recipient's own overrides (that is the update flow, `updates.md`).
- **Attention** (`RV.Flags`) has levels blocked, review, info, none; each reason has a code, a sentence, evidence and sometimes an action:
  `media-blocked` (the last Check refused a file this included change holds), `removed`, `reset`/`release`, `feature-toggled` (an `enabled`
  key flipped inside a module: matched by that exact key name, and the flag says so), `media-external` (another addon's file, before any check),
  `account-wide` (the tooltip-follows-cursor setting), `unrecognized`, `structure` (10 or more settings added or removed inside a module),
  `too-large`, `no-effect` (no layout would change), and the notes `whole-module`, `geometry`, `shared`. The number of changed values is never
  a reason: a module with 80 changed numbers is a note. Not covered, deliberately: a screen-fit warning and a different game client are global
  (Check's lines), not attributable to one row; there is no metadata for EllesmereUI module fields beyond the key name; nothing says a small
  diff is safe. Blocked is only ever a failed check and only for an included change; marking a change reviewed never clears it, and flags alone
  never block Publish. Publish's confirmation mentions how many included changes are flagged and not reviewed.
- **Reviewed** is tied to the change as proposed: the before and after values, the destination (and how a reset reaches players) and which
  layouts it affects. Any of them changing makes the mark stale ("Review again", with the reason). It lives in the session only and is gone when
  the workspace closes; it is not approval and not "verified in game".

Performance: the table is a pool of 20 rows and 8 leaf rows built once; paging and details write texts. Flags, impact and keywords are cached on
the change (flags by revision and Check report), the leaf rows only for the open change. Putting 217 changes in order took 0.2 ms offline once
cached. Scopes `layoutwizard.author.review` and `layoutwizard.author.review.detail`, gauge `layoutwizard.author.review.leaves`
(`diagnostics.md`). In game cost and memory are not measured.

In-game visual checklist: the table at the window's width with long names and a large font; the row states side by side (selected, included,
excluded, reviewed, blocked, review) read apart without colour; hover and tooltips; the details' columns with a colour, a media path and a long
text; scrolling while a row is selected; Escape with the search box focused; the amber marker only on the rows that earn it.

## The package and its envelope

Package format 3 is unchanged: `LY.Validate` is the one validator for the bundled package, a draft and a received one. What is
new is the envelope around it and a stricter reading for a package that is going to strangers (`Pub.Strict`).

```
envelope = { kind = "twichui-layout", v = 1, package = <package, format 3>, meta = {
    id, version (= package.revision), format (= package.format), baseRevision, notes, publisher, published (a time),
    client = "forever" | "other",
    variants = { { id, title } },            both layouts, by id
    requires = <package.requires>, adapters = { "ellesmereui", "twichui" },
    media = { { path, kind, source } },      the files the package points at
    ownership = { [layer] = { n, fp } },     which layer names how many settings, and a fingerprint of them
    counts = { units, variants }, hash } }   hash = fingerprint of the package's canonical text
```

**Derived, not declared.** Everything in `meta` that is a fact about the package (id, version, format, requirements,
adapters, media, ownership, counts, variants, hash) is computed again from the package by whoever reads the envelope and
compared; a difference refuses the whole publication (`meta-mismatch`). Only the author's own words (notes, label, time, client)
are taken as given, and those are checked for shape (plain text, bounded). **The sender's name is not in the envelope.**

**Stricter than a bundled package** (`Pub.Strict`, on top of `LY.Validate`): no `dev` flag; layout rules (`geometry`) present;
no opaque EllesmereUI export string (settings must be data that can be read); no `LY.REMOVE` placeholder (it does not
survive serialization); every string at most 1024 bytes, with no control characters and no game links; media paths classified
as above, at most 64. `LY.Validate`'s own bounds still apply: canonical text at most 8 MB, 50,000 values, depth 16, 256
settings per addon per layer, and every field in the adapters' allowlists.

Published packages are **immutable and deterministic**. `Pub.Build` copies the package whole (nothing is shared with the
draft), drops the developer flag, derives the metadata and checks the result. The same draft, options and time give the same
canonical text and fingerprint (a test builds it twice, once from a deep copy). `Store.Seal` packs it with the transport's own
packer; the stored entry is that packed block as printable text, and sending it sends those bytes unchanged.

## What travels, and how

The transport is `setup/Share.lua`, extended; there is no second one. A setup is: offer, reply, incoming, data lanes, done. A
layout package uses the same sequence, the same routes (Direct, Party or Guild, as chosen, never switching by itself), the same
four throttled data lanes, packing and unpacking a few frames' work at a time, the same progress and watchdogs, with these
message types of its own so a TwichUI that does not know them ignores them:

| Message | Carries |
|---|---|
| `layoutoffer` | package id, revision, fingerprint, size of the packed block, title, label, variant count (all untrusted text, bounded and plain). No sender name: the game says who sent it |
| `reply`, `incoming`, `done` | the existing messages, now also for a layout (`kind = "layout"` on the transfer) |
| lane pieces | the packed block, split as for a setup. It unpacks to `{ t = "layoutdata", env }` |

What is different from a setup, on purpose:

- **Always asked.** "Always accept from this player" does not apply: a sender trusted for setups is still asked about a layout.
  The question names the sender (the game's word), the package, the revision, the size and the label (marked as the author's),
  and says receiving only stores it. It expires after 120 s (the sender is told "declined").
- **Bounded before anything is unpacked.** An offer over `Share.LAYOUT_MAX_WIRE` (768 KB) is declined without a question; the
  announced size is bounded; the pieces are counted as they arrive and one count of pieces is enforced; the joined bytes must be
  exactly the offered size.
- **Bounded while it is unpacked** (RH-1, `Share.LAYOUT_DECODE`). The sender's encoder compresses one 32 KB slice per piece, so a
  piece may hold at most a slice (plus 1 KB) compressed and unpack to at most a slice, and all pieces to at most 8 MB; a piece
  over any of these ends the transfer ("unpacked to more than a layout package can be"), before anything is deserialized. A
  stored package is opened with the same bound. The sender's claimed size is never trusted as a bound.
- **Stored, never applied.** After unpacking, TwichUI_Layouts is loaded and, a frame later (or, in combat, once combat ends: the
  check validates a whole package in one frame), `LY.Receive` checks the envelope
  (`Pub.Check`, the same function the author's Check runs), compares it with the offer (id, revision, fingerprint, size), and
  keeps it in `TwichUIDB.layouts.received`. It is not composed, planned, imported or recorded as an install. A package that
  fails is discarded and the player is told why in plain words.
- **Damaged bytes are not an error report.** A setup's damaged data goes to the game's error handler; a layout package comes
  from another player, so damaged bytes only end the transfer.
- **The same package again** takes its own place; a different sender's copy is a separate entry.

Not built, deliberately: automatic installation or update, remote control, dependency installation, executable adapters.

## Safety limits

| Limit | Value | Where |
|---|---|---|
| Packed block | 786,432 bytes | `Share.LAYOUT_MAX_WIRE` (sender, receiver, pieces as they arrive, store) |
| Pieces | at most 4, one consistent count | `OnLane` |
| Package text | 8 MB canonical, 50,000 values, depth 16 | `LY.CANON` |
| Settings per addon per layer | 256 | `LY.MAX_UNITS` |
| Variants / choices / options | 8 / 6 / 8 | `LY.MAX_*` |
| Any string | 1,024 bytes, no control characters, no game links | `Pub.Strict` |
| Media references | 64 | `Pub.LIMITS.media` |
| Notes / label / titles | 600 bytes and 12 lines / 40 / 40 and 80 | `Pub` |
| Stored | 4 published, 3 received, 3 MB of text in all; a full store refuses, it never drops one | `Store.LIMITS` |
| Offer question | answers expire after 120 s | `handlers.layoutoffer` |

Cost, offline with plain Lua 5.1 on the 389 KB (canonical) included package, as figures to compare and not as in-game numbers:
`LY.Validate` 27 ms; building a publication 116 ms; one full check 126 ms (also what a recipient runs on arrival, in a frame
of its own after the unpacking); packing 85 ms and unpacking 33 ms, spread over frames by the transport's 12 ms job budget. The
packed block is 59 KB (79 KB as stored printable text), against the 768 KB limit. Publishing and receiving each cost one
visible single-frame pause; nothing in them runs unless the player pressed a button or accepted the question. Receiving loads
`TwichUI_Layouts` (the bundled layout data is about 1.6 MB once loaded) until the next reload. In-game CPU and memory are not measured.

Executable content: the transfer is LibSerialize data only (nothing is ever run), `LY.Canon` refuses a function, a cycle or
a foreign key type, and no `loadstring`/`load` is involved. Residual risks, stated: LibDeflate has no output limit of its own, so
a piece is checked after it unpacks; one hostile piece (at most 33 KB compressed) can still expand once, by deflate's ratio (about
1:1032, so tens of MB at worst), before it is refused, and only then is the transfer ended. That bounds the work; it is not "fully
bounded". Configuration setups on the same transport keep the unbounded unpacking (D48). The question is the control, and a
package is never applied on arrival. The fingerprint (Adler-32 and
length) detects accidents and a swapped package, not a determined forger: it is not authentication. Whether a sender is who
they say is the game's word, and TwichUI says so in the review.

## The recipient's workflow

1. The offer asks (above). Accept stores the package; Decline tells the sender.
2. `/tui layout` (the setup wizard) shows a **Layout package** section on its first step as soon as one is stored: the
   included package and each received one. Choosing a received package unpacks it and checks it again.
3. The first step's compatibility list gains **This package** (title, revision, who sent it, the author's label marked as theirs),
   **Older/Newer than yours** when it has the included package's id, **Made elsewhere** if its author was not on WoW: Forever,
   **Files it needs** (media this computer does not have is a blocker; textures and sounds can only be taken on trust) and
   the release notes. EllesmereUI's version requirement is checked as for any package.
4. Both layouts of the package are on the Layout step, with their titles. Helpers and Personalize show only the choices the
   package has; a package with none says so.
5. The review, the confirmation (which now also names the package, its revision and the sender), Apply, the reload, the check
   after it, and **Restore** are exactly the existing pipeline. The install record names the package; after a reload the wizard
   opens on the result and, for a package with another id than the included one, finds the stored package again.
6. **Remove this package** deletes only the stored copy, after a question; an install made from it and Restore are untouched.

## Left out, and why

| Not built | Why |
|---|---|
| Text import of a published package in game | A paste import would be a second way in. **Export** is built for bundling only: "Export for bundling" shows a published entry's own bytes as text to copy out (`Author.ExportText`), and the developer tool imports it (`presets.md`); nothing in game reads that text back |
| Retained overrides and updates | Built in Phase 7 (`updates.md`): a received package with a higher revision is an update that keeps the recipient's changes |
| Editing geometry, the other choices or the package's own text in the workspace | The workspace moves captured settings between layers and edits the TwichUI presets (`presets.md`). The other choices (accent, tooltip, plates, size) and the layout rules stay what the package says |
| Capturing settings that sit in a module's `fields` or a wizard choice | Not capturable (`Capture.Locate`); the accent colour is shown as "set by a choice" |
| Three-way merging, silent updates, remote control, dependency installation, executable adapters | Out of scope, as asked |

## Two ways to make a package, and comparing them

The package TwichUI ships is recaptured offline from saved files (`updating-the-bundled-layout.md`); a published package is
captured in game (above). They are different paths and may give different packages (other profiles, font substitutions, a
setting decided differently). Nothing makes them one artifact; what exists (RH-1) is a deterministic comparison:

- `Pub.Contents(pkg)`: an identity (a fingerprint) of what the package **resolves to**: every layer's units, the choices (ids,
  kinds, defaults and what each option sets), the geometry, the targets and the requirements. Not its id, revision, title, notes,
  made, source or developer flag, which don't change what an install resolves to.
- `Pub.Compare(a, b)`: whether two packages resolve the same for every layout, choice and screen (the same identity proves it:
  `LY.Resolve` is a function of exactly those parts), and if not, which part differs (a layer, the choices, the geometry) and at
  which units; the metadata differences are listed apart.
- `/tui layout compare [published|received] [n]`: a stored package against the included one. Read only (`layouts.publish.compare`).

Publishing in game as the bundled data is built: `tools/update_bundled_layout.sh --from-published` imports a published package
into the repository and checks the round trip (`presets.md`, `architecture.md` §10). The profile recapture stays the other,
separate way in, and never writes the choices.

## Tests

`tests/test_layout_review.lua` covers the review table (names, order, impact against `LY.Resolve`, values and leaves, bounds, flags and
the large-diff rule, reviewed, bulk scope, publication, the window from its builders, repeated use). A mutation pass broke three safeguards
(an override ignored, a big diff treated as risk, a mark ignoring the destination); each is caught.

`tests/test_layout_hardening.lua` (RH-1) adds: the authoring decision for a setting back at the default; comparing a published
package with the bundled one (the same, a shared change, a Compact-only change, a choice, a title only, determinism); portable
media in the bundled package. `test_layout_publish.lua` adds: a block that unpacks to 3 MB in one piece refused by size, a real
package within the bound, and a package accepted in combat whose check waits for combat to end.

`tests/test_layout_publish.lua` (and the updated counts in `test_layout_wizard.lua`), run by `tests/run.sh` (`implementation-status.md` has the latest result).
It covers: packaging and load order; capture (allowlists, per-character stripping, custom colours, switches, defaults, copies,
the personal-data scan); the diff (changed, added, removed, choice-owned) and the assignment rules; **base promotion** (the
effect lines, the draft's layers, both layouts resolved, the starting package untouched); the draft, checks, media fixes and
version rules; publishing (nothing written to any profile, a second revision leaves the first byte-identical, determinism, the
metadata); about 45 malformed, oversized, newer, executable and mismatched envelopes; the store's bounds; **two clients
through the real transport** (offer, question, delivery, confirmation, byte-for-byte storage, a trusted sender still asked,
decline, size decline, an older TwichUI ignoring it, repeated pieces, pieces last to first, a lost piece and the watchdog, pieces
for nothing, pieces over the limit, a sender's name in the payload, an offer that does not match what arrives, bad packages of six
kinds, garbage bytes, a setup payload in a layout transfer); that **nothing is applied on receipt**; that a **setup still
travels**; installing, reloading, checking and restoring a received package through the wizard; a package with no choices; the
window (build once, five reopenings add nothing, no events, Escape); and that every diagnostics id is registered. A mutation
pass broke 21 safeguards one at a time; the result is in the final report.

## Manual send and receive checklist (two game clients, WoW: Forever; none of this has been run)

1. Author: `/tui layout author`. Pick the EllesmereUI and TwichUI profiles to capture; Capture. Nothing in either profile
   changes (compare `/tui` profiles and EllesmereUI's profile list before and after).
2. Review the changes. Move one change between "This layout only" and "Shared" and read the lines for both layouts. Leave one out.
3. Check. If it names a file from another addon, use TwichUI's copy. Check again until it says ready.
4. Set the revision, label and notes. Publish; confirm. Nothing is sent. Close the workspace and reopen it: the package is still
   in the published list.
5. Send to the friend by Direct. The friend gets a question naming you, the package and revision. Decline once: you are told.
   Send again; Receive. Both of you see a chat line; the friend's profiles, settings and EllesmereUI are unchanged and nothing reloaded.
6. Send the same package again, and another package: the first replaces its copy, the second is a second entry. Fill the store
   (3 received): a fourth is refused with a reason, and nothing is dropped.
7. Friend: `/tui layout`. The first step lists the included package and the received one with the sender. Choose it, read the
   compatibility list, go through the steps, Apply, reload, and read the check after it. Switch layouts (Compact) and install again.
8. Restore: the friend's setup is back, and the stored package is still listed. Remove the stored package: the question, then it is gone.
9. Interrupt a send (log out the friend mid-transfer): the sender says it stalled and nothing is stored; sending again works.
10. Party and Guild routes: the offer is addressed to one name, and only that player is asked.
11. Combat or an instance: sending is refused with a reason (the sharing lockdown check), receiving the question still waits for you.
12. `/tui perf`: open the workspace ten times and publish and receive once; `layoutwizard.author.frames`, `layoutwizard.events`
    and the store gauges stay flat; the scopes `layouts.publish.*`, `layouts.capture` and `layouts.store.open` appear with their cost.
