-- Optional settings capture: real bank review and runner, synthetic game reads and an explicitly settled move queue.
-- No live bank calls or inventory data. The simulator proves handler/state behavior, not real client input or transfers.
function Lab.BankReview(pose)
    local R, MI = TwichUI, TwichUI.MagicInventory
    R.SettingsUI.Close()
    local items = {
        [2447] = { name = "Peacebloom", icon = R.PATH .. [[media\icons\magic-herbs]], max = 100 },
        [2589] = { name = "Linen Cloth", icon = R.PATH .. [[media\npcs\cloth-bolts]], max = 100 },
        [2770] = { name = "Copper Ore", icon = R.PATH .. [[media\icons\magic-ore]], max = 100 },
    }
    C_Item.GetItemInfoInstant = function(id) local i = items[id]; if i then return id, "", "", "", i.icon, 7, 5 end end
    C_Item.GetItemInfo = function(id)
        local i = items[id]
        if i then return i.name, "|cffffffff|Hitem:" .. id .. "|h[" .. i.name .. "]|h|r", 1, 1, 1, "", "", i.max, "", i.icon, 1, 7, 5, 0 end
    end
    MI.ClearItemCache()
    local bags = { [0] = { [1] = { id = 2447, count = 55 }, [2] = { id = 2589, count = 5 }, [3] = { id = 2770, count = 27 } },
        [6] = { [1] = { id = 2447, count = 20 }, [2] = { id = 2589, count = 80 } } }
    local cursor, pending
    local attempts = 0
    C_Container.GetContainerNumSlots = function(bag) return bags[bag] and 16 or 0 end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local s = bags[bag] and bags[bag][slot]
        if s then return { itemID = s.id, stackCount = s.count, isLocked = false, isBound = false, iconFileID = items[s.id].icon,
            hyperlink = "|cffffffff|Hitem:" .. s.id .. "|h[" .. items[s.id].name .. "]|h|r" } end
    end
    C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false } end
    C_Container.GetContainerNumFreeSlots = function(bag)
        local n = 0
        if bags[bag] then for slot = 1, 16 do if not bags[bag][slot] then n = n + 1 end end end
        return n, 0
    end
    C_Bank.FetchPurchasedBankTabIDs = function() return { 6 } end
    C_Bank.CanUseBank = function() return true end
    CursorHasItem = function() return cursor ~= nil end
    GetCursorInfo = function() if cursor then return "item", cursor.id end end
    ClearCursor = function() cursor = nil end
    local function Pick(bag, slot, count)
        local s = bags[bag] and bags[bag][slot]
        if not cursor and s then cursor = { id = s.id, count = count or s.count, bag = bag, slot = slot } end
    end
    C_Container.SplitContainerItem = function(bag, slot, count) attempts = attempts + 1; Pick(bag, slot, count) end
    C_Container.PickupContainerItem = function(bag, slot)
        attempts = attempts + 1
        if cursor then pending = { src = cursor, bag = bag, slot = slot }; cursor = nil else Pick(bag, slot) end
    end
    local function Settle()
        local m = pending
        if m then
            local src = bags[m.src.bag][m.src.slot]
            src.count = src.count - m.src.count
            if src.count == 0 then bags[m.src.bag][m.src.slot] = nil end
            local dst = bags[m.bag][m.slot]
            bags[m.bag][m.slot] = { id = m.src.id, count = (dst and dst.count or 0) + m.src.count }
            pending = nil
            A_Admin.FireEvent("BAG_UPDATE_DELAYED")
        end
        Lab.Settle(.1)
    end
    TwichUIDB.modules.magicInventory = true
    MI.ReplaceRules({})
    for _, v in ipairs({ { "Herbal supplies", 2447, 20 }, { "Cloth for bandages", 2589, 20 }, { "Mining supplies", 2770, 10 } }) do
        MI.SaveRule({ name = v[1], kind = "bank", enabled = true, flow = "balance", keep = v[3], include = { [v[2]] = true } })
    end
    MI.Refresh()
    A_Admin.FireEvent("BANKFRAME_OPENED"); Lab.Settle(.2)
    Lab.Check("state", "opening bank moves nothing", 0, attempts)
    MI.Window.Show(); Lab.Settle(.2)
    local f = TwichUIMagicInventory
    f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    Lab.Check("construct", "compact bank review shown", true, MI.Window.Context() == "bank" and f:IsShown())
    Lab.Check("state", "both directions in review", 3, MI.Window.Plan().stacks)
    Lab.Check("construct", "deposit quantity summary", "52 items", f.bankSummary.deposit.value:GetText())
    Lab.Check("construct", "withdraw quantity summary", "15 items", f.bankSummary.withdraw.value:GetText())
    Lab.Check("construct", "batch action visible", true, f.bankGo:IsShown() and f.bankGo:IsEnabled())
    Lab.Check("state", "review moves nothing", 0, attempts)
    local autoSort = f.bankAutoSort
    Lab.Check("construct", "auto-sort switch fits between bank actions", true,
        autoSort.label:GetLeft() > f.bankGo:GetRight() and autoSort:GetRight() < f.again:GetLeft())
    if pose == "ready" then
        Lab.Check("state", "auto-sort switch starts on", true, autoSort:GetChecked())
        autoSort:Click(); Lab.Settle(.1)
        Lab.Check("interact", "auto-sort switch turns off", false, MI.BankAutoSort())
        autoSort:Click(); Lab.Settle(.1)
        Lab.Check("interact", "auto-sort switch turns back on", true, autoSort:GetChecked() and MI.BankAutoSort())
    end
    local function Find(frame, text)
        if not frame:IsShown() then return end
        if type(frame.text) == "table" and frame.text.GetText and frame.text:GetText() == text then return frame end
        for _, child in ipairs({ frame:GetChildren() }) do local found = Find(child, text); if found then return found end end
    end
    if pose == "actions" or pose == "manual" then
        Find(f, "Rule actions"):Click(); Lab.Settle(.2)
        Lab.Check("construct", "manual actions available", true, Find(f, "Deposit all") ~= nil and Find(f, "Withdraw all") ~= nil)
        if pose == "manual" then
            Find(f, "Withdraw all"):Click(); Lab.Settle(.2)
            Lab.Check("state", "manual selection reviews only", true, MI.Window.Plan().manual ~= nil and MI.Run.Current() == nil)
            Lab.Check("state", "manual selection moves nothing", 0, attempts)
        end
    elseif pose == "run" or pose == "complete" or pose == "stopped" then
        f.bankGo:Click(); Lab.Settle(.1)
        Lab.Check("state", "batch begins after click", true, MI.Run.Current() ~= nil)
        Lab.Check("state", "attempt not confirmed", 0, MI.Run.BankProgress().confirmed)
        Settle()
        Lab.Check("state", "first move confirmed", 1, MI.Run.BankProgress().confirmed)
        Lab.Check("construct", "progress bar visible", true, f.bankProgress:IsShown())
        if pose == "complete" then
            Settle(); Settle()
            Lab.Check("state", "batch complete without more clicks", true, MI.Run.Current() == nil and MI.Run.Last().stopReason == "done")
            Lab.Check("state", "all moves confirmed", 3, MI.Run.BankProgress().confirmed)
        elseif pose == "stopped" then
            f.stop:Click(); Lab.Settle(.1)
            Lab.Check("state", "stop retains partial progress", true, MI.Run.Current() == nil and MI.Run.BankProgress().confirmed == 1)
        end
    end
    Lab.Check("construct", "primary and footer fit window", true, f.bankGo:GetLeft() >= f:GetLeft() and f.manage:GetRight() <= f:GetRight())
end
