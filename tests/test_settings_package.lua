-- The settings window ships as an addon of its own (TwichUI_Settings), loaded on demand. Its .toc and the
-- packaging must stay in step with TwichUI's: same interface and version, load on demand, needing TwichUI,
-- no saved variables of its own, every file listed once, and the release zip putting it beside !!!TwichUI.
-- (What the packager actually builds is checked by unzipping a release: RELEASING.md.)
-- Layout: ROOT is the core addon's folder (!!!TwichUI/), TwichUI_Settings/ its sibling, REPO the repository root.

local function Read(path, base)
  local f = assert(io.open((base or ROOT) .. path, "r"), path)
  local s = f:read("*a")
  f:close()
  return s
end
local function Meta(toc, field) return toc:match("## " .. field .. ":%s*([^\r\n]+)") end

local main, settings = Read("!!!TwichUI.toc"), Read("../TwichUI_Settings/TwichUI_Settings.toc")
assert(Meta(settings, "Interface") == Meta(main, "Interface"), "the same interface version")
assert(Meta(settings, "Version") == Meta(main, "Version"), "the same TwichUI version (update both when releasing)")
assert(Meta(settings, "LoadOnDemand") == "1", "loaded on demand")
assert(Meta(settings, "RequiredDeps") == "!!!TwichUI", "needs TwichUI")
assert(not Meta(settings, "SavedVariables") and not Meta(settings, "SavedVariablesPerCharacter"), "keeps nothing of its own")

-- every Lua file of the settings window is listed once in its .toc, and none in TwichUI's
local listed = {}
for line in settings:gmatch("[^\r\n]+") do
  if not line:find("^#") and line:find("%.lua$") then
    local path = line:gsub("\\", "/")
    assert(not listed[path], path .. " is listed once")
    listed[path] = true
  end
end
local p = io.popen('cd "' .. ROOT .. '../TwichUI_Settings" && find . -name "*.lua" | sed "s|^./||"')
local files = 0
for path in p:lines() do
  files = files + 1
  assert(listed[path], path .. " is in TwichUI_Settings.toc")
end
p:close()
assert(files > 0 and files == (function() local n = 0 for _ in pairs(listed) do n = n + 1 end return n end)(), "and nothing listed is missing")
assert(not main:find("TwichUI_Settings\\", 1, true) and not main:find("\nsettings\\", 1, true), "TwichUI's .toc loads none of it")
assert(main:find("\nSwitches.lua", 1, true) and main:find("\nSettingsLauncher.lua", 1, true), "the core keeps the switches and the launcher")

-- the two addons are sibling folders of the repository, and nothing else sits in the core folder's way
assert(not io.open(ROOT .. "TwichUI_Settings", "r"), "TwichUI_Settings is beside the core folder, not inside it")
assert(not io.open(REPO .. "TwitchUI_Settings", "r"), "the misspelled TwitchUI_Settings folder is gone")

-- the release zip puts both beside each other, and nothing ignores either
local pkg = Read(".pkgmeta", REPO)
-- (keys are unquoted on purpose: the packager keeps a key's quotes as part of the key, and the move then never matches)
assert(pkg:find('\n  !!!TwichUI/!!!TwichUI: "!!!TwichUI"', 1, true), ".pkgmeta moves the core addon up to the package folder")
assert(pkg:find('\n  !!!TwichUI/TwichUI_Settings: TwichUI_Settings', 1, true), ".pkgmeta moves it to a folder of its own")
assert(not pkg:find("%- TwichUI_Settings") and not pkg:find("%- !!!TwichUI"), "and doesn't leave either out")
assert(not pkg:find("TwitchUI", 1, true), "no misspelling of the name")
-- tools/deploy.sh is local only (git ignores it), so it is checked where it exists
local deploy = io.open(REPO .. "tools/deploy.sh", "r")
if deploy then
  local text = deploy:read("*a"); deploy:close()
  assert(text:find("TwichUI_Settings", 1, true), "the deploy script copies it too")
  assert(not text:find("TwitchUI", 1, true), "and spells it right")
end
print("PASSED")
