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
-- So a rule copied to another character (or another profile, or a backup restored) never sends to a recipient that
-- character didn't choose: until one is set there, the rule says it needs one and stays off.
--
-- Rule: { id, name, enabled, kind = "mail" | "bank" | "guild" | "keep" | "never", dest = destId (mail, guild),
--         cats = { "7:5", "7", ... } (an item class, or class:subclass, as the game files it),
--         qualities = { [0..5] = true } (none: any), equip = "any" | "equipment" | "other",
--         bind = "any" | "boe" | "nobind", include = { [itemID] = true }, exclude = { [itemID] = true },
--         keep = 0..9999 (how many of EACH matching item stays in the bags; 0: none) }
-- Reading never writes; an entry that can't be read is left out of the next write. Nothing of a visit is saved.

local R = TwichUI
local MI = {}
R.MagicInventory = MI

MI.MAX_RULES = 40
MI.MAX_DESTS = 12
MI.MAX_IDS = 100        -- items in a rule's "Also include" or "Never include" list
MI.MAX_NEVER = 200
MI.MAX_KEEP = 9999
MI.MAX_NAME = 48
MI.MAX_CATS = 24

MI.KIND_ORDER = { "mail", "bank", "guild", "keep", "never" }
MI.KIND_LABEL = {
    mail = "Send by mail", bank = "Deposit in bank", guild = "Deposit in guild bank",
    keep = "Keep in bags", never = "Never transfer",
}
MI.TRANSFER = { mail = true, bank = true, guild = true }   -- kinds that move items (keep and never only protect)
MI.NEEDS_DEST = { mail = true, guild = true }

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

local function ValidCat(v)
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
        cats = {},
    }
    if MI.NEEDS_DEST[kind] and IdText(r.dest) then out.dest = r.dest end
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

-- Sets (or with text nil, clears) this character's recipient for a mail destination. allChars: keep it for every
-- character of this account instead (the player's explicit choice); clearing clears both. Returns true, or false
-- and a sentence.
function MI.SetRecipient(destId, text, allChars)
    local d = MI.Dest(destId)
    if not (d and d.kind == "mail") then return false, "That destination isn't there any more." end
    local name
    if text ~= nil then
        local why
        name, why = MI.NormalizeRecipient(text)
        if not name then return false, why end
    end
    local mine = CharDests(name ~= nil)
    local shared = Sub(AccountStore(name ~= nil and allChars), "shared", name ~= nil and allChars)
    if name == nil then
        if mine then mine[destId] = nil end
        if shared then shared[destId] = nil end
    elseif allChars then
        shared[destId] = { recipient = name }
        if mine then mine[destId] = nil end
    else
        if not mine then return false, "Your settings aren't available right now." end
        mine[destId] = { recipient = name }
    end
    MI.Changed()
    return true, name
end

-- Sets this character's guild bank tab for a guild destination: what the guild bank shows now, chosen by the player
-- with the guild bank open. tab: the tab's number; guild and tabName as the game names them.
function MI.SetGuildTab(destId, guild, tab, tabName)
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
    mine[destId] = { guild = guild, tab = tab, tabName = CleanName(tabName, 64) }
    MI.Changed()
    return true
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
    if not MI.NEEDS_DEST[rule.kind] then return nil end
    local d = rule.dest and MI.Dest(rule.dest)
    if not d or d.kind ~= rule.kind then
        return "no-destination", rule.kind == "mail" and "Choose who to send to." or "Choose a guild bank tab."
    end
    local where = MI.Resolve(d.id)
    if not where then
        if rule.kind == "mail" then return "no-recipient", ("Choose the recipient for \"%s\" on this character."):format(d.label) end
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
    local rule = { kind = t.kind, enabled = false, keep = t.keep or 0, equip = t.equip or "any", bind = t.bind or "any",
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
