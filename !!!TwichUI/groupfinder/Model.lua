-- Local display filters and feature-owned settings. Never issues a server search.
local R = TwichUI
R.GroupFinder = R.GroupFinder or {}
local M = {}
R.GroupFinder.Model = M
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local CLASSES = { WARRIOR=true, PALADIN=true, HUNTER=true, ROGUE=true, PRIEST=true, SHAMAN=true, MAGE=true, WARLOCK=true, DRUID=true }
local function Mode(mode) return (mode == "players" or mode == "recruits") and "players" or "groups" end
M.Mode = Mode
function M.Defaults()
    return { activities = {}, activitiesNone = false, roles = {}, classes = {}, needsRole = false, friendsOnly = false, guildOnly = false,
        search = "", sort = "default" }
end
local function Copy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 4 then return nil end
    local result = {}
    for key, item in pairs(value) do
        if type(key) == "string" or type(key) == "number" then result[key] = Copy(item, (depth or 0) + 1) end
    end
    return result
end
local function Sanitize(input)
    local f = M.Defaults()
    if type(input) ~= "table" then return f end
    for _, key in ipairs({ "activities", "roles", "classes" }) do
        if type(input[key]) == "table" then
            local n = 0
            for id, on in pairs(input[key]) do
                local valid = key == "activities" and type(id) == "number" and id >= 1 and id % 1 == 0
                    or key == "roles" and (id == "TANK" or id == "HEALER" or id == "DAMAGER")
                    or key == "classes" and CLASSES[id] == true
                if valid and on == true and n < 1000 then f[key][id] = true; n = n + 1 end
            end
        end
    end
    for _, key in ipairs({ "activitiesNone", "needsRole", "friendsOnly", "guildOnly" }) do f[key] = input[key] == true end
    if input.needsMyRole == true or input.fillMissingRoles == true then f.needsRole = true end
    if input.social == "friends" then f.friendsOnly = true elseif input.social == "guild" then f.guildOnly = true end
    if type(input.search) == "string" then f.search = input.search:sub(1, 128) end
    if input.sort == "newest" or input.sort == "activity" then f.sort = input.sort end
    for _, key in ipairs({ "minLevel", "maxLevel", "maxAge", "playstyle" }) do
        local v = input[key]
        if type(v) == "number" and v == v and v >= 0 and v <= 1000000 then f[key] = v end
    end
    return f
end
M.Sanitize = Sanitize
function M.Settings()
    if type(TwichUIDB) ~= "table" then return nil end
    if type(TwichUIDB.groupFinder) ~= "table" then TwichUIDB.groupFinder = {} end
    local db = TwichUIDB.groupFinder
    for _, mode in ipairs({ "groups", "players" }) do
        if type(db[mode]) ~= "table" then db[mode] = M.Defaults() end
    end
    if type(db.presets) ~= "table" then db.presets = {} end
    for _, mode in ipairs({ "groups", "players" }) do if type(db.presets[mode]) ~= "table" then db.presets[mode] = {} end end
    db.mode = Mode(db.mode)
    return db
end
function M.Get(mode)
    local db = M.Settings()
    return db and Sanitize(db[Mode(mode)]) or M.Defaults()
end
function M.Set(mode, key, value)
    local db = M.Settings()
    if not db then return end
    mode = Mode(mode)
    if type(key) == "table" then db[mode] = Sanitize(key)
    else local filters = M.Get(mode); filters[key] = Copy(value); db[mode] = Sanitize(filters) end
    return db[mode]
end
function M.GetPresets(mode)
    local db = M.Settings()
    local result = {}
    if db then
        for name, preset in pairs(db.presets[Mode(mode)]) do
            if type(name) == "string" and #name >= 1 and #name <= 48 and not name:find("[|%c]") and type(preset) == "table" then
                result[name] = Sanitize(preset)
            end
        end
    end
    return result
end
function M.SavePreset(mode, name, filters)
    if type(name) ~= "string" then return false, "Enter a preset name." end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 48 or name:find("[|%c]") then return false, "Use a name of 1–48 characters without formatting." end
    local db = M.Settings()
    if not db then return false, "Settings are unavailable." end
    local presets, count = db.presets[Mode(mode)], 0
    for _ in pairs(presets) do count = count + 1 end
    if presets[name] == nil and count >= 24 then return false, "Remove a preset before saving another (24 maximum)." end
    presets[name] = Sanitize(filters or M.Get(mode))
    return true
end
function M.LoadPreset(mode, name, activities)
    local preset = M.GetPresets(mode)[name]
    if type(preset) ~= "table" then return nil, "Preset unavailable." end
    local filters = Sanitize(preset)
    -- Keep saved IDs so temporarily unavailable activities return on the next client session.
    -- A missing ID alone must not hide every current result.
    if type(activities) == "table" then
        local available, selected = {}, {}
        for _, activity in ipairs(activities) do available[activity.id] = true end
        for id in pairs(filters.activities) do if available[id] then selected[id] = true end end
        filters.activities = selected
    end
    M.Set(mode, filters)
    return filters
end
function M.DeletePreset(mode, name)
    local db = M.Settings()
    if not db or db.presets[Mode(mode)][name] == nil then return false end
    db.presets[Mode(mode)][name] = nil
    return true
end
M.RemovePreset = M.DeletePreset

local function Any(set) return type(set) == "table" and next(set) ~= nil end
function M.EffectiveAge(row)
    if not row.age then return nil end
    return row.age + (row.readAt and GetTime and math.max(0, GetTime() - row.readAt) or 0)
end
local function SelectedRole(row, selected, openings)
    for _, role in ipairs(ROLES) do
        if (not Any(selected) or selected[role]) and (openings and (row[role] or 0) > 0 or not openings and row[role]) then return true end
    end
    return false
end
function M.Matches(row, filters, mode, party)
    local f = filters or M.Defaults()
    mode = Mode(mode)
    if f.activitiesNone then return false end
    if row.isDelisted or row.hasSelf or row.solo ~= (mode == "players") then return false end
    if Any(f.activities) then
        local found = false
        for _, id in ipairs(row.activities or {}) do if f.activities[id] then found = true break end end
        if not found then return false end
    end
    if Any(f.roles) and not SelectedRole(mode == "players" and row.roles or row.openings, f.roles, mode == "groups") then return false end
    if f.needsRole or f.needsMyRole or f.fillMissingRoles then
        if mode == "players" then
            -- Unknown party composition leaves manual filters useful.
            if party and party.known then
                local match = false
                for _, role in ipairs(ROLES) do if row.roles[role] and (party.openings[role] or 0) > 0 then match = true break end end
                if not match then return false end
            end
        elseif not SelectedRole(row.openings, f.roles, true) then return false end
    end
    if mode == "players" then
        if Any(f.classes) and not f.classes[row.class] then return false end
        if f.minLevel and (not row.level or row.level < f.minLevel) then return false end
        if f.maxLevel and (not row.level or row.level > f.maxLevel) then return false end
    end
    if f.maxAge then
        local age = M.EffectiveAge(row)
        if not age or age > f.maxAge then return false end
    end
    if (f.friendsOnly or f.social == "friends") and (row.friendCount or 0) == 0 then return false end
    if (f.guildOnly or f.social == "guild") and (row.guildCount or 0) == 0 then return false end
    if f.playstyle and row.playstyle ~= f.playstyle then return false end
    local search = type(f.search) == "string" and f.search:lower() or ""
    if search ~= "" then
        local text = (row.leader or "") .. " " .. (row.activityName or "") .. " " .. table.concat(row.activityNames or {}, " ")
        if not text:lower():find(search, 1, true) then return false end
    end
    return true
end
function M.Sort(rows, sort)
    table.sort(rows, function(a, b)
        if sort == "newest" and a.age ~= b.age then return (a.age or math.huge) < (b.age or math.huge) end
        if sort == "activity" and (a.activityName or "") ~= (b.activityName or "") then return (a.activityName or "") < (b.activityName or "") end
        if sort == "default" or sort == nil then
            local an = R.QoLGroupFinderZones and R.QoLGroupFinderZones.Nearby(a.zone) or false
            local bn = R.QoLGroupFinderZones and R.QoLGroupFinderZones.Nearby(b.zone) or false
            if an ~= bn then return an end
        end
        local aName, bName = a.leader or "", b.leader or ""
        if aName ~= bName then return aName < bName end
        return a.id < b.id
    end)
    return rows
end
function M.Filter(rows, filters, mode, party)
    local result = {}
    for _, row in ipairs(rows or {}) do if M.Matches(row, filters, mode, party) then result[#result + 1] = row end end
    return M.Sort(result, filters and filters.sort)
end
