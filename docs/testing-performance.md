# Test and simulator performance

## Audit before implementation — 2026-11-14

Baseline revision: `420e7319` on `feature/workshop`. Native WSL2, Lua 5.1,
Python 3, 32 logical CPUs, approximately 15.2 GiB RAM. Existing checkout clean.
Only TwichUI may be changed; the sibling simulator installation is read-only.

- `./tests/run.sh`: **322.14 s**, 218 passed, zero failures: **213 Lua files
  and five Python modules (98 unittest cases)**. CPU 299.21 s user / 19.71 s
  system; peak child RSS 4,077,488 KiB. This is a first observed run, not an
  OS-cache-flushed run. A warm per-file profile follows.
- Original runner discovers every `tests/test_*.lua` in shell order, then five
  hard-coded Python modules. Separate Lua processes prevent global-state leaks.
  Failures show only five lines; failed Python modules are executed twice.
- Python tests rebuild artwork in temporary folders; layout import tests make
  disposable repository copies. No assertion or generator should be removed.
  Settings contract/inventory generation is explicitly opt-in via environment;
  verification must clear these variables and seeded-test count overrides.
- Simulator staging: 0.266 / 0.221 / 0.217 s for three clean copies.
  Empty, no-addon `dump-tree --visible-only`: 4.04 s including process startup
  and teardown. These component probes ran during the first offline run;
  complete workflow comparisons are measured separately.
- One representative 1600×1200 Workshop PNG: decoding 1.396 / 1.731 / 1.825 s;
  counting colours 0.102 / 0.121 / 0.120 s (5,216 colours). The pure-Python
  decoder repeatedly allocates tuples for Paeth prediction. Assertions depend on
  decoded pixels; optimize the algorithm without omitting image checks.
- Workshop has 25 launches: 24 screenshot poses and an intentional failure.
  Every pose repeats the complete scenario and is compared for reproducibility.
  Test Lab has nine launches; interaction four; diagnostics five; smoke two.
  Settings discovers its catalog at runtime; Reminders has 37 default poses.
  Exact executed counts will be recorded from the benchmark artifacts.
- Simulator roots, fixtures, home, cache, WTF, and artifact names are shared.
  Existing runners can overwrite one another. Serial execution is required
  until all these resources are isolated. The binary sees staged addons as
  read-only, making one immutable stage per script invocation safe; new
  invocations must always restage. Keep every existing full-run replay.
- Mutation campaigns already support isolated workers and deterministic source
  snapshots (`tools/mutate.py`). Campaigns are separate from the offline suite;
  its five Python modules include the mutation runner's own harness tests.
  The current catalog has 286 entries (verify exact count with `--all --list`).
  Keep the existing money/quantity/ordering mutation policy.
- CI: `.github/workflows/release.yml` runs `./tests/run.sh` before packaging on
  main/beta/tag releases, with no simulator setup. Keep no-argument behavior as
  the complete offline suite; add an explicit milestone command including the
  existing simulator regression scripts. Do not make release CI depend on a
  local game installation.

## Planned bounded improvements

1. A small standard-library runner behind `tests/run.sh`: explicit feature
   selections, fast / feature / full tiers, complete discovery for offline CI,
   syntax checks, per-file logs/timings and visible failures.
2. Benchmark one and two workers; use conservative defaults and exclude
   unproven memory-heavy combinations. Maintain serial debugging.
3. A repository-local disposable simulator workspace and a lock, consuming the
   installed binary/dependencies/cache seed read-only. Avoid repeated staging
   inside one script, retain independent simulator processes and all assertions.
4. Optimize PNG decoding with byte-for-byte parity tests over all five filters.
   Repair focused Workshop verdict selection so omitted files are never read
   or represented as full regression evidence.

Expected benefit: feature checks avoid unrelated layout/art rebuilds and
simulator poses; two workers may reduce offline wall time, subject to memory
measurements; staging saves about 5 s over Workshop's 25 launches; decoder work
may save tens of seconds across screenshot-heavy scripts. Startup cost remains
per launch: batching or reducing full scenario replays is deferred because it
would change existing reproducibility evidence.

Raw logs, original scripts, timing files and profiles are ignored under
`test-output/workflow-baseline/`. The baseline simulator wrapper overlays its
writable directories with `test-output/simlab-baseline/`; the installation stays
read-only. No simulator source/build changes or production addon edits.
