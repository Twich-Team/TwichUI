dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Vendor restocking in the settings window and in configuration sharing:
--   * the page's rows: on/off, Ask/Automatic (automatic needs its own confirmation, and a profile or a share can't
--     give it), the spending limit through the game's money entry;
--   * the Restock items tab: dropping an item (it goes back; anything else is refused and left on the cursor), typing
--     an ID (unknown ones refused), a repeat focuses the rule already there, item details that arrive late or never,
--     targets, on/off, order, Remove, nothing made again on a redraw;
--   * class suggestions: your class first, others on request, nothing added until you click, nothing removed when
--     the class or the profile changes;
--   * profiles: each its own list and mode, the confirmation account-wide;
--   * sharing: the list and how it buys travel; whether it is on and the confirmation don't; no counts or purchases;
--     the review says what it means for spending; applying merges by item; Undo puts it back.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetTexture = function(s, t) s.texture = t end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local ITEMS = {
  [17020] = { "Arcane Powder", 20 }, [17031] = { "Rune of Teleportation", 20 }, [17032] = { "Rune of Portals", 20 },
  [17056] = { "Light Feather", 20 }, [2512] = { "Rough Arrow", 200 }, [2515] = { "Sharp Arrow", 200 },
  [2516] = { "Light Shot", 200 }, [2519] = { "Heavy Shot", 200 }, [4242] = { "Mystery Thing", 20 },
}
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.UNLOADED, c.REQUESTED = {}, {}
  c.CLASS = "MAGE"
  c.UnitClass = function() return "X", c.CLASS end
  c.C_Item = {
    GetItemInfoInstant = function(id) if ITEMS[id] then return id, "", "", "", 1000 + id, 15, 0 end end,
    GetItemIconByID = function(id) if ITEMS[id] then return 1000 + id end end,
    GetItemNameByID = function(id) if ITEMS[id] and not c.UNLOADED[id] then return ITEMS[id][1] end end,
    GetItemInfo = function(id) if ITEMS[id] and not c.UNLOADED[id] then return ITEMS[id][1], "[" .. ITEMS[id][1] .. "]" end end,
    GetItemMaxStackSizeByID = function(id) return ITEMS[id] and ITEMS[id][2] end,
    RequestLoadItemDataByID = function(id) c.REQUESTED[id] = (c.REQUESTED[id] or 0) + 1 end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end,
  }
  c.CURSOR = nil
  c.CLEARED = 0
  c.GetCursorInfo = function() if c.CURSOR then return c.CURSOR[1], c.CURSOR[2] end end
  c.ClearCursor = function() c.CLEARED = c.CLEARED + 1; c.CURSOR = nil end
  c.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", HUNTER = "Hunter", WARRIOR = "Warrior", PRIEST = "Priest" }
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.BAGS = { [0] = { [1] = { 17020, 7 } } }
  c.C_Container = {
    GetContainerNumSlots = function(bag) return c.BAGS[bag] and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local s = c.BAGS[bag] and c.BAGS[bag][slot]
      if s then return { itemID = s[1], stackCount = s[2] } end
    end,
    GetContainerNumFreeSlots = function() return 10, 0 end,
  }
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local RS, K = R.Restock, S.K
local function Flush() for _ = 1, 4 do FlushTimers() end end

---------------------------------------------------------------------------
-- 1. The page and its rows
---------------------------------------------------------------------------
local page, tab
for _, p in ipairs(S.pages) do
  if p.key == "restock" then page = p elseif p.key == "restockItems" then tab = p end
end
Check(page and page.group == "everyday" and page.kind == "page", "Vendor restocking is a page of its own under Everyday")
Check(tab and tab.parent == "Vendor restocking" and tab.kind == "hosted", "its items are a tab of it")
Check(S.variables.TWICHUI_restock and S.variables.TWICHUI_restock:GetValue() == false, "off by default")
local mode = S.variables.TWICHUI_restockMode
Check(mode and mode:GetValue() == "ask" and mode:GetDefaultValue() == "ask", "asks first by default")
local useLimit = S.variables.TWICHUI_restockUseLimit
Check(useLimit and useLimit:GetValue() == false, "no spending limit by default")

-- choosing automatic asks first, and nothing changes until it is confirmed
S.popup = nil
mode:SetValue("auto")
Check(S.popup and S.popup.key == "TWICHUI_RESTOCK_AUTO" and S.popup.text:find("spends your money", 1, true), "automatic: says what it authorizes")
Check(RS.SavedMode() == "ask" and not RS.Acknowledged(), "and changes nothing yet")
c.StaticPopupDialogs.TWICHUI_RESTOCK_AUTO.OnAccept()
Check(RS.Acknowledged() and RS.SavedMode() == "auto" and RS.Mode() == "auto", "confirmed: automatic")
mode:SetValue("ask")
Check(RS.Mode() == "ask" and RS.Acknowledged(), "back to asking; the confirmation is kept")

-- the spending limit, in the game's money entry
local limitRow
for _, row in ipairs(K.pages.restock.rows) do if row.data.name == "Spending limit per visit" then limitRow = row end end
Check(limitRow and not limitRow:Enabled() and limitRow:DisabledReason():find("Limit spending"), "the amount is greyed out until the limit is on, and says why")
useLimit:SetValue(true)
Check(RS.SpendLimit() == RS.DEFAULTS.limit and limitRow:Enabled() == false, "limit on; the amount still needs restocking on")
R:SetEnabled("restock", true)
Check(limitRow:Enabled(), "and then it can be changed")
S.popup = nil
limitRow.click()
local dlg = c.StaticPopupDialogs.TWICHUI_RESTOCK_LIMIT
Check(S.popup and S.popup.key == "TWICHUI_RESTOCK_LIMIT" and dlg and dlg.hasMoneyInputFrame == 1, "the game's gold, silver and copper boxes")
local box = { copper = nil }
c.MoneyInputFrame_SetCopper = function(_, v) box.copper = v end
c.MoneyInputFrame_GetCopper = function() return box.copper end
c.MoneyInputFrame_ResetMoney = function() box.copper = nil end
dlg.OnShow({ MoneyInputFrame = {} })
Check(box.copper == RS.DEFAULTS.limit, "shows the current limit")
box.copper = 12345; dlg.OnAccept({ MoneyInputFrame = {} })
Check(RS.SpendLimit() == 12345 and RS.MoneyText(12345) == "1g 23s 45c", "saved")
box.copper = 0; dlg.OnAccept({ MoneyInputFrame = {} })
Check(RS.SpendLimit() == 0, "0 is a limit of its own")
box.copper = 100000000; c.said = nil
dlg.OnAccept({ MoneyInputFrame = {} })
Check(RS.SpendLimit() == 0, "more than the most a limit can be is refused")
useLimit:SetValue(false)
Check(RS.SpendLimit() == nil and RS.Get("limit") == 0, "off: no limit, and the amount is kept for next time")

---------------------------------------------------------------------------
-- 1b. The question window's appearance: its controls, the greyed-out ones with a reason, Preview and Reset
---------------------------------------------------------------------------
do
  local PR = R.RestockPrompt
  local Style = PR.Style
  local rowsByName, header = {}, false
  for _, row in ipairs(K.pages.restock.rows) do
    if row.data and row.data.name then rowsByName[row.data.name] = row end
    if row.setting and row.setting.variable then rowsByName[row.setting.variable] = row end
    if not row.setting and not row.click and row.data.name == "Question window appearance" then header = true end
  end
  Check(header, "a section for the question window's look")
  for _, suffix in ipairs({ "BgTexture", "BgColor", "BgOpacity", "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }) do
    Check(S.variables["TWICHUI_restockPrompt" .. suffix], suffix .. " is on the page")
  end
  local size, color, opacity = rowsByName.TWICHUI_restockPromptBorderSize, rowsByName.TWICHUI_restockPromptBorderColor, rowsByName.TWICHUI_restockPromptBorderOpacity
  Check(size and color and opacity and rowsByName.TWICHUI_restockPromptBgTexture:Enabled(), "the rows are there")
  Check(not size:Enabled() and size:DisabledReason():find("fixed width", 1, true), "the rim's thickness is greyed out, and says why")
  Check(not color:Enabled() and color:DisabledReason():find("own colors", 1, true) and not opacity:Enabled(), "and its color and opacity")
  S.variables.TWICHUI_restockPromptBorderTexture:SetValue("solid")
  Check(size:Enabled() and color:Enabled() and opacity:Enabled(), "another border can be sized, colored and faded")
  Check(Style.Get("borderTexture") == "solid" and c.TwichUIDB.ui.restockPromptStyle.borderTexture == "solid", "saved in its own table")
  S.variables.TWICHUI_restockPromptBorderTexture:SetValue("none")
  Check(not size:Enabled() and size:DisabledReason():find("o border is drawn", 1, true), "no border: greyed out, and says why")
  S.variables.TWICHUI_restockPromptBorderTexture:SetValue(PR.LEDGER)
  S.variables.TWICHUI_restockPromptBgOpacity:SetValue(40)
  Check(Style.Get("bgOpacity") == 40 and RS.Get("mode") == "ask" and RS.Get("limit") == 0 and #RS.Rules() == 0, "only the look is written")

  -- Preview works whether or not restocking is on, and buys nothing
  c.UISpecialFrames = c.UISpecialFrames or {}
  local preview = rowsByName["Preview"]
  R:SetEnabled("restock", false)
  Check(preview and preview:Enabled(), "Preview is there with restocking off")
  preview.click()
  Check(PR.IsPreview(), "Preview shows the window")
  preview.click()
  Check(not PR.IsShown(), "and puts it away")

  local reset = rowsByName["Question window appearance"]
  Check(reset and reset.click, "a reset for the look")
  S.ClickReset(reset)
  Check(c.TwichUIDB.ui.restockPromptStyle == nil and Style.Get("bgOpacity") == Style.DEFAULTS.bgOpacity, "Reset puts the look back")
  Check(RS.Get("mode") == "ask", "and leaves how it buys alone")
end

---------------------------------------------------------------------------
-- 2. The Restock items tab
---------------------------------------------------------------------------
local P = R.RestockItemsPage
local f = P.Frame()
Check(P.Frame() == f, "one frame")
f:Hide()
f:Show()   -- built the first time it is shown
Check(f.empty and f.empty.shown and f.count.text == "0 of " .. RS.MAX_ITEMS, "an empty list says how to add an item")
Check(f.events.ITEM_DATA_LOAD_RESULT and f.events.BAG_UPDATE_DELAYED, "listens while shown")

-- typing an item ID
Check(not P.AddFromText("12x") and P.lastTone == "warn", "not a number")
Check(not P.AddFromText("999999") and P.lastSaid:find("No item has the ID 999999"), "an ID the game doesn't know")
f.idBox:SetText("17020")
f.idBox:Fire("OnEnterPressed")
local list = RS.Rules()
Check(#list == 1 and list[1].id == 17020 and list[1].target == 20 and list[1].enabled, "added on, with the default target")
Check(f.idBox.text == "" and P.lastSaid:find("Added Arcane Powder"), "the box is cleared and it says what was added")
Flush()
-- a list row: the scroll child's child showing that item
local function RowFor(id)
  for _, ch in ipairs(f.content.children) do
    if ch.target and ch.id == id and ch.shown then return ch end
  end
end
local function Rows()
  local n = 0
  for _, ch in ipairs(f.content.children) do if ch.target then n = n + 1 end end
  return n
end
Check(Rows() == 1 and RowFor(17020), "one row for one item")
f.idBox:SetText("17031"); f.idBox:Fire("OnEnterPressed")
Flush()
local row2 = RowFor(17031)
Check(#RS.Rules() == 2 and Rows() == 2, "a second item, a second row")
Check(row2 and row2.name.text == "Rune of Teleportation" and row2.target.text == "20" and row2.check:GetChecked() == true, "drawn with its name, target and on")
Check(row2.target.focus, "the new item's target box has the cursor")

-- the same item again: focused, not added
row2.target:ClearFocus()
P.AddFromText("17031")
Check(#RS.Rules() == 2 and P.lastSaid:find("already on your list") and row2.target.focus, "a repeat finds the rule already there")
row2.target:ClearFocus()

-- targets: refused, then saved
row2.target:SetFocus(); row2.target:SetText("0"); row2.target:ClearFocus()
Check(RS.Rule(17031).target == 20 and P.lastSaid:find("whole number from 1 to 9999") and row2.target.text == "20", "0 is refused and put back")
row2.target:SetFocus(); row2.target:SetText("45"); row2.target:ClearFocus()
Check(RS.Rule(17031).target == 45, "a good target is saved")
row2.target:SetFocus(); row2.target:SetText("99"); row2.target:Fire("OnEscapePressed")
Check(RS.Rule(17031).target == 45 and row2.target.text == "45", "Esc puts the old number back")

-- on/off and order
row2.check:Fire("OnClick")
Check(RS.Rule(17031).enabled == false and RS.Rule(17031).target == 45, "off keeps the target")
Flush()
Check(row2.status.text:find("Off:", 1, true) and row2.check:GetChecked() == false, "and says it isn't bought")
Check(RowFor(17020).status.text:find("You carry 7: buys up to 13 more", 1, true), "an item on: what you carry and what it would buy (" .. RowFor(17020).status.text .. ")")
row2.up:Fire("OnClick")
Flush()
Check(RS.Rules()[1].id == 17031 and RowFor(17031).up.enabled == false and RowFor(17020).down.enabled == false, "moved up; the ends can't go further")
RowFor(17031).check:Fire("OnClick")
Check(RS.Rule(17031).enabled == true, "on again")

-- dropping: anything but an item is refused and left on the cursor; an item goes back to the bag
c.CURSOR = { "spell", 133 }
Check(not P.AddFromCursor() and c.CURSOR and c.CLEARED == 0 and P.lastTone == "warn", "a spell is refused and left alone")
c.CURSOR = { "item", 17056 }
f.drop:Fire("OnReceiveDrag")
Check(RS.Rule(17056) and c.CURSOR == nil and c.CLEARED == 1, "an item dropped is added and goes back where it came from")
c.CURSOR = { "item", 17056 }
f.drop:Fire("OnClick")
Check(#RS.Rules() == 3 and c.CLEARED == 2 and P.lastSaid:find("already on your list"), "dropped again: no second rule")
Check(not P.AddFromCursor(), "an empty cursor does nothing")

-- item details that arrive late, and an item the game says doesn't exist
c.UNLOADED[17032] = true
P.AddFromText("17032")
Flush()
local row3 = RowFor(17032)
Check(row3.status.text:find("Loading", 1, true) and row3.name.text == "Item 17032" and (c.REQUESTED[17032] or 0) >= 1,
  "not loaded yet: asked for, shown as loading, no name made up")
for _ = 1, 5 do P.Refresh() end
Check(c.REQUESTED[17032] == 2, "asked for at most twice")
c.UNLOADED[17032] = nil
f:Fire("OnEvent", "ITEM_DATA_LOAD_RESULT", 17032, true)
Flush()
Check(row3.name.text == "Rune of Portals", "its name once the game has it")
ITEMS[4242] = { "Mystery Thing", 20 }
c.UNLOADED[4242] = true
P.AddFromText("4242")
f:Fire("OnEvent", "ITEM_DATA_LOAD_RESULT", 4242, false)
Flush()
local row4 = RowFor(4242)
Check(row4.status.text:find("no item with the ID 4242", 1, true), "the game says there is no such item: said so")

-- remove: off the list; bags untouched
local before = c.BAGS[0][1][2]
P.Refresh()
row4.remove:Fire("OnClick")
Check(not RS.Rule(4242) and P.lastSaid:find("Nothing in your bags was touched") and c.BAGS[0][1][2] == before, "removed")
Flush()

-- redraws make nothing new
local count = made
for _ = 1, 5 do P.Refresh() end
f:Hide(); f:Show(); Flush()
Check(made == count, "redrawing and reopening make no new frames")
Check(f.events.ITEM_DATA_LOAD_RESULT, "listening again when shown")
f:Hide()
Check(not f.events.ITEM_DATA_LOAD_RESULT and not f.events.BAG_UPDATE_DELAYED, "and not while hidden")
f:Show()

---------------------------------------------------------------------------
-- 3. Class suggestions
---------------------------------------------------------------------------
do
  local mine = RS.Suggestions()
  Check(#mine == 4 and mine[1].id == 17020 and mine[1].listed, "a Mage's reagents, with what is already listed")
  local rulesBefore = #RS.Rules()
  P.Refresh()
  Check(#RS.Rules() == rulesBefore, "showing suggestions adds nothing")
  -- the class dropdown lists every class with suggestions, in the dropdown's own { value, label } shape
  local choices = f.sugClass.choices and f.sugClass.choices() or {}
  Check(#choices == #RS.SUGGESTION_CLASSES, "every class with suggestions is a choice (" .. #choices .. ")")
  for _, choice in ipairs(choices) do
    Check(type(choice.value) == "string" and RS.SUGGESTIONS[choice.value] and type(choice.label) == "string" and choice.label ~= "",
      "a choice has a class and a label to show")
  end
  -- the dropdown chooses another class; clicking one adds just that one
  f.sugClass.onPick("HUNTER")
  Check(#RS.Suggestions("HUNTER") == 4, "a Hunter's ammunition")
  local ok, how = P.AddSuggestion(2512)
  Check(ok and how == "added" and RS.Rule(2512).target == 1000 and RS.Rule(2512).enabled, "one suggestion added, with its target")
  Check(not RS.Rule(2515) and not RS.Rule(2516), "and only that one")
  ok, how = P.AddSuggestion(2512)
  Check(ok and how == "exists" and #RS.Rules() == rulesBefore + 1, "clicking it again finds it")
  Check(not P.AddSuggestion(17020 + 1), "only a suggestion can be added this way")
  for class, list in pairs(RS.SUGGESTIONS) do
    local seen = {}
    for _, s in ipairs(list) do
      Check(not seen[s.id] and type(s.use) == "string" and s.target >= 1 and s.target <= RS.MAX_TARGET, class .. " suggestion " .. s.id .. " is well formed")
      seen[s.id] = true
    end
  end
  Check(not RS.SUGGESTIONS.WARRIOR and #RS.Suggestions("WARRIOR") == 0, "no suggestions made up for a class without vendor reagents")
  -- a different class (or character) doesn't take anything off the list
  c.CLASS = "WARRIOR"
  f.sugClass.onPick(nil)
  P.Refresh()
  Check(#RS.Rules() == rulesBefore + 1 and f.sugNone.shown, "the list is kept; a class with none says so")
  c.CLASS = "MAGE"
end

---------------------------------------------------------------------------
-- 4. Profiles: each its own list and mode; the confirmation stays with the account
---------------------------------------------------------------------------
do
  local PF = R.Profiles
  local mainRules = #RS.Rules()
  RS.Set("mode", "auto")
  Check(RS.Mode() == "auto", "automatic in Default")
  Check(PF.Create("Alt"), "a second profile")
  Check(#RS.Rules() == 0 and RS.SavedMode() == "ask" and RS.Acknowledged(), "a new profile: empty list, asks first; the confirmation is the account's")
  RS.Add(17056, 5)
  Check(PF.Switch("Default"), "back")
  Check(#RS.Rules() == mainRules and RS.Mode() == "auto", "Default's own list and mode again")
  Flush()
  Check(f.count.text == mainRules .. " of " .. RS.MAX_ITEMS, "the tab follows the profile")
  RS.Set("mode", "ask")
end

---------------------------------------------------------------------------
-- 5. Sharing: what travels, the review, applying, Undo
---------------------------------------------------------------------------
do
  local TC = R.TwichConfig
  local g1, g2 = TC.Group("restock"), TC.Group("restockItems")
  Check(g1 and g1.complete and TC.Usable(g1) and g2 and TC.Usable(g2), "two sharing groups: how it buys, and the items")
  Check(TC.LOCAL["modules.restock"] == "acts" and TC.LOCAL["ui.restockAck"] == "acts", "whether it is on, and the confirmation, stay here")
  RS.Set("useLimit", true); RS.Set("limit", 5000)
  local entry = TC.Build({ all = true })
  local items = entry.groups.restockItems.items
  Check(#items == #RS.Rules() and items[1].id == RS.Rules()[1].id and items[1].target and items[1].enabled ~= nil, "the list, in order")
  for _, e in ipairs(items) do
    for k in pairs(e) do Check(k == "id" or k == "target" or k == "enabled", "an item carries only its id, target and on/off") end
  end
  Check(entry.groups.restock.restock.mode == "ask" and entry.groups.restock.restock.useLimit == true and entry.groups.restock.restock.limit == 5000,
    "how it buys")
  for _, grp in pairs(entry.groups) do
    for slot, vals in pairs(grp) do
      if type(vals) == "table" then Check(vals.restockAck == nil and not (slot == "modules" and vals.restock ~= nil), "no switch or confirmation") end
    end
  end

  -- the receiver: a list of its own, asking first, not confirmed
  local B = SettingsClient({ name = "Bob", beforeInit = World })
  local BR = B.TwichUI
  local BTC, BRS = BR.TwichConfig, BR.Restock
  BRS.Add(17020, 99)
  BRS.Add(17032, 3)
  local sent = { schema = 1, status = "ok", groups = {
    restock = { restock = { mode = "auto", useLimit = true, limit = 2500 } },
    restockItems = { items = { { id = 17020, target = 30, enabled = true }, { id = 2512, target = 1000, enabled = true },
      { id = 17056, target = 15, enabled = false } } } } }
  local clean = BTC.CleanEntry(sent)
  Check(clean.status == "ok" and clean.groups.restockItems and clean.groups.restock, "a share with restocking reads")
  local plan = BTC.Plan(clean)
  local byId = {}
  for _, g in ipairs(plan.groups) do byId[g.id] = g end
  Check(byId.restockItems.state == "changed" and #byId.restockItems.changes == 3, "three items would change")
  local spending = table.concat(plan.spending, " ")
  Check(spending:find("chooses Purchase automatically", 1, true) and spending:find("keeps asking", 1, true),
    "the review says automatic is chosen and still asks until confirmed here: " .. spending)
  Check(spending:find("2 of them on", 1, true) and spending:find("25s", 1, true), "and the items and limit it brings: " .. spending)
  local key = BTC.PlanKey(plan)
  local ok, report = BTC.Apply(clean, { expect = key, from = "Rich" })
  Check(ok, "applied: " .. tostring(report))
  local after = BRS.Rules()
  Check(#after == 4 and after[1].id == 17020 and after[1].target == 30 and after[2].id == 17032 and after[2].target == 3
    and after[3].id == 2512 and after[4].id == 17056 and after[4].enabled == false, "merged by item: named ones set, new at the end, the rest kept")
  Check(BRS.SavedMode() == "auto" and BRS.Mode() == "ask" and BRS.AutoWaiting(), "automatic is chosen, and still asks until confirmed here")
  Check(not BRS.Enabled(), "and restocking isn't turned on by an import")
  Check(BRS.SpendLimit() == 2500, "the limit")
  local undone = BTC.Undo()
  Check(undone, "Undo")
  after = BRS.Rules()
  Check(#after == 2 and after[1].id == 17020 and after[1].target == 99 and after[2].id == 17032, "Undo puts the list back")
  Check(BRS.SavedMode() == "ask" and BRS.SpendLimit() == nil, "and how it buys")

  -- damaged or oversized lists are refused whole
  local function Rejected(items) return BTC.CleanEntry({ schema = 1, groups = { restockItems = { items = items } } }).rejected.restockItems end
  Check(Rejected({ { id = 17020, target = 0, enabled = true } }), "a target of 0")
  Check(Rejected({ { id = 17020, target = 5, enabled = "yes" } }), "an on/off that isn't one")
  Check(Rejected({ { id = 17020, target = 5, enabled = true }, { id = 17020, target = 6, enabled = true } }), "an item twice")
  Check(Rejected({ { id = -4, target = 5, enabled = true } }), "a bad ID")
  local many = {}
  for i = 1, BRS.MAX_ITEMS + 1 do many[i] = { id = i, target = 1, enabled = true } end
  Check(Rejected(many), "too many")
  Check(BTC.CleanEntry({ schema = 1, groups = { restock = { restock = { mode = "buy-everything" } } } }).rejected.restock, "an unknown mode")
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_restock_settings failed")
end
print("RESTOCK SETTINGS PASSED")
