# PR3 benchmark evidence

See the [report](../../performance/v2-opportunities-incremental-pr3.md) for methods, exact helper/production revisions, commands and limits. Baseline/candidate matrix and lifecycle reports retain individual runs and medians/ranges. `headline-*`, `scroll-*` and `stress-*` use the matching c8bd885 helper; `memory-60` and `profile-final` are explicitly non-statistical diagnostics. `intermediate-checkpoint` preserves the earlier implementation and its unexplained 35.4 ms spike; it is not final-code performance. `gc-initial.patch` reproduces the initial diagnostic against helper6754427. No raw production records, database snapshots or personal game data are included.

`accounting-headline.json` rechecks final callback/source timing revision 8a36c29 with the same c8bd885 helper and baseline economic/fixture hashes. The larger matrix remains explicitly labeled 5ca9734. `verification.json` preserves both focused checkpoints and the strict simulator failure.
