-- TwichUI: Reminders, reading the game
-- The live observations the enabled reminders' conditions read, kept as plain facts (the same shape a simulation
-- builds): obs.slots[n] = { empty = true } or { id, classID, subClassID, equipLoc } (no details yet: classID nil),
-- obs.combat = true | false, obs.life = "alive" | "dead" | "ghost", obs.mounted = true | false, obs.class = the class
-- token ("WARRIOR"; UnitClassBase), obs.ammo = the facts
-- about the ranged weapon's ammunition (Ammunition.lua says which and judges them). A key nobody wants
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
-- GetInventoryItemCount, UnitUsesAmmo, C_Container.GetContainerNumSlots / GetContainerItemID,
-- C_Item.GetItemInfoInstant, C_Item.RequestLoadItemDataByID, C_Item.GetItemNameByID, UnitAffectingCombat,
-- UnitIsDeadOrGhost, UnitIsGhost, IsMounted, UnitClassBase; events PLAYER_ENTERING_WORLD,
-- PLAYER_EQUIPMENT_CHANGED (slot, hasCurrent), BAG_UPDATE_DELAYED, UNIT_INVENTORY_CHANGED (unit),
-- PLAYER_REGEN_DISABLED / _ENABLED, PLAYER_DEAD, PLAYER_ALIVE, PLAYER_UNGHOST, PLAYER_MOUNT_DISPLAY_CHANGED,
-- GET_ITEM_INFO_RECEIVED and ITEM_DATA_LOAD_RESULT (itemID, success).

local R = TwichUI
local Perf = R.Perf
local C = R.ReminderConditions
local ST = {}
R.ReminderState = ST

local COALESCE = 0.1
local SETTLE = { 1, 3 }   -- seconds after entering the world when everything wanted is read once more (see OnEvent)
local MAX_ASK = 2

local obs = { slots = {} }   -- the live observations
local want = {}              -- [key] = true: what the enabled reminders read
local evf                    -- the event frame, made when first needed
local registered = {}        -- [event] = true
local dirty = {}             -- [key] = true: due to be read
local changed = {}           -- reused for each telling; the listener must not keep it
local queued = false
local token = 0              -- bumped by Stop: a timer from before does nothing
local settleToken = 0        -- bumped by each world entry (and Stop): an older settle look does nothing
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

-- The character's class never changes while playing, so there is nothing to listen for: it is read when wanted and again
-- on entering the world (ST.ReadAll), and only a different answer is a change.
ST.Source("class", {
    Read = function(_, into)
        local v
        if UnitClassBase then v = Plain(UnitClassBase("player")) end
        if type(v) ~= "string" or v == "" then v = nil end
        return Set(into, "class", v)
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

---------------------------------------------------------------------------
-- Ranged ammunition (key "ammo": obs.ammo, judged by Ammunition.lua)
---------------------------------------------------------------------------
-- A read is up to six values from the character, and the bags only when the weapon takes ammunition and nothing is
-- selected (to tell "carrying some" from "none"), stopping at the first stack that fits. Bag and unit events matter
-- only while the weapon takes ammunition (or the game hasn't said); with a weapon that takes none, only a change of
-- the ranged or ammo slot is noticed, which is all it takes to see one that does being equipped.
local AMMO_RETRY, AMMO_RETRIES = 1.0, 3   -- seconds before looking again at data that wasn't there, and how many times
local ammoWatch = true
local ammoRetries = 0
local ammoFields = { "uses", "ranged", "needs", "id", "kind", "count", "carries" }
local ammoNew = {}

local function LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- Whether the carried bags (the backpack and the equipped bags, quivers and pouches included; never the bank, mail or
-- the auction house) hold ammunition the weapon can use. true / false / nil (unreadable).
local function Carries(needs)
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    local AI = R.AmmoItems
    for bag = 0, LastBag() do
        local slots = Number(C_Container.GetContainerNumSlots(bag))
        if slots then
            for slot = 1, slots do
                local id = Number(C_Container.GetContainerItemID(bag, slot))
                if id then
                    local kind = AI.Kind(id)
                    if (kind == "arrow" or kind == "bullet") and (needs == nil or kind == needs) then return true end
                end
            end
        end
    end
    return false
end

local function ReadAmmo(into)
    stats.reads = stats.reads + 1
    local A, AI = R.ReminderAmmo, R.AmmoItems
    local n = ammoNew
    for _, k in ipairs(ammoFields) do n[k] = nil end

    local uses
    if UnitUsesAmmo then uses = Plain(UnitUsesAmmo("player")) end
    if type(uses) ~= "boolean" then uses = nil end
    n.uses = uses

    local rangedId = GetInventoryItemID and Number(GetInventoryItemID("player", A.RANGED_SLOT)) or nil
    n.ranged = rangedId ~= nil
    if rangedId and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(rangedId)
        n.needs = A.NeedsFor(Number(class), Number(sub))
    end

    local ammoId = GetInventoryItemID and Number(GetInventoryItemID("player", A.AMMO_SLOT)) or nil
    n.id = ammoId
    if ammoId then
        n.kind = AI.Kind(ammoId)
        if GetInventoryItemCount then n.count = Number(GetInventoryItemCount("player", A.AMMO_SLOT)) end
    elseif uses and n.ranged then
        n.carries = Carries(n.needs)
    end

    local f, differs = into.ammo, false
    if not f then f = {}; into.ammo = f; differs = true end
    for _, k in ipairs(ammoFields) do
        if f[k] ~= n[k] then f[k] = n[k]; differs = true end
    end
    if into == obs then ammoWatch = uses ~= false end   -- a settings-window look at a draft doesn't steer the live events

    -- data that wasn't there (just after login): look again shortly, a few times, then give up until the game says more
    if A.Judge(f) == "unknown" then
        if into == obs and ammoRetries < AMMO_RETRIES then
            ammoRetries = ammoRetries + 1
            local mine = token
            C_Timer.After(AMMO_RETRY, function()
                if mine == token then Mark("ammo") end
            end)
        end
    else
        ammoRetries = 0
    end
    return differs
end

ST.Source("ammo", {
    events = {
        PLAYER_EQUIPMENT_CHANGED = function(slot)
            slot = Number(slot)
            local A = R.ReminderAmmo
            if slot == A.AMMO_SLOT or slot == A.RANGED_SLOT then return true end
        end,
        BAG_UPDATE_DELAYED = function() if ammoWatch then return true end end,
        UNIT_INVENTORY_CHANGED = function(unit) if ammoWatch and unit == "player" then return true end end,
    },
    Read = function(_, into) return ReadAmmo(into) end,
})

-- Everything wanted is looked at again, asking the game rather than trusting what its events last said; only what
-- differs is told on (through the usual Mark / Flush).
local function Settle(mine)
    if mine ~= settleToken then return end
    if R.Life and not R.Life.InWorld() then return end   -- another loading screen: its own world entry looks again
    combat = nil
    for key in pairs(want) do Mark(key) end
end

local function OnEvent(_, event, ...)
    stats.events = stats.events + 1
    if event == "PLAYER_ENTERING_WORLD" then
        worldSeen = true
        combat = nil   -- a loading screen: ask the game again
        ammoRetries = 0
        -- The game does not finish settling inside this event (gear, mount, life and combat can still be changing just
        -- after a login, a reload or a dungeon door), and not every change comes with an event of its own: look again
        -- shortly, twice, so what is shown never rests on the first look alone.
        settleToken = settleToken + 1
        local mine = settleToken
        for _, seconds in ipairs(SETTLE) do
            C_Timer.After(seconds, function() Settle(mine) end)
        end
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
        evf:SetScript("OnEvent", Perf.Wrap("reminders.event", OnEvent))
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
    settleToken = settleToken + 1
    queued = false
    started = false
    for k in pairs(want) do want[k] = nil end
    for k in pairs(dirty) do dirty[k] = nil end
    obs.slots = {}
    obs.combat, obs.life, obs.mounted, obs.ammo, obs.class = nil, nil, nil, nil, nil
    combat, ammoWatch, ammoRetries = nil, true, 0
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
            -- the combat events are no longer heard, so what they last said can't be trusted when it is wanted again
            if kind == "combat" then combat = nil end
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
    for _, entry in ipairs(view.leaves) do
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
