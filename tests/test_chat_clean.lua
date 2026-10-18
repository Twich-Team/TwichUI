dofile(TESTS .. "harness.lua")
dofile(TESTS .. "settings_mock.lua")
-- Chat cleaning (modules/ChatCleanMatch.lua, modules/ChatClean.lua, TwichUI_Settings/pages/ChatClean*.lua):
--   * matching: visible text (colors, links, textures, ||), contains with punctuation and pattern characters,
--     wildcards, Lua patterns that are refused or bounded, empty, everything-matching and oversized rules, non-ASCII;
--   * the built-in filters on spam, ordinary trade adverts, links, capitals and other languages;
--   * the filter through a stand-in of the game's own filter list (ChatFrameFilters.lua's rules: true discards, false
--     passes, a second value replaces the arguments, an error lets the message through), with several chat frames
--     and another addon's filter: selected and unselected channels, channel numbers, localized names, zones, custom
--     channels, exemptions, repeats, errors, turning it off, profiles;
--   * the live view: capturing only while shown, pause, clear, closing, plain text; nothing saved or reported;
--   * the settings pages: turning it on asks first; rules added, edited, warned about and removed; the tester;
--   * sharing: what travels, what is refused, the review, merging, and Undo.
-- Nothing here is the game: real chat frames, EllesmereUI's windows and channel IDs on Forever are in-game checks.

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- Stand-in frames (scripts, text, shown state, children)
---------------------------------------------------------------------------
local function Fake(kind, parent)
  local f = { kind = kind, parent = parent, scripts = {}, hooks = {}, points = {}, shown = true, w = 0, h = 0,
    text = "", enabled = true, focus = false, scroll = 0, events = {}, children = {} }
  if parent and parent.children then table.insert(parent.children, f) end
  local function Fire(self, name, ...)
    if self.scripts[name] then self.scripts[name](self, ...) end
    for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
  end
  f.Fire = Fire
  local methods = {
    SetScript = function(s, n, fn) s.scripts[n] = fn; s.hooks[n] = nil end,
    GetScript = function(s, n) return s.scripts[n] end,
    HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
    SetSize = function(s, w, h) s.w, s.h = w, h end,
    SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
    GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
    SetPoint = function(s, ...) table.insert(s.points, { ... }) end,
    ClearAllPoints = function(s) s.points = {} end,
    Show = function(s) if not s.shown then s.shown = true; Fire(s, "OnShow") end end,
    Hide = function(s) if s.shown then s.shown = false; Fire(s, "OnHide") end end,
    SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
    IsShown = function(s) return s.shown end,
    IsVisible = function(s) local p = s while p do if not p.shown then return false end p = p.parent end return true end,
    SetText = function(s, t) s.text = t == nil and "" or tostring(t) end,
    GetText = function(s) return s.text end,
    GetStringHeight = function() return 12 end, GetStringWidth = function(s) return #s.text * 6 end,
    IsTruncated = function() return false end,
    SetEnabled = function(s, v) s.enabled = v and true or false; Fire(s, v and "OnEnable" or "OnDisable") end,
    IsEnabled = function(s) return s.enabled end,
    SetFocus = function(s) s.focus = true; Fire(s, "OnEditFocusGained") end,
    ClearFocus = function(s) if s.focus then s.focus = false; Fire(s, "OnEditFocusLost") end end,
    HasFocus = function(s) return s.focus end,
    SetScrollChild = function(s, child) s.child = child end,
    SetVerticalScroll = function(s, v) s.scroll = v end,
    GetVerticalScroll = function(s) return s.scroll end,
    GetVerticalScrollRange = function(s) return math.max(0, (s.child and s.child.h or 0) - s.h) end,
    IsMouseOver = function() return false end,
    GetEffectiveScale = function() return 1 end, GetScale = function() return 1 end,
    GetOwner = function(s) return s.owner end, SetOwner = function(s, o) s.owner = o end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end, SetFont = function() return true end,
    SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha or 1 end,
    RegisterEvent = function(s, e) s.events[e] = true end, UnregisterEvent = function(s, e) s.events[e] = nil end,
    CreateTexture = function(s) return Fake("Texture", s) end,
    CreateFontString = function(s) return Fake("FontString", s) end,
  }
  if kind == "ScrollFrame" then f.ScrollBar = Fake("Slider", f); f.ScrollBar.ThumbTexture = Fake("Texture", f.ScrollBar) end
  return setmetatable(f, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end

---------------------------------------------------------------------------
-- The game, as far as chat cleaning sees it
---------------------------------------------------------------------------
local NOW = 1000
local registry = {}          -- [event] = { fn, ... }: the game's message filter list
local JOINED = {}            -- [localID] = ChatChannelInfo
local SECRET = {}            -- values the client would mark secret
local FRIENDS, GROUPGUIDS, GUILDNAMES, BNET = {}, {}, {}, {}

local function World(c)
  c.CreateFrame = function(kind, name, parent) local f = Fake(kind, parent); if name then c[name] = f end return f end
  c.UIParent = Fake("Frame")
  c.GameTooltip = Fake("GameTooltip")
  c.GetTime = function() return NOW end
  c.ACCEPT, c.CANCEL = "Accept", "Cancel"
  c.issecretvalue = function(v) return v ~= nil and SECRET[v] == true end
  c.ChatFrameUtil = {
    AddMessageEventFilter = function(event, fn)
      registry[event] = registry[event] or {}
      for _, f in ipairs(registry[event]) do if f == fn then return end end
      table.insert(registry[event], fn)
    end,
    RemoveMessageEventFilter = function(event, fn)
      local list = registry[event] or {}
      for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
    end,
  }
  c.C_ChatInfo.GetGeneralChannelID = function() return 1 end
  c.C_ChatInfo.GetChannelShortcutForChannelID = function(id)
    return ({ [1] = c.LOCALE_GENERAL or "General", [2] = c.LOCALE_TRADE or "Trade", [22] = "LocalDefense", [26] = "LookingForGroup" })[id] or ""
  end
  c.C_ChatInfo.GetChannelInfoFromIdentifier = function(i) return JOINED[i] end
  c.C_FriendList = { IsFriend = function(guid) return FRIENDS[guid] == true end }
  c.C_PartyInfo = { IsGUIDInGroup = function(guid) return GROUPGUIDS[guid] == true end }
  c.C_BattleNet = { GetGameAccountInfoByGUID = function(guid) if BNET[guid] then return {} end end }
  c.C_GuildInfo = { MemberExistsByName = function(name) return GUILDNAMES[name] == true end }
  c.IsInGuild = function() return next(GUILDNAMES) ~= nil end
end

local c, S = SettingsClient({ name = "Rich", beforeInit = World })
local R = c.TwichUI
local CC, M = R.ChatClean, R.ChatCleanMatch
local K = S.K
local function Flush() for _ = 1, 4 do FlushTimers() end end

-- The game's ProcessMessageEventFilters for one chat frame: true discards; a second value replaces the arguments;
-- an error (securecallfunction) is a filter that returned nothing.
local function Process(frame, event, ...)
  local args, n = { ... }, select("#", ...)
  for _, fn in ipairs(registry[event] or {}) do
    local results = { pcall(fn, frame, event, unpack(args, 1, n)) }
    if results[1] then
      if results[2] then return true end
      if results[3] then args = { unpack(results, 3, n + 2) } end
    end
  end
  return false, unpack(args, 1, n)
end

local lineNo = 0
-- One incoming channel message, delivered to `frames` chat frames as the game does. Returns whether each frame
-- discarded it, and the text the last frame would draw.
local function Deliver(m, frames)
  lineNo = lineNo + 1
  local args = { m.text, m.sender or "Stranger-Forever", "Common", (m.index or 2) .. ". " .. (m.base or "Trade - City"), "",
    m.flags or "", m.zone or 2, m.index or 2, m.base or "Trade - City", 7, m.line or lineNo, m.guid or "Player-1-0000ABCD" }
  local out, last = {}, nil
  for i = 1, frames or 1 do
    local r = { Process({ id = i }, "CHAT_MSG_CHANNEL", unpack(args, 1, 12)) }
    out[i] = r[1]
    if not r[1] then last = r[2] end
  end
  return out[1], out, last
end
local function Hidden(m, frames) return (Deliver(m, frames)) end

---------------------------------------------------------------------------
-- 1. Matching
---------------------------------------------------------------------------
do
  Check(M.Visible("plain text") == "plain text", "plain text is unchanged")
  local linked = "|cff9d9d9d|Hitem:2840::::::::60:::::|h[Copper Bar]|h|r for sale || cheap"
  Check(M.Visible(linked) == "[Copper Bar] for sale | cheap", "colors and link data removed, the link's text and a typed | kept: " .. M.Visible(linked))
  Check(not M.Visible(linked):find("item:2840", 1, true), "hidden link data is not part of the visible text")
  Check(M.Visible("|TInterface\\Icons\\x:14|t hi |A:atlas:12:12|a there|n now") == " hi  there  now", "textures, atlases and |n")
  Check(M.Visible("|cnIQ4:Epic|r") == "Epic", "named colors")
  Check(M.Plain(linked) == "[Copper Bar] for sale || cheap", "plain text for display doubles every |")
  Check(#M.Visible(("x"):rep(5000)) == M.SCAN_MAX, "an oversized message is read only up to the bound")

  local function Rule(def) local r = assert(M.CheckRule(def)); return M.Compile(r), r end
  local function Hit(test, text) local v = M.Visible(text); return test(v, M.Lower(v)) end

  -- contains: punctuation and pattern characters are literal
  local t = Rule({ mode = "contains", text = "50%" })
  Check(Hit(t, "only 50% off") and not Hit(t, "only 500 off"), "contains: % is literal")
  t = Rule({ mode = "contains", text = "a.b" })
  Check(Hit(t, "see a.b now") and not Hit(t, "see axb now"), "contains: . is literal")
  t = Rule({ mode = "contains", text = "[gold]" })
  Check(Hit(t, "buy [gold] now") and not Hit(t, "buy g now"), "contains: [ ] are literal")
  t = Rule({ mode = "contains", text = "  WTS boost  " })
  Check(Hit(t, "wts BOOST cheap"), "contains: trimmed, case ignored by default")
  t = Rule({ mode = "contains", text = "WTS", case = true })
  Check(Hit(t, "WTS x") and not Hit(t, "wts x"), "contains: match case")
  t = Rule({ mode = "contains", text = "copper bar" })
  Check(Hit(t, linked), "contains matches a link's shown text")
  t = Rule({ mode = "contains", text = "item:2840" })
  Check(not Hit(t, linked), "contains never matches a link's hidden data")

  -- wildcard
  t = Rule({ mode = "wildcard", text = "wts*boost" })
  Check(Hit(t, "WTS mythic boost") and Hit(t, "xx wtsboost") and not Hit(t, "boost wts"), "wildcard: * is any run, in order, anywhere")
  t = Rule({ mode = "wildcard", text = "l?g" })
  Check(Hit(t, "lfg log") and Hit(t, "lag") and not Hit(t, "lg"), "wildcard: ? is exactly one character")
  t = Rule({ mode = "wildcard", text = "caf?" })
  Check(Hit(t, "café open"), "wildcard: ? is one whole UTF-8 character")
  t = Rule({ mode = "wildcard", text = "50%*off." })
  Check(Hit(t, "now 50% big off.") and not Hit(t, "now 50x big offx"), "wildcard: other pattern characters are escaped")
  t = Rule({ mode = "wildcard", text = "(a)+[b]^$" })
  Check(Hit(t, "x(a)+[b]^$y") and not Hit(t, "aab"), "wildcard: ( ) + [ ] ^ $ are literal")
  local pieces = M.Pieces("wts*b?ost**x")
  Check(#pieces == 3 and pieces[1].plain == "wts" and pieces[2].pattern and pieces[3].plain == "x", "wildcard pieces")
  -- bounded cost: a long message of near-matches with many *
  t = Rule({ mode = "wildcard", text = "a*a*a*a*a*a*b" })
  local start = os.clock()
  Check(not Hit(t, ("a"):rep(255)), "no match")
  Check(os.clock() - start < 0.05, "wildcards never backtrack")

  -- Lua patterns: accepted, refused, bounded
  t = Rule({ mode = "pattern", text = "%d+%s*g%f[%A]" })
  Check(Hit(t, "selling for 500 g each") and not Hit(t, "500 gold"), "a Lua pattern")
  t = Rule({ mode = "pattern", text = "WTS" })
  Check(Hit(t, "WTS x") and not Hit(t, "wts x"), "patterns match case as written")
  for text, why in pairs({ ["[abc"] = "set", ["abc%"] = "end", ["(ab"] = "capture", ["ab)"] = "capture",
      ["(a)%1"] = "back", ["a.-b.-c.-d"] = "repeat", ["%bxy.-.-"] = "repeat", [("x"):rep(81)] = "long", ["%f"] = "frontier" }) do
    local ok = M.CheckRule({ mode = "pattern", text = text })
    Check(ok == nil, "refused pattern (" .. why .. "): " .. text)
  end
  local ok, msg = M.CheckRule({ mode = "pattern", text = "a.-b.-c.-d" })
  Check(not ok and msg:find("at most 2"), "says why: " .. tostring(msg))
  start = os.clock()
  t = Rule({ mode = "pattern", text = "a.-a.-b" })
  Check(not Hit(t, ("a"):rep(255)), "worst case allowed pattern")
  Check(os.clock() - start < 0.5, "two repeats stay quick on a full-length message")

  -- empty, oversized, control characters, invalid UTF-8
  Check(M.CheckRule({ mode = "contains", text = "   " }) == nil, "empty text refused")
  Check(M.CheckRule({ mode = "contains", text = ("x"):rep(101) }) == nil, "over 100 characters refused")
  Check(M.CheckRule({ mode = "contains", text = ("é"):rep(100) }) ~= nil, "100 accented characters are 100 characters")
  Check(M.CheckRule({ mode = "contains", text = "a\nb" }) == nil, "line breaks refused")
  Check(M.CheckRule({ mode = "contains", text = "\255\254" }) == nil, "broken UTF-8 refused")
  Check(M.CheckRule({ mode = "nope", text = "x" }) == nil, "unknown mode refused")
  Check(M.CheckRule({ mode = "contains", text = "x", name = "a|cffff0000b" }) == nil, "a name with | refused")

  -- everything-matching and broad rules are warned about
  local function Warn(def) return M.Warning(assert(M.CheckRule(def))) end
  Check((Warn({ mode = "wildcard", text = "*" }) or {}).code == "everything", "* matches everything")
  Check((Warn({ mode = "wildcard", text = "?*" }) or {}).code == "everything", "?* matches everything")
  Check((Warn({ mode = "pattern", text = ".*" }) or {}).code == "everything", ".* matches everything")
  Check((Warn({ mode = "pattern", text = "^" }) or {}).code == "everything", "^ matches everything")
  Check((Warn({ mode = "contains", text = "e" }) or {}).code == "broad", "one letter is broad")
  Check(Warn({ mode = "contains", text = "cheap gold" }) == nil, "an ordinary rule has no warning")
  Check(Warn({ mode = "pattern", text = "^WTS" }) == nil, "an anchored pattern has no warning")

  -- non-ASCII: only A-Z have a case
  t = Rule({ mode = "contains", text = "ÄRGER" })
  Check(Hit(t, "ÄRGER hier") and not Hit(t, "ärger hier"), "letters outside A-Z are compared as typed")
  t = Rule({ mode = "contains", text = "привет" })
  Check(Hit(t, "всем привет!"), "other scripts match as typed")
end

---------------------------------------------------------------------------
-- 2. The built-in filters
---------------------------------------------------------------------------
do
  local function Spam(text) local v = M.Lower(M.Visible(text)); return M.Spam(v, M.Squash(v)) end
  Check(Spam("Cheapest gold! www.g4mer.com 10% off code WOW"), "classic gold seller")
  Check(Spam("Selling boosts, cheap prices, discord.gg/xyz"), "boost seller with a link and prices")
  Check(Spam("G O L D  fast deliver  w w w . goldz . c o m  $5"), "spaced out")
  Check(Spam("buy gold, best price, visit goldshop dot com"), "dot com spelled out")
  Check(not Spam("WTS [Arcanite Bar] 50g, cheap!"), "ordinary trade advert")
  Check(not Spam("check wowhead.com for the gold farm guide"), "a site and gold, but no price")
  Check(not Spam("WTS BOOST IN DEADMINES PST"), "capitals and a service, no site")
  Check(not Spam("|cff1eff00|Hitem:1:|h[Gold Ring]|h|r 5g cheap"), "a link, no site")
  Check(not Spam("Verkaufe Gold, sehr günstig"), "another language alone")
  local function Club(text) local v = M.Lower(M.Visible(text)); return M.Spam(v, M.Squash(v), M.HasClubLink(text)) end
  local FINDER = "|cff00ccff|HclubFinder:Club-1-2|h[Community: SAFE GOLD AT ForeverGold.net]|h|r"
  Check(M.HasClubLink(FINDER) and M.HasClubLink("|cffffd200|HclubTicket:123|h[Invite: x]|h|r"), "club links are recognised")
  Check(not M.HasClubLink("||HclubFinder:x||h typed") and not M.HasClubLink("|Hitem:1:|h[Gold]|h") and not M.HasClubLink(nil), "other text is not a club link")
  Check(Club(FINDER), "a gold shop community link, no price")
  Check(Club("Safe gold |cff00ccff|HclubFinder:Club-1-2|h[Community: cheap gold shop]|h|r"), "gold and a price in the link name")
  Check(not Spam(FINDER), "the same text without the link type is not enough (the three-sign rule stays)")
  Check(not Club("|cff00ccff|HclubFinder:Club-1-2|h[Guild: Ashen Raiders]|h|r"), "an ordinary guild finder link")
  Check(not Club("|cff00ccff|HclubFinder:Club-1-2|h[Community: Golden Eagles]|h|r"), "a name with gold in it but nothing else")
  Check(not Club("|cff00ccff|HclubFinder:Club-1-2|h[Community: wowhead.com fans]|h|r"), "a web address in the name, nothing sold")
  local function Recruit(text) return M.Recruit(M.Lower(text)) end
  Check(Recruit("<Ashen> is recruiting all classes!"), "recruiting")
  Check(Recruit("Friendly guild looking for members, /w for invite"), "guild invite")
  Check(not Recruit("LF healer for Deadmines"), "an LFG message")
  Check(not Recruit("WTS [Linen Cloth] x20"), "a trade message")
end

---------------------------------------------------------------------------
-- 3. The filter
---------------------------------------------------------------------------
Check(not CC.Enabled() and not CC.Active() and registry.CHAT_MSG_CHANNEL == nil, "off by default: no filter registered")
Check(not CC.Customized(), "the recommended choice is not saved until something changes")
local channels = CC.Channels()
Check(channels["zone:1"] and channels["zone:1"].on and channels["zone:1"].spam and channels["zone:1"].repeats and not channels["zone:1"].recruit,
  "General is recommended with spam and repeats")
Check(channels["zone:2"] and channels["zone:2"].on and channels["zone:2"].label == "Trade", "Trade is recommended, named by the client")
local SPAM = "Cheapest gold! www.g4mer.com 10% off"
Check(Hidden({ text = SPAM }) == false, "nothing is hidden while off")

-- another addon's filter (like EllesmereUI's URL wrapper) registered first, transforming the text
local function UrlFilter(_, _, msg, ...)
  if msg:find("www%.") then return false, (msg:gsub("(www%.%S+)", "|cff00ccff|Hurl:%1|h[%1]|h|r")), ... end
  return false
end
c.ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", UrlFilter)

R:SetEnabled("chatClean", true)
Check(CC.Active() and #registry.CHAT_MSG_CHANNEL == 2, "on: registered once, beside the other addon's filter")
CC.Refresh(); CC.Refresh()
Check(#registry.CHAT_MSG_CHANNEL == 2, "refreshing registers nothing again")
Check(#(registry.CHAT_MSG_WHISPER or {}) == 0 and #(registry.CHAT_MSG_GUILD or {}) == 0 and #(registry.CHAT_MSG_SAY or {}) == 0,
  "whispers, guild and say are never filtered")

-- one message, three chat frames: decided once, hidden in all
local before = CC.Stats()
local first, all = Deliver({ text = SPAM }, 3)
Check(first and all[2] and all[3], "hidden in every chat frame (and the other addon's link markup doesn't hide it from the check)")
local after = CC.Stats()
Check(after.checked - before.checked == 1 and after.hidden - before.hidden == 1, "evaluated and counted once, not once per frame")
-- the return contract: only true or false, never replacement values
local n = select("#", CC.Filter({}, "CHAT_MSG_CHANNEL", "hello", "X", "", "", "", "", 2, 2, "Trade - City", 7, 99999, "G"))
Check(n == 1, "the filter returns exactly one value")
local _, _, shown = Deliver({ text = "WTS [Copper Bar] 5s" }, 2)
Check(shown == "WTS [Copper Bar] 5s", "an allowed message reaches the frame unchanged")
local _, _, drawn = Deliver({ text = "see www.wowhead.com" }, 1)
Check(drawn:find("|Hurl:", 1, true), "an allowed message keeps the other addon's change")

-- selected and unselected channels; numbers, localized names and zones don't matter
Check(Hidden({ text = SPAM, zone = 26, base = "LookingForGroup", index = 4 }) == false, "a channel not chosen is left alone")
Check(Hidden({ text = SPAM, zone = 2, index = 5, base = "Trade - City" }) == true, "Trade at another number")
Check(Hidden({ text = SPAM, zone = 2, index = 2, base = "Handel - Stadt" }) == true, "Trade with a German name")
Check(Hidden({ text = SPAM, zone = 1, index = 1, base = "General - Elwynn Forest" }) == true, "General in one zone")
Check(Hidden({ text = SPAM, zone = 1, index = 1, base = "General - Westfall" }) == true, "General in another zone")
Check(Hidden({ text = SPAM, zone = 0, base = "Trade", index = 7 }) == false, "a custom channel named Trade is not the Trade channel")

-- exemptions
FRIENDS["Player-1-FRIEND"] = true
Check(Hidden({ text = SPAM, guid = "Player-1-FRIEND" }) == false, "a friend's message is never hidden")
GROUPGUIDS["Player-1-GROUP"] = true
Check(Hidden({ text = SPAM, guid = "Player-1-GROUP" }) == false, "a group member's message is never hidden")
BNET["Player-1-BNET"] = true
Check(Hidden({ text = SPAM, guid = "Player-1-BNET" }) == false, "a Battle.net friend's message is never hidden")
GUILDNAMES["Guildie"] = true
Check(Hidden({ text = SPAM, sender = "Guildie", guid = "Player-1-GUILD" }) == false, "a guild member's message is never hidden")
Check(Hidden({ text = SPAM, guid = c.UnitGUID("player") }) == false, "your own message is never hidden")
Check(Hidden({ text = SPAM, flags = "GM" }) == false, "a GM's message is never hidden")
-- secret values (the game skips addon filters for them; checked again here)
SECRET["secret spam goldz dot com 10% off gold"] = true
Check(Hidden({ text = "secret spam goldz dot com 10% off gold" }) == false, "a secret message is never touched")

-- custom channels, by name
CC.SetChannel("custom:mychan", "on", true, "MyChan")
Check(CC.Customized(), "the first change saves the choice")
Check(CC.Channels()["zone:2"].on, "and keeps the recommended channels it showed")
Check(Hidden({ text = SPAM, zone = 0, base = "MYCHAN", index = 6 }) == true, "a custom channel is matched by name, ignoring case")
Check(CC.Channels()["custom:mychan"].spam, "a channel turned on starts with the recommended filters")
Check(not CC.ValidKey("custom:Upper") and not CC.ValidKey("zone:abc") and not CC.ValidKey("custom:a|b") and CC.ValidKey("zone:42"), "channel keys are checked")

-- repeats: once per message, bounded, forgotten
NOW = 2000
local REP = { text = "LF tank for DM, need 1 more!", guid = "Player-1-REP" }
Check(Hidden(REP, 3) == false, "a first message is shown (in every frame)")
NOW = NOW + 10
Check(Hidden(REP, 3) == true, "the same again 10 s later is hidden")
Check(Hidden({ text = "lf  TANK for dm need 1 more", guid = "Player-1-REP" }) == true, "case, spaces and punctuation don't make it new")
Check(Hidden({ text = REP.text, guid = "Player-1-OTHER" }) == false, "another player's copy is their first")
NOW = NOW + CC.REPEAT_WINDOW + 1
Check(Hidden(REP) == false, "after the window it is shown again")
for i = 1, CC.REPEAT_MAX + 50 do Hidden({ text = "unique message number " .. i, guid = "Player-1-R" .. i }) end
Check(CC.RepeatMemory() <= CC.REPEAT_MAX, "the memory never holds more than its limit: " .. CC.RepeatMemory())
NOW = NOW + CC.REPEAT_WINDOW * 3
RunLongTimers(CC.REPEAT_WINDOW)
RunLongTimers(CC.REPEAT_WINDOW)
Check(CC.RepeatMemory() == 0, "and forgets everything once the window has passed")

-- custom rules: order, first reason, channels
Check(CC.AddRule({ mode = "contains", text = "lfg dm" }), "a rule")
local ok, id2 = CC.AddRule({ mode = "wildcard", text = "wts*boost", name = "Boost sellers", all = false, channels = { ["zone:1"] = true } })
Check(ok, "a rule for General only")
local capture = {}
CC.SetCapture(function(e) capture[#capture + 1] = e end)
Check(Hidden({ text = "WTS dungeon boost cheap", zone = 2 }) == false, "a General-only rule doesn't apply in Trade")
Check(Hidden({ text = "WTS dungeon boost cheap", zone = 1, base = "General - Elwynn" }, 3) == true, "it applies in General")
Check(#capture == 1 and capture[1].reason == "Boost sellers" and capture[1].kind == "rule", "seen once, with the rule's name")
local ok3, id3 = CC.AddRule({ mode = "contains", text = "boost" })
CC.MoveRule(id3, -1); CC.MoveRule(id3, -1)
Check(CC.Rules()[1].id == id3, "moved to the top")
capture = {}
Hidden({ text = "WTS dungeon boost cheap", zone = 1, base = "General - Elwynn" })
Check(#capture == 1 and capture[1].reason == 'Contains "boost"', "several rules match: the first in order is the reason, once")
CC.SetRuleEnabled(id3, false)
capture = {}
Hidden({ text = "WTS dungeon boost cheap", zone = 1, base = "General - Elwynn" })
Check(capture[1] and capture[1].reason == "Boost sellers", "a rule turned off is skipped")
CC.SetCapture(nil)
-- a capture that errors is dropped without hiding chat or printing
CC.SetCapture(function() error("view broke") end)
Check(Hidden({ text = SPAM }) == true and not CC.Capturing(), "a broken live view is let go; filtering goes on")

-- an unexpected error lets the message through, is noted, and nothing is printed
local realVisible = M.Visible
M.Visible = function() error("boom") end
local errorsBefore = CC.Stats().errors
local printed = false
local realPrint = c.print
c.print = function() printed = true end
Check(Hidden({ text = SPAM }) == false, "an error lets the message through")
Check(CC.Stats().errors == errorsBefore + 1 and not printed, "counted, nothing printed to chat")
M.Visible = realVisible
c.print = realPrint
Check(Hidden({ text = SPAM }) == true, "and the next message is judged normally")

-- the tester: the same checks, no memory, nothing sent
local repBefore = CC.RepeatMemory()
local result = CC.Test(SPAM, "zone:2")
Check(result.hidden and result.reason == "Gold selling spam" and result.cleaned and result.enabled, "tester: hidden, with the reason")
Check(CC.Test("hello", "zone:2").hidden == false, "tester: shown")
Check(CC.Test(SPAM, "zone:26").cleaned == false, "tester: a channel not cleaned")
Check(CC.RepeatMemory() == repBefore, "the tester leaves the repeat memory alone")

-- turning it off removes only TwichUI's filter
R:SetEnabled("chatClean", false)
Check(not CC.Active() and #registry.CHAT_MSG_CHANNEL == 1 and registry.CHAT_MSG_CHANNEL[1] == UrlFilter, "off: only TwichUI's filter is removed")
Check(CC.RepeatMemory() == 0, "the repeat memory is forgotten")
Check(Hidden({ text = SPAM }) == false, "nothing hidden")
Check(CC.Test(SPAM, "zone:2").hidden and not CC.Test(SPAM, "zone:2").enabled, "the tester still says what would happen")
R:SetEnabled("chatClean", true)

-- EllesmereUI present or not changes nothing: the decision is the game's filter list's, not a frame's
c.EllesmereUI = { RegisterSkin = function() end }
Check(Hidden({ text = SPAM }) == true, "with EllesmereUI loaded")
c.EllesmereUI = nil
Check(Hidden({ text = SPAM }) == true, "without it")

---------------------------------------------------------------------------
-- 4. Profiles
---------------------------------------------------------------------------
do
  local PF = R.Profiles
  local rulesHere = #CC.Rules()
  Check(PF.Create("Quiet"), "a new profile, in use")
  Check(#CC.Rules() == 0 and not CC.Customized() and not CC.Enabled() and not CC.Active(), "a new profile: off, recommended channels, no rules, no filter")
  Check(Hidden({ text = SPAM }) == false, "nothing hidden in it")
  PF.Switch("Default")
  Check(#CC.Rules() == rulesHere and CC.Enabled() and CC.Active(), "back: its own rules, on again")
  Check(Hidden({ text = SPAM }) == true, "and filtering follows")
end

---------------------------------------------------------------------------
-- 5. The live view
---------------------------------------------------------------------------
do
  local P = R.ChatCleanLivePage
  local f = P.Frame()
  Check(P.Frame() == f, "one frame")
  Check(not CC.Capturing(), "nothing captured before the view is shown")
  f:Hide(); f:Show()
  Check(CC.Capturing(), "capturing while shown")
  Hidden({ text = "|cff9d9d9d|Hitem:2840:|h[Copper Bar]|h|r cheap gold www.g4mer.com 10% off", sender = "Spammer-Forever" }, 3)
  Flush()
  Check(P.Entries() == 1, "one entry per message, whatever the number of chat frames")
  local row
  for _, ch in ipairs(f.content.children) do if ch.entry then row = ch end end
  Check(row and row.text.text == "[Copper Bar] cheap gold [www.g4mer.com] 10% off", "plain text: links (the other addon's too) show their text only: " .. tostring(row and row.text.text))
  Check(row and not row.text.text:find("|H", 1, true) and not row.text.text:find("|c", 1, true), "no link or color codes reach the list")
  Check(row and row.head.text:find("Trade", 1, true) and row.head.text:find("Spammer", 1, true) and row.head.text:find("Gold selling spam", 1, true),
    "time, channel, sender and reason: " .. tostring(row and row.head.text))
  local made = #f.content.children
  -- pause: filtering continues, nothing listed
  P.SetPaused(true)
  Check(not CC.Capturing() and P.Paused(), "paused: not capturing")
  local hiddenBefore = CC.Stats().hidden
  Check(Hidden({ text = SPAM }) == true and CC.Stats().hidden == hiddenBefore + 1, "paused: still filtering")
  Flush()
  Check(P.Entries() == 1, "paused: nothing listed")
  P.SetPaused(false)
  Check(CC.Capturing(), "resumed")
  Hidden({ text = SPAM .. " again" }); Flush()
  Check(P.Entries() == 2, "listing again")
  P.Clear()
  Check(P.Entries() == 0, "cleared")
  -- bounded
  for i = 1, 130 do Hidden({ text = SPAM .. " " .. i, guid = "Player-1-B" .. i }) end
  Flush()
  Check(P.Entries() == 100, "at most 100 entries: " .. P.Entries())
  local rowsMade = 0
  for _, ch in ipairs(f.content.children) do if ch.head then rowsMade = rowsMade + 1 end end
  Check(rowsMade <= 100, "at most 100 rows: " .. rowsMade)
  -- leaving the view (another tab, page, search or closing the window all hide it)
  f:Hide()
  Check(not CC.Capturing() and P.Entries() == 0, "hidden: not capturing, nothing kept")
  for _, ch in ipairs(f.content.children) do
    if ch.head then Check(ch.head.text == "" and ch.text.text == "", "rows are emptied") break end
  end
  Hidden({ text = SPAM .. " while closed" })
  f:Show()
  Check(P.Entries() == 0, "nothing hidden while it was closed is shown later")
  -- nothing about messages is saved or reported
  Hidden({ text = "UNIQUE-MARKER cheap gold www.g4mer.com 10% off", sender = "MarkerSender-Forever" }); Flush()
  Check(P.Entries() == 1, "captured")
  local function Holds(t, needle, seen)
    seen = seen or {}
    if type(t) == "string" then return t:find(needle, 1, true) ~= nil end
    if type(t) ~= "table" or seen[t] then return false end
    seen[t] = true
    for k, v in pairs(t) do if Holds(k, needle, seen) or Holds(v, needle, seen) then return true end end
    return false
  end
  Check(not Holds(c.TwichUIDB, "UNIQUE-MARKER") and not Holds(c.TwichUIDB, "MarkerSender"), "no captured chat or sender in saved variables")
  Check(not Holds(c.TwichUIDB, "g4mer"), "no message text from filtering in saved variables")
  local chunk = assert(loadfile(ROOT .. "diag/ChatClean.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  local report = R.Diag.Build()
  Check(report:find("Chat cleaning", 1, true), "the report has a chat cleaning section")
  Check(not report:find("UNIQUE-MARKER", 1, true) and not report:find("MarkerSender", 1, true) and not report:find("g4mer", 1, true),
    "the report holds no messages or senders")
  local entry = R.TwichConfig.Build({ all = true })
  Check(not Holds(entry, "UNIQUE-MARKER") and not Holds(entry, "MarkerSender"), "a share holds no captured chat")
  f:Hide()
  Check(made > 0, "rows were made")
end

---------------------------------------------------------------------------
-- 6. The settings pages
---------------------------------------------------------------------------
do
  local page
  for _, p in ipairs(S.pages) do if p.key == "chatClean" then page = p end end
  Check(page and page.group == "everyday" and page.kind == "page", "Chat cleaning is a page of its own under Everyday")
  local kids = {}
  for _, p in ipairs(S.pages) do if p.parent == "Chat cleaning" then kids[#kids + 1] = p.key end end
  Check(table.concat(kids, ",") == "chatCleanChannels,chatCleanRules,chatCleanLive", "its tabs: " .. table.concat(kids, ","))
  -- turning it on asks first, and says what will be hidden
  R:SetEnabled("chatClean", false)
  local toggle = S.variables.TWICHUI_chatClean
  S.popup = nil
  toggle:SetValue(true)
  Check(S.popup and S.popup.key == "TWICHUI_CHATCLEAN_ON", "turning it on asks first")
  Check(S.popup.text:find("Trade", 1, true) and S.popup.text:find("never looked at", 1, true), "naming the channels and what is never touched")
  Check(not CC.Enabled(), "and changes nothing yet")
  c.StaticPopupDialogs.TWICHUI_CHATCLEAN_ON.OnAccept()
  Check(CC.Enabled() and CC.Active(), "accepted: on")
  S.popup = nil
  toggle:SetValue(false)
  Check(not S.popup and not CC.Enabled(), "turning it off asks nothing")
  toggle:SetValue(true); c.StaticPopupDialogs.TWICHUI_CHATCLEAN_ON.OnAccept()

  -- the rules tab
  local P = R.ChatCleanRulesPage
  local f = P.Frame()
  f:Hide(); f:Show()
  local count = #CC.Rules()
  Check(f.count.text == ("%d of %d"):format(count, CC.MAX_RULES), "the count")
  P.Open(nil)
  f.text:SetText("cheap carry"); f.name:SetText("")
  Check(P.Save() == true and #CC.Rules() == count + 1 and CC.Rules()[count + 1].text == "cheap carry", "added from the editor")
  Check(P.lastSaid:find("Added", 1, true), "says so")
  -- an everything rule asks first
  P.Open(nil)
  f.mode.onPick("wildcard")
  f.text:SetText("*")
  S.popup = nil
  local saved, why = P.Save()
  Check(not saved and why == "everything" and S.popup and S.popup.key == "TWICHUI_CHATCLEAN_RULE", "a rule matching everything asks first")
  Check(#CC.Rules() == count + 1, "not saved yet")
  c.StaticPopupDialogs.TWICHUI_CHATCLEAN_RULE.OnAccept()
  Check(#CC.Rules() == count + 2 and CC.Rules()[count + 2].text == "*", "saved once accepted")
  local starId = CC.Rules()[count + 2].id
  -- an invalid pattern says why and saves nothing
  P.Open(nil)
  f.mode.onPick("pattern")
  f.text:SetText("[abc")
  saved = P.Save()
  Check(not saved and f.problem.text:find("isn't closed", 1, true), "an invalid pattern: " .. f.problem.text)
  P.Close()
  -- edit: channels
  P.Open(id2)
  Check(f.text.text == "wts*boost" and f.name.text == "Boost sellers", "editing shows the rule")
  f.all.scripts.OnClick(f.all)   -- untick All: the channel boxes become usable
  Check(P.Save() == true, "saved")
  -- remove
  for _, row in ipairs(f.content.children) do
    if row.rule and row.rule.id == starId then row.remove.scripts.OnClick(row.remove) end
  end
  Check(not CC.Rule(starId) and P.lastSaid:find("Removed", 1, true), "removed")
  f:Hide()

  -- the channels tab: rows for joined channels and chosen ones; a tick goes through the feature
  JOINED[2] = { name = "Trade - City", shortcut = "Trade", localID = 2, zoneChannelID = 2, channelType = 1 }
  JOINED[4] = { name = "LookingForGroup", shortcut = "LookingForGroup", localID = 4, zoneChannelID = 26, channelType = 1 }
  local PC = R.ChatCleanChannelsPage
  local fc = PC.Frame()
  fc:Hide(); fc:Show()
  local lfgRow
  for _, row in ipairs(fc.content.children) do if row.ch and row.ch.key == "zone:26" and row.shown then lfgRow = row end end
  Check(lfgRow and lfgRow.status.text:find("/4", 1, true), "a joined channel with its number")
  Check(lfgRow and not lfgRow.cats.spam.active, "filters wait for the channel to be ticked")
  lfgRow.clean.scripts.OnClick(lfgRow.clean)
  Check(CC.Channels()["zone:26"].on and CC.Channels()["zone:26"].spam, "ticked through the feature, with the recommended filters")
  Check(Hidden({ text = SPAM, zone = 26, index = 4, base = "LookingForGroup" }) == true, "and it is cleaned at once")
  fc:Hide()

  -- the tester on the live tab
  local PL = R.ChatCleanLivePage
  local result, say = PL.Test("cheap gold at www.g4mer.com 10% off")
  Check(result.hidden and say:find("Would be hidden", 1, true), "tester: " .. say)
  result, say = PL.Test("LF healer for DM")
  Check(not result.hidden and say:find("Would be shown", 1, true), "tester: " .. say)
end

---------------------------------------------------------------------------
-- 7. Sharing
---------------------------------------------------------------------------
do
  local TC = R.TwichConfig
  local g1, g2 = TC.Group("chatClean"), TC.Group("chatCleanRules")
  Check(g1 and g2 and TC.Usable(g1) and TC.Usable(g2), "two parts: the switch, and channels with rules")
  local entry = TC.Build({ all = true })
  local data = entry.groups.chatCleanRules
  Check(data and data.channels["zone:2"] and #data.rules == #CC.Rules(), "channels and rules travel")
  for _, r in ipairs(data.rules) do Check(r.id == nil, "rule ids stay here") end

  -- a second player receives it
  local B = SettingsClient({ name = "Pal", beforeInit = World })
  local TB = B.TwichUI.TwichConfig
  local CB = B.TwichUI.ChatClean
  CB.AddRule({ mode = "contains", text = "lfg dm", enabled = false })   -- the same rule as one shared: updated, not doubled
  local clean = TB.CleanEntry(entry)
  Check(clean.status == "ok" and clean.groups.chatCleanRules and clean.groups.chatClean, "accepted")
  local plan = TB.Plan(clean)
  local disclosed = table.concat(plan.spending, " ")
  Check(disclosed:find("Chat cleaning: turns on", 1, true), "the review says it turns chat cleaning on: " .. disclosed)
  Check(disclosed:find("custom rule", 1, true), "and how many rules and channels change")
  local okApply, report = TB.Apply(clean, { from = "Rich" })
  Check(okApply, "applied: " .. tostring(report))
  Check(CB.Enabled() and CB.Active(), "on, as the share says")
  local same = 0
  for _, r in ipairs(CB.Rules()) do if r.text == "lfg dm" then same = same + 1; Check(r.enabled, "the matching rule takes the share's on/off") end end
  Check(same == 1, "merged by what the rule matches, not doubled")
  Check(#CB.Rules() == #CC.Rules(), "the rest added")
  Check(CB.Channels()["zone:26"] and CB.Channels()["zone:26"].on, "the shared channel choice")
  -- Undo puts it back
  local okUndo = TB.Undo()
  Check(okUndo and #CB.Rules() == 1 and not CB.Rules()[1].enabled and not CB.Customized(), "Undo: rules and channel choice as they were")

  -- refused: damaged or unsafe parts
  local function Bad(mutate, what)
    local e = TC.Build({ all = true })
    mutate(e.groups.chatCleanRules)
    local cl = TB.CleanEntry(e)
    Check(cl.groups.chatCleanRules == nil and cl.rejected.chatCleanRules, "refused: " .. what)
  end
  Bad(function(d) d.channels["zone:abc"] = { on = true } end, "a bad channel key")
  Bad(function(d) d.channels["zone:2"].on = "yes" end, "a flag that isn't true or false")
  Bad(function(d) d.rules[1] = { mode = "pattern", text = "a.-b.-c.-d" } end, "a costly pattern")
  Bad(function(d) d.rules[1] = { mode = "contains", text = "" } end, "an empty rule")
  Bad(function(d) d.rules[1] = { mode = "lua", text = "os.exit()" } end, "an unknown mode")
  Bad(function(d) for i = 1, CC.MAX_RULES + 1 do d.rules[i] = { mode = "contains", text = "w" .. i } end end, "too many rules")
  Bad(function(d) d.rules.extra = { mode = "contains", text = "x" } end, "a list that isn't a list")
  Bad(function(d) d.channels["zone:2"].label = "Trade|cffff0000x" end, "a label with codes")

  -- an everything rule from a share is called out in the review
  local e = TC.Build({ all = true })
  e.groups.chatCleanRules.rules = { { mode = "wildcard", text = "*", enabled = true, all = true } }
  local p2 = TB.Plan(TB.CleanEntry(e))
  Check(table.concat(p2.spending, " "):find("matches every message", 1, true), "an everything rule is called out")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED")
