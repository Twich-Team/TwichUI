local T, W, I, C = unpack(Twich)

TwichUIGoldDB = TwichUIGoldDB or {}
local UnitName = UnitName
local GetRealmName = GetRealmName
local GetMoney = GetMoney
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup


---@type GoldGoblinModule
local GG = T:GetModule("GoldGoblin")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local LM = T:GetModule("Logger")
---@type ToolsModule
local TM = T:GetModule("Tools")


---@class GoldTrackerModule
---@field enabled boolean
---@field eventFrame Frame the frame used to register events
local GT       = GG.GoldTracker or {}
GG.GoldTracker = GT

local Module   = TM.Generics.Module:New(
    {
        ENABLE = { key = "goldGoblin.goldTracker.enable", default = false }
    },
    { 'ACCOUNT_MONEY', 'PLAYER_MONEY', 'SEND_MAIL_MONEY_CHANGED', 'SEND_MAIL_COD_CHANGED', 'PLAYER_TRADE_MONEY',
        'TRADE_MONEY_CHANGED', 'CURRENCY_DISPLAY_UPDATE', 'PERKS_PROGRAM_CURRENCY_REFRESH', 'PLAYER_LOGIN' })

local function InitDB()
    local name, realm = UnitName("player"), GetRealmName()

    TwichUIGoldDB[realm] = TwichUIGoldDB[realm] or {}

    TwichUIGoldDB[realm][name] = TwichUIGoldDB[realm][name] or {
        totalCopper = 0,
        class = select(2, UnitClass("player")),
        faction = UnitFactionGroup("player"),
    }
end

local function EventHandler(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InitDB()
    end

    local name, realm = UnitName("player"), GetRealmName()
    local currentMoney = GetMoney()

    if TwichUIGoldDB and TwichUIGoldDB[realm] and TwichUIGoldDB[realm][name] then
        TwichUIGoldDB[realm][name].totalCopper = currentMoney
        LM.Debug("Gold tracker updated total gold for " .. name .. "-" .. realm .. ": " .. currentMoney)
        -- notify listeners of gold change
        if TM and TM.Money and TM.Money.NotifyGoldUpdated then
            TM.Money:NotifyGoldUpdated()
        end
    end
end

function GT:Enable()
    Module:Enable(EventHandler)
    -- calling the event handler with PLAYER_LOGIN so the database gets initialized (if needed) when enabled for the first time.
    EventHandler(nil, "PLAYER_LOGIN")
    LM.Debug("Gold Tracker enabled")
end

function GT:Disable()
    Module:Disable()
    LM.Debug("Gold Tracker disabled")
end

function GT:Initialize()
    if Module:IsEnabled() then return end

    if CM:GetProfileSettingByConfigEntry(Module.CONFIGURATION.ENABLE) then
        self:Enable()
    end
end

function GT:IsEnabled()
    return Module:IsEnabled()
end
