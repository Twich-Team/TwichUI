-- TwichUI Fishing in the settings window (TwichUI_Settings/pages/Fishing.lua; !!!TwichUI/FishingLauncher.lua's helpers).
-- The page is described (Home, the page list, search) without loading TwichUI Fishing; visiting it loads it (never in
-- combat); until then every control is greyed out and says why; saved preferences show; changes go through Fishing's own
-- validation into its saved preferences and apply at once; a missing addon is explained; the key binding status and the
-- game's key bindings; preview and recovery from the page. Settings mock and the real TwichUI_Fishing files: proves the
-- wiring, not the window's drawing.
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY = "CLICK TwichUIFishingButton:LeftButton"

local function Client(o)
  o = o or {}
  local combat = false
  local c, S = SettingsClient({ beforeInit = function(c)
    local chunk = assert(loadfile(ROOT .. "FishingLauncher.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
    c.InCombatLockdown = function() return combat end
    c.GetBindingKey = function(action) if action == KEY and o.bound ~= false then return "F" end end
    c.TwichUIFishingDB = o.db
    -- the game's Key Bindings, where the client has them
    c.Settings.KEYBINDINGS_CATEGORY_ID = 8
    c.Settings.OpenToCategory = function(id) c.openedBindings = id end
  end })
  c.loads = 0
  local function LoadFishing()
    for line in io.lines(ROOT .. "../TwichUI_Fishing/TwichUI_Fishing.toc") do
      line = line:gsub("\r", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then
        local chunk = assert(loadfile(ROOT .. "../TwichUI_Fishing/" .. line:gsub("\\", "/")))
        setfenv(chunk, c); chunk("TwichUI_Fishing", {})
      end
    end
    c.LOADED.TwichUI_Fishing = true
    c.FireEvent("ADDON_LOADED", "TwichUI_Fishing")
  end
  local base = c.C_AddOns.LoadAddOn
  c.C_AddOns.LoadAddOn = function(name)
    if name ~= "TwichUI_Fishing" then return base(name) end
    assert(not combat, "never loaded in combat")
    if o.missing then return false, "MISSING" end
    c.loads = c.loads + 1
    if not c.LOADED.TwichUI_Fishing then LoadFishing() end
    return true
  end
  c.closed = 0
  c.TwichUI.SettingsUI.Close = function() c.closed = c.closed + 1 end
  c.Fight = function() combat = true; c.FireEvent("PLAYER_REGEN_DISABLED") end
  c.Peace = function() combat = false; c.FireEvent("PLAYER_REGEN_ENABLED") end
  return c, S
end

-- Everything the window reads from a row when it draws one (Window.lua): an error here is an error on screen.
local function DrawAll(page, label)
  local n = 0
  for _, row in ipairs(page.rows) do
    local function Call(what, fn, ...)
      if type(fn) ~= "function" then return end
      local ok, err = pcall(fn, ...)
      if not ok then error(label .. ": " .. tostring(row:GetName()) .. " " .. what .. ": " .. tostring(err), 0) end
    end
    Call("name", row.GetName, row)
    Call("tooltip", row.GetTooltip, row)
    Call("enabled", row.Enabled, row)
    Call("shown", row.Shown, row)
    Call("reason", row.DisabledReason, row)
    Call("button text", row.data.buttonText)
    Call("value", row.value)
    Call("detail", row.detail)
    Call("tone", row.tone)
    Call("note", row.note)
    Call("choices", row.choices)
    if row.setting then Call("setting", row.setting.GetValue, row.setting) end
    n = n + 1
  end
  return n
end

local function Row(page, name)
  for _, r in ipairs(page.rows) do if r:GetName() == name then return r end end
end

---------------------------------------------------------------------------
-- 1. Found without loading anything: the page list, Home, search, its icon
---------------------------------------------------------------------------
do
  local c, S = Client()
  local K, R = S.K, c.TwichUI
  local page = K.pages.fishing
  Check(page and page.group == "everyday" and page.def.icon == "fishing", "Fishing is a page in Everyday, with its own icon")
  local listed = false
  for _, p in ipairs(K.SidebarOrder()) do if p.key == "fishing" then listed = true end end
  Check(listed, "it is in the page list, and so on Home's Explore features")
  Check(page.def.overview and page.def.overview.status() == "Not loaded yet", "Home says it hasn't loaded")
  local found = {}
  for _, q in ipairs({ "fishing", "lure", "ellesmereui", "fishing mode", "cast bar" }) do
    local res = R.SettingsSearch.Run(q)
    found[q] = false
    for _, r in ipairs(res) do if r.entry.page == "fishing" or (r.entry.pageKey == "fishing") or tostring(r.entry.key or ""):find("fishing") then found[q] = true end end
  end
  for q, ok in pairs(found) do Check(ok, "search finds Fishing for \"" .. q .. "\"") end
  Check(R.Icons.Get("fishing") and R.Icons.Get("fishing").source == "fishing", "its icon is registered")
  Check(not c.LOADED.TwichUI_Fishing and c.loads == 0, "describing and searching never load it")
  -- greyed out, with the reason
  local mode = Row(page, "Presentation")
  Check(mode and not mode:Enabled() and mode:DisabledReason():find("loading", 1, true), "controls are greyed out until it loads, and say why")
  Check(S.variables.TWICHUI_fishingMode:GetValue() == "immersive", "and show the value it would have")
end

---------------------------------------------------------------------------
-- 2. Visiting the page loads it; saved preferences show; changes apply through Fishing's validation
---------------------------------------------------------------------------
do
  local c, S = Client({ db = { schema = 1, config = { present = { mode = "compact" }, castbar = { scale = 1.2 }, camera = { offset = -1 } }, chars = {} } })
  local K, R = S.K, c.TwichUI
  local page = K.pages.fishing
  page.def.onShow()
  Check(c.LOADED.TwichUI_Fishing and c.loads == 1, "going to the page loads TwichUI Fishing")
  local F = R.Fishing
  Check(Row(page, "Presentation"):Enabled(), "the controls are live")
  local V = S.variables
  Check(V.TWICHUI_fishingMode:GetValue() == "compact" and V.TWICHUI_fishingCastScale:GetValue() == 120 and V.TWICHUI_fishingOffset:GetValue() == "-1",
    "saved preferences show as they are")
  V.TWICHUI_fishingMode:SetValue("immersive")
  V.TWICHUI_fishingCastScale:SetValue(135)
  V.TWICHUI_fishingOffset:SetValue("0.5")
  V.TWICHUI_fishingFadeAlpha:SetValue(20)
  V.TWICHUI_fishingEllesmere:SetValue(false)
  V.TWICHUI_fishingContainers:SetValue("auto")
  V.TWICHUI_fishingValueArea:SetValue(false)
  local St = F.Store
  Check(St.Get("present.mode") == "immersive" and math.abs(St.Get("castbar.scale") - 1.35) < 1e-9 and St.Get("camera.offset") == 0.5
    and math.abs(St.Get("fade.alpha") - 0.2) < 1e-9 and St.Get("fade.ellesmere") == false and St.Get("containers.mode") == "auto"
    and St.Get("list.value") == "hide", "each change reaches Fishing's own preferences")
  Check(c.TwichUIFishingDB.config.castbar.scale == St.Get("castbar.scale"), "and is saved in its saved variable")
  -- refused values leave things as they were
  V.TWICHUI_fishingCastScale:SetValue(300)
  V.TWICHUI_fishingZoom:SetValue(99)
  Check(math.abs(St.Get("castbar.scale") - 1.35) < 1e-9 and St.Get("camera.zoom") == 7, "values Fishing refuses are not saved")
  -- the poles and lures offered
  local pole = Row(page, "Preferred fishing pole")
  Check(pole and pole.choices()[1].value == "0", "the pole choice starts with \"the best in my bags\"")
  V.TWICHUI_fishingPole:SetValue("6256")
  Check(St.Get("gear.pole") == 6256, "a pole chosen by its id")
  V.TWICHUI_fishingPole:SetValue("0")
  Check(St.Get("gear.pole") == false, "and back to the best in the bags")
  -- turning it off and on through Fishing's own switch
  V.TWICHUI_fishingEnabled:SetValue(false)
  Check(St.Get("enabled") == false and page.def.overview.status() == "Off", "turned off from the page")
  V.TWICHUI_fishingEnabled:SetValue(true)
  -- the status, the keys, the game's key bindings
  Check(page.def.overview.status() == "On", "Home's status: " .. page.def.overview.status())
  Check(Row(page, "Your Fishing key").value() == "F", "the Fishing key shows")
  Row(page, "Key bindings").click()
  Check(c.openedBindings == 8 and c.closed >= 1, "Open Key Bindings opens the game's own, and closes the settings window")
end

---------------------------------------------------------------------------
-- 3. Preview, Fishing Mode and recovery from the page; Move and Reset
---------------------------------------------------------------------------
do
  local c, S = Client()
  local K, R = S.K, c.TwichUI
  local page = K.pages.fishing
  page.def.onShow()
  local F = R.Fishing
  local preview = Row(page, "Try Fishing Mode")
  Check(preview.data.buttonText() == "Preview Fishing Mode", "the preview button")
  preview.click()
  Check(F.Present.Previewing() and c.closed >= 1, "Preview starts it and closes the settings window")
  Check(F.Session.Current() == nil, "nothing is cast and no session begins")
  RunLongTimers(20); FlushTimers()
  Check(not F.Present.Previewing() and c.opened == "fishing", "when it ends by itself the settings come back to Fishing")
  local mode = Row(page, "Fishing Mode")
  mode.click()
  Check(F.Present.On(), "Start Fishing Mode")
  Check(mode.data.buttonText() == "Leave Fishing Mode", "the button now leaves it")
  Row(page, "Put things back").click()
  Check(not F.Present.On(), "Put things back leaves Fishing Mode and puts everything back")
  F.Store.Set("castbar.x", 120)
  local reset
  reset = Row(page, "Starting places")
  reset.click()
  Check(F.Store.Get("castbar.x") == 0, "Reset positions")
end

---------------------------------------------------------------------------
-- 4. Combat, a missing addon, held data
---------------------------------------------------------------------------
do
  local c, S = Client()
  local page = S.K.pages.fishing
  c.Fight()
  page.def.onShow()
  Check(not c.LOADED.TwichUI_Fishing and page.def.overview.status() == "Not loaded yet", "in combat the page doesn't load it")
  Check(Row(page, "Presentation"):DisabledReason():find("combat", 1, true), "and says it loads when combat ends")
  c.Peace()
  page.def.onShow()
  Check(c.LOADED.TwichUI_Fishing, "after combat it loads")
end
do
  local c, S = Client({ missing = true })
  local page = S.K.pages.fishing
  page.def.onShow()
  Check(page.def.overview.status() == "Couldn't load", "a missing folder: Home says it couldn't load")
  Check(Row(page, "Presentation"):DisabledReason():find("TwichUI_Fishing", 1, true), "and the page says why: " .. Row(page, "Presentation"):DisabledReason())
end
do
  local c, S = Client({ db = { schema = 99, chars = {} } })
  local page = S.K.pages.fishing
  page.def.onShow()
  Check(page.def.overview.status():find("held", 1, true), "held data is shown")
  Check(not Row(page, "Presentation"):Enabled() and Row(page, "Presentation"):DisabledReason():find("newer TwichUI", 1, true), "and its settings can't be changed")
end
do
  local c, S = Client({ bound = false })
  local page = S.K.pages.fishing
  page.def.onShow()
  Check(Row(page, "Your Fishing key").value() == "Not bound" and Row(page, "Your Fishing key").tone() == "warn", "no key bound: it says so, and how to bind one")
end

---------------------------------------------------------------------------
-- 5. Every row draws in every state: not loaded, loaded, a TwichUI Fishing older than the settings window (a partial
--    update), and an older core launcher
---------------------------------------------------------------------------
do
  local c, S = Client()
  local page = S.K.pages.fishing
  local ok, err = pcall(DrawAll, page, "not loaded")
  Check(ok, tostring(err))
  page.def.onShow()
  ok, err = pcall(DrawAll, page, "loaded")
  Check(ok, tostring(err))
  -- an older TwichUI_Fishing: no settings interface version, no preview, no EllesmereUI module
  local F = c.TwichUI.Fishing
  F.Present.SETTINGS_API, F.Present.Previewing, F.Present.Preview, F.Ellesmere = nil, nil, nil, nil
  ok, err = pcall(DrawAll, page, "older TwichUI Fishing")
  Check(ok, tostring(err))
  Check(page.def.overview.status() == "Needs updating", "an older TwichUI Fishing: Home says it needs updating")
  Check(not Row(page, "Presentation"):Enabled() and Row(page, "Presentation"):DisabledReason():find("same TwichUI build", 1, true),
    "and every control is greyed out with what to do")
  Row(page, "Fishing Mode").click(); Row(page, "Try Fishing Mode").click(); Row(page, "Put things back").click()
  Check(true, "its buttons do nothing rather than fail")
end
do
  local c, S = Client()
  local L = c.TwichUI.FishingLauncher
  L.KeyText, L.State, L.OpenBindings = nil, nil, nil   -- an older core
  local page = S.K.pages.fishing
  local ok, err = pcall(DrawAll, page, "older core")
  Check(ok, tostring(err))
  page.def.onShow()
  ok, err = pcall(DrawAll, page, "older core, loaded")
  Check(ok, tostring(err))
  ok, err = pcall(Row(page, "Key bindings").click)
  Check(ok, "Open Key Bindings with an older core: " .. tostring(err))
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_settings")
