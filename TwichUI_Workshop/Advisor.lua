-- Supported and tentative advice over one evidence snapshot.
-- Decide has no planning, history decoding, inventory reads, saved writes or frames.
-- Gain/SetGain are the small existing-account preference adapter; callers snapshot it.
local W = TwichUI.Workshop
local A = { POLICY = 6, API = 1 }
W.Advisor = A
A.LABEL = { auction = "Recommended: Auction", vendor = "Recommended: Vendor", craft = "Keep for crafting plan",
    disenchant = "Consider disenchanting", watch = "Watch this item", unknown = "Not enough data to compare" }
A.SHORT = { auction = "Auction", vendor = "Vendor", craft = "Craft", disenchant = "Disenchant", watch = "Watch", unknown = "Limited data" }
A.EVIDENCE = { strong = "Strong evidence", limited = "Limited evidence", insufficient = "Known values and alternatives below" }
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
    if W.Junk then W.Junk.Request() end
    return true
end
function A.Decide(item, ctx)
    ctx = ctx or {}
    local qty = W.Int(ctx.qty, 0, W.MAX_ID)
    local r = { role = "advice", api = A.API, policy = A.POLICY, item = item, qty = qty, action = "unknown", evidence = "insufficient",
        reasons = {}, missing = {}, alternatives = {}, facts = ctx.facts or {nomarket=true}, crafting = ctx.crafting,
        provenance = { source = "local", at = ctx.facts and ctx.facts.at, market = ctx.facts and ctx.facts.key } }
    local function Reason(s) r.reasons[#r.reasons + 1] = s end
    local function Unknown(text, reason) r.unknownText=text;Reason(reason) end
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
    if not W.Int(item, 1, W.MAX_ID) then Unknown("Item data unavailable", "The item identity is unavailable.")
    elseif qty == nil then Unknown("Bag quantity unavailable", "The available bag quantity is unknown.")
    elseif qty == 0 then Unknown("No bag copies", "No copies are currently available in your bags.")
    elseif ctx.crafting and (ctx.crafting.reserved or 0) > 0 then
        r.action, r.evidence = "craft", "strong"
        Reason("This material is needed by your active crafting plan.")
        Reason("Keep the required quantity before considering a sale.")
    elseif ctx.pendingPlan then Unknown("Check crafting plan", "Crafting plan dependencies are not fully checked yet.")
    elseif eligible == false then
        if sell and sell > 0 then r.action, r.evidence = "vendor", "strong" end
        r.unknownText="No vendor sale value"
        Reason("This item cannot be listed on the Auction House.")
    elseif eligible == nil then Unknown("Check item binding", "Auction eligibility is not known.")
    elseif ctx.variant then Unknown("Check variant price", "This variant is not priced separately.")
    elseif s.state == "ok" and sell ~= nil then
        local gain = W.Int(ctx.minGain, 0, W.Prices.MAX_COPPER) or 0
        if s.price >= sell * 1.5 and s.price - sell >= gain and s.price > sell then
            r.action = "auction"
            Reason("Current listings support a higher gross value than vendoring.")
            Reason("Match the competing tier; a sale and net gain are not guaranteed.")
        elseif sell > 0 then
            r.action = "vendor"
            Reason(s.price <= sell and "Vendor value meets or exceeds the gross competing listing." or "The listing gain does not meet your worthwhile-gain preference and margin.")
        else Unknown("Auction gain below preference", "The auction gain does not meet your worthwhile-gain preference.")
        end
        r.evidence = r.action == "unknown" and "insufficient" or (s.quality == "good" and "strong" or "limited")
    else
        local observed=W.Sell.Observation(r.facts)
        local gain=W.Int(ctx.minGain,0,W.Prices.MAX_COPPER) or 0
        if observed and sell~=nil and observed.value>=sell*1.5 and observed.value-sell>=gain and observed.value>sell then
            r.action,r.level,r.evidence,r.observed="auction","tentative","limited",observed
            Reason("Current listings suggest auctioning may be worthwhile; evidence is limited.")
            for _,why in ipairs(observed.reasons) do Reason(why) end
            Reason("The observed listing is not a suggested posting price; a sale is not guaranteed.")
            local alt=r.alternatives[2]
            alt.state,alt.value,alt.note="observed",observed.value,"Observed current listing per item, not a suggested posting price. Limited evidence; fees and sale outcome unknown."
        elseif observed and sell~=nil then
            r.observed=observed
            if sell>0 then
                r.action,r.level,r.evidence="vendor","tentative","limited"
                Reason("The observed auction gain does not meet your worthwhile-gain preference and margin; vendoring is the simpler option.")
            else Unknown("Auction gain below preference", "The auction gain does not meet your worthwhile-gain preference.") end
            for _,why in ipairs(observed.reasons) do Reason(why) end
            local alt=r.alternatives[2]
            alt.state,alt.value,alt.note="observed",observed.value,"Observed current listing per item, not a suggested posting price. Limited evidence; fees and sale outcome unknown."
        elseif r.facts.recent and r.facts.recent.source=="market_server" and sell~=nil
            and W.Int(r.facts.recent.value,1,W.Prices.MAX_COPPER) then
            r.level,r.evidence="tentative","limited"
            r.reference=r.facts.recent
            r.provenance={source="market_server",at=r.reference.at,generation=r.reference.generation,market=r.facts.key}
            if r.reference.value>=sell*1.5 and r.reference.value-sell>=gain and r.reference.value>sell then
                r.action="auction"
                Reason("Market server references favor auctioning over vendoring. Check current listings before choosing a posting price.")
            elseif sell>0 then
                r.action="vendor"
                Reason("The Market reference gain does not meet your worthwhile-gain preference and margin; vendoring is the simpler option.")
            else Unknown("Auction gain below preference", "The Market reference gain does not meet your worthwhile-gain preference.")
            end
            r.alternatives[2].state,r.alternatives[2].value,r.alternatives[2].note="reference",r.reference.value,"Market reference estimate; no live competing offer or suggested posting price."
        elseif sell==nil then Unknown("Vendor value unavailable", "Vendor sell value is unknown.")
        elseif r.facts.referenceWhy=="loading" then Unknown("Loading Market price", "The item's Market partition is still being validated.")
        else Unknown("Auction price unavailable", "No supported current auction price is available; sync Market data or scan the Auction House.") end
        for _, why in ipairs(s.reasons or {}) do r.missing[#r.missing + 1] = why end
    end
    local de = r.disenchant
    r.disenchantUnpriced=ctx.disenchant==true and de.state=="unknown"
    local auctionValue=s.state=="ok" and s.price or r.observed and r.observed.value or r.reference and r.reference.value
    local canChoose=r.action~="craft" and not ctx.pendingPlan and W.Int(item,1,W.MAX_ID) and qty and qty>0
    -- Compare the priced options we actually have. An unpriced suffix never
    -- supplies an auction quote or blocks known vendor/disenchant alternatives.
    if canChoose and r.action=="unknown" then
        if eligible==true and not ctx.variant and not auctionValue then
            local observed=W.Sell.Observation(r.facts)
            local reference=r.facts.recent
            if observed then r.observed=observed;auctionValue=observed.value
            elseif reference and reference.source=="market_server" and W.Int(reference.value,1,W.Prices.MAX_COPPER) then
                r.reference=reference;auctionValue=reference.value
            end
        end
        if sell and sell>0 then
            r.action,r.level,r.evidence="vendor","tentative","limited"
            Reason("Vendor is the available priced sale option.")
        elseif sell==nil and eligible==true and not ctx.variant and auctionValue then
            r.action,r.level,r.evidence="auction","tentative","limited"
            Reason("Auction is the available priced sale option.")
        end
    end
    if canChoose and de.state == "ok" and W.Int(de.expectedGross,1,W.Prices.MAX_COPPER) then
        local ceiling=auctionValue
        if sell~=nil then ceiling=math.max(sell,ceiling or 0) end
        local gain = W.Int(ctx.minGain, 0, W.Prices.MAX_COPPER) or 0
        if ceiling==nil or de.expectedGross > ceiling and de.expectedGross >= ceiling * 1.5 and de.expectedGross - ceiling >= gain then
            r.action, r.evidence = "disenchant", "limited"
            if de.outcomeReference then r.level="tentative" end
            r.reasons = { "Estimated material value favors disenchanting over the available sale values.",de.why or "Estimated material value." }
            r.provenance={source="disenchant",outcomes=de.source,prices=de.priceSource}
            r.proceeds=nil -- the previous auction comparison is not disenchant proceeds
        end
    end
    if ctx.disenchant and de.state == "unknown" then r.missing[#r.missing + 1] = de.why end
    if de.state=="ok" and de.outcomeReference and r.action~="unknown" and r.action~="craft" then
        r.level,r.evidence="tentative","limited"
    end
    -- A local fallback is useful evidence, but cannot finalize a sale while an
    -- applicable server quote (including a disenchant material) is in flight.
    -- Keep dependencies even after completion so consumers can invalidate only
    -- the held items affected by a later price change. No history is required.
    r.dependencies = {}
    local auctionPending = eligible ~= false and not ctx.variant and r.facts.referenceWhy == "loading"
    if eligible ~= false and not ctx.variant and W.Int(item, 1, W.MAX_ID) then r.dependencies[item] = true end
    for dependency in pairs(de.dependencies or {}) do r.dependencies[dependency] = true end
    r.pending = canChoose and (auctionPending or de.pending == true) or false
    r.pricingState = r.pending and "pending" or "ready"
    if r.pending then
        r.action, r.level, r.evidence, r.proceeds = "unknown", "insufficient", "insufficient", nil
        r.unknownText = auctionPending and "Loading Market price" or "Loading disenchant material prices"
        Reason(auctionPending and "The item's Market price is still loading." or "Disenchant material prices are still loading.")
    end
    if r.action=="unknown" and eligible==false and r.disenchantUnpriced and not r.pending then r.unknownText="Check disenchant value" end
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
    r.level=r.action=="unknown" and "insufficient" or r.level or "supported"
    r.text = r.action=="unknown" and (r.unknownText or A.LABEL.unknown) or r.level=="tentative" and
        ((r.reference and "Market comparison: " or "Possible: ")..A.TOOLTIP[r.action]) or A.LABEL[r.action]
    r.evidenceText = A.EVIDENCE[r.evidence]
    return r
end

A.TOOLTIP = {vendor="Vendor",auction="Auction",disenchant="Disenchant",craft="Keep for crafting",watch="Watch",unknown="Not enough data"}
function A.Short(r)
    local text=A.SHORT[r.action] or A.SHORT.unknown
    if r.level~="tentative" then return text end
    return r.reference and text.." (Market)" or "Possible "..text
end
function A.Tooltip(r)
    if r.action=="vendor" or r.action=="auction" or r.action=="disenchant" then return "Workshop: "..A.TOOLTIP[r.action] end
end
