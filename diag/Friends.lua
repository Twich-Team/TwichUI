-- TwichUI: troubleshooting report, friend notifications
-- Replaces the temporary friend login diagnostics. Two parts:
--   * The report section: what the friend login card is doing right now, from F.State() and F.Counts().
--   * A tracer, listening only while tracing is on, that watches the game's real friend events on its own
--     frame (so it still sees them if the module's listener were missing) and records what each event
--     was taken to mean. The module's own decisions (queued, skipped and why, shown) arrive from
--     FriendLogin.lua through D.Trace.
-- Friends appear only as labels that are the same for one trace (F1 = a Battle.net account, C1 = a
-- character friend). Names, BattleTags, ids, guids and friend records are not recorded; the few facts
-- needed to compare one look with the last (online state, client, a signature of the character) are
-- kept in memory only while tracing, and the character is kept as a number, not as text.
-- The synthetic tests (a made-up card, the chime) are marked SYNTHETIC: they prove the card and sound
-- can be drawn and played, and nothing about whether real friend events arrive.

local R = TwichUI
local D = R.Diag
local T = {}
R.DiagFriends = T

-- Real friend events the game may send, and nothing else. Registered only while tracing.
local EVENTS = {
    "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED",
    "FRIENDLIST_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_BN_INLINE_TOAST_ALERT",
    "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD",
}

local SRC = "friend-event"   -- the game's events; the module's own decisions are "friend"
local bnState, legacyState = {}, {}
local baseline = { bn = 0, legacy = 0, taken = false }
local patterns

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if type(v) ~= "string" or Secret(v) or v == "" then return nil end
    return v
end

local function Number(v) return type(v) == "number" and not Secret(v) and tostring(v) or "none" end

local function Code(v)   -- a product or client code such as "WoW" or "App"
    v = Plain(v)
    return v and v:gsub("[^%w_%-]", "?"):sub(1, 12) or "none"
end

-- A number standing for a string, so two looks can be compared without keeping the string.
local function Signature(s)
    if not s then return 0 end
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function Trace(code, detail, subject) D.Trace(SRC, code, detail, subject) end

local function Facts(info)
    if type(info) ~= "table" then return "info=none" end
    local g = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local named = (Plain(info.accountName) or Plain(info.battleTag)) and "y" or "n"
    return ("info=ok name=%s online=%s client=%s proj=%s char=%s fac=%s"):format(
        named, D.Flag(g.isOnline):sub(1, 1), Code(g.clientProgram), Number(g.wowProjectID),
        Plain(g.characterName) and "y" or "n", Plain(g.factionName) and "y" or "n")
end

---------------------------------------------------------------------------
-- Battle.net friends. Account-level events carry an account id; the info-changed event carries a list
-- position, which is not stable, so it is turned into the account before anything is compared.
---------------------------------------------------------------------------
local function Remember(label, info)
    local g = type(info) == "table" and type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
    local online = g.isOnline
    if Secret(online) then online = nil end
    local state = { online = online, client = Code(g.clientProgram), char = Signature(Plain(g.characterName)) }
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
        changes[#changes + 1] = ((nowWow and not wasWow and "entered-wow")
            or (wasWow and not nowWow and "left-wow")
            or "client-changed") .. ("(%s>%s)"):format(previous.client, state.client)
    end
    if previous.char ~= state.char then changes[#changes + 1] = "character-changed" end
    return #changes > 0 and table.concat(changes, ",") or nil
end

local function OnAccount(event, friendId, companion)
    local label = D.Label("F", friendId)
    local info = type(friendId) == "number" and not Secret(friendId)
        and C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(friendId) or nil
    Remember(label, info)
    Trace(event, ("%s companion=%s %s"):format(event == "BN_FRIEND_ACCOUNT_ONLINE" and "account-online" or "account-offline",
        D.Flag(companion):sub(1, 1), Facts(info)), friendId)
end

local function OnInfoChanged(event, index)
    local info = type(index) == "number" and not Secret(index)
        and C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(index) or nil
    if type(info) ~= "table" then
        Trace(event, "friend not resolvable from its list position")
        return
    end
    local label = D.Label("F", info.bnetAccountID)
    local change = Transition(Remember(label, info))
    if change then
        Trace(event, change .. " " .. Facts(info), info.bnetAccountID)
    else
        Trace(event, "no change in online state, client or character (note, broadcast, status...)", info.bnetAccountID)
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
            local label = D.Label("C", guid)
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
    if not n then Trace(event, "character friend list not readable") return end
    if #changes > 0 then
        Trace(event, ("character friends: %s (%d on list, %d unreadable)"):format(table.concat(changes, ", "), n, unreadable))
    else
        Trace(event, "no character friend changed online state")
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
    if Secret(text) then Trace(event, "text unreadable (secret value); not classified") return end
    if type(text) ~= "string" then return end
    patterns = patterns or { online = ToPattern(ERR_FRIEND_ONLINE_SS), offline = ToPattern(ERR_FRIEND_OFFLINE_S) }
    if patterns.online and text:find(patterns.online) then
        Trace(event, "character-friend-online system line")
    elseif patterns.offline and text:find(patterns.offline) then
        Trace(event, "character-friend-offline system line")
    end
end

local TOASTS = { FRIEND_ONLINE = true, FRIEND_OFFLINE = true }
local function OnBNLine(event, kind)
    if Secret(kind) then Trace(event, "kind unreadable (secret)") return end
    Trace(event, TOASTS[kind] and kind or "other-kind")
end

local HANDLERS = {
    BN_FRIEND_ACCOUNT_ONLINE = OnAccount,
    BN_FRIEND_ACCOUNT_OFFLINE = OnAccount,
    BN_FRIEND_INFO_CHANGED = OnInfoChanged,
    FRIENDLIST_UPDATE = OnLegacyUpdate,
    CHAT_MSG_SYSTEM = OnSystem,
    CHAT_MSG_BN_INLINE_TOAST_ALERT = OnBNLine,
    BN_CONNECTED = function(event, quiet) Trace(event, "suppressNotification=" .. D.Flag(quiet)) end,
    BN_DISCONNECTED = function(event) Trace(event) end,
    PLAYER_ENTERING_WORLD = function(event, isLogin, isReload)
        Trace(event, ("isLogin=%s isReload=%s"):format(D.Flag(isLogin), D.Flag(isReload)))
    end,
    PLAYER_LEAVING_WORLD = function(event) Trace(event) end,
}

---------------------------------------------------------------------------
-- The tracer
---------------------------------------------------------------------------
local function Forget()
    wipe(bnState)
    wipe(legacyState)
    baseline.bn, baseline.legacy, baseline.taken = 0, 0, false
    patterns = nil
end

-- Taken once, when tracing starts, so later changes can be told from what was already so.
local function TakeBaseline()
    baseline.bn, baseline.legacy, baseline.taken = 0, 0, true
    local total = type(BNGetNumFriends) == "function" and BNGetNumFriends() or 0
    if type(total) == "number" and not Secret(total) and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        for i = 1, total do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if type(info) == "table" then
                Remember(D.Label("F", info.bnetAccountID), info)
                baseline.bn = baseline.bn + 1
            end
        end
    end
    baseline.legacy = ScanLegacy(true) or 0
    Trace("baseline", ("%d Battle.net friends, %d character friends"):format(baseline.bn, baseline.legacy))
end

D.RegisterTracer("friend", {
    events = EVENTS,
    start = TakeBaseline,
    stop = Forget,
    clear = Forget,
    onEvent = function(event, ...)
        local handler = HANDLERS[event]
        if handler then handler(event, ...) end
    end,
})

---------------------------------------------------------------------------
-- The report section
---------------------------------------------------------------------------
local function CVar(name)
    local value = GetCVar and GetCVar(name)
    return value == nil and "?" or tostring(value)
end

local function Counts(F)
    local list = {}
    for key, n in pairs(F.Counts()) do list[#list + 1] = ("%s x%d"):format(key, n) end
    table.sort(list)
    return list
end

local function Friend()
    local F = R.FriendLogin
    if not F then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = F.State()
    local missing = {}
    for _, event in ipairs(s.wantedEvents) do
        if not s.registered[event] then missing[#missing + 1] = event end
    end
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("friend login card: %s; chime: %s (follows the %s volume)", s.enabled and "on" or "off", s.soundOn and "on" or "off", s.channel)
    if s.enabled then
        Line("required events: %d of %d registered%s", #s.wantedEvents - #missing, #s.wantedEvents,
            #missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or "")
    else
        Line("required events: not wanted while the card is off")
    end
    Line("would show a login now: %s", s.notWanted and ("no (" .. s.notWanted .. ")") or "yes")
    Line("game options: Show Toast Window=%s, Online Friends=%s, Offline Friends=%s",
        CVar("showToastWindow"), CVar("showToastOnline"), CVar("showToastOffline"))
    Line("game's own pop-up: %s; TwichUI has taken the event from it: %s", s.gamePopup, s.takenFromGame and "yes" or "no")
    Line("card state: can be built=%s, on screen=%s, waiting=%d, login quiet time left=%.1fs, in the way=%s",
        s.capable and "yes" or "no", s.cardShowing and "yes" or "no", s.waiting, s.quietLeft, s.inTheWay or "nothing")
    Line("initial presence snapshot: not used by this module (the friend is looked up when the event arrives)")
    if baseline.taken then
        Line("trace baseline: %d Battle.net friends and %d character friends, taken when tracing started (counts only)", baseline.bn, baseline.legacy)
    else
        Line("trace baseline: none (tracing is off)")
    end
    local total, online = 0, 0
    if type(BNGetNumFriends) == "function" then total, online = BNGetNumFriends() end
    Line("friend list as the game reports it now: Battle.net %s total / %s online; character friends online %s",
        Number(total), Number(online), Number(C_FriendList and C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends()))
    Line("sound options: all=%s, effects=%s; volumes master=%s effects=%s dialog=%s ambience=%s",
        CVar("Sound_EnableAllSound"), CVar("Sound_EnableSFX"),
        CVar("Sound_MasterVolume"), CVar("Sound_SFXVolume"), CVar("Sound_DialogVolume"), CVar("Sound_AmbienceVolume"))
    local counts = Counts(F)
    Line("logins skipped or let go since the game started: %s", #counts > 0 and table.concat(counts, ", ") or "none")

    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not s.capable then status, reason = "unavailable", "card-cannot-be-built"
    elseif #missing > 0 then status, reason = "unavailable", "event-not-registered"
    elseif s.notWanted then status, reason = "unavailable", s.notWanted
    elseif s.gamePopup == "has-event" then status, reason = "waiting", "game-popup-still-has-event" end
    local initialized
    if s.enabled then initialized = #missing == 0 end
    return {
        configured = s.enabled, initialized = initialized, status = status, reason = reason,
        lines = lines,
        limits = {
            "A card on screen cannot show whether the game's friend event reached TwichUI; start tracing and have a friend log in to see the event and the decision.",
            "Only Battle.net account logins are announced: not logoffs, character (in-game list) friends, or a friend already online when WoW started.",
        },
    }
end

D.Register("friend", { title = "Friend notifications", order = 30, snapshot = Friend })

---------------------------------------------------------------------------
-- Synthetic tests (/tui diagnostics test friend | test sound [stock])
---------------------------------------------------------------------------
local function Say(fmt, ...) R.Print("troubleshooting: " .. fmt, ...) end

function T.TestCard()
    local F = R.FriendLogin
    if not F then Say("friend login isn't available.") return end
    D.Synthetic("friend", "card-test", "made-up friend; not a real event")
    F.Preview(true)   -- with the chime, as a real card would
    Say("shown a made-up login card (and its chime). This proves the card can be drawn; it says nothing about whether real friend events arrive.")
end

function T.TestSound(stock)
    local F = R.FriendLogin
    if not F then Say("friend login isn't available.") return end
    if stock then
        local ok = PlaySound and SOUNDKIT and SOUNDKIT.UI_BNET_TOAST and PlaySound(SOUNDKIT.UI_BNET_TOAST)
        D.Synthetic("friend", "sound-test", "game's own pop-up sound: " .. (ok and "accepted" or "refused"))
        Say("asked for the game's own friend pop-up sound: %s. If you hear this but not the chime, the chime's file or channel is the problem.", ok and "accepted" or "refused or unavailable")
        return
    end
    local ok = F.PlaySound()
    D.Synthetic("friend", "sound-test", "chime on " .. F.SoundChannel() .. ": " .. (ok and "accepted" or "refused"))
    Say("asked for the chime on channel %s: the game %s it. Sound options: all=%s, effects=%s, master volume=%s. Try /tui diagnostics test sound stock for the game's own sound.",
        F.SoundChannel(), ok and "accepted" or "refused", CVar("Sound_EnableAllSound"), CVar("Sound_EnableSFX"), CVar("Sound_MasterVolume"))
end
