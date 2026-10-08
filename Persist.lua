-- TwichUI: saved data, schema and recovery
-- The one place that knows what TwichUI keeps between sessions and how an older or damaged copy is
-- made safe to use. docs/persistence.md describes every saved variable, who owns it and the upgrade paths.
--
-- Versions (separate from the addon's release version, and from each other):
--   TwichUIDB.schema           settings and sharing records, SCHEMA below. Missing = 0 = every release
--                              before schemas existed. Ordered, repeatable steps in STEPS bring it up to date.
--   TwichUIChronicleDB.version the Journey Chronicle, owned by chronicle/Data.lua (CHRONICLE_VERSION).
--   The other roots (restore points, undo backups, your shareable setup) carry no number: they hold
--   other addons' tables as they were saved and are checked for shape on load by the module that owns them.
--
-- Rules every part of this follows:
--   * Missing values are filled in; existing ones, including false, 0 and empty tables, are kept.
--   * Unknown fields are kept. One bad value never resets its neighbours or a whole table.
--   * Features validate their own values (ranges, textures) when they read them and never erase a value
--     they cannot use, so a texture whose media pack is absent today is still chosen when it returns.
--   * Saved data from a NEWER schema is never changed or downgraded: it is set aside for the session and
--     handed back unchanged at logout (see Hold), and the session runs on fresh defaults.
--   * A failed upgrade leaves the saved data exactly as it was and is tried again next load.
--   * Nothing here plays a sound, shows a card, registers a game event for a feature or touches the game.

local R = TwichUI
local P = {}
R.Persist = P

P.SCHEMA = 1
P.CHRONICLE_VERSION = 1

-- Must match Share.lua's SH.TRANSPORTS (a test checks that they do).
local VALID_TRANSPORT = { DIRECT = true, PARTY = true, GUILD = true }

---------------------------------------------------------------------------
-- What happened this load: counts under stable reason codes, never contents.
-- A loss code means something the player stored was reset or set aside; only those earn the one notice.
---------------------------------------------------------------------------
P.CODES = {
    ["defaults-added"] = false,          -- a setting that was missing got its default
    ["schema-invalid"] = false,          -- the stored schema number was unreadable; treated as unversioned
    ["legacy-key-removed"] = false,      -- a key an earlier build wrote and nothing reads any more
    ["held-recovered"] = false,          -- a set-aside copy was found in the saved file and put back
    ["list-entry-dropped"] = false,      -- an entry of a list that is rebuilt (the last search) or re-asked (trusted senders)
    ["pack-field-reset"] = false,        -- a label or number on a received setup that was not readable
    ["apply-entry-rejected"] = false,    -- a table a setup or backup named was refused when applying
    ["chronicle-entry-set-aside"] = false, -- a Chronicle entry this version does not know, kept unchanged
    ["chronicle-entry-repaired"] = false,  -- a Chronicle entry kept after fixing its id, title or date
    ["chronicle-trimmed"] = false,       -- automatic Chronicle entries removed to keep within the limit
    ["restore-point-repaired"] = false,  -- a backup kept after fixing its id, name or date
    ["root-not-table"] = true,           -- a whole saved variable was not a table
    ["container-not-table"] = true,      -- a settings group was not a table
    ["module-not-boolean"] = true,       -- an on/off setting held something else; back to its default
    ["received-pack-dropped"] = true,    -- a received setup that could not be read (the sender can send it again)
    ["setup-table-dropped"] = true,      -- one addon's settings inside a setup or backup that could not be used
    ["pending-dropped"] = true,          -- a queued apply or undo that could not be read
    ["share-pack-dropped"] = true,       -- your own shareable setup could not be read (save it again)
    ["backup-dropped"] = true,           -- an undo backup that could not be read
    ["restore-point-dropped"] = true,
    ["chronicle-record-dropped"] = true, -- a character's Chronicle record that was not a table
    ["chronicle-entry-dropped"] = true,  -- a Chronicle entry with nothing readable in it
    ["migration-failed"] = true,
    ["future-schema"] = true,
}

local report = {
    main = { current = P.SCHEMA },
    chronicle = { current = P.CHRONICLE_VERSION },
    repairs = {},
}
local notified = false

function P.Repair(code, n)
    report.repairs[code] = (report.repairs[code] or 0) + (n or 1)
end

-- { stored, current, outcome } for each versioned root, and { [code] = count }. A copy.
function P.Report()
    local out = { main = {}, chronicle = {}, repairs = {} }
    for k, v in pairs(report.main) do out.main[k] = v end
    for k, v in pairs(report.chronicle) do out.chronicle[k] = v end
    for k, v in pairs(report.repairs) do out.repairs[k] = v end
    out.lost = P.Lost()
    return out
end

function P.Lost()
    local n = 0
    for code, count in pairs(report.repairs) do
        if P.CODES[code] then n = n + count end
    end
    return n
end

function P.SetChronicle(stored, outcome)
    report.chronicle.stored, report.chronicle.outcome = stored, outcome
end

---------------------------------------------------------------------------
-- Small shared helpers
---------------------------------------------------------------------------
-- A copy that shares nothing with the original. Only plain saved data survives.
local function DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    seen = seen or {}
    if seen[src] then return seen[src] end
    local dst = {}
    seen[src] = dst
    for k, v in next, src do
        local kt, vt = type(k), type(v)
        if (kt == "string" or kt == "number" or kt == "boolean") and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
            dst[k] = (vt == "table") and DeepCopy(v, seen) or v
        end
    end
    return dst
end
P.DeepCopy = DeepCopy

-- The values at positive whole-number keys, in key order, whatever holes there are. ipairs stops at the
-- first hole and would leave everything after it behind.
function P.Sequence(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "number" and k >= 1 and k % 1 == 0 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local out = {}
    for i = 1, #keys do out[i] = t[keys[i]] end
    return out
end

function P.IsCount(n) return type(n) == "number" and n == n and n >= 0 and n % 1 == 0 and n < 2 ^ 53 end

---------------------------------------------------------------------------
-- Setting a newer copy aside (and getting it back)
-- The client saves each saved variable's global as it is at logout. To leave a newer copy alone, it is
-- swapped out for a stand-in, and put back on PLAYER_LOGOUT (a documented synchronous event, which
-- fires for a reload too). The stand-in also holds the original (heldStored), so that if the client
-- were ever to save without that event having run, the next load finds the original and puts it back.
---------------------------------------------------------------------------
local held = {}

function P.Hold(name, stored, standIn)
    standIn.heldStored = stored
    held[name] = stored
    _G[name] = standIn
end

function P.IsHeld(name) return held[name] ~= nil end

local function Release()
    for name, stored in pairs(held) do
        _G[name] = stored
        held[name] = nil
    end
end
P.Release = Release   -- tests; the game calls it at PLAYER_LOGOUT
R:On("PLAYER_LOGOUT", Release)

-- If the saved file holds a stand-in from a session that ended without the swap back, return the original.
function P.Recover(name)
    local cur = _G[name]
    if type(cur) == "table" and type(cur.heldStored) == "table" and held[name] == nil then
        _G[name] = cur.heldStored
        P.Repair("held-recovered")
    end
end

-- A saved variable that must be a table: made one when it is missing or damaged.
function P.EnsureRoot(name)
    P.Recover(name)
    local cur = _G[name]
    if type(cur) ~= "table" then
        if cur ~= nil then P.Repair("root-not-table") end
        _G[name] = {}
    end
    return _G[name]
end

---------------------------------------------------------------------------
-- Upgrading TwichUIDB
-- STEPS[n] brings schema n-1 up to n. A step works on `work`, a copy that shares the live tables until
-- ctx.own(key) makes a private copy of one of them; it must change nothing it did not take with own().
-- Steps are repeatable: running one on data it already upgraded changes nothing.
---------------------------------------------------------------------------
local CONTAINERS = { "modules", "ui", "setup", "gear", "storedData", "whisperProbe" }

local function DeriveTransport(modules)
    local m = type(modules) == "table" and modules or {}
    return (m.shareGroup == true and "PARTY") or (m.shareGuild == true and "GUILD") or "DIRECT"
end

P.STEPS = {
    -- 0 -> 1: the unversioned layout of every release so far. Gathers the clean-ups that used to run on
    -- every load, now once.
    [1] = function(work, ctx)
        -- Sending used to be three switches (shareWhisper, shareGroup, shareGuild). A saved "on" for group or
        -- guild was a choice and is kept; everything else, including having left the defaults, is Direct.
        -- The old keys stay as they were.
        if not VALID_TRANSPORT[work.shareTransport] then work.shareTransport = DeriveTransport(work.modules) end
        -- The unfinished combo points display was removed before release; only its saved keys go.
        local modules, ui = ctx.own("modules"), ctx.own("ui")
        if modules then
            for _, k in ipairs({ "comboPoints", "comboPointsHideGame" }) do
                if modules[k] ~= nil then modules[k] = nil; ctx.repair("legacy-key-removed") end
            end
        end
        if ui then
            for _, k in ipairs({ "comboPoints", "comboPointsPosition" }) do
                if ui[k] ~= nil then ui[k] = nil; ctx.repair("legacy-key-removed") end
            end
        end
        -- Left by earlier builds of the addon-data scan and its temporary check.
        local stored = ctx.own("storedData")
        if stored and stored.scanMode ~= nil then stored.scanMode = nil; ctx.repair("legacy-key-removed") end
        if work.svTest ~= nil then work.svTest = nil; ctx.repair("legacy-key-removed") end
    end,
}

-- A migrated copy must be usable before it replaces anything.
local function Valid(work, target)
    if work.schema ~= target then return false, "schema" end
    for _, key in ipairs(CONTAINERS) do
        if work[key] ~= nil and type(work[key]) ~= "table" then return false, key end
    end
    if not VALID_TRANSPORT[work.shareTransport] then return false, "shareTransport" end
    return true
end

-- Runs steps from+1 .. target on a working copy. Returns true, work, repairs  |  false, step, reason.
-- The live table is not touched.
function P.Migrate(db, steps, from, target)
    local work, owned, repairs = {}, {}, {}
    for k, v in pairs(db) do work[k] = v end
    local ctx = {}
    function ctx.own(key)
        local cur = work[key]
        if type(cur) ~= "table" then return nil end
        if not owned[key] then work[key] = DeepCopy(cur); owned[key] = true end
        return work[key]
    end
    function ctx.repair(code, n) repairs[code] = (repairs[code] or 0) + (n or 1) end
    for n = from + 1, target do
        if type(steps[n]) ~= "function" then return false, n, "no-such-step" end
        local ok, err = pcall(steps[n], work, ctx)
        if not ok then return false, n, tostring(err) end
    end
    work.schema = target
    local okValid, why = Valid(work, target)
    if not okValid then return false, target, "invalid-result:" .. tostring(why) end
    return true, work, repairs
end

-- Puts a validated working copy into the live table. Plain assignments only, after everything has passed.
function P.Commit(db, work)
    for k in pairs(db) do
        if work[k] == nil then db[k] = nil end
    end
    for k, v in pairs(work) do
        if db[k] ~= v then db[k] = v end
    end
end

---------------------------------------------------------------------------
-- Making TwichUIDB usable: containers, on/off settings, defaults
---------------------------------------------------------------------------
-- Fills what is missing and fixes what cannot be used, one value at a time. Repeatable.
function P.Normalize(db)
    for _, key in ipairs(CONTAINERS) do
        if db[key] ~= nil and type(db[key]) ~= "table" then
            db[key] = nil
            P.Repair("container-not-table")
        end
    end
    if type(db.modules) ~= "table" then db.modules = {} end
    local added = 0
    for k, v in pairs(R.DEFAULT_MODULES or {}) do
        local cur = db.modules[k]
        if cur == nil then
            db.modules[k] = v
            added = added + 1
        elseif type(cur) ~= "boolean" then
            -- R:Enabled counts anything but false as on, so a stray number or text would switch a feature on.
            db.modules[k] = v
            P.Repair("module-not-boolean")
        end
    end
    if added > 0 then P.Repair("defaults-added", added) end
    -- Groups the features write into without checking first.
    if type(db.ui) == "table" then
        for _, k in ipairs({ "qol", "foodDrink", "brokerMenu" }) do
            if db.ui[k] ~= nil and type(db.ui[k]) ~= "table" then
                db.ui[k] = nil
                P.Repair("container-not-table")
            end
        end
    end
    if not VALID_TRANSPORT[db.shareTransport] then db.shareTransport = DeriveTransport(db.modules) end
end

local function ValidSchemaNumber(n) return P.IsCount(n) end

-- Called once from Core.lua when the saved variables have loaded, before any module starts.
function P.LoadMain()
    local main = report.main
    P.EnsureRoot("TwichUIBackupDB")
    P.EnsureRoot("TwichUIShareDB")
    local db = P.EnsureRoot("TwichUIDB")

    if next(db) == nil then
        main.outcome = "fresh"
        P.Normalize(db)
        db.schema = P.SCHEMA
        return
    end

    local stored = db.schema
    if stored ~= nil and not ValidSchemaNumber(stored) then
        P.Repair("schema-invalid")
        stored = nil
    end
    main.stored = stored
    local from = stored or 0

    if from > P.SCHEMA then
        -- Written by a newer TwichUI. Leave it exactly as it is and run this session on defaults.
        local standIn = {}
        P.Normalize(standIn)
        standIn.schema = P.SCHEMA
        P.Hold("TwichUIDB", db, standIn)
        main.outcome = "future"
        P.Repair("future-schema")
        return
    end

    if from < P.SCHEMA then
        -- On success: true, the migrated copy, its repair counts. On failure: false, the step, a reason.
        local ok, a, b = P.Migrate(db, P.STEPS, from, P.SCHEMA)
        if ok then
            P.Commit(db, a)
            for code, n in pairs(b) do P.Repair(code, n) end
            main.outcome = "migrated"
        else
            -- Nothing was changed. The session runs on what is stored (every reader tolerates the old layout)
            -- and the upgrade is tried again next time.
            main.outcome = "failed"
            main.failedStep = a
            P.Repair("migration-failed")
            if R.Diag then R.Diag.Error("saved data upgrade", ("step %s: %s"):format(tostring(a), tostring(b))) end
            P.Normalize(db)
            return
        end
    else
        main.outcome = "current"
    end
    P.Normalize(db)
    db.schema = P.SCHEMA
end

---------------------------------------------------------------------------
-- One short notice, only when something was set aside, reset or could not be upgraded
---------------------------------------------------------------------------
function P.Notice()
    local parts = {}
    local main, chron = report.main, report.chronicle
    if main.outcome == "future" and chron.outcome == "future" then
        parts[#parts + 1] = "Your saved settings and Journey Chronicle were made by a newer TwichUI. They are untouched, but this session starts from defaults and its changes are not saved. Update TwichUI to use them."
    elseif main.outcome == "future" then
        parts[#parts + 1] = "Your saved settings were made by a newer TwichUI. They are untouched, but this session starts from defaults and its changes are not saved. Update TwichUI to use them."
    elseif chron.outcome == "future" then
        parts[#parts + 1] = "Your Journey Chronicle was made by a newer TwichUI. It is untouched, but it looks empty this session and anything you add is not saved. Update TwichUI to see it."
    end
    if main.outcome == "failed" then
        parts[#parts + 1] = "TwichUI could not upgrade its saved settings. Nothing was changed, and it will try again next time."
    end
    local lost = P.Lost() - (report.repairs["future-schema"] or 0) - (report.repairs["migration-failed"] or 0)
    if lost > 0 then
        parts[#parts + 1] = ("TwichUI reset or set aside %d saved item%s it could not read; everything readable was kept."):format(lost, lost == 1 and "" or "s")
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ") .. " Details: /tui diagnostics."
end

R:On("PLAYER_LOGIN", function()
    if notified then return end
    notified = true
    local text = P.Notice()
    if text then R.Print("%s", text) end
end)
