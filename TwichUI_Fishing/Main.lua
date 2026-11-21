-- TwichUI Fishing: start-up, events and /tui fish
-- Loaded by the core's FishingLauncher.lua (never in combat). Its saved variable is read when the game says this addon has
-- loaded; until then nothing is recorded. All events go through the core's event bus (R:On / R:Off), each listener once.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Ses = F.Session
local G = F.Gear
local L = F.Lure
local C = F.Containers
local Lo = F.Loot
local A = F.Action
local API = F.API
local M = {}
F.Main = M

local Perf = R.Perf
local listening = {}      -- [event] = fn while registered
local ticker

local function Bags()
    C.Classify()
    if not Lo.Open() and not Lo.Waiting() and not C.Pending() then
        C.Reconcile()
        C.RememberCounts()
    end
end

local function OnUnitInventory(unit) if unit == "player" then L.OnEnchantChanged() end end

local function OnWorld()
    G.Reconcile()
    A.Sync()
    if not A.LineOut() then A.RestoreTargeting() end
    if G.State() ~= "none" and not Ses.Current() and S.Get("gear.restoreOnEnd") and C_Timer and C_Timer.After then
        C_Timer.After(2, function() if not Ses.Current() and G.State() ~= "none" then G.Restore("login") end end)
    end
end

local function OnLogout() A.RestoreTargeting() end

local EVENTS = {
    UNIT_SPELLCAST_CHANNEL_START = A.OnChannelStart,
    UNIT_SPELLCAST_CHANNEL_STOP = A.OnChannelStop,
    UNIT_SPELLCAST_FAILED = A.OnFailed,
    UNIT_SPELLCAST_INTERRUPTED = A.OnInterrupted,
    LOOT_READY = Perf.Wrap("fishing.loot", Lo.OnReady),
    LOOT_OPENED = Perf.Wrap("fishing.loot", Lo.OnOpened),
    LOOT_SLOT_CLEARED = Perf.Wrap("fishing.loot", Lo.OnSlotCleared),
    LOOT_CLOSED = Perf.Wrap("fishing.loot", Lo.OnClosed),
    CHAT_MSG_LOOT = Lo.OnChat,
    PLAYER_EQUIPMENT_CHANGED = G.OnEquipmentChanged,
    WEAPON_ENCHANT_CHANGED = L.OnEnchantChanged,
    UNIT_INVENTORY_CHANGED = OnUnitInventory,
    BAG_UPDATE_DELAYED = Perf.Wrap("fishing.bags", Bags),
    PLAYER_REGEN_DISABLED = A.OnCombatStart,
    PLAYER_REGEN_ENABLED = A.OnCombatEnd,
    UPDATE_BINDINGS = A.OnBindings,
    SPELLS_CHANGED = A.OnSpells,
    PLAYER_ENTERING_WORLD = OnWorld,
    PLAYER_LOGOUT = OnLogout,
    UI_ERROR_MESSAGE = function(_, message) C.OnError(message) end,
    ADDON_ACTION_BLOCKED = C.OnBlocked,
    ADDON_ACTION_FORBIDDEN = C.OnBlocked,
}

-- Registers what is wanted now: everything while turned on (the soft-target event only while a line is out), nothing off.
function M.Listen()
    local want = {}
    if F.ready and S.Get("enabled") then
        for e, fn in pairs(EVENTS) do want[e] = fn end
        if A.LineOut() then want.PLAYER_SOFT_INTERACT_CHANGED = A.OnSoftTarget end
    end
    for e, fn in pairs(listening) do
        if want[e] ~= fn then R:Off(e, fn); listening[e] = nil end
    end
    for e, fn in pairs(want) do
        if not listening[e] then R:On(e, fn); listening[e] = fn end
    end
end

function M.Listening(event) return listening[event] ~= nil end

local function StartTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(60, function() Ses.CheckIdle() end)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

F.Subscribe("SESSION_START", function() StartTicker(); A.Refresh() end)
F.Subscribe("SESSION_END", function() StopTicker(); A.Refresh() end)

function M.Init()
    if F.ready then return end
    local ok, err = pcall(S.Load)
    if not ok then
        R.Fault("fishing saved data", err)
        S.held = true
    end
    F.ready = true
    A.Build()
    if not S.held then
        Ses.CheckIdle()
        if Ses.Current() then StartTicker() end
        if R.Life and R.Life.InWorld and R.Life.InWorld() then OnWorld() end
    end
    A.Refresh()
    M.Listen()
    Perf.Gauge("fishing.queue", { label = "Fishing: unopened containers queued", unit = "count", kind = "state",
        read = function() return C.Status().unopened end })
    Perf.Gauge("fishing.sessions", { label = "Fishing: completed sessions kept", unit = "count", kind = "cache",
        read = function() local c = S.Char(); return c and #c.sessions or 0 end })
    Perf.Gauge("fishing.listeners", { label = "Fishing: notification listeners", unit = "count", kind = "listeners",
        read = function() return F.SubscriberCount() end })
end

R:On("ADDON_LOADED", function(name)
    if name == F.ADDON then M.Init() end
end)

---------------------------------------------------------------------------
-- Turning it on and off
---------------------------------------------------------------------------
function M.SetEnabled(on)
    local ok, why = S.Set("enabled", on and true or false)
    if not ok then return false, why end
    if not on then A.Teardown() end
    M.Listen()
    A.Sync()
    return true
end

---------------------------------------------------------------------------
-- /tui fish
---------------------------------------------------------------------------
local function Say(fmt, ...) R.Print("fishing: " .. fmt, ...) end

local function OnOff(word)
    word = (word or ""):lower()
    if word == "on" or word == "yes" or word == "true" then return true end
    if word == "off" or word == "no" or word == "false" then return false end
    return nil
end

local function Item(arg)
    arg = arg or ""
    if arg:lower() == "none" or arg == "" then return false end
    return F.ItemID(arg) or (arg:match("^%d+$") and tonumber(arg)) or nil
end

local REFUSED = { held = "your fishing records were saved by a newer TwichUI and are kept unchanged.", invalid = "that value doesn't fit.",
    ["not-ready"] = "not ready yet.", unknown = "unknown setting." }

local function Set(path, value, done)
    local ok, why = S.Set(path, value)
    if ok then Say("%s", done) else Say("%s", REFUSED[why] or tostring(why)) end
    return ok
end

local HELP = {
    "/tui fish - status: state, session, lure, gear, containers and recent errors",
    "/tui fish on|off - TwichUI Fishing itself",
    "/tui fish start|stop - begin or end a session (one also begins with your first cast)",
    "/tui fish restore - put your own gear back now; forget - drop the saved gear without restoring",
    "/tui fish pole <item|none>, outfit <equipment set|none>, gear on|off, combatweapons on|off",
    "/tui fish lure <item|none>, lure auto on|off, lure alternative on|off, lure early <seconds>",
    "/tui fish containers queue|auto|off, containers key on|off",
    "/tui fish idle <minutes>, reel target|mouseover, interact on|off (adjust interaction targeting while a line is out)",
    "Keys: Key Bindings > TwichUI > Fishing (no key is bound until you choose one).",
}

function M.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "" or word == "status" then
        for _, line in ipairs(API.Report()) do print(R.GREY .. "  " .. line .. "|r") end
        return
    end
    if word == "help" then for _, line in ipairs(HELP) do print(R.GREY .. "  " .. line .. "|r") end return end
    if word == "on" or word == "off" then
        local ok, why = M.SetEnabled(word == "on")
        if ok then Say("turned %s.", word) else Say("%s", REFUSED[why] or tostring(why)) end
        return
    end
    if S.held then Say("%s", REFUSED.held) return end
    if word == "start" then
        if Ses.Current() then Say("a session is already in progress.") else Ses.Start("command"); Say("session started.") end
    elseif word == "stop" then
        local s = Ses.End("command")
        if s then Say("session %d ended: %s, %d catches, %d items.", s.id, API.Duration(s.seconds), s.catches, s.items)
        else Say("no session in progress.") end
    elseif word == "restore" then
        local r = G.Restore("command")
        local text = { nothing = "nothing to put back.", done = "your gear is already back.", pending = "putting your gear back.",
            combat = "not during combat: it will wait until combat ends, or press the fishing key.",
            unsupported = "this client can't do it from here: press the fishing key to put it back." }
        Say("%s", text[r] or r)
    elseif word == "forget" then
        if G.Forget() then Say("the gear saved before fishing was forgotten; nothing was changed.") else Say("no saved gear.") end
    elseif word == "pole" then
        local v = Item(rest)
        if v == nil then Say("usage: /tui fish pole <item link or id | none>") return end
        Set("gear.pole", v, v and ("preferred pole set to item " .. v .. ".") or "no preferred pole: the best one in your bags is used.")
    elseif word == "outfit" then
        local v = rest ~= "" and rest:lower() ~= "none" and rest or false
        Set("gear.outfit", v, v and ("outfit set to equipment set \"" .. v .. "\".") or "no fishing outfit.")
    elseif word == "gear" or word == "combatweapons" then
        local v = OnOff(rest)
        if v == nil then Say("usage: /tui fish %s on|off", word) return end
        Set(word == "gear" and "gear.manage" or "gear.combatWeapons", v, word .. " " .. (v and "on." or "off."))
    elseif word == "lure" then
        local sub, val = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "auto" or sub == "alternative" then
            local v = OnOff(val)
            if v == nil then Say("usage: /tui fish lure %s on|off", sub) return end
            Set("lure." .. sub, v, "lure " .. sub .. " " .. (v and "on." or "off."))
        elseif sub == "early" then
            Set("lure.early", tonumber(val), "a lure is renewed when the one on the pole has " .. tostring(val) .. " seconds left.")
        else
            local v = Item(rest)
            if v == nil then Say("usage: /tui fish lure <item link or id | none>, or lure auto|alternative on|off") return end
            Set("lure.preferred", v, v and ("preferred lure set to item " .. v .. ".") or "no preferred lure: the best one in your bags is used.")
        end
    elseif word == "containers" then
        local sub, val = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        if sub == "key" then
            local v = OnOff(val)
            if v == nil then Say("usage: /tui fish containers key on|off") return end
            Set("containers.openWithKey", v, "the fishing key " .. (v and "opens" or "no longer opens") .. " queued containers between casts.")
        elseif sub == "queue" or sub == "auto" or sub == "off" then
            Set("containers.mode", sub, "container processing: " .. sub .. (sub == "auto" and " (falls back to the queue if the game refuses)." or "."))
        else
            Say("usage: /tui fish containers queue|auto|off, or containers key on|off")
        end
    elseif word == "idle" then
        Set("session.idleMinutes", tonumber(rest), "a session ends after " .. tostring(rest) .. " minutes without fishing.")
    elseif word == "reel" then
        local v = rest:lower() == "mouseover" and "INTERACTMOUSEOVER" or rest:lower() == "target" and "INTERACTTARGET" or nil
        if not v then Say("usage: /tui fish reel target|mouseover") return end
        if Set("action.reel", v, "reeling uses " .. v .. ".") then A.Sync() end
    elseif word == "interact" then
        local v = OnOff(rest)
        if v == nil then Say("usage: /tui fish interact on|off") return end
        if Set("interact.adjust", v, v and "interaction targeting is adjusted while a line is out, and put back after."
            or "interaction targeting is left as you set it.") and not v then A.RestoreTargeting() end
    else
        Say("unknown option '%s'. Type /tui fish help.", word)
    end
end
