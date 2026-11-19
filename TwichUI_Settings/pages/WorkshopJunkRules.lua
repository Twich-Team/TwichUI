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
local function T() return L().JunkTree end
local function Copy(r)
    local c={};for k,v in pairs(r) do c[k]=k=="tree" and T().Copy(v) or v end;return c
end
local target
function P.Root() return draft and draft.tree end
function P.Draft() return draft and Copy(draft) end
function P.Height() return HEIGHT end
local function Words(n)
    if n.type=="group" then
        local parts={};for _,c in ipairs(n.children) do parts[#parts+1]=Words(c) end
        return #parts==0 and "Empty group (never matches)" or "("..table.concat(parts,n.match=="any" and " OR " or " AND ")..")"
    elseif n.type=="kind" then return labels[n.value] or "Item type"
    elseif n.type=="quality" then return (qualities[n.min+1] or "?").." to "..(qualities[n.max+1] or "?") end
    for _,c in ipairs(conditions) do if c[1]==n.type then return c[2]..": "..(n.value and "Yes" or "No") end end
    return "Unknown condition"
end
function P.Summary(r) return r and ("Advisor: Vendor AND "..Words(r.tree or T().FromRule(r))..". Never mark protections always win.") or "Choose a rule or template." end
local function Say(s) if f then f.note:SetText(s or "") end end
function P.Edit(i)
    if draft then Say("Save or cancel the current draft first.");return false end
    local rows,held=L().JunkRules();if held or not rows[i] then return false end
    index,baseline,draft=i,rows,Copy(rows[i]);draft.tree=T().FromRule(draft);target=draft.tree
    P.Refresh();return true
end
function P.New(template)
    if draft then Say("Save or cancel the current draft first.");return false end
    local rows,held=L().JunkRules();if held or #rows>=8 then Say("Eight rules maximum, or saved rules unavailable.");return false end
    local types={poor={kind="gear",qualityMax=0,name="Poor-quality gear"},nonupgrade={kind="gear",qualityMax=2,upgrade="no",name="Not an upgrade"},materials={kind="materials",name="Vendor materials"},recipes={kind="recipes",qualityMax=1,name="Common recipes"},custom={kind="other",name="New rule"}}
    local v=types[template];if not v then return false end
    index,baseline=#rows+1,rows
    draft={kind=v.kind,name=v.name,on=false,match="all",qualityMin=0,qualityMax=v.qualityMax or 5,wearable="any",upgrade=v.upgrade or "any",classReagent="any",profession="any"}
    draft.tree=template=="custom" and {type="group",match="all",children={}} or T().FromRule(draft)
    target=draft.tree;P.Refresh();return true
end
local function First(node,key)
    if node.type==key then return node end
    for _,c in ipairs(node.children or {}) do local found=First(c,key);if found then return found end end
end
function P.Set(key,value)
    if not draft then return false end
    draft[key]=value
    if key=="match" then draft.tree.match=value
    elseif key=="kind" then local n=First(draft.tree,"kind");if n then n.value=value end
    elseif key=="qualityMin" or key=="qualityMax" then local n=First(draft.tree,"quality");if n then n[key=="qualityMin" and "min" or "max"]=value end
    else local n=First(draft.tree,key);if n then n.value=value=="yes" end end
    P.Refresh();return true
end
local function Make(key)
    if key=="all" or key=="any" then return {type="group",match=key,children={}} end
    if key=="kind" then return {type="kind",value="gear"} end
    if key=="quality" then return {type="quality",min=0,max=2} end
    for _,c in ipairs(conditions) do if c[1]==key then return {type=key,value=true} end end
end
function P.Insert(key,group,slot)
    if not draft then return false end
    group=group or target or draft.tree
    if not T().Contains(draft.tree,group) or group.type~="group" then return false end
    local n=Make(key);if not n then return false end
    slot=slot or #group.children+1
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>#group.children+1 then return false end
    table.insert(group.children,slot,n)
    if not T().Copy(draft.tree) then table.remove(group.children,slot);Say("Maximum 32 nodes and four levels. Move a group higher or remove a condition.");return false end
    if n.type=="group" then target=n end
    P.Refresh();return n
end
function P.Add(key) return P.Insert(key) end
function P.Move(node,group,slot)
    if not draft then return false end
    local ok=T().Move(draft.tree,node,group,slot,true)
    if ok then P.Refresh() end;return ok
end
function P.RemoveNode(node)
    if not draft or node==draft.tree then return false end
    local parent,at=T().Find(draft.tree,node);if not parent then return false end
    table.remove(parent.children,at);if T().Contains(node,target) then target=parent end
    P.Refresh();return true
end
function P.Remove(key) if draft then local node=First(draft.tree,key);if node then return P.RemoveNode(node) end end end
function P.Cancel()
    if f and f.drag then f.drag:Cancel() end
    draft,index,baseline,target=nil,nil,nil,nil
    if f then f.name:ClearFocus() end;P.Refresh()
end
function P.Save()
    if not draft then return false end
    if f then draft.name=f.name:GetText() end
    if not L().SaveJunkRule(index,draft,baseline) then Say("Cannot save: invalid conditions, range or name, or saved rules changed. Cancel and reopen if necessary.");return false end
    P.Cancel();Say("Rule saved. Only enabled rules may mark Vendor recommendations.");return true
end
local function Place(o,parent,x,y,w,h)
    o:ClearAllPoints();o:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    if w then o:SetWidth(w) end;if h then o:SetHeight(h) end
end
local function Menu(group,owner)
    local choices={{value="kind",label="Item type"}}
    for _,c in ipairs(conditions) do choices[#choices+1]={value=c[1],label=c[2]} end
    choices[#choices+1]={value="all",label="AND group: all of these"};choices[#choices+1]={value="any",label="OR group: any of these"}
    R.SettingsWidgets.ContextMenu(owner,choices,function(key) P.Insert(key,group) end)
end
local function Card(i)
    if f.nodes[i] then return f.nodes[i] end
    local G,M=R.SettingsWidgets,R.SettingsMaterial
    local c=CreateFrame("Frame",nil,f.content,"BackdropTemplate");M.PanelFace(c,"canvas")
    c.grip=G.Button(c,"≡",24,"secondary",function() end);Place(c.grip,c,4,4)
    f.drag:Bind(c.grip,function() return c.node and {raw=c.node},c.node and Words(c.node) or "Condition" end)
    c.title=G.Text(c,"small");Place(c.title,c,36,6)
    c.remove=G.Button(c,"×",24,"secondary",function() P.RemoveNode(c.node) end);c.remove:SetPoint("TOPRIGHT",-4,-4)
    c.plus=G.Button(c,"+",24,"secondary",function() target=c.node;Menu(c.node,c.plus) end);c.plus:SetPoint("TOPRIGHT",-34,-4)
    c.select=G.Button(c,"Add here",76,"secondary",function() target=c.node;Say("Conditions you click in the palette will be added to this group.") end);Place(c.select,c,36,28)
    c.value=G.Dropdown(c,180,function(v)
        if c.node.type=="group" then c.node.match=v;c.node.strict=nil else c.node.value=v end;P.Refresh()
    end);Place(c.value,c,118,28)
    local qs={};for q,label in ipairs(qualities) do qs[#qs+1]={value=q-1,label=label} end
    c.low=G.Dropdown(c,126,function(v) c.node.min=v;P.Refresh() end);c.low:SetChoices(qs);Place(c.low,c,36,28)
    c.high=G.Dropdown(c,126,function(v) c.node.max=v;P.Refresh() end);c.high:SetChoices(qs);Place(c.high,c,170,28)
    c.actions=G.Button(c,"Move",56,"secondary",function()
        local choices={};local groups={}
        local function Walk(n,depth)
            if n.type=="group" then
                if T().Move(draft.tree,c.node,n,#n.children+1,false) then groups[#groups+1]=n;choices[#choices+1]={value=#groups,label=string.rep("  ",depth)..(n==draft.tree and "Top level" or n.match=="all" and "AND group" or "OR group")} end
                for _,child in ipairs(n.children) do Walk(child,depth+1) end
            end
        end
        Walk(draft.tree,0);R.SettingsWidgets.ContextMenu(c.actions,choices,function(v) local g=groups[v];if g then P.Move(c.node,g,#g.children+1) end end)
    end);c.actions:SetPoint("TOPRIGHT",-64,-4)
    function c:SetDropHot(on) self:SetAlpha(on and 0.75 or 1) end
    f.nodes[i]=c;return c
end
function P.Refresh()
    if not f then return end
    local width=math.max(644,f:GetWidth());local right=width-222
    f.list:SetSize(208,HEIGHT-8);Place(f.editor,f,220,0,right,HEIGHT-8)
    local rows,held=L().JunkRules()
    f.count:SetText(draft and "Drag or click a condition" or held and "Rules unavailable" or #rows.." / 8 rules")
    for i,row in ipairs(f.rows) do
        local r=rows[i];row:SetShown(r~=nil and not draft)
        if r then row.icon:SetTexture(art[r.kind]);row.name:SetText(r.name or labels[r.kind]);row.state:SetText(r.on and "On" or "Off") end
    end
    for _,button in ipairs(f.palette) do button:SetShown(draft~=nil) end
    f.new:SetEnabled(not draft and not held and #rows<8)
    f.parts:SetShown(draft~=nil);f.empty:SetShown(draft==nil)
    f.drag:ClearTargets();for _,c in ipairs(f.nodes) do c:Hide();c.node=nil end
    if not draft then return end
    local e=f.parts;Place(e,f.editor,12,12,right-24,HEIGHT-32)
    if not f.name:HasFocus() then f.name:SetText(draft.name or "New rule") end
    f.name:SetWidth(right-116);f.on:SetChecked(draft.on)
    f.summary:SetText(P.Summary(draft));f.summary:SetWidth(right-48)
    Place(f.scroll,e,0,130,right-44,428);f.content:SetWidth(right-58)
    local used=0
    local function Draw(n,parent,at,depth,y)
        used=used+1;local c=Card(used);c.node=n;c:Show()
        local x=depth*14;local w=right-62-x
        Place(c,f.content,x,y,w,62)
        c.title:SetText(n.type=="group" and (n==target and "Selected group · " or "")..(n.match=="all" and "AND · All of these" or "OR · Any of these") or n.type=="kind" and "Item type" or n.type=="quality" and "Quality range" or Words(n))
        c.title:SetWidth(math.max(70,w-174));c.grip:SetShown(parent~=nil);c.remove:SetShown(parent~=nil);c.actions:SetShown(parent~=nil)
        c.plus:SetShown(n.type=="group");c.select:SetShown(n.type=="group")
        c.low:SetShown(n.type=="quality");c.high:SetShown(n.type=="quality");c.value:SetShown(n.type~="quality")
        if n.type=="group" then c.value:SetChoices({{value="all",label="All (AND)"},{value="any",label="Any (OR)"}});c.value:SetValue(n.match,n.match=="all" and "All (AND)" or "Any (OR)")
        elseif n.type=="kind" then local choices={};for _,k in ipairs(kinds) do choices[#choices+1]={value=k[1],label=k[2]} end;c.value:SetChoices(choices);c.value:SetValue(n.value,labels[n.value])
        elseif n.type=="quality" then c.low:SetValue(n.min,qualities[n.min+1]);c.high:SetValue(n.max,qualities[n.max+1])
        else c.value:SetChoices({{value=true,label="Yes"},{value=false,label="No"}});c.value:SetValue(n.value,n.value and "Yes" or "No") end
        if parent then f.drag:Row(c,parent,at,n.type=="group") end
        local bottom=y+66
        for i,child in ipairs(n.children or {}) do bottom=Draw(child,n,i,depth+1,bottom) end
        if n.type=="group" then
            if #n.children==0 then bottom=bottom+22 end
            c:SetHeight(bottom-y+4);f.drag:Group(c,n,#n.children,depth)
            bottom=bottom+10
        end
        return bottom
    end
    local h=Draw(draft.tree,nil,nil,0,2);f.content:SetHeight(h+8)
    Place(f.save,e,0,574,94,30);Place(f.cancel,e,102,574,94,30);Place(f.delete,e,204,574,100,30)
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
    f.note:SetText("Drag conditions or groups into the tree. Use each group’s + or Add here to build nested AND/OR logic. Empty groups never match. Nothing here sells an item.")
    f.empty=G.Text(f.editor,"body");Place(f.empty,f.editor,18,20,360,100);f.empty:SetText("Choose a rule on the left, or start with a template.\n\nEdit one draft at a time. Save applies it; Cancel keeps the saved rule.")
    f.parts=CreateFrame("Frame",nil,f.editor)
    local e=f.parts
    f.name=G.EditBox(e,290,26);Place(f.name,e,0,0);f.name:SetMaxLetters(60)
    f.name:SetScript("OnTextChanged",function(self) if draft then draft.name=self:GetText();f.summary:SetText(P.Summary(draft)) end end)
    f.name:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    f.on=G.Checkbox(e,function(on) if draft then draft.on=on end end);f.on:SetPoint("TOPRIGHT",-38,0)
    local on=G.Text(e,"small");on:SetPoint("LEFT",f.on,"RIGHT",4,0);on:SetText("On")
    f.summary=G.Text(e,"small");Place(f.summary,e,0,40,360,76)
    f.scroll,f.content=G.Scroll(e,360)
    f.nodes={}
    local function Validate(src,group,slot)
        if not draft or not group or group.type~="group" then return false end
        if src.raw then return T().Move(draft.tree,src.raw,group,slot,false) end
        local n=Make(src.entry);if not n then return false end
        table.insert(group.children,slot,n);local valid=T().Copy(draft.tree)~=nil;table.remove(group.children,slot);return valid
    end
    f.drag=R.RemindersRuleDrag.New(f.scroll,Validate,function(src,group,slot)
        if src.raw then P.Move(src.raw,group,slot) else P.Insert(src.entry,group,slot) end
    end)
    f.palette={}
    local entries={{"kind","Item type"},{"quality","Quality range"},{"wearable","Wearable now"},{"upgrade","Gear upgrade"},{"classReagent","Class reagent"},{"profession","Recipe material"},{"all","AND group"},{"any","OR group"}}
    for i,entry in ipairs(entries) do
        local key=entry[1]
        local button=G.Button(f.list,"≡  "..entry[2],184,"secondary",function() P.Insert(key) end)
        Place(button,f.list,12,104+(i-1)*48,184,40)
        f.drag:Bind(button,function() return {entry=key},entry[2] end)
        R.Interact.Tip(button,entry[2],"Drag into a group or onto a highlighted edge. Click to add to the selected group. Group + menus and Move menus also work without dragging.")
        f.palette[#f.palette+1]=button
    end
    f.save=G.Button(e,"Save rule",94,"primary",P.Save)
    f.cancel=G.Button(e,"Cancel",94,"secondary",P.Cancel)
    f.delete=G.Button(e,"Delete rule",100,"danger",function()
        -- Deletion first discards this draft; only the saved rule is removed.
        if index and L().RemoveJunkRule(index,baseline) then P.Cancel();Say("Rule removed.") else Say("Saved rules changed. Cancel and reopen before deleting.") end
    end)
    f:SetScript("OnShow",P.Refresh)
    f:SetScript("OnHide",function() f.drag:Cancel();draft,index,baseline,target=nil,nil,nil,nil;f.name:ClearFocus() end)
    f:SetScript("OnSizeChanged",P.Refresh)
end
function P.Frame() if not f then Build() end;return f end
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views","workshop-junk-draft",P.Cancel) end
