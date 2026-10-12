-- TwichUI options: Configuration sharing (setup/: sending and receiving addon configurations, the version
-- check, and the read-only data windows). The workflows themselves live in their own windows.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "sharing", name = "Configuration sharing", order = 100,
    overview = {
        label = "Configuration sharing", tip = "Share your addon settings with friends, and keep backups.",
        status = function() return K.OnOff(R:Enabled("setupSharing")) end,
    },
    build = function()
        local Header, Toggle, Button, Choice, Advanced, Under = K.Header, K.Toggle, K.Button, K.Choice, K.Advanced, K.Under
        -- the sharing window shows these switches' state
        local function RefreshWindow() if R.Window then R.Window:Refresh() end end

        Header("Addon configurations", "Share the settings of the addons you choose with friends, and apply theirs. You always choose what to apply, and Undo puts your own settings back.")
        local sharing = Toggle("setupSharing", "Configuration sharing",
            "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /tui share.",
            true, function()
                if not R:Enabled("setupSharing") and R.Share then R.Share:Settle("module-off") end
                RefreshWindow()
            end)
        local function SharingOn() return R:Enabled("setupSharing") end
        Under(Toggle("acceptSetups", "Let friends send me addon configurations",
            "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
            false, function()
                if not R:Enabled("acceptSetups") and R.Share then R.Share:Settle("module-off", true) end
                RefreshWindow()
            end), sharing, SharingOn)
        Toggle("groupCheck", "Version and group check",
            "On by default. Both players need it on to see each other. Other players never see these messages, even without TwichUI.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /tui check and Party compatibility check in /tui share, and a once-per-game-build test message that shows in Sending options whether direct messages reached another TwichUI user.",
            true, RefreshWindow)
        Under(Button("Configuration sharing", "Open", function()
            if not R:Enabled("setupSharing") then
                R.Print("turn on Configuration sharing first.")
                return
            end
            K.CloseOptions()
            R.Window:Show()
        end, "Opens the sharing window: send your setup, review ones friends sent, create backups and run the party compatibility check (same as typing /tui share)."), sharing, SharingOn)
        Button("Addon data", "Open", function()
            K.CloseOptions()
            if R.StoredDataWindow then R.StoredDataWindow:Show() end
        end, "See which addons keep data between sessions, about how big it is, and look through it. Read-only: nothing can be changed there (same as typing /tui data).")
        Button("Saved Data Explorer", "Open", function()
            K.CloseOptions()
            if R.ExplorerWindow then R.ExplorerWindow.Show() end
        end, "Look through what TwichUI keeps: its settings, your backups and Undo copies, your saved setup, setups friends sent, the Journey Chronicle, and exactly what Send would send. Read-only: nothing is changed, restored or sent there (same as typing /tui saved).")
        local Share = R.Share
        if Share then
            Advanced(Header("Advanced"))
            Advanced(Choice("shareTransport", "Send configurations by",
                "How your configuration travels when you press Send. TwichUI uses only the one you pick and never switches by itself if it fails. Receiving works on all three, whatever you pick here.\n\n" .. Share.TRANSPORT_EXPLAIN,
                K.STRING, "DIRECT",
                function() return Share.Transport() end,
                function(value) Share.SetTransport(value) end,
                function()
                    local list = {}
                    for _, key in ipairs(Share.TRANSPORTS) do
                        list[#list + 1] = { key, Share.TRANSPORT_LABEL[key], Share.TRANSPORT_HELP[key] }
                    end
                    return list
                end))
        end
    end,
})
