-- Workshop settings remain descriptions until an explicit load; saved scopes stay compatible.
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient({ beforeInit = function(c)
    local chunk = assert(loadfile(ROOT .. "WorkshopLauncher.lua")); setfenv(chunk, c); chunk()
end })
local R, K = c.TwichUI, S.K
local L = R.WorkshopLauncher
assert(K.pages.workshop and #R.SettingsDesign.Tasks(K.pages.workshop) == 4)
assert(not L.Loaded() and not L.LoadOnLogin())
assert(not c.TwichUIDB.ui.workshopLoadOnLogin)
assert(S.variables.TWICHUI_workshopLoadOnLogin.default == false)
assert(L.SetLoadOnLogin(true) and L.LoadOnLogin())
local ui = c.TwichUIDB.ui
c.TwichUIDB.ui = {}
assert(not L.LoadOnLogin(), "login preference belongs to the active profile")
c.TwichUIDB.ui = ui
assert(L.LoadOnLogin() and L.SetLoadOnLogin(false) and not L.LoadOnLogin())
assert(not L.SetLoadOnLogin("true"))
assert(not L.SetOption("prices", true), "unloaded settings cannot implicitly load")
c.TwichUIDB.workshop = { view = { prices = "detailed", notices = false }, storage = { useGuild = true } }
local before = L.SettingsState()
assert(before.prices and before.guild and not before.notices, "existing account preferences are retained")
local called = {}
R.Workshop = { ready = true, Session = {
    SetPriceDetail = function(v) called.prices = v; return true end,
    SetUseGuild = function(v) called.guild = v; return true end,
}, Notice = { SetOn = function(v) called.notices = v; return true end } }
for _, key in ipairs({ "prices", "guild", "notices" }) do
    assert(L.SetOption(key, false) and called[key] == false, "uses existing setter: " .. key)
end
assert(not L.SetOption("unknown", true))
local headers = {}
for _, row in ipairs(K.pages.workshop.rows) do
    if row.kind == "header" then headers[#headers + 1] = row:GetName() end
end
assert(table.concat(headers, "|") == "General|Tooltip Designer|Market Data|Crafting & Shopping")
assert(K.pages.workshop.def.hostAfter == "Tooltip Designer")
print("PASSED")
