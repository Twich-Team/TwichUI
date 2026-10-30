-- Reminders: the "Talent specialization" condition (reminders/Conditions.lua, State.lua's "talent" source,
-- gear/Data.lua's TalentSpent). A fake world stands in for the game's talent data, so this checks our logic, not the
-- game: the in-game checks are in docs/reminders.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

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

c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemWeaponSubclass = { Fishingpole = 20 }, ItemArmorSubclass = { Shield = 6 } }
c.GetTime = function() return 1000 end
c.issecretvalue = function() return false end
c.UnitAffectingCombat = function() return false end
c.UnitIsDeadOrGhost = function() return false end
c.UnitIsGhost = function() return false end
c.IsMounted = function() return false end

-- The talent data: the class, whether the game has initialized it, the points per tree skillLine
local T
local WARRIOR = { 26, 256, 257 }
local SHAMAN = { 375, 373, 374 }
local function World(class, lines, points)
  T = { class = class, init = true, lines = lines, points = points or {}, reads = 0 }
end
World("SHAMAN", SHAMAN, {})
c.UnitClassBase = function() return T.class end
c.UnitClass = function() return T.class, T.class end
c.C_SpecializationInfo = {
  IsInitialized = function() return T.init end,
  GetActiveSpecGroup = function() return 1 end,
  GetCombatConfigIDForSpecGroup = function() return 7 end,
  GetSpecialization = function() return 1 end,
}
c.C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 1 } } end,
  GetGroupDisplayInfoByTreeID = function()
    local out = {}
    for i, line in ipairs(T.lines) do out[i] = { groupID = 100 + i, displayName = "Tree" .. i, skillLineID = line, orderIndex = i } end
    return out
  end,
  GetGroupCurrencyInfo = function()
    T.reads = T.reads + 1
    local out = {}
    for i, line in ipairs(T.lines) do out[i] = { traitNodeGroupID = 100 + i, currencyInfos = { { spent = T.points[line] or 0 } } } end
    return out
  end,
}
c.C_ClassTalents = { GetActiveConfigID = function() return 7 end }

local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "Icons.lua",
  "gear/Weights.lua", "gear/Prefs.lua", "gear/Data.lua",
  "reminders/AmmoItems.lua", "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua",
  "reminders/Display.lua", "reminders/Controller.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local RM, C, E, ST, D = R.Reminders, R.ReminderConditions, R.ReminderEval, R.ReminderState, R.ReminderDisplay
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local P = C.Get("talent")

local function Cond(t) t.type = "talent"; return t end
local function Eval(cond, talent)
  local clean = assert(C.Check(cond))
  return (P.Evaluate(clean, { talent = talent }))
end

---------------------------------------------------------------------------
-- 1. The judgement from points: unique leader, ties, nothing spent, unreadable
---------------------------------------------------------------------------
do
  local L = C.TalentLeader
  Check(L("SHAMAN", { { 375, 11 }, { 373, 10 }, { 374, 0 } }) == "SHAMAN:375", "11/10/0: no majority needed")
  Check(L("SHAMAN", { { 375, 1 }, { 373, 0 }, { 374, 0 } }) == "SHAMAN:375", "1/0/0: one point is enough")
  Check(L("SHAMAN", { { 375, 0 }, { 373, 0 }, { 374, 31 } }) == "SHAMAN:374", "the last tree can lead")
  Check(L("SHAMAN", { { 375, 5 }, { 373, 5 }, { 374, 0 } }) == "tied", "equal highest positive totals tie")
  Check(L("SHAMAN", { { 375, 5 }, { 373, 5 }, { 374, 5 } }) == "tied", "a three-way tie")
  Check(L("SHAMAN", { { 375, 0 }, { 373, 0 }, { 374, 0 } }) == "none", "all zero: no points spent")
  Check(L("SHAMAN", { { 375, 3 }, { 373, 5 }, { 374, 5 } }) == "tied", "a tie at the top, a lower tree behind")
  Check(L("SHAMAN", { { 375, 4 }, { 373, 4 }, { 374, 5 } }) == "SHAMAN:374", "a tie below the leader is not a tie")
  Check(L("SHAMAN", {}) == nil and L("SHAMAN", nil) == nil and L(nil, { { 1, 1 } }) == nil, "no data: unknown")
  Check(L("SHAMAN", { { 375, 1 }, { 373, nil } }) == nil and L("SHAMAN", { { 375, "x" } }) == nil, "an unreadable count is unknown, never zero")
end

---------------------------------------------------------------------------
-- 2. The condition: both operators, cross-class, unknown under negation
---------------------------------------------------------------------------
do
  local resto = { class = "SHAMAN", tree = 374 }
  Check(Eval(Cond({ class = "SHAMAN", tree = 374 }), "SHAMAN:374") == MATCH, "is: the leading tree")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374 }), "SHAMAN:373") == NOMATCH, "is: another tree")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374 }), "tied") == NOMATCH, "is: false for a known tie")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374 }), "none") == NOMATCH, "is: false when no points are spent")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374 }), "WARRIOR:257") == NOMATCH, "is: false for another class")
  Check(Eval(Cond({ class = "DRUID", tree = 573 }), "SHAMAN:374") == NOMATCH, "Restoration (Druid) is not Restoration (Shaman)")
  Check(Eval(Cond({ class = "PRIEST", tree = 56 }), "PALADIN:594") == NOMATCH, "Holy (Priest) is not Holy (Paladin)")
  Check(Eval(Cond({ class = "WARRIOR", tree = 257 }), "WARRIOR:257") == MATCH, "Protection (Warrior)")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374, negate = true }), "SHAMAN:374") == NOMATCH, "is not: the leading tree")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374, negate = true }), "SHAMAN:373") == MATCH, "is not: another tree")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374, negate = true }), "tied") == MATCH, "is not: true for a known tie")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374, negate = true }), "none") == MATCH, "is not: true when nothing is spent")
  Check(Eval(Cond({ class = "SHAMAN", tree = 374, negate = true }), "WARRIOR:257") == MATCH, "is not: true for another class")
  Check(Eval(Cond({ state = "tied" }), "tied") == MATCH and Eval(Cond({ state = "tied" }), "SHAMAN:374") == NOMATCH, "the tied state")
  Check(Eval(Cond({ state = "none" }), "none") == MATCH and Eval(Cond({ state = "none" }), "tied") == NOMATCH, "the no points state")
  Check(Eval(Cond({ state = "tied" }), "WARRIOR:257") == NOMATCH and Eval(Cond({ state = "tied", negate = true }), "WARRIOR:257") == MATCH,
    "the states don't depend on the class")
  for _, cond in ipairs({ Cond({ class = "SHAMAN", tree = 374 }), Cond({ class = "SHAMAN", tree = 374, negate = true }),
    Cond({ state = "tied" }), Cond({ state = "none", negate = true }) }) do
    local result, why = P.Evaluate(assert(C.Check(cond)), { })
    Check(result == UNKNOWN and type(why) == "string", "unread talents are unknown for either operator")
  end
  local needs = {}
  P.Needs(Cond({ state = "tied" }), function(k) needs[#needs + 1] = k end)
  Check(#needs == 1 and needs[1] == "talent", "it reads the talent observation")
end

---------------------------------------------------------------------------
-- 3. Stored form: round trip, defaults, invalid and unsupported values kept apart
---------------------------------------------------------------------------
do
  local raw = { type = "talent", negate = true, class = "WARRIOR", tree = 257 }
  local clean = C.Check(raw)
  Check(clean and clean.class == "WARRIOR" and clean.tree == 257 and clean.negate == true and clean.state == nil, "a tree round-trips by class and skillLine")
  local again = C.Check(clean)
  Check(again.class == clean.class and again.tree == clean.tree and again.negate == clean.negate, "and again")
  Check(C.Check({ type = "talent", state = "tied" }).state == "tied", "a state round-trips")
  local _, problem = C.Check({ type = "talent" })
  Check(type(problem) == "string", "nothing chosen is said, and still usable as a draft")
  Check(select(1, C.Check({ type = "talent", class = "SHAMAN", tree = 999 })) == nil, "a tree the class doesn't have is refused")
  Check(select(1, C.Check({ type = "talent", class = "WARRIOR", tree = 374 })) == nil, "a tree of another class is not substituted")
  Check(select(1, C.Check({ type = "talent", class = "DEATHKNIGHT", tree = 1 })) == nil, "an unknown class is refused")
  Check(select(1, C.Check({ type = "talent", state = "sideways" })) == nil, "an unknown state is refused")
  Check(select(1, C.Check({ type = "talent", state = "tied", class = "SHAMAN", tree = 374 })) == nil, "a state with a tree is ambiguous: refused")
  Check(select(1, C.Check({ type = "talent", class = "SHAMAN", tree = "374" })) == nil, "a tree that isn't a number is refused")

  -- unsupported values stay as saved in a reminder
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  local saved = { type = "talent", class = "SHAMAN", tree = 999 }
  c.TwichUIDB.ui.reminders = { version = 1, list = { { id = "r1", name = "T", enabled = false, match = "all", conditions = { saved },
    display = { mode = "text", text = "Hi" } } } }
  RM.Invalidate()
  local v = RM.Get("r1")
  Check(v and not v.valid and c.TwichUIDB.ui.reminders.list[1].conditions[1] == saved and saved.tree == 999, "an unsupported tree is kept exactly as saved, and the reminder can't run")

  -- defaults: the current player's class, and nothing else is changed by who edits later
  World("WARRIOR", WARRIOR, {})
  local new = P.New()
  Check(new.class == "WARRIOR" and new.tree == 26 and new.negate == false, "a new condition names the current class")
  World("SHAMAN", SHAMAN, {})
  Check(P.New().class == "SHAMAN" and C.Check(clean).class == "WARRIOR", "an existing condition is not changed by another character")
  World("NOTACLASS", {}, {})
  Check(P.New().class == nil, "an unknown class leaves it to be chosen")
  World("SHAMAN", SHAMAN, {})

  -- words
  Check(P.Summary(C.Check({ type = "talent", class = "SHAMAN", tree = 374 })) == "Talent specialization is Restoration (Shaman)", "summary: " .. P.Summary(C.Check({ type = "talent", class = "SHAMAN", tree = 374 })))
  Check(P.Summary(C.Check({ type = "talent", class = "WARRIOR", tree = 257, negate = true })) == "Talent specialization is not Protection (Warrior)", "summary, negated")
  Check(P.Summary(C.Check({ type = "talent", state = "tied" })) == "Talent specialization is Tied talent trees")
  Check(P.Summary(C.Check({ type = "talent", state = "none" })) == "Talent specialization is No talent points spent")
  Check(P.Observed(nil, { talent = "tied" }) == "Tied talent trees" and P.Observed(nil, {}) == "Not read yet", "what it saw")

  -- the choices the editor offers: every tree once, plus the two states, all resolvable
  local seen, n = {}, 0
  for _, ch in ipairs(C.TalentChoices()) do
    n = n + 1
    Check(not seen[ch[1]] and C.TalentWords(ch[1]) == ch[2], "choice " .. ch[1] .. " is unique and resolvable")
    seen[ch[1]] = true
  end
  Check(seen.tied and seen.none and seen["SHAMAN:374"] and seen["DRUID:573"] and n == 2 + 3 * 9, "two states and every tree of the nine classes: " .. n)
  local lines = {}
  for key in pairs(seen) do local l = key:match(":(%d+)$"); if l then Check(not lines[l], "skillLine " .. l .. " is in one class only"); lines[l] = true end end

end

---------------------------------------------------------------------------
-- 4. The source: reading the game, and staying current after changes
---------------------------------------------------------------------------
do
  local id = "r2"
  c.TwichUIDB.ui.reminders = { version = 1, list = { { id = id, name = "Resto", enabled = true, match = "all",
    conditions = { { type = "talent", class = "SHAMAN", tree = 374 } }, display = { mode = "text", text = "Hi" } } } }
  RM.Invalidate()
  local CT = R.ReminderController
  CT.Refresh()
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  Check(RM.SetEnabled(id, true), "turned on")
  Settle()
  local function Shown() local f = D.Frame(id) return f ~= nil and f.shown end
  local function Obs() return ST.Observations().talent end

  Check(Obs() == "none" and not Shown(), "nothing spent yet: no points")
  Check(ST.Registered("PLAYER_TALENT_UPDATE") and ST.Registered("CHARACTER_POINTS_CHANGED") and ST.Registered("ACTIVE_TALENT_GROUP_CHANGED"), "it listens for talent changes")

  T.points = { [374] = 1 }
  Fire("CHARACTER_POINTS_CHANGED"); Settle()
  Check(Obs() == "SHAMAN:374" and Shown(), "spending one point in the tree shows it")

  T.points = { [374] = 10, [373] = 11 }
  Fire("PLAYER_TALENT_UPDATE"); Settle()
  Check(Obs() == "SHAMAN:373" and not Shown(), "another tree takes the lead")

  T.points = { [374] = 11, [373] = 11 }
  Fire("PLAYER_TALENT_UPDATE"); Settle()
  Check(Obs() == "tied" and not Shown(), "a tie")

  T.points = { [374] = 11, [373] = 10 }
  Fire("ACTIVE_TALENT_GROUP_CHANGED"); Settle()
  Check(Obs() == "SHAMAN:374" and Shown(), "a talent group change is read")

  T.points = {}
  Fire("PLAYER_TALENT_UPDATE"); Settle()
  Check(Obs() == "none" and not Shown(), "a reset: no points")

  T.points = { [374] = 5 }
  T.init = false
  Fire("PLAYER_TALENT_UPDATE"); Settle()
  Check(Obs() == nil and not Shown(), "uninitialized talent data is unknown, never 'no points'")
  T.init = true
  Fire("PLAYER_TALENT_UPDATE"); Settle()
  Check(Obs() == "SHAMAN:374" and Shown(), "and is read once it is there")

  local reads = T.reads
  Settle(); Settle()
  Check(T.reads == reads, "no polling: nothing is read without an event")

  -- Peek (the settings window's look at a reminder that isn't running)
  local view = RM.Get(id)
  Check(ST.Peek(view).talent == "SHAMAN:374", "a peek reads it into a table of its own")

  RM.SetEnabled(id, false)
  Settle()
  Check(not ST.Registered("PLAYER_TALENT_UPDATE") and ST.Observations().talent == nil, "off: not listened for, not kept")
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
