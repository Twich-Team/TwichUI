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
            local owner, shadow, protectedBy = nil, {}, nil
            local keep, keepFrom = 0, nil
            for _, rule in ipairs(rules) do
                if rule.enabled then
                    local m = MI.Match(rule, facts)
                    if m == "matched" or m == "included" then
                        if rule.kind == "never" then
                            protectedBy = protectedBy or rule
                        elseif rule.kind == "keep" then
                            if rule.keep > keep then keep, keepFrom = rule.keep, rule end
                        elseif not owner then
                            owner = rule
                        else
                            shadow[#shadow + 1] = rule
                        end
                    end
                end
            end
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
        problem = function(rule) return MI.Problem(rule, guildNow) end,
        keepExtra = function(id)
            if not (RS and RS.Protects and RS.Protects(id) and RS.Rule) then return 0 end
            local rule = RS.Rule(id)
            return rule and rule.target or 0
        end,
        context = context, split = MI.SPLIT, leftOut = leftOut,
        attach = tonumber(_G.ATTACHMENTS_MAX_SEND) or MI.ATTACH_FALLBACK,
        generation = MI.Generation(), made = GetTime and GetTime() or 0,
    })
    if pt then R.Perf.Stop(pt) end
    return plan
end

-- Partial stacks: off everywhere until splitting is checked on this client (C_Container.SplitContainerItem is
-- documented, but how the mail, bank and guild bank take a split stack isn't verified on Forever).
MI.SPLIT = { mail = false, bank = false, guild = false }
