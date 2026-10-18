-- TwichUI: class resource bars, effects
-- Optional decoration that reacts to a resource's state and never decides anything about it: an effect reads the
-- normalized state the controller already has (key, cur, max), draws on the bar's effect layer (a frame above the
-- fill and below the text, so a value is always readable and the bar's edges stay where they are) and is
-- forgotten without a trace when it stops. Off until turned on (Effects tab); with it off no effect object exists
-- and nothing runs. The bar is complete without any of this.
--
-- What is drawn, honestly: these are flat tinted textures and, for the Mage preset, a few small star-shaped glow
-- textures (Blizzard's own Interface\Cooldown\star4, the one its cooldown "bling" uses) that rise and fade, and for the
-- Rogue preset, a thin bright edge with a fading streak that slides along the combo point bar. They
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

---------------------------------------------------------------------------
-- Rogue: the blade's glint. When the combo points are all lit, a thin bright edge with a short trailing streak
-- slides once across the combo bar, like light running along a blade. Only the Rogue's combo point bar (a Druid in
-- Cat Form has the same bar but no class touch of its own yet). Needs motion, so it draws nothing under reduced
-- motion (the highlight still plays).
---------------------------------------------------------------------------
local GLINT_TIME, GLINT_EDGE, GLINT_TRAIL = 0.45, 3, 16
local STEEL = { 0.92, 0.94, 1.0 }

local function GlintStep(self, dt)
    local bar = self.bar
    self.t = self.t + dt
    local u = self.t / GLINT_TIME
    if u >= 1 then
        self.edge:Hide()
        self.trail:Hide()
        return true
    end
    local a = math.sin(PI * u)
    local x = bar.edge + u * math.max(0, bar.innerW - GLINT_EDGE)
    self.edge:ClearAllPoints()
    self.edge:SetPoint("LEFT", bar.fx, "LEFT", x, 0)
    self.edge:SetAlpha(0.85 * a)
    self.trail:SetAlpha(0.35 * a)
    return false
end

local glint = { id = "glint", setting = "effectsClass" }

function glint.Applies(view, ctx, slot)
    return ctx.class == "ROGUE" and view.key == "COMBO_POINTS" and slot == "secondary"
end

function glint.Attach(bar)
    local edge = bar.fx:CreateTexture(nil, "ARTWORK", nil, 3)
    edge:SetTexture(WHITE)
    edge:SetBlendMode("ADD")
    edge:SetVertexColor(STEEL[1], STEEL[2], STEEL[3], 1)
    edge:Hide()
    local trail = bar.fx:CreateTexture(nil, "ARTWORK", nil, 3)
    trail:SetTexture(WHITE)
    trail:SetBlendMode("ADD")
    trail:SetVertexColor(STEEL[1], STEEL[2], STEEL[3], 1)
    if CreateColor and trail.SetGradient then   -- fades out behind the edge
        trail:SetGradient("HORIZONTAL", CreateColor(STEEL[1], STEEL[2], STEEL[3], 0), CreateColor(STEEL[1], STEEL[2], STEEL[3], 1))
    end
    trail:Hide()
    return { bar = bar, edge = edge, trail = trail, t = 0, Step = GlintStep }
end

function glint.Play(inst)
    if FX.Reduced() then return end
    local bar = inst.bar
    if not bar.innerW then return end
    inst.t = 0
    inst.edge:SetSize(GLINT_EDGE, bar.innerH)
    inst.edge:SetAlpha(0)
    inst.edge:Show()
    inst.trail:ClearAllPoints()
    inst.trail:SetPoint("RIGHT", inst.edge, "LEFT", 0, 0)   -- follows the edge
    inst.trail:SetSize(GLINT_TRAIL, bar.innerH)
    inst.trail:SetAlpha(0)
    inst.trail:Show()
    if not A.Add(inst) then
        inst.edge:Hide()
        inst.trail:Hide()
    end
end

function glint.Update(inst, view, quiet)
    if FX.Rising(inst, Percent(view), 100, quiet) then glint.Play(inst) end
end

function glint.Stop(inst)
    A.Remove(inst)
    inst.edge:Hide()
    inst.trail:Hide()
    inst.primed, inst.armed, inst.pct = nil, nil, nil
end
glint.Release = glint.Stop

FX.Register(glint)

---------------------------------------------------------------------------
-- Rogue: venom drips. When combo points are spent (the count falls to 0 through a real power change), one drop falls
-- down the combo bar for each point that was spent, staggered, each with a few soft green puffs drifting around it,
-- and they fade. It is decoration tied to what the bar really knows, the points going away; it says nothing about
-- whether any poison is applied, which the bars cannot see. The Rogue's combo bar only; nothing under reduced motion.
-- Setting: effectsPoison.
-- The two textures are ours (media\classbars\): venom-drip.tga is the project's own rendered drop, scaled down to
-- 32x128, and venom-puff.tga a generated soft cloud puff (32x32, white, tinted when drawn). The puffs are the
-- "particle cloud": particle-like tinted textures moved by the shared driver, not the game's particle system. At most
-- 5 drops and 15 puffs exist, made once per bar.
---------------------------------------------------------------------------
local DRIP_TEXTURE = R.PATH .. [[media\classbars\venom-drip.tga]]
local PUFF_TEXTURE = R.PATH .. [[media\classbars\venom-puff.tga]]
local DRIPS, PUFFS, DRIP_LIFE, DRIP_DELAY = 5, 3, 0.75, 0.07
local VENOM = { 0.5, 0.9, 0.25 }
local DRIP_COLUMNS = { 3, 1, 5, 2, 4 }   -- fewer drops spread out instead of bunching on the left
-- where each puff sits around the drop's bulb (pixels at a 28 px drop), and where it drifts to
local PUFF_AT = { { -7, 2 }, { 7, -1 }, { 2, -8 } }

local function DripStep(self, dt)
    local bar = self.bar
    local live = false
    local fall = bar.innerH
    local k = self.dh / 28
    for i = 1, DRIPS do
        local d = self.drips[i]
        if d.on then
            d.t = d.t + dt
            if d.t >= DRIP_LIFE * 1.2 then
                d.on = false
                d.tex:Hide()
                for j = 1, PUFFS do d.puffs[j]:Hide() end
            elseif d.t >= 0 then
                live = true
                local u = math.min(1, d.t / DRIP_LIFE)
                local bulbY = -(bar.edge + u * u * fall)            -- the bulb speeds up as it falls
                local x = bar.edge + d.x
                -- the drop: opaque, fading out over the last 40%
                d.tex:SetAlpha(math.min(1, u * 8) * (u < 0.6 and 1 or (1 - u) / 0.4))
                d.tex:ClearAllPoints()
                d.tex:SetPoint("CENTER", bar.fx, "TOPLEFT", x, bulbY + 0.35 * self.dh)   -- the bulb is the lower end of the picture
                d.tex:Show()
                -- the cloud: puffs around the bulb that swell, drift outward and thin out, one after another
                for j = 1, PUFFS do
                    local p = d.puffs[j]
                    local pu = (d.t - j * 0.05) / (DRIP_LIFE * 1.1)
                    if pu > 0 and pu < 1 then
                        local at = PUFF_AT[j]
                        local size = (8 + 10 * pu) * k
                        p:SetSize(size, size)
                        p:SetAlpha(0.45 * math.sin(PI * pu))
                        p:ClearAllPoints()
                        p:SetPoint("CENTER", bar.fx, "TOPLEFT", x + at[1] * k * (1 + 0.8 * pu), bulbY + (at[2] + 6 * pu) * k)
                        p:Show()
                    else
                        p:Hide()
                    end
                end
            else
                live = true
            end
        end
    end
    return not live
end

local venom = { id = "venom", setting = "effectsPoison" }

function venom.Applies(view, ctx, slot)
    return ctx.class == "ROGUE" and view.key == "COMBO_POINTS" and slot == "secondary"
end

function venom.Attach(bar)
    local inst = { bar = bar, drips = {}, dh = 28, Step = DripStep }
    for i = 1, DRIPS do
        local tex = bar.fx:CreateTexture(nil, "ARTWORK", nil, 3)
        tex:SetTexture(DRIP_TEXTURE)
        tex:Hide()
        local d = { tex = tex, on = false, t = 0, x = 0, puffs = {} }
        for j = 1, PUFFS do
            local puff = bar.fx:CreateTexture(nil, "ARTWORK", nil, 2)
            puff:SetTexture(PUFF_TEXTURE)
            puff:SetVertexColor(VENOM[1], VENOM[2], VENOM[3], 1)
            puff:Hide()
            d.puffs[j] = puff
        end
        inst.drips[i] = d
    end
    return inst
end

-- trigger: how many points were spent (a drop each), or "test".
function venom.Play(inst, trigger)
    if FX.Reduced() then return end
    local bar = inst.bar
    if not bar.innerW then return end
    local n = type(trigger) == "number" and math.max(1, math.min(DRIPS, math.floor(trigger))) or DRIPS
    inst.dh = math.max(20, math.min(36, bar.innerH * 2.5))   -- the drop is picture-sized to the bar, a quarter as wide as tall
    for i = 1, DRIPS do
        local d = inst.drips[i]
        d.on = i <= n
        if d.on then
            d.t = -(i - 1) * DRIP_DELAY
            d.x = bar.innerW * (DRIP_COLUMNS[i] - 0.5) / DRIPS
            d.tex:SetSize(inst.dh / 4, inst.dh)
            d.tex:SetAlpha(0)
        end
    end
    if not A.Add(inst) then
        for i = 1, DRIPS do inst.drips[i].on = false end
    end
end

function venom.Update(inst, view, quiet)
    local before = inst.prev
    inst.prev = view.cur
    if quiet or not inst.primed then
        inst.primed = true
        return
    end
    if before and before >= 1 and view.cur == 0 then venom.Play(inst, before) end
end

function venom.Stop(inst)
    A.Remove(inst)
    for i = 1, DRIPS do
        local d = inst.drips[i]
        d.on = false
        d.tex:Hide()
        for j = 1, PUFFS do d.puffs[j]:Hide() end
    end
    inst.primed, inst.prev = nil, nil
end
venom.Release = venom.Stop

FX.Register(venom)
