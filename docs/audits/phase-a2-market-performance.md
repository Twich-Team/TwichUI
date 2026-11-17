# Phase A2 — Market performance

Investigation baseline: `cdd873a951ebc034b2fac5ad05e556bfd710926c` (main).
Evidence: **unit-tested/offline measured**; source inspection is identified below.
**No new simulator, screenshot or real-client performance acceptance.**

## Executive summary

- [PR #34](https://github.com/Twich-Team/TwichUI/pull/34) was already normally merged
  as the baseline above. Its final `verify` check succeeded; the `internal` job
  was skipped. Reviewed instruction consolidation, navigation/evidence docs and
  the privacy-policy test adjustment; no runtime or release-policy changes.
  `.github/release-policy.json` still has `publication_enabled=false`.
- Hashing is the largest confirmed offline CPU contributor. Schema traversal is
  small by comparison. Assignment is negligible; compilation is separate and
  synchronous. This does **not** establish the cost on Forever's interpreter.
- Small cases still exceed the nominal 3 ms validation-slice target. Dense 100
  is prepared, **not newly benchmarked**: smaller cases have no client acceptance.
  No safe native operating limit or demonstrated game lag can be claimed.
- Keep delivery manual and experimental. Next task: run the bounded client
  procedure below. No production optimization, GC tuning or limit change is justified yet.

## Evidence and reproduction

The [L3 report](../workshop/market-bridge-scoped-l3.md#targeted-synthetic-loading-evidence)
already measured dense 100 at median **8.702 s validation CPU / 4,174 slices**,
with a 7.76 ms median largest slice. Its 155-variant stress case reached **69.08 ms**;
an exploratory small case reached 86.5 ms. These remain historical offline
observations, not discarded outliers and not newly repeated here.

New runs: x86_64 Cloud, Lua 5.1.5 + bit, Python 3.12.14, `os.clock` CPU time,
normal global GC. No simulator ran concurrently. The new small harness reuses
Bridge counters, schema/codec functions and existing Market mocks. Separate
component passes omit yields to identify costs; they are diagnostic timings,
not proposed runtime scheduling. One diagnostic sample per case, plus one final
10-dense smoke after fixing export/install-fixture plumbing: **no five-sample
comparison, speedup, or portable timing bound**.

```sh
source /workspace/twichui-env/activate.sh  # this Cloud environment only
python3 tools/measure_scoped_reader.py --startup-only --report /tmp/market-a2-startup.json
python3 tools/measure_market_a2.py --case 10-dense --measure
python3 tools/measure_market_a2.py --case 100-sparse --measure
python3 tools/measure_market_a2.py --case 100-dense  # prepare only; defer measurement
```

Output defaults to ignored `test-output/market-a2/<case>/`: trusted synthetic
`TwichUI_MarketData/`, optional `TwichUI_MarketAuditCorrupt/`, `fixture.json`, and
when measured, `report.json`/`console.txt`. Nothing is installed. Each report pins
the generation, artifact SHA-256, fixture hash, source revision and six reader
source hashes. `--out` accepts only repository test-output or `/tmp`. No separate
Market checkout is needed or modified. Do not point it at game files.

Fixture: cloned/resealed pinned `scoped.json`, one exact variant per item starting
at 10001, price 100 copper, window **2026-09-17 through 2026-11-15 UTC**. Dense
means 60 complete closes; sparse means days 0/20/40/59, with explicit missing
dates. No distributions. Synthetic mapping remains unverified. Mirror manifest
SHA-256: `c5a465e323005735444f3e5fe2ec48241f50942ebdfb7e7078049849206ec2a7`;
input `scoped.json`: `bc40b8b8a4d81bc66df53600c8bbc23998730284224ecc684fe62f8d83016811`.
These resealed fixtures differ from historical producer fixtures: **do not infer
a performance improvement by comparing their numbers**.

| Case | Generation ID | Canonical / Lua bytes |
|---|---|---:|
| 10 dense | `e1931135f75d837efd1aa0bc34dbf75d230eadc0d49107e63796fadbd0261267` | 159,312 / 222,424 |
| 100 sparse | `9cf501ed422390a27205c2728862c79b3164c4de096be0c777edd78068a440ad` | 182,017 / 249,125 |
| 100 dense, preparation only | `c6ab796c11031b84baa5cd0b3e736dded6111cc05cc674139fde8b423014afe3` | 1,298,175 / 1,842,067 |

## Newly measured results

All times below are **offline ms**, not game frames or timer-driven completion wall time.

| Measurement | 10 dense | 100 sparse |
|---|---:|---:|
| Compile / assignment | 0.852 / 0.001 | 0.611 / 0.001 |
| Compile + assignment + validation-loop CPU, including harness bookkeeping | 521.830 | 555.608 |
| Bridge validation CPU / slices / coroutine resumes | 520.519 / 275 / 70,981 | 554.424 / 282 / 80,796 |
| Step p95 / p99 (harness), maximum internal slice | 2.067 / 2.856 / **4.791** | 2.020 / 2.092 / **3.496** |
| First record / following history | 1.464 / 0.107 | 0.161 / 0.045 |
| Parse all records, separate pass | 10.303 | 10.404 |
| Header parse + Header validation, separate pass | 46.212 | 52.303 |
| All Record validation, including schema/encode/per-record hashes | 144.474 | 169.618 |
| Schema traversal only, nested work above | 8.367 | 11.695 |
| Canonical record encoding only, nested work above | 9.694 | 14.663 |
| Record + exact-identity SHA only, nested work above | 123.005 | 142.521 |
| Two record-stream SHA passes (generation-stream proxy excludes header) | 231.049 | 234.597 |
| Corrupt last-record replacement CPU / worst Step | 479.437 / 2.255 | 536.411 / 3.608 |
| 50 Market close/reopen + exact-history cycles / worst entire cycle | 111.303 / 7.268 | 140.335 / 10.001 |

Hash passes alone are about 354/377 ms, roughly **68%** of actual validation CPU;
they are an attribution estimate from isolated passes, not an exact additive
profile. Do not add Record totals to their nested schema/encode/hash rows.
Other work includes header integrity/request/selection digests, parsing, repeated
canonicalization, semantic checks, index construction, resumes, clocks and GC.
The residual cannot all be assigned to coroutine overhead.

Final 10-dense smoke (same generation, extra saved-data assertion and final corrupt
addon path): 478.507 ms validation, 256 slices, **3.274 ms worst**, 419.589 ms
corruption rejection, 50 cycles 122.563 ms / 6.353 ms worst. Its unchanged 70,981
resumes and retained bytes confirm workload identity; timings vary. Original
successful reports remain under `test-output/market-a2`; final smoke is under
`test-output/market-a2-final-smoke`. An initial harness export failed because the
strict bridge codec rejects fractional numbers; the failed console was retained
as `10-dense/console-integer-export-failure.txt`. Only diagnostic output changed.

| Memory, incremental Lua heap bytes | 10 dense | 100 sparse |
|---|---:|---:|
| Highest sampled heap above pre-payload baseline | 4,790,946 | 5,286,167 |
| Retained payload/index after harness full collection | 274,238 | 272,244 |
| Warm after touching all records / cache entries | 719,361 / 10 | 380,954 / 24 |
| Retained growth after 50 UI cycles | 91,188 | 91,918 |
| Net heap decreases observed between Steps | 0 | 15 |

These are sampled heap, not allocation counts, exact peaks, addon attribution or
GC pause measurements. Net decreases are **not GC-cycle counts**. The harness
collects only between phases, never stops/tunes GC. Record tables and encoding
parts produce transient garbage; dense decoded records retain more per cache
entry. Pages and validation counts stayed stable across cycles; one finite
warming delta does not prove a leak or prove unlimited-session stability.

No-data check: the existing startup tool's current six reader/adapter modules
compiled in median 1.911 ms, initialized in 0.105 ms, retained 301,835 bytes
(three samples), with **zero bridge loads/timers/cache entries and unchanged
synthetic saved-data sentinels**. This is not full Workshop startup. Separately,
the complete mock Workshop load took 40.143–54.227 ms and retained about 4.01 MB,
including fake core/frames; that figure cannot estimate native addon startup.

## Source-confirmed processing and scheduling

See [Bridge](../../TwichUI_Workshop/Bridge.lua),
[validator](../../TwichUI_Workshop/BridgeValidate.lua),
[codec](../../TwichUI_Workshop/BridgeCodec.lua),
[adapter](../../TwichUI_Workshop/ServerMarket.lua) and
[Market view](../../TwichUI_Workshop/auction/ViewMarket.lua).

- `LoadAddOn` compiles and executes the trusted Lua assignment synchronously.
  Validation cannot make compilation cooperative. Assignment alone was tiny here.
- Validation parses and round-trips canonical JSON, traverses the compiled schema,
  verifies calendar/identity/money semantics, manifest/request/selection/record
  hashes, and both complete record/body streams. Only then is `active` replaced.
  The old generation stays accessible throughout replacement and rejection.
- `Step(3)` actually reserves 1 ms headroom: it checks a **2 ms** elapsed budget
  between resumes, with a 512-resume ceiling (32 without a clock). A yield is a
  coroutine work boundary, **not a game frame**. One Step resumes many yields;
  `C_Timer.After(0)` schedules the next Step. No parallel Lua execution occurs.
  If the client delivered only one callback/frame, 275/282 slices at 60 fps would
  span about 4.6/4.7 s, before other work; this is a conditional estimate, not a
  measured client cadence. Historical dense 100 would be about 70 s at that cadence.
- Indivisible work includes `LoadAddOn`, Lua/C string searches/`gsub`, sorts and
  `table.concat`, recursive `J.Copy`, schema `anyOf`/`if` probes under `pcall`
  with no tick, and several post-schema semantic/calendar loops. GC work can
  occur during allocations; a budget check cannot preempt an ongoing call.
  Overshoot is confirmed; **which unit caused the worst slice is undetermined**.
- Records remain encoded; indexing retains item ranges/flat keys. Raw globals,
  active payload, last rejected candidate and a pending replacement can coexist.
  References to a shared string do not imply duplicated string storage. Cancel
  keeps the active generation/cache; addons cannot unload within the session.
- Exact lookups use an item range/binary search. A miss decodes a complete record
  synchronously; FIFO cache is capped at **24**, hits do not refresh its order.
  Public `Record` deep-copies even on cache hits; `Manifest` deep-copies the whole
  header. `ServerMarket.Project` calls both and constructs fresh history/facts.
  `History` is synchronous and builds fresh points/gaps over at most 60 days.
  `record_ms` excludes the returned deep copy; use the full Diagnostics
  `workshop.bridgeRecord` scope to assess player-facing call cost.
- **Unit-tested lifecycle:** closing Market releases its UI job and polling but
  validation continues independently. Workshop `Suspend` calls `Bridge.Cancel`;
  stale queued callbacks no-op and validation stops. Valid data is retained.
  Reopening ready data does not revalidate. Corrupt last-record candidates were
  rejected, prior generation stayed readable, rejected-object retries were
  suppressed, and synthetic local/profile data fingerprints stayed unchanged.

The cooperative design is appropriate in principle for single-threaded Forever,
but its current settings are **not accepted as a native responsiveness budget**.
More caches, more addons, fewer integrity checks or wider work units are not
supported by this evidence. Loaded partitions would still accumulate session
memory and share the global collector.

## Operating limits and ranked next opportunities

Keep current ceilings unchanged: schema-3 **2 MiB canonical delivery**, producer
proposal **3 MiB Lua / 100 selected variants**, record 64 KiB, scoped header
256 KiB, 60-day history, decoded cache 24. The separate contract ceiling is not
a supported delivery envelope. No new safe game limit can be set from Cloud.
For manual client trials start with **10 dense**, then **100 sparse**, and stop
on an unacceptable hitch. Dense 100 remains gated on smaller-case acceptance;
do not use the old 155/166 stress cases as operating defaults.

1. **Native acceptance first (recommended next task).** Existing Diagnostics must
   establish load/wall/callback/frame/memory costs and worst-slice attribution.
   Proposed trial gate, to agree after baseline capture: validation callback
   p99 <=3 ms, max <=5 ms; investigate >33 ms frames and any new >50 ms frame
   around loading; decide an explicit completion-wait budget before larger data.
   These are proposed acceptance criteria, not current guarantees or universal FPS limits.
2. **If native hash CPU dominates:** consider one isolated SHA implementation
   improvement retaining all hashes and yield coverage. Potential benefit is
   lower total validation CPU; actual achievable saving is unknown. Risk:
   bit-operation compatibility/canonical integrity. Success: same fixtures and
   all corruption controls, five interleaved runs exceeding the existing
   `max(3*MAD,5%)` noise rule, no worse p99/max callbacks or retained memory.
   Rollback: revert that reader commit, no data/schema migration.
3. **If native UI traces identify copying:** narrow the metadata copied by
   `ServerMarket.Project` before adding a cache. Potential benefit: fewer header
   allocations per repaint. Current 50-cycle results do not justify implementing
   it. Risk: aliasing/provenance regressions. Require identical UI facts, stable
   local fingerprints and measurable allocation/callback improvement; rollback
   the adapter commit. Do not add persistent decoded histories.

## Remaining Forever procedure (owner participation)

No Forever executable, Wine command or running game was found in this authorized
Cloud workspace; only the simulator/reference sources were available. Therefore
**game lag, native frame impact, load wall time, GC pauses, and native retained
memory remain unmeasured**. Use [Diagnostics](../diagnostics.md) and
[Test Lab](../testlab.md), not a new profiler. Test Lab's existing aggregate/history
benchmarks do not exercise bridge compilation; `perf.ui.redraw` deliberately skips.

1. **Prepare safely while the game is closed.** Use a separate disposable Forever
   installation/test character with a new empty WTF/profile. Do not copy, open,
   replace or fingerprint real player SavedVariables. Install this branch's core,
   Workshop, Settings, Diagnostics, and optionally TestLab there. Leave the
   desktop companion stopped/disconnected from this test installation. Do not
   use the normal deploy script or enable delivery, native replacement, AH reads,
   transactions, login loading or pricing-source defaults. Generate fixtures with
   the commands above (on another host omit the Cloud `source` line). Keep each
   `fixture.json` beside the exported results as the exact identity ledger.
2. **No-data baseline, out of combat and away from an auctioneer.** Initially omit
   both generated addons. In Settings > Workshop enable **Workshop — Experimental**
   on the disposable profile. Run `/tui perf start general 2`, then `/tui ahpreview`.
   Click **Market**, leave its ordinary saved/local source selected, open/close
   ten times, and wait quietly 30 s. `/tui perf stop`. Confirm bridge records/cache
   zero and no bridge load/validation. This separates Workshop/UI load from data.
3. **Cold data load.** Exit the game. Copy only the chosen case's
   `TwichUI_MarketData` folder to the disposable `Interface/AddOns`; it is LoD and
   declares no SavedVariables. Start with 10-dense. Log in, start the same General
   capture, open `/tui ahpreview` > **Market**, then run these commands individually:

   ```text
   /tui perf mark before-market-load
   /run TwichUI.Workshop.Bridge.Load()
   /run local s=TwichUI.Workshop.Bridge.Status();print(s.state,s.validation_ms,s.slices,s.largest_slice_ms,s.cache_entries,s.generation)
   ```

   Repeat only the status command until `ready`, then `/tui perf mark market-ready`.
   Record initial/final counters (they are cumulative). Select **Market server**
   explicitly in Market's source selector, item **10001**, its exact variant,
   **60 days**, **Recent listing price**: expect 100 copper and 60 dense points
   (four sparse points with gaps). This is a temporary display selection, not an
   Advisor/local-pricing switch. Inspect `workshop.bridgeLoad` (native compile +
   execution together), `bridgeValidate` inclusive CPU/calls/p99/max and frame
   timeline. Manual marks give only approximate completion wall time; do not
   mistake status-click delay or CPU totals for exact load wall time. Diagnostics
   cannot separate native compilation from assignment with its existing scopes.
4. **Responsiveness/lifecycle.** Continue the capture: 50 preview close/reopen
   cycles, reselect 10001/exact variant and history; check counts stabilize.
   On a fresh session, start loading and immediately close the preview: status
   should keep advancing. On another fresh session, start loading then turn
   Workshop off via its Settings toggle: status should stop advancing after the
   pending callback drains. Closing Diagnostics alone does not stop its capture.
   Repeat for 100-sparse only if 10-dense is acceptable. Test dense100 only after
   smaller cases meet an agreed native frame/callback/wait budget.
5. **Corruption/recovery with the old generation active.** While the game is
   closed install the **same case's** optional `TwichUI_MarketAuditCorrupt` folder
   alongside the good addon. On a fresh session load/validate the good data first,
   record its generation and displayed price, start a capture, then run:

   ```text
   /run C_AddOns.LoadAddOn("TwichUI_MarketAuditCorrupt")
   /run TwichUI.Workshop.Bridge.Load()
   /run local s=TwichUI.Workshop.Bridge.Status();print(s.state,s.error,s.failures,s.generation,s.loading)
   ```

   After rejection expect `ready`, error `invalid`, a failure increment, and the
   **same previous generation**, price/history and local data. Repeating Load
   should not restart validation. The corrupt addon changes only the in-memory
   external candidate. Exit, remove that optional addon, restart: good data must
   validate again. Never overwrite the good artifact to create this test.
6. **Export/restore.** Stop captures, then `/tui perf` > **Export** > **Full report**
   > **Prepare** > **Select all** > Ctrl+C (all pieces); also export **AI analysis
   prompt**. Attach fixture identities, build, FPS cap/focus, other-addon list,
   status counter deltas, actions and symptoms. Use the same preset/session
   conditions for comparisons; memory updates can themselves cause hitches.
   A separate **Memory and lifecycle** capture can observe the heap settling
   over 60 s; label it natural post-completion memory, not post-forced-GC retained
   memory. Do not force/tune the global collector for prettier results.
   Optional TestLab: load with `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`, select
   one desired existing case, Run case, Copy report; its numbers are separate
   evidence, not bridge acceptance. Finally exit, discard the disposable test
   install/profile and generated addons; resume the untouched original installation.

## Verification and stopping point

**Unit-tested:** `./tests/run.sh development market --profile cloud`: **24 passed,
0 failed**, 83 Lua syntax files, 55.223 s. Includes legacy/scoped identity,
corruption/last-good, deterministic scheduling and UI negative controls. No money
or eligibility implementation changed, so no new mutation campaign was required.
New harness and all six generated data chunks passed `luac5.1 -p`; generator
passed Python compilation. Final small fixture run passed load, history, 50
close/open cycles, cancellation, corruption recovery and saved-data fingerprints.
Documentation links, final diff/whitespace and publication hold checked.
Feature/full certification and simulator catalogs deliberately omitted: this is
an investigation/tooling report, not a production feature or release candidate.

Stop here. The only necessary owner action is the disposable-client procedure
and return of its reports; no implementation or publication is requested by this audit.
