# Verification optimization evidence

[Audit and coverage-to-cost matrix](../../testing-verification-audit.md),
[commands and policy](../../testing.md), and [compact results](results.json).
Raw reports, scenario stdout/stderr, all captured PNGs, instrumented sidecars,
verdict controls and exploratory failures remain ignored under each audit
worktree's `test-output/`. The compact results contain raw report SHA-256 values
and relative report locations, with machine-specific commands/paths omitted.

Source provenance:

- Baseline addon and fixtures: `5133a43477237bf7cd97a429a680a751a9533f7c`.
- Complete offline run and first implementation: `7eb1258`.
- Frozen ten-launch serial/parallel comparison: `4c5b545`.
- Final runtime reporting, worker-lock paths and four-capture worker repeat: `88f504f`.
- Subsequent changes are testing policy, evidence and an additional archive-rejection test.

All ten addon Git tree IDs match the baseline. Every Lua test and scenario/fixture
input is unchanged. All 248 offline modules passed; later infrastructure changes
received focused verification. The comprehensive simulator/local release gate
was not run on this candidate. No full/release PASS is claimed.

Reproduce the bounded selection sequentially on frozen source, with the existing
environment activated and no competing heavy verification:

```sh
./tests/run.sh development workshop-settings --profile cloud
./tests/run.sh feature verification-tools --profile cloud --measure --sim-jobs 1
./tests/run.sh feature verification-tools --profile cloud --measure --sim-jobs 2
./tests/run.sh integration market --with-group crafting --list
./tests/run.sh feature auction-preview --list
./tests/run.sh full --list
```

Compare actual selected artifacts/checks, not only totals. Worker state must be
disjoint. Native wrong expectations are intentional and must be detected by the
catalog verdict. Keep literal transcripts and use alias-preserving table-address
IDs only for offline cross-process comparisons. Native screenshots vary even
between serial runs; existing native gates are structural. Pixel equality is
required for old/new decoders consuming identical files and existing offline
artwork tests, which retain their byte-level contracts.

Measurements show 319.913 → 249.833 seconds for identical representative coverage,
12.7% lower decoder wall time, and approximately nine-second existing development
checks. Full-suite effects remain unmeasured; the 46-second decoder projection
assumes every screenshot resembles the wide-image benchmark. A valid candidate
archive and local full gate remain necessary for release certification.
