-- Unit-tested geometry/lifecycle. Native portrait masks, taint and rendering need owner checks.
local root = ROOT or '../!!!TwichUI/'
local checks = 0
local function check(v,msg) checks=checks+1; assert(v,msg) end
local function near(a,b) check(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b)) end
local made, callbacks, combat = {}, {}, false
local SECRET = {}
local function frame(parent)
    local f = { parent=parent, w=52, h=52, shown=true, scripts={}, hooks={}, events={}, level=10, alpha=1 }
    made[#made+1]=f
    function f:GetObjectType() return 'Frame' end
    function f:GetAttribute(k) return k=='unit' and self.unit end
    function f:GetParent() return self.parent end
    function f:GetWidth() return self.w end
    function f:GetHeight() return self.h end
    function f:GetFrameLevel() return self.level end
    function f:GetFrameStrata() return self.strata or 'MEDIUM' end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(v) self.alpha=v end
    function f:EnableMouse(v) self.mouse=v end
    function f:SetScript(e,fn) self.scripts[e]=fn end
    function f:HookScript(e,fn) self.hooks[e]=self.hooks[e] or {}; table.insert(self.hooks[e],fn) end
    function f:RegisterEvent(e) self.events[e]=true end
    function f:RegisterUnitEvent(e) self.events[e]=true end
    function f:UnregisterEvent(e) self.events[e]=nil end
    function f:UnregisterAllEvents() self.events={} end
    local function layout() check(not combat,'protected layout deferred during combat') end
    function f:SetParent(p) layout(); self.parent=p end
    function f:SetAllPoints(p) layout(); self.all=p end
    function f:ClearAllPoints() layout() end
    function f:SetFrameLevel(v) layout(); self.level=v end
    function f:SetFrameStrata(v) layout(); self.strata=v end
    function f:SetPoint(point,p,rel,x,y) layout(); self.point,self.anchor,self.rel,self.x,self.y=point,p,rel,x,y end
    function f:SetSize(w,h) layout(); self.w,self.h=w,h end
    function f:SetTexCoord(l,r,t,b) self.coords={l,r,t,b} end
    function f:SetTexture(path) self.path=path; self.textureSets=(self.textureSets or 0)+1; return not self.fail end
    function f:Show() self.shown=true end
    function f:Hide() self.shown=false end
    function f:CreateTexture() self.texCount=(self.texCount or 0)+1; return frame(self) end
    return f
end
CreateFrame=function(_,_,p) return frame(p) end
hooksecurefunc=function(f,k,fn) local original=f[k]; f[k]=function(...) original(...); fn(...) end end
InCombatLockdown=function() return combat end
issecretvalue=function(v) return v==SECRET end
C_AddOns={IsAddOnLoaded=function() return true end}
local exists, classification, boss = true,'rare',false
UnitExists=function() return exists end
UnitClassification=function() return classification end
UnitIsBossMob=function() return boss end
local enabled=false
TwichUIDB={modules={targetArt=false},ui={targetArt={x=17,y=-9,scale=135,bossX=4,mapRare='none',opacity=65,mirror=true}}}
TwichUI={PATH='Interface\\AddOns\\!!!TwichUI\\',Life={loggedIn=true},Perf={Wrap=function(_,fn) return fn end},
    Enabled=function() return enabled end,Fault=function(_,err) error(err) end,
    OnInit=function(_,fn) callbacks.init=fn end,On=function(_,e,fn) callbacks[e]=fn end,
    Profiles={OnApply=function(_,_,fn) callbacks.profile=fn end},OnSettingsClosed=function(fn) callbacks.close=fn end}
local function target()
    local f=frame(); f.unit='target'; f.w,f.h=181,52
    f.Portrait={backdrop=frame(f)}
    return f,f.Portrait.backdrop
end
local f,p=target(); EllesmereUIUnitFrames_Target=f
local function fire(e,...)
    for _,o in ipairs(made) do if o.events[e] and o.scripts.OnEvent then o.scripts.OnEvent(o,e,...) end end
end
local function hook(o,e) for _,fn in ipairs(o.hooks[e] or {}) do fn(o) end end
local function load()
    dofile(root..'targetart/Config.lua'); dofile(root..'targetart/Ellesmere.lua'); dofile(root..'targetart/Display.lua')
end
load()
local C,D=TwichUI.TargetArt,TwichUI.TargetArtDisplay
local legacy=TwichUIDB.ui.targetArt
check(C.Get('style')=='modern','old profile defaults to modern')
callbacks.init(); check(not D.Holder() and not enabled,'disabled old profile stays disabled')
check(legacy.x==17 and legacy.bossX==4 and legacy.mapRare=='none','migration preserves legacy values')
check(TwichUIDB.modules.targetArt==false,'module state preserved')
check(not C.Set('style','unknown'),'style validation')
for _,case in ipairs({{'worldboss',false,'boss'},{'rareelite',false,'boss'},{'elite',false,'elite'},{'rare',false,'rare'},{'normal',true,'boss'}}) do
    check(C.PickModern(case[1],case[2])==case[3],'classification priority '..case[1])
end
for _,kind in ipairs({'normal','trivial','minus','player','unknown'}) do check(C.PickModern(kind,false)==nil,'unsupported '..kind) end
check(C.PickModern(nil,nil)==nil,'unreadable classification')
for _,id in ipairs({'boss','elite','rare'}) do
    for _,size in ipairs({32,52,80}) do
        local art=C.MODERN[id]; local q=C.ModernPlacement(id,size,size,{})
        near(q.w/q.h,1)
        local factor=q.w/art.canvas
        near(q.x+(art.x-art.canvas/2)*factor,0)
        near(q.y-(art.y-art.canvas/2)*factor,0)
        check(art.w*factor>=size and art.h*factor>=size,'aperture contains portrait')
        check(q.l==0 and q.r==1 and q.t==0 and q.b==1,'orientation preserved')
    end
end
check(C.ModernPlacement('boss',0,52)==nil and C.ModernPlacement('boss',52,0)==nil, 'zero portrait rejected')
check(C.ModernPlacement('boss',0/0,52)==nil and C.ModernPlacement('missing',52,52)==nil, 'invalid geometry rejected')
local rectangular=C.ModernPlacement('boss',40,80,{})
near(rectangular.w/rectangular.h,1)
check(C.MODERN.boss.w*rectangular.w/C.MODERN.boss.canvas>=40, 'rectangular width contained')
check(C.MODERN.boss.h*rectangular.h/C.MODERN.boss.canvas>=80, 'rectangular height contained')
enabled=true; D.Refresh()
local h,t=D.Holder(),D.Texture()
check(h and h:GetParent()==p and h.mouse==false,'portrait-relative inert holder')
check(t.shown and t.path==C.MODERN.rare.path,'modern ignores legacy None mapping')
local originalWidth=t.w
for _,case in ipairs({{'worldboss','boss'},{'elite','elite'},{'rareelite','boss'},{'rare','rare'}}) do
    classification=case[1]; fire('PLAYER_TARGET_CHANGED')
    check(t.shown and t.path==C.MODERN[case[2]].path,'modern texture '..case[1])
    near(t.w,originalWidth)
end
classification='normal'; fire('PLAYER_TARGET_CHANGED'); check(not t.shown,'normal clears art')
classification='elite'; fire('UNIT_CLASSIFICATION_CHANGED','target'); check(t.shown,'classification event restores')
exists=false; fire('PLAYER_TARGET_CHANGED'); check(not t.shown,'cleared target hides')
exists=true; classification=SECRET; fire('PLAYER_TARGET_CHANGED'); check(not t.shown,'secret classification hides')
classification='rare'; boss=SECRET; fire('PLAYER_TARGET_CHANGED'); check(t.shown and t.path==C.MODERN.rare.path,'secret boss flag uses readable classification')
boss=false
for i=1,50 do classification=i%2==0 and 'elite' or 'rare'; fire('PLAYER_TARGET_CHANGED') end
check(D.Holder()==h and h.texCount==1,'rapid changes reuse texture')
p.w,p.h=104,104; hook(p,'OnSizeChanged'); near(t.w,originalWidth*2)
f.h=100; hook(f,'OnSizeChanged'); near(t.w,originalWidth*2)
fire('UI_SCALE_CHANGED'); near(t.w,originalWidth*2)
check(t.anchor==p,'scale uses portrait coordinate space')
p.shown=false; hook(p,'OnHide'); check(not t.shown,'disabled portrait hides')
p.shown=true; hook(p,'OnShow'); check(t.shown,'portrait return restores')
p.w=0; hook(p,'OnSizeChanged'); check(not t.shown,'zero-size portrait hides')
p.w=104; hook(p,'OnSizeChanged'); check(t.shown,'valid dimensions restore')
f.Portrait=nil; D.Refresh(); check(not t.shown,'missing portrait hides')
f.Portrait={backdrop=p}; D.Refresh(); check(t.shown,'portrait restored')
C.Set('style','legacy'); check(D.Holder()==h and h:GetParent()==f,'legacy reuses holder on target')
check(C.Get('x')==17 and C.Get('scale')==135 and C.Get('bossX')==4 and C.Get('mirror'),'legacy values preserved exactly')
classification='rare'; fire('PLAYER_TARGET_CHANGED'); check(not t.shown,'legacy None mapping restored')
classification='elite'; fire('PLAYER_TARGET_CHANGED'); check(t.path==C.ART.elite.path and t.shown,'legacy artwork restored')
C.Set('style','modern'); check(h:GetParent()==p and t.path==C.MODERN.elite.path,'switch modern immediate')
C.Set('style','legacy'); callbacks.profile(); check(C.Get('style')=='legacy','explicit legacy survives profile apply')
local savedBeforeReset=TwichUIDB.ui.targetArt
local savedCopy={}
for k,v in pairs(savedBeforeReset) do savedCopy[k]=v end
C.ResetSettings(); check(C.Get('style')=='legacy','legacy reset preserves explicit style')
for k,v in pairs(savedCopy) do C.Set(k,v) end
C.Set('style','modern'); callbacks.profile(); check(C.Get('style')=='modern','explicit modern survives profile apply')
local frames=#made; local hooks=#p.hooks.OnSizeChanged
for i=1,10 do D.Refresh(); C.Set('style','legacy'); C.Set('style','modern') end
check(#made==frames and h.texCount==1 and #p.hooks.OnSizeChanged==hooks,'refresh/style switches do not duplicate frames/hooks')
combat=true; fire('PLAYER_REGEN_DISABLED'); classification='rare'; fire('PLAYER_TARGET_CHANGED')
check(t.shown and t.path==C.MODERN.rare.path,'classification texture updates in combat')
local beforeCombatWidth=t.w
p.w,p.h=156,156; hook(p,'OnSizeChanged'); near(t.w,beforeCombatWidth)
check(not t.shown,'stale resized portrait decoration hides in combat')
local replacement,rp=target(); EllesmereUIUnitFrames_Target=replacement; fire('PLAYER_TARGET_CHANGED')
check(not t.shown and h:GetParent()==p,'stale portrait hidden and reparent deferred')
combat=false; fire('PLAYER_REGEN_ENABLED'); check(h:GetParent()==rp and t.shown,'reattach after combat')
enabled=false; D.Refresh(); check(not t.shown,'disable hides')
enabled=true; D.Refresh(); check(t.shown,'enable restores')
-- Fresh runtime observes saved style without rewriting user configuration.
C.Set('style','legacy'); enabled=false; load(); callbacks.init()
check(TwichUI.TargetArt.Get('style')=='legacy' and not TwichUI.TargetArtDisplay.Holder(),'reload preserves explicit legacy and disabled state')
check(legacy.x==17 and legacy.y==-9 and legacy.mapRare=='none','all lifecycle operations preserve saved legacy configuration')
print('TARGET PORTRAIT TESTS PASSED ('..checks..' checks)')
