-- TwichUI: restore points
-- Named snapshots of your own settings, called "backups" in the window: the addons chosen in "Share setup",
-- taken exactly as saved on disk, and TwichUI's own settings (point.own, below). Restoring one works like
-- applying a shared configuration: your current settings are backed up first, so Undo still works, and the UI
-- reloads.

local R = TwichUI
local ST = R.Setups
local RS = {}
R.Restore = RS

-- TwichUIRestoreDB = { points = { point... }, applyOwn = job | nil, ownUndo = undo | nil }
local function DB()
    if type(TwichUIRestoreDB) ~= "table" then TwichUIRestoreDB = {} end
    if type(TwichUIRestoreDB.points) ~= "table" then TwichUIRestoreDB.points = {} end
    return TwichUIRestoreDB
end

local function SetOf(list) local s = {} for _, k in ipairs(list) do s[k] = true end return s end
local function Copy(v) return type(v) == "table" and ST.DeepCopy(v) or v end

local function AddonVersion()
    if R.Group and R.Group.Version then
        local ok, v = pcall(R.Group.Version)
        if ok and type(v) == "string" then return v end
    end
    return "?"
end

---------------------------------------------------------------------------
-- TwichUI's own settings in a backup
--
-- point.own = { schema, made, addon, keys = { [key] = value, setup = { [key] = value } } }
--   schema  TwichUIDB.schema when it was made (Persist.lua). Restoring an older one is upgraded like any older
--           saved file; a newer one is never restored.
--   keys    copies of the TwichUIDB keys below, as they were saved.
--
-- Everything that is a setting is kept: every switch (those that act for you included), places, looks, text
-- choices, gear preferences and stat weights, how you send, your profiles and which character uses which, and
-- what you chose to share and back up. What is left out is not a setting: TwichUI's records and copies, which a
-- restore must never remove or bring back (RS.OWN_LEFT_OUT, each with its reason). A test checks that every key
-- TwichUI saves is in one list or the other, so a key added later has to be placed.
---------------------------------------------------------------------------
RS.OWN_KEYS = { "modules", "ui", "gear", "shareTransport", "profiles", "profileKeys", "profileState" }
RS.OWN_SETUP = { "selection", "recommend", "trusted", "twichui" }   -- the parts of TwichUIDB.setup that are choices
RS.OWN_LEFT_OUT = {
    pins = "map pins and the party session: what you placed, not settings. A restore never removes a pin.",
    npcs = "the vendors and trainers you noted or were sent: records, not settings. A restore never removes one.",
    storedData = "notes from the last saved-data search; searching again makes them",
    whisperProbe = "the result of a check TwichUI makes by itself",
    welcome = "whether the welcome has been shown",
    diagnosticsArm = "a one-shot hand-off between loads (TwichUI Diagnostics' Arm next reload)",
    schema = "kept with the backup as its schema",
    migrated = "an obsolete marker",
    heldStored = "a newer TwichUI's settings, set aside unchanged",
    ["setup.detected"] = "the last addon-settings search; searching again makes it",
    ["setup.received"] = "setups friends sent you",
    ["setup.pending"] = "an apply or undo waiting for the next reload",
    ["setup.scanNext"] = "a one-shot hand-off between loads", ["setup.restoreNext"] = "a one-shot hand-off between loads",
    ["setup.lastScan"] = "when you last searched",
    ["setup.twichUndo"] = "the Undo copy of a friend's TwichUI settings",
    ["setup.eui"] = "EllesmereUI profile bookkeeping",
}
-- Kept in other saved variables, so never in TwichUIDB to begin with: backups themselves, Undo copies,
-- your saved setup and the journey journal.

local OWN_FIELDS = SetOf({ "schema", "made", "addon", "keys" })
local OWN_KEY_SET = SetOf(RS.OWN_KEYS)
local OWN_SETUP_SET = SetOf(RS.OWN_SETUP)

-- What each key may be. shareTransport is a word (Persist.lua checks which); everything else is a table.
local function KindOk(key, v)
    if key == "shareTransport" then return type(v) == "string" and #v <= 16 end
    return type(v) == "table"
end

-- nil when the part can be restored here, or why not: "damaged", "unknown" (fields this version doesn't know),
-- "newer" (made by a newer TwichUI). The shape only; ST.CheckData walks the contents.
function RS.OwnProblem(own)
    local P = R.Persist
    if type(own) ~= "table" or type(own.keys) ~= "table" then return "damaged" end
    for k in pairs(own) do if not OWN_FIELDS[k] then return "unknown" end end
    if not P.IsCount(own.schema) then return "damaged" end
    if own.made ~= nil and (type(own.made) ~= "number" or own.made ~= own.made) then return "damaged" end
    if own.addon ~= nil and (type(own.addon) ~= "string" or #own.addon > 32) then return "damaged" end
    for k, v in pairs(own.keys) do
        if k == "setup" then
            if type(v) ~= "table" then return "damaged" end
            for sk, sv in pairs(v) do
                if not OWN_SETUP_SET[sk] then return "unknown" end
                if type(sv) ~= "table" then return "damaged" end
            end
        elseif not OWN_KEY_SET[k] then
            return "unknown"
        elseif not KindOk(k, v) then
            return "damaged"
        end
    end
    if own.schema > P.SCHEMA then return "newer" end
    return nil
end

RS.OWN_WHY = {
    damaged = "that part of the backup can't be read.",
    unknown = "that part was made by a newer TwichUI. Update TwichUI to restore it.",
    newer = "that part was made by a newer TwichUI. Update TwichUI to restore it.",
    future = "the settings you have now were saved by a newer TwichUI, and TwichUI never replaces those.",
    gone = "the backup isn't there any more.",
}

-- A copy of the keys above from db (TwichUIDB, or the raw saved copy at load). A value of the wrong kind is left
-- out: there is nothing in it to put back.
local function CaptureFrom(db)
    local P = R.Persist
    local keys = {}
    for _, k in ipairs(RS.OWN_KEYS) do
        if KindOk(k, db[k]) then keys[k] = Copy(db[k]) end
    end
    if type(db.setup) == "table" then
        local s = {}
        for _, k in ipairs(RS.OWN_SETUP) do
            if type(db.setup[k]) == "table" then s[k] = Copy(db.setup[k]) end
        end
        if next(s) ~= nil then keys.setup = s end
    end
    return { schema = P.IsCount(db.schema) and db.schema or 0, made = time(), addon = AddonVersion(), keys = keys }
end

-- TwichUI's own settings as they are now, or nil when this session isn't running on yours (a newer TwichUI's
-- were set aside, and the session runs on defaults that must not be saved as a backup of them).
function RS.CaptureOwn()
    if type(TwichUIDB) ~= "table" or R.Persist.IsHeld("TwichUIDB") then return nil end
    return CaptureFrom(TwichUIDB)
end

---------------------------------------------------------------------------
-- Checking what was saved
---------------------------------------------------------------------------
-- Checks what was saved, once at load. A backup is the player's own, so it is kept whenever anything
-- of it can be used: a missing id, name or date is made good; an addon's settings that are not
-- readable are dropped from it (there is nothing in them to restore); something that is not a backup
-- at all is dropped. Unknown fields are left alone.
function RS.Normalize()
    local P = R.Persist
    P.EnsureRoot("TwichUIRestoreDB")
    local db = DB()
    local ids, list, repaired = {}, {}, 0
    for _, p in ipairs(P.Sequence(db.points)) do
        if type(p) ~= "table" then
            P.Repair("restore-point-dropped")
        else
            local fixed = false
            if type(p.tables) ~= "table" then p.tables = {}; fixed = true end
            local dropped = 0
            for name, e in pairs(p.tables) do
                if not ST.EntryShape(name, e) then p.tables[name] = nil; dropped = dropped + 1 end
            end
            -- TwichUI's own settings: only a part that isn't one at all goes. One a newer TwichUI wrote is kept as
            -- it is (it can't be restored here, but it can be after an update).
            if p.own ~= nil and (type(p.own) ~= "table" or type(p.own.keys) ~= "table") then
                p.own = nil; dropped = dropped + 1
            end
            if dropped > 0 then P.Repair("setup-table-dropped", dropped) end
            if type(p.id) ~= "string" or p.id == "" or ids[p.id] then
                local id = R.Share.NewId()
                while ids[id] do id = R.Share.NewId() end
                p.id = id
                fixed = true
            end
            ids[p.id] = true
            if type(p.created) ~= "number" or p.created ~= p.created then p.created = nil end
            if type(p.name) ~= "string" or p.name:gsub("%s", "") == "" then
                p.name = p.created and date("%b %d %H:%M", p.created) or "Backup"
                fixed = true
            end
            if p.source ~= nil and type(p.source) ~= "string" then p.source = nil end
            if p.sourceName ~= nil and type(p.sourceName) ~= "string" then p.sourceName = nil end
            if p.imported ~= nil and type(p.imported) ~= "number" then p.imported = nil end
            if fixed then repaired = repaired + 1 end
            list[#list + 1] = p
        end
    end
    if repaired > 0 then P.Repair("restore-point-repaired", repaired) end
    db.points = list
    -- The Undo copy of TwichUI's own settings: { from, stamp, created, own }.
    local u = db.ownUndo
    if u ~= nil and (type(u) ~= "table" or type(u.own) ~= "table" or type(u.own.keys) ~= "table") then
        db.ownUndo = nil
        P.Repair("backup-dropped")
    elseif u then
        if u.from ~= nil and type(u.from) ~= "string" then u.from = nil end
        if u.stamp ~= nil and type(u.stamp) ~= "number" then u.stamp = nil end
        if u.created ~= nil and type(u.created) ~= "number" then u.created = nil end
    end
    -- A queued job is taken at the start of a load (RS.ApplyOwnAtLoad), so one still here is from a load where
    -- that couldn't run. It was asked for: it stays for the next load, unless it can't be read.
    if db.applyOwn ~= nil and (type(db.applyOwn) ~= "table"
        or not (type(db.applyOwn.id) == "string" or db.applyOwn.undo == true)) then
        db.applyOwn = nil
        P.Repair("pending-dropped")
    end
end
R:OnInit(RS.Normalize)

function RS.List()
    local list = {}
    for _, p in ipairs(DB().points) do list[#list + 1] = p end
    table.sort(list, function(a, b) return (a.created or 0) > (b.created or 0) end)
    return list
end

function RS.Get(id)
    for _, p in ipairs(DB().points) do if p.id == id then return p end end
end

-- Restore points act as a configuration source for the apply code.
local baseSource = ST.SourcePack
function ST.SourcePack(key)
    local id = type(key) == "string" and key:match("^restore:(.+)$")
    if id then return RS.Get(id) end
    return baseSource(key)
end

-- Whether a backup holds TwichUI's own settings, and a short "what's in it" for the window.
function RS.HasOwn(p) return type(p) == "table" and type(p.own) == "table" end

function RS.Contents(p)
    local n = ST.CountAddons(p)
    local addons = ("%d %s"):format(n, n == 1 and "addon" or "addons")
    if not RS.HasOwn(p) then return addons end
    if n == 0 then return "TwichUI's settings" end
    return addons .. " and TwichUI's settings"
end

-- Identical backups give identical hashes (Portable.lua uses it to spot an import you already have).
function RS.Hash(p)
    return ST.Hash({ tables = p and p.tables or {}, own = RS.HasOwn(p) and p.own.keys or nil })
end

---------------------------------------------------------------------------
-- Creating
---------------------------------------------------------------------------
local function DefaultName() return date("%b %d %H:%M") end

local function AnyChosen()
    for _, sel in pairs(ST.db and ST.db.selection or {}) do if sel then return true end end
    return false
end

-- Whether Create has to reload first: addons are chosen, and their settings must be read exactly as saved.
function RS.NeedsReload() return not ST.capture and AnyChosen() end

local function NewPoint(name, tables)
    local own = RS.CaptureOwn()
    if next(tables) == nil and not own then return nil end
    local point = {
        id = R.Share.NewId(),
        name = (name and name ~= "") and name or DefaultName(),
        created = time(),
        source = ST.CharKey(),
        sourceName = (GetUnitName and GetUnitName("player", true)) or UnitName("player"),
        tables = tables,
        own = own,
    }
    table.insert(DB().points, point)
    return point
end

-- Builds the point from this session's settings search (what's on disk) and TwichUI's own settings.
local function CreateFromCapture(name)
    local tables = {}
    for tname, sel in pairs(ST.db.selection) do
        local cap = ST.capture and ST.capture[tname]
        if sel and cap then
            -- Its own copy: the search's data stays as it was, whatever happens to either later.
            tables[tname] = { owner = cap.owner, data = ST.DeepCopy(cap.data) }
        end
    end
    return NewPoint(name, tables)
end

-- Returns "created", point  |  "reloading"  |  nil, reason
function RS:Create(name)
    if InCombatLockdown() then return nil, "Not in combat, please." end
    if ST.capture or not AnyChosen() then
        -- With no addons chosen there is nothing to read from disk: the backup is TwichUI's own settings.
        local p = ST.capture and CreateFromCapture(name) or NewPoint(name, {})
        if not p then return nil, "There's nothing to back up: no addons are chosen in Share setup, and TwichUI's own settings can't be read this session." end
        return "created", p
    end
    -- Need a fresh look at what's on disk: reload once and finish at login.
    ST.db.restoreNext = (name and name ~= "") and name or DefaultName()
    ST.db.scanNext = true
    ReloadUI()
    return "reloading"
end

-- Adds a backup that came from an export string, as a new point with its own
-- id and an unused name. Nothing is applied. The caller has already checked it.
function RS.AddImported(point)
    local points = DB().points
    local ids, names = {}, {}
    for _, p in ipairs(points) do ids[p.id] = true; names[p.name] = true end
    local id = R.Share.NewId()
    while ids[id] do id = R.Share.NewId() end
    local name, n = point.name, 1
    if names[name] then
        name = point.name .. " (imported)"
        while names[name] do n = n + 1; name = ("%s (imported %d)"):format(point.name, n) end
    end
    local new = {
        id = id, name = name, created = point.created, imported = time(),
        source = point.source or "imported", sourceName = point.sourceName, tables = point.tables, own = point.own,
    }
    table.insert(points, new)
    return new
end

---------------------------------------------------------------------------
-- Restoring
---------------------------------------------------------------------------
-- Why TwichUI's own settings in p can't be restored now, or nil when they can (or there are none).
local function OwnBlocked(p)
    if not RS.HasOwn(p) then return nil end
    if R.Persist.IsHeld("TwichUIDB") then return RS.OWN_WHY.future end
    local why = RS.OwnProblem(p.own)
    return why and RS.OWN_WHY[why] or nil
end
RS.OwnBlocked = OwnBlocked

-- Queues the restore (the game reloads). Returns true, note | nil, reason when there is nothing it can restore.
-- note says why TwichUI's own settings in it won't be restored, when that is so.
function RS:Restore(id)
    local p = RS.Get(id)
    if not p then return nil, "That backup isn't there any more." end
    local names = {}
    for tname, e in pairs(type(p.tables) == "table" and p.tables or {}) do
        if ST.ValidEntry(tname, e) then names[#names + 1] = tname end
    end
    local blocked = OwnBlocked(p)
    local own = RS.HasOwn(p) and not blocked
    if #names == 0 and not own then
        return nil, blocked and ("TwichUI's settings in it can't be restored: " .. blocked) or "That backup has nothing TwichUI can restore."
    end
    table.sort(names)
    -- TwichUI's own settings are put back at the very start of the next load (RS.ApplyOwnAtLoad).
    if own then DB().applyOwn = { id = id, at = time() } end
    if #names > 0 then ST:Queue("apply", names, "restore:" .. id) else ReloadUI() end
    return true, blocked and ("TwichUI's settings in it won't be restored: " .. blocked) or nil
end

-- Runs from Persist.LoadMain, before anything else reads TwichUIDB, when a restore (or its Undo) was queued last
-- session: features haven't started and nothing written at logout can follow it. Everything is checked and
-- copied first, then written with plain assignments, so either all of it is put back or none of it.
-- db is TwichUIDB as loaded; the usual upgrade and checks run on the result straight after.
function RS.ApplyOwnAtLoad(db)
    local P = R.Persist
    local rdb = P.EnsureRoot("TwichUIRestoreDB")
    local job = rdb.applyOwn
    if job == nil then return end
    rdb.applyOwn = nil   -- one go, whatever happens: a job that fails is reported, never retried every load
    if type(job) ~= "table" then return end
    local undoing = job.undo == true
    local part, name, stamp
    if undoing then
        local u = rdb.ownUndo
        if type(u) == "table" then part, name = u.own, u.from end
    elseif type(job.id) == "string" then
        for _, p in ipairs(type(rdb.points) == "table" and P.Sequence(rdb.points) or {}) do
            if type(p) == "table" and p.id == job.id then part, name, stamp = p.own, p.name, p.created end
        end
    end
    local function Done(outcome) RS.ownResult = { outcome = outcome, name = type(name) == "string" and name or nil, undo = undoing } end
    if part == nil then return Done("gone") end
    if P.IsCount(db.schema) and db.schema > P.SCHEMA then return Done("future") end
    local why = RS.OwnProblem(part)
    if why then return Done(why) end
    if not ST.CheckData(part.keys) then return Done("damaged") end

    local new, newSetup = {}, {}
    for _, k in ipairs(RS.OWN_KEYS) do new[k] = Copy(part.keys[k]) end
    local ps = type(part.keys.setup) == "table" and part.keys.setup or {}
    for _, k in ipairs(RS.OWN_SETUP) do newSetup[k] = Copy(ps[k]) end
    local undo = not undoing and {
        from = type(name) == "string" and name or nil, stamp = type(stamp) == "number" and stamp or nil,
        created = time(), own = CaptureFrom(db),
    } or nil

    if undo then rdb.ownUndo = undo end
    for _, k in ipairs(RS.OWN_KEYS) do db[k] = new[k] end
    if type(db.setup) ~= "table" then db.setup = {} end
    for _, k in ipairs(RS.OWN_SETUP) do db.setup[k] = newSetup[k] end
    -- The backup's schema: an older one is upgraded by the steps that follow, as any older saved file is. They are
    -- repeatable, so the parts a backup doesn't hold (pins, records) come through them unchanged.
    db.schema = part.schema > 0 and part.schema or nil
    Done("restored")
end

---------------------------------------------------------------------------
-- Undo
---------------------------------------------------------------------------
function RS.OwnUndo()
    local u = DB().ownUndo
    if type(u) == "table" and type(u.own) == "table" then return u end
end

-- What "Undo last change" puts back: this character's addon settings (Setups.lua's Undo copy), TwichUI's own,
-- or both when one restore made them. When they come from different changes, only the later one.
-- Returns addons (true/false), own (true/false).
function RS.UndoPlan()
    local u = RS.OwnUndo()
    local addons = ST:HasBackup() and true or false
    if not u then return addons, false end
    if not addons then return false, true end
    local b = TwichUIBackupDB[ST.CharKey()]
    if u.stamp and b.stamp == u.stamp then return true, true end
    if (u.created or 0) >= (b.created or 0) then return false, true end
    return true, false
end

function RS.CanUndo()
    local addons, own = RS.UndoPlan()
    return addons or own
end

-- Queues the Undo (the game reloads). Returns true | nil, reason.
function RS:UndoLast()
    local addons, own = RS.UndoPlan()
    if not (addons or own) then return nil, "There is nothing left to put back, so nothing was changed." end
    if own then DB().applyOwn = { undo = true, at = time() } end
    if addons then ST:Queue("undo", ST:BackupNames(), nil) else ReloadUI() end
    return true
end

function RS:Delete(id)
    local points = DB().points
    for i = #points, 1, -1 do if points[i].id == id then table.remove(points, i) end end
end

function RS.Size(p) return ST.SizeOf(p and p.tables or {}) + ST.SizeOf(RS.HasOwn(p) and p.own or nil) end

-- Show backups in the Saved data window too.
local baseItems = ST.StorageItems
function ST.StorageItems()
    local items = baseItems()
    for _, p in ipairs(RS.List()) do
        items[#items + 1] = {
            key = "restore:" .. p.id, kind = "Backup",
            label = ("Backup \"%s\""):format(p.name),
            detail = ("%s, %s, %s"):format(date("%b %d", p.created or 0), RS.Contents(p), p.sourceName or "?"),
            bytes = RS.Size(p), remove = function() RS:Delete(p.id) end,
            warn = "You won't be able to go back to this backup.",
        }
    end
    local u = RS.OwnUndo()
    if u then
        items[#items + 1] = {
            key = "restore-undo", kind = "Undo copy",
            label = "TwichUI's settings from before your last restore",
            detail = u.from and ("before \"%s\", %s"):format(u.from, date("%b %d", u.created or 0)) or date("%b %d", u.created or 0),
            bytes = ST.SizeOf(u), remove = function() DB().ownUndo = nil end,
            warn = "Without it, Undo can't put back the TwichUI settings you had before that restore.",
        }
    end
    table.sort(items, function(a, b) return a.bytes > b.bytes end)
    return items
end

R:On("PLAYER_LOGIN", function()
    -- What happened to TwichUI's own settings at the start of this load.
    local r = RS.ownResult
    if r then
        RS.ownResult = nil
        if r.outcome == "restored" then
            if r.undo then
                R.Print("put back TwichUI's own settings from before you restored%s.", r.name and (" \"" .. r.name .. "\"") or " a backup")
            else
                R.Print("TwichUI's own settings restored from backup \"%s\". Undo is on the Backups page.", r.name or "?")
            end
        else
            R.Print("TwichUI's own settings were not %s: %s Nothing of them was changed.", r.undo and "put back" or "restored",
                RS.OWN_WHY[r.outcome] or RS.OWN_WHY.damaged)
        end
    end

    -- Finish a restore point that needed a reload.
    if not ST.db or not ST.db.restoreNext then return end
    local name = ST.db.restoreNext
    ST.db.restoreNext = nil
    local p = ST.capture and CreateFromCapture(name)
    if p then
        R.Print("backup \"%s\" saved (%s).", p.name, RS.Contents(p))
    else
        R.Print("couldn't save the backup: nothing is chosen in Share setup.")
    end
    C_Timer.After(1, function() if R.Window then R.Window:Show("backups") end end)
end)
