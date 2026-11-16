# Verification infrastructure audit — 2026-11-16

Evidence labels: source-inspected, unit-tested and simulator-tested as recorded
below. No real-client acceptance or game appearance validation is claimed.
Implementation branch: `feature/test-verification-optimization`, based on
`feature/workshop` at `5133a43477237bf7cd97a429a680a751a9533f7c`.
All production addon bytes and existing Lua expectations remain unchanged.
The original checkout, L3 branch, PR, output and simulator workspace are untouched.

## Baselines and current inventory

The 6,790.094-second failed cloud regression is historical, not the present
runtime. Its archived evidence is
[the integration record](workshop/auction-house/integration-evidence.json).
It had 243 modules, 191 launches and 30,221 structured checks. The later committed
[M1.5 report](evidence/bridge-m15/full-cloud.json) records **247 modules, 192
launches, 30,552 checks, 2,446.279 seconds, PASS in cloud mode**. Different source,
environment and contention prevent attributing the difference to this PR.
Neither cloud result satisfies the local release gate.

Current discovery is **248 modules: 235 Lua files and 13 Python modules**.
Current default scripts still define 192 launches and 178 screenshots, assuming
the runtime Settings inventory remains 58 pages. Full Settings discovers the
catalog from actual registrations; it is never capped at 58. Workshop now has
38 launches/37 screenshots, including Advisor poses; the old 25-launch summary
in the earlier performance document is historical. AH preview now has 35 poses,
including the bridge fixture; the 191-launch report predates that addition.
The 30,552 total below is observed historical coverage, not a promise that counts
cannot grow. Smoke construction checks are separate from structured markers.

## Coverage-to-cost matrix

Times and checks in this table are observations from M1.5, not new measurements.
All default catalog definitions, screenshots and negative expectations survive.

| Catalog | Launches / PNGs | Seconds / checks | Unique coverage and failure modes | Shared cost and intended scope |
|---|---:|---:|---|---|
| Lab guard | 0 / 0 | 0.388 / separate 36 controls | Refuses destructive/symlink/protected roots, bad shells | Cheap contract checks for launcher changes and release |
| Smoke | 2 / 1 | 21.275 / 56 page constructions | Real initialization/load order, every registered page constructs, narrow runtime error rules | Bootstrap and core/settings staging repeated; feature shared UI/core changes and release |
| Interaction | 4 / 2 | 22.367 / 244 | Notification controls, clamps, in-memory state, fresh replay and exactly one incorrect expectation | Same settings construction; feature shared controls and release; replay is intentional |
| Diagnostics | 6 / 0 | 24.520 / 101 | API contract, unguilded/group/guild/login boundaries, classified errors and rejection controls | Bootstrap repeated; core/message/timer changes and release |
| AH lifecycle | 4 / 0 | 17.768 / 431 | Unloaded/loaded activation, fresh replay, deliberately incorrect expectation | Same core bootstrap; relevant integration and release |
| AH preview | 35 / 35 | 321.393 / 4,563 | Browse, Shopping, Sell, Owned, Market, bridge, metadata, filtering, long lists, scale/resize, replay and incorrect expectation | Common nine-step behavior repeated in each pose; use focused `auction-preview` for relevant PRs, complete catalog for broad AH work/release |
| Workshop | 38 / 37 | 890.723 / 20,187 | Crafting, shopping sources, prices, strategy, compact UI, tooltip designer, Advisor, obstruction controls, fresh-process common-check comparisons and incorrect expectation | Entire behavior scenario and frame advancement repeated before each distinct pose; existing supported focused selections for features, all poses for release |
| Test Lab | 9 / 9 | 57.157 / 229 | In-game test presentation, mixed/failing/filtered/long/guided states and repeatability | Shared scenario repeated, distinct layout/interaction failures; selected poses for features, all for release |
| Settings | 58 / 58 | 363.860 / 1,029 | Actual runtime inventory, per-page construction/state, frame/scroll bounds and image dimensions | One launch per page including Home, staged once; explicit affected pages for feature work, all pages for shared framework/release |
| Reminders | 36 / 36 | 309.257 / 3,768 | Editor, hierarchy, drag, dirty/error/empty states, conditions, appearance and icon picker variations | Static setup and bootstrap repeated; explicit affected views for focused work, broad Reminders/default release retains all |

Offline modules cover pure unit tests, cross-component contracts, SavedVariables
and migration semantics, deterministic/reference models, compatibility, bounded
performance, artwork byte/pixel reproducibility, mutation infrastructure and
release packaging tools. Feature groups conservatively select those contracts;
full discovery includes future modules automatically. Actual production mutation
campaigns remain separate, required for money/quantity/rounding/order/eligibility
logic as stated in [testing.md](testing.md). No mutation count or seed is reduced.
Real-client-only acceptance includes combat, taint, protected actions, pointer
input, addon delivery, reload persistence, other addons, real fonts and packaged
installation. Simulator screenshots are structural checks, not committed pixel
baseline regressions; offline artwork reproducibility tests retain byte equality.

Repeated common assertions detect state leakage and nondeterminism. Distinct
poses also catch clipping, scale and empty-state defects even when screenshots
look similar. They are meaningful release coverage. Unrelated catalogs during
a focused feature change are avoidable workflow cost; removing their definitions
or replay checks would be lost coverage. Intentional incorrect expectations,
obstruction checks and classifier rejection controls are negative controls, not
ordinary failures to suppress.

## Cost attribution and rejected shortcuts

The old 6,790-second trace attributed 1,967.120 seconds to bootstrap across 191
launches (median 9.996 seconds). It attributed 2,780.124 seconds to post-bootstrap
through the first post-check rendering diagnostic, 382.141 to the subsequent
render/PNG/process tail, 109.325 to other native intervals and 654.360 outside
native artifact intervals. These are trace proxies, not isolated fixture,
assertion or encoder measurements. Workshop contributed 1,878.73 seconds of the
combined pre-render work. Assertion totals do not measure CPU cost.

Current source already stages immutable addon input once per script, seeds a
private UI cache once, uses independent native processes and has a faster PNG
reader than the original audit. Reimplementing these optimizations would add
complexity without demonstrated benefit. Staging was previously measured at
0.217–0.266 seconds; that is historical. New command telemetry separates real
elapsed/CPU/RSS observations from simulated time and native bootstrap timestamps.

Fixture construction, catalog discovery, actual-expression evaluation, manual
frame advancement and production recomputation remain coupled inside the native
scenario. No host clock exposed to the Lua fixture has been validated to split
those costs. `Lab.Check` receives already evaluated actual values; timing only
that helper would hide expensive work. No production result or assertion result
is cached. Without a proven expensive fixture-only derivation, changing Workshop
fixture semantics is rejected. Native startup/process reuse and batching several
screenshots per process are also rejected here: v0.1.37 has no tested reset
contract preserving fresh-install and replay behavior. No simulator build/patch
or security guard bypass was made.

The implemented pixel hot path uses the algebraically equivalent Paeth threshold
predictor, avoiding three Python `abs` calls per reconstructed byte. It retains
every decoded byte and screenshot assertion. Independent filter/tie/overflow/
alpha fixtures and real captures establish parity. The reader now refuses bad
signatures, truncation, CRC errors, invalid headers/dimensions, oversized output,
nonconsecutive image data, unsupported critical chunks, missing/invalid end,
corrupt compressed data and short/extra scanlines. Decoder budget is 256 MiB of
uncompressed scanlines, with dimensions at most 16,384 each; existing captures
are at most 1,600×1,200. No PNG dependency is added.

## Profiles and parallelism

[Current commands and policy](testing.md) are authoritative. Existing no-argument,
`fast`, `feature` and `full` scopes remain available. Development aliases fast;
integration merges explicitly affected groups and dependency tests/syntax;
release preserves full defaults and adds the existing archive checker. Reports
record selected/omitted scope, classifications, exit, source identity, timings,
actual artifacts, checks and the slowest twenty offline modules. Incomplete and
source-drift results remain failed. A feature PASS never sets a release flag.

`auction-preview` is a new scoped feature group: 67 offline modules plus eight
preview and four lifecycle launches, versus `auction-house`'s same offline scope
and 39 launches. It avoids **27 native launches and PNGs** by omitting documented
additional visual/stress variants. The old `auction-house` group still runs the
full catalog. Workshop Settings selects 97 offline modules and three launches,
avoiding 189 of 192 full launches. Development selects 11 direct tests and no
simulator, avoiding all 192 launches compared with unnecessarily choosing full.
These savings are scope differences, not equivalent full coverage or measured
engine speedups. New `verification-tools` selects four infrastructure modules
and ten representative launches for repeatable diagnostics.

Simulator execution is serial by default. Opt-in `--sim-jobs 2` schedules whole
catalogs into two fixed lanes; state-sharing scenarios within a catalog remain
serial. Each lane owns roots, home, WTF, fixtures, cache, artifacts and a lock
under `test-output/simlab-workers/worker-1` or `worker-2`. Immutable installation
inputs are read-only; every worker receives a private cache copy. A full catalog
dominates a filtered duplicate, avoiding accidental duplicate integration work.
The runner admits two workers only with at least four quota CPUs and 8 GiB
available under both host and cgroup limits. This is an admission guard, not a
kernel memory reservation. It refuses unsupported resource probing rather than
assuming unlimited capacity. Native existing timeouts and process-group cleanup
remain active. An uneventful two-worker sample does not establish capacity for
more workers; two is the hard CLI maximum.

## Validation and measurements

The frozen-run results are recorded below and in [compact machine-readable evidence](evidence/verification-optimization/results.json). Earlier failed
source-drift and namespace-denied attempts are preserved as failed/invalid timing
samples, never reclassified as passes.

## Twenty slowest historical offline modules

These are per-module wall times from the committed M1.5 report. That report
does not contain individual scenario CPU/wall rows, so a historical top-twenty
scenario ranking cannot be reconstructed honestly. New telemetry supplies those
measurements for executed representative launches.

| Module | Seconds |
|---|---:|
| `test_layout_wizard.lua` | 39.251 |
| `test_layout_publish.lua` | 34.680 |
| `test_workshop_history2.lua` | 30.331 |
| `test_layout_hardening.lua` | 24.909 |
| `test_layout_update.lua` | 21.164 |
| `test_workshop_market_scale.lua` | 21.051 |
| `test_layout_presets.lua` | 19.687 |
| `test_layout_complete.lua` | 18.169 |
| `test_layout_tooltip.lua` | 16.642 |
| `test_reminder_gallery.py` | 15.814 |
| `test_onboarding.lua` | 15.423 |
| `test_workshop_market_reference.lua` | 12.321 |
| `test_layouts.lua` | 11.233 |
| `test_workshop_valuation.lua` | 10.974 |
| `test_layout_force.lua` | 9.581 |
| `test_wizard_art.py` | 7.653 |
| `test_workshop_craftplanner.lua` | 7.089 |
| `test_layout_review.lua` | 5.397 |
| `test_mutate.py` | 5.190 |
| `test_layout_wizard_ui.lua` | 5.140 |

## Measured results and limits

Unit-tested: **248 modules / 149 Python methods passed**, exit 0, on `7eb1258`.
Instrumented elapsed time was **859.472 s**, accumulated test-child CPU
**1,092.397 s**, maximum reaped child RSS **4,242,276 KiB (4.05 GiB)**. The first
455 seconds overlapped the baseline feature measurement; this is validation and
bottleneck evidence, not an isolated before/after performance comparison. Layout
modules remained serial. Subsequent changed infrastructure was checked with the
focused runner/PNG/smoke/workflow tests, including catalog failure propagation
and real rejection of a malformed candidate archive. Full syntax passed for
**714 Lua files** (479 addon + 235 tests), Python and shell scripts; lab guard
passed all 36 cases. No production Lua expectation or fixture was changed.

Simulator-tested on frozen `4c5b545`, four infrastructure modules and the same
ten fresh native launches, nine PNGs and **2,211 structured assertions** in each
run. Both runs exited 0, including the two intentionally failed expectations.

| Catalog | Serial wall s | Two-worker wall s per catalog | Serial sampled native CPU s | Parallel sampled native CPU s |
|---|---:|---:|---:|---:|
| Workshop (`craft design wrong`) | 169.423 | 192.172 | 162.99 | 184.38 |
| Settings (`overview workshop`) | 31.847 | 39.535 | 27.68 | 34.45 |
| Reminders (`editor narrow`) | 42.504 | 52.423 | 39.23 | 48.46 |
| AH preview (`shell replay wrong`) | 70.026 | 78.674 | 63.94 | 70.13 |
| Complete selected feature command | **319.913** | **249.833** | — | — |

Two workers reduce this feature command's wall time by **21.9%** while individual
catalogs become slower. The workload overlaps; total CPU work is not reduced.
This is one bounded serial/parallel pair, with a further four-capture parallel
repeat of Settings/Reminders on final runtime code `88f504f`. That repeat retained
all expected checks and isolated paths. It is not evidence of a full-suite or
local game-assets speedup. Serial remains the release-certification default.

| Developer/decoder comparison | Before | After | Interpretation |
|---|---:|---:|---|
| Existing fast → development alias, 11 identical tests, median of 3 | 8.632 s | 8.786 s | Approximately nine seconds; no demonstrated speedup for the existing focused path |
| Same 1600×1200 PNG, median wall of 3 alternating pairs | 2.035292 s | 1.776474 s | **12.7% less decoder wall time** |
| Same PNG, median CPU | 2.026177 s | 1.771361 s | **12.6% less decoder CPU** |

All nine captured files decode to exactly identical dimensions and RGBA with the
old and new readers. Randomized filter/tie/alpha/overflow tests and corrupt-input
controls pass. A rough **46-second full-run decoder saving** is the product of
178 screenshots and the measured 0.259-second per-wide-image difference. This is
an illustrative projection assuming the same dimensions/filter mix, **not a
measured full-suite improvement**. Full parallel performance is not extrapolated.

Same-addon-source baseline workflow observations were Workshop 198.423 s for
three launches (overlapped offline work), Settings 29.092 s for two, Reminders
38.535 s for two, and scoped AH 70.366 s for three. All passed. The old AH driver
scoped copies of the existing runner/verdict catalog loops to three poses while
retaining every assertion. These whole-workflow differences include host/cache/
load effects; they do not demonstrate a causal decoder speedup. Baseline native
CPU was not captured separately for Workshop/Settings/Reminders; the AH baseline
sampled 70.06 CPU seconds. Missing measurements remain missing in the JSON.

### Startup, fixture, render and verdict attribution

Serial native launches totaled **291.859 s**, including **98.525 s bootstrap**
(median 9.377 s). The first timestamped texture diagnostic after the final check
provides a rendering-boundary proxy: observed launches contributed 127.299 s
between bootstrap and that diagnostic, then 22.758 s through process completion.
The remaining 43.277 s is post-bootstrap work without that boundary. These joint
intervals include actual-expression work, frame advancement, rendering setup,
PNG encoding and process tail; they are not pure assertion/GPU timings.
Catalog time outside native command intervals totaled **21.941 s**, containing
staging, fixture files, Python verdicts, PNG decoding and orchestration.

Fresh guarded Workshop staging measured **0.306–0.611 s**, median **0.309 s**;
the existing within-script immutable-stage reuse took **0.020–0.058 s**, median
**0.023 s**. Generating the entire Workshop fixture file catalog, including
shell/library guards, took **0.313–0.353 s**, median **0.352 s**. Those probes
used an audit-owned worker root and launched no simulator. The actual selected
Workshop verdict alone took **4.074 s wall / 4.056 s CPU**, including both real
PNG decodes and every original assertion/replay/negative-control check. These
measurements support keeping the existing setup reuse and focusing on avoided
launches, rather than caching assertion values or eliminating meaningful checks.
Native PNG encoding is still combined with rendering/process tail; Lua fixture
and expensive actual-expression CPU cannot be separated reliably here.

### Equivalence, negative controls and resources

All ten baseline/candidate transcripts and all ten serial/parallel transcripts
agree in check names, expected/actual values, layers, results, step/done markers
and object-identity relationships. Six serial/parallel transcripts match
literally; four contain different process-local `table: 0x...` addresses. Only
offline evidence comparison assigns first-seen, bijective IDs, preserving alias
relationships. Runtime verdicts and raw transcripts remain untouched. The four
final worker-repeat transcripts also agree by that method.

Native Workshop and AH wrong-expectation scenarios each failed exactly one
intended check and were accepted only by their existing negative-control
verdicts. Copied captured logs with (1) an altered replay value, (2) the negative
failure removed and counts adjusted, or (3) an unexpected Lua error were each
rejected with exit 1 by the real AH verdict, retaining real PNG checks. Runner
controls cover failed Python execution once, full output, Lua markers/nonzero
exits, timeout/descendant cleanup, failed worker propagation, source changes,
resource refusal, cache independence, lock refusal and symlink rejection. An
empty candidate ZIP was rejected by the real packaging checker and both local
and automated-release flags remained false. Missing release inputs fail early.

**Native pixel determinism is unresolved.** Eight of nine serial/parallel PNGs
also differ in decoded pixels; one matches exactly. An independent baseline
serial Workshop repeat already differs in both PNG bytes and RGBA. Thus native
captures are not pixel-baseline certification. Existing structural/dimension/
colour checks and all screenshots remain; offline artwork byte/pixel regression
checks are unchanged and passed. Decoder equivalence concerns the *same input
bytes*, not separate rendered captures. No parallel pixel-determinism claim is
made; keep serial release certification and real-client appearance acceptance.

The host quota was **four CPUs / 16 GiB**. Maximum sampled native-launch tree RSS
was **1.790 GiB**. A follow-up pipeline containing the two-worker repeat peaked
at **2.834 GiB** sampled tree RSS. Samples are 100 ms lower bounds, may count
shared pages twice and are not heap peaks. Reaped-child counters omit native
processes behind the PID namespace; native CPU figures use per-PID samples.
There were zero cgroup OOM events, no remaining simulator processes, no WTF
files and no artifact collisions. Both worker caches/roots/artifacts are separate.

The follow-up sampler exited 1 after all native/development phases passed because
its analysis helper selected a development report instead of the representative
report. That failed log remains. The decoder-only analysis was rerun with an
explicit feature-group filter; no native captures were repeated for that repair.
A separate intermediate run correctly failed its source-drift guard despite
13 passing modules. Neither failed aggregate is reported as a successful suite.

## Integration and release certification

Review this draft infrastructure PR into `feature/workshop`; keep L3's code and
PR independent. After L3 and infrastructure changes are integrated, freeze the
actual target commit and fixtures. Run affected feature/integration checks for
any changed dependency boundaries. Because this changes shared verification
infrastructure, require the complete local release gate before certification.

When a candidate archive and its existing packaging metadata are available, run
**one** `./tests/run.sh release --release-meta <meta.json> --release-zip <candidate.zip>`
from that frozen source with the installed game assets available read-only.
This includes the complete unchanged full gate and archive validation; running
`full` immediately before it would duplicate coverage. Preserve its report,
source/fixture/runtime identity, all captures and any failed attempts. Retain the
existing CI packaging checks and relevant real-client acceptance. A cloud or
focused PASS cannot substitute for that gate. No release archive, full candidate
simulator regression, production mutation campaign or real-client run was
performed by this audit; no merge, deployment, release or Market service change
was performed.

Remaining opportunities are per-step native monotonic instrumentation, validated
fixture-only indexing, large offline mock-client heap profiling, native capture
pixel determinism, and a proven reset contract before process/screenshot reuse.
Any broader parallel certification requires comparison on its actual frozen
source/resource budget. Keep the supported serial path and all default controls.

## Twenty slowest newly measured offline modules

Wall times include instrumentation and the stated contention. CPU is accumulated
reaped test-child CPU; layout heaps stay serial. These figures identify work,
not a comparison of runner speed.

| Module | Wall s | CPU s | Peak child MiB |
|---|---:|---:|---:|
| `test_layout_wizard.lua` | 107.625 | 107.406 | 4142.8 |
| `test_workshop_history2.lua` | 91.019 | 83.748 | 46.9 |
| `test_layout_publish.lua` | 73.252 | 73.067 | 1101.3 |
| `test_workshop_market_scale.lua` | 70.910 | 68.176 | 158.3 |
| `test_layout_update.lua` | 64.022 | 63.799 | 1299.6 |
| `test_layout_hardening.lua` | 57.397 | 57.269 | 1505.1 |
| `test_onboarding.lua` | 50.228 | 44.901 | 1719.7 |
| `test_layout_presets.lua` | 47.083 | 47.165 | 476.7 |
| `test_layout_complete.lua` | 42.532 | 42.396 | 1580.5 |
| `test_layout_tooltip.lua` | 39.146 | 39.019 | 1299.8 |
| `test_reminder_gallery.py` | 37.287 | 32.356 | 103.7 |
| `test_workshop_valuation.lua` | 33.176 | 32.473 | 92.0 |
| `test_workshop_market_reference.lua` | 29.544 | 27.631 | 13.4 |
| `test_layouts.lua` | 27.967 | 27.839 | 1065.9 |
| `test_workshop_craftplanner.lua` | 25.848 | 22.087 | 14.0 |
| `test_layout_force.lua` | 23.612 | 23.499 | 735.9 |
| `test_testlab_bench.lua` | 19.961 | 15.894 | 76.2 |
| `test_wizard_art.py` | 18.233 | 15.216 | 114.8 |
| `test_settings_window.lua` | 14.999 | 12.951 | 558.4 |
| `test_portable.lua` | 13.606 | 12.444 | 59.2 |
