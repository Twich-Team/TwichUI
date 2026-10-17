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
  c.CLASS = "WARRIOR"
  c.UnitClass = function() return c.CLASS:sub(1, 1) .. c.CLASS:sub(2):lower(), c.CLASS end
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitOnTaxi = function() return c.TAXI end
  c.EventToastManagerFrame = Fake()
  c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end
  c.NOW = 1700000000
  c.GetTime = function() return c.NOW end
  c.opened = nil
  c.Settings = nil   -- (the settings window is TwichUI's own; no AddOns entry in these tests)
  for k, v in pairs(sv or {}) do c[k] = v end
  for _, f in ipairs(opts.files or {"chronicle/Style.lua", "Look.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/WelcomeBack.lua", "modules/WelcomeAutomation.lua", "modules/Welcome.lua"}) do
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
assert(f.h and f.h > 150 and f.w == 460, "sized from its content")
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
noLook.TwichUI.Look = nil
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
-- the settings window's addon loads on demand; here it only records where it was asked to open
a.C_AddOns.LoadAddOn = function(name)
  if name ~= "TwichUI_Settings" then return false, "MISSING" end
  a.TwichUI.SettingsUI = { Open = function(page) a.opened = page or "overview" end, IsShown = function() return false end }
  return true
end
Enter(a); Settle()
local dlg = D(a)
assert(dlg.shown)
dlg.open.scripts.OnClick(dlg.open)
assert(a.opened == "overview" and not dlg.shown, "Open Settings closes the dialog and opens TwichUI's settings at the start")
-- The settings window can't load (its folder is missing): say so, keep the dialog.
local b = Boot({ TwichUIDB = { schema = 1, modules = {}, welcome = { state = "seen" } } })
b.TwichUI.RunCommand("about")
b.C_AddOns.LoadAddOn = function() return false, "MISSING" end
D(b).open.scripts.OnClick(D(b).open)
assert(D(b).shown and b.opened == nil, "the dialog stays when the settings can't be opened")
local told = false
for _, s in ipairs(b.said) do if s:find("couldn't open the settings", 1, true) and s:find("TwichUI_Settings", 1, true) then told = true end end
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

---------------------------------------------------------------------------
-- 7. Automation summary: what is on, what is off, scope as set, class filter. It reads and changes nothing.
---------------------------------------------------------------------------
local function Stubs(c, opts)
  opts = opts or {}
  local R = c.TwichUI
  R.Group, R.PinSync = {}, {}
  R.QoL = { Get = function(key) return (opts.qol or {})[key] or ({ summonsFrom = "known", summonsWait = 3, duelsFrom = "known", releaseWait = 2 })[key] end }
  R.QoLGuideWaypoint = {}
  R.Setups = { AddonState = function() return opts.rxp or "ready" end }
  if opts.mage then
    R.MageSell = { Mode = function() return opts.mode or "direct" end, DryRun = function() return opts.dry ~= false end }
    R.RefreshmentsTrade = {}
  end
end
local function Keys(list) local out = {} for _, e in ipairs(list) do out[#out + 1] = e.key end return table.concat(out, ",") end
local function Has(list, key) for _, e in ipairs(list) do if e.key == key then return e end end end

local n = Boot()
Stubs(n)
local A = n.TwichUI.WelcomeAutomation
local modulesNow, uiNow = copy(n.TwichUIDB.modules), copy(n.TwichUIDB.ui or {})
local sum = A.Summary()
assert(Keys(sum.on) == "groupCheck,partyPins,quietLogin", "a new installation: only the default-on background features are on (" .. Keys(sum.on) .. ")")
for _, key in ipairs({ "qolSummons", "qolResurrect", "qolReleasePvP", "qolDuels", "qolGuideWaypoint" }) do
  assert(Has(sum.off, key), key .. " is available but off")
end
assert(not Has(sum.on, "mageSell") and not Has(sum.off, "mageSell") and not Has(sum.off, "mageRefreshmentsAutoFill"), "a Warrior is told nothing about Mage features")
assert(Has(sum.on, "groupCheck").text:find("hidden addon channel", 1, true) and Has(sum.on, "groupCheck").text:find("Nothing is written in chat", 1, true), "background messaging is described, not hidden")
assert(sum.pages[1] == "qol" and #sum.pages == 4, "pages to review, once each, in order")
for k, v in pairs(modulesNow) do assert(n.TwichUIDB.modules[k] == v, "summary changed a switch: " .. k) end

-- Turning a feature on elsewhere moves it to "on", with the scope as set. A damaged value never reads as on.
n.TwichUIDB.modules.qolSummons = true
n.TwichUIDB.modules.qolDuels = "yes"
n.TwichUI.QoL.Get = function(key) return ({ summonsFrom = "group", summonsWait = 0, duelsFrom = "friends" })[key] end
sum = A.Summary()
local s1 = Has(sum.on, "qolSummons")
assert(s1 and s1.text:find("group members", 1, true) and s1.text:find("at once", 1, true) and not s1.text:find("guild", 1, true), "scope follows the chosen source and wait")
assert(Has(sum.off, "qolDuels") and not Has(sum.on, "qolDuels"), "a damaged switch is not on")
n.TwichUIDB.modules.qolDuels = true; n.TwichUIDB.modules.qolDuelsToDeath = true
local s2 = Has(A.Summary().on, "qolDuels")
assert(s2.text:find("friends", 1, true) and s2.text:find("to the death", 1, true), "duel scope names who is excepted and the lethal kind")
-- No RestedXP: its waypoint is not offered at all.
local noRxp = Boot(); Stubs(noRxp, { rxp = "missing" })
assert(not Has(noRxp.TwichUI.WelcomeAutomation.Summary().off, "qolGuideWaypoint"), "RestedXP absent: not listed")

-- Mage: its features appear, with their real state.
local mage = Boot(); mage.CLASS = "MAGE"; Stubs(mage, { mage = true })
local ms = mage.TwichUI.WelcomeAutomation.Summary()
assert(Has(ms.off, "mageSell") and Has(ms.off, "mageRefreshmentsAutoFill") and ms.pages[2] == "mage", "a Mage sees the Mage features, off by default")
mage.TwichUIDB.modules.mageSell = true
local sell = Has(mage.TwichUI.WelcomeAutomation.Summary().on, "mageSell")
assert(sell.text:find("Sells ordinary", 1, true) and sell.text:find("dry run", 1, true), "selling: direct mode, still a dry run")
mage.TwichUI.MageSell.Mode = function() return "ellesmere" end
mage.TwichUI.MageSell.DryRun = function() return false end
sell = Has(mage.TwichUI.WelcomeAutomation.Summary().on, "mageSell")
assert(sell.text:find("junk in EllesmereUI", 1, true) and not sell.text:find("dry run", 1, true) and not sell.text:find("Sells", 1, true), "EllesmereUI mode marks, never sells, and says so")
-- Trade filling needs the refreshments panel too.
mage.TwichUIDB.modules.mageRefreshmentsAutoFill = true
assert(not Has(mage.TwichUI.WelcomeAutomation.Summary().on, "mageRefreshmentsAutoFill"), "trade filling is not on while the panel is off")
mage.TwichUIDB.modules.mageRefreshments = true
local fill = Has(mage.TwichUI.WelcomeAutomation.Summary().on, "mageRefreshmentsAutoFill")
assert(fill and fill.text:find("never accepts the trade", 1, true), "trade filling on, and says it never accepts")

---------------------------------------------------------------------------
-- 8. The dialog shows the summary, links to the right pages, and opens settings only when asked
---------------------------------------------------------------------------
local g = Boot()
Stubs(g)
local loads, openedPages = 0, {}
g.C_AddOns.LoadAddOn = function(name)
  if name ~= "TwichUI_Settings" then return false, "MISSING" end
  loads = loads + 1
  g.TwichUI.SettingsUI = { Open = function(page) openedPages[#openedPages + 1] = page or "overview" end, IsShown = function() return false end }
  return true
end
Enter(g); Settle()
local gd = D(g)
assert(gd.shown and loads == 0 and g.TwichUI.SettingsUI == nil, "showing the welcome does not load the settings addon")
g.TwichUI.RunCommand("about")
assert(loads == 0, "nor does reopening it")
assert(#gd.rows == 3 and gd.rows[1].label.text == "Group version check" and gd.onNone.shown == false, "one row for each feature that is on")
assert(gd.offText.text:find("^Accepting summons") and gd.offText.text:find("%.$"), "what is off is a short sentence")
assert(#gd.links == 4 and gd.links[1].text.text == "Quality of life" and gd.links[2].text.text == "Sharing" and gd.links[3].text.text == "Party pins", "a link to each page that holds one of them")
assert(gd.links[1].shown and gd.links[1].page == "qol")
gd.links[1].scripts.OnClick(gd.links[1])
assert(loads == 1 and openedPages[1] == "qol" and not gd.shown, "a link opens its settings page through the normal entry point")
g.TwichUI.RunCommand("about")
gd.links[3].scripts.OnClick(gd.links[3])
assert(loads == 1 and openedPages[2] == "pins", "the settings addon loads once")
-- Showing again after a feature changed rebuilds the text without making new frames.
local rowFrames, linkFrames = #gd.rows, #gd.links
g.TwichUIDB.modules.qolSummons = true
g.TwichUI.RunCommand("about")
assert(#gd.rows == rowFrames + 1 and gd.rows[4].label.shown, "a feature turned on shows up the next time")
assert(not gd.offText.text:find("^Accepting summons"), "and leaves the off list")
for _ = 1, 5 do g.TwichUI.RunCommand("about") end
assert(#gd.rows == rowFrames + 1 and #gd.links == linkFrames, "reopening makes no new widgets")
-- With everything off there is a plain statement, not an empty box.
local quiet = Boot({ TwichUIDB = { schema = 2, modules = { groupCheck = false, partyPins = false, quietLogin = false }, welcome = { state = "seen" } } })
Stubs(quiet)
quiet.TwichUI.RunCommand("about")
assert(D(quiet).onNone.shown and D(quiet).rows[1] == nil, "nothing on: says so")

---------------------------------------------------------------------------
-- 9. Preview: the coordinator's own, isolated, silent, bounded, taken back on close
---------------------------------------------------------------------------
local v = Boot({ TwichUIDB = { schema = 2, modules = {}, welcome = { state = "seen" } } },
  { files = { "chronicle/Style.lua", "Look.lua", "modules/Notify.lua", "modules/WelcomeAutomation.lua", "modules/Welcome.lua" } })
Stubs(v)
-- Stand-ins for the zone and friend cards (their real renderers need animation frames this fake lacks): what
-- matters here is how the welcome asks for them. Each records what it was shown with.
local shownCards, previewFlags = {}, {}
for i, kind in ipairs({ "arrival", "friend" }) do
  v.TwichUI.Notify.Register(kind, {
    label = kind, sample = function() return { made_up = true } end,
    show = function(payload, ctx) shownCards[#shownCards + 1] = kind; previewFlags[#previewFlags + 1] = ctx and ctx.preview; return true end,
    dismiss = function() v.TwichUI.Notify.Finished(kind) end,
    bounds = function() return i * 100, 0, i * 100 + 50, 50 end, hold = function() return 100 end,
  })
end
local sounds = 0
v.PlaySound = function() sounds = sounds + 1 end
v.PlaySoundFile = function() sounds = sounds + 1 end
Enter(v); Settle()
v.TwichUI.RunCommand("about")
local vd = D(v)
assert(vd.preview.shown, "the preview button is offered when the coordinator is there")
local N = v.TwichUI.Notify
local beforeDB = copy(v.TwichUIDB)
vd.preview.scripts.OnClick(vd.preview)
local snap = N.Snapshot()
assert(snap.active.arrival == "preview" and snap.active.friend == "preview", "the sample zone and friend cards are up, marked as previews")
for _, flag in ipairs(previewFlags) do assert(flag == true, "each was shown as a preview") end
assert(sounds == 0 and not N.PreviewSounds(), "silent by default")
for _ = 1, 4 do vd.preview.scripts.OnClick(vd.preview) end
snap = N.Snapshot()
assert(snap.queued == 0 and snap.active.arrival == "preview" and snap.active.friend == "preview", "pressing again restarts the samples; nothing piles up")
assert(v.TwichUI.Welcome.Snapshot().state == "seen")
for k, val in pairs(beforeDB) do
  if type(val) ~= "table" then assert(v.TwichUIDB[k] == val, "saved value unchanged: " .. k) end
end
for k, val in pairs(beforeDB.modules) do assert(v.TwichUIDB.modules[k] == val, "no switch changed by a preview: " .. k) end
assert(v.TwichUIDB.ui == nil or v.TwichUIDB.ui.previewSounds == nil, "the preview-sound choice is not touched")
-- Closing the dialog takes back what it showed.
vd:Hide()
snap = N.Snapshot()
assert(next(snap.active) == nil and snap.queued == 0, "closing the welcome clears its sample cards")
-- A preview started in the settings is not the welcome's to remove.
v.TwichUI.RunCommand("about")
N.Preview("arrival")
vd:Hide()
assert(N.Snapshot().active.arrival == "preview", "the welcome leaves previews it didn't start")
N.ClearPreviews()
-- Not during combat; says so.
v.TwichUI.RunCommand("about")
v.COMBAT = true
v.said = {}
local okCombat, whyCombat = v.TwichUI.Welcome.Preview()
assert(okCombat == false and whyCombat == "combat" and next(N.Snapshot().active) == nil, "no preview in combat")
local toldCombat = false
for _, line in ipairs(v.said) do if line:find("out of combat", 1, true) then toldCombat = true end end
assert(toldCombat, "and it says why")
-- Without the coordinator the button is left out and the rest still works.
local nn = Boot({ TwichUIDB = { schema = 2, modules = {}, welcome = { state = "seen" } } },
  { files = { "chronicle/Style.lua", "Look.lua", "modules/WelcomeAutomation.lua", "modules/Welcome.lua" } })
nn.TwichUI.RunCommand("about")
assert(D(nn).shown and not D(nn).preview.shown, "no coordinator: no Preview button, dialog still works")
assert(select(2, nn.TwichUI.Welcome.Preview()) == "unavailable")

---------------------------------------------------------------------------
-- 10. Escape, UI scale and reduced motion
---------------------------------------------------------------------------
local e2 = Boot({ TwichUIDB = { schema = 2, modules = {}, welcome = { state = "seen" } } })
Stubs(e2)
local scaled
local create = e2.CreateFrame
e2.CreateFrame = function(...)
  local fr = create(...)
  fr.SetScale = function(s, x) s.scale = x end
  fr.GetScale = function(s) return rawget(s, "scale") or 1 end
  fr.GetHeight = function(s) return rawget(s, "h") or 0 end
  fr.SetAlpha = function(s, x) s.alpha = x end
  return fr
end
e2.UIParent.w = 1000; e2.UIParent.GetHeight = function() return 300 end
e2.TwichUI.RunCommand("about")
local ed = D(e2)
assert(ed.scale and ed.scale < 1 and ed.scale >= 0.6, "a small screen scales the dialog down, not below the floor (" .. tostring(ed.scale) .. ")")
e2.UIParent.w = 4000; e2.UIParent.GetHeight = function() return 3000 end
e2.TwichUI.RunCommand("about")
assert(ed.scale == 1, "and back to full size when there is room")
-- Escape goes through the game's list; the frame hides and nothing is left running.
assert(e2.UISpecialFrames[#e2.UISpecialFrames] == "TwichUIWelcome")
ed:Hide()
assert(not ed.shown)
-- "Reduce window motion" turns its fade off; otherwise it fades in from clear.
e2.TwichUIDB.ui = { reduceSettingsMotion = true }
ed.hooks.OnShow(ed)
assert(ed.alpha == 1, "reduced motion: opens at once")
e2.TwichUIDB.ui.reduceSettingsMotion = false
ed.hooks.OnShow(ed)
assert(ed.alpha == 0, "otherwise it fades in from clear")

print("WELCOME TESTS PASSED")
