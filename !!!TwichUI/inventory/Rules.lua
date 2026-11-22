-- TwichUI: Magic Inventory, the rules
-- What the player sets up: rules that say which items go where, the named destinations they send to, and the
-- account-wide "Never transfer" list. No frames, no game actions; Items.lua reads items, Plan.lua decides, Run.lua
-- moves things and only when the player asks at a mailbox, bank or guild bank (docs/magic-inventory.md).
--
-- Where it is saved:
--   TwichUIDB.ui.magicInventory      per profile: { rules = { rule, ... }, dests = { dest, ... } }. The list order of
--                                    rules is their priority. A dest is a NAME for a place ("Bank alt"), never a
--                                    recipient: { id, kind = "mail" | "guild", label }.
--   TwichUIDB.magicInventory         account-wide, never in a profile, a share or a backup:
--                                    never = { [itemID] = true }       the Never transfer list (a protection)
--                                    chars["Name - Realm"][destId]     what a dest is on that character:
--                                        { recipient = "Name" } or { guild = "Guild", tab = 2, tabName = "Mats" }
--                                    shared[destId] = { recipient }    a recipient the player chose to use on all
--                                                                      their characters (mail only, explicit)
--                                    guilds[guild] = { tabs = { [n] = { name, icon } } }   the tabs of a guild bank as
--                                                                      last seen (names for choosing a tab with the bank
--                                                                      closed; never used to plan anything)
-- So a rule copied to another character (or another profile, or a backup restored) never sends to a recipient that
-- character didn't choose: until one is set there, the rule says it needs one and stays off.
--
-- Rule: { id, name, enabled, kind = "mail" | "bank" | "guild" | "keep" | "never", dest = destId (mail, guild),
--         cats = { "7:5", "7", ... } (game classes/subclasses and supported custom categories),
--         qualities = { [0..5] = true } (none: any), equip = "any" | "equipment" | "other",
--         bind = "any" | "boe" | "nobind", include = { [itemID] = true }, exclude = { [itemID] = true },
--         keep = 0..9999 (how many of EACH matching item stays in the bags; 0: none; for a rule that withdraws, the
--         amount it tops the bags up to),
--         flow = "deposit" | "withdraw" | "balance" (bank and guild bank rules only: deposit what is above keep, take out
--         of that bank up to keep, or both; absent on an older save: "deposit", so an older TwichUI reads a withdrawing
--         rule as a depositing one and keeps it),
--         stack = 0..9999 (a guild bank rule's target stack size: the size each stack of a matching item should end up,
--         one smaller stack holding the rest; 0: no target),
--         and, only on a rule the guild bank arrangement editor made (design = true, guild rules only; docs/magic-inventory.md,
--         "The arrangement editor"):
--         design = true, place = { { slot = 1..98, id = itemID, count = 1..9999 }, ... } (the stacks reserved in the rule's
--         tab, one entry per slot; every id is also in include), sizes = { [itemID] = n } and layout ("packed" | "spaced" | "columns") for how the automatic items are spread, rest = { [itemID] = true } (the items whose extras beyond
--         their reserved stacks go to this tab's free slots) }
-- Reading never writes; an entry that can't be read is left out of the next write. Nothing of a visit is saved.

local R = TwichUI
local MI = {}
R.MagicInventory = MI

MI.MAX_RULES = 40
MI.MAX_DESTS = 12
MI.MAX_IDS = 100        -- items in a rule's "Also include" or "Never include" list
MI.MAX_NEVER = 200
MI.MAX_KEEP = 9999
MI.MAX_STACK = 9999        -- a guild bank rule's target stack size (each item's own limit is checked when planning)
MI.MAX_GUILDS = 8         -- guilds whose tab names are remembered
MI.MAX_GUILD_TABS = 8     -- MAX_GUILDBANK_TABS in the Forever Constants.lua
MI.GUILD_SLOTS = 98       -- MAX_GUILDBANK_SLOTS_PER_TAB (GuildBank.SLOTS says the same; this file loads first)
MI.MAX_NAME = 48
MI.MAX_CATS = 24
-- how an arrangement tab spreads its automatically placed items (Design.lua D.Layout): from slot 1 without gaps, with one empty
-- slot between different items, or with each different item starting a new column of 14 (the bank draws 7 columns of 14)
MI.LAYOUTS = { packed = "Packed from the first slot", spaced = "One empty slot between items", columns = "Each item starts a new column" }
MI.LAYOUT_ORDER = { "packed", "spaced", "columns" }
MI.GUILD_COLUMN = 14

MI.KIND_ORDER = { "mail", "bank", "guild", "keep", "never" }
MI.KIND_LABEL = {
    mail = "Send by mail", bank = "Deposit in bank", guild = "Deposit in guild bank",
    keep = "Keep in bags", never = "Never transfer",
}
MI.TRANSFER = { mail = true, bank = true, guild = true }   -- kinds that move items (keep and never only protect)
MI.NEEDS_DEST = { mail = true, guild = true }

-- Which way a bank or guild bank rule moves items. Withdrawing never goes over the rule's
-- keep amount (its target); the item has to be in that bank.
MI.HAS_FLOW = { bank = true, guild = true }
MI.FLOW_ORDER = { "deposit", "withdraw", "balance" }
MI.FLOW_LABEL = { deposit = "Deposit extras", withdraw = "Withdraw to top up", balance = "Balance both ways" }
-- deposits: moves items out of the bags (every transfer kind, unless it only withdraws); withdraws: takes items out of a bank
function MI.Deposits(rule) return MI.TRANSFER[rule.kind] == true and rule.flow ~= "withdraw" end
function MI.Withdraws(rule) return MI.HAS_FLOW[rule.kind] == true and (rule.flow == "withdraw" or rule.flow == "balance") end

MI.EQUIP = { any = true, equipment = true, other = true }
MI.BIND = { any = true, boe = true, nobind = true }

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
MI.Plain = Plain

local function ValidID(id)
    return type(id) == "number" and id == id and id >= 1 and id <= 2147483647 and math.floor(id) == id
end
MI.ValidID = ValidID

local function Whole(v, lo, hi)
    return type(v) == "number" and v == v and math.floor(v) == v and v >= lo and v <= hi
end

-- Text a player typed for a name: trimmed, one line, no escape codes, at most `max` bytes.
local function CleanName(text, max)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if #text > max then text = text:sub(1, max) end
    return text
end
MI.CleanName = CleanName

---------------------------------------------------------------------------
-- Changes: one notification and one generation counter for everything a plan depends on. A plan made at an older
-- generation is stale (Run.lua refuses to act on it).
---------------------------------------------------------------------------
local generation = 0
local listeners = {}
function MI.Generation() return generation end
function MI.OnChange(fn) listeners[#listeners + 1] = fn end
function MI.Changed()
    generation = generation + 1
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("magic inventory", err) end
    end
end

function MI.Enabled() return type(TwichUIDB) == "table" and type(TwichUIDB.modules) == "table" and TwichUIDB.modules.magicInventory == true end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function ProfileStore(create)
    if type(TwichUIDB) ~= "table" then return nil end
    if create then
        if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
        if type(TwichUIDB.ui.magicInventory) ~= "table" then TwichUIDB.ui.magicInventory = {} end
    end
    local ui = TwichUIDB.ui
    return type(ui) == "table" and type(ui.magicInventory) == "table" and ui.magicInventory or nil
end

local function AccountStore(create)
    if type(TwichUIDB) ~= "table" then return nil end
    if create and type(TwichUIDB.magicInventory) ~= "table" then TwichUIDB.magicInventory = {} end
    return type(TwichUIDB.magicInventory) == "table" and TwichUIDB.magicInventory or nil
end

local function Sub(t, key, create)
    if not t then return nil end
    if create and type(t[key]) ~= "table" then t[key] = {} end
    return type(t[key]) == "table" and t[key] or nil
end

function MI.CharKey()
    local name = Plain(UnitName and UnitName("player"))
    local realm = Plain(GetRealmName and GetRealmName())
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. " - " .. realm
end

-- A fresh id for a rule or a destination: unique in the list it goes into, and across this session.
local made = 0
local function NewId(prefix, taken)
    repeat
        made = made + 1
        local id = ("%s%x%x"):format(prefix, (time and time() or 0) % 1048576, made)
        if not taken[id] then return id end
    until false
end

local function IdText(v) return type(v) == "string" and #v >= 2 and #v <= 24 and v:match("^[%w]+$") ~= nil end

---------------------------------------------------------------------------
-- Checking a stored rule or destination. Returns a clean copy, or nil when it can't be used at all.
---------------------------------------------------------------------------
local function CleanSet(t, max, valid)
    local out, n = {}, 0
    if type(t) ~= "table" then return out end
    local keys = {}
    for k, v in pairs(t) do if v == true and valid(k) then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
        if n >= max then break end
        out[k], n = true, n + 1
    end
    return out
end

MI.WAYLAID_CATEGORY = "waylaid-crates"

local function ValidCat(v)
    if v == MI.WAYLAID_CATEGORY then return true end
    if type(v) ~= "string" then return false end
    local c, s = v:match("^(%d+):(%d+)$")
    if c then return Whole(tonumber(c), 0, 99) and Whole(tonumber(s), 0, 999) end
    return v:match("^%d+$") ~= nil and Whole(tonumber(v), 0, 99)
end
MI.ValidCat = ValidCat

local function CleanRule(r)
    if type(r) ~= "table" or not IdText(r.id) then return nil end
    local kind = MI.KIND_LABEL[r.kind] and r.kind or nil
    if not kind then return nil end
    local out = {
        id = r.id, kind = kind,
        name = CleanName(r.name, MI.MAX_NAME) or "Untitled rule",
        enabled = r.enabled == true,
        equip = MI.EQUIP[r.equip] and r.equip or "any",
        bind = MI.BIND[r.bind] and r.bind or "any",
        include = CleanSet(r.include, MI.MAX_IDS, ValidID),
        exclude = CleanSet(r.exclude, MI.MAX_IDS, ValidID),
        qualities = CleanSet(r.qualities, 8, function(q) return Whole(q, 0, 7) end),
        keep = Whole(r.keep, 0, MI.MAX_KEEP) and r.keep or 0,
        stack = kind == "guild" and Whole(r.stack, 0, MI.MAX_STACK) and r.stack or 0,
        cats = {},
    }
    if MI.NEEDS_DEST[kind] and IdText(r.dest) then out.dest = r.dest end
    if MI.HAS_FLOW[kind] then out.flow = MI.FLOW_LABEL[r.flow] and r.flow or "deposit" end
    if kind == "guild" and r.design == true then
        out.flow = "deposit"   -- an arrangement says where items belong in the bank; it never takes them out
        -- the arrangement editor's rule: reserved stacks (one per slot, in slot order) and the items that take extras
        out.design = true
        local used, place = {}, {}
        if type(r.place) == "table" then
            for _, e in ipairs(r.place) do
                if type(e) == "table" and Whole(e.slot, 1, MI.GUILD_SLOTS) and ValidID(e.id) and Whole(e.count, 1, MI.MAX_STACK) and not used[e.slot] then
                    local n = 0
                    for _ in pairs(out.include) do n = n + 1 end
                    if out.include[e.id] or n < MI.MAX_IDS then
                        used[e.slot] = true
                        out.include[e.id] = true
                        place[#place + 1] = { slot = e.slot, id = e.id, count = e.count }
                    end
                end
            end
        end
        table.sort(place, function(a, b) return a.slot < b.slot end)
        out.place = place
        out.rest = CleanSet(r.rest, MI.MAX_IDS, function(id) return ValidID(id) and out.include[id] == true end)
        -- the size each automatically placed item is spread in (absent: a full stack) and how the tab is laid out
        local sizes = {}
        if type(r.sizes) == "table" then
            for id, n in pairs(r.sizes) do
                if ValidID(id) and out.include[id] and Whole(n, 1, MI.MAX_STACK) then sizes[id] = n end
            end
        end
        out.sizes = sizes
        out.layout = MI.LAYOUTS[r.layout] and r.layout or "packed"
    end
    local seen = {}
    if type(r.cats) == "table" then
        for _, c in ipairs(r.cats) do
            if #out.cats >= MI.MAX_CATS then break end
            if ValidCat(c) and not seen[c] then seen[c] = true; out.cats[#out.cats + 1] = c end
        end
    end
    return out
end
MI.CleanRule = CleanRule

local function CleanDest(d)
    if type(d) ~= "table" or not IdText(d.id) or not MI.NEEDS_DEST[d.kind] then return nil end
    return { id = d.id, kind = d.kind, label = CleanName(d.label, MI.MAX_NAME) or (d.kind == "mail" and "Mail recipient" or "Guild bank tab") }
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- The rules, in priority order: clean copies (changing them changes nothing saved).
function MI.Rules()
    local t = ProfileStore(false)
    local out, seen = {}, {}
    if t and type(t.rules) == "table" then
        for _, r in ipairs(t.rules) do
            if #out >= MI.MAX_RULES then break end
            local c = CleanRule(r)
            if c and not seen[c.id] then seen[c.id] = true; out[#out + 1] = c end
        end
    end
    return out
end

function MI.Rule(id)
    for i, r in ipairs(MI.Rules()) do
        if r.id == id then return r, i end
    end
end

function MI.Dests()
    local t = ProfileStore(false)
    local out, seen = {}, {}
    if t and type(t.dests) == "table" then
        for _, d in ipairs(t.dests) do
            if #out >= MI.MAX_DESTS then break end
            local c = CleanDest(d)
            if c and not seen[c.id] then seen[c.id] = true; out[#out + 1] = c end
        end
    end
    return out
end

function MI.Dest(id)
    for _, d in ipairs(MI.Dests()) do
        if d.id == id then return d end
    end
end

---------------------------------------------------------------------------
-- Recipients. A recipient is checked for its form only: a name the game could accept as one. TwichUI can't tell
-- whether the character exists or who plays it, and says so; it never changes one name into another beyond the
-- game's own capitalization.
---------------------------------------------------------------------------
local function Utf8Len(s)
    local n = 0
    for _ in s:gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

-- Returns the recipient as it will be sent ("Name" or "Name-Realm"), or nil and a sentence.
function MI.NormalizeRecipient(text)
    if type(text) ~= "string" then return nil, "Type the character's name." end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, "Type the character's name." end
    local name, realm = text:match("^([^%-]+)%-(.+)$")
    if not name then name = text end
    if name:find("[%s%d%p%c]") then return nil, "A character's name has only letters: no spaces, numbers or punctuation." end
    local len = Utf8Len(name)
    if len < 2 or len > 12 then return nil, "A character's name is 2 to 12 letters long." end
    if realm then
        realm = realm:gsub("%s", "")
        if realm == "" or #realm > 40 or realm:find("[%c|%-]") then return nil, "Write another realm as Name-Realm." end
    end
    -- the game's own form: an ASCII first letter in capitals, the rest of the ASCII letters lower case
    local first = name:sub(1, 1)
    if first:match("%a") then
        name = first:upper() .. name:sub(2):gsub("%u", string.lower)
    end
    local me = Plain(UnitName and UnitName("player"))
    local myRealm = Plain(GetNormalizedRealmName and GetNormalizedRealmName())
    if type(me) == "string" and name:lower() == me:lower() and (not realm or (type(myRealm) == "string" and realm:lower() == myRealm:lower())) then
        return nil, "That is this character: the game doesn't send mail to yourself."
    end
    return realm and (name .. "-" .. realm) or name
end

-- What a destination is on this character: { recipient, shared } for mail, { guild, tab, tabName } for a guild
-- tab, or nil while nothing is chosen here.
function MI.Resolve(destId)
    local d = MI.Dest(destId)
    if not d then return nil end
    local acct = AccountStore(false)
    local key = MI.CharKey()
    local chars = Sub(acct, "chars", false)
    local mine = key and chars and type(chars[key]) == "table" and chars[key][destId]
    if d.kind == "mail" then
        if type(mine) == "table" and type(mine.recipient) == "string" then
            local name = MI.NormalizeRecipient(mine.recipient)
            if name then return { kind = "mail", recipient = name, label = d.label, id = d.id } end
        end
        local shared = Sub(acct, "shared", false)
        local s = shared and shared[destId]
        if type(s) == "table" and type(s.recipient) == "string" then
            local name = MI.NormalizeRecipient(s.recipient)
            if name then return { kind = "mail", recipient = name, label = d.label, id = d.id, shared = true } end
        end
        return nil
    end
    if type(mine) == "table" and type(mine.guild) == "string" and mine.guild ~= "" and Whole(mine.tab, 1, 16) then
        return { kind = "guild", guild = mine.guild, tab = mine.tab, tabName = type(mine.tabName) == "string" and mine.tabName or nil,
            tabIcon = (type(mine.tabIcon) == "number" or type(mine.tabIcon) == "string") and mine.tabIcon or nil,
            label = d.label, id = d.id }
    end
    return nil
end

local function CharDests(create)
    local key = MI.CharKey()
    if not key then return nil end
    local chars = Sub(AccountStore(create), "chars", create)
    return Sub(chars, key, create)
end

-- Writes an already normalized recipient for a mail destination, with no notification: this character's own
-- (allChars false) or the account-wide one (allChars true, which also removes this character's own so the shared one is
-- used here). Returns true, or false and a sentence. Callers check the destination first.
local function PutRecipient(destId, name, allChars)
    if allChars then
        local shared = Sub(AccountStore(true), "shared", true)
        if not shared then return false, "Your settings aren't available right now." end
        shared[destId] = { recipient = name }
        local mine = CharDests(false)
        if mine then mine[destId] = nil end
        return true
    end
    local mine = CharDests(true)
    if not mine then return false, "Your settings aren't available right now." end
    mine[destId] = { recipient = name }
    return true
end

-- Clears a mail destination's recipient. scope "char" (this character's own only: an account-wide recipient, if there
-- is one, is used here again), "shared" (the account-wide one only: characters with their own keep theirs) or "both".
-- Returns true when something was cleared.
function MI.ClearRecipient(destId, scope)
    local d = MI.Dest(destId)
    if not (d and d.kind == "mail") then return false end
    local cleared = false
    if scope == "char" or scope == "both" then
        local mine = CharDests(false)
        if mine and mine[destId] ~= nil then mine[destId], cleared = nil, true end
    end
    if scope == "shared" or scope == "both" then
        local shared = Sub(AccountStore(false), "shared", false)
        if shared and shared[destId] ~= nil then shared[destId], cleared = nil, true end
    end
    if cleared then MI.Changed() end
    return cleared
end

-- Where a mail destination's recipient comes from on this character: "char" (this character's own), "shared" (the
-- account-wide one) or nil; and whether an account-wide one exists behind this character's own.
function MI.RecipientSource(destId)
    local acct = AccountStore(false)
    local key = MI.CharKey()
    local chars = Sub(acct, "chars", false)
    local mine = key and chars and type(chars[key]) == "table" and chars[key][destId]
    local shared = Sub(acct, "shared", false)
    local s = shared and shared[destId]
    local hasShared = type(s) == "table" and type(s.recipient) == "string" and MI.NormalizeRecipient(s.recipient) ~= nil
    if type(mine) == "table" and type(mine.recipient) == "string" and MI.NormalizeRecipient(mine.recipient) then return "char", hasShared end
    if hasShared then return "shared", true end
    return nil, false
end

-- Sets (or with text nil, clears) this character's recipient for a mail destination. allChars: keep it for every
-- character of this account instead (the player's explicit choice); clearing with text nil clears both (MI.ClearRecipient
-- clears one of them). Returns true, or false and a sentence.
function MI.SetRecipient(destId, text, allChars)
    local d = MI.Dest(destId)
    if not (d and d.kind == "mail") then return false, "That destination isn't there any more." end
    local name
    if text ~= nil then
        local why
        name, why = MI.NormalizeRecipient(text)
        if not name then return false, why end
    end
    if name == nil then
        local mine = CharDests(false)
        local shared = Sub(AccountStore(false), "shared", false)
        if mine then mine[destId] = nil end
        if shared then shared[destId] = nil end
    else
        local ok, why = PutRecipient(destId, name, allChars)
        if not ok then return false, why end
    end
    MI.Changed()
    return true, name
end

-- Sets this character's guild bank tab for a guild destination: what the guild bank shows now, chosen by the player
-- with the guild bank open (or from the tabs last seen). tab: the tab's number; guild, tabName and the icon as the
-- game names them.
function MI.SetGuildTab(destId, guild, tab, tabName, tabIcon)
    local d = MI.Dest(destId)
    if not (d and d.kind == "guild") then return false, "That destination isn't there any more." end
    local mine = CharDests(guild ~= nil)
    if guild == nil then
        if mine then mine[destId] = nil end
        MI.Changed()
        return true
    end
    if type(guild) ~= "string" or guild == "" or not Whole(tab, 1, 16) then return false, "Open the guild bank on the tab you want first." end
    if not mine then return false, "Your settings aren't available right now." end
    if type(tabIcon) ~= "number" and type(tabIcon) ~= "string" then tabIcon = nil end
    mine[destId] = { guild = guild, tab = tab, tabName = CleanName(tabName, 64), tabIcon = tabIcon }
    MI.Changed()
    return true
end

-- The tabs of a guild's bank as last seen, { [n] = { name, icon } }: written when the guild bank shows them (only when
-- something differs) so a tab can be chosen with the bank closed. Names for choosing only: nothing is planned from it.
function MI.NoteGuildTabs(guild, tabs)
    if type(guild) ~= "string" or guild == "" or type(tabs) ~= "table" then return end
    local acct = AccountStore(true)
    local guilds = Sub(acct, "guilds", true)
    if not guilds then return end
    local n = 0
    for _ in pairs(guilds) do n = n + 1 end
    if guilds[guild] == nil and n >= MI.MAX_GUILDS then return end
    local clean = {}
    for i = 1, MI.MAX_GUILD_TABS do
        local t = tabs[i]
        local name = type(t) == "table" and CleanName(t.name, 64)
        if name then
            clean[i] = { name = name, icon = (type(t.icon) == "number" or type(t.icon) == "string") and t.icon or nil }
        end
    end
    local old = type(guilds[guild]) == "table" and guilds[guild].tabs
    if next(clean) == nil and old == nil then return end   -- nothing named yet: nothing to remember
    local same = type(old) == "table"
    for i = 1, MI.MAX_GUILD_TABS do
        local a, b = clean[i], type(old) == "table" and old[i]
        if (a == nil) ~= (not b) or (a and b and (a.name ~= b.name or a.icon ~= b.icon)) then same = false end
    end
    if same then return end
    guilds[guild] = { tabs = clean }
end

-- { [n] = { name, icon } } for a guild, or an empty list.
function MI.GuildTabsSeen(guild)
    local guilds = Sub(AccountStore(false), "guilds", false)
    local g = type(guild) == "string" and guilds and guilds[guild]
    local out = {}
    if type(g) == "table" and type(g.tabs) == "table" then
        for i = 1, MI.MAX_GUILD_TABS do
            local t = g.tabs[i]
            if type(t) == "table" and type(t.name) == "string" then out[i] = { name = t.name, icon = t.icon } end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- What stops a rule from running: nil when it can, otherwise a code and a sentence. Read when drawn; never saved.
-- guildNow: the character's guild as the game names it now (nil: not in one, false: unknown, don't check).
---------------------------------------------------------------------------
function MI.HasItems(rule)
    return #rule.cats > 0 or next(rule.qualities) ~= nil or rule.equip ~= "any" or rule.bind ~= "any" or next(rule.include) ~= nil
end

function MI.Problem(rule, guildNow)
    if not MI.HasItems(rule) then return "no-items", "Choose which items it is for." end
    if MI.Withdraws(rule) and (rule.keep or 0) <= 0 then return "no-target", "Choose how many to keep in your bags: that is what it withdraws up to." end
    if not MI.NEEDS_DEST[rule.kind] then return nil end
    local d = rule.dest and MI.Dest(rule.dest)
    if not d or d.kind ~= rule.kind then
        return "no-destination", rule.kind == "mail" and "Type the recipient character's name." or "Choose a guild bank tab."
    end
    local where = MI.Resolve(d.id)
    if not where then
        if rule.kind == "mail" then return "no-recipient", ("Choose the recipient for \"%s\" on this character: edit the rule and type the character's name."):format(d.label) end
        return "no-guild-tab", ("Choose the guild bank tab for \"%s\" on this character."):format(d.label)
    end
    if rule.kind == "guild" and guildNow ~= false then
        if guildNow == nil or guildNow ~= where.guild then
            return "guild-changed", ("\"%s\" was chosen in <%s>; this character is in %s now. Review it before depositing."):format(
                d.label, where.guild, guildNow and ("<" .. guildNow .. ">") or "no guild")
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Writing. Every write stores the whole list as it reads (clean), and is one change.
---------------------------------------------------------------------------
local function WriteRules(list)
    local t = ProfileStore(true)
    if not t then return false end
    local out = {}
    for i, r in ipairs(list) do out[i] = CleanRule(r) end
    t.rules = out
    MI.Changed()
    return true
end

local function WriteDests(list)
    local t = ProfileStore(true)
    if not t then return false end
    local out = {}
    for i, d in ipairs(list) do out[i] = CleanDest(d) end
    t.dests = out
    MI.Changed()
    return true
end

-- A new destination name of a kind. Returns its id, or nil and a sentence.
function MI.AddDest(kind, label)
    if not MI.NEEDS_DEST[kind] then return nil, "That kind of destination has nothing to choose." end
    local list = MI.Dests()
    if #list >= MI.MAX_DESTS then return nil, ("You can keep %d destinations; remove one first."):format(MI.MAX_DESTS) end
    local taken = {}
    for _, d in ipairs(list) do taken[d.id] = true end
    local id = NewId("d", taken)
    list[#list + 1] = { id = id, kind = kind, label = CleanName(label, MI.MAX_NAME) or (kind == "mail" and "Mail recipient" or "Guild bank tab") }
    if not WriteDests(list) then return nil, "Your settings aren't available right now." end
    return id
end

function MI.RenameDest(id, label)
    label = CleanName(label, MI.MAX_NAME)
    if not label then return false, "Give it a name." end
    local list = MI.Dests()
    for _, d in ipairs(list) do
        if d.id == id then
            if d.label == label then return true end
            d.label = label
            return WriteDests(list)
        end
    end
    return false, "That destination isn't there any more."
end

-- Removes a destination name. Rules that used it keep their place in the list and say they need a destination.
-- This character's choice for it goes too; other characters' choices are left (they are theirs).
function MI.DeleteDest(id)
    local list, out = MI.Dests(), {}
    for _, d in ipairs(list) do if d.id ~= id then out[#out + 1] = d end end
    if #out == #list then return false end
    local mine = CharDests(false)
    if mine then mine[id] = nil end
    local shared = Sub(AccountStore(false), "shared", false)
    if shared then shared[id] = nil end
    -- the rules that used it can't be on any more
    local rules, changed = MI.Rules(), false
    for _, r in ipairs(rules) do
        if r.dest == id then r.dest, r.enabled, changed = nil, false, true end
    end
    if changed then
        local t = ProfileStore(true)
        local outRules = {}
        for i, r in ipairs(rules) do outRules[i] = CleanRule(r) end
        t.rules = outRules
    end
    return WriteDests(out)
end

-- Replaces the whole rule list in one write (the arrangement editor's save: its own rules changed, every other rule as it
-- was). An entry without an id gets a new one. Returns true, or false and a sentence; nothing is written on failure.
function MI.ReplaceRules(list)
    if type(list) ~= "table" then return false, "Nothing to save." end
    if #list > MI.MAX_RULES then return false, ("You can keep %d rules; remove one first."):format(MI.MAX_RULES) end
    local taken = {}
    for _, r in ipairs(list) do if type(r) == "table" and r.id then taken[r.id] = true end end
    local out = {}
    for i, r in ipairs(list) do
        local copy = {}
        for k, v in pairs(r) do copy[k] = v end
        if not copy.id then copy.id = NewId("r", taken); taken[copy.id] = true end
        out[i] = CleanRule(copy)
        if not out[i] then return false, "A rule can't be saved." end
    end
    if not WriteRules(out) then return false, "Your settings aren't available right now." end
    return true
end

-- Saves a rule (new when its id isn't in the list; at the end). A rule that can't run yet is saved turned off.
-- Returns the id, or nil and a sentence.
function MI.SaveRule(rule)
    if type(rule) ~= "table" then return nil, "Nothing to save." end
    local list = MI.Rules()
    local taken, at = {}, nil
    for i, r in ipairs(list) do
        taken[r.id] = true
        if r.id == rule.id then at = i end
    end
    local copy = {}
    for k, v in pairs(rule) do copy[k] = v end
    if not at then
        if #list >= MI.MAX_RULES then return nil, ("You can keep %d rules; remove one first."):format(MI.MAX_RULES) end
        copy.id = NewId("r", taken)
    end
    local clean = CleanRule(copy)
    if not clean then return nil, "That rule can't be saved." end
    if clean.enabled and MI.Problem(clean, false) then clean.enabled = false end
    if at then list[at] = clean else list[#list + 1] = clean end
    if not WriteRules(list) then return nil, "Your settings aren't available right now." end
    return clean.id
end

---------------------------------------------------------------------------
-- A mail rule's recipient, typed in the rule builder. The builder keeps it as part of the rule draft:
--   draft = { text = "Name" | "Name-Realm" | nil (unchanged: whatever the rule's destination is here),
--             allChars = true (the account-wide recipient, the player's explicit choice; default this character only),
--             updateShared = true (change the destination the rule shares with other rules, for all of them: the
--             player's explicit choice, after being shown which rules) }
-- Nothing is written until MI.SaveRuleDraft, which checks everything first and writes the rule, any new destination
-- and the recipient as one change. Recipients stay in the account's table (never in the profile's rules), as before.
---------------------------------------------------------------------------

-- The other rules (in this profile) that send to a destination: { { id, name }, ... }, in priority order.
function MI.RulesUsing(destId, exceptId)
    local out = {}
    if not destId then return out end
    for _, r in ipairs(MI.Rules()) do
        if r.dest == destId and r.id ~= exceptId then out[#out + 1] = { id = r.id, name = r.name } end
    end
    return out
end

-- A destination of a kind with a name, or nil (nothing is made).
function MI.FindDestNamed(kind, label)
    if type(label) ~= "string" then return nil end
    for _, d in ipairs(MI.Dests()) do
        if d.kind == kind and d.label:lower() == label:lower() then return d.id end
    end
end

local function Blank(text) return text == nil or (type(text) == "string" and text:match("^%s*$") ~= nil) end

-- What saving a mail rule's draft would do, without writing anything. Returns a plan, or nil and a sentence:
--   { dest = id or nil (a new destination is made), recipient = "Name" or nil (none on this character),
--     write = nil | "char" | "shared" (the recipient write, on plan.dest or the new one), create = label of a new
--     destination, reuse = true when another destination already sends to that name, others = the rules that share
--     the rule's current destination, ruleOnly = true when the change applies to this rule only }
function MI.PlanRecipient(rule, draft)
    draft = type(draft) == "table" and draft or {}
    local cur = rule and rule.dest and MI.Dest(rule.dest)
    if cur and cur.kind ~= "mail" then cur = nil end
    local where = cur and MI.Resolve(cur.id)
    local others = cur and MI.RulesUsing(cur.id, rule.id) or {}
    if draft.text == nil then
        return { dest = cur and cur.id, recipient = where and where.recipient, shared = where and where.shared, others = others }
    end
    if Blank(draft.text) then
        -- an empty box: the rule keeps its destination, and whatever it is here; nothing is cleared from a rule
        if where then return nil, "Type the recipient character's name, or choose a saved recipient." end
        return { dest = cur and cur.id, others = others }
    end
    local name, why = MI.NormalizeRecipient(draft.text)
    if not name then return nil, why end
    local allChars = draft.allChars == true
    local plan = { recipient = name, shared = allChars, others = others }
    -- already so: nothing to write
    if where and where.recipient == name and (not allChars or (where.shared and MI.RecipientSource(cur.id) == "shared")) then
        plan.dest, plan.shared = cur.id, where.shared
        return plan
    end
    -- the rule's own destination (no other rule sends to it), or the shared one when the player chose to change it for all
    if cur and (#others == 0 or draft.updateShared == true) then
        plan.dest, plan.write, plan.ruleOnly = cur.id, allChars and "shared" or "char", #others == 0
        return plan
    end
    -- another destination that already sends to that name here: this rule uses it, nothing else changes
    for _, d in ipairs(MI.Dests()) do
        if d.kind == "mail" and (not cur or d.id ~= cur.id) then
            local w = MI.Resolve(d.id)
            if w and w.recipient == name and (not allChars or (w.shared and MI.RecipientSource(d.id) == "shared")) then
                plan.dest, plan.reuse, plan.shared, plan.ruleOnly = d.id, true, w.shared, true
                return plan
            end
        end
    end
    -- a new destination for this rule only. Its label is never the recipient's name: labels are in the profile, which can
    -- be copied, shared or backed up; the recipient stays in the account's table. A template's own label ("Bank alt") or a
    -- numbered "Mail recipient" is used, and the player may rename it under Recipients (never required).
    local dests = MI.Dests()
    if #dests >= MI.MAX_DESTS then
        return nil, ("You keep %d recipients and guild bank tabs already: choose a saved recipient, or remove one under Recipients."):format(MI.MAX_DESTS)
    end
    local label = CleanName(draft.label, MI.MAX_NAME)
    if label and label:lower() == name:lower() then label = nil end
    if not label or MI.FindDestNamed("mail", label) then
        local used = {}
        for _, d in ipairs(dests) do used[d.label:lower()] = true end
        local n = 1
        label = "Mail recipient"
        while used[label:lower()] do n = n + 1; label = ("Mail recipient %d"):format(n) end
    end
    plan.create, plan.write, plan.ruleOnly = label, allChars and "shared" or "char", true
    return plan
end

-- What still stops a rule draft from running, counting the recipient typed with it: nil, or a code and a sentence.
function MI.DraftProblem(rule, draft)
    local clean = {}
    for k, v in pairs(rule) do clean[k] = v end
    clean.id = IdText(clean.id) and clean.id or "rdraft"
    clean = CleanRule(clean)
    if not clean then return "invalid", "That rule can't be saved." end
    if clean.kind ~= "mail" then return MI.Problem(clean, false) end
    local plan, why = MI.PlanRecipient(clean, draft)
    if not plan then return "bad-recipient", why end
    if not MI.HasItems(clean) then return MI.Problem(clean, false) end
    if not plan.recipient then
        if plan.dest then return MI.Problem(clean, false) end
        return "no-destination", "Type the recipient character's name."
    end
    return nil
end

-- Saves a rule draft and, for a mail rule, the recipient typed with it (MI.PlanRecipient), as one change: everything is
-- checked first, and if any write fails every earlier one is put back. A rule that can't run yet is saved off, as
-- MI.SaveRule does; a rule is never turned on that the draft didn't turn on. expectId: the saved rule the draft was made
-- from (nil for a new rule): if it is gone, nothing is saved. Returns the rule id and the plan, or nil and a sentence.
function MI.SaveRuleDraft(rule, draft, expectId)
    if type(rule) ~= "table" then return nil, "Nothing to save." end
    local t = ProfileStore(true)
    if not t then return nil, "Your settings aren't available right now." end
    local list = MI.Rules()
    local at
    for i, r in ipairs(list) do if r.id == rule.id then at = i end end
    if expectId and (rule.id ~= expectId or not at) then
        return nil, "This rule was removed or changed elsewhere while you edited it. Cancel, then edit it again."
    end
    if not at and #list >= MI.MAX_RULES then return nil, ("You can keep %d rules; remove one first."):format(MI.MAX_RULES) end
    local copy = {}
    for k, v in pairs(rule) do copy[k] = v end
    local taken = {}
    for _, r in ipairs(list) do taken[r.id] = true end
    if not at then copy.id = NewId("r", taken) end
    local plan
    if copy.kind == "mail" then
        local why
        plan, why = MI.PlanRecipient(copy, draft)
        if not plan then return nil, why end
        if plan.write == "char" and not MI.CharKey() then return nil, "Your settings aren't available right now." end
    else
        plan = {}
    end
    if not CleanRule(copy) then return nil, "That rule can't be saved." end
    -- everything checked: write, keeping what was there to put it back
    local acct = AccountStore(plan.write ~= nil)
    local key = MI.CharKey()
    local before = { dests = t.dests, rules = t.rules, chars = nil, shared = nil, destId = nil }
    local function Restore()
        t.dests, t.rules = before.dests, before.rules
        if before.destId then
            local chars = Sub(acct, "chars", false)
            local mine = key and chars and chars[key]
            if type(mine) == "table" then rawset(mine, before.destId, before.chars) end
            local shared = Sub(acct, "shared", false)
            if shared then rawset(shared, before.destId, before.shared) end
        end
    end
    local ok, result = pcall(function()
        local destId = plan.dest
        if plan.create then
            local dests = MI.Dests()
            local dtaken = {}
            for _, d in ipairs(dests) do dtaken[d.id] = true end
            destId = NewId("d", dtaken)
            dests[#dests + 1] = { id = destId, kind = "mail", label = plan.create }
            local out = {}
            for i, d in ipairs(dests) do out[i] = CleanDest(d) end
            t.dests = out
        end
        if plan.write and destId then
            local chars = Sub(acct, "chars", false)
            local mine = key and chars and chars[key]
            local shared = Sub(acct, "shared", false)
            before.destId = destId
            before.chars = type(mine) == "table" and mine[destId] or nil
            before.shared = shared and shared[destId] or nil
            local okPut, why = PutRecipient(destId, plan.recipient, plan.write == "shared")
            if not okPut then error(why or "Your settings aren't available right now.", 0) end
        end
        if copy.kind == "mail" then copy.dest = destId end
        local clean = CleanRule(copy)
        if not clean then error("That rule can't be saved.", 0) end
        if clean.enabled and MI.Problem(clean, false) then clean.enabled = false end
        if at then list[at] = clean else list[#list + 1] = clean end
        local out = {}
        for i, r in ipairs(list) do out[i] = CleanRule(r) end
        t.rules = out
        plan.dest = destId
        return clean.id
    end)
    if not ok then
        Restore()
        return nil, type(result) == "string" and result or "That rule can't be saved."
    end
    MI.Changed()
    return result, plan
end

-- Turns a rule on or off. Turning on is refused while something it needs is missing (returns false and why).
function MI.SetRuleEnabled(id, on)
    local list = MI.Rules()
    for _, r in ipairs(list) do
        if r.id == id then
            on = on and true or false
            if on then
                local code, why = MI.Problem(r, false)
                if code then return false, why end
            end
            if r.enabled == on then return true end
            r.enabled = on
            return WriteRules(list)
        end
    end
    return false, "That rule isn't there any more."
end

function MI.DeleteRule(id)
    local list, out = MI.Rules(), {}
    for _, r in ipairs(list) do if r.id ~= id then out[#out + 1] = r end end
    if #out == #list then return false end
    return WriteRules(out)
end

-- A copy under it, turned off, named "... (copy)".
function MI.DuplicateRule(id)
    local r, i = MI.Rule(id)
    if not r then return nil, "That rule isn't there any more." end
    local list = MI.Rules()
    if #list >= MI.MAX_RULES then return nil, ("You can keep %d rules; remove one first."):format(MI.MAX_RULES) end
    local taken = {}
    for _, x in ipairs(list) do taken[x.id] = true end
    r.id = NewId("r", taken)
    r.enabled = false
    r.name = CleanName(r.name .. " (copy)", MI.MAX_NAME)
    table.insert(list, i + 1, r)
    if not WriteRules(list) then return nil, "Your settings aren't available right now." end
    return r.id
end

-- Moves a rule up (delta -1) or down (+1) the priority list.
function MI.MoveRule(id, delta)
    local list = MI.Rules()
    for i, r in ipairs(list) do
        if r.id == id then
            local j = i + delta
            if j < 1 or j > #list then return false end
            list[i], list[j] = list[j], list[i]
            return WriteRules(list)
        end
    end
    return false
end

-- Puts a rule at a place in the priority list (1 = first), the rules between shifting by one: a drag in the settings
-- table. A place beyond the ends is the nearest end. Returns false when nothing changed.
function MI.MoveRuleTo(id, place)
    place = tonumber(place)
    if not place then return false end
    local list = MI.Rules()
    for i, r in ipairs(list) do
        if r.id == id then
            local j = math.max(1, math.min(#list, math.floor(place)))
            if j == i then return false end
            table.remove(list, i)
            table.insert(list, j, r)
            return WriteRules(list)
        end
    end
    return false
end

---------------------------------------------------------------------------
-- The Never transfer list: item IDs, account-wide, like Mage selling's never-sell list. A protection: no rule, no
-- "Also include" and no profile change lifts it.
---------------------------------------------------------------------------
function MI.IsNever(id)
    local t = Sub(AccountStore(false), "never", false)
    return t ~= nil and t[id] == true
end

function MI.NeverList()
    local out, t = {}, Sub(AccountStore(false), "never", false)
    for id, on in pairs(t or {}) do if on == true and ValidID(id) then out[#out + 1] = id end end
    table.sort(out)
    return out
end

function MI.SetNever(id, on)
    if not ValidID(id) then return false, "That isn't an item." end
    if on then
        if MI.IsNever(id) then return true end
        if #MI.NeverList() >= MI.MAX_NEVER then return false, ("The list holds %d items; remove one first."):format(MI.MAX_NEVER) end
        local t = Sub(AccountStore(true), "never", true)
        if not t then return false, "Your settings aren't available right now." end
        t[id] = true
    else
        local t = Sub(AccountStore(false), "never", false)
        if not (t and t[id] ~= nil) then return true end
        t[id] = nil
    end
    MI.Changed()
    return true
end

-- An item ID from a number, an item link or text holding an ID.
function MI.ParseItem(v)
    if type(v) == "string" then v = tonumber(v:match("item:(%d+)") or v:match("^%s*(%d+)%s*$")) end
    return ValidID(v) and v or nil
end

---------------------------------------------------------------------------
-- Templates. Each starts turned off; one that sends anywhere can only be turned on once its recipient or tab is
-- chosen on this character. Categories come from an example item as this client files it (Items.lua), so the
-- category is the game's own, under the game's own name, and nothing is guessed from IDs of another version.
---------------------------------------------------------------------------
MI.TEMPLATES = {
    { key = "cloth", example = 2589, kind = "mail", destLabel = "Bank alt", keep = 20,
      name = "%s to bank alt", fallback = "Cloth to bank alt",
      about = "Mails cloth to the character you choose, keeping 20 of each kind in your bags." },
    { key = "herbs", example = 2447, kind = "bank", name = "%s to bank", fallback = "Herbs to bank",
      about = "Deposits herbs in your bank." },
    { key = "ore", example = 2770, kind = "bank", name = "%s to bank", fallback = "Ore to bank",
      about = "Deposits what the game files with ore (it puts bars and stone in the same category) in your bank." },
    { key = "boe", kind = "mail", destLabel = "Friend", name = "Uncommon BoE equipment to a friend",
      equip = "equipment", bind = "boe", qualities = { [2] = true },
      about = "Mails uncommon (green) equipment that binds when equipped and isn't bound yet. Whether an item can be disenchanted isn't checked." },
    { key = "custom", kind = "bank", name = "Custom items",
      about = "Start empty and choose the items yourself." },
}

function MI.Template(key)
    for _, t in ipairs(MI.TEMPLATES) do if t.key == key then return t end end
end

-- A new rule, not yet saved, from a template: { rule, destLabel }. The destination name the template suggests is
-- found among the existing ones or made when the rule is saved (MI.SaveTemplateRule).
function MI.FromTemplate(key)
    local t = MI.Template(key)
    if not t then return nil end
    local rule = { kind = t.kind, enabled = false, keep = t.keep or 0, stack = 0, equip = t.equip or "any", bind = t.bind or "any",
        qualities = {}, include = {}, exclude = {}, cats = {} }
    for q in pairs(t.qualities or {}) do rule.qualities[q] = true end
    local name = t.fallback or t.name
    if t.example and MI.CategoryOf then
        local cat, label = MI.CategoryOf(t.example)
        if cat then
            rule.cats[1] = cat
            if label then name = t.name:format(label) end
        end
    end
    rule.name = CleanName(name, MI.MAX_NAME)
    return rule, t.destLabel
end

-- A destination of that kind with that name, made if there is none. Returns its id or nil.
function MI.DestNamed(kind, label)
    for _, d in ipairs(MI.Dests()) do
        if d.kind == kind and d.label:lower() == label:lower() then return d.id end
    end
    return MI.AddDest(kind, label)
end
