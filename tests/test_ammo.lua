-- Hunter ammunition warning (ammo/): State.lua judges plain facts; Items.lua recognizes ammunition and keeps the
-- player's own list; Warning.lua reads the game, coalesces events and draws one line of text; Config.lua stores the
-- settings. A fake world stands in for the game, so this checks our logic, not the game: the in-game checks are
-- listed in docs/ammo-warning.md.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

---------------------------------------------------------------------------
-- A fake world: frames that record what they were told, events delivered only to what registered, the character's
-- equipment and bags
---------------------------------------------------------------------------
local frames = {}
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, events = {}, unitEvents = {}, points = {}, scale = 1, alpha = 1, calls = {} }
  frames[#frames + 1] = o
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
Methods = {
  Show = function(s) s.shown = true end,
  Hide = function(s) s.shown = false end,
  IsShown = function(s) return s.shown end,
  SetShown = function(s, v) s.shown = v and true or false end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end,
  GetScript = function(s, n) return s.scripts[n] end,
  RegisterEvent = function(s, e) s.events[e] = true end,
  RegisterUnitEvent = function(s, e, u) s.events[e] = true; s.unitEvents[e] = u end,
  UnregisterEvent = function(s, e) s.events[e] = nil; s.unitEvents[e] = nil end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end,
  GetStringWidth = function() return 180 end,
  GetStringHeight = function(s) return s.fontSize or 28 end,
  ClearAllPoints = function(s) s.points = {} end,
  SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetSize = function(s, w, h) s.width, s.height = w, h end,
  GetWidth = function(s) return s.width end,
  GetHeight = function(s) return s.height end,
  SetTexture = function(s, p) s.texture = p end,
  SetAlpha = function(s, a) s.alpha = a end,
  SetScale = function(s, v) s.scale = v end,
  GetScale = function(s) return s.scale end,
  GetEffectiveScale = function(s) return s.scale end,
  SetParent = function(s, p) s.parent = p end,
  EnableMouse = function(s, v) s.mouse = v and true or false end,
  RegisterForDrag = function(s) s.dragRegistered = true end,
  SetBackdrop = function(s, info) s.backdrop = info end,
  GetCenter = function(s) return s.center and s.center[1], s.center and s.center[2] end,
  StartMoving = function(s) s.moving = true end,
  StopMovingOrSizing = function(s) s.moving = false end,
  SetFont = function(s, path, size, flags) s.font = { path, size, flags }; s.fontSize = size; return true end,
}
c.CreateFrame = function(kind, name, parent, template)
  local f = Fake(kind)
  f.name, f.parent, f.template = name, parent, template
  return f
end
c.UIParent = Fake("UIParent")
c.UIParent.GetWidth = function() return 1024 end
c.UIParent.GetHeight = function() return 768 end
c.UIParent.GetCenter = function() return 512, 384 end
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- The items the client knows: class 6 is Projectile (subclass 2 arrows, 3 bullets, 0 something else), class 2 Weapon
-- (subclass 2 Bows, 3 Guns, 18 Crossbow, 19 Wand). 90001 and up are server items the client has no data for.
c.Enum = { ItemClass = { Weapon = 2, Projectile = 6 }, ItemWeaponSubclass = { Bows = 2, Guns = 3, Crossbow = 18, Thrown = 16, Wand = 19 } }
local ITEMS = {
  [2512] = { class = 6, sub = 2, icon = "arrow-icon" },   -- arrows
  [3030] = { class = 6, sub = 2, icon = "arrow2-icon" },  -- more arrows
  [2516] = { class = 6, sub = 3, icon = "bullet-icon" },  -- bullets
  [3033] = { class = 6, sub = 3, icon = "bullet2-icon" },
  [7000] = { class = 6, sub = 0, icon = "odd-icon" },     -- a projectile of a kind nothing here knows
  [2504] = { class = 2, sub = 2, icon = "bow-icon" },     -- a bow
  [2508] = { class = 2, sub = 3, icon = "gun-icon" },     -- a gun
  [2509] = { class = 2, sub = 18, icon = "xbow-icon" },   -- a crossbow
  [5000] = { class = 2, sub = 19, icon = "wand-icon" },   -- a wand
  [5001] = { class = 2, sub = 16, icon = "thrown-icon" }, -- a thrown weapon
  [8000] = { class = 0, sub = 0, icon = "potion-icon" },  -- not ammunition
}

local W, NOW, calls, sounds
local function World(class)
  W = { class = class or "HUNTER", uses = true, ranged = 2504, ammo = 2512, count = 100, combat = false, bags = {} }
  calls = { uses = 0, inv = 0, bag = 0, count = 0 }
  sounds = {}
end
World()
NOW = 1000
c.GetTime = function() return NOW end
c.UnitClassBase = function() return W.class end
c.UnitClass = function() return W.class, W.class end
c.UnitUsesAmmo = function() calls.uses = calls.uses + 1; return W.uses end
c.INVSLOT_AMMO, c.INVSLOT_RANGED = 0, 18
c.GetInventoryItemID = function(_, slot)
  calls.inv = calls.inv + 1
  if slot == 18 then return W.ranged end
  if slot == 0 then return W.ammo end
end
c.GetInventoryItemCount = function(_, slot) calls.count = calls.count + 1; if slot == 0 then return W.count end return 1 end
c.C_Item = {
  GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "type", "subtype", "", it.icon, it.class, it.sub
  end,
  GetItemIconByID = function(id) return ITEMS[id] and ITEMS[id].icon or nil end,
  GetItemNameByID = function() return nil end,
  RequestLoadItemDataByID = function() end,
}
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
c.C_Container = {
  GetContainerNumSlots = function(bag) return bag <= 12 and 6 or 0 end,   -- (bank bags answer too)
  GetContainerItemID = function(bag, slot) calls.bag = calls.bag + 1; return (W.bags[bag] or {})[slot] end,
}
c.UnitAffectingCombat = function() return W.combat end
c.InCombatLockdown = function() return W.combat end
c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel }; return true end
c.issecretvalue = function() return false end

local function Fire(event, ...)
  c.FireEvent(event, ...)   -- the shared bus (Core)
  local args = { ... }
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent and (not f.unitEvents[event] or f.unitEvents[event] == args[1]) then
      f.scripts.OnEvent(f, event, ...)
    end
  end
end
local function Settle() for _ = 1, 6 do FlushTimers() end end   -- every coalesced look and retry that is due

for _, f in ipairs({ "modules/Borders.lua", "modules/MenuStyle.lua", "modules/Media.lua", "ammo/Config.lua", "ammo/Items.lua",
  "ammo/State.lua", "ammo/Warning.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local AM, AI, AS, AW = R.Ammo, R.AmmoItems, R.AmmoState, R.AmmoWarning

local function RegisteredAmmoEvents()
  local n = 0
  for _, f in ipairs(frames) do
    for e in pairs(f.events) do
      if e == "PLAYER_EQUIPMENT_CHANGED" or e == "BAG_UPDATE_DELAYED" or e == "UNIT_INVENTORY_CHANGED" then n = n + 1 end
    end
  end
  return n
end
local function AllEvents()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function OnUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end
-- The words on screen, or nil when the warning is not shown.
local function Words()
  local f = AW.Frame()
  if f and f.shown then return f.text.text end
  return nil
end
local function On() R:SetEnabled("ammoWarning", true) end
local function Off() R:SetEnabled("ammoWarning", false) end
local function EnterWorld() Fire("PLAYER_ENTERING_WORLD"); Settle() end
local function Reset()   -- a clean slate between sections: off, no saved values, a Hunter with a bow and arrows
  Off()
  c.TwichUIDB.ui = {}
  AI.Reindex()
  World()
  AW.Refresh()
end
-- A change in the world, the way the game reports it: the events, then the coalesced look.
local function Changed(events)
  for _, e in ipairs(events or { "BAG_UPDATE_DELAYED" }) do Fire(e, e == "UNIT_INVENTORY_CHANGED" and "player" or (e == "PLAYER_EQUIPMENT_CHANGED" and 0 or nil)) end
  Settle()
end
local function Bag(slot, id) W.bags[0] = W.bags[0] or {}; W.bags[0][slot] = id end

---------------------------------------------------------------------------
-- 1. Off by default: nothing is built, listened for or scanned
---------------------------------------------------------------------------
do
  assert(c.TwichUIDB.modules.ammoWarning == false, "the warning is opt-in")
  assert(R.DEFAULT_MODULES.ammoWarning == false)
  assert(AW.Frame() == nil, "no frame while off")
  assert(RegisteredAmmoEvents() == 0 and AllEvents() == 0, "no event while off (" .. AllEvents() .. ")")
  assert(OnUpdates() == 0)
  EnterWorld()
  assert(AW.Frame() == nil and RegisteredAmmoEvents() == 0 and calls.inv == 0 and calls.bag == 0, "entering the world while off reads nothing")
  local s = AW.Snapshot()
  assert(not s.enabled and not s.running and s.events == 0)
end

---------------------------------------------------------------------------
-- 2. State.lua on its own: the judgement is pure
---------------------------------------------------------------------------
do
  local NIL = {}   -- (a key set to nil in a table constructor is not there to override)
  local function Judge(t)
    local input = { usesAmmo = true, hasRanged = true, needs = "arrow", equippedId = nil, equippedKind = nil, equippedCount = nil,
      carries = function() return false end }
    for k, v in pairs(t) do if v == NIL then input[k] = nil else input[k] = v end end
    return AS.Evaluate(input).state
  end
  assert(Judge({ usesAmmo = false }) == "inactive", "the client says no ammunition is used")
  assert(Judge({ usesAmmo = NIL }) == "unknown", "no answer is not an answer")
  assert(Judge({ hasRanged = false }) == "unknown", "ammunition used with no weapon is not settled")
  assert(Judge({}) == "outOfAmmo", "nothing selected, none carried")
  assert(Judge({ carries = function() return true, 2512 end }) == "noAmmo", "nothing selected, some carried")
  assert(Judge({ carries = function() return nil end }) == "unknown", "the bags could not be read")
  assert(Judge({ equippedId = 1, equippedKind = "arrow", equippedCount = 10 }) == "ok")
  assert(Judge({ equippedId = 1, equippedKind = "arrow", equippedCount = 0 }) == "outOfAmmo", "a selected stack of none")
  assert(Judge({ equippedId = 1, equippedKind = "arrow", equippedCount = NIL }) == "unknown", "a count that has not arrived")
  assert(Judge({ equippedId = 1, equippedKind = "bullet", equippedCount = 10 }) == "wrong")
  assert(Judge({ equippedId = 1, equippedKind = "other", equippedCount = 10 }) == "ok", "an unknown kind is never called wrong")
  assert(Judge({ equippedId = 1, equippedKind = NIL, equippedCount = 10 }) == "ok", "an unrecognized item is never called wrong")
  assert(Judge({ equippedId = 1, equippedKind = "bullet", equippedCount = 10, needs = NIL }) == "ok", "a weapon of unknown type judges nothing")
  local out = AS.Evaluate({ usesAmmo = true, hasRanged = true, needs = "arrow", carries = function() return true, 777 end })
  assert(out.state == "noAmmo" and out.iconItem == 777, "the icon comes from what is carried")
  -- a bag is not read when something is selected
  local read = 0
  AS.Evaluate({ usesAmmo = true, hasRanged = true, needs = "arrow", equippedId = 1, equippedKind = "arrow", equippedCount = 5,
    carries = function() read = read + 1; return false end })
  assert(read == 0, "the bags are read only when nothing is selected")
  -- which ammunition a weapon takes
  assert(AS.NeedsFor(2, 2) == "arrow" and AS.NeedsFor(2, 18) == "arrow" and AS.NeedsFor(2, 3) == "bullet")
  assert(AS.NeedsFor(2, 19) == nil and AS.NeedsFor(2, 16) == nil and AS.NeedsFor(4, 2) == nil and AS.NeedsFor(nil, nil) == nil)
  -- visibility policy
  assert(AS.Visible("noAmmo", "equipped", false) and AS.Visible("wrong", "equipped", false))
  assert(not AS.Visible("noAmmo", "combat", false) and AS.Visible("noAmmo", "combat", true))
  assert(not AS.Visible("ok", "equipped", true) and not AS.Visible("inactive", "combat", true) and not AS.Visible("unknown", "equipped", true))
  assert(AS.MESSAGES.noAmmo == "NO AMMO EQUIPPED" and AS.MESSAGES.outOfAmmo == "OUT OF AMMO" and AS.MESSAGES.wrong == "WRONG AMMO EQUIPPED")
end

---------------------------------------------------------------------------
-- 3. Not a Hunter: no warning and no inventory monitoring
---------------------------------------------------------------------------
do
  Reset(); World("MAGE")
  W.ammo, W.ranged = nil, nil
  On(); EnterWorld()
  assert(RegisteredAmmoEvents() == 0, "no inventory event on another class")
  assert(AllEvents() == 0 and AW.Frame() == nil, "nothing at all on another class")
  Fire("BAG_UPDATE_DELAYED"); Fire("PLAYER_EQUIPMENT_CHANGED", 0); Settle()
  assert(calls.inv == 0 and calls.bag == 0 and calls.uses == 0, "no ammunition is read on another class")
  assert(Words() == nil)
  local s = AW.Snapshot()
  assert(s.enabled and not s.hunter and not s.running and s.events == 0)
  -- the class is localized elsewhere: the token is what counts
  World("HUNTER"); AW.Refresh(); EnterWorld()
  assert(RegisteredAmmoEvents() == 3, "a Hunter listens (" .. RegisteredAmmoEvents() .. ")")
  Off()
  assert(RegisteredAmmoEvents() == 0 and AllEvents() == 0, "off again: nothing is registered")
end

---------------------------------------------------------------------------
-- 4. A Hunter: the warning states, from what the game reports
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  assert(Words() == nil and AW.Snapshot().state == "ok", "bow and arrows: no warning")
  assert(AW.Frame() == nil, "no frame is built until there is something to show")
  assert(calls.bag == 0, "the bags are not read while ammunition is selected")

  -- the ammunition is gone from the slot and the bags hold some that fits: NO AMMO EQUIPPED
  W.ammo, W.count = nil, nil
  Bag(1, 2512)
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "NO AMMO EQUIPPED", "arrows in the bags, none selected: " .. tostring(Words()))
  assert(AW.Frame().icon.texture == "arrow-icon", "the icon is the ammunition that could be selected")
  assert(AW.Frame().mouse == false, "the warning takes no clicks")

  -- selected again
  W.ammo, W.count = 2512, 40
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil and AW.Frame().shown == false, "compatible ammunition is selected: gone")

  -- the selected stack is used up
  W.count = 0
  Changed({ "UNIT_INVENTORY_CHANGED" })
  assert(Words() == "OUT OF AMMO", "a stack of none")
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed()
  assert(Words() == "OUT OF AMMO", "nothing selected, nothing carried")

  -- a bow with only bullets: they do not fit
  Bag(2, 2516)
  Changed()
  assert(Words() == "OUT OF AMMO", "a bow cannot use the bullets in the bags")
  -- a gun can
  W.ranged = 2508
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "NO AMMO EQUIPPED", "a gun can use them")
  -- a gun with only arrows
  W.bags = {}; Bag(1, 2512)
  Changed()
  assert(Words() == "OUT OF AMMO", "a gun cannot use arrows")
  -- a crossbow takes arrows
  W.ranged = 2509
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "NO AMMO EQUIPPED", "a crossbow takes arrows")

  -- the wrong kind selected
  W.ranged, W.ammo, W.count = 2504, 2516, 80
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED", "bullets selected for a bow")
  W.ranged, W.ammo = 2508, 2512
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED", "arrows selected for a gun")
  -- a weapon swap puts it right
  W.ranged = 2504
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil, "the bow takes the arrows")
  -- and so does an ammunition swap
  W.ammo, W.count = 2516, 30
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED")
  W.ranged = 2508
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil, "the gun takes the bullets")

  -- another projectile subclass is never called wrong, and never counted as a supply
  W.ammo, W.count = 7000, 10
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil, "an unknown kind of projectile selected judges nothing")
  W.ammo, W.count, W.bags = nil, nil, {}; Bag(1, 7000)
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO", "an unknown kind of projectile in the bags is not a supply")
  W.bags = {}; Bag(1, 8000)
  Changed()
  assert(Words() == "OUT OF AMMO", "an item that is not ammunition is not a supply")
end

---------------------------------------------------------------------------
-- 5. No ranged weapon, and a weapon that takes no ammunition
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  W.ranged, W.uses, W.ammo, W.count = nil, false, nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil, "no ranged weapon: no missing-ammunition warning")
  W.ranged, W.uses = 5000, false   -- a wand: the client says it takes none
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil and AW.Snapshot().state == "inactive", "a weapon that takes no ammunition")
  W.ranged = 5001                  -- a thrown weapon
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil)
  assert(calls.bag == 0, "the bags are not read for a weapon that takes none")
  -- the client's word wins over any table of ours: a bow it says takes none shows nothing
  W.ranged, W.uses = 2504, false
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil)
  W.uses = true
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO", "now it takes ammunition, and there is none")
end

---------------------------------------------------------------------------
-- 6. Several stacks: the slot's count is the whole supply
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  W.bags = {}; Bag(1, 2512); Bag(2, 2512); Bag(3, 2512)   -- stacks in the bags as well as the selected one
  W.count = 600
  local before = calls.bag
  Changed({ "BAG_UPDATE_DELAYED" })
  assert(Words() == nil, "plenty of arrows over several stacks")
  assert(calls.bag == before, "the bags are not added up when the slot has the count")
  -- the last of the supply goes: the slot empties and the bags are empty with it
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO")
  -- bank, mail and the auction house are not bags: nothing outside the carried bags counts
  W.bags[9] = { [1] = 2512 }
  Changed()
  assert(Words() == "OUT OF AMMO", "a bank bag is not a carried bag")
end

---------------------------------------------------------------------------
-- 7. Information that is not there yet is never a warning
---------------------------------------------------------------------------
do
  Reset(); On()
  -- login: the client has not told us whether the weapon takes ammunition
  W.uses = nil
  Fire("PLAYER_ENTERING_WORLD"); Settle()
  assert(Words() == nil, "no answer, no warning")
  assert(AW.Snapshot().retries >= 1 and AW.Snapshot().retries <= 3, "it looks again, a bounded number of times")
  for _ = 1, 20 do FlushTimers() end
  assert(AW.Snapshot().retries == 3 and Words() == nil, "it gave up without concluding anything")
  local looks = AW.Snapshot().looks
  for _ = 1, 10 do FlushTimers() end
  assert(AW.Snapshot().looks == looks, "no further looks: nothing polls")

  -- the answer arrives with the next event
  W.uses = true
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO", "now it is known")

  -- an ammunition count that has not arrived is not "none"
  Reset(); On(); EnterWorld()
  W.count = nil   -- selected, count not readable
  Changed({ "UNIT_INVENTORY_CHANGED" })
  assert(Words() == nil, "a count that is not there is not a depleted stack")
  -- a warning on screen stays while the data is missing, and does not flicker off
  W.count, W.ammo = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO")
  W.uses = nil
  Fire("BAG_UPDATE_DELAYED"); FlushTimers()
  assert(Words() == "OUT OF AMMO", "what is shown stays while the data is missing")
  for _ = 1, 20 do FlushTimers() end
  assert(Words() == nil, "and goes once the data never comes: nothing is confirmed")
end

---------------------------------------------------------------------------
-- 8. Visibility: whenever it applies, or only in combat
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  assert(AM.Get("show") == "equipped", "the default shows it out of combat too, to fix before a pull")
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO", "out of combat")
  W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
  assert(Words() == "OUT OF AMMO", "and in combat")

  W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
  assert(AM.Set("show", "combat"))
  assert(Words() == nil, "combat only: hidden out of combat")
  assert(AW.Snapshot().state == "outOfAmmo", "the problem is still known")
  W.combat = true; Fire("PLAYER_REGEN_DISABLED"); Settle()
  assert(Words() == "OUT OF AMMO", "combat only: shown when combat starts")
  W.combat = false; Fire("PLAYER_REGEN_ENABLED"); Settle()
  assert(Words() == nil, "combat only: hidden when it ends")
  assert(AM.Set("show", "equipped"))
  assert(Words() == "OUT OF AMMO")
  assert(not AM.Set("show", "never") and not AM.Set("nonsense", true), "an unknown choice or key is refused")
end

---------------------------------------------------------------------------
-- 9. Bursts: one look, no flicker, one sound
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  local before = AW.Snapshot().looks
  for _ = 1, 50 do Fire("BAG_UPDATE_DELAYED"); Fire("UNIT_INVENTORY_CHANGED", "player") end
  Fire("PLAYER_EQUIPMENT_CHANGED", 5)   -- a slot that is not ours: dropped before any work
  assert(AW.Snapshot().looks == before, "nothing is read until the coalescing timer runs")
  FlushTimers()
  assert(AW.Snapshot().looks == before + 1, "a burst of 101 events is one look (" .. (AW.Snapshot().looks - before) .. ")")
  local calls0 = calls.inv
  Fire("PLAYER_EQUIPMENT_CHANGED", 5); Fire("PLAYER_EQUIPMENT_CHANGED", 13); FlushTimers()
  assert(calls.inv == calls0 and AW.Snapshot().looks == before + 1, "other equipment slots are ignored")
  -- the unit event is the player's only
  Fire("UNIT_INVENTORY_CHANGED", "target"); FlushTimers()
  assert(AW.Snapshot().looks == before + 1, "another unit's inventory is not ours")
  -- a swap that settles back to fine shows nothing
  W.ammo, W.count = nil, nil
  Fire("PLAYER_EQUIPMENT_CHANGED", 0)
  W.ammo, W.count = 3030, 60
  Fire("PLAYER_EQUIPMENT_CHANGED", 0)
  FlushTimers()
  assert(Words() == nil and AW.Snapshot().state == "ok", "an ammunition swap judged after it settled never showed a warning")
end

---------------------------------------------------------------------------
-- 10. Sound: off by default, once per problem, never at login, never in the preview
---------------------------------------------------------------------------
do
  Reset(); On()
  assert(AM.Get("sound") == false and AM.DEFAULTS.sound == false, "visual only by default")
  EnterWorld()
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO" and #sounds == 0, "no sound unless it is turned on")

  assert(AM.Set("sound", true))
  assert(#sounds == 0, "turning it on while a problem exists is not a transition")
  W.ammo, W.count = 2512, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  NOW = NOW + 60
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(#sounds == 1, "a problem that begins plays once (" .. #sounds .. ")")
  assert(sounds[1][2] == "SFX" and type(sounds[1][1]) == "string" and sounds[1][1]:find("TwichUI_Notification"), "the default sound on the default channel")
  for _ = 1, 10 do Changed() end
  assert(#sounds == 1, "bag events while it is missing do not repeat it")
  -- fixed and broken again straight away: held back
  W.ammo, W.count = 2512, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  NOW = NOW + 1
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(#sounds == 1 and AW.Snapshot().soundsHeld == 1, "a second problem within five seconds is held back")
  -- later it plays again
  W.ammo, W.count = 2512, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  NOW = NOW + 10
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(#sounds == 2, "and after the gap it plays again")
  -- a different problem while one is showing is not a new beginning
  W.ammo, W.count = 2516, 5
  NOW = NOW + 10
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED" and #sounds == 2, "one problem turning into another is not a new alert")

  -- the choice and the channel
  assert(AM.Set("soundChannel", "Master") and AM.Set("soundName", "Single Knell"))
  W.ammo, W.count = 2512, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  NOW = NOW + 10
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(#sounds == 3 and sounds[3][2] == "Master" and sounds[3][1]:find("Single_Knell"))
  assert(AM.Set("soundName", "A sound nobody has"))
  W.ammo, W.count = 2512, 20
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  NOW = NOW + 10
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(#sounds == 4 and sounds[4][1]:find("TwichUI_Notification"), "a sound that has gone plays the default")

  -- login: the first look after entering the world is quiet even with the sound on
  Reset(); AM.Set("sound", true); On()
  local n = #sounds   -- (Reset starts a new world, with no sounds played)
  W.ammo, W.count = nil, nil
  EnterWorld()
  assert(Words() == "OUT OF AMMO" and #sounds == n, "a problem found at login is shown, not announced")
  -- the explicit test plays once and is the only way the preview side makes a sound
  assert(AW.TestSound() == true and #sounds == n + 1)
  AW.PreviewStart(); AW.PreviewNext(); AW.PreviewStop()
  assert(#sounds == n + 1, "the preview never plays a sound")
  Reset()
end

---------------------------------------------------------------------------
-- 11. Custom ammunition: the list, recognition, and what registering does not mean
---------------------------------------------------------------------------
do
  Reset()
  assert(AI.Count() == 0 and #AI.List() == 0)
  -- input
  local ok, how, kind = AI.Add("90001", "bullet")
  assert(ok and how == "added" and kind == "bullet" and AI.Count() == 1)
  ok, how, kind = AI.Add("|cff1eff00|Hitem:90002::::::::70:::::|h[Strange Shot]|h|r", "arrow")
  assert(ok and how == "added" and kind == "arrow" and AI.Entry(90002).kind == "arrow", "an item link works")
  ok, how, kind = AI.Add(90001, "arrow")
  assert(ok and how == "exists" and kind == "bullet" and AI.Count() == 2, "a duplicate changes nothing")
  for _, bad in ipairs({ "", "abc", "0", "-5", "1.5", "99999999999", false, {}, "item:" }) do
    local good = AI.Add(bad, "arrow")
    assert(good == false, "invalid input refused: " .. tostring(bad))
  end
  assert(AI.Add(90003, "grenade") == false, "an unknown kind is refused")
  assert(AI.Count() == 2, "refused input leaves the list alone")
  -- the client's own classification is the default kind
  ok, how, kind = AI.Add(3033)
  assert(ok and kind == "bullet", "the client's classification is used when no kind is given")
  ok, how, kind = AI.Add(90004)
  assert(ok and kind == "arrow", "arrows when nothing says otherwise")
  -- correcting a classification
  assert(AI.SetKind(90004, "bullet") and AI.Entry(90004).kind == "bullet")
  assert(AI.SetKind(90004, "bullet") == true, "the same kind again is fine")
  assert(AI.SetKind(90004, "grenade") == false and AI.SetKind(424242, "arrow") == false)
  -- removal
  assert(AI.Remove(90004) == true and AI.Entry(90004) == nil and AI.Remove(90004) == false)
  -- the bound
  for i = 1, AI.MAX do AI.Add(100000 + i, "arrow") end
  assert(AI.Count() == AI.MAX, "the list is bounded")
  assert(AI.Add(777777, "arrow") == false)
  for i = 1, AI.MAX do AI.Remove(100000 + i) end

  -- recognition: the player's registration, then the client
  assert(AI.Kind(90001) == "bullet" and select(2, AI.Kind(90001)) == "custom")
  assert(AI.Kind(2512) == "arrow" and select(2, AI.Kind(2512)) == "client")
  assert(AI.Kind(8000) == nil and AI.Kind(31337) == nil, "not ammunition, or unknown to the client")
  assert(AI.Known(31337) == false and AI.Known(2512) == true, "the client says what it has no data for")

  -- an item the client has no data for, registered: a gun with it selected is fine, a bow is wrong
  Reset()
  AI.Add(90001, "bullet")
  On(); EnterWorld()
  W.ranged, W.ammo, W.count = 2508, 90001, 25
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil, "registered bullets are bullets for a gun")
  W.ranged = 2504
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED", "and wrong for a bow")
  AI.SetKind(90001, "arrow")
  assert(Words() == nil, "correcting the classification takes effect at once")
  AI.Remove(90001)
  assert(Words() == nil, "an item nobody recognizes is never called wrong")
  -- counted as a supply from the bags
  AI.Add(90002, "arrow")
  W.ammo, W.count, W.bags = nil, nil, {}
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO")
  Bag(3, 90002)
  Changed()
  assert(Words() == "NO AMMO EQUIPPED", "registered arrows in the bags are a supply for a bow")
  -- registering does not imply anything: with the item not carried or equipped, the warning stands
  W.bags = {}
  Changed()
  assert(Words() == "OUT OF AMMO", "registering an item is not having it")
  -- the registration wins over the client when they differ (a correction)
  AI.Add(2512, "bullet")
  assert(AI.Kind(2512) == "bullet")
  Bag(1, 2512)
  Changed()
  assert(Words() == "OUT OF AMMO", "arrows registered as bullets are not a supply for a bow")
  AI.Remove(2512)
  assert(Words() == "NO AMMO EQUIPPED", "removing it goes back to the client's word")
  Reset()
end

---------------------------------------------------------------------------
-- 12. Disabling, and a profile change, put everything away at once
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "OUT OF AMMO")
  Fire("BAG_UPDATE_DELAYED")           -- a look is queued ...
  Off()                                -- ... and the warning is switched off before it runs
  local snapshot = { inv = calls.inv, bag = calls.bag, uses = calls.uses }
  assert(Words() == nil and AW.Frame().shown == false, "off hides it at once")
  assert(RegisteredAmmoEvents() == 0 and AllEvents() == 0, "off unregisters everything")
  Settle()
  assert(calls.inv == snapshot.inv and calls.bag == snapshot.bag and calls.uses == snapshot.uses, "the queued look did nothing")
  assert(OnUpdates() == 0, "no OnUpdate handler exists")
  for _ = 1, 5 do FlushTimers() end
  assert(calls.inv == snapshot.inv, "nothing polls after it is off")
  local s = AW.Snapshot()
  assert(not s.running and s.state == "inactive" and s.shown == nil and not s.preview)

  -- back on
  On()
  assert(Words() == "OUT OF AMMO" and RegisteredAmmoEvents() == 3, "on again: it looks at once")

  -- a profile change that turns it off and one that turns it on
  c.TwichUIDB.modules.ammoWarning = false
  R.Profiles.Refresh("test")
  assert(Words() == nil and RegisteredAmmoEvents() == 0, "a profile without it turns it off")
  c.TwichUIDB.modules.ammoWarning = true
  c.TwichUIDB.ui.ammo = { show = "combat", fontSize = 40 }
  R.Profiles.Refresh("test")
  assert(AM.Get("show") == "combat" and AM.Get("fontSize") == 40 and Words() == nil, "a profile that shows it only in combat")
  c.TwichUIDB.ui.ammo = {}
  R.Profiles.Refresh("test")
  assert(Words() == "OUT OF AMMO", "back to the default policy")
  -- the list of another profile
  AI.Add(90001, "bullet")
  c.TwichUIDB.ui.ammoCustom = { items = { { id = 90005, kind = "arrow" } } }
  R.Profiles.Refresh("test")
  assert(AI.Kind(90005) == "arrow" and AI.Kind(90001) == nil, "the list follows the profile")
  Reset()
end

---------------------------------------------------------------------------
-- 13. Settings: validated, defaults only where missing, reset
---------------------------------------------------------------------------
do
  Reset()
  assert(AM.Get("fontSize") == 28 and AM.Get("icon") == true and AM.Get("scale") == 100)
  assert(AM.Set("icon", false) and AM.Get("icon") == false, "a saved false is a value")
  assert(not AM.Set("fontSize", 5) and not AM.Set("fontSize", 28.5) and not AM.Set("textColor", "red") and not AM.Set("font", "bad|name"))
  assert(AM.Set("fontSize", 40) and AM.Set("textColor", "ffff0000") and AM.Get("textColor") == "ffff0000")
  -- a damaged saved value reads as the default and is not erased
  c.TwichUIDB.ui.ammo.opacity = "lots"
  assert(AM.Get("opacity") == 100 and c.TwichUIDB.ui.ammo.opacity == "lots")
  AM.ResetSettings()
  assert(AM.Get("fontSize") == 28 and AM.Get("icon") == true and AM.Get("textColor") == "fff0e8d2")
  -- the reset leaves the place, the look and the list
  AM.SetPosition(10, 20); AM.Look.Set("bgTexture", "solid"); AI.Add(90001, "bullet")
  AM.ResetSettings()
  assert(AM.HasPosition() and AM.Look.Get("bgTexture") == "solid" and AI.Count() == 1)
  assert(AM.Look.DEFAULTS.bgTexture == "none" and AM.Look.DEFAULTS.borderTexture == "none", "nothing is drawn behind the words by default")
  Reset()
end

---------------------------------------------------------------------------
-- 14. Place: default, clamp, move, reset; the frame takes no clicks except to be moved
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  local x, y = AM.Position()
  assert(x == 0 and y == 140 and not AM.HasPosition(), "near the centre by default")
  assert(not AM.SetPosition(1e9, 0) and not AM.SetPosition(0 / 0, 0) and not AM.SetPosition("a", 1), "unusable places are refused")
  local cx, cy = AM.ClampPosition(5000, -5000, 1024, 768)
  assert(cx == 492 and cy == -374, "kept on the screen: " .. cx .. "," .. cy)

  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  local f = AW.Frame()
  assert(f.points[1][1] == "CENTER" and f.points[1][4] == 0 and f.points[1][5] == 140, "placed from the centre")
  AM.SetPosition(-200, 90)
  f = AW.Frame()
  assert(f.points[1][4] == -200 and f.points[1][5] == 90, "a saved place moves it")
  AM.Set("scale", 200)
  assert(f.scale == 2 and f.points[1][4] == -100 and f.points[1][5] == 45, "the place is in screen units at any scale")

  -- a border is drawn in whole pixels for the scale the frame has: a UI scale change draws the look again, and the
  -- events for it are wanted only while the warning is on screen
  local function ScaleEvents()
    local n = 0
    for _, fr in ipairs(frames) do if fr.events.UI_SCALE_CHANGED or fr.events.DISPLAY_SIZE_CHANGED then n = n + 1 end end
    return n
  end
  local drawn, applyInset = 0, AM.Look.ApplyInset
  AM.Look.ApplyInset = function(fr) drawn = drawn + 1; return applyInset(fr) end
  assert(ScaleEvents() == 1, "listening for a scale change while shown")
  Fire("UI_SCALE_CHANGED"); Fire("DISPLAY_SIZE_CHANGED")
  assert(drawn == 2, "the look is drawn again for the new scale (" .. drawn .. ")")
  W.ammo, W.count = 2512, 10
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == nil and ScaleEvents() == 0, "and not once it is hidden")
  Fire("UI_SCALE_CHANGED")
  assert(drawn == 2, "a hidden warning draws nothing")
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  AM.Look.ApplyInset = applyInset

  -- unlocking: a sample with a handle that takes the mouse; nothing else does
  assert(AW.PositionStart() == true and AW.PositioningActive())
  local handle
  for _, fr in ipairs(frames) do if fr.dragRegistered then handle = fr end end
  assert(handle and handle.shown and handle.mouse == true, "the handle takes the mouse while unlocked")
  assert(f.mouse == false, "the frame itself never does")
  assert(f.text.text == "NO AMMO EQUIPPED" or f.text.text == AS.MESSAGES.noAmmo, "a sample is shown")
  -- a drag
  f.center = { 612 / 2, 400 }   -- (the frame's centre in its own, scaled, units)
  handle.scripts.OnDragStart()
  assert(f.moving == true)
  handle.scripts.OnDragStop()
  assert(f.moving == false and AM.HasPosition(), "the drop is saved")
  local sx, sy = AM.Position()
  assert(sx == (306 * 2 - 512) and sy == (400 * 2 - 384), "saved as screen units from the centre (" .. sx .. "," .. sy .. ")")
  handle.scripts.OnMouseUp(handle, "RightButton")
  assert(not AW.PositioningActive() and handle.shown == false and handle.mouse == false, "right-click locks it")
  assert(Words() == "NO AMMO EQUIPPED" or Words() == "OUT OF AMMO", "the real warning is back (" .. tostring(Words()) .. ")")
  AW.ResetPosition()
  assert(not AM.HasPosition() and select(2, AM.Position()) == 140, "reset puts the default back")
  AM.Set("scale", 100)
  Reset()
end

---------------------------------------------------------------------------
-- 15. Preview: any class, isolated from the real state, cleaned up
---------------------------------------------------------------------------
do
  Reset()
  assert(AW.PreviewStart() == false, "the preview needs the feature on")
  On()
  World("MAGE"); AW.Refresh()   -- not a Hunter: the preview still works
  assert(AW.PreviewStart() == true and AW.PreviewActive())
  assert(Words() == "NO AMMO EQUIPPED", "first sample")
  assert(AW.PreviewNext() and Words() == "OUT OF AMMO")
  assert(AW.PreviewNext() and Words() == "WRONG AMMO EQUIPPED")
  assert(AW.PreviewNext() and Words() == "NO AMMO EQUIPPED", "it cycles")
  assert(AW.Frame().mouse == false, "a preview is click-through")
  assert(AW.Snapshot().shown == nil and AW.Snapshot().state == "inactive", "the preview is not a real state")
  AW.PreviewStop()
  assert(Words() == nil and not AW.PreviewActive(), "stopping hides it")
  assert(AW.PreviewNext() == false)

  -- on a Hunter the real warning is kept underneath
  World("HUNTER"); W.ammo, W.count = nil, nil
  AW.Refresh(); EnterWorld()
  assert(Words() == "OUT OF AMMO")
  AW.PreviewStart(); AW.PreviewNext()   -- shows "OUT OF AMMO" sample (index 2), then 3 more:
  AW.PreviewNext()
  assert(Words() == "WRONG AMMO EQUIPPED", "the sample, not the real state")
  W.ammo, W.count = 2512, 10
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  assert(Words() == "WRONG AMMO EQUIPPED", "the real state changes underneath")
  AW.PreviewStop()
  assert(Words() == nil, "and ending the preview shows the truth at once")

  -- it ends with the settings window, and when combat starts
  AW.PreviewStart()
  R.OnSettingsClosed(function() end)
  assert(AW.PreviewActive())
  -- (SettingsLauncher calls the registered closers; invoke what it would)
  if R.SettingsClosed then R.SettingsClosed() end
  AW.PreviewStop()
  AW.PreviewStart()
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(not AW.PreviewActive() and Words() == nil, "combat ends a preview")
  assert(AW.PreviewStart() == false, "and no preview starts in combat")
  assert(AW.PositionStart() == false)
  W.combat = false; Fire("PLAYER_REGEN_ENABLED")
  -- unlocked, then combat
  AW.PositionStart()
  assert(AW.PositioningActive())
  W.combat = true; Fire("PLAYER_REGEN_DISABLED")
  assert(not AW.PositioningActive(), "combat locks it")
  W.combat = false
  assert(AW.PositionStart() and AW.PreviewActive() and AW.PositioningActive())
  Off()
  assert(not AW.PreviewActive() and not AW.PositioningActive() and Words() == nil, "off ends both")
  Reset()
end

---------------------------------------------------------------------------
-- 16. Sharing: the settings travel, the place does not, the list is checked and merged
---------------------------------------------------------------------------
do
  Reset()
  local TC = R.TwichConfig
  local ids = {}
  for _, g in ipairs(TC.Groups()) do ids[g.id] = g end
  assert(ids.ammo and ids.ammoLook and ids.ammoCustom, "the groups exist")
  assert(ids.ammo.complete and ids.ammoLook.complete, "their registries are all there")
  assert(TC.LOCAL["ui.ammoPosition"] == "place", "the place stays on this computer")
  local shared = {}
  for _, f in ipairs(ids.ammo.fields) do shared[f.key] = true end
  for key in pairs(AM.DEFAULTS) do assert(shared[key], key .. " is shared") end
  assert(shared.ammoWarning, "the switch is shared")

  local L = ids.ammoCustom.custom
  assert(L.usable() and L.count() == 0 and L.export() == nil, "an empty list shares nothing")
  AI.Add(90001, "bullet"); AI.Add(90002, "arrow")
  local exported = L.export()
  assert(#exported.items == 2 and exported.items[1].id == 90001 and exported.items[2].kind == "arrow")
  -- a share is checked
  assert(L.clean({ items = { { id = 5, kind = "arrow" }, { id = 6, kind = "bullet" } } }))
  assert(L.clean(nil) == nil and L.clean({}) == nil and L.clean({ items = {} }) == nil, "shape and empty")
  assert(L.clean({ items = { { id = 5, kind = "grenade" } } }) == nil, "an unknown kind")
  assert(L.clean({ items = { { id = 0, kind = "arrow" } } }) == nil and L.clean({ items = { { id = "5", kind = "arrow" } } }) == nil, "an unusable id")
  assert(L.clean({ items = { { id = 5, kind = "arrow" }, { id = 5, kind = "bullet" } } }) == nil, "a repeated id")
  assert(L.clean({ items = { x = { id = 5, kind = "arrow" } } }) == nil, "not a list")
  local big = {}
  for i = 1, AI.MAX + 1 do big[i] = { id = 500 + i, kind = "arrow" } end
  assert(L.clean({ items = big }) == nil, "too many")
  -- merging: the share sets what it names, keeps the rest
  local clean = L.clean({ items = { { id = 90001, kind = "arrow" }, { id = 90009, kind = "bullet" } } })
  local plan = L.plan(clean)
  assert(#plan == 2 and plan.full == 0)
  local rows = L.review(clean)
  assert(#rows == 2)
  local undo = L.apply(clean, plan)
  AI.Reindex()
  assert(AI.Entry(90001).kind == "arrow" and AI.Entry(90009).kind == "bullet" and AI.Entry(90002).kind == "arrow", "merged; nothing removed")
  assert(AI.Count() == 3)
  assert(L.restore(undo) == 2)
  AI.Reindex()
  assert(AI.Entry(90001).kind == "bullet" and AI.Entry(90009) == nil and AI.Count() == 2, "the undo puts the list back")
  Reset()
end

---------------------------------------------------------------------------
-- 17. Nothing runtime is saved
---------------------------------------------------------------------------
do
  Reset(); On(); EnterWorld()
  W.ammo, W.count = nil, nil
  Changed({ "PLAYER_EQUIPMENT_CHANGED" })
  AW.PreviewStart(); AW.PreviewNext()
  AM.SetPosition(5, 5)
  AI.Add(90001, "bullet")
  local function Scan(t, path, seen)
    seen = seen or {}
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      local p = path .. "." .. tostring(k)
      local tv = type(v)
      assert(tv ~= "function" and tv ~= "userdata" and tv ~= "thread", "no runtime object is saved: " .. p)
      if tv == "table" then
        assert(getmetatable(v) == nil, "no frame is saved: " .. p)
        Scan(v, p, seen)
      end
      assert(not tostring(k):find("shown") and not tostring(k):find("preview") and not tostring(k):find("state") and not tostring(k):find("pending"), "no state is saved: " .. p)
    end
  end
  Scan(c.TwichUIDB.ui, "ui")
  assert(c.TwichUIDB.ui.ammo == nil or next(c.TwichUIDB.ui.ammo) == nil, "settings left at their defaults store nothing")
  for k in pairs(c.TwichUIDB.ui) do
    if k:find("^ammo") then assert(k == "ammoPosition" or k == "ammoCustom", "only the place and the list are stored: " .. k) end
  end
  -- a new session on the same saved data starts with nothing shown
  local saved = c.TwichUIDB
  local c2 = MakeClient("Rich", { "!!!TwichUI" })
  assert(c2 ~= nil and saved.ui.ammoCustom.items[1].id == 90001)
  Reset()
end

print("PASSED")
