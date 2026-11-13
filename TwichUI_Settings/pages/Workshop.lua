-- TwichUI settings: the Workshop (the TwichUI_Workshop addon: browse your professions' recipes, queue crafts, see the combined
-- materials still needed, price scan and crafting profit). The Workshop is a load-on-demand addon: this page works before it has ever loaded, through the
-- launcher in the core (WorkshopLauncher.lua), and opening the Workshop is what loads it. Its "What's it worth?" tooltip layout is designed here (WorkshopWorth.lua).

local R = TwichUI
local K = R.SettingsKit

local function Launcher() return R.WorkshopLauncher end
local function Loaded() return Launcher() and Launcher().Loaded() end
local function Shown() return Loaded() and R.Workshop.Window and R.Workshop.Window.IsShown() end

K.Page({
    key = "workshop", icon = "guide", name = "Workshop", order = 46, group = "everyday",
    description = "Your professions' recipes in one window: queue crafts and see the materials you still need.",
    keywords = "workshop profession professions recipe recipes craft crafting queue make materials reagents bags still needed open recipe opportunities profit prices scan auction shopping list vendor buy make subcraft spending",
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
        K.Toggle("workshopAutoScan", "Update prices automatically when I open the Auction House",
            "Reads the Auction House at most once an hour. Nothing is bought or posted.")
        K.Status("Update method", function() return R.WorkshopAuto and R.WorkshopAuto.Capability() == "supported" and "Automatic" or "One click" end,
            function()
                if R.WorkshopAuto and R.WorkshopAuto.Capability() == "supported" then
                    return "When an update is due, it starts as you open the Auction House. Stop ends it and saves nothing."
                end
                return "When an update is due, an Update prices button appears on the Auction House window. Starting it by itself has not been confirmed in this game version yet, so it never starts without your click."
            end,
            "The game decides whether an addon may start a whole Auction House read by itself. Until that is confirmed, TwichUI asks for one click and never tries on its own.", function() return "quiet" end)
        K.Header("What it does", "Recipes come from a profession window of your own: open a profession with the Workshop open and they appear, and they are remembered for that character, so you don't have to open them all again after a reload; opening one again updates it. Your queue is saved for each character and stays when you switch professions. Materials count what is in your bags, plus what the Workshop saw in your bank the last time you opened it with the Workshop loaded (and your guild bank, if you turn that on in the window); mail and other characters are not counted. Nothing is made, bought or sent for you.")
        K.Header("Shopping", "The Shopping view lists each material the queue still needs once, with a suggested source: a vendor, the auction house, or making it from its own materials. It compares only prices TwichUI has seen (your last scan, and what vendors charged when you had their window open with the Workshop open), says plainly when a price is missing or an estimate, and never buys, crafts or posts anything for you.")
        K.Header("Opportunities", "At the auction house, press Scan prices in the Opportunities view to see what your known crafts cost to make and might sell for. The scan only reads the listings, and only when you press the button; it never buys, bids or posts. Prices are the cheapest listings seen, not sales, and are saved for the next visit.")
        K.Header("What's it worth?", "Hover an item in your bags or bank (once the Workshop has been loaded this session) to see what a vendor pays, the cheapest auction listing from your last scan, and a suggestion. Choose and order its lines below. It is advice only and never asks the auction house anything. Disenchanting isn't estimated yet (there is no outcome data), and the auction figure says \"before fees\" until the auction house's cut is confirmed.")
    end,
    host = function() return R.WorkshopWorthDesigner.Frame() end, hostAfter = "What's it worth?", hostHeight = function() return R.WorkshopWorthDesigner.Height() end,
})
