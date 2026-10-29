-- Cozy Sleeping Bag guide: the invitation (guides/CozyBagOffer.lua, CozyBagNotice.lua, CozyBagButton.lua).
-- The rule (CozyBagState.Offer), the per-character record, when the card is asked for and shown, the launcher button (click,
-- drag, place, hide, preview), the settings choices, and what is shared. A fake client stands in for the game's quest log,
-- items, notification coordinator and frames, so this checks our logic, not the game: the in-game checks are listed in
-- docs/cozy-sleeping-bag.md.
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end

---------------------------------------------------------------------------
-- A fake game
---------------------------------------------------------------------------
local function Obj()
  local o = { text = "", shown = true }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s)
      local was = s.shown
      s.shown = true
      if not was then for _, h in ipairs((s.hooks or {}).OnShow or {}) do h(s) end end
    end end
    if k == "Hide" then return function(s)
      local was = s.shown
      s.shown = false
      if was then for _, h in ipairs((s.hooks or {}).OnHide or {}) do h(s) end end
    end end
    if k == "SetShown" then return function(s, v) if v then s:Show() else s:Hide() end end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return function() return 60 end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetWidth" then return function(s) return s.width or 372 end end
    if k == "GetHeight" then return function(s) return s.height or 100 end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetWidth" then return function(s, w) s.width = w end end
    if k == "SetHeight" then return function(s, h) s.height = h end end
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "GetScale" or k == "GetEffectiveScale" then return function(s) return s.scale or 1 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "ClearAllPoints" then return function(s) s.points = {} end end
    if k == "SetPoint" then return function(s, ...) s.points = s.points or {}; s.points[#s.points + 1] = { ... } end end
    if k == "GetCenter" then return function(s) return s.center and s.center[1] or 512, s.center and s.center[2] or 384 end end
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return Obj() end end
    if k == "ScrollBar" then
      local sb = Obj(); rawset(sb, "ThumbTexture", false); rawset(sb, "ScrollUpButton", false); rawset(sb, "ScrollDownButton", false)
      rawset(t, k, sb); return sb
    end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end

local MAPS = { [1436] = "Westfall", [1413] = "The Barrens", [1442] = "Stonetalon Mountains", [1432] = "Loch Modan",
  [1417] = "Arathi Highlands", [1424] = "Hillsbrad Foothills" }

local FILES = { "Onboarding.lua", "chronicle/Style.lua", "Look.lua", "Icons.lua", "modules/Interact.lua", "pins/Pins.lua", "modules/Notify.lua",
  "modules/NotifyLook.lua", "modules/Arrival.lua", "guides/CozyBagData.lua", "guides/CozyBagState.lua", "guides/CozyBag.lua",
  "guides/CozyBagOffer.lua", "guides/CozyBagNotice.lua", "guides/CozyBagButton.lua", "guides/CozyBagWindow.lua" }

-- A client with the guide, the offer and the notification coordinator loaded. quests: { done, log, ready } sets.
-- opts: level (20), owned (the item count), db (the saved variables of an earlier session of the same character),
-- fails (the guide window's Show errors).
local function Client(name, faction, quests, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  local realCreate = c.CreateFrame
  c.FRAMES = {}
  c.CreateFrame = function(kind, fname)
    local o = Obj()
    local base = realCreate()
    for k, v in pairs(base) do if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end end
    rawset(o, "kindOf", kind)
    c.FRAMES[#c.FRAMES + 1] = o
    if fname then c[fname] = o end
    return o
  end
  c.tinsert = table.insert
  c.UISpecialFrames = {}
  c.UIParent = Obj()
  rawset(c.UIParent, "width", 1024); rawset(c.UIParent, "height", 768)
  c.GameTooltip = Obj(); c.GameTooltip_Hide = function() end
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function() return {} end
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.UnitFactionGroup = function() return faction end
  c.LEVEL = opts.level or 20
  c.UnitLevel = function() return c.LEVEL end
  c.OWNED = opts.owned or 0
  c.C_Item = { GetItemCount = function() return c.OWNED end }
  c.QUESTS = quests
  c.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return c.QUESTS.done[id] == true end,
    IsOnQuest = function(id) return c.QUESTS.log[id] == true end,
    ReadyForTurnIn = function(id) return (c.QUESTS.ready or {})[id] == true end,
  }
  c.C_Map = { GetMapInfo = function(id) return MAPS[id] and { mapID = id, name = MAPS[id], parentMapID = 0 } or nil end }
  c.issecretvalue = nil
  -- anything that would leave the machine or start a route is counted
  c.OUT = { chat = 0, addon = 0, waypoint = 0 }
  c.SendChatMessage = function() c.OUT.chat = c.OUT.chat + 1 end
  c.C_ChatInfo = { SendAddonMessage = function() c.OUT.addon = c.OUT.addon + 1 return 0 end, RegisterAddonMessagePrefix = function() return true end }
  c.C_Map.SetUserWaypoint = function() c.OUT.waypoint = c.OUT.waypoint + 1 end
  c.PRINTED = {}
  c.print = function(s) c.PRINTED[#c.PRINTED + 1] = tostring(s) end
  c.SOUNDS = 0
  c.PlaySound = function() c.SOUNDS = c.SOUNDS + 1 end
  c.PlaySoundFile = function() c.SOUNDS = c.SOUNDS + 1 return true end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if opts.fails then
    c.FAULTS = 0
    c.geterrorhandler = function() return function() c.FAULTS = c.FAULTS + 1 end end   -- the expected fault is counted, not printed
    c.TwichUI.CozyBagWindow.Show = function() error("boom") end
  end
  c.TwichUIDB = opts.db or { modules = { partyPins = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.R = c.TwichUI
  return c
end

local function Set(...) local s = {} for _, id in ipairs({ ... }) do s[id] = true end return s end
local function Q(done, log, ready) return { done = Set(unpack(done or {})), log = Set(unpack(log or {})), ready = Set(unpack(ready or {})) } end
local ALL = { 79008, 79192, 79980, 79974, 79975, 79976 }

-- Enters the world with the quest log answering at once. The history is trusted, the first look is asked for after 0.5 s.
local function Login(c)
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  c.FireEvent("QUEST_LOG_UPDATE")
  FlushTimers()
end

-- Lets the card's delay pass and the coordinator show it.
local function Wait(c) RunLongTimers(10); FlushTimers() end
local function Shown(c) return c.R.CozyBagNotice.IsShowing() end
local function Button(c) return c.TwichUICozyBagButton end
local function ButtonShown(c) local b = Button(c) return b ~= nil and b.shown == true end
local function Rec(c) local all = c.TwichUIDB.ui and c.TwichUIDB.ui.cozyBagOffer return all and all["Player-1-" .. (c.UnitName and c.UnitName() or "")] end
local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- 1. The rule: pure, with the facts handed in
---------------------------------------------------------------------------
do
  local c = Client("Rule", "Alliance", Q())
  local ST, D = c.R.CozyBagState, c.R.CozyBagData
  local function Offer(facts)
    facts.historyReady = facts.historyReady == nil and true or facts.historyReady
    return ST.Offer(D, facts)
  end
  Check(D.level == 14, "the unlock level is the guide's own figure")
  local ok, why = Offer({ level = 13, complete = false }); Check(not ok and why == "level", "level 13: nothing")
  ok, why = Offer({ level = 14, complete = false }); Check(ok and why == "available", "level 14: available")
  ok, why = Offer({ level = 40, complete = false }); Check(ok, "a higher level is available too")
  ok, why = Offer({ level = nil, complete = false }); Check(not ok and why == "level", "an unknown level offers nothing")
  ok, why = Offer({ level = 14 / 0 * 0, complete = false }); Check(not ok, "a NaN level offers nothing")
  ok, why = Offer({ level = 20, historyReady = false }); Check(not ok and why == "loading", "history not loaded: nothing, and not 'done'")
  ok, why = Offer({ level = 20, complete = nil }); Check(not ok and why == "unknown", "could not conclude: nothing")
  ok, why = Offer({ level = 20, complete = true }); Check(not ok and why == "complete", "finished chain: nothing")
  ok, why = Offer({ level = 20, complete = false, owned = true }); Check(not ok and why == "owned", "owning the item: nothing")
  ok, why = Offer({ level = 20, complete = false, owned = false }); Check(ok, "not owning proves nothing against the offer")
  ok, why = Offer({ level = 20, complete = false, acquired = true }); Check(not ok and why == "acquired", "the record of having got it: nothing")
  ok, why = Offer({ level = 5, historyReady = false, owned = true }); Check(not ok and why == "owned", "ownership outranks level and history")
end

---------------------------------------------------------------------------
-- 2. Level 13: nothing at all
---------------------------------------------------------------------------
do
  local c = Client("Low", "Alliance", Q(), { level = 13 })
  Login(c); Wait(c)
  local O = c.R.CozyBagOffer
  Check(not Shown(c) and not Button(c), "level 13: no card and no button frame is even made")
  Check(O.Status().reason == "level" and not O.Announced() and not O.Hidden(), "level 13: nothing recorded")
  Check(Rec(c) == nil, "level 13: no record is created by looking")
  Check(c.R.Notify.State().waiting[1] == nil, "level 13: nothing queued")
end

---------------------------------------------------------------------------
-- 3. Level 14 at login (catch-up): one card, after the delay; the button; told once
---------------------------------------------------------------------------
local db14
do
  local c = Client("Fourteen", "Alliance", Q({ 79008 }), { level = 14 })
  Login(c)
  local O = c.R.CozyBagOffer
  Check(O.Status().offer, "level 14 with the chain unfinished is available")
  Check(ButtonShown(c), "the launcher is shown")
  Check(not Shown(c) and not O.Announced(), "the card waits (behind the cards a login brings)")
  Check(Rec(c) == nil, "asking for the card records nothing")
  Wait(c)
  Check(Shown(c), "the card shows after the delay")
  Check(O.Announced(), "...and only now is the character marked as told")
  local first = c.R.Notify.Snapshot().shown.cozybag
  Check(first == 1, "shown once")
  c.FireEvent("PLAYER_LEVEL_UP", 15); FlushTimers(); Wait(c)
  Check(c.R.Notify.Snapshot().shown.cozybag == 1, "another level never repeats it")
  Check(c.OUT.chat == 0 and c.OUT.addon == 0 and c.OUT.waypoint == 0 and c.SOUNDS == 0, "nothing sent, no route, no sound")
  Check(not c.R.CozyBagWindow.IsShown(), "the guide did not open by itself")
  db14 = c.TwichUIDB

  -- a second session of the same character: the button, never the card
  local d = Client("Fourteen", "Alliance", Q({ 79008 }), { level = 14, db = db14 })
  Login(d); Wait(d)
  Check(ButtonShown(d) and not Shown(d), "the next login: the button is back, the card is not")
  Check(d.R.Notify.Snapshot().shown.cozybag == nil, "...and it was not even asked for twice")
  -- another character of the same account is told on its own
  local e = Client("Other", "Alliance", Q(), { level = 14, db = db14 })
  Login(e); Wait(e)
  Check(Shown(e) and ButtonShown(e), "another character has its own record")
end

---------------------------------------------------------------------------
-- 4. Crossing the threshold (a level-up, a jump over it)
---------------------------------------------------------------------------
do
  local c = Client("Cross", "Horde", Q(), { level = 13 })
  Login(c); Wait(c)
  Check(not ButtonShown(c) and not Shown(c), "13: nothing yet")
  c.FireEvent("PLAYER_LEVEL_UP", 14); FlushTimers()      -- UnitLevel has not moved yet; the event's level is used
  Check(c.R.CozyBagOffer.Status().offer, "the event's level counts before UnitLevel moves")
  Check(ButtonShown(c), "the button appears at once")
  Check(not Shown(c), "the card waits for the training card and the others")
  Wait(c)
  Check(Shown(c) and c.R.CozyBagOffer.Announced(), "then the card shows, once")
  Check(c.R.Notify.Snapshot().shown.cozybag == 1)

  local j = Client("Jump", "Horde", Q(), { level = 12 })
  Login(j); Wait(j)
  j.LEVEL = 16; j.FireEvent("PLAYER_LEVEL_UP", 16); FlushTimers(); Wait(j)
  Check(Shown(j) and ButtonShown(j), "crossing 14 by jumping past it still offers it")
end

---------------------------------------------------------------------------
-- 5. Done or owned: no offer, and it stays that way
---------------------------------------------------------------------------
do
  local c = Client("Done", "Alliance", Q(ALL))
  Login(c); Wait(c)
  Check(not ButtonShown(c) and not Shown(c), "a finished chain: no button, no card")
  Check(c.R.CozyBagOffer.Acquired(), "...and it is remembered")
  Check(Count(c.R.ListenerCounts({})) >= 0)

  local o = Client("Owner", "Alliance", Q(), { owned = 1 })
  Login(o); Wait(o)
  Check(not ButtonShown(o) and not Shown(o), "owning the item: no offer")
  Check(o.R.CozyBagOffer.Acquired(), "ownership is recorded")
  -- sold, banked or moved: the offer does not come back (this session or the next)
  o.OWNED = 0
  o.FireEvent("PLAYER_ENTERING_WORLD", false, false); FlushTimers(); Wait(o)
  Check(not ButtonShown(o) and not Shown(o), "selling the item does not make it look new")
  local o2 = Client("Owner", "Alliance", Q(), { db = o.TwichUIDB })
  Login(o2); Wait(o2)
  Check(not ButtonShown(o2) and not Shown(o2), "...nor at the next login")
  Check(o2.R.CozyBagOffer.Snapshot().events == 0, "...and the offer listens for nothing any more")

  -- not owning proves nothing: a character without the item and without the chain is still offered
  local n = Client("None", "Alliance", Q())
  Login(n)
  Check(ButtonShown(n), "no item and an open chain: offered")
end

---------------------------------------------------------------------------
-- 6. Data not there yet is not "not done"
---------------------------------------------------------------------------
do
  local c = Client("Slow", "Alliance", Q(ALL))
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()   -- the world, but no quest update yet
  Check(c.R.CozyBagOffer.Status().reason == "loading", "history not trusted yet: loading")
  Check(not ButtonShown(c) and not Shown(c) and not c.R.CozyBagOffer.Acquired(), "...so no button, no card and nothing recorded")
  c.FireEvent("QUEST_LOG_UPDATE"); FlushTimers(); Wait(c)
  Check(not ButtonShown(c) and not Shown(c), "when the history arrives it says finished: still nothing")
  Check(c.R.CozyBagOffer.Acquired(), "...and that is recorded")

  local s = Client("Slow2", "Alliance", Q())
  s.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  Check(not ButtonShown(s), "not offered while loading")
  RunLongTimers(5); FlushTimers()                                      -- the three-second safety wait
  Check(s.R.CozyBagOffer.Status().offer and ButtonShown(s), "the safety wait brings the answer without a poll")

  local f = Client("NoFaction", nil, Q(), {})
  Login(f); Wait(f)
  Check(f.R.CozyBagOffer.Status().reason == "unknown" and not ButtonShown(f) and not Shown(f), "an unreadable faction offers nothing and claims nothing")
  Check(not f.R.CozyBagOffer.Acquired(), "...and records nothing")

  local noapi = Client("NoApi", "Alliance", Q(), { owned = 0 })
  noapi.C_Item = nil
  Login(noapi)
  Check(noapi.R.CozyBagOffer.Status().offer, "no item API: ownership is simply unknown, the quest history decides")
end

---------------------------------------------------------------------------
-- 7. Completion before the card shows cancels it
---------------------------------------------------------------------------
do
  local c = Client("Cancel", "Alliance", Q({ 79008 }))
  Login(c)
  local N = c.R.Notify
  c.COMBAT = true                    -- the card is asked for but held by the fight
  RunLongTimers(10); FlushTimers()
  Check(N.State().waiting[1] == "cozybag:unlock", "asked for and waiting")
  for _, id in ipairs(ALL) do c.QUESTS.done[id] = true end
  c.FireEvent("QUEST_TURNED_IN", 79976); FlushTimers()
  Check(N.State().waiting[1] == nil, "finishing the chain takes the waiting card back")
  c.COMBAT = false
  RunLongTimers(10); FlushTimers()
  Check(not Shown(c) and not c.R.CozyBagOffer.Announced(), "it never shows, and nothing is marked as told")
  Check(not ButtonShown(c) and c.R.CozyBagOffer.Acquired(), "the button is gone")

  -- a turn-in of some other quest does no work
  local d = Client("Other", "Alliance", Q({ 79008 }))
  Login(d)
  local looks = d.R.CozyBagOffer.Snapshot().looks
  d.FireEvent("QUEST_TURNED_IN", 12345); FlushTimers()
  Check(d.R.CozyBagOffer.Snapshot().looks == looks, "an unrelated quest turn-in is dropped at once")
  d.FireEvent("QUEST_TURNED_IN", 79192); FlushTimers()
  Check(d.R.CozyBagOffer.Snapshot().looks == looks + 1, "a chain quest is one look")

  -- going below the level of the offer (it cannot) is not a case; switching the card off cancels a waiting one
  local e = Client("Off", "Alliance", Q())
  Login(e)
  e.COMBAT = true; RunLongTimers(10); FlushTimers()
  Check(e.R.Notify.State().waiting[1] == "cozybag:unlock", "waiting")
  e.R:SetEnabled("cozyBagNotice", false); FlushTimers()
  Check(e.R.Notify.State().waiting[1] == nil, "turning the card off takes it back")
  e.COMBAT = false; RunLongTimers(10); FlushTimers()
  Check(not Shown(e) and not e.R.CozyBagOffer.Announced(), "and it does not show")
  Check(ButtonShown(e), "the button switch is separate")
  e.R:SetEnabled("cozyBagNotice", true); FlushTimers(); Wait(e)
  Check(Shown(e), "turned back on, a character that was never told is told once")
end

---------------------------------------------------------------------------
-- 8. The first-install setup comes first
---------------------------------------------------------------------------
do
  local c = Client("Setup", "Alliance", Q(), { db = { modules = { partyPins = true }, onboarding = { v = 1, state = "new", offers = 0 } } })
  Login(c); Wait(c)
  Check(ButtonShown(c), "the button is not held for the setup")
  Check(not Shown(c) and c.R.Notify.State().waiting[1] == nil, "the card is held back while the setup is under way")
  Check(not c.R.CozyBagOffer.Announced(), "...and nothing is marked as told")
  c.TwichUIDB.onboarding.state = "done"
  c.FireEvent("PLAYER_ENTERING_WORLD", false, true); FlushTimers(); Wait(c)       -- the reload a layout install makes
  Check(Shown(c) and c.R.CozyBagOffer.Announced(), "once the setup is answered, the next world entry brings the card")
  local d = Client("Setup2", "Alliance", Q(), { db = { modules = { partyPins = true }, onboarding = { v = 1, state = "deferred", offers = 1 } } })
  Login(d); Wait(d)
  Check(Shown(d), "a setup the player put off does not hold the card")
end

---------------------------------------------------------------------------
-- 9. The button: click, menu, hide, bring back
---------------------------------------------------------------------------
do
  local c = Client("Btn", "Alliance", Q({ 79008 }))
  Login(c)
  local b, R, O = Button(c), c.R, c.R.CozyBagOffer
  Check(b and b.scripts.OnClick and b.scripts.OnDragStart, "the button exists with its scripts")
  Check(#(function() local n = {} for _, f in ipairs(c.FRAMES) do if f.kindOf == "Button" then n[#n + 1] = f end end return n end)() == 1, "one launcher frame")
  local done0 = c.QUESTS.done
  b.scripts.OnClick(b, "LeftButton")
  Check(R.CozyBagWindow.IsShown(), "left-click opens the guide")
  Check(not b.shown, "the button steps aside while the guide is open")
  Check(not O.Hidden() and not O.Acquired() and Rec(c) == nil, "opening records nothing and dismisses nothing")
  Check(c.QUESTS.done == done0 and Count(c.QUESTS.done) == 1 and next(c.QUESTS.log) == nil, "...and changes no progress")
  Check(R.CozyBag.Result().status == "ready" and R.CozyBag.Result().done == 2, "the guide reads progress as it was")
  R.CozyBagWindow.Hide(); FlushTimers()
  Check(b.shown, "closing the guide brings the button back")
  Check(c.OUT.waypoint == 0 and c.OUT.chat == 0, "no route, no message")

  -- the menu
  local items
  c.MenuUtil = { CreateContextMenu = function(owner, gen)
    items = {}
    gen(owner, { CreateTitle = function(_, t) items[#items + 1] = "title:" .. t end,
      CreateButton = function(_, label, fn) items[#items + 1] = label; items[label] = fn end })
  end }
  b.scripts.OnClick(b, "RightButton")
  Check(items and items[2] == "Open guide" and items[3] == "Move" and items[4] == "Hide button" and #items == 4, "right-click: Open guide, Move, Hide button")
  items["Open guide"](); Check(R.CozyBagWindow.IsShown(), "the menu's Open guide opens it"); R.CozyBagWindow.Hide(); FlushTimers()

  -- hide persists, takes the card with it, and is reversible
  items["Hide button"]()
  Check(O.Hidden() and not b.shown, "Hide button hides it")
  Check(c.PRINTED[#c.PRINTED]:find("Bring it back"), "...and says once how to bring it back")
  Check(not O.Announced(), "hiding before the card showed tells nothing")
  Wait(c)
  Check(not Shown(c), "a hidden button also means no card")
  local d = Client("Btn", "Alliance", Q({ 79008 }), { db = c.TwichUIDB })
  Login(d); Wait(d)
  Check(not ButtonShown(d) and not Shown(d), "hidden stays hidden at the next login")
  d.R.CozyBagOffer.SetHidden(false)
  Check(ButtonShown(d), "bringing it back shows it (while available)")
  d.R.CozyBagOffer.SetHidden(true)
  d.R:SetEnabled("cozyBagButton", false); d.R:SetEnabled("cozyBagButton", true)
  Check(d.R.CozyBagOffer.Hidden() and not ButtonShown(d), "the switch does not undo a hidden button")
  d.R.CozyBagOffer.SetHidden(false)
  Check(ButtonShown(d), "an explicit show does")

  -- a switch off hides it; on shows it; hidden and told are separate from the switch
  local e = Client("Sw", "Alliance", Q())
  Login(e)
  e.R:SetEnabled("cozyBagButton", false)
  Check(not ButtonShown(e), "switch off: no button")
  e.R:SetEnabled("cozyBagButton", true)
  Check(ButtonShown(e), "switch on: button")
  Check(not e.R.CozyBagOffer.Hidden(), "...and no record of hiding was made")
end

---------------------------------------------------------------------------
-- 10. Drag and click are told apart; place, clamp, reset
---------------------------------------------------------------------------
do
  local c = Client("Move", "Alliance", Q())
  Login(c)
  local b, B = Button(c), c.R.CozyBagButton
  local moved, stopped = 0, 0
  rawset(b, "StartMoving", function() moved = moved + 1 end)
  rawset(b, "StopMovingOrSizing", function() stopped = stopped + 1 end)
  b.scripts.OnDragStart(b)
  Check(moved == 0, "outside move mode the button cannot be dragged")
  b.scripts.OnClick(b, "LeftButton")
  Check(c.R.CozyBagWindow.IsShown(), "a click opens the guide"); c.R.CozyBagWindow.Hide(); FlushTimers()

  Check(B.StartMove() and B.Moving(), "move mode starts")
  b.scripts.OnClick(b, "LeftButton")
  Check(not c.R.CozyBagWindow.IsShown(), "in move mode a click does nothing")
  b.scripts.OnDragStart(b)
  Check(moved == 1, "in move mode a drag moves it")
  b.center = { 612, 484 }
  b.scripts.OnDragStop(b)
  local x, y, custom = B.Position()
  Check(x == 100 and y == 100 and custom, "the place is kept as an offset from the centre")
  Check(c.TwichUIDB.ui.cozyBagButton.x == 100, "...in the profile's table")
  B.StopMove()
  Check(not B.Moving(), "Done ends it")
  b.scripts.OnDragStart(b); Check(moved == 1, "and the button is fixed again")

  -- combat
  c.COMBAT = true
  local ok, why = B.StartMove(); Check(not ok and why == "combat", "no move mode in combat")
  c.COMBAT = false
  B.StartMove(); c.COMBAT = true
  c.FireEvent("PLAYER_REGEN_DISABLED")
  Check(not B.Moving(), "a fight ends move mode"); c.COMBAT = false

  -- clamping, bad values, reset, display change
  Check(not B.SetPosition(0 / 0, 5) and not B.SetPosition(1e9, 0) and not B.SetPosition("x", 0), "unusable places are refused")
  Check(B.SetPosition(7000, -7000), "a place far off screen is kept as given")
  local p = b.points[#b.points]
  Check(math.abs(p[4]) <= 512 and math.abs(p[5]) <= 384, "...but the button is held on screen (" .. tostring(p[4]) .. ", " .. tostring(p[5]) .. ")")
  rawset(c.UIParent, "width", 640); rawset(c.UIParent, "height", 480)
  c.FireEvent("DISPLAY_SIZE_CHANGED"); FlushTimers()
  p = b.points[#b.points]
  Check(math.abs(p[4]) <= 320 and math.abs(p[5]) <= 240, "a smaller screen holds it on screen again")
  B.ResetPosition()
  Check(c.TwichUIDB.ui.cozyBagButton.x == nil and select(3, B.Position()) == false, "reset forgets the place")
  Check(select(1, B.Position()) < 0, "...and the default is against the left edge")
  c.TwichUIDB.ui.cozyBagButton.x, c.TwichUIDB.ui.cozyBagButton.y = "bad", 5
  Check(select(3, B.Position()) == false, "a damaged saved place reads as the default")
  Check(c.R.ListenerCounts({}).UI_SCALE_CHANGED == 1, "scale and display are listened for while shown, once")
  c.R:SetEnabled("cozyBagButton", false)
  Check(c.R.ListenerCounts({}).UI_SCALE_CHANGED == nil, "...and not when hidden")
end

---------------------------------------------------------------------------
-- 11. The guide will not load
---------------------------------------------------------------------------
do
  local c = Client("Fail", "Alliance", Q(), { fails = true })
  Login(c)
  c.R.CozyBagButton.Open()
  Check(c.PRINTED[#c.PRINTED]:find("couldn't be opened"), "it says briefly why")
  Check(c.FAULTS == 1, "the failure still reaches the game's error handler, once")
  Check(ButtonShown(c) and not c.R.CozyBagOffer.Hidden(), "the button stays, usable")
  c.R.CozyBagWindow.Show = nil
  local ok, why = c.R.CozyBagOffer.OpenGuide()
  Check(not ok and why:find("isn't available"), "no guide at all: a sentence, no error")
end

---------------------------------------------------------------------------
-- 12. Previews are isolated
---------------------------------------------------------------------------
do
  local c = Client("Prev", "Alliance", Q(ALL), { level = 5 })
  Login(c); Wait(c)
  local O, B = c.R.CozyBagOffer, c.R.CozyBagButton
  Check(O.PreviewCard(), "a card preview on a character that does not qualify")
  Check(c.R.Notify.PreviewShowing("cozybag") or Shown(c), "...is shown")
  Check(not O.Announced() and Rec(c) == nil, "it marks no one as told")
  c.R.Notify.DropPreviews("cozybag")
  B.Preview(true)
  Check(ButtonShown(c) and B.Previewing(), "the button preview shows the button on any character")
  local b = Button(c)
  b.scripts.OnClick(b, "LeftButton")
  Check(not c.R.CozyBagWindow.IsShown(), "clicking a preview does nothing")
  Check(not O.Hidden() and not O.Acquired() and Rec(c) == nil, "no choice, no state changed")
  B.Settle()
  Check(not B.Previewing() and not ButtonShown(c), "the settings closing ends it")
  B.Preview(true); c.FireEvent("PLAYER_REGEN_DISABLED"); Check(not B.Previewing(), "a fight ends it")
  B.Preview(true); RunLongTimers(60); Check(not B.Previewing() and not ButtonShown(c), "and it ends by itself after a while")
  -- the settings closing puts both previews away
  O.PreviewCard(); B.Preview(true)
  Check(c.R.Notify.PreviewShowing("cozybag") and B.Previewing(), "both previews are up")
  c.R.SettingsLauncher.Closed()
  Check(not c.R.Notify.PreviewShowing("cozybag") and not B.Previewing() and not ButtonShown(c), "closing the settings puts both away")
  Check(Rec(c) == nil, "and a character that never qualified still has no record")
end

---------------------------------------------------------------------------
-- 13. Switching, again and again, adds nothing
---------------------------------------------------------------------------
do
  local c = Client("Churn", "Alliance", Q())
  Login(c)
  local function Shape()
    local counts = c.R.ListenerCounts({})
    local frames = 0
    for _, f in ipairs(c.FRAMES) do if f.kindOf == "Button" then frames = frames + 1 end end
    return (counts.PLAYER_LEVEL_UP or 0) .. "/" .. (counts.QUEST_TURNED_IN or 0) .. "/" .. (counts.PLAYER_ENTERING_WORLD or 0) .. "/" .. frames
  end
  local base = Shape()
  for _ = 1, 5 do
    c.R:SetEnabled("cozyBagButton", false); c.R:SetEnabled("cozyBagNotice", false)
    Check(c.R.CozyBagOffer.Snapshot().events == 0, "both off: nothing is listened for")
    c.R:SetEnabled("cozyBagButton", true); c.R:SetEnabled("cozyBagNotice", true)
  end
  FlushTimers(); Wait(c)
  Check(Shape() == base, "after five rounds the same listeners and one frame: " .. Shape() .. " vs " .. base)
  Check(c.R.Notify.Snapshot().shown.cozybag == 1, "the card was shown once through all of it")
  -- a profile change reaches the same code
  c.R.CozyBagOffer.Refresh(); c.R.CozyBagOffer.Refresh()
  Check(Shape() == base, "refreshing again adds nothing")
  Check(c.R.CozyBagOffer.Snapshot().events == 3, "three events while offering")
end

---------------------------------------------------------------------------
-- 14. What is saved, and what is shared
---------------------------------------------------------------------------
do
  local c = Client("Saved", "Alliance", Q(), { level = 20 })
  Login(c); Wait(c)
  local R = c.R
  local rec = Rec(c)
  Check(rec and rec.announced == true and rec.hidden == nil and rec.acquired == nil, "the record holds only what is true")
  for k, v in pairs(rec) do Check(v == true and (k == "announced" or k == "hidden" or k == "acquired"), "only three booleans: " .. k) end
  local PF, TC = R.Profiles, R.TwichConfig
  Check(PF.ACCOUNT.ui.cozyBagOffer == true, "the record is account-wide: a profile never carries or resets it")
  Check(TC.LOCAL["ui.cozyBagOffer"] == "other", "...and sharing leaves it out")
  Check(TC.LOCAL["ui.cozyBagButton.x"] == "place" and TC.LOCAL["ui.cozyBagButton.y"] == "place", "the button's place stays on this computer")
  local group
  for _, g in ipairs(TC.Groups()) do if g.id == "cozyBag" then group = g end end
  Check(group and group.complete, "the appearance is a share group")
  local keys = {}
  for _, f in ipairs(group.fields) do keys[#keys + 1] = f.key end
  table.sort(keys)
  Check(table.concat(keys, ",") == "cozyBagButton,cozyBagNotice,label,opacity,size", "it shares two switches and three look values: " .. table.concat(keys, ","))
  for _, f in ipairs(group.fields) do
    Check(f.key ~= "announced" and f.key ~= "hidden" and f.key ~= "acquired" and f.key ~= "x" and f.key ~= "y", "no history and no place in the share")
  end
  -- appearance is read, validated and kept in the profile table
  local B = R.CozyBagButton
  Check(B.Set("size", 48) and B.Get("size") == 48, "size")
  Check(not B.Set("size", 200) and not B.Set("size", 5) and not B.Set("size", "big") and B.Get("size") == 48, "size is bounded")
  Check(B.Set("opacity", 60) and B.Get("opacity") == 60 and not B.Set("opacity", 10), "opacity is bounded")
  Check(B.Set("label", "name") and B.Get("label") == "name" and not B.Set("label", "loud"), "label is one of two")
  c.TwichUIDB.ui.cozyBagButton.size = 9999
  Check(B.Get("size") == 36, "a damaged saved size reads as the default")
  Check(c.TwichUIDB.ui.cozyBagButton.size == 9999, "...and is not erased")
  B.Refresh()
  Check(Button(c).width > 36 and Button(c).height == 36, "a name widens the button, and the size drawn is the default for a damaged saved one")
end

print("COZY BAG OFFER PASSED")
