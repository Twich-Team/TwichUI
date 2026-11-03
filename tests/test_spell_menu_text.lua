-- SM.RankText and SM.TrainingInfo (modules/SpellMenu.lua): the rank text a not-yet-learned
-- row shows (the game's own subtext, or "Rank <rank>", or nothing), and the training-data
-- lookup that says at what level a wanted spell is trained and what it requires.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local R = c.TwichUI
local SM = R.SpellMenu

-- RankText: "the game's rank text ("Rank 3") when it gives one, otherwise "Rank <rank>"
-- (nil without one)" (modules/SpellMenu.lua:116).
do
  c.C_Spell = { GetSpellSubtext = function(id) return "Rank 3" end }
  assert(SM.RankText(1, 3) == "Rank 3", "the game's subtext is used verbatim")
  assert(SM.RankText(1, 9) == "Rank 3", "a non-empty subtext wins over the given rank")

  c.C_Spell = { GetSpellSubtext = function(id) return nil end }
  assert(SM.RankText(1, 5) == "Rank 5", "no subtext: the rank is formatted")
  assert(SM.RankText(1) == nil, "no subtext and no rank: nothing to show")

  c.C_Spell = { GetSpellSubtext = function(id) return "" end }
  assert(SM.RankText(1, 2) == "Rank 2", "an empty subtext is no subtext")
  assert(SM.RankText(1) == nil, "an empty subtext and no rank: nothing to show")

  c.C_Spell = nil
  assert(SM.RankText(1, 7) == "Rank 7", "no C_Spell at all: the rank is still formatted")
  assert(SM.RankText(1) == nil, "no C_Spell and no rank: nothing to show")
end

-- TrainingInfo: "{ [spellID] = { level = trained at, req = { spellIDs } or nil } } for the
-- IDs in `wanted`", built from R.TrainingData[class](); "the class's whole table is built
-- for this and let go afterwards" (modules/SpellMenu.lua:81-82).
do
  local builds = 0
  R.TrainingData = {
    Mage = function()
      builds = builds + 1
      return {
        [10] = { { 111, req = { 222 } }, { 112 } },
        [20] = { { 333, req = { 444, 555 } } },
      }
    end,
    Warrior = "not a builder",
    Broken = function() error("boom") end,
    Empty = function() return 42 end,
  }
  local wanted = { [111] = true, [112] = true, [333] = true }

  local info = SM.TrainingInfo("Mage", wanted)
  assert(info[111] and info[111].level == 10 and info[111].req and info[111].req[1] == 222 and info[111].req[2] == nil,
    "a wanted ID gets its level and req from the class table")
  assert(info[112] and info[112].level == 10 and info[112].req == nil,
    "a wanted ID with no requirement has req nil")
  assert(info[333] and info[333].level == 20 and info[333].req and info[333].req[1] == 444 and info[333].req[2] == 555,
    "a wanted ID from another level row is found too")
  local n = 0
  for id in pairs(info) do
    n = n + 1
    assert(wanted[id] == true, "only a wanted ID is returned: " .. tostring(id))
  end
  assert(n == 3, "exactly the wanted IDs, no more")
  assert(builds == 1, "the class's table is built once per call")
  SM.TrainingInfo("Mage", wanted)
  assert(builds == 2, "the table is let go afterwards: a later call builds it again")

  assert(next(SM.TrainingInfo("Doom", wanted)) == nil, "an unknown class gives an empty table")
  assert(next(SM.TrainingInfo("Warrior", wanted)) == nil, "a non-function builder gives an empty table")
  assert(next(SM.TrainingInfo("Broken", wanted)) == nil, "a builder that errors gives an empty table")
  assert(next(SM.TrainingInfo("Empty", wanted)) == nil, "a builder that returns a non-table gives an empty table")

  R.TrainingData = nil
  assert(next(SM.TrainingInfo("Mage", wanted)) == nil, "no TrainingData at all gives an empty table")
end

print("TEST_SPELL_MENU_TEXT PASSED")
