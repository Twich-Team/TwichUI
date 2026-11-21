-- TwichUI Workshop: the queue of the current character
-- A short list of recipes the player chose to make, with enough saved to be understood after a reload: which recipe and
-- profession, its name and icon, what it makes, the materials one craft needs, how many crafts are wanted and when the
-- information was last seen in the player's own profession window. It is not a recipe database: only queued recipes are kept.
--
--   TwichUIDB.workshop = { v = 1, chars = { ["Name - Realm"] = { guid = "Player-...", queue = { entry, ... } } } }   account-wide, never in a profile,
--       a share or a backup (Restore.OWN_LEFT_OUT, TwichConfig.LOCAL): it names a character's recipes.
--   entry = { id (recipe), name, crafts, prof, profName, icon, outItem, outMin, outMax, mats = { { item, qty }, ... }, seen (time) }
--       outItem (the item one craft makes) is absent when not known; it lets the shopping list count what a queued craft will make.
--       mats is absent when the materials aren't known (not read, or not supported): the entry stays, says so, and counts for nothing.
--
-- Reading never writes. The queue is read into memory once, every entry checked; an entry that can't be read is left out of the
-- next write (it could not be shown anyway). A queue written by a newer TwichUI (v higher than this one understands) is never
-- changed: every change is refused with "held".

local R = TwichUI
local W = R.Workshop
local Int, Text, Plain = W.Int, W.Text, W.Plain
local Q = {}
W.Queue = Q

Q.Now = function() return time() end

local characterName, characterKey, characterGUID

local function PlayerGUID(value)
    value = Plain(value)
    if type(value) == "string" and #value <= 80 and value:match("^Player%-%d+%-%x+$") then return value end
end
local function CurrentGUID() return PlayerGUID(UnitGUID and UnitGUID("player")) end
local function NamedKey(key, name)
    local prefix = name .. " - "
    return type(key) == "string" and #key <= 160 and key:sub(1, #prefix) == prefix and #key > #prefix
end

-- "Name - Realm", or nil while the game can't say. Forever can return an
-- empty GetRealmName after login. Profiles keeps the canonical identity it
-- captured at login; UnitFullName's realm can differ from that saved realm.
-- Both session identities can be absent after /reload. A GUID saved in the
-- character slot restores the original key then; never guess by name alone.
function Q.CharKey()
    local name = Plain(UnitName and UnitName("player"))
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    local realm = Plain(GetRealmName and GetRealmName())
    local guid = CurrentGUID()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local chars = type(ws) == "table" and ws.chars
    local key
    if type(realm) == "string" and realm ~= "" then
        key = name .. " - " .. realm
    else
        local profiles = R.Profiles
        local canonical = Plain(profiles and profiles.Character and profiles.Character())
        if NamedKey(canonical, name) then
            key = canonical
        elseif characterName == name and (not guid or characterGUID == guid) then
            key = characterKey
        end
    end
    if not key and guid and type(chars) == "table" then
        for savedKey, slot in pairs(chars) do
            if NamedKey(savedKey, name) and type(slot) == "table" and PlayerGUID(slot.guid) == guid then
                if key then return nil end   -- duplicate bindings are ambiguous
                key = savedKey
            end
        end
    end
    local slot = key and type(chars) == "table" and chars[key]
    local bound = type(slot) == "table" and PlayerGUID(slot.guid)
    if bound and guid and bound ~= guid then return nil end
    if key then characterName, characterKey, characterGUID = name, key, guid end
    return key
end

---------------------------------------------------------------------------
-- Checking a record (the saved data, or a recipe the window read)
---------------------------------------------------------------------------
-- A list of { item, qty }: every item and count a whole number in range, repeats added together, at most W.MAX_MATS different
-- items. nil when it isn't usable (and so "not known"), never an empty list.
function Q.CleanMats(list)
    if type(list) ~= "table" then return nil end
    local out, at = {}, {}
    for i = 1, #list do
        local m = list[i]
        if type(m) ~= "table" then return nil end
        local item, qty = Int(m.item, 1, W.MAX_ID), Int(m.qty, 1, W.MAX_QTY)
        if not item or not qty then return nil end
        local k = at[item]
        if k then
            out[k].qty = out[k].qty + qty
            if out[k].qty > W.MAX_QTY then return nil end
        else
            if #out >= W.MAX_MATS then return nil end
            out[#out + 1] = { item = item, qty = qty }
            at[item] = #out
        end
    end
    if #out == 0 then return nil end
    return out
end

-- A checked copy of a saved entry, or nil when it can't be used (no recipe number or name)
function Q.Clean(rec)
    if type(rec) ~= "table" then return nil end
    local id, name = Int(rec.id, 1, W.MAX_ID), Text(rec.name, 80)
    if not id or not name then return nil end
    local e = {
        id = id, name = name,
        crafts = Int(rec.crafts, 1, W.MAX_CRAFTS) or 1,
        prof = Int(rec.prof, 1, W.MAX_ID), profName = Text(rec.profName, 40),
        icon = Int(rec.icon, 0, W.MAX_ID),
        outItem = Int(rec.outItem, 1, W.MAX_ID),
        mats = Q.CleanMats(rec.mats),
        seen = Int(rec.seen, 0, 4102444800),
    }
    local lo, hi = Int(rec.outMin, 1, W.MAX_QTY), Int(rec.outMax, 1, W.MAX_QTY)
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
    if lo and hi and hi >= lo then e.outMin, e.outMax = lo, hi end
    return e
end

local function Copy(e)
    local c = {}
    for k, v in pairs(e) do c[k] = v end
    if e.mats then
        c.mats = {}
        for i, m in ipairs(e.mats) do c.mats[i] = { item = m.item, qty = m.qty } end
    end
    return c
end

-- A queue entry from what the window read (Observe.lua's recipe record)
function Q.FromRecipe(rec, crafts)
    if type(rec) ~= "table" then return nil end
    local e = Q.Clean({
        id = rec.id, name = rec.name, crafts = crafts or 1, prof = rec.prof, profName = rec.profName, icon = rec.icon,
        outItem = rec.outItem, outMin = rec.outMin, outMax = rec.outMax, mats = rec.mats, seen = Q.Now(),
    })
    return e
end

---------------------------------------------------------------------------
-- Keeping it
---------------------------------------------------------------------------
local list      -- the checked queue in memory, nil until read

local function Root(create)
    if type(TwichUIDB) ~= "table" then return nil end
    if type(TwichUIDB.workshop) ~= "table" then
        if not create then return nil end
        TwichUIDB.workshop = {}
    end
    return TwichUIDB.workshop
end

local function Slot(create)
    if create and Q.Held() then return nil end
    local root = Root(create)
    local key = root and Q.CharKey()
    if not key then return nil end
    if type(root.chars) ~= "table" then
        if not create then return nil end
        root.chars = {}
    end
    if type(root.chars[key]) ~= "table" then
        if not create then return nil end
        root.chars[key] = {}
    end
    if create then
        local guid = CurrentGUID()
        if guid then root.chars[key].guid = guid end
    end
    return root.chars[key], root
end

Q.Slot = Slot   -- (Known.lua keeps its recipes in the same character slot)

-- True when a newer TwichUI wrote this: read it as far as it is understood, change nothing
function Q.Held()
    local root = Root(false)
    return root ~= nil and type(root.v) == "number" and root.v > W.SAVED_VERSION
end

-- One-time recovery for legacy slots when the client supplies no realm even
-- at login. The player explicitly selects the existing key; reads never bind
-- by name alone or rewrite saved data. Subsequent reloads use the saved GUID.
function Q.BindCharacter(key)
    if Q.Held() then return false, "held" end
    local name = Plain(UnitName and UnitName("player"))
    key = Plain(key)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT or not NamedKey(key, name) then return false, "bad" end
    local guid = CurrentGUID()
    if not guid then return false, "identity" end
    local root = Root(false)
    local chars = root and root.chars
    local slot = type(chars) == "table" and chars[key]
    if type(slot) ~= "table" then return false, "missing" end
    local bound = PlayerGUID(slot.guid)
    if bound and bound ~= guid then return false, "identity" end
    for otherKey, other in pairs(chars) do
        if otherKey ~= key and type(other) == "table" and PlayerGUID(other.guid) == guid then return false, "identity" end
    end
    root.v = W.SAVED_VERSION
    slot.guid = guid
    characterName, characterKey, characterGUID = name, key, guid
    Q.Unload()
    return true
end

function Q.Load()
    list = {}
    local slot = Slot(false)
    if slot and type(slot.queue) == "table" then
        local seen = {}
        for i = 1, #slot.queue do
            if #list >= W.MAX_QUEUE then break end
            local e = Q.Clean(slot.queue[i])
            if e and not seen[e.id] then
                seen[e.id] = true
                list[#list + 1] = e
            end
        end
    end
    return list
end

function Q.Entries()
    if not list then Q.Load() end
    return list
end

-- The in-memory copy is dropped (the next use reads it again); the saved queue is untouched
function Q.Unload() list = nil end

local function Save()
    if Q.Held() then return false, "held" end
    local slot, root = Slot(true)
    if not slot then return false, "unsaved" end
    root.v = W.SAVED_VERSION
    local out = {}
    for i, e in ipairs(list) do out[i] = Copy(e) end
    slot.queue = out
    return true
end

function Q.Find(id)
    for i, e in ipairs(Q.Entries()) do
        if e.id == id then return e, i end
    end
end

-- Appends a recipe with 1 craft. Returns the entry, or nil and why: "held", "bad", "exists", "full", "unsaved"
function Q.Add(rec, crafts)
    if Q.Held() then return nil, "held" end
    local e = Q.FromRecipe(rec, crafts)
    if not e then return nil, "bad" end
    local entries = Q.Entries()
    if Q.Find(e.id) then return nil, "exists" end
    if #entries >= W.MAX_QUEUE then return nil, "full" end
    entries[#entries + 1] = e
    local ok, why = Save()
    if not ok then
        entries[#entries] = nil
        return nil, why
    end
    return e
end

-- Adds several recipes (and/or more crafts of queued ones) as ONE change, all or nothing (P2: the player confirmed an optimized plan).
-- ops = { { rec = <recipe record>, crafts = n }, ... } in the order they are to stand in the queue; a recipe not queued yet is appended with
-- n crafts (it must have known materials and a fixed output: an unknown recipe is never queued by a plan), a queued one gets n more crafts.
-- Everything is checked before anything changes (held, a recipe that can't be queued, the same recipe twice, room for the new entries,
-- no entry above W.MAX_CRAFTS); the list is then changed in memory and saved once, and if that save fails the list is put back exactly as it
-- was (only this call's own changes are undone: nothing else can have changed in between).
-- Returns true and { added = new entries, raised = queued entries given more crafts }, or false and why: "held", "bad", "toomany", "full", "unsaved".
Q.MAX_BATCH = 40
function Q.AddBatch(ops)
    if Q.Held() then return false, "held" end
    if type(ops) ~= "table" or #ops == 0 or #ops > Q.MAX_BATCH then return false, "bad" end
    local entries = Q.Entries()
    local seen, plan, fresh = {}, {}, 0
    for _, op in ipairs(ops) do
        local n = type(op) == "table" and Int(op.crafts, 1, W.MAX_CRAFTS) or nil
        local rec = type(op) == "table" and op.rec or nil
        local id = type(rec) == "table" and Int(rec.id, 1, W.MAX_ID) or nil
        if not n or not id or seen[id] then return false, "bad" end
        seen[id] = true
        local have = Q.Find(id)
        if have then
            if have.crafts + n > W.MAX_CRAFTS then return false, "toomany" end
            plan[#plan + 1] = { have = have, n = n }
        else
            local e = Q.FromRecipe(rec, n)
            if not e or not e.mats or not e.outItem or not e.outMin or e.outMin ~= e.outMax then return false, "bad" end
            fresh = fresh + 1
            plan[#plan + 1] = { entry = e }
        end
    end
    if #entries + fresh > W.MAX_QUEUE then return false, "full" end
    local was, size = {}, #entries
    for _, p in ipairs(plan) do
        if p.have then
            was[#was + 1] = { p.have, p.have.crafts }
            p.have.crafts = p.have.crafts + p.n
        else
            entries[#entries + 1] = p.entry
        end
    end
    local ok, why = Save()
    if not ok then
        for i = #entries, size + 1, -1 do entries[i] = nil end
        for _, w in ipairs(was) do w[1].crafts = w[2] end
        return false, why
    end
    return true, { added = fresh, raised = #was }
end

-- Returns true, or false and why
function Q.SetCrafts(id, n)
    if Q.Held() then return false, "held" end
    local e = Q.Find(id)
    n = Int(n, 1, W.MAX_CRAFTS)
    if not e or not n then return false, "bad" end
    if e.crafts == n then return true end
    local was = e.crafts
    e.crafts = n
    local ok, why = Save()
    if not ok then e.crafts = was end
    return ok, why
end

function Q.Remove(id)
    if Q.Held() then return false, "held" end
    local e, i = Q.Find(id)
    if not e then return false, "bad" end
    table.remove(list, i)
    local ok, why = Save()
    if not ok then table.insert(list, i, e) end
    return ok, why
end

local function SameMats(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i].item ~= b[i].item or a[i].qty ~= b[i].qty then return false end
    end
    return true
end

-- Brings a queued recipe's saved information up to date from a recipe the player's own profession window just showed.
-- Never loses what is known: materials or an output that couldn't be read this time stay as they were. Nothing is written when
-- nothing differs. Returns true when it changed.
function Q.Refresh(rec)
    if type(rec) ~= "table" or Q.Held() then return false end
    local e = Q.Find(Int(rec.id, 1, W.MAX_ID))
    if not e then return false end
    local fresh = Q.FromRecipe(rec, e.crafts)
    if not fresh then return false end
    if not fresh.mats then fresh.mats = e.mats end
    if not fresh.outMin then fresh.outMin, fresh.outMax = e.outMin, e.outMax end
    if not fresh.prof then fresh.prof, fresh.profName = e.prof, e.profName end
    if not fresh.icon then fresh.icon = e.icon end
    if not fresh.outItem then fresh.outItem = e.outItem end
    if fresh.name == e.name and fresh.icon == e.icon and fresh.prof == e.prof and fresh.profName == e.profName
        and fresh.outItem == e.outItem and fresh.outMin == e.outMin and fresh.outMax == e.outMax and SameMats(fresh.mats, e.mats) then
        return false
    end
    e.name, e.icon, e.prof, e.profName, e.outItem, e.outMin, e.outMax, e.mats, e.seen =
        fresh.name, fresh.icon, fresh.prof, fresh.profName, fresh.outItem, fresh.outMin, fresh.outMax, fresh.mats, fresh.seen
    Save()
    return true
end

-- Entries whose materials aren't known: they stay queued and say "Open profession to update."
function Q.Unresolved(e) return e.mats == nil end

function Q.Count() return #Q.Entries() end
