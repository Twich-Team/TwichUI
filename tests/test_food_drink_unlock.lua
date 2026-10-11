-- Food and Drink in EllesmereUI's Unlock Mode: registered once, only when chosen and only when
-- EllesmereUI has what it needs; the anchor's size is the buttons' footprint; the buttons follow the
-- anchor and never move in combat; the one saved place; a discarded session goes back; nothing
-- changes the secure actions; and everything is a no-op without EllesmereUI.
-- EllesmereUI is a stand-in that follows the documented contract (EllesmereUI.lua MakeUnlockElement,
-- EUI_UnlockMode.lua registration and listeners, EUI_UnlockMode_Session.lua save and revert). What the real
-- mover does in the game still has to be checked there.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})

---------------------------------------------------------------------------
-- Frames with real geometry: anchor points, offsets in the frame's own scale, centres in it too.
---------------------------------------------------------------------------
local W, H, UI_SCALE = 1024, 768, 0.64   -- the screen in its own units, and its effective scale
local ANCH = { CENTER = {0, 0}, TOPLEFT = {-1, 1}, TOP = {0, 1}, TOPRIGHT = {1, 1}, LEFT = {-1, 0}, RIGHT = {1, 0},
  BOTTOMLEFT = {-1, -1}, BOTTOM = {0, -1}, BOTTOMRIGHT = {1, -1} }
local frames = {}
local UIP

local function Centre(f)   -- the frame's centre, in the screen's units
  if f == UIP then return W / 2, H / 2 end
  local p = f.pt
  if not p then return nil end
  local s = f.scale or 1
  local ra, a = ANCH[p.rel], ANCH[p.point]
  local px, py = W / 2 + ra[1] * W / 2 + p.x * s, H / 2 + ra[2] * H / 2 + p.y * s
  return px - a[1] * (f.w or 0) * s / 2, py - a[2] * (f.h or 0) * s / 2
end

local function Frame(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.attrs, o.setPoints = true, {}, {}, {}, 0
  table.insert(frames, o)
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "SetAttribute" then return function(s, n, v) s.attrs[n] = v end end
    if k == "GetAttribute" then return function(s, n) return s.attrs[n] end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "SetSize" then return function(s, w, h) s.w, s.h = w, h; s.sizes = (s.sizes or 0) + 1 end end
    if k == "GetSize" then return function(s) return s.w or 0, s.h or 0 end end
    if k == "ClearAllPoints" then return function(s) s.pt = nil end end
    if k == "SetPoint" then return function(s, point, rel, relPoint, x, y)
      -- only placements against the screen have geometry here (the buttons are laid out inside their parent)
      s.pt = rel == UIP and { point = point, rel = relPoint or point, x = x or 0, y = y or 0 } or nil
      s.setPoints = s.setPoints + 1
    end end
    if k == "GetCenter" then return function(s)
      local cx, cy = Centre(s)
      if not cx then return nil end
      local sc = s == UIP and 1 or (s.scale or 1)
      return cx / sc, cy / sc
    end end
    if k == "GetEffectiveScale" then return function(s) return s == UIP and UI_SCALE or UI_SCALE * (s.scale or 1) end end
    if k == "SetMovable" or k == "SetFrameStrata" or k == "SetFrameLevel" or k == "SetClampedToScreen" then return function() end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Frame() end end
    if type(k) == "string" and k:find("^%u") then return function() end end   -- any other method: does nothing
    return nil                                                                -- fields of ours that are not set
  end})
end
c.CreateFrame = function(kind, _, parent, template) return Frame({ kind = kind, parent = parent, template = template }) end
UIP = Frame()
c.UIParent = UIP
-- hooksecurefunc as the game has it: the original runs, then the hook, on that object.
c.hooksecurefunc = function(obj, name, fn)
  local orig = obj[name]
  rawset(obj, name, function(...) local r = orig(...); fn(...); return r end)
end
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }
c.GameTooltip = Frame()
c.LEVEL, c.COMBAT = 30, false
c.UnitLevel = function() return c.LEVEL end
c.InCombatLockdown = function() return c.COMBAT end
c.HEALTH, c.MANA, c.NUM_BAG_SLOTS = "Health", "Mana", 4
c.BAGS = { [0] = { 2287, 1179 } }
c.ITEMS = {
  [2287] = { class = 0, sub = 5, name = "Haunch of Meat", minLevel = 5, count = 10, icon = 1, spell = 12287, spellName = "Food",
    text = "Restores 234 health over 21 sec.  Must remain seated while eating." },
  [1179] = { class = 0, sub = 5, name = "Ice Cold Milk", minLevel = 5, count = 15, icon = 2, spell = 11179, spellName = "Drink",
    text = "Restores 420 mana over 21 sec.  Must remain seated while drinking." },
}
c.C_Container = {
  GetContainerNumSlots = function(bag) return c.BAGS[bag] and 20 or 0 end,
  GetContainerItemInfo = function(bag, slot) local id = c.BAGS[bag] and c.BAGS[bag][slot]; return id and { itemID = id } end,
}
c.C_Item = {
  GetItemInfoInstant = function(id) local i = c.ITEMS[id]; if not i then return end return id, "", "", "", i.icon, i.class, i.sub end,
  GetItemInfo = function(id) local i = c.ITEMS[id]; if not i then return end return i.name, "link", 1, 1, i.minLevel end,
  GetItemSpell = function(id) local i = c.ITEMS[id]; if i and i.spell then return i.spellName, i.spell end end,
  GetItemCount = function(id) return c.ITEMS[id].count end,
  RequestLoadItemDataByID = function() end,
}
c.C_Spell = {
  GetSpellName = function(id) return ({ [434] = "Food", [431] = "Drink" })[id] end,
  GetSpellDescription = function(id) for _, i in pairs(c.ITEMS) do if i.spell == id then return i.text end end end,
  RequestLoadSpellData = function() end,
}

---------------------------------------------------------------------------
-- EllesmereUI, as documented.
---------------------------------------------------------------------------
local EUI
local function MakeEUI(opts)
  opts = opts or {}
  local e = { elements = {}, registerCalls = 0, unregisterCalls = 0, listeners = {}, reapplied = {}, session = false }
  function e:RegisterUnlockElements(list, folder)
    e.registerCalls = e.registerCalls + 1
    for _, el in ipairs(list) do e.elements[el.key] = el end
  end
  function e:UnregisterUnlockElement() e.unregisterCalls = e.unregisterCalls + 1 end
  if not opts.noMake then
    -- the documented whitelist: a field left out never reaches Unlock Mode
    function e.MakeUnlockElement(o)
      return { key = o.key, label = o.label, group = o.group, order = o.order, getFrame = o.getFrame, getSize = o.getSize,
        savePosition = o.savePos, loadPosition = o.loadPos, clearPosition = o.clearPos, applyPosition = o.applyPos,
        setWidth = o.setWidth, setHeight = o.setHeight, isHidden = o.isHidden, isAnchored = o.isAnchored, noResize = o.noResize }
    end
  end
  function e:RegisterUnlockModeListener(owner, fn)
    e.listeners[owner] = fn
    if e.session then fn(true) end
  end
  function e:IsUnlockModeActive() return e.session end
  function e.ReapplyOwnAnchor(key) table.insert(e.reapplied, key) end
  return e
end
local function SnapHalf(v) return math.floor(v * 2 + 0.5) / 2 end   -- stand-in for EllesmereUI's pixel snap: idempotent

-- What its mover does with a registered element, step for step as read in its source.
local KEY = "TwichUI_FoodDrink"
local function El() return EUI.elements[KEY] end
local function Anchor() return El().getFrame(KEY) end
local function Open() EUI.session = true; for _, fn in pairs(EUI.listeners) do fn(true) end end
local function Close(action) EUI.session = false; for _, fn in pairs(EUI.listeners) do fn(false, action or "exit") end end
-- a drag: the live frame is set by its TOPLEFT (EUI_UnlockMode_Movers.lua)
local function Drag(ox, oy)
  local f = Anchor()
  local w, h = f:GetSize()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIP, "TOPLEFT", W / 2 + ox - w / 2, oy - H / 2 + h / 2)
end
-- Save & Exit: CENTER/CENTER from the live rect in screen units (Positions.lua ConvertToCenterPos / SaveBarPosition)
local function Commit()
  local f = Anchor()
  local cx, cy = f:GetCenter()
  local ratio = f:GetEffectiveScale() / UIP:GetEffectiveScale()
  El().savePosition(KEY, "CENTER", "CENTER", cx * ratio - W / 2, cy * ratio - H / 2, "TOPLEFT", "TOPLEFT")
end
-- ApplyCenterPosition: the centralized apply, snapped
local function ApplyPos(pos)
  local f = Anchor()
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIP, "CENTER", SnapHalf(pos.x), SnapHalf(pos.y))
end
-- RevertPositions: the snapshot taken at open, saved back and applied
local function Revert(snap)
  El().savePosition(KEY, snap.point, snap.relPoint, snap.x, snap.y)
  ApplyPos(snap)
end

for _, f in ipairs({"chronicle/Style.lua", "modules/Borders.lua", "modules/FoodDrink.lua", "modules/FoodDrinkUnlock.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { foodDrink = true }, ui = { foodDrinkPosition = { x = 100, y = -50 }, trainingPosition = { x = 7, y = 8 } } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local F, U = R.FoodDrink, R.FoodDrink.Unlock
local M = c.TwichUIDB.modules
local function Look() FlushTimers() end
assert(U, "the integration is loaded")
assert(R.DEFAULT_MODULES.foodDrinkUnlock == false and M.foodDrinkUnlock == false, "off by default")

c.FireEvent("PLAYER_ENTERING_WORLD", true, false); Look()
local food, drink, container
for _, f in ipairs(frames) do
  if f.template == "SecureActionButtonTemplate" then
    if f.label == "Food" then food = f elseif f.label == "Drink" then drink = f end
  end
end
container = food.parent
assert(food.attrs.item == "Haunch of Meat" and drink.attrs.item == "Ice Cold Milk", "buttons are filled")
local function ContainerAt() local cx, cy = container:GetCenter(); return cx - W / 2, cy - H / 2 end
local function Same(a, b) return math.abs(a - b) < 1e-9 end
local x0, y0 = ContainerAt()
assert(Same(x0, 100) and Same(y0, -50), "buttons sit at the saved place")
local function Secure() return food.attrs.type, food.attrs.item, drink.attrs.type, drink.attrs.item end
local t1, i1, t2, i2 = Secure()

-- Option off: EllesmereUI present, nothing registered, nothing hooked, Edit Mode as before.
do
  c.EllesmereUI = MakeEUI(); EUI = c.EllesmereUI
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "EllesmereUI"); F.Refresh()
  assert(EUI.registerCalls == 0 and next(EUI.listeners) == nil, "not registered while off")
  assert(U.Status() == "off" and not U.Drives())
  assert(U.Offset() == nil, "the saved place is used")
  c.EDITING = true; c.EventRegistry.callbacks["EditMode.Enter"]()
  local outline
  for _, f in ipairs(frames) do if f.scripts.OnDragStop then outline = f end end
  assert(outline and outline.shown, "Edit Mode's outline is the mover")
  c.EDITING = false; c.EventRegistry.callbacks["EditMode.Exit"]()
  assert(not outline.shown)
end

-- Turning it on: registered once, with a clear label, and the buttons do not move.
local anchor
do
  M.foodDrinkUnlock = true; F.Refresh()
  assert(EUI.registerCalls == 1 and El(), "registered")
  assert(El().label == "TwichUI Food & Drink" and El().group == "TwichUI", "clearly labelled")
  assert(El().noResize == true and El().setWidth == nil and El().setHeight == nil, "no size controls are claimed")
  assert(El().isHidden() == false, "shown in Unlock Mode")
  anchor = Anchor()
  assert(anchor and anchor ~= container, "a frame of its own, not the secure buttons' parent")
  local ax, ay = anchor:GetCenter()
  assert(Same(ax - W / 2, 100) and Same(ay - H / 2, -50), "the anchor starts at the saved place")
  local x, y = ContainerAt()
  assert(Same(x, x0) and Same(y, y0), "turning it on moves nothing")
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == 100 and c.TwichUIDB.ui.foodDrinkPosition.y == -50, "the record is as it was")
  assert(U.Status() == "active" and U.Drives())
  assert(EUI.reapplied[1] == KEY, "an existing anchor link is applied once registered")
  -- registered once however often it is asked
  for _ = 1, 4 do F.Refresh(); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("ADDON_LOADED", "EllesmereUI"); c.FireEvent("PLAYER_ENTERING_WORLD", false, false) end
  Look()
  assert(EUI.registerCalls == 1, "never registered twice: " .. EUI.registerCalls)
  assert(EUI.unregisterCalls == 0, "never unregistered (that would delete the player's anchor links)")
  assert(select(1, Secure()) == t1 and select(2, Secure()) == i1 and select(3, Secure()) == t2 and select(4, Secure()) == i2, "secure actions untouched")
end

-- Footprint: the anchor is the buttons' footprint, for both layouts, one or both buttons, any contents.
do
  local function Anchor2() local w, h = anchor:GetSize(); return w, h end
  local w, h = Anchor2(); assert(w == 36 * 2 + 4 and h == 36, "two buttons side by side: " .. w .. "x" .. h)
  assert(F.FootprintFor(2, 36, 4, false) == 76 and select(2, F.FootprintFor(2, 36, 4, true)) == 76, "pure: both buttons")
  local cw, ch = container:GetSize(); assert(cw == w and ch == h, "same as the buttons' parent")
  F.Set("layout", "vertical"); Look(); w, h = Anchor2()
  assert(w == 36 and h == 76, "stacked: " .. w .. "x" .. h)
  M.foodDrinkDrink = false; F.Refresh(); Look(); w, h = Anchor2()
  assert(w == 36 and h == 36 and El().isHidden() == false, "one button")
  F.Set("layout", "horizontal"); F.Set("size", 50); F.Set("spacing", 10); M.foodDrinkDrink = true; F.Refresh(); Look(); w, h = Anchor2()
  assert(w == 110 and h == 50, "bigger buttons, wider gap: " .. w .. "x" .. h)
  assert(select(1, El().getSize(KEY)) == 110 and select(2, El().getSize(KEY)) == 50, "getSize says the same")
  -- from the settings alone: empty bags change nothing
  c.BAGS = { [0] = {} }; c.FireEvent("BAG_UPDATE_DELAYED"); Look(); w, h = Anchor2()
  assert(w == 110 and h == 50 and El().isHidden() == false, "an empty bag still has a place to position")
  assert(food.attrs.type == nil, "...and no item was conjured for it")
  c.BAGS = { [0] = { 2287, 1179 } }; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
  F.Set("size", 36); F.Set("spacing", 4); Look()
  -- both off: nothing to position
  M.foodDrinkFood, M.foodDrinkDrink = false, false; F.Refresh(); Look()
  assert(El().isHidden() == true and U.Status() == "module-off", "no buttons, no anchor in Unlock Mode")
  M.foodDrinkFood, M.foodDrinkDrink = true, true; F.Refresh(); Look()
  assert(El().isHidden() == false)
end

-- Dragging and saving: the buttons follow the anchor; Save & Exit writes the one record.
do
  Open()
  Drag(220, 140)
  local x, y = ContainerAt()
  assert(Same(x, 220) and Same(y, 140), "the buttons follow the anchor as it is dragged: " .. x .. "," .. y)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == 100, "nothing is saved until Save & Exit")
  Commit(); Close("save")
  local saved = c.TwichUIDB.ui.foodDrinkPosition
  assert(Same(saved.x, 220) and Same(saved.y, 140), "saved as the centre's offset: " .. saved.x .. "," .. saved.y)
  x, y = ContainerAt(); assert(Same(x, 220) and Same(y, 140))
  assert(F.Position() == 220 and select(2, F.Position()) == 140, "Edit Mode's reader sees the same record")
  assert(El().loadPosition(KEY).x == 220 and El().loadPosition(KEY).point == "CENTER", "and so does EllesmereUI")
  assert(not EUI.session)
  local t, i = food.attrs.type, food.attrs.item
  assert(t == t1 and i == i1, "secure action unchanged")
end

-- A discarded session goes back; the record is not touched.
do
  Open()
  local snap = El().loadPosition(KEY); snap = { point = snap.point, relPoint = snap.relPoint, x = snap.x, y = snap.y }
  Drag(-300, 90)
  local x = ContainerAt(); assert(Same(x, -300))
  Revert(snap); Close("discard")
  local cx, cy = ContainerAt()
  assert(Same(cx, 220) and Same(cy, 140), "back where it was: " .. cx .. "," .. cy)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == 220, "record unchanged")
end

-- Repeated sessions do not drift: open, apply the snapped place, save without moving, many times.
do
  c.TwichUIDB.ui.foodDrinkPosition = { x = 101.37, y = -52.61 }
  for _ = 1, 6 do
    El().applyPosition(KEY); ApplyPos(El().loadPosition(KEY))   -- login, or a profile apply
    Open(); Commit(); Close("save")
  end
  local p = c.TwichUIDB.ui.foodDrinkPosition
  assert(p.x == SnapHalf(101.37) and p.y == SnapHalf(-52.61), "settles on the snapped place once: " .. p.x .. "," .. p.y)
  local x, y = ContainerAt(); assert(Same(x, p.x) and Same(y, p.y))
  Open(); Commit(); Close("save")
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == p.x and c.TwichUIDB.ui.foodDrinkPosition.y == p.y, "no further movement")
  c.TwichUIDB.ui.foodDrinkPosition = { x = 220, y = 140 }
  El().applyPosition(KEY)
end

-- Coordinates: a differently scaled frame, and values that cannot be a place.
do
  local sx, sy = U.OffsetFrom(300, 200, 0.5 * UI_SCALE, 512, 384, UI_SCALE)   -- own scale half the screen's: centre is 150, 100 in screen units
  assert(Same(sx, 150 - 512) and Same(sy, 100 - 384), "scale compensated once")
  local ax, ay = U.OffsetFrom(512 + 40, 384 - 25, UI_SCALE, 512, 384, UI_SCALE)
  assert(Same(ax, 40) and Same(ay, -25), "unscaled")
  assert(U.OffsetFrom(nil, 1, 1, 1, 1, 1) == nil and U.OffsetFrom(1, 1, 0, 1, 1, 1) == nil and U.OffsetFrom(1e9, 1, 1, 0, 0, 1) == nil, "unusable gives nothing")
  -- an anchor with a scale of its own: offsets are in its units, the buttons sit where it really is
  anchor.scale = 0.8
  anchor:ClearAllPoints(); anchor:SetPoint("CENTER", UIP, "CENTER", 100, -50)
  local x, y = U.Offset()
  assert(Same(x, 80) and Same(y, -40), "converted once: " .. tostring(x) .. "," .. tostring(y))
  local cx, cy = ContainerAt()
  assert(Same(cx, 80) and Same(cy, -40), "the buttons are where the anchor really is")
  anchor.scale = nil
  anchor:ClearAllPoints(); anchor:SetPoint("CENTER", UIP, "CENTER", 220, 140)
  assert(Same(ContainerAt(), 220))
end

-- Combat: nothing of the buttons is moved; only the latest place is applied when it ends.
do
  Open()
  local base = container.setPoints
  c.COMBAT = true
  Drag(10, 10); Drag(30, 30); Drag(-60, 75)
  assert(container.setPoints == base, "the buttons' parent is never moved in combat")
  local x = ContainerAt(); assert(Same(x, 220), "still where it was")
  assert(F.Snapshot().moveWaiting == true, "the wait is known")
  assert(R.Life.Snapshot().notes["unlock-deferred-combat"] >= 1, "counted under a stable code")
  local t, i = food.attrs.type, food.attrs.item
  assert(t == t1 and i == i1, "no secure change in combat")
  c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  local cx, cy = ContainerAt()
  assert(Same(cx, -60) and Same(cy, 75), "goes to where the anchor is when combat ends, not to a stale place: " .. cx .. "," .. cy)
  assert(F.Snapshot().moveWaiting == false)
  Revert({ point = "CENTER", relPoint = "CENTER", x = 220, y = 140 }); Close("discard")
  local rx = ContainerAt(); assert(Same(rx, 220))
end

-- A move waiting for combat is cancelled by the choice being turned off or the buttons disabled.
do
  Open(); c.COMBAT = true; Drag(400, 200)
  M.foodDrinkUnlock = false; F.Refresh()
  c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  local x, y = ContainerAt()
  assert(Same(x, 220) and Same(y, 140), "choice off: the saved place, not the anchor's: " .. x .. "," .. y)
  assert(not U.Drives() and U.Offset() == nil)
  assert(EUI.registerCalls == 1 and EUI.unregisterCalls == 0, "hidden, not unregistered")
  assert(El().isHidden() == true, "hidden from Unlock Mode")
  Close("discard")
  M.foodDrinkUnlock = true; F.Refresh(); Look()
  local ax, ay = Anchor():GetCenter()
  assert(Same(ax - W / 2, 220) and Same(ay - H / 2, 140), "turned on again: the anchor goes to the saved place first")
  assert(EUI.registerCalls == 1, "and is not registered again")
  -- the buttons turned off with a move waiting
  Open(); c.COMBAT = true; Drag(-100, -100)
  M.foodDrink = false; F.Refresh()
  assert(F.Snapshot().moveWaiting == false, "cancelled by the buttons being turned off")
  assert(El().isHidden() == true and U.Status() == "module-off")
  c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  M.foodDrink = true; F.Refresh(); Look(); Close("discard")
  ApplyPos({ x = 220, y = 140 })
  local cx, cy = ContainerAt(); assert(Same(cx, 220) and Same(cy, 140))
end

-- A layout from EllesmereUI (a profile or spec switch) goes through the same record; it is ignored
-- while the choice is off or the buttons are, and an unusable place is refused.
do
  El().savePosition(KEY, "CENTER", "CENTER", -150, 60)
  El().applyPosition(KEY)
  local x, y = ContainerAt()
  assert(Same(x, -150) and Same(y, 60) and c.TwichUIDB.ui.foodDrinkPosition.x == -150, "a profile's place is applied")
  El().savePosition(KEY, "TOPLEFT", "TOPLEFT", 5, 5)
  El().savePosition(KEY, "CENTER", "CENTER", 1e9, 0)
  El().savePosition(KEY, "CENTER", "CENTER", 0 / 0, 0)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == -150 and R.Life.Snapshot().notes["unlock-save-refused"] == 3, "other shapes and junk are refused and counted")
  -- not during a session: applying the saved place would undo what has been dragged
  Open(); Drag(33, 44)
  El().applyPosition(KEY)
  local ax, ay = Anchor():GetCenter()
  assert(Same(ax - W / 2, 33) and Same(ay - H / 2, 44), "a session's own moves are not overwritten")
  Revert({ point = "CENTER", relPoint = "CENTER", x = -150, y = 60 }); Close("discard")
  M.foodDrinkUnlock = false; F.Refresh()
  El().savePosition(KEY, "CENTER", "CENTER", 9, 9)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == -150 and R.Life.Snapshot().notes["unlock-save-ignored"] == 1, "ignored while off")
  M.foodDrinkUnlock = true; M.foodDrink = false; F.Refresh()
  El().savePosition(KEY, "CENTER", "CENTER", 9, 9)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == -150 and R.Life.Snapshot().notes["unlock-save-ignored"] == 2, "ignored while the buttons are off")
  M.foodDrink = true; F.Refresh(); Look()
  -- the same place saved again writes nothing, so an unset place stays unset
  c.TwichUIDB.ui.foodDrinkPosition = nil
  F.Refresh(); Look()
  El().savePosition(KEY, "CENTER", "CENTER", 0, -220)
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil, "the default is not written as if it were chosen")
  local lp = El().loadPosition(KEY)
  assert(lp.x == 0 and lp.y == -220 and lp.point == "CENTER", "but EllesmereUI is always given a place to go back to")
end

-- Reset: this record only. The anchor goes back too; nothing else of ours or of EllesmereUI's is touched.
do
  El().savePosition(KEY, "CENTER", "CENTER", 77, 88)
  assert(c.TwichUIDB.ui.foodDrinkPosition.x == 77)
  F.ResetPosition()
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil, "the record is cleared")
  local ax, ay = Anchor():GetCenter()
  assert(Same(ax - W / 2, 0) and Same(ay - H / 2, -220), "the anchor is at the default")
  local x, y = ContainerAt(); assert(Same(x, 0) and Same(y, -220), "and so are the buttons")
  assert(c.TwichUIDB.ui.trainingPosition.x == 7 and c.TwichUIDB.ui.trainingPosition.y == 8, "another feature's place is untouched")
  assert(EUI.unregisterCalls == 0, "no anchor links were removed")
  El().savePosition(KEY, "CENTER", "CENTER", 12, 34)
  El().clearPosition(KEY)    -- EllesmereUI's own clear does the same
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil and Same(select(2, ContainerAt()), -220))
  -- in combat: the record is cleared, the buttons wait
  El().savePosition(KEY, "CENTER", "CENTER", 12, 34)
  c.COMBAT = true; F.ResetPosition()
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil and Same(select(2, ContainerAt()), 34), "the buttons wait for combat to end")
  c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  assert(Same(select(2, ContainerAt()), -220), "and go back then")
end

-- One mover: Edit Mode's outline stays away while EllesmereUI's anchor is in charge, and comes back
-- when it is not.
do
  c.EDITING = true; c.EventRegistry.callbacks["EditMode.Enter"]()
  local outline
  for _, f in ipairs(frames) do if f.scripts.OnDragStop then outline = f end end
  assert(not outline or not outline.shown, "no second mover while the anchor is in charge")
  M.foodDrinkUnlock = false; F.Refresh()
  outline = nil
  for _, f in ipairs(frames) do if f.scripts.OnDragStop then outline = f end end
  assert(outline and outline.shown, "Edit Mode's outline returns when the choice is off")
  M.foodDrinkUnlock = true; F.Refresh()
  assert(not outline.shown, "and goes when it is on again")
  c.EDITING = false; c.EventRegistry.callbacks["EditMode.Exit"]()
end

-- Diagnostics: codes and flags only.
do
  local s = U.Snapshot()
  assert(s.status == "active" and s.wanted and s.registered and s.drives and s.owner == "EllesmereUI anchor" and s.api == "present", "active")
  Open(); assert(U.Snapshot().session == true); Close("exit"); assert(U.Snapshot().session == false)
  for k, v in pairs(s) do assert(type(v) ~= "table", "no tables from EllesmereUI are copied: " .. k) end
end

---------------------------------------------------------------------------
-- Without EllesmereUI.
---------------------------------------------------------------------------
-- A client where it is missing, then appears late; and one where its Unlock Mode lacks what is used.
local function Fresh(setup)
  local d = MakeClient("Pat", {"!!!TwichUI"})
  for k, v in pairs({ CreateFrame = c.CreateFrame, hooksecurefunc = c.hooksecurefunc, EventRegistry = c.EventRegistry,
    EditModeManagerFrame = c.EditModeManagerFrame, GameTooltip = c.GameTooltip, UnitLevel = c.UnitLevel, HEALTH = "Health", MANA = "Mana",
    NUM_BAG_SLOTS = 4, C_Container = c.C_Container, C_Item = c.C_Item, C_Spell = c.C_Spell }) do d[k] = v end
  d.UIParent = UIP
  d.InCombatLockdown = function() return false end
  for _, f in ipairs({"chronicle/Style.lua", "modules/Borders.lua", "modules/FoodDrink.lua", "modules/FoodDrinkUnlock.lua"}) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, d); chunk("!!!TwichUI", {})
  end
  d.TwichUIDB = { modules = { foodDrink = true, foodDrinkUnlock = true }, ui = { foodDrinkPosition = { x = 40, y = 41 } } }
  if setup then setup(d) end
  d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
  return d
end

do
  local d = Fresh()
  local FD = d.TwichUI.FoodDrink
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  assert(FD.Unlock.Status() == "no-eui" and not FD.Unlock.Drives(), "reported neutrally, not as an error")
  assert(d.TwichUIDB.modules.foodDrinkUnlock == true, "the choice is kept while EllesmereUI is away")
  local x, y = FD.Placement(); assert(x == 40 and y == 41, "standalone: the saved place")
  assert(FD.Snapshot().built, "the buttons work")
  -- it arrives late
  local late = MakeEUI()
  d.EllesmereUI = late
  d.FireEvent("ADDON_LOADED", "EllesmereUI")
  assert(late.registerCalls == 1 and FD.Unlock.Status() == "active", "registered when it appears")
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", false, false)
  assert(late.registerCalls == 1, "once")
  local anchorFrame = late.elements[KEY].getFrame(KEY)
  local ax, ay = anchorFrame:GetCenter()
  assert(Same(ax - W / 2, 40) and Same(ay - H / 2, 41), "at the saved place")
end

do
  local d = Fresh(function(env) env.EllesmereUI = MakeEUI({ noMake = true }) end)
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  local FD = d.TwichUI.FoodDrink
  assert(FD.Unlock.Status() == "no-api" and d.EllesmereUI.registerCalls == 0, "no mover API: nothing registered")
  d.EDITING = true
  assert(not FD.Unlock.Drives(), "Edit Mode keeps the buttons")
end

-- A registration that errors: noted, the buttons carry on at the saved place, and it is not retried each time.
do
  local bad = MakeEUI(); bad.RegisterUnlockElements = function() error("boom") end
  local d = Fresh(function(env) env.EllesmereUI = bad end)
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  local FD = d.TwichUI.FoodDrink
  assert(FD.Unlock.Status() == "register-failed" and not FD.Unlock.Drives())
  assert(d.TwichUI.Life.Snapshot().notes["unlock-register-failed"] == 1)
  for _ = 1, 3 do FD.Refresh() end
  assert(d.TwichUI.Life.Snapshot().notes["unlock-register-failed"] == 1, "not retried")
  local x, y = FD.Placement(); assert(x == 40 and y == 41)
end

-- An old saved choice that is not a boolean never turns it on.
do
  local d = Fresh(function(env) env.EllesmereUI = MakeEUI(); env.TwichUIDB.modules.foodDrinkUnlock = nil end)
  d.TwichUIDB.modules.foodDrinkUnlock = "yes"
  d.FireEvent("PLAYER_LOGIN"); d.FireEvent("PLAYER_ENTERING_WORLD", true, false); FlushTimers()
  assert(d.EllesmereUI.registerCalls == 0 and d.TwichUI.FoodDrink.Unlock.Status() == "off", "only an explicit true turns it on")
end

print("FOOD DRINK UNLOCK TEST PASSED")
