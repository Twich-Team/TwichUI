dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI","Foo"})
-- permissive UI mocks
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
    if k == "HasFocus" then return function() return false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" then local sb = Obj(); rawset(t, k, sb); return sb end
    return function() end
  end})
end
local realCreate = c.CreateFrame
c.tinsert = table.insert; c.CreateFrame = function(kind, ...) local o = Obj(); local base = realCreate(); for k,v in pairs(base) do rawset(o,k,v) end return o end
c.UISpecialFrames = {}
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(k, a) print("popup", k, a) end
c.UnitIsPlayer = function() return false end
c.InCombatLockdown = function() return false end
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
c.Settings = nil
for _, f in ipairs({"setup/Window.lua", "Settings.lua"}) do
  local chunk = assert(loadfile(ROOT..f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.TwichUIDB.setup.detected.FooDB = {owner="Foo", bytes=2000}
c.FireEvent("PLAYER_LOGIN")
local W = c.TwichUI.Window
W:Show("mine"); W:Show("get")
c.TwichUIDB.setup.received["Pal-Forever"] = {created=1, version=2, sourceName="Pal", tables={FooDB={owner="Foo", data={}, hash="1"}}, editMode="abc"}
W:Show("get"); W:ShowEditMode()
W:AskAccept("Pal-Forever", {addons=3, bytes=50000})
W:Received("Pal-Forever")
W:Show("addons"); c.TwichUIDB.setup.received["Pal-Forever"].addons = {["cf:1"]={title="Foo", folders={"Foo"}}, ["x"]={title="Bar", folders={"Bar"}}}; W:Show("get"); W:ShowAddonList("recv:Pal-Forever"); W:ShowStorage(); W:ShowChannels(); W:Show("group"); W:Show("restore"); W:Show("mine"); W:Toggle(); W:Toggle()
print("UI SMOKE OK")
