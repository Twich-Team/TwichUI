--[[
    Developer Configuration: Mythic+ Data Recorder

    Provides UI for recording/exporting Mythic+ run data and synchronizing it with other players.
]]
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)
---@diagnostic disable: undefined-field, inject-field

--- @class ConfigurationModule
local CM = T:GetModule("Configuration")

--- @type DeveloperConfigurationModule
CM.Developer = CM.Developer or {}

--- @class DeveloperMythicPlusDataRecorderConfiguration
local DMDR = CM.Developer.MythicPlusDataRecorder or {}
CM.Developer.MythicPlusDataRecorder = DMDR

local function GetSyncModule()
    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
    if not ok or not mythicPlus then return nil end
    return mythicPlus.RunLoggerSync
end

local function GetPeersValues()
    local sync = GetSyncModule()
    if not sync or not sync.GetPeerDisplayValues then
        return {}
    end
    return sync:GetPeerDisplayValues()
end

local function GetPendingValues()
    local sync = GetSyncModule()
    if not sync or not sync.GetPendingRequestDisplayValues then
        return {}
    end
    return sync:GetPendingRequestDisplayValues()
end

function DMDR:Create(order)
    return {
        type = "group",
        name = "Mythic+ Data Recorder",
        order = order,
        args = {
            description = CM.Widgets:SubmoduleDescription(
                "Developer tools for recording Mythic+ run data and synchronizing it between players."),

            runLoggerGroup = {
                type = "group",
                name = "Run Logger",
                inline = true,
                order = 2,
                args = {
                    runLoggerDesc = {
                        type = "description",
                        order = 0,
                        name = "Records Mythic+ run events and metadata into a copy/paste export after completion.",
                    },

                    enableRunLogger = {
                        type = "toggle",
                        name = "Enable Run Logger",
                        desc = "Records Mythic+ run events into a copy/paste log on completion. Persists across /reload.",
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

                    toggleRunLogFrame = {
                        type = "execute",
                        name = "Show Run Log",
                        desc = "Shows/hides the export frame for the most recent run log.",
                        order = 3,
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
                },
            },

            syncGroup = {
                type = "group",
                name = "Synchronizing",
                inline = true,
                order = 5,
                args = {
                    syncDesc = {
                        type = "description",
                        order = 0,
                        name =
                        "Manage which players can send you run logs, and who you will send your run logs to. Cross-realm is supported by using Name-Realm.",
                    },

                    targetInput = {
                        type = "input",
                        name = "Target Player",
                        desc = "Example: PlayerName-Realm (recommended). If you omit realm, your realm will be assumed.",
                        order = 1,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.target", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.target", value)
                        end,
                    },

                    addRecipient = {
                        type = "execute",
                        name = "Add Receiver (I send to them)",
                        desc =
                        "Send a request to the target. They must acknowledge it before you will send them run logs.",
                        order = 2,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.RequestAddRecipient then return end
                            local target = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.target", "")
                            sync:RequestAddRecipient(target)
                        end,
                    },

                    registerWithSender = {
                        type = "execute",
                        name = "Register With Sender (they send to me)",
                        desc =
                        "Ask the target to add you as a receiver. They must acknowledge it before they will send you run logs.",
                        order = 3,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.RequestRegisterWithSender then return end
                            local target = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.target", "")
                            sync:RequestRegisterWithSender(target)
                        end,
                    },

                    syncNow = {
                        type = "execute",
                        name = "Sync Now",
                        desc = "Attempt to sync any pending run logs to all receivers on your list.",
                        order = 4,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.SyncAll then return end
                            sync:SyncAll()
                        end,
                    },

                    ignoreRegistrations = {
                        type = "toggle",
                        name = "Ignore Incoming Registrations",
                        desc =
                        "If enabled, incoming add/register requests will be ignored (no acknowledgement will be sent).",
                        order = 5,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.ignoreRegistrations",
                                false)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.ignoreRegistrations", value)
                        end,
                    },

                    hideNotFound = {
                        type = "toggle",
                        name = "Hide 'Player Not Found' Messages",
                        desc =
                        "Suppress system chat spam when the addon attempts background sync whispers to an offline/non-existent player.",
                        order = 6,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.hidePlayerNotFound", true)
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.hidePlayerNotFound", value)
                        end,
                    },

                    peersHeader = {
                        type = "header",
                        name = "Peers",
                        order = 10,
                    },

                    peerSelect = {
                        type = "select",
                        name = "Synchronized Players",
                        desc = "Players you can send run logs to and/or accept run logs from.",
                        order = 11,
                        width = "full",
                        values = function()
                            return GetPeersValues()
                        end,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer", value)
                        end,
                    },

                    deletePeer = {
                        type = "execute",
                        name = "Delete Selected",
                        desc = "Remove the selected player from your sync list.",
                        order = 12,
                        disabled = function()
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer", "")
                            return (not v) or v == ""
                        end,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.RemovePeer then return end
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer", "")
                            sync:RemovePeer(v)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer", "")
                        end,
                    },

                    pendingHeader = {
                        type = "header",
                        name = "Pending Requests",
                        order = 20,
                    },

                    pendingSelect = {
                        type = "select",
                        name = "Incoming Requests",
                        desc = "Requests that require your acknowledgement.",
                        order = 21,
                        width = "full",
                        values = function()
                            return GetPendingValues()
                        end,
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", value)
                        end,
                    },

                    acceptRequest = {
                        type = "execute",
                        name = "Accept",
                        order = 22,
                        disabled = function()
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                            return (not v) or v == ""
                        end,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.AcceptRequest then return end
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                            sync:AcceptRequest(v)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                        end,
                    },

                    denyRequest = {
                        type = "execute",
                        name = "Deny",
                        order = 23,
                        disabled = function()
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                            return (not v) or v == ""
                        end,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.DenyRequest then return end
                            local v = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                            sync:DenyRequest(v)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedRequest", "")
                        end,
                    },

                    checkHeader = {
                        type = "header",
                        name = "Check",
                        order = 30,
                    },

                    checkAll = {
                        type = "execute",
                        name = "Check All Peers (are they still sending?)",
                        desc = "Query every player on your sync list to see if they still have you on their send list.",
                        order = 31,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.CheckAllPeers then return end
                            sync:CheckAllPeers()
                        end,
                    },

                    checkSpecificTarget = {
                        type = "input",
                        name = "Check Specific Player",
                        desc =
                        "Example: PlayerName-Realm. If you are on their send list but they are not enabled on yours, you can allow them below.",
                        order = 32,
                        width = "full",
                        get = function()
                            return CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget", "")
                        end,
                        set = function(_, value)
                            CM:SetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget", value)
                        end,
                    },

                    checkSpecific = {
                        type = "execute",
                        name = "Check Specific",
                        desc = "Ask a specific player whether they currently have you on their send list.",
                        order = 33,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.CheckIfOnList then return end
                            local target = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget", "")
                            sync:CheckIfOnList(target)
                        end,
                    },

                    allowIncomingFromSelected = {
                        type = "execute",
                        name = "Allow Incoming From Selected Peer",
                        desc =
                        "If the selected peer is sending to you but you are not accepting yet, enable accepting from them.",
                        order = 34,
                        disabled = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.GetCheckResult or not sync.AllowIncomingFrom or not sync.IsAllowIncoming then
                                return true
                            end

                            local selected = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer",
                                "")
                            if not selected or selected == "" then
                                return true
                            end

                            local status, isOnTheirList = sync:GetCheckResult(selected)
                            if status ~= "SUCCESS" or not isOnTheirList then
                                return true
                            end

                            -- Only enable if we are not already accepting from them.
                            return sync:IsAllowIncoming(selected)
                        end,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.AllowIncomingFrom then return end
                            local selected = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer",
                                "")
                            sync:AllowIncomingFrom(selected)
                        end,
                    },

                    allowIncomingFromSpecific = {
                        type = "execute",
                        name = "Allow Incoming From Specific Player",
                        desc =
                        "If the specific player is sending to you but you are not accepting yet, enable accepting from them.",
                        order = 34.5,
                        disabled = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.GetCheckResult or not sync.AllowIncomingFrom or not sync.IsAllowIncoming then
                                return true
                            end

                            local target = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget", "")
                            if not target or target == "" then
                                return true
                            end

                            local status, isOnTheirList = sync:GetCheckResult(target)
                            if status ~= "SUCCESS" or not isOnTheirList then
                                return true
                            end

                            return sync:IsAllowIncoming(target)
                        end,
                        func = function()
                            local sync = GetSyncModule()
                            if not sync or not sync.AllowIncomingFrom then return end
                            local target = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget", "")
                            sync:AllowIncomingFrom(target)
                        end,
                    },

                    checkStatus = {
                        type = "description",
                        order = 35,
                        name = function()
                            local sync = GetSyncModule()
                            if not sync then return "" end

                            local selected = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.selectedPeer",
                                "")
                            if selected and selected ~= "" and sync.GetCheckResult then
                                local status, isOnTheirList = sync:GetCheckResult(selected)
                                if status == "PENDING" then
                                    return "|cffffcc00Selected peer: waiting for response...|r"
                                end
                                if status == "FAILED" then
                                    return "|cffff0000Selected peer: no response (timeout or offline).|r"
                                end
                                if status == "SUCCESS" then
                                    if isOnTheirList then
                                        return "|cff00ff00Selected peer reports: they ARE sending to you.|r"
                                    end
                                    return "|cffff0000Selected peer reports: they are NOT sending to you.|r"
                                end
                            end

                            local specific = CM:GetProfileSettingSafe("developer.mythicplus.runLoggerSync.checkTarget",
                                "")
                            if specific and specific ~= "" and sync.GetCheckResult then
                                local status, isOnTheirList = sync:GetCheckResult(specific)
                                if status == "PENDING" then
                                    return "|cffffcc00Specific: waiting for response...|r"
                                end
                                if status == "FAILED" then
                                    return "|cffff0000Specific: no response (timeout or offline).|r"
                                end
                                if status == "SUCCESS" then
                                    if isOnTheirList then
                                        return "|cff00ff00Specific reports: they ARE sending to you.|r"
                                    end
                                    return "|cffff0000Specific reports: they are NOT sending to you.|r"
                                end
                            end

                            if sync.checkStatus == "PENDING" then
                                return "|cffffcc00Waiting for response...|r"
                            end

                            if sync.checkStatus == "FAILED" then
                                return "|cffff0000No response (timeout or offline).|r"
                            end

                            if sync.checkStatus == "SUCCESS" then
                                if sync.checkResult then
                                    return "|cff00ff00Target reports: you ARE on their list.|r"
                                end
                                return "|cffff0000Target reports: you are NOT on their list.|r"
                            end

                            return ""
                        end,
                    },
                },
            },
        },
    }
end
