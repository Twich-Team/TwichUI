local T = unpack(Twich)

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

---@class MythicPlusHandbookSubmodule
local Handbook = MythicPlusModule.Handbook or {}
MythicPlusModule.Handbook = Handbook

---@type DataModule
local DataModule = T:GetModule("Data")

---@type ToolsModule
local Tools = T:GetModule("Tools")
local CT = Tools and Tools.Colors

local _G = _G
local CreateFrame = _G.CreateFrame

local ElvUI = _G.ElvUI
local E = ElvUI and ElvUI[1]

local ICON_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\handbook.tga"
local ARROW_UP_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\arrow-up.tga"
local ARROW_DOWN_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\arrow-down.tga"
local X_ICON_PATH = "Interface\\AddOns\\TwichUI\\Media\\Textures\\x.tga"
local PANEL_ID = "handbook"
local LABEL_TEXT = "Handbook"

local function GetColor(key)
    if CT and CT.TWICH and CT.TWICH[key] then
        local hex = CT.TWICH[key]
        if type(hex) == "string" and hex:sub(1, 1) == "#" and #hex >= 7 then
            local r = tonumber(hex:sub(2, 3), 16) or 255
            local g = tonumber(hex:sub(4, 5), 16) or 255
            local b = tonumber(hex:sub(6, 7), 16) or 255
            return r / 255, g / 255, b / 255
        end
    end
    return 1, 1, 1
end

local COLOR_PRIMARY = { GetColor("TEXT_PRIMARY") }
local COLOR_MUTED = { GetColor("TEXT_MUTED") }
local COLOR_ACCENT = { GetColor("SECONDARY_ACCENT") }

local function ColorWrap(text, r, g, b)
    local rr = math.max(0, math.min(255, math.floor((tonumber(r) or 1) * 255 + 0.5)))
    local gg = math.max(0, math.min(255, math.floor((tonumber(g) or 1) * 255 + 0.5)))
    local bb = math.max(0, math.min(255, math.floor((tonumber(b) or 1) * 255 + 0.5)))
    return string.format("|cff%02x%02x%02x%s|r", rr, gg, bb, tostring(text or ""))
end

local function HexToRGB(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("%s+", "")
    if hex:sub(1, 1) == "#" then
        hex = hex:sub(2)
    end
    if #hex ~= 6 then
        return nil
    end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then
        return nil
    end
    return r / 255, g / 255, b / 255
end

local function SetFont(fontString, style)
    if not fontString then return end
    if style == "large" then
        fontString:SetFontObject("GameFontNormalLarge")
    elseif style == "small" then
        fontString:SetFontObject("GameFontNormalSmall")
    else
        fontString:SetFontObject("GameFontNormal")
    end
end

---@class TwichUI_HandbookArrowButton : Button
---@field __twichuiArrowIcon Texture|nil
---@field __twichuiArrowHL Texture|nil

---@param btn Button
---@param direction "up"|"down"
local function SkinArrowButton(btn, direction)
    if not btn or not btn.CreateTexture then return end

    ---@cast btn TwichUI_HandbookArrowButton

    -- Clear any text label so the button reads as an icon.
    if btn.SetText then
        btn:SetText("")
    end

    -- Hide UIPanelButtonTemplate pieces if they exist.
    local templateRegions = {
        "Left", "Middle", "Right",
        "LeftDisabled", "MiddleDisabled", "RightDisabled",
    }
    for _, key in ipairs(templateRegions) do
        local r = btn[key]
        if r and r.Hide then r:Hide() end
    end

    local texPath = (direction == "down") and ARROW_DOWN_PATH or ARROW_UP_PATH

    -- Buttons are typically 18px tall in these rows.
    local iconW, iconH = 16, 18 -- Keeps 32x36 aspect ratio.

    local icon = btn.__twichuiArrowIcon
    if not icon then
        icon = btn:CreateTexture(nil, "ARTWORK")
        btn.__twichuiArrowIcon = icon
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetSize(iconW, iconH)
    icon:SetTexture(texPath)
    icon:SetTexCoord(0, 1, 0, 1)

    local hl = btn.__twichuiArrowHL
    if not hl then
        hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.__twichuiArrowHL = hl
    end
    hl:ClearAllPoints()
    hl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    hl:SetSize(iconW, iconH)
    hl:SetTexture(texPath)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    hl:SetAlpha(0.25)

    local function UpdateState()
        local enabled = (btn.IsEnabled and btn:IsEnabled()) or false
        if icon.SetDesaturated then
            icon:SetDesaturated(not enabled)
        end
        icon:SetAlpha(enabled and 1 or 0.35)
    end

    if btn.HookScript then
        btn:HookScript("OnEnable", UpdateState)
        btn:HookScript("OnDisable", UpdateState)
    end
    UpdateState()
end

---@class TwichUI_HandbookXButton : Button
---@field __twichuiXIcon Texture|nil
---@field __twichuiXHL Texture|nil

---@param btn Button
local function SkinXButton(btn)
    if not btn or not btn.CreateTexture then return end

    ---@cast btn TwichUI_HandbookXButton

    if btn.SetText then
        btn:SetText("")
    end

    local templateRegions = {
        "Left", "Middle", "Right",
        "LeftDisabled", "MiddleDisabled", "RightDisabled",
    }
    for _, key in ipairs(templateRegions) do
        local r = btn[key]
        if r and r.Hide then r:Hide() end
    end

    -- 32x31 original. Fit nicely into 18px-tall rows without looking cramped.
    local iconH = 16
    local iconW = (iconH * 32) / 31

    local icon = btn.__twichuiXIcon
    if not icon then
        icon = btn:CreateTexture(nil, "ARTWORK")
        btn.__twichuiXIcon = icon
    end
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetSize(iconW, iconH)
    icon:SetTexture(X_ICON_PATH)
    icon:SetTexCoord(0, 1, 0, 1)

    local hl = btn.__twichuiXHL
    if not hl then
        hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.__twichuiXHL = hl
    end
    hl:ClearAllPoints()
    hl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    hl:SetSize(iconW, iconH)
    hl:SetTexture(X_ICON_PATH)
    if hl.SetBlendMode then hl:SetBlendMode("ADD") end
    hl:SetAlpha(0.22)

    local function UpdateState()
        local enabled = (btn.IsEnabled and btn:IsEnabled()) or false
        if icon.SetDesaturated then
            icon:SetDesaturated(not enabled)
        end
        icon:SetAlpha(enabled and 1 or 0.35)
    end

    if btn.HookScript then
        btn:HookScript("OnEnable", UpdateState)
        btn:HookScript("OnDisable", UpdateState)
    end
    UpdateState()
end

local FALLBACK_PROFILE_DB = {
    statPriority = {
        list = {},
    },
    gearEnhancements = {
        selectedBySlot = {},
        gemPriority = {
            list = {},
        },
    },
}

---@return {list:string[]}
local function GetStatPriorityDB()
    local profile = (T and T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.handbook = profile.mythicPlus.handbook or {}
        profile.mythicPlus.handbook.statPriority = profile.mythicPlus.handbook.statPriority or {}
        local db = profile.mythicPlus.handbook.statPriority
        db.list = db.list or {}
        return db
    end
    FALLBACK_PROFILE_DB.statPriority.list = FALLBACK_PROFILE_DB.statPriority.list or {}
    return FALLBACK_PROFILE_DB.statPriority
end

---@return {selectedBySlot:table<string, number|nil>, gemPriority:{list:{itemId:number, maxCount:number|nil}[]}}
local function GetGearEnhancementsDB()
    local profile = (T and T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.handbook = profile.mythicPlus.handbook or {}
        profile.mythicPlus.handbook.gearEnhancements = profile.mythicPlus.handbook.gearEnhancements or {}

        local db = profile.mythicPlus.handbook.gearEnhancements
        db.selectedBySlot = db.selectedBySlot or {}
        db.gemPriority = db.gemPriority or {}
        db.gemPriority.list = db.gemPriority.list or {}
        return db
    end

    FALLBACK_PROFILE_DB.gearEnhancements.selectedBySlot = FALLBACK_PROFILE_DB.gearEnhancements.selectedBySlot or {}
    FALLBACK_PROFILE_DB.gearEnhancements.gemPriority = FALLBACK_PROFILE_DB.gearEnhancements.gemPriority or {}
    FALLBACK_PROFILE_DB.gearEnhancements.gemPriority.list = FALLBACK_PROFILE_DB.gearEnhancements.gemPriority.list or {}
    return FALLBACK_PROFILE_DB.gearEnhancements
end

local function EnsureDropDownAPI()
    if type(_G.UIDropDownMenu_Initialize) == "function" then
        return true
    end

    if _G.InCombatLockdown and _G.InCombatLockdown() then
        return false
    end

    if _G.C_AddOns and _G.C_AddOns.LoadAddOn then
        pcall(_G.C_AddOns.LoadAddOn, "Blizzard_Deprecated")
    elseif _G.UIParentLoadAddOn then
        pcall(_G.UIParentLoadAddOn, "Blizzard_Deprecated")
    end

    return type(_G.UIDropDownMenu_Initialize) == "function"
end

local STAT_DEFS = {
    { key = "STRENGTH",    label = _G.STAT_STRENGTH or "Strength" },
    { key = "AGILITY",     label = _G.STAT_AGILITY or "Agility" },
    { key = "INTELLECT",   label = _G.STAT_INTELLECT or "Intellect" },
    { key = "STAMINA",     label = _G.STAT_STAMINA or "Stamina" },

    { key = "CRIT",        label = _G.STAT_CRITICAL_STRIKE or _G.ITEM_MOD_CRIT_RATING_SHORT or "Critical Strike" },
    { key = "HASTE",       label = _G.STAT_HASTE or _G.ITEM_MOD_HASTE_RATING_SHORT or "Haste" },
    { key = "MASTERY",     label = _G.STAT_MASTERY or _G.ITEM_MOD_MASTERY_RATING_SHORT or "Mastery" },
    { key = "VERSATILITY", label = _G.STAT_VERSATILITY or _G.ITEM_MOD_VERSATILITY or "Versatility" },

    { key = "LEECH",       label = _G.STAT_LIFESTEAL or "Leech" },
    { key = "AVOIDANCE",   label = _G.STAT_AVOIDANCE or "Avoidance" },
    { key = "SPEED",       label = _G.STAT_SPEED or "Speed" },
}

local STAT_LABEL_BY_KEY = {}
for _, def in ipairs(STAT_DEFS) do
    STAT_LABEL_BY_KEY[def.key] = def.label
end

local function CreateHandbookFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)

    -- Tabs bar (keep same pattern as ScoreSimulator for consistency)
    local tabsBar = CreateFrame("Frame", nil, frame)
    tabsBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -8)
    tabsBar:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    tabsBar:SetHeight(28)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", tabsBar, "BOTTOMLEFT", 0, -6)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 12)

    local gearPage = CreateFrame("Frame", nil, content)
    gearPage:SetAllPoints(content)

    local crestsPage = CreateFrame("Frame", nil, content)
    crestsPage:SetAllPoints(content)
    crestsPage:Hide()

    local itemUpgradePage = CreateFrame("Frame", nil, content)
    itemUpgradePage:SetAllPoints(content)
    itemUpgradePage:Hide()

    local statPriorityPage = CreateFrame("Frame", nil, content)
    statPriorityPage:SetAllPoints(content)
    statPriorityPage:Hide()

    local gearEnhancementsPage = CreateFrame("Frame", nil, content)
    gearEnhancementsPage:SetAllPoints(content)
    gearEnhancementsPage:Hide()

    local gemPriorityPage = CreateFrame("Frame", nil, content)
    gemPriorityPage:SetAllPoints(content)
    gemPriorityPage:Hide()

    local analyzeEnhancementsPage = CreateFrame("Frame", nil, content)
    analyzeEnhancementsPage:SetAllPoints(content)
    analyzeEnhancementsPage:Hide()

    local tab1 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab1:SetSize(130, 22)
    tab1:SetText("Gear Tracks")
    tab1:SetPoint("TOPLEFT", tabsBar, "TOPLEFT", 0, 2)

    local tab2 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab2:SetSize(110, 22)
    tab2:SetText("Crests")
    tab2:SetPoint("LEFT", tab1, "RIGHT", 8, 0)

    local tab3 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab3:SetSize(120, 22)
    tab3:SetText("Item Upgrade")
    tab3:SetPoint("LEFT", tab2, "RIGHT", 8, 0)

    local tab4 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab4:SetSize(120, 22)
    tab4:SetText("Stat Priority")
    tab4:SetPoint("LEFT", tab3, "RIGHT", 8, 0)

    local tab5 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab5:SetSize(150, 22)
    tab5:SetText("Gear Enhancements")
    tab5:SetPoint("LEFT", tab4, "RIGHT", 8, 0)

    local tab6 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab6:SetSize(120, 22)
    tab6:SetText("Gem Priority")
    tab6:SetPoint("LEFT", tab5, "RIGHT", 8, 0)

    local tab7 = CreateFrame("Button", nil, tabsBar, "UIPanelButtonTemplate")
    tab7:SetSize(210, 22)
    tab7:SetText("Analyze Slot Enhancements")
    tab7:SetPoint("LEFT", tab6, "RIGHT", 8, 0)

    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(tab1)
            S:HandleButton(tab2)
            S:HandleButton(tab3)
            S:HandleButton(tab4)
            S:HandleButton(tab5)
            S:HandleButton(tab6)
            S:HandleButton(tab7)
        end
    end

    local function SetTabSelected(btn, selected)
        if not btn then return end
        if selected then
            btn:Disable()
            local fs = btn.GetFontString and btn:GetFontString() or nil
            if fs then fs:SetTextColor(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3]) end
        else
            btn:Enable()
            local fs = btn.GetFontString and btn:GetFontString() or nil
            if fs then fs:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]) end
        end
    end

    local function ApplySelectedItemTooltip(button)
        if not button or button.__twichuiHasSelectedTooltip then return end
        button.__twichuiHasSelectedTooltip = true

        button:HookScript("OnEnter", function(self)
            local id = tonumber(self.__twichuiItemID)
            if not id or id <= 0 or not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(_G.GameTooltip.SetItemByID) == "function" then
                pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
            else
                local link = select(2, _G.GetItemInfo(id))
                if link and type(_G.GameTooltip.SetHyperlink) == "function" then
                    _G.GameTooltip:SetHyperlink(link)
                end
            end
            _G.GameTooltip:Show()
        end)

        button:HookScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
    end

    do
        local tabs = { tab1, tab2, tab3, tab4, tab5, tab6, tab7 }
        local function LayoutTabs()
            local w = tabsBar:GetWidth() or 0
            if w <= 1 then return end

            local spacingX = 8
            local spacingY = 4
            local topPad = 2
            local bottomPad = 4

            local x = 0
            local y = -topPad
            local rows = 1
            local rowHeight = (tabs[1] and tabs[1].GetHeight and tabs[1]:GetHeight()) or 22

            for _, t in ipairs(tabs) do
                if t then
                    t:ClearAllPoints()
                    local tw = (t.GetWidth and t:GetWidth()) or 0
                    if x > 0 and (x + tw) > w then
                        x = 0
                        y = y - (rowHeight + spacingY)
                        rows = rows + 1
                    end
                    t:SetPoint("TOPLEFT", tabsBar, "TOPLEFT", x, y)
                    x = x + tw + spacingX
                end
            end

            tabsBar:SetHeight((rows * rowHeight) + ((rows - 1) * spacingY) + topPad + bottomPad)
        end

        tabsBar:SetScript("OnSizeChanged", LayoutTabs)
        tabsBar:HookScript("OnShow", LayoutTabs)
        LayoutTabs()
    end

    local MAX_ROWS = 60

    local function CreateTablePage(page, titleText, columns)
        local panel = CreateFrame("Frame", nil, page, "BackdropTemplate")
        panel:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)

        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        panel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        panel:SetBackdropBorderColor(0, 0, 0, 1)

        local header = panel:CreateFontString(nil, "OVERLAY")
        SetFont(header, "normal")
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
        header:SetText(titleText)
        header:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

        local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleScrollBar and scroll.ScrollBar then
                S:HandleScrollBar(scroll.ScrollBar)
            end
        end

        local scrollChild = CreateFrame("Frame", nil, scroll)
        scrollChild:SetPoint("TOPLEFT")
        scrollChild:SetSize(1, 1)
        scroll:SetScrollChild(scrollChild)

        local tableHeader = CreateFrame("Frame", nil, scrollChild)
        tableHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        tableHeader:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        tableHeader:SetHeight(18)

        for i, col in ipairs(columns) do
            local hdr = tableHeader:CreateFontString(nil, "OVERLAY")
            SetFont(hdr, "small")
            hdr:SetPoint("LEFT", tableHeader, "LEFT", col.x or 0, 0)
            hdr:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
            hdr:SetText(col.label or "")
        end

        local headerSep = scrollChild:CreateTexture(nil, "ARTWORK")
        headerSep:SetColorTexture(1, 1, 1, 0.10)
        headerSep:SetHeight(1)
        headerSep:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -4)
        headerSep:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

        local rows = {}

        local function EnsureRow(rowIndex)
            if rows[rowIndex] then return rows[rowIndex] end

            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(18)
            row:EnableMouse(true)

            local base = row:CreateTexture(nil, "BACKGROUND")
            base:SetAllPoints(row)
            if E and E.media and E.media.bordercolor then
                local r, g, b = unpack(E.media.bordercolor)
                base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
            else
                base:SetColorTexture(1, 1, 1, 0.05)
            end
            if (rowIndex % 2) == 0 then
                base:Show()
            else
                base:Hide()
            end
            row.__twichuiBaseBG = base

            local hover = row:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints(row)
            if E and E.media and E.media.bordercolor then
                local r, g, b = unpack(E.media.bordercolor)
                hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
            else
                hover:SetColorTexture(1, 1, 1, 0.10)
            end
            hover:Hide()
            row.__twichuiHoverBG = hover

            row:SetScript("OnEnter", function(self)
                if self.__twichuiHoverBG then
                    self.__twichuiHoverBG:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if self.__twichuiHoverBG then
                    self.__twichuiHoverBG:Hide()
                end
            end)

            if rowIndex == 1 then
                row:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 0, -8)
            else
                row:SetPoint("TOPLEFT", rows[rowIndex - 1], "BOTTOMLEFT", 0, -6)
            end
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

            row.cols = {}
            for i, col in ipairs(columns) do
                local fs = row:CreateFontString(nil, "OVERLAY")
                SetFont(fs, "normal")
                fs:SetPoint("LEFT", row, "LEFT", col.x or 0, 0)
                fs:SetWidth(col.width or 100)
                fs:SetJustifyH("LEFT")
                row.cols[i] = fs
            end

            row:Hide()
            rows[rowIndex] = row
            return row
        end

        local function ClearRows()
            for i = 1, MAX_ROWS do
                if rows[i] then
                    rows[i]:Hide()
                end
            end
        end

        local function SetScrollHeight(lastWidget)
            local bottom = lastWidget or headerSep
            local h = 0
            if bottom and bottom.GetBottom and scrollChild.GetTop then
                local top = scrollChild:GetTop() or 0
                local bot = bottom:GetBottom() or 0
                h = (top - bot) + 20
            end
            if h < 1 then h = 1 end
            scrollChild:SetSize(520, h)
        end

        return {
            EnsureRow = EnsureRow,
            ClearRows = ClearRows,
            SetScrollHeight = SetScrollHeight,
            HeaderSep = headerSep,
        }
    end

    local gearTable = CreateTablePage(gearPage, "Gear Tracks", {
        { label = "Keystone",         x = 0,   width = 150 },
        { label = "Vault Item Level", x = 160, width = 120 },
        { label = "Track",            x = 300, width = 220 },
    })

    local crestsTable = CreateTablePage(crestsPage, "Crests", {
        { label = "Crest",    x = 0,   width = 160 },
        { label = "Keystone", x = 180, width = 110 },
        { label = "Delve",    x = 310, width = 110 },
        { label = "Raid",     x = 440, width = 110 },
    })

    local itemUpgradeTable = CreateTablePage(itemUpgradePage, "Item Upgrade", {
        { label = "Track",      x = 0,   width = 260 },
        { label = "Crest Cost", x = 280, width = 180 },
    })

    -- Stat Priority (profile-backed)
    local statPanel = CreateFrame("Frame", nil, statPriorityPage, "BackdropTemplate")
    statPanel:SetPoint("TOPLEFT", statPriorityPage, "TOPLEFT", 0, 0)
    statPanel:SetPoint("BOTTOMRIGHT", statPriorityPage, "BOTTOMRIGHT", 0, 0)
    statPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    statPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    statPanel:SetBackdropBorderColor(0, 0, 0, 1)

    local statHeader = statPanel:CreateFontString(nil, "OVERLAY")
    SetFont(statHeader, "normal")
    statHeader:SetPoint("TOPLEFT", statPanel, "TOPLEFT", 12, -12)
    statHeader:SetText("Stat Priority")
    statHeader:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local selectedStatKey = nil

    local function StripDropDown(dropdown)
        if not dropdown or type(dropdown.GetName) ~= "function" then return end

        local ddName = dropdown:GetName()
        local left = (ddName and _G[ddName .. "Left"]) or dropdown.Left
        local middle = (ddName and _G[ddName .. "Middle"]) or dropdown.Middle
        local right = (ddName and _G[ddName .. "Right"]) or dropdown.Right
        if left then left:Hide() end
        if middle then middle:Hide() end
        if right then right:Hide() end

        local button = (ddName and _G[ddName .. "Button"]) or dropdown.Button
        if button then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)

            local nt = button.GetNormalTexture and button:GetNormalTexture() or nil
            local pt = button.GetPushedTexture and button:GetPushedTexture() or nil
            local dt = button.GetDisabledTexture and button:GetDisabledTexture() or nil
            local ht = button.GetHighlightTexture and button:GetHighlightTexture() or nil
            if nt then
                nt:SetTexture(nil)
                nt:Hide()
            end
            if pt then
                pt:SetTexture(nil)
                pt:Hide()
            end
            if dt then
                dt:SetTexture(nil)
                dt:Hide()
            end
            if ht then
                ht:SetTexture(nil)
                ht:Hide()
            end
        end

        local text = (ddName and _G[ddName .. "Text"]) or dropdown.Text
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", dropdown, "LEFT", 8, 0)
            text:SetPoint("RIGHT", dropdown, "RIGHT", -8, 0)
        end
    end

    local function MakeDropDownFullClickable(dropdown)
        if not dropdown then return end
        dropdown:EnableMouse(true)
        dropdown:SetScript("OnMouseDown", function()
            local toggle = _G.ToggleDropDownMenu or ToggleDropDownMenu
            if type(toggle) == "function" then
                toggle(1, nil, dropdown, dropdown, 0, 0)
            end
        end)
    end

    local statDropdown = CreateFrame("Frame", "TwichUIHandbookStatPriorityDropdown", statPanel, "UIDropDownMenuTemplate")
    statDropdown:SetPoint("TOPLEFT", statHeader, "BOTTOMLEFT", -10, -6)
    statDropdown:SetFrameLevel(frame:GetFrameLevel() + 100)
    if type(_G.UIDropDownMenu_SetWidth) == "function" then
        _G.UIDropDownMenu_SetWidth(statDropdown, 180)
    end
    if type(_G.UIDropDownMenu_JustifyText) == "function" then
        _G.UIDropDownMenu_JustifyText(statDropdown, "LEFT")
    end

    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleDropDownBox then
            S:HandleDropDownBox(statDropdown)
        end
    end
    StripDropDown(statDropdown)
    MakeDropDownFullClickable(statDropdown)

    local addButton = CreateFrame("Button", nil, statPanel, "UIPanelButtonTemplate")
    addButton:SetSize(60, 22)
    addButton:SetText("Add")
    addButton:SetPoint("LEFT", statDropdown, "RIGHT", 8, 2)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(addButton)
        end
    end

    local statScroll = CreateFrame("ScrollFrame", nil, statPanel, "UIPanelScrollFrameTemplate")
    statScroll:SetPoint("TOPLEFT", statDropdown, "BOTTOMLEFT", 10, -12)
    statScroll:SetPoint("BOTTOMRIGHT", statPanel, "BOTTOMRIGHT", -28, 12)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleScrollBar and statScroll.ScrollBar then
            S:HandleScrollBar(statScroll.ScrollBar)
        end
    end

    local statScrollChild = CreateFrame("Frame", nil, statScroll)
    statScrollChild:SetPoint("TOPLEFT")
    statScrollChild:SetSize(1, 1)
    statScroll:SetScrollChild(statScrollChild)

    local statTableHeader = CreateFrame("Frame", nil, statScrollChild)
    statTableHeader:SetPoint("TOPLEFT", statScrollChild, "TOPLEFT", 0, 0)
    statTableHeader:SetPoint("RIGHT", statScrollChild, "RIGHT", 0, 0)
    statTableHeader:SetHeight(18)

    local hdrPriority = statTableHeader:CreateFontString(nil, "OVERLAY")
    SetFont(hdrPriority, "small")
    hdrPriority:SetPoint("LEFT", statTableHeader, "LEFT", 0, 0)
    hdrPriority:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    hdrPriority:SetText("Priority")

    local hdrStat = statTableHeader:CreateFontString(nil, "OVERLAY")
    SetFont(hdrStat, "small")
    hdrStat:SetPoint("LEFT", statTableHeader, "LEFT", 90, 0)
    hdrStat:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    hdrStat:SetText("Stat")

    local hdrActions = statTableHeader:CreateFontString(nil, "OVERLAY")
    SetFont(hdrActions, "small")
    hdrActions:SetPoint("RIGHT", statTableHeader, "RIGHT", -6, 0)
    hdrActions:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    hdrActions:SetText("Actions")

    local statHeaderSep = statScrollChild:CreateTexture(nil, "ARTWORK")
    statHeaderSep:SetColorTexture(1, 1, 1, 0.10)
    statHeaderSep:SetHeight(1)
    statHeaderSep:SetPoint("TOPLEFT", statTableHeader, "BOTTOMLEFT", 0, -4)
    statHeaderSep:SetPoint("RIGHT", statScrollChild, "RIGHT", 0, 0)

    local statRows = {}

    local function EnsureStatRow(i)
        if statRows[i] then return statRows[i] end

        local row = CreateFrame("Frame", nil, statScrollChild)
        row:SetHeight(18)
        row:EnableMouse(true)

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
        else
            base:SetColorTexture(1, 1, 1, 0.05)
        end
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
        else
            hover:SetColorTexture(1, 1, 1, 0.10)
        end
        hover:Hide()
        row.__twichuiHoverBG = hover

        row:SetScript("OnEnter", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Show() end
        end)
        row:SetScript("OnLeave", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Hide() end
        end)

        if i == 1 then
            row:SetPoint("TOPLEFT", statHeaderSep, "BOTTOMLEFT", 0, -8)
        else
            row:SetPoint("TOPLEFT", statRows[i - 1], "BOTTOMLEFT", 0, -6)
        end
        row:SetPoint("RIGHT", statScrollChild, "RIGHT", 0, 0)

        row.priority = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.priority, "normal")
        row.priority:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.priority:SetWidth(80)
        row.priority:SetJustifyH("LEFT")

        row.stat = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.stat, "normal")
        row.stat:SetPoint("LEFT", row, "LEFT", 90, 0)
        row.stat:SetWidth(220)
        row.stat:SetJustifyH("LEFT")

        row.btnUp = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnUp:SetSize(18, 18)

        row.btnDown = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnDown:SetSize(18, 18)

        row.btnRemove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnRemove:SetSize(22, 18)
        row.btnRemove:SetText("X")
        row.btnRemove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.btnDown:SetPoint("RIGHT", row.btnRemove, "LEFT", -4, 0)
        row.btnUp:SetPoint("RIGHT", row.btnDown, "LEFT", -4, 0)

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then
                S:HandleButton(row.btnUp)
                S:HandleButton(row.btnDown)
                S:HandleButton(row.btnRemove)
            end
        end

        SkinArrowButton(row.btnUp, "up")
        SkinArrowButton(row.btnDown, "down")
        SkinXButton(row.btnRemove)

        row:Hide()
        statRows[i] = row
        return row
    end

    local function ClearStatRows()
        for i = 1, MAX_ROWS do
            if statRows[i] then statRows[i]:Hide() end
        end
    end

    local function SetStatScrollHeight(lastWidget)
        local bottom = lastWidget or statHeaderSep
        local h = 0
        if bottom and bottom.GetBottom and statScrollChild.GetTop then
            local top = statScrollChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        statScrollChild:SetSize(520, h)
    end

    local function RenderStatPriority()
        ClearStatRows()

        local db = GetStatPriorityDB()
        local list = db and db.list or nil
        if type(list) ~= "table" or #list == 0 then
            local row = EnsureStatRow(1)
            row.priority:SetText(ColorWrap("", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.stat:SetText(ColorWrap("Use the dropdown above to add stats", COLOR_MUTED[1], COLOR_MUTED[2],
                COLOR_MUTED[3]))
            row.btnUp:Hide()
            row.btnDown:Hide()
            row.btnRemove:Hide()
            row:Show()
            SetStatScrollHeight(row)
            return
        end

        local last = statHeaderSep
        for i, statKey in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = EnsureStatRow(i)
            row.priority:SetText(ColorWrap(tostring(i), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.stat:SetText(ColorWrap(STAT_LABEL_BY_KEY[statKey] or tostring(statKey), COLOR_PRIMARY[1],
                COLOR_PRIMARY[2], COLOR_PRIMARY[3]))

            row.btnUp:Show()
            row.btnDown:Show()
            row.btnRemove:Show()

            row.btnUp:SetEnabled(i > 1)
            row.btnDown:SetEnabled(i < #list)

            row.btnUp:SetScript("OnClick", function()
                if i <= 1 then return end
                list[i], list[i - 1] = list[i - 1], list[i]
                RenderStatPriority()
            end)
            row.btnDown:SetScript("OnClick", function()
                if i >= #list then return end
                list[i], list[i + 1] = list[i + 1], list[i]
                RenderStatPriority()
            end)
            row.btnRemove:SetScript("OnClick", function()
                table.remove(list, i)
                RenderStatPriority()
            end)

            row:Show()
            last = row
        end

        SetStatScrollHeight(last)
    end

    local function IsStatInList(list, key)
        if type(list) ~= "table" then return false end
        for _, v in ipairs(list) do
            if v == key then return true end
        end
        return false
    end

    local function InitStatDropDown()
        if not EnsureDropDownAPI() then
            return
        end

        local ddInit = _G.UIDropDownMenu_Initialize or UIDropDownMenu_Initialize
        local ddCreateInfo = _G.UIDropDownMenu_CreateInfo or UIDropDownMenu_CreateInfo
        local ddAddButton = _G.UIDropDownMenu_AddButton or UIDropDownMenu_AddButton
        local ddSetSelectedValue = _G.UIDropDownMenu_SetSelectedValue or UIDropDownMenu_SetSelectedValue
        local ddSetText = _G.UIDropDownMenu_SetText or UIDropDownMenu_SetText

        if type(ddInit) ~= "function" or type(ddCreateInfo) ~= "function" or type(ddAddButton) ~= "function" then
            return
        end

        ddInit(statDropdown, function(self, level)
            level = level or 1
            local db = GetStatPriorityDB()
            local list = db and db.list or {}

            local anyAdded = false
            for _, def in ipairs(STAT_DEFS) do
                if not IsStatInList(list, def.key) then
                    anyAdded = true
                    local info = ddCreateInfo()
                    info.text = def.label
                    info.arg1 = def.key
                    info.func = function(_, arg1)
                        selectedStatKey = arg1
                        if type(ddSetSelectedValue) == "function" then ddSetSelectedValue(statDropdown, arg1) end
                        if type(ddSetText) == "function" then
                            ddSetText(statDropdown,
                                STAT_LABEL_BY_KEY[arg1] or tostring(arg1))
                        end
                    end
                    ddAddButton(info, level)
                end
            end

            if not anyAdded then
                local info = ddCreateInfo()
                info.text = "All stats added"
                info.notCheckable = true
                info.disabled = true
                ddAddButton(info, level)
            end
        end)
    end

    InitStatDropDown()
    if type(_G.UIDropDownMenu_SetText) == "function" then
        _G.UIDropDownMenu_SetText(statDropdown, "Select Stat")
    end

    addButton:SetScript("OnClick", function()
        local db = GetStatPriorityDB()
        local list = db.list
        if type(list) ~= "table" then
            db.list = {}
            list = db.list
        end

        local toAdd = selectedStatKey
        if not toAdd then
            for _, def in ipairs(STAT_DEFS) do
                if not IsStatInList(list, def.key) then
                    toAdd = def.key
                    break
                end
            end
        end

        if not toAdd or IsStatInList(list, toAdd) then
            RenderStatPriority()
            return
        end

        table.insert(list, toAdd)
        RenderStatPriority()
    end)

    -- Gear Enhancements (profile-backed)
    local EnsureEnhItemLoadHook = nil
    local function GetItemDisplayFromEntry(entry)
        if not entry then return "" end
        local explicitLink = entry.itemLink
        if type(explicitLink) == "string" and explicitLink ~= "" then
            return explicitLink
        end

        local itemId = tonumber(entry.itemId)
        if not itemId or itemId <= 0 then
            return tostring(entry.label or "")
        end

        if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
            pcall(_G.C_Item.RequestLoadItemDataByID, itemId)
        end

        local name, link = _G.GetItemInfo(itemId)
        if type(link) == "string" and link ~= "" then
            return link
        end
        if type(name) == "string" and name ~= "" then
            return name
        end
        if type(EnsureEnhItemLoadHook) == "function" then
            EnsureEnhItemLoadHook(itemId)
        end
        return tostring(entry.label or "Loading...")
    end

    local function GetItemDisplayFromId(itemId)
        local id = tonumber(itemId)
        if not id or id <= 0 then return "" end
        if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
            pcall(_G.C_Item.RequestLoadItemDataByID, id)
        end
        local name, link = _G.GetItemInfo(id)
        if type(link) == "string" and link ~= "" then
            return link
        end
        if type(name) == "string" and name ~= "" then
            return name
        end
        if type(EnsureEnhItemLoadHook) == "function" then
            EnsureEnhItemLoadHook(id)
        end
        return "Loading..."
    end

    local enhPanel = CreateFrame("Frame", nil, gearEnhancementsPage, "BackdropTemplate")
    enhPanel:SetPoint("TOPLEFT", gearEnhancementsPage, "TOPLEFT", 0, 0)
    enhPanel:SetPoint("BOTTOMRIGHT", gearEnhancementsPage, "BOTTOMRIGHT", 0, 0)
    enhPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    enhPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    enhPanel:SetBackdropBorderColor(0, 0, 0, 1)

    local enhHeader = enhPanel:CreateFontString(nil, "OVERLAY")
    SetFont(enhHeader, "normal")
    enhHeader:SetPoint("TOPLEFT", enhPanel, "TOPLEFT", 12, -12)
    enhHeader:SetText("Gear Enhancements")
    enhHeader:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local slotTitle = enhPanel:CreateFontString(nil, "OVERLAY")
    SetFont(slotTitle, "small")
    slotTitle:SetPoint("TOPLEFT", enhHeader, "BOTTOMLEFT", 0, -10)
    slotTitle:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    slotTitle:SetText("Slot Enhancements")

    local slotScroll = CreateFrame("ScrollFrame", nil, enhPanel, "UIPanelScrollFrameTemplate")
    slotScroll:SetPoint("TOPLEFT", slotTitle, "BOTTOMLEFT", 0, -8)
    slotScroll:SetPoint("RIGHT", enhPanel, "RIGHT", -28, 0)
    slotScroll:SetHeight(220)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleScrollBar and slotScroll.ScrollBar then
            S:HandleScrollBar(slotScroll.ScrollBar)
        end
    end

    local slotScrollChild = CreateFrame("Frame", nil, slotScroll)
    slotScrollChild:SetPoint("TOPLEFT")
    slotScrollChild:SetSize(1, 1)
    slotScroll:SetScrollChild(slotScrollChild)

    local slotHeaderRow = CreateFrame("Frame", nil, slotScrollChild)
    slotHeaderRow:SetPoint("TOPLEFT", slotScrollChild, "TOPLEFT", 0, 0)
    slotHeaderRow:SetPoint("RIGHT", slotScrollChild, "RIGHT", 0, 0)
    slotHeaderRow:SetHeight(18)

    local slotHdr1 = slotHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(slotHdr1, "small")
    slotHdr1:SetPoint("LEFT", slotHeaderRow, "LEFT", 0, 0)
    slotHdr1:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    slotHdr1:SetText("Slot")

    local slotHdr2 = slotHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(slotHdr2, "small")
    slotHdr2:SetPoint("LEFT", slotHeaderRow, "LEFT", 180, 0)
    slotHdr2:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    slotHdr2:SetText("Enhancement")

    local slotHdr3 = slotHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(slotHdr3, "small")
    slotHdr3:SetPoint("LEFT", slotHeaderRow, "LEFT", 420, 0)
    slotHdr3:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    slotHdr3:SetText("Selected")
    slotHdr3:Hide()

    local slotHeaderSep = slotScrollChild:CreateTexture(nil, "ARTWORK")
    slotHeaderSep:SetColorTexture(1, 1, 1, 0.10)
    slotHeaderSep:SetHeight(1)
    slotHeaderSep:SetPoint("TOPLEFT", slotHeaderRow, "BOTTOMLEFT", 0, -4)
    slotHeaderSep:SetPoint("RIGHT", slotScrollChild, "RIGHT", 0, 0)

    local slotRows = {}
    local function EnsureSlotRow(i)
        if slotRows[i] then return slotRows[i] end

        local row = CreateFrame("Frame", nil, slotScrollChild)
        row:SetHeight(22)

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
        else
            base:SetColorTexture(1, 1, 1, 0.05)
        end
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        if i == 1 then
            row:SetPoint("TOPLEFT", slotHeaderSep, "BOTTOMLEFT", 0, -8)
        else
            row:SetPoint("TOPLEFT", slotRows[i - 1], "BOTTOMLEFT", 0, -6)
        end
        row:SetPoint("RIGHT", slotScrollChild, "RIGHT", 0, 0)

        row.slotLabel = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.slotLabel, "normal")
        row.slotLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.slotLabel:SetWidth(170)
        row.slotLabel:SetJustifyH("LEFT")

        row.selectButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.selectButton:SetSize(220, 20)
        row.selectButton:SetText("Select")
        row.selectButton:SetPoint("LEFT", row, "LEFT", 170, 0)
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then
                S:HandleButton(row.selectButton)
            end
        end

        ApplySelectedItemTooltip(row.selectButton)

        row.selectedText = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.selectedText, "normal")
        row.selectedText:SetPoint("LEFT", row, "LEFT", 420, 0)
        row.selectedText:SetWidth(300)
        row.selectedText:SetJustifyH("LEFT")
        row.selectedText:Hide()

        row.btnClear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnClear:SetSize(44, 18)
        row.btnClear:SetText("Clear")
        row.btnClear:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then
                S:HandleButton(row.btnClear)
            end
        end

        row:Hide()
        slotRows[i] = row
        return row
    end

    local function ClearSlotRows()
        for i = 1, MAX_ROWS do
            if slotRows[i] then slotRows[i]:Hide() end
        end
    end

    local function SetSlotScrollHeight(lastWidget)
        local bottom = lastWidget or slotHeaderSep
        local h = 0
        if bottom and bottom.GetBottom and slotScrollChild.GetTop then
            local top = slotScrollChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        slotScrollChild:SetSize(520, h)
    end

    -- Shared selector frame for slot enhancements
    local enhSelectorTargetHeight = 300
    local enhSelector = CreateFrame("Frame", nil, enhPanel, "BackdropTemplate")
    enhSelector:SetWidth(420)
    enhSelector:SetHeight(1)
    enhSelector:SetFrameStrata("DIALOG")
    enhSelector:SetFrameLevel(frame:GetFrameLevel() + 500)
    enhSelector:SetClampedToScreen(true)
    enhSelector:EnableMouse(true)
    enhSelector:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    enhSelector:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    enhSelector:SetBackdropBorderColor(0, 0, 0, 1)
    enhSelector:Hide()

    local enhCloseCatcher = CreateFrame("Button", nil, _G.UIParent)
    enhCloseCatcher:SetAllPoints(_G.UIParent)
    enhCloseCatcher:SetFrameStrata("DIALOG")
    enhCloseCatcher:SetFrameLevel(frame:GetFrameLevel() + 499)
    enhCloseCatcher:EnableMouse(true)
    enhCloseCatcher:Hide()

    local enhCloseCatcherInFrame = CreateFrame("Button", nil, frame)
    enhCloseCatcherInFrame:SetAllPoints(frame)
    enhCloseCatcherInFrame:SetFrameStrata("DIALOG")
    enhCloseCatcherInFrame:SetFrameLevel(frame:GetFrameLevel() + 499)
    enhCloseCatcherInFrame:EnableMouse(true)
    enhCloseCatcherInFrame:Hide()

    local enhSearch = CreateFrame("EditBox", nil, enhSelector, "InputBoxTemplate")
    enhSearch:SetFrameLevel(enhSelector:GetFrameLevel() + 10)
    enhSearch:SetSize(260, 20)
    enhSearch:SetPoint("TOPLEFT", enhSelector, "TOPLEFT", 10, -10)
    enhSearch:SetAutoFocus(false)
    enhSearch:SetText("")
    enhSearch:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleEditBox then
            S:HandleEditBox(enhSearch)
        end
    end

    local enhHint = enhSelector:CreateFontString(nil, "OVERLAY")
    SetFont(enhHint, "small")
    enhHint:SetPoint("LEFT", enhSearch, "RIGHT", 10, 0)
    enhHint:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    enhHint:SetText("Search name or tooltip")

    local enhScroll = CreateFrame("ScrollFrame", nil, enhSelector, "UIPanelScrollFrameTemplate")
    enhScroll:SetFrameLevel(enhSelector:GetFrameLevel() + 10)
    enhScroll:SetPoint("TOPLEFT", enhSearch, "BOTTOMLEFT", -2, -10)
    enhScroll:SetPoint("BOTTOMRIGHT", enhSelector, "BOTTOMRIGHT", -28, 12)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleScrollBar and enhScroll.ScrollBar then
            S:HandleScrollBar(enhScroll.ScrollBar)
        end
    end

    local enhScrollChild = CreateFrame("Frame", nil, enhScroll)
    enhScrollChild:SetFrameLevel(enhSelector:GetFrameLevel() + 11)
    enhScrollChild:SetPoint("TOPLEFT")
    enhScrollChild:SetSize(1, 1)
    enhScroll:SetScrollChild(enhScrollChild)

    local enhRows = {}
    local enhSearchToken = 0
    local enhRefreshToken = 0
    local enhCandidates = {}
    local enhFiltered = {}
    local enhActiveSlotKey = nil

    local RenderSlotEnhancements = nil

    local EnhRender = nil
    local EnhScheduleRender = nil

    local enhSearchCache = {}
    local enhDescCache = {}
    local enhScanTip = nil
    local enhItemLoadHooked = {}

    local gearEnhancementsRefreshToken = 0
    local RenderAnalyzeSlotEnhancements = nil
    local function ScheduleGearEnhancementsRefresh()
        if not _G.C_Timer or type(_G.C_Timer.After) ~= "function" then
            if type(RenderSlotEnhancements) == "function" and gearEnhancementsPage and gearEnhancementsPage.IsShown and gearEnhancementsPage:IsShown() then
                RenderSlotEnhancements()
            elseif type(RenderAnalyzeSlotEnhancements) == "function" and analyzeEnhancementsPage and analyzeEnhancementsPage.IsShown and analyzeEnhancementsPage:IsShown() then
                RenderAnalyzeSlotEnhancements()
            end
            return
        end

        gearEnhancementsRefreshToken = gearEnhancementsRefreshToken + 1
        local myToken = gearEnhancementsRefreshToken
        _G.C_Timer.After(0.05, function()
            if myToken ~= gearEnhancementsRefreshToken then return end
            if type(RenderSlotEnhancements) == "function" and gearEnhancementsPage and gearEnhancementsPage.IsShown and gearEnhancementsPage:IsShown() then
                RenderSlotEnhancements()
                return
            end
            if type(RenderAnalyzeSlotEnhancements) == "function" and analyzeEnhancementsPage and analyzeEnhancementsPage.IsShown and analyzeEnhancementsPage:IsShown() then
                RenderAnalyzeSlotEnhancements()
                return
            end
        end)
    end

    local function EnsureEnhScanTooltip()
        if enhScanTip then return enhScanTip end
        enhScanTip = CreateFrame("GameTooltip", "TwichUIEnhSelectorScanTooltip", _G.UIParent, "GameTooltipTemplate")
        enhScanTip:SetOwner(_G.UIParent, "ANCHOR_NONE")
        enhScanTip:Hide()
        return enhScanTip
    end

    local function EnhBuildTooltipText(itemId)
        local id = tonumber(itemId)
        if not id or id <= 0 then return "", "" end

        local name = _G.GetItemInfo(id)
        name = (type(name) == "string" and name) or ""

        local lines = {}
        local desc = ""

        if _G.C_TooltipInfo and type(_G.C_TooltipInfo.GetItemByID) == "function" then
            local ok, info = pcall(_G.C_TooltipInfo.GetItemByID, id)
            if ok and type(info) == "table" and type(info.lines) == "table" then
                for i = 2, #info.lines do
                    local line = info.lines[i]
                    local t = (type(line) == "table" and line.leftText) or nil
                    if type(t) == "string" and t ~= "" then
                        table.insert(lines, t)
                        if desc == "" and t:find("%+") then
                            desc = t
                        end
                    end
                end
            end
        else
            local tip = EnsureEnhScanTooltip()
            tip:ClearLines()
            if type(tip.SetItemByID) == "function" then
                pcall(tip.SetItemByID, tip, id)
            else
                local link = select(2, _G.GetItemInfo(id))
                if link and type(tip.SetHyperlink) == "function" then
                    tip:SetHyperlink(link)
                end
            end

            local n = tip:NumLines() or 0
            for i = 2, n do
                local fs = _G["TwichUIEnhSelectorScanTooltipTextLeft" .. tostring(i)]
                local t = fs and fs.GetText and fs:GetText() or nil
                if type(t) == "string" and t ~= "" then
                    table.insert(lines, t)
                    if desc == "" and t:find("%+") then
                        desc = t
                    end
                end
            end
        end

        local blob = name
        if #lines > 0 then
            blob = blob .. "\n" .. table.concat(lines, "\n")
        end
        return blob, desc
    end

    local function EnhGetSearchBlobLower(itemId)
        local id = tonumber(itemId)
        if not id or id <= 0 then return "" end
        if type(enhSearchCache[id]) == "string" then
            return enhSearchCache[id]
        end
        local blob, desc = EnhBuildTooltipText(id)
        blob = (type(blob) == "string" and blob) or ""
        desc = (type(desc) == "string" and desc) or ""
        enhSearchCache[id] = blob:lower()
        enhDescCache[id] = desc
        return enhSearchCache[id]
    end

    local function EnhGetDescription(itemId)
        local id = tonumber(itemId)
        if not id or id <= 0 then return "" end
        if type(enhDescCache[id]) == "string" then
            return enhDescCache[id]
        end
        EnhGetSearchBlobLower(id)
        return (type(enhDescCache[id]) == "string" and enhDescCache[id]) or ""
    end

    EnsureEnhItemLoadHook = function(itemId)
        local id = tonumber(itemId)
        if not id or id <= 0 then return end
        if enhItemLoadHooked[id] then return end
        enhItemLoadHooked[id] = true

        if _G.Item and type(_G.Item.CreateFromItemID) == "function" then
            local ok, item = pcall(_G.Item.CreateFromItemID, _G.Item, id)
            if ok and item and type(item.ContinueOnItemLoad) == "function" then
                pcall(item.ContinueOnItemLoad, item, function()
                    ScheduleGearEnhancementsRefresh()
                    if enhSelector and enhSelector.__twichuiOpen and type(EnhScheduleRender) == "function" then
                        EnhScheduleRender(enhSelector.__twichuiRenderOwner)
                    end
                end)
            end
        end
    end

    local function EnsureEnhRow(i)
        if enhRows[i] then return enhRows[i] end

        local row = CreateFrame("Button", nil, enhScrollChild)
        row:SetFrameLevel(enhSelector:GetFrameLevel() + 12)
        row:SetHeight(34)
        row:SetPoint("LEFT", enhScrollChild, "LEFT", 0, 0)
        row:SetPoint("RIGHT", enhScrollChild, "RIGHT", 0, 0)
        row:EnableMouse(true)

        if i == 1 then
            row:SetPoint("TOPLEFT", enhScrollChild, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", enhRows[i - 1], "BOTTOMLEFT", 0, -4)
        end

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
        else
            base:SetColorTexture(1, 1, 1, 0.05)
        end
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
        else
            hover:SetColorTexture(1, 1, 1, 0.10)
        end
        hover:Hide()
        row.__twichuiHoverBG = hover

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.name = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.name, "normal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.name:SetJustifyH("LEFT")

        row.desc = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.desc, "small")
        row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.desc:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

        row:SetScript("OnEnter", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Show() end
            local id = tonumber(self.__twichuiItemID)
            if not id or id <= 0 or not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(_G.GameTooltip.SetItemByID) == "function" then
                pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
            else
                local link = select(2, _G.GetItemInfo(id))
                if link and type(_G.GameTooltip.SetHyperlink) == "function" then
                    _G.GameTooltip:SetHyperlink(link)
                end
            end
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Hide() end
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)

        row:Hide()
        enhRows[i] = row
        return row
    end

    local function ClearEnhRows()
        for i = 1, #enhRows do
            enhRows[i]:Hide()
        end
    end

    local function SetEnhScrollHeight(lastWidget)
        local bottom = lastWidget
        local h = 0
        if bottom and bottom.GetBottom and enhScrollChild.GetTop then
            local top = enhScrollChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        enhScrollChild:SetSize(390, h)
    end

    local function EnhAnimate(open)
        enhSelector.__twichuiOpen = open and true or false
        if open then
            enhCloseCatcher:Show()
            enhCloseCatcherInFrame:Show()
            enhSelector:Show()
            enhSelector:SetAlpha(0)
            enhSelector:SetHeight(1)
            enhSelector.__twichuiAnim = { from = 1, to = enhSelectorTargetHeight, t = 0, dur = 0.16 }
        else
            enhCloseCatcher:Hide()
            enhCloseCatcherInFrame:Hide()
            enhSelector.__twichuiAnim = { from = enhSelector:GetHeight() or enhSelectorTargetHeight, to = 0, t = 0, dur = 0.12, closing = true }
        end

        enhSelector:SetScript("OnUpdate", function(f, elapsed)
            local a = f.__twichuiAnim
            if not a then
                f:SetScript("OnUpdate", nil)
                return
            end
            a.t = a.t + (elapsed or 0)
            local p = a.dur > 0 and math.min(1, a.t / a.dur) or 1
            local h = (a.from or 0) + ((a.to or 0) - (a.from or 0)) * p
            if h < 1 then h = 1 end
            f:SetHeight(h)
            f:SetAlpha(math.max(0, math.min(1, h / enhSelectorTargetHeight)))
            if p >= 1 then
                f:SetScript("OnUpdate", nil)
                if a.closing then
                    f:SetHeight(1)
                    f:SetAlpha(0)
                    f:Hide()
                else
                    f:SetHeight(enhSelectorTargetHeight)
                    f:SetAlpha(1)
                end
            end
        end)
    end

    local function EnhClose()
        if enhSelector and enhSelector.__twichuiOpen then
            EnhAnimate(false)
        end
        if enhSearch then
            enhSearch:ClearFocus()
        end
    end
    enhSelector.__twichuiClose = EnhClose

    enhCloseCatcher:SetScript("OnMouseDown", function() EnhClose() end)
    enhCloseCatcherInFrame:SetScript("OnMouseDown", function() EnhClose() end)

    enhSearch:SetScript("OnEscapePressed", function()
        if enhSelector and enhSelector.__twichuiOpen then
            EnhClose()
        else
            enhSearch:ClearFocus()
        end
    end)

    local function EnhRebuildFiltered()
        local q = enhSearch:GetText() or ""
        q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")
        wipe(enhFiltered)

        if #enhCandidates == 0 then
            return
        end

        if q == "" then
            for _, id in ipairs(enhCandidates) do
                table.insert(enhFiltered, id)
            end
            return
        end

        for _, id in ipairs(enhCandidates) do
            if tonumber(id) == 0 then
                if ("none"):find(q, 1, true) then
                    table.insert(enhFiltered, id)
                end
            else
                local name = _G.GetItemInfo(id)
                local nameLower = (type(name) == "string" and name:lower()) or ""
                if nameLower ~= "" and nameLower:find(q, 1, true) then
                    table.insert(enhFiltered, id)
                else
                    local blob = EnhGetSearchBlobLower(id)
                    if blob ~= "" and blob:find(q, 1, true) then
                        table.insert(enhFiltered, id)
                    end
                end
            end
        end
    end

    EnhRender = function(RenderSlotEnhancementsFn)
        ClearEnhRows()
        EnhRebuildFiltered()
        local list = enhFiltered

        if #list == 0 then
            local row = EnsureEnhRow(1)
            row.__twichuiItemID = nil
            row.icon:SetTexture(nil)
            row.name:SetText(ColorWrap("No matches", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.desc:SetText("")
            row:SetScript("OnClick", nil)
            row:Show()
            SetEnhScrollHeight(row)
            return
        end

        local last = nil
        local needsRefresh = false
        local maxShow = math.min(#list, 80)
        for i = 1, maxShow do
            local id = list[i]
            local row = EnsureEnhRow(i)

            if tonumber(id) == 0 then
                row.__twichuiItemID = 0
                row.icon:SetTexture(nil)
                row.name:SetText(ColorWrap("None", COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
                row.desc:SetText("")
                row:SetScript("OnClick", function()
                    local db = GetGearEnhancementsDB()
                    if db and db.selectedBySlot and enhActiveSlotKey then
                        db.selectedBySlot[enhActiveSlotKey] = nil
                    end
                    EnhClose()
                    if type(RenderSlotEnhancementsFn) == "function" then
                        RenderSlotEnhancementsFn()
                    end
                end)
            else
                row.__twichuiItemID = id

                local name, _, _, _, _, _, _, _, _, icon = _G.GetItemInfo(id)
                if icon then
                    row.icon:SetTexture(icon)
                else
                    row.icon:SetTexture(nil)
                end

                if not name then
                    needsRefresh = true
                    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                        pcall(_G.C_Item.RequestLoadItemDataByID, id)
                    end
                    EnsureEnhItemLoadHook(id)
                    row.name:SetText(ColorWrap("Loading... (" .. tostring(id) .. ")", COLOR_MUTED[1], COLOR_MUTED[2],
                        COLOR_MUTED[3]))
                else
                    row.name:SetText(ColorWrap(GetItemDisplayFromId(id), COLOR_PRIMARY[1], COLOR_PRIMARY[2],
                        COLOR_PRIMARY[3]))
                end

                local desc = EnhGetDescription(id)
                if desc and desc ~= "" then
                    row.desc:SetText(desc)
                else
                    row.desc:SetText("")
                end

                row:SetScript("OnClick", function()
                    local db = GetGearEnhancementsDB()
                    if db and db.selectedBySlot and enhActiveSlotKey then
                        db.selectedBySlot[enhActiveSlotKey] = tonumber(id)
                    end
                    EnhClose()
                    if type(RenderSlotEnhancementsFn) == "function" then
                        RenderSlotEnhancementsFn()
                    end
                end)
            end

            row:Show()
            last = row
        end

        SetEnhScrollHeight(last or enhRows[1])

        if needsRefresh and enhSelector and enhSelector.__twichuiOpen and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            enhRefreshToken = enhRefreshToken + 1
            local myToken = enhRefreshToken
            _G.C_Timer.After(0.25, function()
                if enhSelector and enhSelector.__twichuiOpen and enhRefreshToken == myToken then
                    EnhRender(RenderSlotEnhancementsFn)
                end
            end)
        end
    end

    EnhScheduleRender = function(RenderSlotEnhancementsFn)
        if not enhSelector or not enhSelector.__twichuiOpen then
            return
        end
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            enhSearchToken = enhSearchToken + 1
            local myToken = enhSearchToken
            _G.C_Timer.After(0.08, function()
                if enhSelector and enhSelector.__twichuiOpen and enhSearchToken == myToken then
                    EnhRender(RenderSlotEnhancementsFn)
                end
            end)
        else
            EnhRender(RenderSlotEnhancementsFn)
        end
    end

    enhSearch:SetScript("OnTextChanged", function()
        EnhScheduleRender(enhSelector.__twichuiRenderOwner)
    end)

    RenderSlotEnhancements = function()
        ClearSlotRows()

        local data = DataModule and DataModule.Handbook and DataModule.Handbook.GearEnhancements or nil
        local slots = data and data.Slots or nil
        if type(slots) ~= "table" then
            local row = EnsureSlotRow(1)
            row.slotLabel:SetText(ColorWrap("No entries", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            if row.selectButton and row.selectButton.SetText then
                row.selectButton:SetText("Edit Modules/Data/Handbook.lua")
                row.selectButton:Disable()
                row.selectButton:Show()
            end
            row.btnClear:Hide()
            row:Show()
            SetSlotScrollHeight(row)
            return
        end

        local order = (type(data.SlotOrder) == "table" and data.SlotOrder) or nil
        local slotKeys = {}
        if order then
            for _, k in ipairs(order) do
                if slots[k] then table.insert(slotKeys, k) end
            end
            for k in pairs(slots) do
                local found = false
                for _, ok in ipairs(slotKeys) do
                    if ok == k then
                        found = true
                        break
                    end
                end
                if not found then table.insert(slotKeys, k) end
            end
        else
            for k in pairs(slots) do table.insert(slotKeys, k) end
            table.sort(slotKeys)
        end

        local db = GetGearEnhancementsDB()
        local selectedBySlot = db.selectedBySlot

        local last = slotHeaderSep
        for i, slotKey in ipairs(slotKeys) do
            if i > MAX_ROWS then break end
            local slot = slots[slotKey]
            local row = EnsureSlotRow(i)

            row.slotKey = slotKey
            row.slotLabel:SetText(ColorWrap(tostring(slot.label or slotKey), COLOR_PRIMARY[1], COLOR_PRIMARY[2],
                COLOR_PRIMARY[3]))

            local selectedItemId = selectedBySlot[slotKey]

            row.btnClear:Show()
            row.btnClear:SetScript("OnClick", function()
                selectedBySlot[slotKey] = nil
                if row.selectButton and row.selectButton.SetText then
                    row.selectButton:SetText("Select")
                end
                if row.selectButton then
                    row.selectButton.__twichuiItemID = nil
                end
                RenderSlotEnhancements()
            end)

            if row.selectButton and row.selectButton.SetText then
                if selectedItemId then
                    row.selectButton:SetText(GetItemDisplayFromId(selectedItemId))
                    EnsureEnhItemLoadHook(selectedItemId)
                else
                    row.selectButton:SetText("Select")
                end
            end

            if row.selectButton then
                row.selectButton.__twichuiItemID = selectedItemId
            end

            row.selectButton:Show()
            row.selectButton:Enable()
            row.selectButton:SetScript("OnClick", function(btn)
                enhActiveSlotKey = slotKey

                wipe(enhCandidates)
                table.insert(enhCandidates, 0) -- None

                local items = slot and slot.items or nil
                if type(items) == "table" then
                    for _, entry in ipairs(items) do
                        local itemId = tonumber(entry.itemId)
                        if itemId and itemId > 0 then
                            if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                                pcall(_G.C_Item.RequestLoadItemDataByID, itemId)
                            end
                            table.insert(enhCandidates, itemId)
                        end
                    end
                end

                if #enhCandidates > 2 then
                    table.sort(enhCandidates, function(a, b)
                        if a == 0 then return true end
                        if b == 0 then return false end
                        local an, _, aq = _G.GetItemInfo(a)
                        local bn, _, bq = _G.GetItemInfo(b)
                        aq = tonumber(aq) or -1
                        bq = tonumber(bq) or -1
                        if aq ~= bq then
                            return aq > bq
                        end
                        local al = (type(an) == "string" and an:lower()) or ""
                        local bl = (type(bn) == "string" and bn:lower()) or ""
                        if al ~= bl then
                            return al < bl
                        end
                        return (tonumber(a) or 0) < (tonumber(b) or 0)
                    end)
                end

                enhSearch:SetText(enhSearch:GetText() or "")

                enhSelector:ClearAllPoints()
                enhSelector:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)

                enhSelector.__twichuiRenderOwner = RenderSlotEnhancements
                EnhRender(RenderSlotEnhancements)
                EnhAnimate(true)
                enhSearch:SetFocus()
                enhSearch:HighlightText()
            end)

            row:Show()
            last = row
        end

        SetSlotScrollHeight(last)
    end

    -- Gem Priority (profile-backed)
    local gemPanel = CreateFrame("Frame", nil, gemPriorityPage, "BackdropTemplate")
    gemPanel:SetPoint("TOPLEFT", gemPriorityPage, "TOPLEFT", 0, 0)
    gemPanel:SetPoint("BOTTOMRIGHT", gemPriorityPage, "BOTTOMRIGHT", 0, 0)
    gemPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    gemPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    gemPanel:SetBackdropBorderColor(0, 0, 0, 1)

    local gemHeader = gemPanel:CreateFontString(nil, "OVERLAY")
    SetFont(gemHeader, "normal")
    gemHeader:SetPoint("TOPLEFT", gemPanel, "TOPLEFT", 12, -12)
    gemHeader:SetText("Gem Priority")
    gemHeader:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local selectedGemId = nil

    local function IsGemInList(list, itemId)
        if type(list) ~= "table" then return false end
        local id = tonumber(itemId)
        if not id then return false end
        for _, v in ipairs(list) do
            if tonumber(v.itemId) == id then return true end
        end
        return false
    end

    local function GetConfiguredGemIds()
        local data = DataModule and DataModule.Handbook and DataModule.Handbook.GearEnhancements or nil
        local gems = data and data.Gems or nil
        if type(gems) ~= "table" then
            return {}
        end

        local ids = {}
        for _, entry in ipairs(gems) do
            local itemId = tonumber((type(entry) == "table") and entry.itemId or entry)
            if itemId and itemId > 0 then
                table.insert(ids, itemId)
            end
        end
        return ids
    end

    local function GetGemCandidates(excludeList)
        local candidates = {}
        local configured = GetConfiguredGemIds()
        for _, itemId in ipairs(configured) do
            if not IsGemInList(excludeList, itemId) then
                if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    pcall(_G.C_Item.RequestLoadItemDataByID, itemId)
                end
                table.insert(candidates, itemId)
            end
        end

        table.sort(candidates, function(a, b)
            local an, _, aq = _G.GetItemInfo(a)
            local bn, _, bq = _G.GetItemInfo(b)
            aq = tonumber(aq) or -1
            bq = tonumber(bq) or -1
            if aq ~= bq then
                return aq > bq
            end
            local al = (type(an) == "string" and an:lower()) or ""
            local bl = (type(bn) == "string" and bn:lower()) or ""
            if al ~= bl then
                return al < bl
            end
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)

        return candidates
    end

    -- Custom gem selector (animated open, scroll list, search by name + tooltip text)
    local gemSelectButton = CreateFrame("Button", nil, gemPanel, "UIPanelButtonTemplate")
    gemSelectButton:SetSize(240, 22)
    gemSelectButton:SetText("Select Gem")
    gemSelectButton:SetPoint("TOPLEFT", gemHeader, "BOTTOMLEFT", 0, -6)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(gemSelectButton)
        end
    end

    ApplySelectedItemTooltip(gemSelectButton)

    local gemAddButton = CreateFrame("Button", nil, gemPanel, "UIPanelButtonTemplate")
    gemAddButton:SetSize(60, 22)
    gemAddButton:SetText("Add")
    gemAddButton:SetPoint("LEFT", gemSelectButton, "RIGHT", 8, 0)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(gemAddButton)
        end
    end

    local selectorTargetHeight = 300
    local gemSelector = CreateFrame("Frame", nil, gemPanel, "BackdropTemplate")
    gemSelector:SetPoint("TOPLEFT", gemSelectButton, "BOTTOMLEFT", 0, -6)
    gemSelector:SetWidth(420)
    gemSelector:SetHeight(1)
    gemSelector:SetFrameStrata("DIALOG")
    gemSelector:SetFrameLevel(frame:GetFrameLevel() + 500)
    gemSelector:SetClampedToScreen(true)
    gemSelector:EnableMouse(true)
    gemSelector:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    gemSelector:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    gemSelector:SetBackdropBorderColor(0, 0, 0, 1)
    gemSelector:Hide()

    local selectorCloseCatcher = CreateFrame("Button", nil, _G.UIParent)
    selectorCloseCatcher:SetAllPoints(_G.UIParent)
    selectorCloseCatcher:SetFrameStrata("DIALOG")
    selectorCloseCatcher:SetFrameLevel(frame:GetFrameLevel() + 499)
    selectorCloseCatcher:EnableMouse(true)
    selectorCloseCatcher:Hide()

    local selectorCloseCatcherInFrame = CreateFrame("Button", nil, frame)
    selectorCloseCatcherInFrame:SetAllPoints(frame)
    selectorCloseCatcherInFrame:SetFrameStrata("DIALOG")
    selectorCloseCatcherInFrame:SetFrameLevel(frame:GetFrameLevel() + 499)
    selectorCloseCatcherInFrame:EnableMouse(true)
    selectorCloseCatcherInFrame:Hide()

    local selectorSearch = CreateFrame("EditBox", nil, gemSelector, "InputBoxTemplate")
    selectorSearch:SetFrameLevel(gemSelector:GetFrameLevel() + 10)
    selectorSearch:SetSize(260, 20)
    selectorSearch:SetPoint("TOPLEFT", gemSelector, "TOPLEFT", 10, -10)
    selectorSearch:SetAutoFocus(false)
    selectorSearch:SetText("")
    selectorSearch:SetScript("OnEscapePressed", function(self)
        if gemSelector and gemSelector.__twichuiOpen then
            if gemSelector.__twichuiClose then
                gemSelector.__twichuiClose()
            end
            return
        end
        self:ClearFocus()
    end)
    selectorSearch:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleEditBox then
            S:HandleEditBox(selectorSearch)
        end
    end

    local selectorHint = gemSelector:CreateFontString(nil, "OVERLAY")
    SetFont(selectorHint, "small")
    selectorHint:SetPoint("LEFT", selectorSearch, "RIGHT", 10, 0)
    selectorHint:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    selectorHint:SetText("Search name or tooltip")

    local selectorScroll = CreateFrame("ScrollFrame", nil, gemSelector, "UIPanelScrollFrameTemplate")
    selectorScroll:SetFrameLevel(gemSelector:GetFrameLevel() + 10)
    selectorScroll:SetPoint("TOPLEFT", selectorSearch, "BOTTOMLEFT", -2, -10)
    selectorScroll:SetPoint("BOTTOMRIGHT", gemSelector, "BOTTOMRIGHT", -28, 12)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleScrollBar and selectorScroll.ScrollBar then
            S:HandleScrollBar(selectorScroll.ScrollBar)
        end
    end

    local selectorChild = CreateFrame("Frame", nil, selectorScroll)
    selectorChild:SetFrameLevel(gemSelector:GetFrameLevel() + 11)
    selectorChild:SetPoint("TOPLEFT")
    selectorChild:SetSize(1, 1)
    selectorScroll:SetScrollChild(selectorChild)

    local selectorRows = {}
    local selectorCandidates = {}
    local selectorFiltered = {}

    local selectorSearchToken = 0
    local selectorRefreshToken = 0

    local gemSearchCache = {}
    local gemDescCache = {}
    local scanTip = nil

    local function EnsureScanTooltip()
        if scanTip then return scanTip end
        scanTip = CreateFrame("GameTooltip", "TwichUIGemSelectorScanTooltip", _G.UIParent, "GameTooltipTemplate")
        scanTip:SetOwner(_G.UIParent, "ANCHOR_NONE")
        scanTip:Hide()
        return scanTip
    end

    local function BuildTooltipText(itemId)
        local id = tonumber(itemId)
        if not id then return "", "" end

        local name = _G.GetItemInfo(id)
        name = (type(name) == "string" and name) or ""

        local lines = {}
        local desc = ""

        if _G.C_TooltipInfo and type(_G.C_TooltipInfo.GetItemByID) == "function" then
            local ok, info = pcall(_G.C_TooltipInfo.GetItemByID, id)
            if ok and type(info) == "table" and type(info.lines) == "table" then
                for i = 2, #info.lines do
                    local line = info.lines[i]
                    local t = (type(line) == "table" and line.leftText) or nil
                    if type(t) == "string" and t ~= "" then
                        table.insert(lines, t)
                        if desc == "" and t:find("%+") then
                            desc = t
                        end
                    end
                end
            end
        else
            local tip = EnsureScanTooltip()
            tip:ClearLines()
            if type(tip.SetItemByID) == "function" then
                pcall(tip.SetItemByID, tip, id)
            else
                local link = select(2, _G.GetItemInfo(id))
                if link and type(tip.SetHyperlink) == "function" then
                    tip:SetHyperlink(link)
                end
            end

            local n = tip:NumLines() or 0
            for i = 2, n do
                local fs = _G["TwichUIGemSelectorScanTooltipTextLeft" .. tostring(i)]
                local t = fs and fs.GetText and fs:GetText() or nil
                if type(t) == "string" and t ~= "" then
                    table.insert(lines, t)
                    if desc == "" and t:find("%+") then
                        desc = t
                    end
                end
            end
        end

        local blob = name
        if #lines > 0 then
            blob = blob .. "\n" .. table.concat(lines, "\n")
        end
        return blob, desc
    end

    local function GetSearchBlobLower(itemId)
        local id = tonumber(itemId)
        if not id then return "" end
        if type(gemSearchCache[id]) == "string" then
            return gemSearchCache[id]
        end
        local blob, desc = BuildTooltipText(id)
        blob = (type(blob) == "string" and blob) or ""
        desc = (type(desc) == "string" and desc) or ""
        gemSearchCache[id] = blob:lower()
        gemDescCache[id] = desc
        return gemSearchCache[id]
    end

    local function GetDescription(itemId)
        local id = tonumber(itemId)
        if not id then return "" end
        if type(gemDescCache[id]) == "string" then
            return gemDescCache[id]
        end
        GetSearchBlobLower(id)
        return (type(gemDescCache[id]) == "string" and gemDescCache[id]) or ""
    end

    local function EnsureSelectorRow(i)
        if selectorRows[i] then return selectorRows[i] end

        local row = CreateFrame("Button", nil, selectorChild)
        row:SetFrameLevel(gemSelector:GetFrameLevel() + 12)
        row:SetHeight(34)
        row:SetPoint("LEFT", selectorChild, "LEFT", 0, 0)
        row:SetPoint("RIGHT", selectorChild, "RIGHT", 0, 0)
        row:EnableMouse(true)

        if i == 1 then
            row:SetPoint("TOPLEFT", selectorChild, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", selectorRows[i - 1], "BOTTOMLEFT", 0, -4)
        end

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
        else
            base:SetColorTexture(1, 1, 1, 0.05)
        end
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
        else
            hover:SetColorTexture(1, 1, 1, 0.10)
        end
        hover:Hide()
        row.__twichuiHoverBG = hover

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.name = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.name, "normal")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
        row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.name:SetJustifyH("LEFT")

        row.desc = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.desc, "small")
        row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.desc:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.desc:SetJustifyH("LEFT")
        row.desc:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])

        row:SetScript("OnEnter", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Show() end
            local id = self.__twichuiItemID
            if not id or not _G.GameTooltip then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(_G.GameTooltip.SetItemByID) == "function" then
                pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
            else
                local link = select(2, _G.GetItemInfo(id))
                if link and type(_G.GameTooltip.SetHyperlink) == "function" then
                    _G.GameTooltip:SetHyperlink(link)
                end
            end
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Hide() end
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)

        row:SetScript("OnClick", function(self)
            local id = self.__twichuiItemID
            if not id then return end
            selectedGemId = id
            gemSelectButton:SetText(GetItemDisplayFromId(id))
            gemSelectButton.__twichuiItemID = id
            if gemSelector and gemSelector.__twichuiClose then
                gemSelector.__twichuiClose()
            end
        end)

        row:Hide()
        selectorRows[i] = row
        return row
    end

    local function ClearSelectorRows()
        for i = 1, #selectorRows do
            selectorRows[i]:Hide()
        end
    end

    local function SetSelectorScrollHeight(lastWidget)
        local bottom = lastWidget
        local h = 0
        if bottom and bottom.GetBottom and selectorChild.GetTop then
            local top = selectorChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        selectorChild:SetSize(390, h)
    end

    local function RebuildSelectorFiltered()
        local q = selectorSearch:GetText() or ""
        q = q:lower():gsub("^%s+", ""):gsub("%s+$", "")

        wipe(selectorFiltered)

        if #selectorCandidates == 0 then
            return
        end

        if q == "" then
            for _, id in ipairs(selectorCandidates) do
                table.insert(selectorFiltered, id)
            end
            return
        end

        for _, id in ipairs(selectorCandidates) do
            local name = _G.GetItemInfo(id)
            local nameLower = (type(name) == "string" and name:lower()) or ""
            if nameLower ~= "" and nameLower:find(q, 1, true) then
                table.insert(selectorFiltered, id)
            else
                local blob = GetSearchBlobLower(id)
                if blob ~= "" and blob:find(q, 1, true) then
                    table.insert(selectorFiltered, id)
                end
            end
        end
    end

    local function RenderSelector()
        ClearSelectorRows()

        RebuildSelectorFiltered()
        local list = selectorFiltered

        if #list == 0 then
            local row = EnsureSelectorRow(1)
            row.__twichuiItemID = nil
            row.icon:SetTexture(nil)
            row.name:SetText(ColorWrap("No matches", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.desc:SetText(ColorWrap("", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row:Show()
            SetSelectorScrollHeight(row)
            return
        end

        local last = nil
        local needsRefresh = false
        local maxShow = math.min(#list, 80)
        for i = 1, maxShow do
            local id = list[i]
            local row = EnsureSelectorRow(i)
            row.__twichuiItemID = id

            local name, _, _, _, _, _, _, _, _, icon = _G.GetItemInfo(id)
            if icon then
                row.icon:SetTexture(icon)
            else
                row.icon:SetTexture(nil)
            end

            if not name then
                needsRefresh = true
                if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    pcall(_G.C_Item.RequestLoadItemDataByID, id)
                end
                row.name:SetText(ColorWrap("Loading... (" .. tostring(id) .. ")", COLOR_MUTED[1], COLOR_MUTED[2],
                    COLOR_MUTED[3]))
            else
                row.name:SetText(ColorWrap(GetItemDisplayFromId(id), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY
                    [3]))
            end

            local desc = GetDescription(id)
            if desc and desc ~= "" then
                row.desc:SetText(desc)
            else
                row.desc:SetText("")
            end

            row:Show()
            last = row
        end

        SetSelectorScrollHeight(last or selectorRows[1])

        if needsRefresh and gemSelector and gemSelector.__twichuiOpen and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            selectorRefreshToken = selectorRefreshToken + 1
            local myToken = selectorRefreshToken
            _G.C_Timer.After(0.25, function()
                if gemSelector and gemSelector.__twichuiOpen and selectorRefreshToken == myToken then
                    RenderSelector()
                end
            end)
        end
    end

    local function SelectorAnimate(open)
        gemSelector.__twichuiOpen = open and true or false
        if open then
            selectorCloseCatcher:Show()
            selectorCloseCatcherInFrame:Show()
            gemSelector:Show()
            gemSelector:SetAlpha(0)
            gemSelector:SetHeight(1)
            gemSelector.__twichuiAnim = { from = 1, to = selectorTargetHeight, t = 0, dur = 0.16 }
        else
            selectorCloseCatcher:Hide()
            selectorCloseCatcherInFrame:Hide()
            gemSelector.__twichuiAnim = { from = gemSelector:GetHeight() or selectorTargetHeight, to = 0, t = 0, dur = 0.12, closing = true }
        end

        gemSelector:SetScript("OnUpdate", function(f, elapsed)
            local a = f.__twichuiAnim
            if not a then
                f:SetScript("OnUpdate", nil)
                return
            end
            a.t = a.t + (elapsed or 0)
            local p = a.dur > 0 and math.min(1, a.t / a.dur) or 1
            local h = (a.from or 0) + ((a.to or 0) - (a.from or 0)) * p
            if h < 1 then h = 1 end
            f:SetHeight(h)
            f:SetAlpha(math.max(0, math.min(1, h / selectorTargetHeight)))
            if p >= 1 then
                f:SetScript("OnUpdate", nil)
                if a.closing then
                    f:SetHeight(1)
                    f:SetAlpha(0)
                    f:Hide()
                else
                    f:SetHeight(selectorTargetHeight)
                    f:SetAlpha(1)
                end
            end
        end)
    end

    local function CloseSelector()
        if gemSelector and gemSelector.__twichuiOpen then
            SelectorAnimate(false)
        end
        if selectorSearch then
            selectorSearch:ClearFocus()
        end
    end
    gemSelector.__twichuiClose = CloseSelector

    selectorCloseCatcher:SetScript("OnMouseDown", function()
        CloseSelector()
    end)

    selectorCloseCatcherInFrame:SetScript("OnMouseDown", function()
        CloseSelector()
    end)

    local function ScheduleSelectorRender()
        if not gemSelector or not gemSelector.__twichuiOpen then
            return
        end
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            selectorSearchToken = selectorSearchToken + 1
            local myToken = selectorSearchToken
            _G.C_Timer.After(0.08, function()
                if gemSelector and gemSelector.__twichuiOpen and selectorSearchToken == myToken then
                    RenderSelector()
                end
            end)
        else
            RenderSelector()
        end
    end

    selectorSearch:SetScript("OnTextChanged", function()
        ScheduleSelectorRender()
    end)

    gemSelectButton:SetScript("OnClick", function()
        local db = GetGearEnhancementsDB()
        local list = (db and db.gemPriority and db.gemPriority.list) or {}
        selectorCandidates = GetGemCandidates(list)
        selectorSearch:SetText(selectorSearch:GetText() or "")
        RenderSelector()
        SelectorAnimate(not gemSelector.__twichuiOpen)
        if gemSelector.__twichuiOpen then
            selectorSearch:SetFocus()
            selectorSearch:HighlightText()
        end
    end)

    local gemScroll = CreateFrame("ScrollFrame", nil, gemPanel, "UIPanelScrollFrameTemplate")
    gemScroll:SetPoint("TOPLEFT", gemSelectButton, "BOTTOMLEFT", 10, -12)
    gemScroll:SetPoint("BOTTOMRIGHT", gemPanel, "BOTTOMRIGHT", -28, 12)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleScrollBar and gemScroll.ScrollBar then
            S:HandleScrollBar(gemScroll.ScrollBar)
        end
    end

    local gemScrollChild = CreateFrame("Frame", nil, gemScroll)
    gemScrollChild:SetPoint("TOPLEFT")
    gemScrollChild:SetSize(1, 1)
    gemScroll:SetScrollChild(gemScrollChild)

    local gemHeaderRow = CreateFrame("Frame", nil, gemScrollChild)
    gemHeaderRow:SetPoint("TOPLEFT", gemScrollChild, "TOPLEFT", 0, 0)
    gemHeaderRow:SetPoint("RIGHT", gemScrollChild, "RIGHT", 0, 0)
    gemHeaderRow:SetHeight(18)

    local gemHdr1 = gemHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(gemHdr1, "small")
    gemHdr1:SetPoint("LEFT", gemHeaderRow, "LEFT", 0, 0)
    gemHdr1:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    gemHdr1:SetText("Priority")

    local gemHdr2 = gemHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(gemHdr2, "small")
    gemHdr2:SetPoint("LEFT", gemHeaderRow, "LEFT", 90, 0)
    gemHdr2:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    gemHdr2:SetText("Gem")

    local gemHdr3 = gemHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(gemHdr3, "small")
    gemHdr3:SetPoint("LEFT", gemHeaderRow, "LEFT", 330, 0)
    gemHdr3:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    gemHdr3:SetText("Max")

    local gemHdr4 = gemHeaderRow:CreateFontString(nil, "OVERLAY")
    SetFont(gemHdr4, "small")
    gemHdr4:SetPoint("RIGHT", gemHeaderRow, "RIGHT", -6, 0)
    gemHdr4:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    gemHdr4:SetText("Actions")

    local gemHeaderSep = gemScrollChild:CreateTexture(nil, "ARTWORK")
    gemHeaderSep:SetColorTexture(1, 1, 1, 0.10)
    gemHeaderSep:SetHeight(1)
    gemHeaderSep:SetPoint("TOPLEFT", gemHeaderRow, "BOTTOMLEFT", 0, -4)
    gemHeaderSep:SetPoint("RIGHT", gemScrollChild, "RIGHT", 0, 0)

    local gemRows = {}
    local function EnsureGemRow(i)
        if gemRows[i] then return gemRows[i] end

        local row = CreateFrame("Frame", nil, gemScrollChild)
        row:SetHeight(18)
        row:EnableMouse(true)

        local base = row:CreateTexture(nil, "BACKGROUND")
        base:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            base:SetColorTexture(r or 1, g or 1, b or 1, 0.05)
        else
            base:SetColorTexture(1, 1, 1, 0.05)
        end
        if (i % 2) == 0 then base:Show() else base:Hide() end
        row.__twichuiBaseBG = base

        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        if E and E.media and E.media.bordercolor then
            local r, g, b = unpack(E.media.bordercolor)
            hover:SetColorTexture(r or 1, g or 1, b or 1, 0.10)
        else
            hover:SetColorTexture(1, 1, 1, 0.10)
        end
        hover:Hide()
        row.__twichuiHoverBG = hover

        row:SetScript("OnEnter", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Show() end

            local itemId = self.__twichuiGemItemID
            if not itemId then return end
            if not _G.GameTooltip then return end

            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(_G.GameTooltip.SetItemByID) == "function" then
                pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, itemId)
            else
                local link = select(2, _G.GetItemInfo(itemId))
                if link and type(_G.GameTooltip.SetHyperlink) == "function" then
                    _G.GameTooltip:SetHyperlink(link)
                end
            end
            _G.GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            if self.__twichuiHoverBG then self.__twichuiHoverBG:Hide() end
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)

        if i == 1 then
            row:SetPoint("TOPLEFT", gemHeaderSep, "BOTTOMLEFT", 0, -8)
        else
            row:SetPoint("TOPLEFT", gemRows[i - 1], "BOTTOMLEFT", 0, -6)
        end
        row:SetPoint("RIGHT", gemScrollChild, "RIGHT", 0, 0)

        row.priority = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.priority, "normal")
        row.priority:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.priority:SetWidth(80)
        row.priority:SetJustifyH("LEFT")

        row.gem = row:CreateFontString(nil, "OVERLAY")
        SetFont(row.gem, "normal")
        row.gem:SetPoint("LEFT", row, "LEFT", 90, 0)
        row.gem:SetWidth(260)
        row.gem:SetJustifyH("LEFT")

        row.maxBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        row.maxBox:SetSize(52, 18)
        row.maxBox:SetPoint("LEFT", row, "LEFT", 330, 0)
        row.maxBox:SetAutoFocus(false)
        row.maxBox:SetNumeric(false)
        row.maxBox:SetMaxLetters(4)
        row.maxBox:SetJustifyH("CENTER")
        row.maxBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        row.maxBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleEditBox then
                S:HandleEditBox(row.maxBox)
            end
        end

        row.btnUp = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnUp:SetSize(18, 18)

        row.btnDown = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnDown:SetSize(18, 18)

        row.btnRemove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnRemove:SetSize(22, 18)
        row.btnRemove:SetText("X")
        row.btnRemove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.btnDown:SetPoint("RIGHT", row.btnRemove, "LEFT", -4, 0)
        row.btnUp:SetPoint("RIGHT", row.btnDown, "LEFT", -4, 0)

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then
                S:HandleButton(row.btnUp)
                S:HandleButton(row.btnDown)
                S:HandleButton(row.btnRemove)
            end
        end

        SkinArrowButton(row.btnUp, "up")
        SkinArrowButton(row.btnDown, "down")
        SkinXButton(row.btnRemove)

        row:Hide()
        gemRows[i] = row
        return row
    end

    local function ClearGemRows()
        for i = 1, MAX_ROWS do
            if gemRows[i] then gemRows[i]:Hide() end
        end
    end

    local function SetGemScrollHeight(lastWidget)
        local bottom = lastWidget or gemHeaderSep
        local h = 0
        if bottom and bottom.GetBottom and gemScrollChild.GetTop then
            local top = gemScrollChild:GetTop() or 0
            local bot = bottom:GetBottom() or 0
            h = (top - bot) + 20
        end
        if h < 1 then h = 1 end
        gemScrollChild:SetSize(520, h)
    end

    local function RenderGemPriority()
        ClearGemRows()

        local db = GetGearEnhancementsDB()
        local list = db and db.gemPriority and db.gemPriority.list or nil
        if type(list) ~= "table" or #list == 0 then
            local row = EnsureGemRow(1)
            row.priority:SetText(ColorWrap("", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.gem:SetText(ColorWrap("Use the selector above to add gems", COLOR_MUTED[1], COLOR_MUTED[2],
                COLOR_MUTED[3]))
            row.maxBox:Hide()
            row.btnUp:Hide()
            row.btnDown:Hide()
            row.btnRemove:Hide()
            row:Show()
            SetGemScrollHeight(row)
            return
        end

        local last = gemHeaderSep
        for i, entry in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = EnsureGemRow(i)

            row.__twichuiGemItemID = tonumber(entry.itemId)

            row.priority:SetText(ColorWrap(tostring(i), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.gem:SetText(ColorWrap(GetItemDisplayFromId(entry.itemId), COLOR_PRIMARY[1], COLOR_PRIMARY[2],
                COLOR_PRIMARY[3]))

            row.maxBox:Show()
            if entry.maxCount == nil then
                row.maxBox:SetText("")
            else
                row.maxBox:SetText(tostring(entry.maxCount))
            end

            row.maxBox:SetScript("OnTextChanged", function(self)
                local text = self:GetText()
                if text == nil or text == "" then
                    entry.maxCount = nil
                    return
                end
                local n = tonumber(text)
                if n and n > 0 then
                    entry.maxCount = math.floor(n)
                else
                    entry.maxCount = nil
                end
            end)

            row.btnUp:Show()
            row.btnDown:Show()
            row.btnRemove:Show()
            row.btnUp:SetEnabled(i > 1)
            row.btnDown:SetEnabled(i < #list)

            row.btnUp:SetScript("OnClick", function()
                if i <= 1 then return end
                list[i], list[i - 1] = list[i - 1], list[i]
                RenderGemPriority()
            end)
            row.btnDown:SetScript("OnClick", function()
                if i >= #list then return end
                list[i], list[i + 1] = list[i + 1], list[i]
                RenderGemPriority()
            end)
            row.btnRemove:SetScript("OnClick", function()
                table.remove(list, i)
                RenderGemPriority()
            end)

            row:Show()
            last = row
        end

        SetGemScrollHeight(last)
    end

    gemAddButton:SetScript("OnClick", function()
        local db = GetGearEnhancementsDB()
        local list = db.gemPriority.list
        if type(list) ~= "table" then
            db.gemPriority.list = {}
            list = db.gemPriority.list
        end

        local toAdd = tonumber(selectedGemId)
        if not toAdd then
            local candidates = GetGemCandidates(list)
            toAdd = candidates[1]
        end

        if not toAdd or IsGemInList(list, toAdd) then
            RenderGemPriority()
            return
        end

        table.insert(list, { itemId = toAdd, maxCount = nil })
        selectedGemId = nil
        gemSelectButton:SetText("Select Gem")
        gemSelectButton.__twichuiItemID = nil
        if gemSelector and gemSelector.__twichuiOpen then
            SelectorAnimate(false)
        end
        RenderGemPriority()
    end)

    -- Analyze Slot Enhancements
    local analyzePanel = CreateFrame("Frame", nil, analyzeEnhancementsPage, "BackdropTemplate")
    analyzePanel:SetPoint("TOPLEFT", analyzeEnhancementsPage, "TOPLEFT", 0, 0)
    analyzePanel:SetPoint("BOTTOMRIGHT", analyzeEnhancementsPage, "BOTTOMRIGHT", 0, 0)
    analyzePanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    analyzePanel:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    analyzePanel:SetBackdropBorderColor(0, 0, 0, 1)

    local analyzeHeader = analyzePanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeHeader, "normal")
    analyzeHeader:SetPoint("TOPLEFT", analyzePanel, "TOPLEFT", 12, -12)
    analyzeHeader:SetText("Analyze Slot Enhancements")
    analyzeHeader:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])

    local analyzeHint = analyzePanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeHint, "small")
    analyzeHint:SetPoint("TOPLEFT", analyzeHeader, "BOTTOMLEFT", 0, -8)
    analyzeHint:SetTextColor(COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3])
    analyzeHint:SetText("Drag a piece of gear here to get recommended enhancements.")

    local analyzeItemButton = CreateFrame("Button", nil, analyzePanel, "BackdropTemplate")
    analyzeItemButton:SetSize(44, 44)
    analyzeItemButton:SetPoint("TOPLEFT", analyzeHint, "BOTTOMLEFT", 0, -12)
    analyzeItemButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    analyzeItemButton:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    analyzeItemButton:SetBackdropBorderColor(0, 0, 0, 1)
    analyzeItemButton:EnableMouse(true)

    local analyzeItemIcon = analyzeItemButton:CreateTexture(nil, "ARTWORK")
    analyzeItemIcon:SetAllPoints(analyzeItemButton)
    analyzeItemIcon:SetTexture(nil)

    local analyzeItemText = analyzePanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeItemText, "normal")
    analyzeItemText:SetPoint("LEFT", analyzeItemButton, "RIGHT", 10, 0)
    analyzeItemText:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeItemText:SetText(ColorWrap("Drop Item", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))

    local analyzeItemTextBtn = CreateFrame("Button", nil, analyzePanel)
    analyzeItemTextBtn:SetPoint("TOPLEFT", analyzeItemText, "TOPLEFT", -2, 2)
    analyzeItemTextBtn:SetPoint("BOTTOMRIGHT", analyzeItemText, "BOTTOMRIGHT", 2, -2)
    analyzeItemTextBtn:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeItemTextBtn)

    local analyzeClearButton = CreateFrame("Button", nil, analyzePanel, "UIPanelButtonTemplate")
    analyzeClearButton:SetSize(60, 22)
    analyzeClearButton:SetText("Clear")
    analyzeClearButton:SetPoint("TOPRIGHT", analyzePanel, "TOPRIGHT", -12, -40)
    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(analyzeClearButton)
        end
    end

    local analyzeRecPanel = CreateFrame("Frame", nil, analyzePanel, "BackdropTemplate")
    analyzeRecPanel:SetPoint("TOPLEFT", analyzeItemButton, "BOTTOMLEFT", 0, -14)
    analyzeRecPanel:SetPoint("TOPRIGHT", analyzePanel, "TOPRIGHT", -12, 0)
    analyzeRecPanel:SetHeight(190)
    analyzeRecPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 0,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    analyzeRecPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.65)
    analyzeRecPanel:SetBackdropBorderColor(0, 0, 0, 1)

    local analyzeSectionTitle = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeSectionTitle, "normal")
    analyzeSectionTitle:SetPoint("TOPLEFT", analyzeRecPanel, "TOPLEFT", 10, -10)
    analyzeSectionTitle:SetTextColor(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3])
    analyzeSectionTitle:SetText("Recommendations")

    local analyzeSlotLine = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeSlotLine, "normal")
    analyzeSlotLine:SetPoint("TOPLEFT", analyzeSectionTitle, "BOTTOMLEFT", 0, -8)
    analyzeSlotLine:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeSlotLine:SetText("")

    local analyzeEnhLine = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeEnhLine, "normal")
    analyzeEnhLine:SetPoint("TOPLEFT", analyzeSlotLine, "BOTTOMLEFT", 0, -8)
    analyzeEnhLine:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeEnhLine:SetText("")

    local analyzeEnhBtn = CreateFrame("Button", nil, analyzePanel)
    analyzeEnhBtn:SetPoint("TOPLEFT", analyzeEnhLine, "TOPLEFT", -2, 2)
    analyzeEnhBtn:SetPoint("BOTTOMRIGHT", analyzeEnhLine, "BOTTOMRIGHT", 2, -2)
    analyzeEnhBtn:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeEnhBtn)

    local analyzeGemLine1 = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeGemLine1, "normal")
    analyzeGemLine1:SetPoint("TOPLEFT", analyzeEnhLine, "BOTTOMLEFT", 0, -6)
    analyzeGemLine1:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeGemLine1:SetText("")

    local analyzeGemBtn1 = CreateFrame("Button", nil, analyzePanel)
    analyzeGemBtn1:SetPoint("TOPLEFT", analyzeGemLine1, "TOPLEFT", -2, 2)
    analyzeGemBtn1:SetPoint("BOTTOMRIGHT", analyzeGemLine1, "BOTTOMRIGHT", 2, -2)
    analyzeGemBtn1:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeGemBtn1)

    local analyzeGemLine2 = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeGemLine2, "normal")
    analyzeGemLine2:SetPoint("TOPLEFT", analyzeGemLine1, "BOTTOMLEFT", 0, -6)
    analyzeGemLine2:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeGemLine2:SetText("")

    local analyzeGemBtn2 = CreateFrame("Button", nil, analyzePanel)
    analyzeGemBtn2:SetPoint("TOPLEFT", analyzeGemLine2, "TOPLEFT", -2, 2)
    analyzeGemBtn2:SetPoint("BOTTOMRIGHT", analyzeGemLine2, "BOTTOMRIGHT", 2, -2)
    analyzeGemBtn2:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeGemBtn2)

    local analyzeGemLine3 = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeGemLine3, "normal")
    analyzeGemLine3:SetPoint("TOPLEFT", analyzeGemLine2, "BOTTOMLEFT", 0, -6)
    analyzeGemLine3:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeGemLine3:SetText("")

    local analyzeGemBtn3 = CreateFrame("Button", nil, analyzePanel)
    analyzeGemBtn3:SetPoint("TOPLEFT", analyzeGemLine3, "TOPLEFT", -2, 2)
    analyzeGemBtn3:SetPoint("BOTTOMRIGHT", analyzeGemLine3, "BOTTOMRIGHT", 2, -2)
    analyzeGemBtn3:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeGemBtn3)

    local analyzeGemLine4 = analyzeRecPanel:CreateFontString(nil, "OVERLAY")
    SetFont(analyzeGemLine4, "normal")
    analyzeGemLine4:SetPoint("TOPLEFT", analyzeGemLine3, "BOTTOMLEFT", 0, -6)
    analyzeGemLine4:SetTextColor(COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3])
    analyzeGemLine4:SetText("")

    local analyzeGemBtn4 = CreateFrame("Button", nil, analyzePanel)
    analyzeGemBtn4:SetPoint("TOPLEFT", analyzeGemLine4, "TOPLEFT", -2, 2)
    analyzeGemBtn4:SetPoint("BOTTOMRIGHT", analyzeGemLine4, "BOTTOMRIGHT", 2, -2)
    analyzeGemBtn4:EnableMouse(true)
    ApplySelectedItemTooltip(analyzeGemBtn4)

    local function HandleAnalyzeLinkClick(self)
        local id = tonumber(self and self.__twichuiItemID)
        if not id or id <= 0 then return end
        local link = select(2, _G.GetItemInfo(id))
        if type(link) ~= "string" or link == "" then
            if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                pcall(_G.C_Item.RequestLoadItemDataByID, id)
            end
            return
        end
        if type(_G.HandleModifiedItemClick) == "function" then
            _G.HandleModifiedItemClick(link)
        elseif type(_G.ChatEdit_InsertLink) == "function" then
            _G.ChatEdit_InsertLink(link)
        end
    end

    analyzeItemTextBtn:SetScript("OnClick", HandleAnalyzeLinkClick)
    analyzeEnhBtn:SetScript("OnClick", HandleAnalyzeLinkClick)
    analyzeGemBtn1:SetScript("OnClick", HandleAnalyzeLinkClick)
    analyzeGemBtn2:SetScript("OnClick", HandleAnalyzeLinkClick)
    analyzeGemBtn3:SetScript("OnClick", HandleAnalyzeLinkClick)
    analyzeGemBtn4:SetScript("OnClick", HandleAnalyzeLinkClick)

    local analyzeItemId = nil
    local analyzeItemLink = nil

    local analyzeScanTip = nil
    local function EnsureAnalyzeScanTooltip()
        if analyzeScanTip then return analyzeScanTip end
        analyzeScanTip = CreateFrame("GameTooltip", "TwichUIAnalyzeEnhancementsScanTooltip", _G.UIParent,
            "GameTooltipTemplate")
        analyzeScanTip:SetOwner(_G.UIParent, "ANCHOR_NONE")
        analyzeScanTip:Hide()
        return analyzeScanTip
    end

    local function GetSocketCountForItem(itemLink, itemId)
        local link = itemLink
        local id = tonumber(itemId)

        if not link and id and id > 0 then
            link = select(2, _G.GetItemInfo(id))
        end

        -- If we still can't resolve a link, treat as loading.
        if (type(link) ~= "string" or link == "") and (not id or id <= 0) then
            return nil
        end

        local sockets = 0

        -- 1) Prefer GetItemStats() for empty sockets.
        if type(_G.GetItemStats) == "function" and type(link) == "string" and link ~= "" then
            local ok, stats = pcall(_G.GetItemStats, link)
            if ok and type(stats) == "table" then
                for k, v in pairs(stats) do
                    if type(k) == "string" and k:find("^EMPTY_SOCKET_") then
                        sockets = sockets + (tonumber(v) or 0)
                    end
                end
            end
        end

        -- 2) Count already-inserted gems (helps if sockets aren't reported as EMPTY_SOCKET_*).
        local inserted = 0
        if _G.C_Item and type(_G.C_Item.GetItemGem) == "function" and type(link) == "string" and link ~= "" then
            for gemIndex = 1, 4 do
                local _, gemLink = _G.C_Item.GetItemGem(link, gemIndex)
                if type(gemLink) == "string" and gemLink ~= "" then
                    inserted = inserted + 1
                end
            end
        end
        if inserted > sockets then
            sockets = inserted
        end

        -- 3) Tooltip-scan fallback (prismatic sockets often show up as a line like "Prismatic Socket").
        if sockets == 0 then
            local lines = nil
            if _G.C_TooltipInfo then
                if type(link) == "string" and link ~= "" and type(_G.C_TooltipInfo.GetHyperlink) == "function" then
                    local ok, info = pcall(_G.C_TooltipInfo.GetHyperlink, link)
                    if ok and type(info) == "table" and type(info.lines) == "table" then
                        lines = info.lines
                    end
                elseif id and id > 0 and type(_G.C_TooltipInfo.GetItemByID) == "function" then
                    local ok, info = pcall(_G.C_TooltipInfo.GetItemByID, id)
                    if ok and type(info) == "table" and type(info.lines) == "table" then
                        lines = info.lines
                    end
                end
            end

            if type(lines) == "table" then
                local count = 0
                for i = 1, #lines do
                    local line = lines[i]
                    local t = (type(line) == "table" and line.leftText) or nil
                    if type(t) == "string" and t ~= "" then
                        local low = t:lower()
                        if low:find("socket", 1, true) and not low:find("bonus", 1, true) then
                            -- Counts lines like "Prismatic Socket", "Meta Socket", etc.
                            count = count + 1
                        end
                    end
                end
                if count > sockets then
                    sockets = count
                end
            else
                -- Older fallback: scan a hidden GameTooltip.
                local tip = EnsureAnalyzeScanTooltip()
                tip:ClearLines()
                if type(link) == "string" and link ~= "" and type(tip.SetHyperlink) == "function" then
                    pcall(tip.SetHyperlink, tip, link)
                elseif id and id > 0 and type(tip.SetItemByID) == "function" then
                    pcall(tip.SetItemByID, tip, id)
                end

                local count = 0
                local n = tip:NumLines() or 0
                for i = 1, n do
                    local fs = _G["TwichUIAnalyzeEnhancementsScanTooltipTextLeft" .. tostring(i)]
                    local t = fs and fs.GetText and fs:GetText() or nil
                    if type(t) == "string" and t ~= "" then
                        local low = t:lower()
                        if low:find("socket", 1, true) and not low:find("bonus", 1, true) then
                            count = count + 1
                        end
                    end
                end
                if count > sockets then
                    sockets = count
                end
            end
        end

        return sockets
    end

    local EQUIPLOC_TO_INV_SLOTS = {
        INVTYPE_HEAD = { 1 },
        INVTYPE_NECK = { 2 },
        INVTYPE_SHOULDER = { 3 },
        INVTYPE_CLOAK = { 15 },
        INVTYPE_CHEST = { 5 },
        INVTYPE_ROBE = { 5 },
        INVTYPE_WRIST = { 9 },
        INVTYPE_HAND = { 10 },
        INVTYPE_WAIST = { 6 },
        INVTYPE_LEGS = { 7 },
        INVTYPE_FEET = { 8 },
        INVTYPE_FINGER = { 11, 12 },
        INVTYPE_TRINKET = { 13, 14 },
        INVTYPE_WEAPON = { 16 },
        INVTYPE_WEAPONMAINHAND = { 16 },
        INVTYPE_2HWEAPON = { 16 },
        INVTYPE_WEAPONOFFHAND = { 17 },
        INVTYPE_SHIELD = { 17 },
        INVTYPE_HOLDABLE = { 17 },
    }

    local EQUIPLOC_TO_SLOTKEY_CANDIDATES = {
        INVTYPE_HEAD = { "HEAD" },
        INVTYPE_NECK = { "NECK" },
        INVTYPE_SHOULDER = { "SHOULDERS", "SHOULDER" },
        INVTYPE_CLOAK = { "BACK" },
        INVTYPE_CHEST = { "CHEST" },
        INVTYPE_ROBE = { "CHEST" },
        INVTYPE_WRIST = { "WRISTS", "WRIST" },
        INVTYPE_HAND = { "HANDS", "HAND" },
        INVTYPE_WAIST = { "WAIST" },
        INVTYPE_LEGS = { "LEGS" },
        INVTYPE_FEET = { "FEET" },
        INVTYPE_FINGER = { "RING", "FINGER1", "FINGER2" },
        INVTYPE_TRINKET = { "TRINKET", "TRINKET1", "TRINKET2" },
        INVTYPE_WEAPON = { "MAINHAND" },
        INVTYPE_WEAPONMAINHAND = { "MAINHAND" },
        INVTYPE_2HWEAPON = { "MAINHAND" },
        INVTYPE_WEAPONOFFHAND = { "OFFHAND" },
        INVTYPE_SHIELD = { "OFFHAND" },
        INVTYPE_HOLDABLE = { "OFFHAND" },
    }

    local function ResolveSlotKeyForEquipLoc(equipLoc)
        local data = DataModule and DataModule.Handbook and DataModule.Handbook.GearEnhancements or nil
        local slots = data and data.Slots or nil
        if type(slots) ~= "table" then return nil end

        local candidates = EQUIPLOC_TO_SLOTKEY_CANDIDATES[equipLoc]
        if type(candidates) ~= "table" then return nil end
        for _, k in ipairs(candidates) do
            if slots[k] then
                return k
            end
        end
        return candidates[1]
    end

    local function CountEquippedGems(excludeInvSlots)
        local exclude = {}
        if type(excludeInvSlots) == "table" then
            for _, s in ipairs(excludeInvSlots) do
                exclude[tonumber(s) or -1] = true
            end
        end

        local out = {}
        if not _G.GetInventoryItemLink or not _G.C_Item or type(_G.C_Item.GetItemGem) ~= "function" then
            return out
        end

        for slotId = 1, 19 do
            if not exclude[slotId] then
                local link = _G.GetInventoryItemLink("player", slotId)
                if type(link) == "string" and link ~= "" then
                    for gemIndex = 1, 4 do
                        local _, gemLink = _G.C_Item.GetItemGem(link, gemIndex)
                        if type(gemLink) == "string" and gemLink ~= "" then
                            local gid = _G.GetItemInfoInstant and select(1, _G.GetItemInfoInstant(gemLink)) or nil
                            gid = tonumber(gid)
                            if gid and gid > 0 then
                                out[gid] = (out[gid] or 0) + 1
                            end
                        end
                    end
                end
            end
        end

        return out
    end

    RenderAnalyzeSlotEnhancements = function()
        analyzeGemLine1:SetText("")
        analyzeGemLine2:SetText("")
        analyzeGemLine3:SetText("")
        analyzeGemLine4:SetText("")

        if analyzeItemTextBtn then analyzeItemTextBtn.__twichuiItemID = nil end
        if analyzeEnhBtn then analyzeEnhBtn.__twichuiItemID = nil end
        if analyzeGemBtn1 then analyzeGemBtn1.__twichuiItemID = nil end
        if analyzeGemBtn2 then analyzeGemBtn2.__twichuiItemID = nil end
        if analyzeGemBtn3 then analyzeGemBtn3.__twichuiItemID = nil end
        if analyzeGemBtn4 then analyzeGemBtn4.__twichuiItemID = nil end

        if not analyzeItemId and not analyzeItemLink then
            analyzeItemIcon:SetTexture(nil)
            analyzeItemText:SetText(ColorWrap("Drop Item", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            analyzeSlotLine:SetText(ColorWrap("Slot: —", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            analyzeEnhLine:SetText(ColorWrap("Enhancement: —", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            analyzeGemLine1:SetText(ColorWrap("Gems: —", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            return
        end

        local iid, _, _, equipLoc, iconTex
        if _G.C_Item and type(_G.C_Item.GetItemInfoInstant) == "function" then
            iid, _, _, equipLoc, iconTex = _G.C_Item.GetItemInfoInstant(analyzeItemLink or analyzeItemId)
        else
            iid, _, _, equipLoc, iconTex = _G.GetItemInfoInstant(analyzeItemLink or analyzeItemId)
        end

        iid = tonumber(iid) or tonumber(analyzeItemId)
        analyzeItemId = iid

        if analyzeItemTextBtn then
            analyzeItemTextBtn.__twichuiItemID = iid
        end

        if iconTex then
            analyzeItemIcon:SetTexture(iconTex)
        else
            analyzeItemIcon:SetTexture(nil)
        end

        if iid and iid > 0 then
            if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                pcall(_G.C_Item.RequestLoadItemDataByID, iid)
            end
            if type(EnsureEnhItemLoadHook) == "function" then
                EnsureEnhItemLoadHook(iid)
            end
        end

        do
            local disp = GetItemDisplayFromId(iid)
            if disp == "Loading..." then
                analyzeItemText:SetText(ColorWrap("Loading...", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            else
                analyzeItemText:SetText(disp)
            end
        end

        local slotKey = equipLoc and ResolveSlotKeyForEquipLoc(equipLoc) or nil
        local slotLabel = slotKey or (equipLoc or "")
        local data = DataModule and DataModule.Handbook and DataModule.Handbook.GearEnhancements or nil
        local slots = data and data.Slots or nil
        if type(slots) == "table" and slotKey and slots[slotKey] and slots[slotKey].label then
            slotLabel = tostring(slots[slotKey].label)
        end
        if slotLabel == "" then slotLabel = "—" end
        analyzeSlotLine:SetText(ColorWrap("Slot: " .. slotLabel, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))

        local db = GetGearEnhancementsDB()
        local selectedBySlot = db and db.selectedBySlot or {}
        local enhItemId = (slotKey and selectedBySlot and selectedBySlot[slotKey]) or nil
        if enhItemId then
            if type(EnsureEnhItemLoadHook) == "function" then
                EnsureEnhItemLoadHook(enhItemId)
            end
            if analyzeEnhBtn then
                analyzeEnhBtn.__twichuiItemID = enhItemId
            end
            local disp = GetItemDisplayFromId(enhItemId)
            if disp == "Loading..." then
                analyzeEnhLine:SetText(ColorWrap("Enhancement: Loading...", COLOR_MUTED[1], COLOR_MUTED[2],
                    COLOR_MUTED[3]))
            else
                analyzeEnhLine:SetText("Enhancement: " .. disp)
            end
        else
            analyzeEnhLine:SetText(ColorWrap("Enhancement: None selected", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED
                [3]))
        end

        local sockets = GetSocketCountForItem(analyzeItemLink, iid)
        if sockets == nil then
            analyzeGemLine1:SetText(ColorWrap("Gems: Loading...", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            return
        end
        sockets = tonumber(sockets) or 0
        if sockets <= 0 then
            analyzeGemLine1:SetText(ColorWrap("Gems: No sockets detected", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED
                [3]))
            return
        end

        local excludeSlots = (equipLoc and EQUIPLOC_TO_INV_SLOTS[equipLoc]) or {}
        local equippedCounts = CountEquippedGems(excludeSlots)
        local usedCounts = {}
        for gid, c in pairs(equippedCounts) do
            usedCounts[gid] = c
        end

        local plist = (db and db.gemPriority and db.gemPriority.list) or {}
        if type(plist) ~= "table" or #plist == 0 then
            analyzeGemLine1:SetText(ColorWrap("Gems: Configure Gem Priority first", COLOR_MUTED[1], COLOR_MUTED[2],
                COLOR_MUTED[3]))
            return
        end

        local lines = { analyzeGemLine1, analyzeGemLine2, analyzeGemLine3, analyzeGemLine4 }
        local btns = { analyzeGemBtn1, analyzeGemBtn2, analyzeGemBtn3, analyzeGemBtn4 }
        for s = 1, math.min(4, sockets) do
            local chosen = nil
            for _, entry in ipairs(plist) do
                local gid = tonumber(entry and entry.itemId)
                if gid and gid > 0 then
                    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                        pcall(_G.C_Item.RequestLoadItemDataByID, gid)
                    end
                    if type(EnsureEnhItemLoadHook) == "function" then
                        EnsureEnhItemLoadHook(gid)
                    end
                    local maxCount = entry.maxCount
                    if maxCount ~= nil then
                        maxCount = tonumber(maxCount)
                    end
                    if not maxCount or maxCount <= 0 then
                        maxCount = 999
                    end
                    local used = tonumber(usedCounts[gid]) or 0
                    if used < maxCount then
                        chosen = gid
                        usedCounts[gid] = used + 1
                        break
                    end
                end
            end

            if chosen then
                if btns[s] then
                    btns[s].__twichuiItemID = chosen
                end
                local disp = GetItemDisplayFromId(chosen)
                if disp == "Loading..." then
                    lines[s]:SetText(ColorWrap("Gem " .. tostring(s) .. ": Loading...", COLOR_MUTED[1], COLOR_MUTED[2],
                        COLOR_MUTED[3]))
                else
                    lines[s]:SetText("Gem " .. tostring(s) .. ": " .. disp)
                end
            else
                if btns[s] then
                    btns[s].__twichuiItemID = nil
                end
                lines[s]:SetText(ColorWrap("Gem " .. tostring(s) .. ": No recommendation", COLOR_MUTED[1], COLOR_MUTED
                    [2], COLOR_MUTED[3]))
            end
        end

        for s = sockets + 1, 4 do
            if btns[s] then btns[s].__twichuiItemID = nil end
            if lines[s] then lines[s]:SetText("") end
        end
    end

    local function SetAnalyzeItem(item)
        if type(item) == "string" and item ~= "" then
            analyzeItemLink = item
            analyzeItemId = nil
        else
            analyzeItemLink = nil
            analyzeItemId = tonumber(item)
        end
        RenderAnalyzeSlotEnhancements()
    end

    analyzeClearButton:SetScript("OnClick", function()
        analyzeItemId = nil
        analyzeItemLink = nil
        RenderAnalyzeSlotEnhancements()
    end)

    analyzeItemButton:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if not _G.CursorHasItem or not _G.CursorHasItem() then return end
        local kind, itemIdOrLink = _G.GetCursorInfo()
        if kind ~= "item" then return end
        local link = itemIdOrLink
        if type(link) == "string" and link ~= "" then
            _G.ClearCursor()
            SetAnalyzeItem(link)
            return
        end
        local id = tonumber(itemIdOrLink)
        if id and id > 0 then
            _G.ClearCursor()
            SetAnalyzeItem(id)
            return
        end
    end)

    analyzeItemButton:SetScript("OnReceiveDrag", function()
        if not _G.CursorHasItem or not _G.CursorHasItem() then return end
        local kind, itemIdOrLink = _G.GetCursorInfo()
        if kind ~= "item" then return end
        local link = itemIdOrLink
        if type(link) == "string" and link ~= "" then
            _G.ClearCursor()
            SetAnalyzeItem(link)
            return
        end
        local id = tonumber(itemIdOrLink)
        if id and id > 0 then
            _G.ClearCursor()
            SetAnalyzeItem(id)
            return
        end
    end)

    analyzeItemButton:HookScript("OnEnter", function()
        if not _G.GameTooltip then return end
        if not analyzeItemLink and not analyzeItemId then return end

        _G.GameTooltip:SetOwner(analyzeItemButton, "ANCHOR_RIGHT")
        if analyzeItemLink and type(_G.GameTooltip.SetHyperlink) == "function" then
            _G.GameTooltip:SetHyperlink(analyzeItemLink)
            _G.GameTooltip:Show()
            return
        end

        local id = tonumber(analyzeItemId)
        if id and id > 0 then
            if type(_G.GameTooltip.SetItemByID) == "function" then
                pcall(_G.GameTooltip.SetItemByID, _G.GameTooltip, id)
                _G.GameTooltip:Show()
                return
            end
            local link = select(2, _G.GetItemInfo(id))
            if type(link) == "string" and link ~= "" and type(_G.GameTooltip.SetHyperlink) == "function" then
                _G.GameTooltip:SetHyperlink(link)
                _G.GameTooltip:Show()
                return
            end
        end
    end)
    analyzeItemButton:HookScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    local function RenderGearTracks()
        gearTable.ClearRows()

        local list = DataModule and DataModule.Handbook and DataModule.Handbook.GearTracks or nil
        if type(list) ~= "table" or #list == 0 then
            local row = gearTable.EnsureRow(1)
            row.cols[1]:SetText(ColorWrap("No entries", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.cols[2]:SetText("")
            row.cols[3]:SetText(ColorWrap("Edit Data.Handbook.GearTracks (Modules/Data/Handbook.lua)", COLOR_MUTED[1],
                COLOR_MUTED[2], COLOR_MUTED[3]))
            row:Show()
            gearTable.SetScrollHeight(row)
            return
        end

        local last = gearTable.HeaderSep
        for i, entry in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = gearTable.EnsureRow(i)

            local keyLevel = tonumber(entry.level or entry.keystoneLevel) or 0
            local ilvl = tonumber(entry.itemLevel or entry.ilvl) or 0
            local track = tostring(entry.track or "")

            local tr, tg, tb = COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]
            local rr, gg, bb = HexToRGB(entry.color)
            if rr and gg and bb then
                tr, tg, tb = rr, gg, bb
            end

            row.cols[1]:SetText(ColorWrap("+" .. tostring(keyLevel), COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3]))
            row.cols[2]:SetText(ColorWrap(tostring(ilvl), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.cols[3]:SetText(ColorWrap(track, tr, tg, tb))

            row:Show()
            last = row
        end

        gearTable.SetScrollHeight(last)
    end

    local function RenderCrests()
        crestsTable.ClearRows()

        local list = DataModule and DataModule.Handbook and DataModule.Handbook.Crests or nil
        if type(list) ~= "table" or #list == 0 then
            local row = crestsTable.EnsureRow(1)
            row.cols[1]:SetText(ColorWrap("No entries", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
            row.cols[2]:SetText("")
            row.cols[3]:SetText("")
            row.cols[4]:SetText("")
            row.cols[1]:SetText(ColorWrap("Edit Data.Handbook.Crests (Modules/Data/Handbook.lua)", COLOR_MUTED[1],
                COLOR_MUTED[2], COLOR_MUTED[3]))
            row:Show()
            crestsTable.SetScrollHeight(row)
            return
        end

        local last = crestsTable.HeaderSep
        for i, entry in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = crestsTable.EnsureRow(i)

            local crest = tostring(entry.crest or entry.name or "")

            local keyLevel = tonumber(entry.keystoneLevel or entry.keystone)
            local keyText = keyLevel and ("+" .. tostring(keyLevel)) or ""

            local delveVal = entry.delveLevel
            if delveVal == nil then delveVal = entry.delve end
            local delveText = delveVal ~= nil and tostring(delveVal) or "—"

            local raidVal = entry.raidLevel
            if raidVal == nil then raidVal = entry.raid end
            local raidText = raidVal ~= nil and tostring(raidVal) or ""

            row.cols[1]:SetText(ColorWrap(crest, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.cols[2]:SetText(ColorWrap(keyText, COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3]))
            row.cols[3]:SetText(ColorWrap(delveText, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.cols[4]:SetText(ColorWrap(raidText, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))

            row:Show()
            last = row
        end

        crestsTable.SetScrollHeight(last)
    end

    local function RenderItemUpgrades()
        itemUpgradeTable.ClearRows()

        local list = DataModule and DataModule.Handbook and DataModule.Handbook.ItemUpgrades or nil
        if type(list) ~= "table" or #list == 0 then
            local row = itemUpgradeTable.EnsureRow(1)
            row.cols[1]:SetText(ColorWrap("Edit Data.Handbook.ItemUpgrades (Modules/Data/Handbook.lua)", COLOR_MUTED[1],
                COLOR_MUTED[2], COLOR_MUTED[3]))
            row.cols[2]:SetText("")
            row:Show()
            itemUpgradeTable.SetScrollHeight(row)
            return
        end

        local last = itemUpgradeTable.HeaderSep
        for i, entry in ipairs(list) do
            if i > MAX_ROWS then break end
            local row = itemUpgradeTable.EnsureRow(i)

            local track = tostring(entry.track or "")
            local crestCost = entry.crestCost
            local costText = crestCost ~= nil and tostring(crestCost) or ""

            row.cols[1]:SetText(ColorWrap(track, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))
            row.cols[2]:SetText(ColorWrap(costText, COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))

            row:Show()
            last = row
        end

        itemUpgradeTable.SetScrollHeight(last)
    end

    local function SelectTab(index)
        if index == 7 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Hide()
            statPriorityPage:Hide()
            gearEnhancementsPage:Hide()
            gemPriorityPage:Hide()
            analyzeEnhancementsPage:Show()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab4, false)
            SetTabSelected(tab5, false)
            SetTabSelected(tab6, false)
            SetTabSelected(tab7, true)
            RenderAnalyzeSlotEnhancements()
            return
        end

        if index == 6 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Hide()
            statPriorityPage:Hide()
            gearEnhancementsPage:Hide()
            gemPriorityPage:Show()
            analyzeEnhancementsPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab4, false)
            SetTabSelected(tab5, false)
            SetTabSelected(tab6, true)
            SetTabSelected(tab7, false)
            RenderGemPriority()
            return
        end

        if index == 5 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Hide()
            statPriorityPage:Hide()
            gearEnhancementsPage:Show()
            gemPriorityPage:Hide()
            analyzeEnhancementsPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab4, false)
            SetTabSelected(tab5, true)
            SetTabSelected(tab6, false)
            SetTabSelected(tab7, false)
            RenderSlotEnhancements()
            return
        end

        if index == 4 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Hide()
            statPriorityPage:Show()
            gearEnhancementsPage:Hide()
            gemPriorityPage:Hide()
            analyzeEnhancementsPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab4, true)
            SetTabSelected(tab5, false)
            SetTabSelected(tab6, false)
            SetTabSelected(tab7, false)
            RenderStatPriority()
            return
        end

        if index == 3 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Show()
            statPriorityPage:Hide()
            gearEnhancementsPage:Hide()
            gemPriorityPage:Hide()
            analyzeEnhancementsPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, true)
            SetTabSelected(tab4, false)
            SetTabSelected(tab5, false)
            SetTabSelected(tab6, false)
            SetTabSelected(tab7, false)
            RenderItemUpgrades()
            return
        end

        if index == 2 then
            gearPage:Hide()
            itemUpgradePage:Hide()
            crestsPage:Show()
            statPriorityPage:Hide()
            gearEnhancementsPage:Hide()
            gemPriorityPage:Hide()
            analyzeEnhancementsPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab2, true)
            SetTabSelected(tab4, false)
            SetTabSelected(tab5, false)
            SetTabSelected(tab6, false)
            SetTabSelected(tab7, false)
            RenderCrests()
            return
        end

        crestsPage:Hide()
        itemUpgradePage:Hide()
        statPriorityPage:Hide()
        gearEnhancementsPage:Hide()
        gemPriorityPage:Hide()
        analyzeEnhancementsPage:Hide()
        gearPage:Show()
        SetTabSelected(tab2, false)
        SetTabSelected(tab3, false)
        SetTabSelected(tab4, false)
        SetTabSelected(tab5, false)
        SetTabSelected(tab6, false)
        SetTabSelected(tab7, false)
        SetTabSelected(tab1, true)
        RenderGearTracks()
    end

    tab1:SetScript("OnClick", function() SelectTab(1) end)
    tab2:SetScript("OnClick", function() SelectTab(2) end)
    tab3:SetScript("OnClick", function() SelectTab(3) end)
    tab4:SetScript("OnClick", function() SelectTab(4) end)
    tab5:SetScript("OnClick", function() SelectTab(5) end)
    tab6:SetScript("OnClick", function() SelectTab(6) end)
    tab7:SetScript("OnClick", function() SelectTab(7) end)
    SelectTab(1)

    frame:SetScript("OnShow", function()
        if gearEnhancementsPage:IsShown() then
            RenderSlotEnhancements()
        elseif gemPriorityPage:IsShown() then
            RenderGemPriority()
        elseif analyzeEnhancementsPage:IsShown() then
            RenderAnalyzeSlotEnhancements()
        elseif statPriorityPage:IsShown() then
            RenderStatPriority()
        elseif itemUpgradePage:IsShown() then
            RenderItemUpgrades()
        elseif crestsPage:IsShown() then
            RenderCrests()
        else
            RenderGearTracks()
        end
    end)

    return frame
end

function Handbook:Initialize()
    if self.initialized then return end
    self.initialized = true

    if MythicPlusModule.MainWindow and MythicPlusModule.MainWindow.RegisterPanel then
        -- handbook.tga is 64x50. Keep aspect ratio; match the common 32px height nav icons.
        MythicPlusModule.MainWindow:RegisterPanel(
            PANEL_ID,
            function(parent, window)
                return CreateHandbookFrame(parent)
            end,
            nil,
            nil,
            {
                label = LABEL_TEXT,
                order = 55,
                icon = ICON_PATH,
                iconSize = { 41, 32 },
            }
        )
    end
end
