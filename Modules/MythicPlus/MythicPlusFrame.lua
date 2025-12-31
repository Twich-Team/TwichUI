local _G = _G
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

--- @class MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GameTooltip = _G.GameTooltip
local GetTime = _G.GetTime

-- LSM is backed by ElvUI's media library when available
local LSM = T.Libs and T.Libs.LSM
local Masque = T.Libs and T.Libs.Masque

-- Optional ElvUI integration
local ElvUI = rawget(_G, "ElvUI")
local E = ElvUI and ElvUI[1]

---@class MythicPlusMainWindow
---@field enabled boolean
---@field frame Frame|nil
---@field titleBar Frame|nil
---@field titleLogo Texture|nil
---@field nav Frame|nil
---@field navButtons table<string, Button>|nil
---@field content Frame|nil
---@field header Frame|nil
---@field headerText FontString|nil
---@field headerAffixButtons Button[]|nil
---@field headerEvents Frame|nil
---@field panelContainer Frame|nil
---@field titleText FontString|nil
---@field _panels table<string, MythicPlusMainWindowPanel>|nil
---@field _panelOrder string[]|nil
---@field activePanelId string|nil
local MainWindow = MythicPlusModule.MainWindow or {}
MythicPlusModule.MainWindow = MainWindow

---@class MythicPlusMainWindowPanel
---@field id string
---@field label string|nil
---@field order number|nil
---@field factory fun(parent:Frame, window:MythicPlusMainWindow):Frame
---@field frame Frame|nil
---@field onShow fun(panelFrame:Frame, window:MythicPlusMainWindow)|nil
---@field onHide fun(panelFrame:Frame, window:MythicPlusMainWindow)|nil

local NAV_WIDTH = 80
local NAV_BUTTON_HEIGHT = 22
local NAV_PADDING = 6

local HEADER_HEIGHT = 30
local HEADER_ICON_SIZE = 18
local HEADER_ICON_SPACING = 6

---@class TwichUI_MythicPlus_HeaderAffixButton : Button
---@field Icon Texture
---@field __twichuiAffixId number|nil

---@class TwichUI_MythicPlus_NavButton : Button
---@field __twichuiHoverBG Texture|nil
---@field __twichuiActiveBG Texture|nil
---@field __twichuiText FontString|nil

local function NormalizeAffixId(affixEntry)
    if type(affixEntry) == "number" then return affixEntry end
    if type(affixEntry) ~= "table" then return nil end
    return tonumber(affixEntry.id) or tonumber(affixEntry.affixID) or tonumber(affixEntry[1])
end

---@param affixId number
---@return string|nil name
---@return string|nil description
---@return number|string|nil fileDataId
local function GetAffixInfo(affixId)
    affixId = tonumber(affixId)
    if not affixId then return nil, nil, nil end

    local C_ChallengeMode = _G.C_ChallengeMode
    if C_ChallengeMode and type(C_ChallengeMode.GetAffixInfo) == "function" then
        local name, description, fileDataId = C_ChallengeMode.GetAffixInfo(affixId)
        return name, description, fileDataId
    end

    return nil, nil, nil
end

---@param mapId number
---@return string|nil name
local function GetChallengeMapName(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil end

    local C_ChallengeMode = _G.C_ChallengeMode
    if not C_ChallengeMode then return nil end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name = C_ChallengeMode.GetMapUIInfo(mapId)
        return name
    end

    if type(C_ChallengeMode.GetMapInfo) == "function" then
        local info = C_ChallengeMode.GetMapInfo(mapId)
        if type(info) == "table" then
            return info.name
        end
    end

    return nil
end

---@return any|nil
local function EnsureHeaderMasqueGroup()
    if not Masque or type(Masque.Group) ~= "function" then return nil end
    local ok, group = pcall(Masque.Group, Masque, "TwichUI", "MythicPlus TitleBar")
    if ok then return group end
    return nil
end

local function ApplyElvUITemplate(frame)
    if not frame then return end

    if frame.SetTemplate then
        frame:SetTemplate("Transparent")
        return
    end

    if not E or not E.media or not E.media.blankTex or not E.media.borderTex then
        return
    end

    frame:SetBackdrop({
        bgFile = E.media.blankTex,
        edgeFile = E.media.borderTex,
        tile = false,
        tileSize = 0,
        edgeSize = E.Border,
        insets = { left = E.Spacing, right = E.Spacing, top = E.Spacing, bottom = E.Spacing },
    })
    frame:SetBackdropColor(unpack(E.media.backdropcolor))
    frame:SetBackdropBorderColor(unpack(E.media.bordercolor))
end

local function GetFontPath()
    local baseFontName = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT)
    if LSM and baseFontName then
        return LSM:Fetch("font", baseFontName)
    end
    return nil
end

function MainWindow:IsEnabled()
    return self.enabled or false
end

function MainWindow:_EnsurePanelTables()
    if not self._panels then
        self._panels = {}
    end
    if not self._panelOrder then
        self._panelOrder = {}
    end
end

function MainWindow:_SortPanelOrder()
    if not self._panelOrder or not self._panels then return end

    table.sort(self._panelOrder, function(a, b)
        local pa = self._panels[a]
        local pb = self._panels[b]
        local oa = (pa and pa.order) or 9999
        local ob = (pb and pb.order) or 9999
        if oa ~= ob then
            return oa < ob
        end
        local la = (pa and pa.label) or a
        local lb = (pb and pb.label) or b
        return tostring(la) < tostring(lb)
    end)
end

---@param id string
---@param factory fun(parent:Frame, window:MythicPlusMainWindow):Frame
---@param onShow fun(panelFrame:Frame, window:MythicPlusMainWindow)|nil
---@param onHide fun(panelFrame:Frame, window:MythicPlusMainWindow)|nil
---@param opts table|nil { label?:string, order?:number }
function MainWindow:RegisterPanel(id, factory, onShow, onHide, opts)
    if type(id) ~= "string" or id == "" then
        return false
    end
    if type(factory) ~= "function" then
        return false
    end

    self:_EnsurePanelTables()

    local isNew = (self._panels[id] == nil)
    self._panels[id] = self._panels[id] or {}

    local panel = self._panels[id]
    panel.id = id
    if type(opts) == "table" then
        if type(opts.label) == "string" and opts.label ~= "" then
            panel.label = opts.label
        end
        if type(opts.order) == "number" then
            panel.order = opts.order
        end
        if type(opts.icon) == "string" then
            panel.icon = opts.icon
        end
        if type(opts.iconCoords) == "table" then
            panel.iconCoords = opts.iconCoords
        end
    end
    panel.factory = factory
    panel.onShow = onShow
    panel.onHide = onHide

    if isNew then
        table.insert(self._panelOrder, id)
        self:_SortPanelOrder()
    end

    if self.nav then
        self:RefreshNav()
    end

    -- If the window is already visible and no panel selected, show this one.
    if self:IsEnabled() and self.content and not self.activePanelId then
        self:ShowPanel(id)
    end

    return true
end

---@param id string
---@return Frame|nil
function MainWindow:GetPanelFrame(id)
    if not self._panels or not id then return nil end
    local panel = self._panels[id]
    return panel and panel.frame or nil
end

---@return string|nil
function MainWindow:GetActivePanelId()
    return self.activePanelId
end

local function AttachAnimations(frame)
    if frame.FadeInGroup then return end

    frame.FadeInGroup = frame:CreateAnimationGroup()
    frame.FadeInAnim = frame.FadeInGroup:CreateAnimation("Alpha")
    frame.FadeInAnim:SetDuration(0.2)
    frame.FadeInAnim:SetToAlpha(1)
    frame.FadeInAnim:SetSmoothing("OUT")
    frame.FadeInGroup:SetScript("OnFinished", function() frame:SetAlpha(1) end)

    frame.FadeOutGroup = frame:CreateAnimationGroup()
    frame.FadeOutAnim = frame.FadeOutGroup:CreateAnimation("Alpha")
    frame.FadeOutAnim:SetDuration(0.2)
    frame.FadeOutAnim:SetToAlpha(0)
    frame.FadeOutAnim:SetSmoothing("OUT")
    frame.FadeOutGroup:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
        if frame.onHideCallback then
            frame.onHideCallback()
            frame.onHideCallback = nil
        end
    end)
end

---@param id string
---@return boolean
function MainWindow:ShowPanel(id)
    if type(id) ~= "string" or id == "" then
        return false
    end

    self:_EnsurePanelTables()
    local nextPanel = self._panels[id]
    if not nextPanel or type(nextPanel.factory) ~= "function" then
        return false
    end

    -- Ensure the window exists so we have a content parent.
    self:CreateFrame()
    if not self.content then
        return false
    end

    -- Hide current panel (if any)
    if self.activePanelId and self.activePanelId ~= id then
        local current = self._panels[self.activePanelId]
        if current and current.frame then
            AttachAnimations(current.frame)

            -- Store onHide callback to be called after animation
            current.frame.onHideCallback = function()
                if type(current.onHide) == "function" then
                    pcall(current.onHide, current.frame, self)
                end
            end

            current.frame.FadeInGroup:Stop()
            current.frame.FadeOutAnim:SetFromAlpha(current.frame:GetAlpha())
            current.frame.FadeOutGroup:Play()
        end
    end

    -- Create lazily
    local panelParent = self.panelContainer or self.content

    if not nextPanel.frame then
        local ok, frameOrErr = pcall(nextPanel.factory, panelParent, self)
        if not ok or not frameOrErr then
            return false
        end
        nextPanel.frame = frameOrErr

        -- Default layout: fill the content area if the panel didn't anchor itself.
        if nextPanel.frame.GetNumPoints and nextPanel.frame.SetAllPoints then
            if (nextPanel.frame:GetNumPoints() or 0) == 0 then
                nextPanel.frame:SetAllPoints(panelParent)
            end
        elseif nextPanel.frame.SetAllPoints then
            nextPanel.frame:SetAllPoints(panelParent)
        end
    end

    AttachAnimations(nextPanel.frame)

    self.activePanelId = id

    nextPanel.frame.FadeOutGroup:Stop()
    if not nextPanel.frame:IsShown() then
        nextPanel.frame:SetAlpha(0)
    end
    nextPanel.frame:Show()
    nextPanel.frame.FadeInAnim:SetFromAlpha(nextPanel.frame:GetAlpha())
    nextPanel.frame.FadeInGroup:Play()

    if type(nextPanel.onShow) == "function" then
        pcall(nextPanel.onShow, nextPanel.frame, self)
    end

    self:UpdateNavSelection()

    return true
end

function MainWindow:_CreateHeaderIfNeeded()
    if not self.titleBar or self.header then return end
    if (not self.titleLogo and not self.titleText) or not self.closeButton then return end

    local leftAnchor = self.titleLogo or self.titleText

    local header = CreateFrame("Frame", nil, self.titleBar)
    header:SetPoint("LEFT", leftAnchor, "RIGHT", 12, 0)
    header:SetPoint("RIGHT", self.closeButton, "LEFT", -10, 0)
    header:SetHeight(HEADER_HEIGHT)

    local text = header:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", header, "LEFT", 0, 0)
    text:SetJustifyH("LEFT")
    if text.SetFontObject then
        text:SetFontObject(_G.GameFontHighlight)
    end

    local fontPath = GetFontPath()
    if fontPath and text.SetFont then
        text:SetFont(fontPath, 13, "OUTLINE")
    end
    text:SetText("Keystone: …")

    self.header = header
    self.headerText = text
    self.headerAffixButtons = {}

    local masqueGroup = EnsureHeaderMasqueGroup()

    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(HEADER_ICON_SIZE, HEADER_ICON_SIZE)
        btn:Hide()

        btn.Icon = btn:CreateTexture(nil, "ARTWORK")
        btn.Icon:SetAllPoints(btn)
        btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn.__twichuiAffixId = nil
        btn:SetScript("OnEnter", function(b)
            local affixId = b.__twichuiAffixId
            if not affixId or not GameTooltip then return end
            local name, description = GetAffixInfo(affixId)
            if not name then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 1, 1)
            if description and description ~= "" then
                GameTooltip:AddLine(description, 0.9, 0.9, 0.9, true)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        if i == 1 then
            btn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        else
            btn:SetPoint("RIGHT", self.headerAffixButtons[i - 1], "LEFT", -HEADER_ICON_SPACING, 0)
        end

        self.headerAffixButtons[i] = btn

        if masqueGroup and type(masqueGroup.AddButton) == "function" then
            pcall(masqueGroup.AddButton, masqueGroup, btn, { Icon = btn.Icon })
        end
    end

    -- Anchor text between left edge and icons.
    if self.headerAffixButtons[1] then
        text:ClearAllPoints()
        text:SetPoint("LEFT", header, "LEFT", 0, 0)
        text:SetPoint("RIGHT", self.headerAffixButtons[1], "LEFT", -10, 0)
        text:SetJustifyH("LEFT")
    else
        text:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    end
end

function MainWindow:UpdateKeystoneHeader()
    if not self.header or not self.headerText or not self.headerAffixButtons then return end

    local C_MythicPlus = _G.C_MythicPlus
    local ownedMapID = (C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function")
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or nil
    local ownedLevel = (C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneLevel) == "function")
        and C_MythicPlus.GetOwnedKeystoneLevel() or nil

    local name = GetChallengeMapName(ownedMapID) or "No Keystone"
    local level = tonumber(ownedLevel)

    if ownedMapID and level then
        self.headerText:SetText(string.format("%s  |cff00ff00+%d|r", name, level))
    else
        self.headerText:SetText(name)
    end

    local affixIds = {}
    if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneAffixes) == "function" then
        local affixes = C_MythicPlus.GetOwnedKeystoneAffixes()
        if type(affixes) == "table" then
            for _, entry in ipairs(affixes) do
                local id = NormalizeAffixId(entry)
                if id then table.insert(affixIds, id) end
            end
        end
    end

    local keyHasAffixes = (ownedMapID ~= nil) and (level ~= nil) and (level >= 2)

    for i, btn in ipairs(self.headerAffixButtons) do
        ---@cast btn TwichUI_MythicPlus_HeaderAffixButton
        local affixId = affixIds[i]
        if affixId then
            local _, _, fileDataId = GetAffixInfo(affixId)
            btn.__twichuiAffixId = affixId
            btn.Icon:SetTexture(fileDataId)
            btn:Show()
        else
            btn.__twichuiAffixId = nil
            btn:Hide()
        end
    end

    -- If the key exists but has no affixes (low level), show a short note.
    if ownedMapID and level and (not keyHasAffixes) then
        self.headerText:SetText(string.format("%s  |cff00ff00+%d|r  |cffaaaaaa(No affixes)|r", name, level))
    end
end

function MainWindow:_EnableHeaderEvents()
    if self.headerEvents or not self.frame then return end

    local f = CreateFrame("Frame", nil, self.frame)
    self.headerEvents = f
    f:SetScript("OnEvent", function(_, event)
        -- Only do work while the Mythic+ window is enabled.
        if not self.enabled then return end

        -- Throttle to avoid expensive refresh storms.
        local now = (type(GetTime) == "function") and GetTime() or 0
        if event ~= "PLAYER_ENTERING_WORLD" then
            local last = self.__twichuiHeaderLastUpdate or 0
            if (now - last) < 0.25 then
                return
            end
        end
        self.__twichuiHeaderLastUpdate = now

        -- Request affixes only on non-affix-update events to avoid loops.
        if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_MAPS_UPDATE" then
            local C_MythicPlus = _G.C_MythicPlus
            if C_MythicPlus and type(C_MythicPlus.RequestCurrentAffixes) == "function" then
                pcall(C_MythicPlus.RequestCurrentAffixes)
            end
        end

        self:_CreateHeaderIfNeeded()
        self:UpdateKeystoneHeader()
    end)

    local events = {
        "PLAYER_ENTERING_WORLD",
        "BAG_UPDATE_DELAYED",
        "CHALLENGE_MODE_MAPS_UPDATE",
        "CHALLENGE_MODE_COMPLETED",
        "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
    }
    for _, ev in ipairs(events) do
        pcall(f.RegisterEvent, f, ev)
    end
end

function MainWindow:UpdateNavSelection()
    if not self.navButtons then return end

    for id, btn in pairs(self.navButtons) do
        ---@cast btn TwichUI_MythicPlus_NavButton
        local isActive = (id == self.activePanelId)
        if btn and btn.__twichuiActiveBG then
            if isActive then
                btn.__twichuiActiveBG:Show()
            else
                btn.__twichuiActiveBG:Hide()
            end
        end

        if btn and btn.NavIcon then
            btn.NavIcon:SetAlpha(isActive and 1.0 or 0.5)
        elseif btn and btn.DungeonArt then
            btn.DungeonArt:SetAlpha(isActive and 1.0 or 0.5)
        end
    end
end

function MainWindow:_ShowFirstRegisteredPanelIfNeeded()
    if self.activePanelId then return end
    if not self._panelOrder or #self._panelOrder == 0 then return end
    self:ShowPanel(self._panelOrder[1])
end

function MainWindow:SaveFramePosition()
    if not self.frame or not self.frame.GetPoint then return end

    local point, _, relativePoint, xOfs, yOfs = self.frame:GetPoint(1)
    if not point or not relativePoint then return end

    CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_POINT, point)
    CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_RELATIVE_POINT, relativePoint)
    CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_X, tonumber(xOfs) or 0)
    CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_Y, tonumber(yOfs) or 0)
end

function MainWindow:RestoreFramePosition()
    if not self.frame then return end

    local point = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_POINT)
    local relativePoint = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_RELATIVE_POINT)
    local x = tonumber(CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_X)) or 0
    local y = tonumber(CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_Y)) or 0

    self.frame:ClearAllPoints()
    self.frame:SetPoint(point or "CENTER", UIParent, relativePoint or "CENTER", x, y)
end

function MainWindow:UpdateLockState()
    if not self.frame or not self.titleBar then return end

    local locked = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_LOCKED)

    self.frame:EnableMouse(not locked)
    self.titleBar:EnableMouse(not locked)

    if locked then
        self.frame:RegisterForDrag()
        self.titleBar:RegisterForDrag()
        self.frame:SetScript("OnDragStart", nil)
        self.frame:SetScript("OnDragStop", nil)
        self.titleBar:SetScript("OnDragStart", nil)
        self.titleBar:SetScript("OnDragStop", nil)
        return
    end

    self.frame:SetMovable(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    self.frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SaveFramePosition()
    end)

    self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function()
        if self.frame and self.frame.StartMoving then
            self.frame:StartMoving()
        end
    end)
    self.titleBar:SetScript("OnDragStop", function()
        if self.frame and self.frame.StopMovingOrSizing then
            self.frame:StopMovingOrSizing()
        end
        self:SaveFramePosition()
    end)
end

function MainWindow:UpdateTitleStyling()
    if not self.titleText then return end

    local fontPath = GetFontPath()
    local fontSize = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_TITLE_FONT_SIZE)
    local color = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_TITLE_TEXT_COLOR)

    -- Ensure the FontString always has *some* font before any SetText call.
    -- If LSM/ElvUI aren't ready yet, fall back to a default font object.
    if fontPath and fontSize then
        self.titleText:SetFont(fontPath, fontSize, "OUTLINE")
    elseif self.titleText.SetFontObject then
        self.titleText:SetFontObject(_G.GameFontNormal)
    end
    if color then
        self.titleText:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
    end
end

function MainWindow:CreateTitleBar()
    if not self.frame or self.titleBar then return end

    local titleBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(30)

    ApplyElvUITemplate(titleBar)

    self.titleBar = titleBar

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    if titleText.SetFontObject then
        titleText:SetFontObject(_G.GameFontNormal)
    end
    self.titleText = titleText
    self:UpdateTitleStyling()

    -- Replace text title with custom texture
    titleText:SetText("")
    titleText:Hide()

    local logo = titleBar:CreateTexture(nil, "OVERLAY")
    logo:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    logo:SetSize(24, 22)
    logo:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\mythic-plus.tga")
    self.titleLogo = logo

    -- Close button
    local closeButton = CreateFrame("Button", nil, titleBar)
    closeButton:SetSize(28, 28)
    closeButton:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeButton:SetHitRectInsets(-8, -8, -8, -8)

    local closeText = closeButton:CreateFontString(nil, "OVERLAY")
    local fontPath = GetFontPath()
    local fontSize = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_TITLE_FONT_SIZE) or 14
    if closeText.SetFontObject then
        closeText:SetFontObject(_G.GameFontHighlightLarge)
    end
    if fontPath then
        closeText:SetFont(fontPath, math.max(fontSize + 8, fontSize), "OUTLINE")
    end
    closeText:SetTextColor(1, 1, 1)
    closeText:SetText("×")
    closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 1)

    closeButton:SetScript("OnEnter", function()
        closeText:SetTextColor(1, 0, 0)
    end)
    closeButton:SetScript("OnLeave", function()
        closeText:SetTextColor(1, 1, 1)
    end)
    closeButton:SetScript("OnClick", function()
        self:Disable()
    end)

    self.closeButton = closeButton

    -- Keystone header in title bar (compact)
    self:_CreateHeaderIfNeeded()
    self:UpdateKeystoneHeader()

    self:UpdateLockState()
end

function MainWindow:CreateNav()
    if not self.frame or self.nav then return end

    local nav = CreateFrame("Frame", nil, self.frame)
    nav:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -34)
    nav:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 4, 4)
    nav:SetWidth(NAV_WIDTH)

    -- subtle background using ElvUI backdrop color when available
    if E and E.media and E.media.backdropcolor then
        local bg = nav:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(nav)
        local r, g, b, a = unpack(E.media.backdropcolor)
        bg:SetColorTexture(r or 0, g or 0, b or 0, math.min((a or 1) * 0.4, 0.4))
        nav.__twichuiBG = bg
    end

    self.nav = nav
    self.navButtons = {}

    self:RefreshNav()
end

function MainWindow:RefreshNav()
    if not self.nav then return end

    self:_EnsurePanelTables()
    self:_SortPanelOrder()

    -- Hide unused existing buttons
    if self.navButtons then
        for _, btn in pairs(self.navButtons) do
            if btn then
                btn:Hide()
                btn:SetScript("OnClick", nil)
                btn:SetScript("OnEnter", nil)
                btn:SetScript("OnLeave", nil)
            end
        end
    else
        self.navButtons = {}
    end

    local y = -NAV_PADDING
    for _, id in ipairs(self._panelOrder) do
        local panel = self._panels and self._panels[id]
        if panel then
            local btn = self.navButtons[id]
            local height = NAV_BUTTON_HEIGHT
            local hasIcon = (id == "dungeons" or id == "runs" or id == "summary" or panel.icon)

            if hasIcon then
                height = 60
            end

            if not btn then
                btn = CreateFrame("Button", nil, self.nav)
                btn:SetPoint("TOPLEFT", self.nav, "TOPLEFT", NAV_PADDING, y)
                btn:SetPoint("TOPRIGHT", self.nav, "TOPRIGHT", -NAV_PADDING, y)

                local hover = btn:CreateTexture(nil, "BACKGROUND")
                hover:SetAllPoints(btn)
                hover:Hide()
                if E and E.media and E.media.bordercolor then
                    local r, g, b, a = unpack(E.media.bordercolor)
                    hover:SetColorTexture(r or 1, g or 1, b or 1, 0.08)
                else
                    hover:SetColorTexture(1, 1, 1, 0.08)
                end
                btn.__twichuiHoverBG = hover

                local active = btn:CreateTexture(nil, "BACKGROUND")
                active:SetAllPoints(btn)
                active:Hide()
                if E and E.media and E.media.bordercolor then
                    local r, g, b, a = unpack(E.media.bordercolor)
                    active:SetColorTexture(r or 1, g or 1, b or 1, 0.16)
                else
                    active:SetColorTexture(1, 1, 1, 0.16)
                end
                btn.__twichuiActiveBG = active

                local text = btn:CreateFontString(nil, "OVERLAY")
                if text.SetFontObject then
                    text:SetFontObject(_G.GameFontNormal)
                end
                text:SetPoint("LEFT", btn, "LEFT", 6, 0)
                text:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
                text:SetJustifyH("LEFT")
                btn.__twichuiText = text

                self.navButtons[id] = btn
            else
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self.nav, "TOPLEFT", NAV_PADDING, y)
                btn:SetPoint("TOPRIGHT", self.nav, "TOPRIGHT", -NAV_PADDING, y)
            end

            btn:SetHeight(height)

            if btn.__twichuiText then
                btn.__twichuiText:SetText(panel.label or id)
            end

            if hasIcon then
                if not btn.NavIcon then
                    btn.NavIcon = btn:CreateTexture(nil, "ARTWORK")
                end

                if panel.icon then
                    btn.NavIcon:SetSize(24, 24)
                    btn.NavIcon:SetTexture(panel.icon)
                    if panel.iconCoords then
                        btn.NavIcon:SetTexCoord(unpack(panel.iconCoords))
                    else
                        btn.NavIcon:SetTexCoord(0, 1, 0, 1)
                    end
                elseif id == "dungeons" then
                    btn.NavIcon:SetSize(24, 28)
                    btn.NavIcon:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\dungeons.tga")
                    btn.NavIcon:SetTexCoord(0, 1, 0, 1)
                elseif id == "runs" then
                    btn.NavIcon:SetSize(24, 28)
                    btn.NavIcon:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\runs.tga")
                    btn.NavIcon:SetTexCoord(0, 1, 0, 1)
                else
                    -- Summary (64x92 original)
                    btn.NavIcon:SetSize(22, 32)
                    btn.NavIcon:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\summary.tga")
                    btn.NavIcon:SetTexCoord(0, 1, 0, 1)
                end

                btn.NavIcon:ClearAllPoints()
                btn.NavIcon:SetPoint("TOP", btn, "TOP", 0, -10)
                btn.NavIcon:Show()

                -- Hide legacy texture if present
                if btn.DungeonArt then btn.DungeonArt:Hide() end

                if btn.__twichuiText then
                    btn.__twichuiText:ClearAllPoints()
                    btn.__twichuiText:SetPoint("TOP", btn.NavIcon, "BOTTOM", 0, -4)
                    btn.__twichuiText:SetJustifyH("CENTER")
                end
            else
                if btn.NavIcon then btn.NavIcon:Hide() end
                if btn.DungeonArt then btn.DungeonArt:Hide() end

                if btn.__twichuiText then
                    btn.__twichuiText:ClearAllPoints()
                    btn.__twichuiText:SetPoint("LEFT", btn, "LEFT", 6, 0)
                    btn.__twichuiText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
                    btn.__twichuiText:SetJustifyH("LEFT")
                end
            end

            btn:SetScript("OnClick", function()
                self:ShowPanel(id)
            end)
            btn:SetScript("OnEnter", function(b)
                if b.__twichuiHoverBG and id ~= self.activePanelId then
                    b.__twichuiHoverBG:Show()
                end
                if b.NavIcon then
                    b.NavIcon:SetAlpha(1.0)
                end
            end)
            btn:SetScript("OnLeave", function(b)
                if b.__twichuiHoverBG then
                    b.__twichuiHoverBG:Hide()
                end
                if b.NavIcon and id ~= self.activePanelId then
                    b.NavIcon:SetAlpha(0.5)
                end
            end)

            btn:Show()
            y = y - (height + 2)
        end
    end

    self:UpdateNavSelection()
end

function MainWindow:CreateContent()
    if not self.frame or self.content then return end

    local content = CreateFrame("Frame", nil, self.frame)
    if self.nav then
        content:SetPoint("TOPLEFT", self.nav, "TOPRIGHT", NAV_PADDING, 0)
    else
        content:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -34)
    end
    content:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -4, 4)

    self.content = content

    local panelContainer = CreateFrame("Frame", nil, content)
    panelContainer:SetAllPoints(content)
    self.panelContainer = panelContainer
end

function MainWindow:CreateFrame()
    if self.frame then return end

    local width = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_WIDTH)
    local height = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_HEIGHT)
    local scale = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_SCALE)
    local alpha = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ALPHA)

    local frame = CreateFrame("Frame", "TwichUIMythicPlusWindow", UIParent, "BackdropTemplate")
    self.frame = frame

    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)

    ApplyElvUITemplate(frame)

    frame:SetSize(width, height)
    frame:SetScale(scale)
    frame:SetAlpha(alpha)

    -- Animation Groups
    frame.FadeInGroup = frame:CreateAnimationGroup()
    frame.FadeInAnim = frame.FadeInGroup:CreateAnimation("Alpha")
    frame.FadeInAnim:SetDuration(0.2)
    frame.FadeInAnim:SetToAlpha(1)
    frame.FadeInAnim:SetSmoothing("OUT")
    frame.FadeInGroup:SetScript("OnFinished", function() frame:SetAlpha(1) end)

    frame.FadeOutGroup = frame:CreateAnimationGroup()
    frame.FadeOutAnim = frame.FadeOutGroup:CreateAnimation("Alpha")
    frame.FadeOutAnim:SetDuration(0.2)
    frame.FadeOutAnim:SetToAlpha(0)
    frame.FadeOutAnim:SetSmoothing("OUT")
    frame.FadeOutGroup:SetScript("OnFinished", function()
        frame:Hide()
        frame:SetAlpha(1)
    end)

    self:RestoreFramePosition()

    if frame.GetName then
        local name = frame:GetName()
        local specialFrames = rawget(_G, "UISpecialFrames")
        if type(name) == "string" and type(specialFrames) == "table" then
            table.insert(specialFrames, name)
        end
    end

    self:CreateTitleBar()
    self:CreateNav()
    self:CreateContent()

    self:_EnableHeaderEvents()
    self:_CreateHeaderIfNeeded()
    self:UpdateKeystoneHeader()

    frame:Hide()
end

function MainWindow:RefreshLayout()
    if not self.frame then return end

    local width = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_WIDTH)
    local height = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_HEIGHT)
    local scale = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_SCALE)
    local alpha = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ALPHA)

    self.frame:SetSize(width, height)
    self.frame:SetScale(scale)
    self.frame:SetAlpha(alpha)

    self:UpdateTitleStyling()
    self:UpdateLockState()
end

function MainWindow:ShowAnimated()
    if not self.frame then return end
    local f = self.frame

    f.FadeOutGroup:Stop()
    if not f:IsShown() then
        f:SetAlpha(0)
        f:Show()
    end
    f.FadeInAnim:SetFromAlpha(f:GetAlpha())
    f.FadeInGroup:Play()
end

function MainWindow:HideAnimated()
    if not self.frame then return end
    local f = self.frame

    f.FadeInGroup:Stop()
    f.FadeOutAnim:SetFromAlpha(f:GetAlpha())
    f.FadeOutGroup:Play()
end

---@param persist boolean|nil When true (default), writes to the saved MAIN_WINDOW_ENABLED setting.
function MainWindow:Enable(persist)
    if self:IsEnabled() then
        -- Ensure the existing frame is visible (important during reload/login timing).
        if self.frame then
            self:ShowAnimated()
        end
        if self.nav then
            self:RefreshNav()
        end
        self:_ShowFirstRegisteredPanelIfNeeded()
        return
    end

    -- Parent module must be enabled.
    if not MythicPlusModule.IsEnabled or not MythicPlusModule:IsEnabled() then
        return
    end

    self.enabled = true
    if persist ~= false then
        CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ENABLED, true)
    end

    self:CreateFrame()
    self:RefreshLayout()

    self:_CreateHeaderIfNeeded()
    self:UpdateKeystoneHeader()

    if self.frame then
        self:ShowAnimated()
    end

    if self.nav then
        self:RefreshNav()
    end

    self:_ShowFirstRegisteredPanelIfNeeded()
end

---@param persist boolean|nil When true (default), writes to the saved MAIN_WINDOW_ENABLED setting.
function MainWindow:Disable(persist)
    if not self:IsEnabled() then return end

    self.enabled = false
    if persist ~= false then
        CM:SetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ENABLED, false)
    end

    if self.frame then
        self:HideAnimated()
    end
end

function MainWindow:Toggle()
    if self:IsEnabled() then
        self:Disable()
    else
        self:Enable()
    end
end

function MainWindow:Initialize()
    if self:IsEnabled() then return end

    local shouldShow = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_ENABLED)
    if shouldShow then
        self:Enable()
    end
end
