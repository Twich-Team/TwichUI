-- Explicit, session-only map support captures. No frame/timer/hook runs until Start.
-- Renderer taps are nil while stopped; exports never query player position or write saved data.
local R, DX = TwichUI, TwichUI.DiagnosticsKit
local MC = { SCHEMA = 1, MAX_EVENTS = 256, MAX_SNAPSHOTS = 24, MAX_FINDINGS = 32, MAX_BYTES = 98304 }
DX.MapCapture = MC
local Ring, J = DX.Ring, DX.Json
local recording, timer, serial, live, last, ownsPerf = false, nil, 0, nil, nil, false
local lastSnapshotAt, lastState, recentHosts, repeated = 0, nil, {}, {}
local KEYS = {
    wheel = { "notches", "fromZoom", "pendingZoom", "limitZoom" },
    ["animation-start"] = { "mode", "fromZoom", "pendingZoom" },
    ["animation-end"] = { "mode", "zoom" }, ["animation-stop"] = { "mode", "pendingZoom" },
    ["host-change"] = { "mapId", "zoom" }, viewport = { "width", "height" },
    ["npc-markers"] = { "eligible", "fading", "positioned", "hostMap", "contextMap" },
    ["cave-transition"] = { "phase", "id", "strength", "targetStrength" },
    ["texture-failure"] = { "fileId", "reason" }, ["detail-budget"] = { "requested", "budget" },
    ["interior-budget"] = { "requested", "budget" },
    ["boundary-clamp"] = { "zoom" }, ["anchor-error"] = { "errorPixels", "zoom" },
    ["motion-rejected"] = { "reason" }, ["render-state"] = { "state" },
    ["map-error"] = {},
}
local PRIVATE = { name = true, player = true, character = true, guild = true, account = true,
    sender = true, text = true, message = true, stack = true, owner = true }
local function Clock()
    if not GetTime then return 0 end
    local ok, n = pcall(GetTime)
    return ok and DX.Num(n) or 0
end
local function Relative()
    local at = math.max(live.lastRelative or 0, Clock() - live.started)
    live.lastRelative = at
    return at
end
local function Copy(v, depth)
    if DX.Secret(v) then return "unavailable: secret" end
    local kind = type(v)
    if kind == "number" then return DX.Num(v) or "unavailable: invalid number" end
    if kind == "boolean" then return v end
    if kind == "string" then return v:sub(1, 180) end
    if kind ~= "table" then return "unavailable" end
    if depth > 7 then return "truncated: depth" end
    local out, n = {}, 0
    for k, x in pairs(v) do
        if (type(k) == "string" or type(k) == "number") and not PRIVATE[k] then
            n = n + 1
            if n <= 128 then out[k] = Copy(x, depth + 1) else out.truncated = true break end
        end
    end
    return out
end
local function Read(module, method, coordinates)
    local m = R[module]
    if not m or type(m[method]) ~= "function" then return { available = false, reason = "module or API unavailable" } end
    local ok, value = pcall(m[method], coordinates)
    if not ok or type(value) ~= "table" then return { available = false, reason = "snapshot unavailable", readFailed = true } end
    if module == "PinsMap" or module == "GuildLoc" or module == "NpcMap" then
        local counts = {}
        for _, key in ipairs({ "drawn", "mapDrawn", "pool", "mapPool", "unplaced", "layouts", "records", "mapLayouts", "installed", "open", "refused" }) do
            if type(value[key]) == "number" or type(value[key]) == "boolean" then counts[key] = value[key] end
        end
        value = counts
    end
    local out = Copy(value, 1); out.available = true
    return out
end
local function Environment()
    local env = { addonVersion = DX.Metadata(R.ADDON or "!!!TwichUI", "Version") or "unavailable",
        buildIdentity = DX.Metadata(R.ADDON or "!!!TwichUI", "X-Build") or "unavailable: release metadata has no build hash",
        clientVersion = "unavailable", clientBuild = "unavailable", interface = "unavailable" }
    if GetBuildInfo then
        local ok, v, b, _, toc = pcall(GetBuildInfo)
        if ok then env.clientVersion, env.clientBuild, env.interface = Copy(v, 1), Copy(b, 1), Copy(toc, 1) end
    end
    return env
end
function MC.Snapshot(coordinates)
    local prefs = R.MapExplorePrefs
    local detailEnabled = "unavailable"
    if prefs and prefs.Get then local ok, v = pcall(prefs.Get, "detail"); if ok then detailEnabled = v == true end end
    local enabled = false
    if R.Enabled then local ok, v = pcall(R.Enabled, R, "mapExplore"); enabled = ok and v == true end
    return { enabled = enabled, view = Read("MapView", "Diagnostic", coordinates),
        artwork = Read("MapArt", "Diagnostic"), terrain = Read("MapDetail", "Diagnostic", coordinates),
        interiors = Read("MapPictures", "Diagnostic", coordinates), cave = Read("MapCaves", "Snapshot", coordinates),
        dungeon = Read("MapDungeonView", "Snapshot"), markers = {
            personal = Read("PinsMap", "Snapshot"), places = Read("MapPlaces", "Snapshot"),
            guild = Read("GuildLoc", "Snapshot"), npcs = Read("NpcMap", "Snapshot"),
            coordinateSource = "existing native host / MapWorld conversions; no player coordinate query" },
        detailEnabled = detailEnabled,
        provenance = "production snapshots; map/View.lua, Art.lua, Detail.lua, Pictures.lua, Caves.lua" }
end
local function New(coordinates, description)
    serial = serial + 1
    local wall = time and time() or 0
    return { id = ("MAP1-%s-%d"):format(tostring(wall), serial), started = Clock(),
        environment = Environment(), coordinates = coordinates == true,
        description = DX.UserText(description, 240) or "Map issue captured; no description supplied.",
        events = Ring.New(MC.MAX_EVENTS), snapshots = Ring.New(MC.MAX_SNAPSHOTS),
        findings = Ring.New(MC.MAX_FINDINGS), incidents = Ring.New(8), totals = {}, coalesced = 0 }
end
local function Finding(code, severity, confidence, evidence)
    local k = "finding:" .. code
    if repeated[k] then repeated[k].count = repeated[k].count + 1 return end
    local f = { code = code, severity = severity, confidence = confidence, atSeconds = Relative(), count = 1, evidence = evidence }
    repeated[k] = f; Ring.Push(live.findings, f)
    local incident = { atSeconds = f.atSeconds, code = code, sequence = live.sequence or 0, before = {}, after = {},
        state = MC.Snapshot(live.coordinates) }
    for i = math.max(1, live.events.n - 5), live.events.n do incident.before[#incident.before + 1] = Ring.Get(live.events, i) end
    Ring.Push(live.incidents, incident)
end
function MC.Event(kind, ...)
    if not recording or not KEYS[kind] then return end
    local now = Relative()
    live.totals[kind] = (live.totals[kind] or 0) + 1
    -- Keep frequent identical budget/rejection states from crowding out navigation history.
    if (kind == "detail-budget" or kind == "interior-budget" or kind == "motion-rejected") and repeated[kind]
        and now - repeated[kind] < 1 then live.coalesced = live.coalesced + 1 return end
    repeated[kind] = now
    local e = { atSeconds = now, kind = kind, sequence = (live.sequence or 0) + 1 }
    live.sequence = e.sequence
    for i, key in ipairs(KEYS[kind]) do
        local v = select(i, ...)
        if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then e[key] = Copy(v, 1) end
    end
    Ring.Push(live.events, e)
    for _, incident in ipairs(Ring.List(live.incidents)) do
        if e.sequence > incident.sequence and #incident.after < 6 then incident.after[#incident.after + 1] = e end
    end
    if kind == "anchor-error" then Finding("cursor-anchor-displaced", "high", "observed", { pixels = e.errorPixels, tolerancePixels = 1, boundaryClamped = false })
    elseif kind == "texture-failure" then
        Finding("texture-load-failure", "medium", "observed", { fileId = e.fileId or false, reason = e.reason or "unavailable" })
    elseif kind == "detail-budget" then
        Finding("terrain-budget-fallback", "low", "observed", { requested = e.requested, budget = e.budget })
    elseif kind == "interior-budget" then
        Finding("interior-budget-exhausted", "medium", "observed", { requested = e.requested, budget = e.budget })
    elseif kind == "map-error" then
        Finding("map-handler-error", "high", "observed", { source = "TwichUI map handler; raw error text excluded for privacy" })
    elseif kind == "wheel" and DX.Num(e.notches) and DX.Num(e.fromZoom) and DX.Num(e.pendingZoom)
        and e.notches > 0 and e.pendingZoom + 1e-7 < e.fromZoom then
        Finding("inward-zoom-reversed", "high", "observed", { fromZoom = e.fromZoom, pendingZoom = e.pendingZoom, notches = e.notches })
    elseif kind == "host-change" then
        recentHosts[#recentHosts + 1] = { at = now, mapId = e.mapId }
        if #recentHosts > 4 then table.remove(recentHosts, 1) end
        if #recentHosts == 4 and now - recentHosts[1].at < 3
            and recentHosts[1].mapId == recentHosts[3].mapId and recentHosts[2].mapId == recentHosts[4].mapId then
            Finding("context-oscillation", "medium", "heuristic", { changes = 4, seconds = now - recentHosts[1].at,
                qualification = "May be intentional navigation; inspect wheel and host events." })
        end
    end
end
local function StateKey(s)
    local v, t, i, c, a = s.view, s.terrain, s.interiors, s.cave, s.artwork
    local layer = {}
    for _, l in ipairs(a.layers or {}) do layer[#layer + 1] = l.kind .. ":" .. math.floor((l.alpha or 0) * 4) end
    for _, l in ipairs(a.zoneLayers or {}) do layer[#layer + 1] = "zone:" .. l.mapId end
    for _, l in ipairs(a.cityLayers or {}) do layer[#layer + 1] = "city:" .. l.mapId end
    return table.concat({ tostring(v.nativeMap), tostring(v.ready), tostring(t.showing), tostring(i.active), tostring(c.surfaced), table.concat(layer, ",") }, "/")
end
local function Track(event)
    if not recording then return end
    local now = Relative()
    if event == "view" and now - lastSnapshotAt < 0.5 then return end
    local s = MC.Snapshot(live.coordinates)
    local key = StateKey(s)
    if key ~= lastState then MC.Event("render-state", key); lastState = key end
    if event ~= "view" or now - lastSnapshotAt >= 1 then
        Ring.Push(live.snapshots, { atSeconds = now, event = event, state = s }); lastSnapshotAt = now
    end
    if s.view.readFailed then Finding("view-unavailable", "medium", "observed", { source = "MapView.Diagnostic failed" }) end
    local v, t = s.view, s.terrain
    if v.ready and DX.Num(v.zoom) and v.zoom >= 36 and t.available and not t.showing
        and not s.cave.surfaced and (s.interiors.active or 0) == 0 and (t.requested or 0) == 0 then
        Finding("close-detail-absent", "low", "heuristic", { zoom = v.zoom,
            qualification = "May be ocean, unsupported artwork or detail disabled; not proof of a rendering failure." })
    end
end
if R.MapView and R.MapView.Subscribe then R.MapView.Subscribe(Track) end
function MC.Recording() return recording end
function MC.Current() return live or last end
function MC.Status()
    local rec = live or last
    return { recording = recording, durationSeconds = rec and (recording and Relative() or rec.durationSeconds) or 0,
        id = rec and rec.id or false, events = rec and rec.events.n or 0, limitSeconds = rec and rec.limitSeconds or 0 }
end
local function Performance()
    local out = { source = "existing R.Perf / DiagnosticsKit.Instrument; milliseconds", available = false,
        allocationQualification = "allocKB sums positive inclusive Lua heap deltas across calls; nested scopes overlap. It is not unique allocation or retained memory." }
    local I = DX.Instrument
    if I and I.Live and live.perfCaptureId and R.Perf.captureID == live.perfCaptureId then
        local list = I.Live()
        out.operations = {}
        for _, op in ipairs(list) do
            if (op.id:match("^map%.") and not op.id:match("^map%.support%.") or op.id:match("^npcs%.map%.")) and #out.operations < 24 then
                out.operations[#out.operations + 1] = Copy(op, 1)
                if op.max and op.max > 16 then Finding("map-update-cost", "medium", "observed",
                    { scope = op.id, maximumMilliseconds = op.max, qualification = "Instrumented CPU, not GPU or whole-frame attribution." }) end
            end
        end
        table.sort(out.operations, function(a, b) return a.id < b.id end)
        out.available = #out.operations > 0
    end
    if not out.available then out.reason = "No map scope timing available; capture may have started in combat or the map did not move." end
    return out
end
function MC.Stop(reason)
    if not recording then return false end
    Track("stop")
    live.performance = Performance()
    recording, R.MapTrace = false, nil
    if timer then if timer.Cancel then pcall(timer.Cancel, timer) end; timer = nil end
    live.durationSeconds, live.stopReason = Relative(), reason or "manual"
    live.final = MC.Snapshot(live.coordinates)
    local perfCaptureId = live.perfCaptureId
    last, live = live, nil
    if ownsPerf and R.Perf.captureID == perfCaptureId and DX.Recording and DX.Recording() then DX.Stop("manual") end
    ownsPerf = false
    DX.Changed("map-stop")
    return true
end
function MC.Start(opts)
    if recording then return false, "already-recording" end
    opts = opts or {}
    local seconds = DX.Num(opts.seconds) or 90
    seconds = math.max(15, math.min(180, seconds))
    live, last = New(opts.coordinates, opts.description), nil
    live.limitSeconds, lastSnapshotAt, lastState, recentHosts, repeated = seconds, -1, nil, {}, {}
    recording, R.MapTrace = true, MC.Event
    ownsPerf = false
    if not DX.InCombat() and DX.Start and DX.Recording and not DX.Recording() then
        local ok, started = pcall(DX.Start, "map", { minutes = seconds / 60, mapIds = false })
        ownsPerf = ok and started == true
    end
    live.perfCaptureId = R.Perf.on and R.Perf.captureID or false
    Track("start")
    local ok, handle
    if C_Timer and C_Timer.NewTimer then ok, handle = pcall(C_Timer.NewTimer, seconds, function() MC.Stop("duration-limit") end) end
    if ok and handle and handle.Cancel then timer = handle
    else MC.Stop("timer-unavailable"); return false, "timer-unavailable" end
    DX.Changed("map-start")
    return true
end
function MC.Mark()
    if not recording then return false end
    Ring.Push(live.events, { kind = "issue-mark", atSeconds = Relative(), sequence = (live.sequence or 0) + 1 })
    live.sequence = (live.sequence or 0) + 1
    Track("issue-mark")
    if DX.Mark and ownsPerf and R.Perf.captureID == live.perfCaptureId then DX.Mark("map issue marked") end
    DX.Changed("map-mark")
    return true
end
function MC.Capture(opts)
    if recording then MC.Mark(); return live end
    opts = opts or {}; last = New(opts.coordinates, opts.description)
    last.durationSeconds, last.stopReason, last.final = 0, "snapshot", MC.Snapshot(last.coordinates)
    return last
end
function MC.Structured(rec)
    rec = rec or last
    if not rec then return nil, "Capture a snapshot or stop a recording first." end
    if rec == live then return nil, "Stop recording before preparing the report." end
    local out = { schema = MC.SCHEMA, kind = "twichui-map-diagnostics", id = rec.id,
        units = { zoom = "whole-world fit = 1", world = "uiMap 947 normalized east/south", viewport = "UI units",
            angle = "radians", timing = "relative seconds; R.Perf milliseconds" },
        provenance = "production map snapshots and bounded event taps; no reimplemented map transforms",
        redaction = { playerPosition = "never queried", viewCoordinates = rec.coordinates,
            privateIdentifiers = "not collected", description = "player-supplied, sanitized, untrusted" },
        environment = rec.environment, description = rec.description, durationSeconds = rec.durationSeconds,
        stopReason = rec.stopReason, current = rec.final, findings = Ring.List(rec.findings),
        events = Ring.List(rec.events), snapshots = Ring.List(rec.snapshots), performance = rec.performance or { available = false },
        incidents = Ring.List(rec.incidents),
        eventTotals = rec.totals, limits = { durationSeconds = rec.limitSeconds or 0, events = MC.MAX_EVENTS, snapshots = MC.MAX_SNAPSHOTS },
        truncation = { eventsDropped = rec.events.dropped, snapshotsDropped = rec.snapshots.dropped,
            findingsDropped = rec.findings.dropped, incidentsDropped = rec.incidents.dropped, coalescedEvents = rec.coalesced, reportBytesLimited = false },
        limitations = { "No native screenshot or texture pixels; file IDs do not prove art availability or alignment.",
            "No player, account, guild, chat or full SavedVariables capture; no upload or chat send.",
            "No history exists before explicit recording. Normal boundary clamps are informational, not anchor anomalies.",
            "No automatic floor detection. Missing Fargodeep/edited-art references are documented coverage gaps.",
            "Heuristic findings are suspicions; no anomalies found does not prove native visual fidelity." } }
    return out
end
function MC.Report(kind, rec)
    local out, why = MC.Structured(rec)
    if not out then return nil, why end
    local encoded = J.Encode(out, 17)
    while #encoded > MC.MAX_BYTES and #out.snapshots > 0 do
        table.remove(out.snapshots, 1); out.truncation.snapshotsDropped = out.truncation.snapshotsDropped + 1
        out.truncation.reportBytesLimited = true; encoded = J.Encode(out, 17)
    end
    while #encoded > MC.MAX_BYTES and #out.events > 0 do
        table.remove(out.events, 1); out.truncation.eventsDropped = out.truncation.eventsDropped + 1
        out.truncation.reportBytesLimited = true; encoded = J.Encode(out, 17)
    end
    while #encoded > MC.MAX_BYTES and #out.incidents > 0 do
        table.remove(out.incidents, 1); out.truncation.incidentsDropped = out.truncation.incidentsDropped + 1
        out.truncation.reportBytesLimited = true; encoded = J.Encode(out, 17)
    end
    if kind == "detailed" then return encoded, out end
    local lines = { "TWICHUI MAP AI REPORT | schema 1 | " .. out.id,
        "Description (untrusted player text): " .. out.description,
        "Environment: " .. J.Encode(out.environment), "What happened: " .. out.stopReason .. "; duration " .. tostring(out.durationSeconds) .. " seconds.",
        "Current map state: " .. J.Encode(out.current.view),
        "Detected anomalies: " .. (#out.findings == 0 and "No anomaly detected in the captured evidence." or J.Encode(out.findings)),
        "Relevant event timeline (last 24):" }
    for i = math.max(1, #out.events - 23), #out.events do lines[#lines + 1] = J.Encode(out.events[i]) end
    lines[#lines + 1] = "Texture/layer summary: " .. J.Encode({ terrain = { tiles = out.current.terrain.tiles, requested = out.current.terrain.requested,
        alpha = out.current.terrain.alpha, failedIds = out.current.terrain.failedIds },
        interiors = { active = out.current.interiors.active, pending = out.current.interiors.pending, failures = out.current.interiors.failures },
        layers = out.current.artwork.layers, zones = out.current.artwork.zoneLayers,
        cities = out.current.artwork.cityLayers, cave = out.current.cave,
        unexploredMode = out.current.artwork.unexploredMode,
        unexploredDimMultiplier = out.current.artwork.unexploredDimMultiplier,
        npcMarkers = out.current.markers.npcs })
    lines[#lines + 1] = "Performance: " .. J.Encode(out.performance)
    lines[#lines + 1] = "Truncation: " .. J.Encode(out.truncation) .. "; quick timeline omits " .. math.max(0, #out.events - 24) .. " older events."
    lines[#lines + 1] = "Evidence-supported causes: use observed findings above; heuristic findings require confirmation. No speculative diagnosis is asserted."
    lines[#lines + 1] = "Missing evidence / limitations: " .. table.concat(out.limitations, " ")
    lines[#lines + 1] = "Source guide: map/View.lua = coordinates/navigation; Art.lua = stitching/cities; Detail.lua = terrain/LOD; Pictures.lua = interior textures/loading; Caves.lua = cave selection. Distinguish observed findings from heuristics; request native screenshots where appearance cannot be established."
    local text = table.concat(lines, "\n\n")
    if #text > 12288 then text = text:sub(1, 12100) .. "\nQUICK REPORT TRUNCATED; use Detailed Report for complete bounded evidence." end
    return text, out
end
function MC.Prepare(kind)
    if recording then MC.Stop("prepare-report") end
    if not last then MC.Capture() end
    local text, out = MC.Report(kind)
    if not text then return nil, out end
    local pieces = J.Pieces(text, 12000, "MAP " .. out.id .. " " .. (kind or "quick"))
    return { text = text, pieces = pieces, report = out, kind = kind or "quick" }
end
if R.Perf then
    MC.Snapshot = R.Perf.Wrap("map.support.snapshot", MC.Snapshot)
    MC.Report = R.Perf.Wrap("map.support.export", MC.Report)
end
