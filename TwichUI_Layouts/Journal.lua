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

local R = TwichUI
local LY = R.Layouts
local J = {}
LY.Journal = J

J.VERSION = 1
J.STATES = LY.Set({ "applying", "applied", "verified", "mismatch", "partial", "interrupted", "restoring", "restore-partial" })
J.STEP_STATES = LY.Set({ "pending", "done", "skipped", "failed", "partial", "not-run" })
J.MAX_DIFFS = 8
J.MAX_STEPS = 4
J.MAX_PICKS = 8

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
    return j
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

-- Removes the record (the install is finished with: restored, or detached). Changes nothing else.
function J.Clear()
    local root = Root(false)
    if not root then return end
    root.install = nil
    if next(root) == nil then TwichUIDB.layouts = nil end
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
