-- TwichUI settings: the Workshop (the TwichUI_Workshop addon: browse your professions' recipes, queue crafts, see the combined
-- materials still needed). The Workshop is a load-on-demand addon: this page works before it has ever loaded, through the
-- launcher in the core (WorkshopLauncher.lua), and opening the Workshop is what loads it. It has no settings of its own yet.

local R = TwichUI
local K = R.SettingsKit

local function Launcher() return R.WorkshopLauncher end
local function Loaded() return Launcher() and Launcher().Loaded() end
local function Shown() return Loaded() and R.Workshop.Window and R.Workshop.Window.IsShown() end

K.Page({
    key = "workshop", icon = "guide", name = "Workshop", order = 46, group = "everyday",
    description = "Your professions' recipes in one window: queue crafts and see the materials you still need.",
    keywords = "workshop profession professions recipe recipes craft crafting queue make materials reagents bags still needed open recipe",
    overview = {
        label = "Workshop", tip = "Queue crafts and see the materials you still need.",
        when = function() return Launcher() ~= nil end,
        status = function() return Shown() and "Open" or (Loaded() and "Closed" or "Not opened yet") end,
    },
    when = function() return Launcher() ~= nil end,
    build = function()
        K.Header("Workshop", "Pick recipes from your professions, set how many to make, and see the materials you still need. It reads your own recipes when you have a profession window open, and it never crafts anything for you.")
        K.Button("Workshop window", function() return Shown() and "Close" or "Open" end,
            function()
                Launcher().Toggle()
                K.RefreshOverview()
            end,
            "Opens or closes the Workshop. You can also type /tui workshop or use the TwichUI menu on your data bar. It is loaded the first time you open it, not at login, and not during combat.")
        K.Status("Loaded", function() return Loaded() and "Yes" or "Not yet" end,
            function() return Loaded() and "The Workshop is ready." or "It loads the first time you open it." end,
            "The Workshop is a separate part of TwichUI that waits until you ask for it, so it costs nothing until then.", function() return Loaded() and "ok" or "quiet" end)
        K.Header("What it does", "Recipes come from a profession window of your own: open a profession and they appear. Your queue is saved for each character and stays when you switch professions. Materials count what is in your bags only; the bank, mail and other characters are not counted. Nothing is made, bought or sent for you.")
    end,
})
