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

local FALLBACK_PROFILE_DB = {
    statPriority = {
        list = {},
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
    { key = "STRENGTH", label = _G.STAT_STRENGTH or "Strength" },
    { key = "AGILITY", label = _G.STAT_AGILITY or "Agility" },
    { key = "INTELLECT", label = _G.STAT_INTELLECT or "Intellect" },
    { key = "STAMINA", label = _G.STAT_STAMINA or "Stamina" },

    { key = "CRIT", label = _G.STAT_CRITICAL_STRIKE or _G.ITEM_MOD_CRIT_RATING_SHORT or "Critical Strike" },
    { key = "HASTE", label = _G.STAT_HASTE or _G.ITEM_MOD_HASTE_RATING_SHORT or "Haste" },
    { key = "MASTERY", label = _G.STAT_MASTERY or _G.ITEM_MOD_MASTERY_RATING_SHORT or "Mastery" },
    { key = "VERSATILITY", label = _G.STAT_VERSATILITY or _G.ITEM_MOD_VERSATILITY or "Versatility" },

    { key = "LEECH", label = _G.STAT_LIFESTEAL or "Leech" },
    { key = "AVOIDANCE", label = _G.STAT_AVOIDANCE or "Avoidance" },
    { key = "SPEED", label = _G.STAT_SPEED or "Speed" },
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

    if E then
        local S = E:GetModule("Skins")
        if S and S.HandleButton then
            S:HandleButton(tab1)
            S:HandleButton(tab2)
            S:HandleButton(tab3)
            S:HandleButton(tab4)
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
            if nt then nt:SetTexture(nil) nt:Hide() end
            if pt then pt:SetTexture(nil) pt:Hide() end
            if dt then dt:SetTexture(nil) dt:Hide() end
            if ht then ht:SetTexture(nil) ht:Hide() end
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
        row.btnUp:SetSize(34, 18)
        row.btnUp:SetText("Up")
        row.btnUp:SetPoint("RIGHT", row, "RIGHT", -86, 0)

        row.btnDown = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnDown:SetSize(44, 18)
        row.btnDown:SetText("Down")
        row.btnDown:SetPoint("LEFT", row.btnUp, "RIGHT", 4, 0)

        row.btnRemove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btnRemove:SetSize(22, 18)
        row.btnRemove:SetText("X")
        row.btnRemove:SetPoint("LEFT", row.btnDown, "RIGHT", 4, 0)

        if E then
            local S = E:GetModule("Skins")
            if S and S.HandleButton then
                S:HandleButton(row.btnUp)
                S:HandleButton(row.btnDown)
                S:HandleButton(row.btnRemove)
            end
        end

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
            row.stat:SetText(ColorWrap("Use the dropdown above to add stats", COLOR_MUTED[1], COLOR_MUTED[2], COLOR_MUTED[3]))
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
            row.stat:SetText(ColorWrap(STAT_LABEL_BY_KEY[statKey] or tostring(statKey), COLOR_PRIMARY[1], COLOR_PRIMARY[2], COLOR_PRIMARY[3]))

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
                        if type(ddSetText) == "function" then ddSetText(statDropdown, STAT_LABEL_BY_KEY[arg1] or tostring(arg1)) end
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
        if index == 4 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Hide()
            statPriorityPage:Show()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab4, true)
            RenderStatPriority()
            return
        end

        if index == 3 then
            gearPage:Hide()
            crestsPage:Hide()
            itemUpgradePage:Show()
            statPriorityPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab2, false)
            SetTabSelected(tab3, true)
            SetTabSelected(tab4, false)
            RenderItemUpgrades()
            return
        end

        if index == 2 then
            gearPage:Hide()
            itemUpgradePage:Hide()
            crestsPage:Show()
            statPriorityPage:Hide()
            SetTabSelected(tab1, false)
            SetTabSelected(tab3, false)
            SetTabSelected(tab2, true)
            SetTabSelected(tab4, false)
            RenderCrests()
            return
        end

        crestsPage:Hide()
        itemUpgradePage:Hide()
        statPriorityPage:Hide()
        gearPage:Show()
        SetTabSelected(tab2, false)
        SetTabSelected(tab3, false)
        SetTabSelected(tab4, false)
        SetTabSelected(tab1, true)
        RenderGearTracks()
    end

    tab1:SetScript("OnClick", function() SelectTab(1) end)
    tab2:SetScript("OnClick", function() SelectTab(2) end)
    tab3:SetScript("OnClick", function() SelectTab(3) end)
    tab4:SetScript("OnClick", function() SelectTab(4) end)
    SelectTab(1)

    frame:SetScript("OnShow", function()
        if statPriorityPage:IsShown() then
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
