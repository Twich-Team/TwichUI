# TwichUI Diagnostics: profiling, captures and reports

For anyone investigating TwichUI's performance, supporting a player who reports a problem, or adding an operation or a
gauge to measure. The code is `TwichUI_Diagnostics/` (a load-on-demand addon), `!!!TwichUI/DiagnosticsLauncher.lua`
and the `R.Perf` block in `!!!TwichUI/Core.lua`. **Nothing here has been run in the game yet**: every API below was
checked in Forever's API documentation (`../wow-ui-source`, branch `forever`, 1.60.1) and Blizzard's own uses of it,
and the behaviour was tested offline (Lua 5.1, stand-in frames). See "In-game checks still to do".

The older `/tui diagnostics` (troubleshooting report, temporary tracing, `diag/`) is unchanged and separate.

## Packaging and loading

| Part | Where | Loaded |
|---|---|---|
| `R.Perf` (stub instrumentation points) | `!!!TwichUI/Core.lua` | always (a few functions and two empty tables) |
| Launcher, `/tui perf`, Arm next reload | `!!!TwichUI/DiagnosticsLauncher.lua` | always (no events, timers or frames) |
| Call sites (`Perf.on and Perf.Start(...)`) | the modules listed under "Instrumented operations" | always (one table read and a test each) |
| Settings entry (status row and Open button) | `TwichUI_Settings/pages/Troubleshooting.lua` | with the settings window |
| Collectors, sessions, findings, comparison, export, charts, window | `TwichUI_Diagnostics/` | first `/tui perf` or Open; never in ordinary play |

`TwichUI_Diagnostics.toc`: `RequiredDeps: !!!TwichUI`, `LoadOnDemand: 1`, `SavedVariables: TwichUIDiagnosticsDB`, the
same Interface and Version as the others. `.pkgmeta` moves it out beside the core; `tools/release.py` checks a zip has
exactly four folders and that this one is load on demand; `tools/deploy.sh` deploys it. It is never loaded in combat
(the launcher says so and waits for you), except for an armed start-up, which loads before combat can exist.

The game can't unload an addon: once loaded it stays loaded until a reload. **Stop** ends collection: the sampler's
OnUpdate and every event are removed, `R.Perf.on` goes back to false (the core's own stub functions are put back), the
window's live ticker stops when it closes, and captures are bounded (below). That is lazy construction, not unloading.

## Capability matrix (what this client gives; looked up at run time, never assumed)

| Capability | API (Forever docs) | Unit | Kind | Used for | Notes |
|---|---|---|---|---|---|
| Fine clock | `GetTimePreciseSec` (OsDocumentation) | s → ms | instrumented | operation scopes | nothing else can reset it; smallest step measured at each start (`DX.ClockResolution`) |
| Fallback clock | `debugprofilestop` | ms | instrumented | scopes, only without the above | counts from the last `debugprofilestart` *anyone* called: a backward step is discarded and counted. `debugprofilestart` is never called (a test fails if it is) |
| Addon profiler | `C_AddOnProfiler.GetAddOnMetric/GetOverallMetric`, `IsEnabled` | ms per client tick | client counter | per-frame TwichUI, TwichUI_Settings, TwichUI_Diagnostics and all-addon time (`LastTime`); cumulative ticks over 1/5/10/50/100 ms and `PeakTime` at the start, each gauge interval and the end | "all times are in milliseconds"; `CountTimeOver*` are since client start-up: used as differences, never reset (`ResetCPUUsage` is never called); a counter going down is reported, not used |
| Allocation of one call | `C_AddOnProfiler.MeasureCall` | bytes | client counter | focused trace, opt-in, `Perf.Call` sites only | Blizzard's `BenchmarkUtil.lua` uses it; error behaviour inside it is not documented |
| Legacy CPU totals | `UpdateAddOnCPUUsage`, `GetAddOnCPUUsage` | ms, cumulative | client counter | only when `scriptProfile` was `1` at load | the `scriptProfile` setting is not mentioned anywhere in Forever's UI source: if the client doesn't know it, this is "unavailable". Turning it on is an explicit, confirmed request (Overview > Advanced) that takes effect after a reload you make; the window shows the current value, the value at load and whether Diagnostics requested it, and offers to turn it off again (it explains when someone else turned it on) |
| Per-addon memory | `UpdateAddOnMemoryUsage`, `GetAddOnMemoryUsage` | KB | sampled | memory timeline | Blizzard's addon list calls the update "Expensive" and waits 15 s; never under 5 s here; each update is timed and reported as the diagnostics' own cost |
| Whole-UI Lua heap | `collectgarbage("count")` | KB | sampled | once a second | every addon together |
| Frame interval | OnUpdate `elapsed` | ms | frame interval | distribution, long frames, discontinuities | only while recording; not CPU |
| Client FPS | `GetFramerate` | frames/s | client counter | once a second | the client's smoothed figure, kept apart from intervals |
| Call paths | `debugstack` | text | sampled | focused trace: a new slowest call, at most one a second | TwichUI's files only, relative to `AddOns/`; other code shows as "(other code)" |
| Errors | `R.Fault` (TwichUI's handlers), `ADDON_ACTION_BLOCKED/FORBIDDEN`, `LUA_WARNING` | count | instrumented | Errors view | the game's error handler is never replaced: errors in timers, frame scripts and other addons are not seen |
| Event bus | `R.Perf.Received/Callback` in `Core.lua` | count, ms | instrumented | Events view | TwichUI's bus only (not frames a module registers directly, not other addons) |
| Timers | none | | | | TwichUI has no central timer registry; only what module snapshots report |

`GetFunctionCPUUsage`, `GetFrameCPUUsage`, `GetEventCPUUsage` and `GetEventTime` are documented but not used: they need
function or frame references, `scriptProfile`, or have no documented units.

## Measurement semantics

- **Units:** durations in ms; capture times in seconds from Start; memory in KB; rates per minute of capture unless named.
- **Operation scopes** (`Instrument.lua`): inclusive time is everything inside the scope; *self* time is inclusive
  minus the inclusive time of instrumented scopes directly inside it. Uninstrumented callees and the game's own code stay
  in the caller's self time. Self times never overlap, so "measured TwichUI work" is their sum. An operation running
  inside itself adds its time once (outermost); inner activations count as calls and `reentered`.
- **Aborted scopes:** a scope an error went through never reaches Stop; it is let go (counted `aborted`, its time not
  used) when an outer scope stops, at the next frame (the sampler's OnUpdate can't run inside a TwichUI scope), or when
  recording stops. Until then, scopes started in the same frame are counted as inside it: their own times are right,
  only the recorded caller can be wrong. Scopes must not span a coroutine yield (none of the instrumented ones do).
- **Event callbacks** are scopes under `event:<EVENT>`; one received event and each callback it reaches are counted
  separately, and each listener has its own row (`<EVENT> listener #<slot>`; the bus has no module names, and nothing
  keeps the function alive: a weak table).
- **Percentiles** come from a log histogram (100 buckets, each about 19% wider than the last, from 0.001 ms): the
  value given is the bucket's upper edge. Labelled "approximate" everywhere.
- **Long frames** (`prefs.spikeMs`, default 50 ms) keep the five frames before and after. The client's `LastTime` read
  in an OnUpdate is for its latest tick and may belong to the frame before; instrumented work is what *ended* between
  two OnUpdates. A frame of `prefs.gapMs` (1000 ms) or more, or one during a loading screen, is a discontinuity: listed,
  left out of distributions and shaded on charts.
- **Overhead:** the sampler, gauge reads and memory updates are timed with the same clock; the cost of an empty scope is
  calibrated at each start (200 pairs) and multiplied by the calls; the client's own figure for `TwichUI_Diagnostics`
  is recorded per frame. Findings flag a capture where these reach `prefs.thresholds.overheadShare` of TwichUI's time.

## Recording

States: stopped (default; nothing starts at login), recording, finishing (collection already stopped; summing and
sorting wait for the next frame, or for `PLAYER_REGEN_ENABLED` if stopped in combat). Start / Stop / Cancel /
Marker are on the window's strip and in `/tui perf start [preset] [minutes]`, `stop`, `cancel`, `mark [note]`,
`status`. A capture stops by itself at its length (at most 30 minutes) or when its timeline is full. Closing the window
does not stop it: a small badge (top of the screen, movable, `prefs.badge`) says it is recording until it stops.

Presets (`Presets.lua`) choose what is timed and how often things are read; none changes a setting, toggles a feature,
uses an item, sends anything or makes up events. Each states its cost before you start.

| Preset | Length | Memory | Gauges | Timed |
|---|---|---|---|---|
| General performance | 5 min | 15 s | 5 s | everything |
| Map and NPC tracking | 3 min | 15 s | 2 s + each map close | `npcs.`, `pins.`, `map.`, `nav.`, events |
| Settings responsiveness | 3 min | 10 s | 2 s + each settings close | `settings.`, `core.`, events |
| Group combat | 10 min | 30 s | 5 s | everything (memory rarely, to disturb combat least) |
| Memory and lifecycle | 10 min | 5 s | 5 s + window cycles | everything |
| Focused trace | 2 min | 15 s | 5 s | one subsystem; call paths for slowest calls; optional `MeasureCall` allocation |

## Instrumented operations (and what stays uninstrumented)

| Id | Where | Kind |
|---|---|---|
| `event:<EVENT>` | `Core.lua` event bus dispatch | event |
| `core.savedData`, `core.startupHook` (detail: hook index) | `Core.lua` ADDON_LOADED | init |
| `npcs.search` | `npcs/Search.lua` `SR.Run` (not for an empty query) | search |
| `npcs.knowledge.rebuild` | `npcs/Knowledge.lua` `Build` | rebuild |
| `npcs.map.layout` | `npcs/Map.lua` `NMAP.Layout` | layout |
| `npcs.import`, `npcs.cleanup` | `npcs/Store.lua` `NS.MergeReported`, `NS.ForgetMany` | bulk |
| `pins.map.layout` | `pins/Map.lua` `PM.Layout` | layout |
| `reminders.refresh` (`Perf.Call`), `reminders.decide` | `reminders/Controller.lua` | rebuild, evaluate |
| `healer.update` | `healer/Watch.lua` `Update` (live path; previews not timed) | update |
| `settings.describe`, `settings.window.build` (`Perf.Call`) | `TwichUI_Settings/Window.lua` `UI.Open` | init |
| `settings.page.build` (`Perf.Call`), `settings.page.layout`, `settings.search` | `TwichUI_Settings/Window.lua` | build, layout, search |
| `settings.search.index` | `TwichUI_Settings/Search.lua` `Search.Build` | rebuild |

Gauges (`Gauges.lua`) read what modules already report (`Snapshot()` functions and a few read-only counts): event-bus
listeners and events (`R.ListenerCounts`, added to `Core.lua`), switch listeners, settings-closed callbacks, effects
easing, settings shown, pages drawn and search index, world map shown, NPC and pin marker pools and those in use, map
detail tiles, navigation tiles decoded, reminders running and observation keys, Healer Watch's and class bars' events.
No global function, `CreateFrame`, timer or event registration is wrapped or replaced.

## Views

Overview (start a capture; capability matrix; Arm next reload; legacy CPU; GC experiment; for a capture: what was
recorded, profiling, where the work was, findings, what can't be concluded) · Timeline (one metric per chart on one
axis: frame interval, TwichUI CPU by the client, instrumented work, events, Lua heap, the diagnostics' own CPU; columns
keep each second's worst; markers; drag to select a window; long frames and markers in it) · Operations (ranked by total,
self, slowest, 95th or calls; slowest calls with context and call paths; counters, limits reached) · Events & lifecycle
(received vs callbacks; callbacks; gauges start/end/peak and cycles) · Memory (sampled timeline; net, peak; caches and
pools; how to read it) · Errors (observed; your own note) · Compare · Export. Metric colours are a fixed order checked
with the data-viz palette validator against the window's stone surface (teal, rust, blue, bronze, violet; A/B blue and
bronze); text is in the window's text colours. Live: the strip once a second; the Timeline at most every 5 s and only
while shown; nothing while the window is closed (except the badge's once-a-second text).

## Findings (`Findings.lua`)

Fixed rules with stated thresholds (`prefs.thresholds`; defaults in `Base.lua`): one operation dominating measured work
(or a single expensive initialization), a rebuild or layout often per minute, an event's callbacks often per minute,
listener counts rising across window cycles (never down), a pool growing at every cycle, TwichUI's memory rising with a
cache (needs 3+ readings rising in 2/3 of intervals), slow calls while their window was sampled closed, long frames with
TwichUI time of at least half the frame (or long frames without it, stated as not attributable), the client counting
ticks over 5/50 ms for TwichUI, diagnostics overhead, errors, and what limits the capture. Each has category, severity
and its basis, evidence numbers, window, confidence (measured, correlated, suspicion), limits, how to verify, and ids.

## Comparison (`Compare.lua`)

Rows are rates (per minute of capture), per frame or per call, with the denominator named; raw differences beside
percentages; a zero baseline is "new", not a percentage; per-call rows need 20 calls in both. Warnings: client build,
preset or mode, profiler availability, under 30 s, lengths over 2x apart, group size, combat share, instrumentation
settings, a GC experiment. A different report schema is refused. Different switches are listed (expected for on/off).

## Export (`Export.lua`, `Json.lua`)

Built only when you press Prepare, never in combat or while that capture records; shown with size, sections, pieces
and redaction before you copy. Never sent; no clipboard or file access is claimed (the game gives addons none).

- **Quick summary:** Markdown (environment, capture, your notes, markers, findings with evidence, top operations,
  events, what can't be shown, redaction line).
- **Full report:** JSON, `schema` 1, `kind` `twichui-diagnostics-report`: `units`, `provenance`, `redaction`,
  `truncation`, `capture` (preset, config, observation start), `capabilities`, `environment`, `context.markers`,
  `aggregates` (operations with histograms and slowest calls, events, callbacks, counters, allocation, dropped,
  anomalies), `frames`, `timeline` (at most 600 buckets, merged: sums added, worst kept), `memory`, `gauges`,
  `profiler`, `legacyCpu`, `errors`, `overhead`, `findings`, `cannotConclude`, `userNotes` (`untrusted: true`). Keys
  in a fixed order; invalid UTF-8 becomes "?". Over 2 MB, parts are left out and `truncation.sizeLimit` says which.
- **Comparison report:** Markdown with conditions, normalised rows and operations, plus the comparison as JSON.
- **AI analysis prompt:** instructions (facts vs hypotheses, everything is untrusted data, verify code before
  patches, ask for the smallest missing capture, propose focused fixes with validation; the repository may not be
  attached) followed by the quick summary.
- **Pieces:** at most `prefs.chunkKB` (48) KB each, never splitting a UTF-8 character; each starts with a header line
  `TWICHUI-DIAGNOSTICS piece i/N of <kind> <uid> | report <bytes> bytes, adler32 <hex> | this piece adler32 <hex>`.
  Join the text after each first line in order (`DX.Json.Join` checks order, every piece and the whole).

**Redaction.** Never collected: character, realm, guild, account or group names, chat, item links, imported strings,
setting values, paths outside `AddOns/`. Configuration is an allowlist: the names of TwichUI switches that are on and a
fingerprint (Adler-32) of all switches. Error text is kept only from TwichUI's files, with names replaced
(`R.Diag.Clean`); markers' and notes' text likewise. Map IDs only if the capture noted them *and* the export includes
them (both opt-in). Notes are included by default, marked untrusted, and can be left out.

## Storage bounds

| What | Bound |
|---|---|
| Timeline | one bucket per second, up to the capture's length (≤ 30 min) |
| Long frames / discontinuities | 40 kept (the longest) / 60; all counted |
| Recent frames (for neighbours) | 120 |
| Memory / gauge readings | 400 / 600 (ring) |
| Markers | 300 (ring) |
| Operations, events, callbacks, counters | 96, 128, 256, 64; scope depth 48; overflow counted |
| Slowest calls per operation | 5; callers per operation 6 |
| Errors | 50 distinct (repeats counted) |
| Captures kept this session | `prefs.keepInMemory` (4); the oldest unsaved goes first |
| Saved captures | `prefs.saveLimit` (3), only when you press Save; timeline merged to 300 buckets |

Saved captures are in `TwichUIDiagnosticsDB`, written by the game at logout or reload (only then; only in sessions where
the addon was loaded, which is expected but unverified on Forever). A newer `version` there is left untouched.

## Start-up capture

A capture can only begin once `TwichUI_Diagnostics` is loaded, so start-up is recorded only after a reload you make:
**Arm next reload** (Overview, or `/tui perf arm`) writes `TwichUIDB.diagnosticsArm` (a one-shot hand-off, not part of a
profile or a backup). At the next load, at the very start of TwichUI's `ADDON_LOADED` (after its files ran and its
saved data was read), `DiagnosticsLauncher.ArmedBoot` clears the flag first, loads `TwichUI_Diagnostics` and starts a
one-minute "Start-up" capture: saved data, each start-up hook, login and entering the world are timed. An arming older
than 30 minutes is cleared and says so in chat. Not observed: TwichUI's files loading, other addons before it, the
client. Nothing ever reloads by itself. When not armed, the cost at load is one table field read.

## Overhead (offline measurements, Lua 5.1 on a development machine; not the game)

- **Off** (`tests/test_perf_engine.lua` prints it): a bare call 11–12 ns, the same call behind a guarded site
  16–17 ns, through `Perf.Call` 30–32 ns. No clock read, table, string or stack while off.
- **Recording:** one empty scope (Start + Stop) about 2.2 µs; the start-of-capture calibration agreed (2.25 µs).
- **Core memory at load** (`tools/memory_probe.lua --no-settings`): 7,531 KB before, 7,558 KB after (+28 KB: the
  launcher, the stub, call-site code and eight icon registry entries).

## How to record and export a useful issue report

1. Reproduce once to know the steps. Close other heavy windows; note the time of day if it matters.
2. `/tui perf` (or Settings > Troubleshooting > Diagnostics: Open). Pick the preset that matches (Map and NPC tracking
   for the map, Settings responsiveness for the settings window, General otherwise). Type one line of what you will do.
3. **Start**, do the steps, press **Marker** (with a word or two) at the moment the problem shows. Stop.
4. If you can, record a quiet baseline of the same length (stand still, same place) for Compare.
5. Overview: read the findings and what can't be concluded. Export > Quick summary (or AI analysis prompt) >
   Prepare > read it > Select all > Ctrl+C, piece by piece. Add the Full report if asked.

## How a developer instruments one operation and registers one gauge

```lua
local Perf = R.Perf   -- at the top of the file, beside the other locals

function MOD.Rebuild()
    if not ready then return end                         -- early exits before the scope
    local pt = Perf.on and Perf.Start("mymod.rebuild")   -- a stable "area.operation" id
    -- ... the work, unchanged ...
    if pt then Perf.Stop(pt) end                         -- before every return after the Start
end
-- many exits or results to pass back: wrap the body instead (all results, nils too; errors pass through)
function MOD.Find(...) return Perf.Call("mymod.find", Find, ...) end

-- optional: what it is (the window and findings use it); visible = "map.open" or "settings.shown" for work that
-- should only happen while that window is shown (the "ran while its window looked closed" finding)
Perf.Describe("mymod.rebuild", { module = "mymod", label = "My module's rows rebuilt", kind = "rebuild" })
-- a gauge: a number read at intervals and at window closes; reading it must build, load and change nothing
Perf.Gauge("mymod.pool", { label = "My module's frames made", kind = "pool", unit = "count",
    read = function() return #pool end })
```
Add the id to `DX.OPS` in `TwichUI_Diagnostics/Gauges.lua` if it should be described without loading your module first,
and to the table above.

## Tests

`tests/test_perf_engine.lua` (synthetic clock): off behaviour and cost; results and errors preserved through scopes;
nested inclusive/self time; re-entry; aborted, frame-crossing and backward-clock scopes; events vs callbacks;
sampler long frames and discontinuities; memory; repeated start/stop, cancel, time limit, combat-deferred finish,
profile change; histogram percentiles, ring truncation, timeline merging; findings evidence (and what is never
concluded); comparison normalisation, zero baselines, tiny samples, incompatibility; JSON validity (a reader in the
test), redaction, notes opt-out, the prompt's rules, pieces joining and tamper/order detection, UTF-8, size limits,
no export in combat; explicit saving (plain values only); focused filtering and allocation; armed start-up, stale
arming; no error reaching the handler. `tests/test_perf_window.lua`: every view without a capture, while recording,
after; badge on close; exports and comparison prepared; repeated open/close. `tests/test_npc_search.lua`: results
identical with a capture recording. `tests/test_release_tools.py`: four folders, load on demand.

## In-game checks still to do

1. `/tui perf` loads it (AddOns list shows it loaded); the window draws, icons show, text fits, Esc closes it.
2. Capability matrix: fine clock resolution reported; profiler "available"; scriptProfile row says what the client knows.
3. General capture while questing 5 min: FPS and frame interval agree roughly with the game's own FPS; TwichUI CPU per
   frame is in the range the AddOns list shows; long frames listed when you alt-tab (as discontinuities).
4. Open and close the settings 10 times in a Settings capture: listener gauges stay flat (or the finding appears).
5. World map: open, pan, search NPCs, change the filter, close; repeat. `npcs.map.layout` / `pins.map.layout` and
   pools appear; no layout while the map is closed.
6. Group combat in a dungeon: nothing stalls; stopping in combat says it waits; exports refuse during combat.
7. Memory capture with repeated window cycles; then the GC experiment: marked in the report.
8. Compare a capture with a feature on and off (same steps, same length).
9. Stop, then watch `/run print(TwichUI.Perf.on)` is false and the AddOns list shows no diagnostics CPU afterwards.
10. Arm next reload, `/reload`: the start-up capture starts and its report says when observation began; reload again:
    nothing starts. Test that loading an addon during another's ADDON_LOADED works on Forever.
11. Export pieces: copy each into a text file, join; the Adler-32 matches (`DX.Json.Join`).
12. Save a capture, `/reload`, see it under Capture shown.

## Not implemented, and why

- No statistical sampling profiler, flame graph or per-function CPU: the client gives no sampling API; scopes are
  explicit instrumentation of chosen operations.
- No visibility into timers, arbitrary frames, closures or other addons' events: no wrapping of global APIs.
- No error stack traces for errors TwichUI's handlers catch (the pcall ended them); the game's display has them.
- No per-module memory: the client's figure is per addon; only `MeasureCall` (opt-in) gives per-call allocation.
- No live comparison or chart of two metrics on one axis, by design.
