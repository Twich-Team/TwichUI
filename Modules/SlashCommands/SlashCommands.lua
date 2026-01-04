--[[
    SlashCommands Module for TwichUI
    Handles slash command registration and processing.
]]
---@diagnostic disable: need-check-nil
---@diagnostic disable-next-line: undefined-global
local T, W, I, C = unpack(Twich)

---@class SlashCommandsModule: AceConsole-3.0
local SC         = T:GetModule("SlashCommands")

---@type ToolsModule
local Tools      = T:GetModule("Tools")
local TT         = Tools.Text
local CT         = Tools.Colors

--- Prefixes the text with the colorized addon name
--- @param text string The text to prefix
--- @return string prefixedText prefixed text
local function PrefixWithAddonName(text)
    return TT.Color(CT.TWICH.PRIMARY_ACCENT, T.addonMetadata.addonName .. ": ") .. text
end

SC.COMMANDS = {
    config = {
        description = "Open configuration",
        handler = function()
            T:ToggleOptionsUI()
        end,
    },
    help = {
        description = "Display help information and available commands",
        handler = function()
            SC:DisplayHelp()
        end,
    },
    gph = {
        description = "Gold-per-hour controls",
        subcommands = {
            reset = {
                description = "Reset tracker data",
                handler = function()
                    local LM = T:GetModule("LootMonitor")
                    local GPH = LM and LM.GoldPerHourTracker
                    if GPH then
                        GPH:Reset()
                    else
                    end
                end,
            },
            show  = {
                description = "Show GPH frame",
                handler = function()
                    local LM = T:GetModule("LootMonitor")
                    local Frame = LM and LM.GoldPerHourFrame
                    if Frame then
                        Frame:Enable()
                    else
                    end
                end,
            },
        },
    },
    mythicplus = {
        description = "Open the Mythic+ window",
        handler = function()
            ---@type MythicPlusModule
            local module = T:GetModule("MythicPlus")
            module.MainWindow:Enable(true)
        end,
    },
    developer = {
        description = "Developer commands",
        subcommands = {
            runLink = {
                description =
                "Send a sync request to another player (Usage: /twich developer runLink <PlayerName-Realm>)",
                handler = function(args)
                    local target = args and args:match("%S+")
                    if not target then
                        TT.PrintToChatFrame(PrefixWithAddonName(
                            TT.Color(CT.TWICH.TEXT_ERROR, "Usage: /twich developer runLink <PlayerName>")
                        ))
                        return
                    end

                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                    if not ok or not mythicPlus then return end

                    local sync = mythicPlus.RunLoggerSync
                    if sync and type(sync.Initialize) == "function" then
                        sync:Initialize()
                    end

                    if sync and type(sync.RequestAddRecipient) == "function" then
                        sync:RequestAddRecipient(target)
                        TT.PrintToChatFrame(PrefixWithAddonName(
                            "Sync request sent to " .. TT.Color(CT.TWICH.PRIMARY_ACCENT, target)
                        ))
                        return
                    end

                    TT.PrintToChatFrame(PrefixWithAddonName(
                        TT.Color(CT.TWICH.TEXT_ERROR, "Run Logger Sync module not available.")
                    ))
                end
            },
            testRunSharing = {
                description = "Queue/send a dummy run to all configured receivers (for testing)",
                handler = function()
                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                    if not ok or not mythicPlus then return end

                    local sync = mythicPlus.RunLoggerSync
                    if sync and type(sync.Initialize) == "function" then
                        sync:Initialize()
                    end

                    if sync and type(sync.OnRunFinalized) == "function" then
                        local dummyRun = {
                            id = "TEST-RUN-" .. time(),
                            status = "completed",
                            mapId = 376, -- The Necrotic Wake
                            level = 10,
                            affixes = { 9, 10 },
                            events = {
                                { name = "TEST_EVENT", unix = time(), payload = { message = "Hello World" } }
                            }
                        }
                        sync:OnRunFinalized(dummyRun)
                        TT.PrintToChatFrame(PrefixWithAddonName("Queued dummy run data for sync."))
                    else
                        TT.PrintToChatFrame(PrefixWithAddonName(
                            TT.Color(CT.TWICH.TEXT_ERROR, "Run Logger Sync module not available.")
                        ))
                    end
                end
            },
            runs = {
                description = "Open the Received Runs frame",
                handler = function()
                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                    if not ok or not mythicPlus then return end

                    local frame = mythicPlus.RunSharingFrame
                    if frame and type(frame.Toggle) == "function" then
                        frame:Toggle()
                    end
                end
            },
            runlog = {
                description = "Show the Mythic+ Run Logger export frame",
                handler = function()
                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                    if not ok or not mythicPlus then
                        TT.PrintToChatFrame(PrefixWithAddonName(
                            TT.Color(CT.TWICH.TEXT_ERROR, "MythicPlus module is not available")
                        ))
                        return
                    end

                    local rl = mythicPlus.RunLogger
                    if rl and type(rl.ShowLastRunLog) == "function" then
                        rl:ShowLastRunLog()
                        return
                    end

                    TT.PrintToChatFrame(PrefixWithAddonName(
                        TT.Color(CT.TWICH.TEXT_ERROR, "Run Logger is not available")
                    ))
                end,
            },
            simulate = {
                description = "Open the Mythic+ Simulator (paste run-log JSON to replay)",
                handler = function()
                    local ok, mythicPlus = pcall(function() return T:GetModule("MythicPlus") end)
                    if not ok or not mythicPlus then
                        TT.PrintToChatFrame(PrefixWithAddonName(
                            TT.Color(CT.TWICH.TEXT_ERROR, "MythicPlus module is not available")
                        ))
                        return
                    end

                    local sim = mythicPlus.Simulator
                    if sim and type(sim.ToggleFrame) == "function" then
                        if type(sim.Initialize) == "function" then
                            sim:Initialize()
                        end
                        sim:ToggleFrame()
                        return
                    end

                    TT.PrintToChatFrame(PrefixWithAddonName(
                        TT.Color(CT.TWICH.TEXT_ERROR, "Simulator is not available")
                    ))
                end,
            },
        },
    },
}

--- Prints all available commnands to the chat frame
local function DisplayAvailableCommands()
    local slashTxt = TT.Color(CT.TWICH.TEXT_PRIMARY, "/twich")
    for cmd, info in pairs(SC.COMMANDS) do
        local cmdTxt = TT.Color(CT.TWICH.SECONDARY_ACCENT, cmd)

        -- If the command has subcommands, list each individually
        if info.subcommands then
            for sub, sinfo in pairs(info.subcommands) do
                local subTxt = TT.Color(CT.TWICH.SECONDARY_ACCENT, sub)
                local descTxt = TT.Color(CT.TWICH.TEXT_SECONDARY, sinfo.description or "")
                TT.PrintToChatFrame("  " .. slashTxt .. " " .. cmdTxt .. " " .. subTxt .. " - " .. descTxt)
            end
        else
            local infoTxt = TT.Color(CT.TWICH.TEXT_SECONDARY, info.description)
            TT.PrintToChatFrame("  " .. slashTxt .. " " .. cmdTxt .. " - " .. infoTxt)
        end
    end
end

--- Prints addon help to the chat frame
function SC:DisplayHelp()
    local msg = TT.Color(CT.TWICH.TEXT_PRIMARY, "Available commands:")
    TT.PrintToChatFrame(PrefixWithAddonName(msg))

    DisplayAvailableCommands()
end

--- Primary handler for the /twich slash command. This is invoked by AceConsole when the user types /twich in chat.
--- @param input string The input string following the slash command.
function SC:PrimarySlashHandler(input)
    input = input or ""

    -- Extract first word (command) and the rest
    local command = input:match("^(%S+)")
    command = command and command:lower() or nil

    local rest = ""
    if command and #input > #command then
        rest = input:sub(#command + 1):match("^%s*(.*)") or ""
    end

    if command and SC.COMMANDS[command] then
        local cmd = SC.COMMANDS[command]

        -- If the command has subcommands, parse the subcommand
        if cmd.subcommands then
            local subcmd = nil
            local subcmdToken = nil
            if rest and rest ~= "" then
                subcmdToken = rest:match("^(%S+)")
            end
            subcmd = subcmdToken and subcmdToken:lower() or nil

            if subcmd then
                -- Case-insensitive lookup
                local foundSub = nil
                for k, v in pairs(cmd.subcommands) do
                    if k:lower() == subcmd then
                        foundSub = v
                        subcmd = k -- Restore original casing for length calc if needed, or just use k
                        break
                    end
                end

                if foundSub and type(foundSub.handler) == "function" then
                    local subRest = ""
                    -- Re-calculate rest based on the matched token length
                    -- We matched subcmdToken from rest:match("^(%S+)"), so its length is what we skip
                    local tokenLen = #subcmdToken
                    if rest and #rest > tokenLen then
                        subRest = rest:sub(tokenLen + 1):match("^%s*(.*)") or ""
                    end
                    foundSub.handler(subRest)
                    return
                end
            end

            -- No valid subcommand found; show help
            local slashTxt = TT.Color(CT.TWICH.TEXT_PRIMARY, "/twich")
            local cmdTxt = TT.Color(CT.TWICH.SECONDARY_ACCENT, command)
            TT.PrintToChatFrame(PrefixWithAddonName(TT.Color(CT.TWICH.TEXT_SECONDARY, command .. " subcommands:")))
            for sub, sinfo in pairs(cmd.subcommands) do
                local subTxt = TT.Color(CT.TWICH.SECONDARY_ACCENT, sub)
                local descTxt = TT.Color(CT.TWICH.TEXT_SECONDARY, sinfo.description or "")
                TT.PrintToChatFrame("  " .. slashTxt .. " " .. cmdTxt .. " " .. subTxt .. " - " .. descTxt)
            end
            return
        end

        -- Regular command (no subcommands)
        if type(cmd.handler) == "function" then
            cmd.handler(rest)
        end
    else
        local msg = TT.Color(CT.TWICH.TEXT_ERROR, "Unknown command. Available commands are:")
        TT.PrintToChatFrame(PrefixWithAddonName(msg))
        DisplayAvailableCommands()
    end
end

--- Called by AceAddon when the SlashCommands module is initialized. Registers the slash command handlers.
function SC:OnInitialize()
    -- Pass method name so AceConsole supplies `self` correctly
    self:RegisterChatCommand("twich", "PrimarySlashHandler")
    self:RegisterChatCommand("twichui", "PrimarySlashHandler")
    -- special quick alias to get to the configuration panel
    self:RegisterChatCommand("tc", function()
        T:ToggleOptionsUI()
    end)
end
