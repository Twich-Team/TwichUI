-- TwichUI Fishing: the fishing key (TwichUI_Fishing/Action.lua) and its launcher (!!!TwichUI/FishingLauncher.lua).
-- Decisions, state transitions, the reel override, the guard against casting by accident, combat restrictions, and loading.
-- Simulated client (tests/fishing_mock.lua): proves decisions and bookkeeping, not real secure behaviour.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"

---------------------------------------------------------------------------
-- Loading: nothing until a key is bound or /tui fish is typed; never in combat
---------------------------------------------------------------------------
do
  local c, W = FishingClient()
  Check(W.loads == 0 and not c.TwichUI.FishingLauncher.Loaded(), "nothing loads without a bound key")
  Check(c["BINDING_NAME_" .. KEY]:find("Fishing"), "the key has a readable name before the addon loads")
  Check(next(W.bound) == nil, "no key is ever bound by TwichUI")
  W.Fight()
  W.bound.F = KEY
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  Check(W.loads == 0, "a key bound in combat waits")
  W.Peace()
  Check(W.loads == 1 and c.TwichUI.FishingLauncher.Loaded(), "and loads when combat ends")
  Check(W.frames.TwichUIFishingButton and W.frames.TwichUIFishingButton.template == "SecureActionButtonTemplate", "the key's secure button exists")
  local b = W.frames.TwichUIFishingButton
  Check(b.clicks[1] == "LeftButtonUp" and b.attrs.useOnKeyDown == false, "acts once per press, on the release")
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  Check(W.loads == 1, "loaded once")
end
do
  local c, W = FishingClient()
  c.TwichUI.RunCommand("fish")
  Check(W.loads == 1, "/tui fish loads it")
  local c2, W2 = FishingClient({ missing = true })
  c2.TwichUI.RunCommand("fish")
  Check(not c2.TwichUI.FishingLauncher.Loaded() and c2.TwichUI.FishingLauncher.Snapshot().failed == "MISSING", "a missing folder is reported, not an error")
end

---------------------------------------------------------------------------
-- The decision, case by case (pure)
---------------------------------------------------------------------------
local c, W = FishingClient()
c.TwichUI.RunCommand("fish")
local F = c.TwichUI.Fishing
local A = F.Action
local function D(ctx)
  local base = { enabled = true, spell = 7620 }
  for k, v in pairs(ctx) do base[k] = v end
  return A.Decide(base)
end
local equip = { kind = "equip", bag = 0, slot = 1, item = POLE }
local lure = { kind = "lure", bag = 0, slot = 2, item = LURE50 }
local open = { kind = "open", bag = 0, slot = 3, item = CLAM, lot = 1 }
Check(D({}).kind == "cast", "nothing to prepare: cast")
Check(D({ enabled = false }).why == "off", "turned off: nothing")
Check(D({ combat = true, gear = equip }).why == "combat", "combat: nothing, whatever else is due")
Check(D({ line = "fishing", gear = equip }).why == "line-out", "a line is out: never a second cast or anything else")
Check(D({ line = "other" }).why == "busy", "channelling something else: nothing")
Check(D({ looting = true }).why == "looting", "a loot window is open: nothing")
Check(D({ guard = true }).why == "guard", "just after a line ended: nothing")
Check(D({ gear = equip, lure = lure, open = open }).kind == "equip", "the pole first")
Check(D({ gear = { kind = "none", why = "bags-full" }, lure = lure }).why == "bags-full", "bags too full to swap: say so")
Check(D({ gear = { kind = "none", why = "no-pole" } }).kind == "cast", "no pole: the game decides")
Check(D({ open = open, lure = lure }).kind == "open", "a queued container before the lure")
Check(D({ lure = lure }).kind == "lure", "then the lure")
Check(D({ restore = "/equipslot 16 item:1", gear = equip }).kind == "restore", "no session and gear to put back: restore first")
Check(D({ held = true, gear = equip, lure = lure }).kind == "cast", "saved data held: casting still works, nothing recorded is touched")
Check(D({ spell = false }).why == "no-spell", "Fishing not known")

---------------------------------------------------------------------------
-- One key through a whole cycle: equip, lure, cast, reel, cast
---------------------------------------------------------------------------
W.Wear(16, SWORD); W.Wear(17, SHIELD)
W.Give(POLE); W.Give(LURE50, 2)
W.bound.F = KEY
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
local states = {}
F.Subscribe("STATE", function(_, new) states[#states + 1] = new end)
Check(A.state == "idle", "idle before the first press")
Check(W.Key("F") == "item" and W.equipped[16] == POLE and A.last.kind == "equip", "press 1 equips the pole")
Check(F.Session.Current() ~= nil and A.state == "ready", "and begins the session")
Check(W.equipped[17] == nil and W.Find(SHIELD), "the shield went to the bags")
Check(W.Key("F") == "item" and W.enchant and A.last.kind == "lure", "press 2 applies the lure")
Check(W.calls.casts == 0, "nothing cast yet")
Check(W.Key("F") == "spell" and W.calls.casts == 1 and A.state == "line", "press 3 casts")
Check(W.overrides.F == "INTERACTTARGET", "while the line is out the key reels")
W.Advance(5)
Check(W.calls.casts == 1, "never casts again without a press")
Check(W.Key("F") == "reel" and A.state == "ready", "press 4 reels in")
Check(W.overrides.F == nil, "the override goes with the line")
Check(F.Session.Current().catches == 1, "one catch")
-- the guard: a second press straight after the catch never recasts
Check(W.Key("F") == nil and A.last.why == "guard" and W.calls.casts == 1, "an immediate second press does nothing")
W.Advance(1.1)
Check(W.Key("F") == "spell" and W.calls.casts == 2, "after the guard the key casts again")
-- reeling before a bite: the line comes in empty, counted as missed (not a catch)
W.bite = false
Check(W.Key("F") == "reel", "an early press reels")
W.Advance(2)
local s = F.Session.Current()
Check(s.catches == 1 and s.missed == 1 and s.casts == 2, "an empty line is missed, not caught")
W.bite = true
Check(states[1] == "ready" and states[2] == "line", "states: ready, line, ...")

---------------------------------------------------------------------------
-- The soft target is an NPC: the key does nothing rather than talk to it
---------------------------------------------------------------------------
W.Advance(2)
W.Key("F")
Check(W.overrides.F == "INTERACTTARGET", "line out")
W.softUnit, W.softObject = true, false
c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED")
Check(W.overrides.F == "CLICK TwichUIFishingIdle", "an NPC is the soft target: the key goes to the inert button")
Check(W.Key("F") == nil and W.channel ~= nil, "pressing then neither reels nor casts")
W.softUnit, W.softObject = false, true
c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED")
Check(W.overrides.F == "INTERACTTARGET", "a world object again: reels")
W.Key("F"); W.Advance(2)
Check(not F.Main.Listening("PLAYER_SOFT_INTERACT_CHANGED"), "the soft-target event is heard only while a line is out")

---------------------------------------------------------------------------
-- Interrupted and refused casts
---------------------------------------------------------------------------
local before = F.Session.Current()
local i0, f0 = before.interrupted, before.failed
W.Key("F")
c.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", W.channel[3], 7620)
c.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", W.channel[3], 7620)
W.StopLine(); W.Advance(2)
s = F.Session.Current()
Check(s.interrupted == i0 + 1 and s.missed == 1, "an interrupted line counts once and is not also missed")
W.failCast = true
W.Key("F")
W.failCast = false
s = F.Session.Current()
Check(s.failed == f0 + 1 and A.state == "ready", "a refused cast is counted and the key is ready again")
c.FireEvent("UNIT_SPELLCAST_FAILED", "player", "Cast-other", 133)
Check(F.Session.Current().failed == f0 + 1, "other spells' failures are not ours")
-- a duplicate channel start is one cast
local casts = s.casts
W.Advance(2)
W.Key("F")
c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", W.channel[3], 7620)
Check(F.Session.Current().casts == casts + 1, "a start event delivered twice is one cast")
W.Key("F"); W.Advance(2)

---------------------------------------------------------------------------
-- Combat: nothing changes in lockdown; the key can put your weapons back
---------------------------------------------------------------------------
W.Key("F")
Check(W.overrides.F == "INTERACTTARGET", "line out before the fight")
W.StopLine()
W.Fight()
Check(W.overrides.F == nil, "overrides removed as combat begins (while still allowed)")
Check(W.frames.TwichUIFishingButton.attrs.type == "macro", "the key is set up to put your weapons back")
Check(W.Key("F") == "macro" and W.equipped[16] == SWORD and W.equipped[17] == SHIELD, "a press in combat re-equips sword and shield")
Check(W.calls.casts == casts + 2, "and never casts")
Check(W.Key("F") == nil or A.last.why == "combat", "a second press in combat does nothing")
W.Peace()
Check(F.Gear.State() == "none", "your weapons are back: nothing left to restore")
W.Advance(2)
Check(W.Key("F") == "item" and W.equipped[16] == POLE, "after combat the key equips the pole again")
Check(F.Gear.Snapshot().slots[16].id == SWORD, "the snapshot is your sword again, never the pole")

-- with combatWeapons off the key does nothing in combat
c.TwichUI.RunCommand("fish combatweapons off")
W.Fight()
Check(W.frames.TwichUIFishingButton.attrs.type == nil, "combat weapons off: the key is inert in combat")
W.Key("F")
Check(W.equipped[16] == POLE and W.errors[#W.errors]:find("not during combat"), "a press says why")
W.Peace()
c.TwichUI.RunCommand("fish combatweapons on")

---------------------------------------------------------------------------
-- Interaction targeting is changed only when allowed, and put back
---------------------------------------------------------------------------
W.Advance(2)
W.Key("F")   -- lure? the pole has one; this casts
W.Advance(2)
if W.channel then W.Key("F"); W.Advance(2) end
Check(W.cvars.SoftTargetInteract == "1", "not allowed: never changed")
c.TwichUI.RunCommand("fish interact on")
W.Key("F")
Check(W.channel and W.cvars.SoftTargetInteract == "3" and W.cvars.SoftTargetInteractRange == "60", "allowed: set while the line is out")
W.Key("F"); W.Advance(2)
Check(W.cvars.SoftTargetInteract == "1" and W.cvars.SoftTargetInteractRange == "10", "and put back as it ends")
W.Key("F")
W.cvars.SoftTargetInteractRange = "30"   -- the player's own change mid-line
W.Key("F"); W.Advance(2)
Check(W.cvars.SoftTargetInteractRange == "30" and W.cvars.SoftTargetInteract == "1", "a value the player changed meanwhile is kept")
c.TwichUI.RunCommand("fish interact off")

---------------------------------------------------------------------------
-- The open key, and turning the whole thing off
---------------------------------------------------------------------------
W.bound.G = "CLICK TwichUIFishingOpen:LeftButton"
Check(W.Key("G") == nil and W.errors[#W.errors]:find("no fishing containers"), "nothing queued: the open key says so")
c.TwichUI.RunCommand("fish off")
W.Advance(2)
Check(W.Key("F") == nil and A.last.why == "off", "turned off: the key does nothing")
Check(not F.Main.Listening("LOOT_READY"), "and nothing is listened to")
c.TwichUI.RunCommand("fish on")
Check(F.Main.Listening("LOOT_READY"), "on again")

-- no unprompted chat: every printed line came from a command
for _, e in ipairs(W.errors) do Check(type(e) == "string", "messages are plain text") end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_action")
