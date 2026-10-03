dofile(TESTS .. "harness.lua")
-- Welcome Back bookmark: what it says and how long ago, shown only at a real login (not a
-- reload or another loading screen) once things have settled, kept out of the way of combat,
-- flight and the zone card, dismissed and timed out cleanly, off when switched off, and
-- never writing to the Chronicle.
local c = MakeClient("Rich", {"!!!TwichUI"})

local groups = {}
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks = false, {}, {}
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({owner = s, plays = 0})
      g.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function(_, kind)
        local a = Fake({kind = kind})
        a.SetOffset = function(self, x, y) self.y = y end
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

c.NOW = 1700000000
c.time = function() return c.NOW end
c.COMBAT, c.TAXI, c.TOAST, c.ARRIVAL = false, false, false, false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitOnTaxi = function() return c.TAXI end
c.EventToastManagerFrame = Fake()
c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end

for _, f in ipairs({"chronicle/Style.lua", "modules/WelcomeBack.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local C, B = R.Chronicle, R.WelcomeBack
local M = c.TwichUIDB.modules
assert(M.welcomeBack == true, "on by default")
R.Arrival = R.Arrival or {}
R.Arrival.IsShowing = function() return c.ARRIVAL end
local opened = 0
R.ChronicleWindow = { Show = function() opened = opened + 1 end }
local events = R.frame.events

-- Ago: natural wording from a real timestamp, nothing when it can't be trusted.
local now = c.NOW
assert(B.Ago(now - 20, now) == "just now")
assert(B.Ago(now - 60, now) == "1 minute ago")
assert(B.Ago(now - 12 * 60, now) == "12 minutes ago")
assert(B.Ago(now - 3600, now) == "1 hour ago")
assert(B.Ago(now - 2 * 3600 - 5, now) == "2 hours ago")
assert(B.Ago(now - 3 * 86400, now) == C.FormatDay(C.DayKey(now - 3 * 86400)), "older: a date")
assert(B.Ago(now + 3600, now) == nil, "a time in the future is not shown")
assert(B.Ago(nil, now) == nil and B.Ago("x", now) == nil and B.Ago(-5, now) == nil, "unreadable times are not shown")
do -- yesterday is the previous calendar day, between 24 and 48 hours back
  local noon = os.time({year = 2026, month = 5, day = 10, hour = 12})
  assert(B.Ago(os.time({year = 2026, month = 5, day = 9, hour = 8}), noon + 0) == "yesterday")
  assert(B.Ago(os.time({year = 2026, month = 5, day = 8, hour = 20}), noon) == C.FormatDay(20260508), "two days back is a date")
end

-- No history: nothing to show. The Recorder's own "Chronicle begun" line has no place.
assert(B.Latest() == nil, "no entry with a place yet")
local function Login(isLogin, isReload)
  c.FireEvent("PLAYER_ENTERING_WORLD", isLogin, isReload)
end
local function Settle() RunLongTimers(10) end
local function Card() return groups[1] and groups[1].owner end
Login(true, false); Settle()
assert(not Card(), "no card without history")
C.Add("level", { title = "Reached level 5", level = 5 })   -- no place
assert(B.Latest() == nil, "an entry without a place is not used")
-- notes never show their text
local n = C.Add("note", { title = "Note", note = "private thought", zone = "Westfall" })
local count = C.Count()

-- A real login shows it, once the quiet time has passed.
c.NOW = c.NOW + 2 * 3600 + 30
Login(true, false)
assert(not Card(), "not at once: the login transition and the zone card come first")
Settle()
local card = Card()
assert(card and card.shown and groups[1].playing and groups[1].plays == 1, "card shown and animating")
assert(card.line.text:find("Last noted:", 1, true) and card.line.text:find("Westfall", 1, true) and card.line.text:find("2 hours ago", 1, true), card.line.text)
assert(not card.more.shown, "a note's text isn't repeated on screen")
assert(C.Count() == count, "showing it adds no Chronicle entry")
assert(events.PLAYER_REGEN_DISABLED and events.ZONE_CHANGED_NEW_AREA, "listens for combat and a new scene only while shown")
-- timeout: the animation finishing hides it and stops the listening
groups[1].scripts.OnFinished(groups[1])
assert(not card.shown and not events.PLAYER_REGEN_DISABLED, "gone after it fades")

-- A boss entry gives a second line; the zone entry doesn't repeat itself.
C.Add("boss", { title = "Defeated Deathmaw", zone = "Burning Steppes" })
Login(true, false); Settle()
assert(card.shown and card.more.shown and card.more.text == "Defeated Deathmaw" and card.line.text:find("Burning Steppes", 1, true), "boss line")
B.Dismiss()
assert(not card.shown and not groups[1].playing and not events.PLAYER_REGEN_DISABLED, "dismiss hides and cleans up")
C.Add("zone", { title = "Arrived in Duskwood", zone = "Duskwood" })
c.NOW = c.NOW + 5; C.Add("zone", { title = "Arrived in Elwynn Forest", zone = "Elwynn Forest" })
Login(true, false); Settle()
assert(card.shown and not card.more.shown, "an arrival entry has no second line")
B.Dismiss()

-- Reload and other loading screens never show it.
Login(false, true); Settle()
assert(not card.shown, "not after a reload")
Login(false, false); Settle()
assert(not card.shown, "not after a dungeon or hearthstone loading screen")
-- A reload during the wait drops it.
Login(true, false)
c.FireEvent("PLAYER_LEAVING_WORLD"); Login(false, true); Settle()
assert(not card.shown, "a reload while waiting shows nothing")

-- In the way: combat, flight, the zone card, a banner. It waits briefly, then gives up; nothing is queued.
for _, blocker in ipairs({"COMBAT", "TAXI", "ARRIVAL", "TOAST"}) do
  c[blocker] = true
  Login(true, false); Settle()
  assert(not card.shown, blocker .. " keeps it away")
  Settle(); Settle(); Settle()
  assert(not card.shown, blocker .. " is not queued for later")
  c[blocker] = false
end
-- ...but a short wait is fine.
c.COMBAT = true
Login(true, false); RunLongTimers(10)       -- delay
assert(not card.shown)
c.COMBAT = false; RunLongTimers(10)         -- first retry
assert(card.shown, "shown once combat has ended")
-- combat starting, or a new scene, takes it away
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not card.shown and not events.PLAYER_REGEN_DISABLED, "hides when combat starts")
Login(true, false); Settle()
c.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(not card.shown, "hides on a new zone")
Login(true, false); Settle()
c.FireEvent("PLAYER_LEAVING_WORLD")
assert(not card.shown, "hides when leaving the world")

-- Open Chronicle uses the existing window and dismisses the card.
Login(true, false); Settle()
card.open.scripts.OnClick()
assert(opened == 1 and not card.shown, "opens the Chronicle")
card.close.scripts.OnClick()   -- closing a hidden card is harmless

-- /tui welcome previews it at any time (even in combat), with the same text, and says so when there is nothing to show.
c.COMBAT = true
c.SlashCmdList.TWICHUI("welcome")
assert(card.shown and card.line.text:find("Last noted:", 1, true), "preview shows the card")
c.SlashCmdList.TWICHUI("welcome")
assert(card.shown and groups[1].plays > 0, "a second preview just starts over")
B.Dismiss(); c.COMBAT = false
do
  local saved = {}
  for i, e in ipairs(C.Entries()) do saved[i] = e end
  for i = #saved, 1, -1 do table.remove(C.Entries(), i) end
  local ok, why = B.Preview()
  assert(ok == false and why:find("nothing to show", 1, true) and not card.shown, "no history: a reason, no card")
  for i, e in ipairs(saved) do C.Entries()[i] = e end
end

-- Reduced motion: it only fades.
M.arrivalReducedMotion = true
Login(true, false); Settle()
assert(groups[1].plays > 0 and card.shown)
B.Dismiss()
M.arrivalReducedMotion = false

-- Off: nothing at login, nothing listened for, the Chronicle untouched.
local before = C.Count()
M.welcomeBack = false; B.Refresh()
Login(true, false); Settle()
assert(not card.shown, "off means off")
assert(C.Count() == before, "the Chronicle is unchanged")
assert(events.ZONE_CHANGED_NEW_AREA, "Chronicle zone tracking is still registered")
-- Turned on mid-session: nothing until the next login.
M.welcomeBack = true; B.Refresh(); Settle()
assert(not card.shown, "turning it on doesn't show it")
Login(false, true); Settle()
assert(not card.shown)

-- An existing explicit opt-out survives; a new install gets it on.
local d = MakeClient("Pat", {"!!!TwichUI"})
d.TwichUIDB = { modules = { welcomeBack = false } }
d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(d.TwichUIDB.modules.welcomeBack == false, "saved false is kept")
print("OK welcome back")
