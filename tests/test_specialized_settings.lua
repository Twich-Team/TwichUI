dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient()
local R, K = c.TwichUI, S.K
local function Row(page, name)
  for _, row in ipairs(K.pages[page].rows) do if row:GetName() == name then return row end end
  error("missing row " .. name)
end
for _, def in ipairs({
  { page = "speakstone", module = R.SpeakStoneSkin, switch = "speakstoneSkin", availability = "SpeakStone availability", action = "Sample line" },
  { page = "restedxp", module = R.RestedXPSkin, switch = "restedxpSkin", availability = "RestedXP availability", action = "TwichUI look in RestedXP" },
}) do
  local status = def.module.Status
  local state = { addon = "missing", loaded = false, integrated = false, code = def.page .. "-missing" }
  def.module.Status = function() return state end
  R:SetEnabled(def.switch, true)
  assert(Row(def.page, def.availability).value() == "Not installed")
  assert(not Row(def.page, def.action):Enabled(), "missing dependency action disabled")
  local style = def.module.Style or def.module.Text
  local key = def.page == "speakstone" and "textSize" or "lineSpacing"
  local before = style.Get(key)
  style.Set(key, before + 1)
  assert(style.Get(key) == before + 1, "preferences editable while absent")
  state = { addon = "ready", loaded = true, integrated = true, code = "active" }
  c.SlashCmdList.SPEAKSTONE = function() error("sample must not run during construction") end
  assert(Row(def.page, def.availability).value() == "Loaded")
  assert(Row(def.page, def.action):Enabled(), "supported action enabled")
  R:SetEnabled(def.switch, false)
  assert(not Row(def.page, def.action):Enabled(), "disabled look action disabled")
  assert(style.Get(key) == before + 1, "availability and switch changes preserve preferences")
  style.Set(key, before)
  def.module.Status = status
end
print("SPECIALIZED SETTINGS PASSED")
