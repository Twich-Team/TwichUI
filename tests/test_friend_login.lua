dofile(TESTS .. "harness.lua")
-- Battle.net friend login card: what it shows (name, faction mark, character), that it takes only
-- the friend-online event from the game's own pop-up and gives it back, that the game's Social
-- options and the mobile app are respected, nothing at login or in combat, one card for a burst,
-- waiting for other cards, Edit Mode placement, Reduced motion, and off meaning off.
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
c.CreateFrame = function() return Fake() end
c.UIParent = Fake()
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

for _, f in ipairs({"chronicle/Style.lua", "modules/Arrival.lua", "modules/FriendLogin.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local F = R.FriendLogin
local M = c.TwichUIDB.modules
R.Arrival.IsShowing = function() return c.ARRIVAL end

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
local function Listening(event) return R.frame.events[event] == true end
-- A real login, then past its quiet time.
local function LoggedIn() Fire("PLAYER_ENTERING_WORLD", true, false); c.NOW = c.NOW + 6 end

assert(M.friendLogin == true, "on by default")

---------------------------------------------------------------------------
-- The game's pop-up: only the online event is taken from it.
---------------------------------------------------------------------------
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "the online pop-up is taken")
assert(toast.events.BN_FRIEND_ACCOUNT_OFFLINE and toast.events.BN_CUSTOM_MESSAGE_CHANGED, "its other toasts are left alone")
assert(Listening("BN_FRIEND_ACCOUNT_ONLINE"), "TwichUI listens in its place")

---------------------------------------------------------------------------
-- Quiet at login and reload.
---------------------------------------------------------------------------
Friend(1, "Aria", "Thrall", "Horde")
Fire("PLAYER_ENTERING_WORLD", true, false)
Online(1); Settle()
assert(not Card(), "nothing right after login")
c.NOW = c.NOW + 4; Online(1); Settle()
assert(not Card(), "still quiet")
Fire("PLAYER_ENTERING_WORLD", false, true)
c.NOW = c.NOW + 4; Online(1); Settle()
assert(not Card(), "a reload is quiet too")
LoggedIn()

---------------------------------------------------------------------------
-- One friend: name, faction mark, character. No frame, no clicks, no sound.
---------------------------------------------------------------------------
Online(1)
assert(not Card(), "not at once: the friend's details arrive just after the event")
Settle()
local card = Card()
assert(card and card.shown and card.anim.plays == 1, "card shown and settling in")
assert(card.title.text == "Aria", card.title.text)
assert(card.sub.text == "Online as Thrall", card.sub.text)
assert(card.icon.shown and card.icon.atlas == "UI-HUD-UnitFrame-Player-PVP-HordeIcon", "the Horde mark")
assert(card.icon.h == 22 and card.icon.w == 44, "the mark keeps its proportions")
assert(card.mouse == false, "takes no clicks")
assert(rawget(card, "close") == nil and rawget(card, "SetBackdrop") == nil, "no close button, no backdrop")
local p = card.point
assert(p[1] == "BOTTOMLEFT" and p[2] == c.UIParent and p[3] == "BOTTOMLEFT" and p[4] == 16 and p[5] == 300, "lower left by default")
assert(card.setBack.x == -28 and card.flow.x == 28 and card.setBack.y == 0 and card.flow.y == 0, "flows in from the left, not up")
assert(card.title.point[1] == "TOPLEFT" and card.rule.point[1] == "TOPLEFT" and card.sub.point[1] == "TOPLEFT", "everything lines up on the left edge")
assert(card.title.point[2] == 51 and card.rule.point[4] == -51, "the name sits beside the mark; the rule starts level with the mark")
assert(card.fadeOut.delay and card.fadeOut.delay > 0)
assert(#c.SOUNDS == 1, "one chime with the card")
assert(c.SOUNDS[1].path == [[Interface\AddOns\!!!TwichUI\media\sounds\TwichUI_Notification.mp3]], c.SOUNDS[1].path)
assert(c.SOUNDS[1].channel == "SFX", "follows the Sound Effects volume by default")
Sounds()
Finish(card.anim)
assert(not card.shown, "gone after it fades")
assert(Sounds() == 0, "nothing more when it fades")

-- Alliance, and the picture missing from the client: the emblem file instead.
Friend(2, "Brann", "Muradin", "Alliance")
c.ATLAS = false
Online(2); Settle()
assert(card.shown and card.icon.texture == [[Interface\Timer\Alliance-Logo]] and card.icon.w == 22, "Alliance emblem as the fallback")
Finish(card.anim)
c.ATLAS = true
Online(2); Settle()
assert(card.icon.atlas == "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "the Alliance mark")
Finish(card.anim)

-- No faction given, or not a faction: no mark, and no gap beside the name.
Friend(3, "Cleo", nil, nil)
Online(3); Settle()
assert(card.shown and not card.icon.shown and card.sub.text == "Online", "no faction, no character")
assert(card.title.point[2] == 0 and card.rule.point[4] == 0, "with no mark the name starts at the left edge")
Finish(card.anim)
Friend(3, "Cleo", "Pandaren", "Neutral")
Online(3); Settle()
assert(card.shown and not card.icon.shown and card.sub.text == "Online as Pandaren", "Neutral gets no mark")
Finish(card.anim)
Friend(1, "Aria", "Thrall", "Horde")
Online(1); Settle()
assert(card.icon.shown and card.title.point[2] == 44 + 7 and card.rule.point[4] == -(44 + 7), "the name moves over to make room for the mark")
Finish(card.anim)

-- Text from the game is shown as plain text, and a name that can't be read is never shown.
Friend(4, "Pipe|cffff0000Red", "Bad|rName", "Horde")
Online(4); Settle()
assert(card.title.text == "Pipe||cffff0000Red" and card.sub.text == "Online as Bad||rName", "escape codes are not interpreted")
Finish(card.anim)
Friend(5, "", "Nameless", "Horde")   -- no account name and a BattleTag with nothing before the number
Online(5); for _ = 1, 6 do RunLongTimers(2); FlushTimers() end
assert(not card.shown, "no name, no card")
c.FRIENDS[5] = { accountName = "", battleTag = "Tagged#4321", gameAccountInfo = {} }
Online(5); Settle()
assert(card.title.text == "Tagged", "falls back to the BattleTag's name, without the number")
Finish(card.anim)
c.FRIENDS[5] = { accountName = SECRET, battleTag = SECRET, gameAccountInfo = { characterName = SECRET, factionName = SECRET } }
Online(5); Settle()
assert(not card.shown, "secret values are never shown")
RunLongTimers(2); FlushTimers(); RunLongTimers(2); FlushTimers(); RunLongTimers(2); FlushTimers(); RunLongTimers(2); FlushTimers()
assert(not card.shown, "and not retried forever")
c.FRIENDS[5] = nil

-- The mobile app, a missing friend, junk ids.
Online(1, true); Settle()
assert(not card.shown, "no card for the Battle.net mobile app")
Online(99); for _ = 1, 6 do RunLongTimers(2); FlushTimers() end
assert(not card.shown, "a friend the game can't give details for shows nothing")
Online(nil); Online("x"); Online(SECRET); Settle()
assert(not card.shown, "junk ids are ignored")

---------------------------------------------------------------------------
-- A burst: one card.
---------------------------------------------------------------------------
Online(1); Online(2); Online(1); Online(3)
Settle()
assert(card.shown and card.anim.plays > 0 and card.title.text == "Aria", "the first friend leads")
assert(card.sub.text == "and 2 others online", card.sub.text)
assert(Sounds() >= 1)
Finish(card.anim)
Online(1); Online(2); Settle()
assert(card.sub.text == "and 1 other online", card.sub.text)
Finish(card.anim)

---------------------------------------------------------------------------
-- The chime: once per card, on the chosen channel, off when switched off.
---------------------------------------------------------------------------
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
Sounds()
Online(1); Online(2); Online(3); Settle()
assert(card.shown and Sounds() == 1, "a burst gets one chime")
Finish(card.anim)
for _, channel in ipairs({ "Dialog", "Ambience", "Master", "SFX" }) do
  c.TwichUIDB.ui.friendLoginChannel = channel
  Online(1); Settle()
  assert(#c.SOUNDS == 1 and c.SOUNDS[1].channel == channel, "plays on " .. channel)
  Sounds(); Finish(card.anim)
end
for _, bad in ipairs({ "Music", 3, "", true }) do
  c.TwichUIDB.ui.friendLoginChannel = bad
  assert(F.SoundChannel() == "SFX", "an unknown saved channel falls back to Sound Effects")
end
c.TwichUIDB.ui.friendLoginChannel = nil
assert(#F.CHANNELS == 4 and F.CHANNELS[1].key == F.CHANNEL_DEFAULT)
M.friendLoginSound = false
Online(1); Settle()
assert(card.shown and Sounds() == 0, "the card still shows, silently, with the chime off")
Finish(card.anim)
F.PlaySound()
assert(Sounds() == 1, "the options' Hear button plays it either way")
M.friendLoginSound = true
c.PlaySoundFile = nil
Online(1); Settle()
assert(card.shown, "no sound API, no problem")
Finish(card.anim)
c.PlaySoundFile = function(path, channel) c.SOUNDS[#c.SOUNDS + 1] = { path = path, channel = channel }; return true end

---------------------------------------------------------------------------
-- The game's Social options still rule.
---------------------------------------------------------------------------
c.CV.showToastOnline = false
Online(1); Settle()
assert(not card.shown, "Online Friends off: nothing")
c.CV.showToastOnline, c.CV.showToastWindow = true, false
Online(1); Settle()
assert(not card.shown and Sounds() == 0, "Show Toast Window off: nothing, and no chime")
c.CV.showToastWindow = true

---------------------------------------------------------------------------
-- In the way: combat, the zone card, banners, its own card still up.
---------------------------------------------------------------------------
c.COMBAT = true
Online(1); Settle()
assert(not card.shown, "not in combat")
c.COMBAT = false
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown, "shown once combat ends, within a few looks")
Fire("PLAYER_REGEN_DISABLED")
assert(not card.shown, "makes way for combat")

c.ARRIVAL = true
Online(1); Settle()
assert(not card.shown, "waits for the zone card")
c.ARRIVAL = false
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown, "shown once the zone card has gone")
Finish(card.anim)

c.TOAST = true
Online(2); Settle()
assert(not card.shown, "waits for a banner")
c.TOAST = false
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown and card.title.text == "Brann")
-- another friend while the card is up: it waits for the card to finish rather than replacing it
Online(1); Settle()
assert(card.title.text == "Brann", "the open card is not replaced")
Finish(card.anim)
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown and card.title.text == "Aria", "then the next one")
Finish(card.anim)

-- Gives up rather than showing minutes late.
c.COMBAT = true
Online(1); Settle()
for _ = 1, 8 do RunLongTimers(2); FlushTimers() end
c.COMBAT = false
for _ = 1, 3 do RunLongTimers(2); FlushTimers() end
assert(not card.shown, "a login long past is not announced")

-- Leaving the world drops what was waiting and takes the card down.
Online(1); Fire("PLAYER_LEAVING_WORLD"); Settle()
assert(not card.shown, "a loading screen drops a waiting card")
Online(2); Settle()
assert(card.shown)
Fire("PLAYER_LEAVING_WORLD")
assert(not card.shown)

-- Reduced motion: it only fades.
M.arrivalReducedMotion = true
Online(1); Settle()
assert(card.shown and card.setBack.x == 0 and card.flow.x == 0, "no movement")
M.arrivalReducedMotion = false
Finish(card.anim)

---------------------------------------------------------------------------
-- The game giving the event back to its pop-up.
---------------------------------------------------------------------------
toast.events.BN_FRIEND_ACCOUNT_ONLINE = true    -- as when the game's options load
Fire("PLAYER_LOGIN")
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "taken again at login")
toast.events.BN_FRIEND_ACCOUNT_ONLINE = true    -- as when the Social options change
Fire("CVAR_UPDATE", "showToastOnline", "1")
FlushTimers()
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "taken again when the Social options change")
toast.events.BN_FRIEND_ACCOUNT_ONLINE = true
Fire("CVAR_UPDATE", "graphicsQuality", "3")
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "other options are none of its business")
Online(1)
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "and if it is back when a friend arrives, it is taken at once")
Settle(); Finish(card.anim)
toast.events.BN_FRIEND_ACCOUNT_ONLINE = nil
-- no pop-up frame at all (not loaded): the card still works
c.BNToastFrame = nil
Online(2); Settle()
assert(card.shown, "works without the game's pop-up frame")
Finish(card.anim)
c.BNToastFrame = toast

---------------------------------------------------------------------------
-- Edit Mode: an outline to drag while it is open; the place is kept and used.
---------------------------------------------------------------------------
local enter, exit = c.EventRegistry.callbacks["EditMode.Enter"], c.EventRegistry.callbacks["EditMode.Exit"]
assert(enter and exit, "listens for Edit Mode")
local function Mover() for _, f in ipairs(fakes) do if f.scripts.OnDragStart then return f end end end
assert(not Mover(), "nothing made until Edit Mode opens")
c.EDITING = true; enter()
local mover = Mover()
assert(mover and mover.shown and mover.point[1] == "BOTTOMLEFT" and mover.point[4] == 16 and mover.point[5] == 300, "outline at the card's place")
mover.GetLeft = function() return 200.4 end
mover.GetBottom = function() return 120.6 end
mover.scripts.OnDragStart(mover); mover.scripts.OnDragStop(mover)
local saved = c.TwichUIDB.ui.friendLoginPlace
assert(saved.x == 200 and saved.y == 121, "kept as an offset from the lower left")
assert(mover.point[4] == 200 and mover.point[5] == 121 and card.point[4] == 200 and card.point[5] == 121, "the outline and the card move together")
mover.scripts.OnLeave()
exit()
assert(not mover.shown, "outline gone when Edit Mode closes")
c.EDITING = false
Online(1); Settle()
assert(card.shown and card.point[4] == 200 and card.point[5] == 121, "the card appears where it was put")
Finish(card.anim)
c.EDITING = true; enter()
mover.scripts.OnMouseUp(mover, "LeftButton")
assert(c.TwichUIDB.ui.friendLoginPlace, "a left click changes nothing")
mover.scripts.OnMouseUp(mover, "RightButton")
assert(c.TwichUIDB.ui.friendLoginPlace == nil and mover.point[4] == 16 and mover.point[5] == 300, "right-click: back to the default")
exit(); c.EDITING = false
for _, bad in ipairs({ "x", { x = "1", y = 2 }, { x = 0 / 0, y = 0 }, { x = 1e9, y = 0 }, { y = 100 } }) do
  c.TwichUIDB.ui.friendLoginPlace = bad
  local x, y = F.Position()
  assert(x == 16 and y == 300, "bad saved place ignored")
end
c.TwichUIDB.ui.friendLoginPlace = nil

---------------------------------------------------------------------------
-- /tui friend: a made-up sample, with your own faction.
---------------------------------------------------------------------------
c.COMBAT = true
c.SlashCmdList.TWICHUI("friend")
assert(card.shown and card.title.text == "A Friend" and card.sub.text == "Online as Sample", "the preview skips the combat check")
assert(card.icon.shown and card.icon.atlas == "UI-HUD-UnitFrame-Player-PVP-AllianceIcon", "your own faction")
assert(Sounds() >= 1, "the preview chimes too, so the volume can be judged")
c.COMBAT = false
Finish(card.anim)

---------------------------------------------------------------------------
-- Off: the game's pop-up gets the event back, nothing listened for, nothing shown.
---------------------------------------------------------------------------
M.friendLogin = false; F.Refresh()
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "the game's pop-up is back")
assert(not Listening("BN_FRIEND_ACCOUNT_ONLINE") and not Listening("CVAR_UPDATE"), "nothing listened for")
Fire("PLAYER_LOGIN"); Fire("CVAR_UPDATE", "showToastOnline", "1"); FlushTimers()
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "and the game's pop-up is not touched again")
Online(1); Settle()
assert(not card.shown, "off means off")
F.Refresh(); F.Refresh()
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "refreshing again changes nothing")
-- on again takes it again; and off while the card is up takes the card down
M.friendLogin = true; F.Refresh()
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE and Listening("BN_FRIEND_ACCOUNT_ONLINE"), "on again")
Online(1); Settle()
assert(card.shown)
M.friendLogin = false; F.Refresh()
assert(not card.shown, "off while it is up takes it down")
-- Off when the player's own Social options had it off: the event is not forced back on.
M.friendLogin = true; F.Refresh()
c.CV.showToastOnline = false
M.friendLogin = false; F.Refresh()
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "the game's own option is respected when giving it back")
c.CV.showToastOnline = true
-- Off when TwichUI never took anything: nothing is registered on the game's behalf.
toast.events.BN_FRIEND_ACCOUNT_ONLINE = nil
F.Refresh()
assert(not toast.events.BN_FRIEND_ACCOUNT_ONLINE, "nothing given back that was never taken")
M.friendLogin = true; F.Refresh()

-- A new install gets it on; an existing explicit opt-out survives.
local d = MakeClient("Pat", {"!!!TwichUI"})
d.TwichUIDB = { modules = { friendLogin = false } }
d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(d.TwichUIDB.modules.friendLogin == false, "saved false is kept")

print("FRIEND LOGIN TEST PASSED")
