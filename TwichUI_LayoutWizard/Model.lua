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
local function ADAPTER_LABEL(id) return (LY.ADAPTERS[id] and LY.ADAPTERS[id].label) or tostring(id) end
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
    if j or why or LY.Journal.ReadManaged() then
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
            session.plan, session.pv, session.failed, session.update = nil, nil, nil, nil
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
        s.plan, s.pv, s.scene, s.failed, s.check, s.compat, s.update = nil, nil, nil, nil, nil, nil, nil
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
        -- the UI scale setting (the game's, and EllesmereUI's): the screen is 768 / scale units tall, whatever its pixels
        s = s .. (" (%d × %d pixels at UI scale %.2f)"):format(screen.physW, screen.physH, M.UIScale(screen))
    end
    return s
end

-- The UI scale a screen of these units is at: 768 units of height at UI scale 1 (the game's and EllesmereUI's convention;
-- the author's 1440-pixel screen at 0.64 is 1200 units tall).
function M.UIScale(screen) return 768 / screen.h end

-- Scale guidance for a layout that doesn't fit (RH-1 D): the largest UI scale at which its components fit on a screen of this
-- shape, or nil. Worked out with the same resolver, on screens of the same proportions; never applied (the UI scale stays the
-- player's). Returns scale | nil, why ("readable": it would need less than M.MIN_SCALE).
M.MIN_SCALE = 0.64   -- below it, text gets small; TwichUI doesn't suggest going lower
function M.ScaleHint(layout, screen, density)
    if not (layout and screen and screen.h and screen.h > 0) then return nil end
    local key = ("%s,%.2f,%.2f,%s"):format(layout.id or layout.variant, screen.w, screen.h, tostring(density))
    session.scaleHints = session.scaleHints or {}
    local cached = session.scaleHints[key]
    if cached then return cached.scale, cached.why end
    local ratio, found = screen.w / screen.h, nil
    for h = math.ceil(screen.h), 768 / M.MIN_SCALE + 1, 8 do
        local geo = LY.Geometry.Resolve(layout.pkg.geometry, { w = h * ratio, h = h }, { density = density, variant = layout.variant })
        if geo and geo.fits then found = h break end
    end
    local scale, why
    if found then scale = math.floor(768 / found * 100) / 100 else why = "readable" end
    if scale and scale >= M.UIScale(screen) then scale, why = nil, nil end   -- it fits already
    session.scaleHints[key] = { scale = scale, why = why }
    return scale, why
end

-- The guidance as a sentence, or nil.
function M.ScaleText(layout, screen, density)
    local scale, why = M.ScaleHint(layout, screen, density)
    if scale then
        return ("It fits at a UI scale of %.2f or smaller (yours is %.2f). The setup never changes your UI scale: it is in the game's settings, or EllesmereUI's if it sets it."):format(scale, M.UIScale(screen))
    elseif why == "readable" then
        return ("It would need a UI scale below %.2f, which makes text hard to read. A smaller layout or the Standard size may suit this screen better."):format(M.MIN_SCALE)
    end
end

local DIAG = { overlap = "overlaps", offscreen = "doesn't fit on the screen", clamped = "was moved back onto the screen",
    minimum = "is at its smallest readable size" }
M.DIAG = DIAG

-- Plain sentences for a geometry's problems (overlaps and off-screen pieces), at most `max`. A component the layout never
-- applies (the objective tracker) is only illustrative: its overlaps are left to IllustrativeLines, not counted here.
function M.FitLines(geo, max)
    local out = {}
    for _, d in ipairs(geo and geo.diagnostics or {}) do
        if (d.code == "overlap" or d.code == "offscreen") and not d.illustrative then
            local a = geo.components[d.id]
            local b = d.other and geo.components[d.other]
            out[#out + 1] = ("%s %s%s."):format(a and a.label or d.id, DIAG[d.code] or d.code,
                b and (" " .. (b.label or d.other)) or "")
            if #out >= (max or 4) then break end
        end
    end
    return out
end

-- The pieces' check (LY.Fit): plain sentences, at most `max`. Sample sizes, so "may".
local PIECE = { ["piece-offscreen"] = "would be partly off the screen", ["piece-over"] = "may overlap", ["marker-over"] = "may sit on" }
function M.PieceLines(fit, max)
    local out = {}
    for _, it in ipairs(fit and fit.issues or {}) do
        if not it.illustrative then
            out[#out + 1] = ("%s %s%s."):format(it.label or it.id, PIECE[it.code] or it.code, it.otherLabel and (" " .. it.otherLabel) or "")
            if #out >= (max or 4) then break end
        end
    end
    return out
end

-- What is drawn but never placed by the layout (the objective tracker): one sentence, or nil.
function M.IllustrativeLines(geo)
    for id, c in pairs(geo and geo.components or {}) do
        if c.managed and c.applied then
            return ("%s is drawn where it would go, but Blizzard's Edit Mode places it, so it isn't part of the fit check."):format(c.label or id)
        end
    end
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
        local failed, notFit, fitting, overlaps, hints = false, {}, {}, {}, {}
        for _, l in ipairs(session.layouts) do
            local geo = LY.Geometry.Resolve(l.pkg.geometry, screen, { density = "standard", variant = l.variant })
            local fit = geo and LY.Fit(l.pkg, l.variant, geo)
            if not geo then failed = true
            elseif not geo.fits then
                notFit[#notFit + 1] = l.title .. ": " .. table.concat(M.FitLines(geo, 2), " ")
                hints[#hints + 1] = M.ScaleText(l, screen, "standard")
            elseif not fit.clear then overlaps[#overlaps + 1] = l.title .. ": " .. table.concat(M.PieceLines(fit, 2), " ")
            else fitting[#fitting + 1] = l.title end
        end
        if failed then Add("screen", "Your screen", "warn", text .. ". TwichUI couldn't work out where things would go.")
        elseif #notFit == 0 and #overlaps == 0 then Add("screen", "Your screen", "ok", text .. ". Everything fits, in either layout.")
        else
            -- fits the boxes, but a piece reaches past its box (sample sizes); or doesn't fit at all
            local line = text .. ". " .. (#fitting > 0 and (table.concat(fitting, " and ") .. " fits. ") or "")
            if #overlaps > 0 then line = line .. "Fits, but some pieces may overlap: " .. table.concat(overlaps, " ") .. " " end
            if #notFit > 0 then line = line .. "Not everything fits: " .. table.concat(notFit, " ") .. " " end
            line = line .. (hints[1] and hints[1] or "The layout never shrinks anything below readable.")
            Add("screen", "Your screen", "warn", line)
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
-- On the layout and choice steps the preview is the layout's recommended placement, at once. On Review, for an update, it is
-- the final plan (RH-1 C): what Apply leaves where the player has it is drawn there (plan.final), and M.SceneNote says what
-- isn't. Planning reads only: no profile is changed to draw it.
local function Final()
    local plan = session.step == M.REVIEW and session.plan and session.plan.plan
    return plan and plan.final or nil
end

function M.Scene()
    if not session then return nil, "closed" end
    local geo, why = M.Preview()
    if not geo then return nil, why end
    local final = Final()
    local moved
    if final then geo, moved = final.geometry, final.moved end
    local tip = session.scenario == "tooltip" and M.TooltipAnchor() or nil
    local key = session.scenario .. (tip and ("|%s,%s,%s"):format(tip.point, tip.x, tip.y) or "")
    if session.scene and session.scene.key == key and session.scene.geo == geo then return session.scene.scene end
    local scene = Scene.Build(session.layout, geo, { scenario = session.scenario, tooltip = tip, moved = moved })
    if scene then scene.fit = (final and final.fit) or LY.Fit(session.layout.pkg, session.layout.variant, geo) end
    session.scene = { key = key, geo = geo, scene = scene }
    return scene
end

-- The preview's problems, as Pages shows them under it: the components', then the pieces'. nil when there are none.
function M.SceneIssues(scene)
    if not scene then return nil end
    local out = scene.fits and {} or M.FitLines(scene.geo, 3)
    for _, l in ipairs(M.PieceLines(scene.fit, 3 - #out)) do out[#out + 1] = l end
    return #out > 0 and out or nil
end

-- What the preview shows, beyond the caption: nil on the layout and choice steps (the recommended placement), and on Review
-- for an update, which of the player's own placements it draws and which it can't.
function M.SceneNote()
    local final = session and Final()
    if not final then return nil end
    if final.exact then return "This is the final result: the update leaves nothing of yours elsewhere." end
    local parts = {}
    if #final.whole > 0 then parts[#parts + 1] = "EllesmereUI is kept as you have it; its pieces are drawn where you have the ones TwichUI can read." end
    local drawn, odd = 0, {}
    for _, it in ipairs(final.retained) do
        if it.rec or it.value then drawn = drawn + 1 else odd[#odd + 1] = it.label end
    end
    if drawn > 0 then parts[#parts + 1] = ("%d of your own placements %s drawn where you have %s."):format(drawn, Plural(drawn, "is", "are"), Plural(drawn, "it", "them")) end
    if #odd > 0 then parts[#parts + 1] = "Not drawn (kept in a form TwichUI can't read): " .. table.concat(odd, ", ") .. "." end
    return "Shown as Apply leaves it. " .. table.concat(parts, " ")
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
        .. "|" .. (session.update and session.update.gen or 0)
end

-- How an update treats what the player changed since the last install (updates.md): the engine's opts.update. Kept for the
-- session only; a new layout or package starts again from "keep my changes".
local function UpdateOpts()
    local u = session.update
    if not u then
        u = { policy = "keep", choose = {}, groups = {}, whole = {}, details = false, page = 1, gen = 0 }
        session.update = u
    end
    return u
end

function M.Plan(force)
    if not session then return nil end
    local sig = PlanSignature()
    if session.plan and session.plan.sig == sig and not force then return session.plan.plan end
    local layout = session.layout
    local u = UpdateOpts()
    local plan = LY.Plan(layout.pkg, layout.variant, { picks = session.picks,
        update = { policy = u.policy, choose = u.choose, groups = u.groups, whole = u.whole } })
    session.plan = { sig = PlanSignature(), plan = plan }
    return plan
end

---------------------------------------------------------------------------
-- Updating an installed layout: the three ways (keep my changes, the recommended configuration, review each conflict), and
-- the per-setting choices. Each changes what the plan will do, so the plan is worked out again; nothing in the game changes.
---------------------------------------------------------------------------
local function Changed()
    local u = UpdateOpts()
    u.gen = u.gen + 1
    session.plan, session.failed = nil, nil
end

-- "keep" (update while keeping my customizations), "recommended" (reapply the recommended configuration), "review" (keep,
-- with every conflict shown to choose). Returns true | false, code.
function M.SetUpdateMode(mode)
    if not session then return false, "closed" end
    local u = UpdateOpts()
    if mode == "review" then
        if u.policy ~= "keep" then u.policy = "keep" Changed() end
        u.details = true
    elseif mode == "keep" or mode == "recommended" then
        if u.policy ~= mode then u.policy = mode Changed() end
        u.details = false
    else
        return false, "unknown-mode"
    end
    return true
end

function M.UpdateMode()
    local u = session and UpdateOpts()
    if not u then return "keep" end
    if u.policy == "recommended" then return "recommended" end
    return u.details and "review" or "keep"
end

function M.ShowDetails(v)
    if not session then return end
    UpdateOpts().details = v and true or false
end

-- A choice for one setting: "mine" | "package" | "own" | "manage" | nil (back to the way's default).
function M.Choose(unit, choice)
    if not session then return false, "closed" end
    if choice ~= nil and not LY.Merge.CHOICES[choice] then return false, "unknown-choice" end
    local u = UpdateOpts()
    if u.choose[unit] == choice then return true, false end
    u.choose[unit] = choice
    Changed()
    return true, true
end

function M.ChooseGroup(group, choice)
    if not session then return false, "closed" end
    if choice ~= nil and choice ~= "mine" and choice ~= "package" then return false, "unknown-choice" end
    local u = UpdateOpts()
    u.groups[group] = choice
    Changed()
    return true
end

-- For an addon whose changes can't be carried into the new install: "keep" (this update leaves it as it is) or "replace"
-- (the layout's, with the player's current profile kept for "Undo this update").
function M.SetWhole(adapter, choice)
    if not session then return false, "closed" end
    if choice ~= "keep" and choice ~= "replace" then return false, "unknown-choice" end
    UpdateOpts().whole[adapter] = choice
    Changed()
    return true
end

function M.SetDetailPage(n)
    if not session then return end
    UpdateOpts().page = math.max(1, n)
end

local CASE_ORDER = { conflict = 1, unknown = 2, mine = 3, owned = 4, added = 5, package = 6, removed = 7, ["both-same"] = 8, same = 9 }
local CHOICE_TEXT = { mine = "Keep mine", package = "Use recommended", own = "Stop managing", manage = "Manage again" }
M.CHOICE_TEXT = CHOICE_TEXT

local function ShowValue(adapter, v, comparable)
    if not comparable then return nil end
    local a = LY.ADAPTERS[adapter]
    if v == LY.Merge.ABSENT then return "(not set)" end
    return a and a.Show and a.Show(v) or tostring(v)
end

-- The review's update part, or nil when this is a first install:
-- { mode, baseline, counts, summary = { lines }, rows = { { adapter, unit, label, case, caseText, decision, current,
--   recommended, effect, owner, offers = { { choice, label } }, chosen, group } }, groups = { { id, adapter, choice, text } },
--   whole = { { adapter, choice, text } }, warnings = { lines }, notes = { lines } }
function M.UpdateReview(plan)
    plan = plan or M.Plan()
    local up = plan and plan.update
    if not up then return nil end
    local u = UpdateOpts()
    local out = { mode = M.UpdateMode(), baseline = up.baseline, counts = up.counts, summary = {}, rows = {}, groups = {}, whole = {},
        warnings = {}, notes = {}, details = u.details, page = u.page }
    local c = up.counts
    local apply, keep, conflict, owned = c.apply or 0, c.keep or 0, c.conflict or 0, c.owned or 0
    if up.resume then out.summary[#out.summary + 1] = "The last update stopped part way. What it already finished is not done again." end
    if up.baseline ~= "ok" then
        out.summary[#out.summary + 1] = "TwichUI has no record of what the last install left you with, so it can't tell your changes from the layout's. Anything that differs is treated as yours."
    end
    out.summary[#out.summary + 1] = ("%d %s to the layout's recommended values."):format(apply, Plural(apply, "setting changes", "settings change"))
    if keep > 0 then out.summary[#out.summary + 1] = ("%d of your own %s kept as you have %s."):format(keep, Plural(keep, "changes is", "changes are"), Plural(keep, "it", "them")) end
    if conflict > 0 then
        out.summary[#out.summary + 1] = ("%d %s changed both by you and by the layout: %s."):format(conflict, Plural(conflict, "setting was", "settings were"),
            u.policy == "recommended" and "the layout's value is used" or "yours is kept unless you choose otherwise")
    end
    if owned > 0 then out.summary[#out.summary + 1] = ("%d %s yours: updates never change %s."):format(owned, Plural(owned, "setting is", "settings are"), Plural(owned, "it", "them")) end
    for id in pairs(up.fresh or {}) do
        out.notes[#out.notes + 1] = ("%s: the install's own profile isn't there any more, so it is made again from the layout and nothing of yours can be compared."):format(ADAPTER_LABEL(id))
    end
    local e = plan.parts.ellesmereui
    if e and e.level == "whole" then
        out.notes[#out.notes + 1] = "EllesmereUI's part of this layout is one whole profile: TwichUI can keep your changes to the few settings it reads, not inside it."
    end
    if e and e.backup then
        out.notes[#out.notes + 1] = ("EllesmereUI: your current %s is kept as %s, so Undo this update can put it back exactly."):format(QuoteText(e.target), QuoteText(e.backup.name))
        if e.backup.replaces then
            -- the copy an earlier update kept goes once this one works: that earlier update can't be undone any more
            out.loss = ("The copy %s kept by your last update (from before it) is replaced by this one, so that update can no longer be undone. Restore still goes back to before your first install."):format(QuoteText(e.backup.name))
            out.notes[#out.notes + 1] = out.loss
        end
    end
    for _, w in ipairs(up.warnings or {}) do
        out.warnings[#out.warnings + 1] = w.code == "offscreen" and ("%s, where you put it, is off this screen. It stays where you put it."):format(w.label)
            or ("%s, where you put it, is over %s. It stays where you put it."):format(w.label, w.other or "another piece")
    end
    for _, part in pairs(plan.parts) do
        for _, n in ipairs(part.linkNotes or {}) do
            local p = LY.EllesmereAdapter.POSITIONS[n.id]
            out.warnings[#out.warnings + 1] = ("%s: its layout link couldn't be moved to match, so EllesmereUI may place it from the link."):format(p and p.label or n.id)
        end
    end
    for g, info in pairs(up.groups or {}) do
        out.groups[#out.groups + 1] = { id = g, adapter = info.adapter, choice = info.choice, owned = info.owned,
            text = info.owned and "The layout links and the frames linked to them change together, and one of them is a setting you made yours (Stop managing), so they all stay as you have them. Use Manage again on it to let the layout's links in."
                or info.choice == "mine" and "The layout links and the frames linked to them change together. You changed some and the layout changed others, so they stay as you have them (all of them)."
                or "The layout links and the frames linked to them change together. They take the layout's (all of them)." }
    end
    for id, w in pairs(up.whole or {}) do
        out.whole[#out.whole + 1] = { adapter = id, choice = w.choice,
            text = ("%s: some of your changes are inside parts TwichUI can only replace whole, and your %s data is from another version than the layout's, so they can't be carried over one by one."):format(ADAPTER_LABEL(id), ADAPTER_LABEL(id))
                .. (w.choice == "keep" and " As chosen, this update leaves it exactly as it is." or (" As chosen, it is replaced with the layout's; your current profile is kept so Undo this update can bring it back.")) }
    end
    for _, row in ipairs(up.rows) do
        if row.case ~= "same" and row.case ~= "both-same" then
            local comparable = row.comparable
            local offers = {}
            for _, ch in ipairs(row.offers or {}) do offers[#offers + 1] = { choice = ch, label = CHOICE_TEXT[ch] } end
            local effect = LY.Merge.EFFECT[row.decision] or ""
            -- a whole part (a module, the links, the look) is kept or replaced whole: never merged inside, and the row says so
            if not comparable and row.decision == "apply" then effect = "Replaced whole with the layout's version (TwichUI can't merge inside it)." end
            if not comparable and row.decision == "keep" then effect = "Your version is carried into the new install whole." end
            if not comparable and row.case == "conflict" then
                effect = effect .. " TwichUI can't merge inside this part: keeping yours skips the layout's changes to it, and using the layout's drops your changes in it."
            end
            out.rows[#out.rows + 1] = { adapter = row.adapter, unit = row.unit, label = row.label, case = row.case,
                caseText = LY.Merge.CASE_TEXT[row.case] or row.case, decision = row.decision, how = row.how,
                current = ShowValue(row.adapter, row.e and row.e.cv, comparable) or (comparable and "(not set)" or "your version"),
                recommended = row.e and row.e.n ~= nil and (ShowValue(row.adapter, row.e.nv, comparable) or "the layout's version") or "(not in the layout)",
                effect = effect, owner = LY.Merge.OWNER[row.decision] or "", offers = offers, chosen = u.choose[row.unit], group = row.group }
        end
    end
    table.sort(out.rows, function(a, b)
        local x, y = CASE_ORDER[a.case] or 99, CASE_ORDER[b.case] or 99
        if x ~= y then return x < y end
        return a.label < b.label
    end)
    return out
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
    local nothing = not (plan.update and (plan.update.recordOnly or plan.update.resume))
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
    -- the fit of what Apply leaves (the final plan, for an update), never only of the recommended placement (RH-1 C, D)
    local final = plan.final
    local fgeo = final and final.geometry or geo
    local fit = (final and final.fit) or (geo and LY.Fit(session.layout.pkg, session.layout.variant, geo)) or nil
    out.fit = { fits = fgeo == nil or fgeo.fits, clear = fgeo == nil or (fit and fit.clear) or false, lines = fgeo and M.FitLines(fgeo, 4) or {},
        pieces = M.PieceLines(fit, 4), illustrative = fgeo and M.IllustrativeLines(fgeo) or nil, exact = not final or final.exact,
        recommendedFits = geo == nil or geo.fits }
    if final and not final.exact then
        local labels = {}
        for _, it in ipairs(final.retained) do labels[#labels + 1] = it.label end
        out.fit.retained = #final.whole > 0 and "EllesmereUI is kept as you have it, so its placement is yours, not the layout's."
            or ("Kept where you have %s, and checked there (never moved to clear a warning): %s."):format(Plural(#labels, "it", "them"), table.concat(labels, ", "))
    end
    if fgeo and not out.fit.fits then out.fit.scale = M.ScaleText(session.layout, fgeo.screen, plan.density) end
    local installed = plan.journal
    if installed and installed.variant ~= session.layout.variant then
        local from
        for _, l in ipairs(session.layouts) do if l.id == installed.variant then from = l.title end end
        out.switching = ("%s is installed now. This switches to %s in the same two profiles; Restore still goes back to how things were before your first install."):format(from or tostring(installed.variant), session.layout.title)
        if plan.update then
            out.switching = out.switching .. (" Your changes to settings both layouts share are kept; changes to what %s sets for itself go back to %s's own values unless you keep yours."):format(from or tostring(installed.variant), session.layout.title)
        end
    end
    out.update = M.UpdateReview(plan)

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
        if e.kept then sec.lines[1] = "Kept as it is, as you chose: this update doesn't change EllesmereUI."
        elseif e.nothing then sec.lines[1] = "Already as planned: nothing to change."
        else
            local row = e.rows[1]
            if row and row.made then
                sec.lines[#sec.lines + 1] = ("A new profile %s is made from the package and becomes the one in use (was %s). EllesmereUI's profile choice belongs to the whole account, so this changes every character's interface."):format(Quote(e.target), Quote(e.active))
            elseif plan.update then
                sec.lines[#sec.lines + 1] = ("The profile %s is made again from the package and put in use (was %s), with the changes of yours listed under Updating carried over. It is shared by every character on this account."):format(Quote(e.target), Quote(e.active))
                if e.backup then sec.lines[#sec.lines + 1] = ("Your current one is kept as %s until you keep the update, so Undo this update can put it back."):format(Quote(e.backup.name)) end
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
            if n.code == "unplaced" then
                out.notes[#out.notes + 1] = (n.label or n.id) .. " stays where the layout's author had it (measured from the middle of the screen): it isn't placed for your screen or part of the fit check."
            else
                out.notes[#out.notes + 1] = (p and p.label or n.id) .. " isn't placed."
            end
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
    if r.update then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Updating (" .. (r.update.mode == "recommended" and "the recommended configuration" or "keeping your changes") .. "):"
        for _, l in ipairs(r.update.summary) do lines[#lines + 1] = "  " .. l end
        for _, w in ipairs(r.update.whole) do lines[#lines + 1] = "  " .. w.text end
        if r.update.loss then lines[#lines + 1] = "  " .. r.update.loss end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = r.update and "Nothing reloads by itself. Until you reload, EllesmereUI's part isn't finished or checked. Undo this update (on the Result step) puts back how things are now; Restore goes back to before your first install."
        or "Nothing reloads by itself. Until you reload, EllesmereUI's part isn't finished or checked. Restore puts your previous profiles back."
    if r.fit and not r.fit.fits then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "It doesn't fit this screen: " .. table.concat(r.fit.lines, " ")
        if r.fit.scale then lines[#lines + 1] = r.fit.scale end
    elseif r.fit and not r.fit.clear and #r.fit.pieces > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Some pieces may overlap on this screen: " .. table.concat(r.fit.pieces, " ")
    end
    if r.fit and r.fit.retained then lines[#lines + 1] = r.fit.retained end
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
    local u = UpdateOpts()
    local ok, result, extra = LY.Apply(layout.pkg, layout.variant, plan.key, { picks = session.picks,
        update = { policy = u.policy, choose = u.choose, groups = u.groups, whole = u.whole } })
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
    undoing = { title = "Undoing the update is waiting for a reload", tone = "warn" },
    ["undo-partial"] = { title = "Not everything is as it was before the update", tone = "warn" },
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
        elseif LY.Journal.ReadManaged() then
            -- the setup was finished: TwichUI still manages the layout (no way back is kept, but updates keep your changes)
            local m = LY.Journal.ReadManaged()
            local title = m.variant
            for _, l in ipairs(session.layouts) do if l.id == m.variant then title = l.title end end
            out.kind, out.title, out.tone = "managed", "Installed and managed", "ok"
            out.lines[1] = ("%s, revision %d, is installed. Its setup is finished, so Restore isn't offered; setting it up again updates it and keeps the changes you made since."):format(title, m.revision)
            -- the last check after a reload didn't match (or couldn't read everything): said, never shown as a plain install
            if m.check and m.check ~= "match" then
                out.title, out.tone = "Installed and managed, not verified", "warn"
                out.lines[#out.lines + 1] = "When it was last checked after a reload, some values didn't read back as planned. What didn't is compared with the last install that did check out when you update."
                out.can.check = m.char == Me()
            end
            if m.char ~= Me() then out.lines[1] = Explain("journal-other-character") end
            out.can.again, out.can.stop = m.char == Me(), m.char == Me()
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
    local undoingNow = j.state == "undoing" or j.state == "undo-partial"
    out.steps = StepLines(j.restore and (j.state == "restoring" or j.state == "restore-partial" or undoingNow) and j.restore.steps or j.steps)
    if j.state == "applied" then
        out.lines[1] = "The install is written. EllesmereUI's part is finished by a reload, and TwichUI reads every value back after it. Nothing reloads by itself."
        out.can.reload = not combat
        out.can.restore = true
    elseif j.state == "verified" then
        local byValue = j.verify and j.verify.checked or 0
        out.lines[1] = ("Verified by value: every setting TwichUI can read by value (%d) reads back as planned."):format(byValue)
        local pres = j.verify and j.verify.presence or 0
        if pres > 0 then
            out.lines[#out.lines + 1] = ("%d EllesmereUI %s (modules, layout links, look) %s replaced whole: TwichUI checked only that %s there, not what is inside."):format(
                pres, Plural(pres, "part", "parts"), Plural(pres, "is", "are"), Plural(pres, "it is", "they are"))
        end
        out.lines[#out.lines + 1] = "Restore puts your previous profiles back. Keeping this setup finishes it: the restore point is forgotten, nothing installed changes, and TwichUI keeps managing the layout for later updates."
        out.can.restore, out.can.keep, out.can.again, out.can.check = true, true, true, true
    elseif j.state == "mismatch" then
        local unreadable = j.verify and j.verify.state ~= "mismatch"
        out.lines[1] = unreadable and "Some values couldn't be read back, so they aren't confirmed." or "Some values don't read back as planned. TwichUI doesn't repair them."
        out.diffs = DiffLines(j.verify and j.verify.diffs)
        out.can.restore, out.can.check, out.can.again = true, true, true
    elseif j.state == "partial" then
        out.lines[1] = "The install didn't finish: a step failed or never ran after another had already changed something, so it isn't treated as installed. Nothing was undone for you."
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
    elseif j.state == "undoing" then
        out.lines[1] = "Undoing the update is written. EllesmereUI finishes it at a reload, and TwichUI checks that everything is as it was before the update."
        out.can.reload = not combat
    elseif j.state == "undo-partial" then
        out.lines[1] = "Undoing the update was not fully checked. You can try it again, or Restore goes back to before your first install."
        out.diffs = DiffLines(j.verify and j.verify.diffs)
        out.can.restore, out.can.check = true, true
        if j.reload then out.can.reload = not combat end
    end
    -- an update: one step back is kept until the update is kept for good
    if j.update then
        if j.state == "verified" or j.state == "mismatch" or j.state == "partial" or j.state == "interrupted" or j.state == "applied" or j.state == "undo-partial" then
            out.can.undo = true
            out.lines[#out.lines + 1] = "This was an update. Undo this update puts back how things were just before it; Restore previous setup goes back to before your first install."
        end
        if j.state == "verified" or j.state == "mismatch" then out.can.keepUpdate = true end
        if j.state == "partial" then
            out.can.again = true
            out.lines[#out.lines + 1] = "Set up again with the same choices finishes it: what was already done isn't done a second time."
        end
    end
    if j.state == "mismatch" and j.verify and j.verify.baseline then
        local n = 0
        for _, s in ipairs(j.steps) do if s.state == "done" or s.state == "skipped" then n = n + 1 end end
        if #j.verify.baseline < n then
            out.lines[#out.lines + 1] = "What didn't read back isn't taken as the starting point for the next update: TwichUI keeps comparing with the last install that did."
        end
    end
    if session.check then
        local c = session.check
        if c.state == "match" then out.lines[#out.lines + 1] = "Checked just now: what can be read by value reads back as planned (whole EllesmereUI parts only for being there)."
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
    elseif j and (j.state == "undoing" or j.state == "undo-partial") then report = LY.VerifyUndo(false)
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
                elseif act.backup then
                    out.lines[#out.lines + 1] = ("%s: %s, the copy an update kept, is removed."):format(ADAPTER[id] or id, Quote(act.name))
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

---------------------------------------------------------------------------
-- Undo this update, and keeping it for good
---------------------------------------------------------------------------
function M.UndoPlan()
    local plan = LY.PlanUndo()
    local out = { ok = plan.ok == true, key = plan.key, reload = plan.reload, lines = {}, blocked = {}, plan = plan }
    for _, b in ipairs(plan.blocked or {}) do
        out.blocked[#out.blocked + 1] = (b.adapter and (ADAPTER[b.adapter] or b.adapter) .. ": " or "") .. Explain(b.code)
    end
    for _, id in ipairs(plan.order or {}) do
        local part = plan.parts[id]
        for _, act in ipairs(part.blocked and {} or part.actions) do
            local who = ADAPTER[id] or id
            if act.kind == "values" then
                out.lines[#out.lines + 1] = ("%s: the %d %s the update changed in %s go back to what %s before it."):format(who, act.n, Plural(act.n, "setting", "settings"), Quote(act.target), Plural(act.n, "it was", "they were"))
            elseif act.kind == "switch" then
                out.lines[#out.lines + 1] = ("%s: %s is in use again."):format(who, Quote(act.to))
            elseif act.kind == "delete" then
                out.lines[#out.lines + 1] = ("%s: the profile the update made, %s, is removed. Changes you made in it since go with it."):format(who, Quote(act.name))
            elseif act.kind == "rename" then
                out.lines[#out.lines + 1] = ("%s: %s, kept from before the update, gets its name back: %s."):format(who, Quote(act.from), Quote(act.to))
            end
        end
    end
    if plan.reload then out.lines[#out.lines + 1] = "EllesmereUI finishes it at a reload that you start." end
    return out
end

function M.UndoConfirmText()
    local up = M.UndoPlan()
    local lines = { "Undo the last update?", "" }
    for _, l in ipairs(up.lines) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "This goes back to just before the update, not to before your first install (that is Restore). Nothing reloads by itself."
    return table.concat(lines, "\n"), up
end

-- Undoes exactly the plan that was shown. Returns true, result | false, code, extra.
function M.Undo(key)
    if not session then return false, "closed" end
    if InCombat() then return false, "combat" end
    local ok, result, extra = LY.Undo(key)
    session.check = nil
    if not ok then return false, result, extra end
    session.undoResult = result
    session.step = M.RESULT
    return true, result
end

-- Keeps the update for good: the copy kept for Undo this update is removed. Returns true | false, code.
function M.ForgetUpdate()
    if not session then return false, "closed" end
    local ok, code = LY.ForgetUpdate()
    session.check = nil
    return ok, code
end

-- Finishes the setup (Keep this setup): the way back is forgotten, management goes on (LY.Finish). Returns true | false, code.
function M.Keep()
    if not session then return false end
    local done, code = LY.Finish()
    if done then session.restored = false end
    session.check = nil
    return done, code
end

-- Stops managing (and forgets an unreadable record): nothing installed changes; later updates compare nothing (LY.Detach).
function M.StopManaging()
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
