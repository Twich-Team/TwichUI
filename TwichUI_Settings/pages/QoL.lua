-- TwichUI settings: Quality of life (qol/: summons, resurrection, battleground release, duels, Easy Fishing,
-- Quick Keybind, and the game's waypoint on RestedXP's destination). Everything here is off until turned on.

local R = TwichUI
local K = R.SettingsKit

local FISHING_STATUS = {
    off = { "Off" },
    unsupported = { "Not available", "This client doesn't have the key binding functions Easy Fishing needs. Nothing was changed." },
    ["not-learned"] = { "Fishing isn't learned", "Learn Fishing from a trainer; the key then casts it. Nothing else is needed." },
    ["no-key"] = { "No key chosen", "Choose a key below, or in Key Bindings > TwichUI." },
    ["needs-targeting"] = { "Can cast, can't reel yet", "The game's interaction targeting is off, so it can't pick your bobber. Allow the adjustment below, or turn it on yourself." },
    ready = { "Ready" },
}

local GUIDE_STATUS = {
    off = { "Off" },
    ["restedxp-missing"] = { "RestedXP not installed", "Install RestedXP Guides to use this." },
    ["restedxp-disabled"] = { "RestedXP turned off", "RestedXP Guides is turned off in your AddOns list." },
    waiting = { "Waiting for RestedXP", "RestedXP hasn't finished loading yet." },
    unsupported = { "This RestedXP isn't supported", "This version of RestedXP doesn't have what this needs (its arrow and map updates). Nothing was changed." },
    ["no-guide"] = { "No guide", "RestedXP has no guide showing." },
    ["no-destination"] = { "No destination", "RestedXP's arrow isn't leading anywhere right now (for example, in an instance)." },
    route = { "No single destination", "This step only has a route or an area, so there is nothing to mark." },
    ["map-refused"] = { "Can't mark this map", "The game doesn't allow a waypoint on the map this destination is on." },
    yours = { "Your waypoint is in use", "Your own waypoint is left as it is. Clear it to let this mark the next destination." },
    cleared = { "Waiting for the next destination", "Its waypoint was cleared or replaced, so it waits for RestedXP's next destination." },
    shown = { "Showing the destination" },
}

K.Page({
    key = "qol", name = "Quality of life", order = 30, group = "everyday",
    description = "Small opt-in conveniences. Each is off until you turn it on, and each does only the one thing it says.",
    keywords = "summon resurrect res rez battleground release spirit duel decline fishing fish cast reel bobber keybind quick keybind waypoint restedxp leatrix",
    when = function() return R.QoL ~= nil end,
    overview = {
        label = "Quality of life", tip = "Small opt-in conveniences: accepting summons and resurrection, releasing in battlegrounds, declining duels, one key for fishing, a Quick Keybind button in the Game Menu, and the game's waypoint on RestedXP's destination.",
        status = function()
            local on = (R:Enabled("qolSummons") and 1 or 0) + (R:Enabled("qolResurrect") and 1 or 0)
                + (R:Enabled("qolReleasePvP") and 1 or 0) + (R:Enabled("qolDuels") and 1 or 0)
                + (R:Enabled("qolQuickKeybind") and 1 or 0) + (R:Enabled("qolEasyFishing") and 1 or 0)
            local total = 6
            if R.QoLGuideWaypoint then
                total = total + 1
                if R:Enabled("qolGuideWaypoint") then on = on + 1 end
            end
            return K.OnOff(on > 0, ("%d of %d on"):format(on, total), "Off")
        end,
    },
    build = function()
        local Header, Toggle, Choice, Under, Button = K.Header, K.Toggle, K.Choice, K.Under, K.Button
        local STRING, NUMBER = K.STRING, K.NUMBER
        local Q = R.QoL
        -- Each row's tooltip ends with a note when Leatrix Plus has the same option on, read when it is shown.
        local function QolToggle(key, label, what)
            local row = Toggle(key, label, what)
            if row and Q.LEATRIX[key] then
                row.data.tooltip = function()
                    return what .. (Q.LeatrixOverlap(key)
                        and "\n\nLeatrix Plus also has this turned on. Both do it, which does no harm, but you only need one." or "")
                end
            end
            return row
        end
        local function QolChoice(variable, key, label, tooltip, options)
            local varType = (key == "summonsFrom" or key == "duelsFrom") and STRING or NUMBER
            return Choice(variable, label, tooltip, varType, Q.DEFAULTS[key],
                function() return Q.Get(key) end, function(value) Q.Set(key, value) end, options)
        end
        local function Seconds(n) return n == 0 and "Don't wait" or (n == 1 and "1 second" or ("%d seconds"):format(n)) end
        local function Waits(key)
            local list = {}
            for i, n in ipairs(Q.CHOICES[key]) do list[i] = { n, Seconds(n) } end
            return list
        end

        Header("Summons and resurrection", "Small conveniences for when another player offers to move or raise you. Each is off until you turn it on, and each does only the one thing it says.")
        local summons = QolToggle("qolSummons", "Accept summons",
            "Accepts a summon from another player for you after a short wait, so you arrive without clicking. The game's own pop-up stays up during the wait: choose Decline there to stay where you are. Only an ordinary summon is accepted; a scenario summon, or one that skips a starting area's introduction, is always left to you. Nothing is accepted in combat or when the game won't let you teleport, and there is no second try: the pop-up stays for you to answer.\n\nYou arrive wherever the summoner stands, so choose who you trust below.")
        local function SummonsOn() return R:Enabled("qolSummons") end
        Under(QolChoice("qolSummonsFrom", "summonsFrom", "Accept summons from",
            "Who can summon you without asking. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded. A summon with no name the game will give is never accepted, except from Anyone.",
            {
                { "known", "Friends, guild and group members" },
                { "group", "Group members only", "People in your party or raid." },
                { "anyone", "Anyone", "Any player's summon, strangers included." },
            }), summons, SummonsOn)
        Under(QolChoice("qolSummonsWait", "summonsWait", "Wait before accepting a summon",
            "How long the summon's pop-up stays up before it is accepted, so you can decline it.", Waits("summonsWait")), summons, SummonsOn)

        local resurrect = QolToggle("qolResurrect", "Accept resurrection",
            "Accepts a resurrection another player offers you, so you get up without clicking the pop-up. The game's own waiting time is kept: if it hasn't passed, the offer is accepted when it ends, if it still stands. An offer that carries resurrection sickness is left for you to decide. Soulstones and other self-resurrection, spirit healers and corpse runs aren't touched, and it never releases your spirit. Not used on Hardcore rules.\n\nTurn it off if you'd rather choose who raises you.")
        local function ResurrectOn() return R:Enabled("qolResurrect") end
        Under(QolToggle("qolResurrectCombat", "Also accept combat resurrections",
            "Also accepts a resurrection from someone who is in combat. The game doesn't mark combat resurrections, so this is judged by the person offering being in your group and in combat; someone outside your group can't be seen either way and counts as an ordinary offer. Off: those offers wait for you to accept them yourself. You rise with little health, into whatever fight is still going."), resurrect, ResurrectOn)

        Header("Battlegrounds", "Dying in a battleground, where the next step is nearly always to release.")
        local release = QolToggle("qolReleasePvP", "Release in battlegrounds",
            "After you die in a battleground, your spirit is released for you after a short wait. Battlegrounds only: never in dungeons, raids, arenas or the open world, where nothing here can tell that releasing is wanted. Nothing is released while you have a soulstone or other self-resurrection on offer, while someone's resurrection is on offer, or when the game says you can't release. Hold Shift as the wait ends to keep your body. Not used on Hardcore rules.\n\nThere is no second try: if it doesn't release, the game's own Release button is still there.")
        Under(QolChoice("qolReleaseWait", "releaseWait", "Wait before releasing",
            "How long after you die before your spirit is released. A resurrection offered in that time cancels the release, and holding Shift as it ends keeps your body.", Waits("releaseWait")),
            release, function() return R:Enabled("qolReleasePvP") end)

        Header("Duels", "Duel requests from other players.")
        local duels = QolToggle("qolDuels", "Decline duel requests",
            "Declines an ordinary duel request as soon as it arrives, unless it's from someone you allow below. The challenger sees it declined, as if you had pressed Decline; TwichUI says nothing in chat and shows no message. If the game doesn't give the challenger's name, the request is declined. Off: duels work as the game does.")
        local function DuelsOn() return R:Enabled("qolDuels") end
        Under(QolChoice("qolDuelsFrom", "duelsFrom", "Still allow duels from",
            "Whose duel requests you still get to answer yourself. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded.",
            {
                { "known", "Friends, guild and group members" },
                { "friendsGuild", "Friends and guild members" },
                { "friends", "Friends only" },
                { "nobody", "Nobody", "Every duel request is declined." },
            }), duels, DuelsOn)
        Under(QolToggle("qolDuelsToDeath", "Also decline duels to the death",
            "Also declines a duel to the death, which Forever treats as a separate, lethal kind of duel (accepting one asks you to type a confirmation). The same exceptions apply. Off: duels to the death still reach you."), duels, DuelsOn)

        local EF = R.QoLEasyFishing
        if EF then
            Header("Fishing", "One key for casting your line and reeling in the catch. Every cast and every reel is your own key press.")
            local fishBase = "Use the same key to cast your line and reel in a catch.\n\nWith no line out, the key casts Fishing. While your line is out, the same key does the game's Interact action on the world object it has picked, which should be your bobber. TwichUI never casts, reels or watches for a bite for you: press when the bobber dips. Pressing early pulls the line in empty, as clicking the bobber early does.\n\nIf the game has picked something else (a chest beside you, say), that is what the key reaches; when it has picked a person or an NPC, the key does nothing, and it never casts over a line that is out. Needs Fishing learned and a fishing pole, like the spell itself. Key presses can't change in combat; there is no default key.\n\nBetterFishing, if you have it, also puts keys on fishing: give the two different keys."
            local fishing = QolToggle("qolEasyFishing", "Easy Fishing", fishBase)
            if fishing and fishing.GetTooltip ~= nil then
                -- read when the tooltip is shown, so it is never stale
                fishing.GetTooltip = function()
                    local code = EF.Status()
                    local text = FISHING_STATUS[code] or { code }
                    local color = (code == "ready" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    return fishBase .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
            local function FishingOn() return R:Enabled("qolEasyFishing") end
            local function CanBind() return FishingOn() and not InCombatLockdown() end
            local function CantBind() return FishingOn() and "Key bindings can't be changed in combat." or "Needs \"Easy Fishing\" turned on." end

            local function KeyText()
                local keys = EF.Keys()
                if #keys == 0 then return "not set" end
                local parts = {}
                for i, key in ipairs(keys) do parts[i] = EF.KeyText(key) end
                return table.concat(parts, " or ")
            end

            -- Applies a key the player pressed, asking first when it is in use. Nothing is taken silently.
            local function Apply(chord)
                local result, other = EF.Assign(chord)
                if result == "conflict" then
                    R.Interact.Confirm("TWICHUI_EASYFISHING_KEY",
                        ("Use %s for Easy Fishing?\n\nThat key is already used for \"%s\". If you continue, that action loses this key and Easy Fishing takes it. Its other key, if it has one, and every other binding stay as they are. You can give it a key again in Key Bindings."):format(EF.KeyText(chord), tostring(other)),
                        function()
                            local again = EF.Assign(chord, true)
                            if again ~= "ok" and again ~= "same" then R.Print("that key couldn't be given to Easy Fishing. Nothing was changed.") end
                            K.RefreshOverview()
                        end, { accept = "Use this key", combat = true })
                elseif result == "combat" then
                    R.Print("key bindings can't change in combat. Nothing was changed.")
                elseif result == "ok" or result == "same" then
                    K.RefreshOverview()
                else
                    R.Print("that key couldn't be given to Easy Fishing. Nothing was changed.")
                end
            end

            -- Listens for one key press while the row is on screen; Escape or leaving the page cancels. The
            -- frame is made when the row is, and does nothing until the button is pressed.
            local listener
            local function Capture(parent)
                local c = CreateFrame("Frame", nil, parent)
                c.listening = false
                local function Stop() c.listening = false; c:EnableKeyboard(false); c:Hide(); K.RefreshOverview() end
                c.Stop = Stop
                c:SetScript("OnKeyDown", function(_, input)
                    if not c.listening then return end
                    local key = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
                    if key == "ESCAPE" then Stop() return end
                    if IsKeyPressIgnoredForBinding then
                        if IsKeyPressIgnoredForBinding(key) then return end
                    elseif key == "UNKNOWN" or key:find("^[LR]?ALT$") or key:find("^[LR]?CTRL$") or key:find("^[LR]?SHIFT$") then
                        return
                    end
                    local chord
                    if CreateKeyChordStringUsingMetaKeyState then
                        chord = CreateKeyChordStringUsingMetaKeyState(key)
                    else
                        chord = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
                    end
                    Stop()
                    Apply(chord)
                end)
                c:SetScript("OnHide", function() if c.listening then Stop() end end)
                return c
            end

            local keyRow = Button("Key", function()
                if listener and listener.listening then return "Press a key..." end
                return "Set key"
            end, function()
                if not (listener and CanBind()) then return end
                if listener.listening then listener.Stop() return end
                listener.listening = true
                listener:Show()
                listener:EnableKeyboard(true)
                K.RefreshOverview()
            end, "Press this, then the key you want for Easy Fishing; Escape cancels. A key that is already used asks you first, naming what uses it, and nothing is taken without that. The same entry is in Key Bindings > TwichUI.\n\nShown after the name: the key now. No key is set by default.")
            if keyRow then
                keyRow.extra = function(frame) listener = Capture(frame) return listener end
                keyRow.GetName = function()
                    local code = EF.Status()
                    local note = (code == "not-learned" and "  Fishing isn't learned") or (code == "needs-targeting" and "  can't reel yet") or ""
                    local others = EF.OtherFishingKeys()
                    for _, mine in ipairs(EF.Keys()) do
                        for _, theirs in ipairs(others) do
                            if mine == theirs then note = "  also BetterFishing's key" end
                        end
                    end
                    return "Key: " .. KeyText() .. note
                end
                Under(keyRow, fishing, CanBind, CantBind)
            end
            local clearRow = Button("Clear the key", "Clear", function()
                if EF.ClearKeys() == "combat" then R.Print("key bindings can't change in combat. Nothing was changed.") end
                K.RefreshOverview()
            end, "Takes Easy Fishing's key off it. Only that key is removed; no other binding is touched. With no key, nothing is cast or reeled.")
            Under(clearRow, fishing, function() return CanBind() and #EF.Keys() > 0 end,
                function() if not CanBind() then return CantBind() end return "No key is set." end)

            local function TargetingNow()
                local on = EF.InteractionOn()
                if on == nil then return "can't be read" end
                return on and "on" or "off"
            end
            local targetTip = "Reeling needs the game's interaction targeting to pick your bobber, and a range and arc wide enough to include it. This lets Easy Fishing set those game settings only while a line is out and put them back afterwards. It asks first and changes nothing until you allow it. Off, nothing of the game's is touched."
            local targetRow = Button("Adjust interaction targeting while fishing", function()
                return EF.TargetingAllowed() and "Stop adjusting" or "Allow"
            end, function()
                if EF.TargetingAllowed() then
                    EF.SetTargeting(false)
                    K.RefreshOverview()
                    return
                end
                local lines = {}
                for _, item in ipairs(EF.TARGETING) do lines[#lines + 1] = ("%s to %s"):format(item.name, item.value) end
                R.Interact.Confirm("TWICHUI_EASYFISHING_TARGETING",
                    "Let Easy Fishing adjust the game's interaction targeting while you fish?\n\nWhile a fishing line is out it sets " .. table.concat(lines, ", ") ..
                    ", so the game can pick your bobber when you press the key. When the line is gone, when you turn Easy Fishing off and when you log out, each one is put back to what it was, unless you changed it yourself in the meantime. While the line is out, the game's interact icons and its own Interact key reach further. Nothing else is changed, and without this the key can still cast but may not be able to reel.",
                    function() EF.SetTargeting(true); K.RefreshOverview() end, { accept = "Allow", combat = true })
            end, function()
                return targetTip .. "\n\nInteraction targeting is " .. TargetingNow() .. " in the game right now."
            end)
            if targetRow then
                Under(targetRow, fishing, function() return CanBind() end, CantBind)
            end
        end

        Header("Game Menu", "A shortcut in the Escape menu.")
        QolToggle("qolQuickKeybind", "Quick Keybind button",
            "Adds a Quick Keybind button to the Game Menu, below Macros. It opens the game's own Quick Keybind Mode, the one in Settings > Keybindings, with its usual instructions and Okay and Cancel buttons; entering it changes no bindings. Like the game's own, it can't be opened in combat, and the button is dimmed until combat ends.")

        local GW = R.QoLGuideWaypoint
        if GW then
            Header("RestedXP guides", "Uses the game's own waypoint for where RestedXP is leading you. RestedXP's arrow and map pins are unchanged.")
            local gwBase = "Puts the game's waypoint (its map pin and the marker in the world) on the place RestedXP's arrow is leading you to, and moves it on when RestedXP does. Where RestedXP only routes you along a path, it marks where that path ends; a kill area with no single destination gets none.\n\nA waypoint you placed yourself is never moved or cleared: while yours is there, this waits. If you clear or replace its waypoint, it leaves it so until the next destination. Each new destination is made the tracked one, which can take the in-world marker from a quest you were tracking. Turning this off clears its own waypoint."
            local guideToggle = QolToggle("qolGuideWaypoint", "Mark RestedXP's destination", gwBase)
            if guideToggle and guideToggle.GetTooltip ~= nil then
                -- read when the tooltip is shown, so it is never stale
                guideToggle.GetTooltip = function()
                    local code = GW.Status()
                    local text = GUIDE_STATUS[code] or { code }
                    local color = (code == "shown" and R.GREEN) or (code == "off" and R.GREY) or R.GOLD
                    return gwBase .. "\n\nStatus: " .. color .. text[1] .. "|r" .. (text[2] and ("\n" .. text[2]) or "")
                end
            end
        end
    end,
})
