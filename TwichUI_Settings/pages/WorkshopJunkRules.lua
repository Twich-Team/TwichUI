-- Bounded plain-language All/Any rules, following the settings kit used by
-- Reminders and Magic Inventory. Templates are added disabled for review.
local R=TwichUI
local P={}
R.WorkshopJunkRulesSettings=P
local K=R.SettingsKit
local arts={}
for kind,name in pairs({gear="sword-and-shield",materials="cloth-bolts",recipes="sealed-scroll",consumables="bread-and-tankard",other="leather-backpack"}) do
    arts[kind]=R.PATH.."media\\npcs\\"..name.."-small"
end
local templates={{"poor","Poor-quality gear"},{"nonupgrade","Uncommon or lower, not an upgrade"},
 {"materials","Vendor-recommended materials"},{"recipes","Common recipes"},{"custom","Custom rule"}}
local chosen="poor"
local function L() return R.WorkshopLauncher end
local function Rule(i) return L().JunkRules()[i] end
function P.Build()
    K.Status("How rules combine",function() return "Any enabled rule may match" end,function()
        return "Each rule targets one item type and combines its conditions with All or Any. Unknown requested facts never match. The Advisor must still recommend Vendor; Never mark protections always win."
    end)
    K.Choice("workshopJunkTemplate","Rule template","Templates start disabled; review before enabling.",K.STRING,"poor",
        function() return chosen end,function(v) chosen=v end,templates)
    K.Button("New rule","Add from template",function()
        local rows=L().JunkRules()
        if not L().JunkTemplate(#rows+1,chosen) then R.Print("Junk rules: maximum eight rules, or saved rules are unavailable.") end
        K.RefreshOverview()
    end)
    for i=1,8 do
        local index=i
        local header=K.Header("Marking rule "..i,"All rules still require a Vendor recommendation. A missing fact is never treated as No.")
        K.Accent(header,arts[(Rule(index) or {}).kind] or arts.other)
        header:AddShownPredicate(function() return Rule(index)~=nil end)
        local function Decorate(row)
            row:AddShownPredicate(function() return Rule(index)~=nil end)
            return row
        end
        Decorate(K.ProxyToggle("junkRule"..i.."on","Enable rule "..i,"Enable only after reviewing its conditions.",false,
            function() local r=Rule(index);return r and r.on or false end,
            function(v) L().SetJunkRule(index,"on",v);K.RefreshOverview() end))
        local function Choice(key,label,values,default,tip)
            Decorate(K.Choice("junkRule"..i..key,label,tip or "Combine with this rule's other conditions.",K.STRING,default,
                function() local r=Rule(index);return tostring(r and r[key] or default) end,
                function(v) L().SetJunkRule(index,key,key:find("quality") and tonumber(v) or v);K.RefreshOverview() end,values))
        end
        Choice("kind","Item type",{{"gear","Gear"},{"materials","Trade goods / reagents"},{"recipes","Recipes"},{"consumables","Consumables"},{"other","Other items"}},"gear")
        -- An item illustration accompanies every rule, using the category's native art.
        K.Status("Rule "..i.." item type",function()
            local r=Rule(index)
            local view=R.SettingsUI and R.SettingsUI.View("workshop")
            for _,section in ipairs(view and view.sections or {}) do
                if r and section.header==header and section.glyph then section.glyph:SetTexture(arts[r.kind]) end
            end
            return r and r.kind or ""
        end):AddShownPredicate(function() return Rule(index)~=nil end)
        Choice("match","Combine conditions",{{"all","All conditions (AND)"},{"any","Any condition (OR)"}},"all")
        local qualities={{"0","Poor"},{"1","Common"},{"2","Uncommon"},{"3","Rare"},{"4","Epic"},{"5","Legendary"}}
        Choice("qualityMin","Quality at least",qualities,"0")
        Choice("qualityMax","Quality at most",qualities,"5")
        local states={{"any","Do not check"},{"yes","Yes"},{"no","No"}}
        Choice("wearable","Gear: wearable now",states,"any","Native bag-tooltip requirements, including class, proficiency and level. Unknown blocks matching.")
        Choice("upgrade","Gear: estimated upgrade",states,"any","Uses TwichUI gear upgrade hints, not sale-price advice. Unknown comparisons block matching.")
        Choice("classReagent","Known reagent for my class",states,"any","Uses Restock's verified class suggestions. Unlisted items are unknown, not proven irrelevant.")
        Choice("profession","Used by my remembered recipes",states,"any","Materials in this character's remembered profession recipes. Unlisted materials are unknown, not proven irrelevant; refresh professions to add knowledge.")
        Decorate(K.Button("Remove rule "..i,"Remove",function() L().RemoveJunkRule(index);K.RefreshOverview() end))
        Decorate(K.Button("Reset rule "..i,"Use selected template",function() L().JunkTemplate(index,chosen);K.RefreshOverview() end))
    end
end
