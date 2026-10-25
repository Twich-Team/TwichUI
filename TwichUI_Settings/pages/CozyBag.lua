-- TwichUI settings: Cozy Sleeping Bag guide (guides/). A small page: open the guide, lock it, put it back. The guide is a
-- window of the core addon and works without this page; it never opens by itself and has nothing to switch on.

local R = TwichUI
local K = R.SettingsKit

K.Page({
    key = "cozyBag", icon = "sleepingBag", name = "Cozy Sleeping Bag", order = 77, group = "journey",
    description = "A small guide to the hidden quest chain behind the Cozy Sleeping Bag, following your own quest history.",
    keywords = "cozy sleeping bag guide quest chain hidden rested experience resting bag pins map steps",
    overview = {
        label = "Cozy Sleeping Bag", tip = "A small guide to the hidden quest chain behind the Cozy Sleeping Bag.",
        when = function() return R.CozyBagWindow ~= nil end,
        status = function() return R.CozyBagWindow and R.CozyBagWindow.IsShown() and "Open" or "Closed" end,
    },
    when = function() return R.CozyBagWindow ~= nil end,
    build = function()
        K.Header("Cozy Sleeping Bag", "A step-by-step guide to the hidden quest chain that ends in the Cozy Sleeping Bag. It reads which of its quests this character has finished, so it is right even for steps done before TwichUI was installed. It never opens by itself and does nothing while it is closed.")
        K.Button("Guide window", function() return R.CozyBagWindow.IsShown() and "Close" or "Open" end,
            function()
                R.CozyBagWindow.Toggle()
                K.RefreshOverview()
            end,
            "Opens or closes the guide. You can also type /tui bag. The guide lists the steps in order with what you have done, shows each step's instructions and places, and can put a pin of your own on the world map for a place. It never accepts or turns in quests, and it sends nothing to anyone.")
        K.Button("Lock the guide", function() return R.CozyBag.Locked() and "Unlock" or "Lock" end,
            function() R.CozyBag.SetLocked(not R.CozyBag.Locked()) end,
            "Locked, the guide stays where it is; unlocked, drag it by any empty part. The lock can also be switched in the guide's title bar. The place is kept on this screen and is not shared.")
        K.Button("Reset position", "Reset", function() R.CozyBag.ResetPosition() end,
            "Puts the guide back where it starts. Only its place changes.")
    end,
})
