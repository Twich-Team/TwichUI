-- TwichUI on a data bar (SettingsBroker.lua): one "TwichUI" launcher, made only when a data bar's LibDataBroker exists
-- (at login or later), once; a left click opens its menu (modules/SettingsBrokerMenu.lua) and a second one closes it, or
-- opens the settings when the menu code isn't there; a right click opens the settings through R:OpenSettings (the one way
-- to open them), which opens the window or brings an open one forward without closing it or changing its page; other
-- buttons do nothing; the tooltip says what the clicks do; no update loop; nothing breaks without LibDataBroker.
-- The menu: Open settings, the Leave me alone switch (Decline duels + Decline group invitations through qol/QoL.lua),
-- and the Guild Locations choices (through R.GuildLoc.SetState, never turning sharing on from Off). The game's frames
-- are recorded stand-ins; how it looks is not tested.
dofile(TESTS .. "harness.lua")

local OURS = "TwichUI"
-- Only this broker's registrations: other brokers share the library.
local function Count(c) local n = 0 for _, name in ipairs(c.made) do if name == OURS then n = n + 1 end end return n end
local function Obj(c) return c.objects[OURS] end

local function Client(withLDB)
  local c = MakeClient("Rich", { "!!!TwichUI" })
  c.made, c.objects = {}, {}
  if withLDB then
    local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
    function LDB:NewDataObject(name, o) table.insert(c.made, name); c.objects[name] = o; return o end
  end
  local chunk = assert(loadfile(ROOT .. "SettingsBroker.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  return c
end

-- A stand-in for TwichUI_Settings' window: Open shows it (and goes to the page named, or stays where it was), Close hides it.
local function Window(c)
  local w = { shown = false, opens = 0, closes = 0, page = "overview" }
  c.TwichUI.SettingsUI = {
    Open = function(page) w.opens = w.opens + 1; w.shown = true; if page then w.page = page end end,
    Close = function() w.closes = w.closes + 1; w.shown = false end,
    IsShown = function() return w.shown end,
  }
  return w
end

-- 1. Logged in with a data bar's LibDataBroker: made once, as a launcher with TwichUI's own icon, however often it is asked.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other"); c.TwichUI.SettingsBroker.Refresh()
  assert(Count(c) == 1, "registered once, by name")
  local obj = Obj(c)
  assert(obj.type == "launcher" and obj.label == "TwichUI" and obj.text == "TwichUI", "a launcher named TwichUI")
  assert(obj.icon == c.TwichUI.PATH .. "media\\textures\\twichui-broker-compass", "the TwichUI compass with nothing active")
  assert(obj.OnUpdate == nil, "no update loop")
  assert(c.TwichUI.SettingsBroker.Available(), "available once made")
end

-- 2. Without the menu code a left click opens the settings (once per click, no page named, so the window keeps its page);
--    a right click always does.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local calls = {}
  c.TwichUI.OpenSettings = function(self, ...) calls[#calls + 1] = select("#", ...) end
  Obj(c).OnClick("frame", "LeftButton")
  assert(#calls == 1 and calls[1] == 0, "a left click calls R:OpenSettings() with no page")
  Obj(c).OnClick("frame", "RightButton")
  assert(#calls == 2 and calls[2] == 0, "a right click does the same")
  Obj(c).OnClick("frame", "MiddleButton")
  assert(#calls == 2, "other buttons do nothing")
end

-- 2b. With the menu code a left click toggles the menu on the bar's frame (and puts the tooltip away); a right click opens
--     the settings, not the menu.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local toggled, opened = {}, 0
  c.TwichUI.SettingsBrokerMenu = { Toggle = function(frame) toggled[#toggled + 1] = frame end }
  c.TwichUI.OpenSettings = function() opened = opened + 1 end
  local hidden = 0
  c.GameTooltip = { Hide = function() hidden = hidden + 1 end }
  Obj(c).OnClick("bar", "LeftButton")
  assert(#toggled == 1 and toggled[1] == "bar" and opened == 0 and hidden == 1, "left click: the menu, on the bar")
  Obj(c).OnClick("bar", "RightButton")
  assert(#toggled == 1 and opened == 1, "right click: the settings")
  Obj(c).OnClick("bar", "MiddleButton")
  assert(#toggled == 1 and opened == 1)
end

-- 3. Through the real opener: the window opens; a second right click while it is open brings it forward and neither closes it nor
--    changes its page.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local w = Window(c)
  Obj(c).OnClick("frame", "RightButton")
  assert(w.shown and w.opens == 1, "the first click opens the window")
  w.page = "chronicle"
  Obj(c).OnClick("frame", "RightButton")
  assert(w.shown and w.opens == 2 and w.closes == 0, "the second click shows it again and never closes it")
  assert(w.page == "chronicle", "the page it was left on stays")
end

-- 4. The tooltip names the clicks and the two states the menu changes (nothing without them).
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function() error("no extra rows") end })
  assert(#lines == 4 and lines[1] == "TwichUI" and lines[2] == "Left-click for the menu." and lines[3] == "Right-click to open settings."
    and lines[4] == "Quiet screen: Off.", table.concat(lines, "|"))
  c.TwichUI.QuietScreen.Set(true)
  lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function() error("no extra rows") end })
  assert(lines[4] == "Quiet screen: On.", "the tooltip says when the screen is quiet: " .. table.concat(lines, "|"))
end

---------------------------------------------------------------------------
-- The menu (modules/SettingsBrokerMenu.lua): drawn on recorded stand-ins for the game's frames
---------------------------------------------------------------------------
local MENU_FILES = { "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
  "modules/SettingsBrokerMenu.lua", "qol/QoL.lua", "qol/Duels.lua", "qol/DeclineInvites.lua", "guildloc/State.lua" }

local function MenuClient(opts)
  opts = opts or {}
  local c = Client(true)
  c.TwichUIDB = opts.db or {}
  c.tipHidden = 0
  c.GameTooltip = { Hide = function() c.tipHidden = c.tipHidden + 1 end, GetOwner = function() end }
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
    return f
  end
  c.UIParent = Fake("UIParent")
  c.UISpecialFrames, c.tinsert, c.STANDARD_TEXT_FONT = {}, table.insert, "Fonts\\FRIZQT__.TTF"
  c.inCombat = false
  c.InCombatLockdown = function() return c.inCombat end
  for _, f in ipairs(opts.files or MENU_FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.opened = {}
  c.TwichUI.OpenSettings = function(self, page) c.opened[#c.opened + 1] = page or "none" end
  return c
end

-- The open menu: its frame, its clickable rows by label (name text), and a click.
local function OpenMenu(c, bar)
  Obj(c).OnClick(bar or "bar", "LeftButton")
  local menu
  for _, f in ipairs(c.frames) do if f.name == "TwichUISettingsMenu" then menu = f end end
  assert(menu, "the menu exists after a left click")
  local rows = {}
  for _, f in ipairs(c.frames) do
    if f.kind == "Button" and f.parent == menu then rows[f.name and f.name.text or "?"] = f end
  end
  return menu, rows
end
local function Click(row) assert(row.enabled, "clicking a greyed row"); row.scripts.OnClick(row) end

-- 10. A left click opens it with Open settings, Leave me alone and the Guild Locations choices; a second click closes it;
--     it is a backdrop frame that Esc closes, and the tooltip is put away.
do
  local c = MenuClient()
  local menu, rows = OpenMenu(c)
  assert(menu.shown and menu.template == "BackdropTemplate" and c.UISpecialFrames[1] == "TwichUISettingsMenu", "a backdrop frame Esc closes")
  assert(c.tipHidden == 1, "the tooltip is hidden so it does not sit over the menu")
  for _, label in ipairs({ "Open settings...", "Leave me alone", "Sharing my location", "Invisible (still see others)", "Guild Locations settings..." }) do
    assert(rows[label], "a row: " .. label)
  end
  assert(rows["Leave me alone"].note.text == "Off" and rows["Leave me alone"].fill.shown == false, "Leave me alone starts Off")
  assert(rows["Sharing my location"].note.text == "Current" and rows["Sharing my location"].fill.shown, "Sharing is the current choice by default")
  assert(rows["Invisible (still see others)"].note.text == "" and rows["Invisible (still see others)"].fill.shown == false)
  assert(c.TwichUI.SettingsBrokerMenu.IsOpen(), "open")
  Obj(c).OnClick("bar", "LeftButton")
  assert(not menu.shown and not c.TwichUI.SettingsBrokerMenu.IsOpen(), "a second click closes it")
  Obj(c).OnClick("bar", "LeftButton")
  assert(menu.shown, "and a third opens it again")
  assert(#c.opened == 0, "opening the menu opens no settings")
end

-- 11. Open settings... opens the window and closes the menu; so does the Guild Locations page entry.
do
  local c = MenuClient()
  local menu, rows = OpenMenu(c)
  Click(rows["Open settings..."])
  assert(c.opened[1] == "none" and not menu.shown, "Open settings opens the window (no page) and closes the menu")
  menu, rows = OpenMenu(c)
  Click(rows["Guild Locations settings..."])
  assert(c.opened[2] == "guildLocations" and not menu.shown, "the Guild Locations entry opens its page and closes the menu")
end

-- 12. Leave me alone: both switches at once, the menu stays open and the row follows; the settings window's own change
--     shows too; exceptions and the player's own choices are respected (see test_qol.lua for the switch logic).
do
  local c = MenuClient()
  local R = c.TwichUI
  local menu, rows = OpenMenu(c)
  local leave = rows["Leave me alone"]
  assert(not R:Enabled("qolDuels") and not R:Enabled("qolDeclineInvites"))
  Click(leave)
  assert(R:Enabled("qolDuels") and R:Enabled("qolDeclineInvites"), "one click turns both on")
  assert(menu.shown and leave.note.text == "On" and leave.fill.shown, "the menu stays open and says On")
  assert(c.TwichUIDB.modules.qolDuels == true and c.TwichUIDB.modules.qolDeclineInvites == true, "saved as the ordinary switches")
  Click(leave)
  assert(not R:Enabled("qolDuels") and not R:Enabled("qolDeclineInvites") and leave.note.text == "Off", "and one click turns both off")
  -- the player already had Decline duels on: it stays on
  R:SetEnabled("qolDuels", true)
  assert(leave.note.text == "Off", "only one of the two on is still Off")
  Click(leave); Click(leave)
  assert(R:Enabled("qolDuels") and not R:Enabled("qolDeclineInvites"), "what the player had on stays on")
  -- a change made in the settings while the menu is open
  R:SetEnabled("qolDeclineInvites", true)
  assert(leave.note.text == "On", "the row follows the settings window")
  R:SetEnabled("qolDuels", false); R:SetEnabled("qolDeclineInvites", false)
end

-- 12b. Quiet the screen: one click turns the session-only switch (QuietScreen.lua) on or off, the menu stays open and the row
--      follows, and a change made elsewhere shows too. Nothing is saved.
do
  local c = MenuClient()
  local Q = c.TwichUI.QuietScreen
  local menu, rows = OpenMenu(c)
  local quiet = rows["Quiet the screen"]
  assert(quiet and quiet.enabled and quiet.note.text == "Off" and quiet.fill.shown == false, "the row starts Off")
  assert(quiet.scripts.OnEnter, "and has a tooltip that says what it does")
  Click(quiet)
  assert(Q.On() and menu.shown and quiet.note.text == "On" and quiet.fill.shown, "one click turns it on; the menu stays open and says On")
  Q.Set(false)
  assert(quiet.note.text == "Off" and menu.shown, "turned off elsewhere: the row follows")
  Click(quiet); Click(quiet)
  assert(not Q.On() and quiet.note.text == "Off", "and one click turns it off again")
  local saved = false
  for k in pairs(c.TwichUIDB) do if tostring(k):lower():find("quietscreen") then saved = true end end
  for k in pairs(c.TwichUIDB.modules or {}) do if tostring(k):lower():find("quietscreen") then saved = true end end
  assert(not saved, "no saved key for it")
end

-- 13. Guild Locations: the radios go through the core; never from Off; greyed with the reason; held; outside a guild.
do
  local c = MenuClient()
  local GL = c.TwichUI.GuildLoc
  local menu, rows = OpenMenu(c)
  Click(rows["Invisible (still see others)"])
  assert(GL.State() == "invisible" and c.TwichUIDB.guildLoc.state == "invisible", "Invisible is saved through the core")
  assert(menu.shown and rows["Invisible (still see others)"].note.text == "Current" and rows["Sharing my location"].note.text == "", "the rows follow")
  Click(rows["Sharing my location"])
  assert(GL.State() == "sharing")
  assert(GL.Interval() == 15 and c.TwichUIDB.guildLoc.interval == nil, "the menu never touches the interval")
end
do
  local c = MenuClient({ db = { guildLoc = { state = "off", interval = 30 } } })
  local GL = c.TwichUI.GuildLoc
  local menu, rows = OpenMenu(c)
  for _, label in ipairs({ "Sharing my location", "Invisible (still see others)" }) do
    assert(rows[label].enabled == false and rows[label].note.text == "Off", label .. " is greyed and says Off")
    assert(rows[label].scripts.OnClick, "(a click does nothing)")
    rows[label].scripts.OnClick(rows[label])
  end
  assert(GL.State() == "off" and c.TwichUIDB.guildLoc.state == "off" and c.TwichUIDB.guildLoc.interval == 30, "the menu never turns sharing on from Off")
  c.IsInGuild = function() return false end
  GL.SetState("invisible")
  c.TwichUI.SettingsBrokerMenu.Refresh()
  assert(rows["Sharing my location"].enabled and rows["Invisible (still see others)"].fill.shown, "outside a guild the choices are selectable")
  Click(rows["Sharing my location"])
  assert(GL.State() == "sharing", "a privacy preference can be set outside a guild")
end
do
  local c = MenuClient({ db = { guildLoc = { state = "sharing" } } })
  c.TwichUI.Persist = { IsHeld = function(key) return key == "TwichUIDB" end }
  local menu, rows = OpenMenu(c)
  assert(rows["Sharing my location"].enabled == false and rows["Sharing my location"].note.text == "Unavailable", "held: unavailable")
  assert(rows["Guild Locations settings..."].enabled, "the settings page still opens, to explain")
  assert(c.TwichUIDB.guildLoc.state == "sharing" and not c.TwichUI.GuildLoc.SetState("off"), "held: nothing is written")
end

-- 14. Closing: a click elsewhere, not on the menu or the bar; listens only while open; the player's look follows.
do
  local c = MenuClient()
  local R = c.TwichUI
  local bar = { IsMouseOver = function() return false end }
  assert(not R.frame.events.GLOBAL_MOUSE_DOWN, "not listening before it opens")
  local menu = OpenMenu(c, bar)
  assert(R.frame.events.GLOBAL_MOUSE_DOWN, "listens while open")
  menu.mouse = true; c.FireEvent("GLOBAL_MOUSE_DOWN"); assert(menu.shown, "a click on the menu keeps it open")
  menu.mouse = false; bar.IsMouseOver = function() return true end; c.FireEvent("GLOBAL_MOUSE_DOWN"); assert(menu.shown, "a click on the bar entry leaves that to its own click")
  bar.IsMouseOver = function() return false end; c.FireEvent("GLOBAL_MOUSE_DOWN")
  assert(not menu.shown and not R.frame.events.GLOBAL_MOUSE_DOWN, "a click elsewhere closes it, and it stops listening")
  c.inCombat = true
  OpenMenu(c, bar)
  assert(R.SettingsBrokerMenu.IsOpen(), "it opens in combat (nothing in it is secure)")
end

-- 15. Without Guild Locations loaded the menu has no Guild Locations section; nothing breaks.
do
  local files = {}
  for _, f in ipairs(MENU_FILES) do if f ~= "guildloc/State.lua" then files[#files + 1] = f end end
  local c = MenuClient({ files = files })
  assert(c.TwichUI.GuildLoc == nil)
  local menu, rows = OpenMenu(c)
  local shown = {}
  for label, row in pairs(rows) do if row.shown then shown[label] = true end end
  assert(shown["Open settings..."] and shown["Leave me alone"] and not shown["Sharing my location"] and not shown["Guild Locations settings..."],
    "only the rows that make sense are drawn")
  local lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
  assert(#lines == 5 and lines[4] == "Quiet screen: Off." and lines[5] == "Leave me alone: Off.", table.concat(lines, "|"))
end

-- 5. Without a data bar's LibDataBroker nothing is made and nothing breaks; a data bar addon that loads later brings the
--    library and the launcher is made then, once.
do
  local c = Client(false)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("ADDON_LOADED", "Other")
  assert(not c.TwichUI.SettingsBroker.Available() and Count(c) == 0, "no LibDataBroker, nothing made")
  local w = Window(c)
  c.TwichUI:OpenSettings()
  assert(w.shown, "the settings still open without a launcher")
  local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function LDB:NewDataObject(name, o) table.insert(c.made, name); c.objects[name] = o; return o end
  c.FireEvent("ADDON_LOADED", "SomeDataBar"); c.FireEvent("ADDON_LOADED", "SomeOtherAddon")
  assert(Count(c) == 1 and c.TwichUI.SettingsBroker.Available(), "made once when a data bar brings LibDataBroker later")
end

-- 6. Nothing is made before login.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("ADDON_LOADED", "Other")
  assert(Count(c) == 0, "not before PLAYER_LOGIN")
end

print("SETTINGS BROKER TESTS PASSED")

---------------------------------------------------------------------------
-- State icons: Leave me alone, Quiet the screen, Guild Locations hidden (Invisible / Off)
---------------------------------------------------------------------------
do
  local ICON_FILES = { "qol/QoL.lua", "guildloc/State.lua", "Switches.lua" }
  local function IconClient(db)
    local c = Client(true)
    c.TwichUIDB = db or { modules = {} }
    c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    for _, f in ipairs(ICON_FILES) do
      local ok, chunk = pcall(loadfile, ROOT .. f)
      if ok and chunk then setfenv(chunk, c); local ran, err = pcall(chunk, "!!!TwichUI", {}) ; if not ran then error(f .. ": " .. tostring(err)) end end
    end
    c.FireEvent("PLAYER_LOGIN")
    return c
  end
  local P = "media\\textures\\twichui-broker-"
  local function Icon(c) return Obj(c).icon:sub(#c.TwichUI.PATH + 1) end
  local EXPECT = { none = P .. "compass", leave = P .. "leave-alone", quiet = P .. "quiet", location = P .. "location", multiple = P .. "multiple" }

  local function Set(c, leave, quiet, loc)
    c.TwichUI:SetEnabled("qolDuels", leave); c.TwichUI:SetEnabled("qolDeclineInvites", leave)
    c.TwichUI.QuietScreen.Set(quiet)
    c.TwichUI.GuildLoc.SetState(loc and "invisible" or "sharing")
  end

  -- all eight combinations, each reached from a different earlier state
  local c = IconClient()
  for mask = 0, 7 do
    local leave, quiet, loc = mask % 2 == 1, math.floor(mask / 2) % 2 == 1, math.floor(mask / 4) % 2 == 1
    Set(c, leave, quiet, loc)
    local n = (leave and 1 or 0) + (quiet and 1 or 0) + (loc and 1 or 0)
    local want = n == 0 and "none" or n >= 2 and "multiple" or leave and "leave" or quiet and "quiet" or "location"
    assert(Icon(c) == EXPECT[want], "mask " .. mask .. ": " .. Icon(c))
  end
  -- all three -> pair -> single -> none, and back up
  Set(c, true, true, true);  assert(Icon(c) == EXPECT.multiple)
  Set(c, true, true, false); assert(Icon(c) == EXPECT.multiple, "a pair")
  Set(c, true, false, false); assert(Icon(c) == EXPECT.leave, "a single")
  Set(c, false, false, false); assert(Icon(c) == EXPECT.none, "none")
  Set(c, false, true, false); assert(Icon(c) == EXPECT.quiet)
  Set(c, false, true, true); assert(Icon(c) == EXPECT.multiple)

  -- Off hides the position too; a profile change (Switches.Sync) is followed
  c.TwichUI.GuildLoc.SetState("off"); Set(c, false, false, false); c.TwichUI.GuildLoc.SetState("off")
  assert(Icon(c) == EXPECT.location, "Off is not sharing")
  c.TwichUI.GuildLoc.SetState("sharing")
  c.TwichUIDB.modules.qolDuels, c.TwichUIDB.modules.qolDeclineInvites = true, true
  c.TwichUI.Switches.Sync()
  assert(Icon(c) == EXPECT.leave, "a profile change that turns Leave me alone on")

  -- the initial icon reflects saved state with nothing toggled; defaults show the compass
  local d = IconClient({ modules = { qolDuels = true, qolDeclineInvites = true }, guildLoc = { state = "invisible" } })
  assert(Icon(d) == EXPECT.multiple, "saved Leave me alone + Invisible: " .. Icon(d))
  local e = IconClient({ modules = { qolDuels = false, qolDeclineInvites = false } })
  assert(Icon(e) == EXPECT.none, "defaults: sharing, nothing quiet")
  assert(e.TwichUIDB.guildLoc == nil and e.TwichUIDB.modules.qolDuels == false, "choosing an icon wrote nothing")

  -- unknown state is not active: no saved data, no owners
  local u = IconClient({})
  assert(Icon(u) == EXPECT.none, "saved data not ready")
  local bare = Client(true); bare.FireEvent("ADDON_LOADED", "!!!TwichUI"); bare.FireEvent("PLAYER_LOGIN")
  assert(Icon(bare) == EXPECT.none, "owners not loaded")

  -- the tooltip names the active modes
  Set(c, true, true, false)
  local lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
  assert(lines[#lines] == "Active: Leave me alone, Quiet the screen.", lines[#lines])
  assert(Obj(c).OnUpdate == nil and Count(c) == 1, "no polling, one registration")
end
