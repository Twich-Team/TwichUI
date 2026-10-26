# Layout packages and installer: implementation status

Branch `feature/layout-wizard`. The contract is in `architecture.md` (§11 has the revisions Phase 2 made) and the
evidence in `adapter-capabilities.md`. Update this file at the end of every phase: what was built, what was checked,
and what is still open.

## Status

| Phase | State | Date |
|---|---|---|
| 1. Audit and contract | **Done**: documents only, no code | 2026-10-26 |
| 2. Engine and safe application pipeline | **Done offline**: automated checks pass; nothing run in game | 2026-10-26 |
| 3. Wizard and install lifecycle UI | Not started | |
| 4. Screen adaptation and positions | Not started | |
| 5. Package content (Classic, Compact) | Not started | |
| 6. Retained overrides and updates | Not started | |
| 7. Release hardening and in-game validation | Not started | |

Phase 2 was re-scoped by the author: instead of scaffolding and a pure composer only, it builds the whole pipeline
(validation, composing, both adapters, snapshot, apply, verify, restore, the install record) for one small developer
package. Phase 1's Phases 2–4 are covered as far as that package needs; what they listed and Phase 2 did not build is
under Phases 4–6 below. The phase numbers after 2 are a proposal for the author to confirm.

Nothing in this project has been run in game.

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
{ state, at, diffs (≤ 8) }, restore = { at, steps } }`. Fingerprints, not copies; bounded by 96 units per adapter (the
test package's record is under 4 KB of canonical text). Removed once a restore checks out.

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
precedence tests (done for base, variant, preset, choices, retained, reset); coordinate tests (moved to Phase 4);
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
wizard, add `TwichUI_Layouts` to `.pkgmeta` `ignore` and take it out of `tools/release.py` `ADDONS` until Phase 3.

### 3. Wizard and install lifecycle UI

Build: the wizard window in TwichUI's own look (`Look.lua`, standalone without EllesmereUI): pick a variant, make
choices, review the plan (from `LY.Plan`; the window shows exactly the plan whose key it passes to `LY.Apply`), confirm,
reload button (a click, never automatic). The after-login result card (in place of `LY.Tell`'s chat lines), Detach,
Restore (its own review), and the entry points: the Welcome dialog (offer only), settings (Home or a Layout page
through `R:OpenSettings`) and `/tui layout` (the developer subcommands stay hidden).

Acceptance:
- The review names: the account-wide EllesmereUI profile change, the TwichUI profile used, the reload, exclusions,
  and what Restore will and won't undo (changes made in the install's profiles go with them).
- Combat refuses Apply and Restore centrally (done in Phase 2); the window's disabled controls explain why.
- Escape, focus and reopening behave as in the settings window. No duplicate frames, hooks or callbacks after
  repeated opens (`R.ListenerCounts` gauge).
- Nothing in the wizard runs before the recipient asks for it. The Welcome dialog only offers it.
- Choices: the `choices` layer (`LY.Resolve` `opts.choices`, composed already) gets a package schema and validation.

### 4. Screen adaptation and positions

Build: the coordinate transform (§7), the position registry and `canvas`, TwichUI `places` with a converter per
position key (or left unmanaged with the reason), EllesmereUI `positions`, the UI scale policy (choice `ui-scale`,
`applyUIScale`), and the whole-`EllesmereUIDB` restore point (D3) once anything account-wide is managed.

Acceptance:
- Coordinate tests: left, centre and right affinity across 1920×1080, 2560×1440, 3840×2160 and 3440×1440 at several
  scales. Clamping holds. Anchored entries and non-CENTER entries are left alone.
- The payload holds `uiScale` only when the plan says so; Verify checks `UIParent:GetSize()` against the plan.
- Restore puts back the UI scale and any enable state the install changed.

### 5. Package content

Build (needs the author): EllesmereUI export strings for the shared base and each variant from the author's install,
the TwichUI presets per variant, the position registry with edge affinities, the reference canvas, the choice list
and the target profile names.

Acceptance:
- The package passes the validator. Every managed module is present in the base.
- On the reference canvas, a composed install reproduces the author's layout (positions within 1 unit).
- Each variant reads as intended on 1080p, 1440p, 4K and ultrawide (screenshots reviewed by the author).
- Nothing personal is in the strings (names, gold, character lists, chat). A test scans for the known private keys.

### 6. Retained overrides and updates

Build: the baseline (`TwichUIDB.layouts.baseline`, fingerprints of live values after the reload, §6), retained units
by fingerprint difference (`LY.Compose` already takes `retained` and `reset`), per-unit "reset to the package" in the
review, and updates between package revisions.

### 7. Release hardening and in-game validation

Acceptance:
- Every in-game check below has been run on the packaged artifact, with results recorded here.
- A fresh account, an existing EllesmereUI user, an existing TwichUI user, re-applying after manual changes,
  switching variants, Restore and Detach: each gives the documented result.
- The release zip holds five folders. `tools/release.py` package checks pass. `CHANGELOG.md` is updated.
- No performance regression in a `/tui perf` General capture with the layouts addon not loaded.

## Phase 3 prerequisites (exact)

1. The Phase 2 in-game checks above, 1–12, run and recorded here. 2, 5, 6 and 7 decide whether the restore path and
   the after-reload check can be trusted by a wizard.
2. The author confirms the phase plan above (3 = wizard), and D2, D7 (disclose the account-wide EllesmereUI profile),
   D8 (a new TwichUI profile), D9 (names; now `targets` in the package) and D14 (the first release's choices).
3. The release decision above: ship `TwichUI_Layouts` now, or ignore it until the wizard.
4. A package with at least two variants to choose between: Phase 5 content (D1), or a second developer variant.
5. Where the wizard lives: the Welcome dialog's offer, the settings entry (Home or a Layout page), and what a bare
   `/tui layout` does once the wizard exists.

## Open decisions (recommended default first)

| # | Question | Recommended default |
|---|---|---|
| D1 | What does the brother's interface ("Compact Adventure") consist of? Which addons and modules, and is an EllesmereUI export string of it available? | Needed before Phase 5. Assume EllesmereUI-based |
| D2 | Is EllesmereUI required for both layouts? | Yes. Without it, only the TwichUI layer is offered, with a clear note |
| D3 | Restore point for EllesmereUI: copy the live `EllesmereUIDB` (no extra reload) or use today's disk scan (one extra reload)? | Phase 2 needs neither (§11.6). Live copy, when Phase 4 manages account-wide units |
| D4 | Exclude Cooldown Manager spell layouts? | Exclude (built) |
| D5 | Exclude window and tooltip skins (`blizzSkinGlobals`)? | Exclude in the first release (built); consider as a wizard choice later |
| D6 | Exclude spec and condition overrides? | Exclude (built) |
| D7 | The EllesmereUI active profile is account-wide, so an install changes every character's HUD. Accept and disclose, or offer to assign it per spec? | Accept and disclose; no spec assignment (built: `autoAssignSpecs = false`; the plan says it) |
| D8 | Install TwichUI settings into a new TwichUI profile (per character) or into the profile in use? | New profile (built) |
| D9 | Target profile names | EllesmereUI `TwichUI Classic` / `TwichUI Compact`; TwichUI `Classic Adventure` / `Compact Adventure` (the test package uses `TwichUI Layout Test` / `Layout Test`) |
| D10 | Suppress EllesmereUI's first-run picker every session, or only while a TwichUI install is planned or pending? | Only while one is under way (built), and refuse to plan while the picker is pending |
| D11 | Reference canvas | 2560×1440 UIParent units (pixel-perfect 1440p) |
| D12 | UI scale choice factors (`larger`, `smaller`) | ×1.15 and ×0.87 of pixel-perfect, clamped to 0.40–1.15 |
| D13 | Without EllesmereUI, should TwichUI ever set the game's `uiScale` CVar? | No |
| D14 | Wizard choices in the first release | Variant, UI scale, opt-out of Chat, Minimap, Damage Meters, Quest Tracker and Bags modules, and up to five TwichUI feature toggles |
| D15 | Should Blizzard Edit Mode layouts join a later phase? | Later phase, after an in-game spike |
| D16 | Strip `customColors` from every payload (Phase 2 does), or manage colours as a look unit with its own restore? | Strip until look units exist (Phase 4 or later) |

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
11. The Phase 2 checks above.
