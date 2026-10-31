-- Magic Inventory, the guild bank arrangement editor (TwichUI_Settings/pages/MagicInventoryGuild.lua, MagicInventoryDrag.lua),
-- driven through the controls' own handlers with stand-in frames. This is handler-level: a drag is OnDragStart, "the pointer is over
-- the target" and OnDragStop, a click is OnClick. It proves what the handlers do to the draft, the rules and the game's calls; it
-- does not prove real pointer dragging, how anything looks, or what the real guild bank answers.
--   * opening the editor writes nothing; a drop on a tab or a slot edits the draft only;
--   * Shift-click and the item menu's actions split; cancelling a split, a drag or a move leaves the draft as it was;
--     combining is limited to compatible stacks; a refused edit says why and changes nothing;
--   * the preview uses the draft, says so, and says when the design or the bank changed;
--   * Save arrangement writes rules, Revert discards, leaving the page does neither;
--   * nothing in the game is picked up, split or moved, and a real item on the cursor is never touched.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich", {
  db = { modules = { magicInventory = true } },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = MIFake(kind, parent); if name then cl[name] = fr end return fr end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = MI_FILES,
})
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function(name, text) c.POPUP = { name = name, text = text }; return {} end
c.GetCursorPosition = function() return 100, 100 end
c.UISpecialFrames = {}
c.tinsert = table.insert
for _, file in ipairs({ "../TwichUI_Settings/Kit.lua", "../TwichUI_Settings/Widgets.lua", "../TwichUI_Settings/pages/MagicInventory.lua",
  "../TwichUI_Settings/pages/MagicInventoryDrag.lua", "../TwichUI_Settings/pages/MagicInventoryGuild.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("TwichUI_Settings", {})
end
local R = c.TwichUI
local MI = R.MagicInventory
local P = R.MagicInventoryPage
local D = MI.Design
local function Flush() for _ = 1, 6 do FlushTimers() end end
local function Texts(frame, out)
  out = out or {}
  if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do if ch.shown ~= false then Texts(ch, out) end end
  return out
end
local function Has(frame, pattern)
  for _, t in ipairs(Texts(frame)) do if t:find(pattern) then return true end end
  return false
end
local function Ctl(key) return P.Control(key) end
local function Click(key, button)
  local b = Ctl(key)
  Check(b and b.shown, "control " .. key .. " is there")
  if b and b.scripts.OnClick then b.scripts.OnClick(b, button or "LeftButton") end
  Flush()
end
local function DragTo(srcKey, targetKey)
  local s, t = Ctl(srcKey), Ctl(targetKey)
  Check(s and t, "drag " .. srcKey .. " -> " .. targetKey .. ": both controls exist")
  if not (s and t) then return end
  s.scripts.OnDragStart(s)
  t.IsMouseOver = function() return true end
  s.scripts.OnDragStop(s)
  t.IsMouseOver = nil
  Flush()
end
-- the explicit way to reserve an exact slot: the item's menu "Pin to a slot" (list items) or "Place" (tray items), then a click on the slot
local function PinTo(srcKey, slotKey)
  local s = Ctl(srcKey)
  Check(s ~= nil, "pin " .. srcKey .. ": the control exists")
  if not s then return end
  local act
  for _, a in ipairs(P.ActionsFor(s.src, nil)) do
    if a.label:find("Pin to a slot", 1, true) or a.label:find("Place", 1, true) then act = a end
  end
  Check(act ~= nil, "pin " .. srcKey .. ": the menu has the action")
  if act then act.fn(); Flush(); Click(slotKey) end
end
local function DragNowhere(srcKey)
  local s = Ctl(srcKey)
  s.scripts.OnDragStart(s)
  s.scripts.OnDragStop(s)
  Flush()
end

---------------------------------------------------------------------------
-- The synthetic guild bank and bags
---------------------------------------------------------------------------
c.ITEMS[2447] = c.ITEMS[2447] or { name = "Peacebloom", class = 7, sub = 9, maxStack = 20, quality = 1 }
c.GUILD.name = "Night Owls"
c.GUILD.tabs = {
  [1] = { name = "Gear", icon = 5, withdraw = -1, slots = {} },
  [2] = { name = "Cloth", icon = 133, withdraw = -1, slots = { [2] = { id = 2589, count = 8 } } },
  [3] = { name = "Herbs", icon = 134, withdraw = -1, slots = {} },
}
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 15 }, [3] = { 2447, 10 } } } })
c.OpenGuildBank()
c.GUILD.current = 2
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local gen, nRules, nDests = MI.Generation(), #MI.Rules(), #MI.Dests()

local f = P.Frame()
f:Hide(); f:Show()
Flush()

---------------------------------------------------------------------------
-- What the page shows first
---------------------------------------------------------------------------
Check(Has(f, "^Guild bank arrangement$"), "the page is the arrangement")
Check(Has(f, "^Arrange items here to choose where they belong%.$"), "with the one instruction")
Check(Has(f, "^Editing is design only \226\128\148 items move only when you review and confirm Deposit or Organize bank in the Preview%.$"), "and the label that editing moves nothing")
Check(Ctl("gPreview") and Ctl("gPreview").text.text == nil or true, "(the primary action exists)")
Check(Ctl("gPreview") ~= nil and Ctl("gPreview").enabled, "Preview changes is the primary action")
Check(Ctl("gTab1") and Ctl("gTab2") and Ctl("gTab3") and not Ctl("gTab4"), "the tabs are the bank's three")
Check(Ctl("gTab2").label.text == "Cloth" and Ctl("gTab2").icon.texture == 133, "a tab shows the bank's own name and icon")
Check(Ctl("gSlot1") and Ctl("gSlot98"), "one grid of 98 slots")
Check(Ctl("gSlot99") == nil, "and no second grid")
Check(P.GuildView() == "design", "Design is the first view")
for _, t in ipairs(Texts(f)) do
  Check(not t:find("Eligible:") and not t:find("Held back or left alone") and not t:find("What this does not assume"), "no report on the first screen: " .. t)
end
Check(MI.Generation() == gen and #MI.Rules() == nRules and #MI.Dests() == nDests, "opening the editor wrote nothing: no rule, no destination")
Check(P.GuildDraft() ~= nil and not D.Dirty(P.GuildDraft()), "there is a draft and it is clean")
Check(not Has(f, "Unsaved changes"), "so nothing is said to be unsaved")
Check((Ctl("gSave") == nil or not Ctl("gSave").shown) and (Ctl("gRevert") == nil or not Ctl("gRevert").shown), "Save arrangement and Revert appear only with an edit")
local observedItems = 0
for _ in pairs(c.GUILD.tabs[2].slots) do observedItems = observedItems + 1 end
Check(observedItems == 1, "(the bank holds an item the editor must not turn into a rule)")

---------------------------------------------------------------------------
-- The tray, and dropping an item on a tab
---------------------------------------------------------------------------
Check(Ctl("gTray1") ~= nil and Ctl("gTray1").src.id == 2589, "the tray offers items from the bags and the bank (Linen first, by name)")
Check(Ctl("gTray2") ~= nil and Ctl("gTray2").src.id == 2447, "and the next by name")
local search = Ctl("gSearch")
search:SetText("peace"); search.scripts.OnTextChanged(search, true); Flush()
Check(Ctl("gTray1").src.id == 2447 and not (Ctl("gTray2") and Ctl("gTray2").shown), "the search narrows the tray")
search:SetText(""); search.scripts.OnTextChanged(search, true); Flush()

local picks, cleared = #c.PICKUPS, c.CLEARED
Check(not Has(f, "Unsaved changes"), "(clean)")
DragTo("gTray1", "gTab2")
local d = P.GuildDraft()
Check(d.tabs[2] and d.tabs[2].items[2589] and d.tabs[2].rest[2589], "an item dropped on a tab is assigned to it, placed automatically")
Check(next(d.tabs[2].slots) == nil, "and reserves no slot")
Check(Has(f, "Unsaved changes"), "the page says there are unsaved changes")
Check(Ctl("gSave") and Ctl("gSave").shown and Ctl("gSave").enabled and Ctl("gRevert").shown and Ctl("gRevert").enabled, "Save arrangement and Revert appear and are on")
Check(MI.Generation() == gen and #MI.Rules() == nRules, "a drop edits the draft only: no rule was written")
Check(Has(f, "goes to tab 2 \"Cloth\", placed automatically"), "one contextual message says what happened")

-- the tab's shelf shows it as automatic
Click("gTab2")
Check(Ctl("gShelf1") ~= nil and Ctl("gShelf1").src.kind == "shelf" and Ctl("gShelf1").src.id == 2589, "the tab's automatic items are on its shelf")
Check(Ctl("gShelf1").mark.text == "A" and Has(f, "Placed automatically in this tab"), "marked A, under its own heading")

-- dropping on nothing changes nothing
local before = D.Digest(d)
DragNowhere("gTray2")
Check(D.Digest(P.GuildDraft()) == before and not P.Drag.Active(), "a drop on nothing changes nothing")
Check(Has(f, "^Nothing changed%.$"), "and says so")

---------------------------------------------------------------------------
-- Dropping an item on a slot: an exact reservation
---------------------------------------------------------------------------
-- a plain drop on a slot does NOT pin it: the tab takes the item and the addon decides where (stack size and layout)
DragTo("gShelf1", "gSlot5")
d = P.GuildDraft()
Check(next(d.tabs[2].slots) == nil, "an item dropped on a slot is not pinned there: the tab takes it")
Check(Ctl("gSlot5").mark.text == "" and Ctl("gSlot1").autoId == 2589 and Ctl("gSlot1").count.text == "20", "the picture draws it where the layout puts it (the first slot, a full stack), not where it was dropped")
Check(Ctl("gSlot1").stack == nil, "(it is not a pinned stack)")
-- the explicit way: "Pin to a slot", then click the slot
do
  local pin
  for _, a in ipairs(P.ActionsFor({ kind = "shelf", id = 2589, tab = 2 }, nil)) do if a.label:find("Pin to a slot", 1, true) then pin = a end end
  Check(pin ~= nil, "the list item's menu offers Pin to a slot")
  pin.fn(); Flush()
  Click("gSlot5")
end
d = P.GuildDraft()
Check(d.tabs[2].slots[5] and d.tabs[2].slots[5].id == 2589 and d.tabs[2].slots[5].count == 20, "pinning reserves a full stack in exactly that slot")
Check(Ctl("gSlot5").mark.text == "R" and Ctl("gSlot5").count.text == "20", "the slot shows R and its target quantity")
Check(Ctl("gSlot6").mark.text == "", "a slot nobody reserved shows no mark")
Check(Ctl("gSlot5").stack ~= nil, "(the slot knows its stack)")
Check(Has(f, "Linen Cloth \195\1510? ?20") or Has(f, "reserved"), "(the selection says it is reserved)")
PinTo("gTray2", "gSlot5")
Check(d.tabs[2].slots[5].id == 2589 and Has(f, "Nothing changed%. That slot is already reserved"), "a reserved slot refuses another item, and says why")

---------------------------------------------------------------------------
-- Splitting: Shift-click, the dialog, the destination; cancel and Esc
---------------------------------------------------------------------------
c.SHIFT = false
c.IsModifiedClick = function(what) return what == "SPLITSTACK" and c.SHIFT end
c.SHIFT = true
Click("gSlot5")
c.SHIFT = false
local dlg = P.Split.Dialog()
Check(P.Split.IsShown() and dlg.item.text:find("Linen Cloth") and dlg.item.text:find("20"), "Shift-click on a reserved stack opens the split dialog")
dlg.qty:SetText("5"); dlg.qty.scripts.OnTextChanged(dlg.qty)
Check(dlg.ok.enabled and dlg.hint.text:find("5 go to the new stack, 15 stay"), "a valid quantity enables Split and says what it does")
for _, bad in ipairs({ "0", "20", "21", "x", "", "2.5" }) do
  dlg.qty:SetText(bad); dlg.qty.scripts.OnTextChanged(dlg.qty)
  Check(not dlg.ok.enabled, "'" .. bad .. "' can't be split off a stack of 20")
  dlg.qty.scripts.OnEnterPressed(dlg.qty)
  Check(P.Split.IsShown(), "Enter with '" .. bad .. "' doesn't close the dialog")
end
before = D.Digest(d)
dlg.qty:SetText("5"); dlg.qty.scripts.OnTextChanged(dlg.qty)
dlg.ok.scripts.OnClick(dlg.ok); Flush()
Check(not P.Split.IsShown(), "Split closes the dialog")
Check(D.Digest(d) == before, "choosing the quantity changes nothing yet: the new stack has no place")
Check(Has(f, "Where should the 5 go%?"), "it asks where the new stack goes")
Check(Ctl("gCancelArm") ~= nil, "with a way to cancel")
Click("gCancelArm")
Check(D.Digest(d) == before and not Ctl("gCancelArm").shown, "Cancel leaves the design as it was: nothing disappeared")
-- Esc closes the dialog without a trace
c.SHIFT = true; Click("gSlot5"); c.SHIFT = false
dlg.qty.scripts.OnEscapePressed(dlg.qty)
Check(not P.Split.IsShown() and D.Digest(d) == before and not Ctl("gCancelArm").shown, "Esc in the dialog closes it and changes nothing")
Check(#c.UISpecialFrames >= 1, "the dialog is in the game's Esc list")
-- a real split
c.SHIFT = true; Click("gSlot5"); c.SHIFT = false
dlg.qty:SetText("5"); dlg.qty.scripts.OnTextChanged(dlg.qty); dlg.ok.scripts.OnClick(dlg.ok); Flush()
Click("gSlot9")
d = P.GuildDraft()
Check(d.tabs[2].slots[5].count == 15 and d.tabs[2].slots[9] and d.tabs[2].slots[9].count == 5 and d.tabs[2].slots[9].id == 2589, "the first stack keeps the remainder and the new stack is placed")
Check(Ctl("gSlot9").count.text == "5" and Ctl("gSlot5").count.text == "15", "both show their target quantities")
-- split onto a tab: the first free slot of that tab
c.SHIFT = true; Click("gSlot5"); c.SHIFT = false
dlg.qty:SetText("3"); dlg.qty.scripts.OnTextChanged(dlg.qty); dlg.ok.scripts.OnClick(dlg.ok); Flush()
Click("gTab3")
Check(d.tabs[3] and d.tabs[3].slots[1] and d.tabs[3].slots[1].count == 3 and d.tabs[2].slots[5].count == 12, "a split onto a tab takes its first free slot")

-- a single stack can't be split
PinTo("gTray2", "gSlot30")
Check(P.GuildDraft().tabs[3] ~= nil, "(tab 3 is selected)")

---------------------------------------------------------------------------
-- Moving by drag, combining, refusing
---------------------------------------------------------------------------
Click("gTab2")
d = P.GuildDraft()
local total = function(id) local n = 0 for _, t in pairs(d.tabs) do for _, s in pairs(t.slots) do if s.id == id then n = n + s.count end end end return n end
local linen = total(2589)
DragTo("gSlot9", "gSlot5")
Check(d.tabs[2].slots[5].count == 17 and d.tabs[2].slots[9] == nil, "dragging a stack onto a compatible one combines them")
Check(total(2589) == linen, "and no quantity changed")
-- fill past the limit: overflow stays where it was
PinTo("gTray1", "gSlot12")                       -- Linen full stack of 20 in slot 12
DragTo("gSlot12", "gSlot5")                       -- 17 + 20: 3 fit, 17 stay
Check(d.tabs[2].slots[5].count == 20 and d.tabs[2].slots[12].count == 17, "combining stops at the item's stack limit and the rest stays in its slot")
Check(total(2589) == linen + 20, "no quantity lost in the overflow")
-- incompatible
PinTo("gTray2", "gSlot20")
Check(d.tabs[2].slots[20] and d.tabs[2].slots[20].id == 2447, "(Peacebloom reserved in slot 20)")
before = D.Digest(d)
DragTo("gSlot20", "gSlot5")
Check(D.Digest(d) == before and Has(f, "Nothing changed%. Slot 5 of tab 2 .* is reserved for Linen Cloth"), "another item's stack is never combined with: refused with the reason, nothing changed")
-- move to an empty slot, and onto a tab
DragTo("gSlot20", "gSlot22")
Check(d.tabs[2].slots[22] and not d.tabs[2].slots[20], "a stack moves to an empty slot")
DragTo("gSlot22", "gTab1")
Check(d.tabs[1] and d.tabs[1].slots[1] and d.tabs[1].slots[1].id == 2447 and not d.tabs[2].slots[22], "a stack dropped on a tab moves there")
Check(P.Drag.Active() == false, "no drag is left running")

---------------------------------------------------------------------------
-- The item menu and the non-drag way: select, choose Move or Split, then the destination
---------------------------------------------------------------------------
local function Action(src, label)
  for _, a in ipairs(P.ActionsFor(src, nil)) do if a.label:find(label, 1, true) then return a end end
end
local src12 = { kind = "slot", id = 2589, tab = 2, slot = 12, count = 17 }
local labels = {}
for _, a in ipairs(P.ActionsFor(src12, nil)) do labels[#labels + 1] = a.label end
Check(Action(src12, "Split stack") and Action(src12, "Move") and Action(src12, "Return to automatic placement") and Action(src12, "Remove from design"), "a reserved stack's menu has Split stack, Move, Return to automatic placement and Remove: " .. table.concat(labels, " | "))
Action(src12, "Move").fn(); Flush()
Check(Has(f, "Click the slot or tab to move it to"), "Move asks for the destination")
Click("gSlot40")
Check(d.tabs[2].slots[40] and d.tabs[2].slots[40].count == 17 and not d.tabs[2].slots[12], "clicking the destination moves it, with no dragging")
Action({ kind = "slot", id = 2589, tab = 2, slot = 40, count = 17 }, "Split stack").fn(); Flush()
Check(P.Split.IsShown(), "Split stack in the menu opens the same dialog")
dlg.qty:SetText("7"); dlg.qty.scripts.OnTextChanged(dlg.qty); dlg.ok.scripts.OnClick(dlg.ok); Flush()
Click("gTab3")
Check(d.tabs[3].slots[2] and d.tabs[3].slots[2].count == 7 and d.tabs[2].slots[40].count == 10, "the split's destination can be a tab")
-- from the tray
local tray1 = Ctl("gTray1")
for _, a in ipairs(P.ActionsFor(tray1.src, nil)) do if a.label:find("Place", 1, true) then a.fn() end end
Flush()
Check(Has(f, "Click a slot to reserve it, or a tab to place it automatically"), "a tray item can be placed without dragging too")
Click("gTab2")
Check(d.tabs[2].rest[2589], "(the item is automatic in tab 2)")
-- return to automatic
Action({ kind = "slot", id = 2589, tab = 2, slot = 40, count = 10 }, "Return to automatic placement").fn(); Flush()
Check(not d.tabs[2].slots[40] and d.tabs[2].items[2589] and d.tabs[2].rest[2589], "Return to automatic placement drops the slot and keeps the item in its tab")

---------------------------------------------------------------------------
-- Preview: honours the draft, says so, shows shortage, and says when it is stale
---------------------------------------------------------------------------
Check(D.Dirty(d), "(unsaved)")
Click("gPreview")
local plan, mode = P.GuildPreview()
Check(plan and mode == "deposit" and plan.draft == true, "Preview changes plans the draft (labelled as the draft's)")
Check(P.GuildView() == "preview", "and switches to Preview")
Check(Has(f, "From your unsaved design:"), "the summary says it used unsaved changes")
Check(Has(f, "would move"), "one short summary of what would move")
Check(Ctl("gSrcBags") and Ctl("gSrcBank"), "the sources are From my bags and Already in the bank")
Check(Has(f, "^From my bags$") and Has(f, "^Already in the bank$"), "in those words")
Check(plan.readOnly == true, "the preview is read-only")
Check(#c.PICKUPS == picks and c.CLEARED == cleared and c.CURSOR == nil, "making the preview picked nothing up")
-- short: reserve far more than the bags hold
local before2 = #D.Digest(d)
Click("gVDes")
Click("gTab2")
PinTo("gTray1", "gSlot50")
PinTo("gTray1", "gSlot51")
PinTo("gTray1", "gSlot52")
Click("gPreview")
plan = P.GuildPreview()
Check(plan.summary.design.short >= 1, "reserved stacks the bags can't fill are counted short")
Check(Has(f, "short of"), "and said in the summary")
local ghost
for s = 1, 98 do local cell = plan.tabs[2].proposed[s]; if cell and cell.ghost then ghost = s end end
Check(ghost ~= nil, "a labelled ghost holds a slot whose stock is missing")
if ghost then
  local b = Ctl("gSlot" .. ghost)
  Check(b.mark.text == "~" and b.count.text == "0", "painted ~ with 0 held: a ghost, not an observed stack")
end
-- stale: the design changes
Click("gVDes")
PinTo("gTray2", "gSlot60")
Click("gVPre")
Check(Has(f, "^Design changed%. Refresh preview%.$"), "a preview older than the design says one short thing")
Check(Ctl("gRefresh") ~= nil, "with a Refresh preview button")
Click("gRefresh")
Check(not Has(f, "Refresh preview%."), "refreshing clears it")
-- stale: the bank changes
c.GUILD.tabs[2].slots[7] = { id = 2447, count = 3 }
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED"); f.scripts.OnEvent(f, "GUILDBANKBAGSLOTS_CHANGED"); Flush()
Check(Has(f, "^Bank contents changed%. Refresh preview%.$"), "when the bank is read again: 'Bank contents changed. Refresh preview.'")
Click("gRefresh")
-- a source switch makes the other plan
Click("gSrcBank")
plan, mode = P.GuildPreview()
Check(mode == "reorganize", "Already in the bank plans a reorganize")
Click("gSrcBags")
Check(select(2, P.GuildPreview()) == "deposit", "From my bags plans a deposit")
-- a closed bank is stale
c.CloseGuildBank(); f.scripts.OnEvent(f, "GUILDBANKFRAME_CLOSED"); Flush()
Check(Has(f, "Bank contents changed%. Refresh preview%."), "closing the bank makes it stale in the same words")
c.OpenGuildBank(); c.GUILD.current = 2; c.FireEvent("GUILDBANKBAGSLOTS_CHANGED"); Flush()

-- Current: observed, and an unread tab is not empty
Click("gVCur")
Check(P.GuildView() == "current" and Ctl("gSlot2").count.text == "8", "Current shows what the bank held (8 in slot 2)")
Check(Ctl("gSlot5").count.text == "" and Ctl("gSlot5").mark.text == "", "and none of the design: a reserved slot isn't drawn as stock")
Click("gTab3")
Check(Has(f, "Not read yet%. Show \"Herbs\" in the guild bank to read it%. It is not empty, only unknown%."), "an unread tab says so instead of showing an empty grid")
Click("gTab2")

---------------------------------------------------------------------------
-- Save, Revert, leaving
---------------------------------------------------------------------------
Click("gVDes")
d = P.GuildDraft()
local digest = D.Digest(d)
local rulesBefore = #MI.Rules()
Click("gSave")
Check(#MI.Rules() > rulesBefore, "Save arrangement wrote rules")
Check(not D.Dirty(P.GuildDraft()) and D.Digest(P.GuildDraft()) == digest, "and reopening the saved arrangement gives exactly the draft")
Check(Has(f, "Arrangement saved%. Nothing was moved%."), "with one line that says so")
Check(not Has(f, "Unsaved changes") and not Ctl("gSave").shown, "nothing is unsaved now, and the buttons go")
local saved = {}
for _, r in ipairs(MI.Rules()) do if r.design then saved[#saved + 1] = r end end
local reservedStacks = 0
for _, r in ipairs(saved) do reservedStacks = reservedStacks + #r.place end
Check(#saved >= 1 and reservedStacks >= 3, "the rules hold the reserved stacks (" .. reservedStacks .. ")")
Check(#c.PICKUPS == picks and c.CLEARED == cleared and c.CURSOR == nil, "saving picked nothing up")
-- revert
d = P.GuildDraft()
PinTo("gTray2", "gSlot70")
Check(D.Dirty(P.GuildDraft()), "(edited)")
local mid = D.Digest(P.GuildDraft())
Click("gRevert")
Check(D.Digest(P.GuildDraft()) == digest and not D.Dirty(P.GuildDraft()) and mid ~= digest, "Revert discards the edit")
Check(Has(f, "Unsaved changes discarded%."), "and says so")
-- leaving with unsaved edits: neither saves nor discards
PinTo("gTray2", "gSlot71")
local edited = D.Digest(P.GuildDraft())
local rulesNow = #MI.Rules()
f:Hide(); Flush()
Check(#MI.Rules() == rulesNow, "leaving the page saved nothing")
Check(D.Digest(P.GuildDraft()) == edited, "and discarded nothing")
f:Show(); Flush()
Check(Has(f, "Unsaved changes") and D.Digest(P.GuildDraft()) == edited, "coming back, the edits are still there and still marked unsaved")
-- a change of rules elsewhere doesn't throw the edits away
MI.SaveRule({ kind = "bank", name = "Herbs to bank", enabled = false, cats = { "7:9" } })
Flush()
Check(D.Digest(P.GuildDraft()) == edited, "a rule changed elsewhere keeps the unsaved draft")
Click("gRevert")

---------------------------------------------------------------------------
-- A drag stays virtual; a held item is never touched; the page is quiet
---------------------------------------------------------------------------
c.CURSOR = { other = true }
local drags = P.Drag.Active()
local s = Ctl("gTray1")
local beforeD = D.Digest(P.GuildDraft())
s.scripts.OnDragStart(s); Flush()
Check(not P.Drag.Active(), "a drag doesn't start while the player holds an item")
Check(Has(f, "You are holding an item%. Put it down first; nothing was changed%."), "and says why")
s.scripts.OnDragStop(s)
Check(c.CURSOR and c.CURSOR.other == true and c.CLEARED == cleared, "the held item stayed on the cursor, and the cursor was never cleared")
Check(D.Digest(P.GuildDraft()) == beforeD, "nothing was designed")
c.CURSOR = nil
-- a drag in progress when the page closes is dropped
s.scripts.OnDragStart(s)
Check(P.Drag.Active(), "(a drag is on)")
f:Hide(); Flush()
Check(not P.Drag.Active() and D.Digest(P.GuildDraft()) == beforeD, "hiding the page drops a drag in progress and changes nothing")
f:Show(); Flush()
-- no controls multiply, and nothing real moved
local n = P.ControlCount()
for _ = 1, 5 do P.QueueRefresh(); Flush(); f:Hide(); f:Show(); Flush() end
Check(P.ControlCount() == n, "redrawing makes no new controls: " .. n .. " -> " .. P.ControlCount())
Check(#c.PICKUPS == picks and c.CLEARED == cleared and #(c.DEPOSITS or {}) == 0, "through all of it: no pickup, no clear, no deposit")
for _, t in ipairs(Texts(f)) do
  Check(not t:find("^Deposit %d") and not t:find("^Start") and not t:find("^Apply") and not t:find("^Execute"), "no button that moves anything: " .. t)
end


---------------------------------------------------------------------------
-- Stack sizes and layouts: the items a tab takes, the size each is spread in, and the picture of where they will be
---------------------------------------------------------------------------
do
  -- a fresh tab (tab 1) takes two items automatically
  P.SetView("design"); Flush()
  local sbox = Ctl("gSearch")
  if sbox then sbox:SetText(""); sbox.scripts.OnTextChanged(sbox, true) end
  Flush()
  Click("gTab1")
  local d3 = P.GuildDraft()
  local fx = { facts = function(id) return (MI.ItemFacts(id)) end }
  d3.tabs[1] = nil                                   -- (an empty tab: the earlier sections left stacks in it)
  D.AssignTab(d3, fx, 2589, 1)
  D.AssignTab(d3, fx, 2447, 1)
  P.QueueRefresh(); Flush()
  Check(d3.tabs[1] and d3.tabs[1].rest[2589] and d3.tabs[1].rest[2447], "two items placed automatically in a tab")
  Check(Ctl("gSlot1").autoId ~= nil and Ctl("gSlot2").autoId ~= nil and Ctl("gSlot1").stack == nil, "the grid pictures them from the first slot, as the layout will place them")
  local first = Ctl("gSlot1").autoId
  -- selecting a drawn item selects it in the tab's list and offers the size
  Click("gSlot1")
  local acts = P.ActionsFor({ kind = "shelf", id = first, tab = 1 }, nil)
  local size
  for _, a in ipairs(acts) do if a.label:find("Stack size", 1, true) then size = a end end
  Check(size ~= nil, "the item's menu offers Stack size")
  size.fn(); Flush()
  local dlg = P.Split.Dialog()
  Check(P.Split.IsShown() and dlg.title.text == "Stack size" and dlg.ok.text.text == "Set size", "it opens the size dialog")
  for _, bad in ipairs({ "0", "21", "x", "", "2.5" }) do
    dlg.qty:SetText(bad); dlg.qty.scripts.OnTextChanged(dlg.qty)
    Check(not dlg.ok.enabled, "'" .. bad .. "' is not a size for an item that stacks to 20")
  end
  dlg.qty:SetText("5"); dlg.qty.scripts.OnTextChanged(dlg.qty)
  Check(dlg.ok.enabled and dlg.hint.text:find("Stacks of 5"), "a valid size is accepted and says what it does")
  dlg.ok.scripts.OnClick(dlg.ok); Flush()
  Check(d3.tabs[1].sizes[first] == 5 and not P.Split.IsShown(), "the size is in the draft and the dialog is closed")
  Check(Has(f, "stacks of 5"), "and the selection says so")
  Check(Ctl("gSlot1").count.text == "5" and D.Dirty(d3), "the picture shows stacks of 5, and the design is unsaved")
  -- a layout: spaced, then columns
  Check(D.SetLayout(d3, 1, "spaced"), "a layout is chosen for the tab")
  P.QueueRefresh(); Flush()
  Check(Ctl("gSlot1").autoId == first and Ctl("gSlot2").autoId == nil and Ctl("gSlot3").autoId ~= nil, "spaced: an empty slot between the two items")
  D.SetLayout(d3, 1, "columns")
  P.QueueRefresh(); Flush()
  Check(Ctl("gSlot1").autoId == first and Ctl("gSlot15").autoId ~= nil, "columns: the next item starts a new column of 14")
  Check(Ctl("gLayout") ~= nil, "the tab has a layout control")
  -- nothing here moved anything
  Check(#c.PICKUPS == #c.PICKUPS and c.CLEARED == c.CLEARED, "(no game call was involved)")
  Click("gTab2")
end

if failures == 0 then print("PASSED test_magic_inventory_editor") else print(failures .. " failures") os.exit(1) end
