--- Gold Per Hour Frame Module
--- Displays a live feed of looted items with sorting, grouping, and GPH statistics
--- Integrates with the GoldPerHourTracker for real-time updates

local T, W, I, C       = unpack(Twich)
---@type LootMonitorModule
local LM               = T:GetModule("LootMonitor")

---@type ConfigurationModule
local CM               = T:GetModule("Configuration")
---@type LoggerModule
local Logger           = T:GetModule("Logger")
---@type ToolsModule
local TM               = T:GetModule("Tools")
local TT               = TM.Text

-- LSM is backed by ElvUI's media library when available
local LSM              = T.Libs.LSM

-- Optional ElvUI integration for skinned buttons, etc.
local E                = _G.ElvUI and _G.ElvUI[1]
local Skins            = E and E.GetModule and E:GetModule("Skins", true)

--- Gold Per Hour Frame module
--- Manages the display frame for loot and statistics
---@class GoldPerHourFrame
---@field enabled boolean Whether the frame is visible and active
---@field frame Frame The main display frame
---@field scrollFrame ScrollFrame The scrollable content frame
---@field contentFrame Frame The frame containing all rows
---@field rows table<string, Frame> Indexed by itemLink, stores row frames
---@field statsFrame Frame The frame showing GPH statistics
---@field trackerCallbackID number ID of callback registered with tracker
---@field sortColumn string The currently sorted column ("name", "quantity", "method", "value")
---@field sortAscending boolean Whether sort is ascending (true) or descending (false)
local GPHFrame         = LM.GoldPerHourFrame or {}
LM.GoldPerHourFrame    = GPHFrame

--- Configuration entries for the Gold Per Hour Frame
---@class GoldPerHourFrameConfiguration
---@field ENABLED ConfigEntry Master enable/disable setting
---@field FRAME_WIDTH ConfigEntry Width of the frame in pixels
---@field FRAME_HEIGHT ConfigEntry Height of the frame in pixels
---@field FRAME_SCALE ConfigEntry Scale multiplier for the frame
---@field FRAME_ALPHA ConfigEntry Alpha transparency (0-1)
---@field HEADER_BG_COLOR ConfigEntry Header background color (r, g, b, a)
---@field HEADER_TEXT_COLOR ConfigEntry Header text color (r, g, b)
---@field ROW_HEIGHT ConfigEntry Height of each item row
---@field ROW_BG_COLOR ConfigEntry Row background color (r, g, b, a)
---@field ROW_TEXT_COLOR ConfigEntry Row text color (r, g, b)
---@field ROW_SPACING ConfigEntry Vertical spacing between rows
---@field STATS_LABEL_COLOR ConfigEntry Stats label color (r, g, b)
---@field STATS_VALUE_COLOR ConfigEntry Stats value color (r, g, b)
GPHFrame.CONFIGURATION = {
    ENABLED = { key = "lootMonitor.goldPerHourFrame.enabled", default = false },
    FRAME_WIDTH = { key = "lootMonitor.goldPerHourFrame.frameWidth", default = 500 },
    FRAME_HEIGHT = { key = "lootMonitor.goldPerHourFrame.frameHeight", default = 400 },
    FRAME_SCALE = { key = "lootMonitor.goldPerHourFrame.frameScale", default = 1.0 },
    FRAME_ALPHA = { key = "lootMonitor.goldPerHourFrame.frameAlpha", default = 1.0 },
    FRAME_TEXTURE = { key = "lootMonitor.goldPerHourFrame.frameTexture", default = "ElvUI Norm" },
    FRAME_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.frameBgColor", default = { r = 0.04, g = 0.04, b = 0.04, a = 0.9 } },
    FRAME_BORDER_TEXTURE = { key = "lootMonitor.goldPerHourFrame.frameBorderTexture", default = "ElvUI GlowBorder" },
    FRAME_BORDER_COLOR = { key = "lootMonitor.goldPerHourFrame.frameBorderColor", default = { r = 0.3, g = 0.3, b = 0.3, a = 1.0 } },

    -- Fonts
    BASE_FONT = { key = "lootMonitor.goldPerHourFrame.font", default = "Expressway" },
    TITLE_FONT_SIZE = { key = "lootMonitor.goldPerHourFrame.titleFontSize", default = 14 },
    HEADER_FONT_SIZE = { key = "lootMonitor.goldPerHourFrame.headerFontSize", default = 12 },
    ROW_FONT_SIZE = { key = "lootMonitor.goldPerHourFrame.rowFontSize", default = 11 },
    STATS_FONT_SIZE = { key = "lootMonitor.goldPerHourFrame.statsFontSize", default = 10 },

    -- Colors
    TITLE_TEXT_COLOR = { key = "lootMonitor.goldPerHourFrame.titleTextColor", default = { r = 1, g = 1, b = 1 } },
    HEADER_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.headerBgColor", default = { r = 0.08, g = 0.08, b = 0.08, a = 1.0 } },
    HEADER_TEXT_COLOR = { key = "lootMonitor.goldPerHourFrame.headerTextColor", default = { r = 0.9, g = 0.9, b = 0.9 } },

    -- Header and rows
    ROW_HEIGHT = { key = "lootMonitor.goldPerHourFrame.rowHeight", default = 22 },
    ROW_TEXTURE = { key = "lootMonitor.goldPerHourFrame.rowTexture", default = "ElvUI Norm" },
    ROW_BORDER_TEXTURE = { key = "lootMonitor.goldPerHourFrame.rowBorderTexture", default = "None" },
    ROW_BORDER_COLOR = { key = "lootMonitor.goldPerHourFrame.rowBorderColor", default = { r = 0, g = 0, b = 0, a = 1.0 } },
    ROW_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.rowBgColor", default = { r = 0.06, g = 0.06, b = 0.06, a = 1.0 } },
    ROW_TEXT_COLOR = { key = "lootMonitor.goldPerHourFrame.rowTextColor", default = { r = 0.9, g = 0.9, b = 0.9 } },
    ROW_VALUE_COLOR = { key = "lootMonitor.goldPerHourFrame.rowValueColor", default = { r = 1, g = 0.82, b = 0 } },
    ROW_HOVER_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.rowHoverBgColor", default = { r = 0.12, g = 0.12, b = 0.12, a = 1.0 } },
    ROW_SPACING = { key = "lootMonitor.goldPerHourFrame.rowSpacing", default = 0 },

    -- Scroll / loot area
    SCROLL_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.scrollBgColor", default = { r = 0.03, g = 0.03, b = 0.03, a = 0.9 } },

    -- Stats/footer
    STATS_BG_COLOR = { key = "lootMonitor.goldPerHourFrame.statsBgColor", default = { r = 0.06, g = 0.06, b = 0.06, a = 1.0 } },
    STATS_HEIGHT = { key = "lootMonitor.goldPerHourFrame.statsHeight", default = 55 },
    STATS_SPACING = { key = "lootMonitor.goldPerHourFrame.statsSpacing", default = 140 },
    STATS_LABEL_COLOR = { key = "lootMonitor.goldPerHourFrame.statsLabelColor", default = { r = 0.7, g = 0.7, b = 0.7 } },
    STATS_VALUE_COLOR = { key = "lootMonitor.goldPerHourFrame.statsValueColor", default = { r = 1, g = 0.82, b = 0 } },
}

--- Column definitions for the loot table
local COLUMNS          = {
    { key = "name",     label = "Item Name", width = 0.4 },
    { key = "quantity", label = "Qty",       width = 0.15, align = "CENTER" },
    { key = "method",   label = "Method",    width = 0.25 },
    { key = "value",    label = "Value",     width = 0.2,  align = "RIGHT" },
}

--- Initialize the frame module
function GPHFrame:Initialize()
    if self:IsEnabled() then return end

    local shouldEnable = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ENABLED)
    if shouldEnable then
        self:Enable()
    end
end

--- Check if the frame is currently enabled
---@return boolean enabled True if the frame is visible and active
function GPHFrame:IsEnabled()
    return self.enabled or false
end

--- Enable the frame
--- Creates the frame and registers for tracker updates
function GPHFrame:Enable()
    if self:IsEnabled() then return end
    self.enabled = true

    -- Initialize data structures
    self.rows = {}
    self.sortColumn = "name"
    self.sortAscending = false

    -- Load configuration
    local width = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FRAME_WIDTH)
    local height = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FRAME_HEIGHT)
    local scale = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FRAME_SCALE)
    local alpha = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.FRAME_ALPHA)

    -- Create the frame
    self:CreateFrame(width, height, scale, alpha)

    -- Register for tracker updates
    local GPH = LM.GoldPerHourTracker
    if GPH then
        self.trackerCallbackID = GPH:RegisterCallback(function(stats)
            self:OnTrackerUpdate(stats)
        end)
    end

    GPH:RequestImmediateUpdate()

    Logger.Debug("Gold per hour frame enabled")
end

--- Disable the frame
--- Hides the frame and unregisters from tracker updates
function GPHFrame:Disable()
    if not self:IsEnabled() then return end
    self.enabled = false

    if self.trackerCallbackID then
        local GPH = LM.GoldPerHourTracker
        if GPH then
            GPH:UnregisterCallback(self.trackerCallbackID)
        end
        self.trackerCallbackID = nil
    end

    if self.frame then
        self.frame:Hide()
    end

    Logger.Debug("Gold per hour frame disabled")
end

--- Create the main display frame and all its components
---@param width number Frame width in pixels
---@param height number Frame height in pixels
---@param scale number Frame scale multiplier
---@param alpha number Frame alpha (0-1)
function GPHFrame:CreateFrame(width, height, scale, alpha)
    local isNew = false
    if not self.frame then
        -- First-time creation of the main frame
        self.frame = CreateFrame("Frame", "TwichGPHFrame", UIParent, "BackdropTemplate")
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
        self.frame:SetMovable(true)
        self.frame:EnableMouse(true)
        self.frame:RegisterForDrag("LeftButton")
        self.frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
        self.frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
        isNew = true
    end

    -- Apply sizing/scale/alpha to frame before creating/laying out children
    self.frame:SetSize(width, height)
    self.frame:SetScale(scale)
    self.frame:SetAlpha(alpha)

    if isNew then
        -- Create child components once, now that the frame has a valid size
        self:CreateTitleBar()
        self:CreateColumnHeaders()
        self:CreateScrollFrame()
        self:CreateStatsFooter()
    end

    -- Resize and re-anchor child regions to match new frame size
    if self.titleBar then
        self.titleBar:SetSize(self.frame:GetWidth(), 30)
        self.titleBar:ClearAllPoints()
        self.titleBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    end

    if self.headerFrame then
        self.headerFrame:SetSize(self.frame:GetWidth() - 8, 25)
        self.headerFrame:ClearAllPoints()
        self.headerFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -30)
    end

    local statsHeight = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_HEIGHT.key,
        self.CONFIGURATION.STATS_HEIGHT.default)

    if self.scrollFrame then
        -- Height so scroll bottom meets stats top (no gap)
        self.scrollFrame:SetSize(self.frame:GetWidth() - 8, self.frame:GetHeight() - (statsHeight + 59))
        self.scrollFrame:ClearAllPoints()
        self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -55)
    end

    if self.statsFrame then
        self.statsFrame:SetSize(self.frame:GetWidth() - 8, statsHeight)
        self.statsFrame:ClearAllPoints()
        self.statsFrame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)
    end

    -- Apply textures/colors based on current configuration
    self:UpdateAllStyling()

    self.frame:Show()
end

--- Create the title bar with close button
function GPHFrame:CreateTitleBar()
    local titleBar = CreateFrame("Frame", nil, self.frame)
    titleBar:SetSize(self.frame:GetWidth(), 30)
    titleBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)

    self.titleBar = titleBar

    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local titleFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.TITLE_FONT_SIZE.key,
        self.CONFIGURATION.TITLE_FONT_SIZE.default)
    local titleColor = CM:GetProfileSettingSafe(self.CONFIGURATION.TITLE_TEXT_COLOR.key,
        self.CONFIGURATION.TITLE_TEXT_COLOR.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetFont(fontPath, titleFontSize, "OUTLINE")
    titleText:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
    titleText:SetText("Gold Per Hour - Loot Feed")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)

    self.titleText = titleText

    -- Elapsed time text (updated from tracker stats)
    local timeText = titleBar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(fontPath, titleFontSize - 1, "OUTLINE")
    timeText:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
    timeText:SetText("")
    timeText:SetPoint("RIGHT", titleBar, "RIGHT", -40, 0)

    self.timeText = timeText

    -- Close button (skinned like ElvUI)
    local closeButton = CreateFrame("Button", nil, titleBar)
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -5, -5)

    local closeText = closeButton:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(fontPath, math.max(titleFontSize + 2, titleFontSize), "OUTLINE")
    closeText:SetTextColor(1, 1, 1)
    closeText:SetText("×")
    closeText:SetPoint("CENTER", closeButton, "CENTER")

    closeButton:SetScript("OnEnter", function()
        closeText:SetTextColor(1, 0, 0)
    end)
    closeButton:SetScript("OnLeave", function()
        closeText:SetTextColor(1, 1, 1)
    end)
    closeButton:SetScript("OnClick", function()
        GPHFrame:Disable()
    end)
end

--- Create the column header row
function GPHFrame:CreateColumnHeaders()
    local headerFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    headerFrame:SetSize(self.frame:GetWidth() - 8, 25)
    headerFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -30)

    self.headerFrame = headerFrame
    self.headerColumns = {}

    local headerBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_BG_COLOR.key,
        self.CONFIGURATION.HEADER_BG_COLOR.default)

    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local headerFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_FONT_SIZE.key,
        self.CONFIGURATION.HEADER_FONT_SIZE.default)
    local headerTextColor = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_TEXT_COLOR.key,
        self.CONFIGURATION.HEADER_TEXT_COLOR.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    headerFrame:SetBackdrop({
        bgFile = LSM:Fetch("background", CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_TEXTURE.key,
            self.CONFIGURATION.FRAME_TEXTURE.default)),
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    headerFrame:SetBackdropColor(headerBgColor.r, headerBgColor.g, headerBgColor.b, headerBgColor.a)

    local frameWidth = headerFrame:GetWidth()
    local xOffset = 0

    for i, column in ipairs(COLUMNS) do
        local columnWidth = frameWidth * column.width

        local header = CreateFrame("Button", nil, headerFrame, "BackdropTemplate")
        header:SetSize(columnWidth, 25)
        header:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", xOffset, 0)
        header:SetBackdropColor(0, 0, 0, 0)

        local headerText = header:CreateFontString(nil, "OVERLAY")
        headerText:SetFont(fontPath, headerFontSize, "OUTLINE")
        headerText:SetTextColor(headerTextColor.r, headerTextColor.g, headerTextColor.b)
        headerText:SetText(column.label)
        headerText:SetWidth(columnWidth - 10)
        headerText:SetHeight(25)

        local align = column.align or "LEFT"
        if align == "LEFT" then
            headerText:SetPoint("LEFT", header, "LEFT", 5, 0)
        elseif align == "RIGHT" then
            headerText:SetPoint("RIGHT", header, "RIGHT", -5, 0)
        else
            headerText:SetPoint("CENTER", header, "CENTER", 0, 0)
        end
        headerText:SetJustifyH(align)

        header:SetScript("OnClick", function()
            self:SetSortColumn(column.key)
        end)
        table.insert(self.headerColumns, { button = header, text = headerText })

        xOffset = xOffset + columnWidth
    end
end

--- Create the scrollable content frame
function GPHFrame:CreateScrollFrame()
    self.scrollFrame = CreateFrame("ScrollFrame", nil, self.frame, "BackdropTemplate")
    self.scrollFrame:SetSize(self.frame:GetWidth() - 8, self.frame:GetHeight() - 120)
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -55)

    self.contentFrame = CreateFrame("Frame", nil, self.scrollFrame)
    self.contentFrame:SetSize(self.scrollFrame:GetWidth(), 1)
    self.contentFrame:SetPoint("TOPLEFT", self.scrollFrame, "TOPLEFT", 0, 0)

    self.scrollFrame:SetScrollChild(self.contentFrame)

    -- Apply initial styling to the scroll/loot area
    self:UpdateScrollStyling()
end

--- Create the statistics footer
function GPHFrame:CreateStatsFooter()
    local statsHeight = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_HEIGHT.key,
        self.CONFIGURATION.STATS_HEIGHT.default)

    self.statsFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.statsFrame:SetSize(self.frame:GetWidth() - 8, statsHeight)
    self.statsFrame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)

    local statsBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_BG_COLOR.key,
        self.CONFIGURATION.STATS_BG_COLOR.default)
    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local statsFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_FONT_SIZE.key,
        self.CONFIGURATION.STATS_FONT_SIZE.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    self.statsFrame:SetBackdrop({
        bgFile = LSM:Fetch("background", CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_TEXTURE.key,
            self.CONFIGURATION.FRAME_TEXTURE.default)),
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    self.statsFrame:SetBackdropColor(statsBgColor.r, statsBgColor.g, statsBgColor.b, statsBgColor.a)

    -- Get color configuration
    local labelColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_LABEL_COLOR.key,
        self.CONFIGURATION.STATS_LABEL_COLOR.default)
    local valueColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_VALUE_COLOR.key,
        self.CONFIGURATION.STATS_VALUE_COLOR.default)

    -- Reset button anchored to the right side
    local resetButton = CreateFrame("Button", nil, self.statsFrame, "BackdropTemplate")
    resetButton:SetSize(80, 20)
    resetButton:SetPoint("TOPRIGHT", self.statsFrame, "TOPRIGHT", -10, -15)
    -- Use ElvUI skinned button when available, fallback to simple backdrop otherwise
    if Skins and Skins.HandleButton then
        Skins:HandleButton(resetButton)
    else
        resetButton:SetBackdropColor(0.5, 0.2, 0.2, 0.8)
        resetButton:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 4,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
    end

    local resetText = resetButton:CreateFontString(nil, "OVERLAY")
    resetText:SetFont(fontPath, statsFontSize, "OUTLINE")
    resetText:SetTextColor(1, 1, 1)
    resetText:SetText(TT.Color(TM.Colors.TWICH.TEXT_WARNING, "Reset"))
    resetText:SetPoint("CENTER", resetButton, "CENTER")

    resetButton:SetScript("OnClick", function()
        local GPH = LM.GoldPerHourTracker
        if GPH then
            GPH:Reset()
        end
    end)

    -- Container for statistics text to ensure it never sits behind the reset button
    local statsContainer = CreateFrame("Frame", nil, self.statsFrame)
    statsContainer:SetPoint("TOPLEFT", self.statsFrame, "TOPLEFT", 4, 0)
    statsContainer:SetPoint("BOTTOMLEFT", self.statsFrame, "BOTTOMLEFT", 4, 0)
    statsContainer:SetPoint("RIGHT", resetButton, "LEFT", -10, 0)

    self.statsFrame.container = statsContainer

    -- Stats text displays (anchored inside the container)
    local statsDefs = {
        { label = "Raw Gold:",     key = "rawGold" },
        { label = "Total Looted:", key = "totalGold" },
        { label = "GPH:",          key = "gph" },
    }

    local statsSpacing = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_SPACING.key,
        self.CONFIGURATION.STATS_SPACING.default)
    local baseX = 6

    self.statsFrame.labels = {}
    self.statsFrame.values = {}

    for index, stat in ipairs(statsDefs) do
        local x = baseX + (index - 1) * statsSpacing

        local labelText = statsContainer:CreateFontString(nil, "OVERLAY")
        labelText:SetFont(fontPath, statsFontSize, "OUTLINE")
        labelText:SetTextColor(labelColor.r, labelColor.g, labelColor.b)
        labelText:SetText(stat.label)
        labelText:SetPoint("TOPLEFT", statsContainer, "TOPLEFT", x, -5)

        local valueText = statsContainer:CreateFontString(nil, "OVERLAY")
        valueText:SetFont(fontPath, statsFontSize, "OUTLINE")
        valueText:SetTextColor(valueColor.r, valueColor.g, valueColor.b)
        valueText:SetText("0")
        valueText:SetPoint("TOPLEFT", statsContainer, "TOPLEFT", x, -20)

        self.statsFrame[stat.key] = valueText
        table.insert(self.statsFrame.labels, labelText)
        table.insert(self.statsFrame.values, valueText)
    end
end

--- Set the sort column and refresh the display
---@param columnKey string The key of the column to sort by ("name", "quantity", "method", "value")
function GPHFrame:SetSortColumn(columnKey)
    if self.sortColumn == columnKey then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = columnKey
        self.sortAscending = false
    end

    self:RefreshDisplay()
end

--- Handle tracker update event
--- Updates the frame with new loot and statistics data
---@param stats GoldPerHourData The current tracker statistics
function GPHFrame:OnTrackerUpdate(stats)
    if not self:IsEnabled() then return end
    if not stats or not stats.trackedItems then return end

    self:UpdateItems(stats.trackedItems)
    self:UpdateStats(stats)
end

--- Update the items display from tracked items
---@param trackedItems table<string, TrackedItem> Items indexed by itemLink
function GPHFrame:UpdateItems(trackedItems)
    -- Clear and rebuild rows
    for itemLink, row in pairs(self.rows) do
        if not trackedItems[itemLink] then
            row:Hide()
            self.rows[itemLink] = nil
        end
    end

    -- Add or update rows for existing items
    for itemLink, item in pairs(trackedItems) do
        if not self.rows[itemLink] then
            self:CreateItemRow(itemLink, item)
        else
            self:UpdateItemRow(itemLink, item)
        end
    end

    -- Reapply row styling (background, fonts, colors) and refresh layout
    self:UpdateRowStyling()
end

--- Create a new row for an item
---@param itemLink string The item's link
---@param item TrackedItem The item data
function GPHFrame:CreateItemRow(itemLink, item)
    local rowHeight = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_HEIGHT.key, self.CONFIGURATION.ROW_HEIGHT.default)
    local rowBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BG_COLOR.key,
        self.CONFIGURATION.ROW_BG_COLOR.default)
    local rowTextColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_TEXT_COLOR.key,
        self.CONFIGURATION.ROW_TEXT_COLOR.default)
    local rowTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_TEXTURE.key,
        self.CONFIGURATION.ROW_TEXTURE.default)
    local rowBorderTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BORDER_TEXTURE.key,
        self.CONFIGURATION.ROW_BORDER_TEXTURE.default)
    local rowBorderColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BORDER_COLOR.key,
        self.CONFIGURATION.ROW_BORDER_COLOR.default)

    local rowTexture = LSM:Fetch("background", rowTextureName)
    local rowBorderTexture = LSM:Fetch("border", rowBorderTextureName)
    local hoverBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_HOVER_BG_COLOR.key,
        self.CONFIGURATION.ROW_HOVER_BG_COLOR.default)

    local row = CreateFrame("Button", nil, self.contentFrame, "BackdropTemplate")
    row:SetHeight(rowHeight)
    row:SetBackdropColor(rowBgColor.r, rowBgColor.g, rowBgColor.b, rowBgColor.a)
    row:SetBackdrop({
        bgFile = rowTexture,
        edgeFile = rowBorderTexture ~= "" and rowBorderTexture or nil,
        tile = true,
        tileSize = 16,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    if rowBorderTexture and rowBorderTexture ~= "" then
        row:SetBackdropBorderColor(rowBorderColor.r, rowBorderColor.g, rowBorderColor.b, rowBorderColor.a)
    end

    -- Hover highlight texture (faded in/out on mouseover, behind text)
    local hoverTexture = row:CreateTexture(nil, "BACKGROUND")
    hoverTexture:SetAllPoints(row)
    hoverTexture:SetColorTexture(hoverBgColor.r, hoverBgColor.g, hoverBgColor.b, hoverBgColor.a)
    hoverTexture:SetAlpha(0)
    row.hoverTexture = hoverTexture

    -- Store item data
    row.itemLink = itemLink
    row.item = item

    -- Create column texts
    local frameWidth = self.contentFrame:GetWidth()
    local xOffset = 0

    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local rowFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_FONT_SIZE.key,
        self.CONFIGURATION.ROW_FONT_SIZE.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    for i, column in ipairs(COLUMNS) do
        local columnWidth = frameWidth * column.width

        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontPath, rowFontSize, "OUTLINE")
        text:SetTextColor(rowTextColor.r, rowTextColor.g, rowTextColor.b)
        text:SetPoint("LEFT", row, "LEFT", xOffset + 5, 0)
        text:SetWidth(columnWidth - 10)
        text:SetHeight(rowHeight)
        text:SetJustifyH(column.align or "LEFT")

        row[column.key] = text
        xOffset = xOffset + columnWidth
    end

    -- Tooltip and hover highlight on mouseover
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()

        if row.hoverTexture then
            local hoverColor = CM:GetProfileSettingSafe(
                GPHFrame.CONFIGURATION.ROW_HOVER_BG_COLOR.key,
                GPHFrame.CONFIGURATION.ROW_HOVER_BG_COLOR.default)
            row.hoverTexture:SetColorTexture(hoverColor.r, hoverColor.g, hoverColor.b, hoverColor.a)
            local targetAlpha = hoverColor.a or 0.4
            if UIFrameFadeIn then
                UIFrameFadeIn(row.hoverTexture, 0.12, row.hoverTexture:GetAlpha(), targetAlpha)
            else
                row.hoverTexture:SetAlpha(targetAlpha)
            end
        end
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()

        if row.hoverTexture then
            if UIFrameFadeOut then
                UIFrameFadeOut(row.hoverTexture, 0.12, row.hoverTexture:GetAlpha(), 0)
            else
                row.hoverTexture:SetAlpha(0)
            end
        end
    end)

    self.rows[itemLink] = row
    self:UpdateItemRow(itemLink, item)
end

--- Update an existing item row's data
---@param itemLink string The item's link
---@param item TrackedItem The updated item data
function GPHFrame:UpdateItemRow(itemLink, item)
    local row = self.rows[itemLink]
    if not row then return end

    row.item = item

    local rowValueColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_VALUE_COLOR.key,
        self.CONFIGURATION.ROW_VALUE_COLOR.default)

    -- Update name column with colored itemLink
    row.name:SetText(item.itemLink or itemLink or "Unknown")

    -- Update quantity column
    row.quantity:SetText(tostring(item.quantity))

    -- Update method column (human-friendly decision)
    local decision = (item.decision or "unknown"):lower()
    local methodLabel
    if decision == "vendor" then
        methodLabel = "Vendor"
    elseif decision == "market" then
        methodLabel = "Market"
    elseif decision == "disenchant" then
        methodLabel = "Disenchant"
    elseif decision == "ignore" then
        methodLabel = "Ignored"
    else
        methodLabel = "Unknown"
    end
    row.method:SetText(methodLabel)

    -- Update value column using TextTool copper formatter (g/s/c)
    local copperValue = item.totalValue or 0
    local valueText = TT and TT.FormatCopper(copperValue) or ("%.2fg"):format(copperValue / 10000)
    row.value:SetText(valueText)
    row.value:SetTextColor(rowValueColor.r, rowValueColor.g, rowValueColor.b)
end

--- Refresh the display by sorting and positioning all rows
function GPHFrame:RefreshDisplay()
    local itemList = {}

    -- Convert rows to sortable list
    for itemLink, row in pairs(self.rows) do
        table.insert(itemList, { itemLink = itemLink, row = row, item = row.item })
    end

    -- Sort items
    table.sort(itemList, function(a, b)
        local aItem = a.item
        local bItem = b.item

        local aVal, bVal
        if self.sortColumn == "name" then
            aVal = a.itemLink:match("|h%[(.-)%]|h") or ""
            bVal = b.itemLink:match("|h%[(.-)%]|h") or ""
        elseif self.sortColumn == "quantity" then
            aVal = aItem.quantity or 0
            bVal = bItem.quantity or 0
        elseif self.sortColumn == "method" then
            aVal = aItem.decision or ""
            bVal = bItem.decision or ""
        elseif self.sortColumn == "value" then
            aVal = aItem.totalValue or 0
            bVal = bItem.totalValue or 0
        else
            aVal = ""
            bVal = ""
        end

        -- Handle nil or comparison incompatibility
        if aVal == nil then aVal = 0 end
        if bVal == nil then bVal = 0 end

        if self.sortAscending then
            return aVal < bVal
        else
            return aVal > bVal
        end
    end)

    -- Position rows
    local rowHeight = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_HEIGHT.key, self.CONFIGURATION.ROW_HEIGHT.default)
    local rowSpacing = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_SPACING.key,
        self.CONFIGURATION.ROW_SPACING.default)
    local totalRowHeight = rowHeight + rowSpacing

    local yOffset = 0
    for i, entry in ipairs(itemList) do
        local row = entry.row
        row:SetWidth(self.contentFrame:GetWidth())
        row:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 0, yOffset)
        row:Show()
        yOffset = yOffset - totalRowHeight
    end

    -- Update content frame size
    local totalHeight = math.max(#itemList * totalRowHeight, 1)
    self.contentFrame:SetHeight(totalHeight)
end

--- Update the statistics display
---@param stats GoldPerHourData The current statistics
function GPHFrame:UpdateStats(stats)
    if not self.statsFrame then return end

    -- Raw gold looted (from money events only)
    local rawCopper = stats.goldReceived or 0
    if self.statsFrame.rawGold then
        local rawText = TT and TT.FormatCopper(rawCopper) or ("%.2fg"):format(rawCopper / 10000)
        self.statsFrame.rawGold:SetText(rawText)
    end

    -- Format total gold looted
    local totalCopper = stats.totalGold or 0
    local totalText = TT and TT.FormatCopper(totalCopper) or ("%.2fg"):format((totalCopper or 0) / 10000)
    self.statsFrame.totalGold:SetText(totalText)

    -- Format GPH (full g/s/c per hour)
    local gphCopper = stats.goldPerHour or 0
    local gphText = TT and TT.FormatCopper(gphCopper) or ("%.2fg"):format(gphCopper / 10000)
    self.statsFrame.gph:SetText(gphText .. " /h")

    -- Update elapsed time display on the title bar
    if self.timeText and stats.elapsedTime then
        local minutes = math.floor(stats.elapsedTime / 60)
        local seconds = stats.elapsedTime % 60
        self.timeText:SetText(("Time: %dm %ds"):format(minutes, seconds))
    end
end

--- Update all header colors from configuration
function GPHFrame:UpdateHeaderColors()
    if not self.frame then return end

    local headerBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_BG_COLOR.key,
        self.CONFIGURATION.HEADER_BG_COLOR.default)
    local headerTextColor = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_TEXT_COLOR.key,
        self.CONFIGURATION.HEADER_TEXT_COLOR.default)
    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local headerFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.HEADER_FONT_SIZE.key,
        self.CONFIGURATION.HEADER_FONT_SIZE.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    if self.headerFrame then
        self.headerFrame:SetBackdropColor(headerBgColor.r, headerBgColor.g, headerBgColor.b, headerBgColor.a)
    end

    if self.headerColumns then
        for _, col in ipairs(self.headerColumns) do
            if col.text then
                col.text:SetFont(fontPath, headerFontSize, "OUTLINE")
                col.text:SetTextColor(headerTextColor.r, headerTextColor.g, headerTextColor.b)
            end
        end
    end
end

--- Update all row colors and heights from configuration
function GPHFrame:UpdateRowStyling()
    if not self.rows then return end

    local rowHeight = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_HEIGHT.key, self.CONFIGURATION.ROW_HEIGHT.default)
    local rowBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BG_COLOR.key,
        self.CONFIGURATION.ROW_BG_COLOR.default)
    local rowTextColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_TEXT_COLOR.key,
        self.CONFIGURATION.ROW_TEXT_COLOR.default)
    local rowValueColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_VALUE_COLOR.key,
        self.CONFIGURATION.ROW_VALUE_COLOR.default)
    local rowHoverBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_HOVER_BG_COLOR.key,
        self.CONFIGURATION.ROW_HOVER_BG_COLOR.default)
    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local rowFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_FONT_SIZE.key,
        self.CONFIGURATION.ROW_FONT_SIZE.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    for itemLink, row in pairs(self.rows) do
        row:SetHeight(rowHeight)
        row:SetBackdropColor(rowBgColor.r, rowBgColor.g, rowBgColor.b, rowBgColor.a)

        if row.hoverTexture then
            row.hoverTexture:SetColorTexture(rowHoverBgColor.r, rowHoverBgColor.g, rowHoverBgColor.b,
                rowHoverBgColor.a)
        end

        -- Update text colors in all columns
        for _, column in ipairs(COLUMNS) do
            local fs = row[column.key]
            if fs then
                if column.key == "value" then
                    fs:SetTextColor(rowValueColor.r, rowValueColor.g, rowValueColor.b)
                else
                    fs:SetTextColor(rowTextColor.r, rowTextColor.g, rowTextColor.b)
                end
                fs:SetHeight(rowHeight)
                fs:SetFont(fontPath, rowFontSize, "OUTLINE")
            end
        end
    end

    self:RefreshDisplay()
end

--- Update statistics colors from configuration
function GPHFrame:UpdateStatsStyling()
    if not self.statsFrame then return end

    local labelColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_LABEL_COLOR.key,
        self.CONFIGURATION.STATS_LABEL_COLOR.default)
    local valueColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_VALUE_COLOR.key,
        self.CONFIGURATION.STATS_VALUE_COLOR.default)
    local statsBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_BG_COLOR.key,
        self.CONFIGURATION.STATS_BG_COLOR.default)
    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local statsFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_FONT_SIZE.key,
        self.CONFIGURATION.STATS_FONT_SIZE.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    self.statsFrame:SetBackdropColor(statsBgColor.r, statsBgColor.g, statsBgColor.b, statsBgColor.a)

    if self.statsFrame.labels then
        for _, fs in ipairs(self.statsFrame.labels) do
            fs:SetFont(fontPath, statsFontSize, "OUTLINE")
            fs:SetTextColor(labelColor.r, labelColor.g, labelColor.b)
        end
    end

    if self.statsFrame.values then
        for _, fs in ipairs(self.statsFrame.values) do
            fs:SetFont(fontPath, statsFontSize, "OUTLINE")
            fs:SetTextColor(valueColor.r, valueColor.g, valueColor.b)
        end
    end
end

--- Update statistics layout (horizontal spacing) from configuration
function GPHFrame:UpdateStatsLayout()
    if not self.statsFrame or not self.statsFrame.container then return end
    if not self.statsFrame.labels or not self.statsFrame.values then return end

    local statsContainer = self.statsFrame.container
    local statsSpacing = CM:GetProfileSettingSafe(self.CONFIGURATION.STATS_SPACING.key,
        self.CONFIGURATION.STATS_SPACING.default)

    local baseX = 6

    for index, labelText in ipairs(self.statsFrame.labels) do
        local x = baseX + (index - 1) * statsSpacing
        labelText:ClearAllPoints()
        labelText:SetPoint("TOPLEFT", statsContainer, "TOPLEFT", x, -5)

        local valueText = self.statsFrame.values[index]
        if valueText then
            valueText:ClearAllPoints()
            valueText:SetPoint("TOPLEFT", statsContainer, "TOPLEFT", x, -20)
        end
    end
end

--- Update scroll/loot area styling from configuration
function GPHFrame:UpdateScrollStyling()
    if not self.scrollFrame then return end

    local scrollBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.SCROLL_BG_COLOR.key,
        self.CONFIGURATION.SCROLL_BG_COLOR.default)
    local frameTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_TEXTURE.key,
        self.CONFIGURATION.FRAME_TEXTURE.default)
    local scrollTexture = LSM:Fetch("background", frameTextureName)

    self.scrollFrame:SetBackdrop({
        bgFile = scrollTexture,
        edgeFile = nil,
        tile = true,
        tileSize = 16,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    self.scrollFrame:SetBackdropColor(scrollBgColor.r, scrollBgColor.g, scrollBgColor.b, scrollBgColor.a)
end

--- Update frame texture from configuration
function GPHFrame:UpdateFrameTexture()
    if not self.frame then return end

    local frameTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_TEXTURE.key,
        self.CONFIGURATION.FRAME_TEXTURE.default)
    local frameBgColor = CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_BG_COLOR.key,
        self.CONFIGURATION.FRAME_BG_COLOR.default)
    local frameBorderTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_BORDER_TEXTURE.key,
        self.CONFIGURATION.FRAME_BORDER_TEXTURE.default)
    local frameBorderColor = CM:GetProfileSettingSafe(self.CONFIGURATION.FRAME_BORDER_COLOR.key,
        self.CONFIGURATION.FRAME_BORDER_COLOR.default)

    local frameTexture = LSM:Fetch("background", frameTextureName)
    local frameBorderTexture = LSM:Fetch("border", frameBorderTextureName)

    self.frame:SetBackdrop({
        bgFile = frameTexture,
        edgeFile = frameBorderTexture,
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    self.frame:SetBackdropColor(frameBgColor.r, frameBgColor.g, frameBgColor.b, frameBgColor.a)
    self.frame:SetBackdropBorderColor(frameBorderColor.r, frameBorderColor.g, frameBorderColor.b, frameBorderColor.a)
end

--- Update row texture from configuration for all existing rows
function GPHFrame:UpdateRowTexture()
    if not self.rows then return end

    local rowTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_TEXTURE.key,
        self.CONFIGURATION.ROW_TEXTURE.default)
    local rowBorderTextureName = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BORDER_TEXTURE.key,
        self.CONFIGURATION.ROW_BORDER_TEXTURE.default)
    local rowBorderColor = CM:GetProfileSettingSafe(self.CONFIGURATION.ROW_BORDER_COLOR.key,
        self.CONFIGURATION.ROW_BORDER_COLOR.default)

    local rowTexture = LSM:Fetch("background", rowTextureName)
    local rowBorderTexture = LSM:Fetch("border", rowBorderTextureName)

    for itemLink, row in pairs(self.rows) do
        row:SetBackdrop({
            bgFile = rowTexture,
            edgeFile = rowBorderTexture ~= "" and rowBorderTexture or nil,
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        if rowBorderTexture and rowBorderTexture ~= "" then
            row:SetBackdropBorderColor(rowBorderColor.r, rowBorderColor.g, rowBorderColor.b, rowBorderColor.a)
        end
    end
end

--- Update all styling from configuration (comprehensive update)
function GPHFrame:UpdateAllStyling()
    self:UpdateFrameTexture()
    self:UpdateHeaderColors()
    self:UpdateScrollStyling()
    self:UpdateRowTexture()
    self:UpdateRowStyling()
    self:UpdateStatsStyling()
end

--- Update title styling (font and color) from configuration
function GPHFrame:UpdateTitleStyling()
    if not self.titleText then return end

    local baseFontName = CM:GetProfileSettingSafe(self.CONFIGURATION.BASE_FONT.key,
        self.CONFIGURATION.BASE_FONT.default)
    local titleFontSize = CM:GetProfileSettingSafe(self.CONFIGURATION.TITLE_FONT_SIZE.key,
        self.CONFIGURATION.TITLE_FONT_SIZE.default)
    local titleColor = CM:GetProfileSettingSafe(self.CONFIGURATION.TITLE_TEXT_COLOR.key,
        self.CONFIGURATION.TITLE_TEXT_COLOR.default)
    local fontPath = LSM:Fetch("font", baseFontName)

    self.titleText:SetFont(fontPath, titleFontSize, "OUTLINE")
    self.titleText:SetTextColor(titleColor.r, titleColor.g, titleColor.b)
end
