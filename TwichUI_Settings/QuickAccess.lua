-- TwichUI Settings: Quick access (docs/quick-access.md)
-- The left-hand list offers up to three shortcuts to the features this character opens most. This file is the
-- whole of the learning: it counts a feature's visits, scores them, and picks. It has no frames and no events; the
-- window (Window.lua) says when a visit happened and when to look again, and draws the result.
--
--   TwichUIDB.quickAccess = { v = 1, chars = { ["Name - Realm"] = { seen = time, f = { [pageKey] = { s, t } } } } }
--   account-wide, never in a profile, a share or a backup (Restore.OWN_LEFT_OUT, TwichConfig.LOCAL): what one
--   character opens is a habit, not a setting, so two characters on one profile learn separately.
--   s = the feature's score as of t, t = when it was last counted (time()). The score at any later moment is s
--   halved for every HALF_LIFE since t, so nothing needs updating while a feature goes unused.
--
-- A visit is counted at most once per COOLDOWN for a feature, so flicking through pages adds nothing. Every count
-- adds 1 to the decayed score: a feature used over several sessions outranks one opened once, and an old habit
-- fades without anything deleting it. A feature needs MIN_SCORE (a second visit, in effect) before it is offered.
--
-- Reading never writes. A record from a newer TwichUI (v higher than this one knows) is never read or changed,
-- and nothing is written while TwichUIDB is held (Persist.lua). Everything written is bounded: MAX_FEATURES
-- records per character, MAX_CHARS characters, and a record whose score has faded below FORGET is dropped.

local R = TwichUI
local QA = {}
R.SettingsQuick = QA

QA.VERSION = 1
QA.MAX_SHOWN = 3
QA.HALF_LIFE = 14 * 86400   -- seconds for a score to halve
QA.COOLDOWN = 10 * 60       -- seconds before the same feature counts again
QA.MIN_SCORE = 1.5          -- decayed score a feature needs to be offered
QA.KEEP = 1.25              -- a shortcut already shown outranks a challenger only if the challenger is not 25% stronger
QA.FORGET = 0.05            -- below this a record is dropped on the next write
QA.MAX_FEATURES = 24
QA.MAX_CHARS = 30
local SCORE_CAP = 100

QA.Now = function() return time() end

-- the shortcuts shown now, in order (kept for the session so the list does not reshuffle while the window is used)
QA.shown = {}

local function Held() return R.Persist ~= nil and R.Persist.IsHeld("TwichUIDB") end

local function Finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

-- "Name - Realm", or nil while the game can't say
local function CharKey()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. " - " .. realm
end
QA.CharKey = CharKey

-- A record's score and time, or nil when it is not usable.
local function Read(rec)
    if type(rec) ~= "table" then return nil end
    local s, t = rec.s, rec.t
    if not (Finite(s) and Finite(t)) or s <= 0 or t <= 0 then return nil end
    return math.min(s, SCORE_CAP), t
end

-- What a score of s as of t is worth at `now` (a clock that moved back does not make it grow).
function QA.Decayed(s, t, now)
    local age = now - t
    if age <= 0 then return s end
    return s * 0.5 ^ (age / QA.HALF_LIFE)
end

---------------------------------------------------------------------------
-- The saved record
---------------------------------------------------------------------------
-- The saved root, or nil when it cannot be used: saved data not there, held, or written by a newer TwichUI.
-- create: make it (and put right a root of the wrong shape: it holds only a habit, nothing worth keeping).
local function Root(create)
    if Held() or type(TwichUIDB) ~= "table" then return nil end
    local q = TwichUIDB.quickAccess
    if type(q) ~= "table" then
        if not create then return nil end
        q = { v = QA.VERSION, chars = {} }
        TwichUIDB.quickAccess = q
        return q
    end
    if type(q.v) == "number" and q.v > QA.VERSION then return nil end
    if create then
        if q.v ~= QA.VERSION then q.v = QA.VERSION end
        if type(q.chars) ~= "table" then q.chars = {} end
    elseif type(q.chars) ~= "table" then
        return nil
    end
    return q
end

-- This character's records ({ [pageKey] = { s, t } }), or nil when there are none to read.
function QA.Records()
    local q, ck = Root(false), CharKey()
    local ch = q and ck and q.chars[ck]
    return type(ch) == "table" and type(ch.f) == "table" and ch.f or nil
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Drops the records that have faded away, then the weakest while there are too many.
local function PruneFeatures(f, now)
    for key, rec in pairs(f) do
        local s, t = Read(rec)
        if type(key) ~= "string" or not s or QA.Decayed(s, t, now) < QA.FORGET then f[key] = nil end
    end
    while Count(f) > QA.MAX_FEATURES do
        local weakest, low
        for key, rec in pairs(f) do
            local s, t = Read(rec)
            local v = QA.Decayed(s, t, now)
            if not low or v < low or (v == low and key < weakest) then weakest, low = key, v end
        end
        f[weakest] = nil
    end
end

-- Forgets the character that has not been used for longest while there are too many.
local function PruneChars(q, keep)
    while Count(q.chars) > QA.MAX_CHARS do
        local oldest, at
        for ck, ch in pairs(q.chars) do
            if ck ~= keep then
                local seen = type(ch) == "table" and Finite(ch.seen) and ch.seen or 0
                if not at or seen < at or (seen == at and tostring(ck) < tostring(oldest)) then oldest, at = ck, seen end
            end
        end
        if oldest == nil then return end
        q.chars[oldest] = nil
    end
end

---------------------------------------------------------------------------
-- Counting a visit
---------------------------------------------------------------------------
-- Counts one visit to a feature (the page's top-level key; the caller has already chosen which pages are
-- features). Returns true when it was counted: false inside the cooldown, or when nothing can be saved now.
function QA.Visit(key)
    if type(key) ~= "string" or key == "" then return false end
    local ck = CharKey()
    local q = ck and Root(true)
    if not q then return false end
    local now = QA.Now()
    local ch = q.chars[ck]
    if type(ch) ~= "table" then ch = {}; q.chars[ck] = ch end
    if type(ch.f) ~= "table" then ch.f = {} end
    local s, t = Read(ch.f[key])
    if s and now >= t and now - t < QA.COOLDOWN then return false end
    local score = (s and QA.Decayed(s, t, now) or 0) + 1
    ch.f[key] = { s = math.floor(math.min(score, SCORE_CAP) * 1000 + 0.5) / 1000, t = now }
    ch.seen = now
    PruneFeatures(ch.f, now)
    PruneChars(q, ck)
    return true
end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------
-- The keys to offer, best first (at most MAX_SHOWN). records: { [pageKey] = { s, t } }; eligible(key): whether the
-- key is a feature that can be offered now; previous: the keys offered until now, in order.
--   * a feature must have faded no lower than MIN_SCORE, so a single visit offers nothing;
--   * a shortcut already shown outranks a challenger unless the challenger is KEEP times stronger, and the ones
--     that stay keep their order, so using the window does not shuffle it;
--   * near-equal scores (to a tenth) are ordered by what is shown already, then the later visit, then the key, so the
--     order is always the same.
function QA.Pick(records, now, eligible, previous)
    local was = {}
    for _, key in ipairs(previous or {}) do was[key] = true end
    local list = {}
    for key, rec in pairs(type(records) == "table" and records or {}) do
        if type(key) == "string" and eligible(key) then
            local s, t = Read(rec)
            if s then
                local score = QA.Decayed(s, t, now)
                if score >= QA.MIN_SCORE then
                    local rank = score * (was[key] and QA.KEEP or 1)
                    list[#list + 1] = { key = key, rank = math.floor(rank * 10 + 0.5) / 10, last = t, was = was[key] == true }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.was ~= b.was then return a.was end
        if a.last ~= b.last then return a.last > b.last end
        return a.key < b.key
    end)
    local chosen, order = {}, {}
    for i = 1, math.min(QA.MAX_SHOWN, #list) do chosen[list[i].key] = true; order[i] = list[i].key end
    local out = {}
    for _, key in ipairs(previous or {}) do
        if chosen[key] then out[#out + 1] = key; chosen[key] = nil end
    end
    for _, key in ipairs(order) do
        if chosen[key] then out[#out + 1] = key; chosen[key] = nil end
    end
    return out
end

-- The shortcuts for this character now (and remembered, so the next look keeps what is stable).
function QA.Suggest(eligible)
    QA.shown = QA.Pick(QA.Records(), QA.Now(), eligible, QA.shown)
    return QA.shown
end

-- Whether a page may be offered: a top-level page of a feature group (not Home, not the configuration pages),
-- that drew, and that the list does not already carry (pinned: a set of page keys).
function QA.Eligible(page, pinned)
    return page ~= nil and not page.parent and not page.failed and not pinned[page.key]
        and page.group ~= "home" and page.group ~= "config"
end
