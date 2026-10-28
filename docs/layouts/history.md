# Layout packages: history of the contract and the phases

This file keeps, as they were written, the records that the current documents replaced in the release-hardening pass
(**RH-1**, 2026-10-28). They explain how the contract got where it is. **None of it is the contract**: `architecture.md` is the
one current contract, `updates.md`, `wizard.md`, `publishing.md` and `updating-the-bundled-layout.md` describe their parts as
they are now, and `implementation-status.md` says what is built, tested offline, waiting for in-game checks, unsupported or
deferred. Where anything below disagrees with those, they win; nothing here is kept in step with the code.

Contents: the architecture contract as written in Phase 1 with the revisions Phases 2 to 7 made to it (§1–§16, in the
"later section wins" form RH-1 replaced); the phase records from `implementation-status.md` (Phases 1 to 7, with their in-game
checklists and acceptance lists); the handoff and "additions" notes from `wizard.md` and `publishing.md`, and the wizard's
decision tables (the decisions themselves are in `implementation-status.md`).

## The architecture contract as written (Phase 1) and revised (Phases 2 to 7)

This is the contract for TwichUI's layout packages: two complete interface experiences, **Classic Adventure** and
**Compact Adventure**, built from shared configuration and installed by a TwichUI wizard. It was written in Phase 1
(audit, 2026-10-26). Phase 2 (2026-10-26) built the engine and the apply/verify/restore pipeline for a small developer
test package (`TwichUI_Layouts/`); **§11 lists every place where that implementation revised this contract**, and
those revisions win over the text above them. Phase 3 (2026-10-26) added the screen layer and the first author layout,
Classic Adventure; **§12 lists its revisions**, which win over §1–§11. Phase 4 (2026-10-26) added the setup wizard and the
package `choices`; **§13 lists its revisions**, which win over §1–§12. Phase 5 (2026-10-26) added Compact Adventure as the
second variant of the same package, per-variant screen rules and the full-size preview; **§14 lists its revisions**, which
win over everything above. Phase 6 (2026-10-27) added the authoring workspace, the publication envelope and the transport
extension; **§15 lists its revisions**, which win over §1–§14. Phase 7 (2026-10-27) added updates that keep the recipient's
changes, the baseline, the management record and Undo this update; **§16 lists its revisions**, which win over everything above
(`updates.md` is the authoritative description; §6's fingerprint-only baseline and Detach-as-the-way-to-leave are superseded). `adapter-capabilities.md` holds the source evidence for each integration, and
`implementation-status.md` tracks the phases and the open decisions.

Words used here:

- **Package**: the data TwichUI ships for both layouts (layers, choices, adapter fragments).
- **Adapter**: TwichUI's code for one integration: TwichUI itself, or the EllesmereUI suite.
- **Unit**: the smallest thing an adapter manages and records. A higher layer replaces a unit as a whole.
- **Install**: one run of the wizard that applies a composed layout, reloads and verifies it.

Labels used in this document: **[source]** means read in code (TwichUI, the reference addons or the Forever UI
source). **[in-game]** means it still has to be checked in the client. **[decision]** means a recommended default that
needs the author's confirmation (listed in `implementation-status.md`).

### 1. Composition

```
Shared suite base → Layout variant → TwichUI feature preset → Wizard choices → Screen adaptation → Retained recipient overrides
   (lowest)                                                                                              (highest)
```

TwichUI does the composing. It never relies on a downstream addon's profile inheritance. EllesmereUI has no
inheritance anyway: an import copies the recipient's **active** profile and replaces whole module blobs
([source] `EllesmereUI.ImportProfile`, `EllesmereUI_Profiles.lua:3330-3336`). For each adapter, composition is a pure
function `Compose(package, variantId, choices, screen, retained) -> desired` with no game calls, so it can be tested
offline.

| # | Layer | What it supplies | Who writes it |
|---|---|---|---|
| 1 | Shared suite base | Every managed unit that both layouts share: the look, fonts, colours, common module settings | Author (package) |
| 2 | Layout variant | `classic-adventure` or `compact-adventure`: replaces units (module blobs, positions, sizes) | Author (package) |
| 3 | TwichUI feature preset | Which TwichUI features a variant turns on, and their looks (TwichUI adapter only) | Author (package) |
| 4 | Wizard choices | The recipient's picks: variant, UI scale policy, optional modules, a few TwichUI features | Recipient (wizard) |
| 5 | Screen adaptation | A transform of the positions from layers 1–4, plus the UI scale, for this screen | Computed at install |
| 6 | Retained recipient overrides | Units the recipient changed after a previous install; they win unless reset | Detected (§6) |

Rules:

- **Precedence is per unit.** The highest layer that names a unit decides it. Below the unit there is no deep merge:
  a list or a module blob is replaced whole.
- **Screen adaptation is a function, not stored values.** It runs on the composed result of layers 1–4 and changes
  only registered position units and the UI scale (§7). A retained unit is never adapted again.
- **A layer can remove a unit** with the `REMOVE` sentinel, which means "inherit the layer below". If no layer below
  names the unit, it becomes unmanaged: TwichUI no longer touches or records it.
- **Unmanaged units are never written.** Anything outside the managed categories (§3) keeps the recipient's value.

### 2. First-release supported addons

| Adapter id | Covers | Status |
|---|---|---|
| `twichui` | TwichUI's own settings: the feature groups already defined in `setup/TwichConfig.lua`, plus the TwichUI positions listed in §3 | Supported |
| `ellesmereui` | The EllesmereUI suite through its partner-installer API: core look, every module in `ADDON_DB_MAP` (Action Bars, Unit Frames, Nameplates, Raid Frames, Resource Bars, Cooldown Manager, AuraBuff Reminders, QoL, Bags, Friends, Quest Tracker, Minimap, Damage Meters, Chat, DataBars, Quickdraw, Mythic Timer, Dragon Riding), the unlock layout, the UI scale and module enable states | Supported |

The chat, objectives, minimap and damage-meter surfaces are covered by EllesmereUI's Chat, Quest Tracker, Minimap and
Damage Meters modules. Those are the only implementations of these surfaces in `../reference_addons/` and in the
author's installed AddOns. There is no Details!, Prat or other standalone replacement to integrate with.

Not supported in the first release, each with its reason:

| Not supported | Why |
|---|---|
| Blizzard Edit Mode layouts | `C_EditMode` import (`ConvertStringToLayoutInfo`, `SaveLayouts`, `SetActiveLayout`) is documented in Forever [source] but has never been exercised by TwichUI. Layout scope (account or character) and taint are unverified. EllesmereUI replaces most of the frames Edit Mode places. Candidate for a later phase. |
| Blizzard chat windows, tabs and channel membership | Per-character client chat configuration (FCF), outside any addon profile. EllesmereUI Chat skins these frames but does not own their tabs or channels [source]. |
| Game CVars (graphics, `uiScale`, `useUiScale`) | EllesmereUI owns the UI scale by calling `UIParent:SetScale(ppUIScale)` directly [source `EllesmereUI_Startup.lua`]. Changing CVars as well would fight it. Without EllesmereUI, see the open question on UI scale. |
| RestedXP, SpeakStone, Attune and other skinned addons | Their own settings are not part of a layout. TwichUI's skin settings for them stay in the `twichui` adapter. |
| NaowhForever | Its own suite and presets. Reference only: the license is all rights reserved. |

**[decision]** EllesmereUI is required for both layouts. Without it the wizard offers only the TwichUI layer and
says clearly that the HUD is not installed.

### 3. Managed setting categories

#### `twichui` adapter

| Category | Units | Source of truth |
|---|---|---|
| Feature switches | `modules.<key>` for switches in TwichConfig groups | `TwichConfig.Define` groups (`Switches(...)`) |
| Feature looks and behaviour | `<slot>.<key>` fields of TwichConfig groups (`ui.*`, named tables) | `TwichConfig.Define` |
| List groups | Restock items, chat-clean channels and rules, known ammunition, healer phrases, class-bar overrides: **one unit per group**, replaced whole (unlike sharing, which merges them) | TwichConfig custom groups |
| Positions (new to layouts) | `ui.classBarsPosition`, `ui.markerBarPosition`, `ui.foodDrinkPosition`, `ui.navigation.position`, `ui.navigation.arrowPosition`, `ui.refreshments.position`, `ui.trainingPosition`, `ui.welcomeBackPlace`, `ui.friendLoginPlace`, `ui.partyPins.position`, `ui.healerWatch.point/x/y`, `ui.cozyBag` | Each feature's own setter |

Never managed by a layout, even though a feature owns it:

- every key in `TwichConfig.LOCAL` with reason `acts` (selling, auto-fill, summons, resurrect, duels, release,
  guide waypoint and auto-hide, restock, `restockAck`, conjure) or `network` (sharing, accepting setups, group check,
  party pins, map pings, NPC map, `shareTransport`);
- `PF.ACCOUNT` keys, `gear` weights and trees, `reminders` and `ui.reminders`, and everything under reason `other`.

Positions are `place` in `TwichConfig.LOCAL` because sharing must not move another player's windows. A layout
package, made by the author for a layout the recipient chose, does manage them. That is the layout adapter's own
category; config sharing is unchanged.

#### `ellesmereui` adapter

Units are the parts of a decoded EllesmereUI profile payload (`payload.data`) [source `ImportProfile`]:

| Category | Unit | Notes |
|---|---|---|
| Module settings | `addons[<canon>]`, one unit per module (canonical key `EllesmereUI<suffix>`) | Replaced whole by EllesmereUI's import |
| Look | `fonts`, `customColors`, `darkMode`, `euiAccent`, whole-UI window look (profile root): one unit each | Only applied if present in the payload |
| Layout relationships | `unlockLayout` (anchors, size matches): **one unit** | EllesmereUI merges imported relationships per module |
| Element positions | Registered position entries inside module blobs (`{point, relPoint, x, y}`), e.g. Minimap `position`, Chat `chatPosition` and `toastPosition` | Sub-units of a module blob, used only by screen adaptation and retention (§6, §7) |
| UI scale | `uiScale` → `EllesmereUIDB.ppUIScale` (range 0.40–1.15) | Written by EllesmereUI's import when present |
| Module composition | Enable state of each suite child addon (`disableAddons`) | Takes effect at reload |

Excluded from the payload before import:

| Excluded | Reason |
|---|---|
| `cdmSpells` (Cooldown Manager spell layouts) | Class and spell choices are action-like and personal [decision] |
| `specOverrides`, `condOverrides`, `specUnlockOverrides`, `condUnlockOverrides`, `assignedSpecs` | Per-spec personal systems; `autoAssignSpecs = false` |
| `blizzSkinGlobals`, `applyBlizzSkinGlobals` | Account-wide window skins; out of scope until approved [decision] |
| `clickCast`, `spellAssignments`, profile keybinds, gold or character data | Already stripped or never exported by EllesmereUI [source]; listed so a test asserts it |

#### Default exclusions (both adapters)

These are never in a package, never captured into a baseline and never written: keybindings, action assignments,
character and account identities, NPC knowledge (`npcs`), chat history (`EllesmereUIChatScrollDB`), caches and runtime
state, diagnostics recordings, personal reminder rules, and unrelated profiles and settings. Other EllesmereUI profiles
are never edited. The one exception is the TwichUI-named target profile, which `cleanSlate` replaces (§6).

### 4. Adapter contract

There are exactly two adapters, as plain Lua tables in a small registry inside the layouts addon. This is not a
general framework. Every function returns plain data. Only `Apply` and `Restore` change game state.

```lua
adapter = {
    id = "twichui" | "ellesmereui",
    contract = 1,                                  -- this contract's version
    Detect    = function() return { present, loaded, version, usable, why } end,
    Capture   = function(scope) return snapshot end,            -- scope: "restore" | "baseline"
    Normalize = function(fragment) return fragment end,         -- package/author data -> canonical units
    Validate  = function(fragment) return ok, problems end,     -- types, ranges, known units, size bounds
    Compose   = function(layers, choices, screen, retained) return desired end,   -- pure
    Plan      = function(desired, current) return plan end,     -- per-unit changes, reload, combat, target names
    Apply     = function(plan, ctx) return result end,          -- { applied, failed, reload = true|false }
    Verify    = function(desired) return report end,            -- { state, diffs, unverifiable }
    Restore   = function(snapshot) return result end,
    Fingerprint = function(unitId, value) return hash end,      -- canonical, order-independent (§6)
}
```

Obligations:

- **Validate before touching anything.** The checks follow TwichConfig's (`KIND`, `ENUM`, feature `LIMITS`). For
  EllesmereUI they also include the `ST.CheckData` bounds and the `ES.LIMITS` bounds. One invalid unit refuses the
  whole adapter fragment. A partial layout is never applied.
- **Plan is what the wizard shows**, and `Apply` re-plans and refuses if the plan's key changed. This is the
  `TwichConfig.PlanKey` / `expect` pattern.
- **Apply is refused in combat**, checked inside `Apply`, not only by the window.
- **Verify reads only live state.** It never repairs. An unreadable unit is reported as `unverifiable`, not as a match.
- **`twichui` reuses existing paths:** `TwichConfig` validation and `Plan`, plain assignments, then
  `Profiles.Refresh("layout")`. Feature setters are used for positions.
- **`ellesmereui` calls only EllesmereUI's public functions:** `DecodeImportString`, `EncodePayload`,
  `ImportProfileSilent`, `GetProfileList`, `GetActiveProfileName`, `GetProfilesDB`, `DeleteProfile`,
  `SwitchProfile`, `RegisterExternalInstaller`, `IsModuleAddonLoaded`. It never calls `ApplyProfileData` or
  writes `EllesmereUIDB` directly, except through the restore point (§8).

### 5. Package schema and stable IDs

The package is Lua data in the load-on-demand addon (§10). Nothing is ever loaded with `loadstring`.

```lua
TwichUILayouts.PACKAGE = {
    format = 1,                                   -- package shape; a newer format is refused
    id = "twichui-layouts",
    made = "2026-..", tested = { ellesmereui = "9.6.8" },
    canvas = { w = 2560, h = 1440 },              -- reference UIParent size, in UIParent units (§7)
    requires = { ellesmereui = { min = "9.6.6", forever = true,
                 api = { "ImportProfileSilent", "DecodeImportString", "EncodePayload", "RegisterExternalInstaller" } } },
    layers = {
        base     = { twichui = { ... }, ellesmereui = { ... } },
        variants = { ["classic-adventure"] = { ... }, ["compact-adventure"] = { ... } },
        presets  = { ["classic-adventure"] = { twichui = { ... } }, ["compact-adventure"] = { twichui = { ... } } },
    },
    choices = { { id = "ui-scale", kind = "enum", values = { "auto", "keep", "larger", "smaller" }, default = "auto" }, ... },
    positions = { ["ellesmereui:minimap"] = { unit = "...", h = "right", v = "top" }, ... },   -- §7 registry
}
```

Adapter fragments:

- `twichui`: `{ groups = { [group] = { [slot] = { [key] = value } } }, places = { [placeKey] = value } }`. This is
  TwichConfig's existing shape, so `TC.CleanEntry` rules apply, plus a `places` map.
- `ellesmereui`: `{ base = "<EUI export string>" }` in the base layer. Higher layers give
  `{ modules = { [canon] = "<EUI export string holding that module>" | REMOVE }, positions = { [posId] = {x, y} },
  look = {...} }`. Strings are made with EllesmereUI's own `ExportProfile` from the author's install, so their inner
  shape is EllesmereUI's, not TwichUI's.

Stable IDs (lower-kebab or `adapter:name`; never reused or renamed once released; renaming means a new ID plus a
migration entry):

| Kind | Form | Examples |
|---|---|---|
| Variant | `<name>` | `classic-adventure`, `compact-adventure` |
| Choice | `<name>` | `ui-scale`, `module-damage-meters` |
| Adapter | `<name>` | `twichui`, `ellesmereui` |
| Unit | `<adapter>:<path>` | `twichui:ui.markerBarPosition`, `ellesmereui:addons.EllesmereUIMinimap`, `ellesmereui:look.fonts` |
| Position | `<adapter>:<element>` | `ellesmereui:minimap`, `twichui:marker-bar` |
| Target profile | Fixed display names | EllesmereUI `TwichUI Classic` / `TwichUI Compact`; TwichUI `Classic Adventure` / `Compact Adventure` [decision] |

### 6. Merge, reset, removal and retained overrides

- **Merge**: per unit, highest layer wins (§1). Inside an EllesmereUI install the payload holds every managed module,
  so nothing is inherited from the recipient's active profile by accident. **Units the payload leaves out are
  inherited from the active profile** [source `ImportProfile`], so the base layer must hold every module the
  package manages.
- **Baseline**: after the reload that finishes an install, `Verify` takes a fingerprint of each managed unit's
  **live** value, after EllesmereUI's load-time defaults and migrations. These go in `TwichUIDB.layouts.baseline`:
  `{ [unitId] = hash }`, fingerprints only, no copies. The number of units bounds its size. *Superseded by §16.1: comparable
  units are stored as values, with the recommended, applied and read-back values apart.*
- **Retained recipient override**: a unit whose live fingerprint differs from its baseline. Re-running the wizard
  (an update or a variant change) keeps those units by default. The plan lists them, and the recipient can tick
  "reset to the package" per unit or for everything. Granularity: TwichUI by key; EllesmereUI by module blob and by
  registered position. A change anywhere inside a module blob retains the whole module.
- **Reset**: removes retention for the chosen units and applies the composed value. It is a normal install.
- **Detach** (the default way to leave): stop managing. The journal and baseline are cleared and every value stays
  as it is. *Superseded by §16.3: finishing a setup (`LY.Finish`) keeps managing; Detach is "Stop managing".*
- **Restore**: put back the restore point taken before the install (§8). It is destructive for changes made since,
  and the confirmation says so.
- **Fingerprint**: a canonical walk with sorted keys, numbers written with `%.17g`, and bounded depth and size like
  `ST.CheckData`. It is not LibSerialize output, because that depends on `pairs` order.
- **EllesmereUI target profile**: installs replace only the TwichUI-named profile (`cleanSlate = true`, which goes
  through EllesmereUI's `DeleteProfile` so name-keyed stores are purged). The recipient's other profiles are never
  edited. The `ES.Apply` snapshot and verify pattern checks that.

### 7. Coordinate conventions

- **Canonical form**: the offset of an element's centre from UIParent's centre, in UIParent units. TwichUI already
  uses this (`classbars/Config.lua` `ui.classBarsPosition`, `markers/Bar.lua`, `modules/FoodDrinkUnlock.lua`,
  `nav/Unlock.lua`, `modules/RefreshmentsPanel.lua`). So does EllesmereUI: "All elements store positions as
  CENTER/CENTER (offset from UIParent center)" (`EUI_UnlockMode_Positions.lua:2200`, `ConvertToCenterPos`).
- **Reference canvas**: package positions are written for `canvas = { w, h }` in UIParent units (2560×1440 at
  pixel-perfect scale is suggested [decision]).
- **Edge affinity**: each registered position declares `h = left|center|right` and `v = bottom|center|top`. For a
  target UIParent size `W×H`:
  - `left`: keep the distance to the left edge: `x' = (x + w/2) - W/2`
  - `right`: keep the distance to the right edge: `x' = W/2 - (w/2 - x)`
  - `center`: keep `x`. The same rules apply to `y` with `bottom`, `top` and `center`.
  - Then clamp so the element stays on screen, as `CB.ClampPosition` does.
- **Anchored elements are not adapted.** An element anchored to another through EllesmereUI's `unlockLayout` moves
  with its target.
- **Only CENTER/CENTER entries are adapted.** A stored entry in another point format is left as it is and reported.
- **Target size**: before the reload, the UIParent size is computed from `GetPhysicalScreenSize()` and the target UI
  scale `s`: `H = 768 / s`, `W = 768 * physW / physH / s` [source: Forever `ScreenDocumentation.lua`; EllesmereUI
  `PixelPerfect.lua` `PP.perfect = 768 / physH`]. [in-game] After the reload, check that `UIParent:GetSize()`
  matches.
- **UI scale policy** (choice `ui-scale`): `auto` = `clamp(768 / physH, 0.40, 1.15)`; `keep` = strip `uiScale` from
  the payload (`applyUIScale = false`); `larger` and `smaller` = `auto` × 1.15 and × 0.87, then clamped [decision on
  the factors].
- **TwichUI positions that are not centre offsets** (`ui.healerWatch.point/x/y`, the Edit Mode–placed cards
  `trainingPosition`, `welcomeBackPlace` and `friendLoginPlace`, `ui.cozyBag`, `ui.partyPins.position`) have to be
  read and given a converter, or left unmanaged, in Phase 2.

### 8. Lifecycle: application, verification, restore

A journal in `TwichUIDB.layouts.install` records the state, so a reload or crash mid-install is recoverable:

```
none → planned → restore-point-taken → applied (pending reload) → verified | mismatch
                                                       ↘ failed (rolled back) ↙
mismatch | verified → restore-queued → restored
```

1. **Detect**: each adapter's `Detect`. Show what is missing (EllesmereUI not installed, too old, not the Forever
   build, a module disabled).
2. **Compose and plan**: pure. The wizard shows per-adapter changes, what is excluded, retained units, reloads,
   which EllesmereUI profile becomes active (account-wide, §9) and which TwichUI profile is used.
3. **Confirm**: one explicit confirmation that names the reload.
4. **Restore point**: `RS.CaptureOwn()` for TwichUI. For EllesmereUI, a copy of the live `EllesmereUIDB`, plus the
   enable state of each suite child addon. EllesmereUI writes straight to `EllesmereUIDB` ("single-storage",
   `AutoSaveActiveProfile` is a no-op [source]), so the live table is what will be saved. This differs from today's
   "as saved on disk" scan, which costs one extra reload [decision]. The copy is stored as an ordinary restore point
   (`TwichUIRestoreDB.points`), so the existing Backups window lists and exports it.
5. **Apply, EllesmereUI first** (it is the part most likely to refuse): decode the base string, put in the module
   blobs from higher layers, apply position patches, strip the exclusions (§3), then `EncodePayload` →
   `ImportProfileSilent{ profileName, cleanSlate = true, applyUIScale, autoAssignSpecs = false, disableAddons }`.
   EllesmereUI's serializer writes numbers with `tostring`, so the round trip is not exact. Positions are rounded to
   whole units before encoding. If it fails, the half-made profile is removed (the `ES.Apply` `Cleanup` pattern),
   nothing else is changed and the journal records `failed`.
6. **Apply TwichUI**: create the TwichUI target profile from the current one (`Profiles.Duplicate`, then switch),
   write the planned values, call `Profiles.Refresh("layout")`. If this fails after EllesmereUI succeeded, the
   EllesmereUI restore is queued and the recipient is told.
7. **Reload**: always needed when the EllesmereUI part ran. EllesmereUI's import says "Reload to finish importing",
   and `ImportProfileSilent` "NEVER reloads: the caller owns the ReloadUI" [source]. The reload happens only from the
   recipient's click.
8. **Verify** (at `PLAYER_LOGIN`, after every addon has loaded): EllesmereUI's active profile is the target, the
   module enable states match, the registered positions match within 1 unit, the TwichUI values match, and the
   UIParent size matches the planned size. Then record the baseline (§6) and show a short result: verified, or
   mismatches with a Restore button. The layouts addon is loaded at login only when the journal says
   `applied (pending reload)`.
9. **Restore**: TwichUI uses the existing `applyOwn` path (`RS.ApplyOwnAtLoad`, at the next load). EllesmereUI uses
   the existing restore-point table apply. It runs at EllesmereUI's `ADDON_LOADED`, which `!!!TwichUI` receives first,
   and `ES.Blocked` already allows `EllesmereUIDB` for `restore:` sources. Enable states are put back with
   `C_AddOns`. Then one reload.

**First-run picker**: while a TwichUI install is planned or pending, TwichUI calls
`EllesmereUI.RegisterExternalInstaller("TwichUI")` after EllesmereUI loads (it is read at `PLAYER_LOGIN` + 0.5 s
[source `EllesmereUI_FirstInstall.lua:586`]), so EllesmereUI's own picker does not compete. TwichUI does not register
in every session [decision]. If the recipient declines the TwichUI wizard, EllesmereUI's picker comes back on a later
login, as the API intends.

**Welcome**: the layout wizard is offered from the existing Welcome dialog (`modules/Welcome.lua`) and from
settings. It is not a second first-run system.

### 9. Reload and combat restrictions

| Operation | Combat | Reload |
|---|---|---|
| Plan, preview, Verify | Allowed (read-only) | No |
| EllesmereUI import | Refused (`ImportProfileSilent` returns "in combat" [source]; TwichUI also checks first) | Required |
| Suite module enable/disable | Refused | Required (client applies enable state at load) |
| UI scale change | Refused | Required (EllesmereUI applies `ppUIScale` at login) |
| TwichUI values | Refused (`Profiles` `Guard`) | No, except switches that already need a reload (skins, media, quiet login); `Switches.ReloadPending()` names them |
| Restore | Refused | Required |

- No secure frame, binding or action slot is touched by TwichUI. EllesmereUI's action bars rebuild from their profile
  during the reload.
- **EllesmereUI's active profile is account-wide**: `EllesmereUIDB.activeProfile` lives in an account saved variable,
  and `specProfiles` is keyed by spec ID, not by character [source]. An install changes the HUD for every character
  on the account unless a spec is assigned to another profile. In that case EllesmereUI stores the profile without
  activating it (`status = "spec_locked"`), and Verify must report that. The wizard says so before confirming.
  TwichUI profiles are per character, so the two systems differ here.

### 10. Packaging and compatibility

- **New load-on-demand addon `TwichUI_Layouts`** (a sibling folder, `RequiredDeps: !!!TwichUI`, no saved variables).
  It holds the package data, the composer, both adapters and the wizard window. It follows the pattern of
  `TwichUI_Settings` and `TwichUI_NavData`. The core keeps only a launcher (`R:OpenLayouts()`, modelled on
  `SettingsLauncher.L.Load`), journal and baseline normalization in `Persist.lua`, and the login check that loads the
  addon when verification is pending. Core operation never depends on it.
- **Release wiring** (the same as the other sibling addons): `.pkgmeta` `move-folders` (unquoted key),
  `tools/release.py` `ADDONS`, both `.toc` Version fields, and diagnostics (`Collect.lua` `ReadMemory` and `OURS`,
  `Export.lua`, `Base.lua` `DX`, `Window.lua` `MEMS`).
- **Saved data**: a new `TwichUIDB.layouts = { install = journal, baseline = {..}, choices = {..} }`. It is additive,
  filled only when missing, and needs no schema bump. It is placed in `RS.OWN_LEFT_OUT` (a record, not a setting) and
  in `TwichConfig.LOCAL` (`other`), which the existing coverage tests require.
- **Compatibility**: `package.format` newer than the code → refuse. EllesmereUI missing a required API, not
  `IS_FOREVER`, or older than `requires.min` → that adapter is unusable and the wizard says why. EllesmereUI newer
  than `tested` → allowed, with "tested with 9.6.8" shown. A payload rejected by `DecodeImportString` (version < 3 or
  an unknown prefix) → refuse.
- **Interface**: the client reports `16001` (Forever) in TwichUI's and EllesmereUI's `.toc` files. Metadata is not
  changed by this work.
- **Licensing**: TwichUI only calls EllesmereUI's runtime API and ships export strings the author made from their own
  install. No EllesmereUI or NaowhForever code is copied. EllesmereUI's reference folder now has a `license.txt`
  (all rights reserved; noticed in Phase 3): TwichUI still only calls its runtime API, and the package carries the
  author's own settings, not EllesmereUI's code or assets.

### 11. Revisions made in Phase 2 (2026-10-26)

Phase 2 built `TwichUI_Layouts/` (`Canon.lua`, `Package.lua`, `Compose.lua`, `AdapterTwichUI.lua`,
`AdapterEllesmere.lua`, `Journal.lua`, `Engine.lua`, `TestPackage.lua`, `Dev.lua`) and the core's
`LayoutsLauncher.lua`. Where it differs from §1–§10, the code and this section are the contract:

1. **Adapter functions (§4).** Composition and the fingerprint are shared (`Compose.lua`, `Canon.lua`), not per adapter;
   an adapter supplies `Normalize(fragment, ctx) -> units, parents` and the rest. The implemented set is `Detect`,
   `TargetName`, `Normalize`, `Capture(composed, target)`, `CleanSnapshot`, `Plan(composed, ctx)`, `Apply(part)`,
   `Expect(composed)`, `Verify(expect, snapshot)`, `PlanRestore(snapshot)`, `Restore(snapshot)`,
   `VerifyRestore(snapshot, units)`, `Label`, `Show`. `Plan` returns a part with its own `key`; the engine's plan key is
   the canonical text of the package, variant, mode and every part's key, and `Apply` and `Restore` refuse a key that
   differs from a fresh plan's (the `TC.PlanKey` / `expect` pattern).
2. **Package format 1 (§5) as built.** Top-level fields: `format`, `id`, `revision`, `title`, `dev`, `made`, `requires`,
   `targets`, `layers`. `targets` (new) names each adapter's target profile, so D9 lives in the package.
   `requires[adapter] = true | { min, tested }` (the top-level `tested` moved here). `canvas`, `choices`, `positions`
   and a top-level `tested` are refused as "not yet": this version cannot honour them. Any other field is refused.
3. **TwichUI fragment.** `{ groups = { [group] = { [slot] = { [key] = value | REMOVE } } } }`. `places` and list
   groups (custom groups) are refused as "not yet". The managed allowlist is computed from the schema: fields of
   non-list TwichConfig groups with profile scope and not covered by `TC.LOCAL`. Account-scoped fields (e.g.
   `general.ui.reduceSettingsMotion`) are not managed, because switching back on Restore would not put them back.
4. **EllesmereUI fragment.** `{ base, modules, fields }`. `base` only in the base layer: an export string, or, in a
   package marked `dev = true` only, `{ source = "active-profile" }` (the recipient's own active profile, exported with
   `ExportProfile(name, nil, true, false, nil, false, false, false)`: no spells, look, overrides or skins).
   `fields` is new: an explicit allowlist of values inside a module blob (Phase 2: `minimap.coordsMode`,
   `minimap.coordsPosition`, read in 9.6.8). A field unit's parent is its module unit; a field from a lower layer is
   dropped when a higher layer replaces the whole blob (§1 rule applied to sub-units). `positions`, `look`, `uiScale`,
   `disableAddons` and `unlockLayout` are refused as "not yet".
5. **Exclusions (§3).** `customColors` is also stripped: EllesmereUI profiles can pull colours from one another, so
   deleting the install's profile would not take an imported palette back. The UI scale is always the recipient's in
   Phase 2 (`applyUIScale = false`), and no suite module is enabled or disabled.
6. **Restore (§8 step 9; D3).** Restore uses public operations only and needs no restore-point copy: TwichUI
   `PF.Switch(previous)` then `PF.Delete(target)`; EllesmereUI `SwitchProfile(previous)` then `DeleteProfile(target)`,
   then the player's reload. This is complete because Phase 2 changes nothing account-wide (item 5) and installs only
   into profiles the install itself made. A whole-`EllesmereUIDB` restore point (D3) is needed only once the UI scale,
   enable states or other account-wide units are managed; it is deferred to that phase.
7. **Ownership.** An install never writes a profile it did not make: a target name that exists and is not recorded as
   made by this install (`snapshot.created`) blocks the plan (`target-taken`). Installing again writes into the
   install's own profiles; on EllesmereUI it first switches back to the recipient's profile, so `cleanSlate` never
   deletes the active profile (EllesmereUI would fall back to "Default").
8. **Snapshot and journal (§8).** The snapshot holds identities and fingerprints only: per adapter the profile in use
   before, the target name, whether the install made it, the EllesmereUI version, and a fingerprint of each managed
   value before. It is complete and checked before the record is written, and the record is written before the first
   change. Installing again keeps the first snapshot. States: `applying` (found at a load: `interrupted`), `applied`
   (waits for the reload), `verified`, `mismatch` (not verified: something differs or could not be read), `partial`,
   `restoring`, `restore-partial`; the record is removed when a restore checks out. The record belongs to one
   character (TwichUI profiles are per character): another character can neither install over it nor restore it.
9. **Partial failure (§8 step 6).** When TwichUI fails after EllesmereUI succeeded, the EllesmereUI restore is **not**
   queued by itself: the record says `partial` with each step's state, and Restore is offered. Nothing is undone
   without the player asking. A failure that changed nothing leaves no record (or the previous one, unchanged).
10. **Verification (§8 step 8).** TwichUI fields and EllesmereUI fields are compared by fingerprint; EllesmereUI module
    blobs are checked for presence only, because EllesmereUI merges its defaults into a blob as it loads. Verify reads
    and reports; it never repairs. The check runs 3 s after `PLAYER_LOGIN` (`LayoutsLauncher.lua`), after
    EllesmereUI's own login work (its picker at +0.5 s). The UIParent size check waits for screen adaptation.
11. **First-run picker (§8).** `RegisterExternalInstaller("TwichUI")` is called at EllesmereUI's `ADDON_LOADED` while
    the record says `applying` or `applied`. A plan is refused while `EllesmereUI._firstInstallPending` is true (read
    only): the picker would end in its own import and reload and replace the install.
12. **Combat (§9).** Apply and Restore are refused in combat by the engine and by each adapter; Plan and Verify are
    allowed. Nothing is deferred to the end of combat.
13. **Testing on another client (added 2026-10-26).** While WoW: Forever can't be played, a package marked `dev = true`
    may run on an EllesmereUI that isn't the Forever build (`IS_FOREVER` false, e.g. on Retail). The plan says so, the
    snapshot records `otherClient = true`, and a real package is still refused (`eui-not-forever`). The adapter's
    before-and-after profile check reads `GetProfilesDB()` itself rather than `setup/Ellesmere.lua`'s, which goes
    through sharing's Forever-only gate. A run on another client checks TwichUI's side of the pipeline; it is not one
    of the in-game checks for Forever.

### 12. Revisions made in Phase 3 (2026-10-26)

Phase 3 built the screen layer (`Geometry.lua`), package format 2, the Classic Adventure package (`Classic.lua`, with
its captured data in `ClassicData.lua`), the offline capture tool (`tools/layout_capture.lua`) and the developer review
path (`/tui layout plan|apply|geometry classic`). Where it differs from §1–§11, the code and this section are the
contract:

1. **Package format 2 (§5).** Adds `geometry` and `source`; format 1 packages (the developer test package) read as
   before. `choices` is still refused as "not yet". `canvas` and `positions` are not top-level fields: both live in
   `geometry`. `LY.MAX_UNITS` is 256 per adapter fragment (Classic's TwichUI part names 206 looks), and a record may
   expect `LY.MAX_UNITS + 64` units per adapter (what the fragment names, plus the places the screen layer adds).
2. **Settings as data (§5).** An EllesmereUI fragment may give the author's settings as plain tables instead of export
   strings: `root = { fonts, darkMode, euiAccent, _migrations }` (base layer; the `ROOT` allowlist, the root keys
   EllesmereUI's `ImportProfile` takes), `modules = { [canon] = table }`, and `layout = <unlockLayout>`. TwichUI builds
   the full payload itself (`{ version = 3, type = "full", data }`) and encodes it with `EncodePayload`, so import is
   the same `ImportProfileSilent` path as Phase 2. A package's blob may not hold a `STRIP` key: the per-character
   `characters`/`chars`, and the Cooldown Manager's `spec`, `activeSpecKey`, `specProfiles` and `barGlows` (which specs
   the author played; EllesmereUI recreates them on demand). A developer base built on the recipient's own profile
   loses only the per-character keys. Data is reviewable line by line and diffable, at the cost of size (the Classic
   data file is 375 KB of source, about 0.9 MB once loaded, offline figure).
3. **TwichUI places (§3, §7).** A TwichUI fragment may give `places` (format 2), through the adapter's `PLACES`
   registry only: `class-bars` (`ui.classBarsPosition.main`), `marker-bar`, `nav-arrow`, `food-drink` (centre offsets),
   `healer-watch` (`ui.healerWatch.point/x/y`, from that point of the screen), `training-card` and `welcome-back` (top
   edge from the top centre). The cards may be placed from a component's rect with no stored value. Party pins, the
   Cozy Bag guide, refreshments, navigation's frame and the settings window are windows the player moves: not places
   a layout sets. Sharing still never moves anything (`TC.LOCAL` is unchanged).
4. **The screen layer (§1 layer 5, §7).** Replaces the edge-affinity transform of §7 with components:
   - The **viewport** is UIParent's live size in its own units (`UIParent:GetWidth/GetHeight`; `LY.Geometry.Live`).
     The UI scale stays the recipient's: Phase 3 sets no scale and no CVar, so the viewport follows from it.
     The **composition area** is centred, full height, at most `maxAspect` × height wide.
   - A **component** is a box on the canvas (`ref`, measured from the author's layout) or a box of a given `size`, and
     an **anchor**: one of its nine points on a point of the area, the screen or another component. Offsets are
     measured on the canvas, so the author's own screen reproduces the author's layout exactly. Size: the reference,
     times the density factor if `density`, within `max` and `share`, never under `min` (the readable minimum).
   - Two rules, each applied once in dependency order: **room** (shrink toward a neighbour along one axis, keeping the
     anchored edge, never under `min`) and **above** (move up clear of a neighbour). Below the `narrow` width a
     component's `narrow` anchor and room replace its own. Then clamping on screen (inset by `margin`).
   - **Diagnostics** for managed components: `overlap` (pairs, with the overlap size), `offscreen`, `clamped`,
     `minimum` (a minimum won). `fits` is false on any overlap or offscreen. Nothing is shrunk past readable to fit.
   - **No coordinate is multiplied by a screen ratio.** Positions are kept relative to what they are anchored to.
   - **Attach maps** (`geometry.attach[adapter][positionId] = "component[:POINT]"`): each registered stored position
     moves with that point of its component. A position registered with size fields is the component's own frame and
     is placed and sized from the component.
5. **Conversions (§7).** `G.Stored(rect, point, rel, screen)` gives the `SetPoint` offsets; `G.Follow` moves a stored
   place of unknown size with its component. Every stored number is rounded to 1/100 of a unit. EllesmereUI links to a
   screen edge (`SCREEN_LEFT|RIGHT|TOP|BOTTOM`, with the cross-axis `edge` pin) have their offsets rewritten from how
   far the child's and the screen's edges moved, by the formulas of `UM.ApplyAnchorPosition`; on the canvas they come
   out as captured. Links to another element and point-mode links are left alone (EllesmereUI moves the child with its
   target). A stored position in a format not read (e.g. Bags' `TOPLEFT` with no relative point) is left as it is
   and noted in the plan. The density also scales the registered text sizes (`TEXT`: chat text and tabs, meter text
   and bar height), as whole numbers within bounds.
6. **Plan, record and verify (§8).** `LY.Plan(pkg, variant, opts)` and `LY.Apply(pkg, variant, key, opts)` take
   `opts = { screen, density }`; the plan key includes the screen and density, and each part's key already includes
   every placed position, so a plan shown for one screen is stale on another. The record expects placed positions as
   `"@x,y[,w,h]"` (EllesmereUI) and `"@x,y[,POINT]"` (TwichUI); Verify passes within one unit (EllesmereUI snaps to its
   pixel grid) and reports `moved`, never repairs. Root keys and the layout links are checked for presence, like blobs.
   After a restore, everything that existed only in the install's own profile counts as checked once that profile is
   gone and the previous one is in use.
7. **Objectives.** EllesmereUI's quest tracker stores no position: its placement is delegated to Blizzard's Edit Mode
   (`EllesmereUIQuestTracker_Visibility.lua`, rule 3). The objectives component is resolved (for the preview and the
   plan) and marked `applied = "edit-mode"`; nothing writes it until Edit Mode is managed (D15).
8. **Capture (Phase 5 content, started).** `tools/layout_capture.lua` reads saved files as data with a strict reader
   (never runs them, never writes them), runs TwichUI offline as the tests do, and keeps only what the adapters'
   allowlists keep: for EllesmereUI the `ROOT` keys, the `MODULES` blobs less `STRIP`, and the layout links; for
   TwichUI the `PLACES` and every managed looks-and-behaviour field that differs from TwichUI's default (no on/off
   switches). A whole-word scan for the account's character and realm names, player GUIDs, links and BattleTags must
   find nothing, or nothing is written. The output is deterministic (sorted keys, shortest round-trip numbers) and is
   read back and compared before the report is written (`capture-classic-adventure.md`).
9. **Classic Adventure is a developer package (`dev = true`) until Phase 7.** Its data comes from the Retail client's
   saved files (the only ones there are), so it may be tried on Retail (§11.13); a Forever check is still required.

### 13. Revisions made in Phase 4 (2026-10-26)

Phase 4 built the wizard (`TwichUI_LayoutWizard/`, `wizard.md`) and, for it, the `choices` the wizard asks. Where it
differs from §1–§12, the code and this section are the contract:

1. **Package format 3 (§5).** Adds `choices`: a list (at most `LY.MAX_CHOICES` = 6) of
   `{ id, kind = "preset" | "enum" | "density", label, hint, default, sets, options }`, each option
   `{ id, label, hint, swatch = { r, g, b }, density, [adapter] = fragment }` (at most `LY.MAX_OPTIONS` = 8). Ids are stable
   ids; labels are plain text (no `|`); the default names an option. A format 1 or 2 package carrying `choices` is refused
   as "not yet". A choice is a closed list that names exactly what it writes, and the validator refuses anything else:
   a **preset** may only turn TwichUI switches on (`twichui:modules.<key>` with the value `true`: never off, never a
   non-switch, never another adapter's unit); an **enum** may write only the units in its `sets`; a **density** names a
   density the package's geometry has and carries no fragment; **two choices never write the same unit**. Problem codes:
   `not-allowed`, `not-in-sets`, `choice-conflict`, `density-unknown`, `duplicate-id`, `bad-id`, `bad-value`.
2. **Layers (§1).** A picked preset is a second "preset" layer, above the variant's own preset; a picked enum is the
   "choices" layer (the composer's `opts.choices` pass-through still follows it). `LY.Resolve(pkg, variant, opts)` takes
   `opts.picks = { [choiceId] = optionId }`: a choice left out takes its default; an unknown choice or option is refused
   (`pick-unknown`); `resolved.picks` is every choice with its option. A picked density is the geometry's density;
   `opts.density` named as well must agree (`density-conflict`), and `opts.density` alone (the developer command) stands in
   for an unpicked size, with `picks.size` set to the option that has it.
3. **Plan and record (§8).** `LY.Plan` and `LY.Apply` take `opts.picks`; `plan.picks` is every choice; the picks are part
   of the plan key; the install record keeps them (`picks`, optional, at most `Journal.MAX_PICKS` = 8 id-to-id entries,
   checked by `J.Clean`; an install from before choices has none).
4. **EllesmereUI adapter (§3, §11.4).** `root.euiAccent` is accepted from a choice (the choice layer takes that one root
   key; the base layer still carries the whole look, and every other layer still refuses `root`). Its value is checked in
   shape (`A.AccentOk`: `useClass` a boolean, `custom` with `r`, `g`, `b` in 0..1, nothing else). It is **verified by
   value**, no longer by presence: the plan expects `accent:class` or `accent:rgb:%.3f,%.3f,%.3f`, and Verify computes the
   same signature from the live profile (`A.AccentSig`); three places, because EllesmereUI's serializer writes numbers with
   `tostring` and a round trip is not exact (§11). Other root keys remain presence-only.
5. **Not managed, and why (§2, D5).** The cursor-following tooltip (`EllesmereUIDB.tooltipAnchorCursor`) is an account-wide
   root key of the saved variable, one of the Blizzard-skin globals, which the only supported writer
   (`ApplyBlizzSkinGlobals`) sets whole (every key of the bundle, nil included) and which a profile switch and delete
   cannot put back. It needs the whole-`EllesmereUIDB` restore point (D3) first. See `adapter-capabilities.md`.
6. **Packaging (§10).** The wizard is its own load-on-demand sibling, `TwichUI_LayoutWizard`, requiring the core and
   `TwichUI_Layouts`, so the check after a reload loads the engine and not the window's code. `tools/release.py`
   `REQUIRED_DEPS` states what each load-on-demand addon requires (the core, and for the wizard the engine too). The core
   adds `L.LoadWizard`, `L.OpenWizard` and `L.WizardResume` to `LayoutsLauncher.lua`, and `/tui layout` (bare) opens the
   wizard.
7. **Saved data (§10).** `TwichUIDB.layouts.wizard = { v = 1, picks, resume }` beside `layouts.install`, covered by the same
   `layouts` entries in `TwichConfig.LOCAL` and `RS.OWN_LEFT_OUT`. `Journal.Clear` removes `layouts` only when it holds
   nothing else, so the wizard's picks survive a finished restore.
8. **Resume (§8 step 8).** The check after login (`L.Continue`) opens the wizard on the result only when the wizard left
   the resume note (the player pressed its Reload now); otherwise it prints its chat line as before, and the line points to
   `/tui layout`.

### 14. Revisions made in Phase 5 (2026-10-26)

Phase 5 added Compact Adventure as the second variant of the package `twichui-adventure`, per-variant screen rules, the
pieces-inside-components list the preview needs, and the wizard's layout choice, scenarios and full-size overlay
(`wizard.md`). Where it differs from §1–§13, the code and this section are the contract:

1. **Geometry rules per variant (§12.4).** A package's `geometry` is the rules the layouts share. `geometry.variants[id]`
   may add components and attachments to them or replace ones of the same id (an attachment replaces by position), and may
   give its own `narrow` width and `area`; it may not touch the canvas or the densities. `Geometry.Spec(spec, variant)`
   merges them (sharing the package's tables, cached) and `Geometry.Check` checks the shared rules and every variant's
   whole spec, each complete by itself. `Geometry.Resolve` takes `opts.variant`, `Geometry.Attach(spec, variant)` gives the
   attach maps, `LY.Resolve` and so `LY.Plan` pass the variant through, and `resolved.geometry.variant` says which was used.
   A variant that names nothing (Classic) uses the shared rules as they are. Package problem: `geometry-variant-unknown`.
2. **One pair of target profiles (§5, D9).** The package's `targets` are not per variant: the install's own profiles are
   EllesmereUI `TwichUI Adventure` and TwichUI `TwichUI Adventure` (they were `TwichUI Classic` and `Classic Adventure`
   while only Classic existed; nothing had been installed under the old names). Switching layouts is therefore an ordinary
   install again (§11.7): the same two profiles are written, the first snapshot is kept (Restore still goes back to before the
   first install), no profile is added, and the review says it is a switch. This needed no new pipeline.
3. **Shared base and variant units (§1).** The base holds the look, every EllesmereUI module the two layouts hold identically
   (11 of 18: the capture tool proves it by fingerprint, `capture-compact-adventure.md`), and the TwichUI looks and places
   (D27); each variant holds the modules and layout links that differ (7 modules each). Promoting a setting between a
   variant and the base is moving the module between two tables; nothing else changes. `LY.Compose` is unchanged.
4. **New registered positions (§11.4 `POSITIONS`).** `bar-6`, `bar-7`, `raid-frames` (`unlockPos`) and `party-frames`
   (`partyUnlockPos`), each a `{ point, relPoint, x, y }` record read in the author's Compact profile. The screen layer's
   position math moved into `EllesmereAdapter.Resolved` and `TwichUIAdapter.PlaceOne`, which the install and the preview both
   call. EllesmereUI stores raid and party frames from the centre in Compact (from the left edge in Classic), so they are
   attached to a zero-size `left-edge` component.
5. **`LY.Elements(pkg, variant, geo)` (Elements.lua).** The pieces inside the components for the preview: unit frames, cast
   bars, action bars, the party frames and TwichUI's own markers, each at the place the install would put it and with a
   sample size read from the layout's own data. Pure, read only, no validation or copying (it runs on every redraw). A
   piece with no size in the data is a note, never a guess.
6. **Capture (§12.8).** `tools/layout_capture.lua --shared-with <data file>` leaves out whatever is identical to an
   earlier capture and lists it with a fingerprint (`sameAs`); a differing root look key is refused; `--twichui-profile` is
   optional (a layout with no TwichUI side of its own).
7. **Saved data (§13.7).** `layouts.wizard.variant` (the chosen layout id) joins `picks` and `resume`. A record without it reads
   as the first layout; an unknown one is repaired to the first; a newer record is still never overwritten. The scenario
   and whether the preview is open are not saved.


### 15. Revisions made in Phase 6 (2026-10-27)

Phase 6 added authoring and publishing (`publishing.md` has the workflow, limits, tests and checklists). Where it differs from
§1–§14, the code and this section are the contract:

1. **Capture is one function (§12.8).** `LY.Capture.Read(euiProfile, twichuiSlot)` (`TwichUI_Layouts/Capture.lua`) decides what a
   layout may carry out of a profile; `tools/layout_capture.lua` and the in-game workspace both call it. `Capture.Scan` is the
   personal-data scan (character names whole and by word, realms where the client has them, GUIDs, links, BattleTags);
   `Capture.Put/Clear/Locate` move one unit between a layer's fragments.
2. **The envelope (§5).** A publication is `{ kind = "twichui-layout", v = 1, package, meta }` (`Publish.lua`). The package is
   format 3, unchanged, and `LY.Validate` is still the one validator. `meta` states what the author wants read first; every fact
   in it is derived again from the package by the reader and a mismatch refuses the publication. The sender is never in it.
3. **A stricter reading for a package that travels (§3).** `Pub.Strict`: no `dev`, layout rules required, no opaque EllesmereUI
   export string, no `LY.REMOVE`, bounded plain strings, media references classified (TwichUI's own media checked against
   `modules/Media.lua`, the suite's, the game's; another addon's or off-disk paths refused).
4. **Stored packages (§10).** `TwichUIDB.layouts.published` and `.received` (`Store.lua`): bounded lists, each entry a summary and
   the exact packed block as printable text. A full store refuses. `Journal.Clear` leaves them; the existing `layouts` entries in
   `TwichConfig.LOCAL` and `RS.OWN_LEFT_OUT` cover them (backups do not hold them).
5. **Transport (`Share.lua`).** Message type `layoutoffer`; `SH:SendLayout`, `SH.SendLayoutData`, `SH.RespondLayout`,
   `SH.LayoutReceived`; `SH.DecodeData`; the transfer record carries `kind = "layout"`. It reuses reply, incoming, data lanes, done,
   routes, watchdogs and progress. It is never auto-accepted, bounded before unpacking, and receiving only stores.
6. **The wizard (§13).** `layouts.wizard.package` records which package its picks belong to (a record without it belongs to the
   included package; another package starts from its own defaults); `M.Sources`, `M.SetSource` choose the package; the install
   record names the package (it always did) and, for a received package with another id, the wizard finds it again after a reload.
   Pages that ask a choice the package does not have say so instead of failing.
7. **Core launcher.** `L.OpenAuthor()`; `/tui layout author` (alias `publish`). No settings page, broker entry or Welcome offer.

### 16. Revisions made in Phase 7 (2026-10-27)

Phase 7 added updating an installed layout while keeping the recipient's changes (`updates.md` is authoritative: the cases, the
schema, the geometry rules, the switch policy, the checklist). Where it differs from §1–§15, the code and this section are the
contract:

1. **Baseline (§6).** `TwichUIDB.layouts.baseline` holds, per adapter part, each unit's recommended value (`p`), the value the
   install left where different (`a`), the read-back (`l`), how it was stored (`s`), retained override (`k`), owned (`o`) and
   presence-only (`u`). Comparable units are stored as **values** (`LY.Value`, the whole canonical text), not fingerprints;
   opaque units as fingerprints. A part is committed only after that adapter's check matched (`Engine.lua` `Commit`); never
   because an install started; a failed, partial or kept step leaves the previous part. Parts carry the merge contract, the
   schema (TwichUI settings schema; EllesmereUI version and migration stamps), revision, layout, picks and screen; another
   version is not compared.
2. **Retained overrides (§1 layer 6, §6).** Decided by `Merge.lua` per unit, three ways (baseline, current, new), with the
   policy "keep" (default) or "recommended" and per-unit, per-group and per-addon choices (`opts.update`). §6's "a change anywhere
   inside a module blob retains the whole module" stands, as an explicit fallback: blobs, layout links and look tables are opaque
   (compared only with their own baseline, never merged inside), and a blob's registered positions, text sizes and fields are
   comparable units of their own. Carrying a blob needs the same migration vintage; otherwise the addon is kept as it is or
   replaced whole.
3. **Two lifecycles (§6 Detach, §8).** The install record is the rollback journal; the new management record
   (`TwichUIDB.layouts.managed`: package, revision, layout, picks, character, the install's own profiles, the first install's
   home profiles) and the baseline are management. `LY.Finish` (the wizard's Keep this setup) ends the journal only;
   `LY.Detach` (Stop managing, Forget the record) ends all three; a restore that checks out ends all three (`Journal.Forget`).
   With no install record, a management record makes an install again an update into profiles still recognised as the install's
   own (`ctx.owned`, `ctx.home`).
4. **Undo this update (§8).** An update from a settled install keeps `record.update` (the record, management record and
   baseline from before it; TwichUI values it replaces; the EllesmereUI profile renamed, not copied). `LY.PlanUndo`, `LY.Undo`,
   `LY.VerifyUndo`, states `undoing` and `undo-partial`; `LY.ForgetUpdate` keeps the update for good. One level. Restore is
   unchanged and also removes the copy.
5. **EllesmereUI calls (§4).** `RenameProfile` is added, used only to keep the install's own profile under
   `<target> (previous)` during an update and to put it back; a missing `RenameProfile` blocks an update (`eui-no-rename`), not a
   first install. `OthersUnchanged` treats the install's own names (target, copy, a transient stash) as its own.
6. **Verification (§8 step 8, §11.10).** Presence-only checks (blobs, links, look) are counted apart (`verify.presence`) from
   values read back (`verify.checked`); the result and chat line say so; the baseline marks them `u`.
7. **Resume and record-only updates.** A `partial` or `interrupted` update with the same package, layout and choices resumes
   (done steps are neither planned nor applied again). An update with nothing to write is still recorded when it changes the
   revision, layout or choices, or releases or claims a setting.
8. **Re-running with the same choices (D25).** Answered: the baseline makes it "nothing to do" unless something differs.
9. **Switching layouts (§14.2).** Still an install again into the same profiles, now with the switch rules of `updates.md`;
   it adds the `(previous)` copy, so the account holds the install's profile and one copy until the update is kept.

## Phase records (from implementation-status.md)

#### 1. Audit and contract (done)

- [x] Read the sharing, restore, profile, persistence, settings and navigation load-on-demand code and docs.
- [x] Read EllesmereUI 9.6.8's profile, import, export, first-install, scale and position code.
- [x] Defined: supported addons, managed categories, adapter contract, schema and IDs, precedence, merge semantics,
      coordinates, lifecycle, reload and combat rules, packaging.
- [x] Listed open decisions and in-game checks (below).

#### 2. Engine and safe application pipeline (done offline, 2026-10-26)

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

#### 3. Classic Adventure and the screen-layout resolver (done offline, 2026-10-26)

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

#### 4. Wizard, preview and install lifecycle UI (done offline, 2026-10-26)

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

#### 5. Compact Adventure and richer previews (done offline)

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

#### 6a. Authoring and publishing (done offline, 2026-10-27)

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

#### 6b. Retained overrides and updates (the author's Phase 7; done offline, 2026-10-27)

`updates.md` is the authoritative description; `architecture.md` §16 has the contract revisions. Built: `TwichUI_Layouts/Merge.lua`
(the three-way comparison, groups, the whole-addon decision, tracking, the screen check of kept places), the baseline and the
management record (`Journal.lua`), both adapters' normalized reads, merge, baseline read-back and undo, the EllesmereUI backup by
`RenameProfile`, the engine's update plan, commit after a matching check, resume, record-only updates, `LY.Finish`,
`LY.PlanUndo`/`LY.Undo`/`LY.VerifyUndo`, `LY.ForgetUpdate`; in the wizard the update review (three ways, details with choices),
Undo this update, Keep the update, Keep this setup as Finish, Stop managing, and the "Installed and managed" result. The core's
`LayoutsLauncher.lua` also finishes an `undoing` record after the reload. `LY.Compose`'s `retained`/`reset` parameters are not used
(retention has to carry the player's values into an EllesmereUI payload, which removal can't do).

A mid-implementation review (2026-10-27) required: values not fingerprints for comparable units (done: `LY.Value`, `p`/`a`/`l`/`k`);
whole-module retention disclosed as a fallback (done: opaque labels and conflict wording); Finish not implemented as Detach (it
had been: changed to `LY.Finish` with a separate management record); no full verification from module presence (it had been:
presence is now counted and labelled apart); consecutive updates (a real bug: a kept override read as "unchanged" at the next
update and lost its mark; fixed in `Merge.Classify`); Finish → reload → reopen → update (tested).

**Checks run** (offline Lua 5.1; `./tests/run.sh`: 123 passed, 0 failed): `tests/test_layout_update.lua` (new). Expectations changed
in older tests, each for a stated contract change: `test_layouts.lua` §8 and §18 (an update adds the `(previous)` copy; Restore
removes it; a base-string package is labelled whole; blob checks counted as presence), `test_layout_wizard.lua` (the same choices
again is now "nothing to do" (D25); a switch keeps the old profile as the copy; Keep this setup finishes and keeps managing).
Stand-ins: `RenameProfile` in both, and opt-in load-time defaults in `layouts_mock.lua`. Six hand mutations each fail the new tests.
`luacheck` (globals off): 0 warnings in the files changed (two older warnings in `Model.lua` predate this phase).

**Diagnostics.** No new scope or gauge: the comparison runs inside `layouts.plan`, the baseline commit inside `layouts.verify`, undo
inside `layouts.restore`; their labels in `DX.OPS` and `docs/diagnostics.md` now say so. The baseline, management record and the way
back are bounded saved data in `TwichUIDB.layouts` (measured offline: the Classic baseline is under 64 KB of canonical text, checked
by the tests); in-game memory and CPU are not measured. The comparison copies every EllesmereUI blob twice per plan (normalization);
offline that is part of the plan's cost, not measured in game.

**In-game checks**: the manual checklist in `updates.md`.

#### 7. Release hardening and in-game validation

Acceptance:
- Every in-game check below has been run on the packaged artifact, with results recorded here. Classic loses
  `dev = true` only after the Forever checks.
- A fresh account, an existing EllesmereUI user, an existing TwichUI user, re-applying after manual changes,
  switching variants, Restore and Detach: each gives the documented result.
- The release zip holds five folders. `tools/release.py` package checks pass. `CHANGELOG.md` is updated.
- No performance regression in a `/tui perf` General capture with the layouts addon not loaded.

### Phase 6 handoff (retained overrides, 6b)

`wizard.md` ("Phase 6 handoff") has what retained overrides, per-layout TwichUI settings, the UI scale policy, the tooltip
choice and the unplaced positions need. The engine facts Phases 4 and 5 relied on (kept, and still true; the geometry is now
resolved with `opts.variant`, and `plan.geometry.variant` says which layout it is for):

### Phase 4 handoff (used)

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

## Wizard handoff and additions (from wizard.md)

### Phase 6 handoff

- **Retained overrides**: the wizard keeps the picks and the layout across installs, and switching layouts is an install again, so
  "kept" and "reset" can be shown in the review without changing the steps (`LY.Compose` already takes `retained` and `reset`).
  Module blobs differ per layout, so retention is per module blob and per registered position, as §6 says.
- **Per-layout TwichUI settings**: Compact shares Classic's TwichUI looks and places (D27). If the author wants Compact-specific
  TwichUI places, capture them from a separate TwichUI profile with `--twichui-profile` and put them in the variant layer: the
  composer already lets a variant's units win.
- **UI scale policy** (D12): a `ui-scale` choice would be a fourth choice; the plan, the review, the miniature and the overlay
  already follow the screen the geometry is resolved for, so they need the target scale's viewport. It needs the
  whole-`EllesmereUIDB` restore point (D3), and with it the **tooltip choice** can be offered (D5).
- **Positions not yet placed** (D32): the Battle Res frame (`centerX`/`centerY` storage), the Cooldown Manager's other bars,
  class power. Each needs a registered position with its own format, then an attach entry per layout.
- **Choices the schema already allows**: more enums (each names its `sets`), more presets (switches only).

### Phase 6 additions

Packages other players sent: the first step lists the included package and each received one and opens the one chosen; its
layouts replace the two included ones on the Layout step; choices it does not have are skipped with a note. Authoring is a
separate workspace (`/tui layout author`) that the wizard does not link to. See `publishing.md`.

### Phase 7 additions

Updates (`updates.md`, authoritative): the Review step's **Updating your layout** block (three ways, details with per-setting
choices, group and whole-addon questions, screen warnings); the Result step's **Undo this update** and **Keep the update**.
**Keep this setup** now *finishes* the setup (`LY.Finish`): the restore point is forgotten, TwichUI keeps managing the layout
(management record and baseline stay) and the wizard shows **Installed and managed** with **Set up again** and **Stop managing**.
It is no longer Detach; "Forget the record" and Stop managing are. Re-running with the same choices is "nothing to do" (D25).

## Wizard decision tables, as raised (from wizard.md)

### Open decisions raised in Phase 4

| # | Question | Recommended default |
|---|---|---|
| D21 | The TwichUI helper presets: which switches, which names (`on-screen`: class resource bars, marker bar, food and drink buttons; `finding-my-way`: those and Navigation) | As built; the author to confirm or change the set |
| D22 | The accent options (Aged gold, Class colour, Verdigris, Ember, Dusk blue) and their colours | As built (the three non-captured colours are proposals in TwichUI's palette); the author to confirm |
| D23 | The tooltip choice (cursor-following or fixed): not offered until account-wide units are managed (above) | Keep it out; build with D3 and D5 |
| D24 | A Welcome-dialog offer for the wizard | Not built; the wizard is on Home. Add a button only if the author wants it there |
| D25 | Re-running with the same choices re-imports the install's EllesmereUI profile (a module-blob package is always imported whole), replacing changes made in it since | As built, and the review says so; a "nothing to do" shortcut needs a content fingerprint of the live profile |

### Open decisions raised in Phase 5

| # | Question | Recommended default |
|---|---|---|
| D26 | The package has one pair of install profiles, `TwichUI Adventure` (EllesmereUI) and `TwichUI Adventure` (TwichUI), for both layouts (they were `TwichUI Classic` / `Classic Adventure`; nothing was installed under those) | As built: a layout switch is an install again, with no extra profile and one restore point |
| D27 | Compact's sources: EllesmereUI profile `TwichUI - Minimal Adventure` (confirmed by the author); TwichUI side shared with Classic (confirmed: the only TwichUI profile is `Default`) | As built |
| D28 | Compact's checked box is the core of the bottom strip (1091 × 157.5); the pet frame and bar and the stance bar follow it but are outside it | As built; the author to confirm, or widen it (which makes chat give way on every 16:9 screen) |
| D29 | Compact's narrow width is 1780 (Classic 1700) and below it chat rises above the strip at its full width | As built |
| D30 | The overlay dims the live interface instead of hiding it | As built; hiding UIParent would hide the preview and moving protected frames is not allowed |
| D31 | TwichUI's pieces (class bars, marker bar, navigation arrow, food and drink) are Classic's captured places in Compact too; class bars at (−385, −558) land inside Compact's strip | Look at the markers in the overlay on the author's screen and say which should move; capture them from a separate TwichUI profile if so |
| D32 | Not placed by the screen layer: the Battle Res frame, the Cooldown Manager's other bars, class power (left at the author's coordinates, which in Compact sit above the strip), and the pieces the preview has no size for | Register positions when the author wants them moved |

## Publishing handoff (from publishing.md)

### Phase 7 handoff

- The package carried by the bundled `ClassicData.lua` still points at the author's private `MyFonts` folder
  (`unitNameFontPath`). The bundled package is a developer package, so nothing breaks, but the same publish check that found it
  refuses to publish it as it is. Before release: replace it in the data, or accept the one-click substitution when publishing.
- Retained overrides and updates: built in Phase 7 (`updates.md`); a received package is an ordinary package for the engine, so
  they apply to it unchanged.
- A received package with the included package's id and a higher revision installs over it as an ordinary re-install. There is
  no "update available" notice by design; the sender has to send it.
- In-game: everything in the checklist above, plus the existing Phase 2 to 5 checks. The sizes and times in the final report are
  offline Lua 5.1 figures; in-game CPU and memory are not measured.
