-- Magic Inventory's direct mail recipient (inventory/Rules.lua PlanRecipient / SaveRuleDraft and the rule builder in
-- TwichUI_Settings/pages/MagicInventory.lua), with stand-in frames and synthetic data only. Nothing is sent and no
-- item is moved; the mailbox review is opened and read, never acted on.
--   1-6  the acceptance path: a rule for herbs, "Mail to...", the recipient typed in the builder, a keep amount, a
--        plain review, Save, and the recipient shown on the saved rule's row;
--   7    editing the recipient and cancelling (Cancel, Back, Escape/closing, a profile change) leaves everything saved alone;
--   8    two rules sharing a destination: changing one leaves the other's recipient; the shared change is explicit;
--   9    the mailbox review shows the intended recipient and the matching items, and nothing is sent;
--   and: choosing a saved recipient, refused names, a failed write put back, this character versus all characters,
--   recipients kept out of profiles, shares and backups, and no duplicate controls after redraws.
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
local function Type(key, text) local b = P.Control(key); b:SetText(text); b.scripts.OnTextChanged(b); Flush() end
-- the builder's own category chooser: open it, pick the category the game files under that key, Done
local function PickCategory(key)
  Click("quickCategory1")
  for i, cat in ipairs(MI.Categories()) do if cat.key == key then Click("e1cat" .. i) end end
  Click("filterDone")
end
-- a stable picture of everything saved, to show that nothing changed
local function Signature(value, seen)
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  local keys, out = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do out[#out + 1] = Signature(key) .. "=" .. Signature(value[key]) end
  return "{" .. table.concat(out, ";") .. "}"
end
local function Saved() return Signature(c.TwichUIDB.ui.magicInventory or {}) .. "|" .. Signature(c.TwichUIDB.magicInventory or {}) end
local function Holds(t, text, seen)
  seen = seen or {}
  if type(t) ~= "table" or seen[t] then return false end
  seen[t] = true
  for k, v in pairs(t) do
    if v == text or k == text then return true end
    if type(v) == "table" and Holds(v, text, seen) then return true end
  end
  return false
end

c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local f = P.Frame()
f:Hide(); f:Show(); Flush()

---------------------------------------------------------------------------
-- 1-6. Create a rule, choose herbs with the builder, "Mail to...", type the brother's name, keep 20, review, save
---------------------------------------------------------------------------
P.NewFromTemplate("custom"); Flush()
Check(P.Editing() and P.Editing().kind == "bank", "a new rule opens the existing builder")
PickCategory("7:9")
Check(P.Editing().cats[1] == "7:9" and #P.Editing().cats == 1, "the builder's category chooser picks herbs")
Click("destinationChoicemail")
Check(P.Editing().kind == "mail", "Mail to... is chosen")
Check(P.Control("recipientBox") and P.Control("recipientBox").shown and Has(f, "^Recipient character$"), "a Recipient character field appears right away, in the builder")
Check(Has(f, "Name, or Name%-Realm") and Has(f, "Use Name%-Realm for a character on another realm"), "with the supported format")
Check(Has(f, "can't tell whether the character exists or who plays it"), "and honest about what is checked")
Check(not P.Control("recipientSaved") or not P.Control("recipientSaved").shown, "no saved-recipient chooser while none exist")
Check(not P.Control("e2dd") or not P.Control("e2dd").shown, "no abstract destination chooser in the normal view")
local before = Saved()
Type("recipientBox", "thornbrook")
Check(Saved() == before and #MI.Dests() == 0, "typing writes nothing")
Check(P.Control("recipientStatus").text:find("Saves Thornbrook as this rule's recipient, on this character only, when you save", 1, true), "the field says what saving will do, in the game's capitalization")
local keep = P.Control("builderKeep"); keep:SetText("20"); keep:read(); Flush()
Check(P.Editing().keep == 20, "keep 20 of each")
Check(P.Control("reviewLabel2").text == "Recipient:" and P.Control("reviewValue2").text == "Thornbrook", "the review names the recipient")
Check(P.Control("reviewPlain").text == "Mail matching items (Herb) to Thornbrook. Keep 20 of each matching item in your bags. Only whole stacks are sent, so a few more may stay.",
  "the plain review comes from the rule's own selections: " .. tostring(P.Control("reviewPlain").text))
Check(P.Control("reviewHowSent").text:find("Saving sets up the rule; it sends nothing", 1, true) and P.Control("reviewHowSent").text:find("Prepare mail and Send mail", 1, true), "it says sending happens later, at the mailbox review")
Check(P.Control("builderReady").text == "Ready to save", "nothing else is needed")
Check(P.Control("summaryDetail").text:find("Mail to Thornbrook", 1, true), "the summary banner names the recipient")
local n0 = P.ControlCount()
for _ = 1, 4 do P.QueueRefresh(); Flush() end
Check(P.ControlCount() == n0, "redrawing the builder makes no new controls")
Click("eSave")
Check(P.Editing() == nil, "saved without leaving the builder first")
local herbs = MI.Rules()[1]
Check(herbs and herbs.kind == "mail" and herbs.cats[1] == "7:9" and herbs.keep == 20 and herbs.enabled == false, "the rule is saved off (it was never turned on)")
local w = MI.Resolve(herbs.dest)
Check(w and w.recipient == "Thornbrook" and not w.shared, "it mails to Thornbrook from this character only")
Check(MI.Dest(herbs.dest).label == "Mail recipient", "no label was asked for, and the label isn't the recipient's name: " .. MI.Dest(herbs.dest).label)
Check(Has(f, "Mails to Thornbrook from this character"), "the page says exactly who")
Check(P.Control("rule1to") and P.Control("rule1to").text == "To Thornbrook", "the saved rule's row shows the recipient")
Check(not Holds(c.TwichUIDB.ui, "Thornbrook") and Holds(c.TwichUIDB.magicInventory, "Thornbrook"), "the recipient is kept in the account's table, never in the profile's rules")

-- turning on is the player's choice, and is kept
Click("rule1edit")
P.Control("e4on").scripts.OnClick(P.Control("e4on"), "LeftButton"); Flush()
Click("eSave")
Check(MI.Rules()[1].enabled == true, "turned on when asked")

---------------------------------------------------------------------------
-- 7. Edit the recipient and cancel: nothing saved changes (Cancel, Back, closing with Escape, a profile change)
---------------------------------------------------------------------------
local saved = Saved()
local nDests = #MI.Dests()
Click("rule1edit")
Check(P.Control("recipientBox").text == "Thornbrook", "editing shows the current recipient")
Type("recipientBox", "Otherguy")
P.Control("recipientAll").scripts.OnClick(P.Control("recipientAll"), "LeftButton"); Flush()
Click("eCancel")
Check(Saved() == saved and #MI.Dests() == nDests and MI.Resolve(herbs.dest).recipient == "Thornbrook", "Cancel: nothing saved changed")
Click("rule1edit")
Check(P.Control("recipientBox").text == "Thornbrook", "and the next edit starts from the saved recipient")
Type("recipientBox", "Otherguy")
Click("builderBack"); c.StaticPopupDialogs.TWICHUI_MI_DISCARD_DRAFT.OnAccept(); Flush()
Check(Saved() == saved, "Back and discard: nothing saved changed")
Click("rule1edit"); Type("recipientBox", "Otherguy")
f:Hide(); Flush()   -- Escape closes the settings window: the draft stays private
Check(Saved() == saved, "closing the window mid-edit writes nothing")
f:Show(); Flush()
Check(P.Editing() and P.Control("recipientBox").text == "Otherguy", "reopening keeps the private draft, recipient included")
R.Profiles.Refresh()
Flush()
Check(P.Editing() == nil and Saved() == saved, "a profile change puts the draft away unsaved")
Click("rule1edit")
Check(P.Control("recipientBox").text == "Thornbrook", "and the draft's recipient doesn't come back")
Click("eCancel")

-- a name that can't be one: the field says why, Save is refused, nothing is written
Click("rule1edit")
Type("recipientBox", "Bad Name")
Check(P.Control("recipientStatus").text:find("only letters", 1, true) and P.Control("builderReady").text:find("Needs attention", 1, true), "a name with a space is refused, with the reason")
Click("eSave")
Check(P.Editing() ~= nil and Saved() == saved and Has(f, "only letters"), "Save is refused and nothing is written")
Type("recipientBox", "Rich")
Check(P.Control("recipientStatus").text:find("this character", 1, true), "this character can't be the recipient")
Type("recipientBox", "")
Check(P.Control("builderReady").text:find("Needs attention", 1, true), "an emptied field isn't saved as a cleared recipient")
Click("eSave")
Check(Saved() == saved, "and Save leaves the saved recipient alone")
Click("eCancel")

-- the draft's rule was deleted meanwhile: Save refuses instead of making it again
Click("rule1edit"); Type("recipientBox", "Latename")
do
  local raw = c.TwichUIDB.ui.magicInventory.rules
  c.TwichUIDB.ui.magicInventory.rules = {}
  Click("eSave")
  Check(P.Editing() ~= nil and #c.TwichUIDB.ui.magicInventory.rules == 0 and not Holds(c.TwichUIDB.magicInventory, "Latename"), "a stale draft is refused, and writes nothing")
  c.TwichUIDB.ui.magicInventory.rules = raw
  Click("eCancel")
end
Check(Saved() == saved, "everything as it was")

---------------------------------------------------------------------------
-- 8. Two rules share a destination: changing one keeps the other's recipient
---------------------------------------------------------------------------
local cloth = MI.SaveRule({ name = "Cloth to brother", kind = "mail", dest = herbs.dest, enabled = true, cats = { "7:5" } })
Flush()
Check(#MI.RulesUsing(herbs.dest) == 2, "both rules send to the same destination")
local clothRow
for i, r in ipairs(MI.Rules()) do if r.id == cloth then clothRow = i end end
Click("rule" .. clothRow .. "edit")
Type("recipientBox", "Hollowmere")
Check(Has(f, "also sends to Thornbrook") and P.Control("recipientUpdateShared").shown, "the other rule is named, with an explicit choice to change it too")
Check(P.Control("recipientStatus").text:find("Saves Hollowmere as this rule's recipient", 1, true), "by default only this rule changes")
Click("eSave")
Check(MI.Resolve(MI.Rule(cloth).dest).recipient == "Hollowmere", "the edited rule mails to Hollowmere")
Check(MI.Rule(herbs.id).dest == herbs.dest and MI.Resolve(herbs.dest).recipient == "Thornbrook", "the other rule still mails to Thornbrook")
Check(MI.Rule(cloth).enabled == true and MI.Rule(herbs.id).enabled == true, "neither rule was turned on or off")

-- choosing the shared change on purpose changes it for the rules it names, and only them
local ore = MI.SaveRule({ name = "Ore to brother", kind = "mail", dest = MI.Rule(cloth).dest, enabled = false, cats = { "7:7" } })
Flush()
local oreRow
for i, r in ipairs(MI.Rules()) do if r.id == ore then oreRow = i end end
Click("rule" .. oreRow .. "edit")
Type("recipientBox", "Marrowind")
P.Control("recipientUpdateShared").scripts.OnClick(P.Control("recipientUpdateShared"), "LeftButton"); Flush()
Check(P.Control("recipientStatus").text:find("for this rule and 1 other rule", 1, true), "the shared change says how many rules it changes")
Click("eSave")
Check(MI.Resolve(MI.Rule(ore).dest).recipient == "Marrowind" and MI.Resolve(MI.Rule(cloth).dest).recipient == "Marrowind", "both rules named mail to the new name")
Check(MI.Resolve(herbs.dest).recipient == "Thornbrook", "the unrelated rule is untouched")
Check(MI.Rule(ore).enabled == false, "an off rule stays off")

---------------------------------------------------------------------------
-- An existing recipient, chosen without visiting another tab
---------------------------------------------------------------------------
local nBefore = #MI.Dests()
P.NewFromTemplate("custom"); Flush()
Click("destinationChoicemail")
local dd = P.Control("recipientSaved")
Check(dd and dd.shown, "saved recipients are offered beside the field")
local labels = {}
for _, choice in ipairs(dd.choices()) do labels[#labels + 1] = choice.label end
Check(table.concat(labels, "|"):find("Thornbrook", 1, true) and table.concat(labels, "|"):find("Marrowind", 1, true), "by the recipient's name: " .. table.concat(labels, "|"))
dd.onPick(herbs.dest); Flush()
Check(P.Control("recipientBox").text == "Thornbrook" and P.Control("recipientStatus").text:find("Sends to Thornbrook, on this character only", 1, true), "choosing one fills the field")
PickCategory("7:6")
Click("eSave")
local leather = MI.Rules()[#MI.Rules()]
Check(leather.dest == herbs.dest and #MI.Dests() == nBefore, "the rule uses that recipient: no new destination")
-- typing a name another destination already mails to reuses it
P.NewFromTemplate("custom"); Flush()
Click("destinationChoicemail")
Type("recipientBox", "marrowind")
Check(P.Control("recipientStatus").text:find("Uses your saved recipient Marrowind", 1, true), "a typed name that is already saved is reused")
PickCategory("7:5")
Click("eSave")
Check(MI.Rules()[#MI.Rules()].dest == MI.Rule(ore).dest and #MI.Dests() == nBefore, "and no duplicate destination is made")

---------------------------------------------------------------------------
-- A failed write is put back whole
---------------------------------------------------------------------------
do
  local snapshot = Saved()
  P.NewFromTemplate("custom"); Flush()
  Click("destinationChoicemail")
  Type("recipientBox", "Faultline")
  PickCategory("7:9")
  -- this character's recipient table refuses the write, after the new destination is already in the list
  local acct = c.TwichUIDB.magicInventory
  local key = MI.CharKey()
  local real = acct.chars[key]
  acct.chars[key] = setmetatable({}, { __index = real, __newindex = function() error("write refused") end })
  Click("eSave")
  acct.chars[key] = real
  Check(P.Editing() ~= nil, "the draft stays open after a failed save")
  Check(Saved() == snapshot, "no new destination, recipient or rule was left behind")
  -- too many destinations: refused before anything is written
  local made = {}
  while #MI.Dests() < MI.MAX_DESTS do made[#made + 1] = MI.AddDest("guild", "Tab " .. #MI.Dests()) end
  local full = Saved()
  Click("eSave")
  Check(Saved() == full and Has(f, "choose a saved recipient"), "with no room for a recipient, Save says what to do and writes nothing")
  Click("eCancel")
  for _, id in ipairs(made) do MI.DeleteDest(id) end
  Flush()
end

---------------------------------------------------------------------------
-- This character versus all characters; a local change never clears the account-wide one
---------------------------------------------------------------------------
do
  P.NewFromTemplate("custom"); Flush()
  Click("destinationChoicemail")
  Type("recipientBox", "Everyalt")
  P.Control("recipientAll").scripts.OnClick(P.Control("recipientAll"), "LeftButton"); Flush()
  Check(P.Control("recipientStatus").text:find("on all your characters (account-wide)", 1, true), "the account-wide choice says its scope")
  PickCategory("7:7")
  Click("eSave")
  local acctRule = MI.Rules()[#MI.Rules()]
  local d = acctRule.dest
  Check(MI.Resolve(d).recipient == "Everyalt" and MI.Resolve(d).shared, "saved account-wide")
  c.UnitName = function() return "Other" end
  Check(MI.Resolve(d).recipient == "Everyalt" and MI.Resolve(d).shared, "another character uses it")
  -- on the other character, a recipient of its own for this rule only
  P.QueueRefresh(); Flush()
  local row
  for i, r in ipairs(MI.Rules()) do if r.id == acctRule.id then row = i end end
  Click("rule" .. row .. "edit")
  Check(P.Control("recipientBox").text == "Everyalt", "the other character sees the account-wide recipient")
  Type("recipientBox", "Localpick")
  Check(P.Control("recipientStatus").text:find("on this character only", 1, true) and P.Control("recipientStatus").text:find("Your other characters keep the account-wide recipient", 1, true), "a local change says the account-wide one stays")
  Click("eSave")
  Check(MI.Resolve(d).recipient == "Localpick" and not MI.Resolve(d).shared, "the other character mails to its own choice")
  c.UnitName = function() return "Rich" end
  Check(MI.Resolve(d).recipient == "Everyalt" and MI.Resolve(d).shared, "the account-wide recipient wasn't cleared")
  -- clearing this character's own recipient keeps the account-wide one
  c.UnitName = function() return "Other" end
  Check(MI.ClearRecipient(d, "char") and MI.Resolve(d).recipient == "Everyalt", "clearing here falls back to the account-wide recipient")
  c.UnitName = function() return "Rich" end
  P.SetTask("destinations"); Flush()
  Check(Has(f, "^Mail recipients$") and Has(f, "^Everyalt$") and Has(f, "All your characters %(account%-wide%)"), "Recipients lists it by name and scope")
  local idx
  for i, x in ipairs(MI.Dests()) do if x.id == d then idx = i end end
  Check(P.Control("dest" .. idx .. "unshare") and P.Control("dest" .. idx .. "unshare").shown, "stopping the account-wide recipient is its own action")
  Check(not P.Control("dest" .. idx .. "clear").enabled, "and Clear here has nothing of this character's own to clear")
  P.Control("dest" .. idx .. "unshare").scripts.OnClick(P.Control("dest" .. idx .. "unshare"), "LeftButton"); Flush()
  Check(c.POPUP.name == "TWICHUI_MI_UNSHARE" and c.POPUP.text:find("Everyalt") and c.POPUP.text:find("all your characters"), "it asks first, with its exact scope")
  Check(MI.Resolve(d).recipient == "Everyalt", "nothing changed before the answer")
  c.StaticPopupDialogs.TWICHUI_MI_UNSHARE.OnAccept(); Flush()
  Check(MI.Resolve(d) == nil, "after the answer this character has none")
  c.UnitName = function() return "Other" end
  Check(MI.Resolve(d) == nil, "and the other character, which had cleared its own, has none")
  c.UnitName = function() return "Rich" end
  P.SetTask("rules"); Flush()
end

---------------------------------------------------------------------------
-- Recipients stay out of the profile, configuration shares and portable backups
---------------------------------------------------------------------------
for _, name in ipairs({ "Thornbrook", "Hollowmere", "Marrowind", "Everyalt", "Localpick" }) do
  Check(not Holds(c.TwichUIDB.ui, name), name .. " is not in the profile")
end
Check(R.Restore.OWN_LEFT_OUT.magicInventory ~= nil, "backups leave the account's recipients out")
Check(R.TwichConfig.LOCAL["magicInventory"] and R.TwichConfig.LOCAL["ui.magicInventory"], "sharing keeps rules and recipients local")

---------------------------------------------------------------------------
-- 9. The mailbox review: the intended recipient and the matching items; nothing is sent
---------------------------------------------------------------------------
do
  -- only the herbs rule on, so the review is about one recipient
  for _, r in ipairs(MI.Rules()) do if r.id ~= herbs.id and r.enabled then MI.SetRuleEnabled(r.id, false) end end
  c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 20 }, [3] = { 2447, 5 }, [4] = { 2589, 20 } } } })
  local plan = MI.CurrentPlan("mail")
  local grp = plan.groups[1]
  Check(#plan.groups == 1 and grp.where.recipient == "Thornbrook", "the mail plan is for Thornbrook")
  local herbStacks = 0
  for _, batch in ipairs(grp.batches) do for _, e in ipairs(batch) do if e.id == 2447 then herbStacks = herbStacks + 1 end Check(e.id == 2447, "only herbs are planned") end end
  Check(herbStacks == 2, "keeping 20 of 45 in stacks of 20, 20 and 5: the 20 and the 5 go, one stack of 20 stays: " .. herbStacks)
  c.MailFrame = c.MailFrame or MIFake("Frame")
  c.MailFrame.shown = true
  c.OpenMail(); Flush()
  local Win = MI.Window
  Win.Show(); Flush()
  local wf = c.TwichUIMagicInventory
  Check(Win.IsShown() and Has(wf, "Send by mail to Thornbrook"), "the review shows the exact recipient")
  Check(Has(wf, "Peacebloom") or Has(wf, "Herb"), "and the matching items")
  Check(c.SENDMAIL_CALLS == 0 and #c.SENT == 0 and #c.PICKUPS == 0, "nothing was sent or picked up")
  Win.Hide(); Flush()
end

if failures == 0 then print("PASSED test_magic_inventory_recipient") else print(failures .. " failures") os.exit(1) end
