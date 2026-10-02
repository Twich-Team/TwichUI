dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = tostring(v or "") end end
    if k == "GetChecked" then return function(s) return s.checked end end
    if k == "SetChecked" then return function(s, v) s.checked = v end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true; if rawget(s, "scripts") and s.scripts.OnShow then s.scripts.OnShow(s) end end end
    if k == "Hide" then return function(s) s.shown = false; if rawget(s, "scripts") and s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "SetShown" then return function(s, v) s.shown = v end end
    if k == "GetFrameLevel" then return function() return 1 end end
    if k == "SetScript" then return function(s, n, fn) local t = rawget(s, "scripts"); if not t then t = {}; rawset(s, "scripts", t) end; t[n] = fn end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    return function() end
  end})
end
c.tinsert = table.insert; ALL = {}
c.CreateFrame = function(_, name) local o = Obj(); ALL[#ALL + 1] = o; if name then c[name] = o end return o end
c.UISpecialFrames = {}; c.UIParent = Obj(); c.GameTooltip = Obj()
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function() end
c.CANCEL = "Cancel"; c.Settings = nil; c.TwichUIDB = {}
for _, file in ipairs({"chronicle/Style.lua", "chronicle/Window.lua"}) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local W, C = c.TwichUI.ChronicleWindow, c.TwichUI.Chronicle

-- A client in New York: UTC-5, then UTC-4 from 2026-03-08 07:00 UTC. The clock is the test's, not this machine's.
local DST = 1772953200
c.date = function(fmt, t) return os.date("!" .. fmt, t + (t < DST and -18000 or -14400)) end

-- calendar arithmetic
assert(C.AddDays(20261231, 1) == 20270101)
assert(C.AddDays(20240301, -1) == 20240229 and C.AddDays(20250301, -1) == 20250228)
assert(C.AddDays(20261002, -6) == 20260926 and C.AddDays(20261002, -29) == 20260903)
assert(C.AddDays(20260308, 1) == 20260309 and C.AddDays(20260309, -1) == 20260308)
assert(C.Weekday(2026, 10, 2) == 5, "Oct 2 2026 is a Friday")
assert(C.DaysInMonth(2024, 2) == 29 and C.DaysInMonth(1900, 2) == 28 and C.DaysInMonth(2000, 2) == 29)

-- day keys follow local midnight, also across the daylight-saving change
assert(C.DayKey(1772953199) == 20260308 and C.DayKey(1772953200) == 20260308, "the short day stays one day")
assert(C.DayKey(1773028799) == 20260308, "23:59:59 local")
assert(C.DayKey(1773028800) == 20260309, "00:00:00 local")
assert(C.DayKey(1790999999) == 20261002 and C.DayKey(1791000000) == 20261003)
-- unreadable timestamps have no day
for _, bad in ipairs({ -5, 1e15, 0/0, "x", true }) do assert(C.DayKey(bad) == nil, tostring(bad)) end

-- entries (some with unreadable timestamps, which the loader would drop; they are put in directly here)
local rec = C.Record()
rec.entries = {}
local function Put(id, t) rec.entries[#rec.entries + 1] = { id = id, t = t, kind = "note", title = "Note", note = "n" .. id } end
Put(1, 1790438400)    -- Sep 26 noon
Put(2, 1790956800)    -- Oct 2 noon
Put(3, 1790999999)    -- Oct 2 23:59:59
Put(4, 1791000000)    -- Oct 3 00:00:00
Put(5, 1e15)          -- no usable date
Put(6, 0/0)           -- no usable date
rec.nextId = 7
local function Snapshot()
  local out = {}
  for _, e in ipairs(rec.entries) do out[#out + 1] = ("%s|%s|%s|%s"):format(tostring(e.id), tostring(e.t), e.kind, e.note) end
  return table.concat(out, ";")
end
local before = Snapshot()
local function Shown() local n = 0 for _, e in ipairs(rec.entries) do if C.Matches(e) then n = n + 1 end end return n end

assert(not C.FilterActive() and C.FilterLabel() == "All time" and Shown() == 6, "default shows everything, undated included")
C.SetFilter("day", 20261002); assert(Shown() == 2 and C.FilterLabel() == "On Oct 02, 2026")
C.SetFilter("since", 20261002); assert(Shown() == 3 and C.FilterLabel() == "Since Oct 02, 2026")
C.SetFilter("since", 20260926); assert(Shown() == 4, "undated entries never match a date")
C.SetFilter("day", 20260101); assert(Shown() == 0)
C.SetFilter("bogus", 1); assert(not C.FilterActive(), "bad input means All time")
C.SetFilter("day", nil); assert(not C.FilterActive())
local counts, undated = C.DayCounts()
assert(counts[20261002] == 2 and counts[20261003] == 1 and counts[20260926] == 1 and undated == 2)

-- window: header count, empty result, shortcuts, calendar
local f
W:Show(); f = c.TwichUIChronicle
c.time = function() return 1790956800 end                 -- "now" is Oct 2 2026, noon
local function Click(label)
  for _, o in ipairs(ALL) do
    if type(rawget(o, "text")) == "table" and o.text.text == label and o.scripts and o.scripts.OnClick then o.scripts.OnClick(o) return end
  end
  error("no button " .. label)
end
assert(f.filter.text.text == "All time" and f.sub.text:find("6 entries"), f.sub.text)
f.filter.scripts.OnClick(f.filter)                         -- opens the calendar
local pop = c.TwichUIChronicleDate
assert(pop and pop.shown and pop.title.text == "October 2026", pop and pop.title.text)
local cell
for _, cl in ipairs(pop.cells) do if cl.shown and cl.day == 20261002 then cell = cl end end
assert(cell and cell.dot.shown == true and cell.today.shown == true, "marker and today on Oct 2")
local quiet; for _, cl in ipairs(pop.cells) do if cl.shown and cl.day == 20261015 then quiet = cl end end
assert(quiet and quiet.dot.shown == false, "no marker without entries")
cell.scripts.OnClick(cell)                                 -- That day
assert(f.filter.text.text == "On Oct 02, 2026" and f.sub.text:find("2 of 6 entries"), f.sub.text)
assert(f.undated.text:find("2 entries without a date"), f.undated.text)
pop.sinceBtn.scripts.OnClick(pop.sinceBtn)                 -- Since this day, same day
assert(f.filter.text.text == "Since Oct 02, 2026" and f.sub.text:find("3 of 6 entries"), f.sub.text)
-- month and year navigation
Click("<"); assert(pop.title.text == "September 2026")
Click("<<"); assert(pop.title.text == "September 2025")
Click(">>"); Click(">"); assert(pop.title.text == "October 2026")
for _ = 1, 3 do Click(">") end; assert(pop.title.text == "January 2027")
Click("<"); Click("<"); Click("<"); Click("<")
local sepCell; for _, cl in ipairs(pop.cells) do if cl.shown and cl.day == 20260926 then sepCell = cl end end
assert(pop.title.text == "September 2026" and sepCell.dot.shown, "Sep 26 has an entry")
Click(">")
pop.dayBtn.scripts.OnClick(pop.dayBtn)
assert(f.filter.text.text == "On Oct 02, 2026")
-- shortcuts (now is Oct 2): Today, Last 7 days (Sep 26 on), Last 30 days, Clear filter
Click("Today"); assert(f.filter.text.text == "On Oct 02, 2026" and not pop.shown)
Click("Last 7 days"); assert(f.filter.text.text == "Since Sep 26, 2026" and f.sub.text:find("4 of 6"))
Click("Last 30 days"); assert(f.filter.text.text == "Since Sep 03, 2026")
Click("Clear filter"); assert(f.filter.text.text == "All time" and f.sub.text:find("6 entries"))
-- an empty day
C.SetFilter("day", 20260101); W:Refresh()
assert(f.noMatch.shown and f.noMatchText.text == "No entries on Jan 01, 2026.", f.noMatchText.text)
assert(f.sub.text:find("0 of 6 entries"))
C.SetFilter("since", 20260101); W:Refresh()
assert(not f.noMatch.shown and f.sub.text:find("4 of 6"))
C.SetFilter("since", 20270101); W:Refresh()
assert(f.noMatch.shown and f.noMatchText.text == "No entries since Jan 01, 2027.")
-- the filter changed nothing that is stored
assert(Snapshot() == before, "entries untouched")
-- closing the window returns to All time
f.scripts.OnHide()
assert(not C.FilterActive() and not pop.shown)
W:Show(); assert(f.filter.text.text == "All time" and f.sub.text:find("6 entries") and not f.noMatch.shown)
assert(Snapshot() == before)
print("CHRONICLE FILTER OK")
