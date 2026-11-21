-- TwichUI Fishing: lures (TwichUI_Fishing/Lure.lua) and equipment (TwichUI_Fishing/Gear.lua): choosing and applying a lure,
-- expiry and identification; the original-equipment snapshot, restoration, interrupted swaps, the player's own changes,
-- full bags, combat, and recovery after a reload. Simulated client (tests/fishing_mock.lua).
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"

local function Fresh(opts)
  local c, W = FishingClient(opts)
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  return c, W, c.TwichUI.Fishing
end

---------------------------------------------------------------------------
-- Lures
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local L = F.Lure
  Check(L.Status().state == "no-pole", "no pole: no lure status")
  W.Wear(16, POLE)
  Check(L.Status().state == "none", "a bare pole")
  Check(L.Plan() == nil, "no lure in the bags: nothing to apply")
  Check(W.Key("F") == "spell", "and the key simply casts")
  W.Key("F"); W.Advance(2)
  W.Give(LURE25, 2); W.Give(LURE75, 1); W.Give(LURE50, 5)
  Check(L.Choose().item == LURE75, "no preference: the best lure in the bags")
  c.TwichUI.RunCommand("fish lure " .. LURE25)
  Check(L.Choose().item == LURE25, "the preferred lure when it is there")
  c.TwichUI.RunCommand("fish lure " .. FISH_LINK(LURE50))
  Check(F.Store.Get("lure.preferred") == LURE50, "an item link works too")
  W.bags[W.Find(LURE50)][select(2, W.Find(LURE50))] = nil
  local e, why = L.Choose()
  Check(e == nil and why == "preferred-missing", "preferred missing and no alternatives allowed: none")
  c.TwichUI.RunCommand("fish lure alternative on")
  Check(L.Choose().item == LURE75, "alternatives allowed: the best other one")
  -- applying through the key, and learning the enchant
  Check(W.Key("F") == "item" and F.Action.last.kind == "lure" and W.enchant.id == 265, "the key applies it")
  Check(W.Count(LURE75) == 0, "one lure used")
  local st = L.Status()
  Check(st.state == "active" and st.identified and st.lure == LURE75 and st.seconds == 600, "known as a lure, 10 minutes left")
  Check(W.Key("F") == "spell", "an active lure is not renewed: the key casts")
  -- expiry during a cast: the line is never interrupted, the lure is renewed on the next press
  W.enchant = nil; c.FireEvent("WEAPON_ENCHANT_CHANGED")
  Check(W.channel ~= nil, "a lure expiring never stops the line")
  Check(W.Key("F") == "reel", "the key still reels")
  W.Advance(2)
  Check(W.Key("F") == "item" and F.Action.last.kind == "lure" and W.Count(LURE25) == 1, "the next press renews it")
  -- expiring soon
  W.enchant.ms = 30000
  Check(L.Status().state == "expiring" and L.Plan() == nil, "expiring: reported, not renewed by default (nothing wasted)")
  c.TwichUI.RunCommand("fish lure early 45")
  Check(L.Plan() and L.Plan().kind == "lure", "renew early when asked to")
  c.TwichUI.RunCommand("fish lure early 0")
  -- an enchant TwichUI didn't apply is not assumed to be a lure, and never overwritten
  W.enchant = { ms = 120000, id = 999 }
  st = L.Status()
  Check(st.state == "active" and not st.identified and st.lure == nil, "an unknown enchant is unidentified")
  Check(L.Plan() == nil, "and no lure is used over it")
  c.TwichUI.RunCommand("fish lure auto off")
  W.enchant = nil
  Check(L.Plan() == nil, "lure assistance off: none applied")
  -- a lure that never lands is reported
  c.TwichUI.RunCommand("fish lure auto on")
  W.lureEnchant[LURE25] = nil
  W.Advance(2)
  W.Key("F")
  W.Advance(5)
  Check(F.noteCounts["lure-failed"] == 1, "a lure that did not appear is reported")
end

---------------------------------------------------------------------------
-- Equipment: snapshot, restore at the end of the session
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local G = F.Gear
  W.Wear(16, SWORD); W.Wear(17, SHIELD); W.Wear(18, BOW)
  W.Give(POLE, 1, 1); W.Give(POLE2, 1, 3)
  Check(G.FindPole().item == POLE2, "no preferred pole: the best quality one")
  c.TwichUI.RunCommand("fish pole " .. POLE)
  Check(G.FindPole().item == POLE, "the preferred pole")
  W.Key("F")
  Check(W.equipped[16] == POLE and W.equipped[17] == nil and W.equipped[18] == BOW, "the pole is on")
  local snap = G.Snapshot()
  Check(snap.slots[16].id == SWORD and snap.slots[17].id == SHIELD and snap.slots[16].link:find("item:" .. SWORD), "the snapshot has sword and shield, by id and link")
  W.Advance(3)
  Check(snap.slots[18] == nil, "an untouched slot is not kept")
  -- pressing again never replaces the snapshot
  Check(not G.Capture("pole"), "a snapshot already kept is never replaced")
  -- the session ends: gear goes back
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(W.equipped[16] == SWORD and W.equipped[17] == SHIELD, "the session ended: sword and shield are back")
  Check(G.State() == "none" and G.Snapshot() == nil, "nothing left to restore")
  Check(W.Find(POLE), "the pole is back in the bags")
end

---------------------------------------------------------------------------
-- Interrupted swaps, full bags, missing items, blocked restoration
---------------------------------------------------------------------------
do
  local c, W, F = Fresh({ bagSize = 2 })
  local G = F.Gear
  W.Wear(16, SWORD); W.Wear(17, SHIELD)
  W.Give(POLE)
  for i = 1, 9 do W.Give(3000 + i) end   -- the bags are full
  Check(W.Key("F") == nil and F.Action.last.why == "bags-full", "no room for the shield: the pole is not equipped")
  Check(W.errors[#W.errors]:find("bags are full"), "and the key says why")
  Check(G.Snapshot() == nil, "and nothing is captured")
  W.bags[4][2] = nil
  -- the swap is interrupted (the game didn't change anything)
  local realUse = W.UseBagItem
  W.UseBagItem = function() end
  W.Key("F")
  Check(G.Snapshot() ~= nil, "captured just before the press")
  W.Advance(3)
  Check(G.Snapshot() == nil and F.noteCounts["equip-failed"] == 1, "nothing changed: the snapshot is dropped and the failure noted")
  W.UseBagItem = realUse
  W.Key("F")
  Check(W.equipped[16] == POLE, "the next press works")
  W.Advance(3)
  -- restoration blocked by the client: kept pending, then done by the key's secure macro
  W.blockInsecure.equip = true
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(G.State() == "pending" and W.equipped[16] == POLE, "a blocked restoration is kept, not lost")
  Check(W.errors[#W.errors]:find("isn't fully back"), "and reported")
  Check(W.Key("F") == "macro" and W.equipped[16] == SWORD and W.equipped[17] == SHIELD, "the fishing key puts it back on your press")
  W.Advance(3)
  Check(G.State() == "none", "done")
  W.blockInsecure.equip = false
  -- an item that is gone (sold while fishing)
  W.Advance(2)
  W.Key("F")
  W.Advance(3)
  local b, s = W.Find(SHIELD); W.bags[b][s] = nil
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(W.equipped[16] == SWORD and G.Status().missing == 1 and G.State() == "pending", "what is there goes back; the missing shield is reported")
  Check(G.Forget() and G.State() == "none", "/tui fish forget drops it on purpose")
end

---------------------------------------------------------------------------
-- The player's own changes while fishing are kept
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local G = F.Gear
  W.Wear(16, SWORD); W.Wear(17, SHIELD)
  W.Give(POLE); W.Give(POLE2); W.Give(HAT)
  W.Key("F"); W.Advance(3)
  -- another pole: still fishing gear
  W.EquipFromBag(W.Find(POLE2))
  Check(G.Snapshot().slots[16] and not G.Snapshot().slots[16].kept, "a different pole is still to be put back")
  -- the player takes the pole off and puts a dagger... here, the shield back by hand: that slot is done
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(W.equipped[16] == SWORD and G.State() == "none", "back to the sword")
  -- now the player equips a different weapon while fishing
  W.Advance(2)
  W.Key("F"); W.Advance(3)
  W.items[2050] = { class = 2, sub = 15, loc = "INVTYPE_WEAPONMAINHAND" }
  W.Give(2050)
  W.EquipFromBag(W.Find(2050))
  Check(G.Snapshot().slots[16].kept, "the player's own weapon choice is kept")
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(W.equipped[16] == 2050, "and not overwritten by the restoration")
  Check(W.equipped[17] == SHIELD, "the shield, still TwichUI's to restore, goes back")
  Check(G.State() == "none", "and the record is clear")
end

---------------------------------------------------------------------------
-- An outfit (equipment set)
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  local G = F.Gear
  W.Wear(16, SWORD); W.Wear(17, SHIELD); W.Wear(1, 2004)
  W.Give(POLE); W.Give(HAT)
  W.sets.Fishing = { id = 7, items = { [16] = POLE, [1] = HAT } }
  c.TwichUI.RunCommand("fish outfit Fishing")
  Check(W.Key("F") == "equipmentset" and W.equipped[16] == POLE and W.equipped[1] == HAT, "the outfit goes on with one press")
  W.Advance(3)
  local snap = G.Snapshot()
  Check(snap.kind == "outfit" and snap.slots[1].id == 2004 and snap.slots[16].id == SWORD, "the snapshot holds every slot it changed")
  Check(W.Key("F") == "spell", "worn: the key casts")
  W.Key("F"); W.Advance(2)
  c.TwichUI.RunCommand("fish stop")
  W.Advance(3)
  Check(W.equipped[1] == 2004 and W.equipped[16] == SWORD and W.equipped[17] == SHIELD, "everything goes back")
  c.TwichUI.RunCommand("fish outfit Missing")
  Check(G.Outfit() == nil and select(3, G.Outfit()) == "missing", "an outfit that no longer exists is reported")
end

---------------------------------------------------------------------------
-- Reloads and disconnects
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.Wear(16, SWORD); W.Wear(17, SHIELD)
  W.Give(POLE)
  W.Key("F"); W.Advance(3)
  W.Key("F")   -- cast
  -- the game reloads with the line out and the pole on
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local c2, W2 = FishingClient({ db = saved, epoch = W.epoch + 5 })
  W2.Wear(16, POLE); W2.bags[0][1] = { id = SWORD, count = 1 }; W2.bags[0][2] = { id = SHIELD, count = 1 }
  W2.bound.F = KEY
  c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
  local F2 = c2.TwichUI.Fishing
  Check(F2.Session.Current() ~= nil and F2.Session.Current().id == 1, "the session continues after a reload")
  Check(F2.Gear.State() == "fishing" and F2.Gear.Snapshot().slots[16].id == SWORD, "the snapshot survived")
  -- a disconnect long enough to end the session: it ends at its last activity and the gear goes back
  local saved2 = FishRoundTrip(c2.TwichUIFishingDB)
  local c3, W3 = FishingClient({ db = saved2, epoch = W2.epoch + 3600 })
  W3.Wear(16, POLE); W3.bags[0][1] = { id = SWORD, count = 1 }; W3.bags[0][2] = { id = SHIELD, count = 1 }
  W3.bound.F = KEY
  c3.FireEvent("UPDATE_BINDINGS"); W3.Advance(1)
  local F3 = c3.TwichUI.Fishing
  Check(F3.Session.Current() == nil, "an old session ended at load")
  local last = F3.API.Sessions(1)[1]
  Check(last.ended == "idle" and last.stop < W3.epoch - 3000, "at its last activity, not at the reload")
  W3.Advance(3)
  Check(W3.equipped[16] == SWORD and W3.equipped[17] == SHIELD and F3.Gear.State() == "none", "and the gear went back after login")
  -- a restoration pending across a reload in combat waits for the end of combat
  local c4, W4 = FishingClient({ db = FishRoundTrip(c2.TwichUIFishingDB), epoch = W2.epoch + 3600 })
  W4.Wear(16, POLE); W4.bags[0][1] = { id = SWORD, count = 1 }; W4.bags[0][2] = { id = SHIELD, count = 1 }
  W4.bound.F = KEY
  W4.combat = true
  c4.FireEvent("UPDATE_BINDINGS"); W4.Advance(1)
  Check(W4.loads == 0, "not loaded in combat")
  W4.Peace(); W4.Advance(3)
  Check(W4.equipped[16] == SWORD and c4.TwichUI.Fishing.Gear.State() == "none", "loaded after combat, then restored")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_gear_lure")
