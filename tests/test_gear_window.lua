dofile(TESTS .. "harness.lua")
-- Upgrade hints window: builds and refreshes both pages without errors
-- (permissive UI mocks, as in test_window_smoke.lua).
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
    if k == "HasFocus" then return function() return false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" then local sb = Obj(); rawset(t, k, sb); return sb end
    return function() end
  end})
end
local realCreate = c.CreateFrame
c.tinsert = table.insert; c.CreateFrame = function() local o = Obj(); for k, v in pairs(realCreate()) do rawset(o, k, v) end return o end
c.UISpecialFrames = {}
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.UnitClass = function() return "Mage", "MAGE" end
c.UnitLevel = function() return 30 end
c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
c.Settings = nil
for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "Settings.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local GW, P = R.GearWindow, R.GearPrefs

GW:Show("weights")
P.SetTreeChoice(8)                        -- Fire
P.SetWeight("MAGE", 8, "SPI", 0.5)
GW:Show("weights")
P.ResetWeights("MAGE", 8)
P.SetUsesPriority("MAGE", 8, true)        -- stat priority page
P.SetPriority("MAGE", 8, { "SP", "SPELLHIT", "INT" })
GW:Show("weights")
P.SetPriority("MAGE", 8, nil)             -- empty list
GW:Show("weights")
P.SetUsesPriority("MAGE", 8, false)
GW:Show("behaviour")
for _, key in ipairs({ "cautious", "eager", "balanced" }) do P.Set("strictness", key) end
for _, key in ipairs({ "alt", "ctrl", "always", "compare" }) do P.Set("reveal", key) end
for _, key in ipairs({ "green", "badge", "gilded" }) do P.Set("bagStyle", key) end
GW:Toggle(); GW:Toggle()

-- The slash command opens it.
c.SlashCmdList.TWICHUI("gear")

-- A class without weights: no window, a message instead.
c.UnitClass = function() return "Death Knight", "DEATHKNIGHT" end
GW:Show()
print("GEAR WINDOW SMOKE OK")
