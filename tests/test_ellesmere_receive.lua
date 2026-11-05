-- EllesmereUI profile sharing, receiving side: entry validation (ES.CleanEntry),
-- what a received setup offers (ES.Source), and the rule that EllesmereUI's own
-- database tables are never applied as tables (ES.Blocked / ES.IsTable).
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local ES = c.TwichUI.Ellesmere
local LibDeflate = c.LibStub("LibDeflate")

-- ---------------------------------------------------------------------------
-- ES.IsTable: which table names are EllesmereUI's own saved tables
-- ---------------------------------------------------------------------------
assert(ES.IsTable("EllesmereUIDB") == true, "the main saved table is an EllesmereUI table")
assert(ES.IsTable("EllesmereUIQoLDB") == true, "other EllesmereUI*DB names are its tables too")
assert(ES.IsTable("EllesmereUI") == false, "the addon name itself is not a saved table")
assert(ES.IsTable("EllesmereUIFoo") == false, "a name not ending in DB is not a saved table")
assert(ES.IsTable("FooDB") == false, "a non-Ellesmere table name is not one of its tables")
assert(ES.IsTable(nil) == false, "non-string input is not a table name")
assert(ES.IsTable(123) == false, "non-string input is not a table name")

-- ---------------------------------------------------------------------------
-- ES.Blocked: EllesmereUI tables are never applied as tables from a setup
-- from someone else, except for a restore of your own data
-- ---------------------------------------------------------------------------
for _, name in ipairs({ "EllesmereUIDB", "EllesmereUIQoLDB", "EllesmereUIBagsDB" }) do
  assert(ES.Blocked("Rich|id123", name) == true, name .. " is blocked for an ordinary source key")
  assert(ES.Blocked(nil, name) == true, name .. " is blocked for a nil source key")
  assert(ES.Blocked("whatever", name) == true, name .. " is blocked for any non-restore string")
  assert(ES.Blocked("restore:" .. name, name) == false, name .. " is not blocked for a restore source key")
end
assert(ES.Blocked("Rich|id123", "FooDB") == false, "a non-Ellesmere table name is never blocked")
assert(ES.Blocked("restore:FooDB", "FooDB") == false, "a non-Ellesmere table name is never blocked, even for restore")
assert(ES.Blocked("Rich|id123", "EllesmereUI") == false, "a name that is not an EllesmereUI table is never blocked")

-- ---------------------------------------------------------------------------
-- ES.CleanEntry: keep only what a profile entry should hold
-- ---------------------------------------------------------------------------
local STR = "!EUI_" .. ("x"):rep(20)
local GOOD = {
  id = "abc123", name = "  P1 |  ", str = STR,
  hash = "0:999", made = 1234567890, euiVersion = "1.2.3", extra = "junk",
}
local out = ES.CleanEntry(GOOD)
assert(type(out) == "table", "a well-formed entry is kept")
local keys, n = {}, 0
for k in pairs(out) do keys[k] = true; n = n + 1 end
assert(n == 6, "the entry holds only id, name, str, hash, made, euiVersion")
for _, k in ipairs({ "id", "name", "str", "hash", "made", "euiVersion" }) do
  assert(keys[k] == true, "the entry keeps " .. k)
end
assert(out.id == "abc123", "the id is kept as-is")
assert(out.name == "P1", "the name is cleaned: control chars, '|' and surrounding spaces are stripped")
assert(out.str == STR, "the export string is kept as-is")
assert(out.hash == LibDeflate:Adler32(STR) .. ":" .. #STR, "the hash is recomputed as adler32:len")
assert(out.made == 1234567890, "made is kept when it is a number")
assert(out.euiVersion == "1.2.3", "euiVersion is kept when it is a string")

assert(ES.CleanEntry(nil) == nil, "a non-table is not an entry")
assert(ES.CleanEntry({ id = "a", name = "n" }) == nil, "a missing str is not an entry")
assert(ES.CleanEntry({ str = 42, id = "a", name = "n" }) == nil, "a non-string str is not an entry")
assert(ES.CleanEntry({ str = "noEUI" .. ("x"):rep(20), id = "a", name = "n" }) == nil, "a str without the '!EUI_' magic prefix is not an entry")
assert(ES.CleanEntry({ str = STR, name = "n" }) == nil, "a missing id is not an entry")
assert(ES.CleanEntry({ str = STR, id = "", name = "n" }) == nil, "an empty id is not an entry")
assert(ES.CleanEntry({ str = STR, id = "a\0b", name = "n" }) == nil, "an id containing a control char is not an entry")
assert(ES.CleanEntry({ str = STR, id = "a|b", name = "n" }) == nil, "an id containing '|' is not an entry")
assert(ES.CleanEntry({ str = STR, id = "a" }) == nil, "a missing name is not an entry")
assert(ES.CleanEntry({ str = STR, id = "a", name = "  |  " }) == nil, "a name that cleans to empty is not an entry")

local e = ES.CleanEntry({ id = "a", name = "n", str = STR, made = "not a number" })
assert(e.made == nil, "made is dropped when it is not a number")
e = ES.CleanEntry({ id = "a", name = "n", str = STR, euiVersion = 5 })
assert(e.euiVersion == nil, "euiVersion is dropped when it is not a string")
local LONG = ("1"):rep(60)
e = ES.CleanEntry({ id = "a", name = "n", str = STR, euiVersion = LONG })
assert(e.euiVersion == ("1"):rep(40), "euiVersion is truncated to 40 characters")
local LONGNAME = ("N"):rep(150)
e = ES.CleanEntry({ id = "a", name = LONGNAME, str = STR })
assert(e.name == ("N"):rep(100), "the name is truncated to 100 characters")

-- ---------------------------------------------------------------------------
-- ES.Source: what a received setup offers for EllesmereUI
-- ---------------------------------------------------------------------------
local prof = ES.Source({ source = "Rich", eui = GOOD })
assert(prof and prof.kind == "profile", "a well-formed eui entry yields kind 'profile'")
assert(prof.name == "P1", "the profile name is cleaned")
assert(prof.key == "Rich|abc123", "the key is source|id")
assert(prof.entry == GOOD, "the entry is carried through")
assert(prof.made == 1234567890, "made is carried through")
assert(prof.euiVersion == "1.2.3", "euiVersion is carried through")

local ok, why = ES.Source({ source = "Rich", eui = { str = "noEUI" .. ("x"):rep(20), id = "a", name = "n" } })
assert(ok == nil, "a damaged eui entry is not offered")
assert(why == "the profile in this setup is damaged", "the reason for a damaged eui entry")

local LEGACY_DB = {
  activeProfile = "Mine",
  profiles = {
    Mine = { addons = { EllesmereUIActionBars = { scale = 1 } } },
    Empty = { addons = {} },
  },
}
local leg = ES.Source({ source = "Pal", tables = { EllesmereUIDB = { data = LEGACY_DB } } })
assert(leg and leg.kind == "legacy", "an older share carrying the whole database yields kind 'legacy'")
assert(leg.name == "Mine", "the sender's active profile is pulled out")
assert(leg.key == "Pal|legacy:Mine", "the legacy key is source|legacy:name")
assert(leg.legacyProfile == LEGACY_DB.profiles.Mine, "the active profile's table is carried")
assert(leg.made == nil, "the legacy source carries the pack's created time (absent here)")

local leg2 = ES.Source({ source = "Pal", tables = { EllesmereUIDB = { data = { profiles = { Default = { addons = { A = { x = 1 } } } } } } } })
assert(leg2 and leg2.kind == "legacy" and leg2.name == "Default", "without an active profile the 'Default' profile is used")
assert(leg2.legacyProfile.addons.A.x == 1, "the 'Default' profile is carried")

local leg3, why3 = ES.Source({ source = "Pal", tables = { EllesmereUIDB = { data = { profiles = { Default = { addons = {} } } } } } })
assert(leg3 == nil, "a legacy share whose active profile has no module settings is not offered")
assert(why3 == "this older setup holds a whole EllesmereUI database and its active profile has no module settings", "the reason names the legacy database and the empty profile")

local _, why4 = ES.Source({ source = "Pal", tables = { EllesmereUIDB = { data = { profiles = {} } } } })
assert(why4 == "this older setup holds a whole EllesmereUI database and its active profile has no module settings", "a database with no profiles has no usable active profile")
local _, why5 = ES.Source({ source = "Pal", tables = { EllesmereUIDB = { data = { noProfiles = true } } } })
assert(why5 == "this older setup holds a whole EllesmereUI database and it doesn't hold any profiles", "the reason for a database that holds no profiles table")

assert(ES.Source(nil) == nil, "a non-table pack has no source")
assert(ES.Source({ source = "Rich" }) == nil, "a pack with neither an eui entry nor the database has no source")

print("TEST_ELLESMERE_RECEIVE PASSED")
