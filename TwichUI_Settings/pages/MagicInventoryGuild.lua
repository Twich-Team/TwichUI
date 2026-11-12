-- TwichUI settings: Magic Inventory, the guild bank arrangement editor (inventory/Design.lua, inventory/GuildPlan.lua), drawn in
-- the page's frame.
--
-- ONE guild bank, as the game draws it: the tabs' own names and icons across the top, one slot grid (7 columns of 14) for the
-- selected tab, and a switch for what the grid shows:
--   Current   what the guild bank held when it was last read (observed; a tab never shown is "not read", never empty)
--   Design    the arrangement being edited: reserved stacks (this item, this many, in this slot). Drag an item from the tray onto
--             a tab (placed automatically) or onto a slot (reserved); drag a reserved stack to another slot or tab; Shift-click
--             a stack, or use its menu, to split it; Save arrangement turns the draft into guild bank rules
--   Preview   where the saved (or draft) rules would put things, from your bags or from what is already in the bank
-- Editing is design only: dragging, splitting and placing here never moves, picks up, splits, deposits or withdraws an item,
-- switches a tab or touches the game's cursor (every drag is virtual, MagicInventoryDrag.lua). The draft is kept in memory
-- until Save arrangement or Revert; leaving the page neither saves nor discards it. Opening the editor writes nothing.
-- Items move only from the Preview: Deposit or Organize bank is reviewed, confirmed here, and carried out by
-- inventory/GuildRun.lua, which works from the SAVED arrangement across every tab it can read (the guild bank's own panel,
-- inventory/GuildPanel.lua, offers the same two actions beside the bank window). While it runs, the editor,
-- Save and the preview buttons are off.
-- Controls are kept by name and reused on every redraw (MagicInventory.lua's pool).

local R = TwichUI
local P = R.MagicInventoryPage
local Kit = P.Kit
local Get, Text, Button, At, Wide, Tone, H = Kit.Get, Kit.Text, Kit.Button, Kit.At, Kit.Wide, Kit.Tone, Kit.H
local W, PAD = Kit.W, Kit.PAD

local function MI() return R.MagicInventory end
local function Wg() return R.SettingsWidgets end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local CELL, STEP = 28, 30                -- a slot and the distance between slots
local COLS, ROWS = 7, 14                 -- the game's guild bank grid (98 slots a tab)
local GRID_W, GRID_H = COLS * STEP - (STEP - CELL), ROWS * STEP - (STEP - CELL)
local TRAY_MAX = 24
local AMBER = { 0.93, 0.72, 0.38 }
local TEAL = { 0.36, 0.78, 0.74 }

local view = "design"                    -- "current" | "design" | "preview"
local selTab = 1
local source = "bags"                    -- the preview's source: "bags" | "bank"
local draft                              -- the arrangement being edited (Design.lua), nil until built
local plan, planMode, planDigest, planRev, planDraft   -- the retained preview, its mode, and what it was made from
local designRev = 0                      -- counts edits, so a preview knows the design changed after it was made
local bagsChanged, knownDirty = false, true
local picked                             -- the item selected: { kind = "tray" | "shelf" | "slot", id, tab, slot, count }
local armed                              -- waiting for a destination: { op = "move" | "split", src, qty }
local msg, msgTone                       -- the one contextual line
local review                             -- the reviewed plan waiting for the player's confirmation (GuildRun.Review)
local runStale = false                   -- a run started or ended since the preview was made: the preview no longer describes the bank
local details = false                    -- the Details disclosure
local search = ""                        -- the tray's filter text
local known, knownByName                 -- the item references of the tray
local slotButtons, tabButtons, hoverTarget = {}, {}, nil

local MARK = {
    added   = { glyph = "+", color = { 0.55, 0.78, 0.52 }, word = "New stack" },
    changed = { glyph = "*", color = AMBER, word = "Stack changes" },
    leaves  = { glyph = "-", color = { 0.85, 0.50, 0.42 }, word = "Leaves this slot" },
    blocked = { glyph = "!", color = { 0.95, 0.55, 0.25 }, word = "Blocked" },
    unknown = { glyph = "?", color = { 0.62, 0.66, 0.90 }, word = "Can't tell" },
    short   = { glyph = "~", color = { 0.90, 0.80, 0.45 }, word = "Short of its target" },
    reserved = { glyph = "R", color = TEAL, word = "Reserved slot" },
    active  = { glyph = "\226\128\166", color = AMBER, word = "In progress" },
    done    = { glyph = "=", color = { 0.55, 0.78, 0.52 }, word = "Confirmed" },
}
local OUTCOME = { completed = "Completed", partial = "Partially completed", stopped = "Stopped", review = "Needs review" }
local LEGEND = "R reserved slot    A placed automatically    + new stack    * stack changes    - leaves    ~ short of its target    ! blocked    ? can't tell    \226\128\166 in progress    = confirmed"

local function Plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or (many or one .. "s")) end

local function Say(text, tone) msg, msgTone = text, tone; P.QueueRefresh() end
local function Touch() designRev = designRev + 1; P.QueueRefresh() end
local function RunBusy() local g = MI().GuildRun; return g ~= nil and g.Busy() end
-- editing, saving and previewing are paused while a run is going
local function Locked()
    if not RunBusy() then return false end
    Say("A guild bank run is in progress. Editing and previews resume when it ends.", "warn")
    return true
end
local function Unless(busy, fn) if busy then return nil end return fn end
local RUN = { Busy = RunBusy, Locked = Locked, Unless = Unless }   -- one upvalue for the big draw function (Lua allows 60)

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function Facts(id) return (MI().ItemFacts(id)) end
local function ItemName(id)
    local f = id and Facts(id)
    return f and f.name or (id and ("item " .. id) or "an unidentified item")
end
local function IconOfId(id, hint)
    local f = id and Facts(id)
    return hint or (f and f.icon) or QUESTION
end
local function Ctx() return { facts = Facts } end

-- Every item the tray offers: what the bags and the guild bank snapshot hold, and what the draft already names. References
-- only: nothing says the player has any of it now. Rebuilt only when something it reads changed.
local function Known()
    if known and not knownDirty then return known end
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.designTray")
    local mi = MI()
    local byId, list = {}, {}
    local function Add(id, count, where)
        if not mi.ValidID(id) then return end
        local e = byId[id]
        if not e then e = { id = id, bags = 0, bank = 0 }; byId[id] = e; list[#list + 1] = e end
        if where then e[where] = e[where] + (count or 0) end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, mi.LastBag and mi.LastBag() or 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local id = info and mi.Plain(info.itemID)
                if type(id) == "number" then Add(id, mi.Plain(info.stackCount), "bags") end
            end
        end
    end
    local snap = mi.GuildBank and mi.GuildBank.Snapshot()
    for _, t in pairs(snap and snap.tabs or {}) do
        for _, c in pairs(t.slots or {}) do if c.id then Add(c.id, c.count, "bank") end end
    end
    for _, t in pairs(draft and draft.tabs or {}) do
        for id in pairs(t.items) do Add(id) end
    end
    for _, e in ipairs(list) do e.name = ItemName(e.id) end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    known, knownDirty = list, false
    if pt then R.Perf.Stop(pt) end
    return list
end

local function TrayList()
    local out, total = {}, 0
    local q = (search or ""):lower()
    for _, e in ipairs(Known()) do
        if q == "" or e.name:lower():find(q, 1, true) or tostring(e.id) == q then
            total = total + 1
            if #out < TRAY_MAX then out[#out + 1] = e end
        end
    end
    return out, total
end

---------------------------------------------------------------------------
-- The draft
---------------------------------------------------------------------------
-- The guild's tabs as far as they are known: names and icons from the bank when it has been read, else as last seen.
local function TabNames(guild)
    local mi = MI()
    local names, num = {}, nil
    for i, t in pairs(mi.GuildTabsSeen(guild)) do names[i] = { name = t.name, icon = t.icon }; num = math.max(num or 0, i) end
    local snap = mi.GuildBank.Snapshot()
    if snap.guild == guild then
        for i = 1, snap.numTabs or 0 do
            local t = snap.tabs[i]
            if t and t.name then names[i] = { name = t.name, icon = t.icon } end
        end
        if snap.numTabs and snap.numTabs > 0 then num = snap.numTabs end
    end
    return names, num
end

local function GuildNow()
    local g = MI().Design.GuildNow()
    if g then return g end
    local snap = MI().GuildBank.Snapshot()
    return snap.guild
end

local function Dirty() return draft ~= nil and MI().Design.Dirty(draft) end

local function Open(guild)
    local mi = MI()
    local names, num = TabNames(guild)
    draft = mi.Design.Load(mi.Rules(), { guild = guild, names = names, numTabs = num, resolve = mi.Resolve, facts = Facts })
    picked, armed = nil, nil
end

-- The draft for this guild: made when first needed, kept while it has unsaved edits (a change of guild, profile or rules
-- elsewhere never throws edits away), rebuilt from the saved rules when it has none.
local function EnsureDraft()
    local guild = GuildNow()
    if not guild then return nil end
    if draft and draft.guild == guild then
        if not Dirty() and draft.rulesGen ~= MI().Generation() then Open(guild); draft.rulesGen = MI().Generation() end
        return draft
    end
    if draft and Dirty() then return draft end
    Open(guild)
    draft.rulesGen = MI().Generation()
    return draft
end

-- Names, icons and the tab count move on as the bank is read (a draft's tab names are those it was opened with)
local function RefreshNames()
    if not draft then return end
    local names, num = TabNames(draft.guild)
    for i, t in pairs(names) do draft.names[i] = t end
    if num then draft.numTabs = num end
end

---------------------------------------------------------------------------
-- The preview
---------------------------------------------------------------------------
local function StaleReasons()
    local out = {}
    if not plan then return out end
    local mi = MI()
    if plan.generation ~= mi.Generation() then out[#out + 1] = "your rules or destinations changed" end
    if plan.seq ~= mi.GuildBank.Seq() then out[#out + 1] = "the guild bank was read again" end
    if planMode == "deposit" and bagsChanged then out[#out + 1] = "your bags changed" end
    if plan.open and not mi.GuildBank.IsOpen() then out[#out + 1] = "the guild bank was closed" end
    if draft and planDigest ~= mi.Design.Digest(draft) then out[#out + 1] = "your design changed" end
    if runStale then out[#out + 1] = "a guild bank run started or ended since" end
    return out
end

local function Build()
    if Locked() then return end
    local mi = MI()
    local mode = source == "bags" and "deposit" or "reorganize"
    local override
    if draft and mi.Design.Dirty(draft) then
        local rules, virtual = mi.Design.PreviewRules(draft, mi.Rules())
        override = { rules = rules, virtual = virtual }
    end
    local ok, res = pcall(mi.CurrentGuildPlan, mode, override)
    if not ok then
        R.Fault("magic inventory guild preview", res)
        Say("The preview couldn't be made.", "warn")
        return
    end
    review, runStale = nil, false
    plan, planMode, bagsChanged = res, mode, false
    planDigest, planDraft = draft and mi.Design.Digest(draft) or "", override ~= nil
    view = "preview"
    Say(nil)
end

function P.GuildPreview() return plan, planMode end
function P.GuildDraft() return draft end
function P.GuildView() return view end

-- A review waiting for confirmation is withdrawn when what it was made from may have changed (the confirmation itself is
-- checked again against the game when it is pressed, so this only keeps the screen honest).
local function Withdraw()
    if not review then return end
    review = nil
    Say("Your bags, the bank or your rules changed, so that review was withdrawn. Review again.", "warn")
end

function P.OnEvent(event)
    if event ~= "GET_ITEM_INFO_RECEIVED" then Withdraw() end
    if event == "BAG_UPDATE_DELAYED" then
        knownDirty = true
        if plan and planMode == "deposit" then bagsChanged = true end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" or event == "GUILDBANKFRAME_OPENED" then
        knownDirty = true
        RefreshNames()
    elseif event == "GUILDBANK_UPDATE_TABS" then
        RefreshNames()
    end
end

-- What the guild bank reader knows right now, in one line (for Details, the tests and the simulator scenario)
function P.BankStateText()
    local snap = MI().GuildBank.Snapshot()
    if not snap.open then return "Guild bank: closed (open it, then show each tab you want included)." end
    local read, unread = {}, {}
    for i = 1, snap.numTabs or 0 do
        local t = snap.tabs[i]
        if t and t.slots then read[#read + 1] = i
        elseif t and t.viewable ~= false then unread[#unread + 1] = i end
    end
    return ("Guild bank: open%s \194\183 items read for %s \194\183 not read: %s."):format(
        snap.current and (", showing tab " .. snap.current) or "", #read > 0 and ("tab " .. table.concat(read, ", ")) or "no tab yet",
        #unread > 0 and table.concat(unread, ", ") or "none")
end

---------------------------------------------------------------------------
-- Words about a slot or a tab
---------------------------------------------------------------------------
local AGE = function(seconds)
    if not seconds then return nil end
    if seconds < 90 then return ("%d s ago"):format(math.floor(seconds)) end
    return ("%d min ago"):format(math.floor(seconds / 60))
end

local function TabState(t)
    if not t or not t.slots then return "not read" end
    if t.state == "live" then return "live" end
    if t.state == "earlier" then return "read earlier" .. (t.age and (", " .. AGE(t.age)) or "") .. ", may have changed" end
    if t.state == "closed" then return "read when the guild bank was last open" end
    return t.state or "?"
end

local function RightsText(t)
    local function Yes(v) return v == nil and "not known" or (v and "yes" or "no") end
    if not t then return "" end
    return ("Can see: %s \194\183 deposit: %s \194\183 take out: %s"):format(Yes(t.viewable), Yes(t.canDeposit), Yes(t.canWithdraw))
end

local function ExtrasText(id, tab)
    local at, n = nil, 0
    for i, t in pairs(draft.tabs) do
        if t.rest[id] then at = i end
        if t.items[id] then n = n + 1 end
    end
    if at == tab then return ("Extra %s goes to the free slots of this tab."):format(ItemName(id)) end
    if at then return ("Extra %s goes to tab %d."):format(ItemName(id), at) end
    if n == 1 then return ("Extra %s goes to the free slots of this tab."):format(ItemName(id)) end
    return ("Extra %s has no tab to go to: choose one with \"Extras go here\"."):format(ItemName(id))
end

-- What to tell about one slot in the plan (hover and detail)
local function PlanLines(tab, slot)
    local pv = plan and plan.tabs[tab]
    local cell = pv and pv.proposed and pv.proposed[slot]
    local was = pv and pv.current and pv.current[slot]
    local lines = { ("Tab %d, slot %d"):format(tab, slot) }
    if not cell and not was then lines[#lines + 1] = "Empty" return lines end
    local c = cell or was
    local name = c.id and ItemName(c.id) or "An item the game didn't identify"
    if cell and cell.ghost then
        lines[#lines + 1] = ("%s: reserved, none of it here yet"):format(name)
    else
        lines[#lines + 1] = ("%s%s"):format(name, c.count and (" \195\151" .. c.count) or " (count not known)")
    end
    if cell and cell.reserved then
        lines[#lines + 1] = ("Reserved for %d%s"):format(cell.want or 0, cell.short and (" \226\128\148 %d short"):format(cell.short) or "")
    end
    if cell and cell.change == "added" and not cell.ghost then lines[#lines + 1] = "New stack: nothing is there now"
    elseif cell and cell.change == "changed" then lines[#lines + 1] = ("The stack changes from %d to %d"):format(cell.was or 0, cell.count or 0)
    elseif not cell and was and was.change == "leaves" then lines[#lines + 1] = "This stack leaves the slot" end
    local blocked = (cell and cell.blocked) or (was and was.blocked)
    local unknown = (cell and cell.unknown) or (was and was.unknown)
    if blocked then lines[#lines + 1] = (unknown and "Can't tell: " or "Blocked: ") .. blocked end
    for _, w in ipairs((cell and cell.why) or (was and was.why) or {}) do
        if w ~= blocked then lines[#lines + 1] = "\226\128\162 " .. w end
    end
    return lines
end

local function SnapCell(tab, slot)
    local t = MI().GuildBank.Snapshot().tabs[tab]
    return t and t.slots and t.slots[slot], t
end

local function Tip(owner, lines, link)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if link and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(" ")
        for i = 1, #lines do GameTooltip:AddLine(lines[i], AMBER[1], AMBER[2], AMBER[3], true) end
    else
        GameTooltip:AddLine(lines[1], 1, 1, 1)
        for i = 2, #lines do GameTooltip:AddLine(lines[i], AMBER[1], AMBER[2], AMBER[3], true) end
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Editing: one place applies a drop, a menu choice or an armed click
---------------------------------------------------------------------------
-- pin: the player chose "pin to a slot" (an armed click) for an item from the tray or the tab's list. A plain drop on a slot does not
-- pin it: the tab takes the item, and the addon decides the slots (stack size and layout).
local function Apply(src, tab, slot, qty, pin)
    local D, cx = MI().Design, Ctx()
    local ok, text
    if src.kind == "slot" then
        if qty then ok, text = D.Split(draft, cx, src.tab, src.slot, qty, tab, slot)
        elseif slot then ok, text = D.MoveStack(draft, cx, src.tab, src.slot, tab, slot)
        else ok, text = D.MoveToTab(draft, cx, src.tab, src.slot, tab) end
    elseif slot and pin then ok, text = D.PlaceSlot(draft, cx, src.id, tab, slot)
    else ok, text = D.AssignTab(draft, cx, src.id, tab) end
    armed = nil
    if ok then picked = nil end
    msg, msgTone = ok and text or ("Nothing changed. " .. text), (not ok) and "warn" or nil
    Touch()
    return ok
end
P.ApplyDesign = Apply

local function Arm(op, src, qty)
    armed, picked = { op = op, src = src, qty = qty }, src
    if op == "split" then Say(("Where should the %d go? Click a slot, or a tab for its first free slot."):format(qty))
    elseif src.kind == "slot" then Say("Click the slot or tab to move it to.")
    else Say("Click a slot to reserve it, or a tab to place it automatically.") end
end

local function OpenSplit(src, anchor)
    if not (draft and src and src.kind == "slot") then return end
    local s = draft.tabs[src.tab] and draft.tabs[src.tab].slots[src.slot]
    if not s then return end
    if s.count < 2 then Say("A stack of one can't be split.", "warn") return end
    P.Split.Open({ id = s.id, name = ItemName(s.id), icon = IconOfId(s.id), count = s.count, anchor = anchor,
        onConfirm = function(qty) Arm("split", src, qty) end })
end

local function SizeText(src)
    local t = draft and draft.tabs[src.tab]
    local n = t and t.sizes[src.id]
    return n and (" \194\183 stacks of %d"):format(n) or " \194\183 full stacks"
end

-- The size an automatically placed item is spread in: a small dialog with the item's own limit as the most.
local function OpenSize(src, anchor)
    if not (draft and src and src.kind == "shelf") then return end
    local D, cx = MI().Design, Ctx()
    local f = cx.facts and cx.facts(src.id)
    local limit = f and f.maxStack
    if not limit then Say("The game is still loading this item. Try again in a moment.", "warn") return end
    if limit < 2 then Say("This item doesn't stack.", "warn") return end
    local t = draft.tabs[src.tab]
    P.Split.Open({ size = true, limit = limit, current = t and t.sizes[src.id] or limit, id = src.id, name = ItemName(src.id), icon = IconOfId(src.id), anchor = anchor,
        onConfirm = function(n)
            local ok, text = D.SetSize(draft, cx, src.tab, src.id, n)
            Say(ok and text or ("Nothing changed. " .. text), (not ok) and "warn" or nil)
            Touch()
        end })
end

-- The things that can be done with a selected item: the panel's buttons and the item menu are the same list.
local function ActionsFor(src, anchor)
    local D, cx = MI().Design, Ctx()
    local out = {}
    local function Add(label, tip, fn) out[#out + 1] = { label = label, tip = tip, fn = fn } end
    if src.kind == "slot" then
        local s = draft.tabs[src.tab] and draft.tabs[src.tab].slots[src.slot]
        if not s then return out end
        if s.count > 1 then Add("Split stack", "Choose a quantity, then where the new stack goes. The first keeps the rest.", function() OpenSplit(src, anchor) end) end
        Add("Move\226\128\166", "Then click the slot or tab to move it to.", function() Arm("move", src) end)
        Add("Return to automatic placement", "Gives up the reserved slot and quantity. Its tab then places the item in any free slot.", function()
            local ok, text = D.Unreserve(draft, cx, src.tab, src.slot)
            picked = nil
            Say(ok and text or ("Nothing changed. " .. text), (not ok) and "warn" or nil)
            Touch()
        end)
        if not draft.tabs[src.tab].rest[s.id] then
            Add("Extras go here", "Items beyond the reserved stacks are placed in this tab's free slots.", function()
                local ok, text = D.SetExtras(draft, cx, src.tab, s.id)
                Say(text, (not ok) and "warn" or nil)
                Touch()
            end)
        end
        Add("Remove from design", "Takes this reserved stack out. The item is left alone if no tab takes it.", function()
            local ok, text = D.RemoveStack(draft, cx, src.tab, src.slot)
            picked = nil
            Say(text, (not ok) and "warn" or nil)
            Touch()
        end)
    elseif src.kind == "shelf" then
        Add("Stack size\226\128\166", "Choose the size this item is spread in. Without one it is spread in full stacks.", function() OpenSize(src, anchor) end)
        Add("Pin to a slot\226\128\166", "Then click the slot to reserve a full stack in exactly that slot. Usually the layout is better left to the addon.", function() Arm("move", src) end)
        Add("Take out of this tab", "The item is left alone by this design.", function()
            local ok, text = D.RemoveItem(draft, cx, src.tab, src.id)
            picked = nil
            Say(text, (not ok) and "warn" or nil)
            Touch()
        end)
    else
        Add("Place\226\128\166", "Then click a slot to reserve it, or a tab to place the item automatically.", function() Arm("move", src) end)
    end
    return out
end

P.ActionsFor = ActionsFor   -- for the tests: the same list the item menu shows

---------------------------------------------------------------------------
-- Dragging (virtual)
---------------------------------------------------------------------------
local function TargetUnderPointer()
    for i, b in pairs(tabButtons) do
        if b:IsShown() and b:IsMouseOver() then return { tab = i } end
    end
    if view == "design" then
        for s, b in pairs(slotButtons) do
            if b:IsShown() and b:IsMouseOver() then return { tab = selTab, slot = s } end
        end
    end
    return nil
end

local function Highlight(target)
    if hoverTarget == target or (hoverTarget and target and hoverTarget.tab == target.tab and hoverTarget.slot == target.slot) then return end
    hoverTarget = target
    P.QueueRefresh()
end

local function StartDrag(src, icon, count)
    if view ~= "design" or not draft then return end
    if GetCursorInfo and GetCursorInfo() then
        Say("You are holding an item. Put it down first; nothing was changed.", "warn")
        return
    end
    picked, armed = src, nil
    P.Drag.Start({
        src = src, icon = icon, count = count,
        find = TargetUnderPointer, hover = Highlight,
        drop = function(s, target) Apply(s, target.tab, target.slot) end,
        cancel = function() Say("Nothing changed.") end,
    })
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local menuOwner
local function OpenItemMenu(src, anchor)
    local actions = ActionsFor(src, anchor)
    if #actions == 0 then return end
    local Wgt = Wg()
    local o = Get("gMenuOwner", function()
        local d = Wgt.Dropdown(Kit.Frame(), 120, function(value)
            local a = menuOwner and menuOwner.actions[value]
            if a then a.fn() end
        end)
        d:SetAlpha(0)
        d:EnableMouse(false)
        return d
    end)
    menuOwner = o
    o.actions = actions
    o:SetChoices(function()
        local list = {}
        for i, a in ipairs(actions) do list[i] = { value = i, label = a.label, tooltip = a.tip } end
        return list
    end)
    o:SetValue(nil, "")
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    o:SetWidth(CELL)
    o:EnableMouse(true)
    o:Click()
    o:EnableMouse(false)
end

local function SlotButton(s)
    local key = "gSlot" .. s
    return Get(key, function()
        local b = CreateFrame("Button", nil, Kit.Frame(), "BackdropTemplate")
        b:SetSize(CELL, CELL)
        Wg().Well(b)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.badge = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.badge:SetSize(12, 12)
        b.badge:SetPoint("TOPLEFT", 1, -1)
        b.mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.mark:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
        b.mark:SetDrawLayer("OVERLAY", 2)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b.slot = s
        slotButtons[s] = b
        b:SetScript("OnClick", function(self, button) P.SlotClick(self, button) end)
        b:SetScript("OnDragStart", function(self)
            local st = self.stack
            if view == "design" and st then StartDrag({ kind = "slot", id = st.id, tab = selTab, slot = self.slot, count = st.count }, IconOfId(st.id), st.count) end
        end)
        b:SetScript("OnDragStop", function() P.Drag.Stop() end)
        b:SetScript("OnEnter", function(self) P.SlotTip(self) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end)
end

-- shift-click on a stack opens the split dialog, as the game's own slots do (IsModifiedClick("SPLITSTACK"), default Shift)
local function SplitClick()
    if IsModifiedClick then return IsModifiedClick("SPLITSTACK") end
    return IsShiftKeyDown and IsShiftKeyDown()
end

function P.SlotClick(b, button)
    if view ~= "design" then
        picked = { kind = "cell", tab = selTab, slot = b.slot }
        P.QueueRefresh()
        return
    end
    local st = b.stack
    if armed then Apply(armed.src, selTab, b.slot, armed.op == "split" and armed.qty or nil, true) return end
    if not st and b.autoId then
        -- an automatically placed item drawn by the layout: select it like the item in the tab's list
        local src = { kind = "shelf", id = b.autoId, tab = selTab }
        picked = src
        if button == "RightButton" then OpenItemMenu(src, b) end
        P.QueueRefresh()
        return
    end
    if not st then picked = nil; P.QueueRefresh() return end
    local src = { kind = "slot", id = st.id, tab = selTab, slot = b.slot, count = st.count }
    if button == "RightButton" then picked = src; OpenItemMenu(src, b) P.QueueRefresh() return end
    if SplitClick() and st.count > 1 then picked = src; OpenSplit(src, b) P.QueueRefresh() return end
    picked = src
    P.QueueRefresh()
end

function P.SlotTip(b)
    if view == "design" then
        if not draft then return end
        local st = b.stack
        if st then
            local lines = { ("Tab %d, slot %d: reserved"):format(selTab, b.slot), ("%s \195\151%d is the target for this slot."):format(ItemName(st.id), st.count), ExtrasText(st.id, selTab),
                "Drag to move it. Shift-click or right-click to split it." }
            local f = Facts(st.id)
            Tip(b, lines, f and f.link)
        else
            Tip(b, { ("Tab %d, slot %d"):format(selTab, b.slot), "Not reserved. Drop an item here to reserve this slot for it." })
        end
    elseif view == "preview" then
        if plan then
            local cell = plan.tabs[selTab] and plan.tabs[selTab].proposed and plan.tabs[selTab].proposed[b.slot]
            local f = cell and cell.id and not cell.ghost and Facts(cell.id)
            Tip(b, PlanLines(selTab, b.slot), f and f.link)
        end
    else
        local cell = SnapCell(selTab, b.slot)
        if cell then
            local lines = { ("Tab %d, slot %d (as last read)"):format(selTab, b.slot), ("%s%s"):format(cell.id and ItemName(cell.id) or "An item the game didn't identify", cell.count and (" \195\151" .. cell.count) or "") }
            Tip(b, lines, cell.link)
        else
            Tip(b, { ("Tab %d, slot %d"):format(selTab, b.slot), "Empty as last read" })
        end
    end
end

-- an item square: tray and shelf
local function ItemButton(key)
    return Get(key, function()
        local b = CreateFrame("Button", nil, Kit.Frame(), "BackdropTemplate")
        b:SetSize(CELL, CELL)
        Wg().Well(b)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.badge = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.badge:SetSize(12, 12)
        b.badge:SetPoint("TOPLEFT", 1, -1)
        b.mark = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.mark:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
        b.mark:SetDrawLayer("OVERLAY", 2)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self, button)
            if armed and armed.src.kind == self.src.kind and armed.src.id == self.src.id and armed.src.tab == self.src.tab then
                armed, picked = nil, nil
                Say(nil)
                return
            end
            armed, picked = nil, self.src
            if button == "RightButton" then OpenItemMenu(self.src, self) end
            P.QueueRefresh()
        end)
        b:SetScript("OnDragStart", function(self) StartDrag(self.src, IconOfId(self.src.id), nil) end)
        b:SetScript("OnDragStop", function() P.Drag.Stop() end)
        b:SetScript("OnEnter", function(self)
            local src = self.src
            if not src then return end
            local lines = { ItemName(src.id) }
            if self.held then lines[#lines + 1] = self.held end
            if src.kind == "shelf" then lines[#lines + 1] = ExtrasText(src.id, src.tab)
            else lines[#lines + 1] = "Drag it onto a tab (placed automatically) or onto a slot (reserved)." end
            local f = Facts(src.id)
            Tip(self, lines, f and f.link)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end)
end

local function PaintItemButton(b, src, held)
    local pal = Wg().pal
    b.src, b.held = src, held
    b.tex:SetTexture(IconOfId(src.id))
    local on = picked and picked.kind == src.kind and picked.id == src.id and picked.tab == src.tab
    local edge = on and pal.tealHi or pal.bronzeLo
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], on and 1 or 0.9)
    if src.kind == "shelf" then
        b.badge:SetColorTexture(AMBER[1], AMBER[2], AMBER[3], 1)
        b.badge:Show()
        b.mark:SetText("A")
        b.mark:SetTextColor(0.08, 0.05, 0.03)
    else
        b.badge:Hide()
        b.mark:SetText("")
    end
end

---------------------------------------------------------------------------
-- Painting a slot
---------------------------------------------------------------------------
-- What the plan puts in the slot (never the quantity wanted: that is the hover's, and a "~" mark says it is short of it)
local function CountText(cell)
    if not cell then return "" end
    if cell.ghost then return "0" end
    if cell.reserved and cell.count then return tostring(cell.count) end
    return (cell.count and cell.count > 1) and tostring(cell.count) or ""
end

-- cell: { id, count, icon, ... }; key: which mark; faint: the item isn't there (a ghost)
local function PaintSlot(b, cell, markKey, edgeColor, countText, faint)
    local pal = Wg().pal
    if cell then
        b.tex:SetTexture(IconOfId(cell.id, cell.icon))
        b.tex:SetDesaturated(cell.unknown == true or faint == true)
        b.tex:SetAlpha(faint and 0.45 or 1)
        b.tex:Show()
        b.count:SetText(countText or "")
    else
        b.tex:Hide()
        b.count:SetText("")
    end
    local mark = markKey and MARK[markKey]
    if mark then
        b.badge:SetColorTexture(mark.color[1], mark.color[2], mark.color[3], 1)
        b.badge:Show()
        b.mark:SetText(mark.glyph)
        b.mark:SetTextColor(0.08, 0.05, 0.03)
    else
        b.badge:Hide()
        b.mark:SetText("")
    end
    local edge = edgeColor or (mark and mark.color) or pal.bronzeLo
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], (edgeColor or mark) and 1 or 0.9)
end

local function DrawGrid(x, y)
    local pal = Wg().pal
    local snap = MI().GuildBank.Snapshot()
    local t = snap.tabs[selTab]
    local pv = plan and plan.tabs[selTab]
    local dt = draft and draft.tabs[selTab]
    -- the picture of the arrangement: pinned stacks, and the automatic items where the layout will put them
    local theory = (view == "design" and draft) and MI().Design.Theory(draft, selTab, Ctx()) or nil
    for slot = 1, 98 do
        local col, row = math.floor((slot - 1) / ROWS), (slot - 1) % ROWS
        local b = SlotButton(slot)
        At(b, x + col * STEP, y + row * STEP)
        b.stack, b.autoId = nil, nil
        local hot = hoverTarget and hoverTarget.tab == selTab and hoverTarget.slot == slot
        local isPicked = picked and picked.tab == selTab and picked.slot == slot and (picked.kind == "slot" or picked.kind == "cell")
        if view == "design" then
            local st = dt and dt.slots[slot]
            local th = theory and theory[slot]
            local auto = th and th.auto and th or nil
            b.stack, b.autoId = st, auto and auto.id or nil
            local autoPicked = auto and picked and picked.kind == "shelf" and picked.id == auto.id and picked.tab == selTab
            local edge = (hot or isPicked or autoPicked) and pal.tealHi or (st and TEAL) or nil
            local shown = st or auto
            PaintSlot(b, shown and { id = shown.id }, st and "reserved" or nil, edge, shown and tostring(shown.count) or "", false)
            if st then b.count:SetTextColor(TEAL[1], TEAL[2], TEAL[3]) elseif auto then b.count:SetTextColor(1, 1, 1) end
        elseif view == "current" then
            local c = t and t.slots and t.slots[slot]
            PaintSlot(b, c, nil, isPicked and pal.tealHi or nil, c and c.count and c.count > 1 and tostring(c.count) or "", false)
            if c then b.count:SetTextColor(1, 1, 1) end
        else
            local cell = pv and pv.proposed and pv.proposed[slot]
            local was = pv and pv.current and pv.current[slot]
            local c = cell or was
            local key
            if c then
                if c.blocked and not c.unknown then key = "blocked"
                elseif c.unknown then key = "unknown"
                elseif c.ghost or (c.short and c.short > 0) then key = "short"
                else key = c.change end
            end
            local GR = MI().GuildRun
            local runMark = GR and GR.SlotMark(selTab, slot)
            if runMark == "active" then key = "active" elseif runMark == "done" then key = "done" elseif runMark == "uncertain" then key = "unknown" end
            PaintSlot(b, c, key, isPicked and pal.tealHi or nil, CountText(c), c and c.ghost)
            if c then b.count:SetTextColor(c.short and AMBER[1] or 1, c.short and AMBER[2] or 1, c.short and AMBER[3] or 1) end
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function ViewButton(key, label, v, x, y)
    local b = Get(key, function() return Wg().Tab(Kit.Frame(), label, 88, function() P.SetView(v) end) end)
    b:SetSelected(view == v)
    At(b, x, y)
    return b
end

function P.SetView(v)
    if v == "design" and RunBusy() then Locked() return end
    if v == "preview" and not plan then Build() return end
    view, armed = v, nil
    if v ~= "design" then P.Split.Close() end
    P.QueueRefresh()
end

local function TabButton(i)
    return Get("gTab" .. i, function()
        local btn = CreateFrame("Button", nil, Kit.Frame(), "BackdropTemplate")
        btn:SetHeight(34)
        Wg().Well(btn)
        if R.SettingsMaterial then
            R.SettingsMaterial.ReminderRow(btn)
            R.SettingsMaterial.MaterialHover(btn, function() return not btn.selected end)
        end
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(24, 24)
        btn.icon:SetPoint("LEFT", 4, 0)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
        btn.label:SetPoint("RIGHT", btn, "RIGHT", -12, 0)
        btn.label:SetJustifyH("LEFT")
        btn.label:SetWordWrap(false)
        btn.flag = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.flag:SetPoint("TOPRIGHT", -3, -2)
        btn.index = i
        tabButtons[i] = btn
        btn:SetScript("OnClick", function(self)
            if armed then Apply(armed.src, self.index, nil, armed.op == "split" and armed.qty or nil) return end
            selTab, picked = self.index, nil
            P.QueueRefresh()
            Kit.Relayout()
        end)
        btn:SetScript("OnEnter", function(self) P.TabTip(self) end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return btn
    end)
end

function P.TabTip(b)
    local i = b.index
    local mi = MI()
    local snap = mi.GuildBank.Snapshot()
    local t = snap.tabs[i]
    local names = draft and draft.names or {}
    local lines = { ("Tab %d%s"):format(i, names[i] and names[i].name and (": " .. names[i].name) or "") }
    if armed then lines[#lines + 1] = armed.op == "split" and "Click to put the new stack here." or "Click to put it here." end
    if draft then
        local dt = draft.tabs[i]
        if dt and not mi.Design.TabEmpty(dt) then
            local stacks, items = 0, 0
            for _ in pairs(dt.slots) do stacks = stacks + 1 end
            for _ in pairs(dt.items) do items = items + 1 end
            lines[#lines + 1] = ("Design: %s reserved, %s in all"):format(Plural(stacks, "stack"), Plural(items, "item"))
        else
            lines[#lines + 1] = "Nothing designed here yet. Drop an item on this tab to place it automatically."
        end
    end
    lines[#lines + 1] = "Guild bank: " .. TabState(t)
    if t then lines[#lines + 1] = RightsText(t) end
    Tip(b, lines)
end

local function Summary()
    if not plan then return nil end
    local s = plan.summary
    local bits = {}
    if s.moved > 0 then bits[#bits + 1] = ("%s would move"):format(Plural(s.moved, "stack")) end
    local d = s.design
    if d and d.short > 0 then bits[#bits + 1] = ("%s short of %s"):format(Plural(d.short, "reserved stack"), Plural(d.shortQty, "item")) end
    if d and d.blocked > 0 then bits[#bits + 1] = ("%s blocked"):format(Plural(d.blocked, "reserved stack")) end
    if s.blocked > 0 then bits[#bits + 1] = ("%s blocked"):format(Plural(s.blocked, "stack")) end
    if s.unknown > 0 then bits[#bits + 1] = ("%s can't be told"):format(Plural(s.unknown, "stack")) end
    if d and d.conflicts > 0 then bits[#bits + 1] = Plural(d.conflicts, "rule conflict") end
    if #bits == 0 then return "Nothing would move." end
    return table.concat(bits, " \194\183 ") .. "."
end

local function DetailsBlock(y, x, w)
    local mi = MI()
    local lines = {}
    local function Add(text, tone) lines[#lines + 1] = { text = text, tone = tone } end
    Add(P.BankStateText(), "dim")
    local runRes = mi.GuildRun and mi.GuildRun.Last()
    if runRes then
        Add(("Last run: %s \226\128\148 tab %d, %d of %d moves confirmed%s."):format(OUTCOME[runRes.outcome] or runRes.outcome, runRes.tab or 0, runRes.confirmed, runRes.total,
            runRes.reason and (", " .. runRes.reason) or ""), runRes.outcome == "completed" and "dim" or "warn")
        for i, l in ipairs(runRes.lines) do if i <= 30 then Add("  " .. l, "quiet") end end
    end
    if plan then
        local fresh = #StaleReasons() > 0 and "stale" or plan.freshness
        local words = { live = "current: the tabs involved were read from what the guild bank shows now",
            earlier = "earlier: the bank shows another tab; the tabs involved were read before and may have changed",
            mixed = "partly earlier: only the tab the bank shows is current", stale = "stale: the bank was closed or the preview is out of date" }
        Add("Preview reading: " .. (words[fresh] or fresh), fresh == "live" and "dim" or "warn")
        local s = plan.summary
        Add(("Operations: %s%s%s. Unchanged: %s."):format(Plural(s.ops, "operation"), s.splits > 0 and (", %d of them splitting a stack"):format(s.splits) or "",
            s.blockedOps > 0 and (", %d that can't be carried out as things stand"):format(s.blockedOps) or "", Plural(s.unchanged, "stack")), "dim")
        if planDraft then Add("This preview used your unsaved design.", "warn") end
        for _, o in ipairs(plan.design and plan.design.overflow or {}) do
            local who = ItemName(o.id)
            if o.state == "placed" then Add(("Extra %s \195\151%d would go to the free slots of tab %d."):format(who, o.qty, o.tab or 0), "dim")
            else Add(("Extra %s \195\151%d stays where it is: %s."):format(who, o.qty, o.text or "no place for it"), "warn") end
        end
        for _, a in ipairs(plan.design and plan.design.allocs or {}) do
            if a.state ~= "ok" and #lines < 40 then
                Add(("Tab %d slot %d, %s \195\151%d: %s"):format(a.tab, a.slot, ItemName(a.id), a.want,
                    a.state == "short" and ("%d of %d available (%d short)"):format(a.have, a.want, a.short) or (a.why or a.state)), a.state == "short" and "dim" or "warn")
            end
        end
        for _, c in ipairs(plan.design and plan.design.conflicts or {}) do
            if c.kind == "overridden" then
                Add(("%s is claimed by \"%s\" (%s), which comes before \"%s\" in your rules, so that rule decides. Nothing was changed."):format(ItemName(c.id), c.by, c.where or "another rule", c.rule), "warn")
            else
                Add(("%s is also matched by \"%s\", which comes later and so isn't used for it."):format(ItemName(c.id), c.by), "dim")
            end
        end
        local held = 0
        for _, u in ipairs(plan.untouched) do
            if u.class and u.class ~= "left" and held < 8 then
                held = held + 1
                Add(("%s: %s%s \226\128\148 %s"):format(u.class == "blocked" and "Blocked" or "Can't tell", ItemName(u.id), (u.count and u.count > 0) and (" \195\151" .. u.count) or "", u.text or ""), "warn")
            end
        end
        for _, k in ipairs(plan.constraints) do Add("\226\128\162 " .. k.text, "dim") end
    end
    if draft then
        for _, a in ipairs(draft.advanced) do
            if #lines < 60 then Add(("Rule \"%s\" is kept as it is and isn't drawn here: %s."):format(a.rule.name, a.why), "dim") end
        end
        if not plan then
            for _, c in ipairs(mi.Design.Conflicts(mi.Rules(), { resolve = mi.Resolve, facts = Facts })) do
                if c.kind == "overridden" then Add(("%s is claimed by \"%s\", which comes before \"%s\", so that rule decides."):format(ItemName(c.id), c.by, c.rule), "warn") end
            end
        end
    end
    Add(LEGEND, "quiet")
    for i, l in ipairs(lines) do
        local t = Text("gDet" .. i, "small")
        Wide(t, x, y, w)
        t:SetText(l.text)
        Tone(t, l.tone)
        y = y + H(t) + 3
    end
    return y
end

local function SaveDraft()
    if Locked() then return end
    local mi = MI()
    local ok, why = mi.Design.Save(draft)
    if not ok then Say("Not saved: " .. tostring(why), "warn") return end
    local keep = draft.guild
    draft = nil
    Open(keep)
    draft.rulesGen = mi.Generation()
    Say("Arrangement saved. Nothing was moved.")
    Touch()
end

local function RevertDraft()
    if Locked() then return end
    local keep = draft.guild
    draft, armed, picked = nil, nil, nil
    P.Split.Close()
    Open(keep)
    draft.rulesGen = MI().Generation()
    Say("Unsaved changes discarded.")
    Touch()
end

---------------------------------------------------------------------------
-- Carrying out the saved arrangement (inventory/GuildRun.lua): Deposit and Organize bank, each reviewed and confirmed here
---------------------------------------------------------------------------
local function StartReview(mode)
    local mi = MI()
    if not mi.GuildRun then return end
    local rv = mi.GuildRun.Review(mode)
    if rv.ok then
        review = rv
        Say(nil)
    else
        review = nil
        Say(rv.refuse.text, "warn")
    end
    P.QueueRefresh()
end

local function ConfirmStart()
    local mi = MI()
    local rv = review
    if not rv then return end
    local ok, code, text, fresh = mi.GuildRun.Start(rv)
    if ok then
        review = nil
        view, selTab = "preview", rv.tabs[1] or selTab
        Say(nil)
        return
    end
    -- never a different plan under the same confirmation: a changed state gives a new review to read and confirm
    Build()   -- the preview is made again too (it clears any review), then the new review is put up for reading
    review = (fresh and fresh.ok) and fresh or nil
    Say(text .. (review and " The new review is below." or ""), "warn")
end

-- The panel under the preview summary: the actions, the confirmation, the progress and the result.
local function DrawRun(px, py, pw)
    local mi = MI()
    local GR = mi.GuildRun
    if not GR then return py end
    local prog = GR.Progress()
    local result = GR.Last()
    local function Line(key, text, tone, style)
        local t = Text(key, style or "small")
        Wide(t, px, py, pw)
        t:SetText(text)
        Tone(t, tone)
        py = py + H(t) + 3
        return t
    end
    local head = Text("gRunTitle", "heading")
    Wide(head, px, py + 2, pw)
    head:SetText("Carry out the saved arrangement")
    Tone(head, "head")
    py = py + 24
    if prog then
        Line("gRunProg", ("%s %s: %d of %d moves confirmed."):format(prog.mode == "deposit" and "Depositing in" or "Organizing", prog.tabsText or "the guild bank", prog.confirmed, prog.total), nil, "body")
        local waiting = prog.needClick and "The game needs your click for the next move. Press Continue."
            or (prog.stopping and "Stopping after the move in progress. A move already handed to the game is not undone.")
            or (prog.reading and ("Reading tab %d\226\128\166"):format(prog.reading))
            or (prog.waiting and "Waiting for the bank\226\128\166") or ""
        Line("gRunWait", waiting, "dim")
        local stop = Button("gRunStop", prog.stopping and "Stopping\226\128\166" or "Stop", 90, "secondary", (not prog.stopping) and function() GR.Stop() end or nil)
        At(stop, px, py)
        R.Interact.Tip(stop, "Stop", "Ends the run after the move in progress. Nothing already moved is undone.")
        if prog.needClick then At(Button("gRunGo", "Continue", 100, "primary", function() GR.Continue() end), px + 94, py) end
        return py + 32
    end
    if review then
        Line("gRevHead", review.headline, nil, "body")
        for i, l in ipairs(review.lines) do Line("gRevL" .. i, l, (l:find("^Not included") or l:find("^Blocked") or l:find("^Can't")) and "warn" or "dim") end
        local label = review.complete and (review.mode == "deposit" and "Start deposit" or "Start organizing") or ("Do these " .. review.moves .. " moves")
        At(Button("gRevGo", label, math.max(130, #label * 7 + 24), "primary", ConfirmStart), px, py)
        At(Button("gRevNo", "Cancel", 80, "secondary", function() review = nil; Say("Nothing was moved."); end), px + math.max(130, #label * 7 + 24) + 4, py)
        return py + 34
    end
    if result then
        local word = OUTCOME[result.outcome] or result.outcome
        local bits = { ("%d of %d moves confirmed"):format(result.confirmed, result.total) }
        if result.notStarted > 0 then bits[#bits + 1] = ("%d not started"):format(result.notStarted) end
        if result.uncertain > 0 then bits[#bits + 1] = ("%d uncertain"):format(result.uncertain) end
        if result.notIncluded > 0 then bits[#bits + 1] = ("%d not included"):format(result.notIncluded) end
        if result.unreadTabs and #result.unreadTabs > 0 then bits[#bits + 1] = ("%d %s not read"):format(#result.unreadTabs, #result.unreadTabs == 1 and "tab" or "tabs") end
        if (result.blockedStacks or 0) > 0 then bits[#bits + 1] = ("%d stacks blocked"):format(result.blockedStacks) end
        Line("gResHead", ("%s: %s."):format(word, table.concat(bits, " \194\183 ")), (result.outcome == "completed") and nil or "warn", "body")
        if result.reason and result.outcome ~= "completed" then Line("gResWhy", "Why: " .. result.reason .. ".", "dim") end
        if result.cursor then
            Line("gResCur", ("Your cursor holds %s from this run. Put it back in %s."):format(
                (MI().ItemFacts(result.cursor.id) or {}).name or "an item", result.cursor.where.kind == "bag" and ("bag %d slot %d"):format(result.cursor.where.bag, result.cursor.where.slot) or ("tab %d slot %d"):format(result.cursor.where.tab, result.cursor.where.slot)), "warn")
        end
        if result.outcome == "review" or result.outcome == "stopped" or result.outcome == "partial" then
            Line("gResNext", "Nothing resumes by itself. Refresh the preview to review what is left.", "quiet")
        end
    end
    -- the actions
    local mode = source == "bags" and "deposit" or "reorganize"
    local dirty = draft ~= nil and Dirty()
    local fresh = plan and planMode == mode and #StaleReasons() == 0 and not planDraft
    if dirty then
        Line("gRunDirty", "Your design has unsaved changes. Deposit and Organize bank use the saved arrangement only.", "warn")
        At(Button("gRunSave", "Save and preview", 140, "primary", function() SaveDraft(); if not Locked() then Build() end end), px, py)
        return py + 34
    end
    local label = mode == "deposit" and "Deposit\226\128\166" or "Organize bank\226\128\166"
    local b = Button("gRunAct", label, 140, "primary", fresh and function() StartReview(mode) end or nil)
    At(b, px, py)
    R.Interact.Tip(b, mode == "deposit" and "Deposit" or "Organize bank",
        mode == "deposit" and "Moves eligible items from your bags into the tabs the saved arrangement names. The guild bank shows each tab in turn. You review and confirm first."
        or "Rearranges what is already in the guild bank as the saved arrangement says, between tabs too. Nothing is taken to your bags. You review and confirm first.")
    if not fresh then
        local t = Text("gRunHint", "small")
        Wide(t, px + 146, py + 6, pw - 146)
        t:SetText(plan and (planMode ~= mode and "Press Preview changes for this source first." or "Refresh the preview first.") or "Press Preview changes first.")
        Tone(t, "quiet")
    end
    return py + 34
end

RUN.Draw = DrawRun

function P.DrawGuildPreview(y)
    local mi = MI()
    local pal = Wg().pal
    local pageW = math.max(W, Kit.Frame():GetWidth() or W)
    local head = Text("gHead", "heading")
    Wide(head, PAD, y)
    head:SetText("Guild bank arrangement")
    Tone(head, "head")
    local d = EnsureDraft()
    local dirty = d and Dirty()
    if RUN.Busy() and view == "design" then view = "preview" end
    if dirty then
        local u = Text("gUnsaved", "small")
        Wide(u, PAD + 190, y + 3, 120)
        u:SetText("Unsaved changes")
        Tone(u, "warn")
        local save = Button("gSave", "Save arrangement", 140, "secondary", RUN.Unless(RUN.Busy(), SaveDraft))
        At(save, pageW - PAD - 140 - 4 - 80, y - 4)
        R.Interact.Tip(save, "Save arrangement", "Writes this design as guild bank rules at the end of your rules list; the rules above them keep their order. Nothing is moved.")
        local revert = Button("gRevert", "Revert", 80, "secondary", RUN.Unless(RUN.Busy(), RevertDraft))
        At(revert, pageW - PAD - 80, y - 4)
        R.Interact.Tip(revert, "Revert", "Throws away the changes you haven't saved.")
        y = y + 6
    end
    y = y + 22
    local guild = d and d.guild
    if not d then
        local none = Text("gNone", "small")
        Wide(none, PAD, y)
        none:SetText("Join a guild, or open its guild bank once, to arrange it here. Nothing is moved by this page.")
        Tone(none, "quiet")
        return y + H(none) + 6
    end
    local tabs = d.numTabs or 0
    if tabs == 0 then
        local none = Text("gNoTabs", "small")
        Wide(none, PAD, y)
        none:SetText("Open the guild bank once so its tabs' names and icons can be read. Until then there is nothing to arrange.")
        Tone(none, "quiet")
        return y + H(none) + 6
    end
    if selTab > tabs then selTab = tabs end

    local what = Text("gWhat", "small")
    Wide(what, PAD, y)
    what:SetText("Arrange items here to choose where they belong.")
    Tone(what, "dim")
    y = y + H(what) + 2
    local only = Text("gOnly", "small")
    Wide(only, PAD, y)
    only:SetText("Editing is design only \226\128\148 items move only when you review and confirm Deposit or Organize bank in the Preview.")
    Tone(only, "warn")
    y = y + H(only) + 6

    -- the view switch and the one primary action
    ViewButton("gVCur", "Current", "current", PAD, y)
    ViewButton("gVDes", "Design", "design", PAD + 92, y)
    ViewButton("gVPre", "Preview", "preview", PAD + 184, y)
    At(Button("gPreview", "Preview changes", 130, "primary", RUN.Unless(RUN.Busy(), function() Build() end)), pageW - PAD - 130, y - 2)
    y = y + 34

    -- the tabs
    local snapAll = mi.GuildBank.Snapshot()
    local tabW = math.max(70, math.min(120, math.floor((pageW - PAD * 2 - (tabs - 1) * 2) / tabs)))
    for i = 1, tabs do
        local b = TabButton(i)
        local nm = d.names[i]
        b:SetWidth(tabW)
        At(b, PAD + (i - 1) * (tabW + 2), y)
        b.icon:SetTexture((nm and nm.icon) or QUESTION)
        b.label:SetText(nm and nm.name or ("Tab " .. i))
        local flag, color
        local snapTab = snapAll.tabs[i]
        if view ~= "design" and not (snapTab and snapTab.slots) then flag, color = "?", MARK.unknown.color
        elseif view == "design" and d.tabs[i] and not mi.Design.TabEmpty(d.tabs[i]) then flag, color = "\226\128\162", TEAL
        elseif view == "preview" and plan and plan.tabs[i] and plan.tabs[i].changed then flag, color = "+", MARK.added.color end
        if view == "preview" and plan and plan.tabs[i] and plan.tabs[i].proposed then
            for _, c in pairs(plan.tabs[i].proposed) do if c.blocked then flag, color = c.unknown and "?" or "!", c.unknown and MARK.unknown.color or MARK.blocked.color break end end
        end
        b.flag:SetText(flag or "")
        if color then b.flag:SetTextColor(color[1], color[2], color[3]) end
        local hot = hoverTarget and hoverTarget.tab == i and hoverTarget.slot == nil
        local edge = (hot or (armed and false)) and pal.tealHi or (i == selTab and pal.tealHi or pal.bronzeLo)
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], (i == selTab or hot) and 1 or 0.9)
        b.selected = i == selTab
        if b.sel then b.sel:SetShown(b.selected or hot) end
    end
    y = y + 40

    -- the grid, and beside it what goes with the view
    local gx, gy = PAD, y
    local t = snapAll.tabs[selTab]
    local unreadHere = view ~= "design" and not (t and t.slots)
    local px = gx + GRID_W + 16
    local pw = pageW - px - PAD
    if unreadHere then
        for s = 1, 98 do
            local b = slotButtons[s]
            if b then b:Hide() end
        end
        local u = Text("gUnread", "body")
        Wide(u, gx, gy, GRID_W)
        local nm = d.names[selTab]
        u:SetText((t and t.viewable == false) and "Your rank can't see this tab." or ("Not read yet. Show \"" .. (nm and nm.name or ("tab " .. selTab)) .. "\" in the guild bank to read it. It is not empty, only unknown."))
        Tone(u, "warn")
    else
        DrawGrid(gx, gy)
    end
    local py = gy

    if view == "design" then
        local tray = Text("gTrayHead", "heading")
        Wide(tray, px, py, pw)
        tray:SetText("Items")
        Tone(tray, "head")
        local sb = Get("gSearch", function()
            local e = Wg().EditBox(Kit.Frame(), 150, 22)
            e:SetMaxLetters(40)
            e:SetScript("OnTextChanged", function(self, byUser)
                if byUser ~= false and self:GetText() ~= search then search = self:GetText() or ""; P.QueueRefresh() end
            end)
            return e
        end)
        R.Interact.Tip(sb, "Search items", "Type part of an item's name to narrow the list. It lists items from your bags and from the guild bank as last read, and what this design already names.")
        At(sb, px + 60, py - 3)
        sb:SetWidth(math.min(200, pw - 70))
        if not sb:HasFocus() and sb:GetText() ~= search then sb:SetText(search) end
        py = py + 24
        local list, total = TrayList()
        local per = math.max(4, math.floor((pw + 2) / (CELL + 2)))
        for i, e in ipairs(list) do
            local b = ItemButton("gTray" .. i)
            At(b, px + ((i - 1) % per) * (CELL + 2), py + math.floor((i - 1) / per) * (CELL + 2))
            local held = ("You hold %d in your bags, %d in the guild bank (as last read)."):format(e.bags, e.bank)
            PaintItemButton(b, { kind = "tray", id = e.id }, held)
        end
        local rows = math.max(1, math.ceil(math.max(#list, 1) / per))
        if #list == 0 then
            local none = Text("gTrayNone", "small")
            Wide(none, px, py, pw)
            none:SetText(total == 0 and "No item matches. Items from your bags and the guild bank appear here." or "")
            Tone(none, "quiet")
        end
        py = py + rows * (CELL + 2) + 2
        local more = Text("gTrayMore", "small")
        Wide(more, px, py, pw)
        more:SetText(total > #list and ("%d more: type to narrow the list."):format(total - #list) or "")
        Tone(more, "quiet")
        py = py + (total > #list and 16 or 2)

        -- what this tab places automatically
        local dt = d.tabs[selTab]
        local ah = Text("gAutoHead", "heading")
        Wide(ah, px, py + 4, pw)
        ah:SetText("Placed automatically in this tab")
        Tone(ah, "head")
        py = py + H(ah) + 10
        local ld = Get("gLayout", function()
            return Wg().Dropdown(Kit.Frame(), 230, function(value)
                local ok, text = mi.Design.SetLayout(draft, selTab, value)
                Say(ok and text or ("Nothing changed. " .. text), (not ok) and "warn" or nil)
                Touch()
            end)
        end)
        ld:SetChoices(function()
            local out = {}
            for _, key in ipairs(mi.LAYOUT_ORDER) do out[#out + 1] = { value = key, label = mi.LAYOUTS[key] } end
            return out
        end)
        local layout = (dt and dt.layout) or "packed"
        ld:SetValue(layout, mi.LAYOUTS[layout])
        ld:SetWidth(math.min(230, pw))
        At(ld, px, py)
        py = py + 26
        local n = 0
        if dt then
            local ids = {}
            for id in pairs(dt.rest) do ids[#ids + 1] = id end
            table.sort(ids, function(a, b) return ItemName(a) < ItemName(b) end)
            for _, id in ipairs(ids) do
                n = n + 1
                local b = ItemButton("gShelf" .. n)
                At(b, px + ((n - 1) % per) * (CELL + 2), py + math.floor((n - 1) / per) * (CELL + 2))
                PaintItemButton(b, { kind = "shelf", id = id, tab = selTab }, nil)
            end
        end
        local catN = dt and #dt.cats or 0
        local shelfRows = n > 0 and math.ceil(n / per) or 0
        if n == 0 and catN == 0 then
            local none = Text("gAutoNone", "small")
            Wide(none, px, py, pw)
            none:SetText("Nothing. Drop an item on this tab to place it automatically.")
            Tone(none, "quiet")
            py = py + 18
        else
            py = py + shelfRows * (CELL + 2)
        end
        for i = 1, catN do
            local key = dt.cats[i]
            local c = Text("gCat" .. i, "small")
            Wide(c, px, py, pw - 90)
            c:SetText(("Category: %s"):format(mi.CategoryName(key) or key))
            Tone(c, nil)
            local rb = Button("gCatX" .. i, "Remove", 70, "secondary", function()
                local ok, text = mi.Design.RemoveCategory(draft, Ctx(), selTab, key)
                Say(text, (not ok) and "warn" or nil)
                Touch()
            end)
            At(rb, px + pw - 70, py - 4)
            py = py + 24
        end
        local dd = Get("gAddCat", function()
            return Wg().Dropdown(Kit.Frame(), 170, function(key)
                local ok, text = mi.Design.AddCategory(draft, Ctx(), selTab, key)
                Say(text, (not ok) and "warn" or nil)
                Touch()
            end)
        end)
        dd:SetChoices(function()
            local out = {}
            for _, c in ipairs(mi.Categories()) do out[#out + 1] = { value = c.key, label = c.label .. (c.group ~= c.label and ("  (" .. c.group .. ")") or "") } end
            return out
        end)
        dd:SetValue(nil, "Add a category")
        At(dd, px, py + 2)
        py = py + 30

        -- the selected item and what can be done with it
        local acts = {}
        if picked and (picked.kind == "tray" or picked.kind == "shelf" or picked.kind == "slot") then
            local stillThere = picked.kind ~= "slot" or (draft.tabs[picked.tab] and draft.tabs[picked.tab].slots[picked.slot])
            if stillThere then acts = ActionsFor(picked, nil) else picked = nil end
        end
        if picked then
            local sel = Text("gSel", "body")
            Wide(sel, px, py, pw)
            local st = picked.kind == "slot" and draft.tabs[picked.tab] and draft.tabs[picked.tab].slots[picked.slot]
            sel:SetText(st and ("%s \195\151%d \194\183 tab %d, slot %d \194\183 reserved"):format(ItemName(picked.id), st.count, picked.tab, picked.slot)
                or (ItemName(picked.id) .. (picked.kind == "shelf" and (" \194\183 placed automatically" .. SizeText(picked)) or "")))
            Tone(sel, nil)
            py = py + H(sel) + 2
            if picked.kind ~= "tray" then
                local ex = Text("gSelExtras", "small")
                Wide(ex, px, py, pw)
                ex:SetText(ExtrasText(picked.id, picked.tab))
                Tone(ex, "dim")
                py = py + H(ex) + 4
            end
            local bx = px
            for i, a in ipairs(acts) do
                local w = math.min(190, math.max(90, #a.label * 7 + 22))
                if bx + w > px + pw then bx, py = px, py + 28 end
                local btn = Button("gAct" .. i, a.label, w, "secondary", a.fn)
                At(btn, bx, py)
                R.Interact.Tip(btn, a.label, a.tip)
                bx = bx + w + 4
            end
            py = py + 30
        end
    elseif view == "current" then
        local title = Text("gTabTitle", "body")
        Wide(title, px, py, pw)
        local nm = d.names[selTab]
        title:SetText(("Tab %d%s \194\183 %s"):format(selTab, nm and nm.name and (" \"" .. nm.name .. "\"") or "", TabState(t)))
        Tone(title, (t and t.state == "live") and nil or "warn")
        py = py + H(title) + 2
        local rights = Text("gRights", "small")
        Wide(rights, px, py, pw)
        rights:SetText(RightsText(t))
        Tone(rights, "dim")
        py = py + H(rights) + 8
        local note = Text("gCurNote", "small")
        Wide(note, px, py, pw)
        note:SetText("What the guild bank held when it was last read. Switch to Design to arrange it; nothing here changes the guild bank.")
        Tone(note, "dim")
        py = py + H(note) + 8
        if picked and picked.kind == "cell" and picked.tab == selTab then
            local c = SnapCell(selTab, picked.slot)
            local detail = Text("gDetail", "small")
            Wide(detail, px, py, pw)
            detail:SetText(c and ("Slot %d: %s%s"):format(picked.slot, c.id and ItemName(c.id) or "an item the game didn't identify", c.count and (" \195\151" .. c.count) or "") or ("Slot %d: empty as last read"):format(picked.slot))
            Tone(detail, nil)
            py = py + H(detail) + 4
        end
    else
        -- Preview: the source, one summary, and the one message when it is out of date
        local function SrcButton(key, label, v, x)
            local b = Get(key, function() return Wg().Tab(Kit.Frame(), label, 130, function()
                if source ~= v and not RUN.Locked() then source = v; if plan then plan = nil end; Build() end
            end) end)
            b:SetSelected(source == v)
            At(b, x, py)
        end
        SrcButton("gSrcBags", "From my bags", "bags", px)
        SrcButton("gSrcBank", "Already in the bank", "bank", px + 134)
        py = py + 34
        if plan then
            local reasons = StaleReasons()
            if #reasons > 0 then
                local bank = false
                for _, r in ipairs(reasons) do if r:find("guild bank") or r:find("bags") then bank = true end end
                local st = Text("gStale", "small")
                Wide(st, px, py + 4, pw - 130)
                st:SetText(bank and "Bank contents changed. Refresh preview." or "Design changed. Refresh preview.")
                Tone(st, "warn")
                At(Button("gRefresh", "Refresh preview", 120, "primary", RUN.Unless(RUN.Busy(), function() Build() end)), px + pw - 120, py)
                py = py + 30
            end
            local sum = Text("gSum", "body")
            Wide(sum, px, py, pw)
            sum:SetText((planDraft and "From your unsaved design: " or "") .. (Summary() or ""))
            Tone(sum, nil)
            py = py + H(sum) + 6
            local fresh = Text("gFresh", "small")
            Wide(fresh, px, py, pw)
            local f = #reasons > 0 and "stale" or plan.freshness
            fresh:SetText(f == "live" and "Reading: current. Hover a slot to see what happens there."
                or ("Reading: " .. (f == "stale" and "stale" or "partly from earlier") .. ". Hover a slot to see what happens there."))
            Tone(fresh, f == "live" and "dim" or "warn")
            py = py + H(fresh) + 6
            if picked and picked.kind == "cell" and picked.tab == selTab then
                local detail = Text("gDetail", "small")
                Wide(detail, px, py, pw)
                detail:SetText(table.concat(PlanLines(selTab, picked.slot), "\n"))
                Tone(detail, "dim")
                py = py + H(detail) + 4
            end
            local pv = plan.tabs[selTab]
            for i = 1, 3 do
                local issue = pv and pv.issues and pv.issues[i]
                if issue then
                    local tx = Text("gIssue" .. i, "small")
                    Wide(tx, px, py, pw)
                    tx:SetText("! " .. issue)
                    Tone(tx, "warn")
                    py = py + H(tx) + 2
                end
            end
            py = RUN.Draw(px, py + 6, pw)
        else
            local none = Text("gNoPlan", "small")
            Wide(none, px, py, pw)
            none:SetText("Press Preview changes to see where your saved arrangement would put things. Nothing is moved.")
            Tone(none, "dim")
            py = py + H(none) + 6
        end
    end
    y = math.max(gy + GRID_H, py) + 10

    -- the one contextual line, the arming state, and the arrangement's own buttons
    if msg then
        local m = Text("gMsg", "small")
        Wide(m, PAD, y, pageW - PAD * 2 - (armed and 90 or 0))
        m:SetText(msg)
        Tone(m, msgTone == "warn" and "warn" or "dim")
        y = y + H(m) + 6
    end
    if armed then
        At(Button("gCancelArm", "Cancel", 80, "secondary", function()
            armed = nil
            Say("Nothing changed.")
        end), pageW - PAD - 80, y - 28)
    end
    At(Button("gDetails", details and "Hide details" or "Show details", 110, "secondary", function() details = not details; P.QueueRefresh() end), pageW - PAD - 110, y)
    y = y + 34
    if details then
        y = y + 4
        y = DetailsBlock(y, PAD, pageW - PAD * 2)
    end
    return y + 8
end

-- the page was hidden: a drag in progress is dropped (nothing changes), the split dialog is put away; the draft stays
function P.GuildHidden()
    review = nil
    if P.Drag and P.Drag.Active() then P.Drag.Cancel() end
    if P.Split then P.Split.Close() end
    armed, hoverTarget = nil, nil
end

-- a profile was applied: the rules are another profile's now. A draft with no edits is rebuilt from them; one with edits stays.
function P.GuildProfileChanged()
    if draft and not Dirty() then draft = nil end
    plan, review = nil, nil
    if draft then msg, msgTone = "Your profile changed. Saving writes this arrangement into the new profile's rules.", "warn" end
end

-- what the editor keeps: the draft's reserved stacks and items, and the tray's references (for /tui perf; read-only)
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.design", { label = "Magic Inventory arrangement draft (reserved stacks, items and tray references held)", unit = "count", kind = "cache",
        read = function()
            local n = known and #known or 0
            for _, t in pairs(draft and draft.tabs or {}) do
                for _ in pairs(t.slots) do n = n + 1 end
                for _ in pairs(t.items) do n = n + 1 end
            end
            return n
        end })
end

-- the rules changed anywhere: a review waiting for confirmation no longer describes them
if R.MagicInventory then R.MagicInventory.OnChange(function() Withdraw() end) end
-- the run's progress redraws the page (registered once)
if R.MagicInventory and R.MagicInventory.GuildRun then
    R.MagicInventory.GuildRun.OnUpdate(function(what)
        if what == "start" or what == "done" then runStale = true end
        P.QueueRefresh()
    end)
end
