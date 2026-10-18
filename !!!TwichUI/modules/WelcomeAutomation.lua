-- TwichUI: what acts for the player, as the welcome dialog explains it
-- A list of the features that do something without a click of their own (accept or decline a request, release,
-- sell or mark items, fill a trade, set a waypoint, send a message to the group, hide chat lines) and a summary of
-- which of them are on for this character right now. Reads only: it enables nothing, changes no setting and
-- listens to no event. The welcome dialog (modules/Welcome.lua) asks for the summary each time it is shown.
--
--   * "On" is the feature's own reading of its switch: the saved value, else the default, and for an opt-in only an
--     explicit true. A switch under another (Mage selling, the refreshments trade filling) counts only with the
--     one it needs.
--   * Mage features are listed for a Mage only; the RestedXP waypoint only while RestedXP is installed and turned on.
--   * The words describe the scope the player has chosen today (who a summons is accepted from, how long it waits,
--     whether selling is still a dry run), read through the feature's own accessors, never from a copy here.
--   * Features that need the player's own key press or click (the Food and Drink buttons, the Mage
--     launchers) are not automation and are not listed.
-- A feature that is not in this client this session (its file is missing) is left out, not guessed at.

local R = TwichUI
local A = {}
R.WelcomeAutomation = A

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- A switch as the feature itself reads it. Only an explicit true is on, so a damaged value never reads as on.
local function On(key)
    local m = TwichUIDB and TwichUIDB.modules
    local v
    if type(m) == "table" then v = m[key] end   -- (not `and ... or`: a saved false must stay false)
    if v == nil and R.DEFAULT_MODULES then v = R.DEFAULT_MODULES[key] end
    return v == true
end
A.On = On

local function IsMage()
    local MS = R.MageSell
    if MS and MS.ForPlayer then return MS.ForPlayer() and true or false end
    if not UnitClass then return false end
    local _, class = UnitClass("player")
    return Plain(class) == "MAGE"
end
A.IsMage = IsMage

local PEOPLE = {
    known = "friends, guild members and group members", friendsGuild = "friends and guild members",
    friends = "friends", group = "group members", anyone = "anyone", nobody = "no one",
}

local function Wait(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return "at once" end
    return ("after %d second%s"):format(seconds, seconds == 1 and "" or "s")
end

local function Choice(key)
    local Q = R.QoL
    return Q and Q.Get and Q.Get(key) or nil
end

-- Each entry: key (the switch), page (the settings page to review it on), label, off (a phrase for the list of
-- what is off), scope() (what it does as set today), available() and on() when the default reading isn't enough.
-- Order is the order shown.
A.ENTRIES = {
    {
        key = "qolSummons", page = "qol", label = "Accept summons", off = "accepting summons",
        available = function() return R.QoL ~= nil end,
        scope = function()
            return ("Accepts a summons from %s, %s. Other kinds of summons are left to you."):format(
                PEOPLE[Choice("summonsFrom")] or PEOPLE.known, Wait(Choice("summonsWait")))
        end,
    },
    {
        key = "qolResurrect", page = "qol", label = "Accept resurrection", off = "accepting resurrections",
        available = function() return R.QoL ~= nil end,
        scope = function()
            return "Accepts a resurrection offered to you, except one that carries resurrection sickness"
                .. (On("qolResurrectCombat") and ". Combat resurrections too." or " or a combat resurrection.")
        end,
    },
    {
        key = "qolReleasePvP", page = "qol", label = "Release in battlegrounds", off = "releasing your spirit in battlegrounds",
        available = function() return R.QoL ~= nil end,
        scope = function()
            return ("Releases your spirit %s after you die in a battleground. Nowhere else."):format(Wait(Choice("releaseWait")))
        end,
    },
    {
        key = "qolDuels", page = "qol", label = "Decline duels", off = "declining duel requests",
        available = function() return R.QoL ~= nil end,
        scope = function()
            return ("Declines duel requests, except from %s%s."):format(
                PEOPLE[Choice("duelsFrom")] or PEOPLE.known,
                On("qolDuelsToDeath") and ". Duels to the death too" or "")
        end,
    },
    {
        key = "qolGuideWaypoint", page = "qol", label = "RestedXP waypoint", off = "marking RestedXP's destination on the map",
        available = function()
            if not R.QoLGuideWaypoint then return false end
            local state = R.Setups and R.Setups.AddonState and R.Setups.AddonState("RXPGuides")
            return state ~= "missing" and state ~= "disabled"
        end,
        scope = function() return "Sets the game's map waypoint to where RestedXP is leading you. Your own waypoint is left alone." end,
    },
    {
        key = "mageSell", page = "mage", label = "Mage selling", mage = true,
        off = "selling ordinary food and drink at merchants",
        available = function() return R.MageSell ~= nil end,
        scope = function()
            local MS = R.MageSell
            local marks = MS.Mode and MS.Mode() == "ellesmere"
            local dry = MS.DryRun and MS.DryRun()
            local what = marks and "Marks ordinary (not conjured) food and drink as junk in EllesmereUI's bags."
                or "Sells ordinary (not conjured) food and drink when you open a merchant."
            return what .. (dry and " For now a dry run: it only reports, and changes nothing." or "")
        end,
    },
    {
        key = "mageRefreshmentsAutoFill", page = "mage", label = "Refreshment trades", mage = true,
        off = "filling a group member's trade with conjured refreshments",
        available = function() return R.RefreshmentsTrade ~= nil end,
        on = function()
            return On("mageRefreshments") and On("mageRefreshmentsTrade") and On("mageRefreshmentsAutoFill")
        end,
        scope = function() return "Puts conjured food and water into a group member's trade window when they trade with you. It never accepts the trade." end,
    },
    {
        key = "restock", page = "restock", label = "Vendor restocking",
        off = "buying the items on your restock list from merchants",
        available = function() return R.Restock ~= nil end,
        on = function() return R.Restock.Enabled() end,
        scope = function()
            local RS = R.Restock
            local n = 0
            for _, rule in ipairs(RS.Rules()) do if rule.enabled then n = n + 1 end end
            local how = RS.Mode() == "auto" and "buys them by itself" or "asks before buying them"
            local limit = RS.SpendLimit()
            return ("Keeps %d %s on your restock list at their targets: when you open a merchant that sells one, it %s%s."):format(
                n, n == 1 and "item" or "items", how, limit and (", spending at most " .. RS.MoneyText(limit) .. " a visit") or "")
        end,
    },
    {
        key = "groupCheck", page = "sharing", label = "Group version check", off = "announcing your TwichUI version to your group",
        available = function() return R.Group ~= nil end,
        scope = function() return "In a group, sends your TwichUI version number over the hidden addon channel, and tells you if someone's is newer. Nothing is written in chat." end,
    },
    {
        key = "partyPins", page = "pins", label = "Party pins", off = "sharing party pins with your group",
        available = function() return R.PinSync ~= nil end,
        scope = function() return "Pins you mark for your party reach members who have TwichUI, over the hidden addon channel. Nothing is written in chat." end,
    },
    {
        key = "quietLogin", page = "overview", label = "Hide addon welcome messages", off = "hiding other addons' \"loaded\" lines at login",
        scope = function() return "Hides the \"loaded\" and \"type /command\" lines other addons print at login. Errors and warnings still show." end,
    },
}

-- Where each page is named for a link.
A.PAGE_LABEL = { qol = "Quality of life", mage = "Mage", sharing = "Sharing", pins = "Party pins", overview = "Home",
    restock = "Vendor restocking" }

-- { on = { entry... }, off = { entry... }, pages = { key... } }, each entry { key, label, page, text }.
-- `text` is the scope for what is on and the short phrase for what is off. `pages` are the settings pages that
-- hold something listed, in order, once each.
function A.Summary()
    local out = { on = {}, off = {}, pages = {} }
    local mage = IsMage()
    local seen = {}
    for _, e in ipairs(A.ENTRIES) do
        if (not e.mage or mage) and (not e.available or e.available()) then
            local on
            if e.on then on = e.on() else on = On(e.key) end
            local item = { key = e.key, label = e.label, page = e.page }
            if on then
                local ok, text = pcall(e.scope)
                item.text = ok and text or ""
                out.on[#out.on + 1] = item
            else
                item.text = e.off
                out.off[#out.off + 1] = item
            end
            if not seen[e.page] then
                seen[e.page] = true
                out.pages[#out.pages + 1] = e.page
            end
        end
    end
    return out
end
