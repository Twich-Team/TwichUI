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
Check(#f.templates == 3 and f.templates[1].shown, "three ways to start")
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
local cr = when.rows[1]
Check(cr.subject.text.text == "Off hand" and cr.op.text.text == "is not" and cr.value.text.text == "Shield", "When reads [Off hand] [is not] [Shield]")
Check(not cr.item.shown and not when.match.shown and when.single.shown, "one condition: \"Show when\", no all/any choice, no item box")
Check(when.sentence.text == "Shows when: Off hand is not Shield." and when.scope.text:find("This character only"), "the summary and the scope")
Check(when.note.shown and when.note.text == RM.SHIELD_NOTE, "the template's explanation")
local valueChoices = cr.value.choices()
local labels = {}
for _, ch in ipairs(valueChoices) do labels[#labels + 1] = ch.label end
Check(table.concat(labels, ",") == "Empty,Shield,Weapon,Held in off hand,A specific item", "the off hand's own choices only: " .. table.concat(labels, ","))

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
when.addEquip.scripts.OnClick(when.addEquip)
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
-- 4. Editing the rule: field-specific choices, a second condition, all or any
---------------------------------------------------------------------------
cr.subject.onPick("slot:mainHand")
Flush()
local c1 = RM.Get(id).conditions[1].cond
Check(c1.slot == "mainHand" and c1.what == "empty" and c1.negate == true, "another slot keeps \"is not\" and takes a value it can have")
Check(when.rows[1].value.text.text == "Empty", "its value")
cr.subject.onPick("slot:offHand")
cr.value.onPick("shield")
Flush()
when.addPlayer.scripts.OnClick(when.addPlayer)
Flush()
Check(#RM.Get(id).conditions == 2 and when.match.shown and when.match.text.text == "All conditions match", "two conditions: all or any")
Check(when.rows[2].subject.text.text == "You (the player)" and when.rows[2].value.text.text == "In combat", "the player's condition")
when.match.onPick("any")
Flush()
Check(RM.Get(id).match == "any" and when.sentence.text:find("any of these"), "any: " .. when.sentence.text)
when.rows[2].op.onPick("isnot")
Flush()
Check(RM.Get(id).conditions[2].cond.negate == true and when.rows[2].op.text.text == "is not", "is not")
when.rows[2].remove.scripts.OnClick(when.rows[2].remove)
Flush()
Check(#RM.Get(id).conditions == 1 and not when.rows[2].subject.shown, "removed")

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
local ir = when.rows[1]
Check(ir.subject.text.text == "Any equipment slot" and ir.item.shown, "any slot, with an item box")
local anyLabels = {}
for _, ch in ipairs(ir.value.choices()) do anyLabels[#anyLabels + 1] = ch.label end
Check(table.concat(anyLabels, ",") == "A specific item", "any slot offers only a specific item")
ir.item:SetText("|cffffffff|Hitem:6948::::::::60:::::|h[Hearthstone]|h|r")
ir.item.scripts.OnEnterPressed(ir.item)
Flush()
local iv = RM.Get(iid)
Check(iv.conditions[1].cond.item == 6948 and iv.display.item == 6948 and iv.valid, "the link's item, and the icon uses it")
Check(ir.itemName.shown and ir.itemName.text:find("Hearthstone"), "the item is named: " .. ir.itemName.text)
Check(when.sentence.text == "Shows when: Hearthstone is not equipped.", "its sentence: " .. when.sentence.text)
ir.item:SetText("not an item")
ir.item.scripts.OnEnterPressed(ir.item)
Flush()
Check(RM.Get(iid).conditions[1].cond.item == 6948 and f.say.text:find("isn't an item ID"), "a bad item is refused, nothing changes")
Check(show.src.shown and show.src.text.text == "An item's icon" and show.itemInfo.text:find("Hearthstone"), "Show: an item's icon, named")

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
