dofile(TESTS .. "harness.lua")
-- New training at level-up: which spells are listed (class, faction, race, talent, known
-- spells and later ranks, prerequisites), one card for several levels, nothing when nothing
-- applies, nothing at login, waiting for combat and banners, names the game can't give left
-- out, the list opening, cleanup, off when switched off, and the bundled data's shape.
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
    if k == "SetHeight" then return function(s, v) s.height = v end end
    if k == "EnableMouse" then return function(s, v) s.mouse = v end end
    if k == "SetPoint" then return function(s, ...) s.point = {...} end end
    if k == "ClearAllPoints" then return function(s) s.point = nil end end
    if k == "SetColorTexture" then return function(s, ...) s.color = {...} end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({owner = s, plays = 0})
      g.Play = function(self) self.playing = true; self.plays = self.plays + 1 end
      g.Stop = function(self) self.playing = false end
      g.IsPlaying = function(self) return self.playing end
      g.CreateAnimation = function()
        local a = Fake()
        a.SetOffset = function(self, x, y) self.y = y end
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
-- The game's Edit Mode: its EventRegistry callbacks, and whether it is open.
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }
c.GameTooltip = Fake()

-- Fires an event on the shared bus and on the card's own frame.
local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(fakes) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

c.LEVEL, c.CLASS, c.FACTION, c.RACE = 9, "MAGE", "Alliance", 1
c.COMBAT, c.TOAST = false, false
c.KNOWN, c.NAMES, c.RANKS, c.UNCACHED, c.REQUESTED = {}, {}, {}, {}, {}
c.UnitLevel = function() return c.LEVEL end
c.UnitClass = function() return "Class", c.CLASS end
c.UnitFactionGroup = function() return c.FACTION, c.FACTION end
c.UnitRace = function() return "Race", "Race", c.RACE end
c.InCombatLockdown = function() return c.COMBAT end
c.EventToastManagerFrame = Fake()
c.ARRIVAL = false
c.EventToastManagerFrame.IsCurrentlyToasting = function() return c.TOAST end
c.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
c.C_SpellBook = {
  IsSpellKnown = function(id, bank) assert(bank == nil or bank == 0, "player spells"); return c.KNOWN[id] == true end,
  IsSpellInSpellBook = function(id, bank, overrides) assert(bank == 0 and overrides == false); return false end,
}
c.C_Spell = {
  GetSpellName = function(id) return c.NAMES[id] end,
  GetSpellSubtext = function(id) return c.RANKS[id] or "" end,
  GetSpellTexture = function(id) return 1000 + id end,
  IsSpellDataCached = function(id) return not c.UNCACHED[id] end,
  RequestLoadSpellData = function(id) c.REQUESTED[id] = true end,
}

for _, f in ipairs({"chronicle/Style.lua", "modules/Arrival.lua", "modules/WelcomeBack.lua",
    "modules/TrainingData.lua", "modules/Training.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local T = R.Training
local M = c.TwichUIDB.modules
assert(M.trainingNotice == true, "on by default")
local events = R.frame.events
assert(events.PLAYER_LEVEL_UP, "listens for level-ups while on")

---------------------------------------------------------------------------
-- The bundled data: What's Training?'s Forever set, in the shape the notice reads.
---------------------------------------------------------------------------
local REAL = R.TrainingData
local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
for _, class in ipairs(CLASSES) do
  local levels, ranks = REAL[class]()
  local seen = {}
  for level, list in pairs(levels) do
    assert(type(level) == "number" and level >= 1 and level <= 60, class .. " level " .. tostring(level))
    for _, e in ipairs(list) do
      assert(type(e[1]) == "number", class .. " spell id")
      assert(not seen[e[1]], class .. " lists " .. e[1] .. " once")
      seen[e[1]] = level
      assert(e.faction == nil or e.faction == "Alliance" or e.faction == "Horde")
      for _, key in ipairs({ "req", "race" }) do
        for _, v in ipairs(e[key] or {}) do assert(type(v) == "number", class .. " " .. key) end
      end
      assert(e.talent == nil or type(e.talent) == "number")
    end
  end
  for _, group in ipairs(ranks) do for _, id in ipairs(group) do assert(type(id) == "number") end end
end
do
  local mage = REAL.MAGE()
  local forever = false
  for _, e in ipairs(mage[6]) do if e[1] == 1296017 then forever = true end end
  assert(forever, "the Forever data set (it has Forever's own spells), not Classic Era's")
  local hunter = REAL.HUNTER()
  for _, list in pairs(hunter) do for _, e in ipairs(list) do assert(e[1] ~= 4187, "pet abilities are left out") end end
end
-- A Mage reaching level 4 who trained Arcane Intellect at 1: Conjure Water and Frostbolt are waiting.
do
  local list = T.Select((REAL.MAGE()), select(2, REAL.MAGE()), 4, { faction = "Alliance", race = 1 }, function(id) return id == 1459 end)
  assert(#list == 2 and list[1].id == 5504 and list[2].id == 116, "Conjure Water and Frostbolt")
end

---------------------------------------------------------------------------
-- Selection, on a small made-up data set.
---------------------------------------------------------------------------
local LEVELS = {
  [10] = { {101}, {102, req = {100}} },            -- a new spell; rank 2 of a known spell
  [11] = {},
  [12] = { {103, faction = "Horde"}, {104, faction = "Alliance"}, {105, race = {2}}, {106, race = {1, 3}},
           {107, talent = 900}, {108, talent = 901} },
  [13] = { {109, req = {101}} },                   -- needs 101, itself new at 10
  [14] = { {110} },                                -- already known
  [15] = { {112} },
  [16] = { {111, req = {999}} },                   -- needs a spell the character doesn't have
  [18] = { {201, req = {200}} },                   -- a replaced rank: 202 is known, so 201 is too
  [20] = { {301}, {302}, {303}, {304}, {305}, {306}, {307}, {308}, {309}, {310} },
  [22] = { {401, req = {501}}, {501, req = {500}} }, -- a prerequisite listed after the spell needing it
}
local RANKS = { {200, 201, 202} }
local function Ids(list) local out = {} for i, e in ipairs(list) do out[i] = e.id end return table.concat(out, ",") end
local function Known(set) return function(id) return set[id] == true end end
local who = { faction = "Alliance", race = 1 }
local base = { [100] = true, [110] = true, [901] = true, [202] = true, [500] = true }

-- What has been trained so far, in the steps the tests below use.
local function With(...)
  local set = {}
  for id in pairs(base) do set[id] = true end
  for _, list in ipairs({...}) do for _, id in ipairs(list) do set[id] = true end end
  return set
end
local TO_14 = { 101, 102, 104, 106, 108, 109 }    -- everything waiting up to level 14 (110 was already known)
local TO_20 = { 101, 102, 104, 106, 108, 109, 112, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310 }
local trained = With(TO_14)

assert(Ids(T.Select(LEVELS, RANKS, 10, who, Known(base))) == "101,102", "new spell and next rank")
assert(Ids(T.Select(LEVELS, RANKS, 11, who, Known(base))) == "101,102", "spells from an earlier level not yet trained are still listed")
assert(Ids(T.Select(LEVELS, RANKS, 11, who, Known(With({ 101, 102 })))) == "", "nothing waiting once trained")
assert(Ids(T.Select(LEVELS, RANKS, 12, who, Known(base))) == "101,102,104,106,108", "faction, race and talent")
assert(Ids(T.Select(LEVELS, RANKS, 12, {}, Known(base))) == "101,102,108", "faction or race not known: limited spells left out")
assert(Ids(T.Select(LEVELS, RANKS, 13, who, Known(base))) == "101,102,104,106,108,109", "a prerequisite waiting too counts")
assert(Ids(T.Select(LEVELS, RANKS, 13, who, Known(With({ 101 })))) == "102,104,106,108,109", "a prerequisite already trained")
assert(Ids(T.Select(LEVELS, RANKS, 14, who, Known(trained))) == "", "known spells are never listed")
assert(Ids(T.Select(LEVELS, RANKS, 16, who, Known(With(TO_14, { 112 })))) == "", "unmet prerequisite")
assert(Ids(T.Select(LEVELS, RANKS, 18, who, Known(With(TO_14, { 112 })))) == "", "a later rank known means this one is")
do
  local set = With(TO_14, { 112, 200 }); set[202] = nil
  assert(Ids(T.Select(LEVELS, RANKS, 18, who, Known(set))) == "201", "the next rank after the known one")
end
assert(Ids(T.Select(LEVELS, RANKS, 22, who, Known(With(TO_20)))) == "401,501", "prerequisite order inside a level doesn't matter")
do
  local set = With(TO_20); set[500] = nil
  assert(Ids(T.Select(LEVELS, RANKS, 22, who, Known(set))) == "", "a chain falls when its first link can't be trained")
end
-- Ranks of one spell, each needing the one before.
local CHAIN = { [2] = { {700} }, [4] = { {701, req = {700}} }, [6] = { {702, req = {701}} } }
assert(Ids(T.Select(CHAIN, {}, 6, who, Known({}))) == "700,701,702", "every rank waiting is selected (the card shows the highest)")
assert(Ids(T.Select(CHAIN, {}, 6, who, Known({ [700] = true }))) == "701,702")
assert(Ids(T.Select(CHAIN, {}, 6, who, Known({ [702] = true }))) == "",
  "a known rank means the ones before it are known, even when the spellbook no longer lists them")
assert(Ids(T.Select(CHAIN, {}, 4, who, Known({ [702] = true }))) == "")
do -- each spell once, even when the data repeats it
  local twice = { [5] = { {7} }, [6] = { {7} } }
  assert(Ids(T.Select(twice, {}, 6, who, Known({}))) == "7")
end

---------------------------------------------------------------------------
-- In game: the card.
---------------------------------------------------------------------------
R.TrainingData = { MAGE = function() return LEVELS, RANKS end }
c.KNOWN = base
c.NAMES = { [101] = "Arcane Bolt", [102] = "Frost Lance", [104] = "Portal: Stormwind", [106] = "Holy Light",
  [108] = "Ice Barrier", [109] = "Arcane Barrage", [112] = "Blink", [201] = "Shred" }
c.RANKS = { [102] = "Rank 2", [109] = "Rank 1" }
for id = 301, 310 do c.NAMES[id] = "Spell " .. id; c.RANKS[id] = "Rank " .. (id - 300) end

local wbDismissed = 0
R.WelcomeBack.Dismiss = function() wbDismissed = wbDismissed + 1 end
R.Arrival.IsShowing = function() return c.ARRIVAL end
local function Card()
  for _, f in ipairs(fakes) do if rawget(f, "foot") and rawget(f, "rowFrames") then return f end end
end
-- Whether the card's own event frame is listening for an event.
local function Listening(event)
  for _, f in ipairs(fakes) do if f.events[event] then return true end end
  return false
end
local function Settle() RunLongTimers(2); FlushTimers(); FlushTimers() end
-- Ends an animation group as the game would: no longer playing, then OnFinished.
local function Finish(group) group.playing = false; group.scripts.OnFinished(group) end
local function LevelUp(level) c.LEVEL = level; Fire("PLAYER_LEVEL_UP", level, 10, 10, 0, 0, 1, 1, 1, 1) end
local function ShownRows()
  local n = 0
  for _, row in ipairs(Card().rowFrames) do if row.shown then n = n + 1 end end
  return n
end

Fire("PLAYER_ENTERING_WORLD", true, false)

-- Nothing to train: no card.
c.KNOWN = trained
c.LEVEL = 10; Fire("PLAYER_ENTERING_WORLD", false, true)
LevelUp(11); Settle()
assert(not Card(), "no card when nothing is waiting")

-- One spell: the heading, the spell, and where to learn it. No frame, no buttons, no clicks.
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(15)
assert(not Card(), "not at once: the level-up settles first")
Settle()
local card = Card()
assert(card and card.shown and card.anim.plays == 1, "card shown and settling in")
assert(card.title.text == "New Training Available")
assert(ShownRows() == 1 and card.rowFrames[1].text.text == "Blink", card.rowFrames[1].text.text)
assert(card.foot.text == "Visit a class trainer", card.foot.text)
assert(card.mouse == false, "takes no clicks")
assert(rawget(card, "close") == nil and rawget(card, "toggle") == nil and rawget(card, "SetBackdrop") == nil, "no close, no expand, no backdrop")
assert(card.rowFrames[1].point[1] == "TOP" and card.rowFrames[1].point[4] == 0, "one column, centred")
assert(card.height == 64 + 20, "sized to its one row")
assert(wbDismissed == 0, "the Welcome Back bookmark is elsewhere on screen and left alone")
local p = card.point
assert(p[1] == "TOP" and p[2] == c.UIParent and p[3] == "TOP" and p[4] == 0 and p[5] == -260, "upper centre by default, below the zone card")
assert(Listening("PLAYER_REGEN_DISABLED"), "listens for combat while up")
assert(card.drop.y == -8 and card.rise.y == 8, "settles upward as the zone card does")
assert(math.abs(card.fadeOut.delay - 4.6) < 1e-9, "a short stay for one spell")
-- it fades and cleans up
Finish(card.anim)
assert(not card.shown and not Listening("PLAYER_REGEN_DISABLED") and rawget(card, "rows") == nil, "gone after it fades")

-- Several levels at once: one card for all of them, each spell once, every one shown.
c.KNOWN = base
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); LevelUp(11); LevelUp(12); LevelUp(13)
LevelUp(13)   -- a repeated event
Settle()
assert(card.shown and card.anim.plays == 2, "one card for four levels")
assert(#card.rows == 6 and Ids(card.rows) == "101,102,104,106,108,109", Ids(card.rows))
assert(ShownRows() == 6, "all six listed without opening anything")
local second = card.rowFrames[2].text.text
assert(second:find("Frost Lance", 1, true) and second:find("Rank 2", 1, true) and second:find("level 10", 1, true), second)
assert(card.rowFrames[6].text.text:find("level 13", 1, true), "the level beside each when several were crossed")
assert(card.foot.text == "Visit a class trainer")
assert(math.abs(card.fadeOut.delay - (4 + 0.6 * 6)) < 1e-9, "stays longer for a longer list")
Finish(card.anim)
-- no further card for levels already covered
LevelUp(13); Settle()
assert(not card.shown, "a repeated level-up shows nothing")

-- Not been to a trainer for a while: a level with nothing new still lists what is waiting from before.
LevelUp(14); Settle()
assert(card.shown and Ids(card.rows) == "101,102,104,106,108,109", Ids(card.rows))
assert(card.rowFrames[1].text.text:find("level 10", 1, true), "each with the level it became available")
Finish(card.anim)

-- Several ranks of one spell waiting: only the highest is shown. Poisons' numerals count as ranks too.
do
  local saved = R.TrainingData
  R.TrainingData = { MAGE = function()
    return { [2] = { {700} }, [3] = { {800} }, [4] = { {701, req = {700}} }, [5] = { {801, req = {800}} },
      [6] = { {702, req = {701}} } }, {}
  end }
  c.KNOWN = {}
  for id, rank in pairs({ [700] = 1, [701] = 2, [702] = 3 }) do c.NAMES[id] = "Frostbolt"; c.RANKS[id] = "Rank " .. rank end
  c.NAMES[800], c.RANKS[800] = "Instant Poison", "Rank 1"
  c.NAMES[801], c.RANKS[801] = "Instant Poison II", "Rank 2"
  c.LEVEL = 5; Fire("PLAYER_ENTERING_WORLD", false, false)
  LevelUp(6); Settle()
  assert(Ids(card.rows) == "801,702" and ShownRows() == 2, Ids(card.rows))
  assert(card.rowFrames[2].text.text:find("Frostbolt", 1, true) and card.rowFrames[2].text.text:find("Rank 3", 1, true))
  Finish(card.anim)
  c.KNOWN = { [701] = true }
  c.LEVEL = 5; Fire("PLAYER_ENTERING_WORLD", false, false)
  LevelUp(6); Settle()
  assert(Ids(card.rows) == "801,702", "rank 1 isn't waiting once rank 2 is known")
  Finish(card.anim)
  R.TrainingData = saved
end

-- Long lists: two columns, the rest counted in the last line.
c.KNOWN = With(TO_14, { 112 })
c.LEVEL = 19; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(20); Settle()
assert(#card.rows == 10 and ShownRows() == 10)
assert(card.rowFrames[1].point[1] == "TOPLEFT" and card.rowFrames[6].point[4] == 6, "two columns of five")
assert(card.height == 64 + 5 * 20 and card.foot.text == "Visit a class trainer")
assert(not card.rowFrames[1].text.text:find("level", 1, true), "one level crossed: no level beside each")
Finish(card.anim)
local many = {}
for i = 1, 20 do many[i] = { 600 + i }; c.NAMES[600 + i] = "Spell " .. (600 + i) end
LEVELS[21] = many
c.KNOWN = With(TO_20)
LevelUp(21); Settle()
assert(#card.rows == 20 and ShownRows() == 12, "twelve shown")
assert(card.foot.text == "and 8 more  ·  Visit a class trainer", card.foot.text)
assert(math.abs(card.fadeOut.delay - (4 + 0.6 * 12)) < 1e-9, "the stay counts only the spells shown")
Finish(card.anim)
LEVELS[21] = nil

-- Login, reload and loading screens are never level-ups, and nothing is stored.
local stored = {}
for k in pairs(c.TwichUIDB) do stored[#stored + 1] = k end
c.LEVEL = 15
Fire("PLAYER_ENTERING_WORLD", true, false); Settle()
Fire("PLAYER_ENTERING_WORLD", false, true); Settle()
assert(not card.shown, "nothing at login or reload")
local after = 0
for _ in pairs(c.TwichUIDB) do after = after + 1 end
assert(after == #stored, "nothing saved")

-- Combat: it waits, then shows; combat starting takes it away.
c.KNOWN = trained
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
c.COMBAT = true
LevelUp(15); Settle(); Settle()
assert(not card.shown, "not in combat")
c.COMBAT = false
Fire("PLAYER_REGEN_ENABLED"); FlushTimers(); FlushTimers()
assert(card.shown and card.rows[1].id == 112, "shown once combat ends")
Fire("PLAYER_REGEN_DISABLED")
assert(not card.shown and not Listening("PLAYER_REGEN_DISABLED"), "makes way for combat")

-- A banner at the top: it waits a little, then shows anyway.
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
c.TOAST = true
LevelUp(15); Settle()
assert(not card.shown, "waits for the banner")
for _ = 1, 4 do RunLongTimers(2); FlushTimers() end
assert(not card.shown)
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown, "shown after a few looks")
Finish(card.anim)
c.TOAST = false

-- Names the game hasn't loaded are asked for; a name that never comes is left out.
c.KNOWN = base
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
c.UNCACHED = { [101] = true, [102] = true }
c.NAMES[101] = nil
LevelUp(10); Settle()
assert(c.REQUESTED[101] and c.REQUESTED[102], "asks for unloaded spell data")
assert(not card.shown, "waits for the names")
Fire("SPELL_DATA_LOAD_RESULT", 102, true); FlushTimers()
assert(not card.shown, "still waiting for one")
RunLongTimers(3); FlushTimers()
assert(card.shown and #card.rows == 1 and card.rows[1].id == 102, "the unnamed spell is left out")
Finish(card.anim)
c.UNCACHED = {}
c.NAMES[102] = nil
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Settle()
assert(not card.shown, "no names at all: no card")
c.NAMES[101], c.NAMES[102] = "Arcane Bolt", "Frost Lance"

-- Known spells are never listed.
c.KNOWN = { [100] = true, [110] = true, [901] = true, [202] = true, [101] = true, [102] = true }
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Settle()
assert(not card.shown, "both already known")
c.KNOWN = base

-- A level-up while the card is up: a new card lists everything waiting.
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Settle()
assert(card.shown and #card.rows == 2)
LevelUp(11); LevelUp(12); Settle()
assert(card.shown and Ids(card.rows) == "101,102,104,106,108", "the open card is replaced by one covering both")
Finish(card.anim)

-- Missing data: another class, or no data file at all, shows nothing and raises nothing.
c.CLASS = "DEATHKNIGHT"
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Settle()
assert(not card.shown, "a class without data")
c.CLASS = "MAGE"
local data = R.TrainingData
R.TrainingData = nil
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Settle()
assert(not card.shown, "no data")
R.TrainingData = data

-- The zone card is up: it waits for it, then shows anyway after a few looks.
c.KNOWN = trained
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
c.ARRIVAL = true
LevelUp(15); Settle()
assert(not card.shown, "waits for the zone card")
c.ARRIVAL = false
RunLongTimers(2); FlushTimers(); FlushTimers()
assert(card.shown, "shown once the zone card has gone")
Finish(card.anim)

-- Edit Mode: an outline to drag while it is open; the place is kept and used.
local enter, exit = c.EventRegistry.callbacks["EditMode.Enter"], c.EventRegistry.callbacks["EditMode.Exit"]
assert(enter and exit, "listens for Edit Mode")
local function Mover() for _, f in ipairs(fakes) do if f.scripts.OnDragStart then return f end end end
assert(not Mover(), "nothing made until Edit Mode opens")
c.EDITING = true; enter()
local mover = Mover()
assert(mover and mover.shown and mover.point[5] == -260, "outline at the card's place")
-- dragged so its top centre is 88 right of centre and 168 below the top of a 1024x768 screen
mover.GetLeft = function() return 400 end
mover.GetWidth = function() return 400 end
mover.GetTop = function() return 600 end
mover.scripts.OnDragStart(mover); mover.scripts.OnDragStop(mover)
local saved = c.TwichUIDB.ui.trainingPosition
assert(saved.x == 88 and saved.y == -168, "kept as an offset from the top centre")
assert(mover.point[1] == "TOP" and mover.point[4] == 88 and mover.point[5] == -168, "the outline is re-anchored by its top")
assert(card.point[4] == 88 and card.point[5] == -168, "the card moves with it")
mover.scripts.OnLeave()
exit()
assert(not mover.shown, "outline gone when Edit Mode closes")
c.EDITING = false
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(15); Settle()
assert(card.shown and card.point[4] == 88 and card.point[5] == -168, "the card appears where it was put")
Finish(card.anim)
-- right-click puts it back
c.EDITING = true; enter()
mover.scripts.OnMouseUp(mover, "LeftButton")
assert(c.TwichUIDB.ui.trainingPosition, "a left click changes nothing")
mover.scripts.OnMouseUp(mover, "RightButton")
assert(c.TwichUIDB.ui.trainingPosition == nil and mover.point[4] == 0 and mover.point[5] == -260, "right-click: back to the default")
-- switched off while Edit Mode is open: the outline goes; on again: it returns
M.trainingNotice = false; T.Refresh()
assert(not mover.shown)
M.trainingNotice = true; T.Refresh()
assert(mover.shown, "on again during Edit Mode")
exit(); c.EDITING = false
-- a saved place that can't be right is ignored
for _, bad in ipairs({ "x", { x = "1", y = 2 }, { x = 0 / 0, y = 0 }, { x = 1e9, y = 0 }, { y = -100 } }) do
  c.TwichUIDB.ui.trainingPosition = bad
  local x, y = T.Position()
  assert(x == 0 and y == -260, "bad saved place ignored")
end
c.TwichUIDB.ui.trainingPosition = nil

-- Reduced motion: it only fades.
M.arrivalReducedMotion = true
c.LEVEL = 14; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(15); Settle()
assert(card.shown and card.drop.y == 0 and card.rise.y == 0, "no movement")
M.arrivalReducedMotion = false
-- Leaving the world takes it down and drops anything waiting.
Fire("PLAYER_LEAVING_WORLD")
assert(not card.shown)
c.LEVEL = 9; Fire("PLAYER_ENTERING_WORLD", false, false)
LevelUp(10); Fire("PLAYER_LEAVING_WORLD"); Settle()
assert(not card.shown, "a loading screen drops a waiting look")

-- /tui training previews a level or the current level, and says why when there is nothing.
local printed = {}
c.print = function(s) table.insert(printed, tostring(s)) end
c.SlashCmdList.TWICHUI("training 15"); FlushTimers()
assert(card.shown and #card.rows == 1 and card.rows[1].id == 112, "preview a level")
c.LEVEL = 15
c.SlashCmdList.TWICHUI("training"); FlushTimers()
assert(card.shown and card.rows[1].id == 112, "preview the current level")
c.KNOWN = base
c.SlashCmdList.TWICHUI("training 13"); FlushTimers()
assert(#card.rows == 6, "everything waiting up to that level")
c.KNOWN = trained
c.SlashCmdList.TWICHUI("training 14")
assert(printed[#printed]:find("Nothing to train up to level 14", 1, true), printed[#printed])
c.SlashCmdList.TWICHUI("training soon")
assert(printed[#printed]:find("/tui training 20", 1, true))
Finish(card.anim)

-- Welcome Back waits while the card is up.
assert(T.IsShowing() == false)

-- Off: nothing listened for, nothing shown; on again starts from the current level.
M.trainingNotice = false; T.Refresh()
c.LEVEL = 9; LevelUp(10); Settle()
assert(not card.shown, "off means off")
c.LEVEL = 14
M.trainingNotice = true; T.Refresh()
LevelUp(15); Settle()
assert(card.shown and card.rows[1].id == 112, "on again")
-- Turning it off while the card is up takes it down.
M.trainingNotice = false; T.Refresh()
assert(not card.shown)

-- An existing explicit opt-out survives; a new install gets it on.
local d = MakeClient("Pat", {"!!!TwichUI"})
d.TwichUIDB = { modules = { trainingNotice = false } }
d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(d.TwichUIDB.modules.trainingNotice == false, "saved false is kept")

print("TRAINING TEST PASSED")
