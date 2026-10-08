-- TwichUI: shared interaction helpers
-- Small pieces the windows and options share so their controls behave the same way:
--   Tip / RefreshTip / HideTip   a tooltip that names its owner, may explain why the control is unavailable
--                                (even while disabled), and goes away when the control is hidden or left
--   Confirm                      a confirmation that names what changes, can be accepted once, and checks the
--                                target is still there (and that you are out of combat) before acting
-- Nothing here runs by itself; it only adds the behavior to the frames and popups it is given.

local R = TwichUI
local I = {}
R.Interact = I

I.TIP_ANCHOR = "ANCHOR_TOP"
local WARN = { 0.9, 0.45, 0.38 }   -- the reason a control is unavailable

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local function OwnerIs(frame)
    return GameTooltip ~= nil and GameTooltip.GetOwner ~= nil and GameTooltip:GetOwner() == frame
end

-- Hides the game tooltip only if this frame is the one showing it (never somebody else's).
function I.HideTip(frame)
    if OwnerIs(frame) then GameTooltip:Hide() end
end

local function Show(frame)
    local tip = frame.twichuiTip
    if not (tip and GameTooltip) then return end
    local body, why = tip.body, nil
    if type(body) == "function" then body, why = body(frame) end
    if (body == nil or body == "") and not why then return end
    GameTooltip:SetOwner(frame, tip.anchor or I.TIP_ANCHOR)
    if tip.title then GameTooltip:SetText(tip.title, 1, 1, 1) end
    if body and body ~= "" then GameTooltip:AddLine(body, nil, nil, nil, true) end
    if why and why ~= "" then GameTooltip:AddLine(why, WARN[1], WARN[2], WARN[3], true) end
    GameTooltip:Show()
end

-- title: bold first line (may be nil). body: a string, or a function(frame) returning the text and,
-- optionally, a second line saying why the control can't be used right now. It is read each time the
-- tooltip is shown, so it never holds on to an old state.
-- Disabled buttons still answer the mouse, so the reason can be read where the click would have been.
function I.Tip(frame, title, body, anchor)
    frame.twichuiTip = { title = title, body = body, anchor = anchor }
    if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
    frame:SetScript("OnEnter", Show)
    frame:SetScript("OnLeave", I.HideTip)
    if not frame.twichuiTipHooked then
        frame.twichuiTipHooked = true
        frame:HookScript("OnHide", I.HideTip)
    end
end

-- For a row whose label is cut short with "...": hovering the row shows the whole text, and only when the label really is cut.
-- text: a string, or a function(frame) returning one (read when the tooltip opens, so it is never out of date).
function I.TipTruncated(frame, label, text)
    frame:EnableMouse(true)
    I.Tip(frame, nil, function(f)
        if label.IsTruncated and label:IsTruncated() then
            return type(text) == "function" and text(f) or text
        end
    end)
end

-- Call after a change that alters what a control's tooltip says (it became enabled, its setting
-- changed): redraws it only if it is the one being shown, and drops it if there is now nothing to say.
function I.RefreshTip(frame)
    if not OwnerIs(frame) then return end
    GameTooltip:Hide()
    if frame:IsShown() and frame:IsMouseOver() then Show(frame) end
end

---------------------------------------------------------------------------
-- Confirmation
---------------------------------------------------------------------------
-- key:      the popup's name (one per kind of question)
-- text:     what will change, which data it touches and whether it can be undone. Shown as it is:
--           a % in it is safe.
-- onAccept: runs once, only after the player confirms.
-- opts.valid:    function() -> true, or false and a sentence. Checked at the moment of accepting, since
--                the target may be gone or changed while the question was open. Nothing runs if it fails.
-- opts.combat:   true: also refuses in combat (the action reloads the UI or changes settings).
-- opts.accept / opts.cancel: button labels. opts.onCancel: runs if the player declines.
-- Returns the popup, or nil if the game didn't show one.
function I.Confirm(key, text, onAccept, opts)
    opts = opts or {}
    local armed = true
    StaticPopupDialogs[key] = {
        text = "%s",
        button1 = opts.accept or ACCEPT, button2 = opts.cancel or CANCEL,
        OnAccept = function()
            if not armed then return end
            armed = false
            if opts.combat and InCombatLockdown() then
                R.Print("that has to wait until you're out of combat. Nothing was changed.")
                return
            end
            if opts.valid then
                local ok, why = opts.valid()
                if not ok then
                    R.Print("%s", why or "That is no longer there, so nothing was changed.")
                    return
                end
            end
            onAccept()
        end,
        OnCancel = function(_, _, reason)
            if reason == "override" then return end   -- replaced by a newer question
            armed = false
            if opts.onCancel then opts.onCancel() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    return StaticPopup_Show(key, text)
end
