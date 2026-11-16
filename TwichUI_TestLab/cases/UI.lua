-- TwichUI Test Lab: interface reachability (categories "ui" and "pointer")
-- WHAT IT ANSWERS: can the Workshop's controls actually receive the pointer in THIS client? A working click handler does not prove a working
-- button; this is the evidence a handler test cannot give. It reads and describes frames; it never clicks, writes, hooks or sends.
--
--   ui.pointer.api                  readonly   which pointer APIs this client has (no frame is made or changed)
--   ui.workshop.reach-scan          readonly   every visible, enabled, clickable button of the OPEN Workshop window: is it the topmost frame
--                                              at its centre? (geometry from the frames' own rectangles, strata, levels, insets and clipping:
--                                              an EMULATION run in the client, see Reach.lua; it is not the client's own answer)
--   ui.pointer.add-button           guided     you hold the pointer over "Add to crafting plan" and press the key: GetMouseFoci says which
--   ui.pointer.opportunity-row      guided     frame the client really puts there, and whether the row lit up
--   ui.pointer.row-picture          guided     the same over a row's recipe picture (a child that takes the pointer): the row must stay lit
--
-- The guided cases only run when the "Pointer probe (guided)" category is chosen. They report what the client said at one moment; whether
-- the hover LOOKS right (the animation, the colours) still needs a person to look, because only an alpha value is read here.
-- Frame TEXT is never read, names are redacted (Reach.lua), and at most five frames of the pointer's stack are described.

local R = TwichUI
local TL = R.TestLab
local RC, G = TL.Reach, TL.Guided

TL.Category{ id = "ui", label = "Interface reachability", blurb = "can the open Workshop window's buttons take the pointer? (read only)" }
TL.Category{ id = "pointer", label = "Pointer probe (guided)", blurb = "you place the pointer and press a key; reads what the client puts under it", guided = true }

local Round = function(v) return math.floor(v + 0.5) end

---------------------------------------------------------------------------
-- The Workshop window, as it is open right now (never loaded or opened from here)
---------------------------------------------------------------------------
local function WorkshopWindow()
    local W = R.Workshop
    local win = W and W.Window
    if not (win and win.Frame and win.Opps and win.Lists) then return nil, "The Workshop is not loaded: open it first (/tui workshop)." end
    local f = win.Frame()
    if not (f and f:IsShown()) then return nil, "The Workshop window is not open: open it first (/tui workshop)." end
    return win, f
end

local function Owner(frame)   -- "workshop", "testlab" or "other", and the nearest global name on the way up
    local p, n, first = frame, 0, nil
    while p and n < RC.MAX_DEPTH do
        local ok, name = RC.Call(p, "GetName")
        if ok and type(name) == "string" and name ~= "" then
            first = first or name
            if name == "TwichUIWorkshop" then return "workshop", first end
            if name:find("^TwichUITestLab") then return "testlab", first end
        end
        local okP, parent = RC.Call(p, "GetParent")
        p = okP and parent or nil
        n = n + 1
    end
    return "other", first
end

---------------------------------------------------------------------------
-- ui.pointer.api
---------------------------------------------------------------------------
TL.Case{ id = "ui.pointer.api", cat = "ui", class = "readonly", budget = 2, run = function(t)
    for _, name in ipairs({ "GetMouseFoci", "GetCursorPosition", "EnumerateFrames", "SetOverrideBindingClick", "ClearOverrideBindings", "InCombatLockdown" }) do
        t:Fact("ui.api." .. name, type(_G[name]))
    end
    -- the frame methods, asked of a frame that already exists (UIParent): present or not, and what type they answer
    for _, method in ipairs({ "IsMouseEnabled", "IsMouseClickEnabled", "IsMouseMotionEnabled", "GetHitRectInsets", "GetRect", "GetEffectiveScale", "DoesClipChildren" }) do
        local ok, value = RC.Call(UIParent, method)
        t:Fact("ui.frame." .. method, ok and type(value) or "missing")
    end
    t:Fact("ui.pointer.key", TL.Guided.KEY)
    t:Check(type(GetMouseFoci) == "function", "GetMouseFoci is present: the pointer probe needs it")
end }

---------------------------------------------------------------------------
-- ui.workshop.reach-scan
---------------------------------------------------------------------------
TL.Case{ id = "ui.workshop.reach-scan", cat = "ui", class = "readonly", budget = 30, run = function(t)
    local win, f = WorkshopWindow()
    if not win then t:Skip(f) end
    -- Cooperative pacing: yield when about RC.BUDGET seconds of scanning have passed (not after a fixed number of frames, which took 11 to 15 ms
    -- a step in the first real-client run). The scan still walks every frame, Workshop's or not, so a blocker from anywhere is seen. A step
    -- cannot be cut short; it can only be kept small by yielding often.
    local clock = TL.Runner.Now
    local began = clock()
    local collected = RC.Collect({ clock = clock, yield = function() t:Yield() end })
    t:Fact("ui.scan.frames", collected.scanned)
    t:Fact("ui.scan.yields", collected.yields)
    t:Fact("ui.scan.work_ms", ("%.1f"):format(collected.work * 1000))
    t:Fact("ui.scan.longest_slice_ms", ("%.1f"):format(collected.longest * 1000))
    t:Fact("ui.scan.elapsed_ms", ("%.1f"):format((clock() - began) * 1000))
    t:Fact("ui.scan.takingPointer", #collected.list)
    t:Fact("ui.scan.truncated", collected.truncated)
    t:Check(not collected.truncated, ("the scan looked at all %d frames (it stops at %d)"):format(collected.scanned, RC.MAX_FRAMES))
    local tally = { reachable = 0, ambiguous = 0, blocked = 0, clipped = 0, other = 0, noScript = 0, disabled = 0, controls = 0 }
    local n, paced, seen = 0, clock(), 0
    local function Pace()   -- yield when the budget is spent; the clock is read every few frames, and always after a control's analysis
        if clock() - paced >= RC.BUDGET then t:Yield(); paced = clock() end
    end
    for _, c in ipairs(collected.list) do
        local fr = c.frame
        seen = seen + 1
        if seen % 16 == 0 then Pace() end
        local okT, kind = RC.Call(fr, "GetObjectType")
        if okT and (kind == "Button" or kind == "CheckButton") and RC.Within(fr, f) then
            n = n + 1
            local okS, script = RC.Call(fr, "GetScript", "OnClick")
            if not (okS and type(script) == "function") then
                tally.noScript = tally.noScript + 1
            elseif select(2, RC.Call(fr, "IsEnabled")) == false then
                tally.disabled = tally.disabled + 1
            else
                tally.controls = tally.controls + 1
                local res = RC.Analyze(fr, { kind = "click", collected = collected, evidence = "client-geometry" })
                local v = res.verdict
                if v == "reachable" then tally.reachable = tally.reachable + 1
                elseif v == "clipped" then tally.clipped = tally.clipped + 1
                elseif v == "ambiguous" then tally.ambiguous = tally.ambiguous + 1
                elseif v == "blocked" then tally.blocked = tally.blocked + 1
                else tally.other = tally.other + 1 end
                if v ~= "reachable" and v ~= "clipped" then
                    t:Check(false, ("%s on %s"):format(v, res.intended))
                    t:Note((res.text:gsub("\n%s*", " | ")))
                end
                Pace()
            end
        end
    end
    for k, v in pairs(tally) do t:Fact("ui.scan." .. k, v) end
    t:Check(tally.controls > 0, "the open window has clickable buttons to look at (open a page with buttons, such as Opportunities)")
end }

---------------------------------------------------------------------------
-- The guided cases
---------------------------------------------------------------------------
-- What the client says at the moment of the key: its own stack under the pointer (GetMouseFoci), described without text, and how it
-- relates to the target. Plain data only (no frame is kept), so a later step reads the same thing the key saw.
local function Capture(def, source, attempt)
    local snap = { source = source, attempt = attempt, relations = {}, owners = {}, roots = {} }
    local s = RC.Sample({ max = RC.STACK })
    snap.client = { ok = s.ok, why = s.why, x = s.x, y = s.y, count = s.count, truncated = s.truncated, descs = {} }
    local target = s.ok and def.target(s.x, s.y) or nil
    if target then
        snap.hasTarget = true
        snap.targetLabel = RC.Label(target)
        snap.eligibility = RC.Eligibility(target, def.kind)
        local hr = RC.HitRect(target)
        if hr then
            snap.rect, snap.hit, snap.insets = hr.rect, hr.hit, hr.insets
            if s.x and s.y then
                snap.inRect = s.x >= hr.rect[1] and s.x <= hr.rect[3] and s.y >= hr.rect[2] and s.y <= hr.rect[4]
                snap.inHit = not hr.empty and s.x >= hr.hit[1] and s.x <= hr.hit[3] and s.y >= hr.hit[2] and s.y <= hr.hit[4]
                local dx = s.x < hr.rect[1] and hr.rect[1] - s.x or (s.x > hr.rect[3] and s.x - hr.rect[3] or 0)
                local dy = s.y < hr.rect[2] and hr.rect[2] - s.y or (s.y > hr.rect[4] and s.y - hr.rect[4] or 0)
                snap.away = { Round(dx), Round(dy), s.x < hr.rect[1] and "left" or (s.x > hr.rect[3] and "right" or ""), s.y < hr.rect[2] and "below" or (s.y > hr.rect[4] and "above" or "") }
            end
        end
        if def.hover then snap.hover = def.hover(target) end
    end
    for i, focus in ipairs(s.foci) do
        snap.client.descs[i] = focus.desc
        local owner, root = Owner(focus.frame)
        snap.owners[i], snap.roots[i] = owner, root and RC.Redact(root, 40) or nil
        local rel = "other"
        if target then
            if focus.frame == target then rel = "self"
            elseif RC.Within(focus.frame, target) then rel = "inside"
            elseif RC.Within(target, focus.frame) then rel = "contains"
            end
        end
        snap.relations[i] = rel
    end
    return snap
end

local function Flag(v) if v == nil then return "?" end return tostring(v) end

-- Turns a snapshot into: invalid (not counted; the pointer was not where it was asked to be), unavailable (the probe cannot work here), or
-- { checks = { {ok, text} }, facts = {}, notes = {} }. def.expect(snap, v) adds the checks that are particular to the case.
local function Judge(def, snap)
    local c = snap.client
    if not c.ok then return { unavailable = c.why or "GetMouseFoci gave no answer" } end
    if not (c.x and c.y) then return { unavailable = "the pointer position is not available (GetCursorPosition)" } end
    if not snap.hasTarget then return { invalid = def.missing } end
    if snap.eligibility.state.shown == false or snap.eligibility.state.hiddenAncestor then return { invalid = def.missing } end
    if snap.owners[1] == "testlab" then
        return { invalid = "The Test Lab's own window or prompt is under the pointer. Drag it away from the target and try again." }
    end
    if not snap.rect then return { invalid = "The target has no position on screen yet. " .. def.missing } end
    if not snap.inRect then
        local a = snap.away
        local where = (a[3] ~= "" and (a[1] .. " px to the " .. a[3] .. " of it") or "") .. ((a[3] ~= "" and a[4] ~= "") and ", " or "") .. (a[4] ~= "" and (a[2] .. " px " .. a[4]) or "")
        return { invalid = "The pointer is not over " .. def.what .. " (" .. where .. "). " .. def.where }
    end
    local v = { checks = {}, facts = {}, notes = {} }
    local function Add(ok, text) v.checks[#v.checks + 1] = { ok, text } end
    local function Fact(k, val) v.facts[#v.facts + 1] = { def.key .. "." .. k, val } end
    Fact("source", snap.source); Fact("attempts", snap.attempt)
    Fact("foci_count", c.count); Fact("topmost_relation", snap.relations[1] or "none"); Fact("topmost_owner", snap.owners[1] or "none")
    Fact("in_hit_rect", Flag(snap.inHit)); Fact("target_eligible", Flag(snap.eligibility.ok))
    v.notes[#v.notes + 1] = ("pointer x %d y %d (screen units) | target hit rect x %d..%d y %d..%d | frame x %d..%d y %d..%d | insets L%g R%g T%g B%g | evidence: client-foci (GetMouseFoci at the key)"):format(
        Round(c.x), Round(c.y), Round(snap.hit[1]), Round(snap.hit[3]), Round(snap.hit[2]), Round(snap.hit[4]), Round(snap.rect[1]), Round(snap.rect[3]),
        Round(snap.rect[2]), Round(snap.rect[4]), snap.insets[1], snap.insets[2], snap.insets[3], snap.insets[4])
    for i, d in ipairs(c.descs) do
        v.notes[#v.notes + 1] = ("focus %d (%s, %s): %s"):format(i, snap.relations[i], snap.owners[i], RC.DescribeText(d))
    end
    if c.truncated then v.notes[#v.notes + 1] = ("the stack has %d frames; the first %d are listed"):format(c.count, #c.descs) end
    Add(snap.inHit == true, "the pointer is over the control's painted area but OUTSIDE its hit rectangle (SetHitRectInsets): the pointer would not reach it there")
    Add(snap.eligibility.ok, "the control is not eligible: " .. snap.eligibility.text)
    local top = snap.relations[1]
    if top == nil then
        Add(false, "NO frame takes the pointer at this spot: the client gives it to the world, so the control is not receiving input")
    else
        def.expect(snap, v, Add, Fact)
    end
    return v
end

local function Guided(def)
    TL.Case{ id = def.id, cat = "pointer", class = "guided", budget = 120, run = function(t)
        local ok, why = G.Begin{ title = def.title, lines = def.lines, capture = function(source, attempt) return Capture(def, source, attempt) end }
        if not ok then t:Skip(why) end
        local verdict
        while not verdict do
            G.Poll()
            local status, snap, err = G.Status()
            if status == "sample" then
                local v = Judge(def, snap)
                if v.unavailable then G.End(); t:Skip(v.unavailable) end
                if v.invalid then
                    if not G.Retry(v.invalid) then G.End(); t:Skip(("no usable sample after %d tries; the last: %s"):format(G.MAX_ATTEMPTS, v.invalid)) end
                elseif v.retryAlpha and snap.attempt < 3 then
                    G.Retry(v.retryAlpha)
                else
                    verdict = v
                end
            elseif status == "skipped" then
                G.End(); t:Skip("you skipped this step")
            elseif status == "failed" then
                G.End(); error("the sample could not be taken: " .. tostring(err), 0)
            elseif status == "idle" then
                t:Skip("the request was closed")
            end
            if not verdict then t:Wait(0.05) end
        end
        G.End()
        for _, f in ipairs(verdict.facts) do t:Fact(f[1], f[2]) end
        for _, n in ipairs(verdict.notes) do t:Note(n) end
        for _, c in ipairs(verdict.checks) do t:Check(c[1], c[2]) end
    end }
end

-- the Add button -----------------------------------------------------------------------------------------------------------------
Guided{
    id = "ui.pointer.add-button", key = "ui.add", kind = "click",
    title = "Pointer probe 1 of 3: Add to crafting plan",
    lines = { "Open the Workshop (/tui workshop), go to Opportunities and choose a recipe.",
        "Drag this window and the Test Lab window so neither covers the Workshop's right-hand details.",
        "Put the pointer over \"Add to crafting plan\". Do not click." },
    what = "the Add to crafting plan button",
    missing = "The Add to crafting plan button is not on screen. Open the Workshop, choose Opportunities and select a recipe.",
    where = "Put it over the Add to crafting plan button.",
    target = function()
        local win = WorkshopWindow()
        local d = win and win.Opps() and win.Opps().detail
        return d and d.add or nil
    end,
    expect = function(snap, v, Add)
        Add(snap.relations[1] == "self", ("the topmost frame under the pointer is %s, not the Add button (%s)"):format(
            snap.relations[1] == "inside" and "a child of the button" or (snap.relations[1] == "contains" and "a parent of the button" or "another frame"),
            snap.client.descs[1] and RC.DescribeText(snap.client.descs[1]) or "?"))
    end,
}

-- an opportunity row ---------------------------------------------------------------------------------------------------------
-- What a row keeps about its hover, read through the row's own fields (no handler is patched, nothing is called). Anything unreadable is
-- nil and reported as unobservable; an alpha is not an animation, and how it looks still needs your eyes.
local function HoverState(row)
    local h = { hovered = row.hovered, selected = row.selected, hasEnter = type(row.GetScript) == "function" and type(row:GetScript("OnEnter")) == "function" }
    local function Part(group)
        local part = type(group) == "table" and type(group.parts) == "table" and group.parts[1] or nil
        if not part then return nil, nil end
        local okA, a = RC.Call(part, "GetAlpha")
        local okV, vis = RC.Call(part, "IsVisible")
        return okA and type(a) == "number" and a or nil, okV and vis or nil
    end
    h.hotAlpha, h.hotVisible = Part(row.twichHot)
    h.rimAlpha = Part(row.twichRim)
    h.selShown = select(2, Part(row.twichSel))
    return h
end

local function RowAt(x, y)
    local win = WorkshopWindow()
    local list = win and win.Lists().opps
    for _, row in ipairs(list and list.rows or {}) do
        local hr = RC.HitRect(row)
        if hr and row:IsShown() and x >= hr.rect[1] and x <= hr.rect[3] and y >= hr.rect[2] and y <= hr.rect[4] then return row end
    end
    return nil
end

local function HoverChecks(snap, v, Add, Fact, what)
    local h = snap.hover
    local top = snap.relations[1]
    Fact("hovered", Flag(h and h.hovered)); Fact("selected", Flag(h and h.selected))
    Fact("hot_alpha", h and h.hotAlpha and ("%.2f"):format(h.hotAlpha) or "unobservable")
    Fact("rim_alpha", h and h.rimAlpha and ("%.2f"):format(h.rimAlpha) or "unobservable")
    Fact("hot_visible", Flag(h and h.hotVisible)); Fact("selection_shown", Flag(h and h.selShown))
    Add(h and h.hasEnter, what .. " has no OnEnter script installed")
    Add(top == "self" or top == "inside", ("another frame, not %s, is the topmost under the pointer: %s"):format(what,
        snap.client.descs[1] and RC.DescribeText(snap.client.descs[1]) or "?"))
    if h and (top == "self" or top == "inside") then
        Add(h.hovered == true, what .. " is under the pointer but is not marked hovered (OnEnter did not run, or the highlight was dropped)")
        if h.hotAlpha and h.rimAlpha then
            local lit = h.hotAlpha >= 0.2 and h.rimAlpha >= 0.3
            if h.hovered == true and not lit then
                v.retryAlpha = "the highlight was still fading in; keep the pointer still for a second and press again"
            end
            Add(lit, ("%s is marked hovered but its highlight is not lit (hot %.2f, rim %.2f)"):format(what, h.hotAlpha, h.rimAlpha))
        end
    end
    v.notes[#v.notes + 1] = "hover state read from the row's own fields; the animation itself and how it looks are NOT verified: look at it"
end

Guided{
    id = "ui.pointer.opportunity-row", key = "ui.row", kind = "hover",
    title = "Pointer probe 2 of 3: an opportunity row",
    lines = { "Stay on Opportunities. Move the pointer onto the NAME of any recipe row (not its picture), and hold it still.",
        "A selected row is fine; try both if you like." },
    what = "an opportunity row",
    missing = "No Opportunities row is on screen. Open the Workshop, choose Opportunities and wait for the list.",
    where = "Put it over a recipe row's name.",
    target = function(x, y) return x and RowAt(x, y) or nil end,
    hover = HoverState,
    expect = function(snap, v, Add, Fact)
        HoverChecks(snap, v, Add, Fact, "the row")
        Add(snap.relations[1] ~= "inside", "a child frame of the row (its picture or a button) holds the pointer here: aim at the row's name for this step; the next step covers the picture")
    end,
}

Guided{
    id = "ui.pointer.row-picture", key = "ui.picture", kind = "hover",
    title = "Pointer probe 3 of 3: a row's picture",
    lines = { "Move the pointer onto the little recipe PICTURE at the left of a row, and hold it still.",
        "The picture takes the pointer from the row; the row must stay lit (it follows the picture)." },
    what = "a row's picture",
    missing = "No Opportunities row is on screen. Open the Workshop, choose Opportunities and wait for the list.",
    where = "Put it over a recipe row's picture.",
    target = function(x, y)
        local row = x and RowAt(x, y)
        return row and row.iconBtn or nil
    end,
    hover = function(button)
        local row = button:GetParent()
        local h = HoverState(row)
        h.hasEnter = type(button.GetScript) == "function" and type(button:GetScript("OnEnter")) == "function"   -- the picture's own handler, which sets the row hot
        return h
    end,
    expect = function(snap, v, Add, Fact)
        HoverChecks(snap, v, Add, Fact, "the row's picture")
        Add(snap.relations[1] == "self", "the topmost frame is not the picture itself (see the focus list)")
    end,
}
