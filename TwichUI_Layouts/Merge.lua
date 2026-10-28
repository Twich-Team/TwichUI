-- TwichUI Layouts: updating an installed layout while keeping the recipient's own changes (docs/layouts/updates.md;
-- architecture.md §7). Pure: the adapters read the values, this decides what happens to each one. No saved variables,
-- no game calls.
--
-- Three sides are compared for every managed unit, each as the adapter's normalized text: for a comparable unit the value
-- itself (LY.Value: its whole canonical text, or a position as "@x,y[,w,h],POINT"), for an opaque one a fingerprint, or
-- MG.ABSENT:
--   the baseline  entry.p: what the layout recommended at the last install; entry.a: what that install left, where it
--                 differs (the recipient's value it kept); entry.k: that value is a retained override; entry.l: what was
--                 read back after the check, where it differs from a / p; entry.s: how it was stored; entry.u: checked only
--                 for being there (an opaque unit), not by value
--   current       what the recipient has now
--   new           what the package says now, for this screen, layout and these choices
-- A unit whose two sides live in the same space (a setting, a position, a text size) is `comparable`: current and new
-- can be compared directly. An opaque unit (an EllesmereUI module blob, its layout links, its look) is compared only
-- against its own baseline: the package's blob and the one EllesmereUI keeps after loading it are not the same text, so
-- "both changed to the same value" can't be told for it and counts as a conflict.
--
-- Cases (MG.Classify):
--   same       neither side changed since the baseline                 -> nothing
--   package    only the package changed                                -> apply the package's value
--   mine       only the recipient changed                              -> keep theirs
--   both-same  both changed, to the same value (comparable units only) -> nothing
--   conflict   both changed, differently                               -> keep theirs unless they choose otherwise
--   added      the package manages it now and didn't at the baseline   -> apply (listed as newly managed)
--   unknown    there is no usable baseline (none, or another version)  -> nothing when equal, else keep theirs
--   removed    the package no longer names it                          -> stop managing (what that leaves is the adapter's rule)
--   owned      the recipient said "stop managing this"                 -> never written, never compared
-- Decisions: none, apply, keep, owned, release.

local R = TwichUI
local LY = R.Layouts
local MG = {}
LY.Merge = MG

MG.VERSION = 1            -- the merge contract; a baseline part made under another is not compared (unknown)
MG.ABSENT = "-"           -- the normalized text of "not there" (no fingerprint, position or signature is this)
MG.POLICIES = LY.Set({ "keep", "recommended" })
MG.CHOICES = LY.Set({ "mine", "package", "own", "manage" })
MG.MAX_CHOICES = LY.MAX_EXPECT or 320   -- per-unit choices one plan may carry

-- Two positions are the same within a unit (EllesmereUI snaps to its pixel grid; places are kept to 1/100 of a unit and
-- shown in whole units). Anything else is the same only as the same text.
local function Nums(s)
    local out = {}
    for n in s:sub(2):gmatch("[^,]+") do
        local v = tonumber(n)
        if not v then return nil end
        out[#out + 1] = v
    end
    return out
end

function MG.Near(a, b)
    if a == b then return true end
    if type(a) ~= "string" or type(b) ~= "string" or a:sub(1, 1) ~= "@" or b:sub(1, 1) ~= "@" then return false end
    -- a point name rides at the end of a TwichUI place ("@x,y,LEFT"): it has to be the same
    local pa, pb = a:match(",([%u_]+)$"), b:match(",([%u_]+)$")
    if pa ~= pb then return false end
    local na, nb = Nums(pa and a:gsub(",[%u_]+$", "") or a), Nums(pb and b:gsub(",[%u_]+$", "") or b)
    if not na or not nb or #na ~= #nb then return false end
    for i = 1, #na do if math.abs(na[i] - nb[i]) > 1 then return false end end
    return true
end

-- e = { unit, n, c, cs = "x" (stored) | "d" (not stored: the addon's default) | "a" (not there), b = baseline entry | nil,
--   comparable, known = the adapter has a usable baseline for this install }
-- Returns the case, or nil for a unit nobody manages (not in the package and not in the baseline).
-- Whether the recipient changed a unit since the baseline entry b (what the last install left).
function MG.Changed(e, b)
    if e.cs == "d" and b.s == "d" then
        return false   -- never stored on either side: the addon's own default moved, the recipient did nothing
    elseif b.k then
        -- a value of the recipient's that an earlier update kept stays theirs (an override), not the layout's new default:
        -- comparable, while it differs from what the layout recommended then; opaque, until they choose otherwise
        return not e.comparable or not MG.Near(e.c, b.p)
    end
    return not MG.Near(e.c, b.l or b.a or b.p)
end

function MG.Classify(e)
    local b = e.b
    if b and b.o then return "owned" end
    if e.n == nil then return b and "removed" or nil end
    local equalNow = e.comparable and MG.Near(e.c, e.n)
    if not b or b.p == nil then
        if equalNow then return "same" end
        return e.known and "added" or "unknown"
    end
    local pkg = not MG.Near(e.n, b.p)
    local mine = MG.Changed(e, b)
    if not pkg and not mine then return "same" end
    if pkg and not mine then return "package" end
    if mine and not pkg then return "mine" end
    if equalNow then return "both-same" end
    return "conflict"
end

local DEFAULT = {
    keep = { same = "none", package = "apply", mine = "keep", ["both-same"] = "none", conflict = "keep", added = "apply",
        unknown = "keep", removed = "release", owned = "owned" },
    recommended = { same = "none", package = "apply", mine = "apply", ["both-same"] = "none", conflict = "apply", added = "apply",
        unknown = "apply", removed = "release", owned = "owned" },
}

-- Which choices a row offers (the review's buttons), by case. "own" is never offered inside an atomic group: those
-- units are kept or replaced together, so one of them can't be handed to the recipient alone.
local OFFER = {
    package = { "package", "mine", "own" }, mine = { "mine", "package", "own" }, conflict = { "mine", "package", "own" },
    added = { "package", "mine", "own" }, unknown = { "mine", "package", "own" }, owned = { "manage" },
    same = { "own" }, ["both-same"] = { "own" },
}

-- The decision for one unit: the policy's default for its case, then the recipient's choice when it is one this case
-- offers. Returns decision, how ("default" | "chosen" | "switch" | "absent"). A unit whose current value can't be kept
-- (e.keepAbsent == false and it is not there) is applied: its entity is missing and the package's is put back.
-- switching: the install is moving to another layout of the package. A conflict in a unit the layout sets for itself
-- (e.variantOwned: its value comes from the layout's own layer) returns to the new layout's value; one the layouts share
-- keeps the recipient's (updates.md, "Switching layouts").
function MG.Decide(e, case, policy, choice, switching)
    local d = (DEFAULT[policy] or DEFAULT.keep)[case]
    local how = "default"
    if switching and case == "conflict" and e.variantOwned and d == "keep" then d, how = "apply", "switch" end
    if choice and MG.CHOICES[choice] then
        local ok = false
        for _, c in ipairs(OFFER[case] or {}) do if c == choice and not (c == "own" and e.group) then ok = true end end
        if ok then
            how = "chosen"
            if choice == "mine" then d = "keep"
            elseif choice == "package" or choice == "manage" then d = "apply"
            elseif choice == "own" then d = "owned" end
        end
    end
    if (case == "unknown" or case == "same" or case == "both-same") and d ~= "owned" and e.comparable and MG.Near(e.c, e.n) then d = "none" end
    if d == "apply" and e.comparable and MG.Near(e.c, e.n) then d = "none" end
    if (d == "keep" or d == "owned") and e.c == MG.ABSENT and e.keepAbsent == false then d, how = "apply", "absent" end
    return d, how
end

function MG.Offers(case, inGroup)
    local out = {}
    for _, c in ipairs(OFFER[case] or {}) do if not (c == "own" and inGroup) then out[#out + 1] = c end end
    return out
end

-- Runs the whole comparison for one adapter.
-- entries: { e, ... } (as for Classify, plus label, group, keepAbsent, canKeep = false for an opaque unit whose current
--   value can't be carried into the new install)
-- opts = { policy, choose = { [unit] = choice }, groups = { [group] = "mine" | "package" }, whole = "keep" | "replace",
--   switching = moving to another layout (a group then defaults to the new layout's) }
-- Returns { rows = { row }, by = { [unit] = row }, counts, groups = { [id] = { conflict, choice, members } },
--   whole = { needed, choice, units } | nil }
-- row = { unit, label, case, decision, how, group, comparable, offers }
function MG.Run(entries, opts)
    opts = opts or {}
    local policy = MG.POLICIES[opts.policy] and opts.policy or "keep"
    local out = { rows = {}, by = {}, groups = {}, counts = { apply = 0, keep = 0, conflict = 0, owned = 0, release = 0, none = 0,
        added = 0, unknown = 0, mine = 0, package = 0 }, policy = policy }
    table.sort(entries, function(a, b) return a.unit < b.unit end)
    for _, e in ipairs(entries) do
        local case = MG.Classify(e)
        if case then
            local d, how = MG.Decide(e, case, policy, opts.choose and opts.choose[e.unit], opts.switching)
            local row = { unit = e.unit, label = e.label, case = case, decision = d, how = how, group = e.group,
                comparable = e.comparable == true, offers = MG.Offers(case, e.group ~= nil), e = e }
            -- a unit the package stopped naming: whether the value there now is the recipient's own (what releasing keeps)
            if case == "removed" and e.b and e.b.p ~= nil then row.mine = MG.Changed(e, e.b) end
            out.rows[#out.rows + 1] = row
            out.by[e.unit] = row
            if e.group then
                local g = out.groups[e.group] or { members = {} }
                out.groups[e.group] = g
                g.members[#g.members + 1] = row
            end
        end
    end
    -- Atomic groups: kept or replaced together. When one member keeps the recipient's value and another would take the
    -- package's, the whole group goes one way: the recipient's (the default) or the package's, as they choose.
    -- A member the recipient made theirs ("Stop managing", before it was in the group) can't be handed back by the group: the
    -- group is theirs while it holds one, whatever the policy or the group's choice ("Manage again" on that member first).
    for _, gid in ipairs(LY.SortedKeys(out.groups)) do
        local g = out.groups[gid]
        local keep, apply, owned = false, false, false
        for _, row in ipairs(g.members) do
            if row.decision == "keep" or row.decision == "owned" then keep = true end
            if row.decision == "owned" then owned = true end
            if row.decision == "apply" then apply = true end
        end
        if keep and apply then
            g.conflict = true
            local choice = opts.groups and opts.groups[gid]
            if choice ~= "mine" and choice ~= "package" then choice = (policy == "recommended" or opts.switching) and "package" or "mine" end
            if owned then choice, g.owned = "mine", true end
            g.choice = choice
            for _, row in ipairs(g.members) do
                if choice == "mine" and row.decision == "apply" then row.decision, row.how = "keep", "group"
                elseif choice == "package" and row.decision == "keep" then row.decision, row.how = "apply", "group" end
            end
        end
    end
    -- An opaque unit that would keep the recipient's value but can't be carried into the new install: the adapter as a
    -- whole is kept as it is or replaced with the package's (its old state is kept as a backup either way).
    local stuck = {}
    for _, row in ipairs(out.rows) do
        local carried = row.decision == "keep" or row.decision == "owned"
            or (row.decision == "release" and row.e.c ~= MG.ABSENT and (row.mine or not opts.switching))
        if carried and row.e.canKeep == false then stuck[#stuck + 1] = row.unit end
    end
    if #stuck > 0 then
        local choice = opts.whole
        if choice ~= "keep" and choice ~= "replace" then choice = "keep" end
        out.whole = { needed = true, choice = choice, units = stuck }
        if choice == "replace" then
            for _, row in ipairs(out.rows) do
                if row.decision == "keep" and row.e.canKeep == false then row.decision, row.how = "apply", "whole" end
            end
        end
    end
    for _, row in ipairs(out.rows) do
        out.counts[row.decision] = (out.counts[row.decision] or 0) + 1
        if row.case == "conflict" then out.counts.conflict = out.counts.conflict + 1 end
        if row.case == "added" then out.counts.added = out.counts.added + 1 end
        if row.case == "unknown" then out.counts.unknown = out.counts.unknown + 1 end
        if row.case == "mine" then out.counts.mine = out.counts.mine + 1 end
        if row.case == "package" then out.counts.package = out.counts.package + 1 end
    end
    return out
end

-- What to remember for each unit once this install has been checked: the package's side now, and whether the recipient's
-- value was kept or the unit is theirs. Owned units keep their mark and nothing else.
function MG.Track(result, n)
    local t = {}
    for _, row in ipairs(result.rows) do
        if row.decision == "owned" then t[row.unit] = { o = true }
        elseif row.decision ~= "release" then
            local kept = row.decision == "keep"
            -- p: what the layout recommended; a: what this install leaves (the recipient's value, when it was kept)
            t[row.unit] = { p = n[row.unit], k = kept or nil, a = kept and row.e.c ~= n[row.unit] and row.e.c or nil }
        end
    end
    return t
end

-- Plain words for a decision: the effect of applying, and what it means for later updates.
MG.EFFECT = {
    none = "Already as recommended.",
    apply = "Changes to the layout's recommended value.",
    keep = "Stays as you have it.",
    owned = "Stays as you have it.",
    release = "Left as it is.",
}
MG.OWNER = {
    none = "The layout keeps managing it.",
    apply = "The layout manages it: a later update may change it.",
    keep = "Still the layout's: if a later update changes it again, you are asked again.",
    owned = "Yours from now on: updates never change it. You can hand it back here.",
    release = "The layout no longer manages it.",
}
MG.CASE_TEXT = {
    same = "Unchanged", package = "Updated by the layout", mine = "Changed by you", ["both-same"] = "Changed by both, the same way",
    conflict = "Changed by you and by the layout", added = "Newly managed by the layout", unknown = "Can't tell who changed it",
    removed = "No longer in the layout", owned = "Yours (not managed)",
}

---------------------------------------------------------------------------
-- The screen check for kept places: after the recipient's own placements are carried into the new install, each is
-- looked at on this screen. A warning never changes a value: the recipient's placement stays as they made it.
-- items: { { unit, label, x, y (its anchor point, from the screen's centre), comp (the component it belongs to) } }
-- Returns { { unit, label, code = "offscreen" | "overlap", other } }
---------------------------------------------------------------------------
function MG.CheckPlaces(geo, items)
    local out = {}
    if not geo then return out end
    local W, H = geo.screen.w / 2, geo.screen.h / 2
    local tol = LY.Geometry.TOLERANCE
    for _, it in ipairs(items) do
        if math.abs(it.x) > W + tol or math.abs(it.y) > H + tol then
            out[#out + 1] = { unit = it.unit, label = it.label, code = "offscreen" }
        else
            for _, id in ipairs(geo.order or LY.SortedKeys(geo.components)) do
                local c = geo.components[id]
                local r = c and c.rect
                if c and c.managed and id ~= it.comp and r and r.w > 0 and r.h > 0
                    and it.x > r.l + tol and it.x < r.r - tol and it.y > r.b + tol and it.y < r.t - tol then
                    out[#out + 1] = { unit = it.unit, label = it.label, code = "overlap", other = c.label or id }
                    break
                end
            end
        end
    end
    return out
end
