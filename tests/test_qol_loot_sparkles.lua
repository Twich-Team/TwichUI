dofile(TESTS .. "harness.lua")
-- Synthetic CVar and timer behavior; actual world effects require the Forever client.
local CVAR = "outlineModeShowLootEffectWhenDisabled"
local function Boot(value, saved, unsupported)
    local c = MakeClient("Sparkles", { "!!!TwichUI" })
    local state = { value = value, writes = {}, timers = {} }
    c.InCombatLockdown = function() return state.combat == true end
    c.C_CVar = {
        GetCVar = function(name) assert(name == CVAR); return state.value end,
        SetCVar = function(name, v)
            assert(name == CVAR, "only the loot effect CVar may change")
            assert(not state.combat, "no writes in combat")
            if state.fail then error("unavailable") end
            state.writes[#state.writes + 1] = v
            state.value = v
            c.FireEvent("CVAR_UPDATE", CVAR, v)
            return true
        end,
    }
    if unsupported then c.C_CVar = nil end
    c.C_Timer.NewTimer = function(delay, fn)
        local t = { delay = delay, fn = fn }
        function t:Cancel() self.cancelled = true end
        state.timers[#state.timers + 1] = t
        return t
    end
    function state:Run()
        local pending = self.timers
        self.timers = {}
        for _, t in ipairs(pending) do if not t.cancelled then t.fn() end end
    end
    local chunk = assert(loadfile(ROOT .. "qol/LootSparkles.lua")); setfenv(chunk, c); chunk()
    c.TwichUIDB = saved
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    return c, state
end

local c, s = Boot("0")
local R, DB = c.TwichUI, c.TwichUIDB
local function Set(on) R:SetEnabled("qolLootSparkles", on) end
local function Listening(event) return R.frame.events[event] == true end
assert(DB.modules.qolLootSparkles == false and #s.writes == 0)
assert(not Listening("CVAR_UPDATE") and not Listening("PLAYER_REGEN_ENABLED"), "off has no listeners")
Set(true)
assert(s.value == "1" and DB.lootSparklesWas == "0" and #s.writes == 1)
assert(Listening("CVAR_UPDATE") and Listening("PLAYER_REGEN_ENABLED"))
R.QoLLootSparkles.Refresh(); R.QoLLootSparkles.Refresh()
assert(#s.writes == 1 and #s.timers == 0, "refresh is idempotent; our writes do not queue another pass")

-- Repeated graphics changes coalesce, match case-insensitively and ignore unrelated CVars.
c.FireEvent("CVAR_UPDATE", "Sound_EnableAllSound")
c.FireEvent("CVAR_UPDATE", nil)
assert(#s.timers == 0)
s.value = "0"
c.FireEvent("CVAR_UPDATE", "GRAPHICSQUALITY")
c.FireEvent("CVAR_UPDATE", "raidGraphicsQuality")
assert(#s.timers == 2 and s.timers[1].cancelled and s.timers[2].delay == 1)
s:Run()
assert(s.value == "1" and DB.lootSparklesWas == "0")
c.FireEvent("CVAR_UPDATE", CVAR)
Set(false)
local count = #s.writes
s:Run()
assert(s.value == "0" and #s.writes == count and DB.lootSparklesWas == nil, "disable cancels pending work and restores")
assert(not Listening("CVAR_UPDATE") and not Listening("PLAYER_REGEN_ENABLED"))

-- Login includes one delayed pass for settings that arrive late.
Set(true)
c.FireEvent("PLAYER_LOGIN")
assert(s.timers[#s.timers].delay == 5)
s.value = "0"; s:Run(); assert(s.value == "1")
Set(false)

-- Both enabling and restoration wait for combat, with disable cancelling a pending enable.
s.combat = true; Set(true)
assert(s.value == "0")
Set(false); s.combat = false; c.FireEvent("PLAYER_REGEN_ENABLED")
assert(s.value == "0" and not Listening("PLAYER_REGEN_ENABLED"))
s.combat = true; Set(true); s.combat = false; c.FireEvent("PLAYER_REGEN_ENABLED")
assert(s.value == "1")
s.combat = true; Set(false)
assert(s.value == "1" and Listening("PLAYER_REGEN_ENABLED") and not Listening("CVAR_UPDATE"))
s.combat = false; c.FireEvent("PLAYER_REGEN_ENABLED")
assert(s.value == "0" and DB.lootSparklesWas == nil and not Listening("PLAYER_REGEN_ENABLED"))

-- An existing enabled client setting stays enabled when this feature is toggled off.
s.value = "1"; count = #s.writes; Set(true); Set(false)
assert(s.value == "1" and #s.writes == count and DB.lootSparklesWas == nil)
-- A player/other addon change just before disabling is preserved, including after a queued event.
s.value = "0"; Set(true); s.value = "0"; c.FireEvent("CVAR_UPDATE", CVAR); Set(false); s:Run()
assert(s.value == "0" and DB.lootSparklesWas == nil)

-- Recovery belongs to the client setting across profile changes and reloads.
s.value = "0"; Set(true)
assert(R.Profiles.Create("No sparkles"))
assert(not R:Enabled("qolLootSparkles") and s.value == "0" and DB.lootSparklesWas == nil)
assert(R.Profiles.Switch("Default"))
assert(R:Enabled("qolLootSparkles") and s.value == "1" and DB.lootSparklesWas == "0")
local reload, rs = Boot("1", DB)
reload.TwichUI:SetEnabled("qolLootSparkles", false)
assert(rs.value == "0" and reload.TwichUIDB.lootSparklesWas == nil)
local off, os = Boot("1", { modules = { qolLootSparkles = false }, lootSparklesWas = "0" })
assert(os.value == "0" and off.TwichUIDB.lootSparklesWas == nil, "off at startup completes restoration")

-- Missing APIs/CVars and refused writes neither break initialization nor invent recovery data.
for _, initial in ipairs({ "missing", "bad", "throwing" }) do
    local bad, bs = Boot(initial == "bad" and "unexpected" or nil)
    if initial == "throwing" then bs.value, bs.fail = "0", true end
    bad.TwichUI:SetEnabled("qolLootSparkles", true)
    assert(#bs.writes == 0 and bad.TwichUIDB.lootSparklesWas == nil)
    bad.TwichUI:SetEnabled("qolLootSparkles", false)
end
local unsupported, us = Boot("0", nil, true)
unsupported.TwichUI:SetEnabled("qolLootSparkles", true)
unsupported.TwichUI:SetEnabled("qolLootSparkles", false)
assert(#us.writes == 0)
local damaged, ds = Boot("1", { lootSparklesWas = "not a CVar value" })
assert(#ds.writes == 0 and damaged.TwichUIDB.lootSparklesWas == nil)

print("PASSED test_qol_loot_sparkles")
