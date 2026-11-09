-- TwichUI: camping bar, the rules (pure: no game calls, so it can be tested without a client)
-- Plan() says what is on the bar from facts the controller (camping/Bar.lua) has read; Visible() says whether the
-- bar shows at this moment; Cell()/Footprint() say where a button goes.
--
-- facts = {
--   count = { [itemID] = how many are in the bags },
--   known = { [craftSpellID] = true | false },   absent: the game gave no answer. Only an explicit true counts.
--   rank  = { [skillLineID] = skill },           absent: unknown or not learned. A known rank below a recipe's skill rules it out.
--   fireSpell = true | false | nil,              whether the Basic Campfire spell is known
--   eat   = { item, count } | nil,               the buff food the eat button would use (S.ChooseFood), if any
-- }
-- opts = the bar's settings (Bar.lua's C.Get): showFire, showBag, best, onlyBags, eat, grp_<key>, obj_<itemID>.
--
-- An entry is { kind = "fire" | "object" | "bag" | "eat", state = "have" | "craft" | "cast", item, spell, name, group, tier,
-- count }.
--   have   the item is in the bags: a click uses it;
--   cast   no kit in the bags but the Basic Campfire spell is known: a click casts it;
--   craft  nothing in the bags, but the recipe is known: dimmed, a click opens the recipe (never crafts).
-- Not knowing is never "yes": a recipe the game gave no answer for is not offered.

local R = TwichUI
local D = R.CampingData
local S = {}
R.CampingState = S

local function Number(v) return type(v) == "number" and v == v and v or 0 end

-- Can the recipe be made: known, and the skill (when readable) is enough.
local function CanMake(facts, spell, line, skill)
    if not (facts.known and facts.known[spell] == true) then return false end
    local rank = facts.rank and facts.rank[line]
    if rank ~= nil and rank < skill then return false end
    return true
end

-- The campfire: the largest kit in the bags; else the spell; else the largest kit whose recipe can be made.
local function FireEntry(facts, opts)
    local fires = D.FIRES
    for i = #fires, 1, -1 do
        local fire, n = fires[i], Number(facts.count and facts.count[fires[i].item])
        if n > 0 then
            return { kind = "fire", state = "have", item = fire.item, name = fire.name, count = n, slots = fire.slots }
        end
    end
    if facts.fireSpell == true then
        return { kind = "fire", state = "cast", spell = D.FIRE_SPELL, name = "Basic Campfire", count = 0, slots = fires[1].slots }
    end
    if opts.onlyBags then return nil end
    for i = #fires, 1, -1 do
        local fire = fires[i]
        if CanMake(facts, fire.spell, D.FIRE_LINE, fire.skill) then
            return { kind = "fire", state = "craft", item = fire.item, spell = fire.spell, name = fire.name, count = 0, slots = fire.slots }
        end
    end
    return nil
end

-- One profession's entries (before "best").
local function GroupEntries(group, facts, opts)
    local out = {}
    for _, o in ipairs(group.objects) do
        local n = Number(facts.count and facts.count[o.item])
        if opts["obj_" .. o.item] == false then
            -- left off the bar by the player
        elseif n > 0 then
            out[#out + 1] = { kind = "object", state = "have", item = o.item, spell = o.spell, name = o.name,
                group = group.key, tier = o.tier, count = n }
        elseif not opts.onlyBags and CanMake(facts, o.spell, group.line, o.skill) then
            out[#out + 1] = { kind = "object", state = "craft", item = o.item, spell = o.spell, name = o.name,
                group = group.key, tier = o.tier, count = 0 }
        end
    end
    return out
end

-- "Best": what you hold beats what you could make; then the higher tier. Everything tied for first stays.
local function Best(entries)
    local anyHave = false
    for _, e in ipairs(entries) do if e.state == "have" then anyHave = true break end end
    local top = -1
    for _, e in ipairs(entries) do
        if (e.state == "have" or not anyHave) and e.tier > top then top = e.tier end
    end
    local out = {}
    for _, e in ipairs(entries) do
        if (e.state == "have" or not anyHave) and e.tier == top then out[#out + 1] = e end
    end
    return out
end

function S.Plan(facts, opts)
    facts, opts = facts or {}, opts or {}
    local list = {}
    if opts.showFire ~= false then
        local fire = FireEntry(facts, opts)
        if fire then list[#list + 1] = fire end
    end
    for _, group in ipairs(D.GROUPS) do
        if opts["grp_" .. group.key] ~= false then
            local entries = GroupEntries(group, facts, opts)
            if opts.best then entries = Best(entries) end
            for _, e in ipairs(entries) do list[#list + 1] = e end
        end
    end
    if opts.showBag ~= false and Number(facts.count and facts.count[D.SLEEPING_BAG]) > 0 then
        list[#list + 1] = { kind = "bag", state = "have", item = D.SLEEPING_BAG, name = "Cozy Sleeping Bag",
            count = facts.count[D.SLEEPING_BAG] }
    end
    if opts.eat and facts.eat and Number(facts.eat.count) > 0 then
        list[#list + 1] = { kind = "eat", state = "have", item = facts.eat.item, name = facts.eat.name or "Buff food",
            count = facts.eat.count }
    end
    return list
end

-- The buff food the eat button uses. candidates: { { id, name, icon, amount, count }, ... } (what is in the bags and
-- is food with a buff). mode "choose": the one the player picked (chosen = its item ID), or nothing when it isn't in
-- the bags. mode "auto": the one that restores the most, then the smaller stack (a part stack is finished first), then
-- the lower item ID, so the answer doesn't depend on bag order (the same rule as the Food button, FoodDrink.Pick).
function S.ChooseFood(candidates, mode, chosen)
    if type(candidates) ~= "table" then return nil end
    if mode == "choose" then
        for _, c in ipairs(candidates) do
            if c.id == chosen and Number(c.count) > 0 then return c end
        end
        return nil
    end
    local best
    for _, c in ipairs(candidates) do
        if Number(c.count) > 0 then
            if not best then best = c
            else
                local a, b = Number(c.amount), Number(best.amount)
                if a > b or (a == b and (c.count < best.count or (c.count == best.count and c.id < best.id))) then best = c end
            end
        end
    end
    return best
end

-- What the eat button's secure macro says: use the food, then sit (the sit line is the player's choice). Item names
-- are plain text in a macro, so a name holding a line break or a slash command can't add a command of its own.
function S.EatMacro(name, sit)
    if type(name) ~= "string" or name == "" or name:find("[%c|]") then return nil end
    local text = "/use " .. name
    if sit then text = text .. "\n/sit" end
    return text
end

-- ctx = { instanceType = "none"|"party"|"raid"|"pvp"|"arena"|"scenario"|nil, resting = bool, combat = bool,
--         nearFire = true|false|nil }. Returns whether the bar shows, and the reason when it doesn't.
-- nearFire nil means the game would not say: that never hides the bar.
function S.Visible(opts, ctx)
    opts, ctx = opts or {}, ctx or {}
    local kind = ctx.instanceType
    if opts.hideParty and kind == "party" then return false, "dungeon" end
    if opts.hideRaid and kind == "raid" then return false, "raid" end
    if opts.hidePvp and (kind == "pvp" or kind == "arena") then return false, "pvp" end
    if opts.hideResting and ctx.resting == true then return false, "resting" end
    if opts.hideCombat and ctx.combat == true then return false, "combat" end
    if opts.onlyNearFire and ctx.nearFire == false then return false, "no-fire" end
    return true
end

-- Where button i (1-based) goes: column and row from the top left. perLine buttons fill a row (horizontal) or a column
-- (vertical) before the next starts.
function S.Cell(i, perLine, vertical)
    perLine = math.max(1, perLine or 1)
    local along, across = (i - 1) % perLine, math.floor((i - 1) / perLine)
    if vertical then return across, along end
    return along, across
end

-- The bar's size for n buttons.
function S.Footprint(n, size, spacing, perLine, vertical)
    if n < 1 then return size, size end
    local cols, rows = 1, 1
    for i = 1, n do
        local c, r = S.Cell(i, perLine, vertical)
        if c + 1 > cols then cols = c + 1 end
        if r + 1 > rows then rows = r + 1 end
    end
    return cols * size + (cols - 1) * spacing, rows * size + (rows - 1) * spacing
end
