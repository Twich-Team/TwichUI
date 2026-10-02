dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "GetChecked" then return function(s) return s.checked end end
    if k == "SetChecked" then return function(s, v) s.checked = v end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v end end
    if k == "SetScript" then return function(s, n, fn) local t = rawget(s, "scripts"); if not t then t = {}; rawset(s, "scripts", t) end; t[n] = fn end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    return function() end
  end})
end
c.tinsert = table.insert; c.CreateFrame = function(_, name) local o = Obj(); if name then c[name] = o end return o end
c.UISpecialFrames = {}; c.UIParent = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(k) c.popup = k end
c.CANCEL = "Cancel"; c.Settings = nil
c.GetRealZoneText = function() return "Elwynn Forest" end
c.TwichUIDB = {}
c.SOUNDKIT = { IG_ABILITY_PAGE_TURN = 836 }
c.sounds = {}
c.PlaySound = function(id) c.sounds[#c.sounds + 1] = id end
for _, file in ipairs({"chronicle/Style.lua", "chronicle/Window.lua"}) do
local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local W, C = c.TwichUI.ChronicleWindow, c.TwichUI.Chronicle
W:Toggle()                         -- empty state
assert(W:Toggle() == nil)
W:Show()
C.Add("note", { title = "Note", note = "with |cffff0000 codes", zone = "Elwynn Forest" })
C.Add("level", { title = "Reached level 5", level = 5 })
W:Refresh(); W:Hide(); W:Show()
-- the slash command opens it
c.SlashCmdList.TWICHUI("chronicle"); c.SlashCmdList.TWICHUI("journal")
-- clock: 12-hour by default, 24-hour when chosen
local shown = {}
c.date = function(fmt, t) return os.date(fmt, t) end
c.TwichUIDB.ui = nil; W:Refresh()
c.TwichUIDB.ui = { chronicleClock = "24" }; W:Refresh()
-- opening sound: via the frame's OnShow only; not on refresh; can be turned off
local f = c.TwichUIChronicle
c.sounds = {}
W:Refresh(); W:Refresh()
assert(#c.sounds == 0, "refresh is silent")
f.scripts.OnShow()
assert(#c.sounds == 1 and c.sounds[1] == 836, "one page turn per opening")
c.TwichUIDB.modules = { chronicleSound = false }
f.scripts.OnShow()
assert(#c.sounds == 1, "the setting turns it off")
-- header: placeholder, then a compact time; ignored once the frame is closed
assert(f.played.text == "Journey time: \226\128\148", f.played.text)
W.ShowPlayed(3 * 86400 + 7 * 3600 + 24 * 60)
assert(f.played.text == "Journey time: 3d 7h 24m", f.played.text)
W.ShowPlayed(47 * 60); assert(f.played.text == "Journey time: 47m")
f.shown = false; W.ShowPlayed(60); assert(f.played.text == "Journey time: 47m", "closed frame isn't updated")
print("CHRONICLE WINDOW OK")
