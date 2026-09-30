dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
DROP_SPACED_WHISPERS = true
local function boot(name, ver, scan)
  local c = MakeClient(name, {"!!!TwichUI","Foo","Bar"})
  CLIENTS[name] = c
  c.C_AddOns.GetAddOnMetadata = function(n, field) if n == "!!!TwichUI" and field == "Version" then return ver end end
  if scan then c.TwichUIDB = {setup = {scanNext = true}} end
  c.LOADED["!!!TwichUI"]=true; c.FireEvent("ADDON_LOADED","!!!TwichUI")
  c.FooDB = {a=1}; c.LOADED.Foo=true; c.FireEvent("ADDON_LOADED","Foo")
  c.FireEvent("PLAYER_LOGIN"); TIMERS = {}
  return c
end
local function settle() for _=1,10 do FlushTimers(); Pump() end end
local rich = boot("Ranulf Ashenvow", "3.0.0", true)
local pal = boot("Pal Stonebrook", "3.1.0")
local zed = boot("Zed Quill", "2.4.0")      -- old, but protocol? old clients don't answer hello at all
CLIENTS["Zed Quill"] = nil                  -- simulate no TwichUI answering
GROUP = {["Ranulf Ashenvow"]=true, ["Pal Stonebrook"]=true, ["Zed Quill"]=true}
for _, c in pairs(CLIENTS) do c.TwichUIDB.modules.groupCheck = true end
rich.TwichUIDB.modules.groupCheck = true; pal.TwichUIDB.modules.groupCheck = true
-- version hello
rich.TwichUI.Group:SayHello(); settle()
RunLongTimers(3); settle()                  -- pal answers a newcomer after 1-3 seconds
print("rich knows pal:", rich.TwichUI.Group.peers["Pal Stonebrook"] and rich.TwichUI.Group.peers["Pal Stonebrook"].v)
assert(rich.TwichUI.Group.peers["Pal Stonebrook"].v == "3.1.0", "hello answered")
-- group check
rich.TwichUI.Setups:SaveMine(false)
pal.Bar = nil
assert(rich.TwichUI.Group:RunCheck(true)); settle()
rich.TwichUI.Group.check.done = true
for _, r in ipairs(rich.TwichUI.Group:CheckRows()) do print("row", r.short, r.state, r.version, r.missing and #r.missing) end
-- probe (whispers dropped): marks not working after timeout
RunLongTimers(20)
assert(rich.TwichUIDB.whisperProbe and rich.TwichUIDB.whisperProbe.ok == false, "probe timed out")
print("whisper works?", rich.TwichUI.Share.WhisperWorks(), rich.TwichUI.Group.WhisperStatus())
-- simulate fixed whispers on new build
BUILD = "70100"; DROP_SPACED_WHISPERS = false
rich.TwichUIDB.whisperProbe = nil
rich.TwichUI.Group:MaybeProbe(); settle()
print("after fix:", rich.TwichUI.Share.WhisperWorks())
assert(rich.TwichUI.Share.WhisperWorks())
local route = rich.TwichUI.Share.Route("Pal Stonebrook")
print("route now:", route[1])
assert(route[1] == "WHISPER")
-- restore points
local st, p = rich.TwichUI.Restore:Create("before tweak")
assert(st == "created" and p.tables.FooDB)
rich.TwichUI.Restore:Restore(p.id)
assert(rich.TwichUIDB.setup.pending.source == "restore:"..p.id)
local db, bk, sh, rs = rich.TwichUIDB, rich.TwichUIBackupDB, rich.TwichUIShareDB, rich.TwichUIRestoreDB
local r2 = MakeClient("Ranulf Ashenvow", {"!!!TwichUI","Foo","Bar"})
r2.TwichUIDB, r2.TwichUIBackupDB, r2.TwichUIShareDB, r2.TwichUIRestoreDB = db, bk, sh, rs
r2.LOADED["!!!TwichUI"]=true; r2.FireEvent("ADDON_LOADED","!!!TwichUI")
r2.FooDB = {a=999}; r2.LOADED.Foo=true; r2.FireEvent("ADDON_LOADED","Foo")
r2.FireEvent("PLAYER_LOGIN")
assert(r2.FooDB.a == 1, "restored")
assert(r2.TwichUIBackupDB["Ranulf - Forever"].tables.FooDB.data.a == 999, "backup of pre-restore state")
local kinds = {} for _, i in ipairs(r2.TwichUI.Setups.StorageItems()) do kinds[i.kind] = true end
assert(kinds["Restore point"])
print("GROUP/RESTORE TESTS PASSED")
