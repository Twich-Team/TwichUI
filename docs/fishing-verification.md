# Fishing economics verification

Implementation checkpoints on `feature/fishing-completion`, PR [#140](https://github.com/Twich-Team/TwichUI/pull/140): `a0cf85e` (engine/accounting), `4e5a2cd` (presentation/settings), followed by performance, compatibility and acceptance refinements. The synchronization commit `6e43c36` is preserved.

## Unit and mutation evidence

The final Fishing development selection passed 22 modules with zero failures (including release/package safeguards). Economic cases cover copper arithmetic, quantities/rates, unknown prices, source identity and generation changes, cached presentation refresh, delayed prices, vendor values without Workshop, session/lifetime provenance, late container processing, partial lots, saved-variable round trips and overflow. All six mutation defects were detected: opened-shell double-counting, unknown-as-zero, generation reuse, market mixing shared-item provenance display and premature partial-lot marker clearing. A red/green regression verifies that five directly caught fish and three of the same fish from a container show their respective values, while the total values all eight.

### RSS evidence fixture correction

The prior full run at `623e97b` had 340 passes and one failure: the measurement fixture assumed that a child doing 0.4 CPU seconds must remain alive until the wrapper samples it. Under load the wrapper can be descheduled while the child finishes. A deterministic 0.8-second delay after child launch reproduced exit 7 with positive reaped CPU but zero samples/RSS. The collector's `/proc` indexing and documented sampling-lower-bound behavior were correct.

Commit `31b3b4c` changes the test fixture only. The child now waits until the real collector observes positive RSS, then performs its CPU work and exits 7. A test-only 0.6-second launch delay exercises the original race. Positive RSS/CPU, timing and exit-propagation assertions are retained; telemetry is not fabricated, skipped or weakened. All 21 test-runner tests passed under four concurrent bounded CPU-load workers. A final frozen complete run is recorded in PR #140 after these corrections.

## Performance evidence (synthetic CPU measurements)

`tests/fishing_economy_benchmark.lua` exercises real Fishing code with 100,000 O(1) synthetic reference entries, 1,000 distinct item quantities and 500 historical sessions. It does not emulate compressed Market decoding or native game timings. Existing Workshop Market performance/reference/valuation tests exercise the unchanged pricing pipeline separately.

| Operation | Measured time |
| --- | ---: |
| Cold item cache request, no synchronous pricing | 0.050 ms |
| Warm item cache read | 0.007 ms |
| 1,000 cold item quantities | 2.869 ms |
| 1,000 warm item quantities | 2.468 ms |
| Journal opening, 500 sessions | 45.132 ms |
| Switching all five pages | 8.735 ms |
| Typical redraw | 0.286 ms |
| Market update event with Overview open | 0.012 ms |
| Workshop unavailable, 1,000 quantities | 1.547 ms |
| Largest deferred callback | 4.528 ms |
| Entire benchmark CPU | 100.461 ms |

Three repeated Journal-opening samples had medians 38.303 ms with economics and 38.307 ms with display disabled. Individual measurements vary substantially with allocation/GC and concurrent simulator load; they are not a guarantee of a 26 ms native opening. Deferred callbacks include event/redraw scheduling. Diagnostic scope `fishing.economy` and gauge `fishing.prices` permit real-client measurement without changing behavior.

Final verification reran the unchanged economy benchmark three times. Medians: cold request 0.060 ms, warm item 0.006 ms, 1,000 cold/warm quantities 2.375/2.943 ms, Journal opening 52.587 ms (maximum 53.914), five pages 9.110 ms, redraw 0.279 ms, generation-change event 0.022 ms and unavailable-Workshop aggregation 1.240 ms. Largest deferred callback across the runs was 4.019 ms; median total CPU was 106.685 ms. Compared with the table above, no new blocking pricing work or material regression was demonstrated. Timing variation and GC remain visible; this is not a native-client guarantee.

## Presentation and packaging

Offline HUD/Journal captures used synthetic reference values and the actual Fishing artwork. Reviewed HUD, Overview, Sessions and Collections captures; refined crowded economic text using existing stat/detail areas. The offline renderer cannot display unavailable native coin textures and is not real-client visual verification. Current capture helpers accept `FISHING_ECONOMY_CAPTURE=1`.

An internal, unpublished validation ZIP passed `tools/release.py`'s archive checker, with eight addon roots, both economy modules and all 29 Fishing media files. Versions were changed only in ZIP bytes; repository release metadata and publication workflows were not changed. This is not a certified release candidate.

## Workshop simulator classification

The synchronized baseline `6e43c36` and economics implementation `c0c6030` produced exactly the same 41 extracted assertion failures: SHA256 `22b90b15bde1bb442313320a732fed93985f8cd438af7639e9368a0ca71b3c5f`. Workshop production and the scenario were byte-identical between those commits. No failure in this group was introduced by Fishing, and no production Workshop regression was demonstrated.

| Group | Count | Classification and independent evidence |
| --- | ---: | --- |
| Advisor craft/unknown recommendation lines | 17 | Confirmed pre-existing, outdated expectation. Current policy intentionally omits non-sale advice from the tooltip; `test_workshop_advisor.lua` and `test_workshop_advisor_market.lua` cover it. This explains the absent `Workshop: Not enough data` line. |
| Known vendor option with missing auction price | 1 | Confirmed pre-existing, outdated preview expectation; current Advisor policy and reference-model tests prefer the known eligible vendor option. |
| Non-enchanter capability | 1 | Confirmed pre-existing fixture mismatch; `Disenchant.Character` and `test_workshop_disenchant.lua` support the explicit unavailable reason. |
| Supported outcome catalog | 2 | Confirmed pre-existing, outdated expectation; current WorthLayout catalog and its unit tests support all eight original types. |
| Editable heading and row indices | 13 | Confirmed pre-existing, outdated fixture assumptions; `test_workshop_worth_designer.lua` / `test_workshop_worth_layout.lua` establish the explicit `text#1` heading. Stable IDs and heading-aware drag gaps replace brittle row positions. |
| Recommendation artwork | 6 | Confirmed pre-existing normalization/preview drift; artwork is independently asserted by Advisor unit tests. The scenario now asserts artwork explicitly and normalizes it only for text comparison. |
| Direct-recipe caption | 1 | Confirmed pre-existing, outdated caption; current `ViewShopping.lua` supplies `Add to plan`. |

Commit `ad17f63` corrects the scenario only. Exact money, unavailable-state, layout-preservation and negative-control checks remain; no production behavior was changed to match a test. The existing Workshop verdict already narrowly discloses known voice-API and NPC-share UTF-8 simulator limitations while rejecting unknown errors and any Workshop-origin UTF-8 error. That classifier was not loosened. These are simulator environment limitations, separate from the 41 assertions.

## Integration and native acceptance

Final frozen results, CI and integration commit identities are recorded in PR #140. The latest verified main changes (RestedXP #141 and spoken-reading #142) were merged history-preservingly before final verification, so the combined Core/Settings runtime is tested. No experimental Market branch was incorporated.

Use the [owner acceptance procedure](fishing-acceptance.md) for native interactions and a pasteable Test Lab result. No real-client verification is claimed. Lure purchase costs/net income remain unavailable without historical cost evidence; ambiguous partially processed lots stay incomplete. Merge the completion PR only after automated verification passes; the final mainline PR must remain open for owner acceptance while critical native interactions are unverified. Neither merge nor validation authorizes publication.

## Partial-lot acceptance regression

The first corrected frozen run at `f7af5ca` passed all 341 modules. Acceptance review then demonstrated one genuine valuation defect: partially loot two clams in the same queued lot, move the first behind the second, and finish only the second. Clearing the lot marker at that point restored a 500-copper provisional shell value beside its already-recorded pearl: 20,520 copper instead of the confirmed subtotal of 20,020.

The minimal correction retains uncertainty while the lot survives and clears it only at exhaustion. No new tracking, ledger, opening action or pricing algorithm is added. `test_fishing_partial_lots.lua` exercises real mock key/loot/bag-move bookkeeping, verifies the corrected subtotal, final exhaustion and unsuccessful opens; a sixth mutation reinstating premature clearing is detected. Final source is frozen again for the complete 342-module run before completion-branch integration.
