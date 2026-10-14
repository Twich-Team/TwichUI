-- TwichUI: Saved Data Explorer, core (/tui saved)
-- A read-only look at what TwichUI itself keeps between sessions: its settings, backups (restore
-- points and Undo copies), your saved setup and the exact messages Send would make from it, setups
-- friends sent you, and the Journey Chronicle. setup/ExplorerWindow.lua draws it. Removing anything is
-- a separate, opt-in feature (setup/Cleanup.lua); nothing in this file changes data.
--
-- What "saved" means here: the tables the game loaded from TwichUI's saved variables at login, as
-- they are in memory now. An addon can't read the file on disk; what changed this session reaches
-- the file when you reload or log out. Runtime state (transfers, previews, diagnostics) is not
-- saved and is not listed, except the share preview, which is built here, on request, by the same
-- code that builds the real messages, and is marked as such.
--
-- Read-only: tables are walked with next and rawget, so no metatable code runs; values are shown by
-- type and never called or run; nothing is filled in, repaired, copied into saved data or sent.
-- Nothing of what is looked at is kept after the window closes.

local R = TwichUI
local ST, SH, RS, SD = R.Setups, R.Share, R.Restore, R.StoredData
local EX = {}
R.Explorer = EX

EX.PAGE = 200             -- entries shown per table before "Show more"
EX.MAX_DEPTH = 64         -- deepest level opened, searched or written out (saved data never needs more)
EX.SHAPE_CAP = 1000       -- entries counted for a table's summary
EX.EXPAND_LIMIT = 2000    -- tables "Expand all" opens at most
EX.SEARCH_RESULTS = 300
EX.SEARCH_VISITS = 300000
EX.DUMP_BYTES = 200 * 1024
EX.DETAIL_BYTES = 64 * 1024
EX.PREVIEW_ID = ("0"):rep(14)   -- stands in for a transfer id (same length as SH.NewId's), so sizes match closely
local COMM_MAX = 255            -- AceComm-3.0: longest single addon message; longer texts go in 254-byte parts

local function When(t) return type(t) == "number" and date("%b %d %Y, %H:%M", t) or nil end

---------------------------------------------------------------------------
-- Listeners: the window hears when what it shows may have changed
---------------------------------------------------------------------------
local listeners = {}
function EX.OnChange(fn) listeners[#listeners + 1] = fn end
function EX.Changed(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then geterrorhandler()(err) end
    end
end

-- The places that add, replace or delete what is listed say so (the same wrapping Restore.lua uses).
local function Notify(owner, name)
    local base = owner[name]
    owner[name] = function(...)
        local a, b, c = base(...)
        EX.Changed("sources")
        return a, b, c
    end
end
for _, name in ipairs({ "SaveMine", "DeleteMine", "RemoveReceived", "DeleteBackup", "UpdateSavedAddonList", "ClearSearch" }) do Notify(ST, name) end
for _, name in ipairs({ "Delete", "AddImported" }) do Notify(RS, name) end
SH:OnChange(function() EX.Changed("share") end)
R:On("PLAYER_LOGIN", function() EX.Changed("sources") end)   -- a backup finished after a reload

---------------------------------------------------------------------------
-- Text: keys, values and paths, exactly
---------------------------------------------------------------------------
function EX.IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

-- The shortest text that reads back as the same number. Whole numbers go through %.0f: the game's %d
-- stores an integer in 32 bits and warns past 2,147,483,647 (ids and timestamps are larger).
function EX.NumText(v)
    if v ~= v then return "nan" end
    if v == math.huge then return "inf" end
    if v == -math.huge then return "-inf" end
    if v == math.floor(v) and v > -1e15 and v < 1e15 then return ("%.0f"):format(v + 0) end   -- + 0: -0 reads "0"
    for digits = 14, 17 do
        local s = ("%." .. digits .. "g"):format(v)
        if tonumber(s) == v then return s end
    end
    return ("%.17g"):format(v)
end

local ESC = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
-- A string as a quoted literal: quotes, backslashes and control characters escaped.
function EX.Quote(s)
    return '"' .. s:gsub('[%c\\"]', function(c) return ESC[c] or ("\\%03d"):format(c:byte()) end) .. '"'
end

-- Cuts at most max bytes without splitting a character.
function EX.Clip(s, max)
    if #s <= max then return s, false end
    local cut = max
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut), true
end

-- One step of a path: .name, ["any text"], [1], [true].
function EX.PathPart(k)
    if EX.IsSecret(k) then return "[<secret>]" end
    local t = type(k)
    if t == "string" then
        if k:find("^[%a_][%w_]*$") then return "." .. k end
        return "[" .. EX.Quote(k) .. "]"
    end
    if t == "number" then return "[" .. EX.NumText(k) .. "]" end
    if t == "boolean" then return "[" .. tostring(k) .. "]" end
    return "[<" .. t .. ">]"
end

-- A value for a row: text quoted and shortened, numbers exact, other types named (never tostring'd).
function EX.ValueText(v, max)
    if EX.IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then
        local s, cut = EX.Clip(v, max or 160)
        return EX.Quote(s) .. (cut and ("... (%s characters)"):format(SD.Num(#v)) or "")
    end
    if t == "number" then return EX.NumText(v) end
    if t == "boolean" then return tostring(v) end
    if t == "nil" then return "nil" end
    return "<" .. t .. ">"
end

-- What a type means here, in words.
local TYPE_NOTE = {
    string = "Text.",
    number = "A number.",
    boolean = "true or false. false is a stored value, not a missing one.",
    table = "A table: entries under keys.",
    ["function"] = "Code, not data. Saved variables can't hold it, so it isn't saved; it is shown by type only and never run.",
    userdata = "A game object, not data. It isn't saved; shown by type only.",
    thread = "A coroutine, not data. It isn't saved; shown by type only.",
}
function EX.TypeNote(v)
    if EX.IsSecret(v) then return "Hidden by the game; its value can't be read." end
    return TYPE_NOTE[type(v)] or ("A " .. type(v) .. ", which can't be shown normally.")
end

-- Entries in a table, up to cap, and its shape: "empty", "list" (keys 1..n), "gaps" (only whole
-- numbers from 1, with gaps), "keyed" (no list keys) or "mixed". more: there are more than cap (the shape is then of the first cap only).
function EX.Shape(t, cap)
    cap = cap or EX.SHAPE_CAP
    local n, ints, maxInt = 0, 0, 0
    for k in next, t do
        if n >= cap then return n, true, "large" end
        n = n + 1
        if not EX.IsSecret(k) and type(k) == "number" and k >= 1 and k == math.floor(k) then
            ints = ints + 1
            if k > maxInt then maxInt = k end
        end
    end
    if n == 0 then return 0, false, "empty" end
    if ints == n then return n, false, maxInt == n and "list" or "gaps" end
    if ints == 0 then return n, false, "keyed" end
    return n, false, "mixed"
end

local SHAPE_WORD = { list = "list", gaps = "numbered, with gaps", keyed = "keyed", mixed = "numbered and keyed", large = "" }
function EX.ShapeText(count, more, shape)
    if shape == "empty" then return "empty table" end
    local word = SHAPE_WORD[shape] or ""
    return ("%s%s %s%s"):format(SD.Num(count), more and "+" or "", count == 1 and "entry" or "entries",
        word ~= "" and (", " .. word) or "")
end

local function Readable(t)
    return not (canaccesstable and not canaccesstable(t))
end

---------------------------------------------------------------------------
-- Personal-looking values: hidden on screen and in copies until revealed
---------------------------------------------------------------------------
-- These are signs, not a guarantee: they catch character names in the forms addons store them, the
-- character id, Battle.net tags, friends' names where TwichUI keeps them, and your Chronicle notes.
local NAME_FIELDS = { source = true, sourceName = true, sender = true, from = true, to = true }
local NAME_PARENTS = { trusted = true, received = true, profileKeys = true, chars = true }

local own                         -- this session's own names, lower case (built when first needed)
local function OwnNames()
    if own then return own end
    own = {}
    for _, n in ipairs({ UnitName and UnitName("player"), SH.SelfName(), ST.CharKey(), UnitGUID and UnitGUID("player") }) do
        if type(n) == "string" and n ~= "" and n ~= "?" then own[n:lower()] = true end
    end
    return own
end

local function TextSign(s)
    if #s > 96 then return nil end
    if OwnNames()[s:lower()] then return "your character" end
    if s:find("^Player%-%d+%-%x+$") then return "a character id" end
    if s:find("^[^#%s]+#%d%d%d%d+$") then return "a Battle.net tag" end
    if s:find("%S %- %S") then return "a character and realm" end
end

-- Why the key of an entry looks personal, or nil. parentKey: the key of the table it is in.
function EX.PersonalKey(k, parentKey)
    if type(k) ~= "string" or EX.IsSecret(k) then return nil end
    if NAME_PARENTS[parentKey] then return parentKey == "trusted" and "a friend's name" or "a character's name" end
    return TextSign(k)
end

-- Why a value looks personal, or nil. parent: the table it is in.
function EX.PersonalValue(k, v, parent)
    if type(v) ~= "string" or EX.IsSecret(v) then return nil end
    if NAME_FIELDS[k] then return "a character's name" end
    if k == "note" then return "your own writing" end
    if k == "title" and type(parent) == "table" and rawget(parent, "kind") == "note" then return "your own writing" end
    return TextSign(v)
end

function EX.Hidden(why) return "<hidden: " .. why .. ">" end

-- Forget the cached names (a test, or a character change in another session).
function EX.ResetNames() own = nil end

---------------------------------------------------------------------------
-- Sources: what can be looked at. Each resolves its table afresh every time it is asked, by id, so
-- a backup deleted or a setup replaced while the window is open is noticed, never shown as current.
---------------------------------------------------------------------------
local function G(name) return rawget(_G, name) end

local function SortedKeys(t)
    local keys = {}
    for k in next, t do if type(k) == "string" then keys[#keys + 1] = k end end
    table.sort(keys)
    return keys
end

local function CountTables(t)
    local n = 0
    if type(t) == "table" then for _ in next, t do n = n + 1 end end
    return n
end

-- { id, group, label, detail, path, masked (the path with a name hidden), scope, personal, Root() }
function EX.Sources()
    local list = {}
    local function Add(s) list[#list + 1] = s end

    Add({ id = "settings", group = "Configuration", label = "TwichUI settings", path = "TwichUIDB",
        detail = "account-wide", Root = function() return G("TwichUIDB") end,
        scope = "Account-wide. modules, ui and gear hold the profile this character uses; profiles holds the others, profileKeys which profile each character uses. A few entries are the same for every profile (map pins, sharing records, stat weights, the never-sell list), and a few are kept per character, under a character's name or id." })

    local rdb = G("TwichUIRestoreDB")
    local points = type(rdb) == "table" and type(rdb.points) == "table" and rdb.points or {}
    local order = {}
    for i, p in ipairs(points) do if type(p) == "table" then order[#order + 1] = { i = i, p = p } end end
    table.sort(order, function(a, b) return (a.p.created or 0) > (b.p.created or 0) end)
    for _, e in ipairs(order) do
        local id = e.p.id
        Add({ id = "restore:" .. tostring(id), group = "Backups", kind = "restore",
            label = type(e.p.name) == "string" and e.p.name or "Backup",
            detail = (When(e.p.created) or "date not recorded") .. " · restore point",
            path = function()
                for i, p in ipairs(type(G("TwichUIRestoreDB")) == "table" and G("TwichUIRestoreDB").points or {}) do
                    if p == RS.Get(id) then return ("TwichUIRestoreDB.points[%d]"):format(i) end
                end
                return "TwichUIRestoreDB.points[?]"
            end,
            Root = function() return id and RS.Get(id) end,
            scope = "Account-wide. Addon settings copied when the backup was made; restoring it is in the sharing window's Backups page." })
    end
    local bdb = G("TwichUIBackupDB")
    if type(bdb) == "table" then
        for _, charKey in ipairs(SortedKeys(bdb)) do
            Add({ id = "undo:" .. charKey, group = "Backups", kind = "undo", personal = true,
                label = "Undo copy", detail = charKey,
                path = "TwichUIBackupDB[" .. EX.Quote(charKey) .. "]", masked = "TwichUIBackupDB[" .. EX.Hidden("a character's name") .. "]",
                Root = function() local b = G("TwichUIBackupDB"); b = type(b) == "table" and b[charKey]; return type(b) == "table" and b or nil end,
                scope = "For one character: the settings that character had before it last applied a setup. The next apply replaces it." })
        end
    end

    Add({ id = "share:preview", group = "Sharing", kind = "preview", label = "Outgoing share",
        detail = "exactly what Send sends", path = "(share preview)",
        Root = function() return EX.preview and not EX.preview.failed and EX.preview.root or nil end,
        scope = "Not saved data: the messages Send would make from your saved setup, built on request by the same code that sends. Nothing is sent from here." })
    Add({ id = "share:mine", group = "Sharing", kind = "mine", label = "Your saved setup", path = "TwichUIShareDB.pack",
        detail = "what Send uses", Root = function() return ST.Mine() end,
        scope = "Account-wide. Saved when you press Save setup; Send always sends this saved copy." })
    local setup = type(G("TwichUIDB")) == "table" and G("TwichUIDB").setup
    local received = type(setup) == "table" and type(setup.received) == "table" and setup.received or {}
    for _, sender in ipairs(SortedKeys(received)) do
        local pack = received[sender]
        Add({ id = "recv:" .. sender, group = "Sharing", kind = "received", personal = true,
            label = "From " .. (type(pack) == "table" and type(pack.sourceName) == "string" and pack.sourceName or sender),
            detail = "received setup", path = "TwichUIDB.setup.received[" .. EX.Quote(sender) .. "]",
            masked = "TwichUIDB.setup.received[" .. EX.Hidden("a friend's name") .. "]",
            Root = function()
                local s = type(G("TwichUIDB")) == "table" and G("TwichUIDB").setup
                local p = type(s) == "table" and type(s.received) == "table" and s.received[sender]
                return type(p) == "table" and p or nil
            end,
            scope = "A friend's setup kept on this computer. Applying it is in the sharing window." })
    end

    Add({ id = "chronicle", group = "Feature data", kind = "chronicle", label = "Journey Chronicle", personal = true,
        path = "TwichUIChronicleDB", detail = "personal, per character", Root = function() return G("TwichUIChronicleDB") end,
        scope = "Per character (one record under each character's name), in an account-wide variable. Personal: never part of sharing, backups or exports." })

    for _, name in ipairs({ "TwichUIRestoreDB", "TwichUIBackupDB", "TwichUIShareDB" }) do
        Add({ id = "var:" .. name, group = "Saved variables", kind = "var", label = name, path = name,
            detail = "the whole variable", Root = function() return G(name) end,
            scope = "Account-wide, as the game keeps it: everything in this variable, including anything listed above." })
    end
    return list
end

function EX.Source(id)
    for _, s in ipairs(EX.Sources()) do if s.id == id then return s end end
end

function EX.PathOf(source, reveal)
    if not reveal and source.masked and reveal ~= nil then return source.masked end
    return type(source.path) == "function" and source.path() or source.path
end

---------------------------------------------------------------------------
-- The tree: opened a level at a time, a page at a time. Holds the tables it shows while the window
-- is open, and is dropped when it closes or the source changes.
---------------------------------------------------------------------------
local Tree = {}
Tree.__index = Tree

-- openPaths: what was open in an earlier tree of the same source (paths below the root), to open again.
function EX.NewTree(root, rootPath, openPaths)
    local tree = setmetatable({ first = setmetatable({}, { __mode = "k" }), openPaths = openPaths or {}, opened = 0 }, Tree)
    tree.root = { value = root, depth = 0, path = rootPath, rel = "", isRoot = true }
    if type(root) == "table" then
        tree.first[root] = tree.root
        tree:Open(tree.root)
    end
    return tree
end

local function IsAncestor(node, v)
    local p = node
    while p do
        if rawequal(p.value, v) then return true end
        p = p.parent
    end
    return false
end

-- Whether a node can be opened, and if not, why.
function Tree:CanOpen(node)
    if type(node.value) ~= "table" then return false end
    if node.loop then return false, "It contains itself; opening it would never end." end
    if not Readable(node.value) then return false, "The game keeps this table hidden from addons." end
    if node.depth >= EX.MAX_DEPTH then return false, ("Deeper than %d levels; not opened here."):format(EX.MAX_DEPTH) end
    return true
end

function Tree:Open(node)
    if not self:CanOpen(node) then return false end
    if not node.keys then
        node.keys, node.hidden, node.unsorted = SD.Keys(node.value)
        node.limit = EX.PAGE
        node.kids = {}
    end
    if not node.open then self.opened = self.opened + 1 end
    node.open = true
    self.openPaths[node.rel] = true
    return true
end

function Tree:Close(node)
    node.open = false
    self.openPaths[node.rel] = nil
end

function Tree:Toggle(node)
    if node.open then self:Close(node) return true end
    return self:Open(node)
end

function Tree:More(node) node.limit = node.limit + EX.PAGE end

function Tree:Kid(node, i)
    local kid = node.kids[i]
    if kid then return kid end
    local k = node.keys[i]
    local v = rawget(node.value, k)
    local part = EX.PathPart(k)
    kid = { key = k, value = v, depth = node.depth + 1, parent = node, path = node.path .. part, rel = node.rel .. part }
    if type(v) == "table" then
        kid.loop = IsAncestor(node, v)
        if Readable(v) then kid.count, kid.more, kid.shape = EX.Shape(v) else kid.hiddenTable = true end
        local first = self.first[v]       -- the node where this table was first seen
        if first == nil then self.first[v] = kid
        elseif not kid.loop then kid.sharedWith = first end
        if self.openPaths[kid.rel] and not kid.loop then self:Open(kid) end
    end
    node.kids[i] = kid
    return kid
end

-- The rows on screen: { node } | { more = node } | { hiddenOf = node }.
function Tree:Rows()
    local rows = {}
    local function Flatten(node)
        local n = math.min(#node.keys, node.limit)
        for i = 1, n do
            local kid = self:Kid(node, i)
            rows[#rows + 1] = { node = kid }
            if kid.open then Flatten(kid) end
        end
        if #node.keys > node.limit then rows[#rows + 1] = { more = node } end
        if node.hidden and node.hidden > 0 then rows[#rows + 1] = { hiddenOf = node } end
    end
    if self.root.open then Flatten(self.root) end
    return rows
end

-- Opens the way to an entry given by its keys from the root (a search result). Returns the node, or
-- nil when it is no longer there.
function Tree:Reveal(keys)
    local node = self.root
    for _, k in ipairs(keys) do
        if not (node.open or self:Open(node)) then return nil end
        local idx
        for i, key in ipairs(node.keys) do
            if rawequal(key, k) then idx = i break end
        end
        if not idx then return nil end
        if idx > node.limit then node.limit = math.ceil(idx / EX.PAGE) * EX.PAGE end
        node = self:Kid(node, idx)
    end
    return node
end

-- Opens everything under node (first pages only), up to EX.EXPAND_LIMIT tables. Returns whether it
-- stopped at the limit.
function Tree:ExpandAll(node)
    local budget = EX.EXPAND_LIMIT
    local queue, head = { node }, 1
    while queue[head] do
        local n = queue[head]
        head = head + 1
        if self:Open(n) then
            budget = budget - 1
            if budget <= 0 then return true end
            for i = 1, math.min(#n.keys, n.limit) do
                local kid = self:Kid(n, i)
                if type(kid.value) == "table" and not kid.loop then queue[#queue + 1] = kid end
            end
        end
    end
    return false
end

function Tree:CollapseAll()
    self.openPaths = {}
    self.root.kids = {}
    self.root.limit = EX.PAGE
    self.opened = 0
    self.first = setmetatable({}, { __mode = "k" })
    if type(self.root.value) == "table" then self.first[self.root.value] = self.root end
    self.root.open = false
    self:Open(self.root)
end

-- The keys from the root to node.
function EX.KeysOf(node)
    local keys = {}
    while node and not node.isRoot do
        table.insert(keys, 1, node.key)
        node = node.parent
    end
    return keys
end

---------------------------------------------------------------------------
-- Walking a whole table a slice at a time (search, the share preview's personal-data check).
-- One job of each kind at a time; a job is cancelled by the next of its kind or by Cancel().
---------------------------------------------------------------------------
local BUDGET_MS = 4
local SLICE = 200
local clock = debugprofilestop or function() return GetTime() * 1000 end
local runner = CreateFrame("Frame")
local jobs = {}                       -- [kind] = { co, done }

local function RunJobs()
    local start = clock()
    -- A finished job's callback may start another, so the kinds are listed before any runs.
    local kinds = {}
    for kind in pairs(jobs) do kinds[#kinds + 1] = kind end
    for _, kind in ipairs(kinds) do
        local job = jobs[kind]
        while job and jobs[kind] == job do
            local ok, finished, result = coroutine.resume(job.co)
            if not ok then
                jobs[kind] = nil
                geterrorhandler()(finished)
                pcall(job.done, nil, "failed")
            elseif coroutine.status(job.co) == "dead" then
                jobs[kind] = nil
                local okDone, err = pcall(job.done, result)
                if not okDone then geterrorhandler()(err) end
            end
            if clock() - start >= BUDGET_MS then return end
        end
    end
    if next(jobs) == nil then runner:SetScript("OnUpdate", nil) end
end

function EX.Cancel(kind)
    if kind then jobs[kind] = nil else wipe(jobs) end
    if next(jobs) == nil then runner:SetScript("OnUpdate", nil) end
end

function EX.Busy(kind) return jobs[kind] ~= nil end

local function StartJob(kind, body, done)
    jobs[kind] = { co = coroutine.create(body), done = done }
    runner:SetScript("OnUpdate", RunJobs)
end
EX.StartJob = StartJob    -- setup/Cleanup.lua runs its counting and scanning in the same sliced runner

-- Calls visit(link, key, value, parentTable) for every entry under root in tree order (keys sorted as
-- in the tree), each table once, to EX.MAX_DEPTH. link: { up, key } chain to the entry's table.
-- visit returns true to stop. Returns visits, stopped, cutShort (the visit limit was reached).
local yield = coroutine.yield
local function Walk(root, visit, maxVisits)
    local seen = { [root] = true }
    local stack = { { t = root, keys = SD.Keys(root), i = 0, depth = 1, link = nil } }
    local visits = 0
    while #stack > 0 do
        local top = stack[#stack]
        top.i = top.i + 1
        local k = top.keys[top.i]
        if k == nil then
            stack[#stack] = nil
        else
            visits = visits + 1
            if visits > maxVisits then return visits - 1, false, true end
            if visits % SLICE == 0 and coroutine.running() then yield() end
            local v = rawget(top.t, k)
            if visit(top.link, k, v, top.t) then return visits, true, false end
            if type(v) == "table" and not seen[v] and top.depth < EX.MAX_DEPTH and Readable(v) then
                seen[v] = true
                stack[#stack + 1] = { t = v, keys = SD.Keys(v), i = 0, depth = top.depth + 1, link = { up = top.link, key = k } }
            end
        end
    end
    return visits, false, false
end
EX.Walk = Walk

local function LinkKeys(link, k)
    local keys = { k }
    while link do
        table.insert(keys, 1, link.key)
        link = link.up
    end
    return keys
end

local function PathFrom(rootPath, keys)
    local parts = { rootPath }
    for i, k in ipairs(keys) do parts[i + 1] = EX.PathPart(k) end
    return table.concat(parts)
end

-- What a search matches: a key, or a text, number or true/false value, ignoring case.
local function Matches(q, k, v)
    local kt = type(k)
    if not EX.IsSecret(k) then
        if kt == "string" and k:lower():find(q, 1, true) then return "key" end
        if (kt == "number" and EX.NumText(k):find(q, 1, true)) or (kt == "boolean" and tostring(k) == q) then return "key" end
    end
    if EX.IsSecret(v) then return nil end
    local vt = type(v)
    if vt == "string" and v:lower():find(q, 1, true) then return "value" end
    if vt == "number" and EX.NumText(v):find(q, 1, true) then return "value" end
    if vt == "boolean" and tostring(v) == q then return "value" end
end

-- Searches root for query, a slice each frame. done(result): { query, results = { { keys, path, match } },
-- visits, full (stopped at EX.SEARCH_RESULTS), cut (stopped at EX.SEARCH_VISITS) }. Replaces any search
-- still running. Returns false for an empty query.
function EX.Search(root, rootPath, query, done)
    EX.Cancel("search")
    local q = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" or type(root) ~= "table" then return false end
    StartJob("search", function()
        local results = {}
        local visits, stopped, cut = Walk(root, function(link, k, v)
            local how = Matches(q, k, v)
            if how then
                local keys = LinkKeys(link, k)
                results[#results + 1] = { keys = keys, path = PathFrom(rootPath, keys), match = how }
                return #results >= EX.SEARCH_RESULTS
            end
        end, EX.SEARCH_VISITS)
        return true, { query = q, results = results, visits = visits, full = stopped, cut = cut }
    end, done)
    return true
end

-- Personal-looking keys and values under root: done({ count, examples = { { path, why } }, cut }).
function EX.FindPersonal(root, rootPath, done)
    StartJob("personal", function()
        local count, examples = 0, {}
        local _, _, cut = Walk(root, function(link, k, v, parent)
            local why = EX.PersonalKey(k, link and link.key) or EX.PersonalValue(k, v, parent)
            if why then
                count = count + 1
                if #examples < 20 then
                    local keys = LinkKeys(link, k)
                    examples[#examples + 1] = { keys = keys, path = PathFrom(rootPath, keys), why = why }
                end
            end
        end, EX.SEARCH_VISITS)
        return true, { count = count, examples = examples, cut = cut }
    end, done)
end

---------------------------------------------------------------------------
-- Copying: a path, a value, and a readable text of a table (not an importable configuration)
---------------------------------------------------------------------------
-- A path from keys, with personal-looking keys hidden unless reveal.
function EX.MaskedPath(rootPath, keys, reveal)
    local parts, parent = { rootPath }, nil
    for i, k in ipairs(keys) do
        local why = not reveal and EX.PersonalKey(k, parent)
        parts[i + 1] = why and ("[" .. EX.Hidden(why) .. "]") or EX.PathPart(k)
        parent = k
    end
    return table.concat(parts)
end

-- The node's path, with personal-looking keys hidden unless reveal.
function EX.NodePath(node, reveal)
    if reveal then return node.path end
    local parts, n = {}, node
    while n and not n.isRoot do
        local why = EX.PersonalKey(n.key, n.parent and n.parent.key)
        table.insert(parts, 1, why and ("[" .. EX.Hidden(why) .. "]") or EX.PathPart(n.key))
        n = n.parent
    end
    table.insert(parts, 1, n and (n.maskedPath or n.path) or "")
    return table.concat(parts)
end

-- Why a node's own value is hidden right now, or nil.
function EX.NodeHidden(node, reveal)
    if reveal or node.isRoot then return nil end
    return EX.PersonalValue(node.key, node.value, node.parent and node.parent.value)
end

-- The full value of a primitive node, as copied (text unquoted; numbers exact).
function EX.ValueCopy(node, reveal)
    local v = node.value
    if EX.IsSecret(v) then return "<secret>" end
    local why = EX.NodeHidden(node, reveal)
    if why then return EX.Hidden(why), true end
    local t = type(v)
    if t == "string" then
        local s, cut = EX.Clip(v, EX.DETAIL_BYTES)
        return s, false, cut
    end
    if t == "number" then return EX.NumText(v) end
    if t == "boolean" then return tostring(v) end
    return "<" .. t .. ">"
end

-- Readable text of value, Lua-like, at most EX.DUMP_BYTES. mask: hide personal-looking keys and values.
-- key: value's own key (for the personal-data signs of what is directly in it).
-- Returns text, info { hidden, cut, loops, shared }.
function EX.Dump(value, path, mask, header, key)
    local out, bytes = {}, 0
    local info = { hidden = 0, cut = false, loops = 0, shared = 0 }
    local first = {}
    local function Put(s)
        if info.cut then return end
        if bytes + #s > EX.DUMP_BYTES then
            info.cut = true
            out[#out + 1] = ("\n-- cut here: the text stops at %s"):format(ST.FormatSize(EX.DUMP_BYTES))
            return
        end
        out[#out + 1] = s
        bytes = bytes + #s
    end
    local function Scalar(v)
        if EX.IsSecret(v) then return "<secret>" end
        local t = type(v)
        if t == "string" then return EX.Quote(v) end
        if t == "number" then return EX.NumText(v) end
        if t == "boolean" then return tostring(v) end
        return "<" .. t .. ">"
    end
    local function Key(k, parentKey)
        local why = mask and EX.PersonalKey(k, parentKey)
        if why then info.hidden = info.hidden + 1; return "[" .. EX.Hidden(why) .. "]" end
        if type(k) == "string" and k:find("^[%a_][%w_]*$") and not EX.IsSecret(k) then return k end
        return "[" .. Scalar(k) .. "]"
    end
    local function Write(t, p, indent, depth, onPath, myKey)
        if not Readable(t) then Put("<hidden by the game>") return end
        if depth > EX.MAX_DEPTH then Put(("<deeper than %d levels>"):format(EX.MAX_DEPTH)) return end
        local keys, secret, unsorted = SD.Keys(t)
        if #keys == 0 and secret == 0 then Put("{}") return end
        Put("{" .. (unsorted and "  -- too many entries to sort; stored order" or "") .. "\n")
        local pad = ("  "):rep(indent + 1)
        onPath[t] = true
        for _, k in ipairs(keys) do
            if info.cut then break end
            local v = rawget(t, k)
            local keyWhy = mask and EX.PersonalKey(k, myKey)
            local childPath = p .. (keyWhy and ("[" .. EX.Hidden(keyWhy) .. "]") or EX.PathPart(k))
            Put(pad .. Key(k, myKey) .. " = ")
            if type(v) == "table" then
                if onPath[v] then
                    info.loops = info.loops + 1
                    Put("<contains itself: " .. first[v] .. ">")
                elseif first[v] then
                    info.shared = info.shared + 1
                    Put("<same table as " .. first[v] .. ">")
                else
                    first[v] = childPath
                    Write(v, childPath, indent + 1, depth + 1, onPath, k)
                end
            else
                local why = mask and EX.PersonalValue(k, v, t)
                if why then info.hidden = info.hidden + 1; Put(EX.Hidden(why)) else Put(Scalar(v)) end
            end
            Put(",\n")
        end
        if secret > 0 then Put(pad .. ("-- %d entries hidden by the game\n"):format(secret)) end
        onPath[t] = nil
        Put(("  "):rep(indent) .. "}")
    end
    Put("-- " .. path .. "\n")
    if header then Put(header .. "\n") end
    if type(value) == "table" then
        first[value] = path
        Write(value, path, 0, 1, {}, key)
    else
        Put(Scalar(value))
    end
    Put("\n")
    return table.concat(out), info
end

local README = "-- A readable view of TwichUI's saved data. It is not an importable configuration."

-- What a copy action puts in the copy box, and a note saying what it is.
--   path      the node's full path
--   value     a value in full (not a table)
--   readable  the node as readable text: exact when reveal, else personal-looking values hidden, and it says so
--   support   always sanitized for asking for help, labelled as such; never the exact data
function EX.CopyText(kind, node, reveal)
    if kind == "path" then
        local text = EX.NodePath(node, reveal)
        return text, (not reveal and text:find("<hidden:", 1, true)) and "Parts that look personal are hidden. Reveal to copy the exact path." or "The exact path."
    elseif kind == "value" then
        if type(node.value) == "table" then return "", "It's a table. Use Readable for what's in it." end
        local text, hidden, cut = EX.ValueCopy(node, reveal)
        return text, hidden and "It looks personal and is hidden. Reveal to copy it."
            or (cut and ("The first " .. ST.FormatSize(EX.DETAIL_BYTES) .. " of the text.") or "The exact value.")
    elseif kind == "readable" then
        local body, info = EX.Dump(node.value, EX.NodePath(node, reveal), not reveal, nil, node.key)
        local head = README
        if info.hidden > 0 then
            head = head .. ("\n-- %d personal-looking values are hidden as <hidden: ...>, so this isn't the exact data. Reveal to include them."):format(info.hidden)
        end
        return head .. "\n" .. body, (info.hidden > 0 and "Personal-looking values hidden." or "Exact.") .. (info.cut and " Cut short at its size limit." or "")
    elseif kind == "support" then
        local body, info = EX.Dump(node.value, EX.NodePath(node, false), true, nil, node.key)
        return README .. "\n-- For support: character and friend names, character ids, Battle.net tags and your notes are replaced with <hidden: ...>"
            .. (" (%d here). The rest is as stored. It isn't the exact data, and it isn't what Send sends.\n"):format(info.hidden) .. body,
            "Sanitized copy for support: personal-looking values left out" .. (info.cut and "; cut short at its size limit." or ".")
    end
end

---------------------------------------------------------------------------
-- The share preview: the real messages, built by setup/Share.lua's own functions
---------------------------------------------------------------------------
EX.preview = nil          -- { pack, version, created, offer, data, root, sizes... } while the window shows it
local encoding            -- handle of the packing that measures it

local function MessagesFor(text)
    return #text <= COMM_MAX and 1 or math.ceil(#text / (COMM_MAX - 1))
end

-- Builds the preview from your saved setup, as for a friend who has none of it yet (they are sent
-- every part; a friend who already has some is sent only the changed parts, and the same "keep" list).
-- Nothing is sent, no transfer starts, no id is drawn, nothing is stored. Returns the preview, or nil
-- and why there is none.
function EX.BuildPreview()
    EX.ReleasePreview()
    local mine = ST.Mine()
    if not mine or not (next(mine.tables or {}) or mine.eui) then
        return nil, "You have no saved setup, so Send has nothing to send. Save one on the Share setup page."
    end
    local want = SortedKeys(mine.tables)
    local offer = SH.BuildOffer(mine, EX.PREVIEW_ID)
    local data = SH.BuildData(mine, EX.PREVIEW_ID, want, mine.editMode ~= nil)
    local p = {
        pack = mine, version = mine.version, created = mine.created, made = time(),
        offer = offer, data = data, root = { offer = offer, data = data }, want = #want,
    }
    local okOffer, offerText = pcall(SH.EncodeControl, offer)
    p.offerBytes = okOffer and #offerText or nil
    EX.preview = p
    encoding = SH.EncodeData(data, function(encoded)
        if EX.preview ~= p then return end
        local pieces, total = SH.LanePieces(EX.PREVIEW_ID, encoded)
        p.encoded, p.lanes, p.laneBytes, p.messages = #encoded, #pieces, total, 0
        for _, text in ipairs(pieces) do p.messages = p.messages + MessagesFor(text) end
        encoding = nil
        EX.Changed("preview")
    end, function(err)
        if EX.preview ~= p then return end
        p.encodeError = tostring(err)
        encoding = nil
        EX.Changed("preview")
    end)
    return p
end

function EX.ReleasePreview()
    if encoding then encoding.Cancel() encoding = nil end
    EX.Cancel("personal")
    EX.preview = nil
end

-- Whether the preview still shows what Send would send now; nil, or why not.
function EX.PreviewStale(p)
    p = p or EX.preview
    if not p then return nil end
    local mine = ST.Mine()
    if not mine then return "Your saved setup was deleted since this preview was made. Send has nothing to send now." end
    if mine ~= p.pack or mine.version ~= p.version or mine.created ~= p.created then
        return "Your saved setup changed since this preview was made. Rebuild it to see what Send sends now."
    end
end

-- Ticked in Share setup but not in the saved setup, or the other way round: Send uses the saved setup
-- until you save again. Returns the two lists (names).
function EX.SelectionDrift()
    local mine, db = ST.Mine(), ST.db
    local ticked, notSaved, notTicked = {}, {}, {}
    if not (mine and db) then return notSaved, notTicked end
    for name, sel in pairs(db.selection or {}) do
        local e = db.detected and db.detected[name]
        if sel and e and not e.huge and not R.Ellesmere.IsTable(name) then ticked[name] = true end
    end
    for name in pairs(ticked) do if not mine.tables[name] then notSaved[#notSaved + 1] = name end end
    for name in pairs(mine.tables) do if not ticked[name] then notTicked[#notTicked + 1] = name end end
    table.sort(notSaved); table.sort(notTicked)
    return notSaved, notTicked
end

-- What the preview holds and what the sharing code leaves out, by the rules it actually uses. Worked
-- out once per preview (it sizes every table).
-- { addons = { { title, owner, tables = { name }, bytes } }, eui, editMode, recommended, identity = { {field, value} },
--   excluded = { { name, why } }, rules = { text } }
function EX.ShareContents(p)
    if p.contents then return p.contents end
    local mine = p.pack
    local c = { addons = {}, excluded = {}, rules = {} }
    for _, g in ipairs(ST.PackByAddon(mine)) do
        local bytes = 0
        for _, name in ipairs(g.tables) do bytes = bytes + ST.SizeOf(mine.tables[name].data) end
        c.addons[#c.addons + 1] = { title = g.title, owner = g.owner, tables = g.tables, bytes = bytes }
    end
    c.eui = mine.eui and { name = mine.eui.name, version = mine.eui.euiVersion, chars = type(mine.eui.str) == "string" and #mine.eui.str or 0 }
    c.editMode = mine.editMode and { name = mine.editModeName, chars = #mine.editMode }
    -- TwichUI's own settings: the features and the number of values, never the values themselves
    if type(mine.twichui) == "table" and mine.twichui.status == "ok" and type(mine.twichui.groups) == "table" then
        local TC = R.TwichConfig
        local features, values = {}, 0
        for id, data in pairs(mine.twichui.groups) do
            local g = TC and TC.Group(id)
            features[#features + 1] = g and g.label or id
            values = values + CountTables(data)
        end
        table.sort(features)
        c.twichui = { features = features, bytes = ST.SizeOf(mine.twichui.groups), slots = values }
    end
    c.recommended = CountTables(mine.addons)
    c.identity = {
        { "offer.from", p.offer.from, "your character's name, so they know who it's from" },
        { "data.meta.source", p.data.meta.source, "your character and realm, used to point their addons at the right profile" },
        { "data.meta.sourceName", p.data.meta.sourceName, "your character's name, shown to them" },
    }
    -- Found by the last settings scan but not in the saved setup, and why (the same tests SaveMine uses).
    local db = ST.db
    for _, name in ipairs(SortedKeys(db and db.detected or {})) do
        if not mine.tables[name] then
            local e = db.detected[name]
            local why
            if R.Ellesmere.IsTable(name) then why = "EllesmereUI's whole table is never shared; one EllesmereUI profile can be, instead"
            elseif e.huge then why = "too big to share"
            elseif db.selection[name] then why = "ticked after the setup was saved"
            else why = "not ticked" end
            c.excluded[#c.excluded + 1] = { name = name, why = why }
        end
    end
    c.rules = {
        "TwichUI's own saved variables are never sent as tables: the settings scan skips every name starting with TwichUI, and a receiving TwichUI refuses one. Backups, Undo copies, received setups, the Journey Chronicle and map pins are not part of a setup.",
        "TwichUI's own settings are a part of a setup of their own, only when ticked: the values of the features you ticked, by name (setup/TwichConfig.lua). Positions, per-character records, anything that acts for you and anything that decides what you send or accept stay behind.",
        "Anything in an addon's settings that isn't plain data (code, game objects) is left out when the setup is saved.",
        "Transfers in progress, diagnostics, previews and scan results: kept in memory only, never in a setup.",
        "Your Edit Mode layout is included only when \"Include my Edit Mode layout\" was ticked as you saved.",
        "Addons in the recommended list are named with versions and download links; their settings go only if ticked above.",
    }
    p.contents = c
    return c
end

-- Done with everything the window held: searches, the preview, cached names.
function EX.Release()
    EX.Cancel()
    EX.ReleasePreview()
    own = nil
end

---------------------------------------------------------------------------
-- Summaries for the top of the window: { { label, value } }, notes
---------------------------------------------------------------------------
local function Line(list, label, value) list[#list + 1] = { label, value } end
local function Size(t) return ("about %s (an estimate of the data, not the saved file)"):format(ST.FormatSize(ST.SizeOf(t))) end

local Summary
-- A damaged record still gets a summary line rather than an error.
function EX.Summary(source, root, reveal)
    local ok, lines = pcall(Summary, source, root, reveal)
    if ok then return lines end
    return { { "Summary", "couldn't be worked out: some of it isn't in the expected form. The tree shows it as stored." } }
end

Summary = function(source, root, reveal)
    local lines = {}
    if type(root) ~= "table" then
        Line(lines, "Value", EX.ValueText(root))
        return lines
    end
    local kind = source.kind
    local function Name(v)
        if type(v) ~= "string" then return "not recorded" end
        return reveal and v or EX.Hidden("a character's name")
    end
    if source.id == "settings" then
        local P = R.Persist
        Line(lines, "Schema", ("%s (this TwichUI writes %s)"):format(type(root.schema) == "number" and EX.NumText(root.schema) or "not recorded", P and P.SCHEMA or "?"))
        Line(lines, "Groups", tostring(CountTables(root)))
        Line(lines, "Size", Size(root))
    elseif kind == "restore" then
        Line(lines, "Created", When(root.created) or "not recorded")
        if root.imported then Line(lines, "Imported", When(root.imported) or "?") end
        Line(lines, "Made by", Name(root.sourceName or root.source))
        Line(lines, "Contains", ("%d addons, %d settings tables"):format(ST.CountAddons(root), CountTables(root.tables)))
        Line(lines, "Version", "Restore points carry no version number; each table is the addon's own, as it was saved")
        Line(lines, "Size", Size(root.tables))
    elseif kind == "undo" then
        Line(lines, "Created", When(root.created) or "not recorded")
        Line(lines, "Contains", ("%d settings tables"):format(CountTables(root.tables)))
        Line(lines, "Size", Size(root))
    elseif kind == "mine" then
        Line(lines, "Saved", When(root.created) or "not recorded")
        Line(lines, "Version", ("%s (format %s)"):format(tostring(root.version or "?"), tostring(root.format or "?")))
        Line(lines, "Contains", ("%d addons%s%s%s"):format(ST.CountAddons(root), root.eui and ", an EllesmereUI profile" or "",
            type(root.twichui) == "table" and ", TwichUI's own settings" or "", root.editMode and ", an Edit Mode layout" or ""))
        Line(lines, "Size", Size(root))
    elseif kind == "received" then
        Line(lines, "From", Name(root.sourceName or root.sender))
        Line(lines, "Received", When(root.received) or "not recorded")
        Line(lines, "Version", tostring(root.version or "?"))
        Line(lines, "Contains", ("%d addons%s%s"):format(ST.CountAddons(root), root.eui and ", an EllesmereUI profile" or "",
            type(root.twichui) == "table" and ", TwichUI's own settings" or ""))
        Line(lines, "Size", Size(root))
    elseif kind == "chronicle" then
        local chars, entries, notes = 0, 0, 0
        for _, rec in next, type(root.chars) == "table" and root.chars or {} do
            chars = chars + 1
            for _, e in ipairs(type(rec) == "table" and type(rec.entries) == "table" and rec.entries or {}) do
                entries = entries + 1
                if type(e) == "table" and e.kind == "note" then notes = notes + 1 end
            end
        end
        Line(lines, "Version", ("%s (this TwichUI writes %s)"):format(tostring(root.version or "not recorded"), R.Persist and R.Persist.CHRONICLE_VERSION or "?"))
        Line(lines, "Contains", ("%d characters, %d entries, %d of them your notes"):format(chars, entries, notes))
        Line(lines, "Size", Size(root))
    else
        Line(lines, "Entries", tostring(CountTables(root)))
        Line(lines, "Size", Size(root))
    end
    return lines
end
