dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
local c = MakeClient("Ranulf Ashenvow", {"!!!TwichUI","Foo"})
CLIENTS["Ranulf Ashenvow"] = c
c.TwichUIDB = {setup = {scanNext = true}}
-- UI mocks enough for the popup
local popups = {}
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function(which, a1, a2, data) popups[which] = {dlg = c.StaticPopupDialogs[which], data = data} end
for _, f in ipairs({"setup/Window.lua"}) do local ch = assert(loadfile(ROOT..f)); setfenv(ch, c); ch("!!!TwichUI", {}) end
c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
c.FooDB = {a=1}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
c.FireEvent("PLAYER_LOGIN")
TIMERS = {}; c.TwichUI.Setups:SaveMine(false)
local SH = c.TwichUI.Share
assert(SH:SendToSelf())
for _=1,5 do FlushTimers(); Pump() end
local p = popups.TWICHUI_OFFER; assert(p, "prompt shown")
p.dlg.OnAccept({}, p.data)      -- modern client: dialog has no .data field
for _=1,10 do FlushTimers(); Pump() end
SH:Status()
assert(SH.outgoing.stage == "done", tostring(SH.outgoing.stage))
print("PROMPT ACCEPT TEST PASSED")
