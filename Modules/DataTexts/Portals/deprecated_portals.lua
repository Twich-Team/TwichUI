local E, L, V, P, G = unpack(ElvUI)

local twichui = TwichUI
local twichui_utility = TwichUI_Utility
local Logger = TwichUI.Logger
local DataTextAPI = TwichUI.DataTextAPI
local CacheAPI = TwichUI.CacheAPI

local menuList = {}

-- 1. Define hearthstones: list + lookup
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
    -- TWW S3 --
    246565, -- Cosmic Hearthstone
    245970, -- P.O.S.T. Master's Express Hearthstone
}

local otherLocationHearthstoneList = {
    110560, -- Garrison Hearthstone
    140192, -- Dalaran Hearthstone
}

local hearthstoneIDs = {}
for _, id in ipairs(hearthstoneList) do
    hearthstoneIDs[id] = true
end

local hearthstoneCache = CacheAPI.New("HearthstoneCache")

-- map of hearthstones the player has: [itemID] = localizedName
function twichui:GetAvailableHearthstones()
    local cache = hearthstoneCache:get(function()
        local result = {}

        -- Toys / learned hearthstones
        if PlayerHasToy and C_ToyBox then
            for _, itemID in ipairs(hearthstoneList) do
                if PlayerHasToy(itemID) and C_ToyBox.IsToyUsable(itemID) then
                    local name = C_Item.GetItemInfo(itemID)
                    if name then
                        result[itemID] = name
                    end
                end
            end
        end

        -- Items in bags (covers normal Hearthstone, etc.)
        for bag = 0, NUM_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID and hearthstoneIDs[itemID] then
                    local name = C_Item.GetItemInfo(itemID)
                    if name then
                        result[itemID] = name
                    end
                end
            end
        end

        return result
    end)

    return cache
end

local function TeleportToHouse()
    local houseInfo = C_Housing.GetCurrentHouseInfo()
    C_Housing.TeleportHome(houseInfo.neighborhoodGUID, houseInfo.houseGUID, houseInfo.plotID)
end

local function LeaveHouse()
    C_Housing.ReturnAfterVisitingHouse()
end

-- Build the dropdown list (favorite + otherLocationHearthstoneList)
local function BuildMenu()
    wipe(menuList)

    -- title
    table.insert(menuList, {
        text         = "Hearthstones",
        isTitle      = true,
        notClickable = true,
        color        = E:RGBToHex(1, 0.82, 0),
    })

    local available = twichui:GetAvailableHearthstones()

    -- read favorite from your DB (you must add this to your TwichUI db + config)
    local favoriteID
    if E.db.TwichUI and E.db.TwichUI.datatexts and E.db.TwichUI.datatexts.portals then
        favoriteID = E.db.TwichUI.datatexts.portals.favoriteHearthstone
    end

    -- favorite first, if set and available
    if favoriteID and available[favoriteID] then
        local name = available[favoriteID]
        local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(favoriteID)
        local macro = "/use item:" .. favoriteID

        local notClickable = false
        local cdText = twichui:GetItemCooldownText(favoriteID)
        if cdText then
            name = string.format("|cff808080%s (%s)|r", name, cdText)
            notClickable = true
        end

        table.insert(menuList, {
            text         = name,
            icon         = icon,
            notClickable = notClickable,
            macro        = macro,
            funcOnEnter  = function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                if PlayerHasToy(favoriteID) then
                    GameTooltip:SetToyByItemID(favoriteID)
                else
                    GameTooltip:SetItemByID(favoriteID)
                end
                GameTooltip:Show()
            end,
            funcOnLeave  = function(btn)
                GameTooltip:Hide()
            end,
        })
    end

    -- list only hearthstones in otherLocationHearthstoneList that are available
    for _, itemID in ipairs(otherLocationHearthstoneList) do
        local name = available[itemID]
        if name then
            local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
            local macro = "/use item:" .. itemID

            local notClickable = false
            local cdText = twichui:GetItemCooldownText(itemID)
            if cdText then
                name = string.format("|cff808080%s (%s)|r", name, cdText)
                notClickable = true
            end

            table.insert(menuList, {
                text         = name,
                icon         = icon,
                notClickable = notClickable,
                macro        = macro,
                funcOnEnter  = function(btn)
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    if PlayerHasToy(itemID) then
                        GameTooltip:SetToyByItemID(itemID)
                    else
                        GameTooltip:SetItemByID(itemID)
                    end
                    GameTooltip:Show()
                end,
                funcOnLeave  = function(btn)
                    GameTooltip:Hide()
                end,
            })
        end
    end

    -- safety: if nothing at all
    if #menuList == 1 then
        table.insert(menuList, {
            text         = "No hearthstones found",
            isTitle      = true,
            notClickable = true,
        })
    end

    -- if player is not at home, add home portal
    local atHome = C_Housing.IsInsideHouseOrPlot()
    if not atHome then
        -- As of 12/18/2025, there is no exposed API functionality to return player to previous location like Blizzard does in the offical UI.
        -- title
        table.insert(menuList, {
            text         = " ",
            isTitle      = true,
            notClickable = true,
            color        = E:RGBToHex(1, 0.82, 0),
        })
        table.insert(menuList, {
            text = "Teleport to House",
            icon = "Interface\\Icons\\Creatureportrait_Mageportal_Undercity",
            notClickable = false,
            func = TeleportToHouse
        })
    end
end

local displayCache = CacheAPI.New("PortalsDisplayCache")
local function GetDisplay()
    local cache = displayCache:get(function()
        local db = DataTextAPI:GetDatabase().portals
        return DataTextAPI:ColorTextByElvUISetting(db, "Portals")
    end)
    return cache
end


local function OnEvent(panel, event, ...)
    Logger:Debug("Portals datatext received event: " .. tostring(event))

    if event == "ELVUI_FORCE_UPDATE" then
        displayCache:invalidate()
    end

    if event == "TOYS_UPDATED" then
        hearthstoneCache:invalidate()
    end

    panel.text:SetText(GetDisplay())
end

local function OnEnter(self)
    BuildMenu()
    twichui:DropDown(menuList, twichui.menu, self, 0, 2, "twichui_portals")
end


-----------------------------------------------------------------------
-- Module registration
-----------------------------------------------------------------------

DataTextAPI:NewDataText(
    "TwichPortals",                              -- Internal name
    "Twich: Portals",                            -- Display name
    { "PLAYER_ENTERING_WORLD", "TOYS_UPDATED" }, -- Events
    OnEvent,                                     -- Event handler
    nil,                                         -- OnUpdate (none)
    nil,                                         -- OnClick (none)
    OnEnter,                                     -- Mouse enter
    nil                                          -- Mouse leave
)
