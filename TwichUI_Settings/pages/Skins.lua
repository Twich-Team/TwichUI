-- TwichUI settings: Addon skins (the EllesmereUI look for supported addons, and a pointer to the RestedXP
-- guide window's own page, pages/RestedXP.lua, in the RestedXP section of the list).

local R = TwichUI
local K = R.SettingsKit

-- Addons TwichUI can skin. addon = folder name.
local SKINS = {
    { key = "attuneSkin", addon = "Attune", label = "Attune",
      what = "Gives the Attune window (/attune) and its quest panels the EllesmereUI look." },
    { key = "auctionatorSkin", addon = "Auctionator", label = "Auctionator",
      what = "Gives Auctionator's tabs, buttons, lists and boxes the EllesmereUI look. Also needs EllesmereUI's Auction House window skin." },
    { key = "foreverDungeonJournalSkin", addon = "ForeverDungeonJournal", label = "Dungeon Journal",
      what = "Gives the Forever Dungeon Journal window (/fj) the EllesmereUI look." },
    { key = "whatsTrainingSkin", addon = "WhatsTraining", label = "WhatsTraining",
      what = "Gives WhatsTraining's floating window (/wt) the EllesmereUI look." },
}

-- What a skin is doing right now: a word or two, a sentence (or nil) and, third, whether it is on but can't work
-- as set for want of EllesmereUI (the row says so under its label, not only in its tooltip).
local function SkinStatus(skin)
    local state = K.AddonState(skin.addon)
    if state == "missing" then return R.GREY .. "Not installed|r", "Install " .. skin.label .. " to use this skin." end
    if state == "disabled" then return R.GREY .. "Turned off|r", skin.label .. " is turned off in your AddOns list." end
    local on = R:Enabled(skin.key)
    -- the one record of what waits for a reload (Switches.lua): a skin turned back before a reload is not pending
    if R.Switches.IsPending(skin.key) then
        return R.GOLD .. (on and "On" or "Off") .. " after reload|r", "Reload your UI for this to take effect."
    end
    if not on then return R.GREY .. "Off|r", nil end
    if K.AddonState("EllesmereUI") == "missing" then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI isn't installed. The skin only works with it.", true
    end
    if not R.S then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI hasn't switched on TwichUI's skins. Check its third-party addon skin options.", true
    end
    if not K.Loaded(skin.addon) then
        return R.GREEN .. "Ready|r", "Applies when " .. skin.label .. " loads."
    end
    return R.GREEN .. "Active|r", nil
end

K.Page({
    key = "skins", name = "Addon skins", order = 90, group = "addons",
    description = "The EllesmereUI look for supported addons, and TwichUI's own look for SpeakStone and the RestedXP guide window (in its own section). The rest of TwichUI works without them.",
    keywords = "skin theme ellesmere attune auctionator dungeon journal whatstraining",
    overview = {
        label = "Addon skins", tip = "The EllesmereUI look for supported addons. Needs EllesmereUI; the rest of TwichUI works without it.",
        status = function()
            local installed, on = 0, 0
            for _, skin in ipairs(SKINS) do
                if K.AddonState(skin.addon) ~= "missing" then
                    installed = installed + 1
                    if R:Enabled(skin.key) then on = on + 1 end
                end
            end
            if installed == 0 then return R.GREY .. "None installed|r" end
            return K.OnOff(on > 0, ("%d of %d on"):format(on, installed), "Off")
        end,
    },
    build = function()
        local Header, Toggle, Button = K.Header, K.Toggle, K.Button

        Header("EllesmereUI look", "Gives these addons the EllesmereUI look. Needs EllesmereUI with its third-party addon skins on. TwichUI only skins the addons listed here.")
        -- Each skin's tooltip ends with its status, read when it is shown.
        for _, skin in ipairs(SKINS) do
            local installed = K.AddonState(skin.addon) ~= "missing"
            local label = installed and skin.label or (skin.label .. "  " .. R.GREY .. "(not installed)|r")
            local row = Toggle(skin.key, label, skin.what)
            if row then
                row.data.tooltip = function()
                    local status, detail = SkinStatus(skin)
                    return skin.what .. "\n\nTakes effect after you reload your UI.\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
                end
                -- on, installed, but EllesmereUI isn't giving it a look: said under the label, with what to do
                K.Note(row, function()
                    local _, detail, needs = SkinStatus(skin)
                    if needs then return detail, "warn" end
                end)
                if not installed then
                    row:AddModifyPredicate(function() return false end)
                    row.why = "Install " .. skin.label .. " to use this skin."
                end
            end
        end

        -- RestedXP: its own section in the list (they are many): a short pointer here.
        if R.RestedXPSkin then
            Header("RestedXP guide window", "Gives the RestedXP Guides window a TwichUI look, and its waypoint arrow a shape, color and size of your choosing. Its settings are in the RestedXP section of the list, on the left.")
            Button("RestedXP guide window", "Open its page", function() R:OpenSettings("restedxp") end,
                "Opens the RestedXP page, in the RestedXP section: the game's waypoint on RestedXP's destination, and the guide window's switch, look, text, spacing, scroll bar, header and footer, waypoint arrow and timer bars.")
        end

        -- SpeakStone: the same, its own page, not through EllesmereUI.
        if R.SpeakStoneSkin then
            Header("SpeakStone speech frame", "Gives SpeakStone's speech frame a TwichUI look: background and border, fonts and colors, the controls, the portrait and the progress line. Its settings are on a page of their own, under this one.")
            Button("SpeakStone speech frame", "Open its page", function() R:OpenSettings("speakstone") end,
                "Opens the SpeakStone speech frame page, under Addon skins: the switch, the look, text, controls, portrait, progress line and spacing.")
        end
    end,
})
