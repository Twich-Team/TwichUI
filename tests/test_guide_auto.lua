-- RestedXP guide shown and hidden by situation (qol/GuideAutoHide.lua): off by default and silent when off;
-- works without RestedXP; hides when a chosen situation begins and shows again when the last one ends; only
-- shows a guide it hid itself; a toggle made by the player in between is left alone; nothing is changed in
-- combat; turning it off or dropping the situation shows the guide again; after a reload the guide still comes
-- back; only the events the chosen situations need are listened to.
-- RestedXP is simulated from the source of v4.11.22 (SettingsPanel.lua ToggleActive): the same field and the
-- same hooked functions, not the game.
dofile(TESTS .. "harness.lua")

local function Boot(opts)
  opts = opts or {}
  local addons = { "!!!TwichUI" }
  for _, a in ipairs(opts.addons or {}) do addons[#addons + 1] = a end
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
  -- where the player is
  c.WHERE = { instance = false, kind = "none", group = false, resting = false, taxi = false }
  c.IsInInstance = function() return c.WHERE.instance, c.WHERE.kind end
  c.IsInGroup = function() return c.WHERE.group end
  c.IsResting = function() return c.WHERE.resting end
  c.UnitOnTaxi = function() return c.WHERE.taxi end
  c.TwichUIDB = opts.db or { modules = {} }
  for _, f in ipairs({ "qol/QoL.lua", "qol/GuideAutoHide.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  return c
end

local function Start(c)
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  FlushTimers()
  return c.TwichUI
end

local function MakeRestedXP(c, opts)
  opts = opts or {}
  local rxp = { settings = { profile = { showEnabled = true } }, toggles = 0 }
  function rxp.settings.ToggleActive()
    rxp.toggles = rxp.toggles + 1
    rxp.settings.profile.showEnabled = not rxp.settings.profile.showEnabled
  end
  function rxp.settings:RefreshProfile() end
  if opts.broken then rxp.settings.ToggleActive = nil end
  local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
  function ace:GetAddon(name) if name == "RXPGuides" then return rxp end end
  c.LOADED["RXPGuides"] = true
  return rxp
end

local function RestedXPLoads(c)
  c.FireEvent("ADDON_LOADED", "RXPGuides")
  FlushTimers()
end

local function On(c, key) return c.TwichUI:Enabled(key) end
local function Shown(rxp) return rxp.settings.profile.showEnabled end

-- A running client with RestedXP, the feature on, and the switches given (the rest at their defaults).
local function Running(switches, db)
  local modules = { qolGuideAuto = true }
  for k, v in pairs(switches or {}) do modules[k] = v end
  local c = Boot({ addons = { "RXPGuides" }, db = db or { modules = modules } })
  local R = Start(c)
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  return c, R, rxp
end

local function Enter(c, kind) c.WHERE.instance, c.WHERE.kind = true, kind; c.FireEvent("PLAYER_ENTERING_WORLD") end
local function Leave(c) c.WHERE.instance, c.WHERE.kind = false, "none"; c.FireEvent("PLAYER_ENTERING_WORLD") end

---------------------------------------------------------------------------
-- Off by default: nothing hooked, nothing toggled, no events.
---------------------------------------------------------------------------
do
  local c = Boot({ addons = { "RXPGuides" } })
  local R = Start(c)
  assert(R.DEFAULT_MODULES.qolGuideAuto == false and R:Enabled("qolGuideAuto") == false, "opt-in")
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  assert(c.hookCount == 0, "nothing hooked while off")
  Enter(c, "party")
  assert(rxp.toggles == 0 and Shown(rxp), "nothing toggled")
  assert(R.QoLGuideAuto.Status() == "off")
  -- the starting choices
  local d = R.DEFAULT_MODULES
  assert(d.qolGuideAutoDungeon and d.qolGuideAutoRaid and d.qolGuideAutoPvP, "dungeon, raid and battleground start ticked")
  assert(d.qolGuideAutoGroup == false and d.qolGuideAutoResting == false and d.qolGuideAutoFlight == false, "the rest start unticked")
end

---------------------------------------------------------------------------
-- On, RestedXP not installed or not usable: neutral.
---------------------------------------------------------------------------
do
  local c = Boot({ db = { modules = { qolGuideAuto = true } } })
  local R = Start(c)
  Enter(c, "party")
  assert(R.QoLGuideAuto.Status() == "restedxp-missing", R.QoLGuideAuto.Status())
  assert(c.hookCount == 0)

  local c2 = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideAuto = true } } })
  local R2 = Start(c2)
  MakeRestedXP(c2, { broken = true })
  RestedXPLoads(c2)
  assert(c2.hookCount == 0 and R2.QoLGuideAuto.Status() == "unsupported", R2.QoLGuideAuto.Status())
end

---------------------------------------------------------------------------
-- A dungeon, a raid and a battleground: hidden on entering, shown on leaving. Hooked once.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running()
  local A = R.QoLGuideAuto
  assert(c.hookCount == 2, "ToggleActive and RefreshProfile, once")
  assert(A.Status() == "watching", A.Status())
  for _, kind in ipairs({ "party", "raid", "pvp", "arena" }) do
    rxp.toggles = 0
    Enter(c, kind)
    assert(not Shown(rxp) and rxp.toggles == 1, kind .. ": hidden once")
    assert(A.Status() == "hidden", A.Status())
    -- the same situation looked at again, and again: nothing more
    c.FireEvent("ZONE_CHANGED_NEW_AREA"); c.FireEvent("PLAYER_ENTERING_WORLD")
    assert(rxp.toggles == 1, kind .. ": no repeated toggles")
    Leave(c)
    assert(Shown(rxp) and rxp.toggles == 2, kind .. ": shown again")
    assert(A.Status() == "watching")
  end
  -- a scenario or the open world is none of them
  Enter(c, "scenario")
  assert(Shown(rxp), "a scenario is not a dungeon")
  Leave(c)
  assert(c.hookCount == 2, "no more hooks")
end

---------------------------------------------------------------------------
-- A situation not chosen does nothing; the events it needs are not even listened to.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running({ qolGuideAutoDungeon = false, qolGuideAutoRaid = false, qolGuideAutoPvP = false })
  -- instances are not chosen: entering one does nothing
  Enter(c, "party")
  assert(Shown(rxp) and rxp.toggles == 0, "dungeon not chosen")
  assert(R.QoLGuideAuto.Status() == "none-chosen", R.QoLGuideAuto.Status())
  -- group / resting / flight events do nothing either while their switch is off
  c.WHERE.group, c.WHERE.resting, c.WHERE.taxi = true, true, true
  c.FireEvent("GROUP_ROSTER_UPDATE"); c.FireEvent("PLAYER_UPDATE_RESTING"); c.FireEvent("PLAYER_CONTROL_LOST")
  assert(Shown(rxp) and rxp.toggles == 0)
  local active = R.QoLGuideAuto.feature.active
  assert(not active.GROUP_ROSTER_UPDATE and not active.PLAYER_UPDATE_RESTING and not active.PLAYER_CONTROL_LOST
    and not active.PLAYER_CONTROL_GAINED and not active.PLAYER_ENTERING_WORLD and not active.ZONE_CHANGED_NEW_AREA,
    "no events for situations not chosen")
end

---------------------------------------------------------------------------
-- Group, resting and flight.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running({ qolGuideAutoGroup = true, qolGuideAutoResting = true, qolGuideAutoFlight = true })
  local active = R.QoLGuideAuto.feature.active
  assert(active.GROUP_ROSTER_UPDATE and active.PLAYER_UPDATE_RESTING and active.PLAYER_CONTROL_LOST and active.PLAYER_CONTROL_GAINED)

  c.WHERE.group = true; c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(not Shown(rxp) and rxp.toggles == 1, "hidden in a group")
  -- a second situation while one is on: still one hide; it comes back only when the last one ends
  c.WHERE.resting = true; c.FireEvent("PLAYER_UPDATE_RESTING")
  assert(rxp.toggles == 1 and not Shown(rxp))
  c.WHERE.group = false; c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(not Shown(rxp) and rxp.toggles == 1, "still resting: stays hidden")
  c.WHERE.resting = false; c.FireEvent("PLAYER_UPDATE_RESTING")
  assert(Shown(rxp) and rxp.toggles == 2, "the last one ended: shown")

  -- a flight: the taxi flag may lag the control event, so it is looked at again a moment later
  c.FireEvent("PLAYER_CONTROL_LOST")
  assert(Shown(rxp), "not on the taxi yet")
  c.WHERE.taxi = true
  FlushTimers()
  assert(not Shown(rxp), "hidden once the flight is seen")
  c.WHERE.taxi = false
  c.FireEvent("PLAYER_CONTROL_GAINED")
  assert(Shown(rxp), "shown on landing")
  -- being stunned is a loss of control but not a flight
  c.FireEvent("PLAYER_CONTROL_LOST"); FlushTimers()
  assert(Shown(rxp) and rxp.toggles == 4, "a stun is not a flight")
end

---------------------------------------------------------------------------
-- The player's choice comes first.
---------------------------------------------------------------------------
do
  -- hidden before the situation: stays hidden after it
  local c, R, rxp = Running()
  rxp.settings.ToggleActive()                       -- the player hides it
  local before = rxp.toggles
  Enter(c, "party")
  assert(not Shown(rxp) and rxp.toggles == before, "already hidden: left alone")
  Leave(c)
  assert(not Shown(rxp) and rxp.toggles == before, "not ours to show")
  assert(not (c.TwichUIDB.ui and c.TwichUIDB.ui.guideAuto and c.TwichUIDB.ui.guideAuto["Player-1-Rich"]), "nothing remembered")
end
do
  -- shown by the player during the situation: not hidden again, and not toggled at the end
  local c, R, rxp = Running()
  Enter(c, "party")
  assert(not Shown(rxp))
  rxp.settings.ToggleActive()                       -- the player shows it
  assert(Shown(rxp))
  c.FireEvent("ZONE_CHANGED_NEW_AREA"); c.FireEvent("PLAYER_ENTERING_WORLD")
  assert(Shown(rxp), "not hidden again against the player")
  local n = rxp.toggles
  Leave(c)
  assert(Shown(rxp) and rxp.toggles == n, "nothing to put back")
  assert(not c.TwichUIDB.ui.guideAuto["Player-1-Rich"], "the record is gone")
  -- the next situation begins afresh
  Enter(c, "raid")
  assert(not Shown(rxp), "hidden again for the next one")
end
do
  -- hidden by the player during the situation (after we hid it, shown, hidden again): theirs
  local c, R, rxp = Running()
  Enter(c, "party")
  rxp.settings.ToggleActive(); rxp.settings.ToggleActive()   -- shown, then hidden by the player
  Leave(c)
  assert(not Shown(rxp), "the player hid it last: it stays hidden")
end

---------------------------------------------------------------------------
-- Nothing is changed in combat.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running()
  c.COMBAT = true
  Enter(c, "party")
  assert(Shown(rxp) and rxp.toggles == 0, "not in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(not Shown(rxp) and rxp.toggles == 1, "when combat ends")
  c.COMBAT = true
  Leave(c)
  assert(not Shown(rxp), "not shown in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(Shown(rxp) and rxp.toggles == 2)
end

---------------------------------------------------------------------------
-- Turning it off, or dropping the situation, puts back what it hid; and only that.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running()
  Enter(c, "party")
  assert(not Shown(rxp))
  R:SetEnabled("qolGuideAutoDungeon", false); FlushTimers()
  assert(Shown(rxp), "the situation was dropped while in it")
  R:SetEnabled("qolGuideAutoDungeon", true); FlushTimers()
  assert(not Shown(rxp), "ticked again while in it")
  R:SetEnabled("qolGuideAuto", false); FlushTimers()
  assert(Shown(rxp), "turned off: shown again")
  assert(R.QoLGuideAuto.Status() == "off")
  local n = rxp.toggles
  Leave(c); Enter(c, "raid"); Leave(c)
  assert(rxp.toggles == n, "silent while off")
end
do
  -- turned off in combat: shown when it ends
  local c, R, rxp = Running()
  Enter(c, "party")
  c.COMBAT = true
  R:SetEnabled("qolGuideAuto", false); FlushTimers()
  assert(not Shown(rxp), "not in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(Shown(rxp), "when combat ends")
  -- turned off while the player had hidden it themselves: not touched
  local c2, R2, rxp2 = Running()
  rxp2.settings.ToggleActive()
  Enter(c2, "party")
  R2:SetEnabled("qolGuideAuto", false); FlushTimers()
  assert(not Shown(rxp2), "the player's own hiding is left")
end
do
  -- turned on while already in a dungeon
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = {} } })
  local R = Start(c)
  local rxp = MakeRestedXP(c); RestedXPLoads(c)
  Enter(c, "party")
  assert(Shown(rxp))
  R:SetEnabled("qolGuideAuto", true); FlushTimers()
  assert(not Shown(rxp), "turned on inside a dungeon")
end

---------------------------------------------------------------------------
-- After a reload: still in a dungeon, then out; the guide comes back.
---------------------------------------------------------------------------
do
  local db = { modules = { qolGuideAuto = true } }
  local c = Boot({ addons = { "RXPGuides" }, db = db })
  c.WHERE.instance, c.WHERE.kind = true, "party"
  local R = Start(c)
  local rxp = MakeRestedXP(c); RestedXPLoads(c)
  assert(not Shown(rxp), "hidden at login in a dungeon")
  assert(db.ui.guideAuto["Player-1-Rich"] == true, "remembered")
  local savedShow = rxp.settings.profile.showEnabled   -- RestedXP saves its own setting

  -- reload: a new client, the same saved data (ours and RestedXP's), still inside
  local c2 = Boot({ addons = { "RXPGuides" }, db = db })
  c2.WHERE.instance, c2.WHERE.kind = true, "party"
  local R2 = Start(c2)
  local rxp2 = MakeRestedXP(c2); rxp2.settings.profile.showEnabled = savedShow
  RestedXPLoads(c2)
  assert(not Shown(rxp2) and rxp2.toggles == 0, "still hidden, not toggled twice")
  Leave(c2)
  assert(Shown(rxp2) and rxp2.toggles == 1, "back after the reload")
  assert(db.ui.guideAuto["Player-1-Rich"] == nil, "forgotten")

  -- reload while out in the world with the record left (leaving happened with the feature unable to act)
  db.ui.guideAuto["Player-1-Rich"] = true
  local c3 = Boot({ addons = { "RXPGuides" }, db = db })
  local R3 = Start(c3)
  local rxp3 = MakeRestedXP(c3); rxp3.settings.profile.showEnabled = false
  RestedXPLoads(c3)
  assert(Shown(rxp3), "a record and no situation: shown at login")
end

---------------------------------------------------------------------------
-- A RestedXP profile change: the new profile's own state is respected.
---------------------------------------------------------------------------
do
  local c, R, rxp = Running()
  Enter(c, "party")
  assert(not Shown(rxp))
  rxp.settings.profile.showEnabled = true            -- the other profile shows the guide
  rxp.settings:RefreshProfile()
  assert(not Shown(rxp), "still in a dungeon: hidden for the new profile")
  Leave(c)
  assert(Shown(rxp))
end

print("OK test_guide_auto")
