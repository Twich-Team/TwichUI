# Phase A2 — runtime architecture and efficiency

2026-11-16. Baseline: `67f3de7b85932fa05c439a67dd9d04db71d6cddb`. Report-only investigation; publication remains
disabled. No production change, simulator certification or new runtime benchmark.
PR #37 passed CI and retention review before its normal merge. Market acceptance
and its existing measurement tools were left alone.

## Executive assessment

There is no evidence here for a rewrite, more addon packages or a confirmed
memory leak. The most valuable next task is a controlled Forever capture separating
login/reload, first Settings open and repeated use. The clearest optimization
candidates are narrower: Advisor's synchronous catalog finalization and repeated
queue scans on tooltip rebuilds. Their source cost is confirmed; player-visible
latency is not. A small normal-view hover callback is avoidable but low priority.
Do not turn these observations into speculative parallel refactors.

Evidence: **source-inspected**, with previously measured results explicitly cited;
**not runtime-tested in this campaign**. Reuses [A1 findings](phase-a1-findings.md),
[ownership map](../architecture.md), [Diagnostics](../diagnostics.md),
[lifecycle policy](../lifecycle.md), [verification policy](../testing.md) and
[verification-cost audit](phase-a2-verification-hygiene.md). Existing offline
measurements do not establish gameplay improvements. No new timing percentages
or frame-latency claims are made.

## Startup, saved data and first use

[Core manifest](../../!!!TwichUI/!!!TwichUI.toc) has **276 file entries**, all
present, totaling **5,486,129 source bytes including libraries** (new static
inventory, not heap size or load time). Lua definitions and top-level registration
execute regardless of whether a feature window is opened. Core loads namespace,
persistence, profiles and launchers before features. Six production companions
are already load on demand: Settings, NavData, Diagnostics, Layouts, LayoutWizard
and Workshop. Lazy page construction and LoD solve different costs.

`Core.lua` ADDON_LOADED hook arms Diagnostics only **after** file execution and
SavedVariables loading. It then times `Persist.LoadMain` and numbered `OnInit`
hooks; `Profiles.Load` sits between those scopes without its own explicit scope.
Thus `core.savedData` is not total saved-file deserialization or startup time.
The external client/load-test baseline and named hook attribution are missing,
not evidence that all 276 files should move into new packages.

`Persist.lua:LoadMain` normalizes, migrates or holds future schemas before consumers
run. `Profiles.lua:Load/Swap` selects the character profile, preparing independent
incoming data and preserving outgoing data. These integrity/readiness operations
must stay before feature activation. Do not defer them behind Settings or skip
checks to make login look faster. Feature `Refresh` hooks commonly register events;
registration alone is not proof of expensive initialization.

`SettingsLauncher.lua:L.Load` already loads Settings on demand and handles missing,
disabled or incomplete companions. `TwichUI_Settings/Window.lua:UI.Open` describes
pages once, constructs the shell once and builds visited pages through
`UI.Navigate/BuildView`. Search builds its normalized index once in
`TwichUI_Settings/Search.lua:Search.Build`, without drawing every page. Gear's
`gear/Window.lua:Frame/GW.Refresh` defers widgets until shown and returns while
hidden. Training's card is created on demand; its `T.Refresh` keeps only wanted
events. Retaining constructed frames avoids rebuilding on every open; it is not
unloading and is not by itself a leak.

## Background work and memory

Representative source review found useful controls, not a blanket polling defect:

- `nav/Nav.lua:OnUpdate/StartDriver/StopDriver` uses one driver while navigating;
  `nav/Flight.lua:OnOpened/OnClosed/Sync` starts its ticker only for a relevant
  flight-map visit, cancels it on close/disable and tokens delayed auto-selection.
- `reminders/State.lua` coalesces events, and Controller delayed work uses tokens.
  Display/glows use animation groups. `reminders/Share.lua:Tick/Ensure` and
  `setup/Share.lua:StartWatchdog` cancel watchdogs when no active transfer remains.
  Terminal transfer retention is bounded; these are not perpetual idle timers.
- Settings `UI.Refresh` returns while closed and redraws only the active page;
  slider/swatch changes refresh their own row. Navigation/close stop previews,
  settle motion, cancel color pickers and end sizing. No evidence supports
  rebuilding hidden pages on every event or evicting all cached views.
- `TwichUI_Workshop/ViewAdvisor.lua:Render/Search` tokens old jobs and checks
  visibility. Its OnHide increments both tokens, releases catalog/results and
  clears selected detail state. Catalog row retention grows with input while
  open, then drops; it is not proven unbounded growth across opens.
- `TwichUI_Workshop/Window.lua:W.Suspend` closes views, stops scan/watch/bank,
  tooltip and auction services, cancels Bridge work and resets session/queue
  runtime state. `W.Resume` checks experimental activation. Hidden and disabled
  remain different states; already-committing atomic saves may complete safely.
- `Bridge.lua` already bounds decoded records to 24; source payload retention is
  a deliberate active-generation contract. The separate [Market investigation](phase-a2-market-performance.md)
  owns its measured validation costs and native acceptance. Do not duplicate or
  relabel those measurements as new findings here.

No monotonically growing listener/frame/cache count was measured. Lua heap rises,
retained widgets, temporary allocations and a leak are different observations.
Use comparable checkpoints and existing gauges; do not tune global GC. The old
~4 GiB offline layout-mock peak in the verification audit concerns test fixtures,
not four GiB of addon memory in Forever.

## Ranked modernization candidates

Each row is a separate task. S = narrow local change; M = several cooperating
paths. Benefits below are opportunities, not measured savings. Optimize only
when the named source path contributes meaningful client cost.

### 1. Fill the startup attribution gap before moving work (M; measurement first)

**Confirmed measurement gap:** `Core.lua` ADDON_LOADED/init dispatch and
`Profiles.lua:Load`; see startup boundaries above. Existing scopes cannot explain
file execution/SavedVariables reading, and hook indices are harder to map back to
owners. Smallest task: use existing armed Diagnostics and LoadTest/client counters
for outside-versus-inside startup; add a narrow profile-load scope and stable hook
owner labels if a capture cannot attribute a material contributor. No new profiler
or package split. Benefit: choose one actual eager resource to defer, rather than
shifting an unknown cost into first open.

Success: source/fixture-identical cold/warm login/reload, init and first-open
intervals are separately recorded with p50/p95/max and instrumentation overhead;
no interval is reported as another. Verify startup readiness, failed/future schema,
profile-before-hooks and Settings-never-opened contracts with core tests; shared
startup changes retain the full gate in their later task. **Forever required.**
Risk medium: early-clock attribution and load order. Rollback instrumentation
alone; retain the original synchronous integrity boundary.

### 2. Bound Advisor finalization, not just discovery (M; suspected hitch)

**Confirmed synchronous work, unknown latency:**
`TwichUI_Workshop/AdvisorData.lua:D.Catalog` yields every 160 discovery operations
but calls `table.sort(rows, ...)` without a yield. After completion,
`ViewAdvisor.lua:Render` scans the catalog for categories in one callback;
`Search` finishes with selection scans/paint outside its per-batch scope.
Batch count does not bound the cost of one item-information call or final sort.
Do not infer a leak or a guaranteed hitch from those structures.

Smallest implementation, if measured: replace only the dominant finalization step
with cooperative work, using the existing bounded-sort convention in
`auction/BrowseData.lua` as a local reference. Preserve order, item identity,
viewport and source-change cancellation. Benefit: shorter worst callback on large
known catalogs; total CPU may stay the same. First capture slice/finalization/
paint separately at ordinary and large synthetic catalog sizes. Success: agreed
p95/max callback budget improves without worse completion beyond the agreed bound;
identical results and zero stale paints after hide/disable/source change.
Verify Advisor offline contracts plus focused replay/negative controls and repeated
hide/reopen; **Forever frame-time acceptance required**. Risk medium (ordering,
selection and partial results). Rollback only finalization changes.

### 3. Avoid repeated tooltip reservation scans when unchanged (S/M; unmeasured)

`AdvisorData.lua:D.Reserved` walks queue entries/materials and a finished queue
plan's items. `D.Tooltip` calls it for each requested item; no planner job is started,
which is good. Rebuilding tooltips across several items can repeat these scans.
Source complexity is confirmed; no tooltip latency/allocation regression is proven.

Smallest task: measure call counts/time at a large supported queue, then add a
small derived reservation index only if useful, keyed to all queue/strategy state
that changes its answer. No cached price decisions or shared mutable plans.
Success: identical reservation/pending results, fewer examined queue lines per
repeated unchanged tooltip, and invalidation on edits/profile changes/suspension.
Verify crafting/Advisor/worth contracts including pending/failed plans; **Forever
warm/cold tooltip captures required**. Benefit unknown until measured; risk medium
(stale reservations alter advice). Rollback the index and retain direct scans.

### 4. Stop normal-view hover callbacks in the Cozy guide (S; low impact)

**Confirmed avoidable work, no measured gameplay impact:**
`!!!TwichUI/guides/CozyBagWindow.lua:Build` installs a shown-window OnUpdate hook
permanently; every 0.1 s it computes `not C.Compact() or ...`, which is always true
in full view. It still enters the handler each shown frame and checks the throttle.
Hidden frames do not receive normal OnUpdate calls; do not call this hidden work.

Smallest task: attach the hover driver only in compact mode through existing
`W.Render`, show/hide and size-toggle transitions; keep the shared fader. Benefit:
zero guide hover callbacks in full/closed mode, unknown absolute CPU saving.
Success: callback count is zero there, compact hover/drag/fade behavior unchanged.
Verify Cozy guide/mock frame tests, reduced motion and rapid mode changes;
**Forever pointer/appearance check required**. Risk low/medium (opacity restoration).
Rollback the driver gating alone. This is a small follow-up, not the first campaign.

### 5. Attribute profile application before suppressing refreshes (S; measurement)

`!!!TwichUI/Profiles.lua:Apply` synchronously runs switch sync and named look/layout/
views callbacks, then `UI.RefreshValues`, followed by `Changed` notifications.
It already deduplicates applier names. There is no measurement proving that any
callback is duplicated or expensive; broad skipping could leave secure buttons or
hidden-but-later-opened views stale.

Smallest task: scope the existing named phase entries during Diagnostics capture;
only coalesce a specific repeated visible refresh if one capture proves duplication
and its dependencies permit it. Success: every required callback still runs in
order, costs map to owners, and any later optimization reduces measured repeated
work while preserving generation checks and failures. Verify profile switch,
copy/reset, import, combat rejection and unopened Settings contracts; **Forever
profile-cycle capture required**. Risk medium. Rollback scopes/coalescing separately;
keep atomic preparation and secure reapplication.

### 6. Simplify Settings navigation only at a tested responsibility boundary (M)

**Confirmed maintenance coupling, unmeasured development benefit:**
`TwichUI_Settings/Window.lua:UI.Navigate/DrawResults/BuildWindow` combines page
ownership, search departure offsets, companion preview cleanup, scroll positioning,
window sizing and delayed row reveal. Changing search-to-page behavior crosses
those responsibilities; file length alone does not justify a split. Existing
`Kit`, `Search`, `Companion`, widgets and feature setters already separate much.

Smallest task during a concrete navigation fix: isolate only navigation/scroll
state transitions from frame construction, keep the same API and one window,
and keep async reveals tied to the originating page. No new UI framework or
unification of deliberately different shared styles. Success: fixed search/back/
row-reveal scenarios need fewer cross-responsibility edits, preserve offsets and
create no extra views/callbacks. Compare correctness/tool-read counts on the same
three navigation tasks before claiming faster AI development. Verify Settings
navigation/search/preview contracts and focused captures; **Forever keyboard,
scroll, resize and font acceptance required**. Risk medium. Revert the extraction
as one commit. No startup/CPU benefit is claimed; leave it alone without a real
functional task.

## Required client evidence and implementation order

First run one controlled measurement task covering startup and the suspected
Advisor/tooltip paths; do not start six implementation branches. Freeze commit,
package, Forever version, UI scale, synthetic data sizes and optional-addon set.
Compare Workshop experimental off/on, Settings never opened/first/repeated open,
large Advisor catalog with rapid search/hide/source changes, unchanged tooltip
rebuilds and repeated profile cycles. Record p50/p95/max callback/frame/completion
time separately, listener/frame/cache counts and comparable memory checkpoints.
Repeat equivalent cycles to distinguish warm caches from retained growth. Include
disabled/closed idle intervals and instrumentation overhead. No live transactions,
private SavedVariables or new Market validation benchmarks are needed.

Then implement **one measured hotspot**, likely Advisor finalization if it breaches
the agreed frame budget; tooltip indexing follows only with evidence. The Cozy
driver change is optional and small. Profile instrumentation is diagnostic, and
Settings extraction waits for a relevant functional change. Existing full-gate
requirements apply to any later shared initialization change, not this report.

Leave event-bus identity deduplication and mutation-safe dispatch, future-schema
holding/recovery, combat rejection/defer rules, experimental consent, native AH
default, replay/negative controls, token cancellation, capped caches, lazy page
construction and retained reusable widgets unchanged. Do not merge styling layers,
introduce a generalized scheduler, split packages/repositories, or tune global GC.

## Report verification

Source paths/functions and manifest arithmetic checked at the baseline; local
report links resolve. Only this report changes on the audit branch. No new runtime
results, client acceptance or optimization were produced. Publication policy
remains false. Rollback is a normal revert of this documentation commit.
