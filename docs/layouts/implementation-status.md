# Layout packages and installer: implementation status

Branch `feature/layout-wizard`. `architecture.md` is the one current contract; the evidence is in `adapter-capabilities.md`;
how it got here (the Phase 1 contract, its revisions, every phase's record and checklist) is in `history.md`. Update this file
when something is built, checked or decided.

## Status

| Phase | State | Date |
|---|---|---|
| 1. Audit and contract | Done: documents only | 2026-10-26 |
| 2. Engine and safe application pipeline | Offline-tested | 2026-10-26 |
| 3. Classic Adventure and the screen-layout resolver | Offline-tested | 2026-10-26 |
| 4. Wizard, preview and install lifecycle UI | Offline-tested | 2026-10-26 |
| 5. Compact Adventure and richer previews | Offline-tested | 2026-10-26 |
| 6. Authoring and publishing | Offline-tested | 2026-10-27 |
| 7. Retained overrides and updates | Offline-tested | 2026-10-27 |
| **RH-1. Release hardening (correctness)** | Offline-tested (record below) | 2026-10-28 |
| Editable TwichUI presets and bundling a published package | Offline-tested (record below) | 2026-10-28 |
| First-install setup (the wizard as TwichUI's first-run experience, EllesmereUI coordination, the dimming) | Offline-tested (`docs/onboarding.md`) | 2026-10-29 |
| RH-2. In-game validation on WoW: Forever, packaged artifact | **Not started** (checklist below) | |

**Nothing in this project has been run on WoW: Forever.** (The Phase 2 developer package was once applied, verified and restored
on Retail: a check of TwichUI's side on another client, not an in-game check here.) The package stays `dev = true`, and the
production release is blocked, until RH-2 is done.

## What is where

| | Offline-tested (built, covered by `./tests/run.sh`) | In-game (built, not checked on Forever) | Unsupported (by design, reason in `architecture.md` §1) | Deferred |
|---|---|---|---|---|
| Install, verify, restore | every path, failures and partial steps | everything (import, reload, `spec_locked`, picker, account-wide profile) | | whole-`EllesmereUIDB` restore point (D3) |
| Updates | three-way merge, preservation, reset, ownership, groups, whole-addon, switching, resume, Undo, Finish | runtime-written blob keys, Unlock Mode link behaviour | merging inside a blob, carrying blobs across EllesmereUI vintages | more than one level of Undo |
| Screen and preview | components, pieces (sample sizes), final plan, scale guidance | visual acceptance at every resolution and scale | Edit Mode (objectives), UI scale changes | placing the battle res timer and other unplaced positions (D32), Compact pet/stance (D44) |
| Publishing and transport | envelope, store, two-client transport, bounds, combat wait | two real clients | text export/import (D36) | the same unpack bound for setups (D48) |
| Bundled package | portable media (release-gated), capture decisions, comparison with a published package, importing a published package (round trip, determinism, refusals) | the recaptured data on Forever's EllesmereUI | | |
| TwichUI presets | format 6, the authoring editor, the wizard's cards and review, switching, removed options, Undo/Restore | the editor's layout at real sizes, the Export window's copy, a real install with an editable preset | lists, positions, account-wide and `LOCAL` settings in a preset | editing the other wizard questions in game |

## RH-1: release hardening (2026-10-28)

A focused correctness pass over preservation, reset, the transaction policy, preview and fit, media, the build script, publishing
paths and the transport, made after a documentation review listed possible gaps. Each finding was checked against the code first.

### Findings

| # | Finding | Class | Evidence | Action |
|---|---|---|---|---|
| A1 | The allowlisted minimap fields inside the bundled blob were left out of the blob's fingerprint and never tracked: a recipient's change was invisible and replaced on every update | Confirmed defect | `AdapterEllesmere.lua` `Excluded`/`UnitsOf`; the bundled minimap blob holds `coordsMode`/`coordsPosition`; test A1 failed | Fields the payload holds are units (tracked, carried, verified by value); an older baseline without them reads "can't tell", not "newly managed" |
| A2 | A sub-unit the package stopped naming was released but not carried: a replaced parent blob took it away while the review said "Left as it is" | Confirmed defect | test A2 failed | Released units are carried into the payload (not on a layout switch for a value the old layout set and the player didn't change) |
| A3 | An owned position that joined the atomic layout group could be overruled by the group's "use the layout's" | Confirmed defect | test A3 failed | The group stays the player's while it holds an owned member; the review says so and disables "Use the layout's (all)" |
| A4 | An owned unit TwichUI couldn't read lost its ownership mark | Confirmed defect | test A4 failed | Kept as owned, carried as it is, never compared |
| A5 | No way to reset a managed setting; recapture dropped settings put back to default (recipients kept the old value); in-game authoring pinned the default value without asking | Confirmed gap | `layout_capture.lua`, `Author.lua` `toDefault` | Package format 4 `reset`; authoring and the capture tool ask (reset, stop managing, leave out / keep) |
| A6 | "Manage again" and "Reapply recommended" | Already handled | `Merge.lua` OFFER/DEFAULT; `test_layout_update.lua` §8 | Documented as distinct (`updates.md`) |
| B1 | A record left `applying` with one step done verified to `verified`, committed a baseline and moved management | Confirmed defect (latent: only the engine API reaches it) | `Engine.lua` `DoVerify`; test B1 failed | Unsettled records stay `partial`; no commit, no management change |
| B2 | An update could start from a half-done Restore or Undo | Confirmed defect | `DoPlan`; test B2 failed | Blocked (`restore-unfinished`, `undo-unfinished`) |
| B3 | An Undo stopped after the rename could never be retried (`backup-missing`) | Confirmed defect | `A.PlanUndo`; test B3 failed | Progress recorded (`renamed`); a retry only switches |
| B4 | A finished setup whose last check didn't match showed as "Installed and managed" | Confirmed defect | `Manage`; test B4 failed | The management record keeps the check's result; the wizard says "not verified" |
| B5 | Stop managing had no character guard (`TwichUIDB` is account-wide) | Confirmed defect | `LY.Detach`; test B5 failed | Refused for another character's readable record |
| B6 | A second update silently replaced the copy kept by the first (one Undo level lost) | Confirmed defect (disclosure) | `A.Apply` stash | Review note and confirmation line |
| B7 | Collision with an unrelated `(previous)` profile; a missing copy | Already handled (untested) | `A.Plan` `backup-taken`, `A.PlanUndo` `backup-missing` | Tests added |
| C1 | Review's fit and preview were the recommended layout's even when the update keeps the player's placements | Confirmed defect | `Model.Review` `out.fit` from `plan.geometry` | `plan.final` (final rects, kept pieces, whole-addon keep); Review checks and draws it; the layout step keeps the recommended preview |
| D1 | The objective tracker (never applied) counted toward "fits" | Confirmed defect | `Geometry.Resolve` | Illustrative only, said so |
| D2 | Pieces outside their box weren't checked: Compact's pet frame and stance bar reach over Chat at 1920 × 1080 / 0.64 (the default stand-in screen), pet pieces off screen at 1680 × 1050, while the wizard said "Everything fits" | Confirmed defect | probe and test D | `LY.Fit`; "Fits, but some pieces may overlap"; the placement itself is the author's decision (D44) |
| D3 | The battle resurrection timer is carried at the author's centre offsets and never mentioned | Confirmed gap | `centerX/centerY` storage | Named as not placed; outside fit claims |
| D4 | "UI scale" on the welcome step showed the effective scale (1.20 for the author's 0.64) | Confirmed defect | `Model.ScreenText` | `768 / UIParent height`; scale guidance added |
| D5 | Compact's class bars inside the strip (D31) | Needs the author's decision | not established by the author's profile | Unchanged; D31 stays open |
| M1 | The bundled package pointed at the author's private `MyFonts` folder; portability was enforced for published and received packages only | Confirmed defect | `ClassicData.lua` `unitNameFontPath` | TwichUI's own `AlegreyaSansSC-Bold.ttf` (same file name and registered name `Alegreya Sans SC Bold`; not byte-compared: the MyFonts copy isn't on this machine, D47); a test the release workflow runs refuses foreign media in the bundled package |
| M2 | `update_bundled_layout.sh`: an unresolved font only warned; a Python failure under `set -e` exited without restoring; `--no-tests` reported plain success | Confirmed defects | the script | Two kinds of stop (generate: restore; check: keep for a look, save the files from before, NOT READY, exit 1); `tools/check_bundled_layout.lua`; source reported; "not tested" said |
| P1 | The in-game and bundled publishing paths may produce different packages | Confirmed limitation | two code paths | `Pub.Contents`/`Pub.Compare`, `/tui layout compare`; a unified workflow is deferred |
| V1 | Chat and wizard said "every managed value reads back" for presence-only parts | Confirmed defect (wording) | `LY.Tell`, `Model.Result` | By value and presence said apart everywhere |
| T1 | Unpacking a layout package had no output bound; its check ran in combat | Confirmed risk | `Share.lua` `DecodeBig` | Per-piece and total unpack bounds for layouts and stored packages; the check waits for combat to end. Residual: one piece can expand once before it is refused |
| X1 | The repository's `.git` has 38 empty object files from 2026-10-27 18:15; `HEAD` and the remote-tracking branch point at one | Environment, not code | `git fsck` | Not touched; listed as a release blocker |

### Policies (the contract is `architecture.md` §2, §6, §7)

- **Reset, ownership, release**: §2's table and `updates.md` "Preservation".
- **Partial commit and recovery**: §6, items 3 to 10, and what persistence can and can't promise.
- **Preview and fit**: §5; `wizard.md` "Preview and fit".

### Checks run

Offline Lua 5.1 and Python, `./tests/run.sh`: 125 suites passed, 0 failed (two new: `test_layout_hardening.lua`,
`test_layout_tools.lua`). New tests failing without their fix were confirmed for A1–A4, B1–B5, D2 (the Compact overlap) and M1;
the mutation pass is recorded in the final report of the pass. Expectations changed in older tests, each for a stated contract
change: package format 4 (`test_layouts.lua`, `test_layout_publish.lua`), minimap fields read back by value (`test_layouts.lua`),
the verification wording (`test_layouts.lua`, `test_layout_wizard.lua`), and "Everything fits" no longer claimed where Compact's
pieces overlap Chat (`test_layout_wizard.lua`). `luacheck` (globals off): no new warnings in the files changed.

### Diagnostics

New scope `layouts.publish.compare` (`DX.OPS`, `docs/diagnostics.md`). Everything else added runs inside existing scopes: the
piece check and the final plan inside `layouts.plan`, the field checks inside `layouts.verify`, the unpack bound inside the
transport's existing job, the receipt check inside `layouts.publish.receive`. No new gauges: nothing new is kept between calls
except the wizard's per-session scale-guidance cache (a few entries, dropped with the session).

## Tooltip placement and friendly player nameplates (2026-10-28)

Two personal choices on the wizard's Personalize step (`wizard.md`, "Tooltip placement and friendly player nameplates"), package
**format 5**, revision 4. Offline-tested: `tests/test_layout_tooltip.lua` (new, 12 sections), with changed expectations in
`test_layouts.lua`, `test_layout_publish.lua`, `test_layout_hardening.lua`, `test_layout_geometry.lua` (format 5; the tooltip attach is
not a position in a blob) and `test_layout_wizard.lua` (the game-default tooltip is now the fallback for a package without the choice).
`./tests/run.sh`: 126 suites passed, 0 failed.

| What | State |
|---|---|
| The two choices, their ids, defaults and stable wording | offline-tested |
| `tooltipAnchorCursor` written alone, verified, snapshotted, undone, restored (absent stays absent; a flag the player changed since is left) | offline-tested; **in game**: that EllesmereUI reads it at load as the source says |
| `tooltipFixedPos` placed with the damage meter, written into the install's own profile, carried through updates | offline-tested; **in game**: the place on real screens, and that Unlock Mode keeps it |
| Friendly-plate switches by value; nothing else of the nameplate blob differs from the layout's | offline-tested; **in game**: that EllesmereUI really lets go, and what the client's friendly plates look like afterwards |
| A choice added after a setup: starts from the game, keeps the player's value until they pick | offline-tested |
| Preview: layout place, follow-the-pointer over the miniature only, friendly-plate sample, inert overlay | offline-tested; **in game**: the pointer maths on real frames and scales |

Also fixed on the way: a kept `false` in an EllesmereUI field showed as the layout's value in the plan's row (an `and/or` that dropped a
`false`; not reachable before, when every field was a word).

Unresolved, for the author: **Standard blue** turns EllesmereUI's friendly player nameplates off (as asked), which hands them to
Blizzard's own nameplates. EllesmereUI's own switch also resets three client CVars to Blizzard's defaults when flipped in its window; at
load it only stops writing them, and the adapter writes no CVars, so the plates keep EllesmereUI's last name-only and class-colour
settings until the player changes them in Esc > Options > Nameplates (said on the page, the review and the sample). Resetting those three
CVars from the adapter (with their own snapshot, Undo and Restore) is a possible follow-up. An older baseline reads the nameplate blob as
updated once (its fingerprint leaves the two switches out now). Diagnostics: scope and gauge `layoutwizard.preview.follow`; the adapter's writes run inside
`layouts.apply`, its reads inside `layouts.plan` and `layouts.verify`.

## Editable TwichUI presets and bundling (2026-10-28)

The helper presets are maintained in game (`presets.md`): package **format 6** (`mode = "settings"`, `keep`, `retired`), the
authoring workspace's section 4 (`AuthorPresets.lua`, the model; `AuthorWindow.lua`), the wizard reading options dynamically
(`Model.lua` `PresetSummary`, `PresetCoverage`, `ReviewPreset`, `Missing`; `Pages.lua` cards; `State.lua` `dropped`), and
`tools/update_bundled_layout.sh --from-published` (`tools/import_published_layout.lua`, `tools/published_entry.lua`,
`tools/layout_data.lua`, `check_bundled_layout.lua --published`). The choices are data now (`TwichUI_Layouts/ChoicesData.lua`,
generated from what `Classic.lua` declared, so the bundled package's content and identity are unchanged: `#466738159:15197`).
The bundled package stays **format 5**, its presets switch-on-only, until the author publishes edited presets and imports them.
Offline-tested: `tests/test_layout_presets.lua` (new, 6 sections), with format-number and file-count expectations moved in
`test_layouts.lua`, `test_layout_wizard.lua`, `test_layout_publish.lua`, `test_layout_tooltip.lua`, `test_layout_hardening.lua`.
`./tests/run.sh`: 127 suites, all passed.

| What | State |
|---|---|
| Format 6 validation: values incl. `false`/`0`, resets, keep, retired, refusals (places, other addons, `LOCAL`, account-wide, lists, conflicts, bounds), legacy presets unchanged | offline-tested |
| Authoring: capture into a preset (scope kept, effective values), create, duplicate, rename, describe, reorder, default, remove, include/leave out, values, reset, search, categories, limits; nothing live changed; publish immutable | offline-tested; **in game**: the section and editor at 1080p, larger fonts, a real profile |
| Wizard: more than three cards, what each does, review words, apply, verify by value, deliberate switch, kept/owned settings said, update to the same preset, removed option, keep, Undo, Restore, Finish | offline-tested; **in game**: a real install and reload with an editable preset |
| Export for bundling (the entry's bytes as text) and the import's round trip, no-op, determinism, refusals, failure rollback, the recapture keeping the presets | offline-tested; **in game**: copying an 80 KB line out of the Export window |

Fixed on the way (both pre-existing since RH-1's format 4, neither reachable by the bundled package): a TwichUI fragment holding only a
`reset` list (no `groups`) was read as empty; and a reset of a setting whose TwichUI default is `false` was expected and baselined as the
reset marker (an `and/or` that dropped the `false`), so its check could never match. Both have tests that failed before the fix.
Diagnostics: scope `layoutwizard.presets.capture` (`AP.ReadAll`), gauge `layoutwizard.author.presets` (settings held by the presets'
draft and edit; 0 while closed); registered in `DX.OPS` and `docs/diagnostics.md`. The wizard's added work (normalizing at most eight
preset options for the cards and review, cached per option table) is event-rare and not scoped.

## Open decisions (recommended default first)

| # | Question | Recommended default |
|---|---|---|
| D1 | What does the brother's interface ("Compact Adventure") consist of? Which addons and modules, and which saved profile is its source (`TwichUI - Minimal Adventure`?) | **Answered in Phase 5 (D27)**: EllesmereUI-based, source `TwichUI - Minimal Adventure` |
| D2 | Is EllesmereUI required for both layouts? | Yes. Without it, only the TwichUI layer is offered, with a clear note |
| D3 | Restore point for EllesmereUI: copy the live `EllesmereUIDB` (no extra reload) or use today's disk scan (one extra reload)? | Phases 2 and 3 need neither (`history.md` §11.6). Live copy, when Phase 5 manages account-wide units |
| D4 | Exclude Cooldown Manager spell layouts? | Exclude (built) |
| D5 | Exclude window and tooltip skins (`blizzSkinGlobals`)? | Exclude in the first release (built); consider as a wizard choice later |
| D6 | Exclude spec and condition overrides? | Exclude (built) |
| D7 | The EllesmereUI active profile is account-wide, so an install changes every character's HUD. Accept and disclose, or offer to assign it per spec? | Accept and disclose; no spec assignment (built: `autoAssignSpecs = false`; the plan says it) |
| D8 | Install TwichUI settings into a new TwichUI profile (per character) or into the profile in use? | New profile (built) |
| D9 | Target profile names | EllesmereUI `TwichUI Classic` / `TwichUI Compact`; TwichUI `Classic Adventure` / `Compact Adventure` (the test package uses `TwichUI Layout Test` / `Layout Test`) |
| D10 | Suppress EllesmereUI's first-run picker every session, or only while a TwichUI install is planned or pending? | While an install is under way, and (2026-10-29) in EllesmereUI's first session when TwichUI's own first-install setup is new and can load (`docs/onboarding.md`); planning is refused while the picker is pending unless it is held for TwichUI |
| D11 | Reference canvas | Per package, in `geometry.canvas`: Classic's is the author's 2866.67 × 1200 (built) |
| D12 | UI scale choice factors (`larger`, `smaller`) | ×1.15 and ×0.87 of pixel-perfect, clamped to 0.40–1.15 |
| D13 | Without EllesmereUI, should TwichUI ever set the game's `uiScale` CVar? | No |
| D14 | Wizard choices in the first release | Variant, UI scale, opt-out of Chat, Minimap, Damage Meters, Quest Tracker and Bags modules, and up to five TwichUI feature toggles |
| D15 | Should Blizzard Edit Mode layouts join a later phase? | Later phase, after an in-game spike |
| D16 | Strip `customColors` from every payload (Phase 2 does), or manage colours as a look unit with its own restore? | Strip until look units exist (Phase 5 or later) |
| D17 | Composition area: 2.4:1 keeps the author's 21:9 layout as it is and narrows only wider screens; 16:9 would pull chat, meter and minimap inward on every 21:9 screen, the author's included | 2.4:1 (built) |
| D18 | Classic's rules (the central block's box, the focus frame, room and narrow arrangements, the readable minimums, the attach map) are a reading of the author's layout | Author to review the rules table and the 1680 × 1050 / 1600 × 1200 screenshots |
| D19 | 206 TwichUI looks-and-behaviour fields travel in the base (everything non-default except switches) | As chosen; trim to appearance-only groups if behaviour (e.g. mage, restock, navigation) should stay the recipient's |
| D20 | Classic stays `dev = true` (allowed on Retail) until checked on Forever | Yes |
| D21 | The TwichUI helper presets: `on-screen` (class resource bars, marker bar, food and drink buttons) and `finding-my-way` (those and Navigation) | As built; the author to confirm the set |
| D22 | The accent options and their colours (Aged gold is the layout's own; Verdigris, Ember and Dusk blue are proposals) | As built; the author to confirm |
| D23 | The cursor-following or fixed tooltip choice | **Answered 2026-10-28** (the section above): offered as "Tooltip placement", managed narrowly (the flag alone, written and read back, with its own snapshot, Undo and Restore), not through the import |
| D24 | A Welcome-dialog offer for the wizard | Not built; add only if wanted |
| D25 | Re-running with the same choices re-imports the install's EllesmereUI profile and replaces changes made in it | **Answered in Phase 7**: the baseline makes it "nothing to do" |

| D26 | One pair of install profiles for both layouts, named `TwichUI Adventure` | As built (`wizard.md`, D26) |
| D27 | Compact's sources: EllesmereUI `TwichUI - Minimal Adventure`; TwichUI side shared with Classic | Confirmed by the author |
| D28 | Compact's checked box is the core of the strip (1091 × 157.5); pet and stance pieces follow it outside it | As built; author to confirm |
| D29 | Compact's narrow width 1780; chat above the strip below it | As built |
| D30 | The overlay dims the live interface instead of hiding it | As built |
| D31 | TwichUI's pieces are Classic's captured places in Compact; class bars land inside the strip | Author to look in the overlay and say what moves |
| D32 | Positions not placed by the screen layer: Battle Res, the Cooldown Manager's other bars, class power | Register when wanted |
| D33 | The authoring workspace lives in `TwichUI_LayoutWizard` (about 36 KB more Lua in an addon that loads on demand) rather than in a third load-on-demand addon | As built; a separate addon needs the release, diagnostics-memory and dependency wiring (`CLAUDE.md`) |
| D34 | A received package may not carry opaque EllesmereUI export strings or the developer flag; settings must be data. The bundled package is unaffected | As built |
| D35 | Realm names are not scanned for on a client with no realms (WoW: Forever: the "realm" is the word Forever, which appears in settings); character names (whole and by word) are | As built |
| D36 | No text export or import of a published package | As built; add through the large-paste capture if wanted |
| D37 | A full store (4 published, 3 received, 3 MB) refuses; it never drops a package to make room | As built |
| D38 | Offers for a layout are never auto-accepted, even from a sender trusted for setups | As built |
| D39 | An update keeps the install's EllesmereUI profile as `TwichUI Adventure (previous)` (renamed, visible in EllesmereUI's list, account-wide) until the update is kept, undone or restored | As built: exact Undo with public functions only; the alternative (a copy in saved data) is large and lossy |
| D40 | Conflicts default to the player's value; on a layout switch, layout-specific changes default to the new layout's | As built (`updates.md`, "Switching layouts") |
| D41 | When EllesmereUI's data is of another vintage than the package, EllesmereUI is kept as it is by default (its update is offered again) | As built; Replace (after the copy) on request |
| D42 | Keep this setup finishes the setup (no Restore afterwards) but keeps managing; Stop managing is separate | As built (review requirement) |
| D43 | One level of Undo this update | As built |
| D44 | Compact's pet frame and stance bar sit left of the checked strip and reach over Chat on 16:9 screens (sample sizes), off screen at 1680 × 1050 | Reported as "may overlap" (RH-1). The author to choose: widen the strip (chat gives way on every 16:9 screen), move the pieces, or accept |
| D45 | A reset makes the bundled package format 4, which an older TwichUI refuses | As built: format 4 only when a reset is present |
| D46 | Scale guidance is given down to UI scale 0.64 | As built |
| D47 | The bundled unit-name font: the author's private `MyFonts` copy replaced by TwichUI's `AlegreyaSansSC-Bold.ttf` (same file name and registered name; not byte-compared) | As built; the author to confirm in game |
| D48 | The unpack bound covers layout packages only; configuration setups on the same transport keep LibDeflate's unbounded unpacking | Separate change, with its own tests |
| D49 | "Leave them as they are" and the layout's own TwichUI looks: genuinely preserve every setting the presets cover (the base's value skipped for those), or explain? | As built: **explain**. It writes nothing of the presets'; the layout's own looks (never feature switches) still apply, and the review says how many of the presets' settings they also set. Established behaviour unchanged |
| D50 | Picking another preset than the one installed: take the preset's values ("use recommended") or keep the player's changes? | As built: the preset's values, each still offered as "keep mine"; owned settings stay theirs; the review says when it isn't fully in effect. The same preset updated follows the normal keep-mine rules |
| D51 | Convert the shipped presets to format 6 now? | As built: no. They stay switch-on-only (format 5) until the author saves a change in game and imports the published package |
| D52 | The accent's "Aged gold" option holds its own colour in `ChoicesData.lua`, no longer the look's accent from the capture | As built; `check_bundled_layout.lua` notes a mismatch after a recapture. Alternative: keep generating that option from the capture |
| D53 | A new preset's starting scope | As built: every feature switch a preset may manage (on/off), with the source profile's values; looks are added by the author |
| D54 | Bounds | As built: 8 options, 256 settings per preset, 32 retired ids; `MAX_EXPECT` 320 to 832 (an older TwichUI would read a newer record holding more than 320 entries as damaged) |
| D55 | A removed preset the player had picked | As built: named, and Next/Apply wait for a pick (nothing applied in its place) |
| D56 | Closing the workspace with preset work not saved or published | As built: Close asks; Escape keeps the session until the reload and says so |
| D57 | First-install offers after Do this later | As built: again at each real login (never a reload), three automatic offers per phase, then only when asked. Alternatives: one offer only; a reminder line instead |
| D58 | Skip setup while EllesmereUI's first run is held for TwichUI | As built: EllesmereUI's own picker is shown at once (its Done reloads). Alternative: say where it is and show nothing |
| D59 | Do this later while EllesmereUI's first run is held | As built: it stays held this session (no unregister exists); EllesmereUI's picker then doesn't return by itself (its source), so the setup's first page offers it while `held`. Alternative: hand it back on every deferral |
| D60 | The dimming: 40% warm charcoal, lifted during combat, shown for every opening of the wizard (not only the first install) | As built; tune the strength after the in-game look (check 3 in `docs/onboarding.md`) |
| D61 | First-install state scope | As built: account-wide (one offer per account, like EllesmereUI's active profile). Alternative: per character |


## Production release blockers

1. **RH-2 has not been done**: none of the checklist below has been run on WoW: Forever with the packaged artifact.
2. **The repository needs repair before anything is committed or released.** `git fsck` reports 38 empty object files written
   2026-10-27 18:15 (an interrupted write), and the branch and its remote-tracking ref point at one of them, so `git status`,
   `git diff` and the release tools that use git fail. The working tree is intact. Repair (for example by fetching the pushed
   objects from `origin`, or re-cloning and copying the working tree over) is the owner's call; RH-1 changed nothing in `.git`.
3. The bundled package is `dev = true` (D20) and the wizard says it is a preview; removing that is a decision after RH-2.
4. D44 (Compact's pet and stance pieces over Chat on 16:9) and D31 (Compact's class bars) are visible on the most common screen:
   the wizard says so honestly, but the author should decide before release.
5. D47: confirm the bundled unit-name font is the same font the author chose (compare in game).

## RH-2: in-game acceptance checklist (packaged artifact, WoW: Forever)

Run on the zip the release workflow builds, installed fresh. Record results here. The detailed per-phase checklists are in
`history.md`; these are the release gate, in order.

1. **Fresh install**: a character with no TwichUI layouts data and EllesmereUI on its own profile. `/tui layout`, Classic, Apply,
   reload: "Verified by value" with the presence-only count, both `TwichUI Adventure` profiles in use, nothing else changed.
2. **Both layouts**: switch to Compact, reload, check; switch back. Look at the pet frame and stance bar against chat (D44).
3. **Finish, reload, reopen**: Keep this setup; reload; `/tui layout` says "Installed and managed"; Set up again is an update.
4. **Personal edits and consecutive updates**: change a TwichUI font, move the marker bar, move the minimap and change the chat
   text size and the minimap coordinates; install a newer revision; all kept; install another revision; still kept.
5. **Parent and child preservation**: Stop managing the minimap's place; install a revision that changes the minimap blob;
   reload: the place is yours. A revision that resets a TwichUI setting: back to the default unless you changed it.
6. **Undo and Restore**: Undo this update (reload: as before the update, the copy gone); Restore (reload: as before the first
   install); interrupt one of them (combat, a profile switch) and finish it.
7. **Narrower screen and another UI scale**: 1920 × 1080 at UI scale 1.0 (the wizard says it doesn't fit and gives a scale), then
   at the scale it gives; 1680 × 1050; an ultrawide. Compare the Review preview with the result.
8. **EllesmereUI versions**: the version the package says it was tested with, and the newest available; the review says
   "tested with"; positions and links survive EllesmereUI's load-time migrations.
9. **First run and account**: the first-install checklist in `docs/onboarding.md`; a fresh EllesmereUI without TwichUI's
   first-install setup (its picker pending: planning refused); a second character on the account sees
   the HUD change and can't restore or stop managing the first character's install.
10. **Diagnostics**: `/tui perf` capture while opening the wizard ten times, reviewing, applying, checking and opening the
    overlay; the `layouts.*` scopes appear, the wizard gauges stay flat, and nothing loads when the setup isn't used.
11. **TwichUI presets** (`presets.md`): capture into On-screen helpers from a real profile with a feature switched off; create a
    preset; publish; Export for bundling (copy the line out, import it with `--from-published --text`); install the result on a
    character, reload, check; switch preset; Undo; Restore. Look at the presets section and editor at 1080p and with larger fonts.

Also from the earlier phases (still required; detail in `history.md` and the topic documents): `ImportProfileSilent` and
`RegisterExternalInstaller` on Forever, `spec_locked`, the checklists of `updates.md`, `wizard.md` and `publishing.md` (two
clients).

## Deferred enhancements (not blockers)

- A unified publishing workflow (one artifact path for the bundled and in-game packages): the comparison exists; the merge of the
  two workflows does not.
- Placing the battle resurrection timer, the Cooldown Manager's other bars and class power (D32); Compact-specific TwichUI places.
- The same unpack bound for configuration setups on the shared transport (D48).
- More than one level of Undo; remembering layout-specific personal choices per layout.
- A whole-`EllesmereUIDB` restore point (D3), and with it the UI scale and tooltip choices (D12, D23).
- Blizzard Edit Mode management (D15).


## Earlier whole-project in-game list

1. `ImportProfileSilent` on Forever 9.6.x: the profile is created and active after the reload, `cleanSlate`
   replaces only the target, and the result matches the payload.
2. `disableAddons` and the enable states apply at the reload. Enabling sweeps the other suite children as
   documented.
3. `uiScale` in the payload sets `ppUIScale`, `UIParent:GetSize()` matches the computed `W×H`, and `keep` leaves the
   scale alone.
4. `RegisterExternalInstaller` called after EllesmereUI's `ADDON_LOADED` (and, for a first install, at `PLAYER_LOGIN`) keeps
   the picker away on a fresh account. Without the call, the picker shows. (Source: after a session with module data the
   picker does not return by itself, `docs/onboarding.md`.)
5. `"spec_locked"`: with the current spec assigned to another profile, the import is stored and not activated.
6. Restore at EllesmereUI's `ADDON_LOADED` puts the old `EllesmereUIDB` back before EllesmereUI reads it, with no
   "profile corrupted" warning from `NewDB` (only when D3's restore point is built).
7. Positions survive the reload unchanged (no TOPLEFT re-migration or pixel snap beyond 1 unit) on 1080p, 1440p, 4K
   and ultrawide.
8. Another character on the same account sees the EllesmereUI layout, and their TwichUI profile is unchanged (D7, D8).
9. Combat: Apply and Restore are refused. The reload button is not offered in combat.
10. The packaged install loads `TwichUI_Layouts` on demand. A missing or disabled copy is reported, and the core is
    unaffected.
11. The Phase 2 checks above, and the Phase 3 manual visual checklist.
12. The wizard's manual acceptance checklist (`wizard.md`), including: the pictures draw with transparent backgrounds
    (the emblem's was keyed out of a painted checkerboard); `ReloadUI()` from the button, and the wizard opening on the
    result 3 seconds after login; the picked accent reads back from a Forever EllesmereUI profile
    (`accent:rgb` matches); the window at 1080p, 1440p and ultrawide; `/tui perf` with the window opened ten times.
13. The Phase 5 manual checks (`wizard.md`, 16–23): Compact on the author's screen, the overlay at three resolutions, click-through,
    combat and profile-change closing, the layout switch and its restore, `/tui perf` with the overlay.
