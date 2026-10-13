-- TwichUI settings: Notifications (zone arrival, new training and friend login cards, and their previews).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "notifications", name = "Notifications", order = 20, group = "everyday",
    description = "Small, quiet cards for arriving somewhere new, new training at a level-up, and friends logging in.",
    keywords = "zone text title card banner toast popup friend online chime level up trainer preview",
    overview = {
        label = "Notifications", tip = "Quiet cards for arriving somewhere new, new training at a level-up, and friends logging in. Previews of each card are on this page.",
        status = function()
            local on = (R:Enabled("arrival") and 1 or 0) + (R:Enabled("trainingNotice") and 1 or 0) + (R:Enabled("friendLogin") and 1 or 0)
            return K.OnOff(on > 0, ("%d of 3 on"):format(on), "Off")
        end,
    },
    build = function()
        local Header, Toggle, Button, Choice, ProxyToggle, Advanced, Under = K.Header, K.Toggle, K.Button, K.Choice, K.ProxyToggle, K.Advanced, K.Under
        local STRING = K.STRING

        Header("Notifications", "Small, quiet cards near the edges of the screen for moments worth a glance. None of them makes you do anything, and each can be turned off on its own.")
        Toggle("arrivalReducedMotion", "Reduced motion",
            "The notification cards only fade in and out, without moving. Applies to the zone, training and friend cards.")

        Header("Zone arrival", "A short, quiet title card when you arrive somewhere new, in place of the game's own zone text.")
        local arrival = Toggle("arrival", "Show a title card when I arrive in a new zone",
            "The zone's name appears near the top of the screen under a thin bronze rule, with the smaller place you're in beneath it, then fades away. It replaces the game's own zone text while on. Not shown when you log in or reload, or while on a flight path: only where you land.\n\nIf another addon also replaces the zone text, you may see both.")
        local function ArrivalOn() return R:Enabled("arrival") end
        Under(Toggle("arrivalSubzones", "Also for smaller places",
            "A quieter card when you walk into a smaller place within the zone, such as a town. Off: moving within a zone shows nothing."), arrival, ArrivalOn)
        Under(Toggle("arrivalDungeons", "Show dungeon and raid arrival cards",
            "Walking into a dungeon or raid shows its name with \"Dungeon\" or \"Raid\" beneath it. Off: you get the ordinary zone card there, as before. Not shown when you log in or reload inside one."), arrival, ArrivalOn)

        Header("New training", "A short card when you level up and there is class training you haven't taken yet.")
        Toggle("trainingNotice", "Show new training when I level up",
            "When you level up and there are class spells or ranks you could train and don't know yet, including ones from earlier levels you haven't trained, a short title card near the top of the screen, below the zone's name, lists them (only the highest rank of each spell), in the zone card's style with no frame. Move it in Edit Mode. They are available to train at your class trainer; nothing is learned for you. Nothing shows when there is nothing to train. It waits until you're out of combat, fades by itself, and makes no sound or chat line. Reduced motion (above) applies.\n\nType /tui training to see the card for your current level. Spell data comes from What's Training?.")

        Header("Friend login", "A short card when a Battle.net friend comes online, in place of the game's own pop-up.")
        local friendLogin = Toggle("friendLogin", "Show Battle.net friend logins as a TwichUI card",
            "When a Battle.net friend comes online, a short card with their name, a Horde or Alliance mark if the game says which faction they play, and the character they are on, in the zone card's style with no frame. It replaces the game's own friend-online pop-up while on; the pop-ups for friends going offline, broadcasts, friend requests and invitations, and the line in chat, are unchanged. Turn it off to get the game's pop-up back. The game's own Social options still apply: with Show Toast Window or Online Friends off, nothing shows. Nothing shows at login or reload, or in combat; several friends arriving together give one card. Move it in Edit Mode. It plays a soft chime, which you can change below. Reduced motion (above) applies.\n\nType /tui friend to see the card.")
        local function FriendLoginOn() return R:Enabled("friendLogin") end
        Under(Toggle("friendLoginSound", "Play a soft chime with it",
            "A short chime when the card appears; choose which one below. Off: the card is silent."), friendLogin, FriendLoginOn)
        local FriendLogin = R.FriendLogin
        if FriendLogin then
            local chime = K.Proxy("friendLoginChime", STRING, "Chime sound", FriendLogin.SOUND_DEFAULT,
                function() return FriendLogin.Sound() end, function(value) FriendLogin.SetSound(value) end)
            Under(K.Dropdown(chime, FriendLogin.SoundChoices,
                "The sound to play. TwichUI's own are listed first, then every sound other addons have added to LibSharedMedia. Press Hear the chime to try it. A sound that has gone (its addon isn't loaded) stays chosen, and TwichUI Notification plays in its place until it returns."),
                friendLogin, FriendLoginOn)
            local channels = {}
            for i, channel in ipairs(FriendLogin.CHANNELS) do channels[i] = { channel.key, channel.label, channel.tooltip } end
            Under(Choice("friendLoginChannel", "Chime volume follows",
                "A sound file can't have a volume of its own, so the chime is as loud as the game volume you choose here. Set that volume in the game's Audio options: lower it to make the chime quieter, or pick the one you keep lowest.",
                STRING, FriendLogin.CHANNEL_DEFAULT,
                function() return (FriendLogin.SoundChannel()) end,
                function(value) FriendLogin.SetSoundChannel(value) end,
                channels), friendLogin, FriendLoginOn)
            Under(Button("Hear the chime", "Play", function() FriendLogin.PlaySound() end,
                "Plays the chosen chime now, at the volume you have chosen."), friendLogin, FriendLoginOn)
        end

        local Notify = R.Notify
        if Notify then
            Header("Notification previews", "Try the cards without waiting for the real thing. A preview tests how a card looks and sounds, not whether the game event is noticed: it uses made-up details, records and changes nothing, and works even when that card is turned off.")
            ProxyToggle("previewSounds", "Play notification sounds in previews",
                "Previews are silent unless this is on. The friend login chime then plays with its preview, on the volume you chose above, but only while \"Play a soft chime with it\" is on, as it is for a real login. The other cards have no sound.",
                false,
                Notify.PreviewSounds, Notify.SetPreviewSounds)
            local previewTips = {
                arrival = "Shows the zone card with a made-up place, where and how it would really appear.",
                training = "Shows the new training card with made-up spells. Nothing is trained or marked, and it can't be clicked.",
                friend = "Shows the friend login card with a made-up friend. No friend state is read or changed.",
                welcome = "Shows the Welcome Back card with a made-up entry. Your Chronicle isn't read, and its link does nothing.",
            }
            local labels = {}
            for _, info in ipairs(Notify.Kinds()) do labels[info.kind] = info.label end
            -- A preview waits for the fight to end, like the cards themselves, and says when it couldn't show.
            local previewWhy = { full = "too many cards are waiting. Try Clear previews.", unknown = "that card isn't available." }
            local function Preview(kind)
                if InCombatLockdown() then R.Print("previews wait until you're out of combat.") return end
                local ok, why = Notify.Preview(kind)
                if ok == false then R.Print("couldn't show that preview: %s", previewWhy[why] or "it's already showing.") end
            end
            for _, kind in ipairs({ "arrival", "training", "friend", "welcome" }) do
                if labels[kind] then
                    Button(labels[kind], "Preview", function() Preview(kind) end,
                        previewTips[kind] .. " It appears above this window and fades by itself. Real notices always come first.")
                end
            end
            Button("Test coordinated sequence", "Run", function()
                if InCombatLockdown() then R.Print("previews wait until you're out of combat.") return end
                local sent, dropped = Notify.PreviewSequence()
                R.Print("Test sequence: %d sample notices sent, %d repeat dropped. Cards in different places show together; the rest take turns.", sent, dropped)
            end, "Sends a fixed set of sample notices at once: a zone card, a friend card, a training card, a repeat of the zone card (which is dropped) and a Welcome Back card. The friend card shows beside the zone card; the training and Welcome Back cards wait their turn at the top.")
            Button("Clear previews", "Clear", function() Notify.ClearPreviews() end,
                "Stops every preview, showing or waiting. Real notices aren't touched.")
        end

        local Arrival = R.Arrival
        if Arrival then
            local holds = {}
            for i, hold in ipairs(Arrival.HOLDS) do
                holds[i] = { hold.key, hold.label, ("Stays %g seconds before fading away."):format(hold.seconds) }
            end
            Advanced(Header("Advanced"))
            Under(Advanced(Choice("arrivalHold", "How long the zone card stays",
                "How long the zone's name stays before it fades away. Cards for smaller places stay a little shorter.",
                STRING, Arrival.HOLD_DEFAULT,
                function() return (Arrival.HoldChoice()) end,
                function(value) Arrival.SetHoldChoice(value) end,
                holds)), arrival, ArrivalOn)
        end
    end,
})
