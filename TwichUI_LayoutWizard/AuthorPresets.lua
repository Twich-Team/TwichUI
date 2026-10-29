-- TwichUI Layout Setup: the authoring workspace's TwichUI presets (docs/layouts/presets.md)
-- The options of the package's helper-preset selector ("TwichUI helpers"), edited in game: capture the TwichUI settings of a
-- profile into a preset, create, duplicate, rename, describe, reorder, make default and remove options, and choose exactly which
-- settings each one manages. No frames here (AuthorWindow.lua draws it), so every rule is tested without a screen.
--
-- Two levels, never mixed up:
--   the DRAFT     the selector as the package being authored will have it (s.presets.options). Author.Draft writes it into the
--                 package's `choices` (AP.Apply), so Check, Publish, Send and the bundling import all see exactly it.
--   a PENDING edit one option being captured or reviewed (s.presets.pending): nothing of it is in the draft until Save to draft;
--                 Discard drops it. AP.Unsaved() says when there is one with changes.
-- Nothing here writes a profile, a setting, a published package or anything the game uses: capturing READS one TwichUI profile
-- (the one in use by default; never switched to), through the TwichUI adapter's allowlist.
--
-- Representation (package format 6; Package.lua): the selector becomes `mode = "settings"`; an option is either `keep = true` (the
-- structural "leave them as they are": names nothing) or `twichui = { groups = { [group] = { [slot] = { [key] = value } } },
-- reset = { units } }`: each named setting is SET to that value (false, 0 and "" included) or RESET to TwichUI's default; a setting
-- the option doesn't name is not managed (never "reset" by being left out). Removed options' ids are kept in `retired` so a later
-- option can't take one over. An older switch-on-only selector is shown as it is, and becomes a settings selector (with the same
-- settings, the same values) only when the author saves a change to it; it is never reread as anything else.

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local AP = {}
WZ.AuthorPresets = AP

local TA = LY.TwichUIAdapter
local function TC() return R.TwichConfig end
local function A() return WZ.Author end
local function Session() return A().Session() end

AP.MAX_UNITS = LY.MAX_UNITS              -- settings one preset may manage (the package's bound for one fragment)
AP.LABEL_MAX, AP.HINT_MAX = 48, 200      -- an option's name and description (Package.lua's bounds)
AP.CHOICE_HINT_MAX = 200
AP.SETTINGS_HINT = "Which of TwichUI's own features the setup turns on or off, and how they behave and look. Features that act for you or talk to other players are never part of a preset."

---------------------------------------------------------------------------
-- What a preset may manage, and what it never does (built once per game session: the schema doesn't change while it runs)
---------------------------------------------------------------------------
local eligible   -- { list = { e }, by = { [unit] = e }, groups = { { id, label, n } } }

-- e = { unit, f, group, groupLabel, label, lower (for search), switch, order }
function AP.Eligible()
    if eligible then return eligible end
    local fields = TA.Fields()
    local out = { list = {}, by = {}, groups = {} }
    for _, g in ipairs(TC().Groups()) do
        local n = 0
        if not g.custom then
            for _, f in ipairs(g.fields) do
                local path = table.concat(f.at, ".") .. "." .. f.key
                if fields[path] == f then
                    local unit = "twichui:" .. path
                    local label = f.switch and TA.FeatureLabel(unit) or (f.label or TC().Humanize(f.key))
                    local e = { unit = unit, f = f, group = g.id, groupLabel = g.label, label = label, switch = f.switch == true,
                        order = #out.list + 1 }
                    e.lower = (label .. " " .. g.label):lower()
                    out.list[#out.list + 1] = e
                    out.by[unit] = e
                    n = n + 1
                end
            end
        end
        if n > 0 then out.groups[#out.groups + 1] = { id = g.id, label = g.label, n = n } end
    end
    -- only kept once the schema was complete (as the adapter keeps its own index)
    local complete = true
    for _, g in ipairs(TC().Groups()) do if not g.complete then complete = false end end
    if complete then eligible = out end
    return out
end

-- What is never in a preset, by category, with the reason: { { title, why, n, examples = { labels } } }. Read only.
local LOCAL_TITLE = { acts = "Acts for you", network = "Sends to or accepts from other players", place = "Where things sit on screen",
    other = "Records, personal lists and switches that stay yours" }
function AP.Excluded()
    local out = {}
    local why = {}
    for _, s in ipairs(TC().STAYS or {}) do why[s.code] = s.text end
    local count = {}
    for key, code in pairs(TC().LOCAL) do
        count[code] = count[code] or {}
        count[code][#count[code] + 1] = key
    end
    for _, code in ipairs({ "acts", "network", "place", "other" }) do
        local keys = count[code] or {}
        table.sort(keys)
        out[#out + 1] = { title = LOCAL_TITLE[code], why = why[code] or "", n = #keys, code = code }
    end
    local lists, account = {}, {}
    for _, g in ipairs(TC().Groups()) do
        if g.custom then lists[#lists + 1] = g.label
        else
            for _, f in ipairs(g.fields) do
                if f.scope ~= "profile" then account[#account + 1] = (g.label .. " > " .. (f.label or TC().Humanize(f.key))) end
            end
            if g.scope == "account" and #g.fields == 0 then account[#account + 1] = g.label end
        end
    end
    out[#out + 1] = { title = "Lists", n = #lists, examples = lists, code = "list",
        why = "Each is replaced as a whole and has no safe way to be compared, verified and put back setting by setting, so a preset can't hold it. Set them in TwichUI's own settings." }
    out[#out + 1] = { title = "Account-wide settings", n = #account, examples = account, code = "account",
        why = "They belong to every character and every profile, so Restore (which switches profiles back) couldn't put them back." }
    local places = {}
    for _, p in pairs(TA.PLACES) do places[#places + 1] = p.label end
    table.sort(places)
    out[#out + 1] = { title = "Positions", n = #places, examples = places, code = "positions",
        why = "Where TwichUI's own pieces sit belongs to the layout, which places them for each player's screen. A preset never moves anything." }
    return out
end

---------------------------------------------------------------------------
-- The selector in the starting package
---------------------------------------------------------------------------
local function OpsOf(units)
    local ops = {}
    for unit, v in pairs(units or {}) do
        if v == LY.DEFAULT then ops[unit] = { reset = true } else ops[unit] = { v = LY.Copy(v) } end
    end
    return ops
end

local function CopyOps(ops)
    local out = {}
    for unit, op in pairs(ops or {}) do out[unit] = op.reset and { reset = true } or { v = LY.Copy(op.v) } end
    return out
end

local function SameOp(a, b)
    if a == nil or b == nil then return a == b end
    if a.reset or b.reset then return (a.reset and b.reset) and true or false end
    return LY.Same(a.v, b.v)
end

local function Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- Sets up s.presets from the starting package (Author.UseBase calls it). Read only.
function AP.Init(s)
    local pkg = s.basePkg
    local ok, _, checked = LY.Validate(pkg)
    local P = { options = {}, retired = {}, gen = 0, publishedGen = 0, changed = false }
    s.presets = P
    if not ok then P.none = "invalid" return P end
    local index
    for i, ch in ipairs(pkg.choices or {}) do
        if ch.kind == "preset" then index = i break end
    end
    if not index then P.none = "no-selector" return P end
    local raw = pkg.choices[index]
    local ch = checked.choices.by[raw.id]
    P.index, P.id, P.label = index, raw.id, raw.label
    P.mode, P.hint, P.origHint = ch.mode, raw.hint, raw.hint
    P.default, P.origDefault = raw.default, raw.default
    for _, rid in ipairs(raw.retired or {}) do P.retired[#P.retired + 1] = rid end
    P.origRetired = #P.retired
    P.baseIds = {}
    for _, o in ipairs(raw.options) do
        local co = ch.options[o.id]
        local units = co.frags.twichui and co.frags.twichui.units or {}
        local opt = { id = o.id, label = o.label, hint = o.hint, keep = co.keep, ops = OpsOf(units), origin = "package" }
        -- an option of an older selector that names nothing is that selector's "leave them as they are"
        if not ch.mode and next(units) == nil then opt.structural = true end
        opt.orig = { label = opt.label, hint = opt.hint, ops = CopyOps(opt.ops), keep = opt.keep }
        P.options[#P.options + 1] = opt
        P.baseIds[o.id] = true
    end
    P.selected = P.default
    -- what other parts of the package set: the layout's own layers (the preset's value wins over them when it is picked) and the
    -- other choices (a preset can't set what another choice sets)
    P.layer, P.owned = {}, {}
    local f = checked.layers.base.twichui
    for unit in pairs(f and f.units or {}) do P.layer[unit] = "base" end
    for _, vid in ipairs(checked.variants) do
        local vf = checked.layers.variants[vid].twichui
        for unit in pairs(vf and vf.units or {}) do P.layer[unit] = P.layer[unit] or "variant" end
    end
    for cid, c in pairs(checked.choices.by) do
        if cid ~= raw.id then
            for _, o in pairs(c.options) do
                for _, fr in pairs(o.frags) do for unit in pairs(fr.units) do P.owned[unit] = c.label or cid end end
            end
        end
    end
    P.source = R.Profiles and R.Profiles.Current() or nil
    return P
end

function AP.State() local s = Session() return s and s.presets or nil end

local function Find(id)
    local P = AP.State()
    for i, o in ipairs(P and P.options or {}) do if o.id == id then return o, i end end
end
AP.Find = Find

function AP.IsKeep(o) return o ~= nil and (o.keep == true or o.structural == true) end

-- The draft changed: the selector becomes an editable one (its options keep exactly the settings and values they had; an option
-- that named nothing becomes the "leave them as they are" option), the check is out of date.
local function Touch()
    local P = AP.State()
    local s = Session()
    if P.mode ~= "settings" then
        P.mode, P.converted = "settings", true
        for _, o in ipairs(P.options) do
            if o.structural then o.keep, o.structural = true, nil end
        end
        if P.hint == P.origHint then P.hint = AP.SETTINGS_HINT end
    end
    P.changed = true
    P.gen = P.gen + 1
    s.report = nil
end

---------------------------------------------------------------------------
-- Reading settings from a TwichUI profile (never written, never switched to)
---------------------------------------------------------------------------
function AP.Sources() return R.Profiles and R.Profiles.List() or {} end
function AP.Source() local P = AP.State() return P and P.source end
function AP.SourceInUse() local P = AP.State() return P ~= nil and R.Profiles ~= nil and P.source == R.Profiles.Current() end

function AP.SetSource(name)
    local P = AP.State()
    if not P then return false, "closed" end
    for _, n in ipairs(AP.Sources()) do
        if n == name then P.source = name return true end
    end
    return false, "no-profile"
end

local function Slot(name) return A().TwichSlot(name) end

local function ReadPath(t, at, key)
    for _, k in ipairs(at) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) == "table" then return t[key] end
end

-- The value a feature would use from that profile: the stored value when it is one the setting can have, else the default.
local function EffectiveIn(slot, f)
    local v = ReadPath(slot, f.at, f.key)
    if v ~= nil and TC().ValueOk(f, v) then return LY.Copy(v) end
    return LY.Copy(f.default)
end

-- Every setting a preset may manage, as the source profile has it: { [unit] = value } | nil, code.
function AP.ReadAll()
    local P = AP.State()
    local slot = P and P.source and Slot(P.source)
    if not slot then return nil, "no-twichui-profile" end
    local t0 = R.Perf.on and R.Perf.Start("layoutwizard.presets.capture")
    local out = {}
    for _, e in ipairs(AP.Eligible().list) do out[e.unit] = EffectiveIn(slot, e.f) end
    if t0 then R.Perf.Stop(t0) end
    return out
end

function AP.ReadOne(unit)
    local P = AP.State()
    local e = AP.Eligible().by[unit]
    local slot = P and P.source and Slot(P.source)
    if not (e and slot) then return nil end
    return EffectiveIn(slot, e.f)
end

---------------------------------------------------------------------------
-- The options as the draft has them
---------------------------------------------------------------------------
local function UnitsOf(ops)
    local units = {}
    for unit, op in pairs(ops) do units[unit] = op.reset and LY.DEFAULT or op.v end
    return units
end
AP.UnitsOf = UnitsOf

-- Problems with one option as it stands, in words (Check also validates the whole package).
function AP.Issues(o)
    local P = AP.State()
    local out = {}
    if not LY.Plain(o.label, AP.LABEL_MAX) then out[#out + 1] = "Its name must be plain text of at most 48 characters." end
    if o.hint ~= nil and not LY.Plain(o.hint, AP.HINT_MAX) then out[#out + 1] = "Its description must be plain text of at most 200 characters." end
    local n = Count(o.ops)
    if AP.IsKeep(o) then
        if n > 0 then out[#out + 1] = "The \"leave them as they are\" option can't manage settings." end
    elseif n == 0 then out[#out + 1] = "It manages no settings: include some, or remove it."
    elseif n > AP.MAX_UNITS then out[#out + 1] = ("It manages %d settings; a preset may manage at most %d."):format(n, AP.MAX_UNITS) end
    for unit in pairs(o.ops) do
        if P.owned[unit] then out[#out + 1] = ("It sets %s, which the %s choice sets."):format(TA.Label(unit), P.owned[unit]) break end
        if not AP.Eligible().by[unit] then out[#out + 1] = ("It names %s, which a preset can't manage on this TwichUI."):format(tostring(unit)) break end
    end
    return out
end

-- { { id, label, hint, keep, default, selected, n, summary (TA.Summarize), overlap (settings the layout also sets), issues,
--   changed (differs from the starting package), new } }
function AP.Options()
    local P = AP.State()
    local out = {}
    if not P or P.none then return out end
    for _, o in ipairs(P.options) do
        local units = UnitsOf(o.ops)
        local overlap = 0
        for unit in pairs(units) do if P.layer[unit] then overlap = overlap + 1 end end
        local changed = o.orig == nil or o.orig.label ~= o.label or o.orig.hint ~= o.hint or Count(o.orig.ops) ~= Count(o.ops)
        if not changed then for unit, op in pairs(o.ops) do if not SameOp(op, o.orig.ops[unit]) then changed = true break end end end
        out[#out + 1] = { id = o.id, label = o.label, hint = o.hint, keep = AP.IsKeep(o), default = o.id == P.default,
            selected = o.id == P.selected, n = Count(o.ops), summary = TA.Summarize(units), overlap = overlap,
            issues = AP.Issues(o), changed = changed, new = o.origin ~= "package", option = o }
    end
    return out
end

function AP.Select(id)
    local P = AP.State()
    if not P or not Find(id) then return false end
    P.selected = id
    return true
end

-- The option ids a new one may not take: those offered, those retired, and those the starting package had.
local function Taken()
    local P = AP.State()
    local t = {}
    for _, o in ipairs(P.options) do t[o.id] = true end
    for _, rid in ipairs(P.retired) do t[rid] = true end
    for id in pairs(P.baseIds or {}) do t[id] = true end
    if P.pending and P.pending.isNew and P.pending.id then t[P.pending.id] = true end
    return t
end

-- A stable id for a new option, from its name ("Questing kit" -> "questing-kit"), never one in use or retired.
function AP.NewId(label)
    local base = tostring(label or ""):lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if not base:match("^[a-z]") then base = "preset" .. (base ~= "" and ("-" .. base) or "") end
    base = base:sub(1, 40):gsub("%-+$", "")
    local taken = Taken()
    local id, n = base, 1
    while taken[id] or not LY.IsId(id) do
        n = n + 1
        id = base .. "-" .. n
    end
    return id
end

local function LabelFree(label, except)
    local P = AP.State()
    for _, o in ipairs(P.options) do
        if o.id ~= except and o.label:lower() == tostring(label):lower() then return false end
    end
    if P.pending and P.pending.isNew and P.pending.id ~= except and P.pending.label:lower() == tostring(label):lower() then return false end
    return true
end

local function NewLabel(stem)
    stem = stem:sub(1, AP.LABEL_MAX - 3)
    if LabelFree(stem) then return stem end
    for n = 2, 99 do
        local l = stem .. " " .. n
        if LabelFree(l) then return l end
    end
    return stem
end

---------------------------------------------------------------------------
-- Editing the draft directly: names, descriptions, order, the default, duplicating, removing (each makes the draft "changed")
---------------------------------------------------------------------------
function AP.Rename(id, label)
    local o = Find(id)
    if not o then return false, "unknown" end
    if not LY.Plain(label, AP.LABEL_MAX) then return false, "bad-label" end
    if not LabelFree(label, id) then return false, "label-taken" end
    if o.label == label then return true end
    o.label = label
    Touch()
    return true
end

AP.ID_MAX = 40

-- Gives an option another id. An option this draft added takes it freely: no package has carried the old id. One the starting package
-- offered retires its old id, as Remove does, so no later option takes it and a player who picked it is told it is gone (the window
-- asks first). A new id is a plain id nothing else uses: not an offered, retired or starting id.
function AP.SetId(id, newId)
    local P = AP.State()
    local o = Find(id)
    if not o then return false, "unknown" end
    if AP.IsKeep(o) then return false, "keep" end
    if newId == id then return true end
    if not LY.IsId(newId, AP.ID_MAX) then return false, "bad-id" end
    if Taken()[newId] then return false, "id-taken" end
    if P.baseIds[id] then
        local seen = false
        for _, rid in ipairs(P.retired) do if rid == id then seen = true end end
        if not seen then P.retired[#P.retired + 1] = id end
    end
    o.id = newId
    if P.default == id then P.default = newId end
    if P.selected == id then P.selected = newId end
    if P.pending and P.pending.id == id then P.pending.id = newId end
    Touch()
    return true
end

function AP.Describe(id, hint)
    local o = Find(id)
    if not o then return false, "unknown" end
    if hint == "" then hint = nil end
    if hint ~= nil and not LY.Plain(hint, AP.HINT_MAX) then return false, "bad-hint" end
    if o.hint == hint then return true end
    o.hint = hint
    Touch()
    return true
end

function AP.SetChoiceHint(hint)
    local P = AP.State()
    if not P or P.none then return false, "closed" end
    if hint == "" then hint = nil end
    if hint ~= nil and not LY.Plain(hint, AP.CHOICE_HINT_MAX) then return false, "bad-hint" end
    if P.hint == hint then return true end
    Touch()
    P.hint = hint
    return true
end

function AP.Move(id, delta)
    local P = AP.State()
    local o, i = Find(id)
    if not o then return false, "unknown" end
    local j = i + delta
    if j < 1 or j > #P.options then return false, "edge" end
    P.options[i], P.options[j] = P.options[j], P.options[i]
    Touch()
    return true
end

function AP.SetDefault(id)
    local P = AP.State()
    if not Find(id) then return false, "unknown" end
    if P.default == id then return true end
    P.default = id
    Touch()
    return true
end

function AP.Duplicate(id)
    local P = AP.State()
    local o, i = Find(id)
    if not o then return false, "unknown" end
    if AP.IsKeep(o) then return false, "keep" end
    if #P.options >= LY.MAX_OPTIONS then return false, "full" end
    local label = NewLabel("Copy of " .. o.label)
    local copy = { id = AP.NewId(label), label = label, hint = o.hint, ops = CopyOps(o.ops), origin = "duplicate" }
    table.insert(P.options, i + 1, copy)
    P.selected = copy.id
    Touch()
    return true, copy.id
end

-- Removes an option (the window asks first). replacement: the new default, required when the default is removed. The id is
-- retired (an option the starting package offered), so no later option takes it: a player who picked it is told it is gone.
function AP.Remove(id, replacement)
    local P = AP.State()
    local o, i = Find(id)
    if not o then return false, "unknown" end
    if AP.IsKeep(o) then return false, "keep" end
    if #P.options <= 1 then return false, "last" end
    if P.default == id then
        if not replacement or replacement == id or not Find(replacement) then return false, "needs-default" end
    end
    if P.pending and P.pending.id == id then P.pending = nil end
    table.remove(P.options, i)
    if P.default == id then P.default = replacement end
    if P.baseIds[id] then
        local seen = false
        for _, rid in ipairs(P.retired) do if rid == id then seen = true end end
        if not seen then P.retired[#P.retired + 1] = id end
    end
    if P.selected == id then P.selected = P.default end
    Touch()
    return true
end

---------------------------------------------------------------------------
-- A pending edit: capture into a preset, create one, or review one's settings. Nothing reaches the draft before Save.
---------------------------------------------------------------------------
-- edit = { id, isNew, from (the draft option; nil for a new one), label, hint, ops, captured ({ [unit] = value } | nil), source,
--   view = "managed" | "changed" | "available" | "excluded", group (id | nil), query, touched }
local function Begin(edit)
    local P = AP.State()
    edit.view, edit.query = edit.view or "managed", ""
    P.pending = edit
    return true
end

-- Capture current settings into an existing preset: the settings it manages now (its scope, kept as it is) take the values the
-- source profile has; a reset stays a reset. Settings it doesn't manage are listed apart and never added by themselves.
function AP.BeginCapture(id)
    local P = AP.State()
    local o = Find(id)
    if not o then return false, "unknown" end
    if AP.IsKeep(o) then return false, "keep" end
    local captured, why = AP.ReadAll()
    if not captured then return false, why end
    local ops = {}
    for unit, op in pairs(o.ops) do
        if op.reset then ops[unit] = { reset = true }
        elseif captured[unit] ~= nil then ops[unit] = { v = LY.Copy(captured[unit]) }
        else ops[unit] = { v = LY.Copy(op.v) } end   -- a setting this TwichUI doesn't have: left as the preset had it
    end
    P.selected = id
    return Begin({ id = id, from = o, label = o.label, hint = o.hint, ops = ops, captured = captured, source = P.source, kind = "capture" })
end

-- Create a preset from current settings: a new option, starting from a stated scope (whether each feature is on or off: every
-- feature switch a preset may manage), with the source profile's values. Looks and behaviour settings are added by the author.
function AP.BeginCreate()
    local P = AP.State()
    if not P or P.none then return false, "closed" end
    if #P.options >= LY.MAX_OPTIONS then return false, "full" end
    local captured, why = AP.ReadAll()
    if not captured then return false, why end
    local ops = {}
    for _, e in ipairs(AP.Eligible().list) do
        if e.switch and not P.owned[e.unit] then ops[e.unit] = { v = LY.Copy(captured[e.unit]) } end
    end
    local label = NewLabel("New preset")
    local edit = { id = nil, isNew = true, label = label, ops = ops, captured = captured, source = P.source, kind = "create" }
    P.pending = edit   -- (Taken() reads it: the id is drawn after)
    edit.id = AP.NewId(label)
    return Begin(edit)
end

-- Review or adjust a preset's settings without capturing (a setting added takes the source profile's value when it is ticked).
function AP.BeginEdit(id)
    local o = Find(id)
    if not o then return false, "unknown" end
    if AP.IsKeep(o) then return false, "keep" end
    AP.State().selected = id
    return Begin({ id = id, from = o, label = o.label, hint = o.hint, ops = CopyOps(o.ops), kind = "edit" })
end

function AP.Pending() local P = AP.State() return P and P.pending end

-- What the pending edit changes against the option as the draft has it: { changed, added, removed, same, managed }.
function AP.Diff(edit)
    edit = edit or AP.Pending()
    local d = { changed = 0, added = 0, removed = 0, same = 0, managed = Count(edit and edit.ops) }
    if not edit then return d end
    local was = edit.from and edit.from.ops or {}
    for unit, op in pairs(edit.ops) do
        local w = was[unit]
        if w == nil then d.added = d.added + 1
        elseif SameOp(op, w) then d.same = d.same + 1
        else d.changed = d.changed + 1 end
    end
    for unit in pairs(was) do if edit.ops[unit] == nil then d.removed = d.removed + 1 end end
    return d
end

-- Whether there is work that isn't in the draft yet (a pending edit with any change, or a new preset not saved).
function AP.Unsaved()
    local e = AP.Pending()
    if not e then return false end
    if e.isNew or e.touched then return true end
    local d = AP.Diff(e)
    return d.changed + d.added + d.removed > 0
end

-- Whether closing would lose something: unsaved work, or a draft changed since it was last published.
function AP.Dirty()
    local P = AP.State()
    if not P or P.none then return false end
    return AP.Unsaved() or (P.changed and P.gen ~= P.publishedGen)
end

function AP.Discard()
    local P = AP.State()
    if P then P.pending = nil end
    return true
end

function AP.SetEditName(label)
    local e = AP.Pending()
    if not e then return false, "closed" end
    if not LY.Plain(label, AP.LABEL_MAX) then return false, "bad-label" end
    if not LabelFree(label, e.id) then return false, "label-taken" end
    e.label, e.touched = label, true
    if e.isNew then   -- a preset not yet in the draft: its id follows its name ("New preset" never stays the id)
        e.id = nil
        e.id = AP.NewId(label)
    end
    return true
end

-- Saves the pending edit into the draft. Returns true | false, code, text.
function AP.Save()
    local P = AP.State()
    local e = P and P.pending
    if not e then return false, "closed" end
    local n = Count(e.ops)
    if n == 0 then return false, "empty", "Choose at least one setting for this preset to manage, or discard the edit." end
    if n > AP.MAX_UNITS then return false, "too-many", ("A preset may manage at most %d settings."):format(AP.MAX_UNITS) end
    for unit, op in pairs(e.ops) do
        local en = AP.Eligible().by[unit]
        if not en then return false, "unknown-unit", "It names a setting this TwichUI doesn't let a preset manage." end
        if P.owned[unit] then return false, "owned", ("%s is set by the %s choice."):format(en.label, P.owned[unit]) end
        if not op.reset and not TC().ValueOk(en.f, op.v) then return false, "bad-value", ("%s has a value it can't have."):format(en.label) end
    end
    if e.isNew then
        if #P.options >= LY.MAX_OPTIONS then return false, "full", ("A choice may offer at most %d options."):format(LY.MAX_OPTIONS) end
        P.options[#P.options + 1] = { id = e.id, label = e.label, hint = e.hint, ops = e.ops, origin = "new" }
    else
        local o = Find(e.id)
        if not o then return false, "unknown" end
        o.ops = e.ops
        if e.label ~= o.label then o.label = e.label end
    end
    P.selected = e.id
    P.pending = nil
    Touch()
    return true
end

---------------------------------------------------------------------------
-- The pending edit's list: views, a category, a search; including, leaving out and adjusting settings
---------------------------------------------------------------------------
AP.VIEWS = { { id = "managed", label = "Managed" }, { id = "changed", label = "Changed" }, { id = "available", label = "Not managed" },
    { id = "excluded", label = "Never in a preset" } }

function AP.SetView(view)
    local e = AP.Pending()
    if not e then return false end
    for _, v in ipairs(AP.VIEWS) do if v.id == view then e.view = view return true end end
    return false
end

function AP.SetGroup(group)
    local e = AP.Pending()
    if not e then return false end
    if group ~= nil then
        local ok = false
        for _, g in ipairs(AP.Eligible().groups) do if g.id == group then ok = true end end
        if not ok then return false end
    end
    e.group = group
    return true
end

function AP.SetQuery(q)
    local e = AP.Pending()
    if not e then return false end
    e.query = tostring(q or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40)
    return true
end

local function Show(e, op)
    if op == nil then return "(not managed)" end
    if op.reset then return "TwichUI's default (reset)" end
    return TA.Show(op.v)
end

-- The rows the view, category and search select, in the schema's order:
-- { { unit, label, groupLabel, kind, switch, op, was, status = "added" | "removed" | "changed" | "same" | "available", value text,
--   was text, captured (the source's value, when captured), default, customised (the source differs from TwichUI's default),
--   layer ("base"/"variant": the layout also sets it), owned (another choice sets it: can't be included) } }
function AP.Rows()
    local e = AP.Pending()
    if not e or e.view == "excluded" then return {} end
    local P = AP.State()
    local was = e.from and e.from.ops or {}
    local out = {}
    for _, en in ipairs(AP.Eligible().list) do
        local op, w = e.ops[en.unit], was[en.unit]
        local status
        if op and w then status = SameOp(op, w) and "same" or "changed"
        elseif op then status = e.isNew and "same" or "added"
        elseif w then status = "removed"
        else status = "available" end
        local keep = (e.view == "managed" and op ~= nil) or (e.view == "available" and op == nil)
            or (e.view == "changed" and (status == "added" or status == "removed" or status == "changed"))
        if keep and e.group and en.group ~= e.group then keep = false end
        if keep and e.query ~= "" and not en.lower:find(e.query, 1, true) then keep = false end
        if keep then
            local cap = e.captured and e.captured[en.unit]
            out[#out + 1] = { unit = en.unit, label = en.label, groupLabel = en.groupLabel, kind = en.f.kind, switch = en.switch,
                op = op, was = w, status = status, text = Show(en, op), wasText = Show(en, w), captured = cap,
                default = en.f.default, customised = cap ~= nil and not LY.Same(cap, en.f.default) or nil,
                layer = P.layer[en.unit], owned = P.owned[en.unit], field = en.f }
        end
    end
    -- in "Not managed", the settings the source profile has changed from TwichUI's default come first: those are the ones an
    -- author usually means to add
    if e.view == "available" then
        table.sort(out, function(a, b)
            if (a.customised and 1 or 0) ~= (b.customised and 1 or 0) then return a.customised == true end
            return AP.Eligible().by[a.unit].order < AP.Eligible().by[b.unit].order
        end)
    end
    return out
end

-- Includes or leaves out one setting. An included setting takes the captured value, else the source profile's. true | false, code.
function AP.SetIncluded(unit, on)
    local e = AP.Pending()
    local P = AP.State()
    if not e then return false, "closed" end
    local en = AP.Eligible().by[unit]
    if not en then return false, "unknown" end
    if on then
        if e.ops[unit] then return true end
        if P.owned[unit] then return false, "owned" end
        if Count(e.ops) >= AP.MAX_UNITS then return false, "limit" end
        local v = e.captured and e.captured[unit]
        if v == nil then v = AP.ReadOne(unit) end
        if v == nil then v = LY.Copy(en.f.default) end
        e.ops[unit] = { v = LY.Copy(v) }
    else
        e.ops[unit] = nil
    end
    e.touched = true
    return true
end

-- Includes or leaves out every row the list shows now (the view, category and search): the category and "all shown" controls.
-- All or nothing: past the bound nothing is included. Returns true, n | false, code.
function AP.IncludeShown(on)
    local e = AP.Pending()
    local P = AP.State()
    if not e then return false, "closed" end
    local rows = AP.Rows()
    local add = 0
    for _, r in ipairs(rows) do if on and not r.op and not r.owned then add = add + 1 end end
    if on and Count(e.ops) + add > AP.MAX_UNITS then return false, "limit" end
    local n = 0
    for _, r in ipairs(rows) do
        if on and not r.op and not P.owned[r.unit] then AP.SetIncluded(r.unit, true) n = n + 1
        elseif not on and r.op then e.ops[r.unit] = nil n = n + 1 end
    end
    e.touched = true
    return true, n
end

-- A managed setting's value (checked with the setting's own rule). true | false, code.
function AP.SetValue(unit, v)
    local e = AP.Pending()
    if not e then return false, "closed" end
    local en = AP.Eligible().by[unit]
    if not (en and e.ops[unit]) then return false, "not-managed" end
    if not TC().ValueOk(en.f, v) then return false, "bad-value" end
    e.ops[unit] = { v = LY.Copy(v) }
    e.touched = true
    return true
end

-- A managed setting reset to TwichUI's default (on) or given a value again (off: the captured or the source profile's value).
function AP.SetReset(unit, on)
    local e = AP.Pending()
    if not e then return false, "closed" end
    local en = AP.Eligible().by[unit]
    if not (en and e.ops[unit]) then return false, "not-managed" end
    if on then e.ops[unit] = { reset = true }
    else
        local v = e.captured and e.captured[unit]
        if v == nil then v = AP.ReadOne(unit) end
        if v == nil then v = LY.Copy(en.f.default) end
        e.ops[unit] = { v = LY.Copy(v) }
    end
    e.touched = true
    return true
end

-- The next value of a switch or a word setting (the row's button): on/off, or the next of the setting's words.
function AP.NextValue(unit)
    local e = AP.Pending()
    local en = AP.Eligible().by[unit]
    local op = e and e.ops[unit]
    if not (en and op) then return nil end
    local f = en.f
    local cur = op.reset and f.default or op.v
    if f.kind == "bool" then return not cur end
    if f.kind == "enum" then
        local words = LY.SortedKeys(f.values)
        for i, w in ipairs(words) do if w == cur then return words[i % #words + 1] end end
        return words[1]
    end
    return nil
end

---------------------------------------------------------------------------
-- Into the package (Author.Draft): the selector as the draft has it
---------------------------------------------------------------------------
local function OptionTable(o)
    local t = { id = o.id, label = o.label, hint = o.hint }
    if AP.IsKeep(o) then t.keep = true return t end
    local groups, reset = {}, {}
    for unit, op in pairs(o.ops) do
        if op.reset then reset[#reset + 1] = unit
        else
            local f = TA.FieldOf(unit)
            if f then
                groups[f.group] = groups[f.group] or {}
                groups[f.group][f.slot] = groups[f.group][f.slot] or {}
                groups[f.group][f.slot][f.key] = LY.Copy(op.v)
            end
        end
    end
    table.sort(reset)
    t.twichui = { groups = next(groups) and groups or nil, reset = #reset > 0 and reset or nil }
    if t.twichui.groups == nil and t.twichui.reset == nil then t.twichui = nil end
    return t
end
AP.OptionTable = OptionTable

-- Writes the selector into pkg (a copy Author.Draft made) when the draft changed it. The package then needs format 6.
function AP.Apply(pkg)
    local P = AP.State()
    if not P or P.none or not P.changed then return pkg end
    local raw = pkg.choices and pkg.choices[P.index]
    if not raw or raw.id ~= P.id then return pkg end
    local ch = { id = P.id, kind = "preset", mode = "settings", label = raw.label, hint = P.hint, default = P.default, options = {} }
    for _, o in ipairs(P.options) do ch.options[#ch.options + 1] = OptionTable(o) end
    if #P.retired > 0 then
        ch.retired = {}
        for i, rid in ipairs(P.retired) do ch.retired[i] = rid end
    end
    pkg.choices[P.index] = ch
    if (pkg.format or 0) < 6 then pkg.format = 6 end
    return pkg
end

-- Problems that stop a check, in words, and one note: { blockers = { text }, notes = { text } }.
function AP.CheckLines()
    local P = AP.State()
    local out = { blockers = {}, notes = {} }
    if not P or P.none then return out end
    if AP.Unsaved() then
        local e = AP.Pending()
        out.notes[#out.notes + 1] = ("Your edit of \"%s\" isn't saved to the draft: Check and Publish don't include it."):format(e.label)
    end
    local def = Find(P.default)
    if not def then out.blockers[#out.blockers + 1] = "The TwichUI presets have no default option." end
    for _, o in ipairs(P.options) do
        for _, t in ipairs(AP.Issues(o)) do out.blockers[#out.blockers + 1] = ("TwichUI preset \"%s\": %s"):format(o.label, t) end
    end
    if P.converted then
        out.notes[#out.notes + 1] = "The TwichUI presets are now editable presets (package format 6): TwichUI versions before this one can't read the package."
    end
    return out
end

-- Settings held by the presets' draft and the pending edit (the gauge reads it).
function AP.Held()
    local P = AP.State()
    if not P or P.none then return 0 end
    local n = 0
    for _, o in ipairs(P.options) do n = n + Count(o.ops) end
    if P.pending then n = n + Count(P.pending.ops) + Count(P.pending.captured) end
    return n
end

R.Perf.Gauge("layoutwizard.author.presets", { label = "Layout authoring: TwichUI preset settings held (draft and edit; 0 while closed)", unit = "count",
    kind = "state", group = "layouts", read = function() return AP.Held() end })
