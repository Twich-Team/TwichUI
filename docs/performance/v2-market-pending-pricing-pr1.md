# Market pending pricing remediation PR1

Implementation of [audit PR #97](https://github.com/Twich-Team/TwichUI/pull/97),
reference commit `28f5db452b60719ec3ce8e327081caaf7fb64537`.
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
when transferring a heavily requested bucket. The cached header also retains its
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

## Verification commands

```sh
./tests/run.sh development market-performance --list
./tests/run.sh development market-performance --jobs 1
./tests/run.sh development market --list
./tests/run.sh development market --jobs 2
./tests/run.sh development crafting --list
./tests/run.sh development crafting --jobs 2
bash tools/mutate.sh --group market.consumption --group market.pending --jobs 2
```

The additive fast performance group has six modules. It covers shared pending
consumers/redraws, cold/warm prices, all 64 buckets, >16 reservations per bucket,
8,192 slots, modified identities, missing prices, generation replacement mid-work,
requests while a new header validates, corrupt-part rollback, cancellation,
combat retry, stale admission, stable checked-count completion invalidation,
no-op/coalesced notifications, and one-decoder/zero-outstanding bounds. Existing
consumption tests cover local fallback/newer local scans, faction, Facts, Advisor,
UI consumers and economic isolation. Large benchmarks remain opt-in.

Native client behavior remains unverified. Do not declare the reported 5–10-second
item delay fixed from offline CPU/virtual-timer measurements. No deployment,
publication or merge is authorized. Roll back with an ordinary revert; all caches
and revisions are session-only and no saved-data migration is required.
