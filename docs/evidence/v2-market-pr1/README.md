# PR1 Market pricing evidence

[Implementation, commands, tables and limitations](../../performance/v2-market-pending-pricing-pr1.md).
[Original audit PR #97](https://github.com/Twich-Team/TwichUI/pull/97).

Baseline runtime: `725519e6be87f3e3b9c75d8f7ad271572cb60a1f`.
Implementation runtime: `01ccc197683be1751a37a9c210bd1eed870aaafe`.
No runtime source changed during the timing campaigns. The final evidence commit
adds documentation/JSON only. All data are synthetic; no production database,
service, companion publication, personal records or live SavedVariables were used.

| File | Contents |
|---|---|
| [baseline-2day.json](baseline-2day.json) | Unchanged main, Session 100/1,000 recipes, two history days |
| [baseline-60day.json](baseline-60day.json) | Unchanged main, Session 100/1,000 recipes, 60 history days |
| [baseline-ui.json](baseline-ui.json) | Unchanged main, full Window/View path, 1,000 recipes, two days |
| [implementation-2day.json](implementation-2day.json) | Same Session cases plus full UI 1,000 recipes |
| [implementation-60day.json](implementation-60day.json) | Same 60-day Session cases |
| [verified-inputs.json](verified-inputs.json) | SHA-256 of runtime, regression, fixture and selection inputs verified before commit |
| [verification.json](verification.json) | Compact selected runner reports, mutation totals, diagnostics and simulator results; failures remain failures |
| [simulator-baseline-comparison.json](simulator-baseline-comparison.json) | Exact 40 failed tooltip assertion lines, identical between baseline and implementation Opportunities launches; raw log hashes |

Benchmark JSON retains every sample and min/median/max, clock/runtime identity,
harness hashes, CPU, virtual timers, GC observations, retained/sampled-peak heap,
counts, first/ten/final results and warm reuse. Each case discards one warm-up and
then records three fresh processes. The two-day UI case includes selected-row
Facts/history activity; report its decode range rather than assuming only pricing
requests. The unchanged audit harness is the timing source, not the unit-test's
modeled one-millisecond reader clock.

The feature/local report is **FAIL** because no game assets are installed; all 63
offline modules pass. Separate cloud selected Auction House scenarios **PASS**.
Cloud Workshop verdict **FAILS** with tooltip assertions also reproduced on main
and classified simulator limitations. This is neither a full/local milestone nor
real-client acceptance. No visual or native-client correctness claim follows from
captured mock-frame or no-assets screenshots.

The runner source commit predates the corrective commit and records a dirty,
unchanged input fingerprint; `verified-inputs.json` binds its tested executable
bytes to the corrective commit. Documentation/evidence changes do not invalidate
those runtime checks. Raw ignored run directories remain local; selected exact
failure lines and compact provenance are retained here, not dependent on expiring
CI artifacts.

Keep these baselines immutable. For future changes rerun the same selectors on
both revisions with matching fixtures/harness/host/runtime, review sample ranges
and operation counts first, and commit a separately identified comparison. Update
a baseline intentionally in a reviewed PR explaining the behavioral/fixture change;
do not relax deterministic gates or copy a fast result over a failed campaign.
The normal development group stays six small modules; dedicated timing/stress
workloads remain opt-in.
