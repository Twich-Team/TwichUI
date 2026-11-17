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
-- Record the same native menu contract used by Forever. Opening alone never picks.
local opened
local rootMenu
c.MenuVariants={GetDefaultMenuMixin=function() return {} end}
c.AnchorUtil={CreateAnchor=function(...) return {...} end}
c.MenuUtil={CreateRootMenuDescription=function()
  local root={entries={},SetMinimumWidth=function() end,SetScrollMode=function() end}
  function root:AddMenuReleasedCallback(fn) self.release=fn end
  function root:CreateRadio(text,selected,choose)
    local entry={text=text,selected=selected,choose=function() choose(); opened:Close() end}
    self.entries[#self.entries+1]=entry
    return {AddInitializer=function() end}
  end
  rootMenu=root; return root
end}
c.Menu={GetManager=function() return {OpenMenu=function(_,owner,root,anchor)
  local menu={entries=root.entries,closed=false,anchor=anchor}
  function menu:Close() self.closed=true; root.release() end
  opened=menu; return menu
end} end}
local function Choose(button,label)
  button:GetScript("OnClick")(button)
  for _,entry in ipairs(opened.entries) do if entry.text==label then entry.choose(); return end end
  error("missing menu choice: " .. label)
end
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
W.Window.SetMode("advisor"); Pump()
local p=W.Window.Page("advisor")
Same(W.Window.Mode(),"advisor"); Same(p.result.item,10); Same(p.result.action,"unknown")
Check(p.detail.empty:IsShown()==false,"detail shown")
Same(#p.list.data,1,"first use shows carried items"); Same(p.source.text:GetText(),"In bags")
Same(W.AdvisorData.Source(),"bags")
p.source:GetScript("OnClick")(p.source)
Same(#p.list.data,1,"opening source menu does not refresh results")
Check(opened.entries[1].selected(),"current source marked")
opened:Close(); Same(W.AdvisorData.Source(),"bags","dismissal preserves preference")
Choose(p.source,"All known items"); Pump()
Same(W.AdvisorData.Source(),"all","explicit source persisted")
Same(opened.anchor[1],"TOPLEFT","menu is anchored below its trigger")
Same(opened.anchor[3],"BOTTOMLEFT")
c.TwichUIDB.workshop.view.advisorSource="invalid"
Same(W.AdvisorData.Source(),"bags","invalid saved source defaults narrowly")
W.AdvisorData.SetSource("all")

Same(#p.list.data,2); Check(p.detail.recipes:IsEnabled(),"known uses action")
p.search:SetText("silver"); p.search:GetScript("OnTextChanged")(p.search); Pump()
Same(p.search.hint:IsShown(),false,"search hint hides for programmatically entered text")
Same(#p.list.data,1); Same(p.result.item,11)
p.search:SetText(""); p.search:GetScript("OnTextChanged")(p.search); Pump()
Same(p.search.hint:IsShown(),true,"empty unfocused search restores its hint")
Choose(p.source,"In bags"); Pump(); Same(#p.list.data,1); Same(p.list.data[1].item,10)
W.AdvisorData.Track(11)
Choose(p.source,"Tracked items"); Pump(); Same(#p.list.data,1); Same(p.result.item,11)
Choose(p.category,"Trade Goods"); Pump(); Same(#p.list.data,1)
Choose(p.category,"All categories"); Pump(); Same(#p.list.data,1)
W.UI.Advisor.Open(10); Pump(); Same(p.result.item,10,"cross-page entry resets stale filters")
Same(#p.list.data,2,"cross-page entry restores all known items")
Same(W.AdvisorData.Source(),"tracked","external reveal does not overwrite source preference")
Choose(p.source,"All known items"); Pump()
Same(W.AdvisorData.Source(),"all","explicitly choosing the temporary source saves that preference")
p.auctionable:GetScript("OnClick")(p.auctionable); Pump(); Same(#p.list.data,2,"auctionable combines with all known")
Choose(p.source,"In bags"); Pump(); Same(#p.list.data,1,"auctionable combines with bag filter")
p.search:SetText("silver"); p.search:GetScript("OnTextChanged")(p.search); Pump(); Same(#p.list.data,0,"search combines with source")
W.UI.Advisor.Open(10); Pump()

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
-- Thousands of real discovered identities, still a bounded visible row pool.
for id=1000,3999 do g.names[id]="Sample " .. id; g.bags[id]=1 end
c.C_Container={GetContainerNumSlots=function(bag) return bag==0 and 3000 or 0 end,
  GetContainerItemInfo=function(_,slot) return {itemID=999+slot,stackCount=1,isBound=false} end}
W.UI.Advisor.Invalidate(); W.Window.Render(); Pump()
Choose(p.source,"All known items"); Pump()
Check(#p.list.data>=3000,"large real catalog")
p.list.scroll:SetVerticalScroll(641); p.list:Layout()
local chosen=p.result.item
W.UI.Advisor.ItemReady(1010,true); W.Window.Render(); Pump()
Same(p.list.scroll:GetVerticalScroll(),641,"metadata refresh preserves scrolled viewport")
Same(p.result.item,chosen,"metadata refresh preserves selection")
for _,sourceName in ipairs({"In bags","All known items"}) do
  Choose(p.source,sourceName); Pump()
  p.list.scroll:SetVerticalScroll(1323); p.list:Layout()
  local row=p.list.rows[2]; row:GetScript("OnClick")(row); Pump()
  local selectedItem=p.result.item
  Same(p.list.scroll:GetVerticalScroll(),1323,"selection retains viewport: " .. sourceName)
  for i=1,4 do W.Window.Render(); Pump() end
  Same(p.list.scroll:GetVerticalScroll(),1323,"recommendation paint retains viewport")
  W.UI.Advisor.Invalidate(); W.Window.Render()
  p.list.scroll:SetVerticalScroll(1607); p.list:Layout(); Pump()
  Same(p.list.scroll:GetVerticalScroll(),1607,"asynchronous discovery preserves latest scroll")
  local sameData=p.list.data
  Choose(p.source,sourceName); Pump()
  Same(p.list.data,sameData,"choosing the current source does not rebuild results")
  Same(p.list.scroll:GetVerticalScroll(),1607,"choosing the current source retains viewport")
  Same(p.result.item,selectedItem,"discovery retains selected identity")
  p.source:GetScript("OnClick")(p.source); opened:Close(); Pump()
  Same(p.list.scroll:GetVerticalScroll(),1607,"menu dismissal retains viewport")
  W.Window.SetMode("overview"); Pump(); W.Window.SetMode("advisor"); Pump()
  Same(p.list.scroll:GetVerticalScroll(),1607,"page return restores anchor and offset")
  p.search:SetText("Sample"); p.search:GetScript("OnTextChanged")(p.search); Pump()
  Same(p.list.scroll:GetVerticalScroll(),0,"intentional search resets viewport")
  p.list.scroll:SetVerticalScroll(647); p.list:Layout()
  g.names[1010]="Sample renamed"
  W.UI.Advisor.ItemReady(1010,true); W.Window.Render(); Pump()
  Same(p.list.scroll:GetVerticalScroll(),647,"active search preserves viewport after metadata update")
  Choose(p.category,"Trade Goods"); Pump()
  Same(p.list.scroll:GetVerticalScroll(),0,"intentional category resets viewport")
  p.list.scroll:SetVerticalScroll(707); p.list:Layout()
  W.UI.Advisor.Invalidate(); W.Window.Render(); Pump()
  Same(p.list.scroll:GetVerticalScroll(),707,"category-filtered refresh preserves viewport")
  Choose(p.category,"All categories"); Pump()
  p.search:SetText(""); p.search:GetScript("OnTextChanged")(p.search); Pump()
end
Check(#p.list.rows<20,"large discovery keeps a bounded visible row pool")
-- Metadata may arrive during the identity-only slices, before row.info exists.
Choose(p.category,"Trade Goods"); Pump()
p.list.scroll:SetVerticalScroll(831); p.list:Layout()
W.UI.Advisor.Invalidate(); W.Window.Render()
W.UI.Advisor.ItemReady(1010,true); Pump()
Same(p.list.scroll:GetVerticalScroll(),831,"metadata during discovery retains category-filtered viewport")
Same(#p.list.data,3002,"late metadata keeps the category result set complete")
Choose(p.category,"All categories"); Pump()
p.auctionable:GetScript("OnClick")(p.auctionable); Pump()
p.list.scroll:SetVerticalScroll(913); p.list:Layout()
W.UI.Advisor.Invalidate(); W.Window.Render()
W.UI.Advisor.ItemReady(1010,true); Pump()
Same(p.list.scroll:GetVerticalScroll(),913,"metadata during discovery retains auctionable-filtered viewport")
W.Window.Hide(); Pump()
print("advisor UI: OK")
-- Reuse the recording client for the opt-in Advisor benchmark; ordinary assertions above are unchanged.
return { client = c, workshop = W, page = p, game = g, pump = Pump, choose = Choose }
