-- TwichUI: Quality of Life, Hide error messages and error speech
-- Two separate, opt-in switches:
--   qolHideErrors       the red error text in the middle of the screen ("Not enough rage", "Out of range",
--                       "Spell is not ready yet") is not shown, and neither is the voice or the sound that goes
--                       with it. qolHideErrorsKeep (on by default) still lets a few that you would otherwise miss
--                       through: a full bag, a full quest log, being dead, a raid-only action.
--   qolHideErrorSpeech  the spoken part of an error ("I can't do that yet") is silenced; the text stays.
--
-- What the game gives us (WoW: Forever UI source, Blizzard_UIErrorsFrame):
--   UIErrorsFrame listens for UI_ERROR_MESSAGE (payload: messageType, message) and, in
--   UIErrorsMixin:TryDisplayMessage, adds the red line AND plays the error's voice (C_Sound.PlayVocalErrorSound) or
--   sound. So taking that one event away from the frame hides all three, and nothing else: UI_INFO_MESSAGE (the
--   yellow "Quest accepted" lines) and SYSMSG are separate events, and a message an addon adds with
--   UIErrorsFrame:AddMessage (TwichUI's own notices) never passes through it. Leatrix Plus does the same job by
--   swapping the frame's OnEvent script; unregistering the event instead leaves Blizzard's script untouched.
--   The voice is a game setting, CVar Sound_EnableErrorSpeech (Settings > Audio > Enable Error Speech).
--
-- Speech: turning the switch on sets that CVar to 0 and remembers the value it replaced in
-- TwichUIDB.ui.qol.errorSpeechWas (only when it was on); turning the switch off puts it back, but only if the CVar is
-- still the 0 we set (if you changed it yourself in the meantime, your choice stands). A CVar that was already off is
-- left as it was and is not turned on again.
--
-- Not covered: the ping system's error line, other addons' own messages, errors printed to chat.
-- Untrusted text: a secret or non-string message is never compared and counts as not important.

local R = TwichUI
local E = {}
R.QoLErrors = E

local EVENT = "UI_ERROR_MESSAGE"
local CVAR = "Sound_EnableErrorSpeech"

-- Global strings of the messages worth keeping. Looked up when needed: a name this client lacks is skipped.
E.IMPORTANT = { "ERR_INV_FULL", "ERR_QUEST_LOG_FULL", "ERR_PLAYER_DEAD", "ERR_RAID_GROUP_ONLY" }

local frameTaken = false     -- we took UI_ERROR_MESSAGE away from UIErrorsFrame and it is still gone
local listening = false      -- our own handler (for the important ones) is registered

function E.IsImportant(message)
    if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return false end
    for _, name in ipairs(E.IMPORTANT) do
        local text = _G[name]
        if type(text) == "string" and text == message then return true end
    end
    return false
end

-- Shows one message as the game would have (text, voice or sound, throttling).
local function Show(messageType, message)
    local frame = _G.UIErrorsFrame
    if not frame then return end
    local r, g, b = 1, 0.1, 0.1
    if _G.RED_FONT_COLOR and RED_FONT_COLOR.GetRGB then r, g, b = RED_FONT_COLOR:GetRGB() end
    if frame.TryDisplayMessage then
        frame:TryDisplayMessage(messageType, message, r, g, b)
    elseif frame.AddMessage then
        frame:AddMessage(message, r, g, b, 1.0)
    end
end

local function OnError(messageType, message)
    if E.IsImportant(message) then Show(messageType, message) end
end

---------------------------------------------------------------------------
-- Speech: the game's CVar, put back when the switch goes off
---------------------------------------------------------------------------
local function SavedQol()
    if not TwichUIDB then return nil end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    TwichUIDB.ui.qol = type(TwichUIDB.ui.qol) == "table" and TwichUIDB.ui.qol or {}
    return TwichUIDB.ui.qol
end

local function ApplySpeech()
    if not (GetCVar and SetCVar) then return end
    local current = GetCVar(CVAR)
    local saved = SavedQol()
    if current == nil or not saved then return end      -- this client has no such setting
    if R:Enabled("qolHideErrorSpeech") then
        if current ~= "0" then
            saved.errorSpeechWas = current
            SetCVar(CVAR, "0")
        end
    else
        local was = saved.errorSpeechWas
        if was ~= nil then
            if current == "0" and type(was) == "string" and was ~= "0" and #was <= 8 then SetCVar(CVAR, was) end
            saved.errorSpeechWas = nil
        end
    end
end

---------------------------------------------------------------------------
-- Messages: the frame stops listening; ours keeps the important few
---------------------------------------------------------------------------
local function ApplyMessages()
    local hide = R:Enabled("qolHideErrors")
    local frame = _G.UIErrorsFrame
    if frame and frame.UnregisterEvent and frame.RegisterEvent then
        if hide and not frameTaken then
            frame:UnregisterEvent(EVENT)
            frameTaken = true
        elseif not hide and frameTaken then
            frame:RegisterEvent(EVENT)
            frameTaken = false
        end
    end
    local want = hide and frameTaken and R:Enabled("qolHideErrorsKeep")
    if want and not listening then
        R:On(EVENT, OnError)
        listening = true
    elseif not want and listening then
        R:Off(EVENT, OnError)
        listening = false
    end
end

-- Safe to call any time, as often as you like.
function E.Refresh()
    ApplyMessages()
    ApplySpeech()
end

E.OnError = OnError
R:OnInit(E.Refresh)
