-- TwichUI: class resource bars, effects
-- Optional decoration that reacts to a resource's state and never decides anything about it: an effect reads the
-- normalized state the controller already has (key, cur, max), draws on the bar's effect layer (a frame above the
-- fill and below the text, so a value is always readable and the bar's edges stay where they are) and is
-- forgotten without a trace when it stops. Off until turned on (Effects tab); with it off no effect object exists
-- and nothing runs. The bar is complete without any of this.
--
-- What is drawn, honestly: these are flat tinted textures and, for the Mage preset, a few small star-shaped glow
-- textures (Blizzard's own Interface\Cooldown\star4, the one its cooldown "bling" uses) that rise and fade. They
-- are particle-like, not a particle system: the game's model and particle APIs are not used and no asset of ours
-- is added. Motion runs on the shared driver (Anim.lua) only while an effect is playing.
--
-- An effect is a table registered with FX.Register:
--   id, setting      its name, and the shared setting (a boolean in Config.lua) that turns it on
--   Applies(view, ctx, slot)   whether it belongs on this bar for this resource (a class preset says which class)
--   Attach(bar)      make its objects, once per bar, and return its instance (a table with a Step function if animated)
--   Update(inst, view, quiet)  see the state; play on a real transition. quiet: only note the state (no play)
--   Play(inst, trigger)        play now ("test" from settings, or the transition's name)
--   Stop(inst)       halt, hide, forget what it had noted (the next state is a fresh start)
--   Release(inst)    Stop and let go of anything borrowed; the instance's own objects are kept for next time
-- Objects are made once per bar and reused: no texture is created while the bars are in use after the first play.
--
-- Triggers fire on a transition only: a value rising through the threshold (Rising below), never on every event,
-- never for the first value seen after a login, zone, resource change or target change (quiet), and not again until
-- the value has dropped well below the threshold (so a small spend and refill is not a new transition).
--
-- Reduced motion (its own setting, Effects tab): nothing moves. The pulse becomes a brief steady highlight and the
-- Mage preset's motes are not drawn.

local R = TwichUI
local CB = R.ClassBars
local A = R.ClassBarAnim
local FX = {}
R.ClassBarEffects = FX

local WHITE = [[Interface\Buttons\WHITE8x8]]
local STAR = [[Interface\Cooldown\star4]]   -- Blizzard's own cooldown bling texture (Cooldown.xml)
local PI = math.pi

-- Settings are read through a table that is thrown away when the configuration changes (CB.Rev), so a resource tick
-- costs table lookups, not validation.
local cfg, cfgRev = {}, 0
local function Cfg(key)
    local rev = CB.Rev()
    if rev ~= cfgRev then
        for k in pairs(cfg) do cfg[k] = nil end
        cfgRev = rev
    end
    local v = cfg[key]
    if v == nil then
        v = CB.Get(key)
        cfg[key] = v
    end
    return v
end

local presets, order = {}, {}
local registry = {}   -- the bars that have effect objects, so StopAll can reach them (at most one per slot)

function FX.Reduced() return Cfg("effectsReducedMotion") end
function FX.Enabled() return Cfg("effects") end

function FX.Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or presets[def.id] then return false, "id" end
    for _, fn in ipairs({ "Applies", "Attach", "Update", "Play", "Stop", "Release" }) do
        if type(def[fn]) ~= "function" then return false, fn end
    end
    if type(def.setting) ~= "string" or CB.DEFAULTS[def.setting] == nil then return false, "setting" end
    presets[def.id] = def
    order[#order + 1] = def
    return true
end

function FX.Presets() return order end

-- A rising crossing of threshold (percent). inst keeps what it needs between calls: primed, armed, pct. Pure apart
-- from that. quiet notes the value without ever returning true.
function FX.Rising(inst, pct, threshold, quiet)
    local before = inst.pct
    inst.pct = pct
    if quiet or not inst.primed then
        inst.primed = true
        inst.armed = pct < threshold
        return false
    end
    if inst.armed then
        if pct >= threshold and before ~= nil and before < threshold then
            inst.armed = false
            return true
        end
    elseif pct < threshold * 0.9 then
        inst.armed = true
    end
    return false
end

local function Percent(view)
    if view.max and view.max > 0 then return view.cur / view.max * 100 end
    return 0
end

local function Entry(bar, def)
    local entries = bar.fxEntries
    if not entries then
        entries = {}
        bar.fxEntries = entries
        registry[#registry + 1] = bar
    end
    local e = entries[def.id]
    if not e then
        e = { inst = def.Attach(bar), attached = false }
        entries[def.id] = e
    end
    return e
end

local function Each(bar, fn)
    local entries = bar.fxEntries
    if not entries then return end
    for _, def in ipairs(order) do
        local e = entries[def.id]
        if e then fn(def, e) end
    end
end

---------------------------------------------------------------------------
-- The controller's calls
---------------------------------------------------------------------------

-- The state changed: let the effects that belong on this bar see it. quiet: a start, not a transition.
function FX.Update(bar, view, ctx, quiet)
    if not FX.Enabled() then
        FX.Stop(bar)
        return
    end
    for _, def in ipairs(order) do
        if Cfg(def.setting) and def.Applies(view, ctx, bar.slot) then
            local e = Entry(bar, def)
            e.attached = true
            def.Update(e.inst, view, quiet)
        else
            local e = bar.fxEntries and bar.fxEntries[def.id]
            if e and e.attached then
                def.Release(e.inst)
                e.attached = false
            end
        end
    end
end

-- A different resource, a new profile: every effect on the bar starts over (nothing noted, nothing playing).
function FX.Reset(bar)
    Each(bar, function(def, e) def.Stop(e.inst) end)
end

function FX.Stop(bar)
    Each(bar, function(def, e)
        def.Stop(e.inst)
        e.attached = false
    end)
end

function FX.StopAll()
    for _, bar in ipairs(registry) do FX.Stop(bar) end
end

-- Plays the effects that belong on this bar now, for the Test button. Returns how many.
function FX.Test(bar, view, ctx)
    if not FX.Enabled() then return 0 end
    local n = 0
    for _, def in ipairs(order) do
        if Cfg(def.setting) and def.Applies(view, ctx, bar.slot) then
            local e = Entry(bar, def)
            e.attached = true
            def.Play(e.inst, "test")
            n = n + 1
        end
    end
    return n
end

-- What an object holds for the troubleshooting report and the tests: { bars, entries }.
function FX.Count()
    local n = 0
    for _, bar in ipairs(registry) do
        for _ in pairs(bar.fxEntries or {}) do n = n + 1 end
    end
    return #registry, n
end

---------------------------------------------------------------------------
-- The generic accent: a brief highlight over the bar when its resource rises through the threshold (full by
-- default). Any bar, any resource: the Rogue's combo points complete, a Warrior's rage reaches the top.
---------------------------------------------------------------------------
local ACCENT_PEAK, ACCENT_TIME, ACCENT_STILL = 0.30, 0.5, 0.35

local function AccentStep(self, dt)
    self.t = self.t + dt
    local u = self.t / self.dur
    if u >= 1 then
        self.glow:Hide()
        return true
    end
    local a
    if self.reduced then a = ACCENT_PEAK * 0.7 else a = ACCENT_PEAK * math.sin(PI * u) end
    self.glow:SetAlpha(a)
    return false
end

local accent = { id = "accent", setting = "effectsAccent" }

function accent.Applies() return true end

function accent.Attach(bar)
    local glow = bar.fx:CreateTexture(nil, "ARTWORK", nil, 3)
    glow:SetTexture(WHITE)
    glow:SetBlendMode("ADD")
    glow:Hide()
    return { bar = bar, glow = glow, t = 0, dur = ACCENT_TIME, Step = AccentStep }
end

function accent.Play(inst)
    local bar, s = inst.bar, inst.bar.style
    if not s then return end
    inst.reduced = FX.Reduced()
    inst.dur = inst.reduced and ACCENT_STILL or ACCENT_TIME
    inst.t = 0
    local lift = 0.4   -- toward white, so it reads on its own fill
    inst.glow:ClearAllPoints()
    inst.glow:SetPoint("TOPLEFT", bar.fx, "TOPLEFT", bar.edge, -bar.edge)
    inst.glow:SetPoint("BOTTOMRIGHT", bar.fx, "BOTTOMRIGHT", -bar.edge, bar.edge)
    inst.glow:SetVertexColor(s.r + (1 - s.r) * lift, s.g + (1 - s.g) * lift, s.b + (1 - s.b) * lift, 1)
    inst.glow:SetAlpha(0)
    inst.glow:Show()
    if not A.Add(inst) then inst.glow:Hide() end   -- the driver is full: no accent, rather than a stuck one
end

function accent.Update(inst, view, quiet)
    if FX.Rising(inst, Percent(view), Cfg("effectsThreshold"), quiet) then accent.Play(inst) end
end

function accent.Stop(inst)
    A.Remove(inst)
    inst.glow:Hide()
    inst.primed, inst.armed, inst.pct = nil, nil, nil
end
accent.Release = accent.Stop

FX.Register(accent)

---------------------------------------------------------------------------
-- Mage: frost motes. When the Mage's mana comes back up to full, a few small glints rise from the bar and fade.
-- Only the Mage's mana bar. Needs motion, so it draws nothing under reduced motion (the accent still plays).
---------------------------------------------------------------------------
local MOTES, MOTE_SIZE, MOTE_RISE = 6, 8, 12
local FROST = { 0.70, 0.88, 1.0 }

local function FrostStep(self, dt)
    local bar = self.bar
    local live = false
    for i = 1, MOTES do
        local m = self.motes[i]
        if m.on then
            m.t = m.t + dt
            if m.t >= m.life then
                m.on = false
                m.tex:Hide()
            elseif m.t >= 0 then
                live = true
                local u = m.t / m.life
                m.tex:SetAlpha(0.75 * math.sin(PI * u))
                m.tex:ClearAllPoints()
                m.tex:SetPoint("CENTER", bar.fx, "BOTTOMLEFT",
                    bar.edge + m.x + 2 * math.sin(2 * PI * u + i), bar.edge + bar.innerH * 0.5 + u * (MOTE_RISE + bar.innerH * 0.5))
                m.tex:Show()
            else
                live = true   -- waiting its turn
            end
        end
    end
    return not live
end

local frost = { id = "frost", setting = "effectsClass" }

function frost.Applies(view, ctx, slot)
    return ctx.class == "MAGE" and view.key == "MANA" and slot == "primary"
end

function frost.Attach(bar)
    local inst = { bar = bar, motes = {}, Step = FrostStep }
    for i = 1, MOTES do
        local tex = bar.fx:CreateTexture(nil, "ARTWORK", nil, 3)
        tex:SetTexture(STAR)
        tex:SetBlendMode("ADD")
        tex:SetSize(MOTE_SIZE, MOTE_SIZE)
        tex:SetVertexColor(FROST[1], FROST[2], FROST[3], 1)
        tex:Hide()
        inst.motes[i] = { tex = tex, on = false, t = 0, life = 1, x = 0 }
    end
    return inst
end

function frost.Play(inst)
    if FX.Reduced() then return end
    local bar = inst.bar
    if not bar.innerW then return end
    for i = 1, MOTES do
        local m = inst.motes[i]
        m.on = true
        m.t = -(i - 1) * 0.07                     -- staggered starts
        m.life = 0.9 + 0.08 * (i % 3)
        m.x = bar.innerW * (i - 0.5) / MOTES      -- spread along the bar
        m.tex:SetAlpha(0)
    end
    if not A.Add(inst) then
        for i = 1, MOTES do inst.motes[i].on = false end
    end
end

function frost.Update(inst, view, quiet)
    if FX.Rising(inst, Percent(view), 100, quiet) then frost.Play(inst) end
end

function frost.Stop(inst)
    A.Remove(inst)
    for i = 1, MOTES do
        local m = inst.motes[i]
        m.on = false
        m.tex:Hide()
    end
    inst.primed, inst.armed, inst.pct = nil, nil, nil
end
frost.Release = frost.Stop

FX.Register(frost)
