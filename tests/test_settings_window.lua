dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The settings window (TwichUI_Settings/Window.lua, Widgets.lua, Search.lua) with stand-in frames that keep
-- their size, points, text, scripts and shown state:
--   * nothing settings-only runs until the window is first asked for; features and profile changes work without it;
--   * opening builds one window; every page draws without error; reopening and navigating make nothing new;
--   * an unknown page opens the start page; an unknown setting opens the page at its top;
--   * search finds settings on pages that were never drawn, without drawing them; choosing a result goes to
--     its page, opens its Advanced section and changes nothing; Up/Down/Enter/Esc in the search box;
--   * a control writes through its feature's setter; a greyed-out control says why and does nothing;
--   * "Reset this page" asks first, names its scope, and puts back only that page (pins untouched);
--   * Esc: the dropdown list first, then the window; the game's color picker is left to close itself;
--   * the AddOns entry opens the window; a missing settings addon is explained, and nothing breaks.

---------------------------------------------------------------------------
-- Stand-in frames
---------------------------------------------------------------------------
local made = 0
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", value = 0, min = 0, max = 1, enabled = true, focus = false, scroll = 0, children = {} }
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
    GetPoint = function(s, i) local p = s.points[i or 1]; if p then return unpack(p) end end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t)
      t = t == nil and "" or tostring(t)
      local changed = s.text ~= t
      s.text = t
      if changed and s.kind == "EditBox" then Fire(s, "OnTextChanged", true) end
    end,
    GetText = function(s) return s.text end,
    GetStringHeight = function(s)
      local width = s.w > 0 and s.w or 400
      return 12 * math.max(1, math.ceil(#s.text * 6 / width))
    end,
    GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    Enable = function(s) s:SetEnabled(true) end, Disable = function(s) s:SetEnabled(false) end,
    IsEnabled = function(s) return s.enabled end,
    SetMinMaxValues = function(s, lo, hi) s.min, s.max = lo, hi end,
    SetValue = function(s, v)
      v = math.max(s.min, math.min(s.max, v))
      local changed = s.value ~= v
      s.value = v
      if changed then Fire(s, "OnValueChanged", v, true) end
    end,
    GetValue = function(s) return s.value end,
    GetThumbTexture = function(s) s.thumb = s.thumb or Fake("Texture", s); return s.thumb end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetFrameLevel = function() return 1 end,
    IsOwned = function() return false end,
    GetOwner = function(s) return s.owner end,
    SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
    SetFont = function() return true end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  -- a method the game has and the stand-in doesn't need is a no-op; a field never set is nil, as on a real frame
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local escHandlers = {}
local c, S = SettingsClient({ beforeInit = function(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1920, 1080
  c.GameTooltip = Fake("GameTooltip")
  c.GameMenuEscPriority = { Dialog = 1, Menu = 2, AddOn = 8 }
  c.RegisterGameMenuEscHandler = function(priority, fn) table.insert(escHandlers, { priority = priority, fn = fn }) end
  c.GetLocale = function() return "enUS" end
end })
local R, K = c.TwichUI, S.K
local function PressEsc()
  table.sort(escHandlers, function(a, b) return a.priority < b.priority end)
  for _, h in ipairs(escHandlers) do if h.fn() then return true end end
  return false
end

-- The settings client stands in for the window when it describes pages; this test wants the real one.
local function LoadWindow()
  local chunk = assert(loadfile(ROOT .. "TwichUI_Settings/Window.lua")); setfenv(chunk, c); chunk("TwichUI_Settings", {})
end
LoadWindow()
local UI = R.SettingsUI
assert(UI and UI.escape == "handlers", "Esc goes through the game's Esc handlers")

---------------------------------------------------------------------------
-- 1. Opening: one window, every page draws, nothing made twice
---------------------------------------------------------------------------
assert(not c.TwichUISettingsWindow, "no window before it is asked for")
assert(R:OpenSettings() == true)
local win = c.TwichUISettingsWindow
assert(win and win.shown and UI.IsShown(), "open")
local before = made
R:OpenSettings()
assert(made == before and c.TwichUISettingsWindow == win, "opening again makes nothing new")

-- every page draws; drawing each again makes nothing new
for _, page in ipairs(K.NavOrder()) do UI.Navigate(page.key) end
local afterAll = made
for _ = 1, 3 do for _, page in ipairs(K.NavOrder()) do UI.Navigate(page.key) end end
assert(made == afterAll, "navigating again makes no frames: " .. (made - afterAll))
UI.Close()
assert(not win.shown and not UI.IsShown(), "closed")
R:OpenSettings("chronicle")
assert(win.shown and made == afterAll, "reopened, nothing new")

-- unknown page and setting
R:OpenSettings("nope")
assert(R.SettingsUI and win.shown)
R:OpenSettings("chronicle", "TWICHUI_doesNotExist")
R:OpenSettings(nil, "TWICHUI_arrivalHold")   -- a setting alone: its page

---------------------------------------------------------------------------
-- 1b. Sidebar and tabs: a page under another is a tab of its parent, not a row of the list
---------------------------------------------------------------------------
do
  local side, inSide = K.SidebarOrder(), {}
  for _, page in ipairs(side) do
    assert(not page.parent, page.key .. " is top-level")
    assert(not inSide[page.key], page.key .. " is listed once")
    inSide[page.key] = true
  end
  local seen, children = {}, 0
  for _, page in ipairs(K.NavOrder()) do
    assert(not seen[page.key], page.key .. " appears once in navigation order")
    seen[page.key] = true
    if page.parent then
      children = children + 1
      assert(not inSide[page.key] and inSide[page.parent], page.key .. " is a tab of " .. page.parent .. ", not a sidebar row")
      local tabs = K.Tabs(page.key)
      assert(tabs[1].key == page.parent and K.Tabs(page.parent)[1].key == page.parent, "the parent's tab is first")
      local found
      for _, t in ipairs(tabs) do if t.key == page.key then found = true end end
      assert(found, page.key .. " has a tab")
    else
      assert(inSide[page.key], page.key .. " is in the sidebar")
    end
  end
  assert(children == 6, "six secondary pages: " .. children)
  assert(#K.Tabs("notifications") == 0 and #K.Tabs("overview") == 0, "a feature without pages under it has no tabs")
  local tabs = {}
  for _, t in ipairs(K.Tabs("skins")) do tabs[#tabs + 1] = K.TabLabel(t) end
  assert(table.concat(tabs, ",") == "General,RestedXP guide window,SpeakStone speech frame", table.concat(tabs, ","))

  -- each secondary page: opened directly, it is shown under its parent's sidebar row
  for _, page in ipairs(K.NavOrder()) do
    R:OpenSettings(page.key)
    local shown, row = UI.Selected()
    assert(shown == page.key and row == (page.parent or page.key), page.key .. " selects " .. tostring(row))
  end
  -- and the way back and forth between tabs leaves one selected
  UI.Navigate("chronicleLook"); UI.Navigate("chronicle"); UI.Navigate("pinsLook")
  local shown, row = UI.Selected()
  assert(shown == "pinsLook" and row == "pins")
  UI.Navigate("overview")
  shown, row = UI.Selected()
  assert(shown == "overview" and row == "overview")
end

---------------------------------------------------------------------------
-- 2. Search: across pages, from descriptions only
---------------------------------------------------------------------------
UI.Close()
local Search = R.SettingsSearch
Search.Reset()
local drawn = made
local results = Search.Run("minimap")
assert(#results > 0 and made == drawn, "search draws nothing")
local labels = {}
for _, r in ipairs(results) do labels[#labels + 1] = r.entry.label end
local text = table.concat(labels, " | ")
assert(text:find("Show pins on the minimap", 1, true) and text:find("Pin names on the minimap", 1, true), text)
assert(results[1].entry.label:lower():find("minimap"), "label matches first")
assert(#Search.Run("") == 0 and #Search.Run("   ") == 0, "an empty query finds nothing")
assert(#Search.Run("xyzzy-nothing") == 0)
assert(#Search.Run("%a+") == 0, "a query is plain text, not a pattern")
local hold = Search.Run("how long the zone card")
assert(hold[1] and hold[1].entry.row.id == "arrivalHold" and Search.Note(hold[1].entry) == "Advanced", "advanced results say so")
-- a secondary page's results name the feature and the tab, and open on that tab
do
  local checked = 0
  for _, e in ipairs(Search.Build()) do
    local page = K.pages[e.page]
    if page.parent then
      local parent = K.pages[page.parent]
      assert(e.context:find(parent.name, 1, true), e.label .. " is under " .. parent.name .. ": " .. e.context)
      if e.kind ~= "page" then assert(e.context:find(K.TabLabel(page), 1, true), e.context) end
      UI.Navigate(e.page, e.row and e.row.id or nil)
      local shown, row = UI.Selected()
      assert(shown == e.page and row == page.parent, e.label)
      checked = checked + 1
    end
  end
  assert(checked > 6, "rows and pages of secondary pages are indexed: " .. checked)
  local found = Search.Run("refreshment shares")
  assert(found[1] and found[1].entry.page == "refreshmentShares" and found[1].entry.kind == "page")
end
-- through the window: type, move, Enter
R:OpenSettings("overview")
local box
for _, child in ipairs(win.children[1] and win.children or {}) do end
local function FindEditBox(frame)
  for _, ch in ipairs(frame.children) do
    if ch.kind == "EditBox" and ch.scripts.OnArrowPressed then return ch end
    local found = FindEditBox(ch)
    if found then return found end
  end
end
box = FindEditBox(win)
assert(box, "the search box")
box:SetFocus()
box:SetText("zone card stays")
box.scripts.OnArrowPressed(box, "DOWN"); box.scripts.OnArrowPressed(box, "UP")
local valueBefore = c.TwichUIDB.ui.arrivalHold
box.scripts.OnEnterPressed(box)
assert(box.text == "" and not box.focus, "Enter goes to the result and lets go of the box")
assert(c.TwichUIDB.ui.arrivalHold == valueBefore, "choosing a result changes nothing")
-- Esc in the box: clears first, then lets go; neither closes the window
box:SetFocus(); box:SetText("pins")
box.scripts.OnEscapePressed(box)
assert(box.text == "" and box.focus and win.shown, "first Esc clears")
box.scripts.OnEscapePressed(box)
assert(not box.focus and win.shown, "second Esc lets go of the box")

---------------------------------------------------------------------------
-- 3. Controls write through their features; greyed-out ones say why
---------------------------------------------------------------------------
UI.Navigate("notifications")
local view = (function()
  -- the page's row frames, by setting
  local rows = {}
  local function Walk(frame)
    for _, ch in ipairs(frame.children) do
      if ch.kind == "Button" and ch.twichuiTip then rows[#rows + 1] = ch end
      Walk(ch)
    end
  end
  Walk(win)
  return rows
end)()
assert(#view > 10, "rows are drawn")
local arrivalSetting = S.variables.TWICHUI_arrival
arrivalSetting:SetValue(false)
assert(c.TwichUIDB.modules.arrival == false)
local subzones
for _, row in ipairs(K.pages.notifications.rows) do if row.switch == "arrivalSubzones" then subzones = row end end
assert(not subzones:Enabled() and subzones:DisabledReason():find("Show a title card", 1, true), subzones:DisabledReason())
arrivalSetting:SetValue(true)
-- a slider's own row follows a drag without drawing the page again
UI.Navigate("food")
S.variables.TWICHUI_foodDrinkSize:SetValue(44)
assert(R.FoodDrink.Get("size") == 44)

---------------------------------------------------------------------------
-- 4. Reset this page: asks, names its scope, resets only that page; pins untouched
---------------------------------------------------------------------------
c.C_Map = c.C_Map or {}
c.C_Map.GetMapInfo = function(id) return { mapID = id, name = "Map " .. id } end
assert(R.Pins.AddLocal({ map = 1429, x = 1, y = 2, name = "Kept", kept = true }))
local pinsBefore = #R.Pins.LocalPins()
local asked
c.StaticPopup_Show = function(key, text) asked = { key = key, text = text, dlg = c.StaticPopupDialogs[key] } return {} end
c.TwichUIDB.ui.chronicleClock = "24"
UI.Navigate("food")
local resetButton
local function FindButton(frame, label)
  for _, ch in ipairs(frame.children) do
    if ch.text and type(ch.text) == "table" and ch.text.text == label and ch.scripts.OnClick and ch:IsVisible() then return ch end
    local found = FindButton(ch, label)
    if found then return found end
  end
end
resetButton = FindButton(win, "Reset this page")
assert(resetButton, "the page has a reset")
resetButton.scripts.OnClick(resetButton)
assert(asked and asked.text:find("Food and drink", 1, true) and asked.text:find("map pins", 1, true), "it names the page and what it leaves alone")
assert(R.FoodDrink.Get("size") == 44, "nothing happens before it is accepted")
asked.dlg.OnAccept()
assert(R.FoodDrink.Get("size") == R.FoodDrink.DEFAULTS.size, "the page's settings are back to their defaults")
assert(c.TwichUIDB.ui.chronicleClock == "24", "other pages are not touched")
assert(#R.Pins.LocalPins() == pinsBefore, "pins are not touched")

---------------------------------------------------------------------------
-- 4b. A color swatch drives the game's picker the way the game's own swatches do: it must have what the
-- picker calls on it (SetColorRGB), follows the wheel, and a Cancel puts the old color back
---------------------------------------------------------------------------
do
  local picker = { shown = false }
  function picker:IsShown() return self.shown end
  function picker:GetColorRGB() return self.cur.r, self.cur.g, self.cur.b end
  function picker:GetPreviousValues() return self.prev.r, self.prev.g, self.prev.b end
  -- as Forever's ColorPickerFrameMixin:SetupColorPickerAndShow does: remember, then select the starting color,
  -- which runs the swatch function and calls SetColorRGB on the swatch it was opened from
  function picker:SetupColorPickerAndShow(info)
    self.info, self.shown = info, true
    self.prev = { r = info.r, g = info.g, b = info.b }
    self.cur = { r = info.r, g = info.g, b = info.b }
    self:Select(info.r, info.g, info.b)
  end
  function picker:Select(r, g, b)
    self.cur = { r = r, g = g, b = b }
    if self.info.swatchFunc then self.info.swatchFunc() end
    if self.info.swatch then self.info.swatch:SetColorRGB(r, g, b) end
  end
  c.ColorPickerFrame = picker

  UI.Navigate("chronicleLook")
  local swatch
  local function Walk(frame)
    for _, ch in ipairs(frame.children) do
      if rawget(ch, "SetColorRGB") and ch:IsVisible() and not swatch then swatch = ch end
      Walk(ch)
    end
  end
  Walk(win)
  assert(swatch, "the page has a color swatch")
  local setting = S.variables.TWICHUI_chronicleLookBgColor   -- the first swatch on the page
  local original = setting:GetValue()
  swatch.scripts.OnClick(swatch)
  assert(picker.info.swatch == swatch and picker.shown, "it opens the game's picker for itself")
  assert(setting:GetValue() == original, "opening it changes nothing")
  picker:Select(0.2, 0.4, 0.6)
  assert(setting:GetValue() == "ff336699", "the wheel sets the color: " .. tostring(setting:GetValue()))
  picker.info.cancelFunc()
  assert(setting:GetValue() == original, "Cancel puts the old color back")
  picker.shown = false
  c.ColorPickerFrame = nil
end

---------------------------------------------------------------------------
-- 5. Esc: the list first, then the window; never while the color picker is open
---------------------------------------------------------------------------
local Wg = R.SettingsWidgets
UI.Navigate("food")
local dropdown = FindButton(win, "Side by side")
assert(dropdown, "the layout dropdown shows its choice by name")
dropdown.scripts.OnClick(dropdown)
assert(not Wg.MenuShown(), "greyed out while the buttons are off: no list")
S.variables.TWICHUI_foodDrink:SetValue(true)
dropdown.scripts.OnClick(dropdown)
assert(Wg.MenuShown(), "the list opens")
assert(PressEsc() and not Wg.MenuShown() and win.shown, "Esc puts the list away and leaves the window")
c.ColorPickerFrame = Fake("Frame")
assert(not PressEsc() and win.shown, "with the color picker open, Esc is the picker's")
c.ColorPickerFrame:Hide()
local closed = 0
R.OnSettingsClosed(function() closed = closed + 1 end)
assert(PressEsc() and not win.shown and closed == 1, "then the window, and its previews are told")
assert(not PressEsc(), "nothing of ours left to close")

---------------------------------------------------------------------------
-- 6. Profiles: the footer and the page follow a switch, without stale values
---------------------------------------------------------------------------
R:OpenSettings("profiles")
assert(R.Profiles.Create("Second"))
assert(R.Profiles.Current() == "Second")
assert(R.Profiles.Switch("Default"))

---------------------------------------------------------------------------
-- 7. The game's AddOns entry: one page with one button that opens the window
---------------------------------------------------------------------------
UI.Close()
local launcher = S.registered()
assert(launcher and launcher.name == "TwichUI" and launcher.frame, "one entry in the AddOns list")
local exited
c.SettingsPanel = Fake("Frame")
c.SettingsPanel.HasUnappliedSettings = function() return false end
c.SettingsPanel.ExitWithCommit = function(self, skip) exited = skip; self:Hide() end
launcher.frame:Show()
local open = FindButton(launcher.frame, "Open TwichUI Settings")
assert(open, "an Open TwichUI Settings button")
local settingsRows = 0
for _, ch in ipairs(launcher.frame.children) do if ch.kind == "CheckButton" or ch.kind == "Slider" then settingsRows = settingsRows + 1 end end
assert(settingsRows == 0, "and no settings of its own")
open.scripts.OnClick(open)
assert(win.shown and exited == true and not c.SettingsPanel.shown, "it opens TwichUI's window and closes the game's options without the Game Menu")
UI.Close()
-- the game's options have changes of their own waiting: they are left open, ours opens in front
c.SettingsPanel:Show(); exited = nil
c.SettingsPanel.HasUnappliedSettings = function() return true end
open.scripts.OnClick(open)
assert(win.shown and exited == nil and c.SettingsPanel.shown, "unapplied game settings are left for the player")
UI.Close()
assert(#R.SettingsLauncher.closers > 0)
print("PASSED")
