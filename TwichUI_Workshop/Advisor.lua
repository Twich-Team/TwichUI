-- A8 policy v1: deterministic advice over one immutable evidence snapshot.
-- Decide has no planning, history decoding, inventory reads, saved writes or frames.
-- Gain/SetGain are the small existing-account preference adapter; callers snapshot it.
local W = TwichUI.Workshop
local A = { POLICY = 1, API = 1 }
W.Advisor = A
A.LABEL = { auction = "Consider selling on Auction House", vendor = "Sell to Vendor", craft = "Keep for crafting plan",
    disenchant = "Consider disenchanting", watch = "Watch this item", unknown = "Insufficient data" }
A.SHORT = { auction = "Auction", vendor = "Vendor", craft = "Plan", disenchant = "Disenchant", watch = "Watch", unknown = "Unknown" }
A.EVIDENCE = { strong = "Strong evidence", limited = "Limited evidence", insufficient = "Insufficient data" }
-- Zero adds no universal copper threshold; the 1.5x vendor margin still applies.
function A.Gain()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local view = type(ws) == "table" and ws.view
    return type(view) == "table" and W.Int(view.advisorGain, 0, W.Prices.MAX_COPPER) or 0
end
function A.SetGain(value)
    value = W.Int(value, 0, W.Prices.MAX_COPPER)
    if not value or W.Queue.Held() or type(TwichUIDB) ~= "table" then return false end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then ws = { v = W.SAVED_VERSION }; TwichUIDB.workshop = ws end
    if type(ws.view) ~= "table" then ws.view = {} end
    ws.view.advisorGain = value
    return true
end
function A.Decide(item, ctx)
    ctx = ctx or {}
    local qty = W.Int(ctx.qty, 0, W.MAX_ID)
    local r = { role = "advice", api = A.API, policy = A.POLICY, item = item, qty = qty, action = "unknown", evidence = "insufficient",
        reasons = {}, missing = {}, alternatives = {}, facts = ctx.facts or {nomarket=true}, crafting = ctx.crafting,
        provenance = { source = "local", at = ctx.facts and ctx.facts.at, market = ctx.facts and ctx.facts.key } }
    local function Reason(s) r.reasons[#r.reasons + 1] = s end
    local sell = W.Int(ctx.sell, 0, W.Prices.MAX_COPPER)
    r.vendor = { state = sell == nil and "unknown" or (sell == 0 and "unavailable" or "ok"), value = sell }
    local eligible
    if ctx.bound == true or ctx.bindType == 1 or ctx.bindType == 4 then eligible = false
    elseif ctx.bindType == 0 or ctx.bindType == 2 or ctx.bindType == 3 then eligible = true end
    r.eligible = eligible
    r.disenchant = ctx.disenchantValue or { state = "unknown", why = "Disenchant outcome data is unverified." }
    local s = W.Sell.Suggest(item, qty and math.max(1, qty) or 1, { facts = r.facts, market = ctx.market, now = ctx.now, variant = ctx.variant })
    r.suggestion = s
    if eligible == false then s = { state = "unavailable" }; r.suggestion = s end
    if ctx.variant then s = { state = "uncertain" }; r.suggestion = s end
    r.proceeds = s.price and qty and qty > 0 and W.Sell.Proceeds(s.price, qty) or nil
    r.alternatives = {
        { action = "vendor", state = r.vendor.state, value = sell, note = "Known sell value per item." },
        { action = "auction", state = eligible == true and s.state or (eligible == false and "unavailable" or "unknown"), value = s.price,
          note = eligible == false and "This item cannot be auctioned." or "Gross listing per item; fees and sale outcome unknown." },
        { action = "craft", state = ctx.crafting and #(ctx.crafting.uses or {}) > 0 and "available" or "unknown", note = "Only this character's known recipes are considered." },
        { action = "disenchant", state = r.disenchant.state, value = r.disenchant.expectedGross, note = r.disenchant.why },
        { action = "watch", state = "choice", note = "Refresh manually; future price direction is unknown." },
    }
    if not W.Int(item, 1, W.MAX_ID) then Reason("The item identity is unavailable.")
    elseif qty == nil then Reason("The available bag quantity is unknown.")
    elseif qty == 0 then Reason("No copies are currently available in your bags.")
    elseif ctx.crafting and (ctx.crafting.reserved or 0) > 0 then
        r.action, r.evidence = "craft", "strong"
        Reason("This material is needed by your active crafting plan.")
        Reason("Keep the required quantity before considering a sale.")
    elseif ctx.pendingPlan then Reason("Crafting plan dependencies are not fully checked yet.")
    elseif eligible == false then
        if sell and sell > 0 then r.action, r.evidence = "vendor", "strong" end
        Reason("This item cannot be listed on the Auction House.")
    elseif eligible == nil then Reason("Auction eligibility is not known.")
    elseif ctx.variant then Reason("This variant is not priced separately.")
    elseif s.state == "ok" and sell ~= nil then
        local gain = W.Int(ctx.minGain, 0, W.Prices.MAX_COPPER) or 0
        if s.price >= sell * 1.5 and s.price - sell >= gain and s.price > sell then
            r.action = "auction"
            Reason("Current listings support a higher gross value than vendoring.")
            Reason("Match the competing tier; a sale and net gain are not guaranteed.")
        elseif sell > 0 then
            r.action = "vendor"
            Reason(s.price <= sell and "Vendor value meets or exceeds the gross competing listing." or "The listing gain does not meet your worthwhile-gain preference and margin.")
        end
        r.evidence = r.action == "unknown" and "insufficient" or (s.quality == "good" and "strong" or "limited")
    else
        Reason("No reliable Auction House posting price is available.")
        for _, why in ipairs(s.reasons or {}) do r.missing[#r.missing + 1] = why end
    end
    local de = r.disenchant
    if r.action ~= "craft" and not ctx.pendingPlan and W.Int(item,1,W.MAX_ID) and qty and qty > 0 and sell ~= nil and de.state == "ok" and de.expectedGross
        and (eligible == false or (eligible == true and s.state == "ok")) then
        local ceiling = math.max(sell, s.price or 0)
        local gain = W.Int(ctx.minGain, 0, W.Prices.MAX_COPPER) or 0
        if de.expectedGross > ceiling and de.expectedGross >= ceiling * 1.5 and de.expectedGross - ceiling >= gain then
            r.action, r.evidence = "disenchant", "limited"
            r.reasons = { "Verified outcomes support a higher expected material value.", "Disenchant outcomes and material sales are uncertain; this is not guaranteed proceeds." }
        end
    end
    if ctx.disenchant and de.state == "unknown" then r.missing[#r.missing + 1] = de.why end
    if sell == nil then r.missing[#r.missing + 1] = "Vendor sell value is unknown." end
    if ctx.crafting and #(ctx.crafting.uses or {}) > 0 and r.action ~= "craft" then
        Reason("Known recipes use this item; compare their crafting strategy before selling.")
    end
    if s.price then
        r.missing[#r.missing + 1] = "Fees, deposits and sale likelihood are unknown."
        for _, flag in ipairs(s.flags or {}) do
            if flag == "belowusual" then Reason("Current competition is below the historical market reference.") end
            if flag == "aboveusual" then Reason("Competition is above the historical reference; it may not sell at this price.") end
        end
    end
    r.text, r.evidenceText = A.LABEL[r.action], A.EVIDENCE[r.evidence]
    return r
end

A.TOOLTIP = {vendor="Vendor",auction="Auction",disenchant="Disenchant",craft="Keep for crafting",watch="Watch",unknown="Insufficient data"}
function A.Tooltip(r) return "Workshop: " .. (A.TOOLTIP[r.action] or A.TOOLTIP.unknown) end
