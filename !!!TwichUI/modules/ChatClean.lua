-- TwichUI: chat cleaning
-- Hides unwanted messages in the public channels you choose (General, Trade and the like) before they reach your chat.
-- Off until turned on (modules.chatClean, only an explicit true). Whispers, party, raid, instance, guild, officer,
-- say, yell, emotes, system messages and combat text are never looked at: only CHAT_MSG_CHANNEL is, and only in the
-- channels you chose. Messages from you, your friends (Battle.net friends included), your guild and your group are
-- never hidden. Nothing is reported, ignored, blocked or sent: a hidden message is simply not shown.
--
-- How (verified in the Forever client's source, Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua and
-- Mainline/ChatFrameOverrides.lua): ChatFrameUtil.AddMessageEventFilter(event, fn) adds fn to the filters every chat
-- frame's MessageEventHandler runs before it draws a message. fn(chatFrame, event, ...) returning true discards the
-- message for that frame; returning false (with nothing after it) lets it through unchanged, and the next filter runs.
-- The game skips addon filters for a message whose values are secret (canaccessvalue), and a filter that errors lets
-- the message through. EllesmereUI's chat keeps the game's chat frames and their handler, filters included, and copies
-- what they print into its own windows from an AddMessage hook (EllesmereUIChat_Engine.lua), so a message discarded
-- here never reaches its windows or its session history either. Nothing here hooks a chat frame.
--   * The filter runs once per chat frame that receives the event. The decision is made the first time a line is
--     seen (by the line's ID, arg 11) and repeated for the other frames, so each incoming message is evaluated, counted
--     and shown in the live view once.
--   * Registered only while chat cleaning is on and has something to do; removed (only TwichUI's own filter) when it
--     is turned off. Other addons' filters are never touched.
--   * An unexpected error lets that message through and is noted for /tui diagnostics (coalesced, nothing printed).
--
-- Channels. System channels (General, Trade, LocalDefense, ...) are known by the zone channel ID the game sends with
-- every message (arg 7, zoneChannelID): it is the same in every zone and city, whatever number the channel has in
-- your list (/2, /4) and whatever language the client uses. General's is C_ChatInfo.GetGeneralChannelID(). The game
-- has no call naming Trade's; 2, its customary ID, is used only to preselect it for you to review before turning
-- cleaning on (unverified on Forever; the list shows the name the client gives that channel, so you can see what is
-- chosen). Custom channels (zoneChannelID 0) have nothing but their name, so they are matched by name, ignoring case.
--   key "zone:<zoneChannelID>" or "custom:<lowercased name>"
--
-- Settings (per profile, TwichUIDB.ui.chatClean; the settings window edits them only through the functions below):
--   channels  { [key] = { on, spam, repeats, recruit, politics, lgbt, label } }. Missing (never changed): the recommended
--             choice, General and Trade with the spam and repeat filters, until something is changed, when it is saved.
--             politics and lgbt (topic presets, see ChatCleanMatch.lua) are off unless ticked; a missing one is off.
--   rules     { { id, name, mode, text, case, enabled, all, channels = { [key] = true } }, ... } in the order they are
--             checked. all: every channel being cleaned; otherwise only the channels listed.
--   nextId    the next rule's id
-- Nothing about messages is saved: no captured chat, no senders, no counts, no repeat memory.
--
-- What a message is checked against, in this order (the first that matches is the reason shown): the channel's
-- custom rules in list order, then Gold selling spam, Guild recruitment, the Politics and LGBTQ Topics presets and
-- Repeated messages. Matching is in modules/ChatCleanMatch.lua. Repeated messages: the same text (ignoring case, spaces
-- and punctuation) from the same player again within REPEAT_WINDOW seconds of their previous copy; at most REPEAT_MAX
-- entries of a player ID and a number standing for the text (never the text), forgotten after the window and when
-- cleaning is turned off.

local R = TwichUI
local M = R.ChatCleanMatch
local CC = {}
R.ChatClean = CC

CC.MAX_RULES = 50
CC.MAX_CHANNELS = 32
CC.LABEL_MAX = 40
CC.REPEAT_WINDOW = 60
CC.REPEAT_MAX = 200
CC.TRADE_ID = 2         -- customary; only used to preselect Trade for review (see above)
CC.EVENT = "CHAT_MSG_CHANNEL"

-- The built-in filters, in the order they are checked.
CC.CATEGORIES = {
    { key = "spam", label = "Gold selling spam", short = "Spam",
      text = "Adverts selling gold, boosts or levelling for real money: a message with a web address, something for sale and a price or discount, all together. Also community and guild invitation links named like a gold shop (a web address and gold, boosts or levelling). An ordinary trade message (WTS [item] 5g), a link or a capitalized message is never enough on its own. Spam that disguises itself well still gets through." },
    { key = "recruit", label = "Guild recruitment", short = "Recruiting",
      text = "Guild recruitment adverts: messages with the word recruit, or that mention a guild and invite you to join, whisper or apply. Also catches \"looking for a guild\" messages and some other guild talk, so it is off unless you choose it." },
    { key = "politics", label = "Politics", short = "Politics",
      text = "Hides messages containing selected real-world political names, party labels and slogans. Keyword matching may also hide unrelated mentions. Replies without the listed words stay visible. Only what you see in your own chat changes." },
    { key = "lgbt", label = "LGBTQ Topics", short = "LGBTQ",
      text = "Hides messages containing selected LGBTQ-related terms and discussion phrases. Keyword matching does not determine a message's intent. Replies without the listed words stay visible, and the list says nothing about anyone's identity. Only what you see in your own chat changes." },
    { key = "repeats", label = "Repeated messages", short = "Repeats",
      text = ("The same message from the same player again within %d seconds of their previous copy (ignoring case, spaces and punctuation). The first copy is shown; repeats are hidden while they keep coming."):format(CC.REPEAT_WINDOW) },
}
local CATEGORY = {}
for _, c in ipairs(CC.CATEGORIES) do CATEGORY[c.key] = c end
CC.CATEGORY = CATEGORY
local FLAGS = { on = true, spam = true, repeats = true, recruit = true, politics = true, lgbt = true }
CC.RECOMMENDED = { on = true, spam = true, repeats = true, recruit = false, politics = false, lgbt = false }

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Whole(v) return type(v) == "number" and v == v and v % 1 == 0 and v > -math.huge and v < math.huge end

---------------------------------------------------------------------------
-- Channels: keys and names
---------------------------------------------------------------------------
function CC.ZoneKey(id) return "zone:" .. id end
function CC.CustomKey(name) return "custom:" .. name:lower() end

-- Whether a key is one TwichUI can use: "zone:<1..1000000>" or "custom:<name of 1..40 plain characters>".
function CC.ValidKey(key)
    if type(key) ~= "string" then return false end
    local id = key:match("^zone:(%d+)$")
    if id then
        id = tonumber(id)
        return id >= 1 and id <= 1000000 and key == CC.ZoneKey(id)
    end
    local name = key:match("^custom:(.+)$")
    return name ~= nil and #name <= CC.LABEL_MAX * 4 and not name:find("[%c|]") and name == name:lower()
        and M.ValidUTF8(name) and M.Characters(name) <= CC.LABEL_MAX
end

function CC.GeneralID()
    local id = C_ChatInfo and C_ChatInfo.GetGeneralChannelID and Plain(C_ChatInfo.GetGeneralChannelID())
    if Whole(id) and id > 0 then return id end
    return 1   -- the customary ID, where the client has no call for it
end

local function CleanLabel(text)
    text = Plain(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if M.Characters(text) > CC.LABEL_MAX then
        local out, n = {}, 0
        for ch in text:gmatch("[^\128-\191][\128-\191]*") do
            n = n + 1
            if n > CC.LABEL_MAX then break end
            out[n] = ch
        end
        text = table.concat(out)
    end
    return text
end
CC.CleanLabel = CleanLabel

-- The name the client gives a system channel ("Trade", in the client's language), or nil.
local function ZoneName(id)
    if C_ChatInfo and C_ChatInfo.GetChannelShortcutForChannelID then
        local ok, name = pcall(C_ChatInfo.GetChannelShortcutForChannelID, id)
        if ok then return CleanLabel(name) end
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function CC.Enabled()
    local m = TwichUIDB and TwichUIDB.modules
    return type(m) == "table" and m.chatClean == true
end

local function Store(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.chatClean) ~= "table" then
        if not create then return nil end
        db.ui.chatClean = {}
    end
    return db.ui.chatClean
end

local function CleanChannel(e)
    if type(e) ~= "table" then return nil end
    local out = {}
    for flag in pairs(FLAGS) do out[flag] = e[flag] == true end
    out.label = CleanLabel(e.label)
    return out
end
CC.CleanChannel = CleanChannel

-- The channel choices in use, as copies: { [key] = { on, spam, repeats, recruit, politics, lgbt, label } }. Until something is
-- changed: the recommended choice.
function CC.Channels()
    local t = Store(false)
    local out, n = {}, 0
    if t and type(t.channels) == "table" then
        for key, e in pairs(t.channels) do
            local clean = CC.ValidKey(key) and CleanChannel(e)
            if clean and n < CC.MAX_CHANNELS then
                out[key], n = clean, n + 1
            end
        end
        return out, true
    end
    for _, id in ipairs({ CC.GeneralID(), CC.TRADE_ID }) do
        local e = CleanChannel(CC.RECOMMENDED)
        e.label = ZoneName(id) or (id == CC.GeneralID() and "General" or "Trade")
        out[CC.ZoneKey(id)] = e
    end
    return out, false
end

-- Whether the channel choices were ever saved (false: the recommended choice is in use, unchanged).
function CC.Customized()
    local t = Store(false)
    return t ~= nil and type(t.channels) == "table"
end

-- A rule as kept: { id, name, mode, text, case, enabled, all, channels }, or nil if it can't be used.
local function CleanRule(e)
    if type(e) ~= "table" then return nil end
    local base = M.CheckRule(e)
    if not base then return nil end
    base.id = Whole(e.id) and e.id >= 1 and e.id or nil
    base.enabled = e.enabled ~= false
    base.all = e.all ~= false
    local channels, n = {}, 0
    if type(e.channels) == "table" then
        for key, v in pairs(e.channels) do
            if v == true and CC.ValidKey(key) and n < CC.MAX_CHANNELS then channels[key], n = true, n + 1 end
        end
    end
    base.channels = channels
    if not base.all and n == 0 then base.all = true end   -- applies somewhere: with no channel named, all of them
    return base
end
CC.CleanRule = CleanRule

local function CopyRule(r)
    local c = { id = r.id, name = r.name, mode = r.mode, text = r.text, case = r.case, enabled = r.enabled, all = r.all, channels = {} }
    for k in pairs(r.channels) do c.channels[k] = true end
    return c
end
CC.CopyRule = CopyRule

-- The rules in order, as copies (each with an id).
function CC.Rules()
    local t = Store(false)
    local list, seen = {}, {}
    if t and type(t.rules) == "table" then
        for _, e in ipairs(t.rules) do
            local rule = CleanRule(e)
            if rule and rule.id and not seen[rule.id] then
                seen[rule.id] = true
                list[#list + 1] = rule
                if #list >= CC.MAX_RULES then break end
            end
        end
    end
    return list
end

function CC.Rule(id)
    for i, rule in ipairs(CC.Rules()) do
        if rule.id == id then return rule, i end
    end
end

-- A rule's name, or a summary of what it matches. Plain text.
function CC.RuleName(rule) return rule.name or M.Summary(rule) end

---------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------
local listeners = {}
-- fn() after the settings changed (the settings window redraws). Registered once each.
function CC.OnChange(fn)
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end
local function Notify()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("chat cleaning view", err) end
    end
end

local Changed   -- (below) every change to what is hidden goes through it

local function WriteRules(list)
    local t = Store(true)
    if not t then return false end
    local out, top = {}, 0
    for i, r in ipairs(list) do
        out[i] = CopyRule(r)
        if r.id > top then top = r.id end
    end
    t.rules = out
    if not (Whole(t.nextId) and t.nextId > top) then t.nextId = top + 1 end
    Changed()
    return true
end

local function NextId()
    local t = Store(true)
    local top = 0
    for _, r in ipairs(CC.Rules()) do if r.id > top then top = r.id end end
    local id = (t and Whole(t.nextId) and t.nextId > top) and t.nextId or top + 1
    if t then t.nextId = id + 1 end
    return id
end

-- def: { name, mode, text, case, enabled, all, channels }. Returns a clean rule, or nil and a sentence.
function CC.CheckRule(def)
    local base, why = M.CheckRule(def)
    if not base then return nil, why end
    local rule = CleanRule({ name = base.name, mode = base.mode, text = base.text, case = base.case,
        enabled = def.enabled ~= false, all = def.all ~= false, channels = def.channels })
    if not rule then return nil, "That rule can't be used." end
    if def.all == false then
        if next(rule.channels) == nil then return nil, "Choose at least one channel, or All channels being cleaned." end
    end
    return rule
end

-- Adds a rule at the end. Returns true, id | false, sentence, warning code ("everything" | "broad": valid, but it
-- needs force = true, after the player confirmed the warning).
function CC.AddRule(def, force)
    local rule, why = CC.CheckRule(def)
    if not rule then return false, why end
    local warning = M.Warning(rule)
    if warning and not force then return false, warning.text, warning.code end
    local list = CC.Rules()
    if #list >= CC.MAX_RULES then return false, ("You can have %d rules; remove one first."):format(CC.MAX_RULES) end
    rule.id = NextId()
    list[#list + 1] = rule
    if not WriteRules(list) then return false, "Your settings aren't available right now." end
    return true, rule.id
end

-- Replaces a rule's text, name, mode, case, channels and on/off. Same returns as AddRule.
function CC.UpdateRule(id, def, force)
    local rule, why = CC.CheckRule(def)
    if not rule then return false, why end
    local list = CC.Rules()
    for i, cur in ipairs(list) do
        if cur.id == id then
            local warning = M.Warning(rule)
            local same = cur.mode == rule.mode and cur.text == rule.text and cur.case == rule.case
            if warning and not force and not same then return false, warning.text, warning.code end
            rule.id = id
            list[i] = rule
            if not WriteRules(list) then return false, "Your settings aren't available right now." end
            return true, id
        end
    end
    return false, "That rule isn't there any more."
end

function CC.SetRuleEnabled(id, on)
    local list = CC.Rules()
    for _, rule in ipairs(list) do
        if rule.id == id then
            on = on and true or false
            if rule.enabled == on then return true end
            rule.enabled = on
            return WriteRules(list)
        end
    end
    return false
end

function CC.RemoveRule(id)
    local list = CC.Rules()
    for i, rule in ipairs(list) do
        if rule.id == id then
            table.remove(list, i)
            return WriteRules(list)
        end
    end
    return false
end

-- Moves a rule up (-1) or down (1) in the order rules are checked in.
function CC.MoveRule(id, dir)
    local list = CC.Rules()
    for i, rule in ipairs(list) do
        if rule.id == id then
            local j = i + dir
            if j < 1 or j > #list then return false end
            list[i], list[j] = list[j], list[i]
            return WriteRules(list)
        end
    end
    return false
end

-- One channel's choice: field "on" | "spam" | "repeats" | "recruit" | "politics" | "lgbt". The first change saves the
-- recommended choice with it, so what you saw is what you keep. label: the channel's name as the client shows it, kept
-- for the list.
function CC.SetChannel(key, field, value, label)
    if not (CC.ValidKey(key) and FLAGS[field]) then return false end
    value = value and true or false
    local channels = CC.Channels()
    local e = channels[key]
    if not e then
        local n = 0
        for _ in pairs(channels) do n = n + 1 end
        if n >= CC.MAX_CHANNELS then return false, "full" end
        e = CleanChannel({})
        channels[key] = e
    end
    label = CleanLabel(label)
    if e[field] == value and (not label or e.label == label) and CC.Customized() then return true end
    e[field] = value
    if label then e.label = label end
    -- a channel turned on for the first time starts with the recommended filters
    if field == "on" and value and not (e.spam or e.repeats or e.recruit or e.politics or e.lgbt) then
        e.spam, e.repeats, e.recruit = CC.RECOMMENDED.spam, CC.RECOMMENDED.repeats, CC.RECOMMENDED.recruit
        e.politics, e.lgbt = CC.RECOMMENDED.politics, CC.RECOMMENDED.lgbt
    end
    local t = Store(true)
    if not t then return false end
    t.channels = channels
    Changed()
    return true
end

-- Puts the recommended channel choice back (General and Trade, spam and repeats). Custom rules are kept.
function CC.ResetChannels()
    local t = Store(false)
    if t then t.channels = nil end
    Changed()
end

---------------------------------------------------------------------------
-- Which channels there are: the ones you are in now (the client's list) and the ones you chose before
---------------------------------------------------------------------------
-- { { key, label, joined, number (your number for it), kind "zone" | "custom", choice } } in your channel order, then
-- the ones you aren't in, by name. Read when a list is drawn; nothing is tracked in the background.
function CC.KnownChannels()
    local list, seen = {}, {}
    local channels = CC.Channels()
    local maxChannels = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels) or 20
    if C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier then
        for i = 1, maxChannels do
            local ok, info = pcall(C_ChatInfo.GetChannelInfoFromIdentifier, i)
            info = ok and Plain(info) or nil
            if type(info) == "table" then
                local zoneID, name = Plain(info.zoneChannelID), CleanLabel(info.shortcut) or CleanLabel(info.name)
                local key, kind
                if Whole(zoneID) and zoneID > 0 then
                    key, kind = CC.ZoneKey(zoneID), "zone"
                    name = ZoneName(zoneID) or name
                elseif name then
                    key, kind = CC.CustomKey(CleanLabel(info.name) or name), "custom"
                end
                if key and CC.ValidKey(key) and not seen[key] then
                    seen[key] = true
                    list[#list + 1] = { key = key, label = name or key, joined = true, number = Plain(info.localID) or i, kind = kind,
                        choice = channels[key] }
                end
            end
        end
    end
    local rest = {}
    for key, e in pairs(channels) do
        if not seen[key] then
            local kind = key:find("^zone:") and "zone" or "custom"
            local label = e.label
            if kind == "zone" then label = ZoneName(tonumber(key:match("%d+"))) or label end
            rest[#rest + 1] = { key = key, label = label or key:gsub("^%a+:", ""), joined = false, kind = kind, choice = e }
        end
    end
    table.sort(rest, function(a, b) return a.label:lower() < b.label:lower() end)
    for _, e in ipairs(rest) do list[#list + 1] = e end
    return list
end

-- A channel's name for showing: from the client, or as saved.
function CC.ChannelLabel(key)
    local id = type(key) == "string" and tonumber(key:match("^zone:(%d+)$"))
    local name = id and ZoneName(id)
    if name then return name end
    local e = CC.Channels()[key]
    return (e and e.label) or (type(key) == "string" and key:gsub("^%a+:", "")) or "?"
end

---------------------------------------------------------------------------
-- What a channel is checked against, built when the settings change (never per message)
---------------------------------------------------------------------------
local byZone, byCustom = {}, {}   -- [zoneChannelID] / [lowercased name] = { key, label, spam, recruit, repeats, politics, lgbt, rules }
local anyCustom = false
local compiled = 0                -- channels with something to check

local function Compile()
    byZone, byCustom, anyCustom, compiled = {}, {}, false, 0
    local rules = {}
    for _, rule in ipairs(CC.Rules()) do
        if rule.enabled then
            local ok, test = pcall(M.Compile, rule)
            if ok and test then rules[#rules + 1] = { rule = rule, test = test, label = CC.RuleName(rule) } end
        end
    end
    for key, e in pairs(CC.Channels()) do
        if e.on then
            local ch = { key = key, label = CC.ChannelLabel(key), spam = e.spam, recruit = e.recruit, repeats = e.repeats,
                politics = e.politics, lgbt = e.lgbt, rules = {} }
            for _, r in ipairs(rules) do
                if r.rule.all or r.rule.channels[key] then ch.rules[#ch.rules + 1] = r end
            end
            if ch.spam or ch.recruit or ch.repeats or ch.politics or ch.lgbt or #ch.rules > 0 then
                local id = tonumber(key:match("^zone:(%d+)$"))
                if id then byZone[id] = ch
                else
                    byCustom[key:sub(8)] = ch
                    anyCustom = true
                end
                compiled = compiled + 1
            end
        end
    end
end

---------------------------------------------------------------------------
-- Repeated messages: a short memory of who said what (as a number), bounded and forgotten soon after
---------------------------------------------------------------------------
local recent, ring, ringPos, ringCount = {}, {}, 1, 0
local sweepQueued = false

local function Forget()
    recent, ring, ringPos, ringCount = {}, {}, 1, 0
end
CC.ForgetRepeats = Forget

local function Sweep()
    sweepQueued = false
    local now, left = GetTime(), 0
    for key, t in pairs(recent) do
        if now - t > CC.REPEAT_WINDOW then recent[key] = nil else left = left + 1 end
    end
    if left == 0 then Forget()
    elseif C_Timer then
        sweepQueued = true
        C_Timer.After(CC.REPEAT_WINDOW, Sweep)
    end
end

-- Notes key as seen now; returns when it was seen before (nil: not within memory).
local function Seen(key, now)
    local before = recent[key]
    if before == nil then
        local old = ring[ringPos]
        if old ~= nil then recent[old] = nil else ringCount = ringCount + 1 end
        ring[ringPos] = key
        ringPos = ringPos % CC.REPEAT_MAX + 1
    end
    recent[key] = now
    if not sweepQueued and C_Timer then
        sweepQueued = true
        C_Timer.After(CC.REPEAT_WINDOW, Sweep)
    end
    return before
end

-- How many entries the repeat memory holds now (at most REPEAT_MAX).
function CC.RepeatMemory()
    local n = 0
    for _ in pairs(recent) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Whose messages are never hidden
---------------------------------------------------------------------------
local playerGUID

local function Known(sender, guid)
    if type(guid) == "string" and guid ~= "" then
        if guid == playerGUID then return true end
        if C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID and C_BattleNet.GetGameAccountInfoByGUID(guid) then return true end
        if C_PartyInfo and C_PartyInfo.IsGUIDInGroup and C_PartyInfo.IsGUIDInGroup(guid) then return true end
    end
    if type(sender) == "string" and sender ~= "" and IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.MemberExistsByName then
        if C_GuildInfo.MemberExistsByName(sender) then return true end
        local short = Ambiguate and Ambiguate(sender, "guild")
        if short and short ~= sender and C_GuildInfo.MemberExistsByName(short) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Deciding about one message
---------------------------------------------------------------------------
local stats = { checked = 0, hidden = 0, errors = 0, patternErrors = 0 }
local capture   -- fn(entry) while the live view is open (see CC.SetCapture)

-- What would happen to `text` in channel `ch` (compiled), ignoring who sent it. Returns nil, or the reason:
-- { kind = "rule" | "category", id = rule id | category key, label }. repeatKey: when given, the repeat memory is
-- consulted and updated (real messages only, never a test).
local function Judge(ch, text, repeatKey, now)
    local visible = M.Visible(text)
    local lowered = M.Lower(visible)
    for i = 1, #ch.rules do
        local r = ch.rules[i]
        local ok, hit = pcall(r.test, visible, lowered)
        if not ok then
            stats.patternErrors = stats.patternErrors + 1
        elseif hit then
            return { kind = "rule", id = r.rule.id, label = r.label }
        end
    end
    local squashed
    if ch.spam or ch.repeats then squashed = M.Squash(lowered) end
    if ch.spam and M.Spam(lowered, squashed, M.HasClubLink(text)) then return { kind = "category", id = "spam", label = CATEGORY.spam.label } end
    if ch.recruit and M.Recruit(lowered) then return { kind = "category", id = "recruit", label = CATEGORY.recruit.label } end
    if ch.politics or ch.lgbt then
        local topicText = M.TopicText(lowered)
        for _, key in ipairs(M.TOPIC_KEYS) do
            if ch[key] then
                local hit = M.Topic(key, topicText)
                if hit then return { kind = "category", id = key, rule = hit.rule, label = hit.label } end
            end
        end
    end
    if ch.repeats and repeatKey and squashed ~= "" then
        local before = Seen(repeatKey .. "\31" .. M.Hash(squashed), now)
        if before and now - before <= CC.REPEAT_WINDOW then
            return { kind = "category", id = "repeats", label = CATEGORY.repeats.label }
        end
    end
end

local function Channel(zoneID, baseName)
    if type(zoneID) == "number" and zoneID > 0 then return byZone[zoneID] end
    if anyCustom and type(baseName) == "string" then return byCustom[baseName:lower()] end
end

local function Decide(msg, sender, flags, zoneID, baseName, guid)
    if type(msg) ~= "string" or msg == "" then return false end
    local ch = Channel(zoneID, baseName)
    if not ch then return false end
    -- (the game already skips addon filters for secret values; never compared, measured or kept if one arrives)
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender) or issecretvalue(guid)) then return false end
    if flags == "GM" or flags == "DEV" then return false end
    if playerGUID and guid == playerGUID then return false end
    stats.checked = stats.checked + 1
    local who = (type(guid) == "string" and guid ~= "") and guid or (type(sender) == "string" and sender) or nil
    local reason = Judge(ch, msg, who, GetTime())
    if not reason then return false end
    if Known(sender, guid) then return false end
    stats.hidden = stats.hidden + 1
    if capture then
        local ok, err = pcall(capture, { when = time(), channel = ch.label, sender = sender, text = msg, reason = reason.label,
            kind = reason.kind })
        if not ok then
            capture = nil
            if R.Diag then R.Diag.Error("chat cleaning live view", err) end
        end
    end
    return true
end

-- The filter the game calls, once per chat frame, before a channel message is drawn. Only true or false is ever
-- returned: the message's own values are never replaced.
local lastLine, lastHidden = nil, false
local function Filter(_, _, msg, sender, _, _, _, flags, zoneID, _, baseName, _, lineID, guid)
    if lineID ~= nil and lineID == lastLine then return lastHidden end
    local ok, hidden = pcall(Decide, msg, sender, flags, zoneID, baseName, guid)
    if not ok then
        stats.errors = stats.errors + 1
        if R.Diag then R.Diag.Error("chat cleaning", hidden) end
        hidden = false
    end
    lastLine, lastHidden = lineID, hidden and true or false
    return lastHidden
end
CC.Filter = Filter   -- tests

---------------------------------------------------------------------------
-- Turning the filter on and off
---------------------------------------------------------------------------
local registered = false

local function FilterAPI()
    local U = ChatFrameUtil
    if U and U.AddMessageEventFilter and U.RemoveMessageEventFilter then return U.AddMessageEventFilter, U.RemoveMessageEventFilter end
    return ChatFrame_AddMessageEventFilter, ChatFrame_RemoveMessageEventFilter
end

-- Whether TwichUI's filter is in the game's list now.
function CC.Active() return registered end

local function Sync()
    local want = CC.Enabled() and compiled > 0
    local add, remove = FilterAPI()
    if want and not registered and add then
        add(CC.EVENT, Filter)
        registered = true
    elseif not want and registered and remove then
        remove(CC.EVENT, Filter)
        registered = false
    end
    if not registered then
        Forget()
        lastLine, lastHidden = nil, false
    end
end

-- After the switch, a profile change or an import: build again and follow.
function CC.Refresh()
    Compile()
    lastLine, lastHidden = nil, false
    Sync()
    Notify()
end

Changed = function()
    CC.Refresh()
end

---------------------------------------------------------------------------
-- The live view (TwichUI_Settings/pages/ChatCleanLive.lua) and the sample tester
---------------------------------------------------------------------------
-- fn(entry) is called for each message hidden from now on, until CC.SetCapture(nil). One at a time; the settings
-- window sets it only while the live view is on screen and not paused. entry: { when, channel, sender, text, reason,
-- kind }, raw values that the view makes plain before showing and never keeps beyond its own short list.
function CC.SetCapture(fn) capture = type(fn) == "function" and fn or nil end
function CC.Capturing() return capture ~= nil end

-- What would happen to a sample message in a channel, with the same checks as real messages (rules in order, then
-- the built-in filters), without sending anything or changing any memory. Repeats can't be judged from one sample,
-- and the sender is taken to be a stranger. Returns { hidden, reason (label), kind, cleaned (whether the channel is
-- cleaned at all), enabled (whether chat cleaning is on) }.
function CC.Test(text, key)
    local out = { hidden = false, enabled = CC.Enabled() }
    if type(text) ~= "string" or text == "" or not CC.ValidKey(key) then return out end
    local id = tonumber(key:match("^zone:(%d+)$"))
    local ch
    if id then ch = byZone[id] else ch = byCustom[key:sub(8)] end
    out.cleaned = ch ~= nil
    if not ch then return out end
    local reason = Judge(ch, text, nil, nil)
    if reason then out.hidden, out.reason, out.kind, out.id, out.rule = true, reason.label, reason.kind, reason.id, reason.rule end
    return out
end

-- Counts for /tui diagnostics: never names, channels or messages.
function CC.Stats()
    local rules, on = 0, 0
    for _, rule in ipairs(CC.Rules()) do
        rules = rules + 1
        if rule.enabled then on = on + 1 end
    end
    return { enabled = CC.Enabled(), active = registered, channels = compiled, rules = rules, rulesOn = on,
        checked = stats.checked, hidden = stats.hidden, errors = stats.errors, patternErrors = stats.patternErrors,
        repeatMemory = CC.RepeatMemory(), capturing = capture ~= nil, customized = CC.Customized() }
end

R:OnInit(function()
    Compile()
    Sync()
end)
R:On("PLAYER_LOGIN", function()
    playerGUID = Plain(UnitGUID and UnitGUID("player"))
end)
R.Profiles.OnApply("views", "chat-clean", function() Forget(); CC.Refresh() end)
