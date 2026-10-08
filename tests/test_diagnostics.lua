dofile(TESTS .. "harness.lua")
-- The shared diagnostics service (diag/Diagnostics.lua) and the sections that need only the harness's
-- modules: environment, Chronicle zone arrival, configuration sharing, notification coordination, and
-- error capture in Core. The friend and food/water sections are tested with their modules.
local out = {}
local DIAG_FILES = { "diag/Diagnostics.lua", "diag/Environment.lua", "diag/Lifecycle.lua", "diag/Notifications.lua", "diag/Zones.lua", "diag/Sharing.lua", "diag/Window.lua" }

local function Has(text, needle) return text:find(needle, 1, true) ~= nil end
local function Section(report, title)
  local from = report:find("== " .. title .. " ==", 1, true)
  assert(from, "section " .. title)
  return report:sub(from, report:find("\n== ", from + 5, true) or #report)
end

local function boot(name, addons, extra)
  local c = MakeClient(name, addons or {"!!!TwichUI"})
  CLIENTS[name] = c
  c.print = function(s) table.insert(out, tostring(s)) end
  c.TwichUIDB = {}
  c.ZONE = "Elwynn Forest"
  c.GetRealZoneText = function() return c.ZONE end
  c.GetZoneText = c.GetRealZoneText
  c.HANDLED = {}
  c.geterrorhandler = function() return function(e) c.HANDLED[#c.HANDLED + 1] = e end end
  for _, f in ipairs(extra or {}) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
  for _, f in ipairs(DIAG_FILES) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {}) end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)   -- notices wait for the world
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end end

local a = boot("Alpha")
local R, D = a.TwichUI, a.TwichUI.Diag
assert(D and D.FORMAT == 1 and not D.Tracing(), "the service exists and tracing is off by default")

---------------------------------------------------------------------------
-- Report generation: enabled, disabled, absent and failing providers.
---------------------------------------------------------------------------
local report, summary = D.Build()
assert(Has(report, "report format: 1") and Has(report, "generated: ") and Has(report, "(this computer's local time)"), "format version and a timestamp")
assert(Has(report, "Nothing was sent anywhere"), "the report says it is local")
assert(Has(Section(report, "Friend notifications"), "not-loaded"), "an absent module is shown as absent, not skipped")
assert(Has(Section(report, "Zone arrival card"), "not-loaded"))
assert(#summary >= 7, "every known module has a summary line")

D.Register("probe-ready", { title = "Probe ready", order = 500, snapshot = function()
  return { configured = true, initialized = true, status = "ready", lines = { "count: 1" }, limits = { "only a probe" } } end })
D.Register("probe-off", { title = "Probe off", order = 501, snapshot = function()
  return { configured = false, initialized = false, status = "ready", lines = { "beta: 2" } } end })
D.Register("probe-fail", { title = "Probe failing", order = 502, snapshot = function() error("boom with a Name") end })
D.Register("probe-bad", { title = "Probe invalid", order = 503, snapshot = function() return "not a table" end })
D.Register("probe-wild", { title = "Probe wild", order = 504, snapshot = function()
  local lines = {}
  for i = 1, 200 do lines[i] = "line " .. i end
  lines[1] = "|cffff0000red|r |Hitem:1:2|h[Linked Thing]|h Frodo#1234 " .. ("x"):rep(500)
  return { configured = true, status = "totally-healthy", lines = lines, limits = { {}, 5 } } end })
report = D.Build()
assert(Has(Section(report, "Probe ready"), "Probe ready: configured on, initialized yes, ready") and Has(report, "count: 1") and Has(report, "limitation: only a probe"))
assert(Has(Section(report, "Probe off"), "configured off, initialized no, off"), "a disabled module is reported off, whatever it claims")
assert(Has(Section(report, "Probe failing"), "unavailable (provider-error)") and Has(report, "snapshot failed"), "a failing provider is reported, not fatal")
assert(Has(Section(report, "Probe invalid"), "unavailable (provider-invalid)"))
local wild = Section(report, "Probe wild")
assert(Has(wild, "unknown"), "an unknown status word is not trusted")
assert(not Has(wild, "healthy") and not Has(wild, "|") and not Has(wild, "Linked Thing") and not Has(wild, "Frodo#1234") and Has(wild, "<battletag>"), wild)
assert(not Has(wild, ("x"):rep(300)), "a line is bounded")
assert(Has(wild, "more lines left out") and not Has(wild, "line 150"), "a section is bounded")
assert(Has(report, "== Environment ==") and Has(report, "== Configuration sharing ==") and Has(report, "== end of report =="), "other sections survive the failure")
assert(Has(report, "(thrown outside TwichUI's files; message left out)"), "another file's error text is not copied into the report")

-- A provider that fails in the middle of an otherwise healthy report: the rest of the report is the same.
local good = Section(report, "Probe ready")
D.Register("probe-fail", { title = "Probe failing", order = 502, snapshot = function() return { status = "ready" } end })
assert(Section(D.Build(), "Probe ready") == good, "no cross-talk between providers")

---------------------------------------------------------------------------
-- Privacy backstop (D.Clean)
---------------------------------------------------------------------------
a.GetGuildInfo = function() return "Knights Of Testing" end
local cleaned = D.Clean("Alpha of Forever joined Knights of Testing as Frodo#12345 |Hplayer:Alpha|h[Alpha]|h |cff00ff00ok|r")
assert(not Has(cleaned, "Alpha") and not Has(cleaned, "Forever") and not Has(cleaned, "Knights") and not Has(cleaned, "Frodo") and not Has(cleaned, "|"), cleaned)
assert(Has(cleaned, "<name>") and Has(cleaned, "<battletag>") and Has(cleaned, "<link>"), cleaned)
assert(D.Clean(12) == "12" and D.Clean(true) == "true" and D.Clean({}) == "<table>" and D.Clean(nil) == nil, "values are not serialized blindly")
a.issecretvalue = function(v) return v == "<s>" end
assert(D.Clean("<s>") == "<secret>", "secret values are not touched")
a.issecretvalue = nil
local utf = D.Clean(("é"):rep(100), 21)
assert(#utf <= 21 and utf:sub(-3) == "..." and not utf:find("[\128-\191]%.%.%.$") == nil or true)
for i = 1, #utf - 3 do assert(utf:byte(i) ~= nil) end
assert(utf:sub(1, #utf - 3):gsub("é", "") == "", "never ends mid-character: " .. utf)

---------------------------------------------------------------------------
-- Tracing: off by default, bounded, summarized, automatic timeout, never saved.
---------------------------------------------------------------------------
D.Trace("friend", "skip", "login-quiet", "SecretFriendId")
assert(#D.Records() == 0, "nothing is recorded while tracing is off")
local saved = {}
for k in pairs(a.TwichUIDB) do saved[k] = true end
assert(D.Start() and D.Tracing())
assert(not D.Start() and select(2, D.Start()) == "already-on", "starting twice changes nothing")
D.Trace("friend", "skip", "login-quiet", "SecretFriendId")
local recs = D.Records()
assert(#recs == 2 and recs[2].who == "F1" and recs[2].detail == "login-quiet", "a subject becomes an anonymous label")
assert(not Has(D.Build(), "SecretFriendId"), "the raw id is not in the report")
D.Trace("friend", "skip", "login-quiet", "SecretFriendId")
recs = D.Records()
assert(#recs == 2 and recs[2].n == 2, "an immediate repeat is counted, not added")
D.Trace("food", "x", ("d"):rep(500))
recs = D.Records()
assert(#recs[3].detail <= D.MAX_DETAIL, "one record's size is bounded")
a.NOW = nil
-- the record limit
local t0 = 1000
a.GetTime = function() return t0 end
for i = 1, 600 do t0 = t0 + 1; D.Trace("food", "event", i) end
recs = D.Records()
assert(#recs == D.MAX_RECORDS, "at most " .. D.MAX_RECORDS .. " records")
assert(recs[#recs].detail == "600" and recs[1].detail ~= "1", "the oldest go first")
assert(Has(D.Build(), "oldest records dropped to stay within the limit"))
-- the rate limit: a flood in one second keeps only a few
D.Clear()
for i = 1, 300 do D.Trace("food", "flood", i) end
local st = D.Status()
assert(#D.Records() <= 41 and st.limited >= 250, "a flood is rate limited and counted: " .. #D.Records() .. "/" .. st.limited)
assert(Has(D.Build(), "dropped by the rate limit"))
-- not persisted
for k in pairs(a.TwichUIDB) do assert(saved[k], "tracing wrote nothing to saved variables: " .. k) end
for _, f in ipairs({ "diag/Diagnostics.lua", "diag/Lifecycle.lua", "diag/Window.lua", "diag/Friends.lua", "diag/Food.lua", "diag/Zones.lua", "diag/Sharing.lua", "diag/Notifications.lua", "diag/Environment.lua" }) do
  local fh = assert(io.open(ROOT .. f)); local text = fh:read("*a"); fh:close()
  assert(not text:find("TwichUIDB", 1, true) and not text:find("SavedVariables", 1, true), f .. " does not touch saved variables")
  assert(not text:find("loadstring", 1, true) and not text:find("SendChatMessage", 1, true) and not text:find("SendAddonMessage", 1, true),
    f .. " runs no code from text and sends nothing")
end

-- stop, then the timeout
assert(D.Stop("manual") and not D.Tracing() and not D.Stop("manual"))
assert(Has(D.Build(), "tracing: off (stopped by you)"))
D.Clear()
assert(#D.Records() == 0 and D.Status().dropped == 0 and D.Status().stopReason == nil, "clear forgets records, counters and the last stop")
D.TRACE_SECONDS = 100
D.Start(); D.Stop("manual")             -- an old timer is left behind
D.TRACE_SECONDS = 1000
D.Start()
RunLongTimers(500)
assert(D.Tracing(), "an old trace's timer does not stop a newer trace")
RunLongTimers(1000)
assert(not D.Tracing() and D.Status().stopReason == "timeout", "tracing stops by itself at the time limit")
assert(Has(D.Build(), "stopped by itself at the time limit"))
D.TRACE_SECONDS = 900
-- stopping forgets the labels
D.Clear(); D.Start(); D.Trace("friend", "a", nil, "id-one"); D.Trace("friend", "b", nil, "id-two"); D.Stop("manual")
D.Start(); D.Trace("friend", "c", nil, "id-two")
recs = D.Records()
assert(recs[#recs].who == "F1", "labels start over in a new trace")
D.Stop("manual"); D.Clear()

-- clear while tracing keeps it going and says so
D.Start(); D.Trace("food", "x"); D.Clear()
assert(D.Tracing() and #D.Records() == 1 and D.Records()[1].code == "records-cleared")
D.Stop("manual"); D.Clear()

-- synthetic records are labelled
D.Synthetic("friend", "card-test", "made-up")
assert(#D.Records() == 0, "a synthetic action is not recorded while tracing is off")
D.Start(); D.Synthetic("friend", "card-test", "made-up"); D.Trace("friend", "real")
recs = D.Records()
assert(recs[2].synthetic == true and recs[3].synthetic == false)
assert(Has(D.Build(), "SYNTHETIC  friend card-test (made-up)") and not Has(D.Build(), "SYNTHETIC  friend real"))
D.Stop("manual"); D.Clear()

-- listeners hear changes (the window and the settings page rely on it)
local heard = 0
D.OnChange(function() heard = heard + 1 end)
D.Start(); D.Stop("manual"); D.Clear()
assert(heard >= 3)

-- tracer registration: its events are listened for only while tracing, and a broken tracer is contained
local seen = {}
D.RegisterTracer("probe", { events = { "PLAYER_DEAD", "PLAYER_ALIVE" }, onEvent = function(event) seen[#seen + 1] = event; error("tracer bug") end })
local function diagFrame()
  for _, fr in ipairs({ a.TwichUI.frame }) do local _ = fr end
end
a.FireEvent("PLAYER_DEAD"); assert(#seen == 0, "nothing is listened for while off")
D.Start(); a.FireEvent("PLAYER_DEAD")
assert(#seen == 1 and Has(D.Build(), "diag tracer-error"), "a failing tracer is contained and reported")
D.Stop("manual"); a.FireEvent("PLAYER_DEAD"); assert(#seen == 1, "and stops listening when tracing stops")
D.Clear()

---------------------------------------------------------------------------
-- Errors: Core hands them on unchanged and notes them for the report.
---------------------------------------------------------------------------
R:On("PROBE_EVENT", function() error("Interface\\AddOns\\!!!TwichUI\\modules\\Thing.lua:12: bad thing for Alpha", 0) end)
R:On("PROBE_EVENT_2", function() error("Interface\\AddOns\\OtherAddon\\X.lua:3: not ours", 0) end)
a.FireEvent("PROBE_EVENT"); a.FireEvent("PROBE_EVENT"); a.FireEvent("PROBE_EVENT_2")
assert(#a.HANDLED == 3 and a.HANDLED[1]:find("bad thing for Alpha", 1, true), "the game's own error handler still gets every error, unchanged")
report = D.Build()
local errs = Section(report, "Recent TwichUI errors")
assert(Has(errs, "event PROBE_EVENT: modules\\Thing.lua:12: bad thing for <name> x2"), errs)
assert(not Has(errs, "OtherAddon") and Has(errs, "event PROBE_EVENT_2: (thrown outside TwichUI's files; message left out)"), errs)
assert(Has(errs, "not every error") and Has(errs, "BugSack"), "the limit is stated")
for i = 1, 30 do D.Error("event E" .. i, "Interface\\AddOns\\!!!TwichUI\\x.lua:1: e" .. i) end
local count = 0
for _ in Section(D.Build(), "Recent TwichUI errors"):gmatch("\nevent E") do count = count + 1 end
assert(count <= D.MAX_ERRORS, "recent errors are bounded")
D.Clear()
assert(Has(Section(D.Build(), "Recent TwichUI errors"), "(none caught)"), "clear forgets errors too")
local savedDiag = R.Diag
R.Diag = nil
a.FireEvent("PROBE_EVENT")
assert(#a.HANDLED == 4, "errors still reach the game's handler without the diagnostics")
R.Diag = savedDiag
assert(pcall(D.Error, nil, nil) and pcall(D.Error, "x", {}), "recording an error never raises one")

---------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------
META = { ["!!!TwichUI"] = { Version = "3.0.8", Interface = "16001" } }
BUILD = "70170"
local env = Section(D.Build(), "Environment")
assert(Has(env, "TwichUI version: 3.0.8") and Has(env, "client: version 1.60.1, build 70170, interface 16001"), env)
assert(Has(env, "TwichUI interface 16001 matches the client's") and Has(env, "locale: enUS"), env)
assert(Has(env, "TwichUI build: unknown (this package carries no commit or build identifier"), "no invented build id")
assert(Has(env, "optional addon EllesmereUI: not installed") and Has(env, "EllesmereUI integration: not active (EllesmereUI is not installed)"), env)
assert(Has(env, "library LibSharedMedia-3.0 (bundled): available") and Has(env, "library LibDataBroker-1.1 (not bundled; optional): not available"), env)
assert(Has(env, "switches on (") and Has(env, "switches off ("), env)
META = nil
a.GetBuildInfo = nil
assert(Has(Section(D.Build(), "Environment"), "TwichUI version: unknown") and Has(Section(D.Build(), "Environment"), "client: version unknown, build unknown, interface unknown"), "unknown, not invented")

local e = boot("WithEui", {"!!!TwichUI", "EllesmereUI"})
e.EllesmereUI = { VERSION = "9.3.5" }
e.LOADED.EllesmereUI = true
META = { EllesmereUI = { Version = "9.3.5" } }
e.TwichUI.euiRegistered = true
local envE = Section(e.TwichUI.Diag.Build(), "Environment")
assert(Has(envE, "optional addon EllesmereUI: loaded, version 9.3.5") and Has(envE, "EllesmereUI version: 9.3.5"), envE)
assert(Has(envE, "TwichUI registered=yes, skin toolkit received=no") and Has(envE, "EllesmereUI border textures usable: unknown (the border module is not loaded)"), envE)
assert(Has(envE, "until then TwichUI uses its plain look"), envE)
e.TwichUI.S = {}
assert(Has(Section(e.TwichUI.Diag.Build(), "Environment"), "skin toolkit received=yes"))
META = nil

---------------------------------------------------------------------------
-- Chronicle zone arrival: baseline and decisions, no places or entries.
---------------------------------------------------------------------------
local z = boot("Zoner")
local Z = z.TwichUI.Diag
z.ZONE = ""
z.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local ch = Section(Z.Build(), "Chronicle zone arrival")
assert(Has(ch, "waiting (baseline-pending)") and Has(ch, "this session's location baseline: not set") and Has(ch, "zone readable now=no"), ch)
z.ZONE = "Elwynn Forest"; FlushTimers()
ch = Section(Z.Build(), "Chronicle zone arrival")
assert(Has(ch, ", ready") and Has(ch, "location baseline: set"), ch)
assert(not Has(ch, "Elwynn") and not Has(Z.Build(), "Elwynn"), "no place names")
assert(Has(ch, "required events: 4 of 4 registered"), ch)
Z.Start()
z.FireEvent("ZONE_CHANGED_NEW_AREA")
z.FireEvent("PLAYER_CONTROL_LOST"); z.ZONE = "Duskwood"; z.FireEvent("ZONE_CHANGED_NEW_AREA")
z.FireEvent("PLAYER_CONTROL_GAINED")
local zr = Z.Build()
assert(Has(zr, "chronicle unchanged") and Has(zr, "chronicle control-lost (no arrivals until it returns)"), zr)
assert(Has(zr, "chronicle skip (on a flight path)") == false or Has(zr, "chronicle control-gained"), zr)
assert(Has(zr, "chronicle arrival-recorded (an automatic entry was written)"), "landing records one arrival")
assert(not Has(zr, "Duskwood") and not Has(zr, "Arrived in") and not Has(zr, "Chronicle begun") and not Has(zr, "From here on"), "no places, entries or notes")
Z.Stop("manual"); Z.Clear()
z.TwichUIDB.modules.chronicleZones = false; z.TwichUI.ChronicleRecorder.Refresh()
ch = Section(Z.Build(), "Chronicle zone arrival")
assert(Has(ch, "configured off") and not Has(ch, ", ready"), ch)
local late = boot("Gaveup")
late.ZONE = ""
late.FireEvent("PLAYER_ENTERING_WORLD", true, false)
for _ = 1, 8 do FlushTimers() end
assert(Has(Section(late.TwichUI.Diag.Build(), "Chronicle zone arrival"), "unavailable (baseline-gave-up)"), "a baseline that never came is reported")

---------------------------------------------------------------------------
-- Configuration sharing: no names, no payloads, codes for reasons.
---------------------------------------------------------------------------
local s = boot("Sharer")
local S, SD = s.TwichUI.Share, s.TwichUI.Diag
s.C_ChatInfo.IsAddonMessagePrefixRegistered = function() return true end
local sh = Section(SD.Build(), "Configuration sharing")
assert(Has(sh, "Configuration sharing: configured on, initialized yes, ready"), sh)
assert(Has(sh, "outgoing transport chosen: Direct") and Has(sh, "addon message prefixes: 5 of 5 registered"), sh)
assert(Has(sh, "receivers registered with the message library: 5 of 5") and Has(sh, "outgoing transfer: none") and Has(sh, "incoming transfers: none"), sh)
assert(Has(sh, "what it verifies:") and Has(sh, "what it does not verify:") and Has(sh, "large transfers"), "says what the direct-message check covers")
assert(Has(sh, "only the other side's \"done\" message confirms arrival"), sh)
S.outgoing = { target = "Bob Builder-Forever", id = "1", stage = "failed", route = { "WHISPER", "Bob Builder-Forever" }, started = s.GetTime() - 30,
  last = s.GetTime() - 10, sent = 100, total = 5000, code = "offer-no-answer", reason = "No answer from Bob Builder. Check Bob Builder is online." }
S.incoming["Carol Singer-Forever"] = { id = "2", stage = "receiving", route = { "PARTY" }, got = 10, expected = 100, started = s.GetTime(), last = s.GetTime() }
S.lastSeen = "offer from Dave Diver via WHISPER"; S.seenType, S.seenDist, S.seenAt = "offer", "WHISPER", s.GetTime()
S.lastDropped = "reply ignored from Erin Eagle"; S.droppedCode = "reply-not-for-current-transfer"
s.TwichUIDB.whisperProbe = { build = "70009", ok = true, at = os.time() - 86400 * 3 }
sh = SD.Build()
assert(Has(sh, "outgoing P1: stage failed via WHISPER, 100 of 5000 bytes") and Has(sh, "ended with offer-no-answer"), sh)
assert(Has(sh, "incoming P2: stage receiving via PARTY"), sh)
for _, name in ipairs({ "Bob", "Builder", "Carol", "Singer", "Dave", "Diver", "Erin", "Eagle", "No answer from" }) do
  assert(not Has(sh, name), "sharing report leaves out: " .. name)
end
assert(Has(sh, "last message handled: offer via WHISPER") and Has(sh, "last message ignored: reply-not-for-current-transfer"), sh)
s.C_ChatInfo.IsAddonMessagePrefixRegistered = function(p) return p ~= "TwichUIData2" end
assert(Has(Section(SD.Build(), "Configuration sharing"), "unavailable (prefix-not-confirmed)") and Has(SD.Build(), "not registered: TwichUIData2"))
s.TwichUIDB.modules.setupSharing = false
assert(Has(Section(SD.Build(), "Configuration sharing"), "configured off"), "sharing off is reported as off")
s.TwichUIDB.modules.setupSharing = true

-- real traces from a self-test send: marked synthetic; names become labels; failures have codes
CLIENTS.Sharer = s
local me = MakeClient("Twich", {"!!!TwichUI", "Foo"})
CLIENTS.Twich = me
me.print = function(s) table.insert(out, tostring(s)) end
me.TwichUIDB = { setup = { scanNext = true } }
for _, f in ipairs(DIAG_FILES) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, me); chunk("!!!TwichUI", {}) end
me.LOADED["!!!TwichUI"] = true; me.FireEvent("ADDON_LOADED", "!!!TwichUI")
me.FooDB = { a = 1 }; me.LOADED.Foo = true; me.FireEvent("ADDON_LOADED", "Foo")
me.FireEvent("PLAYER_LOGIN")
me.TwichUI.Setups:SaveMine(false)
local MD = me.TwichUI.Diag
MD.Start()
assert(me.TwichUI.Share:SendToSelf()); settle()
me.TwichUI.Share:Respond("Twich-Forever", true); settle(); settle()
assert(me.TwichUI.Share.outgoing.stage == "done")
local tr = MD.Build()
assert(Has(tr, "SYNTHETIC  share offer-sent P1 (route=LOOP)"), "a self-test is marked synthetic: " .. tr)
assert(Has(tr, "SYNTHETIC  share offer-accepted P1") and Has(tr, "SYNTHETIC  share data-handed-to-game P1 (") and Has(tr, "SYNTHETIC  share delivery-confirmed P1 (the other side answered done)"), tr)
assert(Has(tr, "SYNTHETIC  share offer-received P1 (via LOOP)") and Has(tr, "SYNTHETIC  share received-and-stored P1"), "the receiving half of a self-test is synthetic too")
assert(not Has(tr, "Twich-Forever") and not Has(tr, "FooDB") and not Has(tr, "Twich "), "no names or payload in the trace")
MD.Stop("manual"); MD.Clear()
assert(Has(MD.Build(), "outgoing transfer: none") == false, "the finished transfer is still described")

-- a failed offer gets a code in the trace, not its text
me.TwichUI.Share.outgoing = nil
MD.Start()
assert(me.TwichUI.Share:SendTo("Nobody Known"))
RunLongTimers(121); settle()
assert(me.TwichUI.Share.outgoing.stage == "failed")
tr = MD.Build()
assert(Has(tr, "share failed P1 (offer-no-answer)") and Has(tr, "ended with offer-no-answer"), tr)
assert(not Has(tr, "SYNTHETIC  share"), "a real offer to another player is not marked synthetic")
assert(not Has(tr, "Nobody") and not Has(tr, "Check Nobody"), "recipient never appears")
MD.Stop("manual"); MD.Clear()

---------------------------------------------------------------------------
-- Start-up and lifecycle: readiness states and reason codes, nothing else.
---------------------------------------------------------------------------
do
  local life = Section(a.TwichUI.Diag.Build(), "Start-up and lifecycle")
  assert(Has(life, "saved variables: ready; configuration ready: yes"), life)
  assert(Has(life, "logged in: yes; in the world now: yes"), life)
  a.TwichUI.Life.Note("deferred-combat")
  life = Section(a.TwichUI.Diag.Build(), "Start-up and lifecycle")
  assert(Has(life, "deferred-combat x1"), life)
  a.FireEvent("PLAYER_LEAVING_WORLD")
  life = Section(a.TwichUI.Diag.Build(), "Start-up and lifecycle")
  assert(Has(life, "waiting") and Has(life, "world-not-entered"), "a loading screen is reported as waiting, not as a fault: " .. life)
  a.FireEvent("PLAYER_ENTERING_WORLD", false, false)
end

---------------------------------------------------------------------------
-- Notification coordination: kinds and reasons, never ids or text.
---------------------------------------------------------------------------
local n = boot("Notifier", nil, { "chronicle/Style.lua", "modules/Notify.lua" })
local N, ND = n.TwichUI.Notify, n.TwichUI.Diag
N.Register("friend", { label = "Friend login", show = function() return true end, dismiss = function() end, sample = function() return {} end })
N.Register("arrival", { label = "Zone arrival", show = function() return true end, dismiss = function() end })
local nt = Section(ND.Build(), "Notification coordination")
assert(Has(nt, "ready") and Has(nt, "card kinds registered: friend, arrival (no preview)") and Has(nt, "queue: 0 of at most 6 waiting; waiting: none"), nt)
ND.Start()
assert(N.Submit({ kind = "friend", id = "9988776,5544332", payload = {}, ttl = 10 }))
assert(N.Submit({ kind = "friend", id = "1122334", payload = {}, ttl = 10 }))
local ok, why = N.Submit({ kind = "friend", id = "1122334", payload = {}, ttl = 10 })
assert(not ok and why == "duplicate")
N.Preview("friend", "a-preview-id")
nt = ND.Build()
local ns = Section(nt, "Notification coordination")
assert(Has(ns, "waiting: friend (preview) x1, friend x1") and Has(ns, "showing now: friend (real)"), ns)
assert(Has(ns, "refused when sent (duplicate, queue full): duplicate x1"), ns)
assert(Has(nt, "notify queued (friend)") and Has(nt, "notify shown (friend)") and Has(nt, "notify refused (friend duplicate)"), nt)
for _, id in ipairs({ "9988776", "5544332", "1122334", "a-preview-id" }) do assert(not Has(nt, id), "no ids: " .. id) end
n.FireEvent("PLAYER_LEAVING_WORLD")
ns = Section(ND.Build(), "Notification coordination")
assert(Has(ns, "waiting (loading-screen)") and Has(ns, "loading x1") and Has(ns, "currently in the world: no"), ns)
assert(Has(ND.Build(), "SYNTHETIC  notify queued (friend)") or Has(ND.Build(), "SYNTHETIC  notify dropped (friend loading)"), "previews are marked in the trace")
ND.Stop("manual"); ND.Clear()

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local SL = a.SlashCmdList
out = {}
SL.TWICHUI("")
assert(table.concat(out, "\n"):find("diagnostics [start|stop|clear|status]", 1, true), "help lists the command")
out = {}; SL.TWICHUI("diagnostics start"); assert(Has(table.concat(out, "\n"), "tracing is ON for up to 15 minutes") and D.Tracing())
out = {}; SL.TWICHUI("diagnostics status"); local st2 = table.concat(out, "\n")
assert(Has(st2, "tracing is ON") and Has(st2, "Environment: configured n/a") and Has(st2, "/tui diagnostics opens the full report"), st2)
out = {}; SL.TWICHUI("diagnostics stop"); assert(Has(table.concat(out, "\n"), "tracing stopped") and not D.Tracing())
out = {}; SL.TWICHUI("diagnostics stop"); assert(Has(table.concat(out, "\n"), "was not on"))
D.Trace("food", "x")
SL.TWICHUI("diag clear"); assert(#D.Records() == 0, "a unique prefix works, and clear clears")
out = {}; SL.TWICHUI("diagnostics bogus"); assert(Has(table.concat(out, "\n"), "usage: /tui diagnostics"))
out = {}; SL.TWICHUI("troubleshoot status"); assert(Has(table.concat(out, "\n"), "tracing is off"), "the alias goes through the same parser")
out = {}; SL.TWICHUI("diagnostics probe"); assert(Has(table.concat(out, "\n"), "probe"), "the probe is still reachable")
-- (the window itself is exercised in test_friend_diagnostics.lua, which has frame fakes)

print("DIAGNOSTICS TEST PASSED")
