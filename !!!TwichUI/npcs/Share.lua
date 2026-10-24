-- TwichUI: Vendors and trainers, sharing your list
-- Sends the NPCs in your list to another TwichUI user (a whisper), your group or your guild, over TwichUI's own hidden
-- addon prefix ("TwichUINpc", never chat), and takes in theirs. Players without TwichUI see nothing of it.
-- Sending is only ever your choice, one list at a time: you pick who, are told exactly how many NPCs go (what you saw
-- yourself; what others sent you only if you chose to pass that on), and confirm. What is sent is that list.
-- Messages, version 1 (serialized, not compressed, so nothing grows on arrival):
--   offer { v, o = "offer", t = transfer id, k = parts, n = entries }   comes first
--   part  { v, o = "part", t, i = 1..k, l = { entry, ... } }            at most PART_SIZE entries each
-- entry: npcs/Store.lua's wire form { i, n, m, x, y, k, c, p }: no player names, no dates, nothing of the sender's.
-- Receiving: who sent it is what the game says, never a field of the message. Everything is checked before anything is
-- kept: the channel, that a group message comes from someone in your group now, the size, the version, the rate per
-- sender, and every field of every entry (npcs/Store.lua's ReadWire). A transfer is held in memory only (at most
-- MAX_STAGES senders at once) until its parts are in, or for STAGE_SECONDS, then (npcs/Prefs.lua's receive choice):
--   ask   a question names the sender and how many NPCs are new to you; nothing is added unless you accept
--   auto  from your party or guild, added without asking (one line in your chat frame says so); a whisper still asks
--   off   nothing is held, nothing is asked
-- Whatever is added is "reported by others" (npcs/Store.lua): it never changes an NPC you saw yourself.
-- The game accepting a message is not proof anyone received it; nothing here claims it.

local R = TwichUI
local NS, NP = R.NpcStore, R.NpcPrefs
local SH = R.Share
local NSH = {}
R.NpcShare = NSH

local AceComm = LibStub("AceComm-3.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

NSH.PREFIX = "TwichUINpc"
NSH.PROTOCOL = 1
NSH.PART_SIZE = 150
NSH.MAX_PARTS = 20                  -- 3000 entries, the size of a whole list
local MAX_TEXT = 40000              -- one encoded message, after AceComm has joined its pieces
local STAGE_SECONDS = 180
local MAX_STAGES = 3
local MAX_QUESTIONS = 3
local SEND_GAP = 20                 -- seconds between your own sends
local BUCKET_SIZE, BUCKET_REFILL = 25, 1
local MAX_BUCKETS = 40

local stats = { sent = 0, refused = 0, received = 0, transfers = 0, added = 0, asked = 0, declined = 0, dropped = 0 }
local drops = {}
local staging = {}                  -- [sender] = { t, k, n, dist, got, parts = {}, entries = {}, bad }
local questions = {}                -- waiting to be asked: { sender, dist, entries, preview, partial }
local asking = false
local buckets = {}
local lastSend = -math.huge

local function Enabled() return R:Enabled("npcMap") end
local function Now() return GetTime() end
local function Drop(code)
    drops[code] = (drops[code] or 0) + 1
    stats.dropped = stats.dropped + 1
end
local function Whole(n, low, high) return type(n) == "number" and n == n and n % 1 == 0 and n >= low and n <= high end
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function Npcs(n) return ("%d %s"):format(n, n == 1 and "NPC" or "NPCs") end

local function GroupDist()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return IsInRaid() and "RAID" or "PARTY"
end

local function InGroup(name)
    if not IsInGroup() then return false end
    local unit, count = "party", 4
    if IsInRaid() then unit, count = "raid", 40 end
    for i = 1, count do
        local n = GetUnitName(unit .. i, true)
        if n and SH.SameName(n, name) then return true end
    end
    return false
end

local function Encode(msg) return LibDeflate:EncodeForWoWAddonChannel(LibSerialize:Serialize(msg)) end

local function Decode(text)
    local raw = LibDeflate:DecodeForWoWAddonChannel(text)
    if not raw then return nil end
    local ok, success, t = pcall(LibSerialize.Deserialize, LibSerialize, raw)
    if ok and success and type(t) == "table" then return t end
end

local function Trace(code, detail)
    local D = R.Diag
    if D and D.Tracing() then D.Trace("npcs", code, detail) end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
NSH.AUDIENCE = { party = "your group", guild = "your guild", whisper = nil }

-- What a send would be, exactly: { audience, dist, target, label, wires, own, reported, parts }, or nil and a sentence.
-- audience: "party", "guild" or "whisper" (target: the character's name).
function NSH.Plan(audience, target)
    if not Enabled() then return nil, "Vendors and trainers is turned off." end
    if SH.Blocked() then return nil, "The game isn't letting addons send messages right now. Try again later." end
    local plan = { audience = audience }
    if audience == "party" then
        if not IsInGroup() then return nil, "You aren't in a group." end
        plan.dist, plan.label = GroupDist(), "your group"
    elseif audience == "guild" then
        if not IsInGuild() then return nil, "You aren't in a guild." end
        plan.dist, plan.label = "GUILD", "your guild"
    elseif audience == "whisper" then
        local name = SH.FullName(type(target) == "string" and target or nil)
        if not name then return nil, "Type the name of the character to send to." end
        if SH.SameName(name, SH.SelfName()) then return nil, "That's you." end
        plan.dist, plan.target, plan.label = "WHISPER", name, SH.Short(name)
    else
        return nil, "Choose who to send to."
    end
    local withReports = NP.Get("sendReports")
    local wires, own, reported = {}, 0, 0
    local max = NSH.MAX_PARTS * NSH.PART_SIZE
    for _, e in ipairs(NS.Entries()) do
        if #wires >= max then break end
        if e.own or withReports then
            wires[#wires + 1] = NS.Wire(e)
            if e.own then own = own + 1 else reported = reported + 1 end
        end
    end
    if #wires == 0 then
        return nil, withReports and "Your list is empty." or "You haven't noted any NPCs yourself yet, so there is nothing to send."
    end
    plan.wires, plan.own, plan.reported = wires, own, reported
    plan.parts = math.ceil(#wires / NSH.PART_SIZE)
    return plan
end

function NSH.Describe(plan)
    local what = ("%d %s you dealt with yourself"):format(plan.own, plan.own == 1 and "NPC" or "NPCs")
    if plan.reported > 0 then what = what .. (" and %d others sent you"):format(plan.reported) end
    local reach = plan.dist == "WHISPER" and ("Only %s receives it."):format(plan.label)
        or ("Everyone in %s with TwichUI receives it; each of them chooses whether to add it."):format(plan.label)
    return ("Send %s to %s?\n\nEach is its name, its place and what it offers. Nothing about you or your character is in it. %s It takes about %d seconds to send."):format(
        what, plan.label, reach, math.max(2, math.ceil(#plan.wires / 12)))
end

-- Sends exactly the plan. Returns true when the game took the first message (not that anyone got it), or false and a
-- sentence.
function NSH.Send(plan)
    if not Enabled() then return false, "Vendors and trainers is turned off." end
    if Now() - lastSend < SEND_GAP then return false, "You sent a list a moment ago. Wait a little before sending again." end
    if SH.Blocked() then return false, "The game isn't letting addons send messages right now. Try again later." end
    lastSend = Now()
    local t = math.random(1, 2 ^ 30)
    local msgs = { { v = NSH.PROTOCOL, o = "offer", t = t, k = plan.parts, n = #plan.wires } }
    for i = 1, plan.parts do
        local l = {}
        for j = (i - 1) * NSH.PART_SIZE + 1, math.min(i * NSH.PART_SIZE, #plan.wires) do l[#l + 1] = plan.wires[j] end
        msgs[#msgs + 1] = { v = NSH.PROTOCOL, o = "part", t = t, i = i, l = l }
    end
    local refused = false
    for n, msg in ipairs(msgs) do
        local last = n == #msgs
        AceComm:SendCommMessage(NSH.PREFIX, Encode(msg), plan.dist, plan.target, "BULK", function(_, sent, total, accepted)
            if accepted == false and not refused then
                refused = true
                stats.refused = stats.refused + 1
                R.Print("the game didn't send part of your vendors and trainers list. Try again later.")
            elseif last and sent == total and not refused then
                R.Print("finished sending your vendors and trainers list to %s.", plan.label)
            end
        end)
        stats.sent = stats.sent + 1
    end
    Trace("sent", plan.dist)
    R.Print("sending %s from your vendors and trainers list to %s.", Npcs(#plan.wires), plan.label)
    return true
end

-- The whole path a button or a command takes: plan, the question, then the send.
function NSH.Offer(audience, target)
    local plan, why = NSH.Plan(audience, target)
    if not plan then R.Print("%s", why) return false end
    R.Interact.Confirm("TWICHUI_NPC_SEND", NSH.Describe(plan), function()
        local ok, err = NSH.Send(plan)
        if not ok then R.Print("%s", err) end
    end, { accept = "Send" })
    return true
end

-- Asks for a character's name (your target's, when it is a player, is filled in), then offers to them.
function NSH.AskName()
    StaticPopupDialogs.TWICHUI_NPC_SEND_TO = {
        text = "Send your vendors and trainers list to which character? They need TwichUI to receive it.",
        button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, maxLetters = 64,
        OnShow = function(self)
            local box = self.editBox or self.EditBox
            if not box then return end
            local name = UnitIsPlayer and UnitIsPlayer("target") and GetUnitName("target", true) or ""
            box:SetText(type(name) == "string" and not Secret(name) and name or "")
            box:HighlightText()
        end,
        OnAccept = function(self)
            local box = self.editBox or self.EditBox
            local name = box and box:GetText()
            C_Timer.After(0, function() NSH.Offer("whisper", name) end)   -- after this popup has gone
        end,
        EditBoxOnEnterPressed = function(box)
            local parent = box:GetParent()
            local name = box:GetText()
            parent:Hide()
            C_Timer.After(0, function() NSH.Offer("whisper", name) end)
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_NPC_SEND_TO")
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local function Take(sender)
    local now = Now()
    local b = buckets[sender]
    if not b then
        local n = 0
        for _ in pairs(buckets) do n = n + 1 end
        if n >= MAX_BUCKETS then wipe(buckets) end
        b = { tokens = BUCKET_SIZE, at = now }
        buckets[sender] = b
    end
    b.tokens = math.min(BUCKET_SIZE, b.tokens + (now - b.at) * BUCKET_REFILL)
    b.at = now
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end

local AskNext

local function Add(q)
    local result = NS.MergeReported(q.entries)
    stats.added = stats.added + result.added
    return result
end

local function Question(q)
    local p = q.preview
    local who = SH.Short(q.sender)
    local lines = { ("%s sent you %s from their vendors and trainers list%s."):format(who, Npcs(p.total),
        q.partial and " (not all of it arrived)" or "") }
    local parts = {}
    if p.new > 0 then parts[#parts + 1] = ("%d %s new to you"):format(p.new, p.new == 1 and "is" or "are") end
    if p.more > 0 then parts[#parts + 1] = ("%d %s to what others sent you"):format(p.more, p.more == 1 and "adds" or "add") end
    if p.yours > 0 then parts[#parts + 1] = ("%d you have seen yourself (they stay as you saw them)"):format(p.yours) end
    lines[#lines + 1] = table.concat(parts, "; ") .. "."
    lines[#lines + 1] = "Add them to your map? They are marked as reported by others until you visit them yourself."
    return table.concat(lines, "\n\n")
end

local askedAt = 0
local ASK_STALE = 600   -- a question gone without an answer (hidden by something else) stops holding the others back

function AskNext()
    if asking and Now() - askedAt < ASK_STALE then return end
    local q = table.remove(questions, 1)
    if not q then return end
    asking, askedAt = true, Now()
    stats.asked = stats.asked + 1
    local popup = R.Interact.Confirm("TWICHUI_NPC_RECEIVE", Question(q), function()
        asking = false
        local result = Add(q)
        R.Print("added %s from %s's vendors and trainers list.", Npcs(result.added + result.more), SH.Short(q.sender))
        C_Timer.After(0, AskNext)
    end, { accept = "Add", cancel = "No thanks", onCancel = function()
        asking = false
        stats.declined = stats.declined + 1
        C_Timer.After(0, AskNext)
    end })
    if not popup then asking = false end
end

-- A transfer is in (or timed out): what the receive choice says.
local function Finish(sender, partial)
    local st = staging[sender]
    staging[sender] = nil
    if not st or #st.entries == 0 then return end
    stats.transfers = stats.transfers + 1
    local preview = NS.PreviewMerge(st.entries)
    if preview.new + preview.more == 0 then return end   -- nothing you don't already have: nothing to ask
    local mode = NP.Get("receive")
    if mode == "off" then return end
    if mode == "auto" and st.dist ~= "WHISPER" then
        local result = Add({ entries = st.entries })
        R.Print("added %s from %s's vendors and trainers list.", Npcs(result.added + result.more), SH.Short(sender))
        return
    end
    if #questions >= MAX_QUESTIONS then Drop("too-many-questions") return end
    questions[#questions + 1] = { sender = sender, dist = st.dist, entries = st.entries, preview = preview, partial = partial }
    AskNext()
end

local function OnOffer(sender, dist, msg)
    if not (Whole(msg.t, 1, 2 ^ 31) and Whole(msg.k, 1, NSH.MAX_PARTS) and Whole(msg.n, 1, msg.k * NSH.PART_SIZE)) then
        Drop("bad-offer") return
    end
    if not staging[sender] then
        local n = 0
        for _ in pairs(staging) do n = n + 1 end
        if n >= MAX_STAGES then Drop("too-many-transfers") return end
    end
    local st = { t = msg.t, k = msg.k, n = msg.n, dist = dist, got = 0, parts = {}, entries = {}, bad = 0 }
    staging[sender] = st
    C_Timer.After(STAGE_SECONDS, function()
        if staging[sender] == st then
            Drop("timed-out")
            Finish(sender, true)
        end
    end)
end

local function OnPart(sender, dist, msg)
    local st = staging[sender]
    if not st or st.t ~= msg.t or st.dist ~= dist then Drop("no-offer") return end
    if not Whole(msg.i, 1, st.k) or st.parts[msg.i] then Drop("bad-part") return end
    if type(msg.l) ~= "table" or #msg.l > NSH.PART_SIZE then Drop("bad-part") return end
    st.parts[msg.i] = true
    st.got = st.got + 1
    for _, w in ipairs(msg.l) do
        if #st.entries >= st.n then break end
        local f = NS.ReadWire(w)
        if f then st.entries[#st.entries + 1] = f else st.bad = st.bad + 1 end
    end
    if st.got == st.k then Finish(sender, false) end
end

local VALID_DIST = { WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true }

local function OnMessage(_, text, dist, sender)
    if not Enabled() then return end
    if NP.Get("receive") == "off" then Drop("receive-off") return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then Drop("unreadable") return end
    if not VALID_DIST[dist] then Drop("channel") return end
    sender = SH.FullName(sender)
    if not sender or SH.SameName(sender, SH.SelfName()) then return end   -- your own, echoed back
    if (dist == "PARTY" or dist == "RAID" or dist == "INSTANCE_CHAT") and not InGroup(sender) then Drop("not-member") return end
    if dist == "GUILD" and not IsInGuild() then Drop("not-member") return end
    if not Take(sender) then Drop("rate") return end
    if #text > MAX_TEXT then Drop("too-large") return end
    local msg = Decode(text)
    if not msg then Drop("undecodable") return end
    if msg.v ~= NSH.PROTOCOL then
        Drop(type(msg.v) == "number" and msg.v > NSH.PROTOCOL and "newer-protocol" or "bad-version")
        return
    end
    stats.received = stats.received + 1
    if msg.o == "offer" then OnOffer(sender, dist, msg)
    elseif msg.o == "part" then OnPart(sender, dist, msg)
    else Drop("unknown-op") return end
    Trace("received", msg.o)
end

AceComm:RegisterComm(NSH.PREFIX, OnMessage)

-- The switch went off: anything held is let go.
function NSH.Refresh()
    if Enabled() then return end
    wipe(staging)
    wipe(questions)
    wipe(buckets)
end

-- /tui npcs: the options; send party|guild|<name> (send with nothing after it asks for a name); probe.
function R.NpcCommand(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "" then R:OpenSettings("npcs") return end
    if word == "probe" then R.NpcCollect.Probe() return end
    if word == "send" then
        local to = rest:lower()
        if not Enabled() then R.Print("Vendors and trainers is turned off. Turn it on in /tui npcs.") return end
        if to == "party" or to == "group" then NSH.Offer("party")
        elseif to == "guild" then NSH.Offer("guild")
        elseif rest ~= "" then NSH.Offer("whisper", rest)
        else NSH.AskName() end
        return
    end
    R.Print("type %s/tui npcs|r for its options, %s/tui npcs send party|r, %sguild|r or a character's name to share your list, or %s/tui npcs probe|r.",
        R.GOLD, R.GOLD, R.GOLD, R.GOLD)
end

-- Read only, for /tui diagnostics: counts and words, never names, places or payloads.
function NSH.Snapshot()
    local held = 0
    for _ in pairs(staging) do held = held + 1 end
    local d = {}
    for k, v in pairs(drops) do d[k] = v end
    local registered = "unknown"
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok, result = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, NSH.PREFIX)
        if ok then registered = result and "registered" or "not registered" end
    end
    return { protocol = NSH.PROTOCOL, prefix = NSH.PREFIX, prefixState = registered, held = held, waiting = #questions,
        sent = stats.sent, refused = stats.refused, received = stats.received, transfers = stats.transfers,
        added = stats.added, asked = stats.asked, declined = stats.declined, dropped = stats.dropped, drops = d }
end
