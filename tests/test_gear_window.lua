dofile(TESTS .. "harness.lua")
-- Stat weights page (TwichUI > Stat weights in the options): registers under
-- TwichUI, builds and refreshes in both modes without errors (permissive UI
-- mocks, as in test_window_smoke.lua), and /twichui gear opens it.
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
local menus = {}
c.tinsert = table.insert
local made = {}
c.CreateFrame = function(kind)
  local o = Obj()
  made[#made + 1] = o
  for k, v in pairs(realCreate()) do rawset(o, k, v) end
  o.Show, o.Hide, o.IsShown = nil, nil, nil   -- use the Obj versions, which remember
  if kind == "DropdownButton" then o.SetupMenu = function(self, fn) table.insert(menus, fn) end end
  return o
end
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(key) c.StaticPopupDialogs[key].OnAccept() end
c.UnitClass = function() return "Mage", "MAGE" end
c.UnitLevel = function() return 30 end
c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
local canvas, opened
c.Settings = {
  RegisterVerticalLayoutCategory = function() return {GetID = function() return 1 end}, {AddInitializer = function() end} end,
  RegisterVerticalLayoutSubcategory = function(parent, name) return {GetID = function() return 1 end, name = name}, {AddInitializer = function() end} end,
  RegisterAddOnSetting = function() return {} end,
  CreateCheckbox = function() end,
  RegisterAddOnCategory = function() end,
  RegisterCanvasLayoutSubcategory = function(parent, frame, name)
    assert(parent and parent.name == "Gear comparison" and name == "Stat weights", "Stat weights sits under Gear comparison")
    canvas = frame
    return {GetID = function() return 2 end}
  end,
  OpenToCategory = function(id) opened = id end,
}
for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "Settings.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local GW, P = R.GearWindow, R.GearPrefs
assert(canvas, "registered as a page under TwichUI")

-- Shown by the settings panel: builds, then refreshes as preferences change.
canvas:Show(); canvas.scripts.OnShow(canvas)
canvas:OnRefresh()
P.SetTreeChoice(8)                        -- Fire
P.SetWeight("MAGE", 8, "SPI", 0.5)
P.ResetWeights("MAGE", 8)
P.SetUsesPriority("MAGE", 8, true)        -- stat priority
P.SetPriority("MAGE", 8, { "SP", "SPELLHIT", "INT" })
P.SetPriority("MAGE", 8, nil)             -- empty list
P.SetUsesPriority("MAGE", 8, false)

-- The dropdowns: talent tree and how stats are valued.
local radios = {}
local root = {CreateRadio = function(_, label, isSelected, setSelected)
  local r = {label = label, isSelected = isSelected, setSelected = setSelected}
  table.insert(radios, r)
  return r
end}
for _, build in ipairs(menus) do build(nil, root) end
local labels = {}
for _, r in ipairs(radios) do labels[#labels + 1] = r.label end
assert(#radios == 5, "three trees and two modes: " .. table.concat(labels, ", "))
for _, r in ipairs(radios) do if r.label == "Stat priority" then r.setSelected() end end
local trees = R.GearData.Trees()
local edited
for _, tree in ipairs(trees) do if P.UsesPriority("MAGE", tree.skillLine) then edited = tree.skillLine end end
assert(edited and P.Priority("MAGE", edited), "switching to priority starts the list from the weights")

-- A question about resetting a tree is about the tree that was showing when it was asked, even if
-- another is chosen while it is open; cancelling changes nothing; a spoiled entry is refused by name.
do
  local pending
  c.StaticPopup_Show = function(key, text) pending = { dlg = c.StaticPopupDialogs[key], text = text } return {} end
  local printed = {}
  c.print = function(line) printed[#printed + 1] = line end
  local list = R.GearData.Trees()
  local a, b = list[1], list[2]
  local function Choose(tree)
    radios = {}
    for _, build in ipairs(menus) do build(nil, root) end
    for _, r in ipairs(radios) do
      if r.label:sub(1, #tree.name) == tree.name then r.setSelected() return end
    end
    error("no radio for " .. tree.name)
  end
  local function Button(label)
    for _, o in ipairs(made) do if rawget(o, "text") == label and o.scripts and o.scripts.OnClick then return o end end
    error("no button " .. label)
  end
  P.SetUsesPriority("MAGE", a.skillLine, false); P.SetUsesPriority("MAGE", b.skillLine, false)
  Choose(a)
  P.SetWeight("MAGE", a.skillLine, "SPI", 0.5); P.SetWeight("MAGE", b.skillLine, "SPI", 0.7)
  Button("Reset weights").scripts.OnClick()
  assert(pending and pending.text:find(a.name, 1, true) and pending.text:find("can't be undone", 1, true), "it names the tree: " .. tostring(pending and pending.text))
  Choose(b)
  pending.dlg.OnAccept()
  assert(not (P.CustomWeights("MAGE", a.skillLine) or {}).SPI, "the tree that was asked about is reset")
  assert((P.CustomWeights("MAGE", b.skillLine) or {}).SPI == 0.7, "the tree chosen meanwhile is left alone")
  -- cancelled: nothing changes, and a stale press of the old button does nothing
  P.SetWeight("MAGE", b.skillLine, "SPI", 0.9)
  Button("Reset weights").scripts.OnClick()
  pending.dlg.OnCancel(nil, nil, "clicked")
  pending.dlg.OnAccept()
  assert((P.CustomWeights("MAGE", b.skillLine) or {}).SPI == 0.9, "cancelling leaves the weights as they were")
  -- a bad number is refused with the stat and the entry named, and the old value stays
  local row
  for _, o in ipairs(made) do
    if rawget(o, "stat") == "SPI" then row = o end
  end
  P.SetWeight("MAGE", b.skillLine, "SPI", nil)
  row.edit.text = "lots"
  rawset(row.edit, "revert", false)       -- the stand-in answers every unknown name with a function
  row.edit.scripts.OnEditFocusLost()
  assert(printed[#printed] and printed[#printed]:find("lots", 1, true) and printed[#printed]:find("0 to 1000", 1, true), "the entry is named: " .. tostring(printed[#printed]))
  assert(not (P.CustomWeights("MAGE", b.skillLine) or {}).SPI, "nothing was saved")
  c.StaticPopup_Show = function(key) c.StaticPopupDialogs[key].OnAccept() end
end

-- /twichui gear opens the page in the options.
c.SlashCmdList.TWICHUI("gear")
assert(opened == 2, "slash command opens the Stat weights page")

-- A class without weights: a message instead.
opened = nil
c.UnitClass = function() return "Death Knight", "DEATHKNIGHT" end
GW:Show()
assert(opened == nil)
canvas:OnRefresh()
print("GEAR WINDOW SMOKE OK")
