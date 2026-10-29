-- TwichUI layout tools: a package published in game, found, unpacked and checked offline (docs/layouts/presets.md).
-- Shared by tools/import_published_layout.lua and tools/check_bundled_layout.lua --published, so the import and the check that
-- follows it read the published package in exactly the same way. Needs tools/layout_data.lua and an offline TwichUI client
-- with TwichUI_Layouts loaded (as the tools load it).
--
--   PE.Parse(text) -> entry | nil, why              the in-game "Export for bundling" text:
--                                                   !TwichUI-layout!1!<id>!<revision>!<fingerprint>!<size>!<printable block>
--   PE.FromSaved(path) -> entries | nil, why        every published entry in a COPY of a !!!TwichUI.lua saved file (read as data by
--                                                   the strict reader; nothing in it is run). Entries as TwichUIDB.layouts.published
--   PE.Pick(entries, revision, hash) -> entry | nil, why
--   PE.Open(client, entry) -> envelope | nil, why, problems
--       unpacks the block with the transport's own bounded decoder (as a received package is), and checks the envelope with
--       Pub.Check, the function a recipient's TwichUI runs; the entry's id, revision and fingerprint must be the package's
-- Nothing is written anywhere.

PE = {}

PE.TAG = "!TwichUI-layout!1!"
local MAX_TEXT = 2 * 786432 + 256   -- the stored block is at most twice the wire limit as printable text

local function Whole(n) return type(n) == "number" and n == n and n % 1 == 0 and n >= 1 and n <= 1e6 end
local function IsId(s) return type(s) == "string" and #s <= 64 and s:match("^[a-z][a-z0-9%-]*$") ~= nil end

local function EntryOk(e)
    return type(e) == "table" and IsId(e.id) and Whole(e.revision) and type(e.hash) == "string" and #e.hash <= 48
        and type(e.size) == "number" and e.size >= 3 and e.size <= 786432 and type(e.blob) == "string" and #e.blob >= 3 and #e.blob <= MAX_TEXT
end

function PE.Parse(text)
    if type(text) ~= "string" then return nil, "no text" end
    if #text > MAX_TEXT + 512 then return nil, "the text is longer than a published package can be" end
    text = text:gsub("%s+", "")   -- an editor may wrap or add a line break; the block itself has none
    if text:sub(1, #PE.TAG) ~= PE.TAG then return nil, "it doesn't start with " .. PE.TAG .. " (copy the whole text the Export window shows)" end
    local id, rev, hash, size, blob = text:sub(#PE.TAG + 1):match("^([%w%-]+)!(%d+)!([^!]+)!(%d+)!([%w%(%)]+)$")
    if not id then return nil, "it isn't in the export's form (id, revision, fingerprint, size, then the block)" end
    local e = { id = id, revision = tonumber(rev), hash = hash, size = tonumber(size), blob = blob }
    if not EntryOk(e) then return nil, "its id, revision, fingerprint or size isn't one a published package can have" end
    return e
end

function PE.FromSaved(path)
    local ok, vars = pcall(LD.ReadData, path)
    if not ok then return nil, tostring(vars) end
    local T = vars.TwichUIDB
    local list = type(T) == "table" and type(T.layouts) == "table" and T.layouts.published
    if type(list) ~= "table" then return nil, "it holds no published layout packages (TwichUIDB.layouts.published)" end
    local out = {}
    for i = 1, #list do if EntryOk(list[i]) then out[#out + 1] = list[i] end end
    if #out == 0 then return nil, "it holds no published layout packages that can be read" end
    return out
end

function PE.Pick(entries, revision, hash)
    local found = {}
    for _, e in ipairs(entries) do
        if (revision == nil or e.revision == revision) and (hash == nil or e.hash == hash) then found[#found + 1] = e end
    end
    if #found == 1 then return found[1] end
    if #found == 0 then return nil, "no published package matches" end
    return nil, "more than one published package matches: name one with --revision (and --hash if two share a revision)"
end

function PE.Describe(e)
    return ("%s revision %d, fingerprint %s, %d bytes packed%s"):format(e.id, e.revision, e.hash, e.size,
        e.at and (", published " .. os.date("!%Y-%m-%d %H:%M UTC", e.at)) or "")
end

function PE.Open(c, e)
    local R = c.TwichUI
    local LY = R.Layouts
    local LibDeflate = c.LibStub("LibDeflate")
    local wire = LibDeflate:DecodeForPrint(e.blob)
    if type(wire) ~= "string" or #wire ~= e.size then return nil, "the block is damaged (it doesn't decode to the size it says)" end
    local got, failed
    R.Share.DecodeData(wire, function(msg) got = msg end, function(err) failed = tostring(err) end, R.Share.LAYOUT_DECODE)
    for _ = 1, 100000 do
        if got or failed then break end
        FlushTimers()
    end
    if failed then return nil, "the block didn't unpack: " .. failed end
    if not got then return nil, "the block didn't finish unpacking" end
    local env = type(got) == "table" and got.t == "layoutdata" and got.env or nil
    if not env then return nil, "it isn't a layout package" end
    local ok, problems = LY.Pub.Check(env)
    if not ok then return nil, "it fails the checks a recipient's TwichUI makes: " .. table.concat(LY.Pub.Explain(problems, 4), "; "), problems end
    if env.meta.id ~= e.id or env.meta.version ~= e.revision or env.meta.hash ~= e.hash then
        return nil, "its id, revision or fingerprint isn't the package's own"
    end
    return env
end

return PE
