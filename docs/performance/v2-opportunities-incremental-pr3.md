# Incremental Opportunities PR3

Stacked on unmerged PR2 #100 at `8b5865b20cec7d7f39af78de947b712a9c7c67e1`; PR1 #99 and Market #43/#44 remain dependencies. Market is read-only in this stage. No merge, deployment, release, contract or pricing-policy change.

## Focused baseline and design

One instrumented 1,000-recipe / 60-day / contract-3 UI workload uses the existing production harness and synthetic data. Actual CPU 5,562 ms; Craft accounts for 4,520 ms, Rows 4,578 ms inclusive of Craft, sorting 231 ms, chart reads 1.6 ms. These overlapping scopes must not be added together. 54 full lists / 54,000 Craft entries, 50 estimator instances; a compatible warm redraw still calls Craft 1,000 times and costs 36.8 ms. Worst scheduled callback 171.9 ms. Header admission and fixture construction are outside workload CPU. One diagnostic sample, not a statistical performance baseline; probes add overhead. [Raw phase sample](../evidence/v2-market-pr3/profile-pr2.json).

The partial pricing revision is part of Session.Estimator's context key. Every completion discards shared question memoization, builds all recipe result tables, sorts and refills visible rows. The existing virtualized list already pools frames; it does not need a replacement. Selected charts are not the primary CPU cost in this fixture.

Use one Workshop-specific recipe-result store with item→recipe dependencies. Keep the existing estimator memo, invalidate its affected item answers, and gate calculation until price questions have terminal answers. One tokenized coroutine worker handles invalidation, recipe computation, filtering and cooperative merge sorting under elapsed and operation budgets. Yield between material/questions as well as recipes; record indivisible service calls separately. Prices, formulas, quality and fee rules stay in Estimate/Market.

A changed context invalidates all results; changed prices invalidate dependent recipes only. Result validity must be checked against item/context versions before publication, including while a worker is suspended. Partial results retain stable provisional order, visibly labeled as refreshing; final ordering uses the existing comparator. Filter/sort changes reuse estimates. Visible rows can advance pending work without implying they are the best-profit recipes. Keep one bounded catalog, no historical payload cache, and no background worker when idle.

Context boundaries include actual source/generation, local scan sequence, fee evidence/duration, vendor changes, recipe catalog changes, freshness thresholds and cooldown time. Hiding cancels obsolete workers but retains compatible completed estimates; suspension clears transient engine state. Source changes cannot publish old profits.

## Verified implementation checkpoint

The production TOC now loads `OpportunityEngine.lua` after Estimate. Completed recipe estimates survive compatible redraws; item versions invalidate dependent rows and estimator questions. Cold demand is reserved by partition before its shared decoder handoff, preventing progressive calculation from reintroducing partition churn. Cancellation releases only the unfinished demand lease, leaving shared decoding available to other consumers.

The worker targets 2 ms with an independent 1,024-resume cap (32 without a CPU clock), yielding after estimator service questions/materials, dependency updates and merge-sort steps. An indivisible service call can exceed the target: diagnostics record those calls separately. No CPU scope spans a yield. Provisional order is labeled, final order uses the existing comparator; pooled rows, money formatting and selected details are reused.

The ten-module development group passed in 4.423 seconds (cloud profile; 33 Lua syntax files). The targeted mutation campaign killed all 16 applied defects in 12.8 seconds, including elapsed budget, dependency fanout, mutable recipe snapshots, source/token guards and the preparation lease. The earlier invalid revision mutation was updated to match the refactored completion writer and rerun successfully; no assertions were weakened. Integration, comparable multi-sample benchmarks and native verification are reported below when complete.


Integration follow-up corrected an optional Pricing-module chart read and fee
replacement invalidation (counts can stay equal while deposit amounts change).
Explicit cooldown, same-count vendor/fee, and empty-viewport diagnostic tests now
pass. The latest ten-module fast run took 4.257 s. All 76 affected integration
modules passed; Auction preview's six selected simulator scenarios passed. The
Workshop scenario now waits for real asynchronous settlement without changing its
assertions or raising its 45-second resource limit. Its final comparison is
recorded with the benchmark evidence below.

## Context, memory and lifecycle contract

The result store owns one transient catalog, capped at 10,000 recipes, plus item-to-recipe edges, one version per relevant item, immutable economic-input snapshots and one queued node per recipe. It stores no Market records/history and adds no SavedVariables. Estimate retains its existing question memo, cleared at 20,000 answers before the next recipe (a bounded single-craft overshoot is possible); Pricing retains its existing 8,192-entry bound. Reconciliation may temporarily retain the previous catalog while a replacement is built. Queues and progressive sorting have linear temporary storage; neither is a permanent background task.

Partial completion increments the existing public pricing revision but does not replace the estimator context. Batch completion supplies affected item IDs; row getters suppress stale estimates immediately, even before budgeted invalidation reaches their dependency edge. Pending/combat answers are never memoized. Terminal missing records settle and remain unknown. Completed estimates remain valid even if the reader evicts their decoded partition. Per-bucket preparation uses the existing pricing cache/reservations; a lease prevents decoder handoff before demand registration finishes. Cancellation drops only that unfinished lease, leaving shared decoder work and other consumers intact.

Full contexts include source/generation/failure/readiness, local scan time and sequence, scan completion, character/faction identity, cut/source, fee evidence and duration, hourly freshness plus exact local stale/fair-age thresholds. Vendor/item metadata changes invalidate affected items; recipe reconciliation compares copied economic inputs rather than mutable table identity. Cooldowns refresh on a requested time change, without a permanent ticker. New economic fee evidence invalidates conservatively; unrelated Ledger changes with identical fee evidence preserve estimates. Page switching cancels work, compatible reopening reuses completed results, suspension releases transient state, and token guards reject stale callbacks. Worker failures fail closed once for that context and recover on an explicit reopen/new context.

Visible-first scheduling promotes existing queued rows and not-yet-requested visible buckets. It does not abort/reorder another consumer's shared decoder. Partial order stays provisional; final ordering uses the original profit/cost/sell/margin comparator and filter semantics. Scroll anchoring preserves the first visible ID across incremental ranking updates, while explicit criteria changes may intentionally reorder the page. Selection/details and queue actions retain their existing validation.

## Layered regression policy

| Tier | Command / selection | Budget and cadence |
| --- | --- | --- |
| Development | `./tests/run.sh development market-performance --jobs 2` | Under 30 s target, 60 s review ceiling; relevant commits and PRs. Ten deterministic modules, no simulator or benchmark. Existing PR workflow selects it. |
| Benchmarks | `python tools/measure_market_opportunities.py ...` | Opt-in for performance-sensitive PRs; one warm-up then three fresh processes per case. Never ordinary test discovery. |
| Integration | `./tests/run.sh integration market --with-group crafting --with-group market-performance --profile cloud --jobs 2` | Cross-subsystem checkpoints; actual reader, fallback/corruption/rollback/generation, crafting/AH consumers and selected UI simulator launches. Does not certify a native client or release. |
| Stress | Existing driver `--stress --case opportunities/ui/5000 --rows 96 --scenario stress` | Scheduled/release preparation or explicit performance work; not every commit. One warm-up and at least three measured samples when establishing a timing baseline; a one-sample bounded diagnostic is labeled separately. |

Keep deterministic correctness/operation invariants as merge gates: unchanged reads perform zero Craft/reader/full-list work, a price update touches exactly its dependency set, terminal missing prices settle, shared questions are reused, stale jobs cannot publish, capacity limits release work, and waits have no polling loop. Tests compare every completed economic field, summary and ordering against full recomputation. The benchmark oracle is outside workload CPU/heap timing and excludes only private estimator links and lazily computed typical-profit decoration; the deterministic engine test covers complete estimate fields.

Store source revision, harness SHA, semantic fixture SHA, host/Lua versions, individual samples, medians and ranges under `docs/evidence/`. Compare only matching fixtures and harnesses on the same host; investigate outliers and callbacks over 10 ms, including origin and indivisible service-call scopes. Do not silently overwrite a baseline or raise budgets: intentional changes require reviewed rationale, fresh comparable samples and unchanged correctness checks. Keep failing evidence and link it in the PR. Select Market/pricing/engine tests for reader changes, crafting plus Market dependencies for Estimate/Session/Vendor changes, and selected Workshop/AH consumer UI coverage for shared list/Window/diagnostic changes. Full/release and large historical/mutation campaigns remain separate.

## Native Forever check

On a review build with the intended PR1/PR2 dependencies, use synthetic/test-safe data or the owner's existing companion delivery. No synchronization or publication is performed by PR3. Record client build, recipe count, contract, observation age and diagnostic clock/profile mode; keep those conditions constant when comparing revisions. Do not enable script profiling automatically.

1. Before opening Workshop, run `/tui perf start workshop 3`, then `/tui perf mark opportunities-open`. Open Workshop → Opportunities and avoid filters/scrolling until its initial visible cohort and all known rows settle. Mark `/tui perf mark opportunities-settled`.
2. Close/reopen the page with unchanged inputs; mark `/tui perf mark opportunities-warm`. Confirm immediate valid rows with zero new Craft/reader work, no full invalidation or sort, and no pending/running engine after settlement.
3. In a separate capture, change sort/profession/confidence filters, scroll during a cold calculation, change pages while it is busy, reopen, and inspect a selected recipe/add-to-queue confirmation. Perform no purchase/post/sell action. Test a new local scan or companion generation only through the normal owner-controlled process.
4. `/tui perf stop`; open Diagnostics and export Quick summary plus JSON through the existing UI. Reports contain bounded aggregate timings/counters, no item identifiers or Market payloads.

Read `workshop.opportunityBatch` total/worst CPU and `workshop.opportunityQuestion` indivisible service calls alongside `workshop.render`, Summary validation/load/completion CPU and elapsed wait distributions. The existing first/ten priced opportunities, fixed initial visible cohort, all-row settlement, partition load/repeat counters, pricing cache/pending gauges and five new recipe-state gauges distinguish calculation from queue waiting. `cacheHits` counts compatible catalog reads; `reused` counts recipe estimates preserved during catalog reconciliation; neither is a universal per-price hit rate. Final/provisional publication counters count prepared list publications; row/detail counters show actual visible presentation work.

Native goals: unchanged draws do zero economic work; isolated updates match dependency fanout; ordinary engine slices target 2–3 ms; investigate every callback over 10 ms. The elapsed budget can overrun by one synchronous service call, timer queues and GC affect client frame times, and first-open UI construction is separate from scheduled callbacks. Verify actual frame-time p95/p99, gameplay responsiveness, first/visible/all completion, memory after repeated lifecycle operations, and correctness of the final ranking. Offline virtual seconds are not predicted Forever latency.


Final verification: all 76 integration modules passed; six Auction preview
scenarios passed. The final Workshop rerun retains exactly the baseline 40 failed
tooltip assertions in each normal pose, and 41 in the intentional wrong pose.
No assertions were suppressed and the 45-second scenario limit is unchanged
(40.6 simulated seconds). [Exact failure comparison](../evidence/v2-market-pr3/simulator-comparison.json).
The initial nil-module failure and the first settlement helper's excess idle
waits were corrected and verified; historical failing run evidence remains in the
local verification artifacts. [Compact verification](../evidence/v2-market-pr3/verification.json).


The delivery follow-up keeps economic/runtime calculation code identical to
`6754427`; it adds capture-only first-row construction timing and preserves
all-known settlement when a filter has no visible rows. The final fast group
passed in 4.351 s and all 16 mutations were killed in 10.4 s. The scroll fixture
now dispatches both the stand-in's main script and HookScript listeners; its
initial offset-only timing is superseded, not treated as actual scrolling.
Optional Lua argument nine (`normal` / `nogc`) exposes isolated callback heap,
pool and indivisible-question diagnostics. Never disable GC in addon runtime.


The large-workload follow-up reuses provisional membership/position arrays while
the catalog and metadata-only filters stay unchanged. Existing row objects expose
new estimates without a full copy per 128 recipes; price/confidence filters still
rebuild membership. This removes quadratic presentation work for the default view
without adding a price cache. The fast group passes in 4.293 s; 18/18 targeted
mutations are killed. The repeated 76-module integration run passes all offline
modules and Auction preview, retaining exactly the known Workshop 40/41 failures.
New candidate measurements supersede the earlier PR3 checkpoint comparisons.
The longer memory probe records bounded memo/cache/row counts, rather than
assuming a rising heap is a leak or a plateau.
