-- EllesmereUI's quest tracker on mouseover while RestedXP's guide is shown (qol/GuideTracker.lua): set to Mouseover
-- while the guide is shown, put back when it is hidden; the value each profile had is remembered and kept across a
-- reload and a profile switch; a value the player chose in between is left alone; nothing is changed in combat; a
-- Spec Override is left alone; turning the feature off puts everything back; off by default; works only with both
-- RestedXP and EllesmereUI's Quest Tracker.
-- RestedXP is simulated from v4.11.22 (SettingsPanel.lua, ToggleActive and its field). EllesmereUI's quest tracker
-- is simulated from EllesmereUIQuestTracker (the questTracker table, its live settings _EQT_DB, and visibility as
-- EllesmereUI_Visibility.lua reads it) and EllesmereUI's RequestVisibilityUpdate / RefreshAllAddons. The same fields
-- and functions, not the game.
dofile(TESTS .. "harness.lua")

-- The saved data a client keeps between sessions: the same tables are handed to the next client (a reload).
local function World(o)
  o = o or {}
  local profiles = {}
  for name, vis in pairs(o.profiles or { Default = "always" }) do
    profiles[name] = { addons = { EllesmereUIQuestTracker = { questTracker = { visibility = vis, visHideMounted = false } } } }
  end
  return {
    db = { modules = { qolGuideTracker = o.on ~= false } },
    eui = { activeProfile = o.active or "Default", profiles = profiles },
    rx = { showEnabled = o.shown ~= false },
  }
end

local function Active(w) return w.eui.profiles[w.eui.activeProfile].addons.EllesmereUIQuestTracker end
local function Cfg(w, name) return w.eui.profiles[name].addons.EllesmereUIQuestTracker.questTracker end
local function Vis(w, name) return Cfg(w, name).visibility end
local function Record(w) return w.db.ui and w.db.ui.guideTracker or {} end
local function Empty(t) return next(t) == nil end

-- One run of the game. o.noRestedXP / o.noTracker leave that addon out; o.noLive leaves EllesmereUI's live settings unset.
local function Client(w, o)
  o = o or {}
  local addons = { "!!!TwichUI" }
  if not o.noRestedXP then addons[#addons + 1] = "RXPGuides" end
  if not o.noTracker then addons[#addons + 1] = "EllesmereUIQuestTracker" end
  local c = MakeClient("Rich", addons)
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
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
  c.TwichUIDB = w.db
  c.EllesmereUIDB = w.eui
  c.visRefreshes = 0
  c.EllesmereUI = {
    RefreshAllAddons = function() end,
    RequestVisibilityUpdate = function() c.visRefreshes = c.visRefreshes + 1 end,
    VisOverrideValue = function(store)
      local v = store.visibilityOverride
      if v == "never" or v == "always" or v == "mouseover" then return v end
    end,
  }
  if not o.noTracker then c.EllesmereUIQuestTracker = {} end
  if not o.noLive and not o.noTracker then c._EQT_DB = { profile = Active(w) } end
  for _, f in ipairs({ "qol/QoL.lua", "qol/GuideTracker.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if not o.noRestedXP then
    local rxp = { settings = { profile = w.rx }, toggles = 0 }
    function rxp.settings.ToggleActive()
      rxp.toggles = rxp.toggles + 1
      rxp.settings.profile.showEnabled = not rxp.settings.profile.showEnabled
    end
    function rxp.settings:RefreshProfile() end
    local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
    function ace:GetAddon(name) if name == "RXPGuides" then return rxp end end
    c.LOADED["RXPGuides"] = true
    c.rxp = rxp
  end
  return c
end

-- The game's start-up order: TwichUI first, then the other addons, then PLAYER_LOGIN.
local function Start(c)
  c.LOADED["!!!TwichUI"] = true
  c.LOADED["EllesmereUIQuestTracker"] = c.EllesmereUIQuestTracker ~= nil
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("ADDON_LOADED", "RXPGuides")
  c.FireEvent("ADDON_LOADED", "EllesmereUIQuestTracker")
  FlushTimers()
  c.FireEvent("PLAYER_LOGIN")
  FlushTimers()
  return c.TwichUI
end

-- EllesmereUI switches profiles: its live settings follow, and its profile refresh runs.
local function SwitchProfile(c, w, name)
  w.eui.activeProfile = name
  c._EQT_DB.profile = Active(w)
  c.EllesmereUI.RefreshAllAddons()
end

---------------------------------------------------------------------------
-- Off by default: nothing hooked, nothing written.
---------------------------------------------------------------------------
do
  local w = World{ on = false }
  local c = Client(w)
  local R = Start(c)
  assert(R.DEFAULT_MODULES.qolGuideTracker == false and R:Enabled("qolGuideTracker") == false, "opt-in")
  assert(c.hookCount == 0, "nothing hooked while off")
  assert(R.QoLGuideTracker.Status() == "off")
  c.rxp.settings.ToggleActive()
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "nothing written while off")
end

---------------------------------------------------------------------------
-- On, but one of the two addons is not here: neutral, nothing hooked.
---------------------------------------------------------------------------
do
  local w = World()
  local c = Client(w, { noTracker = true })
  local R = Start(c)
  assert(c.hookCount == 0, "nothing hooked without EllesmereUI's tracker")
  assert(R.QoLGuideTracker.Status() == "ellesmere-missing", R.QoLGuideTracker.Status())
  c.rxp.settings.ToggleActive()
  assert(Empty(Record(w)) and Vis(w, "Default") == "always")

  local w2 = World()
  local c2 = Client(w2, { noRestedXP = true })
  local R2 = Start(c2)
  assert(c2.hookCount == 0 and R2.QoLGuideTracker.Status() == "restedxp-missing", R2.QoLGuideTracker.Status())
  assert(Vis(w2, "Default") == "always" and Empty(Record(w2)))
end

---------------------------------------------------------------------------
-- Shown at login: Mouseover, the set left in place. Hidden: put back. Shown again: Mouseover again. Hooked once.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "in_combat" } }
  local modes = { in_combat = true, in_raid = true }
  Cfg(w, "Default").visibilityModes = modes
  local c = Client(w)
  local R = Start(c)
  assert(c.hookCount == 3, "ToggleActive, RefreshProfile and RefreshAllAddons, once: " .. c.hookCount)
  assert(Vis(w, "Default") == "mouseover", "Mouseover while the guide is shown")
  assert(Cfg(w, "Default").visibilityModes == modes and modes.in_raid, "EllesmereUI's set is left in place")
  assert(Record(w).Default == "in_combat", "the value before is remembered")
  assert(R.QoLGuideTracker.Status() == "held", R.QoLGuideTracker.Status())
  assert(c.visRefreshes > 0, "EllesmereUI is told to apply it")

  c.rxp.settings.ToggleActive()   -- hidden
  assert(Vis(w, "Default") == "in_combat", "put back when hidden")
  assert(Empty(Record(w)), "nothing remembered once put back")
  assert(R.QoLGuideTracker.Status() == "watching", R.QoLGuideTracker.Status())
  assert(Cfg(w, "Default").visibilityModes == modes, "the set is untouched")

  c.rxp.settings.ToggleActive()   -- shown again
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "in_combat", "Mouseover again when shown")
  assert(c.hookCount == 3, "no more hooks")
end

---------------------------------------------------------------------------
-- Already on Mouseover: nothing remembered and nothing put back.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "mouseover" } }
  local c = Client(w)
  local R = Start(c)
  assert(R.QoLGuideTracker.Status() == "already-mouseover", R.QoLGuideTracker.Status())
  assert(Empty(Record(w)), "nothing remembered")
  c.rxp.settings.ToggleActive()
  assert(Vis(w, "Default") == "mouseover", "the player's Mouseover is left alone")
end

---------------------------------------------------------------------------
-- A reload while the guide is shown keeps the first value remembered; a reload while it is hidden puts it back.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always" } }
  local c1 = Client(w)
  Start(c1)
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always")

  local c2 = Client(w)                      -- the game is reloaded; the guide is still shown
  local R2 = Start(c2)
  assert(Vis(w, "Default") == "mouseover", "still Mouseover after a reload")
  assert(Record(w).Default == "always", "the first value is kept")
  assert(R2.QoLGuideTracker.Status() == "held", R2.QoLGuideTracker.Status())
  c2.rxp.settings.ToggleActive()            -- hidden
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "put back after a reload")

  -- the player changed it while held, then the game reloaded with the guide still shown: set again, and the
  -- value from before the first hold is what comes back, not the one the player chose in between
  local w3 = World{ profiles = { Default = "always" } }
  Start(Client(w3))
  Cfg(w3, "Default").visibility = "in_raid"
  local c4 = Client(w3)
  Start(c4)
  assert(Vis(w3, "Default") == "mouseover" and Record(w3).Default == "always", "set again after a reload")
  c4.rxp.settings.ToggleActive()            -- hidden
  assert(Vis(w3, "Default") == "always" and Empty(Record(w3)), "the value from before the first hold comes back")

  local w2 = World{ profiles = { Default = "always" } }
  Start(Client(w2))
  w2.rx.showEnabled = false                 -- hidden while the game was closed
  local c3 = Client(w2)
  Start(c3)
  assert(Vis(w2, "Default") == "always" and Empty(Record(w2)), "a reload with the guide hidden puts it back")
end

---------------------------------------------------------------------------
-- The player changes the tracker's Visibility while the guide is shown: their choice is kept until the next
-- time the guide is shown or hidden.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always" } }
  local c = Client(w)
  Start(c)
  Cfg(w, "Default").visibility = "in_raid"  -- changed in EllesmereUI's options
  c.rxp.settings.ToggleActive()             -- hidden
  assert(Vis(w, "Default") == "in_raid", "the player's choice is kept")
  assert(Empty(Record(w)), "the record goes")
end

---------------------------------------------------------------------------
-- In combat the change waits for combat to end, both ways.
---------------------------------------------------------------------------
do
  local w = World{ shown = false, profiles = { Default = "always" } }
  local c = Client(w)
  Start(c)
  c.COMBAT = true
  c.rxp.settings.ToggleActive()             -- shown, in combat
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "nothing changed in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always", "set when combat ends")

  c.COMBAT = true
  c.rxp.settings.ToggleActive()             -- hidden, in combat
  assert(Vis(w, "Default") == "mouseover", "put back only when combat ends")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "put back when combat ends")
end

---------------------------------------------------------------------------
-- A profile switch puts the changed profile back and changes the new one if the guide is shown.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always", Other = "solo" } }
  local c = Client(w)
  Start(c)
  assert(Vis(w, "Default") == "mouseover")
  SwitchProfile(c, w, "Other")
  assert(Vis(w, "Default") == "always", "the profile that was changed is put back")
  assert(Vis(w, "Other") == "mouseover", "the new profile is set while the guide is shown")
  assert(Record(w).Other == "solo" and Record(w).Default == nil, "the record follows the profile")

  SwitchProfile(c, w, "Default")
  assert(Vis(w, "Other") == "solo", "Other is put back when left")
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always" and Record(w).Other == nil)
end

-- A profile switch while the guide is hidden changes nothing.
do
  local w = World{ shown = false, profiles = { Default = "always", Other = "solo" } }
  local c = Client(w)
  Start(c)
  SwitchProfile(c, w, "Other")
  assert(Vis(w, "Other") == "solo" and Empty(Record(w)), "a hidden guide sets nothing on a profile switch")
end

---------------------------------------------------------------------------
-- EllesmereUI's Spec Override holds the tracker's Visibility: left alone.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always" } }
  Active(w).questTracker.visibilityOverride = "never"
  local c = Client(w)
  local R = Start(c)
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "an override is not changed")
  assert(R.QoLGuideTracker.Status() == "overridden", R.QoLGuideTracker.Status())
  c.rxp.settings.ToggleActive()
  assert(Vis(w, "Default") == "always" and Empty(Record(w)) and Active(w).questTracker.visibilityOverride == "never")
end

---------------------------------------------------------------------------
-- Turning the feature off while it holds the tracker puts it back; turning it on with the guide shown sets it.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always" } }
  local c = Client(w)
  local R = Start(c)
  assert(Vis(w, "Default") == "mouseover")
  R:SetEnabled("qolGuideTracker", false); FlushTimers()
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "turned off: put back")
  c.rxp.settings.ToggleActive()             -- hidden, then shown, while off
  c.rxp.settings.ToggleActive()
  assert(Vis(w, "Default") == "always", "nothing changes while off")
  R:SetEnabled("qolGuideTracker", true); FlushTimers()
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always", "turned on with the guide shown: set")
end

do
  local w = World{ on = false, profiles = { Default = "always" } }
  local c = Client(w)
  local R = Start(c)
  assert(Vis(w, "Default") == "always")
  R:SetEnabled("qolGuideTracker", true); FlushTimers()
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always", "turned on mid-session: set")
end

---------------------------------------------------------------------------
-- EllesmereUI's settings not ready at login: looks again a few times, then sets it.
---------------------------------------------------------------------------
do
  local w = World{ profiles = { Default = "always" } }
  local c = Client(w, { noLive = true })
  local R = Start(c)
  assert(Vis(w, "Default") == "always" and Empty(Record(w)), "waits for EllesmereUI's settings")
  assert(R.QoLGuideTracker.Status() == "waiting", R.QoLGuideTracker.Status())
  c._EQT_DB = { profile = Active(w) }
  FlushTimers(); FlushTimers()
  assert(Vis(w, "Default") == "mouseover" and Record(w).Default == "always", "set once EllesmereUI is ready")
end

print("OK test_guide_tracker")
