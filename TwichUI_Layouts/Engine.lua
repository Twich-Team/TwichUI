-- TwichUI Layouts: the pipeline (architecture.md §8, §9)
--
--   LY.Plan(pkg, variant, opts)    read only: what an install would do, adapter by adapter, with a key
--   LY.Apply(pkg, variant, key, opts)  does exactly the plan with that key (re-planned first; refused if it differs)
--   opts = { screen = { w, h } (default: this screen, LY.Geometry.Live()), density = id } for a package with geometry
--   LY.Verify(record)              reads live values against what the install expects; record = true writes the result
--   LY.PlanRestore(), LY.Restore(key), LY.VerifyRestore(record)
--   LY.Continue()                  after a reload (the core calls it): checks what the install or restore left
--   LY.Detach()                    forgets the record; changes nothing else
--
-- Rules every part of this follows:
--   * Nothing changes without the caller passing the key of a plan the player was shown. Apply and Restore are refused
--     in combat here, not only by whatever asked.
--   * The snapshot is complete and checked before the record is written, and the record is written before the first
--     change. Installing again keeps the first snapshot: Restore always goes back to before the first install.
--   * Apply runs the adapters in order (EllesmereUI first: it is the part most likely to refuse) and stops at the first
--     failure. Across addons this is not atomic: the result lists each step as done, skipped, failed (rolled back or
--     not) or not run. A failure that changed nothing leaves no record behind (or the previous one, unchanged).
--   * Writing values is not success. An install that needs a reload is "applied", and is "verified" only once Verify
--     has read every managed value back after the reload. Nothing here reloads: the player does.

local R = TwichUI
local LY = R.Layouts
local J = LY.Journal
local Perf = R.Perf

LY.APPLY_ORDER = { "ellesmereui", "twichui" }

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Me() return R.Profiles and R.Profiles.Character() or nil end

local LibDeflate = LibStub("LibDeflate")
local function Short(key) return "#" .. tostring(LibDeflate:Adler32(key)) .. ":" .. #key end

---------------------------------------------------------------------------
-- Plan
-- plan = { ok, problems, blocked = { { adapter, code } }, id, revision, variant, title, dev, order = { adapter ids },
--   parts = { [adapter] = part (each adapter's Plan) }, changes, reload, mode = "new"|"again", key,
--   geometry = the resolved screen (Geometry.lua) | nil, density }
---------------------------------------------------------------------------
local function DoPlan(pkg, variant, opts)
    opts = opts or {}
    local plan = { blocked = {}, parts = {}, order = {}, changes = 0, reload = false }
    local screen = opts.screen
    if pkg.geometry ~= nil and screen == nil then
        screen = LY.Geometry.Live()
        if not screen then plan.blocked[1] = { code = "no-screen" } end
    end
    local ok, resolved = LY.Resolve(pkg, variant, { screen = screen, density = opts.density })
    if not ok then plan.problems = resolved return plan end
    plan.geometry, plan.density = resolved.geometry, resolved.geometry and resolved.geometry.density or nil
    plan.id, plan.revision, plan.variant, plan.title, plan.dev = resolved.id, resolved.revision, variant, pkg.title, resolved.dev
    plan.targets = resolved.targets
    local function Block(adapter, code) plan.blocked[#plan.blocked + 1] = { adapter = adapter, code = code } end

    local journal, why = J.Read()
    if why then Block(nil, "journal-" .. why) end
    if journal then
        if journal.package ~= resolved.id then Block(nil, "journal-other-package")
        elseif journal.state == "restoring" then Block(nil, "restore-pending") end
        if journal.char ~= Me() then Block(nil, "journal-other-character") end
    end
    plan.mode = journal and "again" or "new"
    plan.journal = journal
    for _, id in ipairs(LY.APPLY_ORDER) do
        local composed = resolved.adapters[id]
        if composed then
            local a = LY.ADAPTERS[id]
            local part = a.Plan(composed, {
                target = resolved.targets[id], snapshot = journal and journal.snapshot[id],
                requires = pkg.requires and pkg.requires[id], dev = resolved.dev,
                lastInputs = journal and journal.inputs and journal.inputs[id],
                geometry = resolved.geometry, attach = resolved.attach and resolved.attach[id],
            })
            part.composed = composed
            plan.parts[id] = part
            plan.order[#plan.order + 1] = id
            if part.blocked then Block(id, part.blocked) end
            if part.reload then plan.reload = true end
            plan.changes = plan.changes + (part.changes or 0)
        end
    end
    local keys = {}
    for _, id in ipairs(plan.order) do keys[id] = plan.parts[id].key or "" end
    -- the screen the places were worked out for is part of what was shown
    local screenKey = resolved.geometry and { math.floor(resolved.geometry.screen.w + 0.5), math.floor(resolved.geometry.screen.h + 0.5),
        resolved.geometry.density } or false
    plan.key = LY.Canon({ plan.id, plan.revision, variant, plan.mode, keys, screenKey })
    plan.ok = #plan.blocked == 0
    return plan
end

function LY.Plan(pkg, variant, opts) return Perf.Call("layouts.plan", DoPlan, pkg, variant, opts) end

---------------------------------------------------------------------------
-- Verify
---------------------------------------------------------------------------
-- report = { state = "match"|"mismatch"|"unverifiable"|"partial", adapters = { [adapter] = adapter report } }
local function Combine(reports)
    local state, any, unv = "match", false, false
    for _, r in pairs(reports) do
        any = true
        if r.state == "mismatch" then state = "mismatch"
        elseif r.state == "unverifiable" then unv = true end
    end
    if not any then return "unverifiable" end
    if state == "match" and unv then return "partial" end
    return state
end

local function DoVerify(record)
    local j, why = J.Read()
    if not j then return nil, why or "none" end
    local reports = {}
    for _, step in ipairs(j.steps) do
        if step.state == "done" or step.state == "skipped" then
            local a = LY.ADAPTERS[step.adapter]
            local ok, r = pcall(a.Verify, j.expect[step.adapter] or {}, j.snapshot[step.adapter])
            if not ok then R.Fault("layouts verify " .. step.adapter, r); r = { state = "unverifiable", code = "error", diffs = {} } end
            reports[step.adapter] = r
        end
    end
    local report = { state = Combine(reports), adapters = reports }
    if record and (j.state == "applied" or j.state == "verified" or j.state == "mismatch" or j.state == "interrupted") then
        -- "mismatch" is "not verified": verify.state says whether something differs or could not be read
        j.verify = { state = report.state, at = time(), diffs = J.Diffs(reports) }
        j.state = report.state == "match" and "verified" or "mismatch"
        j.reload = false
        J.Write(j)
    end
    return report
end

function LY.Verify(record) return Perf.Call("layouts.verify", DoVerify, record) end

---------------------------------------------------------------------------
-- Apply
-- Returns true, result | false, code, plan-or-extra. result = { state, record, verify = report|nil }
--   codes: combat, blocked, stale, nothing, snapshot (the snapshot could not be made usable)
---------------------------------------------------------------------------
local function DoApply(pkg, variant, expect, opts)
    if InCombat() then return false, "combat" end
    local plan = DoPlan(pkg, variant, opts)
    if not plan.ok then return false, "blocked", plan end
    if type(expect) ~= "string" or plan.key ~= expect then return false, "stale", plan end
    local allNothing = true
    for _, id in ipairs(plan.order) do if not plan.parts[id].nothing then allNothing = false end end
    if allNothing then return false, "nothing", plan end

    local previous = plan.journal
    local snapshot
    if previous then
        snapshot = previous.snapshot   -- the state before the first install: never replaced by a later one
    else
        snapshot = {}
        for _, id in ipairs(plan.order) do
            snapshot[id] = LY.ADAPTERS[id].Capture(plan.parts[id].composed, plan.targets[id], plan.parts[id])
        end
        local okSnap, why = J.CleanSnapshot(snapshot)
        if not okSnap then return false, "snapshot", why end
    end

    local record = { v = J.VERSION, package = plan.id, revision = plan.revision, variant = variant, char = Me(),
        state = "applying", at = time(), key = Short(plan.key), reload = false, steps = {}, snapshot = snapshot,
        expect = {}, inputs = {} }
    for _, id in ipairs(plan.order) do
        record.steps[#record.steps + 1] = { adapter = id, state = "pending" }
        record.expect[id] = LY.ADAPTERS[id].Expect(plan.parts[id].composed, plan.parts[id])
        record.inputs[id] = plan.parts[id].inputs or (previous and previous.inputs and previous.inputs[id])
    end
    J.Write(record)

    local failed = false
    for i, id in ipairs(plan.order) do
        local step = record.steps[i]
        local ok, res = pcall(LY.ADAPTERS[id].Apply, plan.parts[id])
        if not ok then
            R.Fault("layouts apply " .. id, res)
            res = { state = "failed", code = "error", rollback = "unknown" }
        end
        step.state, step.code, step.rollback = res.state, res.code, res.rollback
        if res.reload then step.reload, record.reload = true, true end
        if res.state == "failed" then
            failed = true
            for k = i + 1, #record.steps do record.steps[k].state = "not-run" end
            break
        end
    end

    if failed then
        local changed = false
        for _, s in ipairs(record.steps) do
            if s.state == "done" or s.state == "partial" or (s.state == "failed" and s.rollback ~= "clean") then changed = true end
        end
        if not changed then
            -- Nothing was changed: the previous record (or none) stands as it was.
            if previous then J.Write(previous) else J.Clear() end
            return true, { state = "failed", steps = record.steps, record = nil, changed = false }
        end
        record.state = "partial"
        J.Write(record)
        return true, { state = "partial", steps = record.steps, record = record, changed = true }
    end
    if record.reload then
        record.state = "applied"
        J.Write(record)
        return true, { state = "applied", steps = record.steps, record = record, changed = true }
    end
    -- Nothing waits for a reload: read everything back now.
    record.state = "applied"
    J.Write(record)
    local report = DoVerify(true)
    local now = J.Read()
    return true, { state = now and now.state or "applied", steps = record.steps, record = now, verify = report, changed = true }
end

function LY.Apply(pkg, variant, expect, opts) return Perf.Call("layouts.apply", DoApply, pkg, variant, expect, opts) end

---------------------------------------------------------------------------
-- Restore
-- plan = { ok, blocked = { { adapter, code } }, order, parts = { [adapter] = { actions, reload } }, reload, key }
---------------------------------------------------------------------------
local RESTORABLE = LY.Set({ "applied", "verified", "mismatch", "partial", "interrupted", "restore-partial" })

local function RestoreOrder(j)
    local order = {}
    for i = #j.steps, 1, -1 do order[#order + 1] = j.steps[i].adapter end
    return order
end

function LY.PlanRestore()
    local plan = { blocked = {}, parts = {}, order = {}, reload = false }
    local j, why = J.Read()
    if not j then plan.blocked[1] = { code = why and ("journal-" .. why) or "none" } return plan end
    plan.record = j
    if not RESTORABLE[j.state] then plan.blocked[1] = { code = j.state == "restoring" and "restore-pending" or "not-restorable" } return plan end
    if j.char ~= Me() then plan.blocked[1] = { code = "journal-other-character" } return plan end
    local keys = {}
    for _, id in ipairs(RestoreOrder(j)) do
        local snap = j.snapshot[id]
        if snap then
            local part = LY.ADAPTERS[id].PlanRestore(snap)
            plan.parts[id] = part
            plan.order[#plan.order + 1] = id
            if part.blocked then plan.blocked[#plan.blocked + 1] = { adapter = id, code = part.blocked } end
            if part.reload then plan.reload = true end
            keys[id] = part.key or ""
        end
    end
    plan.key = LY.Canon({ j.package, j.key, keys })
    plan.ok = #plan.blocked == 0
    return plan
end

local function Units(j, id)
    return LY.SortedKeys(j.expect[id] or {})
end

local function DoVerifyRestore(record)
    local j, why = J.Read()
    if not j then return nil, why or "none" end
    local reports = {}
    for _, id in ipairs(RestoreOrder(j)) do
        local snap = j.snapshot[id]
        if snap then
            local ok, r = pcall(LY.ADAPTERS[id].VerifyRestore, snap, Units(j, id))
            if not ok then R.Fault("layouts verify restore " .. id, r); r = { state = "unverifiable", code = "error", diffs = {} } end
            reports[id] = r
        end
    end
    local report = { state = Combine(reports), adapters = reports }
    if record then
        if report.state == "match" then
            J.Clear()   -- finished with: the record held nothing else worth keeping
            report.cleared = true
        else
            j.state = "restore-partial"
            j.verify = { state = report.state, at = time(), diffs = J.Diffs(reports) }
            J.Write(j)
        end
    end
    return report
end

function LY.VerifyRestore(record) return Perf.Call("layouts.verify", DoVerifyRestore, record) end

-- Returns true, result | false, code, plan. result = { state = "restoring"|"restored"|"restore-partial", steps, verify }
local function DoRestore(expect)
    if InCombat() then return false, "combat" end
    local plan = LY.PlanRestore()
    if not plan.ok then return false, "blocked", plan end
    if type(expect) ~= "string" or plan.key ~= expect then return false, "stale", plan end
    local j = plan.record
    j.restore = { at = time(), steps = {} }
    for _, id in ipairs(plan.order) do j.restore.steps[#j.restore.steps + 1] = { adapter = id, state = "pending" } end
    j.state = "restore-partial"   -- what a stop part way through would leave
    J.Write(j)
    local reload, bad = false, false
    for i, id in ipairs(plan.order) do
        local step = j.restore.steps[i]
        local ok, res = pcall(LY.ADAPTERS[id].Restore, j.snapshot[id])
        if not ok then R.Fault("layouts restore " .. id, res); res = { state = "failed", code = "error" } end
        step.state, step.code = res.state, res.code
        if res.reload then step.reload, reload = true, true end
        if res.state ~= "done" then
            bad = true
            for k = i + 1, #j.restore.steps do j.restore.steps[k].state = "not-run" end
            break
        end
    end
    if bad then
        j.state = "restore-partial"
        J.Write(j)
        return true, { state = "restore-partial", steps = j.restore.steps }
    end
    if reload then
        j.state = "restoring"
        j.reload = true
        J.Write(j)
        return true, { state = "restoring", steps = j.restore.steps }
    end
    local steps = j.restore.steps
    local report = DoVerifyRestore(true)
    return true, { state = report.cleared and "restored" or "restore-partial", steps = steps, verify = report }
end

function LY.Restore(expect) return Perf.Call("layouts.restore", DoRestore, expect) end

---------------------------------------------------------------------------
-- After a reload, and forgetting
---------------------------------------------------------------------------
-- Called by the core (LayoutsLauncher.lua) a few seconds after login while the record waits for a load. Only reads and
-- records what it found; it never applies or restores anything. On another character it does nothing.
-- Returns what it did: "interrupted", "verified", "mismatch", "partial", "restored", "restore-partial", or nil.
function LY.Continue()
    local j = J.Read()
    if not j or j.char ~= Me() then return nil end
    local said
    if j.state == "applying" then
        j.state = "interrupted"
        J.Write(j)
        said = "interrupted"
    elseif j.state == "applied" then
        local report = LY.Verify(true)
        said = report and report.state or nil
        if said == "match" then said = "verified" end
    elseif j.state == "restoring" then
        local report = LY.VerifyRestore(true)
        said = report and (report.cleared and "restored" or "restore-partial") or nil
    end
    if said and LY.Tell then LY.Tell(said) end
    return said
end

function LY.Detach()
    if not J.Exists() then return false end
    J.Clear()
    return true
end
