# Development verification

Run from the repository root using native Linux/WSL. Requires Lua 5.1,
`luac5.1`, luabitop and Python 3. The simulator also needs the existing
installation and the dependencies in [simulator-lab.md](simulator-lab.md).
No new Python packages are required.

**Cost-conscious verification:** prefer the smallest existing test or development group
while editing, then affected feature/integration coverage at the appropriate checkpoint.
Add tests only for meaningful new behavior, safety boundaries or plausible regressions;
do not add duplicate scenarios to inflate counts. Cosmetic or documentation-only
changes normally need syntax, targeted visual, or link checks rather than unrelated
simulator catalogs or a new harness. Use benchmarks for changed performance-sensitive
paths, not as an automatic step on every PR. Preserve the independent full release gate.

| Tier | Command | Evidence |
|---|---|---|
| Development | `./tests/run.sh development workshop-settings` (alias `fast`) | Direct feature tests and Lua syntax; no simulator |
| Feature checkpoint | `./tests/run.sh feature workshop-settings` | Feature tests, shared dependency tests/syntax and selected simulator regressions |
| Integration | `./tests/run.sh integration market --with-group crafting` | Union of affected groups/dependencies and selected simulator coverage; deduplicated |
| Release certification | `./tests/run.sh release --release-meta <meta.json> --release-zip <candidate.zip>` | Unchanged full gate plus existing release archive checker; no publication |
| Full regression | `./tests/run.sh full` | Every offline test, all addon Lua syntax (excluding third-party libraries), simulator guard and all default simulator regression scripts |
| Offline/CI | `./tests/run.sh` | Every offline test, including artwork rebuilds and mutation-runner harness tests; no simulator |

Use development checks frequently and affected feature checks before completing
ordinary feature PRs. Use integration for changes crossing subsystem boundaries;
repeat `--with-group` for each affected subsystem. Dependency tests and syntax
expand recursively; simulator selections come from the explicitly requested
groups. Identical catalogs merge, an unfiltered catalog dominates a filter, and
distinct positional subsets remain separate. Unrelated visual catalogs stay out.

Require the unchanged **full gate** for release candidate certification, major
shared infrastructure changes, high-risk migrations, changes affecting global
initialization or saved-data contracts, and explicit owner requests. Record the
trigger; do not make an addon-wide simulator regression a blanket requirement
for ordinary PRs. Full discovery, every default simulator launch, screenshots,
replays, deliberate incorrect expectations and compatibility checks remain intact.
The `release` profile adds `tools/release.py check` against an existing candidate
archive and its packaging metadata. Missing inputs fail before executing tests.
It checks, never builds, stamps, publishes or deploys. The existing CI packaging pipeline remains required. Real-client checks are
owner-directed and are **not** mandatory completion, PR, or release gates; record
any client-only uncertainty and suggested checks without claiming native evidence.
A cloud run never sets `automated_release_gate_passed` or `local_milestone_passed`
true.

Do not repeat an unchanged full run merely to refresh evidence. Diagnose failures
with the smallest reproducing module/scenario, preserve the original report and
logs, state the hypothesis and rerun only affected checks after a relevant fix.
Broaden when the fix crosses boundaries. Retry nondeterminism only for a stated
investigation; a clean retry does not erase a failure. Keep commit, working-tree
fingerprint, fixture bytes and relevant runtime/environment constant in timing
comparisons. Avoid overlapping heavy mutation campaigns and simulator benchmarks.
Documentation-only evidence updates do not require another addon-wide run when
tested executable inputs are unchanged. Focused success is never a full PASS.

## Select a feature

Replace `workshop-settings` with one of these nonempty groups:

| Group | Direct scope |
|---|---|
| `ledger` | Gold recorder, exact auction/vendor evidence, mailbox settlement, existing AH controller/reads/Owned/Sell/lifecycle, diagnostics and Ledger page; smoke and normal/narrow auction Ledger poses |
| `workshop-settings` | Workshop settings, Tooltip Designer, worth layout/tips and Workshop window |
| `item-advisor` | Advisor recommendations, selling and disenchant evidence, discovery, page, market/crafting dependencies and selected Advisor simulator poses |
| `workshop` | All Workshop tests and Test Lab tests |
| `auction-preview` | Focused AH shell/replay, Shopping, Market, Sell, Owned, bridge, all six scoped-reader states and incorrect-expectation captures plus lifecycle; omits additional visual/stress poses |
| `auction-house` | Standalone Auction House preview, existing auction safeguards and Workshop dependencies |
| `crafting` | Crafting, shopping, stock, planner, strategy and compact views |
| `market` | Prices, distribution, history, valuation, schema and automatic scans |
| `market-performance` | Thirteen fast deterministic pricing/partition/estimator/incremental-engine/diagnostics/reference/catalog/experiment modules; no large benchmarks or simulators in development selection |
| `reminders` | Reminders engines, designer, settings and artwork |
| `loot-rolls` | Loot Rolls rules, cards, automatic rolling and settings pages; the synthetic-roll simulator catalog is run by hand with `bash tools/simlab/loot.sh` |
| `fishing` | TwichUI Fishing (load-on-demand `TwichUI_Fishing`) and its core launcher: the fishing key's decisions, reel overrides and combat, lures, gear snapshots and restoration, catch attribution, the container queue, sessions and saved data; Stage 2's Fishing Mode (camera, fading, the Quiet screen hold, cast bar, catch list, notifications, recovery) and its artwork; no simulator catalog (offline captures: `tools/render_fishing_hud.py`) |
| `healer-watch` | Healer monitoring/alerts, guarded hover communication and Settings |
| `execute-range` | Execute threshold configuration, verified EllesmereUI adapters, overlay lifecycle and settings/sharing |
| `navigation` | Navigation, maps, pins, NPCs and guild locations |
| `settings` | Settings contracts, framework, pages and feature settings |
| `shared-ui` | Frame styling, notifications, themes, reachability and shared window components |
| `core` | Initialization, defaults, profiles, persistence, routing, storage and group/guild diagnostic isolation |
| `layouts` | Layouts, wizard, import tools and reproducible artwork |
| `test-tools` | All Python test infrastructure tests |
| `verification-tools` | Four runner/simulator infrastructure modules plus ten representative Workshop, Settings, Reminders and AH launches; scoped infrastructure validation |

Preview exact selections without executing anything:

```sh
./tests/run.sh fast workshop-settings --list
./tests/run.sh feature workshop-settings --list
./tests/run.sh full --list
```

`tests/groups.json` owns the explicit test patterns, syntax boundaries, shared
unit-test dependencies and feature simulator selections. Unmatched patterns or
unknown groups fail instead of silently running nothing. Feature dependencies
expand recursively and are deduplicated. Simulator choices belong to the
requested feature; dependency tests do not trigger unrelated simulator catalogs.
A `workshop-settings` feature run includes all Workshop and shared settings/core
unit tests, then `design`, `craft` and `wrong` simulator launches, preserving
replay comparison and the deliberately wrong expectation. Fast checks use the
12 direct test files, including experimental opt-in migration and service lifecycle
preservation. The infrastructure audit's older 11-file measurements remain historical.

Add new feature tests to their group's patterns. Full/CI discovery automatically
includes **all** `tests/test_*.lua` and `tests/test_*.py`, including future files;
there is no feature allowlist in full discovery. A feature group is conservative,
not an automatic changed-files dependency analyzer. Broaden verification when a
change reaches outside the documented boundaries.

## Workers, failures and artifacts

The default uses two offline workers, capped at four with `--jobs 1..4`.
`test_layout*.lua` files run individually after the other workers finish: the
baseline reached approximately 3.9 GiB for a single Lua process. Separate Lua
processes preserve global isolation; each test receives a private temporary
folder. Python test fixtures use disposable folders and ephemeral local ports.
For serial debugging:

```sh
./tests/run.sh --jobs 1
./tests/run.sh feature workshop-settings --jobs 1
```

Logs are printed in deterministic discovery order. A failed test prints its full
captured output once, retains its exit code in the report, and makes the runner
fail. Lua still requires `PASSED` or `OK`, a zero exit code and no `ERROR:` marker.
Timeouts kill the test's process group and fail; SIGINT/SIGTERM stop running
children. Python modules are never rerun just to obtain a traceback. Missing
interpreters or tooling are errors, not skipped coverage.

Each invocation prints its unique directory under `test-output/verification/`.
It contains `<test filename>.log`, simulator suite logs, `syntax.log` and
`report.json` (selection, timings, worker counts, exit codes, Python case counts,
actual simulator launches/checks and pass/fail). The report also records the requested verification profile, selection reason, omitted catalogs, coverage classification, source commit and working-tree fingerprint before/after, exit status, and the twenty slowest offline modules. A changed source fingerprint fails the run. Interrupted/error runs retain an explicitly incomplete, failed report; they cannot become certification evidence. Names inside that directory are
stable; separate runs cannot overwrite one another. Successful temporary test
folders are removed. Do not commit raw generated results; compact reviewed benchmark evidence may be archived under `docs/evidence/` for infrastructure audits.

Verification clears Lua/Python injection paths, fixture-generation opt-ins and
seed/count overrides so an inherited environment cannot overwrite contracts or
reduce randomized coverage. For debugging a single seed or intentionally
regenerating an audit fixture, use the existing direct-test command from its
source documentation and review the resulting diff. A single test remains:

```sh
(cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_workshop_worth_designer.lua)
```

## Simulator workspace

Use the read-only installation through the local launcher:

```sh
bash tools/simlab/run.sh smoke
bash tools/simlab/run.sh auctionproof
bash tools/simlab/run.sh auctionpreview
SIMLAB_ONLY='design craft wrong' bash tools/simlab/run.sh workshop
SIMLAB_ONLY='idle mixed' bash tools/simlab/run.sh testlab
bash tools/simlab/run.sh settings workshop
bash tools/simlab/run.sh reminders editor narrow
```

`WOWSIM_INSTALL` selects the installed lab (default: sibling
`wow-ui-sim-lab`). All mutable state lives in `test-output/simlab/`; the installed
binary/dependencies are mounted read-only and the existing cache is copied once
as a disposable seed. No setup/download or simulator source change is performed.
The installed game assets remain read-only. `SIMLAB_WOW` may select their path.

A lock refuses simultaneous runs against the same mutable workspace. Default
simulator execution stays **serial**. Opt-in `--sim-jobs 2` uses separate lane
workspaces under `test-output/simlab-workers/worker-1` and `worker-2`, each with
its own roots, fixtures, cache, home, WTF, artifacts and lock. Whole catalogs are
assigned to fixed lanes; scenarios sharing state within a catalog remain serial.
Admission requires at least four quota CPUs and 8 GiB currently available under
host/cgroup limits; this is a guard, not a kernel memory reservation. Serial mode
remains supported on smaller hosts. Offline `--jobs` never raises simulator
concurrency. Compare serial/parallel transcripts and replay/incorrect-expectation
controls before adopting parallelism for a new workload. No higher simulator
worker count is supported. Every launch starts a new
simulator with `--no-saved-vars`; one immutable addon stage is reused only within
a script invocation, and a fresh invocation always replaces it. Set
`SIMLAB_STAGE_ONCE=0` on the local launcher to debug original per-launch staging.
The filesystem guard still refuses the game, home, repository and arbitrary
in-repository paths; the sole exception is this dedicated marked workspace.
Do not edit the checkout or create unrelated artifact files during a scenario:
the existing repository-status guard intentionally treats such changes as a
failed run.

The diagnostics script includes both unguilded-solo (strictly zero messages) and
guilded-solo (exactly one validated own-position GUILD packet) cases. Party
departure does not imply guild departure. See [the diagnostic fixtures](simulator-lab.md#diagnostics-party-membership-and-guild-membership-are-independent).

Full verification clears inherited `SIMLAB_*` filters and synthetic settings
options (preserving the game path), and ignores `WOWSIM_LAB`, so it cannot be
silently narrowed. It runs every original default pose and original negative
control for `smoke`, `interact`, `diagnose`, `workshop`, `testlab`, `settings` and
`reminders`, plus the AH-1a `auctionproof` synthetic lifecycle catalog and the independent `auctionpreview` catalog, including the settings catalog discovered by the scenario. It does
not replace replay checks with pose-only launches. `guild_bank_preview.sh`
remains a manual, parameterized exploratory capture: it has no default catalog
or regression verdict and was never part of the automated suites.

Direct historical scripts still accept `WOWSIM_LAB` and write there. Use the
local launcher when the separate installation must remain read-only. Selected
Workshop/Test Lab verdicts explicitly say **FOCUSED ONLY** and still enforce all
assertions, expected steps, image checks and classified-error rules for the
selected launches. An unknown selection fails; Workshop's `wrong` requires the
`craft` launch for comparison.

Simulator-tested means handler/state checks over synthetic data and structural
screenshots. It does not prove real pointer input, appearance, fonts, combat,
taint, protected actions, messaging delivery or reload persistence. Those remain
real-client checks; screenshots here are not visual acceptance.

AH-1a's `auctionproof` uses four fresh launches (Workshop unloaded, replay,
loaded, deliberate wrong expectation). Its native root and auctioneer/combat
boundaries are synthetic; it does not establish native AH search or fallback
compatibility. `feature core` selects it alongside smoke/diagnostics. Exact
coverage and the pending client gate: [lifecycle proof](workshop/auction-house/lifecycle-proof.md).

## Mutation policy

Campaigns remain separate from routine checks and full regression; the offline
suite still runs the mutation runner's own tests. For substantive changes to
economic formulas, money/quantity rounding, eligibility or persisted accounting,
use the relevant existing mutation campaign when it protects a meaningful risk.
Add a catalog entry only for a distinct plausible defect not already protected;
do not manufacture new mutations or run campaigns for cosmetic/unrelated edits.
See [the Workshop verification policy](workshop/testing-roadmap.md#verification-policy-for-future-workshop-tasks-claudemd-points-here).
Examples of available targeted campaigns:

```sh
bash tools/mutate.sh --group market
bash tools/mutate.sh --group crafting
bash tools/mutate.sh --group market.dist --jobs 2
bash tools/mutate.sh --all --check
```

Campaigns already support isolated disposable source copies and `--jobs`;
conservative one/two-worker use is appropriate. A narrow campaign is not evidence
for an unrun broader group. Their timeout and baseline-must-pass guards remain
unchanged. No campaign assertions or randomized scenarios are reduced.

Measured baselines, exact benchmark commands, counts and limitations are in
[testing-performance.md](testing-performance.md).

The standalone `auctionpreview` catalog uses stored synthetic observations and
the real shared Shopping planner. It covers normal/narrow/scaled/resized views,
empty/filtered Browse, Shopping and purpose grouping, 3,000-item scrolling,
preview-only native-frame isolation, modeled control reachability, independent
replay and an intentional wrong-expectation control. Its screenshots and hit
rectangles do not establish real input, fonts, combat/taint or server behavior.

## Explicit cloud profile

`--profile cloud` runs the same tier selections with the existing no-game-assets
mode; it never satisfies the full local milestone gate. Default local verification
is unchanged. See [cloud environment compatibility](cloud-environment.md) for
commands, exact limitations, smoke classification and the open PNG encoder gate.

## Measured diagnostics and focused Auction House captures

`--profile local|cloud` selects the environment; the positional profile selects
coverage. Existing `fast`, `feature`, `full` and no-argument commands retain their
coverage. `development` aliases `fast`. `release --list` previews the full plan
without needing archive inputs.

```sh
./tests/run.sh integration market --with-group crafting --list
./tests/run.sh feature auction-preview --profile cloud --measure
SIMLAB_ONLY='shell replay wrong' bash tools/simlab/run.sh auctionpreview
```

The new AH filter validates names, refuses duplicates and requires `shell` when
`replay` or `wrong` is selected. Selected verdicts read only selected artifacts and
print FOCUSED ONLY. Default invocation executes all 49 launches (including five chart review poses), retaining every
original expectation and adding three Companion compatibility poses. Narrow AH captures preserve every check for each selected
launch; they do not certify omitted resizing, scaling, metadata/error and long-list
poses. Use `auction-house` or full/release for the complete existing catalog.

The Market feature profile also selects `companionvalid`, `companionnewer` and
`companionolder`: validated receipt provenance, correctly directed update guidance
and preservation of the active generation/receipt/records on refusal. These use
synthetic data in fresh simulator launches; they do not establish persistence
across a game-client reload or acceptance of an actual installed Companion.

Opt-in `--measure` adds per-offline-module and per-native-launch telemetry using
`tools/measure_command.py`. It samples descendant RSS and CPU ticks every 100 ms
and records reaped-child counters separately. PID namespace boundaries can omit
native CPU/RSS from reaped-child counters: use the explicitly labeled sampled
tree values for native workload estimates. Short-lived processes may escape
sampling; shared pages may be counted more than once. These are operational
measurements, not exact heap peaks or a per-assertion profiler. Measurement adds
observer overhead; compare equally instrumented, serially scheduled runs.
Native bootstrap and last native timestamps are reported separately; simulated
`GetTime()` is never interpreted as CPU or wall time. Artifact PNG names and
per-launch assertion totals are retained. No process reuse or simulator worker
parallelism is enabled by `--jobs` or `--measure`.

The reproducible infrastructure benchmark selection is:

```sh
./tests/run.sh feature verification-tools --profile cloud --measure --sim-jobs 1
./tests/run.sh feature verification-tools --profile cloud --measure --sim-jobs 2
```

Run these sequentially on frozen source, with no competing verification activity.
This is ten launches across four representative catalogs, including Workshop and
AH replay/negative controls. It is not the complete full/release gate. Results
and resource limits are in [the verification audit](testing-verification-audit.md).

## Automatic release isolation checks

`./tests/run.sh development release-tools` covers mocked release planning/publishing,
archive contracts, artifact identity/retry regressions and workflow invariants. No live
CurseForge upload endpoint is used. PR/main CI selects this for release/docs-only changes;
unmapped or unreliable scope falls back to complete offline discovery (`./tests/run.sh`).
No ordinary CI invocation runs the full simulator or release-certification tier.
Manual main dispatch additionally produces an uncertified internal package even during
the publication hold. Protected promotion is implemented separately; static workflow checks do not prove
owner-side GitHub environment configuration or a live approved publication.

Release-isolation campaign (2026-11-16): 52 unit/mock cases passed via the focused
runner in 6.057 s (46 release-tool cases plus 6 isolation cases); no simulator run.
The exact pinned packager built an internal seven-addon archive from implementation
commit `e6d8c9e8e6fa605dfc413eabb320d2fc6d9068f1` in 80.668 s using `-d`.
Archive checks, initial seal and re-seal passed. The ZIP SHA256 was
`4f7b817440278472a060e239afaf860363a2c143c4f8941a03815dac2047e04b`.
Training data matched committed source after the packager's existing LF-to-CRLF
conversion (the initial literal-byte comparison detected that expected conversion).
YAML parsing confirmed PR/main event/job structure. This is local/mock and build-only
evidence, not an Actions dispatch, environment approval, live publisher test or release
certification. The first baseline test attempt had three sandbox socket-permission
errors; the focused runner subsequently passed with localhost fixtures permitted.
No live CurseForge upload endpoint was contacted. Future promotion still requires
an end-to-end approved immutable-artifact rehearsal and the full candidate/client gate.

## Source-to-test guidance

Ask the runner for advisory group matches before choosing a plan. Pass one or more
repo-relative file paths from the diff. The command reads existing syntax and test
globs in `tests/groups.json` and prints preview commands without running tests.

```bash
./tests/run.sh --recommend 'TwichUI_Settings/pages/Reminders.lua'
./tests/run.sh --recommend '!!!TwichUI/FrameLook.lua' tests/test_test_runner.py
./tests/run.sh --recommend docs/testing.md
```

A syntax match identifies files checked by a group. Use [architecture](architecture.md)
to review ownership and actual consumers, especially for shared files and overlapping
globs. Removed files and paths outside the globs are reported as unmapped. Use the
guidance below to choose the checkpoint profile and review the selected plan.

- Reminders config or its settings page: `feature reminders`.
- Market bridge/schema/receipt changes: `feature market`; inspect the pinned
  contracts and scoped Lua/Python tests. Preserve integrity negative controls.
- AH preview lifecycle: `feature auction-preview`. If editing shared Workshop
  suspension/services, add `--with-group workshop` using `integration`.
- Workshop settings/Tooltip Designer: `feature workshop-settings`.
- A shared style change affecting Settings and Reminders:
  `integration shared-ui --with-group settings --with-group reminders`.
  Enumerate all actual consumers; this example does not exhaust them.
- Global `Core.lua` initialization, `Persist.lua`, `Profiles.lua`, SavedVariables
  contracts, high-risk migrations or major shared infrastructure: require the
  existing **full** gate. `development core` is only a diagnostic starting point.
- Unknown/unmapped paths: inspect callers, manifests and full test inventory;
  require explicit coverage review. Use complete offline discovery at minimum
  when scope remains unknown, and the full gate when shared/global risk cannot
  be excluded. Never interpret no matching feature group as sufficient coverage.
- Release tooling: `development release-tools`, plus the release-engineering
  requirements in [RELEASING.md](../RELEASING.md). Documentation-only work uses
  path/link checks and previews; it needs no simulator certification.

Preview any command above by appending `--list`; inspect tests, syntax and selected
simulators before running it. Development omits dependency expansion; feature and
integration expand unit/syntax dependencies, but simulator catalogs come only from
explicitly requested groups. Add consumer groups explicitly for cross-feature work.
For Workshop economic changes, apply the risk-based mutation guidance in
[shared rules](engineering-rules.md) and the Workshop verification policy.

`tools/ci_verify.py` separately selects release-tools for its explicit release/docs
allowlist, and complete offline discovery otherwise. It is not a source-to-group
analyzer. Advisory matches have no effect on CI selection or test coverage.

## Evidence retention

See [test evidence retention](evidence/README.md) for bounded CI diagnostics,
permanent evidence, historical path/hash mappings and rollback. Generated outputs
remain ignored; CI refuses newly tracked files under `test-output/`. CI artifacts
expire after 14 days and must not become permanent documentation dependencies.

## AH-7A integration selection

`./tests/run.sh integration auction-house --with-group workshop --profile cloud --measure`
selects the complete AH preview catalog, AH proof/integration, Workshop and Test Lab
regressions plus recursive offline dependencies. `auctionproof` preserves all four
original proof launches and adds six integration launches (normal, replay, narrow,
scaled, restored synthetic native boundary, deliberate wrong expectation). Each new
launch has 131 structured lifecycle/geometry/resource checks. Replay compares
frame-growth deltas; raw global frame totals remain logged because unrelated
Blizzard frames vary between fresh processes. This does not establish real input,
server-session safety, combat/taint or native acceptance. The cloud profile cannot
satisfy local/native acceptance gates. No money/quantity/price logic changed, so
production mutation campaigns are not required for this presentation milestone.

The final affected campaign is recorded in [AH-7A evidence](workshop/auction-house/native-integration.md#automated-evidence-and-performance).
The combined attempt was interrupted by an environment reconnect; completed
catalog verdicts were preserved and the remaining Workshop/Test Lab catalogs ran
in a passing feature profile. Final Host callback hardening and the scoped
Diagnostics preset have their own passing focused checks and simulator evidence.
`auction-house` and `auction-preview` now also select `test_perf_engine.lua` and
the two changed Diagnostics source files. No full/release certification or native
client acceptance is inferred from this campaign.

### Market pending-pricing performance

`./tests/run.sh development market-performance` selects thirteen small production-reader,
pricing, estimator and integrity modules without a simulator. It supplements the
normal affected Market/crafting/consumer groups. Dedicated audit benchmarks remain
opt-in (`tools/measure_market_opportunities.py`), never default test discovery.
[PR1 implementation and comparable measurement procedure](performance/v2-market-pending-pricing-pr1.md).


### Market cold pricing PR2

The existing `market-performance` group now includes contract-3 current/history
laziness, integrity, rollback, priority and elapsed-diagnostics checks. A small
PR workflow runs that same development selection on relevant paths even when a
PR is stacked below main. It does not run the simulator, mutation campaigns or
large fixtures. Local measurement: eight modules in 2.8 s; target under 30 s.

The existing dedicated driver accepts `--contract 2|3` and `--rows` for comparable
Opportunities workloads. `tools/measure_scoped_reader.py --summary-root PATH
--report FILE` runs the existing native-publication summary harness, with one
discarded warm-up and three fresh samples. Both are opt-in. Paired Windows
publication/Lua and protocol tests run in the Market integration workflow.
The 30,000-variant/60-day uneven stress fixture is for on-demand or release
validation, never ordinary development. Exact frozen commands, JSON baselines,
comparison/update policy and observed failures are in the
[PR2 evidence and native acceptance report](performance/v2-market-cold-pricing-pr2.md).


### Incremental Opportunities (PR3)

The existing `market-performance` development group adds deterministic engine and
actual Window/UI lifecycle tests. Its twelve modules passed in 8.012 s on the audit
host. Crafting integration selects the engine/UI tests too. The fast group also includes the existing independent crafting reference and mutation-harness tests, including complete catalog pattern/syntax validation; it does not run the complete mutation campaign. The existing PR workflow uses
the same development command; no large benchmark or simulator entered routine CI.

Use `./tests/run.sh development market-performance --jobs 2` for relevant commits;
use `./tests/run.sh integration market --with-group crafting --with-group market-performance --profile cloud --jobs 2`
at cross-subsystem checkpoints. Preview either with `--list`. The cloud profile
reports native-client and simulator limitations explicitly.

Opt-in `tools/measure_market_opportunities.py --suite opportunities` retains the
20/100/500/1000 matrix. `--contract 2|3`, `--days 2|60`, repeatable `--case`, and
`--scenario single|burst|reopen|filters|scroll|generation|stress` select comparable
workloads; the driver discards one warm-up and defaults to three fresh samples.
`--stress --rows 96 --case opportunities/ui/5000 --scenario stress` adds the large
20-cycle workload, never routine discovery. See the [PR3 report](performance/v2-opportunities-incremental-pr3.md)
for exact before/after commands, operation gates, baseline update policy,
recomputation oracle, memory evidence and retained simulator failures.

Extended memory diagnostics may use `--scenario stress --stress-cycles 60`; cycles default to 20 and remain opt-in. Snapshot fields include memo, price, row and pending counts alongside retained heap.


### Game-ready Market data experiments

The thirteenth `market-performance` module is a small deterministic guard for
**test-only** encoders/providers: source grammar, numeric bounds, exact variants,
unknown/absence, content integrity, warm reuse, cancellation and replacement.
It does not install a format or run the large fixture generator. The normal PR
workflow keeps using the same development selection.

The opt-in generator and measurement driver are
`tools/experiments/market_game_ready.py` and
`tools/experiments/measure_game_ready.py`. Reproduction commands, pinned sources,
raw sample ranges, rejected layouts and interpretation limits are in the
[game-ready investigation](performance/market-game-ready-data-investigation.md).
Run these campaigns explicitly; they are not a new development/release gate.
