-- Backups hold TwichUI's own settings (setup/Restore.lua): what is kept and left out, restore at the start of the
-- next load with an Undo copy, Undo, own-only backups, export/import (format 2, format 1 still read) and refusals.
dofile(TESTS .. "harness.lua")

local SV = { "TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB", "FooDB" }
local function copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local t = {}; seen[v] = t
  for k, x in pairs(v) do t[copy(k, seen)] = copy(x, seen) end
  return t
end

-- A client loaded from saved variables, as the game does at login. foo: whether the Foo addon loads.
local function Boot(sv, foo)
  local c = MakeClient("Twich", foo and { "!!!TwichUI", "Foo" } or { "!!!TwichUI" })
  for _, n in ipairs(SV) do if n ~= "FooDB" then c[n] = copy(sv[n]) end end
  c.said = {}
  c.print = function(s) c.said[#c.said + 1] = tostring(s) end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  if foo then
    c.FooDB = copy(sv.FooDB)
    c.LOADED.Foo = true; c.FireEvent("ADDON_LOADED", "Foo")
  end
  c.FireEvent("PLAYER_LOGIN")
  for _ = 1, 5 do FlushTimers() end
  return c
end
local function Logout(c)
  c.FireEvent("PLAYER_LOGOUT")
  local s = {}
  for _, n in ipairs(SV) do s[n] = copy(c[n]) end
  return s
end
local function heard(c, text)
  for _, s in ipairs(c.said) do if s:find(text, 1, true) then return true end end
  return false
end
local function shares(a, b)
  local seen = {}
  local function walk(t) if type(t) == "table" and not seen[t] then seen[t] = true for _, v in pairs(t) do walk(v) end end end
  walk(a)
  local found, visited = false, {}
  local function look(t)
    if type(t) ~= "table" or visited[t] then return end
    visited[t] = true
    if seen[t] then found = true return end
    for _, v in pairs(t) do look(v) end
  end
  look(b)
  return found
end

---------------------------------------------------------------------------
-- Every key TwichUI saves is either backed up or left out with a reason
---------------------------------------------------------------------------
local c = Boot({ TwichUIDB = { setup = { scanNext = true } }, FooDB = { a = 1 } }, true)
local R = c.TwichUI
local RS, ST, P = R.Restore, R.Setups, R.Portable
local placed = {}
for _, k in ipairs(RS.OWN_KEYS) do placed[k] = "kept" end
for _, k in ipairs(RS.OWN_SETUP) do placed["setup." .. k] = "kept" end
for k in pairs(RS.OWN_LEFT_OUT) do assert(not placed[k], k .. " is both kept and left out"); placed[k] = "left" end
local function Placed(path) return placed[path] ~= nil end
-- top-level keys any file names, and the profile roots Profiles.lua reaches through its own name for TwichUIDB
local top = { profiles = true, profileKeys = true, profileState = true }
local function scan(dir)
  local h = io.popen('find "' .. dir .. '" -name "*.lua" -not -path "*/libs/*"')
  for f in h:lines() do
    local fh = io.open(f); local src = fh:read("*a"); fh:close()
    for k in src:gmatch("TwichUIDB%.([%a_][%w_]*)") do top[k] = true end
    for k in src:gmatch("TwichUIDB%.setup%.([%a_][%w_]*)") do top["setup." .. k] = true end
  end
  h:close()
end
scan(ROOT)
-- the setup keys Setups.lua looks after
local fh = io.open(ROOT .. "setup/Setups.lua"); local setupSrc = fh:read("*a"); fh:close()
local body = setupSrc:match("function ST%.NormalizeDb%(d%)(.-)\nend\n")
for k in body:gmatch("d%.([%a_][%w_]*)") do top["setup." .. k] = true end
for k in setupSrc:match('local SETUP_TABLES = (%b{})'):gmatch('"([%a_]+)"') do top["setup." .. k] = true end
-- and whatever is there after a real load
for k in pairs(c.TwichUIDB) do top[k] = true end
for k in pairs(c.TwichUIDB.setup) do top["setup." .. k] = true end
top.setup = nil
for k in pairs(top) do assert(Placed(k), "TwichUIDB." .. k .. " is neither backed up nor left out with a reason") end
for _, reason in pairs(RS.OWN_LEFT_OUT) do assert(type(reason) == "string" and #reason > 5) end
assert(not Placed("pins") or placed.pins == "left", "map pins are never part of a backup")

---------------------------------------------------------------------------
-- Creating: TwichUI's settings are copied, records are not
---------------------------------------------------------------------------
local db = c.TwichUIDB
db.ui = db.ui or {}
db.ui.backupTest = "before"
db.modules.chronicle = false
db.shareTransport = "PARTY"
db.setup.trusted["Pal-Forever"] = true
db.pins = { list = { { id = "p1", label = "kept pin" } } }
db.storedData = db.storedData or {}
db.setup.received.Pal = { tables = {}, created = 5 }
ST.db.selection.FooDB = true
local status, point = RS:Create("snap")
assert(status == "created" and RS.HasOwn(point), "a backup holds TwichUI's settings")
local own = point.own
assert(own.schema == R.Persist.SCHEMA and own.keys.ui.backupTest == "before" and own.keys.modules.chronicle == false)
assert(own.keys.shareTransport == "PARTY" and own.keys.setup.trusted["Pal-Forever"] == true)
assert(own.keys.pins == nil and own.keys.storedData == nil and own.keys.welcome == nil and own.keys.schema == nil, "records left out")
assert(own.keys.setup.received == nil and own.keys.setup.pending == nil and own.keys.setup.detected == nil, "sharing records left out")
assert(point.tables.FooDB, "addon settings still in it")
assert(not shares(own, c.TwichUIDB), "a copy, sharing nothing with the live settings")
assert(RS.OwnProblem(own) == nil)
assert(RS.Contents(point) == "1 addon and TwichUI's settings")
assert(RS.Size(point) > ST.SizeOf(point.tables), "its size counts TwichUI's part")

---------------------------------------------------------------------------
-- Restoring: queued, then put back at the start of the next load, with an Undo copy
---------------------------------------------------------------------------
db.ui.backupTest = "after"
db.shareTransport = "GUILD"
db.setup.trusted["Pal-Forever"] = nil
db.pins.list[2] = { id = "p2", label = "made after the backup" }
c.FooDB.a = 2
c.reloaded = nil
local ok, note = RS:Restore(point.id)
assert(ok and note == nil and c.reloaded, "restore queued, UI reloads")
assert(c.TwichUIRestoreDB.applyOwn and c.TwichUIRestoreDB.applyOwn.id == point.id)
assert(db.ui.backupTest == "after", "nothing changes before the reload")

local c2 = Boot(Logout(c), true)
local db2 = c2.TwichUIDB
assert(db2.ui.backupTest == "before" and db2.modules.chronicle == false, "settings back")
assert(db2.shareTransport == "PARTY" and db2.setup.trusted["Pal-Forever"] == true)
assert(#db2.pins.list == 2 and db2.pins.list[2].id == "p2", "map pins made since stay")
assert(db2.setup.received.Pal, "received setups stay")
assert(c2.FooDB.a == 1, "the addon settings were restored too")
assert(c2.TwichUIRestoreDB.applyOwn == nil, "the job runs once")
assert(heard(c2, "restored from backup \"snap\""), "said so")
assert(not heard(c2, "could not read"), "a first apply loses nothing")
local u = c2.TwichUI.Restore.OwnUndo()
assert(u and u.from == "snap" and u.own.keys.ui.backupTest == "after" and u.own.keys.shareTransport == "GUILD", "what it replaced is kept")
assert(db2.schema == c2.TwichUI.Persist.SCHEMA)

-- Undo puts back both parts: one restore made them
local a2, o2 = c2.TwichUI.Restore.UndoPlan()
assert(a2 and o2, "same change, both parts")
c2.reloaded = nil
assert(c2.TwichUI.Restore:UndoLast() and c2.reloaded)
local c3 = Boot(Logout(c2), true)
assert(c3.TwichUIDB.ui.backupTest == "after" and c3.TwichUIDB.shareTransport == "GUILD", "undo put TwichUI's settings back")
assert(c3.FooDB.a == 2, "and the addon's")
assert(heard(c3, "put back TwichUI's own settings"))
assert(not heard(c3, "could not read"), "an undo is not reported as lost")
assert(#c3.TwichUIDB.pins.list == 2)

-- A later addon apply makes it the last change: Undo then leaves TwichUI's settings alone
c3.TwichUIBackupDB[c3.TwichUI.Setups.CharKey()].created = c3.TwichUI.Restore.OwnUndo().created + 10
c3.TwichUIBackupDB[c3.TwichUI.Setups.CharKey()].stamp = 999
local a3, o3 = c3.TwichUI.Restore.UndoPlan()
assert(a3 and not o3, "only the later change")

---------------------------------------------------------------------------
-- A backup of TwichUI's settings alone needs no scan and no reload
---------------------------------------------------------------------------
local solo = Boot({ TwichUIDB = { ui = { backupTest = "solo" } } }, false)
local SRS = solo.TwichUI.Restore
assert(not SRS.NeedsReload())
solo.reloaded = nil
local st, sp = SRS:Create("only mine")
assert(st == "created" and not solo.reloaded and next(sp.tables) == nil and sp.own.keys.ui.backupTest == "solo")
assert(SRS.Contents(sp) == "TwichUI's settings")
solo.TwichUIDB.ui.backupTest = "changed"
assert(SRS:Restore(sp.id) and solo.reloaded, "restores with a plain reload")
local solo2 = Boot(Logout(solo), false)
assert(solo2.TwichUIDB.ui.backupTest == "solo")
assert(solo2.TwichUIDB.setup.pending == nil, "no addon apply was queued")
-- no addon Undo copy: Undo is TwichUI's settings alone
local sa, so = solo2.TwichUI.Restore.UndoPlan()
assert(not sa and so)

---------------------------------------------------------------------------
-- Export and import: format 2 carries it; format 1 still reads
---------------------------------------------------------------------------
local function run(fn, ...)
  local out
  fn(..., function(v) out = { true, v } end, function(m) out = { false, m } end)
  for _ = 1, 20000 do if out then break end FlushTimers() end
  assert(out, "job finished")
  return out[1], out[2]
end
local SP = solo2.TwichUI.Portable
local SR = solo2.TwichUI.Restore
local spoint = SR.List()[1]
local okE, str = run(SP.Export, spoint)
assert(okE and str:find("^TUIBK2:"), "format 2")
local okC, r = run(SP.Check, str)
assert(okC and r.blocked and r.duplicate == "only mine", "an identical backup is spotted")
SR:Delete(spoint.id)
okC, r = run(SP.Check, str)
assert(okC and not r.blocked and r.own and r.count == 0, "TwichUI's settings alone import")
local imp = assert(SP.Commit(r))
assert(imp.own.keys.ui.backupTest == "solo" and SR.OwnProblem(imp.own) == nil)

local LibSerialize, LibDeflate = solo2.LibStub("LibSerialize"), solo2.LibStub("LibDeflate")
local function pack(env, fmt)
  local ser = LibSerialize:Serialize(env)
  local enc = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(ser))
  local payload = #enc .. ":" .. enc
  return ("TUIBK%d:%d:%s:%d:%s"):format(fmt, #ser, LibDeflate:Adler32(ser), #payload, payload)
end
local function good()
  return { fmt = 2, point = { name = "x", created = 1, tables = {},
    own = { schema = 2, made = 1, keys = { ui = { k = 1 }, modules = { chronicle = true }, shareTransport = "DIRECT" } } } }
end
local function reject(label, e, fmt, pattern)
  local okR, msg = run(SP.Check, pack(e, fmt or 2))
  assert(not okR and (not pattern or msg:find(pattern, 1, true)), label .. ": " .. tostring(msg))
end
okC, r = run(SP.Check, pack(good(), 2)); assert(okC and r.own, tostring(r))
local e = good(); e.point.own.keys.pins = { list = {} }; reject("a left-out key", e, 2, "newer version")
e = good(); e.point.own.keys.modules = "on"; reject("wrong kind", e, 2, "damaged")
e = good(); e.point.own.schema = 99; reject("newer schema", e, 2, "newer version")
e = good(); e.point.own.extra = 1; reject("unknown field", e, 2, "newer version")
e = good(); e.point.own.keys.setup = { pending = {} }; reject("a sharing record", e, 2, "newer version")
e = good(); e.point.own.keys.ui = { f = string.rep("x", SP.LIMITS.string + 1) }; reject("too long", e, 2)   -- one oversize piece: refused before the string limit is reached
e = good(); e.fmt = 1; reject("own in format 1", e, 1, "newer version")
e = good(); e.fmt = 1; e.point.own = nil; e.point.tables = { FooDB = { owner = "Foo", data = { a = 1 } } }
okC, r = run(SP.Check, pack(e, 1)); assert(okC and not r.own, "a format 1 backup still imports")
e = good(); e.point.own = nil; reject("nothing in it", e, 2, "empty")

---------------------------------------------------------------------------
-- Refusals change nothing of TwichUI's settings
---------------------------------------------------------------------------
-- a part a newer TwichUI wrote is kept, never restored
local sv = Logout(solo2)
local newer = copy(sv.TwichUIRestoreDB.points[1])
newer.id = "newer-one"; newer.own.schema = 99
table.insert(sv.TwichUIRestoreDB.points, newer)
local n1 = Boot(sv, false)
assert(n1.TwichUI.Restore.Get("newer-one").own, "kept at load")
local okN, whyN = n1.TwichUI.Restore:Restore("newer-one")
assert(not okN and whyN:find("newer TwichUI", 1, true), tostring(whyN))
-- and if one is queued anyway, the load refuses it whole
local sv2 = Logout(n1)
sv2.TwichUIDB.ui.backupTest = "untouched"
sv2.TwichUIRestoreDB.applyOwn = { id = "newer-one", at = 1 }
local n2 = Boot(sv2, false)
assert(n2.TwichUIDB.ui.backupTest == "untouched" and heard(n2, "were not restored"), "refused, said so")
assert(n2.TwichUIRestoreDB.applyOwn == nil)
-- current settings from a newer TwichUI are never replaced
local sv3 = Logout(n2)
sv3.TwichUIDB.schema = 99; sv3.TwichUIDB.ui.backupTest = "from the future"
sv3.TwichUIRestoreDB.applyOwn = { id = imp.id, at = 1 }
local n3 = Boot(sv3, false)
local sv4 = Logout(n3)
assert(sv4.TwichUIDB.schema == 99 and sv4.TwichUIDB.ui.backupTest == "from the future", "a newer save is handed back unchanged")
assert(heard(n3, "were not restored"))
-- an unreadable queued job is dropped at load
local sv5 = Logout(Boot({ TwichUIDB = {} }, false))
sv5.TwichUIRestoreDB.applyOwn = "junk"
local n5 = Boot(sv5, false)
assert(n5.TwichUIRestoreDB.applyOwn == nil)
-- a damaged part is dropped at load, the backup kept
local sv6 = Logout(n5)
sv6.TwichUIRestoreDB.points = { { id = "d", name = "damaged", created = 1, tables = {}, own = "x" } }
local n6 = Boot(sv6, false)
assert(n6.TwichUI.Restore.Get("d") and n6.TwichUI.Restore.Get("d").own == nil)

print("BACKUP OWN TESTS PASSED")
