-- BugSack's public API: current-session distinct count, OpenSack, Reset and UpdateDisplay.
dofile(TESTS .. "harness.lua")

local function Library(c)
  local ldb = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
  function ldb:NewDataObject(name, obj)
    if name == "TwichUI BugSack" then c.made = c.made + 1; c.obj = obj end
    return obj
  end
end

local function Sack(c)
  local errors = { {session = 1}, {session = 2, counter = 4} }
  c.errors = errors
  c.BugGrabber = { GetSessionId = function() return 2 end }
  c.BugSack = {
    GetErrors = function(_, session)
      local result = {}
      for _, e in ipairs(errors) do if e.session == session then result[#result + 1] = e end end
      return result
    end,
    UpdateDisplay = function() c.nativeUpdates = c.nativeUpdates + 1 end,
    OpenSack = function() c.opens = c.opens + 1 end,
    Reset = function(self)
      c.resets = c.resets + 1
      for i = #errors, 1, -1 do errors[i] = nil end
      self:UpdateDisplay()
    end,
  }
end

local function Client(withSack, withLibrary)
  local c = MakeClient("Rich", { "!!!TwichUI", "BugSack", "!BugGrabber" })
  c.made, c.opens, c.resets, c.hooks, c.nativeUpdates = 0, 0, 0, 0, 0
  c.hooksecurefunc = function(owner, name, callback)
    c.hooks = c.hooks + 1
    local original = owner[name]
    owner[name] = function(...)
      original(...)
      callback(...)
    end
  end
  if withSack then Sack(c) end
  if withLibrary then Library(c) end
  local chunk = assert(loadfile(ROOT .. "modules/BugSackBroker.lua"))
  setfenv(chunk, c); chunk()
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  return c
end

do
  local c = Client(true, true)
  assert(c.made == 1 and c.hooks == 1 and c.TwichUI.BugSackBroker.Available())
  assert(c.obj.text == "1", "matches native count: distinct errors in current session, not repetitions or old sessions")
  assert(c.opens == 0 and c.resets == 0, "registration does not open or clear anything")
  c.errors[#c.errors + 1] = { session = 2 }
  c.BugSack:UpdateDisplay()
  assert(c.obj.text == "2" and c.nativeUpdates == 1, "display updates follow newly caught bugs and preserve native behavior")
  c.obj.OnClick(nil, "LeftButton"); c.obj.OnClick(nil, "LeftButton")
  assert(c.opens == 2 and c.resets == 0, "left-click always opens the frame")
  c.obj.OnClick(nil, "MiddleButton")
  assert(c.opens == 2 and c.resets == 0, "other buttons are harmless")
  c.obj.OnClick(nil, "RightButton")
  assert(c.resets == 1 and #c.errors == 0 and c.obj.text == "0", "right-click clears all stored bugs through Reset")
  c.errors[1] = { session = 2 }
  c.BugSack:UpdateDisplay()
  c.BugSack:Reset()
  assert(c.obj.text == "0", "external reset is reflected")
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "Other")
  assert(c.made == 1 and c.hooks == 1, "no duplicate registration or hook")
  c.BugSack = nil
  c.obj.OnClick(nil, "RightButton")
  assert(c.resets == 2, "missing integration is harmless even after registration")
end

do
  local c = Client(false, true)
  assert(c.made == 0 and not c.TwichUI.BugSackBroker.Available())
  Sack(c); c.FireEvent("ADDON_LOADED", "BugSack")
  assert(c.made == 1, "late BugSack is supported")
  local d = Client(true, false)
  assert(d.made == 0 and d.hooks == 0, "no library means no object or hooks")
  Library(d); d.FireEvent("ADDON_LOADED", "DataBar")
  assert(d.made == 1 and d.obj.text == "1", "late library gets the current count")
  local e = Client(false, true)
  e.BugSack, e.BugGrabber = {}, {}
  e.FireEvent("ADDON_LOADED", "Unsupported")
  assert(e.made == 0, "unsupported APIs are harmless")
end

print("BUGSACK BROKER TESTS PASSED")
