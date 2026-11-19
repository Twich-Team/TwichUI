-- Workshop settings remain descriptions until an explicit load; saved scopes stay compatible.
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient({ beforeInit = function(c)
    for _, file in ipairs({"WorkshopLauncher.lua", "auction/Build.lua", "auction/Host.lua"}) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk()
    end
end })
local R, K = c.TwichUI, S.K
local L = R.WorkshopLauncher
assert(K.pages.workshop and #R.SettingsDesign.Tasks(K.pages.workshop) == 5)
assert(not L.Loaded() and not L.LoadOnLogin())
assert(S.variables.TWICHUI_workshopAuctionAdvisorOnly.default==false)
assert(S.variables.TWICHUI_workshopAuctionMaxQuantity.default==true)
assert(S.variables.TWICHUI_workshopAuctionDuration.default=="1")
S.variables.TWICHUI_workshopAuctionMaxQuantity:SetValue(false)
S.variables.TWICHUI_workshopAuctionAdvisorOnly:SetValue(true)
S.variables.TWICHUI_workshopAuctionDuration:SetValue("3")
local auctionDefaults=L.AuctionSettings()
assert(not auctionDefaults.maxQuantity and auctionDefaults.advisorOnly and auctionDefaults.duration==3)
assert(not L.Loaded(),"auction defaults never load Workshop")
local section,foundAuction
for _,row in ipairs(K.pages.workshop.rows) do
    if row.kind=="header" then section=row:GetName() end
    if row.id=="auctionDebug" then assert(section=="Auction House");foundAuction=true end
end
assert(foundAuction,"the existing interface toggle moved into the new task tab")
assert(not c.TwichUIDB.ui.workshopLoadOnLogin)
assert(S.variables.TWICHUI_workshopLoadOnLogin.default == false)
assert(S.variables.TWICHUI_workshopEnabled.default == false)
local search = assert(loadfile(REPO .. "TwichUI_Settings/Search.lua")); setfenv(search,c); search()
local found=false
for _, result in ipairs(R.SettingsSearch.Run("experimental")) do
    local entry=result.entry
    if entry.page=="workshop" and entry.row and entry.row.id=="workshopEnabled" then found=true end
end
assert(found and not L.Enabled() and not L.Loaded(), "search discovers the opt-in without loading or enabling Workshop")
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
assert(L.SetEnabled(true), "an existing loaded Workshop can be explicitly enabled")
assert(S.variables.TWICHUI_auctionDebug.default == false)
S.variables.TWICHUI_auctionDebug:SetValue(true)
assert(R.AuctionHost.DebugEnabled() and c.TwichUIDB.ui.auctionDebug == true, "standard Settings enables without a development marker")
S.variables.TWICHUI_auctionDebug:SetValue(false)
assert(not R.AuctionHost.DebugEnabled() and c.TwichUIDB.ui.auctionDebug == false)
for _, key in ipairs({ "prices", "guild", "notices" }) do
    assert(L.SetOption(key, false) and called[key] == false, "uses existing setter: " .. key)
end
assert(not L.SetOption("unknown", true))
R.Workshop.Advisor={SetGain=function(v) called.gain=v; return v~=nil end}
assert(L.SetChoice("advisorGain","1000") and called.gain==1000,"minimum gain uses the Advisor setter")
assert(not L.SetChoice("advisorGain","invalid"),"invalid minimum gain is refused")
local headers = {}
for _, row in ipairs(K.pages.workshop.rows) do
    if row.kind == "header" then headers[#headers + 1] = row:GetName() end
end
assert(table.concat(headers, "|") == "General|Auction House|Tooltip Designer|Market Data|Crafting & Shopping")
assert(K.pages.workshop.def.hostAfter == "Tooltip Designer")
-- Market descriptions use real source summaries, with honest empty/future states.
local status = {}
for _, row in ipairs(K.pages.workshop.rows) do if row.kind == "status" then status[row:GetName()] = row end end
local market, calls, now = nil, 0, 10
c.GetTime = function() return now end
c.date = os.date
R.Workshop.Market = {
    Info = function() calls = calls + 1; return market end,
    AgeShort = function(age) return age < 60 and "just now" or "3h ago" end,
    Freshness = function() return "fresh" end,
}
assert(status["Selected market"].value() == "No observations yet")
market = { label = "Realm Alliance", side = "Alliance", age = 1, items = 123, complete = false,
    history = { state = "ok", from = 20000 } }
now = now + 1
assert(status["Selected market"].value() == "Realm Alliance")
assert(status["Last scan"].value() == "just now", "age text does not append another ago")
assert(status["Freshness"].value() == "Fresh")
assert(status.Coverage.value() == "Partial observations")
assert(status.History.value() == "Since " .. os.date("!%d %b %Y", 20000 * 86400))
assert(calls == 2, "one validated summary per refresh, not one per status row")
market.age = 10800; now = now + 1
assert(status["Last scan"].value() == "3h ago")
market.history = { state = "future" }; now = now + 1
assert(status.History.value() == "Newer format")
assert(status["Data quality"].value() == "Shown per item", "no fabricated aggregate quality")
print("PASSED")

-- The collection label reflects the loaded bridge, never on-disk publication.
assert(status.Collection.value()=="Manual Auction House scans")
local companion={ready=true,contract_version=2,generation='synthetic-loaded-generation',checked_parts=1,parts=3}
R.Workshop.Bridge={Status=function()return companion end,Manifest=function()return {source_observation={observed_at='2026-11-15T12:00:00Z'}}end}
assert(status.Collection.value():find('Companion Market data',1,true))
assert(status['Companion data'].value()=='Loaded · prices and actual daily history')
assert(status['Loaded Market generation'].value()=='synthetic-loaded-generation')
assert(status['Market observations'].value()=='2026-11-15T12:00:00Z')
assert(status['Market validation'].value()=='1 / 3 data partitions checked on demand')
companion.ready=false;companion.error='invalid'
assert(status.Collection.value()=='Manual Auction House scans')
assert(status['Companion data'].value()=='Rejected · local scans remain available')
