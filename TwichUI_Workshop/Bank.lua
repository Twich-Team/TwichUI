-- TwichUI Workshop: seeing the player's bank and the guild bank
-- Once the Workshop addon is loaded (it is load on demand: nothing here exists at login, and nothing loads it when a bank opens), the bank the
-- player opens is read and remembered (Storage.lua) even with the Workshop window hidden, so the plan can use materials that are not in the
-- bags. It only READS: it never picks anything up, moves, withdraws, deposits or buys, and it asks the game nothing while no bank is open.
-- A bank already open when the addon loads is read once, at load.
--
-- The game's side (Forever 1.60.1 UI source; none of it has been seen working in the game yet, docs/workshop.md lists the checks):
--   Personal bank (Blizzard_UIPanels_Game/Camelot/BankFrame.lua): the character bank's tabs are BAGS, listed by
--     C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) and read with C_Container.GetContainerNumSlots / GetContainerItemInfo (itemID,
--     stackCount). It is opened through the player interaction manager (PLAYER_INTERACTION_MANAGER_FRAME_SHOW with Banker 8 or CharacterBanker 67;
--     AccountBanker 68 is the warband bank and is not read: out of scope); BANKFRAME_OPENED / _CLOSED are documented too and are listened to as
--     well. BANK_TABS_CHANGED(bankType) and PLAYERBANKSLOTS_CHANGED(slot) say its tabs and slots changed; BAG_UPDATE_DELAYED follows moves.
--   Guild bank (Blizzard_GuildBankUI.lua; the same facts inventory/GuildBank.lua rests on): GetNumGuildBankTabs, GetCurrentGuildBankTab,
--     GetGuildBankTabInfo(tab) -> name, icon, isViewable, canDeposit, numWithdrawals (0: this rank cannot take from the tab), remainingWithdrawals
--     (stacks left today, 0 none, -1 unlimited; the game keeps it up to date only for the tab being shown), GetGuildBankItemInfo(tab, slot),
--     GetGuildBankItemLink(tab, slot); 98 slots a tab. GUILDBANKBAGSLOTS_CHANGED says the SHOWN tab's items arrived or changed (it carries no tab).
-- How a read is trusted:
--   * Personal bank: only while it is open, and a tab is replaced only when every slot of it was read as a whole number or empty; a tab that was
--     not read completely keeps its old record (marked uncertain), a list of tabs the game did not give is not read as an empty bank.
--   * Guild bank: only the tab that is shown, only after the game said its items arrived, and only when the tab is viewable. The game gives the
--     same empty answer for an empty slot and for a tab it has not sent yet, so an EMPTY answer is believed only when the same tab was already the
--     one shown at the previous answer (a real change); an empty answer right after a tab change, or at load, is not believed and nothing is
--     replaced. A non-empty answer cannot come from an unsent tab. A tab that was never read is unread, not empty.
--   * Moving materials between a bank and the bags: while a bank is open, a bag change marks what is stored "pending" (not planned with) until the
--     bank has been read again; a pending bank that closes before it could be read, or a guild bank tab no event followed, is saved as uncertain.
-- Events: the always-on ones are the few that say a bank opened or closed; the content ones are registered only while a bank is open. No timers
-- run while no bank is open and nothing polls.

local R = TwichUI
local W = R.Workshop
local O, St, Q = W.Observe, W.Storage, W.Queue
local Int, Plain = W.Int, W.Plain
local B = {}
W.Bank = B

B.SETTLE = 0.4          -- seconds a burst of changes settles before the bank is read
B.PAIR = 1.0            -- seconds within which a bag change is the same move as a guild bank answer that just came
B.GUILD_SLOTS = 98      -- MAX_GUILDBANK_SLOTS_PER_TAB (a local in Blizzard_GuildBankUI.lua)
B.reads, B.guildReads = 0, 0

local PLAYER_BANKER = { [8] = true, [67] = true }   -- Enum.PlayerInteractionType.Banker, .CharacterBanker (AccountBanker, 68, is not read)
local GUILD_BANKER = 10                             -- Enum.PlayerInteractionType.GuildBanker

local ALWAYS = { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_LEAVING_WORLD" }
local BANK_EVENTS = { "BANK_TABS_CHANGED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED" }
local GUILD_EVENTS = { "BAG_UPDATE_DELAYED" }

local frame
local registered = {}                       -- [event] = true while a content event is registered
local open = { bank = false, guild = false }
local pending = { bank = false, guild = false }   -- a bag change was seen with that bank open and its read has not come yet
local token = { bank = 0, guild = 0 }        -- changes whenever a waiting timer should be forgotten
local guild = { lastTab = nil, key = nil, items = -100 }   -- the tab of the previous answer, the guild it was for, when it came

local function Now() return GetTime and GetTime() or 0 end

---------------------------------------------------------------------------
-- The personal bank
---------------------------------------------------------------------------
local function CharacterBankOpen()
    if not open.bank then return false end
    local f = _G.BankFrame
    if type(f) == "table" and f.IsShown and not f:IsShown() then return false end
    if C_Bank and C_Bank.CanViewBank and Enum and Enum.BankType then
        local ok, can = pcall(C_Bank.CanViewBank, Enum.BankType.Character)
        if ok and Plain(can) == false then return false end
    end
    return true
end

-- One tab (a bag) as { [itemID] = count }, or nil when it could not be read completely: a slot count that is not a number, or a slot whose item
-- or count is not a whole number (a secret value, a missing field), or more different items than a tab may hold
local function ReadContainer(bag)
    local slots = Int(Plain(C_Container.GetContainerNumSlots(bag)), 1, 400)
    if not slots then return nil end
    local items, distinct = {}, 0
    for slot = 1, slots do
        local info = Plain(C_Container.GetContainerItemInfo(bag, slot))
        if info ~= nil then
            if type(info) ~= "table" then return nil end
            local id, count = Int(info.itemID, 1, W.MAX_ID), Int(info.stackCount, 1, St.MAX_COUNT)
            if not id or not count then return nil end
            if not items[id] then
                distinct = distinct + 1
                if distinct > St.MAX_TAB_ITEMS then return nil end
            end
            items[id] = math.min((items[id] or 0) + count, St.MAX_COUNT)
        end
    end
    return items
end

-- What the open character bank holds right now: { ids = { bagID, ... }, tabs = { [bagID] = items }, incomplete = n }, or nil and why:
-- "api" (the game offers no such calls), "closed", "unread" (the game gave no tab list), "none" (it listed no tab: not evidence of an empty bank)
function B.ReadBank()
    local CB, CT = C_Bank, C_Container
    if not (CB and CB.FetchPurchasedBankTabIDs and CT and CT.GetContainerNumSlots and CT.GetContainerItemInfo and Enum and Enum.BankType) then
        return nil, "api"
    end
    if not CharacterBankOpen() then return nil, "closed" end
    local ok, list = pcall(CB.FetchPurchasedBankTabIDs, Enum.BankType.Character)
    list = ok and Plain(list) or nil
    if type(list) ~= "table" then return nil, "unread" end
    local ids = {}
    for _, raw in ipairs(list) do
        local id = Int(Plain(raw), 1, 99)
        if id and #ids < St.MAX_BANK_TABS then ids[#ids + 1] = id end
    end
    if #ids == 0 then return nil, "none" end
    local tabs, incomplete = {}, 0
    for _, id in ipairs(ids) do
        local okc, items = pcall(ReadContainer, id)
        if okc and items then tabs[id] = items else incomplete = incomplete + 1 end
    end
    return { ids = ids, tabs = tabs, incomplete = incomplete }
end

local function RunBank()
    local read, why = B.ReadBank()
    pending.bank = false
    if not read then
        if why ~= "api" then St.MarkBankUncertain() end   -- it could not be seen: what is remembered may be out of date now
        return false
    end
    B.reads = B.reads + 1
    return St.StoreBank(read)
end

-- Reads the open bank once, after a burst of changes has settled. pend: a bag change was seen, so what is remembered is not planned with until then.
local function ScheduleBank(pend)
    if pend then pending.bank = true end
    token.bank = token.bank + 1
    local mine = token.bank
    C_Timer.After(B.SETTLE, function()
        if mine ~= token.bank or not open.bank then return end
        R.Perf.Call("workshop.bank", RunBank)
    end)
end

---------------------------------------------------------------------------
-- The guild bank
---------------------------------------------------------------------------
-- The shown tab as the game shows it now: { id (the guild), index, nt (tabs), n = { [itemID] = count }, empty, w, lim, rem, by }, or nil and why:
-- "api", "noguild", "notabs", "hidden" (the tab cannot be viewed), "partial" (a slot's item or count could not be read)
function B.ReadGuildTab()
    if not (GetNumGuildBankTabs and GetCurrentGuildBankTab and GetGuildBankTabInfo and GetGuildBankItemInfo and GetGuildBankItemLink) then
        return nil, "api"
    end
    local id = O.GuildId()
    if not id then return nil, "noguild" end
    local nt = Int(Plain(GetNumGuildBankTabs()), 1, St.MAX_GUILD_TABS)
    local index = nt and Int(Plain(GetCurrentGuildBankTab()), 1, nt)
    if not index then return nil, "notabs" end
    local okt, _, _, viewable, _, withdrawals, remaining = pcall(GetGuildBankTabInfo, index)
    if not okt or Plain(viewable) ~= true then return nil, "hidden" end
    withdrawals = Int(Plain(withdrawals), -1, W.MAX_ID)
    remaining = Int(Plain(remaining), -1, W.MAX_ID)
    local items, distinct = {}, 0
    for slot = 1, B.GUILD_SLOTS do
        local okg, texture, count = pcall(GetGuildBankItemInfo, index, slot)
        if not okg then return nil, "partial" end
        if Plain(texture) ~= nil then
            local n = Int(Plain(count), 1, St.MAX_COUNT)
            local okl, link = pcall(GetGuildBankItemLink, index, slot)
            link = okl and Plain(link) or nil
            if not n or type(link) ~= "string" then return nil, "partial" end
            local item = tonumber(link:match("item:(%d+)"))   -- a link that is not an item (a pet, say) takes a slot but is no material
            if item then
                item = Int(item, 1, W.MAX_ID)
                if not item then return nil, "partial" end
                if not items[item] then
                    distinct = distinct + 1
                    if distinct > St.MAX_TAB_ITEMS then return nil, "partial" end
                end
                items[item] = math.min((items[item] or 0) + n, St.MAX_COUNT)
            end
        end
    end
    return { id = id, index = index, nt = nt, n = items, empty = next(items) == nil,
        w = withdrawals ~= nil and (withdrawals == 0 and 0 or 1) or nil, lim = withdrawals, rem = remaining, by = Q.CharKey() }
end

local function GuildAnswer()
    local read, why = B.ReadGuildTab()
    if not read then return false, why end
    if guild.key ~= read.id.key then guild.key, guild.lastTab = read.id.key, nil end   -- another guild: nothing carries over
    local sameTab = guild.lastTab == read.index
    guild.lastTab = read.index
    guild.items = Now()
    if read.empty and not sameTab then return false, "unsure" end   -- an empty answer right after a tab change cannot be told from an unsent tab
    pending.guild = false
    token.guild = token.guild + 1
    B.guildReads = B.guildReads + 1
    return St.StoreGuildTab(read.id, read.index, read, nil, read.nt)
end

-- A bag change with the guild bank open: a deposit or withdrawal is usually answered by the guild bank within a moment. If it is not, the
-- shown tab is saved as uncertain (it may have changed and nothing said so).
local function GuildBagChange()
    if Now() - guild.items < B.PAIR then return end   -- the answer to this very move came first
    pending.guild = true
    token.guild = token.guild + 1
    local mine = token.guild
    C_Timer.After(B.SETTLE + B.PAIR, function()
        if mine ~= token.guild or not pending.guild then return end
        pending.guild = false
        local id = guild.key and O.GuildId()
        if id and guild.lastTab then St.MarkGuildTabUncertain(id, guild.lastTab) end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function SyncEvents()
    if not frame then return end
    local want = {}
    if open.bank then for _, e in ipairs(BANK_EVENTS) do want[e] = true end end
    if open.guild then for _, e in ipairs(GUILD_EVENTS) do want[e] = true end end
    for e in pairs(want) do
        if not registered[e] then registered[e] = true frame:RegisterEvent(e) end
    end
    for e in pairs(registered) do
        if not want[e] then registered[e] = nil frame:UnregisterEvent(e) end
    end
end

local function BankOpened()
    if open.bank then return end
    open.bank = true
    SyncEvents()
    ScheduleBank(false)
end

local function BankClosed()
    if not open.bank then return end
    open.bank = false
    token.bank = token.bank + 1
    if pending.bank then
        pending.bank = false
        St.MarkBankUncertain()   -- it changed and could not be read again before the window closed
    end
    SyncEvents()
end

local function GuildOpened()
    if open.guild then return end
    open.guild = true
    guild.lastTab, guild.key, guild.items = nil, nil, -100
    SyncEvents()
end

local function GuildClosed()
    if not open.guild then return end
    open.guild = false
    token.guild = token.guild + 1
    if pending.guild then
        pending.guild = false
        local id = guild.key and O.GuildId()
        if id and guild.lastTab then St.MarkGuildTabUncertain(id, guild.lastTab) end
    end
    guild.lastTab, guild.key = nil, nil
    SyncEvents()
end

local function GuildFrameShown()
    local f = _G.GuildBankFrame
    return type(f) == "table" and f.IsShown and f:IsShown() == true
end

local HANDLERS = {
    BANKFRAME_OPENED = BankOpened, BANKFRAME_CLOSED = BankClosed,
    GUILDBANKFRAME_OPENED = GuildOpened, GUILDBANKFRAME_CLOSED = GuildClosed,
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = function(kind)
        kind = Plain(kind)
        if PLAYER_BANKER[kind] then BankOpened() elseif kind == GUILD_BANKER then GuildOpened() end
    end,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = function(kind)
        kind = Plain(kind)
        if PLAYER_BANKER[kind] then BankClosed() elseif kind == GUILD_BANKER then GuildClosed() end
    end,
    PLAYER_LEAVING_WORLD = function() BankClosed() GuildClosed() end,
    BANK_TABS_CHANGED = function(bankType)
        bankType = Plain(bankType)
        if open.bank and (bankType == nil or not (Enum and Enum.BankType) or bankType == Enum.BankType.Character) then ScheduleBank(true) end
    end,
    PLAYERBANKSLOTS_CHANGED = function() if open.bank then ScheduleBank(true) end end,
    BAG_UPDATE_DELAYED = function()
        if open.bank then ScheduleBank(true) end
        if open.guild then GuildBagChange() end
    end,
    GUILDBANKBAGSLOTS_CHANGED = function()
        -- the items can arrive before (or without) an "opened" event: a guild bank that is showing is open
        if not open.guild then
            if not GuildFrameShown() then return end
            GuildOpened()
        end
        R.Perf.Call("workshop.bank", GuildAnswer)
    end,
}

function B.Pending() return { bankPending = pending.bank, guildPending = pending.guild } end
function B.Events()
    if not frame then return 0 end
    local n = #ALWAYS
    for _ in pairs(registered) do n = n + 1 end
    return n
end
function B.IsOpen() return { bank = open.bank, guild = open.guild } end

function B.Start()
    if frame or not CreateFrame then return end
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        local fn = HANDLERS[event]
        if fn then fn(...) end
    end)
    for _, e in ipairs(ALWAYS) do frame:RegisterEvent(e) end
    -- a bank already open when the addon loads is read now
    local bf = _G.BankFrame
    if type(bf) == "table" and bf.IsShown and bf:IsShown() == true then BankOpened() end
    if GuildFrameShown() then
        GuildOpened()
        R.Perf.Call("workshop.bank", GuildAnswer)   -- (an empty answer is not believed this early: see GuildAnswer)
    end
end

B.Start()
