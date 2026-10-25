-- TwichUI: Reminders, reading the game
-- The live observations the enabled reminders' conditions read, kept as plain facts (the same shape a simulation
-- builds): obs.slots[n] = { empty = true } or { id, classID, subClassID, equipLoc } (no details yet: classID nil),
-- obs.combat = true | false, obs.life = "alive" | "dead" | "ghost", obs.mounted = true | false. A key nobody wants
-- is not read and not listened for. Nothing here decides anything, and nothing here ever changes the game: no item is
-- equipped, used or moved, nothing is cast, nothing is sent.
--
-- Sources (ST.Source(kind, def) adds one): an observation key is "<kind>" or "<kind>:<arg>" ("slot:17", "combat").
--   def.events = { EVENT = function(...) -> true (every key of this kind) | an arg (that key) | nil (none) }
--   def.Read(arg, obs) -> true when the value in obs changed (writes it into obs: the live table, or a peek's own)
-- Events only mark keys as due; one short timer later (COALESCE) each due key is read once, and the controller is
-- told which ones actually changed (so a burst of equipment events, or swapping gear, is one decision, after it has
-- settled). No OnUpdate, no polling.
--
-- Item details: C_Item.GetItemInfoInstant answers from the client's own data without waiting. When it has no answer
-- for an equipped item (a server's own item), the slot reads as "no details yet" (conditions about its kind are then
-- unknown, never true), the game is asked to load it at most MAX_ASK times per item per session, and
-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT are listened for only while such an item is equipped in a wanted slot.
-- If the game answers that there is no such item, it stays unknown and says so.
--
-- Game APIs (each documented in the Forever UI source; docs/reminders.md has the list): GetInventoryItemID,
-- C_Item.GetItemInfoInstant, C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID, UnitAffectingCombat,
-- UnitIsDeadOrGhost, UnitIsGhost, IsMounted, UnitClassBase; events PLAYER_ENTERING_WORLD,
-- PLAYER_EQUIPMENT_CHANGED (slot, hasCurrent), PLAYER_REGEN_DISABLED / _ENABLED, PLAYER_DEAD, PLAYER_ALIVE,
-- PLAYER_UNGHOST, PLAYER_MOUNT_DISPLAY_CHANGED, GET_ITEM_INFO_RECEIVED and ITEM_DATA_LOAD_RESULT (itemID, success).

local R = TwichUI
local C = R.ReminderConditions
local ST = {}
R.ReminderState = ST

local COALESCE = 0.1
local MAX_ASK = 2

local obs = { slots = {} }   -- the live observations
local want = {}              -- [key] = true: what the enabled reminders read
local evf                    -- the event frame, made when first needed
local registered = {}        -- [event] = true
local dirty = {}             -- [key] = true: due to be read
local changed = {}           -- reused for each telling; the listener must not keep it
local queued = false
local token = 0              -- bumped by Stop: a timer from before does nothing
local started = false        -- the controller wants the world event (Reminders on)
local listener               -- fn(changed or nil): nil means "everything" (the world was entered)
local combat                 -- what the combat events last said (nil until one is seen in this world)
local asked, missing = {}, {}   -- [itemID] = times asked to load; [itemID] = true once the game said there is none
local stats = { reads = 0, tellings = 0, events = 0, asked = 0 }

local EMPTY = { empty = true }   -- an empty slot (shared, never written)

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Number(v)
    v = Plain(v)
    if type(v) == "number" and v == v then return v end
    return nil
end

-- The world is there once the game said so; our own hearing of the event counts too, so the order in which two frames
-- hear PLAYER_ENTERING_WORLD does not matter.
local worldSeen = false
function ST.InWorld() return worldSeen or (R.Life ~= nil and R.Life.InWorld()) end

-- Names come from the game when it has them ready; this never asks for one to be loaded.
C.ItemName = function(id)
    if not (C_Item and C_Item.GetItemNameByID) then return nil end
    local name = Plain(C_Item.GetItemNameByID(id))
    return type(name) == "string" and name or nil
end

---------------------------------------------------------------------------
-- Sources
---------------------------------------------------------------------------
local SOURCES = {}

function ST.Source(kind, def)
    assert(type(kind) == "string" and type(def) == "table" and type(def.Read) == "function", "a source needs Read")
    SOURCES[kind] = def
end

local SyncEvents

local function Ask(id)
    if missing[id] or (asked[id] or 0) >= MAX_ASK then return end
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    asked[id] = (asked[id] or 0) + 1
    stats.asked = stats.asked + 1
    C_Item.RequestLoadItemDataByID(id)
end

local function ReadSlot(n, into)
    stats.reads = stats.reads + 1
    into.slots = into.slots or {}
    local id = GetInventoryItemID and Number(GetInventoryItemID("player", n)) or nil
    local old = into.slots[n]
    if not id then
        if old == EMPTY then return false end
        into.slots[n] = EMPTY
        return true
    end
    if old and old ~= EMPTY and old.id == id and old.classID ~= nil then return false end
    local classID, subClassID, equipLoc
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, loc, _, class, sub = C_Item.GetItemInfoInstant(id)
        classID, subClassID, equipLoc = Number(class), Number(sub), Plain(loc)
    end
    if classID == nil then
        if into == obs then Ask(id) end
        if old and old ~= EMPTY and old.id == id then return false end   -- still no details: nothing new
    end
    into.slots[n] = { id = id, classID = classID, subClassID = subClassID, equipLoc = type(equipLoc) == "string" and equipLoc or nil }
    return true
end

local function Set(into, key, value)
    if into[key] == value then return false end
    into[key] = value
    return true
end

ST.Source("slot", {
    events = {
        PLAYER_EQUIPMENT_CHANGED = function(slot) return Number(slot) end,
        -- the game's answer about an item: the slots holding it are read again
        GET_ITEM_INFO_RECEIVED = "item", ITEM_DATA_LOAD_RESULT = "item",
    },
    Read = function(n, into) return ReadSlot(tonumber(n), into) end,
})

ST.Source("combat", {
    events = {
        PLAYER_REGEN_DISABLED = function() combat = true return true end,
        PLAYER_REGEN_ENABLED = function() combat = false return true end,
    },
    Read = function(_, into)
        local v = combat
        if v == nil and UnitAffectingCombat then v = Plain(UnitAffectingCombat("player")) == true end
        return Set(into, "combat", v)
    end,
})

ST.Source("life", {
    events = { PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true },
    Read = function(_, into)
        local v
        if UnitIsDeadOrGhost then
            if UnitIsGhost and Plain(UnitIsGhost("player")) == true then v = "ghost"
            elseif Plain(UnitIsDeadOrGhost("player")) == true then v = "dead"
            else v = "alive" end
        end
        return Set(into, "life", v)
    end,
})

ST.Source("mounted", {
    events = { PLAYER_MOUNT_DISPLAY_CHANGED = true },
    Read = function(_, into)
        local v
        if IsMounted then v = Plain(IsMounted()) == true end
        return Set(into, "mounted", v)
    end,
})

local function Split(key)
    local kind, arg = key:match("^([%w_]+):(.+)$")
    if kind then return kind, arg end
    return key, nil
end

local function Read(key, into)
    local kind, arg = Split(key)
    local src = SOURCES[kind]
    if not src then return false end
    local ok, result = pcall(src.Read, arg, into)
    if not ok then
        R.Fault("reminders state", result)
        return false
    end
    return result and true or false
end

---------------------------------------------------------------------------
-- Telling the controller
---------------------------------------------------------------------------
local function Flush()
    queued = false
    for k in pairs(changed) do changed[k] = nil end
    local any = false
    for key in pairs(dirty) do
        dirty[key] = nil
        if want[key] and Read(key, obs) then
            changed[key] = true
            any = true
        end
    end
    SyncEvents()   -- an item's details may have arrived (or another may be missing now)
    if any and listener then
        stats.tellings = stats.tellings + 1
        local ok, err = pcall(listener, changed)
        if not ok then R.Fault("reminders", err) end
    end
end

local function Mark(key)
    if not want[key] then return end
    dirty[key] = true
    if queued then return end
    queued = true
    local mine = token
    C_Timer.After(COALESCE, function()
        if mine ~= token then return end
        Flush()
    end)
end

local function MarkKind(kind)
    for key in pairs(want) do
        if Split(key) == kind then Mark(key) end
    end
end

-- The slots holding an item the game just answered about.
local function MarkItem(id, success)
    id = Number(id)
    if not id then return end
    if success == false then missing[id] = true end
    for key in pairs(want) do
        local kind, arg = Split(key)
        local f = kind == "slot" and obs.slots[tonumber(arg)]
        if f and f ~= EMPTY and f.id == id then Mark(key) end
    end
end

local function OnEvent(_, event, ...)
    stats.events = stats.events + 1
    if event == "PLAYER_ENTERING_WORLD" then
        worldSeen = true
        combat = nil   -- a loading screen: ask the game again
        if listener then
            local ok, err = pcall(listener, nil)
            if not ok then R.Fault("reminders", err) end
        end
        return
    end
    for kind, src in pairs(SOURCES) do
        local handler = src.events and src.events[event]
        if handler == "item" then
            MarkItem(...)
        elseif handler == true then
            MarkKind(kind)
        elseif type(handler) == "function" then
            local which = handler(...)
            if which == true then MarkKind(kind)
            elseif which ~= nil then Mark(kind .. ":" .. tostring(which)) end
        end
    end
end

-- Whether a wanted slot holds an item the game hasn't given details for (and might still).
local function Unresolved()
    for key in pairs(want) do
        local kind, arg = Split(key)
        local f = kind == "slot" and obs.slots[tonumber(arg)]
        if f and f ~= EMPTY and f.classID == nil and not missing[f.id] then return true end
    end
    return false
end

-- Registers exactly the events wanted now and drops the rest.
function SyncEvents()
    local events = {}
    if started then
        events.PLAYER_ENTERING_WORLD = true
        local kinds = {}
        for key in pairs(want) do kinds[(Split(key))] = true end
        local items = Unresolved()
        for kind in pairs(kinds) do
            local src = SOURCES[kind]
            for event, handler in pairs(src and src.events or {}) do
                if handler ~= "item" or items then events[event] = true end
            end
        end
    end
    if not evf then
        if next(events) == nil then return end
        evf = CreateFrame("Frame")
        evf:SetScript("OnEvent", OnEvent)
    end
    for event in pairs(registered) do
        if not events[event] then
            evf:UnregisterEvent(event)
            registered[event] = nil
        end
    end
    for event in pairs(events) do
        if not registered[event] then
            evf:RegisterEvent(event)
            registered[event] = true
        end
    end
end

---------------------------------------------------------------------------
-- What the controller calls
---------------------------------------------------------------------------
function ST.OnChange(fn) listener = fn end

-- Reminders are on: the world event is listened for (keys follow ST.Want).
function ST.Start()
    if started then return end
    started = true
    SyncEvents()
end

-- Off: nothing is wanted, listened for or kept. A timer from before finds itself stale.
function ST.Stop()
    token = token + 1
    queued = false
    started = false
    for k in pairs(want) do want[k] = nil end
    for k in pairs(dirty) do dirty[k] = nil end
    obs.slots = {}
    obs.combat, obs.life, obs.mounted = nil, nil, nil
    combat = nil
    SyncEvents()
end

-- The keys the enabled reminders read, as a set. Every one is read now (so a decision made right after is current),
-- and what is no longer wanted is forgotten, so an old value is never used later.
function ST.Want(keys)
    for key in pairs(want) do
        if not keys[key] then
            want[key] = nil
            dirty[key] = nil
            local kind, arg = Split(key)
            if kind == "slot" then obs.slots[tonumber(arg)] = nil else obs[kind] = nil end
        end
    end
    for key in pairs(keys) do want[key] = true end
    if ST.InWorld() then
        for key in pairs(want) do Read(key, obs) end
    end
    SyncEvents()
end

-- Reads every wanted key again (after entering the world). Returns nothing; the controller decides afresh.
function ST.ReadAll()
    for key in pairs(want) do Read(key, obs) end
    SyncEvents()
end

function ST.Observations() return obs end

-- The observations one reminder's conditions need, read now into a table of their own: for the settings window's
-- look at a reminder that isn't running (a draft, or one for another character). The live table is not touched,
-- nothing is listened for and no item is asked for.
function ST.Peek(view)
    local into = { slots = {} }
    if not ST.InWorld() then return into end
    for _, entry in ipairs(view.conditions) do
        if entry.provider and entry.cond then
            entry.provider.Needs(entry.cond, function(key) Read(key, into) end)
        end
    end
    return into
end

-- Who is playing: { character = "Name - Realm" or nil, class = token or nil }. Reused table.
local ctx = {}
function ST.Context()
    ctx.character = R.Reminders.CharacterKey()
    ctx.class = UnitClassBase and Plain(UnitClassBase("player")) or nil
    return ctx
end

-- Whether the game said there is no item with this ID (so it stays without details).
function ST.ItemMissing(id) return missing[id] == true end

-- For /tui diagnostics and the tests: counts only.
function ST.Snapshot()
    local events, keys = 0, 0
    for _ in pairs(registered) do events = events + 1 end
    for _ in pairs(want) do keys = keys + 1 end
    return { started = started, events = events, keys = keys, reads = stats.reads, tellings = stats.tellings,
        eventsSeen = stats.events, asked = stats.asked, unresolved = Unresolved() }
end

function ST.Registered(event) return registered[event] == true end
