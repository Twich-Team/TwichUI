-- TwichUI: restore points
-- Named snapshots of your own addon settings (the addons ticked on "My
-- configuration"), taken exactly as saved on disk. Restoring one works like
-- applying a shared configuration: your current settings are backed up first,
-- so Undo still works, and the UI reloads.

local R = TwichUI
local ST = R.Setups
local RS = {}
R.Restore = RS

local function DB()
    TwichUIRestoreDB = TwichUIRestoreDB or {}
    TwichUIRestoreDB.points = TwichUIRestoreDB.points or {}
    return TwichUIRestoreDB
end

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
            tables[tname] = { owner = cap.owner, data = cap.data }
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
        if not p then return nil, "Nothing is ticked on My configuration, so there's nothing to save." end
        return "created", p
    end
    -- Need a fresh look at what's on disk: reload once and finish at login.
    ST.db.restoreNext = (name and name ~= "") and name or DefaultName()
    ST.db.scanNext = true
    ReloadUI()
    return "reloading"
end

function RS:Restore(id)
    local p = RS.Get(id)
    if not p then return end
    local names = {}
    for tname in pairs(p.tables or {}) do names[#names + 1] = tname end
    ST:Queue("apply", names, "restore:" .. id)
end

function RS:Delete(id)
    local points = DB().points
    for i = #points, 1, -1 do if points[i].id == id then table.remove(points, i) end end
end

function RS.Size(p) return ST.SizeOf(p and p.tables or {}) end

-- Show restore points in the Saved data window too.
local baseItems = ST.StorageItems
function ST.StorageItems()
    local items = baseItems()
    for _, p in ipairs(RS.List()) do
        items[#items + 1] = {
            key = "restore:" .. p.id, kind = "Restore point",
            label = ("Restore point \"%s\""):format(p.name),
            detail = ("%s, %d addons, %s"):format(date("%b %d", p.created or 0), ST.CountAddons(p), p.sourceName or "?"),
            bytes = RS.Size(p), remove = function() RS:Delete(p.id) end,
            warn = "You won't be able to go back to this point.",
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
        R.Print("restore point \"%s\" saved (%d addons).", p.name, ST.CountAddons(p))
    else
        R.Print("couldn't save the restore point: nothing is ticked on My configuration.")
    end
    C_Timer.After(1, function() if R.Window then R.Window:Show("restore") end end)
end)
