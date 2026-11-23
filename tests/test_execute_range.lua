-- Source-shaped EUI fixtures, original stubs only. Not a combat/taint or visual certification.
local root = ROOT or '../!!!TwichUI/'
local checks = 0
local function check(value, why) checks = checks + 1; assert(value, why) end
local function near(a, b) check(math.abs(a - b) < 0.00001, tostring(a) .. ' ~= ' .. tostring(b)) end
local function Client(providerFirst)
    local c = { combat = false, frames = {}, timers = {}, health = {}, maximum = {}, enemy = {}, profiles = {} }
    setmetatable(c, { __index = _G }); c._G = c
    c.TwichUIDB = { modules = { executeRange = false }, ui = {} }
    local R = { init = {}, on = {}, Profiles = {} }; c.TwichUI = R
    function R:Enabled(key) return c.TwichUIDB.modules[key] == true end
    function R:OnInit(fn) self.init[#self.init + 1] = fn end
    function R:On(event, fn) self.on[event] = fn end
    function R.Fault(_, err) error(err) end
    function R.Profiles.OnApply(_, _, fn) c.profiles.apply = fn end
    function R.Profiles.OnChange(fn) c.profiles.change = fn end
    c.issecretvalue = function(v) return type(v) == 'table' and v.secret == true end
    c.InCombatLockdown = function() return c.combat end
    c.UnitCanAttack = function(_, unit) return c.enemy[unit] ~= false end
    c.UnitHealth = function(unit) return c.health[unit] or 80 end
    c.UnitHealthMax = function(unit) return c.maximum[unit] or 100 end
    c.C_Timer = { After = function(delay, fn) check(delay == 0, 'only one event-turn handoff'); c.timers[#c.timers + 1] = fn end }
    function c.Flush()
        local timers = c.timers; c.timers = {}
        for _, fn in ipairs(timers) do fn() end
    end
    function c.Frame(kind, parent, protected)
        local f = { kind = kind or 'Frame', parent = parent, protected = protected, shown = true,
            scripts = {}, hooks = {}, events = {}, textures = {}, w = 200, h = 24, orientation = 'HORIZONTAL', reverse = false }
        c.frames[#c.frames + 1] = f
        function f:GetObjectType() return self.kind end
        function f:GetParent() return self.parent end
        function f:GetWidth() return self.w end
        function f:GetHeight() return self.h end
        function f:GetOrientation() return self.orientation end
        function f:GetReverseFill() return self.reverse end
        function f:GetAttribute(key) return key == 'unit' and self.attribute end
        function f:IsProtected() return self.protected == true end
        function f:IsForbidden() return self.forbidden == true end
        function f:IsShown() return self.shown end
        function f:HookScript(event, fn) self.hooks[event] = self.hooks[event] or {}; table.insert(self.hooks[event], fn) end
        function f:SetScript(event, fn) self.scripts[event] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:Emit(event) for _, fn in ipairs(self.hooks[event] or {}) do fn(self) end end
        function f:Hide() self.shown = false; self:Emit('OnHide') end
        function f:Show() self.shown = true; self:Emit('OnShow') end
        function f:SetOrientation(v) self.orientation = v end
        function f:SetReverseFill(v) self.reverse = v end
        function f:Resize(w,h) self.w,self.h = w,h; self:Emit('OnSizeChanged') end
        -- Any layout or security write to provider frames is a regression.
        function f:SetPoint() error('provider anchor write') end
        function f:SetParent() error('provider parent write') end
        function f:SetSize() error('provider size write') end
        function f:SetAttribute() error('provider attribute write') end
        function f:CreateTexture(_, layer, _, sublevel)
            check(not (c.combat and self.protected), 'protected attachment deferred')
            local t = { parent = self, layer = layer, sublevel = sublevel }
            self.textures[#self.textures + 1] = t
            function t:SetColorTexture(...) self.color = {...} end
            function t:SetTexture(file) self.file = file; return true end
            function t:SetVertexColor(...) self.tint = {...} end
            function t:SetTexCoord(...) self.coords = {...} end
            function t:SetAlpha(alpha) self.alpha = alpha end
            function t:ClearAllPoints() check(not (c.combat and self.parent.protected), 'protected region layout deferred') end
            function t:SetPoint(point, bar, relative, x, y) self.point,self.bar,self.relative,self.x,self.y = point,bar,relative,x,y end
            function t:SetSize(w,h) self.w,self.h = w,h end
            return t
        end
        return f
    end
    c.CreateFrame = function(kind) return c.Frame(kind) end
    c.hooksecurefunc = function(object, method, after)
        local original = object[method]
        object[method] = function(...) original(...); after(...) end
    end
    function c.Fire(event, ...)
        for _, f in ipairs(c.frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end end
    end
    c.EllesmereNameplates_NS = { plates = {} }
    c.bases = {}
    c.C_NamePlate = { GetNamePlateForUnit = function(unit) return c.bases[unit] end }
    function c.Plate(unit, reuse)
        local base = c.Frame(); base.namePlateUnitToken = unit; c.bases[unit] = base
        local plate = reuse or c.Frame('Frame', base)
        plate.unit, plate.nameplate, plate.shown = unit, base, true
        plate.health = plate.health or c.Frame('StatusBar', plate, false)
        plate.UpdateHealthValues = plate.UpdateHealthValues or function(self) self.unit = self.nameplate.namePlateUnitToken end
        plate.health.shown = true
        c.EllesmereNameplates_NS.plates[unit] = plate
        return plate
    end
    local provider
    local function Provider()
        provider = c.Frame()
        provider:RegisterEvent('NAME_PLATE_UNIT_ADDED')
        provider:SetScript('OnEvent', function(_, _, unit) if c.pending then c.pending(unit); c.pending = nil end end)
    end
    if providerFirst then Provider() end
    for _, file in ipairs({ 'Config', 'Ellesmere', 'Display' }) do
        local fn = assert(loadfile(root .. 'execute/' .. file .. '.lua')); setfenv(fn, c); fn()
    end
    local C,D = R.ExecuteRange,R.ExecuteRangeDisplay
    function c.Enable(on) c.TwichUIDB.modules.executeRange = on; D.Refresh() end
    c.Enable(true)
    if not providerFirst then Provider() end
    return c,C,D,R.ExecuteRangeEllesmere
end

-- Fill geometry uses actual provider coordinates, including reverse/vertical fill.
do
    local c,C,D = Client(false)
    local plate = c.Plate('nameplate1'); D.Refresh()
    local bar = plate.health
    local marker,edge,fill = bar.textures[1],bar.textures[2],bar.textures[6]
    C.Set('threshold',25); C.Set('appearance','zone')
    near(fill.w,50); near(fill.h,24); near(fill.x,0)
    check(fill.alpha == .25 and marker.alpha == 0 and edge.alpha == 0,'restrained zone above threshold')
    for _,threshold in ipairs({1,20,35,100}) do
        C.Set('threshold',threshold); near(fill.w,bar.w*threshold/100)
    end
    C.Set('threshold',25)
    local healthGetter = c.UnitHealth
    c.UnitHealth = function() error('unavailable provider health') end
    D.Refresh(); check(fill.alpha > 0,'zone never reads health')
    C.Set('appearance','marker'); check(marker.alpha == .7,'legacy marker never reads health')
    c.UnitHealth = healthGetter
    C.Set('appearance','markerZoneEdge')
    check(marker.alpha == .7 and fill.alpha == .25 and edge.alpha == 0,'combined above range')
    c.health.nameplate1 = 25; c.Fire('UNIT_HEALTH','nameplate1')
    check(edge.alpha == .65,'combined active edge at threshold')
    C.Set('appearance','markerZone'); check(edge.alpha == 0 and marker.alpha == .7 and fill.alpha > 0)
    C.Set('color','80336699'); C.Set('opacity',60)
    near(fill.tint[1],.2); near(fill.tint[2],.4); near(fill.tint[3],.6); near(fill.tint[4],128/255); near(fill.alpha,.6)
    c.TwichUI.MenuStyle = { StatusBars = { Resolve = function(id) if id == 'Soft grain' then return 'registered-grain' end end } }
    C.Set('texture','Soft grain'); check(fill.file == 'registered-grain','registered texture resolved')
    C.Set('texture','Missing'); check(fill.file == 'Interface\\Buttons\\WHITE8X8' and C.Get('texture') == 'Missing','unavailable texture retained with flat fallback')
    for _,pair in ipairs({{'color','invalid'},{'opacity',101},{'opacity',-1},{'opacity',.5},{'texture','bad/path'},{'texture','bad\\path'},{'texture',string.rep('a',129)}}) do
        check(not C.Set(pair[1],pair[2]),'reject malformed fill preference')
    end
    C.Set('appearance','highlight')
    near(fill.w,50); check(marker.alpha == 0 and edge.alpha == 0,'active filled portion at threshold')
    c.health.nameplate1 = 10; c.Fire('UNIT_HEALTH','nameplate1'); near(fill.w,20)
    c.health.nameplate1 = 26; c.Fire('UNIT_HEALTH','nameplate1'); check(fill.alpha == 0,'health recovery clears active fill')
    c.health.nameplate1 = 0; c.Fire('UNIT_HEALTH','nameplate1'); check(fill.alpha == 0,'dead unit not highlighted')
    c.health.nameplate1 = {secret=true}; c.Fire('UNIT_HEALTH','nameplate1'); check(fill.alpha == 0,'secret health not highlighted')
    C.Set('appearance','zone'); check(fill.alpha > 0,'zone needs no health')
    bar:SetReverseFill(true); near(fill.x,150); near(fill.w,50)
    bar:SetOrientation('VERTICAL'); near(fill.y,18); near(fill.h,6); near(fill.w,200)
    bar:Resize(90,80); near(fill.y,60); near(fill.h,20); near(fill.w,90)
    bar:SetReverseFill(false); near(fill.y,0); near(fill.h,20)
    -- Scale is inherited, not multiplied into provider-local geometry.
    bar.scale = 1.75; D.Refresh(); near(fill.h,20)
    local total = #bar.textures
    for _=1,10 do C.Set('appearance','highlight'); C.Set('appearance','markerZoneEdge') end
    check(#bar.textures == total and total == 6,'style changes reuse one fill')
    c.EllesmereNameplates_NS.plates.nameplate1 = nil; c.bases.nameplate1 = nil
    c.Fire('NAME_PLATE_UNIT_REMOVED','nameplate1'); check(fill.alpha == 0,'removal clears fill')
    c.Plate('nameplate2',plate); c.health.nameplate2 = 80; C.Set('appearance','highlight'); D.Refresh()
    check(fill.alpha == 0,'recycled bar cannot retain previous active health')
    c.health.nameplate2 = 5; c.Fire('UNIT_HEALTH','nameplate2'); near(fill.h,4)
    c.Enable(false); check(fill.alpha == 0,'disabled cleans fill')
    local target = c.Frame('Button',nil,true); target.attribute = 'target'
    target.Health = c.Frame('StatusBar',target,true); c.EllesmereUIUnitFrames_Target = target
    c.health.target = 15; c.Enable(true); C.Set('appearance','highlight')
    local tf,te = target.Health.textures[6],target.Health.textures[2]
    near(tf.w,30)
    c.combat = true; c.health.target = 10; c.Fire('UNIT_HEALTH','target')
    check(tf.alpha == 0 and te.alpha == .65 and select(5,D.Status()),'protected changed fill uses safe legacy edge')
    c.health.target = 26; c.Fire('UNIT_HEALTH','target'); check(tf.alpha == 0 and te.alpha == 0,'fallback clears on recovery')
    c.combat = false; c.health.target = 10; c.Fire('PLAYER_REGEN_ENABLED'); near(tf.w,20)
    check(tf.alpha > 0 and te.alpha == 0,'safe layout restores filled highlight')
    c.Enable(false)
    -- Shared preview renderer neither discovers providers nor persists settings.
    local sample = c.Frame(); local decoration = D.CreateDecoration(sample)
    D.Preview(decoration,300,30,.1); near(decoration.fill.w,30)
    check(not c.TwichUIDB.modules.executeRange,'sample does not enable feature')
end
for _, providerFirst in ipairs({ false, true }) do
    local c,C,D,E = Client(providerFirst)
    local target = c.Frame('Button', nil, true); target.attribute = 'target'
    local clip = c.Frame('Frame', target, true)
    target.Health = c.Frame('StatusBar', clip, true); c.EllesmereUIUnitFrames_Target = target
    D.Refresh()
    local marker, edge = target.Health.textures[1], target.Health.textures[2]
    check(marker and marker.bar == target.Health and marker.alpha > 0, 'actual nested target health bar')
    near(marker.x,39.5); near(marker.h,24)
    target.Health:Hide(); check(marker.alpha == 0,'hidden bar clears its regions')
    target.Health:Show(); c.Flush(); check(marker.alpha > 0,'shown bar rediscovers its verified owner')
    check(edge.alpha == 0, 'above threshold not active')
    c.health.target = 20; c.Fire('UNIT_HEALTH','target'); check(edge.alpha > 0,'inclusive threshold')
    c.health.target = 21; c.Fire('UNIT_HEALTH','target'); check(edge.alpha == 0,'leave range')
    c.combat = true; c.health.target = 19; c.Fire('UNIT_HEALTH','target'); check(edge.alpha > 0,'plain health updates do not write protected geometry')
    local secret = setmetatable({ secret = true }, { __lt = function() error('secret comparison') end, __div = function() error('secret arithmetic') end })
    c.health.target = secret; c.Fire('UNIT_HEALTH','target')
    check(edge.alpha == 0 and marker.alpha > 0, 'restricted health hides active only')
    check(select(4,D.Status()) == true, 'restricted health status')
    C.Set('threshold',35); check(marker.alpha == 0,'protected geometry change hides pending marker')
    check(select(5,D.Status()) == true,'pending protected geometry status')
    c.combat = false; c.Fire('PLAYER_REGEN_ENABLED'); near(marker.x,69.5)
    target.Health:SetReverseFill(true); near(marker.x,129.5)
    target.Health:SetOrientation('VERTICAL'); near(marker.y,15.1); near(marker.w,200)
    target.Health:Resize(180,60); near(marker.y,38.5); near(marker.w,180)
    target.Health:SetReverseFill(false); near(marker.y,20.5)
    C.Set('appearance','active'); check(marker.alpha == 0,'active-only mode')
    C.Set('appearance','marker'); check(marker.alpha > 0 and edge.alpha == 0,'marker-only mode')
    C.Set('appearance','both')
    c.enemy.target = false; c.Fire('PLAYER_TARGET_CHANGED'); check(marker.alpha == 0,'friendly target hidden')
    c.enemy.target = true; c.Fire('PLAYER_TARGET_CHANGED'); check(marker.alpha > 0,'enemy target restored')

    -- Native event ordering: TwichUI may run before EUI adds its registry entry.
    local plate
    c.pending = function(unit) plate = c.Plate(unit) end
    c.combat = true
    c.Fire('NAME_PLATE_UNIT_ADDED','nameplate1'); c.Flush()
    check(plate and plate.health.textures[1].alpha > 0,'first above-threshold nameplate appears after one event turn')
    local pm = plate.health.textures[1]
    c.health.nameplate1 = 35; c.Fire('UNIT_HEALTH','nameplate1'); check(plate.health.textures[2].alpha > 0,'nameplate crossing in combat-shaped fixture')
    C.Set('target',false); check(marker.alpha == 0 and pm.alpha > 0,'independent placement')
    C.Set('nameplates',false); check(pm.alpha == 0,'nameplates can be independently disabled')
    C.Set('nameplates',true); check(pm.alpha > 0,'enable discovers existing registry')
    c.EllesmereNameplates_NS.plates.nameplate1 = nil; c.bases.nameplate1 = nil
    plate.unit,plate.nameplate = nil,nil
    c.Fire('NAME_PLATE_UNIT_REMOVED','nameplate1'); check(pm.alpha == 0,'removal after provider deletes registry')
    c.pending = function(unit) c.Plate(unit,plate) end
    c.Fire('NAME_PLATE_UNIT_ADDED','nameplate2'); c.Flush()
    check(pm.alpha > 0 and #plate.health.textures == 6,'pool reuse keeps exactly one overlay set')
    plate.nameplate.namePlateUnitToken = 'nameplate3'
    plate:UpdateHealthValues(); check(pm.alpha == 0,'provider token swap hides old occupant on same update')
    plate.nameplate.namePlateUnitToken = 'nameplate2'; plate:UpdateHealthValues(); D.Refresh(); check(pm.alpha > 0)
    c.Fire('NAME_PLATE_UNIT_ADDED','nameplate2'); c.Enable(false); c.Flush()
    check(pm.alpha == 0 and D.Status() == 'off','disable cancels queued work')
    for _, f in ipairs(c.frames) do if f.scripts.OnEvent ~= nil and f ~= c.frames[#c.frames] then
        -- Provider may still listen; the display event frame must be unregistered.
        if f.events.UNIT_HEALTH then error('health listener retained while disabled') end
    end end
    c.Enable(true); c.Fire('NAME_PLATE_UNIT_ADDED','nameplate2')
    c.TwichUIDB.ui.executeRange = { target = false, nameplates = false }
    c.profiles.change('duplicate'); c.Flush(); check(pm.alpha == 0,'profile identity invalidates queued owner state')
    c.TwichUIDB.ui.executeRange = {}; c.profiles.apply(); check(pm.alpha > 0,'profile application follows current settings')
    c.combat = false
    target.Health.forbidden = true; C.Set('target',true); check(marker.alpha == 0,'forbidden provider hidden')
    target.Health.forbidden = false
    target.Health.orientation = 'HORIZONTAL'
    local originalParent = target.Health.GetParent
    target.Health.GetParent = function() error('provider rebuilding') end
    D.Refresh(); check(marker.alpha == 0,'resolver error hides old overlay')
    local extra = c.Plate('nameplate4'); D.Refresh()
    check(extra.health.textures[1].alpha > 0,'broken target resolver does not suppress valid nameplates')
    target.Health.GetParent = originalParent
    D.Refresh(); check(marker.alpha > 0,'resolver error does not latch refresh guard')
    target.Health.orientation = 'UNKNOWN'; D.Refresh(); check(marker.alpha == 0,'unknown orientation fails closed')
    c.EllesmereUIUnitFrames_Target = c.Frame('Button'); D.Refresh(); check(marker.alpha == 0,'unrecognised target never substituted')
    check(not C.Set('threshold',0) and not C.Set('threshold',101) and not C.Set('threshold',0/0)
        and not C.Set('threshold',math.huge) and not C.Set('threshold',20.5),'invalid threshold rejected')
    for _, value in ipairs({1,25,35,99,100}) do check(C.Set('threshold',value) and C.Get('threshold') == value,'arbitrary whole threshold') end
    C.Set('nameplates',false); C.ResetSettings(); check(C.Get('threshold') == 20 and C.Get('nameplates') and c.TwichUIDB.modules.executeRange,'reset preserves switch')
    c.Enable(false)
end
do
    local c,C,D = Client(false)
    local target = c.Frame('Button',nil,true); target.attribute = 'target'
    target.Health = c.Frame('StatusBar',target,true); c.EllesmereUIUnitFrames_Target = target
    c.combat = true; D.Refresh(); check(#target.Health.textures == 0,'first protected target attachment waits out combat')
    c.combat = false; c.Fire('PLAYER_REGEN_ENABLED'); check(#target.Health.textures == 6,'protected target attaches after combat')
    -- No unbounded accumulation when a provider continually replaces its bars.
    for _ = 1,140 do target.Health = c.Frame('StatusBar',target,true); D.Refresh() end
    check(#target.Health.textures == 0,'retired-provider bar allocation has a hard cap')
end
do
    local c,C,D = Client(false)
    c.enemy.nameplate1 = false
    c.Fire('NAME_PLATE_UNIT_ADDED','nameplate1'); c.Flush()
    local plate
    c.pending = function(unit) plate = c.Plate(unit) end
    -- Provider promotion may run after TwichUI's faction handler.
    local provider = c.Frame(); provider:RegisterEvent('UNIT_FACTION')
    provider:SetScript('OnEvent',function(_,_,unit) if c.pending then c.pending(unit); c.pending = nil end end)
    c.enemy.nameplate1 = true; c.Fire('UNIT_FACTION','nameplate1'); c.Flush()
    check(plate.health.textures[1].alpha > 0,'late friendly-to-enemy promotion attaches after provider event')
    c.enemy.nameplate1 = false; c.Fire('UNIT_FACTION','nameplate1')
    check(plate.health.textures[1].alpha == 0,'enemy-to-friendly transition hides immediately')
end
print('PASSED: ' .. checks .. ' execute range checks')
