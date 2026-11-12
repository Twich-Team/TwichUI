-- TwichUI Test Lab: client UI API probes (milestone 6; categories "api" and "apiguided")
-- WHAT THEY ANSWER: how a few UI calls and input routes behave in THIS client, observed on frames the Lab makes itself (Probe.lua), so the
-- offline model and the simulator stop guessing. They RECORD what the client does; a result is a fact about one client at one moment, and a
-- call the client refuses is recorded as a restriction, never retried another way. Nothing of the Workshop, the auction house or any other
-- addon is touched, and no protected action is attempted. Both groups are opt-in: they run only when ticked by name.
--
--   api.binding.override      owned   an override binding made, cleared, made again and cleared, out of combat, read through GetBindingAction
--                                     (no key is pressed; one step with no yield, so nothing can be routed meanwhile)
--   api.mouse.states          owned   IsMouseEnabled / IsMouseClickEnabled / IsMouseMotionEnabled after each way of switching mouse input on and off,
--                                     for a plain Frame and a Button (also hidden, disabled), and which of the older/newer method names exist
--   api.click.programmatic    owned   what Button:Click() does (OnClick, PreClick, PostClick counters) for a visible, disabled, hidden, mouse-off,
--                                     click-off and parent-hidden button. A programmatic Click is NOT a physical click.
--   api.hitrect.insets        owned   SetHitRectInsets/GetHitRectInsets: callable out of combat, positive and negative values, the read-back, and
--                                     the Lab's own hit-rectangle arithmetic on what the client reports
--   api.binding.keypress      guided  you press F9 twice (bound, then cleared and bound again): does a real key press reach a Lab-owned control
--   api.click.overlap         guided  you click where a lower Button and an upper frame overlap, with the upper frame's mouse off / on / clicks off /
--                                     propagating: which frame ran OnClick, which got the press, what GetMouseFoci said, what you saw on top
--   api.order.equal-level     guided  two Buttons with the SAME strata and level: which one takes a real click when the creation order, the show order
--                                     and the parents change. The reachability analysis keeps calling a tie ambiguous whatever this finds.
--   api.hitrect.pointer       guided  you click inside the painted area but outside the hit rectangle, in the middle, and outside the paint but inside
--                                     the hit rectangle: does the pointer region follow the insets
-- Reports carry three separate pieces of evidence for a click and never assume they agree: GetMouseFoci (the client's own stack), the frame whose
-- OnClick (or mouse-up) really ran, and what the person saw on top. docs/testlab.md "Client UI API probes" has the steps and the findings table.

local R = TwichUI
local TL = R.TestLab
local RC, G, P = TL.Reach, TL.Guided, TL.Probe

TL.Category{ id = "api", label = "Client UI API (own frames)", blurb = "mouse, click, hit-rectangle and key-binding behaviour, measured on frames the Lab makes itself; nothing of yours is touched", optin = true }
TL.Category{ id = "apiguided", label = "Client UI API (guided)", blurb = "you click Lab-made test frames and press a key; reads which frame the client gives each click", guided = true }

local function Own(id, run) TL.Case{ id = id, cat = "api", class = "owned", budget = 8, run = run } end
local function Guide(id, run) TL.Case{ id = id, cat = "apiguided", class = "guided", budget = 150, run = run } end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function NotInCombat(t) if InCombat() then t:Skip("not during combat: the probe makes and changes frames") end end

local function Join(list) return #list > 0 and table.concat(list, "+") or "none" end
local function Has(list, name) for _, v in ipairs(list) do if v == name then return true end end return false end

-- An owned case ends with its frames released and the check that nothing is left live
local function Clean(t)
    P.Release()
    local s = P.Snapshot()
    t:Check(s.shown == 0 and s.mouse == 0 and s.scripted == 0 and not s.trial, ("the probe frames were released (shown %d, mouse on %d, with scripts %d)"):format(s.shown, s.mouse, s.scripted))
end

local function Action(key)
    if type(GetBindingAction) ~= "function" then return "n/a" end
    local ok, v = pcall(GetBindingAction, key, true)
    if not ok then return "raised" end
    return (tostring(v):gsub("[%c|]", " "))
end

---------------------------------------------------------------------------
-- api.binding.override
---------------------------------------------------------------------------
Own("api.binding.override", function(t)
    NotInCombat(t)
    for _, name in ipairs({ "SetOverrideBindingClick", "ClearOverrideBindings", "GetBindingAction", "InCombatLockdown" }) do
        t:Fact("api.binding.fn." .. name, type(_G[name]))
    end
    t:Fact("api.binding.fn.CheckAllowProtectedFunctions", type(C_RestrictedActions) == "table" and type(C_RestrictedActions.CheckAllowProtectedFunctions) or "absent")
    local obs = G.BindingProbe()
    if obs.refused then t:Skip(obs.refused) end
    t:Fact("api.binding.key", obs.key)
    t:Fact("api.binding.combat_at_start", obs.combat)
    t:Fact("api.binding.protected_allowed", obs.protectedOk)
    t:Fact("api.binding.bind_ok", obs.bindOk and "yes" or ("no: " .. tostring(obs.bindWhy)))
    t:Fact("api.binding.rebind_ok", obs.rebindOk and "yes" or ("no: " .. tostring(obs.rebindWhy)))
    t:Fact("api.binding.action_before", obs.before)
    t:Fact("api.binding.action_bound", obs.bound or "-")
    t:Fact("api.binding.action_cleared", obs.cleared or "-")
    t:Fact("api.binding.action_bound_again", obs.bound2 or "-")
    t:Fact("api.binding.action_after", obs.after)
    local lab = obs.bound and obs.bound:find(G.NAME, 1, true) ~= nil
    t:Fact("api.binding.bound_names_lab_button", lab == true)
    t:Fact("api.binding.combat", "not attempted (the Lab refuses to run in combat)")
    t:Note("combat: the Lab never starts or continues in combat, so the restriction is read from C_RestrictedActions (protected_allowed above), not from a try")
    t:Note(("GetBindingAction(%s, true): before %s | while bound %s | after clearing %s | bound again %s | after the final clear %s"):format(
        obs.key, obs.before, obs.bound or "-", obs.cleared or "-", obs.bound2 or "-", obs.after))
    if not obs.bindOk then t:Note("the client refused the first binding: recorded as an observed restriction (" .. tostring(obs.bindWhy) .. ")") end
    t:Check(obs.raised == nil, "the probe itself raised: " .. tostring(obs.raised))
    local live = G.Snapshot()
    t:Check(live.bound == nil and not live.proxyShown, "the binding was cleared and the key's button hidden")
    t:Check(obs.after == obs.before, ("the key reports what it reported before (before %q, after %q): nothing was left behind"):format(obs.before, obs.after))
    t:Note("a real key press is a separate question: api.binding.keypress (guided)")
end)

---------------------------------------------------------------------------
-- api.mouse.states
---------------------------------------------------------------------------
local MOUSE_METHODS = { "EnableMouse", "EnableMouseMotion", "EnableMouseClicks", "SetMouseClickEnabled", "SetMouseMotionEnabled", "IsMouseEnabled",
    "IsMouseClickEnabled", "IsMouseMotionEnabled", "SetPropagateMouseClicks", "GetPropagateMouseClicks", "SetHitRectInsets", "GetHitRectInsets", "Click", "Disable", "Enable" }

Own("api.mouse.states", function(t)
    NotInCombat(t)
    local total, consistent = 0, 0
    local function Steps(kind, role, list)
        local f, isNew, def = P.Get(role, kind == "button" and "Button" or "Frame")
        if not f then t:Skip("a probe frame could not be made") end
        t:Fact(("api.mouse.%s.fresh"):format(kind), P.StateText(def.state))
        t:Fact(("api.mouse.%s.fresh_read"):format(kind), isNew and "when made in this run" or "when first made, earlier this session")
        for _, step in ipairs(list) do
            local f2 = P.Get(role, kind == "button" and "Button" or "Frame")   -- every step starts from the same clean frame
            P.Do(f2, "Show")
            local bad = {}
            for _, c in ipairs(step.calls) do
                local st, err = P.Do(f2, c[1], unpack(c, 2))
                if st ~= "ok" then bad[#bad + 1] = c[1] .. " " .. st .. (err and (": " .. err) or "") end
            end
            local s = P.State(f2)
            t:Fact(("api.mouse.%s.%s"):format(kind, step.name), P.StateText(s))
            if #bad > 0 then t:Note(("%s / %s: %s"):format(kind, step.name, table.concat(bad, "; "))) end
            if s.click ~= "-" and s.click ~= "?" and s.motion ~= "-" and s.motion ~= "?" and s.mouse ~= "-" and s.mouse ~= "?" then
                total = total + 1
                if (s.mouse == "T") == (s.click == "T" or s.motion == "T") then consistent = consistent + 1
                else t:Note(("%s / %s: IsMouseEnabled is %s but click is %s and motion is %s"):format(kind, step.name, s.mouse, s.click, s.motion)) end
            end
        end
        return f
    end
    local common = {
        { name = "reset", calls = {} },
        { name = "enable-true", calls = { { "EnableMouse", true } } },
        { name = "enable-false", calls = { { "EnableMouse", false } } },
        { name = "motion-only-EnableMouseMotion", calls = { { "EnableMouse", false }, { "EnableMouseMotion", true } } },
        { name = "motion-only-SetMouseMotionEnabled", calls = { { "EnableMouse", false }, { "SetMouseMotionEnabled", true } } },
        { name = "clicks-only-by-motion-off", calls = { { "EnableMouse", true }, { "SetMouseMotionEnabled", false } } },
        { name = "motion-only-by-clicks-off", calls = { { "EnableMouse", true }, { "SetMouseClickEnabled", false } } },
        { name = "clicks-only-SetMouseClickEnabled", calls = { { "EnableMouse", false }, { "SetMouseClickEnabled", true } } },
        { name = "both-off-by-flags", calls = { { "EnableMouse", true }, { "SetMouseClickEnabled", false }, { "SetMouseMotionEnabled", false } } },
        { name = "script-only", calls = { { "EnableMouse", false }, { "SetScript", "OnEnter", function() end } } },
        { name = "hidden", calls = { { "EnableMouse", true }, { "Hide" } } },
    }
    Steps("frame", "mouse.frame", common)
    local btnSteps = {}
    for _, s in ipairs(common) do btnSteps[#btnSteps + 1] = s end
    btnSteps[#btnSteps + 1] = { name = "disabled", calls = { { "EnableMouse", true }, { "Disable" } } }
    btnSteps[#btnSteps + 1] = { name = "disabled-then-enabled", calls = { { "EnableMouse", true }, { "Disable" }, { "Enable" } } }
    local button = Steps("button", "mouse.button", btnSteps)
    for _, m in ipairs(MOUSE_METHODS) do t:Fact("api.mouse.method." .. m, type(button[m])) end
    t:Fact("api.mouse.flags_consistent", ("%d of %d steps"):format(consistent, total))
    t:Note("the Lab's model (Reach.Eligibility) reads IsMouseEnabled, then IsMouseClickEnabled (clicks) or IsMouseMotionEnabled (hover). "
        .. ("The client's IsMouseEnabled agreed with click-or-motion in %d of %d steps. A step it did not agree with is listed above; the model is NOT changed here."):format(consistent, total))
    t:Note("a method listed as absent (EnableMouseClicks is not in the Forever API documentation) is not claimed to exist; it is only reported")
    Clean(t)
end)

---------------------------------------------------------------------------
-- api.click.programmatic
---------------------------------------------------------------------------
Own("api.click.programmatic", function(t)
    NotInCombat(t)
    local counts = { on = 0, pre = 0, post = 0 }
    local btn = P.Get("click.button", "Button")
    local parent = P.Get("click.parent", "Frame")
    if not (btn and parent) then t:Skip("a probe frame could not be made") end
    local function Normal()
        P.Get("click.button", "Button")
        P.Get("click.parent", "Frame")
        P.Do(btn, "SetParent", parent)
        P.Do(parent, "Show")
        P.Do(btn, "SetSize", 80, 24)
        P.Do(btn, "SetPoint", "CENTER", UIParent, "CENTER", 0, 0)
        P.Do(btn, "SetScript", "OnClick", function() counts.on = counts.on + 1 end)
        P.Do(btn, "SetScript", "PreClick", function() counts.pre = counts.pre + 1 end)
        P.Do(btn, "SetScript", "PostClick", function() counts.post = counts.post + 1 end)
        P.Do(btn, "Show")
    end
    local results = {}
    local function Step(name, change)
        Normal()
        local bad = {}
        for _, c in ipairs(change) do
            if type(c) == "function" then
                c()
            else
                local st, err = P.Do(btn, c[1], unpack(c, 2))
                if st ~= "ok" then bad[#bad + 1] = c[1] .. " " .. st .. (err and (": " .. err) or "") end
            end
        end
        local before = { on = counts.on, pre = counts.pre, post = counts.post }
        local state = P.State(btn)
        local st, err = P.Do(btn, "Click")
        local d = { on = counts.on - before.on, pre = counts.pre - before.pre, post = counts.post - before.post }
        results[name] = d
        t:Fact("api.click." .. name, ("OnClick +%d PreClick +%d PostClick +%d, Click() %s"):format(d.on, d.pre, d.post, st))
        t:Fact("api.click." .. name .. ".state", P.StateText(state))
        if st ~= "ok" then t:Note(("Click() on the %s button: %s %s"):format(name, st, err or "")) end
        if #bad > 0 then t:Note(("%s: setting up the state: %s"):format(name, table.concat(bad, "; "))) end
    end
    Step("visible-enabled", {})
    Step("disabled", { { "Disable" } })
    Step("hidden", { { "Hide" } })
    Step("mouse-disabled", { { "EnableMouse", false } })
    Step("click-disabled", { { "SetMouseClickEnabled", false } })
    Step("parent-hidden", { function() P.Do(parent, "Hide") end })   -- the button itself is shown; its parent is not
    local okA, constraints = RC.Call(btn, "HasAccessConstraints")
    t:Fact("api.click.has_access_constraints", okA and tostring(constraints) or "unavailable")
    t:Check(results["visible-enabled"] and results["visible-enabled"].on == 1,
        "control: Click() on a visible, enabled, mouse-on Lab button ran its OnClick once (if it did not, the other rows mean nothing)")
    t:Note("Click() is a programmatic call. It is NOT a physical click: whether a real click on the same button in the same state reaches OnClick is a different question (api.click.overlap measures real clicks). The counter harness only counts; nothing protected is clicked.")
    Clean(t)
end)

---------------------------------------------------------------------------
-- api.hitrect.insets
---------------------------------------------------------------------------
local function Near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.001 end

Own("api.hitrect.insets", function(t)
    NotInCombat(t)
    local f = P.Get("hit.frame", "Frame")
    if not f then t:Skip("a probe frame could not be made") end
    P.Do(f, "SetSize", 200, 100)
    P.Do(f, "SetPoint", "CENTER", UIParent, "CENTER", 0, 0)
    P.Do(f, "Show")
    t:Fact("api.hitrect.fn.SetHitRectInsets", type(f.SetHitRectInsets))
    t:Fact("api.hitrect.fn.GetHitRectInsets", type(f.GetHitRectInsets))
    if type(f.SetHitRectInsets) ~= "function" then Clean(t) t:Skip("this client has no SetHitRectInsets on a frame") end
    local okA, allowed = false, nil
    if C_RestrictedActions and C_RestrictedActions.CheckAllowProtectedFunctions then okA, allowed = pcall(C_RestrictedActions.CheckAllowProtectedFunctions, f, true) end
    t:Fact("api.hitrect.protected_allowed", okA and tostring(allowed) or "unavailable")
    local okC, canChange = RC.Call(f, "CanChangeProtectedState")
    t:Fact("api.hitrect.can_change_protected_state", okC and tostring(canChange) or "unavailable")
    local okP, prot, explicit = RC.Call(f, "IsProtected")
    t:Fact("api.hitrect.is_protected", okP and (tostring(prot) .. "/" .. tostring(explicit)) or "unavailable")
    t:Fact("api.hitrect.combat_at_start", InCombat())
    local sets = { { 0, 0, 0, 0 }, { 10, 20, 30, 40 }, { -10, -20, -30, -40 }, { 50, -50, 0, 0 }, { 150, 150, 0, 0 } }
    local refused
    local roundtrips, same = 0, 0
    for i, s in ipairs(sets) do
        local st, err = P.Do(f, "SetHitRectInsets", s[1], s[2], s[3], s[4])
        if st ~= "ok" then
            refused = refused or ("%s %s"):format(st, err or "")
            t:Fact(("api.hitrect.set%d"):format(i), ("set %g,%g,%g,%g: %s"):format(s[1], s[2], s[3], s[4], st))
        else
            local gst, l, r, tp, b = P.Do(f, "GetHitRectInsets")
            roundtrips = roundtrips + 1
            local equal = gst == "ok" and Near(l, s[1]) and Near(r, s[2]) and Near(tp, s[3]) and Near(b, s[4])
            if equal then same = same + 1 end
            t:Fact(("api.hitrect.set%d"):format(i), ("set %g,%g,%g,%g read %s,%s,%s,%s %s"):format(s[1], s[2], s[3], s[4], tostring(l), tostring(r), tostring(tp), tostring(b), equal and "same" or "DIFFERENT"))
            -- the Lab's own arithmetic on what the client reported: width and height of the hit rectangle against the frame's
            local hr = RC.HitRect(f)
            if hr and gst == "ok" and type(l) == "number" then
                local sc = hr.scale
                local wRect, hRect = hr.rect[3] - hr.rect[1], hr.rect[4] - hr.rect[2]
                local wHit, hHit = hr.hit[3] - hr.hit[1], hr.hit[4] - hr.hit[2]
                t:Check(Near(wHit, wRect - (l + r) * sc) and Near(hHit, hRect - (tp + b) * sc),
                    ("the model's hit rectangle follows the client's own insets %g,%g,%g,%g (left, right, top, bottom)"):format(l, r, tp, b))
            end
        end
    end
    P.Do(f, "SetHitRectInsets", 0, 0, 0, 0)
    t:Fact("api.hitrect.roundtrip", ("%d of %d reads equal what was set"):format(same, roundtrips))
    if refused then t:Note("SetHitRectInsets was refused at least once: " .. refused .. ". Recorded as an observed restriction; no other route was tried.") end
    t:Note("whether the POINTER region follows the insets needs a real click: api.hitrect.pointer (guided). The documentation marks SetHitRectInsets as a protected function; whether that applies to an addon's own unprotected frame out of combat is what the protected_allowed and set rows above record.")
    Clean(t)
end)

---------------------------------------------------------------------------
-- The guided cases
---------------------------------------------------------------------------
-- Waits for the pressed key while a key request is open. A press by the prompt's own buttons (or the countdown) is not a key press and is asked
-- again. Returns the snapshot of a key press, or nil and the last snapshot after G.MAX_ATTEMPTS.
local function AwaitKey(t)
    while true do
        local status, snap, err = G.Status()
        if status == "sample" then
            if snap.source == "key" then return snap end
            if not G.Retry(("that was the %s, not the key: press %s"):format(tostring(snap.source), G.KEY)) then return nil, snap end
        elseif status == "skipped" then
            t:Skip("you skipped this step")
        elseif status == "failed" then
            error("the sample could not be taken: " .. tostring(err), 0)
        elseif status == "idle" then
            t:Skip("the request was closed")
        else
            G.Poll()
        end
        t:Wait(0.05)
    end
end

Guide("api.binding.keypress", function(t)
    local before = Action(G.KEY)
    local function Capture(source, attempt) return { source = source, attempt = attempt, action = Action(G.KEY) } end
    local function Phase(title, lines)
        local ok, why = G.Begin{ title = title, lines = lines, capture = Capture }
        if not ok then t:Skip(why) end
        if G.Snapshot().bound == nil then
            t:Fact("api.keypress.bind_refused", "yes")
            t:Skip("the client would not bind the key, so there is no key press to observe (the key request fell back to the countdown only)")
        end
        return AwaitKey(t)
    end
    t:Fact("api.keypress.key", G.KEY)
    t:Fact("api.keypress.action_before", before)
    local first = Phase("Binding probe 1 of 2: the key reaches a Lab control", {
        ("The Lab has bound %s to its own hidden 1 x 1 button for this step only."):format(G.KEY),
        ("Press %s once. Do not click the buttons on this prompt (that is not a key press)."):format(G.KEY) })
    t:Fact("api.keypress.first", first and ("key press arrived (attempt %d)"):format(first.attempt) or "no key press arrived")
    if first then t:Fact("api.keypress.action_while_bound", first.action) end
    G.End()
    local cleared = Action(G.KEY)
    t:Fact("api.keypress.action_after_clear", cleared)
    local second = Phase("Binding probe 2 of 2: cleared, then registered again", {
        "The binding was cleared (nothing was bound for a moment) and has now been registered again.",
        ("Press %s once more."):format(G.KEY) })
    t:Fact("api.keypress.second", second and ("key press arrived (attempt %d)"):format(second.attempt) or "no key press arrived")
    G.End()
    local after = Action(G.KEY)
    t:Fact("api.keypress.action_after_final_clear", after)
    t:Note(("GetBindingAction(%s, true): before %s | while bound %s | after clearing %s | after the final clear %s"):format(G.KEY, before, first and first.action or "-", cleared, after))
    t:Check(first ~= nil, "a real key press reached the Lab-owned button while the binding was registered")
    t:Check(second ~= nil, "after the binding was cleared and registered again, a real key press reached the Lab-owned button again")
    t:Check(cleared == before and after == before, ("the key reports what it reported before once the binding is cleared (before %q, cleared %q, final %q)"):format(before, cleared, after))
    local live = G.Snapshot()
    t:Check(live.bound == nil and not live.proxyShown and not live.promptShown, "the binding, the key's button and the prompt are released")
    t:Note("a cleared binding is shown by GetBindingAction; that a press of the cleared key reaches nothing cannot be observed by code (the Lab never listens to the keyboard)")
    P.Release()
end)

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Click scenarios. def = { name, setup() -> info, lines(info) -> {text}, choices, unsupported(info) -> sentence | nil }.
-- One prompt for the whole case; each scenario sets up its arrangement, asks for ONE click inside the highlighted square (and, when the scenario
-- has choices, one answer about what is on top). A click outside the square is not counted and asked again. Returns a list of
-- { def, info, sum, choice, skipped, unsupported, tries }.
-- ---------------------------------------------------------------------------------------------------------------------------------
local VISUAL = {
    { id = "U", label = "Orange is on top" }, { id = "L", label = "Blue is on top" }, { id = "?", label = "I can't tell" },
}

local function Scenarios(t, title, defs)
    local out, began = {}, false
    for i, def in ipairs(defs) do
        local info = def.setup()
        local res = { def = def, info = info, tries = 0 }
        out[#out + 1] = res
        local why = def.unsupported and def.unsupported(info) or nil
        if why then
            res.unsupported, res.done = why, true
        else
            local req = { mode = "click", title = ("%s: %d of %d, %s"):format(title, i, #defs, def.name), lines = def.lines(info), choices = def.choices, status = "Waiting for your click." }
            if not began then
                local ok, wh = G.Begin(req)
                if not ok then t:Skip(wh) end
                began = true
            else
                G.Update(req)
            end
            P.NewTrial()
        end
        while not res.done do
            local status = G.Status()
            if status == "skipped" then
                res.skipped, res.done = true, true
            elseif status == "idle" then
                t:Skip("the request was closed")
            elseif not res.sum then
                if P.TrialDone() then
                    res.tries = res.tries + 1
                    local sum = P.Summarize(P.Trial(), P.Zone())
                    if sum.inZone == false then
                        if res.tries >= G.MAX_ATTEMPTS then
                            res.sum, res.done, res.notUsable = sum, true, true
                        else
                            G.Say(("Not counted (%d of %d): the pointer was %d px and %d px from the highlighted square. Click inside it."):format(res.tries, G.MAX_ATTEMPTS, sum.away[1], sum.away[2]))
                            P.NewTrial()
                        end
                    else
                        res.sum = sum
                        if def.after then
                            local okAfter, extra = pcall(def.after, res, sum)
                            res.extra = okAfter and extra or { error = tostring(extra) }
                        end
                        if def.choices then G.Say("Click recorded. Now answer the question above with the buttons.") else res.done = true end
                    end
                end
            elseif G.Choice() ~= nil then
                res.choice, res.done = G.Choice(), true
            end
            if not res.done then t:Wait(0.05) end
        end
    end
    G.End()
    return out
end

-- What the model (Reach.Analyze over just the arrangement's frames) says about a click at the highlighted square, as a piece name
local function ModelFor(target, targetPiece)
    local zone = P.Zone()
    if not zone then return nil, "no highlighted square" end
    local pt = { (zone[1] + zone[3]) / 2, (zone[2] + zone[4]) / 2 }
    if not target then return nil, "no target frame" end
    local collected = RC.Collect{ frames = P.Frames() }
    local res = RC.Analyze(target, { kind = "click", point = pt, collected = collected, evidence = "client-geometry" })
    local who
    if res.verdict == "reachable" then who = targetPiece
    elseif res.verdict == "blocked" then who = res.blocker and P.PieceByLabel(res.blocker.label) or "?"
    elseif res.verdict == "ambiguous" then who = "tie"
    else who = res.verdict end
    return who, res.verdict
end

local function Report(t, key, r, idx)
    local pre = ("%s.%s"):format(key, idx)
    if r.unsupported then
        t:Fact(pre .. ".unsupported", r.unsupported)
        t:Note(("%s: not measured, %s"):format(r.def.name, r.unsupported))
        return
    end
    if r.skipped then t:Fact(pre .. ".result", "skipped by you") t:Note(r.def.name .. ": skipped by you") return end
    local s = r.sum
    if r.notUsable then t:Fact(pre .. ".result", "no usable click") t:Note(r.def.name .. ": no click inside the square after " .. r.tries .. " tries") return end
    t:Fact(pre .. ".onclick", Join(s.clicks))
    t:Fact(pre .. ".mouseup", Join(s.ups))
    t:Fact(pre .. ".foci_top", s.foci[1] or (s.hasFoci and "none" or "unavailable"))
    t:Fact(pre .. ".foci", #s.foci > 0 and table.concat(s.foci, ">") or "none")
    if r.choice then t:Fact(pre .. ".visual", r.choice) end
end

Guide("api.click.overlap", function(t)
    local modes = {
        { id = "mouse-off", mode = "off", name = "the upper frame's mouse is OFF", note = "U cannot take the pointer" },
        { id = "mouse-on", mode = "frame", name = "the upper frame's mouse is ON", note = "U is a plain Frame with EnableMouse(true)" },
        { id = "clicks-off", mode = "noclick", name = "the upper frame's CLICKS are off (motion on)", note = "U has SetMouseClickEnabled(false)",
            unsupported = function(info) local st = info.status.clicks_off if st and st ~= "ok" then return "SetMouseClickEnabled " .. st end end },
        { id = "propagate", mode = "propagate", name = "the upper frame propagates clicks", note = "U has SetPropagateMouseClicks(true)",
            unsupported = function(info) local st = info.status.propagate if st and st ~= "ok" then return "SetPropagateMouseClicks " .. st end end },
    }
    local defs = {}
    for i, m in ipairs(modes) do
        defs[i] = { id = m.id, name = m.name, note = m.note, mode = m.mode, unsupported = m.unsupported,
            setup = function() return P.Overlap(m.mode) end,
            after = function(res, sum)
                local who, verdict = ModelFor(res.info.pieces.L, "L")
                return { who = who, verdict = verdict }
            end,
            lines = function(info)
                local l = { "A lower BLUE Button (L) and an upper ORANGE frame (U) overlap in the middle of the screen. Click ONCE inside the white square, where they overlap.",
                    m.note .. "." }
                if i == 1 then l[#l + 1] = "Then answer: which colour is drawn on top inside the white square?" end
                return l
            end,
            choices = i == 1 and VISUAL or nil }
    end
    local results = Scenarios(t, "Click probe", defs)
    for _, r in ipairs(results) do
        local d = r.def
        Report(t, "api.overlap", r, d.id)
        if r.sum and not r.notUsable then
            local s = r.sum
            local who, verdict = r.extra and r.extra.who, r.extra and r.extra.verdict
            local reachable = verdict == "reachable"
            local ranL = Has(s.clicks, "L")
            local agrees = verdict == "ambiguous" and "n/a (tie)" or ((reachable == ranL) and "yes" or "NO")
            t:Fact(("api.overlap.%s.model"):format(d.id), ("%s%s"):format(tostring(verdict), who and verdict == "blocked" and (" by " .. who) or ""))
            t:Fact(("api.overlap.%s.model_agrees_with_onclick"):format(d.id), agrees)
            t:Fact(("api.overlap.%s.foci_top_ran_onclick_or_up"):format(d.id), (s.foci[1] and (Has(s.clicks, s.foci[1]) or Has(s.ups, s.foci[1]))) and "yes" or "NO")
            t:Note(("%s | %s | setters: %s | U now %s | model: %s%s | model vs OnClick on L: %s%s"):format(d.name, s.text, d.mode == "off" and "none" or tostring(r.info.text),
                tostring(r.info.readback), tostring(verdict), who and verdict == "blocked" and (" by " .. who) or "", agrees,
                r.choice and (" | you saw: " .. (r.choice == "U" and "orange on top" or (r.choice == "L" and "blue on top" or "could not tell"))) or ""))
            t:Check(#s.downs > 0 or #s.ups > 0 or #s.clicks > 0, d.name .. ": a Lab-owned frame received the press (if none did, the arrangement itself failed)")
            t:Check(s.hasFoci, d.name .. ": GetMouseFoci answered")
        end
    end
    t:Fact("api.overlap.evidence", "GetMouseFoci, OnClick and what you saw: kept apart")
    t:Note("a row whose model_agrees is NO is a disagreement between the Lab's geometry model and the client: it is documented, not fixed, here (a narrow follow-up).")
    P.Release()
end)

Guide("api.order.equal-level", function(t)
    local specs = {
        { id = "s1", name = "created A first, shown A then B", spec = { pair = 1, order = "AB" } },
        { id = "s2", name = "created A first, shown B then A", spec = { pair = 1, order = "BA" } },
        { id = "s3", name = "created B first, shown A then B", spec = { pair = 2, order = "AB" } },
        { id = "s4", name = "each inside its own container (container 1 made first), shown A then B", spec = { pair = 1, order = "AB", parentage = "containers" } },
    }
    local choices = { { id = "B", label = "Orange (B) is on top" }, { id = "A", label = "Blue (A) is on top" }, { id = "?", label = "I can't tell" } }
    local defs = {}
    for i, s in ipairs(specs) do
        defs[i] = { id = s.id, name = s.name, spec = s.spec, choices = choices,
            setup = function() return P.Equal(s.spec) end,
            after = function(res, sum)
                local _, verdict = ModelFor(res.info.pieces.A, "A")
                return { verdict = verdict }
            end,
            lines = function(info)
                return { "Two Buttons, A (blue) and B (orange), have the SAME strata and the SAME frame level and overlap. Click ONCE inside the white square.",
                    "This arrangement: " .. info.text .. ".", "Then answer which colour is drawn on top inside the white square." }
            end }
    end
    local results = Scenarios(t, "Order probe", defs)
    local counts = { lastShown = { 0, 0 }, createdLast = { 0, 0 }, parentCreatedLast = { 0, 0 } }
    for _, r in ipairs(results) do
        local d = r.def
        Report(t, "api.order", r, d.id)
        if r.sum and not r.notUsable then
            local s = r.sum
            local top = s.foci[1]
            local clicked = s.clicks[1] or s.ups[1]
            local verdict = r.extra and r.extra.verdict
            t:Fact(("api.order.%s.model"):format(d.id), tostring(verdict))
            t:Fact(("api.order.%s.foci_equals_click"):format(d.id), (top and clicked and top == clicked) and "yes" or "NO")
            t:Fact(("api.order.%s.visual_equals_foci"):format(d.id), (r.choice and r.choice ~= "?" and r.choice == top) and "yes" or (r.choice == "?" and "not answered" or "NO"))
            t:Note(("%s | %s | %s | you saw: %s | model: %s"):format(d.name, r.info.text, s.text, r.choice == "A" and "blue (A) on top" or (r.choice == "B" and "orange (B) on top" or "could not tell"), tostring(verdict)))
            t:Check(#s.downs > 0 or #s.ups > 0 or #s.clicks > 0, d.name .. ": a Lab-owned frame received the press")
            t:Check(s.hasFoci, d.name .. ": GetMouseFoci answered")
            for key, letter in pairs({ lastShown = r.info.lastShown, createdLast = r.info.createdLast, parentCreatedLast = r.info.parentCreatedLast }) do
                counts[key][2] = counts[key][2] + 1
                if top == letter then counts[key][1] = counts[key][1] + 1 end
            end
        end
    end
    for _, key in ipairs({ "lastShown", "createdLast", "parentCreatedLast" }) do
        local c = counts[key]
        t:Fact("api.order.top_is_" .. key, c[2] > 0 and ("%d of %d scenarios"):format(c[1], c[2]) or "not measured")
    end
    local rule = "not enough scenarios measured"
    for _, key in ipairs({ "lastShown", "createdLast" }) do
        local c = counts[key]
        if c[2] >= 3 and c[1] == c[2] then rule = "top = " .. (key == "lastShown" and "last frame shown" or "last frame created") .. " in every scenario" end
    end
    if rule == "not enough scenarios measured" and counts.lastShown[2] >= 3 then rule = "no single rule among creation and show order" end
    t:Fact("api.order.observation", rule)
    t:Fact("api.order.analyzer", "unchanged: equal strata and level stays ambiguous")
    t:Note("observed in four arrangements on this client at one moment. It is NOT a universal rule and the analyzer keeps its ambiguous verdict whatever it says; if the order depended on the context here, that is the reason it stays ambiguous.")
    P.Release()
end)

Guide("api.hitrect.pointer", function(t)
    local probeArea = P.HitArea()
    local setupStatus = probeArea.status.insets
    t:Fact("api.hitrect.pointer.set_insets", setupStatus)
    if setupStatus ~= "ok" then
        local msg = ("the client did not take SetHitRectInsets (%s): recorded as an observed restriction, nothing to measure with a click"):format(setupStatus)
        P.Release()
        t:Skip(msg)
    end
    t:Fact("api.hitrect.pointer.read_back", probeArea.readback and ("%g,%g,%g,%g"):format(unpack(probeArea.readback)) or tostring(probeArea.readStatus))
    local defs = {}
    for i, z in ipairs(probeArea.zones) do
        defs[i] = { id = z.id, name = z.text, zone = z,
            setup = function() local a = P.HitArea(); P.Mark(z.x, z.y, z.w, z.h, "click inside this square") return a end,
            after = function(res, sum)   -- the model, on the client's own rectangle and insets, at the place the pointer really was
                local T = res.info.target
                local hr = T and RC.HitRect(T)
                local f = P.Trial() and P.Trial().first
                if hr and f and f.x and f.y then
                    return { modelHit = f.x >= hr.hit[1] and f.x <= hr.hit[3] and f.y >= hr.hit[2] and f.y <= hr.hit[4] }
                end
                return {}
            end,
            lines = function(info)
                return { "A teal Button is drawn in the middle of the screen. Its hit rectangle has insets L70 R-50 (70 px removed on the left, 50 px added on the right).",
                    "Click ONCE inside the white square: " .. z.text .. "." }
            end }
    end
    local results = Scenarios(t, "Hit-rectangle probe", defs)
    for _, r in ipairs(results) do
        local d = r.def
        Report(t, "api.hitrect.pointer", r, d.id)
        if r.sum and not r.notUsable then
            local s = r.sum
            local modelHit = r.extra and r.extra.modelHit
            local gotT = Has(s.clicks, "T")
            t:Fact(("api.hitrect.pointer.%s.onclick_on_T"):format(d.id), gotT)
            t:Fact(("api.hitrect.pointer.%s.model_says_inside"):format(d.id), modelHit == nil and "unknown" or modelHit)
            t:Note(("%s | %s | the model (rectangle and insets as the client reports them) puts the pointer %s the hit rectangle"):format(d.name, s.text,
                modelHit == nil and "(unknown) relative to" or (modelHit and "INSIDE" or "OUTSIDE")))
            t:Check(#s.downs > 0 or #s.ups > 0 or #s.clicks > 0, d.name .. ": a Lab-owned frame received the press")
            if modelHit ~= nil then
                t:Check(modelHit == gotT, ("%s: the model said %s the hit rectangle and OnClick %s on the button"):format(d.name, modelHit and "inside" or "outside", gotT and "ran" or "did not run"))
            end
        end
    end
    P.Release()
end)
