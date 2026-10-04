-- Food and Drink buttons: the choice (level, stack, usable, class gate, unloaded items), the
-- secure attributes, nothing changed in combat and caught up after it, the listeners only while
-- on, the buttons shown or hidden, the Edit Mode place, and the data's shape.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", {"!!!TwichUI"})

local frames = {}
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.events, o.attrs = false, {}, {}, {}, {}
  table.insert(frames, o)
  return setmetatable(o, {__index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "SetAttribute" then return function(s, n, v) s.attrs[n] = v end end
    if k == "GetAttribute" then return function(s, n) return s.attrs[n] end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "SetPoint" then return function(s, ...) s.point = {...} end end
    if k == "ClearAllPoints" then return function(s) s.point = nil end end
    if k == "CreateAnimationGroup" then return function(s)
      local g = Fake({ plays = 0, stops = 0 })
      g.Play = function(self) self.plays = self.plays + 1; self.playing = true end
      g.Stop = function(self) self.stops = self.stops + 1; self.playing = false end
      g.CreateAnimation = function(_, kind)
        local a = Fake({ kind = kind })
        a.SetFromAlpha = function(self, v) self.from = v end
        a.SetToAlpha = function(self, v) self.to = v end
        a.SetDuration = function(self, v) self.duration = v end
        a.SetSmoothing = function() end
        s.anim = a
        return a
      end
      s.group = g
      return g
    end end
    if k == "SetBackdrop" then return function(s, v) s.backdrop = v end end
    if k == "SetBackdropBorderColor" then return function(s, ...) s.bcolor = {...} end end
    if k == "SetHeight" then return function(s, v) s.h = v end end
    if k == "SetWidth" then return function(s, v) s.w = v end end
    if k == "SetColorTexture" then return function(s, ...) s.color = {...} end end
    if k == "SetTexCoord" then return function(s, ...) s.texcoord = {...} end end
    if k == "SetSize" then return function(s, w, h) if w then s.w, s.h = w, h end end end
    if k == "GetSize" then return function(s) return s.w or 0, s.h or 0 end end
    if k == "GetCenter" then return function(s) return s.cx, s.cy end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    return function() end
  end})
end
c.CreateFrame = function() return Fake() end
c.UIParent = Fake()
c.UIParent.cx, c.UIParent.cy = 512, 384
c.EDITING = false
c.EventRegistry = { callbacks = {} }
function c.EventRegistry:RegisterCallback(event, fn, owner) assert(owner, "registered with an owner"); self.callbacks[event] = fn end
c.EditModeManagerFrame = { IsEditModeActive = function() return c.EDITING end }
c.GameTooltip = Fake()

c.LEVEL, c.COMBAT = 30, false
c.BAGS = {}      -- [bag] = { [slot] = itemID }
c.ITEMS = {}     -- [id] = { class, sub, name, minLevel, usable, count, icon, spell, text }
c.UNCACHED, c.REQUESTED, c.SPELL_UNLOADED, c.SPELL_REQUESTED = {}, {}, {}, {}
c.NUM_BAG_SLOTS = 4
c.HEALTH, c.MANA = "Health", "Mana"
c.UnitLevel = function() return c.LEVEL end
c.InCombatLockdown = function() return c.COMBAT end
c.C_Container = {
  GetContainerNumSlots = function(bag) local b = c.BAGS[bag]; return b and 20 or 0 end,
  GetContainerItemInfo = function(bag, slot) local id = c.BAGS[bag] and c.BAGS[bag][slot]; return id and { itemID = id } end,
}
c.C_Item = {
  GetItemInfoInstant = function(id) local i = c.ITEMS[id]; if not i then return end return id, "", "", "", i.icon or 1, i.class, i.sub end,
  GetItemInfo = function(id) local i = c.ITEMS[id]; if not i or c.UNCACHED[id] then return end return i.name, "link", 1, 1, i.minLevel end,
  GetItemSpell = function(id) local i = c.ITEMS[id]; if i and i.spell then return i.spellName, i.spell end end,
  IsUsableItem = function(id) return c.ITEMS[id].usable ~= false, false end,
  GetItemCount = function(id) return c.ITEMS[id].count end,
  RequestLoadItemDataByID = function(id) c.REQUESTED[id] = true end,
}
-- The game's plain use-spells, as seen with /tui probe: 434 "Food", 431 "Drink". Items here have
-- spells of their own (any ID) so each can have its own text; only the names matter.
c.C_Spell = {
  GetSpellName = function(id) return ({ [434] = "Food", [431] = "Drink" })[id] end,
  GetSpellDescription = function(id)
    if c.SPELL_UNLOADED[id] then return "" end
    for _, i in pairs(c.ITEMS) do if i.spell == id then return i.text end end
  end,
  RequestLoadSpellData = function(id) c.SPELL_REQUESTED[id] = true end,
}
local EAT, DRINK = "Restores %d health over 21 sec.  Must remain seated while eating.", "Restores %d mana over 21 sec.  Must remain seated while drinking."
local function Item(id, name, minLevel, count, extra)
  c.ITEMS[id] = { class = 0, sub = 5, name = name, minLevel = minLevel, count = count, icon = 100 + id,
    spell = 10000 + id, spellName = "Food", text = EAT:format(234) }
  for k, v in pairs(extra or {}) do c.ITEMS[id][k] = v end
end
local function Drink(id, name, minLevel, count, amount, extra)
  Item(id, name, minLevel, count, extra)
  c.ITEMS[id].spellName, c.ITEMS[id].text = "Drink", DRINK:format(amount)
  for k, v in pairs(extra or {}) do c.ITEMS[id][k] = v end
end
local function Bags(list) c.BAGS = { [0] = {} }; for i, id in ipairs(list) do c.BAGS[0][i] = id end end

for _, f in ipairs({"chronicle/Style.lua", "modules/FoodDrink.lua", "modules/FoodDrinkProbe.lua"}) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { foodDrink = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local F = R.FoodDrink
local M = c.TwichUIDB.modules
local events = R.frame.events

-- Pick: the most restored, then the smaller stack, then the lower ID.
do
  assert(F.Pick({}) == nil)
  local pick = F.Pick({ { id = 5, amount = 234, count = 20 }, { id = 6, amount = 420, count = 40 }, { id = 7, amount = 420, count = 3 } })
  assert(pick.id == 7, "most restored, then the part stack")
  assert(F.Pick({ { id = 9, amount = 5, count = 2 }, { id = 8, amount = 5, count = 2 } }).id == 8, "then the lower ID")
end

-- Classify, on the texts the game gave (probe output) and what it must refuse.
do
  local names, words = { food = "Food", drink = "Drink" }, { health = "Health", mana = "Mana" }
  local function Kinds(spell, text)
    local kinds, amount = F.Classify(spell, text, names, words)
    if not kinds then return nil end
    return (kinds.food and "F" or "") .. (kinds.drink and "D" or ""), amount
  end
  local k, n = Kinds("Drink", "Restores 420 mana over 21 sec.  Must remain seated while drinking.")
  assert(k == "D" and n == 420, "plain drink")
  k, n = Kinds("Food", "Restores 234 health over 21 sec.  Must remain seated while eating.")
  assert(k == "F" and n == 234, "plain food")
  k, n = Kinds("Food", "Restores 282 health and 282 mana over 21 sec. Must remain seated while eating.")
  assert(k == "FD" and n == 282, "restores both: counts for both buttons")
  assert(Kinds("Minor Discolored Healing Potion", "Restores 150 to 170 health instantly.") == nil, "not the plain spells")
  assert(Kinds("Food", "Restores 234 health over 21 sec.  Must remain seated while eating. If you spend at least 10 seconds eating you will become Well Fed and gain 8 Stamina for 15 min.") == nil, "buff food is left out")
  assert(Kinds("Food", "Restores 234 health over 21 sec.\n\nAnd more.") == nil, "a second paragraph is left out")
  assert(Kinds("Food", "Restores 1 to 2 health over 21 sec.") == nil, "an unexpected shape is left out")
  assert(Kinds("Food", "") == nil and Kinds(nil, "Restores 5 health over 6 sec.") == nil and Kinds("Food", nil) == nil)
  -- three numbers need the game's words for health and mana; without them it can't tell
  assert(F.Classify("Food", "Restores 282 health and 282 mana over 21 sec.", names, {}) == nil, "no words, no guess")
  assert(F.Classify("Food", "Restores 282 salud y 282 man\195\161 en 21 s.", names, words) == nil, "another language it can't read is skipped")
  assert(F.Classify("Food", "Restores 5 health over 6 sec.", {}, words) == nil, "spell names unknown: nothing classified")
end

local function Look() FlushTimers() end
local function Buttons()
  local food, drink
  for _, f in ipairs(frames) do
    if f.label == "Food" then food = f elseif f.label == "Drink" then drink = f end
  end
  return food, drink
end

assert(events.BAG_UPDATE_DELAYED and events.PLAYER_REGEN_ENABLED and events.SPELL_TEXT_UPDATE, "listens while on")
Item(2287, "Haunch of Meat", 5, 10)                                   -- 234
Item(4605, "Red-speckled Mushroom", 5, 20, { text = EAT:format(300) }) -- the most food
Drink(1179, "Ice Cold Milk", 5, 15, 420)
Drink(1205, "Melon Juice", 15, 5, 700)                                  -- more, but level 15 is fine at 30
Item(15, "Buff Food", 5, 5, { text = EAT:format(300) .. " Well Fed: gain 8 Stamina for 15 min." })
Drink(4601, "Too High", 35, 5, 9000)                                     -- above level 30
Item(4542, "Not Usable", 5, 5, { usable = false, text = EAT:format(900) })
Item(211780, "Scroll", 1, 1, { sub = 4, spell = nil })                  -- class 0 but not Food & Drink
Item(3448, "Senggin Root", 1, 3, { spellName = "Food", spell = 2639, text = "Restores 100 health and 100 mana over 21 sec. Must remain seated while eating." })
Bags({ 2287, 4605, 1179, 1205, 15, 4601, 4542, 211780, 3448 })
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
local food, drink = Buttons()
assert(food and drink, "both buttons are made")
assert(food.attrs.type == "item" and food.attrs.item == "Red-speckled Mushroom", "most food restored: " .. tostring(food.attrs.item))
assert(drink.attrs.type == "item" and drink.attrs.item == "Melon Juice", "most drink restored: " .. tostring(drink.attrs.item))
assert(food.itemID == 4605 and food.count.text == 20)
assert(food.name.shown == false and food.icon.shown == true)

-- An item that restores both can win either button.
Bags({ 3448, 2287 })
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(food.attrs.item == "Haunch of Meat", "234 beats 100")
assert(drink.attrs.item == "Senggin Root", "the only thing that restores mana")

-- The class gate: an item the game doesn't call Food & Drink is never offered.
Bags({ 4605, 2287 })
c.ITEMS[4605].sub = 1
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(food.attrs.item == "Haunch of Meat", "falls to the next: " .. tostring(food.attrs.item))
c.ITEMS[4605].sub = 5

-- Nothing usable: an empty, labelled button with no action.
Bags({ 15 })
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(food.attrs.type == nil and food.attrs.item == nil and drink.attrs.item == nil, "empty means no action")
assert(food.name.shown == true and food.icon.shown == false and food.count.text == "")

-- An item the game hasn't loaded: asked for, then picked once it arrives.
Bags({ 2287 })
c.UNCACHED[2287] = true
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(c.REQUESTED[2287] and food.attrs.item == nil, "asked the game for it, nothing chosen yet")
c.UNCACHED[2287] = nil
c.FireEvent("GET_ITEM_INFO_RECEIVED", 2287, true); Look()
assert(food.attrs.item == "Haunch of Meat", "chosen once loaded")

-- Spell text that isn't loaded: asked for, then picked when SPELL_TEXT_UPDATE arrives.
c.SPELL_UNLOADED[12287] = true
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(c.SPELL_REQUESTED[12287] and food.attrs.item == nil, "nothing chosen from text it can't read")
c.SPELL_UNLOADED[12287] = nil
c.FireEvent("SPELL_TEXT_UPDATE", 12287); Look()
assert(food.attrs.item == "Haunch of Meat", "chosen once the text arrives")

-- Combat: nothing is changed; the look is made when combat ends.
Bags({ 2287, 4605 })
c.COMBAT = true
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
assert(food.attrs.item == "Haunch of Meat", "attributes untouched in combat")
c.COMBAT = false
c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
assert(food.attrs.item == "Red-speckled Mushroom", "caught up after combat")
c.FireEvent("PLAYER_REGEN_ENABLED"); Look()   -- nothing waiting: nothing to do

-- One of the buttons off: it is hidden and the other takes its place.
M.foodDrinkDrink = false; F.Refresh(); Look()
assert(drink.shown == false and food.shown == true)
M.foodDrinkDrink = true; F.Refresh(); Look()
assert(drink.shown == true)

-- Appearance: ranges, refusing bad values, and each setting reaching the buttons.
do
  local D = F.DEFAULTS
  assert(F.Get("size") == D.size and F.Get("layout") == "horizontal", "defaults")
  assert(F.Set("size", 99) == false and F.Set("size", 30.5) == false and F.Set("layout", "diagonal") == false
    and F.Set("borderColor", "red") == false and F.Set("showCount", "yes") == false and F.Set("nonsense", 1) == false, "bad values are refused")
  assert(F.Get("size") == D.size, "and change nothing")
  c.TwichUIDB.ui = { foodDrink = { size = "big", zoom = -3, borderClass = 1 } }
  assert(F.Get("size") == D.size and F.Get("zoom") == D.zoom and F.Get("borderClass") == D.borderClass, "bad saved values are ignored")
  c.TwichUIDB.ui = nil
  local r, g, b, a = F.ParseColor("ff8c6e38")
  assert(math.abs(r - 0.549) < 0.01 and math.abs(g - 0.431) < 0.01 and math.abs(b - 0.22) < 0.01 and a == 1, "bronze")
  assert(F.ParseColor("nope") == nil)

  Bags({ 2287, 1179 })
  assert(F.Set("size", 40) and F.Set("spacing", 6) and F.Set("layout", "vertical")); Look()
  assert(food.w == 40 and drink.h == 40, "size")
  assert(food.point[1] == "TOPLEFT" and food.point[4] == 0 and food.point[5] == 0, "stacked: first on top")
  assert(drink.point[4] == 0 and drink.point[5] == -46, "stacked: the second a button and a gap below")
  assert(F.Set("layout", "horizontal")); Look()
  assert(drink.point[4] == 46 and drink.point[5] == 0, "side by side: the second a button and a gap across")

  assert(F.Set("borderSize", 3) and F.Set("borderColor", "ff102030")); Look()
  assert(food.rim.top.h == 3 and food.rim.left.w == 3 and food.rim.top.shown, "border thickness")
  assert(food.icon.point[2] == -3 or food.icon.point[3] == -3, "the icon sits inside the border")
  assert(math.abs(food.rim.top.color[1] - 16 / 255) < 0.001 and food.rim.top.color[4] == 1, "border colour")
  assert(F.Set("borderSize", 0)); Look()
  assert(food.rim.top.shown == false, "no border at 0")
  F.Set("borderSize", 1)

  c.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  c.UnitClass = function() return "Mage", "MAGE" end
  assert(F.Set("borderClass", true)); Look()
  assert(food.rim.top.color[1] == 0.25 and food.rim.top.color[3] == 0.92, "class colour wins over the colour")
  F.Set("borderClass", false)

  assert(F.Set("zoom", 10)); Look()
  assert(math.abs(food.icon.texcoord[1] - 0.1) < 1e-9 and math.abs(food.icon.texcoord[2] - 0.9) < 1e-9, "icon zoom")
  assert(food.count.text ~= nil)
  Bags({ 2287 }); c.ITEMS[2287].count = 12
  F.Set("showCount", true); Look()
  assert(food.count.text == 12)
  assert(F.Set("showCount", false)); Look()
  assert(food.count.text == "", "count hidden")

  for key, v in pairs(D) do F.Set(key, v) end
  Look()
  assert(F.Get("size") == D.size and F.Get("showCount") == true)
  c.ITEMS[2287].count = 10
end

-- Border texture and opacity.
do
  local LSM = c.LibStub("LibSharedMedia-3.0")
  LSM:Register("border", "Test Edge", "Interface\\Test\\Edge")
  local function Backdrops()
    local list = {}
    for _, f in ipairs(frames) do local b = rawget(f, "backdrop"); if type(b) == "table" and b.edgeFile then list[#list + 1] = f end end
    return list
  end
  assert(F.Get("borderTexture") == "solid" and F.Get("borderOpacity") == 100, "defaults")
  assert(F.Set("borderTexture", "") == false and F.Set("borderTexture", ("x"):rep(101)) == false
    and F.Set("borderTexture", "bad|name") == false and F.Set("borderOpacity", 101) == false and F.Set("borderOpacity", -1) == false, "bad values are refused")
  local names = {}
  for _, choice in ipairs(F.TextureChoices()) do names[choice[1]] = choice[2] end
  assert(names.solid == "Solid" and names["Test Edge"] == "Test Edge" and names["Blizzard Tooltip"] and not names.None, "choices: Solid and the shared borders")

  -- choosing a texture seeds a thickness it can be drawn at, and draws it
  assert(F.Get("borderSize") == 1)
  assert(F.Set("borderTexture", "Test Edge")); Look()
  assert(F.Get("borderSize") == 12, "a texture is given room")
  local drawn = Backdrops()
  assert(#drawn == 2, "one backdrop on each button")
  assert(drawn[1].backdrop.edgeFile == "Interface\\Test\\Edge" and drawn[1].backdrop.edgeSize == 12, "the chosen edge file at that size")
  assert(food.rim.top.shown == false, "the plain line is hidden")
  assert(drawn[1].shown and drawn[1].bcolor[4] == 1, "tinted at full opacity")
  -- a choice the user already made stays
  assert(F.Set("borderSize", 9) and F.Set("borderTexture", "Blizzard Tooltip")); assert(F.Get("borderSize") == 9, "a thickness that already fits is kept")
  assert(F.Set("borderTexture", "Test Edge"))

  -- opacity applies to the colour and to the class colour
  assert(F.Set("borderOpacity", 40)); Look()
  assert(math.abs(Backdrops()[1].bcolor[4] - 0.4) < 1e-9, "opacity")
  c.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  c.UnitClass = function() return "Mage", "MAGE" end
  assert(F.Set("borderClass", true)); Look()
  local bc = Backdrops()[1].bcolor
  assert(bc[1] == 0.25 and bc[3] == 0.92 and math.abs(bc[4] - 0.4) < 1e-9, "class colour at that opacity")
  F.Set("borderClass", false)
  assert(F.Set("borderTexture", "solid")); Look()
  assert(F.Get("borderSize") == 1, "back to a plain line puts the thickness back")
  assert(food.rim.top.shown and math.abs(food.rim.top.color[4] - 0.4) < 1e-9, "the plain line takes the opacity too")
  for _, f in ipairs(Backdrops()) do assert(not f.shown, "texture frames hidden for the plain line") end

  -- a texture whose addon has gone falls back to the plain line, and stays listed
  assert(F.Set("borderTexture", "Gone Edge")); Look()
  assert(food.rim.top.shown, "falls back to the plain line")
  local listed
  for _, choice in ipairs(F.TextureChoices()) do if choice[1] == "Gone Edge" then listed = choice[2] end end
  assert(listed and listed:find("not available"), "still listed, marked")
  F.Set("borderTexture", "solid"); F.Set("borderOpacity", 100); F.Set("borderSize", 1); Look()
end

-- EllesmereUI's own border textures: listed and drawn through its API only while it is installed.
do
  local LSM = c.LibStub("LibSharedMedia-3.0")
  LSM:Register("border", "Blizzard Dialog", "Interface\\DialogFrame\\UI-DialogBox-Border")
  Bags({ 2287, 1179 })   -- both buttons filled, so both are drawn at full strength
  local calls, fail = {}, false
  c.EllesmereUI = {
    PP = {},
    GetBorderTextureList = function()
      return { { key = "solid", name = "Solid" }, { key = "glow", name = "Glow" }, { key = "shadow", name = "Shadow" },
        { key = "pixels-textured", name = "Pixels Textured" }, { key = "dialog", name = "Blizzard Dialog" },
        { key = "sm:Test Edge", name = "Test Edge" } }
    end,
    ResolveBorderTexture = function(k) return ({ glow = "g", ["pixels-textured"] = "p", dialog = "d" })[k] end,
    BorderPxStep = function() return 2 end,
    BorderLegacyPx = function() return 16 end,
    GetBorderDefaultSize = function(_, key) return key == "pixels-textured" and 2 or nil end,
    GetBorderStyleSelectDefaults = function(key) if key == "pixels-textured" then return { r = 1, g = 1, b = 1 } end return { r = 0, g = 0, b = 0 } end,
    ApplyBorderStyle = function(frame, step, r, g, b, a, key, ...)
      if fail then error("boom") end
      calls[#calls + 1] = { frame = frame, step = step, r = r, g = g, b = b, a = a, key = key, extra = select("#", ...), edge = select(8, ...) }
    end,
  }
  local labels, count = {}, {}
  for _, choice in ipairs(F.TextureChoices()) do labels[choice[1]] = choice[2]; count[choice[2]] = (count[choice[2]] or 0) + 1 end
  assert(labels["eui:pixels-textured"] == "Pixels Textured" and labels["eui:glow"] == "Glow", "EllesmereUI's textures are listed")
  assert(labels["eui:shadow"] == nil and labels["eui:solid"] == nil and labels["eui:sm:Test Edge"] == nil, "not shadow, not its own Solid, not the shared ones twice")
  assert(count["Blizzard Dialog"] == 1 and labels["eui:dialog"], "a name EllesmereUI lists is not listed twice")
  assert(labels["Test Edge"] == "Test Edge", "the shared borders are still there")

  -- picking one: a thickness and a colour that suit it, drawn through ApplyBorderStyle at the exact pixels
  assert(F.Get("borderColor") == F.DEFAULTS.borderColor and F.Get("borderSize") == 1)
  assert(F.Set("borderTexture", "eui:pixels-textured")); Look()
  assert(F.Get("borderSize") == 16 and F.Get("borderColor") == "ffffffff", "seeded: its default size, tinted white")
  assert(#calls == 2, "one call for each button: " .. #calls)
  local call = calls[#calls]
  assert(call.key == "pixels-textured" and call.step == 2 and call.edge == 16 and call.extra == 8, "its key, step and exact edge")
  assert(call.r == 1 and call.g == 1 and call.b == 1 and call.a == 1, "the colour and opacity")
  assert(call.frame ~= food and call.frame.shown, "drawn on a frame of ours, not on the secure button")
  assert(food.rim.top.shown == false, "the plain line is hidden")
  assert(F.Set("borderOpacity", 50)); Look()
  assert(calls[#calls].a == 0.5, "opacity reaches it")
  F.Set("borderOpacity", 100)

  -- the player's own colour is kept when the texture changes
  assert(F.Set("borderColor", "ff102030")); F.Set("borderTexture", "eui:glow")
  assert(F.Get("borderColor") == "ff102030", "a colour the player chose stays")

  -- back to the plain line: hidden frames, thickness and (unchosen) colour back
  F.Set("borderColor", "ffffffff"); F.Set("borderTexture", "eui:pixels-textured"); Look()
  local euiFrame = calls[#calls].frame
  assert(F.Set("borderTexture", "solid")); Look()
  assert(not euiFrame.shown and food.rim.top.shown, "the plain line again")
  assert(F.Get("borderSize") == 1 and F.Get("borderColor") == F.DEFAULTS.borderColor, "its own thickness and colour back")

  -- an error in EllesmereUI's call falls back to the line
  assert(F.Set("borderTexture", "eui:glow")); fail = true; Look()
  assert(food.rim.top.shown, "falls back when the call fails")
  fail = false

  -- EllesmereUI gone: the saved choice draws the plain line and stays listed
  c.EllesmereUI = nil; Look()
  assert(food.rim.top.shown and not euiFrame.shown, "falls back to the plain line")
  local listed
  for _, choice in ipairs(F.TextureChoices()) do if choice[1] == "eui:glow" then listed = choice[2] end end
  assert(listed == "glow (not available)", "still listed, marked: " .. tostring(listed))
  assert(F.Get("borderTexture") == "eui:glow", "the choice is kept for when it comes back")
  F.Set("borderTexture", "solid"); F.Set("borderSize", 1); F.Set("borderColor", F.DEFAULTS.borderColor); Look()
end

-- Button opacity, and the mouseover fade.
do
  local D = F.DEFAULTS
  local function ContainerAlpha()
    for _, f in ipairs(frames) do
      local a = rawget(f, "alpha")
      if type(a) == "number" then return a end
    end
  end
  local function Mouse(over)   -- over: the frame the mouse is on, or nil
    for _, f in ipairs(frames) do rawset(f, "IsMouseOver", function(self) return self == over end) end
  end
  Mouse(nil)
  Bags({ 2287, 1179 }); Look()
  assert(D.buttonOpacity == 100 and D.mouseover == false and D.idleOpacity == 30, "defaults")
  assert(ContainerAlpha() == 1, "fully solid by default")
  assert(F.Set("buttonOpacity", 101) == false and F.Set("idleOpacity", -1) == false and F.Set("mouseover", "yes") == false, "bad values are refused")
  assert(F.Set("buttonOpacity", 60)); assert(ContainerAlpha() == 0.6, "button opacity, at once")

  -- mouseover: idle opacity until a button is hovered, then the button opacity
  assert(F.Set("idleOpacity", 20) and F.Set("mouseover", true))
  assert(math.abs(ContainerAlpha() - 0.2) < 1e-9, "idle while the mouse is away")
  Mouse(food); food.scripts.OnEnter(food)
  assert(ContainerAlpha() == 0.6, "button opacity under the mouse")
  Mouse(nil); food.scripts.OnLeave(food); FlushTimers()
  assert(math.abs(ContainerAlpha() - 0.2) < 1e-9, "idle again when it leaves")
  Mouse(drink); food.scripts.OnLeave(food); FlushTimers()
  assert(ContainerAlpha() == 0.6, "moving to the other button is not leaving")
  Mouse(nil); drink.scripts.OnLeave(drink); FlushTimers()
  assert(math.abs(ContainerAlpha() - 0.2) < 1e-9)

  -- changes land at once in combat (a plain frame's alpha), while the item choice waits
  c.COMBAT = true
  assert(F.Set("idleOpacity", 40)); assert(math.abs(ContainerAlpha() - 0.4) < 1e-9, "opacity changes in combat")
  c.COMBAT = false; Look()

  -- Edit Mode shows them at full strength, and the fade returns after
  c.EDITING = true; c.EventRegistry.callbacks["EditMode.Enter"]()
  assert(ContainerAlpha() == 0.6, "full strength in Edit Mode")
  c.EDITING = false; c.EventRegistry.callbacks["EditMode.Exit"]()
  assert(math.abs(ContainerAlpha() - 0.4) < 1e-9, "faded again after Edit Mode")

  -- the fade off: the button opacity always
  assert(F.Set("mouseover", false)); assert(ContainerAlpha() == 0.6)
  assert(F.Set("buttonOpacity", 0)); assert(ContainerAlpha() == 0, "0 is allowed")
  for key, v in pairs(D) do F.Set(key, v) end
  Look()
  assert(ContainerAlpha() == 1)
end

-- The fade: the mouse coming and going plays a brief alpha animation to the new opacity; a
-- setting changed in the options is instant; the final alpha is the target either way.
do
  local container
  for _, f in ipairs(frames) do if rawget(f, "group") then container = f end end
  assert(container and container.group and container.anim, "the container has an alpha animation")
  local group, anim = container.group, container.anim
  assert(anim.kind == "Alpha")
  local function Mouse(over)
    for _, f in ipairs(frames) do rawset(f, "IsMouseOver", function(self) return self == over end) end
  end
  Mouse(nil)
  assert(F.Set("buttonOpacity", 80)); assert(F.Set("idleOpacity", 20))
  local plays = group.plays
  assert(F.Set("mouseover", true))
  assert(group.plays == plays and math.abs(container.alpha - 0.2) < 1e-9, "from the options: instant")
  Look()   -- let the redraw the options asked for happen first
  Mouse(food); food.scripts.OnEnter(food)
  assert(group.plays == plays + 1 and math.abs(anim.from - 0.2) < 1e-9 and anim.to == 0.8, "fades in from idle to full")
  assert(anim.duration == 0.12 and container.alpha == 0.8, "quickly, and ends at the target")
  Mouse(nil); food.scripts.OnLeave(food); FlushTimers()
  assert(group.plays == plays + 2 and anim.from == 0.8 and math.abs(anim.to - 0.2) < 1e-9, "fades out when the mouse leaves")
  assert(anim.duration == 0.25 and math.abs(container.alpha - 0.2) < 1e-9, "more slowly")
  -- nothing to fade when nothing changes
  Mouse(nil); drink.scripts.OnLeave(drink); FlushTimers()
  assert(group.plays == plays + 2, "no animation when the opacity is already there")
  -- a new fade first stops the one running
  local stops = group.stops
  Mouse(food); food.scripts.OnEnter(food)
  assert(group.stops > stops and group.playing, "an earlier fade is stopped before the next")
  Mouse(nil); food.scripts.OnLeave(food); FlushTimers()
  for key, v in pairs(F.DEFAULTS) do F.Set(key, v) end
  Look()
end

-- Edit Mode: an outline over the buttons; dragging saves the place, right-click clears it.
do
  assert(c.EventRegistry.callbacks["EditMode.Enter"], "hooks Edit Mode")
  c.EDITING = true
  c.EventRegistry.callbacks["EditMode.Enter"]()
  local mover
  for _, f in ipairs(frames) do if f.scripts.OnDragStop then mover = f end end
  assert(mover and mover.shown, "outline shown in Edit Mode")
  mover.cx, mover.cy = 612, 304
  mover.scripts.OnDragStop(mover)
  local saved = c.TwichUIDB.ui.foodDrinkPosition
  assert(saved and saved.x == 100 and saved.y == -80, "place kept as an offset from the centre")
  local x, y = F.Position(); assert(x == 100 and y == -80)
  mover.scripts.OnMouseUp(mover, "RightButton")
  assert(c.TwichUIDB.ui.foodDrinkPosition == nil)
  x, y = F.Position(); assert(x == 0 and y == -220, "default again")
  c.COMBAT = true
  mover.scripts.OnDragStart(mover)   -- no move in combat (StartMoving is a no-op stub; must not error)
  c.COMBAT = false
  c.EDITING = false
  c.EventRegistry.callbacks["EditMode.Exit"]()
  assert(not mover.shown, "outline gone when Edit Mode closes")
  c.TwichUIDB.ui.foodDrinkPosition = { x = 1e9, y = 0 }
  x, y = F.Position(); assert(x == 0 and y == -220, "a bad saved place is ignored")
end

-- Off: nothing listened for, nothing shown.
M.foodDrink = false; F.Refresh()
assert(not events.BAG_UPDATE_DELAYED and not events.PLAYER_REGEN_ENABLED and not events.GET_ITEM_INFO_RECEIVED and not events.SPELL_TEXT_UPDATE, "no listeners when off")
c.FireEvent("BAG_UPDATE_DELAYED"); Look()   -- nothing happens, nothing errors

-- The temporary probe: prints consumables only, changes nothing, says so when text isn't loaded.
do
  local out = {}
  c.print = function(s) table.insert(out, s) end
  c.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
  c.C_TooltipInfo = { GetBagItem = function() return { lines = { { type = 44, leftText = "Use: Restores 234 health" } } } end }
  Item(15, "Elixir", 10, 1, { sub = 1, spell = nil })
  Bags({ 2287, 15 })
  local before = {}
  for _, f in ipairs(frames) do before[f] = f.attrs and f.attrs.item end
  c.SlashCmdList.TWICHUI("probe")
  local text = table.concat(out, "\n")
  assert(text:find("Haunch of Meat", 1, true) and text:find("Restores 234 health", 1, true), text)
  assert(text:find("Elixir", 1, true), "any consumable is listed, not only food")
  assert(text:find("use-spell: Food (12287)", 1, true) and text:find("tooltip %[44%]"), text)
  for _, f in ipairs(frames) do assert(before[f] == (f.attrs and f.attrs.item), "the probe changes nothing") end
end

-- Off by default.
local d = MakeClient("Pat", {"!!!TwichUI"})
d.LOADED["!!!TwichUI"] = true; d.FireEvent("ADDON_LOADED", "!!!TwichUI")
assert(d.TwichUIDB.modules.foodDrink == false, "opt-in")
assert(d.TwichUIDB.modules.foodDrinkFood == true and d.TwichUIDB.modules.foodDrinkDrink == true)

print("FOOD DRINK TEST PASSED")
