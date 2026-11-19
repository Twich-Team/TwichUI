-- TwichUI Workshop: progress notices (P2.1)
-- A short card through TwichUI's own notification coordinator (R.Notify, modules/Notify.lua: one queue for every card, Quiet screen, duplicates,
-- loading screens and the other cards' places are its rules, not this file's). The card follows the shared notification look (NotifyLook,
-- through Arrival.Typeset, as the other cards do) and never takes the mouse.
-- What is said, and only when it is verified:
--   * a queued craft was counted as done (Progress.Credit: the player's own "Crafted one", or the game's evidence once that is switched on):
--     "Bolt of Woolen Cloth crafted: 2 crafts left." / "Bolt of Woolen Cloth completed." / "Crafting plan complete."
--   * what the bags hold changed so that a queued recipe now has all its materials (Readiness, compared with what was true before; the first
--     look after the window or the compact view opens is only remembered, never announced, so a login or a first scan says nothing):
--     "All materials for Basic Campfire are ready." / "Materials ready for 3 recipes." / "Everything for your crafting plan is in your bags."
-- Never said: that an item was bought, collected or looted (a bag count going up does not say how), anything about another player, anything
-- in chat. Rapid progress is gathered for GATHER seconds into one card; the same words are not shown twice within REPEAT seconds.
-- Off with TwichUIDB.workshop.view.notices = false (the Crafting page's "Progress notices" switch); on by default.

local R = TwichUI
local W = R.Workshop
local S, Q, O, K2 = W.Session, W.Queue, W.Observe, W.Stock
local UI = W.UI
local Nt = {}
W.Notice = Nt

Nt.KIND = "workshop"
Nt.GATHER = 1.5
Nt.REPEAT = 20
local WIDTH, HEIGHT, HOLD = 360, 46, 4

local pending = {}        -- messages gathered for the next card: { text, at }
local gathering = false
local lastText, lastAt
local before              -- [recipe id] = true when its materials were all in the bags at the last look; nil: not looked yet
local stats = { submitted = 0, refused = 0, gathered = 0, repeated = 0 }

local function Now() return GetTime and GetTime() or 0 end

function Nt.On()
    if not W.Active() then return false end
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local v = type(ws) == "table" and ws.view
    return not (type(v) == "table" and v.notices == false)
end

function Nt.SetOn(on)
    if Q.Held() or type(TwichUIDB) ~= "table" then return false end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if on then return true end
        ws = { v = W.SAVED_VERSION }
        TwichUIDB.workshop = ws
    end
    if type(ws.view) ~= "table" then ws.view = {} end
    if on == false then ws.view.notices = false else ws.view.notices = nil end   -- (not "and false or nil": that is always nil)
    return true
end

---------------------------------------------------------------------------
-- The words (pure)
---------------------------------------------------------------------------
function Nt.CreditText(info)
    if info.planDone then return "Crafting plan complete." end
    if info.done then return info.name .. " completed." end
    return ("%s crafted: %d %s left."):format(info.name, info.left, info.left == 1 and "craft" or "crafts")
end

-- names: the recipes that became ready; all: every queued recipe is ready now
function Nt.ReadyText(names, all)
    if all and #names > 0 then return "Everything for your crafting plan is in your bags." end
    if #names == 1 then return ("All materials for %s are ready."):format(names[1]) end
    if #names > 1 then return ("Materials ready for %d recipes."):format(#names) end
    return nil
end

-- several messages gathered at once: one card (the last is the newest)
function Nt.Gather(list)
    if #list == 0 then return nil end
    if #list == 1 then return list[1] end
    for _, t in ipairs(list) do if t == "Crafting plan complete." then return t end end
    return ("%s (and %d more)"):format(list[#list], #list - 1)
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local card
local function Build()
    if card or not CreateFrame then return card end
    card = CreateFrame("Frame", nil, UIParent)
    card:SetSize(WIDTH, HEIGHT)
    card:SetPoint("TOP", UIParent, "TOP", 0, -190)
    card:SetFrameStrata("LOW")
    card:EnableMouse(false)
    card:SetClampedToScreen(true)
    card:Hide()
    UI.Panel(card, "card")
    card.title = UI.Text(card, 12, UI.K.bronzeText, "strong")
    card.title:SetPoint("TOPLEFT", 14, -8)
    card.title:SetText("Workshop")
    card.text = UI.Text(card, 14, UI.K.text, "strong")
    card.text:SetPoint("TOPLEFT", 14, -24)
    card.text:SetPoint("RIGHT", -14, 0)
    return card
end

local showing = 0
local function Dismiss()
    showing = showing + 1
    if card then card:Hide() end
    if R.Notify then R.Notify.Finished(Nt.KIND) end
end

local function Show(p)
    if not Build() then return false end
    local A = R.Arrival
    if A and A.Typeset then   -- the shared notification look, as the other cards use it
        pcall(A.Typeset, Nt.KIND, card.text, { role = "title", size = 14, color = UI.K.text })
    end
    card.text:SetText(p.text)
    card:Show()
    showing = showing + 1
    local mine = showing
    C_Timer.After(HOLD, function() if mine == showing then Dismiss() end end)
    return true
end

local registered = false
local function Register()
    if registered or not (R.Notify and R.Notify.Register) then return registered end
    R.Notify.Register(Nt.KIND, {
        label = "Workshop progress",
        show = function(p) return Show(p) end,
        dismiss = Dismiss,
        hold = function() return HOLD end,
        ready = function() return not (InCombatLockdown and InCombatLockdown()) end,
        sample = function() return { text = "All materials for Bolt of Woolen Cloth are ready." } end,
    })
    registered = true
    return true
end

local function Flush()
    gathering = false
    local list = {}
    for _, p in ipairs(pending) do list[#list + 1] = p end
    pending = {}
    if not W.Active() then return end
    local text = Nt.Gather(list)
    if not text then return end
    local now = Now()
    if text == lastText and lastAt and now - lastAt < Nt.REPEAT then stats.repeated = stats.repeated + 1 return end
    lastText, lastAt = text, now
    if not Register() then return end
    local ok = R.Notify.Submit({ kind = Nt.KIND, id = text, ttl = 8, payload = { text = text }, replace = true })
    if ok then stats.submitted = stats.submitted + 1 else stats.refused = stats.refused + 1 end
end

-- Queues one message; a burst within GATHER seconds becomes one card
function Nt.Say(text)
    if not text or not Nt.On() then return false end
    pending[#pending + 1] = text
    stats.gathered = stats.gathered + 1
    if not gathering then
        gathering = true
        C_Timer.After(Nt.GATHER, Flush)
    end
    return true
end
Nt.Flush = Flush   -- (the tests)

---------------------------------------------------------------------------
-- What became ready
---------------------------------------------------------------------------
-- The recipes of the queue whose materials (for all their crafts) are in the bags now: { [id] = name }, and how many recipes are queued
local function ReadyNow()
    local view = S.Stock()
    local have = O.BagCount
    local out, n = {}, 0
    for _, e in ipairs(Q.Entries()) do
        n = n + 1
        if type(e.mats) == "table" and #e.mats > 0 then
            local mats = {}
            for i, m in ipairs(e.mats) do mats[i] = { item = m.item, qty = m.qty * e.crafts } end
            if K2.Craft(mats, have, view).state == "ready" then out[e.id] = e.name end
        end
    end
    return out, n
end

-- The window or the compact view opened: what is ready now is remembered, nothing is said
function Nt.Arm()
    before = ReadyNow()
end

-- What the bags hold changed (a settled bag event while the window or the compact view is shown): says which recipes became ready since the
-- last look. Returns the words, or nil.
function Nt.BagsChanged()
    if before == nil then Nt.Arm() return nil end
    local now, n = ReadyNow()
    local names, all = {}, n > 0
    for id, name in pairs(now) do
        if not before[id] then names[#names + 1] = name end
    end
    for _, e in ipairs(Q.Entries()) do if not now[e.id] then all = false end end
    table.sort(names)
    before = now
    local text = Nt.ReadyText(names, all)
    if text then Nt.Say(text) end
    return text
end

function Nt.Disarm() before = nil end
function Nt.Stop()
    Nt.Disarm()
    pending = {}
    if R.Notify and R.Notify.Cancel then R.Notify.Cancel(Nt.KIND) end
    Dismiss()
end
function Nt.Stats() return { submitted = stats.submitted, refused = stats.refused, gathered = stats.gathered, repeated = stats.repeated, armed = before ~= nil } end

-- a counted craft: said at once (gathered with whatever else just happened)
if W.Progress then
    W.Progress.onCredit = function(info)
        Nt.Say(Nt.CreditText(info))
        if before then before[info.id] = nil end   -- a recipe that was crafted is looked at afresh
    end
end
