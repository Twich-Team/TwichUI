-- TwichUI Layouts: the ellesmereui adapter, the EllesmereUI suite (architecture.md §3, §4, §8; adapter-capabilities.md)
-- Only EllesmereUI's public functions are called: DecodeImportString, EncodePayload, ImportProfileSilent (never
-- reloads; "the caller owns the ReloadUI"), GetProfileList, GetActiveProfileName, GetProfilesDB (read), SwitchProfile,
-- DeleteProfile, and ExportProfile for a developer package built on the recipient's own profile. EllesmereUIDB is
-- never written here. Read in EllesmereUI 9.6.8 (EllesmereUI_Profiles.lua); nothing of it has been run in game yet.
--
-- An install imports into its own profile (the package's target name, cleanSlate), which EllesmereUI then makes the
-- active one. EllesmereUI's active profile is account-wide, so every character on the account sees it. The import builds
-- on the active profile and replaces whole module blobs; the payload holds every module of the base, so nothing is
-- inherited by accident. Restore switches back to the profile in use before and removes the install's profile.
--
-- Units: "ellesmereui:base" (the base layer's export string, or a developer package's { source = "active-profile" }),
-- "ellesmereui:addons.<module>" (a whole module blob from an export string), and the fields below, inside a blob. The
-- inner shape of a blob is EllesmereUI's and can change between versions, so only these fields are ever patched, and
-- after a reload only they are compared (EllesmereUI fills its defaults into a blob as it loads, so a whole blob never
-- reads back as it was imported; its presence is checked).
--
-- Not done in this phase, and refused by name when a package asks: the UI scale (it stays the recipient's:
-- applyUIScale = false), suite module enable states (disableAddons), positions and look units. Everything account-wide
-- that a profile string can carry is taken out first (EXCLUDED), so deleting the install's profile undoes the install.
--
-- Snapshot part: { active = the profile in use before, target, created, version, values = { [unit] = fingerprint } }

local R = TwichUI
local LY = R.Layouts
local A = { id = "ellesmereui", contract = LY.CONTRACT, label = "EllesmereUI", effect = "reload" }
LY.EllesmereAdapter = A

local PREFIX = "ellesmereui:"
A.BASE_UNIT = PREFIX .. "base"
A.PROFILE_UNIT = PREFIX .. "profile"
A.DEV_SOURCE = "active-profile"

local function ES() return R.Ellesmere end
local function ST() return R.Setups end

local REQUIRED = { "DecodeImportString", "EncodePayload", "ImportProfileSilent", "GetProfileList", "GetActiveProfileName",
    "GetProfilesDB", "SwitchProfile", "DeleteProfile", "ExportProfile", "ImportProfile" }

-- The suite's module keys (canonical; EllesmereUI_Profiles.lua ADDON_DB_MAP).
A.MODULES = LY.Set({ "EllesmereUIActionBars", "EllesmereUINameplates", "EllesmereUIUnitFrames", "EllesmereUICooldownManager",
    "EllesmereUIResourceBars", "EllesmereUIRaidFrames", "EllesmereUIAuraBuffReminders", "EllesmereUIQoL",
    "EllesmereUIDragonRiding", "EllesmereUIBags", "EllesmereUIFriends", "EllesmereUIMythicTimer", "EllesmereUIQuestTracker",
    "EllesmereUIMinimap", "EllesmereUIDamageMeters", "EllesmereUIChat", "EllesmereUIDataBars", "EllesmereUIQuickdraw" })

-- The fields inside a module blob a package may set (the allowlist), each read in EllesmereUI 9.6.8's source:
-- EllesmereUIMinimap.lua's defaults (profile.minimap), EUI_Minimap_Info.lua GetCoordsModePos and MAP_POS_ANCHORS,
-- EUI_Minimap_Options.lua's "Show Coordinates" dropdown. A missing value reads as the default.
A.FIELDS = {
    ["minimap.coordsMode"] = { module = "EllesmereUIMinimap", path = { "minimap", "coordsMode" }, label = "Minimap > Show coordinates",
        values = LY.Set({ "never", "hover", "always" }), default = "always" },
    ["minimap.coordsPosition"] = { module = "EllesmereUIMinimap", path = { "minimap", "coordsPosition" }, label = "Minimap > Coordinates position",
        values = LY.Set({ "belowMap", "aboveMap", "topLeft", "top", "topRight", "left", "right", "bottomLeft", "bottom", "bottomRight" }),
        default = "topLeft" },
}
A.BY_UNIT = {}
for id, f in pairs(A.FIELDS) do
    f.id = id
    f.parent = PREFIX .. "addons." .. f.module
    f.unit = f.parent .. "." .. table.concat(f.path, ".")
    A.BY_UNIT[f.unit] = f
end

-- Taken out of every payload before it is imported: account-wide or personal (architecture.md §3). The UI scale, the
-- window and tooltip skins, spec assignments, the Cooldown Manager's spell layouts, the spec and condition overrides,
-- click-cast and the spell store, and the custom colours (a palette other profiles can pull from, so removing the
-- install's profile would not take it back). EllesmereUI's transport-only keys go too.
A.EXCLUDED = { "uiScale", "applyUIScale", "blizzSkinGlobals", "applyBlizzSkinGlobals", "assignedSpecs", "cdmSpells",
    "specOverrides", "specOverrideGroups", "specOverrideNextId", "condOverrides", "condOverrideGroups", "condOverrideNextId",
    "specUnlockOverrides", "condUnlockOverrides", "specBmOverrides", "condBmOverrides", "clickCast", "spellAssignments",
    "customColors", "unlockLayoutMeta", "_importEstablishPending", "overridesIncluded", "overridesExcluded", "partialImport",
    "layoutExcluded" }
-- What EllesmereUI itself keeps out of a shared profile (per-character data), as setup/Ellesmere.lua does.
local PRIVATE = { EllesmereUIDataBars = "characters", EllesmereUIQoL = "chars" }

local function Unit(module) return PREFIX .. "addons." .. module end
local function ModuleOf(unit) return unit:match("^ellesmereui:addons%.([%w_]+)$") end

function A.Label(unit)
    if unit == A.PROFILE_UNIT then return "Active profile" end
    if unit == A.BASE_UNIT then return "Base profile" end
    local f = A.BY_UNIT[unit]
    if f then return f.label end
    local m = ModuleOf(unit)
    return m and ("Module " .. m) or unit
end

function A.Show(v)
    if v == nil then return "(default)" end
    if type(v) == "string" and v:sub(1, 5) == "!EUI_" then return "an EllesmereUI export" end
    if type(v) == "table" then return "your own profile" end
    return tostring(v)
end

function A.TargetName(name) return LY.Plain(name, R.Ellesmere and R.Ellesmere.LIMITS.name or 30) end

---------------------------------------------------------------------------
-- Detect: present, the functions this needs, the Forever build, the version the package asks for
---------------------------------------------------------------------------
local function Parts(v)
    local out = {}
    for n in tostring(v):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

function A.Older(a, b)   -- version a is older than b
    local pa, pb = Parts(a), Parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

-- { present, usable, version, why = "missing"|"no-api"|"not-forever"|"too-old", missing, untested, otherClient }, E
-- otherClient: let an EllesmereUI that isn't the Forever build through. Only a developer package asks for it (testing
-- the pipeline on another game client while Forever can't be played); what happens there proves nothing about Forever.
function A.Detect(req, otherClient)
    local E = rawget(_G, "EllesmereUI")
    local out = { present = type(E) == "table", version = ES() and ES().Version() or nil }
    if not out.present then out.why = "missing" return out end
    for _, fn in ipairs(REQUIRED) do
        if type(E[fn]) ~= "function" then out.why, out.missing = "no-api", fn return out end
    end
    if E.IS_FOREVER ~= true then
        if not otherClient then out.why = "not-forever" return out end
        out.otherClient = true
    end
    if type(req) == "table" and req.min and (not out.version or A.Older(out.version, req.min)) then out.why = "too-old" return out end
    out.usable = true
    out.untested = type(req) == "table" and req.tested ~= nil and out.version ~= req.tested or false
    return out, E
end

---------------------------------------------------------------------------
-- A fragment: { base = "<export>" | { source = "active-profile" } (base layer only; the source form only in a
--   developer package), modules = { [module] = "<export holding it>" | REMOVE }, fields = { [field id] = value | REMOVE } }
---------------------------------------------------------------------------
local NOT_YET = LY.Set({ "positions", "look", "uiScale", "disableAddons", "unlockLayout" })
local MAX_STRING = 4 * 1048576

local function ExportString(s) return type(s) == "string" and #s > 5 and #s <= MAX_STRING and s:sub(1, 5) == "!EUI_" end

function A.Normalize(fragment, ctx)
    local P, units, parents = ctx.problems, {}, {}
    for k in pairs(fragment) do
        if NOT_YET[k] then P.add("not-yet", ctx.where .. "." .. tostring(k))
        elseif k ~= "base" and k ~= "modules" and k ~= "fields" then P.add("unknown-field", ctx.where .. "." .. tostring(k)) end
    end
    local base = fragment.base
    if base ~= nil then
        if ctx.layer ~= "base" then P.add("base-only-in-base-layer", ctx.where .. ".base")
        elseif ExportString(base) then units[A.BASE_UNIT] = base
        elseif type(base) == "table" and base.source == A.DEV_SOURCE and next(base, next(base)) == nil then
            if ctx.dev then units[A.BASE_UNIT] = { source = A.DEV_SOURCE } else P.add("dev-source-not-allowed", ctx.where .. ".base") end
        else P.add("bad-value", ctx.where .. ".base") end
    elseif ctx.layer == "base" then
        P.add("no-base", ctx.where .. ".base")
    end
    if fragment.modules ~= nil then
        if type(fragment.modules) ~= "table" then P.add("not-table", ctx.where .. ".modules")
        else
            for m, s in pairs(fragment.modules) do
                if not A.MODULES[m] then P.add("unknown-unit", ctx.where .. ".modules." .. tostring(m))
                elseif s == LY.REMOVE or ExportString(s) then units[Unit(m)] = s
                else P.add("bad-value", Unit(m)) end
            end
        end
    end
    if fragment.fields ~= nil then
        if type(fragment.fields) ~= "table" then P.add("not-table", ctx.where .. ".fields")
        else
            for id, v in pairs(fragment.fields) do
                local f = A.FIELDS[id]
                if not f then P.add("unknown-unit", ctx.where .. ".fields." .. tostring(id))
                elseif v == LY.REMOVE or (type(v) == "string" and f.values[v]) then
                    units[f.unit] = v
                    parents[f.unit] = f.parent
                else P.add("bad-value", f.unit) end
            end
        end
    end
    return units, parents
end

---------------------------------------------------------------------------
-- Reading EllesmereUI's profiles (never writing them)
---------------------------------------------------------------------------
local function Profiles(E)
    local ok, db = pcall(E.GetProfilesDB)
    if ok and type(db) == "table" and type(db.profiles) == "table" then return db.profiles end
    return {}
end

local function Active(E)
    local ok, name = pcall(E.GetActiveProfileName)
    return ok and name or nil
end

-- A field's stored value in a profile table (nil: not set, which reads as the default).
local function ReadField(profile, f)
    local t = type(profile) == "table" and type(profile.addons) == "table" and profile.addons[f.module]
    for i = 1, #f.path - 1 do
        if type(t) ~= "table" then return nil end
        t = t[f.path[i]]
    end
    if type(t) == "table" then return t[f.path[#f.path]] end
end

local function Ours(snap, target) return type(snap) == "table" and snap.created == true and snap.target == target end

function A.Capture(composed, target)
    local _, E = A.Detect(nil, true)   -- only after a plan that passed, so the client was already allowed
    local snap = { target = target, values = {}, version = ES().Version(), otherClient = E.IS_FOREVER ~= true or nil }
    snap.active = Active(E)
    local profiles = Profiles(E)
    snap.created = type(profiles[target]) ~= "table"
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then snap.values[e.unit] = LY.Fingerprint(ReadField(profiles[snap.active], f)) end
    end
    return snap
end

function A.CleanSnapshot(s)
    if type(s) ~= "table" then return false end
    if not (type(s.active) == "string" and #s.active <= 64 and A.TargetName(s.target)) then return false end
    if type(s.created) ~= "boolean" or type(s.values) ~= "table" then return false end
    if s.version ~= nil and not LY.Plain(s.version, 40) then return false end
    if s.otherClient ~= nil and type(s.otherClient) ~= "boolean" then return false end
    return true
end

---------------------------------------------------------------------------
-- The payload: decoded with EllesmereUI's own decoder, built up in a fresh table, never run
---------------------------------------------------------------------------
local function Decode(E, str)
    local ok, payload = pcall(E.DecodeImportString, str)
    if not ok or type(payload) ~= "table" or payload.type ~= "full" or type(payload.data) ~= "table"
        or type(payload.data.addons) ~= "table" then return nil end
    return payload
end

-- home: the recipient's own profile (where Restore goes back to, and what a developer base is exported from).
-- Returns payload | nil, why.
local function BuildPayload(E, composed, home, dev)
    local base = composed.units[A.BASE_UNIT]
    if base == nil then return nil, "no-base" end
    local str = base
    if type(base) == "table" then
        if not dev then return nil, "dev-source-not-allowed" end
        -- ExportProfile(name, modules, layout, cdm, cdmSpecs, globals, overrides, windowSkins): every module and its
        -- layout links; no Cooldown Manager spells, overrides, look, UI scale or window skins.
        local ok, s = pcall(E.ExportProfile, home, nil, true, false, nil, false, false, false)
        if not ok or not ExportString(s) then return nil, "eui-export" end
        str = s
    end
    local payload = Decode(E, str)
    if not payload then return nil, "eui-decode" end
    local d = payload.data
    for _, e in ipairs(composed.list) do
        local m = ModuleOf(e.unit)
        if m then
            local p = Decode(E, e.value)
            if not p or type(p.data.addons[m]) ~= "table" then return nil, "eui-module-missing" end
            d.addons[m] = p.data.addons[m]
        end
    end
    for _, k in ipairs(A.EXCLUDED) do d[k] = nil end
    local kept = 0
    for m, blob in pairs(d.addons) do
        if not A.MODULES[m] or type(blob) ~= "table" then d.addons[m] = nil
        else
            if PRIVATE[m] then blob[PRIVATE[m]] = nil end
            kept = kept + 1
        end
    end
    if kept == 0 then return nil, "eui-no-modules" end
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then
            local t = d.addons[f.module]
            if type(t) ~= "table" then return nil, "eui-module-absent" end
            for i = 1, #f.path - 1 do
                local k = f.path[i]
                if t[k] == nil then t[k] = {} end
                if type(t[k]) ~= "table" then return nil, "eui-shape" end
                t = t[k]
            end
            t[f.path[#f.path]] = e.value
        end
    end
    if ST().SizeOf(d) > ES().LIMITS.data then return nil, "too-large" end
    return payload
end

-- What the inputs were: a short fingerprint (an export string by its checksum, not its text).
local LibDeflate = LibStub("LibDeflate")
local function Inputs(composed, home)
    local t = { home = home }
    for _, e in ipairs(composed.list) do
        local v = e.value
        if type(v) == "string" and #v > 64 then v = "#" .. tostring(LibDeflate:Adler32(v)) .. ":" .. #v end
        t[e.unit] = v
    end
    return LY.Fingerprint(t)
end

---------------------------------------------------------------------------
-- Plan: read only. part = { adapter, target, active, home, rows, changes, nothing, reload, blocked, key, payload,
--   inputs, untested, version }. The payload is kept in memory only, for Apply.
---------------------------------------------------------------------------
function A.Plan(composed, ctx)
    local part = { adapter = A.id, effect = A.effect, rows = {}, changes = 0, reload = false }
    local det, E = A.Detect(ctx.requires, ctx.dev)
    part.version, part.untested, part.otherClient, part.dev = det.version, det.untested, det.otherClient, ctx.dev
    part.tested = type(ctx.requires) == "table" and ctx.requires.tested or nil
    if not det.usable then part.blocked = "eui-" .. det.why return part end
    -- EllesmereUI's own first-run picker is waiting to be answered this session: it ends in its own import and
    -- reload, which would replace an install made now. The flag is EllesmereUI's (read only).
    if E._firstInstallPending == true then part.blocked = "eui-first-run" return part end
    local profiles, active, target, snap = Profiles(E), Active(E), ctx.target, ctx.snapshot
    if type(active) ~= "string" then part.blocked = "eui-no-active" return part end
    local exists = type(profiles[target]) == "table"
    if exists and not Ours(snap, target) then part.blocked = "target-taken" return part end
    local home = snap and snap.active or active
    if type(profiles[home]) ~= "table" then part.blocked = "previous-gone" return part end
    local payload, why = BuildPayload(E, composed, home, ctx.dev)
    if not payload then part.blocked = why return part end
    part.payload, part.target, part.active, part.home = payload, target, active, home
    part.inputs = Inputs(composed, home)

    local from = exists and profiles[target] or profiles[active]
    local live = exists and active == target
    part.rows[1] = { unit = A.PROFILE_UNIT, label = "Active profile", old = active, new = target, change = not live,
        made = not exists }
    local modules = 0
    for _, e in ipairs(composed.list) do
        local f = A.BY_UNIT[e.unit]
        if f then
            local old = ReadField(from, f)
            part.rows[#part.rows + 1] = { unit = e.unit, label = f.label, old = old, new = e.value,
                change = not LY.Same(old, e.value), layer = e.layer }
        elseif ModuleOf(e.unit) then
            modules = modules + 1
            part.rows[#part.rows + 1] = { unit = e.unit, label = A.Label(e.unit), old = nil, new = e.value, change = true,
                whole = true, layer = e.layer }
        end
    end
    local keyRows = {}
    for _, row in ipairs(part.rows) do
        if row.change then part.changes = part.changes + 1 end
        keyRows[row.unit] = { LY.Fingerprint(row.old), row.whole and "whole" or LY.Fingerprint(row.new) }
    end
    -- Nothing to import: the install's profile is in use, every field reads as planned, and it was made from these
    -- same inputs (for a developer base, from the same profile name; that profile's later edits are not compared).
    part.nothing = part.changes == 0 and modules == 0 and ctx.lastInputs == part.inputs
    if not part.nothing and part.changes == 0 then
        part.changes = 1
        part.rows[1].change, part.rows[1].reimport = true, true
    end
    part.reload = not part.nothing
    part.key = LY.Canon({ target, active, home, part.inputs, keyRows, part.nothing })
    return part
end

---------------------------------------------------------------------------
-- Apply. Refused in combat (here, and by ImportProfileSilent). A failed import puts back the profile in use and removes
-- a profile it made. Returns { state, code, rollback, reload, stored, others }.
---------------------------------------------------------------------------
-- The recipient's profiles (by table identity) and spec assignments, read straight from EllesmereUI's profile store,
-- and the check that, the install's own profile aside, none was removed, replaced or added and no assignment changed.
-- (setup/Ellesmere.lua has the same check for sharing, but it goes through the sharing code's Forever-only gate.)
local function ProfilesSnapshot(E)
    local snap = { profiles = {}, assign = {} }
    local ok, db = pcall(E.GetProfilesDB)
    if not ok or type(db) ~= "table" or type(db.profiles) ~= "table" then return snap end
    for name, p in pairs(db.profiles) do snap.profiles[name] = p end
    for spec, name in pairs(type(db.specProfiles) == "table" and db.specProfiles or {}) do snap.assign[spec] = name end
    snap.checkable = true
    return snap
end

-- true when nothing else changed (or it could not be read: then checked = false), and how many things did.
local function OthersUnchanged(E, before, target)
    local after = ProfilesSnapshot(E)
    if not (before.checkable and after.checkable) then return true, 0, false end
    local n = 0
    for name, p in pairs(before.profiles) do if name ~= target and after.profiles[name] ~= p then n = n + 1 end end
    for name in pairs(after.profiles) do if name ~= target and before.profiles[name] == nil then n = n + 1 end end
    for spec, name in pairs(before.assign) do if after.assign[spec] ~= name then n = n + 1 end end
    for spec in pairs(after.assign) do if before.assign[spec] == nil then n = n + 1 end end
    return n == 0, n, true
end

function A.Apply(part)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat", rollback = "clean" } end
    if part.nothing then return { state = "skipped", code = "matches" } end
    local det, E = A.Detect(nil, part.dev)
    if not det.usable then return { state = "failed", code = "eui-" .. det.why, rollback = "clean" } end
    local target, home = part.target, part.home
    local before = ProfilesSnapshot(E)
    local existed = before.profiles[target] ~= nil
    local startActive = Active(E)

    local function Rollback()
        local now = Profiles(E)
        if Active(E) ~= startActive and type(now[startActive]) == "table" then pcall(E.SwitchProfile, startActive) end
        if Active(E) ~= startActive and type(now[home]) == "table" then pcall(E.SwitchProfile, home) end
        if not existed and type(Profiles(E)[target]) == "table" then pcall(E.DeleteProfile, target) end
        local clean = (Active(E) == startActive) and ((type(Profiles(E)[target]) == "table") == existed)
        return clean and "clean" or "partial"
    end

    -- Installing again: leave the install's own profile before it is replaced, so EllesmereUI never has to fall back
    -- to "Default" (what DeleteProfile does to the active profile).
    if startActive == target then
        pcall(E.SwitchProfile, home)
        if Active(E) ~= home then return { state = "failed", code = "eui-switch", rollback = Rollback() } end
    end
    local okE, str = pcall(E.EncodePayload, part.payload)
    if not okE or not ExportString(str) then return { state = "failed", code = "eui-encode", rollback = Rollback() } end
    local ok, done, err, status = pcall(E.ImportProfileSilent, { importString = str, profileName = target, cleanSlate = true,
        applyUIScale = false, autoAssignSpecs = false })
    if not ok then R.Fault("layouts: EllesmereUI import", done) end
    if not ok or done ~= true then
        return { state = "failed", code = (ok and err == "in combat") and "combat" or "eui-import", rollback = Rollback() }
    end
    -- nothing else about the recipient's profiles changed (the install's own profile aside)
    local fine, changed = OthersUnchanged(E, before, target)
    return { state = "done", reload = true, stored = status == "spec_locked", others = changed,
        code = (not fine) and "others-changed" or (status == "spec_locked" and "spec-locked" or nil) }
end

---------------------------------------------------------------------------
-- Verify: reads only (after the reload, at login). expect = { [unit] = fingerprint | "present" }.
---------------------------------------------------------------------------
function A.Verify(expect, snap)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then r.state, r.code = "unverifiable", "eui-" .. det.why return r end
    local prof = Profiles(E)[snap.target]
    if type(prof) ~= "table" then
        r.diffs[1] = { unit = A.PROFILE_UNIT, code = "target-missing" }
        r.state = "mismatch"
        return r
    end
    if Active(E) ~= snap.target then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-active" } end
    for _, unit in ipairs(LY.SortedKeys(expect)) do
        local f, m = A.BY_UNIT[unit], ModuleOf(unit)
        if f then
            r.checked = r.checked + 1
            if LY.Fingerprint(ReadField(prof, f)) ~= expect[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
        elseif m then
            r.checked = r.checked + 1
            if type(prof.addons) ~= "table" or type(prof.addons[m]) ~= "table" then r.diffs[#r.diffs + 1] = { unit = unit, code = "missing" } end
        else
            r.unverifiable = r.unverifiable + 1
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

function A.Expect(composed)
    local out = {}
    for _, e in ipairs(composed.list) do
        if A.BY_UNIT[e.unit] then out[e.unit] = LY.Fingerprint(e.value)
        elseif ModuleOf(e.unit) then out[e.unit] = "present" end
    end
    return out
end

---------------------------------------------------------------------------
-- Restore: back to the profile in use before, and the install's profile removed. Then a reload.
---------------------------------------------------------------------------
function A.PlanRestore(snap)
    local out = { adapter = A.id, actions = {} }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then out.blocked = "eui-" .. det.why return out end
    local profiles = Profiles(E)
    if Active(E) == snap.target then
        if type(profiles[snap.active]) ~= "table" then out.blocked = "previous-gone" return out end
        out.actions[#out.actions + 1] = { kind = "switch", from = snap.target, to = snap.active }
    end
    if snap.created and type(profiles[snap.target]) == "table" then out.actions[#out.actions + 1] = { kind = "delete", name = snap.target } end
    out.reload = #out.actions > 0
    out.key = LY.Canon(out.actions)
    return out
end

function A.Restore(snap)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat" } end
    local plan = A.PlanRestore(snap)
    if plan.blocked then return { state = "failed", code = plan.blocked } end
    local _, E = A.Detect(nil, snap.otherClient)
    local before = ProfilesSnapshot(E)
    for _, act in ipairs(plan.actions) do
        if act.kind == "switch" then
            pcall(E.SwitchProfile, act.to)
            if Active(E) ~= act.to then return { state = "failed", code = "eui-switch" } end
        else
            pcall(E.DeleteProfile, act.name)
            if type(Profiles(E)[act.name]) == "table" then return { state = "partial", code = "target-kept", reload = true } end
        end
    end
    local fine = OthersUnchanged(E, before, snap.target)
    return { state = "done", reload = plan.reload, code = (not fine) and "others-changed" or nil }
end

function A.VerifyRestore(snap, units)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    local det, E = A.Detect(nil, snap.otherClient)
    if not det.usable then r.state, r.code = "unverifiable", "eui-" .. det.why return r end
    local profiles = Profiles(E)
    if snap.created and type(profiles[snap.target]) == "table" then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "target-still-there" } end
    if Active(E) ~= snap.active then
        r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-previous" }
    else
        for _, unit in ipairs(units) do
            local f = A.BY_UNIT[unit]
            if not f or snap.values[unit] == nil then r.unverifiable = r.unverifiable + 1
            else
                r.checked = r.checked + 1
                if LY.Fingerprint(ReadField(profiles[snap.active], f)) ~= snap.values[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
            end
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

LY.RegisterAdapter(A)
