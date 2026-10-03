dofile(TESTS .. "harness.lua")
local me = MakeClient("Twich", {"!!!TwichUI","Foo","Bar"})
CLIENTS.Twich = me
me.TwichUIDB = {setup = {scanNext = true}}
me.LOADED["!!!TwichUI"]=true; me.FireEvent("ADDON_LOADED","!!!TwichUI")
local big = {}
for i = 1, 4000 do big["k" .. i] = { i, "value " .. i, i % 2 == 0, { x = i * 1.5 } } end
me.FooDB = { a = 1, nested = { b = { c = "deep" } }, big = big, [false] = "boolkey" }
me.BarDB = { z = "é" }
me.LOADED.Foo = true; me.FireEvent("ADDON_LOADED","Foo")
me.LOADED.Bar = true; me.FireEvent("ADDON_LOADED","Bar")
me.FireEvent("PLAYER_LOGIN")
local ST, RS, P = me.TwichUI.Setups, me.TwichUI.Restore, me.TwichUI.Portable
local status, point = RS:Create("before tweak")
assert(status == "created" and point, "backup created")

local function run(fn, ...)
  local out
  fn(..., function(v) out = { true, v } end, function(m) out = { false, m } end)
  for _ = 1, 20000 do if out then break end FlushTimers() end
  assert(out, "job finished")
  return out[1], out[2]
end
local function export(p) local ok, s = run(P.Export, p); assert(ok, s); return s end
local function check(s) return run(P.Check, s) end
local function snapshot()
  local s = me.TwichUI.Setups
  return ST.Hash({ rs = me.TwichUIRestoreDB, db = me.TwichUIDB, sh = me.TwichUIShareDB, bk = me.TwichUIBackupDB,
                   foo = me.FooDB, bar = me.BarDB, pending = me.TwichUIDB.setup and me.TwichUIDB.setup.pending })
end

-- Round trip
local str = export(point)
print("export length", #str, "bytes", ST.SizeOf(point.tables))
assert(str:find("^TUIBK1:%d+:%d+:%d+:"), "header")
assert(not str:find("[^%w%(%):]"), "printable only")
local before = snapshot()
local ok, r = check(str)
assert(ok, r)
assert(snapshot() == before, "check changes nothing")
assert(r.count >= 1 and r.addons == ST.CountAddons(point) and r.duplicate == "before tweak", "dup of stored original? " .. tostring(r.duplicate))
assert(r.blocked, "repeat of an existing backup is blocked")
assert(snapshot() == before, "blocked check changes nothing")

-- remove the original, then import: not a duplicate any more
local origHash = ST.Hash(point.tables)
local saved = point
RS:Delete(point.id)
ok, r = check(str); assert(ok, r); assert(not r.blocked and not r.duplicate)
assert(#RS.List() == 0)
local activeBefore = ST.Hash({ me.FooDB, me.BarDB })
local pend = me.TwichUIDB.setup.pending
local imported = assert(P.Commit(r))
assert(#RS.List() == 1 and RS.List()[1].id == imported.id)
assert(ST.Hash(imported.tables) == origHash, "full payload round trips")
assert(imported.name == "before tweak" and imported.created == saved.created and imported.source == saved.source)
assert(ST.Hash({ me.FooDB, me.BarDB }) == activeBefore, "active settings untouched")
assert(me.TwichUIDB.setup.pending == pend and not me.reloaded, "import neither applies nor queues anything")
-- repeat is now a duplicate
ok, r = check(str); assert(ok and r.blocked and r.duplicate == "before tweak")
assert(not P.Commit(r), "blocked import refuses")
assert(#RS.List() == 1)

-- name collision gets a safe name
RS:Delete(imported.id)
local keep = RS.AddImported({ name = "before tweak", created = 1, tables = { FooDB = { owner = "Foo", data = { a = 1 } } } })
ok, r = check(str); assert(ok and not r.blocked)
local second = assert(P.Commit(r))
assert(second.name == "before tweak (imported)" and second.id ~= keep.id)
assert(#RS.List() == 2)
RS:Delete(second.id); RS:Delete(keep.id)

-- Rejections change nothing
local function reject(label, s, pattern)
  local b = snapshot()
  local ok2, msg = check(s)
  assert(not ok2, label .. " should be rejected")
  assert(pattern == nil or msg:find(pattern), label .. ": " .. tostring(msg))
  assert(snapshot() == b and #RS.List() == 0, label .. " changed saved data")
  print("rejected", label, "->", msg)
end
reject("empty", "")
reject("nil-ish", "   \n ", "Paste")
reject("garbage", "hello world", "isn't a TwichUI backup")
reject("truncated", str:sub(1, #str - 40), "incomplete")
reject("truncated header", str:sub(1, 20))
reject("wrong version", str:gsub("^TUIBK1", "TUIBK2"), "format 2")
reject("version 0", str:gsub("^TUIBK1", "TUIBK0"), "format 0")
local flipped = str:sub(1, #str - 60) .. (str:sub(#str - 59, #str - 59) == "A" and "B" or "A") .. str:sub(#str - 58)
reject("corrupted", flipped)
reject("oversize", string.rep("A", P.LIMITS.input + 1), "too large")
reject("declared too big", ("TUIBK1:%d:1:0:"):format(P.LIMITS.raw + 1), "larger")
-- whitespace and line wrapping from a text file are fine
local wrapped = str:gsub("(" .. string.rep(".", 100) .. ")", "%1\r\n  ")
ok, r = check(wrapped); assert(ok, r)

-- Crafted but well-formed payloads (valid checksums) with bad content
local LibSerialize, LibDeflate = me.LibStub("LibSerialize"), me.LibStub("LibDeflate")
local function pack(env)
  local ser = LibSerialize:Serialize(env)
  local parts = {}
  for pos = 1, #ser, 16384 do
    local enc = LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(ser:sub(pos, pos + 16383)))
    parts[#parts + 1] = #enc .. ":" .. enc
  end
  local payload = table.concat(parts)
  return ("TUIBK1:%d:%s:%d:%s"):format(#ser, LibDeflate:Adler32(ser), #payload, payload)
end
local good = function() return { fmt = 1, addon = "3.0.7", point = { name = "x", created = 1, tables = { FooDB = { owner = "Foo", data = { a = 1 } } } } } end
ok, r = check(pack(good())); assert(ok, r)
local e = good(); e.point.tables.TwichUIDB = { owner = "TwichUI", data = {} }
reject("TwichUI table", pack(e), "TwichUI's own data")
e = good(); e.fmt = 7; reject("env fmt", pack(e), "format 7")
e = good(); e.extra = 1; reject("unknown field", pack(e), "newer version")
e = good(); e.point.extra = 1; reject("unknown point field", pack(e), "newer version")
e = good(); e.point.tables.FooDB.extra = 1; reject("unknown entry field", pack(e), "damaged")
e = good(); e.point.tables = {}; reject("empty", pack(e), "empty")
e = good(); e.point.tables["bad name"] = { owner = "Foo", data = {} }; reject("bad ident", pack(e), "damaged")
e = good(); e.point.tables.FooDB.data = "string"; reject("data type", pack(e), "damaged")
e = good(); e.point.name = 5; reject("name type", pack(e), "damaged")
e = good(); local deep = e.point.tables.FooDB.data; for _ = 1, 70 do deep.n = {}; deep = deep.n end
reject("too deep", pack(e), "deeply")
e = good(); local cyc = e.point.tables.FooDB.data; cyc.self = cyc
reject("cycle", pack(LibSerialize and (function() return e end)()), nil)
e = good(); e.point.tables.FooDB.data = { [{}] = 1 }; reject("table key", pack(e))
e = good(); e.point.tables.FooDB.data = { s = string.rep("x", P.LIMITS.string + 1) }; reject("long string", pack(e), "larger")
e = good(); for i = 1, P.LIMITS.tables + 1 do e.point.tables["T" .. i] = { owner = "Foo", data = {} } end
reject("too many tables", pack(e), "more settings tables")

-- Missing addons and tables that can't apply here are reported, data kept
me.C_AddOns.DoesAddOnExist = function(n) return n ~= "Gone" end
e = good(); e.point.tables.GoneDB = { owner = "Gone", data = { q = 1 } }
e.point.name = "pipe|cFFFF0000red\n" .. string.rep("é", 80)
ok, r = check(pack(e)); assert(ok, r)
assert(#r.missing == 1 and r.count == 2, "missing addon reported")
assert(not r.point.name:find("[|%c]") and #r.point.name <= 100 and not r.point.name:find("[\192-\255]$"), "name cleaned")
local p2 = assert(P.Commit(r))
assert(p2.tables.GoneDB.data.q == 1, "unavailable addon's data kept")
RS:Delete(p2.id)

-- Caps apply to imports only
for i = 1, P.MAX_POINTS do RS.AddImported({ name = "n" .. i, created = i, tables = { FooDB = { owner = "Foo", data = { v = i } } } }) end
ok, r = check(str); assert(ok and r.blocked and r.blocked:find("most an import"), tostring(r.blocked))
assert(not P.Commit(r) and #RS.List() == P.MAX_POINTS)

-- Cancel leaves everything alone
local b = snapshot()
local got
P.Check(str, function() got = true end, function() got = true end)
P.Cancel(); for _ = 1, 50 do FlushTimers() end
assert(not got and not P.Busy() and snapshot() == b, "cancel")
P.Export(RS.List()[1], function() got = true end); P.Cancel(); for _ = 1, 50 do FlushTimers() end
assert(not got and snapshot() == b)
print("PORTABLE TESTS PASSED")
