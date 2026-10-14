-- Saved Data Explorer, advanced cleanup (setup/Cleanup.lua and the explorer window's controls):
-- read-only by default and after closing; an explicit, acknowledged activation; what is protected and why;
-- targets resolved by key with their types; subtree removal through each module's own function; stale
-- reviews and changed targets removing nothing; all-or-nothing checking and honest partial results; bounded
-- recovery; candidate rules and what they will not claim; counting and scanning that are sliced and
-- cancellable; nothing of any of it saved. All data here is made up.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local a = MakeClient("Alpha", {"!!!TwichUI", "Foo"})
CLIENTS.Alpha = a

local function Obj()
  local o = {text = "", checked = false, shown = true}
  return setmetatable(o, {__index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    -- as the game: SetText takes text (or a number), never a function or table
    if k == "SetText" then return function(s, v)
      if v ~= nil and type(v) ~= "string" and type(v) ~= "number" then error("bad argument #1 to 'SetText' (got " .. type(v) .. ")", 2) end
      s.text = v or ""
    end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) local was = s.shown; s.shown = true
      if not was and s.scripts and s.scripts.OnShow then s.scripts.OnShow(s) end end end
    if k == "Hide" then return function(s) local was = s.shown; s.shown = false
      if was and s.scripts and s.scripts.OnHide then s.scripts.OnHide(s) end end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "HasFocus" then return function() return false end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end})
end
local realCreate = a.CreateFrame
a.CreateFrame = function(kind, name, parent, template)
  local o = Obj()
  for k, v in pairs(realCreate()) do rawset(o, k, v) end
  rawset(o, "Show", nil); rawset(o, "Hide", nil); rawset(o, "IsShown", nil)
  if template == "WowScrollBoxList" then
    rawset(o, "SetDataProvider", function(self, dp)
      self.list = {}
      for i, d in ipairs(dp.rows) do
        local row = a.CreateFrame("Button")
        self.view.init(row, d)
        self.list[i] = row
      end
    end)
  end
  if name then a[name] = o end
  return o
end
a.CreateScrollBoxListLinearView = function()
  return {SetElementExtent = function() end, SetElementInitializer = function(self, _, fn) self.init = fn end}
end
a.ScrollUtil = {InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end}
a.CreateDataProvider = function(rows) return {rows = rows} end
a.UIParent, a.UISpecialFrames, a.tinsert = Obj(), {}, table.insert
a.GameTooltip = Obj(); a.GameTooltip_Hide = function() end
a.C_Map = {GetMapInfo = function(id) return {mapID = id, name = "Map " .. id} end}
-- A clock that moves 5 ms at every reading, so the 4 ms slice budget lets exactly one step run per frame:
-- counting and scanning are visibly sliced, and can be cancelled between frames.
local clockMs = 0
a.debugprofilestop = function() clockMs = clockMs + 5; return clockMs end
for _, f in ipairs({"setup/StoredData.lua", "setup/Explorer.lua", "setup/Cleanup.lua", "chronicle/Style.lua", "Look.lua",
    "setup/ExplorerWindow.lua", "pins/Pins.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, a); chunk("!!!TwichUI", {})
end

-- Saved data before login. The Undo copy of "Void" holds nothing; "Alt" and the current character have settings.
a.TwichUIDB = {setup = {scanNext = true}}
a.TwichUIChronicleDB = {version = 1, chars = {
  ["Alpha - Forever"] = {nextId = 2, tracking = true,
    entries = {{id = 1, t = 1700000000, kind = "note", title = "Camp", note = "dear diary"}}},
  ["Alt - Forever"] = {nextId = 3, tracking = true, entries = {
    {id = 1, t = 1700000100, kind = "note", title = "Inn", note = "my own words"},
    {id = 2, t = 1700000200, kind = "zone", title = "Elwynn Forest"}}},
  ["Empty - Forever"] = {nextId = 1, tracking = false, entries = {}},
}}
a.TwichUIBackupDB = {
  ["Alt - Forever"] = {created = 1700000300, tables = {FooDB = {present = true, data = {x = 1}}}},
  ["Alpha - Forever"] = {created = 1700000400, tables = {FooDB = {present = true, data = {x = 2}}}},
  ["Void - Forever"] = {created = 1700000500, tables = {}},
}
a.LOADED["!!!TwichUI"] = true; a.FireEvent("ADDON_LOADED", "!!!TwichUI")
a.FooDB = {profiles = {Default = {enabled = false, scale = 1}}}
a.LOADED.Foo = true; a.FireEvent("ADDON_LOADED", "Foo"); a.FireEvent("PLAYER_LOGIN")
TIMERS = {}
a.C_AddOns.DoesAddOnExist = function(n) return n ~= "GoneAddon" end

local R = a.TwichUI
local EX, CL, ST, RS, PF, PN, C, SD = R.Explorer, R.Cleanup, R.Setups, R.Restore, R.Profiles, R.Pins, R.Chronicle, R.StoredData
local XW = R.ExplorerWindow
assert(EX and CL and XW, "the cleanup module loaded")
assert(PF.Available(), "profiles are available")
assert(ST.capture and ST.capture.FooDB, "the scan found Foo's settings")
assert(ST:SaveMine(false) == 1)
local status, point = RS:Create("Before raid")
assert(status == "created" and point)
point.created = 1000000000      -- years old, and restorable: age alone must never flag it

-- A table that fails loudly if any metamethod runs.
local function boom(what) return function() error("metatable code ran: " .. what) end end
local trap = setmetatable({inside = 1}, {__index = boom("__index"), __newindex = boom("__newindex"),
  __tostring = boom("__tostring"), __call = boom("__call"), __eq = boom("__eq"), __len = boom("__len"),
  __metatable = "locked"})

local db = a.TwichUIDB
db.profiles.Raid = {modules = {}, ui = {}, gear = {}}
db.profiles.Spare = {modules = {welcome = false}, ui = {scale = 1.2, nested = {deep = {x = 1}}}, gear = {}}
db.profileKeys["Alt - Forever"] = "Raid"
db.profileKeys["Gone - Forever"] = "Missing"
db.whisperProbe = {build = "12345", ok = true, at = 1700000600}
db.migrated = 301
db.storedData.found.OldVar = {owner = "GoneAddon", seen = 1700000700}
db.storedData.found.KeepVar = {owner = "Foo", seen = 1700000800}
db.setup.trusted.Pal = true
db.setup.received.Pal = {created = 1, received = 1700000900, sourceName = "Pal", version = 1,
  tables = {FooDB = {owner = "Foo", data = {x = 1, marker = "RECOVERY_MARKER_PAL"}}}}
db.setup.received.Hollow = {received = 1700001000, sourceName = "Hollow", version = 1, tables = {}}
table.insert(a.TwichUIRestoreDB.points, {id = "empty1", name = "Empty one", created = 1700001100, tables = {}})
db.pins = {nextId = 5, list = {
  {id = "L1", map = 1429, x = 100, y = 200, name = "Camp", color = "gold", created = 1700001200},
  {id = "L2", map = 1429, x = 300, y = 400, name = "Keeper", color = "gold", created = 1700001300, kept = true},
  {id = "L3", map = 1429, x = 500, y = 600, name = "Other", color = "gold", created = 1700001400},
  {id = "L4", bogus = true},
}}
db.oddities = {fn = function() end, trap = trap, [1] = "number one", ["1"] = "text one"}

local VARS = {"TwichUIDB", "TwichUIBackupDB", "TwichUIShareDB", "TwichUIRestoreDB", "TwichUIChronicleDB"}
local function Fingerprint()
  local out, seen, ids = {}, {}, 0
  local function W(v)
    local t = type(v)
    if t ~= "table" then out[#out + 1] = t .. ":" .. ((t == "string" or t == "number" or t == "boolean") and tostring(v) or "?") return end
    if seen[v] then out[#out + 1] = "ref" .. seen[v] return end
    ids = ids + 1; seen[v] = ids
    out[#out + 1] = "{" .. ids
    local keys = {}
    for k in next, v do keys[#keys + 1] = k end
    table.sort(keys, function(x, y)
      local tx, ty = type(x), type(y)
      if tx ~= ty then return tx < ty end
      if tx == "string" or tx == "number" then return x < y end
      return false
    end)
    for _, k in ipairs(keys) do W(k); W(rawget(v, k)) end
    out[#out + 1] = "}"
  end
  for _, name in ipairs(VARS) do out[#out + 1] = name; W(rawget(a, name)) end
  return table.concat(out, ",")
end

local function Pump(n) for _ = 1, n or 6 do FlushTimers() end end
-- Counts targets with the sliced job, as the window does.
local function Review(targets)
  local done
  CL.Count(targets, {}, function(ok) done = ok end)
  for _ = 1, 30 do Pump(1); if done ~= nil then break end end
  assert(done == true, "counting finished")
  CL.PlanRecovery(targets)
  return targets
end
local function Target(var, ...)
  local t, why = CL.NewTarget(var, {...})
  assert(t, "target " .. var .. ": " .. tostring(why))
  return t
end

---------------------------------------------------------------------------
-- 1. Read-only by default; activation needs the acknowledgment
---------------------------------------------------------------------------
local baseline = Fingerprint()
assert(CL.Enabled() == false, "off at start")
assert(CL.Enable() == false and CL.Enable(false) == false and CL.Enable("yes") == false and not CL.Enabled(),
  "only an explicit acknowledgment turns it on")
local rep = CL.Commit({Target("TwichUIDB", "profiles", "Spare")})
assert(rep.status == "blocked" and not rep.reason:find("nil"), "no removal while off")
assert(db.profiles.Spare, "nothing removed")
assert(CL.Pick("x", true) == false, "nothing can be picked while off")
XW.Show()
local f = a.TwichUISavedDataExplorer
assert(f and f.shown and not CL.Enabled(), "opening the explorer does not turn it on")
f.delete.scripts.OnClick(f.delete)
assert(not a.TwichUIExplorerCleanupDialog, "the delete control does nothing while off")
assert(f.chip.shown == false and f.advOn.shown == true and f.advOff.shown == false, "read-only controls")

-- The warning, then the acknowledgment, then the confirmation.
f.advOn.scripts.OnClick(f.advOn)
local d = a.TwichUIExplorerCleanupDialog
assert(d and d.shown and not CL.Enabled(), "the warning opens; nothing is on yet")
local text = d.body.edit.text
assert(text:find("can remove saved data and affect settings or features", 1, true)
  and text:find("not proof that data is unused", 1, true), "the warning's wording")
d.confirmPlain.scripts.OnClick(d.confirmPlain)
assert(not CL.Enabled(), "confirming without the acknowledgment does nothing")
d.scripts.OnKeyDown(d, "RETURN")
assert(not CL.Enabled() and d.shown, "no key confirms")
d.scripts.OnKeyDown(d, "ESCAPE")
assert(not d.shown and not CL.Enabled(), "Escape cancels the dialog only")
f.advOn.scripts.OnClick(f.advOn)
d.ack.scripts.OnClick(d.ack)
d.confirmPlain.scripts.OnClick(d.confirmPlain)
assert(CL.Enabled(), "acknowledged and confirmed")
assert(f.chip.shown == true and f.advLine.shown == true and f.advOff.shown == true and f.advOn.shown == false,
  "the indicator is persistent while on")
assert(Fingerprint() == baseline, "the mode itself saves nothing")

-- Back to read-only, and a reset on close.
f.advOff.scripts.OnClick(f.advOff)
assert(not CL.Enabled() and f.chip.shown == false, "an easy way back")
CL.Enable(true)
f:Hide()
assert(not CL.Enabled(), "closing ends it")
XW.Show()
assert(not CL.Enabled() and f.chip.shown == false, "and it is off when reopened")

---------------------------------------------------------------------------
-- 2. Policy: protected entries say why; allowed ones name the function that does it
---------------------------------------------------------------------------
local function Plan(var, ...)
  local keys = {...}
  local _, value = CL.Resolve(var, keys)
  return CL.Policy(var, keys, value)
end
local function Blocked(why, var, ...)
  local p = Plan(var, ...)
  assert(p.ok == false and type(p.reason) == "string" and #p.reason > 10, why .. ": should be protected")
  return p
end
Blocked("whole settings", "TwichUIDB")
for _, k in ipairs({"schema", "welcome", "profileState", "modules", "ui", "gear", "shareTransport", "profiles", "profileKeys", "pins", "setup", "storedData"}) do
  Blocked("required root " .. k, "TwichUIDB", k)
end
Blocked("a live setting", "TwichUIDB", "ui", "scale")
Blocked("the profile in use", "TwichUIDB", "profiles", "Default")
Blocked("a profile in use by another character", "TwichUIDB", "profiles", "Raid")
assert(Plan("TwichUIDB", "profiles", "Raid").reason:find("1 saved character choice", 1, true))
Blocked("inside a profile", "TwichUIDB", "profiles", "Spare", "ui")
assert(Plan("TwichUIDB", "profiles", "Spare").ok and Plan("TwichUIDB", "profiles", "Spare").via == "Profiles' own Delete")
Blocked("this character's own profile choice", "TwichUIDB", "profileKeys", "Alpha - Forever")
assert(Plan("TwichUIDB", "profileKeys", "Alt - Forever").ok)
Blocked("the pin counter", "TwichUIDB", "pins", "nextId")
Blocked("a kept pin", "TwichUIDB", "pins", "list", 2)
assert(Plan("TwichUIDB", "pins", "list", 2).reason:find("kept", 1, true))
Blocked("a pin TwichUI can't read", "TwichUIDB", "pins", "list", 4)
assert(Plan("TwichUIDB", "pins", "list", 1).ok and Plan("TwichUIDB", "pins", "list", 3).ok)
Blocked("a hand-off", "TwichUIDB", "setup", "scanNext")
Blocked("the container of received setups", "TwichUIDB", "setup", "received")
Blocked("inside a received setup", "TwichUIDB", "setup", "received", "Pal", "tables")
Blocked("an unknown top-level key", "TwichUIDB", "oddities")
Blocked("a whole saved variable", "TwichUIRestoreDB")
Blocked("the Chronicle's own record", "TwichUIChronicleDB", "chars", "Alpha - Forever")
Blocked("a Chronicle entry", "TwichUIChronicleDB", "chars", "Alt - Forever", "entries", 1)
assert(Plan("TwichUIChronicleDB", "chars", "Alt - Forever").ok)
assert(Plan("TwichUIChronicleDB", "chars", "Alt - Forever").consequences[1]:find("1 note", 1, true), "notes are named")
assert(Plan("TwichUIRestoreDB", "points", 1).ok and Plan("TwichUIBackupDB", "Alt - Forever").ok)
Blocked("inside a backup", "TwichUIRestoreDB", "points", 1, "tables")
-- Everything allowed says there is no reload to wait for.
for _, p in ipairs({Plan("TwichUIDB", "whisperProbe"), Plan("TwichUIDB", "migrated"), Plan("TwichUIDB", "setup", "trusted", "Pal"),
    Plan("TwichUIDB", "setup", "detected"), Plan("TwichUIDB", "storedData", "found", "OldVar"), Plan("TwichUIShareDB", "pack")}) do
  assert(p.ok and p.reload:find("No reload is needed", 1, true) and #p.consequences > 0, "allowed: " .. tostring(p.what))
end
-- A pending apply that uses a backup or a received setup protects it.
db.setup.pending = {mode = "apply", tables = {FooDB = true}, source = "recv:Pal", stamp = 0, char = "Alt - Forever"}
Blocked("a received setup queued to be applied", "TwichUIDB", "setup", "received", "Pal")
Blocked("an Undo copy a queued load needs", "TwichUIBackupDB", "Alt - Forever")
db.setup.pending = {mode = "apply", tables = {FooDB = true}, source = "restore:" .. point.id, stamp = 0, char = "Alpha - Forever"}
Blocked("a queued restore", "TwichUIRestoreDB", "points", 1)
db.setup.pending = nil
-- Data a newer TwichUI wrote is set aside for the session: nothing in it can be removed.
local P = R.Persist
local original = a.TwichUIBackupDB
P.Hold("TwichUIBackupDB", original, {})
original["Alt - Forever"] = original["Alt - Forever"]
local heldPlan = CL.Policy("TwichUIBackupDB", {"Alt - Forever"}, {})
assert(heldPlan.ok == false and heldPlan.reason:find("newer TwichUI", 1, true), "a set-aside variable is protected")
P.Release()
assert(a.TwichUIBackupDB == original)
-- A runtime-only source (the share preview) has nothing to delete.
local var, whyNot = CL.SourceAddress(EX.Source("share:preview"))
assert(var == nil and whyNot:find("isn't saved", 1, true))

---------------------------------------------------------------------------
-- 3. Paths are resolved by key, with types kept; metatable code never runs
---------------------------------------------------------------------------
local _, one = CL.Resolve("TwichUIDB", {"oddities", 1})
local _, text1 = CL.Resolve("TwichUIDB", {"oddities", "1"})
assert(one == "number one" and text1 == "text one", "[1] and [\"1\"] are different entries")
assert(CL.Resolve("TwichUIDB", {"oddities", "missing"}) == nil)
assert(CL.Resolve("TwichUIDB", {"oddities", "trap", "inside"}) ~= nil, "a table with a metatable is read raw")
local _, trapped = CL.Resolve("TwichUIDB", {"oddities", "trap"})
local fp = CL.Fingerprint(trapped)
assert(fp.values == 1, "counted without running its metamethods")
local keys = {}
local t = Target("TwichUIDB", "setup", "received", "Pal")
assert(t.keys[3] == "Pal" and t.var == "TwichUIDB" and t.value == db.setup.received.Pal)

---------------------------------------------------------------------------
-- 4. A removal: the subtree goes through its owner's function, and is checked first
---------------------------------------------------------------------------
CL.Enable(true)
local refreshed = 0
R.Window = {Refresh = function() refreshed = refreshed + 1 end}
local spare = db.profiles.Spare
local tSpare = Review({Target("TwichUIDB", "profiles", "Spare")})
assert(tSpare[1].print.values >= 6 and tSpare[1].print.tables >= 5 and not tSpare[1].print.cut, "the subtree is counted, nested tables too")
assert(tSpare[1].recoverable == true)
local before = Fingerprint()
local report = CL.Commit(tSpare)
assert(report.status == "done" and report.removed == 1 and report.undoable == 1, "removed")
assert(db.profiles.Spare == nil and db.profiles.Raid ~= nil)
assert(not PF.Exists("Spare") and PF.Exists("Raid"), "removed by Profiles' own delete; the others are untouched")
assert(CL.RecoveryInfo() and CL.RecoveryInfo().items == 1, "a bounded in-memory copy is kept")
-- The copy is a copy: it shares nothing with what was removed, and it is not in any saved variable.
assert(CL.recovery.items[1].copy ~= spare)
local undo = CL.Undo()
assert(undo.restored == 1 and #undo.failed == 0 and PF.Exists("Spare"), "undone")
assert(db.profiles.Spare.ui.nested.deep.x == 1 and db.profiles.Spare.ui.scale == 1.2, "with its contents")
assert(CL.RecoveryInfo() == nil, "the copy is used up")
assert(Fingerprint() == before, "the data is exactly as it was")

-- Undo puts nothing over something new.
local t2 = Review({Target("TwichUIDB", "profiles", "Spare")})
assert(CL.Commit(t2).status == "done")
db.profiles.Spare = {modules = {}, ui = {}, gear = {}}
local u2 = CL.Undo()
assert(u2.restored == 0 and #u2.failed == 1 and u2.failed[1].why:find("new", 1, true) and db.profiles.Spare.ui.scale == nil)
db.profiles.Spare = nil
assert(CL.RecoveryInfo(), "what could not be put back is kept to try again")
CL.DiscardRecovery()

---------------------------------------------------------------------------
-- 5. Changed targets and stale reviews remove nothing
---------------------------------------------------------------------------
db.profiles.Spare = {modules = {}, ui = {scale = 1.2}, gear = {}}
local function Stale(label, mutate, why)
  local ts = Review({Target("TwichUIDB", "profiles", "Spare")})
  mutate()
  local keep = db.profiles.Spare
  local r = CL.Commit(ts)
  assert(r.status == "changed" and r.removed == 0, label .. ": " .. tostring(r.status))
  if why then assert(r.reason:find(why, 1, true), label .. ": " .. tostring(r.reason)) end
  assert(db.profiles.Spare == keep and keep ~= nil, label .. ": still there")
end
Stale("replaced", function() db.profiles.Spare = {modules = {}, ui = {scale = 1.2}, gear = {}} end, "replaced")
Stale("changed inside", function() db.profiles.Spare.ui.scale = 1.3 end, "inside")
Stale("added inside", function() db.profiles.Spare.ui.extra = true end, "inside")
Stale("now in use", function() db.profileKeys["Alt - Forever"] = "Spare" end)
db.profileKeys["Alt - Forever"] = "Raid"
Stale("now the profile for new characters", function() db.profileState.newCharacters = "Spare" end)
db.profileState.newCharacters = "Default"
-- Switching the mode off between review and confirmation.
local late = Review({Target("TwichUIDB", "profiles", "Spare")})
CL.Disable()
assert(CL.Commit(late).status == "blocked" and db.profiles.Spare, "off: nothing removed")
CL.Enable(true)
-- A batch is all or nothing as to checking: one changed target stops all of them.
local pinA, recvB = Target("TwichUIDB", "pins", "list", 1), Target("TwichUIDB", "setup", "received", "Hollow")
Review({pinA, recvB})
db.setup.received.Hollow.version = 2
local rb = CL.Commit({pinA, recvB})
assert(rb.status == "changed" and PN.FindLocal("L1") and db.setup.received.Hollow, "nothing in the batch was removed")
db.setup.received.Hollow.version = 1

---------------------------------------------------------------------------
-- 6. Batches: overlap, partial failure, a removal that did not happen
---------------------------------------------------------------------------
local parent = {var = "V", keys = {"a"}, plan = {ok = true}}
local child = {var = "V", keys = {"a", "b"}, plan = {ok = true}}
local same1 = {var = "V", keys = {"s1"}, plan = {ok = true, opKey = "search"}}
local same2 = {var = "V", keys = {"s2"}, plan = {ok = true, opKey = "search"}}
local kept, covered = CL.Normalize({child, same1, parent, same2})
assert(#kept == 2 and #covered == 2, "a child and a repeated operation are not removed twice")
local det, sel = Target("TwichUIDB", "setup", "detected"), Target("TwichUIDB", "setup", "selection")
assert(det.plan.opKey == "search" and sel.plan.opKey == "search")
local nk = CL.Normalize({det, sel})
assert(#nk == 1, "the two lists of the last search are one operation")

local p1, p3 = Target("TwichUIDB", "pins", "list", 1), Target("TwichUIDB", "pins", "list", 3)
local rcv = Target("TwichUIDB", "setup", "received", "Hollow")
Review({p1, p3, rcv})
local realRemove = PN.RemoveLocal
PN.RemoveLocal = function(id) if id == "L3" then return false, "gone" end return realRemove(id) end
local part = CL.Commit({p1, p3, rcv})
PN.RemoveLocal = realRemove
assert(part.status == "partial" and part.removed == 2 and part.failed == 1, "an honest partial: " .. part.status)
assert(PN.FindLocal("L3") and not PN.FindLocal("L1") and db.setup.received.Hollow == nil)
local failedRes
for _, r in ipairs(part.results) do if not r.ok then failedRes = r end end
assert(failedRes and failedRes.why and failedRes.target == p3)
-- A function that says yes and removes nothing is not reported as a success.
local t4 = Review({Target("TwichUIDB", "setup", "received", "Pal")})
local realDelete = ST.RemoveReceived
ST.RemoveReceived = function() return true end
local lie = CL.Commit(t4)
ST.RemoveReceived = realDelete
assert(lie.status == "failed" and lie.removed == 0 and db.setup.received.Pal, "still there, so not a success")
assert(lie.results[1].why:find("still there", 1, true))
CL.DiscardRecovery()

---------------------------------------------------------------------------
-- 7. Recovery is bounded; what can't be put back is said so
---------------------------------------------------------------------------
local big = {}
for i = 1, 60000 do big[i] = i end
db.setup.received.Big = {received = 1, version = 1, tables = {FooDB = {owner = "Foo", data = big}}}
local tb = Review({Target("TwichUIDB", "setup", "received", "Big")})
assert(tb[1].print.values > CL.RECOVERY_VALUES and tb[1].recoverable == false, "too large to keep a copy of")
local rbig = CL.Commit(tb)
assert(rbig.status == "done" and rbig.undoable == 0 and CL.RecoveryInfo() == nil and db.setup.received.Big == nil,
  "removed, and nothing was copied")
-- Past the walk's bound the count says "at least" and nothing is kept.
local huge = {}
for i = 1, CL.DIGEST_VISITS + 50 do huge[i] = true end
db.setup.received.Huge = {received = 1, version = 1, tables = {FooDB = {owner = "Foo", data = huge}}}
local th = Review({Target("TwichUIDB", "setup", "received", "Huge")})
assert(th[1].print.cut == true and th[1].recoverable == false)
db.setup.received.Huge = nil

---------------------------------------------------------------------------
-- 8. After a removal: the views that list it follow, and only what is related
---------------------------------------------------------------------------
refreshed = 0
local foundNoted = 0
SD.OnChange(function() foundNoted = foundNoted + 1 end)
local tsd = Review({Target("TwichUIDB", "storedData", "found", "OldVar"), Target("TwichUIDB", "whisperProbe")})
local rsd = CL.Commit(tsd)
assert(rsd.status == "done" and SD.Found("OldVar") == nil and SD.Found("KeepVar") and db.whisperProbe == nil)
assert(foundNoted > 0, "Addon data hears that a note was forgotten")
local trs = Review({Target("TwichUIDB", "setup", "trusted", "Pal")})
assert(CL.Commit(trs).status == "done" and db.setup.trusted.Pal == nil and refreshed > 0, "the sharing window was asked to redraw")
assert(CL.Undo().restored >= 1 and db.setup.trusted.Pal == true, "a raw removal can be put back")
local tch = Review({Target("TwichUIChronicleDB", "chars", "Alt - Forever")})
assert(CL.Commit(tch).status == "done" and a.TwichUIChronicleDB.chars["Alt - Forever"] == nil)
assert(a.TwichUIChronicleDB.chars["Alpha - Forever"], "this character's record is untouched")
assert(CL.Undo().restored == 1 and a.TwichUIChronicleDB.chars["Alt - Forever"].entries[1].note == "my own words", "the notes come back with it")
-- A removed profile choice puts the character on the new-character profile; its profile stays.
local tpk = Review({Target("TwichUIDB", "profileKeys", "Alt - Forever")})
assert(CL.Commit(tpk).status == "done" and db.profileKeys["Alt - Forever"] == nil and db.profiles.Raid)
CL.Undo()
assert(db.profileKeys["Alt - Forever"] == "Raid")
-- This character's choice and record are refused by their owners as well, not only by the policy.
assert(PF.Forget("Alpha - Forever") == false and C.Forget("Alpha - Forever") == false)
assert(PN.RemoveLocal("L2") == false, "the pin code itself still refuses a kept pin")
CL.DiscardRecovery()

---------------------------------------------------------------------------
-- 9. Candidates: what the data shows, how sure, and what is never claimed
---------------------------------------------------------------------------
-- (what earlier sections removed on purpose is put back, so every rule has something to find)
db.setup.received.Hollow = {received = 1700001000, sourceName = "Hollow", version = 1, tables = {}}
db.whisperProbe = {build = "12345", ok = true, at = 1700000600}
db.storedData.found.OldVar = {owner = "GoneAddon", seen = 1700000700}
local pre = Fingerprint()
local scanned
CL.Scan({}, function(res) scanned = res end)
assert(scanned == nil, "a scan is sliced: it does not finish inside the call")
for _ = 1, 40 do Pump(1); if scanned then break end end
assert(scanned and CL.results == scanned, "the scan finished")
assert(Fingerprint() == pre, "finding candidates changed nothing")
assert(CL.Enabled(), "and left the mode as it was")
local byId = {}
for _, c in ipairs(scanned.list) do byId[c.id] = c end
local function Want(id, tier)
  local c = byId[id]
  assert(c, "expected a suggestion: " .. id)
  assert(c.tier == tier, id .. " is " .. c.tier .. ", expected " .. tier)
  assert(type(c.reason) == "string" and #c.reason > 0 and type(c.evidence) == "string" and #c.evidence > 0, id .. " explains itself")
  assert(c.inspect and c.inspect.source and #c.targets > 0)
  return c
end
Want("restore-empty:empty1", "strong")
Want("undo-empty:Void - Forever", "strong")
Want("received-empty:Hollow", "strong")
Want("choice:Gone - Forever", "strong")
Want("chronicle-fresh:Empty - Forever", "strong")
Want("probe", "strong")
Want("migrated", "strong")
Want("profile:Spare", "possible")
Want("found:GoneAddon", "possible")
Want("search", "possible")
Want("undo-other:Alt - Forever", "info")
Want("chronicle-other:Alt - Forever", "info")
-- Not flagged: restorable but ancient, in use, current, or this game's own data.
assert(not byId["restore-empty:" .. point.id], "an old restorable backup is not flagged for its age")
assert(not byId["profile:Raid"] and not byId["profile:Default"], "a profile in use is not flagged")
assert(not byId["undo-other:Alpha - Forever"] and not byId["chronicle-other:Alpha - Forever"], "this character is never a suggestion")
assert(not byId["found:Foo"], "an installed addon's notes are not flagged")
for id, c in pairs(byId) do
  assert(not (c.title .. c.reason .. c.evidence):lower():find("safe to delete", 1, true), id .. " never says safe to delete")
  if c.tier == "info" then assert(c.uncertainty ~= "", id .. " says what is not known") end
end
assert(byId["probe"].date.label == "Checked" and byId["probe"].date.t == 1700000600)
assert(byId["chronicle-fresh:Empty - Forever"].date == nil, "no date is invented")
assert(byId["chronicle-other:Alt - Forever"].date.t == 1700000200, "the latest entry's time")
assert(byId["profile:Spare"].date == nil and byId["profile:Spare"].uncertainty:find("no dates", 1, true), "profiles have no dates, and it says so")
assert(#scanned.checked == #CL.RULES and #CL.NOT_DETECTED > 3, "an empty result can say what was checked and what can't be told")
-- Nothing is picked until it is picked, and only while the mode is on.
assert(next(CL.picks) == nil and #CL.PickedCandidates() == 0)
CL.Pick("probe", true)
assert(#CL.PickedCandidates() == 1)
CL.Disable()
assert(next(CL.picks) == nil, "picks end with the mode")
CL.Enable(true)
-- A candidate's target goes through the same review.
local picked = {byId["probe"], byId["migrated"]}
local tc = Review(CL.TargetsFor(picked))
assert(#tc == 2 and tc[1].candidate)
assert(CL.Commit(tc).status == "done" and db.whisperProbe == nil and db.migrated == nil)
CL.DiscardRecovery()

-- A suggested backup is found again by its id: removing an earlier backup moves it up a place, and the
-- position the scan saw must never name another backup.
do
  local before1 = #a.TwichUIRestoreDB.points
  table.insert(a.TwichUIRestoreDB.points, 1, {id = "front", name = "Front", created = 1, tables = {FooDB = {owner = "Foo", data = {x = 1}}}})
  local idx
  for i, p in ipairs(a.TwichUIRestoreDB.points) do if p.id == "empty1" then idx = i end end
  local cand = {id = "restore-empty:empty1", targets = {{var = "TwichUIRestoreDB", keys = {"points", idx}, byId = "empty1"}}}
  table.remove(a.TwichUIRestoreDB.points, 1)       -- everything moves up one
  local found = CL.TargetsFor({cand})
  assert(#found == 1 and found[1].value.id == "empty1", "found by id, not by the old position")
  assert(CL.CandidateGone(cand) == false)
  RS:Delete("empty1")
  assert(CL.CandidateGone(cand) == true and #CL.TargetsFor({cand}) == 0, "gone is gone, and nothing else takes its place")
  assert(#a.TwichUIRestoreDB.points == before1 - 1)
end

---------------------------------------------------------------------------
-- 10. Scans are bounded: cancelled when asked and when the window closes
---------------------------------------------------------------------------
for i = 1, 400 do table.insert(a.TwichUIRestoreDB.points, {id = "x" .. i, name = "N" .. i, created = 1, tables = {}}) end
local finished, frames = false, 0
CL.Scan({}, function() finished = true end)
local function Frame() for fr, fn in pairs(UPDATERS) do fn(fr, 0.016) end frames = frames + 1 end
Frame()
assert(finished == false and EX.Busy("cleanup-scan"), "one frame does not finish a scan: it is sliced")
Frame(); Frame()
CL.CancelScan()
assert(not EX.Busy("cleanup-scan"), "cancelled")
Pump(10)
assert(finished == false, "a cancelled scan never reports")
CL.Scan({}, function() finished = true end)
Frame()
EX.Release()
Pump(10)
assert(finished == false and CL.results == nil and not CL.Enabled(), "closing the explorer stops the scan and ends the mode")
-- Counting is sliced too, and stops when it is cancelled.
local counted
local bigT = Target("TwichUIDB", "setup", "received", "Pal")
CL.Count({bigT}, {}, function(ok) counted = ok end)
Frame()
CL.Enable(true)
EX.Cancel("cleanup-measure")
Pump(10)
assert(counted == nil, "a cancelled count never reports")
CL.Disable()
for i = #a.TwichUIRestoreDB.points, 1, -1 do
  if tostring(a.TwichUIRestoreDB.points[i].id):find("^x%d") then table.remove(a.TwichUIRestoreDB.points, i) end
end

---------------------------------------------------------------------------
-- 11. The window end to end: review text, counting, confirmation, result
---------------------------------------------------------------------------
XW.Show("restore:" .. point.id)
CL.Enable(true)
XW.Render()
assert(f.chip.shown == true)
f.delete.scripts.OnClick(f.delete)
d = a.TwichUIExplorerCleanupDialog
assert(d.shown, "the review opened")
text = d.body.edit.text
assert(text:find("DELETED PERMANENTLY", 1, true) and text:find("Path: TwichUIRestoreDB.points[", 1, true)
  and text:find("Key: [", 1, true) and text:find("saved data", 1, true) and text:find("everything under it", 1, true)
  and text:find("Done by: Backups' own Delete", 1, true) and text:find("Recovery:", 1, true), "the review: " .. text)
Pump(4)
text = d.body.edit.text
assert(text:find("values in", 1, true) and text:find("nested", 1, true), "nested data is counted: " .. text)
assert(text:find("Undo is available", 1, true))
d.confirmDanger.scripts.OnClick(d.confirmDanger)
assert(RS.Get(point.id) == nil, "deleted")
assert(d.body.edit.text:find("DELETED 1 ENTRY", 1, true) and d.body.edit.text:find("No reload is needed", 1, true))
assert(f.undo.shown == true, "undo is offered")
assert(f.head.text ~= "Before raid", "the explorer moved off what was removed")
d.scripts.OnKeyDown(d, "ESCAPE")
-- Undo through the window.
f.undo.scripts.OnClick(f.undo)
assert(d.shown and d.body.edit.text:find("puts back", 1, true))
d.confirmPlain.scripts.OnClick(d.confirmPlain)
assert(RS.Get(point.id), "put back")
d.scripts.OnKeyDown(d, "ESCAPE")
-- A stale review asks for a fresh one.
XW.Show("restore:" .. point.id)
f.delete.scripts.OnClick(f.delete)
Pump(4)
RS.Get(point.id).name = "Renamed behind the review"
RS.Get(point.id).tables.Extra = {owner = "Foo", data = {1}}
d.confirmDanger.scripts.OnClick(d.confirmDanger)
assert(RS.Get(point.id), "not deleted")
assert(d.body.edit.text:find("NOTHING WAS DELETED", 1, true) and d.body.edit.text:find("changed after it was reviewed", 1, true))
d.scripts.OnKeyDown(d, "ESCAPE")
-- Names are hidden in the review until Reveal is on, as everywhere in the explorer.
XW.Show("undo:Alt - Forever")
f.delete.scripts.OnClick(f.delete)
text = d.body.edit.text
assert(text:find("TwichUIBackupDB[<hidden: ", 1, true) and not text:find("Alt - Forever", 1, true),
  "the review hides the character's name: " .. text)
d.scripts.OnKeyDown(d, "ESCAPE")
f.reveal.scripts.OnClick(f.reveal)
f.delete.scripts.OnClick(f.delete)
assert(d.body.edit.text:find('TwichUIBackupDB["Alt - Forever"]', 1, true), "and shows the exact path when revealed")
d.scripts.OnKeyDown(d, "ESCAPE")
f.reveal.scripts.OnClick(f.reveal)
-- Suggestions in the window: found, picked by hand, reviewed.
f.find.scripts.OnClick(f.find)
for _ = 1, 20 do Pump(1) end
assert(f.head.text == "Cleanup candidates" and CL.results, "suggestions are listed")
assert(#CL.PickedCandidates() == 0, "none picked by default")
f:Hide()
assert(not CL.Enabled() and CL.results == nil and not a.TwichUIExplorerCleanupDialog.shown, "everything ends on close")

---------------------------------------------------------------------------
-- 12. A new install: nothing to suggest, and it says what was looked at
---------------------------------------------------------------------------
local clean = MakeClient("Fresh", {"!!!TwichUI"})
CLIENTS.Fresh = clean
clean.UIParent, clean.UISpecialFrames, clean.tinsert = Obj(), {}, table.insert
clean.CreateFrame = a.CreateFrame
for _, file in ipairs({"setup/StoredData.lua", "setup/Explorer.lua", "setup/Cleanup.lua"}) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, clean); chunk("!!!TwichUI", {})
end
clean.LOADED["!!!TwichUI"] = true; clean.FireEvent("ADDON_LOADED", "!!!TwichUI"); clean.FireEvent("PLAYER_LOGIN")
local CL2 = clean.TwichUI.Cleanup
local none
CL2.Scan({}, function(res) none = res end)
for _ = 1, 20 do FlushTimers() if none then break end end
assert(none and #none.list == 0 and #none.checked == #CL2.RULES, "nothing flagged on a new install, every rule reported")

---------------------------------------------------------------------------
-- 13. Nothing of any of it is in the saved variables
---------------------------------------------------------------------------
local function Contains(v, needle, seen)
  seen = seen or {}
  if type(v) == "string" then return v:find(needle, 1, true) ~= nil end
  if type(v) ~= "table" or seen[v] then return false end
  seen[v] = true
  for k, x in next, v do
    if Contains(k, needle, seen) or Contains(x, needle, seen) then return true end
  end
  return false
end
CL.Enable(true)
local last = Review({Target("TwichUIDB", "setup", "received", "Pal")})
assert(CL.Commit(last).status == "done" and CL.RecoveryInfo())
for _, name in ipairs(VARS) do
  assert(not Contains(rawget(a, name), "RECOVERY_MARKER_PAL"), "the removed data is not kept in " .. name)
  for k in next, rawget(a, name) do
    assert(type(k) ~= "string" or not (k:lower():find("cleanup") or k:lower():find("recovery") or k:lower():find("advanced")),
      "no cleanup state saved: " .. name .. "." .. tostring(k))
  end
end
CL.Reset()
print("CLEANUP OK")
