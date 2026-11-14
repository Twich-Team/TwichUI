-- The Workshop window (TwichUI_Workshop/Window.lua) on recording stand-in frames: it is built on first show, listens to events
-- only while shown, forgets what it read when hidden, shows an instruction (not an empty list) with no profession open, draws the
-- recipes, queue and materials, and its buttons queue, change and remove. Synthetic: it proves what is drawn and kept, not how
-- the game draws it.
dofile(TESTS .. "mi_mock.lua")
local Press = dofile(TESTS .. "press.lua")   -- opt-in (M5): frames record the mouse state, and Press refuses a control that could not take a click

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
      Press.Instrument(fr, name)   -- last, so it replaces the no-op EnableMouse above with one that records
      if name then cl[name] = fr end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    cl.UISpecialFrames = {}
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
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

for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua", "Worth.lua", "Sell.lua", "Disenchant.lua", "Advisor.lua", "Session.lua", "AdvisorData.lua", "AuctionButton.lua", "Style.lua", "ViewOverview.lua", "ViewOpportunities.lua", "ViewCrafting.lua", "ViewShopping.lua", "ViewAdvisor.lua", "ViewStrategy.lua", "Window.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = R.Workshop
local pending = {}
c.C_Timer.After = function(_,fn) pending[#pending+1]=fn end
local function Pump()
  local steps=0
  while #pending>0 do local p=pending; pending={}; for _,fn in ipairs(p) do fn() end; steps=steps+1; assert(steps<1000,"timers settle") end
end
c.C_Item.GetItemInfo = function(id) return g.names[id], nil, 1, nil, nil, "Trade Goods", "Herb",20,"",5000+id,10,7,0,0 end
g.bags[10],g.bags[11]=5,0
W.Session.AllRecipes=function() return { {id=1,name="Potion",outItem=11,mats={{item=10,qty=1}}} } end
W.Window.Show()
Check(W.Window.Frame().tabAdvisor,"first-class sidebar control")
W.UI.Advisor.Open(10); Pump()
local p=W.Window.Page("advisor")
Same(W.Window.Mode(),"advisor"); Same(p.result.item,10); Same(p.result.action,"unknown")
Check(p.detail.empty:IsShown()==false,"detail shown")
Same(#p.list.data,2); Check(p.detail.recipes:IsEnabled(),"known uses action")
p.search:SetText("silver"); p.search:GetScript("OnTextChanged")(p.search); Pump()
Same(#p.list.data,1); Same(p.result.item,11)
p.search:SetText(""); p.search:GetScript("OnTextChanged")(p.search); Pump()
p.source:GetScript("OnClick")(p.source); Pump(); Same(#p.list.data,1); Same(p.list.data[1].item,10)
W.AdvisorData.Track(11)
p.source:GetScript("OnClick")(p.source); Pump(); Same(#p.list.data,1); Same(p.result.item,11)
W.UI.Advisor.Open(10); Pump(); Same(p.result.item,10,"cross-page entry resets stale filters")
Same(#p.list.data,2,"cross-page entry restores all known items")
Check(W.Snapshot().advisorItems>0,"discovery retained count is visible to diagnostics")
local infoReader=c.C_Item.GetItemInfo
c.C_Item.GetItemQualityColor=function(q) if q==3 then return 0,0.44,0.87 end return 1,1,1 end
c.C_Item.GetItemInfo=function(id)
  local n,l,q,lev,req,kind,sub,stack,equip,icon,sell,class,subclass,bind=infoReader(id)
  return id==10 and "Arriving item name" or n,l,id==10 and 3 or q,lev,req,kind,sub,stack,equip,icon,sell,class,subclass,bind
end
p.detail.name.SetTextColor=function(self,r,g,b) self.rgb={r,g,b} end
W.UI.Advisor.ItemReady(10,true); W.Window.Render(); Pump()
Same(p.detail.name:GetText(),"Arriving item name","late item data updates the selected identity")
Same(p.detail.name.rgb[2],0.44,"native quality color is used")
W.Window.SetMode("overview"); Pump(); Same(#p.list.data,0,"hidden discovery released")
for _,row in ipairs(p.list.rows) do Same(row.data,nil,"pooled rows release catalog references") end
Same(W.Snapshot().advisorItems,0,"diagnostics show discovery released")
W.Window.SetMode("advisor"); Pump(); Same(p.result.item,10,"selection survives page switch")
W.Window.Hide(); Pump()
print("advisor UI: OK")
