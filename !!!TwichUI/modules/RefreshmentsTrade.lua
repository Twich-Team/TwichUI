-- TwichUI: Mage refreshments, trade assistance
-- While a Mage with Mage refreshments on trades with a group member (whoever opened the trade), a small
-- strip under the game's trade window says what goes in for them and offers **Fill trade**:
--   whole stacks of the rank planned for them go into empty trade slots (1 to 6, never the seventh, the
--   "will not be traded" slot); what is left over is split off into an empty bag slot, and goes in once
--   the game has shown the new stack. Items already in the window, placed by hand or earlier, count and
--   are never moved or taken out. Only the conjured food and water of the rank planned is ever picked up.
--   It never accepts the trade.
-- How much: by default their whole class share in every trade, however much they had before (they may
-- need more); or, by the player's choice, only what is still owed this session.
-- By itself (Fill trades automatically, on by default): a moment after the trade opens, and again as the
-- game shows each move, what is planned goes in without a click. It stops for the trade as soon as the
-- player takes something out of it, never adds once either side has accepted, waits while something is
-- on the cursor or in combat, and makes a few passes at most. If the game blocks a move made that way,
-- filling by itself is switched off for the session (one line says so) and the button still works.
-- What was handed over: the window as it stood when you accepted is counted when the game says the
-- trade was completed. If no such message is seen (WoW: Forever's own message for it is not in its UI
-- source, so it is looked for, not assumed), the offer is kept as "offered" in the refreshments panel to
-- confirm or dismiss. Once a completed trade has been recognised this session, a trade without the
-- message is taken as not completed.
-- People outside the group get no share, so the strip only explains that for them.
-- Listens for trades only while on; for a trade's details only while it is open (and a few seconds
-- after, for its "complete" message). Nothing here is saved.

local R = TwichUI
local RF = R.Refreshments
local S = R.ChronicleStyle
local K = S.color
local T = {}
R.RefreshmentsTrade = T

local Plain = R.SpellMenu.Plain
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local SLOTS = 6          -- the trade window's item slots; the seventh is never used
local ACK_WAIT = 3       -- seconds for the game to show a placed stack, or a split stack in the bags
local CLOSE_WAIT = 3     -- seconds after a trade closes for its "complete" message
local MAX_CODES = 8      -- message codes kept for diagnostics
local AUTO_DELAY = 0.3   -- seconds after a trade opens, or the game shows a move, before filling by itself
local MAX_AUTO = 8       -- passes that fill by itself in one trade

T.GIVES = { { "share", "Their whole share, every trade" }, { "owed", "Only what is still owed this session" } }
T.DEFAULT_GIVES = "share"

-- What each trade puts in: "share" (their whole share every time) or "owed" (what is still owed).
function T.Gives()
    local v = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.refreshmentsTradeGives
    return (v == "share" or v == "owed") and v or T.DEFAULT_GIVES
end

local Update   -- below

function T.SetGives(value)
    if value ~= "share" and value ~= "owed" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    TwichUIDB.ui.refreshmentsTradeGives = value
    Update()
    return true
end

local autoBlocked = false   -- the game blocked a move made by itself: no more of those this session

function T.AutoOn() return R:Enabled("mageRefreshmentsAutoFill") and not autoBlocked end

local KIND_OF = {}       -- [itemID] = "water" | "food", for every conjured rank
for kind, list in pairs(RF.ITEMS) do
    for _, item in ipairs(list) do KIND_OF[item] = kind end
end

function T.Enabled() return RF.Enabled() and R:Enabled("mageRefreshmentsTrade") end

-- Notice: a short local line where the game shows its own; never chat.
local function Notice(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
end

---------------------------------------------------------------------------
-- What one click would do. Pure, so it can be checked on its own.
-- input = {
--   freeSlots  empty trade slots
--   canSplit   whether there is an empty bag slot to split into
--   kinds      { { kind, item, need, stackSize (or nil), stacks = { { bag, slot, count }, ... } }, ... }
--              stacks: the unlocked stacks of that item
-- }
-- Returns { moves = { { op = "place"|"split", kind, item, bag, slot, count }, ... }, placing = { kind = n },
-- splitting = { kind = n }, later = { kind = n } (a second split, for the next click), short = { kind = n },
-- noRoom = { kind = n } (needs an empty bag slot to split), slotsFull }.
-- Whole stacks go in when they are full or exactly what is left, largest first; what is left after them is
-- split from the smallest stack bigger than it (one split per click: it holds the empty bag slot until it
-- lands); with nothing to split from, or no room to split, loose stacks go in as they are.
---------------------------------------------------------------------------
function T.PlanMoves(input)
    local out = { moves = {}, placing = {}, splitting = {}, later = {}, short = {}, noRoom = {}, slotsFull = false }
    local slots = input.freeSlots
    local splitUsed = false
    for _, k in ipairs(input.kinds) do
        local remaining = k.need
        if remaining > 0 then
            local stacks, have = {}, 0
            for i, s in ipairs(k.stacks) do stacks[i] = s; have = have + s.count end
            table.sort(stacks, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                if a.bag ~= b.bag then return a.bag < b.bag end
                return a.slot < b.slot
            end)
            if have < remaining then out.short[k.kind] = remaining - have end
            local used = {}
            local function Place(i)
                local s = stacks[i]
                out.moves[#out.moves + 1] = { op = "place", kind = k.kind, item = k.item, bag = s.bag, slot = s.slot, count = s.count }
                out.placing[k.kind] = (out.placing[k.kind] or 0) + s.count
                used[i] = true
                slots = slots - 1
                remaining = remaining - s.count
            end
            for i, s in ipairs(stacks) do
                if remaining == 0 or slots == 0 then break end
                if s.count <= remaining and (s.count == remaining or (k.stackSize and s.count >= k.stackSize)) then Place(i) end
            end
            -- What is left, split from the smallest unused stack bigger than it. True when that was dealt with
            -- (split now, left for the next click, or noted as needing a bag slot).
            local function Split()
                local from
                for i = #stacks, 1, -1 do
                    if not used[i] and stacks[i].count > remaining then from = i break end
                end
                if not from then return false end
                if input.canSplit and not splitUsed then
                    local s = stacks[from]
                    out.moves[#out.moves + 1] = { op = "split", kind = k.kind, item = k.item, bag = s.bag, slot = s.slot, count = remaining }
                    out.splitting[k.kind] = remaining
                    splitUsed = true
                    slots = slots - 1      -- the split stack needs a trade slot when it lands
                elseif splitUsed then
                    out.later[k.kind] = remaining
                else
                    out.noRoom[k.kind] = remaining
                end
                remaining = 0
                return true
            end
            if remaining > 0 and slots > 0 and not Split() then
                -- Every stack is smaller than what is left: they go in as they are, largest first, and what
                -- is still left after them is split from one of the rest.
                for i, s in ipairs(stacks) do
                    if remaining == 0 or slots == 0 then break end
                    if not used[i] and s.count <= remaining then Place(i) end
                end
                if remaining > 0 and slots > 0 then Split() end
            end
            if remaining > 0 and slots <= 0 and not out.noRoom[k.kind] then out.slotsFull = true end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The trade
---------------------------------------------------------------------------
local trade              -- the open trade: { gen, open, guid, offer, done, fills }
local closing            -- a closed trade waiting a moment for its "complete" message
local pending = {}       -- [tradeSlot] = { item, kind, count, at }: placed, not yet shown by the game
local splitPending       -- { bag, slot, item, kind, count, at }: split into the bags, not yet landed
local generation = 0
local stats = { trades = 0, fills = 0, autoPasses = 0, placed = 0, splits = 0, refused = 0, blocked = 0,
    confirmed = 0, unconfirmed = 0, notCompleted = 0, completionSeen = false }
local running             -- "auto" or "click" while moves are being made
local halted = false      -- the game blocked one of them
local codes = {}         -- message codes seen while a trade was open or closing, for diagnostics
local lastOutcome
local status             -- the strip's last message after a click, until the next change
local strip

local function Trade(i)
    local name, _, count, _, _, _, _, item = GetTradePlayerItemInfo(i)
    name, count, item = Plain(name), Plain(count), Plain(item)
    if name and type(item) ~= "number" and GetTradePlayerItemLink then
        local link = Plain(GetTradePlayerItemLink(i))
        item = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    return name ~= nil, item, type(count) == "number" and count or 0
end

-- Your side of the window: empty slots, and conjured items per kind (and per item) already there or on
-- their way.
local function ReadWindow()
    local free, offered, items = {}, { water = 0, food = 0 }, {}
    for i = 1, SLOTS do
        local p = pending[i]
        local used, item, count = Trade(i)
        if p and not used then
            item, count, used = p.item, p.count, true
        end
        if not used then
            free[#free + 1] = i
        elseif item and KIND_OF[item] then
            offered[KIND_OF[item]] = offered[KIND_OF[item]] + count
            items[item] = (items[item] or 0) + count
        end
    end
    return free, offered, items
end

local function Unlocked(item)
    local out = {}
    for _, s in ipairs(RF.Stacks(item)) do
        if not s.locked then out[#out + 1] = s end
    end
    return out
end

local function Waiting() return next(pending) ~= nil or splitPending ~= nil end

-- Everything the strip and a click need, worked out the same way for both: who, what is still owed,
-- what is in the window, and what a click would do. reason: why there is nothing to click, or nil.
local function View()
    local v = {}
    if not (trade and trade.open) then v.reason = "closed" return v end
    if InCombat() then v.reason = "combat" return v end
    if trade.blocked then v.reason = "blocked" return v end
    if not trade.guid then v.reason = "unknown" return v end
    v.row = RF.RowFor(trade.guid)
    if not v.row then v.reason = "not-in-group" return v end
    if Waiting() then v.reason = "waiting" return v end
    local free, offered = ReadWindow()
    local whole = T.Gives() == "share"
    -- an unconfirmed earlier trade counts only towards what is owed; a whole share is per trade
    local earlier = (not whole and RF.Unconfirmed(trade.guid)) or {}
    v.offered, v.earlier, v.need, v.kinds = offered, earlier, {}, {}
    local any = false
    for _, kind in ipairs(RF.KINDS) do
        local base = whole and v.row.want[kind] or v.row.remaining[kind]
        local need = base - offered[kind] - (earlier[kind] or 0)
        v.need[kind] = math.max(0, need)
        local rank = v.row.rank[kind]
        if not rank and v.need[kind] > 0 then rank = RF.RankFor(RF.KnownRanks(kind), v.row.level) end
        if v.need[kind] > 0 and rank then
            local item = RF.ITEMS[kind][rank]
            v.kinds[#v.kinds + 1] = { kind = kind, item = item, rank = rank, need = v.need[kind],
                stackSize = RF.StackSize(item), stacks = Unlocked(item) }
            any = true
        end
    end
    if not any then
        if v.row.want.water + v.row.want.food == 0 then v.reason = "no-share"
        elseif not whole and v.row.remaining.water + v.row.remaining.food == 0 then v.reason = "supplied"
        else v.reason = "in-window" end
        return v
    end
    v.result = T.PlanMoves({ freeSlots = #free, canSplit = RF.EmptyBagSlot() ~= nil, kinds = v.kinds })
    v.free = free
    if #v.result.moves == 0 then v.reason = "nothing-to-move" end
    return v
end

local function Name(row) return row and row.name or "them" end

local function Summary(map)
    local parts = {}
    for _, kind in ipairs(RF.KINDS) do
        if map[kind] and map[kind] > 0 then parts[#parts + 1] = ("%d %s"):format(map[kind], kind) end
    end
    return table.concat(parts, " and ")
end

local REASON_TEXT = {
    combat = "Filling waits until you're out of combat.",
    blocked = "The game blocked a move, so nothing more is filled in this trade.",
    unknown = "Couldn't tell who you're trading with, so nothing is filled.",
    ["not-in-group"] = "Not in your group, so no share is planned for them.",
    waiting = "Waiting for the game to show the last move...",
    ["no-share"] = "Their class has no share set. Shares are on the Mage options page.",
    supplied = "Their share is already marked as handed over this session.",
    ["in-window"] = "Their share is in the window. Press Trade when you're both ready.",
}

-- The strip's two lines and whether its button can be clicked.
local function Describe(v)
    local head
    if v.row then
        local whole = T.Gives() == "share"
        local want = {}
        for _, kind in ipairs(RF.KINDS) do
            local n = whole and v.row.want[kind] or v.row.remaining[kind]
            if n > 0 then
                local rank = v.row.rank[kind] or RF.RankFor(RF.KnownRanks(kind), v.row.level)
                want[#want + 1] = ("%d %s%s"):format(n, kind, rank and (" (rank " .. rank .. ")") or "")
            end
        end
        head = Name(v.row) .. ": " .. (#want > 0 and table.concat(want, ", ") or (whole and "no share" or "nothing owed"))
    else
        head = "Mage refreshments"
    end
    if v.reason and v.reason ~= "nothing-to-move" then return head, status or REASON_TEXT[v.reason] or "", false end
    local r = v.result
    local notes = {}
    if next(r.short) then notes[#notes + 1] = "Short " .. Summary(r.short) .. ": conjure more, then Fill again." end
    if next(r.noRoom) then notes[#notes + 1] = "Free a bag slot to split " .. Summary(r.noRoom) .. "." end
    if next(r.later) then notes[#notes + 1] = "Then " .. Summary(r.later) .. " with another click." end
    if r.slotsFull then notes[#notes + 1] = "The trade window is full." end
    if v.earlier and ((v.earlier.water or 0) + (v.earlier.food or 0)) > 0 then
        notes[#notes + 1] = "An earlier trade wasn't confirmed; it counts here until you confirm or dismiss it in the panel."
    end
    if v.reason == "nothing-to-move" then return head, status or table.concat(notes, " "), false end
    local plan = {}
    if next(r.placing) then plan[#plan + 1] = "puts in " .. Summary(r.placing) end
    if next(r.splitting) then
        plan[#plan + 1] = "splits " .. Summary(r.splitting) .. ((trade and trade.auto and T.AutoOn()) and ", which goes in once it lands" or " to add with your next click")
    end
    return head, status or ("Fill trade " .. table.concat(plan, ", ") .. "." .. (#notes > 0 and (" " .. table.concat(notes, " ")) or "")), true
end

function Update()
    if not (strip and strip:IsShown()) then return end
    local head, line, can = Describe(View())
    strip.head:SetText(head)
    strip.line:SetText(line)
    strip.fill:SetEnabled(can)
    R.Interact.RefreshTip(strip.fill)
end

local function Settle(gen)
    C_Timer.After(ACK_WAIT, function()
        if not (trade and trade.gen == gen) then return end
        local now = GetTime()
        for i, p in pairs(pending) do
            if now - p.at >= ACK_WAIT then
                pending[i] = nil
                R.Life.Note("trade-place-not-shown")
            end
        end
        if splitPending and now - splitPending.at >= ACK_WAIT then
            splitPending = nil
            R.Life.Note("trade-split-not-seen")
        end
        Update()
    end)
end

-- One click's moves, in the click. Stops at the first one the game doesn't take.
local BLOCKED = "The game blocked that move."

local function Execute(v)
    local slots = v.free
    local nextSlot = 1
    local placed, split = 0, nil
    halted = false
    local function Halt()
        if GetCursorInfo() then ClearCursor() end
        return placed, split, BLOCKED
    end
    for _, m in ipairs(v.result.moves) do
        if m.op == "place" then
            local tslot = slots[nextSlot]
            if not tslot then break end
            pcall(C_Container.PickupContainerItem, m.bag, m.slot)
            if halted then return Halt() end
            local what, id = GetCursorInfo()
            if what ~= "item" or Plain(id) ~= m.item then
                if GetCursorInfo() then ClearCursor() end
                stats.refused = stats.refused + 1
                return placed, split, "The game didn't let TwichUI pick up the " .. m.kind .. "."
            end
            pcall(ClickTradeButton, tslot)
            if halted then return Halt() end
            if GetCursorInfo() then
                ClearCursor()
                stats.refused = stats.refused + 1
                return placed, split, "The trade window didn't take the " .. m.kind .. "."
            end
            pending[tslot] = { item = m.item, kind = m.kind, count = m.count, at = GetTime() }
            nextSlot = nextSlot + 1
            placed = placed + m.count
            stats.placed = stats.placed + 1
        else
            local bag, slot = RF.EmptyBagSlot()
            if not bag then break end
            pcall(C_Container.SplitContainerItem, m.bag, m.slot, m.count)
            if halted then return Halt() end
            local what, id = GetCursorInfo()
            if what ~= "item" or Plain(id) ~= m.item then
                if GetCursorInfo() then ClearCursor() end
                stats.refused = stats.refused + 1
                return placed, split, "The game didn't split the " .. m.kind .. "."
            end
            pcall(C_Container.PickupContainerItem, bag, slot)
            if halted then return Halt() end
            if GetCursorInfo() then
                ClearCursor()
                stats.refused = stats.refused + 1
                return placed, split, "The game didn't take the split " .. m.kind .. " into your bags."
            end
            splitPending = { bag = bag, slot = slot, item = m.item, kind = m.kind, count = m.count, at = GetTime() }
            split = m.count
            stats.splits = stats.splits + 1
        end
    end
    return placed, split
end

function T.Fill()
    status = nil
    if not (trade and trade.open) then return false end
    if GetCursorInfo() then
        status = "Put down what you're holding first, then Fill again."
        Update()
        return false
    end
    local v = View()
    if v.reason then Update() return false end
    stats.fills = stats.fills + 1
    trade.fills = trade.fills + 1
    running = "click"
    local placed, split, why = Execute(v)
    running = nil
    if why then status = why end
    if placed > 0 or split then Settle(trade.gen) end
    Update()
    return why == nil
end

-- One pass by itself: what a click would do, when nothing is in the way. Stops for the trade when a move
-- isn't taken or nothing more can move (the next change in the bags or the window tries again).
local function AutoStep(gen)
    if not (trade and trade.open and trade.gen == gen and trade.auto and T.AutoOn()) then return end
    if trade.offer or trade.theyAccepted then return end   -- adding now would undo an acceptance
    if InCombat() or GetCursorInfo() then return end        -- waits for the next change
    local v = View()
    if v.reason then return end
    if trade.autoPasses >= MAX_AUTO then
        trade.auto = false
        R.Life.Note("trade-auto-limit")
        return
    end
    trade.autoPasses = trade.autoPasses + 1
    stats.autoPasses = stats.autoPasses + 1
    status = nil
    running = "auto"
    local placed, split, why = Execute(v)
    running = nil
    if why then
        trade.auto = false
        if why ~= BLOCKED then status = why end
    end
    if placed > 0 or split then Settle(trade.gen) else trade.auto = false end
    Update()
end

local function AutoSoon()
    if not (trade and trade.open and trade.auto) or trade.autoQueued then return end
    trade.autoQueued = true
    local gen = trade.gen
    C_Timer.After(AUTO_DELAY, function()
        if trade and trade.gen == gen then trade.autoQueued = false end
        AutoStep(gen)
    end)
end

---------------------------------------------------------------------------
-- What was handed over
---------------------------------------------------------------------------
function T.IsCompletion(errorType, message)
    if LE_GAME_ERR_TRADE_COMPLETE ~= nil and errorType == LE_GAME_ERR_TRADE_COMPLETE then return true end
    if ERR_TRADE_COMPLETE ~= nil and message == ERR_TRADE_COMPLETE then return true end
    return false
end

local function OfferTotal(offer) return offer and (offer.water + offer.food) or 0 end

local ListenTrade   -- below

local function Complete(t)
    if t.done then return end
    t.done = "confirmed"
    stats.completionSeen = true
    lastOutcome = "confirmed"
    if OfferTotal(t.offer) > 0 and RF.Credit(t.guid, t.offer) then
        stats.confirmed = stats.confirmed + 1
        local row = RF.RowFor(t.guid)
        Notice(("Handed %s %s."):format(Name(row), Summary(t.offer)))
    end
end

local function FinishClosing(t)
    if closing == t then closing = nil end
    if not (trade and trade.open) then ListenTrade(false) end
    if t.done then return end
    if OfferTotal(t.offer) == 0 then t.done = "nothing-offered" lastOutcome = t.done return end
    if stats.completionSeen then
        -- The message has been seen for other trades: without it, this one didn't go through.
        t.done = "not-completed"
        stats.notCompleted = stats.notCompleted + 1
        R.Life.Note("trade-not-completed")
    elseif RF.Offered(t.guid, t.offer) then
        t.done = "unconfirmed"
        stats.unconfirmed = stats.unconfirmed + 1
        Notice("TwichUI couldn't confirm that trade went through. Confirm or dismiss it in the refreshments panel.")
    else
        t.done = "not-tracked"
    end
    lastOutcome = t.done
end

---------------------------------------------------------------------------
-- The strip under the trade window. A plain frame (no secure parts), so it shows and hides freely. It
-- has the refreshments panel's look (the player's, from the Mage options page), drawn on the outer
-- frame, which grows round its fixed-size content to clear the border.
---------------------------------------------------------------------------
local STRIP_W, STRIP_H = 338, 58

local function Restyle()
    if not strip then return end
    local style = R.RefreshmentsPanel and R.RefreshmentsPanel.Style
    local edge = style and math.ceil(style.Apply(strip)) or 0
    strip:SetSize(STRIP_W + edge * 2, STRIP_H + edge * 2)
end

local function BuildStrip()
    strip = CreateFrame("Frame", "TwichUIRefreshmentsTrade", UIParent, "BackdropTemplate")
    strip:SetSize(STRIP_W, STRIP_H)
    strip:SetFrameStrata("HIGH")
    strip:SetClampedToScreen(true)
    strip:Hide()
    local body = CreateFrame("Frame", nil, strip)
    body:SetSize(STRIP_W, STRIP_H)
    body:SetPoint("CENTER")
    strip.head = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    strip.head:SetPoint("TOPLEFT", 12, -10)
    strip.head:SetPoint("RIGHT", -100, 0)
    strip.head:SetJustifyH("LEFT")
    strip.head:SetWordWrap(false)
    strip.head:SetTextColor(K.text[1], K.text[2], K.text[3])
    strip.line = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    strip.line:SetPoint("TOPLEFT", 12, -28)
    strip.line:SetPoint("BOTTOMRIGHT", -100, 6)
    strip.line:SetJustifyH("LEFT")
    strip.line:SetJustifyV("TOP")
    strip.line:SetTextColor(K.textDim[1], K.textDim[2], K.textDim[3])
    strip.fill = S.Button(body, "Fill trade", 84, "primary", function() T.Fill() end)
    strip.fill:SetPoint("RIGHT", -10, 0)
    R.Interact.Tip(strip.fill, "Fill trade", function()
        local _, line, can = Describe(View())
        return "Puts their share into empty slots of the trade window. Only the conjured food and water planned for them, never anything else, and nothing already there is moved. You still press Trade yourself.",
            not can and line or nil
    end)
    strip:SetScript("OnHide", function(self) R.Interact.HideTip(self.fill) end)
end

local function ShowStrip()
    if not strip then BuildStrip() end
    strip:ClearAllPoints()
    if TradeFrame and TradeFrame.GetBottom then
        strip:SetPoint("TOPLEFT", TradeFrame, "BOTTOMLEFT", 0, -2)
    else
        strip:SetPoint("TOP", UIParent, "TOP", 0, -420)
    end
    Restyle()
    strip:Show()
    Update()
end

local function HideStrip()
    if strip then strip:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnItemChanged(slot)
    slot = Plain(slot)
    local was = slot and pending[slot]
    if slot then pending[slot] = nil end
    if slot and trade and trade.open and trade.auto and not Trade(slot) then
        -- Taken out, by the player (or not taken by the game): the trade is theirs to finish.
        trade.auto = false
        R.Life.Note(was and "trade-place-refused" or "trade-auto-stopped-by-you")
    end
    status = nil
    Update()
    AutoSoon()
end

local function OnAccept(player, target)
    if not (trade and trade.open) then return end
    trade.theyAccepted = Plain(target) == 1
    if Plain(player) == 1 then
        local _, offered, items = ReadWindow()
        trade.offer, trade.items = offered, items
    else
        trade.offer, trade.items = nil, nil
    end
    Update()
end

local function OnBags()
    if splitPending then
        local info = C_Container.GetContainerItemInfo(splitPending.bag, splitPending.slot)
        if info and Plain(info.itemID) == splitPending.item and Plain(info.isLocked) ~= true then splitPending = nil end
    end
    Update()
    AutoSoon()
end

local function OnInfo(errorType, message)
    if not ((trade and trade.open) or closing) then return end
    errorType = Plain(errorType)
    if type(errorType) == "number" and #codes < MAX_CODES then
        local known = false
        for _, c in ipairs(codes) do if c == errorType then known = true end end
        if not known then codes[#codes + 1] = errorType end
    end
    if T.IsCompletion(errorType, Plain(message)) then
        local t = (trade and trade.open and trade.offer) and trade or closing
        if t and t.offer then Complete(t) end
    end
end

local function OnBlocked(addon)
    if Plain(addon) ~= R.ADDON or not (trade and trade.open) then return end
    stats.blocked = stats.blocked + 1
    halted = true
    if running == "auto" then
        -- Moves made by itself aren't allowed here; one made by your click may still be.
        if not autoBlocked then Notice("The game doesn't let TwichUI fill the trade by itself. Click Fill trade instead.") end
        autoBlocked = true
        trade.auto = false
        R.Life.Note("trade-auto-blocked")
    else
        trade.blocked = true
        R.Life.Note("trade-move-blocked")
    end
    Update()
end

local function OnCombat()
    Update()
    AutoSoon()
end

local active = {}
local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

function ListenTrade(on)
    Want("TRADE_PLAYER_ITEM_CHANGED", OnItemChanged, on)
    Want("TRADE_ACCEPT_UPDATE", OnAccept, on)
    Want("BAG_UPDATE_DELAYED", OnBags, on)
    Want("UI_INFO_MESSAGE", OnInfo, on)
    Want("ADDON_ACTION_BLOCKED", OnBlocked, on)
    Want("PLAYER_REGEN_DISABLED", OnCombat, on)
    Want("PLAYER_REGEN_ENABLED", OnCombat, on)
end

local function OnShow()
    if closing then FinishClosing(closing) end   -- a trade still waiting for its message: decide now
    generation = generation + 1
    wipe(pending)
    splitPending, status = nil, nil
    local guid = Plain(UnitGUID("NPC"))
    trade = { gen = generation, open = true, guid = type(guid) == "string" and guid or nil, fills = 0, autoPasses = 0 }
    trade.auto = T.AutoOn() and trade.guid ~= nil and RF.RowFor(trade.guid) ~= nil
    stats.trades = stats.trades + 1
    ListenTrade(true)
    ShowStrip()
    AutoSoon()
end

local function OnClosed()
    local t = trade
    if not (t and t.open) then return end   -- the game can say it twice
    t.open = false
    trade = nil
    wipe(pending)
    splitPending, status = nil, nil
    HideStrip()
    if t.offer and not t.done then
        closing = t
        C_Timer.After(CLOSE_WAIT, function() if closing == t then FinishClosing(t) end end)
    else
        if not t.done then lastOutcome = "closed" end
        ListenTrade(false)
    end
end

-- Registers what is wanted and lets go of the rest. Safe to call any number of times.
function T.Refresh()
    local on = T.Enabled()
    Want("TRADE_SHOW", OnShow, on)
    Want("TRADE_CLOSED", OnClosed, on)
    if not on then
        ListenTrade(false)
        trade, closing, splitPending, status = nil, nil, nil, nil
        wipe(pending)
        HideStrip()
    else
        Update()
    end
end

-- The plan or the switches changed: an open strip follows. So does a change of look.
RF.OnChange(T.Refresh)
if R.RefreshmentsPanel and R.RefreshmentsPanel.Style then
    R.RefreshmentsPanel.Style.Subscribe(function() if strip and strip:IsShown() then Restyle() end end)
end

---------------------------------------------------------------------------
-- For /tui diagnostics: counts, codes and flags only.
---------------------------------------------------------------------------
function T.Snapshot()
    local events = {}
    for event in pairs(active) do events[#events + 1] = event end
    table.sort(events)
    local copy = {}
    for k, v in pairs(stats) do copy[k] = v end
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return {
        enabled = T.Enabled(), switchOn = R:Enabled("mageRefreshmentsTrade"), open = trade ~= nil and trade.open or false,
        partnerRead = trade ~= nil and trade.guid ~= nil, partnerInGroup = trade ~= nil and trade.guid ~= nil and RF.RowFor(trade.guid) ~= nil,
        blocked = trade ~= nil and trade.blocked or false, pending = n, splitPending = splitPending ~= nil,
        closing = closing ~= nil, lastOutcome = lastOutcome, stats = copy, codes = { unpack(codes) }, events = events,
        completionString = ERR_TRADE_COMPLETE ~= nil, completionCode = LE_GAME_ERR_TRADE_COMPLETE ~= nil,
        autoSwitch = R:Enabled("mageRefreshmentsAutoFill"), autoBlocked = autoBlocked, gives = T.Gives(),
        autoThisTrade = trade ~= nil and trade.auto or false,
    }
end
