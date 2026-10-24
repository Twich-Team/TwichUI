-- TwichUI: Vendors and trainers, noticing them
-- When you deal with an NPC (its merchant, trainer, bank, inn, auction, stable, flight, spirit healer or guild charter
-- window opens), what it offered and where you stood are noted in your list (npcs/Store.lua). Only while the switch
-- modules.npcMap is on; it listens to nothing otherwise. It reads, and never buys, trains, clicks or opens anything.
--   Who:    the creature id from UnitGUID("npc") ("Creature-0-...-<id>-<spawn>"; anything else is not an NPC) and its
--           name, UnitName("npc").
--   Where:  your own place on the map the game says you are on (C_Map.GetBestMapForUnit, GetPlayerMapPosition): the
--           client tells addons where the player is, not where the NPC is, so the mark is a few yards out. Nothing is
--           noted inside an instance or anywhere the game gives no position.
--   What:   npcs/Kinds.lua decides from the facts read here:
--             PLAYER_INTERACTION_MANAGER_FRAME_SHOW (type)  a service (bank, inn, auction house, stable, flight master,
--                                                           spirit healer, guild registrar)
--             MERCHANT_SHOW, MERCHANT_UPDATE                the items for sale (their item class) and CanMerchantRepair;
--                                                           read when the window opens and again a moment later and on
--                                                           an update (the list can arrive in parts), at most once a second
--             TRAINER_SHOW                                  C_Trainer.GetTrainerType, and the profession's name from the
--                                                           first service's skill line (GetTrainerServiceSkillLine)
-- The probe (/tui npcs probe, for this session only): prints what the game reported at each such window to your own chat
-- frame, so the facts this relies on can be checked in the game. It changes nothing and nothing of it is saved.

local R = TwichUI
local NK, NS = R.NpcKinds, R.NpcStore
local NC = {}
R.NpcCollect = NC

local REREAD_SECONDS = 0.6
local MIN_READ_GAP = 1
local stats = { noticed = 0, new = 0, updated = 0, confirmed = 0, skipped = {}, reads = 0 }
local probe = false
local listening = false
local visit             -- the merchant window open now: { gen, guid, lastRead }
local generation = 0

local function Enabled() return R:Enabled("npcMap") end
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Skip(code)
    stats.skipped[code] = (stats.skipped[code] or 0) + 1
    return nil, code
end

local function Say(fmt, ...)
    if probe then R.Print("|cff8a857c[probe]|r " .. fmt, ...) end
end

-- "Creature-0-3137-0-47-1213-0000123456" -> 1213; nil for anything else (a player, a pet, an object).
function NC.CreatureId(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    if kind ~= "Creature" then return nil end
    id = tonumber(id)
    if NS.ValidId(id) then return id end
    return nil
end

-- Where you are: map, x, y (0..1), or nil and a reason code.
local function Here()
    if IsInInstance then
        local ok, inside = pcall(IsInInstance)
        if ok and inside then return Skip("instance") end
    end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return Skip("no-map-api") end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    map = ok and Plain(map) or nil
    if not map then return Skip("no-map") end
    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok2 and pos and pos.GetXY) then return Skip("no-position") end
    local x, y = pos:GetXY()
    x, y = Plain(x), Plain(y)
    if type(x) ~= "number" or type(y) ~= "number" then return Skip("no-position") end
    if not NS.ValidMap(map) then return Skip("map-too-coarse") end
    return map, x, y
end

-- Who the NPC is: id, name, guid, or nil and a reason code.
local function Who()
    local guid = UnitGUID and Plain(UnitGUID("npc"))
    local id = NC.CreatureId(guid)
    if not id then
        Say("the window's unit isn't an NPC the game names (%s)", type(guid) == "string" and (guid:match("^(%a+)") or "?") or "none")
        return Skip("not-a-creature")
    end
    local name = UnitName and Plain(UnitName("npc"))
    if type(name) ~= "string" or name == "" then return Skip("no-name") end
    return id, name, guid
end

-- Notes one NPC with what it was seen to offer. facts: as NK.Classify takes them.
local function Note(facts, what)
    local id, name = Who()
    if not id then return end
    local map, x, y = Here()
    if probe then
        local ok, px, py, _, pmap = pcall(UnitPosition, "npc")
        Say("%s: %s (creature %d); map %s at %s; the NPC's own position: %s", what, name, id, tostring(map or "none"),
            x and ("%.1f, %.1f"):format(x * 100, y * 100) or "unknown",
            (ok and type(px) == "number") and ("given (%.0f, %.0f, map %s)"):format(px, py, tostring(pmap)) or "not given")
    end
    if not map then return end
    facts.playerClass = UnitClassBase and Plain(UnitClassBase("player")) or nil
    local kind = NK.Classify(facts)
    if not kind then
        Say("nothing to note: it offered none of the kinds TwichUI lists")
        return Skip("no-kind")
    end
    if probe then
        Say("%s: %s%s", Enabled() and "noted as" or "would be noted as", NK.Describe(kind.tags), kind.cls and (" (" .. kind.cls .. ")") or "")
    end
    if not Enabled() then return end   -- the probe alone notes nothing
    -- a merchant's list read again during the same visit adds what it offered; it is not another visit
    local again = facts.merchant and visit ~= nil and visit.noted == id
    local entry, status = NS.Observe({ id = id, name = name, map = map, x = x, y = y, tags = kind.tags, cls = kind.cls,
        prof = kind.prof, again = again })
    if entry and facts.merchant and visit then visit.noted = id end
    if not entry then return Skip(status or "refused") end
    stats.noticed = stats.noticed + 1
    stats[status] = (stats[status] or 0) + 1
    return entry, status
end
NC.Note = Note

---------------------------------------------------------------------------
-- The windows
---------------------------------------------------------------------------
local function OnInteraction(kind)
    kind = Plain(kind)
    if probe then Say("interaction window: type %s", tostring(kind)) end
    if kind and NK.SERVICE[kind] then
        Note({ service = kind }, NK.BY_ID[NK.SERVICE[kind]].noun)
    end
end

local function ReadMerchant()
    if not visit then return end
    visit.lastRead = GetTime()
    stats.reads = stats.reads + 1
    local n = GetMerchantNumItems and Plain(GetMerchantNumItems())
    if type(n) ~= "number" then return Skip("merchant-unreadable") end
    local items, counts = {}, {}
    for i = 1, math.min(n, 200) do
        local id = GetMerchantItemID and Plain(GetMerchantItemID(i))
        if id and C_Item and C_Item.GetItemInfoInstant then
            local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, id)
            classID, subClassID = ok and Plain(classID) or nil, ok and Plain(subClassID) or nil
            if classID then
                items[#items + 1] = { classID, subClassID }
                local key = classID .. "." .. tostring(subClassID)
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end
    local repair = false
    if CanMerchantRepair then
        local ok, can = pcall(CanMerchantRepair)
        repair = ok and Plain(can) == true
    end
    -- a list not in yet says nothing (it would make any merchant "another merchant")
    if #items == 0 and not repair then
        Say("merchant: no items readable yet (%d listings)", n)
        return Skip("merchant-empty")
    end
    if probe then
        local list = {}
        for key, c in pairs(counts) do list[#list + 1] = key .. " x" .. c end
        table.sort(list)
        Say("merchant: %d listings, item class.subclass: %s; repairs: %s", n, #list > 0 and table.concat(list, ", ") or "none",
            repair and "yes" or "no")
    end
    Note({ merchant = true, items = items, repair = repair }, "merchant")
end

local function OnMerchantShow()
    generation = generation + 1
    visit = { gen = generation, lastRead = 0 }
    ReadMerchant()
    local mine = generation
    C_Timer.After(REREAD_SECONDS, function()
        if visit and visit.gen == mine then ReadMerchant() end
    end)
end

local function OnMerchantUpdate()
    if not visit or GetTime() - visit.lastRead < MIN_READ_GAP then return end
    ReadMerchant()
end

local function OnMerchantClosed() visit = nil end

local function OnTrainerShow()
    local trainerType
    if C_Trainer and C_Trainer.GetTrainerType then
        local ok, t = pcall(C_Trainer.GetTrainerType)
        trainerType = ok and Plain(t) or nil
    end
    local profession
    if trainerType == NK.TRAINER.tradeskills and GetTrainerServiceSkillLine then
        local ok, line = pcall(GetTrainerServiceSkillLine, 1)
        line = ok and Plain(line) or nil
        if type(line) == "string" then profession = line end
    end
    if probe then Say("trainer: type %s%s", tostring(trainerType), profession and (", skill line " .. profession) or "") end
    if trainerType == nil then return Skip("trainer-unreadable") end
    Note({ trainerType = trainerType, profession = profession }, "trainer")
end

local EVENTS = {
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = OnInteraction,
    MERCHANT_SHOW = OnMerchantShow, MERCHANT_UPDATE = OnMerchantUpdate, MERCHANT_CLOSED = OnMerchantClosed,
    TRAINER_SHOW = OnTrainerShow,
}

-- On with the switch (or the probe), off without: events are listened to only then.
function NC.Refresh()
    local want = Enabled() or probe
    if want == listening then return end
    listening = want
    for event, fn in pairs(EVENTS) do
        if want then R:On(event, fn) else R:Off(event, fn) end
    end
    if not want then visit = nil end
end

-- The probe, for this session. Returns whether it is on now.
function NC.Probe(on)
    if on == nil then on = not probe end
    probe = on and true or false
    NC.Refresh()
    if probe then
        R.Print("probe on: each merchant, trainer or service window you open prints what the game said about it, here only. %s/tui npcs probe|r again to stop.%s",
            R.GOLD, Enabled() and "" or " (Vendors and trainers is off, so nothing is noted, only printed.)")
    else
        R.Print("probe off.")
    end
    return probe
end
function NC.Probing() return probe end

R:On("PLAYER_LOGIN", NC.Refresh)

-- Read only, for /tui diagnostics: counts, never names or places.
function NC.Snapshot()
    local skipped = {}
    for k, v in pairs(stats.skipped) do skipped[k] = v end
    return { listening = listening, probe = probe, noticed = stats.noticed, new = stats.new, updated = stats.updated,
        confirmed = stats.confirmed, reads = stats.reads, skipped = skipped }
end
