-- TwichUI Layouts: published layout packages (docs/layouts/publishing.md)
-- A publication is an immutable snapshot: the package (format 3, checked by the same LY.Validate every package gets) inside
-- an envelope that says what the author wants a recipient to read first. Every claim in the envelope that can be derived
-- from the package IS derived from it, again, by whoever reads it (variants, adapter requirements, media, which layer owns
-- how many units, a fingerprint), and a claim that doesn't match the package refuses the whole publication. The sender's
-- name is not in it at all: it comes from the game with the message (Share.lua) and is shown beside the package, never
-- taken from it.
--
--   envelope = { kind = "twichui-layout", v = 1, package = <package>, meta = {
--       id, version (= package.revision), format (= package.format), notes, published (a time), baseRevision, publisher,
--       client = "forever" | "other", variants = { { id, title } } (every variant, sorted by id),
--       requires = <package.requires>, adapters = { ids }, media = { { path, kind, source } },
--       ownership = { [layer] = { n, fp } }, counts = { units, variants }, hash } }
--
--   Pub.Build(package, opts)     -> envelope | nil, problems     (a deep copy: later edits of the package change nothing)
--   Pub.Check(envelope, opts)    -> ok, problems, info           (read only; info = { checked, derived, media })
--   Pub.Derive(package)          -> derived metadata | nil, problems
--   Pub.Refs(package)            -> media references { path, kind, source } (pure)
--   Pub.Resolve(refs)            -> { { path, kind, source, status } } status: ok | unverified | missing | foreign | unsafe
--   Pub.Layers(package)          -> the layers with their unit ids, for showing who owns what
-- Nothing here is run as code, nothing is written, and no game state is changed.

local R = TwichUI
local LY = R.Layouts
local Perf = R.Perf
local P = {}
LY.Pub = P

P.KIND = "twichui-layout"
P.VERSION = 1
-- Bounds. The wire size is the encoded envelope as sent (about 5 minutes at the game's addon-message rate per 200 KB).
P.LIMITS = { wire = R.Share and R.Share.LAYOUT_MAX_WIRE or 786432, notes = 600, noteLines = 12, publisher = 40, media = 64, string = 1024, title = 40, variants = LY.MAX_VARIANTS }

local ENVELOPE = LY.Set({ "kind", "v", "package", "meta" })
local META = LY.Set({ "id", "version", "format", "notes", "published", "baseRevision", "publisher", "client", "variants",
    "requires", "adapters", "media", "ownership", "counts", "hash" })

local function Whole(n, min, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= min and n <= max end

-- Release notes: plain text, a few short lines. A line break is allowed; nothing else that is not printable, and no "|".
function P.Notes(s)
    if type(s) ~= "string" or #s < 1 or #s > P.LIMITS.notes or s:find("|", 1, true) then return false end
    if s:find("[%z\1-\9\11-\31\127]") then return false end
    local lines = 1
    for _ in s:gmatch("\n") do lines = lines + 1 end
    return lines <= P.LIMITS.noteLines
end

---------------------------------------------------------------------------
-- Media: references to files, never files. A package names paths; the recipient's game finds the files.
---------------------------------------------------------------------------
local EXT = { ttf = "font", otf = "font", tga = "texture", blp = "texture", png = "texture", jpg = "texture", jpeg = "texture",
    ogg = "sound", mp3 = "sound", wav = "sound" }

local function Norm(path) return (path:gsub("/", "\\")) end

-- How a path is classed: "unsafe" (it leaves the game's folders), "twichui" / "ellesmereui" (a folder this installs or
-- the suite ships), "game" (the client's own), "foreign" (any other addon's, or a bare file we can't place)
local function Source(path)
    if path:find("^%a[%w+.%-]*://") or path:find("^%a:[/\\]") or path:find("^[/\\][/\\]") or path:find("%.%.") then return "unsafe" end
    local p = Norm(path):lower()
    local folder = p:match("^interface\\addons\\([^\\]+)\\")
    if folder then
        if folder == "!!!twichui" or folder:find("^twichui_") then return "twichui" end
        if folder == "ellesmereui" or folder:find("^ellesmereui_") or folder:find("^ellesmereui%a") then return "ellesmereui" end
        return "foreign"
    end
    if p:find("^interface\\") or p:find("^fonts\\") or p:find("^sound\\") or p:find("^textures\\") then return "game" end
    return "foreign"
end

local function ExtOf(path)
    local e = Norm(path):match("%.(%a+)$")
    return e and EXT[e:lower()] and e:lower() or nil
end

-- A string is a media reference when it names a file of a kind the game loads, or starts at one of the game's file roots.
local function LooksLikePath(s)
    if #s > P.LIMITS.string then return false end
    if ExtOf(s) then return true end
    local p = Norm(s):lower()
    return p:find("^interface\\addons\\") ~= nil or s:find("^%a:[/\\]") ~= nil or s:find("^%a[%w+.%-]*://") ~= nil
end

-- { { path, kind, source } } sorted by path, without repeats; bounded by the nodes the package already passed.
function P.Refs(pkg)
    local seen, list = {}, {}
    local function Add(s)
        if not LooksLikePath(s) then return end
        local key = Norm(s):lower()
        if seen[key] then return end
        seen[key] = true
        list[#list + 1] = { path = s, kind = EXT[ExtOf(s) or ""] or "other", source = Source(s) }
    end
    local function Walk(v, depth)
        if depth > 20 then return end
        if type(v) == "string" then Add(v)
        elseif type(v) == "table" and v ~= LY.REMOVE then
            for k, x in pairs(v) do
                if type(k) == "string" then Add(k) end
                Walk(x, depth + 1)
            end
        end
    end
    Walk(pkg, 0)
    table.sort(list, function(a, b) return Norm(a.path):lower() < Norm(b.path):lower() end)
    return list
end

-- What can be proven on this client: a font can be tried (SetFont says whether the game took the file); a texture or a
-- sound cannot be looked up without drawing or playing it, so it is "unverified" (its folder is one that belongs to the
-- suite, which is all that is known). Replaceable for tests.
P.probe = {
    font = function(path)
        local ok, fs = pcall(function() return UIParent:CreateFontString(nil, "OVERLAY") end)
        if not ok or not fs then return nil end
        local took = fs:SetFont(path, 12, "")
        return took ~= false
    end,
}

-- TwichUI's bundled media: the folder under media\\ and the file name, and whether the list in modules/Media.lua has the file.
local REGISTRY = { fonts = "MediaFonts", sounds = "MediaSounds", borders = "MediaBorders" }

function P.BundledKind(path)
    local sub = Norm(path):lower():match("^interface\\addons\\[^\\]+\\media\\([^\\]+)\\[^\\]+$")
    return sub and REGISTRY[sub] and sub or nil
end

function P.Bundled(path)
    local sub = P.BundledKind(path)
    if not sub then return false end
    local file = Norm(path):lower():match("([^\\]+)$")
    for _, f in pairs(R[REGISTRY[sub]] or {}) do
        if f:lower() == file then return true end
    end
    return false
end

-- A path in another addon whose file name is one of TwichUI's own fonts: TwichUI's copy, or nil. (An author's private font
-- folder usually holds the same file; the bundled copy is what a recipient has.)
function P.Substitute(path)
    if type(path) ~= "string" or Source(path) ~= "foreign" or ExtOf(path) ~= "ttf" and ExtOf(path) ~= "otf" then return nil end
    local file = Norm(path):lower():match("([^\\]+)$")
    for _, f in pairs(R.MediaFonts or {}) do
        if f:lower() == file then return (R.PATH or [[Interface\AddOns\!!!TwichUI\]]) .. [[media\fonts\]] .. f end
    end
    return nil
end

function P.Resolve(refs)
    local out = {}
    local E = rawget(_G, "EllesmereUI")
    for _, r in ipairs(refs) do
        local status
        if r.source == "unsafe" then status = "unsafe"
        elseif r.source == "foreign" then status = "foreign"
        elseif r.source == "game" then status = "ok"
        elseif r.source == "ellesmereui" and type(E) ~= "table" then status = "missing"
        elseif r.source == "twichui" and P.BundledKind(r.path) then
            -- TwichUI's own fonts, sounds and borders are a list it keeps (modules/Media.lua): the path must be one of them
            status = P.Bundled(r.path) and "ok" or "missing"
        elseif r.kind == "font" then
            local took = P.probe.font(r.path)
            status = took == true and "ok" or (took == false and "missing" or "unverified")
        else status = "unverified" end
        out[#out + 1] = { path = r.path, kind = r.kind, source = r.source, status = status }
    end
    return out
end

---------------------------------------------------------------------------
-- Who owns what: the units each layer names, as a count and a fingerprint of their ids and values
---------------------------------------------------------------------------
local function LayerOf(frags)
    local t, n = {}, 0
    for adapter, f in pairs(frags) do
        for unit, value in pairs(f.units) do t[adapter .. "|" .. unit] = value; n = n + 1 end
    end
    return t, n
end

local function Ownership(checked)
    local own = {}
    local function Put(name, frags)
        local t, n = LayerOf(frags)
        own[name] = { n = n, fp = LY.Fingerprint(t) }
    end
    Put("base", checked.layers.base)
    for _, id in ipairs(checked.variants) do
        Put("variant:" .. id, checked.layers.variants[id])
        if checked.layers.presets[id] then Put("preset:" .. id, checked.layers.presets[id]) end
    end
    if checked.choices then
        for _, cid in ipairs(checked.choices.order) do
            local ch = checked.choices.by[cid]
            for _, oid in ipairs(ch.order) do Put("choice:" .. cid .. ":" .. oid, ch.options[oid].frags) end
        end
    end
    return own
end

-- { { layer, adapter, unit } } for showing: every unit with the layer that holds it, sorted. Not stored or sent.
function P.Layers(pkg)
    local ok, _, checked = LY.Validate(pkg)
    if not ok then return nil end
    local out = {}
    local function Add(name, frags)
        for adapter, f in pairs(frags) do
            for unit in pairs(f.units) do out[#out + 1] = { layer = name, adapter = adapter, unit = unit } end
        end
    end
    Add("base", checked.layers.base)
    for _, id in ipairs(checked.variants) do
        Add("variant:" .. id, checked.layers.variants[id])
        if checked.layers.presets[id] then Add("preset:" .. id, checked.layers.presets[id]) end
    end
    table.sort(out, function(a, b)
        if a.layer ~= b.layer then return a.layer < b.layer end
        return a.unit < b.unit
    end)
    return out
end

---------------------------------------------------------------------------
-- What a package resolves to, apart from what it is called (RH-1 §9). LY.Resolve is a function of a package's layers, choices,
-- geometry, targets and requirements only, so two packages that agree on those resolve identically for every layout, every pick
-- and every screen, whatever their id, revision, title, notes, made, source or developer flag. The bundled package (made by
-- tools/update_bundled_layout.sh) and one published in game (/tui layout author) are made by different paths and may differ:
-- Pub.Compare says whether they do, and where.
--   Pub.Contents(pkg) -> contents | nil, problems. contents = { identity (a fingerprint of all of the below), meta = { id,
--     revision, format, title, made, source, dev }, parts = { ["layer:<name>"] = { [adapter|unit] = fingerprint },
--     geometry, choices, targets, requires (each a fingerprint) } }
--   Pub.Compare(a, b) -> { same (resolves the same), identity = { a, b }, differ = { { part, units = { ids } (≤ 12), n } },
--     meta = { { field, a, b } } }   a, b: packages
---------------------------------------------------------------------------
local function ChoiceShape(checked)
    -- what a choice resolves to: its kind, default, the options' ids, what each sets, its density; not the words shown
    local out = {}
    for _, cid in ipairs(checked.choices and checked.choices.order or {}) do
        local ch = checked.choices.by[cid]
        local opts = {}
        for _, oid in ipairs(ch.order) do
            local o = ch.options[oid]
            local frags = {}
            for adapter, f in pairs(o.frags or {}) do frags[adapter] = f.units end
            opts[#opts + 1] = { id = oid, density = o.density, frags = frags }
        end
        out[#out + 1] = { id = cid, kind = ch.kind, default = ch.default, sets = ch.sets, options = opts }
    end
    return out
end

function P.Contents(pkg)
    local ok, problems, checked = LY.Validate(pkg)
    if not ok then return nil, problems end
    local parts = {}
    local function Layer(name, frags)
        local t = {}
        for adapter, f in pairs(frags) do
            for unit, value in pairs(f.units) do t[adapter .. "|" .. unit] = LY.Fingerprint(value) end
        end
        parts["layer:" .. name] = t
    end
    Layer("base", checked.layers.base)
    for _, id in ipairs(checked.variants) do
        Layer("variant:" .. id, checked.layers.variants[id])
        if checked.layers.presets[id] then Layer("preset:" .. id, checked.layers.presets[id]) end
    end
    parts.geometry = LY.Fingerprint(pkg.geometry or false)
    parts.choices = LY.Fingerprint(ChoiceShape(checked))
    parts.targets = LY.Fingerprint(pkg.targets or false)
    parts.requires = LY.Fingerprint(pkg.requires or false)
    return { identity = LY.Fingerprint(parts), parts = parts,
        meta = { id = pkg.id, revision = pkg.revision, format = pkg.format, title = pkg.title, made = pkg.made, source = pkg.source,
            dev = pkg.dev == true } }
end

local function DoCompare(a, b)
    local ca, pa = P.Contents(a)
    local cb, pb = P.Contents(b)
    if not (ca and cb) then return nil, pa or pb end
    local out = { same = ca.identity == cb.identity, identity = { ca.identity, cb.identity }, differ = {}, meta = {} }
    local names = {}
    for k in pairs(ca.parts) do names[k] = true end
    for k in pairs(cb.parts) do names[k] = true end
    for _, name in ipairs(LY.SortedKeys(names)) do
        local x, y = ca.parts[name], cb.parts[name]
        if type(x) == "table" or type(y) == "table" then
            x, y = type(x) == "table" and x or {}, type(y) == "table" and y or {}
            local keys, units = {}, {}
            for k in pairs(x) do keys[k] = true end
            for k in pairs(y) do keys[k] = true end
            for _, k in ipairs(LY.SortedKeys(keys)) do if x[k] ~= y[k] then units[#units + 1] = k end end
            if #units > 0 then
                local shown = {}
                for i = 1, math.min(#units, 12) do shown[i] = units[i] end
                out.differ[#out.differ + 1] = { part = name, units = shown, n = #units }
            end
        elseif x ~= y then
            out.differ[#out.differ + 1] = { part = name, n = 1 }
        end
    end
    for _, k in ipairs({ "id", "revision", "format", "title", "made", "source", "dev" }) do
        if ca.meta[k] ~= cb.meta[k] then out.meta[#out.meta + 1] = { field = k, a = ca.meta[k], b = cb.meta[k] } end
    end
    return out
end
-- two validations and a fingerprint of every unit: a typed developer command (/tui layout compare) or a test, never a frame's work
function P.Compare(a, b) return Perf.Call("layouts.publish.compare", DoCompare, a, b) end

---------------------------------------------------------------------------
-- The package, held to more than LY.Validate asks: it is going to strangers
---------------------------------------------------------------------------
local function Strings(pkg, problems)
    local n = 0
    local function Check(s, path)
        if #s > P.LIMITS.string then problems.add("string-too-long", path)
        elseif s:find("%c") then problems.add("string-control", path)
        elseif s:sub(1, 5) == "!EUI_" then problems.add("export-string", path)
        elseif s:find("|H", 1, true) then problems.add("link-in-string", path) end
    end
    local function Walk(v, path, depth)
        if depth > 20 or problems.n > LY.MAX_PROBLEMS then return end
        if v == LY.REMOVE then problems.add("remove-not-published", path)
        elseif type(v) == "string" then Check(v, path)
        elseif type(v) == "table" then
            for k, x in pairs(v) do
                if type(k) == "string" then Check(k, path .. "[key]") end
                n = n + 1
                Walk(x, path .. "." .. tostring(k), depth + 1)
            end
        end
    end
    Walk(pkg, "package", 0)
end

-- ok, problems, checked
function P.Strict(pkg)
    local _, problems, checked = LY.Validate(pkg)
    if type(pkg) ~= "table" then return false, problems end
    if pkg.dev ~= nil then problems.add("dev-not-allowed", "package.dev") end
    if checked then
        if pkg.geometry == nil then problems.add("no-geometry", "package.geometry") end   -- the layout rules are part of a published layout
        Strings(pkg, problems)
        local refs = P.Refs(pkg)
        for _, r in ipairs(refs) do
            local where = tostring(r.path):gsub("[%c|]", "?"):sub(1, 120)
            if r.source == "unsafe" then problems.add("media-unsafe", where)
            elseif r.source == "foreign" then problems.add("media-foreign", where) end
        end
        if #refs > P.LIMITS.media then problems.add("too-many-media", "package") end
    end
    return problems.n == 0, problems, checked
end

---------------------------------------------------------------------------
-- Deriving the metadata, and building
---------------------------------------------------------------------------
function P.Derive(pkg)
    local ok, problems, checked = P.Strict(pkg)
    if not ok then return nil, problems end
    local adapters = {}
    for id in pairs(checked.used) do adapters[#adapters + 1] = id end
    table.sort(adapters)
    local units = 0
    local own = Ownership(checked)
    for _, o in pairs(own) do units = units + o.n end
    return { id = pkg.id, version = pkg.revision, format = pkg.format, variantIds = checked.variants,
        requires = LY.Copy(pkg.requires or {}), adapters = adapters, media = P.Refs(pkg), ownership = own,
        counts = { units = units, variants = #checked.variants }, hash = LY.Fingerprint(pkg) }, nil, checked
end

local function TitleCase(id)
    return (id:gsub("%-", " "):gsub("^%l", string.upper):gsub(" %l", string.upper))
end
P.TitleCase = TitleCase

-- opts = { notes, publisher, baseRevision, client, now, titles = { [variant id] = text } }
-- Returns envelope | nil, problems. The package is copied whole; the copy has no `dev` flag and nothing in it is shared with
-- the original, so editing the original afterwards cannot change what was published.
local function DoBuild(pkg, opts)
    opts = opts or {}
    local problems = LY.Problems()
    if type(pkg) ~= "table" then problems.add("not-table", "package") return nil, problems end
    local copy = LY.Copy(pkg)
    copy.dev = nil
    local d, bad, checked = P.Derive(copy)
    if not d then return nil, bad end
    if opts.notes ~= nil and not P.Notes(opts.notes) then problems.add("bad-notes", "meta.notes") end
    if opts.publisher ~= nil and not LY.Plain(opts.publisher, P.LIMITS.publisher) then problems.add("bad-publisher", "meta.publisher") end
    if opts.baseRevision ~= nil and not Whole(opts.baseRevision, 0, 1e6) then problems.add("bad-value", "meta.baseRevision") end
    if opts.client ~= nil and opts.client ~= "forever" and opts.client ~= "other" then problems.add("bad-value", "meta.client") end
    local variants = {}
    for _, id in ipairs(d.variantIds) do
        local title = opts.titles and opts.titles[id] or TitleCase(id)
        if not LY.Plain(title, P.LIMITS.title) then problems.add("bad-title", "meta.variants." .. id) end
        variants[#variants + 1] = { id = id, title = title }
    end
    if problems.n > 0 then return nil, problems end
    local env = { kind = P.KIND, v = P.VERSION, package = copy, meta = {
        id = d.id, version = d.version, format = d.format, notes = opts.notes, published = opts.now or time(),
        baseRevision = opts.baseRevision, publisher = opts.publisher, client = opts.client or "forever",
        variants = variants, requires = d.requires, adapters = d.adapters, media = d.media, ownership = d.ownership,
        counts = d.counts, hash = d.hash } }
    -- (Store.Seal checks the envelope again before it is packed, and it is the same function a recipient runs; checking it here
    -- too would cost the same again for nothing.)
    return env
end
function P.Build(pkg, opts) return Perf.Call("layouts.publish.build", DoBuild, pkg, opts) end

---------------------------------------------------------------------------
-- Checking an envelope (what arrived, or what is stored): read only
---------------------------------------------------------------------------
local function Same(a, b) return LY.Canon(a) == LY.Canon(b) and LY.Canon(a) ~= nil end

local function DoCheck(env, opts)
    local problems = LY.Problems()
    if type(env) ~= "table" then problems.add("not-table", "envelope") return false, problems end
    local canon, why = LY.Canon(env)   -- bounded: a cycle, a function, or too much is refused here
    if not canon then problems.add("shape-" .. tostring(why), "envelope") return false, problems end
    for k in pairs(env) do if not ENVELOPE[k] then problems.add("unknown-field", "envelope." .. tostring(k)) end end
    if env.kind ~= P.KIND then problems.add("bad-kind", "envelope.kind") return false, problems end
    if not Whole(env.v, 1, 1e6) then problems.add("bad-value", "envelope.v") return false, problems end
    if env.v > P.VERSION then problems.add("envelope-newer", "envelope.v") return false, problems end
    local meta = env.meta
    if type(meta) ~= "table" then problems.add("not-table", "meta") return false, problems end
    for k in pairs(meta) do if not META[k] then problems.add("unknown-field", "meta." .. tostring(k)) end end

    local d, bad, checked = P.Derive(env.package)
    if not d then
        for _, p in ipairs(bad) do problems.add(p.code, p.where) end
        return false, problems
    end
    -- the claims that are the package's own: derived again, compared
    if meta.id ~= d.id then problems.add("meta-mismatch", "meta.id") end
    if meta.version ~= d.version then problems.add("meta-mismatch", "meta.version") end
    if meta.format ~= d.format then problems.add("meta-mismatch", "meta.format") end
    if not Same(meta.requires, d.requires) then problems.add("meta-mismatch", "meta.requires") end
    if not Same(meta.adapters, d.adapters) then problems.add("meta-mismatch", "meta.adapters") end
    if not Same(meta.media, d.media) then problems.add("meta-mismatch", "meta.media") end
    if not Same(meta.ownership, d.ownership) then problems.add("meta-mismatch", "meta.ownership") end
    if not Same(meta.counts, d.counts) then problems.add("meta-mismatch", "meta.counts") end
    if meta.hash ~= d.hash then problems.add("meta-mismatch", "meta.hash") end
    -- the variants: exactly the package's, each with a title
    local vlist = meta.variants
    if type(vlist) ~= "table" or #vlist ~= #d.variantIds then problems.add("meta-mismatch", "meta.variants")
    else
        for i, v in ipairs(vlist) do
            if type(v) ~= "table" or v.id ~= d.variantIds[i] or not LY.Plain(v.title, P.LIMITS.title) then
                problems.add("meta-mismatch", "meta.variants")
                break
            end
            for k in pairs(v) do if k ~= "id" and k ~= "title" then problems.add("unknown-field", "meta.variants") end end
        end
    end
    -- the claims that are the author's own: only their shape
    if meta.notes ~= nil and not P.Notes(meta.notes) then problems.add("bad-notes", "meta.notes") end
    if meta.publisher ~= nil and not LY.Plain(meta.publisher, P.LIMITS.publisher) then problems.add("bad-publisher", "meta.publisher") end
    if not Whole(meta.published, 0, 2 ^ 40) then problems.add("bad-value", "meta.published") end
    if meta.baseRevision ~= nil and not Whole(meta.baseRevision, 0, 1e6) then problems.add("bad-value", "meta.baseRevision") end
    if meta.client ~= "forever" and meta.client ~= "other" then problems.add("bad-value", "meta.client") end
    return problems.n == 0, problems, { checked = checked, derived = d }
end

function P.Check(env, opts) return Perf.Call("layouts.publish.check", DoCheck, env, opts) end

-- Plain words for the codes, for the wizard and the chat line. Codes are a fixed vocabulary; paths are not shown.
P.EXPLAIN = {
    ["not-table"] = "it isn't a layout package",
    ["bad-kind"] = "it isn't a TwichUI layout package",
    ["envelope-newer"] = "it was made by a newer TwichUI than this one",
    ["format-newer"] = "its package format is newer than this TwichUI reads",
    ["meta-mismatch"] = "its description doesn't match what is inside it",
    ["no-geometry"] = "it has no layout rules for fitting a screen",
    ["dev-not-allowed"] = "it is marked as a developer package",
    ["export-string"] = "it carries an opaque EllesmereUI export, which can't be reviewed",
    ["string-too-long"] = "it holds text longer than a setting needs",
    ["string-control"] = "it holds text with control characters",
    ["link-in-string"] = "it holds a game link",
    ["remove-not-published"] = "it holds a placeholder a published package never has",
    ["media-unsafe"] = "it points at a file outside the game's folders",
    ["media-foreign"] = "it points at a file that belongs to another addon, which can't be sent along",
    ["too-many-media"] = "it names too many files",
    ["bad-notes"] = "its release notes aren't plain text of a few lines",
    ["bad-publisher"] = "its publisher label isn't plain text",
    ["bad-title"] = "a layout's name isn't plain text",
    ["unknown-field"] = "it has a field this version doesn't read",
    ["not-yet"] = "it asks for something this version can't do yet",
    ["unknown-unit"] = "it names a setting TwichUI doesn't manage",
    ["not-managed"] = "it names a setting a layout may not change",
    ["unknown-adapter"] = "it is for an addon this version doesn't support",
    ["unknown-group"] = "it names a feature this version doesn't have",
    ["bad-value"] = "a value isn't one a setting can have",
    ["too-many-units"] = "it changes more settings than a layout may",
    ["not-allowed"] = "it changes something a layout may not",
}

function P.Explain(problems, max)
    local out, seen = {}, {}
    for _, p in ipairs(problems or {}) do
        local code = tostring(p.code):gsub("^shape%-.*", "shape")
        local text = P.EXPLAIN[code] or (code == "shape" and "it is too large or too deep to be a layout package")
            or ("it failed a check (" .. tostring(p.code) .. ")")
        if not seen[text] then
            seen[text] = true
            out[#out + 1] = text
            if #out >= (max or 3) then break end
        end
    end
    return out
end
