dofile(TESTS .. "harness.lua")
-- Easy Fishing (qol/EasyFishing.lua): what the key does in each state, who owns the bindings, combat and
-- the player's say-so over the game's settings. The game is simulated: this checks the decisions and the
-- event handling, not that the client really reels on INTERACTTARGET, which has to be checked in the game.
local c = MakeClient("Rich", {"!!!TwichUI"})
for _, f in ipairs({ "qol/QoL.lua", "qol/EasyFishing.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R, Q, E = c.TwichUI, c.TwichUI.QoL, c.TwichUI.QoLEasyFishing
local DB = c.TwichUIDB
assert(E, "the module is published")

---------------------------------------------------------------------------
-- A small world the stubs read from
---------------------------------------------------------------------------
local W, calls, ov, frames, cvars
local function Reset()
  W = {
    combat = false, known = { [7620] = true }, channel = nil,   -- channel = { name, spellID }
    softObject = false, bound = {},                             -- bound[key] = action
    secret = {},                                                -- [value] = true: issecretvalue says so
  }
  calls = { setOverride = 0, setClick = 0, clear = 0, setBinding = 0, saved = 0, setCVar = {} }
  ov = {}                                                       -- [key] = "reel" | "idle" while overridden
  frames = {}
  cvars = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" }
end
Reset()

c.InCombatLockdown = function() return W.combat end
c.issecretvalue = function(v) return W.secret[v] == true end
c.UIParent = {}
c.CreateFrame = function(_, name)
  local fr = { name = name, attrs = {}, events = {}, scripts = {} }
  function fr:SetAttribute(k, v) self.attrs[k] = v end
  function fr:GetAttribute(k) return self.attrs[k] end
  function fr:RegisterForClicks(...) self.clicks = { ... } end
  function fr:RegisterEvent() end function fr:UnregisterEvent() end
  function fr:SetScript() end function fr:HookScript() end
  if name then frames[name] = fr end
  return fr
end
c.C_SpellBook = { IsSpellKnown = function(id) return W.known[id] == true end }
c.C_Spell = { GetSpellName = function(id) if id == 7620 or id == 7731 then return "Fishing" end end }
c.UnitChannelInfo = function(unit)
  if unit ~= "player" or not W.channel then return nil end
  return W.channel[1], W.channel[1], 1, 0, 0, false, false, W.channel[2]
end
c.UnitIsGameObject = function(unit) return unit == "softinteract" and W.softObject end
c.GetBindingKey = function(action)
  local keys = {}
  for key, a in pairs(W.bound) do if a == action then keys[#keys + 1] = key end end
  table.sort(keys)
  return keys[1], keys[2]
end
c.GetBindingAction = function(key) return W.bound[key] or "" end
c.GetBindingName = function(action) return "Name of " .. action end
c.GetBindingText = function(key) return key end
c.SetBinding = function(key, action)
  calls.setBinding = calls.setBinding + 1
  W.bound[key] = action
  return true
end
c.SaveBindings = function() calls.saved = calls.saved + 1 end
c.GetCurrentBindingSet = function() return 1 end
c.SetOverrideBinding = function(_, _, key, command)
  assert(not W.combat, "an override is never set in combat")
  calls.setOverride = calls.setOverride + 1
  ov[key] = command == "INTERACTTARGET" and "reel" or command
end
c.SetOverrideBindingClick = function(_, _, key, button)
  assert(not W.combat, "an override is never set in combat")
  calls.setClick = calls.setClick + 1
  ov[key] = button == "TwichUIEasyFishingIdle" and "idle" or button
end
c.ClearOverrideBindings = function()
  assert(not W.combat, "an override is never cleared in combat")
  calls.clear = calls.clear + 1
  ov = {}
end
c.C_CVar = {
  GetCVar = function(name) return cvars[name] end,
  SetCVar = function(name, value) calls.setCVar[#calls.setCVar + 1] = name .. "=" .. value; cvars[name] = value; return true end,
}

local function Listening(event) return R.frame.events[event] == true end
local function On(on) DB.modules.qolEasyFishing = on; Q.Apply(E.feature) end
local function Channel(name, id) W.channel = { name, id } end
local function Start(unit) c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", unit or "player", "guid", W.channel and W.channel[2] or 0) end
local function Stop(unit) W.channel = nil; c.FireEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit or "player", "guid", 0, "") end
local function CountOverrides() local n = 0 for _ in pairs(ov) do n = n + 1 end return n end
local ACTION = E.ACTION

---------------------------------------------------------------------------
-- Off by default: nothing listens, nothing is made, nothing is bound
---------------------------------------------------------------------------
assert(DB.modules.qolEasyFishing == false and R.DEFAULT_MODULES.qolEasyFishing == false, "off for a new install")
for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "PLAYER_SOFT_INTERACT_CHANGED", "UPDATE_BINDINGS" }) do
  assert(not Listening(event), event .. " is not registered while off")
end
assert(next(frames) == nil, "no secure button until it is on")
assert(R.Switches.defs.qolEasyFishing and R.Switches.defs.qolEasyFishing.apply, "the switch applies the feature")
assert(E.Status() == "off")

---------------------------------------------------------------------------
-- Turning it on: the cast button holds Fishing, and only while it is on
---------------------------------------------------------------------------
W.known = {}
On(true)
assert(Listening("UNIT_SPELLCAST_CHANNEL_START") and Listening("UNIT_SPELLCAST_CHANNEL_STOP") and Listening("UPDATE_BINDINGS"))
assert(not Listening("PLAYER_SOFT_INTERACT_CHANGED"), "the soft-target event is wanted only while a line is out")
local cast, idle = frames.TwichUIEasyFishingCast, frames.TwichUIEasyFishingIdle
assert(cast and idle, "both secure buttons exist")
assert(cast:GetAttribute("type") == nil and cast:GetAttribute("spell") == nil, "Fishing not learned: the key casts nothing")
assert(E.Status() == "not-learned")
assert(cast:GetAttribute("useOnKeyDown") == true and cast.clicks[1] == "LeftButtonDown", "acts on the press only")
assert(idle:GetAttribute("type") == nil and idle:GetAttribute("spell") == nil, "the inert button has no action")
W.known = { [7620] = true }
c.FireEvent("SPELLS_CHANGED")
assert(cast:GetAttribute("type") == "spell" and cast:GetAttribute("spell") == "Fishing", "learned: it casts Fishing by name")
assert(E.Status() == "no-key", "no default key is ever bound")
assert(next(W.bound) == nil)

---------------------------------------------------------------------------
-- The key through a cast: idle -> hold -> reel -> idle
---------------------------------------------------------------------------
W.bound = { F = ACTION }
assert(E.Status() == "needs-targeting" or E.Status() == "ready")
c.FireEvent("UPDATE_BINDINGS")
assert(CountOverrides() == 0, "no line out: the key is its own binding, which casts")
Channel("Fishing", 7620); Start()
assert(ov.F == "idle", "line out, nothing the game picked: the key does nothing")
assert(Listening("PLAYER_SOFT_INTERACT_CHANGED"), "now the soft target matters")
assert(calls.setOverride == 0, "and never reels on that")
W.softObject = true
c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "", "GameObject-1")
assert(ov.F == "reel", "a world object picked: the key interacts")
local setBefore = calls.setOverride
Start(); Start(); c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "", "GameObject-1")
assert(calls.setOverride == setBefore, "repeated events change nothing: the same state is not re-bound")
W.softObject = false
c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "GameObject-1", "")
assert(ov.F == "idle", "the object is gone (an NPC is nearer): back to doing nothing, never an interaction with it")
W.softObject = true
c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "", "GameObject-1")
assert(ov.F == "reel")
Stop()
assert(CountOverrides() == 0, "the line is gone: the key casts again")
assert(not Listening("PLAYER_SOFT_INTERACT_CHANGED"), "and the soft-target event is dropped")
W.softObject = false

-- Name match covers a rank whose id isn't in the list
Channel("Fishing", 999999); Start()
assert(ov.F == "idle", "the localized name counts as Fishing")
Stop()

---------------------------------------------------------------------------
-- Another ability's channel, other players' channels, secret values
---------------------------------------------------------------------------
local reels = calls.setOverride
Channel("Evocation", 12051); Start()
assert(ov.F == "idle" and calls.setOverride == reels, "another channel: the key neither casts Fishing over it nor interacts")
W.softObject = true; c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "", "GameObject-1")
assert(ov.F == "idle", "even with an object picked, another channel is never reeled")
Stop(); W.softObject = false
Channel("Fishing", 7620); c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "party1", "g", 7620)
assert(CountOverrides() == 0, "someone else's channel is ignored")
W.channel = nil; Start()
local SECRET = {}
W.secret[SECRET] = true
c.UnitChannelInfo = function() return SECRET, SECRET, 1, 0, 0, false, false, SECRET end
Start()
assert(ov.F == "idle", "an unreadable channel is never fishing, and never lets the key cast over it")
c.UnitChannelInfo = function(unit)
  if unit ~= "player" or not W.channel then return nil end
  return W.channel[1], W.channel[1], 1, 0, 0, false, false, W.channel[2]
end
W.channel = nil; Start()
assert(CountOverrides() == 0)

---------------------------------------------------------------------------
-- Combat: nothing is changed in it, and the state of the moment combat ends is what is made
---------------------------------------------------------------------------
Channel("Fishing", 7620); W.softObject = true
Start(); assert(ov.F == "reel")
-- combat begins while the line is out: the override comes off while the game still allows it
c.FireEvent("PLAYER_REGEN_DISABLED")
assert(CountOverrides() == 0, "combat starting takes a reel binding away so it can't act on something else")
W.combat = true
Stop()                                  -- would clear: can't, and must not try (the stubs assert on it)
Channel("Fishing", 7620); Start()       -- would set: can't
assert(CountOverrides() == 0)
W.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
assert(ov.F == "reel", "combat over: made from what the game says now")
Stop()
assert(CountOverrides() == 0)
-- turned off in combat: it waits
Channel("Fishing", 7620); Start(); assert(ov.F == "reel")
W.combat = true
On(false)
assert(ov.F == "reel", "off in combat: the override can't be cleared yet")
assert(cast:GetAttribute("spell") == "Fishing", "nor the button's spell")
W.combat = false
c.FireEvent("PLAYER_REGEN_ENABLED")
assert(CountOverrides() == 0 and cast:GetAttribute("spell") == nil and cast:GetAttribute("type") == nil, "out of combat: all of it is taken out")
assert(not Listening("PLAYER_REGEN_ENABLED"), "and the combat listener is gone")

---------------------------------------------------------------------------
-- Turning it off with a line out, death, zoning
---------------------------------------------------------------------------
On(true)
assert(cast:GetAttribute("spell") == "Fishing")
Start(); assert(ov.F == "reel")
On(false)
assert(CountOverrides() == 0 and cast:GetAttribute("spell") == nil, "off: no override and no spell left")
assert(not Listening("UNIT_SPELLCAST_CHANNEL_START") and not Listening("PLAYER_SOFT_INTERACT_CHANGED"))
c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "g", 7620)
assert(CountOverrides() == 0, "off: a channel does nothing")
On(true)
Start(); assert(ov.F == "reel")
W.channel = nil; c.FireEvent("PLAYER_DEAD")
assert(CountOverrides() == 0, "dying ends it even when no stop event came")
Channel("Fishing", 7620); Start(); assert(ov.F == "reel")
W.channel = nil; c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
assert(CountOverrides() == 0, "zoning: stale state is dropped")
Channel("Fishing", 7620)
c.FireEvent("PLAYER_ENTERING_WORLD", false, true)
assert(ov.F == "reel", "reload with the line still out: picked up again")
Stop()

---------------------------------------------------------------------------
-- Keys: no default, no silent replacement, only its own bindings touched
---------------------------------------------------------------------------
W.bound = { G = "SOMETHINGELSE", H = "OTHERACTION", ALT_F = nil }
calls.setBinding, calls.saved = 0, 0
local result, name = E.Assign("G")
assert(result == "conflict" and name == "Name of SOMETHINGELSE", "an occupied key is reported, not taken")
assert(calls.setBinding == 0 and W.bound.G == "SOMETHINGELSE", "nothing changed")
assert(E.Conflict("Z") == nil and E.Conflict("") == nil)
result = E.Assign("Z")
assert(result == "ok" and W.bound.Z == ACTION and calls.saved == 1, "a free key is bound and saved")
assert(W.bound.G == "SOMETHINGELSE" and W.bound.H == "OTHERACTION", "unrelated bindings are untouched")
result = E.Assign("G", true)
assert(result == "ok" and W.bound.G == ACTION and W.bound.Z == nil, "confirmed: Easy Fishing's key moves; the old action only loses G")
assert(W.bound.H == "OTHERACTION")
assert(E.Assign("G") == "same")
assert(E.Assign("ESCAPE") == "invalid" and E.Assign("") == "invalid" and E.Assign(nil) == "invalid")
W.combat = true
assert(E.Assign("Q") == "combat" and E.ClearKeys() == "combat" and W.bound.Q == nil and W.bound.G == ACTION, "no binding change in combat")
W.combat = false
W.bound.K2 = ACTION
assert(#E.Keys() == 2)
result = E.Assign("Y")
assert(result == "ok" and W.bound.Y == ACTION and W.bound.K2 == ACTION and W.bound.G == nil, "the first key is replaced, a second stays")
assert(E.ClearKeys() == "ok")
assert(W.bound.Y == nil and W.bound.K2 == nil and W.bound.H == "OTHERACTION", "clearing removes only its own keys")

-- a key change while a line is out is followed
W.bound = { M = ACTION }
Channel("Fishing", 7620); W.softObject = true; Start()
assert(ov.M == "reel")
W.bound = { N = ACTION }
c.FireEvent("UPDATE_BINDINGS")
assert(ov.N == "reel" and ov.M == nil, "the new key is the one overridden, the old one is released")
Stop(); W.softObject = false

-- BetterFishing's key is read, never changed
c.GetBindingKey = (function(real)
  return function(action) if action == "BETTERFISHINGKEY" then return "N" end return real(action) end
end)(c.GetBindingKey)
assert(E.OtherFishingKeys()[1] == "N")

---------------------------------------------------------------------------
-- The game's settings: untouched unless allowed, put back only if still ours
---------------------------------------------------------------------------
assert(Q.Get("easyFishingTargeting") == "leave" and not E.TargetingAllowed(), "not allowed by default")
assert(E.InteractionOn() == false)
Channel("Fishing", 7620); Start()
assert(#calls.setCVar == 0 and cvars.SoftTargetInteract == "1", "not allowed: not one setting is changed")
Stop()
assert(not Q.Set("easyFishingTargeting", "yes") and Q.Get("easyFishingTargeting") == "leave", "only listed choices are kept")
E.SetTargeting(true)
assert(E.TargetingAllowed() and #calls.setCVar == 0, "allowing changes nothing by itself")
Channel("Fishing", 7620); Start()
assert(cvars.SoftTargetInteract == "3" and cvars.SoftTargetInteractArc == "2" and cvars.SoftTargetInteractRange == "60", "set while the line is out")
assert(DB.ui.easyFishingClient and #DB.ui.easyFishingClient.saved == 3, "what they were is kept")
local n = #calls.setCVar
Start(); c.FireEvent("UPDATE_BINDINGS")
assert(#calls.setCVar == n, "not set twice")
Stop()
assert(cvars.SoftTargetInteract == "1" and cvars.SoftTargetInteractArc == "0" and cvars.SoftTargetInteractRange == "10", "put back when the line is gone")
assert(DB.ui.easyFishingClient == nil, "and the record is cleared")

-- the player changes one while the line is out: theirs is kept
Channel("Fishing", 7620); Start()
cvars.SoftTargetInteractRange = "25"
Stop()
assert(cvars.SoftTargetInteractRange == "25", "a setting changed meanwhile is never overwritten")
assert(cvars.SoftTargetInteract == "1" and cvars.SoftTargetInteractArc == "0")
cvars.SoftTargetInteractRange = "10"

-- already as wanted: nothing to set, nothing to put back
cvars.SoftTargetInteract, cvars.SoftTargetInteractArc, cvars.SoftTargetInteractRange = "3", "2", "60"
local before = #calls.setCVar
Channel("Fishing", 7620); Start(); Stop()
assert(#calls.setCVar == before and DB.ui.easyFishingClient == nil, "values already right are left alone")
cvars.SoftTargetInteract, cvars.SoftTargetInteractArc, cvars.SoftTargetInteractRange = "1", "0", "10"

-- turning the feature off, or the permission, with the line out puts them back
Channel("Fishing", 7620); Start()
assert(cvars.SoftTargetInteract == "3")
E.SetTargeting(false)
assert(cvars.SoftTargetInteract == "1" and DB.ui.easyFishingClient == nil, "withdrawing the permission restores at once")
E.SetTargeting(true)
Start(); assert(cvars.SoftTargetInteract == "3")
On(false)
assert(cvars.SoftTargetInteract == "1" and cvars.SoftTargetInteractRange == "10", "turning the feature off restores")
On(true)
Start(); assert(cvars.SoftTargetInteract == "3")
c.FireEvent("PLAYER_LOGOUT")
assert(cvars.SoftTargetInteract == "1", "logout restores")
-- a game closed mid-line leaves a record: put back at the next start
cvars.SoftTargetInteract = "3"
DB.ui.easyFishingClient = { saved = { { name = "SoftTargetInteract", before = "1", set = "3" } } }
W.channel = nil
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
assert(cvars.SoftTargetInteract == "1" and DB.ui.easyFishingClient == nil, "a record from a closed game is honoured once")
-- a damaged record is ignored safely
DB.ui.easyFishingClient = { saved = { "junk", { name = 5, before = {}, set = false } } }
c.FireEvent("PLAYER_ENTERING_WORLD", false, false)
assert(DB.ui.easyFishingClient == nil)
On(false)
E.SetTargeting(false)

---------------------------------------------------------------------------
-- Unsupported client: it says so and does nothing
---------------------------------------------------------------------------
assert(E.Supported() == true)
local savedFn = c.SetOverrideBinding
c.SetOverrideBinding = nil
assert(E.Supported() == false)
DB.modules.qolEasyFishing = true
assert(E.Status() == "unsupported")
c.SetOverrideBinding = savedFn
DB.modules.qolEasyFishing = false

---------------------------------------------------------------------------
-- Packaging: the key binding entry, and the file in the load order
---------------------------------------------------------------------------
local function Read(path) local f = assert(io.open(path, "rb")); local t = f:read("*a"); f:close(); return t end
assert(Read(ROOT .. "Bindings.xml"):find('<Binding name="CLICK TwichUIEasyFishingCast:LeftButton"', 1, true), "a Key Bindings entry")
local toc = Read(ROOT .. "!!!TwichUI.toc")
assert(toc:find("qol\\QoL.lua", 1, true) < toc:find("qol\\EasyFishing.lua", 1, true), "listed after the QoL core")
assert(c._G["BINDING_NAME_" .. ACTION] and c._G.BINDING_HEADER_TWICHUI, "named in the Key Bindings list")

print("EASY FISHING TESTS PASSED")
