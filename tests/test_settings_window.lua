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
    -- the notification cards' animation (previews are shown from the appearance page)
    CreateAnimationGroup = function()
      local g = setmetatable({}, { __index = function() return function() end end })
      function g:Play() self.playing = true end
      function g:Stop() self.playing = false end
      function g:CreateAnimation() return setmetatable({}, { __index = function() return function() end end }) end
      return g
    end,
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
  assert(children == 17, "seventeen secondary pages: " .. children)
  assert(#K.Tabs("overview") == 0 and #K.Tabs("auction") == 0, "a feature without pages under it has no tabs")
  do   -- Quality of life: its own options, then the two kinds of marker cycling, each a tab of its own
    local labels = {}
    for _, t in ipairs(K.Tabs("qol")) do labels[#labels + 1] = K.TabLabel(t) end
    assert(table.concat(labels, "|") == "General|Target markers|World markers|Marker bar", "Quality of life's tabs: " .. table.concat(labels, "|"))
  end
  assert(#K.Tabs("notifications") == 2 and K.Tabs("notifications")[2].key == "notificationsLook", "Notifications has its appearance tab")
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
-- 1b2. Troubleshooting status: drawn with its values, optional addons folded while absent, a snapshot taken
-- when the page opens and dropped when the settings close, Refresh and the support window's button
---------------------------------------------------------------------------
do
  local function Visible(frame, text)
    if frame.text == text and frame.IsVisible and frame:IsVisible() then return true end
    for _, child in ipairs(frame.children or {}) do
      if Visible(child, text) then return true end
    end
    return false
  end
  local St = R.DiagStatus
  R:OpenSettings("troubleshooting")
  for _, label in ipairs({ "TwichUI version", "Release channel", "Game client", "Core", "Settings window", "Reload needed",
    "Status snapshot", "Support information", "Optional integrations", "Skin for Attune", "Data bar library (LibDataBroker)", "Full report" }) do
    assert(Visible(win, label), label .. " is drawn on the Troubleshooting page")
  end
  assert(Visible(win, "1.60.1 (build 70009)") and Visible(win, "Loaded this session") and Visible(win, "Started"), "the values are drawn")
  assert(Visible(win, "EllesmereUI") and Visible(win, "RestedXP") and not Visible(win, "EllesmereUI: Color picker"),
    "EllesmereUI is not installed here: one line, not five")
  assert(not Visible(win, "Healthy") and not Visible(win, "Safe"), "no verdict is drawn")
  -- the snapshot is taken when the page opens, and the next page's navigation leaves it alone
  local snap = St.Current()
  UI.Navigate("troubleshooting")
  assert(St.Current() ~= snap, "going to the page takes a new snapshot")
  snap = St.Current()
  UI.Refresh()
  assert(St.Current() == snap, "redrawing the page does not take another")
  K.rowsById["troubleshooting:status-snapshot"].click()
  assert(St.Current() ~= snap, "Refresh takes a new one")
  -- Support information closes the settings and opens the copy window
  local asked = 0
  local show = R.SupportWindow.Show
  R.SupportWindow.Show = function() asked = asked + 1 return true end
  K.rowsById["troubleshooting:support-information"].click()
  assert(asked == 1 and not UI.IsShown(), "it closes the settings and opens the support window")
  R.SupportWindow.Show = show
  -- closing dropped the snapshot; opening again takes one
  snap = St.Current()
  R.SettingsLauncher.Closed()
  assert(St.Current() ~= snap, "closing the settings drops the snapshot")
  local frames = made
  for _ = 1, 3 do R:OpenSettings("troubleshooting"); UI.Close() end
  assert(made == frames, "opening and closing the page makes nothing new")
  R:OpenSettings("overview")
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
-- Matching each word in the summary or the tooltip separately (instead of joining the two for every entry at
-- every keystroke) ranks exactly as joining them did: the same results, scores and order as the old way, for
-- whole and partial words, many matches, no match, and words split between a setting's name and its tooltip.
do
  local function OldRun(query)
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return {} end
    local words = {}
    for w in query:lower():gmatch("%S+") do words[#words + 1] = w end
    local function AllIn(text) for _, w in ipairs(words) do if not text:find(w, 1, true) then return false end end return true end
    local low = query:lower()
    local out = {}
    for _, e in ipairs(Search.Build()) do
      local score
      if e.labelLow == low then score = 120
      elseif e.labelLow:sub(1, #low) == low then score = 100
      elseif AllIn(e.labelLow) then
        score = 80
        if e.labelLow:find("%f[%w]" .. words[1]:gsub("%p", "%%%0")) then score = 85 end
      elseif AllIn(e.hay) then score = 50
      elseif e.tip and AllIn(e.hay .. " " .. e.tip) then score = 10 end
      if score then
        if e.kind == "page" then score = score + 5 elseif e.kind == "section" then score = score + 2 end
        out[#out + 1] = { entry = e, score = score }
      end
    end
    table.sort(out, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.entry.order < b.entry.order end)
    for i = #out, Search.LIMIT + 1, -1 do out[i] = nil end
    return out
  end
  -- one word only in a setting's name, another only in its tooltip
  local split
  for _, e in ipairs(Search.Build()) do
    local a, b = e.labelLow:match("%a%a%a%a+"), e.tip and e.tip:match("%a%a%a%a%a+")
    if a and b and not e.hay:find(b, 1, true) then split = a .. " " .. b break end
  end
  assert(split, "an entry with a word only in its tooltip")
  local tipOnly = false
  for _, q in ipairs({ "minimap", "pins", "p", "a", "so", "sound", "notification sound", "zone card", "card zone",
      "reset", "chronicle", "xyzzy", split }) do
    local new, old = Search.Run(q), OldRun(q)
    assert(#new == #old, q .. ": " .. #new .. " results, the old way " .. #old)
    for i = 1, #new do
      assert(new[i].entry == old[i].entry and new[i].score == old[i].score, q .. ": result " .. i .. " differs")
      if new[i].tipOnly then tipOnly = true end
    end
  end
  assert(tipOnly, "the comparison covered a match found only in a tooltip")
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
-- 4b2. Notification appearance (TwichUI_Settings/pages/Notifications.lua, modules/NotifyLook.lua): the page edits
-- the shared look or one card; a card that follows the shared look is greyed out and says so; a color edit that is
-- cancelled puts the card's look back; a preview card stays up while it is edited
---------------------------------------------------------------------------
do
  local NL, N = R.NotifyLook, R.Notify
  local K = S.K
  local scope, own = S.variables.TWICHUI_notifyLookScope, S.variables.TWICHUI_notifyLookOwn
  local title = S.variables.TWICHUI_notifyLookTitleColor
  UI.Navigate("notificationsLook")
  assert(UI.Selected() == "notificationsLook", "the page is a tab of Notifications")
  assert(K.pages.notificationsLook.parent == "notifications", "under Notifications")
  assert(NL.Scope() == "shared" and K.rowsById.notifyLookTitleColor:Enabled(), "the shared look is edited at first")
  assert(not K.rowsById.notifyLookOwn:Shown(), "the shared look has no 'own look' switch")
  assert(K.rowsById.notifyLookBodyColor:Shown(), "and every color")

  scope:SetValue("arrival")
  local row = K.rowsById.notifyLookTitleColor
  assert(NL.Scope() == "arrival" and K.rowsById.notifyLookOwn:Shown(), "a card has the switch")
  assert(not row:Enabled() and row:DisabledReason():find("follows the shared look", 1, true), "its settings are greyed out and say why")
  assert(not K.rowsById.notifyLookBodyColor:Shown(), "the zone card has no main text, so no color for it")
  local before = title:GetValue()
  title:SetValue("ff102030")
  assert(title:GetValue() == before and c.TwichUIDB.ui.notifyLookArrival == nil, "a value for a card that follows the shared look is refused, and nothing is saved")
  assert(c.TwichUIDB.ui.notifyLook == nil, "choosing a card changed nothing")

  own:SetValue(true)
  assert(NL.Own("arrival") and row:Enabled(), "with its own look the settings are open")
  assert(K.rowsById.notifyLookPadding:Enabled() == false and K.rowsById.notifyLookPadding:DisabledReason():find("opacity", 1, true),
    "padding waits for a backdrop")
  S.variables.TWICHUI_notifyLookBgOpacity:SetValue(30)
  assert(K.rowsById.notifyLookPadding:Enabled(), "and opens once there is one")
  S.variables.TWICHUI_notifyLookBgOpacity:SetValue(0)
  assert(NL.Get("arrival", "bgOpacity") == 0, "zero stays zero")

  -- the Show button puts the real card up, and a color edit is live on it, and Cancel puts it back
  local picker = { shown = false }
  function picker:IsShown() return self.shown end
  function picker:GetColorRGB() return self.cur.r, self.cur.g, self.cur.b end
  function picker:SetupColorPickerAndShow(info)
    self.info, self.shown = info, true
    self.cur = { r = info.r, g = info.g, b = info.b }
    if info.swatchFunc then info.swatchFunc() end
  end
  c.ColorPickerFrame = picker
  local show = FindButton(win, "Show")
  assert(show, "a Show button for each card")
  show.scripts.OnClick(show)
  assert(NL.Pinned("arrival") and N.State().active[1] == "arrival:preview", "the zone card is up as a preview")
  assert(FindButton(win, "Hide"), "its button now says Hide")
  local swatch
  local function Walk(frame)
    for _, ch in ipairs(frame.children) do
      if rawget(ch, "SetColorRGB") and ch:IsVisible() and not swatch then swatch = ch end
      Walk(ch)
    end
  end
  Walk(win)
  assert(swatch, "the title color swatch")
  local original = NL.Get("arrival", "titleColor")
  swatch.scripts.OnClick(swatch)
  picker.cur = { r = 0.2, g = 0.4, b = 0.6 }
  picker.info.swatchFunc()
  assert(NL.Get("arrival", "titleColor") == "ff336699", "the wheel edits the card's own look live")
  assert(NL.Get("training", "titleColor") == original, "and no other card's")
  picker.info.cancelFunc()
  assert(NL.Get("arrival", "titleColor") == original, "Cancel puts the card's look back")
  assert(NL.Pinned("arrival"), "the preview is still up")
  picker.shown = false
  c.ColorPickerFrame = nil

  -- the resets say what they cover, and do only that
  NL.Set("arrival", "textScale", 120)
  S.variables.TWICHUI_notifyLookScope:SetValue("shared")
  NL.Set("shared", "textScale", 90)
  scope:SetValue("arrival")
  local resets = {}
  local function Collect(frame)
    for _, ch in ipairs(frame.children) do
      if ch.text and type(ch.text) == "table" and ch.text.text == "Reset" and ch.scripts.OnClick and ch:IsVisible() then resets[#resets + 1] = ch end
      Collect(ch)
    end
  end
  Collect(win)
  assert(#resets >= 2, "a reset for the shared look and one for the card")
  asked = nil
  resets[2].scripts.OnClick(resets[2])
  assert(asked and asked.text:find("Zone arrival card", 1, true) and asked.text:find("shared look", 1, true), "it names the card and what is left alone")
  assert(NL.Own("arrival"), "nothing happens before it is accepted")
  asked.dlg.OnAccept()
  assert(not NL.Own("arrival") and c.TwichUIDB.ui.notifyLookArrival == nil, "the card follows the shared look again, its own forgotten")
  assert(NL.Get("arrival", "textScale") == 90 and c.TwichUIDB.ui.notifyLook.textScale == 90, "the shared look was not touched")
  assert(c.TwichUIDB.modules.arrival == true, "whether the card is on is not touched")
  scope:SetValue("shared")
  asked = nil
  resets = {}
  Collect(win)
  resets[1].scripts.OnClick(resets[1])
  assert(asked and asked.text:find("Cards with a look of their own keep it", 1, true), "the shared reset says what it leaves")
  asked.dlg.OnAccept()
  assert(c.TwichUIDB.ui.notifyLook == nil, "the shared look is back to the defaults")
  NL.ClearPreviews()
  assert(not NL.Pinned("arrival"), "Hide all previews puts them away")
  UI.Navigate("overview")
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
-- 6b. The finishing pass: Home's wording and height, the scroll bar only where there is something to scroll,
-- Notifications' one introduction, and the tabs
---------------------------------------------------------------------------
do
  local function Find(frame, pred)
    if pred(frame) then return frame end
    for _, ch in ipairs(frame.children or {}) do
      local found = Find(ch, pred)
      if found then return found end
    end
  end
  local function Texts(frame, out)
    out = out or {}
    if frame.shown == false then return out end   -- a page or row not drawn now
    if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
    if type(frame.text) == "table" and type(frame.text.text) == "string" then out[#out + 1] = frame.text.text end
    for _, ch in ipairs(frame.children or {}) do Texts(ch, out) end
    return out
  end
  local function Has(frame, text)
    for _, t in ipairs(Texts(frame)) do if t == text then return true end end
    return false
  end
  local viewport = 660 - (54 + 10) - (38 + 8)   -- the window's height less its header and footer (Window.lua)
  local scroll = Find(win, function(f) return f.kind == "ScrollFrame" and f.scrollBarHideable ~= nil end)
  assert(scroll and scroll.scrollBarHideable, "the content's scroll bar hides while nothing overflows")

  UI.Navigate("overview")
  assert(Has(win, "Show welcome") and Has(win, "View commands"), "Home's buttons say what they do")
  assert(not Has(win, "Show") and not Has(win, "List"), "and the bare words are gone")
  local homeHeight = scroll.child.h
  assert(homeHeight > 0 and homeHeight < viewport, "Home fits the window with room to spare: " .. homeHeight)
  local blurb = false
  for _, t in ipairs(Texts(win)) do
    if t:find("Reset this page's settings to their defaults", 1, true) then blurb = true end
    assert(not t:find("Restore defaults:", 1, true), "the long scope sentence is not drawn")
  end
  assert(blurb, "Reset says what it covers in one line")

  UI.Navigate("notifications")
  assert(scroll.child.h > viewport, "a dense page still scrolls: " .. scroll.child.h)
  assert(Has(win, "Accessibility") and Has(win, "Reduced motion"), "Notifications has an Accessibility section")
  for _, t in ipairs(Texts(win)) do
    assert(not t:find("Small, quiet cards near the edges of the screen", 1, true), "the introduction is not said twice")
  end
  -- its tabs: the shown one is not a link; the other goes to its page
  local tabs = {}
  Find(win, function(f)
    if f.kind == "Button" and type(f.text) == "table" and (f.text.text == "General" or f.text.text == "Appearance") and f.bar and f:IsVisible() then
      tabs[f.text.text] = f
    end
  end)
  assert(tabs.General and tabs.Appearance, "both tabs are drawn")
  assert(tabs.General.scripts.OnClick == nil and tabs.General.bar.shown, "the shown tab is marked and does nothing")
  assert(tabs.Appearance.scripts.OnClick and not tabs.Appearance.bar.shown, "the other is a way to its page")
  tabs.Appearance.scripts.OnClick(tabs.Appearance)
  assert(select(1, UI.Selected()) == "notificationsLook", "choosing a tab goes to its page")
  UI.Navigate("overview")
end

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
---------------------------------------------------------------------------
-- 5. Feedback: what waits for a reload, why a control is unavailable, what a reset or an integration means
---------------------------------------------------------------------------
do
  local function Shown(frame, fragment)
    if type(frame.text) == "string" and frame.text:find(fragment, 1, true) and frame:IsVisible() then return true end
    for _, child in ipairs(frame.children or {}) do
      if Shown(child, fragment) then return true end
    end
    return false
  end
  local W = R.Switches
  local popupsBefore = S.popups

  -- 5a. Reload: one record (Switches.lua), shown next to the control and in the footer, cleared when reverted
  UI.Close(); R:OpenSettings("overview")
  assert(not W.ReloadPending() and not Shown(win, "Reload your UI to apply"), "nothing waits to begin with")
  local media0, quiet0 = R:Enabled("media"), R:Enabled("quietLogin")
  R:SetEnabled("media", not media0)
  assert(W.IsPending("media") and W.ReloadPending(), "a changed switch that needs a reload is pending")
  assert(Shown(win, "Reload your UI to apply this change."), "the control says so beside it")
  assert(Shown(win, "Reload your UI to apply: Custom fonts and sounds."), "the footer names it")
  assert(not Shown(win, "and 1 more"), "one thing waits")
  R:SetEnabled("quietLogin", not quiet0)
  assert(Shown(win, "Reload your UI to apply: Custom fonts and sounds and 1 more."), "the footer counts the rest")
  assert(S.popups == popupsBefore, "with the window open it is a notice, not a question, and never an automatic reload")
  R:SetEnabled("media", media0)
  assert(not W.IsPending("media") and W.IsPending("quietLogin"), "turned back before a reload, it no longer waits")
  assert(Shown(win, "Reload your UI to apply: Hide addon welcome messages."), "the footer follows")
  R:SetEnabled("quietLogin", quiet0)
  assert(not W.ReloadPending() and not Shown(win, "Reload your UI to apply"), "nothing waits again, anywhere")

  -- a profile change moves what waits: a profile whose value is what loaded clears it, and coming back restores it
  do
    local P = R.Profiles
    local home = P.Current()
    R:SetEnabled("quietLogin", not quiet0)
    assert(W.IsPending("quietLogin") and Shown(win, "Reload your UI to apply: Hide addon welcome messages."), "set up: pending in this profile")
    local made = P.Create("Plain")   -- the default settings, which are what this session loaded with
    assert(made, "set up: a profile of defaults")
    assert(R:Enabled("quietLogin") == R.DEFAULT_MODULES.quietLogin)
    assert(W.IsPending("quietLogin") == (R.DEFAULT_MODULES.quietLogin ~= quiet0), "switching profiles re-reads it")
    P.Switch(home)
    assert(W.IsPending("quietLogin") and Shown(win, "Reload your UI to apply: Hide addon welcome messages."), "and back again it waits again")
    R:SetEnabled("quietLogin", quiet0)
    assert(not W.ReloadPending(), "reverted in the profile, nothing waits")
    P.Delete("Plain")
  end

  -- clicking is not enough: a switch set to the value the UI loaded with is never pending
  R:SetEnabled("media", media0)
  assert(not W.IsPending("media"), "setting what is already so waits for nothing")

  -- 5b. A page reset names what it turns on or off, and the reload it needs; it clears what it undoes
  local function Ask(button)
    asked = nil
    button.scripts.OnClick(button)
    return asked
  end
  UI.Navigate("overview")
  R:SetEnabled("media", not R.DEFAULT_MODULES.media)
  local resetPage = FindButton(win, "Reset this page")
  assert(resetPage, "Home has a reset")
  local q = Ask(resetPage)
  assert(q and q.text:find("of the", 1, true) and q.text:find("settings shown here differ", 1, true), "it counts what differs")
  assert(q.text:find("Custom fonts and sounds", 1, true), "it names the switch that changes")
  assert(q.text:find(R.DEFAULT_MODULES.media and "Turns on:" or "Turns off:", 1, true), "and which way")
  assert(not q.text:find("reload your UI", 1, true), "putting back a change not yet reloaded for needs no reload: it clears")
  -- when the session loaded with something else, the default is the change that needs one
  W.atLoad.media = not R.DEFAULT_MODULES.media
  q = Ask(resetPage)
  assert(q.text:find("Takes effect after you reload your UI: \"Custom fonts and sounds\". Nothing reloads by itself.", 1, true), q.text)
  W.atLoad.media = media0
  q = Ask(resetPage)
  q.dlg.OnAccept()
  assert(R:Enabled("media") == R.DEFAULT_MODULES.media, "the switch is back to its default")
  assert(W.IsPending("media") == (R.DEFAULT_MODULES.media ~= media0), "pending follows what the session loaded with")
  R:SetEnabled("media", media0)
  assert(not W.ReloadPending(), "back to what loaded: nothing waits")
  -- when nothing differs, nothing is asked
  local allDefault = FindButton(win, "Reset this page")
  q = Ask(allDefault)
  if q then q.dlg.OnAccept(); q = Ask(allDefault) end
  assert(q == nil, "a page already at its defaults asks nothing and changes nothing")

  -- 5c. A section reset asks first and says what it covers and what differs
  UI.Navigate("food")
  R.FoodDrink.Set("size", 50)
  local sectionReset
  for _, row in ipairs(K.pages.food.rows) do
    if row.kind == "button" and row.data.name == "Appearance" then sectionReset = row end
  end
  assert(sectionReset and sectionReset.reset and sectionReset.data.buttonText == "Reset", "Food and drink's appearance reset")
  asked = nil
  sectionReset.click()
  assert(asked and asked.key == "TWICHUI_SETTINGS_RESET_SECTION", "it asks")
  assert(asked.text:find("The place is kept", 1, true), "with the feature's own sentence about what is kept")
  assert(asked.text:find("1 of the", 1, true), "and how many shown here differ: " .. asked.text)
  assert(R.FoodDrink.Get("size") == 50, "nothing happens before it is accepted")
  asked.dlg.OnAccept()
  assert(R.FoodDrink.Get("size") == R.FoodDrink.DEFAULTS.size, "accepted, it resets")

  -- 5d. Combat: profile changes are greyed out with the reason, and follow combat starting and ending
  UI.Navigate("profiles")
  local newProfile = K.rowsById["profiles:new-profile"]
  assert(newProfile and newProfile:Enabled() and not Shown(win, "Profile changes wait until combat ends."), "available out of combat")
  c.InCombatLockdown = function() return true end
  c.FireEvent("PLAYER_REGEN_DISABLED")
  assert(not newProfile:Enabled() and newProfile:DisabledReason() == "Profile changes wait until combat ends.", "greyed out in combat")
  assert(Shown(win, "Profile changes wait until combat ends."), "and the reason is on the page")
  c.InCombatLockdown = function() return false end
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(newProfile:Enabled() and not Shown(win, "Profile changes wait until combat ends."), "available again when combat ends")

  -- 5e. Integrations: a missing optional addon is a note, not an error, and never changes the chosen mode
  local MSL = R.MageSell
  R:SetEnabled("mageSell", true)
  MSL.Acknowledge(); MSL.SetMode("ellesmere")
  local mode = K.rowsById.mageSellMode
  local text, tone = mode.note()
  assert(tone == "warn" and text:find("Nothing is marked and nothing is sold by TwichUI", 1, true),
    "with EllesmereUI unusable the row says so: " .. tostring(text))
  assert(MSL.Mode() == "ellesmere", "the chosen mode is kept, not switched to selling")
  MSL.SetMode("direct")
  assert(mode.note() == nil, "no note when the mode doesn't need it")
  R:SetEnabled("mageSell", false)

  R:SetEnabled("mageTravel", true)
  c.LibStub = { GetLibrary = function() return nil end }
  local travel = K.rowsById.mageTravel
  assert(travel.note():find("nowhere to appear", 1, true), "no data bar library: said under the launcher")
  c.LibStub = { GetLibrary = function() return {} end }
  assert(travel.note() == nil, "with one, nothing is said")
  R:SetEnabled("mageTravel", false)
  c.LibStub = { GetLibrary = function() return nil end }
  assert(travel.note() == nil, "and nothing is said about a launcher that is off")

  local skin = K.rowsById.attuneSkin
  local before = R:Enabled("attuneSkin")
  R:SetEnabled("attuneSkin", true)
  local skinText, skinTone = skin.note()
  assert(skinTone == "warn" and skinText:find("EllesmereUI", 1, true), "a skin that is on without EllesmereUI says what is missing")
  R:SetEnabled("attuneSkin", before)

  UI.Close()
  assert(not W.ReloadPending(), "feedback tests leave nothing pending")
end

print("PASSED")
