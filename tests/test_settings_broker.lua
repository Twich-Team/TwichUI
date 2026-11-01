-- TwichUI on a data bar (SettingsBroker.lua): one "TwichUI" launcher, made only when a data bar's LibDataBroker exists
-- (at login or later), once; a left click goes through R:OpenSettings (the one way to open the settings), opens the window
-- or brings an open one forward without closing it or changing its page; a right click opens the Guild Locations menu
-- (Sharing / Invisible through R.GuildLoc.SetState, a shortcut to its page; never turns sharing on from Off; the page
-- instead when the game has no MenuUtil); other buttons do nothing; the tooltip says what the clicks do; no update loop;
-- nothing breaks without LibDataBroker.
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
  assert(obj.icon == c.TwichUI.PATH .. "media\\textures\\twichui-broker", "TwichUI's own icon")
  assert(obj.OnUpdate == nil, "no update loop")
  assert(c.TwichUI.SettingsBroker.Available(), "available once made")
end

-- 2. Left click: the canonical opener, once per click, with no page named (so the window keeps its page).
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local calls = {}
  c.TwichUI.OpenSettings = function(self, ...) calls[#calls + 1] = select("#", ...) end
  Obj(c).OnClick("frame", "LeftButton")
  assert(#calls == 1 and calls[1] == 0, "a left click calls R:OpenSettings() with no page")
  Obj(c).OnClick("frame", "RightButton"); Obj(c).OnClick("frame", "MiddleButton")
  assert(#calls == 1, "without Guild Locations, other buttons do nothing")
end

-- 3. Through the real opener: the window opens; a second click while it is open brings it forward and neither closes it nor
--    changes its page.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local w = Window(c)
  Obj(c).OnClick("frame", "LeftButton")
  assert(w.shown and w.opens == 1, "the first click opens the window")
  w.page = "chronicle"
  Obj(c).OnClick("frame", "LeftButton")
  assert(w.shown and w.opens == 2 and w.closes == 0, "the second click shows it again and never closes it")
  assert(w.page == "chronicle", "the page it was left on stays")
end

-- 4. The tooltip says what the click does, and nothing more.
do
  local c = Client(true)
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  local lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end, AddDoubleLine = function() error("no extra rows") end })
  assert(#lines == 2 and lines[1] == "TwichUI" and lines[2] == "Left-click to open settings.", "title and the one action")
end

---------------------------------------------------------------------------
-- Guild Locations: the right-click menu
---------------------------------------------------------------------------
-- A client with the real guildloc/State.lua (the one authority) and a recording stand-in for the game's menu.
local function GLClient(db)
  local c = Client(true)
  c.TwichUIDB = db or {}
  local chunk = assert(loadfile(ROOT .. "guildloc/State.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN")
  c.menus = {}
  c.MenuUtil = { CreateContextMenu = function(owner, gen)
    local m = { owner = owner, items = {} }
    local root = {}
    local function Add(kind, text, a, b)
      local item = { kind = kind, text = text, a = a, b = b, enabled = true }
      function item:SetEnabled(on) self.enabled = on end
      m.items[#m.items + 1] = item
      return item
    end
    function root:CreateTitle(t) return Add("title", t) end
    function root:CreateButton(t, fn) return Add("button", t, fn, fn) end
    function root:CreateRadio(t, sel, fn) return Add("radio", t, sel, fn) end
    gen(owner, root)
    c.menus[#c.menus + 1] = m
  end }
  return c
end
local function Find(m, text) for _, i in ipairs(m.items) do if i.text == text then return i end end end

-- 7. Right-click: the menu, built from the core's state; Sharing and Invisible go through GL.SetState.
do
  local c = GLClient()
  local GL = c.TwichUI.GuildLoc
  local opened = {}
  c.TwichUI.OpenSettings = function(self, page) opened[#opened + 1] = page or "none" end
  Obj(c).OnClick("bar", "LeftButton")
  assert(#c.menus == 0 and opened[1] == "none", "left click is unchanged: settings, no menu")
  Obj(c).OnClick("bar", "RightButton")
  local m = c.menus[1]
  assert(m and m.owner == "bar" and #opened == 1, "right click opens a menu on the bar, not the settings")
  assert(m.items[1].kind == "title" and m.items[1].text == "Guild Locations")
  local sharing, invisible = Find(m, "Sharing my location"), Find(m, "Invisible (still see others)")
  assert(sharing and invisible and sharing.a() and not invisible.a(), "Sharing is shown selected by default")
  invisible.b()
  assert(GL.State() == "invisible" and c.TwichUIDB.guildLoc.state == "invisible", "Invisible is saved through the core")
  assert(invisible.a() and not sharing.a(), "the radios read the core's state")
  sharing.b()
  assert(GL.State() == "sharing", "and back")
  Find(m, "Guild Locations settings...").b()
  assert(opened[2] == "guildLocations", "the settings entry opens the page")
  Obj(c).OnClick("bar", "MiddleButton")
  assert(#c.menus == 1, "other buttons still do nothing")
  assert(GL.Interval() == 15 and c.TwichUIDB.guildLoc.interval == nil, "the menu never touches the interval")
end

-- 8. Off, held and unusable: the menu never starts sharing from Off; privacy choices stay selectable outside a guild.
do
  local c = GLClient({ guildLoc = { state = "off", interval = 30 } })
  local GL = c.TwichUI.GuildLoc
  local opened = {}
  c.TwichUI.OpenSettings = function(self, page) opened[#opened + 1] = page end
  Obj(c).OnClick("bar", "RightButton")
  local m = c.menus[1]
  assert(not Find(m, "Sharing my location") and not Find(m, "Invisible (still see others)"), "no radios while Off")
  assert(Find(m, "Off") and Find(m, "Off").enabled == false, "Off is stated, greyed")
  Find(m, "Turn on in settings...").b()
  assert(opened[1] == "guildLocations" and GL.State() == "off" and c.TwichUIDB.guildLoc.state == "off", "the shortcut opens settings and changes nothing")
  assert(c.TwichUIDB.guildLoc.interval == 30, "the interval is untouched")
  c.IsInGuild = function() return false end
  GL.SetState("invisible")
  Obj(c).OnClick("bar", "RightButton")
  local m2 = c.menus[2]
  assert(Find(m2, "Sharing my location").enabled and Find(m2, "Invisible (still see others)").a(), "outside a guild the choices are selectable")
  Find(m2, "Sharing my location").b()
  assert(GL.State() == "sharing", "a privacy preference can be set outside a guild")
end
do
  local c = GLClient({ guildLoc = { state = "sharing" } })
  c.TwichUI.Persist = { IsHeld = function(key) return key == "TwichUIDB" end }
  Obj(c).OnClick("bar", "RightButton")
  local m = c.menus[1]
  assert(Find(m, "Unavailable right now") and not Find(m, "Turn on in settings...") and not Find(m, "Sharing my location"), "held: unavailable, nothing to choose")
  assert(Find(m, "Guild Locations settings..."), "the settings page still opens, to explain")
  assert(c.TwichUIDB.guildLoc.state == "sharing" and not c.TwichUI.GuildLoc.SetState("off"), "held: nothing is written")
end

-- 9. Without the game's menu, right-click opens the settings page; the tooltip names the clicks and the state.
do
  local c = GLClient()
  c.MenuUtil = nil
  local opened = {}
  c.TwichUI.OpenSettings = function(self, page) opened[#opened + 1] = page or "none" end
  Obj(c).OnClick("bar", "RightButton")
  assert(#opened == 1 and opened[1] == "guildLocations", "the fallback opens the Guild Locations page")
  local lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
  assert(#lines == 3 and lines[3] == "Right-click for Guild Locations (Sharing).", lines[3])
  c.TwichUI.GuildLoc.SetState("off")
  lines = {}
  Obj(c).OnTooltipShow({ AddLine = function(_, t) lines[#lines + 1] = t end })
  assert(lines[3] == "Right-click for Guild Locations (Off).", lines[3])
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
