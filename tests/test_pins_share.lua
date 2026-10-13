-- Party pins: sharing a saved (local) pin with the party.
-- Sharing publishes a snapshot of a saved pin as one party pin of yours, linked to it by a session-only id:
-- the saved pin keeps its id, place, name, color and Keep; Keep, the link and anything personal are never
-- on the wire; sharing again refreshes the same pin on the others' maps instead of adding one; editing or
-- deleting the saved pin sends nothing; the sender's own list shows one pin, not two; leaving the party and
-- rejoining publishes nothing; a message from someone else can't reach the saved pin or the group copy;
-- another player's pin can't be shared as yours; a raid, no party and the game's lockdown are refused with a
-- sentence; the link survives a /reload.
-- The network is the harness's simulation. Whether the game delivers these messages is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function Load(env, files)
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
  end
end

local MAPS = {
  [1429] = { name = "Elwynn Forest", parentMapID = 1415 },
  [1415] = { name = "Eastern Kingdoms", parentMapID = 947 },
  [1454] = { name = "Orgrimmar", parentMapID = 1411 },
}
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
-- messages the game was given with this prefix, by operation (decoded with the sender's own libraries)
local function sentOps(env)
  local ops = {}
  for _, m in ipairs(NET) do
    if m.prefix == "TwichUIPins" then
      local raw = env.LibStub("LibDeflate"):DecodeForWoWAddonChannel(m.text)
      local good, t = env.LibStub("LibSerialize"):Deserialize(raw)
      if good and type(t) == "table" then ops[#ops + 1] = t end
    end
  end
  return ops
end
local function sent() local n = 0 for _, m in ipairs(SENT_LOG or {}) do if m.prefix == "TwichUIPins" then n = n + 1 end end return n end
local function inject(env, from, msg)
  CLOCK = CLOCK + 2
  local text = env.LibStub("LibDeflate"):EncodeForWoWAddonChannel(env.LibStub("LibSerialize"):Serialize(msg))
  env._comm.TwichUIPins("TwichUIPins", text, "PARTY", from)
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local A, B = "Ranulf Ashenvow", "Pal Stonebrook"
CLOCK = 1000
GROUP = nil; RAID = false; NET = {}; SENT_LOG = {}

local saved = { modules = { partyPins = true }, pins = { nextId = 4, list = {
  { id = "L1", map = 1429, x = 1000, y = 2000, name = "Herb spot", color = "moss" },
  { id = "L2", map = 1454, x = 5500, y = 3100, name = "Reagent vendor", color = "violet", kept = true },
  { id = "L3", map = 1429, x = 700, y = 800, name = "Mailbox", color = "gold" },
} } }
local a = boot(A, saved)
local PN, PS = a.TwichUI.Pins, a.TwichUI.PinSync
local entryOf = function(id) return { kind = "local", pin = PN.FindLocal(id) } end

---------------------------------------------------------------------------
-- 1. Not in a party: refused with a sentence; nothing is made, sent or changed
---------------------------------------------------------------------------
local ok, why = PN.Can("share", entryOf("L2"))
assert(ok == false and why == "Join a party to share this pin.", tostring(why))
local pin, text = PS.ShareLocal("L2")
assert(pin == nil and text == "Join a party to share this pin." and sent() == 0 and PN.SharedCount() == 0)
assert(select(1, PN.Can("unshare", entryOf("L2"))) == false)
assert(PN.FindLocal("L2").kept == true, "a refused share changed nothing")

---------------------------------------------------------------------------
-- 2. A kept pin on another map, shared: the saved pin is untouched, the party gets a snapshot
---------------------------------------------------------------------------
local b = boot(B)
local BPN = b.TwichUI.Pins
GROUP = { [A] = true, [B] = true }
a.FireEvent("GROUP_ROSTER_UPDATE"); b.FireEvent("GROUP_ROSTER_UPDATE"); settle()
assert(PN.SessionOpen() and BPN.SessionOpen())
local before = { id = "L2", map = 1454, x = 5500, y = 3100, name = "Reagent vendor", color = "violet", kept = true }
local listBefore = PN.LocalCount()
NET = {}; SENT_LOG = {}
ok, why = PN.Can("share", entryOf("L2"))
assert(ok == true, "a kept pin on a map other than the one you are on can be shared: " .. tostring(why))
local copy, how = PS.ShareLocal("L2")
assert(copy and how == "new" and copy.mine and copy.source == "L2", "a group copy linked to the saved pin")
-- the saved pin: same record, same id, still kept, same place
local src = PN.FindLocal("L2")
for k, v in pairs(before) do assert(src[k] == v, "the saved pin's " .. k .. " is unchanged") end
assert(PN.LocalCount() == listBefore and PN.IsKept(src), "no pin was made, none removed, Keep stays")
assert(src.source == nil and src.shared == nil, "no sharing state is written onto the saved pin")
-- what went out: a put with exactly the pin's wire fields; nothing personal
local ops = sentOps(a)
assert(#ops == 1 and ops[1].o == "put" and ops[1].v == 1)
for k in pairs(ops[1]) do assert(k == "v" or k == "o" or k == "p", "unexpected field in the message: " .. k) end
for k in pairs(ops[1].p) do
  assert(k == "id" or k == "r" or k == "m" or k == "x" or k == "y" or k == "n" or k == "c", "unexpected field in the pin: " .. k)
end
assert(ops[1].p.m == 1454 and ops[1].p.x == 5500 and ops[1].p.y == 3100 and ops[1].p.n == "Reagent vendor" and ops[1].p.c == "violet",
  "the saved coordinates and look, not where you stand")
assert(not tostring(ops[1].p.id):find("^L%d+$"), "the saved pin's local id is not what the party sees")
settle()
local onB = BPN.Shared(BPN.Key(A, copy.id))
assert(onB and onB.name == "Reagent vendor" and onB.map == 1454 and onB.x == 5500 and onB.color == "violet", "B has it")
assert(onB.mine == false and onB.kept == nil and onB.source == nil, "B's copy is B's view of A's pin: not kept, no link")
-- the sender's own list: one pin, not two; the saved pin says it is shared
local shown = 0
for _, e in ipairs(PN.Entries()) do
  shown = shown + 1
  if e.pin.id == "L2" or e.pin.key == copy.key then assert(e.kind == "local" and e.shared == true, "the saved pin stands for both") end
end
assert(shown == 3, "three entries: the group copy is not a second marker (" .. shown .. ")")
assert(#PN.SharedPins() == 0 and PN.GroupCopy("L2") == copy and PN.Snapshot().sharedLocal == 1)
assert(PN.OwnCount() == 1, "it counts against your limits")

-- the sender's own message coming back changes nothing
local entriesNow = #PN.Entries()
inject(a, A, { v = 1, o = "put", p = { id = copy.id, r = 50, m = 1429, x = 1, y = 1, n = "Echo", c = "gold" } })
assert(#PN.Entries() == entriesNow and copy.name == "Reagent vendor" and copy.rev == 1, "your own echo is set aside")

---------------------------------------------------------------------------
-- 3. Sharing again refreshes the same pin; local edits alone send nothing
---------------------------------------------------------------------------
NET = {}; SENT_LOG = {}
assert(PN.UpdateLocal("L2", { name = "Reagents (Org)", color = "river" }))
settle()
assert(sent() == 0, "editing a saved pin sends nothing")
assert(onB.name == "Reagent vendor" and onB.color == "violet", "so B still has the snapshot")
CLOCK = CLOCK + 5
local again, how2 = PS.ShareLocal("L2")
assert(again == copy and how2 == "updated" and copy.rev == 2 and copy.id == ops[1].p.id, "same pin, same id, next revision")
settle()
assert(BPN.SharedCount() == 1, "no duplicate on B")
assert(onB.name == "Reagents (Org)" and onB.color == "river" and onB.rev == 2, "B has the new snapshot")
assert(PN.FindLocal("L2").id == "L2" and PN.IsKept(PN.FindLocal("L2")), "the saved pin kept its identity")
-- rapid repeats with nothing changed are one message (no settle between them: the clock stands still)
NET = {}; SENT_LOG = {}
CLOCK = CLOCK + 5
local c0, h0 = PS.ShareLocal("L2")
assert(h0 == "updated" and copy.rev == 3 and sent() == 1, "after the gap a re-share goes out again")
local c1, h1 = PS.ShareLocal("L2")
assert(c1 == copy and h1 == "unchanged" and sent() == 1 and copy.rev == 3, "shared a moment ago and nothing changed: not sent again")
settle()
NET = {}; SENT_LOG = {}
assert(PN.UpdateLocal("L2", { name = "Reagents" }))
local c2, h2 = PS.ShareLocal("L2")
assert(h2 == "updated" and sent() == 1 and copy.rev == 4, "a change goes out at once")
settle()
assert(onB.name == "Reagents" and BPN.SharedCount() == 1)
-- a member who removed it from their map keeps it off through a re-share (the existing rule)
assert(BPN.Dismiss(onB.key))
CLOCK = CLOCK + 5
assert(PS.ShareLocal("L2")); settle()
assert(BPN.IsDismissed(onB.key) and BPN.SharedCount() == 1, "a recipient's choice stands")
assert(BPN.Restore(onB.key))

---------------------------------------------------------------------------
-- 4. Nobody else can reach the saved pin or its group copy
---------------------------------------------------------------------------
local listSnapshot = {}
for _, p in ipairs(PN.LocalPins()) do listSnapshot[p.id] = p.name .. p.x .. p.y .. tostring(p.kept) end
inject(a, B, { v = 1, o = "del", id = copy.id, r = 99 })
inject(a, B, { v = 1, o = "put", p = { id = copy.id, r = 99, m = 1429, x = 9, y = 9, n = "Hijack", c = "gold" } })
inject(a, B, { v = 1, o = "all", l = {} })
inject(a, B, { v = 1, o = "put", p = { id = "L2", r = 99, m = 1429, x = 9, y = 9, n = "By local id", c = "gold" } })
assert(PN.Shared(copy.key) == copy and copy.name == "Reagents" and copy.x == 5500, "B's messages can't change A's pin")
for _, p in ipairs(PN.LocalPins()) do
  assert(listSnapshot[p.id] == p.name .. p.x .. p.y .. tostring(p.kept), "the saved pin " .. p.id .. " is untouched")
end
assert(not PN.Shared(PN.Key(B, "L2")) and not PN.Shared(PN.Key(A, "L2")), "a local id isn't a valid party id")
-- extra fields in a message don't create ownership or protection on the receiver
inject(b, A, { v = 1, o = "put", p = { id = "zz9999:1", r = 1, m = 1429, x = 10, y = 20, n = "Extras", c = "gold", k = true, s = "L1", kept = true, source = "L1" } })
local extra = BPN.Shared(BPN.Key(A, "zz9999:1"))
assert(extra and extra.kept == nil and extra.source == nil and not BPN.IsKept(extra), "kept and source never come from a message")
assert(#BPN.SharedPins() == 2, "B lists both of A's pins as ordinary party pins")
-- invalid payloads set aside, nothing half-applied
local bCount = BPN.SharedCount()
inject(b, A, { v = 1, o = "put", p = { id = "zz9999:2", r = 1, m = 99999, x = 10, y = 20, n = "Nowhere", c = "gold" } })
inject(b, A, { v = 1, o = "put", p = { id = "zz9999:3", r = 1, m = 1429, x = -5, y = 20, n = "Off", c = "gold" } })
inject(b, A, { v = 1, o = "put", p = { id = "zz9999:4", r = 1, m = 1429, x = 5, y = 20, n = "", c = "gold" } })
inject(b, A, { v = 2, o = "put", p = { id = "zz9999:5", r = 1, m = 1429, x = 5, y = 20, n = "Newer", c = "gold" } })
assert(BPN.SharedCount() == bCount, "invalid or newer messages made nothing")

---------------------------------------------------------------------------
-- 5. A recipient's copy is independent; someone else's pin can't be shared as yours
---------------------------------------------------------------------------
local fields = assert(BPN.CopyFields(onB.key))
local mineOnB = assert(BPN.AddLocal(fields))
assert(mineOnB.id:find("^L") and mineOnB.id ~= copy.id and mineOnB.name == "Reagents")
ok, why = BPN.Can("share", { kind = "party", pin = onB })
assert(ok == false and why:find("Save it to your pins first"), "another player's pin: " .. tostring(why))
ok, why = PN.Can("share", { kind = "party", pin = copy })
assert(ok == false and why:find("already shared"), "your own party pin is already shared: " .. tostring(why))
local viaB = BPN.GroupCopy(mineOnB.id)
assert(viaB == nil, "saving a copy doesn't share it")
local sharedByB = assert(b.TwichUI.PinSync.ShareLocal(mineOnB.id)); settle()
assert(sharedByB.owner == B and BPN.SharedCount() == 3, "B shares its own copy as B's pin (A's pin, the extras pin, B's)")
assert(PN.Shared(PN.Key(B, sharedByB.id)).owner ~= A, "owned by the sender, never by the original author")
assert(PN.Shared(copy.key) == copy and copy.name == "Reagents", "A's pin is unaffected")

---------------------------------------------------------------------------
-- 6. Deleting the saved pin sends nothing; the group copy stays with the party; unkept pins and the link
---------------------------------------------------------------------------
NET = {}; SENT_LOG = {}
local plain = assert(PS.ShareLocal("L1")); settle()
local plainOnB = BPN.Shared(BPN.Key(A, plain.id))
assert(plainOnB, "an ordinary pin shares the same way")
NET = {}; SENT_LOG = {}
assert(PN.RemoveLocal("L1") and not PN.FindLocal("L1"))
settle()
assert(sent() == 0, "deleting a saved pin sends nothing")
assert(plain.source == nil and PN.Shared(plain.key) == plain and #PN.SharedPins() >= 1, "its group copy is an ordinary party pin of yours now")
assert(BPN.Shared(plainOnB.key), "and the party still has it")
local entryParty = { kind = "party", pin = plain }
assert(PN.Can("removeParty", entryParty), "removable for the party like any of yours")
assert(PS.RemoveForParty(plain.key)); settle()
assert(not BPN.Shared(plainOnB.key))
-- a kept pin can't be deleted whether or not it is shared; stopping the share takes only the copy back
ok, why = PN.RemoveLocal("L2")
assert(ok == false and why == "kept" and PN.FindLocal("L2") and PN.GroupCopy("L2") == copy)
ok, why = PN.Can("unshare", entryOf("L2"))
assert(ok == true, tostring(why))
assert(PS.UnshareLocal("L2")); settle()
assert(PN.GroupCopy("L2") == nil and not PN.Shared(copy.key) and not BPN.Shared(BPN.Key(A, copy.id)), "the shared copy is gone for everyone")
src = PN.FindLocal("L2")
assert(src and src.kept == true and src.name == "Reagents" and src.x == 5500, "the saved pin is exactly as it was")
for _, e in ipairs(PN.Entries()) do if e.pin.id == "L2" then assert(e.shared == false) end end
assert(not PN.Can("unshare", entryOf("L2")))
-- sharing again after that is a new party pin (a removed id never comes back)
CLOCK = CLOCK + 5
local fresh = assert(PS.ShareLocal("L2")); settle()
assert(fresh.id ~= copy.id and BPN.Shared(BPN.Key(A, fresh.id)) and not BPN.Shared(BPN.Key(A, copy.id)))

---------------------------------------------------------------------------
-- 7. Bulk actions: a group copy is not a party pin you can hide, and clearing deletes only unkept saved pins
---------------------------------------------------------------------------
-- (B's own shared pin from section 5 would count as a party pin to hide, so B takes it back first)
assert(b.TwichUI.PinSync.RemoveForParty(sharedByB.key)); settle()
local scope = PN.ClearScope()
assert(scope.partyHide == 0, "a group copy isn't counted among party pins to hide (" .. scope.partyHide .. ")")
assert(PN.DismissAll() == 0 and not PN.IsDismissed(fresh.key))
local mailbox = assert(PS.ShareLocal("L3")); settle()
scope = PN.ClearScope()
assert(scope.localDelete == 1 and scope.partyHide == 0 and scope.kept == 1, "one unkept saved pin would go")
local removed, hidden = PN.ClearUnprotected(scope)
assert(removed == 1 and hidden == 0 and not PN.FindLocal("L3"), "the unkept saved pin is deleted")
assert(PN.Shared(mailbox.key) == mailbox and not PN.IsDismissed(mailbox.key), "its group copy is left, shared, and not hidden by the same clear")
assert(BPN.Shared(BPN.Key(A, mailbox.id)), "and the party still has it")
assert(PS.RemoveForParty(mailbox.key)); settle()

---------------------------------------------------------------------------
-- 8. Leaving and rejoining publishes nothing; the saved pins stay
---------------------------------------------------------------------------
assert(PN.GroupCopy("L2") == fresh)
GROUP = { [B] = true }
a.FireEvent("GROUP_ROSTER_UPDATE"); b.FireEvent("GROUP_ROSTER_UPDATE"); settle()
assert(not PN.SessionOpen() and PN.GroupCopy("L2") == nil and PN.FindLocal("L2") and PN.IsKept(PN.FindLocal("L2")),
  "the party ended: the group copy is gone, the saved pin stays kept")
assert(not BPN.Shared(BPN.Key(A, fresh.id)), "and B no longer has A's pins")
NET = {}; SENT_LOG = {}
GROUP = { [A] = true, [B] = true }
a.FireEvent("GROUP_ROSTER_UPDATE"); b.FireEvent("GROUP_ROSTER_UPDATE"); settle()
for _, m in ipairs(sentOps(a)) do assert(m.o ~= "put" and m.o ~= "all", "nothing was published on rejoining: " .. tostring(m.o)) end
assert(PN.SharedCount() == 0 and not BPN.Shared(BPN.Key(A, fresh.id)), "no saved pin was published by joining")
assert(PN.Entries()[1].shared == false and PN.FindLocal("L2").name == "Reagents")

---------------------------------------------------------------------------
-- 9. A /reload in the party keeps the link, so sharing again still refreshes the same pin
---------------------------------------------------------------------------
local first = assert(PS.ShareLocal("L2")); settle()
local firstId = first.id
a.FireEvent("PLAYER_LOGOUT")
CLIENTS[A] = nil
local a2 = boot(A, a.TwichUIDB, true)
local PN2, PS2 = a2.TwichUI.Pins, a2.TwichUI.PinSync
local back = PN2.GroupCopy("L2")
assert(back and back.id == firstId and back.mine and back.source == "L2", "the group copy and its link came back")
local shown2 = 0
for _, e in ipairs(PN2.Entries()) do shown2 = shown2 + 1 end
assert(shown2 == 1, "still one entry for it (" .. shown2 .. ")")
assert(PN2.UpdateLocal("L2", { color = "rose" }))
CLOCK = CLOCK + 5
local refreshed, how3 = PS2.ShareLocal("L2"); settle()
assert(refreshed and refreshed.id == firstId and how3 == "updated" and BPN.SharedCount() == 1, "same id after the reload, no duplicate")
assert(BPN.Shared(BPN.Key(A, firstId)).color == "rose")
-- a saved session can't invent a link to a pin that isn't a saved id
local ses = PN2.ExportSession()
for _, p in ipairs(ses.pins) do if p.mine then p.s = "not an id" end end
PN2.EndSession()
assert(PN2.ImportSession(ses))
assert(PN2.GroupCopy("L2") == nil, "an unreadable link is dropped")

---------------------------------------------------------------------------
-- 10. Raid, the game's lockdown, limits, a refused send
---------------------------------------------------------------------------
RAID = true
ok, why = PN2.Can("share", { kind = "local", pin = PN2.FindLocal("L2") })
assert(ok == false and why == "Pins can only be shared with a party, not a raid.", tostring(why))
NET = {}; SENT_LOG = {}
local nope, why2 = PS2.ShareLocal("L2")
assert(nope == nil and why2 == why and sent() == 0)
RAID = false
-- the game's own messaging lockdown
local chat = a2.C_ChatInfo
local oldLock = chat.InChatMessagingLockdown
chat.InChatMessagingLockdown = function() return true end
ok, why = PN2.Can("share", { kind = "local", pin = PN2.FindLocal("L2") })
assert(ok == false and why:find("holding addon messages"), tostring(why))
chat.InChatMessagingLockdown = oldLock
-- the game refusing the send is reported once, not as success
local notices = {}
-- the map module isn't loaded in this test: its one-line notice is stood in for
a2.TwichUI.PinsMap = { Notice = function(text) notices[#notices + 1] = text end }
FAIL_SEND = function() return true end
assert(PN2.UpdateLocal("L2", { name = "Refused rename" }))
CLOCK = CLOCK + 5
assert(PS2.ShareLocal("L2"))
FAIL_SEND = nil
local gotRefused = false
for _, n in ipairs(notices) do if n:find("didn't take") then gotRefused = true end end
assert(gotRefused, "a refused send says so")
-- limits: 20 per player, shared copies included
CLOCK = CLOCK + 5
for i = 1, 25 do assert(PN2.AddLocal({ map = 1429, x = 100 + i, y = 100, name = "Spot " .. i })) end
local made, stopped = 0, nil
for _, p in ipairs(PN2.LocalPins()) do
  local s, t = PS2.ShareLocal(p.id)
  if s then made = made + 1 else stopped = t break end
end
-- one group copy was already there (an orphan from the dropped link), one more for L2, then the rest up to 20
assert(made == 19, "shares up to the per-player limit (" .. made .. ")")
assert(stopped and stopped:find("party pins"), "then says why: " .. tostring(stopped))
assert(PN2.OwnCount() == PN2.MAX_PER_OWNER)

---------------------------------------------------------------------------
-- 11. Diagnostics carry counts only
---------------------------------------------------------------------------
local snap = PN2.Snapshot()
assert(type(snap.sharedLocal) == "number")
for k, v in pairs(snap) do assert(type(v) ~= "string" or k == "x", "no text in the snapshot: " .. k) end
print("PINS SHARE TESTS PASSED")
