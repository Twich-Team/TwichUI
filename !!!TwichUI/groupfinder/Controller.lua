-- Owns the browser's session, never the native listing editor or Who view.
-- Search is called only by Refresh's click/key path. Events and the age ticker
-- read public results; neither can initiate a server search or contact a player.
local R = TwichUI
local GF = R.GroupFinder
local D, M = GF.Data, GF.Model
GF.mode, GF.rows, GF.snapshot, GF.state = "groups", {}, {}, "idle"
GF.contacted = {}
local contactOrder = {}
local pending, dispatching, hooked, ticker, query, revision = false, false, false, nil, nil, 0
local MAX_RESULTS, STALE_AFTER, TIMEOUT = 500, 120, 30
local activityCache
local function Now() return GetTime() end
local function Shown() return GF.Window and GF.Window.IsShown() end
local function Render() if Shown() then R.Perf.Call("groupFinder.render", GF.Window.Render) end end
local function Copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end
local function WhisperAPI()
    return ChatFrameUtil and ChatFrameUtil.SendTell or ChatFrame_SendTell
end
local function Refilter()
    GF.party = D.Party()
    GF.availableCount = 0
    for _, row in ipairs(GF.snapshot) do
        if row.solo == (GF.mode == "players") and not row.hasSelf then GF.availableCount = GF.availableCount + 1 end
    end
    GF.rows = M.Filter(GF.snapshot, GF.filters, GF.mode, GF.party)
    local previous, selected = GF.selected, nil
    for _, row in ipairs(GF.rows) do
        row.contacted = row.identity and GF.contacted[row.identity] or nil
        if previous and row.id == previous.id and row.identity == previous.identity then selected = row end
    end
    GF.selected = selected or GF.rows[1]
    Render()
end
GF.Refilter = function() R.Perf.Call("groupFinder.filter", Refilter) end

local function Invalidate(message)
    revision = revision + 1
    pending, query = false, nil
    GF.state, GF.message = "stale", message or "Search results changed elsewhere. Refresh to use this browser."
    Render()
end

-- C_LFGList has one shared result set and no request token. Observing every
-- Search prevents claiming another addon's query as ours. It cannot identify a
-- server completion racing an unrelated query: invalidate instead of guessing.
local function AttachSearch()
    if hooked or not (C_LFGList and type(C_LFGList.Search) == "function") then return end
    hooked = true
    hooksecurefunc(C_LFGList, "Search", function()
        if not dispatching and (query or pending) then Invalidate() end
    end)
end

function GF.GetActivities()
    if not activityCache then activityCache = D.Activities() end
    return activityCache
end
function GF.GetPresets()
    local names = {}
    for name in pairs(M.GetPresets(GF.mode)) do names[#names + 1] = name end
    table.sort(names)
    return names
end
function GF.SetMode(mode)
    mode = mode == "players" and "players" or "groups"
    GF.mode, GF.filters, GF.selected = mode, M.Get(mode), nil
    M.Settings().mode = mode
    GF.Refilter()
end
function GF.ChangeFilter(key, value)
    GF.filters = M.Set(GF.mode, key, value)
    if key == "activities" then GF.message = "Dungeon selection changed. Click Refresh to search these dungeons." end
    GF.Refilter()
end
function GF.Select(id)
    for _, row in ipairs(GF.rows) do if row.id == id then GF.selected = row; Render(); return end end
end
function GF.SavePreset(name)
    local ok, reason = M.SavePreset(GF.mode, name, GF.filters)
    GF.message = ok and "Preset saved." or reason
    Render()
    return ok, reason
end
function GF.LoadPreset(name)
    local filters, reason = M.LoadPreset(GF.mode, name, GF.GetActivities())
    if not filters then GF.message = reason; Render(); return false end
    GF.filters, GF.message = filters, "Preset loaded. Refresh to search its dungeons."
    GF.Refilter()
    return true
end
function GF.DeletePreset(name)
    local ok = M.DeletePreset(GF.mode, name)
    GF.message = ok and "Preset removed." or "Preset unavailable."
    Render()
    return ok
end

function GF.Refresh()
    if not Shown() or pending then return false end
    if InCombatLockdown and InCombatLockdown() then GF.message = "Refresh after combat."; Render(); return false end
    AttachSearch()
    if not hooked then GF.message = "The Group Finder search API is unavailable."; Render(); return false end
    activityCache = nil
    local activities, category, selected = GF.GetActivities(), nil, {}
    local filters = GF.filters.activities or {}
    local hasSelection = next(filters) ~= nil
    for _, activity in ipairs(activities) do
        if (not hasSelection or filters[activity.id]) and (not category or category == activity.categoryID) then
            category = category or activity.categoryID
            selected[#selected + 1] = activity.id
        end
    end
    if not category or #selected == 0 then
        GF.message = "No selected dungeons are available. Choose dungeons and try again."
        Render(); return false
    end
    revision = revision + 1
    query = { revision = revision, activities = Copy(selected), categoryID = category, started = Now() }
    pending, GF.state, GF.message = true, "searching", nil
    dispatching = true
    local ok = pcall(C_LFGList.Search, category, 0, 0, nil, false, nil, selected)
    dispatching = false
    if not ok then
        pending, query = false, nil
        GF.state, GF.message = "failed", "Search could not start. Click Refresh to try again."
    end
    Render()
    return ok
end

local function ResultsReceived()
    if not pending or not query then
        if Shown() and GF.state == "ready" then Invalidate() end
        return
    end
    local results = D.Results()
    if not results then
        pending, query = false, nil
        GF.state, GF.message = "failed", "Search results are unavailable. Showing the last successful results."
        Render(); return
    end
    GF.snapshot = {}
    for i = 1, math.min(#results, MAX_RESULTS) do GF.snapshot[i] = results[i] end
    pending = false
    GF.lastSuccess, GF.state, GF.message = Now(), "ready", nil
    GF.Refilter()
end
local function SearchFailed()
    if not pending then return end
    pending, query = false, nil
    GF.state, GF.message = "failed", "Search failed. Showing the last successful results. Click Refresh to retry."
    Render()
end
local function ResultUpdated(id)
    id = D.Plain(id)
    if not query or pending or type(id) ~= "number" or GF.state ~= "ready" then return end
    for i, old in ipairs(GF.snapshot) do
        if old.id == id then
            local current = D.Read(id)
            if current and current.identity == old.identity then GF.snapshot[i] = current
            else table.remove(GF.snapshot, i) end
            GF.Refilter(); return
        end
    end
    -- New results can arrive individually after a successful search. Re-read
    -- the bounded shared set only while we still own that search.
    local results = D.Results()
    if not results then Invalidate("Search results are unavailable. Refresh to try again."); return end
    GF.snapshot = {}
    for i = 1, math.min(#results, MAX_RESULTS) do GF.snapshot[i] = results[i] end
    GF.Refilter()
end

function GF.CanContact(kind, row)
    row = row or GF.selected
    if pending or not query or GF.state ~= "ready" or not row or not row.identity then return false end
    if GF.lastSuccess and Now() - GF.lastSuccess > STALE_AFTER then return false end
    local live = D.Read(row.id)
    if not live or not live.identity or live.identity ~= row.identity or live.leader ~= row.leader or live.hasSelf or live.actionable ~= true then return false end
    if not live.leader or live.leader:find("[|%c%s]") then return false end
    if kind == "invite" then
        local party = D.Party()
        local allowed = GF.mode == "players" and live.solo and party.canInvite == true
            and C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" or false
        return allowed, allowed and live or nil
    end
    local allowed = type(WhisperAPI()) == "function"
    return allowed, allowed and live or nil
end
function GF.Contact(kind)
    if kind ~= "invite" and kind ~= "whisper" then return false end
    local allowed, row = GF.CanContact(kind)
    if not allowed then
        GF.message = "This listing is no longer actionable. Refresh and select it again."
        Render(); return false
    end
    local ok
    if kind == "invite" then ok = pcall(C_PartyInfo.InviteUnit, row.leader)
    else ok = pcall(WhisperAPI(), row.leader) end
    if ok then
        -- The marker records intentional contact, never delivery/acceptance.
        -- Opening an empty whisper alone is not a sent message.
        if kind == "invite" then GF.MarkContact(row.identity, "Invited") end
        GF.message = kind == "invite" and "Invitation requested." or "Whisper opened."
    else GF.message = "The game could not complete that action." end
    GF.Refilter()
    return ok
end

local function Tick()
    if not Shown() then return end
    if pending and query and Now() - query.started >= TIMEOUT then
        SearchFailed()
    elseif GF.state == "ready" and GF.lastSuccess and Now() - GF.lastSuccess > STALE_AFTER then
        GF.state, GF.message = "stale", "Results are old. Refresh before contacting a listing."
        Render(); return
    end
    if GF.filters.maxAge and not pending and GF.state == "ready" then GF.Refilter()
    elseif GF.Window.UpdateStatus then GF.Window.UpdateStatus() end
end
function GF.OnWindowHidden()
    if ticker then ticker:Cancel(); ticker = nil end
end
function GF.Close()
    GF.OnWindowHidden()
    if GF.Window then GF.Window.Hide() end
end
function GF.ReturnToNative()
    GF.Close()
    if LFGParentFrame then
        if ShowUIPanel then ShowUIPanel(LFGParentFrame) else LFGParentFrame:Show() end
    end
end
function GF.Open()
    if InCombatLockdown and InCombatLockdown() then return false, "Open the Group Finder after combat." end
    AttachSearch()
    activityCache = nil
    GF.filters = M.Get(GF.mode)
    GF.party = D.Party()
    if LFGParentFrame and LFGParentFrame:IsShown() then
        if HideUIPanel then HideUIPanel(LFGParentFrame) else LFGParentFrame:Hide() end
    end
    GF.Window.Show()
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, R.Perf.Wrap("groupFinder.age", Tick)) end
    GF.Refilter()
    return true
end

local entry
local function AttachNative()
    AttachSearch()
    if entry or not LFGBrowseFrame then return end
    entry = R.FrameLook.Button(LFGBrowseFrame, "TwichUI Browse", 124, "secondary", GF.Open)
    entry:SetHeight(24)
    entry:SetPoint("TOPRIGHT", LFGBrowseFrame, "TOPRIGHT", -12, -28)
    if LFGParentFrame and LFGParentFrame.HookScript then
        LFGParentFrame:HookScript("OnShow", function() if Shown() then GF.Close() end end)
    end
end
function GF.MarkContact(identity, label)
    if not GF.contacted[identity] then
        contactOrder[#contactOrder + 1] = identity
        if #contactOrder > MAX_RESULTS then GF.contacted[table.remove(contactOrder, 1)] = nil end
    end
    GF.contacted[identity] = label
end
local function WhisperSent(_, target)
    target = D.Plain(target)
    if type(target) ~= "string" or not query or GF.state ~= "ready" then return end
    for _, row in ipairs(GF.snapshot) do
        if row.identity and row.leader == target and GF.CanContact("whisper", row) then GF.MarkContact(row.identity, "Whispered") end
    end
    GF.Refilter()
end

R:OnInit(function()
    GF.mode = M.Settings().mode == "players" and "players" or "groups"
    GF.filters, GF.party = M.Get(GF.mode), D.Party()
    AttachNative()
    R:On("ADDON_LOADED", function(name) if name == "Blizzard_GroupFinder_VanillaStyle" then AttachNative() end end)
    R:On("LFG_LIST_SEARCH_RESULTS_RECEIVED", R.Perf.Wrap("groupFinder.results", ResultsReceived))
    R:On("LFG_LIST_SEARCH_FAILED", SearchFailed)
    R:On("LFG_LIST_SEARCH_RESULT_UPDATED", R.Perf.Wrap("groupFinder.results", ResultUpdated))
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        R:On(event, function() if Shown() then GF.Refilter() end end)
    end
    R:On("LFG_LIST_AVAILABILITY_UPDATE", function() activityCache = nil; if Shown() then GF.Refilter() end end)
    local zoneQueued = false
    for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
        R:On(event, function()
            if not Shown() or zoneQueued then return end
            zoneQueued = true
            C_Timer.After(0, function()
                zoneQueued = false
                -- Run after GroupFinderZones clears its shared same-area cache.
                if Shown() then GF.Refilter() end
            end)
        end)
    end
    R:On("CHAT_MSG_WHISPER_INFORM", WhisperSent)
end)

_G.BINDING_NAME_TWICHUI_GROUP_FINDER_REFRESH = "Refresh TwichUI Group Finder"
R.Perf.Gauge("groupFinder.results", { label = "Group Finder retained listings", unit = "count", kind = "cache", read = function() return #GF.snapshot end })
R.Perf.Gauge("groupFinder.shown", { label = "Group Finder shown", unit = "bool", kind = "state", read = function() return Shown() and 1 or 0 end })
