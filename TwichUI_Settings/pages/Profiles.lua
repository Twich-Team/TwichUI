-- TwichUI settings: Profiles (Profiles.lua). Named sets of TwichUI's options: which one this character uses, a new
-- one, a copy, copying settings in, a new name, and, apart from those, deleting and resetting. Every action
-- goes through Profiles.lua, which refuses what changes the options in use during combat when the action
-- runs (after a confirmation too), not only here.
--
-- None of these controls has a default, so a page's "Reset this page" never switches, copies or resets a
-- profile. The dropdowns for copying and deleting only pick what to ask about; nothing happens until the
-- confirmation is accepted.

local R = TwichUI
local K = R.SettingsKit

local function PF() return R.Profiles end

local function Quote(name) return "\"" .. tostring(name) .. "\"" end

local function Characters(n) return n == 1 and "1 other character" or (n .. " other characters") end

-- A sentence about who else uses a profile, or nil when only this character does.
local function SharedNote(name)
    local others = PF().UsedBy(name, true)
    if #others == 0 then return nil end
    return ("It is also used by %s, so changes to it affect them too."):format(Characters(#others))
end

-- What happened, in chat (only after the player did something here).
local function Report(ok, code, info, name, extra)
    local P = PF()
    if not ok then
        R.Print("%s", P.Explain(code, info))
        return
    end
    local current = P.Current()
    local text
    if code == "switch" then text = ("Now using profile %s."):format(Quote(current))
    elseif code == "create" then text = ("Made profile %s with the default settings, and switched to it."):format(Quote(current))
    elseif code == "duplicate" then text = ("Made profile %s, an independent copy of %s, and switched to it."):format(Quote(current), Quote(name))
    elseif code == "copy" then text = ("Copied the settings of %s into %s."):format(Quote(name), Quote(current))
    elseif code == "reset" then text = ("Profile %s is back to the default settings."):format(Quote(current))
    elseif code == "rename" then text = ("Renamed %s to %s."):format(Quote(name), Quote(extra))
    elseif code == "delete" then text = ("Deleted profile %s."):format(Quote(name))
    else text = "Done." end
    if code == "switch" or code == "copy" or code == "reset" or code == "duplicate" then
        local shared = code ~= "duplicate" and SharedNote(current)
        if shared then text = text .. " " .. shared end
    end
    if info and info.reload then text = text .. " Some of its settings take effect after you reload your UI." end
    if info and info.failed and #info.failed > 0 then
        text = text .. " Some parts couldn't follow the change; reload your UI to finish (details: /tui diagnostics)."
    end
    R.Print("%s", text)
end

-- Refuses at once what can't be done now (rechecked when it runs).
local function Ready(changesOptions)
    local ok, why = PF().Available()
    if not ok then R.Print("%s", PF().Explain(why)) return false end
    if changesOptions and InCombatLockdown() then R.Print("%s", PF().Explain("combat")) return false end
    return true
end

---------------------------------------------------------------------------
-- Dialogs: Blizzard's own, with an edit box for a name or a question to confirm. The profile names go in as
-- plain text (text_arg1 with an empty format), never as a format string.
---------------------------------------------------------------------------
local function Dialogs()
    if StaticPopupDialogs.TWICHUI_PROFILE_NAME then return end
    StaticPopupDialogs.TWICHUI_PROFILE_NAME = {
        text = "", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
        hasEditBox = 1, maxLetters = R.Persist.PROFILE_NAME_MAX,
        OnShow = function(dialog, data)
            local box = dialog.GetEditBox and dialog:GetEditBox()
            if box then
                box:SetText(data and data.initial or "")
                if box.HighlightText then box:HighlightText() end
            end
            if data and data.button and dialog.GetButton1 then dialog:GetButton1():SetText(data.button) end
        end,
        OnAccept = function(dialog, data)
            local box = dialog.GetEditBox and dialog:GetEditBox()
            if box and data then data.accept(box:GetText()) end
        end,
        EditBoxOnEnterPressed = function(box, data)
            if data then data.accept(box:GetText()) end
            box:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }
    StaticPopupDialogs.TWICHUI_PROFILE_CONFIRM = {
        text = "", button1 = OKAY or "Okay", button2 = CANCEL or "Cancel", showAlert = 1,
        OnShow = function(dialog, data)
            if data and data.button and dialog.GetButton1 then dialog:GetButton1():SetText(data.button) end
        end,
        OnAccept = function(_, data) if data then data.accept() end end,
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }
end

local function AskName(prompt, initial, button, accept)
    Dialogs()
    StaticPopup_Show("TWICHUI_PROFILE_NAME", prompt, nil, { initial = initial, button = button, accept = accept })
end

local function Confirm(question, button, accept)
    Dialogs()
    StaticPopup_Show("TWICHUI_PROFILE_CONFIRM", question, nil, { button = button, accept = accept })
end

local NOT_AFFECTED = "Map pins, the Journey Chronicle, backups, stat weights and other addons' own settings are not affected."

K.Page({
    key = "profiles", name = "Profiles", order = 105, group = "config",
    description = "Saved sets of TwichUI's options. Each character uses one; characters using the same profile share it.",
    keywords = "profile character alt copy duplicate rename delete reset new",
    overview = {
        label = "Profiles", tip = "Save sets of TwichUI options, choose one for each character, and share one between characters.",
        status = function()
            local current = R.Profiles and R.Profiles.Current()
            return current and (R.GOLD .. current .. "|r") or (R.GREY .. "Not available|r")
        end,
    },
    build = function()
        local P = PF()
        local Header, Button, Choice = K.Header, K.Button, K.Choice
        local STRING = K.STRING
        local controls = {}   -- settings to show again after a change

        Header("Profiles",
            "A profile is a saved set of TwichUI's options: which features are on, their looks, fonts and places. Each character uses one and remembers which. Characters using the same profile share it; a copy is independent.\n\n"
            .. NOT_AFFECTED .. " The Mage never-sell list and the RestedXP skin's on/off switch are the same for every profile.")

        -- Who uses the profile in use: rewritten after every change (the panel shows it when the page is drawn).
        local function SharedLabel()
            local current = P.Current()
            if not current then
                local _, why = P.Available()
                return P.Explain(why)
            end
            local others = #P.UsedBy(current, true)
            if others == 0 then return "Used only by this character" end
            return ("Shared with %s"):format(Characters(others))
        end
        local function SharedTip()
            local current = P.Current()
            if not current then return nil end
            local others = P.UsedBy(current, true)
            if #others == 0 then
                return "No other character has chosen this profile, so its changes affect this character only. Other characters can choose it from their own options."
            end
            local shown = {}
            for i = 1, math.min(#others, 10) do shown[i] = others[i] end
            local more = #others > 10 and ("\nand %d more"):format(#others - 10) or ""
            return "Changes to this profile also affect other characters using it. Duplicate it for an independent configuration.\n\nAlso used by:\n"
                .. table.concat(shown, "\n") .. more
        end
        local shared = Header(SharedLabel(), SharedTip())
        if shared then shared.GetTooltip = function() return SharedTip() end end

        -- Current profile: choosing one switches to it.
        local current = Choice("profileCurrent", "Current profile",
            "The profile this character uses. Choosing another switches to it at once; this character remembers the choice. Some options (custom fonts, quiet login, addon skins, configuration sharing) take effect after a reload, as they do when changed by hand. Not available during combat.",
            STRING, nil,
            function() return P.Current() or "" end,
            function(name)
                if name == "" or name == P.Current() then return end
                -- after the panel has finished with the click; the switch checks combat when it runs
                C_Timer.After(0, function()
                    if not Ready(true) then
                        if controls.current then controls.current:NotifyUpdate() end
                        return
                    end
                    local ok, code, info = P.Switch(name)
                    Report(ok, code, info, name)
                    if not ok and controls.current then controls.current:NotifyUpdate() end
                end)
            end,
            function()
                local list = {}
                for _, name in ipairs(P.List()) do
                    local users = #P.UsedBy(name)
                    local tip = users == 0 and "No character uses it." or (users == 1 and "Used by 1 character." or ("Used by %d characters."):format(users))
                    list[#list + 1] = { name, name, tip }
                end
                if #list == 0 then list[1] = { "", "Not available", nil } end
                return list
            end)
        controls.current = current and current.GetSetting and current:GetSetting() or (current and current.data and current.data.setting)
        if current then
            local base = current.GetTooltip
            current.GetTooltip = function(self)
                local tip = base and base(self) or ""
                local extra = SharedTip()
                return extra and (tip .. "\n\n" .. extra) or tip
            end
        end

        Header("Make a profile", "New starts from the default settings; Duplicate copies the one you use. Either way this character switches to it, and the profile it leaves is kept as it was.")
        Button("New profile", "New...", function()
            if not Ready(true) then return end
            AskName("Name for the new profile (it starts with the default settings):", "", "Create", function(text)
                Report(P.Create(text))
            end)
        end, "Makes a profile with TwichUI's default settings, and switches this character to it. The profile you are using now is kept as it is.")
        Button("Duplicate current", "Duplicate...", function()
            if not Ready(true) then return end
            local from = P.Current()
            local suggestion = R.Persist.FreeProfileName(from .. " copy", function(n)
                for _, existing in ipairs(P.List()) do if existing:lower() == n:lower() then return true end end
                return false
            end) or ""
            AskName(("Name for an independent copy of %s:"):format(Quote(from)), suggestion, "Duplicate", function(text)
                local ok, code, info = P.Duplicate(text)
                Report(ok, code, info, from)
            end)
        end, "Makes a new, independent copy of the profile you are using and switches this character to it. Changes to the copy never affect the original or the characters using it.")

        -- Copy settings from: the profile in use takes another's settings and keeps its name.
        local copy = Choice("profileCopyFrom", "Copy settings from...",
            "Replaces the settings of the profile you are using with a copy of another profile's. It keeps its name, and the characters using it keep using it. Asks first. Not available during combat.",
            STRING, nil,
            function() return "" end,
            function(source)
                if source == "" then return end
                C_Timer.After(0, function()
                    if controls.copy then controls.copy:NotifyUpdate() end
                    if not Ready(true) then return end
                    local into = P.Current()
                    local note = SharedNote(into)
                    Confirm(("Replace the settings of profile %s with a copy of %s?\n\n%s keeps its name.%s %s"):format(
                        Quote(into), Quote(source), Quote(into), note and (" " .. note) or "", NOT_AFFECTED),
                        "Copy", function()
                            local ok, code, info = P.CopyFrom(source)
                            Report(ok, code, info, source)
                        end)
                end)
            end,
            function()
                local list = { { "", "Choose a profile", nil } }
                local cur = P.Current()
                for _, name in ipairs(P.List()) do
                    if name ~= cur then list[#list + 1] = { name, name, nil } end
                end
                return list
            end)
        controls.copy = copy and copy.GetSetting and copy:GetSetting() or (copy and copy.data and copy.data.setting)

        Button("Rename", "Rename...", function()
            if not Ready(false) then return end
            local old = P.Current()
            AskName(("New name for profile %s:"):format(Quote(old)), old, "Rename", function(text)
                local ok, code, info = P.Rename(old, text)
                Report(ok, code, ok and nil or info, old, ok and info and info.name)
            end)
        end, "Gives the profile you are using a new name. Every character using it keeps using it under the new name.")

        Header("Delete or reset", "These can't be undone.")
        local delete = Choice("profileDelete", "Delete profile...",
            "Removes a profile for good. Only a profile no character uses can be deleted: the one you are using, one another character has chosen and the one new characters start with are kept. Asks first.",
            STRING, nil,
            function() return "" end,
            function(name)
                if name == "" then return end
                C_Timer.After(0, function()
                    if controls.delete then controls.delete:NotifyUpdate() end
                    if not Ready(false) then return end
                    -- refused at once when it is in use, naming who uses it
                    local users = P.UsedBy(name)
                    if name == P.Current() then R.Print("%s", P.Explain("current")) return end
                    if name == P.NewCharacterProfile() then R.Print("%s", P.Explain("new-characters")) return end
                    if #users > 0 then R.Print("%s %s", Quote(name) .. ":", P.Explain("in-use", users)) return end
                    Confirm(("Delete profile %s?\n\nIts settings are removed for good. No character uses it."):format(Quote(name)),
                        "Delete", function()
                            local ok, code, info = P.Delete(name)
                            Report(ok, code, info, name)
                        end)
                end)
            end,
            function()
                local list = { { "", "Choose a profile", nil } }
                local cur, newChars = P.Current(), P.NewCharacterProfile()
                for _, name in ipairs(P.List()) do
                    if name ~= cur then
                        local users = #P.UsedBy(name)
                        local tip
                        if name == newChars then tip = "New characters start with this profile, so it can't be deleted."
                        elseif users > 0 then tip = ("Used by %d character%s, so it can't be deleted."):format(users, users == 1 and "" or "s")
                        else tip = "No character uses it." end
                        list[#list + 1] = { name, name, tip }
                    end
                end
                return list
            end)
        controls.delete = delete and delete.GetSetting and delete:GetSetting() or (delete and delete.data and delete.data.setting)

        Button("Reset current profile", "Reset...", function()
            if not Ready(true) then return end
            local name = P.Current()
            local note = SharedNote(name)
            Confirm(("Reset profile %s to the default settings?\n\nEvery TwichUI option in it goes back to its default.%s %s"):format(
                Quote(name), note and (" " .. note) or "", NOT_AFFECTED),
                "Reset", function()
                    local ok, code, info = P.Reset()
                    Report(ok, code, info, name)
                end)
        end, "Puts every TwichUI option in the profile you are using back to its default. Asks first. Not available during combat.")

        -- After any change to profiles: the labels and choices show what is true now.
        P.OnChange(function()
            if shared and shared.data then shared.data.name = SharedLabel() end
            for _, setting in pairs(controls) do
                if setting and setting.NotifyUpdate then setting:NotifyUpdate() end
            end
            K.RefreshOverview()
        end)
    end,
})
