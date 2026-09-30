dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
math.randomseed(7)
local function rnd(n) local t = {} for i = 1, n do t[i] = string.char(math.random(33, 126)) end return table.concat(t) end
local function boot(name, scan)
  local c = MakeClient(name, {"!!!TwichUI","Foo"})
  CLIENTS[name] = c
  if scan then c.TwichUIDB = {setup = {scanNext = true}} end
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
  c.FooDB = {a = rnd(12000)}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
  c.FireEvent("PLAYER_LOGIN")
  if ALLOW_GROUP ~= false then c.TwichUIDB.modules.shareGroup = true end
  return c
end
local rich = boot("Ranulf Ashenvow", true)
local big = rich.FooDB.a
rich.TwichUI.Setups:SaveMine(false)
local pal = boot("Pal Stonebrook")
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true}
local SH = rich.TwichUI.Share
assert(SH:SendTo("Pal Stonebrook")); for _=1,10 do FlushTimers(); Pump() end
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); for _=1,10 do FlushTimers(); Pump() end
assert(SH.outgoing.stage == "done")
assert(pal.TwichUIDB.setup.received["Ranulf Ashenvow"].tables.FooDB.data.a == big, "multi-lane data intact")
print("MULTI-LANE OK, bytes", SH.outgoing.total)
