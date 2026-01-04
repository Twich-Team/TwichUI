---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

local _G = _G
---@diagnostic disable-next-line: undefined-field
local ReloadUI = _G.ReloadUI

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type ToolsModule
local TM = T:GetModule("Tools")
--- @type LoggerModule
local LM = T:GetModule("Logger")

CM.Developer = CM.Developer or {}
--- @class DeveloperDatabasesConfiguration
--- @field Create function function to create the logger configuration panels
CM.Developer.Databases = CM.Developer.Databases or {}

local DatabasesConfig = CM.Developer.Databases

--- Create the logger configuration panels
--- @param order number The order of the logger configuration panel
function DatabasesConfig:Create(order)
    return {
        type = "group",
        name = "Databases",
        order = order,
        args = {
            -- module description
            description = CM.Widgets:SubmoduleDescription(
                "Databases control the function of the entire addon. Proceed at your own risk."),
            clearGroup = {
                type = "group",
                name = "Clear Databases",
                inline = true,
                order = 2,
                args = {
                    clearGoldDB = {
                        type = "execute",
                        name = "Clear Gold Database",
                        order = 1,
                        desc = "Clears all stored gold data for all characters on the account.",
                        confirm = true,
                        confirmText = "This will permanently clear all stored gold data for all characters. Continue?",
                        func = function()
                            rawset(_G, "TwichUIGoldDB", {})
                            LM.Info("Cleared TwichUIGoldDB database.")
                        end
                    },
                    clearMythicPlusDB = {
                        type = "execute",
                        name = "Clear Mythic+ Runs Database",
                        desc = "Removes all Mythic+ runs from the database.",
                        order = 2,
                        func = function()
                            local MythicPlus = T:GetModule("MythicPlus")
                            if not MythicPlus or not MythicPlus.Database then return end

                            MythicPlus.Database:ClearRuns()

                            -- Refresh UI if open
                            if MythicPlus.Runs and MythicPlus.Runs.Refresh and MythicPlus.MainWindow then
                                local panel = MythicPlus.MainWindow:GetPanelFrame("runs")
                                if panel and panel:IsShown() then
                                    MythicPlus.Runs:Refresh(panel)
                                end
                            end
                            if MythicPlus.Dungeons and MythicPlus.Dungeons.Refresh and MythicPlus.MainWindow then
                                local panel = MythicPlus.MainWindow:GetPanelFrame("dungeons")
                                if panel and panel:IsShown() then
                                    MythicPlus.Dungeons:Refresh()
                                end
                            end
                        end
                    },

                    clearBiSItemCache = {
                        type = "execute",
                        name = "Clear BiS Item Cache",
                        desc = "Clears the stored Best in Slot item source cache so it will rebuild on demand.",
                        order = 3,
                        confirm = true,
                        confirmText =
                        "This clears the cached item source database (loot sources). It will rebuild automatically and may briefly slow the game. Continue?",
                        func = function()
                            local MythicPlus = T:GetModule("MythicPlus")
                            if MythicPlus and MythicPlus.BestInSlot and MythicPlus.BestInSlot.ClearItemCache then
                                MythicPlus.BestInSlot:ClearItemCache()
                                LM.Info("Cleared Best in Slot item cache.")
                            end
                        end
                    },
                }
            },

            dangerZoneGroup = {
                type = "group",
                name = "Danger Zone",
                inline = true,
                order = 3,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "This will wipe all TwichUI saved data (settings, profiles, and databases) and reload the UI."),
                    enableFullReset = {
                        type = "toggle",
                        name = "Enable 'Clear ALL' button",
                        desc = "Must be enabled before the full reset button can be used.",
                        order = 2,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.databases.enableFullReset", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.databases.enableFullReset", value)
                        end,
                    },
                    clearAllAddonData = {
                        type = "execute",
                        name = "|cffff0000Clear ALL Addon Data|r",
                        desc = "Wipes ALL TwichUI data (TwichUIDB + TwichUIGoldDB) and reloads the UI.",
                        order = 3,
                        confirm = true,
                        confirmText =
                        "This will permanently delete ALL TwichUI data (settings/profiles/databases/gold) and reload the UI. Continue?",
                        disabled = function()
                            return not CM:GetProfileSettingSafe("developer.databases.enableFullReset", false)
                        end,
                        func = function()
                            rawset(_G, "TwichUIDB", nil)
                            rawset(_G, "TwichUIGoldDB", nil)
                            LM.Info("Cleared ALL TwichUI SavedVariables. Reloading UI...")
                            if type(ReloadUI) == "function" then
                                ReloadUI()
                            end
                        end
                    },
                }
            },
        }
    }
end
