dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- The settings window (TwichUI_Settings/Window.lua, Widgets.lua, Search.lua) with stand-in frames that keep
-- their size, points, text, scripts and shown state:
--   * nothing settings-only runs until the window is first asked for; features and profile changes work without it;
--   * opening builds one window; every page draws without error; reopening and navigating make nothing new;
--   * an unknown page opens the start page; an unknown setting opens the page at its top;
--   * search finds settings on pages that were never drawn, without drawing them; choosing a result goes to
--     its page and changes nothing; Up/Down/Enter/Esc in the search box;
--   * a control writes through its feature's setter; a greyed-out control says why and does nothing;
--   * "Reset this page" asks first, names its scope, and puts back only that page (pins untouched);
--   * Esc: the dropdown list first, then the window; the game's color picker is left to close itself; it goes
--     through the game's list of frames Esc closes, never RegisterGameMenuEscHandler (an addon calling that
--     taints the game's Esc path: ADDON_ACTION_FORBIDDEN for SpellStopCasting);
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
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
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

local registeredEscHandlers = 0   -- calls an addon made into the game's own handler table (taints it)
local c, S = SettingsClient({ beforeInit = function(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1920, 1080
  c.GameTooltip = Fake("GameTooltip")
  c.GameMenuEscPriority = { Dialog = 1, Menu = 2, AddOn = 8 }
  c.RegisterGameMenuEscHandler = function() registeredEscHandlers = registeredEscHandlers + 1 end
  c.UISpecialFrames = { "ColorPickerFrame" }   -- as the game has it: the picker is in the list itself
  c.GetLocale = function() return "enUS" end
end })
local R, K = c.TwichUI, S.K
-- The game's CloseSpecialWindows (Blizzard_UIParentPanelManager): every listed frame that is shown is hidden.
local function PressEsc()
  local found = false
  for _, name in ipairs(c.UISpecialFrames) do
    local frame = c[name]
    if frame and frame:IsShown() then frame:Hide(); found = true end
  end
  return found
end

-- The settings client stands in for the window when it describes pages; this test wants the real one.
local function LoadWindow()
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Settings/Window.lua")); setfenv(chunk, c); chunk("TwichUI_Settings", {})
end
LoadWindow()
local UI = R.SettingsUI
assert(UI and UI.escape == "special-frames", "Esc goes through the game's list of frames Esc closes")
assert(registeredEscHandlers == 0, "the game's own Esc handler table is never written to from the addon (taint)")

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

-- A setting that used to sit behind "Show advanced options" is drawn at once, in view, with no toggle to open:
-- reaching it by link or search needs nothing to be turned on first.
do
  local function Visible(frame, text)
    if frame.text == text and frame.IsVisible and frame:IsVisible() then return true end
    for _, child in ipairs(frame.children or {}) do
      if Visible(child, text) then return true end
    end
    return false
  end
  assert(c.TwichUIDB.ui.showAdvanced == nil, "no advanced preference exists")
  R:OpenSettings("qol", "TWICHUI_qolSummonsWait")
  assert(Visible(win, "Wait before accepting a summon"), "the summon wait is drawn on Quality of life without any toggle")
  assert(Visible(win, "Accept summons from"), "beside Accept summons from")
  assert(not Visible(win, "Show advanced options") and not Visible(win, "Show"), "no disclosure control is drawn")
  R:OpenSettings("gear", "TWICHUI_gearStrictness")
  assert(Visible(win, "How big a gain counts"), "a formerly advanced gear setting is drawn")
  R:OpenSettings("overview")
  assert(not Visible(win, "Show advanced options"), "Home has no advanced-options checkbox")
end

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
-- 1c. Motion: eases only while something is easing, stops cleanly, and respects the preference
---------------------------------------------------------------------------
do
  local M = R.SettingsWidgets.Motion
  local ui = c.TwichUIDB.ui
  UI.Close(); M.Settle()
  assert(M.Count() == 0 and win.alpha == 1, "shut and settled: nothing easing, the window at full opacity")

  -- a Fader eases there, and nothing runs afterwards
  local f = M.Fader(function() end, 0)
  f:To(1, 0.1)
  assert(M.Count() == 1 and f:Active())
  M.Advance(0.04)
  assert(f.value > 0 and f.value < 1, "part of the way")
  f:To(0, 0.1)                      -- reversed mid-way: from where it is, not from the end
  assert(M.Count() == 1 and f.value > 0 and f.value < 1)
  M.Advance(1)
  assert(f.value == 0 and M.Count() == 0 and not f:Active(), "arrived, and the driver is idle")
  f:To(1, 1); M.Settle()
  assert(f.value == 1 and M.Count() == 0, "settling puts it where it was going")

  -- the preference: immediate states, nothing easing; changing it cancels what is easing
  ui.reduceSettingsMotion = true
  f:To(0, 0.1)
  assert(f.value == 0 and M.Count() == 0, "reduced: shown at once")
  ui.reduceSettingsMotion = false
  f:To(1, 1)
  assert(M.Count() == 1)
  local pref = S.variables.TWICHUI_reduceSettingsMotion
  assert(pref and pref:GetValue() == false, "the preference is on Home, off by default")
  pref:SetValue(true)
  assert(M.Count() == 0 and f.value == 1, "changing it settles what was easing")
  pref:SetValue(false)
  assert(ui.reduceSettingsMotion == false)

  -- the window: opens at once, fades in, arrives, closes immediately
  R:OpenSettings("overview")
  assert(win.shown and win.alpha == 0 and M.Count() >= 1, "opening starts a fade, the window is already there")
  UI.Navigate("chronicle")          -- during the window's own fade: no second fade on top
  M.Advance(1)
  assert(win.alpha == 1 and M.Count() == 0, "it arrived and the driver is idle")
  UI.Navigate("pins")
  assert(M.Count() == 1, "a new page's content eases in")
  UI.Navigate("chronicle"); UI.Navigate("gear"); UI.Navigate("chronicleLook")
  assert(M.Count() == 1, "rapid navigation: only the latest page is easing, nothing queued")
  assert(select(1, UI.Selected()) == "chronicleLook")
  M.Advance(1)
  assert(M.Count() == 0)
  UI.Navigate("pins")               -- left mid-arrival...
  UI.Close()                        -- ...and closed
  assert(not win.shown and M.Count() == 0 and win.alpha == 1, "closing is immediate and leaves nothing half-way")
  R:OpenSettings("pins")            -- reopened: shown, not found dim or stuck
  M.Advance(1)
  assert(win.shown and win.alpha == 1 and M.Count() == 0)

  -- reduced motion: no fade on opening or on a page
  UI.Close()
  ui.reduceSettingsMotion = true
  R:OpenSettings("overview")
  assert(win.alpha == 1 and M.Count() == 0, "opens at once")
  UI.Navigate("gear")
  assert(M.Count() == 0, "pages arrive at once")
  ui.reduceSettingsMotion = false
  UI.Close()
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
assert(hold[1] and hold[1].entry.row.id == "arrivalHold" and Search.Note(hold[1].entry) == nil, "a formerly advanced setting is an ordinary result")
assert(#Search.Run("show advanced options") == 0 or Search.Run("show advanced options")[1].entry.label ~= "Show advanced options", "the removed switch is not found")
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
-- 4c. EllesmereUI's color picker, when it is there: the same swatches open it instead of the game's, with the
-- same live preview, confirm and cancel; a stand-in that answers as EllesmereUIOptions' picker does (callbacks
-- take no arguments and read the frame; Cancel, click-away and the close box call cancelFunc, some of them
-- twice; OK fires swatchFunc and hides without cancelFunc; opening over an open one cancels it)
---------------------------------------------------------------------------
do
  local game = { shown = false }
  function game:IsShown() return self.shown end
  function game:GetColorRGB() return self.cur.r, self.cur.g, self.cur.b end
  function game:SetupColorPickerAndShow(info)
    self.info, self.shown, self.cur = info, true, { r = info.r, g = info.g, b = info.b }
    game.opened = (game.opened or 0) + 1
  end
  c.ColorPickerFrame = game

  local frame = Fake("Frame"); frame.shown = false
  local live, confirmed, shows, lastOpen = nil, false, 0, nil
  local cur = { r = 0, g = 0, b = 0 }
  function frame:GetColorRGB() return cur.r, cur.g, cur.b end
  frame.scripts.OnHide = function()
    if not confirmed and live and live.cancelFunc then live.cancelFunc() end
    confirmed = false
  end
  local eui = {}
  function eui:ShowColorPicker(info, anchor)
    if frame.shown and live and live.cancelFunc then live.cancelFunc() end
    live, lastOpen = info, { info = info, anchor = anchor }
    cur = { r = info.r, g = info.g, b = info.b }
    shows = shows + 1
    c.EllesmereUIColorPicker = frame   -- built by its first open
    frame.shown = true
  end
  local function Select(r, g, b) cur = { r = r, g = g, b = b }; if live.swatchFunc then live.swatchFunc() end end
  local function OK() live.swatchFunc(); confirmed = true; frame:Hide() end
  local function CancelBtn() confirmed = false; frame:Hide() end
  local function CloseBox() if live.cancelFunc then live.cancelFunc() end; frame:Hide() end

  local function Swatches()
    local list = {}
    local function Walk(f)
      for _, ch in ipairs(f.children) do
        if rawget(ch, "SetColorRGB") and ch:IsVisible() then list[#list + 1] = ch end
        Walk(ch)
      end
    end
    Walk(win)
    return list
  end
  local function Click(sw) sw.scripts.OnClick(sw) end

  UI.Navigate("chronicleLook")
  local list = Swatches()
  assert(#list >= 2, "the page has two swatches")
  local bg = S.variables.TWICHUI_chronicleLookBgColor
  local original = bg:GetValue()
  local writes = 0
  local plain = bg.SetValue
  bg.SetValue = function(self, v) writes = writes + 1; return plain(self, v) end

  -- EllesmereUI there but its options not loaded (no picker method yet): the game's picker, as before
  c.EllesmereUI = { PP = {} }
  Click(list[1])
  assert(game.shown and game.opened == 1 and shows == 0, "without ShowColorPicker the game's picker opens")
  game.info.cancelFunc(); game.shown = false
  assert(bg:GetValue() == original)

  -- and with it
  c.EllesmereUI = eui
  c.EllesmereUIColorPicker = frame
  writes = 0
  Click(list[1])
  assert(frame.shown and shows == 1 and game.opened == 1, "EllesmereUI's picker opens, not the game's")
  assert(lastOpen.anchor == list[1], "anchored on the swatch")
  local rgb = { R.SettingsWidgets.ParseHex(original) }
  assert(lastOpen.info.r == rgb[1] and lastOpen.info.g == rgb[2] and lastOpen.info.b == rgb[3],
    "it starts on the swatch's current color")
  assert(lastOpen.info.hasOpacity == false, "no opacity: these colors are opaque")
  assert(bg:GetValue() == original and writes == 0, "opening changes nothing")
  Select(0.2, 0.4, 0.6)
  assert(bg:GetValue() == "ff336699" and writes == 1, "the preview goes through the setting: " .. tostring(bg:GetValue()))
  Select(0.2, 0.4, 0.6)
  assert(writes == 1, "the same color twice is one write")
  OK()
  assert(not frame.shown and bg:GetValue() == "ff336699" and writes == 1, "OK keeps it, with no write of its own")
  bg:SetValue(original); writes = 0

  -- Cancel, however it is done, puts the color back once
  for name, how in pairs({ cancel = CancelBtn, close = CloseBox }) do
    Click(list[1]); Select(1, 0, 0)
    assert(bg:GetValue() == "ffff0000", name)
    how()
    assert(not frame.shown and bg:GetValue() == original, name .. " puts the old color back")
  end
  writes = 0
  Click(list[1])
  CancelBtn()
  assert(writes == 0, "cancelling what never changed writes nothing")

  -- a color given by the picker as exactly the starting one is not a change
  Click(list[1])
  Select(rgb[1], rgb[2], rgb[3])
  assert(writes == 0 and bg:GetValue() == original, "the starting color again changes nothing")
  CancelBtn(); bg:SetValue(original); writes = 0

  -- another swatch opened while one is open: the first is put back, the second is its own edit
  local other
  local before = {}
  for k, v in pairs(S.variables) do if k:find("^TWICHUI_chronicleLook.*Color$") then before[k] = v:GetValue() end end
  Click(list[1]); Select(0, 1, 0)
  assert(bg:GetValue() == "ff00ff00")
  Click(list[2])
  assert(bg:GetValue() == original, "the first swatch's color is back when another is opened")
  assert(frame.shown and lastOpen.anchor == list[2], "the picker is now the second swatch's")
  Select(0, 0, 1)
  local changed = {}
  for k, v in pairs(S.variables) do
    if before[k] and v:GetValue() ~= before[k] then changed[#changed + 1] = k end
  end
  assert(#changed == 1 and changed[1] ~= "TWICHUI_chronicleLookBgColor", "only the second swatch's setting changed")
  other = S.variables[changed[1]]
  CancelBtn()
  assert(other:GetValue() == before[changed[1]], "and Cancel puts that one back")

  -- the window closing, or another page shown, during an edit
  Click(list[1]); Select(1, 1, 0)
  win:Hide()
  assert(not frame.shown and bg:GetValue() == original, "closing the window puts the old color back and puts the picker away")
  UI.Open("chronicleLook")
  list = Swatches()
  Click(list[1]); Select(1, 1, 0)
  UI.Navigate("food")
  assert(not frame.shown and bg:GetValue() == original, "showing another page does the same")
  UI.Navigate("chronicleLook")
  list = Swatches()

  -- EllesmereUI installed but its picker not loaded yet: the first click has EllesmereUI load it (EnsureLoaded)
  -- and the picker opens a frame later, with the game's never involved
  do
    local loads = 0
    local lazy = {}
    function lazy:EnsureLoaded() loads = loads + 1; self.ShowColorPicker = eui.ShowColorPicker end
    c.EllesmereUI, c.EllesmereUIColorPicker = lazy, nil
    local s0, g0 = shows, game.opened or 0
    Click(list[1])
    assert(loads == 1 and shows == s0 and not frame.shown and not game.shown, "the first click loads EllesmereUI's picker, opening next frame")
    FlushTimers()
    assert(frame.shown and shows == s0 + 1 and (game.opened or 0) == g0 and lastOpen.anchor == list[1], "then it opens EllesmereUI's picker")
    Select(0.1, 0.2, 0.3)
    assert(bg:GetValue() == "ff1a334d")
    CancelBtn()
    assert(bg:GetValue() == original)
    Click(list[1])
    assert(loads == 1 and frame.shown and shows == s0 + 2, "loaded once, opened at once after")
    CancelBtn()

    -- given up before the frame passes: nothing opens
    lazy.ShowColorPicker, c.EllesmereUIColorPicker, loads = nil, nil, 0
    s0 = shows
    Click(list[1])
    R.SettingsWidgets.ColorPicker.Cancel()
    FlushTimers()
    assert(loads == 1 and shows == s0 and not frame.shown and bg:GetValue() == original, "an edit given up while it loads does not open")

    -- in combat it is not loaded: the game's picker, and loaded later out of combat
    lazy.ShowColorPicker, loads, g0 = nil, 0, game.opened or 0
    c.InCombatLockdown = function() return true end
    Click(list[1])
    assert(loads == 0 and game.shown and game.opened == g0 + 1, "in combat the game's picker opens and nothing is loaded")
    game.info.cancelFunc(); game.shown = false
    c.InCombatLockdown = function() return false end
    Click(list[1])
    FlushTimers()
    assert(loads == 1 and frame.shown, "out of combat it is loaded")
    CancelBtn()

    -- a load that leaves no picker: the game's, and not tried again
    lazy.ShowColorPicker, loads, g0 = nil, 0, game.opened or 0
    lazy.EnsureLoaded = function() loads = loads + 1 end
    Click(list[1])
    assert(loads == 1 and game.shown and game.opened == g0 + 1, "a load that gave no picker falls back to the game's")
    game.info.cancelFunc(); game.shown = false
    Click(list[1])
    assert(loads == 1 and game.opened == g0 + 2, "and is not tried again")
    game.info.cancelFunc(); game.shown = false
    assert(bg:GetValue() == original)
    c.EllesmereUI = eui
  end

  -- a picker that does not open (its frame stays down): the game's takes over, nothing half-applied
  local quiet = c.EllesmereUI
  c.EllesmereUI = { ShowColorPicker = function() end }
  game.opened = 0
  Click(list[1])
  assert(game.shown and game.opened == 1, "an EllesmereUI picker that did not show falls back to the game's")
  game.cur = { r = 0.5, g = 0.5, b = 0.5 }; game.info.swatchFunc()
  assert(bg:GetValue() == "ff808080", "the fallback picker previews through the setting")
  game.info.cancelFunc(); game.shown = false
  assert(bg:GetValue() == original, "and cancels")
  -- one that errors: reported, then the same fallback
  local faults = {}
  local realFault = R.Fault
  R.Fault = function(what, err) faults[#faults + 1] = what end
  c.EllesmereUI = { ShowColorPicker = function() error("boom") end }
  Click(list[1])
  assert(#faults == 1 and game.shown and game.opened == 2, "an erroring picker is reported and the game's opens")
  game.info.cancelFunc(); game.shown = false
  R.Fault = realFault
  c.EllesmereUI = quiet

  -- a profile change during an edit: the picker is put away, and nothing it holds can write into the new profile
  local function Pick()
    local sw = Swatches()[1]
    Click(sw)
    return sw
  end
  Pick()
  live = lastOpen.info
  local staleSwatch, staleCancel = live.swatchFunc, live.cancelFunc
  cur = { r = 1, g = 0, b = 1 }; staleSwatch()
  assert(bg:GetValue() == "ffff00ff")
  assert(R.Profiles.Create("PickerTest"))
  assert(not frame.shown, "a profile change puts the picker away")
  local inNew = bg:GetValue()
  staleSwatch(); staleCancel()
  assert(bg:GetValue() == inNew, "a callback from the old edit writes nothing into the new profile")
  assert(R.Profiles.Switch("Default"))
  bg:SetValue(original)
  assert(R.Profiles.Delete("PickerTest"))

  bg.SetValue = plain
  c.EllesmereUI, c.EllesmereUIColorPicker, c.ColorPickerFrame = nil, nil, nil
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
assert(PressEsc() and not c.ColorPickerFrame:IsShown() and win.shown, "with the color picker open, Esc closes the picker only")
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
