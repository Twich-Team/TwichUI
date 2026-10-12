-- Party pins: Keep. A kept pin can't be deleted, cleared or moved until Keep is turned off, however it is
-- asked (the data layer refuses, not only the buttons); naming, coloring and hiding stay possible; old pins
-- load as ordinary pins; clearing leaves kept pins, counts what it will do and only touches the pins it
-- named; bulk hiding skips them; Keep is never sent and a message can't change it; a local copy of someone
-- else's party pin is an independent record that later messages and party changes can't reach; a kept party
-- pin of yours is carried across a /reload with the session and is not sent.
-- The network is the harness's simulation. Whether the game delivers these messages is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

local MAPS = { [1429] = { name = "Elwynn Forest", parentMapID = 1415 }, [1415] = { name = "Eastern Kingdoms", parentMapID = 947 } }
local function boot(name, saved, reload)
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c
  c.C_Map = {
    GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parentMapID } or nil end,
    CanSetUserWaypointOnMap = function(id) return id == 1429 end,
  }
  c.IsInRaid = function() return RAID == true end
  c.GetTime = function() return CLOCK end
  Load(c, { "pins/Pins.lua", "pins/Sync.lua" })
  c.TwichUIDB = saved or { modules = { partyPins = true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", not reload, reload and true or false); TIMERS = {}
  return c
end
local function settle() for _ = 1, 10 do FlushTimers(); Pump() end; CLOCK = CLOCK + 20 end
local function sent() local n = 0 for _, m in ipairs(SENT_LOG or {}) do if m.prefix == "TwichUIPins" then n = n + 1 end end return n end

local A, B = "Ranulf Ashenvow", "Pal Stonebrook"
CLOCK = 1000
GROUP = nil; RAID = false; NET = {}; SENT_LOG = {}

---------------------------------------------------------------------------
-- 1. Saved data: old pins are ordinary; a kept pin survives a reload; only `true` counts
---------------------------------------------------------------------------
local saved = { modules = { partyPins = true }, pins = { nextId = 4, list = {
  { id = "L1", map = 1429, x = 100, y = 200, name = "Old pin", color = "gold", created = 5 },
  { id = "L2", map = 1429, x = 300, y = 400, name = "Odd value", color = "gold", kept = "yes" },
  { id = "L3", map = 1429, x = 500, y = 600, name = "Reagents", color = "river", kept = true },
} } }
local a = boot(A, saved)
local PN, PS = a.TwichUI.Pins, a.TwichUI.PinSync
assert(not PN.IsKept(PN.FindLocal("L1")) and not PN.IsKept(PN.FindLocal("L2")), "a pin without the field, or with a stray value, is ordinary")
assert(PN.IsKept(PN.FindLocal("L3")))
assert(PN.KeptCount() == 1)
local e1 = PN.Entries()
local keptEntries = 0
for _, e in ipairs(e1) do if e.kept then keptEntries = keptEntries + 1 end end
assert(keptEntries == 1, "entries say which are kept")

local fresh = assert(PN.AddLocal({ map = 1429, x = 1, y = 2, name = "Fresh" }))
assert(fresh.kept == nil, "a new pin is unprotected unless asked")
local made = assert(PN.AddLocal({ map = 1429, x = 3, y = 4, name = "Made kept", kept = true }))
assert(made.kept == true and PN.IsKept(PN.FindLocal(made.id)))
a.FireEvent("PLAYER_LOGOUT")
CLIENTS[A] = nil
a = boot(A, a.TwichUIDB)
PN, PS = a.TwichUI.Pins, a.TwichUI.PinSync
assert(PN.IsKept(PN.FindLocal("L3")) and PN.IsKept(PN.FindLocal(made.id)), "kept pins come back after a reload")
assert(not PN.IsKept(PN.FindLocal(fresh.id)))

---------------------------------------------------------------------------
-- 2. A kept pin: not deleted, not moved; still renamed, recolored and (unkept) deletable
---------------------------------------------------------------------------
local ok, why = PN.RemoveLocal("L3")
assert(ok == false and why == "kept" and PN.FindLocal("L3"), "single deletion is refused with the protected-pin code")
assert(PN.Reason("kept"):find("kept"), "and has a sentence")
ok, why = PN.Can("delete", { kind = "local", pin = PN.FindLocal("L3") })
assert(ok == false and why:find("kept") and PN.Can("edit", { kind = "local", pin = PN.FindLocal("L3") }), "the menus are told why")
assert(PN.Can("delete", { kind = "local", pin = PN.FindLocal("L1") }), "an ordinary pin can still be deleted")

assert(PN.UpdateLocal("L3", { name = "Reagent vendor", color = "violet" }), "rename and recolor are allowed")
local p3 = PN.FindLocal("L3")
assert(p3.name == "Reagent vendor" and p3.color == "violet" and p3.kept == true and p3.x == 500, "and don't touch the rest")
for _, fields in ipairs({ { x = 1 }, { y = 1 }, { map = 1415 }, { map = 1415, x = 7, y = 8 }, { name = "Moved", x = 9 } }) do
  ok, why = PN.UpdateLocal("L3", fields)
  assert(ok == false and why == "kept", "a move is refused: " .. tostring(next(fields)))
end
assert(p3.map == 1429 and p3.x == 500 and p3.y == 600 and p3.name == "Reagent vendor", "nothing changed by the refused moves, not even the name")
assert(PN.UpdateLocal("L3", { kept = true, color = "gold" }) and PN.IsKept(p3), "saying it is kept again changes nothing")

-- unlocking and moving in one save is the editor's flow; unlocking alone moves and deletes nothing
local before = PN.LocalCount()
assert(PN.UpdateLocal("L3", { kept = false }))
assert(not PN.IsKept(p3) and PN.LocalCount() == before and p3.x == 500, "unlocking alone deletes and moves nothing")
assert(PN.UpdateLocal("L3", { kept = true }))
assert(PN.UpdateLocal("L3", { kept = false, x = 510, y = 610 }) and p3.x == 510 and p3.y == 610 and not PN.IsKept(p3), "unlocked in the same save: the move is allowed")
ok, why = PN.UpdateLocal("L3", { x = 20000 })
assert(ok == false and why == "bad-coordinates" and p3.x == 510, "a move is still checked like a new pin")
ok, why = PN.UpdateLocal("L3", { map = 99999 })
assert(ok == false and why == "unknown-map" and p3.map == 1429)
assert(PN.UpdateLocal("L3", { kept = true }))

-- a refused edit changes nothing at all
ok, why = PN.UpdateLocal("L3", { name = "Half done", color = "neon" })
assert(ok == false and why == "bad-color" and p3.name == "Reagent vendor", "all or nothing")

-- once unkept, ordinary deletion works
assert(PN.UpdateLocal("L3", { kept = false }) and PN.RemoveLocal("L3") and not PN.FindLocal("L3"))

---------------------------------------------------------------------------
-- 3. Clearing: kept pins stay; the counts are the scope; only the named pins are touched
---------------------------------------------------------------------------
a.TwichUIDB.pins.list = {}
a.TwichUIDB.pins.nextId = 1
PN.selected = nil
local n1 = assert(PN.AddLocal({ map = 1429, x = 1, y = 1, name = "Ore" }))
local n2 = assert(PN.AddLocal({ map = 1429, x = 2, y = 2, name = "Herbs" }))
local k1 = assert(PN.AddLocal({ map = 1429, x = 3, y = 3, name = "Vendor", kept = true }))
local k2 = assert(PN.AddLocal({ map = 1429, x = 4, y = 4, name = "Mailbox", kept = true }))
table.insert(a.TwichUIDB.pins.list, { id = "L77", map = 1429, x = "bad", y = 3, name = "unreadable" })   -- a record this version can't read
local scope = PN.ClearScope()
assert(scope.localDelete == 2 and scope.kept == 2 and scope.partyHide == 0, "counts of the scope, not of all pins")
assert(scope.localIds[n1.id] and scope.localIds[n2.id] and not scope.localIds[k1.id])
-- the player keeps one of the two after the question was asked, and a new pin appears
assert(PN.UpdateLocal(n2.id, { kept = true }))
local late = assert(PN.AddLocal({ map = 1429, x = 5, y = 5, name = "Late" }))
local removed, hidden, kept = PN.ClearUnprotected(scope)
assert(removed == 1 and hidden == 0 and kept == 3, "judged again: the pin kept since stays (" .. removed .. "," .. hidden .. "," .. kept .. ")")
assert(not PN.FindLocal(n1.id) and PN.FindLocal(n2.id) and PN.FindLocal(k1.id) and PN.FindLocal(k2.id), "kept pins survived")
assert(PN.FindLocal(late.id), "a pin made after the question is not in what was confirmed")
assert(PN.FindLocal("L77"), "an entry this version can't read is left, never erased")
-- no scope: every unkept readable pin, still not the kept ones
removed, hidden, kept = PN.ClearUnprotected()
assert(removed == 1 and kept == 3 and not PN.FindLocal(late.id) and PN.LocalCount() == 3)
removed = PN.ClearLocal()
assert(removed == 0 and PN.LocalCount() == 3, "nothing left to clear")
-- one batch, one notification
local notes = 0
PN.OnChange(function() notes = notes + 1 end)
assert(PN.AddLocal({ map = 1429, x = 6, y = 6, name = "A" })); assert(PN.AddLocal({ map = 1429, x = 7, y = 7, name = "B" }))
notes = 0
PN.ClearUnprotected()
assert(notes == 1, "a clear tells the views once (" .. notes .. ")")

---------------------------------------------------------------------------
-- 4. Party: Keep on your own party pin; never sent; messages can't touch it; bulk hiding skips it
---------------------------------------------------------------------------
a.TwichUIDB.pins.list = {}
a.TwichUIDB.pins.nextId = 1
GROUP = nil
local b = boot(B)
local BPN = b.TwichUI.Pins
GROUP = { [A] = true, [B] = true }
a.FireEvent("GROUP_ROSTER_UPDATE"); b.FireEvent("GROUP_ROSTER_UPDATE")
settle()
assert(PN.SessionOpen() and BPN.SessionOpen())
local sentBefore = sent()
local camp = assert(PS.CreateParty({ map = 1429, x = 4000, y = 5000, name = "Camp", color = "ember", kept = true }))
-- what was handed to the game, decoded: the same fields as ever, none for Keep
local wire
for _, m in ipairs(NET) do
  if m.prefix == "TwichUIPins" then
    local raw = a.LibStub("LibDeflate"):DecodeForWoWAddonChannel(m.text)
    local good, t = a.LibStub("LibSerialize"):Deserialize(raw)
    assert(good and type(t) == "table")
    wire = t
  end
end
assert(wire and wire.o == "put" and type(wire.p) == "table", "a put went out")
for k in pairs(wire) do assert(k == "v" or k == "o" or k == "p", "unexpected field in the message: " .. tostring(k)) end
for k in pairs(wire.p) do
  assert(k == "id" or k == "r" or k == "m" or k == "x" or k == "y" or k == "n" or k == "c", "unexpected field in the pin: " .. tostring(k))
end
settle()
assert(camp.kept == true and PN.IsKept(PN.Shared(camp.key)))
local onB = BPN.Shared(BPN.Key(A, camp.id))
assert(onB and onB.kept == nil and not BPN.IsKept(onB), "the recipient's copy is not kept: Keep isn't sent")
assert(sent() == sentBefore + 1, "one message made the pin")

-- Keep alone sends nothing and changes no revision
sentBefore = sent()
local rev = camp.rev
assert(PS.UpdateParty(camp.key, { kept = false })); settle()
assert(not PN.IsKept(camp) and camp.rev == rev and sent() == sentBefore, "turning Keep off alone sends nothing")
assert(PS.UpdateParty(camp.key, { kept = true })); settle()
assert(PN.IsKept(camp) and sent() == sentBefore and camp.rev == rev)
assert(PS.UpdateParty(camp.key, { name = "Camp 2", kept = true })); settle()
assert(camp.rev == rev + 1 and sent() == sentBefore + 1 and BPN.Shared(onB.key).name == "Camp 2", "a rename is shared as before")

-- paused in a raid (nothing can be sent): Keep alone still changes, a new name or color is refused
RAID = true
sentBefore, rev = sent(), camp.rev
local entry = { kind = "party", pin = camp }
assert(PN.Can("keep", entry) and not PN.Can("edit", entry), "Keep is allowed while paused; editing for the party isn't")
assert(PS.UpdateParty(camp.key, { kept = false }), "Keep can be turned off while paused")
assert(not PN.IsKept(camp) and sent() == sentBefore and camp.rev == rev)
assert(PS.UpdateParty(camp.key, { kept = true }), "and on again")
local none, whyPaused = PS.UpdateParty(camp.key, { name = "Not now" })
assert(none == nil and whyPaused:find("paused") and camp.name == "Camp 2" and camp.rev == rev and sent() == sentBefore,
  "a rename waits: " .. tostring(whyPaused))
assert(not PS.UpdateParty(camp.key, { color = "moss", kept = true }) and camp.color ~= "moss", "so does a color, even with Keep in the same change")
RAID = false
assert(PN.IsKept(camp))
-- someone else's pin is never yours to keep
local onBEntry = { kind = "party", pin = BPN.Shared(onB.key) }
assert(not BPN.Can("keep", onBEntry) and select(2, BPN.Can("keep", onBEntry)):find("Only the player"))

-- not removable for the party while kept, by any route
ok, why = PS.RemoveForParty(camp.key)
assert(ok == false and why:find("kept"), "the sync layer refuses: " .. tostring(why))
local rev2, code = PN.DeleteOwn(camp.key)
assert(rev2 == nil and code == "kept" and PN.Shared(camp.key), "and so does the data layer")
assert(not PN.Can("removeParty", { kind = "party", pin = camp }) and BPN.Shared(onB.key))

-- someone else's message can't change it; their own pins are theirs
local function inject(env, from, msg)
  CLOCK = CLOCK + 2
  local text = env.LibStub("LibDeflate"):EncodeForWoWAddonChannel(env.LibStub("LibSerialize"):Serialize(msg))
  env._comm.TwichUIPins("TwichUIPins", text, "PARTY", from)
end
inject(a, B, { v = 1, o = "del", id = camp.id, r = 99 })
inject(a, B, { v = 1, o = "put", p = { id = camp.id, r = 99, m = 1429, x = 1, y = 1, n = "Hijack", c = "gold" } })
inject(a, B, { v = 1, o = "all", l = {} })
assert(PN.Shared(camp.key) and PN.Shared(camp.key).name == "Camp 2" and PN.IsKept(PN.Shared(camp.key)), "A's kept pin is untouched by B's messages")
-- a message claiming to be A's echo can't change it either
inject(a, A, { v = 1, o = "put", p = { id = camp.id, r = 99, m = 1429, x = 1, y = 1, n = "Echo", c = "gold" } })
assert(PN.Shared(camp.key).name == "Camp 2" and PN.IsKept(camp))

-- bulk hiding skips kept pins; a single hide is allowed and keeps the pin kept and protected
local plain = assert(PS.CreateParty({ map = 1429, x = 10, y = 10, name = "Plain" })); settle()
assert(PN.ClearScope().partyHide == 1 and PN.ClearScope().kept == 1, "the scope counts only what would be hidden")
assert(PN.DismissAll() == 1 and not PN.IsDismissed(camp.key) and PN.IsDismissed(plain.key), "Remove all from my map skips kept pins")
assert(PN.Restore(plain.key))
assert(PN.Dismiss(camp.key) and PN.IsDismissed(camp.key) and PN.IsKept(camp) and PN.Shared(camp.key), "hidden: still saved and kept")
ok, why = PS.RemoveForParty(camp.key)
assert(ok == false, "hidden doesn't unlock")
assert(PN.Restore(camp.key))
local sentFor = sent()
removed, hidden, kept = PN.ClearUnprotected()
assert(removed == 0 and hidden == 1 and kept == 1 and PN.IsDismissed(plain.key) and not PN.IsDismissed(camp.key), "clear: hides the plain one, leaves the kept")
assert(sent() == sentFor, "clearing sends nothing")
assert(BPN.Shared(BPN.Key(A, plain.id)) and not BPN.IsDismissed(BPN.Key(A, plain.id)), "and the party keeps its copy")
PN.Restore(plain.key)

---------------------------------------------------------------------------
-- 5. A copy of someone else's pin: independent, reviewed, never sent, out of reach of messages
---------------------------------------------------------------------------
local palPin = assert(BPN.Shared(BPN.Key(A, camp.id)))
local fields = assert(BPN.CopyFields(palPin.key))
assert(fields.map == 1429 and fields.x == 4000 and fields.name == "Camp 2" and fields.color == "ember", "the pin's place, name and color")
assert(fields.copiedFrom == "Ranulf" or fields.copiedFrom == A or fields.copiedFrom:find("Ranulf"), "and who made it")
assert(BPN.LocalCount() == 0, "asking for the fields makes nothing")
sentBefore = sent()
fields.kept = true
local copy = assert(BPN.AddLocal(fields))
assert(copy.kept == true and copy.id:find("^L") and copy.id ~= palPin.id and BPN.IsKept(BPN.FindLocal(copy.id)), "a new local identity, kept")
assert(sent() == sentBefore, "a local copy is not broadcast")
-- the original's life doesn't reach it
assert(PS.UpdateParty(camp.key, { name = "Moved", color = "moss" })); settle()
assert(BPN.FindLocal(copy.id).name == "Camp 2" and BPN.FindLocal(copy.id).color == "ember", "later edits to the original don't reach the copy")
assert(PS.UpdateParty(camp.key, { kept = false }))
-- the owner removes it for the party (unkept), and leaves
ok = PS.RemoveForParty(camp.key); settle()
assert(ok and not BPN.Shared(palPin.key), "gone for B")
assert(BPN.FindLocal(copy.id) and BPN.IsKept(BPN.FindLocal(copy.id)), "the copy stays")
GROUP = { [A] = true }
b.FireEvent("GROUP_ROSTER_UPDATE"); settle()
assert(not BPN.SessionOpen() and BPN.FindLocal(copy.id), "and so does it when the party ends")
-- the copy can be renamed but not removed until unkept
ok, why = BPN.RemoveLocal(copy.id)
assert(ok == false and why == "kept")
-- the same copy again: duplicates are allowed as before, and never replace the kept one
local twin = assert(BPN.AddLocal({ map = fields.map, x = fields.x, y = fields.y, name = fields.name, color = fields.color, copiedFrom = fields.copiedFrom }))
assert(twin.id ~= copy.id and BPN.IsKept(BPN.FindLocal(copy.id)) and not BPN.IsKept(twin), "saving it again makes another pin and leaves the kept one alone")
-- KeepCopy still works for a caller that wants no dialog
GROUP = { [A] = true, [B] = true }
a.FireEvent("GROUP_ROSTER_UPDATE"); b.FireEvent("GROUP_ROSTER_UPDATE"); settle()
local pal2 = assert(PS.CreateParty({ map = 1429, x = 99, y = 99, name = "Wells" })); settle()
local viaCopy = assert(BPN.KeepCopy(BPN.Key(A, pal2.id), true))
assert(viaCopy.kept == true and viaCopy.copiedFrom ~= nil)
assert(not BPN.KeepCopy(BPN.Key(A, "zz:1")), "a pin that is gone can't be copied")

---------------------------------------------------------------------------
-- 6. A kept party pin of yours is carried across a /reload with the session, and only then
---------------------------------------------------------------------------
GROUP = { [A] = true, [B] = true }
local mine = assert(PS.CreateParty({ map = 1429, x = 700, y = 800, name = "Anchor", kept = true })); settle()
assert(PN.IsKept(mine))
a.FireEvent("PLAYER_LOGOUT")
assert(a.TwichUIDB.pins.session, "the session is kept for the next load")
CLIENTS[A] = nil
local a2 = boot(A, a.TwichUIDB, true)
local PN2 = a2.TwichUI.Pins
assert(PN2.Shared(mine.key) and PN2.IsKept(PN2.Shared(mine.key)) and PN2.Shared(mine.key).mine, "kept across a reload")
assert(select(2, PN2.DeleteOwn(mine.key)) == "kept")
-- a damaged saved session whose count is behind its own ids: a new pin takes a fresh id, never the kept
-- pin's place, nor an id removed earlier this session
do
  local PS2 = a2.TwichUI.PinSync
  local gone = assert(PS2.CreateParty({ map = 1429, x = 1, y = 1, name = "Gone" })); settle()
  assert(PS2.RemoveForParty(gone.key)); settle()
  local damaged = PN2.ExportSession()
  damaged.seq = 0
  PN2.EndSession()
  assert(PN2.ImportSession(damaged))
  local anchor = PN2.Shared(mine.key)
  assert(anchor and PN2.IsKept(anchor))
  local before = {}
  for _, p in ipairs(PN2.OwnPins()) do before[p.key] = p.name end
  local made = {}
  -- enough to pass every id handed out before, the kept pin's and the removed one's included
  for i = 1, 5 do made[i] = assert(PS2.CreateParty({ map = 1429, x = 50 + i, y = 50, name = "New " .. i })) end
  settle()
  local anchorNow = PN2.Shared(mine.key)
  assert(anchorNow == anchor and anchorNow.name == "Anchor" and PN2.IsKept(anchorNow), "the kept pin is untouched")
  for key, name in pairs(before) do
    assert(PN2.Shared(key) and PN2.Shared(key).name == name, "an earlier pin of yours is untouched: " .. name)
  end
  for _, p in ipairs(made) do
    assert(p.key ~= mine.key and p.key ~= gone.key and PN2.Shared(p.key) == p, "a fresh id: " .. p.id)
    assert(BPN.Shared(BPN.Key(A, p.id)), "and the party gets it (not dropped as removed): " .. p.id)
  end
  for _, p in ipairs(made) do PS2.RemoveForParty(p.key) end
  settle()
end
-- a saved session can't make someone else's pin kept
local ses = a2.TwichUIDB.pins.session or PN2.ExportSession()
for _, p in ipairs(ses.pins) do p.k = true end
PN2.EndSession()
assert(PN2.ImportSession(ses))
for _, p in ipairs(PN2.SharedPins()) do
  assert(p.mine == PN2.IsKept(p), "only your own pins can be kept, whatever the saved record says")
end

---------------------------------------------------------------------------
-- 7. Diagnostics hold a count, not names
---------------------------------------------------------------------------
local snap = PN2.Snapshot()
assert(type(snap.kept) == "number")
for k in pairs(a2.TwichUIDB.pins) do assert(k == "list" or k == "nextId" or k == "session", "undeclared field: " .. tostring(k)) end

print("PINS KEEP TESTS PASSED")
