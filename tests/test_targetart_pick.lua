dofile(TESTS .. "harness.lua")
-- The target dragon artwork's decision rules (targetart/Config.lua): TA.Pick is pure -- the boss flag is
-- checked before classification, a Boss row of "class" falls through to the unit's classification row,
-- classifications without a row ("normal", "trivial", "minus", unreadable) get no artwork, and a row of
-- "none" gets no artwork. TA.MapKey maps a kind to its saved setting key.
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "targetart/Config.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local TA = c.TwichUI.TargetArt
assert(TA and TA.Pick and TA.MapKey, "the config loaded")

-- TA.MapKey: the saved key of a kind's mapping (Config.lua:116).
assert(TA.MapKey("boss") == "mapBoss", "MapKey(boss)")
assert(TA.MapKey("worldboss") == "mapWorldboss", "MapKey(worldboss)")
assert(TA.MapKey("rareelite") == "mapRareelite", "MapKey(rareelite)")
assert(TA.MapKey("elite") == "mapElite", "MapKey(elite)")
assert(TA.MapKey("rare") == "mapRare", "MapKey(rare)")

-- A settings table standing in for TA.Get: every row set to a known value.
local function FakeGet(over)
  local s = { mapBoss = "boss", mapWorldboss = "boss", mapRareelite = "boss", mapElite = "elite", mapRare = "rare" }
  for k, v in pairs(over or {}) do s[k] = v end
  return function(key) return s[key] end
end

-- The boss flag is checked before classification: with isBoss, mapBoss decides, even when the
-- classification has its own row (Config.lua:206-215).
assert(TA.Pick("rare", true, FakeGet()) == "boss", "the boss flag wins over a rare classification")
assert(TA.Pick("elite", true, FakeGet()) == "boss", "the boss flag wins over an elite classification")
assert(TA.Pick(nil, true, FakeGet()) == "boss", "an unreadable classification still gets the boss row")

-- A Boss row of "class" falls through to the unit's classification row (Config.lua:215, 57).
assert(TA.Pick("rare", true, FakeGet({ mapBoss = "class" })) == "rare", "class falls through to mapRare")
assert(TA.Pick("elite", true, FakeGet({ mapBoss = "class" })) == "elite", "class falls through to mapElite")
assert(TA.Pick("rareelite", true, FakeGet({ mapBoss = "class" })) == "boss", "class falls through to mapRareelite")
assert(TA.Pick("worldboss", true, FakeGet({ mapBoss = "class" })) == "boss", "class falls through to mapWorldboss")
assert(TA.Pick("normal", true, FakeGet({ mapBoss = "class" })) == nil, "normal has no row, even for a boss")
assert(TA.Pick(nil, true, FakeGet({ mapBoss = "class" })) == nil, "an unreadable classification has no row")

-- Without the boss flag (false or nil) only the classification's own row decides.
assert(TA.Pick("worldboss", false, FakeGet()) == "boss", "the worldboss row")
assert(TA.Pick("rareelite", false, FakeGet()) == "boss", "the rareelite row")
assert(TA.Pick("elite", false, FakeGet()) == "elite", "the elite row")
assert(TA.Pick("rare", false, FakeGet()) == "rare", "the rare row")
assert(TA.Pick("rare", nil, FakeGet()) == "rare", "a nil boss flag is not a boss")

-- Classifications without a row never get artwork (Config.lua:55).
for _, k in ipairs({ "normal", "trivial", "minus" }) do
  assert(TA.Pick(k, false, FakeGet()) == nil, k .. " has no row")
  assert(TA.Pick(k, true, FakeGet()) == "boss", k .. " with the boss flag still gets the boss row")
end
assert(TA.Pick(nil, false, FakeGet()) == nil, "an unreadable classification gets no artwork")
assert(TA.Pick(5, false, FakeGet()) == nil, "a non-string classification gets no artwork")
assert(TA.Pick(true, false, FakeGet()) == nil, "a boolean classification gets no artwork")
assert(TA.Pick({ "rare" }, false, FakeGet()) == nil, "a table classification gets no artwork")

-- A row set to "none" returns nil (Config.lua:6, 96).
assert(TA.Pick("rare", false, FakeGet({ mapRare = "none" })) == nil, "a rare row of none")
assert(TA.Pick("elite", false, FakeGet({ mapElite = "none" })) == nil, "an elite row of none")
assert(TA.Pick("rare", true, FakeGet({ mapBoss = "none" })) == nil, "a boss row of none")
assert(TA.Pick("rare", true, FakeGet({ mapBoss = "class", mapRare = "none" })) == nil, "class falls through to a none row")

-- Through TA.Get (the default get): an invalid stored value reads as the kind's default, so Pick still
-- returns the default ART id (Config.lua:5, 176-182; defaults at 64-65).
c.TwichUIDB = { ui = { targetArt = { mapRare = "bogus" } } }
assert(TA.Get("mapRare") == "rare", "an invalid stored row reads as the default")
assert(TA.Pick("rare", false) == "rare", "Pick through TA.Get returns the default ART id")
c.TwichUIDB.ui.targetArt.mapRare = "eliteWide"
assert(TA.Get("mapRare") == "eliteWide", "a valid stored row is read as saved")
assert(TA.Pick("rare", false) == "eliteWide", "Pick through TA.Get returns the saved ART id")
c.TwichUIDB.ui.targetArt = {}
assert(TA.Get("mapBoss") == "boss" and TA.Get("mapWorldboss") == "boss" and TA.Get("mapRareelite") == "boss"
  and TA.Get("mapElite") == "elite" and TA.Get("mapRare") == "rare", "the defaults")
assert(TA.Pick("rare", false) == "rare", "no saved data: the rare default")
assert(TA.Pick("elite", false) == "elite", "no saved data: the elite default")
assert(TA.Pick(nil, true) == "boss", "no saved data: the boss default")
print("TEST_TARGETART_PICK PASSED")
