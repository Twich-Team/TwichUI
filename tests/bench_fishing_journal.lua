-- Not a test: measures what the Journal costs over a large realistic history (500 sessions, 60 zones, 90 species, 3,600
-- species-in-zone entries) and prints it. Run: cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' bench_fishing_journal.lua
dofile(TESTS .. "fishing_mock.lua")
local KEY = "CLICK TwichUIFishingButton:LeftButton"
local c, W = FishingClient({ names = {} })
W.Camera(); W.bound.F = KEY; c.FireEvent("UPDATE_BINDINGS"); W.Advance(1); W.Wear(16, POLE)
local F = c.TwichUI.Fishing
local UI, J = F.JournalUI, F.Journal
local ch = F.Store.Char()
local zoneIds, itemIds = {}, {}
for z = 1, 60 do zoneIds[z] = 2000 + z; ch.zoneNames[2000 + z] = "Zone " .. z end
for i = 1, 90 do itemIds[i] = 5000 + i end
local spz, species, zones, sessions = {}, {}, {}, {}
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
ch.totals.spz, ch.totals.species, ch.totals.zones, ch.totals.spn = spz, species, zones, 3600
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
local function T(f) local t = os.clock(); f(); return (os.clock() - t) * 1000 end
local out = {}
out[#out + 1] = ("open (Overview)          %6.0f ms"):format(T(function() UI.Open("overview") end))
out[#out + 1] = ("Sessions page            %6.0f ms"):format(T(function() UI.Show("sessions") end))
out[#out + 1] = ("Collections page         %6.0f ms"):format(T(function() UI.Show("collections") end))
out[#out + 1] = ("Locations page           %6.0f ms"):format(T(function() UI.Show("locations") end))
out[#out + 1] = ("Treasures page           %6.0f ms"):format(T(function() UI.Show("treasures") end))
out[#out + 1] = ("all five again (cached)  %6.0f ms"):format(T(function() for _, p in ipairs(UI.PAGES) do UI.Show(p) end end))
F.Emit("CATCH")
out[#out + 1] = ("rebuild Locations+Collection after a catch %6.0f ms"):format(T(function() J.Locations(); J.Collection() end))
UI.Select("locations", zoneIds[7])
F.Emit("CATCH")
out[#out + 1] = ("Locations redraw after a catch   %6.0f ms"):format(T(function() UI.Refresh() end))
UI.Show("overview"); F.Emit("CATCH")
out[#out + 1] = ("Overview redraw after a catch    %6.0f ms"):format(T(function() UI.Refresh() end))
out[#out + 1] = ("three navigations              %6.0f ms"):format(T(function()
  UI.Select("locations", zoneIds[7]); UI.Select("collections", itemIds[3], zoneIds[7]); UI.Select("sessions", 250) end))
-- recording: closed and open, through the real loot path (the cost of the event handlers; redraws are on timers)
W.map = zoneIds[5]; UI.Close()
local function Catch() W.StartLine(); W.Loot({ { itemIds[1], 1 } }, { fishing = true }); W.StopLine() end
out[#out + 1] = ("record one catch, Journal closed %6.2f ms"):format(T(function() for _ = 1, 200 do Catch() end end) / 200)
UI.Open("locations")
out[#out + 1] = ("record one catch, Journal open   %6.2f ms (events only, redraw not yet run)"):format(T(function() for _ = 1, 200 do Catch() end end) / 200)
out[#out + 1] = ("the debounced redraw that follows  %6.0f ms"):format(T(function() W.Advance(1) end))
print(table.concat(out, "\n"))
