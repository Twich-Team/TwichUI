-- TwichUI: Journey Chronicle, saved entries
-- A quiet per-character journal. This file only keeps and trims the entries;
-- chronicle/Recorder.lua decides what gets written and chronicle/Window.lua
-- shows them. The data lives in its own saved variable, TwichUIChronicleDB.
-- Its name starts with "TwichUI", so configuration sharing and backups never
-- read, send or restore it.
--
-- TwichUIChronicleDB = { version = 1, chars = { ["Name - Realm"] = {
--     entries = { { id, t, kind, title, note, zone, level, secsAtLevel, secsTotal }, ... }  -- oldest first
--     unreadable = { entry, ... }   -- entries this version cannot read (an unknown kind), kept as they were
--     nextId = n, tracking = bool,
--     journey = { baseLevel, baseTotal,   -- played seconds when the current level began
--                 lastLevel,              -- highest level-up already written
--                 gold = { last, earned, done = { [gold] = true } },  -- copper; thresholds already written
--                 riding = { [spellID] = true },
--                 professions = { baselined = bool, [skillLineID] = { [0] = true (learned), [rank] = true (milestone written) } } } } }

local R = TwichUI
local C = {}
R.Chronicle = C

C.MAX_ENTRIES = 500       -- per character
C.MAX_NOTE = 240          -- characters in a note
C.MAX_TITLE = 120
C.DUPLICATE_SECONDS = 60  -- the same automatic entry twice in this long is ignored

-- "note" is written by the player. The rest are written by TwichUI.
C.KINDS = { note = true, level = true, zone = true, boss = true, death = true, start = true, gold = true, riding = true, profession = true }

-- Anything that shows entries (the window, the data bar) can ask to hear about changes.
local watchers = {}
function C.OnChange(fn) watchers[#watchers + 1] = fn end
local function Changed()
    for i = 1, #watchers do
        local ok, err = pcall(watchers[i])
        if not ok then geterrorhandler()(err) end
    end
end
C.Changed = Changed

-- Characters, not bytes: a UTF-8 character is one lead byte plus continuation bytes (128-191).
function C.Length(text)
    return select(2, text:gsub("[^\128-\191]", ""))
end

-- The first `limit` characters; never cuts a character in half.
local function Truncate(text, limit)
    local count = 0
    for i = 1, #text do
        local b = text:byte(i)
        if b < 128 or b >= 192 then
            count = count + 1
            if count > limit then return text:sub(1, i - 1) end
        end
    end
    return text
end

local function Trim(text, limit)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return Truncate(text, limit)
end

-- Removes one entry to make room. Zone arrivals go first, then other automatic entries, oldest
-- first. The player's notes and the first line saying when tracking began stay; later
-- "Tracking resumed" lines can go. Returns false when nothing may be removed.
local function Evict(entries)
    local other, resumed, firstStart
    for i = 1, #entries do
        local kind = entries[i].kind
        if kind == "zone" then table.remove(entries, i) return true end
        if kind == "start" then
            if firstStart then resumed = resumed or i else firstStart = i end
        elseif kind ~= "note" then
            other = other or i
        end
    end
    local index = other or resumed
    if not index then return false end
    table.remove(entries, index)
    return true
end

function C.CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function Num(v) return type(v) == "number" and v >= 0 and v or nil end

-- Keeps only well-formed tracking state; missing parts are simply absent until measured.
-- Fields this version doesn't know are carried over untouched.
local JOURNEY_KEYS = { baseLevel = true, baseTotal = true, lastLevel = true, riding = true, professions = true, gold = true }
local function CleanJourney(rec)
    local old = type(rec.journey) == "table" and rec.journey or {}
    local j = { baseLevel = Num(old.baseLevel), baseTotal = Num(old.baseTotal), lastLevel = Num(old.lastLevel), riding = {} }
    for k, v in pairs(old) do
        if not JOURNEY_KEYS[k] then j[k] = v end
    end
    if type(old.riding) == "table" then
        for id, v in pairs(old.riding) do if type(id) == "number" and v == true then j.riding[id] = true end end
    end
    j.professions = { baselined = type(old.professions) == "table" and old.professions.baselined == true }
    if type(old.professions) == "table" then
        for id, p in pairs(old.professions) do
            if type(id) == "number" and type(p) == "table" then
                local clean = {}
                for k, v in pairs(p) do if type(k) == "number" and v == true then clean[k] = true end end
                j.professions[id] = clean
            end
        end
    end
    if type(old.gold) == "table" and Num(old.gold.last) then
        j.gold = { last = old.gold.last, earned = Num(old.gold.earned) or 0, done = {} }
        if type(old.gold.done) == "table" then
            for g, v in pairs(old.gold.done) do if type(g) == "number" and v == true then j.gold.done[g] = true end end
        end
    end
    rec.journey = j
end

-- Sort key: undated entries (no usable time) come first, in id order; nothing is given an invented date.
local function When(e) return (type(e.t) == "number" and e.t == e.t) and e.t or -math.huge end
local function ByTime(a, b)
    local ta, tb = When(a), When(b)
    if ta ~= tb then return ta < tb end
    return a.id < b.id
end

-- Cleans anything that looks wrong (older, partial or hand-edited data) without throwing away what the
-- player wrote: a note is kept whenever it has any text, and gets a fresh id or title if it lacks one;
-- it keeps no date rather than an invented one. An entry of a kind this version doesn't know (a newer
-- TwichUI wrote it) is set aside untouched in rec.unreadable. Only a row with nothing readable in it,
-- or an automatic entry missing its title, kind or time, is dropped.
local function CleanRecord(rec)
    local P = R.Persist
    if type(rec.entries) ~= "table" then rec.entries = {} end
    if type(rec.unreadable) ~= "table" then rec.unreadable = nil end
    local clean, repaired, maxId = {}, 0, 0
    local usedIds = {}
    for _, e in ipairs(P.Sequence(rec.entries)) do
        if type(e) ~= "table" then
            P.Repair("chronicle-entry-dropped")
        elseif type(e.kind) == "string" and not C.KINDS[e.kind] then
            rec.unreadable = rec.unreadable or {}
            rec.unreadable[#rec.unreadable + 1] = e
            P.Repair("chronicle-entry-set-aside")
        else
            local isNote = e.kind == "note"
            local title, note = Trim(e.title, C.MAX_TITLE), Trim(e.note, C.MAX_NOTE)
            local keep
            if isNote then
                title = title or (note and "Note")
                keep = title ~= nil
            else
                keep = C.KINDS[e.kind] and type(e.t) == "number" and title ~= nil
            end
            if not keep then
                P.Repair("chronicle-entry-dropped")
            else
                local fixed = isNote and Trim(e.title, C.MAX_TITLE) == nil   -- a note that had no title
                e.title, e.note = title, note
                e.zone = Trim(e.zone, C.MAX_TITLE)
                if type(e.level) ~= "number" then e.level = nil end
                if type(e.secsAtLevel) ~= "number" then e.secsAtLevel = nil end
                if type(e.secsTotal) ~= "number" then e.secsTotal = nil end
                if type(e.icon) ~= "string" and type(e.icon) ~= "number" then e.icon = nil end
                if type(e.t) ~= "number" then e.t = nil; fixed = true end
                if type(e.id) == "number" and e.id == e.id and e.id >= 0 and not usedIds[e.id] then
                    usedIds[e.id] = true
                    if e.id > maxId then maxId = e.id end
                else
                    e.id = false   -- given one below, after every id in use is known
                    fixed = true
                end
                if fixed then repaired = repaired + 1 end
                clean[#clean + 1] = e
            end
        end
    end
    for _, e in ipairs(clean) do
        if e.id == false then maxId = maxId + 1; e.id = maxId end
    end
    if repaired > 0 then P.Repair("chronicle-entry-repaired", repaired) end
    table.sort(clean, ByTime)
    local before = #clean
    while #clean > C.MAX_ENTRIES and Evict(clean) do end
    if #clean < before then P.Repair("chronicle-trimmed", before - #clean) end
    rec.entries = clean
    if type(rec.nextId) ~= "number" or rec.nextId <= maxId then rec.nextId = maxId + 1 end
    rec.tracking = rec.tracking == true
    CleanJourney(rec)
end

-- Set up at load. A Chronicle saved by a newer TwichUI (a higher version) is not read or changed: it is set
-- aside for the session and handed back at logout (see Persist.lua), and this session's Chronicle
-- starts empty and isn't saved.
function C.Init()
    local P = R.Persist
    P.EnsureRoot("TwichUIChronicleDB")
    local db = TwichUIChronicleDB
    if not P.IsHeld("TwichUIChronicleDB") then
        local stored = db.version
        if stored ~= nil and not P.IsCount(stored) then stored = nil end
        P.SetChronicle(stored, next(db) == nil and "fresh" or "current")
        if stored and stored > P.CHRONICLE_VERSION then
            db = { version = P.CHRONICLE_VERSION, chars = {} }
            P.Hold("TwichUIChronicleDB", TwichUIChronicleDB, db)
            P.SetChronicle(stored, "future")
            P.Repair("future-schema")
        end
    end
    db.version = P.CHRONICLE_VERSION
    if type(db.chars) ~= "table" then db.chars = {} end
    for key, rec in pairs(db.chars) do
        if type(key) ~= "string" or type(rec) ~= "table" then
            db.chars[key] = nil
            P.Repair("chronicle-record-dropped")
        else
            CleanRecord(rec)
        end
    end
end

-- This character's record, made on first use.
function C.Record()
    if type(TwichUIChronicleDB) ~= "table" or type(TwichUIChronicleDB.chars) ~= "table" then C.Init() end
    local key = C.CharKey()
    local rec = TwichUIChronicleDB.chars[key]
    if not rec then
        rec = { entries = {}, nextId = 1, tracking = false }
        CleanJourney(rec)
        TwichUIChronicleDB.chars[key] = rec
    end
    return rec
end

-- Entries oldest first. Don't change the table; use Add, Update and Delete.
function C.Entries() return C.Record().entries end
function C.Count() return #C.Record().entries end

-- "2h 34m", "1d 3h 12m", "45m", "under a minute". Whole minutes, rounded down.
function C.FormatDuration(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return nil end
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then return "under a minute" end
    local d, h, m = math.floor(minutes / 1440), math.floor(minutes % 1440 / 60), minutes % 60
    if d > 0 then return ("%dd %dh %dm"):format(d, h, m) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- The zone name, or nil when the game doesn't give one.
function C.CurrentZone()
    local zone = GetRealZoneText and GetRealZoneText()
    if type(zone) ~= "string" or zone == "" then zone = GetZoneText and GetZoneText() end
    if type(zone) ~= "string" or zone == "" then return nil end
    return Trim(zone, C.MAX_TITLE)
end

local function MakeRoom(entries)
    return #entries < C.MAX_ENTRIES or Evict(entries)
end

-- fields: title (required), note, zone, level, secsAtLevel, secsTotal, icon. Returns the entry, or nil and a reason.
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
            if type(e.t) == "number" and now - e.t > C.DUPLICATE_SECONDS then break end
            if e.kind == kind and e.title == title then return nil, "duplicate" end
        end
    end
    if not MakeRoom(entries) then return nil, "full" end
    local entry = {
        id = rec.nextId, t = now, kind = kind, title = title, note = note,
        zone = Trim(fields.zone, C.MAX_TITLE),
        level = type(fields.level) == "number" and fields.level or nil,
        secsAtLevel = Num(fields.secsAtLevel), secsTotal = Num(fields.secsTotal),
        icon = (type(fields.icon) == "string" or type(fields.icon) == "number") and fields.icon or nil,
    }
    rec.nextId = rec.nextId + 1
    entries[#entries + 1] = entry
    Changed()
    return entry
end

local function Find(id)
    local entries = C.Record().entries
    for i = 1, #entries do
        if entries[i].id == id then return entries[i], i end
    end
end
C.Find = Find

-- Adds measurements to an automatic entry after the fact (the note and played times).
function C.SetDetails(id, fields)
    local entry = Find(id)
    if not entry or entry.kind == "note" then return nil, "not found" end
    entry.note = Trim(fields.note, C.MAX_NOTE) or entry.note
    entry.secsAtLevel = Num(fields.secsAtLevel) or entry.secsAtLevel
    entry.secsTotal = Num(fields.secsTotal) or entry.secsTotal
    Changed()
    return entry
end

-- Only the player's own notes can be edited. keepZone = false removes the place.
function C.Update(id, text, keepZone)
    local entry = Find(id)
    if not entry or entry.kind ~= "note" then return nil, "not a note" end
    local note = Trim(text, C.MAX_NOTE)
    if not note then return nil, "empty" end
    entry.note = note
    if keepZone == false then entry.zone = nil end
    Changed()
    return entry
end

function C.Delete(id)
    local _, index = Find(id)
    if not index then return false end
    table.remove(C.Record().entries, index)
    Changed()
    return true
end

R:OnInit(C.Init)
