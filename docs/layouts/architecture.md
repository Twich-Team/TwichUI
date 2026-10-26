# Layout packages and installer: architecture contract

This is the contract for TwichUI's layout packages: two complete interface experiences, **Classic Adventure** and
**Compact Adventure**, built from shared configuration and installed by a TwichUI wizard. It was written in Phase 1
(audit, 2026-10-26). **None of it is implemented yet.** `adapter-capabilities.md` holds the source evidence for each
integration, and `implementation-status.md` tracks the phases and the open decisions.

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
  `{ [unitId] = hash }`, fingerprints only, no copies. The number of units bounds its size.
- **Retained recipient override**: a unit whose live fingerprint differs from its baseline. Re-running the wizard
  (an update or a variant change) keeps those units by default. The plan lists them, and the recipient can tick
  "reset to the package" per unit or for everything. Granularity: TwichUI by key; EllesmereUI by module blob and by
  registered position. A change anywhere inside a module blob retains the whole module.
- **Reset**: removes retention for the chosen units and applies the composed value. It is a normal install.
- **Detach** (the default way to leave): stop managing. The journal and baseline are cleared and every value stays
  as it is.
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
  install. No EllesmereUI or NaowhForever code is copied. EllesmereUI's reference folder has no license file.
