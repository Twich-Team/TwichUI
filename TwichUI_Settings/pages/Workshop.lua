-- Workshop configuration in the existing settings shell. Describing the page
-- never loads the Workshop or reads its separate market database.
local R = TwichUI
local K = R.SettingsKit
local function Launcher() return R.WorkshopLauncher end
local function Enabled() local l = Launcher(); return l and l.Enabled and l.Enabled() end
local function Loaded() return Enabled() and Launcher().Loaded() end
local function Shown() return Loaded() and R.Workshop.Window and R.Workshop.Window.IsShown() end
local function State(key)
    local l = Launcher()
    if l and l.SettingsState then return l.SettingsState()[key] end
    return key == "notices"
end
local function Option(key, variable, label, tip, default)
    local row = K.ProxyToggle(variable, label, tip, default, function() return State(key) end,
        function(on) local l = Launcher(); if l and l.SetOption then l.SetOption(key, on) end end)
    row:AddModifyPredicate(Loaded)
    row.why = "Enable Workshop — Experimental, then load its options. No window or scan will open."
end
local function Choice(key, variable, label, default, choices, tip)
    local setting = K.Proxy(variable, "string", label, default,
        function() return State(key) or default end,
        function(value) local l = Launcher(); if l and l.SetChoice then l.SetChoice(key, value) end end)
    local row = K.Dropdown(setting, function() return choices end, tip)
    row:AddModifyPredicate(Loaded)
    row.why = "Enable Workshop — Experimental, then load its options. No window or scan will open."
end
local function LoadOptions()
    local l = Launcher()
    if l then
        local ok, why = l.Load()
        if not ok then R.Print("workshop: " .. l.Explain(why)) end
    end
    K.RefreshOverview()
end
local info, infoAt
local function Info()
    local w = Loaded() and R.Workshop
    if not (w and w.Market) then return nil end
    local now = GetTime()
    if not infoAt or now - infoAt > 0.1 then info, infoAt = w.Market.Info(), now end
    return info
end
local function Value(key, empty)
    local i = Info(); return i and i[key] or empty or "Not available"
end
K.Page({
    key = "workshop", icon = "guide", name = "Workshop", order = 46, group = "everyday",
    description = "Experimental professions, crafting plans, shopping and market research. Enable it when you want to try it.",
    keywords = "workshop experimental enable opt in tooltip designer normal shift price market history scan crafting shopping guild bank progress login load auction house ah selling duration maximum quantity advisor recommendations",
    overview = { label = "Workshop", tip = "Crafting plans, shopping and item information.",
        when = function() return Launcher() ~= nil end,
        status = function() return not Enabled() and "Experimental · Off" or (Shown() and "Open" or (Loaded() and "Enabled" or "Ready to load")) end },
    when = function() return Launcher() ~= nil end,
    build = function()
        K.Header("General", "Experimental and off for new installations. Enabling keeps loading on demand; disabling stops Workshop work and keeps your saved data. Reload only to unload its code and market database from memory.")
        K.ProxyToggle("workshopEnabled", "Workshop — Experimental",
            "Enable professions, crafting plans, shopping tools and market research. Some features are still being tested. Off for new installations. Disabling stops Workshop work and keeps your saved data. Reload only if you want to unload its code and saved market database from memory; no automatic reload.", false,
            Enabled, function(on)
                local l = Launcher()
                if l and l.SetEnabled then
                    local ok, why = l.SetEnabled(on)
                    if not ok then R.Print("workshop: " .. l.Explain(why)) end
                end
                info, infoAt = nil, nil
                K.RefreshOverview()
            end)
        local login = K.ProxyToggle("workshopLoadOnLogin", "Load Workshop when I log in",
            "Load Workshop after your next login or reload. Opens no window and starts no scan. Large saved market databases can pause the game while loading. Off by default.", false,
            function() local l = Launcher(); return l and l.LoadOnLogin and l.LoadOnLogin() or false end,
            function(on) local l = Launcher(); if l and l.SetLoadOnLogin then l.SetLoadOnLogin(on) end end)
        login:AddModifyPredicate(Enabled)
        login.why = "Enable Workshop — Experimental first. Your login preference is kept while it is off."
        local load = K.Button("Workshop options", "Load options", LoadOptions,
            "Load Workshop and its saved market data to configure its preferences. Opens no Workshop window and starts no scan.")
        load:AddShownPredicate(function() return not Loaded() end)
        load:AddModifyPredicate(Enabled)
        load.why = "Enable Workshop — Experimental first."
        Option("prices", "workshopDetailedPrices", "Detailed price display",
            "Off: uncertain costs say from or at least. On: show supported price ranges. Pricing and calculations are unchanged.", false)
        Choice("advisorGain", "workshopAdvisorGain", "Advisor minimum gain", "0", {
            { "0", "No copper minimum" }, { "100", "1 silver" }, { "1000", "10 silver" }, { "10000", "1 gold" },
        }, "Minimum gross listing gain per item above vendor sell value before considering Auction. The Advisor also requires a 1.5x vendor margin. Fees, deposits and a sale are not guaranteed.")
        local open = K.Button("Workshop window", "Open Workshop", function() Launcher().Open(); K.RefreshOverview() end,
            "Open Workshop. You can also use /tui workshop.")
        open:AddModifyPredicate(Enabled)
        open.why = "Enable Workshop — Experimental first."

        K.Header("Auction House", "Choose the auction interface and defaults for new selling drafts. Every auction action still requires your confirmation.")
        local auction = K.ProxyToggle("auctionDebug", "Use TwichUI Auction House (Experimental)",
            "Open the existing five-page Auction House when visiting an auctioneer. No proof commands are required. Turning this off restores Blizzard. Purchases, posts and cancellations require your own confirmation.", false,
            function() return R.AuctionHost and R.AuctionHost.DebugEnabled() or false end,
            function(on)
                local ok, why = R.AuctionHost.SetDebug(on)
                if not ok then R.Print(tostring(why)) end
                K.RefreshOverview()
            end)
        auction:AddModifyPredicate(function() return Enabled() and R.AuctionHost ~= nil end)
        auction.why = "Enable Workshop — Experimental first."
        local function AuctionSetting(key) return Launcher().AuctionSettings()[key] end
        K.ProxyToggle("workshopAuctionAdvisorOnly", "Start Sell with advisor recommendations only",
            "Start each visit to the Sell tab with the Advisor: auction recommendations only filter enabled. You can still change the filter in the Sell tab.", false,
            function() return AuctionSetting("advisorOnly") end, function(on) Launcher().SetAuctionOption("advisorOnly",on) end)
        K.ProxyToggle("workshopAuctionMaxQuantity", "Start with maximum sell quantity",
            "Select the maximum usable quantity when choosing a bag item. Off starts with one. Locked, bound and crafting-protected items remain excluded; nothing is posted automatically.", true,
            function() return AuctionSetting("maxQuantity") end, function(on) Launcher().SetAuctionOption("maxQuantity",on) end)
        K.Choice("workshopAuctionDuration", "Default auction duration", "The starting duration when choosing an item to sell. Changing this setting keeps the current draft unchanged.", K.STRING,"1",
            function() return tostring(AuctionSetting("duration")) end,
            function(value) Launcher().SetAuctionOption("duration",tonumber(value)) end,
            {{"1",AUCTION_DURATION_ONE or "Short"},{"2",AUCTION_DURATION_TWO or "Medium"},{"3",AUCTION_DURATION_THREE or "Long"}})

        K.Header("Tooltip Designer", "Arrange Normal and Hold Shift item information using safe preview data.")

        K.Header("Market Data", "Observed listings, not sales. Auction House scans start only when you click Scan prices.")
        local data = K.Button("Saved market data", "Load data", LoadOptions, "Read Workshop's saved observations without opening its window or scanning.")
        data:AddShownPredicate(function() return not Loaded() end)
        data:AddModifyPredicate(Enabled)
        data.why = "Enable Workshop — Experimental first."
        K.Status("Selected market", function() return Value("label", Loaded() and "No observations yet" or "Not loaded") end,
            function() return Info() and "Matches the open Auction House; otherwise the latest scan for this realm." or "Open the Auction House and choose Scan prices to collect observations." end)
        K.Status("Faction", function() return Value("side", "Not available") end)
        K.Status("Last scan", function()
            local i = Info(); local w = R.Workshop
            return i and w.Market.AgeShort(i.age) or "No scan recorded"
        end)
        K.Status("Freshness", function() local i = Info(); local words = { fresh = "Fresh", aging = "Aging", old = "Old" }; return i and words[R.Workshop.Market.Freshness(i.age)] or "Unknown" end)
        K.Status("Coverage", function()
            local i = Info(); if not i then return "No observations" end
            return i.complete and "Whole scan" or "Partial observations"
        end, function() local i = Info(); return i and (tostring(i.items or 0) .. " items observed. Listings do not establish demand or sales.") or nil end)
        K.Status("History", function()
            local i = Info(); local h = i and i.history
            if h and h.state == "future" then return "Newer format" end
            return h and h.from and ("Since " .. date("!%d %b %Y", h.from * 86400)) or "No retained history"
        end, function() return "Item-level quality and history depend on what your scans actually observed." end)
        K.Status("Data quality", function() return "Shown per item" end,
            function() return "Good, Fair or Limited describes each item's observed data in its tooltip, not the entire market." end)
        K.Status("Collection", function() return "Manual Auction House scans" end)

        K.Header("Crafting & Shopping", "Use saved observations and choose what is included in your plans.")
        local craft = K.Button("Crafting options", "Load options", LoadOptions, "Load Workshop options without opening its window or starting a plan.")
        craft:AddShownPredicate(function() return not Loaded() end)
        craft:AddModifyPredicate(Enabled)
        craft.why = "Enable Workshop — Experimental first."
        Choice("objective", "workshopObjective", "Planning objective", "economic", {
            { "economic", "Economic cost" }, { "cash", "Gold required now" },
        }, "Economic cost includes the value of materials you own. Gold required now prioritizes additional spending. Manual source choices are retained.")
        Choice("compact", "workshopCompactMode", "Compact view", "travel", {
            { "travel", "Travel: materials to gather" }, { "craft", "Craft: recipe progress" },
        }, "The compact panel's saved view. This changes its display without opening it.")
        Option("guild", "workshopUseGuild", "Include guild-bank materials",
            "Use remembered, permitted guild-bank stock when planning. Unknown or unreadable stock is never treated as available.", false)
        Option("notices", "workshopProgressNotices", "Crafting progress notifications",
            "Show verified progress and materials-ready notices. Nothing is announced at login.", true)
        K.Status("Crafting progress", function() return "Manual" end,
            function() return "Use Crafted one and Undo in Workshop. Automatic craft-completion detection remains off." end)
    end,
    host = function() return R.WorkshopWorthDesigner.Frame() end,
    hostAfter = "Tooltip Designer", hostHeight = function() return R.WorkshopWorthDesigner.Height() end,
})
