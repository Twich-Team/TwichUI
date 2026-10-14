dofile(TESTS .. "harness.lua")
-- The settings' contract: what a reorganisation of the settings window must not change without saying so.
--   * every setting's variable name, kind (switch or proxy), type, default and label;
--   * where each one writes: every setting is changed to another valid value and the whole of TwichUIDB is
--     compared, and then every page's "Reset this page" is run, in page order, and compared again (it must put
--     back what the game's own Defaults button did when the settings were in the game's options);
--   * the pages, their parents and groups, and the keys R:OpenSettings accepts;
--   * each page's rows in order: kind, label, section, what it is greyed out under, and
--     a checksum of its tooltip.
-- tests/fixtures/settings_contract.lua holds the expected values. To record it again after an intended change:
--   cd tests && TWICHUI_GENERATE_CONTRACT=1 lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_settings_contract.lua
-- and review the fixture's diff: only the intended lines may change.
-- The setting objects (TwichUI_Settings/Kit.lua) behave like WoW: Forever's SettingMixin did: a value is only
-- written when it differs, and the value-changed callbacks run either way.
local GENERATE = os.getenv("TWICHUI_GENERATE_CONTRACT") == "1"
local FIXTURE = TESTS .. "fixtures/settings_contract.lua"

dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient()
local pages, variables = S.pages, S.variables
local R, K = c.TwichUI, S.K
assert(S.registered() and S.registered().name == "TwichUI", "the TwichUI launcher is added to the AddOns list")

local function Checksum(s)
  if s == nil then return "-" end
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return ("%08x"):format(h)
end

---------------------------------------------------------------------------
-- Plain, ordered text for a value or table (sorted keys).
local function Serialize(v, indent, out)
  indent, out = indent or "", out or {}
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    if #keys == 0 then out[#out + 1] = indent .. "{}" return out end
    for _, k in ipairs(keys) do
      local val = v[k]
      if type(val) == "table" then
        out[#out + 1] = indent .. tostring(k) .. ":"
        Serialize(val, indent .. "  ", out)
      elseif type(val) ~= "function" and type(val) ~= "userdata" then
        out[#out + 1] = indent .. tostring(k) .. "=" .. (type(val) == "string" and ("%q"):format(val) or tostring(val))
      end
    end
  elseif t == "string" then out[#out + 1] = indent .. ("%q"):format(v)
  else out[#out + 1] = indent .. tostring(v) end
  return out
end

local contract = { pages = {}, keys = {}, settings = {}, rows = {}, changed = {}, defaulted = {} }

for _, page in ipairs(pages) do
  contract.pages[#contract.pages + 1] = page.name .. " < " .. tostring(page.parent) .. " (" .. page.kind .. ", " .. page.group .. ")"
end
local keys = {}
for key, page in pairs(K.pages) do keys[#keys + 1] = key .. " -> " .. page.name end
table.sort(keys)
contract.keys = keys

local names = {}
for name in pairs(variables) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local s = variables[name]
  contract.settings[#contract.settings + 1] = ("%s | %s | %s | %s | default=%s | %s"):format(
    name, s.page, s.kind, s.varType, tostring(s.default), s.name)
end

for _, page in ipairs(pages) do
  for n, i in ipairs(page.rows) do
    local label = i:GetName() or ""
    contract.rows[#contract.rows + 1] = ("%s #%d %s %q%s%s%s tip:%s"):format(page.name, n, i.kind, label,
      (i.kind ~= "header" and i.section) and (" in:%q"):format(i.section:GetName() or "?") or "",
      i.parent and (" under:%q"):format(i.parent:GetName() or "?") or "",
      i.data.setting and (" " .. i.data.setting.variable) or "",
      Checksum(i:GetTooltip()))
  end
end

-- Where each setting writes: change every one to another valid value, in name order.
local function Alternative(s)
  local cur = s.get()
  if s.varType == "boolean" then return not cur end
  if s.options then
    local list = s.options()
    for i = #list, 1, -1 do if list[i].value ~= cur then return list[i].value end end
    return nil
  end
  if s.slider then
    if cur ~= s.slider.min then return s.slider.min end
    return s.slider.max
  end
  if s.swatch then return cur ~= "ff123456" and "ff123456" or "ff654321" end
end
for _, name in ipairs(names) do
  local s = variables[name]
  local alt = Alternative(s)
  if alt ~= nil then s:SetValue(alt) end
end
FlushTimers()
for _, name in ipairs(names) do
  contract.changed[#contract.changed + 1] = name .. " = " .. Serialize(variables[name].get())[1]
end
contract.changedDB = Serialize(c.TwichUIDB)

-- "Reset this page" on every page, in the left-hand list's order.
local reset = 0
for _, page in ipairs(K.NavOrder()) do reset = reset + K.ResetPage(page.key) end
FlushTimers()
local withDefault = 0
for _, name in ipairs(names) do if variables[name].default ~= nil then withDefault = withDefault + 1 end end
assert(reset == withDefault, ("every setting with a default is on a page's reset once: %d of %d"):format(reset, withDefault))
for _, name in ipairs(names) do
  contract.defaulted[#contract.defaulted + 1] = name .. " = " .. Serialize(variables[name].get())[1]
end
contract.defaultedDB = Serialize(c.TwichUIDB)

---------------------------------------------------------------------------
local SECTIONS = { "pages", "keys", "settings", "rows", "changed", "changedDB", "defaulted", "defaultedDB" }
if GENERATE then
  local f = assert(io.open(FIXTURE, "w"))
  f:write("-- Generated by tests/test_settings_contract.lua (TWICHUI_GENERATE_CONTRACT=1). Review its diff before keeping it.\nreturn {\n")
  for _, section in ipairs(SECTIONS) do
    f:write("  ", section, " = {\n")
    for _, line in ipairs(contract[section]) do f:write("    ", ("%q"):format(line), ",\n") end
    f:write("  },\n")
  end
  f:write("}\n")
  f:close()
  print("wrote " .. FIXTURE .. " (" .. #contract.settings .. " settings, " .. #contract.rows .. " rows)")
  print("PASSED")
  return
end

local expected = assert(loadfile(FIXTURE), "no contract fixture: generate it (see the top of this file)")()
local problems = 0
for _, section in ipairs(SECTIONS) do
  local want, got = expected[section], contract[section]
  local n = math.max(#want, #got)
  for i = 1, n do
    if want[i] ~= got[i] then
      problems = problems + 1
      if problems <= 12 then
        print(("%s line %d\n  expected: %s\n  got:      %s"):format(section, i, tostring(want[i]), tostring(got[i])))
      end
      break   -- the first difference in each section is enough to find it
    end
  end
end
assert(problems == 0, problems .. " section(s) of the options contract changed")
print(#contract.settings .. " settings, " .. #contract.rows .. " rows as recorded")
print("PASSED")
