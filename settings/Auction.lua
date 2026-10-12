-- TwichUI options: Auction House (auction/: the Sell from Bags tab).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "auction", name = "Auction House", order = 80,
    overview = {
        label = "Auction House", tip = "A Sell from Bags tab for listing items one at a time.",
        status = function() return K.OnOff(R:Enabled("auctionPosting")) end,
    },
    build = function()
        K.Header("Sell from Bags", "A tab in the Auction House for listing items from your bags, one at a time.")
        K.Toggle("auctionPosting", "Add a Sell from Bags tab to the Auction House",
            "Lists the items in your bags that the auction house will take. Picking one searches its current listings (that item only, never the whole auction house) and suggests a price that matches the lowest comparable listing, with what it's based on. You set the quantity, price and duration; nothing is posted until you press Post. Results aren't saved.",
            false, function() if R.AuctionWindow then R.AuctionWindow.Refresh() end end)
    end,
})
