-- A client with TwichUI's features loaded and the settings window's pages described (TwichUI_Settings, loaded
-- as the game loads it on demand: after everything else, once the saved variables are in). No window is made:
-- R.SettingsUI.Open only records the page and setting asked for (c.opened, c.openedSetting), so tests read the
-- pages' descriptions, which is what search and the window both use. The settings objects behave like the
-- game's own did: SetValue writes only a value that differs, and the change callbacks run either way.
--
-- SettingsClient(opts) -> c, S
--   opts.name: the character ("Rich" when left out)
--   opts.beforeInit(c): runs after the features are loaded and before the saved variables "arrive"
--   opts.beforeDescribe(c): runs after the settings window's files are loaded and before the pages are described
--   S.pages: the pages in their order, each { key, name, parent (its name), kind ("page" or "hosted"), rows }
--   S.variables[name] = setting; S.list: settings in the order made; S.registered(): the AddOns entry's category
--   S.popups: how many times the reload question was asked; S.K: the settings kit

function SettingsClient(opts)
  opts = opts or {}
  local c = MakeClient(opts.name or "Rich", {"!!!TwichUI", "Attune", "TwichUI_Settings"})
  local S = { popups = 0 }
  local registered

  c.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { name = name, frame = frame, GetID = function() return 1 end } end,
    RegisterAddOnCategory = function(category) registered = category end,
  }
  function S.registered() return registered end

  c.UnitClass = function() return "Mage", "MAGE" end
  c.UnitLevel = function() return 30 end
  c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
  local function Obj()
    return setmetatable({}, { __index = function(t, k)
      if k == "twichBevel" or k == "twichBorders" then return nil end
      if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return Obj() end end
      return function() end
    end })
  end
  c.CreateFrame = function() return Obj() end
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function(name) if name == "TWICHUI_RELOAD" then S.popups = S.popups + 1 end end
  c.PlaySoundFile = function() return true end
  -- empty bags, for the features that look in them when they are turned on
  c.C_Spell = { GetSpellName = function() return nil end, GetSpellDescription = function() return nil end }
  c.C_Item = { GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end }
  c.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }

  local FILES = { "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
    "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/Media.lua",
    "modules/FriendLogin.lua", "modules/Borders.lua", "modules/FoodDrink.lua", "modules/FoodDrinkUnlock.lua",
    "modules/TrainingData.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua", "modules/MageConjure.lua",
    "chronicle/Style.lua", "Look.lua", "chronicle/Appearance.lua", "modules/NotifyLook.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua", "modules/RefreshmentsShares.lua",
    "modules/RefreshmentsTrade.lua", "modules/RefreshmentsBroker.lua", "modules/MageSell.lua", "modules/MageSellWindow.lua",
    "modules/RestedXPSkin.lua", "modules/RestedXPTimers.lua", "modules/SpeakStoneSkin.lua", "qol/QoL.lua", "qol/Summons.lua", "qol/Resurrect.lua", "qol/ReleasePvP.lua",
    "qol/Duels.lua", "qol/QuickKeybind.lua", "qol/EasyFishing.lua", "qol/GuideWaypoint.lua",
    "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Minimap.lua", "pins/Editor.lua", "pins/Window.lua",
    "pins/BrokerMenu.lua", "pins/Broker.lua",
    "diag/Diagnostics.lua", "diag/Window.lua" }
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if opts.beforeInit then opts.beforeInit(c) end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)

  -- The settings window's addon, as the game loads it on demand.
  local function LoadCompanion()
    for _, f in ipairs(SettingsFiles()) do
      local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("TwichUI_Settings", {})
    end
    c.LOADED.TwichUI_Settings = true
  end
  c.C_AddOns.LoadAddOn = function(name)
    if name ~= "TwichUI_Settings" then return false, "MISSING" end
    if not c.LOADED.TwichUI_Settings then LoadCompanion() end
    return true
  end
  LoadCompanion()
  local R = c.TwichUI
  local K = R.SettingsKit
  -- no window in these tests: opening records where it would go
  R.SettingsUI.Open = function(page, setting) c.opened, c.openedSetting = page or "overview", setting end
  if opts.beforeDescribe then opts.beforeDescribe(c) end
  K.Describe()

  S.K = K
  S.variables, S.list = K.variables, K.settings
  S.pages = {}
  for _, page in ipairs(K.NavOrder()) do
    S.pages[#S.pages + 1] = {
      key = page.key, name = page.name, parent = page.parent and K.pages[page.parent].name or nil,
      kind = page.def.host and "hosted" or "page", rows = page.rows, group = page.group,
    }
  end
  return c, S
end
