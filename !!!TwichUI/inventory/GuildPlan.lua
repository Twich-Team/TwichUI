-- TwichUI: Magic Inventory, the guild bank placement previews
-- Where items would go in a guild bank, shown before anything moves. Two previews, both read-only:
--   deposit      the carried bags' eligible items placed in their rules' tabs. What is in the bank stays where it is,
--                except that a compatible stack with room may receive items.
--   reorganize   the items already in the guild bank that a guild bank rule claims, gathered into the rule's tab and
--                re-stacked to its target size. Nothing is taken from the bags.
-- Pure: it reads only the tables it is given (nothing is changed in them, nothing in the game is called), so the tests can
-- hand it anything. MI.CurrentGuildPlan is the one place the game is read for a plan (GuildBank.lua, Items.lua).
--
-- Rules are the Magic Inventory rules (Rules.lua), judged in Plan.lua's order: protections and the Never transfer list,
-- a rule's own exclusions, then the first enabled rule that moves items owns the item (MI.Owner). A guild bank rule
-- owns an item for this planner; an item owned by a mail or bank rule is left alone, and an item no rule owns is left
-- alone. An item is never sent to another tab when its tab can't take it.
--
-- Stack sizes: a rule's target is the size each stack ends at, with one smaller stack holding the rest. Only
-- stack-compatible items merge: the same item ID, and the item stacks (its limit is above 1). A target above an item's
-- own limit blocks that item (it is never cut down silently); an unstackable item stays 1.
--
-- What it does not assume (each is a constraint on an operation, not a promise):
--   * splitting a stack: opts.split (GuildRun.CAN_SPLIT for the arrangement's run: SplitGuildBankItem / SplitContainerItem, which
--     the run verifies after placing). An operation that needs a split is listed, and is "blocked" when splitting is off.
--   * swapping two stacks, taking an item out to the bags and back, or parking one in the bags: never used. A
--     placement needs a free slot (or a stack with room) at that moment; items that must leave a full tab first are
--     ordered so, and a loop of full tabs is reported as needing temporary space.
--   * rights: a tab must be viewable and take deposits; taking an item out of a tab needs the rank's withdraw right
--     there. Unknown rights are "unknown", never "allowed". Whether a move between tabs counts against the daily
--     withdrawal allowance is not established, and the allowance is only known for the tab being shown.
-- The arrangement (Design.lua): a guild bank rule the arrangement editor made (rule.design) also carries RESERVED STACKS
-- (rule.place: this item, this many, in exactly this slot) and says which of its items take their extras (rule.rest). The
-- planner honours them like this, and says so in plan.design:
--   * a reserved stack is a target, never an order to acquire: with too little stock the slot is filled as far as it goes and
--     reported short, and nothing is invented, bought, sold or discarded;
--   * a reserved slot is kept for its item: no other item is placed in it, and an empty one is shown as a ghost;
--   * the items left over (beyond the reserved stacks) go to the free slots of the one tab that takes the item's extras,
--     in stacks of at most the item's limit; with no unambiguous tab, or no room, they stay where they are and it says why;
--   * a slot that holds another item is not cleared for a reserved stack: moving it out is never done here (no swaps), so
--     the reservation is reported blocked; an item of the arrangement that has to leave first is moved first;
--   * the item's owner is decided as everywhere (the first enabled rule that moves items): a broader rule above the
--     arrangement keeps the item and the arrangement is reported as overridden (plan.design.conflicts).
-- The plan keeps what a later executor would have to bind an approval to: the guild, each tab's name and reading, every
-- operation with its source, destination, count, rule and requirements (plan.ops), and the snapshot's sequence number.

local R = TwichUI
local MI = R.MagicInventory
local SLOTS = 98   -- GuildBank.SLOTS (this file is pure and doesn't need that file loaded)

MI.GREASON = {
    unmatched = "No guild bank rule picks it out",
    elsewhere = "\"%s\" owns it and sends it somewhere else",
    ["rule-blocked"] = "\"%s\" can't run: %s",
    ["rule-unknown"] = "\"%s\" can't be checked yet: %s",
    ["tab-full"] = "Tab %d has no free slot for %d more",
    ["target-too-big"] = "It stacks to %d, and the target is %d",
    ["no-withdraw"] = "Your rank can't take items out of tab %d",
    ["withdraw-unknown"] = "Whether your rank can take items out of tab %d isn't known",
    ["needs-split"] = "Needs a stack split, which hasn't been checked on this client",
    ["needs-space"] = "Needs room that isn't there: swaps and temporary parking in your bags aren't used",
    ["item-pending"] = "The game is still loading this item",
    ["item-unknown"] = "The game didn't say which item this is",
    ["count-unknown"] = "The game didn't say how many",
    ["tab-unread"] = "Tab %d hasn't been read: show it in the guild bank",
    ["limit"] = "Tab %d allows %d more stacks out today",
    ["slot-taken"] = "Slot %d is reserved for %s, but %s is there. Other items are never moved out of the way",
    ["extras-ambiguous"] = "The extras have no one tab: reserved stacks are in several tabs and none says it takes the extras",
    oversized = "A stack of %d is above the target of %d; Reorganize would split it",
    inplace = "Already as the rule wants it",
}

-- the reasons that mean "can't be told" rather than "can't be done"
MI.GUNKNOWN = { ["item-pending"] = true, ["item-unknown"] = true, ["count-unknown"] = true, ["withdraw-unknown"] = true,
    ["rule-unknown"] = true, ["tab-unread"] = true, pending = true, ["lock-unknown"] = true, ["quest-unknown"] = true,
    ["conjured-unknown"] = true, ["set-unknown"] = true, ["binding-unknown"] = true }
-- the reasons that mean a rule wanted it moved and something stops it (the others are protections and choices)
MI.GBLOCKED = { ["slot-taken"] = true, ["extras-ambiguous"] = true, ["tab-full"] = true, ["target-too-big"] = true, ["no-withdraw"] = true, ["needs-space"] = true,
    ["rule-blocked"] = true, locked = true, limit = true }

local function Text(code, a, b, c)
    local text = MI.GREASON[code] or MI.REASON[code] or code
    local ok, s = pcall(string.format, text, a, b, c)
    return ok and s or text
end

local function ItemName(id, facts) return facts and facts.name or ("item " .. tostring(id)) end

---------------------------------------------------------------------------
-- Rules: can each guild bank rule run, and on which tab? Never redirected: a rule that can't run says why.
---------------------------------------------------------------------------
-- Returns { rule, index, status = "ready" | "blocked" | "unknown", code, why, where, tab }.
local function RuleState(rule, index, opts, bank)
    local st = { rule = rule, index = index, status = "ready" }
    local code, why
    if opts.problem then code, why = opts.problem(rule) end
    local where = opts.resolve and rule.dest and opts.resolve(rule.dest) or nil
    st.where, st.tab = where, where and where.tab or nil
    if code then
        st.status, st.code, st.why = "blocked", code, why
        return st
    end
    if not where then st.status, st.code, st.why = "blocked", "no-guild-tab", "Choose the guild bank tab for this rule on this character." return st end
    local t = bank.tabs[where.tab]
    if bank.numTabs and where.tab > bank.numTabs then
        st.status, st.code = "blocked", "tab-missing"
        st.why = ("This guild bank has %d %s; the rule's tab is number %d."):format(bank.numTabs, bank.numTabs == 1 and "tab" or "tabs", where.tab)
    elseif not t then
        st.status, st.code, st.why = "unknown", "tab-unseen", "Open the guild bank to read the tab's name and your rights there."
    elseif where.tabName and t.name and t.name ~= where.tabName then
        st.status, st.code = "blocked", "tab-renamed"
        st.why = ("Tab %d is called \"%s\" now, not \"%s\". Review the destination."):format(where.tab, t.name, where.tabName)
    elseif t.viewable == false then
        st.status, st.code, st.why = "blocked", "tab-hidden", "Your rank can't see this tab."
    elseif t.canDeposit == false then
        st.status, st.code, st.why = "blocked", "no-deposit", "Your rank can't deposit in this tab."
    elseif t.viewable == nil or t.canDeposit == nil then
        st.status, st.code, st.why = "unknown", "rights-unknown", "The game didn't say whether you can deposit in this tab."
    elseif not t.slots then
        st.status, st.code, st.why = "unknown", "tab-unread", ("Tab %d hasn't been read yet: show it in the guild bank."):format(where.tab)
    end
    return st
end

-- The target stack size for an item under a rule: nil (no target), a size, or nil and a reason code.
local function TargetFor(rule, facts)
    local maxStack = math.max(1, facts.maxStack or 1)
    if maxStack <= 1 then return 1 end                  -- unstackable items stay single
    if (rule.stack or 0) <= 0 then return nil end
    if rule.stack > maxStack then return nil, "target-too-big", maxStack end
    return rule.stack
end

---------------------------------------------------------------------------
-- The simulated tabs. A cell is { id, count, icon, link, quality, locked, unknown }. Nothing in the input is edited.
---------------------------------------------------------------------------
local function CopyCell(c)
    return { id = c.id, count = c.count, icon = c.icon, link = c.link, quality = c.quality, locked = c.locked,
        unknown = (c.id == nil or c.count == nil) or nil }
end

local function NewSim(bank)
    local sim = {}
    for i, t in pairs(bank.tabs) do
        if t.slots then
            local slots = {}
            for s, c in pairs(t.slots) do slots[s] = CopyCell(c) end
            sim[i] = { slots = slots }
        end
    end
    return sim
end

-- The piece to take for a need: an exact fit first, then the largest that fits whole, then the smallest that must be
-- split. `field` names the amount still available in each piece; ties keep the list's order. Fewest splits, no randomness.
local function PickPiece(list, need, field)
    for _, p in ipairs(list) do if p[field] == need then return p end end
    local best
    for _, p in ipairs(list) do
        if p[field] > 0 and p[field] < need and (not best or p[field] > best[field]) then best = p end
    end
    if best then return best end
    for _, p in ipairs(list) do
        if p[field] > need and (not best or p[field] < best[field]) then best = p end
    end
    return best
end

-- skip: { [slot] = anything } slots the arrangement keeps for a reserved stack (never handed to another item)
local function FreeSlot(simTab, skip)
    for s = 1, SLOTS do if simTab.slots[s] == nil and not (skip and skip[s]) then return s end end
end
local function FreeCount(simTab, skip)
    local n = 0
    for s = 1, SLOTS do if simTab.slots[s] == nil and not (skip and skip[s]) then n = n + 1 end end
    return n
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
-- opts:
--   mode         "deposit" or "reorganize"
--   rules        MI.Rules()
--   never(id)    on the Never transfer list
--   facts(id)    -> facts (MI.ItemFacts), or nil and true while the game is loading it
--   resolve(destId) -> where (MI.Resolve)
--   problem(rule) -> code, sentence (MI.Problem with the guild as it is now)
--   guildNow     the character's guild (nil: none, false: not known yet)
--   bank         GuildBank.Snapshot()
--   stacks       the carried bags (MI.ReadBags().stacks); read for "deposit" only
--   keepExtra(id) another feature's keep amount
--   split        true where a partial stack can be moved (off until checked)
--   made, generation

---------------------------------------------------------------------------
-- The arrangement's automatic items, laid out. A design rule lists items its tab takes "automatically" (rest) with the size each is
-- spread in (sizes, else a full stack) and a layout (Design.lua D.Layout). Here that becomes reserved stacks, in the slots the
-- layout gives them, and from then on the planner treats them exactly like stacks the player pinned: they are targets, merged,
-- split and moved by the same machinery, never swapped in. The rules handed in are not changed; a rule that gets stacks is copied.
--   quantity: what the player has of an item = every tab read, plus the carried bags for a deposit
--   blocked slots: a pinned stack's, and one that holds an item no arrangement rule claims (it is never moved out of the way)
-- A stack nothing can fill is not drawn or reported (a tab with no Linen shows no Linen slot); the picture of the arrangement itself
-- is Design.lua D.Theory.
---------------------------------------------------------------------------
local function CompileLayouts(rules, opts, bank, mode)
    local D = MI.Design
    if not D then return rules end
    local claimed = {}
    for _, r in ipairs(rules) do
        if r.enabled and r.kind == "guild" and r.design then for id in pairs(r.include or {}) do claimed[id] = true end end
    end
    local function Quantity(id)
        local n = 0
        for _, t in pairs(bank.tabs) do
            if t.slots then for _, c in pairs(t.slots) do if c.id == id then n = n + (c.count or 0) end end end
        end
        if mode == "deposit" then
            for _, st in ipairs(opts.stacks or {}) do if st.id == id then n = n + (st.count or 0) end end
        end
        return n
    end
    local function Name(id) local f = opts.facts and opts.facts(id); return f and f.name end
    local out, extra = {}, {}
    local tidied = {}        -- tidied[id] = tab: an item the arrangement doesn't name is tidied in one tab only
    for i, rule in ipairs(rules) do
        out[i] = rule
        if rule.enabled and rule.kind == "guild" and rule.design and opts.resolve and rule.dest then
            local where = opts.resolve(rule.dest)
            local tab = where and where.tab
            local bt = tab and bank.tabs[tab]
            if bt and bt.slots then
                local pinned, pinnedTotal = {}, {}
                for _, p in ipairs(rule.place or {}) do
                    pinned[p.slot] = true
                    pinnedTotal[p.id] = (pinnedTotal[p.id] or 0) + p.count
                end

                -- Organize also tidies the tab: the other items in it (named by no arrangement rule, and left to no other rule or the
                -- Never list) are merged into full stacks and sorted at the far end, away from the arrangement. Never in a deposit.
                local movable, foreign = {}, {}
                if mode == "reorganize" then
                    for slot, c in pairs(bt.slots) do
                        if c.id and not claimed[c.id] and not c.locked and c.count and c.count > 0 and (tidied[c.id] == nil or tidied[c.id] == tab) then
                            local facts = opts.facts and opts.facts(c.id)
                            if facts and not (opts.never and opts.never(c.id)) then
                                local owner, _, protectedBy = MI.Owner(rules, facts)
                                if not owner and not protectedBy then
                                    movable[slot] = true
                                    foreign[c.id] = (foreign[c.id] or 0) + c.count
                                end
                            end
                        end
                    end
                end

                -- an item is tidied only when all of it is in this tab: the planner gathers every copy of an owned item into its tab,
                -- and tidying must not pull items out of other tabs
                if next(foreign) then
                    local bankTotal = {}
                    for _, t in pairs(bank.tabs) do
                        if t.slots then for _, c in pairs(t.slots) do if foreign[c.id] then bankTotal[c.id] = (bankTotal[c.id] or 0) + (c.count or 0) end end end
                    end
                    for id, n in pairs(foreign) do
                        if bankTotal[id] ~= n then
                            foreign[id] = nil
                            for slot, c in pairs(bt.slots) do if c.id == id then movable[slot] = nil end end
                        end
                    end
                end

                -- the arrangement's own automatic items
                local laid = {}
                if rule.rest and next(rule.rest) then
                    local ids = {}
                    for id in pairs(rule.rest) do if rule.include[id] then ids[#ids + 1] = id end end
                    D.SortAuto(ids, Name)
                    local list = {}
                    for _, id in ipairs(ids) do
                        local facts = opts.facts and opts.facts(id)
                        if facts then
                            local limit = math.max(1, facts.maxStack or 1)
                            local size = math.min((rule.sizes and rule.sizes[id]) or limit, limit)
                            local pieces = D.Pieces(math.max(0, Quantity(id) - (pinnedTotal[id] or 0)), size)
                            if #pieces > 0 then list[#list + 1] = { id = id, pieces = pieces } end
                        end
                    end
                    if #list > 0 then
                        laid = D.Layout(list, rule.layout or "packed", function(slot)
                            if pinned[slot] then return true end
                            local c = bt.slots[slot]
                            return c ~= nil and not (c.id and claimed[c.id]) and not movable[slot]
                        end)
                    end
                end

                -- the tidied items: stacks of at most the item's limit, sorted by name, in the highest free slots
                local tail = {}
                if next(foreign) then
                    local used = {}
                    for slot in pairs(pinned) do used[slot] = true end
                    for _, c in ipairs(laid) do used[c.slot] = true end
                    local avail = {}
                    for slot = MI.GUILD_SLOTS, 1, -1 do
                        local c = bt.slots[slot]
                        local obstacle = c ~= nil and not (c.id and claimed[c.id]) and not movable[slot]
                        if not used[slot] and not obstacle then avail[#avail + 1] = slot end
                    end
                    local ids = {}
                    for id in pairs(foreign) do ids[#ids + 1] = id end
                    D.SortAuto(ids, Name)
                    local chosen, count = {}, 0
                    for _, id in ipairs(ids) do
                        local facts = opts.facts(id)
                        local pieces = D.Pieces(foreign[id], math.max(1, facts.maxStack or 1))
                        if count + #pieces <= #avail then
                            chosen[#chosen + 1] = { id = id, pieces = pieces }
                            count = count + #pieces
                            tidied[id] = tab
                        end
                    end
                    if count > 0 then
                        local slots = {}
                        for k = 1, count do slots[k] = avail[k] end
                        table.sort(slots)
                        local k = 0
                        for _, it in ipairs(chosen) do
                            for _, n in ipairs(it.pieces) do
                                k = k + 1
                                tail[#tail + 1] = { slot = slots[k], id = it.id, count = n, auto = true }
                            end
                        end
                    end
                end

                if #laid > 0 then
                    local copy = {}
                    for k, v in pairs(rule) do copy[k] = v end
                    local place = {}
                    for _, p in ipairs(rule.place or {}) do place[#place + 1] = p end
                    for _, c in ipairs(laid) do place[#place + 1] = { slot = c.slot, id = c.id, count = c.count, auto = true } end
                    table.sort(place, function(a, b) return a.slot < b.slot end)
                    copy.place = place
                    out[i] = copy
                end
                if #tail > 0 then
                    local include, rest = {}, {}
                    for _, p in ipairs(tail) do include[p.id], rest[p.id] = true, true end
                    extra[#extra + 1] = { id = "tidy:" .. tostring(rule.id), name = ("Other items in tab %d, tidied"):format(tab), kind = "guild", enabled = true,
                        design = true, synthetic = true, dest = rule.dest, include = include, exclude = {}, qualities = {}, cats = {}, equip = "any", bind = "any",
                        keep = 0, stack = 0, place = tail, rest = rest, sizes = {}, layout = "packed" }
                end
            end
        end
    end
    for _, r in ipairs(extra) do out[#out + 1] = r end
    return out
end

function MI.BuildGuildPlan(opts)
    local mode = opts.mode == "reorganize" and "reorganize" or "deposit"
    local rules = opts.rules or {}
    local bank = opts.bank or { tabs = {} }
    local canSplit = opts.split == true
    local plan = { mode = mode, guild = nil, ops = {}, items = {}, untouched = {}, rules = {}, tabs = {}, constraints = {}, notes = {},
        made = opts.made, generation = opts.generation, seq = bank.seq, readOnly = true }

    -- a snapshot of another guild is not this guild's bank
    local mismatch = bank.guild and type(opts.guildNow) == "string" and opts.guildNow ~= bank.guild
    if mismatch then bank = { tabs = {}, open = false, numTabs = nil, seq = bank.seq } end
    plan.guild = bank.guild or (type(opts.guildNow) == "string" and opts.guildNow) or nil
    plan.open = bank.open == true
    rules = CompileLayouts(rules, opts, bank, mode)

    local sim = NewSim(bank)
    local why = {}       -- why[tab][slot] = { text, ... } what happens to that slot
    local blockedAt = {} -- blockedAt[tab][slot] = reason: a slot an operation that can't be carried out ends at
    local function Why(tab, slot, text)
        why[tab] = why[tab] or {}
        local l = why[tab][slot]
        if not l then l = {}; why[tab][slot] = l end
        if #l < 4 then l[#l + 1] = text end
    end
    -- a slot an operation that can't be carried out touches, or an item held back: { text, unknown = true when it can't be told }
    local function Blocked(tab, slot, text, unknown)
        blockedAt[tab] = blockedAt[tab] or {}
        blockedAt[tab][slot] = { text = text, unknown = unknown or nil }
    end

    ---------------------------------------------------------------- rules
    local state, stateByIndex = {}, {}
    for i, rule in ipairs(rules) do
        if rule.enabled and rule.kind == "guild" then
            local st = RuleState(rule, i, opts, bank)
            state[rule.id] = st
            stateByIndex[#stateByIndex + 1] = st
            plan.rules[#plan.rules + 1] = { ruleId = rule.id, rule = rule.name, status = st.status, code = st.code, why = st.why,
                tab = st.tab, tabName = st.where and st.where.tabName, icon = st.where and st.where.tabIcon, stack = rule.stack, design = rule.design or nil }
        end
    end

    local function Untouch(id, facts, code, count, stacks, rule, text, extra)
        local u = { id = id, facts = facts, reason = code, count = count, stacks = stacks, rule = rule and rule.name, ruleId = rule and rule.id,
            text = text or Text(code) }
        if extra then for k, v in pairs(extra) do u[k] = v end end
        plan.untouched[#plan.untouched + 1] = u
        return u
    end
    local function AddItem(entry) plan.items[#plan.items + 1] = entry; return entry end

    local nOps, scopeCount = 0, 0
    local function Op(o)
        nOps = nOps + 1
        o.n = nOps
        if o.split and not canSplit then o.status, o.why, o.code = "blocked", Text("needs-split"), "needs-split" else o.status = "ok" end
        plan.ops[#plan.ops + 1] = o
        return o
    end

    ---------------------------------------------------------------- the arrangement (rules made by the arrangement editor)
    local D = MI.Design
    local reserved = {}          -- reserved[tab][slot] = itemID: a slot kept for a reserved stack
    local design = { allocs = {}, overflow = {}, conflicts = {}, items = 0 }
    local designAt = {}          -- designAt[tab][slot] = the result of the reserved stack there
    plan.design = design
    if D then
        for _, st in ipairs(stateByIndex) do
            local rule = st.rule
            if rule.design and st.tab and (st.status == "ready" or st.status == "unknown") then
                for _, p in ipairs(rule.place or {}) do
                    local facts = opts.facts and opts.facts(p.id)
                    local effective = true
                    if facts then
                        local owner = MI.Owner(rules, facts)
                        effective = owner ~= nil and owner.design == true
                    end
                    if effective then
                        reserved[st.tab] = reserved[st.tab] or {}
                        if reserved[st.tab][p.slot] == nil then reserved[st.tab][p.slot] = p.id end
                    end
                end
            end
        end
        design.conflicts = D.Conflicts(rules, { resolve = opts.resolve, facts = function(id) return opts.facts and (opts.facts(id)) end })
    end

    -- the arrangement's rules that own an item (the first owner, then the arrangement's other rules that match it), or nil
    local function DesignOwners(facts)
        if not D then return nil end
        local owner, shadow = MI.Owner(rules, facts)
        if not (owner and owner.design and owner.kind == "guild") then return nil end
        local list = { owner }
        for _, r in ipairs(shadow) do if r.design and r.kind == "guild" then list[#list + 1] = r end end
        return list
    end

    -- an item's reserved stacks (in tab and slot order) and the tab that takes its extras (nil and a code when none does)
    local function DesignAllocs(id, owners)
        local allocs, ov = {}, {}
        for _, rule in ipairs(owners) do
            local st = state[rule.id]
            if st then
                for _, p in ipairs(rule.place or {}) do
                    if p.id == id then allocs[#allocs + 1] = { tab = st.tab or 0, slot = p.slot, count = p.count, rule = rule, st = st, auto = p.auto } end
                end
                ov[#ov + 1] = { rule = rule, tab = st.tab, st = st, rest = rule.rest ~= nil and rule.rest[id] == true }
            end
        end
        -- pinned stacks are filled first (an automatic stack only gets what they leave), each in tab and slot order
        table.sort(allocs, function(a, b)
            if (a.auto == true) ~= (b.auto == true) then return not a.auto end
            if a.tab ~= b.tab then return a.tab < b.tab end
            return a.slot < b.slot
        end)
        local pick, code = D.OverflowOf(ov)
        return allocs, pick, code
    end

    -- can this reserved stack be looked at at all? nil when it can, else status, code, sentence
    local function AllocGate(a, id, maxStack)
        local st = a.st
        if st.status == "blocked" then return "blocked", "rule-blocked", Text("rule-blocked", a.rule.name, st.why or "") end
        if st.status ~= "ready" or not sim[a.tab] then
            local code = st.status == "unknown" and "rule-unknown" or "tab-unread"
            return "unknown", code, code == "rule-unknown" and Text(code, a.rule.name, st.why or "") or Text(code, a.tab)
        end
        if a.count > maxStack then return "blocked", "target-too-big", Text("target-too-big", maxStack, a.count) end
        if reserved[a.tab] and reserved[a.tab][a.slot] ~= id then return "blocked", "slot-double", Text("slot-double") end
        return nil
    end

    local function Result(a, id, facts, have, status, code, why)
        -- an automatic stack is where the layout wants it, not a quantity the player asked for: short is not a shortfall
        if a.auto and status == "short" then status = "ok" end
        local r = { tab = a.tab, slot = a.slot, id = id, want = a.count, have = have or 0, state = status, code = code, why = why,
            rule = a.rule.name, ruleId = a.rule.id, icon = facts and facts.icon, auto = a.auto }
        r.short = a.auto and 0 or math.max(0, a.count - r.have)
        if a.auto and status == "ok" and r.have == 0 then return r end   -- nothing filled it: it is not drawn
        design.allocs[#design.allocs + 1] = r
        designAt[a.tab] = designAt[a.tab] or {}
        designAt[a.tab][a.slot] = r
        Why(a.tab, a.slot, ("Reserved for %s \195\151%d (\"%s\")%s"):format(ItemName(id, facts), a.count, a.rule.name,
            r.short > 0 and (": %d short"):format(r.short) or ""))
        return r
    end

    -- the items some arrangement rule reserves a stack of, in the rules' order, then by item
    local function DesignIds()
        local out, seen = {}, {}
        for _, st in ipairs(stateByIndex) do
            if st.rule.design then
                local ids = {}
                for _, p in ipairs(st.rule.place or {}) do if not seen[p.id] then seen[p.id] = true; ids[#ids + 1] = p.id end end
                table.sort(ids)
                for _, id in ipairs(ids) do out[#out + 1] = id end
            end
        end
        return out
    end

    -- a design item's stack that can't be looked at (item still loading): its reserved slots are unknown
    local function DesignPending(id, code)
        for _, st in ipairs(stateByIndex) do
            for _, p in ipairs(st.rule.design and st.rule.place or {}) do
                if p.id == id then
                    Result({ tab = st.tab or 0, slot = p.slot, count = p.count, rule = st.rule, st = st }, id, nil, 0, "unknown", code, Text(code))
                end
            end
        end
    end
    -- Deposit: a design item's reserved stacks first (a stack in its slot receives what it lacks), then its extras in the tab that
    -- takes them. e: Plan.lua's entry for the item (what the bags would give), nil when none of it is eligible in the bags.
    local function DepositDesign(id, facts, e, owners)
        local allocs, ovr, ocode = DesignAllocs(id, owners)
        local owner = owners[1]
        local maxStack = math.max(1, facts.maxStack or 1)
        local item = { id = id, facts = facts, rule = owner.name, ruleId = owner.id, tab = (ovr and ovr.tab) or (allocs[1] and allocs[1].tab),
            qty = 0, source = "bags", ops = 0, placed = 0, design = true }
        design.items = design.items + 1
        local pool = {}
        for _, t in ipairs(e and e.take or {}) do
            pool[#pool + 1] = { stack = t.stack, left = t.count, inSlot = t.stack.count }
            item.qty = item.qty + t.count
        end
        local function Place(T, toSlot, isNew, amount, p, rule)
            local needSplit = amount < p.inSlot
            p.left, p.inSlot = p.left - amount, p.inSlot - amount
            local op = Op({ kind = isNew and "deposit" or "merge", id = id, count = amount,
                from = { kind = "bag", bag = p.stack.bag, slot = p.stack.slot, link = p.stack.link }, to = { tab = T, slot = toSlot },
                rule = rule.name, ruleId = rule.id, split = needSplit or nil, needs = { needSplit and "split" or nil, "deposit:" .. T }, link = p.stack.link })
            local simTab = sim[T]
            if isNew then simTab.slots[toSlot] = { id = id, count = amount, icon = facts.icon, link = p.stack.link, quality = facts.quality, added = true }
            else simTab.slots[toSlot].count = simTab.slots[toSlot].count + amount end
            item.ops, item.placed = item.ops + 1, item.placed + amount
            Why(T, toSlot, ("%s %d from your bags (\"%s\")"):format(isNew and "Receives" or "Adds", amount, rule.name))
            if op.status == "blocked" then Blocked(T, toSlot, op.why) end
        end
        -- amount from the pool into one slot, in as many pieces as it takes
        local function Take(T, slot, amount, isNew, rule)
            local got, first = 0, isNew
            while got < amount do
                local p = PickPiece(pool, amount - got, "left")
                if not p then break end
                local n = math.min(p.left, amount - got)
                Place(T, slot, first, n, p, rule)
                first, got = false, got + n
            end
            return got
        end

        local earmark = 0   -- what a blocked reserved slot is waiting for: kept in the bags, not scattered as extras
        for _, a in ipairs(allocs) do
            local status, code, why = AllocGate(a, id, maxStack)
            if status then
                Result(a, id, facts, 0, status, code, why)
            else
                local cell = sim[a.tab].slots[a.slot]
                if cell == nil then
                    local got = Take(a.tab, a.slot, a.count, true, a.rule)
                    Result(a, id, facts, got, got >= a.count and "ok" or "short")
                elseif cell.id == id and cell.count and not cell.locked then
                    local have = cell.count
                    if have < a.count then have = have + Take(a.tab, a.slot, a.count - have, false, a.rule) end
                    Result(a, id, facts, have, have >= a.count and "ok" or "short")
                elseif cell.id == id and cell.locked then
                    Result(a, id, facts, cell.count or 0, "blocked", "locked", Text("locked"))
                    Blocked(a.tab, a.slot, Text("locked"))
                    earmark = earmark + math.max(0, a.count - (cell.count or 0))
                else
                    local why2 = Text("slot-taken", a.slot, ItemName(id, facts), cell.id and ItemName(cell.id, opts.facts and (opts.facts(cell.id))) or "something the game didn't identify")
                    Result(a, id, facts, 0, "blocked", "slot-taken", why2)
                    Blocked(a.tab, a.slot, why2)
                    earmark = earmark + a.count
                end
            end
        end
        for _, p in ipairs(pool) do
            if earmark > 0 and p.left > 0 then p.held, earmark = true, earmark - p.left end
        end

        local left = 0
        for _, p in ipairs(pool) do if not p.held then left = left + p.left end end
        if left > 0 then
            if not ovr then
                local text = Text("extras-ambiguous")
                Untouch(id, facts, "extras-ambiguous", left, nil, owner, text, { source = "bags" })
                design.overflow[#design.overflow + 1] = { id = id, qty = left, state = "unmanaged", code = "extras-ambiguous", text = text }
            elseif ovr.st.status ~= "ready" then
                local code = ovr.st.status == "unknown" and "rule-unknown" or "rule-blocked"
                local text = Text(code, ovr.rule.name, ovr.st.why or "")
                Untouch(id, facts, code, left, nil, ovr.rule, text, { source = "bags" })
                design.overflow[#design.overflow + 1] = { id = id, tab = ovr.tab, qty = left, state = "unmanaged", code = code, text = text }
            else
                local T = ovr.tab
                local simT = sim[T]
                local unplaced, placedExtra = 0, 0
                for _, p in ipairs(pool) do
                    local amount = p.left
                    if amount > 0 and not p.held then
                        local target
                        if maxStack > 1 then
                            for s = 1, SLOTS do
                                local c = simT.slots[s]
                                if c and c.id == id and c.count and not c.locked and not (reserved[T] and reserved[T][s]) and c.count + amount <= maxStack then target = s break end
                            end
                        end
                        if target then Place(T, target, false, amount, p, ovr.rule); placedExtra = placedExtra + amount
                        else
                            local free = FreeSlot(simT, reserved[T])
                            if free then Place(T, free, true, amount, p, ovr.rule); placedExtra = placedExtra + amount
                            else unplaced = unplaced + amount end
                        end
                    end
                end
                if placedExtra > 0 then design.overflow[#design.overflow + 1] = { id = id, tab = T, qty = placedExtra, state = "placed" } end
                if unplaced > 0 then
                    local text = Text("tab-full", T, unplaced)
                    Untouch(id, facts, "tab-full", unplaced, nil, ovr.rule, text, { source = "bags", tab = T })
                    design.overflow[#design.overflow + 1] = { id = id, tab = T, qty = unplaced, state = "unmanaged", code = "tab-full", text = text }
                    item.blocked = unplaced
                end
            end
        end
        item.state = item.placed > 0 and "moves" or "inplace"
        AddItem(item)
    end

    ---------------------------------------------------------------- deposit
    if mode == "deposit" then
        -- the base plan judges the bags (protections, keep amounts, whole stacks) with the arrangement's rules as plain guild
        -- rules of the same place in the list; the reserved stacks and extras are placed below
        local baseRules = rules
        if D then
            baseRules = {}
            for i, r in ipairs(rules) do
                if r.design then
                    local c = {}
                    for k, v in pairs(r) do c[k] = v end
                    c.design, c.place, c.rest, c.stack = nil, nil, nil, 0
                    baseRules[i] = c
                else
                    baseRules[i] = r
                end
            end
        end
        local base = MI.BuildPlan({
            stacks = opts.stacks or {}, rules = baseRules, never = opts.never, resolve = opts.resolve, keepExtra = opts.keepExtra,
            context = "guild", split = { guild = canSplit },
            problem = function(rule)
                local st = state[rule.id]
                if st and st.status ~= "ready" then return st.code, st.why end
                return nil
            end,
        })
        plan.pending = base.pending
        for _, u in ipairs(base.skipped) do
            Untouch(u.id, u.facts, u.reason, u.count, u.stacks, u.rule and { name = u.rule, id = u.ruleId } or nil, u.text, { source = "bags" })
        end
        for _, r in ipairs(base.reserved) do
            Untouch(r.id, r.facts, "elsewhere", r.count, r.stacks, { name = r.rule, id = r.ruleId }, Text("elsewhere", r.rule), { source = "bags" })
        end
        for _, a in ipairs(base.attention) do
            local st = state[a.ruleId]
            if st then st.attention = true end
        end

        -- entries in a fixed order: the rule's place in the list, then the item
        local entries = {}
        for _, g in ipairs(base.groups) do
            for _, e in ipairs(g.entries) do entries[#entries + 1] = { entry = e } end
        end
        table.sort(entries, function(a, b)
            local sa, sb = state[a.entry.ruleId], state[b.entry.ruleId]
            if sa.index ~= sb.index then return sa.index < sb.index end
            return a.entry.id < b.entry.id
        end)
        -- the arrangement's items first (their reserved stacks and extras), then everything else
        local plain, doneDesign = {}, {}
        for _, x in ipairs(entries) do
            local owners = state[x.entry.ruleId].rule.design and DesignOwners(x.entry.facts) or nil
            if owners then
                DepositDesign(x.entry.id, x.entry.facts, x.entry, owners)
                doneDesign[x.entry.id] = true
            else
                plain[#plain + 1] = x
            end
        end
        for _, id in ipairs(DesignIds()) do
            if not doneDesign[id] then
                local facts, pending
                if opts.facts then facts, pending = opts.facts(id) end
                if not facts then
                    DesignPending(id, pending == false and "item-unknown" or "item-pending")
                else
                    local owners = DesignOwners(facts)
                    if owners then DepositDesign(id, facts, nil, owners) end
                end
                doneDesign[id] = true
            end
        end
        entries = plain

        for _, x in ipairs(entries) do
            local e, st = x.entry, state[x.entry.ruleId]
            local rule, T, facts, id = st.rule, st.tab, e.facts, e.id
            local simTab = sim[T]
            local S, tcode, limit = TargetFor(rule, facts)
            local want = 0
            for _, t in ipairs(e.take) do want = want + t.count end
            local item = { id = id, facts = facts, rule = rule.name, ruleId = rule.id, tab = T, qty = want, source = "bags", ops = 0, placed = 0, target = S }
            if not simTab then
                item.state, item.code, item.why = "unknown", "tab-unread", Text("tab-unread", T)
                AddItem(item)
            elseif tcode then
                item.state, item.code, item.why = "blocked", tcode, Text(tcode, limit, rule.stack)
                AddItem(item)
                Untouch(id, facts, tcode, want, #e.take, rule, item.why, { source = "bags" })
            else
                local maxStack = math.max(1, facts.maxStack or 1)
                -- the pool: bag stacks (whole), each with what is still in it
                -- left: still to be deposited from the stack; inSlot: what the slot holds now (an amount below it needs a split)
                local pool = {}
                for _, t in ipairs(e.take) do pool[#pool + 1] = { stack = t.stack, left = t.count, inSlot = t.stack.count } end
                local function From(p, amount)
                    local needSplit = amount < p.inSlot
                    p.left, p.inSlot = p.left - amount, p.inSlot - amount
                    return { kind = "bag", bag = p.stack.bag, slot = p.stack.slot, link = p.stack.link }, needSplit
                end
                -- receivers: compatible stacks already in the tab with room. Only items that stack merge.
                local function Receivers(limitTo)
                    local out = {}
                    if maxStack <= 1 then return out end
                    for s = 1, SLOTS do
                        local c = simTab.slots[s]
                        if c and c.id == id and c.count and not c.locked and c.count < limitTo and not (reserved[T] and reserved[T][s]) then out[#out + 1] = s end
                    end
                    return out
                end
                if S and maxStack > 1 then
                    for s = 1, SLOTS do
                        local c = simTab.slots[s]
                        if c and c.id == id and c.count and c.count > S then
                            item.note = Text("oversized", c.count, S)
                            Why(T, s, item.note)
                        end
                    end
                end
                local unplaced = 0
                local function Place(toSlot, isNew, amount, fromPool)
                    local src, needSplit = From(fromPool, amount)
                    local cur = simTab.slots[toSlot]
                    local op = Op({ kind = isNew and "deposit" or "merge", id = id, count = amount, from = src, to = { tab = T, slot = toSlot },
                        rule = rule.name, ruleId = rule.id, split = needSplit or nil,
                        needs = { needSplit and "split" or nil, "deposit:" .. T }, link = fromPool.stack.link })
                    if isNew then
                        simTab.slots[toSlot] = { id = id, count = amount, icon = facts.icon, link = fromPool.stack.link, quality = facts.quality, added = true }
                    else
                        cur.count = cur.count + amount
                    end
                    item.ops, item.placed = item.ops + 1, item.placed + amount
                    Why(T, toSlot, ("%s %d from your bags (\"%s\")"):format(isNew and "Receives" or "Adds", amount, rule.name))
                    if op.status == "blocked" then Blocked(T, toSlot, op.why) end
                end

                if S == nil or maxStack <= 1 then
                    -- no target: whole stacks go where they fit, preferring a compatible stack with room
                    for _, p in ipairs(pool) do
                        local amount = p.left
                        local target
                        for _, s in ipairs(Receivers(maxStack + 1)) do
                            if simTab.slots[s].count + amount <= maxStack then target = s break end
                        end
                        if target then Place(target, false, amount, p)
                        else
                            local free = FreeSlot(simTab, reserved[T])
                            if free then Place(free, true, amount, p) else unplaced = unplaced + amount end
                        end
                    end
                else
                    -- a target: fill compatible stacks that are below it, then new stacks of the target size and one smaller one
                    local incoming = 0
                    for _, p in ipairs(pool) do incoming = incoming + p.left end
                    local targets, remaining = {}, incoming
                    for _, s in ipairs(Receivers(S)) do
                        if remaining <= 0 then break end
                        local need = math.min(S - simTab.slots[s].count, remaining)
                        targets[#targets + 1] = { slot = s, need = need }
                        remaining = remaining - need
                    end
                    while remaining > 0 do
                        local need = math.min(S, remaining)
                        targets[#targets + 1] = { new = true, need = need }
                        remaining = remaining - need
                    end
                    for _, tg in ipairs(targets) do
                        local slot = tg.slot
                        if tg.new then
                            slot = FreeSlot(simTab, reserved[T])
                            if not slot then unplaced = unplaced + tg.need end
                        end
                        local got, first = 0, tg.new
                        while got < tg.need do
                            local p = PickPiece(pool, tg.need - got, "left")
                            if not p then break end
                            local amount = math.min(p.left, tg.need - got)
                            if slot then
                                Place(slot, first, amount, p)
                                first = false
                            else
                                -- no room for this target: what it would have taken stays in the bags
                                p.left, p.inSlot = p.left - amount, p.inSlot - amount
                            end
                            got = got + amount
                        end
                    end
                end
                if unplaced > 0 then
                    item.state, item.code = (item.placed > 0 and "partial" or "blocked"), "tab-full"
                    item.why = Text("tab-full", T, unplaced)
                    item.blocked = unplaced
                    Untouch(id, facts, "tab-full", unplaced, nil, rule, item.why, { source = "bags", tab = T })
                else
                    item.state = "moves"
                end
                AddItem(item)
            end
        end
    else
        ---------------------------------------------------------------- reorganize
        plan.pending = 0
        -- every occupied slot of every tab that has been read, in tab and slot order
        local stacks = {}
        for i = 1, bank.numTabs or 0 do
            local t, st = bank.tabs[i], sim[i]
            if t and st then
                for s = 1, SLOTS do
                    local c = st.slots[s]
                    if c then stacks[#stacks + 1] = { tab = i, slot = s, cell = c } end
                end
            end
        end
        scopeCount = #stacks
        local byItem, order = {}, {}
        local function Hold(x, code, count, rule, text, extra)
            local u = Untouch(x.cell.id, x.facts, code, count or x.cell.count or 0, 1, rule, text, extra)
            u.tab, u.source = x.tab, "bank"
            Blocked(x.tab, x.slot, u.text, MI.GUNKNOWN[code])
            Why(x.tab, x.slot, u.text)
            return u
        end
        local counted = {}
        for _, x in ipairs(stacks) do
            local c = x.cell
            local id = c.id
            if id == nil then
                x.facts = nil
                Hold(x, "item-unknown", c.count, nil, nil)
                plan.unresolved = (plan.unresolved or 0) + 1
            else
                local facts, pending
                if opts.facts then facts, pending = opts.facts(id) end
                x.facts = facts
                if not facts then
                    Hold(x, pending == false and "item-unknown" or "item-pending", c.count, nil, nil)
                    plan.unresolved = (plan.unresolved or 0) + 1
                else
                    local owner, _, protectedBy = MI.Owner(rules, facts)
                    local ot = owner and state[owner.id]
                    -- an arrangement item is looked at while any of its arrangement rules can run
                    local owners = owner and owner.kind == "guild" and owner.design and DesignOwners(facts) or nil
                    local gate = ot
                    if owners then
                        for _, r in ipairs(owners) do
                            local rs = state[r.id]
                            if rs and rs.status == "ready" then gate = rs break end
                        end
                    end
                    if not owner then
                        plan.leftAlone = (plan.leftAlone or 0) + 1
                        Why(x.tab, x.slot, Text("unmatched"))
                    elseif opts.never and opts.never(id) then
                        Hold(x, "never", c.count, owner)
                    elseif protectedBy then
                        Hold(x, "never-rule", c.count, owner, MI.ReasonText("never-rule", protectedBy.name))
                    elseif owner.kind ~= "guild" then
                        plan.leftAlone = (plan.leftAlone or 0) + 1
                        Why(x.tab, x.slot, Text("elsewhere", owner.name))
                    elseif not gate or gate.status ~= "ready" then
                        local code = ot and ot.status == "unknown" and "rule-unknown" or "rule-blocked"
                        Hold(x, code, c.count, owner, Text(code, owner.name, ot and ot.why or "?"))
                    elseif c.count == nil then
                        Hold(x, "count-unknown", nil, owner)
                    elseif c.locked == true then
                        Hold(x, "locked", c.count, owner)
                    else
                        local src = bank.tabs[x.tab]
                        if src.canWithdraw == false then
                            Hold(x, "no-withdraw", c.count, owner, Text("no-withdraw", x.tab))
                        elseif src.canWithdraw == nil then
                            Hold(x, "withdraw-unknown", c.count, owner, Text("withdraw-unknown", x.tab))
                        else
                            local it = byItem[id]
                            if not it then
                                it = { id = id, facts = facts, rule = owner, st = ot, stacks = {}, owners = owners }
                                byItem[id] = it
                                order[#order + 1] = it
                            end
                            it.stacks[#it.stacks + 1] = x
                        end
                    end
                end
            end
        end
        -- an arrangement item with none of its stacks in the tabs read (or none free to move) still has reserved stacks to report
        if D then
            for _, id in ipairs(DesignIds()) do
                if not byItem[id] then
                    local facts, pending
                    if opts.facts then facts, pending = opts.facts(id) end
                    if not facts then
                        DesignPending(id, pending == false and "item-unknown" or "item-pending")
                    else
                        local owners = DesignOwners(facts)
                        if owners then
                            local it = { id = id, facts = facts, rule = owners[1], st = state[owners[1].id], stacks = {}, owners = owners }
                            byItem[id] = it
                            order[#order + 1] = it
                        end
                    end
                end
            end
        end
        -- items in the rules' order, then by item: a fixed order
        table.sort(order, function(a, b)
            if a.st.index ~= b.st.index then return a.st.index < b.st.index end
            return a.id < b.id
        end)

        -- A design item (the arrangement): its reserved stacks are filled from the item's stacks in the bank, its extras go to the
        -- tab that takes them. Same contract as Settle: true when settled, false when it waits for room or a slot another item
        -- may still free; `final` settles it as it stands.
        local function SettleDesign(it, final)
            local id, facts = it.id, it.facts
            local maxStack = math.max(1, facts.maxStack or 1)
            if not it.info then
                local allocs, ovr, ocode = DesignAllocs(id, it.owners)
                it.allocs, it.ovr, it.ocode = allocs, ovr, ocode
                local info = { id = id, facts = facts, rule = it.rule.name, ruleId = it.rule.id, tab = (ovr and ovr.tab) or (allocs[1] and allocs[1].tab),
                    qty = 0, source = "bank", ops = 0, placed = 0, design = true }
                for _, x in ipairs(it.stacks) do info.qty = info.qty + x.cell.count end
                it.info = info
                design.items = design.items + 1
                AddItem(info)
            end
            local info, allocs, ovr = it.info, it.allocs, it.ovr
            local ovrReady = ovr ~= nil and ovr.st.status == "ready" and sim[ovr.tab] ~= nil
            local made, waiting = 0, false

            local function Move(from, T, toSlot, amount, isNew, rule)
                local srcCell = sim[from.tab].slots[from.slot]
                local needSplit = amount < srcCell.count
                local op = Op({ kind = isNew and "move" or "merge", id = id, count = amount, from = { kind = "bank", tab = from.tab, slot = from.slot },
                    to = { tab = T, slot = toSlot }, rule = rule.name, ruleId = rule.id, split = needSplit or nil,
                    needs = { needSplit and "split" or nil, "withdraw:" .. from.tab, "deposit:" .. T }, link = srcCell.link })
                srcCell.count = srcCell.count - amount
                if srcCell.count == 0 then sim[from.tab].slots[from.slot] = nil end
                local dest = sim[T].slots[toSlot]
                if dest then dest.count = dest.count + amount
                else sim[T].slots[toSlot] = { id = id, count = amount, icon = srcCell.icon, link = srcCell.link, quality = srcCell.quality, added = true } end
                made = made + 1
                info.ops, info.placed = info.ops + 1, info.placed + amount
                local where = from.tab == T and ("slot " .. from.slot) or ("tab " .. from.tab .. ", slot " .. from.slot)
                Why(T, toSlot, ("%s %d from %s (\"%s\")"):format(isNew and "Receives" or "Adds", amount, where, rule.name))
                Why(from.tab, from.slot, ("%d go to tab %d, slot %d (\"%s\")"):format(amount, T, toSlot, rule.name))
                if op.status == "blocked" then Blocked(T, toSlot, op.why); Blocked(from.tab, from.slot, op.why) end
            end

            -- the item's stacks as they are now, and what each is for
            local cur, anchorOf = {}, {}
            for _, x in ipairs(it.stacks) do
                local c = sim[x.tab].slots[x.slot]
                if c and c.id == id and c.count and c.count > 0 then cur[#cur + 1] = { tab = x.tab, slot = x.slot, count = c.count } end
            end
            for _, a in ipairs(allocs) do
                a.gate = nil
                local status, code, why = AllocGate(a, id, maxStack)
                if status then a.gate = { status, code, why } end
                if not a.gate then
                    for _, x in ipairs(cur) do
                        if x.tab == a.tab and x.slot == a.slot and not anchorOf[x] then anchorOf[x] = a break end
                    end
                end
            end
            -- what can be moved: everything above what a reserved stack keeps in its own slot. A stack already in the tab that
            -- takes the extras, in no reserved slot, stays where it is unless the reserved stacks need it.
            local surplus = {}
            for _, x in ipairs(cur) do
                local a = anchorOf[x]
                local keepHere = a and math.min(x.count, a.count) or 0
                local well = a == nil and ovrReady and x.tab == ovr.tab and not (reserved[x.tab] and reserved[x.tab][x.slot])
                if x.count > keepHere then surplus[#surplus + 1] = { tab = x.tab, slot = x.slot, amount = x.count - keepHere, well = well } end
            end
            -- reserved stacks, in order: an empty slot or a stack of the item gets what it lacks, an occupied slot waits
            for _, a in ipairs(allocs) do
                if not a.gate then
                    local cell = sim[a.tab].slots[a.slot]
                    local have = (cell and cell.id == id and cell.count) or 0
                    local need = a.count - have
                    if need > 0 and (cell == nil or (cell.id == id and not cell.locked)) then
                        local first = cell == nil
                        while need > 0 do
                            local pick = PickPiece(surplus, need, "amount")
                            if not pick then break end
                            local amount = math.min(pick.amount, need)
                            Move(pick, a.tab, a.slot, amount, first, a.rule)
                            pick.amount, need, first = pick.amount - amount, need - amount, false
                        end
                    end
                end
            end
            -- what a blocked reserved slot is waiting for (another item in it, or locked) stays put: it is not an extra
            local earmark = 0
            for _, a in ipairs(allocs) do
                if not a.gate then
                    local cell = sim[a.tab].slots[a.slot]
                    local have = (cell and cell.id == id and cell.count) or 0
                    if have < a.count and cell and (cell.id ~= id or cell.locked) then earmark = earmark + (a.count - have) end
                end
            end
            for _, p in ipairs(surplus) do
                if earmark > 0 and p.amount > 0 and not p.well then p.held, earmark = true, earmark - p.amount end
            end
            -- the extras: into a stack of the item with room, else a free slot, of the tab that takes them
            local extraMoved = 0
            for _, p in ipairs(surplus) do
                if p.amount > 0 and not p.well and not p.held then
                    if ovrReady then
                        local T = ovr.tab
                        local simT = sim[T]
                        local target, isNew
                        if maxStack > 1 then
                            for s = 1, SLOTS do
                                local c = simT.slots[s]
                                if c and c.id == id and c.count and not c.locked and not (reserved[T] and reserved[T][s]) and c.count + p.amount <= maxStack
                                    and not (T == p.tab and s == p.slot) then target = s break end
                            end
                        end
                        if not target then target, isNew = FreeSlot(simT, reserved[T]), true end
                        if target then
                            extraMoved = extraMoved + p.amount
                            Move(p, T, target, p.amount, isNew, ovr.rule)
                            p.amount = 0
                        else
                            p.blocked = true
                            waiting = true
                        end
                    else
                        p.stuck = true
                    end
                end
            end
            -- where each reserved stack ended up
            for _, a in ipairs(allocs) do
                if not a.gate then
                    local cell = sim[a.tab].slots[a.slot]
                    a.have = (cell and cell.id == id and cell.count) or 0
                    a.occupant = (cell and cell.id ~= id) and cell or nil
                    if a.occupant then a.state, a.code = "blocked", "slot-taken"
                    elseif cell and cell.locked and a.have < a.count then a.state, a.code = "blocked", "locked"
                    elseif a.have < a.count then a.state, a.code = "short", nil
                    else a.state, a.code = "ok", nil end
                    if a.state == "blocked" then waiting = true end
                end
            end
            if waiting and not final then return false, made end

            -- settled: record the reserved stacks and what is left over
            for _, a in ipairs(allocs) do
                if a.gate then
                    Result(a, id, facts, 0, a.gate[1], a.gate[2], a.gate[3])
                elseif a.state == "blocked" and a.code == "slot-taken" then
                    local why = Text("slot-taken", a.slot, ItemName(id, facts), a.occupant.id and ItemName(a.occupant.id, opts.facts and (opts.facts(a.occupant.id))) or "something the game didn't identify")
                    Result(a, id, facts, a.have, "blocked", "slot-taken", why)
                    Blocked(a.tab, a.slot, why)
                elseif a.state == "blocked" then
                    Result(a, id, facts, a.have, "blocked", a.code, Text(a.code))
                    Blocked(a.tab, a.slot, Text(a.code))
                else
                    Result(a, id, facts, a.have, a.state)
                end
            end
            local stuck, blockedQty = 0, 0
            if extraMoved > 0 then design.overflow[#design.overflow + 1] = { id = id, tab = ovr.tab, qty = extraMoved, state = "placed" } end
            for _, p in ipairs(surplus) do
                if p.amount > 0 and not p.well then
                    local cell = sim[p.tab].slots[p.slot]
                    if cell then
                        if p.blocked then
                            blockedQty = blockedQty + p.amount
                            local why = Text("tab-full", ovr.tab, 1) .. ". " .. Text("needs-space")
                            Hold({ tab = p.tab, slot = p.slot, cell = cell, facts = facts }, "needs-space", p.amount, ovr.rule, why, { tabNeeded = ovr.tab })
                        elseif p.stuck then
                            stuck = stuck + p.amount
                        end
                    end
                end
            end
            if stuck > 0 then
                if not ovr then
                    local text = Text("extras-ambiguous")
                    design.overflow[#design.overflow + 1] = { id = id, qty = stuck, state = "unmanaged", code = "extras-ambiguous", text = text }
                    for _, p in ipairs(surplus) do
                        if p.stuck and p.amount > 0 and sim[p.tab].slots[p.slot] then
                            Hold({ tab = p.tab, slot = p.slot, cell = sim[p.tab].slots[p.slot], facts = facts }, "extras-ambiguous", p.amount, it.rule, text)
                        end
                    end
                else
                    local code = ovr.st.status == "unknown" and "rule-unknown" or "rule-blocked"
                    local text = Text(code, ovr.rule.name, ovr.st.why or "")
                    design.overflow[#design.overflow + 1] = { id = id, tab = ovr.tab, qty = stuck, state = "unmanaged", code = code, text = text }
                    for _, p in ipairs(surplus) do
                        if p.stuck and p.amount > 0 and sim[p.tab].slots[p.slot] then
                            Hold({ tab = p.tab, slot = p.slot, cell = sim[p.tab].slots[p.slot], facts = facts }, code, p.amount, ovr.rule, text)
                        end
                    end
                end
            end
            info.state = (blockedQty > 0 and (info.placed > 0 and "partial" or "blocked")) or (info.placed > 0 and "moves") or "inplace"
            if blockedQty > 0 then info.blocked, info.code = blockedQty, "needs-space" end
            return true, made
        end

        -- one pass over an item: what it needs, using only what is free now. Returns true when it is settled
        -- (done or impossible) and false when it waits for room another item may free.
        local function Settle(it, final)
            if it.owners then return SettleDesign(it, final) end
            local rule, T, facts, id = it.rule, it.st.tab, it.facts, it.id
            local simTab = sim[T]
            local S, tcode, limit = TargetFor(rule, facts)
            local info = it.info
            if not info then
                info = { id = id, facts = facts, rule = rule.name, ruleId = rule.id, tab = T, qty = 0, source = "bank", ops = 0, placed = 0, target = S }
                it.info = info
                for _, x in ipairs(it.stacks) do info.qty = info.qty + x.cell.count end
                AddItem(info)
            end
            if tcode then
                info.state, info.code, info.why = "blocked", tcode, Text(tcode, limit, rule.stack)
                for _, x in ipairs(it.stacks) do Hold(x, tcode, x.cell.count, rule, info.why) end
                return true
            end
            -- the item's stacks as they are now in the simulated bank
            local cur = {}
            for _, x in ipairs(it.stacks) do
                local c = sim[x.tab].slots[x.slot]
                if c and c.id == id and c.count and c.count > 0 then cur[#cur + 1] = { tab = x.tab, slot = x.slot, count = c.count } end
            end
            local maxStack = math.max(1, facts.maxStack or 1)
            local tabT = bank.tabs[T]
            local made = 0
            local function Move(from, toSlot, amount, isNew)
                local srcCell = sim[from.tab].slots[from.slot]
                local needSplit = amount < srcCell.count
                local op = Op({ kind = isNew and "move" or "merge", id = id, count = amount, from = { kind = "bank", tab = from.tab, slot = from.slot },
                    to = { tab = T, slot = toSlot }, rule = rule.name, ruleId = rule.id, split = needSplit or nil,
                    needs = { needSplit and "split" or nil, "withdraw:" .. from.tab, "deposit:" .. T }, link = srcCell.link })
                srcCell.count = srcCell.count - amount
                if srcCell.count == 0 then sim[from.tab].slots[from.slot] = nil end
                local dest = simTab.slots[toSlot]
                if dest then dest.count = dest.count + amount
                else simTab.slots[toSlot] = { id = id, count = amount, icon = srcCell.icon, link = srcCell.link, quality = srcCell.quality, added = true } end
                made = made + 1
                info.ops, info.placed = info.ops + 1, info.placed + amount
                local where = from.tab == T and ("slot " .. from.slot) or ("tab " .. from.tab .. ", slot " .. from.slot)
                Why(T, toSlot, ("%s %d from %s (\"%s\")"):format(isNew and "Receives" or "Adds", amount, where, rule.name))
                Why(from.tab, from.slot, ("%d %s %s (\"%s\")"):format(amount, "go to tab", T .. ", slot " .. toSlot, rule.name))
                if op.status == "blocked" then Blocked(T, toSlot, op.why); Blocked(from.tab, from.slot, op.why) end
            end

            if S == nil or maxStack <= 1 then
                -- no target: every stack outside the tab moves, whole, to a free slot; stacks already there stay
                local unplaced = 0
                for _, x in ipairs(cur) do
                    if x.tab ~= T then
                        local free = FreeSlot(simTab, reserved[T])
                        if free then Move(x, free, x.count, true) else unplaced = unplaced + x.count end
                    end
                end
                if unplaced > 0 then
                    if not final then return false, made end
                    info.state, info.code, info.blocked = (made > 0 and "partial" or "blocked"), "needs-space", unplaced
                    info.why = Text("tab-full", T, unplaced) .. ". " .. Text("needs-space")
                    for _, x in ipairs(cur) do
                        if x.tab ~= T and sim[x.tab].slots[x.slot] then Hold({ tab = x.tab, slot = x.slot, cell = sim[x.tab].slots[x.slot], facts = facts }, "needs-space", x.count, rule, info.why, { tabNeeded = T }) end
                    end
                    return true, made
                end
                info.state = made > 0 and "moves" or "inplace"
                return true, made
            end

            -- a target: the final stacks are floor(total / S) of S and one smaller; reuse the stacks already in the tab
            local total = 0
            for _, x in ipairs(cur) do total = total + x.count end
            local finals = {}
            for _ = 1, math.floor(total / S) do finals[#finals + 1] = S end
            if total % S > 0 then finals[#finals + 1] = total % S end
            local anchors = {}
            for _, x in ipairs(cur) do if x.tab == T then anchors[#anchors + 1] = x end end
            table.sort(anchors, function(a, b) return a.slot < b.slot end)
            local want, usedAnchor, usedFinal = {}, {}, {}
            for ai, a in ipairs(anchors) do   -- stacks already the right size stay
                for fi, size in ipairs(finals) do
                    if not usedFinal[fi] and size == a.count then want[a.slot], usedAnchor[ai], usedFinal[fi] = size, true, true break end
                end
            end
            local restAnchors = {}
            for ai, a in ipairs(anchors) do if not usedAnchor[ai] then restAnchors[#restAnchors + 1] = a end end
            table.sort(restAnchors, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.slot < b.slot
            end)
            local restFinals = {}
            for fi, size in ipairs(finals) do if not usedFinal[fi] then restFinals[#restFinals + 1] = size end end
            for i, a in ipairs(restAnchors) do want[a.slot] = restFinals[i] or 0 end
            local newStacks = {}
            for i = #restAnchors + 1, #restFinals do newStacks[#newStacks + 1] = restFinals[i] end

            -- do the stacks need anything at all?
            local needsWork = #newStacks > 0
            for _, a in ipairs(anchors) do if want[a.slot] ~= a.count then needsWork = true end end
            for _, x in ipairs(cur) do if x.tab ~= T then needsWork = true end end
            if not needsWork then
                info.state = "inplace"
                return true, 0
            end
            -- room for the new stacks, right now
            if #newStacks > FreeCount(simTab, reserved[T]) then
                if not final then return false, 0 end
                info.state, info.code, info.blocked = "blocked", "needs-space", total
                info.why = Text("tab-full", T, #newStacks - FreeCount(simTab, reserved[T])) .. ". " .. Text("needs-space")
                for _, x in ipairs(cur) do Hold({ tab = x.tab, slot = x.slot, cell = sim[x.tab].slots[x.slot], facts = facts }, "needs-space", x.count, rule, info.why, { tabNeeded = T }) end
                return true, 0
            end
            -- the slots: anchors' own, then the first free ones
            local slotsOf = {}   -- deficits: { slot, need, isNew }
            for _, a in ipairs(anchors) do
                local w = want[a.slot] or 0
                if w > a.count then slotsOf[#slotsOf + 1] = { slot = a.slot, need = w - a.count, isNew = false } end
            end
            for _, size in ipairs(newStacks) do
                local free = FreeSlot(simTab, reserved[T])
                -- reserve it now so the next new stack takes the next free slot
                simTab.slots[free] = { id = id, count = 0, reserved = true, icon = facts.icon }
                slotsOf[#slotsOf + 1] = { slot = free, need = size, isNew = true }
            end
            -- the surplus: every stack outside the tab, and what an anchor holds above its wanted size
            local surplus = {}
            for _, x in ipairs(cur) do
                local keepHere = (x.tab == T) and (want[x.slot] or 0) or 0
                if x.count > keepHere then surplus[#surplus + 1] = { tab = x.tab, slot = x.slot, amount = x.count - keepHere } end
            end
            table.sort(slotsOf, function(a, b)
                if a.isNew ~= b.isNew then return not a.isNew end
                return a.slot < b.slot
            end)
            for _, d in ipairs(slotsOf) do
                local need = d.need
                local first = d.isNew
                while need > 0 do
                    local pick = PickPiece(surplus, need, "amount")
                    if not pick then break end
                    local amount = math.min(pick.amount, need)
                    if first then simTab.slots[d.slot] = nil end   -- the reservation gives way to the real stack
                    Move(pick, d.slot, amount, first)
                    pick.amount = pick.amount - amount
                    need = need - amount
                    first = false
                end
            end
            -- stacks below the target that nothing could fill keep a placeholder out of the cells
            for _, d in ipairs(slotsOf) do
                local c = simTab.slots[d.slot]
                if c and c.reserved then simTab.slots[d.slot] = nil end
            end
            info.state = "moves"
            return true, made
        end

        local pending = {}
        for _, it in ipairs(order) do pending[#pending + 1] = it end
        local passes = 0
        while #pending > 0 and passes <= #order + 1 do
            passes = passes + 1
            local nextPending, progress = {}, false
            for _, it in ipairs(pending) do
                local done, made = Settle(it, false)
                if done then progress = true else nextPending[#nextPending + 1] = it end
                if made and made > 0 then progress = true end
            end
            pending = nextPending
            if not progress then break end
        end
        for _, it in ipairs(pending) do Settle(it, true) end
        -- a stack that ended in the wanted place needs no explanation beyond "already as wanted"
        for _, it in ipairs(order) do
            if it.info and it.info.state == "inplace" then
                for _, x in ipairs(it.stacks) do
                    local c = sim[x.tab] and sim[x.tab].slots[x.slot]
                    if c then Why(x.tab, x.slot, Text("inplace")) end
                end
            end
        end
    end

    ---------------------------------------------------------------- limits and constraints
    -- a tab whose allowance for today is known (only the tab being shown) can't give more stacks than it has left
    local pickups = {}
    for _, o in ipairs(plan.ops) do
        if o.from and o.from.kind == "bank" then
            local t = bank.tabs[o.from.tab]
            if t and t.remaining and t.remaining >= 0 then
                pickups[o.from.tab] = (pickups[o.from.tab] or 0) + 1
                if pickups[o.from.tab] > t.remaining and o.status == "ok" then
                    o.status, o.code, o.why = "blocked", "limit", Text("limit", o.from.tab, t.remaining)
                    Blocked(o.to.tab, o.to.slot, o.why); Blocked(o.from.tab, o.from.slot, o.why)
                end
            end
        end
    end

    ---------------------------------------------------------------- the tabs, cell by cell
    -- the counts: stacks in the preview's scope (the carried bags for a deposit, the occupied slots of the tabs read for a
    -- reorganize) that move, are held back by something, can't be told, or stay as they are
    local summary = { ops = #plan.ops, splits = 0, blockedOps = 0, eligible = 0, moved = 0, blocked = 0, unknown = 0, unchanged = 0,
        blockedQty = 0, unknownQty = 0 }
    local movedFrom = {}
    for _, o in ipairs(plan.ops) do
        if o.split then summary.splits = summary.splits + 1 end
        if o.status == "blocked" then summary.blockedOps = summary.blockedOps + 1 end
        local k = o.from and (o.from.kind == "bag" and ("b" .. o.from.bag .. ":" .. o.from.slot) or ("g" .. o.from.tab .. ":" .. o.from.slot))
        if k and not movedFrom[k] then movedFrom[k] = true; summary.moved = summary.moved + 1 end
    end
    for _, it in ipairs(plan.items) do summary.eligible = summary.eligible + (it.qty or 0) end
    for _, u in ipairs(plan.untouched) do
        local rs = u.ruleId and state[u.ruleId]
        if u.reason == "attention" then u.class = (rs and rs.status == "unknown") and "unknown" or "blocked"
        elseif MI.GUNKNOWN[u.reason] then u.class = "unknown"
        elseif MI.GBLOCKED[u.reason] then u.class = "blocked"
        else u.class = "left" end
        local n = u.stacks or 1
        if u.class == "blocked" then summary.blocked, summary.blockedQty = summary.blocked + n, summary.blockedQty + (u.count or 0)
        elseif u.class == "unknown" then summary.unknown, summary.unknownQty = summary.unknown + n, summary.unknownQty + (u.count or 0) end
    end
    local scope = mode == "deposit" and #(opts.stacks or {}) or scopeCount
    summary.scope = scope
    summary.unchanged = math.max(0, scope - summary.moved - summary.blocked - summary.unknown)
    -- the arrangement: reserved stacks filled, short, blocked or unknown; extras placed or left; rules that don't win
    -- the stacks an automatic layout made are reported as extras placed (per item and tab), not as stacks the player reserved
    local autoPlaced, autoOrder = {}, {}
    local reservedN = 0
    for _, a in ipairs(design.allocs) do
        if a.auto then
            if a.state == "ok" and a.have > 0 then
                local k = a.tab .. ":" .. a.id
                if not autoPlaced[k] then autoPlaced[k] = { id = a.id, tab = a.tab, qty = 0, state = "placed", auto = true }; autoOrder[#autoOrder + 1] = k end
                autoPlaced[k].qty = autoPlaced[k].qty + a.have
            end
        else
            reservedN = reservedN + 1
        end
    end
    for _, k in ipairs(autoOrder) do design.overflow[#design.overflow + 1] = autoPlaced[k] end
    local dsum = { reserved = reservedN, filled = 0, short = 0, shortQty = 0, blocked = 0, unknown = 0, extrasPlaced = 0, extrasLeft = 0,
        conflicts = #design.conflicts }
    for _, a in ipairs(design.allocs) do
        if a.state == "ok" then if not a.auto then dsum.filled = dsum.filled + 1 end
        elseif a.state == "short" then dsum.short, dsum.shortQty = dsum.short + 1, dsum.shortQty + a.short
        elseif a.state == "blocked" then dsum.blocked = dsum.blocked + 1
        else dsum.unknown = dsum.unknown + 1 end
    end
    for _, o in ipairs(design.overflow) do
        if o.state == "placed" then dsum.extrasPlaced = dsum.extrasPlaced + o.qty else dsum.extrasLeft = dsum.extrasLeft + o.qty end
    end
    table.sort(design.allocs, function(a, b)
        if a.tab ~= b.tab then return a.tab < b.tab end
        return a.slot < b.slot
    end)
    summary.design = dsum
    local unread = {}
    for i = 1, bank.numTabs or 0 do
        local t = bank.tabs[i]
        local view = { tab = i, name = t and t.name, icon = t and t.icon, state = t and t.state or "unread", age = t and t.age,
            viewable = t and t.viewable, canDeposit = t and t.canDeposit, canWithdraw = t and t.canWithdraw, remaining = t and t.remaining }
        if t and t.slots and sim[i] then
            view.current, view.proposed = {}, {}
            local changed = false
            for s = 1, SLOTS do
                local a, b = t.slots[s], sim[i].slots[s]
                local ca, cb
                if a then
                    ca = CopyCell(a)
                    ca.why = why[i] and why[i][s]
                end
                if b then
                    cb = CopyCell(b)
                    cb.icon = b.icon or (a and a.icon)
                    cb.why = why[i] and why[i][s]
                end
                if cb and not a then cb.change = "added"; changed = true
                elseif cb and a and cb.count ~= a.count then cb.change = "changed"; cb.was = a.count; changed = true
                elseif a and not cb then ca.change = "leaves"; changed = true end
                local dz = designAt[i] and designAt[i][s]
                if dz then
                    -- a reserved stack: what the arrangement wants there, beside what the plan puts there
                    if not cb and dz.state ~= "unknown" and dz.state ~= "blocked" then
                        cb = { id = dz.id, count = 0, icon = dz.icon, ghost = true }
                    end
                    if cb and cb.id == dz.id then
                        cb.want, cb.reserved = dz.want, true
                        cb.short = dz.short > 0 and dz.short or nil
                        cb.why = why[i] and why[i][s]
                    end
                end
                local mark = blockedAt[i] and blockedAt[i][s]
                if mark then
                    if ca and not ca.change then ca.blocked, ca.unknown = mark.text, mark.unknown or ca.unknown end
                    if cb then cb.blocked, cb.unknown = mark.text, mark.unknown or cb.unknown end
                end
                view.current[s], view.proposed[s] = ca, cb
            end
            view.changed = changed
            local used = 0
            for s = 1, SLOTS do if sim[i].slots[s] then used = used + 1 end end
            view.free = SLOTS - used
            local usedNow = 0
            for _ in pairs(t.slots) do usedNow = usedNow + 1 end
            view.freeNow = SLOTS - usedNow
            if bank.open ~= true then view.note = "Read when the guild bank was last open" end
        else
            unread[#unread + 1] = i
            view.note = (t and t.viewable == false) and "Your rank can't see this tab" or "Not read yet: show this tab in the guild bank"
        end
        plan.tabs[i] = view
    end
    -- what is held back at each tab, said at the tab (the full list is plan.untouched)
    for _, u in ipairs(plan.untouched) do
        if u.class and u.class ~= "left" then
            local st = u.ruleId and state[u.ruleId]
            local tab = u.tab or u.tabNeeded or (st and st.tab)
            local view = tab and plan.tabs[tab]
            if view then
                view.issues = view.issues or {}
                if #view.issues < 4 then
                    view.issues[#view.issues + 1] = ("%s%s: %s"):format(ItemName(u.id, u.facts), (u.count and u.count > 0) and (" \195\151" .. u.count) or "", u.text or "")
                elseif #view.issues == 4 then
                    view.issues[5] = "... and more (see Held back or left alone below)"
                end
            end
        end
    end
    plan.numTabs = bank.numTabs
    plan.summary = summary
    plan.unreadTabs = unread

    -- how current it is: a tab that is shown now is live; the rest were read earlier
    local involved, live, earlier = {}, 0, 0
    for _, r in ipairs(plan.rules) do if r.tab then involved[r.tab] = true end end
    if mode == "reorganize" then
        for i, v in pairs(plan.tabs) do if v.current then involved[i] = true end end
    end
    for i in pairs(involved) do
        local t = bank.tabs[i]
        if t and t.state == "live" then live = live + 1 elseif t and t.slots then earlier = earlier + 1 end
    end
    -- live: every tab involved is shown now; mixed: some are; earlier: the bank is open but shows another tab, and the tabs
    -- involved were read before; stale: the bank is closed, or nothing involved was read
    if bank.open ~= true or (live == 0 and earlier == 0) then plan.freshness = "stale"
    elseif live == 0 then plan.freshness = "earlier"
    elseif earlier > 0 then plan.freshness = "mixed"
    else plan.freshness = "live" end
    if next(involved) == nil then plan.freshness = bank.open == true and "live" or "stale" end

    plan.constraints[#plan.constraints + 1] = { code = "unverified", text = "Moving, splitting and merging stacks in a guild bank hasn't been checked on this client, so none of this is a promise that it can be carried out." }
    if mode == "reorganize" then
        local cross = false
        for _, o in ipairs(plan.ops) do if o.from and o.from.kind == "bank" and o.from.tab ~= o.to.tab then cross = true end end
        if cross then
            plan.constraints[#plan.constraints + 1] = { code = "withdraw-count", text = "A move between tabs may count against your rank's daily withdrawal allowance. The game only reports that allowance for the tab being shown." }
        end
        if #unread > 0 then
            plan.constraints[#plan.constraints + 1] = { code = "tabs-unread", text = "Tabs not read: " .. table.concat(unread, ", ") .. ". Items there are not part of this preview." }
        end
    end
    if #design.allocs > 0 then
        plan.constraints[#plan.constraints + 1] = { code = "design-target", text = "A reserved quantity is a target, not an order: nothing is bought, withdrawn from unrelated places, sold or discarded to reach it, and what is missing stays missing." }
    end
    plan.constraints[#plan.constraints + 1] = { code = "no-swaps", text = "Swapping two stacks, or parking one in your bags, is not used: a stack goes where there is a free slot or a stack with room at that moment." }
    return plan
end

---------------------------------------------------------------------------
-- The plan for what the game shows now, with the settings as they are, or (override) with the rules of an arrangement that
-- hasn't been saved: override = { rules = the rule list, virtual = { [destId] = where } } from Design.PreviewRules.
---------------------------------------------------------------------------
function MI.CurrentGuildPlan(mode, override)
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.guildPlan")
    local guildNow = false
    if GetGuildInfo and IsInGuild then
        if IsInGuild() then
            local name = MI.Plain((GetGuildInfo("player")))
            guildNow = type(name) == "string" and name ~= "" and name or false
        else
            guildNow = nil
        end
    end
    local RS = R.Restock
    local stacks
    if mode ~= "reorganize" then stacks = MI.ReadBags().stacks end
    local virtual = override and override.virtual or {}
    local plan = MI.BuildGuildPlan({
        mode = mode, rules = override and override.rules or MI.Rules(), never = MI.IsNever,
        resolve = function(id) return virtual[id] or MI.Resolve(id) end,
        stacks = stacks,
        facts = function(id) return MI.ItemFacts(id) end,
        problem = function(rule)
            local v = rule.dest and virtual[rule.dest]
            if v then
                if not MI.HasItems(rule) then return "no-items", "Choose which items it is for." end
                if guildNow ~= false and (guildNow == nil or guildNow ~= v.guild) then
                    return "guild-changed", ("This arrangement is for <%s>; this character is in %s now."):format(v.guild, guildNow and ("<" .. guildNow .. ">") or "no guild")
                end
                return nil
            end
            return MI.Problem(rule, guildNow)
        end,
        guildNow = guildNow, bank = MI.GuildBank and MI.GuildBank.Snapshot() or { tabs = {} },
        keepExtra = function(id)
            if not (RS and RS.Protects and RS.Protects(id) and RS.Rule) then return 0 end
            local rule = RS.Rule(id)
            return rule and rule.target or 0
        end,
        split = MI.GuildRun ~= nil and MI.GuildRun.CAN_SPLIT == true,   -- the arrangement's own run splits (GuildRun.lua); the older whole-stack review does not
        generation = MI.Generation(), made = GetTime and GetTime() or 0,
    })
    plan.draft = override ~= nil
    if pt then R.Perf.Stop(pt) end
    return plan
end
