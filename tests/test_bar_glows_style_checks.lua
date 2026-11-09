-- Style checks for the bar glows (glows/Config.lua): BG.WhenFits, BG.ValidStyleField, BG.BarLabel.
-- Contract: docs/bar-glows.md:54-56 (strength 10-100%, size 70-170%, speed 25-300%, glow time until done or
-- 1-30 s, repeat off or 5-60 s, Alert in town for reagents and stock) and the comment at glows/Config.lua:132
-- ("Alert in town only for what you buy in a town").
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local chunk = assert(loadfile(ROOT .. "glows/Config.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local BG = c.TwichUI.BarGlows

-- The kinds a glow can be (glows/Config.lua TYPE_DEFAULTS).
local KINDS = { "missingBuff", "weaponBuff", "missingSeal", "missingTracking", "lowReagent", "lowStock", "readyCooldown", "proc", "oldRank" }

---------------------------------------------------------------------------
-- 1. WhenFits: every "when" fits every kind, except townAlert
---------------------------------------------------------------------------
do
  -- townAlert fits only the two kinds bought in a town (Config.lua:132, docs/bar-glows.md:55)
  Check(BG.WhenFits("lowReagent", "townAlert") == true, "townAlert fits lowReagent")
  Check(BG.WhenFits("lowStock", "townAlert") == true, "townAlert fits lowStock")
  for _, kind in ipairs({ "missingBuff", "weaponBuff", "missingSeal", "missingTracking", "readyCooldown", "proc", "oldRank" }) do
    Check(BG.WhenFits(kind, "townAlert") == false, "townAlert does not fit " .. kind)
  end
  -- the other whens (always, in combat, out of combat, enemy targeted) fit every kind (docs/bar-glows.md:55)
  for _, kind in ipairs(KINDS) do
    Check(BG.WhenFits(kind, "always") == true, "always fits " .. kind)
    Check(BG.WhenFits(kind, "inCombat") == true, "inCombat fits " .. kind)
    Check(BG.WhenFits(kind, "outOfCombat") == true, "outOfCombat fits " .. kind)
    Check(BG.WhenFits(kind, "enemyTargeted") == true, "enemyTargeted fits " .. kind)
  end
  -- an unknown "when" is rejected for every kind
  for _, kind in ipairs(KINDS) do
    Check(BG.WhenFits(kind, "sometimes") == false, "an unknown when is rejected for " .. kind)
  end
end

---------------------------------------------------------------------------
-- 2. ValidStyleField: each field's own check (docs/bar-glows.md:54-56)
---------------------------------------------------------------------------
do
  -- strength (opacity) 10-100%
  Check(BG.ValidStyleField("proc", "opacity", 9) == false, "opacity 9 is below the 10 minimum")
  Check(BG.ValidStyleField("proc", "opacity", 10) == true, "opacity 10 is the minimum")
  Check(BG.ValidStyleField("proc", "opacity", 100) == true, "opacity 100 is the maximum")
  Check(BG.ValidStyleField("proc", "opacity", 101) == false, "opacity 101 is above the 100 maximum")
  -- size 70-170%
  Check(BG.ValidStyleField("proc", "size", 69) == false, "size 69 is below the 70 minimum")
  Check(BG.ValidStyleField("proc", "size", 70) == true, "size 70 is the minimum")
  Check(BG.ValidStyleField("proc", "size", 170) == true, "size 170 is the maximum")
  Check(BG.ValidStyleField("proc", "size", 171) == false, "size 171 is above the 170 maximum")
  -- speed 25-300%
  Check(BG.ValidStyleField("proc", "speed", 24) == false, "speed 24 is below the 25 minimum")
  Check(BG.ValidStyleField("proc", "speed", 25) == true, "speed 25 is the minimum")
  Check(BG.ValidStyleField("proc", "speed", 300) == true, "speed 300 is the maximum")
  Check(BG.ValidStyleField("proc", "speed", 301) == false, "speed 301 is above the 300 maximum")
  -- glow time: until done (0) or 1-30 s (docs/bar-glows.md:56; Config.lua GLOW_TIMES = 0,1,2,3,5,10,15,30)
  Check(BG.ValidStyleField("proc", "glowTime", 0) == true, "glowTime 0 means until done")
  Check(BG.ValidStyleField("proc", "glowTime", 1) == true, "glowTime 1 s is the shortest")
  Check(BG.ValidStyleField("proc", "glowTime", 30) == true, "glowTime 30 s is the longest")
  Check(BG.ValidStyleField("proc", "glowTime", 31) == false, "glowTime 31 s is past the 30 s set")
  -- repeat: off (0) or 5-60 s (docs/bar-glows.md:56; Config.lua REPEATS = 0,5,10,15,30,60)
  Check(BG.ValidStyleField("proc", "repeat", 0) == true, "repeat 0 means off")
  Check(BG.ValidStyleField("proc", "repeat", 5) == true, "repeat 5 s is the shortest")
  Check(BG.ValidStyleField("proc", "repeat", 60) == true, "repeat 60 s is the longest")
  Check(BG.ValidStyleField("proc", "repeat", 61) == false, "repeat 61 s is past the 60 s set")
  -- message: a boolean
  Check(BG.ValidStyleField("proc", "message", true) == true, "message true is accepted")
  Check(BG.ValidStyleField("proc", "message", false) == true, "message false is accepted")
  Check(BG.ValidStyleField("proc", "message", "yes") == false, "message is a boolean, not a string")
  -- sound: a name (TwichUI's or LibSharedMedia's), no control characters or a '|' separator
  Check(BG.ValidStyleField("proc", "sound", "none") == true, "sound none is the shipped default (Config.lua NO_SOUND)")
  Check(BG.ValidStyleField("proc", "sound", "UI_Paper") == true, "a LibSharedMedia sound name is accepted")
  Check(BG.ValidStyleField("proc", "sound", "") == false, "an empty sound is rejected")
  Check(BG.ValidStyleField("proc", "sound", "a|b") == false, "a '|' in the sound is rejected")
  Check(BG.ValidStyleField("proc", "sound", "a\nb") == false, "a control character in the sound is rejected")
  -- an unknown field is rejected
  Check(BG.ValidStyleField("proc", "colour", "ff000000") == false, "an unknown field is rejected")
end

---------------------------------------------------------------------------
-- 3. ValidStyleField with field "when": the value must also fit the kind
---------------------------------------------------------------------------
do
  -- townAlert: accepted for the town-bought kinds, rejected for the rest (Config.lua:132)
  Check(BG.ValidStyleField("lowReagent", "when", "townAlert") == true, "when townAlert is accepted for lowReagent")
  Check(BG.ValidStyleField("lowStock", "when", "townAlert") == true, "when townAlert is accepted for lowStock")
  Check(BG.ValidStyleField("missingBuff", "when", "townAlert") == false, "when townAlert is rejected for missingBuff")
  Check(BG.ValidStyleField("readyCooldown", "when", "townAlert") == false, "when townAlert is rejected for readyCooldown")
  -- inCombat fits every kind (docs/bar-glows.md:55)
  for _, kind in ipairs(KINDS) do
    Check(BG.ValidStyleField(kind, "when", "inCombat") == true, "when inCombat is accepted for " .. kind)
  end
  -- an unknown when is rejected for every kind
  for _, kind in ipairs(KINDS) do
    Check(BG.ValidStyleField(kind, "when", "sometimes") == false, "when sometimes is rejected for " .. kind)
  end
end

---------------------------------------------------------------------------
-- 4. BarLabel: the settings rows' labels (tests/fixtures/settings_contract.lua)
---------------------------------------------------------------------------
do
  Check(BG.BarLabel("stance") == "Stance bar", "stance is labelled Stance bar (settings_contract.lua TWICHUI_barGlowsStanceOn)")
  Check(BG.BarLabel("bar1") == "Action Bar 1", "bar1 is labelled Action Bar 1")
  Check(BG.BarLabel("bar10") == "Action Bar 10", "bar10 is labelled Action Bar 10 (settings_contract.lua TWICHUI_barGlowsBar10On)")
end

if failures > 0 then
  print(failures .. " FAILED")
  os.exit(1)
end
print("TEST_BAR_GLOWS_STYLE_CHECKS PASSED")
