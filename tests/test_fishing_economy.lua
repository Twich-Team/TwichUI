dofile(TESTS .. "fishing_mock.lua")
local c, W = FishingClient()
W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
local F = c.TwichUI.Fishing
local E = assert(F.Economy)
local generation, calls, enabled, realm = 1, 0, true, "Fixture"
local prices = { [FISH1] = 123, [CLAM] = 500, [CLAMMEAT] = 20, [PEARL] = 10000 }
c.TwichUI.Workshop = {
  Active = function() return enabled end,
  Pricing = {
    Generation = function() return tostring(generation) end,
    Source = function() return { reference = true, label = "Fixture Alliance", market = { key = "fixture", at = 1800000000, realm = realm, side = "Alliance" } } end,
    Reference = function(id) calls = calls + 1; return prices[id] and { market = prices[id], recent = prices[id] + 1, at = 1800000000 } or nil, "missing" end,
    Changed = function() end,
  },
  Market = { Value = function() error("Reference market must never silently mix local fallback") end },
}
local p = { direct = { [FISH1] = 2 }, contents = { [CLAMMEAT] = 6, [PEARL] = 1 },
 containers = { [CLAM] = { caught = 3, opened = 2, unopened = 1 } } }
local v = E.Calculate(p, 1800, 5)
assert(calls == 0 and v.total == nil and v.missing == 10, "cold drawing never prices or invents zero")
W.Advance(1)
v = E.Calculate(p, 1800, 5)
assert(v.total == 10866 and v.complete, "2 fish + 6 meats + pearl + ONE shell; opened shells excluded")
assert(v.perHour == 21732 and v.perCast == 2173, "whole copper rates")
assert(v.direct[FISH1].total == 246 and v.contents[PEARL].total == 10000)
local before = calls
E.Calculate(p, 1800, 5)
assert(calls == before, "warm valuation reuses cache")
p.contents[PEARL] = 2; p.containers[CLAM].unopened = 0; p.containers[CLAM].opened = 3
v = E.Calculate(p, 1800, 5)
assert(v.total == 20366, "later partial processing replaces provisional shell with actual contents")
p.contents[JUNK] = 1
v = E.Calculate(p, 1800, 5); W.Advance(1); v = E.Calculate(p, 1800, 5)
assert(v.total == 20366 and not v.complete and v.missing == 1, "missing price preserves known subtotal")
prices[FISH1] = 200; generation = 2
v = E.Calculate(p, 1800, 5)
assert(v.total == nil, "market generation cannot reuse old item prices")
W.Advance(1); v = E.Calculate(p, 1800, 5)
assert(v.total == 20520, "new generation reprices quantities")
F.Store.Set("economy.provisional", false)
p.containers[CLAM].unopened = 10
E.Calculate(p); W.Advance(1)
assert(E.Calculate(p).total == 20520, "provisional switch excludes unopened shells")
enabled = false
v = E.Calculate(p, 0, 0)
assert(v.total == nil and not v.complete and v.perHour == nil and v.perCast == nil, "disabled Workshop remains missing")
assert(E.Item(FISH1).why == "workshop-unavailable")
assert(E.Calculate(nil) == nil)
print("PASSED fishing economy")
-- Real container/session bookkeeping rather than synthetic economic inputs.
enabled = true
F.Store.Set("economy.provisional", true)
W.bound.G = "CLICK TwichUIFishingOpen:LeftButton"
c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
W.Wear(16, POLE)
W.StartLine(); W.Loot({ { CLAM, 3 } }, { fishing = true }); W.StopLine(); W.Settle()
local sid = F.API.Session().id
F.Session.End("player")
W.map = 20
W.Key("G"); W.Advance(3)
local prov = F.API.Provenance(sid)
assert(prov.containers[CLAM].unopened == 2 and prov.contents[PEARL] == 1)
local actual = E.Scope(sid); W.Advance(1); actual = E.Scope(sid)
assert(actual.total == 11020, "late opening retains original session and replaces exactly one clam")
local again = E.Scope(sid)
assert(again.total == actual.total, "repeat query cannot attribute contents twice")
local partial = { direct = {}, contents = { [PEARL] = 1 }, containers = { [CLAM] = { unopened = 2, partial = 1 } } }
local pv = E.Calculate(partial)
assert(pv.total == 10500 and not pv.complete, "partially opened shell excluded while untouched shell remains provisional")
print("PASSED late container economy")

local warm = E.Item(PEARL); assert(warm.total == 10000)
realm = "DifferentRealm"
assert(E.Item(PEARL).total == nil, "market identity change invalidates prices even at the same generation")
W.Advance(1)
c.FireEvent("ADDON_LOADED", "TwichUI_Workshop")
local serial = F.Hud.serial
c.TwichUI.Workshop.Pricing.Changed()
assert(F.Hud.serial > serial, "new pricing data invalidates displayed values without another fish")
F.JournalUI.Open("overview"); W.Advance(1)
for _, page in ipairs({ "sessions", "collections", "locations", "treasures" }) do F.JournalUI.Show(page); W.Advance(1) end
F.JournalUI.Summary(sid)
assert(#W.errors == 0, "economic pages and summary construct without client errors")
print("PASSED economy presentation")
-- Saved queues retain partial-processing evidence; no prices enter SavedVariables.
F.Containers.Queue()[1].partial = true
local saved = FishRoundTrip(c.TwichUIFishingDB)
local c2, W2 = FishingClient({ db = saved })
W2.bound.F = "CLICK TwichUIFishingButton:LeftButton"; c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
local F2 = c2.TwichUI.Fishing
assert(F2.API.Provenance(sid).containers[CLAM].partial == 2, "reload conservatively withholds the ambiguous partial lot")
assert(F2.Store.Get("economy.provisional") == true and F2.Store.Get("economy.method") == "market", "economic settings migrate without resetting records")
assert(not saved.prices and not saved.ledger, "estimates do not create saved financial records")
c2.C_Item.GetItemInfo = function() return "Item", nil, nil, nil, nil, nil, nil, nil, nil, nil, 42 end
local vendor = F2.Economy.Item(FISH1, 3)
assert(vendor.total == nil and vendor.vendor == 126, "vendor values remain available without Workshop")
c2.TwichUI.Workshop = c.TwichUI.Workshop
local ref = c2.TwichUI.Workshop.Pricing.Reference
local loading = true
c2.TwichUI.Workshop.Pricing.Reference = function(id)
 if loading then return nil, "loading" end
 return ref(id)
end
F2.Economy.Item(FISH1); W2.Advance(1)
assert(F2.Economy.Item(FISH1).pending, "delayed market data remains pending without blocking")
loading = false; F2.Economy.Invalidate(); F2.Economy.Item(FISH1); W2.Advance(1)
assert(F2.Economy.Item(FISH1).total == 200, "delayed prices become available after invalidation")
assert(F2.Economy.Item(FISH1, 9007199254740991).total == nil, "unsafe copper multiplication remains missing")
print("PASSED economy persistence, vendor and delayed pricing")

local unknown = E.Calculate({ direct = { [PEARL] = 1 }, containers = { [CLAM] = { caught = 10, opened = 2, unopened = 0 } } })
assert(not unknown.complete and unknown.missing == 8, "historical containers without queue/content evidence remain incomplete")
-- A fish can be both a direct catch and container contents in the same session.
local c3, W3 = FishingClient()
W3.bound.F, W3.bound.G = "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton"
c3.FireEvent("UPDATE_BINDINGS"); W3.Advance(1)
local F3 = c3.TwichUI.Fishing
dofile(TESTS .. "fishing_economy_fixture.lua"); FishingEconomyFixture(c3)
W3.Wear(16, POLE)
W3.StartLine(); W3.Loot({ { FISH1, 5 }, { CLAM, 1 } }, { fishing = true }); W3.StopLine(); W3.Settle()
W3.contents[CLAM] = { { FISH1, 3 } }
W3.Key("G"); W3.Advance(3)
F3.Economy.Scope("session"); W3.Advance(1)
local values = F3.Present.Value("session")
local unit = F3.Economy.Item(FISH1).unit
assert(values.items[FISH1] == F3.Economy.Text(unit * 5), "direct catch row must value its own quantity")
assert(values.contents[FISH1] == F3.Economy.Text(unit * 3), "container contents row must value its own quantity")
assert(F3.Economy.Scope("session").total == unit * 8, "display separation preserves the economic total")
print("PASSED shared-item provenance display")
