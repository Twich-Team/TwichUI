-- TwichUI: opening the Workshop
-- The Workshop (browse your professions' recipes, queue crafts, see the combined materials still needed) is an addon of its
-- own, TwichUI_Workshop, loaded the first time it is asked for (load on demand), like TwichUI Diagnostics. Nothing of it is loaded,
-- built at login unless the active profile opts in. Opening a profession also loads the enabled Workshop to remember its recipes,
-- without showing the Workshop window. docs/workshop.md has the whole.
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

-- A profession opened before the first Workshop visit must also be remembered.
-- Watch.Start schedules the initial read after the profession data has settled.
-- Never open a frame, load in combat, or bypass experimental consent here.
R:On("TRADE_SKILL_SHOW", function()
    if L.Enabled() and not L.Loaded() then L.Load() end
end)

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
local bools={wearable=true,upgrade=true,classReagent=true,profession=true,vendor=true,unlearnedRecipe=true,
    professionMaterial=true,tool=true,camping=true,mageScroll=true}
L.JUNK_MAX_RULES=32
local MAX_RULES=L.JUNK_MAX_RULES
local kinds={gear=true,materials=true,recipes=true,consumables=true,other=true}
local armors={cloth=true,leather=true,mail=true,plate=true,shield=true,other=true}
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
        elseif n.type=="armor" and armors[n.value] then return {type="armor",value=n.value}
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
    -- "All" filters sit beside the item type (the same answer, and one flat list to read); "Any" filters keep a group.
    local filters=r.match=="all" and root or {type="group",match=r.match,children={},strict=true}
    if r.qualityMin>0 or r.qualityMax<5 then filters.children[#filters.children+1]={type="quality",min=r.qualityMin,max=r.qualityMax} end
    for _,key in ipairs({"wearable","upgrade","classReagent","profession"}) do
        if r[key]~="any" then filters.children[#filters.children+1]={type=key,value=r[key]=="yes"} end
    end
    if filters~=root and #filters.children>0 then root.children[#root.children+1]=filters end
    return root
end
function T.Uses(n,key)
    if n.type==key then return true end
    for _,child in ipairs(n.children or {}) do if T.Uses(child,key) then return true end end
    return false
end
-- The one evaluator. `trace`, when given, receives "yes", "no" or "unknown" for every node it visits (no
-- short-circuit), so a preview can explain the same answer marking uses. Unknown never counts as a match.
local function Word(v) if v==nil then return "unknown" end;return v and "yes" or "no" end
function T.Eval(n,f,trace)
    local v
    if n.type=="group" then
        if #n.children==0 then v=false
        else
            local yes=n.match=="all"
            local unknown=false
            for _,child in ipairs(n.children) do
                local value=T.Eval(child,f,trace)
                if value==nil then unknown=true
                elseif n.match=="all" then yes=yes and value else yes=yes or value end
            end
            if unknown and (n.strict or (n.match=="all" and yes) or (n.match=="any" and not yes)) then v=nil else v=yes end
        end
    elseif n.type=="kind" then v=f.kind==n.value
    elseif n.type=="armor" then if f.armor~=nil then v=f.armor==n.value end
    elseif n.type=="quality" then
        if type(f.quality)=="number" then v=f.quality>=n.min and f.quality<=n.max end
    elseif bools[n.type] then
        if type(f[n.type])=="boolean" then v=f[n.type]==n.value end
    end
    if trace then trace[n]=Word(v) end
    return v
end
function T.Match(n,f) return T.Eval(n,f) end
T.ARMOR={{"cloth","Cloth"},{"leather","Leather"},{"mail","Mail"},{"plate","Plate"},{"shield","Shields"},{"other","Other armor"}}
T.KINDS={{"gear","Gear"},{"materials","Materials"},{"recipes","Recipes"},{"consumables","Supplies"},{"other","Other"}}
T.QUALITY={"Poor","Common","Uncommon","Rare","Epic","Legendary"}
local kindLabel={};for _,k in ipairs(T.KINDS) do kindLabel[k[1]]=k[2] end
local armorLabel={};for _,k in ipairs(T.ARMOR) do armorLabel[k[1]]=k[2] end
local boolWords={
    wearable={[true]="you can wear it now",[false]="you can't wear it now"},
    upgrade={[true]="it is a gear upgrade for you",[false]="it is not a gear upgrade for you"},
    classReagent={[true]="it is a known reagent for your class",[false]="it is not a known reagent for your class"},
    profession={[true]="a recipe you know uses it",[false]="no recipe you know uses it"},
    vendor={[true]="Workshop recommends Vendor",[false]="Workshop does not recommend Vendor"},
    unlearnedRecipe={[true]="it is a recipe for one of your professions that you have not learned",[false]="it is not an unlearned recipe for your professions"},
    professionMaterial={[true]="it is a material for one of your professions",[false]="it is not a material for your professions"},
    tool={[true]="it is a profession tool",[false]="it is not a profession tool"},
    camping={[true]="it is a camping item",[false]="it is not a camping item"},
    mageScroll={[true]="it is an undeciphered mage scroll",[false]="it is not an undeciphered mage scroll"},
}
-- A short plain phrase for one condition; the sentence below and the editor cards share these words.
function T.Phrase(n)
    if n.type=="kind" then return "it is "..(kindLabel[n.value] or "an item")
    elseif n.type=="armor" then return "its armor type is "..(armorLabel[n.value] or "unknown")
    elseif n.type=="quality" then
        local lo,hi=T.QUALITY[n.min+1] or "?",T.QUALITY[n.max+1] or "?"
        return n.min==n.max and ("its quality is "..lo) or ("its quality is "..lo.." to "..hi)
    elseif boolWords[n.type] then return boolWords[n.type][n.value==true] end
    return "unknown condition"
end
-- Natural language built from the saved representation, never from a second model. Nested groups are put in
-- parentheses so the sentence cannot be read two ways.
local function Join(parts,word)
    if #parts==1 then return parts[1] end
    if #parts==2 then return parts[1].." "..word.." "..parts[2] end
    return table.concat(parts,", ",1,#parts-1).." "..word.." "..parts[#parts]
end
local function Clause(n,nested)
    if n.type~="group" then return T.Phrase(n) end
    if #n.children==0 then return nested and "(nothing chosen yet)" or "nothing is chosen yet" end
    if #n.children==1 then return Clause(n.children[1],nested) end
    local parts={}
    for _,c in ipairs(n.children) do parts[#parts+1]=Clause(c,true) end
    local text=Join(parts,n.match=="any" and "or" or "and")
    return nested and ("("..text..")") or text
end
function T.Summary(tree)
    if type(tree)~="table" or tree.type~="group" then return "Add a condition. A rule with no conditions never marks anything." end
    if #tree.children==0 then return "Add a condition. A rule with no conditions never marks anything." end
    local text=Clause(tree,false)
    return "Mark an item as junk when "..text.."."
end
-- Conditions that cannot be satisfied today: marking reads "a known reagent for my class" and "used by a recipe I
-- know" only as confirmed (true) or unknown, never as proven false. The editor says so instead of hiding it.
T.NEVER={classReagent="TwichUI can confirm an item is on this list, never that it is not, so \"is not\" never matches.",
    profession="TwichUI can confirm an item is used by a recipe you know, never that it is not, so \"is not\" never matches."}
function T.Never(n) return n.value==false and T.NEVER[n.type] or nil end
-- What stops a rule from being switched on: nothing in it, or a group with nothing in it (it never matches).
function T.Problems(tree)
    local out={}
    local function Walk(n,root)
        if n.type=="group" then
            if #n.children==0 then out[#out+1]={node=n,code=root and "empty" or "emptyGroup",
                text=root and "Add at least one condition." or "A group with nothing in it never matches. Add a condition or remove it."} end
            for _,c in ipairs(n.children) do Walk(c,false) end
        elseif n.type=="quality" and n.min>n.max then
            out[#out+1]={node=n,code="range",text="Quality range starts above where it ends."}
        end
    end
    if type(tree)~="table" or tree.type~="group" then return {{code="empty",text="Add at least one condition."}} end
    Walk(tree,true)
    return out
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
    local out={kind=r.kind,on=r.on==true,match=r.match=="any" and "any" or "all",free=r.free==true or nil}
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
        if type(saved)~="table" or (saved.v~=1 and saved.v~=2) or type(saved.rows)~="table" or #saved.rows>MAX_RULES then return {},true end
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
local RULE_KEYS={"name","kind","on","free","match","qualityMin","qualityMax","wearable","upgrade","classReagent","profession"}
local function SameRows(expected,rows)
    if type(expected)~="table" or #expected~=#rows then return false end
    for i,r in ipairs(rows) do
        local e=expected[i]
        if type(e)~="table" or not T.Equal(e.tree,r.tree) then return false end
        for _,key in ipairs(RULE_KEYS) do if e[key]~=r[key] then return false end end
    end
    return true
end
local function Write(rows)
    local cfg=JunkConfig(true);if not cfg then return false end
    cfg.rules={v=2,rows=rows};JunkChanged();return true
end
-- A rule that would match nothing (or has nothing in it) may be saved while it is off, never switched on.
local function Incomplete(clean) return clean.on and clean.tree and #T.Problems(clean.tree)>0 end
-- A fresh rule: off, with an empty tree. An empty rule never matches, so an unfinished rule cannot mark anything.
function L.NewJunkRule(name)
    return {kind="other",name=name or "New rule",on=false,free=true,match="all",qualityMin=0,qualityMax=5,
        wearable="any",upgrade="any",classReagent="any",profession="any",tree={type="group",match="all",children={}}}
end
-- Commit the complete settings draft once, refusing stale profile/list edits.
function L.SaveJunkRule(index,rule,expected)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>math.min(MAX_RULES,#rows+1) then return false,"held" end
    if not SameRows(expected,rows) then return false,"stale" end
    local clean=RuleCopy(rule);if not clean then return false,"invalid" end
    if Incomplete(clean) then return false,"incomplete" end
    rows[index]=clean;return Write(rows) or false,nil
end
function L.SetJunkRule(index,key,value)
    if not ({kind=true,name=true,on=true,match=true,qualityMin=true,qualityMax=true,wearable=true,upgrade=true,classReagent=true,profession=true})[key] then return false end
    if type(index)~="number" or index%1~=0 or index<1 or index>MAX_RULES then return false end
    local rows,held=L.JunkRules();if held or not rows[index] then return false end
    local r=rows[index];r[key]=value;r=RuleCopy(r);if not r then return false end
    if Incomplete(r) then return false,"incomplete" end
    rows[index]=r
    return Write(rows)
end
-- A disabled copy at the end of the list, taken from a saved rule.
function L.DuplicateJunkRule(index)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>#rows or #rows>=MAX_RULES then return false end
    local source=rows[index]
    local copy=RuleCopy(source);if not copy then return false end
    copy.on=false;copy.tree=T.FromRule(source)
    local base=source.name or kindLabel[source.kind] or "Rule"
    copy.name=(base.." copy"):sub(1,60):gsub("[\192-\255][\128-\191]*$","")
    rows[#rows+1]=RuleCopy(copy);if not rows[#rows] then return false end
    return Write(rows) and #rows or false
end
function L.JunkTemplate(index,kind)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>math.min(MAX_RULES,#rows+1) then return false end
    local templates={poor={kind="gear",qualityMax=0},nonupgrade={kind="gear",upgrade="no",qualityMax=2},
        materials={kind="materials"},recipes={kind="recipes",qualityMax=1},custom={kind="other"}}
    local t=templates[kind];if not t then return false end
    rows[index]=RuleCopy({kind=t.kind,on=false,match="all",qualityMin=0,qualityMax=t.qualityMax or 5,upgrade=t.upgrade})
    return Write(rows)
end
function L.RemoveJunkRule(index,expected)
    local rows,held=L.JunkRules()
    if held or type(index)~="number" or index%1~=0 or index<1 or index>#rows then return false end
    if expected and not SameRows(expected,rows) then return false end
    table.remove(rows,index);return Write(rows)
end
-- One rule against one item's facts: true, false or nil (cannot tell). A rule saved without a tree is judged
-- through the tree the editor shows, so the editor, the summary and the marking engine share one expression.
-- A rule saved before the builder made Workshop's Vendor advice an ordinary condition (no `free` mark) still needs
-- it: it is judged as "Workshop recommends Vendor, and the rule". The builder shows that as a real condition.
function T.Effective(r)
    local tree=r.tree or T.FromRule(r)
    if r.free then return tree end
    if tree.match=="all" and not tree.strict then
        local children={{type="vendor",value=true}}
        for _,c in ipairs(tree.children) do children[#children+1]=c end
        return {type="group",match="all",children=children}
    end
    return {type="group",match="all",children={{type="vendor",value=true},tree}}
end
local function RuleValue(r,kind,facts,trace)
    local tree=T.Effective(r)
    local f={};for k,v in pairs(facts) do f[k]=v end;f.kind=kind
    return T.Eval(tree,f,trace),tree
end
-- The decision for one item against a list of rules. "protected" (never mark list or the Cozy Sleeping Bag) and
-- "class" (quest items and keys) come before any rule; a rule can only say "match", "nomatch" or "unknown".
-- Marking (JunkAllows) and the editor's item test both call this; `trace` is for the editor only.
function L.JunkJudge(id,class,facts,rows,trace)
    if L.JunkIgnored(id) then return "protected" end
    if type(class)~="number" or class~=class or class%1~=0 or class<0 or class>20 or class==12 or class==13 then return "class" end
    facts=facts or {}
    local kind=JUNK_CLASS[class] or "other"
    local unknown=false
    for i,r in ipairs(rows) do
        if r.on then
            local value=RuleValue(r,kind,facts,trace)
            if value==true then return "match",i end
            if value==nil then unknown=true end
        end
    end
    return unknown and "unknown" or "nomatch"
end
-- The decision marking acts on: JunkJudge over the saved rules, or (until the player first edits a rule) the older
-- per-type switches, which always required Workshop's Vendor advice.
function L.JunkVerdict(id,class,facts)
    local cfg=JunkConfig()
    if not (cfg and cfg.rules~=nil) then
        if L.JunkIgnored(id) then return "protected" end
        if type(class)~="number" or class~=class or class%1~=0 or class<0 or class>20 or class==12 or class==13 then return "class" end
        if not L.JunkFilter(JUNK_CLASS[class] or "other") then return "nomatch" end
        local v=facts and facts.vendor
        if v==true then return "match" elseif v==false then return "nomatch" end
        return "unknown"
    end
    local rows,held=L.JunkRules();if held then return "nomatch" end
    return L.JunkJudge(id,class,facts,rows)
end
function L.JunkAllows(id,class,facts) return L.JunkVerdict(id,class,facts)=="match" end
-- Whether any rule in force depends on Workshop's advice (the costly fact), so marking asks for it only then.
function L.JunkNeedsAdvisor()
    local cfg=JunkConfig()
    if not (cfg and cfg.rules~=nil) then return true end
    local rows,held=L.JunkRules();if held then return false end
    for _,r in ipairs(rows) do
        if r.on and (not r.free or T.Uses(r.tree or T.FromRule(r),"vendor")) then return true end
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
        advisorGain = tostring(w.Advisor and w.Advisor.Gain() or 0), objective = w.Session.Objective(), compact = w.Session.CompactMode(),
        cut = w.Fees and w.Fees.Mode() or (view.cut == "off" and "off" or "assumed") } end
    return { prices = view.prices == "detailed", guild = stock.useGuild == true, notices = view.notices ~= false,
        advisorGain = tostring(type(view.advisorGain)=="number" and view.advisorGain or 0), objective = view.objective == "cash" and "cash" or "economic", compact = view.compactMode == "craft" and "craft" or "travel",
        cut = view.cut == "off" and "off" or "assumed" }
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
    elseif key == "cut" and w.Fees then ok = w.Fees.SetMode(value)
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
