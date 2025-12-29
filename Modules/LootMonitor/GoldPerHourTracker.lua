--- Gold Per Hour Tracker Module
--- Tracks loot and gold received and calculates gold per hour rates
--- Supports configurable time windows and optional periodic recalculation via ticker

local T, W, I, C      = unpack(Twich)
local LSM             = T.Libs.LSM
---@type LootMonitorModule
local LM              = T:GetModule("LootMonitor")

---@type ConfigurationModule
local CM              = T:GetModule("Configuration")
---@type LoggerModule
local Logger          = T:GetModule("Logger")
---@type ToolsModule
local TM              = T:GetModule("Tools")

--- Represents a single tracked item
---@class TrackedItem
---@field itemLink string The item's full link
---@field quantity number Total quantity of this item looted
---@field totalValue number Total copper value of all quantities
---@field decision string The valuation decision made (e.g., "vendor", "disenchant", "market", "ignore")
---@field timestamp number The timestamp of the last loot occurrence of this item

--- Gold Per Hour Tracker module
--- Manages tracking of looted items and gold received within a time window
---@class GoldPerHourTracker
---@field enabled boolean Whether the tracker is actively running
---@field callbackID number ID of the registered event handler callback
---@field windowSize number The time window in seconds for tracking data
---@field alwaysOn boolean Whether to ignore the window and track indefinitely
---@field useTicker boolean Whether the ticker is currently active (effective, may be overridden for session)
---@field tickRate number The current effective tick rate in seconds (may be overridden for session)
---@field configUseTicker boolean Player-configured ticker setting
---@field configTickRate number Player-configured tick rate in seconds
---@field sessionFastTickerEnabled boolean|nil If true, force ticker to 1s for this session only
---@field tickerID? table The C_Timer ticker object if active
---@field configWatcherID? table The C_Timer config watcher object if active
---@field trackedItems table<string, TrackedItem> Items indexed by itemLink
---@field goldReceived number Raw gold received in copper
---@field startTime? number Timestamp of the first loot/money in current window
---@field gphCallbacks? table Callback instance for update notifications
local GPH             = LM.GoldPerHourTracker or {}
LM.GoldPerHourTracker = GPH

--- Configuration entries for the Gold Per Hour Tracker
---@class GoldPerHourTrackerConfiguration
---@field ENABLED ConfigEntry Master enable/disable setting
---@field WINDOW_SIZE ConfigEntry Time window in seconds for data retention (default: 900 = 15 minutes)
---@field USE_TICKER ConfigEntry Whether to enable periodic recalculation (default: false)
---@field TICK_RATE ConfigEntry Interval in seconds for ticker callbacks (default: 15)
---@field ALWAYS_ON ConfigEntry Whether to ignore the window and track indefinitely (default: false)
---@field PERSISTED_DATA ConfigEntry Persisted tracking data that survives /reloadui
GPH.CONFIGURATION     = {
    ENABLED = { key = "lootMonitor.goldPerHourTracker.enabled", default = false },
    WINDOW_SIZE = { key = "lootMonitor.goldPerHourTracker.windowSize", default = 900 }, -- in seconds (15 minutes)
    USE_TICKER = { key = "lootMonitor.goldPerHourTracker.useTicker", default = false },
    TICK_RATE = { key = "lootMonitor.goldPerHourTracker.tickRate", default = 15 },      -- in seconds
    ALWAYS_ON = { key = "lootMonitor.goldPerHourTracker.alwaysOn", default = false },
    PERSISTED_DATA = { key = "lootMonitor.goldPerHourTracker.persistedData", default = {} },
}

--- Return value from GetCurrentStats()
--- Contains all relevant statistics about the current tracking session
---@class GoldPerHourData
---@field goldPerHour number Calculated gold per hour rate
---@field totalValue number Total copper value from tracked items
---@field totalGold number Total copper value (items + raw gold)
---@field goldReceived number Raw gold received in copper
---@field itemCount number Number of unique item types tracked
---@field elapsedTime number Elapsed time in seconds since tracking started
---@field trackedItems table<string, TrackedItem> Reference to tracked items by itemLink

--- Internal event handler for loot monitor events
--- Dispatches events to the appropriate handler methods
---@param event string The event type
---@param ... any Event-specific data
local function LootMonitorEventHandler(event, ...)
    if event == LM.EVENTS.LOOT_VALUATED then
        -- handle loot valuated event
        ---@type LootValuatedEventData
        local eventData = ...
        GPH:OnLootValuated(eventData)
    elseif event == LM.EVENTS.MONEY_RECEIVED then
        -- handle money received event
        ---@type MoneyReceivedEventData
        local eventData = ...
        GPH:OnMoneyReceived(eventData)
    end
end

--- Check if the tracker is currently enabled
---@return boolean enabled True if the tracker is running
function GPH:IsEnabled()
    return self.enabled
end

--- Remove tracked items and gold outside the configured time window
--- If always-on mode is enabled, this function does nothing
--- Resets the start time if no items remain after trimming
function GPH:TrimOldData()
    if self.alwaysOn then return end

    local now = GetTime()
    local windowStart = now - self.windowSize

    -- Trim items outside the window
    for itemID, item in pairs(self.trackedItems) do
        if item.timestamp < windowStart then
            self.trackedItems[itemID] = nil
        end
    end

    -- Update start time if we have items, otherwise reset
    if next(self.trackedItems) == nil then
        self.startTime = nil
        self.goldReceived = 0
    elseif self.startTime and self.startTime < windowStart then
        -- Only update start time if it's older than the window
        self.startTime = windowStart
    end
end

--- Get the current tracking statistics
--- Calculates gold per hour based on total value and elapsed time
---@return GoldPerHourData statistics Current tracking stats including GPH, totals, and item list
function GPH:GetCurrentStats()
    local now = GetTime()
    local elapsedTime = 0
    local totalValue = 0

    -- Calculate elapsed time
    if self.startTime then
        elapsedTime = now - self.startTime
        if elapsedTime < 1 then elapsedTime = 1 end -- Avoid division by zero
    else
        elapsedTime = 0
    end

    -- Calculate total value from tracked items
    for _, item in pairs(self.trackedItems) do
        totalValue = totalValue + item.totalValue
    end

    -- Calculate gold per hour
    local totalGold = totalValue + self.goldReceived
    local goldPerHour = 0
    if elapsedTime > 0 then
        goldPerHour = (totalGold / elapsedTime) * 3600 -- Convert to per hour
    end

    local itemCount = 0
    for _ in pairs(self.trackedItems) do
        itemCount = itemCount + 1
    end

    return {
        goldPerHour = goldPerHour,
        totalValue = totalValue,
        totalGold = totalGold,
        goldReceived = self.goldReceived,
        itemCount = itemCount,
        elapsedTime = elapsedTime,
        trackedItems = self.trackedItems,
    }
end

--- Handle a loot valuated event
--- Adds or updates the tracked item and triggers an update callback
---@param eventData LootValuatedEventData The loot event containing item and value information
function GPH:OnLootValuated(eventData)
    if not self:IsEnabled() then return end

    self:TrimOldData()

    local now = GetTime()

    -- Initialize start time on first loot
    if not self.startTime then
        self.startTime = now
    end

    -- Track the item using its link as key
    local itemLink = eventData.itemInfo.link
    if not itemLink then return end

    Logger.DumpTable(eventData)

    if not self.trackedItems[itemLink] then
        self.trackedItems[itemLink] = {
            itemLink = itemLink,
            quantity = eventData.quantity,
            totalValue = eventData.totalValueCopper,
            decision = eventData.decision,
            timestamp = now,
        }
    else
        self.trackedItems[itemLink].quantity = self.trackedItems[itemLink].quantity + eventData.quantity
        self.trackedItems[itemLink].totalValue = self.trackedItems[itemLink].totalValue + eventData.totalValueCopper
        self.trackedItems[itemLink].timestamp = now
        -- Ensure decision is populated even for existing entries or older persisted data
        if not self.trackedItems[itemLink].decision and eventData.decision then
            self.trackedItems[itemLink].decision = eventData.decision
        end
    end

    self:TriggerUpdate()
end

--- Handle a money received event
--- Adds the money to goldReceived and triggers an update callback
---@param eventData MoneyReceivedEventData The money event containing the amount received
function GPH:OnMoneyReceived(eventData)
    if not self:IsEnabled() then return end

    self:TrimOldData()

    local now = GetTime()

    -- Initialize start time on first money received
    if not self.startTime then
        self.startTime = now
    end

    self.goldReceived = self.goldReceived + eventData.copper

    self:TriggerUpdate()
end

--- Calculate and invoke all registered callbacks with current statistics
--- Called whenever loot or gold is received, or periodically by the ticker
function GPH:TriggerUpdate()
    local stats = self:GetCurrentStats()
    self.gphCallbacks:Invoke(stats)
    self:SaveState()
end

function GPH:IsSessionFastTickerEnabled()
    return self.sessionFastTickerEnabled == true
end

function GPH:GetEffectiveUseTicker()
    return self:IsSessionFastTickerEnabled() or (self.configUseTicker == true)
end

function GPH:GetEffectiveTickRate()
    if self:IsSessionFastTickerEnabled() then
        return 1
    end
    return tonumber(self.configTickRate) or 15
end

function GPH:ApplyEffectiveTickerSettings()
    local shouldUseTicker = self:GetEffectiveUseTicker()
    local desiredRate = self:GetEffectiveTickRate()

    local rateChanged = (tonumber(self.tickRate) or 0) ~= (tonumber(desiredRate) or 0)
    self.useTicker = shouldUseTicker
    self.tickRate = desiredRate

    if not shouldUseTicker then
        self:StopTicker()
        return
    end

    if self.tickerID then
        if rateChanged then
            self:RestartTicker()
        end
    else
        self:StartTicker()
    end
end

function GPH:SetSessionFastTickerEnabled(enabled)
    self.sessionFastTickerEnabled = enabled == true
    if not self:IsEnabled() then return end
    self:ApplyEffectiveTickerSettings()
    self:TriggerUpdate()
end

--- Start the optional periodic ticker for continuous recalculation
--- The ticker will call TriggerUpdate() at the configured tick_rate interval
--- Has no effect if a ticker is already running
function GPH:StartTicker()
    if self.tickerID then return end

    local function TickerCallback()
        self:TriggerUpdate()
    end

    self.tickerID = C_Timer.NewTicker(self.tickRate, TickerCallback)
    Logger.Debug("Gold per hour tracker ticker started at rate: " .. self.tickRate .. "s")
end

--- Stop the periodic ticker if it's running
--- Has no effect if no ticker is active
function GPH:StopTicker()
    if not self.tickerID then return end
    self.tickerID:Cancel()
    self.tickerID = nil
    Logger.Debug("Gold per hour tracker ticker stopped")
end

--- Restart the ticker with the current configuration
--- Stops the old ticker and starts a new one with updated settings
function GPH:RestartTicker()
    self:StopTicker()
    if self.useTicker then
        self:StartTicker()
    end
end

--- Update the ticker rate and restart the ticker if it's running
--- Called when the tick rate configuration changes
---@param newTickRate number The new tick rate in seconds
function GPH:UpdateTickRate(newTickRate)
    self.configTickRate = tonumber(newTickRate) or self.configTickRate
    self:ApplyEffectiveTickerSettings()
end

--- Switch between always-on and window mode
--- Called when the ALWAYS_ON configuration changes
---@param newAlwaysOn boolean True to enable always-on mode, false for window mode
function GPH:SwitchMode(newAlwaysOn)
    local oldMode = self.alwaysOn and "always-on" or "window"
    local newMode = newAlwaysOn and "always-on" or "window"

    self.alwaysOn = newAlwaysOn

    if newAlwaysOn then
        -- Switching TO always-on mode: keep data, stop trimming
        Logger.Debug("Gold per hour tracker mode changed from " ..
            oldMode .. " to " .. newMode .. " - data will be retained indefinitely")
        self:TriggerUpdate()
    else
        -- Switching TO window mode: establish a new window
        Logger.Debug("Gold per hour tracker mode changed from " ..
            oldMode .. " to " .. newMode .. " - window tracking restarted")
        self.startTime = GetTime()
        self:TriggerUpdate()
    end
end

--- Enable the tracker
--- Loads configuration, registers event handlers, and starts ticker if configured
--- Has no effect if already enabled
function GPH:Enable()
    if self:IsEnabled() then return end
    self.enabled = true

    -- Load configuration
    self.windowSize = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.WINDOW_SIZE)
    self.configUseTicker = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.USE_TICKER)
    self.configTickRate = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.TICK_RATE)
    self.alwaysOn = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ALWAYS_ON)

    -- Register event handler
    self.callbackID = LM:GetCallbackHandler():Register(LootMonitorEventHandler)

    -- Start/stop ticker based on effective config + session override
    self:ApplyEffectiveTickerSettings()

    Logger.Debug("Gold per hour tracker enabled")
end

--- Set whether the ticker should be enabled
--- Called from configuration when user toggles periodic recalculation
---@param enabled boolean True to enable ticker, false to disable
function GPH:SetUseTicker(enabled)
    self.configUseTicker = enabled == true
    self:ApplyEffectiveTickerSettings()
end

--- Set the ticker rate
--- Called from configuration when user changes the tick rate
---@param newTickRate number The new tick rate in seconds
function GPH:SetTickRate(newTickRate)
    self:UpdateTickRate(newTickRate)
end

--- Set the tracking mode (always-on vs window)
--- Called from configuration when user toggles always-on mode
---@param newAlwaysOn boolean True for always-on mode, false for window mode
function GPH:SetAlwaysOn(newAlwaysOn)
    self:SwitchMode(newAlwaysOn)
end

--- Disable the tracker
--- Unregisters event handlers, stops the ticker, and clears all tracked data
--- Has no effect if already disabled
function GPH:Disable()
    if not self:IsEnabled() then return end
    self.enabled = false

    if self.callbackID then
        LM:GetCallbackHandler():Unregister(self.callbackID)
        self.callbackID = nil
    end

    self:StopTicker()

    -- Reset data
    self:Reset()

    Logger.Debug("Gold per hour tracker disabled")
end

--- Reset all tracked data
--- Clears items, gold, and timestamps
function GPH:Reset()
    self.trackedItems = {}
    self.goldReceived = 0
    self.startTime = nil
    self:TriggerUpdate()
end

--- Save the current tracking state to persistent storage
--- Called automatically when data is updated so it survives /reloadui
function GPH:SaveState()
    local persistedData = {
        trackedItems = self.trackedItems,
        goldReceived = self.goldReceived,
        startTime = self.startTime,
    }
    CM:SetProfileSettingSafe(self.CONFIGURATION.PERSISTED_DATA.key, persistedData)
end

--- Load the persisted tracking state from storage
--- Called on Initialize to restore data after /reloadui
function GPH:LoadState()
    local persistedData = CM:GetProfileSettingSafe(self.CONFIGURATION.PERSISTED_DATA.key, {})
    if persistedData and persistedData.trackedItems then
        self.trackedItems = persistedData.trackedItems
        self.goldReceived = persistedData.goldReceived or 0
        self.startTime = persistedData.startTime
    end
end

--- Register a callback to be invoked when statistics are updated
--- Callbacks are called with a GoldPerHourData table as the only argument
---@param callback fun(stats:GoldPerHourData) Function to be called on updates
---@return number id Callback ID for later unregistration
function GPH:RegisterCallback(callback)
    return self.gphCallbacks:Register(callback)
end

--- Unregister a previously registered callback
---@param id number The callback ID returned by RegisterCallback()
function GPH:UnregisterCallback(id)
    self.gphCallbacks:Unregister(id)
end

--- Initialize the tracker
--- Sets up the callback system and loads configuration
--- Automatically enables the tracker if configured to do so
function GPH:Initialize()
    if self:IsEnabled() then return end

    -- Initialize callback system
    self.gphCallbacks = TM.Callback.New()

    -- Do NOT clear persisted data here; load any saved state first
    self:LoadState()

    -- Ensure tables are initialized if nothing was persisted
    self.trackedItems = self.trackedItems or {}
    self.goldReceived = self.goldReceived or 0

    -- Check if it should be enabled via configuration
    local shouldEnable = CM:GetProfileSettingByConfigEntry(self.CONFIGURATION.ENABLED)

    if shouldEnable then
        self:Enable()
    end

    -- Emit an immediate update so UIs can render restored state
    self:TriggerUpdate()
end

--- Request an immediate stats update (used by UI modules)
function GPH:RequestImmediateUpdate()
    self:TriggerUpdate()
end
