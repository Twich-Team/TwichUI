local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

--- @type DataTextsConfigurationModule
local DT = CM.DataTexts or {}
CM.DataTexts = DT

--- @class GoblinDataTextConfigurationModule
local GDT = DT.Goblin or {}
DT.Goblin = GDT

function GDT:Create()
    ---@return GoblinDataText module
    local function GetModule()
        return T:GetModule("DataTexts").Goblin
    end

    return {
        displayGroup = {
            type = "group",
            name = "Display",
            inline = true,
            order = 1,
            args = {
                description = CM.Widgets:ComponentDescription(1, "Configure what the datatext displays on the panel."),
                displayMode = {
                    type = "select",
                    name = "Display Mode",
                    order = 2,
                    values = function()
                        local modes      = {}
                        local lmEnabled  = CM:GetProfileSettingSafe("lootMonitor.enable", false)
                        local gphEnabled = CM:GetProfileSettingSafe("lootMonitor.goldPerHourTracker.enabled", false)
                        local includeGPH = lmEnabled and gphEnabled

                        for _, mode in pairs(T.DataTexts.Goblin.DisplayModes) do
                            if mode and mode.id then
                                if mode.id == "gph" and not includeGPH then
                                    -- skip GPH if LootMonitor or GPH tracker disabled
                                elseif mode.hidden and type(mode.hidden) == "function" and mode:hidden() then
                                    -- skip other hidden modes
                                else
                                    modes[mode.id] = mode.name
                                end
                            end
                        end
                        return modes
                    end,
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE).id
                    end,
                    set = function(_, value)
                        local mode = nil

                        for i, data in pairs(T.DataTexts.Goblin.DisplayModes) do
                            if data.id == value then
                                mode = data
                                break
                            end
                        end
                        if not mode then
                            LM.Error("Failed to set Goblin datatext display mode - invalid mode id: " .. tostring(value))
                            return
                        end
                        CM:SetProfileSettingByConfigEntry(
                            GetModule():GetConfiguration().DISPLAY_MODE,
                            mode
                        )
                        GetModule():Refresh()
                    end,
                },
                goldWarning = {
                    type = "description",
                    name = TM.Text.Color(TM.Colors.TWICH.TEXT_ERROR,
                        "To properly display gold amounts, the Gold Tracker submodule within the Gold Goblin module must be enabled."),
                    order = 2.5,
                    hidden = function()
                        -- Use settings state so UI reflects user toggles immediately.
                        local goldGoblinEnabled = CM:GetProfileSettingSafe("goldGoblin.enable", false)
                        local goldTrackerEnabled = CM:GetProfileSettingSafe("goldGoblin.goldTracker.enable", false)
                        local modulesReady = goldGoblinEnabled and goldTrackerEnabled

                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        local isDefault = mode and mode.id == "default"

                        -- Hide when modules are ready OR when display mode is default.
                        -- Show only if (modules not ready) AND (mode is not default).
                        return modulesReady or isDefault
                    end
                },
                goldDisplayMode = {
                    type = "select",
                    name = "Gold Display Mode",
                    order = 3,
                    desc = "Determines how gold amounts are displayed.",
                    hidden = function()
                        local mode = CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().DISPLAY_MODE)
                        return mode and mode.id == "default"
                    end,
                    values = {
                        full = "Full",
                        short = "Short",
                    },
                    get = function()
                        return CM:GetProfileSettingByConfigEntry(GetModule():GetConfiguration().GOLD_DISPLAY_MODE)
                    end,
                    set = function(_, value)
                        CM:SetProfileSettingByConfigEntry(
                            GetModule():GetConfiguration().GOLD_DISPLAY_MODE,
                            value
                        )
                        GetModule():Refresh()
                    end,
                },
                color = CM.Widgets:DatatextColorSelectorGroup(
                    5,
                    GetModule():GetConfiguration().COLOR_MODE,
                    GetModule():GetConfiguration().CUSTOM_COLOR,
                    function()
                        GetModule():Refresh()
                    end
                ),
            }
        }
    }
end
