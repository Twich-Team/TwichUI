# Test and simulator performance

**Current diagnostics status (2026-11-14): resolved.** The follow-up at the end of
this report corrects the party/guild fixture assumption. Full verification now
passes: **222 files/modules, 140 simulator launches and 17,487 structured checks**
in **1,674.207 s (27 min 54.21 s)**, exit **0**. Historical failed results below
are retained as baseline evidence, not the current verification status.

## Optimization milestone results (historical, `152f2e91`)

| Workflow | Baseline | Optimized | Change |
|---|---:|---:|---|
| Full offline, isolated sequential comparison | 310.69 s / 218 files | 266.87 s / 221 files | **14.10% less wall time** |
| Workshop Settings fast checks | Former full offline check: 310.69 s | Median 1.355 s / 7 files | **99.56% less feedback time, narrower coverage** |
| Workshop Settings feature verification | No previous single feature command | 124.170 s / 71 files + 3 launches | Focused checkpoint evidence |
| Complete milestone command | No previous aggregate command | 1,702.555 s / 221 files + 139 launches | Existing diagnostics failure remains visible |

The isolated offline comparison ran the original serial runner and the new
2-worker runner back-to-back after all simulator processes ended. Both passed;
the new run retains every original test and adds 19 Python infrastructure cases.
Original CPU: 291.57 s user + 16.30 s system; new: 317.81 s + 18.75 s. Parallelism
reduces feedback wall time, not total CPU work; these samples also include the
new tests. Maximum child RSS: 4,085,304 → 4,076,848 KiB (about 3.9 GiB in both).
This supports the conservative two-worker default, not unmeasured higher
concurrency. All layout files remain serial. The original first/warm samples
below show ordinary run-to-run variation; these are not performance thresholds.

**Historical milestone evidence (`152f2e91`):** unit-tested and simulator-tested.
That full verification exited 1 on the pre-existing solo-message assertion.
The diagnostics follow-up below resolves its fixture assumption without changing
production behavior; its verification results are recorded separately. No assertion
was disabled, normalized, or made expected-to-fail to produce a green result.
No real-client or appearance validation is claimed.

Implementation checkpoints were committed and pushed on `feature/workshop`:
`e58e59fc` (audit) and `11f37460` (runner, isolation, controls and instructions).
This document's final benchmark update follows those verified checkpoints.

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
  Settings discovers its catalog at runtime; Reminders has 36 default poses.
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

## Warm profile and verification setup

The original per-file warm run passed all 218 files/modules in **318.808 s**.
Layout tests (13 files) accounted for 177.041 s, Workshop (24) 67.722 s,
Python modules (5) 21.095 s, and the remaining 176 files 52.904 s.
Slowest files: layout publish 33.612 s, layout wizard 30.904 s, Workshop
history2 23.268 s, layout hardening 21.519 s, layout presets 18.411 s,
layout update 15.860 s, Workshop market scale 15.111 s.

An initial new serial run passed 220 files/modules in 364.672 s while simulator
probes were active; this is a contention diagnostic, not an isolated speedup
comparison. Early simulator timing attempts correctly failed repository-status
guards as benchmark setup created files. Scenario assertions passed; these
attempts are not reported as successful guarded regression runs. Baseline
simulator scripts now run from a frozen source snapshot with its own Git
boundary, and benchmark outputs share pre-created ignored directories.

## Implemented workflow and measured focused checks

The interface and exact boundaries are in [testing.md](testing.md).
`tests/groups.json` is the feature map; full discovery uses every Lua/Python
`test_*` file, never a union of feature groups. No production addon file, Lua
test assertion, randomized scenario count or mutation entry was changed.

| Check | Measured result | Selection |
|---|---:|---|
| Fast Workshop Settings (three repeats) | 1.558 / 1.104 / 1.355 s wall; median **1.355 s** | 7 Lua test files + 13 syntax files |
| Workshop Settings feature verification | **124.170 s** | 71 Lua test files + 3 simulator launches / 1,452 checks |
| Paired PNG decode, old → new medians | **1.410662 → 0.860348 s (39.01% less)** | Identical 1600×1200 image, exact decoded bytes |
| Paired colour count, old → new medians | **0.104454 → 0.020756 s (80.13% less)** | Identical crop, 5,216 RGB colours |
| Mutation example (`market.dist`, one worker) | **12.5 s** campaign, 31/31 killed | Full selected campaign, no survivors/invalid/timeouts/infra errors |

The focused samples ran while other benchmark workflows were active. They show
practical feedback time, not an isolated CPU comparison. A fast selection is
approximately 99.6% shorter than the former 318.8-second full offline check,
with **intentionally narrower coverage**. It cannot establish full regression
coverage. Feature verification includes shared dependencies and preserves the
Workshop replay comparison and wrong-expectation control.

PNG timings use three interleaved old/new runs, reversing order on alternating
repetitions. Every decoded byte was compared; randomized tests also cover all
five PNG filters, edge pixels, Paeth ties and modulo-256 overflow. Screenshot
size/colour assertions remain intact, and duplicate colour counting within a
Workshop image verdict was removed. No image validation was dropped.

### Original simulator measurements

All use seeded disposable caches and independent processes, not an OS-cache
flush. The first Workshop attempt (581.41 s) correctly failed its repository
status guard during benchmark setup. It is not successful regression evidence.
The frozen-source repeat below passed its guard and verdict. Its **997 files
match Git blobs at `420e7319`**, with no missing or mismatched file.

| Original script | Seconds | Launches | Structured scenario checks | Images | Result |
|---|---:|---:|---:|---:|---|
| Workshop (all default poses) | 622.09 | 25 | 12,118 | 24 | Pass with classified simulator limitations |
| Smoke | 29.37 | 2 | — (56 pages constructed) | 1 | Pass |
| Interaction | 27.73 | 4 | 244 | 2 | Pass with classified limitations |
| Diagnostics | 22.77 | 5 | 74 | 0 | **Fail: solo expects zero sends, observes one** |
| Test Lab | 73.60 | 9 | 229 | 9 | Pass with classified limitations |
| Settings, `workshop` selection | 16.94 | 2 | 37 | 2 | Pass |
| Reminders, `editor narrow` selection | 24.17 | 2 | 187 | 2 | Pass |

The diagnostics failure is present in the unchanged baseline. Its assertion and
failure exit remain visible. No assertion, source behavior, message observer or
scenario was changed to accommodate it. Fixing that older scenario/behavior
mismatch is separate work. Existing classified runtime limitations also remain
in the logs; a scenario pass is not a claim of zero simulator runtime errors.

### Resource and parallelization decisions

Offline execution uses two workers by default, at most four on request. All 13
layout test files run individually after the worker pool: the original process
peak was about 3.9 GiB. Every test has its own process and temporary folder;
fixture-generation opt-ins and reduced-seed overrides are cleared. Existing
Python generators use disposable directories; the release-tool HTTP server
uses an ephemeral port. New tests must retain those isolation properties;
place unaudited shared writers or large heaps in the exclusive selection until
measured. No persistent Lua process or shared mutable fixture cache was added.

Simulator execution remains one worker, protected by a lock. An observed
simulator process used about 1.3 GiB RSS; GNU time around bubblewrap does **not**
account for every process in the nested PID namespace, so its small wrapper RSS
is not a simulator memory estimate. The installation/dependencies and staged
addons were explicitly checked read-only inside the process boundary; only
repository-local mutable state is writable. Interrupted cache seeding cannot
publish a partially copied cache. No simulator installation/source was changed.

Staging reuse lasts only one script invocation. Full Workshop and Test Lab
replays remain independent processes, with their reproducibility comparisons,
negative controls and screenshots. Serial mode remains available everywhere;
no simulation parallelism is claimed.

## Comprehensive regression result

`SIMLAB_ONLY=bogus SIMLAB_ASSETS=0 ./tests/run.sh full` deliberately supplied
invalid/narrowing inherited options to verify that the milestone command clears
them. It executed the complete defaults with game assets, not the supplied
filter. Total: **1,702.555 s (28 min 22.56 s)**, exit **1** solely for the
unchanged baseline diagnostics failure. Syntax (667 Lua files), every offline
file/module, and the other seven suite/guard results passed. This is not a green
full-regression claim.

| Full-run component | Seconds | Launches | Structured checks | Result |
|---|---:|---:|---:|---|
| Lab guard | 0.689 | — | 36 guard cases | Pass |
| Smoke | 23.406 | 2 | 56 pages constructed | Pass |
| Interaction | 26.718 | 4 | 244 | Pass |
| Diagnostics | 19.171 | 5 | 74 | Baseline failure retained |
| Workshop | 483.597 | 25 | 12,118 | Pass |
| Test Lab | 62.488 | 9 | 229 | Pass |
| Settings | 420.483 | 58 | 1,027 | Pass |
| Reminders | 381.436 | 36 | 3,768 | Pass |

That is **139 launches / 17,460 structured scenario checks**, plus the guard and
smoke construction checks. Workshop still has 24 images and the wrong-on-purpose
launch. Every default settings page and Reminders pose ran. There was no previous
single aggregate command for all these scripts, so there is no invented
before/after percentage for this newly consolidated 28-minute command.

Coverage comparison: **213 original Lua files retained; all five original Python
modules and their 98 cases retained; three new infrastructure modules add 19
cases**. Final full discovery ran **221 files/modules and 117 Python cases**.
Across all 49 launches shared with the representative baseline runs, assertion
names, layers, expected/actual values, pass/fail outcomes and object-identity
relationships agree. Forty-five transcripts match literally; the remaining
four differ only in process-local Lua table addresses. Raw logs were retained;
address canonicalization was used only for this offline comparison, never for a
verdict or assertion.

Workshop's observed 622.09 → 483.597 s is 22.3% less wall time; Test Lab's
73.60 → 62.488 s is 15.1% less. Original simulator measurements overlapped other
benchmark activity, so these whole-script deltas include host/cache/load effects
and are not isolated causal speedup claims. The paired PNG measurements above
are the controlled comparison. All scenario processes/reproducibility checks
were retained; startup remains a substantial cost.

## Exact commands and artifacts

Primary commands (from the repository root):

```sh
/usr/bin/time -v ./tests/run.sh fast workshop-settings
/usr/bin/time -v ./tests/run.sh feature workshop-settings
/usr/bin/time -v ./tests/run.sh --jobs 1
/usr/bin/time -v ./tests/run.sh --jobs 2
/usr/bin/time -v ./tests/run.sh full
bash tools/mutate.sh --all --check
/usr/bin/time -v bash tools/mutate.sh --group market.dist --jobs 1 \
  --json test-output/workflow-optimized/mutation-dist.json
TMPDIR="$PWD/test-output/workflow-optimized" bash tools/simlab/tests/lab_guard.sh
```

The original runner can be reproduced against this unchanged addon/test source
without checking out over current work. The actual isolated comparison used:

```sh
mkdir -p test-output/workflow-optimized
python3 -B - <<'PY'
from pathlib import Path
import subprocess
script = subprocess.check_output(['git', 'show', '420e7319:tests/run.sh'], text=True)
script = script.replace('cd "$(dirname "$0")"', 'cd "$1/tests"')
Path('test-output/workflow-optimized/original-offline.sh').write_text(script)
PY
/usr/bin/time -v bash test-output/workflow-optimized/original-offline.sh "$PWD"
/usr/bin/time -v ./tests/run.sh --jobs 2
```

These two comparison commands run sequentially after simulator activity ends.
They compare the original suite's 218 files/modules with the new runner's 221;
the latter also executes all 19 new infrastructure cases. For a future feature
revision, compare equivalent source/fixtures rather than interpreting changes
in addon workload as runner performance.

Raw first/warm profiles, per-file logs, original simulator scripts and source
integrity checks: `test-output/workflow-baseline/`. Full/feature reports and
per-test logs: `test-output/verification/` (each command prints its exact unique
folder). Comparison timings, process-control results, paired PNG samples,
coverage comparison and mutation report: `test-output/workflow-optimized/`.
All are ignored, intentional development artifacts, not release contents.

Failure controls passed: nonzero Lua/Python exits, caught `ERROR:` markers,
missing success markers, full traceback retention, failed Python modules run
once, process-group timeout/descendant termination, invalid feature/pose names,
wrong-expectation simulator control, workspace lock refusal, symlink refusal,
read-only mounts, isolated cache writes and child exit-code propagation. The
comprehensive run's real baseline diagnostics failure also propagated to exit 1.
The lab guard passes all 36 cases with the runner's in-repository TMPDIR; its
repository stand-in fixes that fixture assumption while retaining explicit
checks against the actual checkout.

## Remaining opportunities

- The diagnostics solo-message mismatch is resolved by the follow-up below;
  its original failed milestone result is retained as historical evidence.
- Profile the large layout mock-client heaps before changing their fixtures.
  Caching mutable mock clients or sharing a Lua process would risk state leaks.
- Simulator workers need separate roots, fixtures, home, cache, WTF, artifacts,
  locks and a measured WSL resource budget. They are not parallelized here.
- Reducing full Workshop replays or batching poses could save startup time, but
  changes existing reproducibility evidence. That requires a separately reviewed
  coverage design; no simulator engine patch or source build was attempted.
- `guild_bank_preview.sh` is still a manual parameterized preview without a
  default regression catalog/verdict. Turning it into regression coverage would
  be separate work, not an excuse to count its screenshots as tested behavior.

No production changes, releases, simulator installation edits or Workshop
Settings 2.0 feature work were performed.

## Isolated comparison artifacts

`test-output/workflow-optimized/baseline-isolated.log` ends with
`218 passed, 0 failed`; its `.time` records 310.69 s. The following
`unit-isolated.log` ends with `221 passed, 0 failed` (266.610 s inside the runner,
266.87 s including launcher startup). Its `report.json` contains all 213 Lua
files, all eight Python modules / 117 cases, and zero failures.
`benchmark-sequence.json` records both exit codes as zero and the comprehensive
run's retained failure as exit 1. `full-summary.json` and
`coverage-comparison.json` record the simulator totals and baseline comparison.

Final scope review: changes are limited to developer documentation, test
selection/runner/control tests, and `tools/simlab/` wrappers/verdicts. Original
Lua tests, production addons, third-party libraries, `.toc` metadata, release CI,
mutation runner/catalog and the separate simulator installation are unchanged.

## Diagnostics follow-up — 2026-11-14

Root cause: `Lab.Solo()` leaves the sample party, not the synthetic guild. The
unexpected call was `TwichUIGuild`, channel `GUILD`, at simulated 7.5 s, accepted
by the simulator. Its synthetic payload was a version-1 position packet,
`1:p:<epoch>:1:2248:5000:5000`. This is the documented, authorized Guild Locations
default (own position, GUILD only), independent of party membership.

Smallest existing reproduction: `bash tools/simlab/run.sh diagnose`, exit 1 on
`solo: no addon message was attempted across the window` (expected 0, actual 1).
A single solo launch with the unchanged fixture plus a trailing observer dump
identified the packet; both commands used repository-local writable state and
the unchanged read-only simulator installation. Raw logs and controlled failure
copies are in `test-output/diagnostics-regression/`.

The fixture now distinguishes unguilded solo from guilded solo. The original
zero-message assertion is retained in the unguilded world, and the real guild
update handler must end the session while sharing remains enabled. A sixth
`guildsolo` launch retains the original guilded world and checks every observed
message: exactly one valid own-position GUILD packet, no party/other traffic.
It covers the entire first-send jitter window. No production file, feature
state setter, transport observer, classifier exception or existing assertion
was disabled or relaxed. Message logging now also identifies failures in solo.

Focused evidence: six native diagnostic launches / 101 checks pass with
the same classified simulator limitations; `fast core` passes 12 files;
`test_guild_locations.lua` passes 645 checks; the new fixture regression test
passes 30 isolation/failure-control checks. A copied native guildsolo log with
channel changed to PARTY and consistent failure counts makes the unchanged
verdict logic return 1. The new regression test also rejects a disposable copy
of the original fixture (exit 1 on the zero-message assertion) and passes the
corrected fixture. All 64 assertions in the original contract, no-addon baseline,
grouped and login cases have identical expected/actual outcomes.

Verification (native WSL; installation read-only):

| Command | Result |
|---|---|
| `./tests/run.sh fast core` | 12 files pass; 1.502 s |
| Direct `test_simlab_diagnostics.lua` | 30 isolation/transport/failure checks pass; original fixture fails this test |
| Direct `test_guild_locations.lua` | 645 real-addon unit checks pass |
| `bash tools/simlab/run.sh diagnose` | Six launches / 101 checks pass with the unchanged classified simulator limitations |
| Copied native log: guildsolo channel deliberately changed to PARTY | Verdict exits 1 on that check; count agreement remains valid |
| `./tests/run.sh feature core` | 21 files, smoke and all diagnostics pass; 47.338 s |
| `./tests/run.sh full` | **PASS**, exit **0**; 222 files/modules (214 Lua, 8 Python / 117 cases), 140 launches / 17,487 structured checks; 1,674.207 s |

The complete run also passes the 668-file Lua syntax check and 36 lab-guard
cases. Other simulator catalogs keep their original scopes: smoke 2 launches,
interaction 4, Workshop 25, Test Lab 9, settings 58 and Reminders 36. Diagnostics
grows from five launches / 74 checks to six / 101. It retains every original
case; the unguilded zero-message case now passes, and the original guilded solo
world is explicitly covered instead of suppressing its legitimate packet.

The full `report.json` is in the unique folder printed by
`test-output/diagnostics-regression/full.log`; `full-summary.json` records its
path/counts, and `unchanged-cases.json` records the original assertion comparison.
The working tree was reviewed for unrelated or generated files. Changes are
limited to three diagnostics files, one focused Lua regression test, its core
selection and developer documentation. Production addons, message transport,
feature defaults, simulator engine/installation, `.toc` metadata and release
configuration are unchanged. No other feature milestone was started.

Evidence is **unit-tested** and **simulator-tested**. The same known voice and
UTF-8 simulator limitations are still reported and classified, with no new
exceptions. No real-client test, network delivery or appearance validation is
claimed.
