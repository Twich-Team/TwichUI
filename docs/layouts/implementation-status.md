# Layout packages and installer: implementation status

Branch `feature/layout-wizard`. The contract is in `architecture.md` (§11 and §12 have the revisions Phases 2 and 3 made) and the
evidence in `adapter-capabilities.md`. Update this file at the end of every phase: what was built, what was checked,
and what is still open.

## Status

| Phase | State | Date |
|---|---|---|
| 1. Audit and contract | **Done**: documents only, no code | 2026-10-26 |
| 2. Engine and safe application pipeline | **Done offline**: automated checks pass; nothing run in game | 2026-10-26 |
| 3. Classic Adventure and the screen-layout resolver | **Done offline**: automated checks pass; nothing run in game | 2026-10-26 |
| 4. Wizard, preview and install lifecycle UI | **Done offline**: automated checks pass; nothing run in game (`wizard.md`) | 2026-10-26 |
| 5. Compact Adventure and richer previews | **Done offline**: automated checks pass; nothing run in game (below, `wizard.md`). The UI scale policy moved to Phase 6 (D12, D3) | 2026-10-26 |
| 6a. Authoring and publishing (the author's Phase 6; see `publishing.md`) | **Done offline**: automated checks pass; nothing run in game | 2026-10-27 |
| 6b. Retained overrides and updates | Not started | |
| 7. Release hardening and in-game validation | Not started | |

Phase 2 was re-scoped by the author: instead of scaffolding and a pure composer only, it builds the whole pipeline
(validation, composing, both adapters, snapshot, apply, verify, restore, the install record) for one small developer
package. Phase 3, as the author set it, is the first real layout and the screen layer (what Phase 1 called screen
adaptation and part of package content). The phases after 3 are a proposal for the author to confirm.

Nothing in this project has been run on WoW: Forever. The Retail saved files show the Phase 2 developer package was
applied, verified, restored and its restore checked out on Retail (the record is gone and both install profiles were
removed); that is a check of TwichUI's side on another client, not one of the in-game checks below.

## Phases and acceptance criteria

Every phase also meets CLAUDE.md: the offline suite passes (`./tests/run.sh`), a new test fails without the change,
diagnostics coverage is decided and reported, and in-game checks are listed rather than claimed.

### 1. Audit and contract (done)

- [x] Read the sharing, restore, profile, persistence, settings and navigation load-on-demand code and docs.
- [x] Read EllesmereUI 9.6.8's profile, import, export, first-install, scale and position code.
- [x] Defined: supported addons, managed categories, adapter contract, schema and IDs, precedence, merge semantics,
      coordinates, lifecycle, reload and combat rules, packaging.
- [x] Listed open decisions and in-game checks (below).

### 2. Engine and safe application pipeline (done offline, 2026-10-26)

**Built.** A load-on-demand sibling addon `TwichUI_Layouts/` (`RequiredDeps: !!!TwichUI`, no saved variables):

| File | What it is |
|---|---|
| `Canon.lua` | Canonical text and fingerprint of a value (sorted keys, `%.17g`, `false`/`0`/`""`/missing distinct; refuses cycles, depth > 16, > 50,000 values, > 8 MB, functions, NaN), `REMOVE`, small helpers |
| `Package.lua` | Package format 1 validator, `LY.Resolve(pkg, variant)` (base → variant → preset → choices) |
| `Compose.lua` | `LY.Compose`: per-unit precedence, `REMOVE`, unmanaged, superseded fields, retained and reset. Pure |
| `AdapterTwichUI.lua` | `twichui` adapter over TwichConfig's schema and checks and the Profiles operations |
| `AdapterEllesmere.lua` | `ellesmereui` adapter over EllesmereUI's public partner-installer functions |
| `Journal.lua` | The install record `TwichUIDB.layouts.install`: shape, bounds, checks |
| `Engine.lua` | `LY.Plan`, `LY.Apply`, `LY.Verify`, `LY.PlanRestore`, `LY.Restore`, `LY.VerifyRestore`, `LY.Continue`, `LY.Detach` |
| `TestPackage.lua` | The developer test package `twichui-layout-test`, variant `test` |
| `Dev.lua` | `/tui layout validate | plan | apply [confirm] | verify | restore [confirm] | status | detach confirm` |

In the core: `LayoutsLauncher.lua` (`L.Load` with reasons, `/tui layout` hand-off, the after-login check while a record
waits, `RegisterExternalInstaller` while one is under way); a hidden `layout` command in `Core.lua`; `layouts` in
`Persist.lua`'s containers, `RS.OWN_LEFT_OUT` and `TC.LOCAL` (`other`); read-only exports `TC.Container`, `TC.Raw`,
`TC.Effective`, `TC.ValueOk` (the existing local functions, not new logic). Release wiring: `.pkgmeta` `move-folders`, `tools/release.py` `ADDONS`/`LOAD_ON_DEMAND`,
`tests/test_release_tools.py`, `RELEASING.md`, and the (ignored) `tools/deploy.sh`.

**The test package** changes, in profiles of its own that Restore removes:
- TwichUI (at once, this character): `ui.arrivalHold` (`long` in the base, `longer` in the variant: the variant
  wins), `ui.trainingStyle = "illustrated"`, `modules.arrivalSubzones = false`. Profile `Layout Test`, a copy of the
  one in use.
- EllesmereUI (after a reload, every character on the account): `minimap.coordsMode = "always"` (base),
  `minimap.coordsPosition = "bottom"` (variant). Profile `TwichUI Layout Test`, built on the recipient's own active
  profile (a developer-only base).

**Supported operations.** Validate; resolve a variant; plan (read only, allowed in combat); apply exactly the plan
whose key was shown (refused in combat, on a stale key, or when nothing would change); verify (read only, never
repairs); restore exactly the restore plan shown (refused in combat); the check after the reload that finishes an
apply or a restore; detach (forget the record, change nothing). Not supported yet, refused by name ("not yet"):
`canvas`, `choices`, `positions`, TwichUI `places` and list groups, EllesmereUI `positions`, `look`, `uiScale`,
`disableAddons`, `unlockLayout`.

**Snapshot and record format.** `TwichUIDB.layouts.install` (`Journal.lua` header; `architecture.md` §11.8):
`{ v = 1, package, revision, variant, char, state, at, key, reload, steps = { { adapter, state, code, rollback,
reload } }, snapshot = { twichui = { char, profile, target, created, values }, ellesmereui = { active, target, created,
version, values } }, expect = { [adapter] = { [unit] = fingerprint } }, inputs = { [adapter] = fingerprint }, verify =
{ state, at, diffs (≤ 8) }, restore = { at, steps } }`. Fingerprints, not copies; bounded by the units per adapter
(96 in Phase 2; 256 named plus 64 placed since Phase 3: the test package's record is under 4 KB of canonical text,
Classic Adventure's 25 KB, measured offline). Removed once a restore checks out.

**Checks run** (offline Lua 5.1; `./tests/run.sh`: 119 passed, 0 failed):
- `tests/test_layouts.lua` (199 checks): the core without the layouts addon (nothing loads at login; a missing addon
  is explained); canonical form and fingerprint; composing (precedence, `REMOVE`, unmanaged, superseded, retained,
  reset, determinism); validation failures (format missing or newer, unknown and not-yet fields, bad ids, values,
  targets, cycles, unknown adapters, groups, units, account-scoped and list fields, dev-only base); a schema walk
  showing no `TC.LOCAL` key and no account-scoped field is writable; the snapshot's contents; apply order
  (EllesmereUI's import before TwichUI's profile); the exact `ImportProfileSilent` options and payload (no UI scale,
  spec assignments, CDM spells, custom colours, overrides, skins, click-cast, private data, unknown modules); every
  unrelated TwichUI key, backups, shares, the Chronicle and the other EllesmereUI profiles unchanged; verify before and
  after a simulated reload (EllesmereUI's load-time defaults included); the picker registration and the after-login
  check; a verified install loading nothing at the next login; installing again (nothing to do; a changed package
  re-imports after switching off the install's profile, keeps the first snapshot and one install profile);
  verification failure recorded and not repaired; restore (reverse order, refused stale or in combat), checked after
  the reload, values and saved data as before the install; mocked adapters for partial failure, clean failure (no
  record; a previous record kept exactly), an adapter error, a failed verification and a failed restore step; real
  adapters failing (an import that breaks leaves no half-made profile; encode failure never imports; `spec_locked`
  reported as not in use; target profiles that aren't ours; EllesmereUI's first-run picker pending; EllesmereUI
  missing, too old, newer than tested, not Forever); a real export-string base (exclusions, module replacement,
  superseded fields, presence-only blob check); damaged, newer and other-character records; the developer command
  end to end, with no reload made by itself.
- Mutation checks (made and reverted by hand): recapturing the snapshot on a repeat install, `applyUIScale = true`,
  and an allowlist that ignores `TC.LOCAL`/scope each make `test_layouts.lua` fail. The `false`-valued field bug found
  while writing it (`a and b or c`) was caught by the verify check.
- `tests/test_perf_engine.lua`: the layouts memory series is analysed and reported, and absent when never loaded; the
  `layouts.*` scopes are in the catalogue (fails without the change).
- `tests/test_release_tools.py`: a package without `TwichUI_Layouts`, or with it not load on demand, is refused.

**Diagnostics coverage.** Scopes `layouts.load` (`LayoutsLauncher.lua`), `layouts.plan`, `layouts.apply`,
`layouts.verify`, `layouts.restore` (`Engine.lua`, `Perf.Call`), registered in `DX.OPS` and `docs/diagnostics.md`.
`TwichUI_Layouts` memory is read and reported (`Base.lua` `DX.LAYOUTS`, `Collect.lua` `ReadMemory` and `OURS`,
`Findings.lua`, `Export.lua`, `Window.lua` `MEMS`, `Session.lua`). No gauges: the engine keeps no pools, listeners or
caches; the record is bounded and in saved data.

**Phase 1's acceptance items, now:** core runs with the addon missing (done, with a reason; disabled/erroring
reasons share `L.Explain`); composer pure and deterministic (done; layer 5, screen adaptation, is not built);
precedence tests (done for base, variant, preset, choices, retained, reset); coordinate tests (done in Phase 3);
fingerprint (done); validator (done); release tools and backup coverage (done); `layouts.load` scope and memory
(done); TwichUI adapter acceptance (done except list groups and places); EllesmereUI adapter acceptance (done except the
UI scale, enable states and the restore point, which nothing in Phase 2 needs).

**In-game checks for Phase 2** (none done; on WoW: Forever with the author's EllesmereUI, installed 9.6.6, package
tested against the 9.6.8 source). While Forever can't be played, the developer package also runs on Retail
(`architecture.md` §11.13). A Retail run is worth doing for TwichUI's side and the record, but it doesn't tick any of
these: Retail EllesmereUI skips Forever-only import steps, and the Forever client may differ.

1. `/tui layout plan` prints the plan; `apply confirm` creates `TwichUI Layout Test` and `Layout Test`, and nothing
   reloads by itself.
2. After `/reload`: the minimap shows coordinates at the bottom; the "checked after the reload" line says verified;
   `EllesmereUI > Profiles` shows `TwichUI Layout Test` in use; the profile you used before is unchanged.
3. The zone card stays longer, the training card is illustrated, subzone cards are off; the settings window (Profiles)
   shows `Layout Test`.
4. `ExportProfile` on a non-active profile name works (the repeat install exports the recipient's profile while the
   install's is active).
5. `ImportProfileSilent` with `cleanSlate` on a repeat install, after `SwitchProfile` back: no "Default" fallback, no
   stray profile, EllesmereUI's sync popup (if any) is harmless.
6. EllesmereUI's load-time merges leave `minimap.coordsMode`/`coordsPosition` as written (no migration rewrites them).
7. `/tui layout restore confirm`, `/reload`: back on the previous profiles in both addons, the install's profiles gone,
   "restored" said; unlock anchors of the previous EllesmereUI profile intact (`SwitchProfile` restores its layout).
8. Another character on the account sees `TwichUI Layout Test` in EllesmereUI after an install (account-wide) and keeps
   its own TwichUI profile; `/tui layout` there refuses to install or restore.
9. In combat, `apply confirm` and `restore confirm` are refused.
10. With `TwichUI_Layouts` disabled in the AddOns list, `/tui layout` explains it and the rest of TwichUI is unaffected;
    with a record waiting, the login line explains it.
11. A spec assigned to another EllesmereUI profile: the install is stored, not activated, and the check says so.
12. A fresh EllesmereUI install: the plan is refused while EllesmereUI's picker is pending (`eui-first-run`).

**Release decision.** `TwichUI_Layouts` is wired into the release zip. The next release would ship the engine, the
hidden developer command and the test package (harmless: nothing runs unless typed). If that is not wanted before the
wizard, add `TwichUI_Layouts` to `.pkgmeta` `ignore` and take it out of `tools/release.py` `ADDONS` until the wizard. Still open after Phase 3, which adds the Classic data
(375 KB of source) to what would ship.

### 3. Classic Adventure and the screen-layout resolver (done offline, 2026-10-26)

**Capture source and fields.** Read from copies of the Retail client's saved files (the only TwichUI and EllesmereUI
saved data on this machine; `_forever_` has none), never the live files, never written. Candidates reported before
capturing: EllesmereUI profiles `TwichUI - Classic Adventure`, `TwichUI - Classic Adventure 2` (the one in use),
`Twich Forever` (the first apart from Cooldown Manager) and `TwichUI - Minimal Adventure`; TwichUI has only `Default`
(every character). The author chose **`TwichUI - Classic Adventure`** and **`Default`**, positions plus looks and
behaviour for TwichUI, the look in the base and everything else in the variant, and Retail as the source.
`capture-classic-adventure.md` is the reviewable result: what was kept (4 root keys, the layout links, 18 module
blobs, 206 TwichUI fields that differ from TwichUI's defaults in 19 groups, 5 TwichUI places), what was left out and
why (Group Finder, custom colours, `chatBubbles`, `tooltipFixedPos`, the Cooldown Manager's per-spec `spec` and
`activeSpecKey`; 48 TwichUI on/off switches; 368 fields at their default; everything outside the allowlists), and the
personal-data scan (0 names, realms, GUIDs, links, BattleTags). Not captured by construction: keybindings and action
slots (Blizzard's, not in profiles), click-cast, CDM spells, overrides, character data, knowledge, caches, chat
history, other profiles, the UI scale. The author's profiles are untouched. A second capture from fresh copies of the
saved files (after the game had run again) was byte-identical.

**Built.**

| File | What it is |
|---|---|
| `TwichUI_Layouts/Geometry.lua` | The resolver: composition area, components, anchors, density, bounds, room, above, narrow rules, clamping, diagnostics; conversions (`Stored`, `Follow`, `Moved`, `Round`); `Live()` reads UIParent's size (read only) |
| `TwichUI_Layouts/Package.lua` | Format 2: `geometry` and `source`; `LY.Resolve` resolves the geometry for `opts.screen` / `opts.density` |
| `TwichUI_Layouts/AdapterEllesmere.lua` | Settings as data (`root`, table `modules`, `layout`), `STRIP`, `POSITIONS` (40 registered), `TEXT`, the screen layer (`Adapt`, `ShiftLink`), placed-position plan rows, `Expect` / `Verify` within a unit |
| `TwichUI_Layouts/AdapterTwichUI.lua` | `PLACES` (7), `places` fragments, `A.Places` (the screen layer), writing and verifying places |
| `TwichUI_Layouts/Engine.lua` | `opts` through plan and apply; the screen and density in the plan key |
| `TwichUI_Layouts/ClassicData.lua` | The capture (generated; 375 KB of source, ~0.9 MB once loaded, offline figure) |
| `TwichUI_Layouts/Classic.lua` | The package `twichui-adventure`, variant `classic-adventure`, targets `TwichUI Classic` / `Classic Adventure`, and its geometry |
| `TwichUI_Layouts/Dev.lua` | `/tui layout validate|plan|apply|geometry [test|classic] [standard|larger] [WxH] [all]` |
| `tools/layout_capture.lua` | The offline capture (strict data reader, the adapters' allowlists, scan, deterministic writer, report) |

**Package structure.** Base (shared suite): EllesmereUI `root` (fonts, accent, dark-mode palette, migration stamps)
and the TwichUI looks. Variant `classic-adventure`: the 18 EllesmereUI module blobs, the layout links, and the TwichUI
places. Geometry: the canvas, rules and attach maps (`architecture.md` §12.4). The package is `dev = true` until it has
been checked on Forever.

**Geometry rules (Classic).** Canvas 2866.67 × 1200 units (3440 × 1440 at UI scale 0.64; confirmed by the minimap's and
the meter's right-edge links). Composition area at most 2.4:1. Densities `standard` (1) and `larger` (1.15). Narrow
below 1700 units. Margin 0 (the author's minimap is 2.5 units from the edge).

| Component | Anchor | Size and bounds | Rules | Attached |
|---|---|---|---|---|
| central | bottom centre of the area | 890 × 525 (unit frames, bars), fixed | — | 21 EllesmereUI positions, 3 TwichUI places |
| focus | the central block | 225 × 59, fixed | — | focus frame and cast bar |
| chat | bottom left of the area | 451 × 186, density, min 280 × 120, max 640 × 320 | room right of central (12) | toast, bar 3, XP bar, food and drink, Healer Watch |
| meter | bottom right of the area | 375 × 150, density, min 240 × 100, max 560 × 300 | room left of central; narrow: under the minimap | — |
| minimap | top right of the area | 200, density, 140–280 | — | buffs, debuffs, queue status, location text |
| objectives | under the minimap (−56) | 280 × 420, min 200 × 160 | room down of focus; narrow: under the meter | **not applied** (Edit Mode) |
| notifications | top centre (−260) | 520 × 96 | above central (12) | training and welcome-back cards |
| top-edge, top-left | the area's top and top-left | points | — | top data bar, boss frames; extra button, reputation bar |

**Supported viewport cases** (offline resolver, both densities; UIParent units):

| Screen | Units | Result |
|---|---|---|
| 3440 × 1440 at 0.64 (the author's) | 2866.67 × 1200 | the captured layout, exactly (positions and link offsets within 0.01) |
| 1920 × 1080 / 1920 × 1200 at 0.64 | 2133 × 1200 / 1920 × 1200 | fits; edges kept, block unchanged |
| 1920 × 1080, 2560 × 1440 pixel-perfect | 1920 × 1080 / 2560 × 1440 | fits; block from the bottom, cards from the top |
| 1680 × 1050 pixel-perfect, 1600 × 1200 at 0.64 | 1680 × 1050 / 1600 × 1200 | fits with the narrow arrangement (chat narrower, meter under the minimap) |
| 3840 × 2160 at 0.40 | 3413 × 1920 | fits |
| 5120 × 1440 at 0.64 (32:9) | 4267 × 1200 | fits, in a 2880-wide composition area |
| 1920 × 1080 at UI scale 1.0, 1024 × 768 | 1365 × 768 / 1024 × 768 | **does not fit**: the overlaps are listed; nothing is shrunk past its minimum. Needs a smaller UI scale (Phase 5) or Compact Adventure |

**Known adapter limits.**
- Objectives: EllesmereUI's quest tracker has no stored position (Blizzard's Edit Mode places it). Resolved and shown,
  never applied (D15).
- EllesmereUI: positions in a format not read are left as captured and noted (`bagsPosition`, `bankPosition`:
  `TOPLEFT` with no relative point). Raid and party frames are stored from the left edge (`LEFT`) and kept as captured.
  Links to another element are left to EllesmereUI; point-mode links are not rewritten. Positions are written for the
  screen planned on: a later resolution change is followed natively only by screen-edge links and edge-relative
  stores (chat), not by the other centre offsets (install again).
- EllesmereUI: the blob shapes are 9.6.8's, captured on Retail; Forever's EllesmereUI may migrate them at load (the
  migration stamps travel so it knows their vintage). Unverified.
- TwichUI: windows the player moves (party pins, the Cozy Bag guide, refreshments, navigation's frame, settings) are
  not places; the arrival card has a fixed place; friend-login is not managed.
- The UI scale is never set (the recipient's own, Phase 2's rule); the resolver adapts to it instead. Density changes
  component and text sizes only.

**Checks run** (offline Lua 5.1; `./tests/run.sh`: 120 passed, 0 failed):
- `tests/test_layout_geometry.lua` (new): each rule on a synthetic layout (canvas exact, wider and ultrawide with the
  composition area, shorter, density with bounds, room down to the minimum, overlap and minimum reported, narrow
  override, above, offscreen and clamping, unmanaged ignored, determinism); refusals (cycles, unknown targets, bad
  points, room on the anchored side, standard density ≠ 1, narrow without a width, missing offsets, unknown attach
  positions, points and adapters, unreal screens); conversions (BOTTOMLEFT, CENTER, TOP, BOTTOM-from-CENTER, follow,
  rounding); Classic on 9 screens × 2 densities (fits, on screen, no shrinking without a rule, never under the
  minimum), the narrow arrangement, 32:9, 1440p; 1365 × 768 honestly not fitting; on the canvas, each of the 37
  attached positions, every link offset and every TwichUI place exactly as captured; EllesmereUI's own link formulas
  (written out independently) put the minimap, meter and chat where the plan says on four screens; links to elements
  left alone; the larger density's text sizes; the capture holds only allowlisted parts and no code; retained memory.
- `tests/test_layouts.lua` §16 (new): Classic through the pipeline on 1920 × 1080 at 0.64: the payload (every module
  and no other; the look and links travel; colours, scale, spells and per-spec records don't; placed minimap, chat and
  followers, an unmoved block), 37 placed rows, objectives not applied; a plan for another screen or density is
  stale; apply into both install profiles with the UI scale and the author's profiles untouched; TwichUI places and
  looks written; backups, shares and the Chronicle unchanged; verified after the reload; a moved minimap reported, not
  repaired; the restore checked out after the reload, both profiles and every place back; narrow + larger,
  1365 × 768 and an unknown density; the developer command end to end (`geometry`, the `plan … all` hint,
  `apply confirm` of the package last shown, unknown words refused).
- `tests/test_layouts.lua` §4: format 3 refused as newer; `geometry` in a format 1 package refused. The stand-in
  EllesmereUI's import now also takes `darkMode`, `euiAccent` and `_migrations`, as the real one does.
- Mutations (made and reverted): links not rewritten, the room rule off, the room's minimum off, and scaling every x by
  one screen ratio each fail the new tests. Leaving the screen out of the plan key does not: each part's key already
  holds every placed position (the screen entry is a second guard).
- `luacheck` (no config in the repo; globals off): 0 warnings in the changed files.
- Measured offline (Lua 5.1 on the development machine, not the game): `LY.Validate(Classic)` ~11 ms and ~3 MB
  allocated per call; `Geometry.Resolve` 0.07 ms and 30 KB; the captured data ~0.9 MB retained once loaded.

**Diagnostics coverage.** No new scope or gauge. Resolving runs inside `layouts.plan` (and `layouts.apply`'s re-plan),
which already time it; `/tui layout geometry` is a typed developer command costing 0.07 ms offline. The addon's
memory, which now includes the Classic data, is already read and reported as `TwichUI_Layouts`. Nothing new is kept
between calls.

**Manual visual checklist** (none done; offline geometry is not visual verification). On Forever when it can be
played, and meanwhile on Retail for TwichUI's side (the developer package is allowed there):
1. `/tui layout geometry classic` on your own screen: the line "Your screen … gives … units" matches UIParent
   (2866.67 × 1200 at 3440 × 1440, 0.64), with no problems listed.
2. `/tui layout plan classic`, `apply confirm`, `/reload`: verified. Compare with `TwichUI - Classic Adventure` side by
   side (screenshots): every frame where it was.
3. EllesmereUI's Unlock Mode after the install: the minimap, meter and XP bar still show their screen-edge links with
   the offsets the plan gives; nothing jumps when Unlock Mode opens or closes.
4. The chat box: position and size as planned after the reload, and Blizzard's Edit Mode (opened and cancelled) leaves
   it there (EllesmereUI writes chat into Edit Mode's store).
5. TwichUI's marker bar, class bars, navigation arrow, food-and-drink buttons, Healer Watch, training and welcome-back
   cards where the plan says (`/tui` previews).
6. Another 16:9 resolution or scale (e.g. 1920 × 1080 at 0.64): `plan classic` again, apply, reload: chat, meter and
   minimap at the edges, the block centred, nothing overlapping. Screenshots for the author (D18).
7. A narrow case (1680 × 1050 pixel-perfect): the meter under the minimap, chat narrower, readable.
8. `larger`: text and boxes larger, chat and meter text as planned, nothing clipped.
9. UI scale 1.0 on 1080p: the plan says it doesn't fit; if applied anyway, the overlaps are where it said.
10. The objective tracker stays where Edit Mode had it, as the plan said.
11. Restore after each: both install profiles gone, the author's profile in use, everything as before.
12. A Forever EllesmereUI: the Retail-captured blobs load without errors, and its load-time migrations leave the
    positions as planned.

### 4. Wizard, preview and install lifecycle UI (done offline, 2026-10-26)

**Built** (`wizard.md` has the workflow, the managed choices, the artwork handling, the checks and the manual checklist):
a load-on-demand sibling addon `TwichUI_LayoutWizard/` (`Art.lua`, `State.lua`, `Model.lua`, `Preview.lua`, `Pages.lua`,
`Window.lua`; `RequiredDeps: !!!TwichUI, TwichUI_Layouts`), six steps (welcome and compatibility, layout, TwichUI helpers,
personalize, review and apply, result), a miniature preview drawn from Phase 3's resolved geometry, the result and
restore flows, and a resume after a reload the player started. Entries: `/tui layout` (bare; the developer commands keep
their words), Home > Interface layout, Troubleshooting > Layout setup. In the core: `LayoutsLauncher.lua`
(`L.LoadWizard`, `L.OpenWizard`, `L.WizardResume`, the resume at the check after login). In the engine: package format 3
with `choices` (a preset of switches turned on, an accent, a size), picks through `LY.Resolve`, the plan key and the record,
and the accent read back by value (`architecture.md` §13). Artwork: four runtime files built from the four sources
(`tools/make_layout_wizard_art.py`); Compact Adventure's is reserved. Release and diagnostics wiring as for
`TwichUI_Layouts`. **Not offered**: the cursor-following or fixed tooltip choice (no adapter backs it: it is an
account-wide EllesmereUI global that its import resets whole; `wizard.md`, "Choices", D23).

**Checks run** (offline Lua 5.1; `./tests/run.sh`: 121 passed, 0 failed): `tests/test_layout_wizard.lua` (new; with
`tests/layouts_mock.lua`) and `tests/test_layouts.lua` §17 (new), `test_perf_engine.lua`, `test_release_tools.py` and the
settings contract fixture updated. Eighteen hand mutations each fail a test (`wizard.md`, "Checks"). `luacheck` (no config,
globals off, no line length): 0 warnings in the wizard's files and the engine files changed.

**Acceptance, as built:**
- The review names the account-wide EllesmereUI profile change, the TwichUI profile used, the reload, what is left alone,
  what isn't placed, what doesn't fit, blockers with reasons, and what Restore will do; on a repeat install it says that
  changes made in the install's profile since are replaced (done).
- The preview draws from the same resolved geometry the plan is built from (same screen and density), and is redrawn when
  a pick or the screen changes; a stale plan can't be applied, by three checks (done).
- Combat refuses Apply, Restore and Reload in the model, the confirmation and the engine; the window's disabled buttons
  say why (done).
- Escape, focus and reopening: Escape through `UISpecialFrames`; six reopenings make no frames, listeners or hooks (done;
  gauges `layoutwizard.events`, `layoutwizard.frames`). Keyboard focus beyond Escape: not built (no text fields).
- Nothing runs before the player asks: no login event, no Welcome change, no minimap button (done).
- Choices: `choices` has a package schema and validation, and density is a choice (done).

**Original acceptance list (kept for the record):**
- The review names: the account-wide EllesmereUI profile change, the TwichUI profile used, the reload, exclusions,
  what isn't applied (objectives), what doesn't fit on this screen, and what Restore will and won't undo.
- The preview draws from the same resolved geometry the plan was built from, and re-plans when the screen or density
  changes; a stale plan can't be applied (done).
- Combat refuses Apply and Restore centrally (done); the window's disabled controls explain why.
- Escape, focus and reopening behave as in the settings window. No duplicate frames, hooks or callbacks after
  repeated opens (`R.ListenerCounts` gauge).
- Nothing in the wizard runs before the recipient asks for it. The Welcome dialog only offers it.
- Choices: the `choices` layer (`LY.Resolve` `opts.choices`, composed already) gets a package schema and validation;
  density becomes a choice.

### 5. Compact Adventure and richer previews (done offline)

Built: the Compact Adventure variant of the same package (capture, shared base, per-variant screen rules), the wizard's
layout choice, the scenarios, the full-size overlay (record below). The UI scale policy (choice `ui-scale`, `applyUIScale`,
D12) and the whole-`EllesmereUIDB` restore point (D3) are **not** part of Phase 5 (the request didn't include them); they
come with the first account-wide unit, in Phase 6 or after.

**Variant differences.** Compact is the author's `TwichUI - Minimal Adventure` EllesmereUI profile (D27). Against Classic it
differs in 7 of 18 module blobs (Action Bars, the Cooldown Manager's tracked-buff group position, Damage Meters' style slots,
QoL, Raid Frames, Resource Bars, Unit Frames) and in the layout links: the unit frames and action bars lie in one low, wide
strip on the bottom edge (bar 1 on bar 2 on the screen's bottom edge, the player and target frames linked to bar 1, bars 4 to 6
below), taller unit frames (63 + 10 high), a wider cast bar, a bar on top of the damage meter, raid and party frames in from the
left edge, a different meter bar texture. Geometry: its own managed block (1091 × 157.5, D28), a left-edge component for the
raid and party frames, bar 7 attached to the meter's top, bars 6 and 7 and the raid and party frames registered as positions,
and a narrow arrangement (chat above the strip below 1780 units, D29).

**Shared values.** The look (fonts, accent, palette, migration stamps: one, a differing key is refused by the capture tool), 11
modules (kept once in the base, each proven identical by fingerprint: Aura/Buff Reminders, Bags, Chat, Data Bars, Dragon Riding,
Friends, Minimap, Mythic Timer, Nameplates, Quest Tracker, Quickdraw), all 206 TwichUI looks and the 5 TwichUI places (D27, D31),
the chat, meter, minimap, objectives, cards and focus components, the densities, the choices (helpers, accent, size) and the
target profile names (D26). Promoting a setting between a variant and the base is moving one module between two tables; a test
shows a base value reaching both layouts and a variant value reaching only its own.

**Preview coverage and limits.** Components: all seven managed ones, from the plan's own geometry. Pieces: 18 EllesmereUI pieces
(unit frames, cast bars, bars 1–7, stance and pet bars, the party frames) plus 5 TwichUI markers, at the install's own
positions with sample sizes. Not drawn: pieces with no size in the data (the Cooldown Manager's bars, class power, data bars, raid
frames) and everything third-party beyond a flat illustration. The limits are in `wizard.md`.

**Tests.** Offline, 121 suites pass (`./tests/run.sh`): new §8–§10 in `test_layout_geometry.lua`, §18 in `test_layouts.lua`,
§12–§17 in `test_layout_wizard.lua` (listed in `wizard.md`, "Phase 5 checks"); mutations made and reverted, each failing a test.
Memory, offline Lua 5.1: Classic's data 880 KB, Compact's only-what-differs 739 KB, both together about 1.6 MB once loaded (the
layouts addon is loaded on demand, so this is paid only when the setup or an install check runs; in-game memory and CPU are not
measured).

**Manual visual checks** are 16–23 in `wizard.md` ("Phase 5 manual checks"), and the in-game checks below still all apply.

### 6a. Authoring and publishing (done offline, 2026-10-27)

The author's Phase 6, built under that number while "Retained overrides and updates" (below, now 6b) stays open. The workflow,
the envelope, the transport extension, the limits, the tests and the manual send and receive checklist are in `publishing.md`;
the contract revisions are `architecture.md` §15.

Built: `LY.Capture` (the allowlist capture, now shared with `tools/layout_capture.lua`, whose output was compared before and
after on a fixture and is identical), `LY.Pub` (envelope, derived metadata, strict checks, media references), `LY.Store`
(bounded published and received lists, kept as the exact packed bytes), `LY.Receive`; in the core `Share.lua`
(`layoutoffer`, `SH:SendLayout`, the receive path) and `LayoutsLauncher.lua` (`L.OpenAuthor`); in the wizard addon `Author.lua`
and `AuthorWindow.lua` (`/tui layout author`), a package source on the wizard's first step, and guards so a package with no
choices still shows every step.

Left open from this work: text export and import of a package (decision, `publishing.md`), and the bundled package's
reference to the author's private `MyFonts` folder (found by the new media check; `publishing.md`, Phase 7 handoff).

### 6b. Retained overrides and updates

Build: the baseline (`TwichUIDB.layouts.baseline`, fingerprints of live values after the reload, §6), retained units
by fingerprint difference (`LY.Compose` already takes `retained` and `reset`), per-unit "reset to the package" in the
review, and updates between package revisions.

### 7. Release hardening and in-game validation

Acceptance:
- Every in-game check below has been run on the packaged artifact, with results recorded here. Classic loses
  `dev = true` only after the Forever checks.
- A fresh account, an existing EllesmereUI user, an existing TwichUI user, re-applying after manual changes,
  switching variants, Restore and Detach: each gives the documented result.
- The release zip holds five folders. `tools/release.py` package checks pass. `CHANGELOG.md` is updated.
- No performance regression in a `/tui perf` General capture with the layouts addon not loaded.

## Phase 6 handoff (retained overrides, 6b)

`wizard.md` ("Phase 6 handoff") has what retained overrides, per-layout TwichUI settings, the UI scale policy, the tooltip
choice and the unplaced positions need. The engine facts Phases 4 and 5 relied on (kept, and still true; the geometry is now
resolved with `opts.variant`, and `plan.geometry.variant` says which layout it is for):

## Phase 4 handoff (used)

What the wizard and preview relied on:
- `LY.Plan(pkg, variant, { screen, density })` returns `plan.geometry`: `{ screen, area, density, factor, narrow,
  order, components = { [id] = { label, managed, rect, ref, dx, dy, notes, applied } }, diagnostics, fits }`. Rects
  are centre offsets in UIParent units (`x, y, w, h, l, r, b, t`), so a preview draws each on a frame the size of the
  screen with `SetPoint("CENTER", parent, "CENTER", x, y)`.
- The plan key covers the screen and density. Re-plan before Apply when the screen changes (`DISPLAY_SIZE_CHANGED`,
  `UI_SCALE_CHANGED` are in Forever's API docs; their timing and payloads are unverified).
- Each part's rows: `place = true` rows are placed positions (`comp`, `sized`), `text = true` rows are scaled text
  sizes, `whole = true` rows are module blobs, links and the look. `part.notes` lists positions not placed, and why.
- `LY.Geometry.Live()` reads the screen; it returns nil when UIParent can't be read, and planning is then refused.

Open before Phase 4: the in-game checks (Phase 2's 1–12 on Forever, Phase 3's visual checklist), D17–D20, the
release decision, and where the wizard lives. Decided in Phase 4: a bare `/tui layout`, a Home section and a
Troubleshooting row; no Welcome offer (D24). The rest is still open.

## Open decisions (recommended default first)

| # | Question | Recommended default |
|---|---|---|
| D1 | What does the brother's interface ("Compact Adventure") consist of? Which addons and modules, and which saved profile is its source (`TwichUI - Minimal Adventure`?) | **Answered in Phase 5 (D27)**: EllesmereUI-based, source `TwichUI - Minimal Adventure` |
| D2 | Is EllesmereUI required for both layouts? | Yes. Without it, only the TwichUI layer is offered, with a clear note |
| D3 | Restore point for EllesmereUI: copy the live `EllesmereUIDB` (no extra reload) or use today's disk scan (one extra reload)? | Phases 2 and 3 need neither (§11.6). Live copy, when Phase 5 manages account-wide units |
| D4 | Exclude Cooldown Manager spell layouts? | Exclude (built) |
| D5 | Exclude window and tooltip skins (`blizzSkinGlobals`)? | Exclude in the first release (built); consider as a wizard choice later |
| D6 | Exclude spec and condition overrides? | Exclude (built) |
| D7 | The EllesmereUI active profile is account-wide, so an install changes every character's HUD. Accept and disclose, or offer to assign it per spec? | Accept and disclose; no spec assignment (built: `autoAssignSpecs = false`; the plan says it) |
| D8 | Install TwichUI settings into a new TwichUI profile (per character) or into the profile in use? | New profile (built) |
| D9 | Target profile names | EllesmereUI `TwichUI Classic` / `TwichUI Compact`; TwichUI `Classic Adventure` / `Compact Adventure` (the test package uses `TwichUI Layout Test` / `Layout Test`) |
| D10 | Suppress EllesmereUI's first-run picker every session, or only while a TwichUI install is planned or pending? | Only while one is under way (built), and refuse to plan while the picker is pending |
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
| D23 | The cursor-following or fixed tooltip choice: not offered (account-wide EllesmereUI global, reset whole by its import, not undone by Restore) | Keep it out until D3 and D5 are built |
| D24 | A Welcome-dialog offer for the wizard | Not built; add only if wanted |
| D25 | Re-running with the same choices re-imports the install's EllesmereUI profile and replaces changes made in it | As built, said in the review; a shortcut needs a content fingerprint of the live profile |

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

## In-game checks still required (whole project)

1. `ImportProfileSilent` on Forever 9.6.x: the profile is created and active after the reload, `cleanSlate`
   replaces only the target, and the result matches the payload.
2. `disableAddons` and the enable states apply at the reload. Enabling sweeps the other suite children as
   documented.
3. `uiScale` in the payload sets `ppUIScale`, `UIParent:GetSize()` matches the computed `W×H`, and `keep` leaves the
   scale alone.
4. `RegisterExternalInstaller` called after EllesmereUI's `ADDON_LOADED` keeps the picker away on a fresh account.
   Without the call, the picker returns.
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