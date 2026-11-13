# Workshop testing roadmap

This plan covers how TwichUI Workshop's correctness, regressions, performance and real-client behaviour are verified. It is for anyone, person or agent, who implements the milestones below. It records what existed on `feature/workshop` at `d09e6dcb` (2026-11-12) and what to build next. Sections A to G are the plan as written then; **section H records what has been built (M1 to M6) and found.** `docs/workshop.md` remains the feature reference, and `docs/simulator-lab.md` and `docs/diagnostics.md` remain the tool references.

**Baseline checked 2026-11-12.** `feature/workshop` is the same commit as `origin/feature/workshop` and `origin/main`, and it descends from the `v1.3.0` tag. Every `feature/workshop-foundation` commit (86fea359 market foundation … b34476a7 third UI pass, 57e767fd art) is contained in it, so nothing is missing and no integration is needed.

---

## A. Current coverage assessment

### What exists

| Layer | What it is | Cost (measured here) |
|---|---|---|
| Offline unit tests | 11 files `tests/test_workshop*.lua`, about 6,100 lines, against 11,600 lines of Workshop code. Plain Lua 5.1, a fake game at the API boundary (`tests/harness.lua`, `tests/mi_mock.lua`), and a virtual clock for the scan | about 10 s of CPU for the Workshop files (6.7 s of it is `test_workshop_market_scale.lua`). **The whole suite took 5 min 14 s** (196 files pass; CLAUDE.md and `.clinerules` said "about 10 s" and were corrected with this plan) |
| Scale test | `test_workshop_market_scale.lua`: 250,000 synthetic records, 30,000 items, eight daily scans, 150 further days, three markets. It prints `os.clock`/`collectgarbage` figures and asserts loose limits | included above |
| Simulator | `tools/simlab/workshop.sh`: the real addon in wow-ui-sim v0.1.37, `/tui workshop`, all four pages and the tooltip designer over fake game data, 13 launches (12 poses plus a negative control) | **3 min 26 s wall**. Each launch uses 26.55 of the 30 simulated seconds (`Lab.BUDGET`) |
| Diagnostics | `R.Perf` scopes (`workshop.load/read/bank/worth/scan/render`), 11 `workshop.*` gauges, captures, findings, A/B comparison and redacted export (`TwichUI_Diagnostics/`) | passive: it measures real play. **It has never run in the game** (docs/diagnostics.md) |
| Real client | the player confirmed that the window opens and works (2026-11-09) and reported milestone 2 done without listing what was checked. In the third pass the player found a nonworking Opportunities Add button and missing row hover | none of the market foundation, Shopping or the third pass has been tried in the game |

### What the tests prove well (unit-tested)

- **The expected values are independent of the code.** They are literals typed from hand arithmetic, often with the arithmetic in the comment. No test checked here takes its expected value from production code.
- **The boundaries are covered.** Unknown values are never zero, as are secret, NaN, negative, fractional and out-of-range values. Held newer versions, bounds, corrupt saved records, legacy recipe-only prices, the scan's refusal, throttle, interruption and stale-timer paths, the commit job's all-or-nothing behaviour, and the window's events (registered only while it is shown) and pool bounds are all tested.
- **A mutation probe.** On 2026-11-12, 19 hand-picked mutants were run against throwaway copies of the Workshop folder (rounding, allocation order, quote boundaries, cut, history folding, the Compare reference window, Trend, ties, stacks, batch accounting). One could not be applied because its pattern was not unique. **16 of the other 18 were killed and 2 survived.** Both survivors are in `Market.Trend`: changing the window's first day from `>=` to `>`, and rounding negative percentages one way. `Trend` has no production consumer yet. (M2 killed both, and found the second one was a real defect: see H.) Ten of the 16 killed mutants were caught by only one test file, so most of these rules have a single line of defence.

### Limitations, and why the button and hover failures got through

1. **Unit tests call handlers, not controls.** `test_workshop_window.lua` runs `btn:GetScript("OnClick")(btn)` directly, which bypasses shown, enabled and mouse state. Its stand-in `EnableMouse` is a no-op that records nothing, `IsMouseOver` is always false, and `GetStringWidth` is `#text * 6`. `MIFake`'s `__index` answers any unknown capitalized method with a silent no-op, so a misspelt or Forever-absent widget method passes offline. Only the simulator can catch that.
2. **The simulator is handler-level.** `Button:Click()` runs scripts, and hover means calling `OnEnter`. The third pass's hit test is *emulated* from `GetRect`, strata, levels and `IsMouseEnabled`, over Workshop frames only. `GetRect` ignores `SetHitRectInsets`, which `Style.lua:330` uses. The test cannot order equal levels or see non-Workshop occluders, and nothing observes which frame the real client puts under the pointer. That is exactly the evidence that was missing: both layers proved that the handlers work and could not prove that the control is reachable. **The in-game cause of the Add-button failure is still unconfirmed.**
3. **Reload is a model.** "Reload" means a deep copy of the saved table handed to a fresh mock client. It does not test serialization, the moment the game fills in a load-on-demand addon's SavedVariables, or a real `/reload`.
4. **The load order is duplicated.** Each Workshop test file carries its own hand-written `FILES` list instead of reading `TwichUI_Workshop.toc`, which only 2 tests read. A load-order dependency can drift unnoticed offline; only `smoke.sh`/`workshop.sh` would catch it.
5. **No randomized testing of Workshop.** The scale test is seeded, but no invariant is checked over generated inputs, and no reference model exists. Elsewhere in the suite, `math.random` is libc-dependent, so a failing seed may not reproduce on another machine.
6. **Performance evidence is offline only.** The figures come from plain Lua on the development machine. There is no recorded baseline, no comparison procedure, nothing from WoW's interpreter, and no frame-time measurement.
7. **The simulator has no room left.** All 13 launches rerun the same 396 checks before posing, so 12 of the 13 runs repeat the same evidence, and a new step does not fit the 30 s budget.
8. **A market-selection rule needs a product decision.** With the auction house closed, `Market.Source` uses the realm's newest market of *any* side (`PR.Newest`, pinned by `test_workshop_prices.lua:162`). A Horde character can therefore be shown Alliance prices, and the market's name appears only in tooltips. See "Unresolved decisions".
9. **An optimistic cost rule.** `Prices.Quote`'s `estimate` (price × qty beyond the cheapest listing's quantity) is the least the materials could cost, so the Opportunities profit is an upper bound in that case. It is flagged (`cheapest`). The saved next-higher price (`x`) is not used to tighten it. This is a modelling choice; reference tests should make it explicit.

---

## B. Risk-based coverage matrix

Priority: **P1** means wrong money figures or lost data are plausible, **P2** means wrong advice or a broken flow, **P3** means low impact or already strong. RC means real-client testing is required.

| Subsystem | Existing evidence | Most important missing tests | Method | Pri | RC |
|---|---|---|---|---|---|
| Auction record batch (`Prices` Unit/Batch/Entry) | strong deterministic tests; mutants killed | invariants over generated listings: the cheapest price is the true minimum of the exact fractions, `q` is the sum at the minimum, `x` is the next distinct copper value, `used + invalid + noBuyout == read` | reference model (sort all listings by exact fraction) + property test | P2 | no; RC for real record shapes and `hasAllInfo` rate |
| Saved markets & commit job | strong: kept/held/cut/legacy/bounds, all-or-nothing | interrupted job at every step index (property), the 3-market eviction order under ties, the round trip through real saved-variable text | property + serializer round-trip helper | P1 | yes: real `/reload`, file size |
| History & statistics (`History`, `Market.Stats/Trend/Compare/Series/Observed`) | strong for History; **Trend: 2 survivors**; Compare boundary killed by one file | a full-day-list reference model compared on random scan calendars (gaps, clock back, folding, expiry); Trend boundary and negative percent | **reference model** + property + regression | **P1** (future trends build on it) | no |
| Market selection & isolation | markets kept apart; variant refusal; legacy scope | which market a character sees with the house closed (side policy); every view reads the same market in one draw | deterministic, after the product decision | P2 | yes: `UnitFactionGroup("npc")` at a neutral house |
| Scan state machine (`Scan.lua`) | strong against a fake house with a virtual clock | random event interleavings (update storms, close at each phase, second click, throttle flips) checked for invariants: ends once, no timer outlives its token, nothing written before Apply | randomized state-machine test | P2 | **yes**: event cadence, throttle, the 15-minute claim, `hasAllInfo` |
| Craft estimate & Opportunities (`Estimate`, `Quote`, `Op.*`) | deterministic, cut path, ranges, unknown last | an independent spreadsheet-style reference over generated recipes; sort stability; profit-bound semantics when `cheapest` is set | reference model + property | **P1** | no; RC for the real cut (mail invoice) |
| Materials & stock allocation (`Materials.Rows`, `W.Split`, `Stock`) | strong (storage tests: 772 lines) | invariant: taken from bags + bank + guild + still needed equals the need, no layer goes negative or exceeds what it holds; `InCycle` on generated graphs | property + small reference | P1 | RC for guild withdrawal facts |
| Shopping planner (`Shopping.Plan`, `Vendor.Quote`) | strong deterministic; 2 of its 3 mutants were killed by one file only | **invariants on generated queues**: nothing owned spent twice, cash ≤ economic cost, the suggestion is never costlier than an option it beat; a brute-force reference on ≤ 6 materials | **reference model** + property | **P1** | no |
| Persistence (Queue/Known/Vendor/Storage/`TwichUIWorkshopDB`) | strong: bounds, held, corrupt, per character | text round trip; a future-schema migration harness (ordered, repeatable, idempotent, never downgrades) before the first schema change | serializer helper + migration fixtures | P1 | **yes**: reload, logout, LoD SavedVariables timing |
| Recipe reading (`Observe`, `Watch`) | strong vs fake `C_TradeSkillUI` | none offline of note | — | P3 | **yes**: real recipe API, filters, ready state |
| Bank recorder (`Bank.lua`) | strong vs fake bank and guild bank | none offline of note | — | P3 | **yes**: event order, unsent-tab answers |
| Window & controls (`Style`, `View*`, `Window`) | handler-level unit + simulator; emulated hit test; pool and frame bounds | **reachability** (shown + enabled + mouse-click-enabled + top at its centre, insets included) for every actionable control; repeated-cycle growth; the real client's frame under the pointer | offline `Press` helper, simulator reachability v2, **in-game pointer probe** | **P1** (the observed failures) | **yes** |
| Worth tooltip (`Worth`, `WorthLayout`, `WorthTip`) | deterministic, designer | repeated-evaluation cost; variant-link classification on real links | bench + in-game probe | P3 | yes: `TooltipDataProcessor` timing |
| Launcher / LoD | launcher tests at login/combat/failure | — | — | P3 | yes: first open from a packaged install |
| *Future:* buy/post/cancel flows | none | state machines with explicit player confirmation, failure injection, never acting without a click | fake API + state-machine tests + simulator | P1 | **yes, always** |
| *Future:* Ledger & attribution | none | replay of event fixtures; deduplication of mail/AH events; economic vs cash profit; an unknown cost basis stays unknown | reference replay model + fixtures | P1 | yes: real event payloads |
| *Future:* multilevel craft-vs-buy, levelling routes, recommendations | none (one-level planner only) | an exhaustive reference on small graphs; cycles; a minimum worthwhile gain; conservative output when evidence is thin | reference model + property | P1 | no for algorithms |

**Where independent reference models pay off most**, in order:
1. `Shopping.Plan`, and later the multilevel planner. Allocation and comparison logic is where plausible-looking wrong answers hide, and a brute force over small instances is easy to write and obviously correct.
2. History plus `Market.Stats/Trend/Compare`. Two-tier compression means the answers derive from a lossy store; a reference that keeps every daily value shows exactly what compression may and may not change.
3. The craft estimate over generated recipes. The arithmetic is simple, so the reference is short and cheap. It also pins the profit-bound semantics.
4. Later, the Ledger: deduplication and attribution, replayed from fixtures.

The batch and `W.Split` need only property tests: their invariants *are* their reference.

---

## C. Test Lab architecture (`TwichUI_TestLab`)

**Purpose.** Run selected TwichUI code and client probes *inside WoW: Forever*, show the results and produce a pasteable report. It does not re-run the offline suite: the mocks cannot load in the game, and the game cannot read files.

### Structure

```
TwichUI_TestLab/                    (sibling addon at the repository root; never packaged)
  TwichUI_TestLab.toc               LoadOnDemand 1, RequiredDeps !!!TwichUI, no SavedVariables, Interface copied from the core .toc
  Lab.lua                           R.TestLab: case registry, safety classes, forbidden-action list
  Runner.lua                        coroutine runner: frame slices, Stop, timeouts, combat stop
  Report.lua                        text report (fixed header, one line per case, a facts block)
  Fixtures.lua                      pure, deterministic synthetic data (own PRNG); also loaded by offline tests and benchmarks
  Window.lua                        category list, Run / Stop, progress, results, copy box
  cases/*.lua                       Core, Market, Crafting, Client, UI, Bench (one file per category)
```

### Loading

- It is never loaded at login and does nothing until opened. **Milestone 1** opens it with `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`. Loading opens its window and registers `/tuilab` to reopen it, with no change to the released core. A hidden `/tui lab` in the core is a decision (see "Unresolved decisions").
- Categories that need the Workshop call the existing `R.WorkshopLauncher.Load()`, which refuses in combat. There is no `.toc` dependency on the Workshop: the Lab can run core-only cases, and it does not rely on how Forever chains load-on-demand dependencies, which is unverified.

### Isolation and safety

Every case declares one class, and the registry refuses a case without one:

| Class | May do | Examples |
|---|---|---|
| `pure` | call production functions **with explicit inputs only**, on `Fixtures` data | `PR.Unit`, `PR.NewBatch`, `PR.Lookup(market, item)`, `PR.Quote`, `PR.Estimate(rec, lookup, rate)`, all of `History`, `Market.Price/Quote/Stats/Trend/Compare/Series/Observed` with `opt.market = <synthetic table>` and `opt.now`, `Materials.Combine/Rows(entries, have, stock)`, `W.Split`, `Stock.Craft`, `Shopping.Plan(inp)` / `Explain` / `WhyNot`, `Op.Rows/Select`, `Worth.Evaluate/Recommend`, `WorthLayout.Rows/Lines(…, layout)` |
| `readonly` | read live game state or real saved data; must leave a fingerprint unchanged | the saved-data integrity check (counts, versions, bounds, every history string decodes), `Stock.Sources`, `WL.Get`, `Market.Source`, API presence |
| `owned` | create and reuse Lab-owned frames, never Blizzard's or the Workshop's | mouse-flag probes, a disabled button's `Click()` |
| `guided` | ask the player to do something themselves, then observe it read-only | "hover the Add button": `GetMouseFoci()` reports the frame path under the pointer |

**Never callable from any case:** `PR.Commit`/`BeginCommit`/`Apply`, `Queue.*` writes, `Known.Store`, Vendor and Storage writes, Session actions, `Scan.Start` (it sends `ReplicateItems` and uses up the player's scan), `Observe.OpenRecipe`, and every purchase, bid, post, cancel, mail, trade, destroy, disenchant or item-use API.

**Saved-variable globals** (`TwichUIDB`, `TwichUIWorkshopDB`, `TwichUIDiagnosticsDB`) are never reassigned or swapped for fixtures. A disconnect during a swap would make the game save the fixture over the player's data.

**Enforcement:**
- An offline static test scans `TwichUI_TestLab/**/*.lua` for the forbidden names and for assignment to the saved roots.
- `readonly` cases are bracketed by a cheap fingerprint of the saved roots (top-level keys, `v` fields, each market's `at`/`n`).
- No Blizzard function is wrapped or hooked, to avoid taint. No network or addon messages are sent.

### UI workflow

1. Open: the window builds on first open; Esc closes it via `UISpecialFrames` (never `RegisterGameMenuEscHandler`).
2. Choose categories: checkboxes, with the cost of each shown.
3. **Run**: a progress bar shows "case n of m", the current id and elapsed time.
4. Results appear as a list with the existing `status-done`, `status-failed` and `status-current` icons (`media/guides/`).
5. **Stop** is always visible while running.
6. **Copy report** fills a selected EditBox. The game gives addons no clipboard, so the player presses Ctrl-C.

Guided cases show a one-line instruction and a countdown of at most 15 s.

### Registration

```lua
TL.Case{ id = "market.unit.round-up", cat = "core", class = "pure", needs = { "workshop" }, budget = 2,
  run = function(t) local PR = t.W.Prices; t:Same(PR.Unit(301, 3), 101, "a stack that does not divide rounds up") end }
```

The case API provides:
- `t:Same`, `t:Check`, `t:Skip(reason)`
- `t:Fact(key, value)`: a reported number, not an assertion
- `t:Yield()`: a cooperative slice boundary
- `t:Measure(label, fn, opts)`: for benchmarks (section E)

`pure` cases contain no WoW calls, so `tests/test_testlab.lua` loads the same case files under the mock and runs them offline in `./tests/run.sh`. **Each such case is one definition run in two interpreters.**

### Execution and cancellation

- One Lab-owned frame has an `OnUpdate` only while a run is active, and it is cleared at the end.
- Each case is a coroutine, resumed once per frame for a slice (default 5 ms by `GetTimePreciseSec`, falling back to `debugprofilestop`; `debugprofilestart` is never called).
- A case that errors is marked `error` with its message, and the run continues.
- Lua 5.1 cannot yield across `pcall`, so cases must not call `t:Yield()` inside one. The runner itself relies on `coroutine.resume` to contain errors.
- Bounds: each case has a timeout (default 10 s, benchmarks up to 60 s) and each run has a cap (5 min). **Stop** takes effect at the next slice and marks the remaining cases `stopped`.
- A run is refused in combat, and `PLAYER_REGEN_DISABLED` (registered only during a run) stops it. Nothing runs at load or on a timer, and no background benchmarking happens.

### Report format (plain text, about 4 to 30 KB)

```
TWICHUI-TESTLAB REPORT schema 1
client 1.60.1 build <n> interface 16001 | TwichUI <ver> | Workshop <ver> loaded | TestLab <ver>
run: core,client | 24 cases: 22 pass, 1 fail, 1 skipped, 0 error, 0 stopped | 0.41 s | slices 31, worst 6.1 ms, worst frame 38 ms
labels: client = observed in WoW: Forever | synthetic = production code in the client's Lua on synthetic data | guided = observed with the player's help | not run
FAIL  market.trend.negative-percent  synthetic  expected -33.4, got -33.3
PASS  client.api.precise-clock       client     GetTimePreciseSec present
SKIP  ui.pointer.add-button          guided     player did not hover within 15 s
facts: client.clock.resolution_ms=0.0001 client.profiler.enabled=true ...
```

**Redaction:** the report contains no character, realm, guild, account or group names, no chat, no item links and no saved values. It holds counts, ids of Lab-generated fixtures, and TwichUI frame keys only. Above 48 KB, reuse Diagnostics' `J.Pieces` (Adler-32 checked) instead of writing a new splitter.

### Packaging exclusion

- Add `TwichUI_TestLab` to `.pkgmeta` `ignore`.
- `tools/release.py` already refuses any top-level folder outside its seven (line 319). Add a `tests/test_release_tools.py` case that a package containing `TwichUI_TestLab` is refused.
- `tools/deploy.sh` is machine-local and gitignored, so putting the Lab into a development install is the developer's own step, documented in the Lab's doc.

---

## D. Simulator improvements (extend `tools/simlab`; no simulator source changes)

| # | Change | Gain |
|---|---|---|
| S1 | **Split the Workshop scenario:** one full-check launch, and pose launches that only set up state and take the screenshot; check steps grouped and selectable (extend `SIMLAB_ONLY`) | cuts most of the 3.5 min; frees each group its own 30 s budget; makes new steps possible |
| S2 | **Reachability v2:** add `GetHitRectInsets`, `IsMouseClickEnabled`/`IsMouseMotionEnabled` (both documented for Forever), the disabled state and non-Workshop occluders (GameTooltip, the Issue Report button). Rule: *every control that is drawn as actionable is reachable, and pressing it changes state* | narrows the gap behind the Add-button failure; still emulated ordering |
| S3 | **Lifecycle growth:** 20 open → navigate → close cycles; frames (`EnumerateFrames`), regions, registered events, and the `Look.Motion` driver idle afterwards; flat after cycle 2 | leak detection in the real widget runtime |
| S4 | **Shared fixtures:** move the synthetic world (items, recipes, listings, merchant) to `scenarios/workshop_fixture.lua`; later a fake auction-house module with an explicit state machine (search, confirm purchase, post, cancel, failures, throttle) for the AH-replacement milestones | one world for every launch; ready for transaction UIs |
| S5 | **Persistence feasibility (investigate first):** whether wow-ui-sim v0.1.37 writes SavedVariables to the lab's `wtf/` at exit and reads them at the next launch (`--no-saved-vars` hints it may). If it does: a two-launch reload scenario (scan, exit, relaunch: same prices, chip and history). If not: reload stays real-client | possibly the first non-mock reload evidence |
| S6 | Interrupted operations as UI: close the house during the read and during saving; the chip and footer states. The logic is already unit-tested | UI reflection only |

**The simulator cannot prove** real pointer order and hover, real fonts and widths, taint, combat and secure actions, the real auction house's timing and throttle, real SavedVariables writing (until S5 says otherwise) or real performance. Screenshots stay human-reviewed. A masked-crop diff as a "something changed" alarm would need an image library (Pillow is not installed here), so it is deferred.

---

## E. Performance framework

**Fixtures** (`TwichUI_TestLab/Fixtures.lua`, pure; seeded with a Lab-owned PRNG, so the same seed gives the same data on every machine and in the game). The generator in `test_workshop_market_scale.lua` moves here.

| Fixture | Size |
|---|---|
| `ah.small` / `ah.medium` / `ah.large` | 2,000 / 50,000 / 250,000 records (about 500 / 10,000 / 30,000 items; the scan's own cap) |
| `history.30d` / `.120d` / `.400d` | daily scans with gaps, for the commit job and the statistics |
| `lookups.10k` | 10,000 `Market.Price` + 1,000 `Stats` against `ah.large` with history |
| `tooltip.1k` | 1,000 `Worth.Evaluate` + `WorthLayout.Rows` |
| `queue.max` | 30 recipes × 16 materials × 4 candidates (the planner's bound) |
| `ui.nav50` | in game only: 50 page switches and redraws of the real window, then 10 open/close cycles |
| *later* `ledger.10k`, `graph.deep` | the Ledger and the multilevel planner |

**Metrics per benchmark:**
- total ms; per-step median, p90 and max, where steps are the production units (400-record batch, 120-item commit step, one lookup)
- KB allocated (`collectgarbage("count")` deltas; approximate, a collection step hides some)
- retained KB after an explicit full collection: **opt-in**, it causes a hitch, and the report says so
- collections seen
- in game, the worst frame interval and frames over 33 and 50 ms during the run, plus `C_AddOnProfiler` figures when `IsEnabled()`
- every figure reported over 5 runs as median and MAD

**One result line per benchmark:**

```json
{"schema":1,"bench":"commit.history120d","fixture":"ah.large#20261111","interp":"lua5.1-offline|wow-forever-<build>","runs":5,
 "median_ms":512,"mad_ms":9,"step_p90_ms":8.1,"step_max_ms":11.4,"alloc_kb":10840,"retained_kb":null,"max_frame_ms":null}
```

**Offline runner:** `tests/bench_workshop.lua`. It is not matched by `run.sh`'s `test_*.lua`, so it never slows the suite. Run it with the documented one-test command and write the results to `test-output/` (ignored by packaging; add it to `.gitignore`).

**Comparing before and after:**
- Interleave the runs on one machine in one session: A B A B A, at least 5 each.
- Report a change only when |Δmedian| > max(3 × the larger MAD, 5 %) and the direction holds in every pair. Otherwise say "no measurable change".
- An offline figure never stands in for a real-client claim.

**No absolute thresholds** until real-client figures are recorded. Until then, assert only structure: linear scaling (5× input < 10× time), a bounded worst step, flat retained memory over repeated runs.

**Who measures what:**

| Tool | Measures |
|---|---|
| `R.Perf` scopes and Diagnostics captures | real play |
| Diagnostics `Compare` | A/B of real captures |
| Test Lab benchmarks | controlled synthetic workloads in the client's interpreter |
| The offline bench | the cheapest regression signal |

---

## F. Implementation milestones

Each milestone is one request. **Tests** lists the evidence the milestone must produce. Every milestone also runs `./tests/run.sh` (about 5 min) once at the end and `luac5.1 -p` on each edited file.

**M1. Test Lab skeleton with shared core cases**
- **Objective:** a working in-client Run → Stop → Copy loop for pure calculations and interpreter facts.
- **Files:** `TwichUI_TestLab/` (toc, Lab, Runner, Report, Window, `cases/Core.lua`, `cases/Client.lua`), `tests/test_testlab.lua`, `.pkgmeta`, `tests/test_release_tools.py`.
- **Accept:** in game, the categories run, Stop works mid-run, and the report copies. Offline, every pure case passes under the mock, the runner's slice, stop, timeout, error and combat paths are tested, the saved roots are unchanged, the forbidden-name scan passes, and the package refuses the Lab.
- **Tests:** unit-tested runner; real-client run by the player.
- **Depends on:** nothing.
- **Out of scope:** benchmarks, UI probes, a core command, the simulator.

**M2. Market reference models** (built 2026-11-12, see H)
- **Objective:** independent models for the batch (sorted exact fractions) and the history and statistics (a full daily list).
- **Files:** `TwichUI_TestLab/Fixtures.lua` (PRNG + generators), `cases/Market.lua`, a regression case for the two Trend survivors.
- **Accept:** about 200 seeded calendars per run; the models agree with production; a failure prints its seed.
- **Tests:** the two Trend mutants from section A are killed (by hand until M4; now the catalog entries `market.trend.window-first-day` and `market.trend.negative-rounding`).
- **Depends on:** M1.
- **Out of scope:** changing Trend unless the model shows a real defect. Report it first.

**M3. Crafting and shopping reference models** (built 2026-11-12, see H)
- **Objective:** a brute-force planner on ≤ 6 materials; invariants for `Materials.Rows`, `W.Split` and `Shopping.Plan`; a reference for the craft estimate.
- **Files:** `cases/Crafting.lua`, `Fixtures.lua` queue generators.
- **Accept:** the invariants hold over about 300 generated queues; the cases agree with the brute force; shrinking is just "print the seed and the size".
- **Depends on:** M2's PRNG.
- **Out of scope:** the multilevel planner.

**M4. Mutation runner** (built 2026-11-12, see H)
- **Objective:** turn the probe described in section A into a reusable runner. Stage a copy of `TwichUI_Workshop/` beside a copy of the core's code files, so that `ROOT .. "../TwichUI_Workshop/"` resolves to the copy (the plan said symlinks; copies were chosen so that nothing in a copy can reach the checkout).
- **Files:** `tools/mutate.sh` (bash wrapper), `tools/mutate.py` (the runner), `tools/mutations/workshop.py` (the catalog), `tests/test_mutate.py` (the runner's own tests).
- **Accept:** a baseline-must-pass guard; the report lists killed and survived mutants and which tests killed them; about 20 mutants take under 2 min.
- **Depends on:** none (more valuable after M2 and M3).
- **Out of scope:** automatic mutant generation.

**M5. Reachability** (built 2026-11-12, see H)
- **Objective:** the observed button and hover failures become testable.
- **Files:**
  - an opt-in `Press(btn)` in a test kit that refuses hidden, disabled or mouse-disabled controls (`MIFake` records `EnableMouse` and insets, opt-in so existing tests are unchanged)
  - simulator S2
  - Lab `cases/UI.lua`: a real-client reachability scan of the Workshop window (rects, strata, levels, insets, click enabled) and the guided `GetMouseFoci` probe for the Add button and a row
- **Accept:** a planted overlay fails all three.
- **Tests:** unit-tested, simulator-tested, guided real-client run.
- **Depends on:** M1.
- **Out of scope:** fixing a failure found. Report it.

**M6. Client API probes** (built 2026-11-12, see H; real-client acceptance pending)
- **Objective:** turn offline assumptions into observed facts.
- **Files:** `cases/Client.lua`; as built, also `Probe.lua` (Lab-owned frames), `cases/Api.lua` (the UI probes) and an extension of `Guided.lua` (click requests, answer buttons, the binding probe).
- **Probes:**
  - Lua number and format facts: division by zero, exact products up to 2^53, `%.0f`, yield across `pcall`
  - whether `SetScript("OnEnter")` enables the mouse
  - whether `Click()` on a disabled button runs `OnClick`
  - clock resolution, profiler availability
  - with the house open: the auction API's presence and types and `UnitFactionGroup("npc")`, **without sending anything**
- **Accept:** each probe reports a value labelled `client`; nothing is written.
- **Depends on:** M1.
- **Out of scope:** `ReplicateItems`.

**M7. Benchmarks**
- **Objective:** section E.
- **Files (as built, see H):** `Fixtures.lua` sizes, `Bench.lua`, `Workloads.lua`, `cases/Perf.lua`, `tests/bench_workshop.lua`, result lines, a comparison note in this document.
- **Accept:** the same fixtures give results in both interpreters; 5-run median and MAD; frame figures in game; the scale test reuses the fixtures.
- **Depends on:** M2.
- **Out of scope:** thresholds, optimizations.

**M8. Simulator restructure**
- **Objective:** S1, S3 and S4.
- **Accept:** the same 396 checks in one launch, poses only elsewhere, wall time measured before and after, a growth check for flat frames and events, the negative control kept.
- **Depends on:** none.
- **Out of scope:** S5 and simulator patches.

**M9. Persistence**
- **Objective:**
  - an offline saved-variables text round trip (writer plus strict reader in the tests; never `loadstring` of data)
  - a migration-harness skeleton for the first future schema change
  - the Lab's `readonly` saved-data integrity check
  - S5 investigation only
- **Accept:** the round trip is exact on fixtures; the integrity check runs on real data and reports counts.
- **Depends on:** M1.
- **Out of scope:** schema changes.

**M10** (with the AH-replacement work, not before). **Transaction harness:** a fake auction-house state machine shared by the unit tests and the simulator (S4), with explicit-confirmation flows, failure and throttle injection, and Ledger replay fixtures. Real-client checks are always listed and never automated.

### Verification policy for future Workshop tasks (CLAUDE.md points here)

| Change | Required evidence | Not required |
|---|---|---|
| Pure algorithm | deterministic cases with hand arithmetic + a property test over seeds; `bash tools/mutate.sh --group market` or `--group crafting` (add a catalog entry for a realistic new defect model; section H, M4) | simulator |
| Money, cost or profit | the above + agreement with an independent reference model | simulator |
| Saved data | bounds/held/corrupt cases + a text round trip; a migration that is ordered, repeatable and idempotent; a real-client `/reload` check listed | — |
| UI | handler tests + `Press`-style reachability + `workshop.sh` (or its relevant group after M8) + a screenshot reviewed by a person; hover and pointer listed for the real client or run as a guided Lab case | benchmarks |
| Performance | before and after with the same fixture, interleaved, with the noise rule; real-client numbers only from the Lab or Diagnostics | — |
| Client API use | source evidence from `wow-ui-source` (forever) + a Lab probe or a listed real-client check; "unknown" stated otherwise | — |
| Transactions | the state machine incl. refusal, confirmation and interruption paths; a static check that no action fires without a click; real-client checks listed and never automated | — |
| Trivial (text, comments, constants with tests) | focused test + `luac5.1 -p` | simulator, full bench |

Run the focused test files first, then `./tests/run.sh` once at the end. Do not rerun an unchanged failing command.

---

## G. Recommended first implementation: M1

M1 is the smallest change that gives both a working in-client tool and stronger automated evidence. Its pure cases run in plain Lua and in WoW's interpreter from one definition, so the in-game run is itself verified offline, and every later milestone (M2, M3, M5, M6, M7) only adds case files.

The mutation probe behind section A was a throwaway script in the session's scratch folder (it is not committed). M4 rebuilds it.

### Prompt for M1 (copy as is)

```
Task: TwichUI Test Lab, milestone 1 (docs/workshop/testing-roadmap.md, sections C and F/M1). Branch feature/workshop.
Read first: CLAUDE.md, docs/workshop/testing-roadmap.md (C, F), tests/harness.lua, tests/mi_mock.lua,
tests/test_workshop_prices.lua (how Workshop files are loaded under the mock), !!!TwichUI/WorkshopLauncher.lua, .pkgmeta,
tools/release.py (package checks) and tests/test_release_tools.py.

Build a new load-on-demand development addon TwichUI_TestLab/ at the repository root:
- TwichUI_TestLab.toc: ## Interface copied from !!!TwichUI/!!!TwichUI.toc, ## Version 0.1.0-dev, ## LoadOnDemand: 1,
  ## RequiredDeps: !!!TwichUI, no SavedVariables. Files: Lab.lua, Runner.lua, Report.lua, Window.lua, cases/Core.lua, cases/Client.lua.
- Lab.lua: R.TestLab (TL) with TL.Case{ id, cat, class, needs, budget, run }. Refuse cases without class "pure" | "readonly" |
  "owned" | "guided" (M1 uses pure and readonly only). Case API t:Same, t:Check, t:Skip, t:Fact, t:Yield; t.W = R.Workshop when
  needs includes "workshop" (load it with R.WorkshopLauncher.Load(); report "skipped" with the launcher's reason if it refuses).
- Runner.lua: one Lab-owned frame whose OnUpdate exists only during a run; each case a coroutine resumed for a 5 ms slice
  (GetTimePreciseSec, else debugprofilestop; never debugprofilestart); per-case timeout 10 s, run cap 5 min; Stop marks the rest
  "stopped" at the next slice; refuse to start in combat; PLAYER_REGEN_DISABLED (registered only during a run) stops the run;
  statuses pass/fail/error/skipped/stopped/timeout; errors are captured by coroutine.resume; no t:Yield inside pcall.
- Report.lua: the plain-text format in section C (header with GetBuildInfo, addon versions from metadata, totals, worst slice and
  worst frame; one line per case with its evidence label "synthetic" or "client"; a facts line). No character, realm, guild, item
  link or saved value in it.
- Window.lua: built on first open; category checkboxes (Core calculations, Client facts), Run, Stop (always visible while running),
  progress (case n of m, id, elapsed), result rows with media/guides status-done / status-failed / status-current (-small),
  Copy report (a selected EditBox; the player presses Ctrl-C). Esc closes it through UISpecialFrames, never
  RegisterGameMenuEscHandler. Loading the addon opens the window once and registers /tuilab to reopen it; nothing runs by itself.
- cases/Core.lua (class pure, needs workshop), about 12 cases with hand-typed expected values: PR.Unit rounding and refusals;
  a NewBatch with cheapest price, quantity at it, next price and counters; PR.Quote exact/estimate/few/none; PR.Estimate with a
  range output and a cut passed as the rate ARGUMENT (never change Prices.CUT); W.Split order bags > bank > guild; History.Add
  folding an eighth day into a bucket; Market.Price and Market.Stats("week") on a synthetic market table via opt.market and opt.now.
- cases/Client.lua (class readonly, no workshop): Lua facts (1/0 behaviour under pcall, 99999999999 * 10000 compared exactly,
  string.format("%.0f", 1e15), yielding across pcall raises an error) and presence/type of GetTimePreciseSec, C_AddOnProfiler,
  GetMouseFoci, EnumerateFrames. Report values with t:Fact; assert nothing about values the client is not documented to give.

Safety: never reassign TwichUIDB, TwichUIWorkshopDB or TwichUIDiagnosticsDB; never call Commit/BeginCommit/Apply, Queue/Known/
Vendor/Storage writes, Session actions, Scan.Start or any purchase/post/cancel/mail/trade/destroy/use API; hook or wrap nothing;
send nothing. No change to !!!TwichUI, TwichUI_Workshop or any released addon.

Packaging: add TwichUI_TestLab to .pkgmeta ignore; add a test_release_tools.py case that a package containing TwichUI_TestLab
is refused.

Offline test tests/test_testlab.lua (runs in ./tests/run.sh): load the Workshop files and the TestLab files into an MIClient env
with stand-in frames; run every case of cases/Core.lua through the real Runner with a virtual clock and assert all pass; check
slice budgeting, Stop mid-run (rest "stopped", no OnUpdate left), a timeout, an erroring case not stopping the others, combat
refusal and combat stop, the report's header and line format and that the mock's character/realm names never appear,
TwichUIDB and TwichUIWorkshopDB deep-equal before and after, and a static scan of TwichUI_TestLab/**/*.lua for the forbidden API
names above and for assignments to the saved roots.

Verify: luac5.1 -p on every new Lua file; the new test alone; ./tests/run.sh (about 5 min). No simulator run is needed.
Docs: a short docs/testlab.md (purpose, how to install into a development copy and open, safety classes, report format, evidence
labels). Do not commit or push unless asked.
Report (CLAUDE.md format) with evidence labels; list the in-game checks: load it, run both categories, Stop mid-run, copy the report.
Out of scope: benchmarks, fixtures/PRNG, UI or pointer probes, guided cases, a /tui command in the core, simulator changes.
```

---

## H. Status: what is built

**M1 (27d8f668):** the Test Lab. First real-client run (Forever 1.60.1, build 70888): 23 of 23 cases passed, no error or timeout, worst slice 1.0 ms.

**M2, market reference models (2026-11-12):** offline verification, no player-facing change. One production fix (below).

| Part | Where |
|---|---|
| Deterministic fixtures: Wichmann-Hill generator (all products below 2^23, so doubles are exact and nothing depends on `math.random`), `Listings`, `Calendar`, `Markets`, every size clamped to `FX.LIMITS` | `TwichUI_TestLab/Fixtures.lua` |
| Independent models: the batch (every valid listing kept, prices compared as **mixed numbers** instead of cross-products), the history (every observed day kept in a map, the two tiers as sets, buckets computed from their days), and `Stats/Trend/Compare/Observed/Series` in whole-number arithmetic (means half up, percentages half away from zero, no floating point) | `TwichUI_TestLab/Reference.lua` |
| The comparison suite, properties and regressions | `tests/test_workshop_market_reference.lua` (about 7 s) |
| 3 bounded in-game cases (16 + 6 seeds, a Trend window/percent regression), also run offline by `test_testlab.lua` | `TwichUI_TestLab/cases/Market.lua` |

**Seeds (fixed):** batch `7100000+i`, history `7200000+i`, three-market sets `7300000+i`, `i = 1..200` (sets: 1..60); Trend mirror property `7400000`. Rerun one: `MARKET_SEED=7200042 <the one-test command>`; more: `MARKET_SCENARIOS=2000` (60 s, optional); every difference instead of the first: `MARKET_ALL=1`. A failure prints the model, seed, scenario, item, the item's observation trace, expected and actual.

**What is compared (default run):** 200 batch houses (12,503 records), 200 calendars, 60 sets of 3 markets, 9,480 scans each compared with the model **after every scan** (the tiers of every item), and 239,167 query comparisons at 8 query times each (Stats for 8 periods, Trend for 7 lengths, Compare for 5, Price, Observed for about 9 days, Series; bad periods and absent items included). Properties: record accounting, nothing counted twice, shuffled order, an item priced alone, every record added twice, the item limit with priority, stored-string invariants (7 exact days, 3 buckets, `lo <= mean <= hi`, buckets made of observed days, nothing older than the retention, never more days than were observed), a window that starts inside the exact days equals the full history, another market's scans change nothing, a listing is never presented as a sale. Stress (2,000 scenarios of each, 2.55 million queries): no difference.

**Mutation probe (disposable copy, `ROOT` resolving to the copy):** 35 hand-picked mutants of `Market.lua` (Trend window and rounding, Stats, Compare, Observed, Series), `Prices.lua` (rounding, comparison, tie, next price, counters, item limit, feeding, scan-day cap) and `History.lua` (fold, both expiries, bucket count, stale rule, bucket sum and high, window edges, skipped, bucket index). **35 of 35 killed by the new test**, including both former survivors; reverting the rounding fix is also killed by the Lab case. The existing `test_workshop_market.lua` and `test_workshop_prices.lua` together killed 23 of the 35. A hand list run by a throwaway script, not an automatic mutation run (M4).

**Defect fixed.** `Market.Trend` rounded a negative change as `floor(x - 0.5)`, one tenth too far for every fall that is not an exact tie: 1000 to 900 read **-10.1 %** (true -10.0), 300 to 200 read **-33.4 %** (true -33.3). Rises were right, so a rise and the same fall were not mirror images. `Trend` had no consumer yet. The fix is whole-number arithmetic, ties away from zero for both signs (`PercentTenths` in `Market.lua`). **The M1 Core case `market.trend.percent` had expected -33.4**, copied from the code ("rounded the way the code states"); it now expects -33.3. That case had passed in the real client, which shows only that the client runs the same arithmetic.

**Reported, not changed** (each is pinned by a characterization test in section 7 of the new test, or counted there, so changing it is a conscious step):
1. `x` (the next higher price) is `0` when the next exact price rounds to the cheapest copper even though a dearer listing exists (`299/3`, `100`, `150` gives `x = 0`, the literal next copper price is `150`). The default run has 261 items like that across its 200 houses. `Quote` does not use `x`.
2. A scan dated **before** the observation a bucket holds is accepted when no exact day is left (`Add` compares only with exact days; the model refuses it as stale). It needs the clock to go back over 120 days.
3. With only buckets left, `Stats.newest.day` is the bucket's last calendar day (not an observed one) and has no price.
4. `Trend` has no upper bound at `now`, `Stats` and `Compare` do: with `now` before the newest observation, `Trend` counts days after `now`.
5. `partialInfo` counts a record with a valid item and `info == false` even when its count or buyout is invalid (the header says "their prices were used").

**Remaining gaps:** `Quote`, `Estimate` and the Opportunities arithmetic (M3); `Shopping.Plan` and `Materials` (M3); the text round trip and the eviction order of markets when `at` ties (M9); the scan state machine; the new Lab cases have not yet run in the real client (the offline run shows the cases pass in plain Lua 5.1, not in the client's interpreter); the mutation probe was a script outside the repository (now `tools/mutate.sh`, M4).

**Handoff to M3 (crafting and shopping reference models):** reuse `TL.Fixtures.Rng` and the pattern of `Reference.lua` (a model built from the documented contract, with whole-number arithmetic, compared with production after every step, failures printing model, seed, scenario and input; known-gap characterization tests for contract corners). Add queue/recipe/stock generators to `Fixtures.lua` (bounded by the planner's limits: 30 recipes, 16 materials, 4 candidates), a brute-force planner for at most 6 materials against `Shopping.Plan`, invariants for `Materials.Rows`, `W.Split` (bags + bank + guild + still needed = need; no layer negative or above what it holds) and an independent craft-estimate model against `Prices.Estimate/Quote` (the profit bound with `cheapest` set is a product decision, see "Unresolved decisions" 3). Seeds: continue at `7500000+i`. Never call `Prices.<commit>`-type writes in Lab cases; keep the large suites offline.

**M3, crafting and shopping reference models (2026-11-12):** offline verification, no player-facing change, **no production file changed**.

| Part | Where |
|---|---|
| Generators (same Wichmann-Hill generator): `FX.Crafting` (3 to 6 materials, 1 to 4 queued recipes, bags/bank/guild counts with unreadable bag counts, auction price lists with stale and partial scans, vendor offers incl. sold out and price never seen, up to 3 make recipes per material incl. circular, range, unknown-output and empty ones), `FX.Economy` (recipes as the window reads them, some malformed, a price lookup, a cut), `FX.StockObs` (bank and guild observations: other characters' tabs, rights, allowance ages around 6 h, uncertain tabs) | `TwichUI_TestLab/Fixtures.lua` |
| Models: one-item-at-a-time allocation, combined materials and rows, the stock rules, the cost of any sourcing choice (vendor stacks by counting, exact copper, owned reagents valued by exact fractions), an **exhaustive enumeration** of the sourcing choices, the craft estimate (whole-number cut), the Opportunities order | `TwichUI_TestLab/Reference.lua` section 4 |
| The suite (about 1 s) | `tests/test_workshop_crafting_reference.lua` |
| 3 bounded in-game cases (24 + 8 + 20 seeds), also run offline by `test_testlab.lua` | `TwichUI_TestLab/cases/Crafting.lua` |

**Seeds (fixed):** materials 7500000+i, shopping 7510000+i, economics 7520000+i, stock 7530000+i, `i = 1..200`. Rerun one: `CRAFT_SCENARIOS=1000 CRAFT_SEED=7510042 <the one-test command>`; stress `CRAFT_SCENARIOS=9000` (26 s); every difference instead of the first: `CRAFT_ALL=1`. A failure prints the model, seed, input, the contract violated, expected, actual.

**What is compared (default run):** 200 `W.Split` calls and 200 queues (720 rows, 75 with a crafting circle) against the model and against invariants (demand conserved, net need = bags + bank + guild + short, layers used in order, queue order irrelevant, unknown stays unknown); 200 stock scenarios (412 guild tabs, every tab state covered) through the real storage records, plus the guild-bank on/off policy; 200 shopping scenarios, **1,643 sourcing choices each forced through the player's picks and compared with production (totals, collect rows, every made material's crafts, leftover, cash, economic cost and reagent lines)**, 825 of them infeasible (both refuse); production's own decisions (options, suggestion, recipe choice) replayed from the contract; 786 estimates (471 fully priced, 228 at a loss) and every Opportunities order for 10 option sets. Stress (9,000 of each): 73,277 choices, 20,774 priced estimates, no difference. Hand-calculated examples: Split, Rows, Stock, Quote, Estimate (cut, range, loss, missing, few), vendor vs auction, ties, stacks, overrides, quantity-aware estimate, make vs buy, every unusable-recipe reason, chain, shared demand, incomplete/stale/partial prices, known vs unknown zero, collect.

**Shopping against the exhaustive best (149 comparisons at default, 7,177 at 9,000):** the model enumerates every combination of vendor, auction and one known recipe per short material and compares (unpriced items, then cash). A difference is **classified, not called a bug**: *same cost* 85 %; *documented basis* (owned reagents are valued at what they would cost, so it buys where making would cost no cash) 3 %; *one material at a time* (an earlier choice changes a later one, or the source chosen at a material's turn is kept for the combined purchase) 2 %; *economic cost unknown* (a recipe whose owned reagent has no price is never preferred, even at zero cash) 8 %; plans that leave a material **undecided** because no option has a known cost are counted and not compared. In every case the better combination is reachable with the player's picks and production computes its cost exactly as the model does. Production never beat the exhaustive best (a hard check).

**Mutation probe (disposable copy, hand-picked, not automatic; M4):** 64 mutants in `Data.lua`, `Materials.lua`, `Stock.lua`, `Prices.lua`, `Opportunities.lua`, `Shopping.lua`, `Vendor.lua` (reversed allocation priority, off-by-one quantities, ignored output counts, shared stock counted twice, missing price as zero, tie handling, make-vs-buy valuation, misapplied cut, loss clamped, the next-higher-price estimate the owner decided against, ...). **Two survived the first run (profit exactly 0 counted as profitable; exactly 999 crafts refused); each now has a hand-calculated boundary case and is killed: 64 of 64 killed.** 15 mutants are killed only by the new test or Lab; the existing Workshop tests killed 49 of the 64 and none that the new test missed.

**Defects:** none confirmed; production is unchanged. **Characterized limits** (each pinned by a test, changing one is a conscious step):
1. `Quote`'s estimate is the least it could cost, flagged (`estimate`, `cheapest`, `totals.estimate`, the row's `uncertain`); the saved next-higher price is not used (owner decision).
2. The planner decides one material at a time. The source chosen at a material's turn is kept for the combined purchase even when a made material's reagents raise the quantity to where another source is cheaper (hand example 16 against 13 copper); the exhaustive best can be a few copper lower (404 against 400).
3. Making is valued at what the reagents would cost, owned ones included: it buys when that is cheaper, though making costs no cash. A recipe with an owned reagent that has no saved price has no economic cost and is not preferred over a recipe that has one.
4. A pick that can no longer be used is reported (`pickLost`) but still moves its item to the front of the decision order, which can change the rest of the plan.
5. `PR.Cut` and the valuation of owned reagents round half up in floating point: an amount exactly halfway between two coppers can come out **one copper low** for some rates and stack sizes (35 %: 90 x 0.35 = 31.5 gives 31; value of 27 items at 13 per stack of 6 = 58.5 gives 58). 5, 10, 15, 20, 25 and 30 % are exact to 20,000,000 copper. The real tie rule is unknown (the real cut is unconfirmed).
6. A zero total does not tell known from unknown: unreadable bag counts leave `totals` at 0 and are carried only by `plan.unknownBags` (the view shows it).
7. A recipe output given only as a maximum is a fixed output; a maximum below the minimum is no output (`Estimate`).
8. The queue credit looks at no more than 60 entries; the queue holds 30.

**Product questions found:** (a) should a lost pick keep deciding first? (b) should the combined purchase re-pick the cheapest source at the combined quantity? (c) should a recipe whose cash cost is known and zero be offered when an owned reagent has no price? (d) which way a half copper of the cut rounds, once the invoice is seen.

**Remaining gaps:** the new Lab cases have not run in the real client; the stock cases need the storage records, so they stay offline; depth-aware purchase costing and the multilevel planner (later milestones) have no model yet (`REF.MakeOption`/`REF.Plan` are one-level); mutation was still a script outside the repository (now `tools/mutate.sh`, M4).

**Handoff to M4/M5:** `REF.Enumerate`, `REF.Plan`, `REF.MakeOption` and `FX.PlanInput` are the pieces a multilevel planner's model would extend (a deeper `MakeOption`, a graph instead of the one-level chain rule). The mutant list above (64 entries, each a single exact-text edit) is the starting list for `tools/mutate.sh`.

**M4, mutation runner (2026-11-12):** offline verification tooling, no player-facing change, **no production file changed**. One test file gained a comparison (below).

| Part | Where |
|---|---|
| Entry point (`bash`, from any folder) and the runner (stdlib Python only) | `tools/mutate.sh`, `tools/mutate.py` |
| The catalog: 102 explicit entries, each with an id, one exact-text edit of one file, the defect it stands for, the tests that must catch it, and an expected result | `tools/mutations/workshop.py` |
| The runner's own tests: 29 harness tests on a fake repository (also run by `./tests/run.sh`, about 5 s) | `tests/test_mutate.py` |

**What it does.** Every mutation gets its own copy under a fresh folder in the system temp directory (never inside the checkout): the core's code files (`.lua .toc .xml`), `TwichUI_Workshop/`, `TwichUI_TestLab/`, the `.lua` test helpers and the tests that mutation names. The source set is read from the checkout once, at the start, and every copy is written from those bytes (so every mutant is compared with the same baseline source); the mutation is applied only inside the copy (the pattern must occur **exactly once**; zero or several is `invalid`), the mutated file must still pass `luac5.1 -p` (else `invalid`), and the focused tests run there with a minimal environment (no inherited seeds or `LUA_INIT`, a private `HOME` and `TMPDIR`) in their own process group. A baseline of every needed test on an unmodified copy runs first; if it fails, the campaign stops. At the end the live files are compared with what was read; any difference is an infrastructure error. Copies are removed on every exit Python can see, including Ctrl-C and SIGTERM (child process groups are killed first); a SIGKILL of the runner itself cannot be caught and would leave a `twichui-mutate-*` folder in the temp directory (delete it). A mutation may only edit a file under `TwichUI_Workshop/`.

**Outcomes** (never merged): `killed` (a relevant test failed; labelled `assertion`, `runtime-error` when the code crashed, `caught-error` when the addon handed an error to the error handler as `run.sh` also treats it, or `no-pass-marker`), `survived`, `invalid`, `timeout` (a hang is never a kill; limit = 6 x the test's baseline time + 5 s, at most 120 s, or `--timeout`), `infra` (the test command could not run, died from a signal, exit 126/127, a missing module or file). The score line always says how many applied mutations were killed and, if anything was excluded, that it is **not a clean score**. A documented known survivor (`expect="survived"` with a required note) is expected and listed.

**Exit status:** 0 every mutation ended as the catalog expects | 1 an unexpected survivor, an unexpected kill of a known survivor, an invalid mutation or a timeout | 2 an infrastructure error (also a checkout that changed during the run) | 3 the baseline failed | 64 bad arguments or a bad catalog | 130/143 interrupted.

**Commands** (from any folder; the full list is `--help`):

```
bash tools/mutate.sh                                 # the smoke group (16 mutations, a few of each kind)
bash tools/mutate.sh --group market                  # prices, history, statistics, quotes, the craft estimate
bash tools/mutate.sh --group crafting                # materials, stock, shopping, vendor, Opportunities
bash tools/mutate.sh --group market.trend            # any id prefix
bash tools/mutate.sh --id market.trend.window-first-day
bash tools/mutate.sh --all --jobs 4                  # the whole catalog, four copies at a time (4 is the best measured; more is slower)
bash tools/mutate.sh --list [--verbose]              # what exists, and the exact edits
bash tools/mutate.sh --check                         # do all patterns still match exactly once and parse? (runs no test)
bash tools/mutate.sh --keep-failed                   # keep the copy (+ MUTATION.txt, OUTPUT.txt, REPRODUCE.txt) of anything unexpected
bash tools/mutate.sh --broad --id <survivor>         # also try the older broad Workshop tests on a survivor
bash tools/mutate.sh --all --json result.json
```

**Catalog coverage (102).** *Market and pricing (46):* the batch (compare unit prices as fractions, cheapest, quantity at the cheapest tier and its reset, next higher price and its same-copper rule, items and listings, bid-only, the item limit's priority and ordering), history (bucket index, fold low/sum/count, seven exact days, both expiry boundaries, same-day overwrite, stale boundary, window first and last day, partly covered bucket, `skipped`), Stats (week length, rounding), Trend (window start, negative and positive rounding, flat, start point), Compare (reference excludes today, equal is not above), Quote (exact and few boundaries, cost beyond the cheapest tier), the craft estimate (cheapest flag, missing price, sell range, cut on both ends, profit range and sign, inverted output range) and the cut's rounding. *Crafting (56):* `W.Split` (order, negative counts, remainder), Materials (crafts multiplier, output credit, cycles, credit subtraction, unreadable bags as zero, unknown recipes, row order, guild-only collect), Stock (uncertain bank, tab sums, pending guild read, another character's tab, unseen rights, allowance expiry boundary, the guild-bank policy, craft state), Shopping (vendor/auction tie, suggestion tie, an unusable make pick honoured, picks first, crafts rounding and the 999-craft limit, surplus, range and circular recipes, reagent multiplication, make cost with and without owned value, owned-value rounding and unit, dearest recipe, bags/bank/reagents counted twice, reagent buys, unpriced and estimate totals, cash accumulation, unknown bags), Vendor (whole stacks, cost basis, sold out, stock check) and Opportunities (zero profit counted and filtered, unknown order, direction, tie order). Of these, 34 are caught by `test_workshop_market_reference.lua` and 68 by `test_workshop_crafting_reference.lua` (the quote, estimate and cut entries sit in `market.*` but are caught by the crafting model).

**Measured** (this machine, WSL2, 2026-11-12; the whole catalog was run twice serially and twice with four jobs, and the pairs agree within a second): baseline 0.6 s (crafting model) + 5.4 s (market model); smoke group 9 s; `--group market` 20 s; `--group crafting` 10 s; **all 102: 29 s serial, 14 s with `--jobs 4`** (8 jobs 19 s, 16 jobs 21 s: Python's file writes and process spawns contend, so 4 is the sweet spot). A kill stops at the first failing assertion, so most mutations take 0.2 to 0.6 s; the slowest took 5.5 s. `--check` takes under a second. The runner's own tests take about 5 s.

**Detection results.** First full run: **100 of 102 killed, 2 survived**, both investigated rather than excused:
1. `market.history.window-skipped` (counting the days a partly covered bucket hides as one): **a real test gap.** The model computed the exact `skipped` count, but the comparison suite checked only `Stats.limited`, a boolean. `test_workshop_market_reference.lua` now also compares the raw `History.Window` result (`n`, `sum`, `lo`, `hi`, `exact`, `skipped`) with the model for every Stats window; the mutation is killed.
2. `crafting.shopping.unusable-make-suggested` (dropping the `state == "ok"` guard in `Suggest`): **equivalent**, not a gap. A make option that is not `ok` returns from `EvalMake` before it is given a `cost`, and `Suggest` needs one. It was removed from the catalog and is listed with the other examined equivalents at the end of the catalog file.

Final catalog: **102 selected, 102 killed, 0 survived, 0 invalid, 0 timeouts, 0 infrastructure errors**; 101 killed by a failed assertion and 1 by a crash in the mutated code (`crafting.shopping.unusable-make-pick-honoured`: the mutant dereferences a missing reagent list; a crash is still a detection, and the report labels it). The four earlier manual survivors are all entries now: `market.trend.window-first-day` and `market.trend.negative-rounding` (M2), `crafting.opps.zero-profit-counted` and `crafting.shopping.make-crafts-limit-boundary` (M3). The runner's own defects were checked the same way: planting seven defects, one at a time, in a scratch copy of `mutate.py` (a timeout counted as a kill, no cleanup of the copies, an ambiguous pattern accepted, a failed baseline ignored, an infrastructure failure counted as a kill, the live checkout never re-checked, the mutation applied to the live file instead of the copy) each makes `tests/test_mutate.py` fail.

**Not carried over from the 64-mutant M3 list:** the hand list was a starting point, not a specification; entries that differed only in an operand of an already covered line, or that turned out to be equivalent, were not rebuilt. Entries for the Lab-only paths and for `Session.lua` do not exist.

**Known limitations.**
- A mutant is judged by the offline tests only: nothing is learned about the real client's Lua, taint, timing or the auction house.
- Exact-text patterns are brittle by design. A refactor of a mutated line makes its entry `invalid` (`--check` finds all of them in under a second; `test_real_catalog_matches_the_source` in `tests/test_mutate.py` fails `./tests/run.sh` until the entry is updated).
- The catalog holds single-line or few-line edits chosen for a realistic story. It is not an exhaustive mutation score: 102 killed says these 102 mistakes are noticed, not that no mistake goes unnoticed. The reference models and the mutants were written by the same hands, so a blind spot they share would show up in neither.
- The runner passes none of the caller's environment to the tests (so `MARKET_SEED`, `MARKET_SCENARIOS` and similar overrides are ignored on purpose): a campaign always runs the default seeds, which is what makes a result reproducible.
- A SIGKILL of the runner leaves its temp folder; the checkout is never touched either way. Edits to the checkout while a campaign runs are reported at its end (exit 2), but the results then describe the files as they were when it started.
- The core addon's media is not copied (only `.lua .toc .xml`), so a test that needs a texture file would fail its baseline; none of the Workshop tests does.
- `--jobs` runs copies side by side; time limits are derived from serial baseline times, so a heavily loaded machine can produce a `timeout`, which is reported as such and never as a kill.

**Found in passing (not fixed, unrelated to M4).** `tests/test_workshop_window.lua` is flaky: it fails about 3 % of the time (2 of 60 standalone runs, and once in a full `./tests/run.sh`) at the assertion "and navigating wrote nothing to the saved data", because a recipe record's `at` is stamped with the real `os.time()` and differs by one second when the clock ticks over during the test. The test (or the code under it) needs a fixed clock; a rerun passes.

**Extending the catalog.** Add an `m(id, file, find, replace, why, tests, ...)` line to `tools/mutations/workshop.py` (the file's header says how): pick a defect someone could really write, copy enough of the line to make it unique, then `bash tools/mutate.sh --check --id <id>` and `bash tools/mutate.sh --id <id>`. A survivor is information: either add the missing test case (do not change `expect`) or, when the edit changes nothing observable, delete the entry and list it under "examined and left out". Use the catalog selectively: when a Workshop task changes money, quantity, rounding, ordering or eligibility logic, run the matching group and add the entry for the mistake that change makes possible; it is not a substitute for the model comparison or for hand-calculated cases.

**Handoff to M5 (reachability).** M4 leaves the offline arithmetic with a repeatable check; the remaining blind spot is the UI. For M5: (1) an opt-in `Press(btn)` in the test kit that refuses hidden, disabled or mouse-disabled controls (the observed button and hover failures of section A: a control that looks clickable and is not); (2) a Lab `cases/UI.lua` reachability scan (rects, strata, frame levels, insets, `IsMouseEnabled`) plus a guided `GetMouseFoci` probe over the Add button and a row, to be run in the real client by the player; (3) a planted overlay as the negative control that must fail all three. The pointer and hover facts stay **not tested** until a real-client run: nothing in M1 to M4 proves them. (M5 built all three; see its section below. The real-client run is still to do.) The mutation runner can be reused for M5's own helpers (for example, mutate `Press`'s refusal rules) but should not be pointed at the view files, whose behaviour is layout, not arithmetic.

**First real-client run of the Lab's M2/M3 cases (2026-11-12, Forever 1.60.1 build 70888): 27 of 29 passed, 2 errors, no failure, no timeout.** Both errors were `integer overflow attempting to store ...`, raised by **`string.format("%d", x)` in the client when x is NaN or does not fit in 32 bits**; plain Lua 5.1 accepts both and prints a number, so the offline suite could not show it. They were defects of the **Lab and test code, not of the Workshop**:
1. `market.trend.window-and-percent` formatted the copper price 99999999999 with `%d`.
2. `market.reference.batch` formatted a reference price (`REF.EntryText`; fixture prices reach 99999999999) and a calendar key from a seed with `%d`; the generator's own boundary test passes a NaN seed.
Fixed: `%.0f` for copper (as `Prices` and `History` already do), a sanitized seed for the calendar key. **Audit of production:** every `%d` in `TwichUI_Workshop/` formats a small count (items, quantities, days, percent), `UI.Num` is used only for item counts (at most 40,000), and money is drawn by `GetMoneyString`; nothing in the Workshop formats copper or a possibly-NaN number with `%d`. **Regression guard:** `tests/client_format.lua` makes `string.format` refuse NaN and 32-bit overflow for `%d` (and `%i %c %x %X %o %u`); `test_testlab.lua` and the two reference tests load it, and the committed Lab code fails under it exactly as in the client. The exact limit is unknown (32-bit is the conservative reading); pinning it is a client-API probe for M6, as is `x % 0` (the client prints `-nan(ind)`, plain Lua `nan`). Other facts from this run: yielding across `pcall` is refused (as in plain Lua 5.1), division by zero gives `inf`, 2^53+1 equals 2^53, the pause probe measured 2001 ms, and the worst slice was 131.9 ms with frame 139 ms (a cooperative case that does not yield, probably the first load; not investigated). The Lab's crafting cases ran 35 sourcing choices in the client and agreed.

**M5, reachability (2026-11-12):** test tooling, a simulator step and a guided Lab probe. **No production file changed.** Reference: `docs/testlab.md` "Reachability and the pointer probe" and `docs/simulator-lab.md` (the reachability step).

*Flaky window test fixed.* `tests/test_workshop_window.lua` failed when the clock ticked between its two saved-data comparisons because `Q.Now` (a recipe record's `at`) reads the real `time()`. Its lifecycle block now sets the already-injectable `Q.Now` to a fixed value (as `test_workshop.lua` does) and restores it; the equality assertion is unchanged, no production code was touched, no sleep. Evidence: a ticking clock (every `time()` call one second later) fails the old test at the assertion deterministically and passes the new one; **600 standalone runs of the old test: 9 failures (1.5 %); 600 of the new: 0.**

*What was built.*
- `TwichUI_TestLab/Reach.lua`, the shared analysis (eligibility, hit rectangle with insets and scale, bounded frame collection, blocker analysis with strata/level/tie/clipping/children, a redacting describer, `Sample` over `GetMouseFoci`). `tests/test_reach.lua`: fake world (`tests/reach_world.lua`), covering hidden frame and ancestor, disabled, mouse off, click off, motion off, missing handlers, valid, parent/child overlap, insets (including negative and empty), a planted overlay blocking then removed, an overlay with click off / propagating / hidden / with its own insets, ties (ambiguous, a child over its parent decided), scroll and clip-children clipping, a pooled hidden row, hover with a child picture and a selected row, redaction and bounded scans.
- `tests/press.lua` (`Press(btn)`, `Press.Must`, `Press.Hover`, `Press.Instrument`), opt-in; `tests/test_press.lua`; the window test opts in and presses the Opportunities Add button and the recipe rows' Add buttons (and asserts the queued, hidden/disabled real buttons are refused). Guarantees and limits: `docs/testlab.md`.
- Simulator: `workshop.sh` concatenates `Reach.lua` into each fixture; the third-pass hit test now uses it (over every frame, not only the Workshop's, with hit-rect insets, clipping, children and ties); a new step plants `SimlabPlantedOverlay` over the Add button (reachable, **blocked and named**, reachable), over a hoverable row (same), checks the picture/child case, the disabled button, the switch's insets, a scenario-owned scroll frame, the pool and the tooltip. `workshop_verdict.py` requires the step and the three states in order. **Full run: 13 launches, 427 checks each (was 396), 26.95 of 30 simulated seconds (design pose 27.85), the doctored-expectation control still fails exactly its one check; the verdict is `PASS WITH KNOWN SIMULATOR LIMITATIONS` (the two classified ones that were there before), and `lab_guard.sh` passes.** No obstruction or ambiguity was found in the Workshop's own controls: the Opportunities, Crafting and Shopping buttons are all reachable at their hit points, and the hit test is no longer vacuous (it sees the window's buttons; the first draft used a frame limit that hid them, which the "is not passing on an empty list" check caught).
- Lab: `Guided.lua`, `cases/UI.lua` (`ui.pointer.api`, `ui.workshop.reach-scan`, `ui.pointer.add-button`, `ui.pointer.opportunity-row`, `ui.pointer.row-picture`), the `guided` class and category flag, `t:Note` evidence lines under a case in the report, window words (`your turn`, `measured`, `skipped`, `cancelled`), the runner's cleanup hook (`Guided.End` on every route a case or run can end). `tests/test_testlab_ui.lua` (a sample on the key, retry when the pointer is elsewhere, the pointer outside the hit rectangle as a failure, skip, cancel, Stop, combat, a closed window, timeout, error and a case that crashes mid-request, the countdown fallback with no binding API, hover cases with selected / lit / fading / child-picture rows, the scan with a planted overlay, redaction, "a default run asks for nothing", no binding/prompt/proxy/timer left).

*Facts found on the way.*
1. **The simulator's `GetMouseFoci` is not a hit test.** It returns exactly the frame a scenario forced with `A_Admin.SetMouseOverFrame` and nothing from a position. So the simulator cannot give the client's answer; the geometry is an emulation and the report says so (class `simulator-geometry`). A check keeps this written down.
2. **The simulator stores `SetVerticalScroll` without moving the scroll child's rows** (`GetRect` unchanged, scroll range 0). A check records it; a scrolled list is modelled by anchoring.
3. A clicked `Disable()`d button in the simulator does not run `OnClick` (probed, not asserted); the client's behaviour is an M6 probe.
4. `SetHitRectInsets` is marked **protected** in the Forever API documentation (`SimpleFrameAPIDocumentation.lua`); `UI.Switch` calls it at build time only. Worth knowing if a Switch is ever built in combat; not investigated, not a finding about M5.
5. `SetOverrideBindingClick` is not in the generated API documentation; it appears in Blizzard's insecure `Blizzard_GamepadSharedUtility` code. Whether this client lets an addon bind with it is **unconfirmed** until the first real run (`ui.pointer.api` reports presence; the guided prompt says so if the key cannot be bound and offers the countdown).

*Mutation check of the new code (a scratch copy, not a catalog entry).* 44 hand-planted defects in `Reach.lua`, `Guided.lua`, `Runner.lua`, `cases/UI.lua`, `Lab.lua`, `Window.lua`, `Report.lua` and `press.lua` (inverted flags, insets signs, strata/level/depth order, clipping dropped, tie dropped, propagation, the target excluded from its own stack, redaction off, unknown treated as eligible, an unreleased binding on each exit route, the guided box ticked by default, ...). The first pass killed 39 and left 5 survivors; all five were real gaps (a click-propagating target, the bounded `EnumerateFrames` walk, a key pressed after Skip, the runner's error/timeout cleanup before the next case), tests were added, and the second pass killed **44 of 44**. A first attempt reported every Lab mutant as surviving because a symlinked checkout made the tests load the real files; the harness copies the code instead.

*Evidence labels.* Handler invoked: unit-tested. Eligible by recorded state: unit-tested (`Press`, `Reach.Eligibility`). Geometrically reachable: simulator-tested (an emulation), unit-tested on a fake world. **Under the real pointer: not tested.** Hover looks / animation: not tested.

*Real-client verification (still to do, by the player).* Follow "What to do in the game" in `docs/testlab.md`: Opportunities with a recipe chosen, `ui.workshop.reach-scan`, then the three guided steps with F9, then Copy report. What the report should show if the Add button and hover work: step 1 `PASS` with `topmost_relation=self` and `in_hit_rect=true`; step 2 `topmost_relation=self`, `hovered=true`, alpha near 1; step 3 `topmost_relation=self`, `hovered=true`. If a step fails, the evidence lines name the frame the client put under the pointer, its strata/level/rectangle/insets, which is what the third-pass failure was missing. If the client refuses the key binding the prompt says so and the 5-second countdown is the (honestly weaker) fallback.

*Known limitations.* The geometry is a model (equal strata and level are reported ambiguous, secure frames and mouse capture are not modelled); `Press` cannot see other frames; the guided probe reads an alpha, not an animation; the Lab window must be dragged away from the Workshop by hand; nothing of M5 has run in the game.

**M5.1, the first real-client run of the Lab (2026-11-12, client 1.60.1 build 70888): one failing case, one slow scan.** Test tooling only; **no production file changed.**

*Result of the run.* 34 cases: 33 pass, 1 fail (`market.reference.batch`), no errors or timeouts; worst step 14.7 ms, worst frame 41 ms, four overruns. The three guided pointer cases **passed in the real client** (`GetMouseFoci` named the intended Workshop frame topmost with the pointer inside its hit rectangle, for the Opportunities Add button, a row and a row's picture; the row and picture highlights read alpha 1.00). That is real-client evidence for the pointer, and for the alpha only, not for how the hover looks.

*Root cause of the market failure: the reference model, not production.* Offline, seeds 7100008 and 7100012 give 4 bid-only and 6 invalid records, and 33 used and 2 invalid, for **both** the model and `Prices.Batch:Add`. In the client, `Batch:Add` still gave those numbers (the report's "actual" column) and the **model** gave 5 and 5, and 34 and 1 (the "expected" column): one record in each seed that is invalid by the contract was counted as valid. Each seed draws a NaN `count` (the fixture writes `0 / 0` among its malformed values): record 10 of 7100008 (buyout 0, so the model made it bid-only) and record 42 of 7100012 (buyout 253700, so the model priced it, which also moved item 1022458734's aggregate). `REF.Whole`, which decided "a whole number in range" with `v == v and v >= lo and v <= hi and v % 1 == 0`, therefore **returned true for a NaN in this client**, and desktop Lua 5.1 rejects it at `v == v`. Production's `W.Int` (`v ~= v or v < lo or v > hi or math.floor(v) ~= v`) rejected the same NaN in the client, so the two disagreed only because the model leaned on NaN comparisons. Which comparison differs (the report's primitives did not say) is **not yet established**: the new `client.lua.nan-comparisons` case reports each one; that is a fact about the client's Lua, not a finding about the Workshop. Not numerical precision, not rounding, not fraction comparison and not the generator (the model and production read the same records within the run; every generated record is identical to the offline one).

*Correction.* `Reference.lua`: `REF.Finite(v)` decides finiteness **without comparing v with anything** (a finite number's `tostring` is digits, a point, an exponent and signs only; NaN and infinity print with letters), and `Whole` and the bid-only test (`Zero`) compare only numbers it passed. Semantics are unchanged for every finite value (including 0, the limits and fractions); a NaN or an infinity in any field is invalid and never bid-only. The same idiom (`v ~= v`) is still in the crafting model's `Qty` and in two crafting guards of `Reference.lua`, in `Fixtures.lua` (`Clamp`, `Rate`, `Whole(seed)`) and in `Reach.lua`'s `Num`; no fixture of theirs produces a NaN (the crafting cases passed in the client), so they were left alone. **Production was not changed:** it classified correctly in the client. Whether a NaN *buyout* (compared with `raw == 0` before `Int`) is read as invalid or as bid-only in this client is now asserted by `market.reference.invalid-values`, which the next run will answer.

*Independent evidence.* `tests/test_workshop_market_reference.lua` section 6b: finiteness and whole-number limits by hand; a six-record batch worked out on paper (5 at 10 for 2 items is the only priced record, so the entry is `5,2,1,2,0`; a NaN count at 5 must NOT become the cheapest; the NaN buyout, NaN item and infinite count are invalid); the two seeds still draw a NaN count (so the regression keeps its teeth) and give the client's numbers. `tests/test_testlab.lua` 2b sabotages production to read a NaN count as 5 and requires both Lab cases to FAIL and name the record and the number primitives. Desktop Lua cannot reproduce the client's NaN comparisons, so the pre-fix model is **not** killed offline; the client run is the evidence for the fix. The market mutation group is unchanged: 46 of 46 killed (production algorithms were not touched).

*New diagnostics (bounded, read-only, synthetic).* `market.reference.batch` names the **first record the model and production read differently** (index, intent, the three fields as type and value, both answers) and prints `REF.NumberProbe` of the differing field (`tostring`, `v==v`, `v<lo`, `v<=hi`, `v%1`, `floor`, then finite/whole), in one line per seed, never the batch. `market.reference.invalid-values` tries every malformed value of the generator (`FX.BAD`: NaN, infinity, fractions, strings, booleans, past each limit, missing) in each field of a good record, plus the limits themselves, and requires model and production to agree with the contract. `client.lua.nan-comparisons` reports the NaN primitives of this client (runtime `0/0`, the literal `0/0`, its negation, infinity).

*Reachability scan performance.* Measured in the client: 28,850 frames enumerated, 164.5 ms of scanning in about 14 steps of **2000 frames**, so a step took 11 to 15 ms against the 5 ms slice (four were recorded as overruns, the longest 14.6 ms). The yield was by frame count; it is now by **time**: `RC.Collect` takes `opts.clock` and yields once `RC.BUDGET` (1.5 ms) of scanning has passed, reading the clock every 32 frames, with the 2000-frame count kept as the upper bound; the analysis loop paces the same way. Every frame of the UI is still walked once, Workshop's or not (so a blocker from anywhere is still found), the planted-overlay control is unchanged, and a step still cannot be interrupted: it is only kept small by yielding often. The scan reports `ui.scan.yields`, `work_ms`, `longest_slice_ms` and `elapsed_ms`, so the next run measures the effect. **Not yet measured in the client**; the offline test pins the yield behaviour on a virtual clock (about one yield per budget, no stretch longer than the budget plus one frame, a stopped clock still bounded by the count, a clock read every 32 frames).

*Pause probe.* `client.runner.pause-probe` kept its 2 s pause; its budget is 4 s (was 2 s, so the 9 ms by which the wait ended late was reported as "late"). The pause is a cooperative wait (the runner schedules nothing for the case meanwhile); the runner and report wording now say so.

*Real-client check that closes M5.1.* Run **Core (reference models)**, **Client facts** and **Interface reachability** (Workshop open on Opportunities): `market.reference.batch` and `market.reference.invalid-values` pass; `client.lua.nan-comparisons` passes and its facts say which NaN comparisons differ; `ui.workshop.reach-scan` passes with `ui.scan.longest_slice_ms` about 2 to 4 (was 14.6) and the run's overrun count 0 or close to it; `client.runner.pause-probe` has no "late" note. If `invalid-values` fails on a NaN buyout, that is a real production finding (see above), not a model error.

**M5.2: a real production defect, NaN auction buyouts (2026-11-12; fixed, client rerun pending).** The Lab's second real-client run (Forever 1.60.1 build 70888) failed `market.reference.batch` and `market.reference.invalid-values` on records with a NaN buyout (seeds 7100001, 7100013, 7100014): the corrected model rejected them, **production classified them as bid-only.** *Root cause:* `Prices.Batch:Add` tested `raw == 0` (bid-only) before any finiteness check, and in that client a NaN equals 0 (it also equals itself and is both less and greater than ordinary numbers), so the `raw == 0` branch took it. Desktop Lua 5.1 never reads NaN == 0, so the offline suite could not show it. `W.Int` (`v ~= v or v < lo ...`) had survived only because `NaN < lo` happens to be true there. *Fix:* `W.Finite(v)` (Data.lua) decides finiteness from the printed form (digits, point, exponent and signs only; NaN and infinities print with letters), with no comparison, as `REF.Finite` already did for the model. It now runs first in `W.Int` (so every item, count and copper amount that goes through it), in `Batch:Add` before the zero test (a NaN, infinity or non-number buyout is **invalid**; only a finite 0 is bid-only), and in `History.Add` / `History.Day`. Valid listings are priced exactly as before (the 200 seeded houses and 60 market sets agree). *Tests:* `test_workshop_market_reference.lua` section 6c: the `W.Finite` contract, every field with NaN, negated NaN and both infinities, a finite and negative zero, negative, string, fractional and over-limit buyouts, the accounting of a mixed batch (read = used + bid-only + invalid, and the invalid records change no price), and an **emulation** that makes `tostring` print "nan" for one chosen number while its comparisons stay ordinary (which is what the code sees for a NaN that is == 0): the old `Batch:Add` fails it, production passes. `market.finite.records` is the same check for the client. *Mutation:* four new entries (`market.batch.finite-check-dropped`, `market.data.int-finite-dropped`, `market.data.finite-always-true`, `market.history.price-finite-dropped`); the market group is **50 of 50 killed.** *Other `v ~= v` guards (left alone, not auction or money):* `Observe.BagCount`, `Stock` and `Materials` held counts (`n ~= n or n < 0`) and `Observe`/`History` fraction checks; in this client they rely on `NaN < 0` being true (the reported behaviour; not re-verified for each), so they are worth `W.Finite` if they are ever reused for money. In the Lab: `Fixtures.lua` (`Clamp`, `Rate`, `Whole(seed)`), `Reach.lua` `Num` and the crafting model's `Qty`, as noted above. *Performance numbers of that run* (worst slice 35.1 ms, worst frame 50 ms, overruns 0, Workshop window closed so `ui.workshop.reach-scan` skipped): the reach scan did not run, so **nothing is claimed about it.** A confirmed accounting defect explains how a long slice could have no overrun: `Runner.Step` timed only a case's steps, but a case's setup (`TL.Workshop()` loading the whole Workshop addon on demand for the first `needs = workshop` case, and the saved-data fingerprint) runs inside the same slice, untimed. That setup is now timed and, when longer than a slice, listed as an overrun under its case (`test_testlab.lua` 3b). Whether the 35.1 ms was that load is **not established** (the report did not say); the next run will name the case if it was. The frame figure (50 ms) is the game's frame interval and includes the slice, the window and every other addon. **Rerun in the client:** Core (reference models) (`market.reference.batch`, `market.reference.invalid-values`, `market.finite.records`), Client facts, and Interface reachability with the Workshop open on Opportunities.

**Test Lab window redesign (2026-11-12): presentation only.** `TwichUI_TestLab/Window.lua` rebuilt after the approved mockup (`docs/test-lab/lab-mockup.png`), with `Kit.lua` (controls) and `View.lua` (pure presentation logic: categories, counts, filters, search, empty states, details). No case, runner behaviour, safety class, report schema or production file changed; the runner records two more read-only fields per case (`fails`, `failed`) and the report gained `Report.BuildFailures` (the failures excerpt; `Build` is unchanged and tested to be). The guided prompt's title says where the step stands. Layout, behaviour, limits and what stays different from the mockup: `docs/testlab.md` "The window". Evidence: unit-tested offline (`tests/test_testlab_window.lua`, with 11 hand-made defects in `View.lua`, `Window.lua`, `Kit.lua` and `Report.lua` all killed), simulator-tested (`tools/simlab/testlab.sh`, nine launches with screenshots), screenshot-reviewed in the simulator (four defects found and fixed from the first captures). **Not tested in the game.**

**Handoff to M6 (client API probes).** Probes to add to `cases/Client.lua`, each reporting a value labelled `client`, nothing written: (1) does `SetOverrideBindingClick`/`ClearOverrideBindings` work from addon code out of combat, and what does `GetBindingAction("F9")` say before and after (`ui.pointer.api` already reports presence); (2) whether `SetScript("OnEnter")` on a plain Frame enables the mouse, and what `EnableMouse(false)` does to `IsMouseClickEnabled`/`IsMouseMotionEnabled` (the simulator says both go false; the Lab model assumes the same); (3) whether `Button:Click()` on a disabled or hidden button runs `OnClick`; (4) whether a mouse-enabled frame with `SetMouseClickEnabled(false)` lets a click through to what is under it, and whether `SetPropagateMouseClicks` does; (5) how equal-strata-and-level frames are ordered under the pointer (create two Lab-owned frames, read `GetMouseFoci`; this decides the "ambiguous" verdict); (6) whether `GetMouseFoci` returns non-frame regions and a scroll child outside its viewport; (7) whether `SetHitRectInsets` is callable from addon code out of combat (it is documented as protected). All of these need frames the Lab makes itself (class `owned`, which the registry already accepts), never the player's UI. The format and `x % 0` probes from the previous section are still open.

**M6, client UI API probes (2026-11-12): test tooling only; no production file changed. Real-client acceptance is pending: nothing about the Forever client is claimed until the cases run in the game.** Reference: `docs/testlab.md` "Client UI API probes (milestone 6)" (the cases, the steps, the safety and cleanup guarantees, the source evidence from the Forever API documentation, and the findings table (filled in by M6.1 from the first real run).

*Built.* Two opt-in groups (never ticked, never in an unqualified run; `TL.Category{ optin = true }`, new). **Client UI API (own frames)**, four automatic `owned` cases: `api.binding.override` (an override binding made, cleared, made again and cleared out of combat in one step with no yield, read through `GetBindingAction`; the combat answer is read from `C_RestrictedActions`, never tried), `api.mouse.states` (the three mouse flags after each way of switching input, for a Frame and a Button, hidden and disabled included, which method names exist), `api.click.programmatic` (`Click()` counters on a visible, disabled, hidden, mouse-off, click-off and parent-hidden button, with a control row), `api.hitrect.insets` (`SetHitRectInsets` out of combat, positive/negative/asymmetric values, the read-back, the Lab's arithmetic on it). **Client UI API (guided)**, four `guided` cases: `api.binding.keypress` (a real F9 press reaches a Lab button, again after clear and re-register), `api.click.overlap` (a lower Button and an upper frame with mouse off / on / clicks off / propagating), `api.order.equal-level` (two Buttons of equal strata and level in four arrangements: creation order, show order, containers), `api.hitrect.pointer` (clicks inside the paint but inside the removed strip, in the middle, and outside the paint inside the added strip). Each click scenario records **three separate pieces of evidence**: the `GetMouseFoci` stack, the frames whose `OnClick` / `OnMouseUp` actually ran, and what the person saw on top (answer buttons on the prompt), and never assumes they agree; the geometry model's prediction is added beside them. The reachability analysis is **unchanged**; equal strata and level stays `ambiguous` whatever `api.order.equal-level` finds (it reports an observation across four arrangements, "no single rule" if none fits, and says it is not universal).

*Safety.* Every frame is made by `Probe.lua` (named `TwichUITestLabProbe<role>`, one per role for the session, reset on reuse) and none of any other addon is touched; handlers only append to a bounded list; the backdrop absorbs probe clicks so none reaches the 3D world; the only key binding is the existing `Guided.lua` one (a click request binds none); `Runner` releases the probe frames and the guided request on a normal end, Stop, a closed window, an error, a timeout and combat; nothing is written (the runner's fingerprint brackets every case). A restricted call is recorded as an observed restriction, never retried another way. Static scan: 17 files; no forbidden name was added.

*Measurement clarity.* The one-time Workshop load is timed on its own (`TL.Workshop()` now says when *it* loaded the addon) and listed in the report under `setup` with its length and the case it preceded; a case's own duration starts after it; an overrun caused by the load is marked `(setup: Workshop load, not the case's own work)`. Nothing is hidden: the load still counts in the run total, `worstSlice` and the overrun count. The 23.6 ms step reported against `price.unit.round-up` is *probably* this load; the next report will say. The reachability scan's cooperative pacing (M5.1) is untouched; **its real-client performance is still unverified** (the latest run had the Workshop closed): run **Interface reachability** with the Workshop open and read `ui.scan.longest_slice_ms`.

*Numeric-safety audit (limited, read-only).* Searched for `v ~= v` (the NaN idiom that desktop Lua 5.1 and this client read differently: in the client a NaN equals itself and 0 and compares both less and greater than ordinary numbers, M5.2) in the Workshop and the Lab. No new production defect was found; nothing was changed in production.

| Site | Guard | Where the input comes from | Can it be malformed? | In the client |
|---|---|---|---|---|
| `Observe.BagCount` (Workshop/Observe.lua) | `type ~= number or n ~= n or n < 0` | `C_Item.GetItemCount` (an integer, a secret, or a failure) | not expected; no NaN source | rejects a NaN only because `NaN < 0` is true there (M5.2). `client.lua.nan-guards` `count_guard` row re-measures it |
| `Stock.Craft` (Stock.lua) and `Materials.Rows` (Materials.lua) | the same guard on `have(item)` | `Observe.BagCount` or a test's function | same | `numeric.guards.held-counts` (core, pure) feeds NaN (runtime, literal, negated), a string, a negative and -inf through both and **asserts** "unknown, never a count, never ready"; +inf is *reported* (it passes the guard on every Lua, and the game cannot give one) |
| `Prices.Batch:Add`, `History.Add/Day`, `W.Int` | `W.Finite` (no comparison) | auction records, saved history | yes (the M5.2 defect) | fixed in M5.2; `market.finite.records` |
| `Fixtures.lua` (`seed`, `Clamp`, `Rate`, `Whole`) | `v ~= v` | typed-in numbers and the Lab's own arithmetic | no | not a guard of untrusted input; left |
| `Reference.lua` (craft hold guards, 2 sites) | the production idiom, mirrored | `FX.CraftHave` (integers or nil) | no | the model mirrors production on purpose; `REF.Finite` is used where a NaN is expected |
| `Reach.lua` `Num` | `v == v and v > -1e12 and v < 1e12` | `GetRect`, `GetEffectiveScale`, insets, frame level | not expected | **the one guard that would *accept* a NaN** if a NaN equals itself and is both less and greater than ordinary numbers; the `reach_num` row of `client.lua.nan-guards` measures it. Lab only, no known NaN source: not changed. **Narrow follow-up if that row shows `nan=A`:** use a comparison-free finite test (as `REF.Finite`) in `Num` |
| `View.lua` duration formatting | `ms ~= ms` | the Lab's own clock | no | display only |

Outside the requested scope and **not audited here**: about 35 other `v ~= v` sites in `!!!TwichUI/` (nav, markers, pins, glows, setup, `auction/Mail.lua`, `auction/Price.lua`). Two of them touch money and were only read, not analysed: `auction/Price.lua:142` (`each < 0 or each ~= each`, which rejects a NaN only through `NaN < 0`) and `auction/Mail.lua:40` (`Num`: `v ~= v` alone, which in this client would let a NaN through if one ever arrived; its input is the game's mail money, where none is expected). Neither input was traced. A separate pass, not part of M6.

*Verification (evidence labels).* **Unit-tested:** `tests/test_testlab_api.lua` (new; stand-in frames that behave several different ways on purpose, so the probes' measuring and cleanup are checked and no Forever behaviour is asserted), `tests/test_testlab.lua` (setup accounting, static scan), `tests/test_testlab_window.lua` (opt-in groups unticked). Ten hand-made defects in `Probe.lua`, `Guided.lua`, `Runner.lua`, `Lab.lua` and `cases/Api.lua` (a release dropped, the trial kept, a clear dropped twice, `ups` counted as clicks, the key requirement dropped, outside-square clicks counted, opt-in dropped, the inset reset dropped, mouse not turned off, the control row dropped) were all killed. **Simulator-tested:** `bash tools/simlab/testlab.sh` (the Lab window with the new groups; the new files load with no Lua error). **Not tested:** every client behaviour the probes measure; the look of the prompt's answer buttons and of the probe arena. The mutation runner was not used (no production number or money logic changed).

*Real-client check that closes M6.* (1) Tick **Client UI API (own frames)** and Run; copy the report. (2) Tick **Client UI API (guided)** and Run; press F9 when asked, click the white square when asked, answer the colour questions; copy the report. (3) Fill the findings table in `docs/testlab.md` from the two reports, and note every row where the Lab's model differs from what was observed (each such row is a narrow follow-up, not a change made by this milestone). (4) Run **Core**, **Client facts** and **Interface reachability** (Workshop open on Opportunities) once more: `numeric.guards.held-counts` and `client.lua.nan-guards` pass or name a real finding; the report's `setup` line names the Workshop load; `ui.scan.longest_slice_ms` is small. (5) Afterwards F9 does what it did before and no Lab frame is on screen.

**Handoff to M7 (benchmarks).** M6 leaves `Probe.lua` and the `owned` class in use; M7 needs neither. For M7: `Fixtures.lua` sizes and `cases/Bench.lua`; the run report already separates setup (the Workshop load) from a case's own time, so a benchmark case's `ms` is its own; use `GetTimePreciseSec` (the Runner's clock) and the noise rule of section E (5-run median and MAD), keep every benchmark `pure` or `readonly`, and put benchmarks in an opt-in group like the probes so an unqualified run stays short. The frame-time figures (`worstFrame`) include every other addon; compare them only between runs of one session. Before M7 relies on `ui.scan.*`, get the Workshop-open reachability run above.

**M6.1: integrating the real-client findings (2026-11-12; one production file set changed, test tooling otherwise; real-client rerun pending).** The first real run of the M6 probes (Forever 1.60.1, build 70888: automatic API 4 of 4, guided API 4 of 4, Core 27 of 27) showed where the Lab's assumptions differed from the client. Verified-behaviour table: `docs/testlab.md` "Verified Forever behaviour".

*Root causes.* (1) **Held counts: a positive infinity counted as stock.** `Materials.Rows`, `Stock.Craft` and `Observe.BagCount` judged a bag count with `n ~= n or n < 0`; infinity is neither, so `numeric.held.inf` printed `have inf short 0 craft ready`. (Desktop Lua accepts it too; the idiom also depends on how an interpreter compares a NaN.) (2) **`IsMouseEnabled` is not "either".** The client reports it false for a click-only and a motion-only frame; `Reach.Eligibility` and `Collect` asked it first, so such controls were rejected or never collected (a click-only overlay would not have blocked a click). (3) **Propagation was read with a method the client does not have.** Forever's API documentation (`SimpleScriptRegionAPIDocumentation.lua`) lists `SetPropagateMouseClicks` and `CanPropagateMouseClicks`; the Lab called `GetPropagateMouseClicks`, got no answer, read that as "does not propagate", and so called a propagating overlay a blocker. This cause is inferred from the documentation and the symptom; the raw guided report is not in the repository, and `api.click.overlap` now records `propagate_readback` beside each click so the next run settles it. (4) **Geometry:** `Reach.Num` (`v == v and v > -1e12`) would accept a NaN in the client.

*Corrections.* `W.Count(v)` (Data.lua) = `W.Int(v, 0, MAX_ID)`: finite decided from the printed form, whole, 0 up to 2147483647; unknown stays nil, never 0. Used by `Observe.BagCount`, `Materials.Rows`, `Stock.Craft`; the model has its own `REF.Held`. `REF.Qty` and the `Fixtures.lua` guards use the printed-form test too (an infinite `want` made `REF.Take` loop for ever). `Reach.lua`: the click/motion flag of the operation decides (`IsMouseEnabled` only as a conservative fallback when the separate methods are missing; `mouse-disabled` only when both are off); `Collect` takes a frame with click **or** motion; propagation is read through `RC.Propagates` (`CanPropagateMouseClicks`, then `GetPropagateMouseClicks`, else nil = unknown); one click-capable propagating frame over the control gives `reachable` with `via = "propagation"`, two or more or an unreadable one give `unknown`, a non-propagating one still `blocked`, equal strata and level still `ambiguous`; `Num` checks the printed form first. No change to the material-source order, `W.Split`, the planner or the UI. `Press` is unchanged in behaviour (it asks the same eligibility) and its header now records that the client's `Click()` is more permissive on purpose.

*Audit of the remaining numeric guards (Workshop and Lab).* Fixed: the three held-count sites, `REF.Rows`, `REF.CraftState`, `REF.Qty`, `Reach.Num`, `Fixtures` `Whole`/`Clamp`/`Rate`. **Safe because the input is already validated:** `W.Split` (`n > 0`; its `want` comes from queue quantities cleared by `W.Int`, and bank and guild counts from `Storage` sums of `Int(1..1e6)` records), `Stock.Counted`. **Potentially unsafe, left alone (display only):** `View.lua` `V.Duration` (`ms ~= ms`; a NaN clock difference would print "nan ms", nothing is decided from it). **Intentional probes, not guards:** `Reference.lua:63`, `cases/Client.lua` `nan-comparisons` and `nan-guards` (they report how the OLD idioms behave). Not audited: the same pattern in `!!!TwichUI/` outside the Workshop (about 35 sites, including `auction/Price.lua:142` and `auction/Mail.lua:40`, listed in M6 above).

*Verification.* Unit-tested: `test_workshop_crafting_reference.lua` section 6d (13 malformed and 6 good counts through `W.Count`, `Materials.Rows`, `Stock.Craft`, `Observe.BagCount` with a stand-in `C_Item`, the model, an infinite `want`, and an emulation in which 5 and 0 print as "nan"), `test_reach.lua` section 8 (click-only, motion-only, mouse-off, click-off and click-only overlays, propagation through each getter, blocking, unreadable, two propagators, a tie, insets both ways, parent hidden, disabled, an old client without the separate methods, NaN geometry), `test_press.lua`, `test_testlab_api.lua` (the guided overlap case under three stand-in clients). The new tests fail against the previous `Reach.lua` and production files. Mutation: `--group crafting` **62 of 62** killed (six new entries: `crafting.materials.count-old-guard`, `crafting.stock.craft-count-old-guard`, `crafting.observe.bagcount-old-guard`, `crafting.data.count-zero-rejected`, `...count-negative-accepted`, `...count-unbounded`; two older entries re-pointed), `--group market` **50 of 50**; 21 hand-planted defects in the new `Reach.lua` code on a scratch copy: first pass 19 of 21, the two survivors (the old-client aggregate fallback in `Collect`, the tie note) got tests, second pass **21 of 21**. Simulator-tested (classification only, labelled simulated): `tools/simlab/workshop.sh` all 13 launches (including the deliberately wrong one), 433 checks per launch, including the new Reachable → Propagated → Blocked → Reachable sequence; `tools/simlab/testlab.sh` PASS; `tools/simlab/tests/lab_guard.sh` 28 of 28. Full `./tests/run.sh`: **205 passed, 0 failed.**

*Performance.* `W.Count` costs about 0.25 µs more than the old guard per count (a `tostring` and a match; tens per refresh). The scan asks two flag questions per passive frame instead of one: 41.7 to 47.0 ms for 20,000 stand-in frames (+13 %, desktop Lua); in the client each question is a protected call, so the cost per frame is higher in absolute terms, but the scan is still time-sliced. Not measured in the client.

*Real-client checks (not done).* (1) Core: `numeric.guards.held-counts` passes with `inf`, `inf-minus-inf`, fractions and `huge` all unknown. (2) Guided `api.click.overlap`: read `propagate_readback` (expect `true via CanPropagateMouseClicks`) and `model` for `propagate` (expect `reachable (through propagation)`, agreeing with `onclick`); if the readback is `unreadable`, the model says `unknown` and the cause above is wrong or incomplete. (3) Interface reachability with the Workshop open: `scan.capturing` should be close to the previous run's figure; a large jump would mean a default plain frame reports its click flag true, and `Collect` needs a narrower rule. (4) F9 and the Lab window unchanged afterwards.

**M6.1 stops here.**

**M7, benchmarks (2026-11-12): test tooling only; no production file changed. Real-client performance acceptance is pending until the suite runs in Forever.** Reference: `docs/testlab.md` "Benchmarks (milestone 7)" (workloads, fixtures and seeds, methodology, comparison policy, commands, in-game steps, limits). Built: `Bench.lua`, `Workloads.lua`, `Baselines.lua`, `cases/Perf.lua` (opt-in category), `FX.Bulk` and `FX.Crafting{bulk=true}`, per-case frame intervals and progress text in the Runner, a separate "benchmarks (schema 1)" report section (report schema 1 unchanged), `tests/bench_workshop.lua`, `tests/test_testlab_bench.lua`. Deviations from section E: workloads are 1k/10k/50k records (+250k offline) rather than 2k/50k/250k; the file is `Workloads.lua` plus `cases/Perf.lua` instead of `cases/Bench.lua`; retained memory is offline or in separate `perf.retained.*` cases. Findings: the last step of a large batch (`Items()` over ~12,000 items) is one production step of about 40 to 90 ms offline, the longest uninterrupted step of any workload, and worth a look when Market Intelligence adds more per-item work. UI redraw benchmarks are deferred (they need the player's real state). Offline figures (WSL, Lua 5.1, quiet machine, labelled host `dev-wsl`, five repetitions) are in `tests/test-output/` only, not committed.

**M7.1, performance findings and targeted corrections (2026-11-12). Real-client confirmation of the corrections is pending.** Evidence: two complete Forever runs (1.60.1 build 70888, unfocused 49.6 s and focused 36.5 s; 19 cases each, 17 pass, 1 error, 1 skip), kept as preliminary instrumentation-level-1 baselines: not overwritten, not recorded in `Baselines.lua`, not labelled optimized.
- **Overflow (`perf.market.stats.6k`, `integer overflow attempting to store 39286995442`): a Lab defect, not the checksum and not production.** `HistoryMarket` (`Workloads.lua`) built the fixture's item strings with `("%d,1,1,1,0"):format(price)`; the generator's prices drift past 2^31 (this one is 39,286,995,442 copper), and the client's `string.format("%d")` refuses that, as recorded for M2/M3. Reproduced offline under `tests/client_format.lua` (same message and number) and fixed with `%.0f` (as Prices and History do); three failure-message formats of copper values in `Workloads.lua` got the same. The checksum was never the cause (it stays below 2^31 x 31 + the terms, exact in doubles); verification is unchanged and a wrong week statistic is still caught (`test_testlab_bench.lua`, with a mutant). Not a production bug: `Market.Stats/Trend/Compare` were not touched.
- **The 625 ms slice: not attributable from the two runs, because the export kept the first 20 overruns and no phase.** Unyielded Lab-owned work was found by instrumenting `Measure` (offline CPU, a different clock, so rankings only): the crafting workloads serialised their whole input in one `fingerprint` (about 110 to 150 ms offline each, about 2.4x in the client), and the history, statistics and fold setups and the replays generated and checked 400-day calendars in single calls (50 to 120 ms offline). These are now yielded on a 4 ms budget (a clock-based `Pace`, `FX.Calendar` takes an optional `tick` that draws nothing, so fixture output is identical). A segment also used to span the end of one repetition and the first step of the next; it now ends at each. What remains un-yielded: one forced collection (`collect`, the retained cases only) and one verification piece, each shown by name in the report. Whether this accounts for the full 625 ms is **not established**; the next run will say (`longest segments between yields`).
- **Market finalization is a real, bounded live hitch, now corrected.** `Scan.lua` read 400 records per timer tick, then called `batch:Items()` in the last tick: one pass that formats five numbers per item, 40 ms at 12,000 items and 135 to 145 ms at the 40,000 limit offline (the 82 ms focused step of the 50k batch is consistent with this call, which offline measured 77 to 80 ms in the benchmark's last step; the benchmark and the scan ran the same code). `BeginCommit`, `Job:Step` (120 items) and `Apply` were measured and are not hitches (at most 4 ms per step offline). Correction: `Batch:ItemsJob()` / `ItemsJob:Step(n)` / `:Result()` in `Prices.lua` (`PR.ITEMS_STEP = 400`); `Items()` runs the same job to the end, so it returns the same answer; `Scan.lua` builds the entries on following timer ticks with the existing token, generation and "auction house still open" checks, then continues into the unchanged commit. Preserved: the saved schema, history, completeness rules, atomic `Apply`, cancellation (closing the window mid-build interrupts and writes nothing: test and mutant), and the over-limit order. Not split: the sort of a market over 40,000 items (rare, one step). A scan now takes one or more extra ticks before saving (`test_workshop_prices.lua` expects them). The benchmark follows the scan (`market.aggregate.*` is **v2**; v1 figures are not comparable by `Compare`).
- **History and memory outliers are stress-test artifacts of the Lab, not production.** `history.insert.400d` replays 80,000 `History.Add` calls for 200 items; a real scan adds one observation per item per scan, and the production commit already merges 120 items per tick. The 68 MB peak is the synthetic calendar and its replay kept alive for verification, outside the timed section; forced collections occur only in the three `perf.retained.*` cases. No history retention, aggregation or format was changed.
- **Verification.** Unit: `test_testlab_bench.lua` (the overflow workload under the client format guard, the beyond-32-bit price present in the fixture, a wrong week average caught, signature separation, phase and segment arithmetic on a scripted clock, the report and the result line, level-1 and level-2 lines comparable), `test_testlab.lua` (longest-20 overruns of 26, counts by case), `test_workshop_prices.lua` (stepped job equal to `Items()` for steps 1/3/400, under and over the limit, with priority; the extra ticks; close during the build). Reference models: `test_workshop_market_reference.lua` and `test_workshop_crafting_reference.lua` pass. Mutation: `--group market` 52 of 52 killed (three new: `market.batch.stepped-boundary-item-lost`, `market.batch.stepped-ranking-shifted`, `market.scan.build-ignores-closed-window`), `--group crafting` 62 of 62. Simulator: `tools/simlab/workshop.sh` (433 checks incl. the real Scan against the fake house) and `testlab.sh` pass with only the classified simulator limitations. Offline, same machine, 50k records: longest step 77 to 80 ms before, 4.4 ms after; median about 170 to 185 ms before and after (within noise; v1 and v2 are not the same workload).
- **Real-client rerun:** `docs/testlab.md`, "Rerunning only what M7.1 changed". Remaining limits: instrumentation attributes Lab segments in the client's clock only once run there; the two preliminary runs cannot be re-read for phases; a forced collection cannot be split.

**M7.1 stops here; the next work is product features (Market Intelligence).**

## Unresolved decisions (product input needed)

1. **How the Lab is opened.** `/run C_AddOns.LoadAddOn("TwichUI_TestLab")` (M1, no change to the release), or a hidden core `/tui lab` that only says "development builds only" when the addon is absent (about 15 lines shipped to players).
2. **Market side with the auction house closed.** Today the realm's newest market of any side is used. Should a character's own faction (or "unknown"/neutral) be preferred, with others only as a labelled fallback?
3. **The profit bound.** When a craft needs more than the cheapest listing holds, should costs use the saved next-higher price (a tighter, still minimum, estimate), or stay as they are with the flag?
4. **Getting the Lab into a development install.** A manual copy, or an option in the machine-local deploy script.
