-- TwichUI: Healer Watch, the magical particle attention effect
-- A slow shimmer for a Healer Watch display: a drifting haze of soft puffs that start near the middle of the panel,
-- swell, spread outward past its edges and fade, one after another for a few seconds, with a faint, slow glow along the
-- border. Nothing flashes and nothing takes the mouse. The puffs are thin (see P.LEVELS) so the readings stay legible. It decorates a state the panel already shows in words and
-- numbers; the color carries no meaning of its own.
--
-- What is drawn, honestly: a pool of one tinted texture (media\classbars\venom-puff.tga, a soft white puff with its own
-- transparency, drawn with normal blending so any color reads on a dark or a bright background) moved, grown and faded by
-- animation groups the game runs, so nothing here has an OnUpdate and an idle effect costs nothing. It is particle-like,
-- not the game's particle system. (Blizzard's star4 was tried and dropped: it has no transparency and shows as a black box.)
--
-- One pool per display (P.New(parent)), made when the display first plays it and then reused: at most MOTES textures
-- and one edge frame, however often it is triggered. A trigger while a burst is still running is coalesced (ignored)
-- unless forced, which is only the settings' preview; a forced play stops the running burst first, so two never overlap.
--
--   fx = P.New(parent)             parent: the panel (or the settings window's sample) it decorates; sized by its owner
--   fx:Play(r, g, b, level, force) one burst in that color at "subtle", "standard" or "strong"; false if coalesced
--   fx:Stop()                      stop at once and leave nothing drawn
--   fx:Active()                    whether a burst is still running (by time, not by polling a frame)

local R = TwichUI
local P = {}
R.HealerParticles = P

local PUFF = R.PATH .. [[media\classbars\venom-puff.tga]]         -- ours: a generated soft white puff, tinted when drawn

P.MOTES = 40                                                       -- the most textures a pool ever holds
P.LEVELS = {                                                       -- puffs in a burst, their strongest opacity, the edge glow's
    subtle = { motes = 16, alpha = 0.30, edge = 0.16 },
    standard = { motes = 26, alpha = 0.45, edge = 0.26 },
    strong = { motes = 40, alpha = 0.60, edge = 0.38 },
}
local LIFE, STAGGER = 2.2, 3.0          -- seconds a puff lives, and the spread of their starts (so the haze keeps coming)
local EDGE_UP, EDGE_DOWN = 0.8, 3.8     -- the border glow's slow rise and fall
P.DURATION = STAGGER + LIFE + 0.1       -- a burst is over this long after it begins

local stats = { pools = 0, motes = 0, bursts = 0, coalesced = 0 }

local Pool = {}
Pool.__index = Pool

local function Build(self)
    if self.built then return end
    self.built = true
    local f = self.frame
    for i = 1, P.MOTES do
        local tex = f:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(PUFF)
        tex:SetAlpha(0)
        tex:Hide()
        local g = tex:CreateAnimationGroup()
        local m = { tex = tex, group = g }
        m.move = g:CreateAnimation("Translation")
        m.move:SetOrder(1)
        m.move:SetSmoothing("OUT")
        m.grow = g:CreateAnimation("Scale")   -- a puff swells as it thins out
        m.grow:SetOrder(1)
        m.grow:SetScaleFrom(0.7, 0.7)
        m.grow:SetScaleTo(1.5, 1.5)
        m.fadeIn = g:CreateAnimation("Alpha")
        m.fadeIn:SetOrder(1)
        m.fadeIn:SetFromAlpha(0)
        m.fadeOut = g:CreateAnimation("Alpha")
        m.fadeOut:SetOrder(1)
        m.fadeOut:SetToAlpha(0)
        g:SetToFinalAlpha(true)
        g:SetScript("OnFinished", function() tex:Hide() end)
        self.motes[i] = m
        stats.motes = stats.motes + 1
    end

    -- the border glow: four hairlines just outside the panel's edge, under one slow fade
    local e = CreateFrame("Frame", nil, f)
    e:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    e:EnableMouse(false)
    e:SetAlpha(0)
    e.lines = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = e:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
            t:SetPoint(side .. "LEFT", e, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", e, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint("TOP" .. side, e, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, e, "BOTTOM" .. side, 0, 0)
        end
        e.lines[i] = t
    end
    local g = e:CreateAnimationGroup()
    e.up = g:CreateAnimation("Alpha")
    e.up:SetOrder(1)
    e.up:SetFromAlpha(0)
    e.up:SetDuration(EDGE_UP)
    e.up:SetSmoothing("IN_OUT")
    e.down = g:CreateAnimation("Alpha")
    e.down:SetOrder(2)
    e.down:SetToAlpha(0)
    e.down:SetDuration(EDGE_DOWN)
    e.down:SetSmoothing("IN_OUT")
    g:SetToFinalAlpha(true)
    e.group = g
    self.edge = e
end

function Pool:Stop()
    self.untilT = -math.huge
    if not self.built then return end
    for i = 1, P.MOTES do
        local m = self.motes[i]
        m.group:Stop()
        m.tex:SetAlpha(0)
        m.tex:Hide()
    end
    self.edge.group:Stop()
    self.edge:SetAlpha(0)
end

function Pool:Active() return GetTime() < self.untilT end

function Pool:Play(r, g, b, level, force)
    local now = GetTime()
    if not force and now < self.untilT then
        stats.coalesced = stats.coalesced + 1
        return false
    end
    Build(self)
    self:Stop()
    local L = P.LEVELS[level] or P.LEVELS.standard
    local w = math.max(1, self.parent:GetWidth() or 1)
    local h = math.max(1, self.parent:GetHeight() or 1)
    self.bursts = self.bursts + 1
    stats.bursts = stats.bursts + 1
    self.untilT = now + P.DURATION
    local n = L.motes
    local shift = (self.bursts * 0.37) % 1   -- each burst starts its motes at other places along the edge
    for i = 1, P.MOTES do
        local m = self.motes[i]
        if i <= n then
            -- small fixed variations by puff and burst, so no two look alike and nothing is random or allocated
            local v1, v2, v3 = ((i * 5 + self.bursts * 3) % 7) / 6, ((i * 3 + self.bursts) % 5) / 4, ((i * 7 + self.bursts * 2) % 9) / 8
            -- each puff starts near the middle and travels outward along its own direction, past the panel's edge
            local angle = 2 * math.pi * ((i - 0.5) / n + shift)
            local cx, cy = math.cos(angle), math.sin(angle)
            local x, y = w / 2 + (v3 - 0.5) * w * 0.2, h / 2 + (v2 - 0.5) * h * 0.2
            local tx = cx > 0.001 and (w - x) / cx or (cx < -0.001 and x / -cx or math.huge)
            local ty = cy > 0.001 and (h - y) / cy or (cy < -0.001 and y / -cy or math.huge)
            local travel = math.min(tx, ty) + 10 + 14 * v1   -- from where it starts to past the edge it is heading for
            local dx, dy = cx * travel, cy * travel + (cy >= 0 and 4 + 8 * v2 or 0)   -- those heading up also lean a little further up
            local delay = (((i * 7) % n) / n) * STAGGER   -- 7 is coprime with every level's count: each start is used once
            local size = 18 + 14 * v3
            local peak = L.alpha
            m.tex:ClearAllPoints()
            m.tex:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
            m.tex:SetSize(size, size)
            m.tex:SetVertexColor(r, g, b)
            m.tex:SetAlpha(0)
            m.tex:Show()
            m.move:SetOffset(dx, dy)
            m.move:SetDuration(LIFE)
            m.move:SetStartDelay(delay)
            m.grow:SetDuration(LIFE)
            m.grow:SetStartDelay(delay)
            m.fadeIn:SetToAlpha(peak)
            m.fadeIn:SetDuration(LIFE * 0.3)
            m.fadeIn:SetStartDelay(delay)
            m.fadeOut:SetFromAlpha(peak)
            m.fadeOut:SetDuration(LIFE * 0.7)
            m.fadeOut:SetStartDelay(delay + LIFE * 0.3)
            m.group:Play()
        end
    end
    local e = self.edge
    for i = 1, #e.lines do e.lines[i]:SetColorTexture(r, g, b, 1) end
    e.up:SetToAlpha(L.edge)
    e.down:SetFromAlpha(L.edge)
    e:SetAlpha(0)
    e.group:Play()
    return true
end

function P.New(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel(parent:GetFrameLevel() or 1)   -- below the panel's own parts (a child frame is one level above its parent): the haze is behind the art, the text and the bar
    f:EnableMouse(false)
    stats.pools = stats.pools + 1
    return setmetatable({ parent = parent, frame = f, motes = {}, built = false, untilT = -math.huge, bursts = 0 }, Pool)
end

-- Plain numbers, for the tests and the diagnostics.
function P.Stats() return { pools = stats.pools, motes = stats.motes, bursts = stats.bursts, coalesced = stats.coalesced } end
