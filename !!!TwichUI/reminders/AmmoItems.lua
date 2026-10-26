-- TwichUI: Reminders, what counts as ammunition
-- Two things, and nothing else: how an item ID is recognized as arrows or bullets, and the list of ammunition the
-- player registered themselves. Neither says anything about what is equipped or carried; that is read from the
-- game each time (State.lua's "ammo" source) and judged by Ammunition.lua's condition.
--
-- Recognizing an item (AI.Kind): the player's own registration first, then the client's classification. An item
-- of the Projectile class (Enum.ItemClass.Projectile, 6: Interface/AddOns/Blizzard_APIDocumentationGenerated/
-- ItemConstantsDocumentation.lua) is arrows when its subclass is 2 and bullets when it is 3. The Forever UI source
-- names the class but has no enumeration for the projectile subclasses; 2 and 3 are the item database's values
-- (the same numbers Enum.ItemWeaponSubclass uses for Bows and Guns, which is how the RXP reference addon reads
-- them too) and have not been seen in the game by this code. Any other projectile subclass is "other": it is never
-- called wrong ammunition and never counted as a supply. C_Item.GetItemInfoInstant answers from the client's own data
-- without waiting for the item to be cached, so recognizing an item never makes a request.
--
-- Registering ammunition (Reminders > Known ammunition in settings): an item ID and what it is, arrows or bullets,
-- kept in TwichUIDB.ui.ammoCustom.items as { { id, kind }, ... }. It exists for a server-specific item the client
-- does not classify (or classifies differently). Registering an item does not say it is equipped, carried,
-- compatible or consumed; it only says what that ID is when it turns up. Removing it forgets the registration and
-- nothing else. The player's registration wins over the client's classification, so a wrong one can be corrected.

local R = TwichUI
local AI = {}
R.AmmoItems = AI

AI.MAX = 40
AI.KINDS = { { "arrow", "Arrows" }, { "bullet", "Bullets" } }

local KIND = { arrow = true, bullet = true }
local SUBCLASS = { [2] = "arrow", [3] = "bullet" }   -- projectile subclass -> kind (see the top of this file)
local PROJECTILE = (Enum and Enum.ItemClass and Enum.ItemClass.Projectile) or 6
local CACHE_MAX = 256

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function ValidID(id) return Whole(id) and id >= 1 and id <= 2147483647 end

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function AI.ValidKind(kind) return KIND[kind] == true end

function AI.KindLabel(kind)
    for _, k in ipairs(AI.KINDS) do if k[1] == kind then return k[2] end end
    return tostring(kind)
end

---------------------------------------------------------------------------
-- What the client says an item is
---------------------------------------------------------------------------
local cache, cached = {}, 0   -- [id] = "arrow" | "bullet" | "other" | false (not a projectile); only answers the client gave

-- "arrow", "bullet", "other" (a projectile of a subclass not known here), false (it is not a projectile), or nil
-- (the client has no answer for this ID). Only an answer is kept.
function AI.Classify(id)
    if not ValidID(id) then return nil end
    local known = cache[id]
    if known ~= nil then return known end
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local itemID, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    itemID, classID, subClassID = Plain(itemID), Plain(classID), Plain(subClassID)
    if itemID == nil or classID == nil then return nil end
    local answer
    if classID == PROJECTILE then answer = SUBCLASS[subClassID] or "other" else answer = false end
    if cached >= CACHE_MAX then
        for k in pairs(cache) do cache[k] = nil end
        cached = 0
    end
    cache[id] = answer
    cached = cached + 1
    return answer
end

-- Whether the client knows an item by this ID: true, false, or nil when it cannot say (no API).
function AI.Known(id)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    return Plain((C_Item.GetItemInfoInstant(id))) ~= nil
end

---------------------------------------------------------------------------
-- The player's list
---------------------------------------------------------------------------
local index            -- [id] = kind, built when asked for after a change
local listeners = {}

local function Store(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.ammoCustom) ~= "table" then
        if not create then return nil end
        db.ui.ammoCustom = {}
    end
    return db.ui.ammoCustom
end

-- One entry, checked: { id, kind } or nil. Used for what is stored and for what arrives in a share.
function AI.CleanEntry(e)
    if type(e) ~= "table" or not ValidID(e.id) or not KIND[e.kind] then return nil end
    return { id = e.id, kind = e.kind }
end

-- The registered ammunition in the order it was added: a copy, with anything unusable left out.
function AI.List()
    local t = Store(false)
    local out, seen = {}, {}
    if t and type(t.items) == "table" then
        for _, e in ipairs(t.items) do
            local clean = AI.CleanEntry(e)
            if clean and not seen[clean.id] then
                seen[clean.id] = true
                out[#out + 1] = clean
            end
        end
    end
    return out
end

function AI.Count() return #AI.List() end

function AI.Entry(id)
    for _, e in ipairs(AI.List()) do if e.id == id then return e end end
end

-- fn() after the list changed (the settings tab redraws).
function AI.OnChange(fn) listeners[#listeners + 1] = fn end

local function Tell()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("ammunition list", err) end
    end
end

-- The list was written somewhere else (a profile change, an import): drop what was built from it and tell the page.
-- The reminders hear about profile changes through their own hook, and about an import through TwichConfig.lua.
function AI.Reindex()
    index = nil
    Tell()
end

local function Changed()
    index = nil
    Tell()
    R.Reminders.Invalidate()   -- the running reminders read their ammunition again
end

local function Write(list)
    local t = Store(true)
    if not t then return false end
    local out = {}
    for i, e in ipairs(list) do out[i] = { id = e.id, kind = e.kind } end
    t.items = out
    Changed()
    return true
end

-- An item ID from a number, an item link or typed digits; nil otherwise.
function AI.ParseItem(value)
    if type(value) == "string" then
        value = tonumber(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"))
    end
    if ValidID(value) then return value end
end

-- Adds an item. kind: "arrow" or "bullet"; left out, the client's own classification is used when it has one, else arrows.
-- Returns true, "added" | "exists", kind (an existing entry is left as it is), or false, a sentence.
function AI.Add(value, kind)
    local id = AI.ParseItem(value)
    if not id then return false, "That isn't an item ID. Type the number from the item's link, or paste the link or drop the item here." end
    if kind == nil then
        local known = AI.Classify(id)
        kind = KIND[known] and known or "arrow"
    end
    if not KIND[kind] then return false, "Choose arrows or bullets." end
    local list = AI.List()
    for _, e in ipairs(list) do
        if e.id == id then return true, "exists", e.kind end
    end
    if #list >= AI.MAX then return false, ("The list holds %d items; remove one first."):format(AI.MAX) end
    list[#list + 1] = { id = id, kind = kind }
    if not Write(list) then return false, "Your settings aren't available right now." end
    return true, "added", kind
end

-- Corrects what a registered item is. Returns true, or false and a sentence.
function AI.SetKind(id, kind)
    if not KIND[kind] then return false, "Choose arrows or bullets." end
    local list = AI.List()
    for _, e in ipairs(list) do
        if e.id == id then
            if e.kind == kind then return true end
            e.kind = kind
            return Write(list)
        end
    end
    return false, "That item isn't on your list any more."
end

-- Takes the registration off. Returns whether anything was removed. Nothing in your bags is touched.
function AI.Remove(id)
    local list = AI.List()
    for i, e in ipairs(list) do
        if e.id == id then
            table.remove(list, i)
            return Write(list)
        end
    end
    return false
end

local function Index()
    if index then return index end
    index = {}
    for _, e in ipairs(AI.List()) do index[e.id] = e.kind end
    return index
end

-- What an item is: kind ("arrow", "bullet", or "other" for a projectile of another subclass), and where that came
-- from ("custom" or "client"); nil for anything that is not ammunition or that the client cannot say.
function AI.Kind(id)
    local custom = Index()[id]
    if custom then return custom, "custom" end
    local known = AI.Classify(id)
    if known then return known, "client" end
    return nil
end

-- Counts only, for the troubleshooting report: no IDs.
function AI.Snapshot()
    return { registered = AI.Count(), cached = cached }
end

-- Before the reminders' own hook (Config.lua, loaded after this file), so they read the new profile's list.
R.Profiles.OnApply("layout", "ammo-items", AI.Reindex)
