--[[
    TwichUI Core
    Contains the core logic to the addon, initializing the TwichUI engine.
]]

local _G = _G

local GetBuildInfo = GetBuildInfo
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local AceAddon, AceAddonMinor = _G.LibStub('AceAddon-3.0')
local CallbackHandler = _G.LibStub("CallbackHandler-1.0")

--[[
    ... in a top‑level addon Lua file is a special vararg containing the addon's name, and the addon's private table (often called the namespace)
]]
local AddOnName, Engine = ...
local T = AceAddon:NewAddon(AddOnName, 'AceConsole-3.0', 'AceEvent-3.0', 'AceTimer-3.0', 'AceHook-3.0')
T.DF = { profile = {}, global = {} }; T.privateVars = { profile = {} }
T.callbacks = T.callbacks or CallbackHandler:New(T)
-- wow metadata
T.wowMetadata = T.wowmetadata or {}
T.wowMetadata.wowpatch, T.wowMetadata.wowbuild, T.wowMetadata.wowdate, T.wowMetadata.wowtoc = GetBuildInfo()
-- addon metadata
T.addonMetadata = T.addonMetadata or {}
T.addonMetadata.addonName = AddOnName

Engine[1] = T
Engine[2] = T.privateVars.profile
Engine[3] = T.DF.profile
Engine[4] = T.DF.global
_G.Twich = Engine

--[[
    Twich Modules
]]
---@class ToolsModule : AceModule
---@field Colors Colors?
---@field Text TextTool?
T.Tools = T:NewModule("Tools")
---@type LoggerModule
T.Logger = T:NewModule("Logger")
T.LootMonitor = T:NewModule("LootMonitor")
---@class MediaModule : AceModule
---@field Font FontModule?
---@field Sound SoundModule?
T.Media = T:NewModule("Media")
T.Configuration = T:NewModule("Configuration")
T.ThirdPartyAPI = T:NewModule("ThirdPartyAPI")

--[[
    Register Libraries to Engine
]]
do
    T.Libs = {}
    T.LibsMinor = {}

    function T:AddLib(name, major, minor)
        if not name then return end

        -- in this case: `major` is the lib table and `minor` is the minor version
        if type(major) == 'table' and type(minor) == 'number' then
            T.Libs[name], T.LibsMinor[name] = major, minor
        else -- in this case: `major` is the lib name and `minor` is the silent switch
            T.Libs[name], T.LibsMinor[name] = _G.LibStub(major, minor)
        end
    end

    T:AddLib("AceAddon", AceAddon, AceAddonMinor)
    T:AddLib("AceDB", "AceDB-3.0")
    T:AddLib("LSM", "LibSharedMedia-3.0")
    T:AddLib("Masque", "Masque", true)

    -- libraries used for options
    T:AddLib('AceGUI', 'AceGUI-3.0')
    T:AddLib('AceConfig', 'AceConfig-3.0-ElvUI') -- we have a dependency on ElvUI, this should be OK
    T:AddLib('AceConfigDialog', 'AceConfigDialog-3.0-ElvUI')
    T:AddLib('AceConfigRegistry', 'AceConfigRegistry-3.0-ElvUI')
    T:AddLib('AceDBOptions', 'AceDBOptions-3.0')
end

--[[
    Setup database baseline
]]
do
    local tables = {
        DataTexts = "datatexts",
        Modules = "modules"
    }

    function T:SetupDB()
        for key, value in next, tables do
            local module = T[key]
            if module then
                module.db = T.db[value]
            end
        end
    end
end

--[[
    Obtain AddOn metadata
]]
do
    local version = GetAddOnMetadata(AddOnName, 'Version')
    T.addonMetadata.version = version
end

--- Called by AceAddon when the addon is initialized. Sets up the database baseline, configures addon configuration panel, and registers events.
function T:OnInitialize()
    ---@type LoggerModule
    local Logger = T:GetModule("Logger")

    ---@type ConfigurationModule
    local Configuration = T:GetModule("Configuration")

    -- ensure AceDB runtime database exists (SavedVariables). If AceDB is available create the runtime DB.
    if not T.db then
        local AceDB = _G.LibStub and _G.LibStub("AceDB-3.0", true)
        if AceDB then
            -- use AddOnName.."DB" as the SavedVariables table name
            T.db = AceDB:New(AddOnName .. "DB", T.DF, true)
        end
    end

    -- setup database baseline (this assigns module.db = T.db[...] when available)
    T:SetupDB()

    -- If we have a runtime DB, expose its profile/global tables on the Engine
    if T.db and type(T.db) == "table" then
        Engine[3] = T.db.profile or T.DF.profile
        Engine[4] = T.db.global or T.DF.global
        _G.Twich = Engine
    end

    -- setup configuration
    Configuration:CreateAddonConfiguration()

    Logger.Info("AddOn initialized.")
end
