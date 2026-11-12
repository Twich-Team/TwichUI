-- TwichUI Test Lab: owned probe frames (R.TestLab.Probe)
-- The client API probes (milestone 6, cases/Api.lua) need frames whose input state they may change and a small arrangement a person can click.
-- Everything here is made by the Lab, named "TwichUITestLabProbe<role>", and is NEVER a control of the Workshop or of any other addon:
--   P.Get(role, kind)   one frame per role for the whole session (the game cannot delete a frame, so a rerun reuses it, reset to a clean state);
--                       the state it reported when it was FIRST created is kept, so a rerun can still say what a fresh frame reports
--   P.Do(obj, method)   calls a method through pcall and says "ok", "missing" or "raised" (with the error text): a restriction is recorded, never worked around
--   P.Release()         hides every probe frame, takes their scripts and mouse off, and forgets the click trial. The Runner calls it when a case or the
--                       run ends (on Stop, close, error, timeout and combat as well), so nothing of this file outlives the run
--   P.Overlap / P.Equal / P.HitArea   the three arrangements of the guided cases (a dark backdrop with a few coloured frames in the middle of the screen)
--   P.NewTrial / P.Trial / P.Summarize   what the arrangement's frames recorded for one real click (which frame got the press, which ran OnClick, what
--                       GetMouseFoci said at that moment)
-- The arrangement only COUNTS: its handlers append a record to a bounded list and nothing else. They never click, send, save, hook or move anything.
-- The backdrop takes the click when no probe frame does, so a probe click never reaches the 3D world. Nothing here binds a key.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local RC = TL.Reach
local P = {}
TL.Probe = P

P.PREFIX = "TwichUITestLabProbe"
P.STRATA = "FULLSCREEN_DIALOG"
P.MAX_EVENTS = 24
P.QUIET = 0.35          -- seconds without a new record before a click is taken as finished
P.ARENA_W, P.ARENA_H = 580, 340

local SCRIPTS = { "OnClick", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "PreClick", "PostClick" }
local pool, kinds, defaults, pieceOf, pieceByName = {}, {}, {}, {}, {}
local trial

local function Now() return TL.Runner and TL.Runner.Now() or (GetTime and GetTime() or 0) end

---------------------------------------------------------------------------
-- Asking and telling a frame without trusting it
---------------------------------------------------------------------------
-- "ok" and what the call returned, "missing" (no such method), or "raised" and the (redacted, cut) error text
function P.Do(obj, method, ...)
    local okIndex, fn = pcall(function() return obj[method] end)
    if not okIndex or type(fn) ~= "function" then return "missing" end
    local ok, a, b, c, d = pcall(fn, obj, ...)
    if not ok then return "raised", RC.Redact(tostring(a), 120) end
    return "ok", a, b, c, d
end

-- one flag as a letter: T, F, "-" (the frame has no such method) or "?" (it answered something odd)
local function Sym(frame, method)
    local ok, v = RC.Call(frame, method)
    if not ok then return (type(v) == "string" and v:find("^no ")) and "-" or "?" end
    if v == true then return "T" elseif v == false then return "F" end
    return "?"
end

function P.State(frame)
    return { mouse = Sym(frame, "IsMouseEnabled"), click = Sym(frame, "IsMouseClickEnabled"), motion = Sym(frame, "IsMouseMotionEnabled"),
        shown = Sym(frame, "IsShown"), visible = Sym(frame, "IsVisible"), enabled = Sym(frame, "IsEnabled") }
end

function P.StateText(s)
    return ("m=%s c=%s mo=%s sh=%s vis=%s en=%s"):format(s.mouse, s.click, s.motion, s.shown, s.visible, s.enabled)
end

---------------------------------------------------------------------------
-- The pool
---------------------------------------------------------------------------
function P.Reset(f, kind)
    P.Do(f, "Hide")
    P.Do(f, "ClearAllPoints")
    for _, s in ipairs(SCRIPTS) do P.Do(f, "SetScript", s, nil) end
    -- the two flags first, EnableMouse last: what a plain Frame ends with is "mouse off", what a Button ends with is "mouse on"
    P.Do(f, "SetMouseClickEnabled", true)
    P.Do(f, "SetMouseMotionEnabled", true)
    P.Do(f, "SetPropagateMouseClicks", false)
    P.Do(f, "SetHitRectInsets", 0, 0, 0, 0)
    P.Do(f, "SetAlpha", 1)
    P.Do(f, "SetToplevel", false)
    if kind == "Button" then
        P.Do(f, "Enable")
        P.Do(f, "EnableMouse", true)
    else
        P.Do(f, "EnableMouse", false)
    end
end

-- Returns frame, isNew, defaults (what the frame reported when first created this session: { state = {...} }), or nil and why
function P.Get(role, kind)
    kind = kind == "Button" and "Button" or "Frame"
    local f = pool[role]
    if f then
        P.Reset(f, kinds[role])
        return f, false, defaults[role]
    end
    local ok, fr = pcall(CreateFrame, kind, P.PREFIX .. role, UIParent)
    if not ok or not fr then return nil, false, nil, "CreateFrame failed" end
    pool[role], kinds[role] = fr, kind
    defaults[role] = { state = P.State(fr) }
    pieceOf[fr] = role:gsub("^arena%.", "")
    pieceByName[P.PREFIX .. role] = pieceOf[fr]
    P.Do(fr, "Hide")
    return fr, true, defaults[role]
end

function P.Release()
    local n = 0
    for role, f in pairs(pool) do
        P.Reset(f, kinds[role])
        P.Do(f, "EnableMouse", false)
        n = n + 1
    end
    trial = nil
    return n
end

-- What is still live (for the tests and the diagnostics): nothing, once a case or the run is over
function P.Snapshot()
    local out = { frames = 0, shown = 0, mouse = 0, scripted = 0, trial = trial ~= nil }
    for _, f in pairs(pool) do
        out.frames = out.frames + 1
        if Sym(f, "IsShown") == "T" then out.shown = out.shown + 1 end
        if Sym(f, "IsMouseEnabled") == "T" then out.mouse = out.mouse + 1 end
        for _, s in ipairs(SCRIPTS) do
            local ok, fn = RC.Call(f, "GetScript", s)
            if ok and type(fn) == "function" then out.scripted = out.scripted + 1 break end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- The click trial: what the arrangement's frames recorded for one real click
---------------------------------------------------------------------------
-- A frame as the report names it: its piece name (L, U, A, B, T, back), UIParent, or another frame's (redacted) global name or type
function P.NameOf(frame, desc)
    local n = pieceOf[frame]
    if n then return n end
    if frame == UIParent then return "UIParent" end
    return "other:" .. (desc and desc.label or "?")
end

function P.PieceByLabel(label) return pieceByName[label] end

local function Sample()
    local s = RC.Sample({ max = 6 })
    local out = { ok = s.ok, why = s.why, x = s.x, y = s.y, count = s.count, names = {} }
    for i, foc in ipairs(s.foci) do out.names[i] = P.NameOf(foc.frame, foc.desc) end
    return out
end

local function Record(name, what, button)
    local tr = trial
    if not tr then return end
    if what == "down" or what == "up" or what == "click" then
        if not tr.first then tr.first = Sample() end   -- GetMouseFoci and the cursor, at the first press of the click
        tr.last = Now()
        if what ~= "down" then tr.finished = true end
    end
    if #tr.events < P.MAX_EVENTS then tr.events[#tr.events + 1] = { name, what, button }
    else tr.dropped = (tr.dropped or 0) + 1 end
end

function P.NewTrial()
    trial = { events = {}, over = {}, entered = {}, started = Now() }
    return trial
end
function P.Trial() return trial end

-- true once a press has been released and nothing new has been recorded for P.QUIET seconds
function P.TrialDone(quiet)
    local tr = trial
    return tr ~= nil and tr.finished == true and tr.last ~= nil and Now() - tr.last >= (quiet or P.QUIET)
end

-- One Lab frame counts what it receives. button: true for a Button (it also has OnClick).
local function Wire(f, name, isButton)
    P.Do(f, "SetScript", "OnMouseDown", function(_, b) Record(name, "down", b) end)
    P.Do(f, "SetScript", "OnMouseUp", function(_, b) Record(name, "up", b) end)
    P.Do(f, "SetScript", "OnEnter", function() if trial then trial.over[name] = true; trial.entered[name] = true end end)
    P.Do(f, "SetScript", "OnLeave", function() if trial then trial.over[name] = false end end)
    if isButton then P.Do(f, "SetScript", "OnClick", function(_, b) Record(name, "click", b) end) end
end

local function Join(list) return #list > 0 and table.concat(list, "+") or "none" end

-- A finished trial in plain words and data. zone: { l, b, r, t } in screen units (or nil). Returns
-- { clicks = {names}, ups = {...}, downs = {...}, foci = {names, top first}, inZone, away = {dx, dy}, hasFoci, hasCursor, text }
function P.Summarize(tr, zone)
    local s = { clicks = {}, ups = {}, downs = {}, foci = {}, over = {}, hasFoci = false, hasCursor = false }
    if not tr then s.text = "no click was recorded" return s end
    local function Add(list, name) for _, v in ipairs(list) do if v == name then return end end list[#list + 1] = name end
    for _, e in ipairs(tr.events) do
        if e[2] == "click" then Add(s.clicks, e[1]) elseif e[2] == "up" then Add(s.ups, e[1]) elseif e[2] == "down" then Add(s.downs, e[1]) end
    end
    for name, on in pairs(tr.over) do if on then s.over[#s.over + 1] = name end end
    table.sort(s.over)
    local f = tr.first
    if f then
        s.hasFoci = f.ok == true
        for i, n in ipairs(f.names) do s.foci[i] = n end
        s.hasCursor = f.x ~= nil and f.y ~= nil
        if s.hasCursor and zone then
            s.inZone = f.x >= zone[1] and f.x <= zone[3] and f.y >= zone[2] and f.y <= zone[4]
            local dx = f.x < zone[1] and zone[1] - f.x or (f.x > zone[3] and f.x - zone[3] or 0)
            local dy = f.y < zone[2] and zone[2] - f.y or (f.y > zone[4] and f.y - zone[4] or 0)
            s.away = { math.floor(dx + 0.5), math.floor(dy + 0.5) }
        end
    end
    s.text = ("OnClick ran on: %s | mouse-down on: %s | mouse-up on: %s | GetMouseFoci (top first): %s | OnEnter seen and not left: %s%s"):format(
        Join(s.clicks), Join(s.downs), Join(s.ups), #s.foci > 0 and table.concat(s.foci, " > ") or (f and (f.why or "empty") or "not sampled"),
        Join(s.over), tr.dropped and (" | " .. tr.dropped .. " records dropped") or "")
    return s
end

---------------------------------------------------------------------------
-- The arena: a dark backdrop in the middle of the screen, a highlight square that says where to click, and the frames of one arrangement
---------------------------------------------------------------------------
local COLORS = { back = { 0.04, 0.04, 0.06, 0.94 }, blue = { 0.18, 0.42, 0.95, 1 }, orange = { 0.96, 0.56, 0.10, 1 }, teal = { 0.12, 0.62, 0.50, 1 } }
local arena

local function Colour(f, c, text)
    if not f.probeTex then f.probeTex = f:CreateTexture(nil, "ARTWORK") end
    f.probeTex:SetAllPoints(f)
    f.probeTex:SetColorTexture(c[1], c[2], c[3], c[4])
    if text then
        if not f.probeLabel then f.probeLabel = R.Look.Text(f, "small"); f.probeLabel:SetPoint("TOPLEFT", 6, -5) end
        f.probeLabel:SetText(text)
    elseif f.probeLabel then
        f.probeLabel:SetText("")
    end
end

local function Place(f, back, x, y, w, h)
    P.Do(f, "ClearAllPoints")
    P.Do(f, "SetSize", w, h)
    P.Do(f, "SetPoint", "CENTER", back, "CENTER", x, y)
end

local function Layer(f, level)
    P.Do(f, "SetFrameStrata", P.STRATA)
    P.Do(f, "SetFrameLevel", level)
end

-- Resets every arrangement frame and returns the backdrop and the highlight; the arrangement then shows only what it uses
local function Begin()
    for role, f in pairs(pool) do
        if role:find("^arena%.") then P.Reset(f, kinds[role]) end
    end
    local back = P.Get("arena.back", "Frame")
    P.Do(back, "SetParent", UIParent)
    Place(back, UIParent, 0, -60, P.ARENA_W, P.ARENA_H)
    Layer(back, 1)
    P.Do(back, "EnableMouse", true)
    Colour(back, COLORS.back, "Test Lab probe area: clicks here reach only Test Lab frames")
    Wire(back, "back", false)
    back:Show()
    local mark = P.Get("arena.mark", "Frame")   -- never takes the pointer
    P.Do(mark, "SetParent", UIParent)
    P.Do(mark, "SetFrameStrata", "TOOLTIP")
    P.Do(mark, "SetFrameLevel", 50)
    if not mark.probeTex then mark.probeTex = mark:CreateTexture(nil, "OVERLAY") end
    mark.probeTex:SetAllPoints(mark)
    mark.probeTex:SetColorTexture(1, 1, 1, 0.34)
    if not mark.probeLabel then mark.probeLabel = R.Look.Text(mark, "small"); mark.probeLabel:SetPoint("BOTTOM", mark, "TOP", 0, 4) end
    arena = { back = back, mark = mark, status = {} }
    return arena
end

-- Highlights where to click. x, y are the centre, relative to the backdrop's centre.
function P.Mark(x, y, w, h, text)
    if not arena then return end
    Place(arena.mark, arena.back, x, y, w, h)
    arena.mark.probeLabel:SetText(text or "")
    arena.mark:Show()
    arena.zone = { x = x, y = y, w = w, h = h }
end

-- The highlighted square in screen units { l, b, r, t } (comparable with the cursor), or nil
function P.Zone()
    if not (arena and arena.mark) then return nil end
    local hr = RC.HitRect(arena.mark)
    return hr and hr.rect or nil
end

-- the frames of the arrangement that could take the pointer, for RC.Collect (the model's side of the comparison)
function P.Frames()
    local list = {}
    for role, f in pairs(pool) do
        if role:find("^arena%.") and role ~= "arena.mark" then list[#list + 1] = f end
    end
    table.sort(list, function(a, b) return tostring(P.NameOf(a)) < tostring(P.NameOf(b)) end)
    return list
end
function P.Piece(name) return pool["arena." .. name] end
function P.Arena() return arena end

-- Two overlapping frames and a third that may sit on the overlap.
--   L  a Button (blue) lower in level; it counts OnClick
--   U  a plain Frame (orange) above it, mode: "off" (mouse off), "frame" (mouse on), "noclick" (mouse on, clicks off, motion on),
--      "propagate" (mouse on, SetPropagateMouseClicks(true))
-- Returns { status = {setter results}, readback = state text of U, text = a sentence }
function P.Overlap(mode)
    local a = Begin()
    local L = P.Get("arena.L", "Button")
    local U = P.Get("arena.U", "Frame")
    P.Do(L, "SetParent", a.back); P.Do(U, "SetParent", a.back)
    Place(L, a.back, -60, 0, 200, 120); Layer(L, 5); Colour(L, COLORS.blue, "L: lower Button (blue)")
    Place(U, a.back, 60, 0, 200, 120); Layer(U, 8); Colour(U, COLORS.orange, "U: upper Frame (orange)")
    Wire(L, "L", true)
    local st = a.status
    if mode ~= "off" then
        st.enable = P.Do(U, "EnableMouse", true)
        Wire(U, "U", false)
    end
    if mode == "noclick" then st.clicks_off = P.Do(U, "SetMouseClickEnabled", false) end
    if mode == "propagate" then st.propagate = P.Do(U, "SetPropagateMouseClicks", true) end
    L:Show(); U:Show()
    P.Mark(0, 0, 40, 40, "click inside this square")
    local order = { "enable", "clicks_off", "propagate" }
    local parts = {}
    for _, k in ipairs(order) do if st[k] then parts[#parts + 1] = k .. "=" .. st[k] end end
    return { status = st, readback = P.StateText(P.State(U)), target = "L", pieces = { L = L, U = U }, text = #parts > 0 and table.concat(parts, " ") or "no setter called" }
end

-- Two Buttons with the SAME strata and level over each other. spec = { pair = 1|2, order = "AB"|"BA", parentage = "siblings"|"containers" }
--   pair 1: A (blue) was created before B (orange); pair 2: B was created before A. (A frame is created once per session, so these are the
--   two ways round that exist; a rerun reuses them.)
--   order: which was shown first. parentage "containers": each sits in its own plain frame, the two frames of equal level.
-- Returns { createdLast, lastShown, parentCreatedLast (letters), status, text }
function P.Equal(spec)
    spec = spec or {}
    local a = Begin()
    local pair = spec.pair == 2 and 2 or 1
    local A, B
    if pair == 1 then
        A = P.Get("arena.A1", "Button"); B = P.Get("arena.B1", "Button")
    else
        B = P.Get("arena.B2", "Button"); A = P.Get("arena.A2", "Button")
    end
    local info = { status = a.status, createdLast = pair == 1 and "B" or "A", pieces = { A = A, B = B } }
    pieceOf[A], pieceOf[B] = "A", "B"   -- the report says A and B whichever pair is in use
    pieceByName[P.PREFIX .. (pair == 1 and "arena.A1" or "arena.A2")], pieceByName[P.PREFIX .. (pair == 1 and "arena.B1" or "arena.B2")] = "A", "B"
    local parentA, parentB = a.back, a.back
    if spec.parentage == "containers" then
        local C1 = P.Get("arena.C1", "Frame"); local C2 = P.Get("arena.C2", "Frame")
        for _, c in ipairs({ C1, C2 }) do
            P.Do(c, "SetParent", a.back)
            Place(c, a.back, 0, 0, P.ARENA_W, P.ARENA_H); Layer(c, 4)
        end
        parentA, parentB = C1, C2
        info.parentCreatedLast = "B"
        C1:Show(); C2:Show()
    end
    P.Do(A, "SetParent", parentA); P.Do(B, "SetParent", parentB)
    Place(A, a.back, -60, 0, 200, 120); Layer(A, 6); Colour(A, COLORS.blue, "A (blue)")
    Place(B, a.back, 60, 0, 200, 120); Layer(B, 6); Colour(B, COLORS.orange, "B (orange)")
    Wire(A, "A", true); Wire(B, "B", true)
    local first, second = A, B
    info.lastShown = "B"
    if spec.order == "BA" then first, second = B, A; info.lastShown = "A" end
    first:Show(); second:Show()
    P.Mark(0, 0, 40, 40, "click inside this square")
    info.readback = ("A %s | B %s"):format(P.StateText(P.State(A)), P.StateText(P.State(B)))
    info.text = ("pair %d (%s created last) | shown %s first | %s | both FULLSCREEN_DIALOG level 6"):format(pair, info.createdLast,
        spec.order == "BA" and "B" or "A", spec.parentage == "containers" and "each in its own container" or "siblings")
    return info
end

-- One Button (teal, 240 x 80) with hit-rectangle insets: positive shrinks the clickable area, negative extends it.
-- Returns { status, readback = {l, r, t, b} as the client reports them, zones = { {id, x, y, w, h, text} } }
P.INSETS = { 70, -50, 0, 0 }   -- left 70 inside the paint, right 50 outside it
function P.HitArea()
    local a = Begin()
    local T = P.Get("arena.T", "Button")
    P.Do(T, "SetParent", a.back)
    Place(T, a.back, 0, 0, 240, 80); Layer(T, 5); Colour(T, COLORS.teal, "T: Button, hit-rect insets L70 R-50")
    Wire(T, "T", true)
    a.status.insets = P.Do(T, "SetHitRectInsets", P.INSETS[1], P.INSETS[2], P.INSETS[3], P.INSETS[4])
    local st, l, r, tp, b = P.Do(T, "GetHitRectInsets")
    T:Show()
    return { status = a.status, readback = st == "ok" and { l, r, tp, b } or nil, readStatus = st, target = T,
        zones = {
            { id = "centre", x = 0, y = 0, w = 40, h = 40, text = "centre of the teal button" },
            { id = "left-strip", x = -85, y = 0, w = 30, h = 40, text = "inside the paint, in the left 70 px that the inset removes" },
            { id = "right-extension", x = 145, y = 0, w = 30, h = 40, text = "outside the paint, in the 50 px that the negative inset adds" },
        } }
end
