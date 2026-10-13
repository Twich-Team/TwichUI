-- The settings window ships as an addon of its own (TwichUI_Settings), loaded on demand. Its .toc and the
-- packaging must stay in step with TwichUI's: same interface and version, load on demand, needing TwichUI,
-- no saved variables of its own, every file listed once, and the release zip putting it beside !!!TwichUI.
-- (What the packager actually builds is checked by unzipping a release: RELEASING.md.)

local function Read(path)
  local f = assert(io.open(ROOT .. path, "r"), path)
  local s = f:read("*a")
  f:close()
  return s
end
local function Meta(toc, field) return toc:match("## " .. field .. ":%s*([^\r\n]+)") end

local main, settings = Read("!!!TwichUI.toc"), Read("TwichUI_Settings/TwichUI_Settings.toc")
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
local p = io.popen('cd "' .. ROOT .. 'TwichUI_Settings" && find . -name "*.lua" | sed "s|^./||"')
local files = 0
for path in p:lines() do
  files = files + 1
  assert(listed[path], path .. " is in TwichUI_Settings.toc")
end
p:close()
assert(files > 0 and files == (function() local n = 0 for _ in pairs(listed) do n = n + 1 end return n end)(), "and nothing listed is missing")
assert(not main:find("TwichUI_Settings\\", 1, true) and not main:find("\nsettings\\", 1, true), "TwichUI's .toc loads none of it")
assert(main:find("\nSwitches.lua", 1, true) and main:find("\nSettingsLauncher.lua", 1, true), "the core keeps the switches and the launcher")

-- the release zip puts it beside !!!TwichUI, and nothing ignores it
local pkg = Read(".pkgmeta")
assert(pkg:find('"!!!TwichUI/TwichUI_Settings": TwichUI_Settings', 1, true), ".pkgmeta moves it to a folder of its own")
assert(not pkg:find("%- TwichUI_Settings"), "and doesn't leave it out")
local deploy = Read("tools/deploy.sh")
assert(deploy:find("TwichUI_Settings", 1, true), "the deploy script copies it too")
print("PASSED")
