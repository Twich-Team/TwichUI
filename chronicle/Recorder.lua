-- TwichUI: Journey Chronicle, automatic entries
-- Writes entries for the moments the player chose to record. It never looks
-- back: only things that happen while tracking is on are written. Events are
-- registered only while they're switched on and removed again when they're
-- turned off. An added entry is mentioned once in your own chat frame
-- (never sent to anyone), unless that's switched off. No popups.

local R = TwichUI
local C = R.Chronicle
local Rec = {}
R.ChronicleRecorder = Rec

local lastZone               -- the zone we last saw, so arriving isn't recorded at login
local zoneBaselined = false  -- true once lastZone is a real zone seen this session; until then nothing is an arrival
local baselineTries = 0      -- looks already spent waiting for the zone to be known after login
local active = {}            -- [event] = handler, while registered
local inWorld = false        -- true once the first PLAYER_ENTERING_WORLD has run
local controlLost = false    -- between PLAYER_CONTROL_LOST and PLAYER_CONTROL_GAINED (flight takeoff to landing)

local COPPER_PER_GOLD = 10000
Rec.GOLD_STEPS = { 10, 50, 100, 500, 1000, 5000, 10000 }

-- Riding ranks, by the spell that teaches them. These two IDs came from the player and haven't
-- been confirmed against the Forever client; the name from the game is used when it gives one.
-- Higher ranks are not listed because their IDs are not known yet.
Rec.RIDING = { [33388] = "Apprentice Riding", [33391] = "Journeyman Riding" }

local PLAYED_TIMEOUT = 10    -- seconds to wait for the played-time answer before leaving an entry as is

local function On(key) return R:Enabled("chronicle") and R:Enabled(key) end

local function Changed()
    if R.ChronicleWindow then R.ChronicleWindow:Refresh() end
end

-- Adds an automatic entry. Only an entry that was really written is mentioned
-- in chat, so duplicates and a full log stay silent.
local function Commit(kind, fields)
    local entry = C.Add(kind, fields)
    if not entry then return nil end
    Changed()
    if R:Enabled("chronicleChat") then
        local icon = R.ChronicleStyle and R.ChronicleStyle.icons
        icon = fields.icon or (icon and (icon[kind] or icon.start))
        print(("%s%sChronicle:|r %s"):format(icon and ("|T" .. icon .. ":14:14|t ") or "", R.GREY, entry.title))
    end
    return entry
end

local function Plain(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    return text
end

---------------------------------------------------------------------------
-- Played time. RequestTimePlayed() answers later with TIME_PLAYED_MSG(total, thisLevel). Right
-- after a level-up we don't rely on "thisLevel" (it may already be the new level). Instead
-- we keep the total played time at which the current level began and subtract.
---------------------------------------------------------------------------
local waitBaseline = false   -- a baseline for the current level was asked for
local waitLevels = {}        -- { {id, level}, ... } level-up entries waiting for the answer
local playedToken            -- identifies the request the timeout belongs to
local muted                  -- chat frames we took TIME_PLAYED_MSG from, to give back
local playedWaiters = {}     -- callbacks (the Chronicle header) waiting for the total played time

local function Journey() return C.Record().journey end

-- Blizzard's chat prints "Total time played" for any answer; keep our own request quiet.
local function MuteChat()
    if muted or not NUM_CHAT_WINDOWS then return end
    muted = {}
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = frame
        end
    end
end

local function UnmuteChat()
    if not muted then return end
    for i = 1, #muted do muted[i]:RegisterEvent("TIME_PLAYED_MSG") end
    muted = nil
end

local function PlayedDone()
    playedToken = nil
    waitBaseline = false
    waitLevels = {}
    playedWaiters = {}
    UnmuteChat()
    if active.TIME_PLAYED_MSG then R:Off("TIME_PLAYED_MSG", active.TIME_PLAYED_MSG) active.TIME_PLAYED_MSG = nil end
end

-- Pure: the two measurements for a level-up, from the stored baseline and the answer.
-- Returns secsAtLevel (nil when it can't be known honestly) and secsTotal.
function Rec.LevelTimes(journey, level, total, onlyOne)
    if type(total) ~= "number" or total < 0 then return nil, nil end
    local atLevel
    if onlyOne and journey.baseLevel == level - 1 and journey.baseTotal and total >= journey.baseTotal then
        atLevel = total - journey.baseTotal
    end
    return atLevel, total
end

local function OnPlayed(total, thisLevel)
    if not playedToken then return end
    local j = Journey()
    local count = #waitLevels
    for _, w in ipairs(waitLevels) do
        local entry = C.Find(w.id)
        if entry then
            local atLevel, whole = Rec.LevelTimes(j, w.level, total, count == 1)
            local lines = {}
            if atLevel then lines[#lines + 1] = ("Level %d to %d: %s"):format(w.level - 1, w.level, C.FormatDuration(atLevel)) end
            if whole then lines[#lines + 1] = "Total journey: " .. C.FormatDuration(whole) end
            if #lines > 0 then
                C.SetDetails(w.id, { note = table.concat(lines, "  ·  "), secsAtLevel = atLevel, secsTotal = whole })
                Changed()
            end
        end
    end
    if count > 0 and type(total) == "number" then
        j.baseLevel, j.baseTotal = waitLevels[count].level, total
    elseif waitBaseline and type(total) == "number" and type(thisLevel) == "number" and total >= thisLevel then
        j.baseLevel, j.baseTotal = UnitLevel("player"), total - thisLevel
    end
    local waiters = playedWaiters
    PlayedDone()
    for i = 1, #waiters do
        local ok, err = pcall(waiters[i], total)
        if not ok then geterrorhandler()(err) end
    end
end

-- callback(total) is called with the total played seconds once the game answers. It is dropped
-- (never called) if no answer comes in time or the API is missing.
local function RequestPlayed(callback)
    if callback then playedWaiters[#playedWaiters + 1] = callback end
    if not RequestTimePlayed or playedToken then return end
    playedToken = {}
    local token = playedToken
    MuteChat()
    active.TIME_PLAYED_MSG = OnPlayed
    R:On("TIME_PLAYED_MSG", OnPlayed)
    C_Timer.After(PLAYED_TIMEOUT, function() if playedToken == token then PlayedDone() end end)
    RequestTimePlayed()
end

-- Takes the baseline for the level the character is on, unless one is already stored for it.
local function EnsureBaseline()
    if not inWorld or not R:Enabled("chronicle") or not R:Enabled("chronicleLevels") then return end
    local level = UnitLevel and UnitLevel("player")
    if type(level) ~= "number" or Journey().baseLevel == level then return end
    waitBaseline = true
    RequestPlayed()
end

-- Brings an open Chronicle header up to date after a level-up's answer.
local function HeaderPlayed(total)
    if R.ChronicleWindow and R.ChronicleWindow.ShowPlayed then R.ChronicleWindow.ShowPlayed(total) end
end

function Rec.RequestPlayed(callback) RequestPlayed(callback) end

local function OnLevelUp(level)
    if not On("chronicleLevels") or type(level) ~= "number" then return end
    local j = Journey()
    if j.lastLevel and level <= j.lastLevel then return end
    local entry = Commit("level", { title = ("Reached level %d"):format(level), level = level, zone = C.CurrentZone() })
    if not entry then return end
    j.lastLevel = level
    waitLevels[#waitLevels + 1] = { id = entry.id, level = level }
    RequestPlayed(HeaderPlayed)
end

---------------------------------------------------------------------------
-- Professions. There is no "profession learned" event, so the profession list is compared with what
-- was seen before whenever SKILL_LINES_CHANGED settles (debounced). Each profession is kept by its
-- skill line ID: [0] = learning written, [rank] = that milestone written. What exists when tracking
-- begins is noted silently, so nothing from before is added.
---------------------------------------------------------------------------
Rec.PROFESSION_STEPS = { 75, 150, 225, 300, 375, 450 }   -- Forever's PROFESSION_RANKS tiers
local PROFESSION_DEBOUNCE = 0.5
local PROFESSION_SETTLE = 5      -- seconds after login before the first look at the professions
local professionPending = false

-- The professions the character has now: { { id, name, rank, icon }, ... }, or nil when the API is missing.
local function ReadProfessions()
    if not GetProfessions or not GetProfessionInfo then return nil end
    local list = {}
    for _, index in pairs({ GetProfessions() }) do
        local name, texture, rank, _, _, _, skillLine = GetProfessionInfo(index)
        name = Plain(name)
        if name and name ~= "" and type(rank) == "number" and type(skillLine) == "number" and skillLine > 0 then
            local icon = (type(texture) == "number" or type(texture) == "string") and texture or nil
            list[#list + 1] = { id = skillLine, name = name, rank = rank, icon = icon }
        end
    end
    return list
end

-- Pure: updates the stored state for what is seen now and returns what is new, as
-- { { learned = true, prof = p }, { step = n, prof = p }, ... }. With silent, only the state changes.
function Rec.ApplyProfessions(state, profs, silent)
    local events = {}
    for _, p in ipairs(profs) do
        local seen = state[p.id]
        if not seen then
            seen = { [0] = true }
            state[p.id] = seen
            for _, step in ipairs(Rec.PROFESSION_STEPS) do
                if p.rank >= step then seen[step] = true end
            end
            if not silent then events[#events + 1] = { learned = true, prof = p } end
        else
            for _, step in ipairs(Rec.PROFESSION_STEPS) do
                if not seen[step] and p.rank >= step then
                    seen[step] = true
                    if not silent then events[#events + 1] = { step = step, prof = p } end
                end
            end
        end
    end
    return events
end

local function CheckProfessions(silent)
    local profs = ReadProfessions()
    if not profs then return end
    local state = Journey().professions
    for _, ev in ipairs(Rec.ApplyProfessions(state, profs, silent)) do
        local p = ev.prof
        Commit("profession", {
            title = ev.learned and ("Learned " .. p.name) or ("%s reached %d"):format(p.name, ev.step),
            icon = p.icon, zone = C.CurrentZone(),
        })
    end
    state.baselined = true
end

local function RunProfessionCheck()
    professionPending = false
    if On("chronicleProfessions") and Journey().professions.baselined then CheckProfessions() end
end

local function OnSkillLines()
    if professionPending or not inWorld or not Journey().professions.baselined then return end
    professionPending = true
    C_Timer.After(PROFESSION_DEBOUNCE, RunProfessionCheck)
end

-- The first look, a moment after login so the game has had time to fill in the profession list.
local function ProfessionSettled(retried)
    if not On("chronicleProfessions") then return end
    local first = not Journey().professions.baselined
    if first and not retried then
        -- An empty list this soon may only mean the game hasn't filled it in; look once more before trusting it.
        local profs = ReadProfessions()
        if profs and #profs == 0 then
            C_Timer.After(PROFESSION_SETTLE, function() ProfessionSettled(true) end)
            return
        end
    end
    CheckProfessions(first)
end

---------------------------------------------------------------------------
-- Gold earned. Counts only increases in the wallet that TwichUI sees, once tracking has begun.
-- Spending never lowers it; what was carried at the start and offline changes are not counted.
---------------------------------------------------------------------------
local function GoldTitle(g)
    local digits = tostring(g):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return "Earned " .. digits .. " gold"
end

-- Pure: adds a wallet change; returns the thresholds (in gold) newly crossed, lowest first.
function Rec.AddEarned(gold, delta)
    local crossed = {}
    if type(delta) ~= "number" or delta <= 0 then return crossed end
    gold.earned = gold.earned + delta
    for _, step in ipairs(Rec.GOLD_STEPS) do
        if not gold.done[step] and gold.earned >= step * COPPER_PER_GOLD then
            gold.done[step] = true
            crossed[#crossed + 1] = step
        end
    end
    return crossed
end

-- Starts counting from what the character holds now. Keeps the earned total and recorded steps.
local function RebaseGold()
    if not GetMoney then return end
    local j = Journey()
    local money = GetMoney()
    if type(money) ~= "number" then return end
    if j.gold then j.gold.last = money else j.gold = { last = money, earned = 0, done = {} } end
end

local function OnMoney()
    if not On("chronicleGold") or not GetMoney then return end
    local money = GetMoney()
    if type(money) ~= "number" then return end
    local g = Journey().gold
    if not g then RebaseGold() return end
    local delta = money - g.last
    g.last = money
    for _, step in ipairs(Rec.AddEarned(g, delta)) do
        Commit("gold", { title = GoldTitle(step), zone = C.CurrentZone() })
    end
end

---------------------------------------------------------------------------
-- Riding ranks. Recorded once per learning spell; known ranks are noted silently at login.
---------------------------------------------------------------------------
local function KnowsSpell(id)
    local known = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
    return known and known(id) or false
end

local function NoteKnownRiding()
    local riding = Journey().riding
    for id in pairs(Rec.RIDING) do
        if not riding[id] and KnowsSpell(id) then riding[id] = true end
    end
end

local function OnLearnedSpell(spellID)
    local fallback = Rec.RIDING[spellID]
    if not fallback or not On("chronicleRiding") then return end
    local riding = Journey().riding
    if riding[spellID] then return end
    riding[spellID] = true
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then name = fallback end
    Commit("riding", { title = "Learned " .. name, zone = C.CurrentZone() })
end

-- On a flight path nothing is recorded; the place the flight ends is looked at once, on landing.
local function OnTaxi()
    return controlLost or (UnitOnTaxi and UnitOnTaxi("player")) or false
end

local BASELINE_RETRIES = 5   -- extra looks (a second apart) for the zone when the game hasn't given it at login

-- Decisions, for /tui diagnostics while it is tracing. Codes only: no place names, entries or notes.
local function Trace(code, detail)
    local D = R.Diag
    if D then D.Trace("chronicle", code, detail) end
end

-- Takes the zone the player is in now as the starting point, without recording it.
-- Returns true once there is one; a missing zone leaves the baseline unset.
local function EstablishZoneBaseline()
    local zone = C.CurrentZone()
    if not zone then return false end
    lastZone, zoneBaselined = zone, true
    Trace("baseline-set", "where you are now is not an arrival")
    return true
end

local function RetryZoneBaseline()
    if zoneBaselined then return end
    if baselineTries >= BASELINE_RETRIES then Trace("baseline-gave-up", "zone never became known") return end
    baselineTries = baselineTries + 1
    Trace("baseline-retry", baselineTries)
    C_Timer.After(1, function()
        if zoneBaselined or not On("chronicleZones") then return end
        if not EstablishZoneBaseline() then RetryZoneBaseline() end
    end)
end

local function StartZoneBaseline()
    zoneBaselined, lastZone, baselineTries = false, nil, 0
    if not EstablishZoneBaseline() then RetryZoneBaseline() end
end

local function CheckZone()
    if not On("chronicleZones") then return end
    -- The first known zone of a session is where the player already was, not somewhere they arrived.
    if not zoneBaselined then
        Trace("no-baseline-yet", "taking the current zone as the starting point")
        EstablishZoneBaseline()
        return
    end
    if OnTaxi() then Trace("skip", "on a flight path") return end
    local zone = C.CurrentZone()
    if not zone then Trace("skip", "zone not available") return end
    if zone == lastZone then Trace("unchanged") return end
    lastZone = zone
    Trace("arrival-recorded", "an automatic entry was written")
    Commit("zone", { title = "Arrived in " .. zone, zone = zone })
end

local function OnControlLost()
    controlLost = true
    Trace("control-lost", "no arrivals until it returns")
end

local function OnControlGained()
    controlLost = false
    Trace("control-gained", "checking where you landed")
    CheckZone()
end

-- Logging in or reloading isn't arriving anywhere. Other loading screens are
-- left to the zone event, so walking into a dungeon is still recorded.
local function OnEnteringWorld(isLogin, isReload)
    inWorld = true
    if isLogin or isReload then
        controlLost = false
        Trace("login", "starting a new location baseline")
        StartZoneBaseline()
        if R:Enabled("chronicle") then
            if R:Enabled("chronicleGold") then RebaseGold() end
            if R:Enabled("chronicleRiding") then NoteKnownRiding() end
            if R:Enabled("chronicleProfessions") then C_Timer.After(PROFESSION_SETTLE, function() ProfessionSettled() end) end
        end
    end
    EnsureBaseline()
end

local function OnEncounterEnd(_, name, _, _, success)
    if not On("chronicleBosses") or success ~= 1 then return end
    name = Plain(name)
    if not name or name == "" then return end
    Commit("boss", { title = "Defeated " .. name, zone = C.CurrentZone() })
end

local function OnDeath()
    if not On("chronicleDeaths") then return end
    local zone = C.CurrentZone()
    Commit("death", { title = zone and ("Fell in " .. zone) or "Fell in battle", zone = zone })
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- For /tui diagnostics: how ready zone-arrival recording is. Place names, entries and notes are not
-- included. Reads only.
function Rec.Snapshot()
    local events = {}
    for event in pairs(active) do events[#events + 1] = event end
    table.sort(events)
    return {
        chronicle = R:Enabled("chronicle"), zones = R:Enabled("chronicleZones"), events = events,
        inWorld = inWorld, baselined = zoneBaselined, baselineTries = baselineTries, baselineRetries = BASELINE_RETRIES,
        zoneReadable = C.CurrentZone() ~= nil, controlLost = controlLost, onFlight = OnTaxi() and true or false,
    }
end

-- Registers exactly the events that are switched on. Safe to call any time.
function Rec.Refresh()
    local master = R:Enabled("chronicle")
    local zones = master and R:Enabled("chronicleZones")
    if zones and not active.ZONE_CHANGED_NEW_AREA then
        if inWorld then StartZoneBaseline() else zoneBaselined, lastZone = false, nil end
    end
    local levels = master and R:Enabled("chronicleLevels")
    local gold = master and R:Enabled("chronicleGold")
    local riding = master and R:Enabled("chronicleRiding")
    local professions = master and R:Enabled("chronicleProfessions")
    -- While off nothing is watched, so the next time it is on it starts from what the character has then.
    if not professions then Journey().professions.baselined = false end
    -- Turned on in this session: start counting gold from now, and don't treat known ranks as new.
    if gold and not active.PLAYER_MONEY and inWorld then RebaseGold() end
    if riding and not active.LEARNED_SPELL_IN_SKILL_LINE and inWorld then NoteKnownRiding() end
    -- Turned on in this session: what the character has now is not new.
    if professions and not active.SKILL_LINES_CHANGED and inWorld then CheckProfessions(true) end
    if not levels then PlayedDone() end
    Want("PLAYER_LEVEL_UP", OnLevelUp, levels)
    Want("ZONE_CHANGED_NEW_AREA", CheckZone, zones)
    Want("PLAYER_CONTROL_LOST", OnControlLost, zones)
    Want("PLAYER_CONTROL_GAINED", OnControlGained, zones)
    Want("PLAYER_MONEY", OnMoney, gold)
    Want("LEARNED_SPELL_IN_SKILL_LINE", OnLearnedSpell, riding)
    Want("SKILL_LINES_CHANGED", OnSkillLines, professions)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, levels or zones or gold or riding or professions)
    if not zones then controlLost = false end
    EnsureBaseline()
    Want("ENCOUNTER_END", OnEncounterEnd, master and R:Enabled("chronicleBosses"))
    Want("PLAYER_DEAD", OnDeath, master and R:Enabled("chronicleDeaths"))

    -- Say in the journal when tracking started (and when it started again).
    local rec = C.Record()
    if master and not rec.tracking then
        local first = true
        for _, e in ipairs(rec.entries) do if e.kind == "start" then first = false break end end
        Commit("start", { title = first and "Chronicle begun" or "Tracking resumed",
            note = "From here on, TwichUI writes the moments you chose to keep. Nothing from before is added." })
        rec.tracking = true
    elseif not master and rec.tracking then
        rec.tracking = false
    end
    Changed()
end

R:OnInit(Rec.Refresh)
