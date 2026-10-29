-- TwichUI bundled layout check: what tools/update_bundled_layout.sh runs after a capture, before (and apart from) the tests.
-- Runs outside the game with plain Lua 5.1 (+ luabitop), from the repository root:
--
--   lua5.1 tools/check_bundled_layout.lua
--
-- Loads TwichUI and the layouts addon offline (as the tests do, with the package data as it is in the repository) and checks
-- the package TwichUI ships the way a published one is checked where it matters to players:
--   * it is a valid package (LY.Validate), and both layouts resolve on the author's canvas;
--   * portable media (RH-1): every file it names is TwichUI's own (and in the list modules/Media.lua keeps), EllesmereUI's or
--     the game's. A path into another addon's folder (an author's private font folder) or outside the game is a failure, not a
--     warning: players don't have that file;
--   * it carries no developer export string and nothing a published package couldn't (the strict string rules).
-- With --published (--sv <copy of !!!TwichUI.lua> | --text <export file>) [--published-revision N] [--published-hash H], it also checks
-- the round trip of an import (tools/import_published_layout.lua): the published entry is unpacked and checked again, and the
-- bundled package must resolve exactly as it does (Pub.Compare), hold its choices byte for byte (labels and descriptions too) and
-- have its revision. Only the documented metadata may differ (title, made, source, the developer flag, the declared format).
-- Prints one line per problem and exits 1 when there is any; prints "ok" and exits 0 otherwise. Writes nothing.

ROOT = "!!!TwichUI/"
REPO = "./"
TESTS = "tests/"
require("bit")

local args = {}
do
    local i = 1
    while i <= #arg do
        local k = arg[i]:match("^%-%-(.+)$")
        if k == "published" then args.published = arg[i + 1] args.source = arg[i + 2] i = i + 3
        elseif k then args[k] = arg[i + 1] i = i + 2
        else io.stderr:write("unexpected argument: " .. arg[i] .. "\n") os.exit(2) end
    end
end

local realPrint = print
print = function() end   -- the harness's client chatter
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c = SettingsClient({ name = "Check", beforeInit = function(c) c.print = function() end end })
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
local pkg = LY.ADVENTURE_PACKAGE
local problems = {}
local function Problem(fmt, ...) problems[#problems + 1] = fmt:format(...) end

local ok, P = LY.Validate(pkg)
if not ok then
    for _, p in ipairs(P) do Problem("invalid package: %s at %s", p.code, tostring(p.where)) end
end

for _, r in ipairs(Pub.Refs(pkg)) do
    if r.source == "unsafe" then Problem("media outside the game's folders: %s", r.path)
    elseif r.source == "foreign" then
        local sub = Pub.Substitute(r.path)
        Problem("media in another addon's folder (players don't have it): %s%s", r.path,
            sub and (" (TwichUI ships a file of that name: " .. sub .. ")") or "")
    elseif r.source == "twichui" and Pub.BundledKind(r.path) and not Pub.Bundled(r.path) then
        Problem("TwichUI media that TwichUI doesn't ship: %s", r.path)
    end
end

-- what a published package may not hold, apart from the developer flag the bundled package keeps until Forever checks
local strict = { pkg = {} }
for k, v in pairs(pkg) do if k ~= "dev" then strict.pkg[k] = v end end
local _, sp = Pub.Strict(strict.pkg)
for _, p in ipairs(sp or {}) do
    if p.code ~= "media-foreign" and p.code ~= "media-unsafe" then Problem("not publishable as it is: %s at %s", p.code, tostring(p.where)) end
end

if ok then
    local canvas = pkg.geometry.canvas
    for _, v in ipairs({ LY.CLASSIC_VARIANT, LY.COMPACT_VARIANT }) do
        local geo, why = LY.Geometry.Resolve(pkg.geometry, { w = canvas.w, h = canvas.h }, { variant = v })
        if not geo then Problem("%s doesn't resolve on the author's canvas: %s", v, tostring(why))
        elseif not geo.fits then Problem("%s doesn't fit the author's own canvas", v) end
    end
end

-- a note, not a failure: the accent choice's default option holds its own colour (ChoicesData.lua), so a profile recapture that
-- changes the look's accent doesn't change what "Aged gold" applies
local notes = {}
if ok then
    for _, ch in ipairs(pkg.choices or {}) do
        if ch.id == "accent" then
            for _, o in ipairs(ch.options) do
                local a = o.id == ch.default and o.ellesmereui and o.ellesmereui.root and o.ellesmereui.root.euiAccent
                local b = pkg.layers.base.ellesmereui and pkg.layers.base.ellesmereui.root and pkg.layers.base.ellesmereui.root.euiAccent
                if a and b and LY.Canon(a) ~= LY.Canon(b) then
                    notes[#notes + 1] = "note: the look's accent (the base) differs from the accent choice's default option, which is what an install applies; change that option in game and publish if the new accent is meant"
                end
            end
        end
    end
end

-- the round trip of an import: the bundled package is the published one, apart from the documented metadata
local matched
if args.published then
    dofile(REPO .. "tools/layout_data.lua")
    dofile(REPO .. "tools/published_entry.lua")
    local entry, why
    if args.published == "--text" then
        entry, why = PE.Parse(LD.ReadText(args.source) or "")
    elseif args.published == "--sv" then
        local entries
        entries, why = PE.FromSaved(args.source)
        if entries then entry, why = PE.Pick(entries, tonumber(args["published-revision"] or ""), args["published-hash"]) end
    else
        why = "--published takes --sv FILE or --text FILE"
    end
    if entry and args["published-revision"] and entry.revision ~= tonumber(args["published-revision"]) then entry, why = nil, "the entry isn't the revision named" end
    if entry and args["published-hash"] and entry.hash ~= args["published-hash"] then entry, why = nil, "the entry isn't the fingerprint named" end
    local env = entry and select(1, PE.Open(c, entry))
    if entry and not env then why = select(2, PE.Open(c, entry)) end
    if not env then Problem("the published package can't be read again: %s", tostring(why))
    else
        local pub = env.package
        local cmp = Pub.Compare(pkg, pub)
        if not (cmp and cmp.same) then
            for _, d in ipairs(cmp and cmp.differ or {}) do Problem("round trip: %s differs from the published package (%d)", d.part, d.n) end
            if not cmp then Problem("round trip: the two packages can't be compared") end
        end
        if LY.Canon(pkg.choices or false) ~= LY.Canon(pub.choices or false) then Problem("round trip: the choices aren't the published ones byte for byte") end
        if pkg.revision ~= pub.revision then Problem("round trip: the bundled revision is %d, the published one %d", pkg.revision, pub.revision) end
        if pkg.id ~= pub.id then Problem("round trip: the bundled package is %s, the published one %s", tostring(pkg.id), tostring(pub.id)) end
        matched = ("round trip: the bundled package resolves exactly as %s (%s)"):format(PE.Describe(entry), Pub.Contents(pub).identity)
    end
end

if #problems > 0 then
    for _, l in ipairs(problems) do io.stderr:write("  " .. l .. "\n") end
    os.exit(1)
end
for _, l in ipairs(notes) do realPrint(l) end
if matched then realPrint(matched) end
realPrint(("ok: package %s revision %d, format %d; %d media references, all portable"):format(pkg.id, pkg.revision, pkg.format, #Pub.Refs(pkg)))
