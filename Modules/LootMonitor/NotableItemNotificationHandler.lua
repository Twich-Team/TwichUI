local T, W, I, C                  = unpack(Twich)
local LSM                         = T.Libs.LSM
---@type LootMonitorModule
local LM                          = T:GetModule("LootMonitor")

---@type ConfigurationModule
local CM                          = T:GetModule("Configuration")
---@type LoggerModule
local Logger                      = T:GetModule("Logger")

--- @class NotableItemNotificationHandler
--- @field enabled boolean
--- @field callbackID number
local NIH                         = LM.NotableItemNotificationHandler or {}
LM.NotableItemNotificationHandler = NIH
--- Shows the notable item notification frame with the provided event data.
--- @param eventData LootValuatedEventData The event data for the looted item.
local function ShowNotificationFrame(eventData)
    local soundKey = CM:GetProfileSettingSafe("lootMonitor.notableItems.notificationSound", "None")
    if soundKey and soundKey ~= "None" then
        local path = LSM and LSM:Fetch("sound", soundKey)
        if path then
            PlaySoundFile(path, "Master")
        end
    end
    LM.NotableItemNotificationFrame:ShowFloatingMessage(eventData.itemInfo.link, eventData.totalValueCopper,
        eventData.quantity)
end


local function LootMonitorEventHandler(event, ...)
    if event == LM.EVENTS.LOOT_VALUATED then
        ---@type LootValuatedEventData
        local eventData = ...

        -- determine if the item looted is notable
        local minCopperValue = CM:GetProfileSettingSafe("lootMonitor.notableItems.minCopperValue", 100 * 100 * 100) -- default 100 gold
        local minSaleRate = CM:GetProfileSettingSafe("lootMonitor.notableItems.minSaleRate", 0.01)
        ShowNotificationFrame(eventData)
        -- if eventData.copperPerItem >= minCopperValue and eventData.saleRate >= minSaleRate then
        --     -- show the notification frame.
        --     ShowNotificationFrame(eventData)
        -- end
    end
end

function NIH:IsEnabled()
    return self.enabled
end

function NIH:Enable()
    if self.enabled then return end
    self.enabled = true

    -- register callback handler for notable item notifications
    self.callbackID = LM:GetCallbackHandler():Register(LootMonitorEventHandler)
    LM.NotableItemNotificationFrame:Initialize()
    Logger.Debug("Notable item notification handler enabled")
end

function NIH:Disable()
    if not self.enabled then return end
    self.enabled = false

    -- unregister callback handler for notable item notifications
    if self.callbackID then
        LM:GetCallbackHandler():Unregister(self.callbackID)
        self.callbackID = nil
    end
    Logger.Debug("Notable item notification handler disabled")
end

function NIH:Initialize()
    if self:IsEnabled() then return end

    -- check db to see if i should init
    local enabled = CM:GetProfileSettingSafe("lootMonitor.notableItems.enable", false)
    if enabled then
        self:Enable()
    end
end

--- Test helper: invoke the notification frame with synthetic event data.
-- @param itemLink string|nil An item link to display (defaults to a sample link)
-- @param copperValue number|nil Total value in copper (defaults to 123456)
-- @param quantity number|nil Quantity (defaults to 1)
function NIH:TestShowNotification(itemLink, copperValue, quantity)
    itemLink = itemLink or "|cffa335ee|Hitem:19019::::::::80:::::|h[Preview Thunderfury]|h|r"
    copperValue = tonumber(copperValue) or 123456
    quantity = tonumber(quantity) or 1

    -- Ensure the notification frame is initialized
    LM.NotableItemNotificationFrame:Initialize()

    Logger.Debug("NotableItemNotificationHandler:TestShowNotification() - link=" ..
    tostring(itemLink) .. " value=" .. tostring(copperValue) .. " qty=" .. tostring(quantity))

    local eventData = {
        itemInfo = { link = itemLink },
        totalValueCopper = copperValue,
        quantity = quantity,
    }

    ShowNotificationFrame(eventData)
end
