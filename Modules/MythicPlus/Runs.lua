local T = unpack(Twich)
local MythicPlusModule = T:GetModule("MythicPlus")
local CM = T:GetModule("Configuration")

local _G = _G
local ElvUI = _G.ElvUI
local E = ElvUI and ElvUI[1]

---@type ToolsModule
local Tools = T:GetModule("Tools")
---@type ToolsUI|nil
local UI = Tools and Tools.UI
local CT = Tools and Tools.Colors
local TT = Tools and Tools.Text
local Textures = Tools and Tools.Textures

--- @class MythicPlusRunsSubmodule
local Runs = MythicPlusModule.Runs or {}
MythicPlusModule.Runs = Runs

local Database = MythicPlusModule.Database

-- Static Popup for Deletion
StaticPopupDialogs["TWICHUI_CONFIRM_DELETE_RUN"] = {
    text = "Are you sure you want to delete this run?\n\n%s",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self, data)
        if data and data.runId then
            Database:DeleteRun(data.runId)
            if data.callback then
                data.callback()
            elseif data.panel then
                Runs:Refresh(data.panel)
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Constants
local PANEL_PADDING = 10
local ROW_HEIGHT = 24
local HEADER_HEIGHT = 24

-- Columns configuration
local COLUMNS = {
    { key = "date",    label = "Date",    width = 120, justify = "LEFT" },
    { key = "dungeon", label = "Dungeon", width = 180, justify = "LEFT" },
    { key = "level",   label = "Key",     width = 60,  justify = "CENTER" },
    { key = "time",    label = "Time",    width = 80,  justify = "RIGHT" },
    { key = "score",   label = "Score",   width = 60,  justify = "RIGHT" },
    { key = "upgrade", label = "Up",      width = 40,  justify = "CENTER" },
}

local function FormatTime(seconds)
    if not seconds then return "—" end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function FormatSignedTimeDelta(seconds)
    if seconds == nil then return "—" end
    seconds = tonumber(seconds)
    if not seconds then return "—" end

    local sign = seconds < 0 and "-" or "+"
    local abs = math.abs(seconds)
    local m = math.floor(abs / 60)
    local s = math.floor(abs % 60)
    return string.format("%s%d:%02d", sign, m, s)
end

local function Color(hex, text)
    if TT and TT.Color and CT and CT.TWICH and type(hex) == "string" then
        return TT.Color(hex, tostring(text))
    end
    return tostring(text)
end

local function Accent(text)
    return (CT and CT.TWICH and CT.TWICH.SECONDARY_ACCENT) and Color(CT.TWICH.SECONDARY_ACCENT, text) or tostring(text)
end

local function GetRunDetailsLabelColor()
    local entry = MythicPlusModule and MythicPlusModule.CONFIGURATION and
        MythicPlusModule.CONFIGURATION.RUN_DETAILS_LABEL_COLOR
    local c = entry and CM and CM.GetProfileSettingByConfigEntry and CM:GetProfileSettingByConfigEntry(entry) or nil
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b
    end
    -- Fallback (matches Tools.Colors.TWICH.SECONDARY_ACCENT #4CC9F0)
    return 76 / 255, 201 / 255, 240 / 255
end

local function FormatDate(timestamp)
    if not timestamp then return "—" end
    return date("%m/%d/%Y", timestamp)
end

local function GetDungeonName(runData)
    if type(runData) == "table" and type(runData.dungeonName) == "string" and runData.dungeonName ~= "" then
        return runData.dungeonName
    end

    local mapId = type(runData) == "table" and runData.mapId or runData

    local mpData = MythicPlusModule and MythicPlusModule.Data
    if mpData and type(mpData.GetMapNameCached) == "function" then
        local name = mpData.GetMapNameCached(mapId)
        if name then
            return name
        end
    end

    local api = MythicPlusModule and MythicPlusModule.API
    if api and type(api.GetMapUIInfo) == "function" then
        local name = api:GetMapUIInfo(mapId)
        if name then
            return name
        end
    end

    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name = C_ChallengeMode.GetMapUIInfo(mapId)
        if name then return name end
    end
    return "Unknown (" .. tostring(mapId) .. ")"
end

local function FormatFullName(name, realm)
    name = tostring(name or "")
    realm = tostring(realm or "")
    if name == "" then return "Unknown" end
    if realm ~= "" and not name:find("-", 1, true) then
        return name .. "-" .. realm
    end
    return name
end

---@param item table
---@return string|nil coloredLink
local function GetColoredItemLink(item)
    if type(item) ~= "table" then return nil end
    local link = item.link
    if type(link) == "string" and link:find("|c", 1, true) and link:find("|Hitem:", 1, true) then
        return link
    end

    local itemId = tonumber(item.itemId)
    if not itemId and type(link) == "string" then
        itemId = tonumber(link:match("item:(%d+):")) or tonumber(link:match("Hitem:(%d+):"))
    end

    if itemId and itemId > 0 then
        local C_Item = _G.C_Item
        if C_Item and type(C_Item.GetItemInfo) == "function" then
            local info = C_Item.GetItemInfo(itemId)
            if type(info) == "table" and type(info.itemLink) == "string" and info.itemLink ~= "" then
                return info.itemLink
            end
        end

        local _, full = GetItemInfo(itemId)
        if type(full) == "string" and full ~= "" then
            return full
        end
    end

    if type(link) == "string" and link ~= "" then
        return link
    end
    return nil
end

local function FormatAffixes(affixes)
    if type(affixes) ~= "table" or #affixes == 0 then
        return "—"
    end

    local api = MythicPlusModule and MythicPlusModule.API
    local C_ChallengeMode = _G.C_ChallengeMode
    local parts = {}
    for _, id in ipairs(affixes) do
        local affixName
        if api and type(api.GetAffixInfo) == "function" then
            local name = api:GetAffixInfo(id)
            if type(name) == "string" and name ~= "" then
                affixName = name
            end
        elseif C_ChallengeMode and type(C_ChallengeMode.GetAffixInfo) == "function" then
            local ok, name = pcall(C_ChallengeMode.GetAffixInfo, id)
            if ok and type(name) == "string" and name ~= "" then
                affixName = name
            end
        end
        parts[#parts + 1] = affixName or tostring(id)
    end

    return table.concat(parts, ", ")
end

local function EnsureRunDetailsFrame(panel)
    if Runs.DetailsFrame then
        return Runs.DetailsFrame
    end
    if panel and panel.__twichuiRunDetailsFrame then
        return panel.__twichuiRunDetailsFrame
    end

    local frame = CreateFrame("Frame", "TwichUI_RunDetailsFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetFrameLevel(500)
    frame:SetClampedToScreen(true)
    frame:SetSize(520, 460)
    frame:SetPoint("CENTER")
    frame:Hide()

    if E and frame.SetTemplate then
        -- Use an opaque template for readability.
        frame:SetTemplate("Default")
    else
        frame:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 1)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(50)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if frame:IsMovable() then
            frame:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local headerBG = header:CreateTexture(nil, "BACKGROUND")
    headerBG:SetAllPoints()
    headerBG:SetColorTexture(1, 1, 1, 0.04)
    frame.Header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 10, -8)
    title:SetJustifyH("LEFT")
    title:SetText(Accent("Run Details"))
    frame.Title = title

    local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("")
    frame.Subtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", 2, 2)
    if UI and UI.SkinCloseButton then
        UI.SkinCloseButton(close)
    end
    close:SetScript("OnClick", function() frame:Hide() end)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -58)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -58)
    divider:SetColorTexture(1, 1, 1, 0.08)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -66)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 12)
    if UI and UI.SkinScrollBar then
        UI.SkinScrollBar(scroll)
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    frame.Scroll = scroll
    frame.Content = content

    frame.LabelFontStrings = {}
    function frame:ApplyLabelColors()
        local r, g, b = GetRunDetailsLabelColor()
        for _, fs in ipairs(self.LabelFontStrings or {}) do
            if fs and fs.SetTextColor then
                fs:SetTextColor(r, g, b)
            end
        end
    end

    local function CreateKV(y, label)
        local l = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        l:SetJustifyH("LEFT")
        l:SetText(tostring(label))
        table.insert(frame.LabelFontStrings, l)

        local v = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPLEFT", l, "TOPRIGHT", 8, 0)
        v:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        v:SetJustifyH("LEFT")
        v:SetText("")
        return v
    end

    frame.Fields = {}
    frame.Fields.date = CreateKV(0, "Date:")
    frame.Fields.time = CreateKV(-18, "Time:")
    frame.Fields.onTime = CreateKV(-36, "Timed:")
    frame.Fields.abandoned = CreateKV(-54, "Abandoned:")
    frame.Fields.upgrade = CreateKV(-72, "Chest:")
    frame.Fields.deaths = CreateKV(-90, "Deaths:")
    frame.Fields.score = CreateKV(-108, "Score:")
    frame.Fields.affixes = CreateKV(-126, "Affixes:")

    local lootHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lootHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -152)
    lootHeader:SetText("Loot")
    frame.LootHeader = lootHeader
    table.insert(frame.LabelFontStrings, lootHeader)

    local lootList = CreateFrame("Frame", nil, content)
    lootList:SetPoint("TOPLEFT", lootHeader, "BOTTOMLEFT", 0, -6)
    lootList:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    lootList:SetHeight(1)
    frame.LootList = lootList

    local groupHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupHeader:SetPoint("TOPLEFT", lootList, "BOTTOMLEFT", 0, -14)
    groupHeader:SetText("Group")
    frame.GroupHeader = groupHeader
    table.insert(frame.LabelFontStrings, groupHeader)

    local groupList = CreateFrame("Frame", nil, content)
    groupList:SetPoint("TOPLEFT", groupHeader, "BOTTOMLEFT", 0, -6)
    groupList:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    groupList:SetHeight(1)
    frame.GroupList = groupList

    local groupFallbackText = groupList:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    groupFallbackText:SetPoint("TOPLEFT", groupList, "TOPLEFT", 0, 0)
    groupFallbackText:SetPoint("RIGHT", groupList, "RIGHT", 0, 0)
    groupFallbackText:SetJustifyH("LEFT")
    groupFallbackText:SetJustifyV("TOP")
    groupFallbackText:SetText("")
    frame.GroupFallbackText = groupFallbackText

    frame.GroupRows = {}

    local GROUP_ROW_HEIGHT = 44
    local GROUP_ICON_SIZE = 28

    local function EnsureGroupRow(i)
        local row = frame.GroupRows[i]
        if row then
            return row
        end

        row = CreateFrame("Frame", nil, groupList)
        row:SetHeight(GROUP_ROW_HEIGHT)
        row:SetPoint("LEFT", groupList, "LEFT", 0, 0)
        row:SetPoint("RIGHT", groupList, "RIGHT", 0, 0)

        local iconFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        iconFs:SetPoint("LEFT", row, "LEFT", 0, 0)
        iconFs:SetWidth(GROUP_ICON_SIZE + 6)
        iconFs:SetJustifyH("LEFT")
        row.Icon = iconFs

        local roleFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleFs:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        roleFs:SetJustifyH("RIGHT")
        row.Role = roleFs

        local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameFs:SetPoint("TOPLEFT", iconFs, "TOPRIGHT", 6, -2)
        nameFs:SetPoint("RIGHT", roleFs, "LEFT", -8, 0)
        nameFs:SetJustifyH("LEFT")
        row.Name = nameFs

        local specFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        specFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -2)
        specFs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        specFs:SetJustifyH("LEFT")
        specFs:SetTextColor(0.8, 0.8, 0.8)
        row.Spec = specFs

        frame.GroupRows[i] = row
        return row
    end

    local function HideGroupRows(from)
        for i = from or 1, #frame.GroupRows do
            frame.GroupRows[i]:Hide()
        end
    end

    local function NormalizeClassFileToken(v)
        if type(v) ~= "string" or v == "" then
            return nil
        end
        local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
        if not RAID_CLASS_COLORS then
            return nil
        end

        if RAID_CLASS_COLORS[v] then
            return v
        end
        local up = v:upper()
        if RAID_CLASS_COLORS[up] then
            return up
        end

        local male = _G.LOCALIZED_CLASS_NAMES_MALE
        if type(male) == "table" then
            for token, localized in pairs(male) do
                if localized == v then
                    return token
                end
            end
        end
        local female = _G.LOCALIZED_CLASS_NAMES_FEMALE
        if type(female) == "table" then
            for token, localized in pairs(female) do
                if localized == v then
                    return token
                end
            end
        end

        return nil
    end

    local GetSpecializationInfoByID = _G.GetSpecializationInfoByID

    ---@param specId any
    ---@return string|nil
    local function TryGetSpecNameFromId(specId)
        if type(specId) ~= "number" or specId <= 0 then
            return nil
        end
        if type(GetSpecializationInfoByID) ~= "function" then
            return nil
        end
        local ok, _, specName = pcall(GetSpecializationInfoByID, specId)
        if ok and type(specName) == "string" and specName ~= "" then
            return specName
        end
        return nil
    end

    ---@param specStr any
    ---@param classFile any
    ---@return string|nil
    local function NormalizeSpecString(specStr, classFile)
        if type(specStr) ~= "string" then
            return nil
        end
        local s = specStr:gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then
            return nil
        end

        local classToken = NormalizeClassFileToken(classFile)
        if classToken then
            local lastWord = s:match("([^%s]+)$")
            local lastToken = NormalizeClassFileToken(lastWord)
            if lastToken and lastToken == classToken then
                local trimmed = s:sub(1, #s - #lastWord):gsub("%s+$", "")
                if trimmed ~= "" then
                    return trimmed
                end
            end
        end

        return s
    end

    ---@param member table
    ---@param classFile any
    ---@return string
    local function GetMemberSpecDisplay(member, classFile)
        local spec = NormalizeSpecString(member.spec, classFile)
        if spec then
            return spec
        end

        spec = NormalizeSpecString(member.specName, classFile)
        if spec then
            return spec
        end

        local specId = nil
        if type(member.spec) == "number" then
            specId = member.spec
        elseif type(member.specId) == "number" then
            specId = member.specId
        elseif type(member.specID) == "number" then
            specId = member.specID
        elseif type(member.specializationID) == "number" then
            specId = member.specializationID
        elseif type(member.specializationId) == "number" then
            specId = member.specializationId
        end

        local fromId = TryGetSpecNameFromId(specId)
        if fromId then
            return fromId
        end

        return "—"
    end

    local function GetClassIconString(classFile, size)
        classFile = NormalizeClassFileToken(classFile)
        if not classFile then
            return nil
        end
        if Textures and type(Textures.GetClassTextureString) == "function" then
            return Textures:GetClassTextureString(classFile, size or GROUP_ICON_SIZE)
        end
        return nil
    end

    frame.LootRows = {}

    local function ClearLootRows()
        for _, r in ipairs(frame.LootRows) do
            r:Hide()
        end
    end

    local function EnsureLootRow(i)
        local r = frame.LootRows[i]
        if r then
            return r
        end

        r = CreateFrame("Button", nil, lootList)
        r:SetHeight(18)
        r:SetPoint("LEFT", lootList, "LEFT", 0, 0)
        r:SetPoint("RIGHT", lootList, "RIGHT", 0, 0)
        r:RegisterForClicks("LeftButtonUp")

        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", r, "LEFT", 0, 0)
        fs:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        r.Text = fs

        r:SetScript("OnEnter", function(self)
            if not self.link then return end
            if GameTooltip and GameTooltip.SetOwner and GameTooltip.SetHyperlink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.link)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        r:SetScript("OnClick", function(self)
            if not self.link then return end
            if ChatEdit_InsertLink then
                ChatEdit_InsertLink(self.link)
            end
        end)

        frame.LootRows[i] = r
        return r
    end

    function frame:SetRun(runData)
        if type(runData) ~= "table" then
            return
        end

        if self.ApplyLabelColors then
            self:ApplyLabelColors()
        end

        local dungeon = GetDungeonName(runData)
        local level = runData.level and ("+" .. tostring(runData.level)) or "—"
        self.Title:SetText(Accent(dungeon) .. " " .. level)

        local sub = {}
        if runData.date then
            sub[#sub + 1] = tostring(runData.date)
        elseif runData.timestamp then
            sub[#sub + 1] = FormatDate(runData.timestamp)
        end
        self.Subtitle:SetText(table.concat(sub, "  •  "))

        self.Fields.date:SetText(runData.date or FormatDate(runData.timestamp))
        self.Fields.score:SetText(tostring(runData.score or 0))

        local timeText = FormatTime(runData.time)
        do
            local ScoreCalculator = MythicPlusModule and MythicPlusModule.ScoreCalculator
            local getPar = ScoreCalculator and ScoreCalculator.GetParTimeSeconds
            local parMapId = runData.mapChallengeModeID or runData.mapChallengeModeId or runData.challengeModeID or
                runData.challengeModeId or runData.mapId
            local parTime = (type(getPar) == "function" and parMapId) and getPar(parMapId) or nil
            if parTime and parTime > 0 then
                if runData.time then
                    local delta = (tonumber(runData.time) or 0) - parTime
                    local deltaTxt = FormatSignedTimeDelta(delta)
                    if CT and CT.TWICH then
                        deltaTxt = delta <= 0 and Color(CT.TWICH.TEXT_SUCCESS, deltaTxt) or
                            Color(CT.TWICH.TEXT_ERROR, deltaTxt)
                    end
                    timeText = timeText .. " / " .. FormatTime(parTime) .. " (" .. deltaTxt .. ")"
                else
                    timeText = timeText .. " / " .. FormatTime(parTime)
                end
            end
        end
        self.Fields.time:SetText(timeText)

        local isAbandoned = (runData.abandoned == true)

        if isAbandoned then
            self.Fields.onTime:SetText("—")
        elseif runData.onTime == true and CT and CT.TWICH then
            self.Fields.onTime:SetText(Color(CT.TWICH.TEXT_SUCCESS, "Yes"))
        elseif runData.onTime == false and CT and CT.TWICH then
            self.Fields.onTime:SetText(Color(CT.TWICH.TEXT_ERROR, "No"))
        else
            self.Fields.onTime:SetText((runData.onTime == true and "Yes") or (runData.onTime == false and "No") or "—")
        end

        if self.Fields.abandoned then
            if isAbandoned and CT and CT.TWICH then
                self.Fields.abandoned:SetText(Color(CT.TWICH.TEXT_ERROR, "Yes"))
            elseif (not isAbandoned) and CT and CT.TWICH then
                self.Fields.abandoned:SetText(Color(CT.TWICH.TEXT_SUCCESS, "No"))
            else
                self.Fields.abandoned:SetText(isAbandoned and "Yes" or "No")
            end
        end

        self.Fields.upgrade:SetText((not isAbandoned and runData.upgrade) and ("+" .. tostring(runData.upgrade)) or "—")
        self.Fields.deaths:SetText(tostring(runData.deaths or 0))
        self.Fields.affixes:SetText(FormatAffixes(runData.affixes))

        local roster = nil
        if type(runData.groupStartRoster) == "table" and #runData.groupStartRoster > 0 then
            roster = runData.groupStartRoster
        elseif type(runData.groupRoster) == "table" and #runData.groupRoster > 0 then
            roster = runData.groupRoster
        elseif type(runData.groupStart) == "table" and #runData.groupStart > 0 then
            roster = runData.groupStart
        elseif type(runData.group) == "table" and #runData.group > 0 then
            roster = runData.group
        end

        local shownRows = 0
        if type(roster) == "table" and #roster > 0 then
            local tank, healer, dps, other = {}, {}, {}, {}
            for _, member in ipairs(roster) do
                if type(member) == "table" then
                    local role = tostring(member.role or "")
                    if role == "TANK" then
                        tank[#tank + 1] = member
                    elseif role == "HEALER" then
                        healer[#healer + 1] = member
                    elseif role == "DAMAGER" or role == "DPS" then
                        dps[#dps + 1] = member
                    else
                        other[#other + 1] = member
                    end
                end
            end

            local ordered = {}
            for _, m in ipairs(tank) do ordered[#ordered + 1] = m end
            for _, m in ipairs(healer) do ordered[#ordered + 1] = m end
            for _, m in ipairs(dps) do ordered[#ordered + 1] = m end
            for _, m in ipairs(other) do ordered[#ordered + 1] = m end

            for i, member in ipairs(ordered) do
                local row = EnsureGroupRow(i)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", self.GroupList, "TOPLEFT", 0, -((i - 1) * GROUP_ROW_HEIGHT))
                row:SetPoint("RIGHT", self.GroupList, "RIGHT", 0, 0)

                local role = tostring(member.role or "")
                local roleLabel = (role == "TANK" and "Tank") or (role == "HEALER" and "Healer") or
                    ((role == "DAMAGER" or role == "DPS") and "DPS") or ""
                row.Role:SetText(roleLabel ~= "" and Accent(roleLabel) or "")

                local classFile = member.classFile or member.class
                if type(classFile) ~= "string" or classFile == "" then
                    classFile = nil
                end
                if not classFile and type(member.spec) == "string" and member.spec ~= "" then
                    classFile = member.spec:match("([^%s]+)$")
                end

                local fullName = FormatFullName(member.name, member.realm)
                row.Name:SetText(fullName)

                local iconStr = GetClassIconString(classFile, GROUP_ICON_SIZE)
                row.Icon:SetText((type(iconStr) == "string" and iconStr) or "")

                row.Spec:SetText(GetMemberSpecDisplay(member, classFile))

                local ctoken = NormalizeClassFileToken(classFile)
                local colors = _G.RAID_CLASS_COLORS
                local c = colors and ctoken and colors[ctoken] or nil
                if c and type(c.r) == "number" then
                    row.Name:SetTextColor(c.r, c.g, c.b)
                else
                    row.Name:SetTextColor(1, 1, 1)
                end

                row:Show()
                shownRows = i
            end
            HideGroupRows(shownRows + 1)
        else
            HideGroupRows(1)
        end

        if shownRows > 0 then
            self.GroupFallbackText:SetText("")
            self.GroupFallbackText:Hide()
            self.GroupList:SetHeight(shownRows * GROUP_ROW_HEIGHT)
        else
            local groupLines = {}
            local g = (type(runData.groupStart) == "table" and runData.groupStart) or runData.group
            if type(g) == "table" then
                if g.tank then groupLines[#groupLines + 1] = "Tank: " .. tostring(g.tank) end
                if g.healer then groupLines[#groupLines + 1] = "Healer: " .. tostring(g.healer) end
                local i = 1
                while g["dps" .. tostring(i)] do
                    groupLines[#groupLines + 1] = "DPS: " .. tostring(g["dps" .. tostring(i)])
                    i = i + 1
                    if i > 10 then break end
                end
            end
            if #groupLines == 0 then
                groupLines[1] = "—"
            end
            self.GroupFallbackText:SetText(table.concat(groupLines, "\n"))
            self.GroupFallbackText:Show()
            self.GroupList:SetHeight(math.max(GROUP_ROW_HEIGHT,
                (self.GroupFallbackText:GetStringHeight() or GROUP_ROW_HEIGHT)))
        end

        ClearLootRows()
        local loot = runData.loot
        local y = -0
        local anchor = self.LootList
        local anyLoot = false

        if type(loot) == "table" and #loot > 0 then
            for i, item in ipairs(loot) do
                local link = type(item) == "table" and GetColoredItemLink(item) or nil
                local qty = type(item) == "table" and tonumber(item.quantity) or nil
                if type(link) == "string" and link ~= "" then
                    anyLoot = true
                    local row = EnsureLootRow(i)
                    row.link = link
                    local text = link
                    if qty and qty > 1 then
                        text = text .. " x" .. tostring(qty)
                    end
                    row.Text:SetText(text)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
                    row:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
                    row:Show()
                    y = y + 18
                end
            end
        end

        if not anyLoot then
            local row = EnsureLootRow(1)
            row.link = nil
            row.Text:SetText("—")
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
            row:SetPoint("RIGHT", anchor, "RIGHT", 0, 0)
            row:Show()
            y = 18
        end

        self.LootList:SetHeight(math.max(y, 1))

        local bottomY = -62
        -- Rough height accounting: static fields (~220) + group text height + loot height
        local gh = math.max(20, (self.GroupList:GetHeight() or 20))
        local totalHeight = 62 + 190 + y + 30 + gh + 20
        content:SetHeight(math.max(totalHeight, 1))
        content:SetWidth(scroll:GetWidth() - 20)
    end

    frame:ApplyLabelColors()

    frame:SetScript("OnShow", function()
        -- Close if main window is hidden
        if MythicPlusModule and MythicPlusModule.MainWindow and type(MythicPlusModule.MainWindow.IsShown) == "function" then
            if not MythicPlusModule.MainWindow:IsShown() then
                frame:Hide()
            end
        end
    end)

    if panel then
        panel.__twichuiRunDetailsFrame = frame
    end
    Runs.DetailsFrame = frame
    return frame
end

local function CreateRunsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:Hide() -- Ensure OnShow fires when the window manager shows it

    -- Filter Input
    local filterBox = CreateFrame("EditBox", nil, panel)
    filterBox:SetSize(150, 20)
    filterBox:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)
    filterBox:SetAutoFocus(false)
    filterBox:SetTextInsets(5, 5, 0, 0)
    filterBox:SetFontObject("GameFontHighlight")

    if UI then
        UI.SkinEditBox(filterBox)
    else
        -- Basic fallback
        local bg = filterBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    end

    -- Placeholder text
    filterBox.placeholder = filterBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    filterBox.placeholder:SetPoint("LEFT", filterBox, "LEFT", 5, 0)
    filterBox.placeholder:SetText("Filter by Dungeon...")
    filterBox.placeholder:SetTextColor(0.5, 0.5, 0.5)

    filterBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
        panel.__twichuiFilterText = self:GetText()
        Runs:Refresh(panel)
    end)

    -- Summary Text
    local summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summary:SetPoint("RIGHT", panel, "RIGHT", -PANEL_PADDING, 0)
    summary:SetPoint("TOP", filterBox, "TOP", 0, 0)
    summary:SetPoint("BOTTOM", filterBox, "BOTTOM", 0, 0)
    summary:SetJustifyH("RIGHT")
    panel.summary = summary

    filterBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Header Row
    local header = CreateFrame("Frame", nil, panel)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING - 25) -- Moved down for filter
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PANEL_PADDING, -PANEL_PADDING - 25)

    local headerBG = header:CreateTexture(nil, "BACKGROUND")
    headerBG:SetAllPoints()
    headerBG:SetColorTexture(1, 1, 1, 0.1)

    local xOffset = 0
    for _, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetHeight(HEADER_HEIGHT)
        btn:SetWidth(col.width)
        btn:SetPoint("LEFT", header, "LEFT", xOffset, 0)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetText(col.label)
        text:SetJustifyH(col.justify)
        -- Add padding to align with row data
        text:SetPoint("LEFT", btn, "LEFT", 4, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        btn.Text = text

        -- Sorting Logic
        btn:SetScript("OnClick", function()
            local currentSort = panel.__twichuiSortBy
            local currentAsc = panel.__twichuiSortAsc

            if currentSort == col.key then
                panel.__twichuiSortAsc = not currentAsc
            else
                panel.__twichuiSortBy = col.key
                -- Default sort direction
                if col.key == "dungeon" or col.key == "date" then
                    panel.__twichuiSortAsc = true
                else
                    panel.__twichuiSortAsc = false -- Descending for numbers
                end
            end
            Runs:Refresh(panel)
        end)

        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if self.Text then self.Text:SetTextColor(1, 1, 1) end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.Text then self.Text:SetTextColor(1, 0.82, 0) end
        end)

        xOffset = xOffset + col.width + 2
    end

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, PANEL_PADDING)

    -- ElvUI scrollbar skinning (best-effort)
    if UI then
        UI.SkinScrollBar(scrollFrame)
    end

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1) -- Initial size, will be updated
    scrollFrame:SetScrollChild(content)

    panel.content = content
    panel.rows = {}

    -- Update content width when scrollframe resizes
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        content:SetWidth(w)
        -- Also update rows if they exist
        if panel.rows then
            for _, row in ipairs(panel.rows) do
                row:SetWidth(w)
            end
        end
    end)

    panel:SetScript("OnShow", function()
        -- Delay refresh slightly to allow layout to settle
        C_Timer.After(0.05, function()
            Runs:Refresh(panel)
        end)
    end)

    return panel
end

function Runs:ShowDetails(runData)
    local panel = nil
    if MythicPlusModule.MainWindow then
        panel = MythicPlusModule.MainWindow:GetPanelFrame("runs")
    end

    local details = EnsureRunDetailsFrame(panel)
    details:SetRun(runData)
    details:Show()
end

local function EnsureEasyMenu()
    local easyMenuFunc = rawget(_G, "EasyMenu")
    if type(easyMenuFunc) == "function" then
        return easyMenuFunc
    end

    if InCombatLockdown and InCombatLockdown() then return nil end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_Deprecated")
    elseif UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_Deprecated")
    end

    return rawget(_G, "EasyMenu")
end

local function ShowContextMenu(runData, panel)
    if not runData then return end

    local details = string.format("%s (+%s)\nDate: %s\nScore: %s",
        GetDungeonName(runData.mapId),
        runData.level,
        FormatDate(runData.timestamp),
        runData.score or 0)

    if MenuUtil then
        MenuUtil.CreateContextMenu(UIParent, function(owner, root)
            root:CreateTitle("Run Options")
            root:CreateButton("|cffff0000Delete Run|r", function()
                StaticPopup_Show("TWICHUI_CONFIRM_DELETE_RUN", details, nil, { runId = runData.id, panel = panel })
            end)
            root:CreateButton("Cancel", function() end)
        end)
        return
    end

    local easyMenuFunc = EnsureEasyMenu()
    if not easyMenuFunc then return end

    local menu = {
        { text = "Run Options", isTitle = true,      notCheckable = true },
        {
            text = "|cffff0000Delete Run|r",
            notCheckable = true,
            func = function()
                StaticPopup_Show("TWICHUI_CONFIRM_DELETE_RUN", details, nil, { runId = runData.id, panel = panel })
            end
        },
        { text = "Cancel",      notCheckable = true, func = function() end }
    }

    local menuFrame = CreateFrame("Frame", "TwichUIRunsContextMenu", UIParent, "UIDropDownMenuTemplate")
    easyMenuFunc(menu, menuFrame, "cursor", 0, 0, "MENU")
end

function Runs:Refresh(panel)
    if not panel or not panel.content then return end

    local allRuns = Database:GetRuns()
    local runs = {}

    -- Filter
    local filterText = panel.__twichuiFilterText and panel.__twichuiFilterText:lower() or ""
    if filterText ~= "" then
        for _, run in ipairs(allRuns) do
            local name = GetDungeonName(run.mapId):lower()
            if name:find(filterText, 1, true) then
                table.insert(runs, run)
            end
        end
    else
        -- Copy array to avoid modifying DB order during sort
        for _, run in ipairs(allRuns) do
            table.insert(runs, run)
        end
    end

    -- Sort
    local sortBy = panel.__twichuiSortBy or "date"
    local sortAsc = panel.__twichuiSortAsc
    if panel.__twichuiSortBy == nil then sortAsc = false end -- Default desc for date

    table.sort(runs, function(a, b)
        local vA, vB
        if sortBy == "dungeon" then
            vA = GetDungeonName(a.mapId)
            vB = GetDungeonName(b.mapId)
        else
            vA = a[sortBy]
            vB = b[sortBy]
        end

        -- Handle nils
        if vA == nil then vA = 0 end
        if vB == nil then vB = 0 end

        if vA == vB then
            return a.timestamp > b.timestamp -- Secondary sort by date desc
        end

        if sortAsc then
            return vA < vB
        else
            return vA > vB
        end
    end)

    -- Update Summary
    if panel.summary then
        panel.summary:SetText("Total Runs: " .. #runs)
    end

    -- Ensure content width matches scrollframe
    local scrollFrame = panel.content:GetParent()
    local width = scrollFrame:GetWidth()

    -- If width is invalid, try to use parent width or default, and schedule a retry
    if width <= 1 then
        width = panel:GetWidth() - 26 -- Approximate scrollbar width
        if width <= 1 then
            -- Still no width, schedule retry
            C_Timer.After(0.1, function() Runs:Refresh(panel) end)
            return
        end
    end

    panel.content:SetWidth(width)

    local yOffset = 0

    -- Ensure enough rows
    for i, runData in ipairs(runs) do
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, panel.content)
            row:SetHeight(ROW_HEIGHT)
            row:SetWidth(panel.content:GetWidth())

            -- Create cells
            row.cells = {}
            local xOffset = 0
            for _, col in ipairs(COLUMNS) do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                -- Add padding to align with header
                fs:SetPoint("LEFT", row, "LEFT", xOffset + 4, 0)
                fs:SetWidth(col.width - 8)
                fs:SetJustifyH(col.justify)
                row.cells[col.key] = fs
                xOffset = xOffset + col.width + 2
            end

            -- Background
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            bg:SetColorTexture(1, 1, 1, 0.05)
            row.bg = bg

            -- Highlight
            local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            highlight:SetAllPoints(row)
            highlight:SetColorTexture(1, 1, 1, 0.1)
            highlight:Hide()
            row.highlight = highlight

            row:SetScript("OnEnter", function(self)
                self.highlight:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.highlight:Hide()
            end)

            -- Context Menu
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and self.runData then
                    local details = EnsureRunDetailsFrame(panel)
                    details:SetRun(self.runData)
                    details:Show()
                    return
                end
                if button == "RightButton" and self.runData then
                    ShowContextMenu(self.runData, panel)
                end
            end)

            panel.rows[i] = row
        end

        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -yOffset)
        row:SetWidth(panel.content:GetWidth()) -- Ensure row width is correct
        row:Show()

        row.runData = runData

        -- Populate Data
        row.cells.date:SetText(FormatDate(runData.timestamp))
        row.cells.dungeon:SetText(GetDungeonName(runData.mapId))
        row.cells.level:SetText("+" .. tostring(runData.level))
        row.cells.time:SetText(FormatTime(runData.time))
        row.cells.score:SetText(tostring(runData.score or 0))

        -- Upgrade Column Coloring
        local upgrade = runData.upgrade
        row.cells.upgrade:SetText(upgrade and ("+" .. upgrade) or "—")
        if upgrade == 3 then
            row.cells.upgrade:SetTextColor(0.64, 0.21, 0.93) -- Purple
        elseif upgrade == 2 then
            row.cells.upgrade:SetTextColor(0, 0.44, 0.87)    -- Blue
        elseif upgrade == 1 then
            row.cells.upgrade:SetTextColor(0, 1, 0)          -- Green
        else
            row.cells.upgrade:SetTextColor(1, 1, 1)          -- White
        end

        -- Alternating row colors
        if i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.02)
        else
            row.bg:SetColorTexture(1, 1, 1, 0.05)
        end

        yOffset = yOffset + ROW_HEIGHT
    end

    -- Hide unused rows
    for i = #runs + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    panel.content:SetHeight(math.max(1, yOffset))
end

function Runs:Initialize()
    if self.initialized then return end
    self.initialized = true

    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        MythicPlusModule.MainWindow:RegisterPanel("runs", function(parent, window)
            return CreateRunsPanel(parent)
        end, nil, nil, { label = "Runs", order = 30 })
    end
end
