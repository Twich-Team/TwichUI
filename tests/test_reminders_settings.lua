dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Reminders in the settings window (TwichUI_Settings/pages/Reminders.lua and RemindersEditor.lua):
--   * the page: where it sits, its switch, its hosted frame;
--   * the list and the templates: a new reminder is a draft, opened in the editor;
--   * the editor: rules read as a sentence, field-specific choices, an item by link, names, duplicate, delete (asks);
--   * Test: what it sees right now (also for a draft), and simulations that never touch the live state;
--   * Preview and moving through the buttons; progressive disclosure; nothing made again on a redraw; events only
--     while shown.
-- Stand-in frames keep their scripts, text, focus and shown state; nothing here is the game.

local made = 0
local created = {}
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  created[#created + 1] = f
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    SetEnabled = function(s, v) s.enabled = v and true or false end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function(s) return unpack(s.font or { "Fonts\\FRIZQT__.TTF", 12, "" }) end,
    SetFont = function(s, file, size, flags) s.font = { file, size, flags }; return true end,
    SetScrollChild = function(s, child) s.child = child end,
    GetScrollChild = function(s) return s.child end,
    SetVerticalScroll = function(s, value) s.scroll = value end,
    GetVerticalScroll = function(s) return s.scroll or 0 end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    SetScale = function(s, v) s.scale = v end,
    SetTexture = function(s, t) s.texture = t; return true end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
    GetThumbTexture = function(s) s.thumbTex = s.thumbTex or Fake("Texture", s) return s.thumbTex end,
    CreateAnimationGroup = function(s)
      local g = Fake("AnimationGroup", s)
      g.Play = function(self) self.playing = true end
      g.Stop = function(self) self.playing = false end
      g.CreateAnimation = function() return Fake("Animation", g) end
      return g
    end,
  }
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

local EQUIP = {}
local ITEMS = { [1201] = { "Dull Heater Shield", 4, 6, "INVTYPE_SHIELD" }, [6948] = { "Hearthstone", 15, 0, "" }, [2139] = { "Dirk", 2, 7, "INVTYPE_WEAPONOFFHAND" } }
local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.UIParent.w, c.UIParent.h = 1024, 768
  c.GameTooltip = Fake("GameTooltip")
  c.Enum = { ItemClass = { Weapon = 2, Armor = 4 }, ItemArmorSubclass = { Shield = 6 }, ItemWeaponSubclass = { Fishingpole = 20 } }
  c.C_Item = {
    GetItemInfoInstant = function(id) local it = ITEMS[id] if it then return id, "", "", it[4], 1000 + id, it[2], it[3] end end,
    GetItemIconByID = function(id) if ITEMS[id] then return 1000 + id end end,
    GetItemNameByID = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    GetItemInfo = function(id) if ITEMS[id] then return ITEMS[id][1] end end,
    RequestLoadItemDataByID = function() end,
    GetItemSpell = function() return nil end, GetItemCount = function() return 0 end,
  }
  c.GetInventoryItemID = function(_, slot) return EQUIP[slot] end
  c.UnitClassBase = function() return "WARRIOR" end
  c.UnitIsGhost = function() return false end
  c.GetCursorInfo = function() return nil end
  c.ClearCursor = function() end
end

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local K, RM, CT, D, ST = S.K, R.Reminders, R.ReminderController, R.ReminderDisplay, R.ReminderState
local P = R.RemindersPage
local editorOpen, editorPage = true, "reminders"
R.SettingsUI.IsPageActive = function(key) return editorOpen and editorPage == key end
R.SettingsUI.SuspendForPlacement = function(on, reopen)
  editorOpen = not on and reopen ~= false
  if not on and editorOpen then P.Refresh() end
end
local function Flush() for _ = 1, 6 do FlushTimers() end end
local function Deep(v)   -- a string for a whole stored value, to see that nothing changed
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Deep(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

---------------------------------------------------------------------------
-- 1. The page
---------------------------------------------------------------------------
local page
for _, p in ipairs(S.pages) do if p.key == "reminders" then page = p end end
Check(page and page.group == "everyday" and page.kind == "hosted" and page.name == "Reminders", "a page of its own under Everyday, with a frame of its own")
Check(K.pages.reminders.def.icon == "reminders" and R.Icons.Get("reminders"), "with the bell icon")
local sw = S.variables.TWICHUI_reminders
Check(sw and sw:GetValue() == true and sw:GetDefaultValue() == true, "the switch is on by default (no reminder exists, and each starts off)")
Check(K.rowsById["reminders"] and K.rowsById["reminders"].primaryOf, "the switch is the card's")
Check(type(K.pages.reminders.def.hostHeight) == "function" and K.pages.reminders.def.hostAfter == "Reminders", "the frame follows the card and grows with its content")

---------------------------------------------------------------------------
-- 2. The list and the templates
---------------------------------------------------------------------------
local f = P.Frame()
f.shown = false
f:Show()
Flush()
local parts = P.Parts()
Check(parts.sections and #parts.sections == 5, "the five sections are built (the preview is beside the window)")
Check(f.empty.shown and f.empty.text:find("No reminders yet"), "an empty list says how to start")
Check(f.newButton and f.newButton.shown, "one way to start: New reminder, which opens the templates")
Check(f.events.PLAYER_EQUIPMENT_CHANGED and f.events.GET_ITEM_INFO_RECEIVED, "while shown it hears what Test reads")
local createdBefore = made

Check(P.Create("shield"), "Missing shield")
Flush()
local id = P.Selected()
local v = RM.Get(id)
Check(v and v.name == "Shield reminder" and not v.enabled, "a draft, opened")
local row = parts.rows[1]
Check(row.shown and row.name.text == "Shield reminder" and row.state.text == "Off" and not row.check:GetChecked(), "its row: name, Off, unchecked")
Check(row.ruleText == "Shows when: Off hand is not Shield.", "its rule in a sentence: " .. row.ruleText)
Check(not f.empty.shown and f.head.shown and f.nameBox.text == "Shield reminder", "the editor's head")
Check(not f.say.shown, "the Off switch and row convey the draft state without a success paragraph")

-- the list and the name panel are as wide as the frame the window gives the page (the feature card's width), and never narrower than 644
Check(f.list.w == 220 and f.head.w == 415 and row.w == 198, "at the first size the list and editor share the available width")
f:SetWidth(780); P.Refresh(); Flush()
Check(f.list.w > 220 and f.list.w <= 280 and f.head.w > 415 and row.w == f.list.w - 22, "a wider window balances both panes without shrinking the editor")
f:SetWidth(500); P.Refresh(); Flush()
Check(f.list.w == 220 and f.head.w == 415, "the page respects its minimum width")
f:SetWidth(644); P.Refresh(); Flush()

local show, when, place, sound, test = unpack(parts.sections)
local PV = R.RemindersPreview
local DZ = R.RemindersDesigner
local function Click(button, ...)
  button:Fire("OnClick", ...)
  Flush()
end
local function Open()
  DZ.Open()
  Flush()
end
local function Advanced()
  DZ.SetAdvanced(true)
  Flush()
end
local function Draft() return DZ.DraftView() end
Check(not when.shown and when.summary:IsShown(), "When starts as a compact summary")
local original = RM.Get(id).conditions[1].raw
original.extension = "keep"
Open()
Check(not R.RemindersPlacement.Start(RM.Get(id)), "an exclusive When workspace cannot start competing placement")
Check(show.shown and show.modes[1].twichSelected and not show.modes[2].twichSelected and not show.modes[3].twichSelected and show.imageName.text == "Steel shield"
    and show.imageSource.text == "TwichUI artwork" and show.choose.shown and show.textBox.text == "Equip your shield", "Show: image with text")
Check(DZ.Frame().workspace.shown and DZ.Frame().rail.rows[1].name.text == "Shield reminder",
    "the dedicated builder rail follows reminder selection")
Check(#show.modes == 3 and show.modes[1].text.text == "Image + text" and show.modes[2].text.text == "Image only" and show.modes[3].text.text == "Text only", "Show: the three display modes")
local cd = when.cards[1]
Check(not when.isAdvanced and cd.title.text == "Equipment slot" and cd.fields[1].shown and cd.fields[3].shown
    and cd.note.shown and not cd.more.shown and when.addBasic.shown, "flat rule with inline controls, read-only state and contextual actions")
local draftRaw, revision = Draft().conditions[1].raw, RM.Rev()
cd.fields[2].onPick("is"); Flush()
Check(Draft().conditions[1].raw == draftRaw and not Draft().conditions[1].cond.negate and draftRaw.extension == "keep",
    "inline editing preserves draft node identity and extension data")
Check(RM.Rev() == revision and original.negate and RM.Get(id).conditions[1].raw == original,
    "inline editing leaves the live condition alone")
Check(not when.editor.shown and DZ.Frame().save.enabled and DZ.Frame().dirty.shown, "no duplicate editor; the footer shows an unsaved change")
Click(DZ.Frame().cancel)
Check(RM.Rev() == revision and original.negate and PV.Shown() and not DZ.Shown(), "Cancel discards draft and restores the preview")
Check(not DZ.Frame().workspace.shown, "Cancel puts away the dedicated workspace")
original.extension = nil
local OFFHAND = {}
for _, ch in ipairs(R.RemindersPlain.ValueChoices(RM.Get(id).conditions[1].cond)) do OFFHAND[#OFFHAND + 1] = ch.label end
Check(table.concat(OFFHAND, ",") == "Empty,Shield,Weapon,Held in off hand,A specific item", "the off hand's own choices only: " .. table.concat(OFFHAND, ","))

---------------------------------------------------------------------------
-- 3. Test: right now, and simulated
---------------------------------------------------------------------------
EQUIP[17] = nil
test.toggle.scripts.OnClick(test.toggle); Flush()
P.Refresh()
Check(test.live[1].title.text == "Your off hand is not a shield" and test.live[1].state.text == "Met" and test.live[1].observation.text == "Observed: Empty", "a diagnostic separates condition, state and observation")
Check(test.liveHead.text == "Hidden now" and test.liveResult.text == "Reminder off", "overall result explains disabled state")
f.onBox.scripts.OnClick(f.onBox)
Flush()
Check(RM.Get(id).enabled and CT.Status(id) == "showing" and parts.rows[1].state.text == "Showing", "turned on: showing")
Check(test.liveHead.text == "Showing now" and test.liveResult.text == "Conditions met", "overall live result")
Click(test.try)
Check(test.simTag.shown and test.picks[1].shown and test.picks[1].text.text == "Shield equipped", "a simulated situation per condition")
local liveObs = ST.Observations().slots[17]
test.picks[1].onPick("match")
Flush()
Check(test.simResult.text:find("^Simulated result: Hidden"), "simulated shield: hidden: " .. test.simResult.text)
Check(test.sim[1].state.text == "Not met" and test.sim[1].observation.text:find("Simulated: A shield"), "simulation observations remain separately labeled")
Check(CT.Status(id) == "showing" and ST.Observations().slots[17] == liveObs, "the live state is untouched")
test.picks[1].onPick("unknown")
Flush()
Check(test.simResult.text:find("Waiting for information"), "simulated no details: waiting")
-- the page redraws from the game's events while it is shown (a draft's "Right now" is read when drawn)
P.Create("custom")
Flush()
local tid = P.Selected()
RM.AddCondition(tid, "equipment")
Flush()
Check(test.live[1].title.text == "Your off hand is empty" and test.live[1].state.text == "Met", "live draft condition result")
EQUIP[17] = 1201
f.scripts.OnEvent(f, "PLAYER_EQUIPMENT_CHANGED", 17)
Flush()
Check(test.live[1].state.text == "Not met" and test.live[1].observation.text:find("Shield"), "live observations refresh after equipment events")
Check(ST.Observations().slots[17] ~= nil and ST.Snapshot().keys == 1, "the draft's look never adds to what the live reminders read")
RM.Delete(tid)
P.Select(id)
Flush()
---------------------------------------------------------------------------
-- 4. The rule transaction, type-aware controls, history and targeting
---------------------------------------------------------------------------
Open()
local ed, pk, builder = when.editor, when.picker, DZ.Frame()
local function Pick(key)
  for _, choice in ipairs(pk.rows) do
    if choice.shown and choice.entry and choice.entry.key == key then Click(choice) return true end
  end
  return false
end
local function Search(text)
  pk.search:SetText(text)
  pk.search:Fire("OnTextChanged", true)
  Flush()
end
local saved, revision = Deep(RM.Get(id).raw), RM.Rev()
Check(pk.searchHint.text == "Search..." and pk.categories.Equipment.shown, "the palette starts with search and category headings")
Search("mounted")
Check(Pick("player:mounted"), "search finds Mounted in the palette")
Check(ed.op.shown and ed.op.text.text == "Is mounted" and not ed.subject.shown and not ed.value.shown,
    "Mounted has a single relevant binary control even during setup")
ed.op.onPick("not"); Flush()
Click(ed.done)
local mounted = when.cards[2]
Check(mounted.title.text == "Mounted" and mounted.fields[1].text.text == "Is not mounted"
    and not mounted.fields[2].shown and not ed.shown, "the mounted card edits its own subject directly")
mounted.fields[1].onPick("slot:trinket1"); Flush()
Check(Draft().conditions[2].cond.state == "mounted" and Draft().conditions[2].cond.negate,
    "a nonsensical equipment option is rejected")
mounted:Fire("OnClick", "RightButton")
Check(R.SettingsWidgets.MenuShown(), "right-click opens the contextual actions")
R.SettingsWidgets.CloseMenu()
mounted.more.onPick("dup"); Flush()
Check(#Draft().conditions == 3 and Draft().conditions[3].raw ~= Draft().conditions[2].raw, "duplicating creates a distinct draft node")
when.cards[3].more.onPick("remove"); Flush()
Check(#Draft().conditions == 2, "a condition can be removed through Actions")
Click(when.undo)
Check(#Draft().conditions == 3, "Undo restores a removed condition")
Click(when.redo)
Check(#Draft().conditions == 2, "Redo reapplies removal")
mounted.more.onPick("up"); Flush()
Check(Draft().conditions[1].cond.state == "mounted", "menu reorder works without a drag")
Click(when.undo)
Check(Draft().conditions[2].cond.state == "mounted", "Undo reverses a reorder")
S.popup = nil
R.RemindersCatalog.Toggle()
Check(S.popup and S.popup.key == "TWICHUI_DISCARD_REMINDER_RULE" and not R.RemindersCatalog.Shown(),
    "the catalog asks before it takes the place of a dirty builder")
c.StaticPopupDialogs[S.popup.key].OnCancel()
Check(DZ.Shown() and #Draft().conditions == 2, "declining to discard leaves the draft open")

Search("dungeon")
Check(Pick("player:dungeon"), "search finds a location")
Click(ed.done)
local loc = when.cards[3]
Check(loc.title.text == "Location" and loc.chips[1].text.text == "Dungeon  ×" and loc.choose.shown,
    "a location has a selected token and additive choice")
loc.choose.onPick("raid"); Flush()
Check(#Draft().conditions[3].children == 2 and Draft().conditions[3].match == "any" and not when.isAdvanced,
    "adding a second location uses the existing Any group and stays in the simple presentation")
Check(builder.result.text:find("raid") and builder.result.text:find("or"),
    "the chip summary retains OR semantics")
Click(loc.chips[1])
Check(#Draft().conditions[3].children == 1 and Draft().conditions[3].children[1].cond.state == "raid",
    "removing a location removes only that selected predicate")
Click(when.undo)
Check(#Draft().conditions[3].children == 2, "Undo restores the selected location")
Check(loc.raw == Draft().conditions[3].raw and loc.chips[2].shown, "Undo refreshes chip bindings to the restored draft")

when.whoEdit.onPick("all"); Flush()
Check(Draft().scope.who == "all" and #Draft().conditions == 3 and not when.target.shown, "For changes only draft targeting")
Click(when.undo)
Check(Draft().scope.who == "characters", "Undo restores targeting")
Click(when.redo)
when.whoEdit.onPick("manage"); Flush()
Check(when.target.shown and #Draft().conditions == 3, "advanced targeting has separate controls")
when.target.class.onPick("MAGE"); Flush()
Click(when.target.done)
Click(builder.try)
Check(DZ.State().try, "Try a situation exposes the draft simulation")
Check(builder.diagnostics.shown and builder.diagnosticsScroll.parent == builder.diagnostics,
    "situation testing stays in the bottom evaluation region")
Check(RM.Rev() == revision and Deep(RM.Get(id).raw) == saved and CT.Status(id) == "hidden",
    "conditions, targeting and simulation leave live state and saved configuration alone")
S.popup = nil
DZ.RequestClose()
Check(S.popup and S.popup.key == "TWICHUI_DISCARD_REMINDER_RULE" and DZ.Shown(), "closing asks before discarding edits")
c.StaticPopupDialogs[S.popup.key].OnAccept()
Flush()
Check(not DZ.Shown() and PV.Shown() and RM.Rev() == revision, "accepting discard restores the same reminder")
Check(not builder.workspace.shown, "discard closes both builder panels")

Open()
Advanced()
Click(when.rootGroup.add)
DZ.AddGroup("any")
Flush()
Check(#Draft().groups == 1 and #Draft().groups[1].children == 0, "an empty Any group can be drafted")
Check(not DZ.Save() and RM.Rev() == revision and Deep(RM.Get(id).raw) == saved and DZ.Shown(),
    "Save rejects an incomplete group atomically")
Click(when.groups[1].add)
Check(Pick("player:dungeon"), "a nested group can add dungeon")
Click(ed.done)
Click(when.groups[1].add)
Search("raid")
Check(Pick("player:raid"), "a nested group can add raid")
Click(ed.done)
Check(builder.result.text:find(" or "), "summary retains the actual nested OR")
when.groups[1].add:Fire("OnClick"); Flush()
Search("")
Check(Pick("player:combat"), "an arbitrary nested rule stays available")
Click(ed.done)
local oldRaw = RM.Get(id).raw
when.whoEdit.onPick("all"); Flush()
RM.SetDisplay(id, "text", "Equip your shield now")
Flush()
local beforeSave = RM.Rev()
Click(builder.save)
local applied = RM.Get(id)
Check(not DZ.Shown() and applied.raw == oldRaw and RM.Rev() == beforeSave + 1 and applied.enabled
    and applied.scope.who == "all" and applied.groups[1].match == "any" and #applied.groups[1].children == 3
    and applied.display.text == "Equip your shield now", "Save commits rule and scope once, preserving identity, enabled state and unrelated concurrent edits")
Open()
Check(when.isAdvanced and not when.advanced.enabled, "an existing nested rule opens advanced without flattening")
local nested = Deep(RM.Get(id).raw)
Click(when.groups[1].fold)
Check(when.groups[1].folded.shown and not when.cards[2].shown, "a folded group hides its children while keeping the saved rule")
Click(when.groups[1].fold)
S.popup = nil
when.groups[1].more.onPick("remove"); Flush()
Check(S.popup and S.popup.key == "TWICHUI_REMINDER_GROUP_DELETE" and #Draft().groups == 1,
    "removing a populated group requires confirmation")
c.StaticPopupDialogs[S.popup.key].OnAccept()
Flush()
Check(#Draft().groups == 0 and Deep(RM.Get(id).raw) == nested, "confirmed group removal changes only the draft")
Click(when.undo)
Check(#Draft().groups == 1 and #Draft().groups[1].children == 3, "Undo restores the entire group")
when.whoEdit.onPick("me"); Flush()
RM.SetMatch(id, "any")
Flush()
Check(not DZ.Save() and DZ.Shown() and RM.Get(id).scope.who == "all" and RM.Get(id).match == "any",
    "a concurrent rule edit refuses Save without partially applying targeting")
Click(builder.cancel)
RM.SetMatch(id, "all")
Check(Deep(RM.Get(id).raw) == nested, "discard and restoration preserve the saved nested rule")
RM.RemoveNode(id, 2)
RM.SetScope(id, "who", "characters")

Open()
local function Cycle()
  Advanced()
  when.cards[1].more.onPick("edit"); Flush()
  Click(ed.cancel)
  Click(when.rootGroup.add)
  Click(pk.cancel)
  when.whoEdit.onPick("manage"); Flush()
  Click(when.target.done)
  Click(when.explain)
  Click(when.explain)
end
Cycle()
local madeBefore = made
for _ = 1, 4 do Cycle() end
Check(made == madeBefore, "repeated editor and picker cycles do not allocate duplicate frames")
cd.more.onPick("dup"); Flush()
f:Hide(); f:Show(); Flush()
Check(not DZ.Shown() and PV.Shown() and #RM.Get(id).conditions == 1, "page exit discards draft and cleans up the companion")

-- The maximum-sized nested rule fits the existing scroll content and pooled cards.
P.Create("custom")
Flush()
local bid = P.Selected()
for _ = 1, 4 do RM.AddCondition(bid, "player") end
RM.AddGroup(bid, nil, "any")
for _ = 1, 5 do RM.AddCondition(bid, "player", { 5 }) end
RM.AddGroup(bid, { 5 }, "all")
for _ = 1, 4 do RM.AddCondition(bid, "class", { 5, 6 }) end
RM.AddGroup(bid, nil, "all")
for _ = 1, 3 do RM.AddCondition(bid, "equipment", { 6 }) end
Open()
local shown, widest = 0, 0
for _, card in ipairs(when.cards) do
  if card.shown then
    shown = shown + 1
    widest = math.max(widest, card.points[1][4] + card.w)
  end
end
Check(shown == RM.MAX_CONDITIONS and widest <= when:GetWidth(), "every card fits even at maximum count and depth")
Check(not when.rootGroup.add.enabled, "the condition limit is enforced from the builder")
Click(builder.cancel)
RM.Delete(bid)
P.Select(id)
Flush()

P.Create("custom"); Flush()
local fullId = P.Selected()
RM.AddCondition(fullId, "weaponEnchant")
RM.AddCondition(fullId, "player", nil, { type = "player", state = "dungeon" })
for _ = 1, RM.MAX_CONDITIONS - 2 do RM.AddCondition(fullId, "player") end
Open()
local fullBefore = Deep(RM.Get(fullId).raw)
when.cards[2].choose.onPick("raid"); Flush()
Check(#Draft().groups == 0 and not DZ.HasUnsaved() and Deep(RM.Get(fullId).raw) == fullBefore,
    "a refused additive location rolls back its entire draft operation at the limit")
Check(when.cards[2].raw == Draft().conditions[2].raw,
    "a refused compound edit refreshes the card bindings after rollback")
Click(builder.cancel)
RM.Delete(fullId)
P.Select(id); Flush()

---------------------------------------------------------------------------
-- 5. Required item input and display artwork in the same draft
---------------------------------------------------------------------------
P.Create("item")
Flush()
local iid = P.Selected()
Check(f.problems.shown and f.problems.text:find("Needs attention") and f.fix.shown and f.problems.text:find("item"),
    "the incomplete reminder exposes an actionable problem")
Click(f.onBox)
Check(not RM.Get(iid).enabled and f.say.text:find("item"), "the incomplete item reminder cannot enable")
Open()
local ic = when.cards[1]
Check(ic.item.shown and ic.item.text.text == "Choose item", "the card exposes its required item directly")
Click(ic.item)
Check(ed.shown and ed.item.shown and not ed.subject.shown and not ed.op.shown and not ed.value.shown and not ed.done.enabled,
    "the secondary item editor shows just the missing input")
ed.item:SetText("|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r")
ed.item:Fire("OnEnterPressed")
Flush()
Check(ed.itemInfo.text:find("Hearthstone") and ed.done.enabled, "a pasted link resolves and can be staged")
Click(ed.done)
Check(Draft().conditions[1].cond.item == 6948 and Draft().display.item == 6948 and not RM.Get(iid).valid,
    "condition and inferred display icon are isolated until Save")
Click(when.undo)
Check(not Draft().conditions[1].cond.item and not Draft().display.item, "Undo reverts item and inferred icon together")
Click(when.redo)
Click(builder.save)
local iv = RM.Get(iid)
Check(iv.conditions[1].cond.item == 6948 and iv.display.item == 6948 and iv.valid and not iv.enabled,
    "Save applies item and icon together and keeps the reminder off")
Check(show.imageSource.text == "Game icon" and show.imageName.text:find("6948"), "the editor shows the saved item icon as a game icon")
Open()
Click(ic.item)
ed.item:SetText("not an item")
ed.item:Fire("OnEnterPressed")
Flush()
Check(builder.message.text:find("isn't an item ID") and RM.Get(iid).conditions[1].cond.item == 6948, "a bad item leaves the saved condition alone")
Click(ed.cancel)
Click(builder.cancel)

---------------------------------------------------------------------------
-- 6. Name, duplicate, delete
---------------------------------------------------------------------------
f.nameBox:SetText("Hearth check")
f.nameBox.scripts.OnEnterPressed(f.nameBox)
Flush()
Check(RM.Get(iid).name == "Hearth check" and parts.rows[2].name.text == "Hearth check", "renamed")
f.nameBox:SetText("")
f.nameBox.scripts.OnEnterPressed(f.nameBox)
Flush()
Check(RM.Get(iid).name == "Hearth check" and f.say.text:find("name"), "an empty name is refused")
f.duplicate.scripts.OnClick(f.duplicate)
Flush()
local did = P.Selected()
Check(did ~= iid and RM.Get(did).name == "Hearth check (copy)" and not RM.Get(did).enabled, "duplicate: a fresh, turned-off copy, opened")
S.popup = nil
f.delete.scripts.OnClick(f.delete)
Check(S.popup and S.popup.key == "TWICHUI_REMINDER_DELETE" and S.popup.text:find("Hearth check %(copy%)") and RM.Get(did), "delete asks first, naming it")
c.StaticPopupDialogs[S.popup.key].OnAccept()
Flush()
Check(RM.Get(did) == nil and RM.Get(iid) and P.Selected() ~= did, "deleted; the others stay")

---------------------------------------------------------------------------
-- 7. Preview and moving, through the buttons
---------------------------------------------------------------------------
R.RemindersDesigner.Close(); Flush()
place.toggle.scripts.OnClick(place.toggle); Flush()
P.Select(id)
Flush()
PV.Parts().show.scripts.OnClick(PV.Parts().show)
Flush()
Check(D.PreviewId() == id and PV.Parts().show:GetChecked() and PV.Parts().state.text:find("On screen"), "on-screen preview")
Check(CT.Status(id) == "hidden", "the preview leaves the live decision as it was (a shield is on)")
PV.Parts().show.scripts.OnClick(PV.Parts().show)
Flush()
Check(D.PreviewId() == nil and not PV.Parts().show:GetChecked(), "preview hidden again")
place.move.scripts.OnClick(place.move)
Flush()
Check(D.Positioning() and R.RemindersPlacement.Active() and not PV.Shown(), "focused placement hides the editing companion")
R.RemindersPlacement.Parts().finish:Fire("OnClick")
Flush()
Check(not D.Positioning() and editorOpen and PV.Shown(), "Finish restores the editor and its preview")
D.PreviewStop()
Check(PV.Parts().surface.art.texture and PV.Parts().surface.art.texture:find("shield"), "the preview draws with the reminder's own layout")

---------------------------------------------------------------------------
-- 8. More options, height, nothing made twice
---------------------------------------------------------------------------
Check(not place.width.shown and not place.strata.shown, "more options are closed at first")
Check(place.opacity.shown and not place.preset.shown and not place.presetLabel.shown,
  "Opacity owns the first Advanced row; Position stays in secondary placement options")
local function RowPoint(control) return control.points[1] end
Check(RowPoint(place.textSize)[5] < RowPoint(place.opacity)[5]
  and RowPoint(place.textPlace)[5] < RowPoint(place.textSize)[5], "Advanced's primary rows occupy separate ordered anchors")
Check(RowPoint(place.opacity)[4] == RowPoint(place.textSize)[4]
  and RowPoint(place.textPlace)[4] == RowPoint(place.opacity)[4], "Advanced controls share one left column")
Check(place.opacity:GetWidth() == place.textSize:GetWidth()
  and RowPoint(place.opacity)[4] + place.opacity:GetWidth() <= place:GetWidth() - 14,
  "sliders and equal numeric boxes stay within Advanced's right padding")
local beforeDisplay = RM.Get(id).display
local diagnosticsWasOpen = R.RemindersEditor.testOpen
local oldOpacity, oldTextSize, oldTextPlace = beforeDisplay.opacity, beforeDisplay.textSize, beforeDisplay.textPlace
place.opacity.slider:Fire("OnValueChanged", 73); Flush()
place.textSize.slider:Fire("OnValueChanged", 24); Flush()
place.textPlace.onPick("below"); Flush()
Check(RM.Get(id).display.opacity == 73 and RM.Get(id).display.textSize == 24
  and RM.Get(id).display.textPlace == "below", "Advanced sliders and Words go still save through Config")
RM.SetDisplay(id, "opacity", oldOpacity); RM.SetDisplay(id, "textSize", oldTextSize); RM.SetDisplay(id, "textPlace", oldTextPlace); Flush()
local h1 = P.Height()
place.more.scripts.OnClick(place.more)
Flush()
Check(place.strata.shown and place.fade.shown and place.delay.shown and place.x.shown, "opened: the rest is there")
Check(place.preset.shown and place.presetLabel.shown and RowPoint(place.preset)[5] < RowPoint(place.panel)[5]
  and RowPoint(place.point)[5] < RowPoint(place.preset)[5], "Position keeps a separate row beside the other placement settings")
Check(P.Height() > h1, "the frame grows, and the window is asked to place it again")
place.keep.scripts.OnClick(place.keep)
Flush()
Check(RM.Get(id).display.keepAspect == false and place.width.shown and place.height.shown, "proportions off: width and height")
place.x:SetText("40")
place.x.scripts.OnEnterPressed(place.x)
Flush()
Check(RM.Get(id).place.preset == "custom" and RM.Get(id).place.x == 40, "a typed offset makes a place of its own")
place.more.scripts.OnClick(place.more)
Flush()
Check(not place.preset.shown and not place.presetLabel.shown and P.Height() < h1 + 50,
  "collapsing secondary placement hides its labels and restores the shorter content height")
local Ed = R.RemindersEditor
Ed.testOpen = true; P.Refresh(); Flush()
local diagnosticsHeight = P.Height()
Check(test:IsShown() and test.live[1]:IsShown(), "Diagnostics expansion includes visible result rows")
Ed.testOpen = false; Ed.placementOpen = false; P.Refresh(); Flush()
Check(not test:IsShown() and not place.opacity:IsShown() and not place.more:IsShown()
  and P.Height() < diagnosticsHeight, "closing both disclosures hides descendants and shrinks the page")
Ed.placementOpen = true; Ed.testOpen = diagnosticsWasOpen; P.Refresh(); Flush()
local count = made
for _ = 1, 5 do P.Refresh(); Flush() end
Check(made == count, "redrawing makes nothing new: " .. (made - count))

---------------------------------------------------------------------------
-- 9. Off, hidden, profiles
---------------------------------------------------------------------------
R:SetEnabled("reminders", false)
Flush()
P.Refresh()
Check(test.liveHead.text == "Hidden now" and test.liveResult.text == "Reminders off", "master disabled reason remains visible")
R:SetEnabled("reminders", true)
Flush()
f:Hide()
Check(next(f.events) == nil, "hidden: it hears nothing")
f:Show()
Flush()
Check(R.Profiles.Create("Empty"), "a new profile")
Flush()
Check(P.Selected() == nil and f.empty.shown and not f.head.shown, "another profile's (empty) list; nothing stale is open")

---------------------------------------------------------------------------
-- 10. The template catalog (RemindersCatalog.lua): cards, copies, cancel, refusals
---------------------------------------------------------------------------
do
  local CAT = R.RemindersCatalog
  Check(CAT and f.newButton.scripts.OnClick, "the catalog and its button exist")
  f.newButton.scripts.OnClick(f.newButton)
  local cf = CAT.Frame()
  Check(CAT.Shown(), "New reminder opens the catalog")
  Check(#cf.cards == 5, "a card for each template that makes a reminder of its own: " .. #cf.cards)
  for _, card in ipairs(cf.cards) do
    Check(card.name.text ~= "" and card.brief.text ~= "" and card.use.text.text == "Use template", "a card has a name, a line and Use template: " .. card.kind)
  end
  Check(cf.custom and cf.custom.scripts.OnClick, "and Custom reminder")

  -- closing without choosing makes nothing and keeps the selection
  local chosen, before = P.Selected(), Deep(RM.List())
  CAT.Hide()
  Check(not CAT.Shown() and P.Selected() == chosen and Deep(RM.List()) == before, "closing it makes and changes nothing")
  f.newButton.scripts.OnClick(f.newButton)
  local esc = false
  for _, name in ipairs(c.UISpecialFrames or {}) do if name == "TwichUIReminderCatalog" then esc = true end end
  Check(esc or not c.UISpecialFrames, "Esc is wired through the game's frame list")

  -- the first card in the catalog is a template (Missing shield): use it twice
  local shield
  for _, card in ipairs(cf.cards) do if card.kind == "shield" then shield = card end end
  local tplBefore = Deep(RM.TEMPLATES)
  local n0 = #RM.List()
  shield.use.scripts.OnClick(shield.use)
  Flush()
  local a = P.Selected()
  Check(#RM.List() == n0 + 1 and a and not RM.Get(a).enabled, "using it makes one reminder, turned off")
  Check(not CAT.Shown(), "and the catalog goes away")
  Check(f.head.shown and f.nameBox.text == RM.Get(a).name, "the new reminder is selected and its editor is open")
  f.newButton.scripts.OnClick(f.newButton)
  shield.use.scripts.OnClick(shield.use)
  Flush()
  local b = P.Selected()
  Check(b and b ~= a and #RM.List() == n0 + 2 and not RM.Get(b).enabled, "a second use is another reminder with its own id")
  RM.SetName(a, "Edited")
  RM.SetPreset(a, "custom")
  Check(RM.Get(b).name == "Shield reminder" and RM.Get(b).place.preset == "belowCenter", "editing one copy leaves the other alone")
  local ok, c2 = RM.Create("shield")
  Check(RM.Get(c2).name == "Shield reminder" and Deep(RM.TEMPLATES) == tplBefore, "nor the template (a third copy is as the template says)")
  RM.Delete(c2)

  -- an on-screen preview of the chosen one survives making another
  RM.SetEnabled(b, false)
  local started = D.PreviewStart(RM.Get(b), false)
  Check(started, "a preview can be started here")
  if started then
    f.newButton.scripts.OnClick(f.newButton)
    shield.use.scripts.OnClick(shield.use)
    Flush()
    Check(D.PreviewId() == b, "the preview of an earlier reminder is still on")
    D.PreviewStop()
  end

  -- at the limit: refused, the catalog stays open and says why
  while #RM.List() < RM.MAX do RM.Create("custom") end
  local sel, count = P.Selected(), #RM.List()
  f.newButton.scripts.OnClick(f.newButton)
  shield.use.scripts.OnClick(shield.use)
  Flush()
  Check(CAT.Shown() and #RM.List() == count and P.Selected() == sel, "at the limit nothing is made and the catalog stays open")
  Check(cf.say.text == RM.REFUSE.full, "and it says why: " .. cf.say.text)
  cf.custom.scripts.OnClick(cf.custom)
  Check(CAT.Shown() and #RM.List() == count, "Custom reminder is refused the same way")
  -- closing the settings page puts it away
  f:Hide()
  Check(not CAT.Shown(), "hiding the page puts the catalog away")
  f:Show()
  Flush()
end

---------------------------------------------------------------------------
-- 11. The preview companion and its handoff with the catalog
---------------------------------------------------------------------------
do
  local CAT = R.RemindersCatalog
  local pf = PV.Parts()
  f:Hide(); f:Show(); Flush()
  Check(PV.Shown() and not CAT.Shown(), "the preview is up beside the window, the catalog is not")
  while #RM.List() > 2 do RM.Delete(RM.List()[#RM.List()].id) end   -- section 10 left the profile full
  Flush()
  local list = RM.List()
  local x, y = list[1], list[2]
  Check(x and y, "two reminders to move between")
  RM.SetEnabled(x.id, false)
  P.Select(x.id); Flush()
  Check(pf.sub.text == RM.Get(x.id).name and not RM.Get(x.id).enabled, "a turned-off reminder is previewed, and stays off")
  local shows0 = CT.Snapshot().shows
  P.Select(y.id); Flush()
  Check(pf.sub.text == RM.Get(y.id).name, "selecting another redraws the preview for it")
  RM.SetName(y.id, "Renamed here"); Flush()
  Check(pf.sub.text == "Renamed here", "an edit updates the preview")
  Check(CT.Snapshot().shows == shows0 and D.PreviewId() == nil, "previewing shows nothing in the world")

  -- the catalog takes the place, cancel gives it back for the same selection
  local framesBefore = made
  local cfg = Deep(RM.List())
  f.newButton.scripts.OnClick(f.newButton); Flush()
  Check(CAT.Shown() and not PV.Shown(), "New reminder: the catalog replaces the preview")
  P.Refresh()
  Check(CAT.Shown() and not PV.Shown(), "a redraw while it is open leaves the preview away")
  CAT.Hide(); Flush()
  Check(not CAT.Shown() and PV.Shown() and pf.sub.text == "Renamed here" and P.Selected() == y.id, "cancel: the preview is back for the same reminder")
  Check(Deep(RM.List()) == cfg, "and nothing was changed")

  -- creation: the preview is for the new, turned-off reminder
  f.newButton.scripts.OnClick(f.newButton); Flush()
  local card = CAT.Frame().cards[1]
  card.use.scripts.OnClick(card.use); Flush()
  local new = P.Selected()
  Check(new ~= y.id and not RM.Get(new).enabled and not CAT.Shown() and PV.Shown() and pf.sub.text == RM.Get(new).name, "creation: the catalog goes, the preview shows the new disabled reminder")
  RM.Delete(new); Flush()

  -- a refusal keeps the catalog, with no preview
  local mark = #RM.List()
  while #RM.List() < RM.MAX do RM.Create("custom") end
  f.newButton.scripts.OnClick(f.newButton); Flush()
  card = CAT.Frame().cards[1]
  card.use.scripts.OnClick(card.use); Flush()
  Check(CAT.Shown() and not PV.Shown(), "a refusal leaves the catalog up and the preview away")
  CAT.Hide(); Flush()
  while #RM.List() > mark do RM.Delete(RM.List()[#RM.List()].id) end
  Flush()

  -- lifecycle: leaving the page, closing the settings, reopening: nothing doubled
  f:Hide()
  Check(not PV.Shown(), "leaving the page hides the preview")
  f:Show(); Flush()
  Check(PV.Shown(), "and it is back with the page")
  local count = made
  for _ = 1, 4 do f:Hide(); f:Show(); Flush() end
  Check(made == count, "reopening makes no new frames: " .. (made - count))
  Check(PV.Parts().events == nil or next(PV.Parts().events) == nil, "the preview listens to nothing")
end

-- Preview navigation reveals the matching control without saving or asking the controller for a decision.
do
  Check(P.Create("enchant"), "enchant template with bundled oil artwork")
  Flush()
  local rid = P.Selected()
  local pv, editor = PV.Parts(), R.RemindersEditor
  local saved, rev = Deep(RM.Get(rid).raw), RM.Rev()
  local writes, inspections = 0, 0
  local setDisplay, inspect = RM.SetDisplay, CT.Inspect
  RM.SetDisplay = function(...) writes = writes + 1; return setDisplay(...) end
  CT.Inspect = function(...) inspections = inspections + 1; return inspect(...) end
  local reveal = R.SettingsUI.RevealFrame
  local target
  R.SettingsUI.RevealFrame = function(frame) target = frame end
  pv.visualHit.scripts.OnClick(pv.visualHit)
  Check(target == show.choose and editor.revealed == show.choose, "artwork click reveals and highlights the image chooser")
  pv.textHit.scripts.OnClick(pv.textHit)
  Check(target == show.textBox and editor.revealed == show.textBox, "words click reveals and highlights its text field")
  Check(writes == 0 and inspections == 0 and RM.Rev() == rev and Deep(RM.Get(rid).raw) == saved,
    "preview navigation writes nothing and reads no conditions")
  Check(not RM.Get(rid).enabled and D.PreviewId() == nil, "navigation leaves the draft off and the world preview closed")
  R.SettingsUI.RevealFrame, RM.SetDisplay, CT.Inspect = reveal, setDisplay, inspect

  local place = Fake("Frame")
  place:SetSize(612, 600)
  local anchor = Fake("Frame")
  anchor:SetSize(936, 480)
  anchor.GetPoint = function(self) return unpack(self.points[1] or {}) end
  anchor.GetLeft, anchor.GetRight, anchor.GetTop = function() return 44 end, function() return 980 end, function() return 680 end
  local getAnchor = R.SettingsAnchor
  R.SettingsAnchor = function() return anchor end
  PV.Place(place)
  Check(place.placement == "overlay" and place.points[1][1] == "CENTER", "narrow screens center the whole companion")
  R.SettingsAnchor = getAnchor
end

-- Geometry is checked in physical cursor units across owner and UIParent scales.
do
  local originalScale, originalCursor = c.UIParent.GetEffectiveScale, c.GetCursorPosition
  c.UIParent.GetEffectiveScale = function() return 0.8 end
  for _, scale in ipairs({ 0.6, 0.95, 1.2 }) do
    local clip, target = Fake("Frame"), Fake("Frame")
    clip.GetLeft, clip.GetRight = function() return 100 end, function() return 700 end
    clip.GetBottom, clip.GetTop = function() return 100 end, function() return 600 end
    target.GetLeft, target.GetRight = function() return 150 end, function() return 500 end
    target.GetBottom, target.GetTop = function() return 200 end, function() return 300 end
    clip.GetEffectiveScale, target.GetEffectiveScale = function() return scale end, function() return scale end
    local drag = R.RemindersRuleDrag.New(clip, function() return true end, function() end)
    drag:Row(target, "top", 1)
    drag.source = {}
    Check(drag:Find(200 * scale, 290 * scale).index == 1, "upper physical edge inserts before at scale " .. scale)
    Check(drag:Find(200 * scale, 210 * scale).index == 2, "lower physical edge inserts after at scale " .. scale)
    Check(not drag:Find(200 * scale, 99 * scale), "the clipped physical boundary rejects a drop")
    drag.ghost.GetEffectiveScale = function(self) return (self.scale or 1) * 0.8 end
    c.GetCursorPosition = function() return 240, 360 end
    drag:Start({ condition = { type = "player", state = "combat" } }, "Combat")
    local point = drag.ghost.points[1]
    Check(point[1] == "CENTER" and math.abs(point[4] * scale - 240) < 0.01
      and math.abs(point[5] * scale - 360) < 0.01, "the ghost stays centered on physical cursor coordinates")
    drag:Cancel()
    local owner = Fake("Button", c.UIParent)
    owner.GetEffectiveScale = function() return scale end
    R.SettingsMaterial.ContextTip(owner, "Condition", "Help")
    owner:Fire("OnEnter")
    local tip
    for _, child in ipairs(c.UIParent.children) do if child.owner == owner and child.body then tip = child end end
    -- (the fake UIParent's effective scale is 0.8; GetCursorPosition answers 240, 360 screen pixels)
    -- a child of UIParent: its effective scale is its own scale times UIParent's (the fake doesn't multiply by itself)
    if tip then
      tip.GetEffectiveScale = function(self) return (self.scale or 1) * 0.8 end
      owner:Fire("OnLeave"); owner:Fire("OnEnter")
    end
    local p = tip and tip.points[#tip.points]
    local ts = tip and tip.scale * 0.8
    Check(tip and math.abs(ts - scale) < 0.01, "context help is drawn at the owner's effective scale")
    Check(p and p[1] == "BOTTOMLEFT" and p[2] == c.UIParent and math.abs((p[4] - 16) * ts - 240) < 0.01
      and math.abs((p[5] - 14) * ts - 360) < 0.01, "context help sits at the mouse pointer, whatever the owner's position or scroll")
    c.GetCursorPosition = function() return 300, 380 end
    tip.scripts.OnUpdate(tip)
    p = tip.points[#tip.points]
    Check(p and math.abs((p[4] - 16) * ts - 300) < 0.01, "and follows the pointer while shown")
    local count = #tip.points
    tip.scripts.OnUpdate(tip)
    Check(#tip.points == count, "a frame with no pointer movement moves nothing")
    owner:Fire("OnLeave")
  end
  c.UIParent.GetEffectiveScale, c.GetCursorPosition = originalScale, originalCursor
end

-- Opening a material dropdown must not leak its look into the next ordinary Settings menu.
do
  local G, M = R.SettingsWidgets, R.SettingsMaterial
  local selected
  local b = G.Dropdown(c.UIParent, 180, function(value) selected = value end)
  b:SetChoices(function() return { { value = "a", label = "Main hand" }, { value = "b", label = "Off hand" } } end)
  b:SetValue("a", "Main hand")
  M.ReminderControl(b, "dropdown")
  b:Fire("OnEnter")
  Check(#b.text.points == 2 and b.text.points[1][1] == "LEFT" and b.text.points[2][1] == "RIGHT",
    "material dropdown values keep their inset alignment during hover")
  b:Fire("OnLeave")
  b:OpenMenu()
  local menu = c.TwichUISettingsMenu
  Check(menu.materialMode and menu.materialBackground:IsShown() and menu.rows[1].mark:IsShown(),
    "the material menu paints the current choice")
  menu.rows[2]:Fire("OnClick")
  Check(selected == "b" and not G.MenuShown(), "a material menu row still picks and closes normally")
  local plain = G.Dropdown(c.UIParent, 180)
  plain:SetChoices(b.choices)
  plain:OpenMenu()
  Check(menu.materialMode and menu.materialBackground:IsShown(),
    "ordinary Settings dropdowns share the same material menu presentation")
  local hooks = #menu.rows[1].hooks.OnEnter
  G.CloseMenu()
  b:OpenMenu()
  Check(#menu.rows[1].hooks.OnEnter == hooks, "reopening the material menu does not add listeners")
  G.CloseMenu()
end

-- Painted states preserve the control's callback, layout and configuration isolation.
do
  local G, M = R.SettingsWidgets, R.SettingsMaterial
  local calls, revision = 0, RM.Rev()
  local button = G.Button(c.UIParent, "Save", 116, "secondary", function() calls = calls + 1 end)
  local callback = button:GetScript("OnClick")
  M.ReminderControl(button, "confirmation")
  local sheet = button.twichCraft
  button:Fire("OnEnter"); button:Fire("OnMouseDown")
  Check(sheet.skin == "primary-down", "painted primary press has a recessed state")
  button:Fire("OnMouseUp"); button:Fire("OnLeave")
  button:SetEnabled(false); button:Fire("OnDisable"); button:Fire("OnEnter")
  Check(sheet.skin == "button-off", "a disabled primary never paints an active highlight")
  button:SetEnabled(true); button:Fire("OnEnable"); button:Fire("OnClick")
  Check(calls == 1 and button:GetScript("OnClick") == callback and RM.Rev() == revision,
    "painted states preserve the native callback and never change configuration")
  button.craftLabelInset = 35; button:Fire("OnEnable")
  Check(#button.text.points == 2 and button.text.points[1][1] == "LEFT" and button.text.points[2][1] == "RIGHT",
    "icon buttons retain their label inset after native state repaint")
  local field = G.EditBox(c.UIParent, 120, 28)
  M.ReminderControl(field, "field")
  field:SetEnabled(false); field:Fire("OnDisable")
  Check(field.twichCraft.skin == "field-off", "numeric/input fields repaint immediately when disabled")
  local primary = G.Button(c.UIParent, "Confirm", 116, "secondary", function() end)
  R.SettingsCraft.Control(primary, "primary")
  Check(primary.twichCraft.skin == "primary", "the reusable component's primary role selects the gold action")
end

-- P0: the hosted frame can remain individually shown under a hidden Settings ancestor.
-- Repeated subscriptions/events after closing must never restore the UIParent companion.
do
  local PV, CAT, DZ = R.RemindersPreview, R.RemindersCatalog, R.RemindersDesigner
  local rid = P.Selected()
  local savedName = RM.Get(rid).name
  PV.SetEnabled(true); editorOpen, editorPage = true, "reminders"
  P.Refresh(); Flush()
  local preview = PV.Parts()
  Check(PV.Shown(), "the active editor reconciles its enabled preview")
  P.QueueRefresh(0.2)
  editorOpen = false
  R.SettingsLauncher.Closed()
  Check(f:IsShown() and not PV.Shown(), "close hides the companion even if the hosted frame remains individually shown")
  for i = 1, 4 do
    RM.SetName(rid, "Closed reminder " .. i)
    c.FireEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    c.FireEvent("ZONE_CHANGED_NEW_AREA")
    P.QueueRefresh(); P.Refresh(); Flush()
    PV.Show(RM.Get(rid)); PV.Update(RM.Get(rid))
    Check(not PV.Shown(), "closed subscriptions, deferred refresh and direct show stay hidden, cycle " .. i)
  end
  editorOpen, editorPage = true, "notifications"
  P.Refresh(); Flush()
  PV.Show(RM.Get(rid))
  Check(not PV.Shown(), "another active Settings page cannot open the companion")
  editorPage = "reminders"; P.Refresh(); Flush()
  Check(PV.Shown() and PV.Parts() == preview, "reopening restores the same companion")
  PV.Hide(); PV.Update(RM.Get(rid))
  Check(not PV.Shown(), "content update alone never shows a hidden companion")
  P.Refresh(); Flush()
  DZ.Open(); Flush()
  for _ = 1, 3 do P.Refresh(); Flush(); Check(not PV.Shown(), "When keeps exclusive ownership") end
  DZ.Close(); Flush()
  Check(PV.Shown(), "closing When restores the active editor preview")
  CAT.Toggle(); Flush()
  for _ = 1, 3 do P.Refresh(); Flush(); Check(not PV.Shown(), "catalog keeps exclusive ownership") end
  CAT.Hide(); Flush()
  Check(PV.Shown(), "canceling the catalog restores the active editor preview")
  PV.SetEnabled(false); Flush()
  for _ = 1, 3 do P.Refresh(); Flush(); PV.Show(RM.Get(rid)); Check(not PV.Shown(), "disabled companion stays disabled on refresh") end
  Check(D.PreviewStart(RM.Get(rid), false), "explicit on-screen preview still starts independently")
  P.Refresh(); Flush()
  Check(D.PreviewId() == rid and not PV.Shown(), "world preview does not reopen the disabled editor companion")
  editorOpen = false; R.SettingsLauncher.Closed(); Flush()
  Check(D.PreviewId() == nil and not PV.Shown(), "Settings close also ends the explicit temporary world preview")
  for _ = 1, 3 do
    PV.SetEnabled(false); Flush()
    editorOpen = true; P.Refresh(); Flush()
    Check(not PV.Shown(), "disabled preference survives editor reopening")
    PV.SetEnabled(true); Flush()
    Check(PV.Shown() and PV.Parts() == preview, "explicit re-enable reuses the existing companion")
    editorOpen = false; R.SettingsLauncher.Closed(); Flush()
    for _ = 1, 3 do P.Refresh(); P.QueueRefresh(); Flush(); Check(not PV.Shown(), "repeated close cannot be undone by refresh") end
  end
  RM.SetName(rid, savedName)
  editorOpen = true; P.Refresh(); Flush()
end

-- Contextual actions belong to the invoked reminder, not the selected one.
do
  DZ.Close(); R.RemindersCatalog.Hide(); editorOpen, editorPage = true, "reminders"
  P.Select(id); P.Refresh(); Flush()
  local source = parts.rows[1]
  local originalId, selectedBefore, rev = source.id, P.Selected(), RM.Rev()
  source:Fire("OnClick", "RightButton")
  local menu = c.TwichUISettingsMenu
  Check(RM.Rev() == rev and P.Selected() == selectedBefore and menu.shown, "right-click opens actions without selecting or toggling")
  Check(menu.w >= 112 and menu.w < 180, "context menu width follows its short labels")
  source:Fire("OnClick", "LeftButton"); Flush()
  Check(not menu.shown and P.Selected() == originalId and RM.Rev() == rev, "left-click dismisses the popup and selects without toggling")
  source:Fire("OnClick", "RightButton")
  menu.rows[1]:Fire("OnClick"); Flush()
  local copy = P.Selected()
  Check(copy ~= originalId and RM.Get(copy) and not RM.Get(copy).enabled, "context Duplicate creates a new disabled reminder")
  RM.SetName(copy, "Independent copy")
  Check(RM.Get(originalId).name ~= "Independent copy", "context duplicate owns its mutable configuration")
  local invoked
  for _, row in ipairs(parts.rows) do if row.id == copy then invoked = row end end
  invoked:Fire("OnClick", "RightButton"); menu.rows[2]:Fire("OnClick")
  Check(S.popup.text:find("Independent copy", 1, true) and RM.Get(copy), "context Delete identifies its target before mutation")
  c.StaticPopupDialogs[S.popup.key].OnCancel(); Flush()
  Check(RM.Get(copy), "canceling context deletion preserves the reminder")
  invoked:Fire("OnClick", "RightButton"); menu.rows[2]:Fire("OnClick")
  c.StaticPopupDialogs[S.popup.key].OnAccept(); Flush()
  Check(not RM.Get(copy) and RM.Get(originalId), "confirmed context deletion removes only its target")
end

-- Four backgrounds are session-only, including a genuinely hollow well; hidden refreshes cannot reopen it.
do
  P.Select(id); P.Refresh(); Flush()
  local preview, rev = PV.Parts(), RM.Rev()
  for _, mode in ipairs({ "landscape", "parchment", "transparent", "dark" }) do
    Check(PV.SetBackground(mode) and preview.background == mode and PV.Shown(), "active editor accepts " .. mode .. " background")
    Check(preview.boxFace.parts[1].shown == (mode == "dark"), "opaque well is removed outside Dark")
  end
  Check(RM.Rev() == rev, "background selection never edits display, position or live rules")
  editorOpen = false; R.SettingsLauncher.Closed(); Flush()
  for _, mode in ipairs({ "transparent", "landscape", "parchment", "dark" }) do
    PV.SetBackground(mode); P.Refresh(); Flush()
    Check(not PV.Shown(), "background refresh cannot reopen a closed companion")
  end
  editorOpen = true; P.Refresh(); Flush()
end

-- A focused placement transaction never saves intermediate drags, and survives gameplay refreshes safely.
do
  local placement = R.RemindersPlacement
  local function Move()
    local frame = D.Frame(id)
    frame.GetLeft, frame.GetRight = function() return 160 end, function() return 260 end
    frame.GetTop, frame.GetBottom = function() return 350 end, function() return 300 end
    frame.handle:Fire("OnDragStop")
  end
  local before, rev = Deep(RM.Get(id).place), RM.Rev()
  Check(placement.Start(RM.Get(id)) and not editorOpen and not PV.Shown(), "placement hides settings and its editing companion")
  Move()
  local moved = D.PlacementDraft()
  Check(moved and Deep(RM.Get(id).place) == before and RM.Rev() == rev, "drag changes only private coordinates")
  for _ = 1, 3 do CT.Refresh(); P.Refresh(); Flush(); Check(not PV.Shown(), "gameplay refresh cannot show editor during placement") end
  placement.Cancel(true); Flush()
  Check(editorOpen and not placement.Active() and Deep(RM.Get(id).place) == before and RM.Rev() == rev, "Cancel discards draft coordinates and restores context")
  D.Frame(id).handle:Fire("OnDragStop"); Flush()
  Check(Deep(RM.Get(id).place) == before and RM.Rev() == rev, "a late mouse release after Cancel cannot write placement")
  Check(placement.Start(RM.Get(id)), "placement can reopen")
  Move(); moved = D.PlacementDraft()
  Check(D.PlacementFinish(true), "Finish accepts valid draft coordinates")
  Flush()
  Check(RM.Get(id).place.x == moved.x and RM.Get(id).place.y == moved.y and RM.Rev() == rev + 1 and PV.Shown(), "Finish commits exactly once and restores the companion")
  local live = Deep(RM.Get(id).place)
  placement.Start(RM.Get(id)); Move()
  for _, frame in ipairs(created) do if frame.events.PLAYER_REGEN_DISABLED then frame:Fire("OnEvent", "PLAYER_REGEN_DISABLED") end end
  Flush()
  Check(not placement.Active() and not D.Positioning() and Deep(RM.Get(id).place) == live, "combat ends placement without saving the draft")
  placement.Start(RM.Get(id)); Move()
  local current = RM.Get(id).place
  RM.SetPosition(id, current.point, current.x + 5, current.y + 7)
  local changed, revision = Deep(RM.Get(id).place), RM.Rev()
  Check(not D.PlacementFinish(true), "Finish refuses a position changed by another writer")
  Check(RM.Rev() == revision and Deep(RM.Get(id).place) == changed, "a rejected placement preserves the newer position")
  placement.Cancel(true); Flush()
  P.Create("enchant"); Flush()
  local deleted = P.Selected()
  placement.Start(RM.Get(deleted))
  RM.Delete(deleted); Flush()
  Check(not placement.Active() and editorOpen and D.PreviewId() == nil, "deletion cancels placement and restores safe editing context")
  P.Select(id); P.Refresh(); Flush()
end

-- Scroll easing is bounded, clamped, cancelable, and bypassed with reduced motion.
do
  local G = R.SettingsWidgets
  local scroll = Fake("ScrollFrame", c.UIParent)
  local child = Fake("Frame", scroll); child:SetHeight(700)
  scroll:SetHeight(200); scroll:SetScrollChild(child)
  G.ScrollMotion(scroll)
  scroll:Fire("OnMouseWheel", -1)
  Check(scroll.motionDriver:GetScript("OnUpdate") ~= nil, "wheel starts a finite easing interval")
  scroll.motionDriver:Fire("OnUpdate", .12)
  Check(scroll:GetVerticalScroll() == 24 and not scroll.motionDriver:GetScript("OnUpdate"), "one wheel notch reaches 24 units and stops updating")
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}; c.TwichUIDB.ui.reduceSettingsMotion = true
  scroll:Fire("OnMouseWheel", -100)
  Check(scroll:GetVerticalScroll() == 500 and not scroll.motionDriver:GetScript("OnUpdate"), "reduced motion jumps precisely to the clamped destination")
  child:SetHeight(100); scroll:Fire("OnMouseWheel", 1)
  Check(scroll:GetVerticalScroll() == 0, "short content cannot scroll past its bounds")
  c.TwichUIDB.ui.reduceSettingsMotion = nil
end

-- Font names use their own supported files and selection still goes through Config.
do
  P.Select(id); local Ed = R.RemindersEditor
  Ed.placementOpen, Ed.moreOpen = true, true; P.Refresh(); Flush()
  local old = RM.Get(id).display.font
  local font = place.font
  font:OpenMenu()
  local menu = c.TwichUISettingsMenu
  for _, row in ipairs(menu.rows) do
    if row.choice then Check(row.choice.font and row.text.font[1] == row.choice.font, "each font option renders only its label in the resolved typeface") end
  end
  local choices = font.choices()
  if #choices > 1 then
    font.onPick(choices[2].value); Flush()
    Check(RM.Get(id).display.font == choices[2].value, "font preview options retain normal persisted selection")
    font.onPick(old); Flush()
  end
  R.SettingsWidgets.CloseMenu()
  Ed.placementOpen, Ed.moreOpen = false, false; P.Refresh(); Flush()
end

-- UIParent popups need scroll transforms once, in the owner's scale.
do
  local outer = Fake("ScrollFrame", c.UIParent)
  outer.IsObjectType = function(_, kind) return kind == "ScrollFrame" end
  outer.GetHorizontalScroll = function() return 3 end
  outer:SetVerticalScroll(80)
  local inner = Fake("Frame", outer)
  local owner = Fake("Button", inner)
  owner.GetParent = function() return inner end; inner.GetParent = function() return outer end
  outer.GetParent = function() return nil end
  owner.GetLeft, owner.GetRight = function() return 100 end, function() return 200 end
  owner.GetBottom, owner.GetTop = function() return 50 end, function() return 70 end
  local l, r, b, t = R.SettingsWidgets.VisibleRect(owner)
  Check(l == 97 and r == 197 and b == 130 and t == 150, "popup rectangle includes scrolling in both axes")
end

-- Structured summaries retain Any grouping, negated leaves and every supported nested condition.
do
  P.Create("custom"); Flush()
  local rid = P.Selected()
  local ok, group = RM.AddGroup(rid, nil, "any")
  RM.AddCondition(rid, "player", group, { type = "player", state = "mounted", negate = true })
  RM.AddCondition(rid, "player", group, { type = "player", state = "combat" })
  local v, before = RM.Get(rid), Deep(RM.Get(rid).raw)
  local rows = R.RemindersPlain.Explanation(v)
  Check(rows[2].text == "Any of these" and rows[3].text:find("not mounted", 1, true)
    and rows[4].text:find("in combat", 1, true), "advanced summary keeps nested Any and negation")
  Check(Deep(RM.Get(rid).raw) == before and not R.RemindersPlain.Basic(v), "summary presentation preserves the advanced tree")
  RM.Delete(rid); P.Select(id); Flush()
end

-- The promoted control reuses the existing transaction; both entry points stay equivalent.
do
  local placement = R.RemindersPlacement
  P.Select(id); R.RemindersEditor.placementOpen = false; P.Refresh(); Flush()
  Check(f.place == place.move and f.place.shown and f.place.text.text == "Place on screen"
    and f.place.points[1][2] == f.head, "placement is a primary header action with Advanced closed")
  local start, calls = placement.Start, 0
  placement.Start = function(view) calls = calls + 1; return start(view) end
  local before, enabled = Deep(RM.Get(id).place), RM.Get(id).enabled
  for _, entry in ipairs({ f.place, PV.Parts().place }) do
    entry:Fire("OnClick"); Flush()
    Check(placement.Active() and D.PreviewId() == id and not PV.Shown(), "a Place entry uses focused placement")
    placement.Cancel(true); Flush()
    Check(Deep(RM.Get(id).place) == before and RM.Get(id).enabled == enabled and PV.Shown(), "Place/Cancel preserves data and restores the editor")
  end
  Check(calls == 2, "main editor and companion both call the same placement API")
  placement.Start = start
end

-- Distinct condition-type art reaches every consumer through the same resolver.
do
  local Pl = R.RemindersPlain
  local conditions = { {type="weaponEnchant"}, {type="player",state="combat"}, {type="player",state="mounted"} }
  local seen = {}
  for _, cond in ipairs(conditions) do
    local texture = Fake("Texture", c.UIParent)
    for _, size in ipairs({22,30,45}) do
      Pl.ApplyArt(texture, cond, size)
      Check(texture.texture == Pl.ArtFile(cond,size) and texture.w == size and texture.h == size, "dedicated condition art uses balanced square runtime files")
    end
    Check(not seen[texture.texture], "unrelated conditions do not share artwork")
    seen[texture.texture] = true
  end
  local choices = Pl.Entries()
  for _, entry in ipairs(choices) do
    local texture = Fake("Texture", c.UIParent)
    Pl.ApplyArt(texture, entry.make(),30)
    Check(texture.texture ~= nil, "every supported palette entry retains artwork: " .. entry.key)
  end
  Check(Pl.ArtFile({type="player",state="mounted"},22):find("horse%-head%-small.tga"), "Mounted reuses original painted horse art")
end

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
