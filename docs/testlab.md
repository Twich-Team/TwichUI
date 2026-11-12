# TwichUI Test Lab

A **development-only** addon, `TwichUI_TestLab/`, that runs selected TwichUI code inside the real WoW: Forever client and produces a report you can copy. It is milestone 1 of `docs/workshop/testing-roadmap.md` (sections C, F, G); later milestones only add case files.

It is not a player feature. It is never packaged and never offered to players (see "Not in releases").

## Installation (development only)

Copy the folder `TwichUI_TestLab/` from the repository into your development client's `Interface/AddOns/` folder, beside `!!!TwichUI`. It needs `!!!TwichUI` turned on. It is marked load-on-demand, so it does nothing at login. There is no deploy-script option yet (a convenient opt-in local one is a later decision).

Nothing in `!!!TwichUI`, `TwichUI_Workshop` or any released addon was changed for it.

## Opening and running

1. In game: `/run C_AddOns.LoadAddOn("TwichUI_TestLab")`. Loading opens the window once. Afterwards `/tuilab` opens and closes it.
2. Tick the categories to run (both are on by default) and press **Run**.
3. Watch the progress line (case *n* of *m*, the case id, elapsed time), the counts and one row per case.
4. **Stop** is enabled while a run is going. **Copy report** fills the box at the bottom and selects it; press **Ctrl+C**, then paste the text where it is needed (the game gives addons no clipboard).
5. Esc or the close button closes the window, and **closing it stops a run in progress**.

Nothing runs by itself: not at login, not at load, not on a timer.

## What the categories hold

| Category | Class | Evidence label | What it does |
|---|---|---|---|
| Core calculations (`core`) | `pure` | **synthetic** | Production Workshop code (`Prices`, `History`, `Market`, `W.Split`) in the client's Lua, on made-up data handed in as arguments. The same file, `cases/Core.lua`, is run offline by `tests/test_testlab.lua`. |
| Client facts (`client`) | `readonly` | **client** | Lua number behaviour (exactness below 2^53, `%.0f`, division by zero, yielding across `pcall`), which API names exist (`GetTimePreciseSec`, `C_AddOnProfiler`, `GetMouseFoci`, `EnumerateFrames`), and a 2-second pause probe of the Lab's own runner. Values the client is not documented to give are *reported* as facts, not asserted. |

Evidence labels in the report: **client** = observed in this game client; **synthetic** = production code in the client's Lua on made-up data; **guided** = observed with the player's help (no guided case exists yet); **not run** = never started.

The core cases' expected values were worked out by hand and are written beside each case in `cases/Core.lua`. If one fails, decide first whether the hand arithmetic or the code is wrong.

### Deferred, on purpose

Calls that read the saved markets (`Market.Source`, `Market.Info`, `Market.Markets`, `Prices.Market`, `Prices.Keys`) are not in M1: the only way to test them is against `TwichUIWorkshopDB`, which the Lab never replaces, swaps or writes. `Market.Price`, `Stats`, `Trend`, `Compare` and the rest are tested through their `opt.market` table argument, the existing pure-data boundary, with an explicit `opt.now`. A saved-data integrity check that *reads* the real roots belongs to the persistence milestone (M9). Market-side selection and the quantity-aware pricing algorithm are not touched (owner decisions: those are future Market-service changes).

## Safety

Every case declares a class, and the registry refuses a case without one.

| Class | May do |
|---|---|
| `pure` | Call production functions with explicit inputs only, on made-up data. |
| `readonly` | Read live game state or real saved data. |
| `owned`, `guided` | Accepted by the registry, not used yet. |

Enforced:

- **Never reassigned:** `TwichUIDB`, `TwichUIWorkshopDB`, `TwichUIDiagnosticsDB`. No fixture is ever swapped in for them (a disconnect during a swap would make the game save the fixture over the player's data).
- **Fingerprint:** every case is bracketed by a cheap fingerprint of the three roots (key counts, `v` fields, each market's `at`/`n`). A difference fails the case. It cannot tell the game's own change in that instant from the case's; run it again.
- **Static scan:** `tests/test_testlab.lua` scans every `TwichUI_TestLab/**/*.lua` (comments removed) for the forbidden names below, for any use of the three roots other than reading them by name, for assignment through `_G`, and checks the scanned files equal the `.toc`'s.
- Forbidden names: `Commit`, `BeginCommit`, `Apply`, `Queue.`, `Known.Store`, `Vendor.`, `Storage.`, `Session.`, `Scan.Start`, `Observe.OpenRecipe`, `ReplicateItems`; every bid, post, purchase, cancel, mail, trade, destroy, disenchant, craft, merchant and item-use call; `SendAddonMessage` / `SendChatMessage` / `SendCommMessage`, `SetCVar`; `hooksecurefunc`, `securecall`, `setfenv`/`getfenv`, `loadstring`/`load`, `dofile`, `require`, `rawset`, `RegisterGameMenuEscHandler`.
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
- The Lab is not a benchmark tool and has no UI probes, fixtures/PRNG, guided cases, simulator support or `/tui lab` command (later milestones, and the last one is an owner decision).

## Real-client checks for initial acceptance

Four, by hand, in the development client:

1. **Load:** `/run C_AddOns.LoadAddOn("TwichUI_TestLab")` opens the window with no Lua error; `/tuilab` closes and reopens it.
2. **Run both categories:** every core case passes; the client category passes; the report's `facts:` line shows what this client has (note especially `client.lua.div_zero_*`, `client.lua.yield_across_pcall` and the API presence values).
3. **Stop mid-run:** run both, then press Stop while the progress line reads `client.runner.pause-probe` (it waits about 2 s). The remaining rows must read `stopped`, the pause-probe row `stopped ... not resumed`, and Run must be enabled again.
4. **Copy the report:** after a run, Copy report selects the text; Ctrl+C and paste it elsewhere; it should start `TWICHUI-TESTLAB REPORT schema 1` and contain no names.

Also worth one look: that `/reload` afterwards shows no change in the Workshop's data (the Lab changed none by design; the offline test checks the roots are deep-equal).
