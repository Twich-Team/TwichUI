dofile(TESTS .. "harness.lua")
-- Zone arrival card: what counts as an arrival (not login or reload, not in flight,
-- only the last of quick crossings, no repeats), subzones only when chosen, the game's
-- zone text hidden only while on, and the card's animation set up and cleaned up.
local c = MakeClient("Rich", {"!!!TwichUI"})

-- Frames with just enough behaviour to follow the card.
local groups, translations, alphas = {}, {}, {}
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks = false, {}, {}
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true; if s.hooks.OnShow then s.hooks.OnShow(s) end end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetFont" then return function() return true end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({owner = s, plays = 0})
      g.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function(_, kind)
        local a = Fake({kind = kind})
        a.SetOffset = function(self, x, y) self.y = y end
        a.SetStartDelay = function(self, d) self.delay = d end
        if kind == "Translation" then table.insert(translations, a) end
        if kind == "Alpha" then table.insert(alphas, a) end
        return a
      end
      table.insert(groups, g)
      return g
    end end
    return function() end
  end})
end
c.CreateFrame = function() return Fake() end
c.UIParent = Fake()

c.NOW = 100
c.GetTime = function() return c.NOW end
c.ZONE, c.SUB, c.TAXI, c.TOAST = "Elwynn Forest", "Northshire Valley", false, false
c.GetZoneText = function() return c.ZONE end
c.GetSubZoneText = function() return c.SUB end
c.UnitOnTaxi = function() return c.TAXI end
c.PVP = "friendly"
c.C_PvP = {GetZonePVPInfo = function() return c.PVP, false, "Alliance" end}
c.FACTION_CONTROLLED_TERRITORY = "(%s Territory)"
c.CONTESTED_TERRITORY = "(Contested Territory)"
c.ZoneTextFrame, c.SubZoneTextFrame = Fake(), Fake()
c.EventToastManagerFrame = Fake()
c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end
c.ZoneText_Clear = function() end
local secureHooks = {}
c.hooksecurefunc = function(name, fn) secureHooks[name] = fn end

local chunk = assert(loadfile(ROOT .. "modules/Arrival.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R, A = c.TwichUI, c.TwichUI.Arrival
local M = c.TwichUIDB.modules
assert(M.arrival == true and M.arrivalSubzones == true and M.arrivalReducedMotion == false, "defaults")

local shows = {}
local show = A.Show
A.Show = function(kind, title, sub, pvpText, pvpType)
  table.insert(shows, {kind = kind, title = title, sub = sub, pvp = pvpText})
  return show(kind, title, sub, pvpText, pvpType)
end
local function Last() return shows[#shows] end
local function Arrive(zone, sub, event)
  c.ZONE, c.SUB = zone, sub or ""
  c.FireEvent(event or "ZONE_CHANGED_NEW_AREA")
end

-- login: the starting place isn't an arrival, even when its zone event comes late
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
Arrive("Elwynn Forest", "Northshire Valley"); FlushTimers()
c.NOW = 102; Arrive("Elwynn Forest", "Goldshire"); FlushTimers()
Arrive("Elwynn Forest", "Northshire Abbey", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 0, "nothing at login")
-- reload too
c.NOW = 200; c.FireEvent("PLAYER_ENTERING_WORLD", false, true)
Arrive("Elwynn Forest"); FlushTimers()
assert(#shows == 0, "nothing at reload")
c.NOW = 300

-- a real arrival: zone, smaller place and PvP line from the game
Arrive("Westfall", "Sentinel Hill"); FlushTimers()
assert(#shows == 1 and Last().kind == "zone" and Last().title == "Westfall" and Last().sub == "Sentinel Hill", "arrival shown")
assert(Last().pvp == "(Alliance Territory)", "PvP line from the game's string")
local card = groups[1].owner
assert(card.shown and groups[1].playing and groups[1].plays == 1, "card shown and animating")
assert(translations[1].y == -8 and translations[2].y == 8, "settles upward, ending where it is anchored")
-- the same zone again: nothing
Arrive("Westfall", "Sentinel Hill"); FlushTimers()
assert(#shows == 1, "no repeats")
-- smaller places are on by default: a quieter card
Arrive("Westfall", "Moonbrook", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 2 and Last().kind == "subzone" and Last().title == "Moonbrook", "subzone cards by default")
-- turned off: moving within a zone shows nothing
M.arrivalSubzones = false; A.Refresh()
Arrive("Westfall", "Sentinel Hill", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 2, "no subzone cards when off")
-- the animation finishing hides the card
groups[1].scripts.OnFinished(groups[1])
assert(not card.shown, "hidden once faded")

-- quick crossings: only the last place, once
Arrive("Duskwood"); Arrive("Redridge Mountains", "Lakeshire"); FlushTimers()
assert(#shows == 3 and Last().title == "Redridge Mountains", "only the latest of quick crossings")
-- a zone with no subzone, or one named like the zone, has no second line
Arrive("Duskwood", "Duskwood"); FlushTimers()
assert(#shows == 4 and Last().sub == nil, "no subzone line")
-- a new arrival restarts the card cleanly
assert(groups[1].plays == 4 and #groups == 1, "one card, replayed")

-- flight: nothing while flying, where you land once
c.FireEvent("PLAYER_CONTROL_LOST")
Arrive("Elwynn Forest"); Arrive("Westfall"); Arrive("Stranglethorn Vale")
FlushTimers()
assert(#shows == 4, "nothing in flight")
c.FireEvent("PLAYER_CONTROL_GAINED"); FlushTimers()
assert(#shows == 5 and Last().title == "Stranglethorn Vale", "landing shows where you land")
c.FireEvent("PLAYER_CONTROL_GAINED"); FlushTimers()
assert(#shows == 5, "landing twice isn't arriving twice")
-- a check already waiting when the flight starts is dropped
Arrive("Duskwood"); c.FireEvent("PLAYER_CONTROL_LOST"); FlushTimers()
assert(#shows == 5, "takeoff drops a waiting check")
c.FireEvent("PLAYER_CONTROL_GAINED"); FlushTimers()
assert(#shows == 6 and Last().title == "Duskwood")
c.TAXI = true; Arrive("Westfall"); FlushTimers()
assert(#shows == 6, "UnitOnTaxi alone also suppresses")
c.TAXI = false

-- a loading screen (dungeon, hearthstone) is an arrival; leaving the world hides the card
c.FireEvent("PLAYER_LEAVING_WORLD")
assert(not card.shown and not groups[1].playing, "hidden on leaving the world")
c.ZONE = "The Deadmines"; c.FireEvent("PLAYER_ENTERING_WORLD", false, false); c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
assert(#shows == 7 and Last().title == "The Deadmines", "entering a dungeon shows once")

-- an event toast showing: nothing now, and the place isn't shown later either
c.TOAST = true; Arrive("Westfall"); FlushTimers(); c.TOAST = false
assert(#shows == 7, "no card over a toast")
Arrive("Westfall"); FlushTimers()
assert(#shows == 7, "not shown late")
A.Show("zone", "Westfall"); c.EventToastManagerFrame:Show()
assert(not card.shown, "makes way for a toast")
A.Show("zone", "Westfall"); secureHooks.ZoneText_Clear()
assert(not card.shown, "makes way for other top banners")

-- subzones when chosen: quieter card, PvP line only when it changed
M.arrivalSubzones = true; A.Refresh()
Arrive("Westfall", "Moonbrook", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 10 and Last().kind == "subzone" and Last().title == "Moonbrook" and Last().pvp == nil, "subzone card")
c.PVP = "contested"; Arrive("Westfall", "The Dagger Hills", "ZONE_CHANGED_INDOORS"); FlushTimers()
assert(#shows == 11 and Last().pvp == "(Contested Territory)", "PvP change shown on a subzone card")
Arrive("Westfall", "", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 11, "leaving a subzone shows nothing")
M.arrivalSubzones = false; A.Refresh()
Arrive("Westfall", "Moonbrook", "ZONE_CHANGED"); FlushTimers()
assert(#shows == 11, "subzones off again")

-- reduced motion: fade only
M.arrivalReducedMotion = true
Arrive("Elwynn Forest"); FlushTimers()
assert(#shows == 12 and translations[1].y == 0 and translations[2].y == 0, "no movement with reduced motion")

-- how long the card stays: standard by default, the chosen length, a little shorter for subzones
local fadeOut = alphas[2]
assert(fadeOut.delay == 2.2, "standard hold")
c.TwichUIDB.ui = {arrivalHold = "long"}
Arrive("Westfall"); FlushTimers()
assert(#shows == 13 and fadeOut.delay == 4, "chosen hold")
A.Show("subzone", "Moonbrook"); assert(fadeOut.delay == 3.2, "subzone a little shorter")
c.TwichUIDB.ui.arrivalHold = "brief"; A.Show("subzone", "Moonbrook"); assert(fadeOut.delay == 1, "never under a second")
c.TwichUIDB.ui.arrivalHold = "bogus"; A.Show("zone", "Westfall"); assert(fadeOut.delay == 2.2, "unknown value: standard")
assert(A.HoldChoice() == "standard")
c.TwichUIDB.ui.arrivalHold = nil
shows = {}

-- the game's zone text: hidden while on, left alone while off
c.ZoneTextFrame:Show(); c.SubZoneTextFrame:Show()
assert(not c.ZoneTextFrame.shown and not c.SubZoneTextFrame.shown, "native zone text hidden while on")
M.arrival = false; A.Refresh()
assert(not card.shown, "turning off hides the card")
c.ZoneTextFrame:Show(); c.SubZoneTextFrame:Show()
assert(c.ZoneTextFrame.shown and c.SubZoneTextFrame.shown, "native zone text back while off")
Arrive("Duskwood"); FlushTimers()
c.FireEvent("PLAYER_CONTROL_GAINED"); FlushTimers()
assert(#shows == 0, "nothing while off")
-- turned on again: where you are isn't an arrival
M.arrival = true; A.Refresh(); FlushTimers()
Arrive("Duskwood"); FlushTimers()
assert(#shows == 0, "turning on doesn't announce where you are")
Arrive("Westfall"); FlushTimers()
assert(#shows == 1, "and works again")

print("ARRIVAL TESTS PASSED")
