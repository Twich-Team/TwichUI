-- Addon data (read-only): the scan (what appears as each addon loads, data
-- kept and code skipped, earlier finds kept for addons that didn't load),
-- probable working data set apart, where addons stand, the size estimate
-- against the client's file format, counting a little each frame, showing
-- values safely, the window and its tree; and setup sharing's addon state for
-- an addon off for this character only, or waiting to load on demand.
dofile(TESTS .. "harness.lua")
LOD = { Lazy = true }
OFF = { Offy = true }
local c = MakeClient("Rich", {"!!!TwichUI", "Foo", "Bar", "Lazy", "Offy", "Blizzard_Thing"})

-- permissive UI mocks (as in test_window_smoke), plus a ScrollBox that
-- builds every row it's given so the initializers run
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end   -- fields (row.label ...) start unset
    return function() end
  end})
end
local realCreate = c.CreateFrame
c.CreateFrame = function(kind, name, parent, template)
  local o = Obj()
  for k, v in pairs(realCreate()) do rawset(o, k, v) end
  rawset(o, "Show", nil); rawset(o, "Hide", nil); rawset(o, "IsShown", nil)   -- keep the mock's own
  if template == "WowScrollBoxList" then
    rawset(o, "SetDataProvider", function(self, dp)
      self.list = {}
      for i, d in ipairs(dp.rows) do
        local row = c.CreateFrame("Button")
        self.view.init(row, d)
        self.list[i] = row
      end
    end)
  end
  if name then c[name] = o end
  return o
end
c.CreateScrollBoxListLinearView = function()
  return {SetElementExtent = function() end, SetElementInitializer = function(self, _, fn) self.init = fn end}
end
c.ScrollUtil = {InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end}
c.CreateDataProvider = function(rows) return {rows = rows} end
c.UIParent, c.UISpecialFrames, c.tinsert = Obj(), {}, table.insert
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(k) c.popup = k end
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
c.UnitGUID = function() return "Player-1-0ABC" end
for _, f in ipairs({"setup/StoredData.lua", "setup/StoredDataWindow.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local R = c.TwichUI
local SD = R.StoredData

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
c.TwichUIDB = {svTest = {report = "old"}, storedData = {scanNext = true, scanMode = "window", found = {
  OldDB = {owner = "Lazy", seen = 1}, GoneDB = {owner = "Gone", seen = 1}, FooOld = {owner = "Foo", seen = 1}}}}
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(c.TwichUIDB.storedData.scanNext == nil, "the scan request is used up")
assert(c.TwichUIDB.svTest == nil and c.TwichUIDB.storedData.scanMode == nil, "the removed check's leftovers are dropped")

c.FooDB = {scale = 1, list = {"a", "b"}}
c.FooMixin = {OnLoad = function() end}               -- code
c.FooFrame = setmetatable({}, {__index = {}})         -- a frame-like object
c.SLASH_FOO1 = "/foo"                                 -- a slash command
c.BINDING_HEADER_FOO = "Foo"
c.FooSpeed = 1.5                                      -- a loose saved value
c._FooCache = {a = 1}                                 -- probable working data: leading _
c.FOO_TEXTURES = {"x"}                                -- ... in capitals
c.Foo = {count = 1}                                   -- ... the addon's own name
c.LOADED.Foo = true; c.FireEvent("ADDON_LOADED", "Foo")
c.BlizzThingDB = {a = 1}
c.LOADED.Blizzard_Thing = true; c.FireEvent("ADDON_LOADED", "Blizzard_Thing")
c.BarDB = {}
c.LOADED.Bar = true; c.FireEvent("ADDON_LOADED", "Bar")
c.FireEvent("PLAYER_LOGIN")

local found = c.TwichUIDB.storedData.found
assert(found.FooDB and found.FooDB.owner == "Foo" and not found.FooDB.value)
assert(found.FooSpeed and found.FooSpeed.value, "loose values count")
assert(not found.FooMixin and not found.FooFrame and not found.SLASH_FOO1 and not found.BINDING_HEADER_FOO, "code is skipped")
assert(not found.BlizzThingDB, "Blizzard's own aren't listed")
assert(found.BarDB and found.BarDB.owner == "Bar", "empty tables count")
assert(found.OldDB and found.GoneDB, "earlier finds kept for addons that didn't load")
assert(not found.FooOld, "an addon that loaded again is found afresh")
assert(not found.TwichUIDB, "TwichUI's own come from its declaration")

---------------------------------------------------------------------------
-- Where addons stand
---------------------------------------------------------------------------
assert(SD.Status("Foo") == "loaded")
assert(SD.Status("Lazy") == "waiting")
assert(select(2, SD.Status("Offy")) == "Off")
assert(SD.Status("Gone") == "missing")
local list = SD.Addons()
assert(list[1].own and list[1].title == "TwichUI" and #list[1].vars == 5, "TwichUI first, with its five")
local byName = {}
for _, a in ipairs(list) do byName[a.name] = a end
assert(not byName.Blizzard_Thing, "Blizzard addons aren't listed")
assert(byName.Gone and byName.Gone.status == "missing" and byName.Gone.vars[1] == "GoneDB")
assert(#byName.Foo.vars == 2 and byName.Foo.vars[1] == "FooDB" and byName.Foo.vars[2] == "FooSpeed", "sorted by name")
local w = byName.Foo.working
assert(#w == 3 and w[1] == "_FooCache" and w[2] == "Foo" and w[3] == "FOO_TEXTURES", "probable working data set apart")
assert(SD.WorkingReason("WT_SpellDisplay", "WhatsTraining") == nil and SD.WorkingReason("EllesmereUIDB", "EllesmereUI") == nil,
  "saved names from the beta's files aren't caught")
assert(#byName.Bar.working == 0 and #list[1].working == 0)
assert(SD.Readable("FooDB") and not SD.Readable("OldDB"), "only loaded owners' data is readable")
assert(SD.Value("OldDB") == nil, "nothing is read for an addon that isn't loaded")

---------------------------------------------------------------------------
-- Size estimate follows the client's file format
---------------------------------------------------------------------------
local function Ser(v)
  local t = type(v)
  if t == "string" then return '"' .. (v:gsub('[\\"]', "\\%0"):gsub("\n", "\\n")) .. '"' end
  if t ~= "table" then return (t == "number") and ("%d"):format(v) or tostring(v) end
  local out = {"{\r\n"}
  for k, x in pairs(v) do
    local key = type(k) == "string" and Ser(k) or tostring(k)
    out[#out + 1] = "[" .. key .. "] = " .. Ser(x) .. ",\r\n"
  end
  return table.concat(out) .. "}"
end
local samples = {
  {"Simple", {a = "x", b = {c = 1}}},
  {"Mixed", {1, 2, "three", true, {false}, name = 'say "hi"\\now\nnext', [10] = -42, deep = {a = {b = {c = {}}}}}},
  {"Loose", "hello"}, {"Flag", false}, {"Count", 12345},
}
for _, s in ipairs(samples) do
  local exact = #(s[1] .. " = " .. Ser(s[2]) .. "\r\n")
  local r = SD.Count(s[1], s[2])
  assert(r.bytes == exact, ("%s: estimate %d, file %d"):format(s[1], r.bytes, exact))
end
assert(SD.Count("Simple", samples[1][2]).entries == 3)
local shared = {x = 1}
local withShared = SD.Count("S", {a = shared, b = shared})
assert(withShared.shared and withShared.entries == 3, "shared tables are counted once")
local loop = {}; loop.self = loop
assert(SD.Count("L", loop).entries == 1, "a table that contains itself ends")
assert(SD.Count("U", {f = function() end}).unsaved, "functions aren't saved")

-- counting a big table happens a little each frame
c.FooDB.big = {}
for i = 1, 3000 do c.FooDB.big[i] = "row" .. i end
SD.Measure("FooDB"); SD.Measure("OldDB")
assert(SD.Busy())
for _ = 1, 20 do FlushTimers() end
assert(not SD.Busy() and SD.sizes.FooDB and SD.sizes.FooDB.entries == 3005)
assert(SD.sizes.OldDB == nil, "an unreadable item isn't counted")
SD.ClearSizes()

---------------------------------------------------------------------------
-- Showing values
---------------------------------------------------------------------------
assert(SD.ShowValue("|cffff0000red|r\nx") == '"||cffff0000red||r\\nx"', "codes are shown, not used")
assert(SD.ShowValue(string.rep("é", 200), 11):find('^"ééééé"'), "cut between characters")
assert(SD.ShowKey(3) == "[3]" and SD.ShowKey("a|b") == "a||b")
assert(SD.Num(1234567) == "1,234,567" and SD.Num(-1000) == "-1,000" and SD.Num(12) == "12")
local keys = SD.Keys({b = 1, A = 1, [2] = 1, [1] = 1, [true] = 1})
assert(keys[1] == 1 and keys[2] == 2 and keys[3] == "A" and keys[4] == "b" and keys[5] == true)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
FlushTimers()                                 -- the scan opens the window
local f = c.TwichUIAddonData
assert(f, "window built after a scan from it")
f.scripts.OnShow(f)
for _ = 1, 20 do FlushTimers() end
local function Row(box, pred)
  for _, row in ipairs(box.scroll.list) do if pred(row.data) then return row end end
end
local fooRow = Row(f.left, function(d) return d.addon and d.addon.name == "Foo" end)
assert(SD.sizes.FOO_TEXTURES, "working data is counted too")
assert(fooRow.right.text == "about " .. SD.FormatSize(SD.sizes.FooDB.bytes + SD.sizes.FooSpeed.bytes), "the total leaves working data out")
assert(Row(f.left, function(d) return d.addon and d.addon.name == "Lazy" end).right.text == "Loads when needed")
fooRow.scripts.OnClick(fooRow)
local group = Row(f.left, function(d) return d.group end)
assert(group and group.right.text == 3 and not Row(f.left, function(d) return d.working end), "working data starts folded")
group.scripts.OnClick(group)
assert(Row(f.left, function(d) return d.working and d.name == "_FooCache" end), "and unfolds")
local dbRow = Row(f.left, function(d) return d.name == "FooDB" end)
assert(dbRow and dbRow.right.text:find("entries") == nil and dbRow.right.text:find("about"), dbRow.right.text)
dbRow.scripts.OnClick(dbRow)
assert(f.head.text == "FooDB")
local listRow = Row(f.tree, function(d) return d.node and d.node.key == "list" end)
assert(listRow and listRow.label.text:find("2 entries"))
listRow.scripts.OnClick(listRow)
assert(Row(f.tree, function(d) return d.node and d.node.key == 2 and d.node.value == "b" end), "opened a level")
local bigRow = Row(f.tree, function(d) return d.node and d.node.key == "big" end)
bigRow.scripts.OnClick(bigRow)
local more = Row(f.tree, function(d) return d.more end)
assert(more and more.label.text:find("2,800 left"), more and more.label.text)
more.scripts.OnClick(more)
assert(Row(f.tree, function(d) return d.more end).label.text:find("2,600 left"))
-- a loop isn't opened
c.FooDB.me = c.FooDB
dbRow.scripts.OnClick(dbRow)
local lazyRow = Row(f.left, function(d) return d.addon and d.addon.name == "Lazy" end)
lazyRow.scripts.OnClick(lazyRow)
local oldRow = Row(f.left, function(d) return d.name == "OldDB" end)
oldRow.scripts.OnClick(oldRow)
assert(f.tree.empty.text:find("isn't loaded"), "an item of an addon that isn't loaded explains why")
f:Hide(); f.scripts.OnHide(f)

-- a scan reloads with the scan queued for the next load
SD.Scan()
assert(c.reloaded and c.TwichUIDB.storedData.scanNext)

---------------------------------------------------------------------------
-- Setup sharing's addon state, as the Forever beta answers: GetAddOnInfo says
-- "loadable" for an addon off for this character only, and "not loadable,
-- DEMAND_LOADED" for a load-on-demand addon that hasn't loaded yet.
---------------------------------------------------------------------------
local ST = R.Setups
local A = c.C_AddOns
local info, enable = A.GetAddOnInfo, A.GetAddOnEnableState
A.GetAddOnInfo = function(n)
  if n == "Lazy" then return n, n, "", false, "DEMAND_LOADED", "INSECURE" end
  return info(n)
end
assert(ST.AddonState("Lazy") == "ready", "waiting to load on demand isn't off")
A.GetAddOnInfo = function(n)
  if n == "Lazy" then return n, n, "", true, "", "INSECURE" end
  return info(n)
end
A.GetAddOnEnableState = function(n, char)
  if n == "Lazy" then return (char == c.UnitGUID("player")) and 0 or 1 end
  return enable(n, char)
end
assert(ST.AddonState("Lazy") == "disabled", "off for this character only")
A.GetAddOnInfo, A.GetAddOnEnableState = info, enable
assert(ST.AddonState("Foo") == "ready" and ST.AddonState("Offy") == "disabled" and ST.AddonState("Gone") == "missing")
print("STORED DATA TESTS PASSED")
