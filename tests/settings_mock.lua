-- A client with TwichUI's features and options loaded, and a stand-in for the game's Settings API that behaves
-- like WoW: Forever's SettingMixin (Blizzard_Setting.lua): SetValue writes only a value that differs, and the
-- value-changed callbacks run either way; NotifyUpdate runs them with the current value; SetValueToDefault is
-- what the panel's Defaults button does. Used by test_settings_contract.lua and test_settings_kit.lua.
--
-- SettingsClient(opts) -> c, S
--   opts.name: the character ("Rich" when left out)
--   opts.beforeInit(c): runs after the files are loaded and before the saved variables "arrive"
--   S.pages: categories in the order made, each { name, parent, kind, rows = { initializers } }
--   S.variables[name] = setting; S.list: settings in the order registered; S.registered(): the category added
--   S.popups: how many times the reload question was asked

function SettingsClient(opts)
  opts = opts or {}
  local c = MakeClient(opts.name or "Rich", {"!!!TwichUI", "Attune"})
  local S = { pages = {}, variables = {}, list = {}, popups = 0 }
  local registered

  local function Category(name, parent, kind)
    local cat = { name = name, parent = parent and parent.name or nil, kind = kind or "vertical", rows = {} }
    local id = #S.pages + 1
    function cat:GetID() return id end
    function cat:GetName() return self.name end
    function cat:SetExpanded() end
    S.pages[#S.pages + 1] = cat
    return cat, { AddInitializer = function(_, initializer) table.insert(cat.rows, initializer) end }
  end

  local function Initializer(kind, data)
    local i = { kind = kind, data = data, shown = {}, modify = {} }
    function i:AddShownPredicate(fn) table.insert(self.shown, fn) end
    function i:AddModifyPredicate(fn) table.insert(self.modify, fn) end
    function i:SetParentInitializer(parent, fn) self.parent = parent; if fn then table.insert(self.modify, fn) end end
    function i:GetTooltip() return self.data.tooltip end
    function i:GetName() if self.data.setting then return self.data.setting:GetName() end return self.data.name end
    function i:GetSetting() return self.data.setting end
    function i:GetData() return self.data end
    function i:Enabled() for _, fn in ipairs(self.modify) do if not fn() then return false end end return true end
    return i
  end

  local function NewSetting(cat, variable, varType, name, default, get, set, kind)
    assert(not S.variables[variable], variable .. " is registered once")
    local s = { variable = variable, varType = varType, name = name, default = default, get = get, set = set,
      page = cat.name, kind = kind, callbacks = {}, notified = 0 }
    function s:GetName() return self.name end
    function s:GetVariable() return self.variable end
    function s:GetValue() return self.get() end
    function s:GetDefaultValue() return self.default end
    function s:SetValueChangedCallback(fn) table.insert(self.callbacks, fn) end
    function s:TriggerValueChanged(value) for _, fn in ipairs(self.callbacks) do fn(self, value) end end
    function s:SetValue(value)
      assert(type(value) == self.varType, variable .. ": SetValue needs a " .. self.varType)
      if self.get() ~= value then self.set(value) end
      self:TriggerValueChanged(value)
    end
    function s:NotifyUpdate() self.notified = self.notified + 1; self:TriggerValueChanged(self.get()) end
    function s:SetValueToDefault() if self.default == nil then return false end self:SetValue(self.default) return true end
    S.variables[variable] = s
    S.list[#S.list + 1] = s
    return s
  end

  local function Control(kind)
    return function(category, setting, a, b)
      local tooltip = (kind == "slider" or kind == "dropdown") and b or a
      local i = Initializer(kind, { setting = setting, tooltip = tooltip })
      if kind == "slider" then setting.slider = a end
      if kind == "dropdown" then setting.options = a end
      if kind == "swatch" then setting.swatch = true end
      table.insert(category.rows, i)
      return i
    end
  end

  c.CreateSettingsListSectionHeaderInitializer = function(name, tooltip) return Initializer("header", { name = name, tooltip = tooltip }) end
  c.CreateSettingsButtonInitializer = function(name, buttonText, click, tooltip)
    local i = Initializer("button", { name = name, buttonText = buttonText, tooltip = tooltip }); i.click = click; return i
  end
  c.Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
    RegisterVerticalLayoutCategory = function(name) return Category(name) end,
    RegisterVerticalLayoutSubcategory = function(parent, name) return Category(name, parent) end,
    RegisterCanvasLayoutSubcategory = function(parent, _, name) return (Category(name, parent, "canvas")) end,
    RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
      if tbl[key] == nil then tbl[key] = default end
      local where = (tbl == c.TwichUIDB.modules and "modules") or (tbl == c.TwichUIDB.ui and "ui") or "?"
      return NewSetting(category, variable, varType, name, default,
        function() return tbl[key] end, function(value) tbl[key] = value end, "switch:" .. where .. "." .. key)
    end,
    RegisterProxySetting = function(category, variable, varType, name, default, get, set)
      return NewSetting(category, variable, varType, name, default, get, set, "proxy")
    end,
    CreateSliderOptions = function(min, max, step) return { min = min, max = max, step = step } end,
    CreateSlider = Control("slider"),
    CreateColorSwatch = Control("swatch"),
    CreateCheckbox = Control("checkbox"),
    CreateDropdown = Control("dropdown"),
    CreateControlTextContainer = function()
      local data = {}
      return { Add = function(_, value, label, tip) table.insert(data, { value = value, label = label, tooltip = tip }) end,
        GetData = function() return data end }
    end,
    OpenToCategory = function(id) c.opened = id end,
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
    "chronicle/Style.lua", "chronicle/Appearance.lua", "modules/Refreshments.lua", "modules/RefreshmentsPanel.lua", "modules/RefreshmentsShares.lua",
    "modules/RefreshmentsTrade.lua", "modules/RefreshmentsBroker.lua", "modules/MageSell.lua", "modules/MageSellWindow.lua",
    "modules/RestedXPSkin.lua", "modules/RestedXPTimers.lua", "modules/SpeakStoneSkin.lua", "qol/QoL.lua", "qol/Summons.lua", "qol/Resurrect.lua", "qol/ReleasePvP.lua",
    "qol/Duels.lua", "qol/QuickKeybind.lua", "qol/GuideWaypoint.lua",
    "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Minimap.lua", "pins/Editor.lua", "pins/Window.lua",
    "pins/BrokerMenu.lua", "pins/Broker.lua",
    "diag/Diagnostics.lua", "diag/Window.lua" }
  for _, f in ipairs(SettingsFiles()) do FILES[#FILES + 1] = f end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  if opts.beforeInit then opts.beforeInit(c) end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  return c, S
end
