-- Synthetic CPU benchmark, real Fishing service/UI, O(1) Workshop reference fixture.
dofile(TESTS .. "fishing_mock.lua")
local c, W = FishingClient()
W.bound.F = "CLICK TwichUIFishingButton:LeftButton"; c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
local F = c.TwichUI.Fishing
local generation, reads, longest, longestTimer = 1, 0, 0, 0
local totalStart = os.clock()
local market = {}
for i = 1, 100000 do market[i] = i * 13 end
c.TwichUI.Workshop = { Active = function() return true end,
 Pricing = { Generation = function() return tostring(generation) end,
 Source = function() return { reference = true, label = "Synthetic market", market = { key = "realm|Alliance", realm = "Realm", side = "Alliance", at = 1800000000 } } end,
 Reference = function(id) reads = reads + 1; return { market = market[id], at = 1800000000 } end, Changed = function() end }, Market = { Value = function() return nil, "nomarket" end } }
c.FireEvent("ADDON_LOADED", "TwichUI_Workshop")
local after = c.C_Timer.After
c.C_Timer.After = function(delay, fn) return after(delay, function()
 local started = os.clock(); fn(); longestTimer = math.max(longestTimer, (os.clock() - started) * 1000)
end) end
local function Measure(name, fn, n)
 local started = os.clock()
 for _ = 1, n or 1 do fn() end
 local ms = (os.clock() - started) * 1000 / (n or 1)
 longest = math.max(longest, ms)
 print(string.format("BENCH %s: %.3f ms", name, ms))
end
Measure("cold catch cache request", function() F.Economy.Item(6291, 1) end)
assert(reads == 0, "no pricing on the cold catch")
W.Advance(1)
Measure("warm catch cache read", function() F.Economy.Item(6291, 1) end, 1000)
local prov = { direct = {}, contents = {}, containers = {} }
for i = 1, 1000 do prov.direct[10000 + i] = 10 end
Measure("1000 distinct items cold calculation", function() F.Economy.Calculate(prov, 1800, 1000) end)
W.Advance(10)
Measure("1000 distinct items warm calculation", function() assert(F.Economy.Calculate(prov, 1800, 1000).complete) end)
local ch = F.Store.Char()
for id = 10001, 10090 do
 ch.totals.species[id] = { q = 500, c = 500, f = 1, l = 2 }
end
ch.totals.sessions, ch.totals.casts, ch.totals.catches, ch.totals.items, ch.totals.seconds = 500, 10000, 9000, 45000, 900000
ch.totals.zones[1429] = { casts = 10000, catches = 9000, items = 45000, line = 100000 }
ch.totals.spz[1429] = F.Copy(ch.totals.species)
for i = 1, 500 do
 ch.sessions[i] = { id = i, start = 1790000000 + i * 2000, stop = 1790001800 + i * 2000, seconds = 1800, ended = "command", zone = 1429,
 casts = 20, catches = 18, items = 90, line = 1000, species = {}, contents = {}, containers = {}, zones = { [1429] = { catches = 18, casts = 20, items = 90 } }, spz = {} }
 for id = 10001, 10030 do ch.sessions[i].species[id] = { q = 3, c = 1, f = 1, l = 2 } end
end
ch.nextSession = 501
F.Emit("SESSION_END")
if os.getenv("FISHING_BENCH_ECONOMY_OFF") == "1" then F.Store.Set("economy.enabled", false) end
Measure("Journal open 500 sessions", function() F.JournalUI.Open("overview") end)
W.Advance(2)
Measure("Journal five pages", function() for _, page in ipairs(F.JournalUI.PAGES) do F.JournalUI.Show(page) end end)
Measure("Journal typical redraw", function() F.JournalUI.Refresh() end, 20)
F.JournalUI.Show("overview")
W.Advance(2)
Measure("market update while Journal open", function() generation = generation + 1; c.TwichUI.Workshop.Pricing.Changed() end)
W.Advance(10)
c.TwichUI.Workshop = nil; F.Economy.Invalidate()
Measure("Workshop unavailable 1000 items", function() assert(F.Economy.Calculate(prov).total == nil) end)
print(string.format("BENCH largest measured uninterrupted callback/operation: %.3f ms; reference reads %d; market entries 100000", longest, reads))
print(string.format("BENCH total CPU %.3f ms; largest deferred callback %.3f ms", (os.clock() - totalStart) * 1000, longestTimer))
assert(#W.errors == 0)
