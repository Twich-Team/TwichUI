--[[
    Mythic+ Simulator replays an exported TwichUI Mythic+ run log (TwichUI_RunLog_v2)
    and forwards events through the MythicPlus DungeonMonitor callback pipeline.

    This is a developer tool to help validate downstream modules and to iterate on
    systems without repeatedly running live keys.
]]

---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

local _G = _G
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusSimulatorSubmodule
---@field enabled boolean
---@field SupportedEvents string[]
---@field SimEvent fun(self:MythicPlusSimulatorSubmodule, eventName:string)
---@field _frame Frame|nil
---@field _editBox EditBox|nil
---@field _simToken number|nil
---@field _simState table|nil
---@field _restoreRunLoggerEnabled boolean|nil
---@field _callbacks table<string, fun(event:string, ...)>|nil
local Sim = MythicPlusModule.Simulator or {}
MythicPlusModule.Simulator = Sim

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ToolsModule
local Tools = T:GetModule("Tools")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")

Sim._callbacks = {}

function Sim:RegisterCallback(name, func)
    if type(name) == "string" and type(func) == "function" then
        self._callbacks[name] = func
    end
end

function Sim:UnregisterCallback(name)
    if type(name) == "string" then
        self._callbacks[name] = nil
    end
end

function Sim:_FireCallback(event, ...)
    for _, func in pairs(self._callbacks) do
        if type(func) == "function" then
            pcall(func, event, ...)
        end
    end
end

---@return MythicPlusDungeonMonitorSubmodule|nil
local function GetDungeonMonitor()
    if MythicPlusModule and MythicPlusModule.DungeonMonitor then
        return MythicPlusModule.DungeonMonitor
    end

    local ok, mp = pcall(function() return T:GetModule("MythicPlus") end)
    if ok and mp then
        return mp.DungeonMonitor
    end

    return nil
end

---@type table<string, ConfigEntry>
local CONFIGURATION = {
    PLAYBACK_SPEED = { key = "developer.mythicplus.simulator.playbackSpeed", default = 10 },
}

local Module = Tools.Generics.Module:New(CONFIGURATION)

-- Back-compat for the Developer -> Testing panel.
-- This list is used to populate a dropdown of "single event" simulations.
Sim.SupportedEvents = Sim.SupportedEvents or {
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_COMPLETED_REWARDS",
    "CHALLENGE_MODE_RESET",
    "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "PLAYER_DEAD",
    "GROUP_ROSTER_UPDATE",
    "CHAT_MSG_LOOT",
}

---@param eventName string
---@return any ...
local function BuildSampleEventArgs(eventName)
    if eventName == "CHALLENGE_MODE_START" then
        local mapID = 525
        -- Simulate the resolution event first
        local name = C_ChallengeMode.GetMapUIInfo(mapID) or "Simulated Dungeon"

        local dm = GetDungeonMonitor()
        if dm and type(dm.EventHandler) == "function" then
            dm:EventHandler("TWICH_DUNGEON_START", mapID, name)
        end

        return mapID
    end

    if eventName == "CHALLENGE_MODE_COMPLETED" then
        return nil
    end

    if eventName == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        return 5
    end

    if eventName == "CHALLENGE_MODE_COMPLETED_REWARDS" then
        local mapID = 525
        local medal = 3
        local timeMS = 1500000
        local money = 500000
        local rewards = {
            {
                rewardID = 32837,
                quantity = 1,
                displayInfoID = nil,
                isCurrency = false,
            },
        }
        return mapID, medal, timeMS, money, rewards
    end

    if eventName == "CHALLENGE_MODE_RESET" then
        return 525
    end

    if eventName == "ENCOUNTER_START" then
        return 1, "Boss", 8, 5
    end

    if eventName == "ENCOUNTER_END" then
        return 1, "Boss", 8, 5, 1
    end

    if eventName == "PLAYER_DEAD" then
        return nil
    end

    if eventName == "GROUP_ROSTER_UPDATE" then
        return nil
    end

    if eventName == "CHAT_MSG_LOOT" then
        return "You receive loot: [Example Item]", "Player-Realm"
    end

    return nil
end

--- Simulate a single supported event (developer testing helper).
---@param eventName string
function Sim:SimEvent(eventName)
    eventName = tostring(eventName or "")
    if eventName == "" then
        Logger.Warn("Simulator: no event provided")
        return
    end

    -- Ensure Mythic+ + DungeonMonitor are enabled so callbacks fire normally.
    if MythicPlusModule and type(MythicPlusModule.IsEnabled) == "function" and type(MythicPlusModule.Enable) == "function" then
        if not MythicPlusModule:IsEnabled() then
            MythicPlusModule:Enable()
        end
    end
    local dungeonMonitor = GetDungeonMonitor()
    if dungeonMonitor and type(dungeonMonitor.Enable) == "function" and not dungeonMonitor.enabled then
        dungeonMonitor:Enable()
    end

    if not dungeonMonitor
        or (type(dungeonMonitor.SimulateEvent) ~= "function" and type(dungeonMonitor.EventHandler) ~= "function") then
        Logger.Error("Simulator: DungeonMonitor not available")
        return
    end

    Logger.Debug("Simulator: simulating event: " .. eventName)
    local a1, a2, a3, a4, a5 = BuildSampleEventArgs(eventName)

    if type(dungeonMonitor.SimulateEvent) == "function" then
        dungeonMonitor:SimulateEvent(eventName, a1, a2, a3, a4, a5)
    else
        dungeonMonitor:EventHandler(eventName, a1, a2, a3, a4, a5)
    end
end

local function ClampNumber(v, min, max, fallback)
    v = tonumber(v)
    if type(v) ~= "number" then
        return fallback
    end
    if v < min then return min end
    if v > max then return max end
    return v
end

-- ----------------------------
-- Minimal JSON decoder
-- ----------------------------

---@param s string
---@param i number
---@return number
local function SkipWS(s, i)
    while true do
        local c = s:sub(i, i)
        if c == "" then return i end
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then
            return i
        end
        i = i + 1
    end
end

---@param s string
---@param i number
---@return string|nil
---@return number
---@return string|nil
local function ParseString(s, i)
    if s:sub(i, i) ~= '"' then
        return nil, i, "expected string"
    end
    i = i + 1
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then
            return nil, i, "unterminated string"
        end
        if c == '"' then
            i = i + 1
            return table.concat(out), i, nil
        end
        if c == "\\" then
            local esc = s:sub(i + 1, i + 1)
            if esc == '"' or esc == "\\" or esc == "/" then
                out[#out + 1] = esc
                i = i + 2
            elseif esc == "b" then
                out[#out + 1] = "\b"; i = i + 2
            elseif esc == "f" then
                out[#out + 1] = "\f"; i = i + 2
            elseif esc == "n" then
                out[#out + 1] = "\n"; i = i + 2
            elseif esc == "r" then
                out[#out + 1] = "\r"; i = i + 2
            elseif esc == "t" then
                out[#out + 1] = "\t"; i = i + 2
            elseif esc == "u" then
                local hex = s:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then
                    return nil, i, "invalid unicode escape"
                end
                local code = tonumber(hex, 16)
                -- Best-effort: keep ASCII; otherwise replace with '?'
                if code and code >= 32 and code <= 126 then
                    out[#out + 1] = string.char(code)
                else
                    out[#out + 1] = "?"
                end
                i = i + 6
            else
                return nil, i, "invalid escape"
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

---@param s string
---@param i number
---@return number|nil
---@return number
---@return string|nil
local function ParseNumber(s, i)
    local start = i
    local c = s:sub(i, i)
    if c == "-" then
        i = i + 1
    end
    while s:sub(i, i):match("%d") do
        i = i + 1
    end
    if s:sub(i, i) == "." then
        i = i + 1
        while s:sub(i, i):match("%d") do
            i = i + 1
        end
    end
    local exp = s:sub(i, i)
    if exp == "e" or exp == "E" then
        i = i + 1
        local sign = s:sub(i, i)
        if sign == "+" or sign == "-" then
            i = i + 1
        end
        while s:sub(i, i):match("%d") do
            i = i + 1
        end
    end
    local numStr = s:sub(start, i - 1)
    local n = tonumber(numStr)
    if type(n) ~= "number" then
        return nil, start, "invalid number"
    end
    return n, i, nil
end

local ParseValue

---@param s string
---@param i number
---@return table|nil
---@return number
---@return string|nil
local function ParseArray(s, i)
    if s:sub(i, i) ~= "[" then
        return nil, i, "expected array"
    end
    i = i + 1
    local out = {}
    i = SkipWS(s, i)
    if s:sub(i, i) == "]" then
        return out, i + 1, nil
    end
    while true do
        local v, ni, err = ParseValue(s, i)
        if err then return nil, i, err end
        out[#out + 1] = v
        i = SkipWS(s, ni)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWS(s, i + 1)
        elseif c == "]" then
            return out, i + 1, nil
        else
            return nil, i, "expected ',' or ']'"
        end
    end
end

---@param s string
---@param i number
---@return table|nil
---@return number
---@return string|nil
local function ParseObject(s, i)
    if s:sub(i, i) ~= "{" then
        return nil, i, "expected object"
    end
    i = i + 1
    local out = {}
    i = SkipWS(s, i)
    if s:sub(i, i) == "}" then
        return out, i + 1, nil
    end
    while true do
        local key, ni, err = ParseString(s, i)
        if err then return nil, i, err end
        if key == nil then
            return nil, i, "invalid object key"
        end
        i = SkipWS(s, ni)
        if s:sub(i, i) ~= ":" then
            return nil, i, "expected ':'"
        end
        i = SkipWS(s, i + 1)
        local v, ni2, err2 = ParseValue(s, i)
        if err2 then return nil, i, err2 end
        out[key] = v
        i = SkipWS(s, ni2)
        local c = s:sub(i, i)
        if c == "," then
            i = SkipWS(s, i + 1)
        elseif c == "}" then
            return out, i + 1, nil
        else
            return nil, i, "expected ',' or '}'"
        end
    end
end

ParseValue = function(s, i)
    i = SkipWS(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return ParseString(s, i)
    end
    if c == "{" then
        return ParseObject(s, i)
    end
    if c == "[" then
        return ParseArray(s, i)
    end
    if c == "-" or c:match("%d") then
        return ParseNumber(s, i)
    end
    local tail = s:sub(i)
    if tail:sub(1, 4) == "true" then
        return true, i + 4, nil
    end
    if tail:sub(1, 5) == "false" then
        return false, i + 5, nil
    end
    if tail:sub(1, 4) == "null" then
        return nil, i + 4, nil
    end
    return nil, i, "unexpected token"
end

---@param s string
---@return any|nil
---@return string|nil
local function DecodeJSON(s)
    if type(s) ~= "string" or s == "" then
        return nil, "empty input"
    end
    local v, i, err = ParseValue(s, 1)
    if err then
        return nil, err
    end
    i = SkipWS(s, i)
    if i <= #s then
        -- allow trailing whitespace; otherwise fail
        if s:sub(i):match("^%s*$") then
            return v, nil
        end
        return nil, "trailing characters"
    end
    return v, nil
end

-- ----------------------------
-- Simulation engine
-- ----------------------------

local function GetConfiguredSpeed()
    local speed = CM:GetProfileSettingSafe(CONFIGURATION.PLAYBACK_SPEED.key, nil)
    if type(speed) ~= "number" then
        speed = CM:GetProfileSettingByConfigEntry(CONFIGURATION.PLAYBACK_SPEED)
    end
    return ClampNumber(speed, 0.1, 50, 10)
end

function Sim:IsSimulating()
    return self._simState ~= nil
end

function Sim:StopSimulation()
    if not self._simState then
        return
    end
    self._simToken = (self._simToken or 0) + 1
    self._simState = nil
    Logger.Info("Simulator: stopped")
    self:_FireCallback("SIMULATOR_STOPPED")

    if self._restoreRunLoggerEnabled then
        self._restoreRunLoggerEnabled = nil
        local rl = MythicPlusModule and MythicPlusModule.RunLogger
        if rl and type(rl.Enable) == "function" then
            rl:Enable()
        end
    end
end

---@param ev table
---@return string
local function EventName(ev)
    return tostring(ev and (ev.name or ev.event or ev.type) or "unknown")
end

---@param ev table
---@return number
local function EventRel(ev)
    local r = ev and (ev.relSeconds or ev.rel or 0)
    r = tonumber(r) or 0
    if r < 0 then r = 0 end
    return r
end

---@param ev table
---@return any
local function EventPayload(ev)
    return ev and (ev.payload or {}) or {}
end

---@param name string
---@param payload any
local function BuildDungeonArgs(name, payload)
    if type(payload) ~= "table" then
        payload = {}
    end

    if name == "CHALLENGE_MODE_START" then
        return payload.mapId
    end
    if name == "CHALLENGE_MODE_COMPLETED" then
        return nil
    end
    if name == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        return payload.count
    end
    if name == "CHALLENGE_MODE_COMPLETED_REWARDS" then
        return payload.mapId, payload.medal, payload.timeMS, payload.money, payload.rewards
    end
    if name == "CHALLENGE_MODE_RESET" then
        return payload.mapId
    end
    if name == "ENCOUNTER_START" then
        return payload.encounterID, payload.encounterName, payload.difficultyID, payload.groupSize
    end
    if name == "ENCOUNTER_END" then
        return payload.encounterID, payload.encounterName, payload.difficultyID, payload.groupSize, payload.success
    end
    if name == "PLAYER_ENTERING_WORLD" then
        return payload.isInitialLogin, payload.isReloadingUi
    end
    if name == "CHAT_MSG_LOOT" then
        return payload.message, payload.player
    end
    if name == "GROUP_ROSTER_SNAPSHOT" then
        return payload.group, payload.reason
    end

    if payload.args and type(payload.args) == "table" then
        return unpack(payload.args)
    end

    return nil
end

---@param ev table
---@param index number
---@param total number
function Sim:_LogStage(ev, index, total)
    local name = EventName(ev)
    if name == "CHALLENGE_MODE_START" or name == "CHALLENGE_MODE_COMPLETED_REWARDS" or name == "CHALLENGE_MODE_RESET" then
        Logger.Info(("Simulator: %s (%d/%d)"):format(name, index, total))
        return
    end
    if index == 1 or index == total or index % 25 == 0 then
        Logger.Debug(("Simulator: %s (%d/%d)"):format(name, index, total))
    end
end

---@param ev table
function Sim:_DispatchEvent(ev)
    local dungeonMonitor = GetDungeonMonitor()
    if not dungeonMonitor then
        Logger.Error("Simulator: DungeonMonitor not available")
        return
    end

    local name = EventName(ev)
    local payload = EventPayload(ev)

    local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16 =
        BuildDungeonArgs(name, payload)

    if type(dungeonMonitor.SimulateEvent) == "function" then
        dungeonMonitor:SimulateEvent(name, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12,
            arg13, arg14, arg15, arg16)
    elseif type(dungeonMonitor.EventHandler) == "function" then
        dungeonMonitor:EventHandler(name, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12,
            arg13, arg14, arg15, arg16)
    end
end

---@param token number
function Sim:_ScheduleNext(token)
    local st = self._simState
    if not st or st.token ~= token or type(st.events) ~= "table" then
        return
    end

    local nextIdx = (tonumber(st.index) or 0) + 1
    local ev = st.events[nextIdx]
    if not ev then
        Logger.Info("Simulator: complete")
        self._simState = nil
        self:_FireCallback("SIMULATOR_STOPPED")

        if self._restoreRunLoggerEnabled then
            self._restoreRunLoggerEnabled = nil
            local rl = MythicPlusModule and MythicPlusModule.RunLogger
            if rl and type(rl.Enable) == "function" then
                rl:Enable()
            end
        end

        return
    end

    local nextRel = EventRel(ev)
    local speed = tonumber(st.speed) or 1
    if speed <= 0 then speed = 1 end

    -- Use absolute time reference to avoid drift and handle resume correctly
    local now = GetTime()
    local currentVirtualTime = (now - st.startedAt) * speed
    local delay = (nextRel - currentVirtualTime) / speed
    if delay < 0 then delay = 0 end

    local function fire()
        st = self._simState
        if not st or st.token ~= token then
            return
        end

        st.index = nextIdx
        st.prevRel = nextRel

        self:_LogStage(ev, st.index or 0, st.total or 0)
        self:_DispatchEvent(ev)
        self:_FireCallback("SIMULATOR_PROGRESS", st.index, st.total)

        self:_ScheduleNext(token)
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, fire)
    else
        fire()
    end
end

function Sim:PauseSimulation()
    local st = self._simState
    if not st or st.paused then return end

    st.paused = true
    st.pauseStart = GetTime()
    self._simToken = (self._simToken or 0) + 1 -- Invalidate pending timers

    Logger.Info("Simulator: paused")
    self:_FireCallback("SIMULATOR_PAUSED")
end

function Sim:ResumeSimulation()
    local st = self._simState
    if not st or not st.paused then return end

    local now = GetTime()
    local pauseDuration = now - (st.pauseStart or now)
    st.startedAt = st.startedAt + pauseDuration
    st.paused = false
    st.pauseStart = nil

    self._simToken = (self._simToken or 0) + 1
    local token = self._simToken

    Logger.Info("Simulator: resumed")
    self:_FireCallback("SIMULATOR_RESUMED", st.maxDuration, st.startedAt, st.speed, st.events)
    self:_ScheduleNext(token)
end

function Sim:SeekSimulation(targetTime)
    local st = self._simState
    if not st then return end

    targetTime = math.max(0, math.min(targetTime, st.maxDuration))

    -- Find the event index just before or at targetTime
    local newIndex = 0
    local prevRel = 0
    for i, ev in ipairs(st.events) do
        local rel = EventRel(ev)
        if rel > targetTime then
            break
        end
        newIndex = i
        prevRel = rel
    end

    st.index = newIndex
    st.prevRel = prevRel

    local now = GetTime()
    local speed = st.speed

    -- Recalculate startedAt so that (now - startedAt) * speed == targetTime
    st.startedAt = now - (targetTime / speed)

    if st.paused then
        st.pauseStart = now
    end

    self._simToken = (self._simToken or 0) + 1
    local token = self._simToken

    Logger.Info(("Simulator: seeked to %.1fs"):format(targetTime))

    if st.paused then
        self:_FireCallback("SIMULATOR_SEEKED", targetTime, st.index, st.total)
    else
        self:_FireCallback("SIMULATOR_RESUMED", st.maxDuration, st.startedAt, st.speed, st.events)
        self:_ScheduleNext(token)
    end
end

---@param jsonText string
---@param opts table|nil
function Sim:StartSimulationFromJSON(jsonText, opts)
    if self._simState then
        self:StopSimulation()
    end

    local parsed, err = DecodeJSON(jsonText)
    if not parsed then
        Logger.Error("Simulator: JSON parse failed: " .. tostring(err))
        return
    end

    self:StartSimulationFromData(parsed, opts)
end

---@param parsed table
---@param opts table|nil
function Sim:StartSimulationFromData(parsed, opts)
    if self._simState then
        self:StopSimulation()
    end

    if type(parsed) ~= "table" then
        Logger.Error("Simulator: Data root must be an object")
        return
    end
    if parsed.format ~= "TwichUI_RunLog_v2" then
        Logger.Warn("Simulator: unexpected format: " .. tostring(parsed.format))
    end
    if type(parsed.events) ~= "table" then
        Logger.Error("Simulator: missing events array")
        return
    end

    local events = {}
    local seq = 0
    for _, ev in ipairs(parsed.events) do
        if type(ev) == "table" then
            seq = seq + 1
            -- Preserve original ordering for events with identical timestamps.
            -- NOTE: We do not rely on `table.sort` stability.
            ev._simSeq = ev._simSeq or seq
            events[#events + 1] = ev
        end
    end

    -- RunLogger already records events in chronological order. Only sort if needed.
    local needSort = false
    do
        local prev = -math.huge
        for i = 1, #events do
            local r = EventRel(events[i])
            if r < prev then
                needSort = true
                break
            end
            prev = r
        end
    end

    if needSort then
        table.sort(events, function(a, b)
            local ar = EventRel(a)
            local br = EventRel(b)
            if ar == br then
                return (tonumber(a._simSeq) or 0) < (tonumber(b._simSeq) or 0)
            end
            return ar < br
        end)
    end

    local speed = opts and opts.speed or nil
    if speed == nil then
        speed = GetConfiguredSpeed()
    end
    speed = ClampNumber(speed, 0.1, 50, 10)

    local startPaused = opts and opts.startPaused or false

    -- Ensure Mythic+ + DungeonMonitor are enabled so callbacks fire normally.
    if MythicPlusModule and type(MythicPlusModule.IsEnabled) == "function" and type(MythicPlusModule.Enable) == "function" then
        if not MythicPlusModule:IsEnabled() then
            MythicPlusModule:Enable()
        end
    end
    local dungeonMonitor = GetDungeonMonitor()
    if dungeonMonitor and type(dungeonMonitor.Enable) == "function" and not dungeonMonitor.enabled then
        dungeonMonitor:Enable()
    end

    -- Avoid overwriting run logs while simulating (restore after).
    local rl = MythicPlusModule and MythicPlusModule.RunLogger
    if rl and rl.enabled and type(rl.Disable) == "function" then
        self._restoreRunLoggerEnabled = true
        rl:Disable()
    end

    self._simToken = (self._simToken or 0) + 1
    local token = self._simToken
    local startedAt = type(GetTime) == "function" and GetTime() or 0

    -- Calculate max duration
    local maxDuration = 0
    if #events > 0 then
        maxDuration = EventRel(events[#events])
    end

    self._simState = {
        token = token,
        meta = parsed.meta,
        run = parsed.run,
        events = events,
        total = #events,
        index = 0,
        prevRel = 0,
        speed = speed,
        startedAt = startedAt,
        maxDuration = maxDuration,
        paused = startPaused,
        pauseStart = startPaused and startedAt or nil,
    }

    Logger.Info(("Simulator: starting (%d events), speed x%.2f"):format(#events, speed))
    self:_FireCallback("SIMULATOR_STARTED", #events, maxDuration, events, startedAt, speed)

    if startPaused then
        self:_FireCallback("SIMULATOR_PAUSED")
    else
        self:_ScheduleNext(token)
    end
end

---@param ev table
function Sim:SimulateSingleEvent(ev)
    if type(ev) ~= "table" then return end
    self:_DispatchEvent(ev)
end

function Sim:Enable()
    if self.enabled then return end
    Module:Enable()
    self.enabled = true
    Logger.Debug("Mythic+ simulator enabled")
end

function Sim:Disable()
    if not self.enabled then return end
    self:StopSimulation()
    Module:Disable()
    self.enabled = false
    Logger.Debug("Mythic+ simulator disabled")
end

function Sim:Initialize()
    if self.enabled then return end
    self:Enable()
end
