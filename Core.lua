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
    welcomeBack = true,      -- a small bookmark at login: the Chronicle's last noted place and when
    arrival = true,          -- title card when arriving in a new zone (in place of the game's zone text)
    arrivalSubzones = true,  -- ... and a quieter one for smaller places within a zone
    arrivalDungeons = true,  -- ... a card with the name when walking into a dungeon or raid
    arrivalReducedMotion = false, -- ... fade only, no upward settle
    trainingNotice = true,   -- a small card after a level-up when new class spells or ranks are available to train
    friendLogin = true,      -- a small card when a Battle.net friend comes online, in place of the game's own pop-up
    friendLoginSound = true, -- ... with a soft chime (TwichUI Notification)
    foodDrink = false,       -- Food and Drink buttons: you click, they eat or drink the best food or drink in your bags (opt-in)
    foodDrinkFood = true,    -- ... the Food button
    foodDrinkDrink = true,   -- ... the Drink button
    mageTravel = true,       -- Mage Travel launcher on a data bar: teleports and portals, cast by your click (Mages only)
    mageConjure = true,      -- Mage Conjuring launcher on a data bar: food and water ranks, cast by your click (Mages only)
    mageRefreshments = false, -- Mage refreshments panel: plan food and water for your group, conjure by click or key, a checklist (Mages only, opt-in)
    mageRefreshmentsTrade = true, -- ... and a Fill trade button under the trade window, and counting completed trades (needs the one above)
    mageRefreshmentsAutoFill = true, -- ... and filling a group member's trade by itself when it opens (needs the one above)
    auctionPosting = true,   -- "Sell from Bags" tab in the Auction House (searches only when you pick an item)
    qolSummons = false,      -- Quality of Life (all opt-in, see qol/QoL.lua): accept summons
    qolResurrect = false,    -- ... accept a resurrection offered to you
    qolResurrectCombat = false, -- ... including a combat resurrection (needs the one above)
    qolReleasePvP = false,   -- ... release your spirit after dying in a battleground
    qolDuels = false,        -- ... decline duel requests (except from the people you choose)
    qolDuelsToDeath = false, -- ... and duels to the death (needs the one above)
    qolQuickKeybind = false, -- ... a Quick Keybind button in the Game Menu
}
R.DEFAULT_MODULES = DEFAULT_MODULES   -- Settings.lua uses these for the panel's Defaults button

function R.Print(fmt, ...)
    print((R.GOLD .. "TwichUI:|r " .. fmt):format(...))
end

function R:Enabled(key)
    return TwichUIDB and TwichUIDB.modules and TwichUIDB.modules[key] ~= false
end

-- An error caught in one of our own handlers: noted for the troubleshooting report (if loaded), then
-- handed to the game's error handler exactly as before. Nothing is hidden or replaced.
local function Fault(source, err)
    if R.Diag then R.Diag.Error(source, err) end
    geterrorhandler()(err)
end
R.Fault = Fault

---------------------------------------------------------------------------
-- Fitting a window to the screen. TwichUI's windows are a fixed size in screen units, so a small game
-- window (or a high UI scale) can leave less room than a window needs, and its edge, close box or buttons
-- end up off screen. FitToScreen only ever makes a window smaller, and only as much as it takes; it sets
-- the scale from the window's own size each time (never multiplying an earlier result), so the window is
-- back at full size as soon as there is room. Text is never resized on its own. Cards and movers keep
-- their saved places and are not touched by this.
---------------------------------------------------------------------------
local FIT_MARGIN, FIT_MIN_SCALE = 24, 0.6

-- The scale (FIT_MIN_SCALE to 1) at which a width by height window fits a screen of those units, leaving a margin.
function R.FitScale(width, height, screenWidth, screenHeight)
    local function Usable(n) return type(n) == "number" and n == n and n > 0 and n < math.huge end
    if not (Usable(width) and Usable(height) and Usable(screenWidth) and Usable(screenHeight)) then return 1 end
    local scale = math.min(1, (screenWidth - FIT_MARGIN * 2) / width, (screenHeight - FIT_MARGIN * 2) / height)
    return math.max(FIT_MIN_SCALE, scale)
end

-- For a window parented to UIParent. Usable directly as an OnShow handler.
function R.FitToScreen(frame)
    if not (frame and UIParent) then return end
    local scale = R.FitScale(frame:GetWidth(), frame:GetHeight(), UIParent:GetWidth(), UIParent:GetHeight())
    if math.abs((frame:GetScale() or 1) - scale) > 0.001 then frame:SetScale(scale) end
end

---------------------------------------------------------------------------
-- Tiny event bus so modules can share one frame and run in a known order.
-- A listener may add or remove listeners (itself included) while its event is being delivered: the
-- delivery in progress still reaches every listener that is still registered, once, in order. A listener
-- removed during delivery is only marked (false) and the list is tidied when the delivery ends.
-- Registering the same function for the same event twice is one registration.
---------------------------------------------------------------------------
local listeners = {}

local function Tidy(event, list)
    for i = #list, 1, -1 do
        if not list[i] then table.remove(list, i) end
    end
    list.dirty = false
    if #list == 0 then
        listeners[event] = nil
        R.frame:UnregisterEvent(event)
    end
end

function R:On(event, fn)
    local list = listeners[event]
    if not list then
        list = { busy = 0 }
        listeners[event] = list
    end
    for i = 1, #list do
        if list[i] == fn then return end
    end
    table.insert(list, fn)
    R.frame:RegisterEvent(event)
end

-- Stops calling fn for event; the event itself is unregistered once nobody listens.
function R:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then
            if list.busy > 0 then
                list[i] = false
                list.dirty = true
            else
                table.remove(list, i)
            end
        end
    end
    if list.busy == 0 then Tidy(event, list) end
end

R.frame = CreateFrame("Frame")
R.frame:SetScript("OnEvent", function(_, event, ...)
    local list = listeners[event]
    if not list then return end
    list.busy = list.busy + 1
    for i = 1, #list do    -- the count as delivery began: listeners added meanwhile wait for the next one
        local fn = list[i]
        if fn then
            local ok, err = pcall(fn, ...)
            if not ok then Fault("event " .. event, err) end
        end
    end
    list.busy = list.busy - 1
    if list.busy == 0 and list.dirty then Tidy(event, list) end
end)

---------------------------------------------------------------------------
-- Where the addon is in its start-up, and the game's world state.
-- Distinct on purpose: code loaded, saved variables validated, configuration ready, startup hooks run,
-- logged in, and in the world. A feature being switched on is none of these. Features that need the
-- world (bags, location, friend lists) ask InWorld() and listen for PLAYER_ENTERING_WORLD to try again.
-- Reason codes are counted for /tui diagnostics: a short fixed vocabulary, never names or text.
---------------------------------------------------------------------------
local Life = {
    savedVariables = "pending",   -- "pending" | "ready" | "failed"
    configReady = false, hooksRun = 0, hookFailures = 0, loggedIn = false, worldEntries = 0,
    notes = {}, noteKinds = 0, notesDropped = 0,
}
R.Life = Life
local MAX_NOTE_KINDS = 32
local inWorld = false

function Life.InWorld() return inWorld end

-- Counts one occurrence of a reason code ("deferred-combat", "cancelled-stale", ...). Bounded.
function Life.Note(code)
    if type(code) ~= "string" then return end
    local n = Life.notes[code]
    if n then Life.notes[code] = n + 1
    elseif Life.noteKinds < MAX_NOTE_KINDS then Life.notes[code], Life.noteKinds = 1, Life.noteKinds + 1
    else Life.notesDropped = Life.notesDropped + 1 end
end

-- Read only, for /tui diagnostics.
function Life.Snapshot()
    local copy = {}
    for k, v in pairs(Life.notes) do copy[k] = v end
    return {
        savedVariables = Life.savedVariables, configReady = Life.configReady, hooksRun = Life.hooksRun,
        hookFailures = Life.hookFailures, loggedIn = Life.loggedIn, inWorld = inWorld, worldEntries = Life.worldEntries,
        notes = copy, notesDropped = Life.notesDropped,
    }
end

-- Registered here, before any module's listener, so the state is already right when theirs run.
R:On("PLAYER_LOGIN", function() Life.loggedIn = true end)
R:On("PLAYER_ENTERING_WORLD", function() inWorld = true; Life.worldEntries = Life.worldEntries + 1 end)
R:On("PLAYER_LEAVING_WORLD", function() inWorld = false end)

-- Hooks run once, right after our saved variables load (before other addons).
R.initHooks = {}
function R:OnInit(fn) table.insert(R.initHooks, fn) end

R.frame:RegisterEvent("ADDON_LOADED")
R.frame:HookScript("OnEvent", function(_, event, name)
    if event ~= "ADDON_LOADED" or name ~= ADDON then return end
    -- Schema, upgrade, defaults and damaged-data repair live in Persist.lua (see docs/persistence.md).
    local loaded, loadErr = pcall(R.Persist.LoadMain)
    Life.savedVariables = loaded and "ready" or "failed"
    if not loaded then Fault("saved data", loadErr) end
    -- Only matters if Persist failed part way: the rest of the addon needs these to be tables.
    if type(TwichUIDB) ~= "table" then TwichUIDB = {} end
    TwichUIBackupDB = type(TwichUIBackupDB) == "table" and TwichUIBackupDB or {}
    TwichUIShareDB = type(TwichUIShareDB) == "table" and TwichUIShareDB or {}   -- only your saved setup (what make_pack ships)
    if type(TwichUIDB.modules) ~= "table" then TwichUIDB.modules = {} end
    for k, v in pairs(DEFAULT_MODULES) do
        if TwichUIDB.modules[k] == nil then TwichUIDB.modules[k] = v end
    end
    Life.configReady = true
    for i, fn in ipairs(R.initHooks) do
        local ok, err = pcall(fn)
        Life.hooksRun = Life.hooksRun + 1
        if not ok then
            Life.hookFailures = Life.hookFailures + 1
            Life.Note("init-failed")
            Fault("startup hook " .. i, err)
        end
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
            if not ok then Fault("EllesmereUI skin", err) end
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
-- Returns true when the game was asked to open it, false when TwichUI's options aren't there (yet).
function R:OpenSettings(key)
    local category = R.settingsCategories and R.settingsCategories[key or "overview"] or R.settingsCategory
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
    return false
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
    { name = "data", usage = "data", desc = "what your addons keep between sessions (read-only)", fn = function()
        if R.StoredDataWindow then R.StoredDataWindow:Show() else Unavailable("Addon data") end
    end },
    { name = "gear", usage = "gear", desc = "stat weights for upgrade hints", fn = function()
        if R.GearWindow then R.GearWindow:Show() else Unavailable("Gear window") end
    end },
    { name = "chronicle", usage = "chronicle", desc = "your journey chronicle", fn = function()
        if R.ChronicleWindow then R.ChronicleWindow:Toggle() else Unavailable("Journey Chronicle") end
    end },
    { name = "refreshments", usage = "refreshments", desc = "Mage refreshments panel (Mages)", fn = function()
        if R.RefreshmentsPanel then R.RefreshmentsPanel.Toggle() else Unavailable("Mage refreshments") end
    end },
    { name = "about", usage = "about", desc = "show the TwichUI welcome again", fn = function()
        if R.Welcome then R.Welcome.Show() else Unavailable("The welcome") end
    end },
    { name = "welcome", usage = "welcome", desc = "preview the Chronicle's Welcome Back bookmark now", fn = function()
        if not R.WelcomeBack then Unavailable("Welcome Back") return end
        local ok, why = R.WelcomeBack.Preview()
        if not ok then R.Print(why) end
    end },
    { name = "training", usage = "training [level]", desc = "preview the new training card for a level", fn = function(arg)
        if not R.Training then Unavailable("New training") return end
        local level = (arg or ""):match("^(%d+)$")
        local ok, why
        if level then ok, why = R.Training.Preview(tonumber(level))
        elseif (arg or "") == "" then ok, why = R.Training.Preview()
        else ok, why = false, "Type /tui training, or /tui training 20 for another level." end
        if not ok then R.Print(why) end
    end },
    { name = "friend", usage = "friend", desc = "preview the Battle.net friend login card now", fn = function()
        if R.FriendLogin then R.FriendLogin.Preview() else Unavailable("Friend login") end
    end },
    { name = "diagnostics", usage = "diagnostics [start|stop|clear|status]", desc = "troubleshooting report to copy; start or stop tracing", fn = function(arg)
        if R.DiagWindow then R.DiagWindow.Command(arg) else Unavailable("Troubleshooting") end
    end },
    { name = "hidden", usage = "hidden", desc = "welcome messages hidden at login", fn = function()
        if R.Quiet then R.Quiet:ShowHidden() else Unavailable("Quiet login") end
    end },
    { name = "skin", usage = "skin [apply]", desc = "Auctionator skin status; apply re-runs it", fn = function(arg)
        if R.SkinCommand then R.SkinCommand(arg) else Unavailable("Auctionator skin") end
    end },
    { name = "commtest", usage = "commtest party|guild|direct <name>", desc = "test addon messages with another TwichUI user", fn = function(arg)
        if R.CommTest then R.CommTest.Run(arg) else Unavailable("Comm test") end
    end },
    -- Kept for checking the Food and Drink buttons' item rules against the game; also /tui diagnostics probe.
    { name = "probe", usage = "probe", desc = "list what the game says about consumables in your bags", hidden = true, fn = function()
        if R.FoodDrinkProbe then R.FoodDrinkProbe.Run() else Unavailable("Probe") end
    end },
    -- The old temporary friend diagnostics now live in /tui diagnostics.
    { name = "frienddiag", usage = "frienddiag", desc = "now /tui diagnostics", hidden = true, fn = function(arg)
        if R.DiagWindow then R.DiagWindow.LegacyFriendDiag(arg) else Unavailable("Troubleshooting") end
    end },
    { name = "troubleshoot", alias = "diagnostics", hidden = true },
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
