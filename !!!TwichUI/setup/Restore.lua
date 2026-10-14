-- TwichUI: restore points
-- Named snapshots of your own addon settings (the addons chosen in "Share
-- setup"), taken exactly as saved on disk. Called "backups" in the window. Restoring one works like
-- applying a shared configuration: your current settings are backed up first,
-- so Undo still works, and the UI reloads.

local R = TwichUI
local ST = R.Setups
local RS = {}
R.Restore = RS

local function DB()
    if type(TwichUIRestoreDB) ~= "table" then TwichUIRestoreDB = {} end
    if type(TwichUIRestoreDB.points) ~= "table" then TwichUIRestoreDB.points = {} end
    return TwichUIRestoreDB
end

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

local function DefaultName() return date("%b %d %H:%M") end

-- Builds the point from this session's settings search (what's on disk).
local function CreateFromCapture(name)
    local tables, count = {}, 0
    for tname, sel in pairs(ST.db.selection) do
        local cap = ST.capture and ST.capture[tname]
        if sel and cap then
            -- Its own copy: the search's data stays as it was, whatever happens to either later.
            tables[tname] = { owner = cap.owner, data = ST.DeepCopy(cap.data) }
            count = count + 1
        end
    end
    if count == 0 then return nil end
    local point = {
        id = R.Share.NewId(),
        name = (name and name ~= "") and name or DefaultName(),
        created = time(),
        source = ST.CharKey(),
        sourceName = (GetUnitName and GetUnitName("player", true)) or UnitName("player"),
        tables = tables,
    }
    table.insert(DB().points, point)
    return point
end

-- Returns "created", point  |  "reloading"  |  nil, reason
function RS:Create(name)
    if InCombatLockdown() then return nil, "Not in combat, please." end
    if ST.capture then
        local p = CreateFromCapture(name)
        if not p then return nil, "Nothing is chosen in Share setup, so there's nothing to back up." end
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
        source = point.source or "imported", sourceName = point.sourceName, tables = point.tables,
    }
    table.insert(points, new)
    return new
end

-- Queues the restore (the game reloads). Returns nil, reason when there is nothing it can restore.
function RS:Restore(id)
    local p = RS.Get(id)
    if not p then return nil, "That backup isn't there any more." end
    local names = {}
    for tname, e in pairs(type(p.tables) == "table" and p.tables or {}) do
        if ST.ValidEntry(tname, e) then names[#names + 1] = tname end
    end
    if #names == 0 then return nil, "That backup has nothing TwichUI can restore." end
    table.sort(names)
    ST:Queue("apply", names, "restore:" .. id)
    return true
end

function RS:Delete(id)
    local points = DB().points
    for i = #points, 1, -1 do if points[i].id == id then table.remove(points, i) end end
end

function RS.Size(p) return ST.SizeOf(p and p.tables or {}) end

-- Show backups in the Saved data window too.
local baseItems = ST.StorageItems
function ST.StorageItems()
    local items = baseItems()
    for _, p in ipairs(RS.List()) do
        items[#items + 1] = {
            key = "restore:" .. p.id, kind = "Backup",
            label = ("Backup \"%s\""):format(p.name),
            detail = ("%s, %d addons, %s"):format(date("%b %d", p.created or 0), ST.CountAddons(p), p.sourceName or "?"),
            bytes = RS.Size(p), remove = function() RS:Delete(p.id) end,
            warn = "You won't be able to go back to this backup.",
        }
    end
    table.sort(items, function(a, b) return a.bytes > b.bytes end)
    return items
end

-- Finish a restore point that needed a reload.
R:On("PLAYER_LOGIN", function()
    if not ST.db or not ST.db.restoreNext then return end
    local name = ST.db.restoreNext
    ST.db.restoreNext = nil
    local p = ST.capture and CreateFromCapture(name)
    if p then
        R.Print("backup \"%s\" saved (%d addons).", p.name, ST.CountAddons(p))
    else
        R.Print("couldn't save the backup: nothing is chosen in Share setup.")
    end
    C_Timer.After(1, function() if R.Window then R.Window:Show("backups") end end)
end)
