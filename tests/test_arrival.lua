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
-- Instances: INST is nil outside, or {type, name} inside. NAME_AFTER makes the name appear only after that many looks.
c.INST, c.NAME_AFTER, c.LOOKS = nil, 0, 0
c.IsInInstance = function() if c.INST then return true, c.INST.type end return false, "none" end
c.GetInstanceInfo = function()
  c.LOOKS = c.LOOKS + 1
  if not c.INST then return "Elwynn Forest", "none" end
  return c.LOOKS > c.NAME_AFTER and c.INST.name or "", c.INST.type
end
c.LFG_TYPE_DUNGEON, c.LFG_TYPE_RAID = "Dungeon", "Raid"
local secureHooks = {}
c.hooksecurefunc = function(name, fn) secureHooks[name] = fn end

for _, f in ipairs({"modules/Notify.lua", "modules/Arrival.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
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

-- dungeon and raid entry cards ------------------------------------------------
assert(M.arrivalDungeons == true, "dungeon cards on by default")
shows = {}
local function Enter(kind, name, zone, afterLooks)
  c.INST = {type = kind, name = name}; c.NAME_AFTER = afterLooks or 0; c.LOOKS = 0
  c.ZONE, c.SUB = zone or name, ""
  c.FireEvent("PLAYER_LEAVING_WORLD")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  c.FireEvent("ZONE_CHANGED_NEW_AREA")
  for _ = 1, 4 do FlushTimers() end   -- a look that finds no name schedules the next one
end
local function Leave(zone)
  c.INST = nil; c.ZONE, c.SUB = zone, ""
  c.FireEvent("PLAYER_LEAVING_WORLD")
  c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  c.FireEvent("ZONE_CHANGED_NEW_AREA")
  FlushTimers()
end

-- walking into a dungeon: one card, its name, the game's word for it, no PvP line
Enter("party", "The Deadmines")
assert(#shows == 1 and Last().kind == "zone" and Last().title == "The Deadmines" and Last().sub == "Dungeon" and Last().pvp == nil,
  "dungeon entry: one card with the name and \"Dungeon\"")
-- internal changes, repeated loading screens and group changes inside: nothing more
c.FireEvent("PLAYER_ENTERING_WORLD", false, false); c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
c.FireEvent("ZONE_CHANGED_NEW_AREA"); c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
assert(#shows == 1, "no second card inside")
-- leaving: the ordinary zone card, unchanged
Leave("Westfall")
assert(#shows == 2 and Last().title == "Westfall" and Last().sub == nil, "leaving shows the zone as before")
-- a raid
Enter("raid", "Molten Core")
assert(#shows == 3 and Last().title == "Molten Core" and Last().sub == "Raid", "raid entry")
Leave("Burning Steppe")
assert(#shows == 4, "leaving the raid: the zone")
-- battlegrounds, arenas and scenarios aren't dungeons: the ordinary zone card
Enter("pvp", "Warsong Gulch")
assert(#shows == 5 and Last().title == "Warsong Gulch" and Last().sub == nil, "other instances keep the zone card")
Leave("Ashenvale")
shows = {}

-- the game's zone text catches up after the card: the same arrival, not a second card replacing it
c.INST = {type = "party", name = "Ruins of Lordaeron"}; c.NAME_AFTER = 0; c.LOOKS = 0
c.ZONE, c.SUB = "Tirisfal Glades", ""     -- still the outside zone when the check runs
c.FireEvent("PLAYER_LEAVING_WORLD"); c.FireEvent("PLAYER_ENTERING_WORLD", false, false); FlushTimers()
assert(#shows == 1 and Last().title == "Ruins of Lordaeron" and Last().sub == "Dungeon", "card at entry")
c.ZONE, c.SUB = "Ruins of Lordaeron", "The Ruined Hall"
c.FireEvent("ZONE_CHANGED_NEW_AREA"); c.FireEvent("ZONE_CHANGED"); FlushTimers()
assert(#shows == 1, "zone text catching up doesn't replace the dungeon card")
-- a real move within it afterwards is the ordinary subzone card, as before
M.arrivalSubzones = true; A.Refresh()
c.SUB = "The Crypt"; c.FireEvent("ZONE_CHANGED"); FlushTimers()
assert(#shows == 2 and Last().kind == "subzone", "later moves inside are unchanged")
M.arrivalSubzones = false; A.Refresh()
Leave("Tirisfal Glades"); shows = {}

-- the name arrives a little late: looked for again, still one card
Enter("party", "Shadowfang Keep", nil, 1)
assert(#shows == 1 and Last().title == "Shadowfang Keep" and Last().sub == "Dungeon", "late name waited for")
Leave("Silverpine Forest"); shows = {}
-- the name never comes: the ordinary zone card, never an empty title
Enter("party", "Wailing Caverns", nil, 99)
assert(#shows == 1 and Last().title == "Wailing Caverns" and Last().sub == nil, "unresolved name falls back to the zone card")
Leave("The Barrens"); shows = {}
-- nothing usable at all: nothing, and no empty title
c.INST = {type = "party", name = ""}; c.NAME_AFTER = 0; c.ZONE = ""
c.FireEvent("PLAYER_ENTERING_WORLD", false, false); FlushTimers()
assert(#shows == 0, "no card without any name")
Leave("The Barrens"); shows = {}

-- reload inside a dungeon: no arrival, and it stays quiet afterwards
c.NOW = c.NOW + 100
c.INST = {type = "party", name = "Gnomeregan"}; c.NAME_AFTER = 0; c.ZONE = "Gnomeregan"
c.FireEvent("PLAYER_ENTERING_WORLD", false, true)
c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
c.NOW = c.NOW + 10
c.FireEvent("PLAYER_ENTERING_WORLD", false, false); c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
assert(#shows == 0, "nothing at reload inside a dungeon, nor on later internal loading screens")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
assert(#shows == 0, "nor at login inside one")
c.NOW = c.NOW + 10   -- past the login quiet time
Leave("Dun Morogh"); shows = {}

-- dungeon cards off: the ordinary zone card, and the zone's own place is still tracked
M.arrivalDungeons = false; A.Refresh()
Enter("party", "Blackfathom Deeps")
assert(#shows == 1 and Last().title == "Blackfathom Deeps" and Last().sub == nil, "off: the ordinary zone card")
-- switched on while inside: where you are isn't an entry
M.arrivalDungeons = true; A.Refresh()
c.FireEvent("PLAYER_ENTERING_WORLD", false, false); c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
assert(#shows == 1, "turning dungeon cards on inside one shows nothing")
Leave("Ashenvale"); shows = {}

-- the whole feature off: no dungeon card either
M.arrival = false; A.Refresh()
Enter("party", "The Stockade")
assert(#shows == 0, "nothing while Zone arrival is off")
M.arrival = true; A.Refresh(); FlushTimers()
assert(#shows == 0, "and turning it on inside doesn't announce")
Leave("Stormwind City"); shows = {}

-- reduced motion and the chosen hold apply to the dungeon card
M.arrivalReducedMotion = true
Enter("party", "Razorfen Kraul")
assert(#shows == 1 and translations[1].y == 0 and translations[2].y == 0, "reduced motion")
Leave("The Barrens")
M.arrivalReducedMotion = false; c.TwichUIDB.ui = {arrivalHold = "long"}
Enter("raid", "Onyxia's Lair")
assert(alphas[2].delay == 4 and translations[2].y == 8, "chosen hold; settles upward")
-- a toast in progress: no card, and it isn't shown late
Leave("Dustwallow Marsh"); shows = {}
c.TOAST = true; Enter("party", "Ragefire Chasm"); c.TOAST = false
assert(#shows == 0, "no dungeon card over a toast")
c.FireEvent("ZONE_CHANGED_NEW_AREA"); FlushTimers()
assert(#shows == 0, "not shown late")

print("ARRIVAL TESTS PASSED")
