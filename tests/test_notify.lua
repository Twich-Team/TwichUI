dofile(TESTS .. "harness.lua")
-- Notification coordinator (modules/Notify.lua) and the settings previews.
-- Part 1 uses stand-in displays to pin down the rules: ordering, priority, overlap, duplicates,
-- expiry, capacity, outside checks, loading screens, replacing, the safety timer, yielding, previews.
-- Part 2 uses the four real displays: previews are isolated from gameplay state, sounds come
-- once and at display time, and the displays take turns only where they overlap.
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
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "RegisterEvent" then return function(s, e) s.events[e] = true end end
    if k == "UnregisterEvent" then return function(s, e) s.events[e] = nil end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetStringWidth" then return function(s) return #(s.text or "") * 8 end end
    if k == "SetWidth" then return function(s, v) s.width = v end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h end end
    if k == "GetWidth" then return function(s) return s.w or s.width or 0 end end
    if k == "SetHeight" then return function(s, v) s.height = v end end
    if k == "EnableMouse" then return function(s, v) s.mouse = v end end
    if k == "SetFrameStrata" then return function(s, v) s.strata = v end end
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
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
c.GameTooltip = Fake()
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
function c.EventRegistry:UnregisterCallback(event, owner) assert(owner); self.callbacks[event] = nil end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }

c.NOW = 1000
c.GetTime = function() return c.NOW end
c.time = function() return 1700000000 end
local ERRORS = {}
c.geterrorhandler = function() return function(e) ERRORS[#ERRORS + 1] = tostring(e) end end
c.COMBAT, c.TOAST, c.TAXI = false, false, false
c.InCombatLockdown = function() return c.COMBAT end
c.UnitOnTaxi = function() return c.TAXI end
c.EventToastManagerFrame = Fake()
c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end

-- Zone text for the zone card.
c.ZONE, c.SUB = "Elwynn Forest", ""
c.GetZoneText = function() return c.ZONE end
c.GetSubZoneText = function() return c.SUB end
c.IsInInstance = function() return false, "none" end
c.GetInstanceInfo = function() return "", "none" end
c.C_PvP = { GetZonePVPInfo = function() return "friendly", false, "Alliance" end }
c.FACTION_CONTROLLED_TERRITORY = "(%s Territory)"
c.ZoneTextFrame, c.SubZoneTextFrame = Fake(), Fake()
c.ZoneText_Clear = function() end

-- The game's friend pop-up, options and Battle.net.
local toast = { events = { BN_FRIEND_ACCOUNT_ONLINE = true, BN_FRIEND_ACCOUNT_OFFLINE = true } }
function toast:IsEventRegistered(e) return self.events[e] == true end
function toast:RegisterEvent(e) self.events[e] = true end
function toast:UnregisterEvent(e) self.events[e] = nil end
c.BNToastFrame = toast
c.GetCVarBool = function() return true end
c.UnitFactionGroup = function() return "Alliance", "Alliance" end
c.C_Texture = { GetAtlasInfo = function() return { width = 40, height = 20 } end }
c.FRIENDS, c.BN_LOOKUPS = {}, 0
c.C_BattleNet = { GetAccountInfoByID = function(id) c.BN_LOOKUPS = c.BN_LOOKUPS + 1; return c.FRIENDS[id] end }
local function Friend(id, name, character)
  c.FRIENDS[id] = { accountName = name, battleTag = name .. "#1", gameAccountInfo = { characterName = character, factionName = "Horde" } }
end
c.SOUNDS = {}
c.PlaySoundFile = function(path, channel) c.SOUNDS[#c.SOUNDS + 1] = { path = path, channel = channel }; return true end

-- The player starts with these four displays all switched off: previews must work anyway.
c.TwichUIDB = { modules = { arrival = false, arrivalSubzones = false, arrivalDungeons = false,
  trainingNotice = false, friendLogin = false, welcomeBack = false } }

for _, f in ipairs({"chronicle/Style.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/WelcomeBack.lua",
    "modules/Training.lua", "modules/FriendLogin.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local N, M = R.Notify, c.TwichUIDB.modules
local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(fakes) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
-- Back to a quiet world with nothing waiting or showing (as after a loading screen).
local function Clean()
  Fire("PLAYER_LEAVING_WORLD"); Fire("PLAYER_ENTERING_WORLD", false, false)
  local s = N.State()
  assert(#s.waiting == 0 and #s.active == 0 and s.inWorld, "clean slate")
end
local function Overlap(...) return N.Overlap(...) end

---------------------------------------------------------------------------
-- Part 1: the rules, with stand-in displays
---------------------------------------------------------------------------
assert(not N.Submit({ kind = "nothing-registered", id = "x" }), "an unknown kind is refused")
assert(select(2, N.Submit({ kind = "nothing-registered", id = "x" })) == "unknown")

local log, dismissed, drops = {}, {}, {}
local function Kind(name, rect, extra)
  local spec = {
    label = name,
    show = function(p, ctx) log[#log + 1] = name .. ":" .. tostring(p.id) .. (ctx.preview and "*" or ""); return true end,
    dismiss = function() dismissed[#dismissed + 1] = name; N.Finished(name) end,
    bounds = function() return rect[1], rect[2], rect[3], rect[4] end,
    hold = function() return 1 end,
    sample = function() return { id = "sample" } end,
  }
  for k, v in pairs(extra or {}) do spec[k] = v end
  N.Register(name, spec)
end
local function Send(kind, id, opts)
  local request = { kind = kind, id = id, payload = { id = id }, onDrop = function(why) drops[#drops + 1] = kind .. ":" .. id .. "=" .. why end }
  for k, v in pairs(opts or {}) do request[k] = v end
  return N.Submit(request)
end
local function Shown() return table.concat(log, " ") end
local function Reset() Clean(); log, dismissed, drops = {}, {}, {} end   -- clean first: it dismisses what the last case left showing

Kind("top1", { 0, 500, 400, 600 })
Kind("near", { 410, 500, 800, 600 })       -- 10 away from top1: inside the 12 pixels of padding
Kind("near2", { 420, 500, 800, 600 })      -- overlaps near
Kind("far", { -500, 500, -50, 600 })       -- 50 away from top1 on the other side
Kind("side", { 2000, 0, 2300, 100 })

-- Overlap: padded, and an unknown rectangle overlaps everything.
assert(Overlap({ 0, 0, 10, 10 }, { 5, 5, 20, 20 }))
assert(Overlap({ 0, 0, 10, 10 }, { 20, 0, 30, 10 }, 12), "within the padding")
assert(not Overlap({ 0, 0, 10, 10 }, { 40, 0, 50, 10 }, 12), "beyond the padding")
assert(not Overlap({ 0, 0, 10, 10 }, { 0, 40, 10, 50 }, 12), "vertical gap too")
assert(Overlap(nil, { 0, 0, 1, 1 }) and Overlap({ 0, 0, 1, 1 }, nil), "unknown overlaps everything")

-- Separate places show together; the same place takes turns, first come first served.
Reset()
assert(Send("top1", "a")); assert(Shown() == "top1:a")
assert(Send("near", "b")); assert(Shown() == "top1:a", "overlapping (with padding) waits")
assert(Send("far", "c")); assert(Shown() == "top1:a far:c", "a card elsewhere does not wait for the first, nor for the one waiting")
assert(Send("side", "d")); assert(Shown() == "top1:a far:c side:d")
assert(Send("near2", "e")); assert(Shown() == "top1:a far:c side:d", "behind near, which it overlaps")
N.Finished("top1")
assert(Shown() == "top1:a far:c side:d near:b", "the first waiter goes first")
N.Finished("near")
assert(Shown() == "top1:a far:c side:d near:b near2:e", "then the next")
assert(#N.State().waiting == 0)

-- A waiting notice never jumps ahead of an earlier one it would overlap, even when its own place is free.
Reset()
Send("top1", "a"); Send("near", "b")
Send("near2", "c")
N.Finished("top1")
assert(Shown() == "top1:a near:b", "near2 stays behind near")

-- Priority beats arrival order; equal priority is first come first served.
Reset()
Send("top1", "a")
Send("near", "low", { priority = N.PRIORITY.low })
Send("near2", "normal")
N.Finished("top1")
assert(Shown() == "top1:a near2:normal", "normal before low, though low came first")
N.Finished("near2")
assert(Shown() == "top1:a near2:normal near:low")

-- Duplicates: same kind and identity while waiting or showing. Nothing is remembered afterwards.
Reset()
assert(Send("top1", "a"))
local ok, why = Send("top1", "a"); assert(not ok and why == "duplicate", "showing")
assert(Send("near", "q")); ok, why = Send("near", "q"); assert(not ok and why == "duplicate", "waiting")
assert(Send("near", "r"), "a different event of the same kind")
assert(Send("side", "a"), "the same identity under another kind")
N.Finished("top1"); N.Finished("near"); N.Finished("near")
assert(Send("top1", "a") and Shown():sub(-6) == "top1:a", "once done, the same identity can be shown again")
assert(Send("top1", "a", { preview = true }), "a preview is not a duplicate of a real one")
Reset()
Send("top1", "x", { preview = true }); ok, why = Send("top1", "x", { preview = true })
assert(not ok and why == "duplicate", "previews are duplicates of each other")

-- Expiry: a notice that waited too long is never shown; so is one that says it no longer applies.
Reset()
Send("top1", "a")
Send("near", "old", { ttl = 5 })
Send("near2", "stale", { valid = function() return false end })
Send("far", "fine")
c.NOW = c.NOW + 6; N.Poke()
assert(table.concat(drops, " "):find("near:old=expired", 1, true), "expired is reported")
assert(table.concat(drops, " "):find("near2:stale=stale", 1, true), "no longer valid is reported")
N.Finished("top1")
assert(Shown() == "top1:a far:fine", "neither was shown late")
-- Expired claims nothing: its identity is free again.
Reset()
Send("top1", "a"); Send("near", "k", { ttl = 1 }); c.NOW = c.NOW + 2
assert(Send("near", "k"), "an expired notice does not make a new one a duplicate")

-- Capacity: six wait; a seventh makes the oldest of the lowest priority go; one that ranks below all is refused.
Reset()
Send("top1", "a")
for i = 1, 6 do assert(Send("near", "n" .. i)) end
assert(#N.State().waiting == 6)
assert(Send("near", "n7"))
local waiting = table.concat(N.State().waiting, " ")
assert(#N.State().waiting == 6 and not waiting:find("near:n1 ", 1, true) and waiting:find("near:n7", 1, true), waiting)
assert(table.concat(drops, " "):find("near:n1=full", 1, true), "the oldest made room")
ok, why = Send("near", "late", { priority = N.PRIORITY.low })
assert(not ok and why == "full", "below everything waiting: refused")
assert(#N.State().waiting == 6)
-- A higher priority newcomer takes a low one's place.
Reset()
Send("top1", "a")
Send("near", "lo", { priority = N.PRIORITY.low })
for i = 1, 5 do Send("near", "n" .. i) end
assert(Send("near", "hi"))
assert(not table.concat(N.State().waiting, " "):find("near:lo", 1, true), "the low one made room")

-- Outside checks (combat, banners): wait, look again on a bounded timer, give up when too late.
local READY = false
Kind("gated", { 3000, 0, 3300, 100 }, { ready = function() return READY end })
Reset()
Send("gated", "g")
assert(Shown() == "" and #N.State().waiting == 1, "held back")
RunLongTimers(2); assert(Shown() == "", "still held back")
READY = true; RunLongTimers(2)
assert(Shown() == "gated:g", "shown once ready")
Reset(); READY = false
Send("gated", "h"); c.NOW = c.NOW + 11; RunLongTimers(2)
READY = true; RunLongTimers(2)
assert(Shown() == "" and table.concat(drops, " "):find("gated:h=expired", 1, true), "too late to be news")
-- A preview is shown on request, whatever the outside checks say.
Reset(); READY = false
Send("gated", "p", { preview = true })
assert(Shown() == "gated:p*", "previews skip outside checks")

-- Loading screens: waiting notices and showing cards go, nothing is replayed; sent during loading, they wait for the world.
Reset()
Send("top1", "a"); Send("near", "b"); Send("far", "c")
Fire("PLAYER_LEAVING_WORLD")
assert(#N.State().waiting == 0 and #N.State().active == 0 and not N.State().inWorld)
assert(table.concat(drops, " "):find("near:b=loading", 1, true), "waiting ones are reported dropped")
log = {}
Send("side", "during")
assert(Shown() == "" and #N.State().waiting == 1, "waits while loading")
Fire("PLAYER_ENTERING_WORLD", false, false)
assert(Shown() == "side:during", "and shows once in the world: nothing older comes back")

-- Replacing: a newer notice takes the place of an older waiting or showing one of its kind.
Reset()
Send("top1", "a", { replace = true })
Send("top1", "b", { replace = true })
assert(Shown() == "top1:a top1:b" and dismissed[1] == "top1", "the showing one is stopped for the newer")
Reset()
Send("top1", "blocker"); Send("near", "x", { replace = true }); Send("near", "y", { replace = true })
assert(table.concat(drops, " "):find("near:x=replaced", 1, true) and #N.State().waiting == 1)
N.Finished("top1")
assert(Shown() == "top1:blocker near:y", "only the latest")

-- A card that never reports back does not hold its place for ever.
local stuck = 0
Kind("stuck", { 4000, 0, 4300, 100 }, { dismiss = function() stuck = stuck + 1 end })
Reset()
Send("stuck", "one"); Send("stuck", "two")
assert(Shown() == "stuck:one", "the second waits for the first")
RunLongTimers(3); assert(Shown() == "stuck:one", "not before it has run its course")
RunLongTimers(4)
assert(stuck == 1 and Shown() == "stuck:one stuck:two", "freed by the safety timer")

-- Yielding: Welcome Back-style cards give way to a real notice that needs their place, only then.
Kind("bookmark", { 0, 500, 400, 600 }, { yields = true })
Reset()
Send("bookmark", "b")
Send("side", "elsewhere")
assert(#dismissed == 0, "a notice in another place leaves it alone")
Send("top1", "t", { preview = true })
assert(#dismissed == 0 and Shown() == "bookmark:b side:elsewhere", "a preview does not take its place")
Reset()
Send("bookmark", "b")
Send("top1", "t")
assert(dismissed[1] == "bookmark" and Shown() == "bookmark:b top1:t", "a real notice takes its place at once")
Reset()
Send("top1", "t"); Send("bookmark", "b")
assert(Shown() == "top1:t", "it does not push a real notice aside")
N.Finished("top1")
assert(Shown() == "top1:t bookmark:b", "it waits its turn")

-- Previews: lowest rank, never delay or clear a real notice, give way to one.
Reset()
Send("top1", "real")
Send("near", "pv", { preview = true })
assert(Shown() == "top1:real", "a preview waits for a real card in its place")
N.Finished("top1")
assert(Shown() == "top1:real near:pv*")
Send("top1", "real2")
assert(dismissed[#dismissed] == "near" and Shown():sub(-10) == "top1:real2", "a real notice dismisses an overlapping preview")
Reset()
Send("far", "pv", { preview = true })
Send("top1", "real")
assert(#dismissed == 0 and Shown() == "far:pv* top1:real", "a preview elsewhere is left alone")
Reset()
Send("top1", "real")
Send("near", "waiting-pv", { preview = true })
Send("side", "real2")
assert(table.concat(drops, " "):find("near:waiting-pv=real-event", 1, true), "a real event drops waiting previews")
-- Clearing previews leaves real cards alone.
Reset()
Send("top1", "real"); Send("far", "pv", { preview = true }); Send("near", "pv2", { preview = true })
N.ClearPreviews()
assert(dismissed[1] == "far" and #N.State().waiting == 0 and N.State().active[1] == "top1:real" and #N.State().active == 1, table.concat(N.State().active, ","))
-- Combat clears previews; the listener exists only while there are previews.
Reset()
assert(not R.frame.events.PLAYER_REGEN_DISABLED, "no listener without previews")
Send("far", "pv", { preview = true })
assert(R.frame.events.PLAYER_REGEN_DISABLED, "listening while a preview exists")
Fire("PLAYER_REGEN_DISABLED")
assert(dismissed[#dismissed] == "far" and not R.frame.events.PLAYER_REGEN_DISABLED, "combat clears previews and the listener goes")
-- Cancel (a feature turned off) takes real notices only.
Reset()
Send("top1", "real"); Send("near", "waiting-real"); Send("far", "pv", { preview = true })
N.Cancel("top1"); N.Cancel("near"); N.Cancel("far")
assert(#N.State().waiting == 0 and N.State().active[1] == "far:pv" and #N.State().active == 1, "previews stay, real ones go")

-- Sound rule.
assert(N.SoundWanted(false, true) and not N.SoundWanted(false, false), "real: the feature's own setting")
c.TwichUIDB.ui = nil
assert(not N.SoundWanted(true, true) and not N.PreviewSounds(), "previews are silent by default")
c.TwichUIDB.ui = { previewSounds = true }
assert(N.SoundWanted(true, true) and not N.SoundWanted(true, false), "previews follow both settings when allowed")
c.TwichUIDB.ui = nil

-- A display that fails or declines to start does not stop the ones after it.
Kind("broken", { 5000, 0, 5300, 100 }, { show = function() error("boom") end })
Kind("decline", { 5000, 0, 5300, 100 }, { show = function() return false end })
Reset()
Send("broken", "x"); Send("decline", "y"); Send("side", "ok")
assert(#N.State().active == 1 and Shown() == "side:ok", "neither is left holding its place")
assert(#ERRORS == 1 and ERRORS[1]:find("boom", 1, true), "the error was reported, not swallowed")
ERRORS = {}

Reset()

---------------------------------------------------------------------------
-- Part 2: the real displays
---------------------------------------------------------------------------
local A, T, F, B = R.Arrival, R.Training, R.FriendLogin, R.WelcomeBack
local function Find(test) for _, f in ipairs(fakes) do if test(f) then return f end end end
local function ArrivalCard() return Find(function(f) return rawget(f, "pvp") ~= nil end) end
local function FriendCard() return Find(function(f) return rawget(f, "icon") ~= nil and rawget(f, "sub") ~= nil and rawget(f, "pvp") == nil end) end
local function TrainingCard() return Find(function(f) return rawget(f, "foot") ~= nil and rawget(f, "rowFrames") ~= nil end) end
local function WelcomeCard() return Find(function(f) return rawget(f, "open") ~= nil end) end
local function Group(card) return Find(function(f) return rawget(f, "owner") == card and rawget(f, "plays") ~= nil end) end
local function Finish(card) local g = Group(card); g.playing = false; g.scripts.OnFinished(g) end
local function Sounds() local n = #c.SOUNDS; c.SOUNDS = {}; return n end
local function Settle() FlushTimers(); RunLongTimers(2); FlushTimers() end

-- A readable copy of a table, to compare saved data before and after.
local function Dump(t, seen)
  if type(t) ~= "table" then return tostring(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]; if v == nil then v = t[tonumber(k)] end
    parts[#parts + 1] = k .. "=" .. Dump(v)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local C = R.Chronicle
local savedBefore = Dump(c.TwichUIDB)
local chronicleBefore = C.Count()
local eventsBefore = {}
for e in pairs(R.frame.events) do eventsBefore[e] = true end
c.BN_LOOKUPS = 0

-- Each preview shows its own card, from made-up details, with every feature switched off.
Clean()
local kinds = {}
for _, info in ipairs(N.Kinds()) do kinds[info.kind] = info end
for _, k in ipairs({ "arrival", "training", "friend", "welcome" }) do assert(kinds[k] and kinds[k].sample, k .. " has a preview") end
assert(kinds.arrival.label == "Zone arrival" and kinds.training.label == "Training available"
  and kinds.friend.label == "Friend login" and kinds.welcome.label == "Chronicle welcome back")

assert(N.Preview("arrival"))
local card = ArrivalCard()
assert(card.shown and card.title.text == "Sample Vale" and card.strata == "FULLSCREEN_DIALOG", "zone card, drawn above the Settings panel")
assert(Group(card).playing, "with its real animation")
Finish(card); assert(not card.shown)
assert(N.Preview("training"))
card = TrainingCard()
assert(card.shown and #card.rows == 3 and card.rows[1].name == "Sample Strike" and card.strata == "FULLSCREEN_DIALOG", "training card with sample spells")
assert(not card.mouse, "it takes no clicks")
Finish(card)
assert(N.Preview("friend"))
card = FriendCard()
assert(card.shown and card.title.text == "A Friend" and card.sub.text == "Online as Sample" and card.strata == "FULLSCREEN_DIALOG")
Finish(card)
assert(N.Preview("welcome"))
card = WelcomeCard()
assert(card.shown and card.line.text:find("Sample Vale", 1, true) and card.line.text:find("2 hours ago", 1, true) and card.strata == "FULLSCREEN_DIALOG")
assert(card.open.mouse == false, "its link takes no clicks")
local opened = 0
R.ChronicleWindow = { Show = function() opened = opened + 1 end, Refresh = function() end }
card.open.scripts.OnClick()
assert(opened == 0 and card.shown, "clicking it does nothing")
Finish(card)

-- Nothing changed: no setting, saved place or Chronicle entry; no event registered for the features; no friend asked about.
assert(Dump(c.TwichUIDB) == savedBefore, "saved variables are untouched")
assert(M.arrival == false and M.trainingNotice == false and M.friendLogin == false and M.welcomeBack == false, "features stay off")
assert(C.Count() == chronicleBefore, "no Chronicle entry")
for e in pairs(R.frame.events) do assert(eventsBefore[e], e .. " was registered by a preview") end
for e in pairs(eventsBefore) do assert(R.frame.events[e], e .. " was dropped by a preview") end
assert(not R.frame.events.BN_FRIEND_ACCOUNT_ONLINE, "the friend event is not registered by a preview")   -- (the Chronicle itself listens for zones and levels)
assert(c.BN_LOOKUPS == 0, "no friend was looked up")
assert(F.State().waiting == 0, "no friend queued")
assert(Sounds() == 0, "silent by default")
assert(toast.events.BN_FRIEND_ACCOUNT_ONLINE, "the game's own pop-up is left alone")
assert(#N.State().waiting == 0 and #N.State().active == 0, "and nothing is left behind")

-- Sounds: only when previews are allowed them and the chime is on; once per card.
c.TwichUIDB.ui = {}
N.Preview("friend"); Finish(FriendCard())
assert(Sounds() == 0, "off by default")
c.TwichUIDB.ui.previewSounds = true
N.Preview("friend"); Finish(FriendCard())
assert(Sounds() == 1, "once with it on")
for _, k in ipairs({ "arrival", "training", "welcome" }) do
  N.Preview(k)
end
assert(Sounds() == 0, "the cards that have no sound stay silent")
N.ClearPreviews()
M.friendLoginSound = false
N.Preview("friend"); Finish(FriendCard())
assert(Sounds() == 0, "the chime off means off, as for a real card")
M.friendLoginSound = true
c.TwichUIDB.ui.previewSounds = nil
-- The chime only when the card appears, not when it waits.
c.TwichUIDB.ui.previewSounds = true
N.Preview("friend"); Sounds()
N.Submit({ kind = "friend", id = "again", preview = true, payload = F and { entries = { { name = "Second" } } } })
assert(Sounds() == 0, "a second preview waits behind the first, and is silent while it waits")
Finish(FriendCard())
assert(FriendCard().title.text == "Second" and Sounds() == 1, "and sounds when it appears")
Finish(FriendCard())
c.TwichUIDB.ui.previewSounds = nil

-- Clear previews: animations stop, cards go, queue empties.
N.Preview("arrival"); N.Preview("friend"); N.Preview("training")
local ac, fc = ArrivalCard(), FriendCard()
assert(ac.shown and fc.shown)
N.ClearPreviews()
assert(not ac.shown and not Group(ac).playing and not fc.shown and not Group(fc).playing and not TrainingCard().shown)
assert(#N.State().waiting == 0 and #N.State().active == 0)

-- The coordinated sequence: a fixed set; the repeat is dropped; separate places show together, the rest take turns.
local sent, dropped = N.PreviewSequence()
assert(sent == 4 and dropped == 1, sent .. "/" .. dropped)
assert(ArrivalCard().shown and FriendCard().shown, "zone and friend cards show together")
assert(not TrainingCard().shown and not WelcomeCard().shown, "training and welcome wait")
Finish(ArrivalCard())
assert(TrainingCard().shown and not WelcomeCard().shown, "training takes the top next")
Finish(TrainingCard())
assert(WelcomeCard().shown, "then the welcome card")
Finish(FriendCard()); Finish(WelcomeCard())
assert(#N.State().waiting == 0 and #N.State().active == 0, "all done, nothing left")
-- Running it again starts from scratch.
N.PreviewSequence(); N.PreviewSequence()
assert(ArrivalCard().shown and #N.State().waiting == 2, "restarted cleanly")
N.ClearPreviews()

-- Real events take precedence over previews, and previews never use up what a real event needs.
M.arrival, M.trainingNotice, M.friendLogin = true, true, true
A.Refresh(); T.Refresh(); F.Refresh()
Fire("PLAYER_ENTERING_WORLD", true, false)
c.NOW = c.NOW + 6
Friend(1, "Aria", "Thrall")
Friend(2, "Brann", "Muradin")
Friend(3, "Cairne", "Baine")
N.Preview("training")
assert(TrainingCard().shown, "a preview is up")
c.ZONE = "Sample Vale"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
assert(ArrivalCard().shown and ArrivalCard().title.text == "Sample Vale" and ArrivalCard().strata == "LOW",
  "a real arrival (even to a place with the preview's name) is shown: the preview used nothing up")
assert(not TrainingCard().shown, "and the preview in its way gave way")
Finish(ArrivalCard())
N.Preview("friend")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
card = FriendCard()
assert(card.shown and card.title.text == "Aria" and card.strata == "LOW", "a real friend login replaces the friend preview")
assert(Sounds() == 1, "with its chime, once")
Finish(card)

-- Moving a card changes who it waits for; sound waits for the display, not the queue.
c.ZONE = "Westfall"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
assert(ArrivalCard().shown)
N.Submit({ kind = "training", id = "level:5", payload = { rows = { { id = 1, level = 5, name = "Real Spell", icon = "x" } } } })
assert(not TrainingCard().shown, "the real training card waits for the zone card at the same place")
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
c.TwichUIDB.ui.trainingPosition = { x = 0, y = -600 }
N.Poke()
assert(TrainingCard().shown and ArrivalCard().shown, "moved apart, they show together")
Finish(TrainingCard()); Finish(ArrivalCard())
c.TwichUIDB.ui.trainingPosition = nil

-- Sound at display time: friend cards queue behind each other; each chimes when it appears, none when dropped.
Sounds()
Fire("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
assert(FriendCard().shown and Sounds() == 1)
Fire("BN_FRIEND_ACCOUNT_ONLINE", 2, false); Settle()
assert(FriendCard().title.text == "Aria" and Sounds() == 0, "the second waits, silently")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 2, false); Settle()
assert(#N.State().waiting == 1 and Sounds() == 0, "a repeat is dropped, silently")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 3, false); Settle()
assert(#N.State().waiting == 2)
c.NOW = c.NOW + 11; N.Poke()
assert(#N.State().waiting == 0, "waited too long: both expired")
Finish(FriendCard())
assert(not FriendCard().shown and Sounds() == 0, "nothing late, and no chime for what expired")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 2, false); Settle()
assert(FriendCard().title.text == "Brann" and Sounds() == 1, "a later login is its own event")
Finish(FriendCard())

-- Several friend logins backed up, then a loading screen: none comes back.
Fire("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
Fire("BN_FRIEND_ACCOUNT_ONLINE", 2, false); Settle()
Fire("BN_FRIEND_ACCOUNT_ONLINE", 3, false); Settle()
assert(#N.State().waiting == 2)
Fire("PLAYER_LEAVING_WORLD"); Fire("PLAYER_ENTERING_WORLD", false, false); Settle()
assert(not FriendCard().shown and #N.State().waiting == 0 and Sounds() == 1, "no backlog after the loading screen (one chime: the card that was up)")

-- Welcome Back: a bookmark that yields, never a block.
N.Submit({ kind = "welcome", id = "login", priority = N.PRIORITY.low, payload = { zone = "Westfall", ago = "1 hour ago" } })
assert(WelcomeCard().shown and WelcomeCard().strata == "LOW")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 1, false); Settle()
assert(FriendCard().shown and WelcomeCard().shown, "it sits beside a friend card")
Finish(FriendCard())
N.Submit({ kind = "training", id = "level:6", payload = { rows = { { id = 1, level = 6, name = "Real Spell", icon = "x" } } } })
assert(TrainingCard().shown and not WelcomeCard().shown, "a real card needing its place takes it at once")
Finish(TrainingCard())
-- The other way round, it waits and goes last.
N.Submit({ kind = "training", id = "level:7", payload = { rows = { { id = 1, level = 7, name = "Real Spell", icon = "x" } } } })
N.Submit({ kind = "welcome", id = "login", priority = N.PRIORITY.low, payload = { zone = "Westfall", ago = "1 hour ago" } })
assert(TrainingCard().shown and not WelcomeCard().shown, "it does not push a real card aside")
Finish(TrainingCard())
assert(WelcomeCard().shown, "and has its turn after")
Finish(WelcomeCard())

-- A zone card waiting behind another card: only the latest place is shown, and one you have left is dropped.
N.Submit({ kind = "training", id = "level:9", payload = { rows = { { id = 1, level = 9, name = "Real Spell", icon = "x" } } } })
assert(TrainingCard().shown)
c.ZONE = "Redridge Mountains"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
assert(not ArrivalCard().shown and #N.State().waiting == 1, "the zone card waits for the training card")
c.ZONE = "Lakeshire"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
assert(#N.State().waiting == 1, "the newer place replaces the older one waiting")
Finish(TrainingCard())
assert(ArrivalCard().shown and ArrivalCard().title.text == "Lakeshire", "only the latest place is shown")
Finish(ArrivalCard())
N.Submit({ kind = "training", id = "level:10", payload = { rows = { { id = 1, level = 10, name = "Real Spell", icon = "x" } } } })
c.ZONE = "Duskwood"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
assert(#N.State().waiting == 1)
Fire("PLAYER_CONTROL_LOST")   -- a flight begins: the place waiting is no longer where you will be
Finish(TrainingCard())
assert(not ArrivalCard().shown and #N.State().waiting == 0, "a place already left is not announced")
Fire("PLAYER_CONTROL_GAINED"); Settle()
Finish(ArrivalCard())

-- Turning a feature off while its notice is showing or waiting.
c.ZONE = "Stranglethorn Vale"; Fire("ZONE_CHANGED_NEW_AREA"); Settle()
N.Submit({ kind = "training", id = "level:8", payload = { rows = { { id = 1, level = 8, name = "Real Spell", icon = "x" } } } })
assert(ArrivalCard().shown and not TrainingCard().shown)
M.trainingNotice = false; T.Refresh()
assert(#N.State().waiting == 0, "a waiting notice goes with its feature")
Finish(ArrivalCard())
assert(not TrainingCard().shown, "and is not shown later")
Fire("BN_FRIEND_ACCOUNT_ONLINE", 3, false); Settle()
assert(FriendCard().shown)
M.friendLogin = false; F.Refresh()
assert(not FriendCard().shown and #N.State().active == 0, "a showing card goes with its feature")
M.arrival = false; A.Refresh()

-- Nothing transient was saved.
local saved = Dump(c.TwichUIDB)
assert(not saved:find("queue", 1, true) and not saved:find("waiting", 1, true) and not saved:find("notice", 1, true), "no queue in saved data")
assert(#ERRORS == 0, table.concat(ERRORS, "\n"))

print("NOTIFY TEST PASSED")
