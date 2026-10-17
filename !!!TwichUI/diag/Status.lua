-- TwichUI: status snapshot and support information
-- A short, current picture of how TwichUI and its optional addons look from here, and a concise plain-text
-- version of it to paste into an issue or a message. It is a snapshot, not a verdict: a state says what the
-- addons' own answers allow (installed? loaded? the call TwichUI needs there? the player's own choice?), never
-- that a feature works. Nothing here changes a setting, turns an addon on or loads one.
--
-- Where each answer comes from (nothing is re-derived here that an adapter already knows):
--   version, interface   the addon list's metadata for TwichUI (GetAddOnMetadata); the channel only when the version
--                        carries the build suffix tools/release.py writes into alpha and beta builds
--   client               GetBuildInfo
--   core                 R.Life.Snapshot (Core.lua)
--   settings window      R.SettingsLauncher.Snapshot and the addon list's state for TwichUI_Settings
--   pending reloads      R.Switches.PendingReloads (Switches.lua)
--   each capability      its own adapter: R.EllesmereJunk.Status, R.FoodDrink.Unlock.Status, R.RestedXPSkin.Status,
--                        RestedXPSkin.Timers.Status, R.QoLGuideWaypoint.Status, R.RestedXPBroker.Available,
--                        R.SpeakStoneSkin.Status, R.Borders.Ellesmere, R.SettingsWidgets.ColorPicker.Status,
--                        R.S / R.euiRegistered (Core.lua), and the addon list (R.Setups.AddonState)
--
-- The report is an allowlist: every line is written from the fields below, and each value is a fixed word, a
-- number or a version-shaped token (letters, digits and . - + _). It carries no character, realm, guild or
-- friend name, no chat, no records, no saved data, no paths and no text the player typed. D.Clean (Diagnostics.lua)
-- is not what keeps it private; the fields chosen are.
--
-- Collected when the Troubleshooting page opens, when Refresh is pressed and when the report is requested;
-- never in the background. The page's copy is dropped when the settings close.

local R = TwichUI
local S = {}
R.DiagStatus = S

S.FORMAT = 1
local MAX_HELD = 12     -- "held back" codes listed

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- A string made only of letters, digits and . - + _ (versions, build numbers, codes), or nil.
local function Token(v, max)
    if type(v) == "number" and not Secret(v) then v = tostring(v) end
    if type(v) ~= "string" or Secret(v) or v == "" or #v > (max or 40) then return nil end
    if v:find("[^%w%.%-%+_]") then return nil end
    return v
end
S.Token = Token

local function Metadata(addon, field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, addon, field)
    if not ok then return nil end
    value = Token(value)
    if value and value:find("^@") then return nil end   -- a packager placeholder that was never filled in
    return value
end

local function Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) == true
end

-- "loaded", "missing", "disabled", "not-loaded" (installed; the game has not loaded it) or "unknown". Reads the
-- addon list only; it loads nothing.
local function Presence(addon)
    if Loaded(addon) then return "loaded" end
    local state = R.Setups and R.Setups.AddonState and R.Setups.AddonState(addon)
    if state == "missing" then return "missing" end
    if state == "disabled" then return "disabled" end
    if state == "ready" then return "not-loaded" end
    return "unknown"
end

local PRESENCE_STATE = { missing = "not-installed", disabled = "disabled", ["not-loaded"] = "not-loaded", unknown = "unknown" }
local PRESENCE_CODE = { missing = "addon-missing", disabled = "addon-disabled", ["not-loaded"] = "addon-not-loaded", unknown = "addon-list-unreadable" }
local PRESENCE_WORD = {
    loaded = "loaded", missing = "not installed", disabled = "turned off in the AddOns list",
    ["not-loaded"] = "installed, not loaded", unknown = "unknown (the AddOns list could not be read)",
}

-- nil when the addon is loaded; otherwise the capability result its absence gives.
local function Gate(folder)
    local p = Presence(folder)
    if p == "loaded" then return nil end
    return { state = PRESENCE_STATE[p], code = PRESENCE_CODE[p] }
end

local function Result(state, code, why, extra)
    local r = extra or {}
    r.state, r.code, r.why = state, code, why
    return r
end

-- Whether a switch is on, as the settings window shows it: a saved true, or no saved value and a default of on.
local function On(key)
    local m = TwichUIDB and TwichUIDB.modules
    local v
    if type(m) == "table" then v = m[key] end   -- (not `and ... or nil`: a saved false must stay false)
    if v == nil then return R.DEFAULT_MODULES and R.DEFAULT_MODULES[key] == true end
    return v == true
end

local function Available(key)
    local W = R.Switches
    return not (W and W.Available) or W.Available(key)
end

---------------------------------------------------------------------------
-- The states a capability can be in
---------------------------------------------------------------------------
S.STATES = { "available", "not-installed", "disabled", "not-loaded", "not-initialized", "unavailable", "off", "not-applicable", "unknown" }
S.LABELS = {
    available = "Available", ["not-installed"] = "Not installed", disabled = "Turned off in the AddOns list",
    ["not-loaded"] = "Installed, not loaded", ["not-initialized"] = "Not initialized yet", unavailable = "Unavailable",
    off = "Off in TwichUI", ["not-applicable"] = "Not applicable", unknown = "Unknown",
}
-- What the person can do, by state, when a capability has nothing more specific to say.
local TODO = {
    ["not-installed"] = "Optional: nothing to do unless you want it.",
    disabled = "Turn it on in the AddOns list and reload, if you want it.",
    ["not-loaded"] = "It has not loaded yet. Press Refresh after logging in; if it stays this way, check the AddOns list.",
    ["not-initialized"] = "It is still starting or waiting for something. Press Refresh in a moment.",
    unavailable = "TwichUI can't fix this from here; updating the addon may help.",
    off = "Turn it on in TwichUI's settings if you want it.",
    unknown = "The AddOns list could not be read. Press Refresh.",
}
-- States in which the functionality is missing right now, so its fallback is what applies.
local MISSING = { ["not-installed"] = true, disabled = true, ["not-loaded"] = true, ["not-initialized"] = true, unavailable = true }

---------------------------------------------------------------------------
-- Capabilities. Each says what it affects, what happens without it and, by state, what can be done; its `check`
-- returns { state, code, why, wanted, actionable }:
--   code        a short stable word (an adapter's own code where it has one), the one thing in the report beside the state
--   why         one sentence about this state, from the adapter
--   wanted      TwichUI is set up to use it (a switch or mode the player chose), so its absence matters to them
--   actionable  worth a warning color: wanted and not available, with something the person can do
-- A group is one addon (or library); a group with several capabilities folds into one line while the addon is
-- not there and nothing in it is wanted.
---------------------------------------------------------------------------
local EUI, RXP = "EllesmereUI", "RXPGuides"

local function EUISkinCapability(id, label, switch, folder, name)
    return {
        id = id, label = label, folder = folder,
        affects = "TwichUI's EllesmereUI look for " .. name,
        fallback = name .. " keeps its own look.",
        check = function()
            if not On(switch) then return Result("off", "off", "TwichUI's skin for " .. name .. " is turned off.") end
            local gate = Gate(folder)
            if gate then return gate end   -- the addon being skinned is not here: nothing to skin, nothing wrong
            if R.S then return Result("available", "toolkit-received") end
            local eui = Presence(EUI)
            if eui ~= "loaded" then
                return Result("unavailable", "needs-ellesmereui", "This skin works through EllesmereUI, which is " .. PRESENCE_WORD[eui] .. ".")
            end
            if not (R.Life and R.Life.loggedIn) then
                return Result("not-initialized", "toolkit-not-received", "EllesmereUI hands over its skin toolkit at login.")
            end
            return Result("unavailable", "toolkit-not-received",
                "EllesmereUI has not handed TwichUI its skin toolkit (it does at login when its third-party addon skins are on).",
                { wanted = true, actionable = true })
        end,
    }
end

S.GROUPS = {
    {
        key = "ellesmereui", title = "EllesmereUI", folder = EUI, fold = true,
        caps = {
            {
                id = "eui-skin", label = "Skin toolkit",
                affects = "the finish of TwichUI's own windows, and the Auctionator, What's Training, Forever Dungeon Journal and Attune skins",
                fallback = "TwichUI's windows keep their own plain look and those skins stay off.",
                todo = { ["not-initialized"] = "Turn on third-party addon skins in EllesmereUI and reload, if you want its finish." },
                check = function()
                    local gate = Gate(EUI)
                    if gate then return gate end
                    if R.S then return Result("available", "toolkit-received") end
                    if R.euiRegistered then
                        return Result("not-initialized", "toolkit-not-received",
                            "EllesmereUI has not handed TwichUI its skin toolkit (it does at login when its third-party addon skins are on).")
                    end
                    return Result("unavailable", "no-register-api", "This EllesmereUI has no skin registration TwichUI can use.")
                end,
            },
            {
                id = "eui-borders", label = "Border textures",
                affects = "EllesmereUI's border choices in TwichUI's border lists",
                fallback = "Those choices are not offered; the game's and LibSharedMedia's borders still work, and a saved EllesmereUI choice is kept and drawn as a plain line.",
                check = function()
                    local gate = Gate(EUI)
                    if gate then return gate end
                    local B = R.Borders
                    if not (B and B.Ellesmere) then return Result("unavailable", "no-border-module", "TwichUI's border module is not loaded.") end
                    if B.Ellesmere() then return Result("available", "ready") end
                    return Result("unavailable", "no-border-api", "This EllesmereUI lacks border functions TwichUI uses.")
                end,
            },
            {
                id = "eui-colorpicker", label = "Color picker",
                affects = "the color picker the settings window's swatches open",
                fallback = "The game's own color picker is used.",
                check = function()
                    local gate = Gate(EUI)
                    if gate then return gate end
                    local Wg = R.SettingsWidgets
                    local CP = Wg and Wg.ColorPicker
                    if not (CP and CP.Status) then
                        return Result("not-initialized", "settings-not-loaded", "The settings window is not loaded, so its color picker has not been checked.")
                    end
                    local state = CP.Status()
                    if state == "ready" then return Result("available", "ready") end
                    if state == "on-demand" then
                        return Result("not-initialized", "loads-on-use", "EllesmereUI loads its picker the first time a color swatch is clicked.")
                    end
                    if state == "load-failed" then
                        return Result("unavailable", "load-failed", "EllesmereUI's picker did not load when it was asked to.")
                    end
                    return Result("unavailable", "no-picker-api", "This EllesmereUI offers no color picker TwichUI can open.")
                end,
            },
            {
                id = "eui-junk", label = "Bag junk marking",
                affects = "marking ordinary food and drink as junk in EllesmereUI's bags (Mage selling)",
                fallback = "Your selected mode is kept. Nothing is marked, and TwichUI is not selling these items directly, until it is available.",
                todo = { unavailable = "Fix it in EllesmereUI, or choose Sell directly in the Mage options.",
                    ["not-installed"] = "Install EllesmereUI's Bags, or choose Sell directly in the Mage options.",
                    disabled = "Turn EllesmereUI's Bags on in the AddOns list and reload, or choose Sell directly in the Mage options." },
                check = function()
                    local MS, EJ = R.MageSell, R.EllesmereJunk
                    if not (MS and EJ) then return Result("not-applicable", "not-loaded", "Mage selling is not part of this install.") end
                    if not MS.ForPlayer() then return Result("not-applicable", "not-a-mage", "Mage selling is for Mages.") end
                    if MS.Mode() ~= "ellesmere" then
                        return Result("not-applicable", "mode-direct", "Mage selling is not set to mark items with EllesmereUI.")
                    end
                    if not MS.Enabled() then return Result("off", "off", "Mage selling is turned off.") end
                    local status = EJ.Status()
                    local why = EJ.REASONS and EJ.REASONS[status]
                    if status == "ready" then
                        local selling = EJ.Selling()
                        return Result("available", "ready",
                            selling == "auto" and "Marked items are sold by EllesmereUI's Auto Sell Junk."
                            or (selling == "button" and "Marked items are sold only when you press Sell Junk in EllesmereUI's bags at a merchant." or nil),
                            { wanted = true })
                    end
                    local state = (status == "not-installed" or status == "disabled" or status == "not-loaded") and status or "unavailable"
                    return Result(state, status, why, { wanted = true, actionable = state ~= "not-loaded" })
                end,
            },
            {
                id = "eui-unlock", label = "Unlock Mode (Food and Drink)",
                affects = "moving the Food and Drink buttons in EllesmereUI's Unlock Mode",
                fallback = "The buttons are moved in the game's Edit Mode instead.",
                check = function()
                    local U = R.FoodDrink and R.FoodDrink.Unlock
                    if not U then return Result("not-applicable", "not-loaded", "The Food and Drink buttons are not part of this install.") end
                    local code = U.Status()
                    if code == "off" then return Result("off", "off", "The Unlock Mode choice for the Food and Drink buttons is off.") end
                    local extra = { wanted = true }
                    if code == "no-eui" then
                        local gate = Gate(EUI)
                        if gate then return Result(gate.state, gate.code, nil, extra) end
                        return Result("unavailable", code, "EllesmereUI's global is missing although it reports as loaded.", { wanted = true, actionable = true })
                    end
                    if code == "no-api" then
                        return Result("unavailable", code, "This EllesmereUI has no Unlock Mode registration TwichUI can use.", { wanted = true, actionable = true })
                    end
                    if code == "waiting" then return Result("not-initialized", code, "The anchor is registered once EllesmereUI is ready.", extra) end
                    if code == "register-failed" then
                        return Result("unavailable", code, "EllesmereUI refused the anchor's registration.", { wanted = true, actionable = true })
                    end
                    if code == "module-off" then
                        return Result("not-applicable", code, "The Food and Drink buttons are off or none is shown, so the anchor is hidden.", extra)
                    end
                    return Result("available", code, nil, extra)
                end,
            },
        },
    },
    {
        key = "restedxp", title = "RestedXP", folder = RXP, fold = true,
        caps = {
            {
                id = "rxp-skin", label = "Guide window skin",
                affects = "TwichUI's look for RestedXP's guide window",
                fallback = "RestedXP's guide window keeps its own look.",
                check = function()
                    local Skin = R.RestedXPSkin
                    if not (Skin and Skin.Status) then return Result("not-applicable", "not-loaded", "The RestedXP skin is not part of this install.") end
                    local s = Skin.Status()
                    local code, extra = s.code, { wanted = s.switchOn }
                    if code == "off" then return Result("off", code, "The RestedXP skin is turned off.") end
                    if code == "restedxp-missing" then return Result("not-installed", code, nil, extra) end
                    if code == "restedxp-disabled" then return Result("disabled", code, nil, extra) end
                    if code == "waiting" then return Result("not-initialized", code, "RestedXP has not finished loading.", extra) end
                    if code == "unsupported" then
                        return Result("unavailable", code, "This RestedXP does not have what the skin needs.", { wanted = true, actionable = true })
                    end
                    if code == "conflict" then
                        return Result("unavailable", code, "Another RestedXP skin is drawing.", { wanted = true, actionable = true })
                    end
                    if code == "theme-not-selected" then
                        return Result("available", code, "RestedXP is using another theme; choose TwichUI's in RestedXP's theme list.", extra)
                    end
                    if code == "v2-window" then
                        return Result("available", code, "RestedXP's v2 guide window is on; only the theme's colors and font reach it.", extra)
                    end
                    return Result("available", code, nil, extra)
                end,
            },
            {
                id = "rxp-timers", label = "Timer bars skin",
                affects = "TwichUI's look for RestedXP's countdown bars",
                fallback = "RestedXP's timer bars keep their own look.",
                check = function()
                    local T = R.RestedXPSkin and R.RestedXPSkin.Timers
                    if not (T and T.Status) then return Result("not-applicable", "not-loaded", "The RestedXP timer-bar skin is not part of this install.") end
                    local s = T.Status()
                    if s.code == "off" then return Result("off", s.code, "The timer-bar skin is turned off.") end
                    if s.code == "skin-off" then
                        return Result("not-applicable", s.code, "The timer-bar skin is a finish on the RestedXP skin, which is not drawing.")
                    end
                    if s.code == "unsupported" then
                        return Result("unavailable", s.code, "This RestedXP has no timer bars the skin can draw.", { wanted = true, actionable = true })
                    end
                    return Result("available", s.code, nil, { wanted = true })
                end,
            },
            {
                id = "rxp-broker", label = "Data bar guide toggle",
                affects = "the entry that turns RestedXP's guide on and off from a data bar",
                fallback = "That entry is not made; RestedXP's own controls are unchanged.",
                check = function()
                    local gate = Gate(RXP)
                    if gate then return gate end
                    local B = R.RestedXPBroker
                    if not (B and B.Available) then return Result("not-initialized", "not-loaded", "TwichUI's data bar module for RestedXP is not loaded.") end
                    if B.Available() then return Result("available", "ready") end
                    if not (R.Life and R.Life.loggedIn) then return Result("not-initialized", "before-login", "The entry is made at login.") end
                    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
                    if not LDB then return Result("unavailable", "no-ldb", "No data bar addon here provides LibDataBroker.") end
                    return Result("unavailable", "restedxp-unreadable", "RestedXP could not be read for the toggle (a version this was not written for?).")
                end,
            },
            {
                id = "rxp-waypoint", label = "Guide waypoint",
                affects = "putting the game's waypoint on RestedXP's current destination",
                fallback = "No waypoint is set for the guide.",
                check = function()
                    local W = R.QoLGuideWaypoint
                    if not (W and W.Status) then return Result("not-applicable", "not-loaded", "The guide waypoint option is not part of this install.") end
                    local code = W.Status()
                    local extra = { wanted = true }
                    if code == "off" then return Result("off", code, "The guide waypoint option is turned off.", { wanted = false }) end
                    if code == "restedxp-missing" then return Result("not-installed", code, nil, extra) end
                    if code == "restedxp-disabled" then return Result("disabled", code, nil, extra) end
                    if code == "waiting" then return Result("not-initialized", code, "RestedXP has not finished loading.", extra) end
                    if code == "unsupported" then
                        return Result("unavailable", code, "This RestedXP does not offer what the waypoint needs.", { wanted = true, actionable = true })
                    end
                    return Result("available", code, nil, extra)
                end,
            },
        },
    },
    {
        key = "speakstone", title = "SpeakStone", folder = "SpeakStone_Forever_Main",
        caps = {
            {
                id = "speakstone-skin", label = "Skin for SpeakStone", folder = "SpeakStone_Forever_Main",
                affects = "TwichUI's look for SpeakStone's speech frame",
                fallback = "SpeakStone's frame keeps its own look.",
                check = function()
                    local Skin = R.SpeakStoneSkin
                    if not (Skin and Skin.Status) then return Result("not-applicable", "not-loaded", "The SpeakStone skin is not part of this install.") end
                    local s = Skin.Status()
                    local code, extra = s.code, { wanted = s.switchOn }
                    if code == "off" then return Result("off", code, "The SpeakStone skin is turned off.") end
                    if code == "speakstone-missing" then return Result("not-installed", code, nil, extra) end
                    if code == "speakstone-disabled" then return Result("disabled", code, nil, extra) end
                    if code == "waiting" then
                        return Result("not-initialized", code, "SpeakStone builds its frame the first time it has something to show.", extra)
                    end
                    if code == "unsupported" or code == "error" then
                        return Result("unavailable", code, "The skin could not be applied to this SpeakStone.", { wanted = true, actionable = true })
                    end
                    return Result("available", code, nil, extra)
                end,
            },
        },
    },
    { key = "auctionator", title = "Auctionator", folder = "Auctionator",
        caps = { EUISkinCapability("auctionator-skin", "Skin for Auctionator", "auctionatorSkin", "Auctionator", "Auctionator") } },
    { key = "whatstraining", title = "What's Training?", folder = "WhatsTraining",
        caps = { EUISkinCapability("whatstraining-skin", "Skin for What's Training?", "whatsTrainingSkin", "WhatsTraining", "What's Training?") } },
    { key = "dungeonjournal", title = "Forever Dungeon Journal", folder = "ForeverDungeonJournal",
        caps = { EUISkinCapability("dungeonjournal-skin", "Skin for Forever Dungeon Journal", "foreverDungeonJournalSkin", "ForeverDungeonJournal", "Forever Dungeon Journal") } },
    { key = "attune", title = "Attune", folder = "Attune",
        caps = { EUISkinCapability("attune-skin", "Skin for Attune", "attuneSkin", "Attune", "Attune") } },
    {
        key = "databar", title = "Data bars",
        caps = {
            {
                id = "databar-ldb", label = "Data bar library (LibDataBroker)",
                labels = { ["not-installed"] = "Not provided" },
                affects = "TwichUI's data bar entries (pins, Mage Travel and Conjuring, refreshments, the RestedXP guide toggle)",
                fallback = "TwichUI makes no data bar entries until an addon provides the library.",
                todo = { ["not-installed"] = "Optional: a data bar addon provides it, if you want those entries." },
                check = function()
                    local LDB = S.DataBarLibrary()
                    if LDB then return Result("available", "ready", "A data bar addon provides the library; it does not show that each entry is on a bar.") end
                    return Result("not-installed", "no-ldb", "No data bar addon here provides LibDataBroker.")
                end,
            },
        },
    },
}

---------------------------------------------------------------------------
-- Features: the switches the report lists, by readable name (the allowlist; a switch not here is not reported)
---------------------------------------------------------------------------
S.FEATURES = {
    { "gearHints", "Gear upgrade hints" }, { "gearBagIcons", "Upgrade marks in bags" },
    { "chronicle", "Journey Chronicle" }, { "welcomeBack", "Welcome Back bookmark" },
    { "arrival", "Zone arrival card" }, { "trainingNotice", "New training notice" }, { "friendLogin", "Friend login card" },
    { "foodDrink", "Food and Drink buttons" }, { "foodDrinkUnlock", "Food and Drink in EllesmereUI Unlock Mode" },
    { "mageTravel", "Mage Travel" }, { "mageConjure", "Mage Conjuring" }, { "mageRefreshments", "Mage refreshments" },
    { "mageSell", "Mage selling" }, { "mageSellDryRun", "Mage selling dry run" },
    { "partyPins", "Party pins" }, { "auctionPosting", "Sell from Bags (Auction House)" }, { "restock", "Vendor restocking" },
    { "qolSummons", "Accept summons" }, { "qolResurrect", "Accept resurrection" }, { "qolReleasePvP", "Release in battlegrounds" },
    { "qolDuels", "Decline duels" }, { "qolQuickKeybind", "Quick Keybind button" }, { "qolEasyFishing", "Easy Fishing" },
    { "qolGuideWaypoint", "Guide waypoint (RestedXP)" },
    { "restedxpSkin", "RestedXP skin" }, { "speakstoneSkin", "SpeakStone skin" }, { "auctionatorSkin", "Auctionator skin" },
    { "whatsTrainingSkin", "What's Training? skin" }, { "foreverDungeonJournalSkin", "Forever Dungeon Journal skin" },
    { "attuneSkin", "Attune skin" },
    { "setupSharing", "Configuration sharing" }, { "groupCheck", "Group check" },
    { "media", "Custom fonts and sounds" }, { "quietLogin", "Hide addon welcome messages" },
}
-- Switches a reload can be waiting on (Switches.lua's `reload` ones, and the Mage launchers), by readable name.
local RELOAD_NAMES = {
    attuneSkin = "Attune skin", auctionatorSkin = "Auctionator skin", foreverDungeonJournalSkin = "Forever Dungeon Journal skin",
    whatsTrainingSkin = "What's Training? skin", setupSharing = "Configuration sharing", groupCheck = "Group check",
    media = "Custom fonts and sounds", quietLogin = "Hide addon welcome messages",
    mageTravel = "Mage Travel", mageConjure = "Mage Conjuring",
}
S.RELOAD_NAMES = RELOAD_NAMES

-- Whether a data bar addon provides LibDataBroker (a single library lookup: nothing is loaded or asked of the
-- library). The status line above and the settings pages' notes read this one answer.
function S.DataBarLibrary()
    return LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) or nil
end

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------
local function VersionInfo()
    local text = Metadata(R.ADDON, "Version")
    local info = { text = text }
    -- tools/release.py writes MAJOR.MINOR.PATCH-alpha|beta.<commits>.g<commit> into alpha and beta builds. A plain
    -- MAJOR.MINOR.PATCH is a stable release and also what an unpackaged copy shows, so it says nothing about the channel.
    local channel = text and text:match("^%d+%.%d+%.%d+%-(%a+)%.%d+%.g%x+$")
    if channel == "alpha" or channel == "beta" then info.channel = channel end
    return info
end

local function ClientInfo()
    local version, build, _, toc
    if GetBuildInfo then version, build, _, toc = GetBuildInfo() end
    local locale = GetLocale and GetLocale()
    return {
        version = Token(version), build = Token(build), interface = Token(toc),
        locale = type(locale) == "string" and locale:match("^%a%a%a%a$") or nil,
        addonInterface = Metadata(R.ADDON, "Interface"),
    }
end

local function CoreInfo()
    local L = R.Life
    if not (L and L.Snapshot) then return { state = "unknown" } end
    local s = L.Snapshot()
    local state = "started"
    if s.savedVariables == "failed" or s.hookFailures > 0 then state = "problem"
    elseif not s.configReady then state = "starting" end
    return {
        state = state, savedVariables = s.savedVariables == "ready" and "ready" or (s.savedVariables == "failed" and "failed" or "waiting"),
        configReady = s.configReady and true or false, hooksRun = s.hooksRun, hooksFailed = s.hookFailures,
        loggedIn = s.loggedIn and true or false, inWorld = s.inWorld and true or false,
    }
end

local function SettingsInfo()
    local L = R.SettingsLauncher
    if not L then return { state = "unknown" } end
    local snap = L.Snapshot()
    local presence = Presence(L.COMPANION)
    local state
    if snap.loaded then state = "loaded"
    elseif presence == "loaded" then state = "incomplete"   -- the game loaded it and it did not start (L.Load's INCOMPLETE)
    elseif presence == "missing" then state = "not-installed"
    elseif presence == "disabled" then state = "disabled"
    elseif presence == "not-loaded" then state = "installed"
    else state = "unknown" end
    return { state = state, failed = Token(snap.failed, 24), attempts = snap.attempts or 0, version = Metadata(L.COMPANION, "Version") }
end

local function PendingInfo()
    local pending = { reloads = {}, held = {} }
    local W = R.Switches
    if W and W.PendingReloads then
        for _, key in ipairs(W.PendingReloads()) do
            pending.reloads[#pending.reloads + 1] = RELOAD_NAMES[key] or "another setting"
        end
    end
    local L = R.Life
    if L and L.Snapshot then
        local notes = L.Snapshot().notes
        for code, n in pairs(notes) do
            if Token(code, 32) and type(n) == "number" then pending.held[#pending.held + 1] = { code = code, n = n } end
        end
        table.sort(pending.held, function(a, b) return a.code < b.code end)
        while #pending.held > MAX_HELD do table.remove(pending.held) end
    end
    return pending
end

local function Capability(group, def)
    local ok, result = pcall(def.check)
    if not ok or type(result) ~= "table" then result = Result("unknown", "check-failed", nil) end
    local state = result.state
    local rec = {
        id = def.id, group = group.key, label = def.label, state = state, code = Token(result.code, 32) or "unknown",
        why = result.why, wanted = result.wanted and true or false, folder = def.folder,
    }
    rec.stateLabel = (def.labels and def.labels[state]) or S.LABELS[state] or S.LABELS.unknown
    -- A warning color is for something wanted that is not available and that the person can do something about.
    rec.actionable = result.actionable == true and state ~= "available"
    local parts = {}
    if result.why then parts[#parts + 1] = result.why end
    if MISSING[state] then
        parts[#parts + 1] = "Affects " .. def.affects .. "."
        parts[#parts + 1] = def.fallback
    end
    local todo = (def.todo and def.todo[state]) or TODO[state]
    if todo then parts[#parts + 1] = todo end
    rec.detail = #parts > 0 and table.concat(parts, " ") or nil
    return rec
end

-- The snapshot: everything below is read now and held only by whoever asked.
function S.Collect()
    local snap = {
        version = VersionInfo(), client = ClientInfo(), core = CoreInfo(), settings = SettingsInfo(), pending = PendingInfo(),
        groups = {}, groupList = {}, caps = {}, capList = {}, features = {},
    }
    for _, g in ipairs(S.GROUPS) do
        local presence = g.folder and Presence(g.folder) or nil
        local group = { key = g.key, title = g.title, fold = g.fold and true or false, presence = presence,
            version = (g.folder and presence == "loaded") and Metadata(g.folder, "Version") or nil, caps = {} }
        snap.groups[g.key] = group
        snap.groupList[#snap.groupList + 1] = group
        for _, def in ipairs(g.caps) do
            local rec = Capability(g, def)
            group.caps[#group.caps + 1] = rec
            snap.caps[rec.id] = rec
            snap.capList[#snap.capList + 1] = rec
        end
    end
    for _, f in ipairs(S.FEATURES) do
        local key, name = f[1], f[2]
        local state = "off"
        if not Available(key) then state = "not-applicable" elseif On(key) then state = "on" end
        snap.features[#snap.features + 1] = { key = key, name = name, state = state }
    end
    local MS = R.MageSell
    if MS and MS.ForPlayer and MS.ForPlayer() and Available("mageSell") then
        snap.mageSellMode = MS.Mode() == "ellesmere" and "mark as junk with EllesmereUI" or "sell directly"
    end
    return snap
end

-- A folded group's line while it is not there (shown only when nothing in it is wanted).
function S.GroupDetail(group)
    local parts = {}
    for _, def in ipairs(S.GROUPS) do
        if def.key == group.key then
            for _, cap in ipairs(def.caps) do parts[#parts + 1] = cap.label .. ": " .. cap.fallback end
        end
    end
    return "Optional; TwichUI works without it. " .. table.concat(parts, " ")
end

-- A group's own word: "Not installed", "Turned off in the AddOns list", "Installed, not loaded", "Loaded".
function S.PresenceLabel(group)
    if group.presence == "loaded" then return "Loaded" end
    local state = PRESENCE_STATE[group.presence]
    return state and S.LABELS[state] or S.LABELS.unknown
end
function S.PresenceWord(group) return PRESENCE_WORD[group.presence] or PRESENCE_WORD.unknown end

---------------------------------------------------------------------------
-- The summary the page shows: { label, value, detail, warn } for each line, from a snapshot
---------------------------------------------------------------------------
function S.Summary(snap)
    local rows = {}
    local function Add(id, label, value, detail, warn) rows[#rows + 1] = { id = id, label = label, value = value, detail = detail, warn = warn } end
    local v = snap.version
    Add("version", "TwichUI version", v.text or "Unknown",
        not v.text and "The addon list gave no version for TwichUI." or nil)
    Add("channel", "Release channel", v.channel or "Unknown",
        not v.channel and "Only alpha and beta builds record their channel in the version. A plain version number could be a stable release or an unpackaged copy, so it is not guessed." or nil)
    local c = snap.client
    Add("client", "Game client", c.version and (c.version .. (c.build and (" (build " .. c.build .. ")") or "")) or "Unknown",
        (c.interface and c.addonInterface and c.interface ~= c.addonInterface)
            and ("TwichUI is marked for interface " .. c.addonInterface .. "; this client reports " .. c.interface .. ".") or nil)
    local k = snap.core
    local coreValue = ({ started = "Started", starting = "Still starting", problem = "Problem", unknown = "Unknown" })[k.state]
    local coreDetail
    if k.state == "problem" then
        coreDetail = k.savedVariables == "failed" and "Saved data did not load. /tui diagnostics has the details."
            or (k.hooksFailed .. " start-up step(s) raised an error. /tui diagnostics has the error.")
    elseif k.state == "starting" then
        coreDetail = "Configuration is not ready yet. Press Refresh in a moment."
    end
    Add("core", "Core", coreValue, coreDetail, k.state == "problem")
    local s = snap.settings
    local settingsValue = ({ loaded = "Loaded this session", installed = "Installed, loads on demand", ["not-installed"] = "Not installed",
        disabled = "Turned off in the AddOns list", incomplete = "Loaded but did not start", unknown = "Unknown" })[s.state]
    local settingsDetail
    if s.state == "loaded" then
        settingsDetail = "TwichUI_Settings loads the first time the settings open, so this does not show it was loaded at startup."
            .. (s.failed and (" The last attempt to load it failed: " .. s.failed .. ".") or "")
    elseif s.failed then
        settingsDetail = "The last attempt to load it failed: " .. s.failed .. "."
    end
    Add("settings", "Settings window", settingsValue, settingsDetail, s.failed ~= nil and s.state ~= "loaded")
    local p = snap.pending
    if #p.reloads > 0 then
        Add("pending", "Reload needed", table.concat(p.reloads, ", "), "These changes take effect after you reload your UI.", false)
    else
        Add("pending", "Reload needed", "None",
            "Only changes that wait for a reload are tracked. Work held back for combat is counted in the full report, not tracked as pending.")
    end
    return rows
end

---------------------------------------------------------------------------
-- Cached snapshot for the settings page: collected on first use after it was cleared (the page opening, Refresh,
-- a profile or switch change), dropped when the settings close.
---------------------------------------------------------------------------
local current
function S.Current()
    if not current then current = S.Collect() end
    return current
end
function S.Refresh() current = S.Collect() return current end
function S.Invalidate() current = nil end

---------------------------------------------------------------------------
-- The support report
---------------------------------------------------------------------------
-- Plain text from a snapshot (a fresh one when none is given). Every line is built from the fields above.
function S.Report(snap)
    snap = snap or S.Collect()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    Add("TwichUI support information (format " .. S.FORMAT .. ")")
    Add("A snapshot of how TwichUI and its optional addons looked when this was made. It does not show that any feature works.")
    Add("")
    local v, c, k, s, p = snap.version, snap.client, snap.core, snap.settings, snap.pending
    Add("TwichUI version: " .. (v.text or "unknown"))
    Add("Release channel: " .. (v.channel or "unknown (only alpha and beta builds record it)"))
    Add(("Game client: version %s, build %s, interface %s, locale %s"):format(c.version or "unknown", c.build or "unknown",
        c.interface or "unknown", c.locale or "unknown"))
    if c.addonInterface then Add("TwichUI interface: " .. c.addonInterface) end
    Add(("Core: %s (saved data %s, configuration ready %s, start-up steps %d run / %d failed, logged in %s)"):format(
        k.state, k.savedVariables or "unknown", k.configReady and "yes" or "no", k.hooksRun or 0, k.hooksFailed or 0, k.loggedIn and "yes" or "no"))
    Add(("Settings window addon: %s%s%s; load attempts this session: %d%s"):format(
        s.state, s.version and (", version " .. s.version) or "", s.state == "loaded" and " (it loads when settings are first opened)" or "",
        s.attempts or 0, s.failed and (", last failure " .. s.failed) or ""))
    Add("Reload needed: " .. (#p.reloads > 0 and table.concat(p.reloads, ", ") or "none"))
    if #p.held > 0 then
        local list = {}
        for _, h in ipairs(p.held) do list[#list + 1] = ("%s x%d"):format(h.code, h.n) end
        Add("Work held back since the game started (counts, not pending now): " .. table.concat(list, ", "))
    else
        Add("Work held back since the game started: none")
    end
    Add("")
    Add("Optional integrations")
    for _, g in ipairs(snap.groupList) do
        local head = g.title
        if g.presence then
            head = head .. ": " .. S.PresenceWord(g) .. (g.version and (", version " .. g.version) or "")
        end
        Add(head)
        for _, cap in ipairs(g.caps) do
            -- the code only where it says more than the state (not "addon-missing" beside "not installed")
            local code = (cap.state ~= "available" and cap.code ~= "unknown" and cap.code ~= cap.state and not cap.code:find("^addon%-")) and (" (" .. cap.code .. ")") or ""
            Add(("  %s: %s%s"):format(cap.label, (cap.stateLabel:gsub("^%a", string.lower)), code))
        end
    end
    Add("")
    Add("Features (switches only; a switch being on says nothing about whether the feature works)")
    local on, off, na = {}, {}, {}
    for _, f in ipairs(snap.features) do
        local list = f.state == "on" and on or (f.state == "off" and off or na)
        list[#list + 1] = f.name
    end
    Add("  on: " .. (#on > 0 and table.concat(on, ", ") or "none"))
    Add("  off: " .. (#off > 0 and table.concat(off, ", ") or "none"))
    if #na > 0 then Add("  not applicable here: " .. table.concat(na, ", ")) end
    if snap.mageSellMode then Add("  Mage selling handling: " .. snap.mageSellMode) end
    Add("")
    Add("Left out on purpose: character, account, realm, guild and friend names; chat; Journey Chronicle entries; inventory; "
        .. "saved data, backups and share payloads; file paths; text you typed; other addons. Read this before you share it.")
    return table.concat(lines, "\n")
end
