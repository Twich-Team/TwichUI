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

local function FormatDate(timestamp)
    if not timestamp then return "—" end
    return date("%m/%d/%Y", timestamp)
end

local function GetDungeonName(mapId)
    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name = C_ChallengeMode.GetMapUIInfo(mapId)
        if name then return name end
    end
    return "Unknown (" .. tostring(mapId) .. ")"
end

local function FormatAffixes(affixes)
    if type(affixes) ~= "table" or #affixes == 0 then
        return "—"
    end

    local C_ChallengeMode = _G.C_ChallengeMode
    local parts = {}
    for _, id in ipairs(affixes) do
        local affixName
        if C_ChallengeMode and type(C_ChallengeMode.GetAffixInfo) == "function" then
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
    if panel and panel.__twichuiRunDetailsFrame then
        return panel.__twichuiRunDetailsFrame
    end

    local parent = (MythicPlusModule and MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.frame) or UIParent
    local frame = CreateFrame("Frame", "TwichUI_RunDetailsFrame", parent, "BackdropTemplate")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetSize(520, 460)
    frame:SetPoint("CENTER")
    frame:Hide()

    if E and frame.SetTemplate then
        frame:SetTemplate("Transparent")
    else
        frame:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.85)
        frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    title:SetJustifyH("LEFT")
    title:SetText("Run Details")
    frame.Title = title

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("")
    frame.Subtitle = subtitle

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if UI and UI.SkinCloseButton then
        UI.SkinCloseButton(close)
    end
    close:SetScript("OnClick", function() frame:Hide() end)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -54)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -54)
    divider:SetColorTexture(1, 1, 1, 0.08)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 12)
    if UI and UI.SkinScrollBar then
        UI.SkinScrollBar(scroll)
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    frame.Scroll = scroll
    frame.Content = content

    local function CreateKV(y, label)
        local l = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        l:SetJustifyH("LEFT")
        l:SetText(label)

        local v = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPLEFT", l, "TOPRIGHT", 8, 0)
        v:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        v:SetJustifyH("LEFT")
        v:SetText("")
        return v
    end

    frame.Fields = {}
    frame.Fields.date = CreateKV(0, "Date:")
    frame.Fields.patch = CreateKV(-18, "Patch:")
    frame.Fields.mapId = CreateKV(-36, "Map ID:")
    frame.Fields.level = CreateKV(-54, "Key:")
    frame.Fields.score = CreateKV(-72, "Score:")
    frame.Fields.time = CreateKV(-90, "Time:")
    frame.Fields.onTime = CreateKV(-108, "On Time:")
    frame.Fields.upgrade = CreateKV(-126, "Upgrade:")
    frame.Fields.deaths = CreateKV(-144, "Deaths:")
    frame.Fields.affixes = CreateKV(-162, "Affixes:")

    local groupHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -190)
    groupHeader:SetText("Group")
    frame.GroupHeader = groupHeader

    local groupText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    groupText:SetPoint("TOPLEFT", groupHeader, "BOTTOMLEFT", 0, -6)
    groupText:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    groupText:SetJustifyH("LEFT")
    groupText:SetJustifyV("TOP")
    groupText:SetText("")
    frame.GroupText = groupText

    local lootHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lootHeader:SetPoint("TOPLEFT", groupText, "BOTTOMLEFT", 0, -14)
    lootHeader:SetText("Loot")
    frame.LootHeader = lootHeader

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

        r = CreateFrame("Button", nil, content)
        r:SetHeight(18)
        r:SetPoint("LEFT", content, "LEFT", 0, 0)
        r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
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

        local dungeon = GetDungeonName(runData.mapId)
        local level = runData.level and ("+" .. tostring(runData.level)) or "—"
        self.Title:SetText(dungeon .. " " .. level)

        local sub = {}
        if runData.date then
            sub[#sub + 1] = tostring(runData.date)
        elseif runData.timestamp then
            sub[#sub + 1] = FormatDate(runData.timestamp)
        end
        if runData.patch then
            sub[#sub + 1] = "Patch " .. tostring(runData.patch)
        end
        if runData.id then
            sub[#sub + 1] = "ID " .. tostring(runData.id)
        end
        self.Subtitle:SetText(table.concat(sub, "  •  "))

        self.Fields.date:SetText(runData.date or FormatDate(runData.timestamp))
        self.Fields.patch:SetText(runData.patch or "—")
        self.Fields.mapId:SetText(tostring(runData.mapId or "—"))
        self.Fields.level:SetText(level)
        self.Fields.score:SetText(tostring(runData.score or 0))
        self.Fields.time:SetText(FormatTime(runData.time))
        self.Fields.onTime:SetText((runData.onTime == true and "Yes") or (runData.onTime == false and "No") or "—")
        self.Fields.upgrade:SetText(runData.upgrade and ("+" .. tostring(runData.upgrade)) or "—")
        self.Fields.deaths:SetText(tostring(runData.deaths or 0))
        self.Fields.affixes:SetText(FormatAffixes(runData.affixes))

        local groupLines = {}
        local g = runData.group
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
        self.GroupText:SetText(table.concat(groupLines, "\n"))

        ClearLootRows()
        local loot = runData.loot
        local y = -0
        local anchor = self.LootHeader
        local anyLoot = false

        if type(loot) == "table" and #loot > 0 then
            for i, item in ipairs(loot) do
                local link = type(item) == "table" and item.link or nil
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
                    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6 - y)
                    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
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
            row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
            row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            row:Show()
            y = 18
        end

        local bottomY = -62
        -- Rough height accounting: static fields (~220) + group text height + loot height
        local gh = math.max(20, (self.GroupText:GetStringHeight() or 20))
        local totalHeight = 62 + 190 + gh + 30 + y + 20
        content:SetHeight(math.max(totalHeight, 1))
        content:SetWidth(scroll:GetWidth() - 20)
    end

    frame:SetScript("OnShow", function()
        if panel and panel.IsShown and not panel:IsShown() then
            frame:Hide()
        end
    end)

    if panel then
        panel.__twichuiRunDetailsFrame = frame
    end
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

    local xOffset = 0
    for _, col in ipairs(COLUMNS) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetHeight(HEADER_HEIGHT)
        btn:SetWidth(col.width)
        btn:SetPoint("LEFT", header, "LEFT", xOffset, 0)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetText(col.label)
        text:SetJustifyH(col.justify)
        text:SetAllPoints(btn)
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
                fs:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                fs:SetWidth(col.width)
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
