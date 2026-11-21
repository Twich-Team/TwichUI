-- TwichUI Fishing: loot windows, catches and the items taken from them
--
-- Evidence is the client's loot events only (Blizzard_APIDocumentationGenerated/LootDocumentation.lua and
-- Blizzard_UIPanels_Game/Mainline/LootFrame.lua, which camelot loads): LOOT_READY (autoloot), LOOT_OPENED (autoLoot,
-- isFromItem), LOOT_SLOT_CLEARED (slot), LOOT_CLOSED; IsFishingLoot(), GetNumLootItems, GetLootSlotType, GetLootSlotLink and
-- GetLootSlotInfo. A change in the bags is never taken as a catch.
--
--   One window = one capture. LOOT_READY and LOOT_OPENED both start it; whichever comes second, and any repeat, only adds
--   what it knows (isFromItem). The slots are read when it starts, before auto-loot empties them.
--   Fishing loot (IsFishingLoot() true): one catch, counted at once. Each item is counted when its slot is cleared (it
--   reached the bags), so items left behind (full bags) are not counted, and an item is counted once however often the
--   event comes. A slot still not cleared when the window closes waits two seconds for the client's own
--   "You receive loot" line (CHAT_MSG_LOOT, LOOT_ITEM_SELF / _MULTIPLE) to confirm it; otherwise it was left.
--   Other loot: a container the fishing key (or an automatic open) just used, or a queued container opened by hand
--   (Containers.lua decides). Everything else (mobs, chests, other bags) is unrelated and not recorded.

local R = TwichUI
local F = R.Fishing
local Ses = F.Session
local C = F.Containers
local Lo = {}
F.Loot = Lo

local cur = nil            -- the capture of the window that is open (nil when none)
local held = {}            -- closed captures waiting for loot chat lines: { capture... }
Lo.CONFIRM_SECONDS = 2
Lo.lastFishing = nil       -- F.Clock() of the last fishing loot window
Lo.windows, Lo.duplicates = 0, 0

local ITEM_SLOT = 1
do
    local E = rawget(_G, "Enum")
    if E and E.LootSlotType and E.LootSlotType.Item then ITEM_SLOT = E.LootSlotType.Item end
end

function Lo.Open() return cur ~= nil and not cur.closed end
function Lo.Current() return cur end

local function ReadSlots()
    local slots, n = {}, F.Count(GetNumLootItems and GetNumLootItems()) or 0
    for i = 1, n do
        local kind = GetLootSlotType and F.Num(GetLootSlotType(i))
        if kind == nil or kind == ITEM_SLOT then
            local id = F.ItemID(GetLootSlotLink and GetLootSlotLink(i))
            local q = GetLootSlotInfo and F.Count((select(3, GetLootSlotInfo(i)))) or nil
            if id then slots[i] = { item = id, q = (q and q > 0) and q or 1 } end
        end
    end
    return slots
end

-- Records one taken item for the capture it came from.
local function Take(capture, item, q)
    if capture.kind == "fishing" then
        Ses.Item(capture.sid, item, q)
        C.Caught(capture.sid, item, q)
    elseif capture.kind == "container" or capture.kind == "maybe" then
        capture.taken[#capture.taken + 1] = { item = item, q = q }
    end
end

-- What a window that is not fishing loot is: a container's (attributed), possibly a hand-opened container's, or unrelated.
local function Resolve(capture, fromItem)
    local attr = C.LootOpened(fromItem)
    if attr and attr.lot then
        capture.kind, capture.attr = "container", attr
    elseif attr and attr.manual then
        capture.kind, capture.attr = "container", attr
    elseif fromItem == nil then
        capture.kind = "maybe"   -- LOOT_READY: LOOT_OPENED says whether it came from an item
    else
        capture.kind = "unrelated"
        capture.taken = {}
    end
end

local function Begin(fromItem)
    if cur and not cur.closed then
        Lo.duplicates = Lo.duplicates + 1
        if cur.kind == "maybe" and fromItem ~= nil then Resolve(cur, fromItem) end
        return
    end
    Lo.windows = Lo.windows + 1
    cur = { at = F.Clock(), slots = ReadSlots(), taken = {} }
    if F.Readable(IsFishingLoot and IsFishingLoot()) == true then
        cur.kind = "fishing"
        Lo.lastFishing = cur.at
        cur.sid = Ses.Catch()
        if F.Action and F.Action.OnCatch then F.Action.OnCatch() end
        local items = 0
        for _ in pairs(cur.slots) do items = items + 1 end
        F.Emit("CATCH", cur.sid, items)
    else
        Resolve(cur, fromItem)
    end
    if F.Action and F.Action.OnLootState then F.Action.OnLootState(true) end
end

function Lo.OnReady() Begin(nil) end
function Lo.OnOpened(_, fromItem) Begin(F.Readable(fromItem) == true) end

function Lo.OnSlotCleared(slot)
    slot = F.Count(slot)
    if not (cur and not cur.closed and slot) then return end
    local e = cur.slots[slot]
    if not e or e.taken then
        Lo.duplicates = Lo.duplicates + 1
        return
    end
    e.taken = true
    Take(cur, e.item, e.q)
end

local function Finish(capture)
    for i, h in ipairs(held) do if h == capture then table.remove(held, i) break end end
    local left = 0
    for _, e in pairs(capture.slots) do if not e.taken then left = left + 1 end end
    if left > 0 and capture.kind == "fishing" then F.Note("left-in-loot", left .. " item(s) not taken") end
    if capture.kind == "container" then
        C.Settle(capture.attr, capture.taken)
    end
    capture.done = true
    if capture.kind == "fishing" then C.ScheduleAuto() end
    if capture.kind == "container" then C.ScheduleAuto() end
end

function Lo.OnClosed()
    if not cur or cur.closed then
        Lo.duplicates = Lo.duplicates + 1
        return
    end
    local capture = cur
    capture.closed = true
    if capture.kind == "maybe" then capture.kind = "unrelated" end
    if F.Action and F.Action.OnLootState then F.Action.OnLootState(false) end
    if capture.kind == "unrelated" then capture.done = true return end
    local waiting = false
    for _, e in pairs(capture.slots) do if not e.taken then waiting = true end end
    if waiting or capture.kind == "container" then
        held[#held + 1] = capture
        while #held > 5 do Finish(held[1]) end
        if C_Timer and C_Timer.After then C_Timer.After(Lo.CONFIRM_SECONDS, function() if not capture.done then Finish(capture) end end) end
    else
        Finish(capture)
    end
end

function Lo.Waiting() return #held > 0 end

---------------------------------------------------------------------------
-- The client's own loot line confirms a slot that was never reported cleared (held captures only)
---------------------------------------------------------------------------
local patterns
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local p = Pattern(rawget(_G, name))
        if p then patterns[#patterns + 1] = { p = p, multiple = name:find("MULTIPLE") ~= nil } end
    end
    return patterns
end
Lo.Patterns = Patterns

function Lo.ParseChat(text)
    text = F.Readable(text)
    if type(text) ~= "string" then return nil end
    for _, e in ipairs(Patterns()) do
        local link, n = text:match(e.p)
        if link then
            local id = F.ItemID(link)
            if id then return id, e.multiple and tonumber(n) or 1 end
        end
    end
    return nil
end

function Lo.OnChat(text)
    if #held == 0 then return end
    local id, q = Lo.ParseChat(text)
    if not id then return end
    for _, capture in ipairs(held) do
        for _, e in pairs(capture.slots) do
            if not e.taken and e.item == id and e.q == q then
                e.taken = true
                Take(capture, id, q)
                return
            end
        end
    end
end

-- Read only.
function Lo.Status()
    return { open = Lo.Open(), kind = cur and cur.kind or nil, waiting = #held, windows = Lo.windows, duplicates = Lo.duplicates }
end
