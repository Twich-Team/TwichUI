-- TwichUI Layouts: what a package may be, and resolving one variant of it (architecture.md §1, §5)
-- A package is Lua data shipped in this addon. Nothing is ever loaded with loadstring. Checking it changes nothing
-- and calls no game function: each adapter turns its own fragments into units (Normalize) against its explicit list
-- of managed fields, and refuses anything else. One problem anywhere refuses the whole package: a partial layout is
-- never applied.
--
-- Formats 1 and 2 (what this version reads; 2 adds geometry):
--   { format = 1|2, id = "<stable id>", revision = n, title = "...", dev = true|nil, made = "...", source = "...",
--     requires = { [adapter] = true | { min = "x.y.z", tested = "x.y.z" } },
--     targets  = { twichui = "<TwichUI profile name>", ellesmereui = "<EllesmereUI profile name>" },
--     layers   = { base = { [adapter] = fragment },
--                  variants = { [variantId] = { [adapter] = fragment } },
--                  presets  = { [variantId] = { [adapter] = fragment } } },     -- presets optional
--     geometry = { ... } }   -- format 2 only: the screen rules (Geometry.lua), resolved for the player's screen
-- Fields of the contract's package that later phases add (choices; canvas and positions became geometry) are refused
-- as "not yet": this version cannot honour them, so it does not pretend to.

local R = TwichUI
local LY = R.Layouts

LY.FORMAT = 2
LY.MAX_UNITS = 256         -- units one adapter fragment may name (Classic Adventure's TwichUI looks are 206)
LY.MAX_EXPECT = LY.MAX_UNITS + 64   -- and what one adapter's record may expect: those, plus the places the screen layer adds
LY.MAX_VARIANTS = 8
LY.ADAPTERS, LY.ADAPTER_ORDER = {}, {}   -- filled by the adapter files

function LY.RegisterAdapter(a)
    assert(type(a) == "table" and LY.IsId(a.id), "an adapter with an id")
    if LY.ADAPTERS[a.id] then return end
    LY.ADAPTERS[a.id] = a
    LY.ADAPTER_ORDER[#LY.ADAPTER_ORDER + 1] = a.id
    table.sort(LY.ADAPTER_ORDER)
end

local FIELDS = LY.Set({ "format", "id", "revision", "title", "dev", "made", "source", "requires", "targets", "layers", "geometry" })
local NOT_YET = LY.Set({ "canvas", "choices", "positions", "tested" })
local LAYER_KEYS = LY.Set({ "base", "variants", "presets" })

local function Whole(n, min, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= min and n <= max end
local function Version(s) return type(s) == "string" and #s <= 24 and s:match("^%d+%.%d+[%.%d]*$") ~= nil end

-- Each adapter's fragment in one layer: units { [unitId] = value | REMOVE }, parents { [unitId] = parentUnitId }.
local function Fragments(layer, ctx, out, where)
    if type(layer) ~= "table" then ctx.problems.add("not-table", where) return end
    for adapterId, fragment in pairs(layer) do
        local a = type(adapterId) == "string" and LY.ADAPTERS[adapterId]
        if not a then
            ctx.problems.add("unknown-adapter", where .. "." .. tostring(adapterId))
        elseif type(fragment) ~= "table" then
            ctx.problems.add("not-table", where .. "." .. adapterId)
        else
            ctx.where = where .. "." .. adapterId
            local units, parents = a.Normalize(fragment, ctx)
            local n = 0
            for _ in pairs(units or {}) do n = n + 1 end
            if n > LY.MAX_UNITS then ctx.problems.add("too-many-units", ctx.where) end
            out[adapterId] = { units = units or {}, parents = parents or {} }
        end
    end
end

-- ok, problems, checked. checked = { id, revision, format, dev, variants = { sorted ids },
--   layers = { base = { [adapter] = { units, parents } }, variants = { [id] = ... }, presets = { [id] = ... } } }
function LY.Validate(pkg)
    local problems = LY.Problems()
    if type(pkg) ~= "table" then problems.add("not-table", "package") return false, problems end
    if not Whole(pkg.format, 1, 1e6) then problems.add("format", "package.format") return false, problems end
    if pkg.format > LY.FORMAT then problems.add("format-newer", "package.format") return false, problems end
    -- the whole of it must have a canonical text: no cycles, no functions, within the size bounds
    local _, why = LY.Canon(pkg)
    if why then problems.add("shape-" .. why, "package") return false, problems end

    for k in pairs(pkg) do
        if NOT_YET[k] then problems.add("not-yet", "package." .. tostring(k))
        elseif not FIELDS[k] then problems.add("unknown-field", "package." .. tostring(k)) end
    end
    if not LY.IsId(pkg.id) then problems.add("bad-id", "package.id") end
    if not Whole(pkg.revision, 1, 1e6) then problems.add("bad-revision", "package.revision") end
    if pkg.title ~= nil and not LY.Plain(pkg.title, 80) then problems.add("bad-value", "package.title") end
    if pkg.made ~= nil and not LY.Plain(pkg.made, 32) then problems.add("bad-value", "package.made") end
    if pkg.source ~= nil and not LY.Plain(pkg.source, 120) then problems.add("bad-value", "package.source") end
    if pkg.dev ~= nil and type(pkg.dev) ~= "boolean" then problems.add("bad-value", "package.dev") end

    if pkg.requires ~= nil then
        if type(pkg.requires) ~= "table" then problems.add("not-table", "package.requires")
        else
            for id, req in pairs(pkg.requires) do
                local where = "package.requires." .. tostring(id)
                if not LY.ADAPTERS[id] then problems.add("unknown-adapter", where)
                elseif type(req) == "table" then
                    for k, v in pairs(req) do
                        if k ~= "min" and k ~= "tested" then problems.add("unknown-field", where .. "." .. tostring(k))
                        elseif not Version(v) then problems.add("bad-value", where .. "." .. k) end
                    end
                elseif req ~= true then
                    problems.add("bad-value", where)
                end
            end
        end
    end

    local checked = { id = pkg.id, revision = pkg.revision, format = pkg.format, dev = pkg.dev == true,
        variants = {}, layers = { base = {}, variants = {}, presets = {} } }
    local ctx = { problems = problems, dev = pkg.dev == true, format = pkg.format }
    local layers = pkg.layers
    if type(layers) ~= "table" then
        problems.add("not-table", "package.layers")
        return false, problems
    end
    for k in pairs(layers) do
        if not LAYER_KEYS[k] then problems.add("unknown-field", "package.layers." .. tostring(k)) end
    end
    if type(layers.base) ~= "table" then problems.add("no-base", "package.layers.base")
    else
        ctx.layer = "base"
        Fragments(layers.base, ctx, checked.layers.base, "base")
    end
    if type(layers.variants) ~= "table" or next(layers.variants) == nil then
        problems.add("no-variants", "package.layers.variants")
    else
        local n = 0
        for id, layer in pairs(layers.variants) do
            n = n + 1
            if not LY.IsId(id) then problems.add("bad-id", "variants." .. tostring(id))
            else
                checked.variants[#checked.variants + 1] = id
                ctx.layer = "variant"
                checked.layers.variants[id] = {}
                Fragments(layer, ctx, checked.layers.variants[id], "variants." .. id)
            end
        end
        if n > LY.MAX_VARIANTS then problems.add("too-many-variants", "package.layers.variants") end
        table.sort(checked.variants)
    end
    if layers.presets ~= nil then
        if type(layers.presets) ~= "table" then problems.add("not-table", "package.layers.presets")
        else
            for id, layer in pairs(layers.presets) do
                if type(id) ~= "string" or checked.layers.variants[id] == nil then
                    problems.add("preset-without-variant", "presets." .. tostring(id))
                else
                    ctx.layer = "preset"
                    checked.layers.presets[id] = {}
                    Fragments(layer, ctx, checked.layers.presets[id], "presets." .. id)
                end
            end
        end
    end

    -- every adapter a layer names needs a target profile to install into
    local used = {}
    for _, frags in pairs({ checked.layers.base }) do for id in pairs(frags) do used[id] = true end end
    for _, layer in pairs(checked.layers.variants) do for id in pairs(layer) do used[id] = true end end
    for _, layer in pairs(checked.layers.presets) do for id in pairs(layer) do used[id] = true end end
    local targets = pkg.targets
    if type(targets) ~= "table" then
        if next(used) then problems.add("no-targets", "package.targets") end
    else
        for id, name in pairs(targets) do
            local a = LY.ADAPTERS[id]
            if not a then problems.add("unknown-adapter", "package.targets." .. tostring(id))
            elseif not a.TargetName(name) then problems.add("bad-target", "package.targets." .. id) end
        end
        for id in pairs(used) do
            if targets[id] == nil then problems.add("no-target", "package.targets." .. id) end
        end
    end
    checked.targets = targets
    checked.used = used

    -- the screen rules: format 2 only, checked against the adapters' position registries
    if pkg.geometry ~= nil then
        if pkg.format < 2 then problems.add("not-yet", "package.geometry")
        else checked.order = LY.Geometry.Check(pkg.geometry, problems, "geometry") end
        checked.geometry = pkg.geometry
    end
    return problems.n == 0, problems, checked
end

-- The layers for one variant, lowest first, as the composer takes them (§1), and the screen rules resolved for one
-- screen (layer 5, §7). Wizard choices and retained overrides are later phases: opts.choices (fragments already
-- normalized per adapter) and opts.retained / opts.reset ({ [adapter] = { [unit] = true } }) are passed through for
-- the composer's tests and later use. opts.screen = { w, h } (UIParent units) and opts.density (an id the package's
-- geometry names; "standard" if none) are needed only by a package with geometry.
-- Returns true, resolved | false, problems.
--   resolved = { id, revision, format, dev, variant, targets, adapters = { [adapter] = composed (Compose.lua) },
--                geometry = the resolved screen (Geometry.lua) | nil, attach = { [adapter] = map } | nil }
function LY.Resolve(pkg, variant, opts)
    opts = opts or {}
    local ok, problems, checked = LY.Validate(pkg)
    if not ok then return false, problems end
    if checked.layers.variants[variant] == nil then
        problems.add("variant-unknown", tostring(variant))
        return false, problems
    end
    local resolved = { id = checked.id, revision = checked.revision, format = checked.format, dev = checked.dev,
        variant = variant, targets = checked.targets, adapters = {} }
    for _, id in ipairs(LY.ADAPTER_ORDER) do
        if checked.used[id] then
            local stack, parents = {}, {}
            local function Push(name, frags)
                local f = frags and frags[id]
                if not f then return end
                stack[#stack + 1] = { name = name, units = f.units }
                for u, p in pairs(f.parents) do parents[u] = p end
            end
            Push("base", checked.layers.base)
            Push("variant", checked.layers.variants[variant])
            Push("preset", checked.layers.presets[variant])
            Push("choices", opts.choices)
            resolved.adapters[id] = LY.Compose(stack, parents, opts.retained and opts.retained[id], opts.reset and opts.reset[id])
        end
    end
    if checked.geometry then
        local density = opts.density or "standard"
        if checked.geometry.densities[density] == nil then
            problems.add("density-unknown", tostring(density))
            return false, problems
        end
        if opts.screen == nil then
            problems.add("no-screen", "geometry")
            return false, problems
        end
        local geo, why = LY.Geometry.Resolve(checked.geometry, opts.screen, { density = density })
        if not geo then
            problems.add(why == "screen" and "bad-screen" or "geometry", "geometry")
            return false, problems
        end
        resolved.geometry, resolved.attach = geo, checked.geometry.attach or {}
    end
    return true, resolved
end
