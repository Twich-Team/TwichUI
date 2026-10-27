# Publishing and sharing layout packages

Phase 6 of the layout project (built 2026-10-27, branch `feature/layout-wizard`). It lets the person who makes a layout capture
their own settings, review what changed, decide which changes are shared by every layout and which belong to one, check the
result the way a recipient's TwichUI will, publish an unchangeable snapshot, and send it through TwichUI's existing sharing
transport. The recipient stores it, reviews who sent it and whether their game can use it, and installs it with the setup
wizard they already have. Nothing in this was run on WoW: Forever; the checks that remain are at the end.

Numbering: `implementation-status.md` called Phase 6 "Retained overrides and updates". This work is the authoring and
publishing phase the author asked for under that number, so that heading stays open (see "Phase 7 handoff").

Contents: the author's workflow; the package's envelope; what travels and how; safety limits; the recipient's workflow;
what was left out; tests; the manual send and receive checklist; the Phase 7 handoff.

## The author's workflow

`/tui layout author` opens the authoring workspace. It is not linked from the setup wizard (the wizard is for people who
install a layout) and is built only when asked for. It is in `TwichUI_LayoutWizard/` (`Author.lua`, the model with no frames;
`AuthorWindow.lua`, the window), because it needs the wizard's styling and the package source; it adds about 36 KB of Lua to
that addon, which loads on demand anyway. Closing it drops the session. Published packages are kept.

| Step | What it does | What it never does |
|---|---|---|
| 1. Start from | The package to build on: the one included with TwichUI, or one this player published earlier. The layout being edited (Classic or Compact Adventure) | |
| 2. Capture | Reads one EllesmereUI profile and one TwichUI profile, named by the author (the ones in use to start with). The kept parts are decided by `LY.Capture.Read`, the same function the offline tool `tools/layout_capture.lua` now calls | Write, switch, rename or reset any profile. Capture a feature's on/off switch, a per-character record, custom colours, spec overrides or anything the adapters do not manage. Keep anything if a character's name, GUID, link or BattleTag is found in it (counts only are kept) |
| 3. Review the changes | A structured diff against the starting package: each setting that was **changed**, **added**, or **removed** (named by the layout and absent from the profile), with its old and new value in words (a position or a word, or "N values differ" for a whole module). Each change can be left out and can be kept **in this layout only** or **shared** (promoted to the base). Under each included change the window says what each choice does to **every layout** of the package: "Compact Adventure: unchanged (it has its own value)" or "gets the new value (it uses the shared value)" | Share by default (a change starts in this layout only). Include a removal by default. Offer a setting a wizard choice sets (the accent colour). Let a layout stop naming something only the base names |
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
- **Stored, never applied.** After unpacking, TwichUI_Layouts is loaded and, a frame later, `LY.Receive` checks the envelope
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
a foreign key type, and no `loadstring`/`load` is involved. Residual risks, stated: a hostile accepted sender can send a
small, highly compressed block that expands before the size checks can run (LibDeflate has no output limit, and this is true
of setups already); the question is the control, and the block is limited to 768 KB packed. The fingerprint (Adler-32 and
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
| Text export / import of a published package | No file or clipboard access can be assumed, and a paste import would be a second way in. The immutable snapshot in the published list is what "export" means here. Decision for the author: add it through the existing large-paste capture if wanted |
| Retained overrides and updates | Still the open Phase 6 item in `implementation-status.md` (baseline, per-unit "reset to the package") |
| Editing choices, geometry or the package's own text in the workspace | The workspace moves captured settings between layers. Choices and layout rules stay what the bundled package says; a person who changes them edits the source |
| Capturing settings that sit in a module's `fields` or a wizard choice | Not capturable (`Capture.Locate`); the accent colour is shown as "set by a choice" |
| Three-way merging, silent updates, remote control, dependency installation, executable adapters | Out of scope, as asked |

## Tests

`tests/test_layout_publish.lua` (and the updated counts in `test_layout_wizard.lua`); all 122 suites pass with `tests/run.sh`.
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

## Phase 7 handoff

- The package carried by the bundled `ClassicData.lua` still points at the author's private `MyFonts` folder
  (`unitNameFontPath`). The bundled package is a developer package, so nothing breaks, but the same publish check that found it
  refuses to publish it as it is. Before release: replace it in the data, or accept the one-click substitution when publishing.
- Retained overrides and updates (baseline, "reset to the package") are still to build; a received package is an ordinary
  package for the engine, so they apply to it unchanged. The new `Store` entries give an update a place to be compared with.
- A received package with the included package's id and a higher revision installs over it as an ordinary re-install. There is
  no "update available" notice by design; the sender has to send it.
- In-game: everything in the checklist above, plus the existing Phase 2 to 5 checks. The sizes and times in the final report are
  offline Lua 5.1 figures; in-game CPU and memory are not measured.
