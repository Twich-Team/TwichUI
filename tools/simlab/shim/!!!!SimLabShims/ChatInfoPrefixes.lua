-- Shim: C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.IsAddonMessagePrefixRegistered.
--
-- Why: wow-ui-sim v0.1.37's Forever profile has C_ChatInfo.SendAddonMessage but not these two. The game has them
-- (Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua, Forever 1.60.1.70532), and bundled AceComm calls
-- the first as it loads, so four of TwichUI's files stop part way without it.
--
-- What it proves: nothing about addon messaging. It keeps a list of names so that loading can go on; no message is
-- ever sent or received, and the game's own limits (the prefix count, the prefix length) are not modelled.
-- Remove it when the simulator has these functions.
local Result = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 }
local registered = {}

assert(C_ChatInfo and not C_ChatInfo.RegisterAddonMessagePrefix,
    "SimLabShims: the simulator has RegisterAddonMessagePrefix now; remove this shim")

function C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if type(prefix) ~= "string" or prefix == "" then return Result.InvalidPrefix end
    if registered[prefix] then return Result.DuplicatePrefix end
    registered[prefix] = true
    return Result.Success
end

function C_ChatInfo.IsAddonMessagePrefixRegistered(prefix)
    return registered[prefix] == true
end
