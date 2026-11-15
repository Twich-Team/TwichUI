# Proposal: verification policy and measured runtime

Status: separate documentation proposal requested during PR #19 verification.
No performance optimization, test selection, assertion, timeout, fixture, runner,
or default full catalog is changed by this proposal. The already frozen smoke
correction is documented separately in [AH integration verification](workshop/auction-house/integration-verification.md).
Do not adopt new infrastructure work as part of that reconciliation.

## Recommended developer policy

Proposed wording for the policy paragraphs in `docs/testing.md`, with matching
short references in `AGENTS.md` and `CLAUDE.md` in a separately reviewed change:

> Run fast focused tests frequently. Before checkpoint commits, run the affected
> feature suites, including their shared dependencies. For ordinary feature
> changes, use relevant supported simulator scenarios and retain their replay,
> intentional wrong-expectation and error-classification controls.
>
> Reserve full addon-wide verification for major milestones, high-risk shared
> changes, release readiness, or explicit requests. Shared architecture, load
> order and saved-data boundaries are high-risk examples. Record why full
> verification is required. Focused success is not complete regression evidence.
>
> Never weaken assertions, hide failures, silently remove coverage or represent
> a narrower selection as a full pass. Keep full discovery and its default
> simulator catalogs intact. A full result must include the actual exit code.
>
> Do not repeat a full suite on the same tested source and relevant environment
> unless investigating a specific nondeterministic failure. Record that reason.
> Prefer the affected scenario first when it can reproduce the issue. Preserve
> failed results; a clean retry does not erase them. Documentation-only evidence
> updates do not require another addon-wide run when tested code is unchanged.

The current written policy is already tiered. This proposal makes the full-run
triggers and repeat rule explicit; it does not replace the existing safety gate.
The user's instruction applies to subsequent work now; the text above is the
proposed repository wording, not an implemented runner change.

## Current run: complete, failed, not repeated

Command: `./tests/run.sh full --profile cloud`, frozen commit
`cbb48c8b90d3c6949a09537c5fedad67ebe2af23`, target `572da3a`.
Total wall time: **6,790.094 s = 1 h 53 m 10 s**. Exit **1**.
243 offline modules and 706 Lua syntax checks passed; 191 simulator launches
emitted 30,221 structured checks. Nine of ten simulator catalogs passed.
Workshop failed three guild-bank checks in each of `overview`, `empty`, and
`notice`, plus their common-check replay comparison. Smoke passed while actually
encountering the narrowly classified native voice error. No full rerun was made.

### Measured suite wall time

| Stage | Seconds | Minutes | Result |
|---|---:|---:|---|
| Offline tests, syntax and remaining orchestration | 897.025 | 14.95 | PASS |
| Lab guard | 0.591 | 0.01 | PASS |
| Smoke | 71.779 | 1.20 | PASS |
| Interaction | 69.265 | 1.15 | PASS |
| Diagnostics | 75.233 | 1.25 | PASS |
| AH lifecycle proof | 55.628 | 0.93 | PASS |
| AH preview | 938.088 | 15.63 | PASS |
| Workshop | 2,535.870 | 42.26 | **FAIL** |
| Test Lab | 168.778 | 2.81 | PASS |
| Settings | 1,036.521 | 17.28 | PASS |
| Reminders | 941.318 | 15.69 | PASS |

Suite durations come directly from the runner report. Offline/syntax/orchestration
is the full elapsed time minus simulator suite durations; parallel offline module
times cannot simply be added to obtain wall time. The serialized layout modules
accounted for 575.457 s. Long individual offline modules included layout wizard
115.158 s, Workshop history 108.957 s, layout publish 92.330 s and layout hardening
66.133 s. These are module durations, not individual assertion timings.

### Phase attribution from existing traces

| Category | Seconds | Share of full time | What is actually measured |
|---|---:|---:|---|
| Offline/syntax/orchestration | 897.025 | 13.2% | Runner total less simulator suites |
| Native bootstrap | 1,967.120 | 29.0% | Existing monotonic `Startup end post-event workarounds` timestamps, all 191 launches |
| Post-bootstrap to first post-check render diagnostic | 2,780.124 | 40.9% | 176 launches with a post-check render diagnostic; includes fixture initialization, assertion evaluation, manual-clock frame work and any unlogged initial render setup |
| After that render diagnostic through final artifact write | 382.141 | 5.6% | 176 launches with that diagnostic; rendering, PNG encoding, final ticks and process tail together |
| Other post-bootstrap native work | 109.325 | 1.6% | Remaining intervals in the 15 launches without that diagnostic, including smoke |
| Outside native artifact intervals | 654.360 | 9.6% | Staging, fixture generation, verdict/image decoding and orchestration together |

These phase numbers are **attribution proxies**, not a new profiler. Native wall
intervals use output-file birth through last artifact write, so process launch/exit
and buffering introduce small uncertainty. Bootstrap timestamps have millisecond
precision. The first timestamped `TexMgr` diagnostic after the final structured
check is a rendering boundary proxy, not an exact GPU-start marker. Do not call
the entire preceding interval pure assertion time or the tail pure GPU time.
Bootstrap median was 9.996 s (range 7.677–16.989 s; p90 12.312 s).

Workshop alone accounts for 1,878.73 s of the combined pre-render interval, versus
392.60 s of bootstrap and 90.70 s of the render tail. This is evidence that
optimizing screenshot rendering alone will not remove its principal cost.
Existing emitted `prepare` records total only 20.174 s across the run; they cover
reported preparation work, not complete rendering or PNG encoding.

A read-only external `ps` observer sampled the final 3,005.831 s at five-second
intervals, beginning late in Workshop. Of 116 observed native simulator processes,
median accumulated CPU/wall ratio was 1.00 (range 0.93–1.08, quantized to seconds).
Observed long verdict processes were also CPU-bound: Workshop verdict had reached
83 CPU seconds after 83 elapsed seconds; Test Lab verdict 20/20. Many Settings
checks use short inline Python verdict processes and were also observed. This is
partial-run sampling, not complete process CPU accounting. The parent runner
mostly waits for children; that does not make the children's work idle waiting.

### What this run cannot time separately

Fixture initialization and individual assertion evaluation have no separate wall
markers. `SIMLAB step-time` is explicitly **simulated** time, and the manual clock
runs frame work without sleeping that many wall seconds. It cannot be used as a
wall-time profile. Assertions' `actual` expressions may do expensive production
work before `Lab.Check` receives them; timing the comparison helper alone would
miss that work. The 30,221 markers therefore establish coverage, not an assertion
cost distribution. No individual assertion is identified as slow without data.

There were no test/simulator timeouts in this full run. `timeout 120/280` values
are caps, not mandatory waits; the nonblocking simulator lock is not an idle
queue. Some bounded settling is required to exercise fades and timers. Measured
CPU activity does not support indiscriminately shortening those windows.

## Specific safe optimizations to consider

1. **Use the existing workflow before changing infrastructure.** Fast checks in
   this task took AH 13.249 s, Market 144.848 s and Advisor 1.980 s. The affected
   AH feature suite took 1,252.412 s with 63 offline modules and 38 launches,
   versus the explicit full run's 6,790.094 s. These different scopes are not
   equivalent coverage. Keep the full gate at its stated triggers; do not add
   extra full runs for each ordinary edit or evidence-only commit. Existing
   Workshop feature selections already support relevant poses plus controls.
   AH preview currently runs its whole catalog; do not invent a narrower CLI.
2. **Avoid resource contention near existing caps.** Concurrent mutation and
   feature work produced five 120 s history timeouts. With the simulator stopped,
   the same five mutations were killed serially in 88.5–103.0 s under unchanged
   caps. Schedule heavy mutation campaigns separately; retain timeout failures
   and retry only affected cases when diagnosing contention. Do not widen the
   limits or count timeouts as detections.
3. **Add opt-in wall-time phase profiling in a future infrastructure change.**
   Measure native bootstrap, fixture data construction, expensive assertion-value
   computation, frame advancement, rendering, PNG encoding and Python verdicts
   separately using a validated real monotonic clock. Keep all checks enabled
   and compare outputs/negative controls. Report per-step and selected expensive
   assertion expressions; do not substitute virtual `GetTime`/`step-time` values.
   Use a few affected scenarios for profiling rather than another full run.
4. **Profile fixture hot paths before attempting reuse.** Workshop's combined
   fixture/assertion/frame work is the largest identified cost. Cache only
   demonstrably immutable input generation, if profiling justifies it, with exact
   input equality checks and fresh per-launch state. Do not cache production
   results or reuse global addon state. The current 3-of-37 replay failure proves
   that dropping repeated common assertions would conceal real nondeterminism.
5. **Optimize the test-only PNG decoder only with equivalence evidence.** The
   native-interval remainder is 10.91 minutes and includes CPU-bound verdict work,
   staging and other overhead. It is an upper bound, not all decoder time.
   `read_rgba` uses Python scanline loops. A separately reviewed faster decoder
   or loop implementation must produce identical dimensions/RGBA and retain
   corrupt-input controls, every image, colour/hit-region assertion and negative
   control. Current major verdicts already decode each image once; memoization
   is not an assumed new saving. Do not skip screenshots because Cloud lacks
   game assets: structural assertions still matter.
6. **Defer process reuse and simulator parallelism.** Bootstrap offers potential
   savings, but shared fixture/root/cache/WTF state and CPU limits make naive
   concurrency unsafe. Any future change needs independent lab roots and locks,
   resource measurements, cold/warm parity, replay equality and failure controls.
   Preserve the supported serial path and full catalog. Existing cached Blizzard
   UI, staged-once roots and serial large-layout execution are already in use.

No option above is implemented here. The next smallest infrastructure proposal is
phase profiling on a selected scenario, followed by the measured hot-path change
with identical assertions and rejection controls. The subsequently authorized
[focused guild-bank repair](workshop/auction-house/integration-verification.md#focused-final-repair--guild-bank-boundary)
now establishes and corrects the fixture assumption. The historical full result
remains FAIL and the repaired source remains pending full rerun; neither this
proposal nor focused success turns that run into a pass.

## Evidence

Raw report: `/workspace/TwichUI-integration-full/test-output/verification/full-all-3ewgjnjt/report.json`.
Full console log and exit: `/workspace/twichui-env/reconcile-full.{log,exit}`.
Timing analysis, per-launch measurements, methods and CPU samples:
`/workspace/twichui-env/reconcile-timing-analysis.json` and
`/workspace/twichui-env/reconcile-process-samples.jsonl`. A compact checksum record
is in [integration evidence](workshop/auction-house/integration-evidence.json).
All captured screenshots and scenario stdout/stderr remain in that frozen
checkout's `test-output/simlab/artifacts/`. Tested source drift is empty.
