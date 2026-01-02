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
---@type ToolsModule
local Tools = T:GetModule("Tools")

local time = _G.time
local UnitName = _G.UnitName
local LibStub = _G.LibStub
local C_Timer = _G.C_Timer
local strtrim = _G.strtrim
local GetTime = _G.GetTime
local ChatFrame_AddMessageEventFilter = _G.ChatFrame_AddMessageEventFilter
local ERR_CHAT_PLAYER_NOT_FOUND_S = _G.ERR_CHAT_PLAYER_NOT_FOUND_S

local PREFIX = "TWICH_RL"

-- Embed Ace libraries
local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

AceComm:Embed(RunSharing)
AceSerializer:Embed(RunSharing)

local function Trim(s)
    if type(s) ~= "string" then return nil end
    if type(strtrim) == "function" then
        return strtrim(s)
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param name any
---@return string|nil
local function NormalizePlayerName(name)
    if type(name) ~= "string" then return nil end
    name = Trim(name)
    if not name or name == "" then return nil end
    -- Some APIs can produce "Name - Realm"; normalize to "Name-Realm".
    name = name:gsub("%s*%-%s*", "-")
    -- Player/realm identifiers never contain spaces in whisper targets.
    name = name:gsub("%s+", "")
    if name == "" then return nil end
    return name
end

local function GetBaseName(fullName)
    if type(fullName) ~= "string" then return nil end
    local dash = fullName:find("-", 1, true)
    if dash then
        return fullName:sub(1, dash - 1)
    end
    return fullName
end

local function MatchesPlayerNotFound(msg, name)
    if type(msg) ~= "string" or type(name) ~= "string" then return false end
    -- Prefer the global localized format string if available.
    if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S:find("%%s", 1, true) then
        local prefix, suffix = ERR_CHAT_PLAYER_NOT_FOUND_S:match("^(.-)%%s(.-)$")
        if prefix and suffix then
            return msg == (prefix .. name .. suffix)
        end
    end
    -- Fallback (enUS-style) matcher.
    local extracted = msg:match("^No player named '(.+)' is currently playing%.$")
    return extracted == name
end

local function NotifyConfigChanged()
    local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
        LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("ElvUI")
    end
end

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

    if type(db.registeredReceivers) ~= "table" then
        db.registeredReceivers = {}
    end
    return db
end

function RunSharing:Initialize()
    if self.initialized then return end
    self.initialized = true

    self:RegisterComm(PREFIX, "OnCommReceived")

    self.OnRunAcknowledged = Tools.Callback:New()
    self.OnConnectionEstablished = Tools.Callback:New()
    self.OnReceiverRegistered = Tools.Callback:New()

    local db = GetDB()
    self.receiver = NormalizePlayerName(db.linkedReceiver) or db.linkedReceiver
    -- Persist registrations across /reload.
    -- Key: character name (as seen by AceComm sender), Value: lastSeenUnix
    self.registeredReceivers = db.registeredReceivers

    -- Install a narrow chat filter to optionally suppress the system "No player named ..." message
    -- when our background (silent) ping targets someone who is offline or not found.
    if not self._systemFilterInstalled and type(ChatFrame_AddMessageEventFilter) == "function" then
        self._systemFilterInstalled = true
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
            if not CM:GetProfileSettingSafe("developer.mythicplus.runSharing.hidePlayerNotFound", true) then
                return false
            end

            local suppress = self._suppressPlayerNotFoundUntil
            if type(suppress) ~= "table" then
                return false
            end

            local now = (type(GetTime) == "function" and GetTime()) or 0
            for name, untilTime in pairs(suppress) do
                if untilTime and now <= untilTime and MatchesPlayerNotFound(msg, name) then
                    return true
                end
            end

            -- Opportunistic cleanup of expired entries.
            for name, untilTime in pairs(suppress) do
                if not untilTime or now > untilTime then
                    suppress[name] = nil
                end
            end

            return false
        end)
    end

    -- Migrate any previously stored keys that include whitespace.
    if type(self.registeredReceivers) == "table" then
        for name, lastSeen in pairs(self.registeredReceivers) do
            local normalized = NormalizePlayerName(name)
            if normalized and normalized ~= name then
                -- Prefer an existing normalized entry if present.
                if self.registeredReceivers[normalized] == nil then
                    self.registeredReceivers[normalized] = lastSeen
                end
                self.registeredReceivers[name] = nil
            end
        end
    end
    self.connectionStatus = "NONE"

    -- Status for registration operations against the configured "Register With" target.
    self.registerWithStatus = self.registerWithStatus or "NONE"           -- NONE|PENDING|SUCCESS|FAILED
    self.registerWithTarget = self.registerWithTarget or nil
    self.registrationCheckStatus = self.registrationCheckStatus or "NONE" -- NONE|PENDING|SUCCESS|FAILED
    self.registrationCheckTarget = self.registrationCheckTarget or nil
    self.registrationCheckResult = self.registrationCheckResult or nil    -- boolean|nil
end

function RunSharing:SetReceiver(name)
    name = NormalizePlayerName(name) or name
    local db = GetDB()
    db.linkedReceiver = name
    self.receiver = name
    Logger.Info("Run Sharing linked to: " .. (name or "None"))
end

---@return string[]
function RunSharing:GetRecipients()
    local recipients = {}
    local seen = {}

    local function Add(name)
        local n = NormalizePlayerName(name)
        if not n then return end
        if not seen[n] then
            seen[n] = true
            recipients[#recipients + 1] = n
        end
    end

    Add(self.receiver)

    if type(self.registeredReceivers) == "table" then
        local myName = type(UnitName) == "function" and UnitName("player") or nil
        for name, _ in pairs(self.registeredReceivers) do
            if not myName or name ~= myName then
                Add(name)
            end
        end
    end

    return recipients
end

---@return string[]
function RunSharing:GetRegisteredReceiversList()
    local out = {}
    if type(self.registeredReceivers) ~= "table" then
        return out
    end

    for name in pairs(self.registeredReceivers) do
        local n = NormalizePlayerName(name)
        if n then
            out[#out + 1] = n
        end
    end
    table.sort(out)
    return out
end

function RunSharing:ClearRegisteredReceivers()
    if type(self.registeredReceivers) ~= "table" then
        return
    end

    for name in pairs(self.registeredReceivers) do
        self.registeredReceivers[name] = nil
    end

    NotifyConfigChanged()
end

---@param targetName string|nil
function RunSharing:RegisterToReceive(targetName)
    local target = NormalizePlayerName(targetName)
        or NormalizePlayerName(CM:GetProfileSettingSafe("developer.mythicplus.runSharing.registerWith", nil))
    if not target then return end

    local payload = { type = "REGISTER", ts = time() }
    local serialized = self:Serialize(payload)
    if serialized then
        self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
    end
end

---@param targetName string|nil
---@param silent boolean|nil
function RunSharing:RegisterWithTarget(targetName, silent)
    local target = NormalizePlayerName(targetName)
        or NormalizePlayerName(CM:GetProfileSettingSafe("developer.mythicplus.runSharing.registerWith", nil))
    if not target then return end

    -- Send the registration request
    self:RegisterToReceive(target)

    -- Then ping the target so we can show a success/fail indicator (online + addon present)
    local payload = { type = "PING", silent = true, purpose = "REGISTER" }
    local serialized = self:Serialize(payload)
    if not serialized then return end

    self.registerWithTarget = target
    self.registerWithStatus = "PENDING"
    self._registerPingToken = (self._registerPingToken or 0) + 1
    local token = self._registerPingToken

    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
    NotifyConfigChanged()

    if not silent then
        print("|cff9580ffTwichUI:|r Sending registration request to " .. target .. "...")
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, function()
            if self.registerWithStatus == "PENDING" and self._registerPingToken == token then
                self.registerWithStatus = "FAILED"
                NotifyConfigChanged()
            end
        end)
    end
end

---@param targetName string|nil
---@param silent boolean|nil
function RunSharing:CheckRegistrationWithTarget(targetName, silent)
    local target = NormalizePlayerName(targetName)
        or NormalizePlayerName(CM:GetProfileSettingSafe("developer.mythicplus.runSharing.registerWith", nil))
    if not target then return end

    local payload = { type = "REG_QUERY", ts = time() }
    local serialized = self:Serialize(payload)
    if not serialized then return end

    self.registrationCheckTarget = target
    self.registrationCheckStatus = "PENDING"
    self.registrationCheckResult = nil
    self._registrationCheckToken = (self._registrationCheckToken or 0) + 1
    local token = self._registrationCheckToken

    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
    NotifyConfigChanged()

    if not silent then
        print("|cff9580ffTwichUI:|r Checking registration status with " .. target .. "...")
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(5, function()
            if self.registrationCheckStatus == "PENDING" and self._registrationCheckToken == token then
                self.registrationCheckStatus = "FAILED"
                NotifyConfigChanged()
            end
        end)
    end
end

---@param targetName string|nil
function RunSharing:UnregisterToReceive(targetName)
    local target = NormalizePlayerName(targetName)
        or NormalizePlayerName(CM:GetProfileSettingSafe("developer.mythicplus.runSharing.registerWith", nil))
    if not target then return end

    local payload = { type = "UNREGISTER", ts = time() }
    local serialized = self:Serialize(payload)
    if serialized then
        self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
    end
end

---@param runData table
---@param overrideReceiver string|nil
function RunSharing:SendRun(runData, overrideReceiver)
    local target = NormalizePlayerName(overrideReceiver) or NormalizePlayerName(self.receiver)
    if not target then return end

    if not overrideReceiver and self.receiver ~= target then
        self.receiver = target
        local db = GetDB()
        db.linkedReceiver = target
    end

    local serialized = self:Serialize(runData)
    if not serialized then
        Logger.Error("Run Sharing: Failed to serialize run data")
        return
    end

    Logger.Info("Sending run data to " .. target)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
end

function RunSharing:SendPing(silent)
    local target = NormalizePlayerName(self.receiver)
    if not target then return end

    if self.receiver ~= target then
        self.receiver = target
        local db = GetDB()
        db.linkedReceiver = target
    end

    local payload = { type = "PING", silent = silent }
    local serialized = self:Serialize(payload)
    if serialized then
        self.connectionStatus = "PENDING"
        self._lastPingTarget = target

        -- If this is the background (silent) ping, suppress the expected system error spam
        -- for a short window.
        if silent and CM:GetProfileSettingSafe("developer.mythicplus.runSharing.hidePlayerNotFound", true) then
            self._suppressPlayerNotFoundUntil = self._suppressPlayerNotFoundUntil or {}
            local now = (type(GetTime) == "function" and GetTime()) or 0
            local untilTime = now + 2.0
            self._suppressPlayerNotFoundUntil[target] = untilTime
            local baseName = GetBaseName(target)
            if baseName and baseName ~= target then
                self._suppressPlayerNotFoundUntil[baseName] = untilTime
            end
        end

        self:SendCommMessage(PREFIX, serialized, "WHISPER", target)

        if not silent then
            print("|cff9580ffTwichUI:|r Sending connection test to " .. target .. "...")
        end

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

    sender = NormalizePlayerName(sender)
    if not sender then return end

    local success, data = self:Deserialize(message)
    if not success then
        Logger.Error("Run Sharing: Failed to deserialize data from " .. tostring(sender))
        return
    end

    if type(data) == "table" then
        if data.type == "PING" then
            -- Reply with PONG
            local pong = { type = "PONG", silent = data.silent, purpose = data.purpose }
            local serialized = self:Serialize(pong)
            if serialized then
                self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
            end
            return
        elseif data.type == "PONG" then
            if data.purpose == "REGISTER" and self.registerWithTarget and sender == self.registerWithTarget then
                self.registerWithStatus = "SUCCESS"
                NotifyConfigChanged()
                if not data.silent then
                    print("|cff9580ffTwichUI:|r Registration target responded: " .. sender)
                end
            else
                -- Only treat PONG as a successful connection test if it came from our linked receiver
                -- (or the last ping target if set).
                local expected = self._lastPingTarget or NormalizePlayerName(self.receiver)
                if expected and sender ~= expected then
                    return
                end
                self.connectionStatus = "SUCCESS"
                if not data.silent then
                    print("|cff9580ffTwichUI:|r Connection confirmed! Received response from " .. sender)
                end
                local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
                    LibStub("AceConfigRegistry-3.0", true)
                if ACR then ACR:NotifyChange("ElvUI") end

                if self.OnConnectionEstablished then
                    self.OnConnectionEstablished:Invoke(sender)
                end
            end
            return
        elseif data.type == "ACK" then
            if self.OnRunAcknowledged then
                self.OnRunAcknowledged:Invoke(data.runId, sender)
            end
            return
        elseif data.type == "REG_QUERY" then
            if CM:GetProfileSettingSafe("developer.mythicplus.runSharing.ignoreRegistrations", false) then
                return
            end

            local isRegistered = false
            if type(self.registeredReceivers) == "table" then
                isRegistered = not not self.registeredReceivers[sender]
            end

            local resp = { type = "REG_STATUS", registered = isRegistered }
            local serialized = self:Serialize(resp)
            if serialized then
                self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
            end
            return
        elseif data.type == "REG_STATUS" then
            -- Response to our CheckRegistrationWithTarget().
            if self.registrationCheckTarget and sender ~= self.registrationCheckTarget then
                return
            end

            self.registrationCheckResult = not not data.registered
            self.registrationCheckStatus = (self.registrationCheckResult and "SUCCESS") or "FAILED"
            NotifyConfigChanged()
            return
        elseif data.type == "REGISTER" then
            if CM:GetProfileSettingSafe("developer.mythicplus.runSharing.ignoreRegistrations", false) then
                return
            end

            if type(self.registeredReceivers) ~= "table" then
                self.registeredReceivers = {}
            end

            -- Receiver registers directly with you (typically via WHISPER).
            self.registeredReceivers[sender] = time()
            Logger.Info("Run Sharing: " .. sender .. " registered to receive run logs")

            NotifyConfigChanged()

            if self.OnReceiverRegistered then
                self.OnReceiverRegistered:Invoke(sender)
            end
            return
        elseif data.type == "UNREGISTER" then
            if CM:GetProfileSettingSafe("developer.mythicplus.runSharing.ignoreRegistrations", false) then
                return
            end

            if type(self.registeredReceivers) == "table" then
                self.registeredReceivers[sender] = nil
            end

            NotifyConfigChanged()
            return
        end
    end

    self:ProcessReceivedRun(sender, data)
end

function RunSharing:ProcessReceivedRun(sender, runData)
    -- Basic validation
    if type(runData) ~= "table" or not runData.id then return end

    -- Send ACK
    local ack = { type = "ACK", runId = runData.id }
    local serialized = self:Serialize(ack)
    if serialized then
        self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
    end

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

    -- Play notification sound
    local sound = CM:GetProfileSettingSafe("developer.mythicplus.runSharing.sound", "None")
    if sound and sound ~= "None" then
        local LSM = T.Libs and T.Libs.LSM
        if LSM then
            local soundFile = LSM:Fetch("sound", sound)
            if soundFile then
                _G.PlaySoundFile(soundFile, "Master")
            end
        end
    end

    -- Notify UI if available
    if MythicPlusModule.RunSharingFrame and MythicPlusModule.RunSharingFrame.UpdateList then
        MythicPlusModule.RunSharingFrame:UpdateList()
    end
end
