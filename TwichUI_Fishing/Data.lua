-- TwichUI Fishing: names, seed data and small helpers
-- No frames and no game state here. This file creates R.Fishing (F); every other file of the addon adds to it.
--
-- Evidence (docs/fishing.md, "What the Forever client gives"): the item class and subclass of a fishing pole come from the
-- client's Enum (ItemClass.Weapon, ItemWeaponSubclass.Fishingpole = 20, Blizzard_APIDocumentationGenerated/
-- ItemConstantsDocumentation.lua). The spell ids, lure items and clam items below are NOT in the client's files: they are
-- seed data from the classic-era game and the repository's earlier Easy Fishing work. They only help recognise things;
-- nothing is decided from them alone (a lure must be in the bags, a clam must have come from fishing loot).

local R = TwichUI
local F = { ready = false }
R.Fishing = F
F.ADDON = "TwichUI_Fishing"
F.SCHEMA = 1               -- TwichUIFishingDB.schema this version writes (Store.lua)

local E = rawget(_G, "Enum")

---------------------------------------------------------------------------
-- Fishing itself
---------------------------------------------------------------------------
-- Fishing's spell ids, in the order a known one is looked for (classic ranks first). Seed data, unverified on Forever:
-- the cast uses whichever the spellbook says is known, and a channel is recognised by id or by Fishing's localized name.
F.FISHING_ORDER = { 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474, 131490, 131476, 158743, 377895, 1224771 }
F.FISHING_SPELL = {}
for _, id in ipairs(F.FISHING_ORDER) do F.FISHING_SPELL[id] = true end

F.WEAPON_CLASS = (E and E.ItemClass and E.ItemClass.Weapon) or 2
F.POLE_SUBCLASS = (E and E.ItemWeaponSubclass and E.ItemWeaponSubclass.Fishingpole) or 20
F.MAINHAND = rawget(_G, "INVSLOT_MAINHAND") or 16
F.OFFHAND = rawget(_G, "INVSLOT_OFFHAND") or 17
F.RANGED = rawget(_G, "INVSLOT_RANGED") or 18
F.FIRST_SLOT = rawget(_G, "INVSLOT_FIRST_EQUIPPED") or 1
F.LAST_SLOT = rawget(_G, "INVSLOT_LAST_EQUIPPED") or 19
F.WEAPON_SLOTS = { F.MAINHAND, F.OFFHAND, F.RANGED }
F.BAGS = { 0, 1, 2, 3, 4 }  -- the backpack and the four bag slots (Enum.BagIndex 0..4)

---------------------------------------------------------------------------
-- Lures (seed data: classic-era items; bonus is the fishing skill they add, minutes how long they last)
---------------------------------------------------------------------------
F.LURES = {
    [6529] = { bonus = 25, minutes = 10 },    -- Shiny Bauble
    [6530] = { bonus = 50, minutes = 10 },    -- Nightcrawlers
    [6532] = { bonus = 75, minutes = 10 },    -- Bright Baubles
    [7307] = { bonus = 75, minutes = 10 },    -- Flesh Eating Worm
    [6811] = { bonus = 50, minutes = 10 },    -- Aquadynamic Fish Lens
    [6533] = { bonus = 100, minutes = 5 },    -- Aquadynamic Fish Attractor
    [34861] = { bonus = 100, minutes = 10 },  -- Sharpened Fish Hook
    [46006] = { bonus = 100, minutes = 60 },  -- Glow Worm
}

---------------------------------------------------------------------------
-- Containers known to come from fishing (seed data). A container is queued only when it came from fishing loot; this list
-- only lets one be recognised before the bags have been read. Any other item from fishing loot that the bags call
-- openable (C_Container.GetContainerItemInfo(...).hasLoot) is learned as a fishing container the first time.
---------------------------------------------------------------------------
F.CONTAINERS = {
    [5523] = "clam",   -- Small Barnacled Clam
    [5524] = "clam",   -- Thick-shelled Clam
    [7973] = "clam",   -- Big-mouth Clam
    [15874] = "clam",  -- Soft-shelled Clam
}

---------------------------------------------------------------------------
-- Limits (docs/fishing.md, "Retention")
---------------------------------------------------------------------------
F.LIMITS = {
    sessions = 100,     -- completed session summaries kept per character (config may set 10..500)
    queue = 200,        -- container lots waiting to be opened, per character
    recent = 20,        -- recent catches kept on the session in progress (dropped when it ends)
    notes = 20,         -- recent errors and refusals kept for diagnostics (runtime only, never saved)
    learned = 200,      -- learned lure enchants and container items, per kind
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
-- A value the game may hand over as a secret (restricted contexts) is never compared or stored: it reads as nil.
function F.Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

function F.Num(v)
    v = F.Readable(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

function F.Count(v)
    v = F.Num(v)
    if not v or v < 0 or v ~= math.floor(v) then return nil end
    return v
end

function F.ItemID(link)
    link = F.Readable(link)
    if type(link) == "number" then return F.Count(link) end
    if type(link) ~= "string" then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- Wall-clock seconds (what is saved) and the session clock (GetTime, for short waits within a play session).
function F.Now() return time() end
function F.Clock() return GetTime and GetTime() or 0 end

function F.InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

function F.CharKey()
    local name = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    return tostring(name) .. " - " .. tostring(realm)
end

function F.Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = F.Copy(v) end
    return out
end

---------------------------------------------------------------------------
-- Notifications for later stages and diagnostics: F.Subscribe(event, fn) -> fn(event, ...). Listeners must not change what
-- they are given. A failing listener is reported and never stops the others. Events (docs/fishing.md, "Public interface"):
-- STATE, SESSION_START, SESSION_END, CAST, CAST_FAILED, CATCH, ITEM, CONTAINER, LURE, GEAR, QUEUE, NOTICE.
---------------------------------------------------------------------------
local subscribers = {}

function F.Subscribe(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    local list = subscribers[event]
    if not list then list = {}; subscribers[event] = list end
    for _, f in ipairs(list) do if f == fn then return true end end
    list[#list + 1] = fn
    return true
end

function F.Unsubscribe(event, fn)
    local list = subscribers[event]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

function F.Emit(event, ...)
    local list = subscribers[event]
    if not list then return end
    local copy = { unpack(list) }
    for _, fn in ipairs(copy) do
        local ok, err = pcall(fn, event, ...)
        if not ok then R.Fault("fishing listener " .. event, err) end
    end
end

function F.SubscriberCount()
    local n = 0
    for _, list in pairs(subscribers) do n = n + #list end
    return n
end

---------------------------------------------------------------------------
-- Recent errors and refusals (runtime only): F.Note(code, detail). Codes are a short fixed vocabulary; detail is plain
-- text written by this addon (never chat, names or item links). Counted per code for diagnostics.
---------------------------------------------------------------------------
F.notes, F.noteCounts = {}, {}

function F.Note(code, detail)
    if type(code) ~= "string" then return end
    F.noteCounts[code] = (F.noteCounts[code] or 0) + 1
    local list = F.notes
    list[#list + 1] = { at = F.Now(), code = code, detail = type(detail) == "string" and detail:sub(1, 120) or nil }
    while #list > F.LIMITS.notes do table.remove(list, 1) end
    if R.Life and R.Life.Note then R.Life.Note("fishing-" .. code) end
end

-- A short line where the game shows its own messages (never chat), said once per half second at most.
local said, saidAt = nil, -1
function F.Say(text)
    if type(text) ~= "string" then return end
    local now = F.Clock()
    if text == said and now - saidAt < 0.5 then return end
    said, saidAt = text, now
    if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
    F.Emit("NOTICE", text)
end
