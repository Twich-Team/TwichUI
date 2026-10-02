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
    groupCheck = false,      -- version hello / group check / DM probe (group channel, opt-in)
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
    -- 3.0.0 turned group check on by default; it's opt-in from 3.0.1, so
    -- switch it off once for anyone who got the old default.
    if (TwichUIDB.migrated or 0) < 301 then
        TwichUIDB.modules.groupCheck = nil
        TwichUIDB.migrated = 301
    end
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
function R:OpenSettings()
    if R.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(R.settingsCategory:GetID())
    end
end

function TwichUI_OnCompartmentClick(_, button)
    if button == "RightButton" then R:OpenSettings()
    elseif R.Window then R.Window:Toggle() end
end

SLASH_TWICHUI1 = "/twichui"
SlashCmdList.TWICHUI = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "hidden" and R.Quiet then R.Quiet:ShowHidden()
    elseif msg == "check" and R.Group then R.Group:RunCheck()
    elseif msg == "version" and R.Group then R.Print("version %s.", R.Group.Version())
    elseif msg == "restore" and R.Window then R.Window:Show("backups")
    elseif msg == "gear" and R.GearWindow then R.GearWindow:Show()
    elseif msg == "help" or msg == "?" then
        R.Print("commands:")
        print("  /twichui - options")
        print("  /pack - share setup, received setups and backups window")
        print("  /pack test - send your setup to yourself")
        print("  /pack status - what sharing is doing (for bug reports)")
        print("  /twichui check - check your group's TwichUI versions and missing addons")
        print("  /twichui restore - backups")
        print("  /twichui gear - stat weights and stat priority for upgrade hints")
        print("  /twichui hidden - welcome messages hidden at login")
        print("  /twichui version - your TwichUI version")
        print("  /aeskin - Auctionator skin status (/aeskin apply to re-run it)")
    else
        R:OpenSettings()
    end
end

function TwichUI_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText("TwichUI", 1, 1, 1)
    GameTooltip:AddLine("Left-click: share and back up your setup", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end
function TwichUI_OnCompartmentLeave() GameTooltip:Hide() end

SLASH_TWICHUIPACK1 = "/pack"
SlashCmdList.TWICHUIPACK = function(msg)
    if not R:Enabled("setupSharing") then
        R.Print("Configuration Sharing is turned off. Turn it on in /twichui.")
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
