-- TwichUI Layouts: the packages kept for sending and for installing (docs/layouts/publishing.md)
-- TwichUIDB.layouts.published (what this player published) and TwichUIDB.layouts.received (what others sent), each a short
-- list of entries. An entry holds a summary for listing and the package itself as ONE text: the exact bytes that travel
-- (Share.lua's packed block), printable-encoded. A package is therefore never kept as tables between uses (about a megabyte
-- each), is immutable by construction (nothing edits a string), and is sent byte for byte as it was published.
--
--   entry = { id, revision, hash, at (a time), size (bytes of the packed block), blob (printable text),
--             title, by (the author's own label, untrusted), sender (received: the game's word), variants (a count) }
--
-- Bounded: at most LIMITS.published and LIMITS.received entries and LIMITS.bytes of text in all. Adding past a bound is
-- refused ("full"); nothing the player made or accepted is dropped to make room. Reading never writes, repairs or removes anything: an entry that doesn't look right is skipped. Opening an entry
-- unpacks it a little at a time and checks it again (Pub.Check) before anyone is shown anything from it.
--
--   Store.List(kind)  Store.Add(kind, entry)  Store.Remove(kind, entry)  Store.Bytes()
--   Store.Seal(envelope, done, fail)      packs a published envelope into an entry (done(entry))
--   Store.Open(entry, done, fail)         unpacks and checks an entry (done(envelope, info) | fail(code, problems))
--   Store.Wire(entry)                     the packed block as it travels
--   LY.Receive(message, wire, ctx)        checks an arrived package and stores it: entry | nil, code, problems

local R = TwichUI
local LY = R.Layouts
local Pub = LY.Pub
local Perf = R.Perf
local S = {}
LY.Store = S

local LibDeflate = LibStub("LibDeflate")

S.LIMITS = { published = 4, received = 3, bytes = 3 * 1048576 }
local KINDS = LY.Set({ "published", "received" })

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

local function Whole(n, min, max) return type(n) == "number" and n == n and n % 1 == 0 and n >= min and n <= max end

local function Wire() return R.Share and R.Share.LAYOUT_MAX_WIRE or 786432 end

local function EntryOk(e, kind)
    if type(e) ~= "table" then return false end
    if not (LY.IsId(e.id) and Whole(e.revision, 1, 1e6) and Whole(e.at, 0, 2 ^ 40) and Whole(e.size, 3, Wire())) then return false end
    if type(e.hash) ~= "string" or #e.hash > 48 or type(e.blob) ~= "string" or #e.blob < 3 or #e.blob > Wire() * 2 then return false end
    if e.title ~= nil and not LY.Plain(e.title, 80) then return false end
    if e.by ~= nil and not LY.Plain(e.by, 40) then return false end
    if e.sender ~= nil and not LY.Plain(e.sender, 64) then return false end
    if e.variants ~= nil and not Whole(e.variants, 0, LY.MAX_VARIANTS) then return false end
    return true
end

-- The usable entries of a kind, oldest first. Each is the saved table itself (do not edit it).
function S.List(kind)
    local out = {}
    local root = KINDS[kind] and Root(false)
    local raw = root and root[kind]
    if type(raw) ~= "table" then return out end
    for i = 1, #raw do
        if EntryOk(raw[i], kind) then out[#out + 1] = raw[i] end
    end
    return out
end

function S.Bytes()
    local n = 0
    for kind in pairs(KINDS) do
        for _, e in ipairs(S.List(kind)) do n = n + #e.blob end
    end
    return n
end

function S.Count(kind) return #S.List(kind) end

-- Adds an entry (a copy of its fields is kept). Returns true | false, code ("bad-kind", "bad-entry", "too-large", "full",
-- "no-room"). Nothing is ever dropped to make room: a full store refuses, and the player removes an entry themselves.
function S.Add(kind, entry)
    if not KINDS[kind] then return false, "bad-kind" end
    if not EntryOk(entry, kind) then return false, "bad-entry" end
    if #entry.blob > S.LIMITS.bytes then return false, "too-large" end
    local root = Root(true)
    if not root then return false, "no-room" end
    if root[kind] ~= nil and type(root[kind]) ~= "table" then return false, "no-room" end   -- not ours to replace
    local list = root[kind] or {}
    local keep = { id = entry.id, revision = entry.revision, hash = entry.hash, at = entry.at, size = entry.size, blob = entry.blob,
        title = entry.title, by = entry.by, sender = entry.sender, variants = entry.variants }
    -- the same package again (same id, revision, fingerprint and sender) takes the place of the copy already kept
    local same
    for i, e in ipairs(list) do
        if type(e) == "table" and e.id == keep.id and e.revision == keep.revision and e.hash == keep.hash and e.sender == keep.sender then same = i end
    end
    if not same and S.Count(kind) >= S.LIMITS[kind] then return false, "full" end
    local bytes = S.Bytes() - (same and #list[same].blob or 0) + #keep.blob
    if bytes > S.LIMITS.bytes then return false, "full" end
    if same then list[same] = keep else list[#list + 1] = keep end
    root[kind] = list
    return true
end

function S.Remove(kind, entry)
    local root = KINDS[kind] and Root(false)
    local list = root and root[kind]
    if type(list) ~= "table" then return false end
    for i = #list, 1, -1 do
        if list[i] == entry then
            table.remove(list, i)
            if #list == 0 then root[kind] = nil end
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Packing and unpacking: Share.lua's own, a few frames' work at a time
---------------------------------------------------------------------------
function S.Wire(entry)
    if not EntryOk(entry) then return nil end
    local wire = LibDeflate:DecodeForPrint(entry.blob)
    if type(wire) ~= "string" or #wire ~= entry.size then return nil end
    return wire
end

local function Summary(env, extra)
    local e = { id = env.meta.id, revision = env.meta.version, hash = env.meta.hash, at = extra.at, size = extra.size,
        blob = extra.blob, title = LY.Plain(env.package.title or "", 80) and env.package.title or nil,
        by = env.meta.publisher, sender = extra.sender, variants = env.meta.counts and env.meta.counts.variants or nil }
    return e
end

-- Packs an envelope that Pub.Build made. done(entry) when it is packed (not stored: Add does that), fail(code).
function S.Seal(env, done, fail)
    local ok, problems = Pub.Check(env)
    if not ok then fail("invalid", problems) return end
    local SH = R.Share
    local handle = SH.EncodeData({ t = "layoutdata", env = env }, function(wire)
        if #wire > Wire() then fail("too-large") return end
        done(Summary(env, { at = env.meta.published, size = #wire, blob = LibDeflate:EncodeForPrint(wire) }))
    end, function(err) fail("pack-failed", err) end)
    return handle
end

-- Unpacks and checks an entry. done(envelope, info) or fail(code, problems). The entry's summary must agree with what is in it.
function S.Open(entry, done, fail)
    local wire = S.Wire(entry)
    if not wire then fail("unreadable") return end
    R.Share.DecodeData(wire, function(msg)
        local t0 = Perf.on and Perf.Start("layouts.store.open")
        local env = type(msg) == "table" and msg.t == "layoutdata" and msg.env or nil
        local ok, problems, info = Pub.Check(env)
        if t0 then Perf.Stop(t0) end
        if not ok then fail("invalid", problems) return end
        if env.meta.id ~= entry.id or env.meta.version ~= entry.revision or env.meta.hash ~= entry.hash then
            fail("mismatch")
            return
        end
        done(env, info)
    end, function(err) fail("unreadable", err) end)
end

---------------------------------------------------------------------------
-- An arrived package (Share.lua hands it over a frame after unpacking it)
---------------------------------------------------------------------------
-- msg = the unpacked message ({ t = "layoutdata", env }); wire = the bytes as they arrived; ctx = { sender, offer }.
-- Checks it as it is checked everywhere (Pub.Check), against what was offered, and keeps it. Nothing is applied.
-- Returns entry | nil, code ("invalid", "mismatch", "full"), problems.
local function DoReceive(msg, wire, ctx)
    local env = type(msg) == "table" and msg.t == "layoutdata" and msg.env or nil
    if type(wire) ~= "string" or #wire > Wire() or type(ctx) ~= "table" or type(ctx.offer) ~= "table" then return nil, "invalid" end
    local ok, problems = Pub.Check(env)
    if not ok then return nil, "invalid", problems end
    local o = ctx.offer
    if env.meta.id ~= o.pkg or env.meta.version ~= o.revision or env.meta.hash ~= o.hash or #wire ~= o.size then return nil, "mismatch" end
    local sender = LY.Plain(tostring(ctx.sender or ""), 64) and ctx.sender or nil
    local entry = Summary(env, { at = time(), size = #wire, blob = LibDeflate:EncodeForPrint(wire), sender = sender })
    local added, why = S.Add("received", entry)
    if not added then return nil, "full", { { code = why, where = "store" } } end
    return entry
end
function LY.Receive(msg, wire, ctx) return Perf.Call("layouts.publish.receive", DoReceive, msg, wire, ctx) end

R.Perf.Gauge("layouts.store.entries", { label = "Layout packages kept (published + received)", unit = "count", kind = "cache",
    group = "layouts", read = function() return S.Count("published") + S.Count("received") end })
R.Perf.Gauge("layouts.store.kb", { label = "Layout packages kept: text held in saved data", unit = "KB", kind = "cache",
    group = "layouts", read = function() return S.Bytes() / 1024 end })
