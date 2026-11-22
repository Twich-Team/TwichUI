# TwichUI V2: incremental Opportunities performance (PR3)

PR3 replaces repeated complete economic calculations with retained recipe estimates, item dependency invalidation and cooperative work slices. It preserves pricing policy, Market contracts and shared consumers. The implementation is in [PR #102](https://github.com/Twich-Team/TwichUI/pull/102), following #99/#100; Market #43/#44 provide the separately negotiated compact current-price path. The owner subsequently authorized verified source integration into main. No deployment, release, signing, production data change or Contract-3 activation is part of this session.

## Results

For the final 1,000-recipe/60-day/contract-3 UI cohort, workload CPU falls **5,349.83 → 1,009.57 ms (81.1% less)**. Craft calls fall from **54,000 to 1,000**; a compatible warm read performs zero Craft/reader work. These are offline Lua 5.1 measurements, not Forever frame timings. Callback tails and first-use construction remain explicit below.

| 1,000 recipes / contract 3 / 60 days | PR2 | Final PR3 |
| --- | --- | --- |
| Workload CPU (ms) | 5,349.83 | 1,009.57 |
| Craft calls | 54,000.00 | 1,000.00 |
| Full passes / catalog builds | 54.00 | 1.00 |
| Production reader calls | 2,128.00 | 1,128.00 |
| Warm Session CPU (ms) | 36.38 | 0.08 |
| Warm Craft calls | 1,000.00 | 0.00 |
| Scheduled callback p95 (ms) | 72.51 | 2.09 |
| Scheduled callback p99 (ms) | 125.46 | 2.15 |
| Worst callback per run, median (ms) | 166.04 | 8.35 |
| Initial request CPU (ms) | 389.73 | 37.34 |
| Session view requests | 54.00 | 97.00 |
| Retained heap (MiB) | 45.60 | 38.71 |
| Sampled peak heap (MiB) | 110.69 | 59.24 |

“Full passes / catalog builds” is 54 synchronous full economic passes versus one incremental catalog build; PR3 performs zero synchronous `Op.Rows` calls in this path. Total CPU includes initial UI construction, queued work/optional chart draining and one compatible warm Session read; fixture construction, initial manifest admission and the full-recomputation oracle are outside workload CPU/heap timing. View requests can increase because price notifications and prepared-result notifications are independently coalesced. This is not a claim of fewer redraws: each draw reuses economic work, pooled cells and selected details.

The final timing-accounting revision `8a36c29` was rechecked with the same headline fixture/helper and unchanged economic-result hash: median **1,044.23 ms** (941.74–1,080.54), **80.5% below PR2**, 1,000 Craft calls, 1,128 reader calls and zero warm Craft/reader work. Callback p95/p99 medians are 2.077/2.132 ms; the worst callback across those three runs is 14.064 ms, while the largest inclusive worker batch is 2.885 ms. Initial request remains 31.931–60.922 ms. The large matrix below records `5ca9734`; this separately labeled [final-accounting recheck](../evidence/v2-market-pr3/accounting-headline.json) avoids presenting earlier timing semantics as final code.

## Cause and implementation

One diagnostic PR2 profile (production `8b5865b`, profiling helper `6e1a89f`) measured 5,562 ms total, 4,520 ms in Craft, 4,578 ms in Rows inclusive of Craft, 231 ms sorting and 1.6 ms chart access. It recorded 54,000 Craft entries, 54 complete lists and 50 estimators. Overlapping timings must not be summed. [Raw profile](../evidence/v2-market-pr3/profile-pr2.json).

`Session.Estimator` included partial pricing revision in its context key. Partition completions therefore discarded shared question memoization and caused `Op.Rows`/sort/render over the whole catalog. Existing virtualized rows were already pooled. The remaining primary bottleneck was repeated economic calculation and allocation, rather than creating thousands of UI frames.

| Owner | Final behavior |
| --- | --- |
| `OpportunityEngine.lua`, `Request/Build/Calculate/Present` | One result/catalog, immutable economic-input snapshots, item→recipe edges, tokenized coroutine, FIFO/viewport priority, final cooperative merge sort. |
| `Estimate.lua`, `Ask/InvalidateItem/ClearMemo/Work` | Existing memo, per-item answer versions; loading/combat answers never cached; yields after synchronous questions/materials, outside Lua 5.1 `pcall`. No formula change. |
| `Pricing.lua`, `ContextGeneration/PrepareBucket/finishBucket` | Public generation/revision semantics preserved; context excludes partial completion. Complete bucket demand is reserved before decoder handoff; cancellation releases only that unfinished lease. Shared decoding continues. |
| `Session.lua`, `Estimator/ItemsChanged/Opportunities/PlanKey` | Compatible catalog/index reuse, targeted dependency invalidation, correct fee/vendor/source keys, fail-closed obsolete work. |
| `ViewOpportunities.lua` / `Style.lua` / `Window.lua` | Existing row pool retained; unchanged money/detail/chart work skipped; viewport priority and anchoring; page cancellation and combat resume. First-use row construction has an opt-in scope. |

The worker targets **2 ms elapsed processing** with a **1,024-resume cap** (32 without a usable CPU clock). It yields inside expensive recipes, between questions/materials, dependency updates and sorting. One indivisible service/VM operation may overrun; ordinary engine slices and aggregate callback tails are different measurements. There is one scheduled worker and one coalesced presentation callback, with no idle/pending polling chain. Old token/source callbacks cannot publish into a new context.

Profiling the 5,000-recipe workload exposed another avoidable cost: copying/filtering all rows every 128 results. Final PR3 reuses provisional membership/positions while the catalog and metadata-only filters stay unchanged. Price/profit/confidence-dependent membership still rebuilds correctly. No extra price cache or generic reactive framework was introduced.

| Input change | Invalidation |
| --- | --- |
| Partial price / terminal missing / item metadata / vendor price | Only dependent recipes; invalidate their shared item questions. |
| Generation, failure/readiness, account/faction/source, local scan sequence/completion | New complete context; old profits suppressed immediately. |
| Cut, duration or economic fee evidence | New context; equal-count changed postings are detected, unrelated Ledger activity with identical fee evidence preserves results. |
| Recipe observation | Reconcile copied input values; preserve estimates of unchanged recipes. |
| Time | Existing hourly window plus exact local stale/fair-age boundaries; cooldown rows refresh on requested seconds. No permanent ticker. |
| Sort/filter | Reuse estimates; recompute only presentation/ranking as needed. |
| Hide/page switch | Cancel owned callbacks; preserve compatible completed results. Suspension clears engine transients. |

Partial ordering is explicitly **provisional**. Previously ranked/catalog order stays stable while visible work is prioritized; completed global ranking uses the original profit/cost/sell/margin comparator and filters. Selected details, queue validation, missing-price explanations and chart/history semantics are preserved. A worker error fails closed once for that context; explicit reopen/new context can recover. Catalogs over 10,000 recipes refuse rather than running an unbounded job.

## Comparable matrix

All CPU values below are milliseconds: PR2 → final PR3, actual Session path, three fresh measured processes after one discarded warm-up per case.

| Recipes | Contract 2 / 2 days | Contract 2 / 60 days | Contract 3 / 2 days | Contract 3 / 60 days |
| --- | --- | --- | --- | --- |
| 20 | 373.34 → 315.69 | 2,663.16 → 2,564.72 | 258.20 → 231.28 | 273.17 → 237.73 |
| 100 | 1,171.75 → 660.52 | 5,593.41 → 4,976.46 | 741.47 → 470.07 | 771.62 → 486.61 |
| 500 | 3,193.71 → 777.42 | 7,876.38 → 5,119.91 | 1,868.97 → 602.39 | 1,877.92 → 615.44 |
| 1000 | 6,197.36 → 947.10 | 10,716.25 → 5,351.37 | 4,973.24 → 748.86 | 4,903.30 → 765.35 |

Contract 2 still validates coupled historical payloads. PR3 reduces repeated calculation but cannot remove that legacy data cost. The server's additive Contract 3, compatible Companion and installed addon declaration are all needed for independent current-price loading. Existing installations are not silently upgraded by a main merge.

## Progressive timing and lifecycle

The timer model advances by at least one synthetic 60 Hz frame per `After`; it does **not** advance virtual time by callback CPU or reproduce the WoW scheduler. The following modeled seconds are not predictions of native latency.

| Modeled seconds | PR2 | Final PR3 |
| --- | --- | --- |
| First priced known recipe | 0.20 | 0.35 |
| First ten priced known recipes | 0.20 | 1.25 |
| Fixed initial visible cohort settled | 6.52 | 1.57 |
| All known opportunity results settled | 6.52 | 6.80 |

First-ten and final modeled settlement need not improve merely because CPU falls. Report them separately: eager synchronous recalculation can appear earlier on a virtual clock which excludes its expensive CPU. The initial visible cohort may contain different recipes because PR3 honestly uses provisional order and prioritizes that viewport. Neither metric is a native frame/response guarantee.

| Lifecycle input | CPU ms PR2 → PR3 | PR2 Craft | PR3 Craft | PR3 sorts |
| --- | --- | --- | --- | --- |
| single | 119.77 → 24.42 | 2000 | 31 | 1 |
| burst | 118.87 → 93.37 | 2000 | 1000 | 1 |
| reopen | 649.09 → 98.21 | 12000 | 0 | 0 |
| filters | 5,143.46 → 27.66 | 105000 | 0 | 0 |
| generation | 14,744.39 → 3,191.87 | 139000 | 3000 | 3 |
| scroll (real hooks) | 61.25 → 18.31 | 1000 | 0 | 0 |

The single item has exactly 31 dependent recipes. The burst affects all 1,000. Reopen means five cycles. Filters means 100 queued criterion changes before timer dispatch (latest-work coalescing, not a human click-rate claim). Generation means three complete replacements. Corrected scroll dispatches the stand-in's real main script **and HookScript callbacks**, during cold work and after settlement; the initial offset-only timing is superseded and not used. Full estimates, summaries and final order match fresh recomputation in every retained pair.

## Frame-time outliers and limits

All run distributions, maxima and origins remain in the evidence; medians are not maximum guarantees. Initial window construction is outside scheduled-callback percentiles and remains a separate first-open cost. Diagnostic probes identify first-use viewport growth from zero to eight pooled rows (about 3 MiB in Lua stand-in frames). Actual native UI objects differ.

An earlier checkpoint recorded a 35.404 ms worker callback (35.311 ms batch) during a burst. Six controlled probes did not reproduce that spike; stopping automatic GC did not eliminate a 10.846 ms UI redraw. Thus GC is **not established as its cause**. The original observation is retained in [intermediate evidence](../evidence/v2-market-pr3/intermediate-checkpoint.json), with the reproducible [diagnostic patch/results](../evidence/v2-market-pr3/gc-initial.json). Final probes record per-question maximums, pool/heap transitions and inclusive view/strategy/chart phases. Never disable or tune global GC in runtime to hide a result. Remaining native tails require the existing opt-in capture, especially `workshop.opportunityBatch`, `.opportunityQuestion`, `.opportunityRow` and `.render`.

Final calculation-source samples also contain 19.460 ms (worker callback), 15.070 ms (publication), 17.526 ms (pricing notification), 12.306 ms (scroll/pricing), and 18.658 ms (stress publication) tails. The 19.460 ms callback had only 3.103 ms inside the former worker scope: source validation and callback overhead were excluded. The final accounting correction (`8a36c29`) starts the elapsed budget before validation and adds whole-callback/source scopes; it changes scheduling accounting, not economic policy. Its focused tests include a 6 ms source guard and ensure scopes never span callbacks. [Tail inventory](../evidence/v2-market-pr3/callback-tails.json). These are unresolved frame-time limits, not hidden behind percentile averages.

## Extended workload and memory

The paired 5,000-recipe/96-record-per-bucket/60-day/contract-3 stress workload has 6,144 synthetic Market records, shared materials, terminal missing variants, 20 material-price bursts, 100 criterion toggles, five reopens and 20 actual scroll-hook dispatches. It uses one discarded warm-up and **one measured process per revision**: a bounded stress diagnostic, not a statistical timing baseline. Explicit offline collections at checkpoints are included in its CPU and separately counted; runtime does not force collection.

| Stress observation | PR2 | Final PR3 |
| --- | --- | --- |
| Total CPU (ms) | 97,017.62 | 19,481.85 |
| Changed-work CPU (ms) | 61,378.54 | 15,883.51 |
| Total Craft calls | 905,000.00 | 105,000.00 |
| Changed-work Craft calls | 560,000.00 | 100,000.00 |
| Worst callback (ms) | 831.04 | 18.66 |
| Callback p99 (ms) | 520.34 | 2.48 |
| Retained heap (MiB) | 153.49 | 79.78 |
| Sampled peak heap (MiB) | 403.68 | 205.91 |

A separate single-process 60-cycle probe records cache counts alongside retained heap; it is not used for a timing-improvement claim.

| Cycle | Retained MiB | Memo answers | Price entries | Rows retained | Pending prices |
| --- | --- | --- | --- | --- | --- |
| 1 | 73.98 | 4975 | 5064 | 5000 | 0 |
| 10 | 77.37 | 11423 | 5064 | 5000 | 0 |
| 20 | 79.90 | 16281 | 5064 | 5000 | 0 |
| 30 | 79.48 | 14713 | 5064 | 5000 | 0 |
| 40 | 81.86 | 17702 | 5064 | 5000 | 0 |
| 50 | 83.00 | 19895 | 5064 | 5000 | 0 |
| 60 | 82.85 | 19060 | 5064 | 5000 | 0 |

The memo warms toward its existing 20,000-answer cap, drops at cycles 30/60, and row/price/pending counts remain bounded. This finite probe does not prove absence of a native leak or a perfectly flat heap.

Heap deltas start after fixture/header setup. They include harness observers and Lua UI stand-ins, exclude preconstructed fixture storage, and sample peaks only at callbacks/lookups. Raw strings can be interned with the fixture. They are not WoW per-addon memory or an exact allocation peak. The result store owns one catalog (≤10,000 rows) plus dependency edges/snapshots; Pricing retains its existing 8,192-entry bound. Estimate clears questions at 20,000 before the next recipe, with bounded single-craft overshoot. Temporary reconciliation/sorting and a parked history decoder can retain additional state. No all-64 decoded cache, imported-history cache or new SavedVariables was added.

## Verification and regression tiers

Final focused development: **10/10 modules**, **4.426 s**. Targeted mutations: **18/18 killed**, **11.0 s**. A repeated affected integration run passes **76/76 offline modules** and all six selected Auction preview scenarios. The overall strict integration verdict remains **FAIL**: each normal Workshop pose retains the exact 40 pre-existing tooltip assertions, and the intentional wrong pose has 41. Voice/UTF-8 simulator boundaries remain explicit. No assertion was suppressed and the 45-second scenario limit was not raised. [Exact comparison](../evidence/v2-market-pr3/simulator-comparison.json), [verification](../evidence/v2-market-pr3/verification.json), [mutations](../evidence/v2-market-pr3/mutations.json).

Deterministic tests cover full-recomputation field/order/summary equivalence, shared material/quantity reuse, targeted dependencies, metadata-only provisional reuse and dynamic price-filter membership, mutable recipes, partial completion/missing prices, context/generation/fallback/fees/vendor/cooldown changes, cancellation, stale timer/source suppression, combat retry, corruption/last-good rollback, error/no-retry and memory capacity. Real UI tests cover selection/details, pooled rows, actual scroll hooks and shared-consumer lease release. No runtime economic formula changed.



| Tier | Command / selection | Budget and cadence |
| --- | --- | --- |
| Development | `./tests/run.sh development market-performance --jobs 2` | Under 30 s target, 60 s review ceiling; relevant commits and PRs. Ten deterministic modules, no simulator or benchmark. Existing PR workflow selects it. |
| Benchmarks | `python tools/measure_market_opportunities.py ...` | Opt-in for performance-sensitive PRs; one warm-up then three fresh processes per case. Never ordinary test discovery. |
| Integration | `./tests/run.sh integration market --with-group crafting --with-group market-performance --profile cloud --jobs 2` | Cross-subsystem checkpoints; actual reader, fallback/corruption/rollback/generation, crafting/AH consumers and selected UI simulator launches. Does not certify a native client or release. |
| Stress | Existing driver `--stress --case opportunities/ui/5000 --rows 96 --scenario stress` | Scheduled/release preparation or explicit performance work; not every commit. One warm-up and at least three measured samples when establishing a timing baseline; a one-sample bounded diagnostic is labeled separately. |

Keep deterministic correctness/operation invariants as merge gates: unchanged reads perform zero Craft/reader/full-list work, a price update touches exactly its dependency set, terminal missing prices settle, shared questions are reused, stale jobs cannot publish, capacity limits release work, and waits have no polling loop. Tests compare every completed economic field, summary and ordering against full recomputation. The benchmark oracle is outside workload CPU/heap timing and excludes only private estimator links and lazily computed typical-profit decoration; the deterministic engine test covers complete estimate fields.

Store source revision, harness SHA, semantic fixture SHA, host/Lua versions, individual samples, medians and ranges under `docs/evidence/`. Compare only matching fixtures and harnesses on the same host; investigate outliers and callbacks over 10 ms, including origin and indivisible service-call scopes. Do not silently overwrite a baseline or raise budgets: intentional changes require reviewed rationale, fresh comparable samples and unchanged correctness checks. Keep failing evidence and link it in the PR. Select Market/pricing/engine tests for reader changes, crafting plus Market dependencies for Estimate/Session/Vendor changes, and selected Workshop/AH consumer UI coverage for shared list/Window/diagnostic changes. Full/release and large historical/mutation campaigns remain separate.


## Reproduction and provenance

PR2 production: `8b5865b20cec7d7f39af78de947b712a9c7c67e1`. Calculation matrix production: `5ca9734` (full SHA in each candidate report). Main 20/100/500/1000 and five lifecycle comparisons use identical helper files from `6754427`; headline/corrected-scroll/paired-20-cycle stress use helpers from `c8bd885`; extended memory/final diagnostics use helpers from `5ca9734`. Only those two isolated helper files are replaced in detached measurement worktrees; baseline production remains unchanged. The main/harness source and semantic fixture/result hashes are retained per report. An earlier c8bd885 checkpoint is retained as intermediate, not presented as the final implementation.

Host: Linux 6.18.57 x86_64, AMD EPYC 9V74, five visible vCPUs, Lua 5.1.5/bitop, Python 3.12.14. No CPU pinning; no other heavy local verification campaign overlapped measurements. Synthetic Market/recipe data only, no production database/network. Each statistical case has one discarded warm-up, three fresh processes, medians/min/max and individual samples. The oracle runs after workload CPU/heap collection, comparing every economic field except private estimator links and lazy typical-profit decoration; deterministic engine tests cover full estimate fields. The same fixture/harness SHA and economic result SHA must match before/after. Do not compare different helper revisions as though identical.

Create detached worktrees at the two production revisions. Copy the listed helper revision's `tests/bench_market_opportunities.lua` and `tools/measure_market_opportunities.py` into **both** before running the same commands from each root:

```sh
# Statistical matrix: repeat for contract 2/3 and days 2/60.
python tools/measure_market_opportunities.py --suite opportunities --contract 3 --days 60 --reps 3 \
  --case opportunities/session/20 --case opportunities/session/100 --case opportunities/session/500 \
  --case opportunities/session/1000 --case opportunities/ui/1000 --report report.json
# Repeat separately for single, burst, reopen, filters, generation (6754427 helpers).
python tools/measure_market_opportunities.py --suite opportunities --contract 3 --days 60 --reps 3 \
  --scenario single --case opportunities/ui/1000 --report single.json
# Corrected real scroll (c8bd885 helpers).
python tools/measure_market_opportunities.py --suite opportunities --contract 3 --days 60 --reps 3 \
  --scenario scroll --case opportunities/ui/1000 --report scroll.json
# Paired bounded stress (c8bd885 helpers); one sample explicitly labeled.
python tools/measure_market_opportunities.py --suite opportunities --contract 3 --days 60 --reps 1 \
  --stress --rows 96 --scenario stress --case opportunities/ui/5000 --report stress.json
# Extended single-process memory and optional controlled diagnostics (5ca9734 helpers).
lua5.1 tests/bench_market_opportunities.lua opportunities ui 5000 60 3 96 normal stress off 60
lua5.1 tests/bench_market_opportunities.lua opportunities ui 1000 60 3 32 profile burst normal
lua5.1 tests/bench_market_opportunities.lua opportunities ui 1000 60 3 32 profile burst nogc
./tests/run.sh development market-performance --profile cloud --jobs 2
./tests/run.sh integration market --with-group crafting --with-group market-performance --profile cloud --jobs 2
bash tools/mutate.sh --group market.opportunity --group market.pending --group market.current --jobs 2
```

`nogc` is an isolated CLI diagnostic only. Benchmark wall-process time includes fixture/oracle/VM setup and is not the addon CPU metric. Routine checks do not select these workloads, the full simulator or mutation campaigns. Intentional baseline updates need a reviewed rationale, exact source/harness/fixture identity, fresh comparable samples and unchanged operation/correctness gates; never raise elapsed budgets or silently replace failing evidence.

## Native Forever check

On a review build with the intended PR1/PR2 dependencies, use synthetic/test-safe data or the owner's existing companion delivery. No synchronization or publication is performed by PR3. Record client build, recipe count, contract, observation age and diagnostic clock/profile mode; keep those conditions constant when comparing revisions. Do not enable script profiling automatically.

1. Before opening Workshop, run `/tui perf start workshop 3`, then `/tui perf mark opportunities-open`. Open Workshop → Opportunities and avoid filters/scrolling until its initial visible cohort and all known rows settle. Mark `/tui perf mark opportunities-settled`.
2. Close/reopen the page with unchanged inputs; mark `/tui perf mark opportunities-warm`. Confirm immediate valid rows with zero new Craft/reader work, no full invalidation or sort, and no pending/running engine after settlement.
3. In a separate capture, change sort/profession/confidence filters, scroll during a cold calculation, change pages while it is busy, reopen, and inspect a selected recipe/add-to-queue confirmation. Perform no purchase/post/sell action. Test a new local scan or companion generation only through the normal owner-controlled process.
4. `/tui perf stop`; open Diagnostics and export Quick summary plus JSON through the existing UI. Reports contain bounded aggregate timings/counters, no item identifiers or Market payloads.

Read `workshop.opportunityCallback` whole-callback CPU, `workshop.opportunitySource` validation and `workshop.opportunityBatch` total/worst CPU and `workshop.opportunityQuestion` indivisible service calls alongside `workshop.render`, Summary validation/load/completion CPU and elapsed wait distributions. The existing first/ten priced opportunities, fixed initial visible cohort, all-row settlement, partition load/repeat counters, pricing cache/pending gauges and five new recipe-state gauges distinguish calculation from queue waiting. `cacheHits` counts compatible catalog reads; `reused` counts recipe estimates preserved during catalog reconciliation; neither is a universal per-price hit rate. Final/provisional publication counters count prepared list publications; row/detail counters show actual visible presentation work.

Native goals: unchanged draws do zero economic work; isolated updates match dependency fanout; ordinary engine slices target 2–3 ms; investigate every callback over 10 ms. The elapsed budget can overrun by one synchronous service call, timer queues and GC affect client frame times, and first-open UI construction is separate from scheduled callbacks. Verify actual frame-time p95/p99, gameplay responsiveness, first/visible/all completion, memory after repeated lifecycle operations, and correctness of the final ranking. Offline virtual seconds are not predicted Forever latency.


## Integration and remaining work

The user authorized verified main integration after PR3 completion: addon #99 → #100 → #102, preserving the historical audit #97 without overwriting evolved infrastructure; Market #43 → #44. Ledger #98 is excluded. Current main's concurrent class-portrait/roadmap changes must be preserved. Final main source and coordinated Windows publication/production-Lua checks are reported in the integration handoff. No merge itself deploys the server or publishes a client/addon release.

Rollback of PR3 requires reverting its source changes, with no SavedVariables migration; shared pricing/contracts remain independently versioned. A rollback before Contract-3 support must first select a complete compatible generation using the compatible Companion, never splice bank files.

Native Forever CPU/frame/GC tails, real load-on-demand disk compilation, physical-PC NTFS/UAC/tray behavior and actual production contract negotiation remain unverified here. The source still advertises Companion beta.10, already released; a future separately authorized release must use a distinct approved version and exact Windows artifact/signature/owner gates, not republish different bytes as beta.10. The future deployment prompt must preserve the actual production Compose chain, collector/history/retention/backups, existing signing identity and prior releases.

No PR4 implementation is started. Native evidence should decide whether remaining work is first-use pool/window construction, common notification coalescing, indivisible services or VM/GC tails. The default-view quadratic presentation copy has already been removed in PR3; there is no evidence justifying another permanent price/history cache or a new Market format at this stage.
