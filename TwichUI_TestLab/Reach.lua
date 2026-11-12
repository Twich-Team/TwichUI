-- TwichUI Test Lab: reachability analysis (R.TestLab.Reach)
-- "Can this control receive the pointer?" asked of any frame-like object through the documented widget methods only. It is ONE definition
-- used three ways, and the evidence differs, so every result carries an `evidence` word the caller sets:
--   the offline tests    a fake world with typed-in rectangles (tests/reach_world.lua): proves this logic, nothing about the game
--   the simulator        the real addon's frames in wow-ui-sim: geometry EMULATED here (the simulator's GetMouseFoci only returns what the scenario
--                        forced with A_Admin.SetMouseOverFrame; it never works out a frame from a position)
--   the real client      RC.Sample reads GetMouseFoci (the client's own answer) beside the same geometry; this is the only real-client evidence
-- A working click handler does not prove a working button. Eligibility (shown, enabled, mouse on) says the control MAY receive input;
-- geometry (strata, level, hit rectangle, insets, clipping, other frames over it) says whether the pointer REACHES it.
--
-- What the geometry assumes (a model, not a fact about the client; docs/testlab.md "Reachability"):
--   * a frame takes the pointer when it is visible, mouse enabled, and the point is inside its hit rectangle (its rectangle less
--     SetHitRectInsets); for a click it must also be click enabled and not propagate clicks, for hover motion enabled;
--   * the topmost is the highest strata, then frame level; a descendant is above its ancestor on a tie; any other tie is reported as
--     ambiguous, never decided (the client's order for equal strata and level is not known);
--   * a ScrollFrame, or a frame that clips children, hides the part of its descendants outside its rectangle from the pointer.
-- Nothing here writes, hooks, binds, clicks or sends. Frame text is never read.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local RC = {}
TL.Reach = RC

RC.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
RC.MAX_FRAMES = 30000    -- frames one scan looks at
RC.MAX_DEPTH = 64        -- parents followed
RC.MAX_CHAIN = 10        -- parents written in a hierarchy line
RC.STACK = 5             -- frames named in a stack

---------------------------------------------------------------------------
-- Asking a frame a question without trusting it
---------------------------------------------------------------------------
local function Index(obj, key) return obj[key] end

-- ok, a, b, c, d: ok is false (and a is why) when the method is missing, raised, or answered with a secret value
local function Call(obj, method, ...)
    local t = type(obj)
    if t ~= "table" and t ~= "userdata" then return false, "not a frame" end
    local okIndex, fn = pcall(Index, obj, method)
    if not okIndex or type(fn) ~= "function" then return false, "no " .. method end
    local ok, a, b, c, d = pcall(fn, obj, ...)
    if not ok then return false, method .. " raised" end
    if issecretvalue and (issecretvalue(a) or issecretvalue(b) or issecretvalue(c) or issecretvalue(d)) then return false, method .. " gave a secret value" end
    return true, a, b, c, d
end
RC.Call = Call

-- true / false when the method answers a boolean; nil and a reason otherwise ("missing" when the frame has no such method)
local function Bool(obj, method)
    local ok, v = Call(obj, method)
    if not ok then return nil, (v:find("^no ") and "missing" or "failed"), v end
    if type(v) ~= "boolean" then return nil, "odd", method .. " answered " .. type(v) end
    return v
end

local function Num(v) return type(v) == "number" and v == v and v > -1e12 and v < 1e12 end

local function Parent(frame)
    local ok, p = Call(frame, "GetParent")
    if ok and (type(p) == "table" or type(p) == "userdata") then return p end
    return nil
end

---------------------------------------------------------------------------
-- Names that are safe to paste: global frame names only (cut, cleaned, with the player's own names taken out); never frame text
---------------------------------------------------------------------------
local function PrivateWords()
    local words = {}
    local function Add(v) if type(v) == "string" and #v >= 3 and not (issecretvalue and issecretvalue(v)) then words[#words + 1] = v end end
    if UnitName then Add((UnitName("player"))) end
    if GetRealmName then Add(GetRealmName()) end
    if GetNormalizedRealmName then Add(GetNormalizedRealmName()) end
    if GetGuildInfo then Add((GetGuildInfo("player"))) end
    return words
end
RC.PrivateWords = PrivateWords

function RC.Redact(text, limit)
    text = tostring(text or "")
    text = text:gsub("|H.-|h(.-)|h", "[link]"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%c", " "):gsub("|", "/")
    local ok, words = pcall(RC.PrivateWords)
    if ok and type(words) == "table" then
        for _, w in ipairs(words) do
            local plain, from = {}, 1
            while true do   -- a plain, case-insensitive replace (the words are not patterns)
                local a, b = text:lower():find(w:lower(), from, true)
                if not a then break end
                plain[#plain + 1] = text:sub(from, a - 1) .. "[private]"
                from = b + 1
            end
            if #plain > 0 then text = table.concat(plain) .. text:sub(from) end
        end
    end
    limit = limit or 80
    if #text > limit then text = text:sub(1, limit) .. "..." end
    return text
end

-- opts.label(frame): a friendlier name from the caller (the simulator scenario uses a button's own text, which is synthetic there);
-- the real-client cases never pass one.
function RC.Label(frame, opts)
    if opts and opts.label then
        local ok, s = pcall(opts.label, frame)
        if ok and type(s) == "string" and s ~= "" then return RC.Redact(s, 60) end
    end
    local ok, name = Call(frame, "GetName")
    if ok and type(name) == "string" and name ~= "" then return RC.Redact(name, 60) end
    local okType, kind = Call(frame, "GetObjectType")
    return "<" .. (okType and type(kind) == "string" and RC.Redact(kind, 20) or "frame") .. ">"
end

function RC.Chain(frame, opts)
    local names, p, n = {}, frame, 0
    while p and n < RC.MAX_CHAIN do
        names[#names + 1] = RC.Label(p, opts)
        p = Parent(p)
        n = n + 1
    end
    local out = {}
    for i = #names, 1, -1 do out[#out + 1] = names[i] end
    return (p and ".. > " or "") .. table.concat(out, " > ")
end

-- is `frame` the root, or inside it?
function RC.Within(frame, root)
    local p, n = frame, 0
    while p and n < RC.MAX_DEPTH do
        if p == root then return true end
        p = Parent(p)
        n = n + 1
    end
    return false
end

-- the frame and its parents, nearest first (as a set for relation tests)
local function Ancestors(frame)
    local set, list, p, n = {}, {}, Parent(frame), 0
    while p and n < RC.MAX_DEPTH do
        set[p] = true
        list[#list + 1] = p
        p = Parent(p)
        n = n + 1
    end
    return set, list
end

---------------------------------------------------------------------------
-- The hit rectangle, in screen units (a rectangle times the frame's effective scale, comparable with the cursor)
---------------------------------------------------------------------------
-- Returns { rect = {l,b,r,t}, hit = {l,b,r,t}, insets = {left,right,top,bottom}, scale, empty, notes }, or nil and why
function RC.HitRect(frame)
    local ok, l, b, w, h = Call(frame, "GetRect")
    if not ok then return nil, l end
    if not (Num(l) and Num(b) and Num(w) and Num(h)) then return nil, "no rectangle (it is not anchored or has no size yet)" end
    local notes = {}
    local okS, scale = Call(frame, "GetEffectiveScale")
    if not (okS and Num(scale) and scale > 0) then scale = 1; notes[#notes + 1] = "scale unknown, 1 assumed" end
    local il, ir, it, ib = 0, 0, 0, 0
    local okI, a1, a2, a3, a4 = Call(frame, "GetHitRectInsets")
    if okI and Num(a1) and Num(a2) and Num(a3) and Num(a4) then
        il, ir, it, ib = a1, a2, a3, a4
    elseif not okI then
        notes[#notes + 1] = "insets unavailable, none assumed"
    end
    local rect = { l * scale, b * scale, (l + w) * scale, (b + h) * scale }
    local hit = { (l + il) * scale, (b + ib) * scale, (l + w - ir) * scale, (b + h - it) * scale }
    return { rect = rect, hit = hit, insets = { il, ir, it, ib }, scale = scale, empty = hit[3] <= hit[1] or hit[4] <= hit[2], notes = notes }
end

local function Inside(r, x, y) return x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] end

---------------------------------------------------------------------------
-- Eligibility: may this control receive the input at all? (shown, ancestors shown, enabled, mouse on, click or motion on, a handler)
-- kind: "click" (default) or "hover". opts.hasScript(frame, name) -> boolean|nil lets a caller with a stand-in answer for itself.
-- Returns { ok, kind, reasons = { {code,text} }, unknown = { text }, state = {...}, text }. Anything the frame could not answer is
-- UNKNOWN and makes ok false: a stand-in that does not model a question never reports success.
---------------------------------------------------------------------------
local SCRIPTS = { click = "OnClick", hover = "OnEnter" }

function RC.Eligibility(frame, kind, opts)
    opts = opts or {}
    kind = kind == "hover" and "hover" or "click"
    local e = { kind = kind, reasons = {}, unknown = {}, state = {} }
    local function No(code, text) e.reasons[#e.reasons + 1] = { code = code, text = text } end
    local function Unknown(text) e.unknown[#e.unknown + 1] = text end

    local shown, status, why = Bool(frame, "IsShown")
    e.state.shown = shown
    if shown == nil then Unknown("IsShown: " .. tostring(why)) elseif shown == false then No("hidden", "the frame is hidden") end

    local p, depth = Parent(frame), 0
    while p and depth < RC.MAX_DEPTH do
        local s, st, w2 = Bool(p, "IsShown")
        if s == nil then Unknown("an ancestor's IsShown: " .. tostring(w2)) break end
        if s == false then
            No("ancestor-hidden", "an ancestor is hidden: " .. RC.Label(p, opts))
            e.state.hiddenAncestor = RC.Label(p, opts)
            break
        end
        p = Parent(p)
        depth = depth + 1
    end
    local visible = Bool(frame, "IsVisible")
    e.state.visible = visible
    if visible == false and shown ~= false and not e.state.hiddenAncestor then No("not-visible", "IsVisible is false though the frame and its ancestors report shown") end

    local enabled, enStatus, enWhy = Bool(frame, "IsEnabled")
    e.state.enabled = enabled
    if enabled == false then No("disabled", "the control is disabled")
    elseif enabled == nil and enStatus ~= "missing" then Unknown("IsEnabled: " .. tostring(enWhy)) end   -- a plain Frame has no IsEnabled: not applicable

    local mouse, _, mouseWhy = Bool(frame, "IsMouseEnabled")
    e.state.mouse = mouse
    if mouse == nil then Unknown("IsMouseEnabled: " .. tostring(mouseWhy))
    elseif mouse == false then No("mouse-disabled", "mouse input is off (EnableMouse)")
    else
        local method, code, flag = "IsMouseClickEnabled", "click-disabled", "click"
        if kind == "hover" then method, code, flag = "IsMouseMotionEnabled", "motion-disabled", "motion" end
        local on, st, w3 = Bool(frame, method)
        e.state[flag] = on
        if on == false then No(code, flag == "click" and "mouse clicks are off (SetMouseClickEnabled)" or "mouse motion is off (SetMouseMotionEnabled)")
        elseif on == nil and st ~= "missing" then Unknown(method .. ": " .. tostring(w3)) end   -- an older client may not have it: not applicable
    end

    local script = opts.script or SCRIPTS[kind]   -- opts.script: a frame that is not a Button is clicked through OnMouseUp, say
    local has = opts.hasScript and opts.hasScript(frame, script)
    if has == nil then
        local ok, fn = Call(frame, "GetScript", script)
        if ok then has = type(fn) == "function" else has = nil; Unknown("GetScript: " .. tostring(fn)) end
    end
    e.state.handler = has
    if has == false then No(kind == "click" and "no-click-handler" or "no-enter-handler", "no " .. script .. " script is set") end

    e.ok = #e.reasons == 0 and #e.unknown == 0
    local parts = {}
    for _, r in ipairs(e.reasons) do parts[#parts + 1] = r.code .. " (" .. r.text .. ")" end
    for _, u in ipairs(e.unknown) do parts[#parts + 1] = "unknown (" .. u .. ")" end
    e.text = e.ok and "eligible according to the frame's own state" or table.concat(parts, "; ")
    return e
end

---------------------------------------------------------------------------
-- The frames that could take the pointer: visible and mouse enabled. opts.frames = a list (tests); otherwise EnumerateFrames, at most
-- opts.limit frames (the simulator has about 68,000; a game UI far fewer).
-- COOPERATIVE: opts.yield() is called when a slice of work is used up, and only there (Lua cannot interrupt a loop that does not yield, so
-- how long one slice runs is decided by how often this asks). It is used up
--   * when opts.clock (a function giving seconds) is given: as soon as opts.budget seconds (default RC.BUDGET) have passed since the last yield,
--     the clock being read only every opts.check frames (default RC.CHECK, so reading it costs next to nothing); a slice is then about the
--     budget plus the cost of up to `check` frames, whatever the machine's speed;
--   * always: after opts.chunk frames (default 2000), whether or not a clock is given (the tests, and the bound if a clock stops moving).
-- Returns { list, scanned, hidden, truncated, yields, work, longest }: `hidden` counts mouse-enabled frames that are not visible; with a clock,
-- `work` is the seconds spent scanning (waiting at a yield is not counted) and `longest` the longest stretch between two yields. List entries
-- carry what the analysis needs, so a frame is asked once; the whole UI is walked ONCE.
---------------------------------------------------------------------------
RC.BUDGET = 0.0015   -- seconds of scanning between yields when a clock is given (the Lab's slice is 5 ms; two or three such steps fit in a frame's slice)
RC.CHECK = 32        -- frames between two clock reads

local function Entry(fr, order)
    if Bool(fr, "IsMouseEnabled") ~= true then return nil, "passive" end   -- the cheap question first: most frames take no pointer
    if Bool(fr, "IsVisible") ~= true then return nil, "hidden" end
    local hr = RC.HitRect(fr)
    if not hr then return nil, "passive" end
    local okS, strata = Call(fr, "GetFrameStrata")
    local okL, level = Call(fr, "GetFrameLevel")
    local propagate = Bool(fr, "GetPropagateMouseClicks")
    return { frame = fr, order = order, hit = hr.hit, rect = hr.rect, insets = hr.insets, empty = hr.empty,
        strata = okS and RC.STRATA[strata] or 3, strataName = okS and tostring(strata) or "MEDIUM", level = okL and Num(level) and level or 0,
        click = Bool(fr, "IsMouseClickEnabled") ~= false, motion = Bool(fr, "IsMouseMotionEnabled") ~= false, propagate = propagate == true }
end

function RC.Collect(opts)
    opts = opts or {}
    local out = { list = {}, scanned = 0, hidden = 0, truncated = false, yields = 0, work = 0, longest = 0 }
    local limit, chunk = opts.limit or RC.MAX_FRAMES, opts.chunk or 2000
    local clock, budget, check = opts.clock, opts.budget or RC.BUDGET, opts.check or RC.CHECK
    local since, mark = 0, clock and clock()
    local function Spent()   -- the stretch of scanning since the last yield
        if not clock then return end
        local d = clock() - mark
        out.work = out.work + d
        if d > out.longest then out.longest = d end
    end
    local function Yield()
        Spent()
        since = 0
        out.yields = out.yields + 1
        opts.yield()
        if clock then mark = clock() end   -- the time spent waiting for the next step is not scan time
    end
    local function Take(fr)
        out.scanned = out.scanned + 1
        local e, skip = Entry(fr, out.scanned)
        if e then out.list[#out.list + 1] = e elseif skip == "hidden" then out.hidden = out.hidden + 1 end
        if opts.yield then
            since = since + 1
            if since >= chunk then Yield()
            elseif clock and since % check == 0 and clock() - mark >= budget then Yield() end
        end
    end
    if opts.frames then
        for _, fr in ipairs(opts.frames) do
            if out.scanned >= limit then out.truncated = true break end
            Take(fr)
        end
    elseif EnumerateFrames then
        local fr = EnumerateFrames()
        while fr do
            if out.scanned >= limit then out.truncated = true break end
            Take(fr)
            fr = EnumerateFrames(fr)
        end
    end
    Spent()
    return out
end

---------------------------------------------------------------------------
-- A frame described for a report: only what reachability needs, no text
---------------------------------------------------------------------------
local function Rounded(r) return { math.floor(r[1] + 0.5), math.floor(r[2] + 0.5), math.floor(r[3] + 0.5), math.floor(r[4] + 0.5) } end

function RC.Describe(entryOrFrame, opts)
    local e = entryOrFrame
    if type(e) ~= "table" or not e.frame then e = Entry(entryOrFrame, 0) or { frame = entryOrFrame } end
    local fr = e.frame
    local hr = RC.HitRect(fr)
    local okT, kind = Call(fr, "GetObjectType")
    local okS, strata = Call(fr, "GetFrameStrata")
    local okL, level = Call(fr, "GetFrameLevel")
    local d = { label = RC.Label(fr, opts), type = okT and RC.Redact(kind, 20) or "?", strata = okS and RC.Redact(strata, 20) or "?",
        level = okL and Num(level) and level or "?", chain = RC.Chain(fr, opts),
        shown = Bool(fr, "IsShown"), enabled = Bool(fr, "IsEnabled"), mouse = Bool(fr, "IsMouseEnabled"),
        click = Bool(fr, "IsMouseClickEnabled"), motion = Bool(fr, "IsMouseMotionEnabled") }
    if hr then d.rect, d.hit, d.insets = Rounded(hr.rect), Rounded(hr.hit), hr.insets end
    return d
end

local function Flag(v) if v == nil then return "?" end return v and "on" or "off" end

function RC.DescribeText(d)
    local s = ("%s [%s, %s level %s, mouse %s click %s motion %s"):format(d.label, d.type, d.strata, tostring(d.level), Flag(d.mouse), Flag(d.click), Flag(d.motion))
    if d.hit then
        s = s .. (", hit rect x %d..%d y %d..%d"):format(d.hit[1], d.hit[3], d.hit[2], d.hit[4])
        local i = d.insets
        if i and (i[1] ~= 0 or i[2] ~= 0 or i[3] ~= 0 or i[4] ~= 0) then
            s = s .. (", insets L%g R%g T%g B%g"):format(i[1], i[2], i[3], i[4])
        end
    end
    return s .. "]"
end

---------------------------------------------------------------------------
-- Clipping: a ScrollFrame, or a frame that clips children, hides what lies outside its rectangle. Returns the clipping ancestor, or nil.
---------------------------------------------------------------------------
local function ClippedBy(frame, x, y)
    local _, list = Ancestors(frame)
    for _, a in ipairs(list) do
        local okT, kind = Call(a, "GetObjectType")
        local okC, clips = Call(a, "DoesClipChildren")
        if (okT and kind == "ScrollFrame") or (okC and clips == true) then
            local hr = RC.HitRect(a)
            if hr and not Inside(hr.rect, x, y) then return a end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Analysis. Returns a result table:
--   verdict   reachable | ambiguous | blocked | clipped | outside | ineligible | unhittable
--   intended, chain, kind, evidence, eligibility, rect, hit, insets, point, pointSource, top, blocker, relation, stack, tie, text, notes
-- opts: kind, point = { x, y } (screen units; default the centre of the hit rectangle), collected (a RC.Collect result), label,
--       hasScript, evidence (a word the caller sets: "simulator-geometry", "offline-model", "client-geometry"), plus RC.Collect's options
---------------------------------------------------------------------------
local function Prep(entry)   -- the entry's parents as a set, and how deep it sits (once)
    if not entry.anc then
        local set, list = Ancestors(entry.frame)
        entry.anc, entry.depth = set, #list
    end
    return entry
end

local function Relation(entry, target, targetAnc)
    if entry.frame == target then return "self" end
    if Prep(entry).anc[target] then return "child" end   -- the entry sits inside the target: it takes the pointer from it
    if targetAnc[entry.frame] then return "parent" end
    return "other"
end

-- A total order for sorting: strata, then level, then deeper (a child above its parent), then the later one found. Only the first three
-- are claims about the game; the last only makes the order repeatable, which is why a tie is reported separately.
local function Above(a, b)
    if a.strata ~= b.strata then return a.strata > b.strata end
    if a.level ~= b.level then return a.level > b.level end
    Prep(a); Prep(b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    return a.order > b.order
end

-- the first entry after `top` that is neither inside it nor above it, with the same strata and level: the order between them is unknown
local function TieWith(stack, top)
    Prep(top)
    for i = 2, #stack do
        local c = stack[i]
        if c.strata ~= top.strata or c.level ~= top.level then return nil end
        Prep(c)
        if not top.anc[c.frame] and not c.anc[top.frame] then return c end
    end
    return nil
end

function RC.Analyze(target, opts)
    opts = opts or {}
    local kind = opts.kind == "hover" and "hover" or "click"
    local res = { kind = kind, evidence = opts.evidence or "geometry", intended = RC.Label(target, opts), chain = RC.Chain(target, opts), notes = {},
        eligibility = RC.Eligibility(target, kind, opts) }
    local hr, why = RC.HitRect(target)
    if not hr then
        res.verdict, res.why = "unhittable", why
        res.text = RC.Explain(res)
        return res
    end
    res.rect, res.hit, res.insets = Rounded(hr.rect), Rounded(hr.hit), hr.insets
    for _, n in ipairs(hr.notes) do res.notes[#res.notes + 1] = n end
    if hr.empty then
        res.verdict = "unhittable"
        res.why = ("the hit rectangle is empty: insets L%g R%g T%g B%g leave no area"):format(hr.insets[1], hr.insets[2], hr.insets[3], hr.insets[4])
        res.text = RC.Explain(res)
        return res
    end
    local x, y
    if opts.point then
        x, y = opts.point[1], opts.point[2]
        res.pointSource = "given"
    else
        x, y = (hr.hit[1] + hr.hit[3]) / 2, (hr.hit[2] + hr.hit[4]) / 2
        res.pointSource = "centre of the hit rectangle"
    end
    res.point = { math.floor(x + 0.5), math.floor(y + 0.5) }

    -- who would take the pointer there
    local collected = opts.collected or RC.Collect(opts)
    res.scan = { scanned = collected.scanned, capturing = #collected.list, truncated = collected.truncated }
    local targetAnc = Ancestors(target)
    local stack = {}
    for _, c in ipairs(collected.list) do
        local takes = c.frame == target or (kind == "click" and c.click and not c.propagate) or (kind == "hover" and c.motion)
        if takes and not c.empty and Inside(c.hit, x, y) and not ClippedBy(c.frame, x, y) then stack[#stack + 1] = c end
    end
    table.sort(stack, Above)
    local top = stack[1]
    if top then
        res.relation = Relation(top, target, targetAnc)
        res.top = RC.Describe(top, opts)
        local tied = TieWith(stack, top)
        if tied then res.tie = RC.Describe(tied, opts) end
    else
        res.relation = "none"
    end
    res.stack = {}
    for i = 1, math.min(RC.STACK, #stack) do res.stack[i] = RC.Describe(stack[i], opts) end

    if not res.eligibility.ok then
        res.verdict = "ineligible"
    elseif not Inside(hr.hit, x, y) then
        res.verdict = "outside"
        res.why = Inside(hr.rect, x, y) and "the point is inside the frame but outside its hit rectangle (SetHitRectInsets)" or "the point is not over the control"
    elseif ClippedBy(target, x, y) then
        res.verdict = "clipped"
        res.why = "a scroll frame or clipping ancestor hides the control at this point: " .. RC.Label(ClippedBy(target, x, y), opts)
    elseif not top then
        res.verdict = "unknown"
        res.why = "the control is eligible but no capturing frame was found at the point" .. (collected.truncated and (" (the scan stopped at " .. collected.scanned .. " frames: raise opts.limit)") or "")
    elseif res.relation == "self" then
        res.verdict = res.tie and "ambiguous" or "reachable"
        if res.tie then res.why = "another frame ties with it on strata and level; the client's order for that is not known: " .. res.tie.label end
    elseif res.relation == "child" then
        res.verdict, res.blocker = "blocked", res.top
        res.why = "a child frame takes the pointer from the control"
    else
        res.verdict, res.blocker = "blocked", res.top
        res.why = res.relation == "parent" and "a parent frame is drawn above the control" or "another frame is drawn above the control"
        if res.tie then res.verdict = "ambiguous"; res.why = res.why .. ", but it ties with it on strata and level (order unknown)" end
    end
    res.text = RC.Explain(res)
    return res
end

-- A result in words: what was intended, where the point was, what happened, who blocked it, the control's own state, the evidence class.
function RC.Explain(res)
    local lines = {}
    lines[#lines + 1] = ("%s %s on %s"):format(res.verdict and res.verdict:upper() or "?", res.kind, res.intended)
    lines[#lines + 1] = "  hierarchy: " .. tostring(res.chain)
    if res.point then lines[#lines + 1] = ("  expected hit point: x %d y %d (%s)"):format(res.point[1], res.point[2], tostring(res.pointSource)) end
    if res.why then lines[#lines + 1] = "  why: " .. res.why end
    if res.blocker then lines[#lines + 1] = "  blocking frame: " .. RC.DescribeText(res.blocker) end
    if res.tie then lines[#lines + 1] = "  tied with: " .. RC.DescribeText(res.tie) end
    if res.top and res.relation == "self" then lines[#lines + 1] = "  topmost there: the control itself" end
    if res.hit then
        local i = res.insets
        lines[#lines + 1] = ("  effective hit rect: x %d..%d y %d..%d (frame x %d..%d y %d..%d, insets L%g R%g T%g B%g)"):format(
            res.hit[1], res.hit[3], res.hit[2], res.hit[4], res.rect[1], res.rect[3], res.rect[2], res.rect[4], i[1], i[2], i[3], i[4])
    end
    local e = res.eligibility
    if e then lines[#lines + 1] = "  control state: " .. e.text end
    if res.notes and #res.notes > 0 then lines[#lines + 1] = "  notes: " .. table.concat(res.notes, "; ") end
    lines[#lines + 1] = "  evidence: " .. tostring(res.evidence) .. " (a model of the pointer, not the client's own answer unless it says client-foci)"
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- The real client's own answer: GetMouseFoci, read at one moment, with the pointer position. Bounded to `max` frames (default RC.STACK)
-- and described by type, strata, level, mouse flags and global name only. Returns { ok, why, x, y, count, foci = { desc }, truncated }.
---------------------------------------------------------------------------
function RC.Sample(opts)
    opts = opts or {}
    local s = { foci = {}, count = 0, truncated = false }
    if type(GetMouseFoci) ~= "function" then s.ok, s.why = false, "GetMouseFoci is not available in this client" return s end
    local ok, list = pcall(GetMouseFoci)
    if not ok or type(list) ~= "table" then s.ok, s.why = false, "GetMouseFoci failed" return s end
    s.ok = true
    local cx, cy = 0, 0
    if GetCursorPosition then cx, cy = GetCursorPosition() end
    if Num(cx) and Num(cy) then s.x, s.y = cx, cy end
    s.count = #list
    local max = opts.max or RC.STACK
    for i, fr in ipairs(list) do
        if i > max then s.truncated = true break end
        s.foci[i] = { frame = fr, desc = RC.Describe(fr, opts) }
    end
    return s
end
