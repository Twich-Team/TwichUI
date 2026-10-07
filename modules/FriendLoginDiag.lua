-- TEMPORARY: friend login diagnostics. Off until asked for with /tui frienddiag, and nothing is saved.
-- To retire it once the friend login card is confirmed in the game: delete this file, its line in the
-- .toc, the "frienddiag" command in Core.lua and tests/test_friend_login_diag.lua. The Note() calls in
-- FriendLogin.lua do nothing without it and can stay or go.
--
-- It separates two questions that a card on screen cannot tell apart:
--   * Does the game's friend event reach TwichUI, and what does TwichUI decide about it? (trace)
--   * Can the card and chime be shown at all? (test, sound: synthetic, they prove nothing about events)
-- The trace listens on its own frame, so it still sees the game's events if the module's own listener
-- were somehow missing. It records times, event names, what the event was taken to mean, and why a
-- notification was skipped. Friends appear only as anonymous labels for this session (F1 = a
-- Battle.net account, C1 = a character friend). No names, BattleTags, account ids or friend records
-- are stored or shown. It reads the friend list only to compare online states, sends nothing to
-- anyone, changes no friend or Battle.net status, and keeps at most MAX_ENTRIES lines in memory.

local R = TwichUI
local D = {}
R.FriendLoginDiag = D

local MAX_ENTRIES = 200
local COALESCE = 2   -- seconds: repeats of the same quiet kind of event become one line with a count

-- Real friend events the game may send, and nothing else. Registered only while tracing.
local EVENTS = {
    "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED",
    "FRIENDLIST_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_BN_INLINE_TOAST_ALERT",
    "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
}

local tracing, started, enteredAt
local frame
local buffer = {}
local labels, counts = {}, { F = 0, C = 0 }
local bnState, legacyState = {}, {}
local refused = {}     -- events the game would not let us listen for
local baseline = { bn = 0, legacy = 0 }
local patterns
local window

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if type(v) ~= "string" or Secret(v) or v == "" then return nil end
    return v
end

local function Say(fmt, ...) print(R.GOLD .. "friend diag:|r " .. fmt:format(...)) end

-- A value for the report that cannot carry anything personal.
local function Flag(v)
    if Secret(v) then return "?" end
    if v == true then return "yes" elseif v == false then return "no" end
    return "?"
end

local function Code(v)   -- a product or client code such as "WoW" or "App"
    v = Plain(v)
    return v and v:gsub("[^%w_%-]", "?"):sub(1, 12) or "none"
end

local function Number(v) return type(v) == "number" and not Secret(v) and tostring(v) or "none" end

-- A stable anonymous label for one friend for this session. kind: "F" or "C". key: the id or guid, never printed.
local function Label(kind, key)
    if key == nil or Secret(key) or not (type(key) == "number" or type(key) == "string") then return kind .. "?" end
    local id = kind .. ":" .. tostring(key)
    local label = labels[id]
    if not label then
        counts[kind] = counts[kind] + 1
        label = kind .. counts[kind]
        labels[id] = label
    end
    return label
end

local function Context()
    local _
    local combat = InCombatLockdown and InCombatLockdown() and "combat" or "no-combat"
    local kind
    if IsInInstance then _, kind = IsInInstance() end
    local since = enteredAt and ("login+%ds"):format(GetTime() - enteredAt) or "login+?"
    return ("%s, %s, %s"):format(combat, kind or "?", since)
end

local function Add(key, text, quiet)
    if not tracing then return end
    local now = GetTime()
    local last = buffer[#buffer]
    if quiet and last and last.key == key and now - last.last <= COALESCE then
        last.n, last.last = last.n + 1, now
        return
    end
    if #buffer >= MAX_ENTRIES then table.remove(buffer, 1) end
    buffer[#buffer + 1] = { t = now - started, last = now, key = key, text = text, n = 1, ctx = Context() }
end

local function Facts(info)
    if type(info) ~= "table" then return "info=none" end
    local g = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local named = (Plain(info.accountName) or Plain(info.battleTag)) and "yes" or "no"
    return ("info=ok name=%s gameOnline=%s client=%s project=%s character=%s faction=%s"):format(
        named, Flag(g.isOnline), Code(g.clientProgram), Number(g.wowProjectID),
        Plain(g.characterName) and "yes" or "no", Plain(g.factionName) and "yes" or "no")
end

---------------------------------------------------------------------------
-- Battle.net friends. Account-level events carry an account id; the info-changed event carries a list
-- position, which is not stable, so it is turned into the account before anything is compared.
---------------------------------------------------------------------------
local function Remember(label, info)
    local g = type(info) == "table" and type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local online = g.isOnline
    if Secret(online) then online = nil end
    local state = { online = online, client = Code(g.clientProgram), char = Plain(g.characterName) }   -- kept here only to compare, never printed
    local previous = bnState[label]
    bnState[label] = state
    return previous, state
end

local function Transition(previous, state)
    if not previous then return "first-seen" end
    local changes = {}
    if previous.online ~= state.online then
        changes[#changes + 1] = state.online and "went-online" or "went-offline"
    end
    if previous.client ~= state.client then
        local nowWow, wasWow = state.client:lower():find("^wow"), previous.client:lower():find("^wow")
        changes[#changes + 1] = (nowWow and not wasWow and "entered-wow")
            or (wasWow and not nowWow and "left-wow")
            or "client-changed"
        changes[#changes] = changes[#changes] .. ("(%s>%s)"):format(previous.client, state.client)
    end
    if previous.char ~= state.char then changes[#changes + 1] = "character-changed" end
    return #changes > 0 and table.concat(changes, ",") or nil
end

local function OnAccount(event, friendId, companion)
    local label = Label("F", friendId)
    local info = type(friendId) == "number" and not Secret(friendId)
        and C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(friendId) or nil
    Remember(label, info)
    local kind = event == "BN_FRIEND_ACCOUNT_ONLINE" and "account-online" or "account-offline"
    Add(event, ("%s  %s  %s  companionApp=%s  %s"):format(event, kind, label, Flag(companion), Facts(info)))
end

local function OnInfoChanged(event, index)
    local info = type(index) == "number" and not Secret(index)
        and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(index) or nil
    if type(info) ~= "table" then
        Add(event .. ":none", event .. "  friend not resolvable from its list position", true)
        return
    end
    local label = Label("F", info.bnetAccountID)
    local change = Transition(Remember(label, info))
    if change then
        Add(event, ("%s  %s  %s  %s"):format(event, label, change, Facts(info)))
    else
        Add(event .. ":same", ("%s  no change in online state, client or character (note, broadcast, status...)"):format(event), true)
    end
end

---------------------------------------------------------------------------
-- Character friends (the game's own in-game list): its update event carries nothing, so the list is
-- compared with the last look, by guid. Looked at only when the event fires.
---------------------------------------------------------------------------
local function ScanLegacy(quiet)
    local list = C_FriendList
    if not (list and list.GetNumFriends and list.GetFriendInfoByIndex) then return nil end
    local n = list.GetNumFriends()
    if type(n) ~= "number" or Secret(n) then return nil end
    local seen, changes, unreadable = {}, {}, 0
    for i = 1, n do
        local info = list.GetFriendInfoByIndex(i)
        local guid = type(info) == "table" and Plain(info.guid) or nil
        local connected = type(info) == "table" and info.connected
        if guid and not Secret(connected) then
            local label = Label("C", guid)
            seen[label] = true
            local online = connected == true
            local previous = legacyState[label]
            legacyState[label] = online
            if not quiet and previous ~= nil and previous ~= online then
                changes[#changes + 1] = label .. (online and " went-online" or " went-offline")
            end
        else
            unreadable = unreadable + 1
        end
    end
    for label in pairs(legacyState) do
        if not seen[label] then legacyState[label] = nil end   -- removed from the list: forget it
    end
    return n, changes, unreadable
end

local function OnLegacyUpdate(event)
    local n, changes, unreadable = ScanLegacy(false)
    if not n then Add(event .. ":api", event .. "  character friend list not readable", true) return end
    if #changes > 0 then
        Add(event, ("%s  character friends: %s  (%d on list, %d unreadable)"):format(event, table.concat(changes, ", "), n, unreadable))
    else
        Add(event .. ":same", ("%s  no character friend changed online state"):format(event), true)
    end
end

---------------------------------------------------------------------------
-- Chat lines the game prints on its own. Only the kind is kept, never the text.
---------------------------------------------------------------------------
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local escaped = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    return "^" .. escaped:gsub("%%%%s", ".+") .. "$"
end

local function OnSystem(event, text)
    if Secret(text) then Add(event .. ":secret", event .. "  text unreadable (secret value); not classified", true) return end
    if type(text) ~= "string" then return end
    patterns = patterns or { online = ToPattern(ERR_FRIEND_ONLINE_SS), offline = ToPattern(ERR_FRIEND_OFFLINE_S) }
    if patterns.online and text:find(patterns.online) then
        Add(event, event .. "  character-friend-online system line")
    elseif patterns.offline and text:find(patterns.offline) then
        Add(event, event .. "  character-friend-offline system line")
    end
end

local TOASTS = { FRIEND_ONLINE = true, FRIEND_OFFLINE = true }
local function OnBNLine(event, kind)
    if Secret(kind) then Add(event, event .. "  kind unreadable (secret)") return end
    Add(event, ("%s  %s"):format(event, TOASTS[kind] and kind or "other-kind"))
end

---------------------------------------------------------------------------
-- Dispatch, and the module's own decisions (FriendLogin.Note)
---------------------------------------------------------------------------
local HANDLERS = {
    BN_FRIEND_ACCOUNT_ONLINE = OnAccount,
    BN_FRIEND_ACCOUNT_OFFLINE = OnAccount,
    BN_FRIEND_INFO_CHANGED = OnInfoChanged,
    FRIENDLIST_UPDATE = OnLegacyUpdate,
    CHAT_MSG_SYSTEM = OnSystem,
    CHAT_MSG_BN_INLINE_TOAST_ALERT = OnBNLine,
    BN_CONNECTED = function(event, quiet) Add(event, ("%s  suppressNotification=%s"):format(event, Flag(quiet))) end,
    BN_DISCONNECTED = function(event) Add(event, event) end,
    PLAYER_ENTERING_WORLD = function(event, isLogin, isReload)
        if isLogin or isReload then enteredAt = GetTime() end
        Add(event, ("%s  isLogin=%s isReload=%s"):format(event, Flag(isLogin), Flag(isReload)))
    end,
    PLAYER_LEAVING_WORLD = function(event) Add(event, event) end,
}

local function OnEvent(_, event, ...)
    local handler = HANDLERS[event]
    if not handler then return end
    local ok, err = pcall(handler, event, ...)
    if not ok then Add("diag-error", ("diagnostic error on %s: %s"):format(event, tostring(err):sub(1, 80)), true) end
end

local function OnNote(stage, id, detail)
    local who = id ~= nil and (" " .. Label("F", id)) or ""
    local why = detail ~= nil and (" (" .. tostring(detail) .. ")") or ""
    Add("module:" .. stage, ("module  %s%s%s"):format(stage, who, why), stage == "look:stale")
end

---------------------------------------------------------------------------
-- Tracing on and off
---------------------------------------------------------------------------
local function Baseline()
    baseline.bn, baseline.legacy = 0, 0
    local total = type(BNGetNumFriends) == "function" and BNGetNumFriends() or 0
    if type(total) == "number" and not Secret(total) and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, total do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if type(info) == "table" then
                Remember(Label("F", info.bnetAccountID), info)
                baseline.bn = baseline.bn + 1
            end
        end
    end
    baseline.legacy = ScanLegacy(true) or 0
end

function D.Tracing() return tracing and true or false end

function D.Start()
    if tracing then return false end
    tracing, started = true, GetTime()
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    wipe(refused)
    for _, event in ipairs(EVENTS) do
        if not pcall(frame.RegisterEvent, frame, event) then refused[#refused + 1] = event end
    end
    if R.FriendLogin then R.FriendLogin.Note = OnNote end
    Baseline()
    Add("trace", ("tracing started; baseline: %d Battle.net friends, %d character friends"):format(baseline.bn, baseline.legacy))
    for _, event in ipairs(refused) do Add("trace", "the game would not let this listen for " .. event) end
    return true
end

function D.Stop()
    if not tracing then return false end
    Add("trace", "tracing stopped")
    tracing = false
    if frame then frame:UnregisterAllEvents() end
    if R.FriendLogin then R.FriendLogin.Note = nil end
    return true
end

---------------------------------------------------------------------------
-- Status and report
---------------------------------------------------------------------------
local function CVar(name)
    local value = GetCVar and GetCVar(name)
    return value == nil and "?" or tostring(value)
end

function D.StatusLines()
    local F = R.FriendLogin
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    if not F then Line("module: not loaded") return lines end
    local s = F.State()
    Line("module: %s; chime %s on %s", s.enabled and "on" or "off", s.soundOn and "on" or "off", s.channel)
    Line("would show a login now: %s", s.notWanted and ("no (" .. s.notWanted .. ")") or "yes")
    Line("game options: Show Toast Window=%s, Online Friends=%s, Offline Friends=%s",
        CVar("showToastWindow"), CVar("showToastOnline"), CVar("showToastOffline"))
    Line("game's own pop-up: %s; TwichUI has taken the event from it: %s", s.gamePopup, s.takenFromGame and "yes" or "no")
    Line("module listens for: %s", #s.events > 0 and table.concat(s.events, ", ") or "nothing")
    Line("card: can be built=%s, on screen=%s, waiting=%d, login quiet time left=%.1fs, in the way=%s",
        s.capable and "yes" or "no", s.cardShowing and "yes" or "no", s.waiting, s.quietLeft, s.inTheWay or "nothing")
    Line("snapshot: none kept by the module; the friend is looked up when the event arrives")
    local total, online = 0, 0
    if type(BNGetNumFriends) == "function" then total, online = BNGetNumFriends() end
    Line("friend list as the game reports it now: Battle.net %s total / %s online; character friends online %s",
        Number(total), Number(online), Number(C_FriendList and C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends()))
    Line("sound options: all=%s, effects=%s, dialog=%s, ambience=%s; volumes master=%s effects=%s dialog=%s ambience=%s",
        CVar("Sound_EnableAllSound"), CVar("Sound_EnableSFX"), CVar("Sound_EnableDialog"), CVar("Sound_EnableAmbience"),
        CVar("Sound_MasterVolume"), CVar("Sound_SFXVolume"), CVar("Sound_DialogVolume"), CVar("Sound_AmbienceVolume"))
    Line("trace: %s; %d of at most %d lines kept; baseline %d Battle.net / %d character friends",
        tracing and ("on for %ds"):format(GetTime() - started) or "off", #buffer, MAX_ENTRIES, baseline.bn, baseline.legacy)
    if refused[1] then Line("events the game refused to let the trace listen for: %s", table.concat(refused, ", ")) end
    return lines
end

function D.Report()
    local lines = { "TwichUI friend login diagnostic report (local only; no names, BattleTags or ids)" }
    local version, build
    if GetBuildInfo then version, build = GetBuildInfo() end
    lines[#lines + 1] = ("game %s build %s, locale %s, TwichUI %s"):format(
        tostring(version), tostring(build), tostring(GetLocale and GetLocale()), R.Group and R.Group.Version and tostring(R.Group.Version()) or "?")
    lines[#lines + 1] = "-- status --"
    for _, line in ipairs(D.StatusLines()) do lines[#lines + 1] = line end
    lines[#lines + 1] = "-- trace, oldest first. Labels: F# Battle.net account, C# character friend. [combat?, instance type, seconds since login/reload] --"
    if #buffer == 0 then lines[#lines + 1] = "(nothing recorded)" end
    for _, e in ipairs(buffer) do
        lines[#lines + 1] = ("+%.1fs  %s%s  [%s]"):format(e.t, e.text, e.n > 1 and (" x" .. e.n) or "", e.ctx)
    end
    lines[#lines + 1] = "-- end --"
    return table.concat(lines, "\n")
end

-- A small copy window: select all, Ctrl+C. Made the first time it is asked for.
local function BuildWindow()
    local K = R.ChronicleStyle and R.ChronicleStyle.color
    local f = CreateFrame("Frame", "TwichUIFriendDiagReport", UIParent, "BackdropTemplate")
    f:SetSize(640, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    local bg, edge = K and K.bg or { 0.15, 0.115, 0.08 }, K and K.bronze or { 0.55, 0.43, 0.22 }
    f:SetBackdropColor(bg[1], bg[2], bg[3], 0.97)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    tinsert(UISpecialFrames, "TwichUIFriendDiagReport")
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("TwichUI friend login report (temporary)")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetText("Click in the text, Ctrl+A, Ctrl+C. Nothing here names a friend. Esc closes.")

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -52)
    scroll:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(580)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    scroll:SetScrollChild(edit)
    f.edit = edit

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    return f
end

function D.ShowReport()
    if not window then window = BuildWindow() end
    local text = D.Report()
    window.edit:SetText(text)
    if #window.edit:GetText() < #text then
        Say("the copy box held only part of the report; use /tui frienddiag report chat for the latest lines.")
    end
    window:Show()
end

function D.ReportToChat(last)
    local text = D.Report()
    local all = {}
    for line in text:gmatch("[^\n]+") do all[#all + 1] = line end
    for i = math.max(1, #all - (last or 30) + 1), #all do print((all[i]:gsub("|", "||"))) end
end

-- Stops tracing and forgets everything: lines, labels, states, the window's text.
function D.Reset()
    D.Stop()
    wipe(buffer); wipe(labels); wipe(bnState); wipe(legacyState); wipe(refused)
    counts.F, counts.C = 0, 0
    baseline.bn, baseline.legacy = 0, 0
    patterns, enteredAt = nil, nil
    if window then window.edit:SetText("") window:Hide() end
end

---------------------------------------------------------------------------
-- Synthetic tests: they prove the card and the chime can be shown, nothing about friend events.
---------------------------------------------------------------------------
function D.TestCard()
    local F = R.FriendLogin
    if not F then Say("friend login isn't available.") return end
    Add("synthetic", "SYNTHETIC login card shown with made-up details (not a real friend event)")
    F.Preview()
    Say("shown a made-up login card (and its chime). This proves the card can be drawn; it says nothing about whether real friend events arrive.")
end

function D.TestSound(stock)
    local F = R.FriendLogin
    if not F then Say("friend login isn't available.") return end
    if stock then
        local ok = PlaySound and SOUNDKIT and SOUNDKIT.UI_BNET_TOAST and PlaySound(SOUNDKIT.UI_BNET_TOAST)
        Say("asked for the game's own friend pop-up sound: %s. If you hear this but not the chime, the chime's file or channel is the problem.", ok and "accepted" or "refused or unavailable")
        return
    end
    local ok = F.PlaySound()
    Add("synthetic", "SYNTHETIC chime requested on " .. F.SoundChannel() .. (ok and ": accepted" or ": refused"))
    Say("asked for the chime on channel %s: the game %s it. Sound options: all=%s, effects=%s, master volume=%s. Try /tui frienddiag sound stock for the game's own sound.",
        F.SoundChannel(), ok and "accepted" or "refused", CVar("Sound_EnableAllSound"), CVar("Sound_EnableSFX"), CVar("Sound_MasterVolume"))
end

---------------------------------------------------------------------------
-- /tui frienddiag
---------------------------------------------------------------------------
local USAGE = "status | test [login|logout] | sound [stock] | trace [on|off] | report [chat] | reset"

function D.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word, rest = word:lower(), rest:lower()
    if word == "status" then
        for _, line in ipairs(D.StatusLines()) do print(R.GOLD .. "  -|r " .. line) end
    elseif word == "test" then
        if rest == "logout" then
            Say("there is no TwichUI logout card; the game's own offline pop-up and chat line are untouched. Only login is built.")
        else
            D.TestCard()
        end
    elseif word == "sound" then
        D.TestSound(rest == "stock")
    elseif word == "trace" then
        if rest == "off" then
            Say(D.Stop() and "tracing stopped; /tui frienddiag report shows what was recorded." or "tracing was not on.")
        elseif rest == "" or rest == "on" then
            Say(D.Start() and "tracing real friend events (kept in memory only, at most %d lines). Have a friend log in or out, then /tui frienddiag report." or "already tracing.", MAX_ENTRIES)
        else
            Say("usage: /tui frienddiag trace on|off")
        end
    elseif word == "report" then
        if rest == "chat" then D.ReportToChat() else D.ShowReport() end
    elseif word == "reset" then
        D.Reset()
        Say("tracing stopped and everything recorded has been cleared.")
    else
        Say("usage: /tui frienddiag %s", USAGE)
        Say("test and sound are synthetic: they prove the card and chime work, not that friend events arrive. trace is off until you turn it on.")
    end
end
