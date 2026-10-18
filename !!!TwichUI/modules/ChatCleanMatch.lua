-- TwichUI: chat cleaning, how a message is read and matched
-- Pure functions: nothing here touches the game, saved data or chat. modules/ChatClean.lua decides which messages are
-- looked at and keeps the settings; it compiles each rule here once, when the settings change, never per message.
--
-- What is matched. A channel message as the game delivers it can carry formatting: colors (|cAARRGGBB ... |r, |cn...:),
-- links (|H<hidden data>|h[shown text]|h), textures and atlases (|T...|t, |A...|a) and a doubled || for a typed "|".
-- Rules and filters read the VISIBLE text: colors, textures and the hidden part of a link are removed, a link becomes
-- the text you see ("[Copper Bar]"), and || becomes "|". So a rule never matches a link's hidden data, and a message
-- is never changed: the original is what chat shows when it is allowed.
--   visible   that text, as written
--   lower     the same with A-Z lowered. The game's string.lower changes only A-Z, so "Ä" and "Ä" differ from "ä";
--             TwichUI doesn't claim more case folding than that.
--   squash    lower without spaces, punctuation or control characters ("W W W . x" reads "wwwx"), for the built-in
--             filters, which look past spacing tricks
--
-- Custom rules (see M.CheckRule for the limits):
--   contains  the text anywhere in the message. Every character is literal: "50%", "[item]" and "a.b" mean exactly that.
--   wildcard  * is any run of characters (none included), ? is one character; everything else is literal. Matches
--             anywhere in the message, like contains. Compiled into literal pieces found one after another, earliest
--             first, which is exact for * and ? and never backtracks, so its cost grows with the message length only.
--   pattern   a Lua pattern (not a regular expression), for people who know them, matched as written (case
--             included) against the visible text. Bounded so it can't stall chat: at most PATTERN_MAX bytes, at most
--             MAX_REPEATS unbounded repetitions (* + - and %b), no back-references, checked for shape before it is
--             accepted, and run under pcall on at most SCAN_MAX bytes of a message.
-- Nothing a player types is ever run as Lua.

local R = TwichUI
local M = {}
R.ChatCleanMatch = M

local find, gsub, gmatch, sub, lower, byte = string.find, string.gsub, string.gmatch, string.sub, string.lower, string.byte

M.TEXT_MAX = 100        -- characters in a rule's text
M.NAME_MAX = 40         -- characters in a rule's name
M.PATTERN_MAX = 80      -- bytes in a Lua pattern
M.MAX_REPEATS = 2       -- unbounded repetitions in a Lua pattern
M.SCAN_MAX = 512        -- bytes of a message that are read (the game's own limit for a chat line is 255)
M.MODES = { contains = true, wildcard = true, pattern = true }

---------------------------------------------------------------------------
-- Reading a message
---------------------------------------------------------------------------
-- The text a player sees. A message without any formatting is returned as it is (no copy).
function M.Visible(msg)
    if type(msg) ~= "string" then return "" end
    if #msg > M.SCAN_MAX then msg = sub(msg, 1, M.SCAN_MAX) end
    if not find(msg, "|", 1, true) then return msg end
    local s = gsub(msg, "||", "\1")                   -- a typed "|", kept apart from the codes
    s = gsub(s, "|c%x%x%x%x%x%x%x%x", "")
    s = gsub(s, "|cn[^:|]*:", "")
    s = gsub(s, "|r", "")
    s = gsub(s, "|H.-|h(.-)|h", "%1")                 -- a link: only what it shows
    s = gsub(s, "|T.-|t", "")
    s = gsub(s, "|A.-|a", "")
    s = gsub(s, "|K.-|k", "")
    s = gsub(s, "|n", " ")
    s = gsub(s, "|", "")                              -- what is left of a code that wasn't complete
    return (gsub(s, "\1", "|"))
end

function M.Lower(s) return lower(s) end

function M.Squash(lowered) return (gsub(lowered, "[%s%c%p]", "")) end

-- Safe to show in a font string: the visible text with every "|" doubled, so nothing in it is a code (no colors,
-- textures or clickable links).
function M.Plain(msg)
    return (gsub(M.Visible(msg), "|", "||"))
end

-- A short number standing for a text, so the repeat check never keeps the message itself.
function M.Hash(s)
    local h = 5381
    for i = 1, math.min(#s, 200) do h = (h * 33 + byte(s, i)) % 2147483647 end
    return h
end

---------------------------------------------------------------------------
-- Characters (UTF-8): counted and checked, never cut in the middle of one
---------------------------------------------------------------------------
function M.Characters(s)
    local n = 0
    for _ in gmatch(s, "[^\128-\191]") do n = n + 1 end
    return n
end

-- Whether s is well-formed UTF-8 (a rule's text must be, so ? always means one whole character).
function M.ValidUTF8(s)
    local i, n = 1, #s
    while i <= n do
        local c = byte(s, i)
        local len = (c < 128 and 1) or (c >= 194 and c <= 223 and 2) or (c >= 224 and c <= 239 and 3) or (c >= 240 and c <= 244 and 4) or nil
        if not len or i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local d = byte(s, j)
            if d < 128 or d > 191 then return false end
        end
        i = i + len
    end
    return true
end

---------------------------------------------------------------------------
-- Lua patterns: their shape, checked before one is accepted
---------------------------------------------------------------------------
-- Returns true, or false and a sentence. Follows the rules of Lua 5.1's matcher closely enough to refuse what it
-- would refuse (an unfinished %, set or capture) and to count what can make it slow.
function M.InspectPattern(p)
    local n = #p
    if n == 0 then return false, "Type a pattern." end
    if n > M.PATTERN_MAX then return false, ("A pattern can be at most %d characters."):format(M.PATTERN_MAX) end
    local i, depth, repeats = 1, 0, 0
    if sub(p, 1, 1) == "^" then i = 2 end
    local function Set()   -- at "[": past the matching "]"
        i = i + 1
        if sub(p, i, i) == "^" then i = i + 1 end
        if sub(p, i, i) == "]" then i = i + 1 end
        while true do
            local c = sub(p, i, i)
            if c == "" then return false end
            if c == "]" then i = i + 1 return true end
            if c == "%" then
                if i + 1 > n then return false end
                i = i + 2
            else
                i = i + 1
            end
        end
    end
    while i <= n do
        local c = sub(p, i, i)
        if c == "(" then
            depth = depth + 1
            i = i + 1
            if sub(p, i, i) == ")" then depth, i = depth - 1, i + 1 end   -- a position capture
        elseif c == ")" then
            depth = depth - 1
            if depth < 0 then return false, "A \")\" has no \"(\" before it." end
            i = i + 1
        elseif c == "$" and i == n then
            i = i + 1
        else
            local single = true   -- a single-character class, which may be followed by a repetition
            if c == "%" then
                local d = sub(p, i + 1, i + 1)
                if d == "" then return false, "A pattern can't end with %." end
                if d == "b" then
                    if i + 3 > n then return false, "%b needs two characters after it, such as %b()." end
                    i, single, repeats = i + 4, false, repeats + 1
                elseif d == "f" then
                    if sub(p, i + 2, i + 2) ~= "[" then return false, "%f needs a set after it, such as %f[%a]." end
                    i = i + 2
                    if not Set() then return false, "A \"[\" set isn't closed with \"]\"." end
                    single = false
                elseif find(d, "%d") then
                    return false, "Back-references such as %1 aren't supported here."
                else
                    i = i + 2
                end
            elseif c == "[" then
                if not Set() then return false, "A \"[\" set isn't closed with \"]\"." end
            else
                i = i + 1
            end
            if single then
                local q = sub(p, i, i)
                if q == "*" or q == "+" or q == "-" then
                    repeats, i = repeats + 1, i + 1
                elseif q == "?" then
                    i = i + 1
                end
            end
        end
    end
    if depth ~= 0 then return false, "A \"(\" isn't closed with \")\"." end
    if repeats > M.MAX_REPEATS then
        return false, ("A pattern can repeat (with * + - or %%b) at most %d times, so it stays quick."):format(M.MAX_REPEATS)
    end
    local ok = pcall(find, "", p)
    if not ok then return false, "The game can't read this pattern." end
    return true
end

---------------------------------------------------------------------------
-- Rules: checked, compiled, described
---------------------------------------------------------------------------
local ONE = "[\1-\127\194-\244][\128-\191]*"   -- ? : one whole UTF-8 character

local function Trim(s) return (gsub(s, "^%s+", ""):gsub("%s+$", "")) end

-- A wildcard's literal pieces, in order: { plain = text } or { pattern = escaped text with ? as one character }.
local function Pieces(text)
    local pieces, literal = {}, false
    for piece in gmatch(text .. "*", "([^*]*)%*") do
        if piece ~= "" then
            if find(piece, "?", 1, true) then
                local p = gsub(piece, "[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
                p = gsub(p, "%?", ONE)
                pieces[#pieces + 1] = { pattern = p }
                if find(piece, "[^?]") then literal = true end
            else
                pieces[#pieces + 1] = { plain = piece }
                literal = true
            end
        end
    end
    return pieces, literal
end
M.Pieces = Pieces

-- def: { name, mode, text, case, enabled, ... }. Returns a clean copy of the parts a rule is matched by
-- ({ name, mode, text, case }) or nil and a sentence saying what to fix. Never reads or changes anything else.
function M.CheckRule(def)
    if type(def) ~= "table" then return nil, "That isn't a rule." end
    local mode = def.mode
    if mode == nil then mode = "contains" end
    if not M.MODES[mode] then return nil, "Choose how the text is matched." end
    if type(def.text) ~= "string" then return nil, "Type the text to match." end
    local text = def.text
    if mode ~= "pattern" then text = Trim(text) end
    if text == "" then return nil, mode == "pattern" and "Type a pattern." or "Type the text to match." end
    if #text > M.TEXT_MAX * 4 or not M.ValidUTF8(text) then return nil, "That text can't be used." end
    if find(text, "%c") then return nil, "The text can't hold line breaks or other control characters." end
    if M.Characters(text) > M.TEXT_MAX then return nil, ("The text can be at most %d characters."):format(M.TEXT_MAX) end
    if mode == "pattern" then
        local ok, why = M.InspectPattern(text)
        if not ok then return nil, why end
    end
    local name = def.name
    if name ~= nil and type(name) ~= "string" then return nil, "That name can't be used." end
    name = name and Trim(name) or ""
    if name ~= "" then
        if #name > M.NAME_MAX * 4 or not M.ValidUTF8(name) or find(name, "[%c|]") then
            return nil, "A name can't hold \"|\", line breaks or other control characters."
        end
        if M.Characters(name) > M.NAME_MAX then return nil, ("A name can be at most %d characters."):format(M.NAME_MAX) end
    end
    return { name = name ~= "" and name or nil, mode = mode, text = text, case = mode ~= "pattern" and def.case == true or false }
end

-- What a rule matches against, for one message (see the top of the file).
-- Returns a function(visible, lowered) -> true when the message matches.
function M.Compile(rule)
    local mode, case = rule.mode, rule.case
    if mode == "contains" then
        local needle = case and rule.text or lower(rule.text)
        return function(visible, lowered)
            return find(case and visible or lowered, needle, 1, true) ~= nil
        end
    elseif mode == "wildcard" then
        local pieces = Pieces(case and rule.text or lower(rule.text))
        return function(visible, lowered)
            local s, pos = case and visible or lowered, 1
            for i = 1, #pieces do
                local piece = pieces[i]
                local _, last
                if piece.plain then _, last = find(s, piece.plain, pos, true) else _, last = find(s, piece.pattern, pos) end
                if not last then return false end
                pos = last + 1
            end
            return true
        end
    elseif mode == "pattern" then
        local pattern = rule.text
        return function(visible)
            local ok, at = pcall(find, visible, pattern)
            if not ok then error("pattern", 0) end   -- ChatClean.lua lets the message through and counts it
            return at ~= nil
        end
    end
end

-- Messages a rule is checked against to see whether it would hide everything.
local PROBES = { "", "x", "lf healer", "WTS [Copper Bar] 5s", "123", "?!", "Привет" }

-- Warnings about a checked rule that is valid but would hide far more than it likely means to: { code, text } or nil.
--   "everything"  matches every message (an empty-matching pattern, a wildcard of only * and ?)
--   "broad"       very short text, which is in many ordinary messages
function M.Warning(rule)
    local everything
    if rule.mode == "wildcard" then
        local _, literal = Pieces(rule.text)
        everything = not literal
    elseif rule.mode == "pattern" then
        everything = true
        local test = M.Compile(rule)
        for _, probe in ipairs(PROBES) do
            local ok, hit = pcall(test, probe, lower(probe))
            if not (ok and hit) then everything = false break end
        end
    end
    if everything then
        return { code = "everything", text = "This rule matches every message, so it would hide everything in the channels it applies to." }
    end
    if rule.mode ~= "pattern" and M.Characters((gsub(rule.text, "[*?%s]", ""))) <= 2 then
        return { code = "broad", text = "Text this short is part of many ordinary messages, so this rule would hide a lot." }
    end
end

local MODE_WORDS = { contains = "Contains", wildcard = "Wildcard", pattern = "Lua pattern" }
M.MODE_WORDS = MODE_WORDS

-- "Contains \"wts\"" and the like, for a rule without a name. Plain text (shown with M.Plain where it is drawn).
function M.Summary(rule)
    local text = rule.text or ""
    if M.Characters(text) > 32 then
        local out, count = {}, 0
        for ch in gmatch(text, "[^\128-\191][\128-\191]*") do
            count = count + 1
            if count > 30 then break end
            out[count] = ch
        end
        text = table.concat(out) .. "..."
    end
    return ("%s \"%s\""):format(MODE_WORDS[rule.mode] or "Contains", text)
end

---------------------------------------------------------------------------
-- The built-in filters. Each reads the lowered visible text (and its squashed form) and asks for several signs
-- together, so an ordinary trade advert (WTS [item] 5g), a link or a capitalized message is never enough alone.
---------------------------------------------------------------------------
local TLD = { com = true, net = true, org = true, ru = true, cn = true, cc = true, co = true, io = true, gg = true,
    us = true, info = true, shop = true, store = true, top = true, xyz = true, vip = true, pro = true, club = true,
    site = true, online = true, me = true, tv = true, biz = true }

-- A web address, written plainly or spelled out to slip past filters ("www . site . c o m", "site dot com").
local function Site(lowered, squashed)
    if find(lowered, "https?://") or find(lowered, "www%s*[%.,]") then return true end
    for tld in gmatch(lowered, "%w%.(%a%a%a?%a?%a?%a?)%f[^%a]") do
        if TLD[tld] then return true end
    end
    if find(lowered, "%w%s*[%.,]%s*c%s*[o0]%s*m%f[^%a]") then return true end
    if find(squashed, "dotc[o0]m") or find(squashed, "dotnet") or find(squashed, "dotorg") then return true end
    return false
end

local function Goods(squashed)
    return find(squashed, "g[o0]ld") or find(squashed, "b[o0][o0]st") or find(squashed, "powerl[e3]vel")
        or find(squashed, "level?ling") or find(squashed, "carr[yi]") or find(squashed, "account")
end

local function Price(lowered)
    return find(lowered, "$", 1, true) or find(lowered, "€", 1, true) or find(lowered, "£", 1, true)
        or find(lowered, "%d%s*%%") or find(lowered, "%f[%a]usd%f[%A]") or find(lowered, "%f[%a]eur%f[%A]")
        or find(lowered, "discount") or find(lowered, "cheap") or find(lowered, "price") or find(lowered, "coupon")
        or find(lowered, "promo") or find(lowered, "%f[%a]sale%f[%A]") or find(lowered, "deliver")
end

-- Whether the message carries a community or guild invitation link (|HclubFinder:...|h or |HclubTicket:...|h, the
-- links the Guild & Communities window opens on, with Accept and Decline). Read from the link's type only; a typed
-- "||Hclub..." is not a link. Gold sellers use them because the name shown on the link is free text.
function M.HasClubLink(msg)
    if type(msg) ~= "string" then return false end
    if #msg > M.SCAN_MAX then msg = sub(msg, 1, M.SCAN_MAX) end
    if not find(msg, "|Hclub", 1, true) then return false end
    msg = gsub(msg, "||", "")
    return (find(msg, "|HclubFinder:", 1, true) or find(msg, "|HclubTicket:", 1, true)) and true or false
end

-- Selling gold, boosts or levelling for money: a web address, something sold and a price or discount, all three.
-- With a community or guild invitation link (clubLink), the name on the link is itself the advert, so a web address
-- and something sold, or something sold and a price, are enough.
function M.Spam(lowered, squashed, clubLink)
    local goods = Goods(squashed)
    if not goods then return false end
    local site = Site(lowered, squashed)
    if site and Price(lowered) then return true end
    return (clubLink and (site or Price(lowered))) and true or false
end

-- Guild recruitment: the word recruit, or "guild" with an invitation to join, whisper or apply.
function M.Recruit(lowered)
    if find(lowered, "recruit") then return true end
    if not find(lowered, "guild") then return false end
    return (find(lowered, "looking for") or find(lowered, "join") or find(lowered, "%f[%a]inv") or find(lowered, "/w")
        or find(lowered, "whisper") or find(lowered, "members") or find(lowered, "raiders") or find(lowered, "all levels")
        or find(lowered, "apply")) and true or false
end
