# Phase A1 — prioritized findings

Baseline `d06d74c89de869ef2aae7a9c0ac2ca5e44bf6164`; 2026-11-16.
[Baseline/evidence map](phase-a1-baseline.md) · [Release decisions](phase-a1-release-engineering.md).
No production changes or new runtime test results accompany these findings.

## Executive assessment

The highest-value work is to separate verification from publication, make candidate bytes immutable through retry/promotion, measure the already-known Market cost in Forever, and reduce verification/navigation friction using existing tools. The addon already has useful boundaries: seven packages, pure computation separated from UI in Workshop, shared core styling, feature-owned settings, bounded cooperative work, explicit experimental gates and preservation of future schemas. A rewrite would discard substantial safeguards without demonstrated benefit.

Ranking considers risk reduction and recurring development cost, not just speed. Effort is relative (S: narrow change, M: cross-file work, L: subsystem campaign); client scheduling/acceptance can dominate elapsed time independently. Every proposed change below is deferred to A2 or later. A hypothesis is not a confirmed gameplay defect.

## Ranked decision register

### 1. Verification disappears when publication is held

**Source-confirmed; high confidence.** `.github/workflows/release.yml` is the only workflow. Main/beta/stable-tag pushes plan a release; Lua install, tests, training refresh, packaging and artifacts all require `publish=true`. `tools/release.py:plan` returns false under the current hold. PRs have no workflow trigger. Thus a successful held main run is not build/test evidence.

Smallest improvement: independent read-only PR/main verification plus a build-only path; retain publication hold and separate protected publisher. Benefit: dependable integration feedback without development uploads. Effort M; risk medium (event selection/credentials). Dependency: owner-approved CI policy and hosted resource budget. Success: ordinary PR/main events produce the selected verification report and zero public writes; held candidates can still build. Verify event matrix and mocked publication refusal; rollback by disabling new verification workflow, never by lifting the hold.

### 2. A rebuilt retry can distribute different bytes under one version

**Source-confirmed path; high confidence, occurrence unproven.** In `tools/release.py:publish`, an existing uploaded GitHub ZIP asset is retained based on name/state. CurseForge receives the local `zip_path`; no digest comparison binds it to the retained GitHub asset. Workflow artifact overwrite and build-time upstream training refresh make changed rebuild inputs possible. A draft with a completed GitHub upload but pending/failed CurseForge upload is the relevant trigger. No assertion that a published release already diverged is made.

Smallest improvement: record/verify candidate SHA256 and provenance in release metadata/state; promotion and retry must consume the same immutable artifact, rejecting a mismatched local ZIP. Move training updates to an explicit reviewed source update, or pin and record an approved upstream revision before certification. Benefit: trustworthy source/package identity and recoverable retries. Effort M; risk medium (existing draft recovery). Dependencies: candidate build separation, handling existing markers lacking hashes. Success: mismatched-byte retry refuses before upload; both destinations reference the certified hash. Verify fake GitHub/CF failure sequences, same-byte retry and old-marker refusal/reconciliation. Rollback retains original draft/assets and hold; never silently overwrites published files.

### 3. Scoped Market validation exceeds its nominal scheduling target

**Previously measured + Source-confirmed; high confidence in offline cost; Real-client acceptance required.** `TwichUI_Workshop/Bridge.lua:validate`, `step`, `schedule`, `BridgeValidate.lua:schema/Record` and `BridgeCodec.lua` are the path. Explicit external load/replacement starts whole-generation validation; `C_Timer.After(0)` schedules cooperative continuations. L3 records 100 dense variants: 8.702 s median CPU/4,174 slices, worst largest slice 8.08 ms; 155 dense: 69.08 ms worst slice. `step` tests elapsed time only after a coroutine resume; indivisible work and GC can exceed a nominal 3 ms. `schema` also performs `anyOf` branch validation without the supplied tick. Its contribution is a hypothesis, not measured attribution.

Smallest improvement: first use existing Bridge counters/Diagnostics to establish a native operating envelope, separating compile, validation, frame time and completion wall time. Only then shorten measured indivisible units or reduce supported delivery budget. Do not weaken schema/hash checks, raise limits, tune global GC or change the Market contract. Benefit: measurable responsiveness and honest capacity defaults. Effort M investigation; optimization unknown. Risk high if integrity/atomic activation changes. Dependencies: approved disposable client installation and synthetic exact fixtures. Success: agreed p95/p99/max callback/frame budgets and wall completion across sparse/dense loads, corrupt replacement preserves prior generation. Verify offline parity, existing scoped tests and targeted client cycles; rollback reader changes/capacity independently with previous artifact intact.

### 4. Live release authorization is implicit in branch/tag pushes

**Source-confirmed + Newly measured remote metadata; high confidence.** Main historically maps to alpha, beta to beta, stable tag to release; no protected environment is referenced. Visible environments are empty; branch listing reports main/release/workshop unprotected. Protection detail API was denied, so organization-level restrictions are not fully known. Visible tag ruleset protects `v3.*`, while published releases use `v1.*`.

Smallest improvement: protected main, short branches, explicit approved artifact promotion; temporary stabilization branches only when needed. Keep all current branch contents and publication hold untouched in A1. Benefit: fewer coordination merges and deliberate public releases. Effort S/M; risk medium during policy transition. Dependencies: owner privileges and required check names. Success: ordinary merge cannot publish, stable tags cannot move, approval targets a specific hash. Verify ruleset/event tests and a no-upload rehearsal; rollback policy configuration without branch/history rewrites. Detailed options are in the release report.

### 5. Existing focused verification needs safer automatic navigation, not another runner

**Source-confirmed; high confidence.** `tests/groups.json` and `tools/test_runner.py` already implement recursive tests/syntax and explicit simulator subsets. They do not map changed sources to required groups. Development selection is intentionally narrower; shared edits can be underselected by an agent. A1 list-only AH preview selection confirms 71 modules/110 syntax files and scoped/lifecycle scenarios.

Smallest improvement: extend the existing group metadata with reviewed source ownership and a conservative selection suggestion. Unmapped/shared/global-init/migration files must demand explicit broader selection; full discovery remains independent. Benefit: fewer wrong selections and less ordinary full certification. Effort M; risk high if treated as proof of complete dependency analysis. Dependencies: ownership map and known shared boundaries. Success: representative changes select all expected groups; unknown sources never silently pass with empty coverage; ordinary feature costs stay scoped. Verify mapping fixtures/negative cases and compare emitted plans, not full catalogs. Rollback to manual groups; keep all existing tests and negative controls.

### 6. Workshop simulator cost still lacks actionable phase attribution

**Previously measured; high confidence in aggregate, Hypothesis requiring validation for causes.** `docs/testing-verification-audit.md` records older Workshop pre-render work of 1,878.73 s, bootstrap 392.60 s; PR #26 already improved isolated parallelism and decoding. Manual simulator time and assertion counts are not CPU attribution. Repeated fixture setup may cost time, but production computation inside assertion expressions is confounded.

Smallest improvement: one bounded representative serial sample with existing host timing and clearly delimited fixture/production phases, only if a usable clock can be verified. Retain separate processes, replay and wrong-expectation controls. Benefit: identify a real hot path before caching or fixture changes. Effort M; risk medium if fixture semantics change. Dependencies: frozen source/fixtures and no competing heavy work. Success: attribute most representative wall time reproducibly and prove identical assertions/negative controls for any later improvement. Rollback instrumentation/optimization independently; no permanent profiler or process-reuse framework. Do not claim a full-suite percentage from the 21.9% representative PR #26 result.

### 7. Historical output is a material part of every checkout

**Newly measured + Source-confirmed; high confidence.** 606 tracked `test-output/` files total 54,133,698 bytes (18.5% of tracked bytes). `.gitignore` cannot remove files already tracked. Style commits `98e0373` and `81f789f` explain provenance. Assets and docs contain a further 184.3 MB; many are legitimate source images/evidence.

Smallest improvement: future raw outputs as retained CI artifacts; preserve compact provenance and selected review images in Git. Separately inventory dependencies before proposing untracking old output in a normal commit. Benefit: smaller future checkouts/context scans; old clone history will not shrink without a history rewrite, which is not recommended. Effort S inventory/M migration; risk medium (tests or historical references may rely on evidence). Dependencies: artifact retention/access policy. Success: no new raw-output tracking, referenced evidence remains retrievable; measure checkout savings after any authorized removal. Verify tracked-path dependencies and links; revert normal commit to recover. Do not split repositories or move runtime assets to LFS by default.

### 8. Agent instructions and release prose contain avoidable drift

**Source-confirmed; high confidence.** AGENTS “Current work” redirects to Reminders, `Libs/` case is wrong, `.clinerules` excludes newer companion edit locations, and RELEASING repeatedly says six packages despite seven in `ADDONS`/.pkgmeta. Current testing guidance is substantially reconciled by PR #26; historical performance documents remain dated evidence, not current mandates.

Smallest improvement: canonical short AGENTS plus minimal adapters; one ownership/test-group map linked to existing contracts; fix exact stale statements. Keep existing recipes and feature docs. Benefit: faster correct discovery and fewer mistaken scope/verification decisions. Effort S; risk low (accidental removal of safety requirements). Dependencies: agree authority order. Success: three identical cold discovery tasks locate source/config/tests without wrong-path detours; links/casing valid; no conflicting verification policy. Verify static links and blinded task comparison; revert prose if instructions regress. A1's informed file-read timing is not a cold-agent benchmark and has no token estimate.

### 9. Startup attribution misses file execution and SavedVariables loading

**Source-confirmed gap + Hypothesis requiring validation; medium performance confidence; Real-client acceptance required.** Core manifest loads 276 entries. `Core.lua` arms startup capture in its `ADDON_LOADED` hook, explicitly after files and SavedVariables have loaded. Its saved-data/init-hook timers cannot explain all login cost. Always-loaded definitions may cost compile/memory even when windows stay unbuilt.

Smallest improvement: measure client login/reload and first-open separately with existing Diagnostics/LoadTest facilities; compare experimental Workshop off/on and typical profiles. Keep existing LoD packages; do not split more companions until a meaningful startup contributor is proven. Effort M; risk low for measurement. Dependencies: authorized client, controlled addons/data. Success: distinguish file/SV load from init hooks and lazy frame construction with repeatable distribution and memory observations. Verification: frozen package, synthetic data fingerprints, cold/warm samples; rollback only disposable measurement state. No claimed login speedup.

### 10. Large list work and retained caches warrant targeted measurement

**Source-confirmed structure + Hypothesis requiring validation; medium confidence; Real-client acceptance required.** Workshop `auction/ViewBrowse.lua:Start/Step`, `ViewMarket.lua:Start`, and `BrowseData.lua` construct/filter catalogs, sort and paint results on explicit opening/search/source changes. Discovery and sorting are already cooperative. Tokens, hidden-page guards, caching and timeouts already limit stale work; do not label all scheduled work a leak. Settings `Window.lua` and Reminders page reuse constructed controls; Workshop tooltips read cached/local market facts. Large datasets may still create allocation/sort/paint spikes.

Smallest improvement: profile catalog completion, rapid filter changes, first/cached tooltip and repeated open/close at existing caps; attribute cooperative sorting and discovery separately from painting. Optimize only the measured operation. Effort M; risk medium (ordering, stale state, selection/scroll restoration). Dependencies: representative fixtures and existing diagnostic scopes. Success: agreed worst-frame budget, bounded retained growth after comparable GC points, stable row/selection identity and zero continuing page jobs after close/disable. Verify focused auction-preview tests plus client cycling; revert optimization while keeping safety tokens and caps.

### 11. Large UI/adapter files are navigation hotspots, not evidence for a framework

**Newly measured size + Source-confirmed responsibility; medium confidence of maintenance benefit.** Baseline lists Settings Window, setup Window/TwichConfig, Wizard Model and AdapterEllesmere. Core styling has multiple deliberate layers; generated layout data dominates Lua line counts. Shared namespace relationships mean a filename-only discovery can miss ownership (Reminders Config versus guessed Prefs).

Smallest improvement: document responsibility boundaries first; on a later functional task, extract only a demonstrably independent repeated helper with unchanged call contract. Benefit: smaller review/context surface. Effort S map/M extraction; risk medium-high for load order and saved-state serializers. Dependencies: caller/test map and a concrete repeated responsibility. Success: reduced files/context needed for the same task and no added dependency cycle or startup work. Verify focused groups and manifest load order; revert extraction as one commit. Do not refactor generated data, libraries, every large file, or introduce classes/service layers.

### 12. Forever compatibility metadata can silently fall back

**Source-confirmed; high confidence; Real-client acceptance required for compatibility.** `tools/release.py:CurseForge.game_version_id` filters Forever versions, selects an exact name if present, otherwise a lower/newest entry and logs only a warning. Current interface `16001` maps to `1.60.1`. Upload metadata includes version/channel/changelog but no external addon relationship list. Seven bundled addon dependency headers are separately checked. Live CurseForge mappings and published file compatibility were not independently verified.

Smallest improvement: public promotion requires exact approved Forever mapping, or an explicit documented owner override; keep optional integrations optional. Benefit: avoid misleading distribution metadata. Effort S; risk low/medium (blocking publication when API mapping lags). Dependencies: current client/package acceptance and CF mapping availability. Success: missing/empty/mismatched mapping fails before public upload; override is recorded with candidate hash. Verify fake API fixtures and explicit override path, never a test upload. Rollback to a held unpublished candidate, not a guessed compatibility claim.

## Preserve these systems

- `R:On/Off` identity deduplication, mutation-safe dispatch and isolated fault reporting.
- Persist future-schema holding/recovery, profile application sequencing, player-authored records and layout recovery journals.
- Workshop experimental opt-in and service suspension; native AH default, unavailable transactions and manual external source activation.
- Bridge integrity, scope-completeness semantics, atomic replacement, exact prices and bounded decoded cache (24 records).
- Pure planner/data modules, cooperative Strategy jobs and existing core UI styling reused by LoD companions.
- PR #26 scoped profiles, independent full discovery, process/resource isolation, serial heavy layouts, source fingerprints, replay/negative controls and full failure evidence.
- Navigation's destination-only OnUpdate driver, Reminders event coalescing and animation groups, glow controller's event coalescing. These already avoid obvious idle polling; measure before replacing them.

No source-confirmed exploit, data-loss incident, timer leak or native frame-latency regression was established in A1. Representative hardening paths were inspected; this is not a guarantee of their correctness in the client. Core partial-init failure falls back to minimal tables and continues hooks, making failure diagnostics and player-data recovery important acceptance cases, not grounds for a speculative rewrite.

## Bounded next campaigns

1. **Release isolation and immutable promotion:** findings 1/2/4/12; one workflow/tooling PR, mock failure/retry tests and build-only rehearsal; hold stays until separate owner approval.
2. **Native Market operating envelope:** finding 3; synthetic sparse/dense generations, compilation/slices/frame/GC/wall measurements, corrupt-replacement preservation; stop with a supported envelope and at most one measured optimization proposal.
3. **Agent navigation and conservative verification selection:** findings 5/8/11; canonical short instructions and ownership map, three fixed cold tasks, mapping negative cases; no feature refactor.
4. **Verification cost attribution and artifact hygiene:** findings 6/7; one representative Workshop profile, tracked-output dependency inventory and retention proposal; no full certification or removal of controls.
5. **Client startup/lifecycle/list acceptance:** findings 9/10; frozen seven-addon package, login/first-open/hidden/disabled/profile/combat cycles, player-data fingerprints and targeted responsiveness measurements; no live transactions.

Each campaign requires a separate task. A1 ends with documentation review, not implementation.
