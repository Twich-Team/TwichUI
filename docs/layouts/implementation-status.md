# Layout packages and installer: implementation status

Branch `feature/layout-wizard`. The contract is in `architecture.md` and the evidence in `adapter-capabilities.md`.
Update this file at the end of every phase: what was built, what was checked, and what is still open.

## Status

| Phase | State | Date |
|---|---|---|
| 1. Audit and contract | **Done**: documents only, no code | 2026-10-26 |
| 2. Scaffolding and pure composer | Not started | |
| 3. TwichUI adapter | Not started | |
| 4. EllesmereUI adapter | Not started | |
| 5. Install lifecycle and wizard | Not started | |
| 6. Package content (Classic, Compact) | Not started | |
| 7. Release hardening and in-game validation | Not started | |

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

### 2. Scaffolding and pure composer

Build: a `TwichUI_Layouts/` load-on-demand sibling addon (`.toc` with `RequiredDeps: !!!TwichUI`,
`LoadOnDemand: 1`, no saved variables). Core launcher `R:OpenLayouts()` (the same shape as `SettingsLauncher.L.Load`,
with failure reasons). `TwichUIDB.layouts` defaults and shape checks in `Persist.lua`. Placement in
`RS.OWN_LEFT_OUT` and `TwichConfig.LOCAL`. Release wiring: `.pkgmeta`, `tools/release.py` `ADDONS`, and the
diagnostics addon lists (`Collect.lua` `ReadMemory` and `OURS`, `Export.lua`, `Base.lua`, `Window.lua`). Pure
modules: package validator, `Compose`, the coordinate transform (§7), and the canonical fingerprint (§6).

Acceptance:
- The core loads and runs with `TwichUI_Layouts` missing, disabled or erroring. The launcher reports each reason.
- The composer is pure: the same inputs give the same output, and it makes no `_G` or game API calls (enforced by
  the test's stub environment).
- The precedence tests cover all six layers, `REMOVE`, unmanaged units untouched, retained units winning, and a
  reset removing retention.
- Coordinate tests: left, centre and right affinity across 1920×1080, 2560×1440, 3840×2160 and 3440×1440 at several
  scales. Clamping holds. Anchored entries and non-CENTER entries are left alone.
- The fingerprint ignores key order, distinguishes `false`, `0`, `""` and missing, and refuses cycles, depth and size
  overruns.
- The package validator refuses a newer `format`, unknown IDs, duplicate IDs and oversized fragments.
- `tests/test_release_tools.py` and `tests/test_backup_own.lua` pass with the new addon and key.
- Diagnostics: the `layouts.load` scope is registered in `DX.OPS` and `docs/diagnostics.md`. Memory of the new
  addon is reported.

### 3. TwichUI adapter

Build: `Detect`, `Capture`, `Normalize`, `Validate`, `Compose`, `Plan`, `Apply`, `Verify`, `Restore` over the
TwichConfig schema, plus a `places` map. Read each listed position key's real format. Add a converter, or leave the
key unmanaged and document why. Profile handling: duplicate the current profile into the target, then switch.

Acceptance:
- No `acts`, `network` or `other` key in `TC.LOCAL` can be written by a package (a test walks the schema).
- Apply goes through `TC.Plan` validation and `Profiles.Refresh`. A stale plan is refused, and so is combat.
- Verify reports a match for every unit after Apply, and a mismatch for a unit changed afterwards.
- Restore and Undo put back exactly the values captured before. Other profiles and other characters' choices are
  unchanged.
- Pins, the Chronicle, NPC knowledge, reminders, backups and received setups are byte-identical before and after.

### 4. EllesmereUI adapter

Build: decode the base string, insert module blobs from higher layers, patch registered positions (rounded to whole
units), strip the exclusions, encode, then `ImportProfileSilent` (`cleanSlate`, `applyUIScale`,
`autoAssignSpecs = false`, `disableAddons`). Restore point: a live copy of `EllesmereUIDB` plus suite enable states.
Verify after the reload. `RegisterExternalInstaller` only while an install is planned or pending.

Acceptance (with a stand-in `EllesmereUI`, as `tests/test_ellesmere_share.lua` and `tests/test_marker_bar.lua`
already use):
- The payload sent to import never contains `cdmSpells`, overrides, `assignedSpecs`, `blizzSkinGlobals`, `clickCast`
  or keybinds, and contains `uiScale` only when the plan says so.
- The payload holds every module the package manages, so nothing is inherited from the recipient's active profile.
- No profile other than the TwichUI target is created, deleted or replaced (snapshot comparison, as in `ES.Apply`).
- A failed import leaves no half-made profile and restores the previously active profile.
- `"spec_locked"` is reported as stored but not active.
- The restore point round-trips: applying it puts back the exact `EllesmereUIDB` and enable states.
- Missing API, not `IS_FOREVER`, too old, or newer than tested: each gives the documented result.
- Diagnostics: `layouts.apply.eui` and `layouts.verify` scopes are registered.

### 5. Install lifecycle and wizard

Build: the journal state machine (§8), the wizard window in TwichUI's own look (`Look.lua`, standalone without
EllesmereUI): pick a variant, make choices, review the plan, confirm, reload. Verification at login (the layouts
addon is loaded only when the journal says so), a result card, Detach, Restore, and an update with retained
overrides. Entry points: the Welcome dialog, settings (Home or a Layout page through `R:OpenSettings`) and a
`/tui layout` subcommand (hidden from bare help if the 20-line cap requires it).

Acceptance:
- Every state survives `/reload` and a crash between states. A stale `applied` journal with no matching profile is
  reported, not looped on.
- Combat refuses Apply and Restore in the central functions. The window's disabled controls explain why.
- The review names: the account-wide EllesmereUI profile change, the TwichUI profile used, the reload, retained
  units, exclusions, and what Restore will and won't undo.
- Escape, focus and reopening behave as in the settings window. No duplicate frames, hooks or callbacks after
  repeated opens (`R.ListenerCounts` gauge).
- Nothing in the wizard runs before the recipient asks for it. The Welcome dialog only offers it.

### 6. Package content

Build (needs the author): EllesmereUI export strings for the shared base and each variant from the author's install,
the TwichUI presets per variant, the position registry with edge affinities, the reference canvas, the choice list
and the target profile names.

Acceptance:
- The package passes the validator. Every managed module is present in the base.
- On the reference canvas, a composed install reproduces the author's layout (positions within 1 unit).
- Each variant reads as intended on 1080p, 1440p, 4K and ultrawide (screenshots reviewed by the author).
- Nothing personal is in the strings (names, gold, character lists, chat). A test scans for the known private keys.

### 7. Release hardening and in-game validation

Acceptance:
- Every in-game check below has been run on the packaged artifact, with results recorded here.
- A fresh account, an existing EllesmereUI user, an existing TwichUI user, re-applying after manual changes,
  switching variants, Restore and Detach: each gives the documented result.
- The release zip holds five folders. `tools/release.py` package checks pass. `CHANGELOG.md` is updated.
- No performance regression in a `/tui perf` General capture with the layouts addon not loaded.

## Open decisions (recommended default first)

| # | Question | Recommended default |
|---|---|---|
| D1 | What does the brother's interface ("Compact Adventure") consist of? Which addons and modules, and is an EllesmereUI export string of it available? | Needed before Phase 6. Assume EllesmereUI-based |
| D2 | Is EllesmereUI required for both layouts? | Yes. Without it, only the TwichUI layer is offered, with a clear note |
| D3 | Restore point for EllesmereUI: copy the live `EllesmereUIDB` (no extra reload) or use today's disk scan (one extra reload)? | Live copy; EllesmereUI is single-storage |
| D4 | Exclude Cooldown Manager spell layouts? | Exclude |
| D5 | Exclude window and tooltip skins (`blizzSkinGlobals`)? | Exclude in the first release; consider as a wizard choice later |
| D6 | Exclude spec and condition overrides? | Exclude |
| D7 | The EllesmereUI active profile is account-wide, so an install changes every character's HUD. Accept and disclose, or offer to assign it per spec? | Accept and disclose; no spec assignment |
| D8 | Install TwichUI settings into a new TwichUI profile (per character) or into the profile in use? | New profile ("Classic Adventure" / "Compact Adventure") |
| D9 | Target profile names | EllesmereUI `TwichUI Classic` / `TwichUI Compact`; TwichUI `Classic Adventure` / `Compact Adventure` |
| D10 | Suppress EllesmereUI's first-run picker every session, or only while a TwichUI install is planned or pending? | Only while planned or pending |
| D11 | Reference canvas | 2560×1440 UIParent units (pixel-perfect 1440p) |
| D12 | UI scale choice factors (`larger`, `smaller`) | ×1.15 and ×0.87 of pixel-perfect, clamped to 0.40–1.15 |
| D13 | Without EllesmereUI, should TwichUI ever set the game's `uiScale` CVar? | No |
| D14 | Wizard choices in the first release | Variant, UI scale, opt-out of Chat, Minimap, Damage Meters, Quest Tracker and Bags modules, and up to five TwichUI feature toggles |
| D15 | Should Blizzard Edit Mode layouts join a later phase? | Later phase, after an in-game spike |

## In-game checks still required

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
   "profile corrupted" warning from `NewDB`.
7. Positions survive the reload unchanged (no TOPLEFT re-migration or pixel snap beyond 1 unit) on 1080p, 1440p, 4K
   and ultrawide.
8. Another character on the same account sees the EllesmereUI layout, and their TwichUI profile is unchanged (D7, D8).
9. Combat: Apply and Restore are refused. The reload button is not offered in combat.
10. The packaged install loads `TwichUI_Layouts` on demand. A missing or disabled copy is reported, and the core is
    unaffected.

## Phase 2 handoff

Start here. Read `architecture.md` §1, §5, §6, §7 and §10 only; Phase 2 needs nothing else.

1. Create `TwichUI_Layouts/` with a `.toc` copied from `TwichUI_Settings/TwichUI_Settings.toc`'s fields
   (`RequiredDeps`, `LoadOnDemand`, the same Interface and Version). Wire `.pkgmeta` (unquoted key),
   `tools/release.py` `ADDONS` and `tests/test_release_tools.py`.
2. Add a core launcher modelled on `!!!TwichUI/SettingsLauncher.lua` `L.Load`/`L.Explain`.
3. Add `TwichUIDB.layouts` (`install`, `baseline`, `choices`) to `Persist.lua` normalization (fill only missing). Place
   it in `setup/Restore.lua` `RS.OWN_LEFT_OUT` and `setup/TwichConfig.lua` `TC.LOCAL`.
4. Write pure modules in the layouts addon (`Package.lua` validator, `Compose.lua`, `Coords.lua`, `Fingerprint.lua`)
   and `tests/test_layouts_compose.lua` covering Phase 2's acceptance list. Use a synthetic package; real strings
   come in Phase 6.
5. Diagnostics: add the `layouts.load` scope and the new addon's memory to the diagnostics addon (CLAUDE.md
   "Diagnostics coverage").
6. Do not write any adapter, any EllesmereUI call or any UI in Phase 2.

Decisions D2, D11 and D12 affect Phase 2 tests. Use the recommended defaults unless the author changes them.
