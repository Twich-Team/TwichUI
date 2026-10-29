-- TwichUI bundled layout: import a package the author published in game (docs/layouts/presets.md).
-- tools/update_bundled_layout.sh --from-published runs it, with its own backup, checks and tests around it. By hand, from the
-- repository root (plain Lua 5.1 + luabitop):
--
--   lua5.1 tools/import_published_layout.lua --sv <copy of !!!TwichUI.lua> [--revision N] [--hash FINGERPRINT] [--list]
--   lua5.1 tools/import_published_layout.lua --text <file holding the in-game "Export for bundling" text>
--       [--report docs/layouts/import-published.md] [--dry-run]
--
-- What it does:
--   1. finds the published entry (TwichUIDB.layouts.published in the saved file, read as data by the strict reader; or the export
--      text), unpacks it with the transport's own bounded decoder and checks it with Pub.Check, exactly as a recipient's TwichUI
--      does. A package that fails, or isn't the bundled package's (`twichui-adventure`), is refused and nothing is written;
--   2. compares it with the package in the repository. The parts written by hand in Classic.lua (the screen rules, the target
--      profiles, the requirements) must be the same, or it stops and says which; the package's revision must be higher than the
--      bundled one unless nothing differs (then it writes nothing: already bundled);
--   3. writes the package's choices (the TwichUI presets among them) to TwichUI_Layouts/ChoicesData.lua exactly; when its layers
--      differ, writes them back into ClassicData.lua and CompactData.lua in the form Classic.lua composes (or stops, when the
--      package holds something that form can't, such as a TwichUI setting kept in one layout only); sets the revision in
--      Classic.lua; and writes a report (what it came from, what changed, what it left out);
--   4. checks the result in a fresh process (tools/check_bundled_layout.lua --published ...): the bundled package must resolve
--      exactly as the published one does (Pub.Compare) and hold its choices byte for byte. If not, every file is put back.
-- Each file is written only when its text changes, and the same package always gives the same files. Nothing is committed, no
-- saved file is written, and no other file is touched. Exit 0: imported or already bundled; 1: refused or failed (nothing changed);
-- 2: bad arguments.

ROOT = "!!!TwichUI/"
REPO = REPO or "./"
TESTS = "tests/"
require("bit")

local args = {}
do
    local i = 1
    while i <= #arg do
        local k = arg[i]:match("^%-%-(.+)$")
        if not k then io.stderr:write("unexpected argument: " .. arg[i] .. "\n") os.exit(2) end
        if k == "list" or k == "dry-run" then args[k] = true i = i + 1
        else args[k] = arg[i + 1] i = i + 2 end
    end
end
if not args.sv and not args.text then
    io.stderr:write("Name the published package: --sv <copy of !!!TwichUI.lua> or --text <file with the exported text> (see the header of tools/import_published_layout.lua)\n")
    os.exit(2)
end
local REPORT = args.report or "docs/layouts/import-published.md"
local WANT_REV = args.revision and tonumber(args.revision)
if args.revision and not WANT_REV then io.stderr:write("--revision: a whole number\n") os.exit(2) end

dofile(REPO .. "tools/layout_data.lua")
dofile(REPO .. "tools/published_entry.lua")

local function Stop(fmt, ...)
    io.stderr:write("Not imported: " .. (select("#", ...) > 0 and fmt:format(...) or fmt) .. "\nNothing was written.\n")
    os.exit(1)
end

---------------------------------------------------------------------------
-- TwichUI and the layouts addon, offline (as the tests and the other tools load them), with the package as it is now
---------------------------------------------------------------------------
local realPrint = print
print = function() end
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c = SettingsClient({ name = "Import", beforeInit = function(c) c.print = function() end end })
for line in io.lines(REPO .. "TwichUI_Layouts/TwichUI_Layouts.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then
        local chunk = assert(loadfile(REPO .. "TwichUI_Layouts/" .. line))
        setfenv(chunk, c)
        chunk("TwichUI_Layouts", {})
    end
end
print = realPrint
local LY = c.TwichUI.Layouts
local Pub = LY.Pub
local bundled = LY.ADVENTURE_PACKAGE

---------------------------------------------------------------------------
-- 1. The published entry, unpacked and checked as a recipient checks it
---------------------------------------------------------------------------
local entry, sourceText
if args.text then
    local text = LD.ReadText(args.text)
    if not text then Stop("can't read %s", args.text) end
    local why
    entry, why = PE.Parse(text)
    if not entry then Stop("the text in %s: %s", args.text, why) end
    sourceText = "the exported text in " .. args.text:gsub("^.*/", "")
else
    local entries, why = PE.FromSaved(args.sv)
    if not entries then Stop("%s: %s", args.sv, why) end
    if args.list then
        realPrint("Published packages in " .. args.sv .. ":")
        for _, e in ipairs(entries) do realPrint("  " .. PE.Describe(e) .. (e.title and (" (\"" .. e.title .. "\")") or "")) end
        os.exit(0)
    end
    entry, why = PE.Pick(entries, WANT_REV, args.hash)
    if not entry then
        io.stderr:write("Not imported: " .. why .. ". The published packages there are:\n")
        for _, e in ipairs(entries) do io.stderr:write("  " .. PE.Describe(e) .. "\n") end
        io.stderr:write("Nothing was written.\n")
        os.exit(1)
    end
    sourceText = "the published list in a copy of the saved file (TwichUIDB.layouts.published)"
end
local env, why = PE.Open(c, entry)
if not env then Stop("%s: %s", PE.Describe(entry), why) end
local pkg = env.package
if pkg.id ~= bundled.id then Stop("it is the package %q; TwichUI bundles %q", tostring(pkg.id), bundled.id) end
-- a layout's own copy of a shared module that differs only in how its numbers were written is left out (kept once, in the base)
local droppedCopies, keptCopies
pkg, droppedCopies, keptCopies = LD.DropSharedCopies(pkg)

---------------------------------------------------------------------------
-- 2. Against the package in the repository
---------------------------------------------------------------------------
local hand = {}
for _, k in ipairs({ "geometry", "targets", "requires" }) do
    if LY.Canon(pkg[k] or false) ~= LY.Canon(bundled[k] or false) then hand[#hand + 1] = k end
end
if #hand > 0 then
    Stop("its %s %s from the bundled package's. Classic.lua holds %s by hand: change it there (or publish from a package with the same), then import again.",
        table.concat(hand, " and "), #hand == 1 and "differs" or "differ", #hand == 1 and "it" or "them")
end
local sameChoices = LY.Canon(pkg.choices or false) == LY.Canon(bundled.choices or false)
local sameLayers = LY.Canon(pkg.layers) == LY.Canon(bundled.layers)
if sameChoices and sameLayers then
    realPrint(("Already bundled: %s resolves exactly as the package in the repository (revision %d) and holds the same choices. Nothing was written.")
        :format(PE.Describe(entry), bundled.revision))
    os.exit(0)
end
if pkg.revision <= bundled.revision then
    Stop("it is revision %d, and the bundled package is already revision %d with other contents. Publish a higher revision in game (the workspace starts from the bundled revision plus one).",
        pkg.revision, bundled.revision)
end

---------------------------------------------------------------------------
-- 3. The files
---------------------------------------------------------------------------
local files, order = {}, {}
local function Put(path, text) if not files[path] then order[#order + 1] = path end files[path] = text end
local made = os.date("!%Y-%m-%d", env.meta.published)
local source = ("package %s revision %d (fingerprint %s), published in game on %s; imported by tools/import_published_layout.lua")
    :format(pkg.id, pkg.revision, env.meta.hash, made)
Put("TwichUI_Layouts/ChoicesData.lua", LD.ChoicesFile(pkg.choices, source))

-- the layers, back into the two data files Classic.lua composes (only the form it composes; anything else stops here)
local layerNote
if not sameLayers then
    local L = pkg.layers
    local CV, KV = LY.CLASSIC_VARIANT, LY.COMPACT_VARIANT
    local function Only(t, keys, where)
        for k in pairs(t or {}) do if not keys[k] then Stop("its %s holds %q, which the bundled data files can't hold (Classic.lua composes the layers in one form). Recapture with tools/update_bundled_layout.sh, or keep that change out of the published package.", where, tostring(k)) end end
    end
    Only(L, { base = true, variants = true }, "layers")
    Only(L.base, { ellesmereui = true, twichui = true }, "shared base")
    Only(L.base.ellesmereui, { root = true, modules = true }, "shared base's EllesmereUI part")
    Only(L.base.twichui, { groups = true, places = true, reset = true }, "shared base's TwichUI part")
    Only(L.variants, { [CV] = true, [KV] = true }, "layouts")
    for _, v in ipairs({ CV, KV }) do
        if type(L.variants[v]) ~= "table" or type(L.variants[v].ellesmereui) ~= "table" then Stop("its layout %s has no EllesmereUI part", v) end
        Only(L.variants[v], { ellesmereui = true }, "layout " .. v .. " (a TwichUI setting kept in one layout only)")
        Only(L.variants[v].ellesmereui, { modules = true, layout = true }, "layout " .. v .. "'s EllesmereUI part")
    end
    if type(L.base.ellesmereui) ~= "table" or type(L.base.twichui) ~= "table" then Stop("its shared base has no EllesmereUI or no TwichUI part") end
    local base, cv, kv = L.base, L.variants[CV].ellesmereui, L.variants[KV].ellesmereui
    local C0, K0 = LY.CLASSIC_CAPTURE, LY.COMPACT_CAPTURE
    local cmods = {}
    for m, b in pairs(base.ellesmereui.modules or {}) do cmods[m] = b end
    for m, b in pairs(cv.modules or {}) do
        if cmods[m] ~= nil then Stop("the module %s is in both the shared base and Classic Adventure's own part", m) end
        cmods[m] = b
    end
    local C = { source = LY.Copy(C0.source), ellesmereui = { root = base.ellesmereui.root or {}, modules = cmods, layout = cv.layout },
        twichui = { groups = base.twichui.groups or {}, places = base.twichui.places or {}, reset = base.twichui.reset } }
    C.source.made = made
    local sameAs = { of = "CLASSIC_CAPTURE", root = {}, modules = {} }
    for k in pairs(C.ellesmereui.root) do sameAs.root[k] = true end
    for m, b in pairs(base.ellesmereui.modules or {}) do sameAs.modules[m] = LY.Fingerprint(b) end
    local only = {}
    for m in pairs(cv.modules or {}) do if not (kv.modules and kv.modules[m]) then only[#only + 1] = m end end
    table.sort(only)
    sameAs.firstOnly = #only > 0 and only or nil
    if kv.layout == nil and K0.sameAs and K0.sameAs.layout then sameAs.layout = true end
    local K = { source = LY.Copy(K0.source), ellesmereui = { root = {}, modules = kv.modules or {}, layout = kv.layout }, sameAs = sameAs }
    K.source.made = made
    local function DataFile(name, value, title)
        return table.concat({
            ("-- TwichUI Layouts: author settings (%s), %s. Written by tools/import_published_layout.lua from a package published in game"):format(made, title),
            ("-- (%s has where it came from): do not edit by hand. A profile recapture (tools/update_bundled_layout.sh) writes it again from"):format(REPORT),
            "-- saved profiles. Plain data: the package file that uses it (Classic.lua) decides which layer each part goes in.",
            "",
            "local LY = TwichUI.Layouts",
            "LY." .. name .. " = " .. LD.Emit(value),
            "",
        }, "\n")
    end
    Put("TwichUI_Layouts/ClassicData.lua", DataFile("CLASSIC_CAPTURE", C, "Classic Adventure"))
    Put("TwichUI_Layouts/CompactData.lua", DataFile("COMPACT_CAPTURE", K, "Compact Adventure (what differs from Classic)"))
    layerNote = true
end

-- the revision line in Classic.lua (the one place it is written)
local classic = assert(LD.ReadText(REPO .. "TwichUI_Layouts/Classic.lua"))
local n = select(2, classic:gsub('id = "twichui%-adventure", revision = %d+', ""))
if n ~= 1 then Stop("couldn't find the one revision line in TwichUI_Layouts/Classic.lua") end
Put("TwichUI_Layouts/Classic.lua", (classic:gsub('(id = "twichui%-adventure", revision = )%d+', "%1" .. pkg.revision)))

-- what changed, for the report (and the screen)
local cmp = Pub.Compare(bundled, pkg)
local function OptionLines(choices)
    local out = {}
    for _, ch in ipairs(choices or {}) do
        if ch.kind == "preset" then
            out[#out + 1] = ("Selector `%s` (\"%s\")%s, default `%s`%s:"):format(ch.id, ch.label, ch.mode == "settings" and ", editable presets (format 6)" or ", switch-on-only presets",
                tostring(ch.default), ch.retired and (", no longer offered: " .. table.concat(ch.retired, ", ")) or "")
            for _, o in ipairs(ch.options) do
                local units = {}
                if type(o.twichui) == "table" then
                    units = LY.TwichUIAdapter.Normalize(o.twichui, { problems = LY.Problems(), where = "x", format = pkg.format, layer = "preset", settings = ch.mode == "settings" or nil }) or {}
                end
                local sm = LY.TwichUIAdapter.Summarize(units)
                out[#out + 1] = ("- `%s` \"%s\": %s"):format(o.id, o.label, o.keep and "leave them as they are (names nothing)"
                    or ("%d settings; on: %s; off: %s; %d other, %d reset"):format(sm.total, #sm.on > 0 and table.concat(sm.on, ", ") or "none",
                        #sm.off > 0 and table.concat(sm.off, ", ") or "none", sm.set, sm.reset))
            end
        end
    end
    return out
end
local lines = {}
local function Line(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
Line("# Bundled layout: imported from a package published in game")
Line("")
Line("Written by `tools/import_published_layout.lua` (`tools/update_bundled_layout.sh --from-published`). Generated: do not edit by hand.")
Line("The procedure is in `docs/layouts/presets.md`.")
Line("")
Line("## Source")
Line("")
Line("| | |")
Line("|---|---|")
Line("| Package | `%s`, revision %d |", pkg.id, pkg.revision)
Line("| Fingerprint | `%s` (the envelope's, derived again and checked) |", env.meta.hash)
Line("| What it resolves to | `%s` (`Pub.Contents`: layers, choices, screen rules, targets, requirements) |", Pub.Contents(pkg).identity)
Line("| Published | %s in game, on a %s client |", made, env.meta.client == "forever" and "WoW: Forever" or "non-Forever")
Line("| Read from | %s |", sourceText)
Line("| Checked | `Pub.Check`, as a recipient's TwichUI checks it |")
Line("")
Line("## What changed in the bundled package")
Line("")
Line("Revision %d to %d.", bundled.revision, pkg.revision)
Line("")
for _, d in ipairs(cmp.differ) do Line("- %s: %d %s%s", d.part, d.n, d.n == 1 and "difference" or "differences", d.units and (" (" .. table.concat(d.units, ", ") .. (d.n > #d.units and ", ..." or "") .. ")") or "") end
if not sameChoices and #cmp.differ == 0 then Line("- the choices' names or descriptions (nothing that changes what an install resolves to)") end
Line("")
Line("Files written: %s.", table.concat(order, ", "))
if #droppedCopies > 0 or #keptCopies > 0 then
    Line("")
    Line("Copies of shared modules in a layout's own part (`LD.DropSharedCopies`): a module the shared base holds, written again in a layout, is left out")
    Line("when the two differ only in how their numbers were written (two decimals, or 15 digits), so a later change to the base still reaches that layout.")
    Line("A setting a wizard choice always writes (friendly plates' showFriendlyPlayers) is not compared, as the picked option replaces it. A module that differs in any other value stays in the layout.")
    if #droppedCopies > 0 then Line("- left out (the base's module applies): %s", table.concat(droppedCopies, ", ")) end
    if #keptCopies > 0 then Line("- kept (it differs): %s", table.concat(keptCopies, ", ")) end
end
if layerNote then Line("The layers came from the published package; `docs/layouts/capture-*.md` still describe the last profile recapture.") end
Line("")
Line("## The TwichUI presets it holds")
Line("")
for _, l in ipairs(OptionLines(pkg.choices)) do Line("%s", l) end
Line("")
Line("## Left out (not part of what is bundled)")
Line("")
Line("The package's own words and labels stay with the publication: its title (`%s`), made, source, release notes and the author's", tostring(pkg.title))
Line("label. The bundled package keeps the title and the developer flag Classic.lua gives it (`dev = true` until it is checked on WoW: Forever),")
Line("and declares the lowest package format its choices need. None of these changes what an install resolves to.")
Line("")
Line("## Round trip")
Line("")
Line("After writing, `tools/check_bundled_layout.lua --published` loads the bundled package from these files in a fresh process, unpacks the")
Line("published entry again (with the same copies left out) and requires `Pub.Compare` to find them the same, the choices to be identical byte for byte (labels and")
Line("descriptions included), and the revision to be the published one. A failure puts every file back.")
Put(REPORT, table.concat(lines, "\n") .. "\n")

---------------------------------------------------------------------------
-- 4. Writing (only what changes), then the round trip in a fresh process; any failure puts every file back
---------------------------------------------------------------------------
local before, changed = {}, {}
for _, path in ipairs(order) do
    before[path] = LD.ReadText(REPO .. path)
    if before[path] ~= files[path] then changed[#changed + 1] = path end
end
if args["dry-run"] then
    realPrint("Would import " .. PE.Describe(entry) .. " and write: " .. (#changed > 0 and table.concat(changed, ", ") or "nothing"))
    os.exit(0)
end
local function PutBack()
    for _, path in ipairs(changed) do
        if before[path] then
            local f = io.open(REPO .. path, "wb")
            if f then f:write(before[path]) f:close() end
        else os.remove(REPO .. path) end
    end
end
local okWrite, err = pcall(function()
    for _, path in ipairs(changed) do
        local tmp = REPO .. path .. ".import-tmp"
        local f = assert(io.open(tmp, "wb"))
        assert(f:write(files[path]))
        f:close()
        assert(os.rename(tmp, REPO .. path))
    end
end)
if not okWrite then
    PutBack()
    for _, path in ipairs(changed) do os.remove(REPO .. path .. ".import-tmp") end
    io.stderr:write("Not imported: writing failed (" .. tostring(err) .. "). Every file is back as it was.\n")
    os.exit(1)
end
local check = ("cd %q && lua5.1 tools/check_bundled_layout.lua --published %s %q --published-revision %d --published-hash %q"):format(
    REPO, args.text and "--text" or "--sv", args.text or args.sv, entry.revision, entry.hash)
local rc = os.execute(check)
if rc ~= 0 and rc ~= true then
    PutBack()
    io.stderr:write("Not imported: the bundled package built from the new files doesn't match the published one (the check above says how). Every file is back as it was.\n")
    os.exit(1)
end
realPrint(("Imported %s. Wrote %s. Report: %s."):format(PE.Describe(entry), table.concat(changed, ", "), REPORT))
