-- TwichUI: Return the Favor, watching for buffs
-- Notices another player buffing you and keeps a short list of who did, for List.lua to draw. Off until turned on.
--
-- What the game gives (WoW: Forever UI source) and so how this works:
--   * UNIT_AURA for "player" hands over what changed (addedAuras, updatedAuraInstanceIDs, removed IDs). An added
--     helpful aura whose sourceUnit is another player (not you, not a pet or NPC) and whose spell is one of
--     Spells.lua's families is a favor; so is one of those auras being cast again on you (its expiration moved on).
--     A full update (logging in, a zone, a reload) only takes stock of what is there: nothing on you then counts as
--     new. Addons can be refused auras (C_Secrets, "SecretWhenAurasRestricted"): a secret field is never compared,
--     and such an aura is simply not noticed.
--   * Nothing is read from the combat log, and nothing is sent: the one thing said to anyone is the optional emote.
--   * The list is the session's only: a player is listed once (their latest buff), for `duration` seconds, at most
--     maxRows of them, newest first. In combat the list on screen can't change (its rows are secure buttons); what
--     arrives waits, and what runs out is dimmed, until combat ends.
--   * Where it pauses (dungeons, raids, battlegrounds, cities and inns, as chosen) nothing is listed and nobody is
--     thanked; the list is hidden. In combat it is hidden too if you choose (the secure state driver does that).
--   * Thanking (off by default): C_ChatInfo.PerformEmote(token, name), the game's own /thank, a few seconds later
--     (your delay plus up to 1.5 s more), only out of combat, only while chat isn't restricted, only if they are
--     still around (a unit of yours names them: target, mouseover, focus, group or nameplate), once per person per
--     five minutes and never two within ten seconds. The game says whether it was restricted; nothing is retried.
--     With "Only after I buff them back" (thankAfterReturn), nothing is scheduled when their buff lands: the delay
--     starts when a click on their row is seen to give your buff back (below), and a player you never buff back is
--     never thanked.
--   * A click that casts the buff back is seen by UNIT_SPELLCAST_SUCCEEDED (your own cast of that family within
--     three seconds of the click): their row then goes. A cast that fails leaves it.

local R = TwichUI
local BB, S = R.BuffBack, R.BuffBackSpells
local Perf = R.Perf
local W = {}
R.BuffBackWatch = W

W.THANK_AGAIN = 300      -- seconds before the same player is thanked again
W.THANK_GAP = 10         -- seconds between any two thanks
W.THANK_SPREAD = 1.5     -- up to this much is added to the delay, so it isn't always the same
W.CAST_WINDOW = 3        -- seconds a click waits to see its cast
W.MAX_KNOWN = 64         -- aura instances remembered (yours are far fewer)
W.MAX_THANKED = 200
W.MAX_ENTRIES = 20       -- kept at most, even in combat (the list shows at most maxRows of them)

local entries = {}       -- newest first: { name, short, class, spellId, spellName, icon, at, expires, inGroup, inParty, buffs }
local known = {}         -- auraInstanceID -> expiration time, for the favors on you now
local knownCount = 0
local thankedAt, thankedCount = {}, 0
local lastThank
local pendingThanks = 0
local epoch = 0          -- bumped when turned off: a timer from before does nothing
local expiryAt           -- when the next prune is scheduled for
local frame, unitFrame
local active = false
local stats = { noticed = 0, thanked = 0, thankSkipped = 0, returned = 0, events = 0 }

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
W.Plain = Plain

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Now() return GetTime() end
local function List() return R.BuffBackList end
local function Changed(what)
    local L = List()
    if L and L.Changed then L.Changed(what) end
end

function W.Enabled() return R:Enabled("buffBack") end

---------------------------------------------------------------------------
-- Where it pauses
---------------------------------------------------------------------------
-- The reason the list is paused here, or nil: "quiet" (the Quiet screen switch, QuietScreen.lua), "dungeon", "raid",
-- "pvp", "resting".
function W.Paused()
    if R.QuietScreen and R.QuietScreen.On() then return "quiet" end
    local inside, kind = false, nil
    if IsInInstance then inside, kind = IsInInstance() end
    inside, kind = Plain(inside), Plain(kind)
    if inside then
        if kind == "party" and BB.Get("hideDungeon") then return "dungeon" end
        if kind == "raid" and BB.Get("hideRaid") then return "raid" end
        if (kind == "pvp" or kind == "arena") and BB.Get("hidePvP") then return "pvp" end
    end
    if BB.Get("hideResting") and IsResting and Plain(IsResting()) then return "resting" end
    return nil
end

---------------------------------------------------------------------------
-- Finding a player among your units (to thank them, to see what they wear). Bounded: about ninety checks.
---------------------------------------------------------------------------
-- On WoW: Forever UnitName's second return is a surname, not a realm (there are no realms), and the game joins the
-- two with CHARACTERNAME_SURNAME_SEPARATOR, a space: "Name Surname" is what /target and the roster know.
local function SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and Plain(consts.CHARACTERNAME_SURNAME_SEPARATOR)
    if type(sep) == "string" and sep ~= "" then return sep end
    return " "
end

local function FullName(unit)
    local name, surname = UnitName(unit)
    name, surname = Plain(name), Plain(surname)
    if type(name) ~= "string" or name == "" then return nil end
    if type(surname) == "string" and surname ~= "" then return name .. SurnameSeparator() .. surname, name end
    return name, name
end
W.FullName = FullName

local function Matches(unit, full)
    if not Plain(UnitExists(unit)) then return false end
    return FullName(unit) == full
end

function W.FindUnit(full)
    if type(full) ~= "string" then return nil end
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if Matches(u, full) then return u end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do if Matches("raid" .. i, full) then return "raid" .. i end end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do if Matches("party" .. i, full) then return "party" .. i end end
    end
    for i = 1, 40 do if Matches("nameplate" .. i, full) then return "nameplate" .. i end end
    return nil
end

-- The party or raid token of a group member (stable until the roster changes), or nil. A macro conditional can't
-- hold a name with a space in it, and a token needs no name at all.
function W.GroupUnit(full)
    if type(full) ~= "string" then return nil end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do if Matches("raid" .. i, full) then return "raid" .. i end end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do if Matches("party" .. i, full) then return "party" .. i end end
    end
    return nil
end

-- What families a unit wears now, or nil when its auras can't be read.
function W.Wearing(unit)
    if not (unit and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() == true then return nil end
    local auras = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil end
        if aura == nil then break end
        if issecretvalue and issecretvalue(aura) then return nil end
        local id, name = Plain(aura.spellId), Plain(aura.name)
        if id == nil and name == nil then return nil end
        auras[#auras + 1] = { id, name }
    end
    return S.Wearing(auras)
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
function W.Entries() return entries end

local function Prune()
    local now, changed = Now(), false
    if InCombat() then
        -- rows can't go in combat: they are dimmed (List.lua) and go when it ends
        for _, e in ipairs(entries) do
            if (e.expires <= now or e.dismissed) and not e.faded then e.faded = true; changed = true end
        end
        if changed then Changed("fade") end
        return
    end
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e.expires <= now or e.dismissed or e.returned then table.remove(entries, i); changed = true end
    end
    local keep = BB.Get("maxRows")
    while #entries > keep do table.remove(entries); changed = true end
    if changed then Changed("entries") end
end

local function ScheduleExpiry()
    local soonest
    for _, e in ipairs(entries) do
        if not e.faded and (not soonest or e.expires < soonest) then soonest = e.expires end
    end
    if not soonest or (expiryAt and expiryAt <= soonest) then return end
    expiryAt = soonest
    local mine = epoch
    C_Timer.After(math.max(0.05, soonest - Now() + 0.05), function()
        if mine ~= epoch then return end
        expiryAt = nil
        Prune()
        ScheduleExpiry()
    end)
end

-- Adds (or moves to the top) one player who buffed you. info: { name, short, class, spellId, spellName, icon,
-- inGroup, inParty }. Returns the entry.
function W.Add(info)
    local now = Now()
    local e
    for i, x in ipairs(entries) do
        if x.name == info.name then e = table.remove(entries, i) break end
    end
    e = e or { buffs = {} }
    e.name, e.short, e.class = info.name, info.short or info.name, info.class
    e.spellId, e.spellName, e.icon = info.spellId, info.spellName, info.icon
    e.inGroup, e.inParty = info.inGroup and true or false, info.inParty and true or false
    e.at, e.expires = now, now + BB.Get("duration")
    e.dismissed, e.returned, e.faded, e.clickedAt, e.clickedFamily = nil, nil, nil, nil, nil
    -- what they have given you lately, newest first, for the tooltip (at most four)
    if info.spellName then
        for i = #e.buffs, 1, -1 do if e.buffs[i] == info.spellName then table.remove(e.buffs, i) end end
        table.insert(e.buffs, 1, info.spellName)
        while #e.buffs > 4 do table.remove(e.buffs) end
    end
    table.insert(entries, 1, e)
    -- out of combat the list holds maxRows; in combat the rows on screen can't change, so a few more wait (bounded)
    local keep = InCombat() and W.MAX_ENTRIES or BB.Get("maxRows")
    while #entries > keep do table.remove(entries) end
    ScheduleExpiry()
    Changed("entries")
    return e
end

-- Right-click on a row: it goes (dimmed in combat, gone when it ends).
function W.Dismiss(entry)
    if not entry then return end
    entry.dismissed = true
    Prune()
end

-- A left click on a row armed with fam: wait a moment to see the cast.
function W.Clicked(entry, fam)
    if not (entry and fam) then return end
    entry.clickedAt, entry.clickedFamily = Now(), fam
end

function W.Clear()
    for i = #entries, 1, -1 do entries[i] = nil end
    Changed("entries")
end

---------------------------------------------------------------------------
-- Thanking them
---------------------------------------------------------------------------
local function Skip(code)
    stats.thankSkipped = stats.thankSkipped + 1
    R.Life.Note("buffback-thank-" .. code)
end

local function Remember(name, now)
    if not thankedAt[name] then
        thankedCount = thankedCount + 1
        if thankedCount > W.MAX_THANKED then
            for who, at in pairs(thankedAt) do
                if now - at >= W.THANK_AGAIN then thankedAt[who] = nil; thankedCount = thankedCount - 1 end
            end
        end
    end
    thankedAt[name] = now
end

-- Thanks one player now, if everything allows it. Returns true when the emote was performed.
function W.ThankNow(name)
    local now = Now()
    if not (W.Enabled() and BB.Get("thank")) then return false end
    if InCombat() then Skip("combat") return false end
    if W.Paused() then Skip("paused") return false end
    if lastThank and now - lastThank < W.THANK_GAP then Skip("gap") return false end
    local chat = C_ChatInfo
    if chat and chat.InChatMessagingLockdown then
        local ok, locked = pcall(chat.InChatMessagingLockdown)
        if not ok or Plain(locked) ~= false then Skip("lockdown") return false end
    end
    local unit = W.FindUnit(name)
    if not unit then Skip("away") return false end
    local emote = BB.Get("thankEmote")
    local perform = chat and chat.PerformEmote or DoEmote
    if type(perform) ~= "function" then Skip("api") return false end
    local ok, restricted = pcall(perform, emote, name)
    lastThank = now
    if not ok then Skip("error") return false end
    if Plain(restricted) == true then Skip("restricted") return false end
    stats.thanked = stats.thanked + 1
    return true
end

local function ScheduleThank(name)
    if not BB.Get("thank") then return end
    local now = Now()
    local last = thankedAt[name]
    if last and now - last < W.THANK_AGAIN then return end
    if pendingThanks >= 3 then Skip("queue") return end
    Remember(name, now)
    pendingThanks = pendingThanks + 1
    local mine = epoch
    local delay = BB.Get("thankDelay") + math.random() * W.THANK_SPREAD
    C_Timer.After(delay, function()
        if mine ~= epoch then return end
        pendingThanks = pendingThanks - 1
        W.ThankNow(name)
    end)
end

---------------------------------------------------------------------------
-- Noticing a buff
---------------------------------------------------------------------------
local function Remembered(id, expires)
    if known[id] == nil then
        if knownCount >= W.MAX_KNOWN then return end
        knownCount = knownCount + 1
    end
    known[id] = expires or 0
end

local function Forget(id)
    if known[id] ~= nil then known[id] = nil; knownCount = knownCount - 1 end
end

local function Note(unit, aura, fam)
    if Plain(UnitIsUnit(unit, "player")) then return end
    if not Plain(UnitIsPlayer(unit)) then return end
    local full, short = FullName(unit)
    if not full then return end
    local _, class = UnitClass(unit)
    class = Plain(class)
    local spellId, spellName, icon = Plain(aura.spellId), Plain(aura.name), Plain(aura.icon)
    if type(spellName) ~= "string" then spellName = S.SpellName(spellId) end
    local inParty = (UnitInParty and Plain(UnitInParty(unit))) and true or false
    local inGroup = inParty or ((UnitInRaid and Plain(UnitInRaid(unit))) and true or false)
    stats.noticed = stats.noticed + 1
    W.Add({ name = full, short = short, class = class, spellId = spellId, spellName = spellName, icon = icon,
        inGroup = inGroup, inParty = inParty, family = fam })
    if not BB.Get("thankAfterReturn") then ScheduleThank(full) end
end

-- One aura of yours, added (fresh) or changed. Notes it when it is a favor that just landed.
local function Consider(aura, added, listening)
    if type(aura) ~= "table" or (issecretvalue and issecretvalue(aura)) then return end
    local id = Plain(aura.auraInstanceID)
    if id == nil then return end
    if Plain(aura.isHelpful) == false then return end
    local src = Plain(aura.sourceUnit)
    if type(src) ~= "string" or src == "player" then return end
    local fam = S.Family(Plain(aura.spellId), Plain(aura.name))
    if not fam and not BB.Get("anyBuff") then return end
    local expires = Plain(aura.expirationTime)
    local was = known[id]
    Remembered(id, expires)
    local fresh = added or (type(was) == "number" and was > 0 and type(expires) == "number" and expires > was + 1)
    if fresh and listening then Note(src, aura, fam) end
end

-- Takes stock of your auras without noting any (a full update).
local function Rebaseline()
    for id in pairs(known) do known[id] = nil end
    knownCount = 0
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or aura == nil then break end
        Consider(aura, false, false)
    end
end
W.Rebaseline = Rebaseline

function W.OnAura(info)
    stats.events = stats.events + 1
    -- no details, a full update, or one the game won't say: take stock again, note nothing
    if type(info) ~= "table" or (issecretvalue and issecretvalue(info.isFullUpdate)) or info.isFullUpdate == true then
        Rebaseline()
        return
    end
    local listening = not W.Paused()
    for _, aura in ipairs(info.addedAuras or {}) do Consider(aura, true, listening) end
    if info.updatedAuraInstanceIDs and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for _, id in ipairs(info.updatedAuraInstanceIDs) do
            id = Plain(id)
            if id and known[id] ~= nil then
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
                if ok then Consider(aura, false, listening) end
            end
        end
    end
    for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
        id = Plain(id)
        if id then Forget(id) end
    end
end

-- Your own cast: a row clicked a moment ago whose buff this is has been given back.
function W.OnCast(spellId)
    spellId = Plain(spellId)
    if not spellId then return end
    local now, changed = Now(), false
    for _, e in ipairs(entries) do
        if e.clickedAt and now - e.clickedAt <= W.CAST_WINDOW and S.IsOf(e.clickedFamily, spellId) then
            e.returned, e.clickedAt = true, nil
            stats.returned = stats.returned + 1
            changed = true
            if BB.Get("thankAfterReturn") then ScheduleThank(e.name) end
        end
    end
    if changed then Prune() end
end

---------------------------------------------------------------------------
-- Turning on and off
---------------------------------------------------------------------------
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED" }

local function OnEvent(event, ...)
    if event == "UNIT_AURA" then
        W.OnAura(select(2, ...))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        W.OnCast(select(3, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        Prune()
        ScheduleExpiry()
        Changed("combat")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Changed("combatStart")   -- the game may not say it is in combat yet: this is the moment combat starts
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_UPDATE_RESTING" then
        if W.Paused() and #entries > 0 and not InCombat() then W.Clear() end
        Changed("where")
    else
        Changed("arm")   -- your target, your group or your spells changed: what a click does may have
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", Perf.Wrap("buffback.event", function(_, event, ...) OnEvent(event, ...) end))
    unitFrame = CreateFrame("Frame")
    unitFrame:SetScript("OnEvent", Perf.Wrap("buffback.aura", function(_, event, ...) OnEvent(event, ...) end))
end

function W.Refresh()
    local want = W.Enabled()
    if want == active then
        Changed("settings")
        return
    end
    if want then
        Build()
        for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
        unitFrame:RegisterUnitEvent("UNIT_AURA", "player")
        unitFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        active = true
        Rebaseline()
    else
        active = false
        epoch = epoch + 1
        expiryAt, pendingThanks = nil, 0
        if frame then frame:UnregisterAllEvents() end
        if unitFrame then unitFrame:UnregisterAllEvents() end
        for id in pairs(known) do known[id] = nil end
        knownCount = 0
        for i = #entries, 1, -1 do entries[i] = nil end
    end
    Changed("switch")
end

BB.Subscribe(function(what)
    if what == "settings" or what == "profile" then
        if active and not InCombat() then Prune() end
        -- a pause that now applies empties the list, as arriving there would
        if active and W.Paused() and #entries > 0 and not InCombat() then W.Clear() end
    end
end)

-- The Quiet screen went on or off: like arriving somewhere it pauses in, the list empties (out of combat; in combat the
-- rows can't change, so the list follows when combat ends) and the rows are drawn again.
if R.QuietScreen then
    R.QuietScreen.OnChange(function(on)
        if not active then return end
        if on and #entries > 0 and not InCombat() then W.Clear() end
        Changed("where")
    end)
end

R:On("PLAYER_LOGIN", function() if W.Enabled() then W.Refresh() end end)

---------------------------------------------------------------------------
-- For the options page and /tui perf. Read only; nothing about who is listed.
---------------------------------------------------------------------------
function W.Snapshot()
    local events = 0
    if frame then for _, e in ipairs(EVENTS) do if frame:IsEventRegistered(e) then events = events + 1 end end end
    if active then events = events + 2 end
    return {
        active = active, entries = #entries, known = knownCount, thanked = stats.thanked, thankSkipped = stats.thankSkipped,
        noticed = stats.noticed, returned = stats.returned, auraEvents = stats.events, events = events,
        paused = W.Paused(), pendingThanks = pendingThanks,
    }
end
