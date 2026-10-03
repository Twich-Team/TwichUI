-- TwichUI: options in Esc > Options > AddOns > TwichUI (/twichui)
-- The one home for TwichUI's settings, built from Blizzard's own controls.
-- A short overview page links to one page per feature (subcategories of
-- TwichUI). Rarely changed options sit under an "Advanced" header that only
-- shows with "Show advanced options" (on the overview) on; they keep their
-- values (and keep working) while hidden. Stat weights are a page under Gear
-- comparison (gear/Window.lua), since a ranked list and a table of numbers
-- don't fit the standard controls.

local R = TwichUI

local function AskReload()
    StaticPopupDialogs.TWICHUI_RELOAD = {
        text = "TwichUI: this change takes effect after reloading your UI. Reload now?",
        button1 = RELOADUI or "Reload", button2 = "Later",
        OnAccept = ReloadUI,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RELOAD")
end

-- Addons TwichUI can skin. addon = folder name.
local SKINS = {
    { key = "attuneSkin", addon = "Attune", label = "Attune",
      what = "Gives the Attune window (/attune) and its quest panels the EllesmereUI look." },
    { key = "auctionatorSkin", addon = "Auctionator", label = "Auctionator",
      what = "Gives Auctionator's tabs, buttons, lists and boxes the EllesmereUI look. Also needs EllesmereUI's Auction House window skin." },
    { key = "foreverDungeonJournalSkin", addon = "ForeverDungeonJournal", label = "Dungeon Journal",
      what = "Gives the Forever Dungeon Journal window (/fj) the EllesmereUI look." },
    { key = "whatsTrainingSkin", addon = "WhatsTraining", label = "WhatsTraining",
      what = "Gives WhatsTraining's floating window (/wt) the EllesmereUI look." },
}

local function AddonState(addon)
    return R.Setups and R.Setups.AddonState(addon) or "ready"
end

local function Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) or false
end

-- What a skin is doing right now: a word or two, and a sentence (or nil).
-- onAtLoad: whether the skin's toggle was on when the UI loaded.
local function SkinStatus(skin, onAtLoad)
    local state = AddonState(skin.addon)
    if state == "missing" then return R.GREY .. "Not installed|r", "Install " .. skin.label .. " to use this skin." end
    if state == "disabled" then return R.GREY .. "Turned off|r", skin.label .. " is turned off in your AddOns list." end
    local on = R:Enabled(skin.key)
    if on ~= onAtLoad then
        return R.GOLD .. (on and "On" or "Off") .. " after reload|r", "Reload your UI for this to take effect."
    end
    if not on then return R.GREY .. "Off|r", nil end
    if AddonState("EllesmereUI") == "missing" then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI isn't installed. The skin only works with it."
    end
    if not R.S then
        return R.GREY .. "Waiting for EllesmereUI|r", "EllesmereUI hasn't switched on TwichUI's skins. Check its third-party addon skin options."
    end
    if not Loaded(skin.addon) then
        return R.GREEN .. "Ready|r", "Applies when " .. skin.label .. " loads."
    end
    return R.GREEN .. "Active|r", nil
end

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory) then return end
    local root, rootLayout = Settings.RegisterVerticalLayoutCategory("TwichUI")
    R.settingsCategory = root
    R.settingsCategories = { overview = root }   -- R:OpenSettings(key)

    -- Pages are made up front so the category list keeps this order. The
    -- helpers below add to whichever page Use() last selected; the page is
    -- built in one go, so nothing is added after the next Use().
    local pages = { overview = { category = root, layout = rootLayout } }
    local function NewPage(key, name)
        local category, layout = Settings.RegisterVerticalLayoutSubcategory(root, name)
        pages[key] = { category = category, layout = layout }
        R.settingsCategories[key] = category
    end
    NewPage("gear", "Gear comparison")
    NewPage("arrival", "Zone arrival")
    NewPage("chronicle", "Journey Chronicle")
    NewPage("skins", "Addon skins")
    NewPage("sharing", "Configuration sharing")

    local category, layout
    local function Use(key) category, layout = pages[key].category, pages[key].layout end
    Use("overview")

    local VarType = Settings.VarType or {}
    local BOOL = VarType.Boolean or "boolean"
    local STRING = VarType.String or "string"
    local NUMBER = VarType.Number or "number"

    TwichUIDB.ui = TwichUIDB.ui or {}
    if TwichUIDB.ui.showAdvanced == nil then TwichUIDB.ui.showAdvanced = false end
    local function AdvancedShown() return TwichUIDB.ui.showAdvanced == true end

    -- Hidden until "Show advanced options" is on. The setting keeps its value.
    local function Advanced(initializer)
        if initializer and initializer.AddShownPredicate then initializer:AddShownPredicate(AdvancedShown) end
        return initializer
    end

    -- Greyed out while the parent checkbox is off.
    local function Under(initializer, parent, isOn)
        if initializer and parent and initializer.SetParentInitializer then
            initializer:SetParentInitializer(parent, isOn)
        end
        return initializer
    end

    -- The overview's feature rows: a name, a short status, and a button to that
    -- page. The status is rewritten whenever a toggle changes (no polling).
    local overviewRows = {}
    local function RefreshOverview()
        for _, row in ipairs(overviewRows) do
            if row.initializer.data then
                row.initializer.data.name = row.label .. "   " .. row.status()
            end
        end
    end

    local function Header(text, tooltip)
        if CreateSettingsListSectionHeaderInitializer then
            local initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    local function Toggle(key, label, tooltip, needsReload, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "TWICHUI_" .. key, key, TwichUIDB.modules, BOOL, label, R.DEFAULT_MODULES[key])
        local initializer = Settings.CreateCheckbox(category, setting, tooltip)
        if setting.SetValueChangedCallback then
            setting:SetValueChangedCallback(function()
                if needsReload then AskReload() end
                if onChange then onChange() end
                RefreshOverview()
                if R.Window then R.Window:Refresh() end
            end)
        end
        return initializer, setting
    end

    local function Button(label, buttonText, onClick, tooltip)
        if CreateSettingsButtonInitializer then
            local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
            layout:AddInitializer(initializer)
            return initializer
        end
    end

    -- A setting stored somewhere other than the modules table.
    local function Proxy(variable, varType, label, default, get, set)
        if not Settings.RegisterProxySetting then return end
        return Settings.RegisterProxySetting(category, "TWICHUI_" .. variable, varType, label, default, get, set)
    end

    local function ProxyToggle(variable, label, tooltip, default, get, set)
        local setting = Proxy(variable, BOOL, label, default, get, set)
        return setting and Settings.CreateCheckbox(category, setting, tooltip)
    end

    -- options: { { value, label, tooltip }, ... } or a function returning that.
    local function Choice(variable, label, tooltip, varType, default, get, set, options)
        local setting = Proxy(variable, varType, label, default, get, set)
        if not (setting and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
        return Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, option in ipairs(type(options) == "function" and options() or options) do
                container:Add(option[1], option[2], option[3])
            end
            return container:GetData()
        end, tooltip)
    end

    -----------------------------------------------------------------------
    -- Feature pages first; the overview is filled in at the end, once each
    -- page's status is known.
    Use("gear")
    Header("Upgrade hints", "Quiet upgrade hints for your class and main talent tree. A rough estimate from item stats, not a simulation.")
    Toggle("gearHints", "Upgrade hints in item tooltips",
        "Adds a short line to an item's tooltip when it looks like an upgrade for your class and main talent tree, such as \"Likely upgrade for Fury\". Hold Shift (your compare-items key) to see why.\n\n\"Use:\" and \"Chance on hit:\" effects aren't weighed.",
        false)
    local bags = Toggle("gearBagIcons", "Mark upgrades in my bags",
        "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade, fainter for possible upgrades. Works with Blizzard's bags and EllesmereUI Bags.",
        false, function() if R.GearBags then R.GearBags.Refresh() end end)

    local P, D, B = R.GearPrefs, R.GearData, R.GearBags
    if P and D then
        Choice("gearTree", "Weigh gear for",
            "The talent tree this character's gear is weighed for. Automatic follows the tree you've put the most points into, or your class's usual levelling tree before then.",
            NUMBER, 0,
            function() return P.TreeChoice() or 0 end,
            function(value) P.SetTreeChoice(value ~= 0 and value or nil) end,
            function()
                local trees, _, auto = D.Trees()
                local list = { { 0, auto and ("Automatic (" .. auto.name .. ")") or "Automatic" } }
                for _, tree in ipairs(trees or {}) do list[#list + 1] = { tree.skillLine, tree.name } end
                return list
            end)
    end
    if R.GearWindow then
        Button("Stat weights", "Edit", function() R.GearWindow:Show() end,
            "How each of your talent trees values stats: a stat priority you rank, as guides list them, or stat weights you can change.")
    end
    if P then
        Advanced(Header("Advanced"))
        Advanced(ProxyToggle("gearPossible", "Show possible upgrades too",
            "Also mark gear that looks a little better, or better apart from effects the estimate can't weigh. Off: only likely upgrades and empty slots.",
            true, function() return P.Get("glancePossible") and true or false end, function(value) P.Set("glancePossible", value) end))
        Advanced(ProxyToggle("gearFuture", "Hint at gear for higher levels",
            "Gear you can't wear yet only because of its level gets a hint with that level, such as \"Likely upgrade at level 32\". Handy at the auction house.",
            true, function() return P.Get("futureLevels") and true or false end, function(value) P.Set("futureLevels", value) end))

        local function Gain(key)
            local numbers = P.STRICTNESS[key]
            return ("Likely from %d%% better than what you wear, possible from %d%%."):format(
                math.floor(numbers.likely * 100 + 0.5), math.floor(numbers.possible * 100 + 0.5))
        end
        Advanced(Choice("gearStrictness", "How big a gain counts",
            "How much better than what you wear an item must look before it gets a hint.",
            STRING, "balanced",
            function() return P.Get("strictness") end, function(value) P.Set("strictness", value) end,
            {
                { "cautious", "Cautious", Gain("cautious") },
                { "balanced", "Balanced", Gain("balanced") },
                { "eager", "Eager", Gain("eager") },
            }))
        Advanced(Choice("gearReveal", "Show the reasoning",
            "What to hold over an item to see why it got its hint: what it's compared with, the stat changes that mattered most and the weights used.",
            STRING, "compare",
            function() return P.Get("reveal") end, function(value) P.Set("reveal", value) end,
            {
                { "compare", "Hold Shift", "Your compare-items key." },
                { "alt", "Hold Alt" },
                { "ctrl", "Hold Ctrl" },
                { "always", "Always", "The reasoning shows under every item you could wear." },
            }))
        if B then
            local stylePreview
            local styles = {}
            for i, style in ipairs(B.STYLES) do styles[i] = { style.key, style.label } end
            local styleRow = Choice("gearBagStyle", "Bag mark style",
                "The mark on upgrades in your bags. All use the game's own art. The square beside the list shows how it looks on a bag slot.",
                STRING, "gilded",
                function() return P.Get("bagStyle") end,
                function(value)
                    P.Set("bagStyle", value)
                    if stylePreview then B.ApplyStyle(stylePreview.mark, value) end
                end,
                styles)
            -- A preview slot beside the dropdown. Setting rows are recycled, so
            -- the slot is made once per row frame and tracked only while shown.
            if styleRow and styleRow.InitFrame then
                local initFrame, resetter = styleRow.InitFrame, styleRow.Resetter
                styleRow.InitFrame = function(self, frame)
                    initFrame(self, frame)
                    local slot = frame.TwichUIStylePreview
                    if not slot then
                        slot = CreateFrame("Frame", nil, frame)
                        slot:SetSize(26, 26)
                        slot.back = slot:CreateTexture(nil, "BACKGROUND")
                        slot.back:SetAllPoints()
                        slot.back:SetColorTexture(0.05, 0.05, 0.05, 0.9)
                        slot.mark = slot:CreateTexture(nil, "OVERLAY")
                        slot.mark:SetPoint("TOPLEFT", 1, -1)
                        frame.TwichUIStylePreview = slot
                    end
                    slot:ClearAllPoints()
                    slot:SetPoint("RIGHT", frame, "CENTER", -90, 0)
                    slot:SetFrameLevel(frame:GetFrameLevel() + 5)
                    B.ApplyStyle(slot.mark, P.Get("bagStyle"))
                    slot:Show()
                    stylePreview = slot
                end
                styleRow.Resetter = function(self, frame)
                    if resetter then resetter(self, frame) end
                    if frame.TwichUIStylePreview then frame.TwichUIStylePreview:Hide() end
                    if stylePreview == frame.TwichUIStylePreview then stylePreview = nil end
                end
            end
            Under(Advanced(styleRow), bags, function() return R:Enabled("gearBagIcons") end)
        end
    end

    if R.GearWindow and R.GearWindow.Register then R.GearWindow:Register(pages.gear.category) end

    -----------------------------------------------------------------------
    Use("skins")
    Header("EllesmereUI look", "Gives these addons the EllesmereUI look. Needs EllesmereUI with its third-party addon skins on. TwichUI only skins the addons listed here.")
    -- Each skin's tooltip ends with its status, kept current by the events
    -- that can change it (no polling).
    local skinRows = {}
    local function RefreshSkinStatus()
        for _, row in ipairs(skinRows) do
            local status, detail = SkinStatus(row.skin, row.onAtLoad)
            if row.initializer.data then
                row.initializer.data.tooltip = row.skin.what .. "\n\nStatus: " .. status .. (detail and ("\n" .. detail) or "")
            end
        end
        RefreshOverview()
    end
    for _, skin in ipairs(SKINS) do
        local installed = AddonState(skin.addon) ~= "missing"
        local label = installed and skin.label or (skin.label .. "  " .. R.GREY .. "(not installed)|r")
        local initializer = Toggle(skin.key, label, skin.what, true, RefreshSkinStatus)
        if initializer then
            skinRows[#skinRows + 1] = { skin = skin, initializer = initializer, onAtLoad = R:Enabled(skin.key) }
            if not installed and initializer.AddModifyPredicate then
                initializer:AddModifyPredicate(function() return false end)
            end
        end
    end
    RefreshSkinStatus()
    R:OnSkin(RefreshSkinStatus)
    R:On("PLAYER_LOGIN", RefreshSkinStatus)
    R:On("ADDON_LOADED", function(name)
        for _, skin in ipairs(SKINS) do
            if name == skin.addon then RefreshSkinStatus() return end
        end
    end)

    -----------------------------------------------------------------------
    Use("arrival")
    Header("Title card", "A short, quiet title card when you arrive somewhere new, in place of the game's own zone text.")
    local function RefreshArrival() if R.Arrival then R.Arrival.Refresh() end end
    local arrival = Toggle("arrival", "Show a title card when I arrive in a new zone",
        "The zone's name appears near the top of the screen under a thin bronze rule, with the smaller place you're in beneath it, then fades away. It replaces the game's own zone text while on. Not shown when you log in or reload, or while on a flight path: only where you land.\n\nIf another addon also replaces the zone text, you may see both.",
        false, RefreshArrival)
    local function ArrivalOn() return R:Enabled("arrival") end
    Under(Toggle("arrivalSubzones", "Also for smaller places",
        "A quieter card when you walk into a smaller place within the zone, such as a town. Off: moving within a zone shows nothing.",
        false, RefreshArrival), arrival, ArrivalOn)
    Under(Toggle("arrivalReducedMotion", "Reduced motion",
        "The card only fades in and out, without moving."), arrival, ArrivalOn)
    local Arrival = R.Arrival
    if Arrival then
        local holds = {}
        for i, hold in ipairs(Arrival.HOLDS) do
            holds[i] = { hold.key, hold.label, ("Stays %g seconds before fading away."):format(hold.seconds) }
        end
        Advanced(Header("Advanced"))
        Under(Advanced(Choice("arrivalHold", "How long the card stays",
            "How long the zone's name stays before it fades away. Cards for smaller places stay a little shorter.",
            STRING, Arrival.HOLD_DEFAULT,
            function() return (Arrival.HoldChoice()) end,
            function(value) TwichUIDB.ui.arrivalHold = value end,
            holds)), arrival, ArrivalOn)
    end

    -----------------------------------------------------------------------
    Use("chronicle")
    Header("Automatic entries", "A quiet, private journal for this character. It isn't shared, sent or backed up with your configuration, and it never tells you what to do next.")
    local chronicle = Toggle("chronicle", "Keep moments for me automatically",
        "On by default. TwichUI adds a short entry to this character's Chronicle for the moments you pick below. It starts the moment it is on and never looks back. You can always write your own notes, whatever this is set to.",
        false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end)
    local function ChronicleOn() return R:Enabled("chronicle") end
    local function ChronicleToggle(key, label, tooltip)
        Under(Toggle(key, label, tooltip, false, function() if R.ChronicleRecorder then R.ChronicleRecorder.Refresh() end end),
            chronicle, ChronicleOn)
    end
    ChronicleToggle("chronicleLevels", "Reaching a new level", "Adds an entry when you gain a level.")
    ChronicleToggle("chronicleZones", "Arriving somewhere new", "Adds an entry when you travel into a new zone, including entering a dungeon. Not when you log in.")
    ChronicleToggle("chronicleBosses", "Defeating an encounter", "Adds an entry when a dungeon or raid encounter you fought ends in victory. Only the encounter's name is kept.")
    ChronicleToggle("chronicleDeaths", "Falling in battle", "Adds an entry when your character dies, with the zone you were in. Off until you choose it.")
    ChronicleToggle("chronicleGold", "Gold earned milestones", "Adds an entry when the gold you've gained since tracking began reaches 10, 50, 100, 500, 1,000, 5,000 and 10,000. Spending doesn't lower it, and what you already carry isn't counted.")
    ChronicleToggle("chronicleRiding", "Learning to ride", "Adds an entry when you learn a new Riding rank.")
    ChronicleToggle("chronicleProfessions", "Professions", "Adds an entry when you learn a profession, and when a profession skill first reaches 75, 150, 225, 300, 375 and 450. Professions and skill you already have aren't counted.")
    ChronicleToggle("chronicleChat", "Show Chronicle entries in chat", "Prints a quiet line in your own chat window when an entry is added automatically. Only you see it; it is never sent to anyone. Entries are still recorded when this is off.")
    Toggle("chronicleSound", "Play Chronicle opening sound", "Plays a soft page-turn sound each time you open the Chronicle. It follows your game sound settings and volume.")
    Choice("chronicleClock", "Time format",
        "How times are shown in your Chronicle.",
        STRING, "12",
        function() return TwichUIDB.ui.chronicleClock == "24" and "24" or "12" end,
        function(value)
            TwichUIDB.ui.chronicleClock = value
            if R.ChronicleWindow then R.ChronicleWindow:Refresh() end
        end,
        { { "12", "12-hour (3:45 PM)" }, { "24", "24-hour (15:45)" } })
    Button("Journey Chronicle", "Open", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if R.ChronicleWindow then R.ChronicleWindow:Show() end
    end, "Opens your Chronicle (same as typing /tui chronicle).")

    -----------------------------------------------------------------------
    Use("sharing")
    Header("Addon configurations", "Share the settings of the addons you choose with friends, and apply theirs. You always choose what to apply, and Undo puts your own settings back.")
    local sharing = Toggle("setupSharing", "Configuration sharing",
        "Save the settings of the addons you choose as an addon configuration, send it to friends in game, and apply configurations friends send you. Type /tui share.",
        true)
    local function SharingOn() return R:Enabled("setupSharing") end
    Under(Toggle("acceptSetups", "Let friends send me addon configurations",
        "When on, friends can offer you their addon configuration. You're always asked first, unless you chose \"Always accept\" for that friend. Nothing is applied until you click Apply.",
        false), sharing, SharingOn)
    Toggle("groupCheck", "Version and group check",
        "On by default. Both players need it on to see each other. Other players never see these messages, even without TwichUI.\n\nWhen you're in a group, TwichUI trades version numbers with other TwichUI users (a few bytes, group channel only) and tells you when someone's version is newer or too old to share with. Also powers /tui check and Party compatibility check in /tui share, and a once-per-game-build test that switches sharing back to direct messages when Forever fixes them.",
        true)
    Button("Configuration sharing", "Open", function()
        if not R:Enabled("setupSharing") then
            R.Print("turn on Configuration sharing first.")
            return
        end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        R.Window:Show()
    end, "Opens the sharing window: send your setup, review ones friends sent, create backups and run the party compatibility check (same as typing /tui share).")
    Advanced(Header("Advanced"))
    Advanced(Toggle("shareWhisper", "Send by direct message",
        "Send and receive configurations with hidden addon messages straight to one player. Only they receive it.\n\n" .. R.Share.WHY_FOREVER,
        false))
    Advanced(Toggle("shareGroup", "Send over the group channel",
        "Send and receive over your party or raid's hidden addon channel. Everyone in the group receives the data; only the named recipient's TwichUI reads it, the rest ignore it. No chat text appears.\n\nUse this on Forever, where direct messages don't work yet.",
        false))
    Advanced(Toggle("shareGuild", "Send over the guild channel",
        "Send and receive over your guild's hidden addon channel. Every online guild member receives the data; only the named recipient's TwichUI reads it. No chat text appears, but it uses guild-wide bandwidth, so prefer the group channel when you can.",
        false))

    -----------------------------------------------------------------------
    Use("overview")
    Header("A quiet interface companion for WoW: Forever.",
        "TwichUI makes the game's interface a little clearer and more cohesive, without taking over. Each feature has its own page below, and every one can be turned off.")

    local function OnOff(on, onText, offText)
        if on then return R.GREEN .. (onText or "On") .. "|r" end
        return R.GREY .. (offText or "Off") .. "|r"
    end
    -- key: page to open; status: a word or two for the row.
    local function FeatureRow(key, label, tooltip, status)
        if not CreateSettingsButtonInitializer then return end
        local initializer = CreateSettingsButtonInitializer(label, "Open", function()
            if Settings.OpenToCategory and R.settingsCategories[key] then
                Settings.OpenToCategory(R.settingsCategories[key]:GetID())
            end
        end, tooltip, false)
        layout:AddInitializer(initializer)
        overviewRows[#overviewRows + 1] = { initializer = initializer, label = label, status = status }
    end
    if R.GearPrefs then
        FeatureRow("gear", "Gear comparison", "Quiet upgrade hints in item tooltips and bags, and the stat weights behind them.",
            function() return OnOff(R:Enabled("gearHints") or R:Enabled("gearBagIcons")) end)
    end
    FeatureRow("arrival", "Zone arrival", "A brief title card when you arrive somewhere new.",
        function() return OnOff(R:Enabled("arrival")) end)
    FeatureRow("chronicle", "Journey Chronicle", "Your private journal for this character.",
        function() return OnOff(R:Enabled("chronicle"), "Recording", "Notes only") end)
    FeatureRow("skins", "Addon skins", "The EllesmereUI look for supported addons.", function()
        local installed, on = 0, 0
        for _, skin in ipairs(SKINS) do
            if AddonState(skin.addon) ~= "missing" then
                installed = installed + 1
                if R:Enabled(skin.key) then on = on + 1 end
            end
        end
        if installed == 0 then return R.GREY .. "None installed|r" end
        return OnOff(on > 0, ("%d of %d on"):format(on, installed), "Off")
    end)
    FeatureRow("sharing", "Configuration sharing", "Share your addon settings with friends, and keep backups.",
        function() return OnOff(R:Enabled("setupSharing")) end)
    RefreshOverview()

    -----------------------------------------------------------------------
    Header("General")
    local advancedSetting = Settings.RegisterAddOnSetting(category, "TWICHUI_showAdvanced", "showAdvanced", TwichUIDB.ui, BOOL,
        "Show advanced options", false)
    Settings.CreateCheckbox(category, advancedSetting,
        "Shows an Advanced section on the pages that have one: how upgrade hints are judged and revealed and the bag mark style (Gear comparison), how long the title card stays (Zone arrival), and how configurations are sent (Configuration sharing). Hidden options keep their values.")
    Toggle("media", "Custom fonts and sounds",
        "Adds Alegreya, Alegreya Sans, Barlow and Cinzel fonts, plus the bell alert sounds, to the font and sound lists of EllesmereUI and other addons. Nothing changes until you pick them there.",
        true)
    Toggle("quietLogin", "Hide addon welcome messages",
        "Hides the \"loaded\" and \"type /command for options\" lines addons print when you log in or reload. Errors and warnings still show. Type /twichui hidden to see what was hidden this session.",
        true)

    Settings.RegisterAddOnCategory(root)
end

R:OnInit(function()
    local ok, err = pcall(Build)
    if not ok then geterrorhandler()(err) end
end)
