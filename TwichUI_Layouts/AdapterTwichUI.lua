-- TwichUI Layouts: the twichui adapter, TwichUI's own settings (architecture.md §3, §4; adapter-capabilities.md)
-- Reuses what configuration sharing already has: TwichConfig's schema names every field, its value checks
-- (TC.ValueOk, TC.CleanEntry) decide what a value may be, and the same reading and writing paths (TC.Effective,
-- TC.Container) are used. Profiles.lua does every profile operation, refuses them in combat, and tells every feature
-- afterwards (PF.Refresh), so nothing here touches a feature's internals.
--
-- Managed fields (the allowlist): every field of a TwichConfig group that is shared field by field, kept in the
-- profile (account-wide fields are not: switching back on Restore would not put them back), and not kept local in
-- TC.LOCAL. Anything else is refused by name: list groups and places ("not yet"), and every key that acts for you,
-- talks to other players or is a record (never). A test walks the schema to hold that.
--
-- An install goes into its own profile, never the one in use: the profile in use is copied under the package's
-- target name (PF.Duplicate) and this character switches to it; the values are written there; Restore switches back
-- and removes the copy. Other profiles, and other characters' choices, are never changed. Profiles are per character,
-- so the snapshot says which character it belongs to, and only that character can verify or restore it.
--
-- Snapshot part: { char, profile = in use before, target, created = the target was made by this install,
--   values = { [unit] = fingerprint of the value in use before } }
--
-- Places (format 2 packages): where a few of TwichUI's own things sit on screen. They are TC.LOCAL "place" for
-- sharing (a share never moves another player's windows), but a layout the recipient chose does place them, through
-- the PLACES registry only: each entry's saved key and how that feature anchors it (read in its source). The screen
-- layer moves them with the component the package attaches them to; a card the package places from a component's
-- rect needs no value of its own. Windows the player opens and moves (party pins, the Cozy Bag guide, refreshments,
-- navigation's frame, settings) are not places a layout sets.

local R = TwichUI
local LY = R.Layouts
local A = { id = "twichui", contract = LY.CONTRACT, label = "TwichUI", effect = "immediate" }
LY.TwichUIAdapter = A

local PREFIX = "twichui:"
A.PROFILE_UNIT = PREFIX .. "profile"

local function TC() return R.TwichConfig end
local function PF() return R.Profiles end

local function Covered(path)
    local LOCAL = TC().LOCAL
    local p = path
    while p do
        if LOCAL[p] then return true end
        p = p:match("^(.*)%.[^.]+$")
    end
    return false
end

local function PathOf(f) return table.concat(f.at, ".") .. "." .. f.key end

-- path: from TwichUIDB (the profile in use) or a stored profile's table. kind: how the feature anchors it to the screen:
--   center: { x, y } from the screen's centre to its centre (classbars/Config.lua CB.Position, markers/Bar.lua,
--     nav/Arrow.lua PlaceOwn, modules/FoodDrinkUnlock.lua)
--   top: { x, y } from the screen's top centre to its top edge (modules/Training.lua, modules/WelcomeBack.lua Place)
--   point: { point, x, y } inside a larger table, from that point of the screen (healer/Display.lua)
-- fromRect: the package may place it from a component's rect alone (the cards have no stored place by default).
A.PLACES = {
    ["class-bars"] = { path = { "ui", "classBarsPosition", "main" }, kind = "center", label = "Class resource bars" },
    ["marker-bar"] = { path = { "ui", "markerBarPosition" }, kind = "center", label = "Marker bar" },
    ["nav-arrow"] = { path = { "ui", "navigation", "arrowPosition" }, kind = "center", label = "Navigation arrow" },
    ["food-drink"] = { path = { "ui", "foodDrinkPosition" }, kind = "center", label = "Food and drink buttons" },
    ["healer-watch"] = { path = { "ui", "healerWatch" }, kind = "point", label = "Healer Watch" },
    ["training-card"] = { path = { "ui", "trainingPosition" }, kind = "top", label = "New training card", fromRect = true },
    ["welcome-back"] = { path = { "ui", "welcomeBackPlace" }, kind = "top", label = "Welcome back card", fromRect = true },
}
function A.Positions() return A.PLACES end
local function PlaceUnit(id) return PREFIX .. "place." .. id end
local function PlaceOf(unit) local id = type(unit) == "string" and unit:match("^twichui:place%.(.+)$") return id and A.PLACES[id] and id end
A.PlaceOf = PlaceOf

local function ReadPath(t, path)
    for _, k in ipairs(path) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end
local POINTS = LY.Set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })

-- A place's value as a feature reads it from t (a profile's table): { x, y } or { point, x, y }, or nil.
local function ReadPlace(t, id)
    local p = A.PLACES[id]
    local v = ReadPath(t, p.path)
    if type(v) ~= "table" or not (Offset(v.x) and Offset(v.y)) then return nil end
    if p.kind == "point" then
        if not POINTS[v.point] then return nil end
        return { point = v.point, x = v.x, y = v.y }
    end
    return { x = v.x, y = v.y }
end

local function PlaceValueOk(id, v)
    local p = A.PLACES[id]
    if type(v) ~= "table" or not (Offset(v.x) and Offset(v.y)) then return false end
    for k in pairs(v) do
        if not (k == "x" or k == "y" or (k == "point" and p.kind == "point")) then return false end
    end
    return p.kind ~= "point" or POINTS[v.point] ~= nil
end

local function PlaceText(v)
    if type(v) ~= "table" then return nil end
    return ("@%d,%d%s"):format(math.floor(v.x + 0.5), math.floor(v.y + 0.5), v.point and ("," .. v.point) or "")
end

local index   -- path -> field, kept once the schema is complete
-- { [path] = field } of every managed field.
function A.Fields()
    if index then return index end
    local out, complete = {}, true
    for _, g in ipairs(TC().Groups()) do
        if not g.complete then complete = false
        elseif not g.custom then
            for _, f in ipairs(g.fields) do
                local path = PathOf(f)
                if f.scope == "profile" and not Covered(path) then out[path] = f end
            end
        end
    end
    if complete then index = out end
    return out
end

function A.FieldOf(unit)
    if type(unit) ~= "string" or unit:sub(1, #PREFIX) ~= PREFIX then return nil end
    return A.Fields()[unit:sub(#PREFIX + 1)]
end

function A.Label(unit)
    if unit == A.PROFILE_UNIT then return "Profile" end
    local place = PlaceOf(unit)
    if place then return A.PLACES[place].label end
    local f = A.FieldOf(unit)
    if not f then return unit end
    local g = TC().Group(f.group)
    return (g and g.label or f.group) .. " > " .. (f.label or TC().Humanize(f.key))
end

function A.Show(v)
    if v == true then return "on" elseif v == false then return "off" elseif v == nil then return "(not set)" end
    if type(v) == "table" and type(v.x) == "number" then
        return ("%d, %d%s"):format(math.floor(v.x + 0.5), math.floor(v.y + 0.5), v.point and (" from " .. v.point:lower()) or "")
    end
    return tostring(v)
end

function A.TargetName(name) return R.Persist.ProfileName(name) == name end

function A.Detect()
    local ok, why = PF().Available()
    return { present = true, usable = ok and true or false, why = not ok and why or nil }
end

---------------------------------------------------------------------------
-- A fragment: { groups = { [group] = { [slot] = { [key] = value | REMOVE } } } } (TwichConfig's own shape)
---------------------------------------------------------------------------
function A.Normalize(fragment, ctx)
    local P, units = ctx.problems, {}
    for k in pairs(fragment) do
        if k == "places" then
            if (ctx.format or 1) < 2 then P.add("not-yet", ctx.where .. ".places") end
        elseif k ~= "groups" then P.add("unknown-field", ctx.where .. "." .. tostring(k)) end
    end
    if (ctx.format or 1) >= 2 and fragment.places ~= nil then
        if type(fragment.places) ~= "table" then P.add("not-table", ctx.where .. ".places")
        else
            for id, v in pairs(fragment.places) do
                if not A.PLACES[id] then P.add("unknown-unit", ctx.where .. ".places." .. tostring(id))
                elseif v == LY.REMOVE or PlaceValueOk(id, v) then units[PlaceUnit(id)] = v
                else P.add("bad-value", PlaceUnit(id)) end
            end
        end
    end
    local groups = fragment.groups
    if groups == nil then return units, {} end
    if type(groups) ~= "table" then P.add("not-table", ctx.where .. ".groups") return units, {} end
    local fields = A.Fields()
    local plain = {}   -- what TwichConfig's own check sees: every value but REMOVE
    for gid, slots in pairs(groups) do
        local where = ctx.where .. ".groups." .. tostring(gid)
        local g = type(gid) == "string" and TC().Group(gid)
        if not g then P.add("unknown-group", where)
        elseif g.custom then P.add("not-yet", where)   -- a list group: replaced whole, which needs its own apply
        elseif type(slots) ~= "table" then P.add("not-table", where)
        else
            for slot, vals in pairs(slots) do
                local idx = type(slot) == "string" and g.index[slot]
                if type(vals) ~= "table" then P.add("not-table", where .. "." .. tostring(slot))
                else
                    for key, v in pairs(vals) do
                        local f = idx and type(key) == "string" and idx[key]
                        local unit = f and (PREFIX .. PathOf(f))
                        if not f then P.add("unknown-unit", where .. "." .. tostring(slot) .. "." .. tostring(key))
                        elseif not fields[PathOf(f)] then P.add("not-managed", unit)
                        elseif v == LY.REMOVE then units[unit] = LY.REMOVE
                        elseif not TC().ValueOk(f, v) then P.add("bad-value", unit)
                        else
                            units[unit] = v
                            plain[gid] = plain[gid] or {}
                            plain[gid][slot] = plain[gid][slot] or {}
                            plain[gid][slot][key] = v
                        end
                    end
                end
            end
        end
    end
    -- and TwichConfig's own check of the groups as a whole (bounds, each group's consistency rule)
    if next(plain) then
        local clean = TC().CleanEntry({ schema = TC().SCHEMA, groups = plain })
        if not clean or clean.status ~= "ok" or (clean.unknown or 0) > 0 then
            P.add("bad-value", ctx.where .. ".groups")
        else
            for gid in pairs(clean.rejected or {}) do P.add("bad-value", ctx.where .. ".groups." .. gid) end
        end
    end
    return units, {}
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
-- What a stored profile (not the one in use) gives a field when it is put in place: its value, or the default.
local function StoredValue(name, f)
    local data = type(TwichUIDB.profiles) == "table" and TwichUIDB.profiles[name]
    local t = data
    for _, k in ipairs(f.at) do
        if type(t) ~= "table" then t = nil break end
        t = t[k]
    end
    local v = type(t) == "table" and t[f.key] or nil
    if v ~= nil and TC().ValueOk(f, v) then return v end
    return f.default
end

local function Ours(snap, target) return type(snap) == "table" and snap.created == true and snap.target == target end

function A.Capture(composed, target, part)
    local snap = { char = PF().Character(), profile = PF().Current(), target = target, created = not PF().Exists(target), values = {} }
    for _, e in ipairs(composed.list) do
        local f = A.FieldOf(e.unit)
        if f then snap.values[e.unit] = LY.Fingerprint(TC().Effective(f)) end
    end
    for _, row in ipairs(part and part.rows or {}) do
        local id = PlaceOf(row.unit)
        if id then snap.values[row.unit] = LY.Fingerprint(PlaceText(ReadPlace(TwichUIDB, id))) end
    end
    return snap
end

function A.CleanSnapshot(s)
    if type(s) ~= "table" then return false end
    if not (LY.Plain(s.char, 64) and A.TargetName(s.target) and type(s.profile) == "string" and #s.profile <= 64) then return false end
    if type(s.created) ~= "boolean" or type(s.values) ~= "table" then return false end
    return true
end

---------------------------------------------------------------------------
-- Plan: what Apply would do, read only. part = { adapter, action = "duplicate"|"switch"|"none", profile, target,
--   rows = { { unit, label, old, new, change, reload, layer } }, changes, reload, nothing, blocked, key }
---------------------------------------------------------------------------
function A.Plan(composed, ctx)
    local part = { adapter = A.id, effect = A.effect, rows = {}, changes = 0, reload = false }
    local ok, why = PF().Available()
    if not ok then part.blocked = "profiles-" .. tostring(why) return part end
    local target, snap = ctx.target, ctx.snapshot
    if snap and snap.char ~= PF().Character() then part.blocked = "other-character" return part end
    local current, exists = PF().Current(), PF().Exists(target)
    if exists and not Ours(snap, target) then part.blocked = "target-taken" return part end
    if current == target then part.action = "none"
    elseif exists then part.action = "switch"
    else part.action = "duplicate" end
    part.profile, part.target = current, target
    part.rows[1] = { unit = A.PROFILE_UNIT, label = "Profile", old = current, new = target, change = part.action ~= "none" }
    for _, e in ipairs(composed.list) do
        if not PlaceOf(e.unit) then
            local f = A.FieldOf(e.unit)
            if not f then part.blocked = "schema-changed" return part end
            local old
            if part.action == "switch" then old = StoredValue(target, f) else old = TC().Effective(f) end
            local change = not LY.Same(old, e.value)
            local reload = change and f.switch and R.Switches.NeedsReload(f.key) or false
            part.rows[#part.rows + 1] = { unit = e.unit, label = A.Label(e.unit), old = old, new = e.value, change = change,
                reload = reload, layer = e.layer }
            if reload then part.reload = true end
        end
    end
    -- Places: each moved for this screen with the component it is attached to (or written as given, with no geometry)
    local from = part.action == "switch" and type(TwichUIDB.profiles) == "table" and TwichUIDB.profiles[target] or TwichUIDB
    local placed, notes = A.Places(composed, ctx.geometry, ctx.attach)
    part.notes = notes
    for _, id in ipairs(LY.SortedKeys(placed)) do
        local old, new = ReadPlace(from, id), placed[id].value
        part.rows[#part.rows + 1] = { unit = PlaceUnit(id), label = A.PLACES[id].label, old = old, new = new,
            change = PlaceText(old) ~= PlaceText(new), place = true, comp = placed[id].comp }
    end
    local keyRows = {}
    for _, row in ipairs(part.rows) do
        if row.change then part.changes = part.changes + 1 end
        keyRows[row.unit] = { LY.Fingerprint(row.old), LY.Fingerprint(row.new) }
    end
    part.nothing = part.changes == 0
    part.key = LY.Canon({ part.action, current, target, keyRows })
    return part
end

---------------------------------------------------------------------------
-- Apply: the profile, then plain assignments, then every feature is told once. Refused in combat here and by
-- Profiles.lua. Returns { state = "done"|"skipped"|"failed", code, rollback = "clean"|"partial", reload, refreshFailed }
---------------------------------------------------------------------------
function A.Apply(part)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat", rollback = "clean" } end
    if part.nothing then return { state = "skipped", code = "matches" } end
    local before = PF().Current()
    local moved
    if part.action == "duplicate" then
        local ok, code = PF().Duplicate(part.target)
        if not ok then return { state = "failed", code = "profile-" .. tostring(code), rollback = "clean" } end
        moved = "created"
    elseif part.action == "switch" then
        local ok, code = PF().Switch(part.target)
        if not ok then return { state = "failed", code = "profile-" .. tostring(code), rollback = "clean" } end
        moved = "switched"
    end
    local written = {}
    local ok, err = pcall(function()
        for _, row in ipairs(part.rows) do
            local place = PlaceOf(row.unit)
            if row.change and place then
                -- the place's table (made where missing); a point place keeps the other keys of the table it is in
                local path = A.PLACES[place].path
                local c = TwichUIDB
                for i = 1, #path - 1 do
                    if type(c[path[i]]) ~= "table" then
                        written[#written + 1] = { c = c, key = path[i], had = c[path[i]] }
                        c[path[i]] = {}
                    end
                    c = c[path[i]]
                end
                local key = path[#path]
                if A.PLACES[place].kind == "point" then
                    if type(c[key]) ~= "table" then
                        written[#written + 1] = { c = c, key = key, had = c[key] }
                        c[key] = {}
                    end
                    local t = c[key]
                    for _, k in ipairs({ "point", "x", "y" }) do
                        written[#written + 1] = { c = t, key = k, had = t[k] }
                        t[k] = row.new[k]
                    end
                else
                    written[#written + 1] = { c = c, key = key, had = c[key] }
                    c[key] = { x = row.new.x, y = row.new.y }
                end
            elseif row.change and row.unit ~= A.PROFILE_UNIT then
                local f = A.FieldOf(row.unit)
                local c = TC().Container(f, true)
                written[#written + 1] = { c = c, key = f.key, had = c[f.key] }
                c[f.key] = LY.Copy(row.new)
            end
        end
    end)
    if not ok then
        R.Fault("layouts: TwichUI settings", err)
        for i = #written, 1, -1 do written[i].c[written[i].key] = written[i].had end
        local back = true
        if moved then
            back = PF().Switch(before) and true or false
            if back and moved == "created" then back = PF().Delete(part.target) and true or false end
        end
        return { state = "failed", code = "write", rollback = back and "clean" or "partial" }
    end
    local okR, _, info = PF().Refresh("layout")
    return { state = "done", reload = okR and info and info.reload or false,
        refreshFailed = okR and info and #info.failed or 0, code = (okR and info and #info.failed > 0) and "refresh-failed" or nil }
end

---------------------------------------------------------------------------
-- Verify: reads only. expect = { [unit] = fingerprint }. Returns { state = "match"|"mismatch"|"unverifiable", code,
--   diffs = { { unit, code } }, checked, unverifiable }
---------------------------------------------------------------------------
function A.Verify(expect, snap)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    if not PF().Available() then r.state, r.code = "unverifiable", "profiles" return r end
    if PF().Character() ~= snap.char then r.state, r.code = "unverifiable", "other-character" return r end
    local live = PF().Current() == snap.target
    if not live then
        r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = PF().Exists(snap.target) and "not-active" or "target-missing" }
        if not PF().Exists(snap.target) then r.state = "mismatch" return r end
    end
    for _, unit in ipairs(LY.SortedKeys(expect)) do
        local f, place = A.FieldOf(unit), PlaceOf(unit)
        if place then
            -- within a unit of the plan
            r.checked = r.checked + 1
            local v = ReadPlace(live and TwichUIDB or (TwichUIDB.profiles or {})[snap.target], place)
            local want = { expect[unit]:match("^@(%-?%d+),(%-?%d+),?(%u*)$") }
            if not v or not want[1] or math.abs(v.x - tonumber(want[1])) > 1 or math.abs(v.y - tonumber(want[2])) > 1
                or (want[3] ~= "" and v.point ~= want[3]) then
                r.diffs[#r.diffs + 1] = { unit = unit, code = v and "moved" or "missing" }
            end
        elseif not f then r.unverifiable = r.unverifiable + 1
        else
            r.checked = r.checked + 1
            local v
            if live then v = TC().Effective(f) else v = StoredValue(snap.target, f) end
            if LY.Fingerprint(v) ~= expect[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

---------------------------------------------------------------------------
-- Restore: back to the profile in use before, and the install's own profile removed.
---------------------------------------------------------------------------
-- { actions = { { kind = "switch", from, to } | { kind = "delete", name } }, blocked }
function A.PlanRestore(snap)
    local out = { adapter = A.id, actions = {} }
    if not PF().Available() then out.blocked = "profiles" return out end
    if PF().Character() ~= snap.char then out.blocked = "other-character" return out end
    if PF().Current() == snap.target then
        if not PF().Exists(snap.profile) then out.blocked = "previous-gone" return out end
        out.actions[#out.actions + 1] = { kind = "switch", from = snap.target, to = snap.profile }
    end
    if snap.created and PF().Exists(snap.target) then out.actions[#out.actions + 1] = { kind = "delete", name = snap.target } end
    out.key = LY.Canon(out.actions)
    return out
end

function A.Restore(snap)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat" } end
    local plan = A.PlanRestore(snap)
    if plan.blocked then return { state = "failed", code = plan.blocked } end
    for _, act in ipairs(plan.actions) do
        if act.kind == "switch" then
            local ok, code = PF().Switch(act.to)
            if not ok then return { state = "failed", code = "profile-" .. tostring(code) } end
        else
            local ok, code = PF().Delete(act.name)
            if not ok then return { state = "partial", code = "target-kept-" .. tostring(code) } end
        end
    end
    return { state = "done", reload = R.Switches.ReloadPending() }
end

-- After a restore: the install's profile is gone, this character uses the profile it used before, and that profile
-- holds the values the snapshot saw. units: the units the install managed.
function A.VerifyRestore(snap, units)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    if not PF().Available() then r.state, r.code = "unverifiable", "profiles" return r end
    if PF().Character() ~= snap.char then r.state, r.code = "unverifiable", "other-character" return r end
    if snap.created and PF().Exists(snap.target) then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "target-still-there" } end
    if PF().Current() ~= snap.profile then
        r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-previous" }
    else
        for _, unit in ipairs(units) do
            local f, place = A.FieldOf(unit), PlaceOf(unit)
            if place and snap.values[unit] ~= nil then
                r.checked = r.checked + 1
                if LY.Fingerprint(PlaceText(ReadPlace(TwichUIDB, place))) ~= snap.values[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
            elseif not f or snap.values[unit] == nil then r.unverifiable = r.unverifiable + 1
            else
                r.checked = r.checked + 1
                if LY.Fingerprint(TC().Effective(f)) ~= snap.values[unit] then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
            end
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
end

-- What verification expects to read back for each unit the install writes (places as the plan placed them).
function A.Expect(composed, part)
    local out = {}
    for _, e in ipairs(composed.list) do
        if not PlaceOf(e.unit) then out[e.unit] = LY.Fingerprint(e.value) end
    end
    for _, row in ipairs(part and part.rows or {}) do
        if row.place then out[row.unit] = PlaceText(row.new) end
    end
    return out
end

---------------------------------------------------------------------------
-- The screen layer for places. Pure: composed values and the resolved screen in, places out.
-- Returns { [id] = { value, comp } }, notes { { code, id } }.
---------------------------------------------------------------------------
-- Where one place goes on this screen (the install and the preview both call it). v = the stored value ({ x, y [, point] }),
-- comp = the resolved component it is attached to, pt = the point of it to follow ("" for its centre).
-- Returns { x, y, point } as stored (point only for a place that keeps one).
local function PlaceOne(p, v, comp, pt, geo)
    local Gm = LY.Geometry
    local point = (p.kind == "top" and "TOP") or (p.kind == "point" and v and v.point) or "CENTER"
    local mv = Gm.Moved(comp, pt ~= "" and pt or nil)
    local x, y = Gm.Follow({ rel = point, x = v.x, y = v.y }, mv, geo.canvas, geo.screen)
    return { x = x, y = y, point = p.kind == "point" and point or nil }, point
end
A.PlaceOne = PlaceOne

function A.Places(composed, geo, attach)
    local out, notes = {}, {}
    local Gm = LY.Geometry
    for _, e in ipairs(composed.list) do
        local id = PlaceOf(e.unit)
        if id and not (geo and attach and attach[id]) then out[id] = { value = LY.Copy(e.value) } end
    end
    if not (geo and attach) then return out, notes end
    for _, id in ipairs(LY.SortedKeys(attach)) do
        local p = A.PLACES[id]
        local compId, pt = attach[id]:match("^([%w%-]+):?(%u*)$")
        local comp = geo.components[compId]
        local v = composed.units[PlaceUnit(id)]
        local point = (p.kind == "top" and "TOP") or (p.kind == "point" and v and v.point) or "CENTER"
        if v ~= nil then
            out[id] = { value = (PlaceOne(p, v, comp, pt, geo)), comp = compId }
        elseif p.fromRect then
            local x, y = Gm.Stored(comp.rect, point, point, geo.screen)
            out[id] = { value = { x = x, y = y }, comp = compId }
        else
            notes[#notes + 1] = { code = "not-stored", id = id }
        end
    end
    return out, notes
end

LY.RegisterAdapter(A)
