-- TwichUI: Setup Sharing, core
--
-- A "setup" is a copy of the saved settings of the addons you pick.
--
-- Because TwichUI loads before other addons, our ADDON_LOADED handler runs
-- right after the game has read an addon's saved settings from disk and
-- before that addon's own code looks at them. That one moment is used to:
--   * find settings  (scan): note which new data tables each addon brings in,
--                            and keep a copy of them exactly as saved on disk
--   * apply a setup:         swap in the setup's copy (keeping a backup), so
--                            the addon starts as if the files were copied in
--   * undo:                  swap the backup back in
-- Anything that needs that moment is queued and runs after a UI reload.

local R = TwichUI
local ST = {}
R.Setups = ST

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local db                     -- TwichUIDB.setup
ST.capture = nil             -- copies taken during a find-settings session (memory only)
ST.report = nil              -- result of the last apply/undo this session
ST.loadedBefore = {}         -- addons that loaded before TwichUI

function ST.CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end
local CharKey = ST.CharKey

---------------------------------------------------------------------------
-- Data helpers
---------------------------------------------------------------------------
local VALUE_OK = { string = true, number = true, boolean = true, table = true }

local function DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    seen = seen or {}
    if seen[src] then return seen[src] end
    local dst = {}
    seen[src] = dst
    for k, v in next, src do
        local kt, vt = type(k), type(v)
        if (kt == "string" or kt == "number" or kt == "boolean") and VALUE_OK[vt] then
            dst[k] = (vt == "table") and DeepCopy(v, seen) or v
        end
    end
    return dst
end
ST.DeepCopy = DeepCopy

local NODE_CAP = 3000000
local function Inspect(t)
    local nodes, bytes, pure = 0, 0, true
    local seen = {}
    local function walk(x)
        if seen[x] or not pure or nodes > NODE_CAP then return end
        seen[x] = true
        for k, v in next, x do
            nodes = nodes + 1
            local kt, vt = type(k), type(v)
            if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then pure = false return end
            if not VALUE_OK[vt] then pure = false return end
            bytes = bytes + (kt == "string" and #k + 6 or 10)
            if vt == "string" then bytes = bytes + #v + 4
            elseif vt == "table" then bytes = bytes + 4; walk(v)
            else bytes = bytes + 8 end
        end
    end
    walk(t)
    return pure, bytes, nodes > NODE_CAP
end

function ST.FormatSize(b)
    b = b or 0
    if b >= 1048576 then return ("%.1f MB"):format(b / 1048576) end
    if b >= 1024 then return ("%.0f KB"):format(b / 1024) end
    return b .. " B"
end

-- Fingerprint of a settings table: identical settings give identical hashes
-- on every machine, so updates only send what changed.
function ST.Hash(data)
    local ok, str = pcall(LibSerialize.SerializeEx, LibSerialize, { stable = true }, data)
    if not ok then return nil end
    return LibDeflate:Adler32(str) .. ":" .. #str
end

-- Settings-looking names are ticked by default; data stores are not.
local LIKELY = { "db", "setting", "config", "option", "profile", "saved", "vars", "pref", "layout" }
local UNLIKELY = { "price", "cache", "log", "history", "bug", "data$", "stats", "scan", "database", "inventory", "items" }
local SUGGEST_MAX = 2 * 1048576
function ST.Suggest(name, bytes)
    local n = name:lower()
    for _, p in ipairs(UNLIKELY) do if n:find(p) then return false end end
    if (bytes or 0) > SUGGEST_MAX then return false end
    for _, p in ipairs(LIKELY) do if n:find(p) then return true end end
    return false
end

function ST.AddonTitle(owner)
    if not owner then return "?" end
    local ok, _, title = pcall(C_AddOns.GetAddOnInfo, owner)
    title = ok and title or owner
    return (title and title ~= "" and title or owner):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function ST.AddonState(owner)
    if not owner then return "unknown" end
    if C_AddOns.IsAddOnLoaded(owner) then return "ready" end
    local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(owner)
    if exists == false then return "missing" end
    local ok, _, _, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, owner)
    if ok and reason == "MISSING" then return "missing" end
    if ok and not loadable then return "disabled" end
    return "ready"
end

---------------------------------------------------------------------------
-- Setups on this machine: the one you made, ones friends sent, and one
-- installed as a file.
---------------------------------------------------------------------------
function ST.Mine() return TwichUIShareDB and TwichUIShareDB.pack end

function ST.Sources()
    local out = {}
    if TwichUI_PackFile and TwichUI_PackFile.pack then
        out[#out + 1] = { key = "file", pack = TwichUI_PackFile.pack, from = TwichUI_PackFile.pack.sourceName or "a file" }
    end
    for sender, pack in pairs(db and db.received or {}) do
        out[#out + 1] = { key = "recv:" .. sender, pack = pack, from = pack.sourceName or Ambiguate(sender, "short") }
    end
    table.sort(out, function(a, b) return (a.pack.created or 0) > (b.pack.created or 0) end)
    return out
end

function ST.SourcePack(key)
    if key == "file" then return TwichUI_PackFile and TwichUI_PackFile.pack end
    local sender = key and key:match("^recv:(.+)$")
    return sender and db.received[sender]
end

---------------------------------------------------------------------------
-- Find settings (you)
---------------------------------------------------------------------------
local known

local function SnapshotGlobals()
    known = {}
    for k in next, _G do known[k] = true end
end

local function ScanNewGlobals(owner)
    local blizzard = owner:find("^Blizzard_") ~= nil
    for k, v in next, _G do
        if not known[k] then
            known[k] = true
            if not blizzard and type(k) == "string" and type(v) == "table"
                and not k:find("^TwichUI") then
                local pure, bytes, huge = Inspect(v)
                if pure and next(v) ~= nil then
                    -- Tables past the size cap are listed but not copied: far too
                    -- big to send, and the copy would sit in memory all session.
                    if not huge then ST.capture[k] = { owner = owner, data = DeepCopy(v) } end
                    db.detected[k] = { owner = owner, bytes = bytes, huge = huge or nil }
                    if huge then db.selection[k] = false
                    elseif db.selection[k] == nil then db.selection[k] = ST.Suggest(k, bytes) end
                end
            end
        end
    end
end

function ST:FindSettings()
    db.scanNext = true
    ReloadUI()
end

-- Grouped for the window: { owner, title, tables = { {name, bytes, selected, huge} }, bytes, selectedCount }
function ST:DetectedByAddon()
    local groups = {}
    for name, e in pairs(db.detected) do
        local g = groups[e.owner]
        if not g then
            g = { owner = e.owner, title = ST.AddonTitle(e.owner), tables = {}, bytes = 0, selected = 0 }
            groups[e.owner] = g
        end
        local sel = db.selection[name] and true or false
        g.tables[#g.tables + 1] = { name = name, bytes = e.bytes or 0, selected = sel, huge = e.huge }
        if sel then g.bytes = g.bytes + (e.bytes or 0); g.selected = g.selected + 1 end
    end
    local list = {}
    for _, g in pairs(groups) do
        table.sort(g.tables, function(a, b) return a.name:lower() < b.name:lower() end)
        list[#list + 1] = g
    end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    return list
end

-- Ticking an addon includes its settings-looking tables (or everything
-- reasonable if none look like settings); unticking removes them all.
function ST:SetAddonSelected(owner, on)
    local any = false
    for name, e in pairs(db.detected) do
        if e.owner == owner then
            local want = on and ST.Suggest(name, e.bytes)
            db.selection[name] = want and true or false
            any = any or want
        end
    end
    if on and not any then
        for name, e in pairs(db.detected) do
            if e.owner == owner and (e.bytes or 0) <= SUGGEST_MAX then db.selection[name] = true end
        end
    end
end

function ST:SetTableSelected(name, on)
    local e = db.detected[name]
    db.selection[name] = (on and not (e and e.huge)) and true or false
end

function ST:SelectSuggested()
    for name, e in pairs(db.detected) do db.selection[name] = ST.Suggest(name, e.bytes) end
end

function ST:CanSave() return ST.capture ~= nil end

local function ActiveEditModeString()
    if not (C_EditMode and C_EditMode.ConvertLayoutInfoToString) then return nil end
    local ok, info = pcall(function()
        return EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo
            and EditModeManagerFrame:GetActiveLayoutInfo()
    end)
    if not ok or not info then return nil end
    local ok2, str = pcall(C_EditMode.ConvertLayoutInfoToString, info)
    if ok2 and type(str) == "string" and #str > 0 then return str, info.layoutName end
end

function ST:SaveMine(includeEditMode)
    if not ST.capture then return 0 end
    local tables, count = {}, 0
    for name, sel in pairs(db.selection) do
        local cap = ST.capture[name]
        if sel and cap then
            tables[name] = { owner = cap.owner, data = cap.data, hash = ST.Hash(cap.data) }
            count = count + 1
        end
    end
    local old = ST.Mine()
    local mine = {
        format = 2,
        created = time(),
        version = ((old and old.version) or 0) + 1,
        source = CharKey(),
        sourceName = (GetUnitName and GetUnitName("player", true)) or UnitName("player"),
        tables = tables,
        addons = ST:BuildAddonList(),
    }
    if includeEditMode then
        mine.editMode, mine.editModeName = ActiveEditModeString()
        mine.editModeHash = mine.editMode and LibDeflate:Adler32(mine.editMode) or nil
    end
    TwichUIShareDB.pack = mine
    return count
end

---------------------------------------------------------------------------
-- Addon list: which addons you have, grouped into "one download" each, with
-- where to get them. Sent along with your configuration so friends get a
-- checklist of what to install.
---------------------------------------------------------------------------
local function Meta(name, field)
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, field)
    if ok and type(v) == "string" and v ~= "" then return v end
end

local function CleanTitle(t)
    return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function FolderExists(folder)
    if C_AddOns.DoesAddOnExist then
        local ok, e = pcall(C_AddOns.DoesAddOnExist, folder)
        if ok then return e end
    end
    local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, folder)
    return ok and reason ~= "MISSING"
end

local function FolderEnabled(folder)
    local ok, state = pcall(C_AddOns.GetAddOnEnableState, folder, UnitGUID("player"))
    if ok and type(state) == "number" then return state > 0 end
    return true
end

-- Returns a sorted list of groups:
-- { key, title, version, curse, wago, wowi, website, folders = {...}, enabled }
function ST.InstalledAddons()
    local info, order = {}, {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, _, _, security = C_AddOns.GetAddOnInfo(i)
        if name and name ~= R.ADDON and not name:find("^Blizzard_") and security ~= "SECURE" then
            local deps = { pcall(C_AddOns.GetAddOnDependencies, i) }
            table.remove(deps, 1)
            info[name] = {
                folder = name, title = CleanTitle(title ~= "" and title or name),
                version = Meta(name, "Version"),
                curse = Meta(name, "X-Curse-Project-ID"), wago = Meta(name, "X-Wago-ID"),
                wowi = Meta(name, "X-WoWI-ID"), website = Meta(name, "X-Website"),
                lod = C_AddOns.IsAddOnLoadOnDemand(i), enabled = FolderEnabled(name), deps = deps,
            }
            order[#order + 1] = name
        end
    end

    -- Folders that ship together become one entry: same project ID, or a
    -- module like "BigWigs_Plugins" that belongs to an installed "BigWigs".
    local function Parent(name, seen)
        local e = info[name]
        seen = seen or {}
        if seen[name] then return name end
        seen[name] = true
        local prefix = name:match("^(.-)[_%-]") 
        if prefix and prefix ~= name and info[prefix] then return Parent(prefix, seen) end
        if e.lod then
            for _, d in ipairs(e.deps) do
                if type(d) == "string" and info[d] and d ~= name then return Parent(d, seen) end
            end
        end
        return name
    end

    local groups, list = {}, {}
    for _, name in ipairs(order) do
        local e = info[name]
        local root = Parent(name)
        local r = info[root]
        local key = (e.curse and "cf:" .. e.curse) or (r.curse and "cf:" .. r.curse)
            or (e.wago and "wago:" .. e.wago) or (r.wago and "wago:" .. r.wago) or root
        local g = groups[key]
        if not g then
            g = { key = key, folders = {}, enabled = false }
            groups[key] = g
            list[#list + 1] = g
        end
        g.folders[#g.folders + 1] = name
        g.enabled = g.enabled or e.enabled
        -- The main folder (the root, or the shortest name) names the entry.
        local main = (name == root) and (not g.main or #name < #g.main)
        if main or not g.title then
            g.main, g.title, g.version = name, e.title, e.version
        end
        g.curse = g.curse or e.curse
        g.wago = g.wago or e.wago
        g.wowi = g.wowi or e.wowi
        g.website = g.website or e.website
    end
    for _, g in ipairs(list) do table.sort(g.folders) end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    return list
end

local function UrlEncode(s)
    return (s:gsub("[^%w%-_%.~ ]", ""):gsub(" ", "%%20"))
end

-- Best place to download an entry, and what to call that place.
function ST.AddonLink(g)
    if g.curse then return "https://www.curseforge.com/projects/" .. g.curse, "CurseForge" end
    if g.wago then return "https://addons.wago.io/addons/" .. g.wago, "Wago" end
    if g.wowi then return "https://www.wowinterface.com/downloads/info" .. g.wowi, "WoWInterface" end
    if g.website and g.website:find("^https?://") then return g.website, "Website" end
    return "https://www.curseforge.com/wow/search?search=" .. UrlEncode(g.title or ""), "Search"
end

-- On the receiving side: installed / off / missing, for a recommended entry.
function ST.AddonInstallState(entry)
    local anyExists, anyOn = false, false
    for _, folder in ipairs(entry.folders or {}) do
        if FolderExists(folder) then
            anyExists = true
            if FolderEnabled(folder) then anyOn = true end
        end
    end
    if anyOn then return "installed" end
    if anyExists then return "off" end
    return "missing"
end

function ST:IsRecommended(g)
    local v = db.recommend[g.key]
    if v == nil then return g.enabled end
    return v
end

function ST:SetRecommended(key, on) db.recommend[key] = on and true or false end

function ST:BuildAddonList()
    local out = {}
    for _, g in ipairs(ST.InstalledAddons()) do
        if ST:IsRecommended(g) then
            out[g.key] = {
                title = g.title, version = g.version, curse = g.curse, wago = g.wago,
                wowi = g.wowi, website = g.website, folders = g.folders,
            }
        end
    end
    return out
end

-- Update just the addon list in your saved configuration (no reload needed).
function ST:UpdateSavedAddonList()
    local mine = ST.Mine()
    if not mine then return false end
    mine.addons = ST:BuildAddonList()
    mine.created = time()
    mine.version = (mine.version or 0) + 1
    return true
end

function ST.SortedRecommended(pack)
    local list = {}
    for key, e in pairs(pack and pack.addons or {}) do
        local item = ST.DeepCopy(e)
        item.key = key
        item.state = ST.AddonInstallState(item)
        list[#list + 1] = item
    end
    local rank = { missing = 1, off = 2, installed = 3 }
    table.sort(list, function(a, b)
        if rank[a.state] ~= rank[b.state] then return rank[a.state] < rank[b.state] end
        return (a.title or ""):lower() < (b.title or ""):lower()
    end)
    return list
end

function ST.CountAddons(pack)
    local owners, n = {}, 0
    for _, e in pairs(pack and pack.tables or {}) do
        if e.owner and not owners[e.owner] then owners[e.owner] = true; n = n + 1 end
    end
    return n
end

function ST.PackBytes(pack)
    local total = 0
    for _, e in pairs(pack and pack.tables or {}) do
        local _, b = Inspect(e.data or {})
        total = total + b
    end
    return total
end

---------------------------------------------------------------------------
-- Apply / use on alt / undo (queued for the next load)
---------------------------------------------------------------------------
local pending, results

local function PointProfiles(t, packData, source, me)
    if type(t) ~= "table" or type(packData) ~= "table" then return end
    if type(t.profileKeys) == "table" and type(t.profiles) == "table" then
        local pk = type(packData.profileKeys) == "table" and packData.profileKeys or {}
        local prof = pk[source]
        if not (prof and t.profiles[prof]) and t.profiles.Default then prof = "Default" end
        if prof and t.profiles[prof] then t.profileKeys[me] = prof end
    end
    if type(t.namespaces) == "table" and type(packData.namespaces) == "table" then
        for ns, sub in pairs(t.namespaces) do PointProfiles(sub, packData.namespaces[ns], source, me) end
    end
end

local function Replace(name, newData)
    local cur = rawget(_G, name)
    if newData == nil then
        _G[name] = nil
    elseif type(cur) == "table" then
        wipe(cur)
        for k, v in pairs(DeepCopy(newData)) do cur[k] = v end
    else
        _G[name] = DeepCopy(newData)
    end
end

local function Backup(name, stamp)
    local me = CharKey()
    TwichUIBackupDB[me] = TwichUIBackupDB[me] or {}
    local b = TwichUIBackupDB[me]
    if b.stamp ~= stamp then b.stamp = stamp; b.created = time(); b.tables = {} end
    if b.tables[name] == nil then
        local cur = rawget(_G, name)
        b.tables[name] = { present = cur ~= nil, data = type(cur) == "table" and DeepCopy(cur) or cur }
    end
end

local function PendingPack() return pending and ST.SourcePack(pending.source) end

local function OwnerOf(name)
    local pack = PendingPack()
    local o = pack and pack.tables[name] and pack.tables[name].owner
    if o then return o end
    local b = TwichUIBackupDB[CharKey()]
    return b and b.owners and b.owners[name]
end

-- A setup only ever replaces addon settings tables. Names come from whoever
-- made the setup, so never touch TwichUI's own data or a global that isn't
-- a table (a function, say).
function ST.SafeName(name)
    if type(name) ~= "string" or name:find("^TwichUI") then return false end
    local cur = rawget(_G, name)
    return cur == nil or type(cur) == "table"
end

local function Skip(name)
    results.skipped[#results.skipped + 1] = name
    pending.tables[name] = nil
end

local function ApplyOne(name)
    local mode = pending.mode
    if mode == "undo" then
        local b = TwichUIBackupDB[CharKey()]
        local e = b and b.tables and b.tables[name]
        if e then Replace(name, e.present and e.data or nil) end
    else
        local pack = PendingPack()
        local entry = pack and pack.tables[name]
        if not entry then pending.tables[name] = nil return end
        if not ST.SafeName(name) then Skip(name) return end
        if mode == "apply" then
            Backup(name, pending.stamp)
            Replace(name, entry.data)
        end
        PointProfiles(rawget(_G, name), entry.data, pack.source, CharKey())
    end
    results.done[#results.done + 1] = name
    pending.tables[name] = nil
end

local function ProcessOwner(owner)
    if not pending then return end
    for name in pairs(pending.tables) do
        if OwnerOf(name) == owner then ApplyOne(name) end
    end
    -- Load-on-demand addons get here after login; finish up once they're all in.
    if pending.announced and next(pending.tables) == nil then
        db.pending = nil
        pending = nil
    end
end

-- mode: "apply" | "alt" | "undo"; names: settings tables; sourceKey: which setup
function ST:Queue(mode, names, sourceKey)
    local t = {}
    for _, n in ipairs(names) do t[n] = true end
    local pack = ST.SourcePack(sourceKey)
    db.pending = { mode = mode, tables = t, source = sourceKey, stamp = pack and pack.created or 0, char = CharKey() }
    if mode == "apply" and pack then
        local me = CharKey()
        TwichUIBackupDB[me] = TwichUIBackupDB[me] or {}
        local owners = TwichUIBackupDB[me].owners or {}
        for _, n in ipairs(names) do owners[n] = pack.tables[n] and pack.tables[n].owner end
        TwichUIBackupDB[me].owners = owners
    end
    ReloadUI()
end

function ST:HasBackup()
    local b = TwichUIBackupDB and TwichUIBackupDB[CharKey()]
    return b and b.tables and next(b.tables) ~= nil
end

function ST:BackupNames()
    local b = TwichUIBackupDB[CharKey()]
    local out = {}
    if b and b.tables then for n in pairs(b.tables) do out[#out + 1] = n end end
    return out
end

-- For the window: a setup grouped by addon, with install state.
function ST.PackByAddon(pack)
    local groups = {}
    for name, e in pairs(pack and pack.tables or {}) do
        local g = groups[e.owner or "?"]
        if not g then
            g = { owner = e.owner, title = ST.AddonTitle(e.owner), state = ST.AddonState(e.owner), tables = {} }
            groups[e.owner or "?"] = g
        end
        g.tables[#g.tables + 1] = name
    end
    local list = {}
    for _, g in pairs(groups) do table.sort(g.tables); list[#list + 1] = g end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    return list
end

-- What applying one addon's settings (a PackByAddon group) would do here:
-- "replace" the settings you have, add "new" ones (the addon is loaded and
-- has none yet), or nothing yet because it's "missing" or "disabled".
-- An addon that hasn't loaded can't be checked, so it counts as "replace".
function ST.ApplyEffect(g)
    if g.state == "missing" or g.state == "disabled" then return g.state end
    if not (g.owner and C_AddOns.IsAddOnLoaded(g.owner)) then return "replace" end
    for _, name in ipairs(g.tables) do
        local cur = rawget(_G, name)
        if type(cur) == "table" and next(cur) ~= nil then return "replace" end
    end
    return "new"
end

function ST:RemoveReceived(sender)
    if db.received then db.received[sender] = nil end
end

---------------------------------------------------------------------------
-- Stored data: everything TwichUI keeps between sessions, with sizes, so it
-- can be cleaned up. The game loads all saved data at every login.
---------------------------------------------------------------------------
function ST.SizeOf(t)
    if type(t) ~= "table" then return 0 end
    local _, b = Inspect(t)
    return b
end

function ST:DeleteMine() TwichUIShareDB.pack = nil end

function ST:DeleteBackup(charKey) TwichUIBackupDB[charKey] = nil end

function ST:ClearSearch()
    wipe(db.detected)
    wipe(db.selection)
    ST.capture = nil
end

-- { key, kind, label, detail, bytes, remove = fn }
function ST.StorageItems()
    local items = {}
    local mine = ST.Mine()
    if mine then
        items[#items + 1] = {
            key = "mine", kind = "Your configuration",
            label = "Your saved configuration",
            detail = ("version %d, %d addons with settings"):format(mine.version or 1, ST.CountAddons(mine)),
            bytes = ST.SizeOf(mine), remove = function() ST:DeleteMine() end,
            warn = "Friends keep the copy they already have. You can save a new one any time.",
        }
    end
    for sender, pack in pairs(db.received or {}) do
        items[#items + 1] = {
            key = "recv:" .. sender, kind = "Shared with you",
            label = ("From %s"):format(pack.sourceName or sender),
            detail = ("version %d, received %s"):format(pack.version or 1, date("%b %d", pack.received or pack.created or 0)),
            bytes = ST.SizeOf(pack), remove = function() ST:RemoveReceived(sender) end,
            warn = "Settings you already applied stay. They can send it again if you want it back.",
        }
    end
    for charKey, b in pairs(TwichUIBackupDB or {}) do
        if type(b) == "table" and b.tables and next(b.tables) then
            items[#items + 1] = {
                key = "backup:" .. charKey, kind = "Undo backup",
                label = ("Undo backup for %s"):format(charKey),
                detail = ("from %s"):format(date("%b %d", b.created or 0)),
                bytes = ST.SizeOf(b), remove = function() ST:DeleteBackup(charKey) end,
                warn = "Without it, Undo can't restore that character's earlier settings.",
            }
        end
    end
    if next(db.detected or {}) then
        items[#items + 1] = {
            key = "search", kind = "Settings search",
            label = "Last \"Find my addon settings\" results",
            detail = "the list of addons and what you ticked",
            bytes = ST.SizeOf(db.detected) + ST.SizeOf(db.selection),
            remove = function() ST:ClearSearch() end,
            warn = "Your saved configuration isn't affected. Search again next time you want to change it.",
        }
    end
    table.sort(items, function(a, b) return a.bytes > b.bytes end)
    return items
end

---------------------------------------------------------------------------
-- Load-time work
---------------------------------------------------------------------------
R:OnInit(function()
    TwichUIDB.setup = TwichUIDB.setup or {}
    db = TwichUIDB.setup
    db.detected = db.detected or {}
    db.selection = db.selection or {}
    db.received = db.received or {}
    db.trusted = db.trusted or {}
    db.recommend = db.recommend or {}
    ST.db = db

    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name ~= R.ADDON and C_AddOns.IsAddOnLoaded(i) then ST.loadedBefore[name] = true end
    end

    if not R:Enabled("setupSharing") then db.scanNext = nil; return end

    if db.scanNext then
        db.scanNext = nil
        wipe(db.detected)
        db.lastScan = time()
        SnapshotGlobals()
        ST.capture = {}
    end

    local p = db.pending
    if p and p.char == CharKey() then
        pending = p
        results = { mode = p.mode, done = {}, skipped = {}, late = {} }
        for name in pairs(p.tables) do
            local owner = OwnerOf(name)
            if owner and ST.loadedBefore[owner] then
                ApplyOne(name)
                results.late[#results.late + 1] = name
            elseif p.mode ~= "undo" and rawget(_G, name) ~= nil then
                -- Its addon hasn't loaded yet, so a global that already exists
                -- isn't that addon's saved settings. Leave it alone.
                Skip(name)
            end
        end
    end
end)

R:On("ADDON_LOADED", function(name)
    if name == R.ADDON or not db then return end
    if known then ScanNewGlobals(name) end
    if pending then ProcessOwner(name) end
end)

R:On("PLAYER_LOGIN", function()
    if not db then return end
    if known then
        known = nil
        local groups = ST:DetectedByAddon()
        R.Print("found settings for %d addons. Pick what to share in the window.", #groups)
        if not db.restoreNext then
            C_Timer.After(1, function() if R.Window then R.Window:Show("share") end end)
        end
    end
    if pending then
        for name in pairs(pending.tables) do
            local owner = OwnerOf(name)
            local lod = owner and C_AddOns.IsAddOnLoadOnDemand(owner)
            if not (lod and ST.AddonState(owner) ~= "missing") then
                results.skipped[#results.skipped + 1] = name
                pending.tables[name] = nil
            end
        end
        local finished = next(pending.tables) == nil
        if finished then db.pending = nil end
        ST.report = results
        -- Say it once. What's left waits for a load-on-demand addon and is
        -- applied when it loads (this session or a later one).
        if not pending.announced then
            pending.announced = true
            local n = #results.done
            if results.mode == "undo" then
                R.Print("restored your previous settings (%d).", n)
            elseif results.mode == "alt" then
                R.Print("this character now uses the shared addon configuration (%d).", n)
            else
                R.Print("addon configuration applied (%d settings). Undo is in /tui share if you change your mind.", n)
            end
            if #results.skipped > 0 then
                R.Print("skipped %d: the addon isn't installed or enabled, or it isn't a settings table.", #results.skipped)
            end
            if #results.late > 0 then
                R.Print("some addons load before TwichUI; /reload once more to be sure they picked it up.")
            end
        end
        if finished then pending = nil end
    end
end)
