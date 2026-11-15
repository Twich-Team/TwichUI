# Development verification

Run from the repository root using native Linux/WSL. Requires Lua 5.1,
`luac5.1`, luabitop and Python 3. The simulator also needs the existing
installation and the dependencies in [simulator-lab.md](simulator-lab.md).
No new Python packages are required.

| Tier | Command | Evidence |
|---|---|---|
| Fast development | `./tests/run.sh fast workshop-settings` | Direct feature tests and Lua syntax; no simulator |
| Feature checkpoint | `./tests/run.sh feature workshop-settings` | Feature tests, shared dependency tests/syntax and selected simulator regressions |
| Full milestone | `./tests/run.sh full` | Every offline test, all addon Lua syntax (excluding third-party libraries), simulator guard and all eight default simulator regression scripts |
| Offline/CI | `./tests/run.sh` | Every offline test, including artwork rebuilds and mutation-runner harness tests; no simulator |

Use fast checks frequently during implementation, feature verification before a
checkpoint commit, and **full verification before declaring a major milestone
complete**. Run full verification earlier for changes to shared architecture,
load order, saved-data boundaries or other high-risk code. Focused evidence is
never complete regression coverage. Record the tier and actual outcome.

## Select a feature

Replace `workshop-settings` with one of these nonempty groups:

| Group | Direct scope |
|---|---|
| `workshop-settings` | Workshop settings, Tooltip Designer, worth layout/tips and Workshop window |
| `item-advisor` | Advisor recommendations, selling and disenchant evidence, discovery, page, market/crafting dependencies and selected Advisor simulator poses |
| `workshop` | All Workshop tests and Test Lab tests |
| `crafting` | Crafting, shopping, stock, planner, strategy and compact views |
| `market` | Prices, distribution, history, valuation, schema and automatic scans |
| `reminders` | Reminders engines, designer, settings and artwork |
| `navigation` | Navigation, maps, pins, NPCs and guild locations |
| `settings` | Settings contracts, framework, pages and feature settings |
| `shared-ui` | Frame styling, notifications, themes, reachability and shared window components |
| `core` | Initialization, defaults, profiles, persistence, routing, storage and group/guild diagnostic isolation |
| `layouts` | Layouts, wizard, import tools and reproducible artwork |
| `test-tools` | All Python test infrastructure tests |

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
seven direct test files. This is the starting workflow for Workshop Settings 2.0;
no Settings 2.0 feature implementation is part of this infrastructure change.

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
actual simulator launches/checks and pass/fail). Names inside that directory are
stable; separate runs cannot overwrite one another. Successful temporary test
folders are removed. No generated results should be committed.

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

A lock refuses simultaneous runs in the local workspace. Root, fixtures, cache,
home and WTF are shared there, so simulator execution stays **serial**. Offline
worker settings never increase simulator concurrency. Every launch starts a new
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
`reminders`, plus the AH-1a `auctionproof` synthetic lifecycle catalog, including the settings catalog discovered by the scenario. It does
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

Campaigns remain separate from routine checks and full regression, matching the
previous suite. The offline suite always runs the mutation runner's own tests.
For Workshop money, quantities, rounding, ordering or eligibility changes, keep
[the verification policy](workshop/testing-roadmap.md#verification-policy-for-future-workshop-tasks):
run the matching campaign and add a realistic defect model. For example:

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
