-- Magic Inventory's settings page (TwichUI_Settings/pages/MagicInventory.lua) with stand-in frames:
--   * the rule list in plain words (items, destination, keep), the template list, an empty state;
--   * a template opens the four-step editor; it saves turned off while its recipient isn't chosen, and says why;
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
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua" }) do
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
Check(Has(f, "^Never transfer$") and Has(f, "Destinations on this character"), "destinations and the Never transfer list")

-- a template opens the editor
P.NewFromTemplate("cloth")
Flush()
Check(P.Editing() ~= nil and Has(f, "^New rule$"), "the editor opens")
Check(Has(f, "^1  Items$") and Has(f, "^4  Review$"), "four steps")
Check(P.Control("e1cat1") and P.Control("e1cat1"):GetChecked(), "the template's category is ticked")
Check(Has(f, "^Cloth"), "named as the game names it")
Click("eNext"); Click("eNext"); Click("eNext")
Check(Has(f, "Send by mail .* Bank alt %(choose the recipient on this character%)"), "the review names the destination and what is missing")
Check(Has(f, "Can't be turned on yet"), "and says it can't be turned on yet")
Check(Has(f, "Whether a player can receive these, or who plays that character, isn't something TwichUI can check"), "honest about recipients")
Click("eSave")
Check(P.Editing() == nil, "saved")
local rule = MI.Rules()[1]
Check(rule and rule.name == "Cloth to bank alt" and rule.enabled == false and rule.keep == 20, "saved turned off, keeping 20 of each")
Check(Has(f, "Items: Cloth") and Has(f, "Keep: 20 of each matching item"), "the list says it plainly")
Check(Has(f, "choose the recipient on this character"), "and what it needs")

-- turning it on is refused, with the reason
local box = P.Control("rule1on")
box.scripts.OnClick(box, "LeftButton"); Flush()
Check(not MI.Rules()[1].enabled and Has(f, "Choose the recipient for \"Bank alt\" on this character"), "refused with the reason")

-- the recipient, for this character only
local rb = P.Control("dest1box")
rb:SetText("bankalt")
Click("dest1set")
local where = MI.Resolve(rule.dest)
Check(where and where.recipient == "Bankalt" and not where.shared, "the recipient is set here, in the game's capitalization")
Check(Has(f, "now mails to Bankalt on this character"), "and the page says exactly who")
box = P.Control("rule1on")
box.scripts.OnClick(box, "LeftButton"); Flush()
Check(MI.Rules()[1].enabled, "now it can be turned on")
rb = P.Control("dest1box"); rb:SetText("Bad Name")
Click("dest1set")
Check(MI.Resolve(rule.dest).recipient == "Bankalt" and Has(f, "only letters"), "a name that isn't one is refused and the old one kept")

-- the Never transfer list through the bag chooser: kinds only, nothing moves
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
Click("rule1edit")
P.Control("eName"):SetText("Something else")
P.Control("eName").scripts.OnTextChanged(P.Control("eName"))
Click("eCancel")
Check(MI.Rules()[1].name == before, "Cancel keeps the rule as it was")

-- delete asks first
Click("rule1del")
Check(c.POPUP and c.POPUP.text:find("Delete the rule \"Cloth to bank alt\"") and c.POPUP.text:find("nothing in your bags, bank or mail changes"), "deleting asks, saying what it changes")
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
Click("eTab2"); Click("e2kguild")
Click("eTab3")
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

-- a rule to preview
local cloth = MI.SaveRule({ kind = "guild", name = "Cloth to tab 2", enabled = true, dest = gdest, cats = { "7:5" }, stack = 20 })
Flush()
Check(MI.Rule(cloth).enabled, "the guild rule is on")
Check(Has(f, "Target stack size: 20"), "the list shows the target")
-- the guild bank arrangement editor has its own test (test_magic_inventory_editor.lua)
Check(Has(f, "Guild bank arrangement") and Has(f, "Editing is design only"), "the page leads with the arrangement and says editing is design only")
Check(P.Control("gPreview") ~= nil, "and has one primary action, Preview changes")
n = P.ControlCount()
for _ = 1, 5 do P.QueueRefresh(); Flush(); f:Hide(); f:Show(); Flush() end
Check(P.ControlCount() == n, "redrawing the page makes no new controls: " .. n .. " -> " .. P.ControlCount())
Check(#c.PICKUPS == 0 and c.CURSOR == nil, "and nothing was picked up")

if failures == 0 then print("PASSED test_magic_inventory_settings") else print(failures .. " failures") os.exit(1) end
