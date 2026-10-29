-- TwichUI Layouts: the twichui adapter, TwichUI's own settings (architecture.md §1, §4; adapter-capabilities.md)
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

-- A feature switch's name for a sentence ("Class resource bars", "Journey Chronicle: Chronicle bosses"): its group's label when it
-- is the group's own switch (the group's first field), else the group and the switch. nil for a unit that isn't a switch.
function A.FeatureLabel(unit)
    local f = A.FieldOf(unit)
    if not (f and f.switch) then return nil end
    local g = TC().Group(f.group)
    if f.label then return f.label end
    if g and g.fields[1] == f then return g.label end
    return (g and (g.label .. ": ") or "") .. TC().Humanize(f.key)
end

-- What a set of TwichUI units does, in words a review can use: units = { [unit] = value | LY.DEFAULT }.
-- Returns { on = { feature labels }, off = { feature labels }, set = n (other settings given a value), reset = n (put back to
-- TwichUI's default), total = n }. Labels sorted; a unit this TwichUI doesn't manage is counted in `unknown`. Read only.
function A.Summarize(units)
    local out = { on = {}, off = {}, set = 0, reset = 0, total = 0, unknown = 0 }
    for unit, v in pairs(units or {}) do
        out.total = out.total + 1
        local f = A.FieldOf(unit)
        if not f then out.unknown = out.unknown + 1
        elseif v == LY.DEFAULT then out.reset = out.reset + 1
        elseif f.switch and v == true then out.on[#out.on + 1] = A.FeatureLabel(unit)
        elseif f.switch and v == false then out.off[#out.off + 1] = A.FeatureLabel(unit)
        else out.set = out.set + 1 end
    end
    table.sort(out.on)
    table.sort(out.off)
    return out
end

function A.Show(v)
    if v == LY.DEFAULT then return "TwichUI's default" end
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
        elseif k ~= "groups" and k ~= "reset" then P.add("unknown-field", ctx.where .. "." .. tostring(k)) end
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
    -- (a fragment may hold only a reset list: the groups are read when there are some, and the reset list always)
    local groups = fragment.groups
    if groups ~= nil and type(groups) ~= "table" then P.add("not-table", ctx.where .. ".groups") return units, {} end
    local fields = A.Fields()
    local plain = {}   -- what TwichConfig's own check sees: every value but REMOVE
    for gid, slots in pairs(groups or {}) do
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
    -- reset (format 4): a managed setting back to TwichUI's own default (its stored value is cleared, so it follows the
    -- default of the TwichUI installed). Places can't be reset: a feature's default place isn't a value TwichUI can name.
    if fragment.reset ~= nil then
        LY.ResetList(fragment.reset, ctx, function(unit, where)
            if PlaceOf(unit) then P.add("reset-unsupported", where)
            elseif not A.FieldOf(unit) then P.add("not-managed", where)
            elseif units[unit] ~= nil then P.add("reset-and-set", where)
            else units[unit] = LY.DEFAULT end
        end)
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
-- Normalized values, for updates (Merge.lua): what one unit is in a profile's table t (TwichUIDB for the profile in
-- use, or a stored profile). A setting: the fingerprint of the value the feature uses, and "x" when it is stored or "d"
-- when nothing is (the default stands). A place: "@x,y[,POINT]" in whole units, or ABSENT (the feature's own default).
---------------------------------------------------------------------------
local function RawIn(t, f)
    for _, k in ipairs(f.at) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) == "table" then return t[f.key] end
end

function A.Normal(t, unit)
    local id = PlaceOf(unit)
    if id then
        local v = ReadPlace(t, id)
        if v then return PlaceText(v), "x" end
        return LY.Merge.ABSENT, "a"
    end
    local f = A.FieldOf(unit)
    if not f then return nil end
    local raw = RawIn(t, f)
    if raw ~= nil and TC().ValueOk(f, raw) then return LY.Value(raw), "x" end
    return LY.Value(f.default), "d"
end

-- The schema the comparison depends on: a baseline made under another can't be compared, unit by unit (Merge.lua).
function A.Schema() return ("twichui:%d:%s"):format(LY.Merge.VERSION, tostring(TC().SCHEMA)) end

-- The stored value of a unit as it is (for "Undo this update"): { v = copy } or {} when nothing is stored.
local function Keep(t, unit)
    local id = PlaceOf(unit)
    if id then
        local v = ReadPlace(t, id)
        return v and { v = v } or {}
    end
    local raw = RawIn(t, A.FieldOf(unit))
    return raw ~= nil and { v = LY.Copy(raw) } or {}
end

-- Where a place's anchor point sits on this screen, from the screen's centre (the check of kept places).
local function PlaceOnScreen(id, v, screen)
    local p = A.PLACES[id]
    local rel = (p.kind == "top" and "TOP") or (p.kind == "point" and v.point) or "CENTER"
    local sx, sy = LY.Geometry.Point(LY.Geometry.Screen(screen.w, screen.h), rel)
    return sx + v.x, sy + v.y
end

---------------------------------------------------------------------------
-- Plan: what Apply would do, read only. part = { adapter, action = "duplicate"|"switch"|"none", profile, target,
--   rows = { { unit, label, old, new, change, reload, layer, decision, kept } }, changes, reload, nothing, blocked, key,
--   merge (an update: Merge.lua's result), track (what the baseline takes once checked), undo (the values an update
--   replaces), warnings (kept places that are off the screen or over another piece) }
-- ctx.merge (an update only) = { part = the baseline's part for this adapter | nil, known, policy, choose, groups }
---------------------------------------------------------------------------
function A.Plan(composed, ctx)
    local part = { adapter = A.id, effect = A.effect, rows = {}, changes = 0, reload = false }
    local ok, why = PF().Available()
    if not ok then part.blocked = "profiles-" .. tostring(why) return part end
    local target, snap = ctx.target, ctx.snapshot
    if snap and snap.char ~= PF().Character() then part.blocked = "other-character" return part end
    local current, exists = PF().Current(), PF().Exists(target)
    if exists and not (Ours(snap, target) or ctx.owned) then part.blocked = "target-taken" return part end
    part.adopted = exists and ctx.force == true and not Ours(snap, target) or nil   -- forced: a profile that was already there
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
            local change, reset = not LY.Same(old, e.value), e.value == LY.DEFAULT
            if reset then
                -- reset: changes when a value is stored (it is cleared); by effective value it is the default
                local stored = RawIn(part.action == "switch" and type(TwichUIDB.profiles) == "table" and TwichUIDB.profiles[target] or TwichUIDB, f)
                change = stored ~= nil
            end
            part.rows[#part.rows + 1] = { unit = e.unit, label = A.Label(e.unit), old = old, new = e.value, change = change,
                layer = e.layer, field = f, reset = reset or nil }
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

    -- What the package says, normalized, for the baseline (and an update's comparison)
    local n = {}
    for i, row in ipairs(part.rows) do
        if i > 1 then
            -- a reset is compared by its effective value: TwichUI's default for that setting
            -- (written out: a default of false must not fall through an `and/or` to the reset marker)
            if row.place then n[row.unit] = PlaceText(row.new)
            elseif row.reset then n[row.unit] = LY.Value(A.FieldOf(row.unit).default)
            else n[row.unit] = LY.Value(row.new) end
        end
    end
    -- An update into the install's own profile: each unit compared with the baseline and what this profile holds now
    local M = ctx.merge
    if M and part.action ~= "duplicate" then
        -- a baseline part made under another merge contract or TwichUI schema isn't compared (only ownership still stands)
        local known = M.part ~= nil and M.part.merge == LY.Merge.VERSION and M.part.schema == A.Schema()
        part.known = known
        local entries, seen, nv = {}, {}, {}
        for i, row in ipairs(part.rows) do if i > 1 then nv[row.unit] = row.new end end   -- a reset shows as TwichUI's default
        local function Entry(unit)
            seen[unit] = true
            local c, cs = A.Normal(from, unit)
            if c == nil then return end   -- a setting this TwichUI no longer has: left alone
            local id, f = PlaceOf(unit), A.FieldOf(unit)
            local cv
            if id then cv = ReadPlace(from, id) else cv = part.action == "switch" and StoredValue(target, f) or TC().Effective(f) end
            local b = M.part and M.part.units[unit] or nil
            if not known and not (b and b.o) then b = nil end
            entries[#entries + 1] = { unit = unit, label = A.Label(unit), n = n[unit], c = c, cs = cs, b = b,
                comparable = true, known = known, keepAbsent = true, cv = cv, nv = nv[unit],
                variantOwned = composed.layer[unit] == "variant" }
        end
        for i, row in ipairs(part.rows) do if i > 1 then Entry(row.unit) end end
        for _, unit in ipairs(LY.SortedKeys(M.part and M.part.units or {})) do if not seen[unit] then Entry(unit) end end
        local result = LY.Merge.Run(entries, M)
        part.merge = result
        part.track = LY.Merge.Track(result, n)
        part.undo = { profile = current, target = target, values = {} }
        part.warnings = {}
        local kept = {}
        for i, row in ipairs(part.rows) do
            local r = i > 1 and result.by[row.unit]
            if r then
                row.decision = r.decision
                if r.decision ~= "apply" then row.change = false end
                if r.decision == "keep" or r.decision == "owned" then
                    row.kept = true
                    row.keptText = PlaceOf(row.unit) and r.e.c or LY.Fingerprint(r.e.cv)
                    local id = PlaceOf(row.unit)
                    local v = id and ReadPlace(from, id)
                    if v and ctx.geometry then
                        local x, y = PlaceOnScreen(id, v, ctx.geometry.screen)
                        kept[#kept + 1] = { unit = row.unit, label = row.label, x = x, y = y, comp = row.comp }
                    end
                end
                if row.change then part.undo.values[row.unit] = Keep(from, row.unit) end
            end
        end
        -- what the final plan leaves where the player has it (RH-1 C): every place kept, owned or released
        part.retained = {}
        for _, r in ipairs(result.rows) do
            local id = PlaceOf(r.unit)
            if id and (r.decision == "keep" or r.decision == "owned" or r.decision == "release") then
                local v = ReadPlace(from, id)
                part.retained[#part.retained + 1] = { adapter = A.id, unit = r.unit, id = id, label = A.PLACES[id].label, value = v }
                if v and ctx.geometry and r.decision == "release" then
                    local x, y = PlaceOnScreen(id, v, ctx.geometry.screen)
                    kept[#kept + 1] = { unit = r.unit, label = A.PLACES[id].label, x = x, y = y }
                end
            end
        end
        part.warnings = LY.Merge.CheckPlaces(ctx.geometry, kept)
    else
        part.track = {}
        for unit, text in pairs(n) do part.track[unit] = { p = text } end
        if M then part.fresh = "target-gone" end   -- the install's profile was removed: made again, nothing to compare
    end
    for _, row in ipairs(part.rows) do
        if row.field then
            row.reload = row.change and row.field.switch and R.Switches.NeedsReload(row.field.key) or false
            if row.reload then part.reload = true end
            row.field = nil
        end
    end

    local keyRows = {}
    for _, row in ipairs(part.rows) do
        if row.change then part.changes = part.changes + 1 end
        keyRows[row.unit] = { LY.Fingerprint(row.old), LY.Fingerprint(row.new), row.decision or false }
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
                if row.new == LY.DEFAULT then c[f.key] = nil else c[f.key] = LY.Copy(row.new) end   -- a reset clears it
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

-- What verification expects to read back for each unit the install writes (places as the plan placed them), and for each
-- unit an update kept as the recipient has it (so the check also shows nothing of theirs was overwritten).
function A.Expect(composed, part)
    local out = {}
    for _, e in ipairs(composed.list) do
        if not PlaceOf(e.unit) then
            -- a reset is checked by what the feature reads: its default (a value stored again would read differently)
            local f = e.value == LY.DEFAULT and A.FieldOf(e.unit)
            if f then out[e.unit] = LY.Fingerprint(f.default)   -- (a default of false is a value, not "no default")
            else out[e.unit] = LY.Fingerprint(e.value) end
        end
    end
    for _, row in ipairs(part and part.rows or {}) do
        if row.place then out[row.unit] = PlaceText(row.new) end
        if row.kept then
            if row.keptText ~= LY.Merge.ABSENT then out[row.unit] = row.keptText else out[row.unit] = nil end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The baseline: after the check matched, what each tracked unit reads now in the install's profile (in use)
-- Returns units = { [unit] = { p, l, s, k, o } }, schema
---------------------------------------------------------------------------
function A.Baseline(track, snap)
    local units = {}
    if PF().Current() ~= snap.target then return nil, "not-active" end
    for unit, t in pairs(track or {}) do
        if t.o then units[unit] = { o = true }
        else
            local text, s = A.Normal(TwichUIDB, unit)
            if text then units[unit] = { p = t.p, a = t.a, l = text ~= (t.a or t.p) and text or nil, s = s, k = t.k } end
        end
    end
    return units, A.Schema()
end

---------------------------------------------------------------------------
-- Undo this update: the values the update replaced in the install's profile go back, and this character uses the profile
-- it used before the update. u = record.update.twichui = { profile, target, values = { [unit] = { v } | {} } }
---------------------------------------------------------------------------
local function UndoKey(u)
    local vals = {}
    for unit, kv in pairs(u.values) do vals[unit] = LY.Fingerprint(kv.v) end
    return vals
end

function A.PlanUndo(u)
    local out = { adapter = A.id, actions = {} }
    if not PF().Available() then out.blocked = "profiles" return out end
    if not PF().Exists(u.target) then out.blocked = "target-missing" return out end
    local n = 0
    for _ in pairs(u.values) do n = n + 1 end
    if n > 0 then out.actions[#out.actions + 1] = { kind = "values", n = n, target = u.target } end
    if PF().Current() ~= u.profile then
        if not PF().Exists(u.profile) then out.blocked = "previous-gone" return out end
        out.actions[#out.actions + 1] = { kind = "switch", from = PF().Current(), to = u.profile }
    end
    out.key = LY.Canon({ out.actions, UndoKey(u) })
    return out
end

local function Path(t, keys, upto)
    for i = 1, upto do
        if type(t[keys[i]]) ~= "table" then t[keys[i]] = {} end
        t = t[keys[i]]
    end
    return t
end

local function PutBack(t, unit, kv)
    local id = PlaceOf(unit)
    if id then
        local p = A.PLACES[id]
        local c = Path(t, p.path, #p.path - 1)
        local key = p.path[#p.path]
        if p.kind == "point" then
            if kv.v == nil then
                if type(c[key]) == "table" then c[key].point, c[key].x, c[key].y = nil, nil, nil end
            else
                if type(c[key]) ~= "table" then c[key] = {} end
                c[key].point, c[key].x, c[key].y = kv.v.point, kv.v.x, kv.v.y
            end
        else
            c[key] = kv.v and { x = kv.v.x, y = kv.v.y } or nil
        end
        return
    end
    local f = A.FieldOf(unit)
    if not f then return end
    local c = Path(t, f.at, #f.at)
    c[f.key] = LY.Copy(kv.v)
end

function A.Undo(u)
    if InCombatLockdown and InCombatLockdown() then return { state = "failed", code = "combat" } end
    local plan = A.PlanUndo(u)
    if plan.blocked then return { state = "failed", code = plan.blocked } end
    local t = PF().Current() == u.target and TwichUIDB or TwichUIDB.profiles[u.target]
    if type(t) ~= "table" then return { state = "failed", code = "target-missing" } end
    local ok, err = pcall(function()
        for _, unit in ipairs(LY.SortedKeys(u.values)) do PutBack(t, unit, u.values[unit]) end
    end)
    if not ok then R.Fault("layouts: undo TwichUI settings", err) return { state = "partial", code = "write" } end
    if PF().Current() ~= u.profile then
        local okS, code = PF().Switch(u.profile)
        if not okS then return { state = "partial", code = "profile-" .. tostring(code) } end
    else
        PF().Refresh("layout")
    end
    return { state = "done", reload = R.Switches.ReloadPending() }
end

function A.VerifyUndo(u)
    local r = { adapter = A.id, diffs = {}, checked = 0, unverifiable = 0 }
    if not PF().Available() then r.state, r.code = "unverifiable", "profiles" return r end
    if PF().Current() ~= u.profile then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "not-previous" } end
    local t = PF().Current() == u.target and TwichUIDB or (TwichUIDB.profiles or {})[u.target]
    if type(t) ~= "table" then r.diffs[#r.diffs + 1] = { unit = A.PROFILE_UNIT, code = "target-missing" } r.state = "mismatch" return r end
    for _, unit in ipairs(LY.SortedKeys(u.values)) do
        local kv = u.values[unit]
        local id = PlaceOf(unit)
        local want
        if id then want = kv.v and PlaceText(kv.v) or LY.Merge.ABSENT
        else
            local f = A.FieldOf(unit)
            if f then want = LY.Value((kv.v ~= nil and TC().ValueOk(f, kv.v)) and kv.v or f.default) end
        end
        if want == nil then r.unverifiable = r.unverifiable + 1
        else
            r.checked = r.checked + 1
            if A.Normal(t, unit) ~= want then r.diffs[#r.diffs + 1] = { unit = unit, code = "differs" } end
        end
    end
    r.state = #r.diffs > 0 and "mismatch" or "match"
    return r
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
