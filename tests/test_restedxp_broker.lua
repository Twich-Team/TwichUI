-- RestedXP guide data source (modules/RestedXPBroker.lua): made once, only with RestedXP and LibDataBroker;
-- its text follows the guide; a click calls RestedXP's own ToggleActive (nothing else of RestedXP's is
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
  c.made = {}
  if not opts.noRXP then
    local rxp = { settings = { profile = { showEnabled = true } }, toggles = 0 }
    function rxp.settings.ToggleActive()
      rxp.toggles = rxp.toggles + 1
      rxp.settings.profile.showEnabled = not rxp.settings.profile.showEnabled
    end
    function rxp.settings:RefreshProfile() self.profile = rxp.nextProfile end
    function rxp.GetGuideName(guide) return guide.displayname end
    if opts.broken then rxp.settings.ToggleActive = nil end
    local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
    function ace:GetAddon(name) if name == "RXPGuides" then return rxp end end
    c.rxp = rxp
  end
  if not opts.lateLDB then
    local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
    function LDB:NewDataObject(name, o) if name == "TwichUI RestedXP Guide" then c.made[#c.made + 1] = name; c.obj = o end return o end
  end
  local chunk = assert(loadfile(ROOT .. "modules/RestedXPBroker.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
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
  assert(tip:find("Guide: On", 1, true) and tip:find("Click to turn the guide off", 1, true), tip)
  assert(not tip:find("Current", 1, true), "no guide loaded, no name: " .. tip)

  obj.OnClick(obj, "LeftButton")
  assert(c.rxp.toggles == 1 and c.rxp.settings.profile.showEnabled == false and obj.text == "Guide off", "click turns it off")
  assert(c.tipHidden == 1, "the out-of-date tooltip is hidden")
  assert(Tip(obj):find("Click to turn the guide on", 1, true), "tooltip offers turning it on")

  obj.OnClick(obj, "RightButton")
  assert(c.rxp.toggles == 2 and obj.text == "Guide on", "any button toggles")

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

print("PASSED")
