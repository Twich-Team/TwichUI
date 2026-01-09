--[[
    Run logger will track events and data during a live mythic plus run for simulation later on.
]]

---@diagnostic disable-next-line: undefined-global
local T = unpack(Twich)

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local time = _G.time
local date = _G.date
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetBuildInfo = _G.GetBuildInfo
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local GetInspectSpecialization = _G.GetInspectSpecialization
local GetSpecializationInfoByID = _G.GetSpecializationInfoByID
local GetNormalizedRealmName = _G.GetNormalizedRealmName
local GetRealmName = _G.GetRealmName
local C_Item = _G.C_Item
local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local strmatch = _G.string and _G.string.match
local strgmatch = _G.string and _G.string.gmatch

---@type MythicPlusModule
local MythicPlusModule = T:GetModule("MythicPlus")
---@class MythicPlusRunLoggerSubmodule
---@field enabled boolean
---@field _callbackHandle any
---@field _frame Frame|nil
---@field _editBox EditBox|nil
local MythicPlusRunLogger = MythicPlusModule.RunLogger or {}
MythicPlusModule.RunLogger = MythicPlusRunLogger

---@type LoggerModule
local Logger = T:GetModule("Logger")
---@type ToolsModule
local Tools = T:GetModule("Tools")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")

---@type ToolsUI|nil
local UI = Tools and Tools.UI

---@type MythicPlusDungeonMonitorSubmodule
local DungeonMonitor = MythicPlusModule.DungeonMonitor
---@type MythicPlusAPISubmodule
local API = MythicPlusModule.API
---@type MythicPlusScoreCalculatorSubmodule
local ScoreCalculator = MythicPlusModule.ScoreCalculator
---@type MythicPlusRunLoggerSyncSubmodule
local RunLoggerSync = MythicPlusModule.RunLoggerSync

local function PrintRunLoggerInfo(message)
    if type(_G.print) ~= "function" then
        return
    end
    _G.print("|cff9580ffTwichUI:|r " .. tostring(message))
end

---@type table<string, ConfigEntry>
local CONFIGURATION = {
    -- NOTE: This is a developer tool; keep under the developer namespace.
    -- Back-compat migration from the earlier key: "mythicPlus.runLogger.enable"
    ENABLE = { key = "developer.mythicplus.runLogger.enable", default = false }
}

local Module = Tools.Generics.Module:New(CONFIGURATION)

local DB_VERSION = 1
local LEGACY_ENABLE_KEY = "mythicPlus.runLogger.enable"

-- Keys for mapping GetItemInfo() returns into a table (matches LootMonitor mapping).
local ITEMINFO_KEYS = {
    "name", "link", "quality", "iLevel", "minLevel", "type", "subType",
    "maxStack", "equipLoc", "icon", "sellPrice", "classID", "subClassID",
    "bindType", "expansionID", "setID", "isCraftingReagent",
}

---@param msg string
---@return string[]
local function ExtractItemLinks(msg)
    if type(msg) ~= "string" or msg == "" or type(strgmatch) ~= "function" then
        return {}
    end

    local out = {}

    -- Prefer full colored item links when present.
    for link in strgmatch(msg, "(%|c%x+%|Hitem:.-%|h%[.-%]%|h%|r)") do
        out[#out + 1] = link
        if #out >= 10 then
            return out
        end
    end

    -- Fallback: uncolored links.
    if #out == 0 then
        for link in strgmatch(msg, "(%|Hitem:.-%|h%[.-%]%|h)") do
            out[#out + 1] = link
            if #out >= 10 then
                return out
            end
        end
    end

    return out
end

---@param msg string
---@return number|nil
local function TryExtractQuantity(msg)
    if type(msg) ~= "string" or msg == "" or type(strmatch) ~= "function" then
        return nil
    end
    -- Best-effort: many loot messages append "xN".
    local qty = strmatch(msg, "x(%d+)")
    qty = qty and tonumber(qty) or nil
    if qty and qty > 0 then
        return qty
    end
    return nil
end

---@param msg string
---@return string|nil
local function TryExtractBracketItemName(msg)
    if type(msg) ~= "string" or msg == "" or type(strmatch) ~= "function" then
        return nil
    end
    -- Best-effort fallback when the chat message doesn't include an itemLink.
    local name = strmatch(msg, "%[(.-)%]")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

---@param playerName any
---@param guid any
---@return boolean
local function IsPlayerLootEvent(playerName, guid)
    local myGuid = (type(UnitGUID) == "function") and UnitGUID("player") or nil
    if myGuid and guid and guid == myGuid then
        return true
    end

    if type(playerName) ~= "string" or playerName == "" then
        return false
    end

    local myName, myRealm
    if type(UnitName) == "function" then
        myName, myRealm = UnitName("player")
    end

    if type(myName) ~= "string" or myName == "" then
        return false
    end

    if playerName == myName then
        return true
    end

    if type(myRealm) == "string" and myRealm ~= "" then
        local full = myName .. "-" .. myRealm
        if playerName == full or playerName == (myName .. " - " .. myRealm) then
            return true
        end
    end

    return false
end

---@param item any
---@return table|nil
local function GetItemInfoTable(item)
    if type(GetItemInfo) ~= "function" then
        return nil
    end

    local results = { GetItemInfo(item) }
    if not results[1] then
        return nil
    end

    local t = {}
    for i = 1, #results do
        t[ITEMINFO_KEYS[i] or ("field" .. i)] = results[i]
    end
    return t
end

---@param link string
---@return number|nil
local function TryGetItemIdFromLink(link)
    if type(link) ~= "string" or link == "" then
        return nil
    end

    if type(GetItemInfoInstant) == "function" then
        local itemId = select(1, GetItemInfoInstant(link))
        itemId = itemId and tonumber(itemId) or nil
        if itemId and itemId > 0 then
            return itemId
        end
    end

    if type(strmatch) == "function" then
        local itemId = strmatch(link, "item:(%d+):")
        itemId = itemId and tonumber(itemId) or nil
        if itemId and itemId > 0 then
            return itemId
        end
    end

    return nil
end

---@class TwichUIRunLogger_RunEvent
---@field rel number seconds since run start
---@field unix number unix timestamp (seconds)
---@field name string
---@field payload any
---@field rawArgs any[]|nil Original callback args from DungeonMonitor
---@field args any[]|nil Args used for simulation (defaults to rawArgs)
---@field meta table|nil RunLogger-only metadata (never used by DungeonMonitor)

---@class TwichUIRunLogger_Run
---@field id string
---@field status string "in_progress"|"completed"|"reset"
---@field startUnix number
---@field startDate string
---@field startRel number GetTime() at run start
---@field endUnix number|nil
---@field endRel number|nil
---@field mapId number|nil
---@field dungeonName string|nil
---@field __twichuiPendingCMCheck boolean|nil Internal: delayed CM-active recheck to avoid premature finalize during loads
---@field level number|nil
---@field affixes number[]|nil
---@field player table|nil
---@field groupStart table[]|nil
---@field group table[]|nil
---@field completion table|nil
---@field completionMeta table|nil
---@field events TwichUIRunLogger_RunEvent[]

---@class TwichUIRunLogger_RemoteRun
---@field sender string
---@field receivedAt number
---@field data table TwichUIRunLogger_Run or a TwichUI_RunLog_v2 export object

---@class TwichUIRunLoggerDB
---@field version number
---@field active TwichUIRunLogger_Run|nil
---@field lastCompleted TwichUIRunLogger_Run|nil
---@field runHistory TwichUIRunLogger_Run[]|nil
---@field linkedReceiver string|nil
---@field remoteRuns TwichUIRunLogger_RemoteRun[]|nil
---@field registeredReceivers table<string, number>|nil
---@field sync table|nil
local FALLBACK_DB = { version = DB_VERSION }

---@return TwichUIRunLoggerDB
local function GetDB()
    -- Prefer profile-scoped DB so run logs differ by profile/character.
    local profile = (T.db and T.db.profile)
    if type(profile) == "table" then
        profile.mythicPlus = profile.mythicPlus or {}
        profile.mythicPlus.runLoggerDB = profile.mythicPlus.runLoggerDB or {}
        local db = profile.mythicPlus.runLoggerDB

        if type(db.version) ~= "number" then
            db.version = DB_VERSION
        end

        return db
    end

    -- Fallback: in-memory only (should be rare).
    return FALLBACK_DB
end

---@param run TwichUIRunLogger_Run
local function AddToRunHistory(run)
    if type(run) ~= "table" or not run.id then return end

    local db = GetDB()
    db.runHistory = db.runHistory or {}
    local history = db.runHistory
    if type(history) ~= "table" then
        return
    end

    -- Remove any existing entry with the same id (keep newest).
    for i = #history, 1, -1 do
        local r = history[i]
        if r and type(r) == "table" and r.id == run.id then
            table.remove(history, i)
            break
        end
    end

    history[#history + 1] = run

    local max = tonumber(CM:GetProfileSettingSafe("developer.mythicplus.runLogger.runHistorySize", 20)) or 20
    if max < 1 then
        max = 1
    end
    while #history > max do
        table.remove(history, 1)
    end
end

---@param val any
---@param depth number
---@return any
local function Sanitize(val, depth)
    if depth <= 0 then
        return tostring(val)
    end

    local t = type(val)
    if t == "nil" or t == "number" or t == "boolean" then
        return val
    end
    if t == "string" then
        return val
    end
    if t == "table" then
        local out = {}
        local n = 0
        for k, v in pairs(val) do
            n = n + 1
            if n > 200 then
                out.__truncated = true
                break
            end

            local sk
            if type(k) == "string" or type(k) == "number" then
                sk = k
            else
                sk = tostring(k)
            end

            out[sk] = Sanitize(v, depth - 1)
        end
        return out
    end

    -- functions/userdata/threads
    return tostring(val)
end

---@param t table
---@return boolean
local function IsArrayTable(t)
    if type(t) ~= "table" then return false end
    local max = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k <= 0 or k % 1 ~= 0 then
            return false
        end
        if k > max then max = k end
        count = count + 1
        if count > 5000 then
            return false
        end
    end
    return max == count
end

---@param s string
---@return string
local function EscapeJSON(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

---@param v any
---@return string
local function EncodeJSON(v)
    local tv = type(v)
    if tv == "nil" then
        return "null"
    end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "null"
        end
        return tostring(v)
    end
    if tv == "boolean" then
        return v and "true" or "false"
    end
    if tv == "string" then
        return '"' .. EscapeJSON(v) .. '"'
    end
    if tv ~= "table" then
        return '"' .. EscapeJSON(tostring(v)) .. '"'
    end

    if IsArrayTable(v) then
        local parts = {}
        for i = 1, #v do
            parts[#parts + 1] = EncodeJSON(v[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local parts = {}
    for k, val in pairs(v) do
        local keyStr = (type(k) == "string") and k or tostring(k)
        parts[#parts + 1] = '"' .. EscapeJSON(keyStr) .. '":' .. EncodeJSON(val)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

---@return table
local function BuildPlayerSnapshot()
    local name, realm = UnitName("player")
    name = name or "Unknown"
    realm = realm or (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName())
        or (type(GetRealmName) == "function" and GetRealmName())
    local guid = UnitGUID("player") or "Unknown"
    local classFile = select(2, UnitClass("player")) or "Unknown"

    local specID, specName
    if type(GetSpecialization) == "function" and type(GetSpecializationInfo) == "function" then
        local specIndex = GetSpecialization()
        if specIndex then
            local id, name2 = GetSpecializationInfo(specIndex)
            if type(id) == "number" and id > 0 then
                specID = id
            end
            if type(name2) == "string" and name2 ~= "" then
                specName = name2
            end
        end
    end

    return {
        name = name,
        realm = realm,
        guid = guid,
        class = classFile,
        specId = specID,
        spec = specName,
    }
end

---@param unit string
---@return number|nil specId
---@return string|nil specName
local function TryGetUnitSpec(unit)
    if unit == "player" then
        local p = BuildPlayerSnapshot()
        return p.specId, p.spec
    end

    if type(GetInspectSpecialization) ~= "function" then
        return nil, nil
    end

    local ok, specID = pcall(GetInspectSpecialization, unit)
    if not ok or type(specID) ~= "number" or specID <= 0 then
        return nil, nil
    end

    if type(GetSpecializationInfoByID) ~= "function" then
        return specID, nil
    end

    local ok2, _, specName = pcall(GetSpecializationInfoByID, specID)
    if ok2 and type(specName) == "string" and specName ~= "" then
        return specID, specName
    end

    return specID, nil
end

---@return table[]
local function BuildGroupSnapshot()
    local group = {}

    local playerRealm = select(2, UnitName("player"))
        or (type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName())
        or (type(GetRealmName) == "function" and GetRealmName())

    -- Always include player
    do
        local classFile = select(2, UnitClass("player"))
        local specID, specName = TryGetUnitSpec("player")
        local name, realm = UnitName("player")
        group[#group + 1] = {
            unit = "player",
            name = name,
            realm = realm or playerRealm,
            guid = UnitGUID("player"),
            class = classFile,
            role = UnitGroupRolesAssigned("player"),
            specId = specID,
            spec = specName,
        }
    end

    if not IsInGroup() then
        return group
    end

    -- Mythic+ groups are typically parties, but handle raid just in case.
    local count = GetNumGroupMembers() or 0
    if count <= 0 then
        return group
    end

    if IsInRaid() then
        -- Avoid iterating raid units for now; keep it minimal + safe.
        return group
    end

    for i = 1, 4 do
        local unit = "party" .. tostring(i)
        if UnitGUID(unit) then
            local classFile = select(2, UnitClass(unit))
            local specID, specName = TryGetUnitSpec(unit)
            local name, realm = UnitName(unit)
            group[#group + 1] = {
                unit = unit,
                name = name,
                realm = realm or playerRealm,
                guid = UnitGUID(unit),
                class = classFile,
                role = UnitGroupRolesAssigned(unit),
                specId = specID,
                spec = specName,
            }
        end
    end

    return group
end

---@param mapId number|nil
---@return number|nil
---@return number[]|nil
local function TryGetKeystoneInfo(mapId)
    if not API or type(API.GetPlayerKeystone) ~= "function" then
        return nil, nil
    end

    local info = API:GetPlayerKeystone()
    if not info then
        return nil, nil
    end

    -- Only trust map match if provided.
    if mapId and info.dungeonID and tonumber(mapId) ~= tonumber(info.dungeonID) then
        -- It's still useful to log level/affixes, but mark map mismatch by returning nil map-dependent fields.
        return info.level, info.affixes
    end

    return info.level, info.affixes
end

---@param run TwichUIRunLogger_Run
---@return table
local function BuildExportObject(run)
    if not run then
        return {
            format = "TwichUI_RunLog_v2",
            error = "no_run",
        }
    end

    local version, build, buildDate, toc = GetBuildInfo()

    local meta = {
        format = "TwichUI_RunLog_v2",
        addonVersion = (T and T.addonMetadata and T.addonMetadata.version) or "unknown",
        wowVersion = version,
        wowBuild = build,
        wowToc = toc,
    }

    local events = {}
    if type(run.events) == "table" then
        for _, ev in ipairs(run.events) do
            -- Ensure every entry has a timestamp.
            local ts = (type(ev.unix) == "number" and ev.unix)
                or (type(run.startUnix) == "number" and (run.startUnix + (tonumber(ev.rel) or 0)))
                or time()

            events[#events + 1] = {
                timestamp = ts, -- unix seconds
                relSeconds = tonumber(ev.rel) or 0,
                name = tostring(ev.name),
                payload = ev.payload,
                rawArgs = ev.rawArgs,
                args = ev.args,
                meta = ev.meta,
            }
        end
    end

    return {
        format = "TwichUI_RunLog_v2",
        meta = meta,
        run = {
            id = run.id,
            status = run.status,
            startUnix = run.startUnix,
            endUnix = run.endUnix,
            mapId = run.mapId,
            level = run.level,
            affixes = run.affixes,
            player = run.player,
            groupStart = run.groupStart,
            group = run.group,
            completion = run.completion,
        },
        events = events,
    }
end

---@param run TwichUIRunLogger_Run
---@return string
local function BuildExportText(run)
    return EncodeJSON(BuildExportObject(run)) .. "\n"
end

---@param run TwichUIRunLogger_Run
local function AddRunToSimulatorList(run)
    if type(run) ~= "table" or not run.id then
        return
    end

    local db = GetDB()
    db.remoteRuns = db.remoteRuns or {}

    -- Avoid duplicates by run id (supports both v2 export object and flat run records).
    for _, rr in ipairs(db.remoteRuns) do
        if type(rr) == "table" and type(rr.data) == "table" then
            local data = rr.data
            local id = data.id
                or (type(data.run) == "table" and data.run.id)
            if id == run.id then
                return
            end
        end
    end

    local exported = BuildExportObject(run)
    db.remoteRuns[#db.remoteRuns + 1] = {
        sender = "Local",
        receivedAt = time(),
        data = exported,
    }

    local frame = MythicPlusModule and MythicPlusModule.RunSharingFrame
    if frame and type(frame.UpdateList) == "function" then
        frame:UpdateList()
    end
end

function MythicPlusRunLogger:_EnsureFrame()
    if self._frame and self._editBox then
        return
    end

    local frame = CreateFrame("Frame", "TwichUI_RunLogger_CopyFrame", UIParent, "BackdropTemplate")
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Backdrop (ElvUI template if present, else generic)
    if frame.SetTemplate then
        frame:SetTemplate("Transparent")
    else
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.9)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("TwichUI Mythic+ Run Log")

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    hint:SetText("Copy/paste the text below")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local scroll = CreateFrame("ScrollFrame", "TwichUI_RunLogger_CopyScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 12)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(700)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnTextChanged", function(self)
        scroll:UpdateScrollChildRect()
    end)

    scroll:SetScrollChild(editBox)

    -- ElvUI skinning (best-effort)
    if UI then
        UI.SkinCloseButton(close)
        UI.SkinScrollBar(scroll)
        UI.SkinEditBox(editBox)
    end

    frame:SetScript("OnShow", function()
        if editBox and editBox.SetFocus then
            editBox:SetFocus()
            editBox:HighlightText()
        end
    end)

    self._frame = frame
    self._editBox = editBox
end

---@param text string
function MythicPlusRunLogger:_ShowExport(text)
    self:_EnsureFrame()
    if not self._frame or not self._editBox then return end

    self._editBox:SetText(text or "")
    self._frame:Show()
end

--- Show the run log export frame on-demand.
--- Prefers the last completed run; falls back to the currently active run.
function MythicPlusRunLogger:ShowLastRunLog()
    local db = GetDB()
    local run = db.lastCompleted or db.active
    if not run then
        Logger.Info("Run Logger: no run log available yet")
        return
    end

    local text = BuildExportText(run)
    self:_ShowExport(text)
end

---@return boolean
function MythicPlusRunLogger:HasRunData()
    local db = GetDB()
    return (db and (db.lastCompleted ~= nil or db.active ~= nil)) or false
end

--- Toggle the run log export frame.
--- - If the frame is currently visible, hides it.
--- - Otherwise, shows the last completed/active run log.
function MythicPlusRunLogger:ToggleRunLogFrame()
    if self._frame and self._frame.IsShown and self._frame:IsShown() then
        self._frame:Hide()
        return
    end

    self:ShowLastRunLog()
end

---@param mapId number|nil
---@param dungeonName string|nil
function MythicPlusRunLogger:_StartNewRun(mapId, dungeonName)
    local db = GetDB()
    db.active = nil
    -- db.lastCompleted = nil -- Keep last completed for history/reference

    local nowUnix = time()
    local nowRel = GetTime()
    local level, affixes = TryGetKeystoneInfo(mapId)
    local groupSnapshot = BuildGroupSnapshot()

    ---@type TwichUIRunLogger_Run
    local run = {
        id = tostring(nowUnix) .. "-" .. tostring(mapId or "unknown"),
        status = "in_progress",
        startUnix = nowUnix,
        startDate = date("%Y-%m-%d %H:%M:%S", nowUnix),
        startRel = nowRel,
        mapId = tonumber(mapId) or nil,
        dungeonName = dungeonName, -- Store resolved name
        level = tonumber(level) or nil,
        affixes = (type(affixes) == "table") and affixes or nil,
        player = BuildPlayerSnapshot(),
        groupStart = groupSnapshot,
        group = groupSnapshot,
        events = {},
    }

    db.active = run

    -- Capture roster immediately so we have it even if GROUP_ROSTER_UPDATE never fires.
    self:_AppendEvent("GROUP_ROSTER_SNAPSHOT", { group = groupSnapshot, reason = "start" })

    do
        local label = dungeonName
        if type(label) ~= "string" or label == "" then
            label = "Mythic+"
        end
        PrintRunLoggerInfo("Run Logger: Recording started (" .. label .. ")")
    end

    Logger.Debug("This Mythic+ run will be recorded.")
end

---@param status string
---@param completionPayload table|nil
function MythicPlusRunLogger:_FinalizeRun(status, completionPayload)
    local db = GetDB()
    local run = db.active
    if not run then return end

    run.status = status or run.status
    run.endUnix = time()
    run.endRel = GetTime()
    if completionPayload then
        run.completion = completionPayload
    end

    -- keep a copy for later (survives reload)
    db.lastCompleted = run
    db.active = nil

    do
        local label = run.dungeonName
        if type(label) ~= "string" or label == "" then
            label = "Mythic+"
        end
        PrintRunLoggerInfo("Run Logger: Recording finished (" .. label .. ")")
    end

    if run.status == "completed" then
        AddToRunHistory(run)
        local text = BuildExportText(run)

        local addToSim = CM:GetProfileSettingSafe("developer.mythicplus.runLogger.addToSimulatorOnComplete", false)
        if addToSim then
            AddRunToSimulatorList(run)
        end

        local autoShow = CM:GetProfileSettingSafe("developer.mythicplus.runLogger.autoShow", false)
        if autoShow then
            self:_ShowExport(text)
        end
    end

    -- Sync finalized data to any configured peers.
    if RunLoggerSync and RunLoggerSync.Initialize then
        RunLoggerSync:Initialize()
        if RunLoggerSync.OnRunFinalized then
            RunLoggerSync:OnRunFinalized(run)
        end
    end

    Logger.Debug("Mythic+ run recording finalized.")
end

---@param eventName string
---@param payload any
---@param rawArgs any[]|nil Original callback args from DungeonMonitor
---@param args any[]|nil Args that should be used for simulation (defaults to rawArgs)
---@param meta table|nil Extra RunLogger-only metadata (never used by DungeonMonitor)
function MythicPlusRunLogger:_AppendEvent(eventName, payload, rawArgs, args, meta)
    local db = GetDB()
    local run = db.active
    if not run or type(run.events) ~= "table" then
        return
    end

    local rel
    if type(run.startRel) == "number" then
        rel = GetTime() - run.startRel
    end
    if type(rel) ~= "number" or rel < 0 then
        -- GetTime() resets across /reload; fall back to unix delta.
        rel = (time() - (run.startUnix or time()))
        if rel < 0 then rel = 0 end
    end

    local entry = {
        rel = rel,
        unix = time(),
        name = tostring(eventName),
        payload = Sanitize(payload, 6),
    }

    if type(rawArgs) == "table" then
        entry.rawArgs = Sanitize(rawArgs, 6)
    end

    if type(args) == "table" then
        entry.args = Sanitize(args, 6)
    elseif type(rawArgs) == "table" then
        entry.args = entry.rawArgs
    end

    if type(meta) == "table" then
        entry.meta = Sanitize(meta, 8)
    end

    run.events[#run.events + 1] = entry
end

---@param eventName string
---@param ... any
function MythicPlusRunLogger:_OnDungeonEvent(eventName, ...)
    if not self.enabled then return end

    if eventName == "TWICH_DUNGEON_START" then
        local mapId, dungeonName = ...
        -- If we already started a run via CHALLENGE_MODE_START (race condition), update it
        local db = GetDB()
        if db.active and db.active.status == "in_progress" then
            -- Some clients/patches fire CHALLENGE_MODE_START with nil/invalid mapId.
            -- Backfill from the resolved TWICH_DUNGEON_START payload.
            if (db.active.mapId == nil) or (tonumber(db.active.mapId) == nil) or (tonumber(db.active.mapId) <= 0) then
                db.active.mapId = tonumber(mapId) or mapId
            end
            if not db.active.dungeonName then
                db.active.dungeonName = dungeonName
                Logger.Debug("RunLogger: Updated active run with resolved dungeon name: " .. tostring(dungeonName))
            end
        else
            -- Otherwise start a new run with this info
            self:_StartNewRun(mapId, dungeonName)
        end

        -- Record exactly what DungeonMonitor emitted.
        self:_AppendEvent(eventName, { mapId = tonumber(mapId) or mapId, dungeonName = dungeonName }, { ... })
        return
    end

    if eventName == "CHALLENGE_MODE_START" then
        local mapId = ...

        -- Some clients/patches provide nil/invalid mapId here; recover from live APIs.
        if (tonumber(mapId) == nil) or (tonumber(mapId) <= 0) then
            if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
                local ok, active = pcall(C_ChallengeMode.GetActiveChallengeMapID)
                if ok and tonumber(active) and tonumber(active) > 0 then
                    mapId = active
                end
            end

            if (tonumber(mapId) == nil) or (tonumber(mapId) <= 0) then
                if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
                    local ok, a = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
                    if ok and tonumber(a) and tonumber(a) > 0 then
                        mapId = a
                    end
                end
            end
        end

        -- Only start if we haven't already (via TWICH_DUNGEON_START)
        local db = GetDB()
        if not db.active or db.active.status ~= "in_progress" then
            self:_StartNewRun(mapId)
            self:_AppendEvent(eventName, { mapId = tonumber(mapId) or mapId }, { ... })
        end
        return
    end

    if eventName == "TWICH_DUNGEON_COMPLETION" then
        local completion = ...
        if type(completion) ~= "table" then
            completion = {}
        end

        local mapIdNum = tonumber(completion.mapID) or completion.mapID
        local level = tonumber(completion.level)
        local timeSec = tonumber(completion.timeSec)
        local timeMS = tonumber(completion.timeMS)
        if timeSec == nil and timeMS ~= nil then
            timeSec = timeMS / 1000
        elseif timeMS == nil and timeSec ~= nil then
            timeMS = timeSec * 1000
        end

        local db = GetDB()
        local run = db and db.active or nil
        local runId = run and run.id or nil
        local activeLevel = run and tonumber(run.level) or nil
        if not level then
            level = activeLevel
        end

        local calculatedScore, calcDetails
        if ScoreCalculator and type(ScoreCalculator.CalculateForRun) == "function" and level and timeSec then
            calculatedScore, calcDetails = ScoreCalculator.CalculateForRun(mapIdNum, level, timeSec)
        end

        local blizzardRunScore, blizzardMatch
        if ScoreCalculator and type(ScoreCalculator.TryGetBlizzardRunScore) == "function" and level and timeSec then
            blizzardRunScore, blizzardMatch = ScoreCalculator.TryGetBlizzardRunScore(mapIdNum, level, timeSec)
        end

        -- Keep the *recorded event payload* as close as possible to what DungeonMonitor emitted.
        -- We'll still compute a normalized summary for `run.completion` below.
        local normalized = {
            mapId = mapIdNum,
            mapID = mapIdNum, -- keep old casing too
            level = level,
            timeSec = timeSec,
            timeMS = timeMS,
            onTime = completion.onTime,
            upgradeLevels = completion.upgradeLevels,
            practiceRun = completion.practiceRun,
            source = completion.source,
        }

        local meta = {
            calculatedRunScore = calculatedScore,
            calculatedScoreDetails = calcDetails,
            blizzardRunScore = blizzardRunScore,
            blizzardRunScoreMatch = blizzardMatch,
            blizzardRunScoreSource = blizzardRunScore and "immediate_run_history" or nil,
        }

        self:_AppendEvent(eventName, completion, { ... }, { completion }, meta)

        -- Mark as completed but DO NOT finalize yet.
        -- We wait for PLAYER_ENTERING_WORLD (leaving the instance) to capture loot.
        if run then
            run.status = "completed"
            run.completion = normalized
            run.completionMeta = meta
        end

        -- Best-effort retry: run history data (and thus runScore) may not be available immediately.
        if (not blizzardRunScore) and C_Timer and type(C_Timer.After) == "function" and runId and mapIdNum and level and timeSec then
            C_Timer.After(1.0, function()
                local db2 = GetDB()
                local targetRun = db2 and db2.active
                if not targetRun or targetRun.id ~= runId then
                    targetRun = db2 and db2.lastCompleted
                end
                if not targetRun or targetRun.id ~= runId or type(targetRun.completion) ~= "table" then
                    return
                end
                if targetRun.completion.blizzardRunScore ~= nil then
                    return
                end

                local score2, match2
                if ScoreCalculator and type(ScoreCalculator.TryGetBlizzardRunScore) == "function" then
                    score2, match2 = ScoreCalculator.TryGetBlizzardRunScore(mapIdNum, level, timeSec)
                end
                if score2 ~= nil then
                    targetRun.completion.blizzardRunScore = score2
                    targetRun.completion.blizzardRunScoreMatch = match2
                    targetRun.completion.blizzardRunScoreSource = "delayed_run_history"
                    if type(targetRun.completionMeta) == "table" then
                        targetRun.completionMeta.blizzardRunScore = score2
                        targetRun.completionMeta.blizzardRunScoreMatch = match2
                        targetRun.completionMeta.blizzardRunScoreSource = "delayed_run_history"
                    end
                end
            end)
        end

        return
    end

    if eventName == "CHALLENGE_MODE_COMPLETED" then
        -- Modern WoW doesn't reliably fire CHALLENGE_MODE_COMPLETED_REWARDS.
        -- Treat this as a marker only; completion details come via TWICH_DUNGEON_COMPLETION.
        self:_AppendEvent(eventName, {}, { ... })

        local db = GetDB()
        if db.active and db.active.status ~= "completed" then
            db.active.status = "completed"
        end

        -- If TWICH_DUNGEON_COMPLETION didn't fire, try to snapshot completion info right now.
        if db.active and type(db.active.completion) ~= "table" and C_ChallengeMode then
            local mapID, level, timeVal, onTime, upgradeLevels, practiceRun

            if type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
                local ok, a, b, c, d, e, f = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
                if ok then
                    mapID, level, timeVal, onTime, upgradeLevels, practiceRun = a, b, c, d, e, f
                end
            end

            if (timeVal == nil) and type(C_ChallengeMode.GetCompletionInfo) == "function" then
                local ok, a, b, c, d, e = pcall(C_ChallengeMode.GetCompletionInfo)
                if ok then
                    mapID, level, timeVal, onTime, upgradeLevels = a, b, c, d, e
                end
            end

            local timeSec, timeMS
            local tv = tonumber(timeVal)
            if tv then
                if tv > 10000 then
                    timeMS = tv
                    timeSec = tv / 1000
                else
                    timeSec = tv
                    timeMS = tv * 1000
                end
            end

            if timeSec or level or mapID then
                local mapIdNum = tonumber(mapID) or tonumber(db.active.mapId) or mapID or db.active.mapId
                local lvlNum = tonumber(level) or tonumber(db.active.level)
                db.active.completion = {
                    mapId = mapIdNum,
                    mapID = mapIdNum,
                    level = lvlNum,
                    timeSec = timeSec,
                    timeMS = timeMS,
                    onTime = (type(onTime) == "boolean") and onTime or nil,
                    upgradeLevels = tonumber(upgradeLevels) or nil,
                    practiceRun = (type(practiceRun) == "boolean") and practiceRun or nil,
                    source = "CHALLENGE_MODE_COMPLETED_fallback",
                }
            end
        end

        return
    end

    if eventName == "CHALLENGE_MODE_DEATH_COUNT_UPDATED" then
        local count = ...
        -- If the event doesn't provide the count, fetch it.
        if not count and C_ChallengeMode and C_ChallengeMode.GetDeathCount then
            count = C_ChallengeMode.GetDeathCount()
        end
        -- Keep original args for transparency, but also record the resolved count for simulation.
        self:_AppendEvent(eventName, { count = count }, { ... }, { count })

        return
    end

    if eventName == "CHALLENGE_MODE_RESET" then
        local mapId = ...
        self:_AppendEvent(eventName, { mapId = tonumber(mapId) or mapId }, { ... })
        self:_FinalizeRun("reset", { mapId = tonumber(mapId) or mapId })
        return
    end

    if eventName == "ENCOUNTER_START" then
        local encounterID, encounterName, difficultyID, groupSize = ...
        self:_AppendEvent(eventName, {
            encounterID = encounterID,
            encounterName = encounterName,
            difficultyID = difficultyID,
            groupSize = groupSize,
        }, { ... })
        return
    end

    if eventName == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        self:_AppendEvent(eventName, {
            encounterID = encounterID,
            encounterName = encounterName,
            difficultyID = difficultyID,
            groupSize = groupSize,
            success = success,
        }, { ... })
        return
    end

    if eventName == "PLAYER_DEAD" then
        self:_AppendEvent(eventName, { unit = "player" }, { ... })
        return
    end

    if eventName == "GROUP_ROSTER_UPDATE" then
        local groupSnapshot = BuildGroupSnapshot()
        local db = GetDB()
        if db.active then
            db.active.group = groupSnapshot
        end
        self:_AppendEvent(eventName, { group = groupSnapshot }, { ... })
        return
    end

    if eventName == "PLAYER_ENTERING_WORLD" then
        -- Keep payload minimal; this fires often and can include instance transitions.
        local isInitialLogin, isReloadingUi = ...
        local isCM = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive()

        local activeMapID
        if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
            if tonumber(activeMapID) and tonumber(activeMapID) > 0 then
                -- Some loads/transitions report IsChallengeModeActive() = false briefly even while a key is active.
                -- Prefer the presence of an active challenge map to avoid prematurely finalizing the run.
                isCM = true
            end
        end

        self:_AppendEvent(eventName, {
            isInitialLogin = isInitialLogin,
            isReloadingUi = isReloadingUi,
            isChallengeModeActive = isCM, -- Log for debugging
        }, { ... })

        -- Failsafe: Ensure run is finalized if we are no longer in a challenge mode
        local db = GetDB()
        if db.active then
            if not isCM then
                -- Delay the failsafe a bit: PLAYER_ENTERING_WORLD can fire during load screens
                -- while CM APIs still return false/nil for a moment.
                if not db.active.__twichuiPendingCMCheck then
                    db.active.__twichuiPendingCMCheck = true
                    if C_Timer and type(C_Timer.After) == "function" then
                        C_Timer.After(1.0, function()
                            local db2 = GetDB()
                            if not db2.active then return end
                            if db2.active.__twichuiPendingCMCheck ~= true then return end
                            db2.active.__twichuiPendingCMCheck = nil

                            local stillCM = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive()
                            local stillActiveMap
                            if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
                                stillActiveMap = C_ChallengeMode.GetActiveChallengeMapID()
                            end
                            if stillCM or (tonumber(stillActiveMap) and tonumber(stillActiveMap) > 0) then
                                return
                            end

                            self:_AppendEvent("FAILSAFE_FINISH", { reason = "not_in_challenge_mode" })

                            -- If the run was already marked completed (by completion event), finalize as completed.
                            -- Otherwise, if we left without completion, it's an abandon/reset.
                            local status = (db2.active.status == "completed") and "completed" or "abandoned"
                            self:_FinalizeRun(status)
                        end)
                    else
                        self:_AppendEvent("FAILSAFE_FINISH", { reason = "not_in_challenge_mode" })
                        local status = (db.active.status == "completed") and "completed" or "abandoned"
                        self:_FinalizeRun(status)
                    end
                end
            else
                db.active.__twichuiPendingCMCheck = nil
            end
        end
        return
    end

    if eventName == "CHAT_MSG_LOOT" then
        local db = GetDB()
        if not db.active then
            return
        end

        local msg, playerName, _, _, _, _, _, _, _, _, lineId, guid = ...
        if not IsPlayerLootEvent(playerName, guid) then
            return
        end
        local links = ExtractItemLinks(msg)
        local qty = TryExtractQuantity(msg)
        local bracketName = TryExtractBracketItemName(msg)

        local items = {}
        if type(links) == "table" then
            for _, link in ipairs(links) do
                local itemId = TryGetItemIdFromLink(link)
                items[#items + 1] = {
                    itemId = itemId,
                    link = link,
                    info = GetItemInfoTable(link),
                }
                if #items >= 10 then
                    break
                end
            end
        end

        self:_AppendEvent("CHAT_MSG_LOOT", {
            message = msg,
            player = playerName,
            guid = guid,
            lineId = lineId,
            itemLinks = links,
            itemNameText = bracketName,
            items = items,
            quantity = qty,
        }, { ... })
        return
    end

    -- Fallback: store raw args
    self:_AppendEvent(eventName, { args = { ... } }, { ... })
end

local function MigrateLegacyEnableKey()
    local legacy = CM:GetProfileSettingSafe(LEGACY_ENABLE_KEY, nil)
    if type(legacy) == "boolean" then
        local current = CM:GetProfileSettingSafe(CONFIGURATION.ENABLE.key, nil)
        if type(current) ~= "boolean" then
            CM:SetProfileSettingSafe(CONFIGURATION.ENABLE.key, legacy)
        end
    end
end

function MythicPlusRunLogger:Enable()
    if self.enabled then return end
    Module:Enable()
    self.enabled = true

    if not DungeonMonitor or type(DungeonMonitor.RegisterCallback) ~= "function" then
        Logger.Warn("Mythic plus run logger enabled, but DungeonMonitor is unavailable")
        return
    end

    if self._callbackHandle then
        DungeonMonitor:UnregisterCallback(self._callbackHandle)
        self._callbackHandle = nil
    end

    self._callbackHandle = DungeonMonitor:RegisterCallback(function(eventName, ...)
        self:_OnDungeonEvent(eventName, ...)
    end)

    Logger.Debug("Mythic plus run logger enabled")
end

function MythicPlusRunLogger:Disable()
    if not self.enabled then return end
    Module:Disable()
    self.enabled = false

    if DungeonMonitor and self._callbackHandle then
        DungeonMonitor:UnregisterCallback(self._callbackHandle)
        self._callbackHandle = nil
    end

    if self._frame then
        self._frame:Hide()
    end

    Logger.Debug("Mythic plus run logger disabled")
end

function MythicPlusRunLogger:Initialize()
    if self.enabled then return end

    if RunLoggerSync and RunLoggerSync.Initialize then
        RunLoggerSync:Initialize()
    end

    MigrateLegacyEnableKey()

    local shouldEnable = CM:GetProfileSettingSafe(CONFIGURATION.ENABLE.key, nil)
    if type(shouldEnable) ~= "boolean" then
        shouldEnable = CM:GetProfileSettingByConfigEntry(CONFIGURATION.ENABLE)
    end

    if shouldEnable then
        self:Enable()
    end
end

function MythicPlusRunLogger:GetLastRun()
    local db = GetDB()
    return db and db.lastCompleted
end
