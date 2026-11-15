-- Simulator lab scenario (docs/simulator-lab.md, docs/loot-rolls-implementation.md "Simulator evidence"): the real Loot Rolls cards,
-- model, rules and settings pages, over SYNTHETIC rolls. Run by tools/simlab/loot.sh, which puts scenarios/lib.lua in front of this file
-- and sets SIMLAB_PARAMS = { view = "..." }.
--
-- WHAT IS REAL: every file of loot/ and the settings window's Loot Rolls pages, the real event path (A_Admin.FireEvent delivers
-- START_LOOT_ROLL, CANCEL_LOOT_ROLL, LOOT_HISTORY_UPDATE_DROP ... to the frames that registered for them), the real timers (the
-- simulator's manual clock), the real cards, Roll.lua's real submit path.
-- WHAT IS FAKE (the game-API boundary, deterministic): the rolls (GetLootRollItemInfo, GetLootRollItemLink, GetLootRollTimeLeft,
-- GetActiveLootRollIDs), the items (C_Item), RollOnLoot (it records the call and never reaches the game), and the roll history.
-- This is NOT evidence that the Forever client sends these events, accepts these calls or exposes other players' rolls: see the
-- capability matrix in docs/loot-rolls-implementation.md.
local R, view = TwichUI, SIMLAB_PARAMS.view
local Check = Lab.Check
A_Admin.SetManualClock(GetTime())
Lab.Solo()

local LR, Ro, A, C = R.LootRolls, R.LootRoll, R.LootAuto, R.LootCards
local ITEMS = {
    ["item:20001"] = { id = 20001, name = "Stormrend Titanblade", quality = 4, class = 2, sub = 8, loc = "INVTYPE_2HWEAPON", bind = 1, price = 2061200,
        icon = "Interface\\Icons\\INV_Sword_62", type = "Weapon", subType = "Two-Handed Swords" },
    ["item:20002"] = { id = 20002, name = "Elixir of Mighty Fortitude (Recipe)", quality = 2, class = 9, sub = 6, loc = "", bind = 1, price = 800,
        icon = "Interface\\Icons\\INV_Scroll_03", type = "Recipe", subType = "Alchemy" },
    ["item:20003"] = { id = 20003, name = "Shieldward Battleplate", quality = 3, class = 4, sub = 4, loc = "INVTYPE_CHEST", bind = 2, price = 15800,
        icon = "Interface\\Icons\\INV_Chest_Plate16", type = "Armor", subType = "Plate" },
    ["item:20004"] = { id = 20004, name = "Verdant Scholar's Mantle", quality = 2, class = 4, sub = 1, loc = "INVTYPE_SHOULDER", bind = 2, price = 1200,
        icon = "Interface\\Icons\\INV_Shoulder_23", type = "Armor", subType = "Cloth" },
    ["item:20005"] = { id = 20005, name = "Linen Cloth", quality = 1, class = 7, sub = 5, loc = "", bind = 0, price = 13,
        icon = "Interface\\Icons\\INV_Fabric_Linen_01", type = "Trade Goods", subType = "Cloth" },
}
local rolls, active, rolled, judged = {}, {}, {}, {}
local NOW = function() return GetTime() end
GetLootRollItemInfo = function(id)
    local r = rolls[id]; local it = r and ITEMS[r.link]
    if not it then return nil end
    return it.icon, it.name, 1, it.quality, it.bind == 1, r.canNeed ~= false, r.canGreed ~= false, false, r.reasonNeed
end
GetLootRollItemLink = function(id) local r = rolls[id]; return r and r.link end
GetLootRollTimeLeft = function(id) local r = rolls[id]; return r and math.max(0, (r.ends - NOW()) * 1000) end
GetActiveLootRollIDs = function() local out = {} for id in pairs(active) do out[#out + 1] = id end table.sort(out) return out end
RollOnLoot = function(id, kind) rolled[#rolled + 1] = { id = id, kind = kind } end
C_Item.GetItemInfoInstant = function(link) local it = ITEMS[link]; if it then return it.id, it.type, it.subType, it.loc, it.icon, it.class, it.sub end end
C_Item.GetItemInfo = function(link)
    local it = ITEMS[link]
    if it then return it.name, link, it.quality, 10, 1, it.type, it.subType, 1, it.loc, it.icon, it.price, it.class, it.sub, it.bind end
end
C_TooltipInfo = C_TooltipInfo or {}
C_TooltipInfo.GetLootRollItem = function(id) local r = rolls[id]; if r then return { lines = { { leftText = ITEMS[r.link].name } } } end end
C_SkillInfo = C_SkillInfo or {}
C_SkillInfo.GetNumSkillLines = function() return 2 end
C_SkillInfo.GetSkillLineInfo = function(i) return ({ { isHeader = true, skillName = "Professions" }, { isHeader = false, skillName = "Alchemy", rank = 150 } })[i] end
GetItemSubClassInfo = function(class, sub) if class == 9 then return "Alchemy" end end
R.GearHints = R.GearHints or {}
R.GearHints.Judge = function(link) return judged[link] end
R.GearHints.Noteworthy = function(j) return j and j.up == true end
local HIST = { encounters = {}, drops = {} }
C_LootHistory = {
    GetAllEncounterInfos = function() return HIST.encounters end,
    GetSortedDropsForEncounter = function(e) return HIST.drops[e] end,
    GetSortedInfoForDrop = function(e, k) for _, d in ipairs(HIST.drops[e] or {}) do if d.lootListKey == k then return d end end end,
}
local nextID = 40
local function Start(link, seconds, extra)
    nextID = nextID + 1
    rolls[nextID] = { link = link, ends = NOW() + (seconds or 30), canNeed = extra and extra.canNeed, reasonNeed = extra and extra.reasonNeed }
    active[nextID] = true
    A_Admin.FireEvent("START_LOOT_ROLL", nextID, (seconds or 30) * 1000, 7000 + nextID)
    Lab.Settle(0.3)
    return nextID
end
local function Frame(roll) return C.Card(roll.key) end

Lab.Step("turn the feature on", function()
    TwichUIDB.modules.lootRolls = true
    LR.Refresh()
    Check("init", "the switch started the model and the cards", true, LR.IsOn() and Ro.Listening() and C.Ready())
    LR.Set("x", 120); LR.Set("y", 230)
end)

if view == "manual" or view == "stack" or view == "auto" or view == "resolved" or view == "waiting" or view == "expired" or view == "unavailable" then
    Lab.Step("the cards", function()
        if view == "manual" then
            judged["item:20001"] = { up = true }
            local id = Start("item:20001", 30)
            local roll = Ro.Find(id)
            Lab.Settle(22.4)   -- 7.3 s of the roll's own clock is left at the mockup's moment: 22.7 s into a 30 s roll
            Check("construct", "a card is on screen for the live roll", true, C.Has(id))
            Check("state", "the upgrade is read from the existing upgrade judge", true, roll.upgrade)
            Check("state", "no choice has been sent", 0, #rolled)
        elseif view == "unavailable" then
            local id = Start("item:20001", 20, { canNeed = false, reasonNeed = 1 })
            Check("state", "Need is shown as unavailable", "unavailable", C.Card(Ro.Find(id).key).buttons.need.state)
        elseif view == "stack" or view == "auto" then
            judged["item:20001"] = { up = true }
            if view == "auto" or view == "stack" then
                local _, rid = LR.Create("professionRecipes")
                LR.SetEnabled(rid, true)
                LR.SetDelay(rid, 6)
                LR.Set("auto", true)
            end
            local id1 = Start("item:20001", 20)
            local id2 = Start("item:20002", 30)
            Lab.Settle(3.2)
            local r2 = Ro.Find(id2)
            Check("state", "the recipe rule started a countdown", "scheduled", r2.state)
            Check("state", "nothing was sent", 0, #rolled)
            if view == "stack" then
                -- a third roll that was rolled on and resolved
                local id3 = Start("item:20003", 30)
                local r3 = Ro.Find(id3)
                Ro.Submit(r3, "greed", "player")
                active[id3] = nil
                A_Admin.FireEvent("CANCEL_LOOT_ROLL", id3)
                HIST.encounters = { { encounterID = 3 } }
                HIST.drops[3] = { { lootListKey = 1, itemHyperlink = "item:20003", playerRollState = 3, rollInfos = {
                    { playerName = "Arcanebloom", isSelf = false, state = 3, isWinner = true, roll = 84 },
                    { playerName = "Stoneshield", isSelf = false, state = 0, roll = 67 },
                    { playerName = UnitName("player") or "You", isSelf = true, state = 3, roll = 42 },
                    { playerName = "Briarfang", isSelf = false, state = 3, roll = 17 } },
                    winner = { playerName = "Arcanebloom", state = 3, roll = 84 } } }
                A_Admin.FireEvent("LOOT_HISTORY_UPDATE_DROP", 3, 1)
                Lab.Settle(0.3)
                Check("state", "the winner came from the roll history", "Arcanebloom", r3.result and r3.result.winner and r3.result.winner.name)
            end
        elseif view == "resolved" then
            local id = Start("item:20003", 30)
            local roll = Ro.Find(id)
            Ro.Submit(roll, "greed", "player")
            active[id] = nil
            A_Admin.FireEvent("CANCEL_LOOT_ROLL", id)
            HIST.encounters = { { encounterID = 3 } }
            HIST.drops[3] = { { lootListKey = 1, itemHyperlink = "item:20003", playerRollState = 3, rollInfos = {
                { playerName = "Arcanebloom", isSelf = false, state = 3, isWinner = true, roll = 84 },
                { playerName = "Stoneshield", isSelf = false, state = 0, roll = 67 },
                { playerName = UnitName("player") or "You", isSelf = true, state = 3, roll = 42 },
                { playerName = "Briarfang", isSelf = false, state = 3, roll = 17 } },
                winner = { playerName = "Arcanebloom", state = 3, roll = 84 } } }
            A_Admin.FireEvent("LOOT_HISTORY_UPDATE_DROP", 3, 1)
            Lab.Settle(0.3)
            Check("state", "resolved with a winner", "resolved", roll.state)
        elseif view == "waiting" then
            local id = Start("item:20001", 30)
            local roll = Ro.Find(id)
            Ro.Submit(roll, "greed", "player")
            active[id] = nil
            A_Admin.FireEvent("CANCEL_LOOT_ROLL", id)
            Lab.Settle(0.3)
            Check("state", "a placed roll waits for the others", "submitted", roll.state)
        elseif view == "expired" then
            local id = Start("item:20005", 2.0)
            active[id] = nil
            Lab.Settle(1.9)
            A_Admin.FireEvent("CANCEL_LOOT_ROLL", id)
            Lab.Settle(0.3)
            Check("state", "a roll that ran out with no choice", "expired", Ro.Find(id).endReason)
        end
        Lab.Settle(0.3)
        Check("construct", "at least one card is shown", true, C.CardCount() >= 1)
    end)
end


if view == "rules" or view == "cards" or view == "narrow" or view == "builder" or view == "empty" then
    Lab.Step("the rules", function()
        local page = (view == "cards") and "lootRolls" or "lootRules"
        if view ~= "empty" and view ~= "cards" then
            local ok, a = LR.Create("greenGear"); LR.SetName(a, "Greed on green gear"); LR.SetEnabled(a, true)
            local _, b = LR.Create("professionRecipes"); LR.SetName(b, "Need my profession recipes"); LR.SetAction(b, "need"); LR.SetEnabled(b, true)
            local _, c2 = LR.Create("recipes"); LR.SetName(c2, "Pass duplicate recipes"); LR.SetEnabled(c2, true)
            local _, d = LR.Create("blank"); LR.SetName(d, "Greed cloth or reagents"); LR.SetMatch(d, "any")
            LR.RemoveCondition(d, 1); LR.AddCondition(d, "class"); LR.SetCondition(d, 1, { value = 7 }); LR.AddCondition(d, "class"); LR.SetCondition(d, 2, { value = 5 }); LR.SetEnabled(d, true)
            LR.AddCondition(a, "context")
            LR.Set("auto", true)
            Check("state", "four rules were made through the real functions", 4, LR.Count())
        end
        if view ~= "narrow" then
            -- a roomy window, as a player would drag it, so the whole editor can be read in one screenshot
            TwichUIDB.ui.settingsWindow = { point = "CENTER", relativePoint = "CENTER", x = -140, y = 0, w = 1080, h = 1060 }
        end
        local opened, why, v = Lab.Open(page)
        Check("init", "the settings page opened", true, opened)
        Lab.Settle(0.5)
        if view == "empty" then
            local parts = R.LootRulesPage.Parts()
            Check("display", "no rules: the list says so and the editor asks for a choice", true, parts.frame.empty:IsShown() and parts.frame.noRule:IsShown())
            Check("state", "nothing was made", 0, LR.Count())
            return
        end
        if page == "lootRules" then
            local P = R.LootRulesPage
            local first = LR.List()[1]
            P.Select(first.id)
            Lab.Settle(0.5)
            local parts = P.Parts()
            Check("construct", "the editor and the list were drawn", true, parts.frame ~= nil and parts.rows[1] ~= nil and parts.rows[1]:IsShown())
            Check("display", "the first row names the rule", "Greed on green gear", parts.rows[1].name:GetText())
            Check("display", "the editor shows its conditions", true, parts.conds[1] ~= nil and parts.conds[1].frame:IsShown())
            Check("display", "the summary bar says what it does", true, (parts.frame.barText:GetText() or ""):find("Greed") ~= nil)
            local target = first
            if view == "builder" then
                target = LR.List()[2]
                P.Select(target.id)
                Lab.Settle(0.4)
            end
            -- handler-level: the Pass button changes the rule through the real function
            local actions = parts.frame.actions
            actions.pass:Click()
            Lab.Settle(0.3)
            Check("interact", "the Pass button chose Pass", "pass", LR.Rule(target.id).action)
            actions.greed:Click()
            Lab.Settle(0.3)
            Check("interact", "the Greed button chose Greed again", "greed", LR.Rule(target.id).action)
            parts.frame.onBox:Click()
            Lab.Settle(0.2)
            Check("interact", "the switch turned the rule off", false, LR.Rule(target.id).enabled)
            parts.frame.onBox:Click()
            Check("interact", "and on again", true, LR.Rule(target.id).enabled)
            if view == "builder" then
                parts.frame.matchAny:Click()
                Lab.Settle(0.3)
            end
            local comp = R.SettingsCompanion
            Check("construct", "the live preview is showing", true, comp.Active() ~= nil and comp.Frame():IsShown())
        elseif page == "lootRolls" then
            Check("construct", "the page's rows were drawn", true, v ~= nil and v.rows ~= nil)
            Check("construct", "the sample preview is showing", true, R.SettingsCompanion.Active() ~= nil)
        end
    end)
end


if view == "place" then
    Lab.Step("placement", function()
        local x0, y0 = LR.Place()
        -- a roll that is open: placing is refused (the player must never lose sight of one)
        local id = Start("item:20005", 30)
        local ok, why = C.PlaceStart()
        Check("state", "placing is refused while a roll is open", false, ok)
        active[id] = nil
        A_Admin.FireEvent("CANCEL_ALL_LOOT_ROLLS")
        Lab.Settle(0.3)
        local done
        Check("interact", "placing starts with no roll open", true, (C.PlaceStart(function(saved) done = saved end)))
        local mover = _G.TwichUILootCardsMover
        Check("construct", "the sample card is shown", true, mover ~= nil and mover:IsShown() and C.Placing())
        Check("state", "starting to place changed nothing saved", x0, (LR.Place()))
        mover:ClearAllPoints(); mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 200, 300)
        Lab.Settle(0.1)
        C.PlaceFinish(false)
        Check("interact", "Cancel keeps the old place", x0, (LR.Place()))
        Check("state", "and tells the caller it was not saved", false, done)
        C.PlaceStart(function(saved) done = saved end)
        mover = _G.TwichUILootCardsMover
        mover:ClearAllPoints(); mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 200, 300)
        Lab.Settle(0.1)
        local es, ues = mover:GetEffectiveScale(), UIParent:GetEffectiveScale()
        local ux, uy = UIParent:GetCenter()
        local wantX = ((200 + mover:GetWidth() / 2) * es - ux * ues) / ues
        local wantY = ((300 + mover:GetHeight()) * es - uy * ues) / ues
        C.PlaceFinish(true)
        local x1, y1 = LR.Place()
        Check("interact", "Finish saves where the card was dragged to (x)", true, math.abs(x1 - wantX) <= 1)
        Check("interact", "and (y)", true, math.abs(y1 - wantY) <= 1)
        Check("state", "and tells the caller it was saved", true, done)
        Check("state", "the sample card is gone again", false, C.Placing())
        -- leave a sample showing for the screenshot
        C.PlaceStart()
        Lab.Settle(0.2)
    end)
end

-- Screenshot fixture only: move Blizzard's PTR feedback button beside the addon.
if PTR_IssueReporter then
    PTR_IssueReporter:ClearAllPoints()
    PTR_IssueReporter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -200)
end
Lab.Finish()
