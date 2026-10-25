-- TwichUI settings: Notifications (zone arrival, new training and friend login cards, and their previews), and
-- how the cards look (modules/NotifyLook.lua) on a page of its own under it.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "notifications", name = "Notifications", order = 20, group = "everyday",
    description = "Small, quiet cards for arriving somewhere new, new training at a level-up, and friends logging in.",
    keywords = "zone text title card banner toast popup friend online chime level up trainer preview font color opacity background appearance",
    overview = {
        label = "Notifications", tip = "Quiet cards for arriving somewhere new, new training at a level-up, and friends logging in. Previews of each card are on this page.",
        status = function()
            local on = (R:Enabled("arrival") and 1 or 0) + (R:Enabled("trainingNotice") and 1 or 0) + (R:Enabled("friendLogin") and 1 or 0)
            return K.OnOff(on > 0, ("%d of 3 on"):format(on), "Off")
        end,
    },
    build = function()
        local Header, Toggle, Button, Choice, ProxyToggle, Under = K.Header, K.Toggle, K.Button, K.Choice, K.ProxyToggle, K.Under
        local STRING = K.STRING

        Header("Accessibility", "Applies to the notification cards only: not to TwichUI's windows.")
        Toggle("arrivalReducedMotion", "Reduced motion",
            "The notification cards only fade in and out, without moving: no rise or slide. Applies to the zone, training, friend login and Welcome Back cards, and to their previews. TwichUI's windows have their own setting, Reduce window motion on Home.")

        Header("Zone arrival", "A short, quiet title card when you arrive somewhere new, in place of the game's own zone text.")
        local arrival = Toggle("arrival", "Show a title card when I arrive in a new zone",
            "The zone's name appears near the top of the screen under a thin bronze rule, with the smaller place you're in beneath it, then fades away. It replaces the game's own zone text while on. Not shown when you log in or reload, or while on a flight path: only where you land.\n\nIf another addon also replaces the zone text, you may see both.")
        local function ArrivalOn() return R:Enabled("arrival") end
        Under(Toggle("arrivalSubzones", "Also for smaller places",
            "A quieter card when you walk into a smaller place within the zone, such as a town. Off: moving within a zone shows nothing."), arrival, ArrivalOn)
        Under(Toggle("arrivalDungeons", "Show dungeon and raid arrival cards",
            "Walking into a dungeon or raid shows its name with \"Dungeon\" or \"Raid\" beneath it. Off: you get the ordinary zone card there, as before. Not shown when you log in or reload inside one."), arrival, ArrivalOn)
        local Arrival = R.Arrival
        if Arrival then
            local holds = {}
            for i, hold in ipairs(Arrival.HOLDS) do
                holds[i] = { hold.key, hold.label, ("Stays %g seconds before fading away."):format(hold.seconds) }
            end
            Under(Choice("arrivalHold", "How long the zone card stays",
                "How long the zone's name stays before it fades away. Cards for smaller places stay a little shorter.",
                STRING, Arrival.HOLD_DEFAULT,
                function() return (Arrival.HoldChoice()) end,
                function(value) Arrival.SetHoldChoice(value) end,
                holds), arrival, ArrivalOn)
        end

        Header("New training", "A short card when you level up and there is class training you haven't taken yet.")
        Toggle("trainingNotice", "Show new training when I level up",
            "When you level up and there are class spells or ranks you could train and don't know yet, including ones from earlier levels you haven't trained, a short title card near the top of the screen, below the zone's name, lists them (only the highest rank of each spell), in the zone card's style with no frame. Move it in Edit Mode. They are available to train at your class trainer; nothing is learned for you. Nothing shows when there is nothing to train. It waits until you're out of combat, fades by itself, and makes no sound or chat line. Reduced motion (above) applies.\n\nType /tui training to see the card for your current level. Spell data comes from What's Training?.")
        local Training = R.Training
        if Training then
            local styles = {}
            for i, style in ipairs(Training.STYLES) do styles[i] = { style.key, style.label, style.tip } end
            Choice("trainingStyle", "Training notification style",
                "How the new training card looks. Classic is the card as it has always been. Illustrated adds a small bronze spellbook above the heading and a thin divider beneath it. Only this card changes, and nothing about when it appears or what it lists. A preview that is up changes at once; press Preview under Notification previews to see the card.",
                STRING, Training.STYLE_DEFAULT,
                function() return Training.Style() end,
                function(value) Training.SetStyle(value) end,
                styles)
        end

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
                training = "Shows the new training card, in the style chosen above, with made-up spells. Nothing is trained or marked, and it can't be clicked.",
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

        -- How the cards look has a page of its own, under this one (there are many settings): a short pointer here.
        if K.pages.notificationsLook then
            Header("Appearance", "How the cards look: fonts, text size, colors, opacity and an optional backdrop, for all of them or for one card. Its settings are on a page of their own, under this one.")
            Button("Notification appearance", "Open its page", function() R:OpenSettings("notificationsLook") end,
                "Opens the Notification appearance page, under this one. A preview there stays up while you change a setting. Nothing there changes when a card appears or what it says.")
        end
    end,
})

-- How the cards look (modules/NotifyLook.lua). Not when they appear, what they say, where they sit or their sounds.
K.Page({
    key = "notificationsLook", name = "Notification appearance", nav = "Appearance", parent = "notifications", order = 21,
    description = "How the notification cards look. Nothing here changes when a card appears, what it says, where it sits or its sound.",
    keywords = "notification card look font size color opacity background backdrop accent rule outline shadow text typeface preview zone training friend welcome",
    when = function() return R.NotifyLook ~= nil and R.Notify ~= nil end,
    build = function()
        local NL, Notify = R.NotifyLook, R.Notify
        local Header, Button = K.Header, K.Button
        local STRING, NUMBER = K.STRING, K.NUMBER
        local Fonts = R.MenuStyle and R.MenuStyle.Fonts

        -- What is being edited: the shared look, or one card. Only a page state; nothing is saved by choosing.
        local function Editing() return NL.Scope() end
        local function Own() return Editing() ~= "shared" and NL.Own(Editing()) end
        local function CanEdit() return Editing() == "shared" or Own() end
        local function Label() return Editing() == "shared" and "the shared look" or (NL.LABELS[Editing()] .. " card") end

        -- A row of appearance, greyed out (and saying why) while a card that follows the shared look is chosen.
        local function Gate(row)
            if row then
                row:AddModifyPredicate(CanEdit)
                row.why = "Greyed out: this card follows the shared look. Turn on \"Give this card its own look\" above to change it here."
            end
            return row
        end
        -- Not every card has every part: the zone and friend cards have no main text, so no color for it.
        local function OnlyWhere(row, key)
            if row then row:AddShownPredicate(function() return NL.Applies(Editing(), key) end) end
            return row
        end
        local function Setting(variable, varType, label, key)
            return K.Proxy("notifyLook" .. variable, varType, label, nil,
                function() return NL.GetFor(Editing(), key) end,
                function(value) NL.Set(Editing(), key, value) end)
        end
        local function Pick(variable, key, label, tooltip, choices)
            return Gate(K.Dropdown(Setting(variable, STRING, label, key), choices, tooltip))
        end
        local function Swatch(variable, key, label, tooltip)
            return OnlyWhere(Gate(K.Swatch(Setting(variable, STRING, label, key), tooltip)), key)
        end
        local function Slide(variable, key, label, tooltip)
            local limit = NL.LIMITS[key]
            return Gate(K.Slider(Setting(variable, NUMBER, label, key), limit[1], limit[2], tooltip))
        end
        local function FontChoices(key, first)
            return function()
                local current = NL.GetFor(Editing(), key)
                return Fonts and Fonts.Choices(current, first) or first
            end
        end

        Header("Notification appearance", "The same look is used by all four cards, unless a card is given a look of its own. Each setting does what the label says and nothing more: the defaults are exactly how the cards have always looked, so nothing changes until you change it. Changes show at once on a preview that is up.")
        local scopes = K.Dropdown(K.Proxy("notifyLookScope", STRING, "Customize", nil, Editing, NL.SetScope),
            function()
                local list = { { "shared", "Shared look (all cards)" } }
                for _, kind in ipairs(NL.KINDS) do
                    list[#list + 1] = { kind, NL.LABELS[kind] .. (NL.Own(kind) and " (own look)" or "") }
                end
                return list
            end,
            "Which look the settings below change. The shared look is used by every card that has no look of its own. Choose a card to give it a look of its own; it then follows only what you set for it. Choosing here changes nothing by itself.")
        local own = K.ProxyToggle("notifyLookOwn", "Give this card its own look",
            "On: this card is drawn with the look set below, copied from the shared look when you turn this on, and later changes to the shared look don't reach it. Off: it follows the shared look again, and what you set for it is kept for next time. \"Reset this card\" at the bottom forgets it.",
            nil,
            function() return Own() end,
            function(on) NL.SetOwn(Editing(), on) end)
        if own then own:AddShownPredicate(function() return Editing() ~= "shared" end) end

        Header("Preview", "Shows a card as it really looks, with made-up details, so you can see a change without waiting for the real event. A preview stays up while you work, is silent, works even when its card is turned off, reads and changes nothing in the game, and gives way to any real notice. It is put away when you close these settings, enter combat or change profile.")
        for _, kind in ipairs(NL.KINDS) do
            Button(NL.LABELS[kind] .. " card",
                function() return NL.Pinned(kind) and "Hide" or "Show" end,
                function()
                    if NL.Pinned(kind) then
                        NL.Unpin(kind)
                    elseif InCombatLockdown() then
                        R.Print("previews wait until you're out of combat.")
                    else
                        local ok, why = NL.Pin(kind)
                        if ok == false then
                            R.Print("couldn't show that preview: %s", why == "full" and "too many cards are waiting. Try Hide all." or "it's already showing.")
                        end
                    end
                end,
                "Shows or hides the " .. NL.LABELS[kind]:lower() .. " card with made-up details, where it really appears, drawn with the look it has now (its own, or the shared one). It is silent, and it appears above this window.")
        end
        Button("Hide all previews", "Hide", NL.ClearPreviews,
            "Puts every preview away, including those from the Notifications page. Real notices aren't touched.")
        if Notify.OnPreviewChange then
            Notify.OnPreviewChange(function() K.RefreshOverview() end)   -- the Show/Hide buttons follow a preview ending
        end

        Header("Text", "Fonts come from LibSharedMedia, so TwichUI's own, EllesmereUI's and any other addon's are listed. A font that has gone is drawn as the card's own and stays chosen.")
        Pick("TitleFont", "titleFont", "Title font",
            "The face of each card's heading: the zone's name, \"New Training Available\", the friend's name and \"Welcome Back\". The card's own is the default.",
            FontChoices("titleFont", { { "default", "Card's own (default)" } }))
        Pick("TextFont", "textFont", "Text font",
            "The face of everything under the heading: the smaller place, the spells, the character, the last place noted and the territory line.",
            FontChoices("textFont", { { "default", "Card's own (default)" } }))
        Slide("TextScale", "textScale", "Text size",
            "How large the text is, in percent of each card's own sizes, so the cards keep their proportions. 100 is how they have always been. The card grows to fit; where it sits doesn't change.")
        Pick("Outline", "outline", "Text outline",
            "Shadow is the soft dark edge the cards have always had. Outline and Thick outline replace it with a line round each letter, which reads well over a bright scene. None leaves the text bare.",
            function() return NL.OUTLINE_CHOICES end)
        Swatch("TitleColor", "titleColor", "Title color",
            "The color of each card's heading. The smaller place's card keeps its slightly quieter shade of whatever you choose.")
        Swatch("BodyColor", "bodyColor", "Main text color",
            "The color of the training card's spells and of the place on the Welcome Back card. The zone and friend cards have no main text.")
        Swatch("DetailColor", "detailColor", "Detail text color",
            "The color of the quieter lines: the smaller place, the character's name, \"Visit a class trainer\", and the rank and level beside a spell. The territory line keeps its own color, which says whose land it is.")
        Slide("TextOpacity", "textOpacity", "Text opacity",
            "How solid the text is, in percent. Only the text fades: the backdrop, the rule and the faction mark are not affected. It can't go below 30 so a card stays readable.")

        Header("Accent and backdrop", "The thin rule under each heading, and an optional panel behind a card's text. The cards have never had a backdrop, so it is off until you give it some opacity.")
        Swatch("AccentColor", "accentColor", "Accent color",
            "The color of the rule under each heading and its small gold mark, which follows it.")
        Slide("AccentOpacity", "accentOpacity", "Accent opacity",
            "How solid the rule is, in percent. 0 hides it. Only the rule fades.")
        Swatch("BgColor", "bgColor", "Backdrop color", "The color of the panel behind the text.")
        local bgOpacity = Slide("BgOpacity", "bgOpacity", "Backdrop opacity",
            "How solid the panel behind the text is, in percent. 0 draws none, as the cards have always been. It sits behind the text only: the text, the rule and the mark keep their own strength.")
        local padding = Slide("Padding", "padding", "Backdrop padding",
            "How far the panel reaches beyond the text, in pixels. Only matters while the backdrop has some opacity.")
        if padding and bgOpacity then
            padding:AddModifyPredicate(function() return NL.GetFor(Editing(), "bgOpacity") > 0 end)
            local gate = padding.why
            padding.why = function()
                if not CanEdit() then return gate end
                return "Greyed out: the backdrop has no opacity, so there is nothing to pad. Raise Backdrop opacity first."
            end
        end

        Header("Reset", "Each reset says what it covers. Which cards are on, their sounds, where they sit, the Journey Chronicle and every other page are never changed here.")
        local function ResetRow(label, tip, text, key, act, shown)
            local row = Button(label, "Reset", function()
                R.Interact.Confirm(key, text(), function()
                    act()
                    K.RefreshOverview()
                end, { accept = "Reset" })
            end, tip)
            if row then
                row.reset = true
                if shown then row:AddShownPredicate(shown) end
            end
            return row
        end
        ResetRow("Reset the shared look", "Puts the shared look back to the defaults, which is how the cards have always looked. A card's own look is left as it is.",
            function()
                return "Reset the shared notification look?\n\nThe fonts, text size, outline, colors, opacity, accent and backdrop of the shared look go back to the defaults. Cards with a look of their own keep it. Which cards are on, their sounds, where they sit and every other setting are not changed."
            end,
            "TWICHUI_NOTIFY_LOOK_RESET_SHARED", function() NL.ResetShared() end)
        ResetRow("Reset this card", "Makes the card chosen above follow the shared look again, and forgets the look you set for it. The shared look and the other cards are not changed.",
            function()
                return ("Make the %s follow the shared look again?\n\nThe look you set for this card is forgotten. The shared look and the other cards are not changed, and nor is anything else: whether the card is on, its sound and where it sits stay as they are."):format(Label())
            end,
            "TWICHUI_NOTIFY_LOOK_RESET_CARD", function() NL.ResetCard(Editing()) end,
            function() return Editing() ~= "shared" end)
    end,
})
