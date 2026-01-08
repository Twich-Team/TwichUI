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

-- Optional logger (used for debug diagnostics)
local Logger = T.GetModule and T:GetModule("Logger")

-- Optional ElvUI integration
local ElvUI = rawget(_G, "ElvUI")
local E = ElvUI and ElvUI[1]

---@class MythicPlusMainWindow
---@field enabled boolean
---@field frame Frame|nil
---@field titleBar Frame|nil
---@field titleLogo Frame|nil
---@field nav Frame|nil
---@field navButtons table<string, Button>|nil
---@field content Frame|nil
---@field header Frame|nil
---@field headerText FontString|nil
---@field headerAffixButtons Button[]|nil
---@field headerSimulatorButton Button|nil
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
---@field icon string|nil
---@field iconCoords number[]|nil
---@field iconSize number[]|nil
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

local DEV_CONFIG_SHOW_SIM_BUTTON = "developer.mythicplus.showSimulatorHeaderButton"
local SIM_BUTTON_TEXTURE = "Interface\\AddOns\\TwichUI\\Media\\Textures\\simulator.tga"

function MainWindow:_ShouldShowSimulatorHeaderButton()
    return CM and type(CM.GetProfileSettingSafe) == "function" and
        CM:GetProfileSettingSafe(DEV_CONFIG_SHOW_SIM_BUTTON, false)
end

function MainWindow:_EnsureSimulatorHeaderButton()
    if not self.header or self.headerSimulatorButton then
        return
    end

    local btn = CreateFrame("Button", nil, self.header)
    btn:SetSize(HEADER_ICON_SIZE, HEADER_ICON_SIZE)
    btn:SetNormalTexture(SIM_BUTTON_TEXTURE)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    if btn.GetNormalTexture and btn:GetNormalTexture() then
        btn:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    btn:SetScript("OnEnter", function(b)
        if not GameTooltip then return end
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open Mythic+ Simulator", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    btn:SetScript("OnClick", function()
        local rsf = MythicPlusModule and MythicPlusModule.RunSharingFrame
        if rsf and type(rsf.Toggle) == "function" then
            rsf:Toggle()
        end
    end)

    self.headerSimulatorButton = btn
end

function MainWindow:_LayoutHeaderIcons()
    if not self.header or not self.headerText or type(self.headerAffixButtons) ~= "table" then
        return
    end

    local simBtn = self.headerSimulatorButton
    local simShown = simBtn and simBtn.IsShown and simBtn:IsShown()

    -- Simulator button sits on the left side of the header (near the main logo).
    if simBtn then
        simBtn:ClearAllPoints()
        simBtn:SetPoint("LEFT", self.header, "LEFT", 0, 0)
    end

    local prev = nil
    for _, btn in ipairs(self.headerAffixButtons) do
        if btn and btn.IsShown and btn:IsShown() then
            btn:ClearAllPoints()
            if not prev then
                btn:SetPoint("RIGHT", self.header, "RIGHT", 0, 0)
            else
                btn:SetPoint("RIGHT", prev, "LEFT", -HEADER_ICON_SPACING, 0)
            end
            prev = btn
        end
    end

    -- Text occupies the space between the left simulator button and the right-aligned affix icons.
    self.headerText:ClearAllPoints()
    if simShown then
        self.headerText:SetPoint("LEFT", simBtn, "RIGHT", 10, 0)
    else
        self.headerText:SetPoint("LEFT", self.header, "LEFT", 0, 0)
    end

    if prev then
        self.headerText:SetPoint("RIGHT", prev, "LEFT", -10, 0)
    else
        self.headerText:SetPoint("RIGHT", self.header, "RIGHT", 0, 0)
    end
    self.headerText:SetJustifyH("CENTER")
end

function MainWindow:UpdateSimulatorHeaderButton()
    if not self.header then return end
    self:_EnsureSimulatorHeaderButton()
    local btn = self.headerSimulatorButton
    if not btn then return end

    if self:_ShouldShowSimulatorHeaderButton() then
        btn:Show()
    else
        btn:Hide()
    end

    self:_LayoutHeaderIcons()
end

---@class TwichUI_MythicPlus_HeaderAffixButton : Button
---@field Icon Texture
---@field __twichuiAffixId number|nil

---@class TwichUI_MythicPlus_NavButton : Button
---@field __twichuiHoverBG Texture|nil
---@field __twichuiActiveBG Texture|nil
---@field __twichuiText FontString|nil
---@field NavIcon Texture|nil
---@field DungeonArt Texture|nil

---@class TwichUI_FadeFrame : Frame
---@field FadeInGroup AnimationGroup
---@field FadeOutGroup AnimationGroup
---@field FadeInAnim Alpha
---@field FadeOutAnim Alpha
---@field onHideCallback function|nil

local function NormalizeAffixId(affixEntry)
    if type(affixEntry) == "number" then return affixEntry end
    if type(affixEntry) ~= "table" then return nil end
    return tonumber(affixEntry.id) or tonumber(affixEntry.affixID) or tonumber(affixEntry[1])
end

---@param outIds number[]
---@param outNames table<number, string>
---@param affixes any
local function AppendAffixes(outIds, outNames, affixes)
    if type(affixes) ~= "table" then return end
    for _, entry in ipairs(affixes) do
        local id = NormalizeAffixId(entry)
        if id then
            table.insert(outIds, id)
            if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
                outNames[id] = entry.name
            end
        end
    end
end

---@param level number|nil
---@return number
local function GetExpectedAffixCountForLevel(level)
    level = tonumber(level)
    if not level or level < 2 then return 0 end
    -- Conservative/default scheme (varies by expansion): +2 has 2, mid keys add 1, high keys add 1.
    if level < 5 then return 2 end
    if level < 10 then return 3 end
    return 4
end

---@return number[] ids
---@return table<number, string> namesById
local function GetWeeklyAffixIds()
    local ids = {}
    local namesById = {}

    local C_MythicPlus = _G.C_MythicPlus
    if not (C_MythicPlus and type(C_MythicPlus.GetCurrentAffixes) == "function") then
        return ids, namesById
    end

    local ok, affixes = pcall(C_MythicPlus.GetCurrentAffixes)
    if ok then
        AppendAffixes(ids, namesById, affixes)
    end

    return ids, namesById
end

local keystoneHeaderScanTip

---@return GameTooltip
local function EnsureKeystoneHeaderScanTooltip()
    if keystoneHeaderScanTip then return keystoneHeaderScanTip end
    keystoneHeaderScanTip = CreateFrame("GameTooltip", "TwichUIKeystoneHeaderScanTooltip", _G.UIParent,
        "GameTooltipTemplate")
    keystoneHeaderScanTip:SetOwner(_G.UIParent, "ANCHOR_NONE")
    keystoneHeaderScanTip:Hide()
    return keystoneHeaderScanTip
end

---@return string|nil
local function GetOwnedKeystoneLink()
    local mp = _G.C_MythicPlus
    if not mp then return nil end

    local function SafeCall(fn, ...)
        if type(fn) ~= "function" then
            return nil
        end
        local ok, a, b, c, d, e = pcall(fn, ...)
        if not ok then
            return nil
        end
        return a, b, c, d, e
    end

    local function ExtractLinkFromReturns(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v ~= "" then
                if v:find("|Hkeystone:", 1, true) then
                    return v
                end
            end
        end
        return nil
    end

    local link = ExtractLinkFromReturns(SafeCall(mp.GetOwnedKeystoneHyperlink))
    if link then return link end

    link = ExtractLinkFromReturns(SafeCall(mp.GetOwnedKeystoneLink))
    if link then return link end

    link = ExtractLinkFromReturns(SafeCall(mp.GetOwnedKeystoneInfo))
    if link then return link end

    -- Fallback: scan player bags for a keystone hyperlink.
    local C_Container = _G.C_Container
    local getNumSlots = C_Container and C_Container.GetContainerNumSlots
    local getItemLink = C_Container and C_Container.GetContainerItemLink
    if type(getNumSlots) == "function" and type(getItemLink) == "function" then
        for bag = 0, 4 do
            local slots = tonumber(getNumSlots(bag)) or 0
            for slot = 1, slots do
                local lnk = getItemLink(bag, slot)
                if type(lnk) == "string" and lnk ~= "" and lnk:find("|Hkeystone:", 1, true) then
                    return lnk
                end
            end
        end
    end

    return nil
end

---@param link string
---@return string[]|nil
local function GetKeystoneAffixNamesFromLinkTooltip(link)
    if type(link) ~= "string" or link == "" then return nil end

    local out = {}

    if _G.C_TooltipInfo and type(_G.C_TooltipInfo.GetHyperlink) == "function" then
        local ok, info = pcall(_G.C_TooltipInfo.GetHyperlink, link)
        if ok and type(info) == "table" and type(info.lines) == "table" then
            for _, line in ipairs(info.lines) do
                local t = type(line) == "table" and line.leftText or nil
                if type(t) == "string" and t ~= "" then
                    local c = type(line) == "table" and line.leftColor or nil
                    local r = type(c) == "table" and (c.r or c[1]) or nil
                    local g = type(c) == "table" and (c.g or c[2]) or nil
                    local b = type(c) == "table" and (c.b or c[3]) or nil

                    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                        if r < 0.35 and g > 0.75 and b < 0.35 then
                            out[#out + 1] = t
                        end
                    end
                end
            end
        end
    end

    if #out > 0 then
        return out
    end

    local tip = EnsureKeystoneHeaderScanTooltip()
    tip:ClearLines()
    if type(tip.SetHyperlink) == "function" then
        pcall(tip.SetHyperlink, tip, link)
    end

    local n = tip:NumLines() or 0
    for i = 1, n do
        local fs = _G["TwichUIKeystoneHeaderScanTooltipTextLeft" .. tostring(i)]
        if fs and fs.GetText and fs.GetTextColor then
            local t = fs:GetText()
            if type(t) == "string" and t ~= "" then
                local r, g, b = fs:GetTextColor()
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    if r < 0.35 and g > 0.75 and b < 0.35 then
                        out[#out + 1] = t
                    end
                end
            end
        end
    end

    if #out > 0 then
        return out
    end

    return nil
end

---@return number[] affixIds
---@return table<number, string> namesById
---@return string source
---@return string[]|nil affixNames
local function GetHeaderKeystoneAffixIds(level)
    local ids = {}
    local namesById = {}

    local source = "none"

    -- Prefer parsing the owned keystone tooltip when possible.
    -- This matches the in-game keystone tooltip even if keystone affix APIs return a superset.
    do
        local link = GetOwnedKeystoneLink()
        if link then
            local names = GetKeystoneAffixNamesFromLinkTooltip(link)
            if type(names) == "table" and #names > 0 then
                source = "keystone.tooltip"
                return ids, namesById, source, names
            end
        end
    end

    local weeklyIds, weeklyNames = GetWeeklyAffixIds()
    local weeklySet = {}
    if type(weeklyIds) == "table" then
        for _, wid in ipairs(weeklyIds) do
            weeklySet[wid] = true
            if weeklyNames and weeklyNames[wid] then
                namesById[wid] = weeklyNames[wid]
            end
        end
    end

    local function IntersectWithWeekly(rawIds)
        if type(rawIds) ~= "table" or #rawIds == 0 then return rawIds end
        if type(weeklyIds) ~= "table" or #weeklyIds == 0 then return rawIds end

        local rawSet = {}
        for _, id in ipairs(rawIds) do
            rawSet[id] = true
        end

        -- Preserve the official order from the weekly API.
        local filtered = {}
        for _, wid in ipairs(weeklyIds) do
            if rawSet[wid] then
                filtered[#filtered + 1] = wid
            end
        end

        -- If intersection was empty (some seasons/patches report seasonal differently), keep raw.
        if #filtered == 0 then
            return rawIds
        end
        return filtered
    end

    -- Best source: the addon API module which prefers per-keystone affix IDs when available.
    do
        local api = MythicPlusModule and MythicPlusModule.API
        if api and type(api.GetPlayerKeystone) == "function" then
            local info = api:GetPlayerKeystone()
            if info and type(info.affixes) == "table" and #info.affixes > 0 then
                local raw = {}
                for _, id in ipairs(info.affixes) do
                    if type(id) == "number" and id > 0 then
                        raw[#raw + 1] = id
                    end
                end
                if #raw > 0 then
                    ids = IntersectWithWeekly(raw)
                    source = "api.keystoneAffixIDs"
                    if #weeklyIds > 0 and #ids < #raw then
                        source = source .. "∩weekly"
                    end
                    return ids, namesById, source, nil
                end
            end
        end
    end

    local C_MythicPlus = _G.C_MythicPlus

    -- Preferred client API variant: per-keystone affix IDs by index.
    if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneAffixID) == "function" then
        local raw = {}
        for i = 1, 10 do
            local ok, affixID = pcall(C_MythicPlus.GetOwnedKeystoneAffixID, i)
            affixID = ok and tonumber(affixID) or nil
            if not affixID or affixID == 0 then
                break
            end
            raw[#raw + 1] = affixID
        end
        if #raw > 0 then
            ids = IntersectWithWeekly(raw)
            source = "C_MythicPlus.GetOwnedKeystoneAffixID"
            if #weeklyIds > 0 and #ids < #raw then
                source = source .. "∩weekly"
            end
            return ids, namesById, source, nil
        end
    end

    if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneAffixes) == "function" then
        local ok, affixes = pcall(C_MythicPlus.GetOwnedKeystoneAffixes)
        if ok then
            AppendAffixes(ids, namesById, affixes)
        end
        if #ids > 0 then
            ids = IntersectWithWeekly(ids)
            source = "C_MythicPlus.GetOwnedKeystoneAffixes"
            if #weeklyIds > 0 then
                source = source .. "∩weekly"
            end
            return ids, namesById, source, nil
        end
    end

    -- Last resort: weekly affixes. If we have a keystone level, try to only show the relevant count.
    if C_MythicPlus and type(C_MythicPlus.GetCurrentAffixes) == "function" then
        local ok, affixes = pcall(C_MythicPlus.GetCurrentAffixes)
        if ok then
            AppendAffixes(ids, namesById, affixes)
        end

        local expected = GetExpectedAffixCountForLevel(level)
        if expected > 0 and #ids > expected then
            -- Assume the API returns affixes in the same order as the official tooltip.
            local sliced = {}
            for i = 1, expected do
                sliced[i] = ids[i]
            end
            ids = sliced
            source = "weekly-sliced"
        else
            source = "weekly"
        end
    end

    return ids, namesById, source, nil
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

    local mpData = MythicPlusModule and MythicPlusModule.Data
    if mpData and type(mpData.GetMapNameCached) == "function" then
        return mpData.GetMapNameCached(mapId)
    end

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
        if E and E.media and E.media.backdropcolor and frame.SetBackdropColor then
            local r, g, b = unpack(E.media.backdropcolor)
            frame:SetBackdropColor(r or 0, g or 0, b or 0, 1)
        end
        if E and E.media and E.media.bordercolor and frame.SetBackdropBorderColor then
            local r, g, b = unpack(E.media.bordercolor)
            frame:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
        end
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
    do
        local r, g, b = unpack(E.media.backdropcolor)
        frame:SetBackdropColor(r or 0, g or 0, b or 0, 1)
    end
    do
        local r, g, b = unpack(E.media.bordercolor)
        frame:SetBackdropBorderColor(r or 1, g or 1, b or 1, 1)
    end
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
---@param opts table|nil { label?:string, order?:number, icon?:string, iconCoords?:table, iconSize?:table }
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
        if type(opts.iconSize) == "table" and type(opts.iconSize[1]) == "number" and type(opts.iconSize[2]) == "number" then
            panel.iconSize = { opts.iconSize[1], opts.iconSize[2] }
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

---@param frame Frame
local function AttachAnimations(frame)
    ---@cast frame TwichUI_FadeFrame
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
            local currentFrame = current.frame
            ---@cast currentFrame TwichUI_FadeFrame
            AttachAnimations(currentFrame)

            -- Store onHide callback to be called after animation
            currentFrame.onHideCallback = function()
                if type(current.onHide) == "function" then
                    pcall(current.onHide, currentFrame, self)
                end
            end

            currentFrame.FadeInGroup:Stop()
            currentFrame.FadeOutAnim:SetFromAlpha(currentFrame:GetAlpha())
            currentFrame.FadeOutGroup:Play()
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

    local nextFrame = nextPanel.frame
    ---@cast nextFrame TwichUI_FadeFrame
    AttachAnimations(nextFrame)

    self.activePanelId = id

    nextFrame.FadeOutGroup:Stop()
    if not nextFrame:IsShown() then
        nextFrame:SetAlpha(0)
    end
    nextFrame:Show()
    nextFrame.FadeInAnim:SetFromAlpha(nextFrame:GetAlpha())
    nextFrame.FadeInGroup:Play()

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
    local rightAnchor = self.closeButton

    local header = CreateFrame("Frame", nil, self.titleBar)
    header:SetPoint("LEFT", leftAnchor, "RIGHT", 12, 0)
    header:SetPoint("RIGHT", rightAnchor, "LEFT", -10, 0)
    header:SetHeight(HEADER_HEIGHT)

    local text = header:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", header, "LEFT", 0, 0)
    text:SetPoint("RIGHT", header, "RIGHT", 0, 0)
    text:SetJustifyH("CENTER")
    if text.SetFontObject then
        text:SetFontObject(_G.GameFontHighlight)
    end
    text:SetText("Keystone: …")

    -- Make the keystone header text interactive: hover shows a keystone-like affix list, click jumps to dungeon page.
    local headerTextButton = CreateFrame("Button", nil, header)
    headerTextButton:SetAllPoints(text)
    headerTextButton:EnableMouse(true)
    headerTextButton:RegisterForClicks("LeftButtonUp")
    headerTextButton:RegisterForDrag("LeftButton")
    headerTextButton:SetScript("OnEnter", function(b)
        if not GameTooltip then return end

        local mapId = self.__twichuiHeaderKeystoneMapId
        local level = self.__twichuiHeaderKeystoneLevel
        local affixIds, namesById, source, affixNames = GetHeaderKeystoneAffixIds(level)
        self.__twichuiHeaderKeystoneAffixIds = affixIds

        if not mapId or not level then
            return
        end

        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Dungeon Modifiers:", 1, 1, 1)

        local any = false
        if type(affixNames) == "table" and #affixNames > 0 then
            for _, name in ipairs(affixNames) do
                if type(name) == "string" and name ~= "" then
                    GameTooltip:AddLine("  " .. name, 0, 1, 0)
                    any = true
                end
            end
        elseif type(affixIds) == "table" then
            for _, affixId in ipairs(affixIds) do
                local name = GetAffixInfo(affixId)
                if (not name or name == "") and namesById and namesById[affixId] then
                    name = namesById[affixId]
                end
                if name and name ~= "" then
                    GameTooltip:AddLine("  " .. name, 0, 1, 0)
                    any = true
                end
            end
        end

        if not any then
            GameTooltip:AddLine("  No affixes", 0.7, 0.7, 0.7)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open dungeon page", 0.7, 0.7, 0.7)

        -- Optional debugging: hold Shift while hovering to show affix source + IDs.
        if type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
            local idsText = (type(affixIds) == "table" and table.concat(affixIds, ",")) or ""
            local namesText = (type(affixNames) == "table" and table.concat(affixNames, " | ")) or ""
            local weeklyText = (type(GetWeeklyAffixIds) == "function") and (function()
                local w = GetWeeklyAffixIds()
                return (type(w) == "table" and table.concat(w, ",")) or ""
            end)() or ""
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
            "Debug: source=" ..
            tostring(source) .. " ids=[" .. tostring(idsText) .. "] weekly=[" .. tostring(weeklyText) .. "]", 0.6, 0.6,
                0.6, true)
            if namesText ~= "" then
                GameTooltip:AddLine("Debug: names=[" .. tostring(namesText) .. "]", 0.6, 0.6, 0.6, true)
            end
            if Logger and Logger.Debug then
                local msg = "Keystone header affixes: source=" ..
                tostring(source) ..
                " level=" ..
                tostring(level) .. " ids=[" .. tostring(idsText) .. "] weekly=[" .. tostring(weeklyText) .. "]"
                if namesText ~= "" then
                    msg = msg .. " names=[" .. tostring(namesText) .. "]"
                end
                Logger.Debug(msg)
            end
        end

        GameTooltip:Show()
    end)
    headerTextButton:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Support dragging the whole frame from the header text region (so it doesn't block titleBar dragging).
    headerTextButton:SetScript("OnDragStart", function()
        if self.frame and self.frame.StartMoving then
            if self.frame.Raise then
                self.frame:Raise()
            end
            self.frame:StartMoving()
        end
    end)
    headerTextButton:SetScript("OnDragStop", function()
        if self.frame and self.frame.StopMovingOrSizing then
            self.frame:StopMovingOrSizing()
        end
        self:SaveFramePosition()
    end)

    headerTextButton:SetScript("OnClick", function()
        local mapId = self.__twichuiHeaderKeystoneMapId
        if not mapId then return end

        if self.ShowPanel then
            self:ShowPanel("dungeons")
        end

        local function selectDungeon()
            local panel = (self.GetPanelFrame and self:GetPanelFrame("dungeons")) or nil
            ---@cast panel TwichUI_MythicPlus_DungeonsPanel|nil
            if panel and panel.SelectDungeonMap then
                panel:SelectDungeonMap(mapId)
            end
        end

        local C_Timer = _G.C_Timer
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, selectDungeon)
        else
            selectDungeon()
        end
    end)

    self.header = header
    self.headerText = text
    self.headerTextButton = headerTextButton
    self.headerAffixButtons = {}

    self:UpdateTypography()

    -- Optional simulator shortcut button (developer toggle).
    self:_EnsureSimulatorHeaderButton()

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

        -- Points are finalized by _LayoutHeaderIcons(). Seed a non-overlapping default.
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

    -- Apply developer toggle + correct layout now that buttons exist.
    self:UpdateSimulatorHeaderButton()
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

    self.__twichuiHeaderKeystoneMapId = ownedMapID
    self.__twichuiHeaderKeystoneLevel = level

    if ownedMapID and level then
        self.headerText:SetText(string.format("%s  |cff00ff00+%d|r", name, level))
    else
        self.headerText:SetText(name)
    end

    local affixIds = {}
    local affixNames = nil
    if ownedMapID and level and level >= 2 then
        local ids, _, _, names = GetHeaderKeystoneAffixIds(level)
        if type(ids) == "table" then
            affixIds = ids
        end
        if type(names) == "table" and #names > 0 then
            affixNames = names
        end
    end

    self.__twichuiHeaderKeystoneAffixIds = affixIds
    self.__twichuiHeaderKeystoneAffixNames = affixNames

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

    self:_LayoutHeaderIcons()

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

function MainWindow:_ShowDefaultPanel()
    self:_EnsurePanelTables()

    -- Default to Summary when available.
    if self._panels and self._panels["summary"] and type(self._panels["summary"].factory) == "function" then
        self:ShowPanel("summary")
        return
    end

    self:_ShowFirstRegisteredPanelIfNeeded()
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
    if self.headerTextButton and self.headerTextButton.EnableMouse then
        self.headerTextButton:EnableMouse(not locked)
    end

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
    self.frame:SetScript("OnDragStart", function(f)
        if f and f.Raise then
            f:Raise()
        end
        f:StartMoving()
    end)
    self.frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        self:SaveFramePosition()
    end)

    self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function()
        if self.frame and self.frame.StartMoving then
            if self.frame.Raise then
                self.frame:Raise()
            end
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

function MainWindow:UpdateTypography()
    local fontPath = GetFontPath()
    local fontSize = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_TITLE_FONT_SIZE)
    local color = CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_TITLE_TEXT_COLOR)

    local function ApplyToFontString(fontString, fallbackFontObject)
        if not fontString then return end

        if fontPath and fontSize and fontString.SetFont then
            fontString:SetFont(fontPath, fontSize, "OUTLINE")
        elseif fallbackFontObject and fontString.SetFontObject then
            fontString:SetFontObject(fallbackFontObject)
        end

        if color and fontString.SetTextColor then
            fontString:SetTextColor(color.r or 1, color.g or 1, color.b or 1)
        end
    end

    ApplyToFontString(self.titleText, _G.GameFontNormal)
    ApplyToFontString(self.headerText, _G.GameFontHighlight)

    if self.navButtons then
        for _, btn in pairs(self.navButtons) do
            if btn then
                local text = rawget(btn, "__twichuiText")
                if text then
                    ApplyToFontString(text, _G.GameFontNormal)
                end
            end
        end
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
    titleText:SetPoint("LEFT", titleBar, "LEFT", 5, 0)
    if titleText.SetFontObject then
        titleText:SetFontObject(_G.GameFontNormal)
    end
    self.titleText = titleText
    self:UpdateTitleStyling()

    -- Replace text title with custom texture
    titleText:SetText("")
    titleText:Hide()

    local logoButton = CreateFrame("Button", nil, titleBar)
    logoButton:SetPoint("LEFT", titleBar, "LEFT", 5, 0)
    logoButton:SetSize(22, 22)
    logoButton:SetHitRectInsets(-8, -8, -8, -8)

    local logo = logoButton:CreateTexture(nil, "OVERLAY")
    logo:SetAllPoints(logoButton)
    logo:SetTexture("Interface\\AddOns\\TwichUI\\Media\\Textures\\twich-logo.tga")
    logo:SetVertexColor(1, 1, 1, 0.85)

    logoButton:SetScript("OnEnter", function()
        logo:SetVertexColor(1, 1, 1, 1)
        if not GameTooltip then return end
        GameTooltip:SetOwner(logoButton, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open TwichUI Settings", 1, 1, 1)
        GameTooltip:Show()
    end)
    logoButton:SetScript("OnLeave", function()
        logo:SetVertexColor(1, 1, 1, 0.85)
        if GameTooltip then GameTooltip:Hide() end
    end)
    logoButton:SetScript("OnClick", function()
        if T and type(T.ToggleOptionsUI) == "function" then
            T:ToggleOptionsUI()
        end
    end)

    self.titleLogo = logoButton

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
        bg:SetColorTexture(r or 0, g or 0, b or 0, 1)
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
                    if panel.iconSize and type(panel.iconSize[1]) == "number" and type(panel.iconSize[2]) == "number" then
                        btn.NavIcon:SetSize(panel.iconSize[1], panel.iconSize[2])
                    else
                        btn.NavIcon:SetSize(24, 24)
                    end
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

    self:UpdateTypography()
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
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)

    frame:SetScript("OnMouseDown", function(f)
        if f and f.Raise then
            f:Raise()
        end
    end)

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
    self:UpdateTypography()
    self:UpdateLockState()
end

function MainWindow:ShowAnimated()
    if not self.frame then return end
    local f = self.frame

    ---@cast f TwichUI_FadeFrame
    AttachAnimations(f)

    if f.Raise then
        f:Raise()
    end

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

    ---@cast f TwichUI_FadeFrame
    AttachAnimations(f)

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
        self:_ShowDefaultPanel()
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

    self:_ShowDefaultPanel()
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
