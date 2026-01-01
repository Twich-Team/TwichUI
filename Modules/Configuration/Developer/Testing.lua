--[[
        Developer Testing Tools
        Tools for simulating in-game events to exercise addon logic.
]]
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)
---@diagnostic disable: undefined-field

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

    local function GetSimulatorSupportedEvents()
        local ok, mp = pcall(function() return GetModule() end)
        if not ok or not mp or not mp.Simulator or type(mp.Simulator.SupportedEvents) ~= "table" then
            return { "CHALLENGE_MODE_START" }
        end
        if #mp.Simulator.SupportedEvents == 0 then
            return { "CHALLENGE_MODE_START" }
        end
        return mp.Simulator.SupportedEvents
    end

    local function RefreshSummaryIfOpen()
        ---@type MythicPlusModule
        local MythicPlus = GetModule()
        if not MythicPlus or not MythicPlus.MainWindow or not MythicPlus.Summary then
            return
        end
        if type(MythicPlus.MainWindow.GetPanelFrame) ~= "function" then
            return
        end

        local panel = MythicPlus.MainWindow:GetPanelFrame("summary")
        if panel and panel.IsShown and panel:IsShown() and type(MythicPlus.Summary.Refresh) == "function" then
            MythicPlus.Summary:Refresh(panel)
        end
    end

    ---@type ConfigEntry
    local mythicPlusDefaultEvent = {
        key = "developer.testing.mythicPlus.simulateEvent.event",
        default = (GetSimulatorSupportedEvents()[1] or "CHALLENGE_MODE_START")
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
                    summarySimGroup = {
                        type = "group",
                        inline = true,
                        name = "Summary Simulation",
                        order = 2,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Simulate a Mythic+ score and reward obtained state for the Summary panel's Season progress bar."),
                            enabled = {
                                type = "toggle",
                                name = "Enable Summary Simulation",
                                desc = "When enabled, the Season progress bar uses the simulated values below.",
                                order = 2,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.enabled", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.enabled",
                                        value)
                                    RefreshSummaryIfOpen()
                                end,
                            },
                            score = {
                                type = "range",
                                name = "Simulated Score",
                                desc = "Score used for the Season progress bar fill and remaining-to-next-reward text.",
                                order = 3,
                                min = 0,
                                max = 3500,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.score", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.summarySimulation.score",
                                        value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.enabled", false)
                                end,
                            },
                            obtained2000 = {
                                type = "toggle",
                                name = "Treat 2,000 reward as obtained",
                                order = 4,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained2000", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained2000", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.enabled", false)
                                end,
                            },
                            obtained2500 = {
                                type = "toggle",
                                name = "Treat 2,500 reward as obtained",
                                order = 5,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained2500", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained2500", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.enabled", false)
                                end,
                            },
                            obtained3000 = {
                                type = "toggle",
                                name = "Treat 3,000 reward as obtained",
                                order = 6,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained3000", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.obtained3000", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.summarySimulation.enabled", false)
                                end,
                            },
                        },
                    },
                    greatVaultSimGroup = {
                        type = "group",
                        inline = true,
                        name = "Great Vault Simulation",
                        order = 3,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Simulate Great Vault (Mythic+) progress and example iLvl values on the Summary panel."),
                            enabled = {
                                type = "toggle",
                                name = "Enable Great Vault Simulation",
                                desc = "When enabled, the Great Vault section uses the simulated values below.",
                                order = 2,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", value)
                                    RefreshSummaryIfOpen()
                                end,
                            },
                            totalRuns = {
                                type = "range",
                                name = "Dungeons Completed (total)",
                                desc = "Used for all slots (e.g., 3/4 and 3/8).",
                                order = 3,
                                min = 0,
                                max = 8,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.totalRuns", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.totalRuns", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", false)
                                end,
                            },
                            ilvl1 = {
                                type = "range",
                                name = "Example iLvl (Slot 1)",
                                desc = "Set to 0 to show —",
                                order = 4,
                                min = 0,
                                max = 700,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl1", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl1", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", false)
                                end,
                            },
                            ilvl4 = {
                                type = "range",
                                name = "Example iLvl (Slot 2)",
                                desc = "Set to 0 to show —",
                                order = 5,
                                min = 0,
                                max = 700,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl4", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl4", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", false)
                                end,
                            },
                            ilvl8 = {
                                type = "range",
                                name = "Example iLvl (Slot 3)",
                                desc = "Set to 0 to show —",
                                order = 6,
                                min = 0,
                                max = 700,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl8", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.ilvl8", value)
                                    RefreshSummaryIfOpen()
                                end,
                                disabled = function()
                                    return not CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultSimulation.enabled", false)
                                end,
                            },
                        },
                    },
                    mythicPlusEventSimulationGrp = {
                        type = "group",
                        inline = true,
                        name = "Event Simulation",
                        order = 4,
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
                                    local list = (MythicPlus and MythicPlus.Simulator and MythicPlus.Simulator.SupportedEvents)
                                    if type(list) ~= "table" then
                                        list = { "CHALLENGE_MODE_START" }
                                    end
                                    for _, eventName in ipairs(list) do
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

                                    if type(MythicPlus.Simulator.SimEvent) ~= "function" then
                                        Logger.Error("MythicPlus simulator does not support SimEvent().")
                                        return
                                    end

                                    MythicPlus.Simulator:SimEvent(eventName)
                                end
                            }
                        }
                    },
                    runSimulation = {
                        type = "group",
                        inline = true,
                        name = "Run Simulation",
                        order = 5,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Simulate a recorded run."),
                            viewReceivedRuns = {
                                type = "execute",
                                name = "Open Simulator",
                                desc = "Open the frame to view and simulate received run logs.",
                                order = 2,
                                func = function()
                                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                    if not ok or not mythicPlus then return end

                                    local frame = mythicPlus.RunSharingFrame
                                    if frame and type(frame.Toggle) == "function" then
                                        frame:Toggle()
                                    end
                                end,
                            },
                        }

                    },

                },
            },

        },
    }
end
