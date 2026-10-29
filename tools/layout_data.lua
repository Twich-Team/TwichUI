-- TwichUI layout tools: reading saved files as data, and writing Lua data deterministically.
-- Shared by tools/layout_capture.lua (profile recapture), tools/import_published_layout.lua (a package published in game) and
-- tools/check_bundled_layout.lua, so the three read and write in exactly the same way. Plain Lua 5.1; no game, no addon.
--
--   LD.ReadData(path) -> { [variable name] = value }   a SavedVariables file read by a strict reader: names = values, tables,
--                        strings, numbers, booleans and nil. Anything else is an error. Nothing in the file is ever run.
--   LD.Emit(value) -> text                            the value as Lua data: sorted keys, the shortest number text that reads
--                        back the same, strings quoted with %q. The same value always gives the same text.
--   LD.ReadOwn(path, name) -> value | nil              one of OUR generated data files in the repository (`LY.<name> = ...`),
--                        loaded with an empty environment. Never used for a saved file or anything from outside.

LD = {}

function LD.ReadData(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    local i, n = 1, #s
    local function Fail(msg)
        local line = select(2, s:sub(1, i):gsub("\n", "")) + 1
        error(("%s: %s (line %d)"):format(path, msg, line), 0)
    end
    local function Space()
        while i <= n do
            local c = s:sub(i, i)
            if c:match("%s") then i = i + 1
            elseif s:sub(i, i + 1) == "--" then
                local nl = s:find("\n", i, true)
                i = nl and nl + 1 or n + 1
            else break end
        end
    end
    local ESC = { n = "\n", t = "\t", r = "\r", a = "\a", b = "\b", f = "\f", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }
    local Value
    local function String()
        local q = s:sub(i, i)
        i = i + 1
        local out = {}
        while true do
            if i > n then Fail("unfinished string") end
            local c = s:sub(i, i)
            if c == q then i = i + 1 return table.concat(out) end
            if c == "\\" then
                local d = s:match("^%d%d?%d?", i + 1)
                if d then out[#out + 1] = string.char(tonumber(d)); i = i + 1 + #d
                else
                    local e = ESC[s:sub(i + 1, i + 1)]
                    if not e then Fail("unknown escape") end
                    out[#out + 1] = e; i = i + 2
                end
            elseif c == "\n" then Fail("line break inside a string")
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    local function Table(depth)
        if depth > 40 then Fail("tables nested too deeply") end
        i = i + 1
        local t, seq = {}, 1
        while true do
            Space()
            if i > n then Fail("unfinished table") end
            local c = s:sub(i, i)
            if c == "}" then i = i + 1 return t end
            if c == "[" then
                i = i + 1
                local k = Value(depth)
                if type(k) == "table" or k == nil then Fail("a key must be a plain value") end
                Space()
                if s:sub(i, i) ~= "]" then Fail("']' expected") end
                i = i + 1
                Space()
                if s:sub(i, i) ~= "=" then Fail("'=' expected") end
                i = i + 1
                t[k] = Value(depth)
            else
                local id = s:match("^[%a_][%w_]*", i)
                local after = id and s:match("^%s*=", i + #id)
                if id and after and id ~= "true" and id ~= "false" and id ~= "nil" then
                    i = i + #id
                    Space()
                    i = i + 1
                    t[id] = Value(depth)
                else
                    t[seq] = Value(depth)
                    seq = seq + 1
                end
            end
            Space()
            local sep = s:sub(i, i)
            if sep == "," or sep == ";" then i = i + 1 elseif sep ~= "}" then Fail("',' or '}' expected") end
        end
    end
    function Value(depth)
        Space()
        local c = s:sub(i, i)
        if c == "{" then return Table((depth or 0) + 1) end
        if c == '"' or c == "'" then return String() end
        local num = s:match("^%-?0[xX]%x+", i) or s:match("^%-?%d+%.?%d*[eE][%+%-]?%d+", i) or s:match("^%-?%d+%.?%d*", i)
            or s:match("^%-?%.%d+", i)
        if num then i = i + #num return assert(tonumber(num)) end
        for word, v in pairs({ ["true"] = true, ["false"] = false }) do
            if s:sub(i, i + #word - 1) == word then i = i + #word return v end
        end
        if s:sub(i, i + 2) == "nil" then i = i + 3 return nil end
        Fail("unexpected '" .. c .. "'")
    end
    local vars = {}
    Space()
    while i <= n do
        local id = s:match("^[%a_][%w_]*", i)
        if not id then Fail("a variable name expected") end
        i = i + #id
        Space()
        if s:sub(i, i) ~= "=" then Fail("'=' expected") end
        i = i + 1
        vars[id] = Value(0)
        Space()
    end
    return vars
end

function LD.NumText(x)
    if x == math.floor(x) and math.abs(x) < 2 ^ 53 then return ("%d"):format(x) end
    for p = 14, 17 do
        local s = ("%." .. p .. "g"):format(x)
        if tonumber(s) == x then return s end
    end
    return ("%.17g"):format(x)
end

local KEYWORDS = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do KEYWORDS[w] = true end

function LD.KeyText(k)
    if type(k) == "string" then
        if k:match("^[%a_][%w_]*$") and not KEYWORDS[k] then return k end
        return "[" .. ("%q"):format(k) .. "]"
    end
    if type(k) == "number" then return "[" .. LD.NumText(k) .. "]" end
    return "[" .. tostring(k) .. "]"
end

function LD.Sorted(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
        return a < b
    end)
    return keys
end

function LD.Emit(v)
    local out = {}
    local function Emit(x, indent)
        local t = type(x)
        if t == "table" then
            local keys = LD.Sorted(x)
            if #keys == 0 then out[#out + 1] = "{}" return end
            out[#out + 1] = "{\n"
            for _, k in ipairs(keys) do
                out[#out + 1] = indent .. "  " .. LD.KeyText(k) .. " = "
                Emit(x[k], indent .. "  ")
                out[#out + 1] = ",\n"
            end
            out[#out + 1] = indent .. "}"
        elseif t == "string" then out[#out + 1] = (("%q"):format(x):gsub("\\\n", "\\n"))
        elseif t == "number" then out[#out + 1] = LD.NumText(x)
        elseif t == "boolean" then out[#out + 1] = tostring(x)
        else error("LD.Emit: a value of type " .. t .. " can't be written as data") end
    end
    Emit(v, "")
    return table.concat(out)
end

function LD.ReadOwn(path, name)
    local f = io.open(path, "rb")
    if not f then return nil end
    f:close()
    local chunk = assert(loadfile(path))   -- our own generated file in the repository, not a saved file
    local env = { TwichUI = { Layouts = {} } }
    setfenv(chunk, env)
    chunk()
    return env.TwichUI.Layouts[name]
end

-- The text of TwichUI_Layouts/ChoicesData.lua: the package's choices (the setup wizard's questions, the TwichUI presets among
-- them) as data. source: one line saying where they came from. The same choices and source always give the same text.
function LD.ChoicesFile(choices, source)
    return table.concat({
        "-- TwichUI Layouts: the Adventure package's choices (what the setup wizard asks, the TwichUI helper presets among them), as data.",
        "-- Generated: do not edit by hand. tools/update_bundled_layout.sh --from-published writes it from a package published in game",
        "-- (docs/layouts/presets.md); the profile recapture (the same script without --from-published) never touches it.",
        "-- Source: " .. source,
        "",
        "local LY = TwichUI.Layouts",
        "LY.ADVENTURE_CHOICES = " .. LD.Emit(choices),
        "",
    }, "\n")
end

function LD.ReadText(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- A published package may hold, in a layout's own part, a copy of a module the shared base already holds, where the two differ only
-- in how their numbers were written down: a position of 473.33 beside 473.33334350586, or the same colour to 14 or 15 digits (an
-- install writes positions to two decimals, and the transport writes 15 digits). Kept in the layout it would stop later changes to
-- the base from reaching that layout, so the bundled data keeps such a module once, in the base.
--   LD.SameToRounding(a, b, path, skip) -> true | false, path     structurally equal; a number counts as equal when it is the other to
--                        about 12 digits, or (a position or size, from 10 up) the other rounded to two decimals. Nothing coarser: a
--                        colour or an opacity is never matched by two decimals. skip is a set of "Module.key.key" paths left out
--   LD.DropSharedCopies(pkg) -> package, dropped, kept    pkg with those copies left out of every layout's own EllesmereUI modules
--                        (a new table along the changed path; pkg is not touched); dropped and kept are lists of
--                        "layout/Module" and, for kept ones, "layout/Module (first difference)". A setting a wizard choice always
--                        writes (an enum choice's `sets`, such as the friendly-plates choice's showFriendlyPlayers) is not compared:
--                        whatever the layer holds, the picked option replaces it, so a difference there changes nothing an install writes
local function Round2(x) return math.floor(x * 100 + 0.5) / 100 end
local function SameNumber(a, b)
    if a == b then return true end
    if a ~= a or b ~= b then return false end
    local scale = math.max(1, math.abs(a), math.abs(b))
    if math.abs(a - b) <= 1e-12 * scale then return true end
    if scale < 10 then return false end   -- only a position or a size is written to two decimals; a colour or a scale this small is not rounded
    return math.abs(Round2(a) - b) <= 1e-9 or math.abs(Round2(b) - a) <= 1e-9
end
function LD.SameToRounding(a, b, path, skip)
    path = path or ""
    if skip and skip[path] then return true end
    if type(a) ~= type(b) then return false, path end
    if type(a) == "number" then
        if SameNumber(a, b) then return true end
        return false, path
    elseif type(a) == "table" then
        for k, v in pairs(a) do
            local ok, where = LD.SameToRounding(v, b[k], path .. "." .. tostring(k), skip)
            if not ok then return false, where end
        end
        for k in pairs(b) do
            local sub = path .. "." .. tostring(k)
            if a[k] == nil and not (skip and skip[sub]) then return false, sub end
        end
        return true
    end
    if a == b then return true end
    return false, path
end

function LD.DropSharedCopies(pkg)
    local layers = pkg.layers
    local shared = layers and layers.base and layers.base.ellesmereui and layers.base.ellesmereui.modules
    local dropped, kept = {}, {}
    if type(shared) ~= "table" or type(layers.variants) ~= "table" then return pkg, dropped, kept end
    local skip = {}
    for _, ch in ipairs(pkg.choices or {}) do
        if ch.kind == "enum" then
            for _, id in ipairs(ch.sets or {}) do
                local path = type(id) == "string" and id:match("^ellesmereui:addons%.(.+)$")
                if path then skip[path] = true end
            end
        end
    end
    local newVariants = {}
    for id, v in pairs(layers.variants) do
        local mods = type(v) == "table" and type(v.ellesmereui) == "table" and v.ellesmereui.modules
        if type(mods) ~= "table" then newVariants[id] = v
        else
            local keep = {}
            for m, blob in pairs(mods) do
                local ok, where = false, nil
                if shared[m] ~= nil then ok, where = LD.SameToRounding(shared[m], blob, m, skip) end
                if ok then dropped[#dropped + 1] = id .. "/" .. m
                else
                    keep[m] = blob
                    if shared[m] ~= nil then kept[#kept + 1] = ("%s/%s (first difference: %s)"):format(id, m, where) end
                end
            end
            local eui = {}
            for k, x in pairs(v.ellesmereui) do eui[k] = x end
            eui.modules = keep
            local nv = {}
            for k, x in pairs(v) do nv[k] = x end
            nv.ellesmereui = eui
            newVariants[id] = nv
        end
    end
    table.sort(dropped)
    table.sort(kept)
    local nl = {}
    for k, x in pairs(layers) do nl[k] = x end
    nl.variants = newVariants
    local np = {}
    for k, x in pairs(pkg) do np[k] = x end
    np.layers = nl
    return np, dropped, kept
end

return LD
