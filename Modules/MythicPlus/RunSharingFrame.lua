--[[
    RunSharingFrame displays received Mythic+ run logs and allows interaction (view, simulate, delete).
]]

local T = unpack(Twich)
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local tinsert = _G.table.insert
local tremove = _G.table.remove
local date = _G.date

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@type MythicPlusRunSharingSubmodule
local RunSharing = MythicPlusModule.RunSharing
---@type MythicPlusSimulatorSubmodule
local Simulator = MythicPlusModule.Simulator
---@type ConfigurationModule
local CM = T:GetModule("Configuration")

---@class MythicPlusRunSharingFrameSubmodule
local RunSharingFrame = MythicPlusModule.RunSharingFrame or {}
MythicPlusModule.RunSharingFrame = RunSharingFrame

-- ElvUI Integration
local E = _G.ElvUI and _G.ElvUI[1]
local Skins = E and E.GetModule and E:GetModule("Skins", true)

-- Constants
local ROW_HEIGHT = 20
local MAX_ROWS = 15

StaticPopupDialogs["TWICHUI_CONFIRM_DELETE_RUN"] = {
    text = "Are you sure you want to delete this run?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        RunSharingFrame:PerformDelete()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- JSON Helpers (Copied from RunLogger to ensure availability)
local function IsArrayTable(t)
    if type(t) ~= "table" then return false end
    local count = 0
    local max = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false
        end
        if k > max then max = k end
        count = count + 1
        if count > 5000 then return false end
    end
    return max == count
end

local function EscapeJSON(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function EncodeJSON(v)
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return tostring(v)
    end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "string" then return '"' .. EscapeJSON(v) .. '"' end
    if tv ~= "table" then return '"' .. EscapeJSON(tostring(v)) .. '"' end

    if IsArrayTable(v) then
        local parts = {}
        for i = 1, #v do
            parts[#parts + 1] = EncodeJSON(v[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for k, val in pairs(v) do
        local keyStr = (type(k) == "string") and k or tostring(k)
        parts[#parts + 1] = '"' .. EscapeJSON(keyStr) .. '":' .. EncodeJSON(val)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

-- JSON Decoder (Minimal implementation)
local ParseValue

local function SkipWS(s, i)
    while true do
        local c = s:sub(i, i)
        if c == "" then return i end
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then
            return i
        end
        i = i + 1
    end
end

local function ParseString(s, i)
    if s:sub(i, i) ~= '"' then return nil, i, "expected string" end
    i = i + 1
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then return nil, i, "unterminated string" end
        if c == '"' then return table.concat(out), i + 1, nil end
        if c == "\\" then
            local esc = s:sub(i + 1, i + 1)
            if esc == '"' or esc == "\\" or esc == "/" then
                out[#out + 1] = esc; i = i + 2
            elseif esc == "b" then
                out[#out + 1] = "\b"; i = i + 2
            elseif esc == "f" then
                out[#out + 1] = "\f"; i = i + 2
            elseif esc == "n" then
                out[#out + 1] = "\n"; i = i + 2
            elseif esc == "r" then
                out[#out + 1] = "\r"; i = i + 2
            elseif esc == "t" then
                out[#out + 1] = "\t"; i = i + 2
            elseif esc == "u" then
                local hex = s:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then return nil, i, "invalid unicode escape" end
                local code = tonumber(hex, 16)
                if code and code >= 32 and code <= 126 then out[#out + 1] = string.char(code) else out[#out + 1] = "?" end
                i = i + 6
            else
                return nil, i, "invalid escape"
            end
        else
            out[#out + 1] = c; i = i + 1
        end
    end
end

local function ParseNumber(s, i)
    local start = i
    if s:sub(i, i) == "-" then i = i + 1 end
    while s:sub(i, i):match("%d") do i = i + 1 end
    if s:sub(i, i) == "." then
        i = i + 1; while s:sub(i, i):match("%d") do i = i + 1 end
    end
    if s:sub(i, i):match("[eE]") then
        i = i + 1; if s:sub(i, i):match("[+-]") then i = i + 1 end; while s:sub(i, i):match("%d") do i = i + 1 end
    end
    local n = tonumber(s:sub(start, i - 1))
    if not n then return nil, start, "invalid number" end
    return n, i, nil
end

local function ParseArray(s, i)
    if s:sub(i, i) ~= "[" then return nil, i, "expected array" end
    i = i + 1
    local out = {}
    i = SkipWS(s, i)
    if s:sub(i, i) == "]" then return out, i + 1, nil end
    while true do
        local v, ni, err = ParseValue(s, i)
        if err then return nil, i, err end
        out[#out + 1] = v
        i = SkipWS(s, ni)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWS(s, i + 1)
        elseif c == "]" then
            return out, i + 1, nil
        else
            return nil, i, "expected ',' or ']'"
        end
    end
end

local function ParseObject(s, i)
    if s:sub(i, i) ~= "{" then return nil, i, "expected object" end
    i = i + 1
    local out = {}
    i = SkipWS(s, i)
    if s:sub(i, i) == "}" then return out, i + 1, nil end
    while true do
        local key, ni, err = ParseString(s, i)
        if err then return nil, i, err end
        i = SkipWS(s, ni)
        if s:sub(i, i) ~= ":" then return nil, i, "expected ':'" end
        i = SkipWS(s, i + 1)
        local v, ni2, err2 = ParseValue(s, i)
        if err2 then return nil, i, err2 end
        out[key] = v
        i = SkipWS(s, ni2)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWS(s, i + 1)
        elseif c == "}" then
            return out, i + 1, nil
        else
            return nil, i, "expected ',' or '}'"
        end
    end
end

ParseValue = function(s, i)
    i = SkipWS(s, i)
    local c = s:sub(i, i)
    if c == '"' then return ParseString(s, i) end
    if c == "{" then return ParseObject(s, i) end
    if c == "[" then return ParseArray(s, i) end
    if c == "-" or c:match("%d") then return ParseNumber(s, i) end
    if s:sub(i, i + 3) == "true" then return true, i + 4, nil end
    if s:sub(i, i + 4) == "false" then return false, i + 5, nil end
    if s:sub(i, i + 3) == "null" then return nil, i + 4, nil end
    return nil, i, "unexpected token"
end

local function DecodeJSON(s)
    if type(s) ~= "string" or s == "" then return nil, "empty input" end
    local v, i, err = ParseValue(s, 1)
    if err then return nil, err end
    return v, nil
end

function RunSharingFrame:Initialize()
    if self.initialized then return end
    self.initialized = true
    self:CreateFrame()
end

function RunSharingFrame:Toggle()
    if not self.frame then
        self:CreateFrame()
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:UpdateList()
        self:UpdateSpeedInput()
        self.frame:Show()
    end
end

function RunSharingFrame:GetDB()
    local key = "TwichUIRunLoggerDB"
    local db = _G[key]
    if type(db) ~= "table" then
        db = { version = 1, remoteRuns = {} }
        _G[key] = db
    end
    if not db.remoteRuns then db.remoteRuns = {} end
    return db
end

function RunSharingFrame:CreateFrame()
    local frame = CreateFrame("Frame", "TwichUI_RunSharingFrame", UIParent, "BackdropTemplate")
    frame:SetSize(800, 500)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Skinning
    if Skins then
        Skins:HandleFrame(frame, true, nil, -5, 0, -5, 0)
    else
        if frame.SetTemplate then
            frame:SetTemplate("Transparent")
        else
            frame:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            frame:SetBackdropColor(0, 0, 0, 0.9)
        end
    end

    self.frame = frame

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Received Mythic+ Runs")

    -- Close Button
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if Skins then Skins:HandleCloseButton(close) end

    -- List ScrollFrame
    local listScroll = CreateFrame("ScrollFrame", "TwichUI_RunSharing_ListScroll", frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -50)
    listScroll:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 50)
    listScroll:SetWidth(250)
    if Skins and listScroll.ScrollBar then Skins:HandleScrollBar(listScroll.ScrollBar) end

    -- List Content
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(250, 1)
    listScroll:SetScrollChild(listContent)
    self.listContent = listContent

    -- Separator
    local sep = frame:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sep:SetPoint("TOPLEFT", listScroll, "TOPRIGHT", 25, 0)
    sep:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", 25, 0)
    sep:SetWidth(1)

    -- Details / JSON View
    local detailsScroll = CreateFrame("ScrollFrame", "TwichUI_RunSharing_DetailsScroll", frame,
        "UIPanelScrollFrameTemplate")
    detailsScroll:SetPoint("TOPLEFT", sep, "TOPRIGHT", 5, 0)
    detailsScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 80) -- Raised bottom to make room for slider
    if Skins and detailsScroll.ScrollBar then Skins:HandleScrollBar(detailsScroll.ScrollBar) end
    detailsScroll:Hide()                                                 -- Hidden by default
    self.detailsScroll = detailsScroll

    local detailsEditBox = CreateFrame("EditBox", nil, detailsScroll)
    detailsEditBox:SetMultiLine(true)
    detailsEditBox:SetAutoFocus(false)
    detailsEditBox:SetFontObject("ChatFontNormal")
    detailsEditBox:SetWidth(480)
    detailsEditBox:SetScript("OnTextChanged", function(self)
        detailsScroll:UpdateScrollChildRect()
    end)
    detailsScroll:SetScrollChild(detailsEditBox)
    self.detailsEditBox = detailsEditBox

    -- Formatted Details View
    local detailsFrame = CreateFrame("Frame", nil, frame)
    detailsFrame:SetPoint("TOPLEFT", sep, "TOPRIGHT", 5, 0)
    detailsFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 80)
    self.detailsFrame = detailsFrame

    -- Header Info
    local headerText = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerText:SetPoint("TOPLEFT", 0, 0)
    headerText:SetJustifyH("LEFT")
    self.headerText = headerText

    -- Events List
    local eventsScroll = CreateFrame("ScrollFrame", "TwichUI_RunSharing_EventsScroll", detailsFrame,
        "UIPanelScrollFrameTemplate")
    eventsScroll:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -10)
    eventsScroll:SetPoint("BOTTOMRIGHT", detailsFrame, "BOTTOMRIGHT", -25, 0)
    if Skins and eventsScroll.ScrollBar then Skins:HandleScrollBar(eventsScroll.ScrollBar) end
    self.eventsScroll = eventsScroll

    local eventsContent = CreateFrame("Frame", nil, eventsScroll)
    eventsContent:SetSize(450, 1)
    eventsScroll:SetScrollChild(eventsContent)
    self.eventsContent = eventsContent
    self.eventRows = {}

    -- View Toggle Button
    local viewToggleBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    viewToggleBtn:SetSize(80, 20)
    viewToggleBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -12)
    viewToggleBtn:SetText("Raw JSON")
    viewToggleBtn:SetScript("OnClick", function() self:ToggleViewMode() end)
    if Skins then Skins:HandleButton(viewToggleBtn) end
    self.viewToggleBtn = viewToggleBtn

    self.viewMode = "formatted" -- "formatted" or "json"

    -- Buttons
    local btnWidth = 100
    local btnHeight = 24
    local iconSize = 32

    -- Simulate Button (Icon)
    local simBtn = CreateFrame("Button", nil, frame)
    simBtn:SetSize(iconSize, iconSize)
    simBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    simBtn:SetNormalTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\play-button.tga")
    simBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    simBtn:SetScript("OnClick", function() self:OnSimulateClick() end)
    simBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Start Simulation")
        GameTooltip:Show()
    end)
    simBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    self.simBtn = simBtn

    -- Stop Button (Icon)
    local stopBtn = CreateFrame("Button", nil, frame)
    stopBtn:SetSize(iconSize, iconSize)
    stopBtn:SetPoint("RIGHT", simBtn, "LEFT", -5, 0)
    stopBtn:SetNormalTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\stop-button.tga")
    stopBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    stopBtn:SetScript("OnClick", function() self:OnStopClick() end)
    stopBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Stop Simulation")
        GameTooltip:Show()
    end)
    stopBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    self.stopBtn = stopBtn

    -- Speed Input
    local speedInput = CreateFrame("EditBox", "TwichUI_RunSharing_SpeedInput", frame, "InputBoxTemplate")
    speedInput:SetSize(40, 20)
    speedInput:SetPoint("RIGHT", stopBtn, "LEFT", -10, 0)
    speedInput:SetAutoFocus(false)
    speedInput:SetJustifyH("CENTER")
    speedInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val > 0 then
            CM:SetProfileSettingSafe("developer.mythicplus.simulator.playbackSpeed", val)
            self:ClearFocus()
        else
            self:SetText(CM:GetProfileSettingSafe("developer.mythicplus.simulator.playbackSpeed", 10))
        end
    end)
    speedInput:SetScript("OnEscapePressed", function(self)
        self:SetText(CM:GetProfileSettingSafe("developer.mythicplus.simulator.playbackSpeed", 10))
        self:ClearFocus()
    end)
    if Skins then Skins:HandleEditBox(speedInput) end
    self.speedInput = speedInput

    local speedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    speedLabel:SetPoint("RIGHT", speedInput, "LEFT", -5, 0)
    speedLabel:SetText("Speed:")

    -- Clear All Button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(btnWidth, btnHeight)
    clearBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function() self:OnClearAllClick() end)
    if Skins then Skins:HandleButton(clearBtn) end
    self.clearBtn = clearBtn

    -- Import Button
    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(btnWidth, btnHeight)
    importBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    importBtn:SetText("Import JSON")
    importBtn:SetScript("OnClick", function() self:OnImportClick() end)
    if Skins then Skins:HandleButton(importBtn) end
    self.importBtn = importBtn

    self.rows = {}
end

function RunSharingFrame:UpdateSpeedInput()
    if not self.speedInput then return end
    local speed = CM:GetProfileSettingSafe("developer.mythicplus.simulator.playbackSpeed", 10)
    self.speedInput:SetText(tostring(speed))
end

function RunSharingFrame:ResolveDungeonName(run)
    if not run or not run.data then return end

    -- Debug: Check what we are working with
    -- print("TwichUI Debug: Checking run...", run.data.dungeonName)

    -- Check if we need to resolve
    local needsResolution = false
    if not run.data.dungeonName or run.data.dungeonName == "Unknown" or run.data.dungeonName == "Unknown Dungeon" then
        needsResolution = true
    end

    if not needsResolution then return end

    local mapId = run.data.run and run.data.run.mapId

    if not mapId and run.data.events then
        for _, ev in ipairs(run.data.events) do
            if ev.name == "CHALLENGE_MODE_START" and ev.payload and ev.payload.mapId then
                mapId = ev.payload.mapId
                -- print("TwichUI Debug: Found mapId in events:", mapId)
                break
            end
        end
    end

    if mapId then
        local name = C_ChallengeMode.GetMapUIInfo(mapId)

        -- Fallback to C_ChallengeMode.GetMapInfo (returns table)
        if not name and C_ChallengeMode.GetMapInfo then
            local info = C_ChallengeMode.GetMapInfo(mapId)
            if info and info.name then
                name = info.name
            end
        end

        -- Fallback to C_Map if ChallengeMode API fails
        if not name then
            local mapInfo = C_Map.GetMapInfo(mapId)
            if mapInfo then
                name = mapInfo.name
            end
        end

        if name then
            run.data.dungeonName = name
            -- Also update the run object mapId if missing, for consistency
            if run.data.run then
                run.data.run.mapId = mapId
            end
            print(string.format("TwichUI: Resolved dungeon name for run to '%s' (MapID: %s)", name, tostring(mapId)))
        else
            print("TwichUI Debug: All API lookups (GetMapUIInfo, GetMapInfo, C_Map) returned nil for mapId:", mapId)
        end
    else
        print("TwichUI Debug: Could not find mapId for run")
    end
end

function RunSharingFrame:UpdateList()
    local db = self:GetDB()
    local runs = db.remoteRuns or {}

    -- Clear existing rows
    for _, row in ipairs(self.rows) do
        row:Hide()
    end

    local yOffset = 0
    for i, run in ipairs(runs) do
        self:ResolveDungeonName(run)

        local row = self.rows[i]
        if not row then
            row = CreateFrame("Button", nil, self.listContent)
            row:SetSize(250, ROW_HEIGHT)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", 5, 0)
            text:SetPoint("RIGHT", -45, 0)
            text:SetJustifyH("LEFT")
            row.text = text

            -- Delete Button (Red X)
            local delBtn = CreateFrame("Button", nil, row)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            delBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            delBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            delBtn:Hide()
            delBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Delete Run")
                GameTooltip:Show()
            end)
            delBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            row.delBtn = delBtn

            -- Rename Button (Pencil/Edit)
            local renameBtn = CreateFrame("Button", nil, row)
            renameBtn:SetSize(16, 16)
            renameBtn:SetPoint("RIGHT", delBtn, "LEFT", -2, 0)
            renameBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
            renameBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
            renameBtn:Hide()
            renameBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Rename Run")
                GameTooltip:Show()
            end)
            renameBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            row.renameBtn = renameBtn

            row:SetScript("OnEnter", function(self)
                self.delBtn:Show()
                self.renameBtn:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if not self:IsMouseOver() then
                    self.delBtn:Hide()
                    self.renameBtn:Hide()
                end
            end)

            row:SetScript("OnClick", function() self:SelectRun(i) end)
            self.rows[i] = row
        end

        -- Update button scripts with current index
        row.delBtn:SetScript("OnClick", function() self:OnDeleteClick(i) end)
        row.renameBtn:SetScript("OnClick", function() self:OnRenameClick(i) end)

        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:Show()

        local dateStr = date("%m/%d %H:%M", run.receivedAt)
        local sender = run.sender or "Unknown"
        local dungeon = run.data and run.data.dungeonName or "Unknown"
        local level = run.data and run.data.keystoneLevel or "?"

        if run.customName then
            row.text:SetText(run.customName)
        else
            row.text:SetText(string.format("%s: +%s %s (%s)", dateStr, level, dungeon, sender))
        end

        yOffset = yOffset + ROW_HEIGHT
    end

    self.listContent:SetHeight(math.max(1, yOffset))
end

function RunSharingFrame:SelectRun(index)
    self.selectedIndex = index
    self:UpdateDetailsView()
end

function RunSharingFrame:ToggleViewMode()
    if self.viewMode == "formatted" then
        self.viewMode = "json"
        self.viewToggleBtn:SetText("Formatted")
    else
        self.viewMode = "formatted"
        self.viewToggleBtn:SetText("Raw JSON")
    end
    self:UpdateDetailsView()
end

function RunSharingFrame:UpdateDetailsView()
    local db = self:GetDB()
    local run = self.selectedIndex and db.remoteRuns[self.selectedIndex]

    if not run or not run.data then
        self.detailsEditBox:SetText("")
        self.detailsScroll:Hide()
        self.detailsFrame:Hide()
        self.headerText:SetText("")
        return
    end

    if self.viewMode == "json" then
        self.detailsFrame:Hide()
        self.detailsScroll:Show()
        local json = EncodeJSON(run.data)
        self.detailsEditBox:SetText(json)
    else
        self.detailsScroll:Hide()
        self.detailsFrame:Show()

        -- Header
        local d = run.data.run or {}
        local dungeon = run.data.dungeonName or (d.dungeonName) -- Check both locations
        if not dungeon or dungeon == "Unknown" then
            dungeon = d.mapId and C_ChallengeMode.GetMapUIInfo(d.mapId) or "Unknown Dungeon"
        end

        local level = d.level or "?"
        local dateStr = date("%Y-%m-%d %H:%M", run.receivedAt)
        self.headerText:SetFontObject("GameFontNormalHuge")
        self.headerText:SetText(string.format("%s +%s\n|cffaaaaaa%s|r", dungeon, level, dateStr))

        -- Events List
        self:UpdateEventsList(run.data.events)
    end
end

function RunSharingFrame:UpdateEventsList(events)
    if not events then return end

    -- Clear rows
    for _, row in ipairs(self.eventRows) do row:Hide() end

    local yOffset = 0
    local ROW_HEIGHT = 28 -- Increased from 24

    local FRIENDLY_NAMES = {
        CHALLENGE_MODE_START = "Key Start",
        CHALLENGE_MODE_COMPLETED = "Key Completed",
        CHALLENGE_MODE_RESET = "Key Reset",
        ENCOUNTER_START = "Boss Start",
        ENCOUNTER_END = "Boss End",
        CHAT_MSG_LOOT = "Loot",
        PLAYER_DEAD = "Player Death",
        GROUP_ROSTER_UPDATE = "Roster Update",
        GROUP_ROSTER_SNAPSHOT = "Roster Snapshot",
    }

    local EVENT_COLORS = {
        CHALLENGE_MODE_START = "|cff4caf50",     -- Green
        CHALLENGE_MODE_COMPLETED = "|cff4caf50", -- Green
        CHALLENGE_MODE_RESET = "|cfff44336",     -- Red
        ENCOUNTER_START = "|cffffc107",          -- Amber
        ENCOUNTER_END = "|cffffc107",            -- Amber
        CHAT_MSG_LOOT = "|cff9c27b0",            -- Purple
        PLAYER_DEAD = "|cfff44336",              -- Red
        GROUP_ROSTER_UPDATE = "|cff9e9e9e",      -- Grey
        GROUP_ROSTER_SNAPSHOT = "|cff9e9e9e",    -- Grey
    }

    self.expandedRows = self.expandedRows or {}

    for i, ev in ipairs(events) do
        local row = self.eventRows[i]
        if not row then
            row = CreateFrame("Button", nil, self.eventsContent)
            row:SetSize(450, ROW_HEIGHT)

            -- Background (Striping)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.05)
            bg:Hide()
            row.bg = bg

            -- Expand Button (Skinnable)
            local expandBtn = CreateFrame("Button", nil, row)
            expandBtn:SetSize(16, 16)
            expandBtn:SetPoint("TOPLEFT", 5, -(ROW_HEIGHT - 16) / 2)

            if Skins then
                Skins:HandleButton(expandBtn)
                expandBtn.text = expandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                expandBtn.text:SetPoint("CENTER")
            else
                -- Fallback for non-ElvUI
                expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
            end

            expandBtn:SetScript("OnClick", function() self:ToggleEventDetails(i) end)
            row.expandBtn = expandBtn

            local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            timeText:SetPoint("TOPLEFT", expandBtn, "TOPRIGHT", 8, -2)
            timeText:SetWidth(45)
            timeText:SetJustifyH("LEFT")
            row.timeText = timeText

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("TOPLEFT", timeText, "TOPRIGHT", 5, 0)
            nameText:SetWidth(300)
            nameText:SetJustifyH("LEFT")
            row.nameText = nameText

            local playBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            playBtn:SetSize(40, 20)
            playBtn:SetPoint("TOPRIGHT", -5, -(ROW_HEIGHT - 20) / 2)
            playBtn:SetText("Play")
            if Skins then Skins:HandleButton(playBtn) end
            row.playBtn = playBtn

            row:SetScript("OnClick", function() self:ToggleEventDetails(i) end)

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.eventData then
                    GameTooltip:AddLine(self.eventData.name or "Event", 1, 1, 1)
                    if self.eventData.payload then
                        local json = EncodeJSON(self.eventData.payload)
                        if #json > 300 then json = json:sub(1, 297) .. "..." end
                        GameTooltip:AddLine(json, 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self) GameTooltip:Hide() end)

            self.eventRows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -yOffset)
        row:Show()
        row.eventData = ev

        -- Striping
        if i % 2 == 0 then
            row.bg:Show()
        else
            row.bg:Hide()
        end

        local rel = ev.relSeconds or 0
        local m = math.floor(rel / 60)
        local s = math.floor(rel % 60)
        row.timeText:SetText(string.format("%02d:%02d", m, s))

        local rawName = ev.name or "Unknown"
        local friendly = FRIENDLY_NAMES[rawName]
        local color = EVENT_COLORS[rawName] or "|cffffffff"

        if friendly then
            row.nameText:SetText(string.format("%s%s|r |cff888888(%s)|r", color, friendly, rawName))
        else
            row.nameText:SetText(color .. rawName .. "|r")
        end

        -- Expansion Logic
        local isExpanded = self.expandedRows[i]

        if Skins then
            row.expandBtn.text:SetText(isExpanded and "-" or "+")
        else
            row.expandBtn:SetNormalTexture(isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or
                "Interface\\Buttons\\UI-PlusButton-Up")
        end

        local rowHeight = ROW_HEIGHT

        if isExpanded then
            if not row.details then
                row.details = CreateFrame("Frame", nil, row)
                row.details:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -ROW_HEIGHT)
                row.details:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.details:EnableMouse(true)
                row.details:SetScript("OnMouseDown", function() end)
            end
            row.details:Show()
            local detailsHeight = self:PopulateEventDetails(row.details, ev.payload)
            row.details:SetHeight(detailsHeight)
            rowHeight = rowHeight + detailsHeight
        else
            if row.details then row.details:Hide() end
        end

        row:SetHeight(rowHeight)

        row.playBtn:SetScript("OnClick", function()
            if Simulator and Simulator.SimulateSingleEvent then
                Simulator:SimulateSingleEvent(ev)
            end
        end)

        yOffset = yOffset + rowHeight
    end

    self.eventsContent:SetHeight(math.max(1, yOffset))
end

function RunSharingFrame:ToggleEventDetails(index)
    self.expandedRows = self.expandedRows or {}
    self.expandedRows[index] = not self.expandedRows[index]

    local db = self:GetDB()
    local run = self.selectedIndex and db.remoteRuns[self.selectedIndex]
    if run and run.data then
        self:UpdateEventsList(run.data.events)
    end
end

function RunSharingFrame:PopulateEventDetails(container, payload)
    -- Hide single big editbox if it exists
    if container.editBox then container.editBox:Hide() end
    if container.measureFS then container.measureFS:Hide() end

    container.rows = container.rows or {}
    -- Hide all existing rows
    for _, row in ipairs(container.rows) do row:Hide() end

    local y = 5
    local rowIndex = 0

    local function GetRow()
        rowIndex = rowIndex + 1
        local row = container.rows[rowIndex]
        if not row then
            row = CreateFrame("Frame", nil, container)

            row.key = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.key:SetPoint("TOPLEFT", 0, 0)
            row.key:SetJustifyH("LEFT")

            row.value = CreateFrame("EditBox", nil, row)
            row.value:SetFontObject("GameFontHighlight")
            row.value:SetMultiLine(true)
            row.value:SetAutoFocus(false)
            row.value:SetJustifyH("LEFT")
            row.value:SetPoint("TOPLEFT", row.key, "TOPRIGHT", 5, 0)
            row.value:SetPoint("RIGHT", 0, 0)
            row.value:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            row.value:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            row.value:SetScript("OnTextChanged", function(self, userInput)
                if userInput then
                    self:SetText(self.originalText or "")
                    self:ClearFocus()
                end
            end)

            -- Measurement helper
            row.measure = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.measure:SetWordWrap(true)
            row.measure:Hide()

            container.rows[rowIndex] = row
        end
        row:Show()
        row.value:Show()
        return row
    end

    local function AddEntry(key, value, indentLevel)
        local row = GetRow()
        local indent = indentLevel * 12 -- Increased indentation

        row:SetPoint("TOPLEFT", 10 + indent, -y)
        row:SetPoint("RIGHT", -10, 0)

        -- Set Key
        row.key:SetText(string.format("|cffffd100%s:|r", key))

        if type(value) == "table" then
            row.value:Hide()
            local rowHeight = row.key:GetStringHeight()
            row:SetHeight(rowHeight)
            y = y + rowHeight + 4 -- Increased spacing

            local keys = {}
            for k in pairs(value) do table.insert(keys, k) end
            table.sort(keys, function(a, b)
                if type(a) == "number" and type(b) == "number" then return a < b end
                if type(a) == "number" then return true end
                if type(b) == "number" then return false end
                return tostring(a) < tostring(b)
            end)

            for _, k in ipairs(keys) do
                AddEntry(k, value[k], indentLevel + 1)
            end
        else
            local valStr = tostring(value)
            row.value.originalText = valStr
            row.value:SetText(valStr)

            -- Calculate dimensions
            local keyWidth = row.key:GetStringWidth()
            local totalWidth = 450 - 20                         -- Approx container width
            local availableWidth = totalWidth - indent - keyWidth - 5
            if availableWidth < 50 then availableWidth = 50 end -- Min width

            row.measure:SetWidth(availableWidth)
            row.measure:SetText(valStr)
            local valHeight = row.measure:GetStringHeight()
            local keyHeight = row.key:GetStringHeight()

            local rowHeight = math.max(keyHeight, valHeight)
            row:SetHeight(rowHeight)
            row.value:SetHeight(rowHeight + 10) -- Extra height to prevent scrolling

            y = y + rowHeight + 4               -- Increased spacing
        end
    end

    if type(payload) == "table" then
        local keys = {}
        for k in pairs(payload) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            AddEntry(k, payload[k], 0)
        end
    else
        AddEntry("Payload", payload, 0)
    end

    return y + 5
end

function RunSharingFrame:OnSimulateClick()
    if not self.selectedIndex then return end
    local db = self:GetDB()
    local run = db.remoteRuns[self.selectedIndex]

    if run and run.data then
        if Simulator and Simulator.StartSimulationFromData then
            Simulator:StartSimulationFromData(run.data)
        elseif Simulator and Simulator.StartSimulationFromJSON then
            -- Fallback if we can convert to JSON, but we can't easily.
            -- We should add StartSimulationFromData to Simulator.lua
            print("Simulator: StartSimulationFromData not found.")
        end
    end
end

function RunSharingFrame:OnStopClick()
    if Simulator and Simulator.StopSimulation then
        Simulator:StopSimulation()
    end
end

function RunSharingFrame:OnDeleteClick(index)
    self.runToDeleteIndex = index or self.selectedIndex
    if not self.runToDeleteIndex then return end
    StaticPopup_Show("TWICHUI_CONFIRM_DELETE_RUN")
end

function RunSharingFrame:PerformDelete()
    local index = self.runToDeleteIndex or self.selectedIndex
    if not index then return end
    
    local db = self:GetDB()
    tremove(db.remoteRuns, index)
    
    if self.selectedIndex == index then
        self.selectedIndex = nil
        self.detailsEditBox:SetText("")
        self.detailsScroll:Hide()
        self.detailsFrame:Hide()
        self.headerText:SetText("")
    elseif self.selectedIndex and self.selectedIndex > index then
        self.selectedIndex = self.selectedIndex - 1
    end
    
    self.runToDeleteIndex = nil
    self:UpdateList()
end

function RunSharingFrame:OnClearAllClick()
    local db = self:GetDB()
    db.remoteRuns = {}
    self.selectedIndex = nil
    self.detailsEditBox:SetText("")
    self.detailsScroll:Hide()
    self.detailsFrame:Hide()
    self.headerText:SetText("")
    self:UpdateList()
end

function RunSharingFrame:OnImportClick()
    self:ShowImportDialog()
end

function RunSharingFrame:ShowImportDialog()
    if self.importFrame then
        self.importFrame:Show()
        return
    end

    local frame = CreateFrame("Frame", "TwichUI_RunSharing_ImportFrame", self.frame, "BackdropTemplate")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(self.frame:GetFrameLevel() + 10)

    if Skins then
        Skins:HandleFrame(frame, true, nil, -5, 0, -5, 0)
    else
        if frame.SetTemplate then
            frame:SetTemplate("Transparent")
        else
            frame:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            frame:SetBackdropColor(0, 0, 0, 0.9)
        end
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Import Run JSON")

    local scroll = CreateFrame("ScrollFrame", "TwichUI_RunSharing_ImportScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 50)
    if Skins and scroll.ScrollBar then Skins:HandleScrollBar(scroll.ScrollBar) end

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(450)
    editBox:SetScript("OnTextChanged", function(self)
        scroll:UpdateScrollChildRect()
    end)
    scroll:SetScrollChild(editBox)

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 24)
    importBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        local data, err = DecodeJSON(text)
        if not data then
            print("TwichUI: Import failed - " .. (err or "Unknown error"))
            return
        end

        -- Basic validation
        if type(data) ~= "table" or not data.events then
            print("TwichUI: Invalid run data format")
            return
        end

        local db = self:GetDB()
        tinsert(db.remoteRuns, {
            sender = "Imported",
            receivedAt = _G.time(),
            data = data
        })
        self:UpdateList()
        frame:Hide()
        editBox:SetText("")
        print("TwichUI: Run imported successfully")
    end)
    if Skins then Skins:HandleButton(importBtn) end

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("RIGHT", importBtn, "LEFT", -10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
    if Skins then Skins:HandleButton(cancelBtn) end

    self.importFrame = frame
end

function RunSharingFrame:OnRenameClick(index)
    self.runToRenameIndex = index or self.selectedIndex
    if not self.runToRenameIndex then return end
    self:ShowRenameDialog()
end

function RunSharingFrame:ShowRenameDialog()
    if self.renameFrame then
        self.renameFrame:Show()
        return
    end

    local frame = CreateFrame("Frame", "TwichUI_RunSharing_RenameFrame", self.frame, "BackdropTemplate")
    frame:SetSize(300, 120)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(self.frame:GetFrameLevel() + 20)

    if Skins then
        Skins:HandleFrame(frame, true, nil, -5, 0, -5, 0)
    else
        if frame.SetTemplate then
            frame:SetTemplate("Transparent")
        else
            frame:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            frame:SetBackdropColor(0, 0, 0, 0.9)
        end
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Rename Run")

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetSize(250, 20)
    editBox:SetPoint("TOP", title, "BOTTOM", 0, -15)
    editBox:SetAutoFocus(true)
    if Skins then Skins:HandleEditBox(editBox) end
    self.renameEditBox = editBox

    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        local db = self:GetDB()
        local index = self.runToRenameIndex or self.selectedIndex
        if index and db.remoteRuns[index] then
            db.remoteRuns[index].customName = (text ~= "" and text) or nil
            self:UpdateList()
        end
        frame:Hide()
        self.runToRenameIndex = nil
    end)
    if Skins then Skins:HandleButton(saveBtn) end

    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() 
        frame:Hide() 
        self.runToRenameIndex = nil
    end)
    if Skins then Skins:HandleButton(cancelBtn) end

    self.renameFrame = frame

    frame:SetScript("OnShow", function()
        local db = self:GetDB()
        local index = self.runToRenameIndex or self.selectedIndex
        if index and db.remoteRuns[index] then
            local run = db.remoteRuns[index]
            if run.customName then
                editBox:SetText(run.customName)
            else
                local dateStr = date("%m/%d %H:%M", run.receivedAt)
                local sender = run.sender or "Unknown"
                local dungeon = run.data and run.data.dungeonName or "Unknown"
                local level = run.data and run.data.keystoneLevel or "?"
                editBox:SetText(string.format("%s: +%s %s (%s)", dateStr, level, dungeon, sender))
            end
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end)
end
