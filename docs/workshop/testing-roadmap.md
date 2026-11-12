# Workshop testing roadmap

This plan covers how TwichUI Workshop's correctness, regressions, performance and real-client behaviour are verified. It is for anyone, person or agent, who implements the milestones below. It records what existed on `feature/workshop` at `d09e6dcb` (2026-11-12) and what to build next. Sections A to G are the plan as written then; **section H records what has been built (M1, M2) and found.** `docs/workshop.md` remains the feature reference, and `docs/simulator-lab.md` and `docs/diagnostics.md` remain the tool references.

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
- **Tests:** the two Trend mutants from section A are killed (by hand until M4 exists).
- **Depends on:** M1.
- **Out of scope:** changing Trend unless the model shows a real defect. Report it first.

**M3. Crafting and shopping reference models**
- **Objective:** a brute-force planner on ≤ 6 materials; invariants for `Materials.Rows`, `W.Split` and `Shopping.Plan`; a reference for the craft estimate.
- **Files:** `cases/Crafting.lua`, `Fixtures.lua` queue generators.
- **Accept:** the invariants hold over about 300 generated queues; the cases agree with the brute force; shrinking is just "print the seed and the size".
- **Depends on:** M2's PRNG.
- **Out of scope:** the multilevel planner.

**M4. Mutation runner**
- **Objective:** turn the probe described in section A into a reusable runner. Stage a copy of `TwichUI_Workshop/` beside a folder of symlinks to the core's entries, so that `ROOT .. "../TwichUI_Workshop/"` resolves to the copy. The path must be absolute.
- **Files:** `tools/mutate.sh` (bash) plus a mutant list per file, staged in a temporary folder outside the repository.
- **Accept:** a baseline-must-pass guard; the report lists killed and survived mutants and which tests killed them; about 20 mutants take under 2 min.
- **Depends on:** none (more valuable after M2 and M3).
- **Out of scope:** automatic mutant generation.

**M5. Reachability**
- **Objective:** the observed button and hover failures become testable.
- **Files:**
  - an opt-in `Press(btn)` in a test kit that refuses hidden, disabled or mouse-disabled controls (`MIFake` records `EnableMouse` and insets, opt-in so existing tests are unchanged)
  - simulator S2
  - Lab `cases/UI.lua`: a real-client reachability scan of the Workshop window (rects, strata, levels, insets, click enabled) and the guided `GetMouseFoci` probe for the Add button and a row
- **Accept:** a planted overlay fails all three.
- **Tests:** unit-tested, simulator-tested, guided real-client run.
- **Depends on:** M1.
- **Out of scope:** fixing a failure found. Report it.

**M6. Client API probes**
- **Objective:** turn offline assumptions into observed facts.
- **Files:** `cases/Client.lua`.
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
- **Files:** `Fixtures.lua` sizes, `cases/Bench.lua`, `tests/bench_workshop.lua`, result lines, a comparison note in this document.
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
| Pure algorithm | deterministic cases with hand arithmetic + a property test over seeds; rerun the mutants for that file | simulator |
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

**Remaining gaps:** `Quote`, `Estimate` and the Opportunities arithmetic (M3); `Shopping.Plan` and `Materials` (M3); the text round trip and the eviction order of markets when `at` ties (M9); the scan state machine; the new Lab cases have not yet run in the real client (the offline run shows the cases pass in plain Lua 5.1, not in the client's interpreter); the mutation probe is a script outside the repository (M4).

**Handoff to M3 (crafting and shopping reference models):** reuse `TL.Fixtures.Rng` and the pattern of `Reference.lua` (a model built from the documented contract, with whole-number arithmetic, compared with production after every step, failures printing model, seed, scenario and input; known-gap characterization tests for contract corners). Add queue/recipe/stock generators to `Fixtures.lua` (bounded by the planner's limits: 30 recipes, 16 materials, 4 candidates), a brute-force planner for at most 6 materials against `Shopping.Plan`, invariants for `Materials.Rows`, `W.Split` (bags + bank + guild + still needed = need; no layer negative or above what it holds) and an independent craft-estimate model against `Prices.Estimate/Quote` (the profit bound with `cheapest` set is a product decision, see "Unresolved decisions" 3). Seeds: continue at `7500000+i`. Never call `Prices.<commit>`-type writes in Lab cases; keep the large suites offline.

## Unresolved decisions (product input needed)

1. **How the Lab is opened.** `/run C_AddOns.LoadAddOn("TwichUI_TestLab")` (M1, no change to the release), or a hidden core `/tui lab` that only says "development builds only" when the addon is absent (about 15 lines shipped to players).
2. **Market side with the auction house closed.** Today the realm's newest market of any side is used. Should a character's own faction (or "unknown"/neutral) be preferred, with others only as a labelled fallback?
3. **The profit bound.** When a craft needs more than the cheapest listing holds, should costs use the saved next-higher price (a tighter, still minimum, estimate), or stay as they are with the flag?
4. **Getting the Lab into a development install.** A manual copy, or an option in the machine-local deploy script.
