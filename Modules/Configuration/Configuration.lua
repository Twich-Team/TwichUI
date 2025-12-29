--[[
        ConfigurationModule
        The primary addon configuration is hosted within the ElvUI configuration panel to provide a consistent experience for users.
]]
local T, W, I, C = unpack(Twich)
local E, L, V, P, G = unpack(ElvUI)

--- @class ConfigurationModule
--- @field Widgets Widgets
--- @field MythicPlus MythicPlusConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
---@type LoggerModule
local LM = T:GetModule("Logger")

local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show
local ReloadUI = ReloadUI
-----------------------------------------------------------------------
-- Internal helpers
-----------------------------------------------------------------------

--- Splits a dotpath into parts: "a.b.c" -> { "a", "b", "c" }.
--- @param key string
--- @return string[] parts
local function SplitDotPath(key)
    local parts = {}

    if type(key) ~= "string" or key == "" then
        return parts
    end

    for part in string.gmatch(key, "([^%.]+)") do
        table.insert(parts, part)
    end

    return parts
end

--- Walks / creates nested tables under root using the path in parts,
--- and sets the final value. If any intermediate value is non-table,
--- the function aborts without writing.
--- @param root table
--- @param parts string[]
--- @param value any
local function SetByPath(root, parts, value)
    if type(root) ~= "table" or #parts == 0 then
        return false
    end

    local current = root
    local lastIndex = #parts

    for i = 1, lastIndex - 1 do
        local k = parts[i]
        local child = current[k]

        if child == nil then
            child = {}
            current[k] = child
        elseif type(child) ~= "table" then
            return
        end

        current = child
    end

    current[parts[lastIndex]] = value
    return true
end

--- Safely retrieves a value from root using the path in parts.
--- Returns default if any step fails.
--- @param root table
--- @param parts string[]
--- @param default any
--- @return any
local function GetByPath(root, parts, default)
    if type(root) ~= "table" or #parts == 0 then
        return default
    end

    local current = root

    for i = 1, #parts do
        local k = parts[i]
        if type(current) ~= "table" then
            return default
        end

        current = current[k]
        if current == nil then
            return default
        end
    end

    return current
end

-----------------------------------------------------------------------
-- Profile database access
-----------------------------------------------------------------------

--- Returns the addon's profile database.
--- @return table
function CM:GetProfileDB()
    -- Prefer the runtime AceDB profile table when available, then the live Engine exposure,
    -- then the unpacked `I` config (legacy), then the default profile table.
    if type(T) == "table" and type(T.db) == "table" and type(T.db.profile) == "table" then
        return T.db.profile
    end
    if _G.Twich and type(_G.Twich[3]) == "table" then
        return _G.Twich[3]
    end
    if type(I) == "table" and type(I.Config) == "table" then
        return I.Config
    end
    return T.DF and T.DF.profile or {}
end

--- Safely allows setting of a profile database setting via a dotpath string.
--- Example: key = "lootMonitor.goldPerHour.showDebug"
--- @param key string The dotpath to the setting (e.g. "a.b.c")
--- @param value any The value to set at the dotpath
function CM:SetProfileSettingSafe(key, value)
    local db = CM:GetProfileDB()
    local parts = SplitDotPath(key)

    if type(db) ~= "table" or #parts == 0 then
        return false
    end
    local ok = SetByPath(db, parts, value)
    if not ok and LM and LM.Error then
        LM.Error("Failed to write profile setting: " .. tostring(key))
    elseif ok and LM and LM.Debug then
        LM.Debug("Wrote profile setting: " .. tostring(key))
    end

    return ok
end

--- Safely retrieves a profile database setting via a dotpath string.
--- Example: key = "lootMonitor.goldPerHour.showDebug"
--- @param key string The dotpath to the setting (e.g. "a.b.c")
--- @param default any The default value to return if the setting does not exist
--- @return any The value at the dotpath, or the default value if the setting does not exist
function CM:GetProfileSettingSafe(key, default)
    local db = CM:GetProfileDB()
    local parts = SplitDotPath(key)

    if type(db) ~= "table" or #parts == 0 then
        return default
    end

    return GetByPath(db, parts, default)
end

local function GetImmediateCallerLine()
    if type(debugstack) == "function" then
        -- Skip frames: debugstack (1), helper (2), validator (3), utility (4) -> caller (5)
        local s = debugstack(5, 1, 0)
        local first = s and s:match("([^\n]*)")
        return first or "unknown"
    end
    return "unknown"
end

--- Validates that the supplied config entry is well-formed.
--- @param configEntry ConfigEntry
--- @return boolean isValid
local function ValidConfigEntry(configEntry)
    if type(configEntry) ~= "table" or type(configEntry.key) ~= "string" then
        LM.Error("Invalid ConfigEntry supplied. Caller: " .. GetImmediateCallerLine())
        return false
    end
    return true
end

---@class ConfigEntry
---@field key string The dotpath key for the setting
---@field default any The default value for the setting

--- Safely retrieves a profile database setting via a ConfigEntry.
--- @param configEntry ConfigEntry The configuration entry containing the key and default value
--- @return any The value at the dotpath, or the default value if the setting does not exist
function CM:GetProfileSettingByConfigEntry(configEntry)
    if not ValidConfigEntry(configEntry) then
        return nil
    end

    return CM:GetProfileSettingSafe(configEntry.key, configEntry.default)
end

--- Safely sets a profile database setting via a ConfigEntry.
--- @param configEntry ConfigEntry The configuration entry containing the key
--- @param value any The value to set at the dotpath
function CM:SetProfileSettingByConfigEntry(configEntry, value)
    if not ValidConfigEntry(configEntry) then
        return false
    end
    return CM:SetProfileSettingSafe(configEntry.key, value)
end

-----------------------------------------------------------------------
-- Global database access
-----------------------------------------------------------------------

--- Returns the addon's global database.
--- @return table
function CM:GetGlobalDB()
    return C.Config
end

--- Safely allows setting of a global database setting via a dotpath string.
--- @param key string
--- @param value any
function CM:SetGlobalSettingSafe(key, value)
    local db = CM:GetGlobalDB()
    local parts = SplitDotPath(key)

    if type(db) ~= "table" or #parts == 0 then
        return
    end

    SetByPath(db, parts, value)
end

--- Safely retrieves a global database setting via a dotpath string.
--- @param key string
--- @param default any
--- @return any
function CM:GetGlobalSettingSafe(key, default)
    local db = CM:GetGlobalDB()
    local parts = SplitDotPath(key)

    if type(db) ~= "table" or #parts == 0 then
        return default
    end

    return GetByPath(db, parts, default)
end

--- Discovers the name of the addon and formats it with the primary accent color.
--- @return string addonName the addon name formatted with the primary accent color
function CM:GetAddonNameFormatted()
    return TM.Text.Color(TM.Colors.TWICH.PRIMARY_ACCENT, T.addonMetadata.addonName)
end

--- Creates the addon's configuration options within the ElvUI configuration panel.
function CM:CreateAddonConfiguration()
    local TT = TM.Text
    local CT = TM.Colors
    --- primary entrypoint into addon configuration
    E.Options.args.TwichUI = {
        type = "group",
        name = TT.Color(CT.TWICH.PRIMARY_ACCENT, "TwichUI"),
        order = 100,
        args = {
            welcome = CM:CreateWelcomePanel(),
            general = CM:CreateGeneralConfiguration(),
            lootMonitor = CM:CreateLootMonitorConfiguration(),
            developer = CM:CreateDeveloperConfiguration(),
            goldGoblin = CM.GoldGoblin:Create(),
            dataTexts = CM.DataTexts:Create(20),
            mythicplus = CM.MythicPlus:Create(60),
        }
    }
end

local keywordColorMap = {
    { keyword = "TwichUI",          color = TM.Colors.TWICH.PRIMARY_ACCENT },
    { keyword = "submodule",        color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "submodules",       color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "module",           color = TM.Colors.TWICH.SECONDARY_ACCENT },
    { keyword = "modules",          color = TM.Colors.TWICH.SECONDARY_ACCENT },
    { keyword = "Loot Monitor",     color = TM.Colors.TWICH.SECONDARY_ACCENT },
    { keyword = "gold goblin",      color = TM.Colors.TWICH.SECONDARY_ACCENT },
    { keyword = "Mythic+",          color = TM.Colors.TWICH.SECONDARY_ACCENT },
    { keyword = "gold tracker",     color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "gold balancer",    color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "notable item",     color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "notable items",    color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "gold per hour",    color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "item valuation",   color = TM.Colors.TWICH.TERTIARY_ACCENT },
    { keyword = "performance",      color = TM.Colors.TWICH.TEXT_WARNING },
    { keyword = "TradeSkillMaster", color = TM.Colors.TWICH.GOLD_ACCENT },
    { keyword = "TSM",              color = TM.Colors.TWICH.GOLD_ACCENT },
    { keyword = "Masque",           color = TM.Colors.TWICH.GOLD_ACCENT },
    { keyword = "coming soon",      color = TM.Colors.TWICH.TEXT_SUCCESS }
}

--- Searches the supplied text for keywords and applies the appropriate color to them
--- @return string coloredText text in which keywords have been colored.
function CM:ColorTextKeywords(text)
    if type(text) ~= "string" or text == "" then
        return text
    end

    local coloredText = text

    -- Build a case-insensitive Lua pattern for each keyword and color matches while
    -- preserving the original casing in the output. Word frontiers (%f[%w]/%f[%W])
    -- prevent partial matches (e.g., "sub" inside "submodules").
    local function buildCaseInsensitivePattern(keyword)
        local core = ""
        for i = 1, #keyword do
            local ch = keyword:sub(i, i)
            if ch:match("%a") then
                core = core .. "[" .. ch:lower() .. ch:upper() .. "]"
            elseif ch:match("%d") then
                core = core .. ch
            else
                core = core .. ch:gsub("(%W)", "%%%1")
            end
        end
        return "%f[%w]" .. core .. "%f[%W]"
    end

    -- Longer keywords first to avoid shorter ones consuming parts of multi-word phrases.
    -- Use a Lua 5.1-safe shallow copy (no table.unpack in WoW's Lua).
    local sorted = {}
    for i = 1, #keywordColorMap do
        sorted[i] = keywordColorMap[i]
    end
    table.sort(sorted, function(a, b) return #a.keyword > #b.keyword end)

    for _, entry in ipairs(sorted) do
        if entry.keyword and entry.color then
            local pattern = buildCaseInsensitivePattern(entry.keyword)
            coloredText = coloredText:gsub(pattern, function(match)
                return TM.Text.Color(entry.color, match)
            end)
        end
    end

    return coloredText
end

--- Prompts the user to reload the UI.
function CM:PromptReloadUI()
    if type(StaticPopupDialogs) == "table" and type(StaticPopup_Show) == "function" then
        if not StaticPopupDialogs["TWICHUI_RELOAD_UI"] then
            StaticPopupDialogs["TWICHUI_RELOAD_UI"] = {
                text = "TwichUI: Some changes require a UI reload to fully apply. Reload now?",
                button1 = OKAY,
                button2 = CANCEL,
                OnAccept = function() ReloadUI() end,
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                preferredIndex = 3,
            }
        end
        StaticPopup_Show("TWICHUI_RELOAD_UI")
    end
end
