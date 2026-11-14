-- Workshop configuration in the existing settings shell. Describing the page
-- never loads the Workshop or reads its separate market database.
local R = TwichUI
local K = R.SettingsKit
local function Launcher() return R.WorkshopLauncher end
local function Loaded() return Launcher() and Launcher().Loaded() end
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
    row.why = "Load Workshop options first. No Workshop window or scan will open."
end
local function Choice(key, variable, label, default, choices, tip)
    local setting = K.Proxy(variable, "string", label, default,
        function() return State(key) or default end,
        function(value) local l = Launcher(); if l and l.SetChoice then l.SetChoice(key, value) end end)
    local row = K.Dropdown(setting, function() return choices end, tip)
    row:AddModifyPredicate(Loaded)
    row.why = "Load Workshop options first. No Workshop window or scan will open."
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
    description = "Choose how Workshop plans your crafts and shows item information.",
    keywords = "workshop tooltip designer normal shift price market history scan crafting shopping guild bank progress login load",
    overview = { label = "Workshop", tip = "Crafting plans, shopping and item information.",
        when = function() return Launcher() ~= nil end,
        status = function() return Shown() and "Open" or (Loaded() and "Closed" or "Not opened yet") end },
    when = function() return Launcher() ~= nil end,
    build = function()
        K.Header("General", "Workshop opens when you ask for it.")
        K.ProxyToggle("workshopLoadOnLogin", "Load Workshop when I log in",
            "Load Workshop after your next login or reload. Opens no window and starts no scan. Large saved market databases can pause the game while loading. Off by default.", false,
            function() local l = Launcher(); return l and l.LoadOnLogin and l.LoadOnLogin() or false end,
            function(on) local l = Launcher(); if l and l.SetLoadOnLogin then l.SetLoadOnLogin(on) end end)
        local load = K.Button("Workshop options", "Load options", LoadOptions,
            "Load Workshop and its saved market data to configure its preferences. Opens no Workshop window and starts no scan.")
        load:AddShownPredicate(function() return not Loaded() end)
        Option("prices", "workshopDetailedPrices", "Detailed price display",
            "Off: uncertain costs say from or at least. On: show supported price ranges. Pricing and calculations are unchanged.", false)
        K.Button("Workshop window", "Open Workshop", function() Launcher().Open(); K.RefreshOverview() end,
            "Open Workshop. You can also use /tui workshop.")

        K.Header("Tooltip Designer", "Arrange Normal and Hold Shift item information using safe preview data.")

        K.Header("Market Data", "Observed listings, not sales. Auction House scans start only when you click Scan prices.")
        local data = K.Button("Saved market data", "Load data", LoadOptions, "Read Workshop's saved observations without opening its window or scanning.")
        data:AddShownPredicate(function() return not Loaded() end)
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
