# Game-ready Market data investigation

Investigation only. No addon runtime, Market API, desktop application, live data,
installed AddOns, SavedVariables, release or deployment changes.

## Decision and evidence status

The supplied Forever capture establishes the remaining cold bottleneck: 8,795 ms
of current-partition validation, 4,802 callbacks, median queue wait 23.17 s and
44.91 s full settlement. The incremental engine's maximum callback was 2.21 ms;
compatible warm settlement was 6.3 ms with no new current decode. History's
2.45–2.66 s validation is a separate, acceptable on-demand operation. These are
owner-provided real-client observations, not measurements made in this workspace.

**Preferred proposal:** 16 current partitions containing sorted, fixed-width
immutable records and packed SHA-256 proof strings, with selective authentication
for sparse requests and cooperative full verification for dense requests. Keep
64 existing JSON history partitions. **Fallback:** use 32 current partitions with
the same format if native loading/GC or visible-cohort tests reject 16. Do not
activate either until the source-authentication and complete consumer tests pass.
Metadata-only trust is not a replacement for integrity verification. No production
implementation is authorized here.

## Source reconciliation

- Addon main at investigation start: `3c4c2dc5e149a35879db1a257b4ff13a83a295b0`.
- The initial ten pinned consumer campaigns and native-format Lua control ran at helper
  commit `79b62a970e2ec5d3b740383b0a180e67265c0ea6` (the experiment sources are
  hashed in each receipt). After measurement, main advanced to
  `cf188ddfa2425da4f549379aa6437ea87e2da7ee` and was reconciled into this branch
  by `8617f137d45987ace0a20a9dbf3f8ff7ae7c21d4`. Its only Session change adds
  Shopping consumer presentation in `NeededFor`; Opportunities/reader/pricing/
  estimation code is unchanged. Final fast verification uses that reconciled tree.
  The PR contains no runtime difference against this main. The final 60-day fixed
  cross-check ran at `776db4ede6ac2a8f6fc3aff6ce676e41f77a9f9d`; measured
  helper/reader hashes match the earlier campaigns. Only untimed tests/curation
  and main reconciliation changed.
- Market main: `e2882dd822b356ffa081efebbff167827f9bf364`.
- Chart UX remains separate in completed draft [#117](https://github.com/Twich-Team/TwichUI/pull/117),
  head `e5cfa5636401c2da5de01b479e15b2c82e628624`; it was not merged or copied into this branch.
- Existing [audit](v2-market-opportunities-audit.md), [PR1](v2-market-pending-pricing-pr1.md),
  [PR2](v2-market-cold-pricing-pr2.md) and [PR3](v2-opportunities-incremental-pr3.md)
  remain historical evidence at their pinned revisions.
- Market's `docs/companion-sync-performance.md` and
  `docs/companion-sync-performance-release.md` distinguish standard page/SQLite
  synchronization and automatic Workshop delivery. Their measured network retry
  and query improvements do not explain in-game partition validation. Market main
  adds the approved beta.11 release identity after the Contract 3 integration;
  this investigation makes no claim about the currently installed production binary.

## Current lifecycle and trust boundaries

| Stage | Actual work and guarantees | Allocation/repetition |
| --- | --- | --- |
| Producer `backend/market/workshop_summary.py:144,201,231` | Selects canonical current observations and real daily closings; preserves exact variants and existing reference prices; validates rows; canonical-encodes rich/current arrays; SHA-256 part descriptors; canonical manifest generation digest; bounds/whole-generation refusal. | Builds immutable exports, not prices inside the addon. No SQL/provider work was benchmarked here. |
| API `workshop_summary.py:363,388` | Device/account authorization, explicit contract negotiation, immutable generation/part routes, ETag reuse. Default remains 1; 3 is explicit. | Download and preparation are outside the in-game timer. |
| Native `desktop/core/src/workshop_summary.rs:37,97,171,216` | Manifest schema/source/account/market/timestamp binding and digest; part byte count/SHA; strict JSON/canonical equality; exact ordered identity/state/value/coverage/daily checks; history projection digest matches current. Cache resume/reuse is revalidated. | Fresh download validates each part, the completed bundle is validated again, publication validates it again, and new-bank verification validates its readback again. A rich validation parses for both the rich row checks and current projection. Branches with old/resumed data add further checks. |
| Publication `workshop_summary.rs:326,347,385` / `delivery.rs:334` | Ownership, path/symlink/unexpected-file refusal; installed capability recheck; inactive bank; atomic temp-file writes, file and directory fsync; byte readback; verified complete bank; previous root retained; root committed last. | Current and history both finish before activation. Unchanged bytes skip writes. These are essential recovery boundaries, not permission to skip later verification. |
| WoW `Summary.lua:93,182,222` | Loads only demanded addons; verifies hash, parses JSON, re-encodes canonically, validates all partition rows before any lookup; sliced coroutine, serialized queue, current before/interrupting history. History also verifies its current projection. | Raw escaped JSON remains in loaded globals; one decoded partition is retained. Crypto/parsing covers unrelated rows. Lua compilation/loading is synchronous and not made cooperative by a later validation budget. |
| Pricing/engine `Summary.lua:362`, `Pricing.lua:200`, `OpportunityEngine.lua:123` | Binary item/variant lookup; bounded 8,192-item pricing cache; full per-bucket pending demand; dependency-aware incremental calculations, estimator reuse and coalesced notifications. | The old audit's sequential lookup lead no longer describes main. This experiment keeps these production modules and their formulas. |

The current checksum is corruption detection relative to the admitted manifest,
not a digital signature or protection against an attacker who can replace the
root/addon code. Generated addon Lua already executes before the current JSON
checks. The native importer restricts that source grammar; the game cannot read
and authenticate arbitrary addon source bytes before `LoadAddOn` executes them.
Trusted atomic publication prevents partial activation at publication time; it
does not prove that files remain unchanged, prevent bank recycling while a game
is open, or make a buggy transformation correct.

The addon must still reject unsupported versions/algorithms, wrong Market/faction,
stale/unavailable sources, wrong content/generation, incomplete publication,
wrong exact identities, unsafe values and invalid integrity evidence. Full
partition traversal is not inherently necessary if requested values and misses
can be authenticated independently. Current Contract 3 cannot simply omit its
checks: that would violate its documented consumer contract.

## Candidates and authentication

1. **Existing Contract 3:** unchanged production reader at 64/64 is the control.
   Other JSON counts reuse the production row validator with only its modulo
   divisor adapted in an isolated loaded copy. They are layout experiments, not
   accepted Contract 3 manifests or production implementations.
2. **Sorted compact arrays:** emit only fixed syntax, bounded integers, hex exact
   variant keys and `false` for unavailable slots. Current arrays retain all 13
   original fields; coverage/state distinguish unavailable from genuine absence.
   Copper remains exact below 99,999,999,999 and supply below 2^53. Binary lookup
   avoids a second item-index table. Metadata plus typed validation alone is an
   explicitly weaker integrity control, not the recommended production path.
3. **Direct item/variant table:** same values, nested keyed tables. The measured
   memory advantage must justify the index; warm pricing already has a cache.
4. **Full-checksum array:** reconstruct canonical row bytes and run existing
   incremental SHA-256 after typed validation. This preserves full payload
   integrity but tests whether removing JSON parsing alone is sufficient.
5. **Selective proofs:** ordinary domain-separated SHA-256 binary trees over exact
   canonical tuples. Verify the requested row and its position against an admitted
   root. A miss verifies adjacent positions and bounds, not an unauthenticated
   search result. Root record count prevents deleted-row false misses. No custom
   crypto primitive, compression engine or general serializer is introduced.
6. **Packed proof/hybrid:** store fixed-width hexadecimal SHA words in one string
   instead of thousands of Lua string-table entries. Numeric rows remain sorted
   arrays. The hybrid uses a declared whole-workload demand hint to choose full
   checksum verification when separate proofs would cost more SHA blocks. That
   hint is test instrumentation; a future provider API must receive the engine's
   already-built dependency set. It does not replace the incremental engine.

The packed candidates bind each artifact to its content ID, not the changing
source-generation ID. The admitted root binds content IDs, counts, layout and
proof roots to a source generation. Unchanged payloads/proof strings therefore
remain byte-identical across metadata-only generations. The earlier non-packed
proof is a conservative generation-bound control, not a migration proposal.

**Authoritative roots matter.** A Companion-generated root proves consistency
with the Companion's transformed output, not independently with the server's
original SHA-bound payload. To preserve the stronger source boundary, prefer a
small authenticated immutable server attestation for the existing Contract 3
source generation and approved current layout, containing canonical payload IDs,
counts and proof roots. The server can compute it from already derived prices;
no pricing formula or historical-data migration is needed. The attestation is a
new explicitly negotiated capability/schema; do not add fields to closed v3
manifests. Its own identity binds the original generation plus roots, avoiding a
circular generation hash. Old API outputs/defaults remain unchanged. The prototype
computes these roots locally as a stand-in; that server endpoint and its end-to-end
trust linkage are **not implemented or verified** by these experiments.

A local-only attestation alternative requires an explicit owner decision to trust
the Companion's transformation as the authority. It is not silently equivalent
to the current independent game-side payload checks.

## Benchmark method

All records are fabricated from committed synthetic Contract 3 templates and pass
Market's actual producer sealer. Ordinary admission flags are used only inside
mock clients, as in the existing cold benchmarks; outer reports remain synthetic.
No live database, player records, native installation or network synchronization
is read or modified.

Main fixture: 16,384 exact variants / 14,745 items. The skew fixture includes 385
variants on one item. Stress: 32,768 variants. Both 2-day and 60-day history are
examined. The 32k stress and concentrated-variant fixtures use two days; a 32k/
60-day or skew/60-day cross-product was not measured. Remaining combinations
are not inferred from the smaller campaigns.
The deterministic 120-recipe workload has 158 distinct item questions, shared
materials and varying quantities, different outputs and genuine absent/no-price
states. The final `--native-cohort` fixture requests 58 buckets, matching the capture's
counts. The earlier exploratory control matrix used 64. Neither fixture recreates
the player's actual recipe/dependency catalog.
Larger 500/1,000/5,000-recipe sets use the same source fixtures.

`bench_market_opportunities.lua` runs the actual Session, Estimate, Pricing and
OpportunityEngine. An explicit optional hook substitutes only the file-backed
fixture/provider in a disposable Lua environment. Normal benchmark/default test
behavior stays unchanged. Each run checks economic fields, ranking/filtering and
summary against a fresh full recomputation; cross-candidate economic hashes must
agree. A new process starts each sample after one discarded warm-up; three
measured samples retain min/median/max, exact helper hashes and fixture identities.
Files are genuinely compiled with `loadfile`, executed, validated and queried.

Host: Linux x86-64, AMD EPYC 9V74, five visible CPUs, cgroup quota four CPUs and
16 GiB memory. Lua 5.1/bitop; no CPU pinning or cold filesystem-cache guarantee.
CPU uses `os.clock`; process elapsed uses Python `perf_counter`. Modeled After
callbacks wait at least one 60 Hz frame. It is a queue experiment, not the Forever
frame scheduler. Current settlement excludes already completed root admission and
module/mock setup. Loading, initialization, validation, calculation, GC and memory
are separated where measured. Sampled peak heap is a lower bound, not an exact
allocator high-water mark. Native addon discovery, Windows storage/Defender and
real frame/GC tails require the acceptance procedure below.

The production 64/64 control retains one decoded partition plus raw globals.
Prepared candidates retain loaded current tables directly (no extra copy of their
JSON strings). JSON layout models retain their decoded outputs, so their memory
is not a one-cache production prediction. Peak/generation retention must be
validated in the actual client before choosing a release budget.

Prototype authenticated-question maps grow with the measured dependency set;
they are not a new production cache-capacity design. An implementation must tie
those entries to the existing bounded price-cache lifetime or use a measured
bounded authentication representation. Dense whole-part verification can use
one generation-scoped bit/flag per physical partition. Loaded addon globals
cannot be unloaded by evicting a Lua reader cache. No all-part decoded cache is
proposed, and no unlimited authentication map should ship from this harness.

## Measurements

### Current layout: all seven counts

16,384 rows, 120 recipes / 158 questions / 58 logical buckets. Median CPU and
bracketed min–max are milliseconds. Other figures are medians; complete ranges
and sample receipts are in the evidence JSON. All fixed candidates retain the
same fields and verify integrity. Folder totals model **both** A/B banks with
equal current/history counts; measured consumer work here is current only.

| Current partitions | Equal-layout folders | JSON control CPU | Fixed adaptive CPU [range] | New current loads | Max fixed source KiB | Worst sync load ms | Retained / sampled peak MiB | First / first-10 opportunity model s | First-12 / all model s |
| ---: | ---: | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 5 | refused >1 MiB/part | 765 [758–777] | 1 | 4208 | 15.82 | 5.75 / 11.19 | 5.85 / 5.85 | 5.97 / 5.97 |
| 2 | 9 | refused >1 MiB/part | 725 [718–735] | 2 | 2104 | 8.26 | 5.76 / 11.75 | 5.53 / 5.53 | 5.65 / 5.65 |
| 4 | 17 | 3312 | 685 [676–715] | 4 | 1052 | 6.65 | 5.76 / 9.82 | 2.63 / 2.63 | 5.22 / 5.32 |
| 8 | 33 | 3387 | 640 [632–648] | 8 | 526 | 2.33 | 5.76 / 10.31 | 1.35 / 2.57 | 4.95 / 4.95 |
| 16 | 65 | 3393 | 654 [641–655] | 16 | 391 | 1.86 | 6.63 / 10.47 | 1.07 / 2.23 | 5.12 / 5.12 |
| 32 | 129 | 3407 | 584 [580–590] | 32 | 196 | 1.04 | 6.20 / 10.07 | 0.60 / 1.60 | 3.77 / 4.92 |
| 64 | 257 | 3178 | 548 [541–548] | 58 | 98 | 0.50 | 6.14 / 10.41 | 0.40 / 1.17 | 2.83 / 5.27 |

The JSON column applies the existing whole-generation bounds to both delivered
projections of the equal-count layout, even when history is not queried. At two
partitions, current alone is 933,060 bytes/part and fits, but 2-day history reaches
1,274,824 bytes and rejects the pair. This does **not** prove that a separately
versioned 2-current/64-history JSON layout is impossible. At one partition both
projections exceed the bound. The fixed columns measure current only; their unused history-count config is
not a mixed-layout integration test. The proposed 64-history component is
measured separately below. No new-format complete pipeline is implemented.

The unchanged production 64/64 control used **3,178 ms CPU [3,172–3,288]**,
3,046 ms partition validation, 22.09 ms compilation and 0.04 ms wrapper execution.
The 16-current fixed prototype used **654 ms [641–655]**: about **4.86× less CPU
(79% reduction)**. Its modeled settlement was **5.12 s versus 30.65 s**. These
are offline comparisons; neither is a prediction that native 44.91 s becomes
5.12 s. The modeled first-12 catalog cohort is not the real visible viewport.

The control loaded/validated 58 current partitions with **zero repeated decodes**, 158 cached
prices, one catalog build and 120 successful crafts. The fixed-16 path also made
120 successful crafts and one catalog build. Engine attempts (474 versus 468)
include pending states; they are not repeated successful crafting calculations.
Both made 216 reader calls and 291 price-service calls. PR1–PR3 caching works in
this workload. Enlarging the decoded-partition cache is not the leading fix.
Its raw `experiment_decodes=59` includes one fixture-metadata `ParseSummary`
call during untimed setup; it is not a 59th current partition. Prepared-format
validation jobs and JSON parser invocations are different counters.

Fixed-16 authenticated 158 questions using 1,814 SHA invocations. The principal
saving is avoiding all unrelated row parsing/canonical hashing; crypto is not
eliminated. First useful reference appeared at modeled 0.33 s versus 0.53 s,
first ten references at 0.33 s versus 2.15 s. Full opportunity progress additionally
depends on shared material availability and physical-part handoff.

Fixed-16 retained 6.63 MiB versus the production control’s 3.71 MiB, while sampled
peak fell to 10.47 MiB from 15.14 MiB. This trades about 2.9 MiB retained memory
for less transient work. Explicit end-of-run full collection cost about 9–10 ms
in either path; it is a diagnostic cost, not a proposed gameplay GC policy.
Heap-drop observations fell from 75 to 5; these are sampled decreases, not an
exact count or attribution of GC cycles.

Compatible warm settlement was about 0.05–0.07 ms offline, with zero new reader
calls/crafts and the same estimator. The service-only 1,000-price timings are
retained for inspection but include differing mock metadata adapters; use the
zero-new-work invariant rather than claiming a native warm speedup.

Fixed source size is 4.11 MiB at eight partitions, 4.98 MiB at sixteen and
4.55 MiB at thirty-two. Power-of-two proof-tree padding explains this nonmonotonic
size; fewer partitions do not necessarily mean fewer bytes. One current file
compiled/loaded in 15.82 ms median, with a 17.85 ms worst-callback median.
Two files still reached 8.26/10.28 ms. Sixteen had 1.86 ms synchronous-load
median and 3.96 ms worst-callback median; individual tails and GC require native
measurement. Eight remains credible, but sixteen halves the first reference
queue delay and leaves smaller load units for growth; the extra 16 folders versus
8/64 buy that headroom. Thirty-two is the explicit fallback if native tails or
visible priority remain unacceptable. Keeping 64 current files gains only about
0.1 s CPU here while substantially increasing folders.

### Source sizes and processing phases

Fixed-current files; CPU milliseconds are medians. Compilation includes string
creation; execution of the two-string wrapper is nearly free. Verification
includes the provider’s pricing handoff. Phase values are not a new independent
wall-clock scheduler model.

| Current count | Mean / max source KiB | Total source MiB | Compile / execute ms | Verify + handoff ms | Worst callback ms | First reference model s |
| ---: | --- | ---: | --- | ---: | ---: | ---: |
| 1 | 4208 / 4208 | 4.11 | 15.82 / 0.001 | 701 | 17.85 | 5.73 |
| 2 | 2104 / 2104 | 4.11 | 16.33 / 0.002 | 662 | 10.28 | 2.65 |
| 4 | 1052 / 1052 | 4.11 | 19.73 / 0.004 | 611 | 8.69 | 1.32 |
| 8 | 526 / 526 | 4.11 | 16.49 / 0.007 | 573 | 4.38 | 0.67 |
| 16 | 319 / 391 | 4.98 | 21.23 / 0.013 | 574 | 3.96 | 0.33 |
| 32 | 146 / 196 | 4.55 | 20.70 / 0.024 | 497 | 4.64 | 0.17 |
| 64 | 78 / 98 | 4.86 | 18.78 / 0.041 | 460 | 3.01 | 0.08 |

The full evidence inventories also retain raw canonical bytes, descriptor/source
hash inventories and maximum record counts for mixed, skewed and stress layouts.
The 60-day fixed-current cross-check used 669 ms at 16 partitions and 597 ms at
32 (120 recipes); no history addon was needed. The existing historical reference
field remains available in the current tuple. The source’s daily coverage does
not require loading its history projection for Opportunities.

### Other representations

| Current-64 representation | CPU ms | Retained MiB | Integrity interpretation |
| --- | ---: | ---: | --- |
| Production JSON | 3178 | 3.71 | Full existing checks |
| Sorted numeric arrays | 217 | 7.22 | Typed/metadata only; weaker |
| Direct item/variant tables | 221 | 8.49 | Typed/metadata only; weaker |
| Arrays plus full SHA | 3056 | 7.24 | Full payload checksum |
| Fixed records + adaptive proofs | 548 | 6.14 | Requested identities/misses authenticated |

Direct tables move JSON parsing out of game, but table initialization is
synchronous and consumes more memory. Arrays with full SHA still used about
3.06 s CPU; they do not remove the dominant work. The much faster unchecked
arrays are a negative integrity control, not a fair safe-format improvement.

### Folder and packaging decision

| Current / history | Two-bank folders including root | Interpretation |
| --- | ---: | --- |
| 64 / 64 | 257 | Existing maximum layout |
| 16 / 16 | 65 | Modeled; 60-day history exceeds the existing per-part bound |
| 8 / 32 | 81 | Modeled mixed layout; fewer files but larger current/history load units |
| 16 / 32 | 97 | Modeled; history still doubles selected-part work relative to 64 |
| 32 / 32 | 129 | Modeled; no reason to enlarge history just to match current |
| 8 / 64 | 145 | Measured components; credible lower-file alternative, less load headroom |
| **16 / 64** | **161** | Preferred components; **96 fewer folders (37.4%)** |
| 32 / 64 | 193 | Explicit fallback; 64 fewer folders (24.9%) |

These are fresh-layout targets, not measured full new-format installations.
Current and history counts can be independent if the admitted root binds their
separate descriptors to one source identity. Existing v3 manifests do not support
arbitrary counts: the prototype does not make these layouts wire-compatible.
Changing history counts requires its own versioned contract/reader change and
invalidates the proposed benefit of leaving history untouched. Static names/TOCs,
ownership markers and the inactive-bank/root-last transaction remain necessary.
Fewer folders reduce metadata operations; they do not permit partial activation.

### Dense, stress, history and publication measurements

### Dense and stress results

CPU milliseconds, median [min–max], using identical economics and source rows.
The dense path uses the actual existing engine dependency set as a test-only
hint; this API must be integrated before a production hybrid can claim these
results. All rows use the matched recipe generator.

| Source rows | Recipes | Production JSON-64 | Fixed adaptive-16 | Fixed adaptive-32 |
| ---: | ---: | --- | --- | --- |
| 16,384 | 120 | 3326 [3134–3412] | 631 [623–638] | 588 [577–608] |
| 16,384 | 500 | 3317 [3297–3355] | 2143 [2098–2170] | 1957 [1936–1998] |
| 16,384 | 1,000 | 3581 [3512–3690] | 3568 [3508–3660] | 3508 [3439–3524] |
| 16,384 | 5,000 | 5223 [5145–5306] | 5574 [5539–5612] | 5558 [5513–5632] |
| 32,768 | 120 | 6307 [6259–6401] | 661 [657–698] | 661 [624–681] |
| 32,768 | 5,000 | 8434 [8270–8462] | 9117 [8879–10770] | 9192 [9152–9231] |

For 32k rows / 120 recipes, fixed-16 uses about **9.5× less CPU** than the
production control (661 versus 6,307 ms). At 16k/5,000 recipes it is about
**7% slower** (5,574 versus 5,223 ms); at 32k/5,000 it is about **8% slower**
(9,117 versus 8,434 ms). This is a sparse-access architecture, not a universal
large-list acceleration. The adaptive check keeps the dense penalty bounded.

The selective-only negative control (`fixed-proof`, 16k/5,000, 32 partitions)
takes about **17.9 s CPU**, versus 5.56 s adaptive and 5.22 s production. Shipping
unconditional per-row proofs would be a regression. At 16k/5,000, fixed-16
retains about 59 MiB including estimator/engine/cache state; the control is also
large. Measure whole-workload memory, not only record storage.

The skew fixture puts 385 variants on item 65. Its fixed-16 CPU was 625 ms,
worst synchronous-load median 1.70 ms; fixed-8 was 674 ms / 3.51 ms. Exact-variant
lookup is binary, and variant concentration can enlarge a file despite modulo
routing. This is one documented synthetic skew, not a claim about production
distribution. Five compatible session pause/reopen cycles used 0.59 ms CPU total
with zero extra crafts or reader calls. This models engine lifecycle, not actual
native window/input behavior. Tiny deterministic tests separately cover source
replacement and stale cancellation; large generation-transition peak memory is
**not measured**.

### History is a separate decision

| Coverage | History count / representation | Selected history CPU ms | Worst sync load ms | Added retained MiB |
| --- | --- | ---: | ---: | ---: |
| 2 days | 16 / json | 475.2 | 2.36 | 0.86 |
| 2 days | 16 / array | 16.1 | 3.20 | 0.61 |
| 2 days | 64 / json | 121.6 | 0.49 | 0.16 |
| 2 days | 64 / array | 4.6 | 0.99 | 0.13 |
| 60 days | 8 / array | 304.0 | 62.97 | 17.57 |
| 60 days | 16 / array | 148.1 | 28.14 | 8.76 |
| 60 days | 32 / json | 1439.9 | 7.04 | 5.21 |
| 60 days | 32 / array | 75.6 | 14.22 | 4.37 |
| 60 days | 64 / json | 715.0 | 3.23 | 2.56 |
| 60 days | 64 / array | 39.1 | 7.47 | 2.16 |

For 60-day JSON, counts 1–16 exceed the existing 1 MiB per-part bound;
32/64 are measurable. Arrays at 1/2/4 exceed the benchmark’s 4 MiB generated-source
safety cap and were not loaded. That cap is a safety choice, **not** a discovered
Forever VM limit. The apparently fast array results omit full integrity hashing;
they are not equivalent safe replacements. Their synchronous table initialization
is substantial: 63 ms at eight history files and 28 ms at sixteen on this host.

Keeping JSON history at 64 limits selected-history work: about 715 ms CPU,
3.24 ms synchronous load and 2.56 MiB incremental retained memory at 60 days,
versus roughly twice the validation and retained bytes at 32. The supplied native
2.45–2.66 s history result remains the appropriate real-client baseline.
No history format rewrite is justified for this current-pricing investigation.

### Producer, publication and native-format control

The actual Python producer sealer (canonicalization/validation/hashing after
row construction, excluding database queries) used **1.00 s CPU [0.97–1.08]**
for 2 days and **8.42 s [8.37–8.48]** for 60 days. These costs already occur on
the server; no SQL or network improvement is claimed.

The following fresh-bank reference test includes file `fsync`, directory `fsync`,
rename and byte readback in temporary Linux directories. It writes three files
per child and a final root. It is **not** the Rust publisher, Windows/Defender,
A/B recovery, ownership validation or a full Companion sync.

| Coverage | Current/history format | Lua source MiB, one bank | Child/root writes | Reference transform CPU ms | Durable I/O ms [range] |
| --- | --- | ---: | ---: | ---: | --- |
| 2 days | 64/64 JSON | 16.86 | 385 | 610 | 296 [291–368] |
| 2 days | 8/32 fixed current / JSON history | 13.84 | 121 | 526 | 99 [95–120] |
| 2 days | 16/32 fixed current / JSON history | 14.71 | 145 | 518 | 120 [111–145] |
| 2 days | 16/64 fixed current / JSON history | 14.72 | 241 | 540 | 232 [212–278] |
| 2 days | 32/32 fixed current / JSON history | 14.28 | 193 | 529 | 172 [161–193] |
| 2 days | 32/64 fixed current / JSON history | 14.28 | 289 | 511 | 232 [232–250] |
| 60 days | 64/64 JSON | 89.45 | 385 | 3404 | 522 [516–592] |
| 60 days | 8/32 fixed current / JSON history | 86.13 | 121 | 3475 | 189 [183–209] |
| 60 days | 16/32 fixed current / JSON history | 87.01 | 145 | 3464 | 242 [239–384] |
| 60 days | 16/64 fixed current / JSON history | 87.01 | 241 | 3454 | 426 [375–451] |
| 60 days | 32/32 fixed current / JSON history | 86.57 | 193 | 3396 | 226 [223–258] |
| 60 days | 32/64 fixed current / JSON history | 86.57 | 289 | 3340 | 342 [331–364] |

For the preferred 16/64, 60-day source shrinks only from 89.45 to 87.01 MiB:
history dominates disk. Fewer writes reduce this synthetic I/O median from 522
to 426 ms, but reference transform CPU remains about 3.4 s. The helper rebuilds
history wrappers for comparison; the proposed Companion should retain unchanged
verified history bytes. Do not extrapolate this Python encoder into a native
Companion timing promise. The recommended migration preserves the existing v3
upstream current/history bytes, adds a small negotiated root attestation and
keeps ETag/resume/reuse behavior; real download latency is **not measured** here.
No network work occurs when looking up a price inside WoW.

An exact-source Linux core build of Market `e2882dd` ran the existing
`workshop_summary` native suite: **20 passed, 0 failed** (51 unrelated tests
filtered). Its `workshop_fixture` example validated the 16k/60-day bundle and
produced 128 real native-format child payloads in a disposable directory. The
unchanged production addon reader then passed three fresh samples: root compile
0.12 ms, root admission 41 ms [40–42], all-current enumeration/validation
3,389 ms [3,387–3,412], no historical bytes loaded during current enumeration,
then exactly one history addon / 714 ms [712–715] for explicit history. Its
1,000 warmed exact record/value queries used 4.74 ms [4.65–4.82]. This verifies
the existing native transport/control, **not** a new-format native publisher,
a Windows installer or Forever acceptance.

The test-only example uses bank A in a new directory. Actual atomic publication,
resume, corrupt pairs, last-good rollback, capability negotiation, unexpected
files and SavedVariables preservation are covered by the existing native unit
suite above. A future prepared-format implementation must extend those same
checks. Disk-space preflight must count the actual prepared bytes, active/inactive
banks, temporary files and preserved compatible generations; do not reuse the
legacy raw-JSON size calculation without reviewing its bound.


## Recommendation and quantitative acceptance proposal

Keep the public current/history separation and the incremental engine. Move full
source validation, deterministic encoding and proof construction outside WoW.
WoW should admit bounded root metadata, load compact immutable current strings,
authenticate only requested exact identities (including genuine misses), then
use the existing price cache. For dense demand, a single cooperative canonical
checksum is cheaper than thousands of independent proof paths. Do not increase
the frame budget to hide repeated work.

Rank the practical choices:

1. **16 fixed-record current / 64 unchanged JSON history**, with authoritative
   content roots, selective/dense verification and per-item visible priority.
   This is the preferred implementation experiment, subject to native load/GC
   acceptance. It removes current JSON parsing and unrelated-row validation
   without dropping integrity checks. The fixed record is a narrow schema over
   the existing 13 fields; the proof tree is the principal added complexity.
2. **32 fixed-record current / 64 unchanged history** if the 16-part native tail
   or visible priority fails. More files buy smaller synchronous loads. Keep the
   choice a negotiated layout, not two permanent competing reader architectures.
3. **Keep current Contract 3** if neither can meet correctness, memory or native
   frame limits. Prepared tables with full-part hashing do not justify a format
   migration on these results. Metadata-only arrays are fast but weaken the
   stated corruption guarantee; they are not the safe fallback.

Do not reduce history to 16/32 just for folder count: 60-day partitions get
larger, and existing history integrity/projection checks are useful. Likewise,
one giant current file is measurable but produces a synchronous load tail and
holds the first result behind more work. A direct nested index adds retained
tables while the existing warm price cache already serves repeated questions.

These are **future acceptance targets**, not demonstrated native results:

- On the supplied 120-recipe scenario, aim for current preparation CPU at most
  2 s (versus 8.795 s native baseline), initial visible settlement at most 3 s
  (versus 7.96 s) and total at most 10 s (versus 44.91 s). Measure three matched
  trials; preserve first/first-10 progress, not only the final number.
- Preserve compatible warm settlement at or below 10 ms, zero new current
  authentication/loads and no completed-recipe recalculation. Do not treat
  Linux microseconds as a Forever guarantee.
- Keep cooperative data work around the existing 2 ms target, coordinate with
  history, and require native synchronous current loads below 8 ms at the 95th
  percentile. Report every tail above a frame; no hard guarantee follows from
  cooperative code because compilation and GC are synchronous.
- Use the measured whole-workload memory baselines to set a native budget;
  provisionally keep the 16k/120 current path below 16 MiB sampled incremental
  heap, including pricing/engine state. Measure generation transitions separately;
  a two-bank disk layout does not imply two decoded banks must stay in memory.
- No incorrect fields/ranks, unsupported zero prices, unauthenticated false
  misses, partial activation, extra warm decode or unbounded retry. Large dense
  workloads must not regress CPU more than 15% against the matched control;
  if they do, revise the verification choice before shipping.

The prototype's physical-part completion gate is a known limitation: it does
**not** prove the visible target. Implementation PR3 below must expose the
existing dependency/viewport priority to authentication and release each ready
question without invalidating unrelated reservations. This is required before
using the smaller current layout in production.

## Proposed implementation PRs (approval required)

| PR | Files/repository | Benefit, gate and dependency | Risk and rollback |
| --- | --- | --- | --- |
| 1. Authentication contract and vectors | Market: new explicitly negotiated current-attestation contract, `backend/market/workshop_summary.py`, focused producer tests | Server roots/counts/content IDs refer to the immutable existing v3 generation and exact 13-column tuples. Preserve current routes/defaults, formulas, authorization and immutable generations. Include membership, neighboring-position nonmembership, empty buckets, duplicates, maximum values, wrong market/source and changed metadata vectors. | No client activation. Keep the endpoint/capability opt-in; withdraw it without changing v1–v3 exports. A locally computed root is not independent server authentication. |
| 2. Native preprocessing/publication | Market: `desktop/core/src/workshop_summary.rs`, installation/capability handling and existing native publisher tests; a narrow encoder module if warranted | Validate the entire upstream bundle as today, validate server attestation, generate deterministic owned current artifacts, preserve existing history bytes, read back and commit one inactive bank/root last. Require exact-source Windows validation and capability negotiation before release. Depends on 1. | Strict literal grammar, integer bounds and exact byte readback; never execute Lua to inspect it. Preserve ownership/unexpected-file refusal, file/directory durability, source cache, previous compatible bundle and updater trust. No signing/version selection/publication in this audit. |
| 3. Current-provider adapter and notifications | TwichUI: proposed new current-reader module, Bridge/Pricing dispatch and a narrow dependency/viewport handoff from the existing engine | Small bounded metadata admission, fixed offsets/binary lookup, selective proofs and cooperative dense verification. Existing Estimate formulas, incremental results, price cache and history reader remain. Root admission binds both projections to one source generation. Add per-item readiness without releasing unrelated pending reservations. Depends on 1/2 fixtures. | The prototype currently merges work behind physical-part completion. Shipping requires cohort-aware proof order and granular ready events, not a larger frame budget. Preserve legacy readers and source/failure invalidation. Reject once, cancel stale tokens, retain last good; no infinite retries. |
| 4. Paired integration/migration acceptance | Both repos: existing native publication/consumer integration, generation fixtures, release checks and opt-in diagnostics | Backend v3 + authoritative attestation → native download/validate/encode → disposable A/B installation → actual addon reader → all price/Opportunities/history checks. Test every supported old/new component pairing, upgrades/downgrades, interrupted writes, unchanged reuse and file ownership. Then owner-directed native acceptance. | Keep new publication disabled until the entire pipeline passes. Roll back through verified compatible bundles and an inactive bank; never manually mix or rename bank files. Reverting an addon alone does not convert an installed new-format root. |

Do not replace PR3's engine. It already has dependency edges and visible/default
cohort priority. Expose that demand to the provider; verify visible questions
before background questions even when they share a physical file. A data worker
must coordinate its budget/priority with the existing history worker: two separate
2 ms workers do not imply a 2 ms aggregate budget. Preserve current-over-history
priority, park/cancel ownership and coalesced redraws. Fast tests must exercise
reservation leases and partial readiness, not just a happy-path final price.

History can retain the original source manifest's modulo-64 descriptors and
current-projection digest check without installing its old current JSON files.
The new current provider must also preserve `Record`, `Value`, `Availability`,
variant/range enumeration and capped full enumeration behavior for other Market
consumers. The prototype is a current-price adapter, not a complete replacement
for those public APIs or a production activation/recovery state machine.

## Compatibility, publication and recovery requirements

- Keep public Contract 3 as the source and old formats readable. Negotiate a
  distinct local prepared-data capability; do not reinterpret `summary_current_contract=3`
  or silently add fields to closed schemas. An older Companion must keep its
  supported legacy output when paired with a newer addon; an older backend must
  lead to explicit legacy fallback, not a polling loop or an invented speed claim.
- The existing capability reader at Market `installation.rs:420` returns 3 only
  for the explicit current/history bounds. Inspection of beta.10's `be09ff9`
  source confirms that it sees the current addon's `history_contract=2` and
  chooses legacy 2, ignoring the additive current capability. A new addon with
  that older Companion remains usable without the Contract 3 speed benefit.
  Future prepared-format tests must include actual older binaries/source snapshots.
- Source generation, attestation identity, encoding/layout version, Market/issuer,
  content IDs, record counts and active bank must all agree. Reusing identical
  immutable content under a new source generation is safe only through that new
  root's verified descriptors. Scope/account ownership remains isolated.
- Preserve current freshness/faction admission and the limited-reference quality
  ceiling. A missing member proof means not included/unavailable; only an
  authenticated absent-state row means observed absence. Neither becomes zero.
- Preserve root-last publication, interrupted-bank refusal and previous compatible
  generations. A/B reuse while a game is open must fail safely on changed content
  and offer existing reload guidance; `LoadAddOn` is not an unload/reload API.
- Save and regenerate a fully compatible legacy bank before an addon/Companion
  downgrade. Verify it completely before the root flip. A historical Previous.lua
  pointer alone is insufficient if its bank has subsequently been recycled.
- Fresh-layout folder totals are maximum target layouts, not a promise that an
  existing installation immediately loses old folders. Retire only owned,
  unreferenced files after compatible rollback is secured. Preserve unknown files,
  user data, SavedVariables, accounts, credentials, history and signed releases.

## Fast checks and dedicated campaigns

`test_market_game_ready.py` belongs to the existing fast `market-performance`
group. It tests source-injection refusal, portable exact-number decoding,
variants/misses, unknown versus absence, warm authentication reuse, corruption,
false misses/truncation, cancellation, source replacement and unchanged bytes.
It uses tiny temporary synthetic data and no Market database. It does not run
large generators or performance campaigns.

For an implemented protocol, extend the existing four-tier strategy rather than
creating a second runner:

1. Development/PR: `./tests/run.sh development market-performance`; deterministic
   operation counts, cache/queue bounds, exact prices and finite cancellation.
   Add canonical/proof vectors and reservation/cohort tests here. Keep additional
   performance-specific work comfortably below 30–60 seconds.
2. Dedicated benchmark: the explicit commands below; discarded warm-up, three
   fresh Lua processes, host identity, same source/data and min/median/max. Retain
   the whole failed receipt if a case fails. No fragile CI millisecond threshold.
3. Market integration: existing producer/native/addon paired fixtures, supported
   schema/consumer combinations, authenticated source identity, corrupt/missing
   partitions, interrupted atomic publication, last-good recovery and exact
   field/profit/history results. Run separately from routine development.
4. Scheduled/release stress: 32k and contract-bound datasets, 1,000/5,000 recipes,
   repeated generations and long lifecycle/memory pressure. Test larger record
   counts only when their existing whole-generation byte limits permit them.
   Preserve full release gates; never silently suppress existing simulator failures.

Store curated baselines under `docs/evidence/market-game-ready/` with commands,
fixture semantic/source IDs, tool hashes, source revisions and raw sample ranges.
A baseline update is an explicit reviewed PR explaining the changed inputs or
implementation; a slower new host is not an automatic product regression.
Select this fast group for these tools/provider/codec changes. Select existing
Market/native integration for protocol/publication changes and Workshop/chart
feature coverage when real runtime/UI integration is implemented. No simulator
campaign is needed to validate documentation and isolated benchmark tooling.

## Minimal future Forever acceptance

This is an owner-directed test plan after an implementation is approved, not an
instruction to change the current installation or deploy anything now.

1. Use a separate test installation/profile through the existing approved
   Companion test-publication workflow. Use one fresh source generation for both
   controls and record its identity. Never turn synthetic flags off in the live
   addon to make fabricated prices eligible.
2. Verify the signed/test build and source/attestation/active-bank identities.
   Start a fresh Lua session (`/reload` only when safe) for each cold run; merely
   closing Workshop is a warm test. Run three matched legacy/candidate trials on
   the same source, hardware, UI scale, viewport and recipe set.
3. Open `/tui perf`, select Workshop diagnostics and start a capture. Open
   Opportunities, keep the initial viewport fixed, wait until settlement, stop
   and export. Collect first useful price, first 10, actual initial-visible
   completion and total; current loads, verified records/proof hashes/bulk jobs,
   queue wait, total/worst callback, and retained/peak memory. Add opt-in scopes
   for the new work in implementation; no always-on polling or heavyweight
   memory traversal. Native `LoadAddOn` timing includes compilation/execution;
   do not claim the API separates them like offline `loadfile` does.
4. Close/reopen without reloading. Expect zero new current loads/proofs and no
   compatible crafting recalculation. Check sort/filter/profit/variant results
   against the legacy control. Request history separately; it must remain lazy,
   interactive and correctly sourced, with the chart UX refinement retained.
5. Rapidly switch selections, hide/reopen while pending and exercise a test-only
   interrupted/corrupt replacement plus a metadata-only unchanged generation.
   Old callbacks must not publish new-context results. Incomplete banks never
   activate, unknown prices stay unknown and compatible rollback remains usable.
6. Judge real frame and GC tails before choosing 16 versus 32 current files.
   The offline model cannot certify responsiveness during combat, addon discovery,
   Windows storage/Defender costs, bank recycling or actual player viewport timing.

## Remaining unknowns

- Actual native CPU/latency/GC after the new format; the supplied capture is the
  current implementation, not acceptance of these prototypes.
- Real Market record/variant distribution and future growth beyond the fabricated
  16k/32k distributions. No confidential records were requested or used.
- Contract-bound 150k-row memory is not certified. A roughly balanced 16-part
  fixed layout would retain about 19.3 MiB of tuple bytes plus about 32 MiB of
  hex proof nodes from power-of-two padding, before engine/cache overhead. This
  is a size estimate, not a measured peak or approval of a 51 MiB current provider.
  An implementation needs explicit total/source/row bounds and a native memory
  gate; reject an oversized whole generation and retain last good rather than
  silently pruning variants. Do not extrapolate the 16k result to every allowed
  Contract 3 generation.
- A reviewed authoritative attestation schema/endpoint, native encoder, activation
  adapter, complete Bridge API compatibility and Windows release verification.
- Aggregate current/history scheduling and granular reservation notifications;
  the prototype exposes this design gap rather than proving it solved.
- Real installed-addon compilation limits/discovery costs and memory under other
  addons. Native mutable-table ownership and loaded-addon lifetime need explicit
  handling; packed immutable strings simplify that lifetime but do not remove it.
- Full native publication and recovery of a new local format. Filesystem timings
  alone do not validate a Companion publisher or a valid game consumer.

## Generated-source safety and the fixed-record experiment

The table results justified testing a narrower representation: a **135-character
fixed-width current tuple** plus a fixed-width SHA proof string. This is a small
experimental record layout, not a general serialization/compression framework.
It requires a reviewed schema before implementation.

| Existing columns | Width / encoding |
| --- | --- |
| Item ID / exact variant hash | 8 hex characters / 64 lowercase hex characters |
| State | 1 hex character |
| Recent / Market / minimum / historical reference | 10 hex characters each |
| Supply | 14 hex characters, bounded to 2^53−1 |
| Bound age / confidence | 1 character each; existing age binding remains zero |
| 14-day / 60-day priced / observed counts | 2 characters each |

Unavailable slots use all `z` characters, never numeric zero. The generator
accepts only verified typed values and emits a fixed template with controlled
numeric/hex atoms. It cannot splice input into identifiers, expressions, statements,
filenames or TOC fields. Arbitrary strings and malformed numbers are rejected.
The native implementation must use the same tight constraints and compare exact
readback bytes or deterministic regenerated artifacts; it must never execute
untrusted Lua to inspect it.

The addon reads two immutable strings and uses fixed offsets/binary search,
materializing only queried rows through its existing bounded pricing cache.
Proof admission and bulk verification remain cooperative. This avoids building
thousands of current-record tables on a synchronous addon load. No `string.unpack`,
FFI, new compression library or non-Forever API is needed.

Base-16 conversion uses at most seven hex digits at a time, then combines exact
numbers. This avoids assuming Lua 5.1's base conversion uses a 64-bit C unsigned
long on Windows. Fast tests cover 99,999,999,999 copper and 2^53−1 supply under an
emulated 32-bit base-conversion bound. Actual Windows/Forever verification is still
required. Source safety does not make arbitrary on-disk Lua safe against execution;
that remains the installation/OS trust boundary described above.


## Reproduce the isolated experiments

Check out the pinned addon/Market revisions in disposable worktrees. Use the
project's Lua 5.1 + bitop environment and the existing Market backend Python
environment (its dependencies are needed for the production sealer). Set
`MARKET_ROOT` to that read-only source checkout and `MARKET_PY` to its Python
executable; the following never connects to a database. Generated fixtures and
large raw receipts stay outside Git. Do not point any output at a game install.

```bash
# From the addon investigation checkout, with lua5.1 available.
: "${MARKET_ROOT:?Set the pinned Market source checkout}"
: "${MARKET_PY:?Set the backend environment Python executable}"
RUN=$(mktemp -d)
FIXTURES="$RUN/fixtures"
RESULTS="$RUN/results"
mkdir -p "$FIXTURES" "$RESULTS"
for spec in mixed:2:16384 mixed:60:16384 skew:2:16384 stress:2:32768; do
  IFS=: read -r profile days records <<< "$spec"
  actual_profile="$profile"
  if [ "$profile" = stress ]; then actual_profile=mixed; fi
  DATABASE_URL=sqlite:// "$MARKET_PY" tools/experiments/market_game_ready.py \
    --market-root "$MARKET_ROOT" --out "$FIXTURES/$profile-$days" \
    --records "$records" --days "$days" --profile "$actual_profile"
done

M=tools/experiments/measure_game_ready.py
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-matrix.json" \
  --recipes 120 --counts 1 2 4 8 16 32 64 \
  --representations json array index verified-array fixed-hybrid --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-control.json" \
  --recipes 120 500 1000 5000 --counts 64 --representations json --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-dense.json" \
  --recipes 120 500 1000 5000 --counts 16 32 --representations fixed-hybrid --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/stress-2" --report "$RESULTS/pinned-stress-control.json" \
  --recipes 120 5000 --counts 64 --representations json --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/stress-2" --report "$RESULTS/pinned-stress.json" \
  --recipes 120 5000 --counts 16 32 --representations fixed-hybrid --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-proof-negative.json" \
  --recipes 5000 --counts 32 --representations fixed-proof --native-cohort --reps 2
python3 "$M" --fixture "$FIXTURES/mixed-60" --report "$RESULTS/pinned-history60.json" \
  --recipes 120 --counts 1 2 4 8 16 32 64 --representations json array --history --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-history2.json" \
  --recipes 120 --counts 16 64 --representations json array --history --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/skew-2" --report "$RESULTS/pinned-skew.json" \
  --recipes 120 --counts 8 16 32 64 --representations fixed-hybrid --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-2" --report "$RESULTS/pinned-reopen.json" \
  --recipes 120 --counts 16 --representations fixed-hybrid --scenario reopen --native-cohort --reps 3
python3 "$M" --fixture "$FIXTURES/mixed-60" --report "$RESULTS/pinned-current60.json" \
  --recipes 120 --counts 16 32 --representations fixed-hybrid --native-cohort --reps 3
for days in 2 60; do
  if [ "$days" = 2 ]; then label=two; else label=sixty; fi
  DATABASE_URL=sqlite:// "$MARKET_PY" tools/experiments/measure_game_ready_stages.py \
    --market-root "$MARKET_ROOT" --fixture "$FIXTURES/mixed-$days" \
    --report "$RESULTS/stages-$label.json" --reps 3
done
```

These are deliberately explicit on-demand campaigns, not one normal CI command.
A report is final only with `source_unchanged` and `economic_results_equal` true.
The curator additionally compares economic hashes across matching campaigns.
One interrupted aggregation run exposed a sparse-counter receipt bug (zero
operation counts were omitted); it was preserved, fixed and covered by a fast
unit guard before the pinned campaigns. It was not counted as a product pass.

The existing benchmark's normal oracle still compares every final economic
field, filtered order and summary with fresh recomputation. The campaign's
`BENCH_ORACLE_SNAPSHOT` option exports the exact same snapshot and computes its
report digest in Python outside workload timing. It does not replace the actual
Lua SHA used by the reader/proofs. A unit guard proves digest equality with the
default Lua oracle. This keeps large stress verification practical without
changing pricing or hiding oracle work inside a claimed improvement.

### Native-format control, without publication

The existing Rust example validates and generates **synthetic** transport in a
new directory. It is not the production A/B publisher, a Companion installer or
a live server request. `--offline` was used with the already available dependency
cache; omit it only when intentionally obtaining the locked dependencies.

```bash
export CARGO_TARGET_DIR="$RUN/native-target"
cargo build --locked --offline --manifest-path "$MARKET_ROOT/desktop/core/Cargo.toml" \
  --example workshop_fixture -j 2
cargo test --locked --offline --manifest-path "$MARKET_ROOT/desktop/core/Cargo.toml" \
  --lib workshop_summary -j 2
python3 - "$FIXTURES/mixed-60/upstream.json" "$RUN/native-input.json" <<'PYINPUT'
import hashlib, json, sys
from pathlib import Path
f = json.loads(Path(sys.argv[1]).read_text())
h = f['manifest']
h['synthetic'] = True
h.pop('generation_id')
h['generation_id'] = hashlib.sha256(json.dumps(h, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
Path(sys.argv[2]).write_text(json.dumps(f, separators=(',', ':')))
PYINPUT
"$CARGO_TARGET_DIR/debug/examples/workshop_fixture" "$RUN/native-input.json" "$RUN/native-artifact"
WORKSHOP_SUMMARY_EXPECTED_ITEM=2589 WORKSHOP_SUMMARY_EXPECTED_RECENT=1595 \
  python3 tools/measure_scoped_reader.py --summary-root "$RUN/native-artifact" \
    --report "$RESULTS/native-contract3.json" --reps 3
./tests/run.sh development market-performance
```

Do not install these fabricated prices in the client. Changing `synthetic` above
only satisfies the example's explicit synthetic-input guard; it does not grant
ordinary in-game pricing eligibility. The generated manifest identity is therefore
different from the ordinary-admission mock fixture while the part bytes agree.


## Verification and evidence index

- [Curated campaigns and fixture inventories](../evidence/market-game-ready/results.json):
  **11 campaigns, 69 measured cases**, 10 explicitly refused/not-loaded cases,
  one discarded warm-up per measured case, 206 measured Lua processes. The
  selective-only negative control has two measured repetitions; other cases have
  three. All completed receipts pass source stability and economic equality;
  the curator also verifies equality across matching campaigns.
- [Fast verification receipt](../evidence/market-game-ready/development-verification.json):
  `./tests/run.sh development market-performance --jobs 2`: **13 passed, zero
  failed, 9.829 s**. The new module's ten methods took 3.565 s, including fixed
  unavailable-state, content reuse, corruption and generation/cancellation checks.
  Existing pricing/reference, pending, engine and Window lifecycle modules pass.
  Syntax and explicit edited-Lua compilation pass; Python tools compile.
- [Native-format control](../evidence/market-game-ready/native-contract3.json) and
  [verification scope/host](../evidence/market-game-ready/verification.json):
  existing native core suite **20 passed**, and actual native-generated data
  consumed by the production Lua reader. No new-format publisher is claimed.
- [Two-day stages](../evidence/market-game-ready/stages-two.json) and
  [60-day stages](../evidence/market-game-ready/stages-sixty.json): actual producer
  sealing plus reference transformation and disposable durable I/O; not network
  or native Companion publication measurements.
- [Interrupted tooling run](../evidence/market-game-ready/interrupted-run.json):
  receipt-aggregation failure and exact repair commit/test. No failed run is
  presented as a passing product benchmark. Large generated files and original
  raw receipts remain in disposable workspace storage, outside the PR; curated
  sample values, min/median/max, semantic identities and source inventories are
  committed for review.

No selected verification failed. This is not full/release certification: unrelated
simulator catalogs, production mutation campaigns, Windows installation/signing,
new-format activation and real Forever acceptance were not run. Main's runtime
folders have zero diff in this investigation; the Market checkout remains clean.
The PR workflow additionally selects this same fast group for experiment-tool
changes. Large generation/benchmark commands remain explicit opt-in operations.

## Owner summary

Cold Opportunities loading is slow because the game verifies thousands of
unrequested records before returning a handful of prices. PR1–PR3's cache and
incremental calculation behavior works in the matched workload. More redraw or
frame budget is not the remedy.

The Companion can do full validation and prepare compact immutable prices. WoW
still needs version/source/freshness checks and integrity for the prices it uses;
trusted publication alone does not detect later corruption or prove a correct
transformation. Selective authentication preserves that boundary without
processing every unrelated row. Simply emitting Lua tables and retaining full
partition SHA work does not materially solve the bottleneck.

Start with **16 current / 64 history**, **161 target folders** across both banks
and root, with 32 current as the native-tail fallback. Keep the existing history
format and incremental engine. The sparse 120-recipe prototype cuts offline CPU
about 79% at 16k rows and about 90% at 32k rows, with roughly 3–5 MiB more retained
memory than the corresponding control. It does not demonstrate a native 45-to-5
second guarantee; visible-priority handoff remains an implementation requirement,
and dense 5,000-recipe CPU is slightly worse.

The server needs a narrow explicitly negotiated authoritative current-attestation
capability over existing immutable exports. The Companion needs a strict typed
encoder, exact readback and compatible A/B publication. The addon needs a
current-provider adapter with bounded cooperative verification and ready-item
notifications. Existing formulas, data collection, public v3 exports, history,
accounts and SavedVariables stay intact. Implement only through the four small
coordinated PRs above after owner approval. This investigation stops here; no
production format, deployment, release, signing or merge to main is authorized by it.
