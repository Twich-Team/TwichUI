local T, W, I, C = unpack(Twich)

---@class LoggerModule : AceModule
---@field LEVELS LoggerLevels
---@field level LogLevel
local LM = T:GetModule("Logger")

---@type ToolsModule
local TM = T:GetModule("Tools")
---@type ConfigurationModule
local CM = T:GetModule("Configuration")

---@class LogLevel
---@field name string
---@field levelNumeric integer
---@field hexColor string

---@class LoggerLevels
---@field DEBUG LogLevel
---@field INFO LogLevel
---@field WARN LogLevel
---@field ERROR LogLevel
LM.LEVELS = {
    DEBUG = {
        name = "DEBUG",
        levelNumeric = 0,
        hexColor = "#6E7A8C",
    },
    INFO = {
        name = "INFO",
        levelNumeric = 1,
        hexColor = "#C2CAD6",
    },
    WARN = {
        name = "WARN",
        levelNumeric = 2,
        hexColor = "#FFCC66"
    },
    ERROR = {
        name = "ERROR",
        levelNumeric = 3,
        hexColor = "#FF6B6B",
    }
}

LM.level = LM.LEVELS.DEBUG



-- Safely obtain the logger prefix. Tools.Text may not be initialized at load time,
-- so build the prefix at runtime to avoid indexing a nil `Text` field.
local function GetLoggerPrefix()
    if TM and TM.Text and TM.Text.Color and TM.Colors and TM.Colors.TWICH then
        return TM.Text.Color(TM.Colors.TWICH.PRIMARY_ACCENT, "TwichUI: ") .. "%s"
    end
    return "TwichUI: %s"
end

-- Safe helpers to avoid indexing `TM.Text` when Tools isn't initialized yet.
local function SafeColor(hex, text)
    if TM and TM.Text and TM.Text.Color then
        return TM.Text.Color(hex, text)
    end
    return text or ""
end

local function SafePrint(text)
    if TM and TM.Text and TM.Text.PrintToChatFrame then
        TM.Text.PrintToChatFrame(text)
        return
    end
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
        return
    end

    -- final fallback: use global print which routes to the default chat frame in WoW
    if print then
        print(text)
    end
end


function LM:OnInitialize()
    SafePrint("Logger initialized.")
    local configLevel = CM:GetProfileSettingSafe("developer.logger.level", self.level)
    SafePrint("Logger level: " .. configLevel.name)
    self.level = configLevel
end

--- Applies formatting to text based on the log level supplied
--- @param message string the text to format
---@param level LogLevel the logging level the text is at
local function formatTextForLevel(message, level)
    -- handle the case of the supplied log text being nil
    if message == nil then
        message = "<nil> (caller: " .. debugstack(2, 1, 0) .. ")"
    end
    message = tostring(message)

    return GetLoggerPrefix():format(SafeColor(level.hexColor, message))
end

---@param level LogLevel the level to determine if it is below the configured level
---@return boolean isBelowConfiguredLevel Returns true if the provided level is below the overall configured level
local function isBelowConfiguredLevel(level)
    return level.levelNumeric < LM.level.levelNumeric
end

--- Write a log message at the DEBUG level
--- @param message string The message to log.
function LM.Debug(message)
    -- determine if this level is below the overall logging level
    if isBelowConfiguredLevel(LM.LEVELS.DEBUG) then
        return
    end

    local formattedText = formatTextForLevel(message, LM.LEVELS.DEBUG)
    SafePrint(formattedText)
end

--- Write a log message at the INFO level
--- @param message string The message to log.
function LM.Info(message)
    -- determine if this level is below the overall logging level
    if isBelowConfiguredLevel(LM.LEVELS.INFO) then
        return
    end

    local formattedText = formatTextForLevel(message, LM.LEVELS.INFO)
    SafePrint(formattedText)
end

--- Write a log message at the WARN level
--- @param message string The message to log.
function LM.Warn(message)
    -- determine if this level is below the overall logging level
    if isBelowConfiguredLevel(LM.LEVELS.WARN) then
        return
    end

    local formattedText = formatTextForLevel(message, LM.LEVELS.WARN)
    SafePrint(formattedText)
end

--- Write a log message at the ERROR level
--- @param message string The message to log.
function LM.Error(message)
    -- determine if this level is below the overall logging level
    if isBelowConfiguredLevel(LM.LEVELS.ERROR) then
        return
    end

    local formattedText = formatTextForLevel(message, LM.LEVELS.ERROR)
    SafePrint(formattedText)
end

--- Recursively prints a Lua value or table to chat for debugging.
--- Uses indentation to show table nesting levels.
--- Strings are printed via print(), which in WoW routes to the default chat frame.
--- @param t any The value or table to dump.
--- @param indent string|nil Current indentation prefix for nested tables (internal use).
function LM.DumpTable(t, indent)
    indent = indent or ""
    if type(t) ~= "table" then
        LM.Debug(indent .. tostring(t))
        return
    end

    for k, v in pairs(t) do
        local key = "[" .. tostring(k) .. "]"
        if type(v) == "table" then
            LM.Debug(indent .. key .. " = {")
            LM.DumpTable(v, indent .. "  ")
            LM.Debug(indent .. "}")
        else
            LM.Debug(indent .. key .. " = " .. tostring(v))
        end
    end
end
