-- TwichUI: core
-- The folder starts with "!!!" so the game loads it before other addons.
-- Setup Sharing depends on that (see setup/Setups.lua); media also benefits,
-- since fonts and sounds are registered before any addon builds its lists.

local ADDON = ...
local R = {}
_G.TwichUI = R
R.ADDON = ADDON
R.PATH = [[Interface\AddOns\]] .. ADDON .. [[\]]
R.ICON = R.PATH .. [[media\icon]]
R.GOLD = "|cffC9A24A"
R.GREY = "|cff8a857c"
R.RED = "|cffc0504a"
R.GREEN = "|cff8FB35A"

local DEFAULT_MODULES = {
    media = true,            -- fonts and sounds for LibSharedMedia
    auctionatorSkin = true,  -- EllesmereUI look for Auctionator
    whatsTrainingSkin = true, -- EllesmereUI look for WhatsTraining's window
    foreverDungeonJournalSkin = true, -- EllesmereUI look for Forever Dungeon Journal
    attuneSkin = true,       -- EllesmereUI look for Attune
    setupSharing = true,     -- capture / send / receive / apply setups
    acceptSetups = true,     -- let friends offer setups (always asks first)
    quietLogin = true,       -- hide addon welcome messages at login/reload
    gearHints = true,        -- "Likely upgrade" line in item tooltips (stat weights: /twichui gear)
    gearBagIcons = false,    -- ... and a mark on upgrades in your bags (opt-in)
    shareWhisper = true,     -- configuration sharing over direct addon messages
    shareGroup = false,      -- ... over the group channel (opt-in)
    shareGuild = false,      -- ... over the guild channel (opt-in)
    groupCheck = true,       -- version hello / group check / DM probe (group channel)
    chronicle = true,        -- Journey Chronicle: write automatic entries (your own notes always work)
    chronicleLevels = true,  -- ... level milestones
    chronicleZones = true,   -- ... arriving in a new zone
    chronicleBosses = true,  -- ... defeating an encounter
    chronicleDeaths = false, -- ... dying (off until chosen, even with the rest on)
    chronicleGold = true,    -- ... gold earned milestones (10, 50, 100 ... 10,000)
    chronicleRiding = true,  -- ... learning a new Riding rank
    chronicleProfessions = true, -- ... learning a profession and reaching its skill milestones
    chronicleSound = true,   -- a soft page-turn sound when the Chronicle opens
    chronicleChat = true,    -- ... and say so in your own chat frame when an automatic entry is added
    arrival = true,          -- title card when arriving in a new zone (in place of the game's zone text)
    arrivalSubzones = true,  -- ... and a quieter one for smaller places within a zone
    arrivalReducedMotion = false, -- ... fade only, no upward settle
}
R.DEFAULT_MODULES = DEFAULT_MODULES   -- Settings.lua uses these for the panel's Defaults button

function R.Print(fmt, ...)
    print((R.GOLD .. "TwichUI:|r " .. fmt):format(...))
end

function R:Enabled(key)
    return TwichUIDB and TwichUIDB.modules and TwichUIDB.modules[key] ~= false
end

---------------------------------------------------------------------------
-- Tiny event bus so modules can share one frame and run in a known order.
---------------------------------------------------------------------------
local listeners = {}
function R:On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
    R.frame:RegisterEvent(event)
end

-- Stops calling fn for event; the event itself is unregistered once nobody listens.
function R:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
    if #list == 0 then
        listeners[event] = nil
        R.frame:UnregisterEvent(event)
    end
end

R.frame = CreateFrame("Frame")
R.frame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Hooks run once, right after our saved variables load (before other addons).
R.initHooks = {}
function R:OnInit(fn) table.insert(R.initHooks, fn) end

R.frame:RegisterEvent("ADDON_LOADED")
R.frame:HookScript("OnEvent", function(_, event, name)
    if event ~= "ADDON_LOADED" or name ~= ADDON then return end
    TwichUIDB = TwichUIDB or {}
    TwichUIBackupDB = TwichUIBackupDB or {}
    TwichUIShareDB = TwichUIShareDB or {}   -- only your saved setup (what make_pack ships)
    TwichUIDB.modules = TwichUIDB.modules or {}
    for k, v in pairs(DEFAULT_MODULES) do
        if TwichUIDB.modules[k] == nil then TwichUIDB.modules[k] = v end
    end
    for _, fn in ipairs(R.initHooks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end)

---------------------------------------------------------------------------
-- EllesmereUI skinning. We load before EllesmereUI, so register once it has
-- loaded. EllesmereUI hands us its skin toolkit (S) at login, if the user
-- has third-party skins switched on. S stays nil otherwise; every consumer
-- falls back to a plain look.
---------------------------------------------------------------------------
R.S = nil
R.skinCallbacks = {}
function R:OnSkin(fn)
    if R.S then fn(R.S) else table.insert(R.skinCallbacks, fn) end
end

local function RegisterWithEllesmere()
    if R.euiRegistered or not (EllesmereUI and EllesmereUI.RegisterSkin) then return end
    R.euiRegistered = true
    EllesmereUI.RegisterSkin("TwichUI", function(S)
        R.S = S
        for _, fn in ipairs(R.skinCallbacks) do
            local ok, err = pcall(fn, S)
            if not ok then geterrorhandler()(err) end
        end
        wipe(R.skinCallbacks)
    end)
end

R:On("ADDON_LOADED", function(name)
    if name == "EllesmereUI" then RegisterWithEllesmere() end
end)
R:On("PLAYER_LOGIN", RegisterWithEllesmere)   -- in case EllesmereUI loaded oddly

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------
-- key: a page under TwichUI (see Settings.lua); the overview when omitted.
function R:OpenSettings(key)
    local category = R.settingsCategories and R.settingsCategories[key or "overview"] or R.settingsCategory
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

function TwichUI_OnCompartmentClick(_, button)
    if button == "RightButton" then R:OpenSettings()
    elseif R.Window then R.Window:Toggle() end
end

---------------------------------------------------------------------------
-- Slash commands: /twichui and /tui share one parser.
-- /pack and /aeskin are gone; use /tui share and /tui skin.
---------------------------------------------------------------------------
local COMMANDS   -- ordered: { name, usage, description, fn(arg) }

local function Unavailable(what) R.Print("%s isn't available right now.", what) end

local function ShowHelp()
    R.Print("/tui (or /twichui) commands:")
    for _, c in ipairs(COMMANDS) do
        if not c.hidden then print(("  %s/tui %s|r %s- %s|r"):format(R.GOLD, c.usage, R.GREY, c.desc)) end
    end
end

COMMANDS = {
    { name = "help", usage = "help", desc = "this list", fn = ShowHelp },
    { name = "options", usage = "options", desc = "open TwichUI options", fn = function() R:OpenSettings() end },
    { name = "share", usage = "share [test|status]", desc = "share setup window; test sends to yourself", fn = function(arg)
        R.ShareCommand(arg)
    end },
    { name = "check", usage = "check", desc = "group's TwichUI versions and missing addons", fn = function()
        if R.Group then R.Group:RunCheck() else Unavailable("Group check") end
    end },
    { name = "version", usage = "version", desc = "your TwichUI version", fn = function()
        if R.Group then R.Print("version %s.", R.Group.Version()) else Unavailable("Version") end
    end },
    { name = "restore", usage = "restore", desc = "backups window", fn = function()
        if R.Window then R.Window:Show("backups") else Unavailable("Backups") end
    end },
    { name = "gear", usage = "gear", desc = "stat weights for upgrade hints", fn = function()
        if R.GearWindow then R.GearWindow:Show() else Unavailable("Gear window") end
    end },
    { name = "chronicle", usage = "chronicle", desc = "your journey chronicle", fn = function()
        if R.ChronicleWindow then R.ChronicleWindow:Toggle() else Unavailable("Journey Chronicle") end
    end },
    { name = "hidden", usage = "hidden", desc = "welcome messages hidden at login", fn = function()
        if R.Quiet then R.Quiet:ShowHidden() else Unavailable("Quiet login") end
    end },
    { name = "skin", usage = "skin [apply]", desc = "Auctionator skin status; apply re-runs it", fn = function(arg)
        if R.SkinCommand then R.SkinCommand(arg) else Unavailable("Auctionator skin") end
    end },
    -- TEMPORARY: remove with setup/CommTest.lua
    { name = "commtest", usage = "commtest party|guild|whisper <name>", desc = "test addon messages with another TwichUI user (temporary)", fn = function(arg)
        if R.CommTest then R.CommTest.Run(arg) else Unavailable("Comm test") end
    end },
    { name = "settings", alias = "options", hidden = true },
    { name = "config", alias = "options", hidden = true },
    { name = "journal", alias = "chronicle", hidden = true },
    { name = "notes", alias = "chronicle", hidden = true },
    { name = "?", alias = "help", hidden = true },
}

local function FindCommand(word)
    for _, c in ipairs(COMMANDS) do
        if c.name == word then return c.alias and FindCommand(c.alias) or c end
    end
    -- unique prefix of a command name, e.g. "res" for "restore"
    local hit, n = nil, 0
    for _, c in ipairs(COMMANDS) do
        if not c.alias and c.name:sub(1, #word) == word then hit, n = c, n + 1 end
    end
    if n == 1 then return hit end
    return nil, n
end

function R.RunCommand(msg)
    local word, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then ShowHelp() return end
    local cmd, ambiguous = FindCommand(word)
    if cmd then cmd.fn(arg) return end
    if ambiguous and ambiguous > 1 then
        R.Print("'%s' could mean more than one command. Type /tui help.", word)
    else
        R.Print("unknown command '%s'. Type /tui help.", word)
    end
end

SLASH_TWICHUI1 = "/twichui"
SLASH_TWICHUI2 = "/tui"
SlashCmdList.TWICHUI = R.RunCommand

function TwichUI_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("TwichUI", 1, 1, 1)
    GameTooltip:AddLine("Left-click: share and back up your setup", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end
function TwichUI_OnCompartmentLeave() GameTooltip:Hide() end

function R.ShareCommand(msg)
    if not R:Enabled("setupSharing") then
        R.Print("Configuration Sharing is turned off. Turn it on in /tui options.")
        return
    end
    if (msg or ""):lower():find("status") and R.Share then
        R.Share:Status()
        return
    end
    if (msg or ""):lower():find("test") and R.Share then
        local ok, why = R.Share:SendToSelf()
        if not ok then R.Print(why) end
        return
    end
    if R.Window then R.Window:Toggle() end
end
