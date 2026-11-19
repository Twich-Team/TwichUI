-- Exact cash correlation for the EXISTING auction controllers. No native transaction is sent here.
-- Quotes/requests alone prove nothing. Completion + one newly observed debit of the quoted amount are required.
-- Native transaction hooks only detect competing operations; outcome events remain owned by the controllers.
local R, L = TwichUI, TwichUI.Ledger
local A = {}
R.AuctionLedger = A
local pending, timer, settle, sending
local active, blocked, hooked = false, false, false
local hooks = {}
local serial = 0
local watching = {}
local stats = { attributed = 0, noMoney = 0, mismatch = 0, ambiguous = 0, expired = 0, interrupted = 0, observerError = 0 }
local Try
local function Int(v, lo)
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" or not tostring(v):find("^[%d%.eE%+%-]+$") or v < lo or v > L.MAX_MONEY or math.floor(v) ~= v then return nil end
    return v
end
local function Now()
    local n = GetTime and GetTime()
    if issecretvalue and issecretvalue(n) then return nil end
    if type(n) == "number" and n >= 0 and n < L.MAX_MONEY then return n end
end
local function Cancel(t) if t and t.Cancel then t:Cancel() end end
local function Changed()
    if not pending or settle then return end
    local token = pending
    settle = C_Timer.NewTimer(0, function()
        if pending ~= token then return end
        settle = nil
        if R.Perf and R.Perf.Call then R.Perf.Call("ledger.auction", Try) else Try() end
    end)
end
local function Clear()
    L.Unsubscribe(Changed)
    Cancel(timer); Cancel(settle)
    pending, timer, settle = nil, nil, nil
end
function A.Abort(token, reason)
    if token and token ~= pending then return end
    if pending then
        reason = stats[reason] ~= nil and reason or "interrupted"
        stats[reason] = stats[reason] + 1
        blocked = true -- late tokenless posting replies cannot belong to a new attempt in this visit
    end
    Clear()
end
Try = function()
    local p = pending
    if not p then return end
    local now = Now()
    local valid = true
    if p.context then local ok, result = pcall(p.context); valid = ok and result == true end
    if not active or not L.Active() or L.CharKey() ~= p.char or not valid then A.Abort(p); return end
    if not now or now < p.started or now >= p.expires then A.Abort(p, "expired"); return end
    local rec = L.Record(p.char)
    if not rec or rec.nextId > p.entry + 1 then A.Abort(p, "ambiguous"); return end
    if rec.nextId == p.entry then return end
    local e = rec.entries[#rec.entries]
    if not e or e.id ~= p.entry or e.k or e.a ~= -p.cost then A.Abort(p, "mismatch"); return end
    if not p.complete then return end
    Clear() -- Evidence can notify synchronously
    local result = L.Evidence({ kind = p.kind, amount = e.a, item = p.item, qty = p.qty, auction = p.auction,
        entry = p.entry, char = p.char, corr = "auctioncash:" .. p.serial })
    if result == "attributed" then stats.attributed = stats.attributed + 1 end
end
local function Foreign()
    if pending and sending ~= pending then
        if R.Perf and R.Perf.Call then R.Perf.Call("ledger.auction", A.Abort, pending, "ambiguous")
        else A.Abort(pending, "ambiguous") end
    end
end
local function Hooks()
    if hooked then return true end
    if not hooksecurefunc or not C_AuctionHouse then return false end
    for _, name in ipairs({ "PostItem", "PostCommodity", "ConfirmPostItem", "ConfirmPostCommodity", "CancelAuction",
        "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "CancelSell" }) do
        if not hooks[name] and type(C_AuctionHouse[name]) == "function" then
            hooksecurefunc(C_AuctionHouse, name, Foreign); hooks[name] = true
        end
    end
    hooked = true
    return true
end
function A.Begin(kind, cost, item, qty, auction, context)
    if not active or not L.Active() then return nil end
    if pending then A.Abort(pending, "ambiguous"); return nil end
    if blocked or (kind ~= "postItem" and kind ~= "postCommodity" and kind ~= "cancel") then return nil end
    cost, item, qty = Int(cost, 1), Int(item, 1), Int(qty, 1)
    auction = Int(auction, 1)
    if not cost or not item or not qty or kind == "cancel" and not auction or not Now()
        or not (C_Timer and C_Timer.NewTimer) or not Hooks() then return nil end
    local key = L.CharKey()
    local rec = key and L.Record(key)
    if not rec then return nil end
    serial = serial + 1
    local p = { mode = kind, kind = kind == "cancel" and "ahCancelFee" or "ahDeposit", cost = cost,
        item = item, qty = qty, auction = auction, context = context, char = key, entry = rec.nextId,
        started = Now(), expires = Now() + 8, serial = serial }
    pending = p
    L.Subscribe(Changed)
    timer = C_Timer.NewTimer(8, function()
        if pending == p then
            local record = L.Record(p.char)
            A.Abort(p, record and record.nextId == p.entry and "noMoney" or "expired")
        end
    end)
    return p
end
function A.Sending(token, on)
    if on then if token and token == pending then sending = token end
    elseif sending == token then sending = nil end
end
function A.Warning(token)
    if not token or pending ~= token then return end
    local rec = L.Record(token.char)
    if token.complete or not rec or rec.nextId ~= token.entry then A.Abort(token, "ambiguous")
    else Clear() end -- a warning is not a posting; a later acceptance starts a fresh correlation
end
function A.Complete(token, auction, created, total)
    if not token or pending ~= token then return false end
    auction = Int(auction, 1)
    if token.mode == "cancel" then
        if auction ~= token.auction then return false end
    elseif token.mode == "postItem" and token.qty > 1 then
        if Int(created, 1) ~= token.qty or Int(total, 1) ~= token.qty then return false end
    elseif not auction then return false end
    token.auction = token.auction or auction
    token.complete = true
    Changed()
    return true
end
local function Reset()
    A.Abort(nil, "interrupted")
    sending, blocked = nil, false
end
local function Interrupt() A.Abort(nil, "interrupted") end
function A.Refresh()
    Interrupt()
    active = L.Active()
    for event, fn in pairs({ AUCTION_HOUSE_SHOW = Reset, AUCTION_HOUSE_CLOSED = Reset,
        PLAYER_LEAVING_WORLD = Reset, PLAYER_LOGOUT = Reset, PLAYER_REGEN_DISABLED = Interrupt }) do
        if active and not watching[event] then watching[event] = fn; R:On(event, fn)
        elseif not active and watching[event] then R:Off(event, watching[event]); watching[event] = nil end
    end
end
function A.Snapshot()
    local out = { pending = pending and 1 or 0, blocked = blocked and 1 or 0 }
    for k, v in pairs(stats) do out[k] = v end
    return out
end
if R.Perf and R.Perf.Gauge then
    for _, key in ipairs({ "pending", "blocked", "attributed", "noMoney", "mismatch", "ambiguous", "expired", "interrupted", "observerError" }) do
        local field = key
        R.Perf.Gauge("ledger.auction." .. field, { label = "Auction accounting: " .. field,
            group = "workshop", kind = "cache", unit = "count", read = function() return A.Snapshot()[field] end })
    end
end
-- Accounting must never change whether a controller sends its already-authorized action.
for _, name in ipairs({ "Begin", "Sending", "Complete", "Warning", "Abort" }) do
    local fn = A[name]
    A[name] = function(...)
        local ok, value = pcall(fn, ...)
        if ok then return value end
        stats.observerError = stats.observerError + 1
        pcall(Clear); blocked = true
        return nil
    end
end
R:OnInit(A.Refresh)
