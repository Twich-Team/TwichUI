-- TwichUI Workshop: the material-availability service (pure)
-- ONE place that turns the remembered bank and guild bank (Storage.lua) into numbers the Workshop can plan with. Crafting (Materials.lua),
-- Shopping (Shopping.lua) and Opportunities (Session.lua) all ask this file, and all split a need with the same W.Split (bags first, then the
-- bank, then the guild bank), so a material can never be spent twice. No frames, no game calls, nothing saved here.
--
-- THE RULES (docs/workshop.md repeats them)
--   * Bags, the personal bank and the guild bank stay three separate numbers. The bags are read live by the caller (Observe.BagCount, which
--     does not include the bank); the other two are REMEMBERED counts with the time they were seen. Nothing here calls the game's bank-inclusive
--     counters, so the bags are never counted twice.
--   * The personal bank is planned with by default. It is counted only when it was ever seen, and not while it may have changed since
--     (a bag change was seen with the bank open and no read followed: "uncertain").
--   * The guild bank is planned with only when the player turned "Use guild bank materials" on AND the character is in the guild whose bank
--     it was, AND the tab holding the item was read, is not uncertain, and this character's own observation of the tab says it can take items
--     from it. Viewing a tab does not establish that: a tab seen only by another character, one the rank cannot withdraw from, one whose daily
--     allowance was used up when it was seen (for REM_FRESH seconds), or one never read is shown as information and not counted. A finite or
--     unknown daily limit does not stop it being counted (it is "potentially withdrawable") but is flagged "limited": the quantity is not promised.
--   * Guild stock is shared stock: counting it is not a reservation, and the next member to open the bank may change it.
--   * An unread tab is not an empty tab: it adds nothing and the notes say so.

local R = TwichUI
local W = R.Workshop
local St = W.Storage
local K = {}
W.Stock = K

K.REM_FRESH = 6 * 3600   -- seconds a "no withdrawals left today" reading is believed (the daily reset time is not known to the addon)

local REASON = {
    uncertain = "may have changed since it was seen",
    rights = "your rights on that tab weren't seen",
    nowithdraw = "your guild rank can't take items from that tab",
    limit = "your daily limit was used up when it was seen",
}
K.REASON = REASON

local function Older(old, new) if not old or new < old then return new end return old end

-- ids: { char = "Name - Realm" | nil, guild = { key, name, club } | nil }; useGuild: the player's choice; live: { bankPending, guildPending } (a bag change
-- was just seen while that bank was open and its read has not come yet); now: the time a remembered daily allowance is judged at.
-- Returns the view every other function here reads.
function K.Sources(ids, useGuild, live, now)
    ids, live = ids or {}, live or {}
    local v = { ids = ids, useGuild = useGuild == true, live = live }

    local b = { seen = false, items = {}, age = {}, tabs = 0 }
    local rec = St.Bank()
    if rec then
        b.seen, b.at = true, rec.at
        for _, t in pairs(rec.tabs) do
            b.tabs = b.tabs + 1
            for item, n in pairs(t.n) do
                b.items[item] = (b.items[item] or 0) + n
                b.age[item] = Older(b.age[item], t.at)
            end
            if t.u then b.uncertain = true end
        end
        if rec.u or live.bankPending then b.uncertain = true end
    end
    b.counted = b.seen and not b.uncertain
    v.bank = b

    local g = { enabled = v.useGuild, inGuild = ids.guild ~= nil, seen = false, tabs = 0, unread = 0, uncertain = 0, limitedTabs = 0,
        counted = {}, info = {}, limited = {}, age = {}, reason = {}, tabState = {} }
    local grec = ids.guild and St.Guild(ids.guild) or nil
    if grec then
        g.seen, g.at, g.nt = true, grec.at, grec.nt
        local last = grec.nt or 0
        for i in pairs(grec.tabs) do if i > last then last = i end end
        for i = 1, last do
            local t = grec.tabs[i]
            if not t then
                g.unread = g.unread + 1
            else
                g.tabs = g.tabs + 1
                local how = "count"
                if t.u or live.guildPending then how = "uncertain"
                elseif not ids.char or t.by ~= ids.char then how = "rights"
                elseif t.w ~= 1 then how = (t.w == 0) and "nowithdraw" or "rights"
                elseif t.rem == 0 and t.remAt and now and (now - t.remAt) < K.REM_FRESH then how = "limit" end
                g.tabState[i] = how
                if how == "uncertain" then g.uncertain = g.uncertain + 1 end
                local limited = how == "count" and t.rem ~= -1
                if limited then g.limitedTabs = g.limitedTabs + 1 end
                for item, n in pairs(t.n) do
                    if how == "count" then
                        g.counted[item] = (g.counted[item] or 0) + n
                        g.age[item] = Older(g.age[item], t.at)
                        if limited then g.limited[item] = true end
                    else
                        g.info[item] = (g.info[item] or 0) + n
                        g.reason[item] = g.reason[item] or how
                    end
                end
            end
        end
    end
    v.guild = g
    return v
end

-- What may be planned with: the bank's count and the guild bank's count of an item (numbers, never nil)
function K.Counted(view, item)
    if not view then return 0, 0 end
    local b = view.bank.counted and view.bank.items[item] or 0
    local g = view.guild.enabled and view.guild.counted[item] or 0
    return b, g
end

-- The same as a function (what Materials.Rows and Shopping.Plan take); nil without a view
function K.Fn(view)
    if not view then return nil end
    return function(item) return K.Counted(view, item) end
end

-- When the counted part of an item was seen (the oldest tab holding it), and whether the guild's part is limited: for the collect rows
function K.Meta(view, item, where)
    if where == "bank" then return { at = view.bank.age[item] } end
    return { at = view.guild.age[item], limited = view.guild.limited[item] == true }
end

-- Is one craft's set of materials in the bags, in storage, or lacking? mats = { { item, qty } }; have(item) -> bags or nil.
-- Returns { state = "ready" | "collect" | "short" | "unknown", bags, bank, guild (counts taken from each), missing (materials still lacking) }.
-- Each craft is judged alone against the whole of what is held (it is a question about one craft, not a plan).
function K.Craft(mats, have, view)
    local out = { state = "ready", bags = 0, bank = 0, guild = 0, missing = 0 }
    if type(mats) ~= "table" or #mats == 0 then out.state = "unknown" return out end
    local collect = false
    for _, m in ipairs(mats) do
        local h = have(m.item)
        if type(h) ~= "number" or h ~= h or h < 0 then out.state = "unknown" return out end
        local bank, guild = K.Counted(view, m.item)
        local b, k, g, rest = W.Split(m.qty, h, bank, guild)
        out.bags, out.bank, out.guild = out.bags + b, out.bank + k, out.guild + g
        if rest > 0 then out.missing = out.missing + 1 end
        if k + g > 0 then collect = true end
    end
    if out.missing > 0 then out.state = "short" elseif collect then out.state = "collect" end
    return out
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
-- Short notes about what has not been seen. The first is the sentence the player is told when the bank was never observed.
function K.Notes(view)
    local out = {}
    if not view then return out end
    if not view.bank.seen then
        out[#out + 1] = "Open your bank with Workshop loaded to update."
    elseif view.bank.uncertain then
        out[#out + 1] = "Your bank may have changed. Open it with Workshop loaded to update."
    end
    local g = view.guild
    if g.enabled then
        if not g.inGuild then
            out[#out + 1] = "You're not in a guild, so no guild bank is counted."
        elseif not g.seen then
            out[#out + 1] = "Open your guild bank with Workshop loaded to update."
        else
            if g.unread > 0 then
                out[#out + 1] = ("%d guild bank %s not seen yet."):format(g.unread, g.unread == 1 and "tab" or "tabs")
            end
            if g.uncertain > 0 then out[#out + 1] = "Some guild bank tabs may have changed." end
        end
    end
    return out
end

-- Which stores the planning counts, in words: "bags only", "bags and bank", "bags, bank and guild bank"
function K.Scope(view)
    if view and view.guild.enabled and view.guild.inGuild and view.guild.seen then
        return view.bank.counted and "bags, bank and guild bank" or "bags and guild bank"
    end
    if view and view.bank.counted then return "bags and bank" end
    return "bags only"
end

-- The tooltip lines for one item: what the bags, the bank and the guild bank hold, how long ago, and why anything is not counted.
-- bags: the bag count or nil; ageText(at) -> "3 days ago". Plain strings.
function K.Lines(view, item, bags, ageText)
    local out = {}
    out[#out + 1] = bags ~= nil and ("In bags %d"):format(bags) or "In bags: unknown"
    local b = view.bank
    if not b.seen then
        out[#out + 1] = "Bank: not seen yet"
    else
        local n = b.items[item] or 0
        local line = ("Bank %d, seen %s"):format(n, ageText(b.age[item] or b.at))
        if b.uncertain then line = line .. " (may have changed, not counted)" end
        out[#out + 1] = line
    end
    local g = view.guild
    local have = (g.counted[item] or 0) + (g.info[item] or 0)
    if not g.enabled then
        if have > 0 then out[#out + 1] = ("Guild bank %d (not counted: guild bank materials are off)"):format(have) end
    elseif not g.inGuild then
        out[#out + 1] = "Guild bank: you aren't in a guild"
    elseif not g.seen then
        out[#out + 1] = "Guild bank: not seen yet"
    else
        if (g.counted[item] or 0) > 0 then
            out[#out + 1] = ("Guild bank %d, seen %s"):format(g.counted[item], ageText(g.age[item]))
            out[#out + 1] = g.limited[item] and "  Shared stock; a withdrawal limit may apply, so it isn't promised."
                or "  Shared stock: other members can take it too."
        end
        if (g.info[item] or 0) > 0 then
            out[#out + 1] = ("Guild bank %d, not counted: %s"):format(g.info[item], REASON[g.reason[item]] or "not usable")
        end
        if have == 0 then out[#out + 1] = "Guild bank: none seen" end
    end
    return out
end
