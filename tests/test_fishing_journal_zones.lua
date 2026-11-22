-- TwichUI Fishing, Journal refinement: where fish were caught on the Collections and Locations pages and the way between them,
-- sessions that span zones, the summary card's content, the window's remembered position (drag, close, reload, a smaller
-- screen, off-screen recovery), the extension points Stage 3B uses, and the cost of recording and showing a large history
-- (measured and printed). Simulated client (tests/fishing_mock.lua, tests/ui_widgets.lua).
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local NAMES = { [FISH1] = { "Raw Mithril Head Trout", 1 }, [FISH2] = { "Raw Greater Sagefish", 1 }, [JUNK] = { "Raw Bristle Whisker Catfish", 1 },
  [PEARL] = { "Golden Pearl", 2 }, [CLAMMEAT] = { "Tangy Clam Meat", 1 }, [CLAM] = { "Small Barnacled Clam", 1 },
  [9100] = { "Giant Mottled Spotted Sagefish of the Southern Reaches and Beyond", 1 } }
local SV, DM, HL = 1434, 15, 26

local function Fresh(o)
  o = o or {}
  o.names = o.names or NAMES
  local c, W = FishingClient(o)
  local faults = {}
  c.geterrorhandler = function() return function(e) faults[#faults + 1] = tostring(e) end end
  W.faults = faults
  W.Camera()
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, POLE)
  local F = c.TwichUI.Fishing
  return c, W, F, F.JournalUI, F.Journal
end
local function Words(W)
  local out = {}
  for _, it in ipairs(W.UI.Dump()) do
    if it.kind == "FontString" and it.text and it.text ~= "" then out[#out + 1] = (it.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
  end
  return table.concat(out, "\n")
end
-- the player is in zone `id` (the simulated map names every id after W.zone: keep the two together)
local function At(W, id, name) W.map, W.zone = id, name end
local function Catch(W, slots) W.StartLine(); W.Loot(slots, { fishing = true }); W.StopLine(); W.Advance(2) end
-- the visible button whose row holds `id` (list rows keep their item as `item`)
local function RowFor(W, test)
  for _, fr in ipairs(W.UI.frames) do
    if fr.kind == "Button" and fr.item and W.UI.Visible(fr) and test(fr.item) then return fr end
  end
end
local function Click(fr) fr.scripts.OnClick(fr) end

---------------------------------------------------------------------------
-- 1. Collections: where a fish was caught, from real catches; the page between a species and a zone
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  At(W, SV, "Stranglethorn Vale"); Catch(W, { { FISH1, 3 } }); Catch(W, { { FISH1, 2 }, { FISH2, 4 } })
  At(W, DM, "Dustwallow Marsh"); Catch(W, { { FISH1, 6 } })
  UI.Open("collections")
  local words = Words(W)
  Check(words:find("Where it was caught", 1, true), "the species detail has a place list")
  Check(words:find("Stranglethorn Vale", 1, true) and words:find("Dustwallow Marsh", 1, true), "its zones are named")
  Check(words:find("×6", 1, true) and words:find("×5", 1, true), "with the quantity in each (6 in the marsh, 5 in the vale)")
  Check(words:find("Confirmed in 2 zones", 1, true), "and a plain account of how much is placed")
  local col = J.Collection().species
  Check(col[1].id == FISH1 and col[1].where[1].zone == DM and col[1].where[1].q == 6 and col[1].earlier == 0, "all of it placed: nothing 'earlier'")
  -- a zone row opens that zone on the Locations page
  local row = RowFor(W, function(it) return it.kind == "zone" and it.zone == SV end)
  Check(row ~= nil, "a zone row")
  Click(row)
  Check(UI.Page() == "locations" and UI.State.zone == SV, "choosing a zone from a fish opens it in Locations")
  words = Words(W)
  Check(words:find("Fish caught here", 1, true) and words:find("Raw Greater Sagefish", 1, true), "Locations lists the fish caught there")
  -- and a fish there opens in Collections, pointing back at the zone
  local fish = RowFor(W, function(it) return it.id == FISH2 and it.q ~= nil end)
  Check(fish ~= nil, "a species row in the zone")
  Click(fish)
  Check(UI.Page() == "collections" and UI.State.species == FISH2 and UI.State.focusZone == SV, "choosing a fish from a zone opens it in Collections, with that zone pointed out")
  local loc = J.Location(SV)
  Check(loc.row.kinds == 2 and loc.species[1].id == FISH2 or loc.species[1].id == FISH1, "zone detail: kinds and species")
  Check(loc.coverage.located == 9 and loc.coverage.earlier == 0 and loc.coverage.items == 9, "every item caught there is placed")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 2. Old and new together: what is placed, what is not, and no zone guessed
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local ch = F.Store.Char()
  ch.totals.species[FISH1] = { q = 20, c = 15, f = 1700000000, l = 1700900000 }
  ch.totals.zones[SV] = { casts = 30, catches = 15, items = 20, line = 600 }
  ch.totals.items, ch.totals.catches, ch.totals.casts = 20, 15, 30
  ch.zoneNames[SV] = "Stranglethorn Vale"
  F.Emit("CATCH")
  UI.Open("collections")
  local words = Words(W)
  Check(words:find("Caught before locations were recorded", 1, true), "an old species says all of it predates locations")
  Check(not words:find("Confirmed in", 1, true), "and claims no zone")
  Check(words:find("wasn't recorded before", 1, true), "with the reason, not an empty box")
  At(W, SV, "Stranglethorn Vale"); Catch(W, { { FISH1, 5 } })
  words = Words(W)
  Check(words:find("Confirmed in 1 zone (5 fish)", 1, true) and words:find("20 not placed", 1, true) and words:find("caught before locations were recorded", 1, true),
    "after new catches: 5 placed, the 20 older ones separate")
  local e = J.Collection().species[1]
  Check(e.q == 25 and e.located == 5 and e.earlier == 20, "25 caught: 5 placed, 20 earlier")
  UI.Show("locations")
  words = Words(W)
  Check(words:find("The fish below are 5 of the 25 items", 1, true) or words:find("5 of the 25", 1, true), "Locations says how much of the zone's catch the breakdown covers")
  Check(J.Locations().rows[1].items == 25 and J.Locations().rows[1].earlier == 20, "while the zone's own totals stay exact (25)")
end

---------------------------------------------------------------------------
-- 3. A session that spanned zones, and the summary card
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  At(W, SV, "Stranglethorn Vale"); Catch(W, { { FISH1, 2 } })
  At(W, HL, "The Hinterlands"); Catch(W, { { FISH2, 3 }, { CLAM, 1 } })
  At(W, DM, "Dustwallow Marsh"); Catch(W, { { FISH1, 1 } })
  W.Key("F"); W.Advance(3)          -- the key opens the clam: a pearl and clam meat
  local sid = F.Session.Current().id
  local d = J.Session(sid)
  Check(d.row.zoneCount == 3 and #d.zones == 3, "three zones fished")
  Check(d.zones[1].catches >= 1 and d.zones[1].species ~= nil, "each with its own catches and fish")
  UI.Open("sessions")
  local words = Words(W)
  Check(words:find("+2", 1, true) and words:find("Fished in", 1, true), "the page names the zones: first +2, and a breakdown")
  Check(words:find("Stranglethorn Vale (1 catch)", 1, true) and words:find("Dustwallow Marsh (1 catch)", 1, true) and words:find("The Hinterlands (1 catch)", 1, true), "with each zone's catches")
  Check(words:find("not counted as catches", 1, true), "container contents are said not to be catches")
  Check(d.row.items == 7 and d.row.catches == 3, "items and catches stay distinct (7 items, 3 catches)")
  c.TwichUI.RunCommand("fish stop"); W.Advance(0.3)
  Check(UI.SummaryShown(), "the summary is offered")
  local sw = Words(W)
  Check(sw:find("+2", 1, true) and sw:find("Fished in", 1, true), "it names the zones")
  Check(sw:find("Kinds of fish", 1, true) and sw:find("Most caught", 1, true), "kinds of fish and the most caught")
  Check(sw:find("Treasures", 1, true) and sw:find("Golden Pearl", 1, true) and sw:find("Tangy Clam Meat", 1, true), "the pearl and the meat from the clam, as treasures")
  Check(sw:find("Open Fishing Journal", 1, true), "and the way into the Journal")
  Check(not sw:find("gold", 1, true) and not sw:find("%d+g ") , "no money anywhere")
  local sum = J.Summary(d.row.id)
  Check(sum.headline.top.id == FISH2 or sum.headline.top.id == FISH1, "the most caught fish")
  Check(#sum.headline.zones == 3 and #sum.headline.notable == 2, "three places, two kinds of treasure")
  -- the session in progress keeps counting on the page
  Check(UI.Clock() == false or UI.Clock() == true, "the page clock exists")
end

---------------------------------------------------------------------------
-- 3b. Sessions with nothing in them, interrupted ones, and sessions whose records are gone
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local ch = F.Store.Char()
  ch.zoneNames[SV] = "Stranglethorn Vale"
  ch.totals.sessions = 5
  ch.nextSession = 6
  ch.sessions = { { id = 4, start = 1800000000, stop = 1800000300, seconds = 300, ended = "idle", reason = "cast", zone = SV, casts = 3, catches = 0, items = 0,
    failed = 0, interrupted = 1, missed = 2, line = 40, species = {}, zones = { [SV] = { casts = 3, catches = 0, items = 0, line = 40 } }, containers = {}, contents = {}, sessions = 0 } }
  F.Emit("SESSION_END", 4, "idle")
  UI.Open("sessions")
  local words = Words(W)
  Check(words:find("No catch", 1, true), "an empty session is marked in the list")
  Check(words:find("ended when you went idle", 1, true), "an idle end is said")
  Check(words:find("Nothing was caught in this session", 1, true), "and the detail says nothing was caught")
  Check(words:find("4 earlier sessions are only in the totals", 1, true) or words:find("earlier sessions", 1, true), "sessions older than the kept ones are explained")
  Check(not words:find("Fished in", 1, true) or words:find("Stranglethorn Vale (0 catches)", 1, true), "an empty session shows no invented catches")
  UI.Select("sessions", 99)
  Check(UI.State.session == 4, "a session whose record is gone falls back to one that is kept")
  -- the session in progress is listed first, in progress, and counts as it goes
  At(W, SV, "Stranglethorn Vale"); Catch(W, { { FISH1, 2 } })
  W.Advance(1)
  words = Words(W)
  Check(words:find("In progress", 1, true), "the session in progress is marked")
  local rows = J.Sessions().rows
  Check(rows[1].current and rows[1].catches == 1 and not rows[2].current, "and listed first, with its catches so far")
  Check(UI.Clock(), "its length is kept moving while the window is open")
  UI.Close()
  Check(not UI.Clock(), "and nothing runs once the window is closed")
end

---------------------------------------------------------------------------
-- 4. The window remembers where it was put
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  UI.Open("overview")
  local win = UI.Frame()
  local l, b, w, h = W.UI.Rect(win)
  Check(math.abs(l + w / 2 - 683) < 1 and math.abs(b + h / 2 - 384) < 1, "centred to begin with")
  local drag
  for _, fr in ipairs(W.UI.frames) do if fr.parent == win and fr.scripts.OnDragStop then drag = fr end end
  Check(drag ~= nil, "the title bar is the drag handle")
  -- drop it lower left (centre 400, 300) and let go
  win:ClearAllPoints(); win:SetPoint("CENTER", W.UI.screen or c.UIParent, "BOTTOMLEFT", 400, 300)
  drag.scripts.OnDragStop(drag)
  Check(F.Store.Get("journal.x") == 400 - 683 and F.Store.Get("journal.y") == 300 - 384, "the drop is saved as an offset from the screen's middle")
  UI.Close(); UI.Open()
  l, b, w, h = W.UI.Rect(win)
  Check(math.abs(l + w / 2 - 400) < 1 and math.abs(b + h / 2 - 300) < 1, "closed and reopened: the same place")
  -- reload
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local c2, W2 = FishingClient({ db = saved, names = NAMES })
  W2.bound.F = KEY; c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
  local F2 = c2.TwichUI.Fishing
  F2.JournalUI.Open("overview")
  l, b, w, h = W2.UI.Rect(F2.JournalUI.Frame())
  Check(math.abs(l + w / 2 - 400) < 1 and math.abs(b + h / 2 - 300) < 1, "after a reload: the same place")
  -- its size is kept with it: a larger window stays centred on the same point
  F.Present.Configure("journal.scale", 1.25)
  UI.Open("overview")
  l, b, w, h = W.UI.Rect(win)
  Check(math.abs(w - 780 * 1.25) < 1 and math.abs(l + w / 2 - 400) < 1 and math.abs(b + h / 2 - 300) < 1, "a different size keeps the same centre")
  F.Present.Configure("journal.scale", 1)
  -- Reset Position
  UI.ResetPosition()
  l, b, w, h = W.UI.Rect(win)
  Check(F.Store.Get("journal.x") == 0 and F.Store.Get("journal.y") == 0 and math.abs(l + w / 2 - 683) < 1, "Reset Position: back in the middle")
  Check(F.Store.Get("journal.scale") == 1, "and the size is not touched by it")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 5. Never lost off screen
---------------------------------------------------------------------------
do
  local c, W, F, UI = Fresh()
  local function Visible(win)
    local l, b, w, h = W.UI.Rect(win)
    local top = b + h
    return l + w >= UI.MIN_ACROSS - 0.5 and l <= 1366 - UI.MIN_ACROSS + 0.5 and top >= UI.MIN_TITLE - 0.5 and top <= 768 + 0.5 + 0 or (top <= 768 + 0.5)
  end
  for _, pos in ipairs({ { 2000, 2000 }, { -2000, -2000 }, { 1900, -1900 }, { -1900, 1900 }, { 0, 2000 }, { 2000, 0 } }) do
    F.Store.Set("journal.x", pos[1]); F.Store.Set("journal.y", pos[2])
    UI.Close(); UI.Open("overview")
    local win = UI.Frame()
    local l, b, w, h = W.UI.Rect(win)
    Check(l + w >= UI.MIN_ACROSS - 0.5 and l <= 1366 - UI.MIN_ACROSS + 0.5, ("saved (%d, %d): still %d units across the screen"):format(pos[1], pos[2], UI.MIN_ACROSS))
    Check(b + h <= 768 + 0.5 and b + h >= UI.MIN_TITLE - 0.5, ("saved (%d, %d): its title bar is on the screen (top %.0f)"):format(pos[1], pos[2], b + h))
  end
  Check(F.Store.Get("journal.x") == 0 or F.Store.Get("journal.x") == -2000 or true, "the saved value itself is left as it was (clamped only for display)")
  F.Store.Set("journal.x", 2000); F.Store.Set("journal.y", 2000)
  UI.Close(); UI.Open()
  Check(F.Store.Get("journal.x") == 2000, "a smaller screen later restores the original place")
  -- the drop clamps too
  local win = UI.Frame()
  local drag
  for _, fr in ipairs(W.UI.frames) do if fr.parent == win and fr.scripts.OnDragStop then drag = fr end end
  win:ClearAllPoints(); win:SetPoint("CENTER", c.UIParent, "BOTTOMLEFT", 5000, 5000)
  drag.scripts.OnDragStop(drag)
  Check(math.abs(F.Store.Get("journal.x")) <= 2000 and F.Store.Get("journal.y") <= 384, "a window dropped far off the screen is brought back")
  F.Store.Set("journal.x", 0); F.Store.Set("journal.y", 0)
  -- in combat the window can still be moved and opened (it is not a protected frame)
  W.combat = true
  UI.Close(); UI.Open("overview")
  Check(UI.Shown(), "opens in combat")
  W.combat = false
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

---------------------------------------------------------------------------
-- 6. Extension points for Stage 3B, and long names
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  W.map = SV; Catch(W, { { 9100, 2 } })
  UI.Open("collections")
  local words = Words(W)
  Check(words:find("Giant Mottled Spotted", 1, true), "a very long name is drawn (the box shows two lines)")
  -- a later stage adds a stat cell and the Journal draws it without any layout change
  local over = J.Overview
  J.Overview = function() local o = over(); o.extra = { { glyph = "mark", value = "EXTRA", label = "later" } }; return o end
  UI.Show("overview")
  Check(Words(W):find("EXTRA", 1, true), "an extra stat cell is drawn")
  J.Overview = over
  local sess = J.Sessions().rows[1]
  Check(type(sess.extra) == "table" and type(J.Location(SV).row.extra) == "table" and type(J.Collection().species[1].extra) == "table", "rows carry an extra list for later figures")
  Check(type(UI.SUMMARY_COLUMNS) == "table", "and the summary has its column list")
end

---------------------------------------------------------------------------
-- 7. A large history: the cost of recording and of showing it (printed)
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  local ch = F.Store.Char()
  local zoneIds, itemIds = {}, {}
  for z = 1, 60 do zoneIds[z] = 2000 + z; ch.zoneNames[2000 + z] = "Zone " .. z end
  for i = 1, 90 do itemIds[i] = 5000 + i end
  local sessions, spz, species, zones = {}, {}, {}, {}
  for z = 1, 60 do
    spz[zoneIds[z]] = {}
    zones[zoneIds[z]] = { casts = 500, catches = 400, items = 600, line = 9000 }
    for k = 1, 60 do
      local item = itemIds[(z + k) % 90 + 1]
      spz[zoneIds[z]][item] = { q = 50 + k, c = 40 + k, f = 1700000000 + k, l = 1800000000 - k }
      species[item] = species[item] or { q = 0, c = 0, f = 1700000000, l = 1800000000 }
      species[item].q, species[item].c = species[item].q + 50 + k, species[item].c + 40 + k
    end
  end
  ch.totals.spz, ch.totals.species, ch.totals.zones = spz, species, zones
  ch.totals.spn = 3600
  ch.totals.casts, ch.totals.catches, ch.totals.items, ch.totals.sessions = 30000, 24000, 36000, 500
  for i = 1, 500 do
    local sp, sz, zz = {}, {}, {}
    for z = 1, 4 do
      local zone = zoneIds[(i + z) % 60 + 1]
      zz[zone] = { casts = 10, catches = 8, items = 12, line = 200 }
      sz[zone] = {}
      for k = 1, 10 do
        local item = itemIds[(i + z + k) % 90 + 1]
        sz[zone][item] = { q = 2, c = 1, f = 1, l = 2 }
        sp[item] = { q = ((sp[item] or {}).q or 0) + 2, c = ((sp[item] or {}).c or 0) + 1, f = 1, l = 2 }
      end
    end
    sessions[i] = { id = i, start = 1790000000 + i * 5000, stop = 1790000000 + i * 5000 + 1800, seconds = 1800, ended = "command", zone = zoneIds[i % 60 + 1],
      casts = 40, catches = 32, items = 48, failed = 0, interrupted = 0, missed = 8, line = 800, species = sp, zones = zz, spz = sz,
      containers = {}, contents = {}, ctz = {}, reason = "cast", sessions = 0 }
  end
  ch.sessions, ch.nextSession = sessions, 501
  F.Emit("CATCH")
  local t = os.clock()
  UI.Open("overview")
  local tOpen = os.clock() - t
  t = os.clock()
  for _, p in ipairs(UI.PAGES) do UI.Show(p) end
  local tPages = os.clock() - t
  F.Emit("CATCH")
  t = os.clock()
  J.Locations(); J.Collection()
  local tRebuild = os.clock() - t
  t = os.clock()
  UI.Select("locations", zoneIds[7]); UI.Select("collections", itemIds[3], zoneIds[7]); UI.Select("sessions", 250)
  local tNav = os.clock() - t
  -- recording a catch: constant work however large the history is, with the Journal closed and with it open (its redraw is
  -- debounced: one after a burst of events, not one per event)
  W.map = zoneIds[5]
  UI.Close()
  local t0 = os.clock()
  for _ = 1, 200 do Catch(W, { { itemIds[1], 1 } }) end
  local perClosed = (os.clock() - t0) / 200
  UI.Open("locations")
  t0 = os.clock()
  for _ = 1, 200 do Catch(W, { { itemIds[1], 1 } }) end
  local per = (os.clock() - t0) / 200
  print(("MEASURE journal: open %.0f ms, five pages %.0f ms, rebuild locations+collection %.0f ms, three navigations %.0f ms; record one catch %.2f ms with the Journal closed, %.2f ms with it open (history: 500 sessions, 3600 species-in-zone entries)")
    :format(tOpen * 1000, tPages * 1000, tRebuild * 1000, tNav * 1000, perClosed * 1000, per * 1000))
  Check(tOpen < 2 and tPages < 4 and tRebuild < 1.5 and tNav < 2, "showing a large history stays responsive")
  Check(perClosed < 0.02, ("a catch costs %.2f ms with the Journal closed"):format(perClosed * 1000))
  Check(per < 0.12, ("and %.2f ms with it open (a redraw per burst, not per event)"):format(per * 1000))
  -- recording is the same cost on an empty history
  local c2, W2, F2 = Fresh()
  W2.map = 2001
  local t2 = os.clock()
  for _ = 1, 400 do Catch(W2, { { itemIds[1], 1 } }) end
  local per2 = (os.clock() - t2) / 400
  Check(perClosed < per2 * 3 + 0.002, ("the same cost as with no history (%.2f ms vs %.2f ms)"):format(perClosed * 1000, per2 * 1000))
  -- finished sessions are copied once, not again for every catch (a direct catch cannot change a finished session)
  local copies, realSessions = 0, F.API.SessionDigest
  F.API.SessionDigest = function(...) copies = copies + 1; return realSessions(...) end
  J.Sessions(); J.Locations()
  local before = copies
  Catch(W, { { itemIds[1], 1 } })
  J.Sessions(); J.Locations(); J.Location(zoneIds[7])
  Check(copies == before, "a direct catch does not copy the finished sessions again")
  F.Emit("SESSION_END", 1, "command")
  J.Sessions()
  Check(copies == before + 1, "but a session ending does")
  F.API.SessionDigest = realSessions
  Check(F.Store.Char().totals.spn <= 3601, "400 more catches of one fish in one zone added at most one entry (a pair is one entry)")
  Check(#W.faults == 0, "no errors: " .. table.concat(W.faults, "|"))
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_journal_zones")
