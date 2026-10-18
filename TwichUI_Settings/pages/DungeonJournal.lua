-- TwichUI settings: Dungeon Journal (the Forever Dungeon Journal, its own addon, /fj): the icon on your data bar
-- that opens or closes it. The journal's look is on the Addon skins page.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "dungeonJournal", name = "Dungeon Journal", order = 91, group = "addons",
    description = "An icon on your data bar that opens or closes the Forever Dungeon Journal. The journal's own look is on the Addon skins page.",
    keywords = "dungeon journal fj fdj book data bar broker icon open close toggle",
    overview = {
        label = "Dungeon Journal", tip = "An icon on your data bar that opens or closes the Forever Dungeon Journal.",
        status = function() return K.OnOff(R:Enabled("dungeonJournalBroker")) end,
    },
    build = function()
        local Header, Toggle = K.Header, K.Toggle

        local installed = K.AddonState("ForeverDungeonJournal") ~= "missing"
        Header("Data bar icon", "Adds \"TwichUI Dungeon Journal\" to the list of your data bar addon (any that shows LibDataBroker launchers, such as EllesmereUI's Broker Plugin block). A click opens the Forever Dungeon Journal, or closes it when it is open. The icon has no text; hover it to see whether the journal is open.")
        local label = installed and "Dungeon Journal icon on my data bar" or ("Dungeon Journal icon on my data bar  " .. R.GREY .. "(not installed)|r")
        local row = Toggle("dungeonJournalBroker", label,
            "Opens or closes the Forever Dungeon Journal (/fj) from your data bar. It is the journal's own window, opened the way its minimap button opens it; nothing else of the journal changes.\n\nWithout a data bar addon there is nowhere for it to show. Turning it off leaves the icon on your data bar until a reload, where clicks then do nothing.")
        if row then
            K.DataBarNote(row, function() return R:Enabled("dungeonJournalBroker") end)
            if not installed then
                row:AddModifyPredicate(function() return false end)
                row.why = "Install the Forever Dungeon Journal to use this icon."
            end
        end
    end,
})
