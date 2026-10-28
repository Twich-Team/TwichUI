dofile(TESTS .. "harness.lua")
dofile(TESTS .. "layouts_mock.lua")
-- The bundled-layout tools (RH-1; docs/layouts/updating-the-bundled-layout.md): tools/layout_capture.lua's comparison with the
-- previous capture (a setting the author put back to the default is a decision: reset, release or keep, never assumed), and
-- tools/update_bundled_layout.sh's two kinds of stop (a failed capture puts every file back; a result that fails a check is
-- kept for a look, with a copy of the files from before, and exits 1 as NOT READY) and its success. The script runs in a
-- temporary copy of the repository, on saved files written here from the package's own data: nothing in the working tree
-- and no game folder is touched.

local failures = 0
local function Check(cond, msg)
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function Sh(cmd)
  local p = io.popen(cmd .. " 2>&1; echo \"__rc=$?\"")
  local out = p:read("*a")
  p:close()
  local rc = tonumber(out:match("__rc=(%d+)%s*$"))
  return rc, out
end
local function Read(path) local f = io.open(path, "rb") if not f then return nil end local s = f:read("*a") f:close() return s end
local function Write(path, s) local f = assert(io.open(path, "wb")) f:write(s) f:close() end

local _, tmp = Sh("mktemp -d")
local TMP = tmp:match("^(%S+)")
assert(TMP and TMP:find("^/"), "a temporary folder")
local ABS = select(2, Sh("cd " .. REPO .. " && pwd")):match("^(%S+)")

-- Saved files from the package's own data: the author's two EllesmereUI profiles and the TwichUI profile
local c = LM.Boot("Fixture", nil, {})
assert(c.TwichUI.LayoutsLauncher.Load())
local LY = c.TwichUI.Layouts
local TC, TA = c.TwichUI.TwichConfig, LY.TwichUIAdapter
local C, K = LY.CLASSIC_CAPTURE, LY.COMPACT_CAPTURE
local function Copy(v) return LM.Copy(v) end
local function EuiProfile(modules, layout)
  local p = { addons = {}, unlockLayout = Copy(layout) }
  for k, v in pairs(C.ellesmereui.root) do p[k] = Copy(v) end
  for m, b in pairs(C.ellesmereui.modules) do p.addons[m] = Copy(b) end
  for m, b in pairs(modules or {}) do p.addons[m] = Copy(b) end
  return p
end
local function TwichDB(edit)
  local db = { profileState = { live = "Default" } }
  for g, slots in pairs(C.twichui.groups) do
    for sl, vals in pairs(slots) do
      for k, v in pairs(vals) do
        local f = TC.Group(g).index[sl][k]
        local t = db
        for _, key in ipairs(f.at) do t[key] = t[key] or {} t = t[key] end
        t[f.key] = Copy(v)
      end
    end
  end
  for id, v in pairs(C.twichui.places) do
    local path = TA.PLACES[id].path
    local t = db
    for i = 1, #path - 1 do t[path[i]] = t[path[i]] or {} t = t[path[i]] end
    if TA.PLACES[id].kind == "point" then
      -- a point place shares its table with the feature's settings (healer/Display.lua): merged, as the feature stores it
      t[path[#path]] = t[path[#path]] or {}
      for k, x in pairs(v) do t[path[#path]][k] = x end
    else
      t[path[#path]] = Copy(v)
    end
  end
  if edit then edit(db) end
  return db
end
-- a plain Lua data writer (what the strict reader reads: names = tables, strings, numbers, booleans)
local function Emit(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = type(k) == "number" and ("[" .. ("%.17g"):format(k) .. "]=") or ("[" .. ("%q"):format(k) .. "]=")
      Emit(v[k], out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t == "string" then out[#out + 1] = ("%q"):format(v)
  elseif t == "number" then out[#out + 1] = ("%.17g"):format(v)
  else out[#out + 1] = tostring(v) end
end
local function SavedFile(path, name, value)
  local out = { name, " = " }
  Emit(value, out)
  Write(path, table.concat(out) .. "\n")
end
local function Saved(dir, euiEdit, twEdit)
  Sh("mkdir -p " .. dir)
  local db = { profiles = {
    ["TwichUI - Classic Adventure"] = EuiProfile(nil, C.ellesmereui.layout),
    ["TwichUI - Minimal Adventure"] = EuiProfile(K.ellesmereui.modules, K.ellesmereui.layout or C.ellesmereui.layout) },
    activeProfile = "TwichUI - Classic Adventure", lastLoginVersion = "9.6.8", ppUIScale = 0.64 }
  for m in pairs(K.sameAs and K.sameAs.modules or {}) do
    db.profiles["TwichUI - Minimal Adventure"].addons[m] = Copy(C.ellesmereui.modules[m])
  end
  if euiEdit then euiEdit(db) end
  SavedFile(dir .. "/EllesmereUI.lua", "EllesmereUIDB", db)
  SavedFile(dir .. "/!!!TwichUI.lua", "TwichUIDB", TwichDB(twEdit))
end

local NAV = TC.Group("navigation").index.navigation.font
local NAV_U = "twichui:" .. table.concat(NAV.at, ".") .. "." .. NAV.key
local function DropNav(db)
  local t = db
  for _, k in ipairs(NAV.at) do t = t[k] end
  t[NAV.key] = nil   -- the author put the navigation font back to TwichUI's default
end

---------------------------------------------------------------------------
-- 1. The capture tool: a setting the previous capture named and this profile doesn't is asked about, never assumed
---------------------------------------------------------------------------
Saved(TMP .. "/sv1")
Saved(TMP .. "/sv2", nil, DropNav)
local function Capture(sv, out, extra)
  return Sh(("cd %q && lua5.1 tools/layout_capture.lua --eui %q --twichui %q --eui-profile %q --twichui-profile Default --out %q --report %q --made 2026-10-28 %s")
    :format(ABS, sv .. "/EllesmereUI.lua", sv .. "/!!!TwichUI.lua", "TwichUI - Classic Adventure", out, out .. ".md", extra or ""))
end
local function Data(path)
  local chunk = assert(loadfile(path))
  local env = { TwichUI = { Layouts = {} } }
  setfenv(chunk, env)
  chunk()
  return env.TwichUI.Layouts.CLASSIC_CAPTURE
end
local rc1, out1 = Capture(TMP .. "/sv1", TMP .. "/v1.lua", "--previous none")
Check(rc1 == 0, "1. the author's profile captures: " .. out1:sub(1, 300))
local v1 = rc1 == 0 and Data(TMP .. "/v1.lua")
Check(v1 and v1.twichui.groups.navigation.navigation.font ~= nil and v1.twichui.reset == nil, "   the navigation font is in it, nothing reset")

local rc2, out2 = Capture(TMP .. "/sv2", TMP .. "/v2.lua", "--previous " .. TMP .. "/v1.lua")
Check(rc2 == 3 and out2:find("no longer has", 1, true) and out2:find("--returned reset", 1, true) and Read(TMP .. "/v2.lua") == nil,
  "   put back to the default: listed, nothing written, exit 3 (" .. tostring(rc2) .. ")")

local rc3 = Capture(TMP .. "/sv2", TMP .. "/v3.lua", "--previous " .. TMP .. "/v1.lua --returned reset")
local v3 = rc3 == 0 and Data(TMP .. "/v3.lua")
Check(v3 and v3.twichui.reset and v3.twichui.reset[1] == NAV_U and v3.twichui.groups.navigation.navigation.font == nil,
  "   --returned reset: in the reset list, no value")
Check((Read(TMP .. "/v3.lua.md") or ""):find("TwichUI's default (reset)", 1, true), "   and the report says what players get")

local rc4 = Capture(TMP .. "/sv2", TMP .. "/v4.lua", "--previous " .. TMP .. "/v1.lua --returned keep")
local v4 = rc4 == 0 and Data(TMP .. "/v4.lua")
Check(v4 and v4.twichui.groups.navigation.navigation.font == v1.twichui.groups.navigation.navigation.font and v4.twichui.reset == nil,
  "   --returned keep: the previous value stays in the package")

local rc5 = Capture(TMP .. "/sv2", TMP .. "/v5.lua", "--previous " .. TMP .. "/v1.lua --returned release")
local v5 = rc5 == 0 and Data(TMP .. "/v5.lua")
Check(v5 and v5.twichui.groups.navigation.navigation.font == nil and v5.twichui.reset == nil, "   --returned release: no longer named, nothing reset")

local rc6 = Capture(TMP .. "/sv2", TMP .. "/v6.lua", "--previous " .. TMP .. "/v3.lua")
local v6 = rc6 == 0 and Data(TMP .. "/v6.lua")
Check(v6 and v6.twichui.reset and v6.twichui.reset[1] == NAV_U, "   a reset from the previous capture stays while the setting is still at its default")

---------------------------------------------------------------------------
-- 2. The script, in a temporary copy of the repository
---------------------------------------------------------------------------
local W = TMP .. "/repo"
local rcCopy, copyOut = Sh(("mkdir -p %q && cd %q && tar --exclude='*.ogg' --exclude='*.tga' --exclude='*.blp' --exclude='*.png' -cf - '!!!TwichUI' TwichUI_Settings TwichUI_Layouts tools tests docs/layouts | (cd %q && tar -xf -)")
  :format(W, ABS, W))
assert(rcCopy == 0, "copied: " .. copyOut)
local FILES = { "TwichUI_Layouts/ClassicData.lua", "TwichUI_Layouts/CompactData.lua", "TwichUI_Layouts/Classic.lua",
  "docs/layouts/capture-classic-adventure.md", "docs/layouts/capture-compact-adventure.md" }
local function Snapshot()
  local t = {}
  for _, f in ipairs(FILES) do t[f] = Read(W .. "/" .. f) end
  return t
end
local function Same(a, b) for _, f in ipairs(FILES) do if a[f] ~= b[f] then return false, f end end return true end
local function Run(sv, extra)
  return Sh(("cd %q && TMPDIR=%q tools/update_bundled_layout.sh --sv %q --no-tests %s"):format(W, TMP, sv, extra or ""))
end
local before = Snapshot()

-- a capture that fails (a profile name that isn't there): every file put back, exit 1
local rcA, outA = Run(TMP .. "/sv1", "--classic-profile Nonexistent")
Check(rcA == 1 and outA:find("no EllesmereUI profile with that name", 1, true) and outA:find("Stopped while generating", 1, true)
  and Same(before, Snapshot()), "2. a failed capture: exit 1, every file as it was (" .. tostring(rcA) .. ")")

-- settings put back to the default and no decision: stopped, every file put back, told how to decide
local rcB, outB = Run(TMP .. "/sv2", "--no-bump")
Check(rcB == 1 and outB:find("no longer has", 1, true) and outB:find("--returned", 1, true) and Same(before, Snapshot()),
  "   a setting back at the default with no --returned: stopped, nothing changed")

-- a font players don't have: the result is kept for a look, NOT READY, exit 1, the files from before saved
Saved(TMP .. "/sv3", function(db)
  for _, name in ipairs({ "TwichUI - Classic Adventure", "TwichUI - Minimal Adventure" }) do
    db.profiles[name].addons.EllesmereUIUnitFrames.unitNameFontPath = [[Interface\AddOns\SomeoneElsesFonts\Private.ttf]]
  end
end)
local rcC, outC = Run(TMP .. "/sv3", "--no-bump --returned release")
local keptDir = outC:match("saved in (%S+)")
Check(rcC == 1 and outC:find("NOT READY", 1, true) and not outC:find("Done:", 1, true), "   a font players don't have: NOT READY, exit 1 (" .. tostring(rcC) .. ")")
Check(not Same(before, Snapshot()) and (Read(W .. "/TwichUI_Layouts/ClassicData.lua") or ""):find("SomeoneElsesFonts", 1, true),
  "   the new files are kept for a look")
Check(keptDir and Read(keptDir .. "/ClassicData.lua") == before["TwichUI_Layouts/ClassicData.lua"], "   and the files from before are saved where it says")
-- put back as the message says, then a clean run succeeds
for _, f in ipairs(FILES) do Write(W .. "/" .. f, before[f]) end
local rcD, outD = Run(TMP .. "/sv1", "--no-bump")
Check(rcD == 0 and outD:find("Done: generated, checked, not tested", 1, true), "   a clean run: Done (and says the tests didn't run) (" .. tostring(rcD) .. ")")
Check(outD:find("TwichUI - Classic Adventure", 1, true) and outD:find(TMP .. "/sv1", 1, true), "   it names the source: the saved files and the profiles")

Sh(("rm -rf %q"):format(TMP))
if failures > 0 then print(failures .. " check(s) FAILED") os.exit(1) end
print("OK")
