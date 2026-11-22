# Market cold pricing PR2

Depends on unmerged [PR1 #99](https://github.com/Twich-Team/TwichUI/pull/99), baseline `cef81e0393ed1827fc7c7a3d5b2943b1b7145f60`. The addon branch is stacked on that head and targets `fix/v2-market-pending-pricing`, not main. Market producer/Companion work starts from canonical Market main `b5954ae2cf33c3b1daa4df8a1baf0f2c111c121a`; its backend/desktop/contracts match the previously audited beta.10 source. No Ledger changes or live operations.

## Evidence and decision

The owner supplied a real Forever 1.60.1/build 71037 capture summary: 2,816 summary-validation calls / 4,820.72 ms, versus 10 addon loads / 10.94 ms, 175 lookups / 2.57 ms and 11 pricing handoffs / 12.92 ms. The independently observed 3–8-second cold-price gaps remain; the capture does not measure exact per-request waits. Its 94% validation share confirms the stage to address after PR1. Two memory samples and gross allocations do not establish a leak.

Production `Summary.rows` verifies the entire raw checksum, parses every tuple, re-encodes canonically, then validates all current and daily fields before a single current price is usable. Modulo-64 distribution and PR1's deduplication cannot remove that per-cold-partition work. A current-only copy after validation or binary search does not remove historical bytes from hashing/parsing/encoding.

### Isolated PR1 stage accounting

`tests/bench_market_cold_stages.lua` uses production modules and the shared fabricated fixture builder. It drives actual Q.Step, instruments stage boundaries and excludes suspended time from stage clocks. No game scheduler claim. Three fresh samples; medians below; phase probes/clock/debug overhead are included. Current/history attribution uses the production validation call sites. The header's one-time JSON-schema validation is outside these partition measurements; partition schema/evidence checks are the current/history validation rows.

| 512 exact records / one bucket | 2 days | 60 days |
|---|---:|---:|
| Raw bytes | 77,141 | 582,997 |
| Integrity SHA CPU ms | 107.26 | 794.49 |
| JSON decode CPU ms | 13.75 | 154.26 |
| Canonical encoding CPU ms | 15.85 | 178.81 |
| Current field validation CPU ms | 10.24 | 16.98 |
| History tuple validation CPU ms | 3.74 | 115.36 |
| Total instrumented CPU ms | 173.85 | 1,549.45 |

The remainder is coroutine/resume/Q.Step/observer overhead, reported separately in [raw stage samples](../evidence/v2-market-pr2/cold-stages-pr1.json). Stage net heap changes are not gross allocation counts; automatic GC can make them negative. Final collection and retained delta are separate. Instrumented totals are not used as uninstrumented latency baselines.

Reproduce with Lua 5.1/bitop from the repository root:

```sh
lua5.1 tests/bench_market_cold_stages.lua 2 512
lua5.1 tests/bench_market_cold_stages.lua 60 512
lua5.1 tests/bench_market_cold_stages.lua 60 512 variants
```

Copy only these two test helpers into a detached PR1 worktree when comparing unchanged production inputs. No benchmark enters ordinary test discovery.

Decision: negotiated separate projections. Even eliminating every selected record copy and row lookup cannot eliminate full historical checksum/parse and canonical traversal. Keep those integrity checks on demand for history, and give current-price consumers their own fully validated bytes. Do not increase frame budgets, weaken validation, retain every decoded partition or change prices.

## Contract and activation plan

Contract 3 retains 64 modulo-item buckets for each projection. Current rows retain all thirteen existing current/reference/coverage fields, including precomputed historical-derived values; history rows retain the exact existing fourteen-field daily-history representation. A single canonical generation manifest binds both descriptor sets, source observations, market, algorithm and receipt. History's first thirteen columns must canonically project to the current-part digest. Native and addon history validation enforce that binding.

Current and history have separate load-on-demand addon folders within each A/B bank, so pricing does not load raw historical strings. Native delivery validates and writes/readbacks both sets before its one root commit. A failed download or publication leaves the last complete root active; matching verified inactive parts can resume. No source observations, archives or SavedVariables are deleted. Schema/capability negotiation preserves contracts 1 and 2; older companions can continue delivering contract 2 to the new addon. Older addons never negotiate 3.

Producer, Companion and addon are separate review milestones. Safe rollout after review: producer support first (default remains 1), then compatible Companion, then addon capability activation. Roll back the generation using the compatible Companion before downgrading to software that cannot read contract 3. No rollout, merge, signed build, publication or service operation is part of this task.


## Consumer implementation milestone

Pricing passes an internal current-only option through Bridge.Record. Summary.Value
and Availability use the same verified projection. Default Record and History
continue to return rich history. Sorted exact item/variant records use binary
search; no additional index or decoded-partition cache is introduced. Contract 2
still validates all coupled history, but current-only callers avoid copying its
daily arrays. Pricing policy, estimator semantics and PR1 deduplication remain.

Current work has priority over optional rich work. At most one historical
coroutine can pause between slices and resume afterward without decoding again.
Cancellation, generation replacement and rejection clear queued/paused work.
The existing effective 2 ms slice, 512 resume limit and 16-resume handoff remain.
Individual operations can exceed that budget; this is not a hard frame-time
ceiling. Raw strings already loaded by WoW cannot be unloaded by cache eviction.
The one completed partition cache, one paused job and current active job bound
decoder retention; memory measurements must include transition allocations.

Missing/corrupt contract-3 payloads reject the paired generation and restore the
last admitted generation, where available. A first bad generation stays
unavailable. Combat postpones loads without treating them as corrupt. Both
projections are independently fully checksum/canonical/schema validated before
use, and rich validation additionally verifies its current prefix digest.

Diagnostics add bounded elapsed distributions using the existing engine,
separate from CPU scopes. The Workshop preset remains opt-in. No game payload,
character identity or unbounded per-item timeline is recorded.
