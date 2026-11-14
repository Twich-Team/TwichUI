-- A8: selling evidence. Competition supplies the price; historical values only qualify it.
-- Pure over a Facts snapshot. No auction operations and no fee assumptions.
local W = TwichUI.Workshop
local S = { POLICY = 1 }
W.Sell = S
local function Has(list, code)
    for _, v in ipairs(list or {}) do if v == code then return true end end
    return false
end
function S.Suggest(item, qty, opt)
    opt = opt or {}
    local r = { role = "suggestion", policy = S.POLICY, item = item, qty = qty, state = "uncertain", reasons = {}, flags = {} }
    if not W.Int(item, 1, W.MAX_ID) or not W.Int(qty, 1, W.MAX_ID) then r.reasons[1] = "Invalid item or quantity." return r end
    if opt.strategy and opt.strategy ~= "match" then r.reasons[1] = "That posting strategy is unavailable." return r end
    local f = opt.facts or W.Facts.Of(item, opt)
    local c, q = f.comp, f.quality
    r.at, r.age, r.market, r.provenance = f.at, f.age, f.key, "local"
    r.quality, r.competition = q and q.level or "none", c
    if not c or not c.competing then
        r.state = "nocompetition"
        r.reasons[1] = "No reliable competing listing is available."
        return r
    end
    local blocked = f.variant or not q or (q.level ~= "good" and q.level ~= "fair") or not c.complete or c.cut
        or not c.age or c.age > W.Valuation.FAIR_AGE or Has(c.notes, "mixedvariants")
    for _, reason in ipairs(q and q.reasons or {}) do
        if reason.code == "farbelow" or reason.code == "mixedvariants" then blocked = true end
        r.reasons[#r.reasons + 1] = reason.text
    end
    if blocked then
        if #r.reasons == 0 then r.reasons[1] = "Current listings are incomplete or too old to suggest a price." end
        return r
    end
    r.state, r.price, r.ahead = "ok", c.competing, c.ahead
    if f.mval and f.mval.value > 1.5 * r.price then r.flags[#r.flags + 1] = "belowusual" end
    if f.hist and r.price > 1.5 * f.hist.value then r.flags[#r.flags + 1] = "aboveusual" end
    return r
end
function S.Proceeds(price, qty)
    local r = { role = "proceeds", sold = "notguaranteed", beforeFees = true,
        missing = { "Auction House fees are unknown.", "Deposits are unknown.", "A listing is not a guaranteed sale." } }
    price, qty = W.Int(price, 1, W.Prices.MAX_COPPER), W.Int(qty, 1, W.MAX_ID)
    if not price or not qty or price > W.Prices.MAX_COPPER / qty then r.state = "unknown" return r end
    r.state, r.gross, r.qty, r.unit = "ok", price * qty, qty, price
    return r
end
