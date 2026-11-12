-- TwichUI settings: Auction House (auction/: the Sell from Bags tab).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "auction", icon = "auctionHouse", name = "Auction House", order = 80, group = "everyday",
    description = "A Sell from Bags tab for listing items from your bags, one at a time, and a mailbox gold summary.",
    keywords = "ah auction sell post price listing bags mail mailbox gold collected summary",
    overview = {
        label = "Auction House", tip = "A Sell from Bags tab for listing items one at a time.",
        status = function() return K.OnOff(R:Enabled("auctionPosting")) end,
    },
    build = function()
        K.Card({
            title = "Sell from your bags", icon = "auctionHouse",
            what = "Choose an item at the Auction House, check its price, then post it yourself.",
            summary = function()
                return R:Enabled("auctionPosting") and "On · Sell from Bags appears at the Auction House"
                    or "Off · the extra selling tab is hidden"
            end,
            consequence = "Nothing is listed until you press Post. A price below known vendor value asks for confirmation.",
        })
        K.Toggle("auctionPosting", "Show Sell from Bags",
            "Adds the selling tab. Selecting an item searches that item only; opening settings never searches or posts.")
        K.Card({
            title = "Track money collected from mail", icon = "reviewChanges",
            what = "See a private chat total when you close the mailbox after collecting money.",
            summary = function()
                return R:Enabled("mailGoldSummary") and "On · one total per mailbox visit"
                    or "Off · no collection summary"
            end,
            consequence = "Money received, not profit. Fees and deposits are not subtracted; nothing is saved.",
        })
        K.Toggle("mailGoldSummary", "Show collected mail gold",
            "Counts auction proceeds and money sent by players that actually reaches you during this visit. No money collected means no message.")
        local details = K.Header("Pricing and totals explained", "Read before relying on a suggested price or a mail total.")
        details.settingsSecondary = true
        K.Status("Suggested price", function() return "Item-specific" end, function() return "Based on current comparable listings for the selected item; results are not saved." end)
        K.Status("Missing price data", function() return "Never assumed zero" end, function() return "Unknown is not zero or a safe price. Check the live tab's search and vendor-value messages." end)
        K.Status("Vendor warning", function() return "Review before posting" end, function() return "Compares the listed price with vendor value, before auction fees; it does not predict profit." end)
        K.Status("Mail total", function() return "Received this visit" end, function() return "Starts fresh each visit. Excludes waiting mail, COD payments, postage and unrelated gold changes." end)
    end,
})
