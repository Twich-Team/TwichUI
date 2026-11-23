return function(t)
  local c, R, MV = t.c, t.R, t.MV
  local function Load(path)
    local f = assert(loadfile(REPO .. path)); setfenv(f, c); f("!!!TwichUI", {})
  end
  Load("TwichUI_Diagnostics/Base.lua"); Load("TwichUI_Diagnostics/Json.lua")
  local DX = R.DiagnosticsKit
  -- Capture ownership is tested without replacing a currently recording performance session.
  local perfStarts, perfStops, owned = 0, 0, false
  DX.Start = function() perfStarts = perfStarts + 1; owned = true; R.Perf.on = true; R.Perf.captureID = R.Perf.captureID + 1; return true end
  DX.Stop = function() perfStops = perfStops + 1; owned = false; R.Perf.on = false end
  DX.Recording = function() return owned end
  DX.Instrument = { Live = function() return { { id = "map.view.notify", calls = 4, total = 2, max = 0.8 } } end }
  Load("TwichUI_Diagnostics/MapCapture.lua")
  local M, J = DX.MapCapture, DX.Json
  local precise = 0.1234567890123456
  assert(tonumber(J.Encode(precise, 17)) == precise and J.Encode(precise) == J.Encode(precise, 0/0),
    "optional replay precision preserves coordinates without changing compact exports")
  local requests, deadline = 0, nil
  c.C_Timer.NewTimer = function(seconds, fn)
    requests = requests + 1; deadline = fn
    return { Cancel = function() deadline = nil end }
  end
  local record = M.Capture()
  local quick = assert(M.Report("quick"))
  assert(quick:find("No anomaly detected", 1, true) and quick:find("withheld", 1, true), "honest compact report, geometry private by default")
  local json, report = M.Report("detailed")
  assert(json == M.Report("detailed"), "deterministic same-capture JSON")
  assert(report.schema == 1 and report.kind == "twichui-map-diagnostics" and report.current.view.available, "self-contained schema and disabled-map state")
  assert(report.redaction.playerPosition == "never queried" and not json:find("Rich Hale", 1, true), "no player identifiers")
  assert(report.current.view.nativeMap ~= nil and report.current.view.viewportWidth ~= nil, "unavailable values explicit")
  assert(#quick < 12288 and #json <= M.MAX_BYTES, "bounded report size")
  assert(not R.MapTrace and not M.Recording() and requests == 0, "snapshot requires no background work")
  local startClock = CLOCK
  assert(M.Start({ seconds = 30, coordinates = true, description = "terrain faded out" }))
  assert(not M.Start() and M.Recording(), "duplicate start refused")
  t.openMap(1429); R.MapExplorePrefs.Set("smooth", true)
  t.pointAt(t.WorldOf(1429, 0.5, 0.5)); t.wheel(2); t.Run(0.3)
  M.Mark()
  M.Event("anchor-error", 8, 25)
  M.Event("texture-failure", 123456, "load-timeout")
  M.Event("interior-budget", 300, 256)
  for i = 1, 4 do M.Event("host-change", i % 2 == 0 and 1429 or 1436, 30) end
  for i = 1, 900 do M.Event("wheel", 1, 20, 25, 48) end
  t.closeMap(); t.openMap(1436)
  assert(M.Stop("manual") and not R.MapTrace and not M.Recording(), "stop releases event taps")
  assert(perfStarts == 1 and perfStops == 1, "existing performance engine ownership is balanced")
  local detailed, data = M.Report("detailed")
  assert(data.current.view.center and #data.events <= 256 and data.truncation.eventsDropped > 0, "bounded history and optional geometry")
  local flags = {}; for _, f in ipairs(data.findings) do flags[f.code] = f end
  assert(flags["cursor-anchor-displaced"].confidence == "observed" and flags["context-oscillation"].confidence == "heuristic", "findings distinguish evidence from suspicion")
  assert(flags["interior-budget-exhausted"].evidence.requested == 300, "interior cap evidence retained")
  assert(#data.incidents > 0 and #data.incidents[1].before > 0 and #data.incidents[1].after > 0, "anomaly context survives event ring eviction")
  local prev = -1
  for _, e in ipairs(data.events) do assert(e.atSeconds >= prev, "monotonic event timestamps"); prev = e.atSeconds end
  local built = M.Prepare("detailed")
  assert(#built.pieces >= 2, "long report chunks")
  local chunks = {}; for i, p in ipairs(built.pieces) do assert(p.index == i and p.count == #built.pieces); chunks[i] = p.text end
  assert(J.Join(chunks) == built.text, "numbered chunks reconstruct report exactly")
  local before = built.text
  t.SetCombat(true)
  assert(M.Start({ seconds = 15 }))
  assert(perfStarts == 1, "combat capture does not start protected native profiling")
  assert(not MV.ZoomBy(1), "normal combat navigation suspension retained")
  M.Stop(); t.SetCombat(false)
  assert(not R.MapTrace and perfStops == 1, "combat capture does not stop someone else's profiler")
  assert(M.Start({ seconds = 15 })); local expire = deadline; expire()
  assert(not M.Recording() and M.Current().stopReason == "duration-limit", "duration deadline stops cleanly")
  local oldMap, oldBuild, oldTime = R.MapView, c.GetBuildInfo, c.GetTime
  R.MapView, c.GetBuildInfo, c.GetTime = nil, nil, function() return 0/0 end
  M.Capture(); local _, missing = M.Report("detailed")
  assert(not missing.current.view.available and missing.environment.clientBuild == "unavailable", "missing APIs explicit")
  R.MapView, c.GetBuildInfo, c.GetTime = oldMap, oldBuild, oldTime
  local timerApi = c.C_Timer.NewTimer
  c.C_Timer.NewTimer = nil
  assert(not M.Start() and not M.Recording() and not R.MapTrace, "missing timer leaves no recording or hooks")
  c.C_Timer.NewTimer = timerApi
  assert(M.Start({ seconds = 9999 }) and M.Status().limitSeconds == 180, "duration limit bounded")
  local stoppedBeforeReplacement = perfStops
  R.Perf.captureID = R.Perf.captureID + 1
  M.Stop()
  assert(perfStops == stoppedBeforeReplacement, "stopping map recording preserves a replacement performance session")
  DX.Stop()
  -- Plain UI uses real palette primitives, not a second designer.
  Load("!!!TwichUI/Look.lua"); Load("TwichUI_Diagnostics/MapWindow.lua")
  DX.OpenMap()
  local W = DX.MapWindow
  assert(W.frame and W.frame:IsShown(), "dedicated diagnostics opens")
  W.Prepare("quick"); local first = W.edit:GetText(); W.Select()
  assert(W.edit:GetText() == first, "reselection does not rebuild export")
  W.frame:Hide()
  assert(not W.frame:GetScript("OnUpdate"), "closed diagnostics UI has no updater")
  if MAP_DIAGNOSTIC_JSON_PATH then
    report.id = "MAP1-synthetic-example-1"
    report.synthetic = true
    local f = assert(io.open(MAP_DIAGNOSTIC_JSON_PATH, "w")); f:write(J.Encode(report)); f:close()
  end
  print("MAP DIAGNOSTICS PASSED: schema, deterministic export, ring bounds, chunk join, combat, lifecycle, anomaly evidence, UI")
end
