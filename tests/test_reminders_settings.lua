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
local function Fake(kind, parent)
  made = made + 1
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
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
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
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
Check(parts.sections and #parts.sections == 5, "the five sections are built")
Check(f.empty.shown and f.empty.text:find("No reminders yet"), "an empty list says how to start")
Check(#f.templates == 4 and f.templates[1].shown, "four ways to start")
Check(f.events.PLAYER_EQUIPMENT_CHANGED and f.events.GET_ITEM_INFO_RECEIVED, "while shown it hears what Test reads")
local createdBefore = made

Check(P.Create("shield"), "Missing shield")
Flush()
local id = P.Selected()
local v = RM.Get(id)
Check(v and v.name == "Shield reminder" and not v.enabled, "a draft, opened")
local row = parts.rows[1]
Check(row.shown and row.name.text == "Shield reminder" and row.state.text == "Off" and not row.check:GetChecked(), "its row: name, Off, unchecked")
Check(row.rule.text == "Shows when: Off hand is not Shield.", "its rule in a sentence: " .. row.rule.text)
Check(not f.empty.shown and f.head.shown and f.nameBox.text == "Shield reminder", "the editor's head")
Check(f.say.shown and f.say.text:find("stays off until you turn it on"), "it says it is off: " .. f.say.text)

local show, when, place, preview, test = unpack(parts.sections)
Check(show.shown and show.mode.text.text == "Artwork with text" and show.art.text.text == "Shield" and show.textBox.text == "Equip your shield", "Show: artwork with text")
Check(not show.icon.shown and not show.itemBox.shown, "Show: no icon choices for artwork")
local cd = when.cards[1]
Check(cd.shown and cd.text.text == "Your off hand is not a shield" and cd.edit.shown and cd.more.shown, "When: the condition is a card, a sentence with Edit and More")
Check(not when.rootGroup.heading.shown and not when.rootGroup.segall.shown, "one condition: no group heading and no all or any choice")
Check(when.who.text == "This character only" and when.whoEdit.shown and not when.target.shown, "who it is for: one line, Edit closed")
Check(when.lines[1].text == "Shows when: Your off hand is not a shield." and not when.lines[2].shown, "why: the rule in one line")
Check(not when.exHead.shown and not when.editor.shown and not when.picker.shown, "nothing else is open: no explanation, no editor, no picker")
Check(when.note.shown and when.note.text == RM.SHIELD_NOTE, "the template's explanation")
Check(when.rootGroup.add.shown and when.rootGroup.add.text.text == "Add a condition", "Add a condition belongs to the group")
local OFFHAND = {}
for _, ch in ipairs(R.RemindersPlain.ValueChoices(RM.Get(id).conditions[1].cond)) do OFFHAND[#OFFHAND + 1] = ch.label end
Check(table.concat(OFFHAND, ",") == "Empty,Shield,Weapon,Held in off hand,A specific item", "the off hand's own choices only: " .. table.concat(OFFHAND, ","))

---------------------------------------------------------------------------
-- 3. Test: right now, and simulated
---------------------------------------------------------------------------
EQUIP[17] = nil
P.Refresh()
Check(test.live[1].text == "Off hand is not Shield  -  Match  -  Observed: Empty", "right now, for a draft: " .. test.live[1].text)
Check(test.liveResult.text:find("^Result: Disabled") and test.liveResult.text:find("Turn it on"), "the result says why: " .. test.liveResult.text)
f.onBox.scripts.OnClick(f.onBox)
Flush()
Check(RM.Get(id).enabled and CT.Status(id) == "showing" and parts.rows[1].state.text == "Showing", "turned on: showing")
Check(test.liveResult.text:find("^Result: Showing") and test.liveResult.text:find("All conditions match"), "live result: " .. test.liveResult.text)
Check(test.simTag.shown and test.picks[1].shown and test.picks[1].text.text == "Shield equipped", "a simulated situation per condition")
local liveObs = ST.Observations().slots[17]
test.picks[1].onPick("match")
Flush()
Check(test.simResult.text:find("^Simulated result: Hidden"), "simulated shield: hidden: " .. test.simResult.text)
Check(test.sim[1].text:find("No match") and test.sim[1].text:find("Simulated: A shield"), "simulated line: " .. test.sim[1].text)
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
Check(test.live[1].text:find("^Off hand is empty  %-  Match"), "a draft's live line: " .. test.live[1].text)
EQUIP[17] = 1201
f.scripts.OnEvent(f, "PLAYER_EQUIPMENT_CHANGED", 17)
Flush()
Check(test.live[1].text:find("No match") and test.live[1].text:find("Shield"), "after the event it reads again: " .. test.live[1].text)
Check(ST.Observations().slots[17] ~= nil and ST.Snapshot().keys == 1, "the draft's look never adds to what the live reminders read")
RM.Delete(tid)
P.Select(id)
Flush()

---------------------------------------------------------------------------
-- 4. Editing the rule: a card opens one editor that works on a copy; Done writes it, Cancel leaves it
---------------------------------------------------------------------------
local ed, pk = when.editor, when.picker
local function Click(b) b.scripts.OnClick(b); Flush() end
local function X(frame) return frame.points[1] and frame.points[1][4] end
-- opens a group's picker and chooses what it offers by its key; false when it isn't there
local picked   -- what the picker said when it was open: its title and where it adds
local function Pick(group, key)
  Click(group.add)
  picked = { title = pk.title.text, where = pk.where.text, shown = pk.shown }
  for _, row in ipairs(pk.rows) do
    if row.shown and row.entry and row.entry.key == key then Click(row) return true end
  end
  return false
end
local function Line(i) local fs = when.lines[i] return fs and fs.shown and (fs.text:gsub("^%-  ", "")) or nil end   -- a summary line without its dash
local function Shown()   -- the sentences of the cards that are on screen, in order
  local out = {}
  for _, card in ipairs(when.cards) do if card.shown then out[#out + 1] = card.text.text end end
  return out
end
local function Menu(owner)
  local out = {}
  for _, ch in ipairs(owner.more.choices()) do out[#out + 1] = ch.label end
  return table.concat(out, " | ")
end

local rev0 = RM.Rev()
Click(cd.edit)
Check(ed.shown and ed.title.text == "Edit this condition" and ed.subject.shown and ed.subject.text.text == "Off hand" and ed.op.text.text == "is not" and ed.value.text.text == "Shield", "Edit: the editor opens under the card with its fields")
Check(ed.reads.text == "Reads as: Your off hand is not a shield" and ed.help.text:find("one equipment slot"), "it reads the condition back, with a line of help: " .. ed.reads.text)
Check(ed.done.text.text == "Done" and ed.cancel.shown and RM.Rev() == rev0, "Done and Cancel; opening it changes nothing")
ed.subject.onPick("slot:mainHand")
Flush()
Check(ed.reads.text == "Reads as: Your main hand is not empty" and ed.value.text.text == "Empty", "a change shows in the editor at once: " .. ed.reads.text)
Check(RM.Get(id).conditions[1].cond.slot == "offHand" and RM.Rev() == rev0, "and is saved only on Done: nothing has been written")
Click(ed.cancel)
Check(not ed.shown and RM.Get(id).conditions[1].cond.slot == "offHand" and RM.Rev() == rev0, "Cancel: the saved condition is as it was and nothing was written")
Click(cd.edit)
Click(ed.done)
Check(not ed.shown and RM.Rev() == rev0, "Done on a condition that was not changed writes nothing")
Click(cd.edit)
ed.subject.onPick("slot:mainHand")
ed.value.onPick("weapon")
Flush()
Click(ed.done)
local c1 = RM.Get(id).conditions[1].cond
Check(not ed.shown and c1.slot == "mainHand" and c1.what == "weapon" and c1.negate == true and cd.text.text == "Your main hand is not a weapon", "Done: written, and the card says it: " .. cd.text.text)
Click(cd.edit)
ed.subject.onPick("slot:offHand")
ed.value.onPick("shield")
Flush()
Click(ed.done)
Check(RM.Get(id).conditions[1].cond.slot == "offHand" and RM.Get(id).conditions[1].cond.what == "shield", "and back to the shield")

-- a second condition: picked, set up, and only then added
Check(Pick(when.rootGroup, "player:combat"), "Add a condition opens a picker, and the player's combat state is one of its choices")
Check(picked.shown and picked.title == "Require another condition" and picked.where == "Adding to the group where all of these must be true.", "the picker says it is for the group where all must be true: " .. tostring(picked.where))
Check(ed.shown and ed.title.text == "Add: You are in combat" and not ed.subject.shown and ed.op.shown and ed.value.text.text == "In combat" and ed.done.text.text == "Add condition", "after choosing, only the values it needs are asked for")
Check(#RM.Get(id).conditions == 1, "nothing is added until Add condition")
Click(ed.cancel)
Check(not ed.shown and #RM.Get(id).conditions == 1, "Cancel adds nothing")
Pick(when.rootGroup, "player:combat")
Click(ed.done)
local v2 = RM.Get(id)
Check(#v2.conditions == 2 and v2.conditions[2].cond.state == "combat" and not ed.shown and not pk.shown, "added, and the picker and editor are put away")
Check(when.cards[2].shown and when.cards[2].text.text == "You are in combat", "its card")
Check(when.rootGroup.heading.shown and when.rootGroup.heading.text == "All of these must be true" and when.rootGroup.segall.shown, "two conditions: the group has its heading and the All and Any choice")
Check(when.seps[1].shown and when.seps[1].text == "and", "joined by a quiet \"and\"")
Check(Line(1) == "Shows when all of these are true:" and Line(2) == "Your off hand is not a shield" and Line(3) == "You are in combat", "the summary: a heading and a line each")
Click(when.rootGroup.segany)
Check(RM.Get(id).match == "any" and when.rootGroup.heading.text == "At least one of these must be true" and when.seps[1].text == "or" and Line(1) == "Shows when at least one of these is true:", "Any: the heading, the separator and the summary follow")
Click(cd.edit)
Click(when.cards[2].edit)
Check(ed.shown and ed.title.text == "Edit this condition", "opening another card moves the one editor")
ed.op.onPick("isnot")
Flush()
Click(ed.done)
Check(RM.Get(id).conditions[2].cond.negate == true and when.cards[2].text.text == "You are not in combat", "is not")
-- the More menu
Check(Menu(when.cards[2]) == "Edit | Duplicate | Move up | Remove", "More on the last card: Edit, Duplicate, Move up, Remove: " .. Menu(when.cards[2]))
Check(Menu(cd) == "Edit | Duplicate | Move down | Remove", "and on the first: Move down, no Move up: " .. Menu(cd))
cd.more.onPick("down")
Flush()
Check(Shown()[1] == "You are not in combat" and Shown()[2] == "Your off hand is not a shield", "Move down reorders")
Check(RM.Get(id).match == "any", "(and the match stays as it was)")
when.cards[1].more.onPick("up")
Flush()
when.cards[2].more.onPick("up")
Flush()
Check(Shown()[1] == "Your off hand is not a shield", "Move up reorders (back)")
when.cards[2].more.onPick("dup")
Flush()
Check(#RM.Get(id).conditions == 3 and Shown()[3] == "You are not in combat" and f.say.text:find("copy"), "Duplicate: a copy right after it")
when.cards[3].more.onPick("remove")
Flush()
Check(#RM.Get(id).conditions == 2 and when.undoText.shown and when.undoText.text == "Removed You are not in combat." and when.undo.shown, "Remove, and it says what was removed and offers Undo")
Click(when.undo)
Check(#RM.Get(id).conditions == 3 and not when.undo.shown, "Undo puts it back")
when.cards[3].more.onPick("remove")
Flush()
when.cards[2].more.onPick("remove")
Flush()
Check(#RM.Get(id).conditions == 1 and Shown()[1] == "Your off hand is not a shield", "removed down to the shield")
Check(Line(1) == "Shows when: Your off hand is not a shield." and not when.rootGroup.heading.shown, "back to the single line and the simple card")

-- ammunition: no "is not", four choices that read as a sentence
Check(Pick(when.rootGroup, "ammunition"), "ranged ammunition is offered")
Check(ed.title.text == "Add: Your ranged ammunition" and not ed.op.shown and ed.value.text.text == "has a problem", "ammunition reads as a sentence on its own: no \"is not\"")
local ammoChoices = ed.value.choices()
Check(#ammoChoices == 4 and ammoChoices[3].value == "outOfAmmo" and ammoChoices[3].label == "is used up" and ammoChoices[3].tooltip, "four choices, each explained")
Check(ed.reads.text == "Reads as: Ranged ammunition needs attention", "reads: " .. ed.reads.text)
ed.value.onPick("outOfAmmo")
Flush()
Click(ed.done)
Check(RM.Get(id).conditions[2].cond.what == "outOfAmmo" and when.cards[2].text.text == "Ranged ammunition is used up", "the choice is stored and read back")
-- (this test client has no way to say whether a weapon takes ammunition: the card, the page and the picker say so in a line)
Check(when.cards[2].state.shown and when.cards[2].note.text == "Cannot check ammunition on this client." and when.cards[2].stateTip == "The client does not report whether this ranged weapon uses ammunition.",
  "a limit of the client is one short line on the card, with the longer words on its mark: " .. tostring(when.cards[2].note.text))
Check(f.problems.shown and f.problems.text:find("Cannot check ammunition on this client.", 1, true) and not f.problems.text:find("Condition 2", 1, true) and not f.problems.text:find("game client doesn't say", 1, true),
  "and the list of what needs attention says the same, not the technical paragraph: " .. f.problems.text)
Check(parts.rows[1].rule.text == "Cannot check ammunition on this client.", "and so does the list row: " .. parts.rows[1].rule.text)
Click(when.cards[2].edit)
ed.subject.onPick("player")
Flush()
Click(ed.done)
Check(RM.Get(id).conditions[2].cond.type == "player", "the subject changes the kind")
Click(when.cards[2].edit)
ed.subject.onPick("ammo")
Flush()
Click(ed.done)
Check(RM.Get(id).conditions[2].cond.type == "ammunition", "and back")
when.cards[2].more.onPick("remove")
Flush()
Check(#RM.Get(id).conditions == 1, "removed")

---------------------------------------------------------------------------
-- 5. A missing item: by link, and its icon follows
---------------------------------------------------------------------------
P.Create("item")
Flush()
local iid = P.Selected()
Check(f.problems.shown and f.problems.text:find("Before it can be turned on") and f.problems.text:find("item"), "its problems are listed: " .. f.problems.text)
f.onBox.scripts.OnClick(f.onBox)
Flush()
Check(not RM.Get(iid).enabled and f.say.text:find("item"), "it can't be turned on yet, and says why")
local ic = when.cards[1]
Check(ic.text.text == "You don't have an item equipped" and ic.state.shown and ic.note.text:find("Choose the item"), "its card says what is missing: " .. tostring(ic.note.text))
Click(ic.edit)
Check(ed.shown and ed.item.shown and ed.subject.text.text == "Any equipment slot", "any slot, with an item box")
local anyLabels = {}
for _, ch in ipairs(ed.value.choices()) do anyLabels[#anyLabels + 1] = ch.label end
Check(table.concat(anyLabels, ",") == "A specific item", "any slot offers only a specific item")
Check(ed.problem.shown and ed.problem.text:find("Choose the item") and ed.done.enabled == false, "Done waits for the item, and says why")
ed.item:SetText("|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r")
ed.item.scripts.OnEnterPressed(ed.item)
Flush()
Check(ed.itemInfo.text:find("Hearthstone") and ed.reads.text == "Reads as: You don't have Hearthstone equipped" and ed.done.enabled == true, "the item is named in the editor: " .. ed.itemInfo.text)
Check(RM.Get(iid).conditions[1].cond.item == nil, "and not saved yet")
Click(ed.done)
local iv = RM.Get(iid)
Check(iv.conditions[1].cond.item == 6948 and iv.display.item == 6948 and iv.valid, "Done: the link's item, and the icon uses it")
Check(ic.text.text == "You don't have Hearthstone equipped" and Line(1) == "Shows when: You don't have Hearthstone equipped.", "its sentence and summary: " .. tostring(Line(1)))
Click(ic.edit)
ed.item:SetText("not an item")
ed.item.scripts.OnEnterPressed(ed.item)
Flush()
Check(f.say.text:find("isn't an item ID") and RM.Get(iid).conditions[1].cond.item == 6948, "a bad item is refused, nothing changes")
Click(ed.cancel)
Check(show.src.shown and show.src.text.text == "An item's icon" and show.itemInfo.text:find("Hearthstone"), "Show: an item's icon, named")

---------------------------------------------------------------------------
-- 5b. Groups: a class, a group that allows either, which group receives what
---------------------------------------------------------------------------
P.Create("custom")
Flush()
local gid = P.Selected()
Check(when.rootGroup.empty.shown and when.rootGroup.empty.text:find("never shows") and not when.cards[1].shown and when.rootGroup.add.shown, "a new custom reminder: an empty rule says it never shows, and where to start")
Check(Line(1):find("add a condition") and not when.rootGroup.heading.shown, "and the summary says to add one")
Check(Pick(when.rootGroup, "class"), "Your class is offered")
Check(ed.title.text == "Add: Your class" and ed.value.text.text == "Choose a class" and ed.done.enabled == false and ed.problem.shown, "a class starts unfinished, and Add waits for it: " .. tostring(ed.problem.text))
Click(ed.done)
Check(#RM.Get(gid).conditions == 0, "pressing it anyway adds nothing")
local classChoices = ed.value.choices()
Check(#classChoices == 9 and classChoices[1].value == "WARRIOR" and classChoices[1].label == "Warrior", "nine classes, stored as tokens and shown as names")
ed.value.onPick("WARRIOR")
Flush()
Click(ed.done)
Check(RM.Get(gid).conditions[1].cond.class == "WARRIOR" and when.cards[1].text.text == "Your class is Warrior" and RM.Get(gid).valid, "chosen: Warrior")
-- a group, with what it will be said before it is made
Click(when.rootGroup.add)
Check(pk.shown and pk.title.text == "Require another condition", "the picker")
local groupRow
for _, row in ipairs(pk.rows) do if row.shown and row.isGroup then groupRow = row end end
Check(groupRow and groupRow.name.text == "Create a condition group", "a group is offered apart from the conditions")
Click(groupRow)
Check(pk.newNote.shown and pk.newNote.text:find("inside \"All of these must be true\"") and pk.newAny.shown and pk.newAll.shown and pk.back.shown, "it says where the group goes and offers how it combines")
Check(#RM.Get(gid).conditions == 1, "nothing has been added yet")
Click(pk.back)
Check(pk.shown and not pk.newAny.shown, "Back returns to the picker")
Click(groupRow)
Click(pk.newAny)
local g1 = when.groups[1]
Check(RM.Get(gid).conditions[2].group and RM.Get(gid).conditions[2].match == "any" and g1.heading.shown and g1.heading.text == "At least one of these must be true", "a group that allows either: " .. tostring(g1.heading.text))
Check(f.say.text:find("Added an empty group") and f.say.text:find("at least one"), "and it says what it did: " .. f.say.text)
Check(when.rootGroup.heading.shown and when.rootGroup.heading.text == "All of these must be true", "the top level did not change its all or any because something was added")
Check(g1.empty.shown and g1.empty.text:find("can't be turned on") and g1.problem.shown, "an empty group says it needs a condition")
Check(f.problems.text:find("Group 2"), "and the reminder lists it")
Check(g1.add.shown and g1.segany.shown and g1.more.shown and g1.fold.shown, "a group has its own Add, its All and Any, its More and its fold")
-- conditions go into the group they were asked for
Check(Pick(g1, "class"), "the group's own picker")
Check(pk.title.text == "Allow another condition", "for a group where at least one must be true, it says Allow: " .. pk.title.text)
ed.value.onPick("WARRIOR")
Flush()
Click(ed.done)
for _, token in ipairs({ "HUNTER", "ROGUE" }) do
  Pick(g1, "class")
  ed.value.onPick(token)
  Flush()
  Click(ed.done)
end
local raw = RM.Get(gid).raw
Check(#raw.conditions == 2 and #raw.conditions[2].conditions == 3, "added to the group, not the top level")
local cards = when.cards
Check(X(cards[2]) > X(cards[1]), "a group's cards are indented under its box")
Check(when.seps[1].text == "and" and when.seps[2].text == "or" and when.seps[3].text == "or", "joined by and between the two, or inside the group that allows either")
Check(g1.outcome and not g1.outcome.shown, "(and no result lines while nothing is being explained)")
Check(RM.Get(gid).valid and Line(1) == "Shows when all of these are true:" and Line(2) == "Your class is Warrior" and Line(3) == "Your class is Warrior, Hunter or Rogue", "the summary follows the tree: " .. tostring(Line(3)))
-- the first becomes "in combat": the example in the request
Click(cards[1].edit)
ed.subject.onPick("player")
Flush()
Click(ed.done)
Check(RM.Get(gid).conditions[1].cond.type == "player" and cards[1].text.text == "You are in combat", "the first is now \"You are in combat\"")
Check(Line(2) == "You are in combat" and Line(3) == "Your class is Warrior, Hunter or Rogue", "(Warrior or Hunter or Rogue) and in combat: " .. tostring(Line(3)))
-- is not, in the group
Click(cards[3].edit)
ed.op.onPick("isnot")
Flush()
Click(ed.done)
local joined = table.concat({ Line(1) or "", Line(2) or "", Line(3) or "", Line(4) or "", Line(5) or "" }, "|")
Check(RM.Get(gid).raw.conditions[2].conditions[2].negate == true and joined:find("Your class is not Hunter"), "is not inside a group: " .. joined)
Click(cards[3].edit)
ed.op.onPick("is")
Flush()
Click(ed.done)
-- the Test section: one choice for the three classes, a line for the group and for each condition
Check(test.picks[1].shown and test.picks[2].shown and not test.picks[3].shown, "Test: one choice for combat and one for the three classes")
Check(test.pickLabels[2].text:find("Player class") and test.pickLabels[2].text:find("3 conditions"), "labelled as shared: " .. test.pickLabels[2].text)
Check(test.live[1].shown and test.live[2].text:find("^Match any %- OR  %-  "), "Right now has a line for the group: " .. tostring(test.live[2].text))
Check(X(test.live[3]) > X(test.live[2]) and X(test.live[3]) > X(test.live[1]), "its conditions a step in")
test.picks[2].onPick("ROGUE")
test.picks[1].onPick("on")
Flush()
Check(test.simResult.text:find("^Simulated result: Showing"), "simulated Rogue in combat: " .. test.simResult.text)
Check(test.sim[2].text:find("^Match any %- OR  %-  Match"), "the group's simulated result: " .. test.sim[2].text)
test.picks[2].onPick("MAGE")
Flush()
Check(test.simResult.text:find("^Simulated result: Hidden") and test.sim[2].text:find("No match"), "simulated Mage: hidden")
Check(RM.Get(gid).enabled == false and CT.Status(gid) == "disabled", "simulating changed nothing")

-- moving: within a group, and into another, with the meaning said
cards[2].more.onPick("down")
Flush()
Check(RM.Get(gid).raw.conditions[2].conditions[2].class == "WARRIOR" and RM.Get(gid).raw.conditions[2].conditions[1].class == "HUNTER", "Move down inside the group")
local menu3 = Menu(cards[3])
Check(menu3:find("Move into: the whole rule: All of these must be true") and menu3:find("Move up") and menu3:find("Move down"), "a card in a group offers Move into the whole rule, with what that is: " .. menu3)
cards[3].more.onPick("to:1")
Flush()
Check(#RM.Get(gid).raw.conditions == 3 and #RM.Get(gid).raw.conditions[2].conditions == 2, "moved out into the whole rule")
Check(f.say.text:find("Moved into the whole rule, where all of these must be true") and f.say.text:find("changes what it is combined with"), "and it says that what it is combined with changes: " .. f.say.text)
Check(Menu(cards[4]):find("Move into: Any of: "), "and the group is offered as a place to go back to, as the group where any must be true")
cards[4].more.onPick("to:1")
Flush()
Check(#RM.Get(gid).raw.conditions == 2 and #RM.Get(gid).raw.conditions[2].conditions == 3, "moved back")

-- an empty group is a place a condition can be moved into
Click(when.rootGroup.add)
for _, row in ipairs(pk.rows) do if row.shown and row.isGroup then Click(row) break end end
Click(pk.newAll)
local emptyRaw = RM.Get(gid).raw.conditions[#RM.Get(gid).raw.conditions]
local combatCard
for _, card in ipairs(when.cards) do if card.shown and card.text.text == "You are in combat" then combatCard = combatCard or card end end
Check(emptyRaw.type == "group" and #emptyRaw.conditions == 0 and Menu(combatCard):find("Move into: All of: Nothing in it yet", 1, true), "an empty group is offered as a place to move into: " .. Menu(combatCard))
for _, ch in ipairs(combatCard.more.choices()) do if ch.label:find("Nothing in it yet", 1, true) then combatCard.more.onPick(ch.value) end end
Flush()
Check(#emptyRaw.conditions == 1 and emptyRaw.conditions[1].state == "combat" and RM.Get(gid).valid, "moving into it fills it, and the rule is whole again")
for i, node in ipairs(RM.Get(gid).raw.conditions) do   -- and back: the condition returns to the top level, the extra group goes
  if node == emptyRaw then RM.MoveNode(gid, { i, 1 }, {}, 1) RM.RemoveCondition(gid, { i + 1 }) break end
end
Flush()
Check(#RM.Get(gid).raw.conditions == 2 and RM.Get(gid).raw.conditions[1].state == "combat" and RM.Get(gid).raw.conditions[2].type == "group", "(the rule is as it was)")

-- folding keeps everything, and what is open keeps its place while others move
Click(g1.fold)
Check(g1.folded.shown and g1.folded.text:find("Warrior") and g1.folded.text:find("Hunter") and not cards[3].shown and not g1.add.shown, "folded: one line saying what is in it, its cards and Add away")
Check(#RM.Get(gid).raw.conditions[2].conditions == 3, "nothing in it changed")
Click(g1.fold)
Check(not g1.folded.shown and cards[3].shown and g1.add.shown, "opened again")
Click(cards[2].edit)
local reading = ed.reads.text
RM.MoveNode(gid, { 2, 1 }, { 2 }, 3)
Flush()
Check(ed.shown and ed.reads.text == reading, "an editor stays on its own condition when another is moved: " .. ed.reads.text)
Click(ed.cancel)

-- the depth limit is explained, not just missing
Click(g1.add)
local row3
for _, row in ipairs(pk.rows) do if row.shown and row.isGroup then row3 = row end end
Click(row3)
Click(pk.newAll)
Check(RM.Get(gid).raw.conditions[2].conditions[4].type == "group" and RM.Get(gid).raw.conditions[2].conditions[4].match == "all", "a group in the group that requires all")
local g2 = when.groups[2]
Check(g2.heading.shown and g2.heading.text == "All of these must be true", "it is its own box")
Click(g2.add)
local deepGroupRow
for _, row in ipairs(pk.rows) do if row.shown and row.isGroup then deepGroupRow = row end end
Check(deepGroupRow == nil and pk.newNote.shown and pk.newNote.text:find("levels deep"), "no third level, and it says so: " .. tostring(pk.newNote.text))
Click(pk.cancel)
Check(not pk.shown, "Cancel closes the picker")
-- removing: an empty group goes without asking; a full one asks, and can be undone
S.popup = nil
g2.more.onPick("remove")
Flush()
Check(S.popup == nil and #RM.Get(gid).raw.conditions[2].conditions == 3, "an empty group is removed without asking")
Click(when.undo)
Check(#RM.Get(gid).raw.conditions[2].conditions == 4 and RM.Get(gid).raw.conditions[2].conditions[4].type == "group" and when.groups[2].heading.shown, "and Undo brings the empty group back, in its place")
g2.more.onPick("remove")
Flush()
local savedRaw = RM.Get(gid).raw.conditions[2]
S.popup = nil
g1.more.onPick("remove")
Flush()
Check(S.popup and S.popup.key == "TWICHUI_REMINDER_GROUP_DELETE" and S.popup.text:find("3 conditions") and RM.Get(gid).raw.conditions[2], "a group with conditions asks first, and says how many")
c.StaticPopupDialogs[S.popup.key].OnAccept()
Flush()
Check(#RM.Get(gid).raw.conditions == 1 and RM.Get(gid).valid and not g1.heading.shown, "removed with what was in it; the rest stays")
Check(when.undo.shown and when.undoText.text:find("Removed a group"), "and Undo is offered")
Click(when.undo)
Check(#RM.Get(gid).raw.conditions == 2 and RM.Get(gid).raw.conditions[2] == savedRaw and #savedRaw.conditions == 3, "Undo: the same group with everything in it, where it was")
-- a group that was already removed in the meantime is not removed again
S.popup = nil
when.groups[1].more.onPick("remove")
local popup = S.popup
RM.RemoveCondition(gid, { 2 })
Flush()
local before = #RM.Get(gid).raw.conditions
c.StaticPopupDialogs[popup.key].OnAccept()
Flush()
Check(#RM.Get(gid).raw.conditions == before, "confirming for a group that is already gone changes nothing")

-- a condition this version doesn't know is shown, kept, movable and removable, never edited
RM.Get(gid).raw.conditions[#RM.Get(gid).raw.conditions + 1] = { type = "futureKind", secret = { 1, 2 } }
RM.Invalidate()
Flush()
local fcard
for _, card in ipairs(when.cards) do if card.shown and card.text.text == "Unsupported condition" then fcard = card end end
Check(fcard and fcard.state.shown and fcard.note.text:find("kept as saved") and fcard.edit.enabled == false, "an unsupported condition: its own card, kept, with Edit unavailable")
Check(not Menu(fcard):find("Edit") and Menu(fcard):find("Remove") and Menu(fcard):find("Move"), "its menu has no Edit: " .. Menu(fcard))
local revF = RM.Rev()
Click(fcard)
Check(not ed.shown and RM.Rev() == revF and f.say.text:find("isn't known"), "clicking it doesn't open an editor, and says why")
fcard.more.onPick("remove")
Flush()
Click(when.undo)
Check(RM.Get(gid).raw.conditions[#RM.Get(gid).raw.conditions].type == "futureKind" and RM.Get(gid).raw.conditions[#RM.Get(gid).raw.conditions].secret[2] == 2, "removed and put back: its data is intact")
RM.RemoveCondition(gid, { #RM.Get(gid).raw.conditions })
Flush()

-- who it is for: a line, chips, and the class kept apart from the rule
Click(when.whoEdit)
Check(when.target.shown and when.whoEdit.text.text == "Close" and when.target.chips[1].shown and when.target.chips[3].shown, "Edit opens who it is for")
Check(when.who.text == "Every character" and when.target.chips[1].bar.shown and not when.target.chips[2].bar.shown, "every character is selected, in words and by the chip")
Click(when.target.chips[2])
Check(RM.Get(gid).scope.who == "characters" and #RM.Get(gid).scope.characters == 1 and when.who.text == "This character only" and when.target.chips[2].bar.shown, "This character only")
when.target.class.onPick("HUNTER")
Flush()
Check(RM.Get(gid).scope.class == "HUNTER" and when.who.text == "This character only, only for Hunters", "a class: " .. when.who.text)
Check(#RM.Get(gid).raw.conditions == 1 and RM.Get(gid).raw.conditions[1].type == "player", "the rule is as it was: no class condition was made from the class above, and none changed")
Check(when.target.note.text:find("never moved here"), "the panel says a class condition stays in the rule")
when.target.class.onPick("")
Click(when.target.chips[1])
Check(RM.Get(gid).scope.who == "all" and RM.Get(gid).scope.class == nil and when.who.text == "Every character", "back to every character")
Click(when.whoEdit)
Check(not when.target.shown, "Close puts it away")

RM.Delete(gid)
P.Select(iid)
Flush()

---------------------------------------------------------------------------
-- 5c. Why it would show, kept to what is asked for; the designer never shows a reminder; opened and closed again and again
---------------------------------------------------------------------------
P.Select(id)
Flush()
local shows0 = CT.Snapshot().shows
local inspected = 0
local realInspect = CT.Inspect
CT.Inspect = function(...) inspected = inspected + 1 return realInspect(...) end
P.Refresh()
inspected = 0
P.Refresh()
local whileClosed = inspected
Check(not when.exHead.shown and not when.exMark.shown and not when.cards[1].state.shown, "closed: no result, no marks on the cards")
Click(when.explain)
inspected = 0
P.Refresh()
Check(inspected == whileClosed + 1, "open: one look at the rule more, and only then: " .. inspected .. " against " .. whileClosed)
local status = CT.Status(id)
Check(when.exHead.shown and when.exHead.text == (status == "showing" and "Would show now" or "Would stay hidden"), "the headline follows what the reminder is doing: " .. tostring(when.exHead.text) .. " / " .. tostring(status))
Check(when.exMark.shown and when.exStatus.text == (status == "showing" and "It is showing on screen." or "It is hidden."), "and what it is doing: " .. tostring(when.exStatus.text))
Check(when.exScope.text == "This character is one it is for.", "and whether it is for this character")
Check(when.exNote.text:find("not the same as the reminder being on screen") and when.exNote.text:find("Preview appearance"), "conditions matching is kept apart from being on screen, and preview from both")
Check(when.cards[1].state.shown and (when.cards[1].note.text:find("^Met") or when.cards[1].note.text:find("^Not met")) and when.cards[1].note.text:find("Sees:"), "each card says Met or Not met, and what it sees: " .. when.cards[1].note.text)
Check(preview.title.text == "Preview appearance", "the Preview section is called Preview appearance")
-- a reminder that is turned off: the conditions can match, and nothing appears
P.Select(iid)
Flush()
Check(CT.Status(iid) == "disabled" and when.exHead.text == "Conditions match now" and when.exStatus.text:find("turned off"), "turned off: the conditions match, and it says nothing appears: " .. tostring(when.exHead.text))
Check(when.exHead.shown and when.cards[1].note.text:find("^Met"), "the card agrees")
-- closing it stops the looking
Click(when.explain)
inspected = 0
P.Refresh()
Check(inspected == whileClosed and not when.exHead.shown, "closed again: back to what it was")
Click(when.explain)
f:Hide()
inspected = 0
P.Refresh()
Check(inspected == 0, "the page hidden: nothing is looked at")
f:Show()
Flush()
CT.Inspect = realInspect
Click(when.explain)
Check(CT.Snapshot().shows == shows0 and D.PreviewId() == nil and not D.Positioning(), "none of this showed a reminder or started a preview")

-- opened and put away again and again: no new frames, nothing left open
P.Select(id)
Flush()
local function Cycle()
  Click(when.cards[1].edit)
  Click(ed.cancel)
  Click(when.rootGroup.add)
  Click(pk.cancel)
  Click(when.whoEdit)
  Click(when.whoEdit)
  Click(when.explain)
  Click(when.explain)
end
Cycle()
local madeBefore = made
for _ = 1, 6 do Cycle() end
Check(made == madeBefore, "the editor, picker, targeting and explanation opened and closed six times make nothing new: " .. (made - madeBefore))
local dsnap = R.RemindersDesigner.Snapshot()
Check(dsnap.cards == RM.MAX_CONDITIONS and dsnap.groups == RM.MAX_GROUPS + 1 and dsnap.pickerRows >= 1 and dsnap.pickerRows <= 20 and dsnap.open == 0 and dsnap.explain == 0,
  "the designer reports its pools (bounded by what a reminder can hold) and that nothing is open, for TwichUI Diagnostics")
Click(when.rootGroup.add)
Check(pk.shown, "(a picker is open)")
f:Hide()
f:Show()
Flush()
Check(not pk.shown and not ed.shown and not when.target.shown, "hidden and shown again: nothing is left open")
local snapId = Deep(RM.Get(id).raw)
for _, card in ipairs(when.cards) do
  if card.shown then Click(card.edit); Click(ed.done); Click(card.edit); Click(ed.cancel) end
end
Check(Deep(RM.Get(id).raw) == snapId, "opening and closing every card, with Done or Cancel, left the saved rule exactly as it was")

-- a full rule on three levels, as large as a reminder can be: every card fits, nothing is clipped
P.Create("custom")
Flush()
local bid = P.Selected()
for _ = 1, 4 do RM.AddCondition(bid, "player") end
RM.AddGroup(bid, nil, "any")                                  -- 5: group A
for _ = 1, 5 do RM.AddCondition(bid, "player", { 5 }) end
RM.AddGroup(bid, { 5 }, "all")                                -- A's sixth: group B
for _ = 1, 4 do RM.AddCondition(bid, "class", { 5, 6 }) end
RM.AddGroup(bid, nil, "all")                                  -- 6: group C
for _ = 1, 3 do RM.AddCondition(bid, "equipment", { 6 }) end
Flush()
local bv = RM.Get(bid)
Check(bv.counts.conditions == 16 and bv.counts.groups == 3, "the rule is as large as it can be: " .. bv.counts.conditions .. " conditions, " .. bv.counts.groups .. " groups")
local widest, shownCards = 0, 0
for _, card in ipairs(when.cards) do
  if card.shown then
    shownCards = shownCards + 1
    widest = math.max(widest, X(card) + card.w)
  end
end
Check(shownCards == 16, "every condition has a card: " .. shownCards)
Check(widest <= 644 - 14, "none passes the right edge, three levels down: " .. widest)
Check(when.rootGroup.add.enabled == false and when.rootGroup.empty.text == RM.REFUSE.conditionsFull, "at the limit, Add a condition is unavailable, and says why: " .. tostring(when.rootGroup.empty.text))
local deepest = when.groups[2]
Check(deepest.heading.shown and deepest.add.shown and (deepest.box.w or 0) > 300, "the inner group keeps a readable width: " .. tostring(deepest.box.w))
Check(P.Height() > 800 and P.Height() < 6000, "the page grows to hold it: " .. P.Height())
local before16 = Deep(RM.Get(bid).raw)
Click(when.groups[1].fold)
local function CardsShown() local n = 0 for _, card in ipairs(when.cards) do if card.shown then n = n + 1 end end return n end
Check(when.groups[1].folded.shown and CardsShown() == 7, "a group folds with everything inside it (its nine conditions' cards go, seven stay): " .. CardsShown())
Check(Deep(RM.Get(bid).raw) == before16, "folding changed nothing")
Click(when.groups[1].fold)
Check(CardsShown() == 16, "and opens again")
RM.Delete(bid)
P.Select(iid)
Flush()

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
P.Select(id)
Flush()
preview.show.scripts.OnClick(preview.show)
Flush()
Check(D.PreviewId() == id and preview.show.text.text == "Hide preview" and preview.state.text:find("On screen"), "on-screen preview")
Check(CT.Status(id) == "hidden", "the preview leaves the live decision as it was (a shield is on)")
preview.show.scripts.OnClick(preview.show)
Flush()
Check(D.PreviewId() == nil and preview.show.text.text == "Show on screen", "preview hidden again")
place.move.scripts.OnClick(place.move)
Flush()
Check(D.Positioning() and place.move.text.text == "Done", "moving")
place.move.scripts.OnClick(place.move)
Flush()
Check(not D.Positioning(), "done moving")
D.PreviewStop()
Check(preview.surface.art.texture and preview.surface.art.texture:find("shield"), "the inline preview draws with the reminder's own layout")

---------------------------------------------------------------------------
-- 8. More options, height, nothing made twice
---------------------------------------------------------------------------
Check(not place.width.shown and not place.strata.shown, "more options are closed at first")
local h1 = P.Height()
place.more.scripts.OnClick(place.more)
Flush()
Check(place.strata.shown and place.fade.shown and place.delay.shown and place.x.shown, "opened: the rest is there")
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
local count = made
for _ = 1, 5 do P.Refresh(); Flush() end
Check(made == count, "redrawing makes nothing new: " .. (made - count))

---------------------------------------------------------------------------
-- 9. Off, hidden, profiles
---------------------------------------------------------------------------
R:SetEnabled("reminders", false)
Flush()
P.Refresh()
Check(test.liveResult.text:find("^Result: Off"), "with Reminders off the result says so: " .. test.liveResult.text)
R:SetEnabled("reminders", true)
Flush()
f:Hide()
Check(next(f.events) == nil, "hidden: it hears nothing")
f:Show()
Flush()
Check(R.Profiles.Create("Empty"), "a new profile")
Flush()
Check(P.Selected() == nil and f.empty.shown and not f.head.shown, "another profile's (empty) list; nothing stale is open")

if failures == 0 then print("PASSED") else print(failures .. " FAILED") end
