dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
local function boot(name, scan)
  local c = MakeClient(name, {"!!!TwichUI","Foo"})
  CLIENTS[name] = c
  if scan then c.TwichUIDB = {setup = {scanNext = true}} end
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
  c.FooDB = {a=0, b=1}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
  c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
  return c
end
local function settle() for _=1,10 do FlushTimers(); Pump() end end
local rich = boot("Ranulf Ashenvow", true); rich.TwichUI.Setups:SaveMine(false)
local pal = boot("Pal Stonebrook")
local SH = rich.TwichUI.Share
print(select(2, SH:SendTo("Pal Stonebrook")))                 -- nothing allowed, not grouped
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true}
print(select(2, SH:SendTo("Pal Stonebrook")))                 -- grouped, group channel off
rich.TwichUIDB.modules.shareGroup = true
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(next(pal.TwichUI.Share.incoming) == nil, "pal hasn't allowed group: ignored")
print("receiver with group off ignores it: ok")
pal.TwichUIDB.modules.shareGroup = true
SH.outgoing = nil
assert(SH:SendTo("Pal Stonebrook")); settle()
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done")
-- self-test while grouped but group off: stays local
rich.TwichUIDB.modules.shareGroup = false
print("self route:", SH.Route("Ranulf Ashenvow")[1])
print("CHANNEL OPT-IN TESTS PASSED")
