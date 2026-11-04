dofile(TESTS .. "harness.lua")
-- The Game Menu button (qol/TwichUISettingsButton.lua): on each GameMenuFrame rebuild a "TwichUI"
-- button is taken from the game's button pool and slotted directly after the last present button of
-- the utility group (AddOns / Edit Mode / Support / Macros, matched by text), shifting the layout
-- indices of all later buttons by one so whatever other addons added is preserved. With none of the
-- utility names present, nothing is added. The game releases the whole pool on the next rebuild, so
-- the button is re-acquired fresh and can never be duplicated. Clicking it hides the menu and opens
-- the settings window. The game is simulated: this checks the decisions, not the game's own layout.
local c = MakeClient("Rich", { "!!!TwichUI" })
for _, f in ipairs({ "qol/QoL.lua", "qol/TwichUISettingsButton.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
local R = c.TwichUI
local K = R.QoLTwichUISettingsButton
-- The game's localized menu strings (enUS), which FindAfter matches button text against.
c.ADDONS = "AddOns"
c.HUD_EDIT_MODE_MENU = "Edit Mode"
c.GAMEMENU_SUPPORT = "Support"
c.MACROS = "Macros"
assert(K ~= nil and K.LABEL == "TwichUI", "the feature is registered and its label is 'TwichUI'")

---------------------------------------------------------------------------
-- A stand-in for the GameMenuFrame's button pool, with the same methods the
-- feature uses: Acquire, Release, IsActive, EnumerateActive.
---------------------------------------------------------------------------
local function MakeMenu(buttons)
  local pool = { active = {} }
  function pool:Acquire()
    local b = { text = "", shown = false, scripts = {} }
    function b:SetText(t) self.text = t end
    function b:GetText() return self.text end
    function b:SetScript(n, fn) self.scripts[n] = fn end
    function b:SetMotionScriptsWhileDisabled() end
    function b:Show() self.shown = true end
    table.insert(pool.active, b)
    return b
  end
  function pool:IsActive(b) for _, x in ipairs(pool.active) do if x == b then return true end end return false end
  function pool:Release(b) for i, x in ipairs(pool.active) do if x == b then table.remove(pool.active, i) return end end end
  function pool:EnumerateActive()
    local i = 0
    return function() i = i + 1; return pool.active[i] end
  end
  local menu = { buttonPool = pool, nextLayoutIndex = #buttons + 1, MarkDirty = function() menu.dirty = (menu.dirty or 0) + 1 end, InitButtons = function() end }
  for _, spec in ipairs(buttons) do
    local b = pool:Acquire()
    b:SetText(spec.text)
    b.layoutIndex = spec.layoutIndex
  end
  return menu
end

-- The menu's buttons in the order the game builds them: the utility group sits above Log Out.
local function StandardMenu()
  return MakeMenu({
    { text = "Character", layoutIndex = 1 },
    { text = "Options", layoutIndex = 2 },
    { text = "AddOns", layoutIndex = 3 },
    { text = "Edit Mode", layoutIndex = 4 },
    { text = "Support", layoutIndex = 5 },
    { text = "Macros", layoutIndex = 6 },
    { text = "Log Out", layoutIndex = 7 },
    { text = "OtherAddon", layoutIndex = 8 },   -- a button some other addon added
  })
end

local function ByIndex(menu)
  local m = {}
  for b in menu.buttonPool:EnumerateActive() do m[b.layoutIndex] = b end
  return m
end
local function TwichButtons(menu)
  local n = 0
  for b in menu.buttonPool:EnumerateActive() do if b:GetText() == "TwichUI" then n = n + 1 end end
  return n
end
local function ReleaseAll(menu)
  local list = {}
  for b in menu.buttonPool:EnumerateActive() do list[#list + 1] = b end
  for _, b in ipairs(list) do menu.buttonPool:Release(b) end
end

---------------------------------------------------------------------------
-- One rebuild: the button is slotted after the last utility button and the
-- later indices shift by one.
---------------------------------------------------------------------------
do
  local menu = StandardMenu()
  c.GameMenuFrame = menu
  K.OnMenuShown()
  local byIndex = ByIndex(menu)
  -- 'Macros' is the last present utility button (layoutIndex 6), so ours goes at 7.
  assert(byIndex[7] ~= nil and byIndex[7]:GetText() == "TwichUI", "the new button sits at layoutIndex 7, one past 'Macros'")
  assert(byIndex[7].shown == true, "the new button is shown")
  -- Everything at or after the insertion point moved up by one, other addons' button included.
  assert(byIndex[8] ~= nil and byIndex[8]:GetText() == "Log Out", "'Log Out' shifted 7 -> 8")
  assert(byIndex[9] ~= nil and byIndex[9]:GetText() == "OtherAddon", "the other addon's button shifted 8 -> 9")
  assert(byIndex[3]:GetText() == "AddOns" and byIndex[4]:GetText() == "Edit Mode" and byIndex[5]:GetText() == "Support"
      and byIndex[6]:GetText() == "Macros", "the utility group itself is untouched")
  assert(menu.nextLayoutIndex == 10, "nextLayoutIndex incremented 9 -> 10")
  assert(TwichButtons(menu) == 1, "exactly one TwichUI button")

  -- Clicking it hides the shown menu and opens the settings window.
  local calls = { hidden = nil, opened = false }
  c.HideUIPanel = function(f) calls.hidden = f end
  menu.IsShown = function() return true end
  local realOpen = R.OpenSettings
  R.OpenSettings = function(self, page) calls.opened = true; calls.page = page end
  byIndex[7].scripts.OnClick()
  R.OpenSettings = realOpen
  assert(calls.hidden == menu, "the shown GameMenuFrame is hidden")
  assert(calls.opened == true, "the settings window is opened (R:OpenSettings)")

  -- A menu that is already hidden is left alone, but the window still opens.
  calls = { hidden = nil, opened = false }
  menu.IsShown = function() return false end
  R.OpenSettings = function(self, page) calls.opened = true end
  byIndex[7].scripts.OnClick()
  R.OpenSettings = realOpen
  assert(calls.hidden == nil and calls.opened == true, "an unshown menu is not hidden")
end

---------------------------------------------------------------------------
-- None of the utility names present: nothing is added, indices untouched.
---------------------------------------------------------------------------
do
  local menu = MakeMenu({
    { text = "Character", layoutIndex = 1 },
    { text = "Options", layoutIndex = 2 },
    { text = "Log Out", layoutIndex = 3 },
  })
  c.GameMenuFrame = menu
  K.OnMenuShown()
  assert(#menu.buttonPool.active == 3, "no button is acquired")
  assert(TwichButtons(menu) == 0, "no TwichUI button")
  local byIndex = ByIndex(menu)
  assert(byIndex[1]:GetText() == "Character" and byIndex[2]:GetText() == "Options" and byIndex[3]:GetText() == "Log Out",
      "the existing indices are untouched")
  assert(menu.nextLayoutIndex == 4, "nextLayoutIndex is untouched")
end

---------------------------------------------------------------------------
-- A second rebuild: the game released the pool, so a fresh button is
-- re-acquired and no duplicate remains.
---------------------------------------------------------------------------
do
  local first = StandardMenu()
  c.GameMenuFrame = first
  K.OnMenuShown()
  local old
  for b in first.buttonPool:EnumerateActive() do if b:GetText() == "TwichUI" then old = b end end
  assert(old ~= nil, "the first rebuild added the button")

  -- The game's Reset releases the whole pool, then InitButtons builds it again.
  ReleaseAll(first)
  local second = StandardMenu()
  c.GameMenuFrame = second
  K.OnMenuShown()

  assert(TwichButtons(second) == 1, "exactly one TwichUI button after the rebuild")
  local fresh
  for b in second.buttonPool:EnumerateActive() do if b:GetText() == "TwichUI" then fresh = b end end
  assert(fresh ~= old, "it is a freshly acquired button, not the old one")
  assert(first.buttonPool:IsActive(old) == false, "the old button was released with the pool")
  local byIndex = ByIndex(second)
  assert(byIndex[7] == fresh, "it is slotted at layoutIndex 7 again")
  assert(byIndex[9] ~= nil and byIndex[9]:GetText() == "OtherAddon", "the other addon's button is shifted again")
  assert(second.nextLayoutIndex == 10, "nextLayoutIndex is 10 again")
end

---------------------------------------------------------------------------
-- No menu at all: the hook is a no-op.
---------------------------------------------------------------------------
do
  c.GameMenuFrame = nil
  K.OnMenuShown()
end

print("TEST_SETTINGS_BUTTON PASSED")
