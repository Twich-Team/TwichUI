-- TwichUI settings: Quality of life (qol/: summons, resurrection, battleground release, duels,
-- Quick Keybind). Everything here is off until turned on. The game's waypoint on RestedXP's destination is
-- on the RestedXP page. Each convenience is a feature card (K.Card) with a sample preview (previews/QoL.lua);
-- the settings, their names and their tooltips are the ones this page has always had.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "qol", icon = "qualityOfLife", name = "Quality of life", order = 30, group = "everyday",
    description = "Small opt-in conveniences. Each is off until you turn it on, and each does only the one thing it says.",
    keywords = "summon resurrect res rez battleground release spirit duel decline keybind quick keybind leatrix",
    when = function() return R.QoL ~= nil end,
    overview = {
        label = "Quality of life", tip = "Small opt-in conveniences: accepting summons and resurrection, releasing in battlegrounds, declining duels and a Quick Keybind button in the Game Menu.",
        status = function()
            local on = (R:Enabled("qolSummons") and 1 or 0) + (R:Enabled("qolResurrect") and 1 or 0)
                + (R:Enabled("qolReleasePvP") and 1 or 0) + (R:Enabled("qolDuels") and 1 or 0)
                + (R:Enabled("qolQuickKeybind") and 1 or 0)
            local total = 5
            return K.OnOff(on > 0, ("%d of %d on"):format(on, total), "Off")
        end,
    },
    build = function()
        local Toggle, Choice, Under = K.Toggle, K.Choice, K.Under
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

        -- one card per convenience (K.Card): what it does, its switch, its rules in a line, what to know first
        local function Value(row) return row and K.ValueText(row.data.setting) or "" end
        local function WaitWords(n) return n == 0 and "no wait" or ("waits " .. Seconds(n):lower()) end
        local function Overlap(row, key)
            return K.Note(row, function()
                if Q.LeatrixOverlap(key) then return "Leatrix Plus also has this turned on. Both do it, which does no harm, but you only need one." end
            end)
        end
        local DOT = "  \194\183  "

        local summonsFrom
        K.Card({
            title = "Accept summons",
            icon = "summons",
            what = "Accepts a summon from the people you choose after a short wait, so you arrive without clicking.",
            summary = function() return Value(summonsFrom) .. DOT .. WaitWords(Q.Get("summonsWait")) end,
            consequence = "You arrive wherever the summoner stands. The game's pop-up stays up during the wait, so you can still decline.",
            preview = "qol.summons",
            details = {
                { "When does it apply?", "To an ordinary summon (a warlock's ritual, a meeting stone) from someone your rule allows. A scenario summon, or one that skips a starting area's introduction, is always left to you." },
                { "When doesn't it?", "Never in combat or when the game won't let you teleport. There is no second try: if it can't accept, the pop-up stays for you to answer." },
            },
        })
        local summons = Overlap(QolToggle("qolSummons", "Accept summons",
            "Accepts a summon from another player for you after a short wait, so you arrive without clicking. The game's own pop-up stays up during the wait: choose Decline there to stay where you are. Only an ordinary summon is accepted; a scenario summon, or one that skips a starting area's introduction, is always left to you. Nothing is accepted in combat or when the game won't let you teleport, and there is no second try: the pop-up stays for you to answer.\n\nYou arrive wherever the summoner stands, so choose who you trust below."), "qolSummons")
        local function SummonsOn() return R:Enabled("qolSummons") end
        local SUMMONS_WHY = "Turn on \"Accept summons\" to choose who and how long."
        summonsFrom = Under(QolChoice("qolSummonsFrom", "summonsFrom", "Accept summons from",
            "Who can summon you without asking. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded. A summon with no name the game will give is never accepted, except from Anyone.",
            {
                { "known", "Friends, guild and group members" },
                { "group", "Group members only", "People in your party or raid." },
                { "anyone", "Anyone", "Any player's summon, strangers included." },
            }), summons, SummonsOn, SUMMONS_WHY)
        Under(QolChoice("qolSummonsWait", "summonsWait", "Wait before accepting a summon",
            "How long the summon's pop-up stays up before it is accepted, so you can decline it.", Waits("summonsWait")), summons, SummonsOn, SUMMONS_WHY)

        -- the combat-resurrection policy stays in view (inline): it is the one choice that decides whether you may
        -- rise into a fight, so it is never tucked behind "Adjust rules"
        K.Card({
            title = "Accept resurrection",
            icon = "resurrection",
            what = "Accepts a resurrection another player offers, so you get up without clicking the pop-up.",
            summary = function()
                return "Out of combat: accepted" .. DOT .. "In combat: " .. (R:Enabled("qolResurrectCombat") and "accepted too" or "waits for you")
            end,
            consequence = "An offer that carries resurrection sickness is always left to you, and it never releases your spirit.",
            preview = "qol.resurrect",
            inline = true,
            details = {
                { "When does it apply?", "To a resurrection another player offers. The game's own waiting time is kept: if it hasn't passed, the offer is accepted when it ends, if it still stands." },
                { "What isn't touched?", "Soulstones and other self-resurrection, spirit healers and corpse runs. Not used on Hardcore rules." },
            },
        })
        local resurrect = Overlap(QolToggle("qolResurrect", "Accept resurrection",
            "Accepts a resurrection another player offers you, so you get up without clicking the pop-up. The game's own waiting time is kept: if it hasn't passed, the offer is accepted when it ends, if it still stands. An offer that carries resurrection sickness is left for you to decide. Soulstones and other self-resurrection, spirit healers and corpse runs aren't touched, and it never releases your spirit. Not used on Hardcore rules.\n\nTurn it off if you'd rather choose who raises you."), "qolResurrect")
        local function ResurrectOn() return R:Enabled("qolResurrect") end
        Under(QolToggle("qolResurrectCombat", "Also accept combat resurrections",
            "Also accepts a resurrection from someone who is in combat. The game doesn't mark combat resurrections, so this is judged by the person offering being in your group and in combat; someone outside your group can't be seen either way and counts as an ordinary offer. Off: those offers wait for you to accept them yourself. You rise with little health, into whatever fight is still going."),
            resurrect, ResurrectOn, "Turn on \"Accept resurrection\" to choose this.")

        K.Card({
            title = "Release in battlegrounds",
            icon = "releaseSpirit",
            what = "Releases your spirit for you after you die in a battleground.",
            summary = function()
                local n = Q.Get("releaseWait")
                return "Battlegrounds only" .. DOT .. (n == 0 and "releases at once" or ("releases " .. Seconds(n):lower() .. " after you die"))
            end,
            consequence = "Never in dungeons, raids, arenas or the open world. Hold Shift as the wait ends to keep your body.",
            preview = "qol.release",
            details = {
                { "When doesn't it release?", "While you have a soulstone or other self-resurrection on offer, while someone's resurrection is on offer, or when the game says you can't release. Not used on Hardcore rules." },
                { "What if it doesn't?", "There is no second try: the game's own Release button is still there." },
            },
        })
        local release = Overlap(QolToggle("qolReleasePvP", "Release in battlegrounds",
            "After you die in a battleground, your spirit is released for you after a short wait. Battlegrounds only: never in dungeons, raids, arenas or the open world, where nothing here can tell that releasing is wanted. Nothing is released while you have a soulstone or other self-resurrection on offer, while someone's resurrection is on offer, or when the game says you can't release. Hold Shift as the wait ends to keep your body. Not used on Hardcore rules.\n\nThere is no second try: if it doesn't release, the game's own Release button is still there."), "qolReleasePvP")
        Under(QolChoice("qolReleaseWait", "releaseWait", "Wait before releasing",
            "How long after you die before your spirit is released. A resurrection offered in that time cancels the release, and holding Shift as it ends keeps your body.", Waits("releaseWait")),
            release, function() return R:Enabled("qolReleasePvP") end, "Turn on \"Release in battlegrounds\" to choose the wait.")

        local duelsFrom
        K.Card({
            title = "Decline duel requests",
            icon = "declineDuels",
            what = "Declines duel requests as soon as they arrive, except from the people you still allow.",
            summary = function()
                return "Still allowed: " .. Value(duelsFrom):lower() .. DOT .. "Duels to the death: "
                    .. (R:Enabled("qolDuelsToDeath") and "declined too" or "still reach you")
            end,
            consequence = "The challenger sees it declined, as if you had pressed Decline. TwichUI says nothing in chat and shows no message.",
            preview = "qol.duels",
            details = {
                { "What if the game gives no name?", "Then the exceptions can't be checked, so the request is declined." },
            },
        })
        local duels = Overlap(QolToggle("qolDuels", "Decline duel requests",
            "Declines an ordinary duel request as soon as it arrives, unless it's from someone you allow below. The challenger sees it declined, as if you had pressed Decline; TwichUI says nothing in chat and shows no message. If the game doesn't give the challenger's name, the request is declined. Off: duels work as the game does."), "qolDuels")
        local function DuelsOn() return R:Enabled("qolDuels") end
        local DUELS_WHY = "Turn on \"Decline duel requests\" to choose exceptions."
        duelsFrom = Under(QolChoice("qolDuelsFrom", "duelsFrom", "Still allow duels from",
            "Whose duel requests you still get to answer yourself. Friends are your character friends and the WoW characters of Battle.net friends; guild members are read from the guild roster the game has loaded.",
            {
                { "known", "Friends, guild and group members" },
                { "friendsGuild", "Friends and guild members" },
                { "friends", "Friends only" },
                { "nobody", "Nobody", "Every duel request is declined." },
            }), duels, DuelsOn, DUELS_WHY)
        Under(QolToggle("qolDuelsToDeath", "Also decline duels to the death",
            "Also declines a duel to the death, which Forever treats as a separate, lethal kind of duel (accepting one asks you to type a confirmation). The same exceptions apply. Off: duels to the death still reach you."), duels, DuelsOn, DUELS_WHY)

        K.Card({
            title = "Quick Keybind button",
            icon = "quickKeybind",
            what = "Adds a Quick Keybind button to the Game Menu, below Macros.",
            consequence = "It opens the game's own Quick Keybind Mode, and entering it changes no bindings. Like the game's own, it can't be opened in combat.",
            preview = "qol.quickKeybind",
        })
        QolToggle("qolQuickKeybind", "Quick Keybind button",
            "Adds a Quick Keybind button to the Game Menu, below Macros. It opens the game's own Quick Keybind Mode, the one in Settings > Keybindings, with its usual instructions and Okay and Cancel buttons; entering it changes no bindings. Like the game's own, it can't be opened in combat, and the button is dimmed until combat ends.")
    end,
})
