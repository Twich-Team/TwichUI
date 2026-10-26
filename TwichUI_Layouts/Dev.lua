-- TwichUI Layouts: /tui layout, the developer test of the install pipeline (not the wizard)
--   /tui layout                  what is installed now, and these commands
--   /tui layout validate         checks the test package
--   /tui layout plan             shows what an install would change (nothing changes)
--   /tui layout apply            shows it again; /tui layout apply confirm makes exactly the changes last shown
--   /tui layout verify           reads every managed value back now
--   /tui layout restore          shows what Restore would do; /tui layout restore confirm does it
--   /tui layout status           the install record: state, steps, the last check
--   /tui layout detach confirm   forgets the record and changes nothing else (for a record that can't be used)
-- Output stays in your own chat frame. Nothing reloads by itself: when a reload is needed, it says so.

local R = TwichUI
local LY = R.Layouts
local J = LY.Journal

local function Say(fmt, ...) R.Print("layout: " .. fmt, ...) end
local function Line(fmt, ...) print(R.GREY .. "  " .. (select("#", ...) > 0 and fmt:format(...) or fmt) .. "|r") end

local EXPLAIN = {
    combat = "not during combat. Try again when combat ends.",
    stale = "what it would do has changed since it was shown. Look again with /tui layout plan.",
    nothing = "everything already matches the package; there is nothing to do.",
    snapshot = "TwichUI couldn't record what it would need to put things back, so nothing was changed.",
    none = "no layout install is recorded.",
    ["journal-damaged"] = "the record of the last layout install can't be read. /tui layout detach confirm forgets it (nothing else changes).",
    ["journal-newer"] = "the record of the last layout install was written by a newer TwichUI. Update TwichUI to use it.",
    ["journal-other-package"] = "another layout package is installed. Restore it first.",
    ["journal-other-character"] = "the last layout install was made on another character. Check or restore it there: TwichUI profiles belong to a character.",
    ["restore-pending"] = "a restore is waiting for a reload. Type /reload first.",
    ["not-restorable"] = "the last install didn't change anything that Restore could put back.",
    ["target-taken"] = "a profile with the package's name already exists, and this install didn't make it. Rename or delete it first.",
    ["previous-gone"] = "the profile you used before the install doesn't exist any more, so there is nothing to go back to.",
    ["other-character"] = "this was installed on another character. TwichUI profiles belong to a character.",
    ["schema-changed"] = "this TwichUI no longer has a setting the package names.",
    ["eui-missing"] = "EllesmereUI isn't installed or isn't turned on.",
    ["eui-no-api"] = "this EllesmereUI doesn't offer the functions an install needs. Update EllesmereUI.",
    ["eui-not-forever"] = "this EllesmereUI isn't the WoW: Forever build.",
    ["eui-too-old"] = "this EllesmereUI is older than the package needs. Update EllesmereUI.",
    ["eui-first-run"] = "EllesmereUI's own first-run setup is still waiting for an answer. Finish or close it, reload, then try again.",
    ["eui-no-active"] = "EllesmereUI didn't say which profile is in use.",
    ["eui-export"] = "EllesmereUI couldn't export your profile.",
    ["eui-decode"] = "EllesmereUI couldn't read the package's profile.",
    ["eui-module-missing"] = "a module the package replaces isn't in its export.",
    ["eui-module-absent"] = "a setting the package changes is in an EllesmereUI module your profile doesn't have.",
    ["eui-shape"] = "a setting the package changes isn't where this EllesmereUI keeps it.",
    ["eui-no-modules"] = "the package's profile has no EllesmereUI modules in it.",
    ["no-base"] = "the package has no EllesmereUI base profile.",
    ["dev-source-not-allowed"] = "only a developer package may build on your own profile.",
    ["too-large"] = "the package's profile is too large.",
    ["eui-switch"] = "EllesmereUI didn't switch profile.",
    ["eui-encode"] = "EllesmereUI couldn't write the profile out for importing.",
    ["eui-import"] = "EllesmereUI refused the import.",
    ["others-changed"] = "another EllesmereUI profile or a spec assignment changed during it. Check EllesmereUI > Profiles.",
    ["spec-locked"] = "this spec has its own EllesmereUI profile, so the new one is stored but not in use.",
    matches = "already as planned.",
    write = "writing a value failed (the error is in /tui diagnostics).",
    ["refresh-failed"] = "the values were written, but a feature didn't take them up (the error is in /tui diagnostics).",
    error = "an error stopped it (the error is in /tui diagnostics).",
    ["target-kept"] = "the install's profile couldn't be removed.",
}

local function Explain(code)
    if code == nil then return "" end
    if EXPLAIN[code] then return EXPLAIN[code] end
    local rest = code:match("^profiles%-(.+)$") or code:match("^profile%-(.+)$") or code:match("^target%-kept%-(.+)$")
    if rest and R.Profiles then return R.Profiles.Explain(rest) end
    return code
end
LY.Explain = Explain

local LABEL = { twichui = "TwichUI", ellesmereui = "EllesmereUI" }
local STEP = { pending = "not finished", done = "done", skipped = "already as planned", failed = "failed",
    partial = "partly done", ["not-run"] = "not run" }

local function Adapter(id) return LY.ADAPTERS[id] end

---------------------------------------------------------------------------
-- Showing a plan
---------------------------------------------------------------------------
local function ShowProblems(problems)
    Say("the test package is not valid (%d problem%s); nothing can be installed from it:", problems.n, problems.n == 1 and "" or "s")
    for _, p in ipairs(problems) do Line("%s at %s", p.code, tostring(p.where)) end
    if problems.n > #problems then Line("... and %d more", problems.n - #problems) end
end

local function ShowPart(id, part)
    local a = Adapter(id)
    if part.blocked then Line("%s: can't: %s", LABEL[id], Explain(part.blocked)) return end
    if part.nothing then Line("%s: already as planned; nothing to do.", LABEL[id]) return end
    local same = 0
    if id == "twichui" then
        Line("%s, at once, this character only:", LABEL[id])
        if part.action == "duplicate" then
            Line("  your profile \"%s\" is copied as \"%s\", and this character uses the copy (\"%s\" itself isn't changed)", part.profile, part.target, part.profile)
        elseif part.action == "switch" then
            Line("  this character goes back to the install's profile \"%s\"", part.target)
        else
            Line("  in the install's profile \"%s\"", part.target)
        end
    else
        Line("%s, after a reload, for every character on this account (EllesmereUI's profile choice is account-wide):", LABEL[id])
        local row = part.rows[1]
        if row.made then Line("  a new profile \"%s\" is made from \"%s\" and becomes the one in use (was \"%s\")", part.target, part.home, part.active)
        elseif row.reimport then Line("  the profile \"%s\" is made again from the package", part.target)
        elseif row.change then Line("  the profile \"%s\" is made again and put in use (was \"%s\")", part.target, part.active) end
        Line("  your UI scale, window skins, spec assignments, Cooldown Manager spells, overrides and other profiles are not touched")
        if part.otherClient then Line("  this EllesmereUI isn't the WoW: Forever build: allowed for this developer test package only, and nothing it shows proves how Forever behaves") end
        if part.untested then Line("  tested with EllesmereUI %s; you have %s", tostring(part.tested), tostring(part.version)) end
    end
    for i, row in ipairs(part.rows) do
        if i > 1 then
            if row.change then
                Line("  %s: %s -> %s%s", row.label, a.Show(row.old), a.Show(row.new), row.reload and " (needs a reload)" or "")
            else
                same = same + 1
            end
        end
    end
    if same > 0 then Line("  %d more already as planned", same) end
end

local function ShowPlan(plan, confirmHint)
    if plan.problems then ShowProblems(plan.problems) return end
    Say("test package \"%s\" (revision %d), variant \"%s\": %d change%s%s.", plan.id, plan.revision, plan.variant, plan.changes,
        plan.changes == 1 and "" or "s", plan.reload and ", finished by a reload you make" or "")
    if plan.mode == "again" then Line("Installed before: Restore still goes back to how things were before the first install.") end
    for _, b in ipairs(plan.blocked) do
        if not b.adapter then Line("Can't install: %s", Explain(b.code)) end
    end
    for _, id in ipairs(plan.order) do ShowPart(id, plan.parts[id]) end
    if plan.ok and confirmHint then
        Line("Type /tui layout apply confirm to make exactly these changes. /tui layout restore takes them back.")
    elseif not plan.ok then
        Line("Nothing can be installed until that is sorted out.")
    end
end

local function ShowSteps(steps)
    for _, s in ipairs(steps or {}) do
        local extra = ""
        if s.state == "failed" and s.rollback then
            extra = s.rollback == "clean" and " (what it changed was put back)" or " (not everything it changed could be put back)"
        end
        Line("%s: %s%s%s", LABEL[s.adapter] or s.adapter, STEP[s.state] or s.state, s.code and (": " .. Explain(s.code)) or "", extra)
    end
end

local function ShowDiffs(diffs)
    for _, d in ipairs(diffs or {}) do
        local a = Adapter(d.adapter)
        Line("%s: %s (%s)", LABEL[d.adapter] or d.adapter, a and a.Label(d.unit) or d.unit, d.code)
    end
end

local function ReportDiffs(report)
    local out = {}
    for _, id in ipairs(LY.SortedKeys(report.adapters)) do
        for _, d in ipairs(report.adapters[id].diffs or {}) do out[#out + 1] = { adapter = id, unit = d.unit, code = d.code } end
    end
    return out
end

---------------------------------------------------------------------------
-- What happened at a load (Engine.lua's Continue)
---------------------------------------------------------------------------
function LY.Tell(said)
    local j = J.Read()
    if said == "verified" then
        Say("the layout install was checked after the reload: every managed value reads back as planned.")
    elseif said == "mismatch" or said == "partial" or said == "unverifiable" then
        Say("the layout install was checked after the reload, and not everything reads back as planned:")
        ShowDiffs(j and j.verify and j.verify.diffs)
        Line("/tui layout restore puts back how things were before it.")
    elseif said == "interrupted" then
        Say("a layout install was interrupted before it finished. /tui layout status shows what it did; /tui layout restore puts things back.")
    elseif said == "restored" then
        Say("restored: everything the layout install changed is back as it was.")
    elseif said == "restore-partial" then
        Say("the restore was checked after the reload, and not everything is back as it was:")
        ShowDiffs(j and j.verify and j.verify.diffs)
    end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local shown = {}   -- the keys of the plans last shown this session: { apply = key, restore = key }

local function Status()
    local j, why = J.Read()
    if not j then
        Say("%s", why and Explain("journal-" .. why) or "no layout install is recorded.")
        return
    end
    Say("\"%s\" (revision %d), variant \"%s\", on %s: %s.", j.package, j.revision, j.variant, j.char, j.state)
    ShowSteps(j.steps)
    if j.verify then Line("Last check: %s, %s", j.verify.state, date("%b %d %H:%M", j.verify.at or 0)) ShowDiffs(j.verify.diffs) end
    if j.restore then Line("Restore:") ShowSteps(j.restore.steps) end
    if j.state == "applied" or j.state == "restoring" then Line("Waiting for a reload: type /reload when you are ready.") end
end

local function Help()
    Say("the developer test of layout installs (not the wizard). Commands:")
    Line("/tui layout validate | plan | apply [confirm] | verify | restore [confirm] | status | detach confirm")
end

local function Apply(confirm)
    local pkg, variant = LY.TEST_PACKAGE, LY.TEST_VARIANT
    if not confirm then
        local plan = LY.Plan(pkg, variant)
        ShowPlan(plan, true)
        shown.apply = plan.ok and plan.key or nil
        return
    end
    if not shown.apply then Say("look at what it would do first: /tui layout plan, then /tui layout apply confirm.") return end
    local ok, result, plan = LY.Apply(pkg, variant, shown.apply)
    shown.apply = nil
    if not ok then
        Say("nothing was changed: %s", Explain(result))
        if result == "blocked" and plan then ShowPlan(plan) end
        return
    end
    local state = result.state
    if state == "applied" then
        Say("applied; it isn't finished or checked until you reload. Type /reload when you are ready: after it, TwichUI reads every managed value back and says whether it took.")
        ShowSteps(result.steps)
    elseif state == "verified" then
        Say("applied and checked: every managed value reads back as planned.")
        ShowSteps(result.steps)
    elseif state == "mismatch" then
        Say("applied, but not everything reads back as planned:")
        ShowSteps(result.steps)
        ShowDiffs(result.record and result.record.verify and result.record.verify.diffs)
    elseif state == "partial" then
        Say("only partly applied. /tui layout restore puts back what was changed:")
        ShowSteps(result.steps)
        if result.record and result.record.reload then Line("A part that was done waits for a reload (/reload).") end
    else
        Say("not applied, and nothing was changed:")
        ShowSteps(result.steps)
    end
end

local function ShowRestorePlan(plan)
    local j = plan.record
    if not j then Say("%s", Explain(plan.blocked[1] and plan.blocked[1].code or "none")) return end
    Say("Restore \"%s\" (variant \"%s\"):", j.package, j.variant)
    for _, b in ipairs(plan.blocked) do
        Line("%sCan't: %s", b.adapter and (LABEL[b.adapter] .. ": ") or "", Explain(b.code))
    end
    for _, id in ipairs(plan.order) do
        local part = plan.parts[id]
        if not part.blocked then
            if #part.actions == 0 then Line("%s: nothing to put back.", LABEL[id]) end
            for _, act in ipairs(part.actions) do
                if act.kind == "switch" then Line("%s: back to your profile \"%s\"", LABEL[id], act.to)
                else Line("%s: the install's profile \"%s\" is removed (changes you made in it since go with it)", LABEL[id], act.name) end
            end
        end
    end
    if plan.reload then Line("EllesmereUI finishes it at a reload you make.") end
end

local function Restore(confirm)
    if not confirm then
        local plan = LY.PlanRestore()
        ShowRestorePlan(plan)
        shown.restore = plan.ok and plan.key or nil
        if plan.ok then Line("Type /tui layout restore confirm to do exactly this.") end
        return
    end
    if not shown.restore then Say("look at what it would do first: /tui layout restore, then /tui layout restore confirm.") return end
    local ok, result, plan = LY.Restore(shown.restore)
    shown.restore = nil
    if not ok then
        Say("nothing was changed: %s", Explain(result))
        if result == "blocked" and plan then ShowRestorePlan(plan) end
        return
    end
    if result.state == "restoring" then
        Say("restored as far as it can be now; EllesmereUI finishes at a reload. Type /reload when you are ready: after it, TwichUI checks that everything is back.")
    elseif result.state == "restored" then
        Say("restored and checked: everything the install changed is back as it was.")
    else
        Say("only partly restored:")
        if result.verify then ShowDiffs(ReportDiffs(result.verify)) end
    end
    ShowSteps(result.steps)
end

local function Verify()
    local j = J.Read()
    if j and (j.state == "restoring" or j.state == "restore-partial") then
        local report = LY.VerifyRestore(false)
        Say("restore check: %s", report and report.state or "nothing to check")
        if report then ShowDiffs(ReportDiffs(report)) end
        return
    end
    local report, why = LY.Verify(false)
    if not report then Say("%s", Explain(why and ("journal-" .. why) or "none")) return end
    if why == nil and j and j.state == "applied" then Line("(read before the reload that finishes it: EllesmereUI's part may still change at that reload)") end
    Say("check: %s", report.state == "match" and "every managed value reads back as planned" or report.state)
    for _, id in ipairs(LY.SortedKeys(report.adapters)) do
        local r = report.adapters[id]
        Line("%s: %s, %d checked%s%s", LABEL[id], r.state, r.checked or 0, (r.unverifiable or 0) > 0 and (", " .. r.unverifiable .. " not readable") or "",
            r.code and (" (" .. Explain(r.code) .. ")") or "")
    end
    ShowDiffs(ReportDiffs(report))
end

function LY.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word, rest = (word or ""):lower(), (rest or ""):lower()
    local confirm = rest == "confirm"
    if word == "" then Status() Help() return end
    if word == "help" then Help() return end
    if word == "status" then Status() return end
    if word == "validate" then
        local ok, problems = LY.Validate(LY.TEST_PACKAGE)
        if ok then Say("the test package is valid (format %d, variants: %s).", LY.TEST_PACKAGE.format, LY.TEST_VARIANT)
        else ShowProblems(problems) end
        return
    end
    if word == "plan" or word == "show" then
        local plan = LY.Plan(LY.TEST_PACKAGE, LY.TEST_VARIANT)
        ShowPlan(plan, true)
        shown.apply = plan.ok and plan.key or nil
        return
    end
    if word == "apply" then Apply(confirm) return end
    if word == "verify" or word == "check" then Verify() return end
    if word == "restore" then Restore(confirm) return end
    if word == "detach" then
        if not confirm then Say("this forgets the install record without changing anything: what was installed stays. Type /tui layout detach confirm.") return end
        Say(LY.Detach() and "the install record is forgotten; nothing else was changed." or "there was no install record.")
        return
    end
    Say("unknown: '%s'.", word)
    Help()
end

LY.ready = true
