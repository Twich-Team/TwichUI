-- A rule list and one transactional draft, following Loot Rolls' split editor
-- and Magic Inventory/Reminders' explicit Save/Cancel condition editing.
local R=TwichUI
local P={}
R.WorkshopJunkRulesSettings=P
local f,draft,index,baseline
local ROWS,HEIGHT=8,700
local kinds={{"gear","Gear","sword-and-shield"},{"materials","Materials","cloth-bolts"},
 {"recipes","Recipes","sealed-scroll"},{"consumables","Supplies","bread-and-tankard"},{"other","Other","leather-backpack"}}
local labels,art={},{}
for _,k in ipairs(kinds) do labels[k[1]]=k[2];art[k[1]]=R.PATH.."media\\npcs\\"..k[3].."-small" end
local conditions={{"quality","Quality range"},{"wearable","Wearable now"},{"upgrade","Estimated gear upgrade"},
 {"classReagent","Known reagent for my class"},{"profession","Used by my remembered recipes"}}
local qualities={"Poor","Common","Uncommon","Rare","Epic","Legendary"}
local templates={{value="poor",label="Poor-quality gear"},{value="nonupgrade",label="Uncommon or lower, not an upgrade"},
 {value="materials",label="Vendor-recommended materials"},{value="recipes",label="Common recipes"},{value="custom",label="Custom rule"}}
local function L() return R.WorkshopLauncher end
local function Copy(r) local c={};for k,v in pairs(r) do c[k]=v end;return c end
local function Has(r,key) return key=="quality" and (r.qualityMin>0 or r.qualityMax<5) or key~="quality" and r[key]~="any" end
function P.Draft() return draft and Copy(draft) end
function P.Height() return HEIGHT end
function P.Summary(r)
    if not r then return "Choose a rule, or start from a template." end
    local parts={}
    if Has(r,"quality") then parts[#parts+1]=(qualities[r.qualityMin+1] or "?").." to "..(qualities[r.qualityMax+1] or "?") end
    for _,c in ipairs(conditions) do
        if c[1]~="quality" and Has(r,c[1]) then parts[#parts+1]=c[2]..": "..(r[c[1]]=="yes" and "Yes" or "No") end
    end
    return "Mark "..(labels[r.kind] or "items").." when the Advisor recommends Vendor"..
        (#parts>0 and (" and ("..table.concat(parts,r.match=="any" and " OR " or " AND ")..")") or "")..". Never mark protections always win."
end
local function Say(s) if f then f.note:SetText(s or "") end end
function P.Edit(i)
    if draft then Say("Save or cancel this draft before choosing another rule.");return false end
    local rows,held=L().JunkRules();if held or not rows[i] then return false end
    index,baseline,draft=i,rows,Copy(rows[i]);P.Refresh();return true
end
function P.New(template)
    if draft then Say("Save or cancel this draft before starting another.");return false end
    local rows,held=L().JunkRules();if held or #rows>=8 then Say("Eight rules maximum, or saved rules unavailable.");return false end
    local t={poor={kind="gear",qualityMax=0,name="Poor-quality gear"},
        nonupgrade={kind="gear",qualityMax=2,upgrade="no",name="Not an upgrade"},
        materials={kind="materials",name="Vendor materials"},recipes={kind="recipes",qualityMax=1,name="Common recipes"},
        custom={kind="other",name="New rule"}}
    local v=t[template];if not v then return false end
    index,baseline=#rows+1,rows
    draft={kind=v.kind,name=v.name,on=false,match="all",qualityMin=0,qualityMax=v.qualityMax or 5,
        wearable="any",upgrade=v.upgrade or "any",classReagent="any",profession="any"}
    P.Refresh();return true
end
function P.Set(key,value)
    if not draft then return false end
    draft[key]=value;P.Refresh();return true
end
function P.Add(key)
    if not draft then return end
    if key=="quality" then draft.qualityMin,draft.qualityMax=0,2
    else for _,c in ipairs(conditions) do if c[1]==key then draft[key]="yes" end end end
    P.Refresh()
end
function P.Remove(key)
    if not draft then return end
    if key=="quality" then draft.qualityMin,draft.qualityMax=0,5 else draft[key]="any" end
    P.Refresh()
end
function P.Cancel() draft,index,baseline=nil,nil,nil;if f then f.name:ClearFocus() end;P.Refresh() end
function P.Save()
    if not draft then return false end
    if f then draft.name=f.name:GetText() end
    if not L().SaveJunkRule(index,draft,baseline) then Say("Could not save: check the quality range, name, or changed profile/rules. Cancel and reopen if saved data changed.");return false end
    P.Cancel();Say("Saved. Only enabled rules can mark Vendor recommendations.");return true
end
local function Place(o,parent,x,y,w,h)
    o:ClearAllPoints();o:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    if w then o:SetWidth(w) end;if h then o:SetHeight(h) end
end
function P.Refresh()
    if not f then return end
    local G=R.SettingsWidgets
    local width=math.max(644,f:GetWidth());local right=width-222
    f.list:SetSize(208,HEIGHT-8);Place(f.editor,f,220,0,right,HEIGHT-8)
    local rows,held=L().JunkRules()
    f.count:SetText(held and "Saved rules unavailable" or #rows.." / 8 rules")
    for i,row in ipairs(f.rows) do
        local r=rows[i];row:SetShown(r~=nil)
        if r then
            row.icon:SetTexture(art[r.kind]);row.name:SetText(r.name or labels[r.kind])
            row.state:SetText((r.on and "On" or "Off").." · "..(r.match=="any" and "Any" or "All"))
        end
        row:SetEnabled(not draft)
    end
    f.new:SetEnabled(not draft and not held and #rows<8)
    f.parts:SetShown(draft~=nil);f.empty:SetShown(draft==nil)
    if not draft then return end
    local e=f.parts;Place(e,f.editor,12,12,right-24,HEIGHT-32)
    if not f.name:HasFocus() then f.name:SetText(draft.name or labels[draft.kind]) end
    f.name:SetWidth(right-116);f.on:SetChecked(draft.on)
    local tileW=math.floor((right-48)/5)
    for i,b in ipairs(f.kinds) do
        Place(b,e,(i-1)*(tileW+6),44,tileW,68)
        b:SetAlpha(draft.kind==kinds[i][1] and 1 or 0.5)
    end
    f.summary:SetText(P.Summary(draft));f.summary:SetWidth(right-48)
    f.all.text:SetText(draft.match=="all" and "● All of these" or "All of these")
    f.any.text:SetText(draft.match=="any" and "● Any of these" or "Any of these")
    local y=230
    for _,c in ipairs(conditions) do
        local card=f.cards[c[1]];local show=Has(draft,c[1]);card:SetShown(show)
        if show then
            Place(card,e,0,y,right-48,58);y=y+64
            card.remove:ClearAllPoints();card.remove:SetPoint("TOPRIGHT",-6,-6)
            if c[1]=="quality" then
                card.low:SetValue(draft.qualityMin,qualities[draft.qualityMin+1]);card.high:SetValue(draft.qualityMax,qualities[draft.qualityMax+1])
            else card.value:SetValue(draft[c[1]],draft[c[1]]=="yes" and "Yes" or "No") end
        end
    end
    Place(f.add,e,0,y,150,26)
    Place(f.save,e,0,y+40,94,30);Place(f.cancel,e,102,y+40,94,30);Place(f.delete,e,204,y+40,100,30)
    f.delete:SetEnabled(index<=#rows)
end
local function Build()
    local G,M=R.SettingsWidgets,R.SettingsMaterial
    f=CreateFrame("Frame",nil,UIParent);f:SetSize(644,HEIGHT);f:Hide()
    f.list=CreateFrame("Frame",nil,f,"BackdropTemplate");M.PanelFace(f.list,"card");Place(f.list,f,0,0)
    f.editor=CreateFrame("Frame",nil,f,"BackdropTemplate");M.PanelFace(f.editor,"card")
    local title=G.Text(f.list,"heading");Place(title,f.list,12,12);title:SetText("Your marking rules")
    f.count=G.Text(f.list,"small");Place(f.count,f.list,12,38)
    f.new=G.Button(f.list,"+ New rule",180,"secondary",function()
        G.ContextMenu(f.new,templates,function(v) P.New(v) end)
    end);Place(f.new,f.list,12,64)
    f.rows={}
    for i=1,ROWS do
        local n=i
        local b=G.Button(f.list,"",184,"secondary",function() P.Edit(n) end);Place(b,f.list,12,104+(i-1)*58,184,52)
        b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetSize(32,32);b.icon:SetPoint("LEFT",6,0)
        b.name=G.Text(b,"body");Place(b.name,b,44,7,132,18);b.name:SetMaxLines(1)
        b.state=G.Text(b,"small");Place(b.state,b,44,28,132,16);f.rows[i]=b
    end
    f.note=G.Text(f.list,"small");Place(f.note,f.list,12,586,184,86)
    f.note:SetText("Any enabled rule may match. Unknown requested facts never match. Nothing here sells an item.")
    f.empty=G.Text(f.editor,"body");Place(f.empty,f.editor,18,20,360,100);f.empty:SetText("Choose a rule on the left, or start with a template.\n\nEdit one draft at a time. Save applies it; Cancel keeps the saved rule.")
    f.parts=CreateFrame("Frame",nil,f.editor)
    local e=f.parts
    f.name=G.EditBox(e,290,26);Place(f.name,e,0,0);f.name:SetMaxLetters(60)
    f.name:SetScript("OnTextChanged",function(self) if draft then draft.name=self:GetText();f.summary:SetText(P.Summary(draft)) end end)
    f.name:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    f.on=G.Checkbox(e,function(on) if draft then draft.on=on end end);f.on:SetPoint("TOPRIGHT",-38,0)
    local on=G.Text(e,"small");on:SetPoint("LEFT",f.on,"RIGHT",4,0);on:SetText("On")
    f.kinds={}
    for i,k in ipairs(kinds) do
        local kind=k[1]
        local b=G.Button(e,"",70,"secondary",function() P.Set("kind",kind) end)
        local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(32,32);icon:SetPoint("TOP",0,-5);icon:SetTexture(art[kind])
        local text=G.Text(b,"small");text:SetPoint("BOTTOM",0,5);text:SetText(k[2]);f.kinds[i]=b
    end
    f.summary=G.Text(e,"small");Place(f.summary,e,0,122,360,64)
    f.all=G.Button(e,"All of these",150,"secondary",function() P.Set("match","all") end);Place(f.all,e,0,192)
    f.any=G.Button(e,"Any of these",150,"secondary",function() P.Set("match","any") end);Place(f.any,e,158,192)
    f.cards={}
    for _,c in ipairs(conditions) do
        local key=c[1]
        local card=CreateFrame("Frame",nil,e,"BackdropTemplate");M.PanelFace(card,"canvas")
        local text=G.Text(card,"body");Place(text,card,8,6);text:SetText(c[2])
        card.remove=G.Button(card,"×",24,"secondary",function() P.Remove(key) end)
        if key=="quality" then
            local choices={};for q,name in ipairs(qualities) do choices[#choices+1]={value=q-1,label=name} end
            card.low=G.Dropdown(card,126,function(v) P.Set("qualityMin",v) end);card.low:SetChoices(choices);Place(card.low,card,8,28)
            card.high=G.Dropdown(card,126,function(v) P.Set("qualityMax",v) end);card.high:SetChoices(choices);Place(card.high,card,144,28)
        else
            card.value=G.Dropdown(card,160,function(v) P.Set(key,v) end);card.value:SetChoices({{value="yes",label="Yes"},{value="no",label="No"}});Place(card.value,card,8,28)
            R.Interact.Tip(card,c[2],key=="profession" and "Only remembered recipes provide positive evidence. Unlisted is unknown, not No." or key=="classReagent" and "Only known class reagent suggestions provide positive evidence. Unlisted is unknown, not No." or key=="upgrade" and "Uses TwichUI gear estimates. Failed or unsupported comparisons are unknown, not No." or "Native tooltip requirements include class, proficiency and level. Unknown blocks matching.")
        end
        f.cards[key]=card
    end
    f.add=G.Button(e,"+ Add condition",150,"secondary",function()
        if not draft then return end
        local choices={}
        for _,c in ipairs(conditions) do if not Has(draft,c[1]) then choices[#choices+1]={value=c[1],label=c[2]} end end
        G.ContextMenu(f.add,choices,P.Add)
    end)
    f.save=G.Button(e,"Save rule",94,"primary",P.Save)
    f.cancel=G.Button(e,"Cancel",94,"secondary",P.Cancel)
    f.delete=G.Button(e,"Delete rule",100,"danger",function()
        -- Deletion first discards this draft; only the saved rule is removed.
        if index and L().RemoveJunkRule(index,baseline) then P.Cancel();Say("Rule removed.") else Say("Saved rules changed. Cancel and reopen before deleting.") end
    end)
    f:SetScript("OnShow",P.Refresh)
    f:SetScript("OnHide",function() draft,index,baseline=nil,nil,nil;f.name:ClearFocus() end)
    f:SetScript("OnSizeChanged",P.Refresh)
end
function P.Frame() if not f then Build() end;return f end
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views","workshop-junk-draft",P.Cancel) end
