dofile(TESTS .. "harness.lua")
-- Applying a setup when one addon is load-on-demand, one is turned off, and
-- the setup names things that aren't addon settings.
LOD = { Bar = true }
OFF = { Off = true }
local function boot(saved)
  local c = MakeClient("Pal", {"!!!TwichUI","Foo","Bar","Off"})
  local said, base = {}, c.print
  c.print = function(s) said[#said + 1] = tostring(s); base(s) end
  c.said = said
  if saved then c.TwichUIDB, c.TwichUIBackupDB = saved.TwichUIDB, saved.TwichUIBackupDB end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  return c
end
local function heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end

local pal = boot()
pal.TwichUIDB.setup.received["Rich-Forever"] = { created = 5, source = "Rich - Forever", tables = {
  FooDB = { owner = "Foo", data = { a = 1 } },
  BarDB = { owner = "Bar", data = { b = 2 } },
  TwichUIDB = { owner = "Foo", data = { modules = {} } },   -- our own data
  print = { owner = "Foo", data = {} },                     -- a function
  SlashCmdList = { owner = "Foo", data = {} },              -- a table that exists before Foo loads
} }
pal.FireEvent("PLAYER_LOGIN")
local ST = pal.TwichUI.Setups
assert(ST.AddonState("Foo") == "ready" and ST.AddonState("Off") == "disabled" and ST.AddonState("Nope") == "missing", "addon states")
ST:Queue("apply", {"FooDB", "BarDB", "TwichUIDB", "print", "SlashCmdList"}, "recv:Rich-Forever")
assert(pal.reloaded)

-- Session 2: Foo loads, Bar (load-on-demand) doesn't.
local s2 = boot(pal)
s2.FooDB = { a = 0 }; s2.LOADED.Foo = true; s2.FireEvent("ADDON_LOADED", "Foo")
s2.FireEvent("PLAYER_LOGIN")
assert(s2.FooDB.a == 1, "Foo applied")
assert(type(s2.print) == "function" and s2.SlashCmdList.TWICHUI and s2.TwichUIDB.setup, "non-settings left alone")
assert(heard(s2, "applied (1 settings)") and heard(s2, "skipped 3"), "summary printed")
assert(s2.TwichUIDB.setup.pending and s2.TwichUIDB.setup.pending.tables.BarDB, "Bar still waiting")

-- Session 3: still waiting, so no second summary; then Bar loads on demand.
local s3 = boot(s2)
s3.FooDB = { a = 1 }; s3.LOADED.Foo = true; s3.FireEvent("ADDON_LOADED", "Foo")
s3.FireEvent("PLAYER_LOGIN")
assert(not heard(s3, "applied"), "summary printed once only")
s3.BarDB = { b = 0 }; s3.LOADED.Bar = true; s3.FireEvent("ADDON_LOADED", "Bar")
assert(s3.BarDB.b == 2, "Bar applied when it loaded")
assert(s3.TwichUIDB.setup.pending == nil, "nothing left waiting")
assert(s3.TwichUIBackupDB["Pal - Forever"].tables.BarDB.data.b == 0, "Bar backed up first")
print("LOAD-ON-DEMAND APPLY TESTS PASSED")
