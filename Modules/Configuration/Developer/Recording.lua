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
                    toggleRunLogFrame = {
                        type = "execute",
                        name = "Show Run Log",
                        desc = "Shows/hides the export frame for the most recent run log.",
                        order = 2.5,
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
                    enableRunLogger = {
                        type = "toggle",
                        name = "Enable Run Logger",
                        desc = "Records Mythic+ run events into a copy/paste log on completion. Persists across /reload.",
                        order = 2,
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
                        order = 2.1,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLogger.autoShow", true)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLogger.autoShow", value)
                        end,
                    },
                    runSharingSpacer = CM.Widgets:Spacer(3),
                    runSharingHeader = {
                        type = "header",
                        name = "Run Sharing",
                        order = 3.1,
                    },
                    runSharingDesc = CM.Widgets:ComponentDescription(3.2,
                        "Automatically send completed run logs to another player (e.g. for simulation). Both players must have the addon installed."),
                    ignoreIncomingRuns = {
                        type = "toggle",
                        name = "Ignore Incoming Runs",
                        desc = "If enabled, incoming Mythic+ run data from other players will be ignored.",
                        order = 3.25,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runSharing.ignoreIncoming", false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runSharing.ignoreIncoming", value)
                        end,
                    },
                    linkedReceiver = {
                        type = "input",
                        name = "Linked Receiver",
                        desc = "The name of the player to send run data to (e.g. 'PlayerName' or 'PlayerName-Realm').",
                        order = 3.3,
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
                        order = 3.35,
                        width = "half",
                        disabled = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus or not mythicPlus.RunSharing then return true end
                            return not mythicPlus.RunSharing.receiver or mythicPlus.RunSharing.receiver == ""
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
                        order = 3.4,
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
                        order = 3.5,
                    },
                    sendLastRun = {
                        type = "execute",
                        name = "Send Last Run",
                        desc = "Manually send the last completed run log to the linked receiver.",
                        order = 3.6,
                        disabled = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus or not mythicPlus.RunSharing or not mythicPlus.RunLogger then return true end
                            return not mythicPlus.RunSharing.receiver or not mythicPlus.RunLogger.GetLastRun or
                            not mythicPlus.RunLogger:GetLastRun()
                        end,
                        func = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus or not mythicPlus.RunSharing or not mythicPlus.RunLogger then return end

                            local lastRun = mythicPlus.RunLogger:GetLastRun()
                            if lastRun then
                                mythicPlus.RunSharing:SendRun(lastRun)
                                print("|cff9580ffTwichUI:|r Manually sent last run to " .. mythicPlus.RunSharing
                                .receiver)
                            end
                        end,
                    },
                    viewReceivedRuns = {
                        type = "execute",
                        name = "View Received Runs",
                        desc = "Open the frame to view and simulate received run logs.",
                        order = 3.7,
                        func = function()
                            local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                            if not ok or not mythicPlus then return end

                            local frame = mythicPlus.RunSharingFrame
                            if frame and type(frame.Toggle) == "function" then
                                frame:Toggle()
                            end
                        end,
                    },
                },
            },
        }
    }
end
