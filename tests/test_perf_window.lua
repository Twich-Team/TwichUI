dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- TwichUI Diagnostics' window (TwichUI_Diagnostics/Window.lua, Charts.lua) drawn against stand-in frames: every view
-- builds and refreshes with no capture, while recording and after, the exports prepare in pieces, Compare takes two
-- captures, closing the window keeps the capture recording (with its badge), and nothing of it loads until asked.
-- Visuals, fonts, the pointer and the copy box can only be checked in the game.

local c, S = SettingsClient({ name = "Rich" })
local R = c.TwichUI
local errors = {}
c.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
c.GetTimePreciseSec = function() return CLOCK end
CLOCK = 50
c.GameTooltip = setmetatable({}, { __index = function() return function() end end })
c.UISpecialFrames = c.UISpecialFrames or {}
c.UpdateAddOnMemoryUsage = function() end
c.GetAddOnMemoryUsage = function() return 1000 end
c.GetFramerate = function() return 60 end
c.GetNumGroupMembers = function() return 0 end
-- frames that know whether they are shown and keep their scripts (OnShow and OnHide hooks run), so the window's
-- lifecycle can be followed; everything else answers with nothing
local function Obj(parent)
  local o = { shown = true, scripts = {}, hooks = {}, parent = parent }
  local api = {}
  function api:Show() if not self.shown then self.shown = true; self:Fire("OnShow") end end
  function api:Hide() if self.shown then self.shown = false; self:Fire("OnHide") end end
  function api:SetShown(v) if v then self:Show() else self:Hide() end end
  function api:IsShown() return self.shown end
  function api:IsVisible() return self.shown end
  function api:SetScript(n, fn) self.scripts[n] = fn end
  function api:GetScript(n) return self.scripts[n] end
  function api:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {}; table.insert(self.hooks[n], fn) end
  function api:Fire(n, ...)
    if self.scripts[n] then self.scripts[n](self, ...) end
    for _, h in ipairs(self.hooks[n] or {}) do h(self, ...) end
  end
  function api:SetText(t) self.text = t end
  function api:GetText() return self.text end
  function api:GetWidth() return self.w or 100 end
  function api:SetWidth(w) self.w = w end
  function api:SetSize(w, h) self.w, self.h = w, h end
  function api:GetHeight() return self.h or 14 end
  function api:SetHeight(h) self.h = h end
  function api:CreateFontString() return Obj(self) end
  function api:CreateTexture() return Obj(self) end
  function api:CreateAnimationGroup() return Obj(self) end
  function api:GetFrameLevel() return 1 end
  function api:GetEffectiveScale() return 1 end
  function api:GetScale() return 1 end
  function api:GetStringWidth() return 100 end
  function api:IsEnabled() return true end
  function api:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
  return setmetatable(o, { __index = function(_, k) return api[k] or function() end end })
end
c.CreateFrame = function(_, _, parent) local f = Obj(parent); f.shown = true; return f end
local loads = 0
local settingsLoad = c.C_AddOns.LoadAddOn
c.C_AddOns.LoadAddOn = function(name)
  if name ~= "TwichUI_Diagnostics" then return settingsLoad(name) end
  if not c.LOADED.TwichUI_Diagnostics then
    loads = loads + 1
    for line in io.lines(ROOT .. "../TwichUI_Diagnostics/TwichUI_Diagnostics.toc") do
      line = line:gsub("\r", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then
        local chunk = assert(loadfile(ROOT .. "../TwichUI_Diagnostics/" .. line:gsub("\\", "/"))); setfenv(chunk, c); chunk("TwichUI_Diagnostics", {})
      end
    end
    c.LOADED.TwichUI_Diagnostics = true
    c.FireEvent("ADDON_LOADED", "TwichUI_Diagnostics")
  end
  return true
end

assert(loads == 0 and R.Diagnostics == nil, "not loaded by the settings or at login")
-- the Troubleshooting page's entry opens it
local entry
for _, page in ipairs(S.pages) do
  if page.key == "troubleshooting" then
    for _, row in ipairs(page.rows) do if row.kind == "button" and row.data.name == "Diagnostics" then entry = row end end
  end
end
assert(entry, "the Troubleshooting page lists TwichUI Diagnostics")
entry.click()
assert(loads == 1 and R.Diagnostics, "its button loads and opens it")
local DX, W = R.Diagnostics, R.Diagnostics.Window
assert(DX.WindowShown(), "the window is shown")

local function AllTabs(label)
  for _, tab in ipairs(W.TABS) do
    DX.Open(tab.key)
    assert(W.State().tab == tab.key, label .. ": " .. tab.key)
  end
  assert(#errors == 0, label .. ": " .. table.concat(errors, "\n"))
end
AllTabs("no capture yet")

-- a capture with some work in it
assert(DX.Start("general", { note = "opening the map" }))
AllTabs("while recording")
local P = R.Perf
for i = 1, 30 do local t = P.Start("npcs.map.layout"); CLOCK = CLOCK + 0.002; P.Stop(t) end
DX.Mark("here")
DX.Close()
assert(DX.Recording() and W.Badged(), "closing the window keeps recording, with the badge")
DX.Open()
assert(not W.Badged(), "the badge goes while the window is open")
DX.Stop("manual"); FlushTimers()
assert(DX.State() == "stopped" and #DX.Sessions() == 1)
AllTabs("one capture")

-- exports
for _, kind in ipairs({ "summary", "full", "prompt" }) do
  W.State().exportKind = kind
  DX.Open("export")
  W.Prepare()
  local b = W.State().built
  assert(b and b.kind == kind and #b.pieces >= 1 and b.bytes > 0, "prepared: " .. kind)
end
assert(#errors == 0, table.concat(errors, "\n"))

-- a second capture, then Compare and its export
assert(DX.Start("general"))
for i = 1, 10 do local t = P.Start("npcs.map.layout"); CLOCK = CLOCK + 0.001; P.Stop(t) end
DX.Stop("manual"); FlushTimers()
AllTabs("two captures")
W.State().exportKind = "compare"
DX.Open("export")
W.Prepare()
assert(W.State().built and W.State().built.kind == "compare", "a comparison is prepared")
W.Cycle("viewing", -1)
AllTabs("the earlier capture shown")
-- a focused trace's options and the preset list
W.State().preset = "focused"
W.State().newCapture = true
DX.Open("overview")
-- open and close many times: one window, no errors
for _ = 1, 10 do DX.Close(); DX.Open() end
assert(#errors == 0, table.concat(errors, "\n"))
print("PERF WINDOW TEST PASSED")
