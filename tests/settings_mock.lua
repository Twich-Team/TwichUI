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
--   opts.reload: the world is entered as after a reload (PLAYER_ENTERING_WORLD false, true), not a login
--   S.pages: the pages in their order, each { key, name, parent (its name), kind ("page" or "hosted"), rows }
--   S.variables[name] = setting; S.list: settings in the order made; S.registered(): the AddOns entry's category
--   S.popups: how many times the reload question was asked; S.popup: the last question asked ({ key, text });
--   S.ClickReset(row): clicks a section Reset and accepts what it asks; S.K: the settings kit

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
  -- a Mage with some mana, for the class resource bars (classbars/): the power APIs, and the state they read
  c.UnitPowerType = function() return 0, "MANA", 0.3, 0.5, 0.9 end
  c.UnitPower = function() return 100 end
  c.UnitPowerMax = function() return 200 end
  c.GetComboPoints = function() return 0 end
  c.UnitAffectingCombat = function() return false end
  c.UnitIsDeadOrGhost = function() return false end
  c.IsMounted = function() return false end
  c.UnitHasVehicleUI = function() return false end
  c.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return nil end }
  -- The real game gives a frame SetBackdrop only when it was made with BackdropTemplate; a mock that has it everywhere hides
  -- the mistake (a plain frame handed to Look.Surface).
  local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true, GetBackdrop = true }
  local function Obj(backdrop)
    return setmetatable({}, { __index = function(t, k)
      if k == "twichBevel" or k == "twichBorders" then return nil end
      if BACKDROP[k] and not backdrop then return nil end
      if k == "GetFrameLevel" or k == "GetEffectiveScale" or k == "GetScale" then return function() return 1 end end
      if k == "GetStringWidth" then return function() return 100 end end
      if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" or k == "CreateLine" then return function() return Obj() end end
      return function() end
    end })
  end
  c.CreateFrame = function(_, _, _, template) return Obj(type(template) == "string" and template:find("BackdropTemplate", 1, true) ~= nil) end
  local screen = Obj()   -- UIParent, for the class resource bars' places
  screen.GetWidth, screen.GetHeight = function() return 1024 end, function() return 768 end
  screen.GetCenter = function() return 512, 384 end
  c.UIParent = screen
  c.StaticPopupDialogs = {}
  c.StaticPopup_Show = function(name, text)
    if name == "TWICHUI_RELOAD" then S.popups = S.popups + 1 end
    S.popup = { key = name, text = text }   -- the last question asked
    return {}
  end
  -- Clicks a Reset button and accepts the question it asks (K.ResetButton asks first). Returns the question's text.
  function S.ClickReset(row)
    S.popup = nil
    row.click()
    local asked = S.popup
    assert(asked and asked.key:find("RESET", 1, true), "a Reset asks before it resets")
    c.StaticPopupDialogs[asked.key].OnAccept()
    return asked.text
  end
  c.PlaySoundFile = function() return true end
  -- empty bags, for the features that look in them when they are turned on
  c.C_Spell = { GetSpellName = function() return nil end, GetSpellDescription = function() return nil end }
  c.C_Item = { GetItemInfoInstant = function() return nil end, GetItemInfo = function() return nil end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end }
  c.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
  -- a unit's state, for Healer Watch when a setting under test makes it watch you: online, alive, no mana pool
  c.UnitIsConnected = function() return true end
  c.UnitIsDeadOrGhost = function() return false end
  c.UnitPower = function() return 0 end
  c.UnitPowerMax = function() return 0 end
  c.IsInInstance = function() return false, "none" end

  local FILES = { "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
    "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua", "gear/Window.lua", "modules/Notify.lua", "modules/Arrival.lua", "modules/Media.lua",
    "modules/FriendLogin.lua", "modules/Borders.lua", "modules/FoodDrink.lua", "modules/FoodDrinkUnlock.lua",
    "modules/TrainingData.lua", "modules/Training.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/MageTravel.lua", "modules/MageConjure.lua",
    "chronicle/Style.lua", "Look.lua", "Icons.lua", "chronicle/Appearance.lua", "modules/NotifyLook.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua", "modules/RefreshmentsShares.lua",
    "modules/RefreshmentsTrade.lua", "modules/RefreshmentsBroker.lua", "modules/EllesmereJunk.lua", "modules/MageSell.lua", "modules/MageSellWindow.lua", "modules/Restock.lua", "modules/RestockPrompt.lua", "inventory/Rules.lua", "inventory/Items.lua", "inventory/Plan.lua", "inventory/Run.lua", "inventory/Window.lua", "inventory/Picker.lua", "modules/ChatCleanMatch.lua", "modules/ChatClean.lua",
    "classbars/Anim.lua", "classbars/Resources.lua", "classbars/Config.lua", "classbars/Bar.lua", "classbars/Effects.lua", "classbars/Controller.lua",
    "reminders/AmmoItems.lua", "reminders/Config.lua", "reminders/Conditions.lua", "reminders/Ammunition.lua", "reminders/Evaluate.lua", "reminders/State.lua", "reminders/Display.lua", "reminders/Controller.lua",
    "healer/Config.lua", "healer/Logic.lua", "healer/Drinks.lua", "healer/Particles.lua", "healer/Display.lua", "healer/Watch.lua",
    "hazard/Config.lua", "hazard/Rules.lua", "hazard/Alerts.lua",
    "targetart/Config.lua", "targetart/Ellesmere.lua", "targetart/Display.lua",
    "modules/RestedXPSkin.lua", "modules/RestedXPTimers.lua", "modules/SpeakStoneSkin.lua", "qol/QoL.lua", "qol/Summons.lua", "qol/Resurrect.lua", "qol/ReleasePvP.lua",
    "qol/Duels.lua", "qol/QuickKeybind.lua", "qol/GuideWaypoint.lua", "markers/Markers.lua", "markers/Keys.lua", "markers/Bar.lua",
    "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Minimap.lua", "pins/Editor.lua", "pins/Window.lua",
    "pins/BrokerMenu.lua", "pins/Broker.lua",
    "nav/Prefs.lua", "nav/Data.lua", "nav/Route.lua", "nav/Journey.lua", "nav/Nav.lua", "nav/Travel.lua", "nav/Paint.lua", "nav/Unlock.lua", "nav/Frame.lua", "nav/Arrow.lua", "nav/MapTrail.lua", "nav/MinimapTrail.lua",
    "map/Prefs.lua", "map/Data.lua", "map/ViewMath.lua", "map/World.lua", "map/View.lua", "map/Art.lua", "map/Detail.lua", "map/Controls.lua", "map/Caves.lua", "map/Places.lua", "map/DungeonView.lua",
    "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Share.lua", "npcs/Knowledge.lua",
    "guides/CozyBagData.lua", "guides/CozyBagState.lua", "guides/CozyBag.lua", "guides/CozyBagOffer.lua", "guides/CozyBagNotice.lua", "guides/CozyBagButton.lua", "guides/CozyBagWindow.lua",
    "diag/Diagnostics.lua", "diag/Status.lua", "diag/SupportWindow.lua", "diag/Window.lua", "DiagnosticsLauncher.lua" }
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if opts.beforeInit then opts.beforeInit(c) end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", not opts.reload, opts.reload == true)   -- opts.reload: a reload, not a login

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
