-- TwichUI: Magic Inventory, the guild bank arrangement (the model behind the visual editor)
-- A DRAFT of how the player wants a guild bank organised, edited in memory and turned into ordinary guild bank rules only
-- when saved. Pure: nothing here touches the game, a frame or the cursor, and nothing is saved except by Design.Save.
--
-- The draft, per tab of one guild:
--   slots  { [slot] = { id, count } }   reserved stacks: this item, this many, in exactly this slot ("exact" assignments)
--   items  { [id] = true }              the items that belong in the tab (every id with a reserved stack is here too)
--   rest   { [id] = true }              the items whose extras (beyond their reserved stacks) go to this tab's free slots:
--                                       "automatic placement". An item has at most one tab that takes its extras
--   cats   { "7:5", ... }               categories (the game's own) that belong in the tab, placed automatically
-- Saved as ONE guild bank rule per tab, the rule the arrangement editor owns: { design = true, kind = "guild", dest = the
-- tab's destination, include = items, cats = cats, place = { { slot, id, count } ... }, rest = rest } (Rules.lua). The planner
-- (GuildPlan.lua) reads exactly those fields, so there is no second rule engine and no lossy step between the drawing and the
-- rules: Load(Commit(draft)) gives the draft back.
--
-- Every other rule is kept exactly as it is, in its place in the list. A rule the editor can't show faithfully (a quality,
-- binding or equipment filter, a never-include list, a keep amount, a target stack size, a rule for another guild or for a
-- tab that was renamed, a rule that is off...) is "advanced": it is never rewritten, and the editor lists it under Details.
-- New arrangement rules go at the END of the list (the lowest priority); nothing above them is moved. A broader rule above
-- one still wins for the items both match, and Conflicts says so.
--
-- A designed quantity is a target. It never asks for items the player doesn't hold, and never causes anything to be sold,
-- destroyed or discarded: the planner shows what is missing and what is left over.

local R = TwichUI
local MI = R.MagicInventory
local D = {}
MI.Design = D

local SLOTS = MI.GUILD_SLOTS

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function SortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

---------------------------------------------------------------------------
-- The draft
---------------------------------------------------------------------------
local function NewTab() return { slots = {}, items = {}, rest = {}, cats = {} } end

-- names: { [tab] = { name, icon } } (as the guild bank names them), numTabs: how many tabs there are (nil: not known)
function D.New(guild, names, numTabs)
    return { guild = guild, names = names or {}, numTabs = numTabs, tabs = {}, advanced = {}, saved = "", managed = {} }
end

local function TabOf(draft, n, create)
    local t = draft.tabs[n]
    if not t and create then t = NewTab(); draft.tabs[n] = t end
    return t
end

local function ValidTab(draft, n)
    return type(n) == "number" and n == math.floor(n) and n >= 1 and n <= MI.MAX_GUILD_TABS and (draft.numTabs == nil or n <= draft.numTabs)
end

local function TabName(draft, n)
    local v = draft.names[n]
    return v and v.name and ("tab %d \"%s\""):format(n, v.name) or ("tab " .. n)
end

local function ItemName(ctx, id)
    local f = ctx and ctx.facts and ctx.facts(id)
    return f and f.name or ("item " .. tostring(id))
end

-- An item's stack limit, or nil when the game hasn't said (the editor then won't reserve a stack of it)
local function Limit(ctx, id)
    local f = ctx and ctx.facts and ctx.facts(id)
    return f and math.max(1, f.maxStack or 1) or nil
end

local function HasStack(tab, id)
    for _, s in pairs(tab.slots) do if s.id == id then return true end end
    return false
end

-- an item stays in a tab only while it has a reserved stack there or that tab takes its extras
local function Tidy(tab, id)
    if not HasStack(tab, id) and not tab.rest[id] then tab.items[id] = nil end
end

local function RestTab(draft, id)
    for n, t in pairs(draft.tabs) do if t.rest[id] then return n end end
end

local function SetRest(draft, id, tab)
    for n, t in pairs(draft.tabs) do
        if n ~= tab and t.rest[id] then t.rest[id] = nil; Tidy(t, id) end
    end
    TabOf(draft, tab, true).rest[id] = true
end

local function FirstFree(draft, tab)
    local t = TabOf(draft, tab, false)
    for s = 1, SLOTS do if not (t and t.slots[s]) then return s end end
end

local function CanHold(tab, id)
    return tab.items[id] or Count(tab.items) < MI.MAX_IDS
end

---------------------------------------------------------------------------
-- Editing. Each returns true and a sentence, or false and a sentence; a refusal changes nothing.
---------------------------------------------------------------------------
-- An item dropped on a tab: that tab takes it, placed automatically in free slots. Reserved stacks it had elsewhere stay.
function D.AssignTab(draft, ctx, id, tab)
    if not ValidTab(draft, tab) then return false, "That tab isn't there." end
    if not MI.ValidID(id) then return false, "That isn't an item." end
    local t = TabOf(draft, tab, true)
    if not CanHold(t, id) then return false, ("A tab holds up to %d items in the arrangement."):format(MI.MAX_IDS) end
    t.items[id] = true
    SetRest(draft, id, tab)
    return true, ("%s goes to %s, placed automatically."):format(ItemName(ctx, id), TabName(draft, tab))
end

-- An item dropped on a slot: a reserved stack of `count` (default a full stack) in exactly that slot.
function D.PlaceSlot(draft, ctx, id, tab, slot, count)
    if not ValidTab(draft, tab) then return false, "That tab isn't there." end
    if not (type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= SLOTS) then return false, "That isn't a slot." end
    local limit = Limit(ctx, id)
    if not limit then return false, "The game is still loading this item. Try again in a moment." end
    local t = TabOf(draft, tab, true)
    local there = t.slots[slot]
    if there then return false, ("That slot is already reserved for %s \195\151%d."):format(ItemName(ctx, there.id), there.count) end
    count = math.min(limit, count or limit)
    if type(count) ~= "number" or count < 1 or count ~= math.floor(count) then return false, "A stack needs at least one item." end
    if not CanHold(t, id) then return false, ("A tab holds up to %d items in the arrangement."):format(MI.MAX_IDS) end
    t.slots[slot] = { id = id, count = count }
    t.items[id] = true
    if not RestTab(draft, id) then t.rest[id] = true end
    return true, ("%s \195\151%d is reserved for slot %d of %s."):format(ItemName(ctx, id), count, slot, TabName(draft, tab))
end

-- Where a moved stack lands: an empty slot (it moves), a stack of the same item (they combine up to the item's stack limit;
-- what doesn't fit stays where it was), or another item's reserved slot (refused).
local function Land(draft, ctx, src, srcTab, srcSlot, toTab, toSlot, qty)
    local st = TabOf(draft, srcTab, false)
    local dt = TabOf(draft, toTab, true)
    local id = src.id
    if not dt.items[id] and Count(dt.items) >= MI.MAX_IDS then return false, ("A tab holds up to %d items in the arrangement."):format(MI.MAX_IDS) end
    local there = dt.slots[toSlot]
    local moved
    if not there then
        moved = qty
        dt.slots[toSlot] = { id = id, count = qty }
    elseif there.id ~= id then
        return false, ("Slot %d of %s is reserved for %s. Move or remove that first."):format(toSlot, TabName(draft, toTab), ItemName(ctx, there.id))
    else
        local limit = Limit(ctx, id) or there.count
        local room = limit - there.count
        if room <= 0 then return false, ("That stack is already full (%d)."):format(limit) end
        moved = math.min(room, qty)
        there.count = there.count + moved
    end
    dt.items[id] = true
    src.count = src.count - moved
    if src.count <= 0 then st.slots[srcSlot] = nil end
    Tidy(st, id)
    if not RestTab(draft, id) then dt.rest[id] = true end
    return true, moved, there ~= nil
end

local function MoveText(draft, ctx, id, moved, left, toTab, toSlot, merged)
    local s = ("%s \195\151%d %s slot %d of %s."):format(ItemName(ctx, id), moved, merged and "combined into" or "reserved in", toSlot, TabName(draft, toTab))
    if left > 0 then s = s .. (" %d stay in the first slot."):format(left) end
    return s
end

-- A reserved stack dragged to another slot or tab.
function D.MoveStack(draft, ctx, fromTab, fromSlot, toTab, toSlot)
    local st = TabOf(draft, fromTab, false)
    local src = st and st.slots[fromSlot]
    if not src then return false, "There is no reserved stack there." end
    if not ValidTab(draft, toTab) then return false, "That tab isn't there." end
    if not (type(toSlot) == "number" and toSlot >= 1 and toSlot <= SLOTS and toSlot == math.floor(toSlot)) then return false, "That isn't a slot." end
    if fromTab == toTab and fromSlot == toSlot then return true, "Nothing changed." end
    local id = src.id
    local ok, moved, merged = Land(draft, ctx, src, fromTab, fromSlot, toTab, toSlot, src.count)
    if not ok then return false, moved end
    return true, MoveText(draft, ctx, id, moved, src.count > 0 and src.count or 0, toTab, toSlot, merged)
end

-- A reserved stack dropped on a tab: it takes the first slot of that tab not reserved yet.
function D.MoveToTab(draft, ctx, fromTab, fromSlot, toTab)
    if not ValidTab(draft, toTab) then return false, "That tab isn't there." end
    if fromTab == toTab then return true, "Nothing changed." end
    local free = FirstFree(draft, toTab)
    if not free then return false, ("%s has no unreserved slot left."):format(TabName(draft, toTab)) end
    return D.MoveStack(draft, ctx, fromTab, fromSlot, toTab, free)
end

-- qty off a reserved stack into another slot (an empty one, or a stack of the same item); the first keeps the rest.
-- toSlot nil: the first unreserved slot of toTab.
function D.Split(draft, ctx, tab, slot, qty, toTab, toSlot)
    local st = TabOf(draft, tab, false)
    local src = st and st.slots[slot]
    if not src then return false, "There is no reserved stack there." end
    if type(qty) ~= "number" or qty ~= math.floor(qty) or qty < 1 or qty >= src.count then
        return false, src.count > 1 and ("Choose a number from 1 to %d."):format(src.count - 1) or "A stack of one can't be split."
    end
    if not ValidTab(draft, toTab) then return false, "That tab isn't there." end
    toSlot = toSlot or FirstFree(draft, toTab)
    if not toSlot then return false, ("%s has no unreserved slot left."):format(TabName(draft, toTab)) end
    if not (type(toSlot) == "number" and toSlot >= 1 and toSlot <= SLOTS and toSlot == math.floor(toSlot)) then return false, "That isn't a slot." end
    if toTab == tab and toSlot == slot then return false, "Choose a different slot for the new stack." end
    local id = src.id
    local ok, moved, merged = Land(draft, ctx, src, tab, slot, toTab, toSlot, qty)
    if not ok then return false, moved end
    return true, MoveText(draft, ctx, id, moved, qty - moved, toTab, toSlot, merged)
end

-- A reserved stack goes back to automatic placement: no slot, no quantity; its tab takes the item's extras.
function D.Unreserve(draft, ctx, tab, slot)
    local t = TabOf(draft, tab, false)
    local s = t and t.slots[slot]
    if not s then return false, "There is no reserved stack there." end
    t.slots[slot] = nil
    t.items[s.id] = true
    SetRest(draft, s.id, tab)
    return true, ("%s is placed automatically in %s now."):format(ItemName(ctx, s.id), TabName(draft, tab))
end

-- One reserved stack taken out of the design (the item stays if its tab still takes its extras).
function D.RemoveStack(draft, ctx, tab, slot)
    local t = TabOf(draft, tab, false)
    local s = t and t.slots[slot]
    if not s then return false, "There is no reserved stack there." end
    t.slots[slot] = nil
    Tidy(t, s.id)
    return true, ("The reserved stack of %s was removed from the design."):format(ItemName(ctx, s.id))
end

-- An item taken out of a tab altogether: its reserved stacks there and its place in the list.
function D.RemoveItem(draft, ctx, tab, id)
    local t = TabOf(draft, tab, false)
    if not (t and t.items[id]) then return false, "That item isn't in this tab." end
    for s, v in pairs(t.slots) do if v.id == id then t.slots[s] = nil end end
    t.items[id], t.rest[id] = nil, nil
    return true, ("%s was taken out of %s. It is left alone by this design."):format(ItemName(ctx, id), TabName(draft, tab))
end

-- This tab takes the item's extras (the others stop).
function D.SetExtras(draft, ctx, tab, id)
    local t = TabOf(draft, tab, false)
    if not (t and t.items[id]) then return false, "That item isn't in this tab." end
    SetRest(draft, id, tab)
    return true, ("Extra %s will go to %s."):format(ItemName(ctx, id), TabName(draft, tab))
end

function D.AddCategory(draft, ctx, tab, key)
    if not ValidTab(draft, tab) then return false, "That tab isn't there." end
    if not MI.ValidCat(key) then return false, "That isn't a category." end
    for n, t in pairs(draft.tabs) do
        for _, k in ipairs(t.cats) do
            if k == key then return false, ("That category already goes to %s."):format(TabName(draft, n)) end
        end
    end
    local t = TabOf(draft, tab, true)
    if #t.cats >= MI.MAX_CATS then return false, ("A tab holds up to %d categories."):format(MI.MAX_CATS) end
    t.cats[#t.cats + 1] = key
    return true, ("%s goes to %s, placed automatically."):format(MI.CategoryName(key) or "That category", TabName(draft, tab))
end

function D.RemoveCategory(draft, ctx, tab, key)
    local t = TabOf(draft, tab, false)
    if not t then return false, "That category isn't in this tab." end
    for i, k in ipairs(t.cats) do
        if k == key then table.remove(t.cats, i) return true, "The category was taken out of the design." end
    end
    return false, "That category isn't in this tab."
end

---------------------------------------------------------------------------
-- Reading a draft
---------------------------------------------------------------------------
function D.TabEmpty(t) return t == nil or (next(t.slots) == nil and next(t.items) == nil and #t.cats == 0) end

-- The same text for the same draft: what is compared to know whether there are unsaved edits.
function D.Digest(draft)
    local out = {}
    for n = 1, MI.MAX_GUILD_TABS do
        local t = draft.tabs[n]
        if not D.TabEmpty(t) then
            local s = {}
            for _, slot in ipairs(SortedKeys(t.slots)) do s[#s + 1] = slot .. "=" .. t.slots[slot].id .. "x" .. t.slots[slot].count end
            local cats = {}
            for _, k in ipairs(t.cats) do cats[#cats + 1] = k end
            table.sort(cats)
            out[#out + 1] = ("%d|%s|%s|%s|%s"):format(n, table.concat(s, ","), table.concat(SortedKeys(t.items), ","), table.concat(SortedKeys(t.rest), ","), table.concat(cats, ","))
        end
    end
    return table.concat(out, ";")
end

function D.Dirty(draft) return D.Digest(draft) ~= draft.saved end

-- The total reserved for an item across the draft, and in how many stacks.
function D.Reserved(draft, id)
    local total, stacks = 0, 0
    for _, t in pairs(draft.tabs) do
        for _, s in pairs(t.slots) do if s.id == id then total, stacks = total + s.count, stacks + 1 end end
    end
    return total, stacks
end

-- Which tab takes an item's extras: the tab that says so; else the only tab that has the item; else none (ambiguous).
-- owners: { { rule, tab } ... } the design rules that match the item. Shared by the planner, which reads rules, not drafts.
function D.OverflowOf(owners)
    local flagged = {}
    for _, o in ipairs(owners) do
        if o.rest then flagged[#flagged + 1] = o end
    end
    if #flagged == 1 then return flagged[1] end
    if #flagged > 1 then return nil, "ambiguous" end
    if #owners == 1 then return owners[1] end
    if #owners == 0 then return nil, "none" end
    return nil, "ambiguous"
end

---------------------------------------------------------------------------
-- Rules <-> draft
---------------------------------------------------------------------------
-- Can the editor show this rule exactly as it is?  nil when it can, else a sentence.
function D.Unshowable(rule)
    if rule.enabled ~= true then return "it is turned off" end
    if rule.equip ~= "any" or rule.bind ~= "any" or next(rule.qualities) ~= nil then return "it filters by quality, equipment or binding" end
    if next(rule.exclude) ~= nil then return "it has a Never include list" end
    if (rule.keep or 0) > 0 then return "it keeps some of each item in your bags" end
    if (rule.stack or 0) > 0 then return "it has a target stack size" end
    return nil
end

-- rules: MI.Rules(). ctx: { guild, names, numTabs, resolve(destId) -> where, facts }.
-- Returns the draft. draft.advanced lists { rule, why } for every guild bank rule left out of it; draft.managed maps a tab to
-- the rule it came from.
function D.Load(rules, ctx)
    local draft = D.New(ctx.guild, ctx.names, ctx.numTabs)
    for _, rule in ipairs(rules) do
        if rule.kind == "guild" then
            local why, tab
            local where = rule.dest and ctx.resolve and ctx.resolve(rule.dest) or nil
            if rule.design then
                if not where then why = "no guild bank tab is chosen for it on this character"
                elseif where.guild ~= ctx.guild then why = ("it is for the guild <%s>"):format(where.guild)
                elseif not ValidTab(draft, where.tab) then why = ("this guild bank has no tab %d"):format(where.tab)
                else
                    local seen = draft.names[where.tab]
                    if seen and seen.name and where.tabName and seen.name ~= where.tabName then
                        why = ("tab %d is called \"%s\" now, not \"%s\""):format(where.tab, seen.name, where.tabName)
                    end
                    why = why or D.Unshowable(rule)
                    if not why and draft.managed[where.tab] then why = ("another rule already arranges tab %d"):format(where.tab) end
                    tab = where.tab
                end
            else
                why = "it is a rule of its own, made on the rules list"
            end
            if why then
                draft.advanced[#draft.advanced + 1] = { rule = rule, why = why, tab = where and where.tab or nil }
            else
                local t = TabOf(draft, tab, true)
                for id in pairs(rule.include) do t.items[id] = true end
                for id in pairs(rule.rest or {}) do t.rest[id] = true end
                for _, key in ipairs(rule.cats) do t.cats[#t.cats + 1] = key end
                for _, e in ipairs(rule.place or {}) do t.slots[e.slot] = { id = e.id, count = e.count } end
                draft.managed[tab] = { id = rule.id, dest = rule.dest, name = rule.name }
            end
        end
    end
    draft.saved = D.Digest(draft)
    return draft
end

local function RuleFor(draft, tab, base, ctx)
    local t = draft.tabs[tab]
    local rule = {}
    if base then for k, v in pairs(base) do rule[k] = v end end
    local n = draft.names[tab]
    rule.kind, rule.design, rule.enabled = "guild", true, true
    if base then rule.enabled = base.enabled end
    rule.name = base and base.name or ("Arrangement: " .. ((n and n.name) or ("tab " .. tab)))
    rule.dest = base and base.dest or ctx.destFor(tab, n and n.name, n and n.icon)
    rule.equip, rule.bind, rule.keep, rule.stack = "any", "any", 0, 0
    rule.qualities, rule.exclude = {}, {}
    rule.include, rule.rest, rule.place, rule.cats = {}, {}, {}, {}
    for id in pairs(t.items) do rule.include[id] = true end
    for id in pairs(t.rest) do rule.rest[id] = true end
    for _, slot in ipairs(SortedKeys(t.slots)) do rule.place[#rule.place + 1] = { slot = slot, id = t.slots[slot].id, count = t.slots[slot].count } end
    for _, k in ipairs(t.cats) do rule.cats[#rule.cats + 1] = k end
    return rule
end

-- The rule list that saving the draft would write: the rules the editor owns rewritten (or dropped, when their tab is empty
-- now) in place, new ones at the end, and every other rule the same table in the same place.
-- ctx.destFor(tab, name, icon) -> the destination id for a tab that has no rule yet.
function D.Commit(draft, rules, ctx)
    local out, kept = {}, {}
    local owned = {}
    for tab, m in pairs(draft.managed) do owned[m.id] = tab end
    for _, rule in ipairs(rules) do
        local tab = owned[rule.id]
        if tab == nil then out[#out + 1] = rule
        elseif not D.TabEmpty(draft.tabs[tab]) then
            out[#out + 1] = RuleFor(draft, tab, rule, ctx)
            kept[tab] = true
        end
    end
    for tab = 1, MI.MAX_GUILD_TABS do
        if not kept[tab] and not D.TabEmpty(draft.tabs[tab]) then out[#out + 1] = RuleFor(draft, tab, nil, ctx) end
    end
    return out
end

---------------------------------------------------------------------------
-- Conflicts: an item the arrangement names that another rule claims too. Priority is the rules list's order, as everywhere:
-- the first enabled rule that moves items owns the item. Read-only; nothing is reordered or rewritten.
-- Returns { { id, tab, rule, by, above = true | false, kind = "overridden" | "shadows" }, ... }
---------------------------------------------------------------------------
function D.Conflicts(rules, ctx)
    local out = {}
    local function Add(c) if #out < 40 then out[#out + 1] = c end end
    local seen = {}
    for _, rule in ipairs(rules) do
        if rule.design and rule.enabled and rule.kind == "guild" then
            local where = rule.dest and ctx.resolve and ctx.resolve(rule.dest) or nil
            local ids = {}
            for id in pairs(rule.include) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local facts = ctx.facts and ctx.facts(id)
                if facts then
                    local owner, shadow = MI.Owner(rules, facts)
                    if owner and not owner.design and owner.kind ~= "keep" then
                        local k = id .. "|" .. rule.id .. "|" .. owner.id
                        if not seen[k] then
                            seen[k] = true
                            Add({ id = id, tab = where and where.tab, rule = rule.name, by = owner.name, byId = owner.id, kind = "overridden",
                                where = owner.kind == "guild" and "another guild bank tab" or (owner.kind == "mail" and "mail" or "your bank") })
                        end
                    elseif owner and owner.design then
                        for _, s in ipairs(shadow) do
                            if not s.design then
                                local k = id .. "|" .. rule.id .. "|" .. s.id
                                if not seen[k] then
                                    seen[k] = true
                                    Add({ id = id, tab = where and where.tab, rule = rule.name, by = s.name, byId = s.id, kind = "shadows" })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- In the game
---------------------------------------------------------------------------
function D.GuildNow()
    if not (GetGuildInfo and IsInGuild) then return nil end
    if not IsInGuild() then return nil end
    local name = MI.Plain((GetGuildInfo("player")))
    return type(name) == "string" and name ~= "" and name or nil
end

-- The destination that already means this tab of this guild on this character, if there is one.
local function FindDest(guild, tab, name)
    for _, d in ipairs(MI.Dests()) do
        if d.kind == "guild" then
            local w = MI.Resolve(d.id)
            if w and w.guild == guild and w.tab == tab and (w.tabName == nil or name == nil or w.tabName == name) then return d.id end
        end
    end
end

-- The rule list a preview of the draft would use, and the destinations of tabs that have none yet (virtual: nothing is
-- created). Returns rules, virtual = { [destId] = where }.
function D.PreviewRules(draft, rules)
    local virtual = {}
    local rl = D.Commit(draft, rules, { destFor = function(tab, name, icon)
        local id = FindDest(draft.guild, tab, name)
        if id then return id end
        id = "dv" .. tab
        virtual[id] = { kind = "guild", guild = draft.guild, tab = tab, tabName = name, tabIcon = icon, label = "Tab " .. tab, id = id }
        return id
    end })
    -- a rule not saved yet has no id: it gets one for this preview only (the planner keys its rules by id)
    for i, r in ipairs(rl) do if not r.id then r.id = "pv" .. i end end
    return rl, virtual
end

-- Saves the draft: destinations for the tabs that need one (this character's choice of tab, as the rules page makes), then
-- every rule in one write. Returns true, or false and a sentence; when it fails nothing was written (a destination name that
-- was made first is harmless and is reused).
function D.Save(draft)
    if not draft.guild then return false, "Open the guild bank, or join a guild, first." end
    local rules = MI.Rules()
    local needNew = 0
    local trial = D.Commit(draft, rules, { destFor = function(tab, name)
        if not FindDest(draft.guild, tab, name) then needNew = needNew + 1 end
        return "dtrial"
    end })
    if #trial > MI.MAX_RULES then return false, ("You can keep %d rules; remove one on the rules list first."):format(MI.MAX_RULES) end
    if #MI.Dests() + needNew > MI.MAX_DESTS then return false, ("You can keep %d destinations; remove one on the rules list first."):format(MI.MAX_DESTS) end
    local why
    local list = D.Commit(draft, rules, { destFor = function(tab, name, icon)
        local id = FindDest(draft.guild, tab, name)
        if id then return id end
        local label = name and ("Tab %d: %s"):format(tab, name) or ("Tab " .. tab)
        id, why = MI.AddDest("guild", label)
        if not id then return nil end
        MI.SetGuildTab(id, draft.guild, tab, name, icon)
        return id
    end })
    if why then return false, why end
    local ok, w = MI.ReplaceRules(list)
    if not ok then return false, w end
    -- what was saved is what is shown: read it back, so Digest and the managed rules match the list
    return true
end
