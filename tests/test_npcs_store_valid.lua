-- npcs/Store.lua's own checks, straight from the entry table: NS.Valid, NS.ValidCoord, NS.ValidId,
-- NS.CleanProfession, NS.CleanTitle. Contract: Store.lua's header (lines 15-17) — "Everything is checked
-- here, the same way for what you saw and what arrived: the creature id, a map the client knows that is a
-- zone or smaller, coordinates in range, kinds from npcs/Kinds.lua only, class tokens from its list, names
-- as plain text (pins/Pins.lua's CleanName). An entry that can't be read is skipped, never erased."
-- The field rules as written in the code: Whole(n, low, high) is a number, not NaN, integral, low..high
-- (Store.lua:41-43); ValidCoord is 0..10000, ValidId is 1..2^31 (Store.lua:67-68); CleanProfession and
-- CleanTitle are pins/Pins.lua's CleanName cut at 32/48 bytes ("Plain text, at most NAME_MAX bytes (or max),
-- or nil when nothing is left", Pins.lua:64); Valid (Store.lua:89-96) accepts an entry only when every field
-- passes, with cls, prof, t, own, seen, rep and at optional (nil is fine).
dofile(TESTS .. "harness.lua")

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

local c = MakeClient("Rich", { "!!!TwichUI" })
CLIENTS["Rich"] = c
Load(c, { "pins/Pins.lua", "npcs/Kinds.lua", "npcs/Store.lua" })
local NS = c.TwichUI.NpcStore

---------------------------------------------------------------------------
-- NS.ValidCoord: a whole number in 0..10000 (Store.lua:67)
---------------------------------------------------------------------------
assert(NS.ValidCoord(0) == true, "0 is the lowest coordinate step")
assert(NS.ValidCoord(10000) == true, "10000 is the highest coordinate step")
assert(NS.ValidCoord(5000) == true, "a step in the middle")
assert(NS.ValidCoord(-1) == false, "below the range")
assert(NS.ValidCoord(10001) == false, "above the range")
assert(NS.ValidCoord(1.5) == false, "not a whole step")
assert(NS.ValidCoord("5") == false, "a number, not a string of one")
assert(NS.ValidCoord(nil) == false, "missing is not a coordinate")
assert(NS.ValidCoord(0 / 0) == false, "NaN is not a coordinate")

---------------------------------------------------------------------------
-- NS.ValidId: a whole number in 1..2^31 (Store.lua:68)
---------------------------------------------------------------------------
assert(NS.ValidId(1) == true, "the lowest creature id")
assert(NS.ValidId(2 ^ 31) == true, "the highest creature id")
assert(NS.ValidId(1453001) == true, "an id in the middle")
assert(NS.ValidId(0) == false, "zero is not a creature id")
assert(NS.ValidId(2 ^ 31 + 1) == false, "above the range")
assert(NS.ValidId(-1) == false, "below the range")
assert(NS.ValidId(1.5) == false, "not a whole id")
assert(NS.ValidId("1") == false, "a number, not a string of one")
assert(NS.ValidId(0 / 0) == false, "NaN is not an id")

---------------------------------------------------------------------------
-- NS.CleanProfession: pins/Pins.lua's CleanName cut at 32 bytes (Store.lua:50, Pins.lua:64-79)
---------------------------------------------------------------------------
assert(NS.CleanProfession("Alchemy") == "Alchemy", "plain text stays")
assert(NS.CleanProfession("|cff00ff00Alchemy|r") == "Alchemy", "escape sequences are taken out")
assert(NS.CleanProfession("|Hitem:1:2:3|hHammer|h") == "Hammer", "a link keeps the text between its |h markers")
assert(NS.CleanProfession("|T13:13:0:0:32:32:0:0:1:1|t") == nil, "a texture alone leaves nothing")
assert(NS.CleanProfession("Alch   emistry") == "Alch emistry", "runs of blanks become one")
assert(NS.CleanProfession(string.rep("a", 32)) == string.rep("a", 32), "32 bytes fit")
assert(NS.CleanProfession(string.rep("a", 33)) == string.rep("a", 32), "33 bytes are cut at 32")
-- 31 plain bytes plus one 3-byte character: the cut must land on the character boundary, not inside it
local prof34 = string.rep("a", 31) .. "\226\130\172"
assert(NS.CleanProfession(prof34) == string.rep("a", 31), "cut on a character boundary, 31 bytes kept")
assert(NS.CleanProfession(nil) == nil, "not a string, nothing to clean")
assert(NS.CleanProfession(123) == nil, "not a string, nothing to clean")
assert(NS.CleanProfession("|r|r") == nil, "text that cleans to empty is nil")

---------------------------------------------------------------------------
-- NS.CleanTitle: the same rules at 48 bytes (Store.lua:51)
---------------------------------------------------------------------------
assert(NS.CleanTitle("Enchanting Reagents") == "Enchanting Reagents", "plain text stays")
assert(NS.CleanTitle("|cff808080Enchanting Reagents|r") == "Enchanting Reagents", "escape sequences are taken out")
assert(NS.CleanTitle(string.rep("a", 48)) == string.rep("a", 48), "48 bytes fit")
assert(NS.CleanTitle(string.rep("a", 49)) == string.rep("a", 48), "49 bytes are cut at 48")
-- 47 plain bytes plus one 3-byte character: the cut must land on the character boundary, not inside it
local title50 = string.rep("a", 47) .. "\226\130\172"
assert(NS.CleanTitle(title50) == string.rep("a", 47), "cut on a character boundary, 47 bytes kept")
assert(NS.CleanTitle(nil) == nil, "not a string, nothing to clean")
assert(NS.CleanTitle(4.5) == nil, "not a string, nothing to clean")
assert(NS.CleanTitle("|T13:13:0:0:32:32:0:0:1:1|t") == nil, "text that cleans to empty is nil")

---------------------------------------------------------------------------
-- NS.Valid: a fully valid entry passes, and each field broken alone fails (Store.lua:89-96)
---------------------------------------------------------------------------
local function entry(over)
  local e = {
    id = 1453001,            -- a creature id in 1..2^31
    n = "Grommash Hellscream", -- plain text, 19 bytes, at most 48
    m = 1429,                 -- a whole number in 1..2^31 (Valid does not look the map up)
    x = 5000, y = 5000,       -- whole steps in 0..10000
    tags = { vendor = true }, -- a known kind (npcs/Kinds.lua), value exactly true
  }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end
assert(NS.Valid(entry()) == true, "a fully valid entry passes")
assert(NS.Valid(entry({ cls = { MAGE = true } })) == true, "a known class token, value true")
assert(NS.Valid(entry({ prof = string.rep("a", 32) })) == true, "a profession name of 32 bytes fits")
assert(NS.Valid(entry({ t = string.rep("a", 48) })) == true, "a title of 48 bytes fits")
assert(NS.Valid(entry({ own = true, seen = 99, rep = 99, at = 2 ^ 40 })) == true, "the optional fields at their limits")
assert(NS.Valid(entry({ cls = nil, prof = nil, t = nil, own = nil, seen = nil, rep = nil, at = nil })) == true,
  "cls, prof, t, own, seen, rep and at are optional")

assert(NS.Valid(nil) == false, "not a table")
assert(NS.Valid("Grommash") == false, "not a table")
assert(NS.Valid(entry({ id = 0 })) == false, "id below the range")
assert(NS.Valid(entry({ id = 2 ^ 31 + 1 })) == false, "id above the range")
assert(NS.Valid(entry({ id = 1.5 })) == false, "id not a whole number")
assert(NS.Valid(entry({ id = "1453001" })) == false, "id a string")
assert(NS.Valid(entry({ n = "" })) == false, "an empty name")
assert(NS.Valid(entry({ n = string.rep("a", 49) })) == false, "a name of 49 bytes")
assert(NS.Valid(entry({ n = 123 })) == false, "a name that is not text")
assert(NS.Valid(entry({ m = 0 })) == false, "a map below the range")
assert(NS.Valid(entry({ m = 2 ^ 31 + 1 })) == false, "a map above the range")
assert(NS.Valid(entry({ m = 1.5 })) == false, "a map not a whole number")
assert(NS.Valid(entry({ x = -1 })) == false, "x below the range")
assert(NS.Valid(entry({ x = 10001 })) == false, "x above the range")
assert(NS.Valid(entry({ x = 5000.5 })) == false, "x not a whole step")
assert(NS.Valid(entry({ y = -1 })) == false, "y below the range")
assert(NS.Valid(entry({ y = 10001 })) == false, "y above the range")
assert(NS.Valid(entry({ y = 5000.5 })) == false, "y not a whole step")
assert(NS.Valid(entry({ tags = {} })) == false, "no tags at all")
assert(NS.Valid(entry({ tags = { unknown = true } })) == false, "a kind npcs/Kinds.lua does not know")
assert(NS.Valid(entry({ tags = { vendor = 1 } })) == false, "a tag value that is not true")
assert(NS.Valid(entry({ tags = { vendor = true, unknown = true } })) == false, "one unknown kind among good ones")
assert(NS.Valid(entry({ cls = { UNKNOWN = true } })) == false, "a class token the list does not know")
assert(NS.Valid(entry({ cls = { MAGE = 1 } })) == false, "a class value that is not true")
assert(NS.Valid(entry({ cls = "MAGE" })) == false, "cls must be a table when present")
assert(NS.Valid(entry({ prof = string.rep("a", 33) })) == false, "a profession name of 33 bytes")
assert(NS.Valid(entry({ prof = 123 })) == false, "a profession name that is not text")
assert(NS.Valid(entry({ t = "" })) == false, "an empty title")
assert(NS.Valid(entry({ t = string.rep("a", 49) })) == false, "a title of 49 bytes")
assert(NS.Valid(entry({ t = 4.5 })) == false, "a title that is not text")
assert(NS.Valid(entry({ own = false })) == false, "own must be true when present")
assert(NS.Valid(entry({ own = 1 })) == false, "own must be true, not a truthy number")
assert(NS.Valid(entry({ seen = 100 })) == false, "seen above 99")
assert(NS.Valid(entry({ seen = -1 })) == false, "seen below 0")
assert(NS.Valid(entry({ seen = 1.5 })) == false, "seen not a whole number")
assert(NS.Valid(entry({ rep = -1 })) == false, "rep below 0")
assert(NS.Valid(entry({ rep = 100 })) == false, "rep above 99")
assert(NS.Valid(entry({ at = -1 })) == false, "at below 0")
assert(NS.Valid(entry({ at = 2 ^ 40 + 1 })) == false, "at above its bound")
assert(NS.Valid(entry({ at = 1.5 })) == false, "at not a whole number")

print("TEST_NPCS_STORE_VALID PASSED")
