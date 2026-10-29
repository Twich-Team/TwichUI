-- TwichUI Layouts: the pipeline (architecture.md §6, §9)
--
--   LY.Plan(pkg, variant, opts)    read only: what an install would do, adapter by adapter, with a key
--   LY.Apply(pkg, variant, key, opts)  does exactly the plan with that key (re-planned first; refused if it differs)
--   opts = { screen = { w, h } (default: this screen, LY.Geometry.Live()), density = id, picks = { [choice] = option } }
--     (screen and density for a package with geometry; picks for a package with choices: what the wizard asked)
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
--   geometry = the resolved screen (Geometry.lua) | nil, density, picks = { [choice id] = option id } (every choice) }
---------------------------------------------------------------------------
-- opts.update (an install again; updates.md) = { policy = "keep" | "recommended", choose = { [unit] = "mine" | "package" |
--   "own" | "manage" }, groups = { [group] = "mine" | "package" }, whole = { [adapter] = "keep" | "replace" } }.
-- opts.force = true (the wizard's "Force re-apply"): plan as a new install over whatever an earlier one left: this character's own
--   install and management records (or a damaged one) are set aside, a profile already named for the install is taken over, and an
--   install that matches is made again. Only the plan says so: plan.forced = { replaced = state of the record set aside | nil,
--   journal = that record, otherCharacter = it was another character's }. Not lifted: a record from a newer TwichUI, combat, a missing or unusable
--   EllesmereUI, EllesmereUI's first-run picker, a package that can't be used.
-- plan.update = { baseline = "ok" | "none" | "other" | "damaged", policy, resume, counts, rows = { row }, warnings, whole,
--   groups, fresh = { [adapter] = why } } (rows: Merge.lua's, each with its adapter), for an install again.
local UPDATE_STATES = LY.Set({ "verified", "mismatch" })   -- settled: an update from here keeps a way back to here
local RESUME_STATES = LY.Set({ "partial", "interrupted" })  -- an update that stopped: steps already done are not done again

local function Opts(u)
    u = type(u) == "table" and u or {}
    local choose = {}
    local n = 0
    for unit, c in pairs(type(u.choose) == "table" and u.choose or {}) do
        n = n + 1
        if n > LY.Merge.MAX_CHOICES then break end
        if type(unit) == "string" and LY.Merge.CHOICES[c] then choose[unit] = c end
    end
    local groups = {}
    for g, c in pairs(type(u.groups) == "table" and u.groups or {}) do if c == "mine" or c == "package" then groups[g] = c end end
    local whole = {}
    for id, c in pairs(type(u.whole) == "table" and u.whole or {}) do if c == "keep" or c == "replace" then whole[id] = c end end
    return { policy = LY.Merge.POLICIES[u.policy] and u.policy or "keep", choose = choose, groups = groups, whole = whole }
end

local function DoPlan(pkg, variant, opts)
    opts = opts or {}
    local plan = { blocked = {}, parts = {}, order = {}, changes = 0, reload = false }
    local screen = opts.screen
    if pkg.geometry ~= nil and screen == nil then
        screen = LY.Geometry.Live()
        if not screen then plan.blocked[1] = { code = "no-screen" } end
    end
    local ok, resolved = LY.Resolve(pkg, variant, { screen = screen, density = opts.density, picks = opts.picks })
    if not ok then plan.problems = resolved return plan end
    plan.geometry, plan.density = resolved.geometry, resolved.geometry and resolved.geometry.density or nil
    plan.id, plan.revision, plan.variant, plan.title, plan.dev = resolved.id, resolved.revision, variant, pkg.title, resolved.dev
    plan.targets = resolved.targets
    plan.picks = resolved.picks
    local function Block(adapter, code) plan.blocked[#plan.blocked + 1] = { adapter = adapter, code = code } end

    local journal, why = J.Read()
    -- Forced (opts.force, "Force re-apply"): an earlier install's record that is damaged, or this character's own, is set aside and
    -- this install is planned as a new one, so a stopped restore, a failed install or another package's record can't hold it.
    -- A record from a newer TwichUI is still respected: it can't be read. Another character's is set aside too (there is one
    -- install record for the account), and the plan says whose it was (forced.otherCharacter) so the player is told it is gone.
    local forced
    if opts.force == true then
        forced = {}
        if why == "damaged" or journal then
            forced.replaced = journal and journal.state or why
            forced.otherCharacter = journal and journal.char ~= Me() or nil
            forced.journal = journal   -- kept to be written back if the install then changes nothing
            journal, why = nil, nil
        end
    end
    if why then Block(nil, "journal-" .. why) end
    if journal then
        if journal.package ~= resolved.id then Block(nil, "journal-other-package")
        elseif journal.state == "restoring" then Block(nil, "restore-pending")
        elseif journal.state == "undoing" then Block(nil, "undo-pending")
        -- a Restore or an Undo that stopped part way is finished (or retried) first: an update started from there would
        -- build on a state that is neither the install nor what came before it (RH-1 B2)
        elseif journal.state == "restore-partial" then Block(nil, "restore-unfinished")
        elseif journal.state == "undo-partial" then Block(nil, "undo-unfinished") end
        if journal.char ~= Me() then Block(nil, "journal-other-character") end
    end
    -- With no install record, a layout whose setup was finished is still managed: its management record says which package
    -- and layout are installed and which profiles are the install's own, and the baseline is still the last checked install.
    local managed
    if not journal and not why then
        local m, mwhy = J.ReadManaged()
        if mwhy == "newer" then Block(nil, "managed-newer") end
        if m and forced then
            forced.replaced = forced.replaced or "managed"
            forced.otherCharacter = forced.otherCharacter or m.char ~= Me() or nil
            m = nil
        end
        if m and m.package == resolved.id then
            if m.char ~= Me() then Block(nil, "journal-other-character") end
            managed = m
        elseif m then
            Block(nil, "journal-other-package")
        end
    end
    plan.mode = (journal or managed) and "again" or "new"
    plan.journal, plan.managed, plan.forced = journal, managed, forced
    local installed = journal or managed

    -- An install again is an update: each unit is compared with the baseline (the last install that checked out) and with
    -- what the recipient has now (Merge.lua). Without a usable baseline nothing can be told apart, so a unit that differs
    -- is kept as the recipient has it unless they choose otherwise.
    local uopts, baseline, upd
    if installed then
        uopts = Opts(opts.update)
        local b, bwhy = J.ReadBaseline()
        if bwhy == "newer" then Block(nil, "baseline-newer") end
        local state = b and ((b.package == resolved.id and b.char == Me()) and "ok" or "other") or (bwhy or "none")
        baseline = state == "ok" and b or nil
        upd = { baseline = state, policy = uopts.policy, rows = {}, warnings = {}, counts = {}, whole = {}, groups = {}, fresh = {},
            switching = installed.variant ~= variant and installed.variant or nil }
        plan.update = upd
        -- a stopped update whose package, layout, choices and screen are the same as before: its done steps stay done
        if journal and RESUME_STATES[journal.state] and journal.update and journal.revision == resolved.revision and journal.variant == variant
            and LY.Same(journal.picks or {}, next(resolved.picks) ~= nil and resolved.picks or {}) then
            upd.resume = true
        end
    end
    for _, id in ipairs(LY.APPLY_ORDER) do
        local composed = resolved.adapters[id]
        if composed then
            local a = LY.ADAPTERS[id]
            local merge
            if uopts then
                merge = { part = baseline and baseline.parts[id] or nil, known = baseline ~= nil and baseline.parts[id] ~= nil,
                    policy = uopts.policy, choose = uopts.choose, groups = uopts.groups, whole = uopts.whole[id],
                    switching = installed.variant ~= variant }
            end
            local done = upd and upd.resume and (function()
                for _, s in ipairs(journal.steps) do if s.adapter == id then return s.state == "done" end end
            end)()
            local part
            if done then
                -- done in the attempt that stopped: not planned or applied again
                part = { adapter = id, rows = {}, changes = 0, nothing = true, resumed = true, key = "resumed", reload = false }
            else
                part = a.Plan(composed, {
                    target = resolved.targets[id], snapshot = journal and journal.snapshot[id],
                    requires = pkg.requires and pkg.requires[id], dev = resolved.dev,
                    lastInputs = journal and journal.inputs and journal.inputs[id],
                    geometry = resolved.geometry, attach = resolved.attach and resolved.attach[id],
                    merge = merge,
                    backup = journal and journal.euiBackup,
                    -- "new": keep the install's profile as it is now (a settled install); "keep": the copy an earlier, stopped
                    -- attempt kept stands, and the profile is replaced in place; "none": no way back is kept
                    backupMode = journal and (UPDATE_STATES[journal.state] and "new" or (journal.update and "keep") or "none")
                        or (managed and "new") or nil,
                    -- the install's own profile, by the management record, once the setup was finished (no snapshot says so)
                    owned = forced ~= nil or (managed ~= nil and managed.targets[id] == resolved.targets[id]),
                    force = forced ~= nil,
                    home = managed and managed.home[id] or nil,
                })
            end
            part.composed = composed
            plan.parts[id] = part
            plan.order[#plan.order + 1] = id
            if part.blocked then Block(id, part.blocked) end
            if part.reload then plan.reload = true end
            plan.changes = plan.changes + (part.changes or 0)
            if upd and part.merge then
                for _, row in ipairs(part.merge.rows) do
                    row.adapter = id
                    upd.rows[#upd.rows + 1] = row
                    upd.counts[row.decision] = (upd.counts[row.decision] or 0) + 1
                    if row.case == "conflict" then upd.counts.conflict = (upd.counts.conflict or 0) + 1 end
                    if row.case == "added" then upd.counts.added = (upd.counts.added or 0) + 1 end
                    if row.case == "unknown" then upd.counts.unknown = (upd.counts.unknown or 0) + 1 end
                end
                for _, w in ipairs(part.warnings or {}) do w.adapter = id; upd.warnings[#upd.warnings + 1] = w end
                if part.merge.whole then upd.whole[id] = part.merge.whole end
                for g, info in pairs(part.merge.groups) do if info.conflict then upd.groups[g] = { adapter = id, choice = info.choice, owned = info.owned } end end
            end
            if upd and part.fresh then upd.fresh[id] = part.fresh end
        end
    end
    -- The final plan (RH-1 C): the recommended geometry with what the update leaves where the player has it. Component
    -- frames the player placed and sized (the minimap, chat, the meter) take their rect; positions and places they keep are
    -- listed (and moved in the preview and the fit check); EllesmereUI kept as it is keeps all of its own. exact: the final
    -- plan is the recommended one (nothing retained).
    if upd and plan.geometry then
        local rects, retained, moved, whole = {}, {}, {}, {}
        for _, id in ipairs(plan.order) do
            local part = plan.parts[id]
            for comp, r in pairs(part.final or {}) do rects[comp] = r end
            for _, it in ipairs(part.retained or {}) do
                retained[#retained + 1] = it
                if it.rec then moved[it.id] = it.rec elseif it.value then moved[it.id] = it.value end
            end
            if part.retainedAll then whole[#whole + 1] = id end
        end
        local geo = next(rects) and LY.Geometry.WithRects(plan.geometry, rects) or plan.geometry
        plan.final = { geometry = geo, retained = retained, moved = moved, whole = whole, exact = #retained == 0 and #whole == 0,
            fit = LY.Fit and LY.Fit(pkg, variant, geo, moved) or nil }
    end
    -- An update with nothing to write is still worth recording when it moves the install to another revision, layout or
    -- choices, or releases or claims a setting: the record, the management record and the baseline then say so.
    if upd then
        local changed = installed.revision ~= resolved.revision or installed.variant ~= variant
            or not LY.Same(installed.picks or {}, next(resolved.picks) ~= nil and resolved.picks or {})
        for _, row in ipairs(upd.rows) do
            if row.decision == "release" or (row.decision == "owned" and row.case ~= "owned") then changed = true end
        end
        upd.recordOnly = changed or nil
    end
    local keys = {}
    for _, id in ipairs(plan.order) do keys[id] = plan.parts[id].key or "" end
    -- the screen the places were worked out for is part of what was shown
    local screenKey = resolved.geometry and { math.floor(resolved.geometry.screen.w + 0.5), math.floor(resolved.geometry.screen.h + 0.5),
        resolved.geometry.density } or false
    plan.key = LY.Canon({ plan.id, plan.revision, variant, plan.mode, keys, screenKey, resolved.picks, uopts and uopts.policy or false,
        upd and upd.resume or false, forced ~= nil })
    plan.ok = #plan.blocked == 0
    return plan
end

function LY.Plan(pkg, variant, opts) return Perf.Call("layouts.plan", DoPlan, pkg, variant, opts) end

---------------------------------------------------------------------------
-- The option of an enum choice that matches what the game has now, for an install that already exists whose player never made that
-- choice (a choice added after they set up): the one option every readable setting of which reads as the option says. Read only.
-- Settings that can't be read as a value (a place, a blob) don't decide it. nil when no option matches or more than one does, so the
-- choice keeps its default and the plan says what picking it would change.
---------------------------------------------------------------------------
function LY.LivePick(pkg, choiceId)
    local ok, _, checked = LY.Validate(pkg)
    local ch = ok and checked.choices and checked.choices.by[choiceId]
    if not ch or ch.kind ~= "enum" then return nil end
    local match
    for _, oid in ipairs(ch.order) do
        local all, any = true, false
        for adapterId, frag in pairs(ch.options[oid].frags) do
            local a = LY.ADAPTERS[adapterId]
            for unit, value in pairs(frag.units) do
                local okLive, live = pcall(a.Live or function() end, unit, pkg.targets and pkg.targets[adapterId])
                if okLive and live ~= nil then
                    any = true
                    local want = a.LiveValue and a.LiveValue(unit, value) or value
                    if not LY.Same(live, want) then all = false end
                end
            end
        end
        if any and all then
            if match then return nil end
            match = oid
        end
    end
    return match
end

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

-- The baseline takes, for each adapter whose check matched, what its units read now (Journal.lua). An adapter that didn't
-- match, or was kept as it was, leaves its part of the baseline as it was: an update that didn't check out never replaces
-- the last one that did.
local function Commit(j, reports)
    local committed = {}
    for _, id in ipairs(LY.SortedKeys(reports)) do
        local a = LY.ADAPTERS[id]
        if reports[id].state == "match" and j.track and j.track[id] and a.Baseline then
            local ok, units, schema = pcall(a.Baseline, j.track[id], j.snapshot[id])
            if not ok then R.Fault("layouts baseline " .. id, units)
            elseif units then
                J.CommitBaseline(j, id, units, schema, j.screen)
                committed[#committed + 1] = id
            end
        end
    end
    return committed
end

-- The management record after a recorded check: the package, layout and choices now installed, and the install's own
-- profiles (made by it, or already recorded as its own) and the profiles in use before the first install.
-- check: the recorded check's result ("match" | "mismatch" | "partial" | "unverifiable"), kept so a finished setup whose last
-- check didn't match is never shown as a plain installed one.
local function Manage(j, check)
    local prev = J.ReadManaged()
    if prev and (prev.package ~= j.package or prev.char ~= j.char) then prev = nil end
    local m = { v = J.MANAGED_VERSION, package = j.package, revision = j.revision, variant = j.variant,
        picks = j.picks and LY.Copy(j.picks) or nil, char = j.char, at = time(), targets = {}, home = {}, check = check }
    for id, snap in pairs(j.snapshot) do
        if snap.created or (prev and prev.targets[id] == snap.target) then m.targets[id] = snap.target end
        local home = (prev and prev.home[id]) or snap.active or snap.profile
        if type(home) == "string" then m.home[id] = home end
    end
    J.WriteManaged(m)
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
    -- A step that is still pending, failed or wasn't run means the install didn't finish (a client that stopped between two
    -- steps leaves "applying" with one done): what was done is read, but the record isn't settled, nothing goes in the
    -- baseline and the management record isn't moved to the new revision. It stays resumable (RH-1 B1).
    local incomplete = false
    for _, step in ipairs(j.steps) do
        if not (step.state == "done" or step.state == "skipped" or step.state == "kept") then incomplete = true end
    end
    report.incomplete = incomplete or nil
    if record and (j.state == "applied" or j.state == "verified" or j.state == "mismatch" or j.state == "interrupted") then
        -- "mismatch" is "not verified": verify.state says whether something differs or could not be read
        j.verify = { state = report.state, at = time(), diffs = J.Diffs(reports) }
        -- what was read back by value, and what only for being there (whole EllesmereUI blobs, links, look): never one count
        local checked, presence = 0, 0
        for _, r in pairs(reports) do checked, presence = checked + (r.checked or 0), presence + (r.presence or 0) end
        j.verify.checked, j.verify.presence = checked, presence
        report.checked, report.presence = checked, presence
        if incomplete then
            j.verify.baseline = {}
            j.state = "partial"
        else
            j.verify.baseline = Commit(j, reports)
            Manage(j, report.state)
            j.state = report.state == "match" and "verified" or "mismatch"
        end
        report.committed = j.verify.baseline
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
-- The record as it was before an update, for "Undo this update": everything but its snapshot (an update never replaces
-- it), its own way back and a restore under way.
local function From(previous)
    local out = {}
    for k, v in pairs(previous) do
        if k ~= "snapshot" and k ~= "update" and k ~= "restore" then out[k] = LY.Copy(v) end
    end
    return out
end

local function StepOf(record, id)
    for _, s in ipairs(record and record.steps or {}) do if s.adapter == id then return s end end
end

local function DoApply(pkg, variant, expect, opts)
    if InCombat() then return false, "combat" end
    local plan = DoPlan(pkg, variant, opts)
    if not plan.ok then return false, "blocked", plan end
    if type(expect) ~= "string" or plan.key ~= expect then return false, "stale", plan end
    local resume = plan.update and plan.update.resume
    local allNothing = true
    for _, id in ipairs(plan.order) do if not plan.parts[id].nothing then allNothing = false end end
    if allNothing and not resume and not plan.forced and not (plan.update and plan.update.recordOnly) then return false, "nothing", plan end

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

    -- An update that newly manages an account-wide setting keeps its value from before, once, in the snapshot (an adapter's `Extend`).
    if previous then
        for _, id in ipairs(plan.order) do
            local a = LY.ADAPTERS[id]
            if a.Extend and snapshot[id] then pcall(a.Extend, snapshot[id], plan.parts[id]) end
        end
        local okSnap, why = J.CleanSnapshot(snapshot)
        if not okSnap then return false, "snapshot", why end
    end
    local record = { v = J.VERSION, package = plan.id, revision = plan.revision, variant = variant, char = Me(),
        state = "applying", at = time(), key = Short(plan.key), reload = false, steps = {}, snapshot = snapshot,
        expect = {}, inputs = {}, track = {}, picks = next(plan.picks) ~= nil and plan.picks or nil }
    local geo = plan.geometry
    record.screen = geo and ("%d,%d,%s"):format(math.floor(geo.screen.w + 0.5), math.floor(geo.screen.h + 0.5), tostring(geo.density)) or nil
    for _, id in ipairs(plan.order) do
        local part = plan.parts[id]
        local before = part.resumed and StepOf(previous, id)
        if before then
            -- done in the attempt that stopped: what it expects and what the baseline takes come from that attempt
            record.steps[#record.steps + 1] = { adapter = id, state = "done", code = before.code, reload = before.reload }
            if before.reload then record.reload = true end
            record.expect[id] = previous.expect[id] or {}
            record.inputs[id] = previous.inputs and previous.inputs[id]
            record.track[id] = previous.track and previous.track[id]
        else
            record.steps[#record.steps + 1] = { adapter = id, state = "pending" }
            if part.kept and previous then
                -- kept as it is (the recipient's choice): nothing is written, nothing new is expected or taken by the baseline
                record.expect[id] = previous.expect[id] or {}
            else
                record.expect[id] = LY.ADAPTERS[id].Expect(part.composed, part)
                record.track[id] = part.track
            end
            record.inputs[id] = part.inputs or (previous and previous.inputs and previous.inputs[id])
        end
    end
    -- An update keeps the way back to how things were just before it ("Undo this update"). From a settled install (checked,
    -- or checked with differences) it is taken now; from an update that stopped part way the one taken before it stands,
    -- and only units this attempt writes for the first time are added to it.
    local managed = plan.managed
    if previous or managed then
        local tw, eu = plan.parts.twichui, plan.parts.ellesmereui
        if not previous or UPDATE_STATES[previous.state] then
            local b = J.ReadBaseline()
            local m = J.ReadManaged()
            record.update = { at = time(), from = previous and From(previous) or nil, managed = m and LY.Copy(m) or nil,
                baseline = b and LY.Copy(b) or nil,
                twichui = tw and not tw.resumed and tw.undo or nil, ellesmereui = eu and not eu.resumed and eu.update or nil }
        elseif previous and previous.update then
            record.update = LY.Copy(previous.update)
            local u = record.update
            if tw and tw.undo and u.twichui then
                for unit, kv in pairs(tw.undo.values) do if u.twichui.values[unit] == nil then u.twichui.values[unit] = kv end end
            elseif tw and tw.undo and not tw.resumed then
                u.twichui = tw.undo
            end
        end
        if record.update and not J.CleanUpdate(record.update) then return false, "snapshot", "update" end
        -- the name the install's old EllesmereUI profile is kept under belongs to the install from now on (Restore removes it)
        record.euiBackup = (eu and eu.update and eu.update.backup) or (previous and previous.euiBackup) or nil
    end
    J.Write(record)

    local failed = false
    for i, id in ipairs(plan.order) do
        local step = record.steps[i]
        if not plan.parts[id].resumed then   -- a step the stopped attempt already did is not done twice
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
    end

    if failed then
        local changed = false
        for _, s in ipairs(record.steps) do
            if s.state == "done" or s.state == "partial" or (s.state == "failed" and s.rollback ~= "clean") then changed = true end
        end
        if not changed then
            -- Nothing was changed: the previous record (or none) stands as it was.
            if previous then J.Write(previous)
            elseif plan.forced and plan.forced.journal then J.Write(plan.forced.journal)   -- the record set aside stands as it was
            else J.Clear() end
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
local RESTORABLE = LY.Set({ "applied", "verified", "mismatch", "partial", "interrupted", "restore-partial", "undo-partial" })

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
            local part = LY.ADAPTERS[id].PlanRestore(snap, j)
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
            local ok, r = pcall(LY.ADAPTERS[id].VerifyRestore, snap, Units(j, id), j)
            if not ok then R.Fault("layouts verify restore " .. id, r); r = { state = "unverifiable", code = "error", diffs = {} } end
            reports[id] = r
        end
    end
    local report = { state = Combine(reports), adapters = reports }
    if record then
        if report.state == "match" then
            J.Forget()   -- restored: nothing is installed or managed any more
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
        local ok, res = pcall(LY.ADAPTERS[id].Restore, j.snapshot[id], j)
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
    elseif j.state == "undoing" then
        local report = LY.VerifyUndo(true)
        said = report and (report.undone and "undone" or "undo-partial") or nil
    end
    if said and LY.Tell then LY.Tell(said) end
    return said
end

-- Stops managing the layout: the install record, the management record and the baseline are forgotten; every profile and
-- value stays exactly as it is. (For a record that can't be used, or a recipient who no longer wants updates compared.)
-- A readable record of another character's install is theirs to end (TwichUIDB is account-wide; the profiles it names are
-- that character's): refused. An unreadable one can be forgotten from any character. Returns true | false, code.
function LY.Detach()
    if not J.Exists() and not J.ReadManaged() and not J.ReadBaseline() then return false, "none" end
    local j, m, b = J.Read(), J.ReadManaged(), J.ReadBaseline()
    local me = Me()
    if (j and j.char ~= me) or (m and m.char ~= me) or (b and b.char ~= me) then return false, "journal-other-character" end
    J.Forget()
    return true
end

-- Finishes the setup (the wizard's "Keep this setup"): the rollback journal ends (Restore and Undo this update are no longer
-- offered, and the copy an update kept is removed), while management goes on: the management record, the install's own
-- profiles and the baseline stay, so a later update still knows the package, the choices and the recipient's changes.
-- Refused in combat and before the install was checked. Returns true | false, code.
function LY.Finish()
    if InCombat() then return false, "combat" end
    local j = J.Read()
    if not j then return false, "none" end
    if j.char ~= Me() then return false, "journal-other-character" end
    if not UPDATE_STATES[j.state] then return false, "not-settled" end
    if not J.ReadManaged() then return false, "not-managed" end
    if j.euiBackup then
        local ok, code = LY.ADAPTERS.ellesmereui.DropBackup(j.euiBackup, j.snapshot.ellesmereui)
        if not ok then return false, code end
    end
    J.Clear()
    return true
end

---------------------------------------------------------------------------
-- Undo this update (updates.md): back to how things were just before the last update, which is not the same as Restore
-- (back to before the first install). TwichUI: the values the update replaced in the install's profile go back, and the
-- profile in use before it is in use again. EllesmereUI: the install's old profile, kept under another name, gets its name
-- back and the one the update made goes; a reload finishes it. Once it checks out, the record and the baseline are the
-- ones from before the update. One level: what came before that is not kept.
-- plan = { ok, blocked, order, parts = { [adapter] = { actions, reload } }, reload, key }
---------------------------------------------------------------------------
local UNDOABLE = LY.Set({ "applied", "verified", "mismatch", "partial", "interrupted", "undo-partial" })

function LY.PlanUndo()
    local plan = { blocked = {}, parts = {}, order = {}, reload = false }
    local j, why = J.Read()
    if not j then plan.blocked[1] = { code = why and ("journal-" .. why) or "none" } return plan end
    plan.record = j
    if not j.update then plan.blocked[1] = { code = "no-update" } return plan end
    if not UNDOABLE[j.state] then plan.blocked[1] = { code = j.state == "undoing" and "undo-pending" or "not-restorable" } return plan end
    if j.char ~= Me() then plan.blocked[1] = { code = "journal-other-character" } return plan end
    local keys = {}
    for _, id in ipairs(RestoreOrder(j)) do
        local u = j.update[id]
        local a = LY.ADAPTERS[id]
        if u and a.PlanUndo then
            local part = a.PlanUndo(u, j.snapshot[id])
            plan.parts[id] = part
            plan.order[#plan.order + 1] = id
            if part.blocked then plan.blocked[#plan.blocked + 1] = { adapter = id, code = part.blocked } end
            if part.reload then plan.reload = true end
            keys[id] = part.key or ""
        end
    end
    if #plan.order == 0 and #plan.blocked == 0 then plan.blocked[1] = { code = "no-update" } end
    plan.key = LY.Canon({ j.package, j.key, "undo", keys })
    plan.ok = #plan.blocked == 0
    return plan
end

local function DoVerifyUndo(record)
    local j, why = J.Read()
    if not j then return nil, why or "none" end
    if not j.update then return nil, "no-update" end
    local reports = {}
    for _, id in ipairs(RestoreOrder(j)) do
        local u, a = j.update[id], LY.ADAPTERS[id]
        if u and a.VerifyUndo then
            local ok, r = pcall(a.VerifyUndo, u, j.snapshot[id])
            if not ok then R.Fault("layouts verify undo " .. id, r); r = { state = "unverifiable", code = "error", diffs = {} } end
            reports[id] = r
        end
    end
    local report = { state = Combine(reports), adapters = reports }
    if record then
        if report.state == "match" then
            -- the record and the baseline from before the update stand again (without a way back of their own)
            local back = j.update.from
            if back then
                back.snapshot = j.snapshot
                back.update, back.restore, back.euiBackup = nil, nil, nil
                J.Write(back)
            else
                -- the update came after the setup was finished: back to managing without an install record
                J.Clear()
            end
            J.WriteManaged(j.update.managed)
            J.WriteBaseline(j.update.baseline)
            report.undone = true
        else
            j.state = "undo-partial"
            j.verify = { state = report.state, at = time(), diffs = J.Diffs(reports) }
            J.Write(j)
        end
    end
    return report
end

function LY.VerifyUndo(record) return Perf.Call("layouts.verify", DoVerifyUndo, record) end

-- Returns true, result | false, code, plan. result = { state = "undoing" | "undone" | "undo-partial", steps, verify }
local function DoUndo(expect)
    if InCombat() then return false, "combat" end
    local plan = LY.PlanUndo()
    if not plan.ok then return false, "blocked", plan end
    if type(expect) ~= "string" or plan.key ~= expect then return false, "stale", plan end
    local j = plan.record
    j.restore = { at = time(), steps = {} }
    for _, id in ipairs(plan.order) do j.restore.steps[#j.restore.steps + 1] = { adapter = id, state = "pending" } end
    j.state = "undo-partial"   -- what a stop part way through would leave
    J.Write(j)
    local reload, bad = false, false
    for i, id in ipairs(plan.order) do
        local step = j.restore.steps[i]
        local ok, res = pcall(LY.ADAPTERS[id].Undo, j.update[id], j.snapshot[id])
        if not ok then R.Fault("layouts undo " .. id, res); res = { state = "failed", code = "error" } end
        step.state, step.code = res.state, res.code
        if res.reload then step.reload, reload = true, true end
        if res.state ~= "done" then
            bad = true
            for k = i + 1, #j.restore.steps do j.restore.steps[k].state = "not-run" end
            break
        end
    end
    if bad then
        j.state = "undo-partial"
        j.reload = reload
        J.Write(j)
        return true, { state = "undo-partial", steps = j.restore.steps }
    end
    if reload then
        j.state, j.reload = "undoing", true
        J.Write(j)
        return true, { state = "undoing", steps = j.restore.steps }
    end
    local steps = j.restore.steps
    local report = DoVerifyUndo(true)
    return true, { state = report.undone and "undone" or "undo-partial", steps = steps, verify = report }
end

function LY.Undo(expect) return Perf.Call("layouts.restore", DoUndo, expect) end

-- Keeps the update for good: the copy of the install's EllesmereUI profile from before it is removed, and "Undo this
-- update" is no longer offered. Restore (back to before the first install) is unchanged. Refused in combat.
-- Returns true | false, code.
function LY.ForgetUpdate()
    if InCombat() then return false, "combat" end
    local j = J.Read()
    if not j or not j.update then return false, "no-update" end
    if j.char ~= Me() then return false, "journal-other-character" end
    if not (UPDATE_STATES[j.state]) then return false, "not-settled" end
    local name = j.euiBackup
    if name then
        local EA = LY.ADAPTERS.ellesmereui
        local ok, code = EA.DropBackup(name, j.snapshot.ellesmereui)
        if not ok then return false, code end
    end
    j.update, j.euiBackup = nil, nil
    J.Write(j)
    return true
end
