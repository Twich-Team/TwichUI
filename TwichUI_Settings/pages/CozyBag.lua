-- TwichUI settings: Cozy Sleeping Bag guide (guides/). Open the guide, lock it, put it back; and, when the bag becomes
-- available to a character (level 14), a quiet card once and a small button that opens the guide (guides/CozyBagOffer.lua,
-- CozyBagNotice.lua, CozyBagButton.lua). The guide is a window of the core addon and works without this page; it never opens
-- by itself, and neither the card nor the button opens it.

local R = TwichUI
local K = R.SettingsKit

local function InCombat() return InCombatLockdown and InCombatLockdown() end
local function Offer() return R.CozyBagOffer end
local function Button() return R.CozyBagButton end

-- What the offer says about this character now, in words (nothing is changed by asking).
local function CharacterStatus()
    local O, D = Offer(), R.CozyBagData
    if not O then return "Not available this session" end
    if O.Acquired() then return "You already have the bag" end
    local s = O.Status()
    if s.reason == "owned" or s.reason == "complete" then return "You already have the bag" end
    if s.reason == "level" then return ("Not yet: level %d is needed"):format(D.level) end
    if s.reason == "loading" or s.reason == "unknown" then return "Waiting for the game to report your quests" end
    if O.Hidden() then return "Available; you hid the button" end
    if O.Announced() then return "Available; you have been told" end
    return "Available"
end

K.Page({
    key = "cozyBag", icon = "sleepingBag", name = "Cozy Sleeping Bag", order = 77, group = "journey",
    description = "A small guide to the hidden quest chain behind the Cozy Sleeping Bag, following your own quest history.",
    keywords = "cozy sleeping bag guide quest chain hidden rested experience resting bag pins map steps button launcher notification card level 14 unlock invitation hide move preview",
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

        if not (Offer() and Button()) then return end
        local Toggle, Under, Button_, Choice, Proxy, Slider = K.Toggle, K.Under, K.Button, K.Choice, K.Proxy, K.Slider
        local B = Button()
        local D = R.CozyBagData

        K.Header("When the bag becomes available", ("From level %d, until you have the bag, a small card says so once and a small button opens the guide. Neither opens it by itself, plays a sound, or sends anything. Both keep a record for each character, so a character is told once and a hidden button stays hidden."):format(D.level))
        Toggle("cozyBagNotice", "Tell me when the Sleeping Bag becomes available",
            ("A quiet card, once per character, when you reach level %d without the bag, or the first time TwichUI sees a higher level character that doesn't have it. It waits for combat, other cards and the first-install setup. It is not shown again after it has been shown, and not at all once you have the bag or have hidden the button."):format(D.level))
        local show = Toggle("cozyBagButton", "Show the guide button",
            "A small button on your screen while the bag is available and you don't have it. Left-click opens the guide; right-click offers Open guide, Move and Hide button. This switch does not undo a button you hid on this character: use \"Show the hidden button\" below.")
        K.Status("This character", CharacterStatus, nil,
            "Whether the bag is available to the character you are playing, from your quest history and what you carry. Having the bag, or having finished the chain, ends the offer for good, even if you later sell it or put it in the bank.")
        local restore = Button_("Show the hidden button", "Show it", function()
            Offer().SetHidden(false)
            if not R:Enabled("cozyBagButton") then R:SetEnabled("cozyBagButton", true) end
            K.RefreshOverview()
        end, "Brings back the button you hid from its menu, on this character, and turns the button switch on if it was off. Nothing else about the offer changes. It appears only while the bag is available.")
        if restore then
            restore:AddModifyPredicate(function() return Offer().Hidden() end)
            restore.why = "You haven't hidden the button on this character."
        end

        local function Number(name, label, tooltip)
            local setting = Proxy("cozyBagButton" .. name:sub(1, 1):upper() .. name:sub(2), K.NUMBER, label, B.DEFAULTS[name],
                function() return B.Get(name) end, function(value) B.Set(name, value) end)
            local lim = B.LIMITS[name]
            return Slider(setting, lim[1], lim[2], tooltip)
        end
        local function On() return R:Enabled("cozyBagButton") end
        Under(Choice("cozyBagButtonLabel", "Button shows", "An icon alone, or the icon with the words \"Sleeping Bag\" beside it.",
            K.STRING, B.DEFAULTS.label, function() return B.Get("label") end, function(value) B.Set("label", value) end, B.CHOICES), show, On)
        Under(Number("size", "Button size", "The button's height and, with the icon only, its width, in screen pixels."), show, On)
        Under(Number("opacity", "Button opacity", "How solid the button is, in percent. It stays at this strength; it does not pulse or fade by itself."), show, On)

        local move = Button_("Button place", function() return B.Moving() and "Done" or "Move" end, function()
            if B.Moving() then B.StopMove() else
                local ok, why = B.StartMove()
                if not ok and why == "combat" then R.Print("the button can't be moved in combat.") end
            end
            K.RefreshOverview()
        end, "Shows the button wherever the bag stands (even before it is available) so you can drag it. It can only be dragged while you are moving it; a click then does nothing. Press Done, close the settings, or start a fight to finish. The place is kept on this screen and is not shared.")
        if move then
            move:AddModifyPredicate(function() return B.Moving() or not InCombat() end)
            move.why = "Can't be moved in combat."
        end
        Button_("Put the button back", "Reset", function() B.ResetPosition() end,
            "Puts the button back where it starts, against the left edge a little above the middle. Only its place changes.")

        K.Header("Previews", "Try the card and the button without waiting. A preview records nothing, changes no choice, and works on any character; it ends when you press the button again, the settings close, or a fight starts.")
        Button_("Unlock card", "Preview", function()
            if InCombat() then R.Print("previews wait until you're out of combat.") return end
            local ok = Offer().PreviewCard()
            if ok == false then R.Print("couldn't show that preview: it's already showing, or too many cards are waiting.") end
        end, "Shows the card as it would appear. It follows the New training card's look (Notification appearance) and fades by itself. It marks nothing as told.")
        Button_("Guide button", function() return B.Previewing() and "Stop preview" or "Preview" end, function()
            B.Preview(not B.Previewing())
            K.RefreshOverview()
        end, "Shows the button as you have set it, for thirty seconds or until you stop it. Clicking it does nothing.")
    end,
})
