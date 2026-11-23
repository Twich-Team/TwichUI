# Fishing economics verification

Implementation checkpoints on `feature/fishing-completion`, PR [#140](https://github.com/Twich-Team/TwichUI/pull/140): `a0cf85e` (engine/accounting), `4e5a2cd` (presentation/settings), followed by performance, compatibility and acceptance refinements. The synchronization commit `6e43c36` is preserved.

## Unit and mutation evidence

The final Fishing development selection passed 21 modules with zero failures (including release/package safeguards). Economic cases cover copper arithmetic, quantities/rates, unknown prices, source identity and generation changes, cached presentation refresh, delayed prices, vendor values without Workshop, session/lifetime provenance, late container processing, partial lots, saved-variable round trips and overflow. All four mutation defects were detected: opened-shell double-counting, unknown-as-zero, generation reuse and market mixing.

An initial complete offline run passed all 341 modules but was correctly rejected by the runner's source-change guard: implementation continued during that run. It is not certified as a passing full gate. A frozen-source rerun is required and its outcome belongs in PR #140.

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

## Presentation and packaging

Offline HUD/Journal captures used synthetic reference values and the actual Fishing artwork. Reviewed HUD, Overview, Sessions and Collections captures; refined crowded economic text using existing stat/detail areas. The offline renderer cannot display unavailable native coin textures and is not real-client visual verification. Current capture helpers accept `FISHING_ECONOMY_CAPTURE=1`.

An internal, unpublished validation ZIP passed `tools/release.py`'s archive checker, with eight addon roots, both economy modules and all 29 Fishing media files. Versions were changed only in ZIP bytes; repository release metadata and publication workflows were not changed. This is not a certified release candidate.

## Integration blockers and native acceptance

The integration Workshop simulator reproduces the synchronization baseline's 41 tooltip assertion failures. The first expects `Workshop: Not enough data`, while the tooltip omits that line. Both the original synchronization baseline and the economic integration run show the same mismatch. Existing simulator-only addon-message UTF-8 and voice API errors also remain. Concurrent implementation invalidated the first integration run's source/status guard; that run is not claimed green.

Do not merge PR #140 as a verified green integration while these failures are unresolved. Preserve publication and branch protections. Real-client acceptance, the read-only Fishing Test Lab report and the compact owner checklist are documented in [Fishing](fishing.md#verification-and-owner-acceptance). No real-client verification is claimed. Lure purchase costs/net income remain unavailable because historical cost evidence was not recorded. Partially processed lots with ambiguous individual shells are conservatively excluded from provisional value and explicitly incomplete.
