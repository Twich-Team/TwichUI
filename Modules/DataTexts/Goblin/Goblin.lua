local T = unpack(Twich)

--- @type DataTextsModule
local DataTexts = T:GetModule("DataTexts")
--- @type ToolsModule
local Tools = T:GetModule("Tools")
--- @type ConfigurationModule
local Configuration = T:GetModule("Configuration")
--- @type LoggerModule
local Logger = T:GetModule("Logger")
--- @type ThirdPartyAPIModule
local ThirdPartyAPI = T:GetModule("ThirdPartyAPI")

--- registering the submobule with the parent datatext module
--- @class GoblinDataText
--- @field displayCache GenericCache cache for the display text
--- @field tokenPrice GenericCache cache for the token price
--- @field playerProfessionsCache GenericCache cache for the player professions
--- @field initialized boolean whether the datatext has been initialized
--- @field panel any the ElvUI datatext panel
--- @field accountMoney table the account gold statistics.
--- @field moneyUpdateCallbackId integer the ID of the registered money update callback
--- @field gphUpdateCallbackId integer the ID of the registered GPH update callback
--- @field lootMonitorCallbackId integer|nil the ID of the registered LootMonitor callback (used for after-loot pulse)
--- @field gph GoldPerHourData the current gold per hour data
--- @field gphDisplayOverride boolean|nil when true, forces the datatext to display GPH
--- @field gphPulseTimer any|nil C_Timer timer handle for temporary GPH display
--- @field gphPulseActive boolean|nil when true, temporarily displays GPH after loot
--- @field menuList table the click menu list
local GoblinDataText = DataTexts.Goblin or {}
DataTexts.Goblin = GoblinDataText

GoblinDataText.DisplayModes = {
    DEFAULT = { id = "default", name = "Default ('Goblin')" },
    ACCOUNT_GOLD = { id = "accountGold", name = "Account Gold" },
    CHARACTER_GOLD = { id = "characterGold", name = "Character Gold" },
    GPH = {
        id = "gph",
        name = "Gold Per Hour",
        hidden = function()
            ---@type LootMonitorModule
            local LootMonitor = T:GetModule("LootMonitor")
            return not LootMonitor:IsEnabled() and not LootMonitor.GoldPerHourTracker:IsEnabled()
        end
    }
}

local UnitName = UnitName
local UnitClass = UnitClass
local GetWoWTokenPrice = C_WowTokenPublic.GetCurrentMarketPrice
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local GetProfessionInfo = GetProfessionInfo
local CastSpell = CastSpell


--- the module for the datatext
local Module = Tools.Generics.Module:New(
    {
        ENABLED = { key = "datatexts.goblin.enable", default = false },
        DISPLAY_MODE = { key = "datatexts.goblin.displayMode", default = GoblinDataText.DisplayModes.DEFAULT },

        DISPLAY_TEXT = { key = "datatexts.goblin.displayText", default = "Goblin" },
        SHOW_ICON = { key = "datatexts.goblin.showIcon", default = false },
        ICON_TEXTURE = { key = "datatexts.goblin.iconTexture", default = "Interface\\Icons\\INV_Misc_Coin_01" },
        ICON_SIZE = { key = "datatexts.goblin.iconSize", default = 14 },
        ICON_PADDING = { key = "datatexts.goblin.iconPadding", default = 2 },

        GOLD_DISPLAY_MODE = { key = "datatexts.goblin.goldDisplayMode", default = "full" },
        COLOR_MODE = { key = "datatexts.goblin.colorMode", default = DataTexts.ColorMode.ELVUI },
        CUSTOM_COLOR = { key = "datatexts.goblin.customColor", default = DataTexts.DefaultColor },

        -- Optional: briefly show GPH after loot, then return to configured display.
        -- Only applies when configured display is NOT GPH and user has not overridden to GPH.
        SHOW_GPH_AFTER_LOOT = { key = "datatexts.goblin.gphAfterLoot.enabled", default = false },
        GPH_AFTER_LOOT_DURATION = { key = "datatexts.goblin.gphAfterLoot.durationSeconds", default = 6 },
    }
)

---@alias AddOnEntryConfig { prettyName: string, enabledByDefault: boolean, iconTexture: string, fallbackIconTexture: string|nil, openFunc: function|nil, availableFunc: function|nil }

---@class GoblinSupportedAddons <string, AddOnEntryConfig> the list of supported third-party addons for the Goblin datatext
GoblinDataText.SUPPORTED_ADDONS = {
    TradeSkillMaster = {
        prettyName = "TradeSkillMaster",
        enabledByDefault = false,
        iconTexture = "Interface\\AddOns\\TradeSkillMaster\\Media\\Logo",
        fallbackIconTexture = "Interface\\Icons\\INV_Misc_Coin_01",
        openFunc = function() ThirdPartyAPI.TSM:Open() end,
    },
    Journalator = {
        prettyName = "Journalator",
        enabledByDefault = false,
        iconTexture = "Interface\\AddOns\\Journalator\\Images\\icon",
        fallbackIconTexture = "Interface\\Icons\\INV_Misc_Coin_01",
        openFunc = function() ThirdPartyAPI.Journalator:Open() end,
    },
    FarmHUD = {
        prettyName = "FarmHUD",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_Gathering_BioluminescentSpores_Small",
        fallbackIconTexture = nil,
        openFunc = function() ThirdPartyAPI.FarmHud:Open() end,
    },
    LootAppraiser = {
        prettyName = "LootAppraiser",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_Fishing_DragonIslesCoins_Gold",
        fallbackIconTexture = nil,
        openFunc = function() ThirdPartyAPI.LootAppraiser:Open() end,
    },
    Routes = {
        prettyName = "Routes",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_DungeonJewelry_Explorer_Trinket_1Compass_Color1",
        fallbackIconTexture = nil,
        openFunc = function() ThirdPartyAPI.Routes:Open() end,
    },
}

--- @param addon GoblinSupportedAddons
--- @return ConfigEntry
function GoblinDataText:GetAddonConfigurationEntry(addon)
    local uppercase = string.upper(addon.prettyName)
    return Module.CONFIGURATION["SHOW_ADDON_" .. uppercase]
end

do
    --- @param addon AddOnEntryConfig
    local function AddAddonDisplayConfiguration(addon)
        local uppercase = string.upper(addon.prettyName)
        local lowercase = string.lower(addon.prettyName)
        local default = addon.enabledByDefault or false
        Module.CONFIGURATION["SHOW_ADDON_" .. uppercase] = {
            key = "datatexts.goblin.showAddon." .. lowercase,
            default = default,
        }
    end

    for _, addon in pairs(GoblinDataText.SUPPORTED_ADDONS) do
        AddAddonDisplayConfiguration(addon)
    end
end

---@return boolean whether at least one supported addon is enabled in the configuration
---@return table<string, BuiltAddonConfig> table table mapping addon names to their enabled/disabled status
local function GetAddonConfgurations()
    local config = {}
    local anyEnabled = false
    for _, addon in pairs(GoblinDataText.SUPPORTED_ADDONS) do
        local entry = GoblinDataText:GetAddonConfigurationEntry(addon)
        local enabled = Configuration:GetProfileSettingByConfigEntry(entry)
        local available = (type(addon.availableFunc) ~= "function") or addon.availableFunc()

        -- Only consider an addon enabled if it's both enabled in settings and available.
        enabled = enabled and available
        if enabled then
            anyEnabled = true
        end

        ---@class BuiltAddonConfig
        local obj = {
            prettyName = addon.prettyName,
            enabled = enabled,
            iconTexture = addon.iconTexture,
            fallbackIconTexture = addon.fallbackIconTexture,
            openFunc = addon.openFunc,
        }

        config[addon.prettyName] = obj
    end
    return anyEnabled, config
end

---
function GoblinDataText:GetPlayerProfessions()
    if not self.playerProfessionsCache then
        self.playerProfessionsCache = Tools.Generics.Cache.New("TwichUIGoblinPlayerProfessionsCache")
    end

    return self.playerProfessionsCache:get(function()
        local profs = {}

        -- Get all profession indices (primary, secondary, archaeology, fishing, cooking)
        local prof1, prof2, arch, fish, cook = GetProfessions()
        local indices = { prof1, prof2, arch, fish, cook }

        -- Build profession data for each valid index
        for _, idx in ipairs(indices) do
            if idx then
                local name, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset, skillLine = GetProfessionInfo(
                    idx)
                if name and skillLine then
                    table.insert(profs, {
                        name = name,
                        icon = icon,
                        skillLine = skillLine,
                        idx = idx,
                    })
                end
            end
        end

        return profs
    end)
end

function GoblinDataText:GetConfiguration()
    return Module.CONFIGURATION
end

local DATATEXT_NAME = "TwichUI_Goblin"

function GoblinDataText:Refresh()
    self.displayCache:invalidate()
    if self.panel then
        local displayText = self:GetDisplayText()
        self.panel.text:SetText(displayText)
        self:UpdatePanelIcon(displayText)
    end
end

function GoblinDataText:UpdatePanelIcon(displayText)
    if not self.panel then return end
    local showIcon = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_ICON)
    local icon = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_TEXTURE) or
        "Interface\\Icons\\INV_Misc_Coin_01"
    local iconSize = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_SIZE) or 14
    local padding = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ICON_PADDING)
    DataTexts:UpdateDatatextIcon(self.panel, showIcon, icon, iconSize, padding, displayText)
end

function GoblinDataText:OnEnter()
    local DT = DataTexts:GetDatatextModule()
    local TT = Tools.Text
    local CT = Tools.Colors

    if self.panel and self.panel.text then
        self:UpdatePanelIcon(self.panel.text:GetText())
    end

    DT.tooltip:ClearLines()

    DT.tooltip:AddDoubleLine(
        TT.Color(CT.TWICH.PRIMARY_ACCENT, "Account Total:"),
        TT.Color(CT.WHITE, TT.FormatCopper(self.accountMoney.total or 0))
    )

    DT.tooltip:AddDoubleLine(
        TT.Color(CT.TWICH.PRIMARY_ACCENT, "In Warbank:"),
        TT.Color(CT.WHITE, TT.FormatCopper(self.accountMoney.warbank or 0))
    )

    DT.tooltip:AddLine(" ")
    DT.tooltip:AddLine("Character")

    -- add current character first
    local classIconSize = 18
    local name, className, classFile = UnitName("player"), UnitClass("player")
    local texture = Tools.Textures:GetClassTextureString(classFile, classIconSize)

    DT.tooltip:AddDoubleLine(
        texture .. " " .. TT.ColorByClass(classFile, name),
        TT.Color(CT.WHITE, TT.FormatCopperShort(self.accountMoney.character or 0))
    )

    for _, char in pairs(Tools.Money:GetTopCharactersByGold(4)) do
        DT.tooltip:AddDoubleLine(
            Tools.Textures:GetClassTextureString(char.class, classIconSize) .. " " ..
            Tools.Text.ColorByClass(char.class, char.name .. "-" .. char.realm),
            Tools.Text.Color(Tools.Colors.WHITE, Tools.Text.FormatCopperShort(char.copper or 0)
            ))
    end

    DT.tooltip:AddLine(" ")
    DT.tooltip:AddDoubleLine(
        TT.Color(CT.TWICH.SECONDARY_ACCENT, "Token:"),
        TT.Color(CT.WHITE, TT.FormatCopperShort(self:GetTokenPrice() or 0))
    )

    -- if GPH is enabled,
    ---@type LootMonitorModule
    local LootMonitor = T:GetModule("LootMonitor")
    if LootMonitor:IsEnabled() and LootMonitor.GoldPerHourTracker:IsEnabled() then
        if self.gph then
            DT.tooltip:AddLine(" ")

            DT.tooltip:AddDoubleLine(
                TT.Color(CT.TWICH.SECONDARY_ACCENT, "Session GPH (last " .. floor(self.gph.elapsedTime / 60) .. " min):"),
                TT.Color(CT.WHITE, TT.FormatCopperShort(self.gph.goldPerHour or 0))
            )
        end

        DT.tooltip:AddLine(" ")
        if LootMonitor.GoldPerHourFrame and LootMonitor.GoldPerHourFrame.Enable then
            DT.tooltip:AddLine(TT.Color(CT.TWICH.TEXT_SECONDARY, "Shift-Click to display loot tracker."))
        end
        DT.tooltip:AddLine(TT.Color(CT.TWICH.TEXT_SECONDARY,
            "Ctrl-Click to toggle between GPH and configured display modes."))
    end

    DT.tooltip:AddLine(" ")
    DT.tooltip:AddLine(TT.Color(CT.TWICH.TEXT_SECONDARY, "Click to show professions and gold-making addons."))


    DT.tooltip:Show()
end

--- Handles events coming in from the datatext registration
function GoblinDataText:OnEvent(panel, event, ...)
    if not self.panel then
        self.panel = panel
    end

    Logger.Debug("GoblinDataText: OnEvent triggered: " .. tostring(event))

    if event == "TWICH_GOLD_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ELVUI_FORCE_UPDATE" then
        self.accountMoney = Tools.Money:GetAccountGoldStats()
        self.displayCache:invalidate()
    end

    if self.panel then
        local displayText = self:GetDisplayText()
        self.panel.text:SetText(displayText)
        self:UpdatePanelIcon(displayText)
    end
end

local function FormatCopper(copper)
    local goldDisplayMode = Configuration:GetProfileSettingByConfigEntry(
        Module.CONFIGURATION.GOLD_DISPLAY_MODE
    )

    if goldDisplayMode == "full" then
        return Tools.Text.FormatCopper(copper)
    else
        return Tools.Text.FormatCopperShort(copper)
    end
end

function GoblinDataText:GetTokenPrice()
    return self.tokenPrice:get(function()
        return GetWoWTokenPrice() or 0
    end)
end

function GoblinDataText:LazyLoadGPHCallback()
    if not self.gphUpdateCallbackId then
        ---@type LootMonitorModule
        local LootMonitor = T:GetModule("LootMonitor")

        local function CancelPulseTimer()
            if self.gphPulseTimer then
                self.gphPulseTimer:Cancel()
                self.gphPulseTimer = nil
            end
        end

        local function IsGPHAvailable()
            return LootMonitor:IsEnabled() and LootMonitor.GoldPerHourTracker and
                LootMonitor.GoldPerHourTracker:IsEnabled()
        end

        local function GetConfiguredDisplayModeId()
            local mode = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.DISPLAY_MODE)
            return mode and mode.id
        end

        local function IsEffectiveDisplayGPH()
            if self.gphDisplayOverride then return true end
            if self.gphPulseActive then return true end
            return GetConfiguredDisplayModeId() == GoblinDataText.DisplayModes.GPH.id
        end

        local function StartGPHPulseIfConfigured()
            if not IsGPHAvailable() then return end
            if self.gphDisplayOverride then return end

            local configuredId = GetConfiguredDisplayModeId()
            if configuredId == GoblinDataText.DisplayModes.GPH.id then
                return
            end

            if not Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.SHOW_GPH_AFTER_LOOT) then
                return
            end

            local duration = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.GPH_AFTER_LOOT_DURATION) or
                0
            if duration <= 0 then return end

            self.gphPulseActive = true
            CancelPulseTimer()
            self.gphPulseTimer = C_Timer.NewTimer(duration, function()
                self.gphPulseActive = false
                self.gphPulseTimer = nil
                if self.panel then
                    self:Refresh()
                end
            end)
        end

        -- Register a LootMonitor callback so we can reliably detect real loot/money events.
        -- This avoids false triggers from GPH ticker recalculations or sliding-window trimming.
        if not self.lootMonitorCallbackId and LootMonitor.GetCallbackHandler then
            local handler = LootMonitor:GetCallbackHandler()
            if handler and handler.Register then
                self.lootMonitorCallbackId = handler:Register(function(event, _)
                    if event == LootMonitor.EVENTS.LOOT_VALUATED or event == LootMonitor.EVENTS.MONEY_RECEIVED then
                        StartGPHPulseIfConfigured()

                        -- show GPH immediately (value may update a moment later via GPH callback)
                        if self.panel and self.gphPulseActive then
                            self:Refresh()
                        end
                    end
                end)
            end
        end

        --- @param gphData GoldPerHourData
        local function GPHCallbackHandler(gphData)
            self.gph = gphData

            -- If we're currently showing GPH (configured, overridden, or pulsing), refresh the display.
            if self.panel and IsEffectiveDisplayGPH() then
                self:Refresh()
            end
        end
        self.gphUpdateCallbackId = LootMonitor.GoldPerHourTracker:RegisterCallback(GPHCallbackHandler)
    end
end

function GoblinDataText:GetDisplayText()
    return self.displayCache:get(function()
        local configuredMode = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.DISPLAY_MODE)
        local displayMode = configuredMode
        local colorMode = Configuration:GetProfileSettingByConfigEntry(
            Module.CONFIGURATION.COLOR_MODE
        )


        -- Manual override (Ctrl-Click) and temporary pulse (after loot) force GPH display.
        if self.gphDisplayOverride or self.gphPulseActive then
            displayMode = GoblinDataText.DisplayModes.GPH
        end

        -- default display
        if displayMode.id == GoblinDataText.DisplayModes.DEFAULT.id then
            local label = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.DISPLAY_TEXT) or "Goblin"
            return DataTexts:ColorTextByElvUISetting(colorMode, label, Module.CONFIGURATION.CUSTOM_COLOR)
        end

        -- character gold
        if displayMode.id == GoblinDataText.DisplayModes.CHARACTER_GOLD.id then
            return FormatCopper(self.accountMoney.character or 0)
        end

        -- account gold
        if displayMode.id == GoblinDataText.DisplayModes.ACCOUNT_GOLD.id then
            return FormatCopper(self.accountMoney.total or 0)
        end

        -- gold per hour
        if displayMode.id == GoblinDataText.DisplayModes.GPH.id then
            self:LazyLoadGPHCallback()
            return FormatCopper(self.gph and self.gph.goldPerHour or 0)
        end

        -- fallback
        return "Goblin"
    end)
end

local function OpenProfessionByIndex(idx)
    if not idx then return end

    local name, icon, skillLevel, maxSkillLevel, numAbilities, spellOffset = GetProfessionInfo(idx)
    if spellOffset and numAbilities and numAbilities > 0 then
        CastSpell(spellOffset + 1, "spell")
    end
end

function GoblinDataText:BuildClickMenu()
    local TT = Tools.Text
    local CT = Tools.Colors

    if not self.menuList then
        self.menuList = {}
    end
    wipe(self.menuList)

    local function insert(data)
        tinsert(self.menuList, data)
    end

    -- Display player professions
    local profs = self:GetPlayerProfessions()
    if profs and #profs > 0 then
        -- header
        insert({
            text = "Professions",
            isTitle = true,
            notClickable = true,
        })

        for _, p in ipairs(profs) do
            insert({
                icon = p.icon,
                text = p.name,
                func = function() OpenProfessionByIndex(p.idx) end,
            })
        end
    end

    -- Third-party addons
    local anyEnabled, addonConfigs = GetAddonConfgurations()
    if anyEnabled then
        -- header
        insert({
            text = "Addons",
            isTitle = true,
            notClickable = true,
        })

        for addonName, config in pairs(addonConfigs) do
            if config.enabled then
                -- resolve icon based on availability and fallbacks
                local icon = nil
                if config.fallbackIconTexture then
                    icon = TT:ResolveIconPath(config.iconTexture, config.fallbackIconTexture)
                else
                    icon = config.iconTexture
                end

                insert({
                    icon = icon,
                    text = config.prettyName,
                    notCheckable = true,
                    func = config.openFunc
                })
            end
        end
    end

    -- Fallback: avoid showing an empty menu frame
    if #self.menuList == 0 then
        insert({
            text = TT.Color(CT.TWICH.PRIMARY_ACCENT, "Menu"),
            isTitle = true,
            notClickable = true,
        })
        insert({
            text = TT.Color(CT.TWICH.TEXT_SECONDARY, "No entries available."),
            isDescription = true,
            notClickable = true,
        })
    end
end

-- panel is the datatext frame; button is the mouse button name
function GoblinDataText:OnClick(panel, button)
    ---@type LootMonitorModule
    local LMM = T:GetModule("LootMonitor")

    -- holding shift; show loot tracker
    if IsShiftKeyDown() and LMM:IsEnabled() and LMM.GoldPerHourTracker:IsEnabled() and LMM.GoldPerHourFrame and LMM.GoldPerHourFrame.Enable then
        LMM.GoldPerHourFrame:Enable()
        return
    end

    -- holding control; toggle display mode
    if IsControlKeyDown() and LMM:IsEnabled() and LMM.GoldPerHourTracker:IsEnabled() then
        -- Toggle manual override between configured display and GPH.
        self.gphDisplayOverride = not self.gphDisplayOverride

        -- Cancel any active pulse when explicitly toggling.
        if self.gphPulseTimer then
            self.gphPulseTimer:Cancel()
            self.gphPulseTimer = nil
        end
        self.gphPulseActive = false

        self:Refresh()
        return
    end

    -- regular click
    GoblinDataText:BuildClickMenu()
    DataTexts.Menu:Toggle("twichui_goblin", panel, GoblinDataText.menuList)
end

function GoblinDataText:OnEnable()
    if not self.initialized then
        self.displayCache = Tools.Generics.Cache.New("GoblinDataTextDisplay")
        self.moneyUpdateCallbackId = Tools.Money:RegisterGoldUpdateCallback(function()
            self:OnEvent(self.panel, "TWICH_GOLD_UPDATE")
        end)
        self.tokenPrice = Tools.Generics.Cache.New("GoblinTokenPriceCache")
        self:LazyLoadGPHCallback()
        self.initialized = true
    end

    -- at this point, it is assumed that the datatext is not already registered with ElvUI
    DataTexts:NewDataText(
        DATATEXT_NAME,
        "TwichUI: Goblin",
        { "PLAYER_ENTERING_WORLD" },                                               -- events
        function(panel, event, ...) GoblinDataText:OnEvent(panel, event, ...) end, -- onEvent (bind self)
        nil,                                                                       -- onUpdate
        function(panel, button) GoblinDataText:OnClick(panel, button) end,         -- onClick
        function() self:OnEnter() end,                                             -- onEnter
        nil                                                                        -- onLeave
    )
end

function GoblinDataText:Enable()
    if Module:IsEnabled() then return end
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        Logger.Debug("Goblin datatext is already registered with ElvUI; skipping enable")
        return
    end
    -- Enable the module (no frame events used here) then perform registration
    Module:Enable(nil)
    self:OnEnable()
    Logger.Debug("Goblin datatext enabled")
end

function GoblinDataText:Disable()
    Module:Disable()
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        DataTexts:RemoveDataText(DATATEXT_NAME)
    end

    if self.moneyUpdateCallbackId then
        Tools.Money:UnregisterGoldUpdateCallback(self.moneyUpdateCallbackId)
        self.moneyUpdateCallbackId = nil
    end

    if self.gphUpdateCallbackId then
        ---@type LootMonitorModule
        local LootMonitor = T:GetModule("LootMonitor")
        LootMonitor.GoldPerHourTracker:UnregisterCallback(self.gphUpdateCallbackId)
        self.gphUpdateCallbackId = nil
    end

    if self.lootMonitorCallbackId then
        ---@type LootMonitorModule
        local LootMonitor = T:GetModule("LootMonitor")
        if LootMonitor and LootMonitor.GetCallbackHandler then
            local handler = LootMonitor:GetCallbackHandler()
            if handler and handler.Unregister then
                handler:Unregister(self.lootMonitorCallbackId)
            end
        end
        self.lootMonitorCallbackId = nil
    end


    Logger.Debug("Goblin datatext disabled")

    -- Prompt user to reload UI to fully apply removal.
    Configuration:PromptReloadUI()
end

function GoblinDataText:OnInitialize()
    if Module:IsEnabled() then return end

    if Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end
