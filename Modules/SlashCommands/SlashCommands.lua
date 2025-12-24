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

SC.COMMANDS      = {
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
    }
}

--- Prefixes the text with the colorized addon name
--- @param text string The text to prefix
--- @return string prefixedText prefixed text
local function PrefixWithAddonName(text)
    return TT.Color(CT.TWICH.PRIMARY_ACCENT, T.addonMetadata.addonName .. ": ") .. text
end

--- Prints all available commnands to the chat frame
local function DisplayAvailableCommands()
    local slashTxt = TT.Color(CT.TWICH.TEXT_PRIMARY, "/twich")
    for cmd, info in pairs(SC.COMMANDS) do
        local cmdTxt = TT.Color(CT.TWICH.SECONDARY_ACCENT, cmd)
        local infoTxt = TT.Color(CT.TWICH.TEXT_SECONDARY, info.description)
        TT.PrintToChatFrame("  " .. slashTxt .. " " .. cmdTxt .. " - " .. infoTxt)
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

    local command, rest = self:GetArgs(input, 1)
    command = command and command:lower()

    if command and SC.COMMANDS[command] then
        SC.COMMANDS[command].handler(rest)
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
