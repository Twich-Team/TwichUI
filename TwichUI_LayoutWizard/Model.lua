-- TwichUI Layout Setup: the model (what each step shows, and what its buttons do)
-- No frames here. The window (Window.lua, Pages.lua) draws what this says and calls what it offers, so every rule the
-- wizard follows can be tested without a screen:
--   * Choosing changes nothing in the game. A pick is remembered (State.lua) and re-draws the preview; the full plan
--     (TwichUI_Layouts' LY.Plan, read only) is worked out only when the review is shown, and again when a pick or the
--     screen changed. The preview is the package's resolved screen geometry for the picks: the same resolver the plan uses.
--   * Applying, restoring, forgetting the record and reloading each happen only from a method called by a button the
--     player pressed (after a confirmation that names the exact scope), and each is refused in combat here.
--   * Applying uses exactly the plan whose key was shown (LY.Apply refuses a stale key), restoring exactly the restore
--     plan shown. Nothing reloads by itself: Reload is a button, and it leaves a note so the result can be shown after it.
--
-- Steps: 1 Welcome (what it does, what this client and screen allow), 2 Layout (Classic or Compact Adventure: choosing
-- re-draws the preview at once and changes nothing else), 3 Helpers, 4 Personalize, 5 Review and apply, 6 Result (waiting
-- for the reload, checked after it, or put back).
--
-- The preview (M.Scene) is the engine's resolved geometry for the chosen layout, this screen and the picked size, with the
-- pieces inside it (Scene.lua); the scenario (M.SetScenario) changes what the sample shows and nothing else. The full-size
-- overlay (Overlay.lua) draws the same scene. Neither writes anything: not a profile, not a pick, not the layout choice.

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local S = WZ.State
local Scene = WZ.Scene
local M = {}
WZ.Model = M

M.STEPS = {
    { key = "welcome", label = "Welcome" },
    { key = "layout", label = "Layout" },
    { key = "helpers", label = "Helpers" },
    { key = "personalize", label = "Personalize" },
    { key = "review", label = "Review" },
    { key = "result", label = "Result" },
}
M.WELCOME, M.LAYOUT, M.HELPERS, M.PERSONALIZE, M.REVIEW, M.RESULT = 1, 2, 3, 4, 5, 6

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Me() return R.Profiles and R.Profiles.Character() or nil end
local function Cap(s) return (tostring(s):gsub("^%l", string.upper)) end
local function Explain(code) return Cap(LY.Explain(code)) end
local function Whole(n) return math.floor(n + 0.5) end
local function Plural(n, one, many) return n == 1 and one or many end
M.Explain = Explain

---------------------------------------------------------------------------
-- The layouts on offer: each is a variant of a package that TwichUI_Layouts ships
---------------------------------------------------------------------------
M.TEXT = {
    ["classic-adventure"] = {
        title = "Classic Adventure", short = "Classic",
        blurb = "The unit frames and action bars sit low in the middle, chat at the lower left, the damage meter at the lower right, the minimap and your objectives at the upper right. EllesmereUI's look and TwichUI's own looks are set to match.",
        covers = {
            "EllesmereUI: its modules, their layout links and its look, as a new profile of its own.",
            "TwichUI: its looks, and where its on-screen pieces sit, in a new profile of its own.",
            "Worked out for your screen: each piece keeps its distance from the edge it is nearest to.",
        },
        art = "classic",
    },
    ["compact-adventure"] = {
        title = "Compact Adventure", short = "Compact",
        blurb = "The unit frames and action bars lie in one low, wide strip along the bottom edge and leave the middle of the screen open. Chat, the damage meter (with a bar on top of it), the minimap and your objectives are where Classic puts them.",
        covers = {
            "The same look, the same choices and the same TwichUI settings as Classic Adventure.",
            "Only the unit frames, action bars, raid and party frames and the layout links are its own.",
            "On narrower screens chat rises above the strip instead of squeezing in beside it.",
        },
        art = "compact",
    },
}
M.ORDER = { "classic-adventure", "compact-adventure" }

-- How many EllesmereUI modules a layout shares with the other one and how many are its own: counted from the package,
-- so the card says what the data says (the base layer holds what both layouts hold identically).
local function ModuleCounts(pkg, variant)
    local function Count(layer)
        local f = layer and layer.ellesmereui
        local n = 0
        for _ in pairs(f and f.modules or {}) do n = n + 1 end
        return n
    end
    return Count(pkg.layers.base), Count(pkg.layers.variants[variant])
end

function M.Layouts()
    local pkg = LY.ADVENTURE_PACKAGE
    if not pkg then return {} end
    local out = {}
    for _, id in ipairs(M.ORDER) do
        local t = M.TEXT[id]
        if pkg.layers.variants[id] then
            local shared, own = ModuleCounts(pkg, id)
            out[#out + 1] = { id = id, title = t.title, short = t.short, blurb = t.blurb, covers = t.covers, pkg = pkg, variant = id,
                art = t.art, dev = pkg.dev == true, sharedModules = shared, ownModules = own }
        end
    end
    return out
end

function M.LayoutIds()
    local ids = {}
    for _, l in ipairs(M.Layouts()) do ids[#ids + 1] = l.id end
    return ids
end

---------------------------------------------------------------------------
-- Packages: the one included with TwichUI, and the ones other players sent (stored by TwichUI_Layouts' Store, never applied
-- by receiving). A received package is opened when it is chosen (unpacked a little at a time and checked again), and its
-- layouts are the variants it names; everything after that (the preview, the choices, the review, apply, restore) is the
-- same code the included package goes through.
---------------------------------------------------------------------------
local function QuoteText(s) return "\"" .. tostring(s) .. "\"" end

local function ReceivedLayouts(env)
    local pkg = env.package
    local out = {}
    for _, v in ipairs(env.meta.variants) do
        local shared, own = ModuleCounts(pkg, v.id)
        out[#out + 1] = { id = v.id, title = v.title, short = v.title, pkg = pkg, variant = v.id, dev = false, received = true,
            blurb = ("A layout in the package %s, revision %d."):format(QuoteText(pkg.title or pkg.id), pkg.revision),
            covers = {
                ("EllesmereUI: %d %s shared by every layout in the package, %d its own."):format(shared, shared == 1 and "module" or "modules", own),
                "TwichUI: the looks and on-screen places the package carries, in a new profile of its own.",
                "Every change is listed on the Review step before anything is applied.",
            },
            sharedModules = shared, ownModules = own }
    end
    return out
end

local function SourceKey(e) return ("received:%s:%s:%s"):format(e.hash, tostring(e.sender), tostring(e.at)) end

-- The packages to choose from: { { key, kind = "bundled" | "received", title, revision, sender, by, entry } }
function M.Sources()
    local out = {}
    local pkg = LY.ADVENTURE_PACKAGE
    if pkg then out[1] = { key = "bundled", kind = "bundled", title = pkg.title or pkg.id, revision = pkg.revision } end
    for _, e in ipairs(LY.Store and LY.Store.List("received") or {}) do
        out[#out + 1] = { key = SourceKey(e), kind = "received", title = e.title or e.id, revision = e.revision, sender = e.sender,
            by = e.by, entry = e, id = e.id }
    end
    return out
end

local session   -- nil while the window is closed

function M.Session() return session end
function M.Active() return session ~= nil end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
-- A session starts when the window opens and ends when it closes: the picks are read from what was remembered (checked
-- narrowly), nothing is changed, and the first step is the result when an install is recorded (there is something to see
-- or to put back) and the welcome otherwise.
function M.Begin()
    local layouts = M.Layouts()
    local layout = layouts[1]
    if not layout then session = nil return nil, "no-layout" end
    local stored = S.Load(layout.pkg, M.LayoutIds())
    for _, l in ipairs(layouts) do if l.id == stored.variant then layout = l end end
    session = { layout = layout, layouts = layouts, picks = stored.picks, stored = stored, step = M.WELCOME, reached = M.WELCOME,
        scenario = Scene.SCENARIOS[1].id }
    local resumed = S.TakeResume(layout.pkg, stored.picks, layout.variant)
    session.source = "bundled"
    local j, why = LY.Journal.Read()
    if j and j.package ~= layout.pkg.id then
        -- the install on record is of a package someone sent: open it again, so Review and Switch know it
        for _, src in ipairs(M.Sources()) do
            if src.kind == "received" and src.id == j.package then M.SetSource(src.key, nil, true) break end
        end
    end
    if j or why then
        session.step, session.reached = M.RESULT, M.RESULT
    elseif resumed == "restore" then
        session.restored = true   -- a restore finished at the reload the wizard started: its record is gone
        session.step, session.reached = M.RESULT, M.RESULT
    end
    return session
end

-- Drops everything worked out (the plan holds the payload it would import) and ends the session. Changes nothing.
function M.End()
    session = nil
end

-- The screen or UI scale changed (or the player asks for a fresh look): what was worked out for the old one is dropped.
function M.Invalidate()
    if not session then return end
    session.plan, session.pv, session.check = nil, nil, nil
end

function M.Step() return session and session.step or nil end

-- Goes to a step: forward only as far as has been reached through Next (or any step at or before it), and never past the
-- review without having been through it. Returns the step now shown.
function M.Go(step)
    if not session then return nil end
    step = math.max(1, math.min(#M.STEPS, step))
    if step > session.reached then step = session.reached end
    session.step = step
    session.failed = nil
    if step ~= M.REVIEW then session.plan = nil end   -- the plan holds the payload it would import: kept only while shown
    return step
end

function M.Next()
    if not session then return nil end
    local ok = M.CanContinue()
    if not ok then return session.step end
    if session.step >= M.REVIEW then return session.step end   -- the review ends in Apply, not Next
    session.step = session.step + 1
    session.failed = nil
    if session.step ~= M.REVIEW then session.plan = nil end
    if session.step > session.reached then session.reached = session.step end
    return session.step
end

function M.Back()
    if not session then return nil end
    if session.step > 1 then session.step = session.step - 1 end
    session.failed = nil
    if session.step ~= M.REVIEW then session.plan = nil end
    return session.step
end

function M.Layout() return session and session.layout end

-- The layout on offer (Classic or Compact Adventure) and the choice between them. Choosing remembers the layout and drops
-- what was worked out for the other one; nothing in the game changes (the install is the Review step's, behind its
-- confirmation, and re-uses the install's own profiles: switching layouts is an install again).
function M.LayoutList() return session and session.layouts or M.Layouts() end

function M.SetLayout(id)
    if not session then return false, "closed" end
    for _, l in ipairs(session.layouts) do
        if l.id == id then
            if session.layout.id == id then return true, false end
            session.layout = l
            session.plan, session.pv, session.failed = nil, nil, nil
            S.Save(l.pkg, session.picks, nil, l.variant)
            return true, true
        end
    end
    return false, "unknown-layout"
end

-- The source in use: "bundled", or a received package's key. loading: the key being unpacked, if one is.
function M.Source() return session and session.source or nil end
function M.Loading() return session and session.loading or nil end
function M.SourceError() return session and session.sourceError or nil end

-- What is known of the received package in use: { entry, env, media = { { path, kind, source, status } } } or nil.
function M.Package() return session and session.package or nil end

-- Chooses the package. "bundled" is immediate. A received package is unpacked over a few frames; done(ok, code) is called
-- when it is ready (or could not be used). Nothing in the game changes. keepStep: leave the step as it is (Begin opens the
-- package an install on record came from, and stays on the result). Returns true, changed | false, code.
function M.SetSource(key, done, keepStep)
    if not session then return false, "closed" end
    local s = session
    if s.source == key and not s.loading then return true, false end
    local function Adopt(layouts, picksFor)
        s.layouts = layouts
        local ids = {}
        for _, l in ipairs(layouts) do ids[#ids + 1] = l.id end
        local stored = S.Load(layouts[1].pkg, ids)
        s.layout = layouts[1]
        for _, l in ipairs(layouts) do if l.id == stored.variant then s.layout = l end end
        s.picks = stored.picks
        s.plan, s.pv, s.scene, s.failed, s.check, s.compat = nil, nil, nil, nil, nil, nil
        if not keepStep then s.step, s.reached = math.min(s.step, M.LAYOUT), math.min(s.reached, M.LAYOUT) end
    end
    if key == "bundled" then
        s.loading, s.sourceError = nil, nil
        s.source, s.package = "bundled", nil
        Adopt(M.Layouts())
        return true, true
    end
    local src
    for _, c in ipairs(M.Sources()) do if c.key == key and c.kind == "received" then src = c end end
    if not src then return false, "unknown-source" end
    s.loading, s.sourceError = key, nil
    LY.Store.Open(src.entry, function(env, info)
        if session ~= s or s.loading ~= key then return end   -- closed, or another was asked for meanwhile
        s.loading = nil
        local ok, err = pcall(function()
            s.package = { entry = src.entry, env = env, media = LY.Pub.Resolve(env.meta.media) }
            Adopt(ReceivedLayouts(env))
            s.source = key
        end)
        if not ok then
            -- half-adopted state is put back, and the error is the game's to show
            s.package, s.source = nil, "bundled"
            s.sourceError = "unreadable"
            R.Fault("layout setup", err)
            if done then done(false, "unreadable") end
            return
        end
        if done then done(true) end
    end, function(code)
        if session ~= s or s.loading ~= key then return end
        s.loading, s.sourceError = nil, code
        if done then done(false, code) end
    end)
    return true, true
end

-- Removes the stored copy of the received package in use (the player confirmed). An install already made from it, its record
-- and Restore are not touched. Back to the package included with TwichUI.
function M.RemovePackage()
    if not session or not session.package then return false end
    local removed = LY.Store.Remove("received", session.package.entry)
    M.SetSource("bundled")
    return removed
end

function M.OtherLayout()
    if not session then return nil end
    for _, l in ipairs(session.layouts) do if l.id ~= session.layout.id then return l end end
end

-- The scenario the preview shows (how much sample content, which pieces are visible). Not remembered, not a choice.
function M.Scenario() return session and session.scenario or Scene.SCENARIOS[1].id end

function M.SetScenario(id)
    if not session then return false, "closed" end
    local found
    for _, sc in ipairs(Scene.SCENARIOS) do if sc.id == id then found = true end end
    if not found then return false, "unknown-scenario" end
    if session.scenario == id then return true, false end
    session.scenario = id
    return true, true
end

---------------------------------------------------------------------------
-- Choices
---------------------------------------------------------------------------
local function ChoiceOf(pkg, id)
    for _, ch in ipairs(pkg.choices or {}) do if ch.id == id then return ch end end
end
local function OptionOf(ch, id)
    for _, o in ipairs(ch.options or {}) do if o.id == id then return o end end
end

function M.Choice(id) return session and ChoiceOf(session.layout.pkg, id) end
function M.Picks()
    local out = {}
    if session then for k, v in pairs(session.picks) do out[k] = v end end
    return out
end
function M.Pick(id) return session and session.picks[id] end
function M.PickedOption(id)
    local ch = session and ChoiceOf(session.layout.pkg, id)
    return ch and OptionOf(ch, session.picks[id]) or nil, ch
end

-- Picks an option. Remembered, the preview and the plan are dropped; nothing in the game changes.
-- Returns true, changed | false, code.
function M.SetPick(choiceId, optionId)
    if not session then return false, "closed" end
    local ch = ChoiceOf(session.layout.pkg, choiceId)
    if not ch then return false, "unknown-choice" end
    if not OptionOf(ch, optionId) then return false, "unknown-option" end
    if session.picks[choiceId] == optionId then return true, false end
    session.picks[choiceId] = optionId
    session.plan, session.pv, session.failed = nil, nil, nil
    S.Save(session.layout.pkg, session.picks, nil, session.layout.variant)
    return true, true
end

-- Whether the picks the player made are anything but the defaults (for "Start over").
function M.IsDefault()
    if not session then return true end
    for id, d in pairs(S.Defaults(session.layout.pkg)) do if session.picks[id] ~= d then return false end end
    return true
end

function M.ResetPicks()
    if not session then return end
    session.picks = S.Defaults(session.layout.pkg)
    session.plan, session.pv = nil, nil
    S.Save(session.layout.pkg, session.picks, nil, session.layout.variant)
end

-- The density the picks give (the size choice), or "standard".
function M.Density()
    local o = session and M.PickedOption("size")
    return o and o.density or "standard"
end

---------------------------------------------------------------------------
-- Compatibility (step 1): what this client, this screen and the game's state allow. Read only.
-- Each item: { id, label, state = "ok" | "warn" | "block" | "info", detail, go = step? }
---------------------------------------------------------------------------
local EUI_WHY = {
    missing = "eui-missing", ["no-api"] = "eui-no-api", ["not-forever"] = "eui-not-forever", ["too-old"] = "eui-too-old",
}

function M.Screen() return LY.Geometry.Live() end

function M.ScreenText(screen)
    screen = screen or M.Screen()
    if not screen then return nil end
    local s = ("%d × %d units"):format(Whole(screen.w), Whole(screen.h))
    if screen.physW and screen.physH then
        s = s .. (" (%d × %d pixels at UI scale %.2f)"):format(screen.physW, screen.physH, screen.scale or 0)
    end
    return s
end

local DIAG = { overlap = "overlaps", offscreen = "doesn't fit on the screen", clamped = "was moved back onto the screen",
    minimum = "is at its smallest readable size" }
M.DIAG = DIAG

-- Plain sentences for a geometry's problems (overlaps and off-screen pieces), at most `max`.
function M.FitLines(geo, max)
    local out = {}
    for _, d in ipairs(geo and geo.diagnostics or {}) do
        if d.code == "overlap" or d.code == "offscreen" then
            local a = geo.components[d.id]
            local b = d.other and geo.components[d.other]
            out[#out + 1] = ("%s %s%s."):format(a and a.label or d.id, DIAG[d.code] or d.code,
                b and (" " .. (b.label or d.other)) or "")
            if #out >= (max or 4) then break end
        end
    end
    return out
end

function M.Compat()
    local items = {}
    if not session then return items, false end
    local pkg = session.layout.pkg
    local function Add(id, label, state, detail, extra)
        local item = { id = id, label = label, state = state, detail = detail }
        for k, v in pairs(extra or {}) do item[k] = v end
        items[#items + 1] = item
    end

    -- EllesmereUI: the layout is made for it
    local EA = LY.ADAPTERS.ellesmereui
    local det = EA.Detect(pkg.requires and pkg.requires.ellesmereui, pkg.dev)
    if not det.usable then
        Add("ellesmereui", "EllesmereUI", "block", Explain(EUI_WHY[det.why] or "eui-missing")
            .. (det.why == "missing" and " Install it, turn it on, and open this again." or ""))
    else
        local req = pkg.requires and pkg.requires.ellesmereui
        local detail = "Version " .. tostring(det.version or "?") .. "."
        local state = "ok"
        if det.untested and type(req) == "table" and req.tested then
            state, detail = "warn", ("Version %s. This layout was tested with %s."):format(tostring(det.version or "?"), tostring(req.tested))
        end
        if det.otherClient then
            state, detail = "warn", "This EllesmereUI isn't the WoW: Forever build. A preview layout may be tried here; it says nothing about how Forever behaves."
        end
        Add("ellesmereui", "EllesmereUI", state, detail)
        local E = rawget(_G, "EllesmereUI")
        if type(E) == "table" and E._firstInstallPending == true then
            Add("eui-first-run", "EllesmereUI's own setup", "block", Explain("eui-first-run"))
        end
    end

    -- a package someone sent: who from, what it is, and whether this computer has what it points at
    local pk = session.package
    if pk then
        local m = pk.env.meta
        local from = pk.entry.sender and (pk.entry.sender .. " sent it to you") or "It was sent to you"
        local made = m.publisher and ("; its author labelled it " .. QuoteText(m.publisher) .. ", in their own words") or ""
        Add("package", "This package", "info", ("%s, revision %d. %s%s. TwichUI checked that it is well formed; nobody has tested it for you."):format(
            QuoteText(pk.env.package.title or m.id), m.version, from, made))
        local mine = LY.ADVENTURE_PACKAGE
        if mine and mine.id == m.id then
            if m.version < mine.revision then
                Add("package-old", "Older than yours", "warn", ("The layout included with TwichUI is revision %d; this is revision %d."):format(mine.revision, m.version))
            elseif m.version > mine.revision then
                Add("package-new", "Newer than yours", "info", ("It replaces the layout included with TwichUI (revision %d)."):format(mine.revision))
            end
        end
        if m.client == "other" then
            Add("package-client", "Made elsewhere", "warn", "Its author made it on another game client, not WoW: Forever. TwichUI can't tell how it behaves here.")
        end
        local missing, unverified = {}, 0
        for _, r in ipairs(pk.media or {}) do
            if r.status == "missing" then missing[#missing + 1] = r.path:match("([^\\]+)$") or r.path
            elseif r.status == "unverified" then unverified = unverified + 1 end
        end
        if #missing > 0 then
            table.sort(missing)
            Add("package-media", "Files it needs", "block", ("It uses %d %s this computer doesn't have: %s. Update TwichUI or EllesmereUI, or ask its author for a build that doesn't."):format(
                #missing, #missing == 1 and "file" or "files", table.concat(missing, ", ", 1, math.min(#missing, 3)) .. (#missing > 3 and ", ..." or "")))
        elseif #(pk.media or {}) > 0 then
            Add("package-media", "Files it needs", "ok", ("%d %s it points at %s TwichUI's or the suite's own%s."):format(
                #pk.media, #pk.media == 1 and "file" or "files", #pk.media == 1 and "is" or "are",
                unverified > 0 and (" (" .. unverified .. " can't be looked up without drawing or playing them, so are taken on trust)") or ""))
        end
        if m.notes then Add("package-notes", "Release notes", "info", m.notes) end
    end
    if session.sourceError then
        Add("package-error", "Chosen package", "block", "It couldn't be opened again (" .. tostring(session.sourceError) .. "). It is stored but unreadable; remove it and ask for another copy.")
    end

    -- TwichUI's own profiles
    local td = LY.ADAPTERS.twichui.Detect()
    if td.usable then Add("twichui", "TwichUI profiles", "ok", "This character's profile is copied for the layout; yours is not changed.")
    else Add("twichui", "TwichUI profiles", "block", R.Profiles and R.Profiles.Explain(td.why) or "TwichUI's profiles aren't available.") end

    -- the screen
    local screen = M.Screen()
    if not screen then
        Add("screen", "Your screen", "block", Explain("no-screen"))
    else
        local text = M.ScreenText(screen)
        local failed, notFit, fitting = false, {}, {}
        for _, l in ipairs(session.layouts) do
            local geo = LY.Geometry.Resolve(l.pkg.geometry, screen, { density = "standard", variant = l.variant })
            if not geo then failed = true
            elseif geo.fits then fitting[#fitting + 1] = l.title
            else notFit[#notFit + 1] = l.title .. ": " .. table.concat(M.FitLines(geo, 2), " ") end
        end
        if failed then Add("screen", "Your screen", "warn", text .. ". TwichUI couldn't work out where things would go.")
        elseif #notFit == 0 then Add("screen", "Your screen", "ok", text .. ". Everything fits, in either layout.")
        else
            Add("screen", "Your screen", "warn", text .. ". " .. (#fitting > 0 and (table.concat(fitting, " and ") .. " fits. ") or "")
                .. "Not everything fits: " .. table.concat(notFit, " ")
                .. " A smaller UI scale gives more room; the layout never shrinks anything below readable.")
        end
    end

    -- a preview build
    if pkg.dev then
        Add("preview", "This layout", "warn", "A preview build: it hasn't been checked on WoW: Forever yet. Restore puts your previous setup back.")
    end

    -- combat
    if InCombat() then Add("combat", "Combat", "warn", "You are in combat. You can look around; applying waits until it ends.")
    else Add("combat", "Combat", "info", "Applying and restoring are refused during combat. Nothing here runs by itself.") end

    -- an install already recorded
    local j, why = LY.Journal.Read()
    if why == "damaged" then
        Add("record", "A previous install", "warn", Explain("journal-damaged"), { go = M.RESULT })
    elseif why == "newer" then
        Add("record", "A previous install", "block", Explain("journal-newer"))
    elseif j then
        if j.char ~= Me() then Add("record", "A previous install", "block", Explain("journal-other-character"))
        else Add("record", "A previous install", "info", "An install made earlier is recorded (" .. j.state .. "). Its result, and Restore, are on the last step.", { go = M.RESULT }) end
    end

    local ok = true
    for _, it in ipairs(items) do if it.state == "block" then ok = false end end
    session.compat = ok
    return items, ok
end

function M.CanContinue()
    if not session then return false end
    if session.loading then return false end   -- a package is still being opened
    if session.step == M.WELCOME then
        local _, ok = M.Compat()
        return ok
    end
    return session.step < M.REVIEW
end

---------------------------------------------------------------------------
-- The preview (steps 2 to 5): the package's resolved geometry for the chosen layout, this screen and the picked size
---------------------------------------------------------------------------
-- Returns geometry, screen | nil, why. Cached by layout, screen and density; dropped by Invalidate, a pick and a layout choice.
function M.Preview()
    if not session then return nil, "closed" end
    local screen = M.Screen()
    if not screen then return nil, "no-screen" end
    local density = M.Density()
    local variant = session.layout.variant
    local key = ("%s,%.2f,%.2f,%s"):format(variant, screen.w, screen.h, density)
    if session.pv and session.pv.key == key then return session.pv.geo, screen end
    local ok, geo, why = pcall(LY.Geometry.Resolve, session.layout.pkg.geometry, screen, { density = density, variant = variant })
    if not ok or not geo then return nil, tostring(ok and why or geo) end
    session.pv = { key = key, geo = geo }
    session.scene = nil
    return geo, screen
end

-- The default tooltip place, read from the game the way Blizzard's own code reads it (GameTooltip_SetDefaultAnchor):
-- the first point of the default container, when it is placed against the screen. Read only; falls back to Forever's own
-- default. Returns { point, x, y }.
function M.TooltipAnchor()
    local C = rawget(_G, "GameTooltipDefaultContainer")
    if type(C) == "table" and C.GetPoint then
        local ok, point, rel, _, x, y = pcall(C.GetPoint, C, 1)
        if ok and type(point) == "string" and (rel == nil or rel == rawget(_G, "UIParent")) and type(x) == "number" and type(y) == "number"
            and LY.Geometry.POINTS[point] then
            return { point = point, x = x, y = y }
        end
    end
    return Scene.TOOLTIP_FALLBACK
end

-- The scene for the chosen layout, screen, size and scenario (Scene.lua). Cached until any of those changes.
function M.Scene()
    if not session then return nil, "closed" end
    local geo, why = M.Preview()
    if not geo then return nil, why end
    local tip = session.scenario == "tooltip" and M.TooltipAnchor() or nil
    local key = session.scenario .. (tip and ("|%s,%s,%s"):format(tip.point, tip.x, tip.y) or "")
    if session.scene and session.scene.key == key and session.scene.geo == geo then return session.scene.scene end
    local scene = Scene.Build(session.layout, geo, { scenario = session.scenario, tooltip = tip })
    session.scene = { key = key, geo = geo, scene = scene }
    return scene
end

-- Whether the full-size preview can open now. nil when it can; otherwise the reason, in a sentence. It needs the player out
-- of combat (the overlay is drawn over the whole screen, and what is behind it is the live interface, which it does not
-- hide or move) and a screen it can read.
function M.OverlayBlock()
    if not session then return "The setup isn't open." end
    if InCombat() then return "The full-size preview needs you out of combat." end
    if not M.Screen() then return Explain("no-screen") end
    return nil
end

-- The accent colour the picks give, as { r, g, b } (nil: the player's class colour, which only the game can say).
function M.Accent()
    local o = session and M.PickedOption("accent")
    return o and o.swatch or nil, o
end

---------------------------------------------------------------------------
-- The plan (step 5): LY.Plan for the picks and this screen. Read only; cached until a pick or the screen changes.
---------------------------------------------------------------------------
local function PlanSignature()
    local screen = M.Screen()
    local ids = { session.layout.variant }
    for _, ch in ipairs(session.layout.pkg.choices or {}) do ids[#ids + 1] = ch.id .. "=" .. tostring(session.picks[ch.id]) end
    return table.concat(ids, ",") .. "|" .. (screen and ("%.2f,%.2f"):format(screen.w, screen.h) or "?")
end

function M.Plan(force)
    if not session then return nil end
    local sig = PlanSignature()
    if session.plan and session.plan.sig == sig and not force then return session.plan.plan end
    local layout = session.layout
    local plan = LY.Plan(layout.pkg, layout.variant, { picks = session.picks })
    session.plan = { sig = sig, plan = plan }
    return plan
end

-- Notes a failure for the footer to say (cleared by the next step, pick or apply).
function M.NoteFailure(code)
    if session then session.failed = { code = code } end
end

-- Whether Apply could be pressed now. Returns true | false, code (combat, invalid, blocked, nothing), blocked item.
function M.CanApply()
    if not session then return false, "closed" end
    if InCombat() then return false, "combat" end
    local plan = M.Plan()
    if plan.problems then return false, "invalid" end
    if not plan.ok then return false, "blocked", plan.blocked[1] end
    local nothing = true
    for _, id in ipairs(plan.order) do if not plan.parts[id].nothing then nothing = false end end
    if nothing then return false, "nothing" end
    return true
end

function M.ApplyReason(code, blocked)
    if code == "combat" then return "Not during combat. Apply is available again when combat ends." end
    if code == "invalid" then return "The layout package can't be used. TwichUI Diagnostics has the details." end
    if code == "blocked" then return Explain(blocked and blocked.code or "blocked") end
    if code == "nothing" then return Explain("nothing") end
    if code == "stale" then return "What it would do changed since it was shown. Look at the review again." end
    if code == "closed" then return "The setup isn't open." end
    return Explain(code)
end

---------------------------------------------------------------------------
-- The review: a plain account of the plan (what changes, where, when; what is left alone; what doesn't fit)
---------------------------------------------------------------------------
local HELPER = { classBars = "Class resource bars", markersBar = "Marker bar", foodDrink = "Food and drink buttons", navigation = "Navigation" }
local HELPER_ORDER = { "classBars", "markersBar", "foodDrink", "navigation" }

local function Quote(s) return "\"" .. tostring(s) .. "\"" end

M.PRESERVED = {
    "Your key bindings and what is on your action bars' buttons",
    "Your UI scale, window and tooltip skins and spec assignments",
    "Your Cooldown Manager spell lists and your other EllesmereUI profiles",
    "Your TwichUI profile as it is now (the layout uses a copy), your backups, shared setups, pins and Chronicle",
}

-- Returns the review: { ok, blocked = { text }, problems, picks = { { choice, option } }, twichui, ellesmereui (each a
-- section { title, when, lines }), helpers = { labels turned on }, preserved, notes, fit = { fits, lines }, reload,
-- changes, mode, key }.
function M.Review()
    local plan = M.Plan()
    local out = { ok = plan.ok == true, blocked = {}, picks = {}, helpers = {}, preserved = M.PRESERVED, notes = {}, reload = plan.reload,
        changes = plan.changes, mode = plan.mode, key = plan.key, plan = plan }
    if plan.problems then out.problems = true return out end
    for _, b in ipairs(plan.blocked or {}) do
        local adapter = b.adapter and LY.ADAPTERS[b.adapter]
        out.blocked[#out.blocked + 1] = (adapter and (adapter.label or b.adapter) .. ": " or "") .. Explain(b.code)
    end
    out.picks[1] = { choice = "Layout", option = session.layout.title, id = "layout", optionId = session.layout.id }
    for _, ch in ipairs(session.layout.pkg.choices or {}) do
        local o = OptionOf(ch, session.picks[ch.id])
        out.picks[#out.picks + 1] = { choice = ch.label, option = o and o.label or "?", id = ch.id, optionId = o and o.id }
    end
    local geo = plan.geometry
    out.fit = { fits = geo == nil or geo.fits, lines = geo and M.FitLines(geo, 4) or {} }
    local installed = plan.journal
    if installed and installed.variant ~= session.layout.variant then
        local from
        for _, l in ipairs(session.layouts) do if l.id == installed.variant then from = l.title end end
        out.switching = ("%s is installed now. This switches to %s in the same two profiles; Restore still goes back to how things were before your first install."):format(from or tostring(installed.variant), session.layout.title)
    end

    -- TwichUI
    local t = plan.parts.twichui
    if t and not t.blocked then
        local sec = { title = "TwichUI", when = "At once, for this character only", lines = {} }
        if t.nothing then sec.lines[1] = "Already as planned: nothing to change."
        else
            if t.action == "duplicate" then
                sec.lines[#sec.lines + 1] = ("Your profile %s is copied as %s, and this character switches to the copy. %s itself is not changed."):format(Quote(t.profile), Quote(t.target), Quote(t.profile))
            elseif t.action == "switch" then
                sec.lines[#sec.lines + 1] = ("This character goes back to the install's own profile %s."):format(Quote(t.target))
            else
                sec.lines[#sec.lines + 1] = ("The install's own profile %s is updated."):format(Quote(t.target))
            end
            local looks, places, on = 0, 0, {}
            for i, row in ipairs(t.rows) do
                if i > 1 and row.change then
                    if row.place then places = places + 1
                    elseif row.unit:find("^twichui:modules%.") and row.new == true and row.layer == "preset" then
                        on[row.unit:match("^twichui:modules%.(.+)$")] = row.label
                    else looks = looks + 1 end
                end
            end
            for _, key in ipairs(HELPER_ORDER) do
                if on[key] then out.helpers[#out.helpers + 1] = HELPER[key] on[key] = nil end
            end
            for _, key in ipairs(LY.SortedKeys(on)) do out.helpers[#out.helpers + 1] = HELPER[key] or on[key] end
            if looks > 0 then sec.lines[#sec.lines + 1] = ("%d TwichUI %s set in the copy: looks and how a few features behave."):format(looks, Plural(looks, "setting is", "settings are")) end
            if #out.helpers > 0 then sec.lines[#sec.lines + 1] = "Turned on: " .. table.concat(out.helpers, ", ") .. "." end
            if places > 0 then sec.lines[#sec.lines + 1] = ("%d on-screen %s placed for your screen."):format(places, Plural(places, "piece is", "pieces are")) end
        end
        for _, n in ipairs(t.notes or {}) do
            local label = LY.TwichUIAdapter.PLACES[n.id] and LY.TwichUIAdapter.PLACES[n.id].label or n.id
            out.notes[#out.notes + 1] = label .. " isn't placed."
        end
        out.twichui = sec
    end

    -- EllesmereUI
    local e = plan.parts.ellesmereui
    if e and not e.blocked then
        local sec = { title = "EllesmereUI", when = "After a reload that you start, for every character on this account", lines = {} }
        if e.nothing then sec.lines[1] = "Already as planned: nothing to change."
        else
            local row = e.rows[1]
            if row and row.made then
                sec.lines[#sec.lines + 1] = ("A new profile %s is made from the package and becomes the one in use (was %s). EllesmereUI's profile choice belongs to the whole account, so this changes every character's interface."):format(Quote(e.target), Quote(e.active))
            else
                sec.lines[#sec.lines + 1] = ("The profile %s is made again from the package and put in use (was %s). It is shared by every character on this account. Anything you changed in it since the last install is replaced."):format(Quote(e.target), Quote(e.active))
            end
            local whole, placed, sized, text = 0, 0, 0, 0
            for i, r in ipairs(e.rows) do
                if i > 1 then
                    if r.whole then whole = whole + 1
                    elseif r.text then text = text + 1
                    elseif r.place then if r.sized then sized = sized + 1 else placed = placed + 1 end end
                end
            end
            if whole > 0 then sec.lines[#sec.lines + 1] = ("%d %s replaced in it: modules, layout links and the look."):format(whole, Plural(whole, "part is", "parts are")) end
            if sized + placed > 0 then sec.lines[#sec.lines + 1] = ("%d positions and sizes are worked out for your screen."):format(sized + placed) end
            if text > 0 then sec.lines[#sec.lines + 1] = ("%d text %s scaled for the size you picked."):format(text, Plural(text, "size is", "sizes are")) end
        end
        for _, n in ipairs(e.notes or {}) do
            local p = LY.EllesmereAdapter.POSITIONS[n.id]
            out.notes[#out.notes + 1] = (p and p.label or n.id) .. " isn't placed."
        end
        if e.untested then sec.lines[#sec.lines + 1] = ("Tested with EllesmereUI %s; you have %s."):format(tostring(e.tested), tostring(e.version)) end
        out.ellesmereui = sec
    end
    for id, c in pairs(geo and geo.components or {}) do
        if c.managed and c.applied then out.notes[#out.notes + 1] = (c.label or id) .. " isn't applied: EllesmereUI leaves it to Blizzard's Edit Mode, which layouts don't manage yet." end
    end
    table.sort(out.notes)
    return out
end

-- The text of the confirmation that comes before Apply: the exact scope, once. Returns text, key (the plan it describes).
function M.ConfirmText()
    local r = M.Review()
    local lines = { ("Apply %s?"):format(session.layout.title), "" }
    local pk = session.package
    if pk then
        lines[#lines + 1] = ("From the package %s, revision %d, %s. Your game was told who sent it; the package itself can't say."):format(
            QuoteText(pk.env.package.title or pk.env.meta.id), pk.env.meta.version, pk.entry.sender and ("sent by " .. pk.entry.sender) or "sent to you")
        lines[#lines + 1] = ""
    end
    for _, sec in ipairs({ r.twichui, r.ellesmereui }) do
        if sec then
            lines[#lines + 1] = sec.title .. " (" .. sec.when:lower() .. "):"
            for _, l in ipairs(sec.lines) do lines[#lines + 1] = "  " .. l end
        end
    end
    if r.switching then
        lines[#lines + 1] = ""
        lines[#lines + 1] = r.switching
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Nothing reloads by itself. Until you reload, EllesmereUI's part isn't finished or checked. Restore puts your previous profiles back."
    if r.fit and not r.fit.fits then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "It doesn't fit this screen: " .. table.concat(r.fit.lines, " ")
    end
    return table.concat(lines, "\n"), r.key
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------
-- Applies exactly the plan that was shown: `expect` is the key of the plan the confirmation described, and nothing is
-- applied if the plan is not that one any more (a pick, the screen or the game's state changed while the question was
-- open: "stale"). The engine checks the key again. Returns true, result | false, code, extra (see LY.Apply). Goes to the
-- result step.
function M.Apply(expect)
    if not session then return false, "closed" end
    local can, code, blocked = M.CanApply()
    if not can then return false, code, blocked end
    local plan = session.plan.plan
    if type(expect) ~= "string" or plan.key ~= expect then
        session.plan = nil
        session.failed = { code = "stale" }
        return false, "stale"
    end
    local layout = session.layout
    local ok, result, extra = LY.Apply(layout.pkg, layout.variant, plan.key, { picks = session.picks })
    session.plan = nil
    session.check = nil
    if not ok then
        session.failed = { code = result }
        return false, result, extra
    end
    session.failed = nil
    session.result = result
    session.restored = false
    session.step, session.reached = M.RESULT, M.RESULT
    return true, result
end

---------------------------------------------------------------------------
-- The result (step 6): what the install record says now, in words and with the actions that make sense
---------------------------------------------------------------------------
local STATE_TEXT = {
    applied = { title = "Waiting for a reload", tone = "warn" },
    verified = { title = "Checked after the reload", tone = "ok" },
    mismatch = { title = "Not everything reads back as planned", tone = "warn" },
    partial = { title = "Only partly applied", tone = "warn" },
    interrupted = { title = "An install was interrupted", tone = "warn" },
    applying = { title = "An install was interrupted", tone = "warn" },
    restoring = { title = "Restore is waiting for a reload", tone = "warn" },
    ["restore-partial"] = { title = "Not everything is back as it was", tone = "warn" },
}
local STEP_TEXT = { pending = "not finished", done = "done", skipped = "already as planned", failed = "failed",
    partial = "partly done", ["not-run"] = "not run" }
local ADAPTER = { twichui = "TwichUI", ellesmereui = "EllesmereUI" }

local function StepLines(steps)
    local out = {}
    for _, s in ipairs(steps or {}) do
        local extra = ""
        if s.state == "failed" and s.rollback then
            extra = s.rollback == "clean" and " (what it changed was put back)" or " (not everything it changed could be put back)"
        end
        out[#out + 1] = (ADAPTER[s.adapter] or s.adapter) .. ": " .. (STEP_TEXT[s.state] or s.state) .. (s.code and (". " .. Explain(s.code)) or "") .. extra
    end
    return out
end

local function DiffLines(diffs)
    local out = {}
    for _, d in ipairs(diffs or {}) do
        local a = LY.ADAPTERS[d.adapter]
        out[#out + 1] = (ADAPTER[d.adapter] or tostring(d.adapter)) .. ": " .. tostring(a and a.Label(d.unit) or d.unit) .. " (" .. tostring(d.code) .. ")"
    end
    return out
end

-- { kind, title, tone, lines, steps, diffs, picks = { { choice, option } }, can = { restore, reload, again, keep, check, forget } }
function M.Result()
    local out = { lines = {}, steps = {}, diffs = {}, picks = {}, can = {} }
    if not session then out.kind, out.title = "closed", "" return out end
    local j, why = LY.Journal.Read()
    local combat = InCombat()
    if not j then
        if why == "damaged" then
            out.kind, out.title, out.tone = "damaged", "The install record can't be read", "warn"
            out.lines[1] = Explain("journal-damaged")
            out.can.forget = true
        elseif why == "newer" then
            out.kind, out.title, out.tone = "newer", "The install record is from a newer TwichUI", "warn"
            out.lines[1] = Explain("journal-newer")
        elseif session.result and session.result.state == "failed" then
            out.kind, out.title, out.tone = "failed", "Nothing was changed", "warn"
            out.lines[1] = "The install couldn't be applied, and it left your setup exactly as it was."
            out.steps = StepLines(session.result.steps)
            out.can.again = true
        elseif session.restored then
            out.kind, out.title, out.tone = "restored", "Restored", "ok"
            out.lines[1] = "Everything the install changed is back as it was, and the install's own profiles are gone."
            out.can.again = true
        else
            out.kind, out.title, out.tone = "none", "Nothing is installed", "info"
            out.lines[1] = "No layout install is recorded. Choose a layout and review it to set one up."
            out.can.again = true
        end
        return out
    end
    if j.char ~= Me() then
        out.kind, out.title, out.tone = "other-character", "Installed on another character", "warn"
        out.lines[1] = Explain("journal-other-character")
        return out
    end
    local st = STATE_TEXT[j.state] or { title = j.state, tone = "info" }
    out.kind, out.state, out.title, out.tone = j.state, j.state, st.title, st.tone
    out.at = j.at
    local ch = session.layout.pkg.choices or {}
    for _, l in ipairs(session.layouts) do
        if l.id == j.variant then out.picks[#out.picks + 1] = { choice = "Layout", option = l.title } end
    end
    for _, c in ipairs(ch) do
        local id = j.picks and j.picks[c.id]
        local o = id and OptionOf(c, id)
        if o then out.picks[#out.picks + 1] = { choice = c.label, option = o.label } end
    end
    out.steps = StepLines(j.restore and (j.state == "restoring" or j.state == "restore-partial") and j.restore.steps or j.steps)
    if j.state == "applied" then
        out.lines[1] = "The install is written. EllesmereUI's part is finished by a reload, and TwichUI reads every value back after it. Nothing reloads by itself."
        out.can.reload = not combat
        out.can.restore = true
    elseif j.state == "verified" then
        out.lines[1] = "Every value the install wrote reads back as planned."
        out.lines[2] = "Restore puts your previous profiles back; keeping this setup forgets the restore point and changes nothing else."
        out.can.restore, out.can.keep, out.can.again, out.can.check = true, true, true, true
    elseif j.state == "mismatch" then
        local unreadable = j.verify and j.verify.state ~= "mismatch"
        out.lines[1] = unreadable and "Some values couldn't be read back, so they aren't confirmed." or "Some values don't read back as planned. TwichUI doesn't repair them."
        out.diffs = DiffLines(j.verify and j.verify.diffs)
        out.can.restore, out.can.check, out.can.again = true, true, true
    elseif j.state == "partial" then
        out.lines[1] = "A step failed after another had already changed something. Nothing was undone for you."
        out.can.restore = true
        if j.reload then out.can.reload = not combat end
    elseif j.state == "interrupted" or j.state == "applying" then
        out.lines[1] = "The game stopped before the install finished. Restore puts back what it changed."
        out.can.restore = true
    elseif j.state == "restoring" then
        out.lines[1] = "The restore is written. EllesmereUI finishes it at a reload, and TwichUI checks that everything is back after it."
        out.can.reload = not combat
    elseif j.state == "restore-partial" then
        out.lines[1] = "The restore was not fully checked. You can try it again."
        out.diffs = DiffLines(j.verify and j.verify.diffs)
        out.can.restore, out.can.check = true, true
    end
    if session.check then
        local c = session.check
        if c.state == "match" then out.lines[#out.lines + 1] = "Checked just now: every managed value reads back as planned."
        else out.lines[#out.lines + 1] = "Checked just now: " .. c.state .. "." out.diffs = DiffLines(c.diffs) end
    end
    if combat then out.combat = "Applying, restoring and reloading wait until combat ends." end
    return out
end

-- Reads every managed value back now (read only; nothing is repaired, and the record is not rewritten).
function M.Check()
    if not session then return nil end
    local j = LY.Journal.Read()
    local report
    if j and (j.state == "restoring" or j.state == "restore-partial") then report = LY.VerifyRestore(false)
    else report = LY.Verify(false) end
    if not report then session.check = nil return nil end
    local diffs = {}
    for _, id in ipairs(LY.SortedKeys(report.adapters or {})) do
        for _, d in ipairs(report.adapters[id].diffs or {}) do diffs[#diffs + 1] = { adapter = id, unit = d.unit, code = d.code } end
    end
    session.check = { state = report.state, diffs = diffs }
    return session.check
end

---------------------------------------------------------------------------
-- Restore, keeping, forgetting, reloading
---------------------------------------------------------------------------
function M.RestorePlan()
    local plan = LY.PlanRestore()
    local out = { ok = plan.ok == true, key = plan.key, reload = plan.reload, lines = {}, blocked = {}, plan = plan }
    for _, b in ipairs(plan.blocked or {}) do
        out.blocked[#out.blocked + 1] = (b.adapter and (ADAPTER[b.adapter] or b.adapter) .. ": " or "") .. Explain(b.code)
    end
    for _, id in ipairs(plan.order or {}) do
        local part = plan.parts[id]
        if not part.blocked then
            if #part.actions == 0 then out.lines[#out.lines + 1] = (ADAPTER[id] or id) .. ": nothing to put back." end
            for _, act in ipairs(part.actions) do
                if act.kind == "switch" then
                    out.lines[#out.lines + 1] = ("%s: back to your profile %s."):format(ADAPTER[id] or id, Quote(act.to))
                else
                    out.lines[#out.lines + 1] = ("%s: the install's profile %s is removed. Changes you made in it since go with it."):format(ADAPTER[id] or id, Quote(act.name))
                end
            end
        end
    end
    if plan.reload then out.lines[#out.lines + 1] = "EllesmereUI finishes it at a reload that you start." end
    return out
end

function M.RestoreConfirmText()
    local rp = M.RestorePlan()
    local lines = { "Put your previous setup back?", "" }
    for _, l in ipairs(rp.lines) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Nothing reloads by itself. Your own profiles, key bindings, backups and saved data are not touched."
    return table.concat(lines, "\n"), rp
end

-- Restores exactly the restore plan that was shown. Returns true, result | false, code, extra.
function M.Restore(key)
    if not session then return false, "closed" end
    if InCombat() then return false, "combat" end
    local ok, result, extra = LY.Restore(key)
    session.check = nil
    if not ok then return false, result, extra end
    session.restoreResult = result
    if result.state == "restored" then session.restored = true end
    session.step = M.RESULT
    return true, result
end

-- Forgets the install record: what was installed stays, and so does everything else. (The package's own Detach.)
function M.Keep()
    if not session then return false end
    local done = LY.Detach()
    if done then session.restored = false end
    session.check = nil
    return done
end

-- Starts the reload the player asked for, leaving a note so the result is shown when the game is back. Refused in combat.
function M.Reload()
    if not session then return false, "closed" end
    if InCombat() then return false, "combat" end
    local j = LY.Journal.Read()
    local kind = (j and (j.state == "restoring")) and "restore" or "install"
    S.SetResume(session.layout.pkg, session.picks, kind)
    ReloadUI()
    return true
end
