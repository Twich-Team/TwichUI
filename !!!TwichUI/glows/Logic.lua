-- TwichUI: Action bar glows, the decisions
-- Which reminders are due, from what the game says (an observation, `obs`, made by State.lua) and the player's
-- choices (Config.lua). Pure: it reads only what it is handed, never the game, so the tests drive it with plain tables.
-- An answer the game did not give (nil) is unknown, and unknown never glows.
--
--   LG.When(kind, style, ctx, quietInTowns)   whether the kind may glow now, and whether its message and sound may come
--   LG.Due(obs, cfg)                          the reminders due now: a list of
--       { id = "kind:key", kind, key, label, spells = { lower names }, items = { ids }, buttons = { frames }, text,
--         detail (the message card's second line; nil: the kind's own words), icon = { spell = id } or { item = id } }
--
-- obs (functions may answer nil for unknown):
--   class, ctx = { combat, resting, dead, taxi, enemy, group = "none" | "party" | "raid" }
--   auras            { [lower name] = true } of the helpful auras on you, or nil
--   name(id)         a spell's name in lower case; display(id) as written; itemName(id), itemDisplay(id) the same for items
--   itemSpell(id)    the lower-case name of the spell an item casts (its buff)
--   known(id)        whether you know the spell; onBars(lowerName) whether a button holds it; itemOnBars(id)
--   count(itemId)    how many you carry
--   weapon           { mainHand = has enchant (bool), offHand = ..., offHandWeapon = a weapon there (bool) } or nil
--   tracking         whether any tracking is on, or nil
--   ready(id)        whether the cooldown is over; usable(id) whether the game says it can be cast now
--   window(key)      a proc whose window the game told us of another way (Revenge after a block or dodge)
--   members          out of combat in a group: { { name, class, mana (bool), auras = { ... } or nil, inRange(id) } }
--   ranks            buttons that hold a lower rank: { { key, name, display, buttons = { ... } } }
--   remembered(category), blessing(class)   what was used last

local R = TwichUI
local C = R.BarGlowCatalog
local LG = {}
R.BarGlowLogic = LG

---------------------------------------------------------------------------
-- When a kind may show
---------------------------------------------------------------------------
-- Returns glow, alert: whether the buttons may glow, and whether the message and sound may come.
function LG.When(kind, style, ctx, quietInTowns)
    if not ctx or ctx.dead or ctx.taxi then return false, false end
    local when = style and style.when or "always"
    if when == "townAlert" then return true, ctx.resting == true end
    if quietInTowns and ctx.resting and not ctx.combat then return false, false end
    local ok
    if when == "inCombat" then ok = ctx.combat == true
    elseif when == "outOfCombat" then ok = not ctx.combat
    elseif when == "enemyTargeted" then ok = ctx.enemy == true
    else ok = true end
    return ok, ok
end

---------------------------------------------------------------------------
-- Small pieces
---------------------------------------------------------------------------
local function Name(obs, id) return id and obs.name and obs.name(id) or nil end

local function Display(obs, e, id)
    local name = (id and obs.display and obs.display(id)) or nil
    if type(name) == "string" and name ~= "" then return name end
    return e and e.label or (id and ("Spell " .. id)) or "?"
end

local function Known(obs, id) return id ~= nil and obs.known ~= nil and obs.known(id) == true end

-- The names an entry's buff goes by: its own spell's, and any others that count (the group version's).
local function BuffNames(obs, e)
    local out = {}
    local own = Name(obs, e.spell)
    if own then out[#out + 1] = own end
    for _, id in ipairs(e.names or {}) do
        local n = Name(obs, id)
        if n then out[#out + 1] = n end
    end
    return out
end

-- true: one of the names is there; false: none is; nil: the names or the auras are unknown.
local function Wearing(auras, names)
    if auras == nil or #names == 0 then return nil end
    for _, n in ipairs(names) do if auras[n] then return true end end
    return false
end

local function Carried(obs, items)
    local total, any = 0, false
    for _, id in ipairs(items) do
        local n = obs.count and obs.count(id)
        if type(n) == "number" then total, any = total + n, true end
    end
    if not any then return nil end
    return total
end

-- An entry the player added, made to look like a built-in one.
local function AddedEntry(a, cfg)
    return { type = a.kind, key = cfg.AddedKey(a), spell = a.spell, item = a.item, aura = a.aura, slot = a.slot, added = true }
end

local function Entries(obs, cfg, kind)
    local list = C.For(kind, obs.class)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e end
    for _, a in ipairs(cfg.Added()) do
        if a.kind == kind then out[#out + 1] = AddedEntry(a, cfg) end
    end
    return out
end

local function Add(due, byId, item)
    local found = byId[item.id]
    if found then
        for _, s in ipairs(item.spells or {}) do found.spells[#found.spells + 1] = s end
        for _, s in ipairs(item.items or {}) do found.items[#found.items + 1] = s end
        if item.text and item.text ~= found.text then found.text = (found.text and (found.text .. " · ") or "") .. item.text end
        return found
    end
    item.spells, item.items = item.spells or {}, item.items or {}
    due[#due + 1] = item
    byId[item.id] = item
    return item
end

---------------------------------------------------------------------------
-- Exclusive groups: one armor, one aspect, one aura, one seal, one tracking. Satisfied by any of them; otherwise
-- the one used last glows (if you still know it and it is on), else the first you know that is on.
---------------------------------------------------------------------------
local function PickInGroup(obs, cfg, list, category)
    local last = obs.remembered and obs.remembered(category)
    local first
    for _, e in ipairs(list) do
        if cfg.On(e.type, e.key) and Known(obs, e.spell) then
            if e.key == last then return e end
            first = first or e
        end
    end
    return first
end

---------------------------------------------------------------------------
-- The kinds
---------------------------------------------------------------------------
local function MissingBuffs(obs, cfg, due, byId)
    local kind = "missingBuff"
    if not cfg.TypeEnabled(kind) then return end
    local groups = {}
    for _, e in ipairs(Entries(obs, cfg, kind)) do
        if e.category then
            groups[e.category] = groups[e.category] or {}
            table.insert(groups[e.category], e)
        elseif cfg.On(kind, e.key) then
            if e.item then
                -- an elixir, a scroll or a food: its buff is the item's spell, or the one named
                local aura = e.aura and Name(obs, e.aura) or (obs.itemSpell and obs.itemSpell(e.item))
                local have = obs.count and obs.count(e.item)
                local wearing = aura and Wearing(obs.auras, { aura })
                if wearing == false and type(have) == "number" and have > 0 then
                    local label = (obs.itemDisplay and obs.itemDisplay(e.item)) or ("Item " .. e.item)
                    Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, items = { e.item },
                        text = label, icon = { item = e.item } })
                end
            elseif Known(obs, e.spell) then
                local wearing = Wearing(obs.auras, BuffNames(obs, e))
                if wearing == false then
                    local n = Name(obs, e.spell)
                    local label = Display(obs, e, e.spell)
                    Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = { n },
                        text = label, self = true, notOnBars = obs.onBars and not obs.onBars(n) or nil, icon = { spell = e.spell } })
                end
            end
        end
    end
    for category, list in pairs(groups) do
        local names = {}
        for _, e in ipairs(list) do
            for _, n in ipairs(BuffNames(obs, e)) do names[#names + 1] = n end
        end
        local wearing = Wearing(obs.auras, names)
        if wearing == false then
            local e = PickInGroup(obs, cfg, list, category)
            if e then
                local n = Name(obs, e.spell)
                local label = Display(obs, e, e.spell)
                Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = { n }, text = label,
                    self = true, notOnBars = obs.onBars and not obs.onBars(n) or nil, icon = { spell = e.spell } })
            end
        end
    end
end

-- Group members in range who lack one of your buffs: out of combat only. A buff for everyone (Fortitude,
-- Intellect, the Mark, Spirit, Shadow Protection) is looked at on each member it suits; a paladin's blessing only on
-- members of a class you gave that blessing (it is told by class). The group version glows instead once enough are
-- missing it (counting you, never you alone) and its reagent is in your bags.
local function GroupBuffs(obs, cfg, due, byId)
    local kind = "missingBuff"
    local ctx = obs.ctx or {}
    if not cfg.TypeEnabled(kind) or ctx.combat or not obs.members then return end
    if ctx.group == "party" and not cfg.Get("partyBuffs") then return end
    if ctx.group == "raid" and not cfg.Get("raidBuffs") then return end
    if ctx.group ~= "party" and ctx.group ~= "raid" then return end
    local from = ctx.group == "raid" and cfg.Get("raidGroupFrom") or cfg.Get("partyGroupFrom")

    local function Consider(e, members, selfMissing)
        local names = BuffNames(obs, e)
        if #names == 0 then return end
        local missing = {}
        for _, m in ipairs(members) do
            if not (e.mana and not m.mana) and m.inRange and m.inRange(e.spell) == true then
                if Wearing(m.auras, names) == false then missing[#missing + 1] = m.name end
            end
        end
        if #missing == 0 then return end
        local counted = #missing + (selfMissing and 1 or 0)
        local single, label = Name(obs, e.spell), Display(obs, e, e.spell)
        local target, targetId = single, e.spell
        local g = e.group
        -- #missing > 0 here, so the group version is never for you alone
        if g and counted >= from then
            local gname = Name(obs, g.spell)
            local reagent = Carried(obs, g.reagents or {})
            if gname and Known(obs, g.spell) and type(reagent) == "number" and reagent > 0 then
                target, targetId, label = gname, g.spell, Display(obs, nil, g.spell)
            end
        end
        local who = #missing <= 3 and table.concat(missing, ", ") or (#missing .. " members")
        local text = Display(obs, e, e.spell) .. " missing on " .. who
        local id = kind .. ":" .. e.key
        local found = byId[id]
        if found and target ~= single then
            -- the group version covers you too: it glows instead of the single one
            found.spells, found.label, found.text, found.group = { target }, label, text, true
            found.detail, found.icon = "Missing on you and " .. who, { spell = targetId }
        elseif found then
            found.text, found.group = (found.text and (found.text .. " · ") or "") .. text, true
            found.detail = (found.self and "Missing on you and " or "Missing on ") .. who
        else
            Add(due, byId, { id = id, kind = kind, key = e.key, label = label, spells = { target }, text = text, group = true,
                detail = "Missing on " .. who, icon = { spell = targetId } })
        end
    end

    -- you count when the same buff is missing on you (already due above)
    local function SelfMissing(e) return byId[kind .. ":" .. e.key] ~= nil and byId[kind .. ":" .. e.key].self == true end

    for _, e in ipairs(C.For(kind, obs.class)) do
        if e.group and e.category ~= "blessing" and cfg.On(kind, e.key) and Known(obs, e.spell) then
            Consider(e, obs.members, SelfMissing(e))
        end
    end
    if obs.class == "PALADIN" and obs.blessing then
        local byBlessing = {}
        for _, m in ipairs(obs.members) do
            local key = m.class and obs.blessing(m.class)
            if key then
                byBlessing[key] = byBlessing[key] or {}
                table.insert(byBlessing[key], m)
            end
        end
        for key, members in pairs(byBlessing) do
            local e = C.Find(kind, key)
            if e and e.category == "blessing" and cfg.On(kind, key) and Known(obs, e.spell) then
                -- a Greater Blessing reaches one class: count per class
                local byClass = {}
                for _, m in ipairs(members) do
                    byClass[m.class] = byClass[m.class] or {}
                    table.insert(byClass[m.class], m)
                end
                for _, list in pairs(byClass) do Consider(e, list, false) end
            end
        end
    end
end

local function WeaponBuffs(obs, cfg, due, byId)
    local kind = "weaponBuff"
    local w = obs.weapon
    if not cfg.TypeEnabled(kind) or not w then return end
    local entries = Entries(obs, cfg, kind)
    for _, hand in ipairs({ "mainHand", "offHand" }) do
        local wanted = w[hand] == false and (hand == "mainHand" or w.offHandWeapon == true)
        if wanted then
            local function Available(e)
                if not cfg.On(kind, e.key) then return false end
                local slot = e.slot or "both"
                if slot ~= "both" and slot ~= hand then return false end
                if e.spell then return Known(obs, e.spell) end
                local have = Carried(obs, e.items or { e.item })
                return type(have) == "number" and have > 0
            end
            local choice = cfg.Weapon(hand)
            local pick
            if choice ~= "auto" then
                for _, e in ipairs(entries) do if e.key == choice and Available(e) then pick = e end end
            else
                local last = obs.remembered and obs.remembered("weapon" .. hand)
                for _, e in ipairs(entries) do
                    if Available(e) then
                        if e.key == last then pick = e break end
                        pick = pick or e
                    end
                end
            end
            if pick then
                local label
                local item = {}
                if pick.spell then label = Display(obs, pick, pick.spell)
                else
                    label = pick.label or (obs.itemDisplay and obs.itemDisplay(pick.item)) or ("Item " .. tostring(pick.item))
                    for _, id in ipairs(pick.items or { pick.item }) do item[#item + 1] = id end
                end
                Add(due, byId, { id = kind .. ":" .. pick.key, kind = kind, key = pick.key, label = label,
                    spells = pick.spell and { Name(obs, pick.spell) } or nil, items = item,
                    text = label .. (hand == "offHand" and " (off hand)" or " (main hand)"),
                    detail = hand == "offHand" and "Weapon buff, off hand" or "Weapon buff, main hand",
                    icon = pick.spell and { spell = pick.spell } or { item = item[1] } })
            end
        end
    end
end

-- Seals and tracking: one exclusive group each.
local function OneOf(obs, cfg, due, byId, kind, category, isMissing)
    if not cfg.TypeEnabled(kind) then return end
    local list = Entries(obs, cfg, kind)
    if #list == 0 then return end
    if not isMissing(list) then return end
    local e = PickInGroup(obs, cfg, list, category)
    if not e then return end
    local label = Display(obs, e, e.spell)
    Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = { Name(obs, e.spell) }, text = label,
        icon = { spell = e.spell } })
end

local function Seals(obs, cfg, due, byId)
    if obs.class ~= "PALADIN" and #cfg.Added() == 0 then return end
    OneOf(obs, cfg, due, byId, "missingSeal", "seal", function(list)
        local names = {}
        for _, e in ipairs(list) do
            local n = Name(obs, e.spell)
            if n then names[#names + 1] = n end
        end
        return Wearing(obs.auras, names) == false
    end)
end

local function Tracking(obs, cfg, due, byId)
    OneOf(obs, cfg, due, byId, "missingTracking", "tracking", function() return obs.tracking == false end)
end

local function Reagents(obs, cfg, due, byId)
    local kind = "lowReagent"
    if not cfg.TypeEnabled(kind) then return end
    for _, e in ipairs(C.For(kind, obs.class)) do
        if cfg.On(kind, e.key) then
            local names = {}
            for _, id in ipairs(e.spells) do
                local n = Name(obs, id)
                if n and Known(obs, id) and obs.onBars and obs.onBars(n) then names[#names + 1] = n end
            end
            if #names > 0 then
                local have = Carried(obs, e.items or { e.reagent })
                local below = cfg.Below(kind, e.key)
                if type(have) == "number" and have < below then
                    local label = (obs.itemDisplay and obs.itemDisplay(e.reagent)) or e.label
                    Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = names,
                        text = ("Running low: %s (%d)"):format(label, have),
                        detail = ("Running low: %d left"):format(have), icon = { item = e.reagent } })
                end
            end
        end
    end
end

local function Stock(obs, cfg, due, byId)
    local kind = "lowStock"
    if not cfg.TypeEnabled(kind) then return end
    for _, a in ipairs(cfg.Added()) do
        if a.kind == kind and a.item then
            local key = cfg.AddedKey(a)
            if cfg.On(kind, key) then
                local have = obs.count and obs.count(a.item)
                local below = cfg.Below(kind, key)
                if type(have) == "number" and have < below then
                    local label = (obs.itemDisplay and obs.itemDisplay(a.item)) or ("Item " .. a.item)
                    Add(due, byId, { id = kind .. ":" .. key, kind = kind, key = key, label = label, items = { a.item },
                        text = ("Running low: %s (%d)"):format(label, have),
                        detail = ("Running low: %d left"):format(have), icon = { item = a.item } })
                end
            end
        end
    end
end

local function Cooldowns(obs, cfg, due, byId)
    local kind = "readyCooldown"
    if not cfg.TypeEnabled(kind) then return end
    for _, e in ipairs(Entries(obs, cfg, kind)) do
        if e.spell and cfg.On(kind, e.key) and Known(obs, e.spell) then
            local n = Name(obs, e.spell)
            if n and obs.onBars and obs.onBars(n) and obs.ready and obs.ready(e.spell) == true then
                local label = Display(obs, e, e.spell)
                Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = { n },
                    text = label .. " ready", pulse = true, spell = e.spell, icon = { spell = e.spell } })
            end
        end
    end
end

local function Procs(obs, cfg, due, byId)
    local kind = "proc"
    if not cfg.TypeEnabled(kind) then return end
    for _, e in ipairs(Entries(obs, cfg, kind)) do
        if e.spell and cfg.On(kind, e.key) and Known(obs, e.spell) then
            local open = (obs.usable and obs.usable(e.spell) == true) or (obs.window and obs.window(e.key) == true)
            local cooling = obs.ready and obs.ready(e.spell) == false
            if open and not cooling then
                local label = Display(obs, e, e.spell)
                Add(due, byId, { id = kind .. ":" .. e.key, kind = kind, key = e.key, label = label, spells = { Name(obs, e.spell) },
                    text = label, icon = { spell = e.spell } })
            end
        end
    end
end

local function OldRanks(obs, cfg, due, byId)
    local kind = "oldRank"
    if not cfg.TypeEnabled(kind) or not obs.ranks then return end
    for _, r in ipairs(obs.ranks) do
        if cfg.On(kind, r.key) then
            Add(due, byId, { id = kind .. ":" .. r.key, kind = kind, key = r.key, label = r.display, buttons = r.buttons,
                text = "Old rank on your bars: " .. r.display, detail = "Old rank on your bars", icon = r.spell and { spell = r.spell } or nil })
        end
    end
end

---------------------------------------------------------------------------
-- Everything due now. The order is the kinds' importance (Catalog.TYPE_ORDER), then as found.
---------------------------------------------------------------------------
function LG.Due(obs, cfg)
    local due, byId = {}, {}
    MissingBuffs(obs, cfg, due, byId)
    GroupBuffs(obs, cfg, due, byId)
    WeaponBuffs(obs, cfg, due, byId)
    Seals(obs, cfg, due, byId)
    Tracking(obs, cfg, due, byId)
    Reagents(obs, cfg, due, byId)
    Stock(obs, cfg, due, byId)
    Cooldowns(obs, cfg, due, byId)
    Procs(obs, cfg, due, byId)
    OldRanks(obs, cfg, due, byId)
    table.sort(due, function(a, b)
        local oa, ob = C.TYPES[a.kind] or 99, C.TYPES[b.kind] or 99
        if oa ~= ob then return oa < ob end
        return a.id < b.id
    end)
    return due
end
