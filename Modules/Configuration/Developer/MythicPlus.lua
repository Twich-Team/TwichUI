---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)
---@diagnostic disable: undefined-field, inject-field

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
--- @type LoggerModule
local Logger = T:GetModule("Logger")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperMythicPlusConfiguration
local DMP = CM.Developer.MythicPlus or {}
CM.Developer.MythicPlus = DMP

--- Create the Mythic+ developer configuration panels
--- @param order number The order of the panel
function DMP:Create(order)
    ---@return MythicPlusModule|nil
    local function GetModule()
        local ok, mp = pcall(function() return T:GetModule("MythicPlus") end)
        if not ok then return nil end
        return mp
    end

    local function GetSimulatorSupportedEvents()
        local mp = GetModule()
        if not mp or not mp.Simulator or type(mp.Simulator.SupportedEvents) ~= "table" then
            return { "CHALLENGE_MODE_START" }
        end
        if #mp.Simulator.SupportedEvents == 0 then
            return { "CHALLENGE_MODE_START" }
        end
        return mp.Simulator.SupportedEvents
    end

    local function RefreshSummaryIfOpen()
        ---@type MythicPlusModule|nil
        local mp = GetModule()
        if not mp or not mp.MainWindow or not mp.Summary then
            return
        end
        if type(mp.MainWindow.GetPanelFrame) ~= "function" then
            return
        end

        local panel = mp.MainWindow:GetPanelFrame("summary")
        if panel and panel.IsShown and panel:IsShown() and type(mp.Summary.Refresh) == "function" then
            mp.Summary:Refresh(panel)
        end
    end

    ---@type ConfigEntry
    local mythicPlusDefaultEvent = {
        key = "developer.testing.mythicPlus.simulateEvent.event",
        default = (GetSimulatorSupportedEvents()[1] or "CHALLENGE_MODE_START")
    }

    local function GetRecordDataArgs()
        if CM.Developer.MythicPlusDataRecorder and type(CM.Developer.MythicPlusDataRecorder.Create) == "function" then
            local group = CM.Developer.MythicPlusDataRecorder:Create(0)
            if group and type(group.args) == "table" then
                return group.args
            end
        end

        return {
            description = {
                type = "description",
                order = 0,
                name = "Mythic+ Data Recorder configuration module is not available.",
            }
        }
    end

    return {
        type = "group",
        name = "Mythic+",
        order = order,
        childGroups = "tab",
        args = {
            simulationTab = {
                type = "group",
                name = "Simulation",
                order = 2,
                args = {
                    description = CM.Widgets:SubmoduleDescription(
                        "Tools for simulating Mythic+ data/events to exercise addon logic."),

                    headerSimButtonGrp = {
                        type = "group",
                        inline = true,
                        name = "Mythic+ Window",
                        order = 0.5,
                        args = {
                            desc = CM.Widgets:ComponentDescription(1,
                                "Show a simulator shortcut button in the Mythic+ window header."),
                            showHeaderButton = {
                                type = "toggle",
                                name = "Show Simulator Header Button",
                                desc = "Adds a play icon to the Mythic+ header that opens the Mythic+ Simulator window.",
                                order = 2,
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.mythicplus.showSimulatorHeaderButton",
                                        false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.mythicplus.showSimulatorHeaderButton",
                                        value and true or false)

                                    local mp = GetModule()
                                    if mp and mp.MainWindow and type(mp.MainWindow.UpdateSimulatorHeaderButton) == "function" then
                                        mp.MainWindow:UpdateSimulatorHeaderButton()
                                    end
                                end,
                            },
                        },
                    },

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
                                    local mp = GetModule()
                                    if not mp or not mp.Database then
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

                                    mp.Database:AddRun(run)
                                    Logger.Info("Added dummy run for map " .. mapId)

                                    -- Refresh UI if open
                                    if mp.Runs and mp.Runs.Refresh and mp.MainWindow then
                                        local panel = mp.MainWindow:GetPanelFrame("runs")
                                        if panel and panel:IsShown() then
                                            mp.Runs:Refresh(panel)
                                        end
                                    end
                                end
                            },
                        }
                    },

                    bisNotificationGrp = {
                        type = "group",
                        inline = true,
                        name = "BiS Notifications",
                        order = 2,
                        args = {
                            desc = CM.Widgets:ComponentDescription(1,
                                "Simulate receiving loot to test Best-in-Slot notifications."),
                            availabilityDesc = {
                                type = "description",
                                order = 1.5,
                                name =
                                "Availability tests simulate the same events Blizzard fires (Roll and Great Vault) for the best end-to-end testing.",
                            },
                            item = {
                                type = "input",
                                name = "Item",
                                desc = "ItemID or itemLink to simulate looting.",
                                order = 2,
                                width = 1.5,
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.testing.mythicPlus.bisNotifications.item",
                                        "19019")
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.bisNotifications.item", value)
                                end,
                            },
                            quantity = {
                                type = "range",
                                name = "Quantity",
                                order = 3,
                                min = 1,
                                max = 20,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.quantity", 1)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.bisNotifications.quantity",
                                        value)
                                end,
                            },
                            overrideIlvl = {
                                type = "range",
                                name = "Override iLvl (0 = use item)",
                                order = 4,
                                min = 0,
                                max = 1000,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.overrideIlvl", 0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.overrideIlvl", value)
                                end,
                            },
                            kind = {
                                type = "select",
                                name = "Force Kind",
                                desc = "Used only by Force Notification.",
                                order = 4.5,
                                values = {
                                    NEW = "NEW",
                                    UPGRADE = "UPGRADE",
                                    FOUND = "FOUND",
                                },
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.kind",
                                        "NEW")
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.bisNotifications.kind", value)
                                end,
                            },
                            previousIlvl = {
                                type = "range",
                                name = "Previous iLvl (Force only)",
                                order = 4.6,
                                min = 0,
                                max = 1000,
                                step = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.previousIlvl",
                                        0)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.previousIlvl",
                                        value)
                                end,
                            },
                            ensureSelected = {
                                type = "toggle",
                                name = "Temporarily add to BiS selection",
                                desc =
                                "When enabled, the test will temporarily add the item to your selected BiS list so the availability checks behave like real usage.",
                                order = 4.7,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureSelected", true)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureSelected", value)
                                end,
                            },
                            ensureEnabled = {
                                type = "toggle",
                                name = "Temporarily enable availability setting",
                                desc =
                                "When enabled, the test will temporarily turn on the Roll/Vault availability setting so you can validate the UI and sounds without changing your normal configuration.",
                                order = 4.8,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureEnabled", true)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureEnabled", value)
                                end,
                            },
                            simulate = {
                                type = "execute",
                                name = "Simulate Loot",
                                desc = "Runs the BiS notification check as if the player looted the item.",
                                order = 5,
                                func = function()
                                    local mp = GetModule()
                                    if not mp or not mp.BestInSlotNotificationHandler then
                                        Logger.Error("MythicPlus BiS notification handler not found.")
                                        return
                                    end

                                    local item = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.item",
                                        "19019")
                                    local qty = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.quantity", 1)
                                    local ilvl = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.overrideIlvl", 0)

                                    mp.BestInSlotNotificationHandler:TestSimulateLoot(item, qty, ilvl)
                                end
                            },
                            simulateRoll = {
                                type = "execute",
                                name = "Simulate Roll Availability",
                                desc = "Simulates Blizzard's START_LOOT_ROLL event for this item.",
                                order = 5.1,
                                func = function()
                                    local mp = GetModule()
                                    if not mp or not mp.BestInSlotNotificationHandler then
                                        Logger.Error("MythicPlus BiS notification handler not found.")
                                        return
                                    end

                                    local item = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.item",
                                        "19019")
                                    local qty = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.quantity", 1)
                                    local ensureSelected = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureSelected", true)
                                    local ensureEnabled = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureEnabled", true)

                                    mp.BestInSlotNotificationHandler:TestSimulateAvailabilityRoll(
                                        item,
                                        qty,
                                        ensureSelected,
                                        ensureEnabled
                                    )
                                end
                            },
                            simulateVault = {
                                type = "execute",
                                name = "Simulate Great Vault Availability",
                                desc =
                                "Simulates a Great Vault update where this item is available as a selectable reward.",
                                order = 5.2,
                                func = function()
                                    local mp = GetModule()
                                    if not mp or not mp.BestInSlotNotificationHandler then
                                        Logger.Error("MythicPlus BiS notification handler not found.")
                                        return
                                    end

                                    local item = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.item",
                                        "19019")
                                    local ensureSelected = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureSelected", true)
                                    local ensureEnabled = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.ensureEnabled", true)

                                    mp.BestInSlotNotificationHandler:TestSimulateAvailabilityVault(
                                        item,
                                        ensureSelected,
                                        ensureEnabled
                                    )
                                end
                            },
                            forceShow = {
                                type = "execute",
                                name = "Force Notification",
                                desc = "Always shows the notification (bypasses BiS selection/upgrade logic).",
                                order = 6,
                                func = function()
                                    local mp = GetModule()
                                    if not mp or not mp.BestInSlotNotificationHandler then
                                        Logger.Error("MythicPlus BiS notification handler not found.")
                                        return
                                    end

                                    local item = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.item",
                                        "19019")
                                    local qty = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.quantity", 1)
                                    local ilvl = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.overrideIlvl", 0)
                                    local kind = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.kind", "NEW")
                                    local prev = CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.bisNotifications.previousIlvl", 0)

                                    mp.BestInSlotNotificationHandler:TestForceNotification(
                                        item,
                                        kind,
                                        (tonumber(ilvl) and tonumber(ilvl) > 0) and tonumber(ilvl) or nil,
                                        (tonumber(prev) and tonumber(prev) > 0) and tonumber(prev) or nil,
                                        qty
                                    )
                                end
                            },
                        }
                    },

                    summarySimGroup = {
                        type = "group",
                        inline = true,
                        name = "Summary Simulation",
                        order = 3,
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
                            debugEnabled = {
                                type = "toggle",
                                name = "Enable Great Vault API Debug",
                                desc =
                                "Logs the raw C_WeeklyRewards activity fields used to determine Great Vault iLvl (once per activity per session).",
                                order = 7,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultDebug.enabled", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe(
                                        "developer.testing.mythicPlus.greatVaultDebug.enabled", value)
                                    RefreshSummaryIfOpen()
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
                                    ---@type MythicPlusModule|nil
                                    local mp = GetModule()
                                    local events = {}
                                    local list = (mp and mp.Simulator and mp.Simulator.SupportedEvents)
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

                                    local mp = GetModule()
                                    if not mp or not mp.Simulator then
                                        Logger.Error("MythicPlus module or simulator not found.")
                                        return
                                    end

                                    if type(mp.Simulator.SimEvent) ~= "function" then
                                        Logger.Error("MythicPlus simulator does not support SimEvent().")
                                        return
                                    end

                                    mp.Simulator:SimEvent(eventName)
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
                                    local mp = GetModule()
                                    if not mp then return end

                                    local frame = mp.RunSharingFrame
                                    if frame and type(frame.Toggle) == "function" then
                                        frame:Toggle()
                                    end
                                end,
                            },
                        }
                    },
                },
            },

            recordDataTab = {
                type = "group",
                name = "Record Data",
                order = 1,
                args = GetRecordDataArgs(),
            },

            convenienceTab = {
                type = "group",
                name = "Convenience",
                order = 3,
                args = {
                    description = CM.Widgets:SubmoduleDescription(
                        "Convenience settings related to Mythic+ development."),

                    autoShowMythicPlusGroup = {
                        type = "group",
                        inline = true,
                        name = "Mythic+ Window",
                        order = 1,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Automatically open the Mythic+ main window after /reload."),
                            autoShowMythicPlus = {
                                type = "toggle",
                                name = "Auto-show Mythic+ Window on Reload",
                                desc =
                                "If enabled, the Mythic+ main window will be shown automatically after /reload (when the Mythic+ module is enabled).",
                                order = 2,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.convenience.autoShowMythicPlusWindow",
                                        false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.convenience.autoShowMythicPlusWindow", value)
                                end,
                            },
                        }
                    },

                    portalMockGroup = {
                        type = "group",
                        name = "Portal Spell Mock",
                        inline = true,
                        order = 5,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Simulates a dungeon portal spell being present in your spellbook so you can test the Dungeons UI without actually unlocking the portal. This does not modify the real spellbook."),
                            enabled = {
                                type = "toggle",
                                name = "Enable Mock",
                                order = 1,
                                width = "full",
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.testing.mythicPlus.portalMock.enabled",
                                        false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.enabled", value)
                                    local mp = GetModule()
                                    if mp and mp.Dungeons and mp.Dungeons.ClearPortalSpellCache then
                                        mp.Dungeons:ClearPortalSpellCache()
                                    elseif mp and mp.Dungeons and mp.Dungeons.Refresh then
                                        mp.Dungeons:Refresh()
                                    end
                                end,
                            },
                            mapId = {
                                type = "input",
                                name = "Map ID (0 = all)",
                                desc =
                                "Set to a specific Challenge Mode mapID to mock only that dungeon, or 0 to apply to all dungeons.",
                                order = 2,
                                width = "full",
                                get = function()
                                    return tostring(CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.portalMock.mapId",
                                        0) or 0)
                                end,
                                set = function(_, value)
                                    local v = tonumber(value) or 0
                                    if v < 0 then v = 0 end
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.mapId", v)
                                    local mp = GetModule()
                                    if mp and mp.Dungeons and mp.Dungeons.ClearPortalSpellCache then
                                        mp.Dungeons:ClearPortalSpellCache()
                                    elseif mp and mp.Dungeons and mp.Dungeons.Refresh then
                                        mp.Dungeons:Refresh()
                                    end
                                end,
                            },
                            spellId = {
                                type = "input",
                                name = "Spell ID",
                                desc =
                                "SpellID to use as the mocked portal spell. For click-testing, pick a spell you actually know; otherwise it may not cast.",
                                order = 3,
                                width = "full",
                                get = function()
                                    return tostring(CM:GetProfileSettingSafe(
                                        "developer.testing.mythicPlus.portalMock.spellId",
                                        0) or 0)
                                end,
                                set = function(_, value)
                                    local v = tonumber(value) or 0
                                    if v < 0 then v = 0 end
                                    CM:SetProfileSettingSafe("developer.testing.mythicPlus.portalMock.spellId", v)
                                    local mp = GetModule()
                                    if mp and mp.Dungeons and mp.Dungeons.ClearPortalSpellCache then
                                        mp.Dungeons:ClearPortalSpellCache()
                                    elseif mp and mp.Dungeons and mp.Dungeons.Refresh then
                                        mp.Dungeons:Refresh()
                                    end
                                end,
                            },
                            clearCache = {
                                type = "execute",
                                name = "Clear Portal Cache",
                                desc = "Clears the cached portal-spell lookup results so the UI re-checks immediately.",
                                order = 4,
                                func = function()
                                    local mp = GetModule()
                                    if mp and mp.Dungeons and mp.Dungeons.ClearPortalSpellCache then
                                        mp.Dungeons:ClearPortalSpellCache()
                                    elseif mp and mp.Dungeons and mp.Dungeons.Refresh then
                                        mp.Dungeons:Refresh()
                                    end
                                end,
                            },
                        }
                    },

                    portalDataGroup = {
                        type = "group",
                        name = "Dungeon Portals",
                        inline = true,
                        order = 6,
                        args = {
                            description = CM.Widgets:ComponentDescription(1,
                                "Print the current Mythic+ dungeon mapIDs so you can update portal data."),
                            printSeasonMaps = {
                                type = "execute",
                                name = "Print Current Season Map IDs",
                                desc = "Prints lines like: [mapID] = \"Dungeon Name\"",
                                order = 2,
                                func = function()
                                    local ids = {}

                                    local C_MythicPlus = _G.C_MythicPlus
                                    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" and type(C_MythicPlus.GetSeasonMaps) == "function" then
                                        local okS, seasonID = pcall(C_MythicPlus.GetCurrentSeason)
                                        seasonID = okS and tonumber(seasonID) or nil
                                        if seasonID then
                                            local okM, maps = pcall(C_MythicPlus.GetSeasonMaps, seasonID)
                                            if okM and type(maps) == "table" then
                                                for _, id in ipairs(maps) do
                                                    id = tonumber(id)
                                                    if id then ids[#ids + 1] = id end
                                                end
                                            end
                                        end
                                    end

                                    local C_ChallengeMode = _G.C_ChallengeMode
                                    if #ids == 0 and C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
                                        local okT, maps = pcall(C_ChallengeMode.GetMapTable)
                                        if okT and type(maps) == "table" then
                                            for _, id in ipairs(maps) do
                                                id = tonumber(id)
                                                if id then ids[#ids + 1] = id end
                                            end
                                        end
                                    end

                                    if #ids == 0 then
                                        Logger.Error(
                                        "No Mythic+ mapIDs found (C_ChallengeMode/C_MythicPlus APIs unavailable).")
                                        return
                                    end

                                    table.sort(ids)

                                    local seasonLabel = "<unknown>"
                                    local C_MythicPlus = _G.C_MythicPlus
                                    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
                                        local okS, seasonID = pcall(C_MythicPlus.GetCurrentSeason)
                                        if okS and seasonID ~= nil then
                                            seasonLabel = tostring(seasonID)
                                        end
                                    end

                                    print("TwichUI: Current Mythic+ MapIDs (season=" .. seasonLabel .. ")")
                                    local mp = GetModule()
                                    local data = mp and mp.Data
                                    local C_ChallengeMode = _G.C_ChallengeMode
                                    for _, id in ipairs(ids) do
                                        local name = nil
                                        if data and type(data.GetMapUIInfoCached) == "function" then
                                            local okI, n = pcall(data.GetMapUIInfoCached, id, true)
                                            if okI then name = n end
                                        end
                                        if not name and C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
                                            local okUI, n = pcall(C_ChallengeMode.GetMapUIInfo, id)
                                            if okUI then name = n end
                                        end
                                        if not name and C_ChallengeMode and type(C_ChallengeMode.GetMapInfo) == "function" then
                                            local okInfo, a, b = pcall(C_ChallengeMode.GetMapInfo, id)
                                            if okInfo then
                                                -- Some clients return a table; others return multiple values with name first.
                                                if type(a) == "table" then
                                                    name = a.name
                                                else
                                                    name = a
                                                end
                                            end
                                        end
                                        name = tostring(name or "Unknown")
                                        print(string.format("[%d] = %q,", id, name))
                                    end
                                end,
                            },
                        },
                    },

                }
            },

            bestInSlotTab = {
                type = "group",
                name = "Best in Slot",
                order = 4,
                args = {
                    description = CM.Widgets:SubmoduleDescription(
                        "Developer tools for Best in Slot data."),

                    cacheGroup = {
                        type = "group",
                        name = "Cache",
                        inline = true,
                        order = 1,
                        args = {
                            clearItemCache = {
                                type = "execute",
                                name = "Clear BiS Item Cache",
                                desc = "Clears the stored item source cache so it will rebuild on demand.",
                                order = 1,
                                func = function()
                                    local mp = GetModule()
                                    if mp and mp.BestInSlot and mp.BestInSlot.ClearItemCache then
                                        mp.BestInSlot:ClearItemCache()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        }
    }
end
