-- A8: expected disenchant value, only from an explicitly verified Forever snapshot.
-- No distributable, verified Forever outcome table is available in this repository.
-- Production therefore reports unknown outcomes. The pure evaluator also accepts
-- verified snapshots for regression/reference use; no Classic/Retail tables ship.
local W = TwichUI.Workshop
local DE = { API = 1 }
W.Disenchant = DE
function DE.Eligibility(f)
    if not W.Worth.DisenchantRelevant(f) then return false, "This item is not a supported disenchant candidate." end
    if f.canDisenchant == false then return false, "Your character does not know Disenchant." end
    if f.canDisenchant ~= true then return nil, "Your character's Disenchant ability is unknown." end
    return nil, "This item's disenchant eligibility and required skill are unverified."
end
function DE.Evaluate(f, snapshot)
    local eligible, why = DE.Eligibility(f)
    local r = { role = "disenchant", state = eligible == false and "unavailable" or "unknown", why = why, expected = true }
    if eligible == false then return r end
    if not (snapshot and snapshot.verified == true and snapshot.client == "forever" and snapshot.item == f.item
        and type(snapshot.source) == "string" and snapshot.source ~= "" and snapshot.eligible == true and f.canDisenchant == true) then return r end
    local skill, required = W.Int(f.enchantSkill, 0, 1000), W.Int(snapshot.requiredSkill, 0, 1000)
    if not skill or not required then r.why = "Enchanting skill requirements are unknown." return r end
    if skill < required then r.state, r.why = "unavailable", "Your Enchanting skill is too low." return r end
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
            if not (p and W.Int(p.value,1,W.Prices.MAX_COPPER) and (p.quality == "good" or p.quality == "fair")) then
                r.why = "A reliable material listing value is missing." return r
            end
            value = value + o.p * m.qty * p.value
        end
    end
    if math.abs(probability - 1) > 0.000001 or value > W.Prices.MAX_COPPER then r.why = "Disenchant outcomes do not form a complete supported estimate." return r end
    r.state, r.expectedGross, r.source, r.why = "ok", math.floor(value), snapshot.source, "Expected material listing value before fees; outcomes and sales are uncertain."
    return r
end
