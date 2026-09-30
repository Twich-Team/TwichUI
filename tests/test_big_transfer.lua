dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
math.randomseed(3)
local function rnd(n) local t = {} for i = 1, n do t[i] = string.char(math.random(33, 126)) end return table.concat(t) end
local c = MakeClient("Ranulf Ashenvow", {"!!!TwichUI","Foo"})
CLIENTS["Ranulf Ashenvow"] = c
c.TwichUIDB = {setup = {scanNext = true}}
c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
-- ~1.5 MB of settings across many tables
c.FooDB = {} for i = 1, 3000 do c.FooDB["k"..i] = {name = rnd(40), vals = {1,2,3,i, rnd(400)}} end
c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
c.TwichUI.Setups:SaveMine(false)
local SH = c.TwichUI.Share
assert(SH:SendToSelf())
local t0 = os.clock()
for _=1,5 do FlushTimers(); Pump() end
SH:Respond("Ranulf Ashenvow", true)
local frames = 0
while SH.outgoing.stage ~= "done" and frames < 5000 do FlushTimers(); Pump(); frames = frames + 1 end
SH:Status()
assert(SH.outgoing.stage == "done")
local got = c.TwichUIDB.setup.received["Ranulf Ashenvow"].tables.FooDB.data
assert(got.k2999.vals[5] == c.FooDB.k2999.vals[5])
print(("BIG TRANSFER OK: %d bytes on the wire, %.1fs cpu"):format(SH.outgoing.total, os.clock() - t0))
