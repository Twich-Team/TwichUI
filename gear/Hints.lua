-- TwichUI: upgrade hints, judging items
-- Works out, once per item, whether it's worth a hint: can you wear it (now,
-- or at a higher level), what it would replace, and the comparison. Tooltips
-- and bag icons both read from here. Answers are kept until your gear,
-- talents, level, skills or upgrade hint options change.

local R = TwichUI
local E, D, P = R.GearEval, R.GearData, R.GearPrefs
local H = {}
R.GearHints = H

local MAX_KEPT = 300
local kept = {}          -- [item link] = judgement, or false for "no hint"
local keptCount = 0

local listeners = {}
function H:OnChange(fn) listeners[#listeners + 1] = fn end

local function Forget()
    wipe(kept)
    keptCount = 0
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

local function Build(link, lines, tooltip, bag, slot)
    local item = D.Item(link)
    if not item then return nil end
    local slots = E.SlotsFor(item.equipLoc)
    local who = slots and D.Character()
    if not who then return false end
    local equipped = {}
    for _, s in ipairs(slots) do
        local worn = D.Equipped(s)
        if worn == nil then return nil end
        equipped[s] = worn
    end
    if E.IsWorn(link, item.equipLoc, equipped) then return false end

    if not lines and bag and C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        lines = data and data.lines
    end
    -- Red requirement text means you can't wear it. When the only thing in
    -- the way is your level, it can still be compared, marked with the level.
    local level
    local red = D.RedLines(lines, tooltip)
    if red > 0 then
        local playerLevel = UnitLevel("player")
        if red == 1 and P.Get("futureLevels") and item.minLevel and playerLevel and item.minLevel > playerLevel then
            level = item.minLevel
        else
            return false
        end
    end
    item.effects = D.Effects(lines)
    local result = E.Compare(item, equipped, who)
    if not result then return false end
    return { result = result, who = who, level = level }
end

-- The judgement for an item: { result, who, level }, false when there's no
-- hint to give, or nil while the game is still loading the item or your gear.
-- lines: the item's tooltip data lines, if at hand; bag and slot let bag
-- icons have them fetched only when the item isn't known yet.
function H.Judge(link, lines, tooltip, bag, slot)
    local judged = kept[link]
    if judged ~= nil then return judged end
    judged = Build(link, lines, tooltip, bag, slot)
    if judged == nil then return nil end
    if keptCount >= MAX_KEPT then
        wipe(kept)
        keptCount = 0
    end
    kept[link] = judged
    keptCount = keptCount + 1
    return judged
end

-- Whether an item gets a line at a glance (and a bag icon).
function H.Noteworthy(judged)
    if not judged then return false end
    local verdict = judged.result.verdict
    return verdict == "likely" or verdict == "empty" or (verdict == "possible" and P.Get("glancePossible"))
end

R:On("PLAYER_EQUIPMENT_CHANGED", function()
    D.ForgetEquipment()
    Forget()
end)
for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "TRAIT_CONFIG_UPDATED",
    "TRAIT_CONFIG_LIST_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do
    R:On(event, function()
        D.ForgetCharacter()
        Forget()
    end)
end
P:OnChange(function()
    D.ForgetCharacter()
    Forget()
end)
