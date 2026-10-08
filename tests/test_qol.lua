dofile(TESTS .. "harness.lua")
-- Quality of Life: Accept summons, Accept resurrection, Release in battlegrounds, Block duels.
-- The game is simulated: this checks the decisions and the event handling, not the game's own
-- behaviour, which has to be checked in the game.
local c = MakeClient("Rich", {"!!!TwichUI"})
for _, f in ipairs({ "qol/QoL.lua", "qol/Summons.lua", "qol/Resurrect.lua", "qol/ReleasePvP.lua", "qol/Duels.lua", "qol/QuickKeybind.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R, Q = c.TwichUI, c.TwichUI.QoL
local DB = c.TwichUIDB

-- A tiny world the stubs read from.
local W
local calls
local function Reset()
  W = {
    combat = false, canTeleport = true, group = {}, groupCombat = {}, raid = false, friends = {}, bnet = {}, guild = {},
    summon = { who = "Mira", area = "Stranglethorn", left = 60 },
    offerer = nil, sickness = false, corpseDelay = 0, hardcore = false,
    dead = true, ghost = false, instance = { false, "none" }, selfRes = nil, releaseRemaining = -1, falling = false, shift = false,
  }
  calls = { confirm = 0, accept = 0, repop = 0, cancelDuel = 0, hidden = {}, roster = 0 }
  TIMERS, LONG_TIMERS = {}, {}
end
Reset()
c.UnitAffectingCombat = function(unit) if unit == "player" then return W.combat end return W.groupCombat[unit] or false end
c.PlayerCanTeleport = function() return W.canTeleport end
c.Enum.SummonReason = { Spell = 0, Scenario = 1 }
c.C_SummonInfo = {
  GetSummonConfirmSummoner = function() return W.summon.who end,
  GetSummonConfirmAreaName = function() return W.summon.area end,
  GetSummonConfirmTimeLeft = function() return W.summon.left end,
  ConfirmSummon = function() calls.confirm = calls.confirm + 1 end,
}
c.StaticPopup_Hide = function(which) table.insert(calls.hidden, which) end
c.IsInGroup = function() return next(W.group) ~= nil end
c.IsInRaid = function() return W.raid end
c.GetNumGroupMembers = function() return #W.group + 1 end
c.UnitName = function(unit)
  local prefix, i = unit:match("^(%a+)(%d+)$")
  if prefix == (W.raid and "raid" or "party") then return W.group[tonumber(i)] end
end
c.C_FriendList = {
  GetNumFriends = function() return #W.friends end,
  GetFriendInfoByIndex = function(i) return { name = W.friends[i] } end,
}
c.BNGetNumFriends = function() return #W.bnet end
c.C_BattleNet = {
  GetFriendNumGameAccounts = function() return 1 end,
  GetFriendGameAccountInfo = function(i) return { clientProgram = "WoW", characterName = W.bnet[i] } end,
}
c.IsInGuild = function() return #W.guild > 0 end
c.GetNumGuildMembers = function() return #W.guild end
c.GetGuildRosterInfo = function(i) return W.guild[i] end
c.C_GuildInfo = { GuildRoster = function() calls.roster = calls.roster + 1 end }
c.ResurrectGetOfferer = function() return W.offerer end
c.ResurrectHasSickness = function() return W.sickness end
c.GetCorpseRecoveryDelay = function() return W.corpseDelay end
c.AcceptResurrect = function() calls.accept = calls.accept + 1 end
c.C_GameRules = { IsHardcoreActive = function() return W.hardcore end }
c.UnitIsDead = function() return W.dead end
c.UnitIsGhost = function() return W.ghost end
c.IsInInstance = function() return W.instance[1], W.instance[2] end
c.C_DeathInfo = { GetSelfResurrectOptions = function() return W.selfRes end }
c.GetReleaseTimeRemaining = function() return W.releaseRemaining end
c.IsFalling = function() return W.falling end
c.IsOutOfBounds = function() return false end
c.IsShiftKeyDown = function() return W.shift end
c.RepopMe = function() calls.repop = calls.repop + 1 end
c.CancelDuel = function() calls.cancelDuel = calls.cancelDuel + 1 end

local function On(key, value) DB.modules[key] = value end
local function Listening(event) return R.frame.events[event] == true end
local function Apply(feature) Q.Apply(feature) end
local S, Rez, Rel, D = R.QoLSummons, R.QoLResurrect, R.QoLRelease, R.QoLDuels

-- Off by default: nothing listens and nothing happens.
for _, key in ipairs({ "qolSummons", "qolResurrect", "qolResurrectCombat", "qolReleasePvP", "qolDuels", "qolDuelsToDeath", "qolQuickKeybind" }) do
  assert(DB.modules[key] == false, key .. " is off for a new install")
end
for _, event in ipairs({ "CONFIRM_SUMMON", "CANCEL_SUMMON", "RESURRECT_REQUEST", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
  "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED" }) do
  assert(not Listening(event), event .. " is not registered while everything is off")
end
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0)

-- Options: only listed choices are kept.
assert(Q.Get("summonsFrom") == "known" and Q.Get("summonsWait") == 3 and Q.Get("duelsFrom") == "known" and Q.Get("releaseWait") == 2)
assert(Q.Set("summonsFrom", "group") and Q.Get("summonsFrom") == "group")
assert(not Q.Set("summonsFrom", "everyone") and Q.Get("summonsFrom") == "group", "an unknown choice is refused")
assert(not Q.Set("summonsWait", 7) and Q.Get("summonsWait") == 3)
DB.ui.qol.summonsFrom = "bogus"; assert(Q.Get("summonsFrom") == "known", "a bad saved value falls back to the default")
DB.ui.qol.summonsFrom = nil

---------------------------------------------------------------------------
-- Who is asking
---------------------------------------------------------------------------
W.friends = { "Ann" }; W.bnet = { "Bo" }; W.guild = { "Cy-Forever" }; W.group = { "Di" }
assert(Q.IsFriend("ann") and Q.IsFriend("Ann-Forever") and Q.IsFriend("Bo") and not Q.IsFriend("Cy"))
assert(Q.IsGuildMember("Cy") and Q.IsGuildMember("cy-forever") and not Q.IsGuildMember("Ann"))
assert(Q.GroupUnit("Di") == "party1" and Q.GroupUnit("Ann") == nil)
W.raid = true; assert(Q.GroupUnit("Di") == "raid1"); W.raid = false
assert(Q.Allowed("Ann", "known") and Q.Allowed("Bo", "known") and Q.Allowed("Cy", "known") and Q.Allowed("Di", "known"))
assert(not Q.Allowed("Eve", "known") and not Q.Allowed("Eve", "group") and Q.Allowed("Di", "group") and not Q.Allowed("Ann", "group"))
assert(Q.Allowed("Ann", "friends") and not Q.Allowed("Cy", "friends") and Q.Allowed("Cy", "friendsGuild") and not Q.Allowed("Di", "friendsGuild"))
assert(not Q.Allowed("Ann", "nobody") and Q.Allowed("Eve", "anyone") and Q.Allowed(nil, "anyone"))
assert(not Q.Allowed(nil, "known") and not Q.Allowed("", "known"), "no name, no exception")
assert(Q.Normal(12) == nil and Q.Normal("Name-Realm") == "name")

---------------------------------------------------------------------------
-- Accept summons
---------------------------------------------------------------------------
Reset(); W.friends = { "Mira" }; W.guild = { "Cy" }
On("qolSummons", true); Apply(S.feature)
assert(Listening("CONFIRM_SUMMON") and Listening("CANCEL_SUMMON"), "listens once on")
assert(calls.roster == 1, "the guild roster is asked for once when a feature that reads it comes on")
Apply(S.feature); Apply(D.feature); assert(calls.roster == 1, "and not again")
c.FireEvent("CONFIRM_SUMMON", 0, false)
assert(calls.confirm == 0, "waits first (the pop-up stays for the player)")
RunLongTimers(2); assert(calls.confirm == 0, "not before the wait is over")
RunLongTimers(3); assert(calls.confirm == 1 and calls.hidden[1] == "CONFIRM_SUMMON", "accepted after the wait, and only that pop-up hidden")
RunLongTimers(60); assert(calls.confirm == 1, "one accept per summon")

Reset(); W.friends = { "Mira" }; Q.Set("summonsWait", 0)
c.FireEvent("CONFIRM_SUMMON", 0, false); assert(calls.confirm == 1, "no wait: at once")
c.FireEvent("CONFIRM_SUMMON", 0, false); assert(calls.confirm == 2, "a second summon is a new one")
Q.Set("summonsWait", 3)

Reset(); -- a stranger under the default source
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0, "strangers are not accepted by default")
Q.Set("summonsFrom", "anyone"); c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 1, "anyone: accepted")
Reset(); W.summon.who = nil; c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 1, "anyone: even with no name")
Q.Set("summonsFrom", "group"); Reset(); W.friends = { "Mira" }
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0, "group only: a friend outside it is not accepted")
W.group = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 1, "group only: a group member is")
Q.Set("summonsFrom", "known")

Reset(); W.friends = { "Mira" }; W.summon.who = nil
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0, "no summoner name: not accepted under a restricted source")

Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 1, false); RunLongTimers(60)
assert(calls.confirm == 0, "a scenario summon is left to the player")
c.FireEvent("CONFIRM_SUMMON", 0, true); RunLongTimers(60); assert(calls.confirm == 0, "so is one that skips the starting experience")

Reset(); W.friends = { "Mira" }; W.combat = true
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0, "not in combat")
W.combat = false; W.canTeleport = false
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0, "not when the game won't let you teleport")

Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); W.combat = true
RunLongTimers(60); assert(calls.confirm == 0, "combat that starts during the wait stops it")
Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); c.FireEvent("CANCEL_SUMMON")
RunLongTimers(60); assert(calls.confirm == 0, "a withdrawn summon is not accepted")
Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); W.summon.who = "Zed"
RunLongTimers(60); assert(calls.confirm == 0, "a different summoner is a different summon")
Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); W.summon.area = "Elsewhere"
RunLongTimers(60); assert(calls.confirm == 0, "so is a different place")
Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); W.summon.left = 0
RunLongTimers(60); assert(calls.confirm == 0, "an expired summon is not accepted")
Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false); c.FireEvent("CONFIRM_SUMMON", 0, false)
RunLongTimers(60); assert(calls.confirm == 1, "two events for one summon: one accept")

Reset(); W.friends = { "Mira" }; c.FireEvent("CONFIRM_SUMMON", 0, false)
On("qolSummons", false); Apply(S.feature)
assert(not Listening("CONFIRM_SUMMON") and not Listening("CANCEL_SUMMON"), "turned off: no listening")
RunLongTimers(60); assert(calls.confirm == 0, "turned off during the wait: nothing is accepted")
c.FireEvent("CONFIRM_SUMMON", 0, false); RunLongTimers(60); assert(calls.confirm == 0)

---------------------------------------------------------------------------
-- Accept resurrection
---------------------------------------------------------------------------
Reset(); On("qolResurrect", true); Apply(Rez.feature)
assert(Listening("RESURRECT_REQUEST") and Listening("PLAYER_ALIVE"))
W.offerer = "Pat"; c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 1, "an ordinary offer is accepted")
c.FireEvent("RESURRECT_REQUEST", ""); assert(calls.accept == 1, "no offerer name: left alone")
c.FireEvent("RESURRECT_REQUEST", nil); assert(calls.accept == 1)

Reset(); W.offerer = "Pat"; W.sickness = true; c.FireEvent("RESURRECT_REQUEST", "Pat")
assert(calls.accept == 0, "an offer with resurrection sickness is the player's call")
Reset(); W.offerer = "Pat"; W.hardcore = true; c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 0, "never on Hardcore rules")

-- combat resurrection: judged by a group member being in combat
Reset(); W.offerer = "Pat"; W.group = { "Pat" }; W.groupCombat.party1 = true
c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 0, "a combat resurrection from the group is not accepted by default")
On("qolResurrectCombat", true); c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 1, "accepted when the separate option is on")
On("qolResurrectCombat", false)
Reset(); W.offerer = "Pat"; W.group = { "Pat" }; c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 1, "a group member out of combat is accepted")
Reset(); W.offerer = "Pat"; c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 1, "someone outside the group can't be seen in combat: ordinary")

-- the game's own wait is kept
Reset(); W.offerer = "Pat"; W.corpseDelay = 30
c.FireEvent("RESURRECT_REQUEST", "Pat"); assert(calls.accept == 0, "not during the game's wait")
RunLongTimers(20); assert(calls.accept == 0)
W.corpseDelay = 0; RunLongTimers(31); assert(calls.accept == 1, "accepted once the wait is over")
RunLongTimers(60); assert(calls.accept == 1, "once")
Reset(); W.offerer = "Pat"; W.corpseDelay = 30; c.FireEvent("RESURRECT_REQUEST", "Pat"); W.offerer = nil
W.corpseDelay = 0; RunLongTimers(60); assert(calls.accept == 0, "an offer that no longer stands isn't accepted")
Reset(); W.offerer = "Pat"; W.corpseDelay = 30; c.FireEvent("RESURRECT_REQUEST", "Pat"); W.offerer = "Quin"
RunLongTimers(60); assert(calls.accept == 0, "a different offerer isn't the offer we waited for")
Reset(); W.offerer = "Pat"; W.corpseDelay = 30; c.FireEvent("RESURRECT_REQUEST", "Pat"); c.FireEvent("PLAYER_ALIVE")
W.corpseDelay = 0; RunLongTimers(60); assert(calls.accept == 0, "coming back to life ends the plan")
Reset(); W.offerer = "Pat"; W.corpseDelay = 30; c.FireEvent("RESURRECT_REQUEST", "Pat"); W.corpseDelay = 5
RunLongTimers(60); assert(calls.accept == 0, "a wait that has not really ended is not skipped, and there is no retry")
Reset(); W.offerer = "Pat"; W.corpseDelay = 30; c.FireEvent("RESURRECT_REQUEST", "Pat")
On("qolResurrect", false); Apply(Rez.feature); assert(not Listening("RESURRECT_REQUEST"))
W.corpseDelay = 0; RunLongTimers(60); assert(calls.accept == 0, "turned off: the plan is cancelled")

---------------------------------------------------------------------------
-- Release in battlegrounds
---------------------------------------------------------------------------
Reset(); W.instance = { true, "pvp" }
On("qolReleasePvP", true); Apply(Rel.feature)
assert(Listening("PLAYER_DEAD") and Listening("RESURRECT_REQUEST") and Listening("PLAYER_ENTERING_WORLD"))
c.FireEvent("PLAYER_DEAD"); assert(calls.repop == 0, "waits first")
RunLongTimers(1); assert(calls.repop == 0)
RunLongTimers(2); assert(calls.repop == 1, "released after the wait in a battleground")
RunLongTimers(60); assert(calls.repop == 1, "once")

for _, where in ipairs({ { false, "none" }, { true, "party" }, { true, "raid" }, { true, "scenario" }, { true, "arena" } }) do
  Reset(); W.instance = where; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60)
  assert(calls.repop == 0, "never released in '" .. where[2] .. "'")
end

Reset(); W.instance = { true, "pvp" }; W.hardcore = true; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 0, "never on Hardcore rules")
Reset(); W.instance = { true, "pvp" }; W.selfRes = { { optionType = 0, id = 1 } }; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60)
assert(calls.repop == 0, "not with a self-resurrection on offer")
Reset(); W.instance = { true, "pvp" }; W.selfRes = {}; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 1, "an empty list is no option")
Reset(); W.instance = { true, "pvp" }; W.offerer = "Pat"; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 0, "not with a resurrection already on offer")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); W.offerer = "Pat"; RunLongTimers(60)
assert(calls.repop == 0, "an offer that stands when the wait ends stops the release")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); c.FireEvent("RESURRECT_REQUEST", "Pat"); RunLongTimers(60)
assert(calls.repop == 0, "an offer arriving during the wait cancels the release even if the offer later goes")
Reset(); W.instance = { true, "pvp" }; W.releaseRemaining = 0; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 0, "not when the game says no release")
Reset(); W.instance = { true, "pvp" }; W.releaseRemaining = 30; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 1, "a release timer is fine")
Reset(); W.instance = { true, "pvp" }; W.falling = true; c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 0, "not while falling (the game's button is off too)")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); W.shift = true; RunLongTimers(60); assert(calls.repop == 0, "Shift as the wait ends keeps the body")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); W.ghost = true; RunLongTimers(60); assert(calls.repop == 0, "already a ghost: nothing to do")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); c.FireEvent("PLAYER_ALIVE"); RunLongTimers(60); assert(calls.repop == 0, "getting up ends the plan")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); W.instance = { false, "none" }; c.FireEvent("PLAYER_ENTERING_WORLD"); RunLongTimers(60)
assert(calls.repop == 0, "leaving ends the plan")
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD"); c.FireEvent("PLAYER_DEAD"); RunLongTimers(60); assert(calls.repop == 1, "repeated events: one release")
Reset(); W.instance = { true, "pvp" }; Q.Set("releaseWait", 0); c.FireEvent("PLAYER_DEAD"); assert(calls.repop == 1, "no wait: at once"); Q.Set("releaseWait", 2)
Reset(); W.instance = { true, "pvp" }; c.FireEvent("PLAYER_DEAD")
On("qolReleasePvP", false); Apply(Rel.feature); assert(not Listening("PLAYER_DEAD"))
RunLongTimers(60); assert(calls.repop == 0, "turned off: the plan is cancelled")

-- Accept resurrection and Release together: they can't contradict each other.
Reset(); W.instance = { true, "pvp" }
On("qolResurrect", true); On("qolReleasePvP", true); Apply(Rez.feature); Apply(Rel.feature)
c.FireEvent("PLAYER_DEAD"); W.offerer = "Pat"; c.FireEvent("RESURRECT_REQUEST", "Pat")
assert(calls.accept == 1, "the offer is accepted")
RunLongTimers(60); assert(calls.repop == 0, "and the release it would have raced with never happens")
On("qolResurrect", false); On("qolReleasePvP", false); Apply(Rez.feature); Apply(Rel.feature)

---------------------------------------------------------------------------
-- Block duels
---------------------------------------------------------------------------
Reset(); On("qolDuels", true); Apply(D.feature)
assert(Listening("DUEL_REQUESTED") and not Listening("DUEL_TO_THE_DEATH_REQUESTED"), "duels to the death are separate and off")
c.FireEvent("DUEL_REQUESTED", "Eve"); assert(calls.cancelDuel == 1 and calls.hidden[1] == "DUEL_REQUESTED", "a stranger is declined")
c.FireEvent("DUEL_REQUESTED", nil); assert(calls.cancelDuel == 2, "no name: declined")
W.friends = { "Ann" }; W.guild = { "Cy" }; W.group = { "Di" }
for _, who in ipairs({ "Ann", "Cy", "Di" }) do c.FireEvent("DUEL_REQUESTED", who) end
assert(calls.cancelDuel == 2, "friends, guild and group members still get to answer")
Q.Set("duelsFrom", "friends"); c.FireEvent("DUEL_REQUESTED", "Cy"); assert(calls.cancelDuel == 3, "friends only: the guild member is declined")
c.FireEvent("DUEL_REQUESTED", "Ann"); assert(calls.cancelDuel == 3)
Q.Set("duelsFrom", "nobody"); c.FireEvent("DUEL_REQUESTED", "Ann"); assert(calls.cancelDuel == 4, "nobody: everyone is declined")
Q.Set("duelsFrom", "known")
for _, which in ipairs(calls.hidden) do assert(which == "DUEL_REQUESTED", "only the duel pop-up is hidden: " .. which) end

Reset(); On("qolDuelsToDeath", true); Apply(D.feature); assert(Listening("DUEL_TO_THE_DEATH_REQUESTED"), "added when chosen, without a reload")
c.FireEvent("DUEL_TO_THE_DEATH_REQUESTED", "Eve")
assert(calls.cancelDuel == 1 and calls.hidden[1] == "DUEL_TO_THE_DEATH_REQUESTED" and calls.hidden[2] == "DUEL_TO_THE_DEATH_REQUESTED_CONFIRM")
W.friends = { "Ann" }; c.FireEvent("DUEL_TO_THE_DEATH_REQUESTED", "Ann"); assert(calls.cancelDuel == 1, "the same exceptions apply")
On("qolDuelsToDeath", false); Apply(D.feature); assert(not Listening("DUEL_TO_THE_DEATH_REQUESTED") and Listening("DUEL_REQUESTED"), "and dropped again")
On("qolDuels", false); Apply(D.feature); assert(not Listening("DUEL_REQUESTED"), "off: duels are the game's again")
Reset(); c.FireEvent("DUEL_REQUESTED", "Eve"); assert(calls.cancelDuel == 0)
On("qolDuelsToDeath", true); Apply(D.feature); assert(not Listening("DUEL_TO_THE_DEATH_REQUESTED"), "the sub-option does nothing without the main one")


---------------------------------------------------------------------------
-- Quick Keybind button: a stand-in Game Menu with the game's pool, layout indices and callback.
---------------------------------------------------------------------------
local K = R.QoLQuickKeybind
local function NewButton()
  local b = { shown = false, enabled = true, scripts = {} }
  function b:SetText(t) self.text = t end
  function b:GetText() return self.text end
  function b:SetScript(k, f) self.scripts[k] = f end
  function b:SetEnabled(v) self.enabled = v end
  function b:SetMotionScriptsWhileDisabled() end
  function b:Show() self.shown = true end
  return b
end
local menu = { shown = false, dirty = 0, nextLayoutIndex = 1, active = {} }
menu.buttonPool = {
  Acquire = function() local b = NewButton(); menu.active[b] = true; return b end,
  Release = function(_, b) menu.active[b] = nil; b.shown = false; b.layoutIndex = nil end,
  IsActive = function(_, b) return menu.active[b] == true end,
  EnumerateActive = function() return pairs(menu.active) end,
}
function menu:IsShown() return self.shown end
function menu:MarkDirty() self.dirty = self.dirty + 1 end
local hooks = {}
c.hooksecurefunc = function(obj, name, fn)
  local orig = obj[name]
  obj[name] = function(...) local r = orig(...); fn(...); return r end
  hooks[#hooks + 1] = fn
end
c.GameMenuFrame = menu
c.GAMEMENU_OPTIONS = "Options"; c.ADDONS = "AddOns"; c.HUD_EDIT_MODE_MENU = "Edit Mode"; c.GAMEMENU_SUPPORT = "Support"; c.MACROS = "Macros"; local shown = 0; c.QuickKeybindFrame = { Show = function() shown = shown + 1 end }
c.HideUIPanel = function(f) f.shown = false; calls.hideMenu = (calls.hideMenu or 0) + 1 end
local combat = false
c.InCombatLockdown = function() return combat end
-- The game's rebuild (InitButtons): release everything and add its buttons; hooks run after it.
function menu:InitButtons(withOthers)
  for b in pairs(menu.active) do menu.buttonPool:Release(b) end
  menu.nextLayoutIndex = 1
  local names = { "Options", "Store", "AddOns", "Macros", "Log Out", "Return" }
  if withOthers then table.insert(names, 5, "Other addon") end
  for _, text in ipairs(names) do
    local b = menu.buttonPool:Acquire(); b.layoutIndex = menu.nextLayoutIndex; menu.nextLayoutIndex = menu.nextLayoutIndex + 1; b:SetText(text)
  end
end
local function OpenMenu(withOthers) menu.shown = true; menu:InitButtons(withOthers) end
local function Ours() local found; for b in pairs(menu.active) do if b.text == K.LABEL then assert(not found, "exactly one"); found = b end end return found end
local function Order() local list = {}; for b in pairs(menu.active) do list[#list + 1] = b end
  table.sort(list, function(a, b) return a.layoutIndex < b.layoutIndex end)
  for i, b in ipairs(list) do list[i] = b.text; if i > 1 then assert(b.layoutIndex ~= nil) end end return table.concat(list, ",") end

OpenMenu(); assert(not Ours() and #hooks == 0, "off: the menu is the game's")
On("qolQuickKeybind", true); Apply(K.feature)
assert(#hooks == 1 and Listening("PLAYER_REGEN_DISABLED") and Listening("PLAYER_REGEN_ENABLED"))
Apply(K.feature); OpenMenu(true)
assert(Order() == "Options,Store,AddOns,Macros,Quick Keybind,Other addon,Log Out,Return", "got " .. Order())
local indices = {}; for b in pairs(menu.active) do assert(not indices[b.layoutIndex], "unique layout index"); indices[b.layoutIndex] = true end
assert(menu.nextLayoutIndex == 9 and Ours().enabled)
for _ = 1, 3 do OpenMenu() end; Ours(); assert(Order() == "Options,Store,AddOns,Macros,Quick Keybind,Log Out,Return", "reopening: " .. Order())
-- Click: closes the menu, shows the game's own frame.
Ours().scripts.OnClick(); assert(shown == 1 and not menu.shown and calls.hideMenu == 1, "closes the menu and enters the mode")
-- Combat: dimmed with a reason, and a click does nothing; back when combat ends.
OpenMenu(); combat = true; c.FireEvent("PLAYER_REGEN_DISABLED")
assert(not Ours().enabled and Ours().scripts.OnEnter, "disabled in combat"); Ours().scripts.OnClick(); assert(shown == 1, "no entry in combat")
combat = false; c.FireEvent("PLAYER_REGEN_ENABLED"); assert(Ours().enabled and not Ours().scripts.OnEnter, "back after combat")
combat = true; OpenMenu(); assert(not Ours().enabled, "opened in combat: disabled"); combat = false
-- The mode is missing: no button that cannot work.
c.QuickKeybindFrame = nil; OpenMenu(); assert(not Ours(), "no Quick Keybind frame: no button")
c.QuickKeybindFrame = { Show = function() shown = shown + 1 end }
-- Turning it off while the menu is open removes it and closes the gap; nothing is left registered.
OpenMenu(true); On("qolQuickKeybind", false); Apply(K.feature)
assert(not Ours() and Order() == "Options,Store,AddOns,Macros,Other addon,Log Out,Return" and menu.nextLayoutIndex == 8, "removed cleanly: " .. Order())
assert(#hooks == 1 and not Listening("PLAYER_REGEN_DISABLED"), "off: nothing listens; the one hook idles")
OpenMenu(); assert(not Ours())
On("qolQuickKeybind", true); Apply(K.feature); OpenMenu(); assert(Ours(), "and on again without a reload")
On("qolQuickKeybind", false); Apply(K.feature)

-- Nothing is left listening, and toggling is idempotent.
for _, f in ipairs({ S.feature, Rez.feature, Rel.feature, D.feature, K.feature }) do Apply(f); Apply(f) end
for _, event in ipairs({ "CONFIRM_SUMMON", "RESURRECT_REQUEST", "PLAYER_DEAD", "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED" }) do
  assert(not Listening(event), event .. " not registered with everything off")
end
On("qolSummons", true); Apply(S.feature); Apply(S.feature); On("qolSummons", false); Apply(S.feature)
assert(not Listening("CONFIRM_SUMMON"), "one Off undoes any number of Applys")

-- Leatrix Plus: only an advisory, read from its saved choices.
assert(Q.LeatrixOverlap("qolSummons") == false, "not installed")
c.C_AddOns.IsAddOnLoaded = function(n) return n == "Leatrix_Plus" end
c.LeaPlusDB = { AutoAcceptSummon = "On", AutoAcceptRes = "Off" }
assert(Q.LeatrixOverlap("qolSummons") == true and Q.LeatrixOverlap("qolResurrect") == false and Q.LeatrixOverlap("qolDuels") == false)
assert(Q.LeatrixOverlap("noSuchKey") == false)
assert(c.LeaPlusDB.AutoAcceptSummon == "On" and c.LeaPlusDB.AutoAcceptRes == "Off", "Leatrix's settings are never written")

print("QOL TESTS PASSED")
