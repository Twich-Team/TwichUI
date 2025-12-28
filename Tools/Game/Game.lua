local T, W, I, C = unpack(Twich)
---@type ToolsModule
local TM = T:GetModule("Tools")


--- @class GameTool
local GameTool = TM.Game or {}
TM.Game = GameTool

local _G = _G
local SlashCmdList = SlashCmdList

--- Checks if a slash command is registered and available.
--- Returns whether it's available, along with the resolved command name and handler.
--- @param cmd string The full command string as a user would type (e.g. "/reload ui").
--- @return boolean available True if the slash exists.
--- @return string|nil name The `SlashCmdList` name for the command if available.
--- @return function|nil handler The command handler function if available.
function GameTool:IsSlashCommandAvailable(cmd)
    if type(cmd) ~= "string" or cmd == "" then
        return false, nil, nil
    end

    local slash = cmd:match("^(%S+)")
    if not slash or slash:sub(1, 1) ~= "/" then
        return false, nil, nil
    end

    -- Fast path via WoW's `hash_SlashCmdList` map when available
    local hash = _G.hash_SlashCmdList
    if hash then
        local name = hash[slash:lower()]
        if name and SlashCmdList and SlashCmdList[name] then
            return true, name, SlashCmdList[name]
        end
    end

    -- Fallback: iterate known slash registrations
    for name, func in pairs(SlashCmdList) do
        local i = 1
        while true do
            local registered = _G["SLASH_" .. name .. i]
            if not registered then break end
            if registered:lower() == slash:lower() then
                return true, name, func
            end
            i = i + 1
        end
    end

    return false, nil, nil
end

--- Runs a slash command as a player would.
--- @param cmd string The command to run.
function GameTool:RunSlashCommand(cmd)
    local slash, rest = cmd:match("^(%S+)%s*(.-)$")
    if not slash then return end

    for name, func in pairs(SlashCmdList) do
        local i, slashCmd = 1
        repeat
            slashCmd, i = _G["SLASH_" .. name .. i], i + 1
            if slashCmd == slash then
                return true, func(rest)
            end
        until not slashCmd
    end
end

--- Safely runs a slash command only if available.
--- @param cmd string The command to run.
--- @return boolean ran True if the command was executed.
--- @return any result The result from the handler, if any.
function GameTool:RunSlashCommandIfAvailable(cmd)
    local available, name, handler = self:IsSlashCommandAvailable(cmd)
    if not available or not handler then
        return false, nil
    end

    -- Extract the rest of the arguments after the slash token
    local _, rest = cmd:match("^(%S+)%s*(.-)$")
    return true, handler(rest)
end
