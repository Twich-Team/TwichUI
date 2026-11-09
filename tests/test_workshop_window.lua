-- The Workshop window (TwichUI_Workshop/Window.lua) on recording stand-in frames: it is built on first show, listens to events
-- only while shown, forgets what it read when hidden, shows an instruction (not an empty list) with no profession open, draws the
-- recipes, queue and materials, and its buttons queue, change and remove. Synthetic: it proves what is drawn and kept, not how
-- the game draws it.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local c = MIClient("Rich", {
  db = { modules = {} },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent, template)
      local fr = MIFake(kind, parent)
      fr.SetColorTexture = function() end
      fr.SetVertexColor = function() end
      fr.SetBackdropColor = function() end
      fr.SetBackdropBorderColor = function() end
      fr.SetTexCoord = function() end
      fr.SetTexture = function(s, v) s.texture = v end
      fr.SetFrameLevel = function(s, l) s.level = l end
      fr.GetFrameLevel = function(s) return s.level or 5 end
      fr.SetVerticalScroll = function(s, v) s.scroll = v end
      fr.GetVerticalScroll = function(s) return s.scroll or 0 end
      fr.SetFontObject = function() end
      fr.SetMaxLetters = function() end
      fr.SetAutoFocus = function() end
      fr.SetTextInsets = function() end
      fr.SetJustifyV = function() end
      fr.SetWordWrap = function() end
      fr.EnableMouse = function() end
      fr.SetToplevel = function() end
      fr.SetMovable = function() end
      fr.SetClampedToScreen = function() end
      fr.RegisterForDrag = function() end
      fr.SetDontSavePosition = function() end
      fr.UnregisterAllEvents = function(s) s.events = {} end
      fr.SetFrameStrata = function() end
      fr.SetMotionScriptsWhileDisabled = function() end
      fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
      fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end return t end
      if name then cl[name] = fr end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    cl.UISpecialFrames = {}
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = {},
})
c.TwichUIDB = c.TwichUIDB or {}
local R = c.TwichUI

-- the fake game (as in test_workshop.lua)
local g = { bags = {}, names = { [10] = "Peacebloom", [11] = "Silverleaf" }, recipes = {}, schem = {}, opened = {} }
g.prof = { professionID = 171, professionName = "Alchemy" }
c.C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return g.prof end,
  IsNPCCrafting = function() return false end, IsTradeSkillGuild = function() return false end, IsTradeSkillLinked = function() return false end,
  IsDataSourceChanging = function() return false end,
  GetFilteredRecipeIDs = function() return g.filtered end,
  GetRecipeInfo = function(id) local r = g.recipes[id]; return r and { name = r.name, learned = true, icon = 1000 + id, relativeDifficulty = r.diff } end,
  GetRecipeSchematic = function(id) return g.schem[id] end,
  OpenRecipe = function(id) g.opened[#g.opened + 1] = id end,
}
c.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } }
c.C_Item = {
  GetItemCount = function(id) return g.bags[id] end,
  GetItemInfoInstant = function(id) return id, "a", "b", "", 5000 + id end,
  GetItemInfo = function(id) return g.names[id] end,
  RequestLoadItemDataByID = function() end,
}
c.InCombatLockdown = function() return false end
c.IsShiftKeyDown = function() return false end

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Observe.lua", "Session.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
Check(W.ready and W.Open and W.Toggle, "the window file marks the addon ready")
local Win, S, Q = W.Window, W.Session, W.Queue

local function Fire(e, ...) local w = R.Workshop.Window.Frame(); if w.events[e] and w.scripts.OnEvent then w.scripts.OnEvent(w, e, ...) end end
local function Events(f) local n = 0 for _ in pairs(f.events) do n = n + 1 end return n end

-- with no profession open: an instruction, no events yet, no frame built until asked
Check(Win.Frame() == nil, "nothing is built until the window is asked for")
Same(W.Snapshot().built, false)
g.filtered = nil
Win.Show()
local f = Win.Frame()
Check(f and f:IsShown(), "shown")
Check(Events(f) > 0, "listens while shown"); Same(W.Snapshot().events, Events(f))
Check(S.Notices()[1]:find("Open one of your professions", 1, true), "an instruction, not an unexplained empty list")
Same(#Win.Lists().recipes.data, 0)
Check(Win.Lists().recipes.empty:GetText() == "No recipes yet.", "and the list says why it is empty")
Check(Win.Lists().mats.empty:GetText():find("Materials for the queue", 1, true))
Check(tContains == nil or true)
local escape = false
for _, n in ipairs(c.UISpecialFrames) do if n == "TwichUIWorkshop" then escape = true end end
Check(escape, "Esc closes it (UISpecialFrames, never the game menu's handler list)")

-- hiding drops every listener
f:Hide()
Same(Events(f), 0, "hidden: no events"); Same(W.Snapshot().events, 0)

-- a profession window of the player's own: recipes appear on show, with rows
g.recipes = { [1] = { name = "Healing Potion", diff = 1 }, [2] = { name = "Mana Potion", diff = 0 } }
g.schem[1] = { quantityMin = 1, quantityMax = 2, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 2, required = true } } }
g.schem[2] = { quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 1, reagents = { { itemID = 10 } }, quantityRequired = 1, required = true }, { reagentType = 1, reagents = { { itemID = 11 } }, quantityRequired = 1, required = true } } }
g.filtered = { 1, 2 }
f:Show()
Same(#Win.Lists().recipes.data, 2)
local rows = Win.Lists().recipes.rows
Check(#rows >= 2 and rows[1]:IsShown(), "recipe rows are made for what is shown")
Check(rows[1].name:GetText() == "Healing Potion" and rows[1].diff:GetText() == "Yellow", "the name and the difficulty in words")
Check(rows[1].sub:GetText() == "Makes 1-2", rows[1].sub:GetText())
Check(rows[2].diff:GetText() == "Orange")

-- queue it with the row's own button, then change and remove
rows[1].add:GetScript("OnClick")(rows[1].add)
Same(#Q.Entries(), 1); Same(Q.Entries()[1].name, "Healing Potion")
Check(rows[1].add.text:GetText() == "Queued" and rows[1].add.enabled == false, "a queued recipe says Queued and can't be added twice")
local qrow = Win.Lists().queue.rows[1]
Check(qrow:IsShown() and qrow.name:GetText():find("Healing Potion", 1, true) and qrow.name:GetText():find("Alchemy", 1, true))
Check(qrow.line:GetText() == "1 craft - makes 1-2", qrow.line:GetText())
Check(not qrow.stale:IsShown(), "known materials: no update line")
qrow.more:GetScript("OnClick")(qrow.more); qrow.more:GetScript("OnClick")(qrow.more)
Same(Q.Entries()[1].crafts, 3)
Check(qrow.line:GetText() == "3 crafts - makes 1-2 each, 3-6 in all", qrow.line:GetText())
Same(qrow.count:GetText(), "3")
c.IsShiftKeyDown = function() return true end
qrow.less:GetScript("OnClick")(qrow.less)
Same(Q.Entries()[1].crafts, 1, "Shift changes by five but never below one")
c.IsShiftKeyDown = function() return false end

-- materials against the bags (bags only), with the words
g.bags = { [10] = 1 }
qrow.more:GetScript("OnClick")(qrow.more)   -- 2 crafts: 4 Peacebloom
Win.Render()
local mrow = Win.Lists().mats.rows[1]
Check(mrow:IsShown() and mrow.name:GetText() == "Peacebloom" and mrow.need:GetText() == "4" and mrow.have:GetText() == "1" and mrow.short:GetText() == "3", "need, in bags, still needed")
Same(R.Workshop.Window.Frame().headline:GetText(), "Still needed: 1 material.")
g.bags = {}
Win.Render()
Check(Win.Lists().mats.rows[1].have:GetText() == "Unknown" and Win.Lists().mats.rows[1].short:GetText() == "Unknown", "an unreadable bag count is Unknown, never 0")
g.bags = { [10] = 4 }
Win.Render()
Same(f.headline:GetText(), "All the materials are in your bags.")

-- open recipe, remove
qrow.open:GetScript("OnClick")(qrow.open)
Same(g.opened[#g.opened], 1)
Check(qrow.open.text:GetText() == "Open recipe")
qrow.remove:GetScript("OnClick")(qrow.remove)
Same(#Q.Entries(), 0); Check(f.note:GetText():find("Removed", 1, true))

-- events: a burst of changes is one redraw, a stale one is dropped, hidden stops everything
rows[2].add:GetScript("OnClick")(rows[2].add)
local before = W.Snapshot().renders
Fire("BAG_UPDATE_DELAYED"); Fire("BAG_UPDATE_DELAYED"); Fire("GET_ITEM_INFO_RECEIVED")
Same(W.Snapshot().renders, before, "nothing is drawn until the burst settles")
FlushTimers()
Same(W.Snapshot().renders, before + 1, "one redraw for the burst")
Fire("BAG_UPDATE_DELAYED")
f:Hide()
FlushTimers()
Same(W.Snapshot().renders, before + 1, "a redraw scheduled before hiding is dropped")
Same(W.Snapshot().recipes, 0, "the recipe lists are forgotten when hidden")
Same(W.Snapshot().queue, 1, "the queue is not")
-- reopening reads fresh (bags changed while it was hidden)
g.bags = {}
f:Show()
Check(Win.Lists().mats.rows[1].have:GetText() == "Unknown", "reopened: drawn from a fresh read, never from before it was closed")
-- profession window events re-read
g.filtered = { 1 }
Fire("TRADE_SKILL_LIST_UPDATE")
FlushTimers()
Same(#Win.Lists().recipes.data, 1, "the profession window's changes are followed while shown")

-- the profession being someone else's
g.prof = { professionID = 164, professionName = "Blacksmithing" }
c.C_TradeSkillUI.IsTradeSkillLinked = function() return true end
Fire("TRADE_SKILL_SHOW"); FlushTimers()
Check(f.notice:GetText():find("isn't one of your own", 1, true), "said, with the earlier list kept")
Same(#S.Professions(), 1, "a linked profession is not added")
f:Hide()
print("PASSED")
