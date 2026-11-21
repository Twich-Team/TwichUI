# V2 Market → Opportunities performance audit #1

Audit date: 2026-11-21. **Audit/proposal only; no addon runtime, Market service, published format, installation or SavedVariables changes.** Evidence is offline Lua 5.1 production-code execution over fabricated data, plus repository inspection. No real-client performance acceptance is claimed.

## Executive summary

There are two different problems. The summary reader repeats complete integrity checking, JSON decoding and validation whenever a request returns to an evicted partition. Raw addon strings stay loaded, so this is repeated processing, not repeated addon loading. A warm single-item benchmark conceals this behavior.

Opportunities has an important protection: Pricing saves compact resolved records independently of the decoded partition. Our normal recipe workload settles without repeatedly decoding partitions. However, while partitions are pending, notifications repeatedly run the entire recipe list, and the estimator's identity changes as partitions become checked. Pending item queries repeatedly compute SHA-256 base-item identities and revisit the reader. The cooperative decoder has a time budget; the synchronous pricing warm-up and complete Opportunities redraw do not share that budget. A small decoder callback can therefore cause a much larger callback.

The precise cause of the reported **5–10 seconds per individual item in Forever remains unproven**. Offline results establish avoidable CPU work and a queue/refresh amplification mechanism. They do not establish the client's timer cadence, installed generation size, active page details, other-addon contention or GC pauses. Do not call a 60Hz timer model a measured game latency.

Recommendation: begin with an addon-only PR that coalesces pending price questions by identity/bucket, preserves resolved compact prices, bounds warming by elapsed time, and separates data-generation identity from partial-completion notification. Verify fallback invalidation explicitly. Then avoid repeated full-list calculation through measured incremental refresh. Preserve modulo-64 delivery initially. Consider a split current-price/history contract only if large-history cold measurements and client captures justify it. Simply retaining all decoded history is not the preferred fix.

## Source identity and reproduction scope

| Source | Exact reference |
| --- | --- |
| TwichUI audit base, fetched `origin/main` | `725519e6be87f3e3b9c75d8f7ad271572cb60a1f` |
| Released V2 initial tag `v2.0.0` / commit | `11b08afec28c314d0cceeddf2ec83da2a93d8ae5` |
| Latest V2 tag `v2.0.1` annotated object / commit | `3f49697e8a7686399c85921a53cf46e50b0cbe6e` / `a3bfd11317bd395f72298025270ad33834221016` |
| Market `origin/main` | `ec3dfc77abc8aef9dd40b09c29f4dcd4bbb2ca75`, README only |
| Inspected Market published-Companion integration | `3b59f0f34617cbcf12a43baddfeed7a1e668feb2`, `origin/integration/companion-beta10-release` |
| Prior synchronization investigation branch | `2c87bee`, `origin/feature/companion-sync-performance`; release status reviewed in beta.10 tree |

`git diff v2.0.0 origin/main -- TwichUI_Workshop/{Summary,Pricing,Estimate,Session,Bridge,Window,ViewOpportunities}.lua` is empty; likewise against v2.0.1. These runtime paths reproduce both released V2 source tags. This is source identity, not an independent attestation of every byte installed by a player's package. No Market main deployment was inferred from its name; integration history and release documents were read, with no live service access.

Engineering/test authorities reviewed: [engineering rules](../engineering-rules.md), [feature rules](../dev-rules.md), [architecture](../architecture.md), [test selection](../testing.md), [git workflow](../git-workflow.md); Market `AGENTS.md`, implementation plan and progress. Historical Market authorization entries are context, not authorization for this audit to deploy anything.

## Confirmed pipeline and costs

Source locations below refer to the pinned audit base; function names disambiguate line drift.

1. Market [`backend/market/workshop_summary.py`](https://github.com/Twich-Team/TwichUI-Market/blob/3b59f0f34617cbcf12a43baddfeed7a1e668feb2/backend/market/workshop_summary.py#L144): `seal/build` derive canonical exact-variant current summaries and, for contract 2, up to 60 actual daily closes. Each record carries 13 current/coverage columns plus daily tuples. This is already a summary, not raw auction listings or a full archive. Contract 1 caps 128 KiB/partition and 8 MiB total; contract 2 permits 1 MiB/partition and 64 MiB total, at most 150,000 records. Whole-generation overflow refuses publication, rather than silently pruning coverage.
2. Companion [`desktop/core/src/workshop_summary.rs`](https://github.com/Twich-Team/TwichUI-Market/blob/3b59f0f34617cbcf12a43baddfeed7a1e668feb2/desktop/core/src/workshop_summary.rs#L186): negotiated manifest + ETag; unchanged generation uses bound 304; changed generations reuse matching verified active or interrupted-staging parts, fetch remaining parts, validate the entire bundle, then activate private cache metadata. This is whole immutable generations with partition reuse, not an in-game streaming incremental network feed.
3. `publish` (same file, line 346) writes the inactive A/B bank, verifies parts/readbacks, writes `Previous.lua`, then replaces root `Data.lua`. Ownership, available space, running-game safeguards, scope/account and receipt checks remain requirements. There are 64 logical buckets; two fixed banks can leave **128 physical partition addon folders**, plus the root. Only the chosen bank's requested nonempty buckets are loaded. Folder count alone is not runtime work.
4. [Bridge.lua:352](../../TwichUI_Workshop/Bridge.lua#L352) routes summary contracts to [Summary.lua](../../TwichUI_Workshop/Summary.lua). Root header validation is separate from lazily requested part loading. `loadPart` (line 111) checks combat, loads absent globals with `C_AddOns.LoadAddOn`, retains raw strings, then starts a coroutine. Already-loaded strings skip addon loading but **do not skip validation/decoding**.
5. `rows` (line 67) hashes raw bytes, parses JSON, checks canonical re-encoding, ordering, exact variants, monetary bounds and every history tuple. `Q.Step` (line 140) resumes one job under a nominal 3 ms slice (budget subtracts 1 ms, maximum 512 coroutine resumes). It retains just `cached={bucket=...,rows=...}`. `active.checked` remembers successful validation but is not a decoded cache.
6. `Q.Record` (line 247) linearly scans rows: O(records in partition). It returns a new record and **copies the daily array even for current-price consumers**. `Q.Value` also goes through this projection. Rows are already sorted by `(item,variant)`; binary search can improve lookup without a large Lua hash index. `Variants` similarly scans the partition.
7. [Pricing.lua:49](../../TwichUI_Workshop/Pricing.lua#L49) caches compact records/negative answers, capped at 8,192 combined cached/pending identities. It intentionally omits daily data, but the reader has already copied it. Cache stamp is generation + failures; it does **not** clear merely because another bucket was decoded. Loading/combat are transient and not stored as terminal misses. Capacity returns explicit `lookup_limit` with local fallback rather than endlessly evicting/retrying.
8. `P.BaseKey` (line 46) hashes `{"id":...}`. Every unresolved `record` retry reaches this hash and `B.Record` again, even when that same item is already reserved in `pending[bucket]`. `pending` prevents duplicate reservation, not duplicate foreground queries. This is a high-leverage opportunity to deduplicate work without creating a second resolved-price cache.
9. `P.Decoded` (line 192) sorts pending IDs and warms 16 records synchronously, then schedules additional batches with `After(0)`. Only the first slice is guaranteed to run before eviction. Subsequent slices may encounter another decoded bucket; under sufficiently long pending lists this can request another decode. The ordinary measured workloads do not demonstrate this race. Sixteen records is an operation limit, **not** an elapsed-time bound; each may hash, scan, copy daily arrays, run eligibility and copy compact state.
10. `Summary.changed` and `notifyWarm` each debounce independently by 0.1 s. A newly checked bucket may therefore cause both validation and warmed-price notification. `P.Changed` clears Facts, bumps Strategy and redraws multiple consumers. The standard desktop price synchronizer (`desktop/core/src/synchronizer.rs:13`) separately stages cursor pages into SQLite and records completion/provenance; it is not called by this game-side path. [Window.lua:84](../../TwichUI_Workshop/Window.lua#L84) assigns `UI.Redraw` directly to `Win.Render`; it is not a central redraw debounce. [ViewOpportunities.lua:370](../../TwichUI_Workshop/ViewOpportunities.lua#L370) calls `S.Opportunities`, which calls `Op.Rows` for **all** recipes before filtering/sorting (Session.lua:684).
11. `P.Generation` includes `checked_parts`, failures and readiness. `P.Source` passes that identity into [Session.Estimator:639](../../TwichUI_Workshop/Session.lua#L639). Each changed checked-count causes a new estimator, even though previously resolved Pricing records survive. [Estimate.lua:50](../../TwichUI_Workshop/Estimate.lua#L50) memoizes questions, not completed recipe rows; `loading` is deliberately not memoized. Warm compatible draws reuse questions but still execute `Craft` once per recipe. Memo cap is 20,000; exceeding it starts a new estimator next draw.

### Scheduling, invalidation and lifecycle

The part queue is FIFO by first request, deduplicated per bucket, with one active decode. It does not prioritize visible recipes or material dependencies. Root completion replaces the queued request set. `After(0)` yields to the client timer system; there is no hard 5-second wait in the Opportunities path. SHA/parser/encoder yields and the 512-resume ceiling can require many callbacks even when each uses less than its CPU budget. There is no aggregate per-frame budget spanning decode, warm-up and redraw.

`Q.Cancel` discards current/queued work; old scheduled decoder callbacks compare job identity and become inert. Window suspension invokes Bridge.Cancel (Window.lua:483). Hiding/changing pages is different from disabling Workshop: price warming checks `W.Active` and generation/failure stamp, not an Opportunities page token. Work can continue to support other consumers. `Win.Render` exits when hidden; page switches can still leave previously requested Market work queued. Do not globally cancel shared pricing because a single page closes; a future consumer-scoped request lifecycle should distinguish these cases.

Do not remove `checked_parts` from the estimator key in isolation: terminal/local fallback answers can have been memoized while references were incomplete. Partial completion needs explicit dependency/revision invalidation, or a correct transient result contract. Failures and last-good rollback, stale age, market/faction mismatch, generation replacement and newer local scans must still change eligible answers. Existing generation/failure and bounded-negative caches should be integrated, not supplemented with an unrelated cache.

## Benchmark design and existing coverage

New [isolated Lua workload](../../tests/bench_market_opportunities.lua) and [Python measurement driver](../../tools/measure_market_opportunities.py) extend the existing `bench_*.lua`/`tools/measure_*.py` convention. Production code is loaded via the existing `auction_mock.lua` and actual Workshop TOC. No competing runner or production runtime monkeypatch is shipped; counters and scheduler substitution are confined to this offline harness. Harness wrappers count production operations; a deterministic timer queue substitutes for WoW timers only in the offline mock.

Synthetic data expands the committed contract-2 fixture to 64 buckets × 32 records = 2,048 exact variants. IDs route by modulo, base keys use production SHA, every seventeenth row has a modified exact identity (missing base price). 2-day and 60-day histories have validated manifests, hashes and daily tuples. Ordinary admission flags are set as in existing consumption tests because Pricing intentionally rejects synthetic-marked manifests; all data remains fabricated and labeled synthetic in reports. This does not weaken production admission. Values are transport/consumer fixtures, not an independent recomputation of the server pricing algorithm; existing pricing conformance/reference tests remain the arithmetic authority.

Reader workloads perform 1,000 successful exact-key lookups. `single` and `alternating` repeat the same item per bucket; `*-distinct` cycle through records per bucket and revisit earlier identities. The initial common lookup is measured separately, then included in total CPU; the cross-partition run's first query hits that initial bucket. Distinct tests use the same 64-request grouping for row-position progression, so row scan depth stays comparable. `batched` reorders the repeated-item request multiset by partition using the **unchanged reader**, to measure locality without implementing a fix.

Recipe fixtures contain 20/100/500/1,000 known schematic shapes with shared ingredients, two differing quantity patterns, varied outputs, and missing base identities at larger sizes. They call the real `Session.Opportunities → Opps.Rows → Estimate.Craft → Pricing` path. `session` replaces redraw dispatch with Session calculation; `ui` builds the real Window, selects Opportunities and runs its Render/detail/Strategy refresh. Item/profession APIs are synthetic. Reported completion means every scheduled callback drains and missing prices settle, not that all rows become priced. First/ten metrics refer to priced opportunities across the list, **not visibility**. The real-client diagnostic must separately capture visible-row completion.

Memory cases retain outputs of the real decoder at capacities 1/2/4/8/16/64 solely inside the harness. Numeric item→row-position hash indexes are separately modeled; the original integrated index net-heap metric is biased by unrelated collection (including negative values) and is excluded from footprint conclusions. A separate pure Lua table-shape workload measures index size after two baseline/retained full collections; exact variants would require ranges or a composite structure. No cache implementation/eviction policy is installed. Heap uses Lua `collectgarbage('count')`: retained deltas after full collection, sampled transition peaks, explicit collection cost, and net heap drops (not GC-cycle counts). Raw fixture strings exist before measurement and Lua interns identical loaded strings, so deltas **exclude the already-held synthetic fixture/raw bytes**. `raw_loaded_bytes` is reported separately. Do not sum raw bytes into a memory delta twice or treat this as exact WoW per-addon accounting. Full UI mock frame tables are also not native frame allocations.

Before timing, fixture generation/header validation and notification drain are excluded. One fresh-process warm-up per case is discarded, then three fresh-process samples; there is no shared mutable process cache. `os.clock` reports workload CPU separately from Python's whole-subprocess elapsed (which includes mock/fixture initialization). Timer model elapsed advances at least one 60Hz frame per `After`, with no CPU stall added to its virtual clock. Therefore modeled seconds and CPU seconds **must not be added or interpreted as wall-time predictions**. Opportunities `cpu_ms` includes the final compatible warm draw; subtract `warm_ms` for cold-only CPU. Callback CPU is inclusive of nested redraws; do not sum it with inclusive validation totals. Slice termination still uses the real CPU clock, so notification interleaving, callback counts and redraw totals vary across repetitions even with an ordered virtual timer queue. Assertions use stable invariants and ceilings, not an exact redraw count. Instrumentation itself adds overhead. The load proxy compiles/executes an in-memory trusted synthetic assignment; it excludes filesystem IO, TOC/dependency discovery and native client LoadAddOn overhead. Actual WoW addon-load cost remains a client measurement, not a proved microsecond bound.

Existing coverage inspected:

| Infrastructure | Existing strength | Gap this audit addresses |
| --- | --- | --- |
| `bench_workshop_summary.lua` | Native publisher artifact, compile/execute/header/enumeration and 1,000 warm same-item lookups | Repeated cross-bucket requests and full pricing redraw path |
| `bench_workshop_history.lua` | Contract-2 native output, focus validation, 100 history calls and retention | Multi-bucket Opportunities |
| `bench_market_bridge.lua`, `measure_market_a2.py` | Scoped bridge CPU/slices/heap, integrity and host timings | Different delivery reader and consumer amplification |
| `bench_workshop.lua`, TestLab Bench/Workloads | Warm-up, repeated samples, baseline comparison and crafting reference workloads | Summary partition scheduling and asynchronous UI |
| `measure_scoped_reader.py` | Source-qualified old/scoped readers, cold bytes and bounds | Modulo summary cache |
| `test_workshop_market_consumption_async.lua` | Already checks two-bucket progress, retained compact prices, idle settling, capacity pressure | Realistic many-recipes/64-bucket counts and time budgets |
| `test_workshop_summary.lua` and bridge tests | Hash/schema/variants/lazy load/rollback/generation contracts | Performance under churn; preserve these controls |

The new fast `test_workshop_market_performance.lua` checks 20-recipe settlement, single decode per needed bucket, shared memo hits, compatible warm reuse, bounded compact cache and bounded refresh work. Existing `market`/`workshop` globs discover it automatically; the new additive `market-performance` group selects five small invariant/integrity modules without simulator/dependency expansion. The amplification ceilings are **characterization guardrails**, not permission to retain current costs as the final target.

## Measurements

See [reviewed baseline evidence](../evidence/v2-market-opportunities/README.md) for commands, host, all samples, medians/ranges and interpretation. Tables below are populated from that evidence. No before/after production implementation measurement exists.

All values below are medians of three measured runs; ranges and every sample are retained in [2-day JSON](../evidence/v2-market-opportunities/baseline-2day.json). The 2,048-record fixture is 306,292 canonical partition bytes in total.

| Reader workload (1,000 lookups) | CPU ms | Lookup-only ms | Addon loads | Decodes / repeats | Compile + execute ms | Modeled timer seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| single | 14.60 | 5.82 | 1 | 1 / 0 | 0.025 | 0.08 |
| alternating | 9136.11 | 9127.07 | 64 | 1000 / 936 | 1.636 | 93.60 |
| single-distinct | 15.08 | 6.04 | 1 | 1 / 0 | 0.024 | 0.08 |
| alternating-distinct | 9156.85 | 9147.91 | 64 | 1000 / 936 | 1.968 | 94.87 |
| batched | 601.51 | 591.83 | 64 | 64 / 0 | 2.074 | 6.08 |

The alternating repeated-item run makes 936 repeated decodes after the 64 distinct buckets; grouping the same request multiset reduces total CPU by **93.4% (15.2×)**, with 64 decodes and no repeats. This is an access-order demonstration, not an implemented remediation. Single-partition lookup-only time is roughly 5 ms after initial validation, versus roughly 9.1 seconds of repeated cross-partition processing. In-memory assignment compilation/execution is tiny here, but excludes actual client addon loader/filesystem overhead.

| Recipes / path | CPU ms, cold + warm | First result CPU ms | Model first / first 10 / drain seconds | Full calculations | Craft calls | Reader calls | Base-key CPU ms | Worst callback ms | Warm ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 20 / session | 642.1 | 88.2 | 0.30 / 1.77 / 3.23 | 38 | 760 | 2163 | 226.0 | 20.5 | 0.7 |
| 20 / ui | 808.6 | 161.4 | 0.30 / 1.80 / 3.38 | 44 | 880 | 2784 | 295.4 | 20.8 | 0.8 |
| 100 / session | 3642.8 | 184.5 | 0.20 / 0.85 / 6.18 | 82 | 8200 | 19672 | 2028.3 | 86.7 | 3.2 |
| 100 / ui | 4468.9 | 540.7 | 0.30 / 0.80 / 6.43 | 96 | 9600 | 23009 | 2410.2 | 108.5 | 3.2 |
| 500 / session | 16135.2 | 1390.0 | 0.30 / 0.48 / 6.22 | 88 | 44000 | 101663 | 10383.0 | 345.8 | 28.6 |
| 500 / ui | 16571.4 | 1428.3 | 0.18 / 0.37 / 6.33 | 89 | 44500 | 101094 | 10551.6 | 368.5 | 20.9 |
| 1000 / session | 31189.7 | 2708.6 | 0.30 / 0.30 / 6.22 | 88 | 88000 | 197138 | 20316.9 | 681.7 | 36.3 |
| 1000 / ui | 34682.6 | 2850.7 | 0.20 / 0.20 / 6.35 | 96 | 96000 | 219176 | 22485.8 | 691.4 | 89.7 |

All ordinary recipe cases decode each needed bucket **once**: 33 for 20 recipes, 64 for larger sets. No repeated decodes. Pricing retains 53/164/564/1,064 compact identities respectively. All 20/100/500 recipes price; the 1,000-recipe case has 960 priced and 40 correctly unavailable modified-only base identities. Every compatible warm draw reuses its estimator and makes **zero reader calls**, but still calls Craft N times. A full calculation includes the explicit final warm draw.

| Retained decoded partitions, 2 days | Decoded/observer retained delta KiB | Sampled peak delta KiB |
| --- | ---: | ---: |
| 1 | 22.6 | 112.4 |
| 2 | 44.3 | 216.8 |
| 4 | 87.8 | 427.1 |
| 8 | 174.6 | 843.7 |
| 16 | 348.3 | 1677.8 |
| 64 | 1390.7 | 6707.0 |

Memory deltas exclude pre-held raw fixture strings. Loaded raw grows from about 14 KiB (including manifest) to 309 KiB; it remains loaded after decoder eviction. The original integrated index net-delta metric is excluded; see the controlled table-shape measurement below. Sampled peaks and observers include temporary validation allocations, not exact peaks inside callbacks. Contract-2 60-day retention is measured separately below.

For the 1,000-recipe Session case, approximately **65%** of total CPU is inside BaseKey hashing; partition validation is under one second, and assignment compilation/execution is a few milliseconds. Thus keeping additional decoded partitions would not remove the majority of the measured ordinary Opportunities CPU. Remaining time includes synchronous full recipe calculations, status/fallback/memo work, copies and GC; it is not fully attributed. Net heap drops show allocation churn, not measured GC pause time.

### Sixty-day history sensitivity

The [60-day evidence](../evidence/v2-market-opportunities/baseline-60day.json) keeps the same 2,048 identities and consumer workload, increasing only the historical fixture shape (coverage fields updated accordingly). Three measured repeats plus one discarded warm-up per case.

| Case | CPU ms | Decodes / repeats | Model timer seconds |
| --- | ---: | ---: | ---: |
| reader / single / 32 | 141.4 | 1 / 0 | 0.90 |
| reader / batched / 32 | 5037.6 | 64 / 0 | 57.80 |
| opportunities / session / 1000 | 54358.8 | 64 / 0 | 58.20 |

The 1,000-recipe run performs 130,000 Craft calls in 130 full calculations, with 325,354 reader/base-key calls. Hashing consumes 33.7 CPU seconds; validation 5.23 seconds; compatible warm calculation 38 ms and zero reader calls. Worst full callback is about 704 ms on this host. This demonstrates simultaneous retry amplification and residual cold history cost; neither is an addon-folder count measurement.

| Retained decoded partitions, 60 days | Retained delta KiB | Sampled peak delta KiB |
| --- | ---: | ---: |
| 1 | 279.6 | 1362.7 |
| 2 | 564.4 | 2686.8 |
| 4 | 1133.8 | 5333.1 |
| 8 | 2272.7 | 10522.1 |
| 16 | 4550.4 | 13477.1 |
| 64 | 18216.7 | 40424.5 |

All 64 decoded partitions retain about 17.8 MiB beyond the pre-held fixture/reader baseline, versus about 0.27 MiB for one. Raw fixture bytes total 2,329,716, tracked separately. The fixture has one exact variant per item; real multi-variant range/index overhead needs separate measurement.

Five CPU seconds to validate even a well-ordered cold 60-day fixture means pending-query deduplication alone cannot guarantee a ≤5-second complete-list client target for this shape, especially with cooperative queue waiting. The current/history split is therefore a justified next design candidate if PR1/2 leave this residual cost; authorize it against a measured client dataset rather than automatically migrating formats. No all-64 decoded cache is recommended from these small synthetic heap results.

### Controlled Lua index footprint

The [separate index measurement](../evidence/v2-market-opportunities/index-memory.json) isolates the same numeric item→position table shape (32 sparse numeric keys per partition). It uses full collections before and after allocation, keeps indexes live through measurement, and verifies their contents. The original integrated `index_retained_kib` values are net heap changes across other collector work, sometimes negative; they are **not valid index-size measurements** and remain only in raw baseline JSON for transparency.

| Partitions | Numeric index KiB |
| --- | ---: |
| 1 | 1.391 |
| 2 | 2.719 |
| 4 | 5.375 |
| 8 | 10.688 |
| 16 | 21.312 |
| 64 | 85.062 |

This measures numeric Lua tables only, not a complete per-variant index or a compact pricing-record cache. Multi-variant ranges/keys and data values add memory; binary search of existing sorted rows avoids this extra allocation. No index performance improvement is implemented or claimed.

## Root cause assessment

**Confirmed:** one-slot decoding thrashes for generic interleaved readers; first-time Lua compilation is a separate, much smaller stage on this fixture. History validation multiplies work by observations. Current-price access traverses/copies history. Pricing's compact cache prevents that raw-reader worst case in the ordinary Opportunities fixture, but pending retries repeatedly perform identity hashing and reader calls. Independent notifications and partial-completion estimator invalidation amplify full recipe calculations. Warm question memoization helps, but does not cache completed recipe calculations.

**Not established:** that a particular installed player's 5–10-second gap is dominated by redecoding, Lua compilation, GC or timer waiting. GC pressure and large callbacks are evidenced offline, but net heap drops do not assign pause duration. Fixture scale is much smaller than contract maxima and differs from the player's actual item/variant distribution. Source plus offline results support a combined CPU/scheduling/refresh diagnosis, not a single measured client cause.

The feedback path in the request is real: redraw→pending prices→decode→warm→notifications→redraw→all recipes. It is **not universally an endless decode loop**: the compact price cache allows ordinary workloads to settle. Repeated checked partitions suppress Summary's first-check notification but `P.Decoded` may still warm pending items and notify. The audit must preserve this distinction.

## Market delivery assessment

The delivered projection is appropriate in identity and provenance, but contract 2 couples current values to daily history that Opportunities does not need. A compact current-only path could avoid parsing, checking and copying historical tuples. The companion already receives canonical current fields and validates them; it can transform them, but it must not independently invent prices or silently merge modified variants. Server generation should bind any derived current index to the same exact source observation/algorithm, receipt and completeness semantics.

Modulo distribution spreads sequential IDs but does not guarantee balanced **bytes**: variant cardinality and history length differ. Our synthetic equal-row fixture is nearly balanced; it does not establish real production balance. Collect per-bucket records/bytes/min/median/max and consumer transitions from a redacted installed manifest/client capture before selecting capacity. Crafting-locality grouping might help one profession and hurt other pages; shared materials, multiple professions and patched recipe sets make stable grouping complicated. Changing the route changes contracts, publisher, both banks and compatibility; batch requests can gain locality without changing routing.

A scoped delivery for known recipes could reduce volume but requires safe upload of selected IDs/scope consent, renewed manifests as professions change, and correct absence semantics. The addon cannot fetch newly needed buckets over a network; it reads installed files at login/reload. The existing broad summary intentionally works without knowing every profession in advance. Do not reintroduce archive dependence or force extra sync/reload per page.

The prior [Companion synchronization investigation](https://github.com/Twich-Team/TwichUI-Market/blob/3b59f0f34617cbcf12a43baddfeed7a1e668feb2/docs/companion-sync-performance.md) and its release record already address key-query/page-size and productive preparation retry waits. Published beta.9 Windows synthetic comparisons report price sync 4.709→3.025 s/full, 9.605→6.054 s/incremental; automatic delivery 154.591→50.914 s, mainly removing retry sleep. These are **prior independently scoped evidence**, not reruns or improvements from this audit. The owner-PC partial sync capture attributed 95.6% to response waiting, with no active Workshop span; server vs WAN and complete owner-PC before/after remain limited. Beta.10 adds negotiated actual daily history. No duplicate sync optimization or deployment is proposed here. The inspected native `synchronizer.rs:13` still applies bounded sequential cursor pages to durable SQLite, then records source provenance/completion; Workshop preparation retries do not restart completed price pages. This preserves distinct sync-stage attribution.

Current full/incremental behavior is supported by source and prior retained tests; this audit does not rerun native Windows publication or a live database. Partition hash reuse/resume and bound 304s already exist. Changed observations can change many partitions even when only a few current prices differ because history is carried alongside current values. A split format may reduce that cost; measure changed-byte ratios before claiming savings.

## Architecture comparison and ranked recommendation

| Rank / option | Benefit | Memory/correctness/complexity | Decision |
| --- | --- | --- | --- |
| 1: C + small E, using existing compact cache | Collect unique pending identities once; bucket batches; bounded warming; coalesce refresh; preserve correct completed results | Keeps one decoder + ≤8,192 compact records; dependency revision must distinguish loading vs terminal missing/fallback | First addon-only milestone; addresses measured retry/refresh cost without a format migration |
| 2: B within existing reader/pricing ownership | Binary search sorted `(item,variant)` rows; current-only projection avoids daily copying; reuse existing price cache | Binary search adds almost no retained index; hash indexes cost Lua table slots + variant structures; generation-scoped base-key reuse must be bounded | Add after pending dedup; measure cold validation remaining cost |
| 3: E targeted recipe refresh | Preserve completed recipe estimates; reverse material/output dependencies; only changed recipes recompute | Extra dependency edges O(recipes×materials), invalidation on fees/vendors/scan/age/recipes, row sort still needed | Use if coalescing still misses frame goals; no generic reactive framework |
| 4: A bounded decoded cache | Avoids redecode for revisits/charts/general consumers | Tiny LRU 2–4 may not help cyclic 64-bucket access; 8/16 still thrash a round-robin; history/raw/rollback can coexist | Optional byte-bounded LRU after trace shows locality. Evaluate 2/4/8/16 and evictions; do not default to all 64 |
| 5: D split companion current/history | Removes history decode from pricing cold path, improves changed-part reuse | Versioned schema, atomic binding of two projections, publisher/server/Windows migration and last-good recovery tests | Conditional follow-up if cold/client evidence warrants; not necessary to remove repeated pending work |
| F broad hybrid | Combines all gains | More cache lifetimes, migration and invalidation surfaces | Adopt only the measured pieces in order above |

The first milestone should use an explicit bucket-completion handoff: deduplicate foreground reservations, transfer each requested compact result while that decoder remains available, and advance to another bucket after the time-sliced transfer finishes. Do not make ordinary reserved reads keep hashing/polling, and do not let an early-return pending guard block the completion writer itself. A short, budgeted decoder pin/handoff can avoid the >16-item eviction race without retaining several history partitions. Generation/cancellation tokens and pending-status reporting must cover this handoff.

In the 1,000-recipe Session baseline, 197,138 reader calls serve only 1,064 retained identities (about 185 calls per identity). A request-plus-completion design would target at most 2×1,064 reader calls in this no-eviction fixture, roughly 99% fewer calls. That is an operation-count acceptance target, not a demonstrated end-to-end speedup; removing retries also changes scheduling and notification interleaving.

A full per-item Lua table index should not be assumed cheaper than binary search. Price cache already supplies O(1) warm base-item reads. An index for every exact variant duplicates references the addon may never ask for. Numeric item→start/end ranges can be compact relative to composite string maps but still use Lua hash/array allocation; compare retained/transition heap and variant correctness, not just successful lookup CPU.

## Remediation roadmap: independently reviewable PRs

No PR below is implemented by this audit. Every implementation retains old behavior on disable/rollback and runs focused integrity/crafting correctness tests; no SavedVariables migration is needed for addon-only ephemeral caches.

| PR | Files / repository | Benefit and acceptance | Risks / tests / dependencies / rollback |
| --- | --- | --- | --- |
| **1. Deduplicate pending pricing and budget completion** | TwichUI `Pricing.lua`, Summary scheduling hooks only if necessary, Session invalidation contract, diagnostics scopes; existing consumption tests | At most one foreground reader request per unique pending identity per revision; no rehash on unchanged pending retries; no repeated ordinary partition decode; one shared refresh notification per burst; preserve resolved compact records. Budget warming by time as well as count | Loading→reference/local fallback correctness, delayed batches after eviction, generation/cancel races. Add 64 buckets, >16 pending/bucket, missing/base/modified variants, 8,192 limit, generation/failure/rollback tests. Depend on audit baselines; revert code, ephemeral caches reset next reload |
| 2. Current projection + sorted lookup | TwichUI `Summary.lua`, Bridge facade and Pricing call sites/tests | No daily copies for current-price queries; exact identity binary search; warm cache remains authoritative; bound scan comparisons logarithmically | Preserve public Record/History copy isolation and absent semantics. Differential tests vs existing reader, history mutation controls, same fixture before/after. Independent of Market format; revert API and callers together |
| 3. Incremental Opportunities work | TwichUI `Session.lua`, `Opportunities.lua`, `Estimate.lua`, view/window refresh | Compatible redraw performs zero Craft recalculations for unchanged recipes; pending completion recalculates affected recipes only; visible results first; CPU-bounded batches | Fee/vendor/age/new local scan invalidation, filtering/sort correctness, cancellation and other consumers. Test dependency counts and full-recompute reference equality; requires explicit revision semantics from PR1; revert in-memory orchestration |
| 4. Optional bounded reader LRU | TwichUI Summary/diagnostics/tests | Choose byte cap and max partitions only from measured real locality; no stale-generation hits; one decoder working set plus bounded retained cache | Peak old/new generations/raw strings; eviction while warming/history. Capacity/rollback/GC stress. Depends on PR1/2 metrics; revert cache policy without format change |
| 5. Optional current/history split | Market server contracts/export + companion download/publish; TwichUI negotiated reader | Current-only projection independently readable without history parse; same prices/exact identities/generation/freshness; no sync-cost regression | Require new version/capability, atomic same-generation projections, old-reader refusal/compatibility, interrupted publish, both-bank/Previous verification, native Windows consumer tests. Depends on residual latency and owner approval; preserve old negotiated format and last-good files; never activate partial data |

Quantitative **provisional engineering gates**, to validate on owner hardware before treating them as SLA: unchanged warm Opportunities calculation should make zero reader calls/decodes; after PR3 zero unchanged Craft calls. Ordinary cold pricing should decode each needed bucket once (extra only after explicit eviction, generation or failure recovery). Pending foreground reader work should scale with unique items + explicit invalidations, not number of redraws × recipes. Target added fast performance checks ≤30 s (hard review ceiling 60 s). Target decoder/warming slices ≤3 ms p95 and ≤5 ms p99 on reference host, excluding non-yieldable addon loading; capture and disclose worst callback/loads. Coalesced UI calculation should meet a separately measured ~3 ms/frame budget, which requires batching rather than merely labeling a full-list loop budgeted.

Provisional client usability goals: repeat page open first visible priced rows ≤100 ms when references/calculations are retained; ordinary cold fixture first 10 ≤500 ms and total ≤2 s for 100 recipes, ≤5 s for 1,000, with no unexplained ≥1 s idle gaps while useful work exists. These are proposed targets, **not demonstrated improvements or promises for 64 MiB/150,000-record maxima**. Adjust only with recorded installed-data/host evidence. Set a byte cap after measuring real active-bucket locality and total retained/raw/transition memory, not a guessed universal partition count.

## Automated regression strategy

Preserve `development/fast`, `feature`, `integration`, `full/release`; large benchmarks remain `bench_` files and are never ordinary discovery. No simulator, mutation campaign or full historical integration is added to routine performance checks.

| Tier | Trigger / commands | Budget and assertions |
| --- | --- | --- |
| 1 fast deterministic | Per-commit performance invariants: `./tests/run.sh development market-performance`. Relevant PR correctness: `./tests/run.sh development market`; pricing/estimator changes also `development crafting`; preview with `--list`. New small fixture is automatically included by existing group globs | Performance-specific additions target ≤30 s, ceiling 60 s; operation counts, correct prices, shared materials/memo reuse, one ordinary decode/bucket, no pending loops, generation/failure invalidation, compact cache capacities, stable idle. Tighten characterization bounds with each approved implementation. Relevant feature checkpoint retains existing selected simulator coverage |
| 2 dedicated benchmarks | On demand/performance PR: `python3 tools/measure_market_opportunities.py --suite all --reps 3 --days 2 --report test-output/opportunities.json`; repeat reader/opportunities/memory suites with `--days 60` as needed | Minutes, not a PR fast gate. Freeze source/fixture/harness/host, one warm-up, ≥3 measured runs, medians/min/max; compare cold/warm, access order, UI vs Session, capacity/memory, large sets. Existing `bench_workshop.lua --compare/--paired` remains for TestLab-format workloads; don't feed a different JSON format to it |
| 3 Market format integration | Before paired contract/publisher PR and release: `./tests/run.sh integration market --with-group crafting --list`, then same command; Market isolated `backend` test selection: `python -m pytest tests/test_workshop_summary.py` within the established backend environment | Separate CI job with existing DB fixtures, no production DB. Add paired native-generated output→Lua consumer and Windows publisher cases using existing summary/history benchmark/native workflows; verify generations/receipt/digests, full+incremental/reuse/304, freshness, interruption/corruption, schema negotiation, atomic last-good/SavedVariables preservation. Native unit command: `cargo test --manifest-path desktop/Cargo.toml --workspace --locked workshop_summary`. Existing `.github/workflows/desktop.yml` runs the Windows synthetic publisher and paired Lua consumer jobs. This audit's Lua-generated fixture is not a substitute |
| 4 stress/release | Scheduled/manual: benchmark driver `--days 60 --suite all`; then existing full/release gate as documented, matching money/quantity mutation groups only for implementation logic changes | Dedicated 10–30 min controlled budget initially, explicit timeouts; grow dataset toward 150k and legal per-part bounds, pathological variants, 8,192 cache pressure, 20,000 memo boundary, long 64-bucket churn, >16 warm queues, alternating generations, cancel/resume/page switches. Maxima may require refusal fixtures. Do not silently reduce coverage if memory guard refuses |

The new driver saves all runs/aggregates, source and harness hash, host/runtime and elapsed measurement definition. Baseline storage: reviewed compact evidence under `docs/evidence/v2-market-opportunities/`; generated runs remain ignored under `test-output/`. Future baseline changes must be a separate reviewed diff with old/new source, fixture/hash, runtime, host, semantic equality and reason (intentional algorithm/data change or documented host replacement). Never regenerate baseline solely to make a failure pass. Compare operation counts strictly; timing only on comparable host/runtime/fixtures, use a warning band (e.g. >20% median regression plus absolute ≥5 ms), repeat only to investigate stated noise, retain failures. Memory thresholds use retained/capacity invariants first, host-specific heap bands second.

Failure output must identify case, source/harness/fixture, seed/count/days, expected vs actual operations, first mismatched price, callbacks outstanding, cache capacity/generation, timing spread and sampled memory; attach the existing runner `report.json`/per-test log and benchmark JSON. CI does not silently bless a missing benchmark baseline. Pending work and timeouts fail, rather than being interpreted as completed missing prices.

Subsystem selection: Summary/Bridge/codec → `market` plus paired Tier3; Pricing/Estimate/Session → `market` + `crafting` and consumer groups (`item-advisor`, `workshop-settings`, `auction-preview`) as actually touched; UI-only Opportunities → crafting/workshop selection; companion contract/publisher → Tier3+Windows, independent sync stages; benchmark tools only → syntax + small fixture assertions + driver smoke, no full simulator. Existing CI ownership fallback/full-release protections remain unchanged.

## Minimal real Forever verification

Existing diagnostics are sufficient for an initial scoped capture, but **not all requested counters are currently available**. Do not claim an unimplemented audit command exists.

1. With WoW closed, synchronize normally using a supported Companion. Record Companion version, selected market, root generation and installed bytes/record count/bucket byte distribution; no confidential records needed. Launch/reload voluntarily, outside combat, with Workshop enabled. Keep the same generation and known recipes for cold/repeat comparisons.
2. Open `/tui perf`; select General performance (all operations; there is no dedicated Workshop preset). Start a one-minute capture with `/tui perf start general 1`, mark `opportunities-open`, open Workshop → Opportunities. Record wall time to first priced row, first ten and visible rows settled, then total settlement including missing-price reasons. Mark completion; `/tui perf stop`; export the existing report. Repeat opening the same page without reloading to measure warm behavior. Do not run a scan/trade/auction action to test this.
3. Inspect registered `workshop.summaryLoad`, `.summaryValidate`, `.summaryLookup`, `.summaryHistory`, `.estimate`, `.render` and gauges for raw bytes/loaded parts/decoded rows/checked parts/pricingReferences/estimate memo. Compare total/worst calls and memory timeline. CPU scopes are inclusive. Addon load is not decoder time; a loaded-parts gauge alone cannot count redecodes. Current `Summary.Status` lacks a decode execution counter; existing timers lack a central wait registry.
4. First implementation instrumentation PR should add an **opt-in bounded aggregate report** inside R.Perf: actual decode starts/repeats per bucket; price hits/terminal misses/pending coalesces; estimator instances/full-list and recipe recalculations; pending queue high-water/oldest/total wait; warm and redraw callback total/worst; first/first10/visible/total settlement timestamps. Count no payloads/item links/player names, do not store frame/function references, reset per capture/generation, cap buckets at 64 and omit per-item logs. Extend DX.OPS/Gauges and tests; off path must cost at most a branch, no continuous polling. Coalesce memory sampling with existing diagnostics (UpdateAddOnMemoryUsage is expensive); no forced GC during normal capture.
5. Repeat cold/warm at 20/100/500/1,000 known recipes where feasible; compare baseline/remediation on same PC/client/addons/generation. Capture frame metrics and input responsiveness during movement/combat separately; never load data addons in combat. Switch pages/hide/disable while pending, then return; verify useful progress, safe cancellation and no stale prices. Change generation only through closed-game sync/reload; verify same exact item/variant and local fallback/fees behavior. Preserve pre-change report and last-good files.

This minimal workflow requires manual timestamp observations now; PR1's bounded aggregate diagnostics makes it concise and repeatable. It is intentionally not implemented in runtime during this audit.

## Remaining unknowns and decision

- Real installed bucket byte/variant/history distribution, cache working set and active consumers; synthetic balanced partitions cannot answer these.
- Actual timer cadence and frame stalls under gameplay; source `After(0)` is not a guaranteed one-callback-per-frame contract.
- Real GC pause attribution, native frame/object costs, addon Lua compilation and concurrent addon cost on Forever.
- Long warm queues after cache eviction, 8,192 identities and 20,000 memo boundary need dedicated stress coverage beyond this ordinary workload.
- Native current/history producer and Windows crash/publication behavior were inspected in prior evidence, not rerun by this audit; no production/network speedup is inferred.
- A compact current format may still be needed at full history scale; do not conflate avoiding repeated work with eliminating all cold validation latency.

**Authorize PR1 first**, with operation-count and frame-budget acceptance, then inspect residual cold validation and UI cost before authorizing format changes or a broader cache. No merge, deployment, publication or runtime remediation is part of this audit.

## Audit-tooling verification

Unit-tested: `./tests/run.sh development market-performance --jobs 1` passes all
five modules in 2.131 s, syntax included; the added test costs 1.476 s.
`python3 tests/test_test_runner.py` passes 17 infrastructure cases in 4.989 s,
including deliberate failure/timeout controls and selection validation for every
group. Python compilation, Lua syntax, local links, baseline/harness identity and
84 reader/Opportunities/retention samples and three controlled index samples were checked. [Receipt](../evidence/v2-market-opportunities/verification.json).
No simulator or full release campaign was required for these isolated tooling,
additive selection and documentation changes; no production price logic changed,
so no financial mutation campaign was run. Real-client and paired native publisher
measurements remain the explicit limits above.
