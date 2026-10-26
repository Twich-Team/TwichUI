-- TwichUI: Healer Watch, what drinking looks like
-- Drinking is confirmed only by an aura on the watched healer that this file recognizes. Never by sitting, by mana
-- going up, by a potion or another regeneration effect, or by anything said in chat.
--
-- How an aura is recognized, in order:
--   1. Its spell ID is in IDS (a registry of drink auras confirmed for WoW: Forever). Seeded with 430, the first rank of
--      the classic "Drink" aura; NaowhForever's Forever healer-mana display (reference_addons, not copied) relies on the
--      same spell for its drinking mark. HD.Register(id) adds another; see docs/healer-watch.md "Adding a drink aura".
--   2. Its name is exactly the client's own name for spell 430 (C_Spell.GetSpellName, so it is in the client's language:
--      "Drink" in English). Every rank of the classic drink aura shares that name, which is why this fallback exists;
--      it is an exact comparison, never a substring, so "Drink Me" or "Drinking Horn" never count. Its limit: an effect
--      the game names differently (a Mage table's "Refreshment", a food-and-drink buff) is not recognized unless its ID is
--      registered, and a server that renamed the aura would need its ID registered too.
-- What the game allows: C_UnitAuras.GetAuraDataByIndex (UnitAuraDocumentation.lua) returns secret values while aura
-- restrictions are active (combat, an encounter), and C_Secrets.ShouldAurasBeSecret says when that is so
-- (SecretPredicateAPIDocumentation.lua). Then nothing is concluded: the drink state is "hidden", not "no".

local R = TwichUI
local HD = {}
R.HealerDrinks = HD

HD.NAME_SPELL = 430
HD.MAX_AURAS = 40          -- helpful auras looked at on one unit, at most

local IDS = { [430] = "Drink (rank 1)" }
HD.IDS = IDS

-- Adds a drink aura confirmed for this client. id: a spell ID; note: what it is (for the diagnostics).
function HD.Register(id, note)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return false end
    IDS[id] = type(note) == "string" and note or ("spell " .. id)
    return true
end

local function Secret(v) return issecretvalue ~= nil and v ~= nil and issecretvalue(v) end

local drinkName
-- The client's name for the drink aura, once it has given one (nil until then; asked again next time).
function HD.Name()
    if drinkName then return drinkName end
    local get = C_Spell and C_Spell.GetSpellName
    local name = get and get(HD.NAME_SPELL)
    if type(name) == "string" and name ~= "" and not Secret(name) then drinkName = name end
    return drinkName
end

-- Whether one aura is drinking: true, evidence | false | nil (its fields are secret: can't tell).
function HD.Classify(aura)
    if type(aura) ~= "table" then return false end
    local id, name = aura.spellId, aura.name
    if Secret(id) or Secret(name) then return nil end
    if type(id) == "number" and IDS[id] then return true, "spell " .. id end
    local want = HD.Name()
    if want and name == want then return true, "name" end
    return false
end

-- Whether auras can be read right now.
function HD.Readable()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local secret = C_Secrets.ShouldAurasBeSecret()
        if secret == true then return false end
    end
    return C_UnitAuras ~= nil and C_UnitAuras.GetAuraDataByIndex ~= nil
end

-- Looks at the helpful auras of `unit`. Returns state ("yes" | "no" | "hidden"), evidence, auraInstanceID.
function HD.Scan(unit)
    if not unit or not HD.Readable() then return "hidden" end
    local unreadable = false
    for i = 1, HD.MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if aura == nil then break end
        local drink, evidence = HD.Classify(aura)
        if drink then
            local inst = aura.auraInstanceID
            return "yes", evidence, (not Secret(inst)) and inst or nil
        elseif drink == nil then
            unreadable = true
        end
    end
    if unreadable then return "hidden" end
    return "no"
end

-- Whether a UNIT_AURA update can have changed drinking, so a full look can be skipped when it can't. info: the
-- event's updateInfo; known: the drink aura's instance ID while drinking. A full update, or any aura added that might
-- be a drink (or can't be read), or the drink aura changing or going, says yes.
function HD.MayChange(info, known)
    if type(info) ~= "table" or info.isFullUpdate then return true end
    for _, aura in ipairs(info.addedAuras or {}) do
        if HD.Classify(aura) ~= false then return true end
    end
    if known then
        for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
            if Secret(id) or id == known then return true end
        end
        for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
            if Secret(id) or id == known then return true end
        end
    end
    return false
end
