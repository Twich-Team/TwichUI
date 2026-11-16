-- Deterministic upgrade fixtures and real Workshop service shutdown/restart.
-- Synthetic state only: no real SavedVariables, client reload or native input.
dofile(TESTS .. "harness.lua")
local function Fingerprint(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out+1] = Fingerprint(k) .. "=" .. Fingerprint(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function Load(c, file)
    local chunk = assert(loadfile(file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local function Setup(ui)
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = {}, ui = ui or {}, workshop = { v = 1,
        chars = { ["Rich - Forever"] = { queue = { { id = 1, crafts = 3, name = "Kept plan" } }, known = {} } },
        storage = { useGuild = false }, view = { notices = false, advisorGain = 1000 },
        shopping = { chosen = { [10] = "vendor" } } } }
    c.TwichUIWorkshopDB = { v = 2, markets = { fixture = { items = { [10] = { price = 123 } }, history = "kept" } } }
    local data = Fingerprint({ c.TwichUIDB.workshop, c.TwichUIWorkshopDB })
    local calls, timers, reloads = {}, {}, 0
    c.ReloadUI = function() reloads = reloads + 1 end
    c.C_Timer = { After = function(_, fn)
        if debug.getinfo(2,"S").source:find("WorkshopLauncher",1,true) then timers[#timers+1]=fn end
    end }
    c.C_AddOns.LoadAddOn = function(name)
        calls[#calls+1]=name
        c.TwichUI.Workshop = { ready = true }
        return true
    end
    Load(c, ROOT .. "WorkshopLauncher.lua")
    c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    c.FireEvent("PLAYER_LOGIN")
    local function Preserved()
        assert(data == Fingerprint({ c.TwichUIDB.workshop, c.TwichUIWorkshopDB }), "saved Workshop records changed")
        assert(reloads == 0, "never automatically reload")
    end
    return c, c.TwichUI.WorkshopLauncher, calls, timers, Preserved
end
for _, case in ipairs({
    { name="fresh", ui={}, enabled=false },
    { name="legacy disabled", ui={workshopLoadOnLogin=false}, enabled=false },
    { name="legacy deliberate login", ui={workshopLoadOnLogin=true}, enabled=true },
    { name="explicit off wins", ui={workshopEnabled=false,workshopLoadOnLogin=true}, enabled=false },
    { name="explicit on", ui={workshopEnabled=true,workshopLoadOnLogin=false}, enabled=true },
    { name="malformed opt-in", ui={workshopEnabled="true",workshopLoadOnLogin=true}, enabled=false },
}) do
    local c,L,calls,timers,Preserved = Setup(case.ui)
    assert(L.Enabled() == case.enabled, case.name)
    L.Migrate(); assert(L.Enabled() == case.enabled, "repeatable migration: " .. case.name)
    Preserved()
    if not case.enabled then
        assert(not L.Load() and select(2,L.Load()) == "EXPERIMENTAL_OFF")
        assert(not L.Open() and not L.AuctionPreview(), "disabled launchers cannot bypass opt-in")
        c.FireEvent("PLAYER_ENTERING_WORLD",true,false)
        assert(#calls==0 and #timers==0, "disabled startup must not load anything")
    end
    assert(L.SetEnabled(true)); assert(#calls==0, "opt-in alone never deserializes an optional database")
    assert(L.Load() and calls[1]=="TwichUI_Workshop" and #calls==1)
    assert(L.SetEnabled(false) and not L.Enabled())
    assert(c.TwichUIDB.ui.workshopEnabled==false, "false must remain explicit")
    assert(not L.Load() and #calls==1)
    assert(L.SetEnabled(true) and L.Load() and #calls==1, "reuse loaded addon")
    Preserved()
    -- In-memory reload fixture: preserve exactly the saved state in a new core.
    local _, reloaded, _, _, CheckAgain = Setup(c.TwichUIDB.ui)
    assert(reloaded.Enabled()); CheckAgain()
end
do
    local c,L,calls,timers,Preserved = Setup({workshopLoadOnLogin=true})
    c.FireEvent("PLAYER_ENTERING_WORLD",true,false); assert(#timers==1)
    assert(L.SetEnabled(false)); timers[1]()
    assert(#calls==0, "disable cancels the delayed login load")
    c.TwichUIDB.ui={workshopEnabled=true}; c.TwichUI.Profiles.Refresh("fixture")
    assert(L.Enabled())
    c.TwichUIDB.ui={workshopEnabled=false,workshopLoadOnLogin=true}; c.TwichUI.Profiles.Refresh("fixture")
    assert(not L.Enabled() and #calls==0, "profile application cannot load disabled Workshop")
    assert(not L.SetEnabled("true")); Preserved()
end

do
    local c,L = Setup({})
    local future={v=99,ui={workshopEnabled=true},workshop={v=99,opaque="preserved"}}
    local before=Fingerprint(future)
    c.TwichUI.Persist.Hold("TwichUIDB",future,{modules={},ui={}})
    L.Migrate()
    assert(c.TwichUIDB.ui.workshopEnabled==nil and not L.SetEnabled(true), "held future saved data cannot be migrated or enabled")
    c.FireEvent("PLAYER_LOGOUT")
    assert(c.TwichUIDB==future and Fingerprint(future)==before, "future original is restored byte-for-byte in the fixture")
end

-- Load every real Workshop TOC file while opted out, then exercise real services.
AUCTION_MOCK_OPTIONS={experimentalOff=true,native=true}
local c = dofile(TESTS .. "auction_mock.lua")
local R,W = c.TwichUI,c.TwichUI.Workshop
local L=R.WorkshopLauncher
local function ReadListeners() return R.ListenerCounts({}).ITEM_SEARCH_RESULTS_UPDATED or 0 end
assert(not W.Active() and W.ready and not W.Window.Frame())
assert(ReadListeners()==0, "disabled addon registers no read-transport events")
assert(W.Watch.Events()==0 and W.Bank.Events()==0 and W.WorthTip.Events()==0)
assert(c.nativeHooks==0 and #c.tooltipCallbacks==0, "disabled addon installs no optional hooks")
assert(not W.Bridge.Load() and not W.AuctionUI.Show() and not W.Window.Show())
assert(not W.Compact.Show() and not W.Notice.Say("must stay silent"))
assert(L.SetEnabled(true) and W.Active())
assert(ReadListeners()==1, "enabled read transport registers once")
assert(W.Watch.Events()>0 and W.Bank.Events()>0 and W.WorthTip.Events()>0)
assert(#c.tooltipCallbacks==1 and not W.AuctionButton.Attached(), "enabling alone cannot attach native AH controls")
W.Queue.Add({id=1,name="Preserved recipe",mats={{item=10,qty=2}}})
W.Queue.SetCrafts(1,4)
W.Window.Show(); W.Window.Hide()
local hooks,frames=c.nativeHooks,#c.testFrames
assert(W.AuctionButton.Attached(), "normal Workshop opening retains the existing manual scan button")
local saved=Fingerprint({c.TwichUIDB.workshop,c.TwichUIWorkshopDB})
local reads,bankReads,added=W.Watch.reads,W.Bank.reads,W.WorthTip.added
W.Watch.Request()
assert(L.SetEnabled(false) and not W.Active())
assert(W.Watch.Events()==0 and W.Bank.Events()==0 and W.WorthTip.Events()==0)
assert(ReadListeners()==0 and not W.AuctionReads.Available(), "disabling removes transport listeners and refuses reads")
assert(not W.AuctionButton.Button():IsShown() and not W.Scan.Busy())
assert(not W.Bridge.Load() and not W.AuctionUI.Show() and not W.Window.Show())
assert(not W.Notice.Say("disabled"))
W.Watch.Run(); c.tooltipCallbacks[1](c.GameTooltip,{guid="ignored"})
FlushTimers()
assert(W.Watch.reads==reads and W.Bank.reads==bankReads and W.WorthTip.added==added)
assert(saved==Fingerprint({c.TwichUIDB.workshop,c.TwichUIWorkshopDB}), "disable/timers/hooks preserve complete saved fingerprints")
for _=1,3 do assert(L.SetEnabled(true)); assert(L.SetEnabled(false)) end
assert(L.SetEnabled(true) and W.Active())
assert(ReadListeners()==1, "repeated toggles never duplicate transport listeners")
assert(c.nativeHooks==hooks and #c.tooltipCallbacks==1, "restart never duplicates hooks")
assert(#c.testFrames==frames, "service frames are reused")
assert(#W.Queue.Entries()==1 and W.Queue.Entries()[1].crafts==4)
local beforeRead=W.Watch.reads
local observe=W.Session.Observe
W.Session.Observe=function() return true end -- a successful synthetic profession read
W.Watch.Request(); W.Watch.Run(); FlushTimers()
W.Watch.Request(); FlushTimers()
assert(W.Watch.reads>=beforeRead+2, "a direct read cannot strand the pending event observer")
W.Session.Observe=observe
local profileUI=c.TwichUIDB.ui
c.TwichUIDB.ui={workshopEnabled=false}; R.Profiles.Refresh("opt-in test")
assert(not W.Active() and W.Watch.Events()==0 and W.Bank.Events()==0, "real profile application suspends services")
c.TwichUIDB.ui=profileUI; R.Profiles.Refresh("opt-in test")
assert(W.Active() and c.nativeHooks==hooks and #c.tooltipCallbacks==1, "profile return resumes without duplicate hooks")
AUCTION_MOCK_OPTIONS={preview=true,native=true}
local preview=dofile(TESTS .. "auction_mock.lua")
preview.TwichUIDB.ui=preview.TwichUIDB.ui or {}
preview.TwichUIDB.ui.workshopEnabled=true
Load(preview,ROOT .. "WorkshopLauncher.lua")
local PL=preview.TwichUI.WorkshopLauncher
assert(PL.SetEnabled(false) and PL.SetEnabled(true))
assert(preview.nativeHooks==0 and not preview.TwichUI.Workshop.AuctionButton.Attached(), "preview-only resume never hooks Blizzard AH")
print("PASSED: conservative opt-in migration, saved fingerprints, profiles, delayed login, lifecycle and hook reuse")
