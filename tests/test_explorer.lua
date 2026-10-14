-- Saved Data Explorer (read-only): traversal that changes nothing and runs no metatable code; false,
-- 0, "" and empty tables; mixed keys and their order; large, nested, cyclic and shared tables; values
-- that aren't data; backups shown as stored, not the live settings; the share preview against the real
-- messages decoded off the wire; no sending or transfer from a preview; a stale preview; personal-looking
-- values hidden and revealed, and the separate sanitized copy; a source deleted or replaced while open;
-- bounded search, dumps and text; and the window itself. All data here is made up.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
math.randomseed(7)

local function boot(name)
  local c = MakeClient(name, {"!!!TwichUI", "Foo"})
  CLIENTS[name] = c
  return c
end

local a = boot("Alpha")
local b = boot("Beta")

-- Alpha gets the explorer and its window, with permissive UI mocks (as test_stored_data) whose Show and
-- Hide run OnShow and OnHide, and a ScrollBox that builds every row it is given.
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) local was = s.shown; s.shown = true
      if not was and s.scripts and s.scripts.OnShow then s.scripts.OnShow(s) end end end
    if k == "Hide" then return function(s) local was = s.shown; s.shown = false
      if was and s.scripts and s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "HasFocus" then return function() return false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end})
end
local realCreate = a.CreateFrame
a.CreateFrame = function(kind, name, parent, template)
  local o = Obj()
  for k, v in pairs(realCreate()) do rawset(o, k, v) end
  rawset(o, "Show", nil); rawset(o, "Hide", nil); rawset(o, "IsShown", nil)
  if template == "WowScrollBoxList" then
    rawset(o, "SetDataProvider", function(self, dp)
      self.list = {}
      for i, d in ipairs(dp.rows) do
        local row = a.CreateFrame("Button")
        self.view.init(row, d)
        self.list[i] = row
      end
    end)
  end
  if name then a[name] = o end
  return o
end
a.CreateScrollBoxListLinearView = function()
  return {SetElementExtent = function() end, SetElementInitializer = function(self, _, fn) self.init = fn end}
end
a.ScrollUtil = {InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end}
a.CreateDataProvider = function(rows) return {rows = rows} end
a.UIParent, a.UISpecialFrames, a.tinsert = Obj(), {}, table.insert
a.GameTooltip = Obj(); a.GameTooltip_Hide = function() end
for _, f in ipairs({"setup/StoredData.lua", "setup/Explorer.lua", "setup/Cleanup.lua", "chronicle/Style.lua", "Look.lua", "setup/ExplorerWindow.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, a); chunk("!!!TwichUI", {})
end

-- Saved data before login (made up): a settings scan is due, and a Chronicle with a note.
a.TwichUIDB = {setup = {scanNext = true}}
a.TwichUIChronicleDB = {version = 1, chars = {["Alpha - Forever"] = {nextId = 2, tracking = true,
  entries = {{id = 1, t = 1700000000, kind = "note", title = "Camp", note = "dear diary"}}}}}
for _, c in ipairs({a, b}) do
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
end
-- Foo's saved settings: false, 0, "", empty tables, mixed keys, per-character keys.
a.FooDB = {
  profileKeys = {["Alpha - Forever"] = "Default", ["Alt - Forever"] = "Default"},
  profiles = {Default = {enabled = false, zero = 0, empty = "", none = {}, scale = 1, list = {"a", "b", "c"},
    nested = {deep = {deeper = {x = 1}}}}},
  [1] = "one", ["1"] = "text one", [2.5] = "a fraction", [true] = "a true key",
}
for _, c in ipairs({a, b}) do
  c.LOADED.Foo = true; c.FireEvent("ADDON_LOADED", "Foo"); c.FireEvent("PLAYER_LOGIN")
end
TIMERS = {}

local R, EX, ST, SH, RS = a.TwichUI, a.TwichUI.Explorer, a.TwichUI.Setups, a.TwichUI.Share, a.TwichUI.Restore
assert(EX and a.TwichUI.ExplorerWindow, "the explorer loaded")
assert(ST.capture and ST.capture.FooDB, "the scan found Foo's settings")
assert(ST:SaveMine(false) == 1)
local status, point = RS:Create("Before raid")
assert(status == "created" and point, "a restore point from the scan")

-- Runtime oddities inside TwichUIDB (a test only; never saved): code, a game-object stand-in, a
-- coroutine, a table key, and a table whose every metamethod fails if anything runs it.
local function boom(what) return function() error("metatable code ran: " .. what) end end
local trap = setmetatable({inside = 1}, {__index = boom("__index"), __newindex = boom("__newindex"),
  __tostring = boom("__tostring"), __call = boom("__call"), __concat = boom("__concat"), __eq = boom("__eq"),
  __lt = boom("__lt"), __le = boom("__le"), __len = boom("__len"), __metatable = "locked"})
a.TwichUIDB.oddities = {fn = function() error("a stored function was called") end, ud = newproxy(true),
  co = coroutine.create(function() end), trap = trap, [trap] = "a table as a key"}

---------------------------------------------------------------------------
-- A fingerprint of everything TwichUI saves, read with next and rawget only.
---------------------------------------------------------------------------
local VARS = {"TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB"}
local function Fingerprint()
  local out, seen, ids = {}, {}, 0
  local function W(v, depth)
    local t = type(v)
    if t ~= "table" then out[#out + 1] = t .. ":" .. ((t == "string" or t == "number" or t == "boolean") and tostring(v) or "?") return end
    if seen[v] then out[#out + 1] = "ref" .. seen[v] return end
    ids = ids + 1; seen[v] = ids
    out[#out + 1] = "{" .. ids
    local keys = {}
    for k in next, v do keys[#keys + 1] = k end
    table.sort(keys, function(x, y)
      local tx, ty = type(x), type(y)
      if tx ~= ty then return tx < ty end
      if tx == "string" or tx == "number" then return x < y end
      return false
    end)
    for _, k in ipairs(keys) do
      W(k, depth); W(rawget(v, k), depth + 1)
    end
    out[#out + 1] = "}"
  end
  for _, name in ipairs(VARS) do out[#out + 1] = name; W(rawget(a, name), 0) end
  return table.concat(out, ",")
end
local before = Fingerprint()

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local ids = {}
for _, s in ipairs(EX.Sources()) do ids[s.id] = s end
for _, id in ipairs({"settings", "restore:" .. point.id, "share:preview", "share:mine", "chronicle",
  "var:TwichUIRestoreDB", "var:TwichUIBackupDB", "var:TwichUIShareDB"}) do
  assert(ids[id], "listed: " .. id)
end
for id in pairs(ids) do assert(not id:find("Foo"), "no other addon's saved variable is a source") end
assert(ids.settings.Root() == a.TwichUIDB and ids.chronicle.Root() == a.TwichUIChronicleDB)
assert(EX.PathOf(ids["restore:" .. point.id]) == "TwichUIRestoreDB.points[1]")

---------------------------------------------------------------------------
-- Text: false, 0, "", empty tables, mixed keys, exact numbers
---------------------------------------------------------------------------
assert(EX.ValueText(false) == "false" and EX.ValueText(0) == "0" and EX.ValueText("") == '""')
assert(EX.ValueText(nil) == "nil", "missing is told apart from false")
assert(EX.ValueText(function() end) == "<function>" and EX.ValueText(newproxy()) == "<userdata>")
assert(EX.ValueText(coroutine.create(function() end)) == "<thread>")
assert(EX.TypeNote(false):find("not a missing one") and EX.TypeNote(function() end):find("never run"))
assert(EX.NumText(0.1) == "0.1" and EX.NumText(-3) == "-3" and EX.NumText(1e300) == "1e+300")
for _, n in ipairs({1/3, 2^53, 1e-7, -2.5, 123456.789}) do assert(tonumber(EX.NumText(n)) == n, "reads back exactly: " .. EX.NumText(n)) end
assert(EX.NumText(0/0) == "nan" and EX.NumText(1/0) == "inf")

-- The client warns ("integer overflow attempting to store") when %d is given an integer outside 32 bits.
-- Plain Lua 5.1 doesn't, so this stand-in for string.format records it, as the client would.
local overflow
do
  local realFormat = string.format
  local function checked(fmt, ...)
    local args, i = {...}, 0
    for spec in fmt:gmatch("%%[%-+ #0]*%d*%.?%d*(%a)") do
      i = i + 1
      if (spec == "d" or spec == "i") and type(args[i]) == "number" and (args[i] >= 2^31 or args[i] < -2^31) then
        overflow = (overflow or 0) + 1
      end
    end
    return realFormat(fmt, ...)
  end
  string.format = checked
end
local function Overflowed(fn) overflow = nil; local r = fn(); return overflow, r end
for _, n in ipairs({3298500249, 2^31, -2^31 - 1, 4294967296, 1e14, 999999999999999}) do
  local hits, text = Overflowed(function() return EX.NumText(n) end)
  assert(not hits, "NumText must not format " .. n .. " with %d")
  assert(tonumber(text) == n and not text:find("e"), "a whole number reads as digits: " .. text)
  -- the saved-size estimate measures the same numbers, as values and as keys
  hits = Overflowed(function() return a.TwichUI.StoredData.Count("Big", {n, [n] = true}) end)
  assert(not hits, "the size estimate must not format " .. n .. " with %d")
end
assert(EX.NumText(-3) == "-3" and EX.NumText(0) == "0" and EX.NumText(2147483647) == "2147483647")
assert(EX.NumText(-0) == "0" or EX.NumText(-0) == "-0")
assert(EX.PathPart(1) == "[1]" and EX.PathPart("1") == '["1"]' and EX.PathPart(true) == "[true]")
assert(EX.PathPart(2.5) == "[2.5]" and EX.PathPart("name") == ".name" and EX.PathPart("two words") == '["two words"]')
assert(EX.PathPart('say "hi"\n') == '["say \\"hi\\"\\n"]', "quotes and line breaks escaped")
assert(EX.PathPart("") == '[""]', "an empty key is still visible")
assert(EX.PathPart({}) == "[<table>]", "a table key is named, never tostring'd")
assert(select(3, EX.Shape({})) == "empty" and select(3, EX.Shape({1, 2})) == "list")
assert(select(3, EX.Shape({a = 1})) == "keyed" and select(3, EX.Shape({1, a = 1})) == "mixed")
assert(select(3, EX.Shape({[2] = 1})) == "gaps", "a lone [2] isn't a list")
assert(select(3, EX.Shape({[2.5] = 1, [1] = 1})) == "mixed", "a fraction is a key, not a list position")
assert(select(3, EX.Shape({[1] = 1, [3] = 1})) == "gaps", "a list with a hole isn't called a list")
assert(EX.ShapeText(EX.Shape({})) == "empty table")

---------------------------------------------------------------------------
-- The tree: the current settings, read only
---------------------------------------------------------------------------
local tree = EX.NewTree(a.TwichUIDB, "TwichUIDB")
local function Find(t, keys) return t:Reveal(keys) end
local odd = Find(tree, {"oddities"})
assert(odd and odd.count == 5, "oddities listed: " .. tostring(odd and odd.count))
tree:Open(odd)
local seenTypes = {}
for i = 1, #odd.keys do local k = tree:Kid(odd, i); seenTypes[type(k.value)] = true end
assert(seenTypes["function"] and seenTypes.userdata and seenTypes.thread and seenTypes.table and seenTypes.string)
local trapNode = Find(tree, {"oddities", "trap"})
assert(trapNode and trapNode.count == 1 and tree:Open(trapNode), "a table with a metatable is opened by its own entries")
local trapKids = tree:Rows()
assert(#trapKids > 0)
-- Expanding everything, dumping and searching the settings run nothing and change nothing.
tree:ExpandAll(tree.root)
local rows = tree:Rows()
assert(#rows > 20)
local text = EX.Dump(a.TwichUIDB, "TwichUIDB", false)
assert(text:find("<function>", 1, true) and text:find("<userdata>", 1, true) and text:find("<thread>", 1, true))
assert(text:find("[<table>] = ", 1, true), "a table key is shown by type")
local found
EX.Search(a.TwichUIDB, "TwichUIDB", "inside", function(r) found = r end)
FlushTimers()
assert(found and #found.results == 1 and found.results[1].path == "TwichUIDB.oddities.trap.inside")
assert(Fingerprint() == before, "nothing was changed by looking")

---------------------------------------------------------------------------
-- Mixed keys, order, and false / 0 / "" / {} in a backup
---------------------------------------------------------------------------
local rp = RS.Get(point.id)
local bt = EX.NewTree(rp, EX.PathOf(ids["restore:" .. point.id]))
local data = Find(bt, {"tables", "FooDB", "data"})
assert(data and bt:Open(data))
local order = {}
for i = 1, #data.keys do order[i] = EX.PathPart(data.keys[i]) end
assert(table.concat(order, " ") == '[1] [2.5] ["1"] .profileKeys .profiles [true]', table.concat(order, " "))
local def = Find(bt, {"tables", "FooDB", "data", "profiles", "Default"})
assert(def.shape == "keyed")
bt:Open(def)
local byKey = {}
for i = 1, #def.keys do local k = bt:Kid(def, i); byKey[k.key] = k end
assert(byKey.enabled.value == false and byKey.zero.value == 0 and byKey.empty.value == "")
assert(byKey.none.shape == "empty" and byKey.list.shape == "list" and byKey.list.count == 3)
assert(byKey.missing == nil, "a missing key has no row: nothing is filled in")
-- Deterministic: the same rows and the same text every time.
local function RowKeys(t) local o = {} for _, r in ipairs(t:Rows()) do o[#o + 1] = r.node and r.node.path or "?" end return table.concat(o, "|") end
local bt2 = EX.NewTree(rp, bt.root.path)
bt2:Reveal({"tables", "FooDB", "data", "profiles", "Default"}); bt2:Open(bt2:Reveal({"tables", "FooDB", "data", "profiles", "Default"}))
assert(RowKeys(bt) == RowKeys(bt2), "same rows in the same order")
assert(EX.Dump(rp, "x", false) == EX.Dump(rp, "x", false), "same text")

-- The backup is the stored copy, not the live settings.
a.FooDB.profiles.Default.scale = 2
assert(byKey.scale.value == 1 and a.FooDB.profiles.Default.scale == 2, "a backup shows what it stored")
assert(EX.Summary(ids["restore:" .. point.id], rp, true)[1][2] ~= "not recorded", "its own date")
a.FooDB.profiles.Default.scale = 1

---------------------------------------------------------------------------
-- Cycles and shared tables
---------------------------------------------------------------------------
local loop = {name = "loop"}
loop.self = loop
local shared = {x = 1}
loop.a, loop.b = shared, shared
local lt = EX.NewTree(loop, "loop")
local kids = {}
for i = 1, #lt.root.keys do local k = lt:Kid(lt.root, i); kids[k.key] = k end
assert(kids.self.loop and not lt:CanOpen(kids.self), "a table inside itself isn't opened")
assert(kids.b.sharedWith and kids.b.sharedWith.path == "loop.a" and not kids.a.sharedWith, "the second sight of a shared table says where it is")
assert(lt:ExpandAll(lt.root) == false)
local lt_text, info = EX.Dump(loop, "loop", false)
assert(lt_text:find("<contains itself: loop>", 1, true) and lt_text:find("<same table as loop.a>", 1, true))
assert(info.loops == 1 and info.shared == 1)
local hits
EX.Search(loop, "loop", "x", function(r) hits = r end); FlushTimers()
assert(hits and #hits.results == 1, "a shared table is searched once, and a loop ends")

---------------------------------------------------------------------------
-- Large and nested collections: pages, limits, bounded search and text
---------------------------------------------------------------------------
local big = {}
for i = 1, 5000 do big["k" .. i] = {i = i, s = "v" .. i} end
local gt = EX.NewTree(big, "big")
local r1 = gt:Rows()
assert(#r1 == EX.PAGE + 1 and r1[#r1].more, "a page, then Show more")
gt:More(gt.root)
assert(#gt:Rows() == 2 * EX.PAGE + 1)
assert(gt:ExpandAll(gt.root) == false and #gt:Rows() > 400)
local wide = {}
for i = 1, EX.EXPAND_LIMIT + 50 do wide[i] = {i} end
local wt = EX.NewTree(wide, "wide")
for _ = 1, 20 do wt:More(wt.root) end
assert(wt:ExpandAll(wt.root) == true, "Expand all stops at its limit and says so")
local deep = {}
local cur = deep
for _ = 1, EX.MAX_DEPTH + 10 do cur.d = {}; cur = cur.d end
local dt = EX.NewTree(deep, "deep")
dt:ExpandAll(dt.root)
local deepest = 0
for _, r in ipairs(dt:Rows()) do if r.node and r.node.depth > deepest then deepest = r.node.depth end end
assert(deepest <= EX.MAX_DEPTH, "nothing deeper than the limit is opened")
local res
EX.Search(big, "big", "v4", function(r) res = r end)
FlushTimers(); FlushTimers(); FlushTimers()
assert(res and #res.results == EX.SEARCH_RESULTS and res.full, "results stop at their limit and say so")
local visits = EX.SEARCH_VISITS
EX.SEARCH_VISITS = 100
res = nil
EX.Search(big, "big", "nothing-matches", function(r) res = r end)
FlushTimers()
assert(res and res.cut and #res.results == 0, "the search stops at its limit and says so")
EX.SEARCH_VISITS = visits
-- A newer search replaces an older one; an empty one doesn't run.
local first, second
EX.Search(big, "big", "v1", function(r) first = r end)
EX.Search(big, "big", "v2", function(r) second = r end)
FlushTimers(); FlushTimers(); FlushTimers()
assert(first == nil and second and second.query == "v2", "the older search was cancelled")
assert(EX.Search(big, "big", "   ", function() end) == false)
EX.Search(big, "big", "v3", function(r) first = r end)
EX.Cancel("search"); FlushTimers()
assert(not EX.Busy("search"))
local limit = EX.DUMP_BYTES
EX.DUMP_BYTES = 4096
local cutText, cutInfo = EX.Dump(big, "big", false)
assert(cutInfo.cut and #cutText < 4096 + 200 and cutText:find("cut here", 1, true), "the text stops at its limit and says so")
EX.DUMP_BYTES = limit
local long = {s = ("x"):rep(EX.DETAIL_BYTES + 10)}
local lnode = EX.NewTree(long, "long"):Kid(EX.NewTree(long, "long").root, 1)
local v, hidden, cutLong = EX.ValueCopy(lnode, true)
assert(not hidden and cutLong and #v <= EX.DETAIL_BYTES, "long text is cut for display and says so")
assert(EX.ValueText(long.s):find("characters)", 1, true))

---------------------------------------------------------------------------
-- Damaged records don't break the window's summary
---------------------------------------------------------------------------
local damaged = {name = "x", tables = "not a table", created = "soon"}
local sum = EX.Summary({kind = "restore"}, damaged, true)
assert(sum[1][1] == "Summary" and sum[1][2]:find("couldn't", 1, true))

---------------------------------------------------------------------------
-- The share preview against the real messages on the wire
---------------------------------------------------------------------------
local sentBefore, netBefore, longBefore = #(SENT_LOG or {}), #NET, #LONG_TIMERS
local backupsBefore, restoreBefore = Fingerprint(), nil
local p = EX.BuildPreview()
assert(p and p.offer.id == EX.PREVIEW_ID and p.data.id == EX.PREVIEW_ID, "no transfer id is drawn")
assert(p.offer.t == "offer" and p.data.t == "data" and p.data.tables.FooDB)
assert(p.data.meta.source == "Alpha - Forever")
assert(not EX.PreviewStale(p))
local personal
EX.FindPersonal(p.root, "(share preview)", function(r) personal = r end)
for _ = 1, 5 do FlushTimers() end
assert(p.encoded and p.lanes >= 1 and p.messages >= 1, "the packed size was measured")
assert(personal and personal.count >= 4, "names in the messages are found: " .. tostring(personal and personal.count))
local paths = {}
for _, e in ipairs(personal.examples) do paths[#paths + 1] = e.path end
paths = table.concat(paths, "\n")
assert(paths:find('profileKeys["Alt - Forever"]', 1, true), "another character's name in an addon's settings is flagged")
assert(paths:find("offer.from", 1, true) and paths:find("data.meta.sourceName", 1, true))
-- Nothing was sent, no transfer began, no timer was set, nothing was stored.
assert(#(SENT_LOG or {}) == sentBefore and #NET == netBefore and #LONG_TIMERS == longBefore, "a preview sends nothing")
assert(SH.outgoing == nil and next(SH.incoming) == nil, "and starts no transfer")
assert(Fingerprint() == backupsBefore, "and changes no saved data")

-- What's included and left out, by the sharing code's own rules.
local contents = EX.ShareContents(p)
assert(#contents.addons == 1 and contents.addons[1].tables[1] == "FooDB")
assert(contents.identity[2][2] == "Alpha - Forever")

-- Now a real send to Beta, and the messages as they cross the wire.
local wire = {}
local function step()
  FlushTimers()
  for _, m in ipairs(NET) do wire[#wire + 1] = m end
  Pump()
end
assert(SH:SendTo("Beta"))
for _ = 1, 3 do step() end
b.TwichUI.Share:Respond("Alpha-Forever", true)
for _ = 1, 30 do step() end
assert(SH.outgoing.stage == "done", "the real send finished: " .. tostring(SH.outgoing.stage))
local LD, LS = a.LibStub("LibDeflate"), a.LibStub("LibSerialize")
local function Control(text)
  local ok, t = LS:Deserialize(LD:DecompressDeflate(LD:DecodeForWoWAddonChannel(text)))
  return ok and t
end
local offer, lanes, nLanes, realId
for _, m in ipairs(wire) do
  if m.prefix == "TwichUISetup" then
    local msg = Control(m.text)
    if msg and msg.t == "offer" then offer = msg; realId = msg.id end
  elseif m.prefix:find("^TwichUIData") then
    local id, i, n, rest = m.text:match("^(%d+):(%d+):(%d+):()")
    lanes = lanes or {}
    lanes[tonumber(i)] = m.text:sub(rest)
    nLanes = tonumber(n)
  end
end
assert(offer and lanes and nLanes, "both messages were seen")
local joined = table.concat(lanes, "", 1, nLanes)
local pos, parts = 3, {}
while pos <= #joined do
  local len, from = joined:match("^(%d+):()", pos)
  len = tonumber(len)
  parts[#parts + 1] = LD:DecompressDeflate(LD:DecodeForWoWAddonChannel(joined:sub(from, from + len - 1)))
  pos = from + len
end
local ok, wireData = LS:Deserialize(table.concat(parts))
assert(ok and wireData.t == "data")
local function Same(x, y, path)
  if type(x) ~= type(y) then error(("differs at %s: %s vs %s"):format(path, type(x), type(y))) end
  if type(x) ~= "table" then
    if x ~= y then error(("differs at %s: %s vs %s"):format(path, tostring(x), tostring(y))) end
    return
  end
  for k, v in pairs(x) do Same(v, y[k], path .. "." .. tostring(k)) end
  for k in pairs(y) do if x[k] == nil then error("only on one side: " .. path .. "." .. tostring(k)) end end
end
-- The real offer carries the recipient's name and a real id; everything else is the preview's.
assert(offer.to == "Beta-Forever" and realId ~= EX.PREVIEW_ID and #realId == #EX.PREVIEW_ID)
offer.to, offer.id = nil, EX.PREVIEW_ID
wireData.id = EX.PREVIEW_ID
Same(p.offer, offer, "offer")
Same(p.data, wireData, "data")
assert(p.lanes == nLanes, "the same number of lanes")
assert(math.abs(p.encoded - #joined) <= 16, ("about the same packed size: %d vs %d"):format(p.encoded, #joined))

---------------------------------------------------------------------------
-- Stale previews
---------------------------------------------------------------------------
local changes = 0
EX.OnChange(function() changes = changes + 1 end)
ST:UpdateSavedAddonList()
assert(changes > 0, "the explorer heard about it")
assert(EX.PreviewStale(p):find("changed", 1, true), "a changed setup makes the preview stale")
local p2 = EX.BuildPreview()
assert(EX.preview == p2 and not EX.PreviewStale(p2))
ST:DeleteMine()
assert(EX.PreviewStale(p2):find("deleted", 1, true))
local none, why = EX.BuildPreview()
assert(none == nil and why:find("no saved setup", 1, true))
assert(ST:SaveMine(false) == 1)

---------------------------------------------------------------------------
-- Personal-looking values: hidden until revealed; the support copy is always sanitized
---------------------------------------------------------------------------
assert(EX.PersonalKey("Alpha - Forever", "profileKeys") and EX.PersonalKey("Pal", "trusted") == "a friend's name")
assert(EX.PersonalValue("sourceName", "Alpha") and EX.PersonalValue("note", "dear diary") == "your own writing")
assert(EX.PersonalValue("title", "Camp", {kind = "note"}) and not EX.PersonalValue("title", "Level 10", {kind = "level"}))
assert(EX.PersonalValue("tag", "Someone#1234") == "a Battle.net tag" and EX.PersonalValue("id", "Player-1-0AB12") == "a character id")
assert(not EX.PersonalValue("scale", "1.5") and not EX.PersonalKey("enabled", "Default"))
local ct = EX.NewTree(a.TwichUIChronicleDB, "TwichUIChronicleDB")
local note = ct:Reveal({"chars", "Alpha - Forever", "entries", 1, "note"})
assert(note and note.value == "dear diary")
assert(EX.NodePath(note, false):find("<hidden: a character's name>", 1, true), "the path hides the name")
assert(EX.NodePath(note, true) == 'TwichUIChronicleDB.chars["Alpha - Forever"].entries[1].note')
assert(EX.ValueCopy(note, false):find("<hidden: your own writing>", 1, true) and EX.ValueCopy(note, true) == "dear diary")
local record = ct:Reveal({"chars", "Alpha - Forever"})
local masked = EX.CopyText("readable", record, false)
local exact = EX.CopyText("readable", record, true)
local support, supportNote = EX.CopyText("support", record, true)
assert(not masked:find("dear diary", 1, true) and masked:find("personal-looking values are hidden", 1, true))
assert(exact:find("dear diary", 1, true) and exact:find("Camp", 1, true) and not exact:find("<hidden", 1, true))
assert(not support:find("dear diary", 1, true) and support:find("For support", 1, true) and support:find("isn't the exact data", 1, true),
  "the support copy is sanitized even with Reveal on, and says so")
assert(supportNote:find("Sanitized", 1, true))
assert(masked:find("not an importable configuration", 1, true))
-- A name in the source's own path, and a shared table first seen under a name, stay hidden too.
a.TwichUIBackupDB["Alpha - Forever"] = {created = 1700000000, tables = {FooDB = {present = true, data = {x = 1}}}}
local undo = EX.Source("undo:Alpha - Forever")
assert(undo and EX.PathOf(undo, false):find("<hidden", 1, true) and EX.PathOf(undo, true):find("Alpha", 1, true))
local ut = EX.NewTree(undo.Root(), EX.PathOf(undo))
ut.root.maskedPath = undo.masked
local ux = ut:Reveal({"tables", "FooDB", "data", "x"})
assert(not EX.NodePath(ux, false):find("Alpha", 1, true) and EX.NodePath(ux, true):find("Alpha", 1, true))
local sharedUnder = {x = 1}
local refText = EX.Dump({profileKeys = {["Alpha - Forever"] = sharedUnder}, z = sharedUnder}, "t", true)
assert(refText:find("<same table as t.profileKeys[<hidden", 1, true) and not refText:find("Alpha", 1, true),
  "a reference to a table under a hidden name doesn't show the name")
local pathText = EX.CopyText("path", note, false)
assert(pathText:find("<hidden", 1, true))
assert(select(2, EX.CopyText("value", record, true)):find("table", 1, true), "a table has no single value to copy")

---------------------------------------------------------------------------
-- The window: open, choose each source, search, copy, delete a backup while it is shown, close
---------------------------------------------------------------------------
local XW = a.TwichUI.ExplorerWindow
local snapshot = Fingerprint()
XW.Show()
local f = a.TwichUISavedDataExplorer
assert(f and f.shown, "the window opened")
assert(#f.sources.scroll.list > 8, "sources listed")
for _, s in ipairs(EX.Sources()) do XW.Show(s.id); FlushTimers() end
XW.Show("share:preview")
for _ = 1, 5 do FlushTimers() end
assert(EX.preview and EX.preview.encoded, "the preview was built and measured in the window")
assert(f.details.edit.text:find("OUTGOING SHARE", 1, true) and f.details.edit.text:find("NOT INCLUDED", 1, true))
assert(f.banner.text:find("hidden on screen", 1, true) and f.banner.text:find("are sent", 1, true),
  "the share view says hidden values are still sent")
assert(not f.details.edit.text:find("Alt - Forever", 1, true), "masked by default")
-- Reveal, then close: Reveal turns off and everything is let go.
f.reveal.scripts.OnClick(f.reveal)
assert(f.details.edit.text:find("Alpha", 1, true), "revealed")
f:Hide()
assert(EX.preview == nil and not EX.Busy("search") and not EX.Busy("personal"), "released on close")
XW.Show("share:preview")
assert(not f.details.edit.text:find("Alt - Forever", 1, true), "Reveal doesn't outlive the window")
-- An Undo copy: named for a character, hidden until revealed.
XW.Show("undo:Alpha - Forever")
assert(f.head.text == "Undo copy" and not f.path.text:find("Alpha", 1, true), "heading and path hide the name")
-- A search, through the box (it waits for typing to pause).
XW.Show("settings")
f.search:SetText("inside")
f.search.scripts.OnTextChanged(f.search, true)
for _ = 1, 4 do FlushTimers() end
assert(f.status.text:find("1 match", 1, true), "search ran: " .. f.status.text)
-- A backup deleted while it is on screen.
XW.Show("restore:" .. point.id)
assert(f.head.text == "Before raid")
RS:Delete(point.id)
FlushTimers(); FlushTimers()
assert(f.banner.text:find("isn't there any more", 1, true), "an understandable unavailable state: " .. f.banner.text)
-- The saved setup replaced while shown: the new one is read.
XW.Show("share:mine")
local oldPack = ST.Mine()
assert(ST:SaveMine(false) == 1 and ST.Mine() ~= oldPack)
FlushTimers(); FlushTimers()
assert(f.head.text == "Your saved setup" and f.banner.text == "")
f:Hide()
-- Looking changed nothing but the backup deleted on purpose, and the window saved nothing of its own.
local after = Fingerprint()
assert(after ~= snapshot)   -- the deleted backup and the re-saved setup
for _, name in ipairs(VARS) do
  for k in next, rawget(a, name) do
    assert(type(k) ~= "string" or not k:lower():find("explor"), "nothing of the explorer is saved: " .. name .. "." .. tostring(k))
  end
end
a.TwichUIDB.oddities = nil
print("EXPLORER OK")
