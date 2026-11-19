# Item Advisor sorting performance

Baseline `518145dee3d887e2553f89a7053dc2052e8c8972`: PR #38 passed CI,
changed only its audit report and merged normally. Publication remains disabled.

## Finding and change

**Offline-measured:** final native sorting dominated the longest catalog callback
at 20,000 items. Discovery/metadata still dominate cumulative catalog CPU; sorting
is a responsiveness issue, not most of the total work. The view's result-list
update was about 1 ms on recording frames; actual client rendering is unmeasured.
Category preparation, filtering and detail painting remain outside this change.

Only `TwichUI_Workshop/AdvisorData.lua:D.Catalog` changes in production. At up to
4,096 rows it retains the native sort. Larger catalogs sort bounded runs, then
merge them cooperatively using the same approach already present in BrowseData.
A single reusable run and a transient O(n) scratch table retain original row
objects. Numeric item IDs are unique through the existing byID deduplication, so
there is no tie-order change. Metadata, eligibility, prices, search, view code,
selection and viewport behavior are unchanged. Existing view tokens can discard
a sort between slices; results publish only after finalization completes.
Existing `workshop.advisor` Diagnostics scope already includes every sort step;
no new profiler, scheduler, API, cache or persistent state is introduced.

## Controlled comparison

[Recorded samples and identities](../evidence/advisor-performance.json).
Five fresh-process pairs per size, alternating before/after order, same Lua 5.1,
fixture, machine and unchanged addon sources except AdvisorData. Shared recording
fixture uses deterministic noncontiguous item IDs and twelve categories. The large
size matches the existing Advisor 20,002-identity regression, not a new capacity
claim. All results are checked for exact count and ascending IDs on every run.

Values below are medians of five samples. Durations are **offline CPU**, including
observer overhead. Total is summed timed callbacks; timer waiting, fixture setup
and native rendering are excluded. This is not elapsed Forever completion time.

| Items / measurement | Before | After |
|---|---:|---:|
| 1,000: total CPU | 8.671 ms | 9.519 ms |
| 1,000: longest callback | 1.282 ms | 1.392 ms |
| 20,000: total CPU | 201.051 ms | 200.419 ms |
| 20,000: longest catalog step | 14.602 ms | 3.720 ms |
| 20,000: longest callback across full view preparation | 15.257 ms | 10.859 ms |
| 20,000: worst observed callback across all five runs | 21.667 ms | 14.206 ms |
| 20,000: scheduled/immediate callbacks | 375 | 409 |
| 20,000: sampled peak heap increase | 28,671.3 KiB | 29,250.2 KiB |
| 20,000: retained increase after completion / after release | 27,086.4 / 257.7 KiB | 27,086.4 / 257.7 KiB |

Median longest catalog step decreases **74.5%**; full-view maximum-callback median
falls **28.8%**. No total-CPU speedup is established: 20,000-item totals range
179–272 ms before and 189–222 ms after. The ordinary-size ~0.85 ms median increase
has overlapping ranges; no ordinary-size benefit is claimed. The responsiveness
tradeoff is **34 additional callbacks (9.1%)** and **578.9 KiB** additional sampled
peak heap. Sampling occurs after callbacks; this is not an exact allocation peak.
Retained/released deltas are measured after comparable collections and remain
stable across repeat runs. Production GC behavior is untouched.

Remaining long callbacks include view finalization/GC; this is not a universal
frame-time bound. A smaller 2,048-row trial scheduled 463 callbacks; it was rejected
in favor of fewer extra scheduling turns. Exploratory fixture/setup errors were excluded from performance results; the
2,048-row trial is retained under `test-output/advisor-performance/`.

Reproduce from the repository's activated environment, using the same test fixture
with each frozen source root. From `tests/`:

```sh
lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' bench_advisor.lua 20000 1
```

For baseline comparisons, set ROOT/REPO to a separate baseline checkout with the
recorded production file hashes, retaining the candidate TESTS fixture. Repeat
five independent processes in alternating order for 1,000 and 20,000 items.
The benchmark is opt-in; it is not discovered by the offline runner.

## Verification and acceptance

- Lua 5.1 syntax and `development item-advisor`: three modules passed.
- `feature item-advisor --profile cloud`: all 60 selected offline modules and
  syntax passed on `85647d9`; aggregate failed when the outer sandbox denied
  Bubblewrap UID mapping, before all 12 native launches could execute.
- A documented elevated retry of **only** those twelve Workshop poses passed
  with known simulator limitations, including all existing common-check replay
  comparisons and the deliberate wrong-expectation control. The failed aggregate
  remains failed; no offline rerun or fabricated replacement report was needed.
- `market.advisor` mutation campaign: 13/13 killed, no survivor, invalid mutation,
  timeout or infrastructure failure. Includes new reversed-run and lost-tail
  defects. Seeded numeric-reference cases cover empty/single catalogs, run
  boundaries and non-power-of-two tails, row identity and metadata. Handler tests
  interrupt a sort on hide, catalog replacement and suspension, then drain stale
  callbacks and assert that no results return. Existing scroll/selection and
  filter tests remain unchanged.

Cloud captures validate handler/structural behavior, not actual fonts, pointer
input or native 20k-item frame latency. The modified sort remains covered by the
existing `workshop.advisor` scope; no Diagnostics registration change is needed.

No full/release certification, native appearance review or Forever test is claimed.
Before promoting this draft, compare real-client 1k/20k first-open and repeated
search latency, per-frame p95/max, total completion wall time and memory; include
hide, suspension, source replacement, rapid filter changes and scrolled selection.
The extra callbacks could increase completion wall time despite unchanged CPU;
accept only with the demonstrated frame-time benefit and acceptable wall time.
No Market/bridge/pricing/transaction/schema or release workflow changes.

Deferred: category preparation, paint changes and tooltip indexing. Rollback the
single catalog sorting change if client acceptance fails; no saved data migration
or package rollback is needed. The draft must remain unmerged pending review.
