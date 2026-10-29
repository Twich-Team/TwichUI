-- TwichUI Layout Setup: the review table's model (docs/layouts/publishing.md, "Review the changes")
-- No frames here: AuthorReviewWindow.lua draws what this says and calls what it offers, so every rule can be tested without a screen.
-- It reads the authoring session's changes (Author.lua: A.Items) and adds what a table needs and the model did not hold:
--
--   Name(it), Tech(it)      the friendly name (Chat, Bags, Unit frames ...) and the canonical id, kept for the tooltip and the details
--   Impact(it, to)          what the change does to EACH layout, worked out with the layout engine's own composer (LY.Compose) over that
--                           unit's layers before and after the change, as the draft (A.Draft) would write it. Cached per destination
--   Flags(it)               why a change deserves a look: blocked | review | info | none, each reason with a code, a sentence and its
--                           evidence. Deterministic and explainable; a count of changed values is shown, never scored as risk
--   Leaves(it)              the leaf-level differences of one change (setting, before, after), built when the details open; bounded
--   Reviewed state          SetReviewed(id, on): the author's acknowledgment of the change AS PROPOSED (its values, destination and
--                           effect); any of them changing makes it need a look again. It is not approval and never bypasses a check
--   View                    search, status, change type, layout and sort, frozen into one order until the author changes one of them
--                           (a checkbox does not reorder the table), paged; Counts() for the summary; bulk actions over exactly that order
--
-- Nothing here writes a profile or the draft except through Author.lua (SetInclude, SetTarget): the review state is the session's.

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local A = WZ.Author
local Pub = LY.Pub
local Capture = LY.Capture
local RV = {}
WZ.AuthorReview = RV

local function Sess() return A.Session() end
local function Plural(n, one, many) return n == 1 and one or many end

RV.PAGE_SIZES = { 10, 15, 20 }
RV.MAX_LEAVES = 400      -- leaf rows built for one change's details
RV.MAX_VALUE = 80        -- characters of a value shown in a cell
RV.FULL_VALUE = 600      -- characters of a value kept for its tooltip
RV.STRUCTURE_MIN = 10    -- settings added or removed inside a module before the shape of it is called out

RV.STATUSES = {
    { key = "all", label = "All" }, { key = "included", label = "Included" }, { key = "excluded", label = "Excluded" },
    { key = "review", label = "Needs review" }, { key = "blocked", label = "Blocked" }, { key = "reviewed", label = "Reviewed" },
}
RV.KINDS = {
    { key = "all", label = "All types" }, { key = "added", label = "Added" }, { key = "changed", label = "Changed" },
    { key = "removed", label = "Removed" }, { key = "default", label = "Reset" },
}
RV.SORTS = {
    { key = "attention", label = "Attention" }, { key = "name", label = "Name" }, { key = "kind", label = "Change" },
    { key = "details", label = "Details" }, { key = "destination", label = "Destination" },
}
local KIND_LABEL = { added = "Added", changed = "Changed", removed = "Removed", default = "Reset" }
local KIND_ORDER = { changed = 1, added = 2, removed = 3, default = 4 }
RV.KIND_LABEL = KIND_LABEL

local function Index(list, key)
    for i, e in ipairs(list) do if e.key == key then return i end end
    return 1
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------
-- EllesmereUI's module ids read well once split into words ("EllesmereUIActionBars" is "Action bars"); these two do not.
local MODULE_NAMES = { EllesmereUIAuraBuffReminders = "Aura and buff reminders", EllesmereUIQoL = "Quality of life" }

local function Humanize(k)
    k = tostring(k)
    if k:match("^%d+$") then return "#" .. k end
    local s = k:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):lower()
    return s:sub(1, 1):upper() .. s:sub(2)
end
RV.Humanize = Humanize

local function ModuleOf(it) return it.id:match("^ellesmereui:addons%.([%w_]+)$") end

-- The friendly name: a module by what it is called in EllesmereUI's options, anything else by the adapter's own label.
function RV.Name(it)
    local m = ModuleOf(it)
    if m then return MODULE_NAMES[m] or Humanize((m:gsub("^EllesmereUI", ""))) end
    return it.label
end
function RV.Tech(it) return it.id end

-- A layout's short name for a chip ("Classic"): the first word of its title, unless two layouts share it.
function RV.Short(id)
    local s = Sess()
    local full = Pub.TitleCase(id)
    local first = full:match("^(%S+)") or full
    for _, v in ipairs(s and s.variants or {}) do
        if v ~= id and (Pub.TitleCase(v):match("^(%S+)") or "") == first then return full end
    end
    return first
end

function RV.IsBlob(it) return ModuleOf(it) ~= nil and type(it.new ~= nil and it.new or it.old) == "table" end

function RV.Storage(it)
    if it.lives == "base" then return "Shared base" end
    if it.lives == "variant" then return "This layout" end
    return "Not in the package"
end
function RV.Destination(it, to) return (to or it.to) == "base" and "Shared base" or "This layout" end

function RV.Details(it)
    local t = it.n
    if not t then return "" end
    local n = t.total
    if t.capped then return ("%d+ fields"):format(n) end
    return ("%d %s"):format(n, Plural(n, "field", "fields"))
end

---------------------------------------------------------------------------
-- Impact: the effective result for each layout, through the real composer
---------------------------------------------------------------------------
-- The layers that decide this unit for one layout, before the change (after = false) or as the draft would write it. This mirrors
-- A.Draft: a change shared to the base is written in the base and removed from the edited layout's own layer (other layouts keep
-- theirs); a change kept in this layout is written only there; a removal forgets the unit; a reset puts DEFAULT where it names it.
local function Layers(s, variant, it, to, after)
    local view = s.view
    local base, mine = {}, {}
    local parent = view.parents[it.id]
    local function Take(map, layer)
        local e = layer and layer[it.id]
        if e then map[it.id] = e.value end
        local p = parent and layer and layer[parent]
        if p then map[parent] = p.value end
    end
    Take(base, view.base)
    Take(mine, view.variants[variant])
    if after then
        local edited = variant == s.variant
        if it.kind == "removed" or (it.kind == "default" and it.how == "release") then
            if to == "base" then base[it.id] = nil end
            if edited then mine[it.id] = nil end
        elseif it.kind == "default" then
            if to == "base" then
                base[it.id] = LY.DEFAULT
                if edited then mine[it.id] = nil end
            elseif edited then mine[it.id] = LY.DEFAULT end
        elseif to == "base" then
            base[it.id] = it.new
            if edited then mine[it.id] = nil end
        elseif edited then
            mine[it.id] = it.new
        end
    end
    return { { name = "base", units = base }, { name = "variant", units = mine } }, parent and { [it.id] = parent } or nil
end

local function Composed(s, variant, it, to, after)
    local layers, parents = Layers(s, variant, it, to, after)
    local ok, out = pcall(LY.Compose, layers, parents)
    if not ok or type(out) ~= "table" then return nil, false end
    return out.units[it.id], true, out.layer[it.id], out
end

-- { key, byVariant = { { variant, title, short, changes, before, after, from ("base" | "variant" | nil), note } }, changing = { ids },
--   text = "Both" | "Classic" | "None" | "Unknown", unknown, none }. Cached on the change by destination; read only.
function RV.Impact(it, to)
    local s = Sess()
    to = to or it.to
    it.rv = it.rv or {}
    local cache = it.rv.impact
    if not cache then cache = {} it.rv.impact = cache end
    local key = to .. "|" .. tostring(it.how)
    if cache[key] then return cache[key] end
    local out = { byVariant = {}, changing = {}, unknown = false }
    for _, id in ipairs(s.variants) do
        local before, ok1, layerB = Composed(s, id, it, to, false)
        local after, ok2, layerA, composed = Composed(s, id, it, to, true)
        local e = { variant = id, title = Pub.TitleCase(id), short = RV.Short(id), before = before, after = after, from = layerA }
        if not (ok1 and ok2) then
            out.unknown = true
            e.changes, e.note = nil, "could not be worked out"
        else
            e.changes = not LY.Same(before, after)
            if before == nil and after == nil then e.changes = false end
            if e.changes then
                e.note = layerA == "base" and "changes: it uses the shared value" or "changes: this layout's own value"
                out.changing[#out.changing + 1] = id
            else
                local superseded = false
                for _, u in ipairs(composed and composed.superseded or {}) do if u == it.id then superseded = true end end
                if superseded then e.note = "unchanged: a higher layer replaces the whole module"
                elseif id ~= s.variant and layerB == "variant" and layerA == "variant" then e.note = "unchanged: its own value wins"
                elseif id ~= s.variant and to ~= "base" then e.note = "unchanged: the change is not shared"
                else e.note = "unchanged" end
            end
        end
        out.byVariant[#out.byVariant + 1] = e
    end
    local n, total = #out.changing, #s.variants
    if out.unknown then out.text = "Unknown"
    elseif n == 0 then out.text, out.none = "None", true
    elseif n == total then out.text = total == 2 and "Both" or "All"
    else
        local names = {}
        for _, id in ipairs(out.changing) do names[#names + 1] = RV.Short(id) end
        out.text = table.concat(names, ", ")
    end
    cache[key] = out
    return out
end

---------------------------------------------------------------------------
-- Values, as they are shown
---------------------------------------------------------------------------
local MEDIA_EXT = { ttf = true, otf = true, tga = true, blp = true, png = true, jpg = true, jpeg = true, ogg = true, mp3 = true, wav = true }

local function Clean(str, max)
    str = str:gsub("|", "||"):gsub("[%c]", "?")   -- a pipe starts a colour or texture code in the game's text: shown as itself
    if #str > max then str = str:sub(1, max - 3) .. "..." end
    return str
end

local function Hex(c)
    local function B(x) return math.max(0, math.min(255, math.floor((tonumber(x) or 0) * 255 + 0.5))) end
    return ("#%02X%02X%02X"):format(B(c.r), B(c.g), B(c.b))
end

-- text (a short reading), full (the whole reading, bounded, for a tooltip), color ({ r, g, b } when it is a colour), media (true for a file)
function RV.Format(v, adapter)
    if v == nil then return "(missing)", "(missing: the package does not set it)" end
    if v == LY.DEFAULT then return "(default)", "(back at the addon's default)" end
    if v == LY.REMOVE then return "(removed)", "(removed)" end
    local t = type(v)
    if t == "boolean" then return v and "On" or "Off" end
    if t == "number" then
        local s
        if v ~= v then s = "NaN" elseif v == math.huge then s = "inf" elseif v == -math.huge then s = "-inf" else s = ("%.6g"):format(v) end
        return s
    end
    if t == "string" then
        if v == "" then return "(empty text)" end
        local ext = v:match("%.(%a+)$")
        if (v:find("[\\/]") and ext and MEDIA_EXT[ext:lower()]) then
            local file = v:match("([^\\/]+)$") or v
            return Clean(file, RV.MAX_VALUE), Clean(v, RV.FULL_VALUE), nil, true
        end
        return Clean(v, RV.MAX_VALUE), Clean(v, RV.FULL_VALUE)
    end
    if t == "table" then
        if A.IsColor(v) then
            local s = Hex(v)
            if type(v.a) == "number" and v.a < 1 then s = s .. (" at %d%%"):format(math.floor(v.a * 100 + 0.5)) end
            return s, s, { r = v.r, g = v.g, b = v.b, a = v.a }
        end
        if type(v.x) == "number" and type(v.y) == "number" then
            local s = ("%d, %d"):format(math.floor(v.x + 0.5), math.floor(v.y + 0.5))
            if type(v.w) == "number" and type(v.h) == "number" then s = s .. (", %d x %d"):format(math.floor(v.w + 0.5), math.floor(v.h + 0.5)) end
            return s, s
        end
        if next(v) == nil then return "(empty list)" end
        local n = 0
        for _ in pairs(v) do n = n + 1 if n >= 1000 then break end end
        return ("(%d%s values)"):format(n, n >= 1000 and "+" or ""), nil
    end
    return "(" .. t .. ")"
end

---------------------------------------------------------------------------
-- Leaf differences (built when the details open)
---------------------------------------------------------------------------
local function Sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local na, nb = type(a) == "number", type(b) == "number"
        if na ~= nb then return na end
        if na then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function IsWalkable(v)
    return type(v) == "table" and v ~= LY.DEFAULT and v ~= LY.REMOVE and not A.IsColor(v) and next(v) ~= nil
        and not (type(v.x) == "number" and type(v.y) == "number")
end

local function PathText(path)
    local out = {}
    for _, k in ipairs(path) do out[#out + 1] = tostring(k) end
    return table.concat(out, ".")
end

local function LeafLabel(it, path)
    if #path == 0 then return RV.Name(it) end
    local out = {}
    for i = math.max(1, #path - 2), #path do out[#out + 1] = Humanize(path[i]) end
    return table.concat(out, " > ")
end

-- { { path, raw, label, before, beforeFull, beforeColor, after, afterFull, afterColor, kind }, ... } sorted by path, total (how many
-- differ), truncated (more differ than are listed). Bounded: RV.MAX_LEAVES rows, depth 14, A.MAX_LEAVES leaves visited. Not cached
-- on the change: the window keeps the one it shows (RV.Detail), so no second copy of every module's settings is held.
function RV.Leaves(it)
    local rows, total, visited = {}, 0, 0
    local truncated = false
    local function Add(path, a, b, kind)
        total = total + 1
        if #rows >= RV.MAX_LEAVES then truncated = true return end
        local bt, bf, bc, bm = RV.Format(a)
        local at, af, ac, am = RV.Format(b)
        rows[#rows + 1] = { raw = PathText(path), label = LeafLabel(it, path), kind = kind, media = bm or am,
            before = bt, beforeFull = bf or bt, beforeColor = bc, after = at, afterFull = af or at, afterColor = ac }
    end
    local function Whole(v, path, kind, depth)
        visited = visited + 1
        if visited > A.MAX_LEAVES then truncated = true return end
        if IsWalkable(v) and depth <= 14 then
            for _, k in ipairs(Sorted(v)) do
                path[#path + 1] = k
                Whole(v[k], path, kind, depth + 1)
                path[#path] = nil
            end
        elseif kind == "added" then Add(path, nil, v, "added")
        else Add(path, v, nil, "removed") end
    end
    local function Walk(a, b, path, depth)
        visited = visited + 1
        if visited > A.MAX_LEAVES then truncated = true return end
        if a == nil and b == nil then return end
        if a == nil then Whole(b, path, "added", depth) return end
        if b == nil then Whole(a, path, "removed", depth) return end
        if IsWalkable(a) and IsWalkable(b) and depth <= 14 then
            local keys = {}
            for k in pairs(a) do keys[k] = true end
            for k in pairs(b) do keys[k] = true end
            for _, k in ipairs(Sorted(keys)) do
                path[#path + 1] = k
                Walk(a[k], b[k], path, depth + 1)
                path[#path] = nil
            end
        elseif not LY.Same(a, b) then
            Add(path, a, b, "changed")
        end
    end
    local old, new = it.old, it.new
    if it.kind == "default" then new = LY.DEFAULT end
    Walk(old, new, {}, 0)
    table.sort(rows, function(x, y) if x.raw ~= y.raw then return x.raw < y.raw end return x.kind < y.kind end)
    return rows, total, truncated
end

---------------------------------------------------------------------------
-- What each change holds that a flag can name (worked out once per change)
---------------------------------------------------------------------------
-- { toggles = { { raw, from, to } }, refs = { { file, source } } }. An "enabled" switch is named only by that exact key (EllesmereUI's
-- module settings have no other metadata here), and the flag says so.
local function Scan(it)
    it.rv = it.rv or {}
    if it.rv.scan then return it.rv.scan end
    local scan = { toggles = {}, refs = {} }
    local visited = 0
    local function Walk(a, b, path, depth)
        visited = visited + 1
        if visited > A.MAX_LEAVES or depth > 14 then return end
        if type(a) == "table" and type(b) == "table" and IsWalkable(a) and IsWalkable(b) then
            for k, v in pairs(a) do
                path[#path + 1] = k
                Walk(v, b[k], path, depth + 1)
                path[#path] = nil
            end
        elseif path[#path] == "enabled" and type(a) == "boolean" and type(b) == "boolean" and a ~= b and #scan.toggles < 3 then
            scan.toggles[#scan.toggles + 1] = { raw = PathText(path), from = a, to = b }
        end
    end
    if type(it.old) == "table" and type(it.new) == "table" then Walk(it.old, it.new, {}, 0) end
    local value = it.new
    if value ~= nil and value ~= LY.DEFAULT and (type(value) == "table" or type(value) == "string") then
        local ok, refs = pcall(Pub.Refs, value)
        if ok then
            for _, r in ipairs(refs) do
                if #scan.refs < 8 then scan.refs[#scan.refs + 1] = { path = r.path, file = r.path:match("([^\\/]+)$") or r.path, source = r.source, kind = r.kind } end
            end
        end
    end
    it.rv.scan = scan
    return scan
end

---------------------------------------------------------------------------
-- Attention
---------------------------------------------------------------------------
local RANK = { blocked = 4, review = 3, info = 2, none = 1 }
RV.RANK = RANK

local function Place(it)
    return it.id:find("^ellesmereui:pos%.") or it.id == (LY.EllesmereAdapter.LAYOUT_UNIT or "") or it.id == (LY.EllesmereAdapter.FIXED_UNIT or "")
        or LY.TwichUIAdapter.PlaceOf(it.id) ~= nil
end

-- { level = "blocked" | "review" | "info" | "none", list = { { code, level, text, evidence = { text }, action } } }.
-- blocked is only ever a failed check (the last one made, for a change that is included); the rest are explanations with their
-- evidence. A flag is a reason to look, not a verdict: nothing here rates a change safe, and the number of values that differ
-- is never one of the reasons.
function RV.Flags(it)
    local s = Sess()
    it.rv = it.rv or {}
    local c = it.rv.flags
    if c and c.rev == s.rev and c.report == s.report then return c end
    local list = {}
    local function Add(code, level, text, evidence, action)
        list[#list + 1] = { code = code, level = level, text = text, evidence = evidence or {}, action = action }
    end
    local scan = Scan(it)
    local impact = RV.Impact(it)
    -- a failed check: the last Check's media list names the file, and the change holds that file
    if s.report and it.include then
        local bad, shown = {}, {}
        for _, m in ipairs(s.report.media or {}) do
            if m.status == "foreign" or m.status == "unsafe" or m.status == "missing" then bad[m.path] = m.status end
        end
        for _, r in ipairs(scan.refs) do
            local st = bad[r.path]
            if st and not s.fixes[r.path] and #shown < 3 then
                shown[#shown + 1] = ("%s: %s"):format(r.file, st == "foreign" and "belongs to another addon" or st == "unsafe" and "outside the game's folders" or "not installed here")
            end
        end
        if #shown > 0 then
            Add("media-blocked", "blocked", "The last check refused a file this change points at.", shown,
                "Use TwichUI's copy under Check, or leave this change out.")
        end
    end
    if it.kind == "removed" then
        Add("removed", "review", ModuleOf(it) and "Removes a whole module's settings from the layout." or "Removes a setting the layout names.",
            { "Now kept in: " .. RV.Storage(it) }, "Check what players who have the layout would keep.")
    end
    if it.kind == "default" then
        if it.how == "release" then
            Add("release", "info", "Stops naming this setting: players keep what they have.", { "Setting: " .. it.label })
        else
            Add("reset", "review", "Players who have the layout go back to TwichUI's default for this setting.", { "Needs a TwichUI that reads package format 4." },
                "Choose Stop managing in the details if they should keep their own value.")
        end
    end
    if #scan.toggles > 0 then
        local ev = {}
        for _, t in ipairs(scan.toggles) do ev[#ev + 1] = ("%s: %s to %s (matched by the key name)"):format(t.raw, t.from and "On" or "Off", t.to and "On" or "Off") end
        Add("feature-toggled", "review", "A feature switch inside the module is flipped.", ev, "Open the details to see what the module switches.")
    end
    if Capture.Locate(it.id) == nil or it.label == it.id then
        Add("unrecognized", "review", "TwichUI cannot place or name this setting, so it cannot say what it does.", { it.id })
    end
    if #scan.refs > 0 then
        local ev = {}
        for _, r in ipairs(scan.refs) do
            if (r.source == "foreign" or r.source == "unsafe") and #ev < 3 then
                ev[#ev + 1] = ("%s: %s"):format(r.file, r.source == "unsafe" and "outside the game's folders" or "another addon's file")
            end
        end
        if #ev > 0 then
            Add("media-external", "review", "Points at a file that is not TwichUI's, EllesmereUI's or the game's.", ev,
                "Check will refuse it unless TwichUI has a copy of the file.")
        end
    end
    if it.id == (LY.EllesmereAdapter.CURSOR_UNIT or "") then
        Add("account-wide", "review", "EllesmereUI keeps this setting for the whole account, not for one profile.", { it.id })
    end
    if it.n and it.n.capped then
        Add("too-large", "review", "More values differ than TwichUI will count.", { ("%d+ values"):format(it.n.total) })
    end
    if RV.IsBlob(it) then
        local structural = (it.n.added or 0) + (it.n.removed or 0)
        if structural >= RV.STRUCTURE_MIN then
            Add("structure", "review", "The shape of the module changes, not only its values.",
                { ("%d %s added, %d removed inside it"):format(it.n.added, Plural(it.n.added, "setting", "settings"), it.n.removed) })
        end
        Add("whole-module", "info", "The module is replaced as a whole; its values cannot be included one at a time.", { RV.Details(it) .. " differ" })
    end
    if Place(it) then
        Add("geometry", "info", "Moves or resizes something on the screen.", { it.label })
    end
    if impact.none and not impact.unknown then
        Add("no-effect", "review", "No layout would change if this were published.", { impact.byVariant[1] and impact.byVariant[1].note or "" },
            "Another layer's value wins; leave it out, or change where it goes.")
    elseif it.to == "base" and #impact.changing >= 2 then
        Add("shared", "info", "A shared change: more than one layout gets the new value.", { ("Changes: %s"):format(impact.text) })
    end
    local level = "none"
    for _, f in ipairs(list) do if RANK[f.level] > RANK[level] then level = f.level end end
    c = { level = level, list = list, rev = s.rev, report = s.report }
    it.rv.flags = c
    return c
end

function RV.Level(it) return RV.Flags(it).level end

---------------------------------------------------------------------------
-- Reviewed: the author's acknowledgment of the change as proposed
---------------------------------------------------------------------------
local function Fp(v)
    if v == nil then return "~" end
    local ok, f = pcall(LY.Fingerprint, v)
    return ok and f or tostring(f)
end

-- The parts a review is tied to: the values, the destination (and how a reset reaches players), and the effect on each layout.
local function Parts(it)
    local impact = RV.Impact(it)
    local sig = {}
    for _, e in ipairs(impact.byVariant) do sig[#sig + 1] = e.variant .. (e.changes and ":1" or ":0") end
    return { value = Fp(it.old) .. "/" .. Fp(it.new), to = it.to, how = tostring(it.how), impact = table.concat(sig, ",") }
end

local STALE = { value = "the values changed", to = "its destination changed", how = "how a reset reaches players changed", impact = "the layouts it affects changed" }

function RV.IsReviewed(it)
    local s = Sess()
    local rec = s and s.reviewed[it.id]
    if not rec then return false end
    local now = Parts(it)
    for k in pairs(STALE) do if rec[k] ~= now[k] then return false end end
    return true
end

-- A mark that no longer fits: why ("the values changed" ...), or nil when it is current or there never was one.
function RV.StaleReason(it)
    local s = Sess()
    local rec = s and s.reviewed[it.id]
    if not rec then return nil end
    local now = Parts(it)
    for _, k in ipairs({ "value", "to", "how", "impact" }) do if rec[k] ~= now[k] then return STALE[k] end end
    return nil
end

-- Marks the change reviewed as it is now, or clears the mark. It changes nothing else: not whether it is included, not a check.
function RV.SetReviewed(id, on)
    local s = Sess()
    local it = s and s.itemBy and s.itemBy[id]
    if not it then return false end
    if on then s.reviewed[id] = Parts(it) else s.reviewed[id] = nil end
    return true
end

---------------------------------------------------------------------------
-- The table: filters, sort, pages
---------------------------------------------------------------------------
function RV.State()
    local s = Sess()
    if not s then return nil end
    local st = s.review
    if not st then
        st = { search = "", status = "all", kind = "all", layout = "all", sort = "attention", page = 1, size = RV.PAGE_SIZES[1], order = {}, stale = true }
        s.review = st
    end
    return st
end

local function Attention(it)
    if not it.include then return 4 end
    local level = RV.Level(it)
    if level == "blocked" then return 1 end
    if level == "review" and not RV.IsReviewed(it) then return 2 end
    return 3
end

local function Hay(it)
    it.rv = it.rv or {}
    if not it.rv.hay then
        it.rv.name = RV.Name(it):lower()
        it.rv.hay = (RV.Name(it) .. " " .. it.id .. " " .. KIND_LABEL[it.kind] .. " " .. it.label):lower()
    end
    return it.rv.hay
end

local function Matches(it, st)
    Hay(it)
    local inc = it.include
    local status = st.status
    if status == "included" and not inc then return false end
    if status == "excluded" and inc then return false end
    if status == "review" and not (inc and RV.Level(it) == "review" and not RV.IsReviewed(it)) then return false end
    if status == "blocked" and not (inc and RV.Level(it) == "blocked") then return false end
    if status == "reviewed" and not RV.IsReviewed(it) then return false end
    if st.kind ~= "all" and it.kind ~= st.kind then return false end
    if st.layout ~= "all" then
        local hit = false
        for _, id in ipairs(RV.Impact(it).changing) do if id == st.layout then hit = true end end
        if not hit then return false end
    end
    if st.search ~= "" then
        local q = st.search
        if not (Hay(it):find(q, 1, true) or RV.Destination(it):lower():find(q, 1, true)) then return false end
    end
    return true
end

local SORT = {
    attention = function(a, b, ka, kb) if ka.rank ~= kb.rank then return ka.rank < kb.rank end end,
    name = function() end,
    kind = function(a, b) if a.kind ~= b.kind then return KIND_ORDER[a.kind] < KIND_ORDER[b.kind] end end,
    details = function(a, b) if a.n.total ~= b.n.total then return a.n.total > b.n.total end end,
    destination = function(a, b) if a.to ~= b.to then return a.to == "variant" end end,
}

-- Works the order out again from the filters and the sort, and freezes it: a checkbox or a mark does not move a row. Called when
-- one of them changes, after a capture, and when the author asks for a refresh. Returns the number of changes in it.
function RV.Rebuild()
    local s = Sess()
    local st = RV.State()
    if not st then return 0 end
    local t0 = R.Perf.on and R.Perf.Start("layoutwizard.author.review")
    local order, keys = {}, {}
    for _, it in ipairs(s.items or {}) do
        if Matches(it, st) then
            order[#order + 1] = it
            keys[it] = { rank = Attention(it) }
        end
    end
    local cmp = SORT[st.sort] or SORT.attention
    table.sort(order, function(a, b)
        local r = cmp(a, b, keys[a], keys[b])
        if r ~= nil then return r end
        if a.rv.name ~= b.rv.name then return a.rv.name < b.rv.name end
        return a.id < b.id
    end)
    local ids = {}
    for i, it in ipairs(order) do ids[i] = it.id end
    st.order, st.items, st.stale = ids, s.items, false
    local pages = math.max(1, math.ceil(#ids / st.size))
    if st.page > pages then st.page = pages end
    if st.page < 1 then st.page = 1 end
    if t0 then R.Perf.Stop(t0) end
    return #ids
end

local function Ready()
    local st = RV.State()
    if not st then return nil end
    if st.stale or st.items ~= Sess().items then
        if st.selected and not (Sess().itemBy and Sess().itemBy[st.selected]) then st.selected, st.detail = nil, nil end
        RV.Rebuild()
    end
    return st
end

function RV.SetFilter(field, value)
    local st = RV.State()
    if not st then return false end
    if field == "search" then st.search = tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    elseif field == "status" then st.status = RV.STATUSES[Index(RV.STATUSES, value)].key
    elseif field == "kind" then st.kind = RV.KINDS[Index(RV.KINDS, value)].key
    elseif field == "layout" then
        st.layout = "all"
        for _, v in ipairs(Sess().variants) do if v == value then st.layout = v end end
    elseif field == "sort" then st.sort = RV.SORTS[Index(RV.SORTS, value)].key
    else return false end
    st.page = 1
    RV.Rebuild()
    return true
end

function RV.Filtered()
    local st = RV.State()
    return st and (st.search ~= "" or st.status ~= "all" or st.kind ~= "all" or st.layout ~= "all") or false
end

function RV.ClearFilters()
    local st = RV.State()
    if not st then return end
    st.search, st.status, st.kind, st.layout, st.page = "", "all", "all", "all", 1
    RV.Rebuild()
end

function RV.SetPageSize(n)
    local st = RV.State()
    for _, size in ipairs(RV.PAGE_SIZES) do
        if size == n then
            local first = (st.page - 1) * st.size + 1
            st.size = n
            st.page = math.floor((first - 1) / n) + 1
            RV.Rebuild()
            return true
        end
    end
    return false
end

function RV.SetPage(n)
    local st = Ready()
    if not st then return end
    local pages = math.max(1, math.ceil(#st.order / st.size))
    st.page = math.max(1, math.min(pages, n))
end

-- { rows = { change, ... } (this page), from, to, total (in the order), pages, page, size }
function RV.Page()
    local st = Ready()
    if not st then return { rows = {}, from = 0, to = 0, total = 0, pages = 1, page = 1, size = RV.PAGE_SIZES[1] } end
    local s = Sess()
    local total = #st.order
    local pages = math.max(1, math.ceil(total / st.size))
    if st.page > pages then st.page = pages end
    local from = (st.page - 1) * st.size + 1
    local to = math.min(total, from + st.size - 1)
    local rows = {}
    for i = from, to do
        local it = s.itemBy[st.order[i]]
        if it then rows[#rows + 1] = it end
    end
    return { rows = rows, from = total == 0 and 0 or from, to = to, total = total, pages = pages, page = st.page, size = st.size }
end

-- The summary: how many changes there are and what state they are in. All of it counts the whole session, not the filtered view;
-- shown is the view.
function RV.Counts()
    local s = Sess()
    local out = { changes = 0, included = 0, excluded = 0, review = 0, blocked = 0, reviewed = 0, shown = 0 }
    if not s or not s.items then return out end
    local st = Ready()
    out.shown = #st.order
    for _, it in ipairs(s.items) do
        out.changes = out.changes + 1
        if it.include then
            out.included = out.included + 1
            local level = RV.Level(it)
            if level == "blocked" then out.blocked = out.blocked + 1
            elseif level == "review" and not RV.IsReviewed(it) then out.review = out.review + 1 end
        else out.excluded = out.excluded + 1 end
        if RV.IsReviewed(it) then out.reviewed = out.reviewed + 1 end
    end
    return out
end

function RV.SummaryText()
    local c = RV.Counts()
    local text = ("%d %s · %d included · %d need review · %d blocked"):format(c.changes, Plural(c.changes, "change", "changes"), c.included, c.review, c.blocked)
    if c.reviewed > 0 then text = text .. (" · %d reviewed"):format(c.reviewed) end
    return text
end

---------------------------------------------------------------------------
-- Selection, details and the next change to look at
---------------------------------------------------------------------------
function RV.Select(id)
    local st = RV.State()
    local s = Sess()
    if not st then return false end
    if id ~= nil and not (s.itemBy and s.itemBy[id]) then return false end
    st.selected = id
    st.detail = nil
    return true
end

function RV.Selected()
    local st = RV.State()
    local s = Sess()
    return st and st.selected and s.itemBy and s.itemBy[st.selected] or nil
end

-- Moves to the page the change is on (in the current order).
function RV.Reveal(id)
    local st = Ready()
    for i, v in ipairs(st.order) do
        if v == id then st.page = math.floor((i - 1) / st.size) + 1 return true end
    end
    return false
end

-- The next included change that still needs a look, after the selected one, in the order shown (wrapping). nil when none.
function RV.NextNeedingReview()
    local st = Ready()
    local s = Sess()
    local at = 0
    for i, v in ipairs(st.order) do if v == st.selected then at = i end end
    local n = #st.order
    for step = 1, n do
        local id = st.order[((at - 1 + step) % n) + 1]
        local it = s.itemBy[id]
        if it and it.include and RV.Level(it) == "review" and not RV.IsReviewed(it) then return it end
    end
    return nil
end

-- Everything the details show for one change; the leaf rows are built here, once, and kept only for the selected change.
function RV.Detail(it)
    local st = RV.State()
    if st.detail and st.detail.id == it.id and st.detail.rev == Sess().rev then return st.detail end
    local t0 = R.Perf.on and R.Perf.Start("layoutwizard.author.review.detail")
    local rows, total, truncated = RV.Leaves(it)
    local d = { id = it.id, rev = Sess().rev, leaves = rows, total = total, truncated = truncated }
    st.detail = d
    if t0 then R.Perf.Stop(t0) end
    return d
end

---------------------------------------------------------------------------
-- Actions the table offers
---------------------------------------------------------------------------
-- What moving the change to the shared base would do to the other layouts: the layouts (besides the one being edited) that would
-- start to change. A promotion that only touches the edited layout needs no question.
function RV.PromotionReach(it)
    local s = Sess()
    local now = RV.Impact(it, it.to)
    local after = RV.Impact(it, "base")
    local reach = {}
    local had = {}
    for _, id in ipairs(now.changing) do had[id] = true end
    for _, id in ipairs(after.changing) do if not had[id] and id ~= s.variant then reach[#reach + 1] = RV.Short(id) end end
    return reach
end

-- Include (or leave out) every change in the current order, on every page. Returns how many changed state, and how many of those were
-- removals or resets (which start out left out because including them is a decision about players' settings).
function RV.Bulk(on)
    local st = Ready()
    local s = Sess()
    local changed, risky = 0, 0
    for _, id in ipairs(st.order) do
        local it = s.itemBy[id]
        if it and it.include ~= (on and true or false) then
            changed = changed + 1
            if on and (it.kind == "removed" or it.kind == "default") then risky = risky + 1 end
        end
    end
    return changed, risky
end

function RV.ApplyBulk(on)
    local st = Ready()
    local s = Sess()
    local n = 0
    for _, id in ipairs(st.order) do
        local it = s.itemBy[id]
        if it and it.include ~= (on and true or false) then
            A.SetInclude(it.id, on)
            n = n + 1
        end
    end
    return n
end

R.Perf.Gauge("layoutwizard.author.review.leaves", { label = "Layout authoring review table: leaf rows held for the open details (0 when none)", unit = "count", kind = "state",
    group = "layouts", read = function()
        local s = A.Session()
        local st = s and s.review
        return st and st.detail and #st.detail.leaves or 0
    end })
