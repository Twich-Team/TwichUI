dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
local c, S = SettingsClient({ beforeDescribe = function(client)
    client.TwichUI.AuctionScan = client.TwichUI.AuctionScan or {}
    client.C_AuctionHouse = client.C_AuctionHouse or {}
    client.TwichUI.AuctionScan.Start = function() error("settings must not start a search") end
    for _, action in ipairs({ "PostItem", "PostCommodity", "PlaceBid", "CancelAuction" }) do
        client.C_AuctionHouse[action] = function() error("settings must not transact") end
    end
end })
local R, K = c.TwichUI, S.K
local page, cards, switches, details = K.pages.auction, {}, {}, nil
for _, row in ipairs(page.rows) do
    if row.card then cards[#cards + 1] = row.card end
    if row.switch then switches[row.switch] = row end
    if row.settingsSecondary then details = row end
end
assert(#cards == 2 and details and details:GetName() == "Pricing and totals explained")
for i, key in ipairs({ "auctionPosting", "mailGoldSummary" }) do
    local setting = switches[key].setting
    local before = setting:GetValue()
    local other = i == 1 and "mailGoldSummary" or "auctionPosting"
    local otherValue = R:Enabled(other)
    setting:SetValue(false)
    assert(not R:Enabled(key) and cards[i].summary():find("Off", 1, true))
    setting:SetValue(true)
    assert(R:Enabled(key) and cards[i].summary():find("On", 1, true))
    assert(R:Enabled(other) == otherValue, "task switches remain independent")
    setting:SetValue(before)
end
assert(cards[1].consequence:find("Post", 1, true))
assert(cards[2].consequence:find("not profit", 1, true))
print("AUCTION SETTINGS PASSED")
