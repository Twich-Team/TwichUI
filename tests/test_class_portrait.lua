-- Synthetic lifecycle and geometry; cannot establish real-client visuals/taint.
local root = ROOT or '../!!!TwichUI/'
local checks = 0
local function check(v, msg) checks = checks + 1; assert(v, msg) end
local function near(a,b) check(math.abs(a-b)<0.00001, tostring(a)..' ~= '..tostring(b)) end
local made, timers, combat, hooks, classQueries = {}, {}, false, {}, 0
local playerClass = 'WARRIOR'
local function frame(parent)
    local f = { parent = parent, w = 52, h = 52, shown = true, scripts = {}, events = {}, hooks = {}, level = 10 }
    made[#made+1] = f
    function f:GetObjectType() return 'Frame' end
    function f:GetWidth() return self.w end
    function f:GetHeight() return self.h end
    function f:GetParent() return self.parent end
    function f:GetAttribute(k) return k == 'unit' and self.unit end
    function f:HookScript(e, fn) self.hooks[e] = fn end
    function f:SetScript(e, fn) self.scripts[e] = fn end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetParent(p) check(not combat, 'reparent in combat'); self.parent = p end
    function f:SetAllPoints(p) check(not combat, 'anchor in combat'); self.all = p end
    function f:ClearAllPoints() check(not combat, 'clear in combat') end
    function f:EnableMouse(v) self.mouse = v end
    function f:GetFrameLevel() return self.level end
    function f:GetFrameStrata() return 'MEDIUM' end
    function f:SetFrameLevel(v) self.level = v end
    function f:SetFrameStrata(v) self.strata = v end
    function f:CreateTexture()
        self.texCount = (self.texCount or 0)+1
        local t = frame(self)
        function t:SetTexture(path) self.path = path; return not self.fail end
        function t:SetPoint(_, p, _, x, y) self.anchor,self.x,self.y = p,x,y end
        function t:SetSize(w,h) check(not combat, 'resize in combat'); self.w,self.h = w,h end
        function t:Show() self.shown = true end
        function t:Hide() self.shown = false end
        return t
    end
    return f
end
CreateFrame = function(_,_,p) return frame(p) end
C_Timer = { After = function(_, fn) timers[#timers+1] = fn end }
InCombatLockdown = function() return combat end
UnitClass = function() classQueries = classQueries+1; return 'Localized class', playerClass end
TwichUIDB = {}
TwichUI = { PATH = 'Interface\\AddOns\\!!!TwichUI\\', Life = { loggedIn = true },
    OnInit = function(_,fn) hooks.init = fn end, On = function(_,e,fn) hooks[e] = fn end,
    Profiles = { OnApply = function(_,_,fn) hooks.profile = fn end },
    OnSettingsClosed = function(fn) hooks.close = fn end }
dofile(root..'classportrait/Config.lua'); dofile(root..'classportrait/Art.lua'); dofile(root..'classportrait/Display.lua')
local C,D = TwichUI.ClassPortrait,TwichUI.ClassPortraitDisplay
local function event(e)
    for _,f in ipairs(made) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f,e) end end
end
local function player()
    local f = frame(); f.unit = 'player'
    f.Portrait = { backdrop = frame(f) }
    return f, f.Portrait.backdrop
end
check(C.Get('enabled') == false, 'off default'); check(C.Get('automatic'), 'auto default')
hooks.init(); check(not D.Holder(), 'lazy while off')
C.Set('enabled', true); check(D.Status() == 'missing', 'absent safe')
local f,p = player(); EllesmereUIUnitFrames_Player = f
event('ADDON_LOADED'); for _,fn in ipairs(timers) do fn() end; timers = {}
check(D.Status() == 'ready', 'delayed attach'); check(D.Holder():GetParent() == p, 'portrait parent')
local holder,t = D.Holder(),D.Texture()
check(holder.mouse == false and holder.level < f.level, 'inert, behind frame')
check(t.path:match('WARRIOR$'), 'own artwork'); check(holder.texCount == 1, 'one texture')
local count = 0
for token,a in pairs(C.ART) do
    count = count+1
    local size,x,y = C.Placement(token,52,52)
    local factor = size/a.canvas
    near((a.x/a.canvas-0.5)*size+x,0); near((0.5-a.y/a.canvas)*size+y,0)
    check(a.w*factor >= 52-0.00001 and a.h*factor >= 52-0.00001, 'portrait contained '..token)
    check(io.open(root..'media/classportrait/'..token..'.tga','rb') ~= nil, 'mapped texture exists')
end
check(count == 9 and not C.ART.DEATHKNIGHT, 'exact nine classes')
local base = t.w
C.Set('x',12); C.Set('y',-7); local _,x,y = C.Placement('WARRIOR',52,52)
near(t.x,x); near(t.y,y)
C.Set('size',120); near(t.w,base*1.2)
check(TwichUIDB.ui.classPortrait.x == 12, 'persisted in profile')
local saved = TwichUIDB; TwichUIDB = { ui = { classPortrait = { enabled = false, size = 0/0, x = 'bad' } } }
hooks.profile(); check(not t.shown, 'profile disables'); check(C.Get('size') == 100 and C.Get('x') == 0, 'invalid fallback')
TwichUIDB = saved; hooks.profile(); check(t.shown and C.Get('x') == 12, 'profile restored')
C.Reset(); check(C.Get('automatic') and C.Get('enabled') and C.Get('x') == 0 and C.Get('y') == 0, 'reset preserves enabled'); near(t.w,base)
p.w,p.h = 104,104; p.hooks.OnSizeChanged(); near(t.w,base*2)
-- Scaling inherits via parent, no SetScale or effective-scale multiplication.
check(holder.parent == p and t.anchor == p, 'single coordinate space')
local f2,p2 = player(); EllesmereUIUnitFrames_Player = f2
combat = true; event('UI_SCALE_CHANGED'); check(not t.shown, 'hide stale in combat'); check(holder.parent == p, 'defer reparent')
combat = false; event('PLAYER_REGEN_ENABLED'); check(holder.parent == p2 and t.shown, 'reattach after combat')
combat = true; event('PLAYER_REGEN_DISABLED'); check(t.shown, 'existing art remains in combat')
C.Set('size',130); check(t.shown, 'combat edit deferred'); combat = false; event('PLAYER_REGEN_ENABLED'); near(t.w,base*1.3)
for i=1,10 do D.Refresh() end
check(D.Holder() == holder and holder.texCount == 1, 'no duplicates'); check(classQueries == 1, 'class cached')
f2.unit = 'target'; D.Refresh(); check(not t.shown and D.Status() == 'missing', 'reject unrelated frame')
f2.unit = 'player'; D.Refresh()
C.Set('enabled',false); check(not t.shown, 'disabled hidden'); D.PreviewStart(); check(t.shown, 'preview while off')
hooks.close(); check(not t.shown, 'preview cleanup')
D.PreviewStart(); combat = true; event('PLAYER_REGEN_DISABLED'); check(not D.PreviewActive() and not t.shown, 'preview stops in combat'); combat = false
C.Set('enabled',true); t.fail = true; D.texturePath = nil; D.Refresh(); check(D.Status() == 'texture' and not t.shown, 'missing texture safe')
t.fail = false; D.Refresh(); check(t.shown, 'texture retry')
check(not C.Set('size',200) and not C.Set('enabled',1), 'invalid setters rejected')
-- A fresh runtime for every class, including unsupported ones. Never retain the
-- previous class's texture when a new session has an unsupported token.
for _,token in ipairs({'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','SHAMAN','MAGE','WARLOCK','DRUID','DEATHKNIGHT'}) do
    playerClass = token
    dofile(root..'classportrait/Display.lua')
    local display = TwichUI.ClassPortraitDisplay
    display.Refresh()
    if C.ART[token] then
        check(display.Status() == 'ready' and display.Texture().path:match(token..'$'), 'class selection '..token)
    else check(display.Status() == 'class' and not display.Holder(), 'unsupported class stays inactive') end
end
print('class portrait: '..checks..' checks passed')

print("PASSED")
