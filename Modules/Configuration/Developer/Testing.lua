--[[
        Developer Testing Tools
        Tools for simulating in-game events to exercise addon logic.
]]
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type LoggerModule
local Logger = T:GetModule("Logger")
---@type LootMonitorModule
local LootMonitor = T:GetModule("LootMonitor")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperTestingConfiguration
local DT = CM.Developer.Testing or {}
CM.Developer.Testing = DT

--- Create the developer testing configuration panels
--- @param order number The order of the panel
function DT:Create(order)
    ---@return MythicPlusModule module
    local function GetModule()
        return T:GetModule("MythicPlus")
    end

    ---@type ConfigEntry
    local mythicPlusDefaultEvent = {
        key = "developer.testing.mythicPlus.simulateEvent.event",
        default = GetModule()
            .Simulator.SupportedEvents[1]
    }
    return {
        type = "group",
        name = "Testing",
        order = order,
        childGroups = "tab",
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Tools in this tab simulate events so you can test addon logic without needing real in-game triggers."
            ),
            lootSimGroup = {
                type = "group",
                name = "Loot Simulation",
                order = 1,
                args = {
                    lootSimDesc = {
                        type = "description",
                        order = 1,
                        name =
                        "Enter an itemID or an itemLink (recommended). Quantity controls the simulated stack size. This triggers Loot Monitor's normal LOOT_RECEIVED pipeline (valuation, notifications, GPH tracking, etc.).",
                    },
                    itemInput = {
                        type = "input",
                        name = "Item (ID or Link)",
                        desc =
                        "Examples: 19019 or |cffff8000|Hitem:19019::::::::70:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
                        order = 2,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.testing.simulateLoot.item", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.testing.simulateLoot.item", value)
                        end,
                    },
                    quantityInput = {
                        type = "range",
                        name = "Quantity",
                        desc = "Quantity to simulate looting.",
                        order = 3,
                        min = 1,
                        max = 200,
                        step = 1,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.testing.simulateLoot.quantity", 1)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.testing.simulateLoot.quantity", value)
                        end,
                    },
                    simulateLoot = {
                        type = "execute",
                        name = "Simulate Loot",
                        desc = "Simulates receiving the specified item.",
                        order = 4,
                        func = function()
                            local item = CM:GetProfileSettingSafe("developer.testing.simulateLoot.item", "")
                            local quantity = CM:GetProfileSettingSafe("developer.testing.simulateLoot.quantity", 1)

                            if type(item) ~= "string" or item:gsub("%s+", "") == "" then
                                Logger.Warn("Simulate Loot: Please enter an itemID or itemLink.")
                                return
                            end

                            LootMonitor:SimulateLoot(item, quantity)
                        end
                    },
                },
            },
            mythicPlusGroup = {
                type = "group",
                name = "Mythic+ Simulation",
                order = 2,
                args = {
                    addRunGrp = {
                        type = "group",
                        inline = true,
                        name = "Fake Run",
                        order = 1,
                        args = {
                            addRunDesc = CM.Widgets:ComponentDescription(1,
                                "Add a fake Mythic+ run to the database for testing the Runs panel."),
                            addRun = {
                                type = "execute",
                                name = "Add Dummy Run",
                                desc = "Adds a fake Mythic+ run to the database for testing Run tables.",
                                order = 2,
                                func = function()
                                    local MythicPlus = T:GetModule("MythicPlus")
                                    if not MythicPlus or not MythicPlus.Database then
                                        Logger.Error("MythicPlus module or database not found.")
                                        return
                                    end

                                    local mapIds = {}
                                    local C_MythicPlus = _G.C_MythicPlus
                                    local C_ChallengeMode = _G.C_ChallengeMode

                                    if C_MythicPlus and C_MythicPlus.GetCurrentSeason and C_MythicPlus.GetSeasonMaps then
                                        local seasonId = C_MythicPlus.GetCurrentSeason()
                                        local maps = seasonId and C_MythicPlus.GetSeasonMaps(seasonId)
                                        if maps then
                                            for _, id in ipairs(maps) do
                                                table.insert(mapIds, id)
                                            end
                                        end
                                    end

                                    if #mapIds == 0 and C_ChallengeMode and C_ChallengeMode.GetMapTable then
                                        local maps = C_ChallengeMode.GetMapTable()
                                        if maps then
                                            for _, id in ipairs(maps) do
                                                table.insert(mapIds, id)
                                            end
                                        end
                                    end

                                    if #mapIds == 0 then
                                        mapIds = { 375, 376, 377, 378, 379, 380, 381, 382 } -- Fallback
                                    end

                                    local mapId = mapIds[math.random(#mapIds)]
                                    local level = math.random(2, 25)
                                    local duration = math.random(1200, 2400)
                                    local score = math.random(100, 300)
                                    local upgrade = math.random(0, 3)

                                    local run = {
                                        timestamp = _G.time(),
                                        date = date("%Y-%m-%d %H:%M:%S"),
                                        mapId = mapId,
                                        level = level,
                                        time = duration,
                                        score = score,
                                        upgrade = upgrade > 0 and upgrade or nil,
                                        onTime = upgrade > 0,
                                        affixes = { 9, 10 }, -- Tyrannical, etc.
                                        group = {
                                            tank = "Protection Paladin",
                                            healer = "Restoration Druid",
                                            dps1 = "Frost Mage",
                                            dps2 = "Havoc Demon Hunter",
                                            dps3 = "Augmentation Evoker",
                                        },
                                        loot = {}
                                    }

                                    MythicPlus.Database:AddRun(run)
                                    Logger.Info("Added dummy run for map " .. mapId)

                                    -- Refresh UI if open
                                    if MythicPlus.Runs and MythicPlus.Runs.Refresh and MythicPlus.MainWindow then
                                        local panel = MythicPlus.MainWindow:GetPanelFrame("runs")
                                        if panel and panel:IsShown() then
                                            MythicPlus.Runs:Refresh(panel)
                                        end
                                    end
                                end
                            },

                        }
                    },
                    mythicPlusEventSimulationGrp = {
                        type = "group",
                        inline = true,
                        name = "Event Simulation",
                        order = 3,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Simulate an incoming Event from the WoW API to test event handling."),
                            eventSelectionBox = {
                                type = "select",
                                order = 2,
                                name = "Event",
                                desc = "Select the event to simulate.",
                                width = 2,
                                values = function()
                                    ---@type MythicPlusModule
                                    local MythicPlus = T:GetModule("MythicPlus")
                                    local events = {}
                                    for _, eventName in ipairs(MythicPlus.Simulator.SupportedEvents) do
                                        events[eventName] = eventName
                                    end
                                    return events
                                end,
                                get = function()
                                    return CM:GetProfileSettingByConfigEntry(mythicPlusDefaultEvent)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingByConfigEntry(mythicPlusDefaultEvent, value)
                                end,
                            },
                            simulateEvent = {
                                type = "execute",
                                name = "Simulate Event",
                                desc = "Simulates the selected event.",
                                order = 3,
                                func = function()
                                    local eventName = CM:GetProfileSettingByConfigEntry(mythicPlusDefaultEvent)

                                    if not eventName or eventName == "" then
                                        Logger.Warn("Please select an event to simulate.")
                                        return
                                    end

                                    local MythicPlus = GetModule()
                                    if not MythicPlus or not MythicPlus.Simulator then
                                        Logger.Error("MythicPlus module or simulator not found.")
                                        return
                                    end

                                    MythicPlus.Simulator:SimEvent(eventName)
                                end
                            }
                        }
                    }
                },
            },

        },
    }
end
