# Market cold pricing PR2

Current prices previously waited for whole historical partitions to be hashed,
parsed, canonically re-encoded and validated. PR2 implements negotiated compact
current records and independently lazy rich history, preserving their generation
binding and all pricing fields. It retains the modulo-64 architecture and PR1.
In the large native-file experiment, current enumeration CPU falls 11.96× and
retained reader heap falls from 41.44 to 3.87 MiB. Addon-only changes on the old
format do not demonstrate a cold-path solution.

Actual Forever request-latency targets remain unverified. The 1,000-recipe UI
stress case still has long redraw callbacks; this is a PR3 concern, not a claim
of frame-safe completion. Three coordinated draft PRs are ready for review; no
deployment, merge or publication occurred.

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

The retained stage samples pin the two helper hashes from milestone `4da50dd`; copy those versions into a detached PR1 worktree to reproduce that exact phase-accounting fixture. Later helpers add split fixtures and GC experiments. Copy only test helpers when comparing unchanged production inputs. No benchmark enters ordinary test discovery.

Decision: negotiated separate projections. Even eliminating every selected record copy and row lookup cannot eliminate full historical checksum/parse and canonical traversal. Keep those integrity checks on demand for history, and give current-price consumers their own fully validated bytes. Do not increase frame budgets, weaken validation, retain every decoded partition or change prices.

## Contract and activation plan

Contract 3 retains 64 modulo-item buckets for each projection. Current rows retain all thirteen existing current/reference/coverage fields, including precomputed historical-derived values; history rows retain the exact existing fourteen-field daily-history representation. A single canonical generation manifest binds both descriptor sets, source observations, market, algorithm and receipt. History's first thirteen columns must canonically project to the current-part digest. Native and addon history validation enforce that binding.

Current and history have separate load-on-demand addon folders within each A/B bank, so pricing does not load raw historical strings. Native delivery validates and writes/readbacks both sets before its one root commit. A failed download or publication leaves the last complete root active; matching verified inactive parts can resume. No source observations, archives or SavedVariables are deleted. Schema/capability negotiation preserves contracts 1 and 2; older companions can continue delivering contract 2 to the new addon. Older addons never negotiate 3.

Producer, Companion and addon are separate review milestones. Safe rollout after review: producer support first (default remains 1), then compatible Companion, then addon capability activation. Pause automatic delivery, restore a compatible previous 1/2 generation with the new Companion, then downgrade the addon/Companion. If no compatible previous generation remains, keep the new Companion, install the older addon so it explicitly negotiates 1/2, and complete that synchronization before downgrading the Companion. Re-enable delivery only after the supported pair is verified. No rollout, merge, signed build, publication or service operation is part of this task.


## Consumer implementation milestone

Source anchors at the measured consumer revision: [partition validation](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Summary.lua#L93),
[separate addon loading](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Summary.lua#L161),
[budgeted scheduler](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Summary.lua#L222),
[exact record lookup](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Summary.lua#L362),
[pricing admission/cache](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Pricing.lua#L148),
and [visible-row diagnostics](https://github.com/Twich-Team/TwichUI/blob/c70566f3a83cfe9da49402b57aa4e614e3c13140/TwichUI_Workshop/Pricing.lua#L55).
Producer [seal_split](https://github.com/Twich-Team/TwichUI-Market/blob/b02a190f22fd403a35c0856dfb3c598cd0720bc7/backend/market/workshop_summary.py#L201)
and [negotiated routes](https://github.com/Twich-Team/TwichUI-Market/blob/b02a190f22fd403a35c0856dfb3c598cd0720bc7/backend/market/workshop_summary.py#L363)
feed native [paired validation](https://github.com/Twich-Team/TwichUI-Market/blob/0ed2edaa5d5fd03eb22501522f6e6dda4a619fa0/desktop/core/src/workshop_summary.rs#L171),
[download](https://github.com/Twich-Team/TwichUI-Market/blob/0ed2edaa5d5fd03eb22501522f6e6dda4a619fa0/desktop/core/src/workshop_summary.rs#L216)
and [atomic publication](https://github.com/Twich-Team/TwichUI-Market/blob/0ed2edaa5d5fd03eb22501522f6e6dda4a619fa0/desktop/core/src/workshop_summary.rs#L385).

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
One active completed partition, the existing previous-generation rollback cache,
one paused historical job and one active job bound decoder retention. Status
decoded-row gauges describe the active completed cache, not the previous cache
or partially parsed coroutine locals; memory measurements must include all of
these transition allocations and whole-UI heap.

Missing/corrupt contract-3 payloads reject the paired generation and restore the
last admitted generation, where available. A first bad generation stays
unavailable. Combat postpones loads without treating them as corrupt. Both
projections are independently fully checksum/canonical/schema validated before
use, and rich validation additionally verifies its current prefix digest.
The native publisher checks the entire pair before root activation. The lazy
addon detects missing/corrupt unloaded files when they are requested; it does
not decode all history to prove its on-disk presence at header admission.

Diagnostics add bounded elapsed distributions using the existing engine,
separate from CPU scopes. The Workshop preset remains opt-in. No game payload,
character identity or unbounded per-item timeline is recorded.



## Comparable Opportunities measurements

Host: Linux 6.18.57 x86-64, AMD EPYC 9V74 (five virtual CPUs), Lua 5.1.5/bitop,
Python 3.12.14; shared cloud host, no CPU pinning or dedicated-hardware claim.
One discarded warm-up then three fresh processes per case, automatic GC enabled.
PR1 production is unchanged `cef81e0`; only benchmark helpers were copied into its
isolated worktree. Candidate runtime is `c70566f`; `5f2179d` changes CI only.
All reports have harness SHA `803abde5d167709f5347639d05ab5b165442f7d7f281f7ab3dad014b2bf02f69`.
Same ordered rich-record hashes and recipe fixture per comparison, 32 records
per bucket / 2,048 variants, shared ingredients, variable quantities and deliberate
missing base identities. There are 20/100/500/960 fully priced recipes respectively;
all samples agree across formats. Header admission and fixture construction are outside Lua workload
CPU; subprocess wall includes construction/startup and is not pricing latency.
A small 129-variant API fixture ran during the campaign; no other heavy benchmark
or simulator ran concurrently. Ranges are retained; small differences are noise,
not evidence of faster algorithms. Large native measurements below run separately.

Workload CPU medians (ms), actual Session.Opportunities path; totals include one
separately timed warm verification draw (`warm_ms` in the reports):

| Recipes | PR1, 2 days | PR2, 2 days | PR1, 60 days | PR2, 60 days | 60-day CPU reduction |
|---:|---:|---:|---:|---:|---:|
| 20 | 366.2 | 258.1 | 2,676.4 | 275.8 | 89.7% |
| 100 | 1,154.5 | 752.2 | 5,587.6 | 762.4 | 86.4% |
| 500 | 3,008.7 | 1,945.8 | 7,668.0 | 2,177.1 | 71.6% |
| 1000 | 6,348.7 | 4,933.5 | 10,613.2 | 5,400.5 | 49.1% |

Keeping the coupled contract on the candidate costs **10,938.9 ms** for
1,000 recipes / 60 days versus PR1's **10,613.2 ms**: no demonstrated addon-only
cold-path benefit. With split current data that case costs **5,400.5 ms**. For
20 recipes it falls **89.7%**, from 2,676.4 to 275.8 ms. Rich history grows
substantially between two and sixty days, while compact current fields stay
similar; current-only CPU is largely independent of daily tuple count. At large
recipe counts the existing calculation/redraw path dominates the remaining CPU.

Virtual timer progression (seconds), same Session path. This model imposes at
least one 60 Hz frame on every After, does **not** advance virtual time by CPU
spent in callbacks, and is **not** the WoW scheduler or measured client latency.
It exposes scheduling volume; it cannot establish a native sub-second result.

| Recipes / 60 days | First priced row PR1→PR2 | Ten priced rows PR1→PR2 | All price identities settled PR1→PR2 | Request p95 PR1→PR2 |
|---:|---:|---:|---:|---:|
| 20 | 1.95 → 0.18 | 16.57 → 1.52 | 30.22 → 2.75 | 29.27 → 2.67 |
| 100 | 1.93 → 0.18 | 7.43 → 0.68 | 58.57 → 5.35 | 54.78 → 5.02 |
| 500 | 1.93 → 0.18 | 3.82 → 0.35 | 58.60 → 5.45 | 55.88 → 5.20 |
| 1000 | 1.95 → 0.20 | 1.95 → 0.20 | 60.62 → 6.47 | 57.80 → 6.15 |

The full 1,000-recipe UI / 60-day case costs **10,820.3 → 5,825.2 ms** CPU;
price settlement is **60.45 → 6.47** virtual seconds. PR2 then loads one optional
rich chart; the price-only Session path loads none. Warm redraws perform **zero
reader calls**, reuse the estimator, and range from roughly 0.6 ms at 20 recipes
to 38–43 ms at 1,000 in PR2. That large warm cost is not an instant/frame-safe UI.

For 1,000 recipes both formats issue 2,128 reader calls / 1,064 identity hashes
and retain 1,064 terminal price references. Each of 64 current buckets decodes
once; no repeated Session decode. Sixty-day full-list passes (including that warm check) fall 66→52 in the
Session path, but that still means about 52,000 Craft entries. These counts are
not an incremental-calculation fix. The UI path has one additional rich decode.

The worst full-UI callback median is **144.9 → 192.9 ms** in this stress fixture;
52–55 complete list redraws and automatic GC remain substantial. This result is
retained as a limitation, not hidden by the decoder improvement. Existing slice
limits are unchanged, but this benchmark does not prove gameplay frame safety.
The 20-recipe Session worst callback improves 17.0→6.2 ms. Native acceptance
must examine both validation slices and rendering, and PR3 must address large
redraws if the real capture confirms them.

Raw samples/ranges: [PR1 two days](../evidence/v2-market-pr2/baseline-2.json),
[PR2 two days](../evidence/v2-market-pr2/candidate-2.json),
[PR1 sixty days](../evidence/v2-market-pr2/baseline-60.json),
[PR2 sixty days](../evidence/v2-market-pr2/candidate-60.json),
[addon-only sixty days](../evidence/v2-market-pr2/addon-only-60.json).

Reproduce from a disposable PR1 worktree and the candidate. Copy the **same**
`tests/bench_market_opportunities.lua` and `tools/measure_market_opportunities.py`
from `c70566f` into both source trees; verify that only those test/tool files
change on PR1. Run each command separately on the same idle host:

```sh
# PR1 worktree; repeat --days 60. One warm-up + three recorded fresh processes.
python3 tools/measure_market_opportunities.py --suite opportunities --contract 2 --days 2 \
  --case opportunities/session/20 --case opportunities/session/100 \
  --case opportunities/session/500 --case opportunities/session/1000 \
  --case opportunities/ui/1000 --report /tmp/pr1-two-days.json
# Candidate worktree: same command with --contract 3, then --days 60.
# Isolate addon-only effect on candidate:
python3 tools/measure_market_opportunities.py --suite opportunities --contract 2 --days 60 \
  --case opportunities/session/1000 --report /tmp/pr2-coupled.json
```


## Large native publication, memory and load accounting

[Fixture descriptors and digests](../evidence/v2-market-pr2/large-fixture.json):
30,000 exact variants / 29,233 distinct items, 60 dated historical observations,
64 uneven buckets, including 768 variants of one item. Actual production sealer
and native fixture assembler, not fabricated Lua strings held by the timing
harness. Rich bytes are identical across the coupled and split generations.
Three fresh recorded processes after one discarded warm-up, no competing local
heavy job. The native harness/driver are pinned by `abe03ce` (reader harness SHA
`3b8eef5588baead562580c75f44b445c7a57f148b5304e68d453b4f480408c4c`).

| Raw payload distribution | Total bytes | Min / median / max bucket bytes |
|---|---:|---:|
| Current | 3,510,064 | 54,289 / 54,289 / 89,857 |
| Rich history | 36,000,064 | 556,801 / 556,801 / 921,601 |

This stays inside the existing 1 MiB per-part limit. Current processing uses
**90.25% fewer payload bytes** than the coupled input. Companion still delivers
both projections atomically: total raw transport grows **9.75%**, plus descriptors,
TOCs and up to 64 additional part requests on a fresh generation. No claim of a
sync improvement; verified unchanged parts and rich 2↔3 migration reuse avoid
unnecessary downloads. Network/preparation time remains outside in-game pricing.
This audit does not activate a new server export or change retention/collection.

| Native-generated reader workload, median | PR1 coupled | PR2 split |
|---|---:|---:|
| Header validation CPU | 27 ms | 43 ms |
| Compile/execute files for current queries | 181 ms | 21 ms |
| Enumerate all current items + validate 64 buckets CPU | 74,190 ms | 6,204 ms |
| All current queries including revisiting hot bucket + warm 1,000 reads CPU | 76,126 ms | 6,365 ms |
| 1,000 warm current-value reads | 54.78 ms | 4.76 ms |
| Retained heap after current queries / explicit GC | 41.44 MiB | 3.87 MiB |
| Sampled peak after Q.Step, current queries | 105.69 MiB | 8.10 MiB |
| Separately requested largest rich history CPU | already validated | 2,075 ms |
| Retained heap after that explicit history read | 41.27 MiB | 11.38 MiB |
| Sampled peak including explicit history | 105.69 MiB | 24.94 MiB |
| Worst validation callback, includes optional history | 22.51 ms | 16.37 ms |

Current enumeration CPU falls **91.64% (11.96×)**, and retained current-query heap
falls **90.66%**. This is actual offline process CPU, not an elapsed game result.
The all-query total also revisits the hot bucket after enumeration (one-entry
cache), so it includes a repeat decode before the 1,000 warm values; this is
intentionally identical access order on both sources. The explicit rich read
restores all original points and independently verifies the prefix binding.
Baseline `history_loads=0` means history was coupled into its 64 ordinary files,
not that it avoided historical processing. Candidate loads 64 current files and
only one explicitly requested rich file. Largest callback includes GC/loads and
cannot be treated as a hard 2 ms guarantee.

Heap is whole process minus pre-load baseline; measured native files are read
from disk, without pre-held payload strings. Retained heap follows a forced
collection **only in this offline benchmark**. Peak is sampled and a lower bound;
it is not an exact allocation high-water mark. A fresh generation has no prior
rollback cache. Explicit history, previous-generation cache and a paused decoder
can increase transition memory; those are bounded but not zero. Raw strings
cannot be unloaded once WoW has loaded their addons. Inspecting every historical
bucket can eventually retain all its raw strings, plus compact current data.
The 32 MiB current / 64 MiB history contract caps are refusal limits, not expected
normal retained memory or a recommendation to load them all.

Full Opportunities UI memory is different: the synthetic 1,000-recipe / 60-day
case retains about **40.9 MiB** and samples a peak around **116.1 MiB** on PR2,
mostly existing estimates/UI state and temporary work. Its harness pre-holds
fixtures before baseline collection, so its raw-payload delta is not a true
native raw-memory measurement. Use the native file experiment above for reader
memory. Neither this nor the supplied two client samples establishes a leak.

[PR1 native samples](../evidence/v2-market-pr2/large-baseline.json) and
[PR2 native samples](../evidence/v2-market-pr2/large-candidate.json) retain every
run/range and host/source/harness/root digest. Reproduce with pinned Market
`0ed2eda` tooling and an isolated output path:

```sh
# Market repository; synthetic sealer input only, no database/provider access.
PYTHONPATH=backend python scripts/measure-workshop-history.py --variants 30000 \
  --days 60 --distribution uneven --contract 2 > /tmp/coupled.json
PYTHONPATH=backend python scripts/measure-workshop-history.py --variants 30000 \
  --days 60 --distribution uneven --contract 3 > /tmp/split.json
cargo run --manifest-path desktop/Cargo.toml --locked --example workshop_fixture -- /tmp/coupled.json /tmp/coupled-addons
cargo run --manifest-path desktop/Cargo.toml --locked --example workshop_fixture -- /tmp/split.json /tmp/split-addons
# Copy the same abe03ce bench_workshop_summary.lua + measure_scoped_reader.py
# into the isolated PR1 worktree; production reader files stay unchanged.
python3 tools/measure_scoped_reader.py --summary-root /tmp/coupled-addons --report /tmp/old-native.json
# Candidate source tree:
python3 tools/measure_scoped_reader.py --summary-root /tmp/split-addons --report /tmp/new-native.json
```


A separate [GC accounting experiment](../evidence/v2-market-pr2/gc-pr1.json) uses
unchanged PR1 production code, three fresh 512-record/60-day partition samples
with phase probes. Enabled versus stopped collector CPU is 1,539.3 versus
1,536.1 ms: this does not identify GC as the primary validation CPU cost.
Pre-final-collection heap delta rises 21.89→31.50 MiB when GC is stopped;
post-collection retained delta is 4.45→4.52 MiB, and forced final collection takes
10.65→15.69 ms. Those are instrumented endpoint heap readings, not gross
allocation counts or a measured maximum. The collector is stopped only inside
this disposable experiment, never in runtime code. Reproduce in the PR1 tree
with the c70566f test helpers, three fresh processes per command:

```sh
lua5.1 tests/bench_market_cold_stages.lua 60 512 ordinary
lua5.1 tests/bench_market_cold_stages.lua 60 512 ordinary gc-stopped
```


## Review and regression protection

Three coordinated draft reviews implement the protocol: [producer Market #43](https://github.com/Twich-Team/TwichUI-Market/pull/43), [Companion Market #44](https://github.com/Twich-Team/TwichUI-Market/pull/44), and [consumer TwichUI #100](https://github.com/Twich-Team/TwichUI/pull/100). Consumer #100 depends on unmerged #99. Producer defaults and installed releases are unchanged. The consumer branch alone continues receiving coupled contract 2 from the released Companion and cannot eliminate that format's historical validation.

| Tier | Selection and budget | Use |
|---|---|---|
| Fast | `./tests/run.sh development market-performance --jobs 2`; eight deterministic modules, measured 2.8 s locally, target under 30 s excluding installation | relevant PRs including stacked bases, ordinary edits; new workflow uses the existing runner |
| Dedicated | `tools/measure_market_opportunities.py`, explicit cases, discarded warm-up + three fresh processes | relevant performance work/on demand; no routine timing threshold |
| Integration | focused Market backend/auth tests, native workspace, actual API/native/Lua pairing and existing `integration market --with-group crafting` | protocol changes; separate Windows publication + Linux reader artifact check |
| Stress/release | explicit 30,000-variant/60-day uneven native publication, 768 variants of one item, longer lifecycle/generation and memory runs | release preparation or scheduled validation; never ordinary test discovery |

Fast tests protect independent current/history loading, exact variants and prices,
current schema mirror, rehashed mismatched-history refusal, whole-generation
rollback, missing first payload, finite settlement, generation/cancel cleanup,
one paused decoder, current priority and non-restarting history. PR1's tests
continue covering deduplication, cache capacity/invalidation, local fallback,
combat retry and estimator reuse. Diagnostics tests cover observation bounds,
60-second tails, reset/disabled behavior, no CPU contamination, exports and
pre-Workshop passive gauge selection. Fifteen targeted mutants were caught
(three new cold-path/binding/priority defects and twelve existing PR1 defects).
Native tests additionally protect partial downloads, verified reuse, canonical
pair validation, 304 negotiation, cancellation before each root commit, no-op
readback, unknown-file refusal and SavedVariables sentinels. Producer tests
protect authenticated/scoped route negotiation and exact prefix projections.

Timing baselines remain versioned JSON under `docs/evidence/v2-market-pr2/`.
Compare semantic fixture and harness hashes first, then operation counts,
medians/ranges and memory on a comparable host. Do not compare virtual scheduling
seconds with real-client request waits. An intentional baseline update requires
a separately reviewed source/fixture justification and old/new results; it must
not update expected price values to excuse a failure. No long benchmark is added
to `tests/run.sh` defaults. A format regression fails laziness/binding invariants
even on a fast CI host.

## Native acceptance after separately authorized activation

This environment cannot run the real Forever client. Linux Lua CPU, native
staging, automated Windows disposable publication and modeled timers are distinct
evidence levels. No offline result establishes that the player's 3–8-second gaps
are eliminated. No signing, release, deployment or game-file modification occurs
in this task.

1. Use the coordinated reviewed producer/Companion/addon only after a separate activation decision. Synchronize while the game is closed; preserve normal configuration/SavedVariables. Confirm a complete contract-3 generation and receipt in Companion, with matching market/source in Workshop. Record generation, client/build, recipe count, hardware and other addons. Test old contract 2 separately for compatibility.
2. Reload once for a cold addon/cache state; do not clear SavedVariables. Before opening Workshop, run `/tui perf start workshop 3`, then `/tui perf mark opportunities-open`, `/tui workshop`, and open Opportunities with the Market reference source. Keep the same filters, initial scroll and visible rows throughout the capture. Do not scan the Auction House during it.
3. Wait for prices or terminal missing results; stop with `/tui perf stop`. Open `/tui perf` and export Quick summary and JSON. Inspect `aggregates.elapsedWaits`: `workshop.priceWait` (usable reference), `priceSettlementWait` (includes missing), `firstColdPrice`, `tenColdPrices`, `firstVisiblePrice`, `tenVisiblePrices`, `visibleSettled`, `opportunitiesSettled`, `partitionQueueWait`, `currentValidationWait`, and `historyValidationWait`. Values are wall milliseconds; quantiles are approximate. Missing ten-row samples are expected for fewer than ten priced cohort rows.
4. Compare CPU total/worst `summaryValidate`, `historyValidate`, `pricingComplete`, estimate and render, decode starts/repeats/preemptions, completed/cancelled requests, cache/pending gauges, raw current/history bytes, decoded rows, sampled heap and addon memory. Memory-update hitches are Diagnostics' own separately reported cost. Request timers predating the capture are excluded; start before opening.
5. Close/reopen Opportunities without reload in a separate warm capture. Existing prices should be immediate with no new current decoding. Then explicitly inspect a historical chart: original points/gaps/provenance must remain, and new cold current work must proceed before optional rich validation completes. The full Opportunities UI can request an optional selected-item chart itself; zero history loading is required by the price-only path, not by every full UI capture.
6. Check hide/show, page switching, cancellation and combat interruption in ordinary safe gameplay. A pending load must postpone safely, resume once permitted, leave no stuck spinner/retry loop and retain correct prices. Repeat across a new synchronized generation and a deliberately corrupt *disposable test installation*, verifying last-good fallback. Never damage the live player's files to test refusal.

Provisional client targets: head-of-queue current validation for typical median
54 kB buckets should finish in under one second (record the 90 kB hot bucket separately); target first visible priced
row under one second and ten initially visible priced rows under two seconds in
the owner's ordinary workload. Record p50/p95/max request waits and all-visible
settlement rather than inferring them from load markers. These are acceptance
goals, not achieved results. Preserve the existing effective 2 ms validation
budget; evaluate worst callbacks and long frames against the same-client baseline.
Large-list queue waits and full redraws can miss these goals despite the much
smaller decoder workload; prioritize PR3 only from the new direct measurements.

## Remaining scope for PR3

The full-list recalculation/redraw architecture remains. The 1,000-recipe fixture
still spends material CPU recreating estimates and UI state, and its cold requests
wait behind other current buckets. Follow-up should measure visible-row priority,
completed-estimate reuse and affected-recipe updates before choosing complexity.
Do not add a general dependency engine or broad decoded cache without that
measurement. Large-client frame behavior, actual memory collection, physical-PC
permissions, long-running generation churn and the real request-latency targets
remain owner-directed acceptance. The unresolved separate Windows automatic-sync
baseline transport failure is retained as a review limitation, not a passing test.


## Verified source, failures and review order

Consumer runtime `c70566f3a83cfe9da49402b57aa4e614e3c13140` is unchanged by later
CI/helper/evidence commits. Producer runtime is
`b02a190f22fd403a35c0856dfb3c598cd0720bc7`; Companion runtime is
`39cb354e524cbc9f6d14b22d1d440e39e65e9e8f`, with native fixture/CI tooling frozen
at `0ed2edaa5d5fd03eb22501522f6e6dda4a619fa0`. Market base is `b5954ae`, addon
PR1 base is `cef81e0`. All actual benchmark report heads and helper hashes are
retained in the JSON evidence; the native reader harness was extended after the
Opportunities timing campaign without changing production code.

| Verification | Result and boundary |
|---|---|
| `./tests/run.sh development market-performance --profile cloud --jobs 2` | 8/8, 2.783 s; final runtime, 25 Lua syntax inputs |
| Fast stacked-PR CI at `5f2179d` | [passed](https://github.com/Twich-Team/TwichUI/actions/runs/44975871902); standard main-only build workflow does not trigger for the stacked base, so this small workflow supplies the existing fast group |
| `./tests/run.sh integration market --with-group crafting --profile cloud --jobs 2` | 73 offline passed; overall **FAIL** because Workshop strict simulator fails; auctionpreview passed. Precommit dirty-tree fingerprint unchanged throughout run; [complete report](../evidence/v2-market-pr2/integration-report.json) retained |
| Workshop simulator comparison | [40 identical baseline assertions](../evidence/v2-market-pr2/simulator-comparison.json) on each normal pose; negative control adds exactly its intentional wrong assertion. UTF-8 transport/voice simulator limitations retained. No assertion weakened or simulator patched |
| `bash tools/mutate.sh --group market.current --group market.pending --group market.consumption --jobs 2` | [15 killed](../evidence/v2-market-pr2/mutations.json), zero survivors/invalids/timeouts/infrastructure errors; 14 assertions and one runtime failure |
| Direct `test_diagnostics.lua` | passed after final diagnostics changes; engine/export checks are also in fast group |
| Focused producer summary + scoped Companion auth, disposable SQLite | 73 passed, four PostgreSQL-only skips; backend PostgreSQL CI separately passed |
| `cargo test --manifest-path desktop/Cargo.toml --locked --workspace --jobs 2` | Linux 139 passed, one pre-existing optional profiler ignored; final production source |
| Producer primary CI | Backend, website and Windows passed at `b02a190` |
| Companion primary CI at `0ed2eda` | [Windows/paired Lua passed](https://github.com/Twich-Team/TwichUI-Market/actions/runs/44975496335); [Backend passed](https://github.com/Twich-Team/TwichUI-Market/actions/runs/44975496290); website passed |
| Paired contract-3 pipeline | Actual authenticated synthetic API → Windows native publisher → exact Linux Lua consumer `c70566f`; 129 variants, all 64 current buckets, zero rich bytes during current queries; one rich load on explicit history. Also passed Linux staging independently. [compact CI](../evidence/v2-market-pr2/ci.json), [API/native/Lua evidence](../evidence/v2-market-pr2/api-native-lua.json) |
| Separate Windows automatic-sync performance CI | **FAIL**, including [latest 0ed2eda run](https://github.com/Twich-Team/TwichUI-Market/actions/runs/44975496301). Frozen baseline fails before candidate with `Error: Network` / Windows connection reset 10054; final request is 202/Retry-After 5, server alive/no request in flight. Other price/archive comparison stages passed. Cause remains unresolved; not reported as candidate acceptance or concealed by retry |
| Real Forever / physical owner PC | **not tested**; no game latency, taint, true frames, physical NTFS/UAC or long-running memory claim |

Exact focused producer command from Market root (test-only database):

```sh
DATABASE_URL=sqlite:// pytest backend/tests/test_workshop_summary.py backend/tests/test_companion_auth.py -q
```

The native/API fixture can be reproduced without provider access:

```sh
cargo build --manifest-path desktop/Cargo.toml --locked --example workshop_smoke
DATABASE_URL=sqlite:// python scripts/verify-workshop-e2e.py \
  --rust-client desktop/target/debug/examples/workshop_smoke \
  --addon-root /path/to/PR2-addon --current --variants 129 --out /tmp/pr2-pair
```

Review #43 first (versioned contract/sealer/routes), then #44 (paired native
validation/publication and migration), then #100 stacked on #99 (consumer and
opt-in diagnostics). #43 risks export volume/contract correctness; #44 risks
interrupted publication/platform permissions; #100 risks ingestion priority and
stale cache lifetimes. Each has focused tests and can be reviewed independently.
Do not activate only the consumer and expect cold-format benefits. Safe activation
and rollback order above are required for a coordinated follow-up. Remaining
large-list UI work belongs to a measured PR3, not this protocol migration.

No merge, deploy, signed Companion publication, addon release, live data/service
operation or SavedVariables reset was performed. Stop at draft review.
