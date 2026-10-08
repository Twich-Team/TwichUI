dofile(TESTS .. "harness.lua")
-- Welcome dialog: owed only to a new installation, shown once when the game is ready for it, never
-- scheduled twice, never discarding a real notice, routing "Open Settings" to the real options, and
-- changing no setting. Synthetic data only. See modules/Welcome.lua and docs/persistence.md.

---------------------------------------------------------------------------
-- A session: the client with the files the dialog uses, a stand-in for frames, and the saved variables
---------------------------------------------------------------------------
local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.shows, o.blocked = false, {}, {}, 0, false
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true; s.shows = s.shows + 1 end end
    if k == "Hide" then return function(s) local was = s.shown; s.shown = false; if was and s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "IsVisible" then return function(s) return s.shown and not s.blocked end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h end end
    if k == "SetWidth" then return function(s, w) s.w = w end end
    if k == "GetWidth" then return function(s) return s.w or 0 end end
    if k == "GetStringWidth" then return function(s) return #(s.text or "") * 6 end end
    if k == "GetStringHeight" then return function(s)
      -- A wrapped line is LINE tall and holds ~60 characters at the dialog's width (the footer's width is narrower).
      local width = s.w or 400
      local perLine = math.max(10, math.floor(width / 7))
      return math.ceil(#(s.text or "") / perLine) * (LINE or 14)
    end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    return function() end
  end})
end

local function Settle() for _ = 1, 4 do FlushTimers(); RunLongTimers(10) end end
local function Enter(c, isLogin) c.FireEvent("PLAYER_ENTERING_WORLD", isLogin == nil or isLogin, false) end

-- A client with the files the dialog uses, a stand-in for frames (remembering the dialog), and the
-- saved variables as given (none: a new installation).
local function Boot(sv, opts)
  opts = opts or {}
  local holder = {}
  local c = MakeClient("Rich", {"!!!TwichUI"})
  c.said = {}
  c.print = function(s) c.said[#c.said + 1] = tostring(s) end
  c.CreateFrame = function(_, name)
    local f = Fake()
    if name == "TwichUIWelcome" then holder.dialog = f end
    return f
  end
  c.UIParent = Fake(); c.UIParent.shown = true
  c.UISpecialFrames = {}
  c.COMBAT, c.TAXI, c.TOAST = false, false, false
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitOnTaxi = function() return c.TAXI end
  c.EventToastManagerFrame = Fake()
  c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end
  c.NOW = 1700000000
  c.GetTime = function() return c.NOW end
  c.opened = nil
  c.Settings = { OpenToCategory = function(id) c.opened = id end }
  for k, v in pairs(sv or {}) do c[k] = v end
  for _, f in ipairs(opts.files or {"chronicle/Style.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/WelcomeBack.lua", "modules/Welcome.lua"}) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.holder = holder
  return c
end
local function D(c) return c.holder.dialog end
local function State(c) return c.TwichUIDB.welcome and c.TwichUIDB.welcome.state end
local function W(c) return c.TwichUI.Welcome end
local function Listening(c) return W(c).Snapshot().listening end

---------------------------------------------------------------------------
-- 1. A new installation: owed, quiet until the world is ready, then shown once
---------------------------------------------------------------------------
local c = Boot()
assert(State(c) == "pending" and W(c).Owed(), "a new installation is owed the welcome")
assert(Listening(c), "and listens for the world")
assert(not D(c), "nothing is built before it is needed")
assert(c.TwichUI.DEFAULT_MODULES.welcome == nil and c.TwichUIDB.modules.welcome == nil, "the marker is not a feature switch")
local modulesBefore = copy(c.TwichUIDB.modules)
local uiBefore = copy(c.TwichUIDB.ui or {})
local giveUp = W(c).Snapshot()
assert(giveUp.shown == 0 and giveUp.waiting == false)

Enter(c)
assert(not D(c), "not at once: the world settles first")
assert(W(c).Snapshot().waiting, "one look is waiting")
-- Entering the world again and again (a loading screen, a zone) never stacks looks.
Enter(c, false); Enter(c, false); Enter(c, false)
assert(W(c).Snapshot().waiting)
Settle()
local f = D(c)
assert(f and f.shown, "shown once the world has settled")
assert(State(c) == "seen" and not W(c).Owed(), "marked seen only now that it is on screen")
assert(not Listening(c), "and no longer listening for anything")
assert(W(c).Snapshot().shown == 1, "exactly once, however many world entries")
assert(c.UISpecialFrames[#c.UISpecialFrames] == "TwichUIWelcome", "Escape closes it through the game's own list")
assert(f.title.text == "Welcome to TwichUI" and f.intro.text == W(c).INTRO)
assert(#f.points == 3 and f.open.text.text == "Open Settings" and f.dismiss.text.text == "Close", "title, three points, two buttons")
assert(f.footer.text:find("/tui", 1, true), "a /tui reminder in the footer")
assert(f.h and f.h > 150 and f.w == 440, "sized from its content")
-- It changes nothing the player set.
assert(copy(c.TwichUIDB.modules) ~= nil)
for k, v in pairs(modulesBefore) do assert(c.TwichUIDB.modules[k] == v, "setting unchanged: " .. k) end
for k, v in pairs(uiBefore) do assert(c.TwichUIDB.ui and c.TwichUIDB.ui[k] == v, "ui unchanged: " .. k) end

-- Closing it (its Close button) leaves it closed: later world entries and a new login never bring it back.
f.dismiss.scripts.OnClick(f.dismiss)
assert(not f.shown)
Enter(c, false); Settle(); Enter(c, true); Settle()
assert(not f.shown and W(c).Snapshot().shown == 1, "never reopens by itself")
-- The title-area close control and Escape (which hides the frame) do the same.
W(c).Show(); assert(f.shown)
f.close.scripts.OnClick(f.close); assert(not f.shown, "close control")
W(c).Show(); f:Hide(); assert(not f.shown, "Escape hides the frame")
-- A new session from what was saved: no welcome.
local saved = copy(c.TwichUIDB)
local again = Boot({ TwichUIDB = saved })
assert(State(again) == "seen" and not Listening(again), "a later login")
Enter(again); Settle()
assert(not D(again), "and nothing is built or shown")
-- Switching characters is the same account-wide data; a feature-level reset or the options' Defaults button
-- only touch the switches, never the marker.
again.TwichUIDB.modules = {}
for k, v in pairs(again.TwichUI.DEFAULT_MODULES) do again.TwichUIDB.modules[k] = v end
assert(State(again) == "seen", "resetting the switches does not reset the welcome")

---------------------------------------------------------------------------
-- 2. Existing installations are never put through it
---------------------------------------------------------------------------
for name, sv in pairs({
  current = { schema = 1, modules = {} },
  unversioned = { modules = { chronicle = false }, ui = {} },
  older = { shareTransport = "GUILD", modules = { comboPoints = true, shareGroup = true } },
  junkMarker = { schema = 1, modules = {}, welcome = "pending" },
  junkState = { schema = 1, modules = {}, welcome = { state = "pending-ish" } },
}) do
  local e = Boot({ TwichUIDB = copy(sv) })
  assert(State(e) == "seen" and not W(e).Owed() and not Listening(e), name .. ": not owed")
  Enter(e); Settle()
  assert(not D(e), name .. ": nothing shown after upgrading")
end

---------------------------------------------------------------------------
-- 3. Deferral: combat, flight, a banner, a hidden interface, a loading screen, a TwichUI card
---------------------------------------------------------------------------
local function Fresh() return Boot() end
local function Showing(e) return D(e) and D(e).shown end

local e = Fresh()
e.COMBAT = true
Enter(e); Settle()
assert(not Showing(e) and State(e) == "pending", "combat holds it back, and it is still owed")
assert(e.TwichUI.Life.Snapshot().notes["welcome-deferred"], "counted for the troubleshooting report (a code, no text)")
e.COMBAT = false
e.FireEvent("PLAYER_REGEN_ENABLED"); Settle()
assert(Showing(e) and State(e) == "seen", "shown when the fight ends")

for name, set in pairs({
  flight = function(x, on) x.TAXI = on end,
  banner = function(x, on) x.TOAST = on end,
  interface = function(x, on) x.UIParent.shown = not on end,
}) do
  local x = Fresh()
  set(x, true)
  Enter(x); Settle()
  assert(not Showing(x) and State(x) == "pending", name .. ": held back")
  set(x, false)
  Enter(x); Settle()
  assert(Showing(x), name .. ": shown afterwards")
end

-- A loading screen drops the look that was waiting; the next world entry makes a new one.
local x = Fresh()
Enter(x)
x.FireEvent("PLAYER_LEAVING_WORLD")
Settle()
assert(not Showing(x) and State(x) == "pending", "nothing is shown while the world is not entered")
Enter(x); Settle()
assert(Showing(x) and W(x).Snapshot().shown == 1)

-- Shown but not actually visible (nothing was seen): still owed, tried again.
x = Fresh()
local blocked = true
local origCreate = x.CreateFrame
x.CreateFrame = function(...) local fr = origCreate(...); fr.blocked = blocked; return fr end
Enter(x); Settle()
assert(State(x) == "pending" and W(x).Snapshot().shown == 0, "not marked seen when it was not visible")
blocked = false; D(x).blocked = false
Enter(x); Settle()
assert(State(x) == "seen" and Showing(x), "marked seen when it finally is")

-- The tries are bounded: constant combat makes a fixed number of looks, not an endless loop.
x = Fresh()
x.COMBAT = true
Enter(x)
for _ = 1, 60 do
  if not W(x).Snapshot().waiting then break end
  FlushTimers(); RunLongTimers(10)
end
local give = W(x).Snapshot()
assert(not give.waiting and give.tries == 15, "stops looking by itself after a fixed number of looks (" .. tostring(give.tries) .. ")")
assert(State(x) == "pending", "and the welcome is still owed for the next time")
x.COMBAT = false; x.FireEvent("PLAYER_REGEN_ENABLED"); Settle()
assert(Showing(x), "the end of the fight starts it again")

-- A TwichUI card up: the dialog waits; the card is neither dropped nor delayed by it.
x = Fresh()
Enter(x)
local N = x.TwichUI.Notify
local cardShown, cardDismissed = 0, 0
N.Register("welcometest", { label = "test", show = function() cardShown = cardShown + 1 return true end,
  dismiss = function() cardDismissed = cardDismissed + 1 end, bounds = function() return 0, 0, 10, 10 end, hold = function() return 100 end })
assert(N.Submit({ kind = "welcometest", id = "one", payload = {} }) and cardShown == 1, "a real card is up")
FlushTimers(); RunLongTimers(3)   -- the dialog's first look
assert(not Showing(x) and State(x) == "pending", "the dialog waits for the card")
assert(cardDismissed == 0 and next(N.Snapshot().active), "the card was not dismissed, replaced or hurried for it")
assert(next(N.Snapshot().dropped) == nil and next(N.Snapshot().refused) == nil, "nothing was discarded or refused")
N.Finished("welcometest")
Settle()
assert(Showing(x) and State(x) == "seen", "it appears once the card is gone")
-- The other way round: a notice that arrives while the dialog is open is shown as always.
assert(N.Submit({ kind = "welcometest", id = "two", payload = {} }) and cardShown == 2, "notices are not held back by an open dialog")

-- Missing pieces are neutral: no coordinator, no Chronicle look.
local bare = Fresh()
bare.TwichUI.Notify = nil
Enter(bare); Settle()
assert(Showing(bare), "without the coordinator it still shows")
local noLook = Fresh()
noLook.TwichUI.ChronicleStyle = nil
Enter(noLook); Settle()
assert(not Showing(noLook) and State(noLook) == "pending", "without its look it does not show, and stays owed")
local said = false
for _, line in ipairs(noLook.said) do if line:find("TwichUI", 1, true) then said = true end end
assert(not said, "and says nothing about it")

---------------------------------------------------------------------------
-- 4. Manual opening
---------------------------------------------------------------------------
local m = Boot({ TwichUIDB = { schema = 1, modules = {}, welcome = { state = "seen" } } })
local mods = copy(m.TwichUIDB.modules)
m.TwichUI.RunCommand("about")
assert(Showing(m), "/tui about shows it")
assert(State(m) == "seen", "and changes nothing about the marker")
for k, v in pairs(mods) do assert(m.TwichUIDB.modules[k] == v, "no setting changed by opening it: " .. k) end
D(m):Hide()
m.TwichUI.RunCommand("about"); m.TwichUI.RunCommand("about")
assert(Showing(m) and W(m).Snapshot().shown == 3, "can be shown any number of times, one frame")
-- Before the automatic one: showing it by hand counts as seen and stops the waiting look.
local p = Fresh()
Enter(p)
p.TwichUI.RunCommand("about")
assert(Showing(p) and State(p) == "seen" and not Listening(p))
D(p):Hide()
Settle()
assert(not Showing(p) and W(p).Snapshot().shown == 1, "the waiting look did not show it a second time")

---------------------------------------------------------------------------
-- 5. Actions
---------------------------------------------------------------------------
local a = Boot()
a.TwichUI.settingsCategories = { overview = { GetID = function() return 42 end } }
Enter(a); Settle()
local dlg = D(a)
assert(dlg.shown)
dlg.open.scripts.OnClick(dlg.open)
assert(a.opened == 42 and not dlg.shown, "Open Settings closes the dialog and opens TwichUI's own page")
-- No settings page (the options failed to build): say so, keep the dialog.
local b = Boot({ TwichUIDB = { schema = 1, modules = {}, welcome = { state = "seen" } } })
b.TwichUI.RunCommand("about")
b.TwichUI.settingsCategories, b.TwichUI.settingsCategory = nil, nil
D(b).open.scripts.OnClick(D(b).open)
assert(D(b).shown and b.opened == nil, "the dialog stays when the settings are missing")
local told = false
for _, s in ipairs(b.said) do if s:find("settings aren't available", 1, true) then told = true end end
assert(told, "and says why, in plain words")
-- /tui help lists the command; the Welcome Back preview keeps its own name.
local listed = {}
b.print = function(s) listed[#listed + 1] = s end
b.TwichUI.RunCommand("help")
local blob = table.concat(listed, "\n")
assert(blob:find("/tui about", 1, true), "help lists the command")
assert(blob:find("/tui welcome", 1, true) and blob:find("Welcome Back", 1, true), "the Welcome Back preview command is kept")

---------------------------------------------------------------------------
-- 6. Layout follows the text: taller text, taller frame; nothing is a fixed height
---------------------------------------------------------------------------
LINE = 14
local short = Boot({ TwichUIDB = { schema = 1, modules = {}, welcome = { state = "seen" } } })
short.TwichUI.RunCommand("about")
local h1 = D(short).h
LINE = 28
short.TwichUI.RunCommand("about")
local h2 = D(short).h
LINE = nil
assert(h1 and h2 and h2 > h1 + 40, "a bigger font or a longer translation grows the frame (" .. tostring(h1) .. " -> " .. tostring(h2) .. ")")

print("WELCOME TESTS PASSED")
