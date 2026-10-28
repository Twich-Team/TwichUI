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
-- Prints one line per problem and exits 1 when there is any; prints "ok" and exits 0 otherwise. Writes nothing.

ROOT = "!!!TwichUI/"
REPO = "./"
TESTS = "tests/"
require("bit")

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

if #problems > 0 then
    for _, l in ipairs(problems) do io.stderr:write("  " .. l .. "\n") end
    os.exit(1)
end
realPrint(("ok: package %s revision %d, format %d; %d media references, all portable"):format(pkg.id, pkg.revision, pkg.format, #Pub.Refs(pkg)))
