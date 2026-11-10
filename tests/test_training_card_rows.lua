dofile(TESTS .. "harness.lua")
-- The three functions between the bundled data and the card: ForLevel (the game-facing
-- wrapper), SpellKey (rank-name collapsing) and Rows (one row per spell, highest rank only,
-- unnamed spells dropped). ForLevel is public and tested directly; SpellKey and Rows are
-- local, so their behaviour is checked through the card's rows, the only thing that exposes
-- them (the card's rows are Rows(Select(...)) and SpellKey decides which ranks collapse).
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
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h end end
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
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }
c.GameTooltip = Fake()

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
c.NOW = 1000
c.GetTime = function() return c.NOW end
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

for _, f in ipairs({"chronicle/Style.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/WelcomeBack.lua",
    "modules/TrainingData.lua", "modules/Training.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local T = R.Training
local REAL = R.TrainingData

local function Ids(list) local out = {} for i, e in ipairs(list) do out[i] = e.id end return table.concat(out, ",") end
local function ShownRows()
  local n = 0
  for _, f in ipairs(fakes) do
    if rawget(f, "foot") and rawget(f, "rowFrames") then
      for _, row in ipairs(f.rowFrames) do if row.shown then n = n + 1 end end
    end
  end
  return n
end
local function Card()
  for _, f in ipairs(fakes) do if rawget(f, "foot") and rawget(f, "rowFrames") then return f end end
end
local function Settle() RunLongTimers(2); FlushTimers(); FlushTimers() end
local function Finish(group) group.playing = false; group.scripts.OnFinished(group) end
local function LevelUp(level) c.LEVEL = level; Fire("PLAYER_LEVEL_UP", level, 10, 10, 0, 0, 1, 1, 1, 1) end

Fire("PLAYER_ENTERING_WORLD", true, false)

---------------------------------------------------------------------------
-- ForLevel: the game-facing wrapper. For a MAGE it must agree with T.Select over the
-- real bundled MAGE data (the existing test checks Select directly the same way).
---------------------------------------------------------------------------
do
  local levels, ranks = REAL.MAGE()
  local who = { faction = "Alliance", race = 1 }
  c.KNOWN = { [1459] = true }   -- Arcane Intellect trained at 1; ForLevel's Known reads this
  local expected = T.Select(levels, ranks, 4, who, function(id) return c.KNOWN[id] == true end)
  local got = T.ForLevel(4)
  assert(Ids(got) == Ids(expected), "ForLevel(4) agrees with Select over the real MAGE data")
  -- The contract's own example: a Mage reaching 4 who trained Arcane Intellect waits on
  -- Conjure Water and Frostbolt.
  assert(Ids(got) == "5504,116", "Conjure Water and Frostbolt waiting at 4")
end

-- ForLevel: a class with no builder in R.TrainingData returns {}.
do
  local saved = R.TrainingData
  R.TrainingData = {}   -- no MAGE builder
  local got = T.ForLevel(4)
  assert(type(got) == "table" and #got == 0, "no builder: {}")
  R.TrainingData = saved
end

-- ForLevel: a non-numeric level returns {}.
do
  assert(type(T.ForLevel("4")) == "table" and #T.ForLevel("4") == 0, "non-numeric level: {}")
  assert(type(T.ForLevel(nil)) == "table" and #T.ForLevel(nil) == 0, "nil level: {}")
end

-- ForLevel: a level below 1 returns {} (the data's levels run 1-60).
do
  assert(type(T.ForLevel(0)) == "table" and #T.ForLevel(0) == 0, "level 0: {}")
  assert(type(T.ForLevel(-3)) == "table" and #T.ForLevel(-3) == 0, "negative level: {}")
end

---------------------------------------------------------------------------
-- Rows and SpellKey, through the card's rows (the only thing that exposes them).
-- Data: two ranks of one spell (700 at 2, 701 at 4) plus a poison pair (800 "Instant
-- Poison" at 3, 801 "Instant Poison II" at 5) and an unnamed spell (900 at 6).
---------------------------------------------------------------------------
do
  local saved = R.TrainingData
  R.TrainingData = { MAGE = function()
    return { [2] = { {700} }, [3] = { {800} }, [4] = { {701, req = {700}} }, [5] = { {801, req = {800}} },
      [6] = { {900} } }, {}
  end }
  c.KNOWN = {}
  c.NAMES[700], c.RANKS[700] = "Frostbolt", "Rank 1"
  c.NAMES[701], c.RANKS[701] = "Frostbolt", "Rank 2"
  c.NAMES[800], c.RANKS[800] = "Instant Poison", "Rank 1"
  c.NAMES[801], c.RANKS[801] = "Instant Poison II", "Rank 2"
  c.NAMES[900] = nil   -- the game gives no name for 900
  c.LEVEL = 5; Fire("PLAYER_ENTERING_WORLD", false, false)
  LevelUp(6); Settle()
  local card = Card()
  assert(card and card.shown, "card shown")
  -- Rows: the unnamed 900 is dropped; the two Frostbolt ranks collapse to the later (higher)
  -- one, 701; the poison pair collapses to 801. Listed by level: 701 (level 4) before 801 (5).
  assert(Ids(card.rows) == "701,801", "one row per spell, highest rank, unnamed dropped, by level: " .. Ids(card.rows))
  assert(ShownRows() == 2, "two rows shown")
  -- SpellKey: "Instant Poison II" collapses to "Instant Poison", so 801's row is the poison's.
  assert(card.rowFrames[2].text.text:find("Instant Poison", 1, true), "the poison's numeral collapses to its name")
  Finish(card.anim)
  R.TrainingData = saved
end

print("TEST_TRAINING_CARD_ROWS PASSED")
