dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
DROP_SPACED_WHISPERS = true            -- what Forever does
local function boot(name, addons, scan)
  local c = MakeClient(name, addons)
  CLIENTS[name] = c
  if scan then c.TwichUIDB = {setup = {scanNext = true}} end
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
  c.FooDB = {a=string.rep("abcdefghij", 800)}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
  c.FireEvent("PLAYER_LOGIN")
  if ALLOW_GROUP ~= false then c.TwichUI.Share.SetTransport("PARTY") end
  return c
end
local function settle() for _ = 1, 20 do FlushTimers(); Pump() end end
local rich = boot("Ranulf Ashenvow", {"!!!TwichUI","Foo"}, true)
rich.TwichUI.Setups:SaveMine(false)
local SH = rich.TwichUI.Share
-- 1) self test, no group: loopback
assert(SH:SendToSelf()); settle()
assert(SH.incoming["Ranulf Ashenvow"].stage == "asking", "loop offer")
SH:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done", "loop done: "..tostring(SH.outgoing.stage))
print("loopback self-test ok, lanes total", SH.outgoing.total)
-- 2) friend not grouped: refused with advice
local pal = boot("Pal Stonebrook", {"!!!TwichUI","Foo"})
local third = boot("Zed Quill", {"!!!TwichUI","Foo"})
SH.outgoing = nil
print(SH:SendTo("Pal Stonebrook"))
-- 3) grouped: works over PARTY; third member ignores
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true, ["Zed Quill"]=true}
assert(SH:SendTo("pal stonebrook")); settle()
assert(pal.TwichUI.Share.incoming["Ranulf Ashenvow"].stage == "asking")
assert(next(third.TwichUI.Share.incoming) == nil, "third party ignores")
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done", "party done: "..tostring(SH.outgoing.stage))
assert(pal.TwichUIDB.setup.received["Ranulf Ashenvow"].tables.FooDB.data.a:len() == 8000)
assert(next(third.TwichUIDB.setup.received) == nil)
-- 4) self-test while grouped goes over PARTY
SH.outgoing = nil; rich.TwichUIDB.setup.received = {}
assert(SH:SendToSelf()); settle()
SH:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done")
assert(next(pal.TwichUI.Share.incoming) and pal.TwichUI.Share.incoming["Ranulf Ashenvow"].stage == "done", "pal untouched by self-test")
print("ROUTING TESTS PASSED")
