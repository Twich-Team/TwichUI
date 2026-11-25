-- Forever's public search data, copied into bounded, secret-free display records.
local R = TwichUI
R.GroupFinder = R.GroupFinder or {}
local D = {}
R.GroupFinder.Data = D
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local FLAGS = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
D.MAX_RESULTS = 500

function D.Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end
function D.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return D.Plain(value) end
end
local function Number(value, low, high)
    value = D.Plain(value)
    if type(value) == "number" and value == value and value >= (low or 0) and value <= (high or 1000000000) then return value end
end
local function Text(value, length)
    value = D.Plain(value)
    -- Keep bounded plain data here; the window owns escaping game text markup.
    if type(value) == "string" and value ~= "" then return value:sub(1, length or 256) end
end
local function Table(value)
    value = D.Plain(value)
    if type(value) == "table" then return value end
end
local function API(name, ...)
    return D.Call(C_LFGList and C_LFGList[name], ...)
end
local function IDs(values, limit)
    local result, seen = {}, {}
    values = Table(values)
    if values then
        for i = 1, limit or D.MAX_RESULTS do
            local raw = D.Plain(values[i])
            if raw == nil then break end
            local id = Number(raw, 1)
            if id and id % 1 == 0 and not seen[id] then result[#result + 1], seen[id] = id, true end
        end
    end
    return result
end

-- Scholomance's instance/map id is verified in map/Data.lua (Forever 1.60.1.70450).
-- BRD is absent from that verified map inventory; use its public English activity
-- name rather than guessing an activity or map id. Other/localized dungeons use
-- the existing painted entrance, so new Forever activities never lose their art.
function D.ActivityIcon(info, small)
    info = Table(info) or {}
    local name = Text(info.fullName) or Text(info.shortName)
    local art
    if Number(info.mapID) == 289 or name == "Scholomance" then art = "scholomance"
    elseif name == "Blackrock Depths" then art = "blackrock-depths" end
    if art then return R.PATH .. [[media\groupfinder\]] .. art .. (small and "-small" or "") end
    return R.PATH .. [[media\reminders\gallery\reminder-dungeon-entrance]] .. (small and "-small" or "")
end

-- Do not use the native suggested-level filter: activity and character levels are separate controls.
function D.Activities()
    local result, seen = {}, {}
    for _, categoryID in ipairs(IDs(API("GetAvailableCategories"), 100)) do
        for _, id in ipairs(IDs(API("GetAvailableActivities", categoryID), 1000)) do
            local info = Table(API("GetActivityInfoTable", id))
            if info and Number(info.maxNumPlayers) == 5 and D.Plain(info.useDungeonRoleExpectations) == true and not seen[id] then
                local name = Text(info.fullName) or Text(info.shortName)
                if name then
                    result[#result + 1] = { id = id, name = name, categoryID = categoryID,
                        minLevel = Number(info.minLevelSuggestion, 1, 1000), maxLevel = Number(info.maxLevelSuggestion, 1, 1000),
                        mapID = Number(info.mapID), icon = D.ActivityIcon(info), iconSmall = D.ActivityIcon(info, true) }
                    seen[id] = true
                end
            end
        end
    end
    table.sort(result, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
    return result
end

local function Member(info)
    info = Table(info)
    if not info then return nil end
    local role = Text(info.assignedRole, 16)
    if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then role = nil end
    local roles, flags = {}, Table(info.lfgRoles)
    for _, r in ipairs(ROLES) do roles[r] = flags and D.Plain(flags[FLAGS[r]]) == true or false end
    return { name = Text(info.name, 80), level = Number(info.level, 1, 1000), zone = Text(info.areaName),
        class = Text(info.classFilename, 24), className = Text(info.className, 64), role = role,
        roles = roles, specName = Text(info.specName, 80), isLeader = D.Plain(info.isLeader) == true }
end

function D.Read(id)
    id = Number(id, 1)
    if not id or id % 1 ~= 0 then return nil end
    local info = Table(API("GetSearchResultInfo", id))
    if not info or D.Plain(info.isDelisted) == true then return nil end
    local count = Number(info.numMembers, 1, 5)
    if not count or count % 1 ~= 0 then return nil end
    local activities, names, icon = {}, {}, nil
    for _, activityID in ipairs(IDs(info.activityIDs, 50)) do
        local activity = Table(API("GetActivityInfoTable", activityID))
        if activity and Number(activity.maxNumPlayers) == 5 and D.Plain(activity.useDungeonRoleExpectations) == true then
            activities[#activities + 1] = activityID
            names[#names + 1] = Text(activity.fullName) or Text(activity.shortName) or "Unknown dungeon"
            icon = icon or D.ActivityIcon(activity)
        end
    end
    if #activities == 0 then return nil end
    local roster = {}
    for i = 1, count do
        local member = Member(API("GetSearchResultPlayerInfo", id, i))
        if member then roster[#roster + 1] = member end
    end
    local leader = Member(API("GetSearchResultLeaderInfo", id))
    if not leader then
        for _, member in ipairs(roster) do if member.isLeader then leader = member break end end
    end
    if count == 1 then leader = leader or roster[1] end
    leader = leader or {}
    local leaderName = Text(info.leaderName, 80) or leader.name
    local guid = Text(info.partyGUID, 128)
    local openings, counts = {}, Table(API("GetSearchResultMemberCounts", id))
    for _, role in ipairs(ROLES) do openings[role] = counts and Number(counts[role .. "_REMAINING"], 0, 5) or nil end
    local zone = R.QoLGroupFinderZones and R.QoLGroupFinderZones.LeaderZone(id) or leader.zone
    zone = Text(zone)
    local friends = (Number(info.numBNetFriends, 0, 100) or 0) + (Number(info.numCharFriends, 0, 100) or 0)
    local class = leader.class
    if count == 1 and class and class:match("^[A-Z]+$") then icon = "Interface\\Icons\\ClassIcon_" .. class end
    return { id = id, identity = guid and leaderName and guid .. ":" .. leaderName or nil,
        partyGUID = guid, leader = leaderName, level = leader.level, zone = zone, solo = count == 1, numMembers = count,
        activities = activities, activityNames = names, activityName = names[1], icon = icon,
        roles = leader.roles or {}, openings = openings, roster = roster, class = class, className = leader.className,
        style = "UNKNOWN", specName = leader.specName, age = Number(info.age), readAt = Number(D.Call(GetTime)), hasSelf = D.Plain(info.hasSelf) == true,
        isDelisted = false, actionable = D.Plain(info.isDelisted) == false and D.Plain(info.hasSelf) == false and leaderName ~= nil and guid ~= nil,
        friendCount = friends, guildCount = Number(info.numGuildMates, 0, 100) or 0,
        playstyle = Number(info.generalPlaystyle, 0, 100), newPlayerFriendly = D.Plain(info.newPlayerFriendly) == true }
end

function D.Results()
    local fn = C_LFGList and C_LFGList.GetSearchResults
    if type(fn) ~= "function" then return nil, "Search results are unavailable." end
    local ok, _, values = pcall(fn)
    if not ok or not Table(values) then return nil, "Search results could not be read." end
    local result = {}
    for _, id in ipairs(IDs(values)) do
        local row = D.Read(id)
        if row then result[#result + 1] = row end
    end
    return result
end

function D.Party()
    local groupedValue, raidValue, combatValue = D.Call(IsInGroup), D.Call(IsInRaid), D.Call(InCombatLockdown)
    local grouped = groupedValue == true
    local raid = raidValue == true
    local count = grouped and Number(D.Call(GetNumGroupMembers), 1, 40) or 1
    local authority = not grouped or D.Call(UnitIsGroupLeader, "player") == true or D.Call(UnitIsGroupAssistant, "player") == true
    local canInvite = (groupedValue == true or groupedValue == false) and raidValue == false and combatValue == false
        and count ~= nil and count < 5 and authority
    local party = { known = false, count = count, openings = {}, canInvite = canInvite }
    if (groupedValue ~= true and groupedValue ~= false) or (raidValue ~= true and raidValue ~= false) then
        party.count = nil
        party.reason = "Party composition is unavailable. Manual role filters remain usable."
        return party
    end
    if raid or not count or count > 5 then party.reason = "Party roles unavailable outside a five-player party." return party end
    local filled = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for i = 1, count do
        local unit = i == 1 and "player" or "party" .. (i - 1)
        local role = D.Plain(D.Call(UnitGroupRolesAssigned, unit))
        if type(role) ~= "string" or filled[role] == nil then
            party.reason = "Assign a role to every party member to fill missing roles."
            return party
        end
        filled[role] = filled[role] + 1
    end
    if filled.TANK > 1 or filled.HEALER > 1 or filled.DAMAGER > 3 then
        party.reason = "Party roles do not match a five-player dungeon composition."
        return party
    end
    party.known = true
    party.openings = { TANK = 1 - filled.TANK, HEALER = 1 - filled.HEALER, DAMAGER = 3 - filled.DAMAGER }
    return party
end
