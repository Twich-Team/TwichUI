# TwichUI Test Lab

A **development-only** addon, `TwichUI_TestLab/`, that runs selected TwichUI code inside the real WoW: Forever client and produces a report you can copy. It is milestone 1 of `docs/workshop/testing-roadmap.md` (sections C, F, G); later milestones only add case files (milestone 2 added `Fixtures.lua`, `Reference.lua` and `cases/Market.lua`, below; milestone 5 added `Reach.lua`, `Guided.lua` and `cases/UI.lua`, see "Reachability and the pointer probe"; milestone 6 added `Probe.lua` and `cases/Api.lua`, see "Client UI API probes").

It is not a player feature. It is never packaged and never offered to players (see "Not in releases").

## Installation (development only)

Copy the folder `TwichUI_TestLab/` from the repository into your development client's `Interface/AddOns/` folder, beside `!!!TwichUI`. It needs `!!!TwichUI` turned on. It is marked load-on-demand, so it does nothing at login. The machine-local, gitignored `tools/deploy.sh` also copies it (and adds the extra interface number to its `.toc`, as for the other addons), so a normal deploy to the development client installs the Lab. That script is never part of a release.

The only change to a released addon is one row in the TwichUI data bar menu (`!!!TwichUI/modules/SettingsBrokerMenu.lua`): **Test Lab (development)...**. It is drawn only while the `TwichUI_TestLab` folder is installed (`C_AddOns.DoesAddOnExist`), so a standard release, which never contains the folder, shows nothing. The first click loads the addon (which opens its window); after that it opens and closes the window. If the load fails it says why in chat. The shipped code is that one row and about ten lines; `TwichUI_Workshop` is unchanged.

## Opening and running

1. In game: click the TwichUI data bar entry and choose **Test Lab (development)...** (or `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`). Loading opens the window once. Afterwards the menu row and `/tuilab` open and close it.
2. Tick the groups to run on the left (every group is on by default except **Pointer probe (guided)**, which asks things of you and runs only when you tick it) and press **Run**.
3. Watch the run state beside the buttons (case *n* of *m*, the case id, elapsed time), the cards, the bar and the table, which fills as cases finish.
4. **Stop** is enabled while a run is going. **Copy report** and **Copy failures** fill the report box at the bottom and select it; press **Ctrl+C**, then paste the text where it is needed (the game gives addons no clipboard, so the window never says it "copied" anything).
5. Esc or the close button closes the window, and **closing it stops a run in progress**.

Nothing runs by itself: not at login, not at load, not on a timer.

## What the categories hold

| Category | Class | Evidence label | What it does |
|---|---|---|---|
| Core calculations (`core`) | `pure` | **synthetic** | Production Workshop code (`Prices`, `History`, `Market`, `W.Split`) in the client's Lua, on made-up data handed in as arguments. The same file, `cases/Core.lua`, is run offline by `tests/test_testlab.lua`. |
| Client facts (`client`) | `readonly` | **client** | Lua number behaviour (exactness below 2^53, `%.0f`, division by zero, yielding across `pcall`), which API names exist (`GetTimePreciseSec`, `C_AddOnProfiler`, `GetMouseFoci`, `EnumerateFrames`), how this client compares a NaN (`client.lua.nan-comparisons`), and a 2-second pause probe of the Lab's own runner (a cooperative wait, with 4 s of budget). Values the client is not documented to give are *reported* as facts, not asserted. |

**Fixtures and reference models (milestone 2).** `Fixtures.lua` makes deterministic synthetic markets from a seed (its own Wichmann-Hill generator, so a seed gives the same data in plain Lua and in the client): `FX.Listings` (auction records, with deliberately malformed ones marked by `intent`), `FX.Calendar` (a market's scans over days, with gaps, repeats, clock moves and cut scans), `FX.Markets`; every size is clamped to `FX.LIMITS`. `Reference.lua` holds independent models of the batch and of the history and statistics (how they differ from the production code is in the file's header). `cases/Market.lua` adds five bounded `pure` cases to the core category (`market.reference.batch` 16 seeds, which names the first record the model and production read differently, `market.reference.invalid-values` (every malformed value the generator draws, one at a time, in each field), `market.finite.records` (every NaN/infinity form in each field of a record, a finite zero still bid-only, and the accounting of a mixed batch), `market.reference.history` 6 seeds, `market.trend.window-and-percent`); they call `History.Add/Trim` and `Market.*` with a market table handed in, and never the saved markets or `Prices.<commit>`. The large randomized suite (200 scenarios per model) stays offline: `tests/test_workshop_market_reference.lua`.

**Crafting fixtures and reference models (milestone 3).** `Fixtures.lua` adds `FX.Crafting` (a small craft queue with what is owned in the bags, bank and guild bank, auction price lists, vendor offers, known recipes and an optional cut), `FX.Economy` (recipes as the window may read them, some malformed on purpose) and `FX.StockObs` (what the bank and guild bank were last seen to hold); `Reference.lua` section 4 adds one-item-at-a-time allocation, combined materials, the stock rules, the cost of any sourcing choice for the shopping plan with an exhaustive enumeration, the craft estimate and the Opportunities order. `cases/Crafting.lua` adds three bounded `pure` cases to the core category (`crafting.reference.allocation` 24 seeds, `crafting.reference.shopping` 8 seeds and at most 64 sourcing choices each, `crafting.reference.estimate` 20 seeds). They call `W.Split`, `Materials.Rows`, `Shopping.Plan`, `Prices.Quote/Estimate` with explicit inputs, never the saved prices, stock or queue. The stock cases (they fill the saved storage records to test `Stock.Sources`) and the large randomized suite stay offline: `tests/test_workshop_crafting_reference.lua`.

**Reachability and the pointer probe (milestone 5).** A working click handler does not prove a working button, so this category reads what the client does with the pointer. Section "Reachability and the pointer probe" below has the whole picture; `Reach.lua` is the analysis, `Guided.lua` the guided-case mechanism, `cases/UI.lua` the cases (`ui.pointer.api`, `ui.workshop.reach-scan`, and the three guided cases `ui.pointer.add-button`, `ui.pointer.opportunity-row`, `ui.pointer.row-picture`).

**Client UI API probes (milestone 6).** Two opt-in groups that measure how a few UI calls and input routes behave in the client, on frames the Lab makes itself: **Client UI API (own frames)** (`api`, four automatic `owned` cases) and **Client UI API (guided)** (`apiguided`, four guided cases). Neither is ticked for you and neither runs in an unqualified run. The section "Client UI API probes (milestone 6)" below has the cases, the steps, the safety guarantees and the findings table (to be filled in from real runs). `numeric.guards.held-counts` (core) and `client.lua.nan-guards` (client) are the read-only numeric audit cases of the same milestone (roadmap section H, M6).

Evidence labels in the report: **client** = observed in this game client; **synthetic** = production code in the client's Lua on made-up data; **guided** = observed with the player's help (the pointer probe); **not run** = never started.

The core cases' expected values were worked out by hand and are written beside each case in `cases/Core.lua`. If one fails, decide first whether the hand arithmetic or the code is wrong.

### Deferred, on purpose

Calls that read the saved markets (`Market.Source`, `Market.Info`, `Market.Markets`, `Prices.Market`, `Prices.Keys`) are not in M1: the only way to test them is against `TwichUIWorkshopDB`, which the Lab never replaces, swaps or writes. `Market.Price`, `Stats`, `Trend`, `Compare` and the rest are tested through their `opt.market` table argument, the existing pure-data boundary, with an explicit `opt.now`. A saved-data integrity check that *reads* the real roots belongs to the persistence milestone (M9). Market-side selection and the quantity-aware pricing algorithm are not touched (owner decisions: those are future Market-service changes).

## Safety

Every case declares a class, and the registry refuses a case without one.

| Class | May do |
|---|---|
| `pure` | Call production functions with explicit inputs only, on made-up data. |
| `readonly` | Read live game state or real saved data. |
| `guided` | Asks the player to put the pointer somewhere, then **reads** what the client reports (`GetMouseFoci`, rectangles, flags). Never clicks, writes or sends. Its input is the one temporary key binding described below, or (milestone 6) a **click the player makes on a Lab-made test frame**, which the frame only counts. Its category is never ticked for the player, and an unqualified `TL.Select()` leaves it out. |

**Opt-in groups.** `TL.Category{ optin = true }` (a guided group is always opt-in) means the group is unticked in the window and left out of `TL.Select()` with no argument; it runs only when chosen by name. The sidebar says "Builds its own test frames, so it is never ticked for you".
| `owned` | Creates and changes **Lab-made probe frames only** (`Probe.lua`, named `TwichUITestLabProbe...`), out of combat, and reads what they report. Never a control of the Workshop or of any other addon, never a click on one. Its group is **opt-in** (below), and the Runner releases every probe frame when a case or the run ends. |

Enforced:

- **Never reassigned:** `TwichUIDB`, `TwichUIWorkshopDB`, `TwichUIDiagnosticsDB`. No fixture is ever swapped in for them (a disconnect during a swap would make the game save the fixture over the player's data).
- **Fingerprint:** every case is bracketed by a cheap fingerprint of the three roots (key counts, `v` fields, each market's `at`/`n`). A difference fails the case. It cannot tell the game's own change in that instant from the case's; run it again.
- **Static scan:** `tests/test_testlab.lua` scans every `TwichUI_TestLab/**/*.lua` (comments removed) for the forbidden names below, for any use of the three roots other than reading them by name, for assignment through `_G`, and checks the scanned files equal the `.toc`'s.
- Forbidden names: `Commit`, `BeginCommit`, `Apply`, `Queue.`, `Known.Store`, `Vendor.`, `Storage.`, `Session.`, `Scan.Start`, `Observe.OpenRecipe`, `ReplicateItems`; every bid, post, purchase, cancel, mail, trade, destroy, disenchant, craft, merchant and item-use call; `SendAddonMessage` / `SendChatMessage` / `SendCommMessage`, `SetCVar`; `hooksecurefunc`, `securecall`, `setfenv`/`getfenv`, `loadstring`/`load`, `dofile`, `require`, `rawset`, `RegisterGameMenuEscHandler`; and for input: `SaveBindings`, `SetBinding*` (a saved binding), `LoadBindings`, `EnableKeyboard`, `SetPropagateKeyboardInput`, `OnKeyDown`/`OnKeyUp`/`OnChar` (no keyboard capture). **`SetOverrideBindingClick` / `ClearOverrideBindings` appear in `Guided.lua` and nowhere else** (a test checks that, that the binding is made for the Lab's own button with one key, and that it is never cleared for `UIParent`); other files may only name them inside a quoted string (the API presence report).
- No Blizzard function is wrapped or hooked; nothing is sent; Esc uses `UISpecialFrames`.
- **One side effect to know:** a case that `needs` the Workshop loads it through the core's `WorkshopLauncher.Load()` (refused in combat; the case is then skipped with the launcher's reason). Loading the Workshop is the normal load: the game loads its saved variables and the Workshop initialises as it always does. The Lab does that *before* a case's fingerprint, and does nothing more.
- A run is refused in combat; `PLAYER_REGEN_DISABLED` (registered only during a run) and a check each frame stop one.

## The window

Redesigned (2026-11-12) after the approved mockup, `docs/test-lab/lab-mockup.png`: a larger landscape window in the Workshop's materials (espresso and chestnut leather, aged bronze, ivory text; the core's shared `Look`, `FrameLook` and `CraftLook`). The mockup is a **visual target only**: its numbers, market name, seed and "suggested next step" are illustrative, and nothing in the window is made up to match them. It is a presentation layer; the runner, the registry, the safety classes and the report are unchanged (the runner now also keeps each case's failure lines, `fails` and `failed`, so the details panel can list them; the report does not use them).

**Layout, four zones.**

- **What to run** (left): one check per registered group, with its name, its case count and what it is for, read from the registry (`View.Categories`), so a new group appears by registering it. The whole entry is the click target. A guided group is never ticked for you. Checks are off while a run is going. The list scrolls.
- **Summary cards and the toolbar** (top): Total cases, Passed, Failed, Skipped, Errors, Timeouts, Duration, each with a painted icon and a word (never colour alone; the icons are `TwichUI_TestLab/media/summary/*.tga`, 64 x 64 with real transparency, drawn at 32 units, cut from the sources in `docs/test-lab/` by `tools/make_testlab_art.py`; a card with nothing to show dims its icon to 60% and a narrow card drops it), from the runner's own records. Before a run every card shows a dash (not run is not zero failures). While running they count only the cases that have **finished**; an unfinished case is never counted as passed. After a stopped run the Total card says how many did not run. Then **Run**, **Stop**, **Copy report**, **Copy failures** and the run state (Not run yet, Running, Waiting for you, Finished: all passed, Finished with problems, Stopped, with why). **Run** is off while a run is going or when nothing is chosen; **Stop** only while a run is going; **Copy report** after a run; **Copy failures** only when the last run had a failure, an error or a timeout. The bar shows cases finished out of the cases chosen, not time spent waiting for you at a guided step.
- **Filters, search, the table and the details** (middle): chips for All, Failed, Passed, Guided, Synthetic and Client, with real counts; **Skipped, Errors, Timeouts and Stopped** chips appear when the run has some, so none is hidden. A filter only chooses which records the table shows: it never changes which groups run, the report or your selection. The search field matches every word you type (any order, any case, plain text, never a pattern) against the case id, its kind, its status word and the start of its message, and combines with the chosen filter. The table has Status (a mark and a word), Case, Type (Synthetic, Client or Guided), Duration and Message, with alternating rows and a painted hover and selection; a guided case reads Your turn, Measured, Skipped, Cancelled or Not run, never "running". Click a row to choose it.
- **Details** (right): for the chosen result its full id, evidence type, outcome, the headline (the first failed check, "N checks passed", the skip reason, the error text, the timeout note, ...), every failed check, what the evidence type means, the duration, the checks made, any seed the case's own text names (quoted, not guessed), the case's evidence lines and the facts it recorded. A case that recorded only a message shows that message and nothing else; no root cause, market, recommendation, seed or expected value is ever added.
- **Report** (bottom): the full report, written once when the run ends, selectable and scrollable. **Copy report** puts the whole schema 1 report there. **Copy failures** puts only the cases that did not pass, with all their evidence, under a header that says it is an excerpt (`TWICHUI-TESTLAB FAILURES ...`, not a schema 1 report). Typing in the box puts the text back.

**Choosing a result.** When a run ends with a failure, the first failed case (else the first error, else the first timeout) is chosen for you. A result you chose yourself, by clicking its row, is kept. A new run clears the choice.

**Empty states** each have a sentence: nothing chosen, nothing run yet, a filter or search that matches nothing (it names the search and the filter), no failures, no passes yet, a stopped run, every case skipped.

**Guided runs.** The window is big, so it **steps aside** while a run that includes a guided group (a pointer probe or a click probe) is going: its content is hidden and it takes no pointer, so the Workshop and the prompt at the top of the screen are not covered and the pointer cannot land on the Lab. It is still open (the run goes on), and it comes back when the run ends or is stopped, or by closing it, which ends the run as before. The prompt's title now says where the step stands (case *n* of *m*). Cancel on the prompt or **Stop** ends the run and removes the key as before.

**A small screen.** The window is sized from the screen (at most 1280 by 780, at least 940 by 600) and scaled to fit by the core's `FitToScreen`. Below 1100 wide it narrows: a narrower sidebar without descriptions (they are tooltips), smaller buttons, and a table that drops the Message and then the Type column (the details panel has them). Cards use short labels and no mark when they are narrow. A window shorter than 680 gets a shorter report box.

**Cost.** Frames are built once, when the window first opens. The table is a pooled list: only the rows that can show exist (a 300-case run uses about nine), scrolling and filtering reuse them, and nothing allocates once the window has settled (a test counts every frame, texture and text made). The runner calls the window at most once per frame while running; the window redraws only what changed (a card, the run state, the chips and the table when a status changed). The report is built once, at the end. Nothing animates except the row hover and the existing bounded fades, which honour the reduced-motion choice. The window has no `OnUpdate` and no timer, and is idle when closed.

Offline, `tests/test_testlab_window.lua` tests `View.lua`, the failures excerpt and the window under the mock; `tools/simlab/testlab.sh` draws every state in the simulator (below).

### Simulator scenario (`tools/simlab/testlab.sh`)

Loads `TwichUI_TestLab` with `LoadAddOn` and hands the window **synthetic recorded results** (`Window.OnProgress` / `OnDone`) in nine launches, each ending in a screenshot: `idle`, `running` (the scenario makes the runner read as active; no case runs), `allpass`, `mixed` (one failure chosen, its details shown), `failfilter`, `problems` (a failure, a skip, an error and a timeout), `long` (300 cases, scrolled), `guided` (the window stepped aside, only the prompt shows) and `small` (1000 by 700). It checks the displayed text and state, that the cards, chips, run state, bar, table and details agree with the records, the emulated hit test (`Reach.lua`, M5) for Run, Copy, Stop (not eligible when idle), the chips, a group's check and entry, the Close button, the search field and the rows in view, and that no card label, value, chip or button text is wider than its box. `testlab_verdict.py` fails the run on any check, any unclassified Lua error, a missing step, a wrong-size or blank screenshot, or opening checks that differ between launches. **Limits:** nothing here is real input, the clipboard, or how it looks in the game: addon fonts are drawn in Friz Quadrata (wider than the game's), the simulator's multi-line edit box draws the report's lines on top of each other (the text is read back with `GetText`), and a stand-in "Issue report" widget the simulator places mid-screen appears in every capture. The first captures led to these changes: the Passed and Failed cards drew the wrong mark, group names were cut, the details headline did not wrap, the filter chips ran into the search field when a run had every kind of outcome, and the narrow window cut its run-state text.

**Visual differences from the mockup that remain:** fonts (see above); the selected row uses the shared gold-leather selection rather than the mockup's red wash; the status column carries a word beside each mark (an accessibility choice); the Passed and Failed cards use the shared status art while the other five marks are drawn shapes (stack, skip, shield, warning, hourglass), not painted icons; column headings have no sort arrows (not requested); the mockup's Market and Crafting groups are not shown because the registry has no such groups (the sidebar lists the real ones); and the mockup's "Suggested next step" and Market/Query evidence lines are not reproduced because no case records them. **Nothing of the redesign has been seen in the game yet.**

## Cooperative cancellation: what Stop does and does not do

Lua coroutines are cooperative. **Nothing here can interrupt code that is running**, and the Lab never claims otherwise.

- Each frame the runner resumes cases until about **5 ms** have passed (`GetTimePreciseSec`, else `debugprofilestop`, else `GetTime`; `debugprofilestart` is never called), then waits for the next frame.
- A case shares frames by calling `t:Yield()` at a safe point, or pauses with `t:Wait(seconds)` (nothing is scheduled for it meanwhile). A case that never yields runs to its end in one step; such cases are kept small.
- Every step is timed. A step longer than a slice is an **overrun**: it is counted, named in the report with its measured length, and was never cut short.
- **Stop**, combat, the 5-minute run cap and closing the window all do the same thing: *no further step is scheduled*. The case that was waiting at a yield point is marked `stopped` ("not resumed"); cases that had not started are `stopped` ("before it started"). A step that was already running had finished before any of this could act; the window says so.
- A case that has used its **budget** (default 10 s, at most 60 s, `budget =` in the registration) and has yielded is **abandoned** at that yield point: status `timeout`, never resumed. A step that overran its budget and then finished keeps its result and is reported `late`.
- Cases must not call `t:Yield()` or `t:Wait()` inside a `pcall` (Lua 5.1 cannot yield across one; the client fact `client.lua.yield_across_pcall` reports what this client does).
- One frame with an `OnUpdate` exists only while a run is active, and `PLAYER_REGEN_DISABLED` is registered only then. The window has no `OnUpdate` of its own. No timers are created.

## Statuses

`pass`, `fail` (an assertion), `error` (the case raised), `skipped` (`t:Skip`, or the Workshop could not be loaded), `timeout`, `stopped`.

## The report

Plain text, a few KB for M1 (cut at 30,000 bytes):

```
TWICHUI-TESTLAB REPORT schema 1
client <version> build <n> interface <toc> | TwichUI <ver> | Workshop <ver or "not loaded"> | TestLab 0.1.0-dev
run: core,client | N cases: a pass, b fail, c skipped, d error, e timeout, f stopped | 0.41 s | slices 31, worst 6.1 ms, worst frame 38 ms, overruns 0 | ended: complete
clock: GetTimePreciseSec | slice 5 ms | cooperative: a step that never yields cannot be interrupted, only measured
labels: client = ... | synthetic = ... | guided = ... | not run = never started
PASS    price.unit.round-up  synthetic 0.2 ms
FAIL    market.trend.percent  synthetic 0.3 ms  negative percent: expected -33.4, got -33.3
...
setup (one-time, before the case named; not part of that case's time, but part of the run's):
  Workshop load  23.6 ms, before price.unit.round-up
overruns (a step ran longer than the slice; it could not be interrupted):
  <case id>  <ms> ms in one step
  <case id>  <ms> ms in one step (setup: Workshop load, not the case's own work)
facts: client.api.GetTimePreciseSec=function client.lua.div_zero_value=inf ...
```

**Setup is reported apart (milestone 6).** The one-time load of the Workshop for the first case that needs it is timed on its own and listed under `setup`; a case's own duration starts after it, so `price.unit.round-up` (or whichever case comes first) is no longer charged for the load. The load still counts in the run's total, in `worstSlice`, and as an overrun when it exceeds a slice (marked `(setup: ...)`): nothing is hidden, only labelled. The 23.6 ms step in the real-client report that prompted this is *probably* that load; the next report's `setup` line will say.

`ended` is `complete`, `user`, `combat`, `cap` or `closed`. The report holds counts, case ids, the Lab's own messages and facts. Text that came from a case has control characters, item links and colour codes removed and is cut at 240 characters. It contains no character, realm, guild or account name, no chat, no item link and no saved value (the offline test uses a mock character and realm and checks they never appear).

## Not in releases

- `.pkgmeta` lists `TwichUI_TestLab` under `ignore`, and it is not one of the `move-folders`.
- `tools/release.py`'s package check refuses a zip whose top-level folders are not exactly the seven addons, and now also refuses any path containing `TwichUI_TestLab` anywhere (its `FORBIDDEN` set).
- `tests/test_release_tools.py` covers both: a Lab folder beside the addons, a Lab folder inside the core, and the `.pkgmeta` entries.

## Known limits

- Everything above about timing is **unit-tested with a virtual clock**; how long a real step takes, and the real frame time, are only known from a real run.
- The offline run proves the cases and the runner's logic in plain Lua 5.1. It cannot prove WoW's interpreter agrees (that is what running the Lab in the client is for), or how the window looks.
- The fingerprint cannot tell a case's change from the game's own in the same moment.
- Facts are observations of one client at one moment.
- **Numbers that are not numbers.** The client's Lua does not reject a NaN everywhere desktop Lua 5.1 does (the reference model accepted a NaN count by comparison, 2026-11-12). Pure code that must refuse a NaN should not rely on `v == v`; the model decides finiteness without a comparison (`REF.Finite`), and `client.lua.nan-comparisons` reports what this client does.
- Milestone 6's probes (below) have run **offline against stand-in frames only**; nothing about the Forever client is claimed until you run them in the game and the findings table is filled in.
- The Lab is not a benchmark tool and has no `/tui lab` command (an owner decision). The reachability cases (milestone 5) ran **offline, in the simulator and, once (2026-11-12), in the game**: the three guided cases passed (`GetMouseFoci` named the intended Workshop frame topmost in each); how the hover *looks* is still not tested.

## Real-client checks for initial acceptance

Four, by hand, in the development client:

1. **Load:** the data bar menu's **Test Lab (development)...** row appears (and does not appear with the folder removed), and clicking it opens the window with no Lua error; the row and `/tuilab` close and reopen it.
2. **Run both categories:** every core case passes; the client category passes; the report's `facts:` line shows what this client has (note especially `client.lua.div_zero_*`, `client.lua.yield_across_pcall` and the API presence values).
3. **Stop mid-run:** run both, then press Stop while the progress line reads `client.runner.pause-probe` (it waits about 2 s, a cooperative wait: nothing runs meanwhile). The remaining rows must read `stopped`, the pause-probe row `stopped ... not resumed`, and Run must be enabled again.
4. **Copy the report:** after a run, Copy report selects the text; Ctrl+C and paste it elsewhere; it should start `TWICHUI-TESTLAB REPORT schema 1` and contain no names.

Also worth one look: that `/reload` afterwards shows no change in the Workshop's data (the Lab changed none by design; the offline test checks the roots are deep-equal).

### Real-client checks for the redesigned window (not done yet)

1. Open it: the layout matches `docs/test-lab/lab-mockup.png` in composition (header, four zones, seven cards, toolbar, bar, chips and search, table and details, report), nothing is cut off, and the sidebar lists every group with its true count. The fonts are the game's (Spectral and Alegreya Sans), not the simulator's.
2. Run **Core**, **Client facts** and **Interface reachability**: the cards fill as cases finish; Total, Passed and so on agree with the report's `run:` line; the table scrolls smoothly; the first failure (if any) is chosen with its details; **Copy failures** is only available when something failed.
3. Try each filter chip and the search (`batch`, `guided`, two words, nothing); a filter keeps your row selected and the report unchanged.
4. **Copy report** and **Copy failures**: the box fills and selects; **Ctrl+C** and paste; the text starts `TWICHUI-TESTLAB REPORT schema 1` or `TWICHUI-TESTLAB FAILURES`.
5. Tick the guided group and Run: the window steps aside, the prompt shows "case *n* of *m*", F9 samples, and the window returns with the results (and also returns on Stop, Cancel and closing).
6. Resize your screen or UI scale (or run on a small one): the window fits, and below about 1100 wide the table drops its Message column and the sidebar drops its descriptions.
7. Watch the frame time while the table scrolls and a run is in progress: it should not rise (the redesign makes no per-frame work).

## Reachability and the pointer probe (milestone 5)

**Why it exists.** The Workshop's tests call a control's handler (`btn:GetScript("OnClick")(btn)`), which skips everything between the player and the handler: the control must be shown, enabled and take the mouse, and nothing may sit on top of it. In the third pass the player found a nonworking Add button and missing row hover; the tests and the simulator had passed. These are four different levels of evidence, and the report and the docs never merge them:

| Level | What it shows | Where | Label |
|---|---|---|---|
| Handler invoked | the registered script runs and does the right thing | `btn:GetScript("OnClick")(btn)`, `Button:Click()` | unit-tested / simulator-tested (handler level) |
| Eligible | the control *may* take input: shown, ancestors shown, enabled, mouse and clicks on, a script set | `Press(btn)` (offline), `Reach.Eligibility` | unit-tested (a stand-in's recorded state) |
| Geometrically reachable | nothing else is drawn over the control's hit point, by an **emulation** of rectangle, hit-rect insets, strata, level, visibility, clipping | `Reach.Analyze` in the simulator and in the client (`ui.workshop.reach-scan`) | simulator-tested / client geometry (a model) |
| Under the pointer | the **client's own** `GetMouseFoci` names this frame at this position | the guided cases | real-client (when run), label `guided` |

### `Reach.lua` (the analysis)

One module, used by the offline tests (a fake world, `tests/reach_world.lua`), the simulator scenario (it is concatenated into the fixture by `tools/simlab/workshop.sh`; the Lab addon itself is never loaded there) and the Lab. It asks frames only through documented widget methods, asks each one safely (a missing method, an error or a secret value is *unknown*, never success) and never reads frame text.

- `Eligibility(frame, kind)`: reasons `hidden`, `ancestor-hidden` (naming the ancestor), `not-visible`, `disabled`, `mouse-disabled`, `click-disabled` (clicks) or `motion-disabled` (hover), `no-click-handler` / `no-enter-handler`. Anything the frame cannot answer is listed as *unknown* and makes it not eligible. A method the client may lack (`IsMouseClickEnabled`, `IsEnabled` on a plain frame) is "not applicable".
- `HitRect(frame)`: the rectangle times the effective scale (comparable with `GetCursorPosition`), less `SetHitRectInsets` (a negative inset extends it, as `UI.Switch` does over its label).
- `Collect()`: the frames that could take the pointer (mouse enabled, visible), by `EnumerateFrames`, **bounded** (30,000 frames; it says so when it stops).
- `Analyze(control, { kind = "click" | "hover", point })`: `reachable`, `blocked` (by a frame above it, by a parent above it, or by a child that takes the pointer from it), `ambiguous` (an unrelated frame with the **same strata and level**: the client's order for that is not known, so it is reported, not decided), `clipped` (a scroll frame or clipping ancestor hides that part), `outside`, `ineligible`, or `unhittable` (no rectangle, or insets that leave nothing). The result names the intended control, its hierarchy, the expected hit point, the **blocking frame** (type, strata, level, mouse flags, hit rectangle, insets), the control's own state and the evidence class. A disabled control still takes the pointer (it blocks what is under it and is itself ineligible). A frame whose click is off, or that propagates clicks, does not block a click; one with motion off does not block hover.
- `Sample()`: the real client's own answer, `GetMouseFoci`, at one moment, with `GetCursorPosition`, at most five frames described.
- **Names are redacted:** global frame names only (cut at 60 characters, links and colour codes removed, the player's name, realm and guild name replaced by `[private]`). Frame text is never read.

**What the geometry assumes (a model, not a fact about the client):** a frame takes the pointer when it is visible, mouse enabled and the point is inside its hit rectangle; the topmost has the highest strata, then level; a child is above its parent on a tie; `ScrollFrame`s and frames that clip children hide what is outside them from the pointer. **Not modelled:** the client's order for equal strata and level, `SetToplevel` raising, regions, secure frames, mouse capture, the cursor's own scale rounding. The real-client cases (below) are what tests the model.

### `Press(button)` (the offline helper, `tests/press.lua`)

Opt-in. `Press.Instrument(frame, name)` (called from a test's `CreateFrame`) gives a stand-in the state a real frame keeps (type, name, parent, mouse click and motion, hit-rect insets, `Enable`/`Disable`; a Button takes the mouse by default and a plain Frame does not, as in the game). `Press(btn)` then:

- **refuses**, without running any script, a control that is hidden, under a hidden ancestor, disabled, mouse-off, click-off (where the stand-in models it) or without a handler, and returns an outcome table (`invoked`, `outcome`, `reasons`, `text`, `evidence`); `Press.Must(btn)` raises with that text instead;
- treats a question the stand-in does not model (an un-instrumented `MIFake` answers every capitalised method with nothing) as **unknown and refuses**, never as success;
- otherwise runs the **real** scripts in the game's order, `PreClick`, `OnClick` (and its hooks), `PostClick`, with the control first and `(button, down)` after it (`button` and `down` can be given); a non-Button is pressed through `OnMouseUp` (or `opts.script`); `Press.Hover(frame)` does the same for `OnEnter`.

What it does **not** tell you is stated in the outcome's `evidence`: `handler invoked (offline); eligible according to the stand-in's recorded state; geometry not checked; not confirmed under a real pointer`. It does not look at other frames, rectangles or strata, and says nothing about what the real client does with a disabled or hidden control (that is a client probe, milestone 6). `tests/test_workshop_window.lua` opts in and presses the Opportunities Add button and the recipe rows' Add buttons; after queueing it asserts the real buttons are **refused** (hidden / disabled). Nothing else in the suite changed.

### The read-only cases (category "Interface reachability")

- `ui.pointer.api` (`readonly`): which pointer APIs this client has (`GetMouseFoci`, `GetCursorPosition`, `EnumerateFrames`, `SetOverrideBindingClick`, `ClearOverrideBindings`) and which frame methods answer on `UIParent` (`IsMouseClickEnabled`, `GetHitRectInsets`, ...), as facts. It asserts only that `GetMouseFoci` exists.
- `ui.workshop.reach-scan` (`readonly`): needs the Workshop window **open** (it never loads or opens it; skipped with a sentence otherwise). Every visible, enabled button with a click script is analysed at its hit point; `reachable` and `clipped` (scrolled out of its list) pass; `blocked`, `ambiguous` or anything else fails with the explanation in an evidence line under the case. Evidence class: **client geometry (an emulation run in the client)**, not the client's own answer.

### The guided pointer probe (category "Pointer probe (guided)")

Opt-in: its box starts **unticked**, and `TL.Select()` without a category leaves guided cases out. It never clicks the target, never writes, never touches the auction house or the Workshop's settings, and keeps nothing between runs.

**How the sample is taken without moving the pointer.** A click on a "Sample" button would move the pointer off the target, so the sample is taken **on a key**: while a request is open, one key (`F9`, `Guided.KEY`) is bound with `SetOverrideBindingClick` to a Lab-owned button that is 1 x 1, **mouse off**, and shown only during the request. An override binding belongs to its owner frame, is never saved and is removed by `ClearOverrideBindings(owner)`; nothing else is rebound and `SaveBindings` is never called. `SetOverrideBindingClick` is used by Blizzard's own insecure code in the Forever UI source (`Blizzard_GamepadSharedUtility/InputBindingStack`), but **whether this client lets an addon call it is reported by the first real run, not assumed** (`ui.pointer.api` reports the function's presence). It is refused in combat, and if the function is missing the prompt says so and offers the fallback: **"Sample in 5 s"**, which takes the sample 5 seconds after you click, wherever the pointer is by then (no binding at all; the limitation is that you must park the pointer within the 5 seconds, and the prompt's own buttons are what you clicked).

**What is released, and when.** The key, the prompt and a pending countdown are released when the case ends, on Skip, on Cancel (the prompt) or Stop (the Lab window), on combat (`PLAYER_REGEN_DISABLED`, which the runner already listens to during a run), when the Lab window is closed, on a timeout (150 s at most for a guided case), on an error and at the end of the run. `Guided.Snapshot()` says what is still live (nothing, afterwards); a test checks it after each of those routes and after a case that crashes mid-request.

### What to do in the game (steps)

1. Copy `TwichUI_TestLab/` into the development client's `Interface/AddOns/`, as always; `/reload`.
2. Open the Workshop (`/tui workshop`), go to **Opportunities**, wait for the list, **choose a recipe** (click a row; the details panel shows "Add to crafting plan").
3. Open the Test Lab (data bar menu, **Test Lab (development)...**, or `/tuilab`). You no longer need to drag it aside: while a run that includes the guided group is going the window steps aside by itself (see "The window"), so the Workshop is uncovered and the Lab cannot be under the pointer. (If the Lab's prompt is under the pointer anyway, the sample is *not counted* and says so.)
4. Tick **Pointer probe (guided)** (and **Interface reachability** if you want the scan too) and press **Run**. The read-only cases finish at once. The Lab window disappears and a small **prompt** appears at the top of the screen with the first step and "case *n* of *m*".
5. **Step 1, the Add button.** Put the pointer over **Add to crafting plan** (do not click) and press **F9**. If the pointer was not over it, the sample is not counted and the prompt tells you how far off it was; try again. Then the next prompt appears.
6. **Step 2, a row.** Move the pointer onto a recipe row's **name**, hold it still for a second, press **F9**. (A selected row is fine; try both.)
7. **Step 3, a row's picture.** Move onto the little recipe picture at a row's left, hold still, press **F9**. The row must stay lit (it follows the picture).
8. When the run ends the window comes back with the report in its box and the first failure, if any, chosen. Press **Copy report**, then **Ctrl+C**, and paste it where it is needed. Skip a step with the prompt's **Skip this step**; **Cancel** (prompt) ends it all.
9. Afterwards check that F9 does whatever it did before (nothing is left bound), and that `/reload` is not needed for anything.

Look at the row yourself in step 2 as well: the probe reads the highlight's alpha, it cannot tell you whether the animation *looks* right.

### How the window and the report tell the outcomes apart

| Row word | Report word | Meaning |
|---|---|---|
| `your turn` | (while running) | **pending guided action**: the prompt is waiting for you |
| `measured` | `PASS` | a **completed measurement**: the client's answer matched the expectation |
| `FAIL` | `FAIL` | a **failed assertion**: the answer did not match; the evidence lines say what was under the pointer instead |
| `skipped` | `SKIP` | a **skipped action**: you skipped it, or the probe could not work here (the sentence says which) |
| `cancelled` | `CANCEL` | a **cancelled observation**: Stop, Cancel, combat or a closed window ended it before a sample counted |
| `ERROR` | `ERROR` | the case raised |

A failing guided case prints evidence lines under it (up to 16, each cut at 400 characters):

```
FAIL    ui.pointer.add-button  guided 4021.7 ms  the topmost frame under the pointer is another frame, not the Add button (...)
        pointer x 1090 y 258 (screen units) | target hit rect x 920..1260 y 240..276 | frame x ... | insets L0 R0 T0 B0 | evidence: client-foci (GetMouseFoci at the key)
        focus 1 (other, other): SomeFrameName [Frame, DIALOG level 1, mouse on click on motion on, hit rect x ...]
        focus 2 (self, workshop): ...
```

`focus n (relation, owner)`: *relation* to the target is `self`, `inside` (a child of it), `contains` (a parent) or `other`; *owner* is `workshop`, `testlab` or `other`. Only the first five frames of the stack are described, by type, strata, level, mouse flags, rectangle and global name; frame text, links, the character, realm and guild names are never in the report.

**Hover facts** (`ui.row.*`, `ui.picture.*`): `hovered` (the row's own flag), `selected`, `hot_alpha` and `rim_alpha` (the painted highlight's alpha, read through the row's own fields; no handler is patched), `hot_visible`, `selection_shown`, whether `OnEnter` is installed, and whether a child (the picture) holds the pointer. A hovered row whose highlight is still fading in is asked again (up to twice) before it fails. A selected row is dimmer by design (its highlight is capped at 0.4 / 0.6) and still counts as lit. **An alpha is not an animation**: what it looks like still needs a person.

### Known limits of the reachability work

- Everything above is **unit-tested offline against a fake frame world and simulator-tested; the guided cases and the scan have run once in the game** (2026-11-12, see `docs/workshop/testing-roadmap.md` M5.1). The guided cases are the only thing that says what the client puts under the pointer.
- **The scan is cooperative, not preemptive.** `Collect` yields after about 1.5 ms of scanning (a clock read every 32 frames) so no step is long; a Lua step that does not yield cannot be cut short by anything, and the runner can only measure it. It walks every frame of the UI once, not only the Workshop's, so a blocker from elsewhere is found. The case reports `ui.scan.yields`, `work_ms`, `longest_slice_ms` and `elapsed_ms`.
- The simulator's `GetMouseFoci` returns only a frame a scenario forced with `A_Admin.SetMouseOverFrame`; it never works out a frame from a position. The simulator also stores a scroll frame's offset without moving its rows' rectangles. Both are recorded as checks in the scenario.
- The geometry cannot say how the client orders frames of equal strata and level (it reports them ambiguous), and it does not model secure frames or mouse capture.
- A hit-test miss in a scan is a pointer-level finding, not a diagnosis: the frame named as blocker is where to look.

## Client UI API probes (milestone 6)

**Why they exist.** The simulator and the offline tests assume how some UI calls behave (what `EnableMouse(false)` does to the click and motion flags, whether `Click()` runs a disabled button's script, which of two overlapping frames takes a real click, whether `SetHitRectInsets` changes the pointer's region). Those are guesses until the game answers. The probes ask it, on frames the Lab makes, and **record what it says**: a result is a fact about one client at one moment, a refused call is a recorded restriction (never retried another way), and no expected answer is built into the report.

**What they are not.** Not a UI redesign, not an auction house tool, not a way to click anything of the Workshop or any other addon. Both groups are opt-in; nothing runs by itself.

### The cases

| Case | Group, class | Needs you | What it records |
|---|---|---|---|
| `api.binding.override` | own frames, `owned` | no | An override binding made for the Lab's own hidden button, cleared, made again and cleared, **out of combat, in one step with no yield** (so no key press can be routed meanwhile). `GetBindingAction(F9, true)` before, while bound, after clearing, bound again and after the final clear; whether each call was accepted; `C_RestrictedActions.CheckAllowProtectedFunctions` on the button. The combat answer is *read* (`protected_allowed`), never tried: the Lab does not start or continue in combat. |
| `api.mouse.states` | own frames, `owned` | no | For a plain Frame and a Button: `IsMouseEnabled / IsMouseClickEnabled / IsMouseMotionEnabled` (+ shown, visible, enabled) after each way of switching input: a fresh frame (as it was when first made this session), `EnableMouse(true/false)`, motion only (by `EnableMouseMotion`, by `SetMouseMotionEnabled`, by turning clicks off), clicks only, both flags off, a `SetScript("OnEnter")` alone, hidden, and (Button) disabled and enabled again. Which of the method names exist (`EnableMouseClicks`, absent from the Forever API documentation, is *reported*, never assumed). Whether `IsMouseEnabled` agrees with "click or motion" in each step, which is what the reachability model relies on. |
| `api.click.programmatic` | own frames, `owned` | no | What `Button:Click()` does to counters on `OnClick`, `PreClick` and `PostClick` for a visible and enabled button (the **control**: if it does not run, the other rows mean nothing and the case fails), disabled, hidden, mouse-disabled, click-disabled and shown-under-a-hidden-parent; the state at the moment of the call; whether `Click()` raised. **A programmatic Click is not a physical click** (the guided cases measure those). |
| `api.hitrect.insets` | own frames, `owned` | no | `SetHitRectInsets` callable out of combat; `(0,0,0,0)`, asymmetric positive `(10,20,30,40)`, negative, mixed and degenerate values; what `GetHitRectInsets` reports back (asymmetric values show the order); the Lab's own hit-rectangle arithmetic against what the client reported. A refused or missing call is recorded as a restriction. The pointer's region is the guided case below. |
| `api.binding.keypress` | guided, `guided` | **press F9 twice** | A real key press reaches a Lab-owned button while the binding is registered; the binding is cleared (`GetBindingAction`) and **registered again**, and a second press reaches it again. A press of the prompt's own buttons is not a key press and is asked again. |
| `api.click.overlap` | guided, `guided` | **click 4 times, answer once** | A lower blue Button and an upper orange frame overlap; you click the white square where they meet. Four configurations of the upper frame: mouse off, mouse on, clicks off (motion on), `SetPropagateMouseClicks(true)` (skipped, with the reason, if the method is missing or refused). |
| `api.order.equal-level` | guided, `guided` | **click 4 times, answer 4 times** | Two Buttons with the **same** strata and frame level overlap. You click where they meet in four arrangements: A created first and shown first; the same shown in the other order; B created first (the second pair of frames); each inside its own container. |
| `api.hitrect.pointer` | guided, `guided` | **click 3 times** | A teal Button with insets `L70 R-50`: you click inside its paint but inside the removed strip, in the middle, and outside the paint inside the added strip. |

### Three kinds of evidence for a click, never merged

Each click scenario reports, separately and in the facts line: **`foci`** (the client's own `GetMouseFoci` stack at the first press, by piece name, top first, e.g. `U>L>back`), **`onclick`** and **`mouseup`** (the pieces whose `OnClick` / `OnMouseUp` actually ran; a plain Frame cannot have an `OnClick`), and **`visual`** (what **you** saw on top, answered with the buttons on the prompt, because code cannot read what is drawn). It also records whether the topmost focus is a frame that ran `OnClick` or `OnMouseUp` (`foci_top_ran_onclick_or_up`) and what the Lab's geometry model (`Reach.Analyze`, over just the arrangement's frames) predicted (`model`, `model_agrees_with_onclick`). **They are not assumed to be equal**; a difference is the finding.

### How to run them in the game (steps)

1. Copy `TwichUI_TestLab/` into the development client's `Interface/AddOns/` (as always) and `/reload`. Open the Lab (data bar menu, **Test Lab (development)...**, or `/tuilab`).
2. **Automatic group.** Tick **Client UI API (own frames)** only and press **Run**. It finishes in a moment; nothing is asked of you. Copy the report (**Copy report**, Ctrl+C).
3. **Guided group.** Tick **Client UI API (guided)** only and press **Run**. The Lab window steps aside; a prompt appears at the top of the screen and a dark **Test Lab probe area** in the middle of it. Do what the prompt says, one case at a time:
   - **Key press (`api.binding.keypress`):** press **F9** when asked (do not click the prompt's buttons), then **F9** again for step 2.
   - **Clicks:** click **once**, inside the white square, with the **left** button. A click outside the square is not counted and the prompt says how far off it was. When the prompt shows answer buttons, say which colour you see drawn on top inside the square (or "I can't tell").
   - **Skip this step** skips one scenario and moves on; **Cancel** (or **Stop**, or closing the Lab) ends the run and removes everything.
4. When the run ends the Lab window returns with the report. **Copy report**, paste it into the findings table below (or hand it over).
5. Afterwards: F9 does whatever it did before (nothing is left bound), and no Lab frame is on screen.

### Safety and cleanup guarantees

- **Explicit action.** The groups are opt-in and run only when ticked by name. A guided case does nothing until you act; nothing runs at load, at login or on a timer.
- **Ownership.** Every frame is made by `Probe.lua` and named `TwichUITestLabProbe<role>` (one per role for the whole session: the game cannot delete a frame, so a rerun reuses them, reset to a clean state). No frame of the Workshop, the auction house or any other addon is read for its state, changed, hooked or clicked by these cases.
- **What a probe frame does.** Its handlers append a short record to a bounded list (at most 24 records per click) and nothing else: no send, save, hook, move, or protected action. The backdrop takes a click that no probe frame takes, so a probe click never reaches the 3D world. `Click()` only increments a counter.
- **Key binding.** The only one is the existing temporary override binding in `Guided.lua` (one key, `F9`, for the Lab's own hidden 1 x 1 button, never `UIParent`, never saved: `SaveBindings` and `SetBinding*` are forbidden by the static scan). The automatic binding probe makes, clears, makes and clears it in a single step with no yield, so no press can be routed; the guided key probe holds it only while its prompt is open. Click requests bind no key.
- **Released on every path.** `Runner` calls `Guided.End()` and `Probe.Release()` when a case ends, on Stop, on a closed window, on an error, on a timeout, on combat and at the end of the run. `Probe.Release()` hides every probe frame, takes their scripts and mouse off, puts hit-rectangle insets and propagation back and forgets the click trial; `Probe.Snapshot()` and `Guided.Snapshot()` say what is still live (nothing, afterwards). Tests check each route.
- **Combat.** A run is refused in combat and stopped by `PLAYER_REGEN_DISABLED`; the probes never try a protected call in combat. A restriction the client *does* show out of combat (a call that raises, `HasRestrictions`, `IsProtected`) is recorded as an observed restriction and the probe goes on; it never tries a different route to get the same effect.
- **Saved data.** Nothing is written. The runner's fingerprint of the saved roots brackets every case; a test checks `TwichUIDB` is deep-equal afterwards.
- **Not in releases.** Unchanged: the Lab is excluded from packages (`.pkgmeta`, `tools/release.py`).

### Source evidence from the Forever API documentation (documentation, not observation)

Read from `wow-ui-source` (`forever`) `Blizzard_APIDocumentationGenerated`; these say what the documentation declares, **not** what the client does:

- `EnableMouse`, `EnableMouseMotion`, `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetHitRectInsets`, `SetFrameLevel` and `SetToplevel` are `IsProtectedFunction`; `SetPropagateMouseClicks` / `SetPropagateMouseMotion` / `SetPassThroughButtons` are also `HasRestrictions`. `GetHitRectInsets` is not protected. Whether "protected" bites an addon's own unprotected frame out of combat is exactly what `api.mouse.states` and `api.hitrect.insets` record.
- There is no `EnableMouseClicks` in the documentation; the click flag's setter is `SetMouseClickEnabled`. The probes report the method's presence and never claim support.
- `Button:Click` declares `ChecksForbiddenAspects = ScriptedInput` on `self`; Blizzard's own slash-command code checks `HasAccessConstraints()` and `HasAnyForbiddenAspects(ScriptedInput)` before clicking a button. The Lab's button has none (`api.click.has_access_constraints` reports it).
- `C_RestrictedActions.CheckAllowProtectedFunctions(object, silent)` returns whether the calling context may call protected functions on the object; the probes use it (silent) as the safe observation of "would a protected call be allowed here".
- `SetOverrideBindingClick`, `ClearOverrideBindings` and `GetBindingAction` are not in the generated documentation files; `GetBindingAction(key, checkOverride)` is used by Blizzard's own UI (`Blizzard_Keybindings`, `CoinPickupFrame`).

### Client-API findings (fill in from real runs)

Nothing below has been observed yet. Each row is updated from a copied report, with the client version, the date and the case. "Model" rows compare the Lab's assumption in `Reach.lua` with what was observed; **if they differ, the model is not changed by running the probe**: record the discrepancy and open a narrow follow-up.

| Question | Case, fact keys | Observed (client, date) | Reach model assumes | Agrees? |
|---|---|---|---|---|
| Can an override binding be made and cleared out of combat from addon code? | `api.binding.override` `bind_ok`, `action_*` | not yet observed | yes (M5 used it once) | - |
| Does a real key press reach the Lab's button, again after clear and re-register? | `api.binding.keypress` `first`, `second` | not yet observed | yes | - |
| Is the binding API restricted in combat? | `api.binding.override` `protected_allowed` (read, not tried) | not yet observed | refused in combat | - |
| `EnableMouse(false)` and the click/motion flags | `api.mouse.states` `enable-false`, `flags_consistent` | not yet observed | all three read false | - |
| Motion only / clicks only: which calls produce them | `api.mouse.states` `motion-only-*`, `clicks-only-*` | not yet observed | flags are independent | - |
| A script alone (`SetScript("OnEnter")`) and the mouse | `api.mouse.states` `script-only` | not yet observed | does not enable the mouse | - |
| Hidden and disabled frames' flags | `api.mouse.states` `hidden`, `disabled` | not yet observed | flags unchanged, ineligible for other reasons | - |
| Does `EnableMouseClicks` exist? | `api.mouse.method.EnableMouseClicks` | not yet observed | not used | - |
| `Click()` on a disabled / hidden / mouse-off / click-off / parent-hidden button | `api.click.*` | not yet observed | (not modelled; `Press` refuses) | - |
| A mouse-enabled upper frame: who gets a real click | `api.click.overlap` `mouse-on` | not yet observed | the upper frame blocks | - |
| Upper frame with clicks off | `api.click.overlap` `clicks-off` | not yet observed | does not block a click | - |
| Upper frame propagating clicks | `api.click.overlap` `propagate` | not yet observed | does not block a click | - |
| Equal strata and level: what decides the top frame | `api.order.*`, `observation` | not yet observed | unknown (reported **ambiguous**; unchanged whatever is found) | - |
| `SetHitRectInsets`: callable out of combat, values accepted, read-back | `api.hitrect.insets` | not yet observed | accepted | - |
| Does the pointer's region follow the insets? | `api.hitrect.pointer` | not yet observed | yes (hit rectangle = rectangle less insets) | - |
| Do `GetMouseFoci`, `OnClick` and what you saw agree? | every click scenario (`foci_top_ran_onclick_or_up`, `visual_equals_foci`) | not yet observed | not assumed | - |

### Offline tests

`tests/test_testlab_api.lua` (stand-in frames that answer the way each test says, several different ways on purpose): registration, safety classes and opt-in; the mouse-state matrix (and a client without the newer methods, and one whose `IsMouseEnabled` disagrees); the click counters (a lenient, a strict, a broken and a raising `Click`); the hit-rectangle round trip (rounding, refusal, missing method); the binding probe (combat, a held key, no API, a raising call, `GetBindingAction` missing or raising, and `TwichUIDB` unchanged); release on error, normal end without cleanup, Stop, timeout, combat and a closed window; the click trial (bounded, outside the square, finished after a quiet moment); the guided flows (a button press is not a key press, Skip, Cancel, combat, timeout, unsupported methods, answers kept apart from `GetMouseFoci` and `OnClick`, the equal-level observation under three different stand-in clients, the hit-rectangle model disagreeing with the pointer); and that no fact is cut at 60 characters. **They assert no Forever behaviour**: they prove the probes measure and report whatever the frames did and clean up. Hand-made defects were checked against them (release dropped, trial kept, clear dropped, `ups` counted as clicks, key requirement dropped, outside-square clicks counted, opt-in dropped, inset reset dropped, mouse not turned off, control dropped): all killed.
