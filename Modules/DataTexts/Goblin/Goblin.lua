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
--- @field gph GoldPerHourData the current gold per hour data
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
        GOLD_DISPLAY_MODE = { key = "datatexts.goblin.goldDisplayMode", default = "full" },
        COLOR_MODE = { key = "datatexts.goblin.colorMode", default = DataTexts.ColorMode.ELVUI },
        CUSTOM_COLOR = { key = "datatexts.goblin.customColor", default = DataTexts.DefaultColor },
    }
)

---@alias AddOnEntryConfig { prettyName: string, enabledByDefault: boolean, iconTexture: string, fallbackIconTexture: string|nil, openFunc: function|nil }

---@class GoblinSupportedAddons <string, AddOnEntryConfig> the list of supported third-party addons for the Goblin datatext
GoblinDataText.SUPPORTED_ADDONS = {
    TradeSkillMaster = {
        prettyName = "TradeSkillMaster",
        enabledByDefault = false,
        iconTexture = "Interface\\AddOns\\TradeSkillMaster\\Media\\Logo",
        fallbackIconTexture = "Interface\\Icons\\INV_Misc_Coin_01",
        openFunc = ThirdPartyAPI.TSM.Open,
    },
    Journalator = {
        prettyName = "Journaltor",
        enabledByDefault = false,
        iconTexture = "Interface\\AddOns\\Journalator\\Images\\icon",
        fallbackIconTexture = "Interface\\Icons\\INV_Misc_Coin_01",
        openFunc = ThirdPartyAPI.Journalator.Open,
    },
    FarmHUD = {
        prettyName = "FarmHUD",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_Gathering_BioluminescentSpores_Small",
        fallbackIconTexture = nil,
        openFunc = ThirdPartyAPI.FarmHud.Open,
    },
    LootAppraiser = {
        prettyName = "LootAppraiser",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_Fishing_DragonIslesCoins_Gold",
        fallbackIconTexture = nil,
        openFunc = ThirdPartyAPI.LootAppraiser.Open,
    },
    Routes = {
        prettyName = "Routes",
        enabledByDefault = false,
        iconTexture = "Interface\\Icons\\INV_10_DungeonJewelry_Explorer_Trinket_1Compass_Color1",
        fallbackIconTexture = nil,
        openFunc = ThirdPartyAPI.Routes.Open,
    },
}

--- @param addonName string
--- @return ConfigEntry
function GoblinDataText:GetAddonConfigurationEntry(addonName)
    local uppercase = string.upper(addonName)
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
        local entry = GoblinDataText:GetAddonConfigurationEntry(addon.prettyName)
        local enabled = Configuration:GetProfileSettingByConfigEntry(entry)
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
        self.panel.text:SetText(self:GetDisplayText())
    end
end

function GoblinDataText:OnEnter()
    local DT = DataTexts:GetDatatextModule()
    local TT = Tools.Text
    local CT = Tools.Colors

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
        DT.tooltip:AddLine(TT.Color(CT.TWICH.TEXT_SECONDARY, "Shift-Click to display loot tracker."))
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

    panel.text:SetText(self:GetDisplayText())
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

        --- @param gphData GoldPerHourData
        local function GPHCallbackHandler(gphData)
            self.gph = gphData
        end
        self.gphUpdateCallbackId = LootMonitor.GoldPerHourTracker:RegisterCallback(GPHCallbackHandler)
    end
end

function GoblinDataText:GetDisplayText()
    return self.displayCache:get(function()
        local displayMode = Configuration:GetProfileSettingByConfigEntry(
            Module.CONFIGURATION.DISPLAY_MODE
        )
        local colorMode = Configuration:GetProfileSettingByConfigEntry(
            Module.CONFIGURATION.COLOR_MODE
        )

        -- default display
        if displayMode.id == GoblinDataText.DisplayModes.DEFAULT.id then
            return DataTexts:ColorTextByElvUISetting(colorMode, "Goblin", Module.CONFIGURATION.CUSTOM_COLOR)
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
            text = TT.Color(CT.TWICH.PRIMARY_ACCENT, "Professions"),
            isTitle = true,
            notClickable = true,
        })

        for _, p in ipairs(profs) do
            local iconTag = p.icon and TT.CreateIconStr(p.icon) or ""
            insert({
                text = iconTag .. p.name,
                func = function() OpenProfessionByIndex(p.idx) end,
            })
        end
    end

    -- Third-party addons
    local anyEnabled, addonConfigs = GetAddonConfgurations()
    if anyEnabled then
        -- header
        insert({
            text = TT.Color(CT.TWICH.PRIMARY_ACCENT, "Addons"),
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

                -- default to a space if no icon found to avoid layout issues
                local iconStr = " "
                if icon then
                    iconStr = TT.CreateIconStr(icon)
                end

                insert({
                    text = iconStr .. " " .. config.prettyName,
                    notCheckable = true,
                    func = config.openFunc
                })
            end
        end
    end
end

-- panel is the datatext frame; button is the mouse button name
function GoblinDataText:OnClick(panel, button)
    ---@type LootMonitorModule
    local LMM = T:GetModule("LootMonitor")

    -- holding shift; show loot tracker
    if IsShiftKeyDown() and LMM:IsEnabled() and LMM.GoldPerHourTracker:IsEnabled() then
        LMM.GoldPerHourFrame:Enable()
        return
    end

    -- holding control; toggle display mode
    if IsControlKeyDown() and LMM:IsEnabled() and LMM.GoldPerHourTracker:IsEnabled() then
        -- TODO
        return
    end

    -- regular click
    GoblinDataText:BuildClickMenu()
    DataTexts:DropDown(GoblinDataText.menuList, DataTexts.menuFrame, panel, 0, 2, "twichui_goblin")
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
