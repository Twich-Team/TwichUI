-- Reminders: sharing one reminder (reminders/Share.lua, ShareUI.lua, and RM.Export / RM.Admit in Config.lua).
-- Two or three fake clients exchange the real messages through the harness's addon-message queue, so the offer, the
-- answer, the data and the confirmation all go through the real handlers, the real routing and the real encoder. What
-- is NOT covered: the game's own message limits and delivery, the look of the card, and the question windows' real
-- buttons (the popups are recorded, then answered by calling their handlers).
dofile(TESTS .. "harness.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local NOW = 1000
local POPUPS

-- A frame that remembers what it was told and answers anything else with nothing.
local function Stub()
  local o = { shown = false }
  return setmetatable(o, { __index = function(t, k)
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Stub() end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetValue" then return function(s, v) s.value = v end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetScript" then return function(s, n, fn) s.scripts = s.scripts or {}; s.scripts[n] = fn end end
    if k == "HookScript" then return function() end end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local function NewClient(name, extra)
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.GetTime = function() return NOW end
  c.CreateFrame = function() return Stub() end
  c.UIParent = Stub()
  c.StaticPopupDialogs = {}
  c.popups = {}
  c.StaticPopup_Show = function(key, text) c.popups[key] = { text = text, def = c.StaticPopupDialogs[key] }; return {} end
  c.StaticPopup_Hide = function(key) c.popups[key] = nil end
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.TwichUIDB = { modules = {} }
  for k, v in pairs(extra or {}) do c[k] = v end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  for _, f in ipairs({ "reminders/AmmoItems.lua", "reminders/ArtData.lua", "artwork/Catalog.lua", "reminders/Config.lua", "reminders/Gallery.lua",
    "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Share.lua", "reminders/ShareUI.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.opened = {}
  c.TwichUI.OpenSettings = function(_, page) c.opened[#c.opened + 1] = page; return true end
  return c
end
local function Settle() for _ = 1, 12 do FlushTimers(); Pump() end end

GROUP = { Rich = true, Pal = true, Kit = true }
local rich, pal, kit = NewClient("Rich"), NewClient("Pal"), NewClient("Kit")
local RR, PR, KR = rich.TwichUI, pal.TwichUI, kit.TwichUI
local RRM, PRM = RR.Reminders, PR.Reminders
local RS, PS = RR.ReminderShare, PR.ReminderShare

local function Say(r) return r end
local function Has(t, needle)
  local found = false
  local function Walk(v) if type(v) == "table" then for k, x in pairs(v) do Walk(k); Walk(x) end elseif type(v) == "string" and v:find(needle, 1, true) then found = true end end
  Walk(t)
  return found
end
local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

---------------------------------------------------------------------------
-- A reminder worth sharing: groups, an item, a class limit, and a character limit that must stay home
---------------------------------------------------------------------------
local ok, id = RRM.Create("custom")
Check(ok, "a reminder is made")
RRM.SetName(id, "Eat before the dungeon")
RRM.AddCondition(id, "equipment", nil, { type = "equipment", slot = "offHand", what = "shield", negate = true })
RRM.SetDisplayMany(id, { mode = "iconText", iconSource = "item", item = 6948, text = "Eat now" })
RRM.SetScope(id, "class", "WARRIOR")
RRM.AddCharacter(id, "Rich - Forever")
RRM.SetSound(id, "Some Sound")
local original = RRM.Get(id)
Check(original.valid, "the reminder is complete: " .. tostring(original.problems[1]))
Check(#original.scope.characters >= 1, "it is limited to a character here")

local payload, why = RRM.Export(id)
Check(payload ~= nil, "it exports: " .. tostring(why))
Check(payload.name == "Eat before the dungeon" and payload.class == "WARRIOR" and payload.sound == "Some Sound", "name, class and sound are in it")
Check(not Has(payload, "Rich - Forever") and not Has(payload, "characters") and not Has(payload, "scope"), "no character name or scope is sent")
Check(payload.display.item == 6948, "the item is in it")
Check(payload.id == nil and payload.enabled == nil, "no id or switch is sent")

local draft = RRM.Create("custom")
local _, draftId = RRM.Create("custom")
local bad, badWhy = RRM.Export(draftId)
Check(bad == false and badWhy:find("Finish this reminder first", 1, true), "an unfinished reminder is not sent: " .. tostring(badWhy))
Check(select(2, RRM.Export("r999")) == RRM.REFUSE.missing, "an unknown reminder is not sent")
RRM.Delete(draftId)

---------------------------------------------------------------------------
-- Admit: the only door. Each way a received table can be wrong, and nothing is added for any of them
---------------------------------------------------------------------------
local function Fresh() return PRM.DeepCopy(payload) end
local function Refused(mutate, what)
  local p = Fresh(); mutate(p)
  local before, nextBefore = PRM.Count(), pal.TwichUIDB.ui and pal.TwichUIDB.ui.reminders and pal.TwichUIDB.ui.reminders.nextId
  local added, reason = PRM.Admit(p)
  Check(added == false and type(reason) == "string", what .. " is refused")
  Check(PRM.Count() == before, what .. ": nothing was added")
  Check((pal.TwichUIDB.ui and pal.TwichUIDB.ui.reminders and pal.TwichUIDB.ui.reminders.nextId) == nextBefore, what .. ": no id was used")
end
Refused(function(p) p.v = 99 end, "a newer version")
Refused(function(p) p.v = nil end, "no version")
Refused(function(p) p.name = "bad|cname" end, "a name with markup")
Refused(function(p) p.name = ("x"):rep(200) end, "a long name")
Refused(function(p) p.match = "sometimes" end, "an unknown match")
Refused(function(p) p.conditions = {} end, "no conditions")
Refused(function(p) p.conditions = { { type = "noSuchKind" } } end, "a condition of an unknown kind")
Refused(function(p) p.conditions = { "text" } end, "a condition that is not a table")
Refused(function(p) p.conditions = { { type = "group", match = "all", conditions = {} } } end, "an empty group")
Refused(function(p) p.conditions = { { type = "group", match = "maybe", conditions = p.conditions } } end, "a group with no match")
Refused(function(p)
  local inner = { { type = "equipment", slot = "offHand", what = "shield" } }
  for _ = 1, 6 do inner = { { type = "group", match = "all", conditions = inner } } end
  p.conditions = inner
end, "groups nested too deeply")
Refused(function(p) local many = {} for i = 1, 40 do many[i] = { type = "equipment", slot = "offHand", what = "shield" } end p.conditions = many end, "too many conditions")
Refused(function(p) p.display.mode = "hologram" end, "an unknown display mode")
Refused(function(p) p.display.size = 99999 end, "an out-of-range size")
Refused(function(p) p.display.item = -4 end, "an unusable item")
Refused(function(p) p.display.mode = "artwork"; p.display.art = "noSuchPicture" end, "artwork this version doesn't have")
Refused(function(p) p.display = nil end, "no display")
Check(PRM.Admit("not a table") == false and PRM.Admit(nil) == false, "a non-table is refused")

-- a table with extra and hostile fields: only checked values are kept
do
  local p = Fresh()
  p.id, p.enabled, p.scope = "r99", true, { who = "all", characters = { "Mallory - Forever" } }
  p.display.evil = function() end
  p.place = { preset = "hovering", x = 1e99 }
  p.class = "WIZARD"
  local added, newId = PRM.Admit(p)
  Check(added == true, "a table with extra fields is admitted without them: " .. tostring(newId))
  local v = PRM.Get(newId)
  Check(newId ~= "r99" and v.enabled == false, "it has its own id and starts off")
  Check(v.scope.who == "characters" and #v.scope.characters == 1 and v.scope.characters[1] ~= "Mallory - Forever", "its scope is this character, not what was sent")
  Check(v.scope.class == nil, "an unknown class is dropped")
  Check(v.place.preset == "belowCenter", "an unknown place falls back to the default")
  Check(pal.TwichUIDB.ui.reminders.list[1].display.evil == nil, "unknown display fields are not stored")
  PRM.Delete(newId)
end

---------------------------------------------------------------------------
-- A whole transfer
---------------------------------------------------------------------------
local sent, msg = RS.Send(id, "Pal")
Check(sent == true, "the offer goes: " .. tostring(msg))
Settle()
local inc = PS.inc["Rich-Forever"]
Check(inc and inc.stage == "asking", "Pal is asked")
Check(pal.popups.TWICHUI_REMINDER_OFFER and pal.popups.TWICHUI_REMINDER_OFFER.text:find("Eat before the dungeon", 1, true), "the question names the reminder")
Check(pal.popups.TWICHUI_REMINDER_OFFER.text:find("turned off", 1, true), "the question says it arrives turned off")
Check(RS.out[1].stage == "offered", "Rich is waiting")
Check(PRM.Count() == 0, "nothing is added before Pal accepts")
local rows = rich.TwichUI.ReminderShareUI.Rows()
Check(#rows == 1 and rows[1].text:find("Waiting for Pal", 1, true), "Rich's card says who it is waiting for")
Check(#pal.TwichUI.ReminderShareUI.Rows() == 0, "Pal's card has nothing yet: the question is the question")

-- Pal's side counts the pieces as they arrive
PS.Respond("Rich-Forever", true)
Check(inc.stage == "waiting", "Pal accepted")
local half = math.floor(inc.expected / 2)
pal.FireEvent("CHAT_MSG_ADDON", RR.Share.PREFIX, ("x"):rep(half), "WHISPER", "Rich-Forever")
Check(inc.stage == "waiting" and inc.got == 0, "unrelated addon traffic cannot advance reminder progress")
PR.Share.handlers.remprogress("Rich-Forever", { id = "wrong", sent = half })
Check(inc.got == 0, "progress for another recipient or transfer is ignored")
PR.Share.handlers.remprogress("Rich-Forever", { id = inc.id, sent = half })
Check(inc.stage == "receiving" and inc.got == half, "matching transfer progress is shown")
PR.Share.handlers.remprogress("Rich-Forever", { id = inc.id, sent = -1 })
PR.Share.handlers.remprogress("Rich-Forever", { id = inc.id, sent = inc.expected + 1 })
PR.Share.handlers.remprogress("Rich-Forever", { id = inc.id, sent = half - 1 })
Check(inc.got == half, "invalid or late progress cannot move the bar backwards")
local mid = PR.ReminderShareUI.Rows()
Check(#mid == 1 and mid[1].text:find("Receiving", 1, true) and mid[1].text:find("%d+%%") and mid[1].frac > 0.4 and mid[1].frac < 0.6, "Pal's card shows about half")
Settle()
Check(inc.stage == "done", "Pal stored it: " .. tostring(inc.stage) .. " " .. tostring(inc.reason))
Check(RS.out[1].stage == "done", "Rich was told it arrived: " .. tostring(RS.out[1].stage) .. " " .. tostring(RS.out[1].reason))
Check(RS.out[1].sent == RS.out[1].total and RS.out[1].total > 0, "the send reached its full size")
Check(PRM.Count() == 1, "one reminder was added")
local got = PRM.List()[1]
Check(got.name == "Eat before the dungeon" and got.enabled == false, "it is named and off")
Check(got.id == inc.newId, "its id is the one reported")
Check(got.scope.who == "characters" and #got.scope.characters == 1 and got.scope.class == "WARRIOR", "limited to Pal's character, with the class")
Check(Same(got.display, original.display), "its look is the same")
Check(Same(PRM.Export(got.id).conditions, payload.conditions), "its conditions are the same")
Check(got.sound == "Some Sound", "its sound name came across")
Check(#RRM.Get(id).scope.characters == #original.scope.characters, "Rich's own reminder is unchanged")

-- the question afterwards
local arrived = pal.popups.TWICHUI_REMINDER_ARRIVED
Check(arrived and arrived.text:find("Open the Reminders settings", 1, true), "Pal is asked about opening the settings")
arrived.def.OnAccept()
Check(pal.opened[1] == "reminders", "accepting opens the Reminders settings")
Check(#pal.TwichUI.ReminderShareUI.Rows() == 1 and pal.TwichUI.ReminderShareUI.Rows()[1].text:find("off until you turn it on", 1, true), "Pal's card says it is off")

-- finished transfers leave the card
NOW = NOW + 30
Check(#rich.TwichUI.ReminderShareUI.Rows() == 0 and #pal.TwichUI.ReminderShareUI.Rows() == 0, "the cards empty after a few seconds")
Check(RR.Perf and RS.Count() >= 1, "the transfers held are counted")

---------------------------------------------------------------------------
-- Declined, busy, full, switched off, newer protocol
---------------------------------------------------------------------------
NOW = NOW + 100
RS.Send(id, "Pal"); Settle()
pal.popups.TWICHUI_REMINDER_OFFER.def.OnCancel(nil, nil, "clicked")
Settle()
local last = RS.out[#RS.out]
Check(last.stage == "declined" and last.reason == "They declined.", "a declined offer says so: " .. tostring(last.stage) .. " " .. tostring(last.reason))
Check(PRM.Count() == 1, "declining adds nothing")

-- a second sender while a question is open: busy
PS.inc = {}
RS.Send(id, "Pal"); Settle()
Check(PS.inc["Rich-Forever"].stage == "asking", "Pal has one question open")
local kitReminder = select(2, KR.Reminders.Create("custom"))
KR.Reminders.AddCondition(kitReminder, "equipment", nil, { type = "equipment", slot = "offHand", what = "shield" })
KR.Reminders.SetDisplayMany(kitReminder, { mode = "text", text = "hello" })
Check(KR.ReminderShare.Send(kitReminder, "Pal"), "Kit offers too")
Settle()
local kitOut = KR.ReminderShare.out[1]
Check(kitOut.stage == "declined" and kitOut.reason:find("answering another offer", 1, true), "the second offer is told Pal is busy: " .. tostring(kitOut.reason))
Check(PS.inc["Kit-Forever"] == nil, "and is not held")
PS.Respond("Rich-Forever", false); Settle()

-- a full list
do
  local t = pal.TwichUIDB.ui.reminders
  local keep = {}
  for i = 1, #t.list do keep[i] = t.list[i] end
  for i = #t.list + 1, PRM.MAX do t.list[i] = { id = "r" .. (100 + i), name = "filler" .. i, enabled = false, match = "all", conditions = {}, display = {}, scope = {}, place = {} } end
  PRM.Invalidate()
  RS.Send(id, "Pal"); Settle()
  local o = RS.out[#RS.out]
  Check(o.stage == "declined" and o.reason == "Their reminder list is full.", "a full list declines at the offer: " .. tostring(o.reason))
  for i = #t.list, #keep + 1, -1 do t.list[i] = nil end
  PRM.Invalidate()
end

-- receiving switched off, reminders switched off
pal.TwichUIDB.modules.acceptSetups = false
RS.Send(id, "Pal"); Settle()
Check(RS.out[#RS.out].reason == "They've turned off receiving shared items.", "receiving off is said: " .. tostring(RS.out[#RS.out].reason))
pal.TwichUIDB.modules.acceptSetups = true
pal.TwichUIDB.modules.reminders = false
RS.Send(id, "Pal"); Settle()
Check(RS.out[#RS.out].reason == "They have reminders turned off.", "reminders off is said: " .. tostring(RS.out[#RS.out].reason))
pal.TwichUIDB.modules.reminders = true

-- the sender's own switch
rich.TwichUIDB.modules.setupSharing = false
local offOk, offWhy = RS.Send(id, "Pal")
Check(offOk == false and offWhy:find("turned off", 1, true), "sharing off refuses to send: " .. tostring(offWhy))
rich.TwichUIDB.modules.setupSharing = true

-- names
Check(RS.Send(id, "Rich") == false, "you can't share with yourself")
Check(select(2, RS.Send(id, "Someone#1234")):find("Battle.net", 1, true), "a Battle.net name is refused")
Check(RS.Send(id, "") == false, "an empty name is refused")

---------------------------------------------------------------------------
-- Tampered traffic: not for you, wrong id, wrong sender, oversize
---------------------------------------------------------------------------
do
  local before = PRM.Count()
  local SH = PR.Share
  -- data nobody asked for
  SH.handlers.remdata("Mallory-Forever", { t = "remdata", id = "123", r = payload })
  Check(PRM.Count() == before, "data from someone who wasn't asked is ignored")
  -- a reply for a transfer that isn't ours
  SH.handlers.remreply("Mallory-Forever", { t = "remreply", id = "123", accept = true })
  SH.handlers.remdone("Mallory-Forever", { t = "remdone", id = "123", ok = true })
  -- malformed offers are dropped without a question
  PS.inc = {}
  SH.handlers.remoffer("Mallory-Forever", { id = ("9"):rep(40), size = 100, name = "x", p = 2 }, "WHISPER")
  SH.handlers.remoffer("Mallory-Forever", { id = "1", size = 10 ^ 9, name = "x", p = 2 }, "WHISPER")
  SH.handlers.remoffer("Mallory-Forever", { id = "1", size = 100, name = "bad|cname", p = 2 }, "WHISPER")
  SH.handlers.remoffer("Mallory-Forever", { id = "1", size = 100, name = 5, p = 2 }, "WHISPER")
  Check(next(PS.inc) == nil, "malformed offers are dropped without a question")
  -- data from the right player but a wrong id
  RS.Send(id, "Pal"); Settle()
  PS.Respond("Rich-Forever", true)
  SH.handlers.remdata("Rich-Forever", { t = "remdata", id = "wrong", r = payload })
  Check(PRM.Count() == before and PS.inc["Rich-Forever"].stage == "waiting", "data with the wrong id is ignored")
  -- the right id from the wrong player
  SH.handlers.remdata("Mallory-Forever", { t = "remdata", id = PS.inc["Rich-Forever"].id, r = payload })
  Check(PRM.Count() == before, "data from another player is ignored")
  -- hostile data from the right player: refused, and the sender is told
  local hostile = PRM.DeepCopy(payload); hostile.conditions = { { type = "noSuchKind" } }
  SH.handlers.remdata("Rich-Forever", { t = "remdata", id = PS.inc["Rich-Forever"].id, r = hostile })
  Settle()
  Check(PRM.Count() == before and PS.inc["Rich-Forever"].stage == "failed", "hostile data is refused")
  local o = RS.out[#RS.out]
  Check(o.stage == "failed" and o.reason == "It couldn't be used on their side, so nothing was added.", "the sender is told it couldn't be used: " .. tostring(o.reason))
  Check(#pal.TwichUI.ReminderShareUI.Rows() == 1 and PR.ReminderShareUI.Rows()[1].bad, "Pal's card shows the refusal")
end

---------------------------------------------------------------------------
-- Everyone in the group: one offer each, each answered on its own
---------------------------------------------------------------------------
NOW = NOW + 100
PS.inc, KR.ReminderShare.inc = {}, {}
RS.out = {}
local gOk, gMsg = RS.Send(id, RS.GROUP)
Check(gOk and gMsg:find("2 players", 1, true), "the group is offered to: " .. tostring(gMsg))
Settle()
Check(#RS.out == 2, "two offers were made")
Check(PS.inc["Rich-Forever"] and PS.inc["Rich-Forever"].stage == "asking" and KR.ReminderShare.inc["Rich-Forever"].stage == "asking", "each member is asked")
PS.Respond("Rich-Forever", true)
KR.ReminderShare.Respond("Rich-Forever", false)
Settle()
local byTarget = {}
for _, o in ipairs(RS.out) do byTarget[o.target] = o end
Check(byTarget.Pal.stage == "done" and byTarget.Kit.stage == "declined", "one accepted and one declined: " .. tostring(byTarget.Pal.stage) .. " / " .. tostring(byTarget.Kit.stage))
Check(KR.Reminders.Count() == 1 and PRM.Count() == 2, "only the one who accepted got it (Kit keeps only their own)")
Check(RS.Send(id, "Pal") == true, "a finished transfer doesn't block the next")
Settle(); PS.Respond("Rich-Forever", false); Settle()

GROUP = { Rich = true }
local solo = select(2, RS.Send(id, RS.GROUP))
Check(solo == "You aren't in a group with anyone else.", "no group, no offers: " .. tostring(solo))
GROUP = { Rich = true, Pal = true, Kit = true }

-- a group over the limit is not offered to at all
do
  GROUP = { Rich = true }
  local origUnitName = rich.GetUnitName
  rich.IsInRaid = function() return true end
  rich.GetUnitName = function(u)
    if u == "player" then return "Rich" end
    local i = tonumber(u:match("^raid(%d+)$"))
    return i and i <= RS.MAX_GROUP + 2 and ("Raider" .. i) or nil
  end
  rich.IsInGroup = function() return true end
  local before = #RS.out
  local manyOk, manyWhy = RS.Send(id, RS.GROUP)
  Check(manyOk == false and manyWhy:find("up to " .. RS.MAX_GROUP, 1, true) and #RS.out == before, "a group over the limit gets no offers: " .. tostring(manyWhy))
  rich.IsInRaid = function() return false end
  rich.IsInGroup = function() return GROUP ~= nil and GROUP.Rich ~= nil end
  rich.GetUnitName = origUnitName
  GROUP = { Rich = true, Pal = true, Kit = true }
end

-- more than three at once is one line
do
  local fake = {}
  for i = 1, 5 do fake[i] = { id = tostring(i), target = "P" .. i, name = "Eat", stage = i <= 2 and "done" or "offered", sent = 0, total = 10, started = NOW, ended = i <= 2 and NOW or nil } end
  local keep = RS.out
  RS.out = fake
  local lines = RR.ReminderShareUI.Rows()
  Check(#lines == 1 and lines[1].text:find("5 players", 1, true) and lines[1].text:find("2 have it", 1, true), "five transfers are one summary line: " .. tostring(lines[1] and lines[1].text))
  RS.out = keep
end

---------------------------------------------------------------------------
-- Guild fan-out uses GUILD, skips offline/self, and needs each player's consent.
---------------------------------------------------------------------------
do
  NOW = NOW + 1000
  RS.out, PS.inc, KR.ReminderShare.inc = {}, {}, {}
  GUILD = { Rich = true, Pal = true, Kit = true, Offline = false }
  local palBefore, kitBefore = PRM.Count(), KR.Reminders.Count()
  local ok, why = RS.Send(id, RS.GUILD)
  Check(ok and #RS.out == 2, "guild offers only online peers: " .. tostring(why))
  for _, o in ipairs(RS.out) do Check(o.route[1] == "GUILD", "guild choice uses guild channel despite Direct preference") end
  Settle()
  Check(PRM.Count() == palBefore and KR.Reminders.Count() == kitBefore, "guild offers store nothing without consent")
  local originalInc = PS.inc["Rich-Forever"]
  -- A second offer from the same sender must not replace the question or data state.
  PR.Share.handlers.remoffer("Rich-Forever", { id = "999", name = "Other", size = 100, p = PR.Share.PROTOCOL }, "GUILD")
  Check(PS.inc["Rich-Forever"] == originalInc, "duplicate sender cannot replace an open question")
  PS.Respond("Rich-Forever", true)
  PR.Share.handlers.remoffer("Rich-Forever", { id = "998", name = "Other", size = 100, p = PR.Share.PROTOCOL }, "GUILD")
  Check(PS.inc["Rich-Forever"] == originalInc and originalInc.stage == "waiting", "duplicate sender cannot replace an accepted transfer")
  KR.ReminderShare.Respond("Rich-Forever", false)
  Settle()
  Check(PRM.Count() == palBefore + 1 and KR.Reminders.Count() == kitBefore, "only consenting guild member receives the reminder")
  local done, declined = 0, 0
  for _, o in ipairs(RS.out) do
    if o.stage == "done" then done = done + 1 elseif o.stage == "declined" then declined = declined + 1 end
  end
  Check(done == 1 and declined == 1, "sender sees independent guild completion and decline")
  Check(PRM.Get(originalInc.newId).enabled == false, "guild reminder is disabled on arrival")
  GUILD = nil
  Check(RS.Send(id, RS.GUILD) == false, "no guild offers when unguilded")
end

---------------------------------------------------------------------------
-- Time: no answer, a stalled transfer, an unanswered question
---------------------------------------------------------------------------
NOW = NOW + 1000
PS.inc, RS.out = {}, {}
RS.Send(id, "Pal")                     -- not pumped: no answer ever comes
local o = RS.out[1]
NOW = NOW + 125
RunTickers()
Check(o.stage == "failed" and o.reason:find("No answer from Pal", 1, true), "an unanswered offer ends: " .. tostring(o.stage) .. " " .. tostring(o.reason))

Settle()   -- the late offer arrives at Pal now
local late = PS.inc["Rich-Forever"]
Check(late and late.stage == "asking", "the late offer is a question")
NOW = NOW + 130
RunTickers()
Check(late.stage == "declined" and pal.popups.TWICHUI_REMINDER_OFFER == nil, "an unanswered question is answered 'not now' and taken down")

PS.inc, RS.out = {}, {}
RS.Send(id, "Pal"); Settle(); PS.Respond("Rich-Forever", true)
NOW = NOW + 70
RunTickers()
Check(PS.inc["Rich-Forever"].stage == "failed", "a transfer that stops ends: " .. tostring(PS.inc["Rich-Forever"].stage))

---------------------------------------------------------------------------
-- Switching sharing off settles everything, on both sides
---------------------------------------------------------------------------
NOW = NOW + 1000
PS.inc, RS.out = {}, {}
RS.Send(id, "Pal"); Settle()
PR.Share:Settle("module-off", true)
Settle()
Check(PS.inc["Rich-Forever"].stage == "declined" and pal.popups.TWICHUI_REMINDER_OFFER == nil, "receiving off answers and takes the question down")
Check(RS.out[1].stage == "declined", "and the sender is told")
RS.out = {}
RS.Send(id, "Pal")
RR.Share:Settle("module-off")
Check(RS.out[1].stage == "failed" and RS.out[1].reason == "Sharing was turned off.", "sharing off ends what you were sending")
Settle()

---------------------------------------------------------------------------
-- Not in combat
---------------------------------------------------------------------------
do
  NOW = NOW + 1000
  PS.inc, RS.out = {}, {}
  pal.popups.TWICHUI_REMINDER_ARRIVED = nil
  pal.InCombatLockdown = function() return true end
  RS.Send(id, "Pal"); Settle(); PS.Respond("Rich-Forever", true); Settle()
  Check(PS.inc["Rich-Forever"].stage == "done", "it still arrives in combat")
  Check(pal.popups.TWICHUI_REMINDER_ARRIVED == nil, "but nothing is asked until combat ends")
  pal.InCombatLockdown = function() return false end
  pal.FireEvent("PLAYER_REGEN_ENABLED")
  Check(pal.popups.TWICHUI_REMINDER_ARRIVED ~= nil, "the question comes when it ends")
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local toc = io.open(ROOT .. "!!!TwichUI.toc"):read("*a")
local a, b, c = toc:find("reminders\\Controller.lua", 1, true), toc:find("reminders\\Share.lua", 1, true), toc:find("reminders\\ShareUI.lua", 1, true)
Check(a and b and c and a < b and b < c, "the .toc loads Share.lua and ShareUI.lua after the controller, in order")
local setupToc = toc:find("setup\\Share.lua", 1, true)
Check(setupToc and setupToc < b, "after setup sharing, whose handlers it adds to")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
