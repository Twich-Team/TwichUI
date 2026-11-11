-- Magic Inventory's settings page (TwichUI_Settings/pages/MagicInventory.lua) with stand-in frames:
--   * the rule list in plain words (items, destination, keep), the template list, an empty state;
--   * a template opens the goal-based private builder; it saves turned off while its recipient isn't chosen, and says why;
--   * the recipient is set for this character only, exactly as typed (in the game's capitalization), then the rule
--     can be turned on; the Never transfer list and a rule's lists come from the bag chooser without moving anything;
--   * deleting asks first; redrawing again and again makes no new controls.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich", {
  db = { modules = { magicInventory = true } },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = MIFake(kind, parent); if name then cl[name] = fr end return fr end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = MI_FILES,
})
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function(name, text) c.POPUP = { name = name, text = text }; return {} end
for _, file in ipairs({ "../TwichUI_Settings/Kit.lua", "../TwichUI_Settings/Widgets.lua", "../TwichUI_Settings/pages/MagicInventory.lua", "../TwichUI_Settings/pages/MagicInventoryDrag.lua", "../TwichUI_Settings/pages/MagicInventoryGuild.lua" }) do
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("TwichUI_Settings", {})
end
TIP = {}
c.GameTooltip.SetText = function(_, t) TIP[#TIP + 1] = t end
c.GameTooltip.AddLine = function(_, t) TIP[#TIP + 1] = t end
local R = c.TwichUI
local MI = R.MagicInventory
local P = R.MagicInventoryPage
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
local function Click(key) local b = P.Control(key); Check(b and b.shown, "control " .. key .. " is there"); if b then b.scripts.OnClick(b, "LeftButton") end; Flush() end

c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local f = P.Frame()
f:Hide(); f:Show()
Flush()
Check(Has(f, "^Your rules$") and Has(f, "No rules yet"), "an empty list says how to start")
Check(P.Task() == "rules" and not Has(f, "^Never transfer$"), "rules are the initial focused task")
Check(P.SetTask("destinations"), "destination task is available"); Flush()
Check(Has(f, "Destinations on this character"), "destinations have their own view")
P.SetTask("protected"); Flush()
Check(Has(f, "^Never transfer$"), "protected items have their own view")
P.SetTask("rules"); Flush()

-- a template opens the editor
P.NewFromTemplate("cloth")
Flush()
Check(P.Editing() ~= nil and Has(f, "^New rule$"), "the editor opens")
Check(Has(f, "^What items%?$") and Has(f, "^Rule review$"), "cohesive builder sections")
Click("moreItemFilters")
Check(not P.Control("e1cat1") or not P.Control("e1cat1").shown, "the long category catalog is initially disclosed")
Check(Has(f, "^Cloth"), "selected categories are readable without opening the catalog")
Click("e1chooseCats")
Check(P.Control("e1cat1") and P.Control("e1cat1"):GetChecked(), "the template's category is ticked")
Check(Has(f, "^Cloth"), "named as the game names it")
Click("e1chooseCats")
Check(not P.Control("e1cat1").shown and P.Editing() ~= nil, "closing the catalog retains the private rule")
Click("advancedDestination")
Check(Has(f, "Destination: Bank alt") and Has(f, "Needs attention"), "the review names the destination and what is missing")
Check(Has(f, "Needs attention"), "and says it can't be turned on yet")
TIP = {}; P.Control("reviewPanel").scripts.OnEnter(P.Control("reviewPanel"))
Check(table.concat(TIP, " "):find("Whether a player can receive these", 1, true), "review help is honest about recipients")
Click("eSave")
Check(P.Editing() == nil, "saved")
local rule = MI.Rules()[1]
Check(rule and rule.name == "Cloth to bank alt" and rule.enabled == false and rule.keep == 20, "saved turned off, keeping 20 of each")
Check(Has(f, "Cloth to bank alt") and Has(f, "^Cloth") and Has(f, "Keep 20"), "a rule card says what it matches and what it keeps")
Check(Has(f, "Mail") and Has(f, "Bank alt"), "the destination and missing configuration are visible without hover")
local row1 = P.Control("tr1")
row1.scripts.OnEnter(row1)
local tipText = table.concat(TIP, "\n")
Check(tipText:find("Items: Cloth") and tipText:find("Keep: 20 of each matching item") and tipText:find("choose the recipient on this character"), "the row's tooltip says it plainly, and what it needs")
row1.scripts.OnLeave(row1)

-- Filtering retains absolute priorities and cannot reorder hidden rules.
local savedBeforeFilter = MI.Rules()[1].id
local search = P.Control("findRule")
search:SetText("Cloth"); search.scripts.OnTextChanged(search); Flush()
Check(P.Control("tr1").index == 1, "filtered priority stays absolute")
P.StartRuleDrag(P.Control("tr1")); Check(not P.Drag.Active(), "filtered drag is rejected")
search:SetText(""); search.scripts.OnTextChanged(search); Flush()
Check(MI.Rules()[1].id == savedBeforeFilter, "search never changes order")

-- turning it on is refused, with the reason
local box = P.Control("rule1on")
box.scripts.OnClick(box, "LeftButton"); Flush()
Check(not MI.Rules()[1].enabled and Has(f, "Choose the recipient for \"Bank alt\" on this character"), "refused with the reason")

-- the recipient, for this character only
P.SetTask("destinations"); Flush()
local rb = P.Control("dest1box")
rb:SetText("bankalt")
Click("dest1set")
local where = MI.Resolve(rule.dest)
Check(where and where.recipient == "Bankalt" and not where.shared, "the recipient is set here, in the game's capitalization")
Check(Has(f, "now mails to Bankalt on this character"), "and the page says exactly who")
P.SetTask("rules"); Flush()
box = P.Control("rule1on")
box.scripts.OnClick(box, "LeftButton"); Flush()
Check(MI.Rules()[1].enabled, "now it can be turned on")
P.SetTask("destinations"); Flush()
rb = P.Control("dest1box"); rb:SetText("Bad Name")
Click("dest1set")
Check(MI.Resolve(rule.dest).recipient == "Bankalt" and Has(f, "only letters"), "a name that isn't one is refused and the old one kept")

-- the Never transfer list through the bag chooser: kinds only, nothing moves
P.SetTask("protected"); Flush()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2447, 5 } } } })
Click("neverPick")
Check(MI.Picker.IsShown(), "the bag chooser opens")
MI.Picker.Toggle(2447)
MI.Picker.Done()
Flush()
Check(MI.IsNever(2447) and not MI.IsNever(2589), "the chosen kind is on the Never transfer list")
Check(#c.PICKUPS == 0, "nothing was picked up")

-- redrawing makes no new controls
local n = P.ControlCount()
for _ = 1, 5 do P.QueueRefresh(); Flush(); f:Hide(); f:Show(); Flush() end
Check(P.ControlCount() == n, "no new controls after redrawing: " .. n .. " -> " .. P.ControlCount())

-- editing then cancelling changes nothing
local before = MI.Rules()[1].name
P.SetTask("rules"); Flush()
Click("rule1edit")
Check(not P.SetTask("destinations"), "a private editor requires Save or Cancel before changing tasks")
P.Control("eName"):SetText("Something else")
P.Control("eName").scripts.OnTextChanged(P.Control("eName"))
Click("eCancel")
Check(MI.Rules()[1].name == before, "Cancel keeps the rule as it was")

-- delete asks first
Click("rule1more")
P.Control("rule1more").onPick("delete"); Flush()
Check(c.POPUP and c.POPUP.text:find("Cloth to bank alt") and c.POPUP.text:find("no items move"), "deleting asks, saying what it changes")
Check(#MI.Rules() == 1, "nothing deleted before the answer")
c.StaticPopupDialogs.TWICHUI_MI_RULE_DELETE.OnAccept()
Flush()
Check(#MI.Rules() == 0, "deleted after the answer")

---------------------------------------------------------------------------
-- The guild bank: a tab chosen from what the bank showed, a target stack size, and the read-only placement previews
---------------------------------------------------------------------------
c.GUILD.name = "Night Owls"
c.GUILD.tabs = {
  [1] = { name = "Gear", icon = 5, withdraw = -1, slots = {} },
  [2] = { name = "Cloth", icon = 133, withdraw = -1, slots = { [2] = { id = 2589, count = 8 } } },
}
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 15 } } } })
c.OpenGuildBank()
c.GUILD.current = 2
c.FireEvent("GUILDBANKBAGSLOTS_CHANGED")
local gdest = MI.AddDest("guild", "Cloth tab")
P.SetTask("destinations")
Flush()
local di
for i, d in ipairs(MI.Dests()) do if d.id == gdest then di = i end end
local tabsKey = "dest" .. di .. "tabs"
Check(P.Control(tabsKey) ~= nil, "a guild destination offers a tab chooser")
P.Control(tabsKey).onPick(2)
Flush()
local gw = MI.Resolve(gdest)
Check(gw and gw.tab == 2 and gw.tabName == "Cloth" and gw.tabIcon == 133 and gw.guild == "Night Owls", "a tab chosen from the tabs the bank showed: its guild, number, name and icon are kept")
Check(Has(f, "tab 2 .*Cloth"), "and shown with its name")
c.CloseGuildBank()
Flush()
P.Control(tabsKey).onPick(1)
Flush()
Check(MI.Resolve(gdest).tab == 1 and MI.Resolve(gdest).tabName == "Gear", "with the bank closed a tab can still be chosen by name (from when it was last open)")
P.Control(tabsKey).onPick(2)
Flush()
-- the target stack size in the editor
P.NewFromTemplate("custom")
Flush()
Click("advancedDestination"); Click("e2kguild")
Click("advancedLimits")
Check(P.Control("e3stackN") ~= nil and Has(f, "^Target stack size$"), "a guild bank rule has a Target stack size")
local sb = P.Control("e3stackN")
sb:SetText("25"); sb.scripts.OnEnterPressed(sb); Flush()
Check(P.Editing().stack == 25, "a typed size is kept")
sb = P.Control("e3stackN"); sb:SetText("abc"); sb.scripts.OnEnterPressed(sb); Flush()
Check(P.Editing().stack == 25 and Has(f, "whole number from 0 to"), "text that isn't a number is refused and the size kept")
sb = P.Control("e3stackN"); sb:SetText("99999"); sb.scripts.OnEnterPressed(sb); Flush()
Check(P.Editing().stack == 25, "a size above the largest is refused")
Click("e3stackOn")
Check(P.Editing().stack == 0, "unticking it means no target")
Click("e3stackOn")
Check(P.Editing().stack == 20, "ticking it starts at 20")
Click("eCancel")

-- a rule that withdraws: the editor asks which way, the keep amount becomes the target, and the words say it never goes over
P.NewFromTemplate("custom")
Flush()
Click("advancedDestination"); Click("e2kbank")
Check(Has(f, "^Which way$") and P.Control("e2fwithdraw") ~= nil and P.Control("e2fbalance") ~= nil, "a bank rule asks which way")
Click("e2fwithdraw")
Check(P.Editing().flow == "withdraw" and P.Editing().keep == 20, "withdrawing starts with a target of 20")
Click("advancedLimits")
Check(Has(f, "^Target in bags$") and Has(f, "never goes over"), "the keep amount is the target, and it says it never goes over")
Flush()
TIP = {}; P.Control("reviewPanel").scripts.OnEnter(P.Control("reviewPanel"))
Check(Has(f, "Behavior: Withdraw") and table.concat(TIP, " "):find("never more", 1, true), "structured review and help describe withdrawal limits")
Click("eCancel")
do
  local wid = MI.SaveRule({ kind = "bank", name = "Keep 40 milk", enabled = false, cats = { "0:5" }, flow = "balance", keep = 40 })
  Flush()
  Check(Has(f, "Balance") and Has(f, "Bank") and Has(f, "Keep 40"), "the rule card shows balance and its target in words")
  MI.DeleteRule(wid)
  Flush()
end

-- a rule to preview
local cloth = MI.SaveRule({ kind = "guild", name = "Cloth to tab 2", enabled = true, dest = gdest, cats = { "7:5" }, stack = 20 })
Flush()
Check(MI.Rule(cloth).enabled, "the guild rule is on")
TIP = {}
local grow = P.Control("tr1")
grow.scripts.OnEnter(grow)
Check(table.concat(TIP, "\n"):find("Target stack size: 20"), "the row's tooltip shows the target")

-- the table is reordered by dragging a row: the rule lands where it is let go, and letting go elsewhere changes nothing
do
  local extra = MI.SaveRule({ kind = "bank", name = "Herbs to bank", enabled = false, cats = { "7:9" } })
  local third = MI.SaveRule({ kind = "bank", name = "Ore to bank", enabled = false, cats = { "7:7" } })
  Flush()
  local function Names() local out = {} for _, r in ipairs(MI.Rules()) do out[#out + 1] = r.name end return table.concat(out, ",") end
  local before = Names()
  local r1, r3 = P.Control("tr1"), P.Control("tr3")
  r1.scripts.OnDragStart(r1)
  Check(P.Drag.Active() and P.Drag.Source().id == MI.Rules()[1].id, "pressing and moving on a row starts a drag of that rule")
  r1.scripts.OnDragStop(r1); Flush()
  Check(not P.Drag.Active() and Names() == before, "letting go over no row changes nothing")
  r3.IsMouseOver = function() return true end
  r1.scripts.OnDragStart(r1)
  r1.scripts.OnDragStop(r1); Flush()
  r3.IsMouseOver = nil
  Check(Names() == "Herbs to bank,Ore to bank,Cloth to tab 2", "dropping the first rule on the third row puts it third: " .. Names())
  Check(Has(f, "Moved .* to place 3"), "and the page says so")
  r1 = P.Control("tr1")
  r1.IsMouseOver = function() return true end
  P.Control("tr3").scripts.OnDragStart(P.Control("tr3"))
  P.Control("tr3").scripts.OnDragStop(P.Control("tr3")); Flush()
  r1.IsMouseOver = nil
  Check(Names() == before, "dropping the third on the first puts it first again: " .. Names())
  Check(extra and third and #MI.Rules() == 3, "no rule lost or copied by dragging")
  -- the page is hidden mid-drag: the drag is put away
  P.Control("tr1").scripts.OnDragStart(P.Control("tr1"))
  f:Hide(); f:Show(); Flush()
  Check(not P.Drag.Active(), "hiding the page ends a drag")
  MI.DeleteRule(extra); MI.DeleteRule(third); Flush()
end

-- Goal-based controls edit only the private draft and save through the same schema.
local savedCount = #MI.Rules()
P.NewFromTemplate("custom"); Flush()
Click("quickCategory1")
Check(#P.Editing().cats >= 2, "cloth/herbs uses category criteria")
Click("quickCategory3")
Check(P.Editing().equip == "equipment", "equipment uses the existing equipment filter")
Click("destinationChoicebank"); Click("flowChoicebalance")
Check(P.Editing().kind == "bank" and P.Editing().flow == "balance", "destination and movement selectors edit the draft")
local originalKeep = P.Editing().keep
Click("keepPlus"); Check(P.Editing().keep == originalKeep + 1, "quantity stepper edits the draft")
Check(#MI.Rules() == savedCount, "draft changes do not allocate a rule")
Click("eCancel"); Check(#MI.Rules() == savedCount, "cancel discards the private changes")

P.NewFromTemplate("custom"); Flush()
Click("builderBack")
Check(P.Editing() ~= nil and c.POPUP.name == "TWICHUI_MI_DISCARD_DRAFT", "Back asks before discarding a draft")
c.StaticPopupDialogs.TWICHUI_MI_DISCARD_DRAFT.OnAccept(); Flush()
Check(P.Editing() == nil and #MI.Rules() == savedCount, "discard changes no saved rule")
Click("rule1edit"); Click("builderDuplicate")
Check(P.Editing() and not P.Editing().id and #MI.Rules() == savedCount, "builder duplicate is an independent unsaved draft")
Click("eCancel")

-- the guild bank arrangement editor has its own test (test_magic_inventory_editor.lua)
P.SetTask("guild"); Flush()
Check(Has(f, "Guild bank arrangement") and Has(f, "Editing is design only"), "the page leads with the arrangement and says editing is design only")
Check(P.Control("gPreview") ~= nil, "and has one primary action, Preview changes")
n = P.ControlCount()
for _ = 1, 5 do P.QueueRefresh(); Flush(); f:Hide(); f:Show(); Flush() end
Check(P.ControlCount() == n, "redrawing the page makes no new controls: " .. n .. " -> " .. P.ControlCount())
Check(#c.PICKUPS == 0 and c.CURSOR == nil, "and nothing was picked up")

if failures == 0 then print("PASSED test_magic_inventory_settings") else print(failures .. " failures") os.exit(1) end
