-- TwichUI Workshop: "What's it worth?" (vendor, auction and disenchant for ONE item; pure: no game calls, no frames)
-- WorthTip.lua reads the game and adds the lines to an item tooltip; this file decides what is known and what to suggest (Evaluate,
-- Recommend); WorthLayout.lua decides which lines are shown, in what order, and the words of each.
--
-- THE RULES (docs/workshop.md, "What's it worth?"):
--   * every value is for ONE item, at the same basis for every option;
--   * Vendor is the item's own sell value; Auction is the cheapest buyout listing the newest scan saw (Prices.lua), minus the auction
--     house's cut ONLY when that cut is confirmed (Prices.CUT): until then it is "before fees" and no after-fees winner is claimed;
--   * Disenchant is NOT estimated: there is no legally reusable, Forever-appropriate table of outcomes (docs/workshop.md, "Disenchant
--     outcome data"), so a disenchantable-looking item shows "no data" and, because that competing option is unknown, no best option
--     is suggested for it ("Disenchant value unknown"). Nothing here invents a chance or a quantity;
--   * a missing price or an unknown outcome is never zero; an action that cannot be done (a bound item cannot be auctioned) is
--     "unavailable", which is not the same as an unknown estimate: only an UNKNOWN competitor blocks a suggestion;
--   * a variant (random properties, bonus IDs, a changed item level) is never priced from the base item's listings: the scan keeps
--     one price per item id, so its estimate is unavailable and says so.
--

local R = TwichUI
local W = R.Workshop
local PR = W.Prices
local Int = W.Int
local WO = {}
W.Worth = WO

-- Item class and quality that MIGHT disenchant. This is not a rule of the game, only the reason a disenchant option is "relevant"
-- (so that its missing data keeps a best option from being named); the client offers no way to ask. Quality 2..4 = uncommon to epic.
WO.DE_CLASSES = { [2] = true, [4] = true }   -- Weapon, Armor
WO.DE_QUALITY_MIN, WO.DE_QUALITY_MAX = 2, 4

-- GetItemInfo's bindType
local BIND_NONE, BIND_PICKUP, BIND_EQUIP, BIND_USE, BIND_QUEST = 0, 1, 2, 3, 4

---------------------------------------------------------------------------
-- What an item link says about its variant
---------------------------------------------------------------------------
-- nil for the plain item, or "suffix" (random properties, "of the Bear") / "bonus" (bonus IDs). The auction scan keeps one price per
-- item id, so a variant's price would be the cheapest of unrelated versions.
function WO.LinkVariant(link)
    if type(link) ~= "string" then return nil end
    local body = link:match("|Hitem:([^|]*)|h") or link:match("^item:([^|]*)")
    if not body then return nil end
    local f = {}
    for part in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
    -- item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:level:spec:modifiers:context:numBonusIDs:...
    local suffix = tonumber(f[7])
    if suffix and suffix ~= 0 then return "suffix" end
    local bonus = tonumber(f[13])
    if bonus and bonus > 0 then return "bonus" end
    return nil
end

-- Shirts and tabards are armour that does not disenchant (the game's rule, also stated by NaowhForever_Professions' README; not verified here)
WO.DE_NEVER = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

function WO.DisenchantRelevant(f)
    local q, c = Int(f.quality, 0, 20), Int(f.classID, 0, 100)
    if type(f.equipLoc) == "string" and WO.DE_NEVER[f.equipLoc] then return false end
    return q ~= nil and c ~= nil and WO.DE_CLASSES[c] == true and q >= WO.DE_QUALITY_MIN and q <= WO.DE_QUALITY_MAX
end

-- true (it can be listed), false and why ("bound", "quest"), or nil when the client evidence doesn't say
local function AuctionEligible(f)
    if f.bound == true then return false, "bound" end
    local b = Int(f.bindType, 0, 20)
    if b == BIND_PICKUP then return false, "bound" end
    if b == BIND_QUEST then return false, "quest" end
    if b == BIND_NONE or b == BIND_EQUIP or b == BIND_USE then return true end
    return nil
end

---------------------------------------------------------------------------
-- The comparison
---------------------------------------------------------------------------
-- f (what the game was asked, already checked by the caller):
--   sell (vendor sell value of one item, copper; 0 = no value), quality, classID, bindType, bound (true/false/nil: this item is soulbound now),
--   variant (WO.LinkVariant's answer or a reason of the caller's), market ({ label, side, at, complete } or nil: the saved prices),
--   price (Prices.Lookup's answer for the item id, or nil), rate (the confirmed cut or nil), now.
-- Returns r:
--   vendor      { state = "ok", value } | { state = "none" } (no sell value) | { state = "unknown" }
--   auction     { state = "ok", gross, cut, net, value, beforeFees, at, age, old, complete }
--               | { state = "unavailable", why = "bound"|"quest" }
--               | { state = "unknown", why = "bind"|"variant"|"nomarket"|"noprice" }
--   disenchant  nil (not relevant) | { state = "unknown", why = "nodata" }
-- WO.Recommend(r) turns that into the one short recommendation; WorthLayout.lua turns both into the tooltip's lines.
function WO.Evaluate(f)
    local r = {}
    local sell = Int(f.sell, 0, PR.MAX_COPPER)
    if sell == nil then r.vendor = { state = "unknown" }
    elseif sell == 0 then r.vendor = { state = "none" }
    else r.vendor = { state = "ok", value = sell } end

    local can, why = AuctionEligible(f)
    if can == false then
        r.auction = { state = "unavailable", why = why }
    elseif can == nil then
        r.auction = { state = "unknown", why = "bind" }
    elseif f.variant then
        r.auction = { state = "unknown", why = "variant", variant = f.variant }
    elseif not f.market then
        r.auction = { state = "unknown", why = "nomarket" }
    elseif not f.price then
        r.auction = { state = "unknown", why = "noprice" }
    else
        local gross = f.price.price
        local a = { state = "ok", gross = gross, at = f.price.at, complete = f.price.complete == true }
        a.age = PR.Age(a.at, f.now)
        a.old = a.age ~= nil and a.age > PR.OLD_AFTER
        if type(f.rate) == "number" and f.rate >= 0 and f.rate < 1 then
            a.cut = PR.Cut(gross, f.rate)
            a.rate = f.rate
            a.net = gross - a.cut
            a.value = a.net
        else
            a.beforeFees = true
            a.value = gross   -- an upper bound: the cut only lowers it
        end
        r.auction = a
    end

    if WO.DisenchantRelevant(f) then r.disenchant = { state = "unknown", why = "nodata" } end

    return r
end

---------------------------------------------------------------------------
-- The recommendation
---------------------------------------------------------------------------
-- Which action has the highest ESTIMATED proceeds, when the evidence proves one; otherwise the short reason none is named. Estimates, not
-- sales: nothing here says an item will sell. An action that cannot be done (a bound item cannot be auctioned, an item without a sell value
-- cannot be sold to a vendor) is not an option; an action whose value is merely not known IS a competitor, and blocks a winner. The
-- auction value before the cut is an upper bound (the cut only lowers it), so it can LOSE to an exact value but never win.
--
-- Returns { kind, text, tone } or nil (nothing worth saying: fewer than two real options and nothing unknown):
--   kind  "pick"      one option wins (text "Suggested: Vendor" / "Suggested: Auction house" / "Suggested: Disenchant"), pick = its key
--         "beats"     vendor and auction compare, but disenchant is unknown, so it is only a qualified comparison ("Vendor beats auction (disenchant unknown)")
--         "tie"       the best estimates are equal ("Similar value")
--         "fee"       the auction value is before the cut and may be higher than the others: nothing is proven
--         "more"      a competing price is missing ("More prices needed"); "variant" / "bind": the auction value cannot be known
--         "disenchant" the disenchant value is unknown ("Disenchant value unknown")
--   tone  "good" (a pick or a proven comparison) or "quiet"
local LABEL = { vendor = "Vendor", auction = "Auction house", disenchant = "Disenchant" }
local SHORT = { vendor = "vendor", auction = "auction", disenchant = "disenchant" }

local function AuctionTags(a)
    local tags = {}
    if a and a.state == "ok" then
        if a.old then tags[#tags + 1] = "old prices" end
        if not a.complete then tags[#tags + 1] = "partial scan" end
    end
    return tags
end

local function Tagged(text, tags)
    if #tags == 0 then return text end
    return text .. " (" .. table.concat(tags, ", ") .. ")"
end

-- The winner among the options with a value, or the reason there is none. Exact values: vendor, disenchant, and an auction value
-- after a confirmed cut. An auction value before the cut is only a ceiling.
local function Compare(r)
    local exact, n = {}, 0
    local function Add(key, o)
        if o and o.state == "ok" and type(o.value) == "number" then exact[key] = o.value; n = n + 1 end
    end
    Add("vendor", r.vendor)
    Add("disenchant", r.disenchant)
    local a = r.auction
    local ceiling
    if a and a.state == "ok" then
        if a.beforeFees then ceiling = a.value; n = n + 1 else exact.auction = a.value; n = n + 1 end
    end
    if n < 2 then return nil end
    local bestKey, bestVal, tied
    for _, key in ipairs({ "vendor", "auction", "disenchant" }) do
        local v = exact[key]
        if v then
            if bestVal == nil or v > bestVal then bestKey, bestVal, tied = key, v, false
            elseif v == bestVal then tied = true end
        end
    end
    if ceiling then
        -- the best exact value must reach the ceiling to be proven better than the auction after any cut
        if bestVal == nil or bestVal < ceiling then return "fee" end
    end
    if tied then return "tie" end
    return "pick", bestKey
end

function WO.Recommend(r)
    local v, a, d = r.vendor, r.auction, r.disenchant
    local good = function(kind, text, key) return { kind = kind, text = text, tone = "good", pick = key } end
    local quiet = function(kind, text) return { kind = kind, text = text, tone = "quiet" } end

    -- a competing PRICE that is not known comes first: more prices fix it
    if a.state == "unknown" then
        if a.why == "variant" then return quiet("variant", "No suggestion: this variant isn't priced") end
        if a.why == "bind" then return quiet("bind", "No suggestion: can't tell if it can be listed") end
        return quiet("more", "More prices needed")
    end
    if v.state == "unknown" then return quiet("more", "More prices needed") end

    local tags = AuctionTags(a)
    local outcome, key = Compare(r)
    if d and d.state == "unknown" then
        -- disenchant is a competitor with no value: only a qualified comparison of vendor and auction can be proven, and it says so
        if outcome == "pick" then
            tags[#tags + 1] = "disenchant unknown"
            return good("beats", Tagged(key == "vendor" and "Vendor beats auction" or "Auction beats vendor", tags), key)
        end
        return quiet("disenchant", Tagged("Disenchant value unknown", tags))
    end
    if outcome == nil then return nil end
    if outcome == "fee" then return quiet("fee", "No suggestion: auction fee unknown") end
    if outcome == "tie" then return quiet("tie", Tagged("Similar value", tags)) end
    return good("pick", Tagged("Suggested: " .. LABEL[key], tags), key)
end
