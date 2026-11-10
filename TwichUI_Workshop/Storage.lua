-- TwichUI Workshop: what the player's bank and the guild bank were last seen to hold
-- No frames and no game calls (Bank.lua reads the game and hands the observations here). It keeps remembered COUNTS of items, with the time
-- they were seen, so the Workshop can plan with materials that are not in the bags without confusing them with the bags. It is a memory of
-- what was observed, never live stock: every number carries the time of the observation.
--
--   TwichUIDB.workshop.storage = { v = 1, useGuild = false,
--       chars  = { ["Name - Realm"] = { bank = { u = true|nil, tabs = { [bagID] = { at, n = { [itemID] = count } } } } } },
--       guilds = { ["Guild-Realm"] = { name, club, nt, at, tabs = { [1..8] = { at, n, by, w, lim, rem, remAt, u } } } } }
--   account-wide, bounded, never in a profile, a share or a backup (the same "workshop" key as the queue: Restore.OWN_LEFT_OUT,
--   TwichConfig.LOCAL).
--   * The personal bank belongs to ONE character and is never added to another character's. The guild bank belongs to a GUILD (its name and
--     realm; `club` is the guild's community id when the game gave one: a different id under the same name is a different guild), one record per
--     tab, so two characters of one guild never produce two snapshots to add together: the newer observation of a tab replaces the older.
--   * A tab's contents are replaced as a whole and only by a complete observation (Bank.lua decides what is complete). A tab that was not
--     observed keeps what it had; one never observed has no record ("unread"), which is NOT an empty tab.
--   * u ("uncertain") means the tab may have changed since it was last read (a bag change was seen while the bank was open and no read followed);
--     the Workshop shows the count but does not plan with it until the next complete read clears it.
--   * Guild tabs also remember what the OBSERVING character may do there: by (who saw it), w (1 can withdraw, 0 cannot; unknown is nil),
--     lim (the game's withdrawal count for the rank), rem and remAt (stacks left today as seen, -1 unlimited, and when). Viewing a tab does
--     not establish a right to take from it; another character's rights are not yours, so a tab seen by someone else is information only.
--   v higher than this file understands (a newer TwichUI) makes every change refuse with "held".

local R = TwichUI
local W = R.Workshop
local Q = W.Queue
local Int, Text = W.Int, W.Text
local St = {}
W.Storage = St

St.SAVED_VERSION = 1
St.MAX_COUNT = 1000000      -- one item in one tab (a player can hold more than one stack)
St.MAX_BANK_TABS = 14       -- character bank tabs (the client names nine; the limit is a bound, not a claim)
St.MAX_GUILD_TABS = 8
St.MAX_GUILDS = 3           -- guilds remembered at once (the one observed longest ago goes)
St.MAX_TAB_ITEMS = 150      -- different items remembered per tab (a guild tab has 98 slots)

local MAX_TIME = 4102444800

St.rev = 0                  -- changes with every write (the readers may cache against it)
St.OnChange = nil           -- function(): called after a write, so a shown window can redraw

local function Changed()
    St.rev = St.rev + 1
    if St.OnChange then St.OnChange() end
end

local function Root(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if not create then return nil end
        ws = {}
        TwichUIDB.workshop = ws
    end
    local s = ws.storage
    if type(s) ~= "table" then
        if not create then return nil end
        s = { v = St.SAVED_VERSION }
        ws.storage = s
    end
    return s, ws
end

-- True when a newer TwichUI wrote the workshop data or this part of it: read as far as understood, never changed
function St.Held()
    if Q.Held() then return true end
    local s = Root(false)
    return s ~= nil and type(s.v) == "number" and s.v > St.SAVED_VERSION
end

---------------------------------------------------------------------------
-- Checking a record
---------------------------------------------------------------------------
-- { [itemID] = count } with every id and count a whole number in range; at most MAX_TAB_ITEMS different items. nil when it isn't a table.
-- `strict`: the data is being SAVED, so too many items or one bad number make it unusable (nil) instead of being cut or skipped (a tab with
-- something left out would look complete). Saved data being read is checked leniently: a bad entry is skipped.
local function CleanItems(t, strict)
    if type(t) ~= "table" then return nil end
    local out, n = {}, 0
    for item, count in pairs(t) do
        local id, c = Int(item, 1, W.MAX_ID), Int(count, 1, St.MAX_COUNT)
        if id and c then
            n = n + 1
            if n > St.MAX_TAB_ITEMS then
                if strict then return nil end
                break
            end
            out[id] = c
        elseif strict then
            return nil   -- an observation with one bad number is not a complete observation
        end
    end
    return out
end

local function CleanTab(t)
    if type(t) ~= "table" then return nil end
    local at, n = Int(t.at, 1, MAX_TIME), CleanItems(t.n)
    if not at or not n then return nil end
    return { at = at, n = n, u = t.u == true or nil }
end

local function CleanGuildTab(t)
    local tab = CleanTab(t)
    if not tab then return nil end
    tab.by = Text(t.by, 80)
    local w = Int(t.w, 0, 1)
    tab.w = w
    tab.lim = Int(t.lim, -1, W.MAX_ID)
    tab.rem = Int(t.rem, -1, W.MAX_ID)
    tab.remAt = tab.rem ~= nil and Int(t.remAt, 1, MAX_TIME) or nil
    return tab
end

---------------------------------------------------------------------------
-- The choice
---------------------------------------------------------------------------
-- "Use guild bank materials": off unless the player turned it on
function St.UseGuild()
    local s = Root(false)
    return s ~= nil and s.useGuild == true
end

function St.SetUseGuild(on)
    if St.Held() then return false, "held" end
    on = on == true
    if on == St.UseGuild() then return true end
    local s = Root(true)
    if not s then return false, "unsaved" end
    s.v = St.SAVED_VERSION
    s.useGuild = on or nil
    Changed()
    return true
end

---------------------------------------------------------------------------
-- The personal bank (this character's)
---------------------------------------------------------------------------
local function CharSlot(create)
    local s, ws = Root(create)
    local key = s and Q.CharKey()
    if not key then return nil end
    if type(s.chars) ~= "table" then
        if not create then return nil end
        s.chars = {}
    end
    if type(s.chars[key]) ~= "table" then
        if not create then return nil end
        s.chars[key] = {}
    end
    return s.chars[key], s, ws
end

-- A checked copy of this character's bank record: { at (the newest tab observation), u, tabs = { [bagID] = { at, n, u } } }, or nil when
-- nothing was ever observed
function St.Bank()
    local slot = CharSlot(false)
    local b = slot and slot.bank
    if type(b) ~= "table" or type(b.tabs) ~= "table" then return nil end
    local out, count = { tabs = {}, u = b.u == true }, 0
    for id, t in pairs(b.tabs) do
        local bag, tab = Int(id, 1, 99), CleanTab(t)
        if bag and tab and count < St.MAX_BANK_TABS then
            count = count + 1
            out.tabs[bag] = tab
            if not out.at or tab.at > out.at then out.at = tab.at end
        end
    end
    if count == 0 then return nil end
    return out
end

-- read = { ids = { bagID, ... } (the purchased tabs, as the game listed them; empty/nil when it could not say), tabs = { [bagID] = { [itemID] = count } }
-- (ONLY the tabs read completely), incomplete = how many purchased tabs could not be read completely }.
-- Replaces each completely read tab, drops a tab the game no longer lists, leaves every other tab as it was, and marks the record uncertain while
-- any tab could not be read. Returns true, or false and why ("held", "unsaved", "bad").
function St.StoreBank(read, now)
    if St.Held() then return false, "held" end
    now = Int(now or Q.Now(), 1, MAX_TIME)
    if not now or type(read) ~= "table" or type(read.tabs) ~= "table" then return false, "bad" end
    local fresh = {}
    for id, items in pairs(read.tabs) do
        local bag, n = Int(id, 1, 99), CleanItems(items, true)
        if not (bag and n) then return false, "bad" end   -- one bad tab: nothing is taken from this read
        fresh[bag] = n
    end
    local ids
    if type(read.ids) == "table" and #read.ids > 0 then
        ids = {}
        for _, id in ipairs(read.ids) do
            local bag = Int(id, 1, 99)
            if bag then ids[bag] = true end
        end
    end
    local slot, s = CharSlot(true)
    if not slot then return false, "unsaved" end
    s.v = St.SAVED_VERSION
    local b = slot.bank
    if type(b) ~= "table" then b = {} slot.bank = b end
    if type(b.tabs) ~= "table" then b.tabs = {} end
    for bag, n in pairs(fresh) do b.tabs[bag] = { at = now, n = n } end
    if ids then
        for bag in pairs(b.tabs) do
            if not ids[bag] then b.tabs[bag] = nil end
        end
    end
    b.u = (tonumber(read.incomplete) or 0) > 0 or nil
    Changed()
    return true
end

-- The bank may have changed since it was read. Returns true when that was news.
function St.MarkBankUncertain()
    if St.Held() then return false end
    local slot = CharSlot(false)
    local b = slot and slot.bank
    if type(b) ~= "table" or b.u == true then return false end
    b.u = true
    Changed()
    return true
end

---------------------------------------------------------------------------
-- The guild bank (the current guild's)
---------------------------------------------------------------------------
-- id = { key = "Guild-Realm", name, club (or nil) } as Observe.GuildId gives it. The same name with a different club id is another guild.
local function SameGuild(rec, id)
    if type(rec) ~= "table" or type(id) ~= "table" then return false end
    local club = Text(id.club, 40)
    local have = Text(rec.club, 40)
    return not (club and have and club ~= have)
end

-- A checked copy of the record of that guild, or nil: { name, club, nt, at, tabs = { [i] = tab } }
function St.Guild(id)
    local s = Root(false)
    if not (s and type(s.guilds) == "table" and type(id) == "table") then return nil end
    local key = Text(id.key, 100)
    local rec = key and s.guilds[key]
    if type(rec) ~= "table" or not SameGuild(rec, id) then return nil end
    local out = { name = Text(rec.name, 60), club = Text(rec.club, 40), nt = Int(rec.nt, 1, St.MAX_GUILD_TABS), tabs = {} }
    for i = 1, St.MAX_GUILD_TABS do
        local t = type(rec.tabs) == "table" and CleanGuildTab(rec.tabs[i]) or nil
        if t and (not out.nt or i <= out.nt) then
            out.tabs[i] = t
            if not out.at or t.at > out.at then out.at = t.at end
        end
    end
    if not out.at then return nil end
    return out
end

-- Replaces ONE tab of the guild's record from a complete observation. tab = { n = { [itemID] = count }, by = "Name - Realm", w = 1|0|nil, lim, rem }.
-- nt is how many tabs the guild bank has (tabs past it are dropped). Returns true, or false and why ("held", "unsaved", "bad").
function St.StoreGuildTab(id, index, tab, now, nt)
    if St.Held() then return false, "held" end
    now = Int(now or Q.Now(), 1, MAX_TIME)
    index = Int(index, 1, St.MAX_GUILD_TABS)
    local key = type(id) == "table" and Text(id.key, 100) or nil
    local n = type(tab) == "table" and CleanItems(tab.n, true) or nil
    if not (now and index and key and n) then return false, "bad" end
    local s = Root(true)
    if not s then return false, "unsaved" end
    s.v = St.SAVED_VERSION
    if type(s.guilds) ~= "table" then s.guilds = {} end
    local rec = s.guilds[key]
    if type(rec) ~= "table" or not SameGuild(rec, id) or type(rec.tabs) ~= "table" then
        rec = { tabs = {} }   -- a guild never seen, or one re-made under the same name: nothing carries over
        s.guilds[key] = rec
    end
    rec.name = Text(id.name, 60)
    rec.club = Text(id.club, 40) or rec.club
    local count = Int(nt, 1, St.MAX_GUILD_TABS)
    if count and count < index then count = index end
    if count then
        rec.nt = count
        for i = count + 1, St.MAX_GUILD_TABS do rec.tabs[i] = nil end
    end
    local rem = Int(tab.rem, -1, W.MAX_ID)
    rec.tabs[index] = { at = now, n = n, by = Text(tab.by, 80), w = Int(tab.w, 0, 1), lim = Int(tab.lim, -1, W.MAX_ID), rem = rem,
        remAt = rem ~= nil and now or nil }
    rec.at = now
    -- over the limit: the guild observed longest ago goes (never the one just written)
    local guilds = 0
    for _ in pairs(s.guilds) do guilds = guilds + 1 end
    while guilds > St.MAX_GUILDS do
        local oldest, oldAt
        for k, g in pairs(s.guilds) do
            local at = k ~= key and type(g) == "table" and tonumber(g.at) or 0
            if k ~= key and (not oldAt or at < oldAt) then oldest, oldAt = k, at end
        end
        if oldest == nil then break end
        s.guilds[oldest] = nil
        guilds = guilds - 1
    end
    Changed()
    return true
end

-- One tab may have changed since it was read. Returns true when that was news.
function St.MarkGuildTabUncertain(id, index)
    if St.Held() then return false end
    local s = Root(false)
    local key = type(id) == "table" and Text(id.key, 100) or nil
    local rec = s and type(s.guilds) == "table" and key and s.guilds[key] or nil
    index = Int(index, 1, St.MAX_GUILD_TABS)
    local tab = index and type(rec) == "table" and SameGuild(rec, id) and type(rec.tabs) == "table" and rec.tabs[index] or nil
    if type(tab) ~= "table" or tab.u == true then return false end
    tab.u = true
    Changed()
    return true
end

---------------------------------------------------------------------------
-- For the diagnostics
---------------------------------------------------------------------------
function St.Counts()
    local out = { bankTabs = 0, bankItems = 0, guilds = 0, guildTabs = 0, guildItems = 0 }
    local b = St.Bank()
    if b then
        for _, t in pairs(b.tabs) do
            out.bankTabs = out.bankTabs + 1
            for _ in pairs(t.n) do out.bankItems = out.bankItems + 1 end
        end
    end
    local s = Root(false)
    if s and type(s.guilds) == "table" then
        for _, g in pairs(s.guilds) do
            if type(g) == "table" and type(g.tabs) == "table" then
                out.guilds = out.guilds + 1
                for _, t in pairs(g.tabs) do
                    if type(t) == "table" and type(t.n) == "table" then
                        out.guildTabs = out.guildTabs + 1
                        for _ in pairs(t.n) do out.guildItems = out.guildItems + 1 end
                    end
                end
            end
        end
    end
    return out
end
