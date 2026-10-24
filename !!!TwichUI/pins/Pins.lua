-- TwichUI: Party pins, the data
-- Named map pins of two kinds:
--   local  pins only you see, kept between sessions (TwichUIDB.pins.list, account-wide like the rest of
--          TwichUI's own data). Stable ids ("L12") that never change with a rename or a new color.
--   party  pins shared with your party while you are in it. Each belongs to the player who made it: its
--          key is that player's name (as the game reported who sent it, never a field inside a message)
--          and an id they chose, so nobody can name, change or remove anyone else's pin. They last for
--          the current party only; pins/Sync.lua starts and ends that session and carries the messages.
-- What you do on your own map stays on your map: "remove from my map" (dismiss) is a local record that
-- later updates and resyncs respect, and "keep as a local copy" makes an independent local pin that a
-- party-wide removal of the original never touches.
-- Keep: a pin of yours (local, or one of your own party pins) can be "kept", a personal protection that is
-- never sent and never changed by a message. A kept pin can't be deleted, cleared or moved until you turn
-- Keep off in the editor; renaming, recoloring and hiding it stay possible. It is enforced here, in the
-- functions that delete or move a pin, not by the windows. A kept party pin of yours lasts as long as the
-- party session does (it is carried over a /reload with the rest of the session, like the pin itself).
-- Share: a local pin can be published to the party as a snapshot. That makes (or refreshes) one party pin
-- of yours, linked to the saved pin by `source` (the local id, session-only, never sent). The saved pin
-- is not changed, moved or protected differently, and a message can never reach it; editing it sends
-- nothing; deleting it sends nothing and just drops the link. While a saved pin has its group copy, the
-- copy is not listed or drawn for you as a second pin: the saved pin stands for both.
-- Everything a pin carries is checked here, the same way for what you type and what arrives: names are
-- plain text (escape sequences, links, textures and control characters are taken out), coordinates are
-- whole steps of 1/10000 of the map from 0 to 10000, the map must be one the game knows, and the color
-- one of COLORS. Nothing here draws, sends or registers an event.

local R = TwichUI
local PN = {}
R.Pins = PN

PN.PROTOCOL = 1
PN.COORD = 10000               -- coordinates are kept and sent as 0..COORD
PN.NAME_MAX = 48               -- bytes of a pin's name (cut on a character boundary)
PN.MAX_LOCAL = 200
PN.MAX_PER_OWNER = 20          -- party pins one player can have at a time
PN.MAX_SHARED = 60             -- party pins in the session altogether
PN.MAX_DISMISSED = 100         -- "removed from my map" records kept for the session
PN.MAX_DELETED = 200           -- removal records kept for the session, so a late message can't bring a pin back
local MAX_MAP_ID = 2 ^ 31
local MAX_REV = 1000000

-- Pin colors, by a stable id that is what's saved and sent. Warm and muted, readable on the map's parchment.
PN.COLORS = {
    { "gold", "Gold", { 0.86, 0.69, 0.30 } },
    { "ember", "Ember", { 0.84, 0.43, 0.30 } },
    { "moss", "Moss", { 0.56, 0.71, 0.36 } },
    { "river", "River", { 0.44, 0.66, 0.82 } },
    { "violet", "Violet", { 0.64, 0.52, 0.82 } },
    { "rose", "Rose", { 0.86, 0.54, 0.64 } },
    { "parchment", "Parchment", { 0.93, 0.87, 0.71 } },
    { "slate", "Slate", { 0.60, 0.62, 0.64 } },
}
PN.DEFAULT_COLOR = "gold"
local COLOR_RGB, COLOR_LABEL = {}, {}
for _, c in ipairs(PN.COLORS) do COLOR_RGB[c[1]], COLOR_LABEL[c[1]] = c[3], c[2] end

function PN.ValidColor(id) return type(id) == "string" and COLOR_RGB[id] ~= nil end
function PN.ColorRGB(id) return COLOR_RGB[id] or COLOR_RGB[PN.DEFAULT_COLOR] end
function PN.ColorLabel(id) return COLOR_LABEL[id] or COLOR_LABEL[PN.DEFAULT_COLOR] end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
-- Plain text, at most NAME_MAX bytes (or max), or nil when nothing is left.
function PN.CleanName(text, max)
    max = max or PN.NAME_MAX
    if type(text) ~= "string" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|", "")
    text = text:gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #text > max then
        local cut = max
        -- never end inside a character: step back over continuation bytes (10xxxxxx)
        while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do cut = cut - 1 end
        text = text:sub(1, cut):match("^(.-)%s*$")
    end
    return text ~= "" and text or nil
end

local function IsInteger(n, low, high)
    return type(n) == "number" and n == n and n % 1 == 0 and n >= low and n <= high
end

-- A position on the map (0..1) as whole coordinate steps, or nil.
function PN.Quantize(v)
    if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return nil end
    return math.floor(v * PN.COORD + 0.5)
end

function PN.ValidCoord(n) return IsInteger(n, 0, PN.COORD) end

-- A map the game knows. The look-up is guarded: an id the client has no data for is not a map.
function PN.ValidMap(map)
    if not IsInteger(map, 1, MAX_MAP_ID) then return false end
    if not (C_Map and C_Map.GetMapInfo) then return false end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    return ok and type(info) == "table"
end

function PN.MapName(map)
    local ok, info = pcall(function() return C_Map.GetMapInfo(map) end)
    return ok and type(info) == "table" and type(info.name) == "string" and info.name or ("Map " .. tostring(map))
end

-- "Elwynn Forest (45.2, 61.3)"
function PN.Describe(pin)
    return ("%s (%.1f, %.1f)"):format(PN.MapName(pin.map), pin.x / PN.COORD * 100, pin.y / PN.COORD * 100)
end

---------------------------------------------------------------------------
-- What changed, for the map, the window and the data bar. Listeners must not change pins.
---------------------------------------------------------------------------
local listeners = {}
local holding, held = 0, false   -- PN.Batch: notifications wait until the outermost batch ends
function PN.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    if holding > 0 then held = true return end
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("party pins", err) end
    end
end
PN.Changed = Changed

-- Runs fn with the map, window and data bar told once afterwards instead of after every pin it changes
-- (a pasted list of waypoints). A failure in fn still ends the hold, then is raised again.
function PN.Batch(fn)
    holding = holding + 1
    local ok, err = pcall(fn)
    holding = holding - 1
    if holding == 0 and held then
        held = false
        Changed()
    end
    if not ok then error(err, 0) end
end

-- Reason codes for /tui diagnostics: a fixed vocabulary, never names, places or text.
PN.drops = {}
function PN.Drop(code)
    PN.drops[code] = (PN.drops[code] or 0) + 1
    return false, code
end

---------------------------------------------------------------------------
-- Local pins (saved)
---------------------------------------------------------------------------
-- create: make the saved table if there is none (only when a pin is added); reading never does.
local function Store(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local db = TwichUIDB.pins
    if type(db) ~= "table" then
        if not create then return nil end
        db = {}
        TwichUIDB.pins = db
    end
    if type(db.list) ~= "table" then db.list = {} end
    if not IsInteger(db.nextId, 1, 2 ^ 53) then
        -- one past the highest id kept, so an id is never given out twice
        local high = 0
        for _, p in ipairs(db.list) do
            local n = type(p) == "table" and type(p.id) == "string" and tonumber(p.id:match("^L(%d+)$"))
            if n and n > high then high = n end
        end
        db.nextId = high + 1
    end
    return db
end

local function ValidLocal(p)
    return type(p) == "table" and type(p.id) == "string" and PN.ValidCoord(p.x) and PN.ValidCoord(p.y)
        and IsInteger(p.map, 1, MAX_MAP_ID) and PN.CleanName(p.name) ~= nil
end

-- The local pins that can be used, in the order they were made. A saved entry that can't be read is
-- skipped, never erased.
function PN.LocalPins()
    local db = Store()
    local out = {}
    if not db then return out end
    for _, p in ipairs(db.list) do
        if ValidLocal(p) then out[#out + 1] = p end
    end
    return out
end

function PN.LocalCount() return #PN.LocalPins() end

-- Guide pins: a saved pin a guide made carries `guide`, a tag of its own ("cozybag:litter:1": the guide, the step and
-- the place), so the guide can find its pin again instead of making a second one, and clean up only its own. It is
-- an ordinary local pin in every other way: listed, drawn, edited, kept, limited and deleted like any other, and
-- the tag is never sent (a group copy and a copy for someone else are made from the visible fields only).
PN.GUIDE_TAG_MAX = 64
PN.guideNames = {}   -- guide id -> the name its pins' tooltips give ("Cozy Sleeping Bag guide"); a guide sets its own
function PN.ValidGuideTag(tag)
    if type(tag) ~= "string" or #tag > PN.GUIDE_TAG_MAX or not tag:match("^[%w_:%-]+$") then return nil end
    return tag
end

-- The saved pin that carries exactly this tag, or nil.
function PN.FindGuide(tag)
    if not PN.ValidGuideTag(tag) then return nil end
    for _, p in ipairs(PN.LocalPins()) do
        if p.guide == tag then return p end
    end
end

-- Every usable saved pin whose tag starts with prefix ("cozybag:"), in the order they were made.
function PN.GuidePins(prefix)
    local out = {}
    if type(prefix) ~= "string" or prefix == "" then return out end
    for _, p in ipairs(PN.LocalPins()) do
        if type(p.guide) == "string" and p.guide:sub(1, #prefix) == prefix then out[#out + 1] = p end
    end
    return out
end

function PN.FindLocal(id)
    local db = Store()
    if not db then return nil end
    for i, p in ipairs(db.list) do
        if type(p) == "table" and p.id == id then return p, i end
    end
end

-- Whether the pin is kept (protected). Only an explicit true counts, so a missing or odd saved value is
-- an ordinary pin.
function PN.IsKept(pin) return type(pin) == "table" and pin.kept == true end

-- fields: { map, x, y (0..COORD), name, color, copiedFrom, kept, guide }. Returns the pin, or nil and a reason.
function PN.AddLocal(fields)
    local db = Store(true)
    if not db then return nil, "not-ready" end
    if PN.LocalCount() >= PN.MAX_LOCAL then return nil, "local-limit" end
    if not PN.ValidMap(fields.map) then return nil, "unknown-map" end
    if not (PN.ValidCoord(fields.x) and PN.ValidCoord(fields.y)) then return nil, "bad-coordinates" end
    local name = PN.CleanName(fields.name) or PN.DefaultName()
    while PN.FindLocal("L" .. db.nextId) do db.nextId = db.nextId + 1 end   -- never the id of a kept entry
    local pin = {
        id = "L" .. db.nextId, map = fields.map, x = fields.x, y = fields.y, name = name,
        color = PN.ValidColor(fields.color) and fields.color or PN.DEFAULT_COLOR,
        created = time(), copiedFrom = PN.CleanName(fields.copiedFrom),
        kept = fields.kept == true or nil, guide = PN.ValidGuideTag(fields.guide),
    }
    db.nextId = db.nextId + 1
    db.list[#db.list + 1] = pin
    Changed()
    return pin
end

-- Rename, recolor, keep or unkeep; the id stays. fields: { name, color, kept, and optionally map, x, y }.
-- A kept pin's place can't change: map, x and y are refused with "kept" unless this same call turns Keep off
-- (the editor saves an unlock and a move together). Nothing is changed unless everything passes.
-- Returns true, or false and a reason.
function PN.UpdateLocal(id, fields)
    local pin = PN.FindLocal(id)
    if not pin then return false, "gone" end
    local name = pin.name
    if fields.name ~= nil then name = PN.CleanName(fields.name) end
    if not name then return false, "empty-name" end
    if fields.color ~= nil and not PN.ValidColor(fields.color) then return false, "bad-color" end
    local kept = PN.IsKept(pin)
    if fields.kept ~= nil then kept = fields.kept == true end
    local moving = fields.map ~= nil or fields.x ~= nil or fields.y ~= nil
    local map, x, y = pin.map, pin.x, pin.y
    if moving then
        if PN.IsKept(pin) and kept then return false, "kept" end
        if fields.map ~= nil then map = fields.map end
        if fields.x ~= nil then x = fields.x end
        if fields.y ~= nil then y = fields.y end
        if not PN.ValidMap(map) then return false, "unknown-map" end
        if not (PN.ValidCoord(x) and PN.ValidCoord(y)) then return false, "bad-coordinates" end
    end
    pin.name = name
    if fields.color ~= nil then pin.color = fields.color end
    pin.kept = kept or nil
    pin.map, pin.x, pin.y = map, x, y
    Changed()
    return true
end

-- Deleting one pin. A kept pin is refused with "kept"; the way to delete it is to turn Keep off first.
function PN.RemoveLocal(id)
    local pin, i = PN.FindLocal(id)
    if not pin then return false, "gone" end
    if PN.IsKept(pin) then return false, "kept" end
    table.remove(TwichUIDB.pins.list, i)
    if PN.selected == "local:" .. id then PN.selected = nil end
    PN.DropLinks()   -- a group copy it had stays with the party; nothing is sent
    Changed()
    return true
end

-- What a clear may delete: a pin that can be read and isn't kept. An entry that can't be read is left
-- alone (it may be a kept pin from a newer version), as everywhere else.
local function Clearable(p) return ValidLocal(p) and not PN.IsKept(p) end

-- The local pins a clear would delete (as a set of ids) and how many kept ones it would leave, as saved now.
function PN.LocalClearScope()
    local db = Store()
    local ids, n, kept = {}, 0, 0
    if not db then return ids, n, kept end
    for _, p in ipairs(db.list) do
        if Clearable(p) then
            ids[p.id] = true
            n = n + 1
        elseif PN.IsKept(p) and ValidLocal(p) then
            kept = kept + 1
        end
    end
    return ids, n, kept
end

-- Deletes the local pins that aren't kept, after the player confirmed; each pin is judged now, not when the
-- question was asked. only: a set of ids (from PN.LocalClearScope), so that a pin made since the question is
-- never swept up; nil means every unkept pin. Party pins are not touched and nothing is sent. Returns how
-- many were deleted and how many kept pins were left.
function PN.ClearLocal(only)
    local db = Store()
    if not db then return 0, 0 end
    local left, removed, kept = {}, 0, 0
    for _, p in ipairs(db.list) do
        if Clearable(p) and (only == nil or only[p.id]) then
            removed = removed + 1
        else
            left[#left + 1] = p
            if PN.IsKept(p) and ValidLocal(p) then kept = kept + 1 end
        end
    end
    if removed > 0 then
        db.list = left
        if type(PN.selected) == "string" and PN.selected:find("^local:") and not PN.FindLocal(PN.selected:sub(7)) then
            PN.selected = nil
        end
        PN.DropLinks()
        Changed()
    end
    return removed, kept
end

function PN.DefaultName()
    return ("Pin %d"):format(PN.LocalCount() + PN.OwnCount() + 1)
end

---------------------------------------------------------------------------
-- Party pins (this party session only)
---------------------------------------------------------------------------
local session        -- see NewSession; nil while there is no party session

local function NewSession(epoch)
    return {
        epoch = epoch or PN.NewEpoch(), seq = 0,
        pins = {},                 -- [key] = pin
        count = 0, perOwner = {},  -- totals, kept in step with pins
        dismissed = {}, dismissOrder = {},
        deleted = {}, deletedOrder = {},   -- [key] = the revision it was removed at
    }
end

-- A short random word that, with a running number, makes this player's ids for one session.
function PN.NewEpoch()
    local chars = "abcdefghijkmnpqrstuvwxyz23456789"
    local out = {}
    for i = 1, 6 do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

function PN.Key(owner, id) return owner .. "\1" .. id end

local function SelfName()
    local SH = R.Share
    return SH and SH.FullName(SH.SelfName()) or nil
end
PN.SelfName = SelfName

local function SameName(a, b)
    local SH = R.Share
    if SH then return SH.SameName(a, b) end
    return a == b
end

function PN.SessionOpen() return session ~= nil end

-- Started by pins/Sync.lua when you are in a party with the feature on; epoch is given back after a reload.
function PN.StartSession(epoch)
    if session then return end
    session = NewSession(epoch)
end

-- Leaving the party, turning the feature off: every party pin, dismissal and removal record goes.
-- Local pins (and local copies) stay.
function PN.EndSession()
    if not session then return end
    session = nil
    if type(PN.selected) == "string" and PN.selected:find("^party:") then PN.selected = nil end
    Changed()
end

function PN.Shared(key) return session and session.pins[key] end

-- Every party pin in the session (dismissed ones too), in no particular order.
function PN.AllSharedPins()
    local out = {}
    if not session then return out end
    for _, p in pairs(session.pins) do out[#out + 1] = p end
    return out
end

-- The group copies of saved pins that can still be read: { [localId] = party pin }. Those are yours alone
-- and stand behind the saved pin, so the lists, the maps and the counts leave them out.
local function GroupCopies()
    local out = {}
    if not session then return out end
    local ids
    for _, p in pairs(session.pins) do
        if p.mine and p.source then
            if not ids then
                ids = {}
                local db = Store()
                if db then
                    for _, l in ipairs(db.list) do
                        if ValidLocal(l) then ids[l.id] = true end
                    end
                end
            end
            if ids[p.source] then out[p.source] = p end
        end
    end
    return out
end

-- The same pins as a set keyed by the pin itself, for skipping them in a loop over the session.
local function CopySet()
    local set = {}
    for _, p in pairs(GroupCopies()) do set[p] = true end
    return set
end

-- The party pins as they are listed: everything but the group copies of your saved pins.
function PN.SharedPins()
    local out = {}
    if not session then return out end
    local hidden = CopySet()
    for _, p in pairs(session.pins) do
        if not hidden[p] then out[#out + 1] = p end
    end
    return out
end

-- The group copy of a saved pin, or nil when it isn't shared in this party.
function PN.GroupCopy(localId)
    return GroupCopies()[localId]
end

function PN.SharedCount() return session and session.count or 0 end

function PN.OwnCount()
    local me = SelfName()
    return (session and me and session.perOwner[me]) or 0
end

function PN.IsDismissed(key) return session ~= nil and session.dismissed[key] == true end

function PN.DismissedCount()
    if not session then return 0 end
    local n = 0
    for key in pairs(session.dismissed) do if session.pins[key] then n = n + 1 end end
    return n
end


local function Put(pin)
    local old = session.pins[pin.key]
    if not old then
        session.count = session.count + 1
        session.perOwner[pin.owner] = (session.perOwner[pin.owner] or 0) + 1
    end
    session.pins[pin.key] = pin
end

local function Take(key)
    local old = session.pins[key]
    if not old then return nil end
    session.pins[key] = nil
    session.count = session.count - 1
    local n = (session.perOwner[old.owner] or 1) - 1
    session.perOwner[old.owner] = n > 0 and n or nil
    if PN.selected == "party:" .. key then PN.selected = nil end
    return old
end

-- Bounded, oldest first out.
local function Remember(map, order, key, value, limit)
    if map[key] == nil then order[#order + 1] = key end
    map[key] = value
    while #order > limit do
        local oldest = table.remove(order, 1)
        map[oldest] = nil
    end
end

local function Forget(map, order, key)
    if map[key] == nil then return end
    map[key] = nil
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) break end
    end
end

local function Tombstone(key, rev)
    local prev = session.deleted[key]
    Remember(session.deleted, session.deletedOrder, key, math.max(rev or 0, prev or 0), PN.MAX_DELETED)
    Forget(session.dismissed, session.dismissOrder, key)
end

---------------------------------------------------------------------------
-- Your own party pins. These only change the collection; pins/Sync.lua sends.
---------------------------------------------------------------------------
-- Returns the pin, or nil and a reason.
function PN.CreateOwn(fields)
    if not session then return nil, "no-party" end
    local me = SelfName()
    if not me then return nil, "not-ready" end
    if PN.OwnCount() >= PN.MAX_PER_OWNER then return nil, "owner-limit" end
    if session.count >= PN.MAX_SHARED then return nil, "session-limit" end
    if not PN.ValidMap(fields.map) then return nil, "unknown-map" end
    if not (PN.ValidCoord(fields.x) and PN.ValidCoord(fields.y)) then return nil, "bad-coordinates" end
    session.seq = session.seq + 1
    local id = session.epoch .. ":" .. session.seq
    -- never an id in use or removed this session (a damaged saved session can hold a lower count): a new pin
    -- must not replace a kept one, nor be ignored by the party as one already removed
    while session.pins[PN.Key(me, id)] or session.deleted[PN.Key(me, id)] do
        session.seq = session.seq + 1
        id = session.epoch .. ":" .. session.seq
    end
    local pin = {
        key = PN.Key(me, id), owner = me, id = id, rev = 1, mine = true,
        map = fields.map, x = fields.x, y = fields.y,
        name = PN.CleanName(fields.name) or PN.DefaultName(),
        color = PN.ValidColor(fields.color) and fields.color or PN.DEFAULT_COLOR,
        at = time(), kept = fields.kept == true or nil,   -- yours alone: not in the wire form (pins/Sync.lua)
        source = fields.source,   -- only PN.PublishLocal sets it: the saved pin this is the group copy of
    }
    Put(pin)
    Changed()
    return pin
end

-- Rename, recolor, keep or unkeep one of your own. fields: { name, color, kept }. A new revision is made
-- only when a name or color is given (what the party sees); turning Keep on or off alone is yours, changes
-- no revision and is not sent. Returns the pin and whether the party's copy changed, or nil and a reason.
function PN.UpdateOwn(key, fields)
    local pin = session and session.pins[key]
    if not pin then return nil, "gone" end
    if not pin.mine then return nil, "not-owner" end
    local name = pin.name
    if fields.name ~= nil then name = PN.CleanName(fields.name) end
    if not name then return nil, "empty-name" end
    if fields.color ~= nil and not PN.ValidColor(fields.color) then return nil, "bad-color" end
    local shared = fields.name ~= nil or fields.color ~= nil
    if shared then
        pin.name = name
        if fields.color ~= nil then pin.color = fields.color end
        pin.rev = pin.rev + 1
    end
    if fields.kept ~= nil then pin.kept = fields.kept == true or nil end
    Changed()
    return pin, shared
end

-- Removes one of your own from the session and records it removed. Returns its last revision + 1 (what
-- the removal is sent with), or nil and a reason.
function PN.DeleteOwn(key)
    local pin = session and session.pins[key]
    if not pin then return nil, "gone" end
    if not pin.mine then return nil, "not-owner" end
    if PN.IsKept(pin) then return nil, "kept" end
    local rev = pin.rev + 1
    Take(key)
    Tombstone(key, rev)
    Changed()
    return rev, pin
end

-- Whether you have made a party pin this session (then you answer hellos, even with an empty list, so a
-- member who missed a removal hears of it).
function PN.HasPublished() return session ~= nil and session.seq > 0 end

-- Your own current pins, as sent in a full list.
function PN.OwnPins()
    local out = {}
    if not session then return out end
    local me = SelfName()
    for _, p in pairs(session.pins) do
        if p.mine and p.owner == me then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---------------------------------------------------------------------------
-- Sharing a saved pin. The saved pin is only read: its place, name and color are copied into one party pin
-- of yours, which is the one thing a later share of the same saved pin refreshes. Nothing here changes the
-- saved pin, and pins/Sync.lua does the sending.
---------------------------------------------------------------------------
-- Whether the group copy already shows what the saved pin has now.
function PN.GroupCopyCurrent(localId)
    local copy, src = PN.GroupCopy(localId), PN.FindLocal(localId)
    return copy ~= nil and src ~= nil and copy.map == src.map and copy.x == src.x and copy.y == src.y
        and copy.name == PN.CleanName(src.name) and copy.color == (PN.ValidColor(src.color) and src.color or PN.DEFAULT_COLOR)
end

-- Makes the group copy of a saved pin, or brings the one there is up to date (a new revision, the same id).
-- Returns the party pin and whether it is new, or nil and a reason code.
function PN.PublishLocal(localId)
    if not session then return nil, "no-party" end
    local src = PN.FindLocal(localId)
    if not (src and ValidLocal(src)) then return nil, "gone" end
    local fields = {
        map = src.map, x = src.x, y = src.y, name = src.name,
        color = PN.ValidColor(src.color) and src.color or PN.DEFAULT_COLOR,
    }
    local copy = PN.GroupCopy(localId)
    if not copy then
        fields.source = localId
        local pin, why = PN.CreateOwn(fields)
        if not pin then return nil, why end
        return pin, true
    end
    if not PN.ValidMap(fields.map) then return nil, "unknown-map" end
    copy.map, copy.x, copy.y = fields.map, fields.x, fields.y
    copy.name, copy.color = PN.CleanName(fields.name), fields.color
    copy.rev = math.min(copy.rev + 1, MAX_REV)
    Changed()
    return copy, false
end

-- A saved pin that is gone leaves its group copy as an ordinary party pin of yours: still shared, removable
-- for the party, no longer tied to anything. A saved pin that can't be read now keeps its link.
function PN.DropLinks()
    if not session then return end
    for _, p in pairs(session.pins) do
        if p.source and not PN.FindLocal(p.source) then p.source = nil end
    end
end

---------------------------------------------------------------------------
-- Messages from party members. owner: who the game says sent it (already checked to be in the party).
-- Each returns true, or false and a reason code; nothing is thrown.
---------------------------------------------------------------------------
local function ValidId(id)
    return type(id) == "string" and #id >= 3 and #id <= 20 and id:match("^%w+:%d+$") ~= nil
end
PN.ValidId = ValidId

-- A pin as it arrives: { id, r, m, x, y, n, c }. Returns a clean copy, or nil and a reason.
function PN.ReadPin(t)
    if type(t) ~= "table" then return nil, "malformed" end
    if not ValidId(t.id) then return nil, "bad-id" end
    if not IsInteger(t.r, 1, MAX_REV) then return nil, "bad-revision" end
    if not (PN.ValidCoord(t.x) and PN.ValidCoord(t.y)) then return nil, "bad-coordinates" end
    if not IsInteger(t.m, 1, MAX_MAP_ID) then return nil, "bad-map" end
    if not PN.ValidMap(t.m) then return nil, "unknown-map" end
    local name = PN.CleanName(t.n)
    if not name then return nil, "bad-name" end
    local color = t.c
    if not PN.ValidColor(color) then
        if type(color) ~= "string" or #color > 16 then return nil, "bad-color" end
        PN.Drop("color-unknown")   -- a color a newer TwichUI knows: drawn in the default
        color = PN.DEFAULT_COLOR
    end
    return { id = t.id, rev = t.r, map = t.m, x = t.x, y = t.y, name = name, color = color }
end

-- Pins from other players that were not here before, for the message being applied (nil between messages).
-- Updates, pins already held and your own are never in it.
local arrived
local receivedListeners = {}

-- fn(pins) is called once per message, after Changed, with the new pins in the order they came.
function PN.OnReceived(fn) receivedListeners[#receivedListeners + 1] = fn end

local function Received(pins)
    if #pins == 0 then return end
    for _, fn in ipairs(receivedListeners) do
        local ok, err = pcall(fn, pins)
        if not ok and R.Fault then R.Fault("party pins", err) end
    end
end

-- Adds or updates one pin of `owner`'s. No event: callers fire Changed once per message.
local function Accept(owner, data)
    local key = PN.Key(owner, data.id)
    if session.deleted[key] then return PN.Drop("deleted") end
    local cur = session.pins[key]
    if cur then
        if cur.mine then return PN.Drop("own-echo") end
        if data.rev <= cur.rev then return PN.Drop("stale") end
        cur.rev, cur.map, cur.x, cur.y, cur.name, cur.color = data.rev, data.map, data.x, data.y, data.name, data.color
        return true
    end
    if (session.perOwner[owner] or 0) >= PN.MAX_PER_OWNER then return PN.Drop("owner-limit") end
    if session.count >= PN.MAX_SHARED then return PN.Drop("session-limit") end
    local pin = { key = key, owner = owner, id = data.id, rev = data.rev, map = data.map, x = data.x, y = data.y,
        name = data.name, color = data.color, mine = false, at = time() }
    Put(pin)
    if arrived then arrived[#arrived + 1] = pin end
    return true
end

function PN.ApplyPut(owner, t)
    if not session then return PN.Drop("no-party") end
    if SameName(owner, SelfName()) then return PN.Drop("own-echo") end
    local data, why = PN.ReadPin(t)
    if not data then return PN.Drop(why) end
    arrived = {}
    local ok, code = Accept(owner, data)
    local new = arrived
    arrived = nil
    if ok then
        Changed()
        Received(new)
    end
    return ok, code
end

-- A removal by its owner. Kept as a record even if the pin was never seen here, so a late copy of it
-- can't appear afterwards.
function PN.ApplyDel(owner, id, rev)
    if not session then return PN.Drop("no-party") end
    if SameName(owner, SelfName()) then return PN.Drop("own-echo") end
    if not ValidId(id) or not IsInteger(rev, 1, MAX_REV) then return PN.Drop("malformed") end
    local key = PN.Key(owner, id)
    local cur = session.pins[key]
    if cur and rev <= cur.rev then return PN.Drop("stale") end
    Take(key)
    Tombstone(key, rev)
    Changed()
    return true
end

-- An owner's full list: what is listed is added or updated, and their pins that are not listed were
-- removed while the message was missed here.
function PN.ApplyAll(owner, list)
    if not session then return PN.Drop("no-party") end
    if SameName(owner, SelfName()) then return PN.Drop("own-echo") end
    if type(list) ~= "table" or #list > PN.MAX_PER_OWNER then return PN.Drop("malformed") end
    local listed = {}
    arrived = {}
    for i = 1, #list do
        local data = PN.ReadPin(list[i])
        if data then
            listed[PN.Key(owner, data.id)] = true
            Accept(owner, data)
        else
            PN.Drop("bad-entry")
        end
    end
    for key, p in pairs(session.pins) do
        if p.owner == owner and not listed[key] then
            Take(key)
            Tombstone(key, p.rev + 1)
        end
    end
    local new = arrived
    arrived = nil
    Changed()
    Received(new)
    return true
end

-- A player left the party: their pins go (never yours).
function PN.RemoveOwner(owner)
    if not session or SameName(owner, SelfName()) then return 0 end
    local n = 0
    for key, p in pairs(session.pins) do
        if p.owner == owner then
            Take(key)
            Forget(session.dismissed, session.dismissOrder, key)
            n = n + 1
        end
    end
    if n > 0 then Changed() end
    return n
end

-- The players with pins here, other than you.
function PN.Owners()
    local out = {}
    if not session then return out end
    local me = SelfName()
    for owner in pairs(session.perOwner) do
        if owner ~= me then out[#out + 1] = owner end
    end
    return out
end

---------------------------------------------------------------------------
-- Your own map: dismiss and restore (nothing is sent), and local copies
---------------------------------------------------------------------------
function PN.Dismiss(key)
    if not (session and session.pins[key]) then return false, "gone" end
    Remember(session.dismissed, session.dismissOrder, key, true, PN.MAX_DISMISSED)
    if PN.selected == "party:" .. key then PN.selected = nil end
    Changed()
    return true
end

function PN.Restore(key)
    if not (session and session.dismissed[key]) then return false, "gone" end
    Forget(session.dismissed, session.dismissOrder, key)
    Changed()
    return true
end

-- Hides every party pin on your map (yours too) except kept ones; nothing is sent and each can be restored.
function PN.DismissAll()
    if not session then return 0 end
    local n = 0
    local copies = CopySet()
    for key, p in pairs(session.pins) do
        if not session.dismissed[key] and not PN.IsKept(p) and not copies[p] then
            Remember(session.dismissed, session.dismissOrder, key, true, PN.MAX_DISMISSED)
            n = n + 1
        end
    end
    if n > 0 then Changed() end
    return n
end

-- What a local copy of a party pin starts with: the same place, name and color, who made it, and no link
-- to the original. Returns the fields (a snapshot: later changes to the party pin don't reach it), or nil
-- and a reason. The editor shows them for review and PN.AddLocal makes the pin when it is saved.
function PN.CopyFields(key)
    local pin = session and session.pins[key]
    if not pin then return nil, "gone" end
    local SH = R.Share
    local from = pin.mine and nil or (SH and SH.Short(pin.owner) or pin.owner)
    return { map = pin.map, x = pin.x, y = pin.y, name = pin.name, color = pin.color, copiedFrom = from }
end

-- A local pin made from a party pin at once, without the editor. kept: make it a kept pin.
function PN.KeepCopy(key, kept)
    local fields, why = PN.CopyFields(key)
    if not fields then return nil, why end
    fields.kept = kept == true
    return PN.AddLocal(fields)
end

---------------------------------------------------------------------------
-- Clearing: every pin that isn't kept. Local pins are deleted; party pins (yours and others') are taken
-- off your map, which sends nothing and deletes nothing for anyone, and can be undone under Removed.
-- This is the whole scope of the old "clear all", minus the kept pins.
---------------------------------------------------------------------------
-- What a clear would do right now, for the question that is asked first:
-- { localDelete, partyHide, kept, localIds, partyKeys } (kept: the kept pins in that scope, which stay;
-- localIds and partyKeys: sets naming exactly the pins counted, handed back to PN.ClearUnprotected).
function PN.ClearScope()
    local localIds, localDelete, kept = PN.LocalClearScope()
    local partyKeys, partyHide = {}, 0
    if session then
        local copies = CopySet()
        for key, p in pairs(session.pins) do
            if not session.dismissed[key] and not copies[p] then
                if PN.IsKept(p) then
                    kept = kept + 1
                else
                    partyKeys[key] = true
                    partyHide = partyHide + 1
                end
            end
        end
    end
    return { localDelete = localDelete, partyHide = partyHide, kept = kept, localIds = localIds, partyKeys = partyKeys }
end

-- Does it. scope: what PN.ClearScope returned when the question was asked; only pins it named are touched,
-- and each is judged again now, so one that has become kept since stays. Without a scope, every unkept pin.
-- Returns pins deleted, party pins taken off your map, kept pins left.
function PN.ClearUnprotected(scope)
    local removed, hidden, kept = 0, 0, 0
    PN.Batch(function()
        -- the group copies of saved pins are told apart before any saved pin goes: one whose source this
        -- clear deletes stays a party pin of yours, shared, and is not hidden by the same clear
        local copies = CopySet()
        removed, kept = PN.ClearLocal(scope and scope.localIds or nil)
        if not session then return end
        for key, p in pairs(session.pins) do
            if not session.dismissed[key] and not copies[p] then
                if PN.IsKept(p) then
                    kept = kept + 1
                elseif scope == nil or scope.partyKeys[key] then
                    Remember(session.dismissed, session.dismissOrder, key, true, PN.MAX_DISMISSED)
                    if PN.selected == "party:" .. key then PN.selected = nil end
                    hidden = hidden + 1
                end
            end
        end
        if hidden > 0 then Changed() end
    end)
    return removed, hidden, kept
end

---------------------------------------------------------------------------
-- What may be done with a pin, asked when a menu is drawn and again when the action runs.
-- entry: { kind = "local" | "party", pin = pin }. Returns true, or false and a sentence.
---------------------------------------------------------------------------
local REASONS = {
    ["no-party"] = "You are not in a party now.",
    paused = "Party pins are paused while you are in a raid.",
    blocked = "The game is holding addon messages here right now. Try again in a moment.",
    ["not-owner"] = "Only the player who made it can do that.",
    kept = "That pin is kept. Edit it and turn off Keep first.",
    gone = "That pin is no longer there.",
    off = "Party pins are turned off.",
    ["owner-limit"] = ("You already have %d party pins. Remove one first."):format(PN.MAX_PER_OWNER),
    ["session-limit"] = ("Your party already has %d party pins."):format(PN.MAX_SHARED),
    ["local-limit"] = ("You already have %d local pins. Remove some first."):format(PN.MAX_LOCAL),
    ["unknown-map"] = "That map can't hold a pin.",
    ["bad-coordinates"] = "That spot is off the map.",
    ["empty-name"] = "A pin needs a name.",
    ["bad-color"] = "That color isn't available.",
    ["no-waypoint"] = "The game doesn't allow a waypoint on that map.",
    ["not-ready"] = "Party pins aren't ready yet.",
    ["share-no-party"] = "Join a party to share this pin.",
    ["share-raid"] = "Pins can only be shared with a party, not a raid.",
    ["share-own"] = "It is already shared with your party. Edit it to change what they see.",
    ["share-theirs"] = "It is another player's pin. Save it to your pins first, then share your own copy.",
    ["not-shared"] = "This pin isn't shared with your party.",
}
function PN.Reason(code) return REASONS[code] or "That can't be done right now." end

-- pins/Sync.lua sets this: nil when party pins can be sent now, else a reason code.
PN.SendBlocked = function() return "no-party" end

local function Fresh(entry)
    if entry.kind == "local" then
        local p = PN.FindLocal(entry.pin.id)
        return p and ValidLocal(p) and p or nil
    end
    return session and session.pins[entry.pin.key] or nil
end
PN.Fresh = Fresh

function PN.Can(action, entry)
    if not R:Enabled("partyPins") then return false, REASONS.off end
    local pin = entry and Fresh(entry)
    if not pin then return false, REASONS.gone end
    if action == "show" then return true end
    if action == "share" or action == "unshare" then
        -- Sharing publishes a snapshot of a saved pin to the party; it needs a party the game will carry a
        -- message to, a place the game knows, and room under the limits. It never depends on Keep.
        if entry.kind ~= "local" then
            if action == "unshare" then return false, REASONS["not-shared"] end
            return false, pin.mine and REASONS["share-own"] or REASONS["share-theirs"]
        end
        local blocked = PN.SendBlocked()
        if action == "unshare" then
            if not PN.GroupCopy(pin.id) then return false, REASONS["not-shared"] end
            if blocked then return false, PN.Reason(blocked) end
            return true
        end
        if not PN.ValidMap(pin.map) then return false, REASONS["unknown-map"] end
        if blocked == "no-party" then return false, REASONS["share-no-party"] end
        if blocked == "paused" then return false, REASONS["share-raid"] end
        if blocked then return false, PN.Reason(blocked) end
        if not PN.GroupCopy(pin.id) then
            if PN.OwnCount() >= PN.MAX_PER_OWNER then return false, REASONS["owner-limit"] end
            if PN.SharedCount() >= PN.MAX_SHARED then return false, REASONS["session-limit"] end
        end
        return true
    end
    if action == "navigate" then
        if not (R.Nav and R.Nav.CanNavigate) then return false, "Navigation isn't available." end
        return R.Nav.CanNavigate(pin.map, pin.x / PN.COORD, pin.y / PN.COORD)
    end
    if action == "waypoint" then
        local ok, can = pcall(function() return C_Map.CanSetUserWaypointOnMap(pin.map) end)
        if ok and can then return true end
        return false, REASONS["no-waypoint"]
    end
    if entry.kind == "local" then
        if action == "edit" or action == "keep" then return true end
        if action == "delete" then
            if PN.IsKept(pin) then return false, REASONS.kept end
            return true
        end
        return false, REASONS.gone
    end
    local dismissed = PN.IsDismissed(pin.key)
    if action == "copy" then
        if PN.LocalCount() >= PN.MAX_LOCAL then return false, REASONS["local-limit"] end
        return true
    elseif action == "dismiss" then
        if dismissed then return false, "It is already off your map." end
        return true
    elseif action == "restore" then
        if not dismissed then return false, "It is already on your map." end
        return true
    elseif action == "keep" then
        -- Keep is yours alone and sends nothing, so it doesn't wait for the party channel (a raid, a block)
        if not pin.mine then return false, REASONS["not-owner"] end
        return true
    elseif action == "edit" or action == "removeParty" then
        if not pin.mine then return false, REASONS["not-owner"] end
        if action == "removeParty" and PN.IsKept(pin) then return false, REASONS.kept end
        local blocked = PN.SendBlocked()
        if blocked then return false, PN.Reason(blocked) end
        return true
    end
    return false, REASONS.gone
end

---------------------------------------------------------------------------
-- Kept across a /reload while you stay in the party (pins/Sync.lua decides when). Plain data only.
---------------------------------------------------------------------------
function PN.ExportSession()
    if not session then return nil end
    local pins = {}
    for _, p in pairs(session.pins) do
        pins[#pins + 1] = { owner = p.owner, id = p.id, r = p.rev, m = p.map, x = p.x, y = p.y, n = p.name, c = p.color, mine = p.mine or nil, k = p.mine and p.kept or nil,
            s = p.mine and p.source or nil }
    end
    local dismissed, deleted = {}, {}
    for _, key in ipairs(session.dismissOrder) do dismissed[#dismissed + 1] = key end
    for _, key in ipairs(session.deletedOrder) do deleted[#deleted + 1] = { key, session.deleted[key] } end
    return { epoch = session.epoch, seq = session.seq, pins = pins, dismissed = dismissed, deleted = deleted }
end

-- Everything is checked again as if it had just arrived; what can't be read is left out.
function PN.ImportSession(s)
    if type(s) ~= "table" or type(s.epoch) ~= "string" or not s.epoch:match("^%w+$") or #s.epoch > 12 then return false end
    session = NewSession(s.epoch)
    session.seq = IsInteger(s.seq, 0, MAX_REV) and s.seq or 0
    local me = SelfName()
    if type(s.deleted) == "table" then
        for i = 1, math.min(#s.deleted, PN.MAX_DELETED) do
            local d = s.deleted[i]
            if type(d) == "table" and type(d[1]) == "string" and IsInteger(d[2], 0, MAX_REV) then
                Remember(session.deleted, session.deletedOrder, d[1], d[2], PN.MAX_DELETED)
            end
        end
    end
    if type(s.pins) == "table" then
        for i = 1, math.min(#s.pins, PN.MAX_SHARED) do
            local t = s.pins[i]
            local data = type(t) == "table" and type(t.owner) == "string" and PN.ReadPin(t)
            if data then
                local mine = t.mine == true and SameName(t.owner, me)
                local owner = mine and me or t.owner
                local key = PN.Key(owner, data.id)
                if not session.deleted[key] and (session.perOwner[owner] or 0) < PN.MAX_PER_OWNER then
                    local source = mine and type(t.s) == "string" and #t.s <= 20 and t.s:match("^L%d+$") and t.s or nil
                    Put({ key = key, owner = owner, id = data.id, rev = data.rev, map = data.map, x = data.x, y = data.y,
                        name = data.name, color = data.color, mine = mine, at = time(), kept = mine and t.k == true or nil,
                        source = source })
                end
            end
        end
    end
    if type(s.dismissed) == "table" then
        for i = 1, math.min(#s.dismissed, PN.MAX_DISMISSED) do
            local key = s.dismissed[i]
            if type(key) == "string" and session.pins[key] then
                Remember(session.dismissed, session.dismissOrder, key, true, PN.MAX_DISMISSED)
            end
        end
    end
    Changed()
    return true
end

---------------------------------------------------------------------------
-- The pins to draw and list. selected: "local:<id>" or "party:<key>", the pin picked in the window or
-- on the map (its label shows when labels are on hover).
---------------------------------------------------------------------------
PN.selected = nil

function PN.Select(token)
    if PN.selected == token then return end
    PN.selected = token
    Changed()
end

-- Every pin, as entries { kind, pin, token, dismissed }, local first then party, each in a fixed order.
function PN.Entries()
    local out = {}
    local copies = GroupCopies()
    for _, p in ipairs(PN.LocalPins()) do
        out[#out + 1] = { kind = "local", pin = p, token = "local:" .. p.id, dismissed = false, kept = PN.IsKept(p),
            shared = copies[p.id] ~= nil }
    end
    local shared = PN.SharedPins()
    table.sort(shared, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.owner ~= b.owner then return a.owner < b.owner end
        return a.at < b.at or (a.at == b.at and a.id < b.id)
    end)
    for _, p in ipairs(shared) do
        out[#out + 1] = { kind = "party", pin = p, token = "party:" .. p.key, dismissed = PN.IsDismissed(p.key), kept = PN.IsKept(p) }
    end
    return out
end

-- Kept pins of yours, local and party. A count only.
function PN.KeptCount()
    local n = 0
    for _, p in ipairs(PN.LocalPins()) do if PN.IsKept(p) then n = n + 1 end end
    if session then
        for _, p in pairs(session.pins) do if p.mine and PN.IsKept(p) then n = n + 1 end end
    end
    return n
end

-- Read only, for /tui diagnostics: counts and codes, never names, places or text.
function PN.Snapshot()
    local drops = {}
    for code, n in pairs(PN.drops) do drops[#drops + 1] = code .. " " .. n end
    table.sort(drops)
    local deleted, sharedLocal = 0, 0
    if session then for _ in pairs(session.deleted) do deleted = deleted + 1 end end
    for _ in pairs(GroupCopies()) do sharedLocal = sharedLocal + 1 end
    return {
        localPins = PN.LocalCount(), shared = PN.SharedCount(), own = PN.OwnCount(), kept = PN.KeptCount(),
        dismissed = PN.DismissedCount(), deleted = deleted, owners = #PN.Owners(),
        session = session ~= nil, drops = drops, sharedLocal = sharedLocal,
    }
end
