local T, W, I, C    = unpack(Twich)
---@class LootMonitorModule
---@field enabled boolean
---@field frame Frame
---@field ItemValuator ItemValuator
local LM            = T:GetModule("LootMonitor")

LM.EVENTS           = {
    LOOT_RECEIVED = "LOOT_MONITOR_LOOT_RECEIVED",
    MONEY_RECEIVED = "LOOT_MONITOR_MONEY_RECEIVED",
    LOOT_VALUATED = "LOOT_MONITOR_LOOT_VALUATED",
}

---@type LoggerModule
local Logger        = T:GetModule("Logger")
---@type ToolsModule
local Tools         = T:GetModule("Tools")

local CreateFrame   = CreateFrame
local GetItemInfo   = C_Item.GetItemInfo
local EVENTS        = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY" }

---@class LootReceievedEventData
---@field itemInfo LootMonitorItemInfo
---@field quantity number

---@class MoneyReceivedEventData
---@field copper number

---@class LootMonitorItemInfo
---@field name string|nil
---@field link string|nil
---@field quality number|nil
---@field iLevel number|nil
---@field minLevel number|nil
---@field type string|nil
---@field subType string|nil
---@field maxStack number|nil
---@field equipLoc string|nil
---@field icon number|nil
---@field sellPrice number|nil
---@field classID number|nil
---@field subClassID number|nil
---@field bindType number|nil
---@field expansionID number|nil
---@field setID number|nil
---@field isCraftingReagent boolean|nil

-- Keys for mapping GetItemInfo() returns into a table
local ITEMINFO_KEYS = {
    "name", "link", "quality", "iLevel", "minLevel", "type", "subType",
    "maxStack", "equipLoc", "icon", "sellPrice", "classID", "subClassID",
    "bindType", "expansionID", "setID", "isCraftingReagent"
}

--- Safe wrapper for `GetItemInfo` that returns a table of named fields.
-- If the item info isn't cached yet and a `callback` is provided, it will
-- register a one-time `GET_ITEM_INFO_RECEIVED` listener and invoke the
-- callback with the table once data becomes available.
-- @param item string|number itemLink or itemID
--- @param callback fun(info:LootMonitorItemInfo|nil):void|nil optional one-time callback(itemTable)
--- @return LootMonitorItemInfo|nil item info table if available immediately
local function GetItemInfoTable(item, callback)
    local results = { GetItemInfo(item) }
    if not results[1] then
        -- not cached yet
        if type(callback) == "function" then
            -- try to extract itemID if we have an itemLink
            local itemID
            if type(item) == "number" then
                itemID = item
            elseif type(item) == "string" then
                itemID = tonumber(item:match("item:(%d+):"))
            end

            -- create a short-lived frame to listen for GET_ITEM_INFO_RECEIVED
            local waiter = CreateFrame("Frame")
            local function OnGetItemInfoReceived(_, event, gotItemID, success)
                if not success then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    if type(callback) == "function" then callback(nil) end
                    return
                end

                if not itemID or tonumber(gotItemID) == tonumber(itemID) then
                    waiter:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
                    waiter:SetScript("OnEvent", nil)
                    local filled = GetItemInfoTable(item)
                    if type(callback) == "function" then callback(filled) end
                end
            end

            waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            waiter:SetScript("OnEvent", OnGetItemInfoReceived)
        end
        return nil
    end

    local t = {}
    for i = 1, #results do
        t[ITEMINFO_KEYS[i] or ("field" .. i)] = results[i]
    end
    return t
end

-- Constants from the game
local GOLD_AMOUNT       = GOLD_AMOUNT
local SILVER_AMOUNT     = SILVER_AMOUNT
local COPPER_AMOUNT     = COPPER_AMOUNT
local LOOT_ITEM_SELF    = LOOT_ITEM_SELF

-- Patterns defined based on the money constants to parse the money received chat messages
local GOLD_PATTERN      = string.gsub(GOLD_AMOUNT, "%%d", "(%%d+)")
local SILVER_PATTERN    = string.gsub(SILVER_AMOUNT, "%%d", "(%%d+)")
local COPPER_PATTERN    = string.gsub(COPPER_AMOUNT, "%%d", "(%%d+)")
local LOOT_SELF_PATTERN = string.gsub(LOOT_ITEM_SELF, "%%s", "(.+)")

local callbackHandler   = Tools.Callback.New()

---@param frame Frame the frame to clear events from
local function ClearFrame(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
end

--- Parses the money received chat message to determine the number of copper received.
--- @param message string the chat message to parse
--- @return number copper the number of copper received
local function ParseMoneyChatMessage(message)
    if not message then return 0 end
    local g = tonumber(message:match(GOLD_PATTERN) or 0)
    local s = tonumber(message:match(SILVER_PATTERN) or 0)
    local c = tonumber(message:match(COPPER_PATTERN) or 0)
    return g * 10000 + s * 100 + c
end

--- Handles the chat message for money received.
--- @param message string the chat message to handle
local function OnChatMsgMoney(message)
    -- parse the copper received from the message
    ---@type MoneyReceivedEventData
    local copperReceived = {
        copper = ParseMoneyChatMessage(message)
    }
    if copperReceived > 0 then
        callbackHandler:Invoke(LM.EVENTS.MONEY_RECEIVED, copperReceived)
    end
end

--- Handles the chat message for loot received.
--- @param message string the chat message to handle
local function OnChatMsgLoot(message)
    -- only handling self loot messages
    local raw = message:match(LOOT_SELF_PATTERN)
    if not raw then return end

    -- extract quantity looted
    local quantity = 1

    -- handle common "[Item]xN" / "[Item]xN."
    local qtyMatch = raw:match("x(%d+)%.?$")
    if not qtyMatch then
        -- Fallback: " xN" at end if Blizzard ever formats that way
        qtyMatch = raw:match("%sx(%d+)%s*%.?$")
    end

    if qtyMatch then
        quantity = tonumber(qtyMatch) or 1
        -- strip the trailing "xN" with optional leading space and trailing period
        raw = raw:gsub("%s*x%d+%.?$", "")
    end

    -- create an item link from the message
    local itemLink = raw:match("(|c%x+|Hitem:[^|]+|h%[[^]]+%]|h|r)") or raw
    if not itemLink then
        return
    end

    -- get item data as a table; if not cached we'll wait and invoke the callback once available
    local info = GetItemInfoTable(itemLink)
    if info then
        ---@type LootReceievedEventData
        local eventData = {
            itemInfo = info,
            quantity = quantity
        }
        callbackHandler:Invoke(LM.EVENTS.LOOT_RECEIVED, eventData)
        return
    end

    -- not cached: register a one-time callback to fire when GetItemInfo becomes available
    GetItemInfoTable(itemLink, function(filled)
        if not filled then
            Logger.Error("Failed to retrieve item information from Blizzard API for item: " .. tostring(itemLink))
            return
        end
        ---@type LootReceievedEventData
        local eventData = {
            itemInfo = filled,
            quantity = quantity
        }
        callbackHandler:Invoke(LM.EVENTS.LOOT_RECEIVED, eventData)
    end)
end

--- Handles the incoming events to the module.
local function HandleEvent(_, event, ...)
    if event == "CHAT_MSG_LOOT" then
        local message = ...
        if type(message) == "string" then
            OnChatMsgLoot(message)
        end
    elseif event == "CHAT_MSG_MONEY" then
        local message = ...
        if type(message) == "string" then
            OnChatMsgMoney(message)
        end
    end
end

---@return boolean isenabled true if the module is enabled
function LM:IsEnabled()
    return self.enabled
end

--- Enable the Loot Monitor module
function LM:Enable()
    if self:IsEnabled() then return end

    -- clear the frame if for some reason it still exists
    if self.frame then
        ClearFrame(self.frame)
        self.frame = nil
    end

    self.enabled = true

    -- create the frame
    self.frame = CreateFrame("Frame", "TwichLootMonitorFrame")

    -- set the event handler on it
    self.frame:SetScript("OnEvent", HandleEvent)

    -- register desired events
    for _, event in ipairs(EVENTS) do
        self.frame:RegisterEvent(event)
    end

    Logger.Debug("Loot monitor enabled")

    LM.ItemValuator:Enable()
end

--- Disable the Loot Monitor module
function LM:Disable()
    if not self:IsEnabled() then return end

    if self.frame then
        ClearFrame(self.frame)
        self.frame = nil
    end

    self.enabled = false

    Logger.Debug("Loot Monitor disabled")

    LM.ItemValuator:Disable()
end

--- Called by Ace on initialization.
function LM:OnInitialize()
    Logger.Debug("Loot Monitor initialing..")
    -- if already enabled, do nothing
    if self:IsEnabled() then return end

    ---@type ConfigurationModule
    local CM = T:GetModule("Configuration")
    -- if not enabled via configuration, do nothing
    if not CM:GetProfileSettingSafe("lootMonitor.enable", false) then return end

    self:Enable()

    -- temporarily registering a callback handler here to debug
    local callbackID = callbackHandler:Register(function(event, ...)
        Logger.Debug("Loot Monitor callback invoked for event: " .. tostring(event))
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "table" then
                Logger.Debug("Arg " .. i .. " (table): ")
                Logger.DumpTable(v)
            else
                Logger.Debug("Arg " .. i .. ": " .. tostring(v))
            end
        end
    end)
end

--- Get the CallbackInstance for the module. The following events are available: "LOOT_MONITOR_LOOT_RECEIVED", and "LOOT_MONITOR_MONEY_RECEIVED".
--- These callbacks are only invoked for the current player and for items/money that are received "RAW" (not from a container or bank).
--- @return CallbackInstance callbackHandler module's callback handler
function LM:GetCallbackHandler()
    return callbackHandler
end
