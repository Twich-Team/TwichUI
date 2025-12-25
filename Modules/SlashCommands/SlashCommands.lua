--[[
    SlashCommands Module for TwichUI
    Handles slash command registration and processing.
]]
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
            if rest and rest ~= "" then
                subcmd = rest:match("^(%S+)")
            end
            subcmd = subcmd and subcmd:lower() or nil

            if subcmd and cmd.subcommands[subcmd] then
                local sub = cmd.subcommands[subcmd]
                if type(sub.handler) == "function" then
                    sub.handler()
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
