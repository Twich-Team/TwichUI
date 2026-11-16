# Phase A1 — certified baseline and engineering map

Audit date: 2026-11-16. Read-only source audit; no new runtime acceptance claim.
Companions: [findings](phase-a1-findings.md), [release engineering](phase-a1-release-engineering.md).

## Provenance and limits

**Newly measured:** remote `git ls-remote origin` returned exactly:

| Branch | Commit |
|---|---|
| main (audit baseline) | `d06d74c89de869ef2aae7a9c0ac2ca5e44bf6164` |
| release/v1.3 | `cd5cbf037f2185e66403d0709361fb5abaf55313` |
| feature/workshop | `20cb1da1031d350cfb430c8c6e65fd2ea3c2f480` |

`git rev-parse <SHA>^{tree}` gives `8deae3b5a7bd8cc6a9ad13c17fb54631a579658c` for all three. GitHub PRs [27](https://github.com/Twich-Team/TwichUI/pull/27), [28](https://github.com/Twich-Team/TwichUI/pull/28), [29](https://github.com/Twich-Team/TwichUI/pull/29) are merged. No newer development on these three branch heads was observed. Other remote branches are not replacement consolidation evidence. Different histories need no synchronization merge.

**Previously measured:** [v1.3 readiness](../v1.3-release-readiness.md) and PRs 27/28 record frozen source `b778b262f77cea1f5df8510bde4bd01965adb3ae`: 253 offline modules, 164 Python cases, 718 syntax checks, all ten catalogs, 197 native simulator launches, 31,492 structured checks, 183 structural PNGs, 7,377.085 seconds. A1 verified that its diff to main is solely `docs/v1.3-release-readiness.md`. Report SHA256: `50a460502cec3ddb13fa3cd59ee1150cb214f9ade58ac08442508e6fc5ee1e43`. These are retained certification claims, not rerun results or Forever-client acceptance. Raw certification artifacts were not rehashed in A1.

Independent worktree `/workspace/TwichUI-audit-a1`, branch `audit/phase-a1-engineering`, starts at main above. Owner checkout `/workspace/TwichUI` was clean on `work` at `1e8cd26`; it was neither switched nor edited. Fetch/worktree registration necessarily updates shared Git metadata, not owner files. Publication policy remains `publication_enabled=false`.

## Runtime packages and initialization

**Source-confirmed:** manifests and [.pkgmeta](../../.pkgmeta) are authoritative; counts below are non-comment manifest entries, not recursively expanded Lua counts.

| Package | Entries | Load and dependency | Ownership |
|---|---:|---|---|
| `!!!TwichUI` | 276 | Always loaded | Namespace, persistence, profiles, feature engines and launchers |
| `TwichUI_Settings` | 67 | LoD; core | Kit/page declarations, search, widgets, window |
| `TwichUI_NavData` | 10 | LoD; core | Generated crossing graphs, tiles, transit |
| `TwichUI_Diagnostics` | 12 | LoD; core | Opt-in captures, reports and gauges |
| `TwichUI_Layouts` | 19 | LoD; core | Canonical package, composition, adapters, transactional install |
| `TwichUI_LayoutWizard` | 14 | LoD; core and Layouts | Review, choices, authoring, wizard |
| `TwichUI_Workshop` | 61 | LoD; core | Crafting, market, Advisor, standalone AH preview |

Three development packages are excluded: TestLab (24 entries, LoD), LoadTest (one, LoD), LoadTestClock (one, always loaded if installed). External `TwichUI_MarketData` is explicitly loaded by Workshop Bridge, not included among the seven distributed packages. No TwichUI Market repository was inspected or modified.

Core manifest order is libraries → `Core.lua`, `Persist.lua`, `Profiles.lua`, switches/launchers → feature declarations. `Core.lua` registers the namespace/event bus and `OnInit` hooks. Its `ADDON_LOADED` hook calls persistence, profiles, missing switch defaults, then initialization hooks in registration order with individual `pcall` error reporting. Login/world events are separate lifecycle stages. Optional skins register after their external addon loads or at login. A successful file load is not proof every initialization hook succeeded (`Life.hookFailures` tracks failures).

Settings loads Kit first, page declarations next, search/widgets/design and Window last; frames are lazy, but page code is loaded together. Workshop loads data/bridge/pure calculations before session/services/views, Window last. Core `WorkshopLauncher.Load` guards experimental consent, missing APIs/addons, combat and incomplete initialization. `Window.lua` owns `W.Suspend`/`W.Resume`; suspension stops scans, read listeners, Bridge jobs, recipe/bank/tooltip services and windows without deleting player records. Hidden enabled Workshop deliberately continues recipe/bank observation; hidden is different from disabled.

## Responsibility and dependency map

Paths are relative to core unless prefixed with a companion package. **Source-confirmed** at manifest/header and representative lifecycle level; this is not a function-by-function correctness review.

| System | Owner/source navigation | Principal relationship |
|---|---|---|
| Core/settings/profiles | `Core.lua`, `Persist.lua`, `Profiles.lua`, `Switches.lua`; Settings Kit/pages/Window | Features own setters; settings calls them; profile apply stages refresh consumers |
| Reminders | `reminders/Config.lua`, `State.lua`, `Controller.lua`, `Display.lua`; Settings `pages/Reminders*.lua` | Validated config → coalesced facts → rules/timing → display; shared notifications/look |
| Notifications | `modules/Notify.lua`, `NotifyLook.lua`, arrival/training/friend/death cards | Coordinator prevents overlapping cards; QuietScreen is session-only |
| Action bars/effects | `classbars/`, `glows/`, `camping/`, `modules/FoodDrink.lua` | Config/state/logic/draw split; protected buttons need client combat acceptance |
| Navigation/maps | `nav/Nav.lua`, `map/`, `pins/`, `npcs/`; NavData | Cooperative routing, destination-only driver; map overlays and optional guide contracts |
| Guild locations | `guildloc/State.lua`, `Map.lua` and sibling transport files | Explicit privacy state, bounded peer state; guild channel contract separate from personal Chronicle |
| Inventory/equipment | `inventory/`, `gear/` | Inventory plans/actions versus stat evaluation, hints, tooltips and rolls |
| Vendor utilities | `modules/Restock.lua`, `RestockPrompt.lua`, `MageSell.lua`, `MageSellWindow.lua` | Player settings and explicit interaction; no new automation authorized |
| Layouts | Layouts `Canon`, `Package`, `Compose`, `Merge`, `Journal`, `Engine`, adapters; Wizard `Model.lua` | Pure geometry/validation plus external Ellesmere adapter and recovery record |
| Crafting/shopping | Workshop `Materials`, `Stock`, `Shopping`, `CraftPlanner`, `Strategy`, `Session`, `View*` | Pure arithmetic separated from cooperative jobs and presentation |
| Item Advisor | Workshop `Advisor.lua`, `AdvisorData.lua`, `Sell.lua`, `Disenchant.lua`, `ViewAdvisor.lua` | Existing pricing/valuation services; imported scoped history does not enable Advisor decisions |
| Auction House | core `auction/Host.lua`, `Scan.lua`, `Mail.lua`; Workshop `auction/` | Native lifecycle proof separate from standalone preview/read transport; transactions remain unavailable |
| Market | Workshop `Prices`, `History2`, `Market`, `Valuation`, `MarketFacts`, `ServerMarket`, `Bridge*` | Local history versus explicit external generation; integrity and scope checks before atomic activation |
| Diagnostics | core `diag/`, `R.Perf`; Diagnostics companion | No-op instrumentation until capture; event, operation and retained-state gauges |

Shared UI layering is `chronicle/Style` → `Look` → `FrameLook` → `CraftLook`; Workshop uses core styling without loading Settings. `docs/dev-rules.md` documents deliberate older Look consumers. Unifying every style helper would change appearances and saved preferences without a demonstrated benefit.

Large modules need responsibility review, not line-count mandates: generated ClassicData/CompactData (12,148/9,251 lines) are data; third-party libraries are not refactor targets. Handwritten hotspots include RestedXPSkin (2,662), setup Window (2,639), TwichConfig (2,595), Wizard Model (2,386), AdapterEllesmere (2,030), Settings Window (2,004), ExplorerWindow (1,919), RemindersDesigner (1,914). Boundary-heavy adapters and validated serializers justify some size. Settings layout/render/search coordination and setup presentation are candidates for narrowly scoped extraction only when a change demonstrates duplicated responsibility. No framework/classes recommendation follows from these counts.

## SavedVariables and external contracts

**Source-confirmed:** all declared runtime variables are account-wide; character identity is represented inside tables.

| Variable | Owner / preservation boundary |
|---|---|
| `TwichUIDB` | Persist/Core/Profiles plus feature owners; active configuration, named profiles, pins, layouts, inventory and Workshop queue/known/vendor/storage records |
| `TwichUIBackupDB` | setup backup/configuration recovery |
| `TwichUIShareDB` | setup sharing; explicitly saved outgoing setup |
| `TwichUIRestoreDB` | setup restore points |
| `TwichUIChronicleDB` | `chronicle/Data.lua`; personal journal separate from configuration sharing |
| `TwichUIDiagnosticsDB` | Diagnostics persistence/capture state |
| `TwichUIWorkshopDB` | Workshop Prices/history; separate from queue/preferences in core DB |

Development-only LoadTest and LoadTestClock own `TwichUILoadTestDB` and `TwichUILoadClockDB`. See [persistence](../persistence.md), [profiles](../profiles.md), and Workshop source for exact subtrees. The persistence document's opening “all five” describes core variables, not the whole repository.

`Persist.Migrate` uses owned-copy work and commit; `Hold` swaps a future schema for a stand-in retaining `heldStored`, restoring the original on logout; `Recover` handles a persisted stand-in. Preserve this mechanism and deterministic migration tests. Actual logout/reload serialization remains client acceptance. Event bus `R:On` deduplicates function identity, `Off` defers removal during delivery, and callback faults do not abort subsequent callbacks. Timers generally use cancellation tokens where `C_Timer.After` cannot cancel physically; do not count an inert scheduled callback as active feature work without measurement.

Contracts requiring care: Forever API/event signatures, secure actions, optional Ellesmere and broker integrations, serialized sharing limits, guild location privacy, layout adapter allowlists, Market schema/transport/receipt/digest semantics. Experimental Workshop consent, native AH default, transaction restrictions and manual scan policy are release boundaries, not cleanup opportunities.

## Repository composition

**Newly measured**, `git ls-tree -rl HEAD`, byte sums (decimal MB):

| Root | Files | Bytes |
|---|---:|---:|
| All tracked content | 2,466 | 292,412,027 |
| assets | 161 | 118,597,199 |
| docs | 163 | 65,697,152 |
| test-output | 606 | 54,133,698 |
| core | 827 | 28,152,160 |
| NavData | 12 | 10,114,303 |
| tests | 326 | 6,965,258 |
| LayoutWizard | 25 | 2,089,998 |
| Settings | 68 | 1,526,067 |
| tools | 121 | 1,413,428 |
| Workshop | 63 | 1,200,518 |
| Layouts | 20 | 1,101,851 |

`du -sk`: audit checkout 292,136 KiB, shared `.git` 234,564 KiB (environment-specific disk allocation). `git count-objects -v`: two packs, 10,281 packed objects, 233,305 KiB packs; 33 loose objects/312 KiB. Git reported one 4-KiB worktree metadata garbage entry; no cleanup attempted. Available all-ref reachable blobs: 6,544 unique blobs, 425,124,015 uncompressed bytes. This is fetched local reachability, not every remote branch's complete history.

Largest current blob: `docs/reminders-revision/actual screenshots/ChatGPT Image Nov 10, 2026, 07_37_20 PM.png`, 3,335,163 bytes. Other largest blobs are screenshots/mockups/source artwork, not runtime Lua. Historical largest remains that image; an older `assets/Addon Image.png` is 3,227,874 bytes. `git log --all --numstat` largest textual churn: `81f789f` 23,732 added+deleted lines/58 paths; `d4166b8` 15,112/18; `98e0373` 14,059/684. Binary bytes are excluded from that churn metric; it is not compressed commit size.

`.gitignore:18` ignores future test-output files, but does not untrack existing files. History shows tracked output entered with style work (`98e0373`, later `81f789f`). Keep runtime artwork and generated navigation shipped in Git until a reproducible replacement exists. Source artwork is legitimate editable input; consider LFS only after measuring clone pain and generator compatibility. Prefer CI artifacts for new raw runs, compact hashes/results in docs. Do not rewrite history, split repositories, delete historical evidence or move fixtures in A1. The tracked editor workspace `pins/TwichUI.code-workspace` and historical session handoffs deserve a future portability review; packaging already excludes them.

## Verification and reusable measurements

All requested starting files exist: `tests/run.sh`, `tools/test_runner.py`, `tests/groups.json`, `tools/simlab/`, testing/testing-performance/testing-policy-proposal/testing-verification-audit/simulator-lab documents, and Workshop testing-roadmap.

**Source-confirmed:** shell entry delegates to Python runner; full discovery uses every test file, not a union of groups. Fifteen explicit groups expand shared test/syntax dependencies; simulator selections belong to requested groups. Separate test processes/private temporary roots, serial heavy layouts, capped offline workers, isolated optional simulator workers, source fingerprints, full failure logs and preserved negative controls are valuable existing architecture.

**Newly measured:** `./tests/run.sh feature auction-preview --list` selects 71 offline modules, 110 syntax paths, 14 preview poses plus lifecycle catalog. No tests or simulator ran. PR [26](https://github.com/Twich-Team/TwichUI/pull/26) already implemented profiles, safe opt-in two-worker catalogs and PNG improvements. Its recorded identical representative selection improved 319.913 → 249.833 seconds (21.9%); PNG decoding 12.7%. These are not full-suite gains.

**Previously measured:** testing-verification-audit attributes 1,878.73 seconds of an older Workshop run to combined pre-render work, versus 392.60 bootstrap. This does not isolate fixture construction from production calculations. Historical layout tests approached 3.9 GiB RSS. Independent launches/replays protect fresh-state determinism; do not remove them merely to reduce launch counts.

L3 [scoped reader evidence](../workshop/market-bridge-scoped-l3.md): dense 100 variants median validation 8.702 seconds CPU, largest slice median 7.76 ms/worst 8.08 ms, 4,174 slices; dense 155 variants 12.658 seconds median, worst slice 69.08 ms. Earlier exploratory outliers remain disclosed. No A1 benchmark repeated these measurements. Native scheduling, global GC and total frame latency remain unknown.

## Agent discovery and documentation

Root AGENTS delegates to CLAUDE and dev-rules; `.clinerules` repeats policy and supplies a narrower local-model workflow. README is user-facing; feature docs/contracts explain ownership; testing.md is current command authority. Testing-performance, testing-policy-proposal, testing-roadmap and milestone reports contain historical plans/evidence that require date/provenance interpretation. Prefer current source and current testing.md over an old plan's future tense.

Three bounded, informed read-only discovery exercises used one batched terminal call plus targeted follow-up reads (not independent cold agent trials). Python `perf_counter` measured only file/search work, **not reasoning or task completion time**:

| Task | Initial reads and result | Search/read time |
|---|---|---:|
| Reminders individual enable behavior | AGENTS/testing.md/groups navigation; Settings Reminders and settings test; guessed Prefs path absent. Header correctly led to `reminders/Config.lua:RM.SetEnabled`; settings test lines 132/223 distinguish global switch and individual reminder | 0.0119 s |
| Schema-3 reader/lifecycle/tests | Bridge, BridgeValidate, scoped Lua test; case-sensitive `Bridge` navigation search returned no matches. Follow-up found scoped Python test and L3 evidence | 0.0089 s |
| AH preview activation/cleanup/group | WorkshopLauncher.AuctionPreview, auction Window, Workshop Window; group `auction-preview` includes scoped states and lifecycle | 0.0073 s |

Initial inspection: two existing source/test files plus one failed path for Reminders, three for Market, three for AH; each also searched three navigation documents. Follow-up used Config/settings test/groups, scoped fixture listing/L3 document, and list-only plan respectively. Context was already informed by the audit: these are navigation demonstrations, not full implementation speed measurements. No token telemetry available. Future comparison should start fresh sessions on fixed baseline/candidate, identical prompts and budgets, log wall time/tool calls/files until a correct source/config/test answer, and score correctness before speed.

Observed drift: root “Current work” still directs all tasks to Reminders; `Libs/` casing contradicts actual `libs/`; `.clinerules` edit allowlist excludes newer companions; RELEASING still says six folders in multiple places. No systematic historical-doc link repair attempted. Smallest future system: short canonical AGENTS, thin tool-specific adapters, one current ownership table linking existing contracts and test groups. Do not create another documentation hierarchy.

## Evidence gaps and A1 verification boundary

No full/offline regression, simulator catalog, mutation campaign, client action, deployment or publication ran. Static source reads and Git measurements cannot establish actual frame budgets, secure behavior, live API timing or player data persistence. GitHub main protection endpoint returned 403; branch list reported `protected=false`, visible ruleset covered only `v3.*`, environments list was empty. CurseForge live files/compatibility were not independently checked. Documentation-only diff and path/link checks are the appropriate completion gate; A2 must separately authorize client work and executable changes.
