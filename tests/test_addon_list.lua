dofile(TESTS .. "harness.lua")
META = { Foo = {["X-Curse-Project-ID"]="1234", Version="1.0"}, BigWigs = {["X-Wago-ID"]="abc"}, Lonely = {} }
DEPS = { BigWigs_Plugins = {"BigWigs"}, BigWigs_Options = {"BigWigs"} }
LOD = { BigWigs_Options = true }
OFF = { Lonely = true }
local rich = MakeClient("Rich", {"!!!TwichUI","Foo","BigWigs","BigWigs_Plugins","BigWigs_Options","Lonely","Blizzard_Test"})
CLIENTS.Rich = rich
rich.TwichUIDB = {setup = {scanNext = true}}
rich.LOADED["!!!TwichUI"]=true; rich.FireEvent("ADDON_LOADED","!!!TwichUI")
rich.FooDB = {a=1}; rich.LOADED.Foo=true; rich.FireEvent("ADDON_LOADED","Foo")
rich.FireEvent("PLAYER_LOGIN")
local ST = rich.TwichUI.Setups
for _, g in ipairs(ST.InstalledAddons()) do
  print(g.key, g.title, table.concat(g.folders, ","), tostring(g.enabled), (ST.AddonLink(g)), tostring(ST:IsRecommended(g)))
end
ST:SaveMine(false)
local n = 0 for k in pairs(ST.Mine().addons) do n = n + 1 end
print("recommended in pack:", n)
assert(n == 2, "Lonely (off) excluded by default")

local pal = MakeClient("Pal", {"!!!TwichUI","Foo"})
CLIENTS.Pal = pal
pal.LOADED["!!!TwichUI"]=true; pal.FireEvent("ADDON_LOADED","!!!TwichUI")
pal.FireEvent("PLAYER_LOGIN")
assert(rich.TwichUI.Share:SendTo("Pal")); (function() for _=1,10 do FlushTimers(); Pump() end end)()
pal.TwichUI.Share:Respond("Rich-Forever", true); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
local recv = pal.TwichUIDB.setup.received["Rich-Forever"]
for _, e in ipairs(pal.TwichUI.Setups.SortedRecommended(recv)) do print("friend sees:", e.state, e.title, (pal.TwichUI.Setups.AddonLink(e))) end
-- update list only, resend: addons change arrives even with 0 settings parts
rich.TwichUI.Setups:SetRecommended("wago:abc", false)
assert(rich.TwichUI.Setups:UpdateSavedAddonList())
rich.TwichUI.Share.outgoing = nil
assert(rich.TwichUI.Share:SendTo("Pal")); (function() for _=1,10 do FlushTimers(); Pump() end end)()
pal.TwichUI.Share:Respond("Rich-Forever", true); (function() for _=1,10 do FlushTimers(); Pump() end end)(); (function() for _=1,10 do FlushTimers(); Pump() end end)()
local c = 0 for _ in pairs(pal.TwichUIDB.setup.received["Rich-Forever"].addons) do c = c + 1 end
assert(c == 1 and rich.TwichUI.Share.outgoing.parts == 0, "list-only update")
assert(pal.TwichUIDB.setup.received["Rich-Forever"].tables.FooDB, "settings kept")
print("ADDON LIST TESTS PASSED")
