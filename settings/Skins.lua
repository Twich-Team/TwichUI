-- TwichUI options: Addon skins (the EllesmereUI look for supported addons, and a pointer to the RestedXP
-- guide window's own page, settings/RestedXP.lua).

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

-- What a skin is doing right now: a word or two, and a sentence (or nil).
-- onAtLoad: whether the skin's toggle was on when the UI loaded.
local function SkinStatus(skin, onAtLoad)
    local state = K.AddonState(skin.addon)
    if state == "missing" then return R.GREY .. "Not installed|r", "Install " .. skin.label .. " to use this skin." end
    if state == "disabled" then return R.GREY .. "Turned off|r", skin.label .. " is turned off in your AddOns list." end
    local on = R:Enabled(skin.key)
    if on ~= onAtLoad then
        return R.GOLD .. (on and "On" or "Off") .. " after reload|r", "Reload your UI for this to take effect."
    end
    if not on then return R.GREY .. "Off|r", nil end
    if K.AddonState("EllesmereUI") == "missing" then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI isn't installed. The skin only works with it."
    end
    if not R.S then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI hasn't switched on TwichUI's skins. Check its third-party addon skin options."
    end
    if not K.Loaded(skin.addon) then
        return R.GREEN .. "Ready|r", "Applies when " .. skin.label .. " loads."
    end
    return R.GREEN .. "Active|r", nil
end

K.Page({
    key = "skins", name = "Addon skins", order = 90,
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
        -- Each skin's tooltip ends with its status, kept current by the events
        -- that can change it (no polling).
        local skinRows = {}
        local function RefreshSkinStatus()
            for _, row in ipairs(skinRows) do
                local status, detail = SkinStatus(row.skin, row.onAtLoad)
                if row.initializer.data then
                    row.initializer.data.tooltip = row.skin.what .. "\n\nTakes effect after you reload your UI.\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
                end
            end
            K.RefreshOverview()
        end
        for _, skin in ipairs(SKINS) do
            local installed = K.AddonState(skin.addon) ~= "missing"
            local label = installed and skin.label or (skin.label .. "  " .. R.GREY .. "(not installed)|r")
            local initializer = Toggle(skin.key, label, skin.what, true, nil, RefreshSkinStatus)
            if initializer then
                skinRows[#skinRows + 1] = { skin = skin, initializer = initializer, onAtLoad = R:Enabled(skin.key) }
                if not installed and initializer.AddModifyPredicate then
                    initializer:AddModifyPredicate(function() return false end)
                end
            end
        end
        RefreshSkinStatus()
        R:OnSkin(RefreshSkinStatus)
        R:On("PLAYER_LOGIN", RefreshSkinStatus)
        R:On("ADDON_LOADED", function(name)
            for _, skin in ipairs(SKINS) do
                if name == skin.addon then RefreshSkinStatus() return end
            end
        end)

        -- RestedXP: its own look, set on a page of its own under this one (they are many): a short pointer here.
        if R.RestedXPSkin then
            Header("RestedXP guide window", "Gives the RestedXP Guides window a TwichUI look, and its waypoint arrow a shape, color and size of your choosing. Its settings are on a page of their own, under this one.")
            Button("RestedXP guide window", "Open its settings", function() R:OpenSettings("restedxp") end,
                "Opens the RestedXP guide window page, under Addon skins: the switch, the look, text, spacing, scroll bar, header and footer, and the waypoint arrow.")
        end

        -- SpeakStone: the same, its own page, not through EllesmereUI.
        if R.SpeakStoneSkin then
            Header("SpeakStone speech frame", "Gives SpeakStone's speech frame a TwichUI look: background and border, fonts and colors, the controls, the portrait and the progress line. Its settings are on a page of their own, under this one.")
            Button("SpeakStone speech frame", "Open its settings", function() R:OpenSettings("speakstone") end,
                "Opens the SpeakStone speech frame page, under Addon skins: the switch, the look, text, controls, portrait, progress line and spacing.")
        end
    end,
})
