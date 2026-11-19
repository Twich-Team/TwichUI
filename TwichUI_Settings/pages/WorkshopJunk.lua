-- Settings-only picker. Records IDs, never moves, marks or sells an item.
local R = TwichUI
local P = {}
R.WorkshopJunkSettings = P
local f, mode, page = nil, "bags", 1
local WIDTH, HEIGHT, ROWS = 492, 558, 7
local function L() return R.WorkshopLauncher end
local function Plain(v) if not (issecretvalue and issecretvalue(v)) then return v end end
local function ID(v)
    v=Plain(v)
    return type(v)=="number" and v==v and v>=1 and v<=2147483647 and v%1==0 and v or nil
end
local function Info(id)
    local name,_,_,_,_,_,_,_,_,icon
    if C_Item and C_Item.GetItemInfo then name,_,_,_,_,_,_,_,_,icon=C_Item.GetItemInfo(id) end
    name,icon=Plain(name),Plain(icon)
    return type(name)=="string" and name or ("Item "..id),icon
end
-- Only called on explicit open/refresh or events while the picker is visible.
function P.Entries(source,query)
    local ids,seen,where={},{},{}
    local function Add(id,bag,slot)
        id=ID(id);if id and not seen[id] then seen[id]=true;ids[#ids+1]=id;where[id]={bag,slot} end
    end
    if source=="ignored" then
        for _,id in ipairs(L().JunkIgnoreList()) do Add(id) end
    elseif C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag=0,math.min(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4,10) do
            local slots=Plain(C_Container.GetContainerNumSlots(bag))
            if type(slots)=="number" then
                for slot=1,math.min(slots,200) do
                    local x=C_Container.GetContainerItemInfo(bag,slot)
                    if type(x)=="table" then Add(x.itemID,bag,slot) end
                end
            end
        end
    end
    local out={};query=(query or ""):lower()
    for _,id in ipairs(ids) do
        local name,icon=Info(id)
        if query=="" or (name.." "..id):lower():find(query,1,true) then
            out[#out+1]={id=id,name=name,icon=icon,ignored=L().JunkIgnored(id),fixed=id==211527,bag=where[id] and where[id][1],slot=where[id] and where[id][2]}
        end
    end
    table.sort(out,function(a,b) if a.name~=b.name then return a.name<b.name end;return a.id<b.id end)
    return out
end
function P.Shown() return f~=nil and f:IsShown() end
function P.Frame() return f end
function P.Close() if f then f:Hide() end end
function P.Refresh()
    if not P.Shown() then return end
    local entries=P.Entries(mode,f.search:GetText())
    local pages=math.max(1,math.ceil(#entries/ROWS));page=math.min(page,pages)
    f.count:SetText((mode=="bags" and "Bag items" or "Never mark").." · "..#entries.." · "..page.." / "..pages)
    f.prev:SetEnabled(page>1);f.next:SetEnabled(page<pages)
    for i,row in ipairs(f.rows) do
        local e=entries[(page-1)*ROWS+i];row.entry=e;row:SetShown(e~=nil)
        if e then
            row.name:SetText(e.name);row.id:SetText("Item "..e.id)
            row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.action.text:SetText(e.fixed and "Protected" or e.ignored and "Remove" or "Never mark")
            row.action:SetEnabled(not e.fixed)
        end
    end
    f.empty:SetShown(#entries==0)
    f.empty:SetText(mode=="bags" and "No matching bag items." or "No matching ignored items. Cozy Sleeping Bag is always protected.")
end
function P.Ignore(id,on)
    if id==211527 and on==true then
        if f then f.note:SetText("Cozy Sleeping Bag is always protected. Remove any existing junk mark in EllesmereUI.") end
        return true
    end
    local ok=L().SetJunkIgnored(id,on)
    if f then f.note:SetText(ok and (on and "Added to Never mark. Existing junk marks must be removed in EllesmereUI." or "Removed. The Advisor and item-type filters apply again.") or "Could not change this list (maximum 512 items, or saved data is held).") end
    P.Refresh()
    if R.SettingsKit then R.SettingsKit.RefreshOverview() end
    return ok
end
function P.TakeCursor()
    if not GetCursorInfo then return false end
    local kind,id=GetCursorInfo()
    if Plain(kind)~="item" or not ID(id) then return false end
    -- Forever's own bag/drop controls use the cursor item ID. Clearing returns
    -- it to its origin; no pickup, use or sale API is called.
    local ok=P.Ignore(id,true)
    if ok then ClearCursor() end
    return ok
end
local function Build(parent)
    local G,M=R.SettingsWidgets,R.SettingsMaterial
    f=CreateFrame("Frame",nil,parent)
    f:SetSize(WIDTH,HEIGHT);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG")
    f:SetToplevel(true);f:SetClampedToScreen(true);f:EnableMouse(true);f:Hide()
    M.Companion(f);M.HeaderBand(f,64)
    local title=G.Text(f,"heading");title:SetPoint("TOPLEFT",16,-16);title:SetText("Never mark as junk")
    local close=G.Button(f,"X",28,"secondary",P.Close);close:SetPoint("TOPRIGHT",-12,-12)
    f.note=G.Text(f,"small");f.note:SetPoint("BOTTOMLEFT",16,14);f.note:SetWidth(WIDTH-32);f.note:SetHeight(42)
    f.note:SetText("Choose a bag item or drop one above. Protects every copy across your account. Cozy Sleeping Bag is always protected.")
    f.drop=G.Button(f,"Drop a bag item here to never mark it",WIDTH-32,"secondary",P.TakeCursor)
    f.drop:SetPoint("TOPLEFT",16,-62);f.drop:SetHeight(42)
    f.drop:SetScript("OnReceiveDrag",P.TakeCursor)
    R.Interact.Tip(f.drop,"Never mark this item","Drag an item here from your bags. Only its item ID is saved; the item returns to its original slot. Existing junk marks stay until you remove them in EllesmereUI.")
    local function Source(value) mode=value;page=1;P.Refresh() end
    f.bags=G.Button(f,"Choose from bags",220,"secondary",function() Source("bags") end)
    f.bags:SetPoint("TOPLEFT",16,-114)
    f.ignored=G.Button(f,"Ignored items",220,"secondary",function() Source("ignored") end)
    f.ignored:SetPoint("TOPRIGHT",-16,-114)
    f.search=G.EditBox(f,WIDTH-32,26);f.search:SetPoint("TOPLEFT",16,-152);f.search:SetMaxLetters(100)
    R.Interact.Tip(f.search,"Find an item","Search by item name or ID.")
    f.search:SetScript("OnTextChanged",function() page=1;P.Refresh() end)
    f.search:SetScript("OnEscapePressed",function(self) self:ClearFocus();P.Close() end)
    f.rows={}
    for i=1,ROWS do
        local row=CreateFrame("Frame",nil,f);row:SetSize(WIDTH-32,36);row:SetPoint("TOPLEFT",16,-190-(i-1)*40)
        row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(30,30);row.icon:SetPoint("LEFT",0,0)
        row.name=G.Text(row,"body");row.name:SetPoint("TOPLEFT",40,-1);row.name:SetWidth(290);row.name:SetMaxLines(1)
        row.id=G.Text(row,"small");row.id:SetPoint("TOPLEFT",40,-19)
        row.action=G.Button(row,"Never mark",104,"secondary",function()
            local e=row.entry;if e and not e.fixed then P.Ignore(e.id,not e.ignored) end
        end);row.action:SetPoint("RIGHT")
        f.rows[i]=row
    end
    f.empty=G.Text(f,"body");f.empty:SetPoint("TOPLEFT",20,-202);f.empty:SetWidth(WIDTH-40)
    f.count=G.Text(f,"small");f.count:SetPoint("BOTTOMLEFT",16,72)
    f.prev=G.Button(f,"Previous",80,"secondary",function() page=math.max(1,page-1);P.Refresh() end)
    f.prev:SetPoint("BOTTOMRIGHT",-108,64)
    f.next=G.Button(f,"Next",80,"secondary",function() page=page+1;P.Refresh() end)
    f.next:SetPoint("BOTTOMRIGHT",-16,64)
    f:SetScript("OnShow",function()
        f:RegisterEvent("BAG_UPDATE_DELAYED");f:RegisterEvent("GET_ITEM_INFO_RECEIVED");P.Refresh()
    end)
    f:SetScript("OnHide",function() f:UnregisterAllEvents();f.search:ClearFocus();for _,row in ipairs(f.rows) do row.entry=nil end end)
    f:SetScript("OnEvent",P.Refresh)
end
function P.Open()
    local parent=R.SettingsUI and R.SettingsUI.Frame()
    if not parent or not parent:IsShown() then return false end
    if not f then Build(parent) end
    mode,page="bags",1;f.search:SetText("");f:Show();P.Refresh();return true
end
if R.OnSettingsClosed then R.OnSettingsClosed(P.Close) end
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views","workshop-junk-settings",function() page=1;P.Refresh() end)
end
