-- RestedXP guide data source (modules/RestedXPBroker.lua): made once, only with RestedXP and LibDataBroker;
-- its text follows the guide; a click opens a menu (show guide = RestedXP's own ToggleActive, lock windows =
-- profile.lockFrames, auto quests / auto flight path = profile.enableQuestAutomation / enableFPAutomation,
-- discard junk if full = profile.autoDiscardItems (greyed out while enableInventoryManager is off or no bag
-- addon is supported), import = guideImporter:Open(), greyed out in combat; nothing else of RestedXP's is
-- touched); a toggle or profile change made elsewhere is followed; hooks go in once; an unknown RestedXP
-- shape makes nothing.
-- Choosing a guide: the menu lists RXPFrame:GenerateMenuTable({}) up to its empty title (sections, groups,
-- guides, chapters), marks the loaded guide and the groups leading to it, steps in and back, and loads a pick
-- through that entry's own click handler. The menu table is shaped as GuideWindow.lua builds it.
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
  c.GameTooltip = { Hide = function() c.tipHidden = c.tipHidden + 1 end, GetOwner = function() end }
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
    local f = Fake(kind); f.name, f.parent, f.template = name, parent, template
    if template == "UIPanelScrollFrameTemplate" then
      f.ScrollBar = Fake("bar")
      f.ScrollBar.ThumbTexture = Fake("texture")
      f.ScrollBar.ScrollUpButton, f.ScrollBar.ScrollDownButton = Fake("button"), Fake("button")
    end
    return f
  end
  c.UIParent = Fake("UIParent")
  c.UISpecialFrames = {}
  c.tinsert = table.insert
  c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  if not opts.noRXP then
    local rxp = { settings = { profile = { showEnabled = true, enableQuestAutomation = true, enableFPAutomation = false,
      enableInventoryManager = true, autoDiscardItems = false } }, toggles = 0, bagsAvailable = true }
    rxp.inventoryManager = { bagManager = { IsAvailable = function() return rxp.bagsAvailable end } }
    function rxp.settings.ToggleActive()
      rxp.toggles = rxp.toggles + 1
      rxp.settings.profile.showEnabled = not rxp.settings.profile.showEnabled
    end
    function rxp.settings:RefreshProfile() self.profile = rxp.nextProfile end
    function rxp.GetGuideName(guide) return guide.displayname end
    rxp.guideImporter = { opens = 0, Open = function(self) self.opens = self.opens + 1 end }
    -- RestedXP's menu table: a title, groups with guides (and a sub-group), a guide with chapters, a disabled
    -- guide, then the empty title where its own entries start (which must not be read).
    rxp.loaded = {}
    local function OnClick(_, group, name) rxp.loaded[#rxp.loaded + 1] = group .. "/" .. name; rxp.currentGuide = { group = group, name = name, displayname = name } end
    local function Guide(group, name, text) return { text = text or name, func = OnClick, arg1 = group, arg2 = name, notCheckable = 1 } end
    rxp.RXPFrame = {
      builds = 0,
      GenerateMenuTable = function(self, menu)
        assert(self == rxp.RXPFrame and type(menu) == "table", "called as RXPFrame:GenerateMenuTable(table)")
        self.builds = self.builds + 1
        local out = menu
        out[#out + 1] = { text = "Available Guides", isTitle = 1, notCheckable = 1 }
        out[#out + 1] = { text = "Alliance", hasArrow = true, notCheckable = 1, menuList = {
          Guide("Alliance", "1-6 Elwynn", "1-6 Elwynn Forest\nStart"),
          Guide("Alliance", "6-10 Westfall"),
          { text = "Dungeons", hasArrow = true, notCheckable = 1, menuList = { Guide("Alliance", "Deadmines") } },
          { text = "Hidden", isTitle = 1, notCheckable = 1 },
        } }
        out[#out + 1] = { text = "Questlines", hasArrow = true, notCheckable = 1, menuList = {
          { text = "Chain", hasArrow = true, notCheckable = 1, menuList = { Guide("Questlines", "Chain 1") } },
        } }
        out[#out + 1] = { text = "Empty group", hasArrow = true, notCheckable = 1, menuList = {} }
        out[#out + 1] = { text = "", isTitle = 1, notCheckable = 1 }
        out[#out + 1] = { text = "Display Tips", notCheckable = 1, func = function() error("must not be read") end }
        return out
      end,
    }
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
    assert(#rows == 7, "seven rows: " .. #rows)
    local function Click(row) if row.enabled then row.scripts.OnClick(row) end end
    return menu, rows, Click
  end

  local bus = c.TwichUI.frame
  assert(not bus.events.GLOBAL_MOUSE_DOWN and not bus.events.PLAYER_REGEN_DISABLED, "listens to nothing while closed")
  local menu, rows, Click = Open("LeftButton")
  assert(bus.events.GLOBAL_MOUSE_DOWN and bus.events.PLAYER_REGEN_DISABLED, "listens while open")
  local choose, guide, lock, quests, flight, discard, import =
    rows[1], rows[2], rows[3], rows[4], rows[5], rows[6], rows[7]
  assert(choose.name.text == "Choose guide" and choose.chev.shown and choose.enabled, "Choose guide leads the menu, with an arrow")
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

  -- Auto quests and auto flight path: plain profile switches, no RestedXP toggle, the menu stays open.
  assert(quests.name.text == "Auto quests" and quests.note.text == "On" and quests.fill.shown == true, "auto quests starts on")
  assert(flight.name.text == "Auto flight path" and flight.note.text == "Off" and flight.fill.shown == false, "auto flight path starts off")
  Click(quests)
  assert(c.rxp.settings.profile.enableQuestAutomation == false and quests.note.text == "Off" and menu.shown, "auto quests turns off in place")
  assert(c.rxp.toggles == 2 and obj.text == "Guide on", "without touching the guide")
  Click(flight)
  assert(c.rxp.settings.profile.enableFPAutomation == true and flight.note.text == "On" and flight.fill.shown == true, "auto flight path turns on")
  Click(flight)
  assert(c.rxp.settings.profile.enableFPAutomation == false and flight.note.text == "Off", "and back off")
  Click(quests)
  assert(c.rxp.settings.profile.enableQuestAutomation == true and quests.note.text == "On", "auto quests back on")

  -- Discard junk if full: RestedXP's own option, set in place, the guide untouched.
  assert(discard.name.text == "Discard junk if full" and discard.note.text == "Off" and discard.fill.shown == false
    and discard.enabled, "discard junk starts off and can be clicked")
  Click(discard)
  assert(c.rxp.settings.profile.autoDiscardItems == true and discard.note.text == "On" and discard.fill.shown == true
    and menu.shown, "discard junk turns on in place")
  assert(c.rxp.toggles == 2 and obj.text == "Guide on", "without touching the guide")
  Click(discard)
  assert(c.rxp.settings.profile.autoDiscardItems == false and discard.note.text == "Off", "and back off")

  -- Greyed out, with the reason, while RestedXP's own option page would hide it; its box still shows the state.
  -- The central operation refuses too, so a stale click can't change it.
  local B = c.TwichUI.RestedXPBroker
  c.rxp.settings.profile.autoDiscardItems = true
  c.rxp.settings.profile.enableInventoryManager = false
  c.TwichUI.RestedXPBrokerMenu.Refresh()
  assert(not discard.enabled and discard.note.text == "Inventory off" and discard.fill.shown == true,
    "greyed out while the inventory manager is off")
  Click(discard)
  B.SetDiscard(false)
  assert(c.rxp.settings.profile.autoDiscardItems == true, "a greyed switch changes nothing")
  c.rxp.settings.profile.enableInventoryManager = true
  c.rxp.bagsAvailable = false
  c.TwichUI.RestedXPBrokerMenu.Refresh()
  assert(not discard.enabled and discard.note.text == "Unavailable", "greyed out when no supported bag addon is there")
  B.SetDiscard(false)
  assert(c.rxp.settings.profile.autoDiscardItems == true, "the operation refuses then too")
  c.rxp.bagsAvailable = true
  c.TwichUI.RestedXPBrokerMenu.Refresh()
  assert(discard.enabled and discard.note.text == "On", "available again, and on")
  Click(discard)
  assert(c.rxp.settings.profile.autoDiscardItems == false and discard.note.text == "Off", "switched off again")

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

  -- Choosing a guide.
  do
    local menu2
    c.rxp.currentGuide = { group = "Alliance", name = "6-10 Westfall", displayname = "6-10 Westfall" }
    obj.OnClick(obj, "LeftButton")
    for _, f in ipairs(c.frames) do if f.name == "TwichUIRestedXPMenu" then menu2 = f end end
    local main = {}
    for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu2 then main[#main + 1] = f end end
    assert(c.rxp.RXPFrame.builds == 0, "the guide list is not read until asked for")
    main[1].scripts.OnClick(main[1])
    assert(c.rxp.RXPFrame.builds == 1, "read once when Choose guide is clicked")
    assert(menu2.shown, "the menu stays open")

    local function Level()
      local list = {}
      local scrollShown
      for _, f in ipairs(c.frames) do if f.template == "UIPanelScrollFrameTemplate" then scrollShown = f.shown end end
      if not scrollShown then return list end   -- (the fake frames don't hide children with their parent)
      for _, f in ipairs(c.frames) do
        if f.kind == "Button" and f.entry and f.shown then list[#list + 1] = f end
      end
      return list
    end
    local function Find(text) for _, r in ipairs(Level()) do if r.entry.text == text then return r end end end
    local back
    for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu2 and f.text and f.text.text == "Back" then back = f end end
    assert(back, "a Back button is shown")

    local top = Level()
    assert(#top == 3 and top[1].entry.heading and top[1].head.text == "Available Guides", "a heading, then the groups; nothing after the empty title")
    assert(top[2].entry.text == "Alliance" and top[2].chev.shown and top[2].mark.shown, "a group is marked as holding the loaded guide")
    assert(top[3].entry.text == "Questlines" and not top[3].mark.shown, "another group is not")
    assert(not Find("Empty group"), "a group with nothing in it is left out")
    assert(not Find("Display Tips"), "RestedXP's own entries are not listed")
    assert(not top[1].enabled, "a heading can't be clicked")

    top[3].scripts.OnClick(top[3])
    local inner = Level()
    assert(#inner == 1 and inner[1].entry.text == "Chain" and inner[1].chev.shown, "stepping into a group shows its contents")
    back.scripts.OnClick(back)
    assert(#Level() == 3, "Back returns to the list")

    Find("Alliance").scripts.OnClick(Find("Alliance"))
    local alliance = Level()
    assert(#alliance == 4, "guides, a sub-group, a disabled guide")
    local elwynn, westfall, dungeons, hidden = alliance[1], alliance[2], alliance[3], alliance[4]
    assert(elwynn.entry.text == "1-6 Elwynn Forest Start", "a newline in a name becomes a space: " .. tostring(elwynn.entry.text))
    assert(westfall.entry.current and westfall.mark.shown and westfall.note.text == "Current", "the loaded guide is marked, in words as well")
    assert(not elwynn.mark.shown and elwynn.note.text == "" and not elwynn.chev.shown, "others are not")
    assert(dungeons.chev.shown and not hidden.enabled, "a sub-group has an arrow; a disabled guide can't be clicked")
    hidden.scripts.OnClick(hidden)
    assert(#c.rxp.loaded == 0 and #Level() == 4, "a disabled guide does nothing")

    elwynn.scripts.OnClick(elwynn)
    assert(#c.rxp.loaded == 1 and c.rxp.loaded[1] == "Alliance/1-6 Elwynn", "a pick loads the guide through RestedXP's own handler")
    assert(not menu2.shown, "and closes the menu")
    assert(Tip(obj):find("Current: 1-6 Elwynn", 1, true), "the tooltip follows")

    -- It opens at the top level again, and the list is read again.
    obj.OnClick(obj, "LeftButton")
    assert(#Level() == 0 and menu2.shown and main[1].shown, "closing leaves browsing: the menu opens on its rows again")
    main[1].scripts.OnClick(main[1])
    assert(c.rxp.RXPFrame.builds == 2, "read again on the next visit")
    c.FireEvent("GLOBAL_MOUSE_DOWN")
    assert(not menu2.shown)

    -- Combat does not stop a choice (RestedXP's own menu doesn't).
    c.inCombat = true
    obj.OnClick(obj, "LeftButton")
    assert(main[1].enabled, "Choose guide stays available in combat")
    c.inCombat = false
    menu2:Hide()

    -- A menu table that can't be built, or RestedXP without the function.
    local frame = c.rxp.RXPFrame
    local real = frame.GenerateMenuTable
    frame.GenerateMenuTable = function() error("boom") end
    local handled, realHandler = 0, c.geterrorhandler
    c.geterrorhandler = function() return function() handled = handled + 1 end end
    obj.OnClick(obj, "LeftButton")
    main[1].scripts.OnClick(main[1])
    c.geterrorhandler = realHandler
    assert(handled == 1, "the error goes to the normal error handler, not swallowed")
    assert(#Level() == 0 and menu2.shown, "a failing list shows nothing, the menu survives")
    menu2:Hide()
    frame.GenerateMenuTable = nil
    obj.OnClick(obj, "LeftButton")
    assert(not main[1].enabled and main[1].note.text == "Unavailable" and not main[1].chev.shown, "greyed out when RestedXP has no such list")
    menu2:Hide()
    frame.GenerateMenuTable = real
  end

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
  assert(#rows == 8 and rows[8].name.text == "Guide rebinder..." and rows[8].enabled, "an eighth, enabled row")
  rows[8].scripts.OnClick(rows[8])
  assert(opened == 1 and not menu.shown, "its action runs and the menu closes")
  -- Added while the menu already exists.
  assert(M.AddRow({ key = "Late", label = "Late", act = function() end, enabled = function() return false end, why = "Not now" }))
  c.obj.OnClick(c.obj, "LeftButton")
  rows = {}
  for _, f in ipairs(c.frames) do if f.kind == "Button" and f.parent == menu then rows[#rows + 1] = f end end
  assert(#rows == 9 and not rows[9].enabled and rows[9].note.text == "Not now",
    "a late row is greyed out with its reason")
  -- RestedXP unreadable: the other addon's row still works.
  c.rxp.settings.ToggleActive = nil
  M.Refresh()
  assert(rows[8].enabled, "an added row doesn't depend on RestedXP being readable")
end

print("PASSED")
