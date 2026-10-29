-- Reminders: grouped conditions (AND / OR, groups inside groups) and the "Player class" condition. The tree is the
-- same stored list the flat rules always were (the top level is the reminder's own `match` + `conditions`; a group is a
-- condition of type "group"), so the same evaluator, controller and sources run it. A fake world stands in for the game,
-- so this checks our logic, not the game: the in-game checks are in docs/reminders.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- A fake world: frames that record what they were told, the character's equipment, combat, life and mount state
---------------------------------------------------------------------------
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, events = {}, points = {}, alpha = 1, scale = 1, w = 10, h = 10 }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
Methods = {
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end, GetScript = function(s, n) return s.scripts[n] end,
  RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  GetStringWidth = function(s) return #(s.text or "") * 8 end,
  GetStringHeight = function(s) return s.fontSize or 18 end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetTexture = function(s, p) s.texture = p; return true end, SetTexCoord = function(s, ...) s.coords = { ... } end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  SetScale = function(s, v) s.scale = v end, SetFrameStrata = function(s, v) s.strata = v end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
  StartMoving = function(s) s.moving = true end, StopMovingOrSizing = function(s) s.moving = false end,
  GetLeft = function(s) return s.left end, GetRight = function(s) return s.left and s.left + s.w end,
  GetTop = function(s) return s.bottom and s.bottom + s.h end, GetBottom = function(s) return s.bottom end,
  CreateAnimationGroup = function(s)
    local g = Fake("group")
    g.owner, g.plays, g.stops = s, 0, 0
    g.Play = function(self) self.plays = self.plays + 1; self.playing = true end
    g.Stop = function(self) if self.playing then self.stops = self.stops + 1 end self.playing = false end
    g.Finish = function(self) self.playing = false; if self.scripts.OnFinished then self.scripts.OnFinished(self) end end
    g.CreateAnimation = function() return Fake("anim") end
    return g
  end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.w, c.UIParent.h = 1024, 768
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- Items the client knows: class 4 Armor (subclass 6 Shield, 1 Cloth), class 2 Weapon (7 one-handed sword, 8 two-handed,
-- 20 fishing pole). 90001 and up are server items the client has no details for.
c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
local ITEMS = {
  [1201] = { 4, 6, "INVTYPE_SHIELD", "Dull Heater Shield" },
  [2139] = { 2, 7, "INVTYPE_WEAPONOFFHAND", "Dirk" },
  [2489] = { 2, 8, "INVTYPE_2HWEAPON", "Two-Handed Sword" },
  [6256] = { 2, 20, "INVTYPE_2HWEAPON", "Fishing Pole" },
  [5976] = { 4, 0, "INVTYPE_TABARD", "Guild Tabard" },
  [6948] = { 15, 0, "", "Hearthstone" },
}
local W, calls, asked, NOW
local function World()
  W = { slots = {}, combat = false, dead = false, ghost = false, mounted = false, class = "WARRIOR" }
  calls = { inv = 0 }
  asked = {}
end
World()
NOW = 1000
c.GetTime = function() return NOW end
c.UnitClassBase = function() return W.class end
c.GetInventoryItemID = function(_, slot) calls.inv = calls.inv + 1; return W.slots[slot] end
c.C_Item = {
  GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "t", "s", it[3], 100000 + id, it[1], it[2]
  end,
  GetItemIconByID = function(id) return ITEMS[id] and (100000 + id) or nil end,
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][4] or nil end,
  RequestLoadItemDataByID = function(id) asked[id] = (asked[id] or 0) + 1 end,
}
c.UnitAffectingCombat = function() return W.combat end
c.InCombatLockdown = function() return W.combat end
c.UnitIsDeadOrGhost = function() return W.dead or W.ghost end
c.UnitIsGhost = function() return W.ghost end
c.IsMounted = function() return W.mounted end
c.issecretvalue = function() return false end
-- anything that would act in the game: none of it may ever be called
local acted = {}
for _, name in ipairs({ "EquipItemByName", "UseInventoryItem", "PickupInventoryItem", "CastSpellByName", "UseItemByName",
  "AutoEquipCursorItem", "SendChatMessage" }) do
  c[name] = function() acted[#acted + 1] = name end
end
c.C_ChatInfo.SendAddonMessage = function() acted[#acted + 1] = "SendAddonMessage" end

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "reminders/AmmoItems.lua", "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua",
  "reminders/Display.lua", "reminders/Controller.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, C, E, ST, D, CT = R.Reminders, R.ReminderConditions, R.ReminderEval, R.ReminderState, R.ReminderDisplay, R.ReminderController
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN

local function EventCount()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function OnUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end
local function Shown(id) local f = D.Frame(id) return f ~= nil and f.shown end

local function Settle() for _ = 1, 6 do FlushTimers() end end
local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Shown(id) local f = D.Frame(id) return f ~= nil and f.shown end
c.TwichUIDB.ui = {}
RM.Invalidate()
Fire("PLAYER_ENTERING_WORLD"); Settle()

-- A rule as the view Config.lua makes of it, without saving anything
local function View(conds, match, scope)
  local raw = { id = "r99", name = "Test", enabled = true, match = match, conditions = conds, scope = scope,
    display = { mode = "text", text = "Hi" } }
  local keep = c.TwichUIDB.ui.reminders
  c.TwichUIDB.ui.reminders = { version = 1, list = { raw } }
  RM.Invalidate()
  local v = RM.Get("r99")
  c.TwichUIDB.ui.reminders = keep
  RM.Invalidate()
  return v
end
local function Class(token, negate) return { type = "class", class = token, negate = negate or false } end
local function Combat(negate) return { type = "player", state = "combat", negate = negate or false } end
local function Mounted() return { type = "player", state = "mounted" } end
local function NoShield() return { type = "equipment", slot = "offHand", what = "shield", negate = true } end
local function Group(match, ...) return { type = "group", match = match, conditions = { ... } } end
local SHIELD = { classID = 4, subClassID = 6, equipLoc = "INVTYPE_SHIELD", id = 1201 }
local EMPTY = { empty = true }
local function Obs(t) t.slots = t.slots or {}; return t end
local function Status(v, obs, ctx) return E.Run(v, obs, ctx or {}).status end
local function Result(v, obs) return E.Run(v, obs, {}).result end

---------------------------------------------------------------------------
-- A. A rule edit while a delay or a minimum is running
---------------------------------------------------------------------------
local _, id = RM.Create("shield")
RM.SetScope(id, "who", "all")
RM.SetDisplay(id, "delay", 3)
RM.SetEnabled(id, true)
Settle()
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(CT.Status(id) == "pending", "empty with a 3 s delay: pending")
RM.SetMatch(id, "any")   -- an edit of the rules while it waits
Settle()
NOW = NOW + 4; RunLongTimers(5); Settle()
Check(Shown(id), "an edit during a delay doesn't leave it waiting for ever: " .. tostring(CT.Status(id)))

-- a minimum running when the rules are edited: it still goes when the minimum is over
RM.SetDisplay(id, "delay", 0)
RM.SetDisplay(id, "minShow", 10)
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(Shown(id) and CT.Status(id) == "holding", "a minimum keeps it up")
RM.SetMatch(id, "all")
Settle()
Check(Shown(id), "an edit during the minimum doesn't take it down early")
NOW = NOW + 11; RunLongTimers(15); Settle()
Check(not Shown(id), "and it goes when the minimum is over, though the edit stopped the first timer")
RM.SetDisplay(id, "minShow", 0)
RM.Delete(id)
W.slots[17] = nil

-- a delay waiting when an edit makes the rule false: nothing shows afterwards
local _, did = RM.Create("custom")
RM.SetDisplay(did, "delay", 3)
RM.AddCondition(did, "player")
RM.SetEnabled(did, true)
W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
Check(CT.Status(did) == "pending", "in combat with a delay: pending")
Check(RM.AddCondition(did, "equipment"), "a second condition")
RM.SetCondition(did, 2, { type = "equipment", slot = "offHand", what = "shield" })   -- a shield is needed too: it isn't worn
Settle()
NOW = NOW + 4; RunLongTimers(5); Settle()
Check(not Shown(did) and CT.Status(did) == "hidden", "an edit that makes the rule false cancels the wait: nothing shows later")
RM.Delete(did)
W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()

---------------------------------------------------------------------------
-- B. Player class
---------------------------------------------------------------------------
local P = C.Get("class")
Check(P and P.label == "Player class", "a Player class condition exists")
local clean, problem = C.Check({ type = "class", class = "WARRIOR", negate = false })
Check(clean and not problem and clean.class == "WARRIOR" and clean.negate == false, "a class token is stored as given, with an explicit false")
clean, problem = C.Check({ type = "class" })
Check(clean and clean.class == nil and problem:find("class"), "no class chosen: kept, and flagged")
clean, problem = C.Check({ type = "class", class = "Warrior" })
Check(clean == nil and problem:find("class"), "a name is not a token: refused (stored values are tokens, never labels)")
Check(C.Check({ type = "class", class = "DEATHKNIGHT" }) == nil, "a class this client doesn't have is refused")
local choices = C.ClassChoices()
local toks = {}
for _, ch in ipairs(choices) do toks[#toks + 1] = ch[1] end
Check(#choices == 9 and table.concat(toks, ","):find("WARRIOR") and not table.concat(toks, ","):find("DEATHKNIGHT"), "the choices are the client's nine classes: " .. table.concat(toks, ","))
c.CLASS_SORT_ORDER = { "WARRIOR", "MAGE", "PALADIN" }
choices = C.ClassChoices()
Check(#choices == 3 and choices[2][1] == "MAGE", "a client that lists fewer classes offers only those, in its order")
c.CLASS_SORT_ORDER = nil
local keys = {}
P.Needs(Class("ROGUE"), function(k) keys[#keys + 1] = k end)
Check(#keys == 1 and keys[1] == "class", "it reads one observation: class")
local cw = View({ Class("WARRIOR") }).conditions[1]
Check(E.Condition(cw, Obs({ class = "WARRIOR" })) == MATCH and E.Condition(cw, Obs({ class = "ROGUE" })) == NOMATCH, "is: match and no match")
Check(E.Condition(cw, Obs({})) == UNKNOWN, "class not read: unknown, never a match")
local cn = View({ Class("WARRIOR", true) }).conditions[1]
Check(E.Condition(cn, Obs({ class = "ROGUE" })) == MATCH and E.Condition(cn, Obs({ class = "WARRIOR" })) == NOMATCH, "is not")
Check(E.Condition(cn, Obs({})) == UNKNOWN, "is not, unread: still unknown (not true)")
Check(E.Summary(cw) == "Player class is Warrior" and E.Summary(cn) == "Player class is not Warrior", "summaries: " .. E.Summary(cw))
Check(select(2, E.Condition(cw, Obs({ class = "HUNTER" }))) == "Hunter" and select(2, E.Condition(cw, Obs({}))) == "Not read yet", "observed words")
local unfinished = View({ { type = "class" } })
Check(not unfinished.valid and unfinished.problems[1]:find("Condition 1") and E.Run(unfinished, Obs({ class = "WARRIOR" }), {}).status == "invalid", "an unfinished class condition makes the reminder invalid")

-- the source: read once, only a different answer is a change, nothing to listen for
c.TwichUIDB.ui = {}
RM.Invalidate()
local _, cid = RM.Create("custom")
RM.SetScope(cid, "who", "all")
RM.AddCondition(cid, "class")
RM.SetCondition(cid, 1, Class("WARRIOR"))
W.class = "WARRIOR"
RM.SetEnabled(cid, true)
Settle()
Check(ST.Snapshot().keys == 1 and ST.Observations().class == "WARRIOR", "the character's class is read when a reminder wants it")
Check(CT.Status(cid) == "showing" and Shown(cid), "a Warrior with \"Player class is Warrior\": shows")
Check(ST.Snapshot().events == 1, "and listens for nothing but the world: " .. ST.Snapshot().events)
RM.SetCondition(cid, 1, Class("MAGE"))
Settle()
Check(CT.Status(cid) == "hidden" and not Shown(cid), "another class: hidden")
Check(ST.Snapshot().events == 1, "still only the world event")
RM.Delete(cid)

---------------------------------------------------------------------------
-- C. The tree as it is read
---------------------------------------------------------------------------
local tree = View({ Group("any", Class("WARRIOR"), Class("HUNTER"), Class("ROGUE")), Combat(), NoShield() }, "all")
Check(tree.valid, "(Warrior or Hunter or Rogue) and in combat and no shield is valid: " .. tostring(tree.problems[1]))
Check(#tree.conditions == 3 and tree.conditions[1].group and #tree.conditions[1].children == 3 and tree.conditions[1].match == "any", "its shape")
Check(tree.counts.conditions == 5 and tree.counts.groups == 1 and #tree.leaves == 5 and #tree.groups == 1 and #tree.flat == 6, "five conditions and one group")
local order = {}
for _, e in ipairs(tree.flat) do order[#order + 1] = table.concat(e.path, ".") .. (e.group and "g" or "") end
Check(table.concat(order, ",") == "1g,1.1,1.2,1.3,2,3", "reading order is the stored order, a group before its contents: " .. table.concat(order, ","))
Check(tree.conditions[1].depth == 1 and tree.conditions[1].children[2].depth == 2, "depth is the level of the list it is in")

---------------------------------------------------------------------------
-- D. Every combination, against a table written out by hand
---------------------------------------------------------------------------
local T, F, U = MATCH, NOMATCH, UNKNOWN
local function AllOf(a, b) if a == F or b == F then return F end if a == U or b == U then return U end return T end
local function AnyOf(a, b) if a == T or b == T then return T end if a == U or b == U then return U end return F end
local combos = { T, F, U }
local function ObsFor(a, b)   -- a is combat, b is mounted
  local o = Obs({})
  if a == T then o.combat = true elseif a == F then o.combat = false end
  if b == T then o.mounted = true elseif b == F then o.mounted = false end
  return o
end
local bad = 0
for _, a in ipairs(combos) do
  for _, b in ipairs(combos) do
    local o = ObsFor(a, b)
    if Result(View({ Group("all", Combat(), Mounted()) }, "all"), o) ~= AllOf(a, b) then bad = bad + 1 end
    if Result(View({ Group("any", Combat(), Mounted()) }, "all"), o) ~= AnyOf(a, b) then bad = bad + 1 end
    if Result(View({ Combat(), Mounted() }, "all"), o) ~= AllOf(a, b) then bad = bad + 1 end
    if Result(View({ Combat(), Mounted() }, "any"), o) ~= AnyOf(a, b) then bad = bad + 1 end
  end
end
Check(bad == 0, "all and any, flat and as a group, agree with the table for every true/false/unknown pair: " .. bad .. " wrong")
-- three states in each of three places: (A or B) and C, and A or (B and C)
bad = 0
for _, a in ipairs(combos) do for _, b in ipairs(combos) do for _, cc in ipairs(combos) do
  local o = ObsFor(a, b)
  if cc == T then o.class = "WARRIOR" elseif cc == F then o.class = "MAGE" end
  local isC = Class("WARRIOR")
  local v1 = View({ Group("any", Combat(), Mounted()), isC }, "all")
  if Result(v1, o) ~= AllOf(AnyOf(a, b), cc) then bad = bad + 1 end
  local v2 = View({ Combat(), Group("all", Mounted(), isC) }, "any")
  if Result(v2, o) ~= AnyOf(a, AllOf(b, cc)) then bad = bad + 1 end
end end end
Check(bad == 0, "an OR inside an AND and an AND inside an OR agree with the table for all 27 combinations: " .. bad .. " wrong")
-- a group of one is its child
bad = 0
for _, a in ipairs(combos) do
  local o = ObsFor(a, T)
  if Result(View({ Group("all", Combat()) }, "all"), o) ~= a or Result(View({ Group("any", Combat()) }, "any"), o) ~= a then bad = bad + 1 end
  if Result(View({ Group("any", Combat(true)) }, "all"), o) ~= (a == U and U or (a == T and F or T)) then bad = bad + 1 end
end
Check(bad == 0, "a group with one condition is that condition, true, false or unknown")
-- three levels
local deep = View({ Group("any", Combat(), Group("all", Mounted(), Class("ROGUE"))) }, "all")
Check(deep.valid and deep.counts.groups == 2 and deep.conditions[1].children[2].depth == 2, "three levels of lists are allowed")
Check(Result(deep, Obs({ combat = false, mounted = true, class = "ROGUE" })) == T and Result(deep, Obs({ combat = false, mounted = true, class = "MAGE" })) == F, "and decided from the inside out")

---------------------------------------------------------------------------
-- E. The examples
---------------------------------------------------------------------------
local anyClass = View({ Class("WARRIOR"), Class("HUNTER"), Class("ROGUE") }, "any")
for _, cl in ipairs({ "WARRIOR", "HUNTER", "ROGUE" }) do
  Check(Status(anyClass, Obs({ class = cl })) == "showing", "Warrior or Hunter or Rogue: " .. cl .. " shows")
end
Check(Status(anyClass, Obs({ class = "MAGE" })) == "hidden", "a Mage: hidden")
Check(Status(anyClass, Obs({})) == "waiting", "class not read: waiting, not showing")
local mixed = View({ Group("any", Class("WARRIOR"), Class("HUNTER"), Class("ROGUE")), Combat(), NoShield() }, "all")
local function Mixed(class, combat, off)
  local o = Obs({ class = class, combat = combat, slots = { [17] = off } })
  return Status(mixed, o)
end
Check(Mixed("HUNTER", true, EMPTY) == "showing", "a Hunter in combat with an empty off hand: shows")
Check(Mixed("ROGUE", true, SHIELD) == "hidden", "with a shield: hidden")
Check(Mixed("ROGUE", false, EMPTY) == "hidden", "out of combat: hidden")
Check(Mixed("MAGE", true, EMPTY) == "hidden", "a Mage: hidden even in combat with no shield")
Check(Mixed("WARRIOR", nil, EMPTY) == "waiting", "combat unread: waiting, not showing")
Check(Mixed("MAGE", nil, EMPTY) == "hidden", "but a Mage is a definite no whatever else is unread")
Check(Mixed(nil, true, SHIELD) == "hidden", "and a shield is a definite no whatever the class")
Check(Mixed(nil, true, EMPTY) == "waiting", "unread class with everything else true: waiting")
local plain = View({ Combat(), NoShield() }, "all")
Check(Status(plain, Obs({ combat = true, slots = { [17] = EMPTY } })) == "showing", "in combat and no shield equipped: shows")

---------------------------------------------------------------------------
-- F. Empty, unfinished and unreadable parts never become "always"
---------------------------------------------------------------------------
local empty = View({ Group("any"), Combat() }, "all")
Check(not empty.valid and empty.problems[1]:find("Group 1") and empty.problems[1]:find("no conditions"), "an empty group is a problem: " .. tostring(empty.problems[1]))
local out = E.Run(empty, Obs({ combat = true }), {})
Check(out.status == "invalid" and out.result == E.INVALID, "the reminder is invalid, not shown, though the other condition matches")
Check(E.Run(View({ Group("all") }, "any"), Obs({}), {}).status == "invalid", "an only-empty-group rule is invalid")
Check(E.Run(View({}, "all"), Obs({}), {}).status == "invalid", "no conditions at all is still invalid")
local noOp = View({ { type = "group", conditions = { Combat() } } }, "all")
Check(not noOp.valid and noOp.problems[1]:find("all or any"), "a group without an operator is a problem: " .. tostring(noOp.problems[1]))
Check(E.Run(noOp, Obs({ combat = true }), {}).status == "invalid", "and invalid")
noOp = View({ { type = "group", match = "either", conditions = { Combat() } } }, "all")
Check(not noOp.valid, "an operator it doesn't know is a problem, not read as all")
local half = View({ Group("any", Class("WARRIOR"), { type = "buff", spell = 1 }) }, "all")
Check(not half.valid and half.problems[1]:find("Condition 1.2") and half.problems[1]:find("buff"), "an unknown kind inside a group is named with its place: " .. tostring(half.problems[1]))
out = E.Run(half, Obs({ class = "WARRIOR" }), {})
Check(out.status == "invalid" and out.nodes[1].result == E.INVALID, "its group is invalid, not just true because Warrior matched")
local unfin = View({ Group("any", Class("WARRIOR"), { type = "class" }) }, "all")
Check(not unfin.valid and E.Run(unfin, Obs({ class = "WARRIOR" }), {}).status == "invalid", "an unfinished condition in an OR doesn't get left out")
Check(View({ Group("any", "not a table") }, "all").valid == false, "a group entry that isn't a table is a problem")

---------------------------------------------------------------------------
-- G. Limits and loops
---------------------------------------------------------------------------
local tooDeep = View({ Group("any", Group("all", Group("any", Combat()))) }, "all")
Check(not tooDeep.valid and tooDeep.problems[1]:find("levels deep"), "a fourth level is a problem: " .. tostring(tooDeep.problems[1]))
local tdEntry = tooDeep.conditions[1].children[1].children[1]
Check(tdEntry.group and tdEntry.why and #tdEntry.children == 0, "and is not read any further")
local many = {}
for i = 1, 7 do many[i] = Group("any", Combat()) end
local manyView = View(many, "all")
Check(not manyView.valid and manyView.counts.groups == RM.MAX_GROUPS and manyView.problems[#manyView.problems] == RM.PROBLEM.tooManyGroups, "more than " .. RM.MAX_GROUPS .. " groups: flagged, and read no further")
local lots = {}
for i = 1, 17 do lots[i] = Combat() end
local lotsView = View(lots, "all")
Check(not lotsView.valid and #lotsView.leaves == RM.MAX_CONDITIONS and lotsView.problems[1] == RM.PROBLEM.tooMany, "more than " .. RM.MAX_CONDITIONS .. " conditions: flagged")
local split = {}
for i = 1, 9 do split[i] = Combat() end
local splitView = View({ Group("any", unpack(split)), Group("any", unpack(split)) }, "all")
Check(not splitView.valid and #splitView.leaves == RM.MAX_CONDITIONS, "the conditions are counted across all the groups, not for each")
-- a group that holds itself, and a loop through the top level's own list
local selfy = { type = "group", match = "any" }
selfy.conditions = { selfy, Combat() }
local loopView = View({ selfy }, "all")
Check(not loopView.valid and loopView.problems[1]:find("contains itself"), "a group that contains itself is a problem, and reading ends: " .. tostring(loopView.problems[1]))
Check(E.Run(loopView, Obs({ combat = true }), {}).status == "invalid", "and it never shows")
local rootList = {}
local g2 = { type = "group", match = "any", conditions = rootList }
rootList[1] = g2
local loop2 = View(rootList, "all")
Check(not loop2.valid, "a loop through the top level's own list is a problem, not a hang")
-- thousands of entries can't make reading slow: bounded by the limits
local wide = {}
for i = 1, 5000 do wide[i] = Combat() end
local t0 = os.clock()
local wideView = View(wide, "all")
Check(#wideView.leaves == RM.MAX_CONDITIONS and os.clock() - t0 < 0.5, "thousands of entries are cut at the limit")
-- the API refuses to go past them
c.TwichUIDB.ui = {}
RM.Invalidate()
local _, lid = RM.Create("custom")
for _ = 1, RM.MAX_CONDITIONS do Check(RM.AddCondition(lid, "player"), "add up to the limit") end
local okFull, whyFull = RM.AddCondition(lid, "player")
Check(not okFull and whyFull == RM.REFUSE.conditionsFull, "one more is refused with a sentence: " .. tostring(whyFull))
RM.Delete(lid)
_, lid = RM.Create("custom")
local ok1, p1 = RM.AddGroup(lid)
local ok2, p2 = RM.AddGroup(lid, p1)
Check(ok1 and ok2 and #p1 == 1 and #p2 == 2, "a group in a group")
local ok3, why3 = RM.AddGroup(lid, p2)
Check(not ok3 and why3 == RM.REFUSE.tooDeep, "a third group level is refused: " .. tostring(why3))
local ok4 = RM.AddCondition(lid, "player", p2)
Check(ok4, "but a condition can go in the innermost group")
for _ = 1, RM.MAX_GROUPS - 2 do RM.AddGroup(lid) end
local ok5, why5 = RM.AddGroup(lid)
Check(not ok5 and why5 == RM.REFUSE.groupsFull, "more than " .. RM.MAX_GROUPS .. " groups is refused: " .. tostring(why5))
RM.Delete(lid)

---------------------------------------------------------------------------
-- H. Editing through the API
---------------------------------------------------------------------------
_, lid = RM.Create("custom")
local stored = c.TwichUIDB.ui.reminders.list[#c.TwichUIDB.ui.reminders.list]
Check(RM.AddCondition(lid, "player"), "a condition at the top")
local okg, gpath = RM.AddGroup(lid)
Check(okg and gpath[1] == 2, "a group after it, at path { 2 }")
Check(stored.conditions[2].type == "group" and stored.conditions[2].match == "any" and #stored.conditions[2].conditions == 0, "a new group starts empty, and matches any inside an all")
Check(RM.Get(lid).conditions[2].why and not RM.Get(lid).valid, "empty: a problem until something is put in it")
Check(RM.AddCondition(lid, "class", gpath) and RM.AddCondition(lid, "class", gpath), "two class conditions in the group")
Check(RM.SetCondition(lid, { 2, 1 }, Class("WARRIOR")) and RM.SetCondition(lid, { 2, 2 }, Class("HUNTER")), "set by path")
Check(stored.conditions[2].conditions[1].class == "WARRIOR" and stored.conditions[2].conditions[2].class == "HUNTER", "stored in the group")
Check(RM.Get(lid).valid, "now valid")
Check(RM.SetCondition(lid, { 2 }, Combat()) == false and RM.SetCondition(lid, { 2, 1 }, { type = "group" }) == false, "a group isn't replaced by a condition, nor a condition by a group")
Check(RM.SetCondition(lid, { 5, 1 }, Combat()) == false and RM.SetCondition(lid, { 1, 1 }, Combat()) == false, "paths that lead nowhere are refused")
Check(RM.SetMatch(lid, "all", gpath) and stored.conditions[2].match == "all", "a group's operator is its own")
Check(stored.match == nil or stored.match == "all", "and the top level's is not touched")
Check(RM.SetMatch(lid, "any") and stored.match == "any", "the top level's operator")
Check(RM.SetMatch(lid, "both", gpath) == false and RM.SetMatch(lid, "any", { 1 }) == false, "an operator it doesn't know, or on something that isn't a group, is refused")
Check(RM.AddCondition(lid, "nothing", gpath) == false and RM.AddCondition(lid, "player", { 1 }) == false, "unknown kinds, and 'groups' that aren't, are refused")
local before = RM.Rev()
Check(RM.RemoveCondition(lid, { 2, 1 }) and #stored.conditions[2].conditions == 1 and RM.Rev() > before, "remove a condition from a group")
Check(RM.RemoveCondition(lid, { 2 }) and #stored.conditions == 1 and stored.conditions[1].type == "player", "remove a group")
Check(RM.RemoveCondition(lid, {}) == false and RM.RemoveCondition(lid, 9) == false, "nothing to remove: refused")
-- plain data only
local function PlainData(t, depth)
  if type(t) ~= "table" then return type(t) == "string" or type(t) == "number" or type(t) == "boolean" end
  if depth > 6 then return false end
  for k, v in pairs(t) do
    if type(k) ~= "string" and type(k) ~= "number" then return false end
    if not PlainData(v, depth + 1) then return false end
  end
  return true
end
RM.AddGroup(lid)
RM.AddCondition(lid, "class", { 2 })
Check(PlainData(stored, 0), "what is stored is plain values: no functions, frames or references")
for k in pairs(stored.conditions[2]) do Check(({ type = 1, match = 1, conditions = 1 })[k], "a group stores only type, match and conditions: " .. k) end
-- duplicate copies the tree, not a reference to it
local okd, dup = RM.Duplicate(lid)
local dupRaw
for _, raw in ipairs(c.TwichUIDB.ui.reminders.list) do if raw.id == dup then dupRaw = raw end end
Check(okd and dupRaw.conditions[2].conditions ~= stored.conditions[2].conditions, "a duplicate has groups of its own")
dupRaw.conditions[2].conditions[1].class = "MAGE"
Check(stored.conditions[2].conditions[1].class ~= "MAGE", "changing the copy leaves the original")
RM.Delete(dup); RM.Delete(lid)

---------------------------------------------------------------------------
-- I. Literal false, zero and absent values
---------------------------------------------------------------------------
local lit = View({ Group("all", Combat(), Class("WARRIOR", false)) }, "all")
Check(Result(lit, Obs({ combat = false, class = "WARRIOR" })) == F, "combat = false is a definite no, not unread")
Check(Result(lit, Obs({ class = "WARRIOR" })) == U, "combat absent is unknown")
Check(lit.conditions[1].children[2].cond.negate == false and lit.conditions[1].children[1].cond.negate == false, "negate = false is kept as false")
local ids = View({ { type = "equipment", slot = "offHand", what = "item", item = 1201, negate = false } })
Check(ids.valid and Result(ids, Obs({ slots = { [17] = { id = 0, classID = 4 } } })) == F, "an item id of 0 in a slot is not the item")
local zero = View({ { type = "equipment", slot = "offHand", what = "item", item = 0 } })
Check(not zero.valid, "an item id of 0 is not a usable item")

---------------------------------------------------------------------------
-- J. Existing reminders are read exactly as before
---------------------------------------------------------------------------
local flatRaw = { id = "r5", name = "Old", enabled = true, match = "any", scope = { who = "all", characters = {}, class = "WARRIOR" },
  conditions = { NoShield(), Combat() }, display = { mode = "text", text = "Hi" }, place = { preset = "belowCenter" } }
local function Dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
c.TwichUIDB.ui.reminders = { version = 1, nextId = 6, list = { flatRaw } }
local snapshot = Dump(c.TwichUIDB.ui.reminders)
RM.Invalidate()
local fv = RM.Get("r5")
Check(fv.valid and fv.match == "any" and #fv.conditions == 2 and not fv.conditions[1].group and fv.scope.class == "WARRIOR", "a flat rule with its scope is read as it always was")
Check(E.RuleSentence(fv) == "Shows when any of these is true: Off hand is not Shield; or Player is in combat.", "its sentence is unchanged: " .. E.RuleSentence(fv))
for _ = 1, 3 do RM.Invalidate(); RM.Get("r5"); RM.List() end
Check(Dump(c.TwichUIDB.ui.reminders) == snapshot, "reading it again and again changes nothing in what is saved (nothing to migrate, so nothing to repeat)")
Check(c.TwichUIDB.ui.reminders.version == 1, "the stored shape is still version 1")
Check(C.providers.group == nil, "groups are not a provider: a build without them sees an unknown kind (kept, not run)")
-- a newer table is never written
c.TwichUIDB.ui.reminders.version = 2
RM.Invalidate()
Check(RM.AddGroup("r5") == false and RM.AddCondition("r5", "player") == false and RM.SetMatch("r5", "all") == false, "a table from a newer version isn't changed")
Check(Dump(c.TwichUIDB.ui.reminders):find("version=2") and #flatRaw.conditions == 2, "and is as it was")
c.TwichUIDB.ui.reminders.version = 1
c.TwichUIDB.ui = {}
RM.Invalidate()

---------------------------------------------------------------------------
-- K. Who it is for is separate from what it matches
---------------------------------------------------------------------------
local forMage = View({ Class("WARRIOR") }, "all", { who = "all", class = "MAGE" })
Check(E.Run(forMage, Obs({ class = "WARRIOR" }), { class = "WARRIOR" }).status == "notApplicable", "a Mage-only reminder doesn't run for a Warrior, though its condition would match")
Check(E.Run(forMage, Obs({ class = "MAGE" }), { class = "MAGE" }).status == "hidden", "for a Mage the condition decides")
local anyone = View({ Class("WARRIOR") }, "all", { who = "all" })
Check(E.Run(anyone, Obs({ class = "WARRIOR" }), { class = "WARRIOR" }).status == "showing" and E.Run(anyone, Obs({ class = "MAGE" }), { class = "MAGE" }).status == "hidden", "without a restriction the class condition is the whole test")
Check(E.Run(anyone, Obs({}), { class = nil }).status == "waiting", "applicability unknown and class unread: waiting")

---------------------------------------------------------------------------
-- L. The rule in words
---------------------------------------------------------------------------
Check(E.RuleSentence(anyClass) == "Shows when: Player class is Warrior, Hunter or Rogue.", "Warrior, Hunter or Rogue: " .. E.RuleSentence(anyClass))
Check(E.RuleSentence(mixed) == "Shows when all of these are true: Player class is Warrior, Hunter or Rogue; and Player is in combat; and Off hand is not Shield.", "the mixed rule: " .. E.RuleSentence(mixed))
local notThese = View({ Class("WARRIOR", true), Class("MAGE", true) }, "all")
Check(E.RuleSentence(notThese) == "Shows when: Player class is none of Warrior or Mage.", "not these: " .. E.RuleSentence(notThese))
local halfMerge = View({ Class("WARRIOR"), Class("MAGE", true), Class("ROGUE") }, "any")
Check(E.RuleSentence(halfMerge) == "Shows when any of these is true: Player class is Warrior or Rogue; or Player class is not Mage.", "only what means the same is merged: " .. E.RuleSentence(halfMerge))
local grouped = View({ Combat(), Group("all", Mounted(), NoShield()) }, "any")
Check(E.RuleSentence(grouped) == "Shows when any of these is true: Player is in combat; or (all of: Player is mounted; and Off hand is not Shield).", "a group that can't be merged keeps its parentheses: " .. E.RuleSentence(grouped))
local nested = View({ Group("any", Combat(), Group("all", Mounted(), NoShield())), Class("ROGUE") }, "all")
Check(E.RuleSentence(nested) == "Shows when all of these are true: (any of: Player is in combat; or (all of: Player is mounted; and Off hand is not Shield)); and Player class is Rogue.", "nested groups: " .. E.RuleSentence(nested))
local onlyGroup = View({ Group("any", Combat(), Mounted()) }, "all")
Check(E.RuleSentence(onlyGroup) == "Shows when any of these is true: Player is in combat; or Player is mounted.", "a top level that is one group reads as that group: " .. E.RuleSentence(onlyGroup))
local oneIn = View({ Group("any", Combat()), Mounted() }, "all")
Check(E.RuleSentence(oneIn) == "Shows when all of these are true: Player is in combat; and Player is mounted.", "a group of one says just its condition: " .. E.RuleSentence(oneIn))
Check(E.RuleSentence(empty):find("empty"), "an empty group is named in the sentence: " .. E.RuleSentence(empty))
Check(E.Summary(tree.conditions[1]) == "Player class is Warrior, Hunter or Rogue", "a group has a summary of its own")
Check(E.GroupWords("any") == "Match any - OR" and E.GroupWords("all") == "Match all - AND", "the group headings")

---------------------------------------------------------------------------
-- M. The result of every part, for the inspector
---------------------------------------------------------------------------
local o = Obs({ class = "ROGUE", combat = false, slots = { [17] = SHIELD } })
out = E.Run(mixed, o, { class = "ROGUE" })
Check(out.status == "hidden" and out.result == F, "the whole: no match")
local words = {}
for i, n in ipairs(out.nodes) do words[i] = ("%s%s=%s"):format(n.group and "G" or "", n.depth, n.result) end
Check(table.concat(words, ",") == "G1=match,2=nomatch,2=nomatch,2=match,1=nomatch,1=nomatch", "a result for each group and condition, in reading order: " .. table.concat(words, ","))
Check(out.nodes[1].summary == "Match any - OR" and out.nodes[4].observed == "Rogue" and out.nodes[5].observed == "Out of combat", "with what was observed")
Check(#out.conditions == 5 and out.conditions[1] == out.nodes[2], "the conditions alone are the same entries")
out = E.Run(mixed, Obs({ class = "ROGUE", slots = {} }), {})
Check(out.nodes[5].result == U and out.nodes[5].reason and out.nodes[6].result == U and out.nodes[1].result == T, "an unknown part says why: " .. tostring(out.nodes[5].reason))
out = E.Run(mixed, Obs({ combat = false, slots = {} }), {})
Check(out.nodes[1].result == U and out.nodes[2].result == U and out.status == "hidden", "an unread class is unknown in its group (and the rule is a definite no because combat is false)")
-- every condition is read even when the first settles it
local read = 0
local probe = { type = "probe" }
C.Register({ type = "probe", label = "probe", New = function() return { type = "probe" } end, Check = function() return { type = "probe" } end,
  Needs = function() end, Evaluate = function() read = read + 1 return MATCH end, Summary = function() return "Probe" end,
  Observed = function() return "x" end, Scenarios = function() return {} end })
local both = View({ Combat(), probe, probe }, "any")
read = 0
E.Run(both, Obs({ combat = true }), {})
Check(read == 2, "no condition is skipped because another already settled the answer: " .. read)
C.providers.probe = nil; C.order[#C.order] = nil
-- nodes are reused from one decision to the next
out = E.Run(mixed, o, {})
local reuse = out
local firstNode, firstList = out.nodes[3], out.conditions
out = E.Run(mixed, Obs({ class = "HUNTER", combat = true, slots = { [17] = EMPTY } }), {}, out)
Check(out == reuse and out.nodes[3] == firstNode and out.conditions == firstList, "the tree of results is reused, not rebuilt, for each decision")
Check(out.status == "showing" and out.nodes[3].result == T, "and holds this decision, not the last one")
out = E.Run(plain, Obs({ combat = true, slots = { [17] = EMPTY } }), {}, out)
Check(#out.nodes == 2 and out.nodes[3] == nil and #out.conditions == 2, "a smaller rule leaves no stale lines")

---------------------------------------------------------------------------
-- N. Simulation
---------------------------------------------------------------------------
local inputs = E.SimInputs(anyClass)
Check(#inputs == 1 and #inputs[1].leaves == 3 and inputs[1].label == "Player class", "three class conditions share one choice")
local sc = {}
for _, x in ipairs(inputs[1].scenarios) do sc[#sc + 1] = x.key end
Check(sc[1] == "WARRIOR" and sc[#sc] == "unread" and #sc == 10, "every class, then 'not read': " .. table.concat(sc, ","))
Check(E.Simulate(anyClass, { "ROGUE" }).status == "showing" and E.Simulate(anyClass, { "MAGE" }).status == "hidden", "simulated Rogue shows, Mage doesn't")
Check(E.Simulate(anyClass, { "unread" }).status == "waiting", "simulated unread: waiting")
local simMixed = E.SimInputs(mixed)
Check(#simMixed == 3, "mixed: one choice each for class, combat and off hand: " .. #simMixed)
Check(E.Simulate(mixed, { "HUNTER", "on", "empty" }).status == "showing", "simulated Hunter, in combat, empty off hand: shows")
Check(E.Simulate(mixed, { "HUNTER", "on", "match" }).status == "hidden", "with a shield: hidden")
Check(E.Simulate(mixed, { "MAGE", "on", "empty" }).status == "hidden", "a simulated Mage: hidden")
local simOut = E.Simulate(mixed, { "HUNTER", "on", "empty" })
Check(simOut.simulated and simOut.nodes[1].group and simOut.nodes[1].result == T, "a simulation has the same tree of results")
local twice = View({ Combat(), Group("any", Combat(true), Mounted()) }, "all")
Check(#E.SimInputs(twice) == 2, "two conditions about combat share one choice; mounted has its own")
Check(E.Simulate(twice, { "on", "on" }).status == "showing", "in combat (so 'not in combat' is false) and mounted: the group holds")
Check(E.Simulate(twice, { "on", "off" }).status == "hidden", "in combat and not mounted: the group fails")
-- isolation: nothing live is read, written or saved
local liveObs = ST.Observations()
local savedBefore = Dump(c.TwichUIDB.ui)
local liveClass = liveObs.class
E.Simulate(mixed, { "ROGUE", "on", "empty" })
Check(ST.Observations() == liveObs and liveObs.class == liveClass and Dump(c.TwichUIDB.ui) == savedBefore, "a simulation touches neither the live observations nor what is saved")

---------------------------------------------------------------------------
-- O. Live: every branch is heard, nothing twice, nothing left behind by an edit
---------------------------------------------------------------------------
c.TwichUIDB.ui = {}
RM.Invalidate()
W.class, W.combat = "HUNTER", false
W.slots[17] = nil
local _, gid = RM.Create("custom")
RM.SetScope(gid, "who", "all")
local graw = c.TwichUIDB.ui.reminders.list[1]
graw.match = "all"
graw.conditions = { Group("any", Class("WARRIOR"), Class("HUNTER"), Class("ROGUE")), Combat(), NoShield() }
RM.Invalidate()
Check(RM.Get(gid).valid, "the example reminder is valid")
RM.SetEnabled(gid, true)
Settle()
local snap = ST.Snapshot()
Check(snap.keys == 3, "it reads class, combat and the off hand, each once: " .. snap.keys)
Check(ST.Registered("PLAYER_REGEN_DISABLED") and ST.Registered("PLAYER_REGEN_ENABLED") and ST.Registered("PLAYER_EQUIPMENT_CHANGED") and snap.events == 4,
  "and listens for combat and equipment, plus the world: " .. snap.events)
Check(CT.Snapshot().keys == 3, "the index has three keys")
Check(not Shown(gid) and CT.Status(gid) == "hidden", "out of combat: hidden")
local d0 = CT.Snapshot().decisions
W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
Check(Shown(gid), "a Hunter in combat with no shield: shows")
Check(CT.Snapshot().decisions == d0 + 1, "one event, one decision (the class conditions are three branches, not three listeners): " .. (CT.Snapshot().decisions - d0))
W.slots[17] = 1201; Fire("PLAYER_EQUIPMENT_CHANGED", 17, true); Settle()
Check(not Shown(gid), "a shield: hidden")
W.slots[17] = nil; Fire("PLAYER_EQUIPMENT_CHANGED", 17, false); Settle()
Check(Shown(gid), "off again: shows")
-- the inspector reads the running reminder's own decision
local live = CT.Inspect(gid)
Check(live.nodes[1].group and live.nodes[1].result == T and live.nodes[3].result == T and live.nodes[2].result == F, "Right now: a result for each part, Hunter matching its branch")
-- branches that no longer exist are no longer listened for
RM.RemoveCondition(gid, 2)   -- the combat condition
Settle()
Check(ST.Snapshot().keys == 2 and not ST.Registered("PLAYER_REGEN_DISABLED"), "removing a branch stops listening for what only it read")
-- ... and what the combat events last said is not believed once they are no longer heard
W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
RM.AddCondition(gid, "player")
RM.SetCondition(gid, 2, Combat())
Settle()
Check(ST.Observations().combat == false, "a combat condition added back reads the game, not the last event it heard: " .. tostring(ST.Observations().combat))
RM.RemoveCondition(gid, 2)
Settle()
RM.RemoveCondition(gid, 1)   -- the class group, with its three conditions
Settle()
Check(ST.Snapshot().keys == 1 and CT.Snapshot().keys == 1, "removing a group stops reading what only it read")
RM.AddGroup(gid)
Settle()
Check(CT.Status(gid) == "invalid" and not Shown(gid), "adding an empty group takes a showing reminder down at once: invalid")
Check(ST.Snapshot().keys == 0, "and an invalid reminder reads nothing")
RM.AddCondition(gid, "class", { 2 })
RM.SetCondition(gid, { 2, 1 }, Class("HUNTER"))
RM.SetMatch(gid, "any")
Settle()
Check(Shown(gid) and CT.Status(gid) == "showing", "filled in and valid again: shows (Hunter, any)")
local frames0, events0 = #frames, ST.Snapshot().events
for _ = 1, 5 do RM.AddCondition(gid, "player", { 2 }); RM.RemoveCondition(gid, { 2, 2 }) end
Settle()
Check(#frames == frames0 and ST.Snapshot().events == events0, "editing again and again makes no frames and no listeners")
RM.Delete(gid)
Settle()
Check(ST.Snapshot().keys == 0 and not Shown(gid), "deleted: nothing read")

---------------------------------------------------------------------------
-- P. Nothing acts in the game
---------------------------------------------------------------------------
Check(#acted == 0, "no item equipped or used, nothing cast or sent: " .. table.concat(acted, ","))

print(failures == 0 and "PASSED" or (failures .. " FAILED"))
