-- Presentation only. Enum values 0..8 are pinned to Forever's
-- Blizzard_APIDocumentationGenerated/ItemQualitiesDocumentation.lua.
-- RGB values below are synthetic provider results, never item/name heuristics.
local env = { TwichUI = {} }; setmetatable(env, { __index = _G })
for _, file in ipairs({ "Data.lua", "Style.lua" }) do
    local f = assert(loadfile(REPO .. "TwichUI_Workshop/" .. file)); setfenv(f, env); f()
end
local UI = env.TwichUI.Workshop.UI
UI.K = { text = { .9, .85, .8 } }
local fs = { SetTextColor = function(self, r, g, b) self.r,self.g,self.b = r,g,b end }
local function check(q, r, g, b)
    UI.ItemQuality(fs, q)
    assert(fs.r == r and fs.g == g and fs.b == b, "quality/reset mismatch: " .. tostring(q))
end
local calls = 0
env.C_Item = { GetItemQualityColor = function(q) calls=calls+1; return q/16, .5, .75 end }
for q = 0, 8 do check(q, q/16, .5, .75) end
check(nil, .9, .85, .8); check(false, .9, .85, .8)
check(-1, .9, .85, .8); check(9, .9, .85, .8); check(2.5, .9, .85, .8)
assert(calls == 9, "unknown values never reach quality API")
-- A delayed metadata arrival recolors the same font string, then a recycled
-- unknown row resets it. Common is distinct from unknown.
check(nil, .9,.85,.8); check(1, 1/16,.5,.75); check(4, .25,.5,.75); check(nil,.9,.85,.8)
env.C_Item.GetItemQualityColor = function() error("unavailable") end
env.ITEM_QUALITY_COLORS = { [0]={r=.1,g=.2,b=.3}, [4]={r=.5,g=.25,b=.75} }
check(0,.1,.2,.3); check(4,.5,.25,.75); check(2,.9,.85,.8)
assert(UI.QualityText("Material",4)=="|cff8040bfMaterial|r")
assert("20 x " .. UI.QualityText("Material",4) .. " · missing" == "20 x |cff8040bfMaterial|r · missing")
assert(UI.QualityText("Unknown",nil)=="Unknown")
env.ITEM_QUALITY_COLORS[4]={r=2,g=0,b=0}; check(4,.9,.85,.8)
-- Secret metadata is never compared or passed to the API.
local secret={};env.issecretvalue=function(v) return v==secret end
check(secret,.9,.85,.8)
print("PASSED Workshop item-quality presentation")
