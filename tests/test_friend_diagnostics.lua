dofile(TESTS .. "harness.lua")
-- Friend notification diagnostics through the shared service (diag/Friends.lua, diag/Diagnostics.lua):
-- off by default, real friend events and the module's decisions with anonymous labels only, bounded, local,
-- cleared by clear, and synthetic tests marked as such.
local c = MakeClient("Rich", {"!!!TwichUI"})

local fakes = {}
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.events = false, {}, {}, {}
  table.insert(fakes, o)
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "GetText" then return function(s) return s.text or "" end end
    if k == "RegisterEvent" then return function(s, e)
      if s.refuse and s.refuse[e] then error("unknown event " .. e) end
      s.events[e] = true
    end end
    if k == "UnregisterAllEvents" then return function(s) s.events = {} end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetStringWidth" then return function(s) return #(s.text or "") * 8 end end
    if k == "SetWidth" then return function(s, v) s.width = v end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h end end
    if k == "GetWidth" then return function(s) return s.w or s.width or 0 end end
    if k == "SetHeight" then return function(s, v) s.height = v end end
    if k == "EnableMouse" then return function(s, v) s.mouse = v end end
    if k == "SetPoint" then return function(s, ...) s.point = {...} end end
    if k == "ClearAllPoints" then return function(s) s.point = nil end end
    if k == "SetAtlas" then return function(s, v) s.atlas, s.texture = v, nil end end
    if k == "SetTexture" then return function(s, v) s.texture, s.atlas = v, nil end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({owner = s, plays = 0})
      g.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function()
        local a = Fake()
        a.SetOffset = function(self, x, y) self.x, self.y = x, y end
        a.SetStartDelay = function(self, d) self.delay = d end
        return a
      end
      return g
    end end
    return function() end
  end})
end
c.CreateFrame = function(_, name) local f = Fake(); f.name = name; f.refuse = false; return f end
c.UISpecialFrames = {}
c.BackdropTemplate = nil
c.UIParent = Fake()
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
c.GameTooltip = Fake()
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }

-- The game's own pop-up: only its event list matters.
local toast = { events = { BN_FRIEND_ACCOUNT_ONLINE = true, BN_FRIEND_ACCOUNT_OFFLINE = true, BN_CUSTOM_MESSAGE_CHANGED = true } }
function toast:IsEventRegistered(e) return self.events[e] == true end
function toast:RegisterEvent(e) self.events[e] = true end
function toast:UnregisterEvent(e) self.events[e] = nil end
c.BNToastFrame = toast

c.CV = { showToastWindow = true, showToastOnline = true }
c.GetCVarBool = function(name) return c.CV[name] == true end
c.NOW = 1000
c.GetTime = function() return c.NOW end
c.COMBAT, c.TOAST, c.ARRIVAL = false, false, false
c.InCombatLockdown = function() return c.COMBAT end
c.EventToastManagerFrame = Fake()
c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end
c.UnitFactionGroup = function() return "Alliance", "Alliance" end
c.ATLAS = true
c.C_Texture = { GetAtlasInfo = function() return c.ATLAS and { width = 40, height = 20 } or nil end }
local SECRET = "<secret>"
c.issecretvalue = function(v) return v == SECRET end
c.SOUNDS = {}
c.PlaySoundFile = function(path, channel) c.SOUNDS[#c.SOUNDS + 1] = { path = path, channel = channel }; return true end
local function Sounds() local n = #c.SOUNDS; c.SOUNDS = {}; return n end

-- Friends the game knows about, by Battle.net account id.
c.FRIENDS = {}
c.C_BattleNet = { GetAccountInfoByID = function(id) return c.FRIENDS[id] end }
local function Friend(id, name, character, faction)
  c.FRIENDS[id] = { accountName = name, battleTag = name .. "#1234", gameAccountInfo = { characterName = character, factionName = faction, clientProgram = "WoW" } }
end

for _, f in ipairs({"chronicle/Style.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/FriendLogin.lua",
  "diag/Diagnostics.lua", "diag/Notifications.lua", "diag/Window.lua", "diag/Friends.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local F = R.FriendLogin
local M = c.TwichUIDB.modules

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(fakes) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Card() for _, f in ipairs(fakes) do if rawget(f, "icon") and rawget(f, "sub") then return f end end end
local function Settle() FlushTimers(); RunLongTimers(2); FlushTimers() end
local function Finish(group) group.playing = false; group.scripts.OnFinished(group) end
local function Online(id, companion) Fire("BN_FRIEND_ACCOUNT_ONLINE", id, companion or false) end
-- A real login, then past its quiet time.
local function LoggedIn() Fire("PLAYER_ENTERING_WORLD", true, false); c.NOW = c.NOW + 6 end

local D = R.Diag
local T = R.DiagFriends
local PRINTED = {}
c.print = function(s) PRINTED[#PRINTED + 1] = tostring(s) end
local function Said() local all = table.concat(PRINTED, "\n"); PRINTED = {}; return all end
local function Cmd(arg) c.SlashCmdList.TWICHUI("diagnostics " .. (arg or "")); return Said() end
local function DiagFrame() for _, f in ipairs(fakes) do if f.scripts.OnEvent and f ~= R.frame and rawget(f, "refuse") ~= nil then return f end end end
-- Game-side pieces the diagnostics read.
c.IsInInstance = function() return c.INSTANCE ~= nil, c.INSTANCE or "none" end
c.INSTANCE = nil
c.GetBuildInfo = function() return "1.2.3", "45678" end
c.GetCVar = function(n) return c.CV[n] == nil and "1" or (c.CV[n] and "1" or "0") end
c.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
c.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
c.BN = {}     -- list position -> account info
c.BNGetNumFriends = function() return #c.BN, 0 end
c.C_BattleNet.GetFriendAccountInfo = function(i) return c.BN[i] end
c.LEGACY = {}
c.C_FriendList = { GetNumFriends = function() return #c.LEGACY end, GetFriendInfoByIndex = function(i) return c.LEGACY[i] end,
  GetNumOnlineFriends = function() local n = 0 for _, f in ipairs(c.LEGACY) do if f.connected then n = n + 1 end end return n end }
local function BN(id, online, client, character)
  local info = { bnetAccountID = id, accountName = "Secretname" .. id, battleTag = "Tag" .. id .. "#9999",
    gameAccountInfo = { isOnline = online, clientProgram = client or "", characterName = character, factionName = character and "Horde" or nil, wowProjectID = 99 } }
  c.FRIENDS[id] = info
  for i, f in ipairs(c.BN) do if f.bnetAccountID == id then c.BN[i] = info return info end end
  c.BN[#c.BN + 1] = info
  return info
end
local function Legacy(guid, name, connected)
  for _, f in ipairs(c.LEGACY) do if f.guid == guid then f.connected = connected return end end
  c.LEGACY[#c.LEGACY + 1] = { guid = guid, name = name, connected = connected }
end
local function Report() return (D.Build()) end
local function Has(text, needle) return text:find(needle, 1, true) ~= nil end
local function Section(report, title)
  local from = report:find("== " .. title .. " ==", 1, true)
  assert(from, "section " .. title)
  local to = report:find("\n== ", from + 5, true) or #report
  return report:sub(from, to)
end

LoggedIn()

---------------------------------------------------------------------------
-- Off by default: nothing listens, nothing is recorded.
---------------------------------------------------------------------------
assert(D and not D.Tracing(), "tracing is off by default")
assert(DiagFrame() == nil, "no frame or event registration exists before tracing starts")
Friend(1, "Aria", "Thrall", "Horde")
Online(1); Settle(); Finish(Card().anim)
assert(#D.Records() == 0 and Has(Report(), "(no records)"), "nothing recorded while off")
assert(Has(Report(), "never started this session"), "the report says why there is nothing")

---------------------------------------------------------------------------
-- The report section: what the module is doing, with no names.
---------------------------------------------------------------------------
local friend = Section(Report(), "Friend notifications")
assert(Has(friend, "Friend notifications: configured on, initialized yes, ready"), friend)
assert(Has(friend, "friend login card: on; chime: on (follows the SFX volume)"), friend)
assert(Has(friend, "required events: 8 of 8 registered"), friend)
assert(Has(friend, "would show a login now: yes"), friend)
assert(Has(friend, "game's own pop-up: event-removed; TwichUI has taken the event from it: yes"), friend)
assert(Has(friend, "initial presence snapshot: not used by this module"), "the report does not invent a snapshot")
assert(Has(friend, "trace baseline: none (tracing is off)"), friend)
assert(Has(friend, "logins skipped or let go since the game started: none"), friend)
c.CV.showToastOnline = false
friend = Section(Report(), "Friend notifications")
assert(Has(friend, "would show a login now: no (game-online-friends-off)"), friend)
assert(Has(friend, "unavailable (game-online-friends-off)"), friend)
c.CV.showToastOnline = true
M.friendLogin = false; F.Refresh()
friend = Section(Report(), "Friend notifications")
assert(Has(friend, "configured off") and Has(friend, "off") and Has(friend, "required events: not wanted while the card is off"), friend)
assert(not Has(friend, ", ready") and Has(friend, "initialized n/a, off"), "a disabled module is not called ready")
M.friendLogin = true; F.Refresh()
-- Enabled but not actually listening: not called healthy.
R.frame:UnregisterEvent("CVAR_UPDATE")
friend = Section(Report(), "Friend notifications")
assert(Has(friend, "required events: 7 of 8 registered; missing: CVAR_UPDATE") and Has(friend, "unavailable (event-not-registered)"), friend)
R.frame:RegisterEvent("CVAR_UPDATE")
assert(Has(Section(Report(), "Friend notifications"), ", ready"), "and ready again once it is")
-- The card cannot be built.
local style = R.ChronicleStyle
R.ChronicleStyle = nil
assert(Has(Section(Report(), "Friend notifications"), "unavailable (card-cannot-be-built)"))
R.ChronicleStyle = style

---------------------------------------------------------------------------
-- Synthetic tests are separate from real events.
---------------------------------------------------------------------------
Sounds()
local out = Cmd("test friend")
assert(Card().shown and Card().title.text == "A Friend" and Sounds() == 1, "synthetic card and its chime")
assert(Has(out, "says nothing about whether real friend events arrive"), out)
Finish(Card().anim)
out = Cmd("test sound")
assert(#c.SOUNDS == 1 and c.SOUNDS[1].channel == "SFX" and Has(out, "accepted"), out)
Sounds()
c.TwichUIDB.ui = c.TwichUIDB.ui or {}; c.TwichUIDB.ui.friendLoginChannel = "Master"
Cmd("test sound"); assert(c.SOUNDS[1].channel == "Master", "tests the configured channel"); Sounds()
c.TwichUIDB.ui.friendLoginChannel = nil
c.PlaySoundFile = function() return false end
assert(Has(Cmd("test sound"), "refused"), "a refused sound is reported as refused")
c.PlaySoundFile = function(path, channel) c.SOUNDS[#c.SOUNDS + 1] = { path = path, channel = channel }; return true end
c.SOUNDKIT = { UI_BNET_TOAST = 1234 }
local stock
c.PlaySound = function(id) stock = id return true end
assert(Has(Cmd("test sound stock"), "accepted") and stock == 1234, "the game's own sound, for comparison")
assert(#D.Records() == 0, "synthetic tests are not recorded while not tracing")
assert(Has(Cmd("test"), "usage: /tui diagnostics test friend"), "a bare test says what the tests are")

---------------------------------------------------------------------------
-- The old command still leads somewhere.
---------------------------------------------------------------------------
c.SlashCmdList.TWICHUI("frienddiag status"); out = Said()
assert(Has(out, "has moved: use /tui diagnostics") and Has(out, "Friend notifications: configured on"), out)
c.SlashCmdList.TWICHUI("frienddiag test logout"); assert(Has(Said(), "no TwichUI logout card"))

---------------------------------------------------------------------------
-- Tracing: real events, interpreted, anonymous.
---------------------------------------------------------------------------
BN(1, false, "", nil); BN(2, true, "App", nil)
Legacy("Player-1-AAA", "Charfriendone", false)
out = Cmd("start")
assert(Has(out, "tracing is ON for up to 15 minutes") and D.Tracing(), out)
assert(Has(Cmd("start"), "already on"), "turning it on twice is harmless")
local df = DiagFrame()
for _, e in ipairs({ "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED", "FRIENDLIST_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_BN_INLINE_TOAST_ALERT", "BN_CONNECTED", "PLAYER_ENTERING_WORLD" }) do
  assert(df.events[e], "listens for " .. e)
end
assert(Has(Section(Report(), "Friend notifications"), "trace baseline: 2 Battle.net friends and 1 character friends"), "baseline taken once, when asked")
local function Real(event, ...) Fire(event, ...) end

-- A real account login, through the module and the diagnostics.
BN(1, true, "WoW", "Thrall")
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
local r = Report()
assert(Has(r, "friend-event BN_FRIEND_ACCOUNT_ONLINE F1 (account-online companion=n info=ok name=y online=y client=WoW proj=99 char=y fac=y)"), r)
assert(Has(r, "friend event F1") and Has(r, "friend queued F1") and Has(r, "friend card:shown (1)"), r)
assert(Has(r, "friend sound:requested (accepted)"), r)
Finish(Card().anim)

-- Privacy: no names, tags, ids or character names anywhere in the report, status or chat output.
for _, secret in ipairs({ "Secretname", "Tag1", "Aria", "Thrall", "Charfriendone", "Player-1-AAA", "9999" }) do
  assert(not Has(r, secret) and not Has(Cmd("status"), secret), "report is anonymous: " .. secret)
end

-- Skip reasons are recorded, and counted.
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, true)
assert(Has(Report(), "friend skip F1 (companion-app)"), "mobile app skipped, with the reason")
c.COMBAT = true
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
for _ = 1, 6 do RunLongTimers(2); FlushTimers() end
c.NOW = c.NOW + 11   -- past the time a login is worth waiting for
RunLongTimers(2); FlushTimers()
r = Report()
assert(Has(r, "friend submitted (1)") and Has(r, "friend dropped (expired)"), r)
assert(Has(r, "[c,none]"), "every record carries the combat state")
assert(Has(r, "notify queued (friend)") and Has(r, "notify dropped (friend expired)"), "the coordinator's decisions are traced too")
c.COMBAT = false
c.CV.showToastOnline = false
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false)
assert(Has(Report(), "friend skip F1 (game-online-friends-off)"))
c.CV.showToastOnline = true
Fire("PLAYER_ENTERING_WORLD", true, false)
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false)
assert(Has(Report(), "friend skip F1 (login-quiet)"), "quiet time after login is recorded")
c.NOW = c.NOW + 6
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false)
assert(Has(Report(), "friend skip F1 (duplicate)"), "a repeat while waiting is recorded as a duplicate")
Settle(); Finish(Card().anim)
c.FRIENDS[77] = nil
Real("BN_FRIEND_ACCOUNT_ONLINE", 77, false); for _ = 1, 6 do RunLongTimers(2); FlushTimers() end
r = Report()
assert(Has(r, "info=none") and Has(r, "friend look:gave-up (no-info)"), "an unresolvable friend is reported as such")
assert(not Card().shown)
friend = Section(r, "Friend notifications")
assert(Has(friend, "skip:companion-app x1") and Has(friend, "skip:login-quiet x1") and Has(friend, "skip:duplicate x1")
  and Has(friend, "look:gave-up:no-info x1") and Has(friend, "dropped:expired x1"), friend)

-- Offline and entering/leaving WoW while staying on Battle.net, from the info-changed event.
BN(2, true, "App", nil)
Real("BN_FRIEND_INFO_CHANGED", 2)
assert(not Has(Report(), "first-seen"), "no change since the baseline: not a transition")
assert(Has(Report(), "BN_FRIEND_INFO_CHANGED F2 (no change"), "recorded as a quiet no-change line")
BN(2, true, "WoW", "Arthas")
Real("BN_FRIEND_INFO_CHANGED", 2)
r = Report()
assert(Has(r, "F2 (entered-wow(App>WoW),character-changed"), r)
assert(not Has(r, "Arthas"), "no character names")
BN(2, true, "WoW", "Sylvanas")
Real("BN_FRIEND_INFO_CHANGED", 2)
assert(Has(Report(), "F2 (character-changed"), "changing characters while staying in WoW")
BN(2, true, "App", nil)
Real("BN_FRIEND_INFO_CHANGED", 2)
assert(Has(Report(), "left-wow(WoW>App)"), "leaving WoW while staying on Battle.net")
BN(2, false, "", nil)
Real("BN_FRIEND_INFO_CHANGED", 2)
assert(Has(Report(), "went-offline"), "going offline")
Real("BN_FRIEND_ACCOUNT_OFFLINE", 2, false)
assert(Has(Report(), "BN_FRIEND_ACCOUNT_OFFLINE F2 (account-offline"), "offline event recorded (the module shows no card for it)")
assert(not Card().shown, "no logout card exists")
Real("BN_FRIEND_INFO_CHANGED", 55)
assert(Has(Report(), "friend not resolvable from its list position"), "an unstable list position resolves to nothing, not to someone else")

-- Character friends: from the list's own update, and the system line.
Legacy("Player-1-AAA", "Charfriendone", true)
Real("FRIENDLIST_UPDATE")
assert(Has(Report(), "FRIENDLIST_UPDATE (character friends: C1 went-online"), Report())
c.NOW = c.NOW + 5
Real("FRIENDLIST_UPDATE"); Real("FRIENDLIST_UPDATE"); Real("FRIENDLIST_UPDATE")
r = Report()
assert(Has(r, "no character friend changed online state) x3"), "repeats are one record with a count")
Legacy("Player-1-AAA", "Charfriendone", false)
Real("FRIENDLIST_UPDATE")
assert(Has(Report(), "C1 went-offline"))
Real("CHAT_MSG_SYSTEM", "|Hplayer:Charfriendone|h[Charfriendone]|h has come online.")
Real("CHAT_MSG_SYSTEM", "Charfriendone has gone offline.")
Real("CHAT_MSG_SYSTEM", "You have 5 unread mail.")
r = Report()
assert(Has(r, "character-friend-online system line") and Has(r, "character-friend-offline system line"), r)
assert(not Has(r, "unread mail") and not Has(r, "Charfriendone"), "unrelated system text and names are never kept")
Real("CHAT_MSG_SYSTEM", SECRET)
assert(Has(Report(), "text unreadable (secret value)"), "secret text is not touched")
Real("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_ONLINE", "Whoever")
Real("CHAT_MSG_BN_INLINE_TOAST_ALERT", "FRIEND_REQUEST", "Whoever")
r = Report()
assert(Has(r, "CHAT_MSG_BN_INLINE_TOAST_ALERT (FRIEND_ONLINE)") and Has(r, "(other-kind)") and not Has(r, "Whoever"), r)
c.LEGACY[1].guid = SECRET
Real("FRIENDLIST_UPDATE")
assert(Has(Report(), "1 unreadable") or Has(Report(), "no character friend changed"), "secret guid does not break it")

---------------------------------------------------------------------------
-- A synthetic test while tracing is marked, and a real event is not.
---------------------------------------------------------------------------
Cmd("test friend"); Finish(Card().anim)
r = Report()
assert(Has(r, "SYNTHETIC  friend card-test (made-up friend; not a real event)"), r)
assert(Has(r, "SYNTHETIC  notify queued (friend)"), "the preview's coordinator records are synthetic too")
local real = 0
for _, rec in ipairs(D.Records()) do if rec.code == "BN_FRIEND_ACCOUNT_ONLINE" and rec.synthetic then real = real + 1 end end
assert(real == 0, "real events are never marked synthetic")

---------------------------------------------------------------------------
-- Bounded.
---------------------------------------------------------------------------
for _ = 1, 500 do Real("PLAYER_LEAVING_WORLD"); c.NOW = c.NOW + 3 end
local n = #D.Records()
assert(n <= D.MAX_RECORDS, "at most " .. D.MAX_RECORDS .. " records kept, not " .. n)
assert(Has(Report(), "PLAYER_LEAVING_WORLD") and not Has(Report(), "trace-started"), "the oldest were dropped")
assert(Has(Report(), "oldest records dropped to stay within the limit"), "and the report says so")

---------------------------------------------------------------------------
-- Stop, clear, and the real feature afterward.
---------------------------------------------------------------------------
Cmd("stop")
assert(not D.Tracing() and next(df.events) == nil, "stopping unregisters everything")
local before = #D.Records()
Real("BN_FRIEND_ACCOUNT_ONLINE", 1, false)
assert(#D.Records() == before, "nothing recorded once stopped")
assert(Has(Report(), "tracing: off (stopped by you)"), "the report says it was stopped")
Cmd("start"); Cmd("clear")
assert(D.Tracing() and #D.Records() == 1 and D.Records()[1].code == "records-cleared", "clear keeps tracing on and leaves only a note")
Cmd("stop"); Cmd("clear")
assert(not D.Tracing() and #D.Records() == 0 and Has(Report(), "(no records)"), "clear empties the record")
Cmd("start")
Real("BN_FRIEND_ACCOUNT_ONLINE", 2, false)
assert(Has(Report(), "BN_FRIEND_ACCOUNT_ONLINE F2 (account-online") and not Has(Report(), "F3"), "labels start over after a trace ends (the baseline numbers the two friends again)")
Cmd("stop"); Cmd("clear")
Fire("PLAYER_LEAVING_WORLD"); Fire("PLAYER_ENTERING_WORLD", false, false)
BN(1, true, "WoW", "Thrall")
Online(1); Settle()
assert(Card().shown, "the card works the same with the diagnostics cleared")
Finish(Card().anim)

---------------------------------------------------------------------------
-- The window.
---------------------------------------------------------------------------
-- Skinned like the sharing window when EllesmereUI's toolkit is there.
local skinned = {}
R.S = setmetatable({}, { __index = function(_, kind) return function(obj, ...) skinned[kind] = (skinned[kind] or 0) + 1 end end })
Cmd("")
for _, kind in ipairs({ "Shell", "Panel", "Button", "StateButtonLabel", "CloseButton", "Font" }) do
  assert(skinned[kind], "the window is skinned with EllesmereUI's " .. kind)
end
assert(skinned.Button == 3 and skinned.Shell == 1, "three buttons, one shell")
R.S = nil
local win
for _, f in ipairs(fakes) do if f.name == "TwichUIDiagnosticsWindow" then win = f end end
assert(win and win.shown and c.UISpecialFrames[1] == "TwichUIDiagnosticsWindow", "window opens and Esc closes it")
assert(Has(win.edit.text, "TwichUI diagnostic report") and Has(win.edit.text, "report format: 1"), "the report is in the copy box")
assert(Has(win.status.text, "Tracing is off"), win.status.text)
assert(win.toggle.text == "Start tracing")
D.Start()
assert(Has(win.status.text, "Tracing is ON") and win.toggle.text == "Stop tracing", "the window follows the tracing state")
D.Stop("manual"); D.Clear()

-- Opened before EllesmereUI hands over its toolkit: plain at first, skinned when it arrives.
do
  local chunk = assert(loadfile(ROOT .. "diag/Window.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  R.DiagWindow.Show()
  assert(#R.skinCallbacks >= 1, "waits for the toolkit")
  local late = {}
  R.S = setmetatable({}, { __index = function(_, kind) return function() late[kind] = true end end })
  for _, fn in ipairs(R.skinCallbacks) do fn(R.S) end
  assert(late.Shell and late.Panel and late.Button and late.CloseButton and late.Font, "skinned once it arrives")
  R.S = nil
end

---------------------------------------------------------------------------
-- A game that refuses an event name: reported, and the rest still work.
---------------------------------------------------------------------------
c.CreateFrame = function(_, name) local f = Fake(); f.name = name; f.refuse = { CHAT_MSG_BN_INLINE_TOAST_ALERT = true }; return f end
for _, f in ipairs({ "diag/Diagnostics.lua", "diag/Friends.lua" }) do   -- a second service, so its frame is made now
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local D2 = R.Diag
D2.Start()
assert(D2.Status().refused == 1 and Has(D2.Build(), "diag event-refused (CHAT_MSG_BN_INLINE_TOAST_ALERT)"), "a refused event is reported")
D2.Stop("manual"); D2.Clear()

-- The module itself is unchanged when the game's pop-up is absent or the card cannot be built.
local capable = R.ChronicleStyle
R.ChronicleStyle = nil
toast.events.BN_FRIEND_ACCOUNT_ONLINE = true
Fire("PLAYER_LOGIN")
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "without the Chronicle look there is no card, so the game's pop-up is left alone")
assert(F.State().capable == false)
R.ChronicleStyle = capable
Fire("PLAYER_LOGIN")
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "and taken again once the card can be built")

print("FRIEND DIAGNOSTICS TEST PASSED")
