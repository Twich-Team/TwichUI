-- TwichUI: Magic Inventory, reading the guild bank
-- What the guild bank shows, kept in memory as a snapshot for the placement previews (GuildPlan.lua). Reads only: nothing
-- here picks up, splits, deposits or withdraws, switches the tab the bank shows, or asks the server for a tab.
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
-- other way. A tab that hasn't been shown is "unread", never empty. Each tab says how current it is:
--   live     shown now, read after the game's last word
--   earlier  read while the bank was open, but another tab is shown now (it may have changed)
--   closed   read in a visit that has ended
--   unread   its items were never seen (names and rights may be known)
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

local snap = { tabs = {}, open = false, seq = 0, guild = nil, current = nil, numTabs = nil }
local received = {}      -- [tab] = true once the game sent that tab's items in this visit

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
        t.slots, t.readAt = ReadSlots(current), Now()
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
            elseif not snap.open then state = "closed"
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
    received = {}
end

local function OnShown()
    if not snap.open then return end
    GB.Capture()
end
local function OnItems()
    -- the items can arrive before (or without) the "opened" event: a guild bank that is showing is open
    if not snap.open then
        if not (_G.GuildBankFrame and _G.GuildBankFrame.IsShown and _G.GuildBankFrame:IsShown()) then return end
        snap.open = true
    end
    SyncGuild()   -- before marking the tab: a new guild must not take the old one's marks (or drop this one's)
    local current = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    if current then received[current] = true end
    GB.Capture()
end
local function OnOpened()
    if not snap.open then received = {} end   -- (items that already arrived stay trusted)
    snap.open = true
    GB.Capture()
end
local function OnClosed()
    if not snap.open then return end
    snap.open, received = false, {}
    snap.seq = snap.seq + 1
end
local function OnLeaving() Forget() end

local HANDLERS = {
    GUILDBANKFRAME_OPENED = OnOpened, GUILDBANKFRAME_CLOSED = OnClosed,
    GUILDBANKBAGSLOTS_CHANGED = OnItems, GUILDBANK_UPDATE_TABS = OnShown,
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
