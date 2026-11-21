-- TwichUI Fishing: clams and other containers caught while fishing
--
-- Which items: only items taken from a fishing loot window (Loot.lua) are ever considered. One is a fishing container when it
-- is a known clam (Data.lua) or when the bags call it openable (C_Container.GetContainerItemInfo(...).hasLoot); the latter
-- is learned for next time. Containers that did not come from fishing are never queued, opened or counted.
--
-- The queue (TwichUIFishingDB.chars[...].queue) holds lots: { id, item, n, sid, t }: n containers of one item caught in
-- session sid. Nothing about their contents is assumed before one is opened.
--
-- Opening (config containers.mode):
--   "queue" (default): only by the player's press, of the fishing key between casts (config containers.openWithKey) or of
--          its own key ("Open the next fishing container"). The press is a secure "item" action on the container's bag slot.
--   "auto": additionally, out of combat and with no line out, C_Container.UseContainerItem from addon code after a catch.
--          The Forever API documentation does not mark it restricted, but whether the client allows it without a key press
--          is NOT verified: the first ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN naming this addon turns it off for good
--          (TwichUIFishingDB.capability.autoOpen = "blocked") and the queue is used instead.
--   "off": nothing is opened by TwichUI; containers are still recorded.
--
-- What a container held: the loot window that opens within a few seconds of the press is that container's
-- (Loot.lua counts what is taken from it). A container the player opens by hand (right-click) is matched only when, after
-- that loot window, exactly one queued item has exactly one fewer in the bags; anything else stays unattributed. A
-- container is counted opened when it has left the bags; one that stays (bags full, loot left in it) stays queued.
-- Contents are recorded apart from direct catches (Session.lua), so a container and what it held are never both counted
-- as catches, and the session it was caught in keeps them.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local G = F.Gear
local Ses = F.Session
local C = {}
F.Containers = C

local pending = nil       -- { lot, item, at, count, via }: a press or an automatic open, waiting for its loot window
local candidates = {}     -- [itemID] = { { sid, q }... }: items from fishing loot not known yet to be containers
local candidatesAt = 0
C.OPEN_SECONDS = 3

local function Queue()
    local c = S.Char()
    return c and c.queue or nil
end
C.Queue = Queue

function C.Pending() return pending end

local function Lot(id)
    for _, lot in ipairs(Queue() or {}) do if lot.id == id then return lot end end
    return nil
end

local function Enqueue(sid, item, q)
    local c = S.Char()
    if not c then return end
    local queue = c.queue
    -- the same session's lot of that item grows instead of adding another
    local last = queue[#queue]
    if last and last.item == item and last.sid == sid and not last.locked then
        last.n = last.n + q
    else
        if #queue >= F.LIMITS.queue then
            table.remove(queue, 1)
            F.Note("queue-full", "the oldest queued container was forgotten")
        end
        queue[#queue + 1] = { id = c.nextLot, item = item, n = q, sid = sid, t = F.Now() }
        c.nextLot = c.nextLot + 1
    end
    Ses.ContainerCaught(sid, item, q)
    F.Emit("CONTAINER", "caught", item, q, sid)
    F.Emit("QUEUE")
end

-- Loot.lua: an item taken from a fishing loot window.
function C.Caught(sid, item, q)
    if S.IsKnownContainer(item) then
        Enqueue(sid, item, q)
        return true
    end
    local list = candidates[item]
    if not list then list = {}; candidates[item] = list end
    list[#list + 1] = { sid = sid, q = q }
    candidatesAt = F.Clock()
    return false
end

-- After the bags change: a candidate the bags call openable is a container from now on.
function C.Classify()
    if not next(candidates) then return end
    local open = {}
    G.EachBagItem(function(e) if candidates[e.item] and e.hasLoot then open[e.item] = true end end)
    local now = F.Clock()
    for item, list in pairs(candidates) do
        if open[item] then
            S.LearnContainer(item)
            for _, x in ipairs(list) do Enqueue(x.sid, item, x.q) end
            candidates[item] = nil
        elseif now - candidatesAt > 5 or G.BagCount(item) > 0 then
            candidates[item] = nil   -- in the bags and not openable (or never arrived): not a container
        end
    end
end

---------------------------------------------------------------------------
-- The next container to open
---------------------------------------------------------------------------
-- The oldest lot whose item is in the bags and openable now: lot, bag, slot (nil when none).
function C.Next()
    local queue = Queue()
    if not queue or #queue == 0 then return nil end
    local where = {}
    G.EachBagItem(function(e)
        if e.hasLoot and not e.locked and not where[e.item] then where[e.item] = e end
    end)
    for _, lot in ipairs(queue) do
        local e = not lot.locked and where[lot.item]
        if e then return lot, e.bag, e.slot end
    end
    return nil
end

-- What the fishing key (fromKey) or the open key should do: { kind = "open", lot, item, bag, slot } or nil and why.
function C.Plan(fromKey)
    local mode = S.Get("containers.mode")
    if mode == "off" then return nil, "off" end
    if fromKey and not S.Get("containers.openWithKey") then return nil, "not-with-key" end
    if pending and F.Clock() < pending.at + C.OPEN_SECONDS then return nil, "opening" end
    local lot, bag, slot = C.Next()
    if not lot then return nil, "empty" end
    local free = G.FreeSlots()
    if free ~= nil and free < (S.Get("containers.minFree") or 1) then return nil, "bags-full" end
    return { kind = "open", lot = lot.id, item = lot.item, bag = bag, slot = slot }
end

-- The press (or the automatic open) is about to use the container.
function C.BeginOpen(plan, via)
    pending = { lot = plan.lot, item = plan.item, at = F.Clock(), count = G.BagCount(plan.item), via = via or "key" }
    if C_Timer and C_Timer.After then C_Timer.After(C.OPEN_SECONDS + 0.1, function() C.CheckOpen() end) end
end

-- No loot window came: the open failed (or was blocked).
function C.CheckOpen()
    local p = pending
    if not p or p.loot or F.Clock() < p.at + C.OPEN_SECONDS then return end
    pending = nil
    local lot = Lot(p.lot)
    if lot then
        lot.fails = (lot.fails or 0) + 1
        Ses.ContainerFailed(lot.sid, lot.item)
    end
    F.Note("open-failed", "no loot window opened")
    F.Emit("CONTAINER", "failed", p.item)
end

-- UI_ERROR_MESSAGE while an open is waiting.
function C.OnError(message)
    local p = pending
    if not p or p.loot or F.Clock() > p.at + C.OPEN_SECONDS then return end
    message = F.Readable(message)
    if type(message) ~= "string" then return end
    local lot = Lot(p.lot)
    if message == rawget(_G, "ERR_ITEM_LOCKED") then
        if lot then lot.locked = true end
        pending = nil
        F.Note("container-locked", "a container needs a key or lockpicking")
        F.Say("TwichUI: that container is locked; it stays in your bags and is skipped.")
        F.Emit("QUEUE")
    elseif message == rawget(_G, "ERR_INV_FULL") then
        F.Note("bags-full", "no room for a container's contents")
    end
end

---------------------------------------------------------------------------
-- Loot windows from items (Loot.lua)
---------------------------------------------------------------------------
-- A loot window that is not fishing loot opened. Returns the attribution it starts with: { lot, item, via } when a press
-- or an automatic open is waiting for it, { manual = counts } when the player may have opened a queued container by
-- hand, or nil (unrelated).
function C.LootOpened(fromItem)
    local p = pending
    if p and not p.loot and F.Clock() <= p.at + C.OPEN_SECONDS then
        p.loot = true
        if p.via == "auto" then
            local db = S.db
            if db and db.capability then db.capability.autoOpen = "worked" end
        end
        return { lot = p.lot, item = p.item, via = p.via, count = p.count }
    end
    if fromItem ~= true then return nil end   -- only LOOT_OPENED says a window came from an item
    local queue = Queue()
    if not queue or #queue == 0 then return nil end
    -- the counts from the last settled bags before this window (the client may take the container out of the bags as the
    -- window opens or only as it closes; the remembered counts work either way), else the bags now
    local counts, any = {}, false
    for _, lot in ipairs(queue) do
        if counts[lot.item] == nil then counts[lot.item] = C.counts[lot.item] or G.BagCount(lot.item); any = true end
    end
    if not any then return nil end
    return { manual = counts }
end

-- The bags settled with no loot window in progress: remember how many of each queued item they hold.
C.counts = {}
function C.RememberCounts()
    local counts = {}
    for _, lot in ipairs(Queue() or {}) do
        if counts[lot.item] == nil then counts[lot.item] = G.BagCount(lot.item) end
    end
    C.counts = counts
end

local function TakeFromLot(lot)
    lot.n = lot.n - 1
    lot.partial = nil
    Ses.ContainerOpened(lot.sid, lot.item)
    if lot.n <= 0 then
        local queue = Queue()
        for i, l in ipairs(queue) do if l == lot then table.remove(queue, i) break end end
    end
end

-- The container loot window closed and the bags have settled. taken: { { item, q } } from that window.
-- Returns the lot it was attributed to (nil: unattributed, nothing recorded).
function C.Settle(attr, taken)
    if pending and attr.lot and pending.lot == attr.lot then pending = nil end
    local lot
    if attr.lot then
        lot = Lot(attr.lot)
        if lot then
            if G.BagCount(lot.item) < (attr.count or 0) then TakeFromLot(lot) else lot.partial = true end
        end
    elseif attr.manual then
        local match, n = nil, 0
        for item, before in pairs(attr.manual) do
            if G.BagCount(item) == before - 1 then match, n = item, n + 1 end
        end
        if n == 1 then
            for _, l in ipairs(Queue() or {}) do if l.item == match and not l.locked then lot = l break end end
            if lot then TakeFromLot(lot) end
        else
            F.Note("unattributed", "a container loot window matched no single queued container")
        end
    end
    if lot then
        for _, x in ipairs(taken) do Ses.Content(lot.sid, lot.item, x.item, x.q) end
        F.Emit("CONTAINER", "opened", lot.item, lot.sid)
    end
    F.Emit("QUEUE")
    return lot
end

-- After the bags change with nothing waiting: a queued container no longer in the bags (sold, destroyed, opened where
-- TwichUI couldn't see) is taken off the queue, newest first, so the queue never claims more than the bags hold.
function C.Reconcile()
    if pending then return end
    local queue = Queue()
    if not queue or #queue == 0 then return end
    local want = {}
    for _, lot in ipairs(queue) do want[lot.item] = (want[lot.item] or 0) + lot.n end
    local changed = false
    for item, n in pairs(want) do
        local have = G.BagCount(item)
        local over = n - have
        for i = #queue, 1, -1 do
            if over <= 0 then break end
            local lot = queue[i]
            if lot.item == item then
                local take = math.min(lot.n, over)
                lot.n, over, changed = lot.n - take, over - take, true
                if lot.n <= 0 then table.remove(queue, i) end
            end
        end
    end
    if changed then
        F.Note("queue-trimmed", "queued containers left your bags")
        F.Emit("QUEUE")
    end
end

---------------------------------------------------------------------------
-- Automatic opening (config containers.mode "auto"; never while blocked, in combat, looting or with a line out)
---------------------------------------------------------------------------
function C.AutoBlocked()
    local db = S.db
    return db and db.capability and db.capability.autoOpen == "blocked" or false
end

function C.TryAuto()
    if S.Get("containers.mode") ~= "auto" or C.AutoBlocked() then return false end
    if F.InCombat() or pending then return false end
    if F.Action and F.Action.LineOut() then return false end
    if F.Loot and F.Loot.Open() then return false end
    local plan = C.Plan(false)
    if not plan then return false end
    if not (C_Container and C_Container.UseContainerItem) then return false end
    C.BeginOpen(plan, "auto")
    local ok, err = pcall(C_Container.UseContainerItem, plan.bag, plan.slot)
    if not ok then
        F.Note("open-error", tostring(err):sub(1, 80))
        pending = nil
        return false
    end
    return true
end

function C.ScheduleAuto()
    if S.Get("containers.mode") ~= "auto" or C.AutoBlocked() then return end
    if C_Timer and C_Timer.After then C_Timer.After(1, C.TryAuto) end
end

-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN (addon, function).
function C.OnBlocked(addon)
    addon = F.Readable(addon)
    if addon ~= F.ADDON and addon ~= R.ADDON then return end
    if pending and pending.via == "auto" then
        pending = nil
        local db = S.db
        if db and db.capability then db.capability.autoOpen = "blocked" end
        F.Note("blocked", "automatic container opening is not allowed by the client")
        F.Say("TwichUI: the game doesn't allow opening containers automatically; press the fishing key to open them.")
    else
        F.Note("blocked", "an action was blocked by the client")
    end
end

-- Read only.
function C.Status()
    local queue = Queue() or {}
    local lots, n, locked = #queue, 0, 0
    for _, lot in ipairs(queue) do
        n = n + lot.n
        if lot.locked then locked = locked + lot.n end
    end
    local db = S.db
    return { lots = lots, unopened = n, locked = locked, mode = S.Get("containers.mode"),
        autoOpen = db and db.capability and db.capability.autoOpen or nil, opening = pending ~= nil }
end
