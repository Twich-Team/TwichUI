-- TwichUI: marker cycling, the markers and their order
-- Two kinds, kept apart everywhere: target markers (the icons the game puts over a unit, SetRaidTarget's 1 to 8)
-- and world markers (the ones placed on the ground, PlaceRaidMarker's 1 to 8). The same number is a different
-- marker in each: target 1 is the Star, world 1 is the Square.
--
-- Identities, checked in WoW: Forever's UI source:
--   target markers: index 1..8 = Star, Circle, Diamond, Triangle, Moon, Square, Cross, Skull (RAID_TARGET_1..8,
--     the icons Interface\TargetingFrame\UI-RaidTargetingIcon_1..8 the chat frame's {star} ... {skull} use)
--   world markers: Blizzard's own marker buttons (Blizzard_CompactRaidFrameManager, Mainline and Classic) show
--     world marker WORLD_RAID_MARKER_ORDER[9 - id] with target icon id, which makes world marker 1..8 the
--     icons of target markers 6, 4, 3, 7, 1, 2, 5, 8 (Square, Triangle, Diamond, Cross, Star, Circle, Moon,
--     Skull). Both lists are shown in the game's order: Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star.
--
-- Saved (the profile's, TwichUIDB.ui.markerOrder[kind] = { order = { all 8 ids }, off = { ids skipped } }):
-- the order always holds all eight, so a marker turned off keeps its place and comes back to it. Nothing about
-- the cycle's position is saved; that lives on the secure buttons (markers/Keys.lua) and starts again each
-- session. Options that aren't the order are in TwichUIDB.ui.markers (M.Get / M.Set).
-- Nothing here makes a frame or touches the game: markers/Keys.lua does that, and listens through M.OnChange.

local R = TwichUI
local M = {}
R.Markers = M

M.KINDS = { "target", "world" }
M.COUNT = 8
M.SWITCH = { target = "markersTarget", world = "markersWorld" }

local TARGET_FALLBACK = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local WORLD_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }   -- world marker id -> the target icon it shows

M.DEFAULT_ORDER = {
    target = { 8, 7, 6, 5, 4, 3, 2, 1 },          -- Skull, Cross, Square, Moon, Triangle, Diamond, Circle, Star
    world = { 8, 4, 1, 7, 2, 3, 6, 5 },           -- the same icons in the same order (WORLD_RAID_MARKER_ORDER)
}

---------------------------------------------------------------------------
-- Identities
---------------------------------------------------------------------------
local function ValidKind(kind) return kind == "target" or kind == "world" end
M.ValidKind = ValidKind

function M.ValidId(id) return type(id) == "number" and id % 1 == 0 and id >= 1 and id <= M.COUNT end

-- The target icon (1..8) a marker of this kind shows.
function M.Icon(kind, id)
    if not M.ValidId(id) then return nil end
    if kind == "world" then return WORLD_ICON[id] end
    return id
end

function M.Texture(kind, id)
    local icon = M.Icon(kind, id)
    return icon and ([[Interface\TargetingFrame\UI-RaidTargetingIcon_]] .. icon) or nil
end

-- The marker's name in the game's language (its icon's name: a world marker is the same symbol on the ground).
function M.Name(kind, id)
    local icon = M.Icon(kind, id)
    if not icon then return "?" end
    local name = _G["RAID_TARGET_" .. icon]
    if type(name) ~= "string" or name == "" then name = TARGET_FALLBACK[icon] end
    return name
end

-- "|T...|t Skull", for one line of text.
function M.Tag(kind, id, size)
    local tex = M.Texture(kind, id)
    if not tex then return "" end
    return ("|T%s:%d:%d|t %s"):format(tex, size or 14, size or 14, M.Name(kind, id))
end

---------------------------------------------------------------------------
-- Checking a sequence (saved, imported, or about to be saved)
---------------------------------------------------------------------------
-- An order: exactly the eight ids, each once.
function M.ValidOrder(list)
    if type(list) ~= "table" then return false end
    local n, seen = 0, {}
    for k, id in pairs(list) do
        if type(k) ~= "number" or not M.ValidId(id) or seen[id] then return false end
        seen[id] = true
        n = n + 1
    end
    if n ~= M.COUNT then return false end
    for i = 1, M.COUNT do if list[i] == nil then return false end end
    return true
end

-- The markers turned off: known ids, each once (in any order; an empty list is every marker on).
function M.ValidOff(list)
    if type(list) ~= "table" then return false end
    local n, seen = 0, {}
    for k, id in pairs(list) do
        if type(k) ~= "number" or not M.ValidId(id) or seen[id] then return false end
        seen[id] = true
        n = n + 1
    end
    for i = 1, n do if list[i] == nil then return false end end
    return true
end

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

---------------------------------------------------------------------------
-- The saved order
---------------------------------------------------------------------------
local listeners = {}

-- fn(kind) after the order, a marker's on/off or an option of that kind changed (kind nil: both, after a
-- profile change or an import put other values in place).
function M.OnChange(fn)
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end

local function Changed(kind)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, kind)
        if not ok then R.Fault("marker cycling", err) end
    end
end
M.Changed = Changed

local function Saved(kind)
    local ui = TwichUIDB and TwichUIDB.ui
    local all = type(ui) == "table" and ui.markerOrder
    local entry = type(all) == "table" and all[kind]
    return type(entry) == "table" and entry or nil
end

-- For writing: the kind's table, made if missing (the other kind's is left as it is).
local function Store(kind)
    if type(TwichUIDB) ~= "table" then return nil end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.markerOrder) ~= "table" then TwichUIDB.ui.markerOrder = {} end
    local entry = TwichUIDB.ui.markerOrder[kind]
    if type(entry) ~= "table" then
        entry = {}
        TwichUIDB.ui.markerOrder[kind] = entry
    end
    return entry
end

-- The order as it is used: the saved one if it is whole, else the default. A copy.
function M.Order(kind)
    if not ValidKind(kind) then return {} end
    local entry = Saved(kind)
    if entry and M.ValidOrder(entry.order) then return Copy(entry.order) end
    return Copy(M.DEFAULT_ORDER[kind])
end

-- The markers turned off, as a set. A damaged list counts as none turned off.
function M.OffSet(kind)
    local set = {}
    local entry = ValidKind(kind) and Saved(kind)
    if entry and M.ValidOff(entry.off) then
        for _, id in ipairs(entry.off) do set[id] = true end
    end
    return set
end

function M.IsOn(kind, id) return M.ValidId(id) and not M.OffSet(kind)[id] end

-- What a press goes through: the markers that are on, in order. Empty when every one is off.
function M.Sequence(kind)
    local off, out = M.OffSet(kind), {}
    for _, id in ipairs(M.Order(kind)) do
        if not off[id] then out[#out + 1] = id end
    end
    return out
end

-- Whether order and markers are as a new installation has them.
function M.IsDefault(kind)
    local order, def = M.Order(kind), M.DEFAULT_ORDER[kind]
    for i = 1, M.COUNT do if order[i] ~= def[i] then return false end end
    return next(M.OffSet(kind)) == nil
end

local function SameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
M.SameList = SameList

local function SortedOff(set)
    local list = {}
    for id in pairs(set) do list[#list + 1] = id end
    table.sort(list)
    return list
end

-- Saves an order (all eight ids, each once). The markers turned off stay off, wherever they now are.
function M.SetOrder(kind, list)
    if not ValidKind(kind) or not M.ValidOrder(list) then return false end
    if SameList(M.Order(kind), list) then return true end
    local entry = Store(kind)
    if not entry then return false end
    entry.order = Copy(list)
    if not M.ValidOff(entry.off) then entry.off = {} end   -- a damaged off list: none off, rather than unreadable
    Changed(kind)
    return true
end

-- Turns one marker on or off. It keeps its place in the order either way.
function M.SetOn(kind, id, on)
    if not ValidKind(kind) or not M.ValidId(id) then return false end
    local off = M.OffSet(kind)
    on = on and true or false
    if (not off[id]) == on then return true end
    off[id] = (not on) or nil
    local entry = Store(kind)
    if not entry then return false end
    if not M.ValidOrder(entry.order) then entry.order = M.Order(kind) end
    entry.off = SortedOff(off)
    Changed(kind)
    return true
end

-- Moves the marker at position `from` (1..8) to position `to`, the others closing up. Its on/off is unchanged.
function M.Move(kind, from, to)
    local order = M.Order(kind)
    if type(from) ~= "number" or type(to) ~= "number" or not order[from] or to < 1 or to > #order then return false end
    if from == to then return true end
    local id = table.remove(order, from)
    table.insert(order, to, id)
    return M.SetOrder(kind, order)
end

-- Where a marker ends up when dropped in gap g (0: before the first, 8: after the last), moving from `from`.
function M.DropTarget(from, gap)
    if type(from) ~= "number" or type(gap) ~= "number" then return from end
    gap = math.max(0, math.min(M.COUNT, math.floor(gap)))
    if gap >= from then return gap end
    return gap + 1
end

-- Puts back the default order with every marker on, for this kind only.
function M.ResetOrder(kind)
    if not ValidKind(kind) then return false end
    local ui = TwichUIDB and TwichUIDB.ui
    if type(ui) == "table" and type(ui.markerOrder) == "table" and ui.markerOrder[kind] ~= nil then
        ui.markerOrder[kind] = nil
        Changed(kind)
    end
    return true
end

---------------------------------------------------------------------------
-- The cycle's arithmetic (the secure buttons do the same, in markers/Keys.lua)
---------------------------------------------------------------------------
-- step: how many presses since the cycle (re)started, as the buttons keep it (0 = the next is the first).
-- Returns the marker the next press gives and the step after it, or nil while the sequence is empty.
function M.NextAfter(sequence, step)
    local n = #sequence
    if n == 0 then return nil, step end
    local nextStep = ((tonumber(step) or 0) % n) + 1
    return sequence[nextStep], nextStep
end

---------------------------------------------------------------------------
-- Options other than the order (TwichUIDB.ui.markers)
---------------------------------------------------------------------------
M.DEFAULTS = {
    targetUnit = "target",          -- "target": your target; "mouseover": a living enemy under the pointer, else your target
    targetClearRestarts = true,     -- removing your target's mark also restarts the target cycle
    worldClearRestarts = true,      -- removing every world marker also restarts the world cycle
}
M.UNITS = { target = true, mouseover = true }

function M.Valid(key, value)
    if key == "targetUnit" then return type(value) == "string" and M.UNITS[value] == true end
    if key == "targetClearRestarts" or key == "worldClearRestarts" then return type(value) == "boolean" end
    return false
end

function M.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = type(ui) == "table" and ui.markers
    local value
    if type(t) == "table" then value = t[key] end   -- not "and ... or": a saved false is a value
    if M.Valid(key, value) then return value end
    return M.DEFAULTS[key]
end

function M.Set(key, value)
    if M.DEFAULTS[key] == nil or not M.Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.markers) ~= "table" then TwichUIDB.ui.markers = {} end
    if TwichUIDB.ui.markers[key] == value then return true end   -- unchanged: nothing to redo
    TwichUIDB.ui.markers[key] = value
    Changed(key:find("^target") and "target" or "world")
    return true
end

---------------------------------------------------------------------------
-- Configuration sharing (setup/TwichConfig.lua): the two orders as data, checked the same way
---------------------------------------------------------------------------
-- { target = { order, off }, world = { order, off } }: the orders in use (a missing or damaged one is shared as
-- the default it is used as).
function M.Export()
    local out = {}
    for _, kind in ipairs(M.KINDS) do
        out[kind] = { order = M.Order(kind), off = SortedOff(M.OffSet(kind)) }
    end
    return out
end

-- An imported entry, checked: each kind present must have a whole order and a valid off list; nothing else is
-- read. Returns the clean copy, or nil and why ("shape", "invalid", "empty").
function M.Clean(raw)
    if type(raw) ~= "table" then return nil, "shape" end
    local out, any = {}, false
    for k in pairs(raw) do
        if not ValidKind(k) then return nil, "invalid" end
    end
    for _, kind in ipairs(M.KINDS) do
        local e = raw[kind]
        if e ~= nil then
            if type(e) ~= "table" then return nil, "shape" end
            for field in pairs(e) do
                if field ~= "order" and field ~= "off" then return nil, "invalid" end
            end
            if not M.ValidOrder(e.order) then return nil, "invalid" end
            local off = e.off == nil and {} or e.off
            if not M.ValidOff(off) then return nil, "invalid" end
            local set = {}
            for _, id in ipairs(off) do set[id] = true end
            out[kind] = { order = Copy(e.order), off = SortedOff(set) }
            any = true
        end
    end
    if not any then return nil, "empty" end
    return out
end

-- Writes a clean entry's kinds in place, with plain assignments (the import tells the features afterwards).
-- Returns undo records: { kind, had, entry }.
function M.ApplyClean(clean)
    local undo = {}
    for _, kind in ipairs(M.KINDS) do
        local e = clean[kind]
        if e then
            local all = TwichUIDB.ui.markerOrder
            if type(all) ~= "table" then
                all = {}
                TwichUIDB.ui.markerOrder = all
            end
            local old = all[kind]
            undo[#undo + 1] = { kind = kind, had = type(old) == "table",
                entry = type(old) == "table" and { order = type(old.order) == "table" and Copy(old.order) or nil,
                    off = type(old.off) == "table" and Copy(old.off) or nil } or nil }
            all[kind] = { order = Copy(e.order), off = Copy(e.off) }
        end
    end
    return undo
end

-- Puts back what ApplyClean replaced. Returns how many kinds were put back.
function M.RestoreRecords(records)
    local n = 0
    if type(records) ~= "table" then return 0 end
    for i = #records, 1, -1 do
        local u = records[i]
        if type(u) == "table" and ValidKind(u.kind) and type(TwichUIDB.ui) == "table" then
            if type(TwichUIDB.ui.markerOrder) ~= "table" then TwichUIDB.ui.markerOrder = {} end
            if u.had == true and type(u.entry) == "table" then
                local e = {}
                if M.ValidOrder(u.entry.order) then e.order = Copy(u.entry.order) end
                if M.ValidOff(u.entry.off) then e.off = Copy(u.entry.off) end
                TwichUIDB.ui.markerOrder[u.kind] = e
            else
                TwichUIDB.ui.markerOrder[u.kind] = nil
            end
            n = n + 1
        end
    end
    return n
end

-- After a profile change or an import: every listener reads the orders again.
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "markers", function() Changed(nil) end)
end
