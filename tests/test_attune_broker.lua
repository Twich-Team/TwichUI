-- Optional integration lifecycle and delegation to Attune's own lazy window toggle.
dofile(TESTS .. "harness.lua")

local NAME = "TwichUI Attune"
local function Library(c)
  local ldb = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function ldb:NewDataObject(name, obj)
    if name == NAME then c.made = c.made + 1; c.obj = obj end
    return obj
  end
end

local function Attune(c)
  c.Attune_SlashCommandHandler = function(msg)
    assert(msg == "", "only the window toggle, no commands or arguments")
    c.toggles = c.toggles + 1
    c.window = c.window or { shown = false }
    c.window.shown = not c.window.shown
  end
end

local function Client(attune, library)
  local c = MakeClient("Rich", { "!!!TwichUI", "Attune" })
  c.made, c.toggles = 0, 0
  if attune then Attune(c) end
  if library then Library(c) end
  local chunk = assert(loadfile(ROOT .. "modules/AttuneBroker.lua"))
  setfenv(chunk, c); chunk()
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  return c
end

do
  local c = Client(true, true)
  assert(c.made == 0, "waits for login")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other")
  assert(c.made == 1 and c.TwichUI.AttuneBroker.Available(), "registered once")
  assert(c.obj.type == "data source" and c.obj.label == "Attune" and c.obj.text == "", "icon only")
  assert(not c.window and c.toggles == 0, "registration never creates Attune's window")
  c.obj.OnClick(nil, "LeftButton")
  assert(c.window.shown and c.toggles == 1, "first click delegates lazy creation and opening")
  c.obj.OnClick(nil, "LeftButton")
  assert(not c.window.shown and c.toggles == 2, "second click delegates closing")
  c.Attune_SlashCommandHandler = nil
  c.obj.OnClick(nil, "LeftButton")
  assert(c.toggles == 2, "missing handler is harmless")
end

do
  local c = Client(false, true)
  c.FireEvent("PLAYER_LOGIN")
  assert(c.made == 0 and not c.TwichUI.AttuneBroker.Available(), "absent Attune is harmless")
  Attune(c); c.FireEvent("ADDON_LOADED", "Attune")
  assert(c.made == 1, "late Attune is discovered")
  local d = Client(true, false)
  d.FireEvent("PLAYER_LOGIN")
  assert(d.made == 0, "absent library is harmless")
  Library(d); d.FireEvent("ADDON_LOADED", "DataBar")
  assert(d.made == 1, "late library is discovered")
  local e = Client(false, false)
  e.LibStub = nil
  e.FireEvent("PLAYER_LOGIN")
  assert(e.made == 0, "no LibStub is harmless")
end

print("ATTUNE BROKER TESTS PASSED")
