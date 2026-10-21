-- Hazard alerts (hazard/): Config.lua stores settings and the player's rules, Rules.lua decides what is registered (no
-- game calls), Alerts.lua registers aura sounds with the game and plays the preview. A fake C_UnitAuras stands in for the
-- game, so this checks our logic, not the game: the in-game checks are listed in docs/hazard-alerts.md.
-- The client gives addons no combat-log payload, so there is no combat-log parser to test; what is tested is what the
-- feature actually does: which rules are registered, with which sound, when, and that nothing runs otherwise.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

---------------------------------------------------------------------------
-- A fake game: frames that record their events, aura sound registrations, restrictions, sound playback
---------------------------------------------------------------------------
local frames = {}
c.CreateFrame = function()
  local f = { events = {}, scripts = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:GetScript(n) return self.scripts[n] end
  frames[#frames + 1] = f
  return f
end
local function Deliver(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function EventCount()
  local n = 0
  for _, f in ipairs(frames) do for _ in pairs(f.events) do n = n + 1 end end
  return n
end
local function OnUpdates()
  local n = 0
  for _, f in ipairs(frames) do if f.scripts.OnUpdate then n = n + 1 end end
  return n
end

c.Enum = { UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 },
  AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 } }
local G
local function Game()
  G = { next = 100, live = {}, adds = 0, removes = 0, refuse = false, restricted = false, calls = {}, played = {}, playOk = true }
end
Game()
c.C_UnitAuras = {
  AddAuraSound = function(trigger, info)
    G.adds = G.adds + 1
    G.calls[#G.calls + 1] = { trigger = trigger, info = info }
    if G.refuse then return nil end
    G.next = G.next + 1
    G.live[G.next] = { trigger = trigger, info = info }
    return G.next
  end,
  RemoveAuraSound = function(id) G.removes = G.removes + 1; G.live[id] = nil end,
}
c.C_RestrictedActions = { IsAddOnRestrictionActive = function() return G.restricted end }
c.PlaySoundFile = function(path, channel) G.played[#G.played + 1] = { path, channel }; return G.playOk end
c.issecretvalue = function() return false end
c.C_Spell = { GetSpellName = function(id) return ({ [1000] = "Test Fire" })[id] end }
local function Live()
  local n = 0
  for _ in pairs(G.live) do n = n + 1 end
  return n
end
local function LiveFor(spell, trigger)
  for _, e in pairs(G.live) do
    if e.info.spellID == spell and e.trigger == trigger then return e end
  end
end

for _, f in ipairs({ "modules/Media.lua", "hazard/Config.lua", "hazard/Rules.lua", "hazard/Alerts.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local HZ, HR, A = R.Hazard, R.HazardRules, R.HazardAlerts

local function On() R:SetEnabled("hazardAlerts", true) end
local function Off() R:SetEnabled("hazardAlerts", false) end
local function Reset()   -- a clean slate between sections: off, no saved values, a clean fake game
  Off()
  c.TwichUIDB.ui = {}
  HR.Load({})
  Game()
  A.Refresh()
  Game()
end
local function Rule(spell, trigger, category, extra)
  local f = { name = "Rule " .. spell, spell = spell, trigger = trigger or "applied", category = category or "high", throttle = 2 }
  for k, v in pairs(extra or {}) do f[k] = v end
  local ok, id = HZ.Add(f)
  assert(ok, "rule added: " .. tostring(id))
  return id
end

---------------------------------------------------------------------------
-- 1. Off by default: nothing registered, listened for or drawn
---------------------------------------------------------------------------
do
  assert(c.TwichUIDB.modules.hazardAlerts == false, "the alerts are opt-in")
  assert(R.DEFAULT_MODULES.hazardAlerts == false)
  assert(G.adds == 0 and #frames == 0 and EventCount() == 0 and OnUpdates() == 0, "nothing at load")
  HZ.Add({ name = "x", spell = 5, trigger = "applied", category = "low", throttle = 1 })
  assert(G.adds == 0, "a rule saved while off registers nothing")
  local s = A.Snapshot()
  assert(not s.enabled and s.registered == 0 and not s.watching and s.available)
  assert(HR.Builtin and #HR.Builtin() == 0, "no built-in rule ships until one is confirmed on the client")
end

---------------------------------------------------------------------------
-- 2. Settings: validated, defaults only where missing, reset
---------------------------------------------------------------------------
do
  Reset()
  for key, default in pairs(HZ.DEFAULTS) do assert(HZ.Get(key) == default, key .. " default") end
  assert(HZ.Set("highOn", false) and HZ.Get("highOn") == false, "a saved false is a value")
  assert(not HZ.Set("highOn", "no") and not HZ.Set("channel", "Music") and not HZ.Set("nonsense", true), "invalid values refused")
  assert(not HZ.Set("highSound", "") and not HZ.Set("highSound", "a|cff"), "sound names are checked")
  assert(HZ.Set("highSound", HZ.NONE) and HZ.Get("highSound") == "None", "None is a choice")
  c.TwichUIDB.ui.hazard.lowSound = 42
  assert(HZ.Get("lowSound") == HZ.DEFAULTS.lowSound and c.TwichUIDB.ui.hazard.lowSound == 42, "an invalid stored value reads as the default and is left alone")
  HZ.ResetSettings()
  assert(HZ.Get("highOn") == true and HZ.Get("highSound") == HZ.DEFAULTS.highSound and next(c.TwichUIDB.ui.hazard) == nil, "reset forgets")
  Reset()
end

---------------------------------------------------------------------------
-- 3. Custom rules: validation, bounds, duplicates, uncached spells
---------------------------------------------------------------------------
do
  Reset()
  local base = { name = "Fire", spell = 1000, trigger = "applied", category = "high", throttle = 2 }
  local function With(k, v) local t = {}; for a, b in pairs(base) do t[a] = b end; t[k] = v; return t end
  for _, bad in ipairs({ { "spell", 0 }, { "spell", -4 }, { "spell", 1.5 }, { "spell", "abc" }, { "spell", 2 ^ 40 }, { "spell", "12 34" },
      { "trigger", "damage" }, { "trigger", 7 }, { "category", "friendly" }, { "throttle", 6 }, { "throttle", -1 }, { "throttle", 1.5 }, { "throttle", "x" },
      { "name", "" }, { "name", "a|cffff0000b" }, { "name", string.rep("x", 61) } }) do
    local ok, why = HZ.Add(With(bad[1], bad[2]))
    assert(not ok and why == bad[1], "refused " .. bad[1] .. " = " .. tostring(bad[2]) .. " (" .. tostring(why) .. ")")
  end
  assert(HZ.Count() == 0, "nothing was stored by the refusals")
  local ok, id = HZ.Add(With("spell", "1000"))
  assert(ok and HZ.Find(id).spell == 1000, "a spell ID typed as text is accepted")
  local ok2, why, twin = HZ.Add(With("name", "Again"))
  assert(not ok2 and why == "duplicate" and twin.id == id, "the same spell and trigger is a duplicate")
  assert(HZ.Add(With("trigger", "removed")), "the same spell with another trigger is a different rule")
  -- uncached or server-specific spell: its name is unknown to the client, and the rule is still valid
  assert(c.C_Spell.GetSpellName(987654) == nil and HZ.Add({ name = "Unknown", spell = 987654, trigger = "applied", category = "low", throttle = 0 }),
    "a spell the client has no name for is accepted")
  -- the defaults of a new rule
  local d = HZ.Normalize({ spell = 5, name = "n" })
  assert(d.trigger == "applied" and d.category == "low" and d.throttle == HZ.THROTTLE_DEFAULT and d.enabled == true)
  -- update, enable, copy, remove
  assert(HZ.Update(id, { name = "Fire!", category = "low", throttle = 0 }) and HZ.Find(id).name == "Fire!" and HZ.Find(id).category == "low" and HZ.Find(id).spell == 1000)
  local okU, whyU, twinU = HZ.Update(id, { trigger = "removed" })
  assert(not okU and whyU == "duplicate" and twinU, "an edit cannot create a duplicate")
  assert(not HZ.Update(id, { throttle = 9 }) and HZ.Find(id).throttle == 0, "an invalid edit changes nothing")
  assert(HZ.SetRuleEnabled(id, false) and HZ.Find(id).enabled == false and HZ.SetRuleEnabled(id, true) and HZ.Find(id).enabled)
  local okC, copyId = HZ.DuplicateRule(id)
  assert(okC and HZ.Find(copyId).enabled == false and HZ.Find(copyId).trigger == "stacks" and HZ.Find(copyId).spell == 1000, "the copy is off and takes a free trigger")
  assert(not HZ.DuplicateRule(id), "no trigger left to copy to")
  assert(HZ.Remove(copyId) and not HZ.Find(copyId) and not HZ.Remove("nope"))
  -- ids are not reused while their rule is there
  local a = Rule(11); local b = Rule(12)
  assert(a ~= b and HZ.Find(a) and HZ.Find(b))
  -- a malformed stored rule is ignored and left alone
  local stored = #c.TwichUIDB.ui.hazardCustom.rules
  c.TwichUIDB.ui.hazardCustom.rules[#c.TwichUIDB.ui.hazardCustom.rules + 1] = { id = "bad", spell = "x" }
  assert(HZ.Count() == stored and #c.TwichUIDB.ui.hazardCustom.rules == stored + 1, "an invalid stored rule is not listed and not erased")
  -- the cap
  Reset()
  for i = 1, HZ.MAX_CUSTOM do assert(HZ.Add({ name = "r" .. i, spell = 2000 + i, trigger = "applied", category = "low", throttle = 1 })) end
  local okF, whyF = HZ.Add({ name = "one more", spell = 9999, trigger = "applied", category = "low", throttle = 1 })
  assert(not okF and whyF == "full" and HZ.Count() == HZ.MAX_CUSTOM, "the number of rules is capped")
  HZ.ClearCustom()
  assert(HZ.Count() == 0)
  -- the built-in "off" list is bounded and checked
  assert(not HZ.SetBuiltinEnabled("bad id!", false) and not HZ.SetBuiltinEnabled(42, false))
  for i = 1, HZ.MAX_BUILTIN_OFF do assert(HZ.SetBuiltinEnabled("b" .. i, false)) end
  assert(not HZ.SetBuiltinEnabled("overflow", false), "turned-off built-in rules are capped")
  HZ.ResetBuiltin()
  assert(next(HZ.BuiltinOff()) == nil)
  Reset()
end

---------------------------------------------------------------------------
-- 4. Rules.lua alone: definitions, precedence, categories
---------------------------------------------------------------------------
do
  Reset()
  local good = function(id, spell, trigger, category)
    return { id = id, spell = spell, name = "Built " .. id, trigger = trigger, category = category, throttle = 3, why = "w", source = "checked in game" }
  end
  local loaded, skipped = HR.Load({
    good("b.high", 500, "applied", "high"), good("b.low", 501, "applied", "low"), good("b.fail", 502, "stacks", "fail"),
    good("b.high", 503, "applied", "high"),                                   -- a repeated id
    { id = "no.why", spell = 504, name = "x", trigger = "applied", category = "low", throttle = 1, source = "s" },
    { id = "bad.spell", spell = 0, name = "x", trigger = "applied", category = "low", throttle = 1, why = "w", source = "s" },
    "not a table",
  })
  assert(loaded == 3 and skipped == 4, "valid definitions load, the others are counted: " .. loaded .. "/" .. skipped)
  local allOn = function() return true end
  local sounded = function() return true end
  local out = HR.Resolve({}, {}, allOn, sounded)
  assert(#out == 3 and out[1].source == "builtin" and out[1].key == "500:applied")
  -- one rule per category reaches the game
  local byCat = {}
  for _, r in ipairs(out) do byCat[r.category] = r end
  assert(byCat.high and byCat.low and byCat.fail, "each category is represented")
  -- off, category off, no sound
  assert(#HR.Resolve({}, { ["b.low"] = true }, allOn, sounded) == 2, "a built-in rule turned off is not registered")
  assert(#HR.Resolve({}, {}, function(cat) return cat ~= "fail" end, sounded) == 2, "a category turned off registers none of its rules")
  assert(#HR.Resolve({}, {}, allOn, function(cat) return cat ~= "low" end) == 2, "a category with no sound registers none of its rules")
  -- precedence: an enabled custom rule replaces the built-in one for the same spell and trigger; one registration only
  local custom = { { id = "c1", enabled = true, name = "Mine", spell = 500, trigger = "applied", category = "fail", throttle = 0 } }
  out = HR.Resolve(custom, {}, allOn, sounded)
  local n500 = 0
  for _, r in ipairs(out) do if r.spell == 500 and r.trigger == "applied" then n500 = n500 + 1; assert(r.source == "custom" and r.category == "fail") end end
  assert(n500 == 1 and #out == 3, "custom wins and there is no duplicate")
  custom[1].enabled = false
  out = HR.Resolve(custom, {}, allOn, sounded)
  assert(#out == 3 and out[1].source == "builtin", "a custom rule that is off does not shadow the built-in one")
  -- the custom rule in a category that is off does not shadow either
  custom[1].enabled = true
  out = HR.Resolve(custom, {}, function(cat) return cat ~= "fail" end, sounded)
  local still
  for _, r in ipairs(out) do if r.spell == 500 then still = r end end
  assert(still and still.source == "builtin" and still.category == "high", "a custom rule that cannot play does not hide the built-in one")
  assert(HR.Shadows(500, "applied").id == "b.high" and HR.Shadows(500, "stacks") == nil)
  Reset()
end

---------------------------------------------------------------------------
-- 5. Registration with the game
---------------------------------------------------------------------------
do
  Reset()
  local hi = Rule(1000, "applied", "high")
  local lo = Rule(1001, "stacks", "low", { throttle = 0 })
  local fl = Rule(1002, "removed", "fail", { throttle = 5 })
  assert(G.adds == 0 and EventCount() == 0, "off: rules are saved and nothing is registered")
  On()
  assert(G.adds == 3 and Live() == 3, "on: each enabled rule is registered once (" .. G.adds .. ")")
  local e = LiveFor(1000, 0)
  assert(e and e.info.unitToken == "player", "for the player only")
  assert(e.info.outputChannel == "SFX" and e.info.throttleSeconds == 2)
  assert(e.info.soundFileName == R:SoundPath("TwichUI_Drums.mp3") or e.info.soundFileName == R:SoundPath("TwichUI_Drums.mp3"), "the high sound")
  assert(LiveFor(1001, 1).info.soundFileName == R:SoundPath("TwichUI_Notification.mp3") and LiveFor(1001, 1).info.throttleSeconds == 0, "stacks growing, the low sound")
  assert(LiveFor(1002, 2).info.soundFileName == R:SoundPath("Single_Knell.ogg") and LiveFor(1002, 2).info.throttleSeconds == 5, "fading, the failed-mechanic sound")
  -- the three sounds are distinct
  assert(e.info.soundFileName ~= LiveFor(1001, 1).info.soundFileName and LiveFor(1001, 1).info.soundFileName ~= LiveFor(1002, 2).info.soundFileName)
  -- listening: only the restriction event and the world, and no update handler
  assert(EventCount() == 2 and OnUpdates() == 0, "two events and no OnUpdate while on: " .. EventCount())
  Deliver("PLAYER_ENTERING_WORLD")
  assert(EventCount() == 1 and G.adds == 3, "the world event is used once and changes nothing here")
  -- a refresh that changes nothing makes no game call
  local before = G.adds + G.removes
  A.Refresh(); A.Refresh(); HZ.Invalidate()
  assert(G.adds + G.removes == before, "an unchanged refresh makes no game call")
  -- changing a sound re-registers that category's rules only
  HZ.Set("highSound", "Light Fades")
  assert(G.adds == 4 and G.removes == 1 and Live() == 3 and LiveFor(1000, 0).info.soundFileName == R:SoundPath("Light_Fades.ogg"))
  -- the channel changes every registration
  HZ.Set("channel", "Master")
  assert(Live() == 3 and LiveFor(1001, 1).info.outputChannel == "Master" and G.adds == 7 and G.removes == 4)
  -- a category turned off, a category set to None, a rule turned off, a rule removed
  HZ.Set("lowOn", false)
  assert(Live() == 2 and not LiveFor(1001, 1), "a category turned off is unregistered")
  HZ.Set("lowOn", true)
  assert(Live() == 3)
  HZ.Set("lowSound", HZ.NONE)
  assert(Live() == 2 and not LiveFor(1001, 1), "None registers nothing for the category")
  HZ.Set("lowSound", "Light Fades")
  assert(Live() == 3)
  HZ.SetRuleEnabled(fl, false)
  assert(Live() == 2 and not LiveFor(1002, 2))
  HZ.Remove(hi)
  assert(Live() == 1 and not LiveFor(1000, 0))
  -- an edit moves the registration
  HZ.Update(lo, { spell = 1010, trigger = "applied" })
  assert(Live() == 1 and LiveFor(1010, 0) and not LiveFor(1001, 1))
  -- a sound that is not available is reported and registers nothing
  HZ.Set("lowSound", "No Such Sound")
  assert(Live() == 0 and A.MissingSound("low") and A.Snapshot().missingSound, "a missing sound is reported")
  HZ.Set("lowSound", "Light Fades")
  assert(Live() == 1 and not A.MissingSound("low"))
  -- turning the switch off removes everything and stops listening
  Off()
  assert(Live() == 0 and EventCount() == 0 and OnUpdates() == 0, "off: nothing registered, nothing listened for")
  assert(A.Snapshot().registered == 0 and not A.Snapshot().watching)
  local after = G.adds
  HZ.Set("highOn", false); HZ.Set("highOn", true); Rule(1020, "applied", "high")
  assert(G.adds == after, "while off, changes register nothing")
  Reset()
end

---------------------------------------------------------------------------
-- 6. The game refuses, the API is missing, a numeric LibSharedMedia sound
---------------------------------------------------------------------------
do
  Reset()
  Rule(1000, "applied", "high")
  G.refuse = true
  On()
  local s = A.Snapshot()
  assert(Live() == 0 and s.refused == 1 and s.registered == 0 and s.wanted == 1, "a refused registration is counted, not stored")
  G.refuse = false
  A.Refresh()
  assert(Live() == 1, "and tried again on the next refresh")
  Off()
  -- a file ID from LibSharedMedia goes as a file ID
  local LSM = c.LibStub("LibSharedMedia-3.0")
  LSM:Register("sound", "Numeric Test", 567890)
  HZ.Set("highSound", "Numeric Test")
  On()
  assert(LiveFor(1000, 0).info.soundFileID == 567890 and LiveFor(1000, 0).info.soundFileName == nil, "a file ID is passed as one")
  Off()
  -- an old client with no aura sound API
  local saved = c.C_UnitAuras.AddAuraSound
  c.C_UnitAuras.AddAuraSound = nil
  assert(not A.Available())
  On()
  assert(Live() == 0 and A.Snapshot().available == false, "without the API nothing is registered and nothing errors")
  c.C_UnitAuras.AddAuraSound = saved
  Reset()
end

---------------------------------------------------------------------------
-- 7. Restrictions: changes wait and are made when they lift
---------------------------------------------------------------------------
do
  Reset()
  Rule(1000, "applied", "high")
  On()
  assert(Live() == 1)
  G.restricted = true
  Rule(1001, "applied", "low")
  local s = A.Snapshot()
  assert(Live() == 1 and s.pending and s.restricted and s.deferred == 1, "a change in a restricted state waits")
  HZ.Set("lowSound", "Light Fades")
  assert(A.Snapshot().deferred == 1, "more changes while waiting are one wait")
  Deliver("ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
  assert(Live() == 1, "still restricted: still waiting")
  G.restricted = false
  Deliver("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
  assert(Live() == 2 and not A.Snapshot().pending, "when the restriction lifts the change is made")
  -- turning off while restricted: removal waits, then happens
  G.restricted = true
  Off()
  assert(Live() == 2 and A.Snapshot().pending and EventCount() >= 1, "off while restricted: the removal waits, and still listens")
  G.restricted = false
  Deliver("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
  assert(Live() == 0 and not A.Snapshot().pending and EventCount() == 0, "removed once the restriction lifted, and then nothing is listened for")
  Reset()
end

---------------------------------------------------------------------------
-- 8. The preview: the real playback path, nothing registered, nothing changed
---------------------------------------------------------------------------
do
  Reset()
  Rule(1000, "applied", "high")
  -- works with the alerts off, and registers nothing
  for _, cat in ipairs({ "high", "low", "fail" }) do
    local ok = A.TestSound(cat)
    assert(ok, cat .. " plays")
  end
  assert(#G.played == 3 and G.adds == 0 and Live() == 0, "three sounds played, nothing registered")
  assert(G.played[1][1] == R:SoundPath("TwichUI_Drums.mp3") and G.played[1][2] == "SFX", "the chosen file on the chosen channel")
  assert(G.played[1][1] ~= G.played[2][1] and G.played[2][1] ~= G.played[3][1], "each category has its own sound")
  HZ.Set("channel", "Master")
  A.TestSound("low")
  assert(G.played[4][2] == "Master")
  -- None, a missing sound, a game that refuses, an unknown category
  HZ.Set("failSound", HZ.NONE)
  local ok, why = A.TestSound("fail")
  assert(not ok and why == "none" and #G.played == 4, "None plays nothing")
  HZ.Set("failSound", "No Such Sound")
  ok, why = A.TestSound("fail")
  assert(not ok and why == "missing" and #G.played == 4)
  G.playOk = false
  ok, why = A.TestSound("high")
  assert(not ok and why == "refused" and A.Snapshot().testsRefused == 1)
  G.playOk = true
  ok, why = A.TestSound("friendly")
  assert(not ok and why == "category")
  -- with the alerts on, a preview leaves the registrations exactly as they were
  On()
  local adds, removes, live = G.adds, G.removes, Live()
  A.TestSound("high"); A.TestSound("low")
  assert(G.adds == adds and G.removes == removes and Live() == live, "the preview touches no registration")
  Reset()
end

---------------------------------------------------------------------------
-- 9. Profiles and the standalone GTFO notice
---------------------------------------------------------------------------
do
  Reset()
  Rule(1000, "applied", "high")
  On()
  assert(Live() == 1)
  -- a profile that has no rules and one that turns the alerts off
  c.TwichUIDB.ui.hazardCustom = { rules = {} }
  R.Profiles.Refresh("test")
  assert(Live() == 0, "the rules follow the profile")
  c.TwichUIDB.ui.hazardCustom = { rules = { { id = "c1", enabled = true, name = "P", spell = 77, trigger = "applied", category = "low", throttle = 1 } } }
  R.Profiles.Refresh("test")
  assert(Live() == 1 and LiveFor(77, 0), "another profile's rules are registered")
  c.TwichUIDB.modules.hazardAlerts = false
  R.Profiles.Refresh("test")
  assert(Live() == 0 and EventCount() == 0, "a profile with the alerts off turns them off")
  -- GTFO: only the addon-presence check is used
  assert(A.GtfoActive() == false)
  c.LOADED.GTFO = true
  assert(A.GtfoActive() == true and A.Snapshot().gtfo, "standalone GTFO is noticed")
  On()
  assert(HZ.Get("highOn") == true and R:Enabled("hazardAlerts"), "its presence changes none of our settings")
  c.LOADED.GTFO = nil
  Reset()
end

---------------------------------------------------------------------------
-- 10. Sharing: rules travel as plain data, are merged, and undo puts them back
---------------------------------------------------------------------------
do
  Reset()
  local TC = R.TwichConfig
  local g = TC.Group("hazardRules")
  assert(g and g.custom and g.custom.usable(), "the rules are a shared group")
  local mine = Rule(1000, "applied", "high", { name = "Mine" })
  HZ.SetBuiltinEnabled("some.builtin", false)
  local export = g.custom.export()
  assert(#export.rules == 1 and export.rules[1].id == nil and export.off[1] == "some.builtin", "ids stay home")
  -- validation of what arrives
  local function Clean(raw) return g.custom.clean(raw) end
  assert(not Clean("x") and not Clean({ rules = "x" }) and not Clean({ rules = {} }) and not Clean({ rules = { { spell = 1 } } }))
  assert(not Clean({ rules = { { name = "a", spell = 0, trigger = "applied", category = "low", throttle = 1 } } }), "a bad spell ID refuses the group")
  assert(not Clean({ rules = { { name = "a", spell = 3, trigger = "damage", category = "low", throttle = 1 } } }), "an unknown trigger refuses the group")
  assert(not Clean({ rules = { { name = "a", spell = 3, trigger = "applied", category = "low", throttle = 99 } } }), "a long cooldown refuses the group")
  assert(not Clean({ rules = { { name = "a", spell = 3, trigger = "applied", category = "low", throttle = 1, enabled = "yes" } } }))
  local dup = { name = "a", spell = 3, trigger = "applied", category = "low", throttle = 1 }
  assert(not Clean({ rules = { dup, dup } }), "the same aura twice refuses the group")
  assert(not Clean({ off = { "bad id!" } }) and not Clean({ off = { "a", "a" } }))
  local many = {}
  for i = 1, HZ.MAX_CUSTOM + 1 do many[i] = { name = "r" .. i, spell = 100 + i, trigger = "applied", category = "low", throttle = 1 } end
  assert(not Clean({ rules = many }), "too many rules refuse the group")
  local ok = Clean({ rules = { { name = "Mine renamed", spell = 1000, trigger = "applied", category = "low", throttle = 4, enabled = false, extra = "dropped" },
      { name = "Fresh", spell = 2000, trigger = "stacks", category = "fail", throttle = 0 } }, off = { "other.builtin" } })
  assert(ok and #ok.rules == 2 and ok.rules[1].extra == nil and ok.rules[1].id == "c0")
  local plan = g.custom.plan(ok)
  assert(#plan == 3, "two rules and a built-in choice would change")
  local rows = g.custom.review(ok)
  assert(#rows == 3 and rows[1].old:find("Urgent danger") and rows[1].new:find("Warning"))
  local before = HZ.Count()
  local undo = g.custom.apply(ok, plan)
  assert(HZ.Count() == before + 1 and HZ.Find(mine).name == "Mine renamed" and HZ.Find(mine).enabled == false and HZ.IsBuiltinOff("other.builtin") and HZ.IsBuiltinOff("some.builtin"),
    "merged: updated, added, and nothing removed")
  assert(g.custom.restore(undo) == 3)
  assert(HZ.Count() == before and HZ.Find(mine).name == "Mine" and HZ.Find(mine).enabled and HZ.Find(mine).category == "high" and not HZ.IsBuiltinOff("other.builtin") and HZ.IsBuiltinOff("some.builtin"),
    "undo puts it back exactly")
  -- a full list leaves extras out and says so
  for i = 1, HZ.MAX_CUSTOM do HZ.Add({ name = "f" .. i, spell = 5000 + i, trigger = "applied", category = "low", throttle = 1 }) end
  local p2 = g.custom.plan(Clean({ rules = { { name = "Late", spell = 777, trigger = "applied", category = "low", throttle = 1 } } }))
  assert(p2.full == 1 and #p2 == 0)
  -- importing turns nothing on
  Reset()
  g.custom.apply(ok, g.custom.plan(ok))
  assert(G.adds == 0 and not R:Enabled("hazardAlerts"), "an imported rule plays nothing while the alerts are off")
  Reset()
end

---------------------------------------------------------------------------
-- 11. Bounded state
---------------------------------------------------------------------------
do
  Reset()
  On()
  for round = 1, 30 do
    local id = Rule(3000 + round, "applied", "low")
    HZ.Set("channel", round % 2 == 0 and "SFX" or "Master")
    HZ.Remove(id)
  end
  assert(Live() == 0 and A.Snapshot().registered == 0 and A.Snapshot().stale == 0, "registrations are exactly what is wanted after churn")
  assert(G.adds == G.removes, "every registration was removed: " .. G.adds .. "/" .. G.removes)
  assert(EventCount() == 1 and OnUpdates() == 0)
  Off()
  assert(EventCount() == 0)
end

print("HAZARD TESTS PASSED")
