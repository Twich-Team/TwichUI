-- TwichUI: Vendors and trainers, what merchants sell
-- A merchant's stock is kept as item ids only (npcs/Store.lua's `s`): an id is the same in every language and on every
-- client, so it is what is shared. Everything you read about an item (its name, link, icon, colour, tooltip) is the
-- game's own, looked up by id when it is wanted. Nothing about an item is stored but its id: no name, no price.
--   Names.   C_Item.GetItemNameByID answers from the client's item cache, so an item this client has never met has no
--            name yet. When something wants names (a search, the stock window), the unknown ones are asked for with
--            C_Item.RequestLoadItemDataByID, a few at a time, once each per session, and GET_ITEM_INFO_RECEIVED says
--            when one arrives. That is the game's ordinary item lookup (what a tooltip does); nothing is sent to any
--            player. A search asks for at most REQUEST_SESSION_MAX items in a session, and stops when its list closes.
--   The index. For a search: item id -> the merchants that sell it, built from the list when first asked and let go when
--            the search closes or the list changes. Held in memory only.
--   Matching. Find(words): an item matches when its name holds at least one of the words; the words it lacks have to be
--            in the NPC's own text (name, area, role, title; the World Knowledge filter's text), so "acorn goldshire"
--            finds the Goldshire merchant that sells an acorn. An item that holds no word at all matches nothing.

local R = TwichUI
local NS, KN = R.NpcStore, R.NpcKnowledge
local NI = {}
R.NpcItems = NI

NI.REQUEST_BATCH = 20               -- items asked for at once
NI.REQUEST_EVERY = 0.5              -- seconds between batches
NI.REQUEST_SESSION_MAX = 1500       -- items a search asks the game for in one session
local NOTIFY_DELAY = 0.3

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

---------------------------------------------------------------------------
-- What the game says about an item
---------------------------------------------------------------------------
-- The item's name when the client has it, else nil.
function NI.Name(id)
    if not (C_Item and C_Item.GetItemNameByID) then return nil end
    local ok, name = pcall(C_Item.GetItemNameByID, id)
    name = ok and Plain(name) or nil
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local lowered, loweredCount = {}, 0   -- [id] = lower-case name, for the ones that have one (a name never changes within a session)
local MAX_LOWERED = 8000                  -- bounded: past it the table starts again (the game's own cache answers meanwhile)
local function LowerName(id)
    local l = lowered[id]
    if l then return l end
    local name = NI.Name(id)
    if not name then return nil end
    l = name:lower()
    if loweredCount >= MAX_LOWERED then lowered, loweredCount = {}, 0 end
    lowered[id] = l
    loweredCount = loweredCount + 1
    return l
end
NI.LowerName = LowerName

-- The item's icon (a file id), or nil.
function NI.Icon(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        icon = ok and Plain(icon) or nil
        if icon then return icon end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, id)
        icon = ok and Plain(icon) or nil
        if icon then return icon end
    end
    return nil
end

-- The item's quality colour r, g, b, or nil.
function NI.Color(id)
    if not (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityColor) then return nil end
    local ok, quality = pcall(C_Item.GetItemQualityByID, id)
    quality = ok and Plain(quality) or nil
    if type(quality) ~= "number" then return nil end
    local ok2, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    r, g, b = ok2 and Plain(r), ok2 and Plain(g), ok2 and Plain(b)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    return nil
end

-- A link to the item for a chat line, or nil while the name isn't known. The game's own link when it has one.
function NI.Link(id)
    if C_Item and C_Item.GetItemInfo then
        local ok, _, link = pcall(C_Item.GetItemInfo, id)
        link = ok and Plain(link) or nil
        if type(link) == "string" and link ~= "" then return link end
    end
    local name = NI.Name(id)
    if not name then return nil end
    local r, g, b = NI.Color(id)
    return ("|cff%02x%02x%02x|Hitem:%d|h[%s]|h|r"):format(math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5), id, name)
end

---------------------------------------------------------------------------
-- Asking the game for names it hasn't loaded
---------------------------------------------------------------------------
local requested = {}        -- [id] = true: asked for this session (never asked twice)
local waiting = {}          -- [id] = true: asked for, no answer yet
local queue, head, tail = {}, 1, 0
local pumping = false
local listening = false
local asked = 0
local notifyPending = false
local listeners = {}

-- fn() runs (once, a moment after) when names have arrived. It must not change the list.
function NI.OnNames(fn) listeners[#listeners + 1] = fn end

local function Arrived()
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(NOTIFY_DELAY, function()
        notifyPending = false
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn)
            if not ok and R.Fault then R.Fault("vendors and trainers", err) end
        end
    end)
end

local function Settled()
    if listening and next(waiting) == nil and head > tail then
        listening = false
        R:Off("GET_ITEM_INFO_RECEIVED", NI.OnInfo)
    end
end

function NI.OnInfo(id)
    id = Plain(id)
    if not (id and waiting[id]) then return end
    waiting[id] = nil
    Arrived()
    Settled()
end

local function Pump()
    pumping = false
    local sent = 0
    while head <= tail and sent < NI.REQUEST_BATCH do
        local id = queue[head]
        queue[head] = nil
        head = head + 1
        if not requested[id] and not NI.Name(id) and C_Item and C_Item.RequestLoadItemDataByID then
            requested[id], waiting[id] = true, true
            asked = asked + 1
            sent = sent + 1
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    if head > tail then
        queue, head, tail = {}, 1, 0
        Settled()
    else
        pumping = true
        C_Timer.After(NI.REQUEST_EVERY, Pump)
    end
end

-- Asks the game for these items' names (ids), the ones it hasn't got and hasn't been asked for. capped: counts toward
-- REQUEST_SESSION_MAX (a search); the stock window's own items do not.
function NI.Request(ids, capped)
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return 0 end
    local added = 0
    for _, id in ipairs(ids) do
        if not requested[id] and not NI.Name(id) then
            if capped and asked + (tail - head + 1) >= NI.REQUEST_SESSION_MAX then break end
            tail = tail + 1
            queue[tail] = id
            added = added + 1
        end
    end
    if added > 0 then
        if not listening then
            listening = true
            R:On("GET_ITEM_INFO_RECEIVED", NI.OnInfo)
        end
        if not pumping then
            pumping = true
            C_Timer.After(0, Pump)
        end
    end
    return added
end

---------------------------------------------------------------------------
-- The index, for searching
---------------------------------------------------------------------------
local idx   -- { src = the list's entries, by = { [item id] = { entry, ... } }, ids = { every item id once } }

local function Index()
    local entries = NS.Entries()
    if idx and idx.src == entries then return idx end
    idx = { src = entries, by = {}, ids = {} }
    for _, e in ipairs(entries) do
        if e.s then
            for _, id in ipairs(e.s) do
                local list = idx.by[id]
                if not list then
                    list = {}
                    idx.by[id] = list
                    idx.ids[#idx.ids + 1] = id
                end
                list[#list + 1] = e
            end
        end
    end
    return idx
end

NS.OnChange(function() idx = nil end)

-- Lets go of the index and of any names still waiting to be asked for (the search that wanted them has closed). Names
-- already asked for still arrive; they are kept by the game.
function NI.Release()
    idx = nil
    queue, head, tail = {}, 1, 0
    Settled()
end

-- The switch went off: nothing is asked for and the index goes.
function NI.Refresh() if not R:Enabled("npcMap") then NI.Release() end end

-- words: lower-case words (the query split on spaces). Returns { [row] = { item id, ... } } for the NPC rows (npcs/Knowledge.lua)
-- that sell an item matching, and the number of items whose names are not yet known (they are being asked for, so a later
-- search finds more).
function NI.Find(words)
    local hits, unknown = {}, {}
    if #words == 0 then return hits, 0 end
    local ix = Index()
    local lacks = {}
    for _, id in ipairs(ix.ids) do
        local name = LowerName(id)
        if not name then
            unknown[#unknown + 1] = id
        else
            local any, n = false, 0
            for i = 1, #words do
                if name:find(words[i], 1, true) then any = true
                else n = n + 1 lacks[n] = words[i] end
            end
            if any then
                for _, e in ipairs(ix.by[id]) do
                    local row = KN.Row(e)
                    local ok = row ~= nil
                    for i = 1, ok and n or 0 do
                        if not row.hay:find(lacks[i], 1, true) then ok = false break end
                    end
                    if ok then
                        local list = hits[row]
                        if not list then list = {} hits[row] = list end
                        list[#list + 1] = id
                    end
                end
            end
        end
    end
    if #unknown > 0 then NI.Request(unknown, true) end
    return hits, #unknown
end

-- Read only, for /tui diagnostics: counts, never an item or a merchant.
function NI.Snapshot()
    local waitingCount = 0
    for _ in pairs(waiting) do waitingCount = waitingCount + 1 end
    return { asked = asked, waiting = waitingCount, queued = math.max(0, tail - head + 1), indexed = idx ~= nil,
        listening = listening }
end
