-- TwichUI Layouts: the install record, TwichUIDB.layouts.install (architecture.md §8)
-- What an install needs to be finished, checked or undone after a reload, and nothing more: which package and variant,
-- the state, each adapter's step, the snapshot (the profiles in use before, the install's own profile names, and
-- fingerprints of the values it replaced), and fingerprints of what verification expects to read back. No copies of
-- anyone's settings, no names of other profiles, no frames, timers or callbacks. Bounded by the units a package may name.
--
--   { v = 1, package, revision, variant, char, state, at, key, reload,
--     picks = { [choice id] = option id },                               -- what the wizard asked (optional; at most MAX_PICKS)
--     steps = { { adapter, state, code, rollback, reload } },          -- in apply order
--     snapshot = { [adapter] = part }, expect = { [adapter] = { [unit] = fingerprint } }, inputs = { [adapter] = fingerprint },
--     verify = { state, at, diffs = { { adapter, unit, code } }, unverifiable },
--     restore = { at, steps = { ... } } }
--
-- States: applying (written before the first change; found at a load, it means the client stopped mid-way: interrupted)
--   -> applied (waits for the reload, then is checked) -> verified | mismatch;  partial (a step failed after another
--   changed something);  restoring (waits for the reload) -> the record is removed once the restore checks out, or
--   restore-partial. A record whose version is newer than this one is never changed.
--
-- Updates (updates.md; architecture.md §16) add, all optional:
--   track = { [adapter] = { [unit] = { p, k, o } } }   what the baseline takes from this install once it checks out:
--                                                      the package's side (p), kept the recipient's (k), theirs (o)
--   update = { at, from, baseline, twichui, ellesmereui }   the state before this update, for "Undo this update":
--     from      the record as it was (without its snapshot, which an update never replaces)
--     baseline  the baseline as it was (nil: there was none)
--     twichui   { profile = in use before, target, values = { [unit] = { v = the stored value } | {} (not stored) } }
--     ellesmereui { active = in use before, target, backup = the name the install's old profile was renamed to }
--   States undoing (an undo waits for the reload) and undo-partial (it did not fully check out).
--
-- The baseline (TwichUIDB.layouts.baseline) is the managed configuration the last install applied and then read back:
--   { v = 1, package, char, at, parts = { [adapter] = { revision, variant, picks, key, merge, schema, screen, at,
--     units = { [unit] = { p, l, s, o, k } } } } }
--   p: the package's normalized value; l: what was read back (only where it differs from p); s: "x" stored, "d" the
--   addon's default (nothing stored), "a" not there; o: the recipient's own (not managed); k: the recipient's value was
--   kept. Fingerprints and positions only, never copies. A part is written only for an adapter whose check matched,
--   and never because an install started.

local R = TwichUI
local LY = R.Layouts
local J = {}
LY.Journal = J

J.VERSION = 1
J.BASELINE_VERSION = 1
J.STATES = LY.Set({ "applying", "applied", "verified", "mismatch", "partial", "interrupted", "restoring", "restore-partial",
    "undoing", "undo-partial" })
J.STEP_STATES = LY.Set({ "pending", "done", "skipped", "failed", "partial", "not-run", "kept" })
J.MAX_DIFFS = 8
J.MAX_STEPS = 4
J.MAX_PICKS = 8
J.MAX_UPDATE = 256 * 1024   -- canonical text of the state before an update (fingerprints and a few hundred small values)
J.MAX_VALUE = 272           -- one normalized value in the baseline: "=" and LY.VALUE_MAX of canonical text, or a fingerprint

local function Root(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local l = TwichUIDB.layouts
    if type(l) ~= "table" then
        if not create then return nil end
        l = {}
        TwichUIDB.layouts = l
    end
    return l
end

local function Code(s) return s == nil or (type(s) == "string" and #s <= 48 and s:match("^[%w%-]+$") ~= nil) end
local function Count(n) return type(n) == "number" and n == n and n >= 0 and n % 1 == 0 and n < 2 ^ 53 end

local function CleanSteps(steps)
    if type(steps) ~= "table" or #steps > J.MAX_STEPS then return false end
    for k in pairs(steps) do if type(k) ~= "number" or k < 1 or k > #steps then return false end end
    for _, s in ipairs(steps) do
        if type(s) ~= "table" or not LY.ADAPTERS[s.adapter] or not J.STEP_STATES[s.state] then return false end
        if not (Code(s.code) and (s.rollback == nil or s.rollback == "clean" or s.rollback == "partial" or s.rollback == "unknown")) then return false end
        if s.reload ~= nil and type(s.reload) ~= "boolean" then return false end
    end
    return true
end

local function CleanFingerprints(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for unit, fp in pairs(t) do
        n = n + 1
        if n > LY.MAX_EXPECT then return false end
        if type(unit) ~= "string" or #unit > 128 or type(fp) ~= "string" or #fp > LY.FINGERPRINT_KEEP + 8 then return false end
    end
    return true
end

local function CleanPicks(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
        n = n + 1
        if n > J.MAX_PICKS or not LY.IsId(k) or not LY.IsId(v) then return false end
    end
    return true
end

-- Whether a snapshot can be used to restore from: { [adapter] = part }, each part's own shape (the adapter's check).
function J.CleanSnapshot(snap)
    if type(snap) ~= "table" or next(snap) == nil then return false, "empty" end
    for id, part in pairs(snap) do
        local a = LY.ADAPTERS[id]
        if not a then return false, "unknown-adapter" end
        if not a.CleanSnapshot(part) then return false, "damaged" end
        if not CleanFingerprints(part.values) then return false, "damaged" end
    end
    return true
end

-- The record, checked: record | nil, why ("damaged", "newer"). Read only; nothing is repaired or removed here.
function J.Clean(j)
    if type(j) ~= "table" then return nil, "damaged" end
    if not Count(j.v) then return nil, "damaged" end
    if j.v > J.VERSION then return nil, "newer" end
    if not (LY.IsId(j.package) and Count(j.revision) and LY.IsId(j.variant) and LY.Plain(j.char, 64)) then return nil, "damaged" end
    if not J.STATES[j.state] or not Count(j.at) or (j.key ~= nil and not LY.Plain(j.key, 96)) then return nil, "damaged" end
    if j.reload ~= nil and type(j.reload) ~= "boolean" then return nil, "damaged" end
    if j.picks ~= nil and not CleanPicks(j.picks) then return nil, "damaged" end
    if not CleanSteps(j.steps) then return nil, "damaged" end
    if not J.CleanSnapshot(j.snapshot) then return nil, "damaged" end
    if type(j.expect) ~= "table" then return nil, "damaged" end
    for id, e in pairs(j.expect) do
        if not LY.ADAPTERS[id] or not CleanFingerprints(e) then return nil, "damaged" end
    end
    if j.inputs ~= nil and not CleanFingerprints(j.inputs) then return nil, "damaged" end
    if j.verify ~= nil then
        local v = j.verify
        if type(v) ~= "table" or not Code(v.state) or type(v.diffs) ~= "table" or #v.diffs > J.MAX_DIFFS then return nil, "damaged" end
    end
    if j.restore ~= nil and (type(j.restore) ~= "table" or not CleanSteps(j.restore.steps)) then return nil, "damaged" end
    if j.track ~= nil and not J.CleanTrack(j.track) then return nil, "damaged" end
    if j.euiBackup ~= nil and not LY.Plain(j.euiBackup, 64) then return nil, "damaged" end
    if j.screen ~= nil and not LY.Plain(j.screen, 40) then return nil, "damaged" end
    if j.update ~= nil and not J.CleanUpdate(j.update) then return nil, "damaged" end
    return j
end

-- { [adapter] = { [unit] = { p, k, o } } }, bounded like the expectations.
function J.CleanTrack(t)
    if type(t) ~= "table" then return false end
    for id, units in pairs(t) do
        if not LY.ADAPTERS[id] or type(units) ~= "table" then return false end
        local n = 0
        for unit, e in pairs(units) do
            n = n + 1
            if n > LY.MAX_EXPECT or type(unit) ~= "string" or #unit > 128 or type(e) ~= "table" then return false end
            for _, k in ipairs({ "p", "a" }) do
                if e[k] ~= nil and (type(e[k]) ~= "string" or #e[k] > J.MAX_VALUE) then return false end
            end
            if (e.k ~= nil and e.k ~= true) or (e.o ~= nil and e.o ~= true) then return false end
        end
    end
    return true
end

-- The state before an update: shape and size only (what it restores is checked again when it is used).
function J.CleanUpdate(u)
    if type(u) ~= "table" or not Count(u.at) then return false end
    local c = LY.Canon(u)
    if not c or #c > J.MAX_UPDATE then return false end
    local f = u.from
    if f == nil then
        -- an update of a layout whose setup was finished (no install record before it): the management record it replaces
        if not J.CleanManaged(u.managed) then return false end
    else
        if type(f) ~= "table" or not J.STATES[f.state] or not Count(f.revision) or not LY.IsId(f.variant) or type(f.expect) ~= "table" then return false end
        if f.picks ~= nil and not CleanPicks(f.picks) then return false end
    end
    if u.baseline ~= nil and not J.CleanBaseline(u.baseline) then return false end
    if u.managed ~= nil and not J.CleanManaged(u.managed) then return false end
    local t = u.twichui
    if t ~= nil and (type(t) ~= "table" or type(t.profile) ~= "string" or type(t.target) ~= "string" or type(t.values) ~= "table") then return false end
    local e = u.ellesmereui
    if e ~= nil and (type(e) ~= "table" or type(e.active) ~= "string" or type(e.target) ~= "string" or (e.backup ~= nil and type(e.backup) ~= "string")) then return false end
    return true
end

---------------------------------------------------------------------------
-- The baseline
---------------------------------------------------------------------------
local ENTRY_KEYS = LY.Set({ "p", "a", "l", "s", "o", "k", "u" })
local STORED = LY.Set({ "x", "d", "a" })

local function CleanEntry(e)
    if type(e) ~= "table" then return false end
    for k in pairs(e) do if not ENTRY_KEYS[k] then return false end end
    for _, k in ipairs({ "p", "a", "l" }) do
        if e[k] ~= nil and (type(e[k]) ~= "string" or #e[k] > J.MAX_VALUE) then return false end
    end
    if e.s ~= nil and not STORED[e.s] then return false end
    return (e.o == nil or e.o == true) and (e.k == nil or e.k == true) and (e.u == nil or e.u == true)
end

-- baseline | nil, why ("damaged", "newer"). Read only.
function J.CleanBaseline(b)
    if type(b) ~= "table" or not Count(b.v) then return nil, "damaged" end
    if b.v > J.BASELINE_VERSION then return nil, "newer" end
    if not (LY.IsId(b.package) and LY.Plain(b.char, 64) and Count(b.at) and type(b.parts) == "table") then return nil, "damaged" end
    for id, part in pairs(b.parts) do
        if not LY.ADAPTERS[id] or type(part) ~= "table" or type(part.units) ~= "table" then return nil, "damaged" end
        if not (Count(part.revision) and LY.IsId(part.variant) and Count(part.merge)) then return nil, "damaged" end
        if part.picks ~= nil and not CleanPicks(part.picks) then return nil, "damaged" end
        for _, k in ipairs({ "schema", "screen", "key" }) do
            if part[k] ~= nil and (type(part[k]) ~= "string" or #part[k] > 160) then return nil, "damaged" end
        end
        local n = 0
        for unit, e in pairs(part.units) do
            n = n + 1
            if n > LY.MAX_EXPECT or type(unit) ~= "string" or #unit > 128 or not CleanEntry(e) then return nil, "damaged" end
        end
    end
    return b
end

-- The baseline in use: baseline | nil (none) | nil, why.
function J.ReadBaseline()
    local root = Root(false)
    local b = root and root.baseline
    if b == nil then return nil end
    return J.CleanBaseline(b)
end

function J.WriteBaseline(b)
    local root = Root(b ~= nil)
    if not root then return end
    root.baseline = b
    if b == nil and next(root) == nil then TwichUIDB.layouts = nil end
end

-- Puts one adapter's part in the baseline after its check matched. The rest of the baseline is left as it was, unless it
-- belongs to another package or character (then it is replaced: it described an install that no longer exists).
function J.CommitBaseline(record, id, units, schema, screen)
    local b = J.ReadBaseline()
    if not b or b.package ~= record.package or b.char ~= record.char then
        b = { v = J.BASELINE_VERSION, package = record.package, char = record.char, parts = {} }
    end
    b.at = time()
    b.parts[id] = { revision = record.revision, variant = record.variant, picks = record.picks and LY.Copy(record.picks) or nil,
        key = record.key, merge = LY.Merge.VERSION, schema = schema, screen = screen, at = b.at, units = units }
    J.WriteBaseline(b)
    return b
end

-- The record in use: record | nil (none) | nil, why (there is one, and it can't be used).
function J.Read()
    local root = Root(false)
    local j = root and root.install
    if j == nil then return nil end
    return J.Clean(j)
end

function J.Exists()
    local root = Root(false)
    return root ~= nil and root.install ~= nil
end

function J.Write(record)
    local root = Root(true)
    if root then root.install = record end
end

-- Two lifecycles (updates.md): the install record (the rollback journal: what Restore and Undo this update put back) ends when
-- an install is restored, or when its setup is finished; the management record and the baseline (which package and layout are
-- installed, which profiles are the install's own, what the last checked install left) last as long as TwichUI manages the
-- layout, and end only when it is restored or the recipient stops managing it.
--
-- Removes the install record only. Changes nothing else.
function J.Clear()
    local root = Root(false)
    if not root then return end
    root.install = nil
    if next(root) == nil then TwichUIDB.layouts = nil end
end

-- Removes the install record, the management record and the baseline (restored, or no longer managed). Changes nothing else.
function J.Forget()
    local root = Root(false)
    if not root then return end
    root.install, root.baseline, root.managed = nil, nil, nil
    if next(root) == nil then TwichUIDB.layouts = nil end
end

---------------------------------------------------------------------------
-- The management record: TwichUIDB.layouts.managed = { v = 1, package, revision, variant, picks, char, at,
--   targets = { [adapter] = the install's own profile name }, home = { [adapter] = the profile in use before the first install } }
-- Written each time an install is checked after its reload; read when there is no install record (the setup was finished).
---------------------------------------------------------------------------
J.MANAGED_VERSION = 1

function J.CleanManaged(m)
    if type(m) ~= "table" or not Count(m.v) or m.v > J.MANAGED_VERSION then return nil, type(m) == "table" and Count(m.v) and "newer" or "damaged" end
    if not (LY.IsId(m.package) and Count(m.revision) and LY.IsId(m.variant) and LY.Plain(m.char, 64) and Count(m.at)) then return nil, "damaged" end
    if m.picks ~= nil and not CleanPicks(m.picks) then return nil, "damaged" end
    for _, k in ipairs({ "targets", "home" }) do
        if type(m[k]) ~= "table" then return nil, "damaged" end
        for id, name in pairs(m[k]) do
            if not LY.ADAPTERS[id] or type(name) ~= "string" or #name > 64 then return nil, "damaged" end
        end
    end
    return m
end

function J.ReadManaged()
    local root = Root(false)
    local m = root and root.managed
    if m == nil then return nil end
    return J.CleanManaged(m)
end

function J.WriteManaged(m)
    local root = Root(m ~= nil)
    if not root then return end
    root.managed = m
    if m == nil and next(root) == nil then TwichUIDB.layouts = nil end
end

-- At most J.MAX_DIFFS of an adapter report's differences, for the record (codes and unit ids only).
function J.Diffs(reports)
    local out = {}
    for _, id in ipairs(LY.SortedKeys(reports)) do
        for _, d in ipairs(reports[id].diffs or {}) do
            if #out >= J.MAX_DIFFS then return out end
            out[#out + 1] = { adapter = id, unit = d.unit, code = d.code }
        end
    end
    return out
end
