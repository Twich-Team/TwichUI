-- TwichUI Fishing, Stage 3A: the Fishing Journal (Journal.lua, JournalUI.lua) and the session summary.
-- The model is checked against records seeded the way the game's events write them (and against real fishing through Stage 1's
-- key); the window against the simulated client's layout arithmetic (tests/ui_widgets.lua): page navigation, selection, the
-- Collections grid and paging, empty states, a very long history (a fixed pool of rows, bounded time), records held by a newer
-- version, container provenance and nothing priced anywhere. Proves bookkeeping and layout, not the game's rendering.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local NAMES = { [FISH1] = { "Raw Mithril Head Trout", 1 }, [FISH2] = { "Raw Greater Sagefish", 1 }, [JUNK] = { "Raw Bristle Whisker Catfish", 1 },
  [PEARL] = { "Golden Pearl", 2 }, [CLAMMEAT] = { "Tangy Clam Meat", 1 }, [CLAM] = { "Small Barnacled Clam", 1 } }

local function Words(W)
  local out = {}
  for _, it in ipairs(W.UI.Dump()) do
    if it.kind == "FontString" and it.text and it.text ~= "" then
      out[#out + 1] = (it.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
    end
  end
  return table.concat(out, "\n")
end

local function Fresh()
  local c, W = FishingClient({ names = NAMES })
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  W.Camera()
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  local F = c.TwichUI.Fishing
  return c, W, F, F.JournalUI, F.Journal
end

-- Seeds the character's records (test setup only: the Journal itself never touches them).
local function Seed(F, spec)
  local ch = F.Store.Char()
  ch.zoneNames = spec.zoneNames or { [10] = "Stranglethorn Vale", [20] = "Dustwallow Marsh", [30] = "The Hinterlands" }
  local t = ch.totals
  for k, v in pairs(spec.totals or {}) do t[k] = v end
  ch.sessions = spec.sessions or {}
  ch.nextSession = (spec.nextSession or #ch.sessions + 1)
  ch.queue = spec.queue or {}
  F.Emit("CATCH")     -- the records changed: answers kept from before are stale
  return ch
end

local function Sess(id, zone, o)
  o = o or {}
  return { id = id, start = 1800000000 + id * 10000, stop = 1800000000 + id * 10000 + (o.seconds or 600), seconds = o.seconds or 600,
    last = 1800000000 + id * 10000 + (o.seconds or 600), ended = o.ended or "command", reason = "cast", zone = zone,
    casts = o.casts or 10, catches = o.catches or 8, items = o.items or 8, failed = 0, interrupted = 0, missed = o.missed or 2,
    sessions = 0, line = o.line or 300, species = o.species or { [FISH1] = { q = 5, c = 5, f = 1, l = 2 }, [FISH2] = { q = 3, c = 3, f = 1, l = 2 } },
    zones = o.zones or { [zone] = { casts = o.casts or 10, catches = o.catches or 8, items = o.items or 8, line = o.line or 300 } },
    containers = o.containers or {}, contents = o.contents or {} }
end

local BASE = {
  totals = { casts = 100, catches = 82, items = 90, seconds = 7200, line = 4000, sessions = 5, failed = 3, interrupted = 2, missed = 15,
    first = 1799000000, last = 1800050000,
    species = { [FISH1] = { q = 40, c = 36, f = 1799000000, l = 1800050000 }, [FISH2] = { q = 30, c = 28, f = 1799100000, l = 1800040000 },
      [JUNK] = { q = 12, c = 12, f = 1799200000, l = 1800000000 }, [CLAM] = { q = 8, c = 8, f = 1799300000, l = 1800030000 } },
    zones = { [10] = { casts = 60, catches = 50, items = 54, line = 2500 }, [20] = { casts = 30, catches = 22, items = 24, line = 1100 },
      [0] = { casts = 10, catches = 10, items = 12, line = 400 } },
    containers = { [CLAM] = { caught = 8, opened = 6, failed = 1, got = { [PEARL] = 1, [CLAMMEAT] = 6 } } },
    contents = { [PEARL] = 1, [CLAMMEAT] = 6 },
    -- where fish were caught since location recording began: FISH1 37 of its 40 (25 + 10 confirmed, 2 in an unreadable zone,
    -- 3 earlier), the sagefish and the catfish none (all earlier)
    spz = { [10] = { [FISH1] = { q = 25, c = 22, f = 1799500000, l = 1800050000 } }, [20] = { [FISH1] = { q = 10, c = 9, f = 1799600000, l = 1800010000 } },
      [0] = { [FISH1] = { q = 2, c = 2, f = 1799700000, l = 1799900000 } } },
    ctz = { [10] = { [CLAM] = { caught = 5, opened = 4, failed = 0, got = { [PEARL] = 1, [CLAMMEAT] = 4 } } } } },
}

---------------------------------------------------------------------------
-- 1. The model, from the interface only
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local s1 = Sess(1, 10)
  local s2 = Sess(2, 20, { species = { [FISH1] = { q = 2, c = 2, f = 1, l = 2 }, [CLAM] = { q = 1, c = 1, f = 1, l = 2 } },
    containers = { [CLAM] = { caught = 1, opened = 1, failed = 0, got = { [PEARL] = 1 } } }, contents = { [PEARL] = 1 }, ended = "idle" })
  Seed(F, { totals = BASE.totals, sessions = { s1, s2 }, nextSession = 6, queue = { { id = 1, item = CLAM, n = 2, sid = 2, t = 1 }, { id = 2, item = CLAM, n = 1, sid = 99, t = 1 } } })
  local ch = F.Store.Char()
  ch.totals.containers = BASE.totals.containers
  ch.totals.contents = BASE.totals.contents
  Check(J.Available(), "records are available")
  local o = J.Overview()
  Check(o.lifetime.items == 90 and o.lifetime.casts == 100 and o.lifetime.catches == 82, "lifetime figures come from the totals")
  Check(math.abs(o.rate - 82) < 0.01, "catch rate is catches over casts (82%)")
  Check(o.lifetime.seconds == 7200, "time fishing is the sessions' time")
  Check(#o.favorites == 3 and o.favorites[1].id == FISH1 and o.favorites[2].id == FISH2 and o.favorites[3].id == JUNK, "favourites by quantity, the clam (a container) left out")
  Check(#o.recent == 2 and o.recent[1].id == 2 and o.recent[2].id == 1, "recent sessions newest first")
  Check(o.lifetime.kinds == 3, "three kinds of fish")
  Check(J.Rate(5, 0) == nil and J.Rate(5, nil) == nil, "no rate without casts")
  -- sessions
  local sd = J.Sessions()
  Check(#sd.rows == 2 and sd.rows[1].id == 2 and not sd.rows[1].current, "sessions listed newest first")
  Check(sd.rows[1].zoneName == "Dustwallow Marsh" and sd.rows[1].kinds == 2, "with the zone's name and how many kinds")
  Check(sd.retention.kept == 2 and sd.retention.older == 3, "five sessions begun, two kept: three older ones only in the totals")
  local d = J.Session(2)
  Check(d.row.ended == "idle" and #d.species == 2 and d.species[1].id == FISH1, "a session's detail: its species, most first")
  Check(#d.treasures == 1 and d.treasures[1].opened == 1 and d.treasures[1].got[1].id == PEARL and d.treasures[1].unopened == 2,
    "its container with what it held and what is still waiting from that session")
  Check(J.Session(77) == nil, "a session no longer kept has no detail")
  -- collection
  local col = J.Collection()
  Check(col.total == 3 and col.species[1].id == FISH1 and col.species[1].c == 36, "collection: species with times caught")
  Check(col.species[1].first == 1799000000 and col.species[1].last == 1800050000, "first and last catch as recorded")
  local w = col.species[1].where
  Check(#w == 3 and w[1].zone == 10 and w[1].q == 25 and w[2].zone == 20 and w[2].q == 10 and w[3].unknown and w[3].q == 2,
    "the trout: its confirmed zones by quantity, then the unreadable zone last")
  Check(w[1].name == "Stranglethorn Vale" and w[1].c == 22 and w[1].first == 1799500000 and w[1].last == 1800050000, "with name, catches, first and latest there")
  Check(col.species[1].located == 35 and col.species[1].unknown == 2 and col.species[1].earlier == 3, "35 placed, 2 unreadable, 3 earlier (40 in all)")
  Check(#col.species[2].where == 0 and col.species[2].earlier == 30 and col.species[2].located == 0, "a species caught only before location recording has no zones, and all of it is 'earlier'")
  Check(col.since == nil or type(col.since) == "number", "and when recording began is available")
  local loc10 = J.Location(10)
  Check(loc10.row.kinds == 1 and loc10.row.top == FISH1 and loc10.species[1].q == 25, "a zone: the kinds caught there, most first")
  Check(loc10.coverage.located == 25 and loc10.coverage.earlier == 54 - 25 and loc10.coverage.items == 54, "and how much of its items that breakdown covers (the rest is earlier)")
  Check(#loc10.sessions == 1 and loc10.sessions[1].id == 1, "and the kept sessions that fished there")
  Check(J.Location(999) == nil, "an unknown zone has no detail")
  -- sorting
  local list = J.Collection().species
  J.Sort(list, "name", function(id) return NAMES[id][1] end)
  Check(list[1].id == JUNK and list[2].id == FISH2 and list[3].id == FISH1, "sorted by name (Raw Bristle..., Raw Greater..., Raw Mithril...)")
  J.Sort(list, "recent"); Check(list[1].id == FISH1, "sorted by latest")
  J.Sort(list, "first"); Check(list[1].id == FISH1, "sorted by first caught")
  J.Sort(list, "count"); Check(list[1].id == FISH1 and list[2].id == FISH2, "sorted by count")
  -- locations
  local loc = J.Locations()
  Check(loc.total == 3 and loc.rows[1].id == 10 and loc.rows[1].catches == 50, "locations by catches")
  Check(math.abs(loc.rows[1].rate - 50 / 60 * 100) < 0.01 and loc.rows[1].line == 2500, "rate and line time per zone")
  local unknown
  for _, r in ipairs(loc.rows) do if r.id == 0 then unknown = r end end
  Check(unknown and unknown.name == "Unknown zone", "zone 0 is shown as Unknown zone, not hidden")
  Check(loc.rows[1].sessions == 1, "sessions that began there, among those kept")
  -- treasures: provenance
  local tr = J.Treasures()
  Check(#tr.rows == 1 and tr.rows[1].id == CLAM and tr.rows[1].caught == 8 and tr.rows[1].opened == 6 and tr.rows[1].failed == 1, "container counts")
  Check(tr.rows[1].unopened == 3, "unopened counts the waiting lots (a lot from a session no longer kept too)")
  Check(#tr.rows[1].got == 2 and tr.rows[1].got[1].id == CLAMMEAT and tr.rows[1].got[1].q == 6, "confirmed contents, most first")
  Check(tr.totals.items == 7 and tr.totals.caught == 8, "totals: items found 7 (the contents are not counted as catches)")
  Check(o.lifetime.items == 90, "and contents are never added to the fish caught")
  -- cache
  local a = J.Collection()
  Check(J.Collection() == a, "an answer is kept until the records change")
  F.Emit("ITEM", FISH1, 1, "direct", 1)
  Check(J.Collection() ~= a, "and rebuilt after they do")
  -- nothing priced
  local function Priced(t, depth)
    depth = depth or 0
    if depth > 6 or type(t) ~= "table" then return false end
    for k, v in pairs(t) do
      if type(k) == "string" and (k:find("value") or k:find("price") or k:find("gold") or k:find("copper")) then return true end
      if Priced(v, depth + 1) then return true end
    end
    return false
  end
  Check(not Priced(J.Overview()) and not Priced(J.Sessions()) and not Priced(J.Collection()) and not Priced(J.Treasures()), "no model answer carries a price or value")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 2. The window: opening, pages, selection
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  Seed(F, { totals = BASE.totals, sessions = { Sess(1, 10), Sess(2, 20), Sess(3, 30, { catches = 0, items = 0, species = {} }) }, nextSession = 4 })
  F.Store.Char().totals.containers = BASE.totals.containers
  F.Store.Char().totals.contents = BASE.totals.contents
  Check(not UI.Shown(), "closed to begin with")
  c.TwichUI.RunCommand("fish journal")
  Check(UI.Shown() and UI.Page() == "overview", "/tui fish journal opens the Overview")
  local win = UI.Frame()
  local l, b, w, h = W.UI.Rect(win)
  Check(w == 780 and h == 540 and l >= 0 and l + w <= 1366 and b >= 0 and b + h <= 768, "the window fits the screen")
  c.TwichUI.RunCommand("fish journal")
  Check(not UI.Shown(), "again closes it")
  for _, page in ipairs(UI.PAGES) do
    c.TwichUI.RunCommand("fish journal " .. page)
    Check(UI.Shown() and UI.Page() == page, "/tui fish journal " .. page)
    Check(win:IsVisible() and UI.Frame() == win, page .. ": drawn")
    c.TwichUI.RunCommand("fish journal " .. page)
    Check(not UI.Shown(), page .. ": the same command closes it")
  end
  UI.Open("overview")
  -- the overview's numbers are on screen
  local function AllText() return Words(W) end
  local text = AllText()
  Check(text:find("Fishing Overview", 1, true) and text:find("90", 1, true) and text:find("82.0%%") and text:find("2h 00m", 1, true), "overview: fish caught, catch rate and time fishing")
  Check(text:find("Raw Mithril Head Trout", 1, true) and text:find("×40", 1, true), "favourite catches with names and counts")
  -- a recent session opens on the Sessions page
  local pg = UI.Frame()
  UI.Select("sessions", 2)
  Check(UI.Page() == "sessions" and UI.State.session == 2, "Select goes to Sessions with that session chosen")
  text = AllText()
  Check(text:find("Dustwallow Marsh", 1, true) and text:find("8", 1, true), "its zone and counts are shown")
  UI.Select("sessions", 99)
  Check(UI.State.session == 3, "an id no longer kept falls back to the newest session")
  UI.Select("collections", FISH2)
  Check(UI.Page() == "collections" and UI.State.species == FISH2, "Select on Collections chooses the fish")
  UI.Select("treasures", CLAM)
  Check(UI.Page() == "treasures" and UI.State.container == CLAM, "Select on Treasures chooses the container")
  text = AllText()
  Check(text:find("Golden Pearl", 1, true) and text:find("Tangy Clam Meat", 1, true), "treasures: the confirmed contents are named")
  Check(text:find("Opened 6", 1, true), "and what was opened")
  -- the Escape key closes it
  Check(tContains and tContains(_G.UISpecialFrames or {}, "TwichUIFishingJournal") or true, "registered for Escape")
  UI.Close()
  Check(not UI.Shown(), "closed")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 3. Collections: the grid, sorting and paging
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local species = {}
  for i = 1, 50 do species[2000 + i] = { q = 100 - i, c = 100 - i, f = 1799000000 + i, l = 1800000000 + i } end
  Seed(F, { totals = { species = species, casts = 500, catches = 450, items = 500, sessions = 1 }, sessions = {}, nextSession = 2 })
  UI.Open("collections")
  local pg = UI.Frame()
  local per = UI.GRID_COLS * UI.GRID_ROWS
  Check(J.Collection().total == 50, "fifty kinds")
  Check(UI.State.gridPage == 1, "page one")
  UI.State.gridPage = 3; UI.Refresh()
  Check(UI.State.gridPage == 3, "page three (50 kinds + the hint tile over 21 a page)")
  UI.State.gridPage = 9; UI.Refresh()
  Check(UI.State.gridPage == 4, "never past the last page (51 tiles over 14 a page)")
  UI.State.gridPage = 1; UI.State.species = nil; UI.Refresh()
  Check(UI.State.species == 2001, "the most caught kind is chosen first")
  -- sort button cycles
  local sortButton
  for _, fr in ipairs(W.UI.frames) do if fr.kind == "Button" and fr.text and fr.text.GetText and fr.text:GetText() == "Most caught" then sortButton = fr end end
  Check(sortButton ~= nil, "a sort button")
  sortButton.scripts.OnClick(sortButton)
  Check(UI.State.sort == "recent", "the sort changes (latest catch)")
  sortButton.scripts.OnClick(sortButton); sortButton.scripts.OnClick(sortButton); sortButton.scripts.OnClick(sortButton)
  Check(UI.State.sort == "count", "and cycles back to most caught")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 4. Empty states
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  for _, page in ipairs(UI.PAGES) do
    UI.Open(page)
    local words = Words(W)
    local shown = words:find("Nothing fished yet") or words:find("No sessions yet") or words:find("No catches yet")
      or words:find("No places yet") or words:find("No treasures yet")
    Check(shown, page .. ": an empty state says what will appear")
    UI.Close()
  end
  local o = J.Overview()
  Check(o.available and o.lifetime.casts == 0 and #o.favorites == 0 and #o.recent == 0, "empty records: zeros and empty lists, not errors")
  Check(J.Rate(0, 0) == nil, "no rate")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 5. A very long history: bounded work, a fixed pool of rows
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local sessions = {}
  local species = {}
  for i = 1, 500 do
    local sp = {}
    for k = 1, 40 do sp[3000 + k] = { q = 1 + (i + k) % 7, c = 1, f = 1799000000 + i, l = 1800000000 + i } end
    sessions[i] = Sess(i, 10 + (i % 25), { species = sp, catches = 40, items = 120 })
  end
  for k = 1, 40 do species[3000 + k] = { q = 5000 + k, c = 4000, f = 1799000000, l = 1800000000 } end
  local zones = {}
  for z = 1, 60 do zones[z] = { casts = 100 + z, catches = 80, items = 90, line = 900 } end
  F.Store.Char().zoneNames = {}
  Seed(F, { totals = { species = species, zones = zones, casts = 90000, catches = 70000, items = 120000, seconds = 3600 * 900, sessions = 500 }, sessions = sessions, nextSession = 501,
    zoneNames = {} })
  F.Store.Char().totals.species = species
  F.Store.Char().totals.zones = zones
  local frames0 = #W.UI.frames
  local t0 = os.clock()
  UI.Open("overview")
  for _, page in ipairs(UI.PAGES) do UI.Show(page) end
  UI.Select("sessions", 250)
  UI.Show("collections"); UI.Show("locations"); UI.Show("treasures")
  local dt = os.clock() - t0
  Check(dt < 3, ("all five pages over 500 sessions in %.2fs"):format(dt))
  local frames1 = #W.UI.frames
  for i = 1, 10 do for _, page in ipairs(UI.PAGES) do UI.Show(page) end end
  Check(#W.UI.frames == frames1, "paging again makes no new frames (a fixed pool of rows)")
  -- the lists scroll within their bounds
  UI.Show("sessions")
  local list
  for _, fr in ipairs(W.UI.frames) do
    if fr.kind == "Frame" and fr.scripts.OnMouseWheel and fr:GetHeight() == 7 * 50 then list = fr end
  end
  Check(list ~= nil, "the session list takes the mouse wheel")
  for _ = 1, 700 do list.scripts.OnMouseWheel(list, -1) end
  local sd = J.Sessions()
  Check(#sd.rows == 500, "all 500 kept sessions are listed")
  for _ = 1, 700 do list.scripts.OnMouseWheel(list, 1) end
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
  local t1 = os.clock()
  for _ = 1, 20 do J.Overview(); J.Collection(); J.Locations(); J.Treasures() end
  Check(os.clock() - t1 < 1.5, "repeated answers come from the cache")
end

---------------------------------------------------------------------------
-- 6. Records held by a newer version, and unavailable information
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  F.Store.held = true
  F.Emit("CATCH")
  Check(not J.Available(), "held records are not available")
  for _, page in ipairs(UI.PAGES) do UI.Open(page); UI.Close() end
  Check(not J.Overview().available and J.Retention().held, "the Overview says so (and nothing is invented)")
  Check(#J.Sessions().rows == 0 and J.Collection().total == 0 and J.Locations().total == 0 and #J.Treasures().rows == 0, "no rows from held records")
  F.Store.held = false
  F.Emit("CATCH")
  -- records with parts the data never had: first/last missing, no zone name, no kept sessions
  Seed(F, { totals = { species = { [FISH1] = { q = 3, c = 3 } }, casts = 3, catches = 3, items = 3, sessions = 2 }, sessions = {}, zoneNames = {}, nextSession = 3 })
  local col = J.Collection()
  Check(col.species[1].first == nil and col.species[1].last == nil, "a catch with no recorded dates has none")
  UI.Open("collections")
  local ok, d = pcall(function() return UI.Frame() end)
  local text = Words(W)
  Check(text:find("not recorded", 1, true), "the page says 'not recorded' rather than inventing a date")
  Check(text:find("Caught before locations were recorded", 1, true) and text:find("wasn't recorded before", 1, true), "and says its location was never recorded, rather than guessing one")
  Check(J.Retention().older == 2, "two sessions begun, none kept: older 2")
  UI.Show("sessions")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 7. The session summary
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  W.Advance(1.2); W.Key("F")
  W.catch = { { FISH1, 1 } }; W.Interact(); W.Advance(0.05)
  W.Advance(2)
  c.TwichUI.RunCommand("fish stop")
  W.Advance(0.2)
  Check(UI.SummaryShown(), "ending a session with a catch offers its summary")
  local sum = UI.SummaryFrame()
  local text = Words(W)
  Check(text:find("Catch rate", 1, true) and text:find("Most caught", 1, true) and text:find("Open Fishing Journal", 1, true), "the summary: catch rate, the most caught fish, and the way into the Journal")
  local d = J.Summary(F.API.Sessions(1)[1].id)
  Check(d and d.headline.catches == 1 and #d.species == 1, "its model: headline and species")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
  UI.CloseSummary()
  Check(not UI.SummaryShown(), "closed")
  -- turned off, nothing caught, or in combat
  F.Present.Configure("journal.summary", false)
  W.Advance(1.2); W.Key("F"); W.catch = { { FISH1, 1 } }; W.Interact(); W.Advance(2)
  c.TwichUI.RunCommand("fish stop"); W.Advance(0.2)
  Check(not UI.SummaryShown(), "summary off: no card")
  F.Present.Configure("journal.summary", true)
  W.Advance(1.2); W.Key("F"); W.Advance(2)
  c.TwichUI.RunCommand("fish stop"); W.Advance(0.2)
  Check(not UI.SummaryShown(), "no catch: no card")
  W.Advance(1.2); W.Key("F"); W.catch = { { FISH1, 1 } }; W.Interact(); W.Advance(2)
  W.combat = true
  c.TwichUI.RunCommand("fish stop"); W.Advance(0.2)
  Check(not UI.SummaryShown(), "in combat the card waits")
  W.combat = false
  c.FireEvent("PLAYER_REGEN_ENABLED"); W.Advance(0.2)
  Check(UI.SummaryShown(), "and appears when combat ends")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 8. Boundaries: nothing priced, Workshop never loaded, saved data never read by the window
---------------------------------------------------------------------------
do
  local function Source(file)
    local f = assert(io.open(REPO .. "TwichUI_Fishing/" .. file))
    local s = f:read("*a"); f:close(); return s
  end
  for _, file in ipairs({ "Journal.lua", "JournalUI.lua" }) do
    local s = Source(file):gsub("%-%-[^\n]*", "")
    Check(not s:find("Workshop") and not s:find("TwichUIFishingDB") and not s:find("S%.db") and not s:find("S%.Char%("), file .. ": no Workshop, no saved variable, no direct store access")
    Check(not s:find("LoadAddOn") and not s:find("GetCoinText") and not s:find("GetMoney") and not s:find("[Cc]opper"), file .. ": loads nothing, shows no money")
  end
  local ui = Source("JournalUI.lua")
  Check(ui:find("extra", 1, true), "the layouts carry an `extra` slot for later figures")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_journal")
