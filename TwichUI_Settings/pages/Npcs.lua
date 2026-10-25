-- TwichUI settings: Vendors and trainers (npcs/). Its first tab has the switch and which kinds of NPC the world map
-- shows; its second (npcsList) your list's counts, sharing it, the probe and removing what is in it. Every choice goes
-- through npcs/Prefs.lua and every action through the feature's own functions (Store, Share, Collect); nothing here
-- reads or writes TwichUIDB itself.

local R = TwichUI
local K = R.SettingsKit

local npcToggle   -- the switch (first tab), which the other tab's rows are greyed out under

local function On() return R:Enabled("npcMap") end

local function Counts()
    local NS = R.NpcStore
    if not NS then return "Not loaded" end
    local own, reported = NS.Counts()
    if own + reported == 0 then return "Empty" end
    return ("%d seen by you, %d from others"):format(own, reported)
end

-- A checkbox for one choice in npcs/Prefs.lua, remembered for its page's reset.
local function Checker(reset)
    return function(variable, key, label, tooltip)
        local NP = R.NpcPrefs
        local setting = K.Proxy(variable, K.BOOL, label, NP.DEFAULTS[key], function() return NP.Get(key) end,
            function(value) NP.Set(key, value and true or false) end)
        if setting then reset[#reset + 1] = { setting = setting, default = NP.DEFAULTS[key] } end
        return K.Checkbox(setting, tooltip)
    end
end

K.Page({
    key = "npcs", name = "Vendors and trainers", tab = "On the map", order = 75, group = "journey",
    description = "The vendors, trainers and services you deal with, noted where they stand and shown on your world map by the kinds you choose.",
    keywords = "npc npcs vendor vendors merchant reagent reagents ammo ammunition arrows bullets food drink trade supplies repair recipes bags trainer trainers class profession pet innkeeper inn banker bank auctioneer auction stable flight master spirit healer guild map markers icons",
    when = function() return R.NpcStore ~= nil and R.NpcPrefs ~= nil end,
    overview = { label = "Vendors and trainers", tip = "The vendors, trainers and services you have dealt with, on your world map.",
        status = function() return K.OnOff(On()) end },
    build = function()
        local NK, NP = R.NpcKinds, R.NpcPrefs
        local Header, Toggle, Under, Proxy = K.Header, K.Toggle, K.Under, K.Proxy
        local reset = {}
        local Check = Checker(reset)

        Header("Vendors and trainers", "When you deal with an NPC (buy from it, train, use its bank, inn, auction house, stable or flight master), TwichUI notes what it offered and where you stood, and shows it on your world map. Only NPCs you have dealt with yourself, or that another TwichUI user sent you, are known: nothing is downloaded or guessed.")
        npcToggle = Toggle("npcMap", "Note vendors, trainers and services",
            "Notes each NPC you deal with: its name, what it offered (a merchant by the kinds of item it sold and whether it repairs, a trainer by the client's own trainer type, a service by the window it opened) and where you stood, which is within a few yards of it. Its marker then shows on your world map on its zone and the maps inside it.\n\nIt only reads: it never buys, trains or opens anything for you. Inside dungeons and raids nothing is noted.\n\nOff: nothing is noted, the markers leave the map and lists others are sending you are ignored. Your list is kept for when you turn it on again.")
        Under(K.Status("Your list", Counts, nil, "How many NPCs you have noted yourself, and how many came from other TwichUI users and haven't been seen by you yet."), npcToggle, On)

        for _, section in ipairs(NK.SECTIONS) do
            local intro = {
                vendors = "Merchants, by what they had for sale when you visited. One merchant can be several of these.",
                trainers = "Trainers, by the kind of trainer the game says they are.",
                services = "NPCs that offer a service of the game's own.",
            }
            Header(section.label, intro[section.id])
            for _, kind in ipairs(NK.LIST) do
                if kind.section == section.id then
                    local name = kind.id:sub(1, 1):upper() .. kind.id:sub(2)
                    Under(Check("npcMapShow" .. name, "show." .. kind.id, kind.label, kind.tip), npcToggle, On)
                end
            end
            if section.id == "trainers" then
                local trainerClass = Proxy("npcMapTrainerClass", K.STRING, "Class trainers shown", NP.DEFAULTS.trainerClass,
                    function() return NP.Get("trainerClass") end, function(value) NP.Set("trainerClass", value) end)
                if trainerClass then reset[#reset + 1] = { setting = trainerClass, default = NP.DEFAULTS.trainerClass } end
                Under(K.Dropdown(trainerClass, function() return NP.TRAINER_CLASS end,
                    "Your own class's trainers only, or every class's (those you have from other characters of yours or from other players)."), npcToggle, On)
            end
        end

        Header("How they show", "Square markers, apart from your pins (diamonds) and the map's places (round). Click one for its actions: set a waypoint there, pin it, navigate to it or forget it.")
        Under(Check("npcMapReports", "reports", "Show NPCs others sent you",
            "NPCs another TwichUI user sent you that you haven't dealt with yourself, drawn dimmed and grey. Once you deal with one yourself it is yours like any other."), npcToggle, On)
        Under(Check("npcMapLabels", "labels", "Names under the markers",
            "Each NPC's name under its marker. Off, the name shows when you point at it."), npcToggle, On)
        local size = Proxy("npcMapIconSize", K.NUMBER, "Marker size", NP.DEFAULTS.iconSize,
            function() return NP.Get("iconSize") end, function(value) NP.Set("iconSize", math.floor(value + 0.5)) end)
        if size then reset[#reset + 1] = { setting = size, default = NP.DEFAULTS.iconSize } end
        Under(K.Slider(size, NP.LIMITS.iconSize[1], NP.LIMITS.iconSize[2], "In percent. The same size on screen at every zoom."), npcToggle, On)

        K.ResetButton("Reset what the map shows", reset, function() NP.Reset("show") NP.Reset("look") end,
            "Puts which kinds show, the class trainers choice, reports, names and the marker size back to the defaults. Your list and the switch are not changed.")
    end,
})

K.Page({
    key = "npcsList", name = "Vendors and trainers: your list", nav = "Your list and sharing", parent = "npcs", order = 76,
    description = "How many NPCs you know, sending your list to other TwichUI users, how lists sent to you are taken in, and removing what is in it.",
    keywords = "share send whisper party group guild receive accept import list reports others probe check forget clear remove",
    when = function() return R.NpcStore ~= nil and R.NpcShare ~= nil end,
    build = function()
        local NS, NP, NSH, NC = R.NpcStore, R.NpcPrefs, R.NpcShare, R.NpcCollect
        local Header, Under, Button, Proxy = K.Header, K.Under, K.Button, K.Proxy
        local reset = {}
        local Check = Checker(reset)
        local function Toggle() return npcToggle end

        Header("Your list", "Every NPC in it was either dealt with by you on one of your characters, or sent to you by another TwichUI user. It is the same for all your characters and is not part of a profile, a backup or a shared setup.")
        Under(K.Status("In your list", Counts, nil, "Yours: NPCs you dealt with. From others: what other TwichUI users sent you that you haven't dealt with yourself; those not sent again go after 120 days."), Toggle(), On)

        Header("Sharing", "Send your list to another TwichUI user, your group or your guild, over TwichUI's own hidden addon channel (no chat text). You are told how many NPCs go and asked first. Or let new finds go out one at a time as you make them (live sharing, below). Only NPCs travel: their names, places and what they offer, nothing about you.")
        local receive = Proxy("npcMapReceive", K.STRING, "Lists sent to you", NP.DEFAULTS.receive,
            function() return NP.Get("receive") end, function(value) NP.Set("receive", value) end)
        if receive then reset[#reset + 1] = { setting = receive, default = NP.DEFAULTS.receive } end
        Under(K.Dropdown(receive, function() return NP.RECEIVE end,
            "What happens when another TwichUI user sends you their list. Whatever you add is marked as from others until you deal with that NPC yourself, and never changes one you have seen."), Toggle(), On)
        Under(Check("npcMapSendReports", "sendReports", "Also send what others sent you",
            "Off, only NPCs you dealt with yourself are sent, so what you pass on is what you saw. On, what others sent you goes too (it arrives as reports either way)."), Toggle(), On)
        Under(Check("npcMapLiveGroup", "liveGroup", "Tell your group about new NPCs as you find them",
            "When you deal with an NPC for the first time (or it turns out to offer something new), a small message with just that NPC goes to your party or raid a few seconds later, so others' lists grow without long transfers. Only NPCs you saw yourself go; nothing about you. Each NPC is sent once per session, and at most a dozen messages a minute. On by default; no question is asked per NPC."), Toggle(), On)
        Under(Check("npcMapLiveGuild", "liveGuild", "Tell your guild about new NPCs as you find them",
            "The same, to your guild. Only guild members who have TwichUI and have not turned this off receive it. On by default."), Toggle(), On)
        Under(Check("npcMapLiveReceive", "liveReceive", "Take in NPCs your group and guild find",
            "NPCs your party, raid or guild pass on as they find them are added quietly to your list as reports from others (dimmed on the map until you deal with them yourself). Nothing is asked and nothing is printed; they never change an NPC you saw yourself. On by default. This is separate from \"Lists sent to you\", which is about whole lists."), Toggle(), On)
        Under(Button("Send to your group", "Send", function() NSH.Offer("party") end,
            "Everyone in your party or raid with TwichUI receives it; each of them chooses whether to add it. You are asked first."), Toggle(), On)
        Under(Button("Send to your guild", "Send", function() NSH.Offer("guild") end,
            "Every online guild member with TwichUI receives it; each of them chooses whether to add it. You are asked first."), Toggle(), On)
        Under(Button("Send to a player", "Choose...", function() NSH.AskName() end,
            "Asks for the character's name (your target's, if it is a player, is filled in). Only they receive it. You are asked first."), Toggle(), On)

        Header("Checking what the game reports", "For trying the feature in the game: what each NPC's window told TwichUI, printed to your own chat frame.")
        Button("Probe", function() return NC.Probing() and "Stop" or "Start" end, function() NC.Probe() end,
            "While it runs (this session only), each merchant, trainer or service window you open prints what the game said: the interaction, the NPC, your map and place, what the merchant sold and what kind of trainer it is. Nothing is sent and nothing of it is saved. Also /tui npcs probe.")

        Header("Remove", "Removing can't be undone. A removed NPC is noted again the next time you deal with it.")
        Button("NPCs others sent you", "Remove", function()
            local _, reported = NS.Counts()
            if reported == 0 then R.Print("nothing others sent you is in your list.") return end
            R.Interact.Confirm("TWICHUI_NPC_CLEAR_REPORTED", ("Remove the %d NPCs other TwichUI users sent you that you haven't dealt with yourself?\n\nThe ones you have seen stay, on every character."):format(reported),
                function() R.Print("removed %d NPCs others sent you.", NS.Clear("reported")) end, { accept = "Remove" })
        end, "Removes every NPC in your list that came from others and that you haven't dealt with yourself. Asks first.")
        Button("Your whole list", "Forget all", function()
            local own, reported = NS.Counts()
            if own + reported == 0 then R.Print("your vendors and trainers list is empty.") return end
            R.Interact.Confirm("TWICHUI_NPC_CLEAR_ALL", ("Forget all %d NPCs in your list (%d seen by you, %d from others)?\n\nThis is the list every character of yours shares. Your settings, map pins and everything else stay."):format(own + reported, own, reported),
                function() R.Print("forgot %d NPCs.", NS.Clear("all")) end, { accept = "Forget all" })
        end, "Empties your list of vendors, trainers and services, for every character. Asks first.")

        K.ResetButton("Reset sharing choices", reset, function() NP.Reset("sharing") end,
            "Puts how lists sent to you are taken in, whether you pass on what others sent you, and the live sharing choices back to the defaults. Your list is not changed.")
    end,
})
