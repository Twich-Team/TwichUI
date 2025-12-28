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
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

--- @class PortalsDataText
--- @field displayCache GenericCache caching the display text
--- @field hearthstoneCache GenericCache caching available hearthstones
--- @field name string the name of the datatext
--- @field panel any the ElvUI datatext panel
--- @field menuList TwichUI_MenuItem[] the menu list for the datatext
--- @field clickButton Button|nil secure overlay button for favorite hearthstone
local PortalsDataText = DataTexts.Portals or {}
DataTexts.Portals = PortalsDataText
PortalsDataText.name = "TwichUI_Portals"

local Module = Tools.Generics.Module:New({
    ENABLED = { key = "datatexts.portals.enable", default = false, },
    COLOR_MODE = { key = "datatexts.portals.colorMode", default = DataTexts.ColorMode.ELVUI },
    CUSTOM_COLOR = { key = "datatexts.portals.customColor", default = DataTexts.DefaultColor },
    -- Default to the regular Hearthstone.
    FAVORITE_HEARTHSTONE_ID = { key = "datatexts.portals.favoriteHearthstoneId", default = 6948 },

    HIDE_TIP_TEXT = { key = "datatexts.portals.hideTipText", default = false },

})

local DATATEXT_NAME = "TwichUI_Portals"

-- Hearthstone IDs (toys and items)
local hearthstoneList = {
    6948,   -- Hearthstone
    110560, -- Garrison Hearthstone
    140192, -- Dalaran Hearthstone
    64488,  -- The Innkeeper's Daughter
    168907, -- Holographic Digitalization Hearthstone
    190196, -- Enlightened Hearthstone
    228940, -- Notorious Thread's Hearthstone
    200630, -- Ohn'ir Windsage's Hearthstone
    209035, -- Hearthstone of the Flame
    188952, -- Dominated Hearthstone
    172179, -- Eternal Traveler's Hearthstone
    163045, -- Headless Horseman's Hearthstone
    208704, -- Deepdweller's Earthen Hearthstone
    193588, -- Timewalker's Hearthstone
    182773, -- Necrolord Hearthstone
    162973, -- Greatfather Winter's Hearthstone
    236687, -- Explosive Hearthstone
    184353, -- Kyrian Hearthstone
    165802, -- Noble Gardener's Hearthstone
    165669, -- Lunar Elder's Hearthstone
    180290, -- Night Fae Hearthstone
    166746, -- Fire Eater's Hearthstone
    166747, -- Brewfest Reveler's Hearthstone
    165670, -- Peddlefeet's Lovely Hearthstone
    250411, -- Timerunner's Hearthstone
    183716, -- Venthyr Sinstone
    -- TWW S3
    246565, -- Cosmic Hearthstone
    245970, -- P.O.S.T. Master's Express Hearthstone
}

-- Optional quick-travel hearthstones to always show when available
local otherLocationHearthstoneList = {
    110560, -- Garrison Hearthstone
    140192, -- Dalaran Hearthstone
}

local hearthstoneIDs = {}
for _, id in ipairs(hearthstoneList) do
    hearthstoneIDs[id] = true
end

local function GetItemName(itemID)
    if not itemID then return nil end
    if _G.C_Item and _G.C_Item.GetItemNameByID then
        return _G.C_Item.GetItemNameByID(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        return (_G.C_Item.GetItemInfo(itemID))
    end
    return nil
end

local function GetItemIcon(itemID)
    if not itemID then return nil end
    if _G.C_Item and _G.C_Item.GetItemIconByID then
        return _G.C_Item.GetItemIconByID(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        return select(10, _G.C_Item.GetItemInfo(itemID))
    end
    return nil
end

local function GetItemCooldownSeconds(itemID)
    if not itemID then return 0 end

    local start, duration, enable
    if _G.C_Item and _G.C_Item.GetItemCooldown then
        start, duration, enable = _G.C_Item.GetItemCooldown(itemID)
    elseif _G.GetItemCooldown then
        start, duration, enable = _G.GetItemCooldown(itemID)
    end

    if not start or not duration or enable == 0 then
        return 0
    end

    local remaining = (start + duration) - (_G.GetTime and _G.GetTime() or 0)
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function FormatCooldownShort(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return nil end

    -- prefer coarse formatting
    if seconds >= 3600 then
        return string.format("%dh", math.ceil(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%ds", math.ceil(seconds))
    end
end

local function TooltipForItemByID(itemID)
    return function(button)
        if not _G.GameTooltip or not _G.GameTooltip.SetOwner then return end
        _G.GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if _G.PlayerHasToy and _G.PlayerHasToy(itemID) and _G.GameTooltip.SetToyByItemID then
            _G.GameTooltip:SetToyByItemID(itemID)
        elseif _G.GameTooltip.SetItemByID then
            _G.GameTooltip:SetItemByID(itemID)
        end
        _G.GameTooltip:Show()
    end
end

local function TooltipHide()
    if _G.GameTooltip and _G.GameTooltip.Hide then
        _G.GameTooltip:Hide()
    end
end

local function TeleportToHouse()
    if not (_G.C_Housing and _G.C_Housing.GetCurrentHouseInfo and _G.C_Housing.TeleportHome) then
        return
    end
    local houseInfo = _G.C_Housing.GetCurrentHouseInfo()
    if not houseInfo then return end
    pcall(_G.C_Housing.TeleportHome, houseInfo.neighborhoodGUID, houseInfo.houseGUID, houseInfo.plotID)
end

function PortalsDataText:GetConfiguration()
    return Module.CONFIGURATION
end

function PortalsDataText:Refresh()
    if self.displayCache then
        self.displayCache:invalidate()
    end
    if self.panel and self.panel.text then
        self.panel.text:SetText(self:GetDisplayText())
    end

    self:UpdateFavoriteClickButton()
end

function PortalsDataText:UpdateFavoriteClickButton()
    if not self.panel or not CreateFrame then return end
    if InCombatLockdown and InCombatLockdown() then return end

    if not self.clickButton then
        -- Secure overlay to allow click-to-cast favorite hearthstone.
        -- NOTE: must be secure to execute protected item/macro actions.
        local btn = CreateFrame("Button", nil, self.panel, "SecureActionButtonTemplate")
        btn:SetAllPoints(self.panel)
        btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        btn:SetFrameLevel((self.panel.GetFrameLevel and self.panel:GetFrameLevel() or 1) + 5)
        btn:EnableMouse(true)

        -- Preserve hover UX by forwarding hover events.
        btn:SetScript("OnEnter", function()
            self:OnEnter(self.panel)
        end)
        btn:SetScript("OnLeave", function() end)

        self.clickButton = btn
    elseif self.clickButton:GetParent() ~= self.panel then
        self.clickButton:SetParent(self.panel)
        self.clickButton:SetAllPoints(self.panel)
    end

    local available = self:GetAvailableHearthstones() or {}
    local favoriteID = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.FAVORITE_HEARTHSTONE_ID) or 0
    if favoriteID == 0 then favoriteID = nil end

    -- Default to regular hearthstone if favorite is unset.
    if not favoriteID then
        favoriteID = 6948
    end

    local btn = self.clickButton
    if not btn then return end

    -- Clear attributes first.
    btn:SetAttribute("type", nil)
    btn:SetAttribute("type1", nil)
    btn:SetAttribute("macrotext", nil)
    btn:SetAttribute("macrotext1", nil)

    -- Clear modifier overrides
    btn:SetAttribute("ctrl-type1", nil)
    btn:SetAttribute("ctrl-macrotext1", nil)

    if favoriteID and available[favoriteID] then
        btn:SetAttribute("type", "macro")

        -- Default click: favorite hearthstone
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext1", "/use item:" .. tostring(favoriteID))

        -- Ctrl+Click override: Dalaran Hearthstone (only if available)
        local dalaranID = 140192
        if available[dalaranID] then
            btn:SetAttribute("ctrl-type1", "macro")
            btn:SetAttribute("ctrl-macrotext1", "/use item:" .. tostring(dalaranID))
        end
    end
end

function PortalsDataText:GetAvailableHearthstones()
    if not self.hearthstoneCache then
        self.hearthstoneCache = Tools.Generics.Cache.New("TwichUIPortalsHearthstoneCache")
    end

    return self.hearthstoneCache:get(function()
        local result = {}

        -- Toys / learned hearthstones
        if _G.PlayerHasToy and _G.C_ToyBox and _G.C_ToyBox.IsToyUsable then
            for _, itemID in ipairs(hearthstoneList) do
                if _G.PlayerHasToy(itemID) and _G.C_ToyBox.IsToyUsable(itemID) then
                    local name = GetItemName(itemID)
                    if name then
                        result[itemID] = name
                    end
                end
            end
        end

        -- Items in bags (covers normal Hearthstone, etc.)
        if _G.C_Container and _G.NUM_BAG_SLOTS then
            for bag = 0, _G.NUM_BAG_SLOTS do
                local slots = _G.C_Container.GetContainerNumSlots(bag)
                for slot = 1, slots do
                    local itemID = _G.C_Container.GetContainerItemID(bag, slot)
                    if itemID and hearthstoneIDs[itemID] then
                        local name = GetItemName(itemID)
                        if name then
                            result[itemID] = name
                        end
                    end
                end
            end
        end

        return result
    end)
end

function PortalsDataText:BuildMenu()
    local TT = Tools.Text
    local CT = Tools.Colors

    if not self.menuList then
        self.menuList = {}
    end
    wipe(self.menuList)

    local function insert(item)
        table.insert(self.menuList, item)
    end

    insert({
        text = "Hearthstones",
        isTitle = true,
        notClickable = true,
    })

    local available = self:GetAvailableHearthstones()

    local favoriteID = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.FAVORITE_HEARTHSTONE_ID) or 0
    if favoriteID == 0 then favoriteID = nil end

    local function AddHearthstoneEntry(itemID)
        if not itemID then return end
        local itemName = available[itemID]
        if not itemName then return end

        local displayName = itemName

        local cdSeconds = GetItemCooldownSeconds(itemID)
        local cdText = FormatCooldownShort(cdSeconds)
        local notClickable = false

        if cdText then
            if TT and TT.Color and CT and CT.TWICH and CT.TWICH.TEXT_SECONDARY then
                displayName = TT.Color(CT.TWICH.TEXT_SECONDARY, string.format("%s (%s)", displayName, cdText))
            else
                displayName = string.format("%s (%s)", displayName, cdText)
            end
            notClickable = true
        end

        insert({
            text = displayName,
            icon = GetItemIcon(itemID),
            notClickable = notClickable,
            -- Match deprecated working behavior: macro uses item:<id> even for toys.
            macro = "/use item:" .. tostring(itemID),
            funcOnEnter = TooltipForItemByID(itemID),
            funcOnLeave = TooltipHide,
        })
    end

    -- Favorite first, if available
    if favoriteID and available[favoriteID] then
        AddHearthstoneEntry(favoriteID)
    end

    -- Other quick-location hearthstones
    for _, itemID in ipairs(otherLocationHearthstoneList) do
        if itemID ~= favoriteID then
            AddHearthstoneEntry(itemID)
        end
    end

    -- Safety: if nothing at all
    if #self.menuList == 1 then
        insert({
            text = (TT and TT.Color and CT and CT.TWICH and CT.TWICH.TEXT_SECONDARY)
                and TT.Color(CT.TWICH.TEXT_SECONDARY, "No hearthstones found")
                or "No hearthstones found",
            isDescription = true,
            notClickable = true,
        })
    end

    -- Optional: Housing teleport
    local housing = _G.C_Housing
    local atHome = housing and housing.IsInsideHouseOrPlot and housing.IsInsideHouseOrPlot()
    if housing and not atHome and housing.GetCurrentHouseInfo and housing.TeleportHome then
        insert({
            text = " ",
            isTitle = true,
            notClickable = true,
        })

        insert({
            text = "Teleport to House",
            icon = "Interface\\Icons\\Creatureportrait_Mageportal_Undercity",
            func = TeleportToHouse,
        })
    end

    -- Footer tip (optional)
    local hideTip = Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.HIDE_TIP_TEXT)
    if not hideTip then
        local tip = "Click datatext: favorite hearthstone\nCtrl+Click: Dalaran hearthstone"
        insert({
            text = (TT and TT.Color and CT and CT.TWICH and CT.TWICH.TEXT_SECONDARY)
                and TT.Color(CT.TWICH.TEXT_SECONDARY, tip)
                or tip,
            isDescription = true,
            notClickable = true,
        })
    end
end

function PortalsDataText:OnEvent(panel, event, ...)
    if not self.panel then
        self.panel = panel
    end

    Logger.Debug("PortalsDataText: OnEvent triggered: " .. tostring(event))

    if event == "ELVUI_FORCE_UPDATE" then
        if self.displayCache then
            self.displayCache:invalidate()
        end
    end

    if event == "TOYS_UPDATED" or event == "BAG_UPDATE_DELAYED" then
        if self.hearthstoneCache then
            self.hearthstoneCache:invalidate()
        end
    end

    if self.panel then
        self.panel.text:SetText(self:GetDisplayText())
    end

    self:UpdateFavoriteClickButton()
end

function PortalsDataText:OnEnter(panel)
    if panel then
        self.panel = panel
    end

    if not self.panel then
        return
    end

    self:BuildMenu()
    local instance = DataTexts.Menu:Acquire("twichui_portals")
    DataTexts.Menu:Show(instance, self.panel, self.menuList)

    self:UpdateFavoriteClickButton()
end

function PortalsDataText:Enable()
    if Module:IsEnabled() then return end
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        Logger.Debug("Portals datatext is already registered with ElvUI; skipping enable")
        return
    end

    self:GetDisplayText() -- calling once to build cache

    Module:Enable(nil)

    DataTexts:NewDataText(
        DATATEXT_NAME,
        "TwichUI: Portals",
        { "PLAYER_ENTERING_WORLD", "TOYS_UPDATED", "BAG_UPDATE_DELAYED" }, -- events
        function(panel, event, ...) self:OnEvent(panel, event, ...) end,   -- onEvent
        nil,                                                               -- onUpdate (bind self)
        nil,                                                               --onClick (handled by secure overlay)
        function(panel) self:OnEnter(panel) end,                           --onEnter
        nil                                                                --onLeave
    )

    Logger.Debug("Portals datatext enabled")
end

function PortalsDataText:Disable()
    Module:Disable()
    if DataTexts:IsDataTextRegistered(DATATEXT_NAME) then
        DataTexts:RemoveDataText(DATATEXT_NAME)
    end

    Logger.Debug("Portals datatext disabled")
end

function PortalsDataText:OnInitialize()
    if Module:IsEnabled() then return end
    if Configuration:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ENABLED) then
        self:Enable()
    end
end

function PortalsDataText:GetDisplayText()
    if not self.displayCache then
        self.displayCache = Tools.Generics.Cache.New("TwichUIPortalsDataTextDisplayCache")
    end

    return self.displayCache:get(function()
        local colorMode = Configuration:GetProfileSettingByConfigEntry(
            Module.CONFIGURATION.COLOR_MODE
        )

        return DataTexts:ColorTextByElvUISetting(colorMode, "Portals", Module.CONFIGURATION.CUSTOM_COLOR)
    end)
end
