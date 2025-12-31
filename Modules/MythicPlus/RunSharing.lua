--[[
    RunSharing handles the transmission of run data between players.
    Uses AceComm-3.0 and AceSerializer-3.0 for efficient data transfer.
]]

local T = unpack(Twich)
local _G = _G

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

---@class MythicPlusRunSharingSubmodule
---@field enabled boolean
---@field receiver string|nil
local RunSharing = MythicPlusModule.RunSharing or {}
MythicPlusModule.RunSharing = RunSharing

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")

local time = _G.time
local LibStub = _G.LibStub

local PREFIX = "TWICH_RL"

-- Embed Ace libraries
local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

AceComm:Embed(RunSharing)
AceSerializer:Embed(RunSharing)

---@return TwichUIRunLoggerDB
local function GetDB()
    local key = "TwichUIRunLoggerDB"
    local db = _G[key]
    if type(db) ~= "table" then
        db = { version = 1 }
        _G[key] = db
    end
    if not db.remoteRuns then
        db.remoteRuns = {}
    end
    return db
end

function RunSharing:Initialize()
    if self.initialized then return end
    self.initialized = true

    self:RegisterComm(PREFIX, "OnCommReceived")

    local db = GetDB()
    self.receiver = db.linkedReceiver
    self.connectionStatus = "NONE"
end

function RunSharing:SetReceiver(name)
    local db = GetDB()
    db.linkedReceiver = name
    self.receiver = name
    Logger.Info("Run Sharing linked to: " .. (name or "None"))
end

---@param runData table
function RunSharing:SendRun(runData)
    if not self.receiver then return end

    local serialized = self:Serialize(runData)
    if not serialized then
        Logger.Error("Run Sharing: Failed to serialize run data")
        return
    end

    Logger.Info("Sending run data to " .. self.receiver)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", self.receiver)
end

function RunSharing:SendPing()
    if not self.receiver then return end

    local payload = { type = "PING" }
    local serialized = self:Serialize(payload)
    if serialized then
        self.connectionStatus = "PENDING"
        self:SendCommMessage(PREFIX, serialized, "WHISPER", self.receiver)
        print("|cff9580ffTwichUI:|r Sending connection test to " .. self.receiver .. "...")

        local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
            LibStub("AceConfigRegistry-3.0", true)
        if ACR then ACR:NotifyChange("ElvUI") end

        -- Timeout check (5 seconds)
        _G.C_Timer.After(5, function()
            if self.connectionStatus == "PENDING" then
                self.connectionStatus = "FAILED"
                local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
                    LibStub("AceConfigRegistry-3.0", true)
                if ACR then ACR:NotifyChange("ElvUI") end
            end
        end)
    end
end

function RunSharing:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end

    local success, data = self:Deserialize(message)
    if not success then
        Logger.Error("Run Sharing: Failed to deserialize data from " .. sender)
        return
    end

    if type(data) == "table" then
        if data.type == "PING" then
            -- Reply with PONG
            local pong = { type = "PONG" }
            local serialized = self:Serialize(pong)
            if serialized then
                self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
            end
            return
        elseif data.type == "PONG" then
            self.connectionStatus = "SUCCESS"
            print("|cff9580ffTwichUI:|r Connection confirmed! Received response from " .. sender)
            local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
                LibStub("AceConfigRegistry-3.0", true)
            if ACR then ACR:NotifyChange("ElvUI") end
            return
        end
    end

    self:ProcessReceivedRun(sender, data)
end

function RunSharing:ProcessReceivedRun(sender, runData)
    -- Basic validation
    if type(runData) ~= "table" or not runData.id then return end

    -- Check if we should ignore incoming runs
    if CM:GetProfileSettingSafe("developer.mythicplus.runSharing.ignoreIncoming", false) then
        Logger.Info("Run Sharing: Ignored incoming run data from " .. sender .. " (setting enabled)")
        return
    end

    local db = GetDB()

    table.insert(db.remoteRuns, {
        sender = sender,
        receivedAt = time(),
        data = runData -- Storing as Lua table
    })

    Logger.Info("Received Mythic+ run data from " .. sender)

    -- Notify UI if available
    if MythicPlusModule.RunSharingFrame and MythicPlusModule.RunSharingFrame.UpdateList then
        MythicPlusModule.RunSharingFrame:UpdateList()
    end
end
