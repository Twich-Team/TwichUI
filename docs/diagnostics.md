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
  value given is the bucket's upper edge, clamped to the largest call (or frame interval) actually seen, so a
  percentile is never above the maximum. Labelled "approximate" everywhere.
- **Allocation per operation:** `collectgarbage("count")` is read at each scope's start and end (two reads, about 0.1 µs
  with the scope). The rise is summed per operation, inclusive and self (what instrumented children grew is taken off).
  It is approximate: a collection step inside the scope hides some of it (a fall counts as nothing), and it includes
  what the game's own functions allocated inside the scope. `C_AddOnProfiler.MeasureCall` (focused trace, `Perf.Call`
  sites) remains the client's own per-call figure.
- **Long frames** (`prefs.spikeMs`, default 50 ms) keep the five frames before and after. The client's `LastTime` read
  in an OnUpdate is for its latest tick and may belong to the frame before; instrumented work is what *ended* between
  two OnUpdates. A frame of `prefs.gapMs` (1000 ms) or more, or one during a loading screen, is a discontinuity: listed,
  left out of distributions and shaded on charts.
- **Overhead:** three parts that never overlap, timed with the same clock: the sampler (the OnUpdate's work *without*
  the reads below; before 2026-10-26 it included them and they were counted twice), the gauge reads (profiler counters
  included) and the memory updates; plus the cost of an empty scope, calibrated at each start (200 pairs) and
  multiplied by the calls. The client's own figure for `TwichUI_Diagnostics` is recorded per frame as a cross-check
  only: when it reads 0 although our clock measured work, the report says so instead of printing 0 as a fact. A
  finding is raised when the total reaches `prefs.thresholds.overheadShare` of TwichUI's time, as "medium" only when
  it is also large in absolute terms (2% of the capture, a memory update at the long-frame limit, or 5% of a frame
  per frame); otherwise "low": beside a cheap addon any tool looks large. A long frame also keeps what the diagnostics
  did in the frame before it (its interval includes our previous OnUpdate); one that would be under the limit without
  that (and our work was 10 ms or more) is reported as made by the diagnostics. Memory updates cost about 25 ms each on
  the first real capture, so General, Map and Focused read memory every 30 s (Settings 20 s, Memory and lifecycle 5 s).

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
| `npcs.minimap.tick`, `pins.minimap.tick` (`Perf.Call`, after the throttle) | `npcs/Minimap.lua`, `pins/Minimap.lua` `Update` > `Step` | update |
| `nav.search`, `nav.position`, `nav.progress`, `nav.ticker` (`Perf.Call`) | `nav/Nav.lua` `OnUpdate` (`nav.ticker`: each trail or arrow updater) | update |
| `nav.load` (`Perf.Call`) | `nav/Data.lua` `ND.Load`, around `C_AddOns.LoadAddOn` of `TwichUI_NavData` | init |
| `layouts.load` (`Perf.Call`) | `LayoutsLauncher.lua` `L.Load`, around `C_AddOns.LoadAddOn` of `TwichUI_Layouts` | init |
| `layoutwizard.load` (`Perf.Call`) | `LayoutsLauncher.lua` `L.LoadWizard`, around `C_AddOns.LoadAddOn` of `TwichUI_LayoutWizard` | init |
| `layoutwizard.overlay.build` (`Perf.Call`), `layoutwizard.overlay` (`Perf.Call`) | `TwichUI_LayoutWizard/Overlay.lua` `Build` (the first time the full-size preview opens), `Draw` (each time it opens, or a layout, scenario or the screen changes in it; never while it is closed) | init, layout |
| `layoutwizard.build` (`Perf.Call`), `layoutwizard.preview` (`Perf.Call`) | `TwichUI_LayoutWizard/Window.lua` `Build` (the first open only), `TwichUI_LayoutWizard/Preview.lua` `Draw` (each time a step with the preview is shown, a choice or the screen changes) | init, layout |
| `layouts.capture` (`Perf.Start`/`Perf.Stop`) | `TwichUI_LayoutWizard/Author.lua` `A.Capture` (the authoring workspace's Capture button: copies the named profiles through the adapters' allowlists and scans them) | bulk |
| `layouts.publish.build`, `layouts.publish.check` (`Perf.Call`) | `TwichUI_Layouts/Publish.lua` `Pub.Build` (Publish in the workspace), `Pub.Check` (Check, Publish, a package arriving, a stored one opened) | rebuild, evaluate |
| `layouts.publish.receive` (`Perf.Call`), `layouts.store.open` (`Perf.Start`/`Perf.Stop`) | `TwichUI_Layouts/Store.lua` `LY.Receive` (once per package a player accepts, a frame after it is unpacked), `Store.Open` (a stored package chosen in the setup or the workspace; the unpacking itself is Share.lua's background job) | bulk, evaluate |
| `layoutwizard.author.build` (`Perf.Call`) | `TwichUI_LayoutWizard/AuthorWindow.lua` `Build` (the first open of the authoring workspace only) | init |
| `layouts.plan`, `layouts.apply`, `layouts.verify`, `layouts.restore` (`Perf.Call`) | `TwichUI_Layouts/Engine.lua` `LY.Plan`, `LY.Apply`, `LY.Verify` and `LY.VerifyRestore`, `LY.Restore` (on request; `layouts.verify` also once after the reload that finishes an install or restore) | rebuild, bulk, evaluate, bulk |
| `classbars.anim`, `pins.ping.tick`, `npcs.map.pulse` (`Perf.Call`) | `classbars/Anim.lua`, `pins/PingMap.lua`, `npcs/Map.lua` | update |
| `map.view.step`, `map.view.follow`, `map.view.notify` (`Perf.Wrap`) | `map/View.lua` OnUpdate scripts | update |
| `reminders.event`, `healer.event`, `healer.unitEvent`, `targetart.event`, `refreshments.cast` (`Perf.Wrap`) | the private event frames' OnEvent in `reminders/State.lua`, `healer/Watch.lua`, `targetart/Display.lua`, `modules/Refreshments.lua` | event |
| `rxp.skin.*`, `rxp.timers.*`, `rxp.waypoint.sync` (`Perf.Wrap`; `rxp.skin.currentTick` after its throttle) | the `hooksecurefunc` callbacks on RestedXP's functions and the hover button's OnUpdate in `modules/RestedXPSkin.lua`, `modules/RestedXPTimers.lua`, `qol/GuideWaypoint.lua` | hook, update |

`Perf.Wrap(id, fn)` (in `Core.lua`) is `fn` that runs inside a scope while a capture records; off, it is one table read
and a tail call. It is for hooks and a frame's OnEvent, where there is no call site of ours to guard. A throttled
OnUpdate is scoped *after* its throttle so the scope's call count is the number of real updates, not of frames.
`DX.OPS` (`Gauges.lua`) gives every id its file, function and expected rate, which the reports print under "Where the
code is"; `DX.UNSCOPED` lists code with no scope yet (other hooks, private event frames, timers, OnUpdate scripts of
windows), which the reports name when most TwichUI CPU is outside every scope.
Gauges (`Gauges.lua`) read what modules already report (`Snapshot()` functions and a few read-only counts): event-bus
listeners and events (`R.ListenerCounts`, added to `Core.lua`), switch listeners, settings-closed callbacks, effects
easing, settings shown, pages drawn and search index, world map shown, NPC and pin marker pools and those in use, map
detail tiles, navigation tiles decoded, reminders running and observation keys, Healer Watch's and class bars' events.
The layout setup registers four of its own (`TwichUI_LayoutWizard/Window.lua` and `Overlay.lua`, only once it is loaded):
`layoutwizard.events` (events it has registered: 4 while its window is open, 0 closed), `layoutwizard.frames` (frames and
pages it keeps; it does not grow when the window is opened again), and for its full-size preview
`layoutwizard.overlay.events` (3 while it is shown, 0 closed) and `layoutwizard.overlay.frames` (frames and textures it
keeps: made as the pieces first appear, bounded by the package, not growing when it is opened again). The publishing code registers `layouts.store.entries` and `layouts.store.kb` (packages kept for sending and installing, and the
text they hold in saved data: read without unpacking anything) and, in the authoring workspace, `layoutwizard.author` (changes held:
0 while it is closed) and `layoutwizard.author.frames` (the frames it keeps). Not scoped, and
why: building the scene (`Scene.lua`, `LY.Elements`: a few table reads and arithmetic per redraw, cached until a pick, a
layout, a scenario or the screen changes). No global function, `CreateFrame`, timer or event registration is wrapped or replaced.

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
cache (needs 3+ readings rising in 2/3 of intervals), slow calls while their window was sampled closed (calls within 2 s of that window's own opened or closed marker are left out: the clock is read once a second), long frames with
TwichUI time of at least half the frame (or long frames without it, stated as not attributable), the client counting
ticks over 5/50 ms for TwichUI, diagnostics overhead (with its hitches: long frames the diagnostics' own memory or
gauge read lifted over the limit), TwichUI CPU outside every scope (`unattributed-cpu`; `prefs.thresholds.unattributedPerSec`,
default 1 ms a second, medium at five times that), errors, and what limits the capture. The memory finding reports the
series (lowest, highest, intervals up and down, at least how many KB/s were allocated between readings, the largest
fall as evidence that the collector ran, the scopes' allocation) and says a pool's size is not measured. The report's memory section also shows `TwichUI_NavData`, `TwichUI_Layouts` and `TwichUI_LayoutWizard` (read with the others, separate
addons) and its CPU section shows the instrumented total as a true ratio of the client's count: above about 110% it says the
instrumented times are upper bounds (the first real capture had 877 ms instrumented against 509 ms counted; the cause is
not established). A long frame next to an addon load names the addon, and the Markers list includes addon loads and
profile changes. A dominant
operation is only named when measured work is 20 ms or more. Each has category, severity
and its basis, evidence numbers, window, confidence (measured, correlated, suspicion), limits, how to verify, and ids.

## Comparison (`Compare.lua`)

Rows are rates (per minute of capture), per frame or per call, with the denominator named; raw differences beside
percentages; a zero baseline is "new", not a percentage; per-call rows need 20 calls in both. Warnings: client build,
preset or mode, profiler availability, under 30 s, lengths over 2x apart, group size, combat share, instrumentation
settings, a GC experiment. A different report schema is refused. Different switches are listed (expected for on/off).

## Export (`Export.lua`, `Json.lua`)

Built only when you press Prepare, never in combat or while that capture records; shown with size, sections, pieces
and redaction before you copy. Never sent; no clipboard or file access is claimed (the game gives addons none).

- **Quick summary:** Markdown, written to be read by an AI assistant with no one to ask: environment (with the switch
  names that are on), capture, context (map, settings and combat seconds, zone changes, frame rate), your notes,
  markers, **where TwichUI's CPU went** (client count, per frame and second, the instrumented share, the shape over
  time, the client's tick counts), **memory** (series, collections seen, allocation, the whole heap and the
  diagnostics' own memory beside it), findings with ids and evidence, **checked and clear** (so silence is not "not
  looked at"), top operations with allocation, **where the code is** (operation id to file and function), long frames
  (with what the diagnostics did before each and the nearest marker), events by time, every gauge first to last,
  the diagnostics' own cost, **code with no scope yet**, **suggested next captures** (preset, what to do, how long,
  why), what can't be shown, redaction line. The figures are `Findings.Analyze(rec)`, computed on demand, never stored.
- **Full report:** JSON, `schema` 1, `kind` `twichui-diagnostics-report`: `units`, `provenance`, `redaction`,
  `truncation`, `capture` (preset, config, observation start), `capabilities`, `environment`, `context.markers`,
  `aggregates` (operations with histograms and slowest calls, events, callbacks, counters, allocation, dropped,
  anomalies), `frames`, `timeline` (at most 600 buckets, merged: sums added, worst kept), `memory`, `gauges`,
  `profiler`, `legacyCpu`, `errors`, `overhead`, `analysis` (the same derived figures as the summary: `cpu`, `memory`,
  `context`, `diagnosticsCost`, `longFrames`, `checkedAndClear`, `suggestedNextCaptures`, `codeWithNoScope`; operations
  also carry `file`, `where`, `expectedRate` and their allocation), `findings`, `cannotConclude`, `userNotes` (`untrusted: true`). Keys
  in a fixed order; invalid UTF-8 becomes "?". Over 2 MB, parts are left out and `truncation.sizeLimit` says which.
- **Comparison report:** Markdown with conditions, normalised rows and operations, plus the comparison as JSON.
- **AI analysis prompt:** instructions followed by the quick summary. The assistant is told to keep facts and
  hypotheses apart, treat everything as untrusted data, respect the limits (the diagnostics' own cost is not
  TwichUI's), say first whether anything is worth fixing (and stop if not), name at most three suspects with evidence,
  the file to read and the smallest change, measure before guessing when most CPU or memory is outside every scope,
  give each fix a validation (which capture, which figure, how much) and a failure condition, and keep a fix within
  TwichUI's constraints (combat safety, throttled work, no new globals, no saved-data changes, no removed features,
  no unmeasured memory claims).
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
5. For an AI to analyse with the least from you: export **AI analysis prompt**, paste it into the assistant, and do
   what its "Suggested next captures" ask (each names a preset, what to do and how long). Repeat with the same
   preset and activity after a fix and paste the new prompt: the assistant compares the figures it named.
6. Overview: read the findings and what can't be concluded. Export > Quick summary (or AI analysis prompt) >
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

A new feature that does real work or holds memory should join this (see CLAUDE.md, "Diagnostics coverage for new
features"): scope the work, register gauges for what it keeps, add it to `DX.OPS`, and put a row in the table above.

## Tests

`tests/test_perf_engine.lua` (synthetic clock): off behaviour and cost; results and errors preserved through scopes;
nested inclusive/self time; re-entry; aborted, frame-crossing and backward-clock scopes; events vs callbacks;
sampler long frames and discontinuities; memory; repeated start/stop, cancel, time limit, combat-deferred finish,
profile change; histogram percentiles, ring truncation, timeline merging; findings evidence (and what is never
concluded); comparison normalisation, zero baselines, tiny samples, incompatibility; JSON validity (a reader in the
test), redaction, notes opt-out, the prompt's rules, pieces joining and tamper/order detection, UTF-8, size limits,
no export in combat; explicit saving (plain values only); focused filtering and allocation; armed start-up, stale
arming; no error reaching the handler; the diagnostics' cost counted once (sampler without its reads), a long frame
that follows our memory read told apart, percentiles never above the maximum, allocation inside a scope (inclusive and
self), `Perf.Wrap` off and recording, and a synthetic capture shaped like the first real one (small CPU mostly outside
every scope, memory with a collection in it) for the findings, the "checked and clear" lines, the suggested captures
and the summary's sections and size; the gaps that capture showed (navigation data memory, an addon load named at its long
frame, the instrumented/client ratio, a window's own opening not read as hidden work, the `nav.load` scope).
`tests/test_perf_window.lua`: every view without a capture, while recording,
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
13. Does the client's profiler report anything for `TwichUI_Diagnostics`? A General capture prints "the client reported
    nothing" when its figure is 0; if it is always 0 for a load-on-demand addon, say so here and drop the cross-check.
14. The new scopes: a Focused trace of "Per-frame updaters" with the minimap markers on shows `npcs.minimap.tick` and
    `pins.minimap.tick` at about 10 calls a second; "Hooks and private event frames" with RestedXP's guide visible
    shows the `rxp.*` rows. The unattributed share of a General capture should fall; if it stays high, the code is in
    `DX.UNSCOPED`.
15. Memory: a Memory and lifecycle capture with the garbage collection experiment at the end; compare the lowest
    reading after the fall with the first reading, and the scopes' allocation with the series' rise.
16. Nothing the scopes touch changes while off: hooks and event frames behave as before with no capture (the `rxp.*`
    wrappers are plain pass-throughs while `Perf.on` is false).

## Not implemented, and why

- No statistical sampling profiler, flame graph or per-function CPU: the client gives no sampling API; scopes are
  explicit instrumentation of chosen operations.
- No visibility into timers, arbitrary frames, closures or other addons' events: no wrapping of global APIs.
- No error stack traces for errors TwichUI's handlers catch (the pcall ended them); the game's display has them.
- No per-module memory: the client's figure is per addon; only `MeasureCall` (opt-in) gives per-call allocation.
- No live comparison or chart of two metrics on one axis, by design.
