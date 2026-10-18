-- TwichUI settings: Quality of life (qol/: summons, resurrection, battleground release, duels,
-- Quick Keybind). Everything here is off until turned on. The game's waypoint on RestedXP's destination is
-- on the RestedXP page.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "qol", name = "Quality of life", order = 30, group = "everyday",
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

        Header("Game Menu", "A shortcut in the Escape menu.")
        QolToggle("qolQuickKeybind", "Quick Keybind button",
            "Adds a Quick Keybind button to the Game Menu, below Macros. It opens the game's own Quick Keybind Mode, the one in Settings > Keybindings, with its usual instructions and Okay and Cancel buttons; entering it changes no bindings. Like the game's own, it can't be opened in combat, and the button is dimmed until combat ends.")
    end,
})
