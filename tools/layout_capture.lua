-- TwichUI layout capture: an author's saved settings, read as data and turned into a layout package's data file.
-- tools/update_bundled_layout.sh runs both captures for the shipped package (docs/layouts/updating-the-bundled-layout.md).
-- Runs outside the game with plain Lua 5.1 (+ luabitop), from the repository root:
--
--   lua5.1 tools/layout_capture.lua --eui <EllesmereUI.lua> --twichui <!!!TwichUI.lua> \
--       --eui-profile "<EllesmereUI profile>" --twichui-profile "<TwichUI profile>" \
--       --out TwichUI_Layouts/ClassicData.lua --report docs/layouts/capture-classic-adventure.md \
--       [--name CLASSIC_CAPTURE] [--client retail|forever] [--made YYYY-MM-DD]
--       [--title "Classic Adventure"] [--shared-with <earlier data file> [--shared-name CLASSIC_CAPTURE]]
--
-- A second layout of the same package (Compact Adventure) is captured with --shared-with, naming the first layout's data
-- file: whatever is identical in both (module blobs, root look keys, the layout links) is not written again. The
-- output lists the modules it left out with a fingerprint of each, so the package can keep them once in its shared base
-- and a test can prove the claim; a root look key that differs is refused (the look is shared by every layout). Without
-- --twichui-profile the TwichUI side is not captured at all (the layout shares the first layout's TwichUI settings).
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
for _, k in ipairs({ "eui", "twichui", "eui-profile", "out", "report" }) do
    if not args[k] then error("missing --" .. k .. " (see the header of tools/layout_capture.lua)") end
end
local NAME = args.name or "CLASSIC_CAPTURE"
assert(NAME:match("^[A-Z][A-Z0-9_]*$"), "--name: an upper-case identifier")
local TITLE = args.title or "Classic Adventure"
local SHARED_NAME = args["shared-name"] or "CLASSIC_CAPTURE"

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
-- The two profiles, through the adapters' allowlists: LY.Capture (TwichUI_Layouts/Capture.lua), the same code the in-game
-- authoring workspace runs, so the tool and the workspace keep exactly the same things
---------------------------------------------------------------------------
local euiName = args["eui-profile"]
local prof = EDB.profiles[euiName]
assert(type(prof) == "table", "no EllesmereUI profile with that name")
local twName = args["twichui-profile"]   -- nil: this layout has no TwichUI settings of its own
-- which profile is live in the copy loaded here (it loads as a character of its own, so it may not be the one live in game)
local live = type(c.TwichUIDB.profileState) == "table" and c.TwichUIDB.profileState.live or "Default"
local slot   -- the profile's table: the live one is TwichUIDB itself (schema 2), a stored one is TwichUIDB.profiles[name]
if twName == nil then slot = nil
elseif twName == live then slot = c.TwichUIDB
else
    slot = type(c.TwichUIDB.profiles) == "table" and c.TwichUIDB.profiles[twName]
    assert(type(slot) == "table", "no TwichUI profile with that name")
end
local taken, rep = LY.Capture.Read(prof, slot)
local report = { kept = {}, left = rep.left, notes = rep.notes }
local eui = taken.ellesmereui
local groups = taken.twichui and taken.twichui.groups or {}
local places = taken.twichui and taken.twichui.places or {}
local nFields, nSwitch, nDefault = rep.counts.fields, rep.counts.switches, rep.counts.defaults

---------------------------------------------------------------------------
-- A second layout: what is identical to the first is left out, with a fingerprint of it
---------------------------------------------------------------------------
local sameAs
if args["shared-with"] then
    local ref
    do
        local chunk = assert(loadfile(args["shared-with"]))   -- our own generated file in the repository, not a saved file
        local env = { TwichUI = { Layouts = {} } }
        setfenv(chunk, env)
        chunk()
        ref = env.TwichUI.Layouts[SHARED_NAME]
    end
    assert(type(ref) == "table" and type(ref.ellesmereui) == "table", "--shared-with: no " .. SHARED_NAME .. " in that file")
    sameAs = { root = {}, modules = {} }
    for k, v in pairs(eui.root) do
        if ref.ellesmereui.root[k] ~= nil and LY.Canon(v) == LY.Canon(ref.ellesmereui.root[k]) then
            sameAs.root[k] = true
            eui.root[k] = nil
        else
            io.stderr:write("the profile's look key '" .. tostring(k) .. "' differs from " .. SHARED_NAME .. ": the look (fonts, accent, "
                .. "palette) is shared by every layout of the package, so nothing is written\n")
            os.exit(1)
        end
    end
    for k in pairs(ref.ellesmereui.root) do
        if not sameAs.root[k] then
            io.stderr:write("the profile has no look key '" .. tostring(k) .. "' but " .. SHARED_NAME .. " does; nothing is written\n")
            os.exit(1)
        end
    end
    for m, b in pairs(eui.modules) do
        local r = ref.ellesmereui.modules[m]
        if r ~= nil and LY.Canon(b) == LY.Canon(r) then
            sameAs.modules[m] = LY.Fingerprint(b)
            eui.modules[m] = nil
        end
    end
    local only = {}
    for m in pairs(ref.ellesmereui.modules) do
        if eui.modules[m] == nil and not sameAs.modules[m] then only[#only + 1] = m end
    end
    table.sort(only)
    sameAs.firstOnly = #only > 0 and only or nil
    if eui.layout ~= nil and ref.ellesmereui.layout ~= nil and LY.Canon(eui.layout) == LY.Canon(ref.ellesmereui.layout) then
        sameAs.layout = true
        eui.layout = nil
    end
    sameAs.of = SHARED_NAME
end

local capture = {
    source = { client = args.client or "retail", made = args.made or os.date("!%Y-%m-%d"),
        ellesmereui = { version = type(EDB.lastLoginVersion) == "string" and EDB.lastLoginVersion or nil, uiScale = EDB.ppUIScale } },
    ellesmereui = eui,
    twichui = slot and { groups = groups, places = places } or nil,
    sameAs = sameAs,
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
local found, where = LY.Capture.Scan(capture, names, realms)
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
-- again (%s has the command, what was kept and left out, and the scan's result).
-- Plain data: the package file that uses it (Classic.lua) decides which layer each part goes in.

local LY = TwichUI.Layouts
LY.%s = ]]):format(capture.source.made, args.report:gsub("^.*/docs/", "docs/"), NAME)
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
L("# Layout capture: %s", TITLE)
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
if twName then L("| TwichUI profile | `%s`%s |", twName, twName == live and " (the profile in use)" or "")
else L("| TwichUI profile | none: this layout shares the first layout's TwichUI settings |") end
L("| Other profiles | not read |")
L("")
L("## Kept")
L("")
L("| Part | What | Size (canonical bytes) |")
L("|---|---|---|")
for _, k in ipairs(Sorted(eui.root)) do L("| EllesmereUI profile root | `%s` | %d |", k, Size(eui.root[k])) end
if eui.layout then L("| EllesmereUI layout links | `unlockLayout` (%s) | %d |", table.concat(Sorted(eui.layout), ", "), Size(eui.layout)) end
for _, m in ipairs(Sorted(eui.modules)) do L("| EllesmereUI module | `%s` | %d |", m, Size(eui.modules[m])) end
if slot then
    L("| TwichUI looks and behaviour | %d fields that differ from the defaults, in %d groups | %d |", nFields,
        #Sorted(groups), Size(groups))
    for _, id in ipairs(Sorted(places)) do L("| TwichUI place | `%s` | %d |", id, Size(places[id])) end
    L("")
    L("TwichUI fields not captured: %d on/off feature switches (a layout never turns a feature on or off), %d at their "
        .. "default. Never captured by the adapter's allowlist: anything in `TwichConfig.LOCAL` (acts, network, other, places "
        .. "outside `PLACES`), account-scoped settings, list groups.", nSwitch, nDefault)
end
L("")
if sameAs then
    L("## Identical to the first layout (kept once, in the package's shared base)")
    L("")
    L("Compared with `%s` in `%s`. Nothing here is written again; the fingerprints let a test prove the claim.", sameAs.of, args["shared-with"])
    L("")
    L("| What | Fingerprint |")
    L("|---|---|")
    for _, k in ipairs(Sorted(sameAs.root)) do L("| EllesmereUI profile root `%s` | (the look is shared) |", k) end
    for _, m in ipairs(Sorted(sameAs.modules)) do L("| EllesmereUI module `%s` | `%s` |", m, sameAs.modules[m]) end
    if sameAs.layout then L("| EllesmereUI layout links | identical |") end
    L("")
    if sameAs.firstOnly then
        L("In the first layout only (this profile has no such module): %s.", table.concat(sameAs.firstOnly, ", "))
        L("")
    end
end
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
L("    --eui-profile %q %s\\", euiName, twName and ("--twichui-profile " .. ("%q"):format(twName) .. " ") or "")
L("    --out %s --report %s --name %s --title %q --client %s --made %s%s", args.out, args.report, NAME, TITLE,
    capture.source.client, capture.source.made, sameAs and (" \\\n    --shared-with " .. args["shared-with"] .. " --shared-name " .. SHARED_NAME) or "")
L("```")
local rf = assert(io.open(args.report, "wb"))
rf:write(table.concat(lines, "\n"), "\n")
rf:close()
realPrint(("captured: %d EllesmereUI modules%s, %d root keys, layout links %s; %d TwichUI fields, %d places; %d bytes. Wrote %s and %s.")
    :format(#Sorted(eui.modules), sameAs and (" (+" .. #Sorted(sameAs.modules) .. " identical to " .. sameAs.of .. ")") or "", #Sorted(eui.root),
    eui.layout and "yes" or (sameAs and sameAs.layout and "identical" or "no"), nFields, #Sorted(places), #canon, args.out, args.report))
