-- TwichUI: Magic Inventory, carrying out a reviewed guild bank arrangement
-- Two actions, both the player's own click on a reviewed plan: DEPOSIT (carried items into the arrangement's tabs) and ORGANIZE
-- (items already in the guild bank moved to where the arrangement wants them, inside a tab and between tabs). The plan is the one
-- GuildPlan.lua makes from the SAVED rules; this file adds the review (what can really be done now, what cannot, and why), the
-- confirmation (bound to the exact plan and the state it was made from) and the run (one move at a time, each confirmed by reading
-- the game back). One review and one confirmation cover every tab the plan touches.
--
-- What the Forever client gives and what is not established (the Forever UI source, docs/magic-inventory.md):
--   * PickupGuildBankItem(tab, slot), SplitGuildBankItem(tab, slot, amount), GetGuildBankItemInfo(tab, slot) (-> texture,
--     count, locked), GetGuildBankTabInfo, GetCurrentGuildBankTab, CursorHasItem, GetCursorInfo, and the events
--     GUILDBANKBAGSLOTS_CHANGED (no payload: it does not say which tab), GUILDBANK_ITEM_LOCK_CHANGED, GUILDBANK_UPDATE_TABS,
--     CURSOR_CHANGED are all used by Blizzard_GuildBankUI.lua or documented. The guild bank calls are not in the API
--     documentation at all (no arguments, no protection or hardware-event flag), and the Blizzard UI only ever calls them for the
--     tab it SHOWS. Nothing in the source says they work for a tab that is not shown, so this file never relies on that.
--   * What the source does show: the frame itself selects tabs from code (OnShow, SelectAvailableTab), through the tab button's
--     OnClick, which shows the tab and asks the server for its items; the cursor is not touched by it. GuildBank.lua's GB.Show
--     calls that handler. So a run reaches another tab by SHOWING it and waiting until its items have been sent (GB.IsLive):
--     a tab switch alone is never evidence about the tab's contents.
--   * SplitGuildBankItem is used by the Blizzard stack-split dialog with nothing after it, so the split stack must go to the
--     cursor (as SplitContainerItem does for bags); the cursor's COUNT cannot be read (GetCursorInfo gives the item only),
--     so a split is verified only after it is placed.
--   * Not established: that these calls work for an addon outside a click, that the cursor's item survives the switch to another
--     tab the way the source suggests, and whether a move between tabs counts against the withdrawal allowance. The run finds
--     out by checking: if the game blocks a call (ADDON_ACTION_BLOCKED/FORBIDDEN) with nothing done, the run stops asking for a
--     click per move (Continue); a move between tabs is verified at the destination AND, after showing the source tab again, at
--     the source.
--
-- Safety, in the order a move is taken:
--   * the bank is open on its item page, the guild, the tabs' names and the rank's rights are the reviewed ones, out of combat,
--     the saved rules unchanged, the cursor empty, the source (and, where its tab is the one shown, the destination) hold exactly
--     what the review saw (identity AND count, not locked), the source stack is still allowed to move (the protections), and a
--     withdrawal is still allowed. A destination in another tab is judged the same way, from a fresh read of that tab, after it is
--     shown and before the item is placed (a placing onto a slot that changed would swap, so it is never done unchecked);
--   * split (when the stack is only partly moved), pickup, showing the destination tab and placing are tracked phases, each
--     confirmed from the game before the next; a cursor that holds anything else than the item of this move stops the run and is
--     never touched;
--   * a move counts only when a fresh read shows the source AND the destination as expected, both unlocked, the cursor
--     empty (between tabs: the destination right after placing, then the source once its tab is shown and read again, before the
--     next move). An event only says "read again". A wait is bounded (GR.WAIT) with a few reads inside it; there is no polling;
--   * a move is paced (GR.GAP after the last one: the real game dropped placements made right after the previous one, and
--     GuildBankSort, which works on Forever, does one move a second) and is retried at most once, only when a fresh read shows it
--     did NOT start (cursor empty, source and destination unchanged and unlocked, both readable) after a pause (GR.SETTLE), and
--     only through the full revalidation again. Anything else that times out or surprises reads the state once more and stops: a
--     move that may have happened is "uncertain", never repeated. The run never takes an item to the bags, swaps, parks or sells
--     anything;
--   * an item the run holds on the cursor is put back only where it came from and only when that is verified safe (its tab is
--     shown again first), then confirmed; otherwise it is left and the player is told where it belongs. The player's own cursor
--     is never touched;
--   * the player's own tab navigation is not fought: a tab shown that this run did not ask for stops it at once.
-- Nothing is saved, nothing resumes after a reload, a close or a reopening: a new review and confirmation are needed.

local R = TwichUI
local MI = R.MagicInventory
local Plain = MI.Plain
local GB = MI.GuildBank

local GR = {}
MI.GuildRun = GR

GR.WAIT = 4                 -- seconds the game has to show a move's result (or a tab's items)
GR.CHECKS = { 0.5, 1.5 }    -- state reads inside the wait (besides the game's events and the deadline)
GR.NAV_TRIES = 2            -- times a tab is asked for when its items are late (a read: safe to repeat)
GR.GAP = 1.0                -- seconds after one move is confirmed before the next is started (the game drops calls made too fast)
GR.SETTLE = 1.5             -- seconds to let a move the game never started settle before it is looked at once more and tried again
GR.TRIES = 2                -- times one move may be handed to the game, and only when it demonstrably did not start (see Untouched)
GR.CONFIRM_AGE = 120        -- seconds a reviewed plan can be confirmed
GR.START_AGE = 15           -- a tab read earlier is read again at the start unless it was read this recently (or is shown)
GR.MAX_MOVES = 250          -- at most this many moves in one run (the rest is "run again")
-- Splitting a stack is part of the plan the run carries out (SplitGuildBankItem for the guild bank, SplitContainerItem for a
-- bag: the part goes to the cursor, as the Blizzard stack-split dialog expects). Nothing in the source says how Forever answers,
-- so every split is checked from the game after it is placed (a wrong amount stops the run: Needs review). Off: the planner
-- lists splits as blocked and none is attempted.
GR.CAN_SPLIT = true

local run          -- the run in progress, or nil
local last         -- the last finished run's result (this session only)
local serial = 0
local active = {}  -- [event] = handler while registered

local listeners = {}
function GR.OnUpdate(fn) listeners[#listeners + 1] = fn end
local function Notify(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("magic inventory guild run", err) end
    end
end

function GR.Current() return run end
function GR.Last() return last end
function GR.Busy() return run ~= nil end
function GR.ClearLast() if last then last = nil; Notify("clear") end end

local function Num(v) v = Plain(v); if type(v) == "number" and v == v then return v end end
local function Now() return GetTime and GetTime() or 0 end
local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or (many or one .. "s")) end
local function Name(id)
    local f = id and MI.ItemFacts(id)
    return f and f.name or ("item " .. tostring(id))
end

---------------------------------------------------------------------------
-- What the game shows now (small readers; the only place this file looks at the client)
---------------------------------------------------------------------------
local function ShownTab() return Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab()) end

local function GuildNow()
    if not (IsInGuild and IsInGuild()) then return nil end
    local name = Plain(GetGuildInfo and (GetGuildInfo("player")))
    return type(name) == "string" and name ~= "" and name or nil
end

local function BankOpen()
    if not (MI.GuildBank and MI.GuildBank.IsOpen()) then return false end
    local frame = _G.GuildBankFrame
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end
    return true
end

-- name and the rank's rights in a tab; nil entries are "the game didn't say"
local function TabInfo(tab)
    if not GetGuildBankTabInfo then return nil end
    local name, _, viewable, canDeposit, withdrawals, remaining = GetGuildBankTabInfo(tab)
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local function Bool(v) v = Plain(v); if type(v) == "boolean" then return v end end
    withdrawals = Num(withdrawals)
    local canWithdraw
    if withdrawals ~= nil then canWithdraw = withdrawals ~= 0 end
    return { name = name, viewable = Bool(viewable), canDeposit = Bool(canDeposit), canWithdraw = canWithdraw, remaining = Num(remaining) }
end

-- A guild bank slot: nil when empty, else { id, count, locked } (id or count nil: the game didn't say)
local function GuildCell(tab, slot)
    local texture, count, locked = GetGuildBankItemInfo(tab, slot)
    if Plain(texture) == nil then return nil end
    local link = GetGuildBankItemLink and Plain(GetGuildBankItemLink(tab, slot))
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    return { id = id, count = Num(count), locked = Plain(locked) == true }
end

local function BagCell(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return { id = Num(info.itemID), count = Num(info.stackCount), locked = Plain(info.isLocked) == true }
end

-- where = { kind = "bag", bag, slot } or { kind = "guild", tab, slot }
local function Read(where)
    if where.kind == "bag" then return BagCell(where.bag, where.slot) end
    return GuildCell(where.tab, where.slot)
end

-- Whether what Read gives for this place can be believed now: a bag always; a guild bank slot only while its tab is the one
-- shown and its items arrived after it was shown (an empty answer for another tab means nothing)
local function Known(where)
    if where.kind == "bag" then return true end
    return GB.IsLive(where.tab)
end

-- "empty", "item" (and its ID), or "other" (something that is not an item, or that cannot be told)
local function Cursor()
    local kind, id
    if GetCursorInfo then kind, id = GetCursorInfo() end
    kind = Plain(kind)
    if kind == "item" then return "item", Num(id) end
    if kind ~= nil then return "other" end
    if CursorHasItem and CursorHasItem() then return "other" end
    return "empty"
end

-- The calls that move things. Each is one request to the game; whether it did anything is read back, never assumed.
local function CallPickup(where)
    if where.kind == "bag" then C_Container.PickupContainerItem(where.bag, where.slot) else PickupGuildBankItem(where.tab, where.slot) end
end
local function CallSplit(where, amount)
    if where.kind == "bag" then C_Container.SplitContainerItem(where.bag, where.slot, amount) else SplitGuildBankItem(where.tab, where.slot, amount) end
end

-- want: nil (empty) or { id, count }
local function Is(cell, want)
    if want == nil then return cell == nil end
    return cell ~= nil and cell.id == want.id and cell.count == want.count
end

local function Where(w)
    if w.kind == "bag" then return ("bag %d slot %d"):format(w.bag, w.slot) end
    return ("tab %d slot %d"):format(w.tab, w.slot)
end

local function Key(w) return w.kind == "bag" and ("b%d:%d"):format(w.bag, w.slot) or ("g%d:%d"):format(w.tab, w.slot) end

local function Cross(op) return op.src.kind == "guild" and op.src.tab ~= op.dst.tab end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
GR.WHY = {
    off = "Magic Inventory was turned off",
    combat = "combat started",
    changed = "your rules or destinations changed",
    stale = "the bank, your bags or your rules changed since the review",
    closed = "the guild bank closed",
    leaving = "you left the world",
    stopped = "you stopped it",
    guild = "this isn't the guild the plan was made for",
    tab = "you changed the tab the guild bank shows",
    mode = "the guild bank isn't showing its items",
    ["nav-timeout"] = "the guild bank didn't send a tab's items in time",
    ["nav-failed"] = "a tab couldn't be shown",
    rights = "your rank's rights in a tab changed",
    limit = "your rank's withdrawals from a tab for today are used up",
    cursor = "something else is on your cursor",
    ["cursor-changed"] = "your cursor changed while a move was under way",
    source = "a slot changed since the review",
    dest = "the destination changed since the review",
    protected = "an item is no longer allowed to move",
    blocked = "the game blocked an action",
    click = "the game wants a click for each move",
    timeout = "the game didn't answer in time",
    ["not-accepted"] = "the destination didn't take the item, so it was put back where it came from",
    mismatch = "the bank doesn't show what was expected",
    error = "something went wrong inside TwichUI",
    verify = "the final check didn't match the approved result",
}

-- why an operation can't be part of this run (shown in the review)
GR.NOT_INCLUDED = {
    depends = "It depends on work that is not included",
    ["source-changed"] = "The source isn't what the plan saw",
    ["source-short"] = "The source holds less than the plan needs",
    ["slot-taken"] = "The destination slot holds something else",
    ["dest-full"] = "The destination stack has no room",
    ["dest-gone"] = "The destination stack to merge into is gone",
    locked = "A slot is locked by the game",
    scope = "It isn't part of this action",
    more = "Too many moves for one run",
    ["tab-unread"] = "A tab it needs hasn't been read",
    ["tab-rights"] = "Your rank can't do this in a tab it needs",
}

---------------------------------------------------------------------------
-- The review
---------------------------------------------------------------------------
local function Fingerprint(rv)
    local p = { rv.mode, tostring(rv.guild), tostring(MI.Generation()), tostring(#rv.dropped), tostring(rv.planBlocked), tostring(rv.planUnknown) }
    for _, tab in ipairs(rv.tabs) do
        local t = rv.tabInfo[tab]
        p[#p + 1] = ("tab%d:%s:%s:%s"):format(tab, tostring(t.name), tostring(t.canDeposit), tostring(t.canWithdraw))
    end
    for _, tab in ipairs(rv.unread) do p[#p + 1] = "unread" .. tab end
    for _, o in ipairs(rv.ops) do
        p[#p + 1] = ("%s>%s %d x%d [%s/%s]"):format(Key(o.src), Key(o.dst), o.id, o.count,
            o.srcBefore and (o.srcBefore.count) or "-", o.dstBefore and (o.dstBefore.count) or "-")
    end
    for _, d in ipairs(rv.dropped) do p[#p + 1] = d.code .. ":" .. d.id .. ":" .. d.count end
    return table.concat(p, "|")
end

-- "tab 2 \"Cloth\"", "tabs 1 \"Gear\" and 2 \"Cloth\"", "tabs 1, 2, 3"
local function TabsText(tabs, names)
    local parts = {}
    for _, t in ipairs(tabs) do parts[#parts + 1] = names[t] and ("%d \"%s\""):format(t, names[t]) or tostring(t) end
    if #parts == 0 then return "no tab" end
    if #parts == 1 then return "tab " .. parts[1] end
    local lastPart = table.remove(parts)
    return "tabs " .. table.concat(parts, ", ") .. " and " .. lastPart
end
GR.TabsText = TabsText

-- The words of a review, for the confirmation: headline, and the lines under it.
local function Describe(rv)
    local lines = {}
    local items = {}
    for _, it in ipairs(rv.items) do items[#items + 1] = ("%s \195\151%d"):format(it.name, it.qty) end
    if #rv.itemsMore > 0 then items[#items + 1] = ("and %d more"):format(#rv.itemsMore) end
    local names = {}
    for tab, t in pairs(rv.tabInfo) do names[tab] = t.name end
    rv.tabsText = TabsText(rv.tabs, names)
    if rv.mode == "deposit" then
        rv.headline = ("Deposit %s from your bags into %s."):format(Plural(rv.moves, "move"), rv.tabsText)
    else
        rv.headline = ("Organize %s: %s."):format(rv.tabsText, Plural(rv.moves, "move"))
    end
    local extra = {}
    if rv.splits > 0 then extra[#extra + 1] = ("%d of them %s"):format(rv.splits, rv.splits == 1 and "splitting a stack" or "splitting stacks") end
    if rv.crossTab > 0 then extra[#extra + 1] = ("%d of them between tabs"):format(rv.crossTab) end
    lines[#lines + 1] = ("%d items in %s%s: %s."):format(rv.quantity, Plural(rv.moves, "move"),
        #extra > 0 and (", " .. table.concat(extra, ", ")) or "", table.concat(items, ", "))
    for _, d in ipairs(rv.dropped) do
        lines[#lines + 1] = ("Not included: %s \195\151%d \226\128\148 %s."):format(Name(d.id), d.count, d.text)
    end
    if #rv.unread > 0 then
        local un = {}
        for _, tab in ipairs(rv.unread) do un[#un + 1] = tostring(tab) end
        lines[#lines + 1] = ("Not read: tab%s %s. The bank can't be called organized while %s unread."):format(#un == 1 and "" or "s", table.concat(un, ", "), #un == 1 and "it is" or "they are")
    end
    if rv.planBlocked > 0 then lines[#lines + 1] = ("Blocked by the rules or the bank: %s (see Details)."):format(Plural(rv.planBlocked, "stack")) end
    if rv.planUnknown > 0 then lines[#lines + 1] = ("Can't be told yet: %s (see Details)."):format(Plural(rv.planUnknown, "stack")) end
    if rv.complete then
        lines[#lines + 1] = "Each move is checked in the game before the next. Stop ends it after the move in progress."
    else
        lines[#lines + 1] = ("Only these %s will be done. The rest stays as it is. Each move is checked in the game before the next."):format(Plural(rv.moves, "move"))
    end
    if rv.crossTab > 0 or #rv.tabs > 1 then
        lines[#lines + 1] = "The guild bank will show each tab in turn while this runs, and your own tab again at the end."
    end
    rv.lines = lines
end
GR.Describe = Describe

-- Builds the review for a mode ("deposit" or "organize" = the planner's "reorganize") from the SAVED rules and what the game
-- shows now, across every tab that has been read. opts.allowRun: made from inside a run (its refresh before the first move).
-- Returns the review: ok, or ok = false with refuse = { code, text }. Reads the bags and the snapshot; changes nothing.
local function BuildReview(mode, opts)
    mode = (mode == "reorganize" or mode == "organize") and "reorganize" or "deposit"
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.guildReview")
    local rv = { mode = mode, made = Now(), ops = {}, dropped = {}, items = {}, itemsMore = {}, tabs = {}, tabInfo = {}, unread = {},
        moves = 0, quantity = 0, splits = 0, crossTab = 0, planBlocked = 0, planUnknown = 0, home = ShownTab() }
    local function Refuse(code, text)
        rv.ok, rv.refuse = false, { code = code, text = text }
        if pt then R.Perf.Stop(pt) end
        return rv
    end
    if not MI.Enabled() then return Refuse("off", "Magic Inventory is off.") end
    if (run and not (opts and opts.allowRun)) or (MI.Run and MI.Run.Busy()) then return Refuse("busy", "Another transfer is in progress.") end
    if not BankOpen() then return Refuse("closed", "Open the guild bank first.") end
    if InCombat() then return Refuse("combat", "Wait until combat ends.") end
    if Cursor() ~= "empty" then return Refuse("cursor", "Put down what is on your cursor first.") end
    local mode0 = GB.Mode()
    if mode0 ~= nil and mode0 ~= "bank" then return Refuse("mode", "Show the guild bank's items (its Bank page) first.") end
    local guild = GuildNow()
    local snap = GB.Snapshot()
    if not guild or snap.guild ~= guild then return Refuse("guild", "The guild bank isn't this character's guild's, as far as the game says.") end
    rv.guild = guild

    -- which tabs can be worked with: read (shown, or read earlier in this visit and recently), viewable
    local ready = {}
    local anyReady = false
    for i = 1, snap.numTabs or 0 do
        local t = snap.tabs[i]
        if t and t.viewable == true then
            if GB.IsFresh(i) then ready[i] = true; anyReady = true else rv.unread[#rv.unread + 1] = i end
        end
    end
    if not anyReady then
        return Refuse("unread", "The guild bank's tabs haven't been read yet. Give it a moment, or show a tab.")
    end

    local plan = MI.CurrentGuildPlan(mode)
    local dz = plan.summary.design or {}
    rv.planBlocked, rv.planUnknown = (plan.summary.blocked or 0) + (dz.blocked or 0), (plan.summary.unknown or 0) + (dz.unknown or 0)
    rv.blockedItems = {}
    for _, a in ipairs(plan.design and plan.design.allocs or {}) do
        if (a.state == "blocked" or a.state == "unknown") and #rv.blockedItems < 12 then
            rv.blockedItems[#rv.blockedItems + 1] = { id = a.id, count = a.want, text = a.why or a.code, unknown = a.state == "unknown" }
        end
    end
    for _, u in ipairs(plan.untouched) do
        if (u.class == "blocked" or u.class == "unknown") and #rv.blockedItems < 12 then
            rv.blockedItems[#rv.blockedItems + 1] = { id = u.id, count = u.count, text = u.text, unknown = u.class == "unknown" }
        end
    end

    -- the model: the cells the moves touch, as the game shows them, changed by each move that can be done
    local cells = {}
    local function Cell(w)
        local k = Key(w)
        local v = cells[k]
        if v == nil then
            local c
            if w.kind == "bag" then c = BagCell(w.bag, w.slot)
            else
                local st = snap.tabs[w.tab]
                local s = st and st.slots and st.slots[w.slot]
                c = s and { id = s.id, count = s.count, locked = s.locked } or nil
            end
            v = c and { id = c.id, count = c.count, locked = c.locked } or false
            cells[k] = v
        end
        return v or nil, k
    end

    -- cells an excluded move would have changed, by the plan's number of the first such move: a LATER move on one of them builds
    -- on work that is not included and goes with it (an earlier one doesn't)
    local tainted = {}
    local function After(k, n) local t = tainted[k]; return t ~= nil and t < n end
    local function Taint(src, dst, n)
        for _, w in ipairs({ src, dst }) do
            local k = Key(w)
            if tainted[k] == nil or n < tainted[k] then tainted[k] = n end
        end
    end
    local function Exclude(o, src, dst, code, text)
        local why = (After(Key(src), o.n) or After(Key(dst), o.n)) and "depends" or code
        Taint(src, dst, o.n)
        rv.dropped[#rv.dropped + 1] = { n = o.n, id = o.id, count = o.count, code = why, text = (why == "depends" or not text) and (GR.NOT_INCLUDED[why] or why) or text }
    end
    local function TabProblem(w, needDeposit, needWithdraw)
        if w.kind ~= "guild" then return nil end
        local t = snap.tabs[w.tab]
        if not ready[w.tab] then return "tab-unread", ("Tab %d hasn't been read"):format(w.tab) end
        if t.viewable ~= true or (needDeposit and t.canDeposit ~= true) or (needWithdraw and t.canWithdraw ~= true) then
            return "tab-rights", ("Your rank can't %s tab %d"):format(needDeposit and "deposit in" or "take items out of", w.tab)
        end
        return nil
    end

    local candidates = {}
    for _, o in ipairs(plan.ops) do
        local src = o.from.kind == "bag" and { kind = "bag", bag = o.from.bag, slot = o.from.slot } or { kind = "guild", tab = o.from.tab, slot = o.from.slot }
        local dst = { kind = "guild", tab = o.to.tab, slot = o.to.slot }
        local code, text
        if o.status ~= "ok" then
            code, text = o.code or "blocked", o.why
        elseif (mode == "deposit" and src.kind ~= "bag") or (mode == "reorganize" and src.kind ~= "guild") then
            code, text = "scope", GR.NOT_INCLUDED.scope
        else
            code, text = TabProblem(dst, true, false)
            if not code then code, text = TabProblem(src, false, true) end
        end
        if code then
            Exclude(o, src, dst, code, text)
        elseif #candidates >= GR.MAX_MOVES then
            Exclude(o, src, dst, "more", GR.NOT_INCLUDED.more)
        else
            candidates[#candidates + 1] = { plan = o, src = src, dst = dst }
        end
    end

    -- replay what can be done, in the plan's order, on the cells as they are now: a move whose source or destination is not
    -- what the plan assumed (or depends on one that is excluded) is left out, with its dependents
    local totals = {}
    local touched = {}
    for _, c in ipairs(candidates) do
        local o = c.plan
        local srcC, sk = Cell(c.src)
        local dstC, dk = Cell(c.dst)
        local facts = MI.ItemFacts(o.id)
        local maxStack = math.max(1, facts and facts.maxStack or 1)
        local code
        if After(sk, o.n) or After(dk, o.n) then code = "depends"   -- it builds on work that is not included: never done without it
        elseif not srcC or srcC.id ~= o.id or not srcC.count then code = "source-changed"
        elseif srcC.count < o.count then code = "source-short"
        elseif srcC.locked or (dstC and dstC.locked) then code = "locked"
        elseif o.kind == "merge" and not dstC then code = "dest-gone"
        elseif dstC and o.kind ~= "merge" then code = "slot-taken"
        elseif dstC and (dstC.id ~= o.id or not dstC.count) then code = "slot-taken"
        elseif dstC and dstC.count + o.count > maxStack then code = "dest-full" end
        if code then
            Exclude(o, c.src, c.dst, code, GR.NOT_INCLUDED[code])
        else
            local op = { n = #rv.ops + 1, planN = o.n, kind = o.kind, id = o.id, count = o.count, src = c.src, dst = c.dst, ruleId = o.ruleId,
                srcBefore = { id = srcC.id, count = srcC.count }, dstBefore = dstC and { id = dstC.id, count = dstC.count } or nil }
            op.whole = o.count == srcC.count
            op.cross = Cross(op)
            if not op.whole then rv.splits = rv.splits + 1 end
            if op.cross then rv.crossTab = rv.crossTab + 1 end
            srcC.count = srcC.count - o.count
            op.srcAfter = srcC.count > 0 and { id = o.id, count = srcC.count } or nil
            if srcC.count <= 0 then cells[sk] = false end
            if dstC then dstC.count = dstC.count + o.count
            else cells[dk] = { id = o.id, count = o.count }; dstC = cells[dk] end
            op.dstAfter = { id = o.id, count = dstC.count }
            rv.ops[#rv.ops + 1] = op
            rv.moves, rv.quantity = rv.moves + 1, rv.quantity + o.count
            totals[o.id] = (totals[o.id] or 0) + o.count
            for _, w in ipairs({ op.src, op.dst }) do
                if w.kind == "guild" and not touched[w.tab] then touched[w.tab] = true; rv.tabs[#rv.tabs + 1] = w.tab end
            end
        end
    end
    table.sort(rv.tabs)
    for _, tab in ipairs(rv.tabs) do
        local info = TabInfo(tab) or {}
        local st = snap.tabs[tab]
        rv.tabInfo[tab] = { name = st and st.name or info.name, canDeposit = st and st.canDeposit, canWithdraw = st and st.canWithdraw }
    end

    -- the approved end state: every cell a move touches, as it should read when the run is done
    rv.endState = {}
    local seen = {}
    for _, o in ipairs(rv.ops) do
        for _, w in ipairs({ o.src, o.dst }) do
            local k = Key(w)
            if not seen[k] then
                seen[k] = true
                local c = cells[k]
                rv.endState[#rv.endState + 1] = { where = w, want = c and { id = c.id, count = c.count } or nil }
            end
        end
    end

    local ids = {}
    for id in pairs(totals) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) if totals[a] ~= totals[b] then return totals[a] > totals[b] end return a < b end)
    for i, id in ipairs(ids) do
        if i <= 6 then rv.items[#rv.items + 1] = { id = id, name = Name(id), qty = totals[id] } else rv.itemsMore[#rv.itemsMore + 1] = id end
    end

    -- "completed" later means the whole approved plan was done: a plan that leaves work out can only be "partial". A tab that was
    -- not read and that no rule needs doesn't change that, but it is always said (the bank is not called organized then)
    rv.complete = #rv.dropped == 0 and rv.planBlocked == 0 and rv.planUnknown == 0
    if rv.moves == 0 then
        local text = "Nothing to do for this action."
        if #rv.dropped > 0 then text = text .. (" %s can't be done as things stand (see Details)."):format(Plural(#rv.dropped, "move")) end
        if #rv.unread > 0 then text = text .. (" %s not read yet."):format(Plural(#rv.unread, "tab") .. (#rv.unread == 1 and " is" or " are")) end
        rv.fingerprint = Fingerprint(rv)
        Describe(rv)
        return Refuse("nothing", text)
    end
    rv.ok = true
    rv.fingerprint = Fingerprint(rv)
    Describe(rv)
    if pt then R.Perf.Stop(pt) end
    return rv
end

function GR.Review(mode) return BuildReview(mode) end

---------------------------------------------------------------------------
-- The run
---------------------------------------------------------------------------
local Check, Halt

local function Listen(wanted)
    for event, fn in pairs(active) do
        if not wanted then R:Off(event, fn); active[event] = nil end
    end
end

local function Later(r, delay)
    C_Timer.After(delay, function()
        if run == r and r.state == "running" then Check(r, "timer") end
    end)
end

-- Events are reasons to read again, nothing more; a burst is one read.
local function Wake(r)
    if not r or r ~= run or r.wakeQueued then return end
    r.wakeQueued = true
    C_Timer.After(0, function()
        r.wakeQueued = false
        if run == r and r.state == "running" then Check(r, "event") end
    end)
end

local function Counts(r)
    local c = { confirmed = 0, uncertain = 0, failed = 0, pending = 0, active = 0, total = #r.ops }
    for _, o in ipairs(r.ops) do
        if o.status == "confirmed" then c.confirmed = c.confirmed + 1
        elseif o.status == "uncertain" then c.uncertain = c.uncertain + 1
        elseif o.status == "failed" then c.failed = c.failed + 1
        elseif o.status == "active" then c.active = c.active + 1
        else c.pending = c.pending + 1 end
    end
    return c
end

function GR.Progress()
    local r = run
    if not r then return nil end
    local c = Counts(r)
    local op = r.ops[r.index]
    return { confirmed = c.confirmed, total = c.total, waiting = (op ~= nil and op.phase ~= nil and not r.needClick) or r.nav ~= nil,
        stopping = r.stop ~= nil, needClick = r.needClick == true, mode = r.mode, tabs = r.review.tabs, tabsText = r.review.tabsText,
        stage = r.stage, reading = r.nav and r.nav.tab or nil,
        current = op and { id = op.id, count = op.count, tab = op.dst.tab } or nil }
end

local function OpLine(o)
    local state = ({ confirmed = "confirmed", uncertain = "uncertain", failed = "not done", active = "in progress", pending = "not started" })[o.status] or o.status
    return ("%s \195\151%d, %s to %s: %s%s"):format(Name(o.id), o.count, Where(o.src), Where(o.dst), state, o.note and (" (" .. o.note .. ")") or "")
end

-- Marks for the grid: "uncertain", "active", "pending" or "done" for a guild bank slot touched by the run in progress or the last one.
local MARK_RANK = { uncertain = 4, active = 3, pending = 2, done = 1 }
function GR.SlotMark(tab, slot)
    local list = run and run.ops or (last and last.ops)
    if not list then return nil end
    local best
    for _, o in ipairs(list) do
        for _, w in ipairs({ o.src, o.dst }) do
            if w.kind == "guild" and w.tab == tab and w.slot == slot then
                local m = (o.status == "confirmed" and "done") or (o.status == "active" and "active")
                    or (o.status == "uncertain" and "uncertain") or "pending"
                if not best or MARK_RANK[m] > MARK_RANK[best] then best = m end
            end
        end
    end
    return best
end

-- What the game shows for a move that could not be confirmed, in words (it goes into the move's note, under Details)
local function CellText(c, known)
    if not known then return "not readable now" end
    if not c then return "empty" end
    return ("%s \195\151%s%s"):format(c.id and Name(c.id) or "an item", tostring(c.count or "?"), c.locked and ", locked" or "")
end
local function Saw(o, r)
    local cur = Cursor()
    local s, d = Read(o.src), Read(o.dst)
    local bits = { ("cursor %s"):format(cur == "empty" and "empty" or (cur == "item" and "holds an item" or "holds something")),
        ("source %s"):format(CellText(s, Known(o.src))), ("destination %s"):format(CellText(d, Known(o.dst))) }
    if o.trace then bits[#bits + 1] = o.trace end
    if o.placedAt then bits[#bits + 1] = ("%.1f s after placing"):format(Now() - o.placedAt) end
    if r.lastError then bits[#bits + 1] = "the game said: " .. r.lastError end
    return "saw: " .. table.concat(bits, "; ")
end

-- Ends the run: reads what is left in flight once more, decides the outcome and keeps the result.
-- cursorLeft is set when an item of this run is still on the cursor.
local function Conclude(r, code, detail)
    if r.state ~= "running" then return end
    local rv = r.review
    -- a move still in flight is read one last time: done, not moved, or uncertain (never repeated). A slot of a tab that is not
    -- shown and read cannot be read at all, so a move that depends on one is uncertain, not "done" and not "not moved".
    for _, o in ipairs(r.ops) do
        if o.phase then
            local s, d = Read(o.src), Read(o.dst)
            local sk, dk = Known(o.src), Known(o.dst)
            local cur, cid = Cursor()
            local calm = cur == "empty" and not (sk and s and s.locked) and not (dk and d and d.locked)
            local srcBefore = sk and Is(s, o.srcBefore)
            local before = srcBefore and (not dk or Is(d, o.dstBefore))
            if o.status == "active" then
                if o.phase == "verifying" then
                    if calm and sk and Is(s, o.srcAfter) then
                        o.status, o.phase = "confirmed", nil
                    else
                        o.status, o.note = "uncertain", "it was placed, but the source tab wasn't read again"
                    end
                elseif o.phase == "placing" then
                    if not o.cross and calm and sk and dk and Is(s, o.srcAfter) and Is(d, o.dstAfter) then
                        o.status, o.phase = "confirmed", nil
                    else
                        o.status = "uncertain"
                        if not o.note then o.note = (o.cross and calm and dk and Is(d, o.dstAfter)) and "it was placed, but the source tab wasn't read again" or "the game hasn't shown the result; it may still happen" end
                    end
                elseif o.phase == "restoring" then
                    if calm and srcBefore then
                        o.status, o.phase, o.note = "failed", nil, "put back where it came from"
                    else
                        o.status = "uncertain"
                        if not o.note then o.note = "it was not confirmed back in its slot" end
                    end
                elseif calm and before then
                    o.status, o.phase, o.note = "failed", nil, "not moved"
                else
                    o.status = "uncertain"
                    if not o.note then o.note = "the game hasn't shown the result; it may still happen" end
                end
            end
            if o.phase and o.status == "uncertain" then
                o.note = (o.note and (o.note .. " ") or "") .. "(" .. Saw(o, r) .. ")"
                -- judged uncertain: is the run's item stranded on the cursor?
                if cur == "item" and cid == o.id then
                    r.cursorLeft = r.cursorLeft or { id = o.id, where = o.src }
                    o.note = "it is on your cursor"
                end
                o.phase = nil
            end
        end
    end
    local c = Counts(r)
    local finished = c.confirmed == c.total
    local outcome
    local verifyLines
    if c.uncertain > 0 or r.cursorLeft then
        outcome = "review"
    elseif finished and code then
        outcome = "review"   -- every move was confirmed, but the final check could not be made
    elseif finished then
        -- the approved result: every cell the run touched, as read again once its tab was shown (bags read directly)
        verifyLines = {}
        for _, e in ipairs(rv.endState) do
            local read = r.finalRead and r.finalRead[Key(e.where)]
            local cell
            if read then cell = read.cell else cell = Read(e.where) end
            if not Is(cell, e.want) or (cell and cell.locked) then
                verifyLines[#verifyLines + 1] = ("%s holds %s, expected %s"):format(Where(e.where),
                    cell and ((cell.id and Name(cell.id) or "an item") .. " \195\151" .. tostring(cell.count or "?")) or "nothing",
                    e.want and (Name(e.want.id) .. " \195\151" .. e.want.count) or "nothing")
            end
        end
        if #verifyLines > 0 then outcome, code = "review", "verify"
        elseif rv.complete then outcome = "completed"
        else outcome = "partial" end
    elseif code == "error" or code == "mismatch" or code == "timeout" or code == "cursor-changed" then
        outcome = "review"
    else
        outcome = "stopped"
    end
    local res = { outcome = outcome, code = code, reason = code and (GR.WHY[code] or code) or nil, detail = detail,
        mode = r.mode, tabs = rv.tabs, tabsText = rv.tabsText, guild = r.guild, confirmed = c.confirmed, total = c.total,
        notStarted = c.pending, uncertain = c.uncertain, failed = c.failed, quantity = 0,
        notIncluded = #rv.dropped, unreadTabs = rv.unread, blockedStacks = rv.planBlocked, unknownStacks = rv.planUnknown,
        cursor = r.cursorLeft, verify = verifyLines, finishedAt = Now(), ops = {}, lines = {}, error = r.lastError, fresh = r.changed }
    for _, o in ipairs(r.ops) do
        if o.status == "confirmed" then res.quantity = res.quantity + o.count end
        res.ops[#res.ops + 1] = { src = o.src, dst = o.dst, id = o.id, count = o.count, status = o.status, note = o.note, cross = o.cross }
    end
    local L = res.lines
    for i, o in ipairs(r.ops) do
        if i <= 40 then L[#L + 1] = OpLine(o) elseif i == 41 then L[#L + 1] = ("... and %s more"):format(#r.ops - 40) end
    end
    for _, d in ipairs(rv.dropped) do L[#L + 1] = ("Not included: %s \195\151%d \226\128\148 %s"):format(Name(d.id), d.count, d.text) end
    for _, tab in ipairs(rv.unread) do L[#L + 1] = ("Not read: tab %d (nothing was done there, and the bank can't be called organized)"):format(tab) end
    for _, v in ipairs(verifyLines or {}) do L[#L + 1] = "Final check: " .. v end
    if r.cursorLeft then
        L[#L + 1] = ("Your cursor holds %s from this run. Put it back in %s."):format(Name(r.cursorLeft.id), Where(r.cursorLeft.where))
    end
    if r.lastError then L[#L + 1] = "The game said: " .. r.lastError end
    r.state = "finished"
    last = res
    run = nil
    Listen(false)
    Notify("done")
end

Halt = function(r, code, detail) Conclude(r, code, detail) end

-- the destination judged from a fresh read once its tab is shown (placing onto a changed slot could swap)
-- an operation's cells right now against what the review expects; "done", "wait" (still under way), or "bad" and why
local function Reconcile(op)
    local cur, cid = Cursor()
    local d, dk = Read(op.dst), Known(op.dst)
    local s, sk = Read(op.src), Known(op.src)
    if not dk then return "wait", "pending" end
    local dDone, dPre = Is(d, op.dstAfter), Is(d, op.dstBefore)
    if op.cross then
        -- the source's tab is not shown: the destination is judged now, the source after that tab is shown again ("verifying")
        if dDone and cur == "empty" and not (d and d.locked) then return "done" end
        if cur == "item" and cid == op.id then return "wait", "holding" end
        if cur ~= "empty" then return "bad", "cursor-changed" end
        if dDone or dPre then return "wait", "pending" end
        return "bad", "mismatch"
    end
    local locked = (s and s.locked) or (d and d.locked)
    local sDone, sPre = Is(s, op.srcAfter), Is(s, op.srcBefore)
    if sk and sDone and dDone and cur == "empty" and not locked then return "done" end
    if cur == "item" and cid == op.id then return "wait", "holding" end
    if cur ~= "empty" then return "bad", "cursor-changed" end
    if sk and (sDone or sPre) and (dDone or dPre) then return "wait", "pending" end
    return "bad", "mismatch"
end

local function PickTab(op) return op.src.kind == "guild" and op.src.tab or op.dst.tab end

-- the tab's name and the rank's rights are still the reviewed ones; nil, or "rights"
local function RightsProblem(r, w, needDeposit, needWithdraw)
    local info = TabInfo(w.tab)
    if not info or info.name ~= r.tabNames[w.tab] or info.viewable ~= true then return "rights" end
    if needDeposit and info.canDeposit ~= true then return "rights" end
    if needWithdraw and info.canWithdraw ~= true then return "rights" end
    return nil, info
end

-- Everything that must hold before a move is started (its source tab is shown and read). Returns nil, or a reason code.
local function Boundary(r, op)
    if not MI.Enabled() then return "off" end
    if InCombat() then return "combat" end
    if r.generation ~= MI.Generation() then return "changed" end
    if not BankOpen() then return "closed" end
    if GuildNow() ~= r.guild then return "guild" end
    local mode = GB.Mode()
    if mode ~= nil and mode ~= "bank" then return "mode" end
    if ShownTab() ~= PickTab(op) then return "tab" end
    if RightsProblem(r, op.dst, true, false) then return "rights" end
    if op.src.kind == "guild" then
        local bad, info = RightsProblem(r, op.src, false, true)
        if bad then return "rights" end
        if info.remaining and info.remaining >= 0 and info.remaining < 1 then return "limit" end
    end
    if Cursor() ~= "empty" then return "cursor" end
    local s, d = Read(op.src), Read(op.dst)
    if not Is(s, op.srcBefore) or (s and s.locked) then return "source" end
    -- a destination in another tab cannot be read from here: it is read after that tab is shown, before the item is placed
    if Known(op.dst) and (not Is(d, op.dstBefore) or (d and d.locked)) then return "dest" end
    if op.src.kind == "bag" then
        -- the bag stack is judged again, as for any deposit
        local rule = MI.Rule(op.ruleId)
        local stack = MI.ReadSlot(op.src.bag, op.src.slot)
        if not rule or not stack or MI.IsNever(op.id) then return "protected", "never" end
        local problem = MI.StackProblem(stack, "guild", rule)
        if problem then return "protected", problem end
    end
    return nil
end

-- The guild, bank page and shown tab must still be what this run asked for: a tab shown that it did not ask for is the player's.
local function Guards(r)
    if not BankOpen() then return "closed" end
    if GuildNow() ~= r.guild then return "guild" end
    local mode = GB.Mode()
    if mode ~= nil and mode ~= "bank" then return "mode" end
    local shown = ShownTab()
    if shown ~= r.expect and not (r.nav and shown == r.nav.tab) then return "tab" end
    return nil
end

-- Makes sure a tab is shown and its items were sent after it was shown. true: it is. false: waiting (the game was asked, a timer
-- and the bank's events look again). nil, why: it can't be (a late answer is asked for once more, then given up).
local function Need(r, tab)
    local nav = r.nav
    if nav and nav.tab ~= tab then r.nav = nil; nav = nil end
    if nav then
        if GB.IsLive(tab) then r.nav, r.expect = nil, tab; return true end
        if Now() >= nav.deadline then
            if nav.tries < GR.NAV_TRIES then
                nav.tries, nav.deadline = nav.tries + 1, Now() + GR.WAIT
                local ok = GB.Show(tab)
                if not ok then r.nav = nil; return nil, "nav-failed" end
                for _, d in ipairs(GR.CHECKS) do Later(r, d) end
                Later(r, GR.WAIT + 0.05)
                return false
            end
            r.nav, r.expect = nil, tab   -- the tab is still the one shown, and it was this run that showed it
            return nil, "nav-timeout"
        end
        return false
    end
    if ShownTab() == tab and GB.IsLive(tab) then r.expect = tab; return true end
    local ok, why = GB.Show(tab)
    if not ok then return nil, why == "mode" and "mode" or "nav-failed" end
    r.nav = { tab = tab, deadline = Now() + GR.WAIT, tries = 1 }
    for _, d in ipairs(GR.CHECKS) do Later(r, d) end
    Later(r, GR.WAIT + 0.05)
    if GB.IsLive(tab) then r.nav, r.expect = nil, tab; return true end
    return false
end

-- Reads a tab again WITHOUT showing it (GB.Query: the player's tab stays where it is), for the refresh before the first move. Like Need:
-- true when it is read, false while waiting, nil + why when it can't be. When the game gives no answer to the query the tab is shown instead.
local function NeedRead(r, tab)
    if GB.IsLive(tab) then return Need(r, tab) end
    local q = r.query
    if q and q.tab ~= tab then GB.QueryCancel(); r.query, q = nil, nil end
    if q then
        if GB.QueryDone(tab) then r.query = nil; return true end
        if Now() >= q.deadline then
            if q.tries < GR.NAV_TRIES then
                q.tries, q.deadline = q.tries + 1, Now() + GR.WAIT
                GB.Query(tab)
                for _, d in ipairs(GR.CHECKS) do Later(r, d) end
                Later(r, GR.WAIT + 0.05)
                return false
            end
            GB.QueryCancel()
            r.query = nil
            return Need(r, tab)      -- the last resort: show it
        end
        Later(r, GB.QUERY_DWELL + 0.05)
        return false
    end
    if not GB.CanQuery() then return Need(r, tab) end
    local ok = GB.Query(tab)
    if not ok then return Need(r, tab) end
    r.query = { tab = tab, deadline = Now() + GR.WAIT, tries = 1 }
    for _, d in ipairs(GR.CHECKS) do Later(r, d) end
    Later(r, GR.WAIT + 0.05)
    Later(r, GB.QUERY_DWELL + 0.55)
    return false
end

local function Dispatch(r, op)
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.guildRun")
    op.status, op.startedAt = "active", Now()
    op.deadline = op.startedAt + GR.WAIT
    r.dispatched = r.dispatched + 1
    for _, d in ipairs(GR.CHECKS) do Later(r, d) end
    Later(r, GR.WAIT + 0.05)
    if op.whole then
        op.phase = "picking"
        CallPickup(op.src)
    else
        op.phase = "splitting"
        CallSplit(op.src, op.count)
    end
    if pt then R.Perf.Stop(pt) end
end

local function Place(r, op)
    op.phase = "placing"
    op.deadline = Now() + GR.WAIT
    for _, d in ipairs(GR.CHECKS) do Later(r, d) end
    Later(r, GR.WAIT + 0.05)
    op.placedAt = Now()
    CallPickup(op.dst)
    op.trace = ("right after the place call the cursor was %s"):format(Cursor() == "empty" and "empty" or "still holding it")
end

-- The cursor still holds this move's item and the destination didn't take it (or couldn't be shown): put it back where it came
-- from, but only when that slot can safely receive it (its tab is shown again first). Returns true when a restore was started.
local function Restore(r, op, code)
    r.restoreFor = code
    local cur, cid = Cursor()
    if cur ~= "item" or cid ~= op.id or not BankOpen() then return false end
    op.phase, op.restoreSent = "restoring", nil
    op.deadline = Now() + GR.WAIT
    Later(r, GR.CHECKS[1]); Later(r, GR.WAIT + 0.05)
    return true
end

local function Confirm(r, op)
    op.status, op.phase = "confirmed", nil
    if (op.tries or 1) > 1 then op.note = "confirmed on the second try" end
    r.index = r.index + 1
    r.notBefore = Now() + GR.GAP
    Notify("progress")
end

-- True when a fresh read shows this move did NOT start: nothing on the cursor, the source and the destination (both readable
-- now) exactly as reviewed and unlocked. Only then may it be handed to the game once more (after GR.SETTLE and a full
-- revalidation). A move that might have landed, or that sits in a tab that can't be read now, is never repeated.
local function Untouched(op)
    if Cursor() ~= "empty" then return false end
    if not (Known(op.src) and Known(op.dst)) then return false end
    local s, d = Read(op.src), Read(op.dst)
    if not Is(s, op.srcBefore) or (s and s.locked) then return false end
    if not Is(d, op.dstBefore) or (d and d.locked) then return false end
    return true
end

-- The game ignored the move without a word. Back to a boundary, to try again after a pause (once). Returns true when scheduled.
local function Retry(r, op)
    if (op.tries or 1) >= GR.TRIES or r.stop or not Untouched(op) then return false end
    op.tries = (op.tries or 1) + 1
    op.status, op.phase, op.note = "pending", nil, nil
    r.blockedSeen = nil
    r.notBefore = Now() + GR.SETTLE
    Later(r, GR.SETTLE + 0.05)
    return true
end

local function StepOps(r, op)
    local now = Now()
    if not op.phase then
        -- a boundary between moves
        if r.stop then return Halt(r, r.stop) end
        local ok, why = Need(r, PickTab(op))
        if ok == nil then return Halt(r, why) end
        if ok == false then return "wait" end
        -- paced: the game drops calls that come too fast after the last move (and after one it did not start)
        if r.notBefore and now < r.notBefore and not r.clicking then
            Later(r, r.notBefore - now + 0.02)
            return "wait"
        end
        if r.needClick and not r.clicking then Notify("click"); return "wait" end
        local bad, why2 = Boundary(r, op)
        if bad then
            if (op.tries or 1) > 1 then
                -- the first try may have landed after all: it is not assumed either way
                op.status, op.note = "uncertain", "the first try did not show, and the bank changed before the second; it may have happened"
            end
            return Halt(r, bad, why2)
        end
        r.clicking, r.blockedSeen = nil, nil
        Dispatch(r, op)
    elseif op.phase == "splitting" or op.phase == "picking" then
        local cur, cid = Cursor()
        if cur == "item" and cid == op.id then
            op.phase = "holding"
        elseif cur ~= "empty" then
            return Halt(r, "cursor-changed")
        elseif r.blockedSeen then
            -- the game refused the call and nothing happened: from then on each move needs the player's click
            op.phase, op.status, r.blockedSeen = nil, "pending", nil
            if r.clickAttempt then return Halt(r, "blocked") end
            r.needClick = true
            Notify("click")
            return "wait"
        elseif now >= op.deadline then
            if Retry(r, op) then return "wait" end
            op.status, op.note = "uncertain", "the game didn't pick it up in time"
            return Halt(r, "timeout")
        else
            return "wait"
        end
    elseif op.phase == "holding" then
        local cur, cid = Cursor()
        if not (cur == "item" and cid == op.id) then return Halt(r, "cursor-changed") end
        -- the destination's tab: shown (the item stays on the cursor) and read before anything is placed
        local ok, why = Need(r, op.dst.tab)
        if ok == nil then
            if Restore(r, op, why) then return end
            op.status, op.note = "uncertain", "it is on your cursor"
            return Halt(r, why)
        end
        if ok == false then return "wait" end
        local bad = RightsProblem(r, op.dst, true, false)
        local d = Read(op.dst)
        if bad or not Is(d, op.dstBefore) or (d and d.locked) then
            if Restore(r, op, bad or "dest") then return end
            return Halt(r, bad or "dest")
        end
        if r.needClick and not r.clicking then return "wait" end   -- waiting for the player's click to place it
        r.clicking, r.blockedSeen = nil, nil
        Place(r, op)
    elseif op.phase == "placing" then
        local res, why = Reconcile(op)
        if res == "done" then
            r.clickAttempt = nil
            if op.cross then
                -- the destination holds it; the source's tab is shown and read again before this move counts
                op.phase, op.deadline = "verifying", now + GR.WAIT
                for _, d in ipairs(GR.CHECKS) do Later(r, d) end
                Later(r, GR.WAIT + 0.05)
                return
            end
            Confirm(r, op)
            Wake(r)   -- yield before the next move
            return "wait"
        elseif res == "bad" then
            op.status, op.note = "uncertain", (why == "mismatch") and "the slots don't show what was expected" or "the cursor changed"
            return Halt(r, why)
        elseif r.blockedSeen and why == "holding" then
            -- the place was refused and the item is still on the cursor: it waits there for the player's click
            r.blockedSeen = nil
            if r.clickAttempt then return Halt(r, "blocked") end
            op.phase, r.needClick = "holding", true
            Notify("click")
            return "wait"
        elseif now >= op.deadline then
            if why == "holding" and Restore(r, op, "not-accepted") then return end
            if why == "pending" and Retry(r, op) then return "wait" end
            op.status = "uncertain"
            op.note = why == "holding" and "the destination didn't take it" or "the game hasn't shown the result; it may still happen"
            return Halt(r, "timeout")
        else
            return "wait"
        end
    elseif op.phase == "verifying" then
        local ok, why = Need(r, op.src.tab)
        if ok == nil then
            op.status, op.note = "uncertain", "it was placed, but the source tab couldn't be read again"
            return Halt(r, why)
        end
        if ok == false then return "wait" end
        local s = Read(op.src)
        local cur = Cursor()
        if cur == "empty" and Is(s, op.srcAfter) and not (s and s.locked) then
            Confirm(r, op)
            Wake(r)
            return "wait"
        elseif now >= op.deadline then
            op.status = "uncertain"
            op.note = "the source doesn't show the move yet; it may still happen"
            return Halt(r, "timeout")
        elseif cur ~= "empty" then
            op.status, op.note = "uncertain", "the cursor changed"
            return Halt(r, "cursor-changed")
        elseif not (Is(s, op.srcAfter) or Is(s, op.srcBefore)) then
            op.status, op.note = "uncertain", "the source doesn't show what was expected"
            return Halt(r, "mismatch")
        else
            return "wait"
        end
    elseif op.phase == "restoring" then
        if not op.restoreSent then
            if op.src.kind == "guild" then
                local ok, why = Need(r, op.src.tab)
                if ok == nil then
                    op.status, op.note = "uncertain", "it is on your cursor, and its tab couldn't be shown"
                    return Halt(r, why)
                end
                if ok == false then return "wait" end
            end
            local cur, cid = Cursor()
            if not (cur == "item" and cid == op.id) then return Halt(r, "cursor-changed") end
            local s = Read(op.src)
            if s and s.id ~= op.id then
                op.status, op.note = "uncertain", "its slot holds something else now; it is on your cursor"
                return Halt(r, r.restoreFor or "dest")
            end
            op.restoreSent, op.deadline = true, Now() + GR.WAIT
            Later(r, GR.CHECKS[1]); Later(r, GR.WAIT + 0.05)
            CallPickup(op.src)
            return "wait"
        end
        local s, d = Read(op.src), Read(op.dst)
        local sk, dk = Known(op.src), Known(op.dst)
        local locked = (sk and s and s.locked) or (dk and d and d.locked)
        if Cursor() == "empty" and sk and Is(s, op.srcBefore) and (not dk or Is(d, op.dstBefore)) and not locked then
            op.status, op.phase, op.note = "failed", nil, "put back where it came from"
            return Halt(r, r.restoreFor or "dest")
        elseif now >= op.deadline then
            op.status, op.note = "uncertain", "it was not confirmed back in its slot"
            return Halt(r, "timeout")
        else
            return "wait"
        end
    else
        return Halt(r, "error")
    end
end

-- One evaluation of the run: reads the game and does at most what the state allows, then waits for the next event or timer.
local function Step(r)
    local guard = 0
    while run == r and r.state == "running" do
        local bad = Guards(r)
        if bad then return Halt(r, bad) end
        if r.stage == "refresh" then
            -- tabs read a while ago are read again first; if anything the approval rests on changed, nothing is done
            if r.stop then return Halt(r, r.stop) end
            local tab = r.refresh[r.refreshI]
            if tab then
                local ok, why = NeedRead(r, tab)
                if ok == nil then return Halt(r, why) end
                if not ok then return end
                r.refreshI = r.refreshI + 1
            else
                local fresh = BuildReview(r.mode, { allowRun = true })
                if not fresh.ok or fresh.fingerprint ~= r.review.fingerprint then
                    r.changed = fresh.ok and fresh or nil
                    return Halt(r, "stale")
                end
                r.stage = "ops"
            end
        elseif r.stage == "final" then
            -- stopped (or the feature turned off) with every move done: the final check is not started, and says so
            if r.stop then return Halt(r, r.stop) end
            if not r.finalTabs then
                r.finalTabs, r.finalRead, r.finalI = {}, {}, 1
                local seen = {}
                for _, e in ipairs(r.review.endState) do
                    if e.where.kind == "guild" and not seen[e.where.tab] then seen[e.where.tab] = true; r.finalTabs[#r.finalTabs + 1] = e.where.tab end
                end
                local shown = ShownTab()
                table.sort(r.finalTabs, function(a, b)
                    if (a == shown) ~= (b == shown) then return a == shown end
                    return a < b
                end)
            end
            local tab = r.finalTabs[r.finalI]
            if tab then
                local ok, why = Need(r, tab)
                if ok == nil then return Halt(r, why) end
                if not ok then return end
                for _, e in ipairs(r.review.endState) do
                    if e.where.kind == "guild" and e.where.tab == tab then r.finalRead[Key(e.where)] = { cell = Read(e.where) } end
                end
                r.finalI = r.finalI + 1
            else
                -- the player's own tab again, as it was when the run started (best effort: it is not part of the result)
                if r.home and not r.homeDone and ShownTab() ~= r.home and not r.stop then
                    local ok = Need(r, r.home)
                    if ok == false then return end
                end
                r.homeDone = true
                return Halt(r, nil)
            end
        else
            local op = r.ops[r.index]
            if not op then
                r.stage = "final"
            else
                -- "wait": nothing more can be done until the game answers; nothing returned: the phase moved on, look again at once
                if StepOps(r, op) == "wait" then return end
            end
        end
        guard = guard + 1
        if guard > 200 then return Halt(r, "error") end
    end
end

Check = function(r, why)
    if r ~= run or r.state ~= "running" then return end
    if r.inCall then r.again = true; return end
    r.inCall = true
    local guard = 0
    repeat
        r.again = false
        guard = guard + 1
        local ok, err = pcall(Step, r)
        if not ok then
            r.inCall = false
            R.Fault("magic inventory guild run", err)
            if run == r then
                for _, o in ipairs(r.ops) do if o.status == "active" then o.status = "uncertain"; o.note = "TwichUI hit an error" end end
                Halt(r, "error")
            end
            return
        end
    until not r.again or run ~= r or guard >= 5
    r.inCall = false
end

-- The player's click on Continue after the game wanted a click for a move: one move per click.
function GR.Continue()
    local r = run
    if not r or not r.needClick then return false end
    r.clicking, r.clickAttempt = true, true
    Check(r, "click")
    return true
end

-- Stop at the next safe boundary. A move already handed to the game is not undone; it is waited for.
function GR.Stop(code)
    local r = run
    if not r then return false end
    r.stop = r.stop or code or "stopped"
    Notify("stopping")
    Check(r, "stop")
    return true
end

---------------------------------------------------------------------------
-- Starting: the confirmation of a review
---------------------------------------------------------------------------
-- rv: a review from GR.Review. Fails (and says why) unless the review is still exactly what the game and the saved rules say.
-- Tabs that were read a while ago are read again first (the run's first step, see Step): if the plan is no longer the one
-- reviewed, the run ends with "stale" before anything moves and the result carries the new review to read and confirm.
-- Returns true, or false, code, sentence (and the new review when the plan changed).
function GR.Start(rv)
    if run then return false, "busy", "A guild bank run is already in progress." end
    if type(rv) ~= "table" or not rv.ok then return false, "stale", "Review again first." end
    if rv.used then return false, "used", "That review was already used. Review again." end
    rv.used = true
    if Now() - rv.made > GR.CONFIRM_AGE then return false, "old", "That review is too old. Review again." end
    local fresh = BuildReview(rv.mode)
    if not fresh.ok then return false, fresh.refuse.code, fresh.refuse.text, fresh end
    local refresh = {}
    for _, tab in ipairs(rv.tabs) do
        if not GB.IsLive(tab) and (GB.Age(tab) or math.huge) > GR.START_AGE then refresh[#refresh + 1] = tab end
    end
    if #refresh == 0 and fresh.fingerprint ~= rv.fingerprint then
        return false, "changed", "The guild bank, your bags or your rules changed since the review. Review again.", fresh
    end
    serial = serial + 1
    local shown = ShownTab()
    local r = { id = serial, mode = rv.mode, guild = rv.guild, generation = MI.Generation(), review = rv, ops = {}, index = 1,
        state = "running", dispatched = 0, startedAt = Now(), stage = #refresh > 0 and "refresh" or "ops", refresh = refresh, refreshI = 1,
        home = shown, expect = shown, tabNames = {} }
    for tab, t in pairs(rv.tabInfo) do r.tabNames[tab] = t.name end
    for i, o in ipairs(rv.ops) do
        r.ops[i] = { n = i, kind = o.kind, id = o.id, count = o.count, src = o.src, dst = o.dst, ruleId = o.ruleId, whole = o.whole, cross = o.cross,
            srcBefore = o.srcBefore, dstBefore = o.dstBefore, srcAfter = o.srcAfter, dstAfter = o.dstAfter, status = "pending" }
    end
    last = nil
    run = r
    local function On(event, fn) active[event] = fn; R:On(event, fn) end
    local function Reread() Wake(run) end
    On("GUILDBANKBAGSLOTS_CHANGED", Reread)
    On("GUILDBANK_ITEM_LOCK_CHANGED", Reread)
    On("GUILDBANK_UPDATE_TABS", Reread)
    On("BAG_UPDATE_DELAYED", Reread)
    On("CURSOR_CHANGED", Reread)
    On("GUILDBANKFRAME_CLOSED", function() if run then Halt(run, "closed") end end)
    On("PLAYER_LEAVING_WORLD", function() if run then Halt(run, "leaving") end end)
    On("PLAYER_REGEN_DISABLED", function() if run then run.stop = run.stop or "combat"; Wake(run) end end)
    On("UI_ERROR_MESSAGE", function(_, message)
        local text = Plain(message)
        if run and type(text) == "string" then run.lastError = text:sub(1, 120) end
    end)
    local function Blocked(addon)
        if Plain(addon) ~= R.ADDON or not run then return end
        run.blockedSeen = true
        Wake(run)
    end
    On("ADDON_ACTION_BLOCKED", Blocked)
    On("ADDON_ACTION_FORBIDDEN", Blocked)
    Notify("start")
    Check(r, "start")
    return true
end

-- The feature was turned off (Run.lua's MI.Refresh), or the rules changed: the run stops at its next boundary.
function GR.Disable()
    if run then run.stop = run.stop or "off"; Check(run, "off") end
    if last then last = nil end
end
MI.OnChange(function()
    if run and run.generation ~= MI.Generation() then run.stop = run.stop or "changed"; Wake(run) end
end)

function GR.ListenerCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    return n
end

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.guildRunState", { label = "Magic Inventory guild bank run (moves held for the run in progress and the last result)", unit = "count", kind = "cache",
        read = function() return (run and #run.ops or 0) + (last and #last.ops or 0) end })
end
