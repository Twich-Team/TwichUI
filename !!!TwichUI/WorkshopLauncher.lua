-- TwichUI: opening the Workshop
-- The Workshop (browse your professions' recipes, queue crafts, see the combined materials still needed) is an addon of its
-- own, TwichUI_Workshop, loaded the first time it is asked for (load on demand), like TwichUI Diagnostics. Nothing of it is loaded,
-- built at login unless the active profile opts in. Only that opt-in schedules a delayed load; it opens no window. docs/workshop.md has the whole.
--
--   L.Loaded()      read only: has the addon started this session
--   L.Load()        loads it if needed: true, or false and a reason code (never in combat)
--   L.Open()        loads it and shows its window; true, or false and a reason (said in chat)
--   L.Toggle()      the same, but closes the window when it is open (the command, the menu and the settings page use this)
--   L.Command(arg)  /tui workshop
--   L.Snapshot()    read only: loaded, attempts, failed

local R = TwichUI
local L = { attempts = 0 }
R.WorkshopLauncher = L
L.ADDON = "TwichUI_Workshop"

local function Say(fmt, ...) R.Print("workshop: " .. fmt, ...) end

local WHY = {
    EXPERIMENTAL_OFF = "Workshop is experimental and turned off. Enable Workshop — Experimental in TwichUI Settings > Workshop.",
    SAVED_NEWER = "your settings were saved by a newer TwichUI and are being kept unchanged. Use a compatible version before enabling Workshop.",
    MISSING = "its folder, TwichUI_Workshop, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Workshop is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Workshop needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Workshop can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Workshop is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Workshop's files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Workshop loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Workshop ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
    COMBAT = "not during combat. Try again when combat ends.",
}

function L.Explain(code)
    return "couldn't open the Workshop: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Workshop ~= nil and R.Workshop.ready == true end

local function LoadAddOn() return pcall(C_AddOns.LoadAddOn, L.ADDON) end

function L.Load()
    if not L.Enabled() then return false, "EXPERIMENTAL_OFF" end
    if L.Loaded() then
        if R.Workshop.Resume then R.Workshop.Resume() end
        return true
    end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = R.Perf.Call("workshop.load", LoadAddOn)
    if not ok then
        R.Fault("workshop", loaded)
        L.failed = "ERROR"
        return false, "ERROR"
    end
    if not loaded then
        L.failed = reason or "UNKNOWN"
        return false, L.failed
    end
    if not L.Loaded() then
        L.failed = "INCOMPLETE"
        return false, "INCOMPLETE"
    end
    L.failed = nil
    if R.Workshop.Resume then R.Workshop.Resume() end
    return true
end

local function Ready()
    local ok, why = L.Load()
    if ok then return R.Workshop end
    Say("%s", L.Explain(why))
    return nil
end

local function Run(method)
    local WS = Ready()
    if not WS then return false end
    local ok, err = pcall(WS[method])
    if not ok then
        R.Fault("workshop window", err)
        Say("%s", L.Explain("ERROR"))
        return false
    end
    return true
end

function L.Open() return Run("Open") end
function L.Toggle() return Run("Toggle") end

-- Shared guarded service load for both AH contexts; never attaches native scan
-- controls merely to change presentation. Existing Load owns consent/diagnostics.
function L.LoadAuctionUI()
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    local previous = L.previewLoading
    L.previewLoading = true
    local ok, loaded, why = pcall(L.Load)
    L.previewLoading = previous
    if not ok then R.Fault("auction UI load", loaded); return false, "ERROR" end
    return loaded, why
end

-- Explicit standalone preview; never touches the native Auction House or Host.
function L.AuctionPreview()
    if InCombatLockdown and InCombatLockdown() then Say("%s", L.Explain("COMBAT")); return false end
    -- Workshop's optional native scan-button integration is deferred for this
    -- load path: previewing must not add children or hooks to Blizzard's frame.
    L.previewLoading = true
    local loaded, WS = pcall(Ready)
    L.previewLoading = nil
    if not loaded then R.Fault("auction preview load", WS); Say("%s", L.Explain("ERROR")); return false end
    if not WS then return false end
    if not (WS.AuctionUI and WS.AuctionUI.Show) then Say("%s", L.Explain("INCOMPLETE")); return false end
    local ok, result, why = pcall(WS.AuctionUI.Show)
    if not ok then
        WS.AuctionUI.Hide()
        R.Fault("auction preview", result)
        Say("%s", L.Explain("ERROR"))
        return false
    end
    if result ~= true then Say("%s", L.Explain(why or "INCOMPLETE")); return false end
    return true
end

function L.Command(arg)
    local word = (arg or ""):match("^%s*(%S*)"):lower()
    if word == "" or word == "open" then L.Toggle() return end
    print(R.GREY .. "/tui workshop: open or close the Workshop (loads it the first time)." .. "|r")
end

local loginState, loginMS = "waiting", nil
function L.Snapshot()
    return { enabled = L.Enabled(), loaded = L.Loaded(), attempts = L.attempts, failed = L.failed, login = loginState, loginMS = loginMS }
end

-- Profile-scoped opt-in. Only the old explicit login preference establishes
-- prior intent; stored recipes/queues/history are never used to infer consent.
function L.Enabled()
    local ui = type(TwichUIDB) == "table" and TwichUIDB.ui
    if type(ui) ~= "table" then return false end
    if type(ui.workshopEnabled) == "boolean" then return ui.workshopEnabled end
    return ui.workshopEnabled == nil and ui.workshopLoadOnLogin == true
end
function L.Migrate()
    if type(TwichUIDB) ~= "table" or (R.Persist and R.Persist.IsHeld("TwichUIDB")) then return end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    if TwichUIDB.ui.workshopEnabled == nil then
        TwichUIDB.ui.workshopEnabled = TwichUIDB.ui.workshopLoadOnLogin == true
    end
end
function L.Apply()
    L.Migrate()
    if not L.Enabled() and R.AuctionHost then R.AuctionHost.SetTestEnabled(false) end
    local w = L.Loaded() and R.Workshop
    if w then
        if L.Enabled() then if w.Resume then w.Resume() end; if w.Junk then w.Junk.Start() end
        elseif w.Suspend then w.Suspend() end
    end
    if R.Ledger then R.Ledger.Refresh() end   -- the gold ledger records while the Workshop is on, loaded or not
end
function L.SetEnabled(on)
    if type(on) ~= "boolean" or type(TwichUIDB) ~= "table" then return false, "ERROR" end
    if R.Persist and R.Persist.IsHeld("TwichUIDB") then return false, "SAVED_NEWER" end
    if on and InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    L.Migrate()
    TwichUIDB.ui.workshopEnabled = on
    L.Apply()
    -- Enabling permits the normal explicit Load/Open path. It does not eagerly
    -- deserialize a large saved market database or attach native AH controls.
    return true
end
R:OnInit(L.Migrate)
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views", "workshop-opt-in", L.Apply) end

-- Lightweight settings access. Reading this never loads the Workshop or its
-- separate market database. Presentation keys keep their established scope.
function L.VendorJunkEnabled()
    local ui=type(TwichUIDB)=="table" and TwichUIDB.ui
    return type(ui)=="table" and ui.workshopVendorJunk==true or false
end
function L.SetVendorJunkEnabled(on)
    if type(on)~="boolean" or type(TwichUIDB)~="table" or R.Persist and R.Persist.IsHeld("TwichUIDB") then return false end
    if type(TwichUIDB.ui)~="table" then TwichUIDB.ui={} end
    TwichUIDB.ui.workshopVendorJunk=on
    if R.Workshop and R.Workshop.Junk then R.Workshop.Junk.Start() end
    return true
end
-- Profile-local filters and account-wide protections, without loading Workshop.
local JUNK_DEFAULTS = {gear=true, materials=true, recipes=false, consumables=false, other=false}
local JUNK_CLASS = {[0]="consumables", [2]="gear", [4]="gear", [5]="materials", [7]="materials", [9]="recipes"}
local function JunkID(id)
    return not (issecretvalue and issecretvalue(id)) and type(id)=="number" and id==id
        and id>=1 and id<=2147483647 and id%1==0
end
local function JunkConfig(write)
    local ui=type(TwichUIDB)=="table" and TwichUIDB.ui
    if write then
        if type(TwichUIDB)~="table" or R.Persist and R.Persist.IsHeld("TwichUIDB") then return nil end
        if type(ui)~="table" then ui={};TwichUIDB.ui=ui end
        if type(ui.workshopJunk)~="table" then ui.workshopJunk={} end
    end
    return type(ui)=="table" and type(ui.workshopJunk)=="table" and ui.workshopJunk or nil
end
function L.JunkFilter(key)
    local cfg=JunkConfig()
    local value=cfg and cfg[key]
    if type(value)=="boolean" then return value end
    return JUNK_DEFAULTS[key]==true
end
local function JunkChanged()
    if R.Workshop and R.Workshop.Junk then R.Workshop.Junk.Start() end
end
function L.SetJunkFilter(key,on)
    if JUNK_DEFAULTS[key]==nil or type(on)~="boolean" then return false end
    local cfg=JunkConfig(true);if not cfg then return false end
    cfg[key]=on;JunkChanged();return true
end
local function JunkIgnores(write)
    if type(TwichUIDB)~="table" then return nil end
    if write then
        if R.Persist and R.Persist.IsHeld("TwichUIDB") then return nil end
        if type(TwichUIDB.workshopJunkIgnore)~="table" then TwichUIDB.workshopJunkIgnore={} end
    end
    -- Outside the profile groups: changing profiles must not lift protection.
    return type(TwichUIDB.workshopJunkIgnore)=="table" and TwichUIDB.workshopJunkIgnore or nil
end
function L.JunkIgnored(id)
    if not JunkID(id) then return true end
    if id==211527 then return true end -- Cozy Sleeping Bag, also used by camping/Data.lua
    local ignore=JunkIgnores()
    return ignore and ignore[id]==true or false
end
function L.JunkIgnoreList()
    local out={}
    for id,on in pairs(JunkIgnores() or {}) do
        if on==true and JunkID(id) then out[#out+1]=id end
    end
    table.sort(out);return out
end
function L.SetJunkIgnored(id,on)
    if not JunkID(id) or type(on)~="boolean" or id==211527 then return false end
    local ignore=JunkIgnores(true);if not ignore then return false end
    if on and ignore[id]~=true and #L.JunkIgnoreList()>=512 then return false end
    ignore[id]=on or nil;JunkChanged();return true
end
L.JunkRuleTypes={"gear","materials","recipes","consumables","other"}
-- Bounded condition trees. UI paths/drag targets reference draft nodes only.
local T={MAX_NODES=32,MAX_DEPTH=4}
L.JunkTree=T
local bools={wearable=true,upgrade=true,classReagent=true,profession=true}
local kinds={gear=true,materials=true,recipes=true,consumables=true,other=true}
function T.Copy(node)
    local count,seen=0,{}
    local function Read(n,depth)
        if type(n)~="table" or seen[n] or depth>T.MAX_DEPTH then return nil end
        seen[n]=true;count=count+1;if count>T.MAX_NODES then return nil end
        if n.type=="group" then
            if (n.match~="all" and n.match~="any") or type(n.children)~="table" or #n.children>T.MAX_NODES then return nil end
            local children={}
            for k in pairs(n.children) do if type(k)~="number" or k%1~=0 or k<1 or k>#n.children then return nil end end
            for _,child in ipairs(n.children) do local c=Read(child,depth+1);if not c then return nil end;children[#children+1]=c end
            return {type="group",match=n.match,children=children,strict=n.strict==true or nil}
        elseif n.type=="kind" and kinds[n.value] then return {type="kind",value=n.value}
        elseif n.type=="quality" then
            if type(n.min)~="number" or type(n.max)~="number" or n.min%1~=0 or n.max%1~=0 or n.min<0 or n.max>5 or n.min>n.max then return nil end
            return {type="quality",min=n.min,max=n.max}
        elseif bools[n.type] and type(n.value)=="boolean" then return {type=n.type,value=n.value} end
    end
    return Read(node,1)
end
function T.Equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not T.Equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function T.FromRule(r)
    if r.tree then return T.Copy(r.tree) end
    local root={type="group",match="all",children={{type="kind",value=r.kind}}}
    local filters={type="group",match=r.match,children={},strict=true}
    if r.qualityMin>0 or r.qualityMax<5 then filters.children[#filters.children+1]={type="quality",min=r.qualityMin,max=r.qualityMax} end
    for _,key in ipairs({"wearable","upgrade","classReagent","profession"}) do
        if r[key]~="any" then filters.children[#filters.children+1]={type=key,value=r[key]=="yes"} end
    end
    if #filters.children>0 then root.children[#root.children+1]=filters end
    return root
end
function T.Uses(n,key)
    if n.type==key then return true end
    for _,child in ipairs(n.children or {}) do if T.Uses(child,key) then return true end end
    return false
end
function T.Match(n,f)
    if n.type=="group" then
        if #n.children==0 then return false end
        local yes=n.match=="all"
        local unknown=false
        for _,child in ipairs(n.children) do
            local value=T.Match(child,f)
            if value==nil then unknown=true
            elseif n.match=="all" then yes=yes and value else yes=yes or value end
        end
        if unknown and (n.strict or (n.match=="all" and yes) or (n.match=="any" and not yes)) then return nil end
        return yes
    elseif n.type=="kind" then return f.kind==n.value
    elseif n.type=="quality" then
        if type(f.quality)~="number" then return nil end
        return f.quality>=n.min and f.quality<=n.max
    elseif bools[n.type] then
        if type(f[n.type])~="boolean" then return nil end
        return f[n.type]==n.value
    end
end
function T.Find(root,node,parent)
    if root==node then return parent end
    for i,child in ipairs(root.children or {}) do
        if child==node then return root,i end
        local p,j=T.Find(child,node,root);if p then return p,j end
    end
end
function T.Contains(root,node)
    if root==node then return true end
    for _,child in ipairs(root.children or {}) do if T.Contains(child,node) then return true end end
    return false
end
-- Validate a proposed move on a disposable clone, including depth, cycles and bounds.
function T.Move(root,node,destination,slot,apply)
    if node==root or not T.Contains(root,node) or not T.Contains(root,destination)
        or destination.type~="group" or T.Contains(node,destination) then return false end
    local parent,at=T.Find(root,node)
    slot=slot or #destination.children+1
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>#destination.children+1 then return false end
    local adjusted=slot-(parent==destination and at<slot and 1 or 0)
    table.remove(parent.children,at);table.insert(destination.children,adjusted,node)
    local valid=T.Copy(root)~=nil
    if not apply or not valid then table.remove(destination.children,adjusted);table.insert(parent.children,at,node) end
    return valid
end
local function RuleCopy(r)
    if type(r)~="table" then return nil end
    local kinds={gear=true,materials=true,recipes=true,consumables=true,other=true}
    if not kinds[r.kind] then return nil end
    local out={kind=r.kind,on=r.on==true,match=r.match=="any" and "any" or "all"}
    if r.name~=nil then
        if type(r.name)~="string" or #r.name>60 or r.name:find("[%c|]") then return nil end
        out.name=r.name
    end
    for _,key in ipairs({"qualityMin","qualityMax"}) do
        local n=r[key]
        if type(n)~="number" or n~=n or n%1~=0 or n<0 or n>5 then return nil end
        out[key]=n
    end
    if out.qualityMin>out.qualityMax then return nil end
    for _,key in ipairs({"wearable","upgrade","classReagent","profession"}) do
        if r[key]~=nil and r[key]~="any" and r[key]~="yes" and r[key]~="no" then return nil end
        out[key]=r[key] or "any"
    end
    if r.tree~=nil then out.tree=T.Copy(r.tree);if not out.tree or out.tree.type~="group" then return nil end end
    return out
end
function L.JunkRules()
    local cfg=JunkConfig();local saved=cfg and cfg.rules
    if saved~=nil then
        if type(saved)~="table" or (saved.v~=1 and saved.v~=2) or type(saved.rows)~="table" or #saved.rows>8 then return {},true end
        local rows={}
        for _,r in ipairs(saved.rows) do local copy=RuleCopy(r);if not copy then return {},true end;rows[#rows+1]=copy end
        return rows,false
    end
    local rows={}
    for _,kind in ipairs(L.JunkRuleTypes) do
        rows[#rows+1]={kind=kind,on=L.JunkFilter(kind),match="all",qualityMin=0,qualityMax=5,
            wearable="any",upgrade="any",classReagent="any",profession="any"}
    end
    return rows,false
end
-- Commit the complete settings draft once, refusing stale profile/list edits.
function L.SaveJunkRule(index,rule,expected)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>math.min(8,#rows+1) then return false end
    if type(expected)~="table" or #expected~=#rows then return false end
    for i,r in ipairs(rows) do
        if not T.Equal(expected[i] and expected[i].tree,r.tree) then return false end
        for _,key in ipairs({"name","kind","on","match","qualityMin","qualityMax","wearable","upgrade","classReagent","profession"}) do
            if type(expected[i])~="table" or expected[i][key]~=r[key] then return false end
        end
    end
    local clean=RuleCopy(rule);if not clean then return false end
    local cfg=JunkConfig(true);if not cfg then return false end
    rows[index]=clean;cfg.rules={v=2,rows=rows};JunkChanged();return true
end
function L.SetJunkRule(index,key,value)
    if not ({kind=true,on=true,match=true,qualityMin=true,qualityMax=true,wearable=true,upgrade=true,classReagent=true,profession=true})[key] then return false end
    if type(index)~="number" or index%1~=0 or index<1 or index>8 then return false end
    local rows,held=L.JunkRules();if held or not rows[index] then return false end
    local r=rows[index];r[key]=value;r=RuleCopy(r);if not r then return false end
    rows[index]=r
    local cfg=JunkConfig(true);if not cfg then return false end
    cfg.rules={v=2,rows=rows};JunkChanged();return true
end
function L.JunkTemplate(index,kind)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>math.min(8,#rows+1) then return false end
    local templates={poor={kind="gear",qualityMax=0},nonupgrade={kind="gear",upgrade="no",qualityMax=2},
        materials={kind="materials"},recipes={kind="recipes",qualityMax=1},custom={kind="other"}}
    local t=templates[kind];if not t then return false end
    rows[index]=RuleCopy({kind=t.kind,on=false,match="all",qualityMin=0,qualityMax=t.qualityMax or 5,upgrade=t.upgrade})
    local cfg=JunkConfig(true);if not cfg then return false end
    cfg.rules={v=2,rows=rows};JunkChanged();return true
end
function L.RemoveJunkRule(index,expected)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>#rows then return false end
    if expected then
        if #expected~=#rows then return false end
        for i,r in ipairs(rows) do
            if not T.Equal(expected[i] and expected[i].tree,r.tree) then return false end
        for _,key in ipairs({"name","kind","on","match","qualityMin","qualityMax","wearable","upgrade","classReagent","profession"}) do
                if type(expected[i])~="table" or expected[i][key]~=r[key] then return false end
            end
        end
    end
    local cfg=JunkConfig(true);if not cfg then return false end
    table.remove(rows,index);cfg.rules={v=2,rows=rows};JunkChanged();return true
end
function L.JunkAllows(id,class,facts)
    if L.JunkIgnored(id) or type(class)~="number" or class~=class or class%1~=0 or class<0 or class>20
        or class==12 or class==13 then return false end
    local cfg=JunkConfig()
    -- Legacy toggles remain authoritative until the player first edits a rule.
    if not (cfg and cfg.rules~=nil) then return L.JunkFilter(JUNK_CLASS[class] or "other") end
    local rows,held=L.JunkRules();if held then return false end
    facts=facts or {}
    for _,r in ipairs(rows) do
        if r.on and r.tree then
            local f={};for k,v in pairs(facts) do f[k]=v end;f.kind=JUNK_CLASS[class] or "other"
            if T.Match(r.tree,f)==true then return true end
        elseif r.on and r.kind==(JUNK_CLASS[class] or "other") then
            local checks={}
            local unknown=false
            if r.qualityMin>0 or r.qualityMax<5 then
                if type(facts.quality)~="number" then unknown=true end
                checks[#checks+1]=type(facts.quality)=="number" and facts.quality>=r.qualityMin and facts.quality<=r.qualityMax
            end
            for _,key in ipairs({"wearable","upgrade","classReagent","profession"}) do
                if r[key]~="any" then
                    if type(facts[key])~="boolean" then unknown=true end
                    checks[#checks+1]=type(facts[key])=="boolean" and facts[key]==(r[key]=="yes")
                end
            end
            local pass=r.match=="all"
            for _,check in ipairs(checks) do
                if r.match=="all" then pass=pass and check else pass=pass or check end
            end
            if #checks==0 then pass=true end
            if pass and not unknown then return true end
        end
    end
    return false
end
function L.LoadOnLogin()
    local ui = type(TwichUIDB) == "table" and TwichUIDB.ui
    return type(ui) == "table" and ui.workshopLoadOnLogin == true or false
end
function L.SetLoadOnLogin(on)
    if type(on) ~= "boolean" or type(TwichUIDB) ~= "table" then return false end
    if on == L.LoadOnLogin() then return true end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.workshopLoadOnLogin = on or nil
    return true
end
-- Auction defaults stay lightweight and profile-local. Reading them never
-- loads Workshop or creates saved data; existing drafts keep their edits.
L.AuctionDefaults={advisorOnly=false,maxQuantity=true,duration=1}
function L.AuctionSettings()
    local ui=type(TwichUIDB)=="table" and TwichUIDB.ui
    local saved=type(ui)=="table" and type(ui.auctionHouse)=="table" and ui.auctionHouse or {}
    return {advisorOnly=saved.advisorOnly==true,maxQuantity=saved.maxQuantity~=false,
        duration=type(saved.duration)=="number" and saved.duration%1==0 and saved.duration>=1 and saved.duration<=3 and saved.duration or 1}
end
function L.SetAuctionOption(key,value)
    if key=="duration" then
        if type(value)~="number" or value%1~=0 or value<1 or value>3 then return false end
    elseif key=="advisorOnly" or key=="maxQuantity" then
        if type(value)~="boolean" then return false end
    else return false end
    if type(TwichUIDB)~="table" or R.Persist and R.Persist.IsHeld("TwichUIDB") then return false end
    if type(TwichUIDB.ui)~="table" then TwichUIDB.ui={} end
    if type(TwichUIDB.ui.auctionHouse)~="table" then TwichUIDB.ui.auctionHouse={} end
    TwichUIDB.ui.auctionHouse[key]=value
    return true
end
function L.SettingsState()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local view = type(ws) == "table" and type(ws.view) == "table" and ws.view or {}
    local stock = type(ws) == "table" and type(ws.storage) == "table" and ws.storage or {}
    local w = L.Enabled() and L.Loaded() and R.Workshop
    if w then return { prices = w.Session.PriceDetail(), guild = w.Storage.UseGuild(), notices = w.Notice.On(),
        advisorGain = tostring(w.Advisor and w.Advisor.Gain() or 0), objective = w.Session.Objective(), compact = w.Session.CompactMode() } end
    return { prices = view.prices == "detailed", guild = stock.useGuild == true, notices = view.notices ~= false,
        advisorGain = tostring(type(view.advisorGain)=="number" and view.advisorGain or 0), objective = view.objective == "cash" and "cash" or "economic", compact = view.compactMode == "craft" and "craft" or "travel" }
end
function L.SetOption(key, on)
    if type(on) ~= "boolean" or not L.Loaded() then return false end
    local w = R.Workshop
    local ok
    if key == "prices" then ok = w.Session.SetPriceDetail(on)
    elseif key == "guild" then ok = w.Session.SetUseGuild(on)
    elseif key == "notices" then ok = w.Notice.SetOn(on)
    else return false end
    if ok and w.Window and w.Window.IsShown() then w.Window.Render() end
    if ok and w.Compact and w.Compact.IsShown() then w.Compact.Schedule() end
    return ok
end

function L.SetChoice(key, value)
    if not L.Loaded() then return false end
    local w, ok = R.Workshop
    if key == "objective" then ok = w.Session.SetObjective(value)
    elseif key == "compact" then ok = w.Compact.SetMode(value)
    elseif key == "advisorGain" and w.Advisor then ok = w.Advisor.SetGain(tonumber(value))
    else return false end
    if ok and w.Window and w.Window.IsShown() then w.Window.Render() end
    if ok and w.Compact and w.Compact.IsShown() then w.Compact.Schedule() end
    return ok
end

-- A session's first world entry latches the login choice, after profile loading.
-- Off means no timer and no Workshop initialization. Opting in later takes effect
-- next login/reload. Deserialization is synchronous even though the load is delayed.
local entered, pending, waiting, attempted = false, false, false, false
local generation
local function CurrentProfile()
    return R.Profiles and R.Profiles.Generation and R.Profiles.Generation() or 0
end
local function ScheduleLogin()
    if pending or attempted then return end
    pending, waiting, loginState = true, false, "scheduled"
    C_Timer.After(2, function()
        pending = false
        if generation ~= CurrentProfile() or not L.Enabled() or not (L.LoadOnLogin() or L.VendorJunkEnabled()) then loginState = "cancelled"; return end
        if not R.Life.InWorld() then loginState = "world"; return end
        if L.Loaded() then attempted, loginState = true, "already-loaded"; return end
        if InCombatLockdown and InCombatLockdown() then waiting, loginState = true, "combat"; return end
        attempted = true
        local start = debugprofilestop and debugprofilestop()
        local ok, why = L.Load()
        if start then loginMS = math.max(0, debugprofilestop() - start) end
        loginState = ok and "loaded" or (why or "failed")
        if not ok and R.Life then R.Life.Note("workshop-login-failed") end
    end)
end
R:On("PLAYER_ENTERING_WORLD", function()
    if not (R.Life and R.Life.configReady) then return end
    if entered then
        if loginState == "world" then ScheduleLogin() end
        return
    end
    entered = true
    if not L.Enabled() or not (L.LoadOnLogin() or L.VendorJunkEnabled()) then loginState = "off"; return end
    generation = CurrentProfile()
    ScheduleLogin()
end)
R:On("PLAYER_REGEN_ENABLED", function()
    if waiting and not attempted then ScheduleLogin() end
end)
