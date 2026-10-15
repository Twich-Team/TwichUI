dofile(TESTS .. "harness.lua")
-- The memory section of the troubleshooting report (diag/Memory.lua) and /tui diagnostics memory: nothing runs or
-- is read until asked; the game's count is read at most every READ_EVERY seconds; saved data is counted by part,
-- exactly and within bounds; the report names no character and no stored table; a garbage collection happens only
-- when "collect" is typed.
local out = {}
local c = MakeClient("Rich", {"!!!TwichUI"})
c.print = function(s) out[#out + 1] = tostring(s) end
local now = 100
c.GetTime = function() return now end
local reads, collects = 0, 0
c.UpdateAddOnMemoryUsage = function() reads = reads + 1 end
c.GetAddOnMemoryUsage = function(name) return name == "!!!TwichUI" and 12345.6 or 0 end
c.collectgarbage = function(what) if what == "collect" then collects = collects + 1 end return 0 end

-- Loading the file: no frame, no timer, no event.
local R = c.TwichUI
local framesMade, timers, ons = 0, 0, 0
local realCreate, realAfter, realOn = c.CreateFrame, c.C_Timer.After, R.On
for _, f in ipairs({ "diag/Diagnostics.lua", "diag/Saved.lua", "diag/Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.CreateFrame = function(...) framesMade = framesMade + 1 return realCreate(...) end
c.C_Timer.After = function(...) timers = timers + 1 return realAfter(...) end
R.On = function(...) ons = ons + 1 return realOn(...) end
local chunk = assert(loadfile(ROOT .. "diag/Memory.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
c.CreateFrame, c.C_Timer.After, R.On = realCreate, realAfter, realOn
assert(framesMade == 0 and timers == 0 and ons == 0, "the memory section makes no frame, timer or listener")

c.LOADED["!!!TwichUI"] = true
c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
for _ = 1, 5 do FlushTimers() end
assert(reads == 0 and collects == 0, "nothing is read or collected until asked")

local M, D = R.DiagMemory, R.Diag
assert(M and D, "the section loaded")

-- Counting: every key of every table, exactly.
assert(M.Values({ a = 1, b = { c = 1, d = { e = 1 } } }) == 5)
assert(M.Values({}) == 0 and M.Values(nil) == 0 and M.Values("text") == 0)
assert(M.Values({ 1, 2, 3, { 4, 5 } }) == 6)
-- Bounded whatever the data: a table that holds itself, twice, stops at the bounds.
local loop = {}
loop.a, loop.b = loop, loop
local n, capped = M.Values(loop)
assert(capped and n > 0, "a cycle is cut off at the bound")
local deep = {}
local cur = deep
for _ = 1, 100 do cur.next = {}; cur = cur.next end
local d, dcapped = M.Values(deep)
assert(d == 64 and not dcapped, "depth stops at 64: " .. d)

-- Synthetic saved data with known sizes. The names must never reach the report.
c.TwichUIRestoreDB = { points = {
  { id = "1", name = "Before raid", created = 1, tables = { FooDB = { owner = "Foo", data = { x = 1, y = 2 } } } },
  { id = "2", name = "Big", created = 2, tables = { BigData = { owner = "Big", data = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } } } },
} }
c.TwichUIShareDB = { pack = { format = 2, tables = { FooDB = { owner = "Foo", data = { x = 1 } } } } }
c.TwichUIDB.setup.received = { ["Pal-Forever"] = { tables = { PalSecretDB = { owner = "Pal", data = { a = 1 } } } } }
c.TwichUIChronicleDB = { version = 1, chars = { ["Rich - Forever"] = { entries = { { text = "a note" } } } } }
c.TwichUIBackupDB = {}

local parts, total = M.Saved()
local byKey = {}
for _, p in ipairs(parts) do byKey[p.key] = p end
assert(byKey.backups.items == 2, "two backups")
-- point 1: id, name, created, tables, FooDB, owner, data, x, y = 9; point 2: id, name, created, tables, BigData,
-- owner, data and ten values = 17; plus points and the two list entries = 29
assert(byKey.backups.values == 29, "backup values: " .. byKey.backups.values)
assert(byKey.backups.largest == 17, "the largest backup: " .. tostring(byKey.backups.largest))
assert(byKey.mine.values == 7, "your setup: " .. byKey.mine.values)
assert(byKey.received.items == 1 and byKey.received.values == 6, "received: " .. byKey.received.values)
assert(byKey.chronicle.values == 6, "chronicle: " .. byKey.chronicle.values)
assert(byKey.undo.values == 0 and byKey.undo.items == 0)
local sum = 0
for _, p in ipairs(parts) do sum = sum + p.values end
assert(total == sum and byKey.settings.values == M.Values(c.TwichUIDB) - 6, "settings exclude received setups; the total adds up")

-- The report: one read of the game's count, then none for READ_EVERY seconds.
local report = D.Build()
local from = report:find("== Memory ==", 1, true)
assert(from, "the report has a memory section")
local section = report:sub(from, report:find("\n== ", from + 5, true) or #report)
assert(section:find("12,346 KB", 1, true), section)
assert(section:find("not loaded this session", 1, true), "the settings window has not been loaded")
assert(section:find("backups (TwichUIRestoreDB): 29 values; 2 items; the largest 17 values", 1, true), section)
for _, secret in ipairs({ "Pal", "Rich", "FooDB", "BigData", "PalSecretDB", "Before raid", "a note" }) do
  assert(not section:find(secret, 1, true), "the report leaves out " .. secret)
end
assert(reads == 1 and collects == 0, "one read, no collection")
D.Build()
assert(reads == 1, "a second report within the interval reuses the reading")
now = now + M.READ_EVERY
D.Build()
assert(reads == 2, "read again after the interval")

-- The chat command: the game's count read fresh, the largest tables by name, no character names, and a
-- collection only when asked for.
out = {}
M.Command("")
local said = table.concat(out, "\n")
assert(reads == 3 and collects == 0, "the command reads fresh and collects nothing")
assert(said:find("BigData in a backup (10)", 1, true), said)
assert(said:find("FooDB in your setup", 1, true) and said:find("PalSecretDB in a received setup", 1, true), said)
assert(not said:find("Pal-Forever", 1, true) and not said:find("Rich", 1, true) and not said:find("Before raid", 1, true), said)
out = {}
M.Command("collect")
assert(collects == 1, "collect runs one full collection")
assert(table.concat(out, "\n"):find("after one full garbage collection", 1, true))

-- Through /tui diagnostics memory
out = {}
R.RunCommand("diagnostics memory")
assert(table.concat(out, "\n"):find("the game's count", 1, true) and collects == 1, "the command is reachable and collects nothing by itself")
assert(not D.Tracing(), "tracing stays off")
print("MEMORY DIAG TEST PASSED")
