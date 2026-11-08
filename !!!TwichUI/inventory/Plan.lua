-- TwichUI: Magic Inventory, the plan
-- What would move, where, and why the rest stays: one dry run over the carried bags, made only when asked for (a
-- mailbox, bank or guild bank opening with the feature on, the review, the settings' Preview). Pure: it reads only
-- the lists it is given, so the tests can hand it anything; nothing here moves an item.
--
-- The order every item is judged in (docs/magic-inventory.md, "Precedence"):
--   1. Hard protections and the Never transfer list: the account's Never transfer list, any enabled "Never transfer"
--      rule matching it, and, per stack, what the destination can't take or what can't be told (a quest item,
--      conjured, in an equipment set, locked, soulbound for mail and guild banks, binding or lock state unknown).
--      Nothing below overrides these, an "Also include" list included.
--   2. A rule's own "Never include" list: that rule never matches the item.
--   3. A rule's "Also include" list, or its filters (category, quality, equipment, binding): the rule matches.
--   4. Keep amounts: the most any matching rule keeps (its own "keep N of each", a "Keep in bags" rule, and a vendor
--      restocking target), counted over every carried stack of that item; only what is above it may move.
--   5. Where it goes: the destination must be able to take each stack (step 1's per-stack checks).
--   6. Priority: the first enabled rule in the list that moves items owns the item, wherever it sends it. Later
--      matching rules are listed as shadowed. An item is never passed to a later rule, so a mailbox never takes
--      what a bank rule above owns, and an unavailable destination never reroutes anything.
-- Whole stacks only unless the destination can split reliably (opts.split[kind]); a keep amount is never broken to
-- move a full stack: the stacks that would pass it stay, and the plan says how many more than the keep amount stay.

local R = TwichUI
local MI = R.MagicInventory

MI.ATTACH_FALLBACK = 12   -- ATTACHMENTS_MAX_SEND in the Forever MailFrame.lua

MI.REASON = {
    never = "On your Never transfer list",
    ["never-rule"] = "Protected by \"%s\"",
    quest = "A quest item",
    ["quest-unknown"] = "Can't tell whether a quest needs it",
    conjured = "Conjured",
    ["conjured-unknown"] = "Can't tell whether it is conjured",
    ["equipment-set"] = "In an equipment set",
    ["set-unknown"] = "Can't tell whether it is in an equipment set",
    locked = "Locked right now",
    ["lock-unknown"] = "The game didn't say whether it is locked",
    ["binding-unknown"] = "The game didn't say whether it is bound",
    ["bound-mail"] = "Soulbound: mail can't carry it",
    ["bound-guild"] = "Soulbound: a guild bank can't take it",
    ["bound-now"] = "Bound to you now, so it no longer binds when equipped",
    keep = "You keep %d and carry %d",
    pending = "The game is still loading this item",
    attention = "\"%s\" needs attention: %s",
    ["left-out"] = "Left out this time",
    stale = "Changed in your bags since the review",
}

function MI.ReasonText(code, a, b)
    local text = MI.REASON[code] or code
    if a ~= nil then
        local ok, s = pcall(string.format, text, a, b)
        if ok then return s end
    end
    return text
end

-- Can this stack go to a destination of this kind? nil when it can, else a reason code. rule: the owning rule.
function MI.StackProblem(stack, kind, rule)
    if stack.quest == nil then return "quest-unknown" end
    if stack.quest then return "quest" end
    if stack.conjured == true then return "conjured" end
    if stack.conjured == nil then return "conjured-unknown" end
    if stack.inSet == true then return "equipment-set" end
    if stack.inSet == nil then return "set-unknown" end
    if stack.locked == true then return "locked" end
    if stack.locked == nil then return "lock-unknown" end
    if kind == "mail" or kind == "guild" or rule.bind == "boe" then
        if stack.bound == nil then return "binding-unknown" end
        if stack.bound == true then
            if rule.bind == "boe" then return "bound-now" end
            return kind == "mail" and "bound-mail" or "bound-guild"
        end
    end
    return nil
end

-- Who decides what happens to an item: the first enabled rule that moves items out of the bags and matches it (the
-- owner), the later matching transfer rules (shadowed), the first enabled "Never transfer" rule that matches it, and the
-- most any matching rule keeps in the bags (and the rule that says so). A rule that only withdraws never owns an item; it
-- keeps its target in the bags, as every rule that withdraws does, so no other rule sends away what it tops up.
-- Pure; shared by the guild bank planner (GuildPlan.lua).
function MI.Owner(rules, facts)
    local owner, shadow, protectedBy = nil, {}, nil
    local keep, keepFrom = 0, nil
    for _, rule in ipairs(rules) do
        if rule.enabled then
            local m = MI.Match(rule, facts)
            if m == "matched" or m == "included" then
                if MI.Withdraws(rule) and rule.keep > keep then keep, keepFrom = rule.keep, rule end
                if rule.kind == "never" then
                    protectedBy = protectedBy or rule
                elseif rule.kind == "keep" then
                    if rule.keep > keep then keep, keepFrom = rule.keep, rule end
                elseif not MI.Deposits(rule) then   -- luacheck: ignore 542
                    -- it only withdraws: its target is counted above
                elseif not owner then
                    owner = rule
                else
                    shadow[#shadow + 1] = rule
                end
            end
        end
    end
    return owner, shadow, protectedBy, keep, keepFrom
end

local function GroupKey(kind, where, rule)
    if kind == "bank" then return "bank" end
    return kind .. ":" .. (rule.dest or "?")
end

-- opts:
--   stacks      MI.ReadBags().stacks (or test data)
--   rules       MI.Rules()
--   never(id)   on the Never transfer list
--   resolve(destId) -> where (MI.Resolve)
--   problem(rule) -> code, sentence (MI.Problem, with the guild as it is now)
--   keepExtra(id) -> n   another feature's keep amount for the item (vendor restocking's target)
--   context     "mail", "bank", "guild", or nil for everything (the settings' preview)
--   split       { [kind] = true } where a partial stack can be moved
--   leftOut     { [entryKey] = true }: left out of this operation by the player (the rule is unchanged)
--   attach      attachments a mail can hold
-- Returns the plan (see the end of this function).
function MI.BuildPlan(opts)
    local rules = opts.rules or {}
    local split = opts.split or {}
    local leftOut = opts.leftOut or {}
    local attach = math.max(1, math.floor(tonumber(opts.attach) or MI.ATTACH_FALLBACK))
    local plan = { groups = {}, reserved = {}, skipped = {}, shadowed = {}, attention = {}, pending = 0,
        context = opts.context, generation = opts.generation, stacks = 0, items = 0, made = opts.made }
    local groupsByKey = {}
    local attentionSeen = {}

    -- the stacks of each item, in the order they are first met in the bags
    local order, byId = {}, {}
    for _, s in ipairs(opts.stacks or {}) do
        local list = byId[s.id]
        if not list then list = {}; byId[s.id] = list; order[#order + 1] = s.id end
        list[#list + 1] = s
    end

    local function Skip(id, facts, reason, count, stacks, rule, text)
        plan.skipped[#plan.skipped + 1] = { id = id, facts = facts, reason = reason, count = count, stacks = stacks,
            rule = rule and rule.name, ruleId = rule and rule.id, text = text or MI.ReasonText(reason) }
    end

    local problems = {}
    local function Problem(rule)
        local p = problems[rule.id]
        if p == nil then
            local code, why
            if opts.problem then code, why = opts.problem(rule) end
            p = code and { code = code, why = why } or false
            problems[rule.id] = p
        end
        return p or nil
    end

    for _, id in ipairs(order) do
        local list = byId[id]
        local facts
        for _, s in ipairs(list) do
            if not s.facts then facts = nil break end
            facts = s.facts
        end
        local total = 0
        for _, s in ipairs(list) do total = total + (s.count or 0) end

        if not facts then
            plan.pending = plan.pending + 1
            Skip(id, nil, "pending", total, #list)
        else
            -- who matches: transfer rules in priority order, protections and keep amounts from every rule
            local owner, shadow, protectedBy, keep, keepFrom = MI.Owner(rules, facts)
            if owner then
                if owner.keep > keep then keep, keepFrom = owner.keep, owner end
                local extra = opts.keepExtra and tonumber(opts.keepExtra(id)) or 0
                if extra > keep then keep, keepFrom = extra, nil end
                for _, rule in ipairs(shadow) do
                    plan.shadowed[#plan.shadowed + 1] = { id = id, facts = facts, rule = rule.name, ruleId = rule.id, by = owner.name, byId = owner.id }
                end
            end

            -- no owner: nothing would move it, which is not this feature's business, and it isn't listed
            if not owner then -- luacheck: ignore 542
            elseif opts.never and opts.never(id) then
                Skip(id, facts, "never", total, #list, owner)
            elseif protectedBy then
                Skip(id, facts, "never-rule", total, #list, owner, MI.ReasonText("never-rule", protectedBy.name))
            elseif opts.context and owner.kind ~= opts.context then
                plan.reserved[#plan.reserved + 1] = { id = id, facts = facts, count = total, stacks = #list, rule = owner.name,
                    ruleId = owner.id, kind = owner.kind }
            else
                local p = Problem(owner)
                if p then
                    if not attentionSeen[owner.id] then
                        attentionSeen[owner.id] = true
                        plan.attention[#plan.attention + 1] = { ruleId = owner.id, rule = owner.name, code = p.code, why = p.why }
                    end
                    Skip(id, facts, "attention", total, #list, owner, MI.ReasonText("attention", owner.name, p.why))
                else
                    local where = opts.resolve and owner.dest and opts.resolve(owner.dest) or nil
                    -- per stack: what this destination can take
                    local eligible, kept = {}, {}
                    for _, s in ipairs(list) do
                        local why = MI.StackProblem(s, owner.kind, owner)
                        if why then kept[why] = kept[why] or { count = 0, stacks = 0 }
                            kept[why].count, kept[why].stacks = kept[why].count + s.count, kept[why].stacks + 1
                        else eligible[#eligible + 1] = s end
                    end
                    for why, k in pairs(kept) do Skip(id, facts, why, k.count, k.stacks, owner) end

                    if #eligible > 0 then
                        local budget = total - keep
                        if budget <= 0 then
                            local n = 0
                            for _, s in ipairs(eligible) do n = n + s.count end
                            Skip(id, facts, "keep", n, #eligible, keepFrom or owner, MI.ReasonText("keep", keep, total))
                        else
                            table.sort(eligible, function(a, b)
                                if a.count ~= b.count then return a.count > b.count end
                                if a.bag ~= b.bag then return a.bag < b.bag end
                                return a.slot < b.slot
                            end)
                            local take, moved, leftover = {}, 0, 0
                            for _, s in ipairs(eligible) do
                                if s.count <= budget then
                                    take[#take + 1] = { stack = s, count = s.count }
                                    budget, moved = budget - s.count, moved + s.count
                                elseif budget > 0 and split[owner.kind] then
                                    take[#take + 1] = { stack = s, count = budget, partial = true }
                                    moved, budget = moved + budget, 0
                                else
                                    leftover = leftover + s.count
                                end
                            end
                            local key = GroupKey(owner.kind, where, owner)
                            local entryKey = key .. "|" .. id
                            local entry = { key = entryKey, id = id, facts = facts, rule = owner.name, ruleId = owner.id,
                                keep = keep, keepFrom = keepFrom and keepFrom.name, carried = total, take = take,
                                count = moved, stacks = #take, leftOut = leftOut[entryKey] or nil,
                                -- how many more than the keep amount stay because only whole stacks move
                                extraKept = (leftover > 0 and budget > 0) and budget or nil }
                            if #take == 0 then
                                Skip(id, facts, "keep", leftover, #eligible, keepFrom or owner,
                                    ("Only whole stacks move, and moving any would leave fewer than %d"):format(keep))
                            else
                                local g = groupsByKey[key]
                                if not g then
                                    g = { key = key, kind = owner.kind, where = where, entries = {}, stacks = 0, items = 0 }
                                    groupsByKey[key] = g
                                    plan.groups[#plan.groups + 1] = g
                                end
                                g.entries[#g.entries + 1] = entry
                                if not entry.leftOut then
                                    g.stacks, g.items = g.stacks + #take, g.items + moved
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- mail: batches of at most `attach` stacks, one recipient each, in the entries' order
    for _, g in ipairs(plan.groups) do
        plan.stacks, plan.items = plan.stacks + g.stacks, plan.items + g.items
        if g.kind == "mail" then
            g.batches = {}
            local batch
            for _, e in ipairs(g.entries) do
                if not e.leftOut then
                    for _, t in ipairs(e.take) do
                        if not batch or #batch >= attach then batch = {}; g.batches[#g.batches + 1] = batch end
                        batch[#batch + 1] = { id = e.id, entry = e, stack = t.stack, count = t.count, partial = t.partial,
                            bag = t.stack.bag, slot = t.stack.slot, link = t.stack.link }
                    end
                end
            end
            g.mails = #g.batches
        else
            g.steps = {}
            for _, e in ipairs(g.entries) do
                if not e.leftOut then
                    for _, t in ipairs(e.take) do
                        g.steps[#g.steps + 1] = { id = e.id, entry = e, stack = t.stack, count = t.count, partial = t.partial,
                            bag = t.stack.bag, slot = t.stack.slot, link = t.stack.link }
                    end
                end
            end
        end
    end
    return plan
end

---------------------------------------------------------------------------
-- Withdrawing: what rules that withdraw would take out of a bank to top the bags up. Pure.
-- For each item the bank holds, the first enabled rule of this kind that withdraws and matches it decides (for a guild
-- bank: only from that rule's tab). It tops the carried amount up to the rule's keep amount (its target), never past it:
-- whole stacks only, largest first while they fit. Protections: the Never transfer list and an enabled "Never transfer"
-- rule (nothing on them is moved either way), the rule's own Never include list, a locked stack, or one the game didn't
-- describe. Unlike a deposit, a soulbound item may come out of your own bank. What can't be reached says why.
-- opts:
--   kind        "bank" or "guild"
--   source      the bank's stacks: { id, count, facts, locked, bound, bag, slot } (bank) or { id, count, facts, locked, tab, slot } (guild)
--   carried     the carried bags' stacks (MI.ReadBags().stacks)
--   rules, never(id), problem(rule) -> code, why, resolve(destId) -> where (guild: the rule's tab)
--   leftOut     { [entryKey] = true }
-- Returns { entries = { entry, ... }, skipped = { ... }, attention = { ... }, stacks, items } where an entry is
--   { key, id, facts, rule, ruleId, target, carried, take = { { stack, count } }, count, stacks, short, shortWhy, tab, leftOut }.
---------------------------------------------------------------------------
MI.WREASON = {
    ["w-enough"] = "You carry %d, and the target is %d",
    ["w-none"] = "None of it is in %s",
    ["w-short"] = "%s holds only %d more",
    ["w-whole"] = "Only whole stacks are taken, and the next stack would go over %d",
}

function MI.BuildWithdraw(opts)
    local kind = opts.kind == "guild" and "guild" or "bank"
    local rules = opts.rules or {}
    local leftOut = opts.leftOut or {}
    local out = { entries = {}, skipped = {}, attention = {}, stacks = 0, items = 0, kind = kind }
    local place = kind == "bank" and "your bank" or "that tab"
    local carried = {}
    for _, s in ipairs(opts.carried or {}) do carried[s.id] = (carried[s.id] or 0) + (s.count or 0) end

    local withdrawing = {}
    for _, rule in ipairs(rules) do
        if rule.enabled and rule.kind == kind and MI.Withdraws(rule) then withdrawing[#withdrawing + 1] = rule end
    end
    if #withdrawing == 0 then return out end

    local problems, attentionSeen = {}, {}
    local function Problem(rule)
        local p = problems[rule.id]
        if p == nil then
            local code, why
            if opts.problem then code, why = opts.problem(rule) end
            p = code and { code = code, why = why } or false
            problems[rule.id] = p
        end
        return p or nil
    end
    local function TabOf(rule)
        if kind ~= "guild" then return nil end
        local where = rule.dest and opts.resolve and opts.resolve(rule.dest)
        return where and where.tab
    end
    local function Skip(id, facts, reason, count, rule, text)
        out.skipped[#out.skipped + 1] = { id = id, facts = facts, reason = reason, count = count, rule = rule and rule.name,
            ruleId = rule and rule.id, text = text or MI.ReasonText(reason), withdraw = true }
    end

    -- the bank's stacks of each item, in the order first met
    local order, byId = {}, {}
    for _, s in ipairs(opts.source or {}) do
        if s.id and s.count and s.count > 0 then
            local list = byId[s.id]
            if not list then list = {}; byId[s.id] = list; order[#order + 1] = s.id end
            list[#list + 1] = s
        end
    end

    for _, id in ipairs(order) do
        local list = byId[id]
        local facts = list[1].facts
        if facts then
            -- the deciding rule: the first that withdraws and matches (a stack in its tab, for a guild bank)
            local rule, protectedBy
            for _, r in ipairs(rules) do
                if r.enabled then
                    local m = MI.Match(r, facts, list[1])
                    if (m == "matched" or m == "included") then
                        if r.kind == "never" then protectedBy = protectedBy or r
                        elseif not rule and r.kind == kind and MI.Withdraws(r) then rule = r end
                    end
                end
            end
            if rule then
                local total = 0
                for _, s in ipairs(list) do total = total + s.count end
                local have = carried[id] or 0
                local need = rule.keep - have
                if opts.never and opts.never(id) then
                    Skip(id, facts, "never", total, rule)
                elseif protectedBy then
                    Skip(id, facts, "never-rule", total, rule, MI.ReasonText("never-rule", protectedBy.name))
                elseif Problem(rule) then
                    local p = Problem(rule)
                    if not attentionSeen[rule.id] then
                        attentionSeen[rule.id] = true
                        out.attention[#out.attention + 1] = { ruleId = rule.id, rule = rule.name, code = p.code, why = p.why }
                    end
                elseif need > 0 then
                    local tab = TabOf(rule)
                    local eligible, locked = {}, 0
                    for _, s in ipairs(list) do
                        if kind == "guild" and s.tab ~= tab then   -- luacheck: ignore 542
                            -- another tab: not this rule's
                        elseif s.locked ~= false then locked = locked + s.count
                        else eligible[#eligible + 1] = s end
                    end
                    table.sort(eligible, function(a, b)
                        if a.count ~= b.count then return a.count > b.count end
                        local ka, kb = a.bag or a.tab or 0, b.bag or b.tab or 0
                        if ka ~= kb then return ka < kb end
                        return a.slot < b.slot
                    end)
                    local take, got, avail = {}, 0, 0
                    for _, s in ipairs(eligible) do
                        avail = avail + s.count
                        if got + s.count <= need then
                            take[#take + 1] = { stack = s, count = s.count }
                            got = got + s.count
                        end
                    end
                    local short, shortWhy = need - got, nil
                    if short > 0 then
                        if avail == 0 then shortWhy = MI.ReasonText(locked > 0 and "locked" or "w-none", place)
                        elseif avail - got < short then shortWhy = MI.WREASON["w-short"]:format(place:gsub("^%l", string.upper), avail - got)
                        else shortWhy = MI.WREASON["w-whole"]:format(rule.keep) end
                    end
                    if #take == 0 then
                        Skip(id, facts, "w-short", 0, rule, ("Short by %d: %s"):format(short, shortWhy or ""))
                    else
                        local key = (kind == "bank" and "bank-out" or ("guild-out:" .. tostring(rule.dest))) .. "|" .. id
                        local e = { key = key, id = id, facts = facts, rule = rule.name, ruleId = rule.id, target = rule.keep, carried = have,
                            take = take, count = got, stacks = #take, short = short > 0 and short or nil, shortWhy = shortWhy, tab = tab,
                            leftOut = leftOut[key] or nil }
                        out.entries[#out.entries + 1] = e
                        if not e.leftOut then out.stacks, out.items = out.stacks + #take, out.items + got end
                    end
                end
            end
        end
    end
    return out
end
MI.REASON["w-none"] = MI.WREASON["w-none"]

-- The bank's stacks, read now (only while it is open: its bags can't be trusted otherwise).
function MI.ReadBank()
    local out = {}
    local bags = MI.Run and MI.Run.BankBags and MI.Run.BankBags() or {}
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local s = MI.ReadSlot(bag, slot)
            if s then out[#out + 1] = s end
        end
    end
    return out
end

-- The withdrawals at the bank as a plan group (the review draws it beside the deposits): { kind = "bank", dir = "withdraw", ... }.
local function WithdrawGroup(w)
    local g = { key = "bank-out", kind = "bank", dir = "withdraw", entries = w.entries, stacks = w.stacks, items = w.items, steps = {} }
    for _, e in ipairs(w.entries) do
        if not e.leftOut then
            for _, t in ipairs(e.take) do
                g.steps[#g.steps + 1] = { id = e.id, entry = e, stack = t.stack, count = t.count, bag = t.stack.bag, slot = t.stack.slot,
                    link = t.stack.link, target = e.target, withdraw = true }
            end
        end
    end
    return g
end
MI.WithdrawGroup = WithdrawGroup

-- The plan for what is in the bags now, with the settings as they are: the one place the game is read for a plan.
-- context: "mail", "bank", "guild" or nil. leftOut: entry keys the player removed from this operation.
function MI.CurrentPlan(context, leftOut)
    local pt = R.Perf.on and R.Perf.Start("inventory.plan")
    local bags = MI.ReadBags()
    local guildNow = false
    if GetGuildInfo and IsInGuild then
        if IsInGuild() then
            local name = MI.Plain((GetGuildInfo("player")))
            guildNow = type(name) == "string" and name ~= "" and name or false   -- the roster not in yet: don't judge
        else
            guildNow = nil
        end
    end
    local RS = R.Restock
    local plan = MI.BuildPlan({
        stacks = bags.stacks, rules = MI.Rules(), never = MI.IsNever, resolve = MI.Resolve,
        problem = function(rule)
            -- an arrangement rule says where items belong in a guild bank, slot by slot; nothing here carries that out, so it
            -- never deposits anything: its items are listed as needing attention (and, as everywhere, no lower rule takes them)
            if rule.design then return "design-only", "It belongs to your guild bank arrangement, which is design only: nothing is moved from it." end
            return MI.Problem(rule, guildNow)
        end,
        keepExtra = function(id)
            if not (RS and RS.Protects and RS.Protects(id) and RS.Rule) then return 0 end
            local rule = RS.Rule(id)
            return rule and rule.target or 0
        end,
        context = context, split = MI.SPLIT, leftOut = leftOut,
        attach = tonumber(_G.ATTACHMENTS_MAX_SEND) or MI.ATTACH_FALLBACK,
        generation = MI.Generation(), made = GetTime and GetTime() or 0,
    })
    -- at the bank, what rules that withdraw would take out (the bank's bags are read only while it is open)
    if context == "bank" and MI.Run and MI.Run.IsOpen("bank") then
        local w = MI.BuildWithdraw({ kind = "bank", source = MI.ReadBank(), carried = bags.stacks, rules = MI.Rules(), never = MI.IsNever,
            problem = function(rule) return MI.Problem(rule, guildNow) end, resolve = MI.Resolve, leftOut = leftOut })
        for _, e in ipairs(w.skipped) do plan.skipped[#plan.skipped + 1] = e end
        for _, a in ipairs(w.attention) do
            local seen = false
            for _, x in ipairs(plan.attention) do if x.ruleId == a.ruleId then seen = true end end
            if not seen then plan.attention[#plan.attention + 1] = a end
        end
        if #w.entries > 0 then
            local g = WithdrawGroup(w)
            plan.groups[#plan.groups + 1] = g
            plan.stacks, plan.items = plan.stacks + g.stacks, plan.items + g.items
        end
    end
    if pt then R.Perf.Stop(pt) end
    return plan
end

-- Partial stacks: off everywhere until splitting is checked on this client (C_Container.SplitContainerItem is
-- documented, but how the mail, bank and guild bank take a split stack isn't verified on Forever). The reviews above and Run.lua
-- move whole stacks only. The guild bank arrangement (GuildPlan.lua, run by GuildRun.lua) splits on its own switch,
-- GuildRun.CAN_SPLIT.
MI.SPLIT = { mail = false, bank = false, guild = false }
