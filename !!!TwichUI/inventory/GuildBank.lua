-- TwichUI: Magic Inventory, reading the guild bank
-- What the guild bank shows, kept in memory as a snapshot for the placement previews (GuildPlan.lua). Nothing here picks up,
-- splits, deposits or withdraws. The one thing it can do besides reading is GB.Show(tab): show a tab the way the guild bank's
-- own tab button does, so that tab's items are sent and can be read (see below; GuildPrep.lua and GuildRun.lua are the callers).
--
-- What the Forever client gives (Blizzard_GuildBankUI.lua, which reads and draws only the tab it is showing):
--   GetNumGuildBankTabs, GetCurrentGuildBankTab, GetGuildBankTabInfo(tab) -> name, icon, isViewable, canDeposit,
--     numWithdrawals (0: this rank can't withdraw from the tab), remainingWithdrawals (stacks left today; -1 unlimited;
--     only kept up to date for the tab being shown), GetGuildBankItemInfo(tab, slot) -> texture, count, locked,
--     isFiltered, quality, GetGuildBankItemLink(tab, slot); 98 slots a tab (MAX_GUILDBANK_SLOTS_PER_TAB), up to 8 tabs.
--   Events: GUILDBANKFRAME_OPENED / _CLOSED, GUILDBANK_UPDATE_TABS (tab names, rights), GUILDBANKBAGSLOTS_CHANGED
--     (the shown tab's contents arrived or changed).
-- A tab's items are only trusted after GUILDBANKBAGSLOTS_CHANGED arrived while that tab was the one shown: the game gives
-- the same empty answer for an empty slot and for a tab it hasn't sent yet, and this file can't tell them apart any
-- other way (the event carries no tab number, and the source documents no call that reads a tab that is not shown). A tab that
-- hasn't been shown is "unread", never empty. Each tab says how current it is:
--   live     shown now, read after the game's last word
--   earlier  read while the bank was open, but another tab is shown now (it may have changed)
--   closed   read in a visit that has ended
--   unread   its items were never seen (names and rights may be known)
-- Reading a tab WITHOUT showing it (GB.Query). QueryGuildBankTab(tab) takes the tab as an argument and GetGuildBankItemInfo(tab, slot)
-- reads any tab from what the client holds, so a tab can be asked for while the player keeps using the one shown. The Blizzard UI never
-- does this (it only queries the shown tab) and the generated documentation has nothing on it; the evidence is GuildBankSort
-- (reference_addons), which queries every tab this way and reads them all, and which the player reports working on this client. The event
-- that answers (GUILDBANKBAGSLOTS_CHANGED) still carries no tab, so one query is in flight at a time and its answer is accepted only after
-- an event came AND things were quiet for GB.QUERY_DWELL (an empty answer looks like an unanswered one; this is the residual risk).
-- Showing a tab (GB.Show). The Blizzard frame itself selects a tab from code, not only from a click: GuildBankFrameMixin:OnShow
-- runs Tabs[1]:OnClick() and SelectAvailableTab runs BankTabs[n]:OnClick("LeftButton") from an event handler. That handler
-- (GuildBankTabMixin:OnClick) is SetCurrentGuildBankTab(n), the frame's UpdateTabs/Update, then QueryGuildBankTab(n) when the
-- Bank page is up (it queries the log or the tab text instead when those pages are up, so a tab is never shown from there).
-- GB.Show calls exactly that handler, so the frame, the cursor and the answer stay the game's own; for the tab already shown it
-- asks again with QueryGuildBankTab(tab), the call the frame makes for the shown tab. The answer is then read as usual (above).
-- Not established by the source: that these calls work for an addon outside a click (the frame's own uses are not clicks, which
-- is the evidence), and that an answer to an earlier request cannot arrive after the switch and be taken for this tab's.
-- Nothing here is saved except the tab names and icons (MI.NoteGuildTabs) so a tab can be chosen with the bank closed.

local R = TwichUI
local MI = R.MagicInventory
local Plain = MI.Plain

local GB = {}
MI.GuildBank = GB

GB.SLOTS = 98            -- MAX_GUILDBANK_SLOTS_PER_TAB (a local in Blizzard_GuildBankUI.lua)
GB.COLUMNS = 7           -- the bank draws 7 columns of 14 slots
GB.PER_COLUMN = 14
GB.MAX_TABS = MI.MAX_GUILD_TABS
GB.QUERY_DWELL = 0.5     -- seconds of quiet after the answering event before a tab asked for without showing it is taken as read
GB.MAX_AGE = 120         -- seconds a tab read earlier in this visit still counts as current for a review (a shown tab is live)

local watchers = {}
-- fn(what): "items" (a tab's items arrived), "tabs" (names or rights), "open", "close". Called after the snapshot changed.
function GB.Watch(fn) watchers[#watchers + 1] = fn end
local function Tell(what)
    for _, fn in ipairs(watchers) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("magic inventory guild bank", err) end
    end
end

local snap = { tabs = {}, open = false, seq = 0, guild = nil, current = nil, numTabs = nil, visit = 0 }
local received = {}      -- [tab] = true once the game sent that tab's items in this visit
local pending            -- the one tab asked for without showing it: { tab, events, lastEvent }

local function Num(v) v = Plain(v); return type(v) == "number" and v == v and v or nil end
local function Bool(v) v = Plain(v); if type(v) == "boolean" then return v end return nil end
local function Now() return GetTime and GetTime() or 0 end

local function GuildName()
    if not (IsInGuild and IsInGuild()) then return nil end
    local name = Plain(GetGuildInfo and (GetGuildInfo("player")))
    return type(name) == "string" and name ~= "" and name or nil
end

-- One tab's name, icon and the player's rights on it. nil entries are "the game didn't say".
local function ReadTabInfo(i)
    if not GetGuildBankTabInfo then return nil end
    local name, icon, viewable, canDeposit, numWithdrawals, remaining = GetGuildBankTabInfo(i)
    name = Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    numWithdrawals = Num(numWithdrawals)
    local canWithdraw
    if numWithdrawals ~= nil then canWithdraw = numWithdrawals ~= 0 end   -- 0: the rank can't withdraw from this tab
    return { name = name, icon = Num(icon) or (type(Plain(icon)) == "string" and Plain(icon)) or nil,
        viewable = Bool(viewable), canDeposit = Bool(canDeposit), canWithdraw = canWithdraw, remaining = Num(remaining) }
end

-- The 98 slots of a tab, as the game shows them now. { [slot] = { id, count, locked, link, icon, quality } }; id is nil
-- when the link wasn't an item the planner can identify (it still takes its slot).
local function ReadSlots(tab)
    local slots = {}
    for slot = 1, GB.SLOTS do
        local texture, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
        texture = Plain(texture)
        if texture ~= nil then
            local link = GetGuildBankItemLink and Plain(GetGuildBankItemLink(tab, slot))
            local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
            slots[slot] = { id = id, count = Num(count), locked = Bool(locked), link = type(link) == "string" and link or nil,
                icon = Num(texture) or (type(texture) == "string" and texture) or nil, quality = Num(quality) }
        end
    end
    return slots
end

-- A snapshot belongs to one guild: another guild (or none) starts from nothing. True when it was dropped.
local function SyncGuild()
    local guild = GuildName()
    if guild == snap.guild then return false end
    snap.tabs, snap.guild, received = {}, guild, {}
    return true
end

-- Reads what the game says now: the tab list and rights always, and the shown tab's items when the game has sent them.
-- Returns true when something changed.
function GB.Capture()
    if not (snap.open and GetNumGuildBankTabs and GetGuildBankItemInfo) then return false end
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.guildRead")
    local changed = false
    if SyncGuild() then changed = true end
    local n = Num(GetNumGuildBankTabs())
    n = n and math.min(math.max(n, 0), GB.MAX_TABS) or nil
    snap.numTabs = n
    local current = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    snap.current = current
    local seen = {}
    for i = 1, n or 0 do
        local info = ReadTabInfo(i)
        local t = snap.tabs[i]
        if not t then t = {}; snap.tabs[i] = t end
        if not info then
            if t.name ~= nil then t.name, t.icon, t.viewable, t.canDeposit, t.canWithdraw, t.remaining = nil, nil, nil, nil, nil, nil; changed = true end
        else
            seen[i] = { name = info.name, icon = info.icon }
            for _, k in ipairs({ "name", "icon", "viewable", "canDeposit", "canWithdraw", "remaining" }) do
                if t[k] ~= info[k] then t[k], changed = info[k], true end
            end
        end
        -- contents are kept only for a tab the player can look into
        if info and info.viewable ~= true and t.slots then t.slots, t.readAt = nil, nil; changed = true end
    end
    for i in pairs(snap.tabs) do if n == nil or i > n then snap.tabs[i], received[i] = nil, nil; changed = true end end
    if snap.guild then MI.NoteGuildTabs(snap.guild, seen) end
    -- the shown tab's items, once the game has said so
    if current and snap.tabs[current] and snap.tabs[current].viewable == true and received[current] then
        local t = snap.tabs[current]
        t.slots, t.readAt, t.visit = ReadSlots(current), Now(), snap.visit
        changed = true
    end
    if changed then snap.seq = snap.seq + 1 end
    if pt then R.Perf.Stop(pt) end
    return changed
end

-- The snapshot as the planner reads it: a fresh outer table (the slot tables inside are replaced, never edited, so they
-- are safe to hold). { guild, open, current, numTabs, seq, now, tabs = { [i] = { name, icon, viewable, canDeposit,
-- canWithdraw, remaining, slots, readAt, age, state } } }
function GB.Snapshot()
    local now = Now()
    local out = { guild = snap.guild, open = snap.open, current = snap.current, numTabs = snap.numTabs, seq = snap.seq, now = now, tabs = {} }
    for i = 1, snap.numTabs or 0 do
        local t = snap.tabs[i]
        if t then
            local state
            if not t.slots then state = "unread"
            elseif not snap.open or t.visit ~= snap.visit then state = "closed"
            elseif i == snap.current and received[i] then state = "live"
            else state = "earlier" end
            out.tabs[i] = { name = t.name, icon = t.icon, viewable = t.viewable, canDeposit = t.canDeposit, canWithdraw = t.canWithdraw,
                remaining = (i == snap.current and snap.open) and t.remaining or nil,
                slots = t.slots, readAt = t.readAt, age = t.readAt and (now - t.readAt) or nil, state = state }
        end
    end
    return out
end

function GB.Seq() return snap.seq end
function GB.IsOpen() return snap.open end

-- true when this tab is the one shown and its items arrived after it was last asked for (the only read that is trusted)
function GB.IsLive(tab)
    if not (snap.open and tab) then return false end
    return Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab()) == tab and received[tab] == true
end

-- how long ago this tab's items were read, or nil when they never were
function GB.Age(tab)
    local t = snap.tabs[tab]
    return t and t.readAt and (Now() - t.readAt) or nil
end

-- true when a review may use this tab's items: shown and read, or read earlier in this visit and not too long ago
function GB.IsFresh(tab, maxAge)
    local t = snap.tabs[tab]
    if not (snap.open and t and t.slots and t.viewable == true and t.visit == snap.visit) then return false end
    if GB.IsLive(tab) then return true end
    local age = GB.Age(tab)
    return age ~= nil and age <= (maxAge or GB.MAX_AGE)
end

-- "bank" while the guild bank shows its item page (the page GB.Show may select tabs from), else what it shows instead
function GB.Mode()
    local f = _G.GuildBankFrame
    if type(f) ~= "table" then return nil end
    for _, page in ipairs({ "Log", "Info" }) do
        local p = f[page]
        if type(p) == "table" and p.IsShown and p:IsShown() then return page == "Log" and "log" or "info" end
    end
    local m = Plain(f.mode)
    if m == nil or m == "bank" then return "bank" end
    return tostring(m)
end

-- Whether a tab can be asked for from code now: the frame's own tab buttons exist and its item page is up.
function GB.CanNavigate()
    if not snap.open then return false, "closed" end
    local f = _G.GuildBankFrame
    if type(f) ~= "table" or type(f.BankTabs) ~= "table" then return false, "unsupported" end
    if GB.Mode() ~= "bank" then return false, "mode" end
    return true
end

-- Whether a tab can be asked for without showing it.
function GB.CanQuery() return snap.open and type(_G.QueryGuildBankTab) == "function" end

-- Asks the game for one tab's items without showing it. One at a time: false, "busy" while another is in flight.
-- Returns true, or false and why: closed | unsupported | hidden | busy | error.
function GB.Query(tab)
    if not snap.open then return false, "closed" end
    if type(_G.QueryGuildBankTab) ~= "function" then return false, "unsupported" end
    local t = snap.tabs[tab]
    if not (t and t.viewable == true) then return false, "hidden" end
    if pending and pending.tab ~= tab then return false, "busy" end
    pending = { tab = tab, events = 0, lastEvent = Now() }
    local ok, err = pcall(_G.QueryGuildBankTab, tab)
    if not ok then
        pending = nil
        R.Fault("magic inventory guild bank query", err)
        return false, "error"
    end
    return true
end

-- The answer to GB.Query(tab): true once the game's event came and nothing more came for GB.QUERY_DWELL; the tab's items are then in the
-- snapshot (read now, stamped with this visit). false, "waiting" until then.
function GB.QueryDone(tab)
    local p = pending
    if not (p and p.tab == tab) then return false, "none" end
    if p.events == 0 or Now() - p.lastEvent < GB.QUERY_DWELL then return false, "waiting" end
    local t = snap.tabs[tab]
    if not (t and t.viewable == true) then pending = nil; return false, "hidden" end
    t.slots, t.readAt, t.visit = ReadSlots(tab), Now(), snap.visit
    pending = nil
    snap.seq = snap.seq + 1
    return true
end
function GB.QueryPending() return pending and pending.tab or nil end
-- gives up on the query in flight (its answer, if it comes later, is then only an event)
function GB.QueryCancel() pending = nil end

-- Shows a tab and asks the game for its items. The tab counts as read again only when its items arrive (IsLive).
-- Returns true, or false and why: closed | unsupported | mode | hidden | error.
function GB.Show(tab)
    local ok, why = GB.CanNavigate()
    if not ok then return false, why end
    local t = snap.tabs[tab]
    if not (t and t.viewable == true) then return false, "hidden" end
    local f = _G.GuildBankFrame
    local current = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    received[tab] = nil
    local called, err
    if current == tab then
        if not QueryGuildBankTab then return false, "unsupported" end
        called, err = pcall(QueryGuildBankTab, tab)
    else
        local b = f.BankTabs[tab]
        if type(b) ~= "table" or not b.OnClick then return false, "unsupported" end
        called, err = pcall(b.OnClick, b, "LeftButton")
    end
    if not called then
        R.Fault("magic inventory guild bank show", err)
        return false, "error"
    end
    snap.seq = snap.seq + 1
    GB.Capture()
    return true
end

-- How many slots of items are held, for the diagnostics.
function GB.Retained()
    local n = 0
    for _, t in pairs(snap.tabs) do
        if t.slots then for _ in pairs(t.slots) do n = n + 1 end end
    end
    return n
end

---------------------------------------------------------------------------
-- Listening: only while the feature is on. The snapshot is thrown away when it is turned off or the player leaves the world.
---------------------------------------------------------------------------
local listening = {}
local function Forget()
    snap.tabs, snap.open, snap.current, snap.numTabs, snap.guild = {}, false, nil, nil, nil
    snap.seq = snap.seq + 1
    received, pending = {}, nil
end

local function OnShown()
    if not snap.open then return end
    GB.Capture()
    Tell("tabs")
end
local function OnItems()
    -- the items can arrive before (or without) the "opened" event: a guild bank that is showing is open
    local opened = false
    if not snap.open then
        if not (_G.GuildBankFrame and _G.GuildBankFrame.IsShown and _G.GuildBankFrame:IsShown()) then return end
        snap.open = true
        snap.visit = snap.visit + 1
        opened = true
    end
    SyncGuild()   -- before marking the tab: a new guild must not take the old one's marks (or drop this one's)
    if pending then pending.events, pending.lastEvent = pending.events + 1, Now() end
    local current = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    if current then received[current] = true end
    GB.Capture()
    if opened then Tell("open") end
    Tell("items")
end
local function OnOpened()
    if not snap.open then received = {}; snap.visit = snap.visit + 1 end   -- (items that already arrived stay trusted)
    snap.open = true
    GB.Capture()
    Tell("open")
end
local function OnClosed()
    if not snap.open then return end
    snap.open, received, pending = false, {}, nil
    snap.seq = snap.seq + 1
    Tell("close")
end
local function OnLeaving() Forget(); Tell("close") end

-- This client shows and hides the guild bank through the player interaction manager (Blizzard_GuildBankUI_Bootstrap.lua registers it
-- with Enum.PlayerInteractionType.GuildBanker, 10); GUILDBANKFRAME_OPENED / _CLOSED are only routed on the Burning Crusade client
-- (Blizzard_Game/TBC/EventRouting.lua), so here they may never arrive. Both are listened to; opening or closing twice is one.
local function IsGuildBanker(kind)
    kind = Plain(kind)
    local want = _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.GuildBanker or 10
    return kind == want
end
local function OnInteractionShow(kind) if IsGuildBanker(kind) then OnOpened() end end
local function OnInteractionHide(kind) if IsGuildBanker(kind) then OnClosed() end end

local HANDLERS = {
    GUILDBANKFRAME_OPENED = OnOpened, GUILDBANKFRAME_CLOSED = OnClosed,
    GUILDBANKBAGSLOTS_CHANGED = OnItems, GUILDBANK_UPDATE_TABS = OnShown,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = OnInteractionShow, PLAYER_INTERACTION_MANAGER_FRAME_HIDE = OnInteractionHide,
    PLAYER_LEAVING_WORLD = OnLeaving,
}

-- Safe to call any time (Run.lua's MI.Refresh does, on load and whenever the switch changes).
function GB.Sync()
    local on = MI.Enabled()
    for event, fn in pairs(HANDLERS) do
        if on and not listening[event] then listening[event] = fn; R:On(event, fn)
        elseif not on and listening[event] then R:Off(event, listening[event]); listening[event] = nil end
    end
    if not on then Forget()
    elseif not snap.open and _G.GuildBankFrame and _G.GuildBankFrame.IsShown and _G.GuildBankFrame:IsShown() then
        OnOpened()   -- the feature was turned on with the bank already showing
    end
end

function GB.ListenerCount()
    local n = 0
    for _ in pairs(listening) do n = n + 1 end
    return n
end

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.guildBank", { label = "Magic Inventory guild bank snapshot (slots held)", unit = "count", kind = "cache",
        read = function() return GB.Retained() end })
end
