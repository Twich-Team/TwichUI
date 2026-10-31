-- Simulator lab scenario (docs/simulator-lab.md): the Magic Inventory guild bank arrangement editor, drawn by the real settings
-- page from SYNTHETIC data. Run once per view by tools/simlab/guild_bank_preview.sh, each launch followed by a screenshot
-- (scenarios/lib.lua goes in front of this file).
--
-- WHAT IS SYNTHETIC. The simulator knows no items and has no guild bank, so this file stands in for the game's READ calls only:
-- the item lookups for a few made-up ids (C_Item.GetItemInfoInstant / GetItemInfo, other ids pass through), the carried bags
-- (C_Container.GetContainerNumSlots / GetContainerItemInfo / GetContainerItemQuestInfo) and the guild bank (IsInGuild,
-- GetGuildInfo, GetNumGuildBankTabs, GetCurrentGuildBankTab, GetGuildBankTabInfo, GetGuildBankItemInfo, GetGuildBankItemLink).
-- The addon's own reader (inventory/GuildBank.lua), planner, draft model (inventory/Design.lua) and page are the real code. No
-- stand-in exists for anything that moves an item: if the addon called PickupGuildBankItem, SplitGuildBankItem,
-- AutoStoreGuildBankItem, SetCurrentGuildBankTab or QueryGuildBankTab it would raise an error, which this run would show.
-- Items, guild and numbers below are examples, not anything a player has. Nothing here says how the real guild bank answers.
--
-- THE RUN STAGES (review, run, timeout, blocked) drive the real executor (inventory/GuildRun.lua) and its page against an INERT
-- game: only when one of them is asked for, PickupGuildBankItem, SplitGuildBankItem, C_Container.PickupContainerItem/SplitContainerItem
-- are replaced by stand-ins that record the call and change NOTHING (and, for "blocked", raise ADDON_ACTION_BLOCKED as the game does
-- when it refuses a call). So the run can only show what an executor shows when the game does not answer: a review to confirm, "0
-- of N moves confirmed" with "Waiting for the bank...", a pause that asks for a click, and "Needs review" after the wait. A completed
-- run is NOT shown here: that needs a guild bank that moves items, which this lab does not emulate (tests/mi_guildsim.lua stands in
-- for it in the unit tests only, and proves the executor's decisions, not the game's behaviour).
--
-- WHAT "INTERACTION" IS. Handler level: a click is Button:Click(); a drop is the page's own P.ApplyDesign (the function a real
-- drop calls) with the same arguments the drop handler passes; the split dialog is typed into and its buttons clicked. There is
-- no pointer here, so real dragging (OnDragStart, the pointer over a target, OnDragStop) and Shift-click are NOT exercised.
--
-- THE PANEL STAGES (panel = "reading" | "ready" | "review" | "run" | "blocked" | "timeout" | "partial" | "setup") draw the real panel at
-- the bank window (inventory/GuildPanel.lua) and the real preparation (inventory/GuildPrep.lua) with NOTHING of the settings page. The
-- bank window is a plain stand-in frame named GuildBankFrame (a 760x560 box where the real one would be, so the screenshot shows where the
-- panel sits beside it) whose tab buttons only set the shown tab and, a moment later, send GUILDBANKBAGSLOTS_CHANGED for it: the read
-- path of the game, as these other stand-ins are, and nothing that moves an item. "reading": the tabs never answer; "partial": tab 3
-- never answers; "run"/"blocked"/"timeout" use the inert game below. A COMPLETED run, the review of a run that crosses tabs being
-- carried out, and the cursor across a tab switch are NOT shown here: nothing in this lab moves an item (tests/mi_guildsim.lua stands
-- in for that in the unit tests only).
--
-- fixture = "completed" | "partial" | "unavailable" | "short" (panel stages only: presentation-only, see the code), details = true.
-- Parameters (SIMLAB_PARAMS): view = "design" | "current" | "preview", size = "default" (920x660) | "min" (920x480),
-- script = a comma list of stages run in order before the screenshot:
--   assign   Linen to tab 2 (automatic), Silk pinned to tab 2 slot 5, Linen pinned in slots 3, 4 and 10 (5, 5 and 10 by splitting)
--   layout   (the stack-size model) four items given to tab 2 automatically, Linen in stacks of 5 and Silk in stacks of 50, laid out
--            as params.layout says ("packed" | "spaced" | "columns", default spaced); nothing is pinned
--   cancel   a split whose destination is never chosen (Cancel), a split closed with Esc: the design must be unchanged
--   merge    a Peacebloom stack split in two and combined back
--   refuse   an incompatible combination and a quantity above the stack limit
--   save     Save arrangement, then reopen the page: the draft must equal what was saved
--   menu     a right-click on a reserved stack opens the item menu (the shared list), then it is closed
--   short    reserve more Silk than the bags hold, so the preview shows missing stock
--   stale    change the design after a preview, then change the bank: the one-line stale messages
--   conflict a broader cloth rule above the arrangement (needs existing = true)
--   review   (needs existing = true) Preview, then Deposit...: the review to confirm, with what is not included; nothing starts
--   run      review, then Start with an inert game: progress "0 of N", "Waiting for the bank...", no marker is claimed as done
--   timeout  run, then the wait passes with no answer: Needs review, one uncertain move, nothing retried
--   blocked  review, then Start with a game that refuses calls outside a click: the pause that asks for Continue
-- existing = true: the profile already has three category guild rules (Cloth, Herbs, Ore) above anything the editor writes;
-- source = "bags" | "bank" (the preview's source), tab = the tab to show, details = true (open Details),
-- bank = "open" | "closed" (after visiting the tabs), focus = the key of the page control to scroll to (default "gVDes"),
-- scroll = a number of pixels to add to that.
local R = TwichUI
local MI = R.MagicInventory
local Check = Lab.Check
local params = rawget(_G, "SIMLAB_PARAMS") or {}

A_Admin.SetManualClock(GetTime())
Lab.Solo()

-- ---------------------------------------------------------------- the synthetic world
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ITEMS = {
    [2589] = { name = "Linen Cloth", class = 7, sub = 5, stack = 20, icon = "Interface\\Icons\\INV_Fabric_Linen_01" },
    [2592] = { name = "Wool Cloth", class = 7, sub = 5, stack = 20, icon = "Interface\\Icons\\INV_Fabric_Wool_01" },
    [4306] = { name = "Silk Cloth", class = 7, sub = 5, stack = 200, icon = "Interface\\Icons\\INV_Fabric_Silk_01" },
    [2447] = { name = "Peacebloom", class = 7, sub = 9, stack = 20, icon = "Interface\\Icons\\INV_Misc_Flower_02" },
    [2770] = { name = "Copper Ore", class = 7, sub = 7, stack = 20, icon = "Interface\\Icons\\INV_Ore_Copper_01" },
    [6948] = { name = "Hearthstone", class = 15, sub = 0, stack = 1, icon = "Interface\\Icons\\INV_Misc_Rune_01" },
}
local origInstant, origInfo = C_Item.GetItemInfoInstant, C_Item.GetItemInfo
C_Item.GetItemInfoInstant = function(id)
    local i = ITEMS[id]
    if i then return id, "", "", "", i.icon, i.class, i.sub end
    return origInstant(id)
end
C_Item.GetItemInfo = function(id)
    local i = ITEMS[id]
    if i then
        return i.name, "|cffffffff|Hitem:" .. id .. "::::::::80:70:::::::::|h[" .. i.name .. "]|h|r", 1, 1, 1, "", "", i.stack, "", i.icon, 1, i.class, i.sub, 0
    end
    return origInfo(id)
end

local BAGS = {
    [0] = { size = 16, slots = {
        [1] = { 2589, 20 }, [2] = { 2589, 20 }, [3] = { 2589, 5 }, [4] = { 2592, 12 },
        [5] = { 4306, 120 }, [6] = { 4306, 30 }, [7] = { 2447, 10 }, [8] = { 2770, 7 }, [9] = { 6948, 1 },
    } },
}
C_Container.GetContainerNumSlots = function(bag) return BAGS[bag] and BAGS[bag].size or 0 end
C_Container.GetContainerItemInfo = function(bag, slot)
    local s = BAGS[bag] and BAGS[bag].slots[slot]
    if not s then return nil end
    return { itemID = s[1], stackCount = s[2], isBound = false, isLocked = false, iconFileID = ITEMS[s[1]].icon,
        hyperlink = "|cffffffff|Hitem:" .. s[1] .. "::::::::80:70:::::::::|h[" .. ITEMS[s[1]].name .. "]|h|r" }
end
C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false } end
C_Container.GetContainerItemEquipmentSetInfo = function() return false, "" end

local GUILD = "Night Owls"
local FULL = {}
for s = 1, 98 do FULL[s] = { 6948, 1 } end   -- a tab with no free slot (synthetic)
local TABS = {
    [1] = { name = "Gear", icon = "Interface\\Icons\\INV_Chest_Plate04", viewable = true, canDeposit = true, withdraw = -1, remaining = -1,
        slots = { [1] = { 6948, 1 }, [3] = { 2770, 4 }, [4] = { 2447, 6 }, [8] = { 2592, 9 } } },
    [2] = { name = "Cloth", icon = "Interface\\Icons\\INV_Fabric_Linen_01", viewable = true, canDeposit = true, withdraw = -1, remaining = -1,
        slots = { [1] = { 2589, 8 }, [2] = { 2589, 20 }, [4] = { 2592, 15 }, [15] = { 4306, 80 }, [16] = { 6948, 1 } } },
    [3] = { name = "Herbs", icon = "Interface\\Icons\\INV_Misc_Flower_02", viewable = true, canDeposit = false, withdraw = 0, remaining = 0,
        slots = { [1] = { 2447, 20 }, [2] = { 2447, 12 } } },
    [4] = { name = "Ore and stone", icon = "Interface\\Icons\\INV_Ore_Copper_01", viewable = true, canDeposit = true, withdraw = -1, remaining = -1,
        slots = FULL },
    [5] = { name = "Officers", icon = "Interface\\Icons\\INV_Misc_Key_03", viewable = false, canDeposit = false, withdraw = 0, remaining = 0, slots = {} },
}
local current, bankOpen = 2, false
IsInGuild = function() return true end
GetGuildInfo = function() return GUILD, "Member", 3 end
GetNumGuildBankTabs = function() return 5 end
GetCurrentGuildBankTab = function() return current end
GetGuildBankTabInfo = function(tab)
    local t = TABS[tab]
    if not t then return nil end
    return t.name, t.icon, t.viewable, t.canDeposit, t.withdraw, t.remaining
end
GetGuildBankItemInfo = function(tab, slot)
    local s = TABS[tab] and TABS[tab].slots[slot]
    if not s then return nil, 0, false, false, 1 end
    return ITEMS[s[1]].icon, s[2], false, false, 1
end
GetGuildBankItemLink = function(tab, slot)
    local s = TABS[tab] and TABS[tab].slots[slot]
    return s and ("|cffffffff|Hitem:" .. s[1] .. "::::::::80:70:::::::::|h[" .. ITEMS[s[1]].name .. "]|h|r") or nil
end

local function Event(name, ...)
    local script = R.frame:GetScript("OnEvent")
    script(R.frame, name, ...)
end
local function ShowTab(tab) current = tab; Event("GUILDBANKBAGSLOTS_CHANGED") end

-- ---------------------------------------------------------------- the player's settings (synthetic)
R:SetEnabled("magicInventory", true)
local function Dest(label, tab)
    local id = MI.AddDest("guild", label)
    MI.SetGuildTab(id, GUILD, tab, TABS[tab].name, TABS[tab].icon)
    return id
end
if params.existing then
    MI.SaveRule({ kind = "guild", name = "Cloth to the Cloth tab", enabled = true, dest = Dest("Cloth tab", 2), cats = { "7:5" }, stack = 20, include = { [4306] = true } })
    MI.SaveRule({ kind = "guild", name = "Herbs to the Herbs tab", enabled = true, dest = Dest("Herb tab", 3), cats = { "7:9" } })
    MI.SaveRule({ kind = "guild", name = "Ore to the Ore tab", enabled = true, dest = Dest("Ore tab", 4), cats = { "7:7" } })
end
local rulesBefore, destsBefore, generationBefore = #MI.Rules(), #MI.Dests(), MI.Generation()

if params.size == "min" then
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.settingsWindow = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, w = 920, h = 480 }
end

-- ---------------------------------------------------------------- the panel stages (see the header)
if params.panel then
    local mode = params.panel
    local host = CreateFrame("Frame", "GuildBankFrame", UIParent)
    host:SetSize(760, 560)
    host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110)
    local bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.16, 0.13, 0.1, 0.92)
    local label = host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("TOP", 0, -14)
    label:SetText("Guild Bank (stand-in window: where the real one is)")
    host.mode = "bank"
    host.BankTabs = {}
    local function Answer() C_Timer.After(0.1, function() Event("GUILDBANKBAGSLOTS_CHANGED") end) end
    for i = 1, 5 do
        host.BankTabs[i] = { OnClick = function()
            current = i
            if mode ~= "reading" and not (mode == "partial" and i == 3) then Answer() end
        end }
    end
    QueryGuildBankTab = function(tab) if mode ~= "reading" and not (mode == "partial" and tab == 3) then Answer() end end
    if mode ~= "setup" then
        local D = MI.Design
        local names = {}
        for i, t in pairs(TABS) do names[i] = { name = t.name, icon = t.icon } end
        local d = D.New(GUILD, names, 5)
        local ctx = { facts = function(id) return (MI.ItemFacts(id)) end }
        D.AssignTab(d, ctx, 2589, 2); D.AssignTab(d, ctx, 2592, 1); D.AssignTab(d, ctx, 2447, 1)
        local saved, why = D.Save(d)
        Check("state", "the synthetic arrangement saved", true, saved == true)
        if not saved then Lab.Say("save", tostring(why)) end
    end
    current = 2
    Event("GUILDBANKFRAME_OPENED")
    Event("GUILDBANKBAGSLOTS_CHANGED")
    local function Find(frame, pattern)
        for _, ch in ipairs({ frame:GetChildren() }) do
            if ch:IsShown() then
                if ch.text and ch.text.GetText and (ch.text:GetText() or ""):find(pattern) then return ch end
                local hit = Find(ch, pattern)
                if hit then return hit end
            end
        end
    end
    local panel = _G.TwichUIGuildBankPanel
    local function PanelClick(pattern)
        panel = _G.TwichUIGuildBankPanel
        local b = panel and Find(panel, pattern)
        Check("interact", "panel control " .. pattern .. " exists", true, b ~= nil)
        if b then b:Click() end
        Lab.Settle(0.4)
    end
    local function Texts()
        local out = {}
        local function Walk(f)
            for _, region in ipairs({ f:GetRegions() }) do
                if region.GetText and region:IsShown() and (region:GetText() or "") ~= "" then out[#out + 1] = region:GetText() end
            end
            for _, ch in ipairs({ f:GetChildren() }) do if ch:IsShown() then Walk(ch) end end
        end
        if panel then Walk(panel) end
        return out
    end
    if mode == "reading" then Lab.Settle(1.8)
    elseif mode == "partial" then Lab.Settle(30)
    else Lab.Settle(8) end
    panel = _G.TwichUIGuildBankPanel
    Check("state", "the panel exists and is shown with the bank", true, panel ~= nil and panel:IsShown())
    if mode == "review" or mode == "run" or mode == "blocked" or mode == "timeout" then
        local calls = {}
        if mode ~= "review" then
            local function Inert(name)
                return function() calls[#calls + 1] = name; if mode == "blocked" then Event("ADDON_ACTION_BLOCKED", R.ADDON, name) end end
            end
            PickupGuildBankItem, SplitGuildBankItem = Inert("PickupGuildBankItem"), Inert("SplitGuildBankItem")
            C_Container.PickupContainerItem, C_Container.SplitContainerItem = Inert("PickupContainerItem"), Inert("SplitContainerItem")
        end
        GetCursorInfo, CursorHasItem = function() return nil end, function() return false end
        PanelClick("^Deposit")
        Check("state", "Deposit made one review and nothing was called", true, MI.GuildPanel.Review() ~= nil and #calls == 0)
        if mode ~= "review" then
            PanelClick("^Start")
            Check("state", "Start began one run", true, MI.GuildRun.Busy())
            if mode == "timeout" then
                for _ = 1, 8 do Lab.Settle(2) end          -- two tries of 4 s with a pause between (GuildRun.TRIES), then it gives up
                local res = MI.GuildRun.Last()
                Check("state", "no answer in time: Needs review, and the move was handed to the game twice, no more", "review/2", (res and res.outcome or "?") .. "/" .. #calls)
                PanelClick("^Details")
            end
            if mode == "blocked" then
                local prog = MI.GuildRun.Progress()
                Check("state", "a refused call outside a click asks for a click", true, prog and prog.needClick == true)
            end
        end
    end
    -- Presentation-only fixtures (params.fixture): the panel's own drawing fed a made-up result or summary, because this lab cannot
    -- complete a run. They replace what GuildRun.Last / GuildPrep.Summary RETURN; nothing is executed and nothing moves.
    --   completed    "Completed", 58 of 58 stacks, eleven distinct items (the strip's overflow tile)
    --   partial      "Partially completed" with a long reason, an uncertain item, an unread tab and a cursor note
    --   unavailable  ready with Organize bank unavailable (nothing for it to do)
    --   short        a short summary: one stack ready, Organize bank unavailable
    -- params.details = true opens Details afterwards.
    if params.fixture then
        local GRM, GP = MI.GuildRun, MI.GuildPrep
        local icons = { "INV_Misc_Food_15", "INV_Drink_05", "INV_Misc_Herb_01", "INV_Scroll_03", "INV_Misc_Gem_01", "INV_Ore_Iron_01", "INV_Misc_Bone_01" }
        local extra = { 2453, 3355, 3818, 8153, 4234, 2776, 765 }
        for i, id in ipairs(extra) do
            ITEMS[id] = ITEMS[id] or { name = "Sample item " .. i, class = 7, sub = 5, stack = 20, icon = "Interface\\Icons\\" .. icons[i] }
        end
        local ids = { 6948, 2589, 4306, 2592, 2447, 2770, 2453, 3355, 3818, 8153, 4234 }
        local function Result(outcome, uncertainAt)
            local r = { outcome = outcome, confirmed = 58, total = 58, ops = {}, lines = {} }
            for i, id in ipairs(ids) do
                local n = i == 5 and 436 or (i == 6 and 208 or (i * 3 + 1))
                r.ops[#r.ops + 1] = { id = id, count = n, status = (uncertainAt and i == uncertainAt) and "uncertain" or "confirmed" }
                r.lines[#r.lines + 1] = ("%s x%d: tab 1 slot %d -> tab 2 slot %d: %s"):format(ITEMS[id].name, n, i, i + 10, (uncertainAt and i == uncertainAt) and "uncertain" or "confirmed")
            end
            return r
        end
        local fake
        if params.fixture == "completed" then fake = Result("completed")
        elseif params.fixture == "partial" then
            fake = Result("partial", 4)
            fake.confirmed, fake.total = 41, 58
            fake.reason = "the bank stopped answering after tab 2 changed while the run was waiting for it to settle"
            fake.unreadTabs = { 3, 5 }
            fake.cursor = { id = 2589, where = { kind = "bag", bag = 0, slot = 3 } }
        end
        if fake then GRM.Last = function() return fake end end
        if params.fixture == "unavailable" or params.fixture == "short" then
            local sum = params.fixture == "short" and { deposit = { moves = 1 }, organize = { code = "nothing" } }
                or { deposit = { moves = 3 }, organize = { code = "nothing" } }
            GP.Summary = function() return sum end
        end
        MI.GuildPanel.Refresh()
        Lab.Settle(0.4)
        if params.details then PanelClick("^Details") end
    end
    for _, t in ipairs(Texts()) do Lab.Say("panel", t) end
    local x1, y1, x2, y2 = panel:GetLeft(), panel:GetTop(), panel:GetRight(), panel:GetBottom()
    Lab.Say("placement", ("panel left=%s top=%s right=%s bottom=%s"):format(tostring(x1), tostring(y1), tostring(x2), tostring(y2)),
        ("bank left=%s top=%s right=%s bottom=%s"):format(tostring(host:GetLeft()), tostring(host:GetTop()), tostring(host:GetRight()), tostring(host:GetBottom())))
    Lab.Say("outside", tostring(y1 and host:GetBottom() and y1 <= host:GetBottom() + 0.5 or (y2 and host:GetTop() and y2 >= host:GetTop() - 0.5)))
    Lab.Finish()
    return
end

-- the bank is opened and the tabs are shown one after another: tab 3 and 5 are never shown (unread), 1 and 4 earlier
Event("GUILDBANKFRAME_OPENED")
ShowTab(1)
ShowTab(4)
ShowTab(2)
if params.bank == "closed" then Event("GUILDBANKFRAME_CLOSED") bankOpen = false else bankOpen = true end

-- ---------------------------------------------------------------- the real page
local ok, why = R:OpenSettings("magicInventory")
Lab.Say("open", ok, why)
Lab.Settle(2)
local P = R.MagicInventoryPage
Check("construct", "the page is there", true, P ~= nil and P.Frame() ~= nil)
Check("state", "opening the editor wrote no rule and no destination", true,
    #MI.Rules() == rulesBefore and #MI.Dests() == destsBefore and MI.Generation() == generationBefore)

local function Click(key, button)
    local c = P.Control(key)
    Check("interact", "control " .. key .. " exists", true, c ~= nil)
    if c then c:Click(button) end
    Lab.Settle(0.3)
end
local D = MI.Design
local function Draft() return P.GuildDraft() end
local function Stack(tab, slot) local d = Draft(); return d and d.tabs[tab] and d.tabs[tab].slots[slot] end
local function Drop(src, tab, slot) local r = P.ApplyDesign(src, tab, slot); Lab.Settle(0.2); return r end
-- "Pin to a slot": the item's menu, then a click on the slot (the page's armed click passes pin = true). A plain drop on a slot only
-- gives the tab the item: the addon decides where it goes.
local function Pin(src, tab, slot) local r = P.ApplyDesign(src, tab, slot, nil, true); Lab.Settle(0.2); return r end
local function Tray(id) return { kind = "tray", id = id } end
local function Slot(tab, slot) local s = Stack(tab, slot); return { kind = "slot", id = s and s.id, tab = tab, slot = slot, count = s and s.count } end
local function Action(src, label)
    for _, a in ipairs(P.ActionsFor(src, nil)) do if a.label:find(label, 1, true) then return a end end
end
-- Split stack: the item menu's own action, the dialog typed into and its Split button, then a click on the destination slot
local function SplitTo(tab, slot, qty, destSlot)
    Action(Slot(tab, slot), "Split stack").fn()
    Lab.Settle(0.2)
    local dlg = P.Split.Dialog()
    dlg.qty:SetText(tostring(qty))
    Lab.Settle(0.1)
    dlg.ok:Click()
    Lab.Settle(0.2)
    Click("gSlot" .. destSlot)
end
local function Totals(id)
    local n = 0
    for _, t in pairs(Draft().tabs) do for _, s in pairs(t.slots) do if s.id == id then n = n + s.count end end end
    return n
end

local stages = {}
for name in tostring(params.script or ""):gmatch("[%w]+") do stages[name] = true end
Click("gTab2")

if stages.assign then
    Check("interact", "Linen dropped on tab 2 is placed automatically", true, Drop(Tray(2589), 2, nil) and Draft().tabs[2].rest[2589] == true)
    Check("interact", "Silk dropped on slot 5 reserves a full stack of 200", 200, Pin(Tray(4306), 2, 5) and Stack(2, 5).count)
    Check("interact", "Linen dropped on slot 3 reserves a full stack", 20, Pin(Tray(2589), 2, 3) and Stack(2, 3).count)
    SplitTo(2, 3, 10, 10)
    Check("interact", "split 10 of 20 into slot 10: 10 and 10", "10/10", Stack(2, 3).count .. "/" .. (Stack(2, 10) and Stack(2, 10).count or 0))
    SplitTo(2, 3, 5, 4)
    Check("interact", "split 5 of 10 into slot 4: stacks of 5, 5 and 10 for one item", "5/5/10",
        Stack(2, 3).count .. "/" .. Stack(2, 4).count .. "/" .. Stack(2, 10).count)
    Check("state", "the Linen total is still 20", 20, Totals(2589))
end
if stages.layout then
    local cx = { facts = function(id) return (MI.ItemFacts(id)) end }
    Check("interact", "a plain drop on a slot gives the tab the item and pins nothing", true, Drop(Tray(2589), 2, 9) and next(Draft().tabs[2].slots) == nil)
    for _, id in ipairs({ 2592, 4306, 2447 }) do Drop(Tray(id), 2, nil) end
    Check("interact", "Linen in stacks of 5", true, D.SetSize(Draft(), cx, 2, 2589, 5))
    Check("interact", "Silk in stacks of 50", true, D.SetSize(Draft(), cx, 2, 4306, 50))
    Check("interact", "the tab's layout is chosen", true, D.SetLayout(Draft(), 2, params.layout or "spaced"))
    P.QueueRefresh()
    Lab.Settle(0.5)
    local drawn = {}
    for slot = 1, 98 do
        local b = P.Control("gSlot" .. slot)
        if b and b.autoId then drawn[#drawn + 1] = slot .. ":" .. b.autoId end
    end
    Lab.Say("layout", params.layout or "spaced", table.concat(drawn, " "))
    Check("state", "four items are drawn, none pinned", "4/0", #drawn .. "/" .. (next(Draft().tabs[2].slots) and 1 or 0))
end
if stages.cancel then
    local before = D.Digest(Draft())
    Action(Slot(2, 10), "Split stack").fn()
    Lab.Settle(0.2)
    local dlg = P.Split.Dialog()
    dlg.qty:SetText("4")
    Lab.Settle(0.1)
    dlg.ok:Click()
    Lab.Settle(0.2)
    Click("gCancelArm")
    Check("interact", "a split cancelled at the destination changes nothing", before, D.Digest(Draft()))
    Action(Slot(2, 10), "Split stack").fn()
    Lab.Settle(0.2)
    dlg:Hide()
    Lab.Settle(0.2)
    Check("interact", "a split dialog closed (as Esc does) changes nothing", before, D.Digest(Draft()))
end
if stages.merge then
    Pin(Tray(2447), 2, 20)
    local before = Totals(2447)
    SplitTo(2, 20, 5, 21)
    Check("interact", "Peacebloom split 15 and 5", "15/5", Stack(2, 20).count .. "/" .. Stack(2, 21).count)
    Check("interact", "slot 21 combined into slot 20", true, Drop(Slot(2, 21), 2, 20) and Stack(2, 20).count == 20 and Stack(2, 21) == nil)
    Check("state", "combining lost nothing", before, Totals(2447))
end
if stages.refuse then
    local before = D.Digest(Draft())
    Pin(Tray(2592), 2, 30)
    local mid = D.Digest(Draft())
    Check("interact", "Wool reserved in slot 30", true, Stack(2, 30) ~= nil and Stack(2, 30).id == 2592)
    Check("interact", "Wool can't be combined with Linen", false, Drop(Slot(2, 30), 2, 3))
    Check("state", "and the design is as it was before that attempt", mid, D.Digest(Draft()))
    Check("interact", "a split of 25 off a stack of 20 is refused", false, P.ApplyDesign(Slot(2, 30), 2, 31, 25))
    Check("state", "and the design is unchanged", mid, D.Digest(Draft()))
    local _ = before
end
if stages.menu then
    -- the item menu: a right-click on a reserved stack opens the shared menu list, anchored to the slot
    local Wg = R.SettingsWidgets
    Check("interact", "no menu is open before the click", false, Wg.MenuShown())
    Click("gSlot3", "RightButton")
    Lab.Say("menu", "shown=" .. tostring(Wg.MenuShown()))
    Check("interact", "a right-click on a reserved stack opens the item menu", true, Wg.MenuShown())
    Wg.CloseMenu()
    Check("state", "the menu changed nothing in the design", true, Stack(2, 3) ~= nil)
end
if stages.short then
    Pin(Tray(4306), 2, 6)
    Pin(Tray(4306), 2, 7)
end
if stages.conflict then
    Pin(Tray(2589), 2, 40)
end
if stages.save then
    local digest = D.Digest(Draft())
    Click("gSave")
    Check("state", "Save arrangement wrote rules", true, #MI.Rules() > rulesBefore)
    P.Frame():Hide()
    Lab.Settle(0.2)
    P.Frame():Show()
    Lab.Settle(0.5)
    Check("state", "reopened: the draft equals what was saved", digest, D.Digest(Draft()))
    Check("state", "and nothing is unsaved", false, D.Dirty(Draft()))
end

-- ---------------------------------------------------------------- the run stages (an inert game, see the header)
local calls = {}
if stages.review or stages.run or stages.timeout or stages.blocked then
    local function Inert(name)
        return function(...)
            calls[#calls + 1] = name
            if stages.blocked then Event("ADDON_ACTION_BLOCKED", R.ADDON, name) end
        end
    end
    PickupGuildBankItem, SplitGuildBankItem = Inert("PickupGuildBankItem"), Inert("SplitGuildBankItem")
    C_Container.PickupContainerItem, C_Container.SplitContainerItem = Inert("PickupContainerItem"), Inert("SplitContainerItem")
    GetCursorInfo, CursorHasItem = function() return nil end, function() return false end
    Click("gVPre")
    Click("gPreview")
    Click("gRunAct")
    local rv = P.Control("gRevGo")
    Check("interact", "Deposit... opens a review with Start, and nothing was called", true, rv ~= nil and #calls == 0)
    if stages.run or stages.timeout or stages.blocked then
        local GR = MI.GuildRun
        Click("gRevGo")
        Check("interact", "Start begins one run", true, GR.Busy())
        local prog = GR.Progress()
        Lab.Say("run", "confirmed=" .. tostring(prog and prog.confirmed), "total=" .. tostring(prog and prog.total), "waiting=" .. tostring(prog and prog.waiting), "needClick=" .. tostring(prog and prog.needClick), "calls=" .. #calls)
        Check("state", "nothing is counted as confirmed while the game says nothing", 0, prog and prog.confirmed or -1)
        if stages.timeout then
            for _ = 1, 8 do Lab.Settle(2) end          -- two tries of 4 s with a pause between (GuildRun.TRIES)
            local res = GR.Last()
            Check("state", "no answer in time: Needs review, not a success", "review", res and res.outcome)
            Check("state", "and the move was handed to the game twice, no more", 2, #calls)
            Lab.Say("result", res and res.outcome, res and res.code, "uncertain=" .. tostring(res and res.uncertain))
        end
        if stages.blocked then
            Check("state", "a refused call outside a click pauses the run and asks for a click", true, prog and prog.needClick == true)
        end
    end
end

local view = params.view or "design"
if params.tab then Click("gTab" .. params.tab) end
if (view == "preview" and not (stages.review or stages.run or stages.timeout or stages.blocked)) or stages.stale then
    Click("gPreview")
    if params.source == "bank" then Click("gSrcBank") end
end
if stages.stale then
    Pin(Tray(2592), 2, 60)
    Lab.Say("stale", "design changed after the preview")
    Click("gVPre")
    if params.stale == "bank" then
        TABS[2].slots[7] = { 2447, 3 }
        ShowTab(2)
        local host = P.Frame()
        host:GetScript("OnEvent")(host, "GUILDBANKBAGSLOTS_CHANGED")   -- the page's own frame hears the game's event too
        Lab.Settle(0.5)
    end
end
if view == "current" then Click("gVCur") elseif view == "design" and not stages.stale and not (stages.review or stages.run or stages.timeout or stages.blocked) then Click("gVDes") end
if params.details then Click("gDetails") end

local plan, mode = P.GuildPreview()
local draft = Draft()
Lab.Say("state", "view=" .. tostring(P.GuildView()), "mode=" .. tostring(mode), "dirty=" .. tostring(D.Dirty(draft)), "rules=" .. #MI.Rules() .. "(was " .. rulesBefore .. ")")
if plan then
    local s = plan.summary
    Lab.Say("plan", "draft=" .. tostring(plan.draft), "ops=" .. s.ops, "splits=" .. s.splits, "blockedOps=" .. s.blockedOps, "freshness=" .. tostring(plan.freshness), "readOnly=" .. tostring(plan.readOnly))
    local d = s.design
    Lab.Say("design", "reserved=" .. d.reserved, "filled=" .. d.filled, "short=" .. d.short, "shortQty=" .. d.shortQty, "blocked=" .. d.blocked,
        "extrasPlaced=" .. d.extrasPlaced, "extrasLeft=" .. d.extrasLeft, "conflicts=" .. d.conflicts)
    for _, a in ipairs(plan.design.allocs) do Lab.Say("alloc", "tab" .. a.tab, "slot" .. a.slot, "id" .. a.id, a.state, a.have .. "/" .. a.want) end
    for _, c in ipairs(plan.design.conflicts) do Lab.Say("conflict", c.kind, "item" .. c.id, c.rule, "<-", c.by) end
end
Lab.Say("page", "tabs=" .. tostring(draft and draft.numTabs), "advanced=" .. tostring(draft and #draft.advanced))

Lab.Settle(1)
-- scroll the settings window to the editor so the screenshot shows it: the scroll frame is the page host's ancestor
local win = R.SettingsUI.Frame()
local host = P.Frame()
local scroll = host:GetParent()
while scroll and scroll:GetObjectType() ~= "ScrollFrame" do scroll = scroll:GetParent() end
if scroll and host:GetTop() and scroll:GetScrollChild():GetTop() then
    local focus = P.Control(params.focus or ((stages.review or stages.run or stages.timeout or stages.blocked) and "gRunTitle" or "gVDes"))
    local offset = scroll:GetScrollChild():GetTop() - ((focus and focus:GetTop()) or host:GetTop())
    scroll:SetVerticalScroll(math.max(0, offset - 6 + (params.scroll or 0)))
    Lab.Say("scroll", "host offset=" .. tostring(offset), "applied=" .. tostring(scroll:GetVerticalScroll()), "range=" .. tostring(scroll:GetVerticalScrollRange()))
else
    Lab.Say("scroll", "no scroll frame found above the page")
end
Lab.Settle(0.5)
Lab.Say("window", "size=" .. tostring(win:GetWidth()) .. "x" .. tostring(win:GetHeight()), "pageHeight=" .. tostring(P.Height()), "pageWidth=" .. tostring(host:GetWidth()))
Lab.Say("controls", tostring(P.ControlCount()))
Lab.Finish()
