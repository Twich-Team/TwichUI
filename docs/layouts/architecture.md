# Layout packages and installer: architecture contract

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

## 1. Composition

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

## 2. First-release supported addons

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

## 3. Managed setting categories

### `twichui` adapter

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

### `ellesmereui` adapter

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

### Default exclusions (both adapters)

These are never in a package, never captured into a baseline and never written: keybindings, action assignments,
character and account identities, NPC knowledge (`npcs`), chat history (`EllesmereUIChatScrollDB`), caches and runtime
state, diagnostics recordings, personal reminder rules, and unrelated profiles and settings. Other EllesmereUI profiles
are never edited. The one exception is the TwichUI-named target profile, which `cleanSlate` replaces (§6).

## 4. Adapter contract

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

## 5. Package schema and stable IDs

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

## 6. Merge, reset, removal and retained overrides

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

## 7. Coordinate conventions

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

## 8. Lifecycle: application, verification, restore

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

## 9. Reload and combat restrictions

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

## 10. Packaging and compatibility

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

## 11. Revisions made in Phase 2 (2026-10-26)

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

## 12. Revisions made in Phase 3 (2026-10-26)

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

## 13. Revisions made in Phase 4 (2026-10-26)

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

## 14. Revisions made in Phase 5 (2026-10-26)

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


## 15. Revisions made in Phase 6 (2026-10-27)

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

## 16. Revisions made in Phase 7 (2026-10-27)

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
