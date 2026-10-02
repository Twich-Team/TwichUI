-- TwichUI: Journey Chronicle, saved entries
-- A quiet per-character journal. This file only keeps and trims the entries;
-- chronicle/Recorder.lua decides what gets written and chronicle/Window.lua
-- shows them. The data lives in its own saved variable, TwichUIChronicleDB.
-- Its name starts with "TwichUI", so configuration sharing and backups never
-- read, send or restore it.
--
-- TwichUIChronicleDB = { version = 1, chars = { ["Name - Realm"] = {
--     entries = { { id, t, kind, title, note, zone, level }, ... }  -- oldest first
--     nextId = n, tracking = bool } } }

local R = TwichUI
local C = {}
R.Chronicle = C

C.MAX_ENTRIES = 500       -- per character
C.MAX_NOTE = 240          -- characters in a note
C.MAX_TITLE = 120
C.DUPLICATE_SECONDS = 60  -- the same automatic entry twice in this long is ignored

-- "note" is written by the player. The rest are written by TwichUI.
C.KINDS = { note = true, level = true, zone = true, boss = true, death = true, start = true }

local function Trim(text, limit)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if #text > limit then text = text:sub(1, limit) end
    return text
end

function C.CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

-- Cleans anything that looks wrong (older, partial or hand-edited data).
local function CleanRecord(rec)
    if type(rec.entries) ~= "table" then rec.entries = {} end
    local clean, maxId, seen = {}, 0, {}
    for _, e in ipairs(rec.entries) do
        if type(e) == "table" and C.KINDS[e.kind] and type(e.id) == "number" and not seen[e.id]
            and type(e.t) == "number" and type(e.title) == "string" then
            seen[e.id] = true
            if type(e.note) ~= "string" then e.note = nil end
            if type(e.zone) ~= "string" then e.zone = nil end
            if type(e.level) ~= "number" then e.level = nil end
            clean[#clean + 1] = e
            if e.id > maxId then maxId = e.id end
        end
    end
    table.sort(clean, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
    rec.entries = clean
    if type(rec.nextId) ~= "number" or rec.nextId <= maxId then rec.nextId = maxId + 1 end
    rec.tracking = rec.tracking == true
end

function C.Init()
    if type(TwichUIChronicleDB) ~= "table" then TwichUIChronicleDB = {} end
    local db = TwichUIChronicleDB
    db.version = 1
    if type(db.chars) ~= "table" then db.chars = {} end
    for key, rec in pairs(db.chars) do
        if type(rec) ~= "table" then db.chars[key] = nil else CleanRecord(rec) end
    end
end

-- This character's record, made on first use.
function C.Record()
    if type(TwichUIChronicleDB) ~= "table" or type(TwichUIChronicleDB.chars) ~= "table" then C.Init() end
    local key = C.CharKey()
    local rec = TwichUIChronicleDB.chars[key]
    if not rec then
        rec = { entries = {}, nextId = 1, tracking = false }
        TwichUIChronicleDB.chars[key] = rec
    end
    return rec
end

-- Entries oldest first. Don't change the table; use Add, Update and Delete.
function C.Entries() return C.Record().entries end
function C.Count() return #C.Record().entries end

-- The zone name, or nil when the game doesn't give one.
function C.CurrentZone()
    local zone = GetRealZoneText and GetRealZoneText()
    if type(zone) ~= "string" or zone == "" then zone = GetZoneText and GetZoneText() end
    if type(zone) ~= "string" or zone == "" then return nil end
    return Trim(zone, C.MAX_TITLE)
end

-- Makes room for one more. Automatic entries go first, oldest first; the
-- player's own notes (and the line that says when tracking began) stay.
local function MakeRoom(entries)
    if #entries < C.MAX_ENTRIES then return true end
    for i = 1, #entries do
        local kind = entries[i].kind
        if kind ~= "note" and kind ~= "start" then
            table.remove(entries, i)
            return true
        end
    end
    return false
end

-- fields: title (required), note, zone, level. Returns the entry, or nil and a reason.
function C.Add(kind, fields)
    if not C.KINDS[kind] then return nil, "unknown kind" end
    fields = fields or {}
    local title = Trim(fields.title, C.MAX_TITLE)
    if kind == "note" then title = title or "Note" end
    if not title then return nil, "no title" end
    local note = Trim(fields.note, C.MAX_NOTE)
    if kind == "note" and not note then return nil, "empty" end
    local rec = C.Record()
    local entries, now = rec.entries, time()
    if kind ~= "note" then
        for i = #entries, 1, -1 do
            local e = entries[i]
            if now - e.t > C.DUPLICATE_SECONDS then break end
            if e.kind == kind and e.title == title then return nil, "duplicate" end
        end
    end
    if not MakeRoom(entries) then return nil, "full" end
    local entry = {
        id = rec.nextId, t = now, kind = kind, title = title, note = note,
        zone = Trim(fields.zone, C.MAX_TITLE),
        level = type(fields.level) == "number" and fields.level or nil,
    }
    rec.nextId = rec.nextId + 1
    entries[#entries + 1] = entry
    return entry
end

local function Find(id)
    local entries = C.Record().entries
    for i = 1, #entries do
        if entries[i].id == id then return entries[i], i end
    end
end
C.Find = Find

-- Only the player's own notes can be edited. keepZone = false removes the place.
function C.Update(id, text, keepZone)
    local entry = Find(id)
    if not entry or entry.kind ~= "note" then return nil, "not a note" end
    local note = Trim(text, C.MAX_NOTE)
    if not note then return nil, "empty" end
    entry.note = note
    if keepZone == false then entry.zone = nil end
    return entry
end

function C.Delete(id)
    local _, index = Find(id)
    if not index then return false end
    table.remove(C.Record().entries, index)
    return true
end

R:OnInit(C.Init)
