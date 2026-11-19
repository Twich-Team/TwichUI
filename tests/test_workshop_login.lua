-- Safe login loading over the real core lifecycle; game loading is a controlled stand-in.
dofile(TESTS .. "harness.lua")
local function Setup(on, failure)
    local c = MakeClient("Rich", { "!!!TwichUI" })
    local timers, loads, generation, faults = {}, 0, 0, 0
    c.geterrorhandler = function() return function() faults = faults + 1 end end
    c.TwichUIDB = { modules = {}, ui = on and { workshopLoadOnLogin = true } or {} }
    c.C_Timer = { After = function(delay, fn)
        if debug.getinfo(2, "S").source:find("WorkshopLauncher", 1, true) then
            assert(delay == 2); timers[#timers + 1] = fn
        end
    end }
    c.InCombatLockdown = function() return c.COMBAT == true end
    c.debugprofilestop = function() return os.clock() * 1000 end
    c.C_AddOns.LoadAddOn = function(name)
        assert(name == "TwichUI_Workshop"); loads = loads + 1
        if failure == "throw" then error("expected load failure") end
        if failure then return false, failure end
        c.TwichUI.Workshop = { ready = true,
            Open = function() error("login must not open a window") end,
            Toggle = function() error("login must not toggle a window") end }
        return true
    end
    local f = assert(loadfile(ROOT .. "WorkshopLauncher.lua")); setfenv(f, c); f()
    c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    c.TwichUI.Profiles = { Generation = function() return generation end }
    c.FireEvent("PLAYER_LOGIN")
    local t = { c = c, L = c.TwichUI.WorkshopLauncher }
    function t.World(reload) c.FireEvent("PLAYER_ENTERING_WORLD", not reload, reload == true) end
    function t.Tick() local fn = table.remove(timers, 1); if fn then fn() end end
    function t.Pending() return #timers end
    function t.Loads() return loads end
    function t.Faults() return faults end
    function t.Profile() generation = generation + 1 end
    return t
end
local off = Setup(false)
assert(off.Loads() == 0 and off.Pending() == 0)
off.World(); assert(off.Pending() == 0 and off.L.Snapshot().login == "off")
off.L.SetLoadOnLogin(true); off.World(); off.c.FireEvent("PLAYER_REGEN_ENABLED")
assert(off.Pending() == 0 and off.Loads() == 0, "turning on takes effect next login, not a later zone")
for _, reload in ipairs({ false, true }) do
    local t = Setup(true)
    assert(t.Loads() == 0 and t.Pending() == 0, "not at ADDON_LOADED or PLAYER_LOGIN")
    t.World(reload); t.World(reload); assert(t.Pending() == 1 and t.Loads() == 0, "one delayed world-entry load")
    t.Tick(); assert(t.Loads() == 1 and t.L.Loaded() and t.L.Snapshot().login == "loaded")
    assert(type(t.L.Snapshot().loginMS) == "number")
    t.World(); t.c.FireEvent("PLAYER_REGEN_ENABLED"); t.Tick()
    assert(t.Loads() == 1 and t.Pending() == 0, "initialization is idempotent")
end
local combat = Setup(true); combat.c.COMBAT = true; combat.World(); combat.Tick()
assert(combat.Loads() == 0 and combat.L.Snapshot().login == "combat")
combat.c.COMBAT = false; combat.c.FireEvent("PLAYER_REGEN_ENABLED"); combat.c.FireEvent("PLAYER_REGEN_ENABLED")
assert(combat.Pending() == 1); combat.Tick(); assert(combat.Loads() == 1)
local zoning = Setup(true); zoning.World(); zoning.c.FireEvent("PLAYER_LEAVING_WORLD"); zoning.Tick()
assert(zoning.Loads() == 0 and zoning.L.Snapshot().login == "world", "no load after leaving the world")
zoning.World(); zoning.Tick(); assert(zoning.Loads() == 1)
local cancel = Setup(true); cancel.World(); cancel.L.SetLoadOnLogin(false); cancel.Tick()
assert(cancel.Loads() == 0 and cancel.L.Snapshot().login == "cancelled")
local profile = Setup(true); profile.World(); profile.Profile(); profile.Tick()
assert(profile.Loads() == 0 and profile.L.Snapshot().login == "cancelled", "old profile work is cancelled")
local manual = Setup(true); manual.World(); assert(manual.L.Load()); manual.Tick()
assert(manual.Loads() == 1 and manual.L.Snapshot().login == "already-loaded")
for _, reason in ipairs({ "MISSING", "DISABLED", "throw" }) do
    local t = Setup(true, reason); t.World(); t.Tick()
    assert(t.Loads() == 1 and not t.L.Loaded())
    t.World(); t.c.FireEvent("PLAYER_REGEN_ENABLED"); t.Tick()
    assert(t.Loads() == 1, "failed startup is not retried by recurring world/combat events")
    assert(t.L.Snapshot().login == (reason == "throw" and "ERROR" or reason))
    assert(t.Faults() == (reason == "throw" and 1 or 0), "load exception is reported once")
end
local junk=Setup(false)
assert(junk.L.SetEnabled(true) and junk.L.SetVendorJunkEnabled(true))
junk.World();assert(junk.Pending()==1);junk.Tick()
assert(junk.Loads()==1 and junk.L.Loaded(),"standalone junk feature loads its authorized Advisor dependency without Workshop login preference")
local junkOff=Setup(false)
assert(junkOff.L.SetEnabled(true) and junkOff.L.SetVendorJunkEnabled(true))
junkOff.World();junkOff.L.SetVendorJunkEnabled(false);junkOff.Tick()
assert(junkOff.Loads()==0,"disabled junk startup cancels its dependency load")
print("PASSED")
