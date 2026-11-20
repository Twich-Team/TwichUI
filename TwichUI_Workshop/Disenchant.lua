-- Expected material value. Bundled Forever brackets use explicitly labeled
-- Classic yield estimates; verified snapshots retain their separate admission.
local W = TwichUI.Workshop
local DE = { API = 1 }
W.Disenchant = DE
local REFERENCE = {} -- only ForItem can admit the bundled, reviewed reference
function DE.Eligibility(f)
    if not W.Worth.DisenchantRelevant(f) then return false, "This item is not a supported disenchant candidate." end
    local data=W.DisenchantData
    if data and data.excluded and data.excluded[f.item] then return false,"This item cannot be disenchanted." end
    if data and data.special and data.special[f.item] then return nil,"This item has special disenchant rewards; ordinary yields do not apply." end
    if f.canDisenchant == false then return false, "Your character does not know Disenchant." end
    if f.canDisenchant ~= true then return nil, "Your character's Disenchant ability is unknown." end
    return nil, "This item's disenchant eligibility and required skill are unverified."
end
function DE.Evaluate(f, snapshot)
    local eligible, why = DE.Eligibility(f)
    local r = { role = "disenchant", state = eligible == false and "unavailable" or "unknown", why = why, expected = true }
    if eligible == false then return r end
    local reference=snapshot and snapshot.reference==REFERENCE
    local verified=snapshot and snapshot.verified == true and snapshot.client == "forever"
    if not ((reference or verified) and snapshot.item == f.item and type(snapshot.source) == "string"
        and snapshot.source ~= "" and snapshot.eligible == true and f.canDisenchant == true) then return r end
    local skill, required = W.Int(f.enchantSkill, 0, 1000), W.Int(snapshot.requiredSkill, 0, 1000)
    -- The bundled bracket data carries no per-item skill requirement. A known
    -- Disenchant ability is required; do not invent a Classic/TBC rank rule.
    if not reference then
        if not skill or not required then r.why = "Enchanting skill requirements are unknown." return r end
        if skill < required then r.state, r.why = "unavailable", "Your Enchanting skill is too low." return r end
    end
    local outcomes = snapshot.outcomes
    if type(outcomes) ~= "table" or #outcomes == 0 or #outcomes > 64 then r.why = "No verified disenchant outcomes are available." return r end
    local probability, value = 0, 0
    for _, o in ipairs(outcomes) do
        if type(o) ~= "table" or not W.Finite(o.p) or o.p <= 0 or o.p > 1 or type(o.materials) ~= "table" or #o.materials == 0 or #o.materials > 16 then
            r.why = "Disenchant outcome data is incomplete." return r
        end
        probability = probability + o.p
        for _, m in ipairs(o.materials) do
            if type(m) ~= "table" or not W.Int(m.item,1,W.MAX_ID) or not W.Finite(m.qty) or m.qty <= 0 or m.qty > W.MAX_ID then
                r.why = "Disenchant material quantities are unknown." return r
            end
            local p = snapshot.values and snapshot.values[m.item]
            if not (p and W.Int(p.value,1,W.Prices.MAX_COPPER) and (p.quality == "good" or p.quality == "fair"
                or reference and p.quality=="limited" and (p.source=="market_server" or p.source=="local"))) then
                r.why = "A reliable material listing value is missing." return r
            end
            value = value + o.p * m.qty * p.value
        end
    end
    if math.abs(probability - 1) > 0.000001 or value > W.Prices.MAX_COPPER then r.why = "Disenchant outcomes do not form a complete supported estimate." return r end
    r.state, r.expectedGross, r.source, r.why = "ok", math.floor(value), snapshot.source, "Expected material listing value before fees; outcomes and sales are uncertain."
    r.value=r.expectedGross
    if reference then
        r.outcomeReference=true;r.quality="limited"
        r.why="Expected material value using average quantities and current material prices."
    end
    return r
end

-- Existing Forever profession APIs (Observe.Skills/Chronicle) supply rank and
-- skill-line identity. Spell availability wins when the client supplies it.
function DE.Character()
    local can,rank
    if C_SpellBook and C_SpellBook.ContainsAnyDisenchantSpell then can=W.Plain(C_SpellBook.ContainsAnyDisenchantSpell()) end
    if GetProfessions and GetProfessionInfo then
        local prof={GetProfessions()}
        for i=1,6 do
            local index=W.Int(prof[i],1,1000)
            if index then
                local _,_,value,_,_,_,id=GetProfessionInfo(index)
                if W.Plain(id)==333 then rank=W.Int(value,0,1000);break end
            end
        end
        if can==nil then can=rank~=nil and rank>0 end
    end
    if can~=true and can~=false then can=nil end
    return {canDisenchant=can,enchantSkill=rank}
end

-- At most three material quotes, no saved writes, scans or planner work. Price
-- caching and asynchronous completion belong to Pricing, including local fallback.
function DE.ForItem(f,opt)
    opt=opt or {}
    local input={item=f.item,quality=f.quality,classID=f.classID,equipLoc=f.equipLoc,
        canDisenchant=f.canDisenchant,enchantSkill=f.enchantSkill}
    if not W.Int(input.item,1,W.MAX_ID) then return {state="unknown",why="The item identity is unavailable."} end
    if not W.Worth.DisenchantRelevant(input) then return {state="unavailable",why="This item does not use a supported disenchant bracket."} end
    if input.canDisenchant==nil then
        local character=DE.Character();input.canDisenchant,input.enchantSkill=character.canDisenchant,character.enchantSkill
    end
    local unavailable=DE.Evaluate(input)
    if unavailable.state=="unavailable" or input.canDisenchant~=true then return unavailable end
    local data=W.DisenchantData
    if not data or data.special[input.item] then return unavailable end
    local level=W.Int(f.itemLevel,1,1000)
    if not level or f.variant and not f.actualLevel then unavailable.why="The actual item level is unavailable.";return unavailable end
    local row=data.Find(input.classID,input.quality,level)
    if not row or row.unconfirmed then unavailable.why="No supported yield estimate exists for this item bracket.";return unavailable end
    local snapshot={reference=REFERENCE,item=input.item,source="DisenchantForever / Classic yield reference",eligible=true,outcomes={},values={}}
    local materials,words,sources,yields={},{},{},{}
    local missing,pending
    local now=opt.now or f.now or time()
    local pricing=W.Pricing or W.Market
    for i=3,#row do
        local chance,low,high,item=unpack(row[i])
        yields[#yields+1]={item=item,chance=chance,min=low,max=high}
        snapshot.outcomes[#snapshot.outcomes+1]={p=chance/100,materials={{item=item,qty=(low+high)/2}}}
        local quote,why=pricing.Price(item,{market=opt.market,now=now})
        -- a material is valued at its competing price, not one cheap listing (Estimate.AtCompeting; a reference keeps its Recent Price)
        if W.Estimate and quote then quote=W.Estimate.AtCompeting(quote,item,{market=opt.market,now=now}) end
        local at=quote and W.Plain(quote.at)
        if not (quote and W.Int(quote.price,1,W.Prices.MAX_COPPER) and W.Finite(at) and at<=now and now-at<=W.Prices.OLD_AFTER) then
            missing=missing or ("A current price is missing for "..(data.names[item] or ("item "..item))..".")
            pending=pending or why=="loading"
        else
            local source=quote.reference and "market_server" or "local"
            snapshot.values[item]={value=quote.price,quality="limited",source=source}
            sources[source]=true
            materials[#materials+1]={item=item,chance=chance,min=low,max=high,expectedQty=chance/100*(low+high)/2,unit=quote.price,source=source,at=at}
        end
        words[#words+1]=chance.."% × "..low..(low~=high and ("–"..high) or "").." "..(data.names[item] or ("item "..item))
    end
    if missing then
        unavailable.why=pending and "Loading disenchant material prices." or missing
        unavailable.pending=pending;unavailable.outcomeReference=true;unavailable.outcomes=table.concat(words,"; ")
        unavailable.yields=yields
        return unavailable
    end
    local result=DE.Evaluate(input,snapshot)
    if result.state=="ok" then
        result.materials,result.outcomes=materials,table.concat(words,"; ")
        result.yields=yields
        result.priceSource=sources.market_server and (sources["local"] and "mixed" or "market_server") or "local"
        result.bracketsBuild=data.BRACKETS_BUILD
        result.why=result.why.." Prices: "..(result.priceSource=="market_server" and "Market server" or result.priceSource=="mixed" and "Market server + local scans" or "local scans").."."
    end
    return result
end
