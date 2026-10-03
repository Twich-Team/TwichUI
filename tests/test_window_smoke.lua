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
c.tinsert = table.insert; c.CreateFrame = function(kind, name, ...) local o = Obj(); local base = realCreate(); for k,v in pairs(base) do rawset(o,k,v) end if name then c[name] = o; rawset(o, "IsShown", function() return true end) end return o end
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
W:Show("share"); W:Show("received")
c.TwichUIDB.setup.received["Pal-Forever"] = {created=1, version=2, sourceName="Pal", tables={FooDB={owner="Foo", data={}, hash="1"}}, editMode="abc"}
W:Show("received"); W:ShowEditMode()
W:AskAccept("Pal-Forever", {addons=3, bytes=50000})
W:Received("Pal-Forever")
W:Show("addons"); W:ShowChoose(); W:ShowRecommend(); W:ShowParty(); c.TwichUIDB.setup.received["Pal-Forever"].addons = {["cf:1"]={title="Foo", folders={"Foo"}}, ["x"]={title="Bar", folders={"Bar"}}}; W:Show("received"); W:ShowAddonList("recv:Pal-Forever"); W:ShowStorage(); W:ShowChannels(); W:Show("group"); W:Show("backups"); W:Show("mine"); W:Toggle(); W:Toggle()
-- Import preview: what applying each addon would do.
local ST = c.TwichUI.Setups
local g = ST.PackByAddon(c.TwichUIDB.setup.received["Pal-Forever"])[1]
assert(ST.ApplyEffect(g) == "replace", "an addon that hasn't loaded counts as replacing")
c.LOADED.Foo = true
assert(ST.ApplyEffect(g) == "new", "loaded with no settings: new")
c.FooDB = {scale = 1}
assert(ST.ApplyEffect(g) == "replace", "loaded with settings: replaces")
assert(ST.ApplyEffect({state = "missing", tables = {}}) == "missing")
W:Show("received")
-- Backup export / import panel
local pt = c.TwichUI.Restore.AddImported({name = "Smoke", created = 1, tables = {FooDB = {owner = "Foo", data = {a = 1}}}})
W:Show("backups"); W:ExportBackup(pt)
for _ = 1, 50 do FlushTimers() end
local tp = c.TwichUIBackupTransfer
assert(tp.edit:GetText():find("^TUIBK1:"), "export string shown")
local str = tp.edit:GetText()
W:ImportBackup(); assert(tp.edit:GetText() == "", "buffer cleared between uses")
tp.edit:SetText(str); tp.check.scripts.OnClick(tp.check)
for _ = 1, 50 do FlushTimers() end
assert(tp.result and tp.result.blocked, "repeat is blocked in the preview")
c.TwichUI.Restore:Delete(pt.id)
tp.check.scripts.OnClick(tp.check)
for _ = 1, 50 do FlushTimers() end
assert(tp.result and not tp.result.blocked)
tp.importBtn.scripts.OnClick(tp.importBtn)
assert(#c.TwichUI.Restore.List() == 1 and not c.reloaded, "imported, not applied")
print("UI SMOKE OK")
