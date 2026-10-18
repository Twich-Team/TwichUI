-- RestedXP guide data source (modules/RestedXPBroker.lua): made once, only with RestedXP and LibDataBroker;
-- its text follows the guide; a click opens a menu (show guide = RestedXP's own ToggleActive, lock windows =
-- profile.lockFrames, import = guideImporter:Open(), greyed out in combat; nothing else of RestedXP's is
-- touched); a toggle or profile change made elsewhere is followed; hooks go in once; an unknown RestedXP
-- shape makes nothing.
-- RestedXP is simulated from the source of v4.11.22 (SettingsPanel.lua: settings.ToggleActive flips
-- settings.profile.showEnabled; settings:RefreshProfile swaps settings.profile), not the game.
dofile(TESTS .. "harness.lua")

local function Boot(opts)
  opts = opts or {}
  local c = MakeClient("Rich", { "!!!TwichUI", "RXPGuides" })
  c.hookCount = 0
  c.hooksecurefunc = function(tbl, name, fn)
    local orig = assert(tbl[name], "hooking something that is not there: " .. tostring(name))
    c.hookCount = c.hookCount + 1
    tbl[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end
  c.tipHidden = 0
  c.GameTooltip = { Hide = function() c.tipHidden = c.tipHidden + 1 end }
  c.TwichUIDB = { modules = {} }
  c.inCombat = false
  c.InCombatLockdown = function() return c.inCombat end
  c.made = {}
  -- Frames that record what the menu does to them.
  c.frames = {}
  local Methods
  local function Fake(kind)
    local o = { kind = kind, shown = false, scripts = {}, enabled = true }
    table.insert(c.frames, o)
    return setmetatable(o, { __index = function(_, k)
      if Methods[k] then return Methods[k] end
      if type(k) == "string" and k:find("^%u") then return function() end end
    end })
  end
  Methods = {
    Show = function(s) s.shown = true end,
    Hide = function(s) if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(s) end end end,
    IsShown = function(s) return s.shown end,
    SetShown = function(s, v) s.shown = v and true or false end,
    SetScript = function(s, n, fn) s.scripts[n] = fn end,
    CreateTexture = function() return Fake("texture") end,
    CreateFontString = function() return Fake("font") end,
    SetText = function(s, v) s.text = v end,
    SetEnabled = function(s, v) s.enabled = v end,
    IsMouseOver = function(s) return s.mouse == true end,
    SetPoint = function(s, ...) s.point = { ... } end,
    SetHeight = function(s, v) s.height = v end,
  }
  c.CreateFrame = function(kind, name, parent, template)
    local f = Fake(kind); f.name, f.parent, f.template = name, parent, template; return f
  end
  c.UIParent = Fake("UIParent")
  c.UISpecialFrames = {}
  c.tinsert = table.insert
  c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  if not opts.noRXP then
    local rxp = { settings = { profile = { showEnabled = true } }, toggles = 0 }
    function rxp.settings.ToggleActive()
      rxp.toggles = rxp.toggles + 1
      rxp.settings.profile.showEnabled = not rxp.settings.profile.showEnabled
    end
    function rxp.settings:RefreshProfile() self.profile = rxp.nextProfile end
    function rxp.GetGuideName(guide) return guide.displayname end
    rxp.guideImporter = { opens = 0, Open = function(self) self.opens = self.opens + 1 end }
    if opts.broken then rxp.settings.ToggleActive = nil end
    local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
    function ace:GetAddon(name) if name == "RXPGuides" then return rxp end end
    c.rxp = rxp
  end
  if not opts.lateLDB then
    local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
    function LDB:NewDataObject(name, o) if name == "TwichUI RestedXP Guide" then c.made[#c.made + 1] = name; c.obj = o end return o end
  end
  for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
    "modules/RestedXPBrokerMenu.lua", "modules/RestedXPBroker.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  FlushTimers()
  return c
end

local function Tip(obj)
  local lines = {}
  local tip = {
    AddLine = function(_, s) lines[#lines + 1] = s end,
    AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. ": " .. b end,
  }
  obj.OnTooltipShow(tip)
  return table.concat(lines, "\n")
end

-- Without RestedXP: loads, makes nothing.
do
  local c = Boot({ noRXP = true })
  assert(c.TwichUI.RestedXPBroker and not c.TwichUI.RestedXPBroker.Available() and #c.made == 0, "nothing without RestedXP")
  assert(c.TwichUI.RestedXPBroker.GuideOn() == nil, "no state without RestedXP")
end

-- A RestedXP this wasn't written for: nothing made, nothing hooked.
do
  local c = Boot({ broken = true })
  assert(#c.made == 0 and c.hookCount == 0, "unknown RestedXP shape: nothing made or hooked")
end

-- RestedXP and a data bar: made once, text follows, a click is RestedXP's own toggle.
do
  local c = Boot()
  local B = c.TwichUI.RestedXPBroker
  assert(#c.made == 1 and c.made[1] == "TwichUI RestedXP Guide" and B.Available(), "made once at login")
  local obj = c.obj
  assert(obj.type == "data source" and obj.label == "RestedXP" and obj.text == "Guide on", "starts on: " .. tostring(obj.text))
  assert(c.hookCount == 2, "ToggleActive and RefreshProfile hooked once each: " .. c.hookCount)

  local tip = Tip(obj)
  assert(tip:find("Guide: On", 1, true) and tip:find("Click for options", 1, true), tip)
  assert(tip:find("Windows: Unlocked", 1, true), tip)
  assert(not tip:find("Current", 1, true), "no guide loaded, no name: " .. tip)

  -- What the open menu shows: the rows' labels and notes, whether each switch is filled, and which can be clicked.
  local function Open(button)
    obj.OnClick(obj, button)
    local menu
    for _, f in ipairs(c.frames) do if f.name == "TwichUIRestedXPMenu" then menu = f end end
    assert(menu and menu.shown, "a click opens the menu")
    local rows = {}
    for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu then rows[#rows + 1] = f end end
    assert(#rows == 3, "three rows: " .. #rows)
    local function Click(row) if row.enabled then row.scripts.OnClick(row) end end
    return menu, rows, Click
  end

  local bus = c.TwichUI.frame
  assert(not bus.events.GLOBAL_MOUSE_DOWN and not bus.events.PLAYER_REGEN_DISABLED, "listens to nothing while closed")
  local menu, rows, Click = Open("LeftButton")
  assert(bus.events.GLOBAL_MOUSE_DOWN and bus.events.PLAYER_REGEN_DISABLED, "listens while open")
  local guide, lock, import = rows[1], rows[2], rows[3]
  assert(menu.template == "BackdropTemplate", "a backdrop frame, as the Mage menus are")
  assert(c.rxp.toggles == 0, "opening the menu changes nothing")
  assert(c.tipHidden == 1, "the tooltip is hidden so it does not sit over the menu")
  assert(guide.name.text == "Show guide" and guide.note.text == "On" and guide.fill.shown == true, "Show guide: on, said in words")
  assert(lock.name.text == "Lock windows" and lock.note.text == "Unlocked" and lock.fill.shown == false, "Lock windows: unlocked")
  assert(import.name.text == "Import guides..." and import.enabled and import.note.text == "", "import is available out of combat")
  assert(c.UISpecialFrames[1] == "TwichUIRestedXPMenu", "Esc closes it")

  Click(guide)
  assert(c.rxp.toggles == 1 and c.rxp.settings.profile.showEnabled == false and obj.text == "Guide off", "Show guide turns it off")
  assert(menu.shown and guide.note.text == "Off" and guide.fill.shown == false, "the menu stays open and shows the new state")
  Click(guide)
  assert(c.rxp.toggles == 2 and obj.text == "Guide on" and guide.note.text == "On", "and back on")

  Click(lock)
  assert(c.rxp.settings.profile.lockFrames == true and lock.note.text == "Locked" and lock.fill.shown == true, "Lock windows locks")
  assert(Tip(obj):find("Windows: Locked", 1, true), "tooltip says so")
  Click(lock)
  assert(c.rxp.settings.profile.lockFrames == false and lock.note.text == "Unlocked" and c.rxp.toggles == 2, "unlocks, without touching the guide")

  -- A toggle made in RestedXP itself while the menu is open: the rows follow.
  c.rxp.settings.ToggleActive()
  assert(guide.note.text == "Off", "follows RestedXP's own toggle")
  c.rxp.settings.ToggleActive()

  -- A second click on the data bar entry closes it; so does a click elsewhere.
  obj.OnClick(obj, "LeftButton")
  assert(not menu.shown, "a second click closes it")
  assert(not bus.events.GLOBAL_MOUSE_DOWN and not bus.events.PLAYER_REGEN_DISABLED, "and it stops listening")
  obj.OnClick(obj, "LeftButton")
  assert(menu.shown)
  c.FireEvent("GLOBAL_MOUSE_DOWN")
  assert(not menu.shown, "a click elsewhere closes it")
  obj.OnClick(obj, "RightButton")
  assert(menu.shown, "any button opens it")

  Click(import)
  assert(c.rxp.guideImporter.opens == 1 and not menu.shown, "Import opens RestedXP's import window and closes the menu")

  -- Combat: Import is greyed out and says why; the switches stay.
  obj.OnClick(obj, "LeftButton")
  c.inCombat = true
  c.FireEvent("PLAYER_REGEN_DISABLED")
  assert(not import.enabled and import.note.text == "In combat", "import is greyed out in combat")
  Click(import)
  assert(c.rxp.guideImporter.opens == 1, "and does nothing in combat")
  assert(guide.enabled and lock.enabled, "the rest stay available")
  c.inCombat = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(import.enabled and import.note.text == "", "back out of combat")
  menu:Hide()

  -- RestedXP's own minimap button or /rxp toggle: the text follows.
  c.rxp.settings.ToggleActive()
  assert(obj.text == "Guide off", "follows a toggle made in RestedXP")

  -- A RestedXP profile change: the text follows.
  c.rxp.nextProfile = { showEnabled = true, hideGuideWindow = true }
  c.rxp.settings:RefreshProfile()
  assert(obj.text == "Guide on", "follows a RestedXP profile change")

  c.rxp.currentGuide = { displayname = "1-6 Elwynn Forest" }
  tip = Tip(obj)
  assert(tip:find("Current: 1-6 Elwynn Forest", 1, true), tip)
  assert(tip:find("guide window is hidden in RestedXP's options", 1, true), "says when the window itself is hidden: " .. tip)

  -- Later ADDON_LOADED events: nothing made or hooked again.
  c.FireEvent("ADDON_LOADED", "SomeAddon")
  assert(#c.made == 1 and c.hookCount == 2, "made and hooked once")
end

-- A data bar addon that brings LibDataBroker after login.
do
  local c = Boot({ lateLDB = true })
  assert(#c.made == 0, "no LibDataBroker yet")
  local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function LDB:NewDataObject(name, o) if name == "TwichUI RestedXP Guide" then c.made[#c.made + 1] = name; c.obj = o end return o end
  c.FireEvent("ADDON_LOADED", "SomeDataBar")
  assert(#c.made == 1 and c.obj.text == "Guide on", "made once a data bar brings LibDataBroker")
end

-- A row from another addon (the Guide Rebinder): added once, below the built-in rows, closes the menu.
do
  local c = Boot()
  local M = c.TwichUI.RestedXPBrokerMenu
  local opened = 0
  assert(not M.AddRow(nil) and not M.AddRow({ key = "x", label = "X" }) and not M.AddRow({ key = "", label = "X", act = function() end }),
    "an invalid spec is refused")
  assert(not M.AddRow({ key = "guide", label = "Dup", act = function() end }), "a built-in key is refused")
  assert(M.AddRow({ key = "Rebinder", label = "Guide rebinder...", act = function() opened = opened + 1 end }), "added before the menu is built")
  assert(not M.AddRow({ key = "Rebinder", label = "Again", act = function() end }), "a second add with the same key is ignored")
  c.obj.OnClick(c.obj, "LeftButton")
  local menu
  for _, f in ipairs(c.frames) do if f.name == "TwichUIRestedXPMenu" then menu = f end end
  local rows = {}
  for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu then rows[#rows + 1] = f end end
  assert(#rows == 4 and rows[4].name.text == "Guide rebinder..." and rows[4].enabled, "a fourth, enabled row")
  rows[4].scripts.OnClick(rows[4])
  assert(opened == 1 and not menu.shown, "its action runs and the menu closes")
  -- Added while the menu already exists.
  assert(M.AddRow({ key = "Late", label = "Late", act = function() end, enabled = function() return false end, why = "Not now" }))
  c.obj.OnClick(c.obj, "LeftButton")
  rows = {}
  for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu then rows[#rows + 1] = f end end
  assert(#rows == 5 and not rows[5].enabled and rows[5].note.text == "Not now", "a late row is greyed out with its reason")
  -- RestedXP unreadable: the other addon's row still works.
  c.rxp.settings.ToggleActive = nil
  M.Refresh()
  assert(rows[4].enabled, "an added row doesn't depend on RestedXP being readable")
end

print("PASSED")
