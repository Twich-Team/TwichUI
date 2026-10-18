-- TwichUI settings: Auction House (auction/: the Sell from Bags tab).

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "auction", name = "Auction House", order = 80, group = "everyday",
    description = "A Sell from Bags tab for listing items from your bags, one at a time, and a mailbox gold summary.",
    keywords = "ah auction sell post price listing bags mail mailbox gold collected summary",
    overview = {
        label = "Auction House", tip = "A Sell from Bags tab for listing items one at a time.",
        status = function() return K.OnOff(R:Enabled("auctionPosting")) end,
    },
    build = function()
        K.Header("Sell from Bags", "A tab in the Auction House for listing items from your bags, one at a time.")
        K.Toggle("auctionPosting", "Add a Sell from Bags tab to the Auction House",
            "Lists the items in your bags that the auction house will take. Picking one searches its current listings (that item only, never the whole auction house) and suggests a price that matches the lowest comparable listing, with what it's based on. You set the quantity, price and duration; nothing is posted until you press Post. Results aren't saved.")
        K.Header("Mailbox", "A short line in your chat when you close the mailbox.")
        K.Toggle("mailGoldSummary", "Show mailbox gold summary",
            "When you close the mailbox, says in your chat how much money you took from mail during that visit: auction proceeds and money other players sent. Each time you open the mailbox starts again from zero, and nothing is said if you took no money. Only money that actually reached you counts, not money merely waiting in the inbox, cash-on-delivery payments, postage or other gold you gained or spent meanwhile. It is not a profit figure: deposits and fees are not subtracted. Nothing is saved.")
    end,
})
