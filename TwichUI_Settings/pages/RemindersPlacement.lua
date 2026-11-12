-- Explicit placement owns a temporary renderer transaction and a small toolbar, never live enable state.
local R = TwichUI
local P = {}
R.RemindersPlacement = P
local active, bar, restore

function P.Active() return active ~= nil end
function P.Parts() return bar end

local function Closed()
    local bringBack = restore
    active, restore = nil, nil
    if bar then bar:Hide() end
    if R.SettingsUI.SuspendForPlacement then R.SettingsUI.SuspendForPlacement(false, bringBack) end
    if R.RemindersPage then R.RemindersPage.QueueRefresh() end
end

function P.Cancel(reopen)
    if not active then return end
    restore = reopen ~= false
    R.ReminderDisplay.PlacementFinish(false)
end

function P.Start(view)
    if active or InCombatLockdown() then return false end
    if (R.RemindersDesigner and R.RemindersDesigner.Shown()) or (R.RemindersCatalog and R.RemindersCatalog.Shown()) then return false end
    if not (R.SettingsUI.IsPageActive("reminders") and R.SettingsUI.SuspendForPlacement) then return false end
    local G, M = R.SettingsWidgets, R.SettingsMaterial
    if not bar then
        bar = CreateFrame("Frame", "TwichUIReminderPlacement", UIParent)
        bar:SetSize(500, 78)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -36)
        bar:SetFrameStrata("DIALOG")
        bar:SetClampedToScreen(true)
        bar:EnableMouse(true)
        M.Companion(bar)
        bar.title = M.ReminderFont(G.Text(bar, "body"), 14, true)
        bar.title:SetPoint("TOPLEFT", 16, -12)
        bar.title:SetWidth(468)
        bar.title:SetMaxLines(1)
        M.ContextTip(bar, "Place reminder", function() return bar.title:GetText() end)
        bar.note = M.ReminderFont(G.Text(bar, "small"), 12)
        bar.note:SetPoint("BOTTOMLEFT", 16, 18)
        bar.note:SetWidth(250)
        bar.note:SetText("Drag the reminder. Cancel keeps its old position.")
        bar.cancel = G.Button(bar, "Cancel", 86, "secondary", function() P.Cancel(true) end)
        bar.cancel:SetPoint("BOTTOMRIGHT", -112, 12)
        M.ReminderControl(bar.cancel, "secondary")
        bar.finish = G.Button(bar, "Finish", 86, "secondary", function()
            local ok, why = R.ReminderDisplay.PlacementFinish(true)
            if not ok and active then bar.note:SetText(why or "Could not save this position.") end
        end)
        bar.finish:SetPoint("BOTTOMRIGHT", -16, 12)
        M.ReminderControl(bar.finish, "confirmation")
        bar:SetScript("OnHide", function() if active then P.Cancel(true) end end)
        if UISpecialFrames then table.insert(UISpecialFrames, "TwichUIReminderPlacement") end
    end
    active, restore = view.id, true
    local ok = R.ReminderDisplay.PlacementStart(view, Closed)
    if not ok then active, restore = nil, nil; return false end
    R.RemindersPreview.Hide()
    R.RemindersEditor.ClearReveal()
    R.SettingsUI.SuspendForPlacement(true)
    bar.title:SetText("Place reminder · " .. view.name)
    bar.note:SetText("Drag the reminder. Cancel keeps its old position.")
    bar:Show()
    return true
end
