dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
-- Party is explicit: the sender picks it, the receiver doesn't have to.
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
assert(SH.Transport() == "DIRECT", "default is Direct")
-- Party chosen, not grouped: refused with advice, nothing sent
SH.SetTransport("PARTY")
local ok, why = SH:SendTo("Pal Stonebrook"); assert(not ok and why:find("not in a party"), why)
GROUP = {["Ranulf Ashenvow"]=true}
ok, why = SH:SendTo("Pal Stonebrook"); assert(not ok and why:find("isn't in your group"), why)
assert(#NET == 0)
-- grouped: the receiver never switched anything on and still gets it
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true}
assert(pal.TwichUI.Share.Transport() == "DIRECT")
assert(SH:SendTo("Pal Stonebrook")); settle()
assert(pal.TwichUI.Share.incoming["Ranulf Ashenvow"].stage == "asking", "party offer reaches a Direct-default receiver")
pal.TwichUI.Share:Respond("Ranulf Ashenvow", true); settle()
assert(SH.outgoing.stage == "done")
-- self-test: chosen channel when it exists, otherwise on this computer
assert(SH.Route("Ranulf Ashenvow")[1] == "PARTY")
SH.SetTransport("DIRECT")
assert(SH.Route("Ranulf Ashenvow")[1] == "LOOP", "you can't whisper yourself")
print("CHANNEL TESTS PASSED")
