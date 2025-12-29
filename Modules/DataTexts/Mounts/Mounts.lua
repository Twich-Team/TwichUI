local T = unpack(Twich)

--- @type DataTextsModule
local DataTexts = T:GetModule("DataTexts")
--- @type ToolsModule
local Tools = T:GetModule("Tools")
--- @type ConfigurationModule
local Configuration = T:GetModule("Configuration")
--- @type LoggerModule
local Logger = T:GetModule("Logger")

-- WoW globals
local _G = _G
local tinsert = tinsert
local wipe = wipe
local ipairs = ipairs
local tostring = tostring

---@class MountsDataText
---@field displayCache GenericCache|nil
---@field utilityMountIdCache GenericCache|nil
---@field mountsCache GenericCache|nil
---@field mountOptionsCache GenericCache|nil
---@field menuList TwichUI_MenuItem[]|nil
---@field panel any|nil
local MountsDataText = DataTexts.Mounts or {}
DataTexts.Mounts = MountsDataText

local DATATEXT_NAME = "TwichUI_Mounts"

-- Default utility mounts (spell IDs); can be extended in code.
local DEFAULT_UTILITY_MOUNT_SPELL_IDS = {
    122708, -- Grand Expedition Yak
    457485, -- Grizzly Hills Packmaster? (legacy)
    264058, -- Mighty Caravan Brutosaur (legacy)
    465235, -- (TWW) repair/vendor style mount
    61447,  -- Traveler's Tundra Mammoth
}

local SortMode = {
    JOURNAL = { id = "journal", name = "Journal order" },
    NAME = { id = "name", name = "Name (A-Z)" },
}

local Module = Tools.Generics.Module:New({
    ENABLED = { key = "datatexts.mounts.enable", default = false, },
    COLOR_MODE = { key = "datatexts.mounts.colorMode", default = DataTexts.ColorMode.ELVUI },
    CUSTOM_COLOR = { key = "datatexts.mounts.customColor", default = DataTexts.DefaultColor },

    DISPLAY_TEXT = { key = "datatexts.mounts.displayText", default = "Mounts" },
    SHOW_ICON = { key = "datatexts.mounts.showIcon", default = false },
    ICON_TEXTURE = { key = "datatexts.mounts.iconTexture", default = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    ICON_SIZE = { key = "datatexts.mounts.iconSize", default = 14 },
    ICON_PADDING = { key = "datatexts.mounts.iconPadding", default = 2 },

    OPEN_MENU_ON_HOVER = { key = "datatexts.mounts.openMenuOnHover", default = true },

    CLICK_SUMMON_ENABLED = { key = "datatexts.mounts.clickSummon.enabled", default = true },
    FAVORITE_GROUND_MOUNT_ID = { key = "datatexts.mounts.clickSummon.groundMountId", default = 0 },
    FAVORITE_FLYING_MOUNT_ID = { key = "datatexts.mounts.clickSummon.flyingMountId", default = 0 },

    SHOW_FAVORITES = { key = "datatexts.mounts.showFavorites", default = true },
    SHOW_UTILITY = { key = "datatexts.mounts.showUtility", default = true },
    HIDE_UNUSABLE = { key = "datatexts.mounts.hideUnusable", default = false },
    SORT_MODE = { key = "datatexts.mounts.sortMode", default = SortMode.JOURNAL },

    SHOW_SWITCH_FLIGHT_STYLE = { key = "datatexts.mounts.showSwitchFlightStyle", default = true },
    HIDE_TIP_TEXT = { key = "datatexts.mounts.hideTipText", default = false },
})

function MountsDataText:GetConfiguration()
    return Module.CONFIGURATION
end

local function TooltipHide()
    if _G.GameTooltip and _G.GameTooltip.Hide then
        _G.GameTooltip:Hide()
    end
end

local function TooltipForMountBySpellID(spellID)
    return function(button)
        if not _G.GameTooltip or not _G.GameTooltip.SetOwner then return end
        _G.GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if _G.GameTooltip.SetMountBySpellID then
            _G.GameTooltip:SetMountBySpellID(spellID)
        elseif _G.GameTooltip.SetSpellByID then
            _G.GameTooltip:SetSpellByID(spellID)
        end
        _G.GameTooltip:Show()
    end
end

---@return table<number, true>
function MountsDataText:GetUtilityMountIdSet()
    if not self.utilityMountIdCache then
        self.utilityMountIdCache = Tools.Generics.Cache.New("TwichUIMountsUtilityMountIdCache")
    end

    return self.utilityMountIdCache:get(function()
        local set = {}
        if not _G.C_MountJournal or not _G.C_MountJournal.GetMountFromSpell then
            return set
        end

        for _, spellID in ipairs(DEFAULT_UTILITY_MOUNT_SPELL_IDS) do
            local mountID = _G.C_MountJournal.GetMountFromSpell(spellID)
            if mountID then
                set[mountID] = true
            end
        end
        return set
    end)
end

---@class MountEntry
---@field name string
---@field spellID number
---@field icon any
---@field mountID number

---@return { utility: MountEntry[], favorite: MountEntry[] }
function MountsDataText:GetMountLists()
    if not self.mountsCache then
        self.mountsCache = Tools.Generics.Cache.New("TwichUIMountsMountListCache")
    end

    return self.mountsCache:get(function()
        local result = { utility = {}, favorite = {} }

        if not _G.C_MountJournal
            or not _G.C_MountJournal.GetNumMounts
            or not _G.C_MountJournal.GetDisplayedMountID
            or not _G.C_MountJournal.GetDisplayedMountInfo
            or not _G.C_MountJournal.GetIsFavorite then
            return result
        end

        local utilitySet = self:GetUtilityMountIdSet() or {}
        local numMounts = _G.C_MountJournal.GetNumMounts() or 0
        for displayIndex = 1, numMounts do
            local mountID = _G.C_MountJournal.GetDisplayedMountID(displayIndex)
            local isUtility = mountID and utilitySet[mountID]

            local isFavorite = false
            if not isUtility then
                isFavorite = _G.C_MountJournal.GetIsFavorite(displayIndex)
            end

            if isUtility or isFavorite then
                local creatureName, spellID, icon, _, _, _, _, _, _, _, isCollected, collectedMountID =
                    _G.C_MountJournal.GetDisplayedMountInfo(displayIndex)

                if isCollected and (collectedMountID or mountID) and creatureName and spellID then
                    local targetList = isUtility and result.utility or result.favorite
                    tinsert(targetList, {
                        name = creatureName,
                        spellID = spellID,
                        icon = icon,
                        mountID = collectedMountID or mountID,
                    })
                end
            end
        end

        local sortMode = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SORT_MODE) or SortMode
            .JOURNAL
        if sortMode and sortMode.id == SortMode.NAME.id then
            local function SortByName(a, b)
                return tostring(a.name or "") < tostring(b.name or "")
            end
            table.sort(result.favorite, SortByName)
            table.sort(result.utility, SortByName)
        end

        return result
    end)
end

---@return string
function MountsDataText:GetDisplayText()
    if not self.displayCache then
        self.displayCache = Tools.Generics.Cache.New("TwichUIMountsDataTextDisplayCache")
    end

    return self.displayCache:get(function()
        local colorMode = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.COLOR_MODE)
        local label = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.DISPLAY_TEXT) or "Mounts"

        return DataTexts:ColorTextByElvUISetting(colorMode, label, Module.CONFIGURATION.CUSTOM_COLOR)
    end)
end

function MountsDataText:UpdatePanelIcon(displayText)
    if not self.panel then return end
    local showIcon = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_ICON)
    local icon = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_TEXTURE)
        or "Interface\\Icons\\Ability_Mount_RidingHorse"
    local iconSize = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_SIZE) or 14

    local padding = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_PADDING)

    DataTexts:UpdateDatatextIcon(self.panel, showIcon, icon, iconSize, padding, displayText)
end

function MountsDataText:Refresh()
    if self.displayCache then
        self.displayCache:invalidate()
    end
    if self.mountsCache then
        self.mountsCache:invalidate()
    end
    if self.mountOptionsCache then
        self.mountOptionsCache:invalidate()
    end
    if self.panel and self.panel.text then
        local displayText = self:GetDisplayText()
        self.panel.text:SetText(displayText)
        self:UpdatePanelIcon(displayText)
    end
end

---@return table<number, string>
function MountsDataText:GetCollectedMountOptions()
    if not self.mountOptionsCache then
        self.mountOptionsCache = Tools.Generics.Cache.New("TwichUIMountsCollectedMountOptionsCache")
    end

    return self.mountOptionsCache:get(function()
        local values = { [0] = "None" }
        if not _G.C_MountJournal
            or not _G.C_MountJournal.GetNumMounts
            or not _G.C_MountJournal.GetDisplayedMountInfo then
            return values
        end

        local mounts = {}
        local numMounts = _G.C_MountJournal.GetNumMounts() or 0
        for displayIndex = 1, numMounts do
            local creatureName, _, icon, _, _, _, _, _, _, _, isCollected, mountID =
                _G.C_MountJournal.GetDisplayedMountInfo(displayIndex)

            if isCollected and mountID and creatureName then
                tinsert(mounts, { mountID = mountID, name = creatureName, icon = icon })
            end
        end

        table.sort(mounts, function(a, b)
            return tostring(a.name or "") < tostring(b.name or "")
        end)

        for _, m in ipairs(mounts) do
            if m.icon then
                values[m.mountID] = ("|T%s:14:14|t %s"):format(m.icon, m.name)
            else
                values[m.mountID] = m.name
            end
        end

        return values
    end)
end

local function IsFlyableHere()
    if _G.IsFlyableArea then
        return _G.IsFlyableArea() and true or false
    end
    return false
end

---@param mountID number|nil
---@return boolean
local function IsMountUsable(mountID)
    if not mountID or mountID == 0 then return false end
    if not _G.C_MountJournal or not _G.C_MountJournal.GetMountInfoByID then
        return false
    end
    local _, _, _, _, isUsable = _G.C_MountJournal.GetMountInfoByID(mountID)
    return isUsable and true or false
end

---@param mountID number|nil
local function SummonMountByID(mountID)
    if not mountID or mountID == 0 then return end
    if _G.C_MountJournal and _G.C_MountJournal.SummonByID then
        _G.C_MountJournal.SummonByID(mountID)
    end
end

function MountsDataText:SummonPreferredMount()
    local groundID = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.FAVORITE_GROUND_MOUNT_ID) or 0
    local flyingID = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.FAVORITE_FLYING_MOUNT_ID) or 0

    local flyable = IsFlyableHere()

    local primary = flyable and flyingID or groundID
    local fallback = flyable and groundID or flyingID

    if IsMountUsable(primary) then
        SummonMountByID(primary)
        return
    end
    if IsMountUsable(fallback) then
        SummonMountByID(fallback)
        return
    end
end

function MountsDataText:BuildMenu()
    if not self.menuList then
        self.menuList = {}
    end
    wipe(self.menuList)

    local TT = Tools.Text
    local CT = Tools.Colors

    local mounts = self:GetMountLists()
    local hideUnusable = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.HIDE_UNUSABLE)

    local function insert(item)
        tinsert(self.menuList, item)
    end

    local showFavorites = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_FAVORITES)
    if showFavorites then
        insert({
            text = "Favorite Mounts",
            isTitle = true,
            notClickable = true,
        })

        if mounts and mounts.favorite and #mounts.favorite > 0 then
            for _, mount in ipairs(mounts.favorite) do
                local _, _, _, _, isUsable = _G.C_MountJournal.GetMountInfoByID(mount.mountID)
                if not hideUnusable or isUsable then
                    local displayName = mount.name
                    if not isUsable then
                        displayName = TT.Color(CT.TWICH.TEXT_SECONDARY, displayName)
                    end

                    insert({
                        text = displayName,
                        icon = mount.icon,
                        notClickable = not isUsable,
                        func = function()
                            if _G.C_MountJournal and _G.C_MountJournal.SummonByID then
                                _G.C_MountJournal.SummonByID(mount.mountID)
                            end
                        end,
                        funcOnEnter = TooltipForMountBySpellID(mount.spellID),
                        funcOnLeave = TooltipHide,
                    })
                end
            end
        else
            insert({
                text = TT.Color(CT.TWICH.TEXT_SECONDARY, "No favorite mounts found"),
                isDescription = true,
                notClickable = true,
            })
        end
    end

    local showUtility = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_UTILITY)
    if showUtility then
        insert({
            text = "Utility Mounts",
            isTitle = true,
            notClickable = true,
        })

        if mounts and mounts.utility and #mounts.utility > 0 then
            for _, mount in ipairs(mounts.utility) do
                local _, _, _, _, isUsable = _G.C_MountJournal.GetMountInfoByID(mount.mountID)
                if not hideUnusable or isUsable then
                    local displayName = mount.name
                    if not isUsable then
                        displayName = TT.Color(CT.TWICH.TEXT_SECONDARY, displayName)
                    end

                    insert({
                        text = displayName,
                        icon = mount.icon,
                        notClickable = not isUsable,
                        func = function()
                            if _G.C_MountJournal and _G.C_MountJournal.SummonByID then
                                _G.C_MountJournal.SummonByID(mount.mountID)
                            end
                        end,
                        funcOnEnter = TooltipForMountBySpellID(mount.spellID),
                        funcOnLeave = TooltipHide,
                    })
                end
            end
        else
            insert({
                text = TT.Color(CT.TWICH.TEXT_SECONDARY, "No utility mounts found"),
                isDescription = true,
                notClickable = true,
            })
        end
    end

    local showSwitchFlightStyle = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION
        .SHOW_SWITCH_FLIGHT_STYLE)
    if showSwitchFlightStyle then
        insert({
            text = "Other",
            isTitle = true,
            notClickable = true,
        })

        insert({
            text = "Switch Flight Style",
            icon = "Interface\\Icons\\Ability_DragonRiding_DynamicFlight01",
            macro = "/use Switch Flight Style",
            funcOnEnter = function(btn)
                if not _G.GameTooltip then return end
                _G.GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                if _G.GameTooltip.SetSpellByID then
                    _G.GameTooltip:SetSpellByID(460002)
                end
                _G.GameTooltip:Show()
            end,
            funcOnLeave = TooltipHide,
        })
    end

    local hideTip = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.HIDE_TIP_TEXT)
    if not hideTip then
        insert({
            text = TT.Color(CT.TWICH.TEXT_SECONDARY, "Click a mount to summon"),
            isDescription = true,
            notClickable = true,
        })
    end
end

function MountsDataText:OnEvent(panel, event, ...)
    if not self.panel then
        self.panel = panel
    end

    Logger.Debug("MountsDataText: OnEvent triggered: " .. tostring(event))

    if event == "ELVUI_FORCE_UPDATE" then
        if self.displayCache then
            self.displayCache:invalidate()
        end
    end

    if event == "COMPANION_UPDATE"
        or event == "NEW_MOUNT_ADDED"
        or event == "MOUNT_JOURNAL_USABILITY_CHANGED"
        or event == "MOUNT_JOURNAL_SEARCH_UPDATED" then
        if self.mountsCache then
            self.mountsCache:invalidate()
        end
        if self.utilityMountIdCache then
            self.utilityMountIdCache:invalidate()
        end
        if self.mountOptionsCache then
            self.mountOptionsCache:invalidate()
        end
    end

    if self.panel and self.panel.text then
        local displayText = self:GetDisplayText()
        self.panel.text:SetText(displayText)
        self:UpdatePanelIcon(displayText)
    end
end

function MountsDataText:OnEnter(panel)
    if panel then
        self.panel = panel
    end
    if not self.panel then return end

    if self.panel.text then
        self:UpdatePanelIcon(self.panel.text:GetText())
    end

    local openOnHover = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.OPEN_MENU_ON_HOVER)
    if not openOnHover then
        return
    end

    self:BuildMenu()
    local instance = DataTexts.Menu:Acquire("twichui_mounts")
    DataTexts.Menu:Show(instance, self.panel, self.menuList)
end

function MountsDataText:OnClick(panel, button)
    local clickSummonEnabled = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.CLICK_SUMMON_ENABLED)
    if clickSummonEnabled then
        self:SummonPreferredMount()
        return
    end

    -- Legacy behavior (if user disables click-to-summon): allow click-to-toggle menu when hover open is disabled.
    local openOnHover = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.OPEN_MENU_ON_HOVER)
    if not openOnHover then
        self:BuildMenu()
        DataTexts.Menu:Toggle("twichui_mounts", panel, self.menuList)
    end
end

function MountsDataText:Enable()
    if Module:IsEnabled() then return end
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        Logger.Debug("Mounts datatext is already registered with ElvUI; skipping enable")
        return
    end

    -- Prime caches
    self:GetDisplayText()
    Module:Enable(nil)

    DataTexts:NewDataText(
        DATATEXT_NAME,
        "TwichUI: Mounts",
        { "PLAYER_ENTERING_WORLD", "COMPANION_UPDATE", "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED",
            "MOUNT_JOURNAL_SEARCH_UPDATED" },
        function(panel, event, ...) self:OnEvent(panel, event, ...) end,
        nil,
        function(panel, button) self:OnClick(panel, button) end,
        function(panel) self:OnEnter(panel) end,
        nil
    )

    Logger.Debug("Mounts datatext enabled")
end

function MountsDataText:Disable()
    Module:Disable()
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        DataTexts:RemoveDataText(DATATEXT_NAME)
    end

    Logger.Debug("Mounts datatext disabled")
    Configuration:PromptReloadUI()
end

function MountsDataText:OnInitialize()
    if Module:IsEnabled() then return end
    if Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end
