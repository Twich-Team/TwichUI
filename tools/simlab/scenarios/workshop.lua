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
Lab.BUDGET = 36   -- (A6) the automatic-update step needs one scan's quiet period of simulated time (was 30); the delayed failures that grow with time are classified by the verdict
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

-- the character's professions and their skill (Observe.Skills: GetProfessions / GetProfessionInfo, which the Forever profession book also calls)
local SKILLS = { { "Alchemy", 136240, 125, 150 }, { "Blacksmithing", 136241, 80, 100 }, { "Fishing", 136245, 75, 150 } }
GetProfessions = function() return 1, 2, nil, 3 end
GetProfessionInfo = function(i) local k = SKILLS[i] if k then return k[1], k[2], k[3], k[4] end end

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
    if depth > 6 then return nil end
    for _, c in ipairs({ root:GetChildren() }) do
        if c.text and c.text.GetText and c.text:GetText() == text and c:IsVisible() then return c end   -- only what a player could click
        local hit = FindButton(c, text, depth + 1)
        if hit then return hit end
    end
end
local function Click(btn, what)
    if not btn then error("missing control: " .. tostring(what)) end
    if btn.IsEnabled and not btn:IsEnabled() then error("control is disabled: " .. tostring(what)) end
    btn:Click()
end
local function QueueAct(row, which, what)   -- Open recipe and Remove sit in the chosen craft's details: choose the row, then the action
    Click(row, "choose the queued craft for: " .. tostring(what))
    Click(Win().Craft()[which], what)
end
local function Queue()   -- the saved queue, read back: "name x crafts, ..."
    local out = {}
    for _, e in ipairs(R.Workshop.Queue.Entries()) do out[#out + 1] = e.name .. " x" .. e.crafts end
    return table.concat(out, ", ")
end
-- the window redraws 0.2 s after an event (Window.lua SETTLE); 0.3 s is past that, and the check that follows still reads the redrawn page
local function Event(name) A_Admin.FireEvent(name) Lab.Settle(0.3) end
local function Opps() return Win().Opps() end
local function ProfitHead() local h = Win().Heads().profit return Txt(h.text) .. " " .. Txt(h.sub) end   -- the profit heading: its label, and its qualification beneath
local function Shop() return Win().Shop() end
local function Lists() return Win().Lists() end

local function Tab(name)   -- the page list on the left
    local f = Frame()
    local b = ({ Overview = f.tabOverview, Crafting = f.tabCraft, Shopping = f.tabShop, Opportunities = f.tabOpps })[name]
    Click(b, "tab " .. name)
    Lab.Settle(0.1)   -- the page switch is synchronous; the next frame runs the page's batched reading
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
    Check("display", "window opens on the Overview", "overview", Win().Mode())
    Check("display", "Overview shown, Crafting, Shopping and Opportunities hidden", "true/false/false/false",
        tostring(Win().Overview():IsVisible()) .. "/" .. tostring(Lists().recipes.box:IsVisible()) .. "/" .. tostring(Shop():IsShown()) .. "/" .. tostring(Opps():IsShown()))
    Check("display", "the page list marks Overview", "true/false", tostring(Frame().tabOverview.on) .. "/" .. tostring(Frame().tabCraft.on))
    Check("display", "Overview: no scan yet is said, not a made-up price", "No scan yet", Txt(Win().Overview().cards.market.facts[1].text))
    Check("display", "Overview: no price count is invented before a scan", "\226\128\148 | no prices yet",
        Txt(Win().Overview().cards.market.stat) .. " | " .. Txt(Win().Overview().cards.market.statLabel))
    do
        local rows = Win().Overview().cards.profs.facts
        local function PRow(i) return Txt(rows[i].text) .. " | " .. Txt(rows[i].value) .. " | " .. ("%.4f"):format(rows[i].bar.frac) end
        -- the game's own answer (GetProfessions: Alchemy 125 of 150, Blacksmithing 80 of 100, Fishing 75 of 150): 125/150, 80/100, 75/150
        Check("display", "Overview: Alchemy skill and its bar", "Alchemy | 125 / 150 | 0.8333", PRow(1))
        Check("display", "Overview: Blacksmithing skill and its bar", "Blacksmithing | 80 / 100 | 0.8000", PRow(2))
        Check("display", "Overview: Fishing skill and its bar (a profession the Workshop never read)", "Fishing | 75 / 150 | 0.5000", PRow(3))
        Check("display", "Overview: no fourth profession row", false, rows[4]:IsShown())
    end
    Check("display", "Overview: an empty plan", "0 | of 30 queued", Txt(Win().Overview().cards.plan.stat) .. " | " .. Txt(Win().Overview().cards.plan.statLabel))
    Check("display", "Overview: the quick action to scan prices exists", "Scan prices/true", Txt(Win().Overview().actions.scan.text) .. "/" .. tostring(Win().Overview().actions.scan:IsEnabled()))
    Check("display", "Overview: nothing has happened yet this session", true, Win().Overview().bottom.empty:IsShown())
    Tab("Crafting")
    Check("click", "Crafting tab: mode", "craft", Win().Mode())
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
    Check("display", "empty queue says so", "Nothing queued yet. Choose Add recipe, then Add on a recipe.", Txt(Lists().queue.empty))
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
    QueueAct(q, "remove", "Remove (unsupported recipe)")
    Check("state", "unsupported recipe removed", "", Queue())
    Check("display", "queue count after remove", "0 of 30", Txt(Frame().queueCount))
    Check("display", "empty materials headline", "Add recipes to see the materials you need.", Txt(Frame().headline))
end)

Lab.Step("crafting: add, change quantity, remove", function()
    local list = Lists().recipes
    Click(Row(list, "Minor Healing Potion").add, "Add Minor Healing Potion")
    Click(Row(list, "Weak Troll's Blood Potion").add, "Add Weak Troll's Blood Potion")
    Check("state", "two recipes queued, one craft each", "Minor Healing Potion x1, Weak Troll's Blood Potion x1", Queue())
    Check("display", "added recipe's row now says Queued in its mark, and its Add is gone and disabled", "Queued/true/false/false",
        Txt(Row(list, "Minor Healing Potion").mark.text) .. "/" .. tostring(Row(list, "Minor Healing Potion").mark:IsShown()) .. "/"
        .. tostring(Row(list, "Minor Healing Potion").add:IsShown()) .. "/" .. tostring(Row(list, "Minor Healing Potion").add:IsEnabled()))
    local q = Lists().queue
    local a, b = Rows(q)[1], Rows(q)[2]
    Check("display", "queue order and labels", "Minor Healing Potion | Weak Troll's Blood Potion", Names(q))
    Check("display", "the first queued craft's details, with its profession", "Minor Healing Potion | Alchemy",
        Txt(Win().Craft().detail.name) .. " | " .. Txt(Win().Craft().detail.prof))
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
    QueueAct(Rows(q)[2], "remove", "Remove Weak Troll's Blood Potion")
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
    Check("event", "headline when everything is in the bags", "Ready to craft: all the materials are in your bags.", Txt(Frame().headline))
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
    QueueAct(Rows(Lists().queue)[1], "open", "Open recipe")
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
    local function StatusTip() local b = Opps().statusBox return b.twichuiTip.body(b) end
    Check("display", "no prices yet: the status tooltip says so (the source is no longer a line on the page)", "No saved prices for this auction house yet.", StatusTip())
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
    -- 17 listings are read; 1 does not count: a bid-only Peacebloom (buyout 0) -> 16 used. Every item with a usable listing is kept, whether
    -- or not a recipe uses it: the 12 recipe items with a listing (2447 765 3371 2450 2770 2771 2841 118 3382 3390 9999 2851; Coarse Thread
    -- 2320 has none) plus 55555 = 13.
    Check("state", "records read / used / items priced / complete", "17/16/13/true", ("%s/%s/%s/%s"):format(res.read, res.used, res.items, tostring(res.complete)))
    Check("display", "status line after the scan", "Scan finished. Prices found for 13 items.", Txt(Opps().status))
    Check("display", "button back to Scan prices", "Scan prices/true", Txt(Opps().scan.text) .. "/" .. tostring(Opps().scan:IsEnabled()))
    Check("display", "progress bar hidden after the scan", false, Opps().bar:IsShown())
    do
        local b = Opps().statusBox
        local tip = Norm(b.twichuiTip.body(b))
        Check("display", "the status tooltip names the market and how old it is", "Prices: the auction house on SimulatedRealm \194\183 just now", (tip:match("^[^\n]*")))
    end
    -- the saved cheapest unit prices (hand arithmetic: stack buyout / stack count, rounded up)
    local items = TwichUIWorkshopDB.markets["SimulatedRealm|unknown"].items
    local function P(id) local e = items[id] local a, b, c, d = (e or ""):match("^(%d+),(%d+),(%d+),(%d+),%d+$") return a and ("%d/%d/%d/%d"):format(a, b, c, d) or "none" end
    Check("state", "Peacebloom cheapest 5c (100/20), 20 at that price, 2 buyout listings, 30 items", "5/20/2/30", P(2447))
    Check("state", "Bronze Bar cheapest 400c (800/2), 2 at that price, 2 listings, 5 items", "400/2/2/5", P(2841))
    Check("state", "Coarse Thread has no price", "none", P(2320))
    Check("state", "an item no recipe uses is priced too: 3 for 999 is 333c each", "333/3/1/3", P(55555))
    -- A3: the price distribution kept beside the minimum entries. Hand arithmetic: Peacebloom is 20 at 5c and 10 at 7c (30 items, the 25% mark
    -- is passed inside the first price, so Recent Price 5c); Bronze Bar 2 at 400c and 3 at 500c (the cheapest 30% of 5 items is 1.5 items, all at
    -- 400c); the two Frostweave-like single listings of item 118 are 150c and 180c. Every other item has one price: no entry.
    local mk = TwichUIWorkshopDB.markets["SimulatedRealm|unknown"]
    local ids = {}
    for id in pairs(mk.dist or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    Check("state", "the scan kept a checked distribution (algorithm 1) for the three items with two prices, and for no other", "1/118,2447,2841", tostring(mk.snap.alg) .. "/" .. table.concat(ids, ","))
    Check("state", "Peacebloom distribution", "1,5,5,5,5,7,7,20|5:20:1;7:10:1", tostring(mk.dist[2447]))
    Check("state", "Bronze Bar distribution", "1,400,400,400,500,500,500,2|400:2:1;500:3:1", tostring(mk.dist[2841]))
    Check("state", "item 118 distribution", "1,150,150,150,150,180,180,1|150:1:1;180:1:1", tostring(mk.dist[118]))
    Check("state", "the scan reports the algorithm of the distribution it kept", "1", tostring(R.Workshop.Scan.result.alg))
    -- A4: the version-2 history recorded from the same scan (the A3 observation of each listed item): one ring point and one daily point.
    -- Peacebloom: minimum 5c, Recent Price 5c (dr 0), 30 items in 2 listings; the 3-for-999 item has one price, so Recent Price = minimum.
    local h2 = mk.h2 or {}
    local function Shape(id) return ((h2[id] or ""):gsub("^%d+,", "M,"):gsub("|%d+:%d+,", "|D:D,")) end
    Check("state", "A4: Peacebloom's history: one observation and one day, Recent Price = minimum here", "M,0,5,0,30,2|D:D,5,0,30,2", Shape(2447))
    Check("state", "A4: a one-price item records r = p (dr 0), never an empty Recent Price", "M,0,333,0,3,1|D:D,333,0,3,1", Shape(55555))
    Check("state", "A4: no history for an item with no buyout listing", "nil", tostring(h2[2320]))
    local n2 = 0
    for _ in pairs(h2) do n2 = n2 + 1 end
    Check("state", "A4: one history entry per priced item, and the history's own record", "13/13/1", ("%d/%s/%s"):format(n2, tostring(mk.h2info and mk.h2info.items), tostring(mk.h2info and mk.h2info.v)))
    Check("state", "A4: the scan log says this scan was recorded (flags 1 + 2 + 64)", "67", (mk.scans[#mk.scans] or ""):match("^%d+,%d+,(%d+),") or "none")
    local hs = R.Workshop.Market.History(2447, "recent", { market = "SimulatedRealm|unknown" })
    local kinds = {}
    for _, pnt in ipairs(hs and hs.points or {}) do kinds[#kinds + 1] = pnt.kind .. ":" .. tostring(pnt.v) end
    Check("state", "A4: Market.History gives a day point and an observation, nothing invented", "day:5,obs:5", table.concat(kinds, ","))
    -- A5: the valuation services over the same saved scan, read-only. Hand arithmetic: Bronze Bar is one stack of 2 at 400c and one of 3 at 500c,
    -- so buying 3 is 2 x 400 + 1 x 500 = 1300c, or 2300c if the whole 3-stack must be bought (a range); its Recent Price is 400c and the cheapest
    -- price at or above half the anchor (400c) is 400c itself, with 2 items at or below it. Peacebloom has 2 listings (thin: limited quality)
    -- and one recorded day (Market Value 5c from one day; Historical Value needs 3 days).
    local function Sig()
        local parts = {}
        for _, tb in ipairs({ mk.items, mk.dist or {}, mk.h2 or {}, mk.c2 or {} }) do
            local keys = {}
            for k in pairs(tb) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(tb[k]) end
        end
        return table.concat(parts, ";") .. "|" .. tostring(mk.snap.seq) .. "|" .. tostring(TwichUIWorkshopDB.v)
    end
    local before = Sig()
    local MKt, opt = R.Workshop.Market, { market = "SimulatedRealm|unknown" }
    local function V(id, kind) local v, why = MKt.Value(id, kind, opt) return v and tostring(v.value) or ("nil:" .. tostring(why)) end
    Check("state", "A5: Minimum Buyout, Recent Price, Market Value, Historical Value of Peacebloom", "5/5/5/nil:insufficient", V(2447, "min") .. "/" .. V(2447, "recent") .. "/" .. V(2447, "market") .. "/" .. V(2447, "historical"))
    Check("state", "A5: Bronze Bar's Recent Price", "400", V(2841, "recent"))
    local cost = MKt.Cost(2841, 3, opt)
    Check("state", "A5: buying 3 Bronze Bars: a range, whole stacks", "range/1300/2300", ("%s/%s/%s"):format(cost.state, tostring(cost.low), tostring(cost.high)))
    local comp = MKt.Competition(2841, 1, opt)
    Check("state", "A5: Bronze Bar competition: the competing price and the items at or below it", "400/2/competition", ("%s/%s/%s"):format(tostring(comp and comp.competing), tostring(comp and comp.ahead), tostring(comp and comp.role)))
    local q = MKt.Quality(2447, opt)
    Check("state", "A5: Peacebloom's Data Quality (2 listings, one observed day): limited, policy 1", "limited/1/Only 2 listings.", ("%s/%s/%s"):format(q.level, tostring(q.policy), tostring(q.reasons[1] and q.reasons[1].text)))
    Check("state", "A5: posture needs more evidence", "unknown", MKt.Posture(2447, opt).posture)
    Check("state", "A5: nothing above changed the saved prices", "same", Sig() == before and "same" or "changed")
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
        "Unknown for profit; 1 material has no price \194\183 In your queue", (OppLine("Copper Belt Buckle"):find("Unknown | .*Unknown$") and "Unknown for profit" or OppLine("Copper Belt Buckle")) .. "; " .. Txt(Row(o, "Copper Belt Buckle").sub))
    Check("display", "unsupported recipe: Unknown with its reason", "Its materials aren't known or can't be counted", Txt(Row(o, "Enchant Bracer - Lesser Choice").sub))
    Check("display", "output basis under a priced name (quantity and profession)", "Alchemy \194\183 makes 1-3", Txt(Row(o, "Elixir of Many Wonders").sub))
    Check("display", "output basis for a fixed output", "Blacksmithing \194\183 makes 2", Txt(Row(o, "Smelt Bronze").sub))
    do
        local b = Opps().statusBox
        local tip = Norm(b.twichuiTip.body(b))
        Check("display", "the before-fees qualification is in the status tooltip, and the page carries no summary or footer paragraphs",
            "true/true/nil/nil/nil", tostring(tip:find("Profit is before fees: the auction house's cut isn't confirmed.", 1, true) ~= nil) .. "/"
            .. tostring(tip:find("Some recipes may be missing", 1, true) ~= nil) .. "/" .. tostring(Opps().summary) .. "/" .. tostring(Opps().notes) .. "/" .. tostring(Opps().about))
    end
    Check("display", "profit column is not called estimated while no cut is taken off", "Profit before fees", ProfitHead())
    Check("display", "no Profitable only switch in the toolbar", "nil", tostring(Opps().profitOnly))
    local H = Win().Heads()
    Check("display", "sort indicator: profit is the sort (gold triangle pointing down, highest first); the others only hint", "true/true/false/false/true/true",
        tostring(H.profit.active) .. "/" .. tostring(H.profit.tri:IsShown()) .. "/" .. tostring(H.cost.active) .. "/" .. tostring(H.cost.tri:IsShown()) .. "/" .. tostring(H.cost.hintUp:IsShown()) .. "/" .. tostring(H.sell.hintDown:IsShown()))
    Check("display", "sort indicator direction: down for highest first", "down", H.profit.tri.dir)

    -- sort: Cost to make. First click = cheapest first; ties by name. Costs: 30 (Elixir, Greater Elixir, Weak Troll's), 70 (Minor), 100 (Smelt).
    Click(Win().Heads().cost, "Cost to make heading")
    Check("display", "sort indicator moves to Cost to make, pointing up for cheapest first", "true/up/false",
        tostring(Win().Heads().cost.active) .. "/" .. tostring(Win().Heads().cost.tri.dir) .. "/" .. tostring(Win().Heads().profit.active))
    Check("click", "sort by cost, cheapest first",
        "Elixir of Many Wonders | Greater Elixir of Extremely Long Fortitude Name | Weak Troll's Blood Potion | Minor Healing Potion | Smelt Bronze | Copper Belt Buckle | Enchant Bracer - Lesser Choice", Names(o))
    Click(Win().Heads().cost, "Cost to make heading (second click)")
    Check("display", "the second click turns the indicator down", "down", Win().Heads().cost.tri.dir)
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

    -- the filter's logic is kept (Session), though the toolbar no longer carries its switch: it drops the loss and the unknowns
    R.Workshop.Session.ToggleProfitOnly(); R.Workshop.UI.Redraw()
    Check("direct", "profitable only: losses and unknowns hidden", "Smelt Bronze | Minor Healing Potion | Elixir of Many Wonders | Weak Troll's Blood Potion", Names(o))
    R.Workshop.Session.ToggleProfitOnly(); R.Workshop.UI.Redraw()
    Check("direct", "profitable only off shows all again", 7, #Rows(o))
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

-- The fake item APIs and a captured GameTooltip the "what's it worth" steps share. WorthWorld() installs them and returns the world:
-- w.Hover(id, data) calls the product's WorthTip.OnItem and returns the lines it ADDED (the simulator does not draw tooltips), w.SetShift(on),
-- w.Restore() puts the real functions back. The item APIs are FAKE (bag item locations, binding, links); the prices are the real saved scan.
local function WorthWorld()
    local WT = R.Workshop.WorthTip
    local tt = GameTooltip
    local oldLine, oldDouble, oldShift = tt.AddLine, tt.AddDoubleLine, IsShiftKeyDown
    local oldInfo, oldItem = C_Item.GetItemInfo, {}
    for _, k in ipairs({ "GetItemLocation", "DoesItemExist", "GetItemLink", "GetItemID", "IsBound", "GetStackCount", "GetDetailedItemLevelInfo" }) do oldItem[k] = C_Item[k] end
    local W = {   -- id = { sell, quality, class, bind, bound, count, link }
        [118] = { 60, 1, 7, 0 }, [2841] = { 500, 1, 7, 0 }, [9999] = { 10, 2, 4, 2 }, [2320] = { 20, 1, 7, 0 }, [2447] = { 4, 1, 7, 1, true },
        [3382] = { 30, 1, 7, 0, false, 20 }, [765] = { 3, 1, 7, 0, false, 1, "|cffffffff|Hitem:765::::::-15|h[Silverleaf of the Bear]|h|r" },
    }
    C_Item.GetItemLocation = function(guid) local id = tonumber(tostring(guid):match("^Item%-(%d+)")) if id and W[id] then return { id = id, IsBagAndSlot = function() return true end } end end
    C_Item.DoesItemExist = function(loc) return W[loc.id] ~= nil end
    C_Item.GetItemID = function(loc) return loc.id end
    C_Item.GetItemLink = function(loc) return W[loc.id][7] or ("|cffffffff|Hitem:" .. loc.id .. "::::::::80|h[" .. ITEMS[loc.id] .. "]|h|r") end
    C_Item.IsBound = function(loc) return W[loc.id][5] == true end
    C_Item.GetStackCount = function(loc) return W[loc.id][6] or 1 end
    C_Item.GetDetailedItemLevelInfo = function() return 10, false, 10 end
    C_Item.GetItemInfo = function(x)
        local id = type(x) == "number" and x or tonumber(tostring(x):match("Hitem:(%d+)"))
        local w = id and W[id]
        if not w then return oldInfo(x) end
        return ITEMS[id], "link", w[2], 10, 1, "", "", 20, "", ICON, w[1], w[3], 0, w[4]
    end
    local lines, mlines, shift = {}, {}, false
    -- the A7 market lines (Market value, Recent price, Historical value, Supply, Market data) are collected apart: the checks of the older lines
    -- compare the Vendor / Auction / recommendation lines exactly as before, and the market lines have checks of their own (HoverMarket)
    local function IsMarket(text) return text:find("^Market value") or text:find("^Recent price") or text:find("^Historical value") or text:find("^Supply") or text:find("^Market data") end
    tt.AddLine = function(_, text) if text ~= " " then if IsMarket(text) then mlines[#mlines + 1] = text else lines[#lines + 1] = text end end end
    tt.AddDoubleLine = function(_, a, b) if IsMarket(a) then mlines[#mlines + 1] = a .. " | " .. b else lines[#lines + 1] = a .. " | " .. b end end
    IsShiftKeyDown = function() return shift end
    local function Hover(id, data)
        lines, mlines = {}, {}
        WT.OnItem(tt, data or { guid = "Item-" .. id .. "-0", id = id })
        return Norm(table.concat(lines, " / "))
    end
    local function HoverMarket(id) Hover(id) return Norm(table.concat(mlines, " / ")) end

    return {
        WT = WT, tt = tt, ah = ah,
        Hover = Hover, HoverMarket = HoverMarket,
        SetShift = function(on) shift = on end,
        Restore = function()
            tt.AddLine, tt.AddDoubleLine, IsShiftKeyDown, C_Item.GetItemInfo = oldLine, oldDouble, oldShift, oldInfo
            for k, v in pairs(oldItem) do C_Item[k] = v end
        end,
    }
end

Lab.Step("what's it worth: item tooltip lines", function()
    -- WorthTip.OnItem (the product's own tooltip post call) is called directly with a captured GameTooltip: the simulator does not draw
    -- tooltips or run Blizzard's post calls, so this proves the lines the product ADDS, not how the game lays them out (layer "direct").
    -- The item APIs are FAKE (bag item locations, binding, links); the prices are the real saved scan of the step before, which had no
    -- auction house side, so the cut is unconfirmed. Hand arithmetic (copper): Minor Healing Potion lists at 150 and 180 -> cheapest 150;
    -- Bronze Bar 800/2 = 400 and 1500/3 = 500 -> 400; Greater Elixir 25; Coarse Thread has no listing; Peacebloom is not used.
    local w = WorthWorld()
    local WT, Hover, tt = w.WT, w.Hover, w.tt
    Check("init", "the tooltip module is loaded with the addon", "table", type(WT))
    Say("TooltipDataProcessor in the simulator: " .. tostring(rawget(_G, "TooltipDataProcessor") ~= nil) .. "; registered by the product: " .. tostring(WT.registered))
    local requestsBefore = ah.requested
    Check("direct", "no cut confirmed, the auction is dearer: the fee is named and no winner is claimed",
        "What's it worth? / No suggestion: auction fee unknown / Vendor | 60c / Auction (before fees) | 1s 50c / Hold Shift for details", Hover(118))
    Check("direct", "the vendor wins even before fees (the cut can only lower the auction)",
        "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / Hold Shift for details", Hover(2841))
    Check("direct", "repeating the update gives the same lines, not more",
        "What's it worth? / No suggestion: auction fee unknown / Vendor | 60c / Auction (before fees) | 1s 50c / Hold Shift for details", Hover(118))
    Check("direct", "green armour: disenchant has no data, so it is said and no winner is claimed",
        "What's it worth? / Disenchant value unknown / Vendor | 10c / Auction (before fees) | 25c / Disenchant (average) | no data / Hold Shift for details", Hover(9999))
    Check("direct", "a bound item cannot be listed (unavailable, not unknown)",
        "What's it worth? / Vendor | 4c / Auction | can't be listed (bound)", Hover(2447))
    Check("direct", "an item with no listing: no price (never 0), more prices needed",
        "What's it worth? / More prices needed / Vendor | 20c / Auction | no price / Hold Shift for details", Hover(2320))
    Check("direct", "a random-properties variant is not priced from the base item's listings",
        "What's it worth? / No suggestion: this variant isn't priced / Vendor | 3c / Auction | this variant isn't priced", Hover(765))
    Check("direct", "a stack says the values are for one item",
        "What's it worth? (each) / No suggestion: auction fee unknown / Vendor | 30c / Auction (before fees) | 60c / Hold Shift for details", Hover(3382))
    -- 3382: Weak Troll's Blood Potion 300/5 = 60c each
    Check("direct", "an item the player does not hold (no guid) gets nothing", "", Hover(118, { id = 118 }))

    w.SetShift(true)
    local long = Hover(118)
    Check("direct", "Shift: the Always lines plus the age and the source, once each, and the unconfirmed cut stays on the value",
        "What's it worth? / No suggestion: auction fee unknown / Vendor | 60c / Auction (before fees) | 1s 50c / Scanned | just now / Prices from | the auction house on SimulatedRealm / Estimates, not sales. Deposits and failed listings aren't counted.", long)
    local _, n = long:gsub("Deposits and failed listings", "")
    Check("direct", "Shift: the deposit / failed-listing exclusion is stated once", 1, n)
    Check("direct", "Shift: the details stay short enough for a tooltip", true, select(2, long:gsub(" / ", "")) + 1 <= 10)
    w.SetShift(false)
    Check("direct", "released: the short form again, nothing left over", "What's it worth? / No suggestion: auction fee unknown / Vendor | 60c / Auction (before fees) | 1s 50c / Hold Shift for details", Hover(118))

    -- TEST INPUT: a made-up 5% cut for the 'unknown' side (the product's PR.CUT is empty). 150 x 0.05 = 7.5 -> 8, net 142.
    R.Workshop.Prices.CUT.unknown = 0.05
    Check("direct", "[test input] with a cut the auction wins, after the cut",
        "What's it worth? / Suggested: Auction house / Vendor | 60c / Auction (after fees) | 1s 42c / Hold Shift for details", Hover(118))
    R.Workshop.Prices.CUT.unknown = nil
    Check("direct", "test cut removed: back to before fees", true, Hover(118):find("Auction (before fees) | 1s 50c", 1, true) ~= nil)

    Check("state", "no auction house request was made by any tooltip", requestsBefore, ah.requested)
    w.Restore()
end)

-- THE TOOLTIP DESIGNER (TwichUI_Settings/pages/WorkshopWorth.lua), opened on the Workshop page of the real settings window. Buttons are
-- driven with Button:Click() (HANDLER LEVEL, layer "click"); the drag HANDLERS (OnDragStart / OnDragStop, with GetCursorPosition faked to a
-- point over the mockup) are called directly (layer "direct"): they prove what a drop does, NOT that a real pointer can drag anything in
-- the game. The live tooltip is WorthTip.OnItem over the same fake items as the step before; the mockup and the tooltip are compared
-- as text. Example "ordinary" is the same numbers as Bronze Bar here (vendor 5s, cheapest listing 4s), so their Normal lines are equal.
Lab.Step("what's it worth: tooltip designer", function()
    local w = WorthWorld()
    local WL = R.Workshop.WorthLayout
    local ok = Lab.Open("workshop")
    Check("init", "the settings window opened on the Workshop page", true, ok == true)
    local D = R.WorkshopWorthDesigner
    Check("init", "the designer is loaded with the settings window", "table", type(D))
    local f = D.Frame()
    Check("init", "with the Workshop loaded, the designer (not the invitation) is shown", true, f:IsShown() and f.mock:IsShown() and not f.inviteButton:IsShown())
    Check("display", "the list has the eight line types", 8, (function() local n = 0 for i = 1, 8 do if D.ListButton(i) and D.ListButton(i):IsShown() then n = n + 1 end end return n end)())
    Check("display", "one instruction", "Drag lines into the preview.", Txt(f.instruction))

    local function Mock()   -- what the mockup shows, top to bottom (rows without anything to say are the designer's own placeholders)
        local out = { Txt(f.mock.title) }
        for i = 1, #D.Model().sec.rows do
            local r = D.Row(i)
            local text = r.wide:IsShown() and Txt(r.wide) or (Txt(r.left) .. " | " .. Txt(r.right))
            if not text:find("^%(?Market value") and not text:find("^%(?Recent price") and not text:find("^%(?Historical value") and not text:find("^%(?Supply")
                and not text:find("^%(?Market data") then out[#out + 1] = text end   -- (the A7 market lines have their own check)
        end
        if f.mock.hint:IsShown() then out[#out + 1] = Txt(f.mock.hint) end
        return table.concat(out, " / ")
    end
    local function NoPlaceholders(text) return (text:gsub(" / %(%u[^%)]-%)%)", ""):gsub(" / %([^/]-nothing to show for this example%)", "")) end
    local A7 = { marketvalue = true, recent = true, historical = true, supply = true, quality = true }   -- (the A7 lines: checked on their own)
    local function Layout() local t = {} for _, e in ipairs(WL.Get().lines) do if not A7[e.id] then t[#t + 1] = e.id .. (e.when == "shift" and "*" or "") end end return table.concat(t, ",") end
    local DEFAULT = "recommend,vendor,auction,disenchant,status*,source*,note*"
    local function Live(shiftHeld) w.SetShift(shiftHeld) return w.Hover(2841) end   -- Bronze Bar: vendor 5s, cheapest listing 4s, before fees

    Check("state", "the layout starts as the short default", DEFAULT, Layout())
    Check("state", "the A7 market lines are in the default: market value Always, the rest Hold Shift", "marketvalue,recent*,historical*,supply*,quality*",
        (function() local t = {} for _, e in ipairs(WL.Get().lines) do if A7[e.id] then t[#t + 1] = e.id .. (e.when == "shift" and "*" or "") end end return table.concat(t, ",") end)())
    Check("direct", "the live tooltip carries the market value line, labelled as a 14-day reference", true, w.HoverMarket(2841):find("Market value (14 days)", 1, true) ~= nil)
    Check("display", "Normal preview of the ordinary example",
        "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / (Disenchant value (average): nothing to show for this example) / Hold Shift for details", Mock())
    Check("display", "labelled as preview data", true, Txt(f.caption):find("Preview data", 1, true) ~= nil)
    Check("direct", "the live tooltip for the same numbers has the same lines (minus the designer's placeholder)",
        "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / Hold Shift for details", Live(false))
    Check("display", "the preview without its placeholder equals the live tooltip", Live(false), NoPlaceholders(Mock()))

    Click(f.modeShift, "Hold Shift preview")
    Check("display", "Hold Shift preview adds the Shift lines to the Always lines, once each",
        "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / (Disenchant value (average): nothing to show for this example) / Scanned | 3 hours ago / Prices from | the example auction house / Estimates, not sales. Deposits and failed listings aren't counted.", Mock())
    Check("direct", "the live tooltip with Shift held has the same kinds of lines (this scan's own age and market)",
        "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / Scanned | just now / Prices from | the auction house on SimulatedRealm / Estimates, not sales. Deposits and failed listings aren't counted.", Live(true))
    Click(f.modeNormal, "Normal preview")

    -- select and move (buttons): Vendor down one, past Auction
    Click(D.Row(2), "the Vendor row")
    Check("state", "clicking a row selects it", "vendor", D.Selected())
    Click(f.down, "Move down")
    Check("state", "Move down puts Vendor after Auction", "recommend,auction,vendor,disenchant,status*,source*,note*", Layout())
    Check("display", "and the preview shows it", "What's it worth? / Suggested: Vendor / Auction (before fees) | 4s / Vendor | 5s / (Disenchant value (average): nothing to show for this example) / Hold Shift for details", Mock())
    Check("direct", "and the live tooltip follows at once", "What's it worth? / Suggested: Vendor / Auction (before fees) | 4s / Vendor | 5s / Hold Shift for details", Live(false))

    -- Always -> Hold Shift for Auction: the recommendation is untouched and the value keeps its own "before fees"
    Click(D.Row(2), "the Auction row")
    Click(f.holdShift, "Hold Shift (visibility)")
    Check("state", "Auction is a Hold Shift line", "recommend,auction*,vendor,disenchant,status*,source*,note*", Layout())
    Check("state", "the Hold Shift preview came up so the line stays in view", true, D.Mode())
    Check("direct", "live, Shift not held: no auction line, the suggestion unchanged", "What's it worth? / Suggested: Vendor / Vendor | 5s / Hold Shift for details", Live(false))
    Check("direct", "live, Shift held: the auction line is back in its place, with 'before fees', once",
        "What's it worth? / Suggested: Vendor / Auction (before fees) | 4s / Vendor | 5s / Scanned | just now / Prices from | the auction house on SimulatedRealm / Estimates, not sales. Deposits and failed listings aren't counted.", Live(true))
    w.SetShift(false)

    -- remove, and click to add again; no duplicate
    Click(D.Row(#D.Model().sec.rows), "the last row (Limits note)")
    Check("state", "selected the Limits note", "note", D.Selected())
    Click(f.remove, "Remove")
    Check("state", "Remove takes it out", "recommend,auction*,vendor,disenchant,status*,source*", Layout())
    Check("direct", "live, Shift held: no note", false, Live(true):find("Estimates", 1, true) ~= nil)
    w.SetShift(false)
    Click(D.ListButton(8), "Limits note in the list")
    Check("state", "clicking an unused line adds it at the end (its usual choice in the Hold Shift preview)", "recommend,auction*,vendor,disenchant,status*,source*,note*", Layout())
    Click(D.ListButton(8), "Limits note again")
    Check("state", "clicking it again adds nothing: no duplicate line types", "recommend,auction*,vendor,disenchant,status*,source*,note*", Layout())

    -- the outcomes line: addable, but there is no outcome data, so nothing is ever shown for it
    Click(D.ListButton(7), "Disenchant outcomes in the list")
    Check("state", "outcomes added", true, Layout():find("outcomes", 1, true) ~= nil)
    Check("display", "the mockup holds its place and says there is nothing to show", true, Mock():find("(Disenchant outcomes: nothing to show for this example)", 1, true) ~= nil)
    Check("direct", "the live tooltip shows no outcomes line", false, Live(true):find("Disenchant gives", 1, true) ~= nil)
    w.SetShift(false)
    Click(f.remove, "Remove outcomes")

    -- the drag handlers (not a pointer): the pointer position is faked to a point over the mockup
    Click(D.Row(2), "the Auction row"); Click(f.always, "Always")
    Check("state", "Auction back to Always", "recommend,auction,vendor,disenchant,status*,source*,note*", Layout())
    D.SetMode(false)
    local mock = f.mock
    local left, top = mock:GetLeft(), mock:GetTop()
    Check("direct", "the mockup has a screen position the handlers can be tested against", true, left ~= nil and top ~= nil)
    local realCursor = GetCursorPosition
    local function PointerAt(rel)
        local scale = mock:GetEffectiveScale()
        GetCursorPosition = function() return (left + 20) * scale, (top - rel) * scale end
    end
    local Drag = R.MagicInventoryPage.Drag
    local model = D.Model()
    -- drag "Disenchant outcomes" from the list and let go between Recommendation and Auction (gap 1)
    local b = D.ListButton(7)
    ;(b:GetScript("OnDragStart"))(b)
    Check("direct", "[handler] OnDragStart on a list line starts a carry", true, Drag.Active())
    PointerAt(model.tops[2] - 1)
    Check("direct", "[handler] over the top of the second row the gap is 1", 1, D.Find())
    Check("direct", "[handler] and a gap means a place in the layout", 2, D.PositionOf(1))
    ;(b:GetScript("OnDragStop"))(b)
    Check("state", "[handler] OnDragStop over the mockup adds the line there", "recommend,outcomes,auction,vendor,disenchant,status*,source*,note*", Layout())
    Check("direct", "[handler] and the carry is over", false, Drag.Active())
    -- drag a row to the end, then outside the mockup
    D.RemoveLine("outcomes")
    local r1 = D.Row(1)
    ;(r1:GetScript("OnDragStart"))(r1)
    Check("direct", "[handler] OnDragStart on a row carries it", "recommend", Drag.Source() and Drag.Source().id)
    model = D.Model()
    PointerAt(model.bottoms[#model.sec.rows] + 2)
    ;(r1:GetScript("OnDragStop"))(r1)
    Check("state", "[handler] dropped below the last row: Recommendation moved to the end of the shown rows",
        "auction,vendor,disenchant,recommend,status*,source*,note*", Layout())
    r1 = D.Row(4)
    ;(r1:GetScript("OnDragStart"))(r1)
    GetCursorPosition = function() return 1, 1 end   -- far from the mockup
    Check("direct", "[handler] away from the mockup there is no target", true, D.Find() == nil)
    ;(r1:GetScript("OnDragStop"))(r1)
    Check("state", "[handler] released outside: nothing changed", "auction,vendor,disenchant,recommend,status*,source*,note*", Layout())
    Check("display", "[handler] and it says so", "Nothing changed.", select(1, D.Said()))
    GetCursorPosition = realCursor
    -- put the layout back by Reset
    Click(f.reset, "Reset layout")
    Check("state", "Reset layout puts the short default back", DEFAULT, Layout())
    Check("direct", "and the live tooltip is the default again", "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / Hold Shift for details", Live(false))

    -- the examples: missing prices and an action that cannot be done
    local function Pick(v) f.example:Click() local menu = rawget(_G, "TwichUISettingsMenu")   -- the list is made by the first click
        for _, entry in ipairs(menu and menu.rows or {}) do if entry:IsShown() and entry.choice and entry.choice.value == v then entry:Click() return true end end return false end
    Check("click", "the example list offers 'Missing prices'", true, Pick("missing"))
    Check("display", "missing prices: said once, the unknown stays unknown (never zero)",
        "What's it worth? / More prices needed / Vendor | 3s / Auction | no price / Disenchant (average) | no data / Hold Shift for details", Mock())
    Check("click", "the example list offers 'Can't be auctioned'", true, Pick("unavailable"))
    Check("display", "an action that can't be done and an unknown value, side by side",
        "What's it worth? / Disenchant value unknown / Vendor | 3s / Auction | can't be listed (bound) / Disenchant (average) | no data", Mock())
    Pick("higher")
    Check("display", "an auction that looks higher before fees: no winner is claimed",
        "What's it worth? / No suggestion: auction fee unknown / Vendor | 5s / Auction (before fees) | 9s / (Disenchant value (average): nothing to show for this example) / Hold Shift for details", Mock())
    Pick("ordinary")

    -- Enable tooltip
    Click(f.enable, "Enable tooltip (off)")
    Check("state", "Enable tooltip off is saved", false, WL.Enabled())
    Check("direct", "live: no section at all, Shift or not", "", Live(true) .. Live(false))
    Click(f.enable, "Enable tooltip (on)")
    Check("direct", "back on: the section is back", "What's it worth? / Suggested: Vendor / Vendor | 5s / Auction (before fees) | 4s / Hold Shift for details", Live(false))
    Check("state", "nothing was asked of the auction house", 0, w.ah.requested - ah.requested)

    w.SetShift(false)
    w.Restore()
    R:CloseSettings()
    Check("init", "the settings window is closed again", false, R.SettingsUI.IsShown())
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
    Check("display", "[test input] the status tooltip now speaks of the cut", true,
        Norm(Opps().statusBox.twichuiTip.body(Opps().statusBox)):find("Profit is after the auction house's cut.", 1, true) ~= nil and ProfitHead() == "Profit after the cut")
    R.Workshop.Prices.CUT.unknown = nil
    Win().Render()
    Check("display", "test cut removed: profit back to the uncut value", "7s", Profit("Smelt Bronze"))
end)

Lab.Step("opportunities: Add to queue", function()
    local o = Lists().opps
    local row = Row(o, "Elixir of Many Wonders")
    Click(row, "choose Elixir of Many Wonders")
    local add = Opps().detail.add
    Check("display", "its details are shown", "Elixir of Many Wonders", Txt(Opps().detail.name))
    Check("display", "Add button before", "Add to crafting plan/true", Txt(add.text) .. "/" .. tostring(add:IsEnabled()))
    Click(add, "Add to crafting plan (Elixir of Many Wonders)")
    Check("state", "the real queue gained the recipe",
        "Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2, Elixir of Many Wonders x1", Queue())
    Check("display", "button now In your queue and disabled", "In your queue/false", Txt(add.text) .. "/" .. tostring(add:IsEnabled()))
    Check("display", "the row says it is queued", true, Txt(Row(o, "Elixir of Many Wonders").sub):find("In your queue", 1, true) ~= nil)
    Tab("Crafting")
    local q = Lists().queue
    Check("display", "Crafting shows the added entry with its range", "1 craft - makes 1-3", Txt(Rows(q)[4].line))
    QueueAct(Rows(q)[4], "remove", "Remove Elixir of Many Wonders")
    Check("state", "queue back to three entries", "Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2", Queue())
end)

---------------------------------------------------------------------------------------------------------------------------
-- 4. Shopping
---------------------------------------------------------------------------------------------------------------------------
local function ShopRow(name) return Row(Lists().shop, name) end
local function Pick(name) Click(ShopRow(name), "choose the row " .. name) return Shop().detail end   -- choosing a row shows its details
local function Source(r) return r.data.source and R.Workshop.Shopping.NAMES[r.data.source] or "No source" end
local function Line(name)   -- to get | source | spend | spend note | the details' action
    local r = ShopRow(name)
    local d = Pick(name)
    return table.concat({ Txt(r.need), Source(r), Txt(r.spend.a), Txt(r.spend.b), d.act:IsShown() and Txt(d.act.text) or "-" }, " | ")
end
local function Explain(name) return Txt(Pick(name).explain) end   -- the words that explain the row, in the details
local function Lit(d)   -- which source choice is lit in the details
    for _, k in ipairs({ "vendor", "auction", "make" }) do if d.choose[k].on then return k end end
    return "none"
end
local function Choose(name, kind)   -- the details' source choice (a click on its segment)
    local d = Pick(name)
    Click(d.choose[kind], "source " .. kind .. " for " .. name)
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
    Check("display", "Peacebloom (auction, exact)", "3 | Auction house | 15c | to 1s | -", Line("Peacebloom"))
    Check("display", "Silverleaf (unpriced: not enough listed)", "3 | No source | Unknown | no price | -", Line("Silverleaf"))
    Check("display", "Coarse Thread (vendor)", "1 | Vendor | 25c | just now | Show vendor", Line("Coarse Thread"))
    Check("display", "Copper Ore (2 to buy for the subcraft)", "2 | Auction house | 70c | to 7s | -", Line("Copper Ore"))
    Check("display", "Tin Ore (vendor stack of 5 for 3 needed)", "3 | Vendor | 80c | just now | Show vendor", Line("Tin Ore"))
    Check("display", "Bronze Bar (make suggested)", "5 | Make | 1s 50c | materials, counted in their rows | Add to crafting plan", Line("Bronze Bar"))
    Check("display", "Peacebloom detail", "Suggested source. Only the auction house has a price. Auctions may require buying larger stacks.", Explain("Peacebloom"))
    Check("display", "Silverleaf detail says why", "Not enough are listed at the auction house.", Explain("Silverleaf"))
    Check("display", "Tin Ore detail: leftover from the whole stack", "2 left over. Needed to make Smelt Bronze.", Explain("Tin Ore"))
    Check("display", "Bronze Bar detail: crafts, made, leftover, comparison",
        "Make 3 x Smelt Bronze: makes 6, 1 left over. Suggested source. Making this looks cheaper than buying at the auction house.", Explain("Bronze Bar"))
    Check("display", "total with the incomplete-total warning",
        "Estimated spending: 1s 90c so far \194\183 1 price missing", Txt(Shop().total))
    Check("display", "vendor status line", "Vendor prices as last seen (2 noted) \194\183 bags only", Txt(Shop().status))
    Check("display", "notes keep one short caveat about the suggestions", true, Txt(Shop().notes):find("Suggestions compare one material at a time", 1, true) ~= nil)
end)

Lab.Step("shopping: source choices", function()
    -- Bronze Bar options: auction (estimate) and make. The details lit the suggestion (Make); the player chooses the auction house, then Make
    -- explicitly, and choosing the chosen one again returns to the suggestion.
    local d = Pick("Bronze Bar")
    Check("display", "Bronze Bar details: Make is lit, the auction house can be chosen, the vendor cannot", "make/false/true/true",
        Lit(d) .. "/" .. tostring(d.choose.vendor:IsEnabled()) .. "/" .. tostring(d.choose.auction:IsEnabled()) .. "/" .. tostring(d.choose.make:IsEnabled()))
    Choose("Bronze Bar", "auction")
    Check("click", "the auction house: an estimate", "5 | Auction house | 23s | just now | -", Line("Bronze Bar"))
    Check("display", "the whole-quantity walk of the price tiers gives an exact figure, so no estimate is claimed", false, Explain("Bronze Bar"):find("estimate", 1, true) ~= nil)
    Check("display", "the details lit the chosen source and the row stays chosen", "auction/Bronze Bar", Lit(Shop().detail) .. "/" .. Txt(Shop().detail.name))
    Check("state", "choice is kept in memory", "auction", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "its reagent rows go (no subcraft now)", "Silverleaf | Coarse Thread | Peacebloom | Bronze Bar", Names(Lists().shop))
    Check("display", "total now includes the estimate: 15 + 25 + 2000 = 2040c",
        "Estimated spending: 23s 40c so far \194\183 1 price missing", Txt(Shop().total))
    Choose("Bronze Bar", "make")
    Check("state", "make, chosen by the player", "make", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "make row again, with the reagent rows back, and still chosen", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore | Bronze Bar/Bronze Bar",
        Names(Lists().shop) .. "/" .. Txt(Shop().detail.name))
    Choose("Bronze Bar", "make")
    Check("state", "choosing it again: back to the suggestion", "nil", tostring(R.Workshop.Session.picks[2841]))
    Check("display", "back to the original total", "Estimated spending: 1s 90c so far \194\183 1 price missing", Txt(Shop().total))
    -- Peacebloom has one option (auction): choosing it picks it, choosing it again returns to the suggestion.
    Choose("Peacebloom", "auction")
    Check("state", "single option: chosen", "auction", tostring(R.Workshop.Session.picks[2447]))
    Choose("Peacebloom", "auction")
    Check("state", "single option: chosen again returns to the suggestion", "nil", tostring(R.Workshop.Session.picks[2447]))
    -- Silverleaf has no priced option. Choosing the auction house must not invent a price or a complete total.
    local total = Txt(Shop().total)
    local sl = Pick("Silverleaf")
    Say("info", "Silverleaf source choices: enabled", tostring(sl.choose.auction:IsEnabled()), "lit", Lit(sl))
    if sl.choose.auction:IsEnabled() then Choose("Silverleaf", "auction") end
    Check("display", "an unpriced material stays Unknown after a source choice", "Unknown", Txt(ShopRow("Silverleaf").spend.a))
    Check("display", "the total is not made complete by a source choice", total, Txt(Shop().total))
    if R.Workshop.Session.picks[765] then Choose("Silverleaf", "auction") end
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
    Click(Pick("Coarse Thread").act, "Show vendor (Coarse Thread)")
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
    Click(Pick("Bronze Bar").act, "Add to crafting plan (Bronze Bar)")
    -- 3 crafts of Smelt Bronze added: needs Copper Ore 6 (bags 4 -> 2 short), Tin Ore 3 (3 short); Bronze Bar need 8, 6 will be made, 3 in bags -> 0 short
    Check("state", "Smelt Bronze x3 queued", q0 .. ", Smelt Bronze x3", Queue())
    Check("display", "the made item is no longer on the list; its ingredients are, once each",
        "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore", Names(Lists().shop))
    Check("display", "Copper Ore: queue's own need, once", "2 | Auction house | 70c | to 7s | -", Line("Copper Ore"))
    Check("display", "Tin Ore: queue's own need, once", "3 | Vendor | 80c | just now | Show vendor", Line("Tin Ore"))
    Check("display", "total unchanged: the ingredients are counted once", "Estimated spending: 1s 90c so far \194\183 1 price missing", Txt(Shop().total))
    local anyMake = false
    for _, r in ipairs(Rows(Lists().shop)) do if r.data.kind == "make" then anyMake = true end end
    Check("display", "no Make row is left, so no Add to crafting plan action", false, anyMake)
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
    Check("event", "total drops by the Copper Ore row (190 - 70 = 120c)", "Estimated spending: 1s 20c so far \194\183 1 price missing", Txt(Shop().total))
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
        (function() Click(Win().Craft().segRecipes, "Recipes (the left card)") Click(FindButton(Frame(), "Alchemy"), "Alchemy chip") return Txt(Frame().notice):find("Remembered from", 1, true) ~= nil end)())
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
    Check("display", "Opportunities lists all seven recipes from saved knowledge, priced from the saved scan (the Overview counts 5 priced)", "7 | of 5 priced",
        #Rows(Lists().opps) .. " | " .. (function() Tab("Overview") local t = Txt(Win().Overview().cards.opps.side) Tab("Opportunities") return t end)())
    Tab("Crafting")
    Check("display", "Crafting says the list is remembered", true, Txt(Frame().notice):find("Remembered from", 1, true) ~= nil)
    -- restore the open profession for the screenshot poses
    T.GetBaseProfessionInfo = function() return { professionID = open.id, professionName = open.name } end
    open = saved
    ShowProfession(PROF.smith)
end)

---------------------------------------------------------------------------------------------------------------------------
-- 1d. The player's bank and the guild bank (bank and guild bank materials; handler level and in memory: NOT a real bank, NOT a /reload)
---------------------------------------------------------------------------------------------------------------------------
-- WHAT IS FAKE HERE (read-only stand-ins at the game-API boundary): C_Bank.FetchPurchasedBankTabIDs / CanViewBank and the reads of bags 6 and 7
-- (BANKTABS: the character bank's tabs are bags), the globals BankFrame and GuildBankFrame (plain frames the scenario shows and hides),
-- IsInGuild / GetGuildInfo and the guild bank reads (GBANK: two tabs; tab 1 may be taken from, tab 2 only viewed). WHAT IS REAL: the Workshop's
-- recorder (Bank.lua), saved records (Storage.lua), the availability service (Stock.lua), the planner, the window. The bank is opened with the
-- legacy BANKFRAME_OPENED / _CLOSED events: the player interaction manager's events are covered by the unit tests, and here they would also
-- reach Blizzard's own bank frame, which the simulator cannot run. Nothing is moved, withdrawn, deposited or bought, here or in the product.
local BANKTABS = { [6] = { { 2447, 3 }, { 2447, 2 }, { 765, 1 } }, [7] = { { 2771, 2 } } }   -- stacks: { item, count }
local GBANK = { current = 1, tabs = {
    { w = 5, rem = -1, items = { { 765, 4 }, { 2770, 5 } } },   -- tab 1: the rank may take items; no daily limit
    { w = 0, rem = 0, items = { { 2771, 9 } } },                -- tab 2: viewable, the rank cannot take items
} }
local swapped = {}
local function Swap(tbl, key, value) swapped[#swapped + 1] = { tbl, key, rawget(tbl, key) } rawset(tbl, key, value) end
local function RestoreFakes() for i = #swapped, 1, -1 do rawset(swapped[i][1], swapped[i][2], swapped[i][3]) end swapped = {} end
local function StandIn(global)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(10, 10) f:SetPoint("CENTER") f:Hide()
    Swap(_G, global, f)
    return f
end
local function InstallBank()
    if rawget(_G, "C_Bank") == nil then Swap(_G, "C_Bank", {}) end
    Swap(C_Bank, "FetchPurchasedBankTabIDs", function() return { 6, 7 } end)
    Swap(C_Bank, "CanViewBank", function() return true end)
    if not Enum.BankType then Swap(Enum, "BankType", { Character = 0, Guild = 1, Account = 2 }) end
    local slots, info = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
    Swap(C_Container, "GetContainerNumSlots", function(bag) if BANKTABS[bag] then return 6 end return slots(bag) end)
    Swap(C_Container, "GetContainerItemInfo", function(bag, slot)
        if BANKTABS[bag] then
            local st = BANKTABS[bag][slot]
            if st then return { itemID = st[1], stackCount = st[2], isLocked = false } end
            return nil
        end
        return info(bag, slot)
    end)
    return StandIn("BankFrame")
end
local function InstallGuild()
    Swap(_G, "IsInGuild", function() return true end)
    Swap(_G, "GetGuildInfo", function() return "Simulated Guild", "Member", 3, nil end)
    Swap(_G, "GetNumGuildBankTabs", function() return #GBANK.tabs end)
    Swap(_G, "GetCurrentGuildBankTab", function() return GBANK.current end)
    Swap(_G, "GetGuildBankTabInfo", function(i) local t = GBANK.tabs[i] if not t then return nil end return "Tab " .. i, "", true, true, t.w, t.rem end)
    Swap(_G, "GetGuildBankItemInfo", function(tab, slot) local t = GBANK.tabs[tab] local it = t and t.items[slot] if it then return "tex", it[2], false end end)
    Swap(_G, "GetGuildBankItemLink", function(tab, slot)
        local t = GBANK.tabs[tab] local it = t and t.items[slot]
        if it then return "|cffffffff|Hitem:" .. it[1] .. "::::::::80|h[x]|h|r" end
    end)
    return StandIn("GuildBankFrame")
end
local function Fire(name, ...) A_Admin.FireEvent(name, ...) end
local function Mat(name)   -- need/in bags/stored/still needed, from the Crafting materials list
    local r = Row(Lists().mats, name)
    return table.concat({ Txt(r.need), Txt(r.have), Txt(r.stored), Txt(r.short) }, "/")
end
local function SLine(i)    -- name | to get | where or source | spending | its note, for the i-th shown Shopping row
    local r = Rows(Lists().shop)[i]
    local where
    if r.data.kind == "collect" then where = r.data.where == "guild" and "Collect from guild bank" or "Collect from bank" else where = Source(r) end
    return table.concat({ Txt(r.name), Txt(r.need), where, Txt(r.spend.a), Txt(r.spend.b) }, " | ")
end
local function ExplainAt(i) local r = Rows(Lists().shop)[i] Click(r, "choose shopping row " .. i) return Txt(Shop().detail.explain) end   -- the i-th row's explanation
local oppBefore, bankFrame, guildFrame

-- State on entry: the window is shown on Crafting; queue = Minor Healing Potion x3, Weak Troll's Blood Potion x2, Copper Belt Buckle x2, Smelt
-- Bronze x3. Bags: Peacebloom 4, Silverleaf 0, Vial 5, Bronze Bar 3, Coarse Thread 1, Copper Ore 4, Tin Ore 0. Needs (hand arithmetic): Peacebloom 7,
-- Silverleaf 3, Vial 5, Bronze Bar 8 (6 made by the queued Smelt Bronze), Coarse Thread 2, Copper Ore 6, Tin Ore 3: five short, as before.
Lab.Step("bank and guild bank: remembered while the window is closed", function()
    local W = R.Workshop
    -- what Opportunities says before any stored material is known (to compare with later)
    Tab("Opportunities")
    oppBefore = OppLine("Minor Healing Potion") .. " / " .. OppLine("Weak Troll's Blood Potion") .. " / " .. OppLine("Smelt Bronze")
    Check("display", "Opportunities before any bank is seen: cost | sell | profit", "70c | 1s 50c | 80c / 30c | 60c | 30c / 1s | 8s | 7s", oppBefore)
    Tab("Crafting")
    Check("display", "bank never seen: what is counted", "Counts bags only.", Txt(Frame().scope))
    Check("display", "bank never seen: it says how to fix that", "Open your bank with Workshop loaded to update.", Txt(Frame().storeNote))
    Check("display", "bank never seen: Peacebloom need/in bags/stored/still needed", "7/4/-/3", Mat("Peacebloom"))
    Check("display", "bank never seen: the headline is the bags-only one", "Still needed: 5 materials.", Txt(Frame().headline))
    Check("state", "the guild bank choice is off by default", false, W.Storage.UseGuild())

    Click(Frame().close, "Close button")
    Lab.Settle(0.3)
    bankFrame = InstallBank()
    Check("state", "window hidden: the window listens to nothing, the recorder to its eight always-on events", "0/8", W.Snapshot().events .. "/" .. W.Snapshot().bankEvents)
    bankFrame:Show()
    Fire("BANKFRAME_OPENED")
    Check("state", "bank open: its change events are registered too", 11, W.Snapshot().bankEvents)
    Lab.Settle(0.5)
    local rec = W.Storage.Bank()
    Check("state", "read with the window closed: tab 6 Peacebloom 3+2 and Silverleaf 1, tab 7 Tin Ore 2", "5/1/2",
        rec.tabs[6].n[2447] .. "/" .. rec.tabs[6].n[765] .. "/" .. rec.tabs[7].n[2771])
    Check("state", "and when it was seen is kept", true, W.Queue.Now() - rec.tabs[6].at < 30)
    Check("state", "the window was not needed", false, Frame():IsShown())
    bankFrame:Hide()
    Fire("BANKFRAME_CLOSED")
    Check("state", "bank closed: back to the always-on events", 8, W.Snapshot().bankEvents)
end)

Lab.Step("bank and guild bank: planned with, collected not bought, labelled, profit unchanged", function()
    local W = R.Workshop
    SlashWorkshop()
    Tab("Crafting")
    Check("display", "the scope names the bank", "Counts bags and bank.", Txt(Frame().scope))
    Check("display", "the bank was seen: nothing left to explain", "", Txt(Frame().storeNote))
    Check("display", "Peacebloom: 7 needed, 4 in bags, 3 of the bank's 5 to collect", "7/4/3/0", Mat("Peacebloom"))
    Check("display", "Silverleaf: 3 needed, 1 in the bank, 2 still needed", "3/0/1/2", Mat("Silverleaf"))
    Check("display", "Tin Ore: 3 needed, 2 in the bank, 1 still needed", "3/0/2/1", Mat("Tin Ore"))
    Check("display", "Copper Ore: nothing stored", "6/4/-/2", Mat("Copper Ore"))
    Check("display", "Empty Vial: the bags cover it", "5/5/-/0", Mat("Empty Vial"))
    Check("display", "headline: still needed, and what to collect", "Still needed: 4 materials. 3 to collect from storage.", Txt(Frame().headline))
    Check("display", "order: short first, then those to collect, then the rest", "Silverleaf | Coarse Thread | Copper Ore | Tin Ore | Peacebloom | Bronze Bar | Empty Vial", Names(Lists().mats))

    -- Shopping: collect rows apart from the rows to buy (bought: 2 Silverleaf at 45c, 1 thread at 25c, 2 Copper Ore at 35c, 1 Tin Ore at 30c)
    Tab("Shopping")
    Check("display", "collect rows first (bank), then what is bought", "Silverleaf | Peacebloom | Tin Ore | Silverleaf | Coarse Thread | Copper Ore | Tin Ore", Names(Lists().shop))
    Check("display", "collect Silverleaf from the bank", "Silverleaf | 1 | Collect from bank | Already owned | seen just now", SLine(1))
    Check("display", "collect Peacebloom from the bank (3 of 5)", "Peacebloom | 3 | Collect from bank | Already owned | seen just now", SLine(2))
    Check("display", "collect Tin Ore from the bank", "Tin Ore | 2 | Collect from bank | Already owned | seen just now", SLine(3))
    Check("display", "buy the Silverleaf still missing: 2 listed at 45c, now exact", "Silverleaf | 2 | Auction house | 90c | just now", SLine(4))
    Check("display", "buy Coarse Thread at the vendor", "Coarse Thread | 1 | Vendor | 25c | just now", SLine(5))
    Check("display", "buy 2 Copper Ore", "Copper Ore | 2 | Auction house | 70c | to 7s", SLine(6))
    Check("display", "buy the 1 Tin Ore still missing: 30c at the auction house beats a stack of 5 at 80c", "Tin Ore | 1 | Auction house | 30c | to 3s", SLine(7))
    local c1 = Rows(Lists().shop)[1]
    Click(c1, "choose the first collect row")
    local cd = Shop().detail
    Check("display", "a collect row has no source choices and no action", "false/false/false", tostring(cd.choose.vendor:IsShown()) .. "/" .. tostring(cd.choose.make:IsShown()) .. "/" .. tostring(cd.act:IsShown()))
    Check("display", "a collect row says it is already owned", "Collect from your bank. It is already yours: nothing to buy.", Txt(cd.explain))
    Check("display", "total counts only what is bought: 90 + 25 + 70 + 30", "Estimated spending: 2s 15c to 11s 15c", Txt(Shop().total))
    Check("display", "status line names what is counted", "Vendor prices as last seen (2 noted) \194\183 bags and bank", Txt(Shop().status))

    -- Opportunities: stored materials say whether a craft can start; the cost, the sell price and the profit do not move
    Tab("Opportunities")
    local after = OppLine("Minor Healing Potion") .. " / " .. OppLine("Weak Troll's Blood Potion") .. " / " .. OppLine("Smelt Bronze")
    Check("display", "cost, sell price and profit are exactly what they were without the bank", oppBefore, after)
    local o = Lists().opps
    Check("display", "Minor Healing Potion: 1 Silverleaf is in the bank", "Alchemy \194\183 Collect materials \194\183 In your queue", Txt(Row(o, "Minor Healing Potion").sub))
    Check("display", "Weak Troll's Blood Potion: all in the bags", "Alchemy \194\183 Ready to craft \194\183 In your queue", Txt(Row(o, "Weak Troll's Blood Potion").sub))
    Check("display", "Elixir of Many Wonders: nothing held, nothing said", "Alchemy \194\183 makes 1-3", Txt(Row(o, "Elixir of Many Wonders").sub))
    Tab("Crafting")
end)

Lab.Step("bank and guild bank: the guild choice, permissions and limits", function()
    local W = R.Workshop
    guildFrame = InstallGuild()
    guildFrame:Show()
    Fire("GUILDBANKFRAME_OPENED")
    Fire("GUILDBANKBAGSLOTS_CHANGED")      -- tab 1's items arrive
    GBANK.current = 2
    Fire("GUILDBANKBAGSLOTS_CHANGED")      -- tab 2's items arrive (not empty: believed at once)
    Lab.Settle(0.3)
    local g = W.Storage.Guild({ key = "Simulated Guild-" .. GetRealmName(), name = "Simulated Guild" })
    Check("state", "both tabs are remembered, each with what this character may do there", "4+5 can take / 9 view only",
        g and (g.tabs[1].n[765] .. "+" .. g.tabs[1].n[2770] .. " " .. (g.tabs[1].w == 1 and "can take" or "no") .. " / " .. g.tabs[2].n[2771] .. " " .. (g.tabs[2].w == 0 and "view only" or "?")) or "no record")
    Check("state", "remembered by this character", W.Queue.CharKey(), g and g.tabs[1].by)
    Check("display", "the choice is off: the guild bank adds nothing to Crafting", "3/0/1/2", Mat("Silverleaf"))
    Tab("Shopping")
    Check("display", "and nothing to Shopping", "Silverleaf | Peacebloom | Tin Ore | Silverleaf | Coarse Thread | Copper Ore | Tin Ore", Names(Lists().shop))
    Check("display", "the notes do not mention the guild bank while the choice is off", false, Txt(Shop().notes):find("guild", 1, true) ~= nil)

    Click(Shop().useGuild, "Use guild bank")
    Lab.Settle(0.3)
    Check("state", "the choice is saved", true, W.Storage.UseGuild())
    Check("display", "the bank first, then the guild bank, then what is bought", "Silverleaf | Silverleaf | Peacebloom | Copper Ore | Tin Ore | Coarse Thread | Tin Ore", Names(Lists().shop))
    Check("display", "collect Silverleaf from the bank", "Silverleaf | 1 | Collect from bank | Already owned | seen just now", SLine(1))
    Check("display", "collect Silverleaf from the guild bank (3 needed - 1)", "Silverleaf | 2 | Collect from guild bank | Already owned | seen just now", SLine(2))
    Check("display", "collect Copper Ore from the guild bank (6 needed - 4 in bags)", "Copper Ore | 2 | Collect from guild bank | Already owned | seen just now", SLine(4))
    Check("display", "Tin Ore: tab 2 only allows viewing, so only the bank's 2 are collected and 1 is bought", "Tin Ore | 1 | Auction house | 30c | to 3s", SLine(7))
    Check("display", "shared stock is said so", "Collect from the guild bank. Shared stock: other members can take it too.", ExplainAt(2))
    Check("display", "total counts only what is bought: 25 + 30", "Estimated spending: 55c to 3s 25c", Txt(Shop().total))
    Check("display", "status line names the guild bank", "Vendor prices as last seen (2 noted) \194\183 bags, bank and guild bank", Txt(Shop().status))
    local view = W.Session.Stock()
    Check("state", "tab 2's 9 Tin Ore are information, not counted: a viewable tab does not establish a right to take", "9/nowithdraw/0",
        (view.guild.info[2771] or 0) .. "/" .. tostring(view.guild.reason[2771]) .. "/" .. (view.guild.counted[2771] or 0))
    Tab("Crafting")
    Check("display", "Crafting with the choice on: Silverleaf", "3/0/3/0", Mat("Silverleaf"))
    Check("display", "Crafting with the choice on: Copper Ore", "6/4/2/0", Mat("Copper Ore"))
    Check("display", "Crafting with the choice on: Tin Ore", "3/0/2/1", Mat("Tin Ore"))
    Check("display", "headline", "Still needed: 2 materials. 4 to collect from storage.", Txt(Frame().headline))
    Check("display", "scope", "Counts bags, bank and guild bank.", Txt(Frame().scope))

    -- a finite daily allowance: still potentially withdrawable, but flagged, not promised
    GBANK.tabs[1].rem = 3
    GBANK.current = 1
    Fire("GUILDBANKBAGSLOTS_CHANGED")
    Lab.Settle(0.3)
    Tab("Shopping")
    Check("display", "a daily limit is flagged on the collect row", "Collect from the guild bank. Shared stock: other members can take it too, and a withdrawal limit may apply.",
        ExplainAt(2))
    -- a bag change nobody answers (the guild bank is open, and the last answer is over a second old): that tab is uncertain and is no longer planned with
    Lab.Settle(0.6)
    Fire("BAG_UPDATE_DELAYED")
    Lab.Settle(1.5)
    Check("state", "no answer followed the bag change: the tab may have changed", true, W.Storage.Guild({ key = "Simulated Guild-" .. GetRealmName() }).tabs[1].u == true)
    Check("display", "its stock is not collected from any more: back to the bank-only list", "Silverleaf | Peacebloom | Tin Ore | Silverleaf | Coarse Thread | Copper Ore | Tin Ore", Names(Lists().shop))
    Check("display", "and the note says why", true, Txt(Shop().notes):find("Some guild bank tabs may have changed.", 1, true) ~= nil)
    Fire("GUILDBANKBAGSLOTS_CHANGED")      -- the next answer is a fresh read
    Lab.Settle(0.3)
    Check("display", "a fresh answer brings it back", "Silverleaf | Silverleaf | Peacebloom | Copper Ore | Tin Ore | Coarse Thread | Tin Ore", Names(Lists().shop))

    Click(Shop().useGuild, "Use guild bank (off again)")
    Lab.Settle(0.3)
    Check("state", "the choice is off again", false, W.Storage.UseGuild())
    Check("display", "and the list is the bank-only list", "Silverleaf | Peacebloom | Tin Ore | Silverleaf | Coarse Thread | Copper Ore | Tin Ore", Names(Lists().shop))
    guildFrame:Hide()
    Fire("GUILDBANKFRAME_CLOSED")
    Tab("Crafting")
end)

Lab.Step("bank and guild bank: a withdrawal and a deposit never count twice", function()
    local W = R.Workshop
    bankFrame:Show()
    Fire("BANKFRAME_OPENED")
    Lab.Settle(0.5)
    Check("display", "bank visit: Peacebloom as before", "7/4/3/0", Mat("Peacebloom"))
    -- the player takes the 3-stack out: the bags gain 3 and the bank loses 3
    BANKTABS[6] = { { 2447, 2 }, { 765, 1 } }
    BAGS[2447] = 7
    Fire("PLAYERBANKSLOTS_CHANGED", 1)
    Fire("BAG_UPDATE_DELAYED")
    Check("state", "a bag change with the bank open: the remembered bank is pending", true, W.Bank.Pending().bankPending)
    Check("state", "and is not planned with until it is read again", false, W.Session.Stock().bank.counted)
    Lab.Settle(0.6)
    Check("state", "read again", false, W.Bank.Pending().bankPending)
    Check("state", "the bank now remembers 2 Peacebloom", 2, W.Storage.Bank().tabs[6].n[2447])
    Check("display", "Peacebloom is in the bags (7 of 7) and nothing is collected: the 3 are not counted in both places", "7/7/-/0", Mat("Peacebloom"))
    Check("display", "the headline counts one thing fewer to collect", "Still needed: 4 materials. 2 to collect from storage.", Txt(Frame().headline))
    -- put them back
    BANKTABS[6] = { { 2447, 3 }, { 2447, 2 }, { 765, 1 } }
    BAGS[2447] = 4
    Fire("PLAYERBANKSLOTS_CHANGED", 1)
    Fire("BAG_UPDATE_DELAYED")
    Lab.Settle(0.6)
    Check("display", "deposited again: Peacebloom as before", "7/4/3/0", Mat("Peacebloom"))
    bankFrame:Hide()
    Fire("BANKFRAME_CLOSED")
    Check("state", "bank closed: the always-on events only", 8, W.Snapshot().bankEvents)

    -- put everything back for the rest of the scenario: remembered bank and guild data forgotten, the real game functions restored
    RestoreFakes()
    TwichUIDB.workshop.storage = nil
    SetBags({ [2447] = 4, [765] = 0, [3371] = 5, [2841] = 3, [2320] = 1, [2770] = 4 })
    Event("BAG_UPDATE_DELAYED")
    Check("display", "storage forgotten again: bags only", "Counts bags only.", Txt(Frame().scope))
    Check("display", "Peacebloom as before any bank", "7/4/-/3", Mat("Peacebloom"))
    Tab("Shopping")
    Check("display", "the shopping list as before any bank", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore", Names(Lists().shop))
    Tab("Crafting")
end)

---------------------------------------------------------------------------------------------------------------------------
-- Third pass: what the owner found in the real client, as far as the simulator can show it
--   hit test   EMULATED by TwichUI_TestLab/Reach.lua (loaded into this chunk by workshop.sh) from every frame's rectangle, hit-rect insets,
--              strata, level, mouse flags, visibility, scroll clipping and parent chain (the simulator has no pointer, and its GetMouseFoci only
--              returns what a scenario forced). It says whether any other mouse-enabled frame is stacked over a control's hit point and, if so,
--              which. It cannot say how the real client orders equal levels (it reports those as ambiguous). The next step plants an overlay.
--   hover      the row's own OnEnter, run by the scenario: the painted art's state (shown, alpha, parent visible). Not a pointer, not how it looks.
--   fit        measured string widths against the control's rectangle (the simulator draws addon fonts in Friz Quadrata: a structural check)
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("third pass: hit test, hover, fit, tooltips, status", function()
    local W = R.Workshop
    local RC = R.TestLab.Reach
    local function Label(fr)   -- a frame's name, else a button's own text (synthetic text here), else its type
        local name = fr.GetName and fr:GetName()
        if name then return name end
        local tx = fr.text
        if type(tx) == "table" and tx.GetText then
            local t = tx:GetText()
            if t and t ~= "" then return t end
        end
        return nil
    end
    local function Look(fr, kind, extra)   -- one analysis of a control, against every frame the simulator has
        local o = { kind = kind or "click", label = Label, evidence = "simulator-geometry", limit = 1000000 }
        for k, v in pairs(extra or {}) do o[k] = v end
        return RC.Analyze(fr, o)
    end
    -- every shown, enabled button of the window with a click script is the topmost mouse frame at its hit point (a row only where the scroll
    -- frame shows it)
    local function CoveredButtons()
        local col, bad, n = RC.Collect({ limit = 1000000 }), {}, 0
        for _, c in ipairs(col.list) do
            local fr = c.frame
            local kind = fr:GetObjectType()
            if (kind == "Button" or kind == "CheckButton") and RC.Within(fr, TwichUIWorkshop) and fr:IsEnabled() and type(fr:GetScript("OnClick")) == "function" then
                n = n + 1
                local res = RC.Analyze(fr, { kind = "click", collected = col, label = Label, evidence = "simulator-geometry", limit = 1000000 })
                if res.verdict ~= "reachable" and res.verdict ~= "clipped" then bad[#bad + 1] = (res.text:gsub("\n%s*", " | ")) end
            end
        end
        return #bad == 0 and "none covered" or table.concat(bad, "; "), n
    end
    local function Hover(row) row:GetScript("OnEnter")(row) Lab.Settle(0.15) end
    local function Unhover(row) row:GetScript("OnLeave")(row) Lab.Settle(0.15) end
    local function Art(row) return row.twichHot.parts[1], row.twichRim.parts[1] end

    -- 1. Opportunities: the Add button, through its real control, with the real queue
    Tab("Opportunities")
    Check("state", "the hit test sees the window's mouse targets (it is not passing on an empty list)", true, select(2, CoveredButtons()) > 8)
    local add = Opps().detail.add
    local rows = Rows(Lists().opps)
    local pick
    for _, r in ipairs(rows) do if r.rec and not W.Queue.Find(r.rec.id) then pick = r break end end
    Check("display", "an unqueued recipe is listed", true, pick ~= nil)
    Click(pick, "choose an unqueued recipe")
    local rec = Opps().detail.rec
    Check("display", "its details are shown, and Add is offered", "Add to crafting plan/true", Txt(add.text) .. "/" .. tostring(add:IsEnabled()))
    do
        local res = Look(add)
        Check("display", "HIT TEST (emulated): the Add button is the top mouse target at its centre", "Add to crafting plan", res.verdict == "reachable" and res.top.label or res.text)
    end
    Check("display", "HIT TEST (emulated): no button on Opportunities has another mouse frame stacked over its centre", "none covered", CoveredButtons())
    local before = #W.Queue.Entries()
    Click(add, "Add to crafting plan")
    Check("state", "the click put the chosen recipe in the queue", true, W.Queue.Find(rec.id) ~= nil and #W.Queue.Entries() == before + 1)
    Check("display", "the button says it is queued, and the row and footer agree", "In your queue/false/true/true",
        Txt(add.text) .. "/" .. tostring(add:IsEnabled()) .. "/" .. tostring(Row(Lists().opps, rec.name).sub:GetText():find("In your queue", 1, true) ~= nil)
        .. "/" .. tostring(Txt(Frame().note):find("^Added ") ~= nil))
    Tab("Crafting")
    Check("display", "Crafting shows it in the queue", true, (function()
        for _, q in ipairs(Lists().queue.data) do if q.entry.id == rec.id then return true end end
        return false
    end)())
    W.Session.Remove(rec.id)   -- put the queue back as the poses expect it
    Win().Render()

    -- 2. Crafting: the action of every recipe row fits its place (measured), in each state: Queued (the real rows), Add and Full (a row filled with
    --    a recipe that is not queued, with a very long name, as the list does when it scrolls)
    local function Fits(r)
        local box = r.mark:IsShown() and r.mark or r.add
        local label = r.mark:IsShown() and r.mark.text or r.add.text
        local left = label:GetLeft()
        local right = left and (left + label:GetStringWidth())
        local ok = right and right <= box:GetRight() - 1 and box:GetWidth() == 70
        return ok and "inside" or (Txt(label) .. " ends " .. tostring(right) .. " > " .. tostring(box:GetRight() - 1) .. " width " .. box:GetWidth())
    end
    Click(Win().Craft().segRecipes, "Recipes")
    local rr = Rows(Lists().recipes)
    local states = {}
    for _, r in ipairs(rr) do if r.mark:IsShown() then states[#states + 1] = Txt(r.mark.text) .. " " .. Fits(r) end end
    Check("display", "every queued recipe's mark is inside its 70-wide place", "Queued inside", states[1] or "none queued")
    local spare = rr[1]
    local fakeRec = { id = 3001, name = "A recipe with a very long name that never fits the row beside its action", diff = 1, icon = 1, prof = 171, profName = "Alchemy" }
    spare.fill(spare, fakeRec)
    Check("display", "an unqueued recipe is an Add button, inside its place, with a long name beside it", "Add inside", Txt(spare.add.text) .. " " .. Fits(spare))
    local fill = {}
    for i = 1, 30 - #W.Queue.Entries() do fill[#fill + 1] = 9000 + i; W.Queue.Add({ id = 9000 + i, name = "Filler " .. i }, 1) end
    spare.fill(spare, fakeRec)
    Check("display", "with a full queue an unqueued recipe says Full, inside its place", "Full inside", Txt(spare.mark.text) .. " " .. Fits(spare))
    for _, id in ipairs(fill) do W.Queue.Remove(id) end
    Win().Render()
    Click(Win().Craft().segQueue, "Craft queue")

    -- 3. The queue's tooltips: each picture binds its own output item; the glyph controls keep the row lit
    local seenItem
    local origSet = GameTooltip.SetItemByID
    GameTooltip.SetItemByID = function(self, id) seenItem = id return true end
    local bad = {}
    for _, q in ipairs(Rows(Lists().queue)) do
        seenItem = nil
        q.iconBtn:GetScript("OnEnter")(q.iconBtn)
        if seenItem ~= q.entry.outItem then bad[#bad + 1] = Txt(q.name) .. " shows " .. tostring(seenItem) .. " not " .. tostring(q.entry.outItem) end
        q.iconBtn:GetScript("OnLeave")(q.iconBtn)
    end
    GameTooltip.SetItemByID = origSet
    Check("display", "every queued craft's picture shows the tooltip of the item it makes", "all bound", #bad == 0 and "all bound" or table.concat(bad, "; "))
    Check("display", "HIT TEST (emulated): no button on Crafting has another mouse frame stacked over its centre", "none covered", CoveredButtons())

    -- 4. Hover: the row's own scripts, the art's state, hover with the chosen state, a child control
    local q1, q2 = Rows(Lists().queue)[1], Rows(Lists().queue)[2]
    Click(q1, "choose the first queued craft")
    Unhover(q2)
    local hot, rim = Art(q2)
    Check("display", "a row at rest: no hover art", "0.00/0.00", ("%.2f/%.2f"):format(hot:GetAlpha(), rim:GetAlpha()))
    Hover(q2)
    Check("display", "hovering a row lights its face and its rim (shown, in a visible row)", "true/true/true/true",
        tostring(hot:GetAlpha() >= 0.9) .. "/" .. tostring(rim:GetAlpha() >= 0.9) .. "/" .. tostring(hot:IsVisible()) .. "/" .. tostring(rim:IsVisible()))
    Hover(q1)
    local hot1, rim1 = Art(q1)
    Check("display", "a chosen row hovered: the chosen sheet and a quieter rim", "true/true/true",
        tostring(q1.selected) .. "/" .. tostring(q1.twichSel.parts[1]:IsVisible()) .. "/" .. tostring(rim1:GetAlpha() > 0 and rim1:GetAlpha() < 0.9))
    Unhover(q1); Unhover(q2)
    Check("display", "leaving the rows takes the art out", "0.00/0.00", ("%.2f/%.2f"):format(select(1, Art(q2)):GetAlpha(), select(2, Art(q2)):GetAlpha()))
    Check("display", "no row keeps an easing running", 0, R.Look.Motion.Count())

    -- 5. Overview: the professions fit the card, at three, four (one with a very long name) and none
    Tab("Overview")
    local ov = Win().Overview()
    local card = ov.cards.profs
    local function Inside()
        local worst, n = 0, 0
        for _, row in ipairs(card.facts) do
            if row:IsShown() then
                n = n + 1
                local over = card:GetBottom() - row:GetBottom()   -- positive: the row's bottom is above the card's
                if row:GetBottom() < card:GetBottom() + 6 then worst = worst + 1 end
            end
        end
        local more = card.more:GetText() ~= "" and (card.more:GetBottom() < card:GetBottom() + 4) and 1 or 0
        return ("%d rows, %d outside"):format(n, worst + more)
    end
    Check("display", "three professions: all inside the card", "3 rows, 0 outside", Inside())
    SKILLS[4] = { "A profession with a very long localized name that cannot fit", 136241, 300, 300 }
    GetProfessions = function() return 1, 2, 3, 4 end
    Win().Render()
    Check("display", "four professions, one with a very long name: all inside the card", "4 rows, 0 outside", Inside())
    Check("display", "and the long name stays between the picture and the numbers", true,
        card.facts[4].text:GetRight() <= card.facts[4].value:GetLeft() and card.facts[4].text:GetLeft() >= card.facts[4].icon:GetRight())
    SKILLS[4] = nil
    GetProfessions = function() return 1, 2, nil, 3 end
    Win().Render()
    local bar = card.facts[1].bar
    Check("display", "a bar's fill is inside its track with the rim around it", true, bar.fill:GetLeft() > bar:GetLeft() and bar.fill:GetRight() < bar:GetRight())

    -- 6. The footer's status chip, and no market name on the pages
    local chip = Frame().chip
    Check("display", "the footer chip says how old the prices are", "Prices updated just now", Txt(chip.text))
    Check("display", "the chip's text is inside the chip, and the chip inside the footer", true,
        chip.text:GetLeft() + chip.text:GetStringWidth() <= chip:GetRight() and chip:GetRight() <= Frame().footer:GetRight())
    Check("display", "no page or footer text names the realm or the side", true, (function()
        local texts = { Txt(chip.text), Txt(Frame().note), Txt(ov.cards.market.facts[1].text), Txt(ov.cards.market.facts[2].text) }
        for _, t in ipairs(texts) do if t:find("SimulatedRealm", 1, true) or t:find("Horde", 1, true) or t:find("Alliance", 1, true) then return false end end
        return true
    end)())
    Check("display", "the chip's tooltip names the whole market", true, tostring(chip.twichuiTip.body(chip)):find("SimulatedRealm", 1, true) ~= nil)

    -- 7. Shopping: the suggestion and the player's own choice are told apart
    Tab("Shopping")
    local d = Shop().detail
    local target
    for _, r in ipairs(Rows(Lists().shop)) do
        if r.data and r.data.kind ~= "collect" and r.data.suggested and #W.Shopping.Choices(r.data) >= 2 then target = r break end
    end
    Check("display", "a row with two possible sources is listed", true, target ~= nil)
    if target then
        Click(target, "choose a row with two sources")
        local s = target.data.suggested
        local function Tags()
            local out = {}
            for _, k in ipairs(W.Shopping.ORDER) do out[#out + 1] = k .. "=" .. Txt(d.tags[k]) end
            return table.concat(out, " ")
        end
        local expect = {}
        for _, k in ipairs(W.Shopping.ORDER) do expect[#expect + 1] = k .. "=" .. (k == s and "Suggested" or "") end
        Check("display", "the suggested source is named in words, nothing is overridden", table.concat(expect, " ") .. "/false", Tags() .. "/" .. tostring(d.useSuggestion:IsShown()))
        local other
        for _, k in ipairs(W.Shopping.Choices(target.data)) do if k ~= s then other = k end end
        Click(d.choose[other], "choose another source")
        local expect2 = {}
        for _, k in ipairs(W.Shopping.ORDER) do expect2[#expect2 + 1] = k .. "=" .. (k == s and "Suggested" or (k == other and "Your choice" or "")) end
        Check("display", "an override: the suggestion stays marked, the choice is named, and Use suggestion is offered", table.concat(expect2, " ") .. "/true",
            Tags() .. "/" .. tostring(d.useSuggestion:IsShown()))
        Click(d.useSuggestion, "Use suggestion")
        Check("state", "Use suggestion drops the choice", "nil/false", tostring(W.Session.picks[target.data.item]) .. "/" .. tostring(d.useSuggestion:IsShown()))
    end
    Check("display", "the spending line is one line and inside the bar", true,
        Shop().total:GetLeft() + Shop().total:GetStringWidth() <= Shop().bar:GetRight() and Shop().total:GetHeight() <= 20)
    Check("display", "HIT TEST (emulated): no button on Shopping has another mouse frame stacked over its centre", "none covered", CoveredButtons())

    -- 8. Navigation and redraws make no new frame, once the pools have settled
    local function CountFrames()
        local n, fr = 0, EnumerateFrames()
        while fr do n = n + 1; fr = EnumerateFrames(fr) end
        return n
    end
    local function Cycle() for _, key in ipairs({ "overview", "opps", "craft", "shop" }) do Win().SetMode(key); Win().Render(); Win().Render() end end
    for _ = 1, 3 do Cycle() end
    local settled = CountFrames()
    for _ = 1, 4 do Cycle() end
    Check("state", "four more rounds of navigation and redraws made no frame (the change in the count)", 0, CountFrames() - settled)
    Win().SetMode("overview")
    W.Session.ClearNote()   -- the step's own removal message is not the pose's
    Win().Render()
end)

---------------------------------------------------------------------------------------------------------------------------
-- Reachability (testing roadmap M5): can the pointer reach the controls, and does the check SEE it when it cannot?
--   The geometry is TwichUI_TestLab/Reach.lua's EMULATION over the simulator's frames: rectangles, hit-rect insets, strata, levels, mouse flags,
--   visibility, scroll clipping and parents. It is not input: the simulator has no pointer, and its GetMouseFoci only returns what a scenario
--   forces (checked below, so nobody mistakes it for a hit test). What it can do is catch an obstruction we put there on purpose:
--   NEGATIVE CONTROL: a mouse-enabled frame planted over a working button by THIS SCENARIO (never by the Workshop's code). The same button
--   must read reachable, then blocked (naming the planted frame), then reachable again once the frame is gone. The same for a hoverable row.
--   A working handler is not a reachable button: the planted overlay leaves the button enabled with its click script, and Click() still runs it.
---------------------------------------------------------------------------------------------------------------------------
Lab.Step("reachability: planted overlay, hover rows, insets, clipping, tooltip", function()
    local W = R.Workshop
    local RC = R.TestLab.Reach
    local function Label(fr)
        local name = fr.GetName and fr:GetName()
        if name then return name end
        local tx = fr.text
        if type(tx) == "table" and tx.GetText then
            local t = tx:GetText()
            if t and t ~= "" then return t end
        end
        return nil
    end
    local function Look(fr, kind, extra)
        local o = { kind = kind or "click", label = Label, evidence = "simulator-geometry", limit = 1000000 }
        for k, v in pairs(extra or {}) do o[k] = v end
        return RC.Analyze(fr, o)
    end
    local function Verdict(res) return res.verdict .. (res.blocker and ("/" .. res.blocker.label) or "") end
    -- the planted obstruction: made here, over a given control's hit point, in a strata above the Workshop; the Workshop never sees it
    local ov
    local function Plant(over, mouse)   -- over: the control whose hit point is covered
        local hit = RC.HitRect(over).hit
        local cx, cy = (hit[1] + hit[3]) / 2, (hit[2] + hit[4]) / 2
        if not ov then
            ov = CreateFrame("Frame", "SimlabPlantedOverlay", UIParent)
            ov:SetFrameStrata("TOOLTIP")
        end
        ov:ClearAllPoints()
        ov:SetSize(60, 40)
        ov:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / UIParent:GetEffectiveScale(), cy / UIParent:GetEffectiveScale())
        ov:EnableMouse(mouse ~= false)
        ov:Show()
    end
    local function Unplant()
        if ov then
            if ov.SetPropagateMouseClicks then pcall(ov.SetPropagateMouseClicks, ov, false) end
            ov:EnableMouse(true); ov:EnableMouse(false); ov:Hide()
        end
    end

    -- 0. the simulator's own pointer API, so its limits are written down by a check: GetMouseFoci answers what was forced, not a position
    Tab("Opportunities")
    local add = Opps().detail.add
    local pick
    for _, r in ipairs(Rows(Lists().opps)) do if r.rec and not W.Queue.Find(r.rec.id) then pick = r break end end
    Check("display", "REACH: an unqueued recipe is listed", true, pick ~= nil)
    Click(pick, "choose an unqueued recipe")
    A_Admin.SetMouseOverFrame(add)
    local forced = RC.Sample()
    Check("display", "REACH: the simulator's GetMouseFoci returns the frame the scenario FORCED (SetMouseOverFrame), as a list", "true/1/true",
        tostring(forced.ok) .. "/" .. tostring(forced.count) .. "/" .. tostring(forced.foci[1] and forced.foci[1].frame == add))
    pcall(A_Admin.SetMouseOverFrame, nil)
    A_Admin.SetMousePosition(5, 5)
    Check("display", "REACH: and it names no frame from a position (the pointer is at 5,5, nowhere near; the forced frame is not a hit test)", "0",
        tostring(#GetMouseFoci() > 0 and #GetMouseFoci() or 0))

    -- 1. the Add button, then the planted overlay, then removal
    local before = Look(add)
    Check("display", "REACH: the Add button is reachable at its hit point", "reachable", Verdict(before))
    Check("display", "REACH: its own state is eligible: shown, enabled, mouse on, clicks on, a click script", "true/true/true/true/true/true",
        tostring(before.eligibility.state.shown) .. "/" .. tostring(before.eligibility.state.enabled) .. "/" .. tostring(before.eligibility.state.mouse)
        .. "/" .. tostring(before.eligibility.state.click) .. "/" .. tostring(before.eligibility.state.handler) .. "/" .. tostring(before.eligibility.ok))
    Plant(add)
    local blocked = Look(add)
    Check("display", "NEGATIVE CONTROL: with a mouse-enabled frame planted over it, the Add button reads BLOCKED and names the planted frame",
        "blocked/SimlabPlantedOverlay", Verdict(blocked))
    Check("display", "NEGATIVE CONTROL: the report says what, where and why", "true/true/true/true/true/true", (function()
        local t = blocked.text
        return tostring(t:find("BLOCKED click on Add to crafting plan", 1, true) ~= nil) .. "/" .. tostring(t:find("hierarchy: ", 1, true) ~= nil)
            .. "/" .. tostring(t:find("expected hit point: x ", 1, true) ~= nil) .. "/" .. tostring(t:find("blocking frame: SimlabPlantedOverlay [Frame, TOOLTIP level", 1, true) ~= nil)
            .. "/" .. tostring(t:find("effective hit rect: x ", 1, true) ~= nil) .. "/" .. tostring(t:find("evidence: simulator-geometry", 1, true) ~= nil)
    end)())
    Check("display", "NEGATIVE CONTROL: the blocked button is still ELIGIBLE (enabled, a click script): its handler would work, the pointer would not reach it", "true/true",
        tostring(blocked.eligibility.ok) .. "/" .. tostring(type(add:GetScript("OnClick")) == "function"))
    local queued = #W.Queue.Entries()
    add:Click()   -- handler level: it still runs, which is exactly why a handler test cannot see the obstruction
    Check("click", "NEGATIVE CONTROL: Button:Click() still runs the blocked button's handler (a passing handler test proves nothing about the pointer)", queued + 1, #W.Queue.Entries())
    W.Session.Remove(pick.rec.id)   -- put the queue back
    Win().Render()
    Unplant()
    Check("display", "NEGATIVE CONTROL: with the overlay removed, the Add button is reachable again", "reachable", Verdict(Look(add)))
    -- M6.1 NEGATIVE CONTROL for propagation: the planted overlay passes clicks on (SetPropagateMouseClicks), so the button is reachable THROUGH it;
    -- Reachable -> Propagated -> Reachable. SIMULATED classification only: the simulator has no pointer, and the client's own behaviour (one
    -- propagating frame over a Button handed it the click, observed in Forever 1.60.1 build 70888) is a Test Lab fact, not something proved here.
    -- The overlay's flag is read through the Lab's own reader (CanPropagateMouseClicks, then GetPropagateMouseClicks): if the simulator has
    -- neither, the analysis must say UNKNOWN, which the first check records.
    Plant(add)
    local canSet = type(ov.SetPropagateMouseClicks) == "function"
    local flag = canSet and RC.Propagates(ov)
    Check("display", "REACH: the simulator's overlay answers its propagation flag (false by default) through the Lab's reader", "true/false", tostring(canSet) .. "/" .. tostring(flag))
    if canSet then
        ov:SetPropagateMouseClicks(true)
        local passed = Look(add)
        Check("display", "NEGATIVE CONTROL: with the overlay propagating clicks the Add button is REACHABLE THROUGH PROPAGATION (simulated), naming the propagating frame",
            "reachable/propagation/SimlabPlantedOverlay", passed.verdict .. "/" .. tostring(passed.via) .. "/" .. tostring(passed.propagator and passed.propagator.label))
        Check("display", "NEGATIVE CONTROL: the report says it is through propagation", true, passed.text:find("REACHABLE (through propagation) click on Add to crafting plan", 1, true) ~= nil)
        ov:SetPropagateMouseClicks(false)
        Check("display", "NEGATIVE CONTROL: propagation switched off, the overlay BLOCKS again", "blocked/SimlabPlantedOverlay", Verdict(Look(add)))
        Check("display", "NEGATIVE CONTROL: and a propagating overlay does not change what the hover sees (it still takes the pointer)", "blocked/SimlabPlantedOverlay", (function()
            ov:SetPropagateMouseClicks(true)
            local hv = Look(add, "hover", { hasScript = function() return true end })
            ov:SetPropagateMouseClicks(false)
            return Verdict(hv)
        end)())
    end
    Unplant()
    Check("display", "NEGATIVE CONTROL: with the overlay removed again, the Add button is reachable with no propagation involved", "reachable/nil", (function()
        local r = Look(add)
        return r.verdict .. "/" .. tostring(r.via)
    end)())
    -- a decorative frame (mouse off) over the button is no obstruction
    Plant(add, false)
    Check("display", "REACH: a decorative frame with the mouse off over the button does not block it", "reachable", Verdict(Look(add)))
    Unplant()

    -- 2. a hoverable row: the row, a planted overlay, removal; its picture (a child that takes the pointer); a chosen row is as reachable
    local row = pick   -- the unqueued recipe's row chosen above
    Check("display", "REACH: the row is reachable for hover at its centre", "reachable", Verdict(Look(row, "hover")))
    Plant(row)
    Check("display", "NEGATIVE CONTROL: a planted frame over the row blocks its hover", "blocked/SimlabPlantedOverlay", Verdict(Look(row, "hover")))
    Unplant()
    Check("display", "NEGATIVE CONTROL: and hover reaches the row again once it is gone", "reachable", Verdict(Look(row, "hover")))
    local pic = row.iconBtn
    Check("display", "REACH: the row's picture is reachable for hover", "reachable", Verdict(Look(pic, "hover")))
    local ph = RC.HitRect(pic).hit
    local onPic = Look(row, "hover", { point = { (ph[1] + ph[3]) / 2, (ph[2] + ph[4]) / 2 } })
    Check("display", "REACH: at the picture the row is NOT the frame under the pointer: its child is (so the row must follow the child to stay lit)", "blocked/" .. RC.Label(pic, { label = Label }) .. "/child",
        Verdict(onPic) .. "/" .. onPic.relation)
    pic:GetScript("OnEnter")(pic)
    Check("display", "REACH: the picture's own enter keeps the row lit (Follow)", "true", tostring(row.hovered))
    pic:GetScript("OnLeave")(pic)
    Check("display", "REACH: leaving the picture puts it out", "false", tostring(row.hovered))
    Click(row, "choose the row")
    Check("display", "REACH: a chosen row is still reachable for hover (selection is painting, not input)", "true/reachable", tostring(row.selected) .. "/" .. Verdict(Look(row, "hover")))
    -- a disabled button: reachable geometry, ineligible state; the handler (Click) refuses it
    Click(add, "Add to crafting plan")   -- queued: the button turns into "In your queue", disabled
    local disabled = Look(add)
    Check("display", "REACH: a queued recipe's Add button is disabled: ineligible, and still the topmost frame there", "ineligible/self", disabled.verdict .. "/" .. tostring(disabled.relation))
    W.Session.Remove(pick.rec.id)
    Win().Render()

    -- 3. hit-rect insets: the switch's label is part of its hit area
    Tab("Crafting")
    local sw = Frame().useGuild   -- "Use guild bank" in the Crafting materials card (the window frame keeps it)
    local hr = RC.HitRect(sw)
    Check("display", "REACH: the switch's hit rectangle reaches past its frame, over its label (SetHitRectInsets with a negative left)", true, hr.hit[1] < hr.rect[1] and hr.insets[1] < 0)
    local cyS = (hr.rect[2] + hr.rect[4]) / 2
    Check("display", "REACH: a point on the label is reachable for the switch", "reachable", Verdict(Look(sw, "click", { point = { hr.rect[1] - 5, cyS } })))
    Check("display", "REACH: a point further left than the hit rectangle is not the switch's", "outside", Verdict(Look(sw, "click", { point = { hr.hit[1] - 4, cyS } })))
    hr = nil

    -- 4. scroll clipping: a scroll frame the scenario owns, scrolled; and the Opportunities pool
    local sf = CreateFrame("ScrollFrame", "SimlabReachScroll", UIParent)
    sf:SetSize(200, 100); sf:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20); sf:SetFrameStrata("TOOLTIP")
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(200, 400)
    sf:SetScrollChild(child)
    local btns = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", "SimlabReachRow" .. i, child)
        b:SetSize(200, 50); b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 50)
        b:SetScript("OnClick", function() end)
        btns[i] = b
    end
    local function Seen() local out = {} for i = 1, 8 do out[#out + 1] = Verdict(Look(btns[i])):sub(1, 1) end return table.concat(out) end
    Check("display", "REACH: a scroll frame at the top shows rows 1-2: reachable (r), the rest clipped (c)", "rrcccccc", (Seen():gsub("[^rc]", "?")))
    -- SIMULATOR LIMIT, written down as a check: SetVerticalScroll stores the offset (GetVerticalScroll answers it) but the simulator does not
    -- move the scroll child's rows (GetRect is unchanged, GetVerticalScrollRange stays 0). The real engine does move them. A scrolled list is
    -- therefore modelled here by anchoring the child where the engine would put it at that offset.
    local y0 = select(2, btns[3]:GetRect())
    sf:SetVerticalScroll(100)
    Check("state", "SIMULATOR LIMIT: SetVerticalScroll does not move the rows' rectangles (so scrolling is modelled by anchoring)", "stored 100, rect unchanged",
        "stored " .. sf:GetVerticalScroll() .. ", rect " .. (select(2, btns[3]:GetRect()) == y0 and "unchanged" or "MOVED: the simulator now scrolls; use it"))
    sf:SetVerticalScroll(0)
    child:ClearAllPoints()
    child:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 100)   -- the child 100 higher: two rows scrolled out of the top
    Check("display", "REACH: scrolled by two rows (the child 100 higher), rows 3-4 are reachable and 1-2 are clipped", "ccrrcccc", (Seen():gsub("[^rc]", "?")))
    sf:Hide()
    Check("display", "REACH: a hidden scroll frame hides every row (ineligible, none reachable)", "iiiiiiii", (Seen():gsub("[^i]", "?")))
    -- the pooled Opportunities rows: only the SHOWN ones take the pointer; recycled (hidden) rows never do
    Tab("Opportunities")
    local list = Lists().opps
    local shown, pooled, taking = 0, #list.rows, 0
    local col = RC.Collect({ limit = 1000000 })
    local takes = {}
    for _, c in ipairs(col.list) do takes[c.frame] = true end
    for _, r in ipairs(list.rows) do
        if r:IsShown() then shown = shown + 1 end
        if takes[r] then taking = taking + 1 end
    end
    Check("display", "REACH: the Opportunities pool: the rows that take the pointer are exactly the shown ones", shown .. "/" .. shown, taking .. "/" .. shown)
    local worst = "all reachable or scrolled out"
    for _, r in ipairs(Rows(list)) do
        local res = Look(r, "hover", { collected = col })
        if res.verdict ~= "reachable" and res.verdict ~= "clipped" then worst = r.rec and Verdict(res) or res.verdict end
    end
    Check("display", "REACH: each shown Opportunities row is reachable for hover or scrolled out of view", "all reachable or scrolled out", worst)
    Check("state", "REACH: the pool is not smaller than what it shows", true, pooled >= shown)

    -- 5. a tooltip does not take the pointer from what it covers
    GameTooltip:SetOwner(add, "ANCHOR_TOP")
    GameTooltip:AddLine("Simlab reachability tooltip")
    GameTooltip:Show()
    local tipMouse = GameTooltip:IsMouseEnabled()
    Check("display", "REACH: with the game tooltip shown beside the button, the Add button is reachable; the tooltip's own mouse flag is reported", "reachable/" .. tostring(tipMouse),
        Verdict(Look(add)) .. "/" .. tostring(tipMouse))
    GameTooltip:Hide()

    sf:Hide()
    Unplant()
    Win().SetMode("overview")
    W.Session.ClearNote()
    Win().Render()
end)

---------------------------------------------------------------------------------------------------------------------------
-- The pose a screenshot is taken in (params.view). The checks above are the same in every launch.
---------------------------------------------------------------------------------------------------------------------------
-- A6: updating prices on opening the auction house. The Workshop is loaded already here (the earlier steps opened it), so the core detector, the policy
-- and the shared scanner run for real against the fake auction house; what is NOT proven is that the REAL client accepts an automatic request (the Test
-- Lab probes autoscan.* do that). The detector's entry points (WA.Opened/WA.Closed, what its events call) are called directly: the events themselves would make Blizzard load its real auction UI, which the simulator cannot (the events are covered in tests/test_workshop_auto.lua). A market of its own (the other side) keeps the scenario's main prices untouched; it is removed afterwards.
Lab.Step("automatic price updates on opening the auction house", function()
    local WA, A, SC = R.WorkshopAuto, R.Workshop.Auto, R.Workshop.Scan
    local AB = R.Workshop.AuctionButton
    local realFaction, realCombat = UnitFactionGroup, InCombatLockdown
    local offset = 0
    local wall0, mono0 = A.wall, A.mono
    A.wall = function() return time() + offset end
    A.mono = function() return GetTime() + offset end
    UnitFactionGroup = function() return "Horde" end
    local KEY = "SimulatedRealm|Horde"
    local function Open() SetAuctionHouse(true) WA.Opened() Lab.Settle(0.1) end
    local function Close() SetAuctionHouse(false) WA.Closed() Lab.Settle(0.05) end
    local function Finish() A_Admin.FireEvent("REPLICATE_ITEM_LIST_UPDATE") Lab.Settle(2.6) end   -- (the scan's quiet period is 2 s)
    local function Saved() local m = TwichUIWorkshopDB.markets[KEY] return m and (m.snap and m.snap.seq or 0) or "none" end
    local base = ah.requested
    A.Reset()
    Check("init", "shipped policy is manual and the setting off by default", "manual/false", WA.POLICY .. "/" .. tostring(R:Enabled("workshopAutoScan")))
    Open()
    Check("event", "manual policy: opening makes no request and offers no prompt", "0/false", (ah.requested - base) .. "/" .. tostring(A.Prompting()))
    Close()
    WA.POLICY = "auto" R:SetEnabled("workshopAutoScan", true)   -- (the A6 behaviour, kept for a later decision, is what the rest of this step exercises)
    Check("init", "the capability is not yet verified in the real client", "unknown", WA.Capability())
    -- unknown capability: a prompt, never a request
    Open()
    Check("event", "unverified capability: opening makes no request", 0, ah.requested - base)
    Check("state", "unverified capability: a one-click prompt is offered", "prompt/true", tostring(A.state.action) .. "/" .. tostring(A.Prompting()))
    if AB and AB.Button() then
        Check("display", "the button offers Update prices", "Update prices", Txt(AB.Button().text))
        Click(AB.Button(), "Update prices")
        Check("click", "the click is the player's own scan: one request", "scanning/1", SC.state .. "/" .. (ah.requested - base))
        Check("display", "while it runs the button is Stop", "Stop", Txt(AB.Button().text))
        Check("click", "a click while it runs stops it, nothing saved", "true/stopped/none", tostring(SC.Stop()) .. "/" .. tostring(SC.why) .. "/" .. tostring(Saved()))
    else
        Check("init", "(the Auction House button exists)", true, false)
    end
    -- supported (set here for the test only): fresh market, then due
    -- (an earlier accepted scan of this market, made directly: the full scan takes more simulated time than this scenario has left)
    Check("state", "an earlier scan is saved for the market", true, R.Workshop.Prices.Commit(KEY, { realm = "SimulatedRealm", side = "Horde", at = time() + offset, complete = true,
        read = 1, used = 1, n = 1, items = { [2447] = "5,1,1,1,0" } }) ~= false)
    local seq = Saved()
    Close() WA.CAPABILITY = "supported" Open()
    Check("event", "fresh market: no further request", 1, ah.requested - base)
    Check("state", "fresh market: the visit says so", "skip/fresh", tostring(A.state.action) .. "/" .. tostring(A.state.why))
    Close() offset = 3700 Open()
    Check("event", "an hour later the update starts by itself, once", "scanning/2", SC.state .. "/" .. (ah.requested - base))
    Check("display", "its line says prices are updating", "Updating market prices...", (SC.Message()))
    if AB and AB.Button() then Check("display", "the button is its Stop", "Stop", Txt(AB.Button().text)) end
    -- Stop: ends it, writes nothing, a late answer changes nothing
    Check("click", "Stop ends the scan", "true/stopped", tostring(SC.Stop()) .. "/" .. tostring(SC.why))
    A_Admin.FireEvent("REPLICATE_ITEM_LIST_UPDATE") Lab.Settle(0.3)
    Check("state", "stopped: nothing was saved", seq, Saved())
    -- the window closing mid-scan
    Close() offset = 7400 Open()
    Check("event", "due again: a request", "scanning/3", SC.state .. "/" .. (ah.requested - base))
    A_Admin.FireEvent("REPLICATE_ITEM_LIST_UPDATE") Lab.Settle(0.1)
    Close()
    Lab.Settle(2.3)   -- (the scan notices the closed window when its quiet period ends and the reading begins)
    Check("state", "closed during the scan: interrupted, nothing saved", "interrupted/closed/" .. tostring(seq), SC.state .. "/" .. tostring(SC.why) .. "/" .. tostring(Saved()))
    -- the setting off, and combat
    local n = ah.requested
    R:SetEnabled("workshopAutoScan", false) offset = 11100 Close() Open()
    Check("event", "setting off: no request", 0, ah.requested - n)
    R:SetEnabled("workshopAutoScan", true)
    Close() InCombatLockdown = function() return true end Open()
    Check("event", "in combat: no request, and the visit says why", "0/combat", (ah.requested - n) .. "/" .. tostring(WA.Snapshot().skipped))
    InCombatLockdown = realCombat
    -- the same events again are one visit: one request
    Close() Open() WA.Opened() WA.Opened() Lab.Settle(0.1)
    Check("event", "repeated equivalent events: one request for the visit", 1, ah.requested - n)
    Finish()
    local mk = TwichUIWorkshopDB.markets[KEY]
    Check("state", "the automatic scan is saved as automatic, in the version-2 database", "true/" .. tostring(R.Workshop.Prices.SAVED_VERSION),
        tostring(mk and mk.snap and mk.snap.auto) .. "/" .. tostring(TwichUIWorkshopDB.v))
    Check("state", "the other market was not touched", "SimulatedRealm|unknown", (function() local m = R.Workshop.Prices.Market("SimulatedRealm|unknown") return m and m.key or "none" end)())
    -- put everything back
    Close()
    WA.CAPABILITY = "unknown"
    UnitFactionGroup = realFaction
    A.wall, A.mono = wall0, mono0
    A.Reset()
    TwichUIWorkshopDB.markets[KEY] = nil
    SetAuctionHouse(true)
    Lab.Settle(0.3)
end)

Lab.Step("pose for the screenshot", function()
    local view = params.view or "craft"
    Say("pose", view)
    if view == "craft" then
        Tab("Crafting")
        Click(Win().Craft().segQueue, "Craft queue (the left card)")
        Click(Rows(Lists().queue)[2], "choose the second queued craft")
        Check("display", "pose: the chosen craft's details", Txt(Rows(Lists().queue)[2].name), Txt(Win().Craft().detail.name))
        Rows(Lists().queue)[3]:SetHot(true)   -- a row under the pointer, for the screenshot (the art only: no tooltip is opened)
    elseif view == "empty" then
        -- the empty states: every queued craft removed through the details' Remove, and the saved prices taken away (synthetic data:
        -- the scenario's own fake market, nothing of a real install)
        Tab("Crafting")
        while #Rows(Lists().queue) > 0 do QueueAct(Rows(Lists().queue)[1], "remove", "Remove (emptying the queue)") end
        TwichUIWorkshopDB.markets = {}
        -- the game gives no profession skill either (the call is missing): the Workshop's own professions are drawn as unavailable
        GetProfessions, GetProfessionInfo = nil, nil
        Tab("Overview")
        Check("display", "pose: no prices is said, not a made-up figure", "No scan yet", Txt(Win().Overview().cards.market.facts[1].text))
        Check("display", "pose: no skill from the game is unavailable, not zero", "n/a | 0", Txt(Win().Overview().cards.profs.facts[1].value) .. " | " .. Win().Overview().cards.profs.facts[1].bar.frac)
        Check("display", "pose: an empty plan", "0 | of 30 queued", Txt(Win().Overview().cards.plan.stat) .. " | " .. Txt(Win().Overview().cards.plan.statLabel))
        Check("display", "pose: the quick action to scan prices", "Scan prices", Txt(Win().Overview().actions.scan.text))
    elseif view == "overview" or view == "smallov" then
        -- four professions, the last with a long name: the card has to hold them (the pose of the Overview screenshots, normal and small screen)
        SKILLS[4] = { "Enchanting and other long localized names", 136241, 300, 300 }
        GetProfessions = function() return 1, 2, 3, 4 end
        Tab("Overview")
        Check("display", "pose: the Overview with prices, a plan and skills", true, Win().Overview():IsShown())
        Check("display", "pose: four professions, the maximum one full", "4 | 300 / 300 | 1.0000", (function()
            local rows = Win().Overview().cards.profs.facts
            local n = 0
            for _, r in ipairs(rows) do if r:IsShown() then n = n + 1 end end
            return n .. " | " .. Txt(rows[4].value) .. " | " .. ("%.4f"):format(rows[4].bar.frac)
        end)())
        local ov = Win().Overview()
        Check("display", "pose: the market card says how many items were priced and that the scan was whole", "13 | Scan complete \194\183 just now",
            Txt(ov.cards.market.stat) .. " | " .. Txt(ov.cards.market.facts[1].text))
        Check("display", "pose: the opportunities card counts what is profitable and names the best", "4 | of 5 priced | Top profit: Smelt Bronze",
            Txt(ov.cards.opps.stat) .. " | " .. Txt(ov.cards.opps.side) .. " | " .. Txt(ov.cards.opps.facts[1].text))
        Check("display", "pose: the activity names the scan and the plan changes of this run", true, Txt(ov.activity[1].text) ~= "" and ov.activity[3]:IsShown())
    elseif view == "history" then
        -- the history chart with several observed days and a gap (synthetic days: the market's own scan day, and earlier ones)
        Tab("Opportunities")
        local mk = TwichUIWorkshopDB.markets["SimulatedRealm|unknown"]
        local today = math.floor(time() / 86400)
        mk.hist[118] = (today - 6) .. ",190;" .. (today - 5) .. ",175;" .. (today - 3) .. ",160;" .. (today - 2) .. ",180;" .. today .. ",150|"
        Click(Row(Lists().opps, "Minor Healing Potion"), "choose Minor Healing Potion")
        local chart = Opps().detail.chart
        Check("display", "pose: five observed days are five dots, a gap where no scan was made", "5 | 5 observed days", chart.shown .. " | " .. Txt(Opps().detail.chartNote))
    elseif view == "craftlong" then
        -- a longer queue: every known recipe of both professions
        Tab("Crafting")
        Click(Win().Craft().segRecipes, "Recipes")
        for _, p in ipairs({ "Alchemy", "Blacksmithing" }) do
            Click(FindButton(Frame(), p), p .. " chip")
            for _, r in ipairs(Rows(Lists().recipes)) do if r.add:IsEnabled() then Click(r.add, "Add " .. Txt(r.name)) end end
        end
        Click(Win().Craft().segQueue, "Craft queue")
        Check("display", "pose: a long queue", true, #R.Workshop.Queue.Entries() >= 7)
        Click(Rows(Lists().queue)[3], "choose the third queued craft")
        Rows(Lists().queue)[5]:SetHot(true)
    elseif view == "shopmix" or view == "shopcollect" then
        -- stored materials make Collect rows beside Buy and Make rows; with everything stored only Collect rows remain (synthetic bank counts)
        Tab("Crafting")
        QueueAct(Rows(Lists().queue)[4], "remove", "Remove Smelt Bronze")
        if view == "shopmix" then
            R.Workshop.Storage.StoreBank({ ids = { 6 }, tabs = { [6] = { [2447] = 2, [765] = 1 } }, incomplete = 0 }, R.Workshop.Queue.Now() - 7200)
        else
            SetBags({})
            R.Workshop.Storage.StoreBank({ ids = { 6 }, tabs = { [6] = { [2447] = 7, [765] = 3, [3371] = 5, [2841] = 8, [2320] = 2 } }, incomplete = 0 }, R.Workshop.Queue.Now() - 7200)
        end
        Event("BAG_UPDATE_DELAYED")
        Tab("Shopping")
        local kinds = {}
        for _, r in ipairs(Rows(Lists().shop)) do kinds[r.data.kind] = (kinds[r.data.kind] or 0) + 1 end
        if view == "shopmix" then
            Check("display", "pose: Collect rows beside Buy rows", true, (kinds.collect or 0) > 0 and (kinds.buy or 0) > 0)
        else
            Check("display", "pose: only Collect rows", "nil/nil/5", tostring(kinds.buy) .. "/" .. tostring(kinds.make) .. "/" .. tostring(kinds.collect))
        end
    elseif view == "opps" then
        Tab("Opportunities")
        local row = Row(Lists().opps, "Minor Healing Potion")
        Click(row, "choose Minor Healing Potion")
        Check("display", "pose: its details are shown", "Minor Healing Potion", Txt(Opps().detail.name))
        Row(Lists().opps, "Weak Troll's Blood Potion"):SetHot(true)   -- a row under the pointer, for the screenshot
        Check("display", "pose: the details price one craft's materials, each with its quantity", true, Txt(Opps().detail.mats[1].qty):find("^\195\151%d+") ~= nil and Opps().detail.mats[1].item ~= nil)
    elseif view == "design" then
        -- the settings window on the Workshop page, scrolled to the tooltip designer, the Hold Shift preview with a line selected
        Lab.Open("workshop")
        local D = R.WorkshopWorthDesigner
        D.SetMode(true)
        D.Select("auction")
        local content = R.SettingsUI.View("workshop").frame:GetParent()
        local scroll = content and content:GetParent()
        Lab.Settle(0.2)   -- let the page lay out before measuring where the designer is
        local ct, dt = content and content:GetTop(), D.Frame():GetTop()
        if scroll and scroll.SetVerticalScroll and ct and dt then scroll:SetVerticalScroll(math.max(0, ct - dt - 8)) end
        Lab.Settle(0.2)
        Check("display", "pose: the designer is on screen with the Hold Shift preview", true, D.Frame():IsShown() and D.Mode())
    elseif view == "shop" then
        -- the mixed-source list with a Make row: take the Smelt Bronze entry back out through its Remove button
        Tab("Crafting")
        local q = Lists().queue
        QueueAct(Rows(q)[4], "remove", "Remove Smelt Bronze")
        Tab("Shopping")
        Check("display", "pose: shopping shows the Make row again", "Silverleaf | Coarse Thread | Peacebloom | Copper Ore | Tin Ore | Bronze Bar", Names(Lists().shop))
        Rows(Lists().shop)[2]:SetHot(true)   -- a row under the pointer, for the screenshot
    end
    Lab.Settle(0.5)
end)

Lab.Finish()
