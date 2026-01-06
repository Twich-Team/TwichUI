--[[
    RunLoggerSync handles opt-in synchronization of Mythic+ Run Logger data between players.

    Goals:
    - Cross-realm safe: always canonicalize to Name-Realm when possible.
    - Explicit consent: registration/add requests require an acknowledgement.
    - No chat spam: suppress "player not found" system messages for our background whispers.
    - Persistent pending queue: a configurable number of runs per peer are cached (default 5) until next successful sync.
]]

---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)
---@diagnostic disable: undefined-field, inject-field
local _G = _G

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")

---@class MythicPlusRunLoggerSyncSubmodule
---@field initialized boolean
local RunLoggerSync = MythicPlusModule.RunLoggerSync or {}
MythicPlusModule.RunLoggerSync = RunLoggerSync

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")
---@type ToolsModule
local Tools = T:GetModule("Tools")

local LibStub = _G.LibStub
local time = _G.time
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local C_Timer = _G.C_Timer
local strtrim = _G.strtrim
local ChatFrame_AddMessageEventFilter = _G.ChatFrame_AddMessageEventFilter
local ERR_CHAT_PLAYER_NOT_FOUND_S = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
local StaticPopupDialogs = _G.StaticPopupDialogs
local StaticPopup_Show = _G.StaticPopup_Show

local AceComm = LibStub("AceComm-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")

AceComm:Embed(RunLoggerSync)
AceSerializer:Embed(RunLoggerSync)

local PREFIX = "TWICH_RL_SYNC" -- <= 16 chars
local MAX_PENDING_PER_PEER = 5
local AUTO_SYNC_INTERVAL_SEC = 120
local CHECK_TIMEOUT_SEC = 5

local GetDB

local function NotifyConfigChanged()
    local ACR = (T.Libs and T.Libs.AceConfigRegistry) or LibStub("AceConfigRegistry-3.0-ElvUI", true) or
        LibStub("AceConfigRegistry-3.0", true)
    if ACR then
        ACR:NotifyChange("ElvUI")
    end
end

local REQUEST_POPUP_ID = "TWICHUI_RL_SYNC_INCOMING_REQUEST"

local function DescribeRequest(kind)
    if kind == "ADD_RECIPIENT" then
        return "They want to SEND you runs."
    end
    if kind == "REGISTER_ME" then
        return "They want you to SEND them runs."
    end
    return "Request: " .. tostring(kind)
end

local function EnsureRequestPopupDialog()
    if type(StaticPopupDialogs) ~= "table" then return end
    if StaticPopupDialogs[REQUEST_POPUP_ID] then return end

    StaticPopupDialogs[REQUEST_POPUP_ID] = {
        text = "Run Logger Sync request from %s:\n\n%s",
        button1 = "Accept",
        button2 = "Decline",
        OnAccept = function(_, payload)
            local sync = MythicPlusModule and MythicPlusModule.RunLoggerSync
            if sync and payload and payload.key and sync.AcceptRequest then
                sync:AcceptRequest(payload.key)
            end
            if sync and sync._OnRequestPopupResolved then
                sync:_OnRequestPopupResolved(payload and payload.key)
            end
        end,
        OnCancel = function(_, payload)
            local sync = MythicPlusModule and MythicPlusModule.RunLoggerSync
            if sync and payload and payload.key and sync.DenyRequest then
                sync:DenyRequest(payload.key)
            end
            if sync and sync._OnRequestPopupResolved then
                sync:_OnRequestPopupResolved(payload and payload.key)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function RunLoggerSync:_OnRequestPopupResolved(key)
    -- Clear the currently active popup marker and show the next queued request.
    if self._activeRequestPopupKey and (not key or key == self._activeRequestPopupKey) then
        self._activeRequestPopupKey = nil
    end
    self:_ShowNextRequestPopup()
end

function RunLoggerSync:_EnqueueRequestPopup(key)
    if type(key) ~= "string" or key == "" then return end
    self._requestPopupQueue = self._requestPopupQueue or {}

    -- Avoid duplicate enqueues.
    for _, existing in ipairs(self._requestPopupQueue) do
        if existing == key then
            return
        end
    end

    self._requestPopupQueue[#self._requestPopupQueue + 1] = key
    self:_ShowNextRequestPopup()
end

function RunLoggerSync:_ShowNextRequestPopup()
    if self._activeRequestPopupKey then return end

    EnsureRequestPopupDialog()
    if type(StaticPopup_Show) ~= "function" then return end

    local q = self._requestPopupQueue
    if type(q) ~= "table" or #q == 0 then return end

    local db = GetDB()

    while #q > 0 do
        local key = table.remove(q, 1)
        local req = db and db.sync and db.sync.pendingRequests and db.sync.pendingRequests[key] or nil
        if type(req) == "table" and type(req.from) == "string" and type(req.kind) == "string" then
            self._activeRequestPopupKey = key
            local payload = { key = key }
            StaticPopup_Show(REQUEST_POPUP_ID, req.from, DescribeRequest(req.kind), payload)
            return
        end
    end
end

local function GetMaxPendingPerPeer()
    local v = tonumber(CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.maxPendingPerPeer",
        MAX_PENDING_PER_PEER))
    if not v then
        v = MAX_PENDING_PER_PEER
    end
    v = math.floor(v)
    if v < 1 then v = 1 end
    if v > 50 then v = 50 end
    return v
end

local function ExtractRunId(data)
    if type(data) ~= "table" then return nil end
    if type(data.id) == "string" then
        return data.id
    end
    if type(data.run) == "table" and type(data.run.id) == "string" then
        return data.run.id
    end
    return nil
end

local FALLBACK_DB = { version = 1, sync = { peers = {}, pending = {}, pendingRequests = {} }, remoteRuns = {} }

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

    -- Normalize "Name - Realm" => "Name-Realm"
    name = name:gsub("%s*%-%s*", "-")
    -- Whisper targets never contain spaces.
    name = name:gsub("%s+", "")

    if name == "" then return nil end
    return name
end

local function GetPlayerRealm()
    local realm = (_G.GetNormalizedRealmName and _G.GetNormalizedRealmName())
        or (_G.GetRealmName and _G.GetRealmName())
    return NormalizePlayerName(realm)
end

---@param fullName any
---@return string|nil
local function CanonicalizeName(fullName)
    local s = NormalizePlayerName(fullName)
    if not s then return nil end
    if s:find("-", 1, true) then
        return s
    end

    local realm = GetPlayerRealm()
    if realm and realm ~= "" then
        return NormalizePlayerName(s .. "-" .. realm)
    end
    return s
end

---@param sender any
---@return string|nil
local function CanonicalizeSender(sender)
    -- AceComm often provides same-realm senders without realm. Canonicalize to Name-Realm.
    return CanonicalizeName(sender)
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

    if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S:find("%%s", 1, true) then
        local prefix, suffix = ERR_CHAT_PLAYER_NOT_FOUND_S:match("^(.-)%%s(.-)$")
        if prefix and suffix then
            return msg == (prefix .. name .. suffix)
        end
    end

    -- Fallback (enUS-style)
    local extracted = msg:match("^No player named '(.+)' is currently playing%.$")
    return extracted == name
end

---@return TwichUIRunLoggerDB
GetDB = function()
    local profile = (T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.runLoggerDB = profile.mythicPlus.runLoggerDB or {}
        local db = profile.mythicPlus.runLoggerDB

        if type(db.version) ~= "number" then
            db.version = 1
        end

        db.sync = db.sync or {}
        db.sync.peers = db.sync.peers or {}
        db.sync.pending = db.sync.pending or {}
        db.sync.pendingRequests = db.sync.pendingRequests or {}
        db.remoteRuns = db.remoteRuns or {}

        return db
    end

    -- Fallback: in-memory only (should be rare).
    return FALLBACK_DB
end

function RunLoggerSync:ClearDatabase()
    local db = GetDB()
    for k in pairs(db) do
        db[k] = nil
    end
    db.version = 1
    db.active = nil
    db.lastCompleted = nil
    db.sync = { peers = {}, pending = {}, pendingRequests = {} }
    db.remoteRuns = {}

    -- Reset in-memory sync state so UI reflects the cleared DB immediately.
    self._pendingPings = nil
    self._awaitingAddRecipientAck = nil
    self._awaitingRegisterMeAck = nil
    self._checkRequests = nil
    self._checkResults = nil

    self.checkTarget = nil
    self.checkStatus = nil
    self.checkResult = nil

    Logger.Info("Run Logger database cleared.")
end

---@param fullName string
---@return table
function RunLoggerSync:_EnsurePeer(fullName)
    local db = GetDB()
    db.sync.peers[fullName] = db.sync.peers[fullName] or {}
    local peer = db.sync.peers[fullName]
    peer.name = fullName
    peer.lastSeen = tonumber(peer.lastSeen) or nil
    peer.allowOutgoing = not not peer.allowOutgoing -- we send to them
    peer.allowIncoming = not not peer.allowIncoming -- we accept from them
    peer.addedAt = tonumber(peer.addedAt) or time()
    return peer
end

---@return string[]
function RunLoggerSync:GetPeerNames()
    local db = GetDB()
    local out = {}
    for name, rec in pairs(db.sync.peers) do
        if type(name) == "string" and name ~= "" and type(rec) == "table" then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

---@return table<string, string>
function RunLoggerSync:GetPeerDisplayValues()
    local db = GetDB()
    local values = {}
    for _, name in ipairs(self:GetPeerNames()) do
        local peer = db.sync.peers[name]
        local sendFlag = (peer and peer.allowOutgoing) and "Send" or ""
        local recvFlag = (peer and peer.allowIncoming) and "Recv" or ""
        local flags
        if sendFlag ~= "" and recvFlag ~= "" then
            flags = "[Send/Recv]"
        elseif sendFlag ~= "" then
            flags = "[Send]"
        elseif recvFlag ~= "" then
            flags = "[Recv]"
        else
            flags = "[None]"
        end

        local sendingSuffix = ""
        local status, isOnTheirList
        if self.GetCheckResult then
            status, isOnTheirList = self:GetCheckResult(name)
        end
        if status == "PENDING" then
            sendingSuffix = " (sending: ?)"
        elseif status == "FAILED" then
            sendingSuffix = " (sending: timeout)"
        elseif status == "SUCCESS" then
            sendingSuffix = isOnTheirList and " (sending: yes)" or " (sending: no)"
        end

        values[name] = name .. " " .. flags .. sendingSuffix
    end
    return values
end

---@param targetName string
---@return boolean
function RunLoggerSync:IsAllowIncoming(targetName)
    local target = self:_NormalizeTarget(targetName)
    if not target then return false end
    local db = GetDB()
    local peer = db.sync.peers and db.sync.peers[target] or nil
    return not not (peer and peer.allowIncoming)
end

---@param name string
function RunLoggerSync:RemovePeer(name)
    local full = CanonicalizeName(name)
    if not full then return end

    local db = GetDB()
    db.sync.peers[full] = nil
    db.sync.pending[full] = nil

    -- Remove pending requests from this sender.
    for key, req in pairs(db.sync.pendingRequests) do
        if type(req) == "table" and req.from == full then
            db.sync.pendingRequests[key] = nil
        end
    end
end

---@param targetName string
---@return string|nil
function RunLoggerSync:_NormalizeTarget(targetName)
    return CanonicalizeName(targetName)
end

---@param target string
---@param seconds number
function RunLoggerSync:_SuppressNotFoundFor(target, seconds)
    if not CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.hidePlayerNotFound", true) then
        return
    end

    self._suppressPlayerNotFoundUntil = self._suppressPlayerNotFoundUntil or {}
    local now = (type(GetTime) == "function" and GetTime()) or 0
    local untilTime = now + (tonumber(seconds) or 2.0)

    self._suppressPlayerNotFoundUntil[target] = untilTime

    local baseName = GetBaseName(target)
    if baseName and baseName ~= target then
        self._suppressPlayerNotFoundUntil[baseName] = untilTime
    end
end

---@param name string
function RunLoggerSync:_MarkPeerNotFound(name)
    -- Mark last failure; ping timeouts/queues will handle the rest.
    if type(name) ~= "string" or name == "" then
        return
    end

    self._lastNotFoundAt = self._lastNotFoundAt or {}
    self._lastNotFoundAt[name] = (type(GetTime) == "function" and GetTime()) or 0

    -- Fail any in-flight ping waiting on this target.
    -- Important: system messages often omit realm even if the target includes it.
    local pendingPings = self._pendingPings
    if type(pendingPings) ~= "table" then
        return
    end

    local base = GetBaseName(NormalizePlayerName(name) or name)

    for target, pending in pairs(pendingPings) do
        if target == name or (base and base ~= "" and GetBaseName(target) == base) then
            pendingPings[target] = nil
            if type(pending) == "table" and type(pending.onFail) == "function" then
                pending.onFail("not_found")
            end
        end
    end
end

function RunLoggerSync:_InstallSystemFilter()
    if self._systemFilterInstalled or type(ChatFrame_AddMessageEventFilter) ~= "function" then
        return
    end

    self._systemFilterInstalled = true
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg, ...)
        if not CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.hidePlayerNotFound", true) then
            return false
        end

        local suppress = self._suppressPlayerNotFoundUntil
        if type(suppress) ~= "table" then
            return false
        end

        local now = (type(GetTime) == "function" and GetTime()) or 0

        for name, untilTime in pairs(suppress) do
            if untilTime and now <= untilTime and MatchesPlayerNotFound(msg, name) then
                -- Treat as an offline/not-found signal for our background comms.
                self:_MarkPeerNotFound(name)
                return true
            end
        end

        -- Cleanup expired entries.
        for name, untilTime in pairs(suppress) do
            if not untilTime or now > untilTime then
                suppress[name] = nil
            end
        end

        return false
    end)
end

---@param from string
---@param kind string
---@return string
local function RequestKey(from, kind)
    return tostring(from) .. ":" .. tostring(kind)
end

---@return table<string, {from:string, kind:string, ts:number}>
function RunLoggerSync:GetPendingRequests()
    local db = GetDB()
    return db.sync.pendingRequests
end

---@return table<string, string>
function RunLoggerSync:GetPendingRequestDisplayValues()
    local db = GetDB()
    local values = {}
    for key, req in pairs(db.sync.pendingRequests) do
        if type(req) == "table" and type(req.from) == "string" and type(req.kind) == "string" then
            local label
            if req.kind == "ADD_RECIPIENT" then
                label = req.from .. " wants to SEND you runs"
            elseif req.kind == "REGISTER_ME" then
                label = req.from .. " wants you to SEND them runs"
            else
                label = req.from .. " request: " .. tostring(req.kind)
            end
            values[key] = label
        end
    end
    return values
end

---@param key string
---@param accepted boolean
function RunLoggerSync:_RespondToRequest(key, accepted)
    local db = GetDB()
    local req = db.sync.pendingRequests[key]
    if type(req) ~= "table" then return end

    local from = req.from
    local kind = req.kind
    db.sync.pendingRequests[key] = nil

    if not from or not kind then return end

    if kind == "ADD_RECIPIENT" then
        -- We are the receiver; if accepted, allow incoming runs from them.
        if accepted then
            local peer = self:_EnsurePeer(from)
            peer.allowIncoming = true
            peer.lastSeen = time()
        end

        local payload = { type = "ADD_RECIPIENT_ACK", accepted = not not accepted }
        local serialized = self:Serialize(payload)
        if serialized then
            self:_SuppressNotFoundFor(from, 2.0)
            self:SendCommMessage(PREFIX, serialized, "WHISPER", from)
        end
        NotifyConfigChanged()
        return
    end

    if kind == "REGISTER_ME" then
        -- We are the sender; if accepted, add them to outgoing list.
        if accepted then
            local peer = self:_EnsurePeer(from)
            peer.allowOutgoing = true
            peer.lastSeen = time()
        end

        local payload = { type = "REGISTER_ME_ACK", accepted = not not accepted }
        local serialized = self:Serialize(payload)
        if serialized then
            self:_SuppressNotFoundFor(from, 2.0)
            self:SendCommMessage(PREFIX, serialized, "WHISPER", from)
        end
        NotifyConfigChanged()
        return
    end
end

---@param key string
function RunLoggerSync:AcceptRequest(key)
    self:_RespondToRequest(key, true)
end

---@param key string
function RunLoggerSync:DenyRequest(key)
    self:_RespondToRequest(key, false)
end

---@param targetName string
function RunLoggerSync:RequestAddRecipient(targetName)
    self:Initialize()
    local target = self:_NormalizeTarget(targetName)
    if not target then return end

    local payload = { type = "ADD_RECIPIENT_REQ", ts = time() }
    local serialized = self:Serialize(payload)
    if not serialized then return end

    self:_SuppressNotFoundFor(target, 2.0)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)

    -- Track locally as "pending ack".
    self._awaitingAddRecipientAck = self._awaitingAddRecipientAck or {}
    self._awaitingAddRecipientAck[target] = true
end

---@param targetName string
function RunLoggerSync:RequestRegisterWithSender(targetName)
    self:Initialize()
    local target = self:_NormalizeTarget(targetName)
    if not target then return end

    local payload = { type = "REGISTER_ME_REQ", ts = time() }
    local serialized = self:Serialize(payload)
    if not serialized then return end

    self:_SuppressNotFoundFor(target, 2.0)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)

    self._awaitingRegisterMeAck = self._awaitingRegisterMeAck or {}
    self._awaitingRegisterMeAck[target] = true
end

---@param targetName string
function RunLoggerSync:AllowIncomingFrom(targetName)
    local target = self:_NormalizeTarget(targetName)
    if not target then return end

    local peer = self:_EnsurePeer(target)
    peer.allowIncoming = true
    peer.lastSeen = time()
end

---@param target string
---@param focus boolean|nil
function RunLoggerSync:_StartCheck(target, focus)
    if not target then return end

    self._checkToken = (self._checkToken or 0) + 1
    local token = self._checkToken

    self._checkRequests = self._checkRequests or {}
    self._checkResults = self._checkResults or {}

    self._checkRequests[token] = {
        target = target,
        focus = not not focus,
        startedAt = time(),
    }

    self._checkResults[target] = {
        status = "PENDING",
        result = nil,
        updatedAt = time(),
    }

    if focus then
        self.checkTarget = target
        self.checkStatus = "PENDING"
        self.checkResult = nil
    end

    NotifyConfigChanged()

    local payload = { type = "CHECK_REQ", ts = time(), token = token }
    local serialized = self:Serialize(payload)
    if not serialized then
        local checkRequests = self._checkRequests
        if type(checkRequests) == "table" then
            checkRequests[token] = nil
        end
        self._checkResults[target] = { status = "FAILED", result = nil, updatedAt = time() }
        if focus then
            self.checkStatus = "FAILED"
        end
        NotifyConfigChanged()
        return
    end

    self:_SuppressNotFoundFor(target, 2.0)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(CHECK_TIMEOUT_SEC, function()
            local checkRequests = self._checkRequests
            local req = (type(checkRequests) == "table") and checkRequests[token] or nil
            if not req then return end

            checkRequests[token] = nil

            local t = req.target
            if t then
                self._checkResults = self._checkResults or {}
                self._checkResults[t] = { status = "FAILED", result = nil, updatedAt = time() }
            end

            if req.focus then
                self.checkStatus = "FAILED"
            end

            NotifyConfigChanged()
        end)
    end
end

---@param targetName string
function RunLoggerSync:CheckIfOnList(targetName)
    local target = self:_NormalizeTarget(targetName)
    if not target then return end
    self:_StartCheck(target, true)
end

function RunLoggerSync:CheckAllPeers()
    local db = GetDB()
    for name, peer in pairs(db.sync.peers) do
        if type(name) == "string" and type(peer) == "table" then
            local target = CanonicalizeName(name)
            if target then
                self:_StartCheck(target, false)
            end
        end
    end
end

---@param targetName string
---@return string|nil status "PENDING"|"SUCCESS"|"FAILED"|nil
---@return boolean|nil isOnTheirList
function RunLoggerSync:GetCheckResult(targetName)
    local target = self:_NormalizeTarget(targetName)
    if not target then return nil, nil end
    local r = self._checkResults and self._checkResults[target] or nil
    if type(r) ~= "table" then
        return nil, nil
    end
    return r.status, r.result
end

---@param target string
---@param purpose string
---@param onSuccess function|nil
---@param onFail function|nil
function RunLoggerSync:_Ping(target, purpose, onSuccess, onFail)
    if not target then return end

    self._pendingPings = self._pendingPings or {}

    self._pingToken = (self._pingToken or 0) + 1
    local token = self._pingToken

    self._pendingPings[target] = {
        token = token,
        purpose = purpose,
        onSuccess = onSuccess,
        onFail = onFail,
    }

    local payload = { type = "PING", token = token, purpose = purpose, silent = true }
    local serialized = self:Serialize(payload)
    if not serialized then
        self._pendingPings[target] = nil
        return
    end

    self:_SuppressNotFoundFor(target, 2.0)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(3, function()
            local pending = self._pendingPings and self._pendingPings[target]
            if pending and pending.token == token then
                self._pendingPings[target] = nil
                if type(pending.onFail) == "function" then
                    pending.onFail("timeout")
                end
            end
        end)
    end
end

---@param target string
---@param run TwichUIRunLogger_Run
function RunLoggerSync:_QueueRun(target, run)
    if not target or type(run) ~= "table" or not run.id then return end

    local db = GetDB()
    db.sync.pending[target] = db.sync.pending[target] or {}
    local q = db.sync.pending[target]

    q[#q + 1] = {
        id = run.id,
        run = run,
        queuedAt = time(),
    }

    local max = GetMaxPendingPerPeer()
    while #q > max do
        table.remove(q, 1)
    end
end

---@param targetName string
---@param count number|nil
function RunLoggerSync:RequestRecentRuns(targetName, count)
    self:Initialize()
    local target = self:_NormalizeTarget(targetName)
    if not target then return end

    self._recentReqToken = (self._recentReqToken or 0) + 1
    local token = self._recentReqToken

    local n = tonumber(count)
    if not n then
        n = tonumber(CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.requestRecentCount", 5)) or 5
    end
    n = math.floor(n)
    if n < 1 then n = 1 end
    if n > 25 then n = 25 end

    local payload = { type = "RECENT_RUNS_REQ", token = token, count = n }
    local serialized = self:Serialize(payload)
    if not serialized then
        return
    end

    self:_SuppressNotFoundFor(target, 2.0)
    self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
    Logger.Info("Requested recent runs from " .. target .. " (count=" .. tostring(n) .. ")")
end

---@param target string
function RunLoggerSync:_FlushPending(target)
    local db = GetDB()
    local q = db.sync.pending[target]
    if type(q) ~= "table" or #q == 0 then return end

    for _, entry in ipairs(q) do
        if type(entry) == "table" and type(entry.run) == "table" then
            local payload = { type = "RUN", run = entry.run, runId = entry.id }
            local serialized = self:Serialize(payload)
            if serialized then
                self:_SuppressNotFoundFor(target, 2.0)
                self:SendCommMessage(PREFIX, serialized, "WHISPER", target)
            end
        end
    end
end

---@param run TwichUIRunLogger_Run
function RunLoggerSync:OnRunFinalized(run)
    if type(run) ~= "table" or not run.id then return end

    local db = GetDB()

    for name, peer in pairs(db.sync.peers) do
        if type(name) == "string" and type(peer) == "table" and peer.allowOutgoing then
            local target = CanonicalizeName(name)
            if target then
                self:_QueueRun(target, run)
                self:_Ping(target, "SYNC", function()
                    self:_FlushPending(target)
                end, function()
                    -- Leave queued for later.
                end)
            end
        end
    end
end

function RunLoggerSync:SyncAll()
    local db = GetDB()
    for name, peer in pairs(db.sync.peers) do
        if type(name) == "string" and type(peer) == "table" and peer.allowOutgoing then
            local target = CanonicalizeName(name)
            if target then
                self:_Ping(target, "SYNC_NOW", function()
                    self:_FlushPending(target)
                end)
            end
        end
    end
end

function RunLoggerSync:_AutoSyncTick()
    local db = GetDB()
    local now = time()

    for name, peer in pairs(db.sync.peers) do
        if type(name) == "string" and type(peer) == "table" and peer.allowOutgoing then
            local target = CanonicalizeName(name)
            local q = target and db.sync.pending[target] or nil
            if target and type(q) == "table" and #q > 0 then
                local lastAttempt = tonumber(peer.lastAutoSyncAttempt) or 0
                if (now - lastAttempt) >= AUTO_SYNC_INTERVAL_SEC then
                    peer.lastAutoSyncAttempt = now
                    self:_Ping(target, "AUTO_SYNC", function()
                        self:_FlushPending(target)
                    end)
                end
            end
        end
    end
end

---@param target string
---@param runId string
function RunLoggerSync:_HandleRunAck(target, runId)
    local db = GetDB()
    local q = db.sync.pending[target]
    if type(q) ~= "table" or type(runId) ~= "string" then return end

    for i = #q, 1, -1 do
        local e = q[i]
        if type(e) == "table" and e.id == runId then
            table.remove(q, i)
        end
    end
end

---@param sender string
---@param runData table
function RunLoggerSync:_ProcessReceivedRun(sender, runData)
    if type(runData) ~= "table" then return end

    local run = runData.run or runData
    if type(run) ~= "table" or not run.id then
        return
    end

    local db = GetDB()
    local peer = db.sync.peers[sender]

    -- Only accept run data from authorized senders.
    if not peer or not peer.allowIncoming then
        return
    end

    -- Best-effort: resolve dungeon name (compat with older payloads).
    local mapId = tonumber(run.mapId or run.mapID)
    if mapId and (not run.dungeonName or run.dungeonName == "Unknown" or run.dungeonName == "Unknown Dungeon") then
        local name
        local mpData = MythicPlusModule and MythicPlusModule.Data
        if mpData and type(mpData.GetMapNameCached) == "function" then
            name = mpData.GetMapNameCached(mapId)
        end
        if not name and _G.C_ChallengeMode and type(_G.C_ChallengeMode.GetMapUIInfo) == "function" then
            name = _G.C_ChallengeMode.GetMapUIInfo(mapId)
        end
        if name then
            run.dungeonName = name
        end
    end

    local runId = run.id
    local inserted = false
    do
        local alreadyHave = false
        for _, entry in ipairs(db.remoteRuns) do
            if type(entry) == "table" then
                local existingId = ExtractRunId(entry.data)
                if existingId and existingId == runId then
                    alreadyHave = true
                    break
                end
            end
        end

        if not alreadyHave then
            table.insert(db.remoteRuns, {
                sender = sender,
                receivedAt = time(),
                data = run,
            })
            inserted = true
        end
    end

    if inserted then
        do
            local dungeon = tostring(run.dungeonName or "Mythic+")
            local level = tonumber(run.level) or (type(run.completion) == "table" and tonumber(run.completion.level))
            local levelStr = level and (" +" .. tostring(level)) or ""
            print("|cff9580ffTwichUI:|r Received run from " .. tostring(sender) .. " (" .. dungeon .. levelStr .. ")")
        end

        local enabled = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.incomingSoundEnable", false)
        if enabled then
            local sound = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.incomingSound", "Game Error")
            if sound and sound ~= "None" then
                local LSM = T.Libs and T.Libs.LSM
                if LSM then
                    local soundFile = LSM:Fetch("sound", sound)
                    if soundFile then
                        _G.PlaySoundFile(soundFile, "Master")
                    end
                end
            end
        end
    end

    -- ACK
    local ack = { type = "RUN_ACK", runId = run.id }
    local serialized = self:Serialize(ack)
    if serialized then
        self:_SuppressNotFoundFor(sender, 2.0)
        self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
    end

    -- Notify UI if available (RunSharingFrame is legacy; keep compatibility)
    if inserted and MythicPlusModule.RunSharingFrame and MythicPlusModule.RunSharingFrame.UpdateList then
        MythicPlusModule.RunSharingFrame:UpdateList()
    end
end

function RunLoggerSync:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= PREFIX then return end

    sender = CanonicalizeSender(sender)
    if not sender then return end

    local ok, data = self:Deserialize(message)
    if not ok then
        return
    end

    local db = GetDB()
    local peer = self:_EnsurePeer(sender)
    peer.lastSeen = time()

    if type(data) ~= "table" then
        return
    end

    if data.type == "PING" then
        local pong = { type = "PONG", token = data.token, purpose = data.purpose, silent = true }
        local serialized = self:Serialize(pong)
        if serialized then
            self:_SuppressNotFoundFor(sender, 2.0)
            self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
        end
        return
    end

    if data.type == "PONG" then
        local pending = self._pendingPings and self._pendingPings[sender]
        if pending and pending.token == data.token then
            self._pendingPings[sender] = nil
            if type(pending.onSuccess) == "function" then
                pending.onSuccess()
            end
        end
        return
    end

    if data.type == "ADD_RECIPIENT_REQ" then
        if CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.ignoreRegistrations", false) then
            return
        end

        local key = RequestKey(sender, "ADD_RECIPIENT")
        if not db.sync.pendingRequests[key] then
            db.sync.pendingRequests[key] = { from = sender, kind = "ADD_RECIPIENT", ts = time() }
            self:_EnqueueRequestPopup(key)
            NotifyConfigChanged()
        end
        return
    end

    if data.type == "REGISTER_ME_REQ" then
        if CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.ignoreRegistrations", false) then
            return
        end

        local key = RequestKey(sender, "REGISTER_ME")
        if not db.sync.pendingRequests[key] then
            db.sync.pendingRequests[key] = { from = sender, kind = "REGISTER_ME", ts = time() }
            self:_EnqueueRequestPopup(key)
            NotifyConfigChanged()
        end
        return
    end

    if data.type == "ADD_RECIPIENT_ACK" then
        -- We initiated RequestAddRecipient(); if accepted, we will send to them.
        if self._awaitingAddRecipientAck and self._awaitingAddRecipientAck[sender] then
            self._awaitingAddRecipientAck[sender] = nil
            if data.accepted then
                local p = self:_EnsurePeer(sender)
                p.allowOutgoing = true
                p.lastSeen = time()
            end
        end
        return
    end

    if data.type == "REGISTER_ME_ACK" then
        -- We initiated RequestRegisterWithSender(); if accepted, allow incoming runs from them.
        if self._awaitingRegisterMeAck and self._awaitingRegisterMeAck[sender] then
            self._awaitingRegisterMeAck[sender] = nil
            if data.accepted then
                local p = self:_EnsurePeer(sender)
                p.allowIncoming = true
                p.lastSeen = time()
            end
        end
        return
    end

    if data.type == "CHECK_REQ" then
        -- Sender asks: "am I on your outgoing (recipient) list?"
        local isRecipient = false
        local p = db.sync.peers[sender]
        if p and p.allowOutgoing then
            isRecipient = true
        end

        local resp = { type = "CHECK_RESP", token = data.token, isRecipient = isRecipient }
        local serialized = self:Serialize(resp)
        if serialized then
            self:_SuppressNotFoundFor(sender, 2.0)
            self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
        end
        return
    end

    if data.type == "CHECK_RESP" then
        local token = tonumber(data.token)
        local req = token and self._checkRequests and self._checkRequests[token] or nil

        -- If we have a matching in-flight request, validate sender and update that target.
        if type(req) == "table" and type(req.target) == "string" then
            if sender ~= req.target then
                return
            end

            local checkRequests = self._checkRequests
            if token and type(checkRequests) == "table" then
                checkRequests[token] = nil
            end

            self._checkResults = self._checkResults or {}
            self._checkResults[sender] = {
                status = "SUCCESS",
                result = not not data.isRecipient,
                updatedAt = time(),
            }

            if req.focus then
                self.checkTarget = sender
                self.checkResult = not not data.isRecipient
                self.checkStatus = "SUCCESS"
            end

            NotifyConfigChanged()
            return
        end

        -- Fallback: update last-known result by sender.
        self._checkResults = self._checkResults or {}
        self._checkResults[sender] = {
            status = "SUCCESS",
            result = not not data.isRecipient,
            updatedAt = time(),
        }

        if self.checkTarget and sender == self.checkTarget then
            self.checkResult = not not data.isRecipient
            self.checkStatus = "SUCCESS"
        end

        NotifyConfigChanged()
        return
    end

    if data.type == "RUN_ACK" then
        self:_HandleRunAck(sender, data.runId)
        return
    end

    if data.type == "RECENT_RUNS_REQ" then
        local db = GetDB()
        local peer = db.sync.peers and db.sync.peers[sender] or nil

        -- Only send runs to peers we've explicitly allowed outgoing.
        if not (peer and peer.allowOutgoing) then
            return
        end

        local count = math.floor(tonumber(data.count) or 5)
        if count < 1 then count = 1 end
        if count > 25 then count = 25 end

        local history = db.runHistory
        local runsToSend = {}
        if type(history) == "table" and #history > 0 then
            local startIndex = #history - count + 1
            if startIndex < 1 then startIndex = 1 end
            for i = startIndex, #history do
                local r = history[i]
                if type(r) == "table" and r.id then
                    runsToSend[#runsToSend + 1] = r
                end
            end
        elseif type(db.lastCompleted) == "table" and db.lastCompleted.id then
            runsToSend[1] = db.lastCompleted
        end

        for _, r in ipairs(runsToSend) do
            local payload = { type = "RUN", run = r, runId = r.id }
            local serialized = self:Serialize(payload)
            if serialized then
                self:_SuppressNotFoundFor(sender, 2.0)
                self:SendCommMessage(PREFIX, serialized, "WHISPER", sender)
            end
        end

        Logger.Info("Sent recent runs to " .. sender .. " (count=" .. tostring(#runsToSend) .. ")")
        return
    end

    if data.type == "RUN" then
        self:_ProcessReceivedRun(sender, data)
        return
    end

    -- Back-compat: accept flat run table.
    self:_ProcessReceivedRun(sender, data)
end

function RunLoggerSync:Initialize()
    if self.initialized then return end
    self.initialized = true

    self:_InstallSystemFilter()

    self:RegisterComm(PREFIX, "OnCommReceived")

    if not self._autoSyncTicker and C_Timer and type(C_Timer.NewTicker) == "function" then
        self._autoSyncTicker = C_Timer.NewTicker(AUTO_SYNC_INTERVAL_SEC, function()
            self:_AutoSyncTick()
        end)
    end

    -- Best-effort migration: normalize any stored peer keys.
    local db = GetDB()
    local migrated = {}
    for name, rec in pairs(db.sync.peers) do
        if type(name) == "string" and type(rec) == "table" then
            local normalized = CanonicalizeName(name) or name
            if normalized ~= name then
                migrated[#migrated + 1] = { from = name, to = normalized, rec = rec }
            end
        end
    end
    for _, m in ipairs(migrated) do
        if db.sync.peers[m.to] == nil then
            db.sync.peers[m.to] = m.rec
        end
        db.sync.peers[m.from] = nil
    end
end
