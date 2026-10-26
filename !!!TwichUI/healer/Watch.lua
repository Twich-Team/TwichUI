-- TwichUI: Healer Watch, reading the game
-- Works out who to watch, reads that one player's mana, life and auras and what they say in the chat channels you
-- chose, and hands the result to Logic.lua and Display.lua. It informs only: it never casts, targets, sends a message
-- or an addon message, and never decides whether anyone is ready.
--
-- Game APIs and events (each documented in the Forever UI source, Blizzard_APIDocumentationGenerated):
--   group: IsInGroup, IsInRaid, GetNumGroupMembers, GetNumSubgroupMembers, UnitGUID, UnitName, UnitIsUnit,
--     UnitGroupRolesAssigned (Forever sets roles through its role poll, the unit menu and the group finder;
--     Blizzard_FrameXML/Mainline/RolePoll.lua, Blizzard_UnitPopupShared), GROUP_ROSTER_UPDATE, PLAYER_ROLES_ASSIGNED;
--   mana: UnitPower / UnitPowerMax with Enum.PowerType.Mana (never the unit's current power type), UNIT_POWER_UPDATE
--     (unit, "MANA"), UNIT_MAXPOWER, UNIT_DISPLAYPOWER. Documented as SecretWhenUnitPowerRestricted: when the values
--     come back secret they are drawn (Display.UpdateSecret) but never compared, so no low or critical state then;
--   life: UnitIsConnected, UnitIsDeadOrGhost, UNIT_CONNECTION, UNIT_FLAGS, UNIT_HEALTH (only the yes/no is read);
--   auras: Drinks.lua (C_UnitAuras.GetAuraDataByIndex, C_Secrets.ShouldAurasBeSecret), UNIT_AURA (unit, updateInfo),
--     ADDON_RESTRICTION_STATE_CHANGED;
--   chat: CHAT_MSG_PARTY, _PARTY_LEADER, _RAID, _RAID_LEADER, _INSTANCE_CHAT, _INSTANCE_CHAT_LEADER, _SAY, _WHISPER
--     (text first, the sender's GUID twelfth). Documented as SecretInChatMessagingLockdown: secret during encounters
--     and "on a communication-restricted map such as a dungeon or raid". A message whose text or sender is secret is
--     skipped and counted, never guessed at; a sender is never matched by name.
--   where: IsInInstance ("party" is a five-player dungeon), PLAYER_ENTERING_WORLD.
-- None of this has been seen in the game; docs/healer-watch.md lists what to check.
--
-- Lifecycle:
--   * Off (the default): no frame, no timer, no event.
--   * On, not where it applies (or nobody to watch): PLAYER_ENTERING_WORLD, GROUP_ROSTER_UPDATE and
--     PLAYER_ROLES_ASSIGNED only. Nothing about any unit is read.
--   * Watching: the unit events for the watched unit alone (RegisterUnitEvent), the chat events of the channels you
--     chose, combat and restriction changes. Mana is read when it changes (two numbers); auras are looked at, coalesced,
--     only when an update could have changed drinking; the roster is read again once per burst of roster events.
--   * Timers: one per coalesced burst, one for the chat signal's expiry, and a one-second tick only while elapsed time is
--     shown on a visible signal. Each carries the life it was made in, so one from before a change does nothing.
--   * Switching it off, a profile change and leaving the world put everything away at once.

local R = TwichUI
local HW, HL, HD, D = R.HealerWatch, R.HealerLogic, R.HealerDrinks, R.HealerDisplay
local W = {}
R.HealerWatcher = W

local COALESCE = 0.1      -- seconds a burst of roster or aura events waits, so it is one read
local DUP_WINDOW = 4      -- seconds: the same message again from the same healer is the same signal
local SOUND_GAP = 15      -- seconds between two chat sounds, at least
local EXCERPT = 40        -- characters of what was said, at most

local evf, unitf
local registered, unitRegistered = {}, {}
local token = 0           -- bumped by Teardown and by a change of who is watched: older timers do nothing
local running, worldSeen, inCombat, scopeActive = false, false, false, false
local cfg
local choice              -- { guid, name }: the player's own choice, for this session only
local sel, obs            -- who is watched, and what is known of them (keyed by GUID, never by unit token)
local shown, reason = false, "off"
local rosterQueued, auraQueued, expiryQueued, tickQueued = false, false, false, false
local lastMsg = { guid = nil, norm = nil, at = -math.huge }
local lastSound
local preview = { active = false, position = false, scenario = "normal" }
local listeners = {}
local stats = { rosterReads = 0, manaReads = 0, auraScans = 0, auraSkipped = 0, chatSeen = 0, chatMatched = 0,
    chatOther = 0, chatSecret = 0, chatNoSender = 0, chatDuplicates = 0, sounds = 0, soundsHeld = 0, renders = 0 }

local CHANNEL = {
    CHAT_MSG_PARTY = "chatParty", CHAT_MSG_PARTY_LEADER = "chatParty", CHAT_MSG_RAID = "chatParty", CHAT_MSG_RAID_LEADER = "chatParty",
    CHAT_MSG_INSTANCE_CHAT = "chatInstance", CHAT_MSG_INSTANCE_CHAT_LEADER = "chatInstance",
    CHAT_MSG_SAY = "chatSay", CHAT_MSG_WHISPER = "chatWhisper",
}
local UNIT_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_HEALTH", "UNIT_AURA" }

---------------------------------------------------------------------------
-- Small readers
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end
local function Plain(v) if Secret(v) then return nil end return v end
local function Mana() return Enum and Enum.PowerType and Enum.PowerType.Mana or 0 end
local function InWorld() return worldSeen or (R.Life ~= nil and R.Life.InWorld()) end
local function Now() return GetTime() end

local function Snapshot()
    local t = {}
    for key in pairs(HW.DEFAULTS) do t[key] = HW.Get(key) end
    t.thresholds = HW.Thresholds()
    t.phrases = HW.Phrases()
    return t
end

-- The settings as Logic and Display read them (a copy, made again after every change).
function W.Config()
    cfg = cfg or Snapshot()
    return cfg
end

local function ScopeActive()
    local s = cfg.scope
    if s == "anywhere" then return true end
    if s == "group" then return Plain(IsInGroup()) == true end
    if not IsInInstance then return false end
    local inInstance, kind = IsInInstance()
    inInstance, kind = Plain(inInstance), Plain(kind)
    if not inInstance then return false end
    if s == "dungeon" then return kind == "party" end
    return kind == "party" or kind == "raid"
end
W.ScopeActive = function() return cfg ~= nil and ScopeActive() end

local ROLES = { HEALER = true, TANK = true, DAMAGER = true }

local function Identity(unit, playerGUID)
    local guid = Plain(UnitGUID(unit))
    if type(guid) ~= "string" or guid == "" then return nil end
    local name, realm = UnitName(unit)
    name, realm = Plain(name), Plain(realm)
    if type(name) ~= "string" or name == "" then return nil end
    local role = Plain(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit))
    if not ROLES[role] then role = nil end
    local full = (type(realm) == "string" and realm ~= "") and (name .. "-" .. realm) or name
    return { guid = guid, name = name, fullName = full, unit = unit, role = role, isPlayer = guid == playerGUID }
end

-- Everyone who could be watched now: you, and each member of your party or raid. A list of new tables.
function W.Candidates()
    local list = {}
    local me = Plain(UnitGUID("player"))
    if Plain(IsInRaid()) == true then
        for i = 1, math.min(Plain(GetNumGroupMembers()) or 0, 40) do
            local c = Identity("raid" .. i, me)
            if c then list[#list + 1] = c end
        end
    else
        local c = Identity("player", me)
        if c then list[#list + 1] = c end
        for i = 1, math.min(Plain(GetNumSubgroupMembers and GetNumSubgroupMembers()) or 0, 4) do
            c = Identity("party" .. i, me)
            if c then list[#list + 1] = c end
        end
    end
    stats.rosterReads = stats.rosterReads + 1
    return list
end

local function NewObs(guid)
    return { guid = guid, life = "unknown", mana = { state = "unknown" }, band = nil, drink = { state = "unknown" }, chat = nil }
end

local function Watching() return running and scopeActive and sel ~= nil and sel.unit ~= nil and not sel.problem end

---------------------------------------------------------------------------
-- Events: exactly the ones needed now
---------------------------------------------------------------------------
local OnEvent, OnUnitEvent

local function SyncEvents()
    local want = {}
    local enabled = R:Enabled("healerWatch")
    if enabled then
        want.PLAYER_ENTERING_WORLD = true
        if InWorld() then
            want.GROUP_ROSTER_UPDATE, want.PLAYER_ROLES_ASSIGNED = true, true
        end
        if Watching() then
            want.PLAYER_REGEN_DISABLED, want.PLAYER_REGEN_ENABLED, want.ADDON_RESTRICTION_STATE_CHANGED = true, true, true
            if cfg.chatDisplay ~= "off" then
                for event, key in pairs(CHANNEL) do
                    if cfg[key] then want[event] = true end
                end
            end
        end
        if preview.active then want.PLAYER_REGEN_DISABLED = true end
    end
    if not evf then
        if next(want) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", function(_, ...) OnEvent(...) end)
    end
    for e in pairs(registered) do
        if not want[e] then evf:UnregisterEvent(e); registered[e] = nil end
    end
    for e in pairs(want) do
        if not registered[e] then evf:RegisterEvent(e); registered[e] = true end
    end

    -- the watched unit's own events, for that unit alone
    local unit = Watching() and sel.unit or nil
    if unit and not unitf then
        unitf = CreateFrame("Frame")
        unitf:SetScript("OnEvent", function(_, ...) OnUnitEvent(...) end)
    end
    if unitf then
        for _, e in ipairs(UNIT_EVENTS) do
            if unitRegistered[e] ~= unit then
                if unitRegistered[e] then unitf:UnregisterEvent(e) end
                if unit then unitf:RegisterUnitEvent(e, unit) end
                unitRegistered[e] = unit
            end
        end
    end
end

---------------------------------------------------------------------------
-- Reading the watched player
---------------------------------------------------------------------------
-- Returns true when what is shown could have changed, and whether mana just became critical.
local function ReadMana()
    if not Watching() then return false end
    stats.manaReads = stats.manaReads + 1
    local unit, M = sel.unit, obs.mana
    local cur, max = UnitPower(unit, Mana()), UnitPowerMax(unit, Mana())
    local before, beforeBand, beforePct = M.state, obs.band, M.pct
    if Secret(cur) or Secret(max) then
        M.state, M.cur, M.max, M.pct = "secret", nil, nil, nil
        obs.band = nil
    elseif type(cur) == "number" and type(max) == "number" and cur == cur and max == max then
        if max > 0 then
            M.state, M.cur, M.max = "ok", cur, max
            M.pct = math.max(0, math.min(100, cur / max * 100))
            obs.band = HL.NextBand(obs.band, M.pct, cfg.thresholds)
        else
            M.state, M.cur, M.max, M.pct = "none", nil, nil, nil   -- no mana pool reported: not the same as 0%
            obs.band = nil
        end
    else
        M.state, M.cur, M.max, M.pct = "unknown", nil, nil, nil
        obs.band = nil
    end
    return before ~= M.state or beforeBand ~= obs.band or beforePct ~= M.pct or M.state == "secret",
        obs.band == "critical" and beforeBand ~= "critical"
end

local function ReadLife()
    if not Watching() then return false end
    local unit = sel.unit
    local online, dead = Plain(UnitIsConnected(unit)), Plain(UnitIsDeadOrGhost(unit))
    local life = "unknown"
    if online == false then life = "offline"
    elseif dead == true then life = "dead"
    elseif online == true and dead == false then life = "alive" end
    if life == obs.life then return false end
    obs.life = life
    return true
end

local drinkBegan = false   -- the last scan found drinking beginning
local function ScanDrink()
    if not Watching() then return false end
    stats.auraScans = stats.auraScans + 1
    local d = obs.drink
    local state, evidence, inst = HD.Scan(sel.unit)
    if d.state == state and d.evidence == evidence and d.instance == inst then return false end
    drinkBegan = state == "yes" and (d.state == "no" or d.state == "hidden")   -- not at the first look at someone
    d.state, d.evidence, d.instance = state, evidence, inst
    return true
end

---------------------------------------------------------------------------
-- Deciding and drawing
---------------------------------------------------------------------------
local function Tell()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("healer watch", err) end
    end
end

local ScheduleTick

local function Update()
    if preview.active then
        local now = Now()
        local s, o = HL.Scenario(preview.scenario, now)
        D.Render(HL.Present(s, o, cfg, now), cfg, preview.position and "position" or "preview")
        reason = "preview"
        Tell()
        return
    end
    local now = Now()
    local show, why = false, "off"
    if running then
        show, why = HL.Visible({ enabled = true, scopeActive = scopeActive, inCombat = inCombat, sel = sel, obs = obs, now = now }, cfg)
    end
    reason = why
    if show then
        local v = HL.Present(sel, obs, cfg, now)
        D.Render(v, cfg, "live")
        if v.manaSecret or v.secretBar then D.UpdateSecret(sel.unit, cfg) end
        stats.renders = stats.renders + 1
    elseif cfg then
        D.Hide(false, cfg)
    end
    shown = show
    if show and cfg.showElapsed then ScheduleTick() end
    Tell()
end

-- A full read of the watched player (a new selection, a new unit, the world, the end of combat).
local function ReadAll()
    if not Watching() then return end
    ReadLife()
    ReadMana()
    ScanDrink()
end

---------------------------------------------------------------------------
-- Timers (each guarded by the life it was made in)
---------------------------------------------------------------------------
local function After(seconds, fn)
    local mine = token
    C_Timer.After(seconds, function()
        if mine ~= token then return end
        fn()
    end)
end

local Roster

local function RosterSoon()
    if rosterQueued then return end
    rosterQueued = true
    After(COALESCE, function()
        rosterQueued = false
        Roster()
    end)
end

local function AuraSoon()
    if auraQueued then return end
    auraQueued = true
    After(COALESCE, function()
        auraQueued = false
        if ScanDrink() then
            local began = drinkBegan
            Update()
            if began then D.Flash("drinking", cfg) end
        end
    end)
end

local function ScheduleExpiry()
    if expiryQueued or not (obs and obs.chat) then return end
    expiryQueued = true
    local left = obs.chat.at + cfg.chatExpiry - Now()
    After(math.max(0.05, left + 0.05), function()
        expiryQueued = false
        if not (obs and obs.chat) then return end
        if HL.ChatActive(obs.chat, Now(), cfg.chatExpiry) then
            ScheduleExpiry()   -- a newer message moved the end on
        else
            obs.chat = nil
            Update()
        end
    end)
end

-- Elapsed time ("4s ago") is redrawn once a second, only while it is shown on a current signal.
function ScheduleTick()
    if tickQueued or not (shown and obs and HL.ChatActive(obs.chat, Now(), cfg.chatExpiry)) then return end
    tickQueued = true
    After(1, function()
        tickQueued = false
        if shown and obs and obs.chat then Update() end
    end)
end

---------------------------------------------------------------------------
-- Who is watched
---------------------------------------------------------------------------
-- Reads the group and works out who to watch. A different person (or nobody) means nothing observed of the last one
-- carries over: mana, drinking and their chat signal are cleared, and timers made for them do nothing.
local function Resolve()
    local list = W.Candidates()
    local me = Plain(UnitGUID("player"))
    -- leaving the group ends a choice of someone else: it was for that group
    if choice and choice.guid ~= me and Plain(IsInGroup()) ~= true then choice = nil end
    local new = HL.Resolve(list, choice)
    if not obs or obs.guid ~= new.guid then
        token = token + 1
        rosterQueued, auraQueued, expiryQueued, tickQueued = false, false, false, false
        obs = new.guid and NewObs(new.guid) or nil
    end
    local unitChanged = (sel and sel.unit) ~= new.unit
    sel = new
    return unitChanged
end

function Roster()
    if not running then return end
    scopeActive = ScopeActive()
    local unitChanged = Resolve()
    SyncEvents()
    -- the same person in another party slot keeps what was seen in chat; mana, life and auras are read again for the
    -- unit they are now, so nothing read from the old slot is shown as theirs
    if unitChanged then ReadAll() end
    Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function PlaySound()
    if not PlaySoundFile then return false end
    local path = R:ResolveSound(cfg.chatSoundName) or R:ResolveSound(HW.DEFAULTS.chatSoundName)
    if not path then return false end
    return PlaySoundFile(path, "SFX") and true or false
end

local function OnChat(event, text, guid)
    stats.chatSeen = stats.chatSeen + 1
    if not (Watching() and obs and cfg[CHANNEL[event]]) or cfg.chatDisplay == "off" then return end
    if Secret(text) or Secret(guid) then stats.chatSecret = stats.chatSecret + 1 return end
    if type(guid) ~= "string" or guid == "" then stats.chatNoSender = stats.chatNoSender + 1 return end
    if guid ~= sel.guid then stats.chatOther = stats.chatOther + 1 return end   -- only the watched healer, by GUID
    if type(text) ~= "string" then return end
    local i, phrase = HL.Match(text, cfg.phrases)
    if not i then return end
    local now = Now()
    local norm = HL.Normalize(text)
    if lastMsg.guid == guid and lastMsg.norm == norm and now - lastMsg.at < DUP_WINDOW then
        stats.chatDuplicates = stats.chatDuplicates + 1
        return
    end
    lastMsg.guid, lastMsg.norm, lastMsg.at = guid, norm, now
    stats.chatMatched = stats.chatMatched + 1
    local began = not HL.ChatActive(obs.chat, now, cfg.chatExpiry)
    obs.chat = { phrase = phrase.text, mode = phrase.mode, excerpt = HL.Excerpt(text, EXCERPT), channel = CHANNEL[event], at = now }
    ScheduleExpiry()
    Update()
    if began then D.Flash("chat", cfg) end
    if began and shown and cfg.chatSound then
        if lastSound and now - lastSound < SOUND_GAP then
            stats.soundsHeld = stats.soundsHeld + 1
        else
            lastSound = now
            if PlaySound() then stats.sounds = stats.sounds + 1 end
        end
    end
end

function OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        worldSeen = true
        W.Refresh()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        RosterSoon()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if preview.active then W.PreviewStop() end   -- a preview or a move never carries into a fight
        if Watching() then AuraSoon() end           -- auras are usually kept from addons in combat
        Update()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if Watching() then ReadAll() end
        Update()
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if Watching() then
            local changed = ReadMana()
            AuraSoon()
            if changed then Update() end
        end
    elseif CHANNEL[event] then
        local text = ...
        local guid = select(12, ...)
        OnChat(event, text, guid)
    end
end

function OnUnitEvent(event, unit, arg)
    if not (Watching() and unit == sel.unit) then return end
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if Secret(arg) or arg ~= "MANA" then return end
        local changed, critical = ReadMana()
        if changed then
            Update()
            if critical then D.Pulse(cfg); D.Flash("critical", cfg) end
        end
    elseif event == "UNIT_DISPLAYPOWER" then
        if ReadMana() then Update() end
    elseif event == "UNIT_AURA" then
        if HD.MayChange(arg, obs.drink.instance) then AuraSoon() else stats.auraSkipped = stats.auraSkipped + 1 end
    else   -- UNIT_CONNECTION, UNIT_FLAGS, UNIT_HEALTH: only whether they are online and alive
        if ReadLife() then
            if obs.life == "alive" then ReadMana(); ScanDrink() end
            Update()
        end
    end
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe at any time.
---------------------------------------------------------------------------
local function Teardown()
    token = token + 1
    running, scopeActive = false, false
    rosterQueued, auraQueued, expiryQueued, tickQueued = false, false, false, false
    preview.active, preview.position = false, false
    sel, obs, shown, reason = nil, nil, false, "off"
    lastMsg.guid, lastMsg.norm, lastMsg.at = nil, nil, -math.huge
    D.Hide(true)
    SyncEvents()
    Tell()
end

function W.Refresh()
    cfg = Snapshot()
    if not R:Enabled("healerWatch") then
        if running or evf or preview.active or shown then Teardown() end
        return
    end
    if not InWorld() then
        running = false
        SyncEvents()
        return
    end
    running = true
    inCombat = InCombatLockdown() == true or (UnitAffectingCombat ~= nil and Plain(UnitAffectingCombat("player")) == true)
    scopeActive = ScopeActive()
    Resolve()
    SyncEvents()
    ReadAll()
    Update()
end

-- A setting changed: the settings are read again; the group only when where it applies changed.
local function Reconfigure(what)
    local before = cfg and cfg.scope
    cfg = Snapshot()
    if what == "place" then
        D.Place(cfg)
        return
    end
    if what == "profile" then preview.active, preview.position = false, false end
    if not running or before ~= cfg.scope or what == "profile" then W.Refresh() return end
    D.Invalidate()
    if Watching() and obs.mana.state == "ok" then obs.band = HL.NextBand(obs.band, obs.mana.pct, cfg.thresholds) end
    SyncEvents()
    Update()
end
HW.Subscribe(function(what) Reconfigure(what) end)

---------------------------------------------------------------------------
-- Choosing who to watch (the settings window). Lasts for this session; nothing is saved.
---------------------------------------------------------------------------
-- guid nil or "auto": back to automatic. Returns true, or false and a sentence.
function W.Choose(guid)
    if guid == nil or guid == "auto" then
        choice = nil
    else
        local found
        for _, c in ipairs(W.Candidates()) do if c.guid == guid then found = c end end
        if not found then return false, "That player isn't in your group now." end
        choice = { guid = found.guid, name = found.name }
    end
    if running then Roster() else Tell() end
    return true
end

-- The group as a list for a picker: { { value = "auto" | guid, label }, ... } and the current value. Shared by the
-- settings window's dropdown and the quick-select menu on the panel.
function W.PickerChoices()
    local list = { { "auto", "Automatic (the one with the Healer role)" } }
    local chosen, chosenName = W.Choice()
    local present = chosen == "auto"
    for _, c in ipairs(W.Candidates()) do
        local label = c.isPlayer and ("You (" .. c.name .. ")") or c.fullName
        if c.role == "HEALER" then label = label .. " - Healer role" end
        list[#list + 1] = { c.guid, label }
        if c.guid == chosen then present = true end
    end
    if not present then list[#list + 1] = { chosen, (chosenName or "Your choice") .. " (not in your group)" } end
    return list, chosen
end

-- The quick-select menu, from a click on the panel while it asks you to choose. Choosing changes only who is watched.
function W.OpenPicker(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    local list, chosen = W.PickerChoices()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Watch which healer?")
        for _, entry in ipairs(list) do
            local value = entry[1]
            local function Is() return value == W.Choice() end
            local function Pick() W.Choose(value) end
            if root.CreateRadio then root:CreateRadio(entry[2], Is, Pick) else root:CreateButton(entry[2], Pick) end
        end
    end)
    return true
end
D.onPick = function(owner) W.OpenPicker(owner) end

-- "auto", or the chosen GUID, and the chosen name.
function W.Choice()
    if not choice then return "auto" end
    return choice.guid, choice.name
end

-- Who is watched and why, for the settings window: a copy.
function W.Selection()
    if not sel then
        if not cfg then cfg = Snapshot() end
        local s = HL.Resolve(W.Candidates(), choice)
        return { name = s.name, source = s.source, problem = s.problem, unit = s.unit, guid = s.guid, live = false }
    end
    return { name = sel.name, source = sel.source, problem = sel.problem, unit = sel.unit, guid = sel.guid, live = true }
end

---------------------------------------------------------------------------
-- Preview and moving (settings). Never in combat; only while Healer Watch is on. The live readings are kept and not
-- touched; the preview draws a scenario's own made-up tables in the same frame, so the two never sit on top of each
-- other, and the live panel comes back when it ends.
---------------------------------------------------------------------------
function W.SetScenario(key)
    for _, s in ipairs(HL.SCENARIOS) do
        if s[1] == key then
            preview.scenario = key
            if preview.active then Update() end
            Tell()
            return true
        end
    end
    return false
end
function W.Scenario() return preview.scenario end

-- The view a scenario gives with the settings as they are (the settings window's inline preview).
function W.ScenarioView(key)
    local now = Now()
    local s, o = HL.Scenario(key or preview.scenario, now)
    return HL.Present(s, o, W.Config(), now)
end

function W.PreviewActive() return preview.active end
function W.PositioningActive() return preview.active and preview.position end

function W.PreviewStart(moving)
    if not R:Enabled("healerWatch") then return false, "off" end
    if InCombatLockdown() then return false, "combat" end
    cfg = cfg or Snapshot()
    preview.active = true
    preview.position = moving and true or false
    SyncEvents()
    Update()
    return true
end

function W.PreviewStop()
    if not preview.active then return end
    preview.active, preview.position = false, false
    SyncEvents()
    D.Hide(true)
    Update()
end

function W.PositionEnd()
    if not preview.position then return end
    preview.position = false
    Update()
end

-- "Try the flash": the chosen kind in the panel while a preview is showing. Returns whether it flashed.
function W.TestFlash(kind)
    if not preview.active then return false, "preview" end
    if not D.Flash(kind or "chat", cfg, true) then return false, "motion" end
    return true
end

function W.ResetPosition() HW.ResetPlace() end

D.onMoved = function() if cfg then D.Place(cfg) end end
D.onPositionEnd = function() W.PositionEnd() end
D.onInvalidate = function() if shown or preview.active then Update() end end

-- A sample message against the phrases in use: index, phrase (nil when none). Nothing is sent or remembered.
function W.TestPhrase(text) return HL.Match(text, HW.Phrases()) end

-- fn() after anything the settings window shows changed (a reading, a decision, a choice).
function W.OnChange(fn) listeners[#listeners + 1] = fn end

---------------------------------------------------------------------------
-- Status, for the settings window's diagnostics, /tui diagnostics and the tests: plain values only
---------------------------------------------------------------------------
function W.Snapshot()
    local events = 0
    for _ in pairs(registered) do events = events + 1 end
    for _, u in pairs(unitRegistered) do if u then events = events + 1 end end
    local now = Now()
    local s = {
        enabled = R:Enabled("healerWatch"), running = running, inWorld = InWorld(), scopeActive = scopeActive,
        scope = cfg and cfg.scope, inCombat = inCombat, shown = shown, reason = reason, events = events,
        preview = preview.active, positioning = preview.position, scenario = preview.scenario,
        choice = choice ~= nil, drinkName = HD.Name(), secretRefused = D.SecretRefused(),
    }
    if sel then
        s.source, s.problem, s.name, s.unit, s.guid = sel.source, sel.problem, sel.name, sel.unit, sel.guid
    end
    if obs then
        s.life, s.mana, s.manaPct, s.band = obs.life, obs.mana.state, obs.mana.pct, obs.band
        s.manaCur, s.manaMax = obs.mana.cur, obs.mana.max
        s.drink, s.drinkEvidence = obs.drink.state, obs.drink.evidence
        if obs.chat and cfg and HL.ChatActive(obs.chat, now, cfg.chatExpiry) then
            s.chatPhrase, s.chatLeft = obs.chat.phrase, math.max(0, obs.chat.at + cfg.chatExpiry - now)
        end
    end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then s.aurasSecret = C_Secrets.ShouldAurasBeSecret() == true end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok then s.chatLockdown = locked == true end
    end
    if C_Secrets and C_Secrets.GetPowerTypeSecrecy then
        local ok, level = pcall(C_Secrets.GetPowerTypeSecrecy, Mana())
        if ok and not Secret(level) then s.manaSecrecy = level end
    end
    for k, v in pairs(stats) do s[k] = v end
    return s
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
R:OnInit(function() W.Refresh() end)
R:On("PLAYER_LEAVING_WORLD", function()
    worldSeen = false
    if running then Teardown() end
end)
R.OnSettingsClosed(function()
    -- the sample goes away with the settings window; moving (an explicit, visible mode) is left to its own end
    if preview.active and not preview.position then W.PreviewStop() end
end)
