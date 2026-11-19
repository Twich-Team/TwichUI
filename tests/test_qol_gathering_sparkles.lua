dofile(TESTS .. "harness.lua")
-- Synthetic engine targeting, CVar ownership and recycled nameplates. No gameplay actions.
local INITIAL = { SoftTargetInteract = "0", SoftTargetNameplateInteract = "0", SoftTargetInteractRange = "10",
    SoftTargetInteractArc = "1", SoftTargetInteractOnlyInRange = "1", SoftTargetIconGameObject = "0" }
local function Boot(saved, initial)
    local c = MakeClient("Gatherer", { "!!!TwichUI" })
    local s = { cvars = {}, writes = {}, timers = {}, frames = {}, now = 0, y = 0, x = 0 }
    for k, v in pairs(initial or INITIAL) do s.cvars[k] = v end
    local function Object()
        local o = { alpha = 1, shown = true, scripts = {} }
        function o:SetAlpha(v) self.alpha = v end
        function o:GetAlpha() return self.alpha end
        function o:GetEffectiveAlpha() return self.alpha end
        function o:Show() self.shown = true end
        function o:Hide() self.shown = false end
        function o:IsShown() return self.shown end
        function o:IsForbidden() return self.forbidden == true end
        function o:SetScript(k, fn) self.scripts[k] = fn end
        function o:GetScript(k) return self.scripts[k] end
        function o:SetSize(w, h) self.w, self.h = w, h end
        function o:SetPoint(...) self.point = { ... } end
        function o:ClearAllPoints() self.point = nil end
        function o:SetFrameStrata() end
        function o:EnableMouse(v) assert(v == false) end
        function o:SetTexture(v) self.texture = v end
        function o:GetTexture() return self.texture end
        function o:GetAtlas() return self.atlas end
        function o:SetBlendMode() end
        function o:SetVertexColor(...) self.color = { ... } end
        function o:CreateTexture()
            local texture = Object(); self.textures = self.textures or {}; self.textures[#self.textures + 1] = texture
            return texture
        end
        return o
    end
    c.CreateFrame = function() local f = Object(); s.frames[#s.frames + 1] = f; return f end
    c.UIParent = Object()
    s.plate = Object(); s.plate.UnitFrame = Object(); s.plate.UnitFrame.SoftTargetFrame = Object()
    function s:VisibleTarget() return self.cvars.SoftTargetInteract ~= "0" and self.pick or nil end
    c.UnitIsGameObject = function() local u = s:VisibleTarget(); return u == "herb" or u == "ore" or u == "other" end
    c.UnitExists = function(unit) return unit == "player" or s:VisibleTarget() == "npc" or s:VisibleTarget() == "corpse" end
    c.UnitIsDead = function() return s:VisibleTarget() == "corpse" end
    c.UnitIsUnit = function(unit) return unit == "nameplate1" and s:VisibleTarget() ~= nil end
    c.UnitGUID = function(unit) return unit == "player" and "Player-1-Gatherer" or (s:VisibleTarget() and (s.guid or "GameObject-1-2-3-4-5-6")) end
    c.UnitPosition = function() if s.noPosition then return nil end; return s.y, s.x end
    c.GetTime = function() return s.now end
    c.InCombatLockdown = function() return s.combat == true end
    c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    c.GetFileIDFromPath = function(path)
        return ({ ["Interface\\Cursor\\GatherHerbs"] = 101, ["Interface\\Cursor\\UnableGatherHerbs"] = 102,
            ["Interface\\Cursor\\Mine"] = 201, ["Interface\\Cursor\\UnableMine"] = 202 })[path]
    end
    c.SetUnitCursorTexture = function(tex)
        if s.cursorError then error("restricted") end
        tex.texture = s.cursor or (s.pick == "herb" and 101 or s.pick == "ore" and 201 or "Interface\\Cursor\\Interact")
        tex.atlas = s.atlas
        return true
    end
    c.C_NamePlate = { GetNamePlateForUnit = function(unit)
        if s.cvars.SoftTargetNameplateInteract ~= "1" or not s:VisibleTarget() then return nil end
        if s.fallback and unit == "softinteract" then return nil end
        return s.plate
    end }
    c.C_CVar = {
        GetCVar = function(k) return s.cvars[k] end,
        SetCVar = function(k, v)
            assert(INITIAL[k], "only the six owned interaction CVars may change")
            assert(not s.combat, "no protected write is attempted in combat")
            if s.refuse == k then return false end
            s.writes[#s.writes + 1] = k .. "=" .. v
            s.cvars[k] = v
            c.FireEvent("CVAR_UPDATE", k, v)
            if k == "SoftTargetInteract" then c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "", "") end
            return true
        end,
    }
    c.C_Timer.NewTicker = function(delay, fn)
        assert(delay == 0.2)
        local t = { fn = fn }
        function t:Cancel() self.cancelled = true end
        s.timers[#s.timers + 1] = t
        return t
    end
    function s:Tick(dt)
        self.now = self.now + (dt or 0.2)
        for _, t in ipairs(self.timers) do if not t.cancelled then t.fn() end end
    end
    for _, f in ipairs({ "qol/GatheringSparkles.lua", "qol/GatheringSparklesDisplay.lua" }) do
        local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk()
    end
    c.TwichUIDB = saved
    c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    return c, s, c.TwichUI.QoLGathering
end
local function Set(c, key, on) c.TwichUI:SetEnabled(key, on) end
local function Off(c) Set(c, "qolHerbSparkles", false); Set(c, "qolOreSparkles", false) end
local function Restored(s)
    for k, v in pairs(INITIAL) do assert(s.cvars[k] == v, k .. ": " .. tostring(s.cvars[k])) end
end

local c, s, G = Boot()
assert(c.TwichUIDB.modules.qolHerbSparkles == false and c.TwichUIDB.modules.qolOreSparkles == false)
assert(#s.writes == 0 and #s.frames == 0 and G.stats.timers == 0 and G.stats.listeners == 0)
s.pick = "herb"; Set(c, "qolHerbSparkles", true)
assert(G.stats.shown == 1 and G.stats.frames == 1 and G.stats.timers == 1 and G.stats.cvars == 6)
assert(s.plate.UnitFrame.alpha == 0 and s.plate.UnitFrame.SoftTargetFrame.alpha == 0)
local frame = s.frames[1]
assert(frame.point[2] == s.plate and frame.scripts.OnUpdate)
frame.scripts.OnUpdate(frame, 0.1)
local count = #s.writes
for _ = 1, 20 do G.Refresh(); s:Tick() end
assert(#s.writes == count and #s.frames == 1 and G.stats.timers == 1, "refresh reuses one effect and one ticker")

-- Independent categories and numeric, path and atlas cursor results, including unavailable nodes.
s.cursor, s.atlas = "unrecognized", "Cursor_Crosshair_Gather_64"
s:Tick(); assert(G.stats.shown == 1, "herb atlas names may use Gather without the Herbs suffix")
s.cursor, s.atlas = nil, nil
s.pick = "ore"; c.FireEvent("PLAYER_SOFT_INTERACT_CHANGED", "old", "new")
assert(G.stats.shown == 0 and s.plate.UnitFrame.alpha == 1)
Set(c, "qolOreSparkles", true); assert(G.stats.shown == 1)
Set(c, "qolHerbSparkles", false); s.pick = "herb"; s:Tick(); assert(G.stats.shown == 0)
s.pick, s.cursor = "ore", "Interface\\Cursor\\UnableMine"; s:Tick(); assert(G.stats.shown == 1)
assert(frame.textures[1].color[1] == 0.65 and frame.textures[1].color[2] == 0.65, "unavailable nodes are grey")
s.cursor, s.atlas = false, "Cursor_Crosshair_UnableMine_64" -- false selects the numeric fallback; force unknown texture below
s.cursor = "unrecognized"; s:Tick(); assert(G.stats.shown == 1)
s.cursor, s.atlas = { secret = true }, nil; s:Tick(); assert(G.stats.shown == 0)
s.cursor, s.cursorError = nil, true; s:Tick(); assert(G.stats.shown == 0)
s.cursorError = false

-- Recycled plates and external alpha changes restore only the visual state still owned.
s.pick = "ore"; s.guid = "GameObject-ore-one"; s:Tick(); assert(G.stats.shown == 1)
s.plate.UnitFrame.alpha = 0.45
s.pick, s.guid = "other", "GameObject-chest-two"; s:Tick()
assert(G.stats.shown == 0 and s.plate.UnitFrame.alpha == 0.45, "do not overwrite another skin's alpha")
s.plate.UnitFrame.alpha = 1; s.pick = "ore"; s:Tick()
c.FireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
Off(c); Restored(s)
assert(G.stats.shown == 0 and not frame.scripts.OnUpdate and G.stats.timers == 0 and G.stats.listeners == 0)
assert(c.TwichUIDB.gatheringSparklesCVars == nil)

-- Living characters pause selection immediately, including one revealed by enabling soft targeting.
s.pick = "npc"; Set(c, "qolHerbSparkles", true)
assert(G.status == "unit" and s.cvars.SoftTargetInteract == "0" and G.stats.shown == 0)
s.pick = "herb"; s:Tick(1); assert(s.cvars.SoftTargetInteract == "0")
s.x = 6; s:Tick(); assert(s.cvars.SoftTargetInteract == "3" and G.stats.shown == 1)
-- Combat closes the overlay, defers restoration, and cancelling a switch cancels future enabling.
s.combat = true; c.FireEvent("PLAYER_REGEN_DISABLED")
assert(G.stats.shown == 0 and G.status == "combat")
Off(c); count = #s.writes; s:Tick(5); assert(#s.writes == count and G.stats.timers == 0)
s.combat = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Restored(s)
assert(G.stats.listeners == 0 and c.TwichUIDB.gatheringSparklesCVars == nil)

-- A manual change yields all other settings and never fights the player on the next poll.
s.pick = "herb"; Set(c, "qolHerbSparkles", true)
s.cvars.SoftTargetInteractRange = "12"; c.FireEvent("CVAR_UPDATE", "softtargetinteractrange", "12")
assert(G.status == "changed" and G.stats.timers == 0 and G.stats.shown == 0)
count = #s.writes; s:Tick(); assert(#s.writes == count and s.cvars.SoftTargetInteractRange == "12")
Off(c); s.cvars.SoftTargetInteractRange = "10"
Set(c, "qolHerbSparkles", true); assert(G.stats.shown == 1)

-- Profiles and reloads retain the client recovery record outside configuration copies.
assert(c.TwichUI.Profiles.Create("Gathering off")); Restored(s)
assert(c.TwichUI.Profiles.Switch("Default") and G.stats.shown == 1)
local reload, rs, RG = Boot(c.TwichUIDB, s.cvars)
Off(reload); Restored(rs); assert(RG.stats.timers == 0)
Off(c)
local log, logs, LG = Boot(); logs.pick = "herb"; Set(log, "qolHerbSparkles", true)
log.FireEvent("PLAYER_LOGOUT"); Restored(logs)
assert(LG.stats.shown == 0 and LG.stats.timers == 0 and LG.stats.listeners == 0)
log.FireEvent("PLAYER_ENTERING_WORLD"); assert(LG.stats.shown == 0, "logout detached the old session's listeners")
local pending, ps, PG = Boot(); ps.pick = "herb"; Set(pending, "qolHerbSparkles", true)
local recovery = pending.TwichUIDB.gatheringSparklesCVars
local restart, rss, RSG = Boot({ modules = { qolHerbSparkles = false, qolOreSparkles = false }, gatheringSparklesCVars = recovery }, ps.cvars)
Restored(rss); assert(RSG.stats.timers == 0 and restart.TwichUIDB.gatheringSparklesCVars == nil)
Off(pending)
local retry, rts, RTG = Boot(); rts.pick = "herb"; Set(retry, "qolHerbSparkles", true)
rts.refuse = "SoftTargetInteract"; Off(retry)
assert(retry.TwichUIDB.gatheringSparklesCVars and RTG.stats.timers == 0 and RTG.stats.listeners > 0)
rts.refuse = nil; retry.FireEvent("PLAYER_REGEN_ENABLED"); Restored(rts); assert(RTG.stats.listeners == 0)
local timed, tms, TMG = Boot(); tms.pick, tms.noPosition = "npc", true; Set(timed, "qolHerbSparkles", true)
tms.pick = "herb"; tms:Tick(2); assert(TMG.stats.shown == 0)
tms:Tick(2); assert(TMG.stats.shown == 1); Off(timed)

-- Known competitors suspend and restore; native quest-only ForeverLootSparkles 2.x can coexist.
for _, addon in ipairs({ "Lueur", "LueurStill", "LueurLegacy", "ForeverLootSparkles_Coloring" }) do
    local t, ts, TG = Boot(); ts.pick = "herb"; Set(t, "qolHerbSparkles", true)
    t.LOADED[addon] = true; t.FireEvent("ADDON_LOADED", addon)
    assert(TG.conflict == addon and TG.stats.timers == 0 and TG.stats.shown == 0)
    Restored(ts)
    t.FireEvent("PLAYER_REGEN_DISABLED"); Restored(ts)
end
local t, ts, TG = Boot()
t.LOADED.ForeverLootSparkles = true
t.C_AddOns.GetAddOnMetadata = function() return "2.0.0" end
ts.pick = "herb"; Set(t, "qolHerbSparkles", true); assert(not TG.conflict and TG.stats.shown == 1); Off(t)
local old, olds, OLD = Boot(); old.LOADED.ForeverLootSparkles = true
old.C_AddOns.GetAddOnMetadata = function() return "1.3.1" end
Set(old, "qolHerbSparkles", true)
assert(OLD.conflict == "ForeverLootSparkles" and #olds.writes == 0 and OLD.stats.timers == 0)

-- Missing settings/APIs and refused writes fail closed, preserving recovery for later retries.
local u, us, UG = Boot(); us.cvars.SoftTargetInteractRange = nil
Set(u, "qolHerbSparkles", true)
assert(#us.writes == 0 and UG.stats.shown == 0 and UG.stats.timers == 0)
local v, vs, VG = Boot(); vs.refuse = "SoftTargetInteract"
Set(v, "qolOreSparkles", true)
assert(VG.stats.shown == 0); Off(v); Restored(vs)
local w, ws, WG = Boot(); w.C_NamePlate = nil; Set(w, "qolHerbSparkles", true)
assert(#ws.writes == 0 and WG.stats.timers == 0 and #ws.frames == 0)
local damaged, dms, DMG = Boot({ gatheringSparklesCVars = { SoftTargetInteract = { was = "not a number", set = "3" } } })
assert(#dms.writes == 0 and damaged.TwichUIDB.gatheringSparklesCVars == nil and DMG.stats.listeners == 0)

-- Direct object nameplates have a bounded fallback and recycled/removal bookkeeping.
local f, fs, FG = Boot(); fs.pick, fs.fallback = "herb", true; Set(f, "qolHerbSparkles", true)
assert(FG.stats.shown == 0)
f.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate1"); assert(FG.stats.shown == 1)
for i = 2, 100 do f.FireEvent("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
assert(FG.stats.units == 64)
Off(f); assert(FG.stats.units == 0)

-- Instrumentation is read-only and retains the same bounds with a capture enabled.
local seen = {}
c.TwichUI.Perf.on = true
c.TwichUI.Perf.Start = function(id) seen[id] = true; return id end
c.TwichUI.Perf.Stop = function() end
Set(c, "qolHerbSparkles", true); s:Tick(); frame.scripts.OnUpdate(frame, 0.1)
assert(seen["gathering.evaluate"] and seen["gathering.refresh"] and seen["gathering.animate"])
local made, writes = #s.frames, #s.writes
for _, gauge in ipairs(c.TwichUI.Perf.gauges) do if gauge.id:find("^gathering%.") then assert(type(gauge.read()) == "number") end end
assert(#s.frames == made and #s.writes == writes)
Off(c); c.TwichUI.Perf.on = false
print("PASSED test_qol_gathering_sparkles")
