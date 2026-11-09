-- Simulator lab scenario (docs/simulator-lab.md, docs/workshop.md "Simulator coverage"): the real Workshop window, opened the
-- normal way (/tui workshop), driven through its Crafting, Opportunities and Shopping views over SYNTHETIC game data.
-- Run by tools/simlab/workshop.sh, which puts scenarios/lib.lua in front of this file and sets SIMLAB_PARAMS.
--
-- WHAT IS REAL: TwichUI_Workshop (every file, loaded by C_AddOns.LoadAddOn through the launcher), the launcher, the saved-data layers
-- (TwichUIDB, in memory only: every run starts with no saved variables), the NPC collection store (a merchant is entered through its
-- own NS.Observe), the price scan state machine (Scan.lua) and the window's frames and controls.
--
-- WHAT IS FAKE (the game-API boundary, all deterministic, all read-only):
--   C_TradeSkillUI   two professions with seven recipes (GetBaseProfessionInfo, GetRecipeInfo, GetRecipeSchematic, GetFilteredRecipeIDs, the
--                    "is it mine" questions, OpenRecipe which only records the id). GetAllRecipeIDs is removed, as in the Forever UI source.
--   C_Item           names/icons (GetItemInfo, GetItemInfoInstant) and the bag counts (GetItemCount) from the BAGS table below
--   C_AuctionHouse   a listing table behind ReplicateItems / GetNumReplicateItems / GetReplicateItemInfo / IsThrottledMessageSystemReady;
--                    AuctionHouseFrame is a plain shown frame. The Scan runs for real against it. Nothing is bought, bid or posted.
--   merchant         GetMerchantNumItems/GetMerchantItemID/C_MerchantFrame.GetItemInfo/GetMerchantItemCostInfo/UnitGUID("npc") and a stand-in
--                    for the global MerchantFrame, only while a MERCHANT_SHOW is delivered.
-- NOT FAKE BY ACCIDENT: the auction house cut. PR.CUT is empty in the product (the real cut is unconfirmed). One step sets a 5% cut as TEST
-- INPUT to check the arithmetic and wording of the cut path; it says nothing about the real game's cut and is removed again.
--
-- LAYERS named in each check (what the check is evidence of):
--   display  text or state read from the frames the window drew
--   click    a control's OnClick, run by Button:Click() (HANDLER LEVEL: the simulator has no pointer or key injection; no hit test, no focus)
--   direct   a Session/Window function called directly by the scenario (not through a control)
--   event    a game event delivered by the simulator (A_Admin.FireEvent) to the frames that registered for it
--   state    the underlying data (queue, saved vendor/price records, picks) read back
--   init     the addon loaded / the window opened
--
-- EXPECTED VALUES are typed from hand arithmetic written beside each block (never read from the code under test).
local R = TwichUI
local Check = Lab.Check
local params = rawget(_G, "SIMLAB_PARAMS") or {}
local Say = Lab.Say

A_Admin.SetManualClock(GetTime())
Lab.Solo()

---------------------------------------------------------------------------------------------------------------------------
-- The synthetic world
---------------------------------------------------------------------------------------------------------------------------
local ITEMS = {   -- name; every one gets the same stand-in icon
    [118] = "Minor Healing Potion", [3382] = "Weak Troll's Blood Potion", [3390] = "Elixir of Many Wonders",
    [9999] = "Greater Elixir of Extremely Long Fortitude Name", [2851] = "Copper Belt Buckle", [2841] = "Bronze Bar",
    [2447] = "Peacebloom", [765] = "Silverleaf", [3371] = "Empty Vial", [2450] = "Briarthorn", [2320] = "Coarse Thread",
    [2770] = "Copper Ore", [2771] = "Tin Ore", [4400] = "Heavy Stock",
}
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
C_Item.GetItemInfoInstant = function(id)
    if ITEMS[id] then return id, "", "", "", ICON, 7, 0 end
end
C_Item.GetItemInfo = function(id)
    local n = ITEMS[id]
    if n then return n, "|cffffffff|Hitem:" .. id .. "::::::::80:70:::::::::|h[" .. n .. "]|h|r", 1, 1, 1, "", "", 20, "", ICON, 1, 7, 0, 0 end
end
C_Item.RequestLoadItemDataByID = function() end

local BAGS = {}   -- [itemID] = count; absent = 0
local function SetBags(t) for k in pairs(BAGS) do BAGS[k] = nil end for k, v in pairs(t) do BAGS[k] = v end end
C_Item.GetItemCount = function(id) return BAGS[id] or 0 end

-- professions and recipes ---------------------------------------------------------------------------------------------------
local PROF = {
    alch = { id = 171, name = "Alchemy", recipes = { 2330, 3170, 7001, 7002, 7003 } },
    smith = { id = 164, name = "Blacksmithing", recipes = { 2663, 2659 } },
}
local RECIPES = {   -- diff: 0 Orange .. 3 Grey. mats = { {item, qty} }. out = {item, min, max}. choice = two items in one slot (not supported)
    [2330] = { name = "Minor Healing Potion", diff = 0, out = { 118, 1, 1 }, mats = { { 2447, 1 }, { 765, 1 }, { 3371, 1 } } },
    [3170] = { name = "Weak Troll's Blood Potion", diff = 1, out = { 3382, 1, 1 }, mats = { { 2447, 2 }, { 3371, 1 } } },
    [7001] = { name = "Elixir of Many Wonders", diff = 2, out = { 3390, 1, 3 }, mats = { { 2450, 1 } } },
    [7002] = { name = "Greater Elixir of Extremely Long Fortitude Name", diff = 3, out = { 9999, 1, 1 }, mats = { { 2447, 2 }, { 3371, 1 } } },
    [7003] = { name = "Enchant Bracer - Lesser Choice", diff = 1, choice = { 2447, 2450 } },
    [2663] = { name = "Copper Belt Buckle", diff = 1, out = { 2851, 1, 1 }, mats = { { 2841, 4 }, { 2320, 1 } } },
    [2659] = { name = "Smelt Bronze", diff = 0, out = { 2841, 2, 2 }, mats = { { 2770, 2 }, { 2771, 1 } } },
}
local open = PROF.alch
local opened = {}   -- recipes the window asked the game to open (OpenRecipe)
local T = C_TradeSkillUI
T.GetAllRecipeIDs = nil   -- the Forever UI source has no such function (docs/workshop.md); the window then follows the filters
T.GetBaseProfessionInfo = function() return { professionID = open.id, professionName = open.name } end
T.GetFilteredRecipeIDs = function() local out = {} for i, id in ipairs(open.recipes) do out[i] = id end return out end
T.IsTradeSkillLinked = function() return false end
T.IsTradeSkillGuild = function() return false end
T.IsNPCCrafting = function() return false end
T.IsDataSourceChanging = function() return false end
T.GetRecipeInfo = function(id)
    local r = RECIPES[id]
    if not r then return nil end
    return { learned = true, name = r.name, icon = 136240, relativeDifficulty = r.diff, isRecraft = false }
end
T.GetRecipeSchematic = function(id)
    local r = RECIPES[id]
    if not r then return nil end
    local s = { reagentSlotSchematics = {} }
    if r.out then s.quantityMin, s.quantityMax, s.outputItemID = r.out[2], r.out[3], r.out[1] else s.quantityMin, s.quantityMax = 1, 1 end
    if r.choice then
        s.reagentSlotSchematics[1] = { reagentType = 1, required = true, quantityRequired = 2,
            reagents = { { itemID = r.choice[1] }, { itemID = r.choice[2] } } }
    else
        for i, m in ipairs(r.mats) do
            s.reagentSlotSchematics[i] = { reagentType = 1, required = true, quantityRequired = m[2], reagents = { { itemID = m[1] } } }
        end
    end
    return s
end
T.OpenRecipe = function(id) opened[#opened + 1] = id return true end

-- the auction house -----------------------------------------------------------------------------------------------------------
-- { item, stack count, buyout of the whole stack in copper (0 = bid only) }, read by index 0 .. n-1 as the product reads them
local LISTINGS = {
    { 2447, 20, 100 }, { 2447, 10, 70 }, { 2447, 1, 0 }, { 765, 2, 90 }, { 3371, 20, 400 }, { 118, 1, 150 }, { 118, 1, 180 },
    { 3382, 5, 300 }, { 3390, 1, 100 }, { 9999, 1, 25 }, { 2450, 10, 300 }, { 2770, 20, 700 }, { 2771, 10, 300 }, { 2841, 2, 800 },
    { 2841, 3, 1500 }, { 2851, 1, 5000 }, { 55555, 3, 999 },
}
local ah = { requested = 0 }
local AH = C_AuctionHouse
AH.IsThrottledMessageSystemReady = function() return true end
AH.ReplicateItems = function() ah.requested = ah.requested + 1 end
AH.GetNumReplicateItems = function() return #LISTINGS end
AH.GetReplicateItemInfo = function(k)
    local l = LISTINGS[k + 1]
    if not l then return nil end
    return "x", ICON, l[2], 1, true, 0, 0, 1, 1, l[3], 0, false, "", "seller", "seller", 0, l[1], true
end
local function SetAuctionHouse(shown)
    local f = rawget(_G, "AuctionHouseFrame")
    if not f then f = CreateFrame("Frame", "AuctionHouseFrame", UIParent) f:SetSize(400, 300) f:SetPoint("CENTER") end
    f:SetShown(shown)
end

-- a merchant ------------------------------------------------------------------------------------------------------------------
-- (id, price in copper for one purchase, items per purchase, available (-1 = unlimited), extended cost)
local MERCHANT = {
    { 2320, 25, 1, -1, false },   -- Coarse Thread: money only, 25c each
    { 2771, 80, 5, -1, false },   -- Tin Ore: 80c for a stack of 5
    { 2770, 40, 1, -1, true },    -- Copper Ore: paid with an extra cost (skipped by the product)
    { 4400, 10, 1, -1, false },   -- an item no recipe uses (skipped)
}
local realMerchantFrame, realUnitGUID, realUnitName = rawget(_G, "MerchantFrame"), UnitGUID, UnitName
GetMerchantNumItems = function() return #MERCHANT end
GetMerchantItemID = function(i) return MERCHANT[i] and MERCHANT[i][1] end
GetMerchantItemCostInfo = function(i) return MERCHANT[i] and MERCHANT[i][5] and 1 or 0 end
C_MerchantFrame.GetItemInfo = function(i)
    local m = MERCHANT[i]
    if not m then return nil end
    return { price = m[2], stackCount = m[3], numAvailable = m[4], isPurchasable = true, hasExtendedCost = m[5] }
end

---------------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------------
-- 150 copper's coin text "1|T..SilverIcon..|t 50|T..CopperIcon..|t" becomes "1s 50c" (the simulator draws no inline textures)
local function Norm(s)
    s = tostring(s == nil and "<nil>" or s)
    s = s:gsub("(%d+)|T[^|]*GoldIcon[^|]*|t", "%1g")
    s = s:gsub("(%d+)|T[^|]*SilverIcon[^|]*|t", "%1s")
    s = s:gsub("(%d+)|T[^|]*CopperIcon[^|]*|t", "%1c")
    return s
end
local function Txt(fs) return fs and fs.GetText and Norm(fs:GetText()) or "<missing>" end

local function Win() return R.Workshop.Window end
local function Frame() return TwichUIWorkshop end
local function Rows(list)
    local out = {}
    for _, row in ipairs(list.rows) do if row:IsShown() then out[#out + 1] = row end end
    return out
end
local function Names(list, field)   -- the shown rows' name texts, in order
    local out = {}
    for _, row in ipairs(Rows(list)) do out[#out + 1] = Txt(row[field or "name"]) end
    return table.concat(out, " | ")
end
local function Row(list, name)
    for _, row in ipairs(Rows(list)) do if Txt(row.name) == name then return row end end
    error(("no shown row named %q (shown: %s)"):format(name, Names(list)))
end
local function FindButton(root, text, depth)
    depth = depth or 0
    if depth > 3 then return nil end
    for _, c in ipairs({ root:GetChildren() }) do
        if c.text and c.text.GetText and c.text:GetText() == text and c:IsShown() then return c end
        local hit = FindButton(c, text, depth + 1)
        if hit then return hit end
    end
end
local function Click(btn, what)
    if not btn then error("missing control: " .. tostring(what)) end
    if btn.IsEnabled and not btn:IsEnabled() then error("control is disabled: " .. tostring(what)) end
    btn:Click()
end
local function Queue()   -- the saved queue, read back: "name x crafts, ..."
    local out = {}
    for _, e in ipairs(R.Workshop.Queue.Entries()) do out[#out + 1] = e.name .. " x" .. e.crafts end
    return table.concat(out, ", ")
end
local function Event(name) A_Admin.FireEvent(name) Lab.Settle(0.4) end
local function Opps() return Win().Opps() end
local function Shop() return Win().Shop() end
local function Lists() return Win().Lists() end

local function Tab(name)   -- the three buttons beside the title
    local f = Frame()
    local b = ({ Crafting = f.tabCraft, Shopping = f.tabShop, Opportunities = f.tabOpps })[name]
    Click(b, "tab " .. name)
    Lab.Settle(0.2)
end

-- open the Workshop the way a player does (/tui workshop) and switch which profession the fake profession window shows
local function SlashWorkshop() SlashCmdList.TWICHUI("workshop") Lab.Settle(0.7) end
local function ShowProfession(p)
    open = p
    Event("TRADE_SKILL_LIST_UPDATE")
    Lab.Settle(0.4)
end

---------------------------------------------------------------------------------------------------------------------------
-- 1. Opening and navigation
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("open and navigate", function()
    Check("init", "workshop addon is not loaded before the first open", false, R.WorkshopLauncher.Loaded())
    Check("init", "no workshop window exists before the first open", "nil", tostring(rawget(_G, "TwichUIWorkshop")))
    SetBags({ [2447] = 4, [765] = 0, [3371] = 5 })
    SetAuctionHouse(true)
    SlashWorkshop()
    Check("init", "workshop addon loaded by /tui workshop", true, R.WorkshopLauncher.Loaded())
    Check("display", "window is shown after /tui workshop", true, Frame() ~= nil and Frame():IsShown())
    Check("display", "window is visible (anchored, alpha up)", true, Frame():IsVisible() and Frame():GetAlpha() > 0.99)
    Check("display", "window opens on Crafting", "craft", Win().Mode())
    Check("display", "Crafting view shown, Shopping and Opportunities hidden", "true/false/false",
        tostring(Lists().recipes.box:IsVisible()) .. "/" .. tostring(Shop():IsShown()) .. "/" .. tostring(Opps():IsShown()))
    Check("display", "Alchemy recipes listed, sorted by name",
        "Elixir of Many Wonders | Enchant Bracer - Lesser Choice | Greater Elixir of Extremely Long Fortitude Name | Minor Healing Potion | Weak Troll's Blood Potion",
        Names(Lists().recipes))

    Tab("Shopping")
    Check("click", "Shopping tab: mode", "shop", Win().Mode())
    Check("display", "Shopping tab: only the Shopping view is shown", "false/true/false",
        tostring(Lists().recipes.box:IsVisible()) .. "/" .. tostring(Shop():IsShown()) .. "/" .. tostring(Opps():IsShown()))
    Check("display", "Shopping with an empty queue says so", "Add recipes to the queue to build a shopping list.", Txt(Lists().shop.empty))
    Tab("Opportunities")
    Check("click", "Opportunities tab: mode", "opps", Win().Mode())
    Check("display", "Opportunities tab: only the Opportunities view is shown", "false/false/true",
        tostring(Lists().recipes.box:IsVisible()) .. "/" .. tostring(Shop():IsShown()) .. "/" .. tostring(Opps():IsShown()))
    Tab("Crafting")
    Check("click", "Crafting tab: mode", "craft", Win().Mode())
    Check("display", "back on Crafting the recipe list is visible", true, Lists().recipes.box:IsVisible())
end)

---------------------------------------------------------------------------------------------------------------------------
-- 2. Crafting
---------------------------------------------------------------------------------------------------------------------------
-- Queue after this block: Minor Healing Potion x3 (Alchemy), Weak Troll's Blood Potion x2 (Alchemy), Copper Belt Buckle x2 (Blacksmithing).
-- Bags: Peacebloom 4, Silverleaf 0, Empty Vial 5, Bronze Bar 3, Coarse Thread 1, Copper Ore 4, Tin Ore 0.
Lab.Step("crafting: unsupported recipe is not ready", function()
    Check("display", "empty queue says so", "Nothing queued yet. Use Add on a recipe.", Txt(Lists().queue.empty))
    Check("display", "empty materials list says so", "Materials for the queue appear here.", Txt(Lists().mats.empty))
    local row = Row(Lists().recipes, "Enchant Bracer - Lesser Choice")
    Check("display", "unsupported recipe row: difficulty word", "Yellow", Txt(row.diff))
    Check("display", "unsupported recipe row: output from the schematic's quantity (no item)", "Makes 1", Txt(row.sub))
    Click(row.add, "Add (unsupported recipe)")
    Check("state", "unsupported recipe is queued", "Enchant Bracer - Lesser Choice x1", Queue())
    local q = Rows(Lists().queue)[1]
    Check("display", "queued unsupported recipe: crafts line", "1 craft - makes 1", Txt(q.line))
    Check("display", "queued unsupported recipe: 'Open profession to update.' shown", true, q.stale:IsShown())
    Check("display", "headline is NOT 'all materials in your bags'", "1 recipe can't be counted yet. Open its profession to update.", Txt(Frame().headline))
    Check("display", "no material row for an uncountable recipe", 0, #Rows(Lists().mats))
    Click(q.remove, "Remove (unsupported recipe)")
    Check("state", "unsupported recipe removed", "", Queue())
    Check("display", "queue count after remove", "0 of 30", Txt(Frame().queueCount))
    Check("display", "empty materials headline", "Add recipes to see the materials you need.", Txt(Frame().headline))
end)

Lab.Step("crafting: add, change quantity, remove", function()
    local list = Lists().recipes
    Click(Row(list, "Minor Healing Potion").add, "Add Minor Healing Potion")
    Click(Row(list, "Weak Troll's Blood Potion").add, "Add Weak Troll's Blood Potion")
    Check("state", "two recipes queued, one craft each", "Minor Healing Potion x1, Weak Troll's Blood Potion x1", Queue())
    Check("display", "added recipe's button now says Queued and is disabled", "Queued/false",
        Txt(Row(list, "Minor Healing Potion").add.text) .. "/" .. tostring(Row(list, "Minor Healing Potion").add:IsEnabled()))
    local q = Lists().queue
    local a, b = Rows(q)[1], Rows(q)[2]
    Check("display", "queue order and labels", "Minor Healing Potion  (Alchemy) | Weak Troll's Blood Potion  (Alchemy)", Names(q))
    Check("display", "1 craft line (makes 1)", "1 craft - makes 1", Txt(a.line))
    Check("display", "'-' is disabled at one craft", false, a.less:IsEnabled())
    Click(a.more, "+ on Minor Healing Potion")
    Click(Rows(q)[1].more, "+ on Minor Healing Potion (2)")
    Click(Rows(q)[2].more, "+ on Weak Troll's Blood Potion")
    Check("state", "quantities after + clicks", "Minor Healing Potion x3, Weak Troll's Blood Potion x2", Queue())
    Check("display", "3 crafts line: output quantity", "3 crafts - makes 1 each, 3 in all", Txt(Rows(q)[1].line))
    Check("display", "2 crafts line: output quantity", "2 crafts - makes 1 each, 2 in all", Txt(Rows(q)[2].line))
    Check("display", "crafts counters", "3 | 2", Txt(Rows(q)[1].count) .. " | " .. Txt(Rows(q)[2].count))
    Check("display", "queue count", "2 of 30", Txt(Frame().queueCount))

    -- remove one through its control and add it back
    Click(Rows(q)[2].remove, "Remove Weak Troll's Blood Potion")
    Check("state", "Remove takes the entry out", "Minor Healing Potion x3", Queue())
    Click(Row(list, "Weak Troll's Blood Potion").add, "Add Weak Troll's Blood Potion again")
    Click(Rows(q)[2].more, "+ on re-added entry")
    Check("state", "re-added with two crafts", "Minor Healing Potion x3, Weak Troll's Blood Potion x2", Queue())
    Click(Rows(q)[2].less, "- on Weak Troll's Blood Potion")
    Check("state", "'-' lowers by one", "Minor Healing Potion x3, Weak Troll's Blood Potion x1", Queue())
    Click(Rows(q)[2].more, "+ again")
    Check("state", "back to two", "Minor Healing Potion x3, Weak Troll's Blood Potion x2", Queue())
end)

Lab.Step("crafting: materials against the bags", function()
    -- Needs: Peacebloom 1x3 + 2x2 = 7; Silverleaf 1x3 = 3; Empty Vial 1x3 + 1x2 = 5.
    -- Bags Peacebloom 4, Silverleaf 0, Vial 5 -> still needed 3, 3, 0. Short items first (by item number), then the rest.
    local m = Lists().mats
    Check("display", "material order (short first)", "Silverleaf | Peacebloom | Empty Vial", Names(m))
    local function Line(name) local r = Row(m, name) return Txt(r.need) .. "/" .. Txt(r.have) .. "/" .. Txt(r.short) end
    Check("display", "Peacebloom shared by two recipes: need/in bags/still needed", "7/4/3", Line("Peacebloom"))
    Check("display", "Silverleaf need/in bags/still needed", "3/0/3", Line("Silverleaf"))
    Check("display", "Empty Vial need/in bags/still needed", "5/5/0", Line("Empty Vial"))
    Check("display", "headline", "Still needed: 2 materials.", Txt(Frame().headline))

    -- bags change: seven Peacebloom
    BAGS[2447] = 7
    Event("BAG_UPDATE_DELAYED")
    Check("event", "Peacebloom 7 in bags after BAG_UPDATE_DELAYED", "7/7/0", Line("Peacebloom"))
    Check("event", "material order follows", "Silverleaf | Peacebloom | Empty Vial", Names(m))
    Check("event", "headline after one fix", "Still needed: 1 material.", Txt(Frame().headline))
    BAGS[765] = 3
    Event("BAG_UPDATE_DELAYED")
    Check("event", "Silverleaf 3 in bags", "3/3/0", Line("Silverleaf"))
    Check("event", "headline when everything is in the bags", "All the materials are in your bags.", Txt(Frame().headline))
    -- a count that cannot be read is Unknown, never zero or ready
    C_Item.GetItemCount = function(id) if id == 3371 then return nil end return BAGS[id] or 0 end
    Event("BAG_UPDATE_DELAYED")
    Check("event", "unreadable bag count shows Unknown, not 0", "5/Unknown/Unknown", Line("Empty Vial"))
    Check("event", "headline with an unreadable count is not 'all in your bags'", "Some of your bag counts can't be read yet.", Txt(Frame().headline))
    C_Item.GetItemCount = function(id) return BAGS[id] or 0 end
    BAGS[2447], BAGS[765] = 4, 0
    SetBags({ [2447] = 4, [765] = 0, [3371] = 5, [2841] = 3, [2320] = 1, [2770] = 4 })
    Event("BAG_UPDATE_DELAYED")
    Check("event", "bags put back for later steps", "7/4/3", Line("Peacebloom"))
end)

Lab.Step("crafting: a second profession and Open recipe", function()
    ShowProfession(PROF.smith)
    local names = {}
    for _, p in ipairs(R.Workshop.Session.Professions()) do names[#names + 1] = p.name .. (p.selected and "*" or "") end
    Check("state", "both professions known, Blacksmithing browsed", "Alchemy | Blacksmithing*", table.concat(names, " | "))
    Check("display", "Blacksmithing recipes listed", "Copper Belt Buckle | Smelt Bronze", Names(Lists().recipes))
    Click(Row(Lists().recipes, "Copper Belt Buckle").add, "Add Copper Belt Buckle")
    Click(Rows(Lists().queue)[3].more, "+ on Copper Belt Buckle")
    Check("state", "queue with the third recipe", "Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2", Queue())
    -- Needs: Bronze Bar 4x2 = 8 (bags 3 -> 5 short); Coarse Thread 1x2 = 2 (bags 1 -> 1 short). Plus the Alchemy needs above.
    local m = Lists().mats
    local function Line(name) local r = Row(m, name) return Txt(r.need) .. "/" .. Txt(r.have) .. "/" .. Txt(r.short) end
    Check("display", "Bronze Bar need/in bags/still needed", "8/3/5", Line("Bronze Bar"))
    Check("display", "Coarse Thread need/in bags/still needed", "2/1/1", Line("Coarse Thread"))
    Check("display", "headline counts every short material", "Still needed: 4 materials.", Txt(Frame().headline))
    -- profession chip
    local chip = FindButton(Frame(), "Alchemy")
    Click(chip, "Alchemy chip")
    Check("click", "Alchemy chip switches the recipe list", "Elixir of Many Wonders | Enchant Bracer - Lesser Choice | Greater Elixir of Extremely Long Fortitude Name | Minor Healing Potion | Weak Troll's Blood Potion", Names(Lists().recipes))
    -- Open recipe records the id and asks nothing else of the game
    Click(Rows(Lists().queue)[1].open, "Open recipe")
    Check("click", "Open recipe asks the game to open recipe 2330", "2330", tostring(opened[#opened]))
end)

---------------------------------------------------------------------------------------------------------------------------
-- A merchant window, noted while the Workshop is shown (needed by Shopping)
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("merchant prices noted", function()
    -- The merchant window is "open" for the length of one MERCHANT_SHOW. The product's own NPC collection (npcs/Collect.lua) hears the same
    -- event and notes the merchant (id from UnitGUID("npc"), name from UnitName("npc"), the place from the simulator's player position).
    _G.MerchantFrame = { IsShown = function() return true end }
    _G.UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-1-1-3333-0000000001" end return realUnitGUID(unit) end
    _G.UnitName = function(unit) if unit == "npc" then return "Haldric the Peddler" end return realUnitName(unit) end
    Event("MERCHANT_SHOW")
    _G.MerchantFrame, _G.UnitGUID, _G.UnitName = realMerchantFrame, realUnitGUID, realUnitName
    local seen
    for _, e in ipairs(R.NpcStore.Entries()) do if e.id == 3333 then seen = e end end
    Check("state", "the NPC collection noted the merchant and what it sells (2320 2770 2771 4400)", "Haldric the Peddler | 2320,2770,2771,4400",
        seen and (seen.n .. " | " .. table.concat(seen.s or {}, ",")) or "not noted")
    local v = TwichUIDB.workshop.vendor and TwichUIDB.workshop.vendor.items or {}
    local function Rec(id) local t = v[id] return t and ("p=%d s=%d a=%d npc=%s"):format(t.p, t.s, t.a, tostring(t.npc)) or "none" end
    Check("state", "Coarse Thread price noted", "p=25 s=1 a=-1 npc=3333", Rec(2320))
    Check("state", "Tin Ore stack price noted", "p=80 s=5 a=-1 npc=3333", Rec(2771))
    Check("state", "extended-cost listing skipped (Copper Ore)", "none", Rec(2770))
    Check("state", "unused item skipped", "none", Rec(4400))
end)

---------------------------------------------------------------------------------------------------------------------------
-- 3. Opportunities
---------------------------------------------------------------------------------------------------------------------------
local function OppLine(name)   -- cost | sell | profit, each "a" with its "to" line when a range
    local r = Row(Lists().opps, name)
    local function Cell(c) local b = c.b:IsShown() and Txt(c.b) or "" return Txt(c.a) .. (b ~= "" and (" " .. b) or "") end
    return Cell(r.cost) .. " | " .. Cell(r.sell) .. " | " .. Cell(r.profit)
end

Lab.Step("opportunities: before any scan", function()
    Tab("Opportunities")
    Check("display", "no prices yet: source line", "No saved prices for this auction house yet.", Txt(Opps().source))
    Check("display", "no prices yet: empty state", "No prices for this auction house yet. Choose Scan prices.", Txt(Lists().opps.empty))
    Check("display", "Scan prices button is available", "Scan prices/true", Txt(Opps().scan.text) .. "/" .. tostring(Opps().scan:IsEnabled()))
end)

Lab.Step("opportunities: scan against the fake auction house", function()
    Click(Opps().scan, "Scan prices")
    Check("click", "scan started by the button, request sent once", "scanning/1", R.Workshop.Scan.state .. "/" .. ah.requested)
    Check("display", "button shows Scanning... and is disabled", "Scanning.../false", Txt(Opps().scan.text) .. "/" .. tostring(Opps().scan:IsEnabled()))
    Check("display", "status while asking", "Asking the auction house for its listings...", Txt(Opps().status))
    Check("display", "progress bar is shown during the scan", true, Opps().bar:IsShown())
    A_Admin.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
    Lab.Settle(0.3)
    Check("event", "status after the listings arrive", "Receiving listings...", Txt(Opps().status))
    Lab.Settle(3)
    local res = R.Workshop.Scan.result or {}
    Check("state", "scan finished", "done", R.Workshop.Scan.state)
    -- 17 listings are read; 2 do not count: a bid-only Peacebloom (buyout 0) and an item no recipe uses (55555) -> 15 used.
    -- Wanted items with a usable listing: 13 wanted (2447 765 3371 2450 2770 2771 2841 2320 118 3382 3390 9999 2851) minus Coarse Thread (no listing) = 12.
    Check("state", "records read / used / items priced / complete", "17/15/12/true", ("%s/%s/%s/%s"):format(res.read, res.used, res.items, tostring(res.complete)))
    Check("display", "status line after the scan", "Scan finished. Prices found for 12 of your items.", Txt(Opps().status))
    Check("display", "button back to Scan prices", "Scan prices/true", Txt(Opps().scan.text) .. "/" .. tostring(Opps().scan:IsEnabled()))
    Check("display", "progress bar hidden after the scan", false, Opps().bar:IsShown())
    Check("display", "price source line", "Prices: the auction house on SimulatedRealm \194\183 just now", Txt(Opps().source))
    -- the saved cheapest unit prices (hand arithmetic: stack buyout / stack count, rounded up)
    local items = TwichUIDB.workshop.prices.markets["SimulatedRealm|unknown"].items
    local function P(id) local t = items[id] return t and ("%d/%d/%d/%d"):format(t[1], t[2], t[3], t[4]) or "none" end
    Check("state", "Peacebloom cheapest 5c (100/20), 20 at that price, 2 buyout listings, 30 items", "5/20/2/30", P(2447))
    Check("state", "Bronze Bar cheapest 400c (800/2), 2 at that price, 2 listings, 5 items", "400/2/2/5", P(2841))
    Check("state", "Coarse Thread has no price", "none", P(2320))
    Check("state", "the unwanted item was not kept", "none", P(55555))
end)

Lab.Step("opportunities: rows, ordering, filtering, unknowns", function()
    -- One craft each, no cut. cost = sum(qty x unit); sell = unit x output; profit = sell - cost.
    --   Smelt Bronze          cost 2x35+1x30 = 100   sell 2x400 = 800          profit 700
    --   Minor Healing Potion  cost 5+45+20 = 70      sell 150                  profit 80
    --   Elixir of Many Wonders cost 30               sell 100 to 300 (1-3)     profit 70 to 270
    --   Weak Troll's Blood    cost 2x5+20 = 30       sell 60                   profit 30
    --   Greater Elixir (long) cost 2x5+20 = 30       sell 25                   profit -5
    --   Copper Belt Buckle    Coarse Thread has no price                        Unknown
    --   Enchant Bracer        materials not supported                           Unknown
    local o = Lists().opps
    Check("display", "default order: highest profit first, unknown last (by name)",
        "Smelt Bronze | Minor Healing Potion | Elixir of Many Wonders | Weak Troll's Blood Potion | Greater Elixir of Extremely Long Fortitude Name | Copper Belt Buckle | Enchant Bracer - Lesser Choice",
        Names(o))
    Check("display", "Smelt Bronze: cost | sell | profit", "1s | 8s | 7s", OppLine("Smelt Bronze"))
    Check("display", "Minor Healing Potion: cost | sell | profit", "70c | 1s 50c | 80c", OppLine("Minor Healing Potion"))
    Check("display", "Elixir of Many Wonders (makes 1-3): range shown with 'to'", "30c | 1s to 3s | 70c to 2s 70c", OppLine("Elixir of Many Wonders"))
    Check("display", "Weak Troll's Blood Potion: cost | sell | profit", "30c | 60c | 30c", OppLine("Weak Troll's Blood Potion"))
    Check("display", "loss is shown as negative", "30c | 25c | -5c", OppLine("Greater Elixir of Extremely Long Fortitude Name"))
    Check("display", "missing price: everything unknown, reason under the name",
        "Unknown for profit; 1 material has no price", (OppLine("Copper Belt Buckle"):find("Unknown | .*Unknown$") and "Unknown for profit" or OppLine("Copper Belt Buckle")) .. "; " .. Txt(Row(o, "Copper Belt Buckle").sub))
    Check("display", "unsupported recipe: Unknown with its reason", "Its materials aren't known or can't be counted", Txt(Row(o, "Enchant Bracer - Lesser Choice").sub))
    Check("display", "output basis under a priced name (quantity and profession)", "Makes 1-3  -  Alchemy", Txt(Row(o, "Elixir of Many Wonders").sub))
    Check("display", "output basis for a fixed output", "Makes 2  -  Blacksmithing", Txt(Row(o, "Smelt Bronze").sub))
    Check("display", "summary line (5 of 7 priced, 4 profitable)", "5 of 7 priced \194\183 4 profitable \194\183 profit, highest first", Txt(Opps().summary))
    Check("display", "footer is one short line saying the profit is before fees", "Profit is before fees: the auction house's cut isn't confirmed. Some recipes may be missing.", Txt(Opps().notes))
    Check("display", "profit column is not called estimated while no cut is taken off", "Profit before fees", Txt(Win().Heads().profit.text))
    Check("display", "About prices holds the long explanation", true, Opps().about:IsShown())

    -- sort: Cost to make. First click = cheapest first; ties by name. Costs: 30 (Elixir, Greater Elixir, Weak Troll's), 70 (Minor), 100 (Smelt).
    Click(Win().Heads().cost, "Cost to make heading")
    Check("click", "sort by cost, cheapest first",
        "Elixir of Many Wonders | Greater Elixir of Extremely Long Fortitude Name | Weak Troll's Blood Potion | Minor Healing Potion | Smelt Bronze | Copper Belt Buckle | Enchant Bracer - Lesser Choice", Names(o))
    Click(Win().Heads().cost, "Cost to make heading (second click)")
    Check("click", "second click reverses",
        "Smelt Bronze | Minor Healing Potion | Elixir of Many Wonders | Greater Elixir of Extremely Long Fortitude Name | Weak Troll's Blood Potion | Copper Belt Buckle | Enchant Bracer - Lesser Choice", Names(o))
    Click(Win().Heads().profit, "Estimated profit heading")
    Check("click", "back to profit: highest first", "Smelt Bronze | Minor Healing Potion | Elixir of Many Wonders", (Names(o):gsub(" | Weak.*", "")))

    -- profession filter
    Click(FindButton(Opps(), "Blacksmithing"), "Blacksmithing filter")
    Check("click", "Blacksmithing only: priced first, unknown after", "Smelt Bronze | Copper Belt Buckle", Names(o))
    Click(FindButton(Opps(), "Alchemy"), "Alchemy filter")
    Check("click", "Alchemy only (5 recipes, unknown last)",
        "Minor Healing Potion | Elixir of Many Wonders | Weak Troll's Blood Potion | Greater Elixir of Extremely Long Fortitude Name | Enchant Bracer - Lesser Choice", Names(o))
    Click(FindButton(Opps(), "All"), "All filter")
    Check("click", "All again shows every recipe", 7, #Rows(o))

    -- Profitable only drops the loss and the unknowns
    Click(Opps().profitOnly, "Profitable only")
    Check("click", "Profitable only: losses and unknowns hidden", "Smelt Bronze | Minor Healing Potion | Elixir of Many Wonders | Weak Troll's Blood Potion", Names(o))
    Click(Opps().profitOnly, "Profitable only (off)")
    Check("click", "Profitable only off shows all again", 7, #Rows(o))
end)

Lab.Step("opportunities: short tooltip, details with Shift", function()
    -- A capture stands in for GameTooltip's lines (the real tooltip is not drawn by the simulator); IsShiftKeyDown is a test input.
    local lines = {}
    local tt = GameTooltip
    local oldLine, oldDouble, oldShift = tt.AddLine, tt.AddDoubleLine, IsShiftKeyDown
    tt.AddLine = function(_, text) lines[#lines + 1] = text end
    tt.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " | " .. b end
    local shift = false
    IsShiftKeyDown = function() return shift end
    local row = Row(Lists().opps, "Minor Healing Potion")
    row:GetScript("OnEnter")(row)
    local short = Norm(table.concat(lines, "\n"))
    -- hand arithmetic as above: cost 70c, sell 1s 50c, profit before fees 80c; the scan has no market side and is complete
    Check("display", "short tooltip: name, cost, sell, profit before fees, status, hint",
        "Minor Healing Potion / Cost to make | 70c / Sell price | 1s 50c / Profit before fees | 80c / just now / Hold Shift for details", (short:gsub("\n", " / ")))
    Check("display", "short tooltip: a handful of lines, no reagent list", true, #lines <= 6 and not short:find("Peacebloom", 1, true))
    lines = {}
    shift = true
    A_Admin.FireEvent("MODIFIER_STATE_CHANGED")
    local long = Norm(table.concat(lines, "\n"))
    Check("event", "Shift pressed while hovering shows the details", true,
        long:find("1 x Peacebloom | 5c each = 5c", 1, true) ~= nil and long:find("Auction house cut | not deducted (not confirmed)", 1, true) ~= nil
        and long:find("Profit before fees | 80c", 1, true) ~= nil)
    lines = {}
    shift = false
    A_Admin.FireEvent("MODIFIER_STATE_CHANGED")
    Check("event", "released: the short tooltip again", true, table.concat(lines, "\n"):find("Hold Shift for details", 1, true) ~= nil)
    -- an unknown price stays visible without opening the details
    lines = {}
    local bad = Row(Lists().opps, "Copper Belt Buckle")
    bad:GetScript("OnEnter")(bad)
    Check("display", "unknown price: the reason is in the short tooltip and no profit is invented", true,
        table.concat(lines, "\n"):find("1 material has no price", 1, true) ~= nil and not table.concat(lines, "\n"):find("Profit", 1, true))
    bad:GetScript("OnLeave")(bad)
    tt.AddLine, tt.AddDoubleLine, IsShiftKeyDown = oldLine, oldDouble, oldShift
end)

Lab.Step("opportunities: test-input cut, then removed", function()
    -- TEST INPUT: a made-up 5% cut for the 'unknown' side. The product has no confirmed cut (Prices.CUT is empty).
    -- cut = round(sell x 0.05): 800->40, 150->7.5->8, 100->5, 300->15, 60->3, 25->1.25->1. Profit = sell - cut - cost.
    --   Smelt 660; Minor 72; Elixir 65 to 255; Weak Troll's 27; Greater -6.
    R.Workshop.Prices.CUT.unknown = 0.05
    Win().Render()
    local function Profit(name) local r = Row(Lists().opps, name) return Txt(r.profit.a) .. (r.profit.b:IsShown() and (" " .. Txt(r.profit.b)) or "") end
    Check("display", "[test input] Smelt Bronze profit after a 5% cut", "6s 60c", Profit("Smelt Bronze"))
    Check("display", "[test input] Minor Healing Potion profit", "72c", Profit("Minor Healing Potion"))
    Check("display", "[test input] range profit", "65c to 2s 55c", Profit("Elixir of Many Wonders"))
    Check("display", "[test input] loss gets bigger", "-6c", Profit("Greater Elixir of Extremely Long Fortitude Name"))
    Check("display", "[test input] note now speaks of the cut", true, Txt(Opps().notes):find("^Profit is after the auction house's cut%.") ~= nil and Txt(Win().Heads().profit.text) == "Estimated profit")
    R.Workshop.Prices.CUT.unknown = nil
    Win().Render()
    Check("display", "test cut removed: profit back to the uncut value", "7s", Profit("Smelt Bronze"))
end)

Lab.Step("opportunities: Add to queue", function()
    local o = Lists().opps
    local row = Row(o, "Elixir of Many Wonders")
    Check("display", "Add button before", "Add/true", Txt(row.add.text) .. "/" .. tostring(row.add:IsEnabled()))
    Click(row.add, "Add (Elixir of Many Wonders)")
    Check("state", "the real queue gained the recipe",
        "Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2, Elixir of Many Wonders x1", Queue())
    row = Row(o, "Elixir of Many Wonders")
    Check("display", "button now Queued and disabled", "Queued/false", Txt(row.add.text) .. "/" .. tostring(row.add:IsEnabled()))
    Tab("Crafting")
    local q = Lists().queue
    Check("display", "Crafting shows the added entry with its range", "1 craft - makes 1-3", Txt(Rows(q)[4].line))
    Click(Rows(q)[4].remove, "Remove Elixir of Many Wonders")
    Check("state", "queue back to three entries", "Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2", Queue())
end)

---------------------------------------------------------------------------------------------------------------------------
-- 4. Shopping
---------------------------------------------------------------------------------------------------------------------------
local function ShopRow(name) return Row(Lists().shop, name) end
local function Line(name)   -- need | source | spend | spend note | action
    local r = ShopRow(name)
    return table.concat({ Txt(r.need), Txt(r.source.text), Txt(r.spend.a), Txt(r.spend.b), r.act:IsShown() and Txt(r.act.text) or "-" }, " | ")
end

-- State: queue = Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2. Bags: Peacebloom 4, Silverleaf 0, Vial 5,
-- Bronze Bar 3, Coarse Thread 1, Copper Ore 4, Tin Ore 0. Merchant: Coarse Thread 25c each, Tin Ore 80c per 5. Merchant 3333 known to sell both.
-- Needs: Peacebloom 7 (short 3), Silverleaf 3 (short 3), Vial 5 (0), Bronze Bar 8 (short 5), Thread 2 (short 1).
--   Peacebloom 3: auction exact, 3 x 5 = 15c.            Silverleaf 3: only 2 listed in all -> not enough listed, no price.
--   Coarse Thread 1: vendor 25c.
--   Bronze Bar 5: auction cheapest 400c (2 at that price, 5 listed) -> estimate 5 x 400 = 2000c.
--                 Make Smelt Bronze: ceil(5/2) = 3 crafts, 6 made, 1 left over. Reagents 3x: Copper Ore 6 (4 owned, buy 2 at 35 = 70),
--                 Tin Ore 3 (owned 0, vendor 1 stack of 5 = 80c beats auction 3 x 30 = 90c, 2 left over). Cash 70 + 80 = 150.
--                 Economic cost 150 + owned 4 x 35 = 290 < 2000 -> Make is suggested.
-- Spending (priced buy rows only): Peacebloom 15 + Thread 25 + Copper Ore 70 + Tin Ore 80 = 190c = 1s 90c; 1 material (Silverleaf) unpriced.
Lab.Step("shopping: combined list, sources, total, warning", function()
    Tab("Shopping")
    local s = Lists().shop
    Check("display", "rows: buys by item number, then the made item",
        "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore | Bronze Bar", Names(s))
    Check("display", "Peacebloom (auction, exact)", "3 | Auction house | 15c | just now | -", Line("Peacebloom"))
    Check("display", "Silverleaf (unpriced: not enough listed)", "3 | No source | Unknown |  | -", Line("Silverleaf"))
    Check("display", "Coarse Thread (vendor)", "1 | Vendor | 25c | just now | Show vendor", Line("Coarse Thread"))
    Check("display", "Copper Ore (2 to buy for the subcraft)", "2 | Auction house | 70c | just now | -", Line("Copper Ore"))
    Check("display", "Tin Ore (vendor stack of 5 for 3 needed)", "3 | Vendor | 80c | just now | Show vendor", Line("Tin Ore"))
    Check("display", "Bronze Bar (make suggested)", "5 | Make | 1s 50c | materials, counted in their rows | Add to queue", Line("Bronze Bar"))
    Check("display", "Peacebloom detail", "Suggested source. Only the auction house has a price.", Txt(ShopRow("Peacebloom").detail))
    Check("display", "Silverleaf detail says why", "Not enough are listed at the auction house.", Txt(ShopRow("Silverleaf").detail))
    Check("display", "Tin Ore detail: leftover from the whole stack", "2 left over. Needed to make Smelt Bronze.", Txt(ShopRow("Tin Ore").detail))
    Check("display", "Bronze Bar detail: crafts, made, leftover, comparison",
        "Make 3 x Smelt Bronze: makes 6, 1 left over. Suggested source. Making this looks cheaper than buying at the auction house.", Txt(ShopRow("Bronze Bar").detail))
    Check("display", "total with the incomplete-total warning",
        "Estimated spending: 1s 90c so far. Some prices missing: 1 material has no price.", Txt(Shop().total))
    Check("display", "price source line", "Auction prices: the auction house on SimulatedRealm \194\183 just now", Txt(Shop().source))
    Check("display", "vendor status line", "Vendor prices as last seen (2 noted) \194\183 bags only", Txt(Shop().status))
    Check("display", "notes keep one short caveat about the suggestions", true, Txt(Shop().notes):find("Suggestions compare one material at a time", 1, true) ~= nil)
end)

Lab.Step("shopping: source button", function()
    -- Bronze Bar options: auction (estimate) and make. Cycle: suggestion (Make) -> Auction house -> Make (chosen) -> suggestion.
    Click(ShopRow("Bronze Bar").source, "Source (1st click)")
    Check("click", "1st click: auction house, an estimate", "5 | Auction house | about 20s | estimate, just now | -", Line("Bronze Bar"))
    Check("display", "estimate is explained on the row", true, Txt(ShopRow("Bronze Bar").detail):find("Unit-price estimate: more may cost more.", 1, true) ~= nil)
    Check("state", "choice is kept in memory", "auction", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "its reagent rows go (no subcraft now)", "Silverleaf | Coarse Thread | Peacebloom | Bronze Bar", Names(Lists().shop))
    Check("display", "total now includes the estimate: 15 + 25 + 2000 = 2040c",
        "Estimated spending: 20s 40c so far. Some prices missing: 1 material has no price.", Txt(Shop().total))
    Click(ShopRow("Bronze Bar").source, "Source (2nd click)")
    Check("state", "2nd click: make, chosen by the player", "make", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "make row again, with the reagent rows back", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore | Bronze Bar", Names(Lists().shop))
    Click(ShopRow("Bronze Bar").source, "Source (3rd click)")
    Check("state", "3rd click: back to the suggestion", "nil", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "back to the original total", "Estimated spending: 1s 90c so far. Some prices missing: 1 material has no price.", Txt(Shop().total))
    -- Peacebloom has one option (auction): the first click chooses it, the second returns to the suggestion.
    Click(ShopRow("Peacebloom").source, "Source (Peacebloom, 1st click)")
    Check("state", "single option: chosen by the first click", "auction", tostring(R.Workshop.Session.picks[2447]))
    Click(ShopRow("Peacebloom").source, "Source (Peacebloom, 2nd click)")
    Check("state", "single option: second click returns to the suggestion", "nil", tostring(R.Workshop.Session.picks[2447]))
    -- Silverleaf has no priced option. Choosing the auction house must not invent a price or a complete total.
    local total = Txt(Shop().total)
    Click(ShopRow("Silverleaf").source, "Source (Silverleaf, 1st click)")
    Say("info", "Silverleaf source button, 1st click: picks", tostring(R.Workshop.Session.picks[765]), "button now", Txt(ShopRow("Silverleaf").source.text))
    Check("display", "an unpriced material stays Unknown after a source click", "Unknown", Txt(ShopRow("Silverleaf").spend.a))
    Check("display", "the total is not made complete by a source click", total, Txt(Shop().total))
    Click(ShopRow("Silverleaf").source, "Source (Silverleaf, 2nd click)")
    Check("state", "Silverleaf back to its suggestion", "nil", tostring(R.Workshop.Session.picks[765]))
end)

Lab.Step("shopping: Show vendor", function()
    -- The intended calls are: open the world map (ToggleWorldMap) and NpcMap.Locate(entry) for a merchant seen to sell the item, and nothing
    -- that navigates. The simulator cannot run Blizzard's world map (opening it raises many Blizzard Lua errors: unsupported map APIs), so
    -- BOTH are replaced here by recording stand-ins: this checks what the Workshop asks for, not what the map then shows.
    local NM, calls, toggles = R.NpcMap, {}, 0
    local originalLocate, originalToggle = NM.Locate, ToggleWorldMap
    NM.Locate = function(e) calls[#calls + 1] = e return true end
    _G.ToggleWorldMap = function() toggles = toggles + 1 end
    local here = C_Map.GetBestMapForUnit("player")
    local pinsBefore = R.Pins.LocalCount() .. "/" .. #R.Pins.AllSharedPins()
    local navBefore = tostring(R.Nav.Active())
    local waypointBefore = C_Map.HasUserWaypoint and tostring(C_Map.HasUserWaypoint()) or "n/a"
    Click(ShopRow("Coarse Thread").act, "Show vendor (Coarse Thread)")
    NM.Locate, _G.ToggleWorldMap = originalLocate, originalToggle
    Check("click", "the world map is asked to open once", 1, toggles)
    Check("click", "Locate was called once", 1, #calls)
    Check("state", "Locate got the merchant entry (id, name, the player's map when it was noted)", "3333 | Haldric the Peddler | " .. tostring(here),
        calls[1] and (calls[1].id .. " | " .. calls[1].n .. " | " .. calls[1].m) or "no call")
    Check("display", "the note names the merchant", "Showing Haldric the Peddler on the map.", Txt(Frame().note))
    Check("state", "no waypoint was set", waypointBefore, C_Map.HasUserWaypoint and tostring(C_Map.HasUserWaypoint()) or "n/a")
    Check("state", "no pin was created (local/shared)", pinsBefore, R.Pins.LocalCount() .. "/" .. #R.Pins.AllSharedPins())
    Check("state", "no navigation was started", navBefore, tostring(R.Nav.Active()))
    -- an item no known merchant sells has no Show vendor button
    Check("display", "Peacebloom (no merchant) offers no Show vendor", "-", (Line("Peacebloom"):match("([^|]+)$"):gsub("%s", "")))
end)

Lab.Step("shopping: add the suggested subcraft", function()
    local q0 = Queue()
    Click(ShopRow("Bronze Bar").act, "Add to queue (Bronze Bar)")
    -- 3 crafts of Smelt Bronze added: needs Copper Ore 6 (bags 4 -> 2 short), Tin Ore 3 (3 short); Bronze Bar need 8, 6 will be made, 3 in bags -> 0 short
    Check("state", "Smelt Bronze x3 queued", q0 .. ", Smelt Bronze x3", Queue())
    Check("display", "the made item is no longer on the list; its ingredients are, once each",
        "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore", Names(Lists().shop))
    Check("display", "Copper Ore: queue's own need, once", "2 | Auction house | 70c | just now | -", Line("Copper Ore"))
    Check("display", "Tin Ore: queue's own need, once", "3 | Vendor | 80c | just now | Show vendor", Line("Tin Ore"))
    Check("display", "total unchanged: the ingredients are counted once", "Estimated spending: 1s 90c so far. Some prices missing: 1 material has no price.", Txt(Shop().total))
    local anyAdd = false
    for _, r in ipairs(Rows(Lists().shop)) do if r.act:IsShown() and Txt(r.act.text) == "Add to queue" then anyAdd = true end end
    Check("display", "no Add to queue button is left", false, anyAdd)
    Check("display", "the window says what it queued", "Queued 3 crafts of Smelt Bronze.", Txt(Frame().note))
    -- repeated activation (DIRECT call: the control is gone, so the session handler is what a second activation would reach)
    local ok = R.Workshop.Session.AddSubcraft(2841)
    Check("direct", "second activation adds nothing", "false", tostring(ok))
    Check("state", "queue unchanged after the repeat", q0 .. ", Smelt Bronze x3", Queue())
    Check("direct", "the repeat's note", "Nothing to add: your queue already covers that.", tostring(R.Workshop.Session.Note()))
    Tab("Crafting")
    local m = Lists().mats
    local function L(name) local r = Row(m, name) return Txt(r.need) .. "/" .. Txt(r.have) .. "/" .. Txt(r.short) end
    Check("display", "Crafting view agrees: Copper Ore need/in bags/still needed", "6/4/2", L("Copper Ore"))
    Check("display", "Crafting view: Tin Ore", "3/0/3", L("Tin Ore"))
    Check("display", "Crafting view: Bronze Bar covered by the queued crafts", "8/3/0", L("Bronze Bar"))
    Tab("Shopping")
end)

Lab.Step("shopping: bags change", function()
    BAGS[2770] = 6
    Event("BAG_UPDATE_DELAYED")
    Check("event", "enough Copper Ore: its row goes", "Silverleaf | Coarse Thread | Peacebloom | Tin Ore", Names(Lists().shop))
    Check("event", "total drops by the Copper Ore row (190 - 70 = 120c)", "Estimated spending: 1s 20c so far. Some prices missing: 1 material has no price.", Txt(Shop().total))
    BAGS[2447] = 7
    BAGS[765] = 3
    Event("BAG_UPDATE_DELAYED")
    Check("event", "Peacebloom and Silverleaf covered: rows go, the warning goes",
        "Coarse Thread | Tin Ore", Names(Lists().shop))
    Check("event", "total is exact now (25 + 80 = 105c)", "Estimated spending: 1s 5c", Txt(Shop().total))
    BAGS[2320], BAGS[2771] = 2, 3
    Event("BAG_UPDATE_DELAYED")
    Check("event", "nothing left to buy: empty state", "Nothing to buy: the materials are in your bags, or made by your queue.", Txt(Lists().shop.empty))
    Check("event", "no total when there is nothing to buy", "", Txt(Shop().total))
    SetBags({ [2447] = 4, [765] = 0, [3371] = 5, [2841] = 3, [2320] = 1, [2770] = 4 })
    Event("BAG_UPDATE_DELAYED")
    Check("event", "bags restored: five rows again", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore", Names(Lists().shop))
end)

---------------------------------------------------------------------------------------------------------------------------
-- 1b. Close and reopen
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("close and reopen", function()
    local before = { queue = Queue(), mode = Win().Mode(), total = Txt(Shop().total), rows = Names(Lists().shop) }
    Click(Frame().close, "Close button")
    Lab.Settle(0.3)
    local snap = R.Workshop.Snapshot()
    Check("click", "Close hides the window", false, Frame():IsShown())
    Check("state", "hidden window listens to nothing", "0/false", snap.events .. "/" .. tostring(snap.shown))
    Check("state", "the queue is kept while closed", before.queue, Queue())
    SlashWorkshop()
    Check("display", "/tui workshop shows it again", true, Frame():IsShown() and Frame():IsVisible())
    Check("display", "the view is the one left open", before.mode, Win().Mode())
    Check("display", "same queue", before.queue, Queue())
    Check("display", "same shopping rows", before.rows, Names(Lists().shop))
    Check("display", "same total", before.total, Txt(Shop().total))
    Tab("Crafting")
    Check("display", "Crafting after reopen: the same queue, three plus the subcraft", 4, #Rows(Lists().queue))
    Check("display", "Crafting after reopen: materials recalculated from the bags", "3 materials still needed, Peacebloom 7/4/3",
        (function()
            local r = Row(Lists().mats, "Peacebloom")
            return "3 materials still needed, Peacebloom " .. Txt(r.need) .. "/" .. Txt(r.have) .. "/" .. Txt(r.short)
        end)())
    -- Both professions are remembered by the product (not re-read: only Blacksmithing, the open one, is live now)
    local names = {}
    for _, p in ipairs(R.Workshop.Session.Professions()) do names[#names + 1] = p.name end
    Check("state", "both professions are known after reopening", "Alchemy | Blacksmithing", table.concat(names, " | "))
    Check("display", "remembered profession is labelled as remembered", true,
        (function() Click(FindButton(Frame(), "Alchemy"), "Alchemy chip") return Txt(Frame().notice):find("Remembered from", 1, true) ~= nil end)())
    Click(FindButton(Frame(), "Blacksmithing"), "Blacksmithing chip")
end)

---------------------------------------------------------------------------------------------------------------------------
-- 1c. Remembered recipes, with no profession open (handler level and in-memory: NOT a real /reload)
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("remembered recipes: closed window, background read, nothing open", function()
    Click(Frame().close, "Close button")
    Lab.Settle(0.3)
    local W = R.Workshop
    local reads = W.Watch.reads
    -- the window is closed and the Workshop addon is loaded: a profession being opened is read without the window
    Check("state", "window hidden: it listens to nothing, the watcher does", "0/4", W.Snapshot().events .. "/" .. W.Snapshot().watchEvents)
    ShowProfession(PROF.alch)
    Lab.Settle(1)
    Check("event", "an own profession opened while the window is closed is read once", reads + 1, W.Watch.reads)
    Check("state", "and its recipes are saved for this character", 5, #TwichUIDB.workshop.chars[W.Queue.CharKey()].known[171].r)
    Check("state", "the copy in memory is let go of", 0, W.Snapshot().professions)
    -- now nothing is open at all (the fake game answers no profession): the saved recipes are what the Workshop works from
    local saved = open
    open = { id = nil, name = nil, recipes = {} }
    T.GetBaseProfessionInfo = function() return nil end
    SlashWorkshop()
    Tab("Opportunities")
    Check("display", "no profession open: both professions come from what was saved", "Alchemy | Blacksmithing", (function()
        local n = {} for _, p in ipairs(W.Session.Professions()) do n[#n + 1] = p.name end return table.concat(n, " | ") end)())
    Check("display", "Opportunities lists all seven recipes from saved knowledge, priced from the saved scan", "5 of 7 priced", Txt(Opps().summary):match("^(%d+ of %d+ priced)"))
    Tab("Crafting")
    Check("display", "Crafting says the list is remembered", true, Txt(Frame().notice):find("Remembered from", 1, true) ~= nil)
    -- restore the open profession for the screenshot poses
    T.GetBaseProfessionInfo = function() return { professionID = open.id, professionName = open.name } end
    open = saved
    ShowProfession(PROF.smith)
end)

---------------------------------------------------------------------------------------------------------------------------
-- The pose a screenshot is taken in (params.view). The checks above are the same in every launch.
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("pose for the screenshot", function()
    local view = params.view or "craft"
    Say("pose", view)
    if view == "craft" then
        Tab("Crafting")
        Click(FindButton(Frame(), "Alchemy"), "Alchemy chip")
    elseif view == "opps" then
        Tab("Opportunities")
        -- scrolling: seven rows of 46 px do not fit the 304 px list. One row down (46 px): the first row is gone, the last is whole.
        Lists().opps.scroll:SetVerticalScroll(46)
        Lab.Settle(0.1)
        Check("display", "pose: scrolled one row, the list starts at the second row and ends with the last",
            "Minor Healing Potion|Enchant Bracer - Lesser Choice", (function()
                local n = Names(Lists().opps) local first = n:match("^[^|]-%s*|") or n
                return (n:match("^(.-) | ") or n) .. "|" .. (n:match(" | ([^|]-)$") or n)
            end)())
        Lists().opps.scroll:SetVerticalScroll(0)
    elseif view == "shop" then
        -- the mixed-source list with a Make row: take the Smelt Bronze entry back out through its Remove button
        Tab("Crafting")
        local q = Lists().queue
        Click(Rows(q)[4].remove, "Remove Smelt Bronze")
        Tab("Shopping")
        Check("display", "pose: shopping shows the Make row again", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore | Bronze Bar", Names(Lists().shop))
        -- scrolling: six rows of 54 px do not fit the 296 px list. One row down puts the Make row in view.
        Lists().shop.scroll:SetVerticalScroll(54)
        Lab.Settle(0.1)
        Check("display", "pose: scrolled one row, the Make row is at the bottom of the list", "Coarse Thread|Bronze Bar",
            (function() local n = Names(Lists().shop) return (n:match("^(.-) | ") or n) .. "|" .. (n:match(" | ([^|]-)$") or n) end)())
    end
    Lab.Settle(0.5)
end)

Lab.Finish()
