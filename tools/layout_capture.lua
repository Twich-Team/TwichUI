-- TwichUI layout capture: an author's saved settings, read as data and turned into a layout package's data file.
-- Runs outside the game with plain Lua 5.1 (+ luabitop), from the repository root:
--
--   lua5.1 tools/layout_capture.lua --eui <EllesmereUI.lua> --twichui <!!!TwichUI.lua> \
--       --eui-profile "<EllesmereUI profile>" --twichui-profile "<TwichUI profile>" \
--       --out TwichUI_Layouts/ClassicData.lua --report docs/layouts/capture-classic-adventure.md \
--       [--name CLASSIC_CAPTURE] [--client retail|forever] [--made YYYY-MM-DD]
--
-- What it does, and what it never does:
--   * The saved files are read as data by a strict reader: names = values, tables, strings, numbers, booleans and nil.
--     Anything else is an error. Nothing in them is ever run, and they are never written (copy them first if the game
--     is running).
--   * Only the named profiles are read. Other profiles, characters, knowledge, caches and records are not looked at,
--     except that the character names are read (never written out) to check nothing of them got into the capture.
--   * What is kept is decided by the layout adapters' own allowlists, run here as the game would run them (TwichUI is
--     loaded offline the way the tests load it):
--       EllesmereUI: the profile-root keys in ROOT, the module blobs in MODULES (less the STRIP keys), and the layout
--         links (unlockLayout). Everything else in the profile is left out and listed in the report.
--       TwichUI: places in PLACES, and every looks-and-behaviour field the adapter manages (profile-scoped, not kept
--         local, not a feature's on/off switch) whose value differs from TwichUI's default.
--   * The output is checked before it is written: the data must have a canonical form within the package bounds, and
--     a scan for character and realm names (as whole words), player GUIDs, item or spell links and BattleTags must
--     find nothing. On any finding nothing is written.
-- The report lists what was kept, what was left out and why, counts and sizes, and the scan's result (counts only).

ROOT = "!!!TwichUI/"
REPO = "./"
TESTS = "tests/"
require("bit")

local args = {}
do
    local i = 1
    while i <= #arg do
        local k = arg[i]:match("^%-%-(.+)$")
        if not k then error("unexpected argument: " .. arg[i]) end
        args[k] = arg[i + 1]
        i = i + 2
    end
end
for _, k in ipairs({ "eui", "twichui", "eui-profile", "twichui-profile", "out", "report" }) do
    if not args[k] then error("missing --" .. k .. " (see the header of tools/layout_capture.lua)") end
end
local NAME = args.name or "CLASSIC_CAPTURE"
assert(NAME:match("^[A-Z][A-Z0-9_]*$"), "--name: an upper-case identifier")

---------------------------------------------------------------------------
-- Reading a SavedVariables file as data
---------------------------------------------------------------------------
local function ReadData(path)
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

---------------------------------------------------------------------------
-- TwichUI, loaded offline as the tests load it, with the author's TwichUI saved data (a copy) and the layout addon
---------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = Copy(x) end
    return o
end

local twichSV = ReadData(args.twichui)
local euiSV = ReadData(args.eui)
local TDB, EDB = twichSV.TwichUIDB, euiSV.EllesmereUIDB
assert(type(TDB) == "table", "no TwichUIDB in " .. args.twichui)
assert(type(EDB) == "table" and type(EDB.profiles) == "table", "no EllesmereUI profiles in " .. args.eui)

local realPrint = print
print = function() end   -- the harness's client chatter
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c = SettingsClient({ name = "Capture", beforeInit = function(c)
    c.TwichUIDB = Copy(TDB)
    c.print = function() end
end })
for line in io.lines(REPO .. "TwichUI_Layouts/TwichUI_Layouts.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    -- the layout code only: not the package data this tool writes
    if line ~= "" and not line:find("^#") and not line:find("Data%.lua$") and not line:find("^Classic") then
        local chunk = assert(loadfile(REPO .. "TwichUI_Layouts/" .. line))
        setfenv(chunk, c)
        chunk("TwichUI_Layouts", {})
    end
end
print = realPrint
local R = c.TwichUI
local LY = R.Layouts
local TA, EA = LY.TwichUIAdapter, LY.EllesmereAdapter

---------------------------------------------------------------------------
-- EllesmereUI: the one profile, through the adapter's allowlists
---------------------------------------------------------------------------
local report = { kept = {}, left = {}, notes = {} }
local function Left(where, why) report.left[#report.left + 1] = { where = where, why = why } end

local euiName = args["eui-profile"]
local prof = EDB.profiles[euiName]
assert(type(prof) == "table", "no EllesmereUI profile with that name")
local eui = { root = {}, modules = {}, layout = nil }
for k, v in pairs(prof) do
    if k == "unlockLayout" then
        eui.layout = {}
        for lk, lv in pairs(v) do
            if type(lv) == "table" and (lk == "anchors" or lk == "widthMatch" or lk == "heightMatch" or lk == "phantomBounds"
                or lk == "widthMatchExtra" or lk == "heightMatchExtra") then
                eui.layout[lk] = Copy(lv)
            else Left("unlockLayout." .. tostring(lk), "not a layout link table") end
        end
    elseif EA.ROOT[k] then eui.root[k] = Copy(v)
    elseif k ~= "addons" then   -- the module blobs are taken below, one by one
        Left("profile." .. tostring(k), k == "customColors" and "custom colours stay the recipient's (architecture.md §11.5)"
            or "not a key EllesmereUI's import takes, or not managed (AdapterEllesmere.lua ROOT)")
    end
end
for m, blob in pairs(prof.addons or {}) do
    if not EA.MODULES[m] then Left("addons." .. tostring(m), "not in EllesmereUI's profile module map (ADDON_DB_MAP)")
    elseif type(blob) ~= "table" then Left("addons." .. m, "not a table")
    else
        local b = Copy(blob)
        for _, k in ipairs(EA.STRIP[m] or {}) do
            if b[k] ~= nil then b[k] = nil; Left("addons." .. m .. "." .. k, "per-character or per-spec record (STRIP)") end
        end
        eui.modules[m] = b
    end
end

---------------------------------------------------------------------------
-- TwichUI: the looks and behaviour fields that differ from the defaults, and the places
---------------------------------------------------------------------------
local twName = args["twichui-profile"]
local live = type(TDB.profileState) == "table" and TDB.profileState.live or "Default"
local slot   -- the profile's table: the live one is TwichUIDB itself (schema 2), a stored one is TwichUIDB.profiles[name]
if twName == live then slot = c.TwichUIDB
else
    slot = type(c.TwichUIDB.profiles) == "table" and c.TwichUIDB.profiles[twName]
    assert(type(slot) == "table", "no TwichUI profile with that name")
end
local function ReadPath(t, at, key)
    for _, k in ipairs(at) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) == "table" then return t[key] end
end
local groups, nFields, nSwitch, nDefault = {}, 0, 0, 0
for _, f in pairs(TA.Fields()) do
    local v = ReadPath(slot, f.at, f.key)
    if v ~= nil and not R.TwichConfig.ValueOk(f, v) then v = nil end
    if f.switch then nSwitch = nSwitch + 1
    elseif v == nil or LY.Same(v, f.default) then nDefault = nDefault + 1
    else
        nFields = nFields + 1
        groups[f.group] = groups[f.group] or {}
        groups[f.group][f.slot] = groups[f.group][f.slot] or {}
        groups[f.group][f.slot][f.key] = Copy(v)
    end
end
local places = {}
for id, p in pairs(TA.PLACES) do
    local t = slot
    for _, k in ipairs(p.path) do t = type(t) == "table" and t[k] or nil end
    if type(t) == "table" and type(t.x) == "number" and type(t.y) == "number" then
        places[id] = p.kind == "point" and { point = t.point, x = t.x, y = t.y } or { x = t.x, y = t.y }
    else report.notes[#report.notes + 1] = "TwichUI place " .. id .. ": not set in the profile (the feature's default)" end
end

local capture = {
    source = { client = args.client or "retail", made = args.made or os.date("!%Y-%m-%d"),
        ellesmereui = { version = type(EDB.lastLoginVersion) == "string" and EDB.lastLoginVersion or nil, uiScale = EDB.ppUIScale } },
    ellesmereui = eui,
    twichui = { groups = groups, places = places },
}

---------------------------------------------------------------------------
-- Checks: bounds, and nothing personal
---------------------------------------------------------------------------
local canon, why = LY.Canon(capture)
assert(canon, "the capture has no canonical form: " .. tostring(why))

local names, realms = {}, {}
for key in pairs(type(TDB.profileKeys) == "table" and TDB.profileKeys or {}) do
    local nm, realm = tostring(key):match("^(.-) %- (.+)$")
    if nm then names[nm] = true; realms[realm] = true end
end
local found = { name = 0, realm = 0, guid = 0, link = 0, battletag = 0 }
local where = {}
local function Word(s, w) return s:find("%f[%w]" .. w:gsub("%p", "%%%0") .. "%f[%W]") ~= nil end
local function Scan(v, path)
    if type(v) == "table" then
        for k, x in pairs(v) do
            if type(k) == "string" then Scan(k, path .. "[key]") end
            Scan(x, path .. "." .. tostring(k))
        end
    elseif type(v) == "string" then
        local hit
        for nm in pairs(names) do if Word(v, nm) then found.name = found.name + 1; hit = "name" end end
        for rl in pairs(realms) do if Word(v, rl) then found.realm = found.realm + 1; hit = "realm" end end
        if v:find("Player%-%d+%-%x+") then found.guid = found.guid + 1; hit = "guid" end
        if v:find("|H", 1, true) then found.link = found.link + 1; hit = "link" end
        if v:find("[%a]#%d%d%d%d") then found.battletag = found.battletag + 1; hit = "battletag" end
        if hit and #where < 20 then where[#where + 1] = hit .. " at " .. path end
    end
end
Scan(capture, "capture")
local clean = true
for _, n in pairs(found) do if n > 0 then clean = false end end
if not clean then
    io.stderr:write("personal data found; nothing written:\n")
    for _, w in ipairs(where) do io.stderr:write("  " .. w .. "\n") end
    os.exit(1)
end

---------------------------------------------------------------------------
-- Writing: deterministic Lua data (sorted keys, the shortest number text that reads back the same)
---------------------------------------------------------------------------
local function NumText(x)
    if x == math.floor(x) and math.abs(x) < 2 ^ 53 then return ("%d"):format(x) end
    for p = 14, 17 do
        local s = ("%." .. p .. "g"):format(x)
        if tonumber(s) == x then return s end
    end
    return ("%.17g"):format(x)
end
local KEYWORDS = {}
for w in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do KEYWORDS[w] = true end
local function KeyText(k)
    if type(k) == "string" then
        if k:match("^[%a_][%w_]*$") and not KEYWORDS[k] then return k end
        return "[" .. ("%q"):format(k) .. "]"
    end
    if type(k) == "number" then return "[" .. NumText(k) .. "]" end
    return "[" .. tostring(k) .. "]"
end
local function Sorted(t)
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
local out = {}
local function Emit(v, indent)
    local t = type(v)
    if t == "table" then
        local keys = Sorted(v)
        if #keys == 0 then out[#out + 1] = "{}" return end
        out[#out + 1] = "{\n"
        for _, k in ipairs(keys) do
            out[#out + 1] = indent .. "  " .. KeyText(k) .. " = "
            Emit(v[k], indent .. "  ")
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    elseif t == "string" then out[#out + 1] = ("%q"):format(v):gsub("\\\n", "\\n")
    elseif t == "number" then out[#out + 1] = NumText(v)
    else out[#out + 1] = tostring(v) end
end
Emit(capture, "")
local body = table.concat(out)

local header = ([[
-- TwichUI Layouts: captured author settings (%s). Generated by tools/layout_capture.lua: do not edit by hand, run it
-- again (docs/layouts/capture-classic-adventure.md has the command, what was kept and left out, and the scan's result).
-- Plain data: the package file that uses it (Classic.lua) decides which layer each part goes in.

local LY = TwichUI.Layouts
LY.%s = ]]):format(capture.source.made, NAME)
local f = assert(io.open(args.out, "wb"))
f:write(header, body, "\n")
f:close()

-- the file reads back as the same data, and is valid as the package will use it
do
    local chunk = assert(loadfile(args.out))
    local env = { TwichUI = { Layouts = {} } }
    setfenv(chunk, env)
    chunk()
    assert(LY.Canon(env.TwichUI.Layouts[NAME]) == canon, "the written file does not read back as the capture")
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------
local function Size(v) local s = LY.Canon(v) return s and #s or 0 end
local function Count(v)
    if type(v) ~= "table" then return 1 end
    local n = 0
    for _, x in pairs(v) do n = n + Count(x) end
    return n
end
local lines = {}
local function L(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
L("# Layout capture: Classic Adventure")
L("")
L("Generated by `tools/layout_capture.lua` on %s. The data is in `%s` (`LY.%s`), %d bytes of canonical text, %d values.",
    capture.source.made, args.out, NAME, #canon, Count(capture))
L("")
L("## Source")
L("")
L("| | |")
L("|---|---|")
L("| Game client of the saved files | %s |", capture.source.client)
L("| EllesmereUI profile | `%s` (EllesmereUI %s; the account's UI scale %s, not captured) |", euiName,
    tostring(capture.source.ellesmereui.version), tostring(EDB.ppUIScale))
L("| TwichUI profile | `%s`%s |", twName, twName == live and " (the profile in use)" or "")
L("| Other profiles | not read |")
L("")
L("## Kept")
L("")
L("| Part | What | Size (canonical bytes) |")
L("|---|---|---|")
for _, k in ipairs(Sorted(eui.root)) do L("| EllesmereUI profile root | `%s` | %d |", k, Size(eui.root[k])) end
L("| EllesmereUI layout links | `unlockLayout` (%s) | %d |", table.concat(Sorted(eui.layout or {}), ", "), Size(eui.layout))
for _, m in ipairs(Sorted(eui.modules)) do L("| EllesmereUI module | `%s` | %d |", m, Size(eui.modules[m])) end
L("| TwichUI looks and behaviour | %d fields that differ from the defaults, in %d groups | %d |", nFields,
    #Sorted(groups), Size(groups))
for _, id in ipairs(Sorted(places)) do L("| TwichUI place | `%s` | %d |", id, Size(places[id])) end
L("")
L("TwichUI fields not captured: %d on/off feature switches (a layout never turns a feature on or off), %d at their "
    .. "default. Never captured by the adapter's allowlist: anything in `TwichConfig.LOCAL` (acts, network, other, places "
    .. "outside `PLACES`), account-scoped settings, list groups.", nSwitch, nDefault)
L("")
L("## Left out")
L("")
table.sort(report.left, function(a, b) return a.where < b.where end)
L("| Where | Why |")
L("|---|---|")
for _, e in ipairs(report.left) do L("| `%s` | %s |", e.where, e.why) end
L("")
for _, n in ipairs(report.notes) do L("- %s", n) end
L("")
L("## Personal data scan")
L("")
L("Every string in the capture (keys and values) was checked for the account's %d character names and %d realm names "
    .. "as whole words, player GUIDs, `|H` links and BattleTags. Found: %d names, %d realms, %d GUIDs, %d links, "
    .. "%d BattleTags. (The names themselves are never written anywhere.)", (function() local n = 0 for _ in pairs(names) do n = n + 1 end return n end)(),
    (function() local n = 0 for _ in pairs(realms) do n = n + 1 end return n end)(), found.name, found.realm, found.guid, found.link, found.battletag)
L("")
L("## Command")
L("")
L("```")
L("lua5.1 tools/layout_capture.lua --eui <copy of EllesmereUI.lua> --twichui <copy of !!!TwichUI.lua> \\")
L("    --eui-profile %q --twichui-profile %q \\", euiName, twName)
L("    --out %s --report %s --name %s --client %s --made %s", args.out, args.report, NAME, capture.source.client, capture.source.made)
L("```")
local rf = assert(io.open(args.report, "wb"))
rf:write(table.concat(lines, "\n"), "\n")
rf:close()
realPrint(("captured: %d EllesmereUI modules, %d root keys, layout links %s; %d TwichUI fields, %d places; %d bytes. Wrote %s and %s.")
    :format(#Sorted(eui.modules), #Sorted(eui.root), eui.layout and "yes" or "no", nFields, #Sorted(places), #canon, args.out, args.report))
