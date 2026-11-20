dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Quick access (TwichUI_Settings/QuickAccess.lua): what the left-hand list learns and offers.
--   * nothing is offered, and nothing is written, until a feature has been used again (first use, reading);
--   * a visit counts once per cooldown; a feature needs a second counted visit; three shortcuts at most;
--   * pinned features, Home, the configuration pages, tabs and unknown pages are never offered;
--   * frequency and recency together, old use fading, a stronger challenger needed to displace a shortcut;
--   * each character learns its own habits, in a record outside profiles, shares and backups;
--   * saved data: bounded, damaged parts repaired, a newer record left alone, nothing written while held;
--   * the window side (which navigation counts) is in test_settings_window.lua.

local c, S = SettingsClient()
local R, K = c.TwichUI, S.K
local QA = R.SettingsQuick
assert(QA and QA.Eligible and QA.Visit and QA.Pick and QA.Suggest, "Quick access is loaded with the settings")

local DAY, MIN = 86400, 60
local now = 1800000000
QA.Now = function() return now end
local function Reset() c.TwichUIDB.quickAccess = nil; QA.shown = {} end

-- what the window lets through: a feature page that is not already in the list
local pinned = { overview = true, notifications = true, reminders = true, healerWatch = true, qol = true,
  chronicle = true, navigation = true, workshop = true, magicInventory = true, auction = true }
local function Eligible(key) return QA.Eligible(K.pages[key], pinned) end
local function Visits(key, n, gap)
  for _ = 1, n do QA.Visit(key); now = now + (gap or 11 * MIN) end
end
local function List(t) return table.concat(t, ",") end

---------------------------------------------------------------------------
-- Which pages can be offered
---------------------------------------------------------------------------
for _, key in ipairs({ "pins", "food", "hazard", "gear", "mage", "cozyBag", "restedxp", "classBars" }) do
  assert(K.pages[key], key .. " is a page in this build")
  assert(Eligible(key), key .. " is a feature that can be offered")
end
for _, key in ipairs({ "overview", "profiles", "sharing", "troubleshooting" }) do
  assert(K.pages[key] and not Eligible(key), key .. " is Home or a configuration page: never offered")
end
for key in pairs(pinned) do assert(not Eligible(key), key .. " is in the list already: never offered") end
assert(K.pages.chronicleLook and K.pages.chronicleLook.parent and not Eligible("chronicleLook"), "a tab is not a feature of its own")
assert(not QA.Eligible(nil, pinned) and not QA.Eligible(K.pages.nope, pinned), "an unknown page is not offered")
assert(not QA.Eligible({ key = "x", group = "everyday", failed = true }, pinned), "a page that failed to describe is not offered")
-- every top-level page is either offered or accounted for
local offered = 0
for _, page in ipairs(K.SidebarOrder()) do if QA.Eligible(page, pinned) then offered = offered + 1 end end
assert(offered >= 8, "most features can be offered: " .. offered)

---------------------------------------------------------------------------
-- First use: no history, nothing written by looking
---------------------------------------------------------------------------
Reset()
assert(#QA.Suggest(Eligible) == 0, "no history: nothing offered")
assert(c.TwichUIDB.quickAccess == nil, "looking writes nothing")
assert(QA.Records() == nil)

-- one visit is not yet a habit; the record exists and holds plain numbers
assert(QA.Visit("pins") == true, "the first visit counts")
assert(#QA.Suggest(Eligible) == 0, "one visit offers nothing")
local rec = c.TwichUIDB.quickAccess
assert(rec.v == 1 and type(rec.chars) == "table", "the record is versioned")
local ck = QA.CharKey()
assert(ck == "Rich - Forever" and rec.chars[ck].f.pins.s == 1 and rec.chars[ck].f.pins.t == now)

-- the cooldown: flicking through counts once
assert(QA.Visit("pins") == false, "the same feature again at once does not count")
now = now + 9 * MIN
assert(QA.Visit("pins") == false, "nor within the cooldown")
assert(rec.chars[ck].f.pins.s == 1, "the score did not move")
now = now + 2 * MIN
assert(QA.Visit("pins") == true, "after the cooldown it counts")
assert(List(QA.Suggest(Eligible)) == "pins", "a second counted visit offers it")
assert(QA.Visit("food") == true and QA.Visit("hazard") == true, "other features count at once (the cooldown is per feature)")

---------------------------------------------------------------------------
-- Three at most; the strongest
---------------------------------------------------------------------------
Reset(); now = 1800000000
Visits("pins", 6); Visits("food", 5); Visits("hazard", 4); Visits("gear", 3); Visits("mage", 2); Visits("cozyBag", 1)
local list = QA.Suggest(Eligible)
assert(#list == 3 and QA.MAX_SHOWN == 3, "three at most: " .. List(list))
assert(List(list) == "pins,food,hazard", "the most used first: " .. List(list))

-- fewer qualify: fewer shown
Reset(); now = 1800000000
Visits("pins", 3); Visits("food", 1)
assert(List(QA.Suggest(Eligible)) == "pins", "only the ones that qualify")

---------------------------------------------------------------------------
-- Pinned and utility features are never offered, however used
---------------------------------------------------------------------------
Reset(); now = 1800000000
Visits("notifications", 8); Visits("overview", 8); Visits("profiles", 8); Visits("chronicleLook", 8); Visits("pins", 2)
assert(List(QA.Suggest(Eligible)) == "pins", "pinned, Home, configuration and tab pages are left out: " .. List(QA.Suggest(Eligible)))

---------------------------------------------------------------------------
-- Frequency, recency and fading
---------------------------------------------------------------------------
-- a habit of weeks beats a single recent visit
Reset(); now = 1800000000
for _ = 1, 10 do Visits("pins", 1); now = now + DAY end     -- ten days of use
Visits("food", 2)                                           -- two visits today
assert(List(QA.Suggest(Eligible)) == "pins,food", "consistent use stays ahead of a new interest: " .. List(QA.Suggest(Eligible)))

-- but once the habit has been dropped for long enough, the newer interest takes over
now = now + 60 * DAY
Visits("food", 3)
local later = QA.Suggest(Eligible)
assert(later[1] == "food", "recent use outranks use from weeks ago: " .. List(later))
assert(QA.Decayed(10, now - 14 * DAY, now) == 5, "a score halves every fourteen days")
assert(QA.Decayed(10, now + DAY, now) == 10, "a clock that moved back does not make a score grow")

-- old use fades out of the list
Reset(); now = 1800000000
Visits("pins", 2)
assert(List(QA.Suggest(Eligible)) == "pins")
now = now + 5 * DAY
assert(List(QA.Suggest(Eligible)) == "pins", "a few days later it is still offered")
now = now + 30 * DAY
assert(#QA.Suggest(Eligible) == 0, "after a month of not using it, it is no longer offered")

-- and its record is dropped by the next write
now = now + 200 * DAY
QA.Visit("food")
local f = c.TwichUIDB.quickAccess.chars[QA.CharKey()].f
assert(f.pins == nil and f.food, "a faded record is discarded")

---------------------------------------------------------------------------
-- Removed or unavailable features
---------------------------------------------------------------------------
Reset(); now = 1800000000
Visits("pins", 3); Visits("ghostFeature", 5); Visits("food", 3)
assert(List(QA.Suggest(Eligible)) == "pins,food" or List(QA.Suggest(Eligible)) == "food,pins", "a page this build doesn't have is not offered")
-- one that stops existing (a switch off, a page that no longer applies) leaves the list
local present = { pins = true, food = true }
local function Only(key) return present[key] and Eligible(key) end
assert(#QA.Suggest(Only) == 2)
present.pins = nil
local after = QA.Suggest(Only)
assert(List(after) == "food", "a feature that is gone disappears from the list: " .. List(after))
present.pins = true
assert(#QA.Suggest(Only) == 2, "and returns with its history when it comes back")
-- a shortcut the player stops using does not hold its place
Reset(); now = 1800000000
Visits("pins", 3); QA.Suggest(Eligible)
now = now + 45 * DAY
Visits("food", 3); Visits("hazard", 3)
local moved = QA.Suggest(Eligible)
assert(List(moved) == "food,hazard" or List(moved) == "hazard,food", "an old shortcut gives way: " .. List(moved))

---------------------------------------------------------------------------
-- Stable ordering
---------------------------------------------------------------------------
-- the same scores always give the same order
Reset(); now = 1800000000
for _, key in ipairs({ "mage", "pins", "gear" }) do QA.Visit(key) end
now = now + 11 * MIN
for _, key in ipairs({ "mage", "pins", "gear" }) do QA.Visit(key) end
local a = List(QA.Suggest(Eligible))
QA.shown = {}
assert(List(QA.Suggest(Eligible)) == a and a == "gear,mage,pins", "equal scores: by key, the same every time: " .. a)

-- a shortcut is not displaced by a slightly stronger challenger, and the ones that stay keep their order
Reset(); now = 1800000000
Visits("pins", 6); Visits("food", 5); Visits("hazard", 4)
assert(List(QA.Suggest(Eligible)) == "pins,food,hazard")
Visits("gear", 5)            -- five against four: not 25% ahead, so it waits
assert(List(QA.Suggest(Eligible)) == "pins,food,hazard", "a near equal does not displace: " .. List(QA.Suggest(Eligible)))
Visits("gear", 6)            -- clearly stronger now
local swapped = QA.Suggest(Eligible)
assert(#swapped == 3 and swapped[1] == "pins" and swapped[2] == "food" and swapped[3] == "gear", "a clear leader takes the last place only: " .. List(swapped))
-- using a shortcut does not move it
Visits("food", 3)
assert(List(QA.Suggest(Eligible)) == "pins,food,gear", "using a shortcut does not reorder the list")

---------------------------------------------------------------------------
-- Each character learns for itself
---------------------------------------------------------------------------
Reset(); now = 1800000000
Visits("pins", 3)
local name = "Rich"
c.UnitName = function() return name end
name = "Healer"
assert(#QA.Suggest(Eligible) == 0, "another character starts with nothing")
QA.shown = {}
Visits("food", 3)
assert(List(QA.Suggest(Eligible)) == "food", "and learns its own")
name = "Rich"; QA.shown = {}
assert(List(QA.Suggest(Eligible)) == "pins", "the first character is unchanged")
local chars = c.TwichUIDB.quickAccess.chars
assert(chars["Rich - Forever"].f.pins and not chars["Rich - Forever"].f.food and chars["Healer - Forever"].f.food, "records are kept apart")
-- a profile has nothing to do with it
assert(c.TwichUIDB.ui.quickAccess == nil and c.TwichUIDB.profiles.quickAccess == nil, "the habit is not in any profile")
local RS, TC = R.Restore, R.TwichConfig
assert(RS.OWN_LEFT_OUT.quickAccess, "a backup leaves it out, with a reason")
for _, key in ipairs(RS.OWN_KEYS) do assert(key ~= "quickAccess") end
assert(TC.LOCAL.quickAccess, "sharing a configuration leaves it out")
-- no character name: nothing is learned
c.UnitName = function() return nil end
assert(QA.Visit("pins") == false and QA.CharKey() == nil, "while the game cannot say who this is, nothing is counted")
name = "Rich"; c.UnitName = function() return name end

---------------------------------------------------------------------------
-- Saved data: shape, bounds, repair, a newer record, held data, other settings
---------------------------------------------------------------------------
local function Plain(v, seen)
  seen = seen or {}
  local kind = type(v)
  if kind == "function" or kind == "userdata" or kind == "thread" then return false end
  if kind == "table" then
    assert(not seen[v], "no table is shared or cyclic")
    seen[v] = true
    for k, x in pairs(v) do
      if not Plain(k, seen) or not Plain(x, seen) then return false end
    end
  end
  return true
end
Reset(); now = 1800000000
Visits("pins", 3)
assert(Plain(c.TwichUIDB.quickAccess), "only plain data is saved")
for k in pairs(c.TwichUIDB.quickAccess) do assert(k == "v" or k == "chars", "only declared fields: " .. k) end
for k in pairs(c.TwichUIDB.quickAccess.chars[QA.CharKey()]) do assert(k == "f" or k == "seen", "character fields: " .. k) end

-- it survives a save and a load (the way the game keeps variables)
local function Copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in pairs(v) do t[k] = Copy(x) end return t end
local saved = Copy(c.TwichUIDB.quickAccess)
QA.shown = {}
c.TwichUIDB.quickAccess = Copy(saved)
assert(List(QA.Suggest(Eligible)) == "pins", "a saved record gives the same shortcuts after a reload")

-- other saved data is never touched
local others = {}
for k, v in pairs(c.TwichUIDB) do if k ~= "quickAccess" then others[k] = v end end
Visits("food", 2)
for k, v in pairs(others) do assert(c.TwichUIDB[k] == v, "TwichUIDB." .. k .. " is the same table") end

-- records that cannot be read are ignored, and replaced when the feature is next counted
Reset(); now = 1800000000
c.TwichUIDB.quickAccess = { v = 1, chars = { [QA.CharKey()] = { f = {
  pins = { s = 4, t = now }, food = { s = -3, t = now }, hazard = { s = 0 / 0, t = now }, gear = "yes",
  mage = { s = 5, t = "today" }, cozyBag = { s = math.huge, t = now }, [7] = { s = 9, t = now } } } } }
assert(List(QA.Suggest(Eligible)) == "pins", "damaged records are skipped, the sound one still offered")
QA.Visit("food")
local fixed = c.TwichUIDB.quickAccess.chars[QA.CharKey()].f
assert(fixed.food.s == 1 and fixed.gear == nil and fixed.hazard == nil and fixed.mage == nil and fixed[7] == nil and fixed.pins.s == 4,
  "a write keeps what is sound and drops what is not")

-- a root that is the wrong shape is put right by the next count, and looking at it changes nothing
Reset(); now = 1800000000
c.TwichUIDB.quickAccess = "oops"
assert(#QA.Suggest(Eligible) == 0 and c.TwichUIDB.quickAccess == "oops", "a damaged record is only read, never written, by looking")
assert(QA.Visit("pins") == true and type(c.TwichUIDB.quickAccess) == "table" and c.TwichUIDB.quickAccess.v == 1, "counting replaces it")
c.TwichUIDB.quickAccess = { v = 1, chars = "x" }
assert(#QA.Suggest(Eligible) == 0)
assert(QA.Visit("pins") and type(c.TwichUIDB.quickAccess.chars) == "table", "damaged characters table put right")
c.TwichUIDB.quickAccess = { chars = {} }   -- no version: an older or hand-made record
Visits("pins", 2)
assert(c.TwichUIDB.quickAccess.v == 1 and List(QA.Suggest(Eligible)) == "pins", "a record without a version is adopted")

-- a record from a newer TwichUI is never read or changed
Reset(); now = 1800000000
local newer = { v = 2, chars = { [QA.CharKey()] = { f = { pins = { s = 9, t = now } } } }, extra = "kept" }
c.TwichUIDB.quickAccess = newer
local before = Copy(newer)
assert(#QA.Suggest(Eligible) == 0, "a newer record is not read")
assert(QA.Visit("food") == false, "and not written")
local function Same(x, y)
  if type(x) ~= "table" or type(y) ~= "table" then return x == y end
  for k, v in pairs(x) do if not Same(v, y[k]) then return false end end
  for k in pairs(y) do if x[k] == nil then return false end end
  return true
end
assert(c.TwichUIDB.quickAccess == newer and Same(newer, before), "left exactly as it was")

-- while saved data is held (a newer schema set aside), nothing is read or written
Reset(); now = 1800000000
Visits("pins", 3)
local held = true
local isHeld = R.Persist.IsHeld
R.Persist.IsHeld = function(name) return held end
assert(#QA.Suggest(Eligible) == 0, "held: nothing offered")
assert(QA.Visit("food") == false, "held: nothing counted")
held = false
R.Persist.IsHeld = isHeld
assert(List(QA.Suggest(Eligible)) == "pins" and c.TwichUIDB.quickAccess.chars[QA.CharKey()].f.food == nil, "released: as it was")

-- bounded: features per character, characters in all
Reset(); now = 1800000000
local keys = {}
for i = 1, 40 do keys[i] = ("feature%02d"):format(i) end
for i, key in ipairs(keys) do Visits(key, 1 + (i % 4)); end
local feats = c.TwichUIDB.quickAccess.chars[QA.CharKey()].f
local n = 0 for _ in pairs(feats) do n = n + 1 end
assert(n == QA.MAX_FEATURES and QA.MAX_FEATURES == 24, "features per character are bounded: " .. n)
Reset(); now = 1800000000
for i = 1, 45 do
  name = "Alt" .. i
  now = now + MIN * 20
  QA.Visit("pins")
end
local people = 0 for _ in pairs(c.TwichUIDB.quickAccess.chars) do people = people + 1 end
assert(people == QA.MAX_CHARS and c.TwichUIDB.quickAccess.chars["Alt45 - Forever"], "characters are bounded, the one in use kept: " .. people)
assert(not c.TwichUIDB.quickAccess.chars["Alt1 - Forever"] and c.TwichUIDB.quickAccess.chars["Alt16 - Forever"], "the longest unused character goes first")
name = "Rich"

-- a clock set back: the visit counts and nothing grows without bound
Reset(); now = 1800000000
QA.Visit("pins")
now = now - 3 * DAY
assert(QA.Visit("pins") == true, "a visit after the clock moved back counts")
local fut = c.TwichUIDB.quickAccess.chars[QA.CharKey()].f.pins
assert(fut.t == now and fut.s <= 2.001 and fut.s >= 1.99, "and the score is sensible: " .. fut.s)
for _ = 1, 400 do now = now + 11 * MIN; QA.Visit("pins") end
assert(c.TwichUIDB.quickAccess.chars[QA.CharKey()].f.pins.s <= 100, "a score has a ceiling")

-- bad arguments
assert(QA.Visit(nil) == false and QA.Visit("") == false and QA.Visit(5) == false, "only a page key counts")
assert(#QA.Pick(nil, now, Eligible, nil) == 0 and #QA.Pick({}, now, Eligible, { "pins" }) == 0, "nothing in, nothing out")
assert(#QA.Pick({ pins = { s = 5, t = now } }, now, Eligible, { "pins", "pins", "gone" }) == 1, "a repeated or unknown earlier shortcut is harmless")

print("PASSED")
