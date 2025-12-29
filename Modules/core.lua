--[[
    TwichUI Core
    Contains the core logic to the addon, initializing the TwichUI engine.
]]

local _G = _G

local GetBuildInfo = GetBuildInfo
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local LoadAddOn = C_AddOns.LoadAddOn


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
T.SlashCommands = T:NewModule("SlashCommands", "AceConsole-3.0")
T.GoldGoblin = T:NewModule("GoldGoblin")
T.DataTexts = T:NewModule("DataTexts")
T.MythicPlus = T:NewModule("MythicPlus")

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

--[[
    Setup the addon compartment function
]]
do
    function T:ToggleOptionsUI()
        local E, L, V, P, G = unpack(ElvUI)

        -- Ensure ElvUI options addon is loaded (try modern then legacy name)
        if not IsAddOnLoaded("ElvUI_OptionsUI") and not IsAddOnLoaded("ElvUI_Options") then
            local loaded = LoadAddOn("ElvUI_OptionsUI")
            if not loaded then
                loaded = LoadAddOn("ElvUI_Options")
            end
            if not loaded then
                print("TwichUI: Could not load ElvUI options addon.")
                return
            end
        end

        local opened
        if E and type(E.ToggleOptionsUI) == "function" then
            E:ToggleOptionsUI()
            opened = true
        elseif E and type(E.ToggleOptions) == "function" then
            E:ToggleOptions()
            opened = true
        end

        if not opened then
            print("TwichUI: Unable to open ElvUI options (missing toggle function).")
            return
        end

        -- Prefer ElvUI-patched AceConfig variants if available
        local ACD = (T.Libs and T.Libs.AceConfigDialog)
            or _G.LibStub("AceConfigDialog-3.0-ElvUI", true)
            or _G.LibStub("AceConfigDialog-3.0", true)
        local ACR = (T.Libs and T.Libs.AceConfigRegistry)
            or _G.LibStub("AceConfigRegistry-3.0-ElvUI", true)
            or _G.LibStub("AceConfigRegistry-3.0", true)
        if ACR and ACR.NotifyChange then
            pcall(ACR.NotifyChange, ACR, "ElvUI")
        end

        if ACD and ACD.SelectGroup then
            local tries, maxTries, delay = 0, 20, 0.1 -- up to ~2s total
            local function trySelect()
                tries = tries + 1
                local ok = pcall(ACD.SelectGroup, ACD, "ElvUI", "TwichUI")
                if not ok then
                    ok = pcall(ACD.SelectGroup, ACD, "ElvUI", "plugins", "TwichUI")
                end
                if not ok and _G.C_Timer and _G.C_Timer.After and tries < maxTries then
                    _G.C_Timer.After(delay, trySelect)
                elseif not ok and tries >= maxTries then
                    print("TwichUI: Could not focus TwichUI in ElvUI options.")
                end
            end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(delay, trySelect)
            else
                trySelect()
            end
        end
    end

    _G.TwichUI_AddonCompartmentFunc = function()
        T:ToggleOptionsUI()
    end
end

-- Auto-open options handler (enable/disable)
do
    local auto = {
        frame = nil,
        enabled = false,
        tries = 0,
        maxTries = 20,
        delay = 0.2,
    }

    local function tryOpen()
        auto.tries = auto.tries + 1
        local ok = pcall(function() T:ToggleOptionsUI() end)
        if ok then
            -- success, stop further attempts
            if auto.frame then
                auto.frame:UnregisterEvent("PLAYER_LOGIN")
            end
            auto.enabled = false
            return
        end
        if auto.tries < auto.maxTries and _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(auto.delay, tryOpen)
        else
            auto.enabled = false
        end
    end

    function T:StartAutoOpenOptions()
        if auto.enabled then return end
        auto.enabled = true
        auto.tries = 0
        if not auto.frame then
            auto.frame = _G.CreateFrame("Frame")
            auto.frame:SetScript("OnEvent", function(self, event, ...)
                if event == "PLAYER_LOGIN" then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0.2, tryOpen)
                    else
                        tryOpen()
                    end
                end
            end)
        end
        auto.frame:RegisterEvent("PLAYER_LOGIN")
    end

    function T:StopAutoOpenOptions()
        if not auto.enabled then return end
        auto.enabled = false
        if auto.frame then
            auto.frame:UnregisterEvent("PLAYER_LOGIN")
        end
    end
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

    if Configuration:GetProfileSettingSafe("general.showWelcomeMessageOnLogin", true) then
        Logger.Info("Welcome! v" ..
            T.Tools.Text.Color(T.Tools.Colors.TWICH.SECONDARY_ACCENT, T.addonMetadata.version) ..
            " loaded. Use '/twich help' for a list of available commands.")
    end

    if Configuration:GetProfileSettingSafe("developer.convenience.autoOpenConfig", false) then
        -- Start the auto-open handler (can be enabled/disabled via Start/Stop)
        pcall(function() T:StartAutoOpenOptions() end)
    end
end
