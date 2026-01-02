--[[
        Recording Configuration
        Developer-only settings related to capturing and exporting data.
]]
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")
---@type LoggerModule
local Logger = T:GetModule("Logger")

local LSM = T.Libs and T.Libs.LSM

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperRecordingConfiguration
local DR = CM.Developer.Recording or {}
CM.Developer.Recording = DR

--- Create the recording configuration panels
--- @param order number The order of the panel
function DR:Create(order)
    return {
        type = "group",
        name = "Recording",
        order = order,
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Recording tools capture in-game data for later review and analysis."
            ),
            mythicPlusGroup = {
                type = "group",
                inline = true,
                name = "Mythic+",
                order = 2,
                args = {
                    description = CM.Widgets:ComponentDescription(1,
                        "Record Mythic+ run data (events and metadata) into a copy/paste export."),

                    runLoggerGroup = {
                        type = "group",
                        name = "Run Logger",
                        inline = true,
                        order = 2,
                        args = {
                            enableRunLogger = {
                                type = "toggle",
                                name = "Enable Run Logger",
                                desc =
                                "Records Mythic+ run events into a copy/paste log on completion. Persists across /reload.",
                                order = 1,
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.mythicplus.runLogger.enable", false)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.mythicplus.runLogger.enable", value)
                                    -- Legacy key back-compat (older builds)
                                    CM:SetProfileSettingSafe("mythicPlus.runLogger.enable", value)

                                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                    if ok and mythicPlus and mythicPlus.RunLogger then
                                        if value then
                                            if mythicPlus.RunLogger.Initialize then
                                                mythicPlus.RunLogger:Initialize()
                                            elseif mythicPlus.RunLogger.Enable then
                                                mythicPlus.RunLogger:Enable()
                                            end
                                        else
                                            if mythicPlus.RunLogger.Disable then
                                                mythicPlus.RunLogger:Disable()
                                            end
                                        end
                                    else
                                        Logger.Debug(
                                            "MythicPlus module not available yet; Run Logger toggle will apply on next load.")
                                    end
                                end,
                            },
                            autoShowRunLog = {
                                type = "toggle",
                                name = "Auto-Show Log",
                                desc = "Automatically show the run log export frame when a Mythic+ run is completed.",
                                order = 2,
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.mythicplus.runLogger.autoShow", true)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.mythicplus.runLogger.autoShow", value)
                                end,
                            },
                            historySize = {
                                type = "range",
                                name = "History Size",
                                desc = "Number of runs to keep in history for syncing.",
                                min = 1,
                                max = 20,
                                step = 1,
                                order = 3,
                                get = function()
                                    return CM:GetProfileSettingSafe("developer.mythicplus.runLogger.historySize", 5)
                                end,
                                set = function(_, value)
                                    CM:SetProfileSettingSafe("developer.mythicplus.runLogger.historySize", value)
                                end,
                            },
                            toggleRunLogFrame = {
                                type = "execute",
                                name = "Show Run Log",
                                desc = "Shows/hides the export frame for the most recent run log.",
                                order = 4,
                                disabled = function()
                                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                    if not ok or not mythicPlus or not mythicPlus.RunLogger then
                                        return true
                                    end
                                    if type(mythicPlus.RunLogger.HasRunData) ~= "function" then
                                        return true
                                    end
                                    return not mythicPlus.RunLogger:HasRunData()
                                end,
                                func = function()
                                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                    if not ok or not mythicPlus or not mythicPlus.RunLogger then
                                        return
                                    end
                                    if type(mythicPlus.RunLogger.ToggleRunLogFrame) == "function" then
                                        mythicPlus.RunLogger:ToggleRunLogFrame()
                                    elseif type(mythicPlus.RunLogger.ShowLastRunLog) == "function" then
                                        mythicPlus.RunLogger:ShowLastRunLog()
                                    end
                                end,
                            },
                        }
                    },

                    runSharingGroup = {
                        type = "group",
                        name = "Run Sharing",
                        inline = true,
                        order = 3,
                        args = {
                            description = CM.Widgets:ComponentDescription(0,
                                "Automatically send completed run logs to another player (e.g. for simulation). Both players must have the addon installed."),

                            settingsGroup = {
                                type = "group",
                                name = "Settings",
                                inline = true,
                                order = 1,
                                args = {
                                    description = CM.Widgets:ComponentDescription(0,
                                        "Configure how the addon behaves when receiving run data."),
                                    notificationSound = {
                                        type = "select",
                                        dialogControl = "LSM30_Sound",
                                        name = "Notification Sound",
                                        desc = "Play a sound when new run data is received.",
                                        order = 1,
                                        values = LSM and LSM:HashTable("sound") or {},
                                        get = function()
                                            return CM:GetProfileSettingSafe("developer.mythicplus.runSharing.sound",
                                                "None")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("developer.mythicplus.runSharing.sound", value)
                                        end,
                                    },
                                    ignoreIncomingRuns = {
                                        type = "toggle",
                                        name = "Ignore Incoming Runs",
                                        desc =
                                        "If enabled, incoming Mythic+ run data from other players will be ignored.",
                                        order = 2,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.ignoreIncoming", false)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe("developer.mythicplus.runSharing.ignoreIncoming",
                                                value)
                                        end,
                                    },
                                }
                            },

                            registrationGroup = {
                                type = "group",
                                name = "Registration",
                                inline = true,
                                order = 1.5,
                                args = {
                                    description = CM.Widgets:ComponentDescription(0,
                                        "Register with a target so they will automatically send you future run logs."),
                                    registerWith = {
                                        type = "input",
                                        name = "Target",
                                        desc =
                                        "Character name to register with. Example: 'PlayerName' or 'PlayerName-Realm'.",
                                        order = 0,
                                        width = "full",
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", "")
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", value)
                                        end,
                                    },
                                    registerToReceive = {
                                        type = "execute",
                                        name = "Register",
                                        desc =
                                        "Send a registration request to the target, then ping for a success/fail indicator.",
                                        order = 0.1,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            local target = CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", "")
                                            return (not mythicPlus.RunSharing.RegisterWithTarget and not mythicPlus.RunSharing.RegisterToReceive) or
                                                (not target) or (target == "")
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if ok and mythicPlus and mythicPlus.RunSharing then
                                                local target = CM:GetProfileSettingSafe(
                                                    "developer.mythicplus.runSharing.registerWith", "")
                                                if mythicPlus.RunSharing.RegisterWithTarget then
                                                    mythicPlus.RunSharing:RegisterWithTarget(target)
                                                elseif mythicPlus.RunSharing.RegisterToReceive then
                                                    mythicPlus.RunSharing:RegisterToReceive(target)
                                                end
                                            end
                                        end,
                                    },
                                    registerStatus = {
                                        type = "description",
                                        name = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return "" end

                                            local status = mythicPlus.RunSharing.registerWithStatus
                                            if status == "SUCCESS" then
                                                return "|cff00ff00Target responded (pong received).|r"
                                            elseif status == "FAILED" then
                                                return "|cffff0000No response from target (timeout).|r"
                                            elseif status == "PENDING" then
                                                return "|cffffcc00Waiting for target response...|r"
                                            else
                                                return ""
                                            end
                                        end,
                                        image = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return nil end

                                            local status = mythicPlus.RunSharing.registerWithStatus
                                            if status == "SUCCESS" then
                                                return "Interface\\RaidFrame\\ReadyCheck-Ready", 16, 16
                                            elseif status == "FAILED" then
                                                return "Interface\\RaidFrame\\ReadyCheck-NotReady", 16, 16
                                            elseif status == "PENDING" then
                                                return "Interface\\RaidFrame\\ReadyCheck-Waiting", 16, 16
                                            else
                                                return nil, 0, 0
                                            end
                                        end,
                                        order = 0.2,
                                    },
                                    checkRegistration = {
                                        type = "execute",
                                        name = "Check Registration",
                                        desc = "Ask the target whether they currently have you registered.",
                                        order = 0.3,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            local target = CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", "")
                                            return (not mythicPlus.RunSharing.CheckRegistrationWithTarget) or
                                                (not target) or (target == "")
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return end
                                            local target = CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", "")
                                            if mythicPlus.RunSharing.CheckRegistrationWithTarget then
                                                mythicPlus.RunSharing:CheckRegistrationWithTarget(target)
                                            end
                                        end,
                                    },
                                    checkRegistrationStatus = {
                                        type = "description",
                                        name = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return "" end

                                            local status = mythicPlus.RunSharing.registrationCheckStatus
                                            local result = mythicPlus.RunSharing.registrationCheckResult
                                            if status == "SUCCESS" and result == true then
                                                return "|cff00ff00Target reports: you are registered.|r"
                                            elseif status == "FAILED" and result == false then
                                                return "|cffff0000Target reports: you are NOT registered.|r"
                                            elseif status == "FAILED" and result == nil then
                                                return "|cffff0000No response from target (timeout).|r"
                                            elseif status == "PENDING" then
                                                return "|cffffcc00Waiting for target response...|r"
                                            else
                                                return ""
                                            end
                                        end,
                                        image = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return nil end

                                            local status = mythicPlus.RunSharing.registrationCheckStatus
                                            local result = mythicPlus.RunSharing.registrationCheckResult
                                            if status == "SUCCESS" and result == true then
                                                return "Interface\\RaidFrame\\ReadyCheck-Ready", 16, 16
                                            elseif status == "FAILED" then
                                                return "Interface\\RaidFrame\\ReadyCheck-NotReady", 16, 16
                                            elseif status == "PENDING" then
                                                return "Interface\\RaidFrame\\ReadyCheck-Waiting", 16, 16
                                            else
                                                return nil, 0, 0
                                            end
                                        end,
                                        order = 0.4,
                                    },
                                    unregisterToReceive = {
                                        type = "execute",
                                        name = "Unregister",
                                        desc = "Send an unregister whisper to the configured target.",
                                        order = 0.5,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            local target = CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.registerWith", "")
                                            return (not mythicPlus.RunSharing.UnregisterToReceive) or (not target) or
                                                (target == "")
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if ok and mythicPlus and mythicPlus.RunSharing and mythicPlus.RunSharing.UnregisterToReceive then
                                                local target = CM:GetProfileSettingSafe(
                                                    "developer.mythicplus.runSharing.registerWith", "")
                                                mythicPlus.RunSharing:UnregisterToReceive(target)
                                                print(
                                                    "|cff9580ffTwichUI:|r Unregistered with " .. target .. ".")
                                            end
                                        end,
                                    },
                                    ignoreRegistrations = {
                                        type = "toggle",
                                        name = "Ignore Registrations",
                                        desc =
                                        "If enabled, incoming REGISTER/UNREGISTER messages from other players will be ignored.",
                                        order = 1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.ignoreRegistrations", false)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.ignoreRegistrations", value)
                                        end,
                                    },
                                }
                            },

                            connectionGroup = {
                                type = "group",
                                name = "Connection",
                                inline = true,
                                order = 2,
                                args = {
                                    description = CM.Widgets:ComponentDescription(0,
                                        "Link to another player to automatically send run data."),
                                    linkedReceiver = {
                                        type = "input",
                                        name = "Linked Receiver",
                                        desc =
                                        "The name of the player to send run data to (e.g. 'PlayerName' or 'PlayerName-Realm').",
                                        order = 1,
                                        get = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if ok and mythicPlus and mythicPlus.RunSharing then
                                                return mythicPlus.RunSharing.receiver
                                            end
                                            return ""
                                        end,
                                        set = function(_, value)
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if ok and mythicPlus and mythicPlus.RunSharing then
                                                mythicPlus.RunSharing:SetReceiver(value)
                                            end
                                        end,
                                    },
                                    unlinkReceiver = {
                                        type = "execute",
                                        name = "Unlink",
                                        desc = "Clear the linked receiver.",
                                        order = 2,
                                        width = "half",
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            return not mythicPlus.RunSharing.receiver or
                                                mythicPlus.RunSharing.receiver == ""
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if ok and mythicPlus and mythicPlus.RunSharing then
                                                mythicPlus.RunSharing:SetReceiver(nil)
                                            end
                                        end,
                                    },
                                    testRunSharing = {
                                        type = "execute",
                                        name = "Test Connection",
                                        desc = "Send a ping to the linked receiver to verify the connection.",
                                        order = 3,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            return not mythicPlus.RunSharing.receiver
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return end

                                            local rs = mythicPlus.RunSharing
                                            if rs.SendPing then
                                                rs:SendPing()
                                            end
                                        end,
                                    },
                                    hidePlayerNotFound = {
                                        type = "toggle",
                                        name = "Hide Player-Not-Found Spam",
                                        desc =
                                        "If enabled, hides the system message 'No player named ... is currently playing.' that can appear from the background (silent) connection ping.",
                                        order = 3.1,
                                        get = function()
                                            return CM:GetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.hidePlayerNotFound", true)
                                        end,
                                        set = function(_, value)
                                            CM:SetProfileSettingSafe(
                                                "developer.mythicplus.runSharing.hidePlayerNotFound", value)
                                        end,
                                    },
                                    connectionStatus = {
                                        type = "description",
                                        name = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return "" end

                                            local status = mythicPlus.RunSharing.connectionStatus
                                            if status == "SUCCESS" then
                                                return "|cff00ff00Connection Successful!|r"
                                            elseif status == "FAILED" then
                                                return "|cffff0000Connection Failed (Timeout)|r"
                                            elseif status == "PENDING" then
                                                return "|cffffcc00Testing Connection...|r"
                                            else
                                                return ""
                                            end
                                        end,
                                        image = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return nil end

                                            local status = mythicPlus.RunSharing.connectionStatus
                                            if status == "SUCCESS" then
                                                return "Interface\\RaidFrame\\ReadyCheck-Ready", 16, 16
                                            elseif status == "FAILED" then
                                                return "Interface\\RaidFrame\\ReadyCheck-NotReady", 16, 16
                                            elseif status == "PENDING" then
                                                return "Interface\\RaidFrame\\ReadyCheck-Waiting", 16, 16
                                            else
                                                return nil, 0, 0
                                            end
                                        end,
                                        order = 4,
                                    },
                                }
                            },

                            registeredReceiversGroup = {
                                type = "group",
                                name = "Registered Receivers",
                                inline = true,
                                order = 2.5,
                                args = {
                                    description = CM.Widgets:ComponentDescription(0,
                                        "Players who have registered with you to receive run logs."),
                                    list = {
                                        type = "description",
                                        name = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then
                                                return "None"
                                            end

                                            local rs = mythicPlus.RunSharing
                                            if type(rs.GetRegisteredReceiversList) ~= "function" then
                                                return "None"
                                            end

                                            local names = rs:GetRegisteredReceiversList()
                                            if not names or #names == 0 then
                                                return "None"
                                            end
                                            return table.concat(names, "\n")
                                        end,
                                        order = 1,
                                    },
                                }
                            },

                            actionsGroup = {
                                type = "group",
                                name = "Actions",
                                inline = true,
                                order = 3,
                                args = {
                                    sendLastRun = {
                                        type = "execute",
                                        name = "Send Last Run",
                                        desc = "Manually send the last completed run log to the linked receiver.",
                                        order = 1,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing or not mythicPlus.RunLogger then return true end
                                            return not mythicPlus.RunSharing.receiver or
                                                not mythicPlus.RunLogger.GetLastRun or
                                                not mythicPlus.RunLogger:GetLastRun()
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing or not mythicPlus.RunLogger then return end

                                            local lastRun = mythicPlus.RunLogger:GetLastRun()
                                            if lastRun then
                                                mythicPlus.RunSharing:SendRun(lastRun)
                                                print("|cff9580ffTwichUI:|r Manually sent last run to " ..
                                                    mythicPlus.RunSharing
                                                    .receiver)
                                            end
                                        end,
                                    },
                                    clearRegisteredReceivers = {
                                        type = "execute",
                                        name = "Clear Registered Receivers",
                                        desc = "Remove all registered receivers stored on this character.",
                                        order = 2,
                                        disabled = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                                            local rs = mythicPlus.RunSharing
                                            if type(rs.GetRegisteredReceiversList) ~= "function" then return true end
                                            local names = rs:GetRegisteredReceiversList()
                                            return (not names) or (#names == 0)
                                        end,
                                        func = function()
                                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return end
                                            local rs = mythicPlus.RunSharing
                                            if type(rs.ClearRegisteredReceivers) == "function" then
                                                rs:ClearRegisteredReceivers()
                                                print("|cff9580ffTwichUI:|r Cleared registered receivers.")
                                            end
                                        end,
                                    },
                                }
                            }
                        }
                    },
                },
            },
        }
    }
end
