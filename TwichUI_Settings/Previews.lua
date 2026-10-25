-- TwichUI Settings: sample previews on feature cards
-- A preview is a small drawing of what a feature does, made of the window's own textures and text: a sample
-- summon, a sample duel request. It is never the feature: nothing here calls a feature's handler or a game action
-- (no summon, resurrection, release, duel, purchase, chat message or journal entry), and nothing here writes a
-- setting. A preview reads the settings it illustrates (who may summon you, how long the wait is) when it is reset
-- or played, so it shows the rules as they are set.
--
--   P.Register(id, def)          def: { height, duration (seconds of one play, or Duration(sample) -> seconds),
--                                  static (true: nothing plays),
--                                  Sample() -> the values it illustrates (read only),
--                                  Create(stage, sample) -> scene (its textures and text on `stage`),
--                                  Reset(scene, sample)  -> the "before" picture,
--                                  Update(scene, t, sample) -> the picture t seconds into a play,
--                                  Final(scene, sample)  -> the "after" picture,
--                                  Caption(sample) -> the whole sample in words (shown under it, always),
--                                  Release(scene) (optional) }
--   P.Host(parent, id, width)    a host for one preview: host.frame, host:Play(), host:Stop(), host:Reset(),
--                                host:Release(), host:IsPlaying(), host.height; nil for an unknown id
--   P.StopAll()                  every playing preview back to its "before" picture (the window calls it when it
--                                closes, changes page, or a card's preview is hidden)
--   P.Playing()                  how many are playing (for tests and diagnostics)
--
-- A play runs once (never looping) for `duration` seconds through the host frame's OnUpdate, which is set only while
-- it plays and removed when it ends, stops, hides or is released, so nothing runs while the window is idle or
-- shut. With Reduce window motion on, Play shows the "after" picture at once; the caption says the same in words
-- either way, so nothing is shown only as motion.

local R = TwichUI
local Wg = R.SettingsWidgets
local pal, Motion = Wg.pal, Wg.Motion
local P = { defs = {} }
R.SettingsPreviews = P

local playing, playCount = {}, 0

function P.Register(id, def)
    assert(type(id) == "string" and type(def) == "table" and type(def.Create) == "function", "a preview needs an id and Create")
    P.defs[id] = def
end

function P.Get(id) return id and P.defs[id] or nil end
function P.Playing() return playCount end

local function Sample(def)
    if not def.Sample then return {} end
    local ok, sample = pcall(def.Sample)
    if ok and type(sample) == "table" then return sample end
    if not ok then R.Fault("settings preview", sample) end
    return {}
end

local function Call(host, name, ...)
    local fn = host.def[name]
    if not fn or not host.scene then return end
    local ok, err = pcall(fn, host.scene, ...)
    if not ok then
        R.Fault("settings preview " .. host.id, err)
        host.broken = true
    end
    return ok
end

local function Detach(host)
    if not playing[host] then return end
    playing[host] = nil
    playCount = playCount - 1
    host.frame:SetScript("OnUpdate", nil)
end

local Host = {}
Host.__index = Host

function Host:IsPlaying() return playing[self] == true end

-- The words under the drawing: the whole sample, current settings included.
function Host:Caption(extra)
    local text = ""
    if self.def.Caption then
        local ok, words = pcall(self.def.Caption, self.sample or Sample(self.def))
        if ok and type(words) == "string" then text = words end
    end
    if extra then text = text .. (text ~= "" and " " or "") .. extra end
    self.caption:SetText(text)
end

-- The "before" picture, with the settings as they are now.
function Host:Reset()
    if self.released then return end
    Detach(self)
    self.sample = Sample(self.def)
    Call(self, "Reset", self.sample)
    self:Caption()
    self.done = false
end

-- Back to the "before" picture if a play is under way (a finished play keeps its "after" picture).
function Host:Stop()
    if self:IsPlaying() then self:Reset() end
end

local function Step(frame, elapsed)
    local host = frame.twichPreview
    if not host or not playing[host] then frame:SetScript("OnUpdate", nil) return end
    if elapsed > Motion.MAX_STEP then elapsed = Motion.MAX_STEP end
    host.t = host.t + elapsed
    if host.t >= host.duration or host.broken then
        Detach(host)
        Call(host, "Final", host.sample)
        host.done = true
        if host.onDone then host.onDone(host) end
        return
    end
    Call(host, "Update", host.t, host.sample)
end

-- Plays the sample once from the start. Shown at once (the "after" picture) where motion is reduced.
function Host:Play()
    if self.released or self.def.static then return end
    self:Reset()
    if not Motion.Enabled() then
        Call(self, "Final", self.sample)
        self.done = true
        self:Caption("(Reduce window motion is on, so the end of the sample is shown at once.)")
        if self.onDone then self.onDone(self) end
        return
    end
    self.t = 0
    self.duration = self.def.duration or 3
    if self.def.Duration then
        local ok, seconds = pcall(self.def.Duration, self.sample)
        if ok and type(seconds) == "number" and seconds > 0 then self.duration = math.min(seconds, 6) end
    end
    playing[self] = true
    playCount = playCount + 1
    self.frame:SetScript("OnUpdate", Step)
    Call(self, "Update", 0, self.sample)
end

function Host:Release()
    if self.released then return end
    Detach(self)
    if self.def.Release and self.scene then pcall(self.def.Release, self.scene) end
    self.scene = nil
    self.released = true
    self.frame:Hide()
end

-- A host for preview `id`, `width` wide: a recessed stage with a "Sample" tag, and its caption below. Its height
-- (host.height) is the stage plus room for two lines of caption; Window.lua reads it after the caption is set.
function P.Host(parent, id, width)
    local def = P.Get(id)
    if not def then return nil end
    local host = setmetatable({ id = id, def = def, width = width, t = 0 }, Host)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, def.height or 72)
    frame.twichPreview = host
    host.frame = frame
    local stage = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", 0, 0)
    stage:SetSize(width, def.height or 72)
    Wg.Surface(stage, pal.well, 0.75, pal.bronzeLo, 0.45)
    Wg.Recess(stage, 0.8)
    host.stage = stage
    -- the drawing is labelled as a sample wherever it could be mistaken for the real thing
    local tag = Wg.Tag(stage, "SAMPLE")
    tag:SetPoint("TOPRIGHT", -6, -6)
    host.caption = Wg.Text(frame, "small")
    host.caption:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 2, -6)
    host.caption:SetWidth(width - 4)
    host.caption:SetWordWrap(true)
    local ok, scene = pcall(def.Create, stage, Sample(def))
    if ok then host.scene = scene else R.Fault("settings preview " .. id, scene); host.broken = true end
    -- a preview stops when its card, page or the window is hidden
    frame:SetScript("OnHide", function() host:Stop() end)
    host:Reset()
    return host
end

-- Height of the host as laid out now: the stage and its caption.
function P.HostHeight(host)
    return (host.def.height or 72) + 6 + (host.caption:GetStringHeight() or 12)
end

function P.StopAll()
    for host in pairs(playing) do host:Reset() end
end

---------------------------------------------------------------------------
-- Pieces previews draw with: flat, inert copies of the game's shapes (a pop-up, a button), so a sample reads as
-- what it shows. None takes the mouse: a sample button can't be pressed, and there is nothing behind it.
---------------------------------------------------------------------------
-- A small pop-up: a dark panel with a bronze edge, like the game's dialogs at a glance.
function P.Popup(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    Wg.Surface(f, pal.nav, 0.96, pal.bronze, 0.75)
    f:EnableMouse(false)
    return f
end

-- A sample button: a face and a label, never clickable. b:SetLit(on) shows it pressed (teal edge).
function P.FakeButton(parent, label, w)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetSize(w or 64, 18)
    Wg.Surface(b, pal.quiet.bg, 1, pal.quiet.border, 1)
    b:EnableMouse(false)
    b.text = Wg.Text(b, "meta")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    Wg.Color(b.text, pal.text)
    function b:SetLit(on)
        local c = on and pal.tealHi or pal.quiet.border
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        Wg.Color(self.text, on and pal.tealHi or pal.text)
    end
    return b
end

-- A portrait: the player's own face where the game draws it (SetPortraitTexture, display only), else the
-- profiles icon. Returns the texture; a second, desaturated copy can be made with P.Portrait(..., true).
function P.Portrait(parent, size, gray)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    local drawn = false
    if SetPortraitTexture then drawn = pcall(SetPortraitTexture, t, "player") end
    if not drawn and R.Icons then R.Icons.Apply(t, "profilesSharing", size) end
    if gray and t.SetDesaturated then t:SetDesaturated(true) end
    return t
end

-- The fraction (0..1) of the way from a to b that t is, clamped.
function P.Ramp(t, a, b)
    if t <= a then return 0 end
    if t >= b then return 1 end
    return (t - a) / (b - a)
end

-- A wait as words: "waits 3 seconds", "at once".
function P.Wait(n)
    if not n or n == 0 then return "at once" end
    return n == 1 and "after 1 second" or ("after %d seconds"):format(n)
end
