# Market pending pricing remediation PR1

Implementation of [audit PR #97](https://github.com/Twich-Team/TwichUI/pull/97),
reference commit `28f5db452b60719ec3ce8e327081caaf7fb64537`.

PR1 removes repeated unresolved-price hashing and reader work while keeping the
existing compact cache and single decoder. On 1,000 recipes/two history days,
CPU falls **31.36 → 5.87 seconds (81.3%)**, reader calls **195,270 → 2,128**.
Full-list callbacks and cold history validation remain substantial; real-client
latency is unverified. This is a draft implementation, with no merge or deployment.
Base: current main `725519e6be87f3e3b9c75d8f7ad271572cb60a1f`.
There are no Workshop runtime differences from the audit baseline. This branch
selectively reuses the audit's benchmark scripts and small invariant test; it
contains no Ledger work, Market service/Companion changes or format migration.

## Request and completion ownership

Pricing retains the existing single compact resolved-record cache. A pending
bucket holds an item-to-base-key reservation and a bounded FIFO of requested IDs.
Repeated foreground reads return transient `loading` without another hash or
reader call. The private completion writer explicitly bypasses that guard and
reuses the reserved hash. Positive, terminal-missing and terminal-failed results
enter the existing cache; combat/loading/admission failures are not permanent
missing prices. Positive Facts reuse the record's already-verified variant key.

The combined reservation/resolved limit remains 8,192. FIFO IDs are transient work,
not a second resolved-price cache. They avoid a large synchronous snapshot/sort
when transferring a heavily requested bucket. A rejected batch detaches before it
yields: post-combat retries enter a new queue rather than extending the rejected
cursor. One old rejection FIFO can temporarily coexist with the live queues;
at most two sets of 8,192 ID slots are retained, while outstanding reservations
plus compact answers still share the 8,192 limit. Processed slots hold IDs only.
The cached header also retains its
immutable parsed observation time; freshness and faction admission remain live.
Each price query uses one reader-status snapshot rather than repeatedly copying
status tables in that same call.

Summary retains one decoded partition. After validation it enters an explicit
handoff job before advancing its FIFO. Each transferred record yields. Q.Step
checks its existing elapsed budget (nominal 3 ms, with 1 ms headroom) and also caps
handoff resumes at 16. This is cooperative: one indivisible Record call can exceed
the remaining budget; it cannot be preempted. Current record lookup/history copies
remain PR2 work. Non-yieldable AddOn loading retains its separate existing scope.

Handoff finishes, cancels, or exits on admission/lifecycle change; it never pins
all partitions. Failed/combat addon loads get a yielding rejection handoff, which
settles or releases reservations and allows following buckets to progress. The
format, integrity/canonical validation, raw retention, last-good rollback and
SavedVariables are unchanged.

Research-only partition reads with no pending pricing/chart request skip the
handoff. A retry can queue behind a rejected handoff for the same bucket. The
regression checks that completion writes that retry's result before any later
foreground read, so a test cannot accidentally rescue a lost request.

## Revision and notification contract

The estimator identity uses data generation, failure count, readiness, cancellation
epoch and a **pricing completion revision**, rather than `checked_parts`. This is
not removal of invalidation: a bucket's pending-to-terminal transfer explicitly
advances that revision, including terminal misses and invalid/combat outcomes.
Revisiting a decoded bucket with no pending pricing changes does not advance it.

Cancellation/replacement invalidates old reservations and scheduled completion
notifications. Activation also clears requests made against the old generation
while the replacement header was validating. Failure/rollback clears obsolete
reservations; the existing generation/failure cache stamp invalidates resolved
answers when required. Resolved compatible answers survive ordinary decoder churn.
Stale/faction/local-newer rules remain enforced on every request. Local scan,
fee/vendor/time and recipe invalidation in Session are preserved.

Summary and Pricing use one 0.1-second completion notification coalescer; revision
and cache writes precede downstream notification. A focused chart may promote it
to the next callback to preserve access before another decoder replaces its rows.
P.Changed still refreshes Facts, Strategy, Workshop, Auction House, tooltips and
Junk through the existing downstream hooks. Full-list Opportunities calculations
remain synchronous; this PR does not implement the proposed incremental engine.

## Implementation review points

- `Pricing.lua`: `record` reserves the hash and distinguishes foreground reads
  from completion writes; `finishBucket`, `CancelPending`, `Generation` and
  `Notify` own settlement, revision and cancellation.
- `Summary.lua`: `handoff`, `Q.Step` and `request` preserve decoder availability,
  enforce cooperative time/resume limits and allow retries behind rejection.
  Header activation and failed validation release obsolete reservations.
- `Session.lua`: estimator logic is retained; the full-list diagnostic is the only
  change in that file. Its existing source identity consumes the explicit revision.
- `TwichUI_Diagnostics/Gauges.lua`: fixed operation descriptions; the existing
  capture engine owns counters, retention and export.

## Diagnostics and native check

Use `/tui perf start general 1`, mark the Opportunities open, open the page, mark
completion and stop/export. Existing report counters now include
`workshop.pricing.uniquePending`, `.deduplicated`, `.readerCalls`, `.baseKeys`,
`.settled`, `.notifications`, `.fullLists`, and `workshop.summary.decodeStarts` /
`.decodeRepeats`. `workshop.pricingComplete` reports total/worst handoff-slice CPU;
`workshop.summaryLoad`, `.summaryValidate`, `.estimate` and `.render` remain.
Pending/resolved identities and existing raw/decoder/memo gauges expose retention.

Counters are fixed aggregate IDs in R.Perf's bounded capture engine and are off
by default. No per-item logs, identities, payloads or SavedVariables are added.
Counters reset with captures; unique pending means reservations during a request
lifecycle (a cancellation/new generation may reserve the identity again). A repeat
decode is one whose bucket was already validated in that generation, including
validation before the capture. Scope timings are inclusive; do not sum nested
load/validation/render scopes. Manually record first/visible/all completion times;
these new counters do not pretend to measure row visibility or timer waiting.

## Reproducible benchmark conditions

Baseline production source: `725519e6be87f3e3b9c75d8f7ad271572cb60a1f`.
Implementation production source: `01ccc197683be1751a37a9c210bd1eed870aaafe`.
The evidence/documentation commit changes no executable inputs after this point.
Both run the exact audit harness, SHA-256
`d3f90b67696adf9ce785bff6d9df95d0b7ce9750573221720975241c47efa180`.
Fixture SHA-256:
`f266725c40b7dec92b9058242bdec335216c9aacfac0560660112136ab544495`.
The imported driver and index harness are byte-identical to audit commit
`28f5db452b60719ec3ce8e327081caaf7fb64537`.

Same execution environment: Linux 6.18.57 x86-64, AMD EPYC 9V74 (five visible
logical CPUs), Lua 5.1.5 with bitop, Python 3.12.14/glibc 2.41. No core/frequency
pinning or isolated hardware is claimed. Timing campaigns run sequentially,
without concurrent simulator/mutation/test campaigns. One discarded warm-up and
three fresh Lua processes per case; report medians and retain all samples/ranges.
Clock-dependent redraw counts can vary with validation slice boundaries.

Each fixture has 2,048 records, 32 per bucket across all 64 buckets, shared
materials, differing recipe quantities/outputs and deliberately absent base
variants. Two history days encode 306,292 raw bytes; 60 days encode 2,329,716.
The known recipe count is 100 or 1,000. Expected final priced counts are 100 or
960 respectively (40 deliberately missing outputs in the larger fixture).
The Session path executes production Opportunities estimation; the UI path adds
production Window/View rendering over mock frames.

CPU (`os.clock`) includes the final explicit warm calculation. `warm_ms` separately
measures it; `warm_record_calls` must be zero. Python subprocess elapsed includes
fixture construction/startup and is retained in JSON. Virtual latency assumes
one minimum 60-Hz frame for **every** `C_Timer.After`, excludes callback CPU and
is **not WoW wall time**. Report it separately; do not add it to CPU as a client
latency estimate. Peak heap is a callback/lookup sampled lower bound, not allocator
peak. Retained delta follows a full collection. Already-held raw fixture strings
and header setup are outside that delta; raw-loaded bytes are separately recorded.
Automatic GC is included in CPU; heap drops do not measure GC pause duration.
Validation-stage accounting now excludes handoff whereas the old synchronous first
warming batch was included, so do not compare that stage alone as identical work.

To reproduce, create a detached baseline worktree at the baseline SHA. Copy only
`tests/bench_market_opportunities.lua`, `tests/bench_market_index_memory.lua` and
`tools/measure_market_opportunities.py` from audit commit `28f5db4` into it (or
from this PR, verifying their hashes). Leave baseline runtime files untouched.
Run the following in each checkout with Lua 5.1/bitop available:

```sh
python3 tools/measure_market_opportunities.py --suite opportunities --reps 3 --days 2 \
  --case opportunities/session/100 --case opportunities/session/1000 --report /tmp/market-2day.json
python3 tools/measure_market_opportunities.py --suite opportunities --reps 3 --days 60 \
  --case opportunities/session/100 --case opportunities/session/1000 --report /tmp/market-60day.json
python3 tools/measure_market_opportunities.py --suite opportunities --reps 3 --days 2 \
  --case opportunities/ui/1000 --report /tmp/market-ui.json
```

The implementation's two-day campaign selected the UI case in the same invocation;
each case still has its own discarded warm-up and three fresh processes. No
benchmark is discovered by the normal test runner. Earlier development measurements
and the interrupted pre-correction 60-day campaign are excluded from final comparisons.
The new 8,192-identity fixture separately demonstrates the >16-per-bucket case;
the unchanged audit workloads do not prove that edge by themselves.

## Comparable results

All entries are **before → after**, medians of three samples. Counts and timing
medians are calculated independently; sample ranges and raw runs are retained in
[benchmark evidence](../evidence/v2-market-pr1/README.md).

| Recipes / history / path | Reader calls | Base hashes | Total CPU seconds | CPU saved | Full lists |
|---|---:|---:|---:|---:|---:|
| 100 / 2 days | 20,157 → 328 | 20,157 → 164 | 3.68 → 1.14 | 69.0% | 82 → 63 |
| 1,000 / 2 days | 195,270 → 2,128 | 195,270 → 1,064 | 31.36 → 5.87 | 81.3% | 86 → 66 |
| 100 / 60 days | 33,424 → 328 | 33,424 → 164 | 10.17 → 5.59 | 45.1% | 130 → 66 |
| 1,000 / 60 days | 325,354 → 2,128 | 325,354 → 1,064 | 54.76 → 10.35 | 81.1% | 130 → 66 |
| 1,000 / 2 days / UI | 233,071 → 2,128 | 233,169 → 1,064 | 37.06 → 6.15 | 83.4% | 102 → 68 |

| Workload | Hash CPU ms | Craft calls | High-level Price calls | Worst callback CPU ms |
|---|---:|---:|---:|---:|
| 100 / 2 days | 2060.82 → 16.50 | 8,200 → 6,300 | 19,893 → 22,364 | 86.19 → 17.03 |
| 1,000 / 2 days | 20253.78 → 107.87 | 86,000 → 66,000 | 147,936 → 144,888 | 704.39 → 121.43 |
| 100 / 60 days | 3465.09 → 16.41 | 13,000 → 6,600 | 32,130 → 23,562 | 90.54 → 17.17 |
| 1,000 / 60 days | 33666.90 → 118.42 | 130,000 → 66,000 | 238,802 → 145,071 | 709.74 → 116.81 |
| 1,000 / 2 days / UI | 24184.28 → 107.97 | 102,000 → 68,000 | 177,246 → 151,603 | 695.59 → 150.07 |

| Workload | First result, model s | First ten, model s | Final, model s | Explicit warm CPU ms |
|---|---:|---:|---:|---:|---:|
| 100 / 2 days | 0.30 → 0.33 | 0.85 → 1.02 | 6.17 → 7.43 | 3.65 → 3.04 |
| 1,000 / 2 days | 0.30 → 0.35 | 0.30 → 0.35 | 6.20 → 8.48 | 58.34 → 35.74 |
| 100 / 60 days | 1.93 → 1.92 | 7.47 → 7.43 | 58.18 → 58.72 | 3.00 → 3.15 |
| 1,000 / 60 days | 1.88 → 1.95 | 1.88 → 1.95 | 58.27 → 60.38 | 38.51 → 42.10 |
| 1,000 / 2 days / UI | 0.30 → 0.37 | 0.30 → 0.37 | 6.50 → 8.53 | 37.72 → 37.09 |

| Workload | Retained delta MiB | Sampled peak delta MiB | Explicit final GC ms (outside workload CPU) |
|---|---:|---:|---:|
| 100 / 2 days | 1.26 → 1.25 | 12.99 → 12.25 | 5.96 → 5.26 |
| 1,000 / 2 days | 10.09 → 10.02 | 50.65 → 45.70 | 31.89 → 30.38 |
| 100 / 60 days | 1.53 → 1.52 | 14.83 → 15.32 | 8.60 → 9.72 |
| 1,000 / 60 days | 10.36 → 10.29 | 51.51 → 54.36 | 38.75 → 61.65 |
| 1,000 / 2 days / UI | 40.24 → 40.16 | 117.39 → 114.27 | 73.75 → 105.14 |

All Session samples load/decode 64 partitions with **zero repeated decodes**;
the full UI path is 64–65 decodes / 0–1 repeats in **both** revisions. The UI also
requests selected-row Facts/history (`ViewOpportunities.lua` detail rendering →
`Facts.Chart` → `Pricing.Chart`); the one decoded history reader remains on demand.
This PR does not claim that arbitrary raw/history-reader alternation stops decoding.
All samples retain one active decoded partition and 164/1,064 compact identities.
All warm samples reuse the estimator and perform **zero reader calls**; matching
completion counts are 100/100 and 960/1,000, including the 40 designed missing outputs.
Existing reference/consumer tests, rather than only these completion counts, cover
copper values, quantities, variants, fees, source admission and local fallback.

For 1,000 recipes/two days, **193,142 reader calls** (98.9%) and **194,206 hashes**
(99.5%) disappear; hashing CPU falls 20,253.79 → 107.87 ms. Every candidate sample
meets the target of two reader calls and one hash per compact identity. This is
request/completion work, not merely a repeated warm-item microbenchmark.

Full-list work remains material: 66,000 Craft calls on the large Session path,
68,000 on UI (medians); worst UI callback median **150.07 ms**, maximum **156.80 ms**.
Even warm estimation is about 36–42 ms for 1,000 recipes. High-level Price calls
do not universally fall (the 100-recipe/two-day case increases); cheap pending
answers and compact hits replace hashing/reader work, not all repeated questions.
The explicit completion revision preserves correctness when fallback/missing
questions were already memoized. Full incremental recipe/UI updates remain PR3.

**Virtual latency increases** in several cases: 1,000/two-day Session 6.20 →
8.48 s and UI 6.50 → 8.53 s. Handoff now yields before advancing the reader, so the
minimum-one-frame timer model charges extra callbacks. The model excludes the
large CPU savings and cannot establish improved or regressed WoW wall time.
First/ten model latency is also not uniformly better. Native measurements are
needed before claiming the original item-by-item delay resolved.

**The 60-day cold problem remains.** Initial history validation still costs about
4.9–5.0 CPU seconds after PR1, with roughly 59–60 modeled seconds overall. Raw
synthetic addon compilation is about 10 ms total for 64 loads (execution <0.1 ms);
file compilation is not the multi-second stage on this host. Integrity/history
validation and scheduled progress remain separate from the removed hash amplification.

Retained Session/UI heaps remain close to baseline; no extra decoded-history cache
is introduced. Sampled peak is not uniformly reduced: 1,000/60-day median is
51.51 → 54.36 MiB (+5.5%), with overlapping ranges (before 51.17–56.98; after
42.54–54.36 MiB). Explicit final collection is sometimes slower, as recorded above;
it is not an in-game GC-pause measurement. Different temporary allocation/GC phases
can change sampled peaks despite similar retained state. Counts, capacity/lifecycle
tests and retained measurements support bounded storage; native GC/frame behavior
remains unverified.

## Verification commands

```sh
./tests/run.sh development market-performance --list
./tests/run.sh development market-performance --jobs 1
./tests/run.sh development market --list
./tests/run.sh development market --jobs 2
./tests/run.sh feature market --list
./tests/run.sh feature market --jobs 2
./tests/run.sh development crafting --list
./tests/run.sh development crafting --jobs 2
bash tools/mutate.sh --group market.consumption --group market.pending --jobs 2
```

Direct diagnostics/infrastructure checks use the existing individual-test entry:

```sh
cd tests
lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_perf_engine.lua
lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_diagnostics.lua
python3 test_test_runner.py
```

The additive fast performance group has six modules. It covers shared pending
consumers/redraws, cold/warm prices, all 64 buckets, >16 reservations per bucket,
8,192 slots, modified identities, missing prices, generation replacement mid-work,
requests while a new header validates, corrupt-part rollback, cancellation,
combat retry, stale admission, stable checked-count completion invalidation,
no-op/coalesced notifications, and one-decoder/zero-outstanding bounds. Existing
consumption tests cover local fallback/newer local scans, faction, Facts, Advisor,
UI consumers and economic isolation. Large benchmarks remain opt-in.

### Verification results and exceptions

**Unit-tested:** fast `market-performance` 6/6 modules, **4.107 s**; Market feature
selection **63/63 offline modules**, syntax passed; crafting **11/11**, 10.516 s.
Direct perf-engine and diagnostics modules pass. Runner infrastructure: 17 cases,
5.374 s. Targeted `market.consumption` + `market.pending` mutation campaign:
**12/12 killed**, no survivor/invalid/timeout/infrastructure result, 7.3 s.
The new rejected-retry mutant initially survived a weaker test that read again
before asserting completion. The strengthened oracle checks cache commitment and
no additional reader call; the final campaign kills it.

**Simulator-tested with failures retained:** the default/local Market feature
command fails before launching addon code because this cloud environment has no
game assets. Its offline tests all pass; it is not a passing feature certification.
Only the simulator selections were then rerun using the prepared cloud launcher:

```sh
SIMLAB_ASSETS=0 SIMLAB_ONLY='craft opps history wrong' bash tools/simlab/run.sh workshop
SIMLAB_ASSETS=0 SIMLAB_ONLY='companionvalid companionnewer companionolder summaryvalid summarycorrupt summaryfuture' \
  bash tools/simlab/run.sh auctionpreview
```

All six scoped Auction House scenarios pass. All four Workshop native processes
exit zero, but the strict verdict **fails**: each ordinary launch includes 40
Worth tooltip assertions (missing Workshop advice lines, among others). A separate
`SIMLAB_ONLY=opps` replay on unchanged baseline has **the same 40 failure lines,
identical text**. The deliberate wrong control also fails as expected. Classified
voice-settings and addon-message simulator limitations remain in the logs; no
assertion, exclusion rule or runtime behavior was changed to suppress them.
These results establish no new assertion difference in that baseline comparison,
not a complete passing simulator/local/release gate. No screenshot visual review
or real-client acceptance is claimed. Compact reports, verified executable hashes,
and exact failed assertion comparison are retained in
[verification evidence](../evidence/v2-market-pr1/README.md).

Native client behavior remains unverified. Do not declare the reported 5–10-second
item delay fixed from offline CPU/virtual-timer measurements. No deployment,
publication or merge is authorized. Roll back with an ordinary revert; all caches
and revisions are session-only and no saved-data migration is required.

## Owner-directed WoW Forever check

1. Test the candidate outside combat using the normal install workflow. Note the
   source revision, known recipe count, Market generation/age/history coverage,
   local scan age, other addons and frame rate. Do not replace SavedVariables.
2. For a cold session, reload normally, start `/tui perf start general 3`, then
   `/tui perf mark opportunities-open` immediately before opening Workshop →
   Opportunities. Mark the first priced row, first ten, all visible and final
   completion. Stop with `/tui perf stop`; export the report using Diagnostics.
   Markers are manual observations, not automatically measured row timestamps.
3. Check sampled cost/selling/profit values, fee assumptions and provenance.
   Include absent prices, a modified item variant and local fallback/newer scans.
   Warm close/reopen should use the same compact answers without further reader
   calls for those identities. Preserve the report rather than forcing a GC.
4. During a second capture, switch pages, hide/reopen the window and enter/leave
   combat while prices load. Confirm queued work settles or safely retries,
   pending count returns to zero and Workshop suspension cancels work. Check
   existing Advisor, Facts/tooltips, Strategy and AH preview refreshes normally.
5. Compare first/visible/all completion and frame spikes with a quiet capture and
   the unchanged candidate baseline in the same conditions. Inspect load,
   validation, handoff, full-list estimation/render and repeated decode counts
   separately. A 2-ms cooperative slice plus one indivisible lookup is not a
   whole-frame deadline. Capture the worst full-list callback as well.

Ordinary cold pricing with no intervening invalidation/eviction should use at most
two reader calls and one base hash per retained identity; warm reads should use
zero reader calls. Generation replacement/combat retries are separate request
lifecycles. The 8,192 bound and zero settled pending count are deterministic
acceptance checks. Native latency/frame-time targets need these captures; this
PR does not certify that the original per-item delay is resolved.

## Next decision and rollback

Wait for a real-client profile before automatically authorizing PR2. Full-list
refresh work remains a candidate for the proposed PR3, and cold history validation
remains a separate cost. A current-record projection/index can reduce selected
lookup work, but an index alone does not remove validation of delivered history.
Prioritize the measured client stage; keep any companion/format change separately
reviewed. No further remediation is included or automatically authorized here.

Revert the implementation commits together to restore the former request and
notification protocol; do not revert just one side of the Summary/Pricing handoff.
No schema, raw data format, server/Companion, deployment, SavedVariables or retained
history policy changed. The test/benchmark evidence can remain as characterization;
the new operation-count assertions intentionally fail against the old behavior.
