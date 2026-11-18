-- Synthetic presentation client with real Workshop modules and recording frames.
dofile(TESTS .. "mi_mock.lua")
local Press = dofile(TESTS .. "press.lua")
local options = rawget(_G, "AUCTION_MOCK_OPTIONS") or {}
AUCTION_MOCK_OPTIONS = nil
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
      fr.SetFrameStrata = function(s, v) s.strata = v end
      fr.GetFrameStrata = function(s) return s.strata or "MEDIUM" end
      fr.GetParent = function(s) return s.parent end
      fr.SetScale = function(s, v) s.scale = v end
      fr.GetScale = function(s) return s.scale or 1 end
      fr.GetEffectiveScale = function(s) return s:GetScale() * (s.parent and s.parent:GetEffectiveScale() or 1) end
      fr.GetLeft = function(s) return (cl.UIParent:GetWidth()/s:GetScale()-s:GetWidth())/2 end
      fr.GetBottom = function(s) return (cl.UIParent:GetHeight()/s:GetScale()-s:GetHeight())/2 end
      fr.GetRight = function(s) return s:GetLeft()+s:GetWidth() end
      fr.GetTop = function(s) return s:GetBottom()+s:GetHeight() end
      fr.SetMotionScriptsWhileDisabled = function() end
      fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end t.SetAtlas = function(x,v) x.atlas=v end return t end
      fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end t.SetDirection = function() error("FontString has no SetDirection API") end return t end
      Press.Instrument(fr, name)   -- last, so it replaces the no-op EnableMouse above with one that records
      if cl.testFrames then cl.testFrames[#cl.testFrames+1] = fr end
      if name then cl[name] = fr end
      return fr
    end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.UIParent.GetParent = function() return nil end
    cl.UIParent.GetLeft = function() return 0 end
    cl.UIParent.GetBottom = function() return 0 end
    cl.UIParent.GetRight = function(s) return s:GetWidth() end
    cl.UIParent.GetTop = function(s) return s:GetHeight() end
    cl.GameTooltip = MIFake("GameTooltip")
    cl.UISpecialFrames = {}
    cl.testFrames = {}
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = {},
})
c.TwichUIDB = c.TwichUIDB or {}
local R = c.TwichUI
local host = assert(loadfile(ROOT .. "auction/Host.lua")); setfenv(host, c); host()

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

if options.preview then R.WorkshopLauncher = { previewLoading = true } end
if options.experimentalOff then
    c.TwichUIDB.ui = c.TwichUIDB.ui or {}
    c.TwichUIDB.ui.workshopEnabled = false
    local chunk = assert(loadfile(ROOT .. "WorkshopLauncher.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
    c.Enum.TooltipDataType = { Item = 1 }
    c.tooltipCallbacks = {}
    c.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) c.tooltipCallbacks[#c.tooltipCallbacks + 1] = fn end }
end
if options.native then
    c.AuctionHouseFrame = c.CreateFrame("Frame", "AuctionHouseFrame", c.UIParent)
    c.AuctionHouseFrame:SetSize(800,500); c.AuctionHouseFrame:SetPoint("CENTER"); c.AuctionHouseFrame:Show()
    c.nativeHooks = 0
    local hook = c.AuctionHouseFrame.HookScript
    c.AuctionHouseFrame.HookScript = function(self,...)
        c.nativeHooks = c.nativeHooks + 1
        return hook(self,...)
    end
end
local toc = assert(io.open(REPO .. "TwichUI_Workshop/TwichUI_Workshop.toc"))
for line in toc:lines() do
  if line:match("%.lua$") then
    local chunk = assert(loadfile(REPO .. "TwichUI_Workshop/" .. line)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
end
toc:close()
return c, g, Press
