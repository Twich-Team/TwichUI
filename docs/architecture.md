# Source navigation

Paths in code spans are repository-relative. Each package's same-named `.toc`
is the load-order authority; `.pkgmeta` is the packaging authority. Read the
manifest before adding a file. This map is an entry point, not a dependency analyzer.

| Production package | Ownership | Loading |
|---|---|---|
| `!!!TwichUI` | Namespace/events, persistence, profiles, feature engines and companion launchers | Always loaded |
| `TwichUI_Settings` | `Kit.lua`, `pages/`, search, widgets, window, `QuickAccess.lua` (the list's learned shortcuts); calls feature-owned setters | Load on demand; core dependency |
| `TwichUI_NavData` | Generated walking maps and crossing/transit data | Load on demand; core dependency |
| `TwichUI_Diagnostics` | Opt-in captures, gauges and reports | Load on demand; core dependency |
| `TwichUI_Layouts` | Canonical packages, composition, adapters and transactional install | Load on demand; core dependency |
| `TwichUI_LayoutWizard` | Layout choices, review and authoring | Load on demand; core and Layouts dependencies |
| `TwichUI_Workshop` | Crafting, shopping, prices, Market bridge, Advisor and AH preview | Load on demand; core dependency |
| `TwichUI_Fishing` | The fishing key (next step, reel override), lures, gear snapshots, catch tracking, container queue, sessions; Fishing Mode (camera, fading, cast bar, catch list, notifications; artwork in `media/`); `TwichUIFishingDB` | Load on demand (`/tui fish` or a bound fishing or Fishing Mode key); core dependency |

`TwichUI_TestLab`, `TwichUI_LoadTest` and `TwichUI_LoadTestClock` are development
packages excluded from production packaging. External `TwichUI_MarketData` is
explicitly loaded by the bridge, not shipped here. Lazy frame construction is
separate from addon loading: closing a window does not unload its Lua code.

## Ownership and verification entry points

Core paths below begin inside `!!!TwichUI/`; companion paths are explicit.
Use the named group with [test-selection guidance](testing.md#source-to-test-guidance).
The actual test patterns and recursive dependencies live in [groups.json](../tests/groups.json).

| Area | Source/config entry | Group and existing detail |
|---|---|---|
| Core, profiles, saved data | `Core.lua`, `Persist.lua`, `Profiles.lua`, `Switches.lua`, `setup/` | `core`; [persistence](persistence.md), [profiles](profiles.md); global changes require full gate |
| Shared styling/notifications | `chronicle/Style.lua`, `Look.lua`, `FrameLook.lua`, `CraftLook.lua`, `modules/Notify.lua` | `shared-ui` plus affected consumers; [feature rules](dev-rules.md) |
| Settings | `TwichUI_Settings/Kit.lua`, `pages/`, `Window.lua`; behavior owned by feature APIs | `settings`; [recipes](recipes/add-feature-setting.md) |
| Reminders | `reminders/Config.lua` (`RM.SetEnabled`), State/Controller/Display; `TwichUI_Settings/pages/Reminders.lua` calls setters | `reminders`; `tests/test_reminders_settings.lua`; [guide](reminders.md) |
| Navigation/maps/pins/guild | `nav/`, `map/`, `pins/`, `npcs/`, `guildloc/` and NavData | `navigation`; [guild privacy](guild-locations.md) |
| Layouts | `TwichUI_Layouts/Engine.lua`, `TwichUI_LayoutWizard/Model.lua` | `layouts`; [architecture](layouts/architecture.md) |
| Fishing | `FishingLauncher.lua` loads `TwichUI_Fishing/` (`Action.lua` key, `Loot.lua`, `Containers.lua`, `Gear.lua`, `Lure.lua`, `Session.lua`, `Store.lua`, `Api.lua`; Fishing Mode: `Present.lua`, `Camera.lua`, `Fade.lua`, `CastBar.lua`, `CatchList.lua`, `Toast.lua`, `Hud.lua`; art from `tools/make_fishing_art.py`) | `fishing`; [fishing](fishing.md) |
| Crafting/shopping | `TwichUI_Workshop/CraftPlanner.lua`, `Shopping.lua`, `Stock.lua`, `Strategy.lua` | `crafting`; [Workshop](workshop.md) |
| Market schema-3 | `TwichUI_Workshop/Bridge.lua` schedules validation; `BridgeValidate.lua`, `BridgeSchema.lua`, `BridgeCodec.lua` validate before activation | `market`; `tests/test_workshop_bridge_scoped.lua`, `tests/test_workshop_bridge_scoped.py`; [scoped contract/evidence](workshop/market-bridge-scoped-l3.md) |
| Workshop reference pricing | `TwichUI_Workshop/Pricing.lua` selects validated Companion base-item references; `Session.lua` and `MarketFacts.lua` connect consumers; `Market.lua` remains the native/local observation API | `market` plus `crafting`, `item-advisor`, `workshop-settings`, `auction-preview`; [consumption contract](workshop/automatic-market-summary.md#workshop-price-consumption) |
| Workshop planning estimate | `TwichUI_Workshop/Estimate.lua` (pure: craft cost, sell price, confidence) and `Fees.lua` (the cut and the deposit, from the Gold Ledger); `Session.Estimator` builds its context for Opportunities, the Overview and the queue estimate | `crafting` plus `market`; `tests/test_workshop_estimate.lua`; [pricing realism](workshop/pricing-realism-proposal.md) |
| Item Advisor | `TwichUI_Workshop/Advisor.lua`, `AdvisorData.lua`, `ViewAdvisor.lua` | `item-advisor`; [verification policy](workshop/testing-roadmap.md) |
| Disenchant estimates | `TwichUI_Workshop/Disenchant.lua`, `DisenchantData.lua`, `DisenchantExclusions.lua`; bundled MIT reference tables, Market/local material prices | `item-advisor` plus `market` and `workshop-settings`; [data and limits](workshop/automatic-market-summary.md#disenchant-support) |
| AH preview lifecycle | `WorkshopLauncher.lua`, `TwichUI_Workshop/Window.lua` Suspend/Resume, `TwichUI_Workshop/auction/Window.lua`; core `auction/Host.lua` owns native lifecycle | `auction-preview`; `tests/test_workshop_auction_lifecycle.lua`; [lifecycle proof](workshop/auction-house/lifecycle-proof.md) |
| Diagnostics | `diag/`, `Core.lua` R.Perf, `TwichUI_Diagnostics/` | `core` plus affected feature; [coverage rules](dev-rules.md#diagnostics-coverage-for-new-features) |

For other features (gear, inventory, class bars, skins, Chronicle, vendor utilities),
start with the core manifest and matching folder/module, then search full test
inventory. They have no guaranteed dedicated group; do not infer coverage from
folder names. The [A1 responsibility map](audits/phase-a1-baseline.md) provides
additional dated context.

## Initialization, persistence and contracts

Core manifest order is libraries, namespace/persistence/profiles/switches/launchers,
then features. `Core.lua` handles ADDON_LOADED and runs persistence, profiles and
registered initialization hooks; login/world events are separate. Settings loads
Kit before pages and Window last. Workshop loads data/bridge/calculations before
services/views and Window. Preserve that order and optional-load failure paths.

Core `.toc` declares `TwichUIDB`, `TwichUIBackupDB`, `TwichUIShareDB`,
`TwichUIRestoreDB`, `TwichUIChronicleDB`. Diagnostics owns `TwichUIDiagnosticsDB`;
Workshop owns `TwichUIWorkshopDB` (prices/history); Workshop preferences and queue
also live in core DB. Use feature setters, preserve future-schema hold/recovery,
and keep gameplay records separate from configuration sharing.

Market contracts and pinned upstream identities live in
`tests/fixtures/market_bridge_v1/` and `tests/fixtures/market_bridge_scoped_l1/`.
The latter includes `generation-schema3.schema.json`, `selection.schema.json`,
`UPSTREAM.json` and hashes. The external repository is not inferred from local
code. Preserve scope, receipt, digest and atomic-generation checks.

## Generated and external material

`!!!TwichUI/libs/` is third-party: do not edit. NavData and `TwichUI_Layouts/ClassicData.lua` /
`TwichUI_Layouts/CompactData.lua` are generated data; follow their source headers and existing tools.
Artwork inputs are in `assets/`, runtime art in addon `media/`; use the matching
existing generator only within authorized scope. Never regenerate unrelated art.
`test-output/` contains historical evidence as well as ignored new run output;
do not treat it as source or delete it for navigation. See shared rules for
read-only external references and licensing constraints.
