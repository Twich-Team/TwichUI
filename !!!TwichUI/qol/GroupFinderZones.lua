-- TwichUI: Quality of Life, Group Finder zones
-- Shows, on each listing in the game's Group Finder (Looking for Group > Find a group), the zone the game
-- reports for the listing's leader, after the activity name. A zone that is where you are is marked with a
-- check and drawn in the "on" color, so a player or group close by is easy to pick out before you invite or
-- whisper. Off until turned on. It only reads and draws: it never invites, whispers, searches or lists, it
-- sends nothing to anyone and saves nothing but its switch.
--
-- What the game gives us (WoW: Forever UI source, forever branch, and API documentation, 1.60.1):
--   * Blizzard_GroupFinder_VanillaStyle (load on demand) draws the list. Every listing row is updated by the
--     global LFGBrowseSearchEntry_Update(row), from the scroll box's initializer and on
--     LFG_LIST_SEARCH_RESULT_UPDATED; the row keeps the result in row.resultID and has the regions
--     ActivityName (the second line) and DataDisplay (the roles, member icons or count on the right). We
--     hook that function once (hooksecurefunc: a hook can't be removed) and do nothing while the switch is off.
--   * C_LFGList.GetSearchResultLeaderInfo(resultID) returns LfgSearchResultPlayerInfo, whose areaName is the
--     only location the Group Finder has. Forever fills it for the leader only (other members come back
--     with areaName nil: NaowhForever PR #185, checked in the game), so the leader's zone is what is shown;
--     for a single player's listing that is the player's own zone. Older or missing: member 1 of
--     GetSearchResultPlayerInfo when it is the leader. Both are SecretInChatMessagingLockdown: a secret
--     value is never compared or shown, the zone is just left out.
--   * Whether areaName is a zone ("Elwynn Forest") or a subzone ("Goldshire") is not documented, so "where
--     you are" is every name the game gives for your spot: GetRealZoneText, GetZoneText, GetSubZoneText and
--     GetMinimapZoneText. A leader in another subzone of your zone is then not marked, when the game gives
--     subzones; nothing is guessed about neighbouring zones.
--   * The zone is the one the server sent with the search results; it is as fresh as your last search.
--
-- Nothing is written on the game's rows: each row's zone is a font string of ours made on it, kept in a
-- weak table. Its width is held to the room between the activity and the right-hand block, as measured
-- from the regions the game is showing there; when that can't be measured it is capped at Z.CAP, and with
-- less than Z.MIN of room it is left out rather than squeezed to an ellipsis.

local R = TwichUI
local Z = {}
R.QoLGroupFinderZones = Z

Z.KEY = "qolGroupFinderZones"
Z.ADDON = "Blizzard_GroupFinder_VanillaStyle"
Z.HOOK = "LFGBrowseSearchEntry_Update"
Z.GAP = 6        -- pixels between the activity name and the zone, and kept clear before the right-hand block
Z.CAP = 110      -- the widest the zone may be when the room beside it can't be measured
Z.MIN = 24       -- with less room than this the zone is not shown
Z.CHECK = R.PATH .. [[media\guides\status-done-small]]
Z.HERE_FUNCTIONS = { "GetRealZoneText", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText" }
local ZONE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }

local hooked = false
local labels = setmetatable({}, { __mode = "k" })   -- [the game's row] = our font string
local made = 0                                     -- font strings made (one per row the game ever showed)
local here                                         -- [name] = true: where you are; nil until asked again
local listening = {}                               -- [event] = handler, while registered

local function Plain(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

local function Name(value)
    value = Plain(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok then return nil end
    return Plain(value)
end

---------------------------------------------------------------------------
-- What the game says
---------------------------------------------------------------------------
-- The zone the game gives for a listing's leader, or nil.
function Z.LeaderZone(resultID)
    resultID = Plain(resultID)
    local api = C_LFGList
    if type(resultID) ~= "number" or type(api) ~= "table" then return nil end
    local info = Call(api.GetSearchResultLeaderInfo, resultID)
    if type(info) == "table" then return Name(info.areaName) end
    info = Call(api.GetSearchResultPlayerInfo, resultID, 1)
    if type(info) == "table" and Plain(info.isLeader) == true then return Name(info.areaName) end
    return nil
end

-- Every name the game gives for where you are, as a set. Kept until the zone changes.
function Z.Here()
    if here then return here end
    here = {}
    for _, key in ipairs(Z.HERE_FUNCTIONS) do
        local name = Name(Call(_G[key]))
        if name then here[name] = true end
    end
    return here
end

function Z.Nearby(area)
    return area ~= nil and Z.Here()[area] == true
end

local function Delisted(resultID)
    local api = C_LFGList
    local info = type(api) == "table" and Call(api.GetSearchResultInfo, resultID) or nil
    return type(info) == "table" and Plain(info.isDelisted) == true
end

---------------------------------------------------------------------------
-- Room on the row
---------------------------------------------------------------------------
local function Shown(region)
    return region ~= nil and type(region.IsShown) == "function" and region:IsShown() and true or false
end

local function Left(region)
    if not Shown(region) or type(region.GetLeft) ~= "function" then return nil end
    local left = Plain(region:GetLeft())
    return type(left) == "number" and left or nil
end

-- The left edge of what the game shows on the right of the row, or false when its layout is one we don't know.
local function BlockLeft(display)
    if not Shown(display) then return nil end
    if Shown(display.RoleCount) then return false end
    local edge
    local function Take(region)
        local left = Left(region)
        if left and (not edge or left < edge) then edge = left end
    end
    if Shown(display.Solo) then
        Take(display.Solo.RolesText)
        for _, role in ipairs(display.Solo.Roles or {}) do Take(role) end
    end
    if Shown(display.Enumerate) then
        for _, icon in ipairs(display.Enumerate.Icons or {}) do Take(icon) end
    end
    if Shown(display.PlayerCount) then
        Take(display.PlayerCount.Count)
        Take(display.PlayerCount.Icon)
    end
    Take(display.Comment)
    Take(display.DelistButton)
    return edge
end

-- How wide the zone may be on this row.
function Z.Room(row)
    local activity = row.ActivityName
    local right = activity and type(activity.GetRight) == "function" and Plain(activity:GetRight())
    if type(right) ~= "number" then return Z.CAP end
    local edge = BlockLeft(row.DataDisplay)
    if edge == false then return Z.CAP end
    if not edge then
        edge = type(row.GetRight) == "function" and Plain(row:GetRight())
        if type(edge) ~= "number" then return Z.CAP end
    end
    return edge - right - 2 * Z.GAP
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Label(row)
    local label = labels[row]
    if label then return label end
    label = row:CreateFontString(nil, "ARTWORK")
    local font = row.ActivityName.GetFontObject and row.ActivityName:GetFontObject()
    if font then label:SetFontObject(font) else label:SetFontObject("GameFontDisableLeft") end
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    labels[row] = label
    made = made + 1
    return label
end

-- Draws (or hides) one row's zone. The hook: runs after the game has drawn the row.
function Z.Draw(row)
    local label = labels[row]
    local area = R:Enabled(Z.KEY) and type(row) == "table" and row.ActivityName and Z.LeaderZone(row.resultID) or nil
    if not area then
        if label then label:Hide() end
        return
    end
    local room = Z.Room(row)
    if room < Z.MIN then
        if label then label:Hide() end
        return
    end
    label = Label(row)
    label:ClearAllPoints()
    label:SetPoint("LEFT", row.ActivityName, "RIGHT", Z.GAP, 0)
    if Z.Nearby(area) and not Delisted(row.resultID) then
        local sage = R.Look and R.Look.pal and R.Look.pal.sage
        label:SetText(("|T%s:0|t %s"):format(Z.CHECK, area))
        if sage then label:SetTextColor(sage[1], sage[2], sage[3]) end
    else
        label:SetText(area)
        label:SetTextColor(row.ActivityName:GetTextColor())   -- dims with the row when the game dims it
    end
    label:SetWidth(0)
    local want = label:GetStringWidth() or 0
    label:SetWidth(want > room and room or want)
    label:Show()
end

-- Every row the list is showing now, drawn again (after the switch or your zone changes).
function Z.Redraw()
    local on = R:Enabled(Z.KEY)
    for row, label in pairs(labels) do
        if not on then label:Hide() end
    end
    if not on then return end
    local box = LFGBrowseFrame and LFGBrowseFrame.ScrollBox
    if box and type(box.ForEachFrame) == "function" then
        box:ForEachFrame(function(row)
            if type(row) == "table" and row.resultID and row.ActivityName then Z.Draw(row) end
        end)
    end
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------
local function Attach()
    if hooked or type(_G[Z.HOOK]) ~= "function" then return hooked end
    hooked = true
    hooksecurefunc(Z.HOOK, R.Perf.Wrap("qol.groupFinderZones.row", Z.Draw))
    return true
end

local function Want(event, handler, on)
    if on and listening[event] ~= handler then
        R:On(event, handler)
        listening[event] = handler
    elseif not on and listening[event] then
        R:Off(event, listening[event])
        listening[event] = nil
    end
end

local function OnAddOnLoaded(name)
    if name ~= Z.ADDON then return end
    Z.Refresh()
end

local function OnZoneChanged()
    here = nil
    Z.Redraw()
end

function Z.Refresh()
    local on = R:Enabled(Z.KEY)
    if on then Attach() end
    Want("ADDON_LOADED", OnAddOnLoaded, on and not hooked)
    for _, event in ipairs(ZONE_EVENTS) do Want(event, OnZoneChanged, on) end
    here = nil
    Z.Redraw()
end

function Z.Hooked() return hooked end

-- Read only, for the diagnostics tool: how many font strings were made.
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("qol.groupFinderZones.labels", { label = "Group Finder zones: zone labels made (one per listing row the game showed)",
        unit = "count", kind = "pool", read = function() return made end })
end

R:OnInit(Z.Refresh)
