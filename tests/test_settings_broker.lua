-- TwichUI on a data bar (SettingsBroker.lua): one "TwichUI" launcher, made only when a data bar's LibDataBroker exists
-- (at login or later), once; a left click goes through R:OpenSettings (the one way to open the settings), opens the window
-- or brings an open one forward without closing it or changing its page; other buttons do nothing; the tooltip says only
-- what the click does; no update loop; nothing breaks without LibDataBroker.
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
  assert(#calls == 1, "other buttons do nothing")
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
