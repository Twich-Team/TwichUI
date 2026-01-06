local _G = _G
---@diagnostic disable: need-check-nil, undefined-field
---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

--- @class MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

--- @type ConfigurationModule
local CM = T:GetModule("Configuration")

local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip

-- LSM is backed by ElvUI's media library when available
local LSM = T.Libs and T.Libs.LSM
local Masque = T.Libs and T.Libs.Masque

---@class MythicPlusKeystoneSubmodule
---@field initialized boolean|nil
local Keystone = MythicPlusModule.Keystone or {}
MythicPlusModule.Keystone = Keystone

---@class TwichUI_MythicPlus_AffixListFrame : Frame
---@field __twichuiButtons TwichUI_MythicPlus_AffixButton[]|nil
---@field __twichuiEmptyText FontString|nil

---@class TwichUI_MythicPlus_KeystonePanel : Frame
---@field __twichuiTitle FontString
---@field __twichuiHeader Frame
---@field __twichuiKeyLine FontString
---@field __twichuiSubLine FontString
---@field __twichuiDungeonImage Texture
---@field __twichuiOwnedLabel FontString
---@field __twichuiOwnedList TwichUI_MythicPlus_AffixListFrame
---@field __twichuiWeeklyLabel FontString
---@field __twichuiWeeklyList TwichUI_MythicPlus_AffixListFrame
---@field __twichuiFontPath string|nil
---@field __twichuiEventsEnabled boolean|nil

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE_DELAYED",
    "CHALLENGE_MODE_MAPS_UPDATE",
    "CHALLENGE_MODE_COMPLETED",
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
}

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
---@return number|string|nil texture
local function GetMapNameAndTexture(mapId)
    mapId = tonumber(mapId)
    if not mapId then return nil, nil end

    local mpData = MythicPlusModule and MythicPlusModule.Data
    if mpData and type(mpData.GetMapUIInfoCached) == "function" then
        local name, _, texture, backgroundTexture = mpData.GetMapUIInfoCached(mapId)
        if name or backgroundTexture or texture then
            return name, backgroundTexture or texture
        end
    end

    local C_ChallengeMode = _G.C_ChallengeMode
    if not C_ChallengeMode then return nil, nil end

    if type(C_ChallengeMode.GetMapUIInfo) == "function" then
        local name, _, _, texture, backgroundTexture = C_ChallengeMode.GetMapUIInfo(mapId)
        return name, backgroundTexture or texture
    end

    if type(C_ChallengeMode.GetMapInfo) == "function" then
        local info = C_ChallengeMode.GetMapInfo(mapId)
        if type(info) == "table" then
            return info.name, info.texture or info.backgroundTexture
        end
    end

    return nil, nil
end

local function GetFontPath()
    local fontName = MythicPlusModule.CONFIGURATION and MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT and
        CM:GetProfileSettingByConfigEntry(MythicPlusModule.CONFIGURATION.MAIN_WINDOW_FONT)

    if LSM and fontName then
        return LSM:Fetch("font", fontName)
    end

    return nil
end

---@return any|nil masqueGroup
function Keystone:_EnsureMasqueGroup()
    if self.__twichuiMasqueGroup ~= nil then
        return self.__twichuiMasqueGroup
    end

    if not Masque or type(Masque.Group) ~= "function" then
        self.__twichuiMasqueGroup = false
        return nil
    end

    local ok, group = pcall(Masque.Group, Masque, "TwichUI", "MythicPlus Keystone")
    if ok and group then
        self.__twichuiMasqueGroup = group
        return group
    end

    self.__twichuiMasqueGroup = false
    return nil
end

---@class TwichUI_MythicPlus_AffixButton : Button
---@field Icon Texture
---@field Label FontString
---@field __twichuiAffixId number|nil
---@field __twichuiMasqueAdded boolean|nil

---@param parent Frame
---@param size number
---@param fontPath string|nil
---@return TwichUI_MythicPlus_AffixButton
local function CreateAffixButton(parent, size, fontPath)
    ---@class TwichUI_MythicPlus_AffixButton
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

    btn.Icon = btn:CreateTexture(nil, "ARTWORK")
    btn.Icon:SetAllPoints(btn)
    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.Label = btn:CreateFontString(nil, "OVERLAY")
    if btn.Label.SetFontObject then
        btn.Label:SetFontObject(_G.GameFontHighlightSmall)
    end
    if fontPath and btn.Label.SetFont then
        btn.Label:SetFont(fontPath, 11, "OUTLINE")
    end
    if btn.Label.SetWordWrap then
        btn.Label:SetWordWrap(true)
    end
    btn.Label:SetJustifyH("CENTER")
    btn.Label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    if btn.Label.SetWidth then
        btn.Label:SetWidth(size + 14)
    end
    if btn.Label.SetHeight then
        btn.Label:SetHeight(26)
    end
    btn.Label:SetText("")

    btn:SetScript("OnEnter", function(self)
        local affixId = self.__twichuiAffixId
        if not affixId or not GameTooltip then return end

        local name, description = GetAffixInfo(affixId)
        if not name then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name, 1, 1, 1)
        if description and description ~= "" then
            GameTooltip:AddLine(description, 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    return btn
end

---@param group any|nil
---@param btn TwichUI_MythicPlus_AffixButton
local function AddToMasqueGroup(group, btn)
    if not group or type(group.AddButton) ~= "function" then return end
    if btn.__twichuiMasqueAdded then return end

    local ok = pcall(group.AddButton, group, btn, { Icon = btn.Icon })
    if ok then
        btn.__twichuiMasqueAdded = true
    end
end

---@param panel TwichUI_MythicPlus_KeystonePanel
---@param listContainer TwichUI_MythicPlus_AffixListFrame
---@param labelPrefix string
---@param affixIds number[]
---@param maxCount number
---@param iconSize number
---@param fontPath string|nil
---@param masqueGroup any|nil
local function UpdateAffixButtons(panel, listContainer, labelPrefix, affixIds, maxCount, iconSize, fontPath, masqueGroup)
    listContainer.__twichuiButtons = listContainer.__twichuiButtons or {}

    ---@type TwichUI_MythicPlus_AffixButton[]
    local buttons = listContainer.__twichuiButtons
    local count = math.max(maxCount or 0, #affixIds)

    for i = 1, count do
        local btn = buttons[i]
        if not btn then
            btn = CreateAffixButton(listContainer, iconSize, fontPath)
            buttons[i] = btn
            local prev = (i > 1) and buttons[i - 1] or nil
            if prev then
                btn:SetPoint("LEFT", prev, "RIGHT", 16, 0)
            else
                btn:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, 0)
            end
            AddToMasqueGroup(masqueGroup, btn)
        end

        local affixId = affixIds[i]
        if affixId then
            local name, _, fileDataId = GetAffixInfo(affixId)
            btn.__twichuiAffixId = affixId
            btn.Icon:SetTexture(fileDataId)
            btn.Label:SetText(name or (labelPrefix .. tostring(affixId)))
            btn:Show()
            btn.Label:Show()
        else
            btn.__twichuiAffixId = nil
            btn:Hide()
            btn.Label:Hide()
        end
    end
end

---@param parent Frame
---@return TwichUI_MythicPlus_KeystonePanel
local function CreateKeystonePanel(parent)
    ---@class TwichUI_MythicPlus_KeystonePanel
    local panel = CreateFrame("Frame", nil, parent)

    local title = panel:CreateFontString(nil, "OVERLAY")
    if title.SetFontObject then
        title:SetFontObject(_G.GameFontNormalLarge)
    end

    local fontPath = GetFontPath()
    if fontPath and title.SetFont then
        title:SetFont(fontPath, 16, "OUTLINE")
    end

    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    title:SetText("Keystone")

    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    header:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    header:SetHeight(86)

    local dungeonImage = header:CreateTexture(nil, "BACKGROUND")
    dungeonImage:SetAllPoints(header)
    dungeonImage:SetAlpha(0.45)
    dungeonImage:Hide()

    local keyLine = header:CreateFontString(nil, "OVERLAY")
    if keyLine.SetFontObject then
        keyLine:SetFontObject(_G.GameFontHighlightLarge)
    end
    if fontPath and keyLine.SetFont then
        keyLine:SetFont(fontPath, 14, "OUTLINE")
    end
    keyLine:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -6)
    keyLine:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    keyLine:SetJustifyH("LEFT")
    keyLine:SetText("Loading keystone…")

    local subLine = header:CreateFontString(nil, "OVERLAY")
    if subLine.SetFontObject then
        subLine:SetFontObject(_G.GameFontNormal)
    end
    if fontPath and subLine.SetFont then
        subLine:SetFont(fontPath, 12, "OUTLINE")
    end
    subLine:SetPoint("TOPLEFT", keyLine, "BOTTOMLEFT", 0, -6)
    subLine:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    subLine:SetJustifyH("LEFT")
    subLine:SetText("")

    local ownedLabel = panel:CreateFontString(nil, "OVERLAY")
    if ownedLabel.SetFontObject then
        ownedLabel:SetFontObject(_G.GameFontNormal)
    end
    if fontPath and ownedLabel.SetFont then
        ownedLabel:SetFont(fontPath, 12, "OUTLINE")
    end
    ownedLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    ownedLabel:SetText("Keystone affixes")

    ---@class TwichUI_MythicPlus_AffixListFrame
    local ownedList = CreateFrame("Frame", nil, panel)
    ownedList:SetPoint("TOPLEFT", ownedLabel, "BOTTOMLEFT", 0, -8)
    ownedList:SetHeight(64)
    ownedList:SetPoint("RIGHT", panel, "RIGHT", -10, 0)

    local weeklyLabel = panel:CreateFontString(nil, "OVERLAY")
    if weeklyLabel.SetFontObject then
        weeklyLabel:SetFontObject(_G.GameFontNormal)
    end
    if fontPath and weeklyLabel.SetFont then
        weeklyLabel:SetFont(fontPath, 12, "OUTLINE")
    end
    weeklyLabel:SetPoint("TOPLEFT", ownedList, "BOTTOMLEFT", 0, -14)
    weeklyLabel:SetText("Weekly affixes")

    ---@class TwichUI_MythicPlus_AffixListFrame
    local weeklyList = CreateFrame("Frame", nil, panel)
    weeklyList:SetPoint("TOPLEFT", weeklyLabel, "BOTTOMLEFT", 0, -8)
    weeklyList:SetHeight(64)
    weeklyList:SetPoint("RIGHT", panel, "RIGHT", -10, 0)

    panel.__twichuiTitle = title
    panel.__twichuiHeader = header
    panel.__twichuiKeyLine = keyLine
    panel.__twichuiSubLine = subLine
    panel.__twichuiDungeonImage = dungeonImage
    panel.__twichuiOwnedLabel = ownedLabel
    panel.__twichuiOwnedList = ownedList
    panel.__twichuiWeeklyLabel = weeklyLabel
    panel.__twichuiWeeklyList = weeklyList
    panel.__twichuiFontPath = fontPath

    panel:SetScript("OnShow", function()
        if Keystone and Keystone.Refresh then
            Keystone:Refresh()
        end
    end)

    return panel
end

---@param panel Frame
function Keystone:_EnableEvents(panel)
    ---@cast panel TwichUI_MythicPlus_KeystonePanel
    if not panel or panel.__twichuiEventsEnabled then return end
    panel.__twichuiEventsEnabled = true

    panel:SetScript("OnEvent", function()
        if Keystone and Keystone.Refresh then
            Keystone:Refresh()
        end
    end)

    for _, ev in ipairs(EVENTS) do
        pcall(panel.RegisterEvent, panel, ev)
    end
end

---@param panel Frame
function Keystone:_DisableEvents(panel)
    ---@cast panel TwichUI_MythicPlus_KeystonePanel
    if not panel or not panel.__twichuiEventsEnabled then return end
    panel.__twichuiEventsEnabled = false

    for _, ev in ipairs(EVENTS) do
        pcall(panel.UnregisterEvent, panel, ev)
    end
end

function Keystone:Refresh()
    ---@type TwichUI_MythicPlus_KeystonePanel|nil
    local panel = self.__twichuiPanel
    if not panel or not panel.__twichuiKeyLine then return end

    local C_MythicPlus = _G.C_MythicPlus
    local ownedMapID = (C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function")
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or nil
    local ownedLevel = (C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneLevel) == "function")
        and C_MythicPlus.GetOwnedKeystoneLevel() or nil

    -- Ask the client to populate map/affix data if it supports these calls.
    if ownedMapID and C_MythicPlus and type(C_MythicPlus.RequestMapInfo) == "function" then
        pcall(C_MythicPlus.RequestMapInfo, ownedMapID)
    end
    if C_MythicPlus and type(C_MythicPlus.RequestCurrentAffixes) == "function" then
        pcall(C_MythicPlus.RequestCurrentAffixes)
    end

    local mapName, mapTexture = GetMapNameAndTexture(ownedMapID)

    if ownedMapID and ownedLevel then
        panel.__twichuiKeyLine:SetText(string.format("%s  |cff00ff00+%d|r", mapName or "Unknown Dungeon",
            tonumber(ownedLevel) or 0))
    else
        panel.__twichuiKeyLine:SetText("No keystone found")
    end

    if panel.__twichuiDungeonImage then
        if mapTexture then
            panel.__twichuiDungeonImage:SetTexture(mapTexture)
            panel.__twichuiDungeonImage:Show()
        else
            panel.__twichuiDungeonImage:Hide()
        end
    end

    local ownedAffixIds = {}
    if C_MythicPlus and type(C_MythicPlus.GetOwnedKeystoneAffixes) == "function" then
        local affixes = C_MythicPlus.GetOwnedKeystoneAffixes()
        if type(affixes) == "table" then
            for _, entry in ipairs(affixes) do
                local id = NormalizeAffixId(entry)
                if id then table.insert(ownedAffixIds, id) end
            end
        end
    end

    local keyLevel = tonumber(ownedLevel)
    local keyHasAffixes = (ownedMapID ~= nil) and (keyLevel ~= nil) and (keyLevel >= 2)

    local weeklyAffixIds = {}
    if C_MythicPlus and type(C_MythicPlus.GetCurrentAffixes) == "function" then
        local affixes = C_MythicPlus.GetCurrentAffixes()
        if type(affixes) == "table" then
            for _, entry in ipairs(affixes) do
                local id = NormalizeAffixId(entry)
                if id then table.insert(weeklyAffixIds, id) end
            end
        end
    end

    local masqueGroup = self:_EnsureMasqueGroup()

    local hasOwned = (#ownedAffixIds > 0)

    if panel.__twichuiSubLine then
        if ownedMapID and ownedLevel then
            if hasOwned then
                panel.__twichuiSubLine:SetText("Your key affixes")
            elseif not keyHasAffixes then
                panel.__twichuiSubLine:SetText("No affixes")
            else
                panel.__twichuiSubLine:SetText("Affixes loading…")
            end
        else
            panel.__twichuiSubLine:SetText("Weekly affixes shown below")
        end
    end

    if panel.__twichuiOwnedList then
        UpdateAffixButtons(panel, panel.__twichuiOwnedList, "Affix ", ownedAffixIds, 4, 32, panel.__twichuiFontPath,
            masqueGroup)

        local ownedList = panel.__twichuiOwnedList
        if ownedList then
            if not ownedList.__twichuiEmptyText then
                ownedList.__twichuiEmptyText = ownedList:CreateFontString(nil, "OVERLAY")
                local txt = ownedList.__twichuiEmptyText
                if txt.SetFontObject then
                    txt:SetFontObject(_G.GameFontDisable)
                end
                if panel.__twichuiFontPath and txt.SetFont then
                    txt:SetFont(panel.__twichuiFontPath, 12, "OUTLINE")
                end
                txt:SetPoint("TOPLEFT", ownedList, "TOPLEFT", 0, 6)
                txt:SetJustifyH("LEFT")
            end

            local empty = ownedList.__twichuiEmptyText
            if ownedMapID and ownedLevel and (not hasOwned) and (not keyHasAffixes) then
                empty:SetText("No affixes")
                empty:Show()
            else
                empty:Hide()
            end
        end
    end
    if panel.__twichuiWeeklyList then
        UpdateAffixButtons(panel, panel.__twichuiWeeklyList, "Affix ", weeklyAffixIds, 4, 32, panel.__twichuiFontPath,
            masqueGroup)
    end
end

function Keystone:Initialize()
    if self.initialized then return end
    self.initialized = true

    -- Keystone info is now shown in the title bar header; the old Keystone panel is retired.
end
