-- Healer Watch: explicit player-authored self-status messages, never watch-state inference.
-- Hover only opens a menu. A row click rechecks live state, channel and restrictions.
local R = TwichUI
local C = {}
R.HealerCommunication = C
local choices = {
    { "drinking", "Drinking." }, { "oom", "Out of mana." },
    { "moment", "Need a moment." }, { "ready", "Ready." },
}
local messages = { drinking = "Drinking.", oom = "Out of mana.", moment = "Need a moment.", ready = "Ready." }
local generation, lastSent = 0, nil
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function GroupFlag(category, raid)
    local fn = raid and IsInRaid or IsInGroup
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, category)
    if not ok or not Plain(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function Available()
    if not R:Enabled("healerWatch") or not R.HealerDisplay.CommunicationLive() then return nil, "Panel unavailable" end
    if not InCombatLockdown then return nil, "Combat state unavailable" end
    local ok, combat = pcall(InCombatLockdown)
    if not ok or not Plain(combat) or combat ~= false then return nil, "Unavailable in combat" end
    local chat = C_ChatInfo
    if not chat or type(chat.SendChatMessage) ~= "function" or type(chat.InChatMessagingLockdown) ~= "function" then return nil, "Chat unavailable" end
    local safe, locked = pcall(chat.InChatMessagingLockdown)
    if not safe or not Plain(locked) or locked ~= false then return nil, "Chat restricted" end
    if LE_PARTY_CATEGORY_INSTANCE == nil or LE_PARTY_CATEGORY_HOME == nil then return nil, "Group unavailable" end
    local instance = GroupFlag(LE_PARTY_CATEGORY_INSTANCE)
    if instance == nil then return nil, "Group unavailable" end
    if instance then return "INSTANCE_CHAT" end
    local raid = GroupFlag(nil, true)
    if raid == nil then return nil, "Group unavailable" end
    if raid then return "RAID" end
    local home = GroupFlag(LE_PARTY_CATEGORY_HOME)
    if home == nil then return nil, "Group unavailable" end
    if home then return "PARTY" end
    return nil, "No group channel"
end
function C.Close()
    generation = generation + 1
    if R.HealerPicker and R.HealerPicker.Kind() == "communication" then R.HealerPicker.Close() end
end
function C.Open(owner)
    if not R.HealerDisplay.CommunicationLive() or not R.HealerPicker then return false end
    if R.HealerPicker.IsOpen() then return false end
    local channel, why = Available()
    generation = generation + 1
    local token = generation
    if why == "Unavailable in combat" or why == "Combat state unavailable" then
        if GameTooltip then GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:SetText("Your status: unavailable in combat"); GameTooltip:Show() end
        return false
    end
    local title = channel and ("Your status · " .. channel) or ("Your status · " .. (why or "Unavailable"))
    return R.HealerPicker.Open(owner, choices, nil, function(key)
        if token ~= generation or not messages[key] then return end
        generation = generation + 1
        local dist, reason = Available()
        if not dist then R.Print("Healer Watch: %s.", reason or "Chat unavailable"); return end
        if not GetTime then R.Print("Healer Watch: timing unavailable."); return end
        local good, now = pcall(GetTime)
        if not good or not Plain(now) or type(now) ~= "number" or now ~= now or now < 0 or now == math.huge then return end
        if lastSent and now - lastSent < 3 then R.Print("Healer Watch: wait before sending another message."); return end
        lastSent = now
        local sent = pcall(C_ChatInfo.SendChatMessage, messages[key], dist)
        if not sent then R.Print("Healer Watch: the message could not be sent.") end
    end, { kind = "communication", title = title, onClose = function(reason)
        if reason ~= "selected" and token == generation then generation = generation + 1 end
    end })
end
R.HealerDisplay.onCommunication = C.Open
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views", "healer-communication", C.Close) end
if R.Profiles and R.Profiles.OnChange then R.Profiles.OnChange(C.Close) end
