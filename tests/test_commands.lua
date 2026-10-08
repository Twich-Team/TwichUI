dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
local out = {}
local function boot(name)
  local c = MakeClient(name, {"!!!TwichUI"})
  CLIENTS[name] = c
  c.print = function(s) table.insert(out, tostring(s)) end
  c.TwichUIDB = {}
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
  return c
end
local function settle() for _=1,10 do FlushTimers(); Pump() end end
local function last() return out[#out] or "" end
local a = boot("Alpha")
local SL = a.SlashCmdList

-- both roots share one parser
assert(a.SLASH_TWICHUI1 == "/twichui" and a.SLASH_TWICHUI2 == "/tui")
assert(SL.TWICHUI == a.TwichUI.RunCommand)

-- help
out = {}; SL.TWICHUI("")
local n = #out; assert(n > 5 and n < 20, n); assert(out[1]:find("commands"))
local noarg = table.concat(out, "\n")
out = {}; SL.TWICHUI("help"); assert(table.concat(out, "\n") == noarg)
out = {}; SL.TWICHUI("?"); assert(table.concat(out, "\n") == noarg)

-- about: the welcome dialog, through the same parser; "welcome" stays the Chronicle's Welcome Back preview
out = {}; SL.TWICHUI("about"); assert(last():find("welcome isn't available", 1, true), "neutral when the dialog isn't loaded")
local shownWelcome = 0
a.TwichUI.Welcome = { Show = function() shownWelcome = shownWelcome + 1 end }
out = {}; SL.TWICHUI("about"); SL.TWICHUI("abo"); assert(shownWelcome == 2, "/tui about and its unique prefix")
assert(noarg:find("/tui about", 1, true) and noarg:find("Welcome Back", 1, true))
a.TwichUI.Welcome = nil

-- unknown / ambiguous
out = {}; SL.TWICHUI("bogus"); assert(last():find("unknown command 'bogus'") and last():find("/tui help"))
out = {}; SL.TWICHUI("c"); assert(last():find("more than one"))

-- old forms still dispatch
local hit = {}
a.TwichUI.Group = { RunCheck = function() hit.check = true end, Version = function() return "9" end }
a.TwichUI.Quiet = { ShowHidden = function() hit.hidden = true end }
a.TwichUI.Window = { Show = function(_, p) hit.restore = p end }
a.TwichUI.GearWindow = { Show = function() hit.gear = true end }
a.TwichUI.OpenSettings = function() hit.options = true end
for _, c in ipairs({"check","hidden","restore","gear","options","settings","res","ver"}) do SL.TWICHUI(c) end
assert(hit.check and hit.hidden and hit.restore == "backups" and hit.gear and hit.options)
a.TwichUI.Quiet = nil; out = {}; SL.TWICHUI("hidden"); assert(last():find("isn't available"))

-- commtest: bad input
out = {}; SL.TWICHUI("commtest"); assert(last():find("usage"))
out = {}; SL.TWICHUI("commtest whisper"); assert(last():find("needs a name"))
out = {}; SL.TWICHUI("commtest party"); assert(last():find("not in a party"))
out = {}; SL.TWICHUI("commtest guild"); assert(last():find("not in a guild"))
assert(#NET == 0)

-- commtest: party, no peer -> inconclusive, state cleaned, nothing saved
GROUP = {Alpha = true}
out = {}; SL.TWICHUI("commtest party")
assert(#NET == 1 and NET[1].dist == "PARTY" and NET[1].prefix == "TwichUISetup")
for k in pairs(a.TwichUIDB) do assert(k ~= "whisperProbe") end
SL.TWICHUI("commtest party"); assert(last():find("already running"))
RunLongTimers(11); settle()
assert(last():find("INCONCLUSIVE"), last())
out = {}; SL.TWICHUI("commtest party"); assert(last():find("Waiting")); NET = {}; RunLongTimers(11)

-- commtest: party with a peer, even with sharing switches off -> success
local b = boot("Beta"); b.TwichUIDB.modules = {shareGroup = false, groupCheck = false, setupSharing = false}
GROUP = {Alpha = true, Beta = true}
out = {}; SL.TWICHUI("commtest party"); settle()
assert(last():find("SUCCESS") and last():find("Beta"), last())
-- the probe carries only the id and type
local sent = false
RunLongTimers(11)
print("COMMANDS TEST PASSED")
