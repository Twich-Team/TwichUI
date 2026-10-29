-- TwichUI Layout Setup: the authoring workspace's model (docs/layouts/publishing.md)
-- For the person who makes a layout, not the person who installs one. No frames here: the window (AuthorWindow.lua) draws
-- what this says and calls what it offers, so every rule can be tested without a screen.
--
-- The workflow, each step a function and none of them writing anywhere but the workspace's own session:
--   1. Begin()              a session; SetBase(key) the package to start from (the one included, or one this player published);
--                           SetVariant(id) the layout being edited
--   2. SetSource(adapter, name)   which EllesmereUI profile and which TwichUI profile to capture. They are only READ: a profile
--                           is never written, switched or renamed by anything here
--   3. Capture()            reads them through the adapters' allowlists (LY.Capture, the code the offline tool runs), scans the
--                           result for names of the account's characters, links and the like, and builds the changes
--   4. Items()              the structured diff against the starting package: what changed, was added, or was removed, each
--                           with its old and new value in words. SetInclude(unit, bool); SetTarget(unit, "variant" | "base")
--                           keeps a change in the layout being edited, or promotes it to the shared base; Effects(unit) says
--                           what either choice does to EVERY layout of the package
--   5. Check()              builds the draft and checks it as a recipient will: the package, both layouts resolved, the media it
--                           points at, the personal-data scan, the version
--   6. Publish(done)        makes the immutable snapshot (Pub.Build, Store.Seal) and keeps it in the published list
--   7. Send(name)           through the same sharing transport as a setup (Share.lua SendLayout)
-- Beside steps 2 to 4, the package's TwichUI helper presets are edited as a draft of their own (AuthorPresets.lua), written into
-- the package by Draft(). ExportText(entry) gives a published package as text to copy out for bundling it with TwichUI.
-- Nothing is published or sent without the caller asking, nothing is sent to anyone but the name given, and the draft is
-- rebuilt from the items every time: editing afterwards cannot change what was already published.

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local Pub, Store, Capture = LY.Pub, LY.Store, LY.Capture
local A = {}
WZ.Author = A

local session   -- nil while the workspace is closed

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Short(s) return tostring(s) end
local function Eui() return rawget(_G, "EllesmereUI") end
local EA, TA = LY.EllesmereAdapter, LY.TwichUIAdapter

A.MAX_ITEMS = 600

---------------------------------------------------------------------------
-- Sessions and starting packages
---------------------------------------------------------------------------
function A.Active() return session ~= nil end
function A.Session() return session end

-- The packages that can be started from: the one included with TwichUI, and the ones this player published.
function A.Bases()
    local out = {}
    local pkg = LY.ADVENTURE_PACKAGE
    if pkg then out[1] = { key = "bundled", title = pkg.title or pkg.id, revision = pkg.revision, kind = "bundled" } end
    for i, e in ipairs(Store.List("published")) do
        out[#out + 1] = { key = "published:" .. e.hash, title = e.title or e.id, revision = e.revision, kind = "published", entry = e }
    end
    return out
end

local function Highest(id)
    local n = 0
    for _, e in ipairs(Store.List("published")) do if e.id == id and e.revision > n then n = e.revision end end
    return n
end

local function Release(base)
    local rel = { id = base.id, title = base.title or base.id, publisher = nil, notes = nil }
    rel.revision = math.max(base.revision, Highest(base.id)) + 1
    return rel
end

local function UseBase(s, pkg, key)
    s.basePkg, s.baseKey = pkg, key
    local variants = {}
    for id in pairs(pkg.layers.variants) do variants[#variants + 1] = id end
    table.sort(variants)
    s.variants, s.variant = variants, variants[1]
    s.release = Release(pkg)
    s.capture, s.items, s.itemBy, s.report, s.fixes, s.captureError, s.fixList = nil, nil, nil, nil, {}, nil, nil
    WZ.AuthorPresets.Init(s)   -- the package's TwichUI presets, as a draft of their own (AuthorPresets.lua)
end

function A.Begin()
    local pkg = LY.ADVENTURE_PACKAGE
    if not pkg then return nil, "no-package" end
    session = { eui = nil, twichui = nil }
    UseBase(session, pkg, "bundled")
    local E = Eui()
    if type(E) == "table" and type(E.GetActiveProfileName) == "function" then
        local ok, name = pcall(E.GetActiveProfileName)
        if ok and type(name) == "string" then session.eui = name end
    end
    session.twichui = R.Profiles and R.Profiles.Current() or nil
    return session
end

function A.End() session = nil end

-- Chooses the package to start from. A published one is unpacked first (a few frames); done(ok, code) when it is ready.
function A.SetBase(key, done)
    local s = session
    if not s then return false, "closed" end
    if key == "bundled" then
        UseBase(s, LY.ADVENTURE_PACKAGE, "bundled")
        return true
    end
    for _, b in ipairs(A.Bases()) do
        if b.key == key and b.entry then
            Store.Open(b.entry, function(env)
                if session ~= s then return end
                UseBase(s, env.package, key)
                if done then done(true) end
            end, function(code)
                if done and session == s then done(false, code) end
            end)
            return true
        end
    end
    return false, "unknown-base"
end

function A.Variants()
    local s = session
    local out = {}
    if not s then return out end
    for _, id in ipairs(s.variants) do out[#out + 1] = { id = id, title = Pub.TitleCase(id) } end
    return out
end

function A.SetVariant(id)
    local s = session
    if not s or not s.basePkg.layers.variants[id] then return false end
    if s.variant == id then return true end
    s.variant = id
    s.report = nil
    if s.capture then A.BuildItems() end   -- the differences are against this layout: worked out again
    return true
end

---------------------------------------------------------------------------
-- The sources: which profiles are read
---------------------------------------------------------------------------
function A.EuiProfiles()
    local E = Eui()
    local out = {}
    if type(E) ~= "table" or type(E.GetProfilesDB) ~= "function" then return out end
    local ok, db = pcall(E.GetProfilesDB)
    if not ok or type(db) ~= "table" or type(db.profiles) ~= "table" then return out end
    for name, p in pairs(db.profiles) do if type(name) == "string" and type(p) == "table" then out[#out + 1] = name end end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

function A.TwichProfiles() return R.Profiles and R.Profiles.List() or {} end

function A.SetSource(adapter, name)
    local s = session
    if not s or (adapter ~= "eui" and adapter ~= "twichui") then return false end
    s[adapter] = name
    s.capture, s.items, s.itemBy, s.report = nil, nil, nil, nil   -- what was captured came from the other profile
    return true
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------
local function EuiProfile(name)
    local E = Eui()
    if type(E) ~= "table" or type(E.GetProfilesDB) ~= "function" then return nil end
    local ok, db = pcall(E.GetProfilesDB)
    local p = ok and type(db) == "table" and type(db.profiles) == "table" and db.profiles[name]
    return type(p) == "table" and p or nil
end

-- A TwichUI profile's table, to read: the one in use is TwichUIDB itself, a stored one TwichUIDB.profiles[name]. Never written.
local function TwichSlot(name)
    if not R.Profiles or type(TwichUIDB) ~= "table" then return nil end
    if name == R.Profiles.Current() then return TwichUIDB end
    local p = type(TwichUIDB.profiles) == "table" and TwichUIDB.profiles[name]
    return type(p) == "table" and p or nil
end
A.TwichSlot = TwichSlot

-- Reads the named profiles. Returns true | false, code ("no-source", "no-eui-profile", "no-twichui-profile", "personal").
function A.Capture()
    local s = session
    if not s then return false, "closed" end
    local prof, slot
    if s.eui then
        prof = EuiProfile(s.eui)
        if not prof then return false, "no-eui-profile" end
    end
    if s.twichui then
        slot = TwichSlot(s.twichui)
        if not slot then return false, "no-twichui-profile" end
    end
    if not prof and not slot then return false, "no-source" end
    local t0 = R.Perf.on and R.Perf.Start("layouts.capture")
    local cap, rep = Capture.Read(prof, slot)
    local names, realms = Capture.KnownNames()
    local found, where = Capture.Scan(cap, names, realms)
    local bad = 0
    for _, n in pairs(found) do bad = bad + n end
    if bad > 0 then
        -- nothing is kept: a capture with someone's name in it is never held, shown or published
        s.capture, s.items, s.itemBy, s.captureError = nil, nil, nil, "personal"
        s.scan = { found = found, where = where }
        if t0 then R.Perf.Stop(t0) end
        return false, "personal"
    end
    local E = Eui()
    s.capture = { cap = cap, report = rep, units = Capture.Units(cap),
        euiVersion = prof and R.Ellesmere and R.Ellesmere.Version() or nil,
        client = (prof and type(E) == "table" and E.IS_FOREVER ~= true) and "other" or "forever" }
    s.captureError, s.scan = nil, { found = found, where = {} }
    A.BuildItems()
    if t0 then R.Perf.Stop(t0) end
    return true
end

---------------------------------------------------------------------------
-- The structured diff
---------------------------------------------------------------------------
local function Leaves(v, out, limit)
    if type(v) == "table" then
        for _, x in pairs(v) do
            Leaves(x, out, limit)
            if out.n > limit then return end
        end
    else out.n = out.n + 1 end
end

local function Differ(a, b, depth)
    if depth > 14 then return 1 end
    if type(a) ~= "table" or type(b) ~= "table" then return LY.Same(a, b) and 0 or 1 end
    local n = 0
    for k, v in pairs(a) do n = n + Differ(v, b[k], depth + 1) end
    for k, v in pairs(b) do if a[k] == nil then n = n + Differ(nil, v, depth + 1) end end
    return n
end

local function Plural(n, one, many) return n == 1 and one or many end

-- a value that reads as one line (a number, a word, a position), as opposed to a module's whole settings
local function Small(v) return v == nil or v == LY.DEFAULT or type(v) ~= "table" or type(v.x) == "number" end

local function Describe(adapter, unit, old, new)
    local A_ = LY.ADAPTERS[adapter]
    if not (Small(old) and Small(new)) then
        if old ~= nil and new ~= nil then
            local n = Differ(old, new, 0)
            return ("%d %s differ"):format(n, Plural(n, "value", "values"))
        end
        local c = { n = 0 }
        Leaves(old ~= nil and old or new, c, 5000)
        if new ~= nil then return ("new, %d %s"):format(c.n, Plural(c.n, "value", "values")) end
        return ("dropped, %d %s"):format(c.n, Plural(c.n, "value", "values"))
    end
    local function Show(v) return v == nil and "(not set)" or A_.Show(v) end
    return Show(old) .. " → " .. Show(new)
end

-- The layers of a package as unit maps, and where each unit lives.
local function View(pkg)
    local ok, problems, checked = LY.Validate(pkg)
    if not ok then return nil, problems end
    local v = { checked = checked, base = {}, variants = {}, owned = {} }
    for adapter, f in pairs(checked.layers.base) do for u, val in pairs(f.units) do v.base[u] = { adapter = adapter, value = val } end end
    for _, id in ipairs(checked.variants) do
        v.variants[id] = {}
        for adapter, f in pairs(checked.layers.variants[id]) do for u, val in pairs(f.units) do v.variants[id][u] = { adapter = adapter, value = val } end end
    end
    -- what a wizard choice writes is the player's to pick, not something a capture can change
    for cid, ch in pairs(checked.choices and checked.choices.by or {}) do
        for _, o in pairs(ch.options) do
            for _, f in pairs(o.frags) do for u in pairs(f.units) do v.owned[u] = cid end end
        end
    end
    return v
end

-- The value a layout gets for a unit, and where it comes from ("variant", "base" or nil).
local function Effective(view, variant, unit)
    local own = view.variants[variant] and view.variants[variant][unit]
    if own and own.value ~= LY.REMOVE then return own.value, "variant" end
    local b = view.base[unit]
    if b and b.value ~= LY.REMOVE then return b.value, "base" end
    return nil, nil
end

function A.BuildItems()
    local s = session
    local view = View(s.basePkg)
    s.view = view
    local items, by = {}, {}
    local function Add(it)
        if #items >= A.MAX_ITEMS then return end
        items[#items + 1] = it
        by[it.id] = it
    end
    local previous = s.itemBy or {}
    s.skipped = {}
    for _, adapter in ipairs(LY.ADAPTER_ORDER) do
        local got = s.capture.units[adapter]
        if got then
            local seen = {}
            for unit, new in pairs(got.units) do
                seen[unit] = true
                if view.owned[unit] then
                    s.skipped[#s.skipped + 1] = { unit = unit, why = "the " .. view.owned[unit] .. " choice sets it" }
                else
                    local cur, lives = Effective(view, s.variant, unit)
                    if cur == nil or not LY.Same(cur, new) then
                        local kind = cur == nil and "added" or "changed"
                        Add({ id = unit, adapter = adapter, label = LY.ADAPTERS[adapter].Label(unit), kind = kind, lives = lives,
                            old = cur, new = new, text = Describe(adapter, unit, cur, new) })
                    end
                end
            end
            -- what the layout names and the captured profile doesn't
            local function Gone(unit)
                if seen[unit] or view.owned[unit] then return end
                if Capture.Locate(unit) ~= adapter then return end
                local cur, lives = Effective(view, s.variant, unit)
                if cur == nil or cur == LY.DEFAULT then return end   -- not named, or already reset to the default
                local f = adapter == "twichui" and TA.FieldOf(unit) or nil
                if f then
                    -- a TwichUI setting the profile leaves at its default. That alone doesn't say what the author wants for
                    -- the players who have the layout (RH-1 A5): left out unless the author includes it, then "Reset to
                    -- default" (players' value goes back to TwichUI's default) or "Stop managing" (players keep theirs).
                    if f.default ~= nil and not LY.Same(cur, f.default) then
                        Add({ id = unit, adapter = adapter, label = LY.ADAPTERS[adapter].Label(unit), kind = "default", lives = lives,
                            old = cur, new = LY.DEFAULT, how = "reset", canReset = true,
                            text = Describe(adapter, unit, cur, LY.DEFAULT) })
                    end
                else
                    Add({ id = unit, adapter = adapter, label = LY.ADAPTERS[adapter].Label(unit), kind = "removed", lives = lives,
                        old = cur, new = nil, text = Describe(adapter, unit, cur, nil) })
                end
            end
            local done = {}
            for u, e in pairs(view.base) do if e.adapter == adapter then done[u] = true Gone(u) end end
            for u, e in pairs(view.variants[s.variant] or {}) do if e.adapter == adapter and not done[u] then Gone(u) end end
        end
    end
    table.sort(items, function(a, b)
        if a.adapter ~= b.adapter then return a.adapter < b.adapter end
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    for _, it in ipairs(items) do
        it.rootOnly = it.id:find("^ellesmereui:root%.") ~= nil
        -- a layout can only stop naming something the base names by changing the base
        it.baseOnly = it.rootOnly or ((it.kind == "removed" or it.kind == "default") and it.lives == "base")
        it.include = it.kind ~= "removed" and it.kind ~= "default"
        it.to = it.baseOnly and "base" or "variant"
        local was = previous[it.id]
        if was and LY.Same(was.new, it.new) then
            it.include = was.include
            if not it.baseOnly then it.to = was.to end
            if it.canReset and (was.how == "reset" or was.how == "release") then it.how = was.how end
        end
    end
    s.items, s.itemBy = items, by
    s.report = nil
end

function A.Items() return session and session.items or nil end
function A.Skipped() return session and session.skipped or {} end

function A.Counts()
    local out = { changed = 0, added = 0, removed = 0, default = 0, included = 0, shared = 0, own = 0, reset = 0 }
    for _, it in ipairs(session and session.items or {}) do
        out[it.kind] = out[it.kind] + 1
        if it.include then
            out.included = out.included + 1
            if it.to == "base" then out.shared = out.shared + 1 else out.own = out.own + 1 end
            if it.kind == "default" and it.how == "reset" then out.reset = out.reset + 1 end
        end
    end
    return out
end

-- For a setting the profile leaves at its default ("default" items): "reset" (players who have the layout get TwichUI's
-- default) or "release" (the layout stops naming it; players keep what they have). Returns true | false, code.
function A.SetHow(unit, how)
    local it = session and session.itemBy and session.itemBy[unit]
    if not it or not it.canReset then return false, "unknown" end
    if how ~= "reset" and how ~= "release" then return false, "unknown" end
    it.how = how
    session.report = nil
    return true
end

function A.SetInclude(unit, on)
    local it = session and session.itemBy and session.itemBy[unit]
    if not it then return false end
    it.include = on and true or false
    session.report = nil
    return true
end

-- Returns true | false, code ("base-only": the change can only be made in the shared base).
function A.SetTarget(unit, to)
    local it = session and session.itemBy and session.itemBy[unit]
    if not it or (to ~= "variant" and to ~= "base") then return false, "unknown" end
    if to == "variant" and it.baseOnly then return false, "base-only" end
    it.to = to
    session.report = nil
    return true
end

-- What putting the change in `to` ("variant" | "base") does to every layout of the package:
-- { { variant, title, change = "gets" | "keeps", from, to, why } }. Read only.
function A.Effects(unit, to)
    local s = session
    local it = s and s.itemBy and s.itemBy[unit]
    if not it then return nil end
    to = to or it.to
    local out = {}
    for _, id in ipairs(s.variants) do
        local before = Effective(s.view, id, unit)
        local after
        local own = s.view.variants[id] and s.view.variants[id][unit]
        own = own and own.value ~= LY.REMOVE
        if id == s.variant then
            after = it.new
        elseif to == "base" and not own then
            after = it.new   -- inherits the base: it gets the new value
        else
            after = before   -- has its own value, or the change isn't in the base
        end
        local e = { variant = id, title = Pub.TitleCase(id), from = before, to = after }
        if LY.Same(before, after) then
            e.change = "keeps"
            e.why = (id ~= s.variant and own) and "it has its own value" or (id ~= s.variant and "the change is not shared" or "no change")
        else
            e.change = "gets"
            e.why = id == s.variant and "this layout" or "it uses the shared value"
        end
        e.text = Describe(it.adapter, unit, before, after)
        out[#out + 1] = e
    end
    return out
end

---------------------------------------------------------------------------
-- The release: what the package is called and which version it is
---------------------------------------------------------------------------
function A.Release() return session and session.release or nil end

-- field: id, title, revision, notes, publisher. Returns true | false, code.
function A.SetRelease(field, value)
    local s = session
    if not s then return false, "closed" end
    local r = s.release
    if field == "id" then
        if not LY.IsId(value) then return false, "bad-id" end
        r.id = value
        r.revision = value == s.basePkg.id and (math.max(s.basePkg.revision, Highest(value)) + 1) or (Highest(value) + 1)
    elseif field == "title" then
        if not LY.Plain(value, 80) then return false, "bad-title" end
        r.title = value
    elseif field == "revision" then
        value = tonumber(value)
        if not value or value % 1 ~= 0 or value < 1 or value > 1e6 then return false, "bad-revision" end
        r.revision = value
    elseif field == "notes" then
        if value == "" or value == nil then r.notes = nil
        elseif not Pub.Notes(value) then return false, "bad-notes"
        else r.notes = value end
    elseif field == "publisher" then
        if value == "" or value == nil then r.publisher = nil
        elseif not LY.Plain(value, Pub.LIMITS.publisher) then return false, "bad-publisher"
        else r.publisher = value end
    else
        return false, "unknown"
    end
    s.report = nil
    return true
end

---------------------------------------------------------------------------
-- Media: references that point at another addon's files
---------------------------------------------------------------------------
-- { { path, replacement } }: every file the draft, as last checked, points at that belongs to another addon, with TwichUI's own
-- copy when it has one (an author's private font folder usually holds a file TwichUI bundles). It is read from the draft that
-- Check built, so it follows the changes included; empty until a check has been made.
function A.MediaFixes()
    local s = session
    return s and s.fixList or {}
end

function A.FixMedia(path)
    local s = session
    if not s then return false end
    local rep = Pub.Substitute(path)
    if not rep then return false end
    s.fixes[path] = rep
    s.report = nil
    for i = #(s.fixList or {}), 1, -1 do if s.fixList[i].path == path then table.remove(s.fixList, i) end end
    return true
end

---------------------------------------------------------------------------
-- The draft: the starting package with the included changes in their layers, rebuilt every time
---------------------------------------------------------------------------
local function Replace(v, map)
    if type(v) == "string" then return map[v] or v end
    if type(v) == "table" then
        for k, x in pairs(v) do
            if type(x) == "string" or type(x) == "table" then v[k] = Replace(x, map) end
        end
    end
    return v
end

-- rough: true skips the release metadata (for looking at the media only)
function A.Draft(rough)
    local s = session
    local pkg = LY.Copy(s.basePkg)
    pkg.dev = nil
    local base, mine = pkg.layers.base, pkg.layers.variants[s.variant]
    local list = {}
    for _, it in ipairs(s.items or {}) do if it.include then list[#list + 1] = it end end
    table.sort(list, function(a, b) return a.id < b.id end)
    local resets = false
    for _, it in ipairs(list) do
        if it.kind == "removed" or (it.kind == "default" and it.how == "release") then
            if it.to == "base" then Capture.Forget(base, it.id) end
            Capture.Forget(mine, it.id)
        elseif it.kind == "default" then
            -- reset to TwichUI's default, in the layer that named it (format 4)
            if it.to == "base" then Capture.Reset(base, it.id) Capture.Forget(mine, it.id)
            else Capture.Reset(mine, it.id) end
            resets = true
        elseif it.to == "base" then
            Capture.Put(base, it.id, it.new)
            Capture.Clear(mine, it.id)   -- this layout takes the shared value
        else
            Capture.Put(mine, it.id, it.new)
        end
    end
    if resets and (pkg.format or 0) < 4 then pkg.format = 4 end   -- a reset needs format 4 (an older TwichUI refuses it)
    WZ.AuthorPresets.Apply(pkg)   -- the TwichUI presets as the draft has them (format 6 once they were edited)
    if next(s.fixes) then Replace(pkg, s.fixes) end
    if not rough then
        local r = s.release
        pkg.id, pkg.revision, pkg.title = r.id, r.revision, r.title
        pkg.made = os.date and os.date("%Y-%m-%d") or pkg.made
        pkg.source = "Captured in game" .. (s.capture and s.capture.euiVersion and (" with EllesmereUI " .. s.capture.euiVersion) or "")
        if s.capture and s.capture.euiVersion and type(pkg.requires) == "table" and type(pkg.requires.ellesmereui) == "table" then
            pkg.requires.ellesmereui.tested = s.capture.euiVersion
        end
    end
    return pkg
end

---------------------------------------------------------------------------
-- Checking the draft as a recipient will
---------------------------------------------------------------------------
-- Returns the report: { ok, blockers = { text }, warnings = { text }, variants = { { id, title, ok, units, fits, lines } },
--   media = { { path, kind, source, status } }, changes = Counts() }. Cached until something changes.
function A.Check()
    local s = session
    if not s then return nil end
    if s.report then return s.report end
    local rep = { blockers = {}, warnings = {}, variants = {}, media = {}, changes = A.Counts() }
    local function Block(t) rep.blockers[#rep.blockers + 1] = t end
    local function Warn(t) rep.warnings[#rep.warnings + 1] = t end
    s.report = rep
    local pkg = A.Draft()
    local presets = WZ.AuthorPresets.CheckLines()
    local P = s.presets
    if rep.changes.included == 0 and not s.capture and not (P and P.changed) then Warn("Nothing has been captured or changed, so this republishes the starting package as it is.") end
    for _, t in ipairs(presets.blockers) do Block(t) end
    for _, t in ipairs(presets.notes) do Warn(t) end
    -- the package, held to what a recipient holds it to
    local ok, problems, checked = Pub.Strict(pkg)
    if not ok then
        for _, line in ipairs(Pub.Explain(problems, 4)) do Block("The package " .. line .. ".") end
    end
    -- nothing personal
    local names, realms = Capture.KnownNames()
    local found, where = Capture.Scan(pkg, names, realms)
    for kind, n in pairs(found) do
        if n > 0 then
            Block(("The package holds %d %s that looks personal (%s)%s."):format(n, Plural(n, "string", "strings"), kind,
                where[1] and (", for example " .. where[1]:gsub("^%a+ at capture%.", "at ")) or ""))
        end
    end
    -- the version
    local r = s.release
    if r.revision <= Highest(r.id) then Block(("Revision %d of this package was already published. Use a higher number."):format(r.revision)) end
    if r.id == s.basePkg.id and r.revision <= s.basePkg.revision then Block(("It starts from revision %d; the new one has to be higher."):format(s.basePkg.revision)) end
    -- media
    if checked then
        local refs = Pub.Refs(pkg)
        s.fixList = {}
        for _, r in ipairs(refs) do
            if r.source == "foreign" then s.fixList[#s.fixList + 1] = { path = r.path, replacement = Pub.Substitute(r.path) } end
        end
        rep.media = Pub.Resolve(refs)
        local unverified = 0
        for _, m in ipairs(rep.media) do
            local file = m.path:match("([^\\/]+)$") or m.path
            if m.status == "foreign" then Block(("It points at %s, which belongs to another addon and can't be sent."):format(file))
            elseif m.status == "unsafe" then Block(("It points at %s, which is outside the game's folders."):format(file))
            elseif m.status == "missing" then Block(("It points at %s, which is not installed here."):format(file))
            elseif m.status == "unverified" then unverified = unverified + 1 end
        end
        if unverified > 0 then Warn(("%d %s can't be looked up without drawing or playing them, so %s taken on trust."):format(
            unverified, Plural(unverified, "file", "files"), Plural(unverified, "it is", "they are"))) end
    end
    -- both layouts, resolved
    if checked then
        local geo = pkg.geometry
        local canvas = geo and geo.canvas
        local screens = {}
        if canvas then screens[#screens + 1] = { name = "its own canvas", w = canvas.w, h = canvas.h } end
        local live = LY.Geometry.Live()
        if live then screens[#screens + 1] = { name = "this screen", w = live.w, h = live.h } end
        for _, id in ipairs(checked.variants) do
            local v = { id = id, title = Pub.TitleCase(id), ok = true, lines = {}, fits = true }
            for _, sc in ipairs(screens) do
                local good, resolved = LY.Resolve(pkg, id, { screen = { w = sc.w, h = sc.h } })
                if not good then
                    v.ok = false
                    Block(("The %s layout can't be resolved for %s."):format(v.title, sc.name))
                else
                    local n = 0
                    for _, c in pairs(resolved.adapters) do n = n + #c.list end
                    v.units = n
                    if resolved.geometry and not resolved.geometry.fits then
                        v.fits = false
                        Warn(("The %s layout doesn't fully fit %s."):format(v.title, sc.name))
                    end
                end
            end
            rep.variants[#rep.variants + 1] = v
        end
    end
    if s.capture and s.capture.client == "other" then
        Warn("These settings were captured on another game client, not WoW: Forever. The package says so, and recipients are told.")
    end
    rep.ok = #rep.blockers == 0
    return rep
end

---------------------------------------------------------------------------
-- Publishing and sending
---------------------------------------------------------------------------
-- Makes the snapshot and keeps it. done(true, entry) | done(false, code). Nothing is sent. One at a time.
function A.Publish(done)
    local s = session
    if not s then return false, "closed" end
    if s.publishing then return false, "busy" end
    local rep = A.Check()
    if not rep.ok then return false, "blocked" end
    local r = s.release
    local env, problems = Pub.Build(A.Draft(), { notes = r.notes, publisher = r.publisher, now = time(), client = s.capture and s.capture.client or "forever",
        baseRevision = r.id == s.basePkg.id and s.basePkg.revision or nil })
    if not env then return false, "invalid", problems end
    s.publishing = true
    Store.Seal(env, function(entry)
        s.publishing = nil
        local added, why = Store.Add("published", entry)
        if not added then if done then done(false, why) end return end
        s.published = entry
        if s.presets then s.presets.publishedGen = s.presets.gen end   -- the presets' draft is in a publication now
        r.revision = r.revision + 1   -- the next one is already the next number
        s.report = nil
        if done then done(true, entry) end
    end, function(code)
        s.publishing = nil
        if done then done(false, code) end
    end)
    return true
end

function A.Published() return Store.List("published") end

-- A published package as one line of text to copy out of the game, for the developer's bundling import
-- (tools/update_bundled_layout.sh --from-published --text FILE; docs/layouts/presets.md). It is the stored entry's own bytes (the
-- packed block, printable), with its id, revision, fingerprint and size in front so the import can check it is what was approved:
--   !TwichUI-layout!1!<id>!<revision>!<fingerprint>!<size>!<printable block>
-- Nothing is packed again: what is copied is exactly what was published.
A.EXPORT_TAG = "!TwichUI-layout!1!"
function A.ExportText(entry)
    if type(entry) ~= "table" or type(entry.blob) ~= "string" then return nil end
    return ("%s%s!%d!%s!%d!%s"):format(A.EXPORT_TAG, entry.id, entry.revision, entry.hash, entry.size, entry.blob)
end

-- Whether closing the workspace would lose work: a TwichUI preset edit not saved to the draft, or a preset draft not published.
function A.Dirty() return session ~= nil and WZ.AuthorPresets.Dirty() end

function A.RemovePublished(entry)
    local s = session
    local removed = Store.Remove("published", entry)
    if removed and s and s.published == entry then s.published = nil end
    if s then s.report = nil end
    return removed
end

-- Sends a published package (the one just published, unless entry is given) to a named player. Returns true | false, reason.
function A.Send(name, entry, selfTest)
    local s = session
    entry = entry or (s and s.published)
    if not entry then return false, "Publish first." end
    return R.Share:SendLayout(name, entry, selfTest)
end

R.Perf.Gauge("layoutwizard.author", { label = "Layout authoring workspace: items held (0 while closed)", unit = "count", kind = "state",
    group = "layouts", read = function() return session and session.items and #session.items or 0 end })
