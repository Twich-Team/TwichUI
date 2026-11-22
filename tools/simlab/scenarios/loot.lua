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

if view == "preview" then
    Lab.Step("sample-roll preview", function()
        rolled = {}
        local id = Start("item:20005", 30)
        local ok = C.PreviewStart()
        Check("state", "a sample is refused while a roll is open", false, ok)
        active[id] = nil
        A_Admin.FireEvent("CANCEL_ALL_LOOT_ROLLS")
        Lab.Settle(0.3)
        for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
        -- the Loot cards page's Preview button, then the card's own buttons
        local opened = Lab.Open("lootRolls")
        Check("init", "the Loot cards page opened", true, opened)
        Lab.Settle(0.3)
        Check("interact", "the sample starts", true, (C.PreviewStart()))
        Lab.Settle(0.4)
        local card = C.PreviewCard()
        Check("display", "a card shows a made-up item", "Verdant Scholar's Mantle", card.name:GetText())
        card.buttons.greed:Click()
        Lab.Settle(0.3)
        Check("interact", "Greed on the sample shows the choice", "submitted", card.view.state)
        Check("state", "and nothing was rolled", 0, #rolled)
        Lab.Settle(1.5)
        Check("display", "then made-up results", "resolved", card.view.state)
        -- a rule's preview, from the rules page
        local ok2 = Lab.Open("lootRules")
        Check("init", "the Loot rules page opened", true, ok2)
        Lab.Settle(0.4)
        local P = R.LootRulesPage
        local _, ruleId = LR.Create("greenGear"); LR.SetName(ruleId, "Greed on green gear"); LR.SetEnabled(ruleId, true)
        Lab.Settle(0.3)
        P.Select(ruleId)
        Lab.Settle(0.4)
        P.Parts().frame.previewRule:Click()
        Lab.Settle(0.5)
        card = C.PreviewCard()
        Check("interact", "Preview this rule shows the rule's countdown", "scheduled", card.view.state)
        Check("display", "named after the rule", true, (card.line3:GetText() or ""):find("Greed on green gear", 1, true) ~= nil)
        Check("state", "and still nothing was rolled", 0, #rolled)
        Lab.Settle(0.2)
    end)
end

-- Isolated sweep diagnostic: real runtime TGA/UV/blend at gameplay scale.
-- Four backgrounds and full/half alpha; old scissor versus a feathered endpoint.
if view == "sweepLab" then
    Lab.Step("isolated sweep transparency", function()
        local V = R.LootVictory
        Check("construct", "production preview loads textures", true, V.Preview("need", 4))
        V.PreviewAt(0.70)
        local f = V.PreviewCard().victory
        local board = CreateFrame("Frame", nil, UIParent); board:SetSize(840, 650)
        board:SetPoint("CENTER"); board:SetFrameStrata("TOOLTIP"); board:EnableMouse(false)
        local labels = { "Black", "Dark leather", "Mid-gray", "Checkerboard" }
        for column = 1, 4 do
            local panel = CreateFrame("Frame", nil, board); panel:SetSize(200, 650); panel:SetPoint("TOPLEFT", (column - 1) * 210, 0)
            local bg = panel:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
            bg:SetColorTexture(column == 3 and 0.35 or 0, column == 3 and 0.35 or 0, column == 3 and 0.35 or 0, 1)
            if column == 2 then
                bg:SetTexture(R.PATH .. [[media\loot\victory\loot_won_frame.tga]]); bg:SetTexCoord(0.12, 0.88, 0.25, 0.65)
            elseif column == 4 then
                for y = 0, 32 do for x = 0, 9 do
                    local tile = panel:CreateTexture(nil, "BACKGROUND"); tile:SetSize(20, 20); tile:SetPoint("TOPLEFT", x * 20, -y * 20)
                    local c = (x + y) % 2 == 0 and 0.24 or 0.48; tile:SetColorTexture(c, c, c, 1)
                end end
            end
            local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("TOP", 0, -12); title:SetText(labels[column])
            for row = 1, 4 do
                local host = CreateFrame("Frame", nil, panel); host:SetSize(142, 46 * 384 / 460)
                host:SetPoint("TOPLEFT", 14, -75 - (row - 1) * 145); host:SetClipsChildren(row == 3)
                local text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); text:SetPoint("TOPLEFT", 8, -45 - (row - 1) * 145)
                text:SetText(({ "1.00 / free edges", "0.50 / free edges", "Old scissor / at exit", "Free edges / same exit" })[row])
                for _, name in ipairs({ "sweepTail", "sweepHaze", "sweepCore" }) do
                    local source = f[name]; local t = host:CreateTexture(nil, "ARTWORK")
                    t:SetTexture(source:GetTexture()); t:SetTexCoord(source:GetTexCoord()); t:SetBlendMode(source:GetBlendMode())
                    t:SetSize(source:GetWidth() * 384 / 460, source:GetHeight() * 384 / 460)
                    t:SetPoint("CENTER", host, "TOPLEFT", (row >= 3 and 130 or 80) - (name == "sweepTail" and 48 * 384 / 460 or name == "sweepHaze" and 16 * 384 / 460 or 0), -13 * 384 / 460)
                    t:SetAlpha((row == 2 and 0.5 or 1) * (name == "sweepTail" and 0.65 or name == "sweepHaze" and 0.60 or 1))
                end
            end
        end
        V.PreviewStop()
        Check("display", "four diagnostic backgrounds constructed", true, board:IsShown())
        Check("state", "diagnostic leaves real wins untouched", 0, V.Count())
    end)
end

if view == "dropdown" or view == "dropdownScaled" then
    Lab.Step("scrolled Loot Rolls dropdown", function()
        Check("init", "Loot Rolls settings opens", true, Lab.Open("lootRolls"))
        local UI, Wg = R.SettingsUI, R.SettingsWidgets
        if view == "dropdownScaled" then UI.Frame():SetScale(0.75) end
        Lab.Reveal("lootRolls", "lootRollsVictoryIntensity"); Lab.Settle(0.2)
        local control = Lab.Row("lootRolls", "lootRollsVictoryIntensity").control
        local parent, scrolled = control:GetParent(), false
        while parent do
            if parent:IsObjectType("ScrollFrame") and parent:GetVerticalScroll() > 0 then scrolled = true end
            parent = parent:GetParent()
        end
        Check("state", "test owner is on a scrolled page", true, scrolled)
        Lab.EmulateNativeScrollRect(control)
        control:OpenMenu(); Lab.Settle(0.1)
        local menu = TwichUISettingsMenu
        Check("interact", "menu opens for the clicked dropdown", control, menu.owner)
        local delta = math.abs(menu:GetTop() * menu:GetEffectiveScale() - control:GetBottom() * control:GetEffectiveScale())
        Check("geometry", "menu touches the visible control", true, delta < 4)
        for _, row in ipairs(menu.rows) do if row.choice and row.choice.value == "full" then row:Click(); break end end
        Check("state", "selection still uses the loot setting", "full", LR.Get("victoryIntensity"))
        Check("interact", "selection dismisses popup", false, Wg.MenuShown())
        control:OpenMenu(); Lab.Settle(0.1)
        Check("state", "reopened menu retains its owner", control, menu.owner)
    end)
end

if view == "victorySettings" then
    Lab.Step("victory preview from settings", function()
        TwichUIDB.modules.lootRolls = false; LR.Refresh()
        local ok = Lab.Open("lootRolls")
        Check("init", "loot settings opens while disabled", true, ok)
        local button
        for _, row in ipairs(R.SettingsKit.pages.lootRolls.rows) do
            if row:GetName() == "Preview victory card" then button = row end
        end
        Check("construct", "victory preview row exists", true, button ~= nil)
        if not button then return end
        Lab.Reveal("lootRolls", button.id)
        Lab.Settle(0.3)
        Lab.Row("lootRolls", button.id).control:Click()
        Lab.Settle(0.5)
        local card = R.LootVictory.PreviewCard()
        Check("interact", "settings preview shows a Need victory", "need", card and card.view and card.view.choice)
        Lab.Reveal("lootRolls", "lootRollsVictoryPreviewChoice")
        Lab.Settle(0.2)
        local picked = Lab.PickChoice(Lab.Row("lootRolls", "lootRollsVictoryPreviewChoice"), "greed")
        Check("interact", "preview roll selector chooses Greed", true, picked)
        Lab.Reveal("lootRolls", "lootRollsVictoryPreviewQuality")
        Lab.Settle(0.2)
        local qualityPicked = Lab.PickChoice(Lab.Row("lootRolls", "lootRollsVictoryPreviewQuality"), 5)
        Check("interact", "preview quality selector chooses Legendary", true, qualityPicked)
        Lab.Reveal("lootRolls", button.id)
        Lab.Settle(0.2)
        Lab.Row("lootRolls", button.id).control:Click()
        Lab.Settle(R.LootVictory.MOTION_END + 0.05)
        Check("display", "preview quality matches the selected sample", 5, card.view.quality)
        Check("display", "sample tooltip has the selected quality", "Shoulder · Legendary", card.view.sampleLines[1])
        Check("interact", "next preview shows a Greed victory", "greed", card.view.choice)
        Check("state", "preview creates no real result or roll", 0, #rolled + R.LootVictory.Count())
        Check("state", "preview reaches static rest", nil, card.victory:GetScript("OnUpdate"))
    end)
end

if view:find("^victory") and view ~= "victorySettings" and view ~= "victoryReplay" and not view:find("^victoryPose") then
    Lab.Step("approved victory artwork", function()
        local V = R.LootVictory
        LR.Set("maxCards", 4)
        LR.Set("victoryIntensity", view == "victoryOff" and "off" or "subtle")
        LR.Set("victorySound", false)
        local link = view == "victoryGreed" and "item:20004" or "item:20001"
        if view == "victoryScaled" then LR.Set("scale", 75) end
        local choice = view == "victoryGreed" and "greed" or "need"
        local id = Start(link, 30)
        local roll = Ro.Find(id)
        Ro.Submit(roll, choice, "player")
        local old = C.Card(roll.key)
        Check("init", "native win relay available", true, V.Listening())
        A_Admin.FireEvent("LOOT_ITEM_ROLL_WON", link, 1, choice == "greed" and 2 or 1, 87, false)
        local entry = V.Entries()[1]
        Check("state", "confirmed event accepted", 1, V.Count())
        Check("construct", "existing card reused", old, entry and entry.card)
        local seconds = ({ victoryResolve = 0.1, victoryReveal = 0.3, victorySheen = 0.6, victoryParticles = 0.95,
            victoryStatic = 1.85, victoryOff = 1.85, victoryFade = entry.total - 0.15, victoryDone = entry.total + 0.15 })[view] or 1.85
        Lab.Settle(seconds)
        if view == "victoryDone" then
            Check("state", "victory completed", 0, V.Count())
            Check("state", "no decorative updater remains", nil, old.victory:GetScript("OnUpdate"))
        else
            Check("display", "title is dynamic", "YOU WON!", old.victory.title:GetText())
            Check("display", "redundant footer text is absent", nil, old.victory.footer)
            if view == "victoryStatic" or view == "victoryOff" then
                Check("state", "no per-frame work at rest", nil, old.victory:GetScript("OnUpdate"))
            end
        end
    end)
end

-- Quick replay/interruption drives actual clocks and the one existing pool.
if view == "victoryReplay" then
    Lab.Step("rapid lighting previews", function()
        local V = R.LootVictory
        LR.Set("victorySound", false); LR.Set("victoryIntensity", "full")
        Check("construct", "initial rich preview starts", true, V.Preview("need", 4))
        Lab.Settle(0.95)
        local card, before = V.PreviewCard(), V.PoolSize()
        Check("display", "active preview has warm light", true, card.victory.headerHaze:GetAlpha() > 0)
        Check("interact", "Greed replay interrupts cleanly", true, V.Preview("greed", 5))
        Check("state", "replay resets bloom", 0, card.victory.iconBloom:GetAlpha())
        Check("state", "replay resets glint", 0, card.victory.arrivalGlint:GetAlpha())
        for _, particle in ipairs(card.victory.particles) do Check("state", "replay resets particle", 0, particle:GetAlpha()) end
        Lab.Settle(1.90)
        Check("state", "no decorative updater at rest", nil, card.victory:GetScript("OnUpdate"))
        Check("state", "no new pool on replay", before, V.PoolSize())
        Check("state", "no real win created", 0, V.Count())
        V.PreviewStop()
        Check("state", "stopped preview is hidden", false, card.victory:IsShown())
        Check("state", "stopped preview cancels timer", nil, card.victory.timer)
    end)
end

-- Paused poses use the production painter on the exact reusable preview card.
-- The lifecycle scenarios above separately drive the real OnUpdate/timer path.
if view:find("^victoryPose") then
    Lab.Step("production animation pose", function()
        local V = R.LootVictory
        LR.Set("x", 0); LR.Set("y", 180)
        LR.Set("victorySound", false)
        LR.Set("victoryIntensity", view:find("Off") and "off" or view:find("Full") and "full" or "subtle")
        if view:find("Scaled") then LR.Set("scale", 75) end
        local seconds = tonumber(view:match("(%d+)$")) / 100
        local quality = view:find("Legendary") and 5 or view:find("Epic") and 4 or view:find("Rare") and 3 or 2
        local sample = { upgrade = not view:find("NoUpgrade") }
        if view:find("Long") then sample.name = "Stormrend Titanblade of the Unbroken Oath of the Eternal Watchers" end
        Check("construct", "production preview starts", true, V.Preview(view:find("Greed") and "greed" or "need", quality, sample))
        Check("interact", "preview can seek a synthetic pose", true, V.PreviewAt(seconds))
        local f = V.PreviewCard().victory
        Check("state", "paused capture has no updater", nil, f:GetScript("OnUpdate"))
        Check("display", "no redundant footer label on the card", nil, f.footer)
        Check("display", "upgrade indicator matches fixture", sample.upgrade, f.badge:IsShown())
        Check("display", "sample has requested quality", quality, f.entry.quality)
        Check("display", "lighting is below title", true, f.atmosphere:GetFrameLevel() < f.header:GetFrameLevel()
            and f.railCanvas:GetFrameLevel() < f.header:GetFrameLevel())
        if view:find("Off") then
            local clear = f.atmosphere:GetAlpha() == 0 and f.sweepCore:GetAlpha() == 0 and f.sweepTail:GetAlpha() == 0 and f.arrivalGlint:GetAlpha() == 0
            for _, particle in ipairs(f.particles) do clear = clear and particle:GetAlpha() == 0 end
            Check("display", "Off has no supplemental effects", true, clear)
        end
        if seconds >= V.MOTION_END then
            local clear = f.headerBloom:GetAlpha() == 0 and f.emblemBurst:GetAlpha() == 0 and f.radiance:GetAlpha() == 0 and f.iconBloom:GetAlpha() == 0
                and f.sweepCore:GetAlpha() == 0 and f.sweepTail:GetAlpha() == 0 and f.arrivalGlint:GetAlpha() == 0
            for _, particle in ipairs(f.particles) do clear = clear and particle:GetAlpha() == 0 end
            Check("state", "rest has no strong light or particles", true, clear)
        end
        if seconds >= V.MOTION_END and seconds < f.entry.total - 0.30 then
            Check("display", "finished header is fully opaque", 1, f.header:GetAlpha())
        end
        Lab.Settle(0.1)
    end)
end

-- Screenshot fixture only: move Blizzard's PTR feedback button beside the addon.
if PTR_IssueReporter then
    PTR_IssueReporter:ClearAllPoints()
    PTR_IssueReporter:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 8, -200)
end
Lab.Finish()
