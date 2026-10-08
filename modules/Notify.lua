-- TwichUI: notification coordinator
-- The zone arrival card, the new training card, the friend login card and the Welcome Back
-- card each decide for themselves that something is worth showing, then hand the request
-- here. This decides only WHEN each one may start, so that two cards never fight over the
-- same part of the screen. It detects nothing and draws nothing, and nothing in it is saved:
-- a reload or a loading screen starts with an empty queue.
--
-- Where cards go. Each kind registers bounds(payload): the rectangle its card covers, worked
-- out from its own saved place and size each time it is asked (never kept), so moving a card in
-- Edit Mode or changing the UI scale or resolution is picked up by the next look. Two cards
-- conflict when their rectangles, each padded by GAP, intersect; cards that don't conflict show
-- together. Kinds with no known rectangle conflict with everything. Nothing here moves a card.
-- With the default places the zone, training and Welcome Back cards share the top of the screen
-- and take turns; the friend card, bottom left, is on its own.
--
-- Rules:
--  Order      Higher priority first (real notices, then Welcome Back, then previews), then
--             first come, first served. A waiting notice never starts ahead of an earlier one it
--             would overlap.
--  Capacity   At most MAX_QUEUE wait. When full, the oldest of the lowest priority is let go; a
--             newcomer that ranks below everything waiting is refused.
--  Expiry     A waiting notice is discarded once its time to live has passed, or when its own
--             valid() says it no longer applies. A shown card is freed by its renderer finishing,
--             or, if that never comes (a hidden frame, an interrupted animation), by a single
--             timer GRACE seconds after its expected display time.
--  Duplicates Same kind and same event identity as a notice already waiting or showing: dropped.
--             Previews have their own identities and nothing is remembered once a card is done.
--  Replacing  A request marked replace takes the place of an older waiting or showing notice of
--             its kind (the zone and training cards already behaved this way).
--  Welcome    The Welcome Back card is a bookmark, not an alert. It has the lowest real priority
--             and yields: a real notice that needs its area dismisses it instead of waiting for
--             its ten seconds, so it can never hold up the queue.
--  Loading    Leaving the world clears the queue and every card. Notices sent while loading wait
--             until the world is entered, within their time to live. Combat clears previews (listened
--             for only while one exists).
--  Previews   Sent through the same path with synthetic data and preview = true. They rank below
--             everything real: any real notice drops the waiting previews and dismisses a
--             showing one it would overlap. They skip the outside checks (combat, banners) because
--             the player asked, and show above the Settings panel while they run.

local R = TwichUI
local N = {}
R.Notify = N

local MAX_QUEUE = 6
local GAP = 12              -- pixels kept between two cards before they are taken as overlapping
local RETRY = 2             -- seconds between looks while combat or a game banner holds a notice back
local GRACE = 3             -- seconds past a card's expected display time before its place is taken as free
local DEFAULT_TTL, DEFAULT_HOLD = 10, 12

N.PRIORITY = { preview = 0, low = 1, normal = 2 }
-- Above the Settings panel (DIALOG), so a preview can be seen while the options are open.
N.PREVIEW_STRATA = "FULLSCREEN_DIALOG"

local specs = {}            -- [kind] = registration
local order = {}            -- kinds, in registration order
local queue = {}            -- waiting notices, in the order they were sent
local active = {}           -- [kind] = the notice being shown
local seq = 0
local inWorld = true
local retryScheduled = false
local pumping, again = false, false
local listening = false       -- the world listeners are registered (set by the init hook at the end)

-- Counts since the game started, for /tui diagnostics: integers keyed by a fixed reason or kind, never
-- by an id. Notices are traced (kind and reason only) while tracing is on.
local stats = { shown = {}, dropped = {}, refused = {} }
local function Count(group, key) group[key] = (group[key] or 0) + 1 end

local function Trace(code, notice, detail)
    local D = R.Diag
    if D and D.Tracing() then
        D.Trace("notify", code, notice.kind .. (detail and (" " .. detail) or ""), nil, notice.preview)
    end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

-- spec: {
--   label     = "Zone arrival",                    shown on the preview buttons
--   show      = function(payload, ctx) -> truthy   starts the card; ctx.preview is true for a preview.
--                                                  Plays the notice's sound, if it has one, only now.
--   dismiss   = function()                         stops and hides the card at once; calls N.Finished(kind)
--   bounds    = function(payload) -> l, b, r, t    screen rectangle in UIParent units (optional)
--   hold      = function(payload) -> seconds       the card's expected time on screen (optional)
--   ready     = function() -> bool                 false while combat or a game banner is in the way (optional)
--   sample    = function() -> payload              synthetic data for previews (optional)
--   yields    = true                               gives way to any real notice that needs its area
-- }
function N.Register(kind, spec)
    if not specs[kind] then order[#order + 1] = kind end
    specs[kind] = spec
end

function N.Kinds()
    local list = {}
    for i, kind in ipairs(order) do list[i] = { kind = kind, label = specs[kind].label, sample = specs[kind].sample ~= nil } end
    return list
end

---------------------------------------------------------------------------
-- Where cards are
---------------------------------------------------------------------------

-- True when two { l, b, r, t } rectangles, each padded by gap, intersect. A nil rectangle is unknown
-- and counts as overlapping everything.
function N.Overlap(a, b, gap)
    if not a or not b then return true end
    gap = gap or GAP
    return a[1] - gap < b[3] and b[1] - gap < a[3] and a[2] - gap < b[4] and b[2] - gap < a[4]
end

local function Rect(notice)
    local bounds = specs[notice.kind].bounds
    if not bounds then return nil end
    local ok, l, b, r, t = pcall(bounds, notice.payload)
    if ok and type(l) == "number" and type(b) == "number" and type(r) == "number" and type(t) == "number" then
        return { l, b, r, t }
    end
    return nil
end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------
local function Ranks(a, b)   -- true when a goes before b
    if a.priority ~= b.priority then return a.priority > b.priority end
    return a.seq < b.seq
end

local function Remove(list, notice)
    for i = #list, 1, -1 do
        if list[i] == notice then table.remove(list, i) return end
    end
end

-- Lets a waiting notice go without showing it, and says why to whoever asked to be told.
-- reasons: "expired", "stale", "full", "replaced", "real-event", "cancelled", "cleared", "loading"
local function Discard(notice, reason)
    Remove(queue, notice)
    Count(stats.dropped, notice.preview and ("preview " .. reason) or reason)
    Trace("dropped", notice, reason)
    if notice.onDrop then pcall(notice.onDrop, reason) end
end

-- Stops a showing notice at once and frees its place.
local function Dismiss(kind)
    local notice = active[kind]
    if not notice then return end
    active[kind] = nil
    local dismiss = specs[kind].dismiss
    if dismiss then
        local ok, err = pcall(dismiss)
        if not ok then geterrorhandler()(err) end
    end
end

local Pump

-- Previews make way for combat. That is listened for only while one is waiting or showing.
local watchingCombat = false
local function WatchCombat()
    local wanted = false
    for _, notice in ipairs(queue) do
        if notice.preview then wanted = true end
    end
    for _, notice in pairs(active) do
        if notice.preview then wanted = true end
    end
    if wanted and not watchingCombat then
        watchingCombat = true
        R:On("PLAYER_REGEN_DISABLED", N.ClearPreviews)
    elseif not wanted and watchingCombat then
        watchingCombat = false
        R:Off("PLAYER_REGEN_DISABLED", N.ClearPreviews)
    end
end

-- The renderer calls this whenever its card is gone, however that came about. Safe to call at any time.
function N.Finished(kind)
    if active[kind] then
        active[kind] = nil
        Pump()
    end
end

local function Expected(notice)
    local hold = specs[notice.kind].hold
    local ok, seconds = true, nil
    if hold then ok, seconds = pcall(hold, notice.payload) end
    return (ok and type(seconds) == "number" and seconds > 0) and seconds or DEFAULT_HOLD
end

local function Start(notice)
    local spec = specs[notice.kind]
    local ok, started = pcall(spec.show, notice.payload, { preview = notice.preview })
    if not ok then geterrorhandler()(started) end
    if not (ok and started) then return false end
    active[notice.kind] = notice
    Count(stats.shown, notice.preview and (notice.kind .. " preview") or notice.kind)
    Trace("shown", notice)
    -- If the card never reports back, its place is freed once it has certainly run its course.
    C_Timer.After(Expected(notice) + GRACE, function()
        if active[notice.kind] == notice then
            Dismiss(notice.kind)
            Pump()
        end
    end)
    return true
end

local function Ready(notice)
    if notice.preview then return true end
    local ready = specs[notice.kind].ready
    if not ready then return true end
    local ok, result = pcall(ready)
    return ok and result and true or false
end

local function Step()
    local now = GetTime()
    for i = #queue, 1, -1 do
        local notice = queue[i]
        local valid = true
        if notice.valid then
            local ok, result = pcall(notice.valid)
            valid = ok and result and true or false
        end
        if now >= notice.expires then Discard(notice, "expired") elseif not valid then Discard(notice, "stale") end
    end
    if not inWorld or #queue == 0 then return end

    table.sort(queue, Ranks)
    local held = {}         -- rectangles of earlier notices that are still waiting for their turn
    local outside = false   -- something is waiting only on combat or a banner
    local i = 1
    while i <= #queue do
        local notice = queue[i]
        local started = false
        if not Ready(notice) then
            outside = true
        else
            local rect = Rect(notice)
            local blocked = false
            for _, other in ipairs(held) do
                if N.Overlap(rect, other) then blocked = true break end
            end
            if not blocked then
                -- Showing cards in the way: previews give way to anything real, and Welcome Back to any
                -- real notice. Anything else makes this one wait.
                local yield = {}
                for kind, shown in pairs(active) do
                    if kind == notice.kind or N.Overlap(rect, Rect(shown)) then   -- one card per kind, wherever it is
                        if (shown.preview and not notice.preview) or (specs[kind].yields and not notice.preview) then
                            yield[#yield + 1] = kind
                        else
                            blocked = true
                        end
                    end
                end
                if not blocked then
                    for _, kind in ipairs(yield) do Dismiss(kind) end
                    table.remove(queue, i)
                    started = true
                    if not Start(notice) then again = true end
                end
            end
            if blocked then held[#held + 1] = rect or false end
        end
        if not started then i = i + 1 end
    end
    if outside and not retryScheduled then
        retryScheduled = true
        C_Timer.After(RETRY, function()
            retryScheduled = false
            Pump()
        end)
    end
end

-- Looks at the queue and starts what can start. Called whenever something that could change the
-- answer happens: a request, a card finishing, a card being moved, the world being entered.
function Pump()
    if pumping then again = true return end
    pumping = true
    local rounds = 0
    repeat
        again = false
        rounds = rounds + 1
        Step()
    until not again or rounds > MAX_QUEUE + 2
    pumping = false
    WatchCombat()
end

N.Poke = Pump   -- a card's place or size changed: waiting notices are looked at again

---------------------------------------------------------------------------
-- Sending a notice
---------------------------------------------------------------------------

-- request: {
--   kind     registered kind
--   id       the event's identity within its kind (a zone name, a level, the friends who came online)
--   payload  whatever the renderer needs, already worked out
--   ttl      seconds it may wait before being let go (default 10)
--   priority N.PRIORITY value (default normal; previews are always lowest)
--   valid    optional function; false means it no longer applies and it is discarded
--   onDrop   optional function(reason), called if it is let go without being shown
--   replace  take the place of an older waiting or showing notice of this kind
--   preview  true for a settings preview
-- }
-- Returns true when it was accepted (it may start at once), or false and why: "unknown", "duplicate" or "full".
function N.Submit(request)
    local spec = specs[request.kind]
    if not spec then Count(stats.refused, "unknown") return false, "unknown" end
    local preview = request.preview and true or false
    local now = GetTime()
    -- Whatever has run out of time makes no claim on the queue.
    for i = #queue, 1, -1 do
        if now >= queue[i].expires then Discard(queue[i], "expired") end
    end
    local id = tostring(request.id or request.kind)
    local function Same(notice)
        return notice.kind == request.kind and notice.id == id and notice.preview == preview
    end
    local function Duplicate()
        Count(stats.refused, preview and "preview duplicate" or "duplicate")
        Trace("refused", request, "duplicate")
        return false, "duplicate"
    end
    for _, notice in ipairs(queue) do
        if Same(notice) then return Duplicate() end
    end
    if active[request.kind] and Same(active[request.kind]) then return Duplicate() end

    if request.replace then
        for i = #queue, 1, -1 do
            if queue[i].kind == request.kind and queue[i].preview == preview then Discard(queue[i], "replaced") end
        end
        if active[request.kind] and active[request.kind].preview == preview then Dismiss(request.kind) end
    end
    -- A real event comes first: waiting previews are let go (a showing one gives way in Pump if it is in the way).
    if not preview then
        for i = #queue, 1, -1 do
            if queue[i].preview then Discard(queue[i], "real-event") end
        end
    end

    seq = seq + 1
    local notice = {
        kind = request.kind, id = id, payload = request.payload, preview = preview, seq = seq,
        priority = preview and N.PRIORITY.preview or request.priority or N.PRIORITY.normal,
        expires = now + (request.ttl or DEFAULT_TTL), valid = request.valid, onDrop = request.onDrop,
    }
    if #queue >= MAX_QUEUE then
        -- Full: the oldest of the lowest priority makes room, unless the newcomer ranks below them all.
        local worst = queue[1]
        for _, queued in ipairs(queue) do
            if queued.priority < worst.priority or (queued.priority == worst.priority and queued.seq < worst.seq) then worst = queued end
        end
        if notice.priority < worst.priority then
            Count(stats.refused, preview and "preview full" or "full")
            Trace("refused", notice, "full")
            return false, "full"
        end
        Discard(worst, "full")
    end
    queue[#queue + 1] = notice
    Trace("queued", notice)
    Pump()
    return true
end

---------------------------------------------------------------------------
-- Taking notices back
---------------------------------------------------------------------------

-- Lets go of a kind's real notices, waiting and showing (its feature was turned off, or the world changed).
function N.Cancel(kind)
    for i = #queue, 1, -1 do
        if queue[i].kind == kind and not queue[i].preview then Discard(queue[i], "cancelled") end
    end
    if active[kind] and not active[kind].preview then Dismiss(kind) end
    Pump()
end

-- Stops every preview, waiting or showing.
function N.ClearPreviews()
    for i = #queue, 1, -1 do
        if queue[i].preview then Discard(queue[i], "cleared") end
    end
    for kind, notice in pairs(active) do
        if notice.preview then Dismiss(kind) end
    end
    Pump()
end

-- Everything, as when a loading screen starts.
local function Reset()
    for i = #queue, 1, -1 do Discard(queue[i], "loading") end
    for kind in pairs(active) do Dismiss(kind) end
    WatchCombat()
end

---------------------------------------------------------------------------
-- Previews. Synthetic data through the same renderers; nothing is recorded, saved or marked as shown.
---------------------------------------------------------------------------
local PREVIEW_TTL = 45

-- Whether previews play their notice's sound (TwichUIDB.ui.previewSounds, off unless chosen).
function N.PreviewSounds()
    return TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.previewSounds == true or false
end

-- Whether a card should play its sound now: a real one when the feature's own sound setting is on, a
-- preview only when previews are allowed sound as well.
function N.SoundWanted(preview, featureSound)
    if not featureSound then return false end
    return not preview or N.PreviewSounds()
end

-- Takes back this kind's previews, waiting and showing.
function N.DropPreviews(kind)
    for i = #queue, 1, -1 do
        if queue[i].kind == kind and queue[i].preview then Discard(queue[i], "cleared") end
    end
    if active[kind] and active[kind].preview then Dismiss(kind) end
end

-- Shows one kind's sample card. Without an id, a preview already up for the kind starts over.
-- extra: fields added to the sample payload (the friend card test in /tui diagnostics asks for the chime this way).
function N.Preview(kind, id, extra)
    local spec = specs[kind]
    if not (spec and spec.sample) then return false, "unknown" end
    if not id then N.DropPreviews(kind) end
    local payload = spec.sample()
    for key, value in pairs(extra or {}) do payload[key] = value end
    return N.Submit({ kind = kind, id = id or "preview", payload = payload, ttl = PREVIEW_TTL, preview = true })
end

-- The same sample notices, in a fixed order, with one repeat: shows queueing, cards in separate places
-- showing together, and a duplicate being dropped. Returns how many were sent and how many repeats dropped.
local SEQUENCE = { "arrival", "friend", "training", "arrival", "welcome" }

function N.PreviewSequence()
    N.ClearPreviews()
    local sent, dropped = 0, 0
    for i, kind in ipairs(SEQUENCE) do
        -- The fourth is the first again, with the same identity, so it is a duplicate.
        local ok, why = N.Preview(kind, (i == 4 and "sequence-arrival" or ("sequence-" .. kind)))
        if ok then sent = sent + 1 elseif why == "duplicate" then dropped = dropped + 1 end
    end
    return sent, dropped
end

---------------------------------------------------------------------------
-- The world
---------------------------------------------------------------------------
local function OnLeavingWorld()
    inWorld = false
    Reset()
end

local function OnEnteringWorld()
    inWorld = true
    Pump()
end

-- Waiting and showing notices, for tests. Reads only. The ids may identify friends, so reports use
-- N.Snapshot instead.
function N.State()
    local waiting, shown = {}, {}
    for i, notice in ipairs(queue) do waiting[i] = notice.kind .. ":" .. notice.id end
    for kind, notice in pairs(active) do shown[#shown + 1] = kind .. ":" .. notice.id end
    table.sort(shown)
    return { waiting = waiting, active = shown, inWorld = inWorld }
end

-- For /tui diagnostics: the coordinator's state with no ids, and counts since the game started. Reads only.
function N.Snapshot()
    local waiting, shown = {}, {}
    for _, notice in ipairs(queue) do
        local key = notice.kind .. (notice.preview and " (preview)" or "")
        waiting[key] = (waiting[key] or 0) + 1
    end
    for kind, notice in pairs(active) do shown[kind] = notice.preview and "preview" or "real" end
    local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
    return {
        listening = listening, inWorld = inWorld, capacity = MAX_QUEUE, queued = #queue,
        waiting = waiting, active = shown, kinds = N.Kinds(),
        watchingCombat = watchingCombat, retryScheduled = retryScheduled,
        previewSounds = N.PreviewSounds(),
        shown = Copy(stats.shown), dropped = Copy(stats.dropped), refused = Copy(stats.refused),
    }
end

R:OnInit(function()
    listening = true
    R:On("PLAYER_LEAVING_WORLD", OnLeavingWorld)
    R:On("PLAYER_ENTERING_WORLD", OnEnteringWorld)
end)
