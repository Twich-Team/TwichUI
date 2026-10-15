dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Mage page, "Handling mode": two choices, the EllesmereUI one annotated while its Junk Marker can't be used,
-- the first choice of it asks for a confirmation that stays on this computer, and the status row says what is
-- going on. The popup is Blizzard's own; here it is only recorded.
local c, S = SettingsClient()
local R, K = c.TwichUI, c.TwichUI.SettingsKit
local MS = R.MageSell

local shown
c.StaticPopup_Show = function(name, text) shown = { name = name, text = text } end

local function Page(name) for _, cat in ipairs(S.pages) do if cat.name == name then return cat end end end
local function Row(label)
  for _, i in ipairs(Page("Mage").rows) do
    if i:GetName() == label then return i end
  end
end

local mode = Row("Handling mode")
assert(mode and mode.kind == "dropdown", "the mode control is on the Mage page")
local setting = mode:GetSetting()
assert(setting:GetValue() == "direct" and setting.default == "direct", "existing and new users sell directly")
local choices = mode.choices()
assert(#choices == 2 and choices[1].value == "direct" and choices[1].label == "Sell directly", "first: Sell directly")
assert(choices[2].value == "ellesmere" and choices[2].label:find("^Mark as junk with EllesmereUI"), "second: Mark as junk with EllesmereUI")
assert(choices[2].label:find("not available now", 1, true), "annotated while EllesmereUI's Junk Marker can't be used: " .. choices[2].label)

-- greyed out under the feature's own switch
assert(mode.parent and mode.parent:GetName() == "Sell non-conjured food and drink", "under the existing enable control")
assert(S.variables.TWICHUI_mageSell, "the enable control is still there")

-- the first choice of EllesmereUI asks first, and changes nothing
setting:SetValue("ellesmere")
assert(shown and shown.name == "TWICHUI_MAGE_SELL_MARK", "the confirmation was asked for")
assert(shown.text:find("every copy", 1, true) or shown.text:find("kind of item", 1, true), "it names the scope")
assert(shown.text:find("never removes marks", 1, true), "and that nothing is unmarked")
assert(MS.Mode() == "direct" and not MS.Acknowledged() and setting:GetValue() == "direct", "nothing changed yet")
-- cancelled: still nothing
assert(c.TwichUIDB.ui == nil or c.TwichUIDB.ui.mageSellMode == nil, "nothing saved")
-- accepted
c.StaticPopupDialogs.TWICHUI_MAGE_SELL_MARK.OnAccept()
assert(MS.Mode() == "ellesmere" and MS.Acknowledged(), "confirmed: the mode is set, and the confirmation kept")
assert(c.TwichUIDB.ui.mageSellMode == "ellesmere" and c.TwichUIDB.ui.mageSell.euiAck == true)
assert(setting:GetValue() == "ellesmere")

-- back and forth: no second question, nothing erased
shown = nil
setting:SetValue("direct")
assert(MS.Mode() == "direct" and MS.Acknowledged() and shown == nil)
setting:SetValue("ellesmere")
assert(MS.Mode() == "ellesmere" and shown == nil, "already confirmed: no second question")

-- the status row
local status = Row("EllesmereUI marking status")
assert(status and status.kind == "button")
local function Text() local t = status.data.buttonText; return type(t) == "function" and t() or t end
c.TwichUIDB.modules.mageSell = false
assert(Text() == "Not in use", "feature off: " .. tostring(Text()))
c.TwichUIDB.modules.mageSell = true
assert(Text() == "Not available", "EllesmereUI isn't there: " .. tostring(Text()))
assert(select(1, MS.MarkState()) ~= "direct", "and it is not reported as selling")
c.TwichUIDB.ui.mageSell.euiAck = nil
assert(Text() == "Needs confirmation", "a mode that arrived unconfirmed: " .. tostring(Text()))
-- its click asks, as choosing it does
shown = nil
status.click()
assert(shown and shown.name == "TWICHUI_MAGE_SELL_MARK", "clicking it offers the confirmation")
c.StaticPopupDialogs.TWICHUI_MAGE_SELL_MARK.OnAccept()
assert(MS.Acknowledged())

-- the other rows keep working in both modes and say so
for _, label in ipairs({ "Sell ordinary food", "Sell ordinary drink", "Dry run: report only, sell nothing" }) do
  assert(Row(label), label .. " is still there")
end

print("MAGE SELL SETTINGS PASSED")
