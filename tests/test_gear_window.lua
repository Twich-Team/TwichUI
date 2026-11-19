dofile(TESTS .. "harness.lua")
-- Stat weights page (TwichUI settings > Gear comparison > Stat weights): its frame builds and refreshes in
-- both modes without errors (permissive UI mocks, as in test_window_smoke.lua), with the settings window's
-- own cards, buttons and virtual drag, and /twichui gear opens it in the settings window.
local c = MakeClient("Rich", {"!!!TwichUI"})
local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetWidth" then return function(s) return s.width or 180 end end
    if k == "SetWidth" then return function(s, value) s.width = value end end
    if k == "GetHeight" then return function() return 22 end end
    if k == "GetEffectiveScale" or k == "GetScale" then return function() return 1 end end
    if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
    if k == "IsEnabled" then return function() return true end end
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
    if k == "ScrollBar" or k == "ThumbTexture" then local sb = Obj(); rawset(t, k, sb); return sb end
    if type(k) == "string" and k:find("^%u") then return function() end end
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
  return o
end
c.UIParent = Obj(); c.GetCursorPosition = function() return c.cursorX or 0, c.cursorY or 0 end
c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
c.StaticPopupDialogs = {}; c.StaticPopup_Show = function(key) c.StaticPopupDialogs[key].OnAccept() end
c.UnitClass = function() return "Mage", "MAGE" end
c.UnitLevel = function() return 30 end
c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
local opened
for _, f in ipairs({ "chronicle/Style.lua", "Look.lua", "Icons.lua", "FrameLook.lua", "CraftLook.lua", "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
-- the settings window's addon, loaded on demand; opening records the page asked for
c.C_AddOns.LoadAddOn = function(name)
  if name ~= "TwichUI_Settings" then return false, "MISSING" end
  if not c.TwichUI.SettingsUI then
    for _, f in ipairs(SettingsFiles()) do
      local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("TwichUI_Settings", {})
    end
    c.TwichUI.SettingsUI.Open = function(page) opened = page end
  end
  return true
end
c.C_AddOns.LoadAddOn("TwichUI_Settings")
local R = c.TwichUI
local GW, P = R.GearWindow, R.GearPrefs
local canvas = GW.Frame()
assert(canvas and GW.Frame() == canvas, "one frame, made once")

-- Shown on the settings window's Stat weights page: builds, then refreshes as preferences change.
canvas:Show(); canvas.scripts.OnShow(canvas)
GW:Refresh()
P.SetTreeChoice(8)                        -- Fire
P.SetWeight("MAGE", 8, "SPI", 0.5)
P.ResetWeights("MAGE", 8)
P.SetUsesPriority("MAGE", 8, true)        -- stat priority
P.SetPriority("MAGE", 8, { "SP", "SPELLHIT", "INT" })
P.SetPriority("MAGE", 8, nil)             -- empty list
P.SetUsesPriority("MAGE", 8, false)

local parts = GW.Parts()
local trees = R.GearData.Trees()
assert(#parts.trees == #trees and #trees == 3, "a card for each talent tree")
for _, card in ipairs(parts.trees) do assert(card:IsShown() and card.skillLine, "each tree card is shown and knows its tree") end
local function Card(skillLine)
  for _, card in ipairs(parts.trees) do if card.skillLine == skillLine then return card end end
  error("no card for " .. tostring(skillLine))
end
local function Click(frame) frame.scripts.OnClick(frame) end

-- Choosing a tree card shows that tree's choices; one card is chosen at a time.
local a, b = trees[1], trees[2]
Click(Card(a.skillLine))
assert(Card(a.skillLine).chosen and not Card(b.skillLine).chosen, "the chosen tree's card is marked")
assert(parts.frame.title.text:find(a.name, 1, true), "the editor names the tree: " .. tostring(parts.frame.title.text))

-- Browsing one group hides unrelated fields and preserves their saved values.
P.SetUsesPriority("MAGE", a.skillLine, false)
GW:Refresh()
local savedWeights = P.CustomWeights("MAGE", a.skillLine)
local groupCount = #R.GearWeights.EDITOR
assert(#parts.frame.filters == groupCount + 1, "All, then a button for each stat group")
local function Filter(label)
  for _, bt in ipairs(parts.frame.filters) do if bt.group == label then return bt end end
  error("no filter " .. label)
end
Click(Filter("Attributes"))
local total, visible = #parts.groups, 0
for _, group in ipairs(parts.groups) do if group.box:IsShown() then visible = visible + 1 end end
assert(visible == 1 and total > 1, "the group filter shows one group's card")
assert(P.CustomWeights("MAGE", a.skillLine) == savedWeights, "browsing does not write weights")
Click(Filter("all"))
for _, group in ipairs(parts.groups) do assert(group.box:IsShown(), "all stat groups restored") end

-- Every stat has a field; a changed one is marked and can be put back with its own Reset.
local function Row(stat)
  for _, row in ipairs(parts.weights) do if row.stat == stat then return row end end
  error("no weight row " .. stat)
end
P.SetWeight("MAGE", a.skillLine, "SPI", 0.7)
assert(Row("SPI").undo:IsShown() and not Row("INT").undo:IsShown(), "only a changed weight offers its own Reset")
Click(Row("SPI").undo)
assert(not (P.CustomWeights("MAGE", a.skillLine) or {}).SPI, "Reset puts one weight back")

-- Switching to stat priority starts the list from the weights.
assert(not P.Priority("MAGE", a.skillLine), "no list yet")
Click(parts.frame.modePriority)
assert(P.UsesPriority("MAGE", a.skillLine) and P.Priority("MAGE", a.skillLine), "switching to priority starts the list from the weights")
Click(parts.frame.modeWeights)
assert(not P.UsesPriority("MAGE", a.skillLine), "and back to weights")

-- The ranking: drag a card (the settings window's virtual drag), drag a stat in, drag a card out, click to add.
do
  local kit = R.MagicInventoryPage.Drag
  P.SetUsesPriority("MAGE", a.skillLine, true)
  P.SetPriority("MAGE", a.skillLine, { "SP", "SPELLHIT", "INT", "SPI" })
  local function List() return table.concat(P.Priority("MAGE", a.skillLine) or {}, ",") end
  assert(List() == "SP,SPELLHIT,INT,SPI" and parts.ranked[4]:IsShown() and not parts.ranked[5]:IsShown(), "a card per ranked stat")
  assert(parts.ranked[1].label.text == "Spell Power" or parts.ranked[1].label.text:find("Spell", 1, true), "the card names the stat: " .. tostring(parts.ranked[1].label.text))
  assert(parts.ranked[2].shareText == "80%", "and what it counts: " .. tostring(parts.ranked[2].shareText))
  -- geometry for the pointer: rows 34 high, 37 apart, from y 400 down; the palette to the right
  local function Box(o, l, r, bt, t)
    rawset(o, "GetLeft", function() return l end); rawset(o, "GetRight", function() return r end)
    rawset(o, "GetBottom", function() return bt end); rawset(o, "GetTop", function() return t end)
    rawset(o, "IsVisible", function() return true end)
  end
  local function Place()
    Box(parts.frame.rankBox, 0, 300, 100, 420)
    for i, row in ipairs(parts.ranked) do Box(row, 6, 294, 400 - (i - 1) * 37 - 34, 400 - (i - 1) * 37) end
    Box(parts.frame.palette, 320, 600, 100, 420)
  end
  Place()
  local function Carry(frame, x, y)
    frame.scripts.OnDragStart(frame)
    assert(kit.Active(), "a drag has begun")
    c.cursorX, c.cursorY = x, y
    frame.scripts.OnDragStop(frame)
    assert(not kit.Active(), "and ended")
    Place()
  end
  -- the first card dropped just above the third card's middle goes between the second and third
  Carry(parts.ranked[1], 100, 320)
  assert(List() == "SPELLHIT,SP,INT,SPI", "a card moved down: " .. List())
  -- dropped where it already is: nothing changes
  Carry(parts.ranked[2], 100, 350)
  assert(List() == "SPELLHIT,SP,INT,SPI", "a drop that changes nothing is no drop: " .. List())
  -- dropped on nothing
  Carry(parts.ranked[2], 900, 900)
  assert(List() == "SPELLHIT,SP,INT,SPI", "a drop on nothing changes nothing")
  -- below the last card: the bottom
  Carry(parts.ranked[1], 100, 110)
  assert(List() == "SP,INT,SPI,SPELLHIT", "a card dropped under the list goes last: " .. List())
  -- a stat from "Not ranked", to the top
  assert(parts.chips.HASTE:IsShown() and not (parts.chips.SP and parts.chips.SP:IsShown()), "ranked stats leave the unranked ones")
  Carry(parts.chips.HASTE, 100, 395)
  assert(List() == "HASTE,SP,INT,SPI,SPELLHIT", "a stat dragged in: " .. List())
  -- a card dragged out onto "Not ranked" comes off the list
  Carry(parts.ranked[3], 400, 300)
  assert(List() == "HASTE,SP,SPI,SPELLHIT", "a card dragged out: " .. List())
  -- a click adds at the bottom
  Click(parts.chips.INT)
  assert(List() == "HASTE,SP,SPI,SPELLHIT,INT", "a click adds at the bottom: " .. List())
  -- a drag cancelled midway changes nothing
  parts.ranked[1].scripts.OnDragStart(parts.ranked[1])
  kit.Cancel()
  assert(List() == "HASTE,SP,SPI,SPELLHIT,INT" and parts.ranked[1]:IsShown(), "cancelling leaves the list")
  -- a stat can't be carried while values come from weights
  P.SetUsesPriority("MAGE", a.skillLine, false)
  parts.ranked[1].scripts.OnDragStart(parts.ranked[1])
  assert(not kit.Active(), "no drag outside stat priority")
  P.SetUsesPriority("MAGE", a.skillLine, true)
  P.SetPriority("MAGE", a.skillLine, nil)
  assert(parts.frame.rankEmpty:IsShown(), "an empty list says how to fill it")
  P.SetUsesPriority("MAGE", a.skillLine, false)
end

-- A question about resetting a tree is about the tree that was showing when it was asked, even if
-- another is chosen while it is open; cancelling changes nothing; a spoiled entry is refused by name.
do
  local pending
  c.StaticPopup_Show = function(key, text) pending = { dlg = c.StaticPopupDialogs[key], text = text } return {} end
  local printed = {}
  c.print = function(line) printed[#printed + 1] = line end
  P.SetUsesPriority("MAGE", a.skillLine, false); P.SetUsesPriority("MAGE", b.skillLine, false)
  Click(Card(a.skillLine))
  P.SetWeight("MAGE", a.skillLine, "SPI", 0.5); P.SetWeight("MAGE", b.skillLine, "SPI", 0.7)
  Click(parts.frame.reset)
  assert(pending and pending.text:find(a.name, 1, true) and pending.text:find("can't be undone", 1, true), "it names the tree: " .. tostring(pending and pending.text))
  Click(Card(b.skillLine))
  pending.dlg.OnAccept()
  assert(not (P.CustomWeights("MAGE", a.skillLine) or {}).SPI, "the tree that was asked about is reset")
  assert((P.CustomWeights("MAGE", b.skillLine) or {}).SPI == 0.7, "the tree chosen meanwhile is left alone")
  -- cancelled: nothing changes, and a stale press of the old button does nothing
  P.SetWeight("MAGE", b.skillLine, "SPI", 0.9)
  Click(parts.frame.reset)
  pending.dlg.OnCancel(nil, nil, "clicked")
  pending.dlg.OnAccept()
  assert((P.CustomWeights("MAGE", b.skillLine) or {}).SPI == 0.9, "cancelling leaves the weights as they were")
  -- a bad number is refused with the stat and the entry named, and the old value stays
  local row = Row("SPI")
  P.SetWeight("MAGE", b.skillLine, "SPI", nil)
  row.edit.text = "lots"
  rawset(row.edit, "revert", false)       -- the stand-in answers every unknown name with a function
  row.edit.scripts.OnEditFocusLost()
  assert(printed[#printed] and printed[#printed]:find("lots", 1, true) and printed[#printed]:find("0 to 1000", 1, true), "the entry is named: " .. tostring(printed[#printed]))
  assert(not (P.CustomWeights("MAGE", b.skillLine) or {}).SPI, "nothing was saved")
  c.StaticPopup_Show = function(key) c.StaticPopupDialogs[key].OnAccept() end
end

-- /twichui gear opens the page in the settings window.
c.SlashCmdList.TWICHUI("gear")
assert(opened == "statWeights", "slash command opens the Stat weights page")

-- A class without weights: a message instead.
opened = nil
c.UnitClass = function() return "Death Knight", "DEATHKNIGHT" end
GW:Show()
assert(opened == nil)
GW:Refresh()
assert(parts.frame.noClass:IsShown() and not parts.frame.editor:IsShown(), "the editor gives way to the explanation")
print("GEAR WINDOW SMOKE OK")
