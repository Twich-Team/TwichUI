# TwichUI Test Lab

A **development-only** addon, `TwichUI_TestLab/`, that runs selected TwichUI code inside the real WoW: Forever client and produces a report you can copy. It is milestone 1 of `docs/workshop/testing-roadmap.md` (sections C, F, G); later milestones only add case files (milestone 2 added `Fixtures.lua`, `Reference.lua` and `cases/Market.lua`, below; milestone 5 added `Reach.lua`, `Guided.lua` and `cases/UI.lua`, see "Reachability and the pointer probe").

It is not a player feature. It is never packaged and never offered to players (see "Not in releases").

## Installation (development only)

Copy the folder `TwichUI_TestLab/` from the repository into your development client's `Interface/AddOns/` folder, beside `!!!TwichUI`. It needs `!!!TwichUI` turned on. It is marked load-on-demand, so it does nothing at login. The machine-local, gitignored `tools/deploy.sh` also copies it (and adds the extra interface number to its `.toc`, as for the other addons), so a normal deploy to the development client installs the Lab. That script is never part of a release.

The only change to a released addon is one row in the TwichUI data bar menu (`!!!TwichUI/modules/SettingsBrokerMenu.lua`): **Test Lab (development)...**. It is drawn only while the `TwichUI_TestLab` folder is installed (`C_AddOns.DoesAddOnExist`), so a standard release, which never contains the folder, shows nothing. The first click loads the addon (which opens its window); after that it opens and closes the window. If the load fails it says why in chat. The shipped code is that one row and about ten lines; `TwichUI_Workshop` is unchanged.

## Opening and running

1. In game: click the TwichUI data bar entry and choose **Test Lab (development)...** (or `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`). Loading opens the window once. Afterwards the menu row and `/tuilab` open and close it.
2. Tick the categories to run (every category is on by default except **Pointer probe (guided)**, which asks things of you and runs only when you tick it) and press **Run**.
3. Watch the progress line (case *n* of *m*, the case id, elapsed time), the counts and one row per case.
4. **Stop** is enabled while a run is going. **Copy report** fills the box at the bottom and selects it; press **Ctrl+C**, then paste the text where it is needed (the game gives addons no clipboard).
5. Esc or the close button closes the window, and **closing it stops a run in progress**.

Nothing runs by itself: not at login, not at load, not on a timer.

## What the categories hold

| Category | Class | Evidence label | What it does |
|---|---|---|---|
| Core calculations (`core`) | `pure` | **synthetic** | Production Workshop code (`Prices`, `History`, `Market`, `W.Split`) in the client's Lua, on made-up data handed in as arguments. The same file, `cases/Core.lua`, is run offline by `tests/test_testlab.lua`. |
| Client facts (`client`) | `readonly` | **client** | Lua number behaviour (exactness below 2^53, `%.0f`, division by zero, yielding across `pcall`), which API names exist (`GetTimePreciseSec`, `C_AddOnProfiler`, `GetMouseFoci`, `EnumerateFrames`), and a 2-second pause probe of the Lab's own runner. Values the client is not documented to give are *reported* as facts, not asserted. |

**Fixtures and reference models (milestone 2).** `Fixtures.lua` makes deterministic synthetic markets from a seed (its own Wichmann-Hill generator, so a seed gives the same data in plain Lua and in the client): `FX.Listings` (auction records, with deliberately malformed ones marked by `intent`), `FX.Calendar` (a market's scans over days, with gaps, repeats, clock moves and cut scans), `FX.Markets`; every size is clamped to `FX.LIMITS`. `Reference.lua` holds independent models of the batch and of the history and statistics (how they differ from the production code is in the file's header). `cases/Market.lua` adds three bounded `pure` cases to the core category (`market.reference.batch` 16 seeds, `market.reference.history` 6 seeds, `market.trend.window-and-percent`); they call `History.Add/Trim` and `Market.*` with a market table handed in, and never the saved markets or `Prices.<commit>`. The large randomized suite (200 scenarios per model) stays offline: `tests/test_workshop_market_reference.lua`.

**Crafting fixtures and reference models (milestone 3).** `Fixtures.lua` adds `FX.Crafting` (a small craft queue with what is owned in the bags, bank and guild bank, auction price lists, vendor offers, known recipes and an optional cut), `FX.Economy` (recipes as the window may read them, some malformed on purpose) and `FX.StockObs` (what the bank and guild bank were last seen to hold); `Reference.lua` section 4 adds one-item-at-a-time allocation, combined materials, the stock rules, the cost of any sourcing choice for the shopping plan with an exhaustive enumeration, the craft estimate and the Opportunities order. `cases/Crafting.lua` adds three bounded `pure` cases to the core category (`crafting.reference.allocation` 24 seeds, `crafting.reference.shopping` 8 seeds and at most 64 sourcing choices each, `crafting.reference.estimate` 20 seeds). They call `W.Split`, `Materials.Rows`, `Shopping.Plan`, `Prices.Quote/Estimate` with explicit inputs, never the saved prices, stock or queue. The stock cases (they fill the saved storage records to test `Stock.Sources`) and the large randomized suite stay offline: `tests/test_workshop_crafting_reference.lua`.

**Reachability and the pointer probe (milestone 5).** A working click handler does not prove a working button, so this category reads what the client does with the pointer. Section "Reachability and the pointer probe" below has the whole picture; `Reach.lua` is the analysis, `Guided.lua` the guided-case mechanism, `cases/UI.lua` the cases (`ui.pointer.api`, `ui.workshop.reach-scan`, and the three guided cases `ui.pointer.add-button`, `ui.pointer.opportunity-row`, `ui.pointer.row-picture`).

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
| `guided` | Asks the player to put the pointer somewhere, then **reads** what the client reports (`GetMouseFoci`, rectangles, flags). Never clicks, writes or sends. The only input mechanism is the one temporary key binding described below. Its category is never ticked for the player, and an unqualified `TL.Select()` leaves it out. |
| `owned` | Accepted by the registry, not used yet. |

Enforced:

- **Never reassigned:** `TwichUIDB`, `TwichUIWorkshopDB`, `TwichUIDiagnosticsDB`. No fixture is ever swapped in for them (a disconnect during a swap would make the game save the fixture over the player's data).
- **Fingerprint:** every case is bracketed by a cheap fingerprint of the three roots (key counts, `v` fields, each market's `at`/`n`). A difference fails the case. It cannot tell the game's own change in that instant from the case's; run it again.
- **Static scan:** `tests/test_testlab.lua` scans every `TwichUI_TestLab/**/*.lua` (comments removed) for the forbidden names below, for any use of the three roots other than reading them by name, for assignment through `_G`, and checks the scanned files equal the `.toc`'s.
- Forbidden names: `Commit`, `BeginCommit`, `Apply`, `Queue.`, `Known.Store`, `Vendor.`, `Storage.`, `Session.`, `Scan.Start`, `Observe.OpenRecipe`, `ReplicateItems`; every bid, post, purchase, cancel, mail, trade, destroy, disenchant, craft, merchant and item-use call; `SendAddonMessage` / `SendChatMessage` / `SendCommMessage`, `SetCVar`; `hooksecurefunc`, `securecall`, `setfenv`/`getfenv`, `loadstring`/`load`, `dofile`, `require`, `rawset`, `RegisterGameMenuEscHandler`; and for input: `SaveBindings`, `SetBinding*` (a saved binding), `LoadBindings`, `EnableKeyboard`, `SetPropagateKeyboardInput`, `OnKeyDown`/`OnKeyUp`/`OnChar` (no keyboard capture). **`SetOverrideBindingClick` / `ClearOverrideBindings` appear in `Guided.lua` and nowhere else** (a test checks that, that the binding is made for the Lab's own button with one key, and that it is never cleared for `UIParent`); other files may only name them inside a quoted string (the API presence report).
- No Blizzard function is wrapped or hooked; nothing is sent; Esc uses `UISpecialFrames`.
- **One side effect to know:** a case that `needs` the Workshop loads it through the core's `WorkshopLauncher.Load()` (refused in combat; the case is then skipped with the launcher's reason). Loading the Workshop is the normal load: the game loads its saved variables and the Workshop initialises as it always does. The Lab does that *before* a case's fingerprint, and does nothing more.
- A run is refused in combat; `PLAYER_REGEN_DISABLED` (registered only during a run) and a check each frame stop one.

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
overruns (a step ran longer than the slice; it could not be interrupted):
  <case id>  <ms> ms in one step
facts: client.api.GetTimePreciseSec=function client.lua.div_zero_value=inf ...
```

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
- The Lab is not a benchmark tool and has no `/tui lab` command (an owner decision). The reachability cases (milestone 5) have been run **offline against a fake frame world and in the simulator only; they have not run in the game yet.** What the real client puts under the pointer is exactly what their first real run will tell us.

## Real-client checks for initial acceptance

Four, by hand, in the development client:

1. **Load:** the data bar menu's **Test Lab (development)...** row appears (and does not appear with the folder removed), and clicking it opens the window with no Lua error; the row and `/tuilab` close and reopen it.
2. **Run both categories:** every core case passes; the client category passes; the report's `facts:` line shows what this client has (note especially `client.lua.div_zero_*`, `client.lua.yield_across_pcall` and the API presence values).
3. **Stop mid-run:** run both, then press Stop while the progress line reads `client.runner.pause-probe` (it waits about 2 s). The remaining rows must read `stopped`, the pause-probe row `stopped ... not resumed`, and Run must be enabled again.
4. **Copy the report:** after a run, Copy report selects the text; Ctrl+C and paste it elsewhere; it should start `TWICHUI-TESTLAB REPORT schema 1` and contain no names.

Also worth one look: that `/reload` afterwards shows no change in the Workshop's data (the Lab changed none by design; the offline test checks the roots are deep-equal).

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
3. Open the Test Lab (data bar menu, **Test Lab (development)...**, or `/tuilab`). **Drag the Lab window aside** so it does not cover the Workshop's right-hand details or the list (the Lab frames are movable; if one is under the pointer the sample is *not counted* and says so).
4. Tick **Pointer probe (guided)** and **Interface reachability**; press **Run**. The read-only cases finish at once. A small **prompt** appears at the top of the screen with the first step.
5. **Step 1, the Add button.** Put the pointer over **Add to crafting plan** (do not click) and press **F9**. If the pointer was not over it, the sample is not counted and the prompt tells you how far off it was; try again. Then the next prompt appears.
6. **Step 2, a row.** Move the pointer onto a recipe row's **name**, hold it still for a second, press **F9**. (A selected row is fine; try both.)
7. **Step 3, a row's picture.** Move onto the little recipe picture at a row's left, hold still, press **F9**. The row must stay lit (it follows the picture).
8. Press **Copy report**, then **Ctrl+C**, and paste it where it is needed. Skip a step with the prompt's **Skip this step**; **Cancel** (prompt) or **Stop** ends it all.
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

- Everything above is **unit-tested offline against a fake frame world and simulator-tested; none of it has run in the game.** The guided cases are the only thing that will say what the client puts under the pointer.
- The simulator's `GetMouseFoci` returns only a frame a scenario forced with `A_Admin.SetMouseOverFrame`; it never works out a frame from a position. The simulator also stores a scroll frame's offset without moving its rows' rectangles. Both are recorded as checks in the scenario.
- The geometry cannot say how the client orders frames of equal strata and level (it reports them ambiguous), and it does not model secure frames or mouse capture.
- A hit-test miss in a scan is a pointer-level finding, not a diagnosis: the frame named as blocker is where to look.
