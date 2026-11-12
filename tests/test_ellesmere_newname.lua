-- ES.NewName: the name a received profile is imported under.
-- Contract (Ellesmere.lua: "A name no existing profile uses (case aside), within
-- EllesmereUI's name limit"; name limit 30; empty cleaned name -> "Imported";
-- sender tail is the cleaned sender truncated to 10 characters; collisions get
-- a numbered suffix until the name is free, so nothing existing is overwritten).
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local ES = c.TwichUI.Ellesmere

-- A stand-in for EllesmereUI's profile functions: only what ES.Api() and
-- ES.ProfileNames() read (see test_ellesmere_share.lua InstallEUI for the full shape).
local db = { activeProfile = "Mine", profileOrder = {}, profiles = {} }
-- ES.Api() requires all five profile functions to be present.
c.EllesmereUI = {
  IS_FOREVER = true,
  GetProfileList = function() return db.profileOrder, db.profiles end,
  GetActiveProfileName = function() return db.activeProfile end,
  ExportProfile = function() end,
  DecodeImportString = function() end,
  ImportProfile = function() end,
}

local function Add(name)
  db.profiles[name] = { addons = {} }
  db.profileOrder[#db.profileOrder + 1] = name
end

local function IsTaken(name)
  for _, n in ipairs(ES.ProfileNames()) do
    if n:lower() == name:lower() then return true end
  end
  return false
end

-- Fresh: the cleaned profile name plus the "(sender)" tail.
assert(ES.NewName("Raid", "Rich") == "Raid (Rich)", "profile name plus sender tail")

-- The sender tail is the cleaned sender truncated to 10 characters.
assert(ES.NewName("Raid", "VeryLongSenderName") == "Raid (VeryLongSe)", "sender cut to 10 characters")

-- An empty or whitespace-only profile name falls back to the base "Imported".
assert(ES.NewName("", "Rich") == "Imported (Rich)", "empty name becomes Imported")
assert(ES.NewName("   ", "Rich") == "Imported (Rich)", "whitespace-only name becomes Imported")

-- A case-insensitive collision with an existing profile gets a numbered suffix
-- and the result stays unused, so nothing existing is overwritten.
Add("raid (rich)")
local n1 = ES.NewName("Raid", "Rich")
assert(n1 == "Raid (Rich) 2", "collision gets a numbered suffix")
assert(not IsTaken(n1), "the new name is not one an existing profile uses")

-- Multiple collisions: the suffix increments until a free name is found.
Add("Raid (Rich) 2")
Add("Raid (Rich) 3")
local n2 = ES.NewName("Raid", "Rich")
assert(n2 == "Raid (Rich) 4", "suffix increments past every taken name")
assert(not IsTaken(n2), "the incremented name is free")

-- A long profile name with a long sender still stays within the 30-character limit.
local long = ES.NewName("AveryLongProfileNameHere", "VeryLongSenderName")
assert(#long == 30, "a long source still yields a name of at most 30 characters")
assert(long == "AveryLongProfileN (VeryLongSe)", "the base is cut, the sender tail is kept")

-- Control characters and '|' are stripped from the profile name and the sender.
assert(ES.NewName("My|Profile" .. string.char(7), string.char(1) .. "B|C") == "MyProfile (BC)", "junk stripped from name and sender")

print("TEST_ELLESMERE_NEWNAME PASSED")
