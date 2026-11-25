-- TwichUI: Loot Rolls, the rolls themselves
-- Watches the game's group-loot rolls and keeps one record for each, from the moment it starts to the moment the card leaves.
-- It decides nothing and draws nothing (Auto.lua decides, Cards.lua draws); it is the one place that talks to the game about a roll, and
-- the only place a Need, Greed or Pass is sent from, so every choice, the player's or a rule's, goes through the same checks.
--
-- What the client is known to give (docs/loot-rolls-implementation.md has the matrix and what is still unproved):
--   START_LOOT_ROLL(rollID, rollTime in milliseconds, lootHandle)   a roll began; GetLootRollItemInfo / GetLootRollItemLink read it
--   CANCEL_LOOT_ROLL(rollID)                                        the roll is over for you: you rolled, it ran out, or it was cancelled
--   CANCEL_ALL_LOOT_ROLLS, LOOT_ROLLS_COMPLETE(lootHandle)          every roll ended / this drop's rolls are all in
--   CONFIRM_LOOT_ROLL(rollID, rollType, reason)                     the game wants a confirmation (the game's own dialog does that)
--   RollOnLoot(rollID, 0 pass | 1 need | 2 greed), GetLootRollTimeLeft(rollID) in milliseconds, GetActiveLootRollIDs()
--   C_LootHistory (LOOT_HISTORY_UPDATE_DROP): who rolled what, the winner. It names no rollID: a roll is matched to its drop by the
--   item link, and only when exactly one roll could be it.
-- A roll is never assumed to have been placed because a button was pressed: it is "sent" when the call was made and "placed" when
-- the game ended the roll for you (CANCEL_LOOT_ROLL after a send) or the history shows your choice.
--
-- States: pending (you can choose) -> scheduled (a rule's countdown runs; Auto.lua) -> submitted (a choice was sent) -> resolved
-- (the roll is over); or ended (it ran out or was cancelled with no choice). A record holds nothing the game did not say.

local R = TwichUI
local Ru, LR = R.LootRules, R.LootRolls
local Ro = {}
R.LootRoll = Ro

Ro.TYPE = { pass = 0, need = 1, greed = 2 }
Ro.GRACE = 6          -- seconds a sent roll waits for the others after the roll ran out, before it stops waiting
Ro.EXPIRE_MARGIN = 0.4   -- a choice is not sent in the last moments: the game may already be closing the roll
Ro.MAX_RECORDS = 14

local rolls = {}      -- records, oldest first
local seq = 0
local active = false
local frame
local listeners = {}
local retryAt = {}    -- [record key] = number of item-info retries made

local function Now() return GetTime() end
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
    if not ok then return false end
    return true, a, b, c, d, e, f, g, h, i, j, k, l, m, n
end

function Ro.Subscribe(fn) listeners[#listeners + 1] = fn end
local function Tell(kind, roll)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, kind, roll)
        if not ok then R.Fault("loot rolls", err) end
    end
end
Ro.Tell = Tell

function Ro.Rolls() return rolls end
function Ro.Active() return active end

local function IsLive(roll) return roll.state == "pending" or roll.state == "scheduled" or roll.state == "submitted" end
Ro.IsLive = IsLive

-- The newest record for a game roll id (ids come back around in a later drop, so a finished record is only a fallback).
function Ro.Find(rollID)
    local fallback
    for i = #rolls, 1, -1 do
        local r = rolls[i]
        if r.rollID == rollID then
            if IsLive(r) then return r end
            fallback = fallback or r
        end
    end
    return fallback
end

function Ro.ByKey(key)
    for _, r in ipairs(rolls) do if r.key == key then return r end end
end

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------
-- Presentation belongs to this unique roll key, never to an item ID or card slot.
function Ro.DisplayMode(roll)
    return roll.manualDisplay or roll.displayMode or "expanded"
end
function Ro.RefreshDisplay(roll, notify)
    local decision = R.LootRules.DecideDisplay(LR.Active(), roll.obs or {})
    local mode = decision.status == "match" and decision.rule.display or "expanded"
    local ruleId = decision.status == "match" and decision.rule.id or nil
    if roll.displayMode == mode and roll.displayRuleId == ruleId then return end
    roll.displayMode, roll.displayRuleId = mode, ruleId
    if notify then Tell("updated", roll) end
end
function Ro.SetDisplay(roll, mode)
    if not roll or Ro.ByKey(roll.key) ~= roll or (mode ~= "collapsed" and mode ~= "expanded") then return false end
    roll.manualDisplay = mode
    Tell("updated", roll)
    return true
end

-- Seconds left to choose: the game's clock when available, else this record's deadline.
function Ro.Remaining(roll)
    if not (roll and (roll.state == "pending" or roll.state == "scheduled")) then return 0 end
    local ms
    if GetLootRollTimeLeft then
        local ok, left = Call(GetLootRollTimeLeft, roll.rollID)
        left = ok and Plain(left)
        if type(left) == "number" and left >= 0 and left <= (roll.duration or 0) * 1000 + 5000 then ms = left end
    end
    if ms then return ms / 1000 end
    return math.max(0, (roll.deadline or 0) - Now())
end

---------------------------------------------------------------------------
-- What the game says about the item (the facts rules read)
---------------------------------------------------------------------------
local professionNames, professionAt = nil, -100

-- Cache the localized skill names used to match C_Item recipe subclasses.
local function Professions()
    local t = Now()
    if professionNames and t - professionAt < 20 then return professionNames end
    local names, SI = {}, C_SkillInfo
    if SI and SI.GetNumSkillLines and SI.GetSkillLineInfo then
        local n = Plain(SI.GetNumSkillLines())
        if type(n) == "number" then
            for i = 1, n do
                local info = SI.GetSkillLineInfo(i)
                if type(info) == "table" and Plain(info.isHeader) ~= true then
                    local name = Plain(info.name)
                    if type(name) == "string" and name ~= "" then names[name] = true end
                end
            end
        else
            names = nil
        end
    else
        names = nil
    end
    professionNames, professionAt = names, t
    return names
end
function Ro.ForgetProfessions() professionNames = nil end

local function Lines(rollID)
    local TI = C_TooltipInfo
    if not (TI and TI.GetLootRollItem) then return nil end
    local ok, data = Call(TI.GetLootRollItem, rollID)
    if ok and type(data) == "table" and type(data.lines) == "table" then return data.lines, Plain(data.dataInstanceID) end
end

local function HasKnownLine(lines)
    local known = ITEM_SPELL_KNOWN
    if type(known) ~= "string" or known == "" then return nil end
    for _, line in ipairs(lines) do
        local text = Plain(line.leftText)
        if type(text) == "string" and text == known then return true end
    end
    return false
end

local function RecipeFacts(roll, obs, lines)
    if obs.classID == nil then return nil end
    if obs.classID ~= 9 then return { isRecipe = false } end
    local facts = { isRecipe = true }
    local names = Professions()
    local sub = obs.subClassID
    local subclassName = C_Item and C_Item.GetItemSubClassInfo or GetItemSubClassInfo
    if names and type(sub) == "number" then
        local ok, name = Call(subclassName, 9, sub)
        name = ok and Plain(name)
        if type(name) == "string" and name ~= "" then facts.profession = names[name] == true end
    end
    if lines and #lines > 0 then
        facts.known = HasKnownLine(lines)
        local D = R.GearData
        if facts.known == false and D and D.RedLines then facts.canLearn = D.RedLines(lines) == 0 end
        if facts.known == true then facts.canLearn = false end
    end
    return facts
end

-- "Requires Level %d" as a pattern, in the game's own words (nil when it does not say).
local function LevelPattern()
    local text = ITEM_MIN_LEVEL
    if type(text) ~= "string" or not text:find("%%d") then return nil end
    return "^" .. text:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%d", "%%d+") .. "$"
end

-- Can the player equip it now? Gear (anything with a slot) whose tooltip has no red line: red is the game saying class, armor type, weapon
-- skill or a reputation stands in the way. A red level requirement is not counted, since it fixes itself. nil while the item or its tooltip
-- is not there yet, or when the tooltip cannot be judged.
local function EquippableFact(obs, lines)
    local loc = obs.equipLoc
    if obs.classID == nil or type(loc) ~= "string" then return nil end
    if loc == "" or loc == "INVTYPE_NON_EQUIP" then return false end
    local D = R.GearData
    if not (lines and D and D.RedLines) then return nil end
    local level, kept = LevelPattern(), {}
    for _, line in ipairs(lines) do
        local text = Plain(line.leftText)
        if not (level and type(text) == "string" and text:find(level)) then kept[#kept + 1] = line end
    end
    local ok, red = Call(D.RedLines, kept)
    if not ok or type(red) ~= "number" then return nil end
    return red == 0
end

local function UpgradeFact(link, lines)
    local H = R.GearHints
    if not (H and H.Judge and link and lines) then return nil end
    local ok, judged = Call(H.Judge, link, lines)
    if not ok or judged == nil then return nil end
    if judged == false then return false end
    local noteworthy = H.Noteworthy and select(2, Call(H.Noteworthy, judged))
    return noteworthy == true, judged   -- the judgement too: the card's hover explains it
end

local function ContextFacts()
    local x = {}
    if IsInInstance then
        local ok, inside, kind = Call(IsInInstance)
        kind = ok and Plain(kind)
        if type(kind) == "string" then x.instanceType = kind end
    end
    if IsInRaid then
        local ok, raid = Call(IsInRaid)
        if ok then x.inRaidGroup = Plain(raid) == true end
    end
    if x.instanceType == nil then return nil end
    return x
end

-- Reads the game again for one roll and fills the record. Returns true when the item itself is known (name and class).
function Ro.Observe(roll)
    local id = roll.rollID
    if GetLootRollItemInfo then
        local ok, texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, _, _, canTransmog = Call(GetLootRollItemInfo, id)
        if ok then
            name = Plain(name)
            if type(name) == "string" and name ~= "" then
                roll.name, roll.icon, roll.count = name, Plain(texture), tonumber(Plain(count)) or 1
                roll.quality = Plain(quality)
                roll.bop = Plain(bop) == true
                roll.canNeed, roll.canGreed = Plain(canNeed) == true, Plain(canGreed) == true
                roll.reasonNeed, roll.reasonGreed = Plain(reasonNeed), Plain(reasonGreed)
                roll.canTransmog = Plain(canTransmog) == true
            end
        end
    end
    if GetLootRollItemLink then
        local ok, link = Call(GetLootRollItemLink, id)
        link = ok and Plain(link)
        if type(link) == "string" and link ~= "" then roll.link = link end
    end
    local obs = roll.obs or {}
    roll.obs = obs
    obs.link, obs.name, obs.quality = roll.link, roll.name, roll.quality
    if roll.link then
        local I = C_Item
        if I and I.GetItemInfoInstant then
            local ok, itemID, _, _, equipLoc, icon, classID, subClassID = Call(I.GetItemInfoInstant, roll.link)
            if ok and type(Plain(itemID)) == "number" then
                obs.itemID, obs.equipLoc, obs.classID, obs.subClassID = itemID, equipLoc, classID, subClassID
                roll.icon = roll.icon or Plain(icon)
            end
        end
        if I and I.GetItemInfo then
            local ok, name, _, quality, _, _, typeName, subType, _, equipLoc, _, sellPrice, classID, subClassID, bindType = Call(I.GetItemInfo, roll.link)
            if ok and type(Plain(name)) == "string" then
                -- Match the quality shown on this loot roll; the item lookup is only a fallback.
                obs.quality = obs.quality or Plain(quality)
                obs.equipLoc = Plain(equipLoc) or obs.equipLoc
                obs.classID, obs.subClassID = Plain(classID) or obs.classID, Plain(subClassID) or obs.subClassID
                obs.bindType = Plain(bindType)
                roll.typeText, roll.subTypeText = Plain(typeName), Plain(subType)
                roll.sellPrice = tonumber(Plain(sellPrice))
                roll.itemKnown = true
            end
        end
    end
    local lines, tooltipDataID = Lines(id)
    roll.tooltipDataID = tooltipDataID
    obs.recipe = RecipeFacts(roll, obs, lines)
    obs.equippable = EquippableFact(obs, lines)
    obs.upgrade, roll.judged = UpgradeFact(roll.link, lines)
    roll.upgrade = obs.upgrade
    obs.context = ContextFacts()
    obs.ready = roll.itemKnown == true
    Ro.RefreshDisplay(roll)
    return obs.ready
end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------
-- Whether a choice can be sent now, and if not, why (words for a tooltip).
function Ro.CanChoose(roll, choice)
    if not roll or roll.victoryOwned or not IsLive(roll) then return false, "This roll is over." end
    if roll.state == "submitted" then return false, "You have already chosen." end
    if choice == "need" then
        if not roll.canNeed then
            local why = roll.reasonNeed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonNeed)]
            return false, (type(why) == "string" and why) or "You can't roll Need on this."
        end
    elseif choice == "greed" then
        if not roll.canGreed then
            local why = roll.reasonGreed and _G["LOOT_ROLL_INELIGIBLE_REASON" .. tostring(roll.reasonGreed)]
            return false, (type(why) == "string" and why) or "You can't roll Greed on this."
        end
    elseif choice ~= "pass" then
        return false, "Choose Need, Greed or Pass."
    end
    if Ro.Remaining(roll) <= Ro.EXPIRE_MARGIN then return false, "Out of time." end
    return true
end

-- The one way a choice is sent. source: "player" or "auto". Never sends twice for a roll (a send that needs the game's confirmation
-- may be sent again, since nothing was placed). Returns ok, reason.
function Ro.Submit(roll, choice, source)
    if type(RollOnLoot) ~= "function" then return false, "This client has no way to roll." end
    local ok, why = Ro.CanChoose(roll, choice)
    if not ok then return false, why end
    if roll.sending then return false, "Already sending." end
    roll.sending = true
    roll.choice, roll.source, roll.sentAt = choice, source or "player", Now()
    roll.needsConfirm = nil
    local was = roll.state
    roll.state = "submitted"
    local called, err = pcall(RollOnLoot, roll.rollID, Ro.TYPE[choice])
    roll.sending = nil
    if not called then
        roll.state, roll.choice, roll.sentAt, roll.source = was, nil, nil, nil
        R.Life.Note("loot-send-failed")
        Tell("updated", roll)
        return false, "The game refused the roll."
    end
    if roll.needsConfirm then
        -- the game is asking first: nothing is placed until the player agrees in its own dialog, so the card stays open
        -- (a countdown that sent it is over, and is not started again: the player takes it from here)
        roll.state = "pending"
        roll.auto = nil
        roll.sentAt = nil
        if roll.source == "auto" then roll.autoStopped = true end
    elseif roll.state == "submitted" then
        roll.auto = nil
    end
    R.Life.Note(roll.source == "auto" and "loot-sent-auto" or "loot-sent-player")
    Tell("updated", roll)
    return true
end

---------------------------------------------------------------------------
-- Results (C_LootHistory). The history names no roll id, so a drop is attached to a roll only when one roll fits it.
---------------------------------------------------------------------------
local STATE_WORD = { [0] = "need", "need", "transmog", "greed", "none", "pass" }   -- Enum.EncounterLootDropRollState

local function ReadDrop(encounterID, key)
    local H = C_LootHistory
    if not (H and H.GetSortedInfoForDrop) then return nil end
    local ok, info = Call(H.GetSortedInfoForDrop, encounterID, key)
    if ok and type(info) == "table" then return info end
end

local function Result(info)
    local res = { rolls = {}, allPassed = info.allPassed == true, tied = info.isTied == true }
    for _, r in ipairs(type(info.rollInfos) == "table" and info.rollInfos or {}) do
        local name = Plain(r.playerName)
        if type(name) == "string" then
            local entry = { name = name, class = Plain(r.playerClass), self = r.isSelf == true,
                choice = STATE_WORD[Plain(r.state) or 4] or "none", roll = tonumber(Plain(r.roll)), winner = r.isWinner == true }
            res.rolls[#res.rolls + 1] = entry
            if entry.winner then res.winner = entry end
        end
    end
    if not res.winner and type(info.winner) == "table" then
        local name = Plain(info.winner.playerName)
        if type(name) == "string" then
            res.winner = { name = name, class = Plain(info.winner.playerClass), self = info.winner.isSelf == true,
                choice = STATE_WORD[Plain(info.winner.state) or 4] or "none", roll = tonumber(Plain(info.winner.roll)), winner = true }
        end
    end
    table.sort(res.rolls, function(a, b)
        local ra, rb = a.roll or -1, b.roll or -1
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)
    res.mine = Plain(info.playerRollState)
    return res
end

local MAX_RESULT_ROWS = 10

-- A drop changed (or is being looked for): attach it to the one roll it can be and copy what it says.
local function Absorb(encounterID, key, info)
    info = info or ReadDrop(encounterID, key)
    if not info then return end
    local link = Plain(info.itemHyperlink)
    if type(link) ~= "string" then return end
    local target
    for _, r in ipairs(rolls) do
        if r.hist and r.hist.encounterID == encounterID and r.hist.key == key then target = r break end
    end
    if not target then
        local fits = {}
        for _, r in ipairs(rolls) do
            if not r.hist and r.link == link and r.state ~= "ended" then fits[#fits + 1] = r end
        end
        -- a second drop of the same item is told apart only when the others have been matched already: never guessed
        if #fits ~= 1 then
            if #fits > 1 then R.Life.Note("loot-history-ambiguous") end
            return
        end
        target = fits[1]
        target.hist = { encounterID = encounterID, key = key }
    end
    local res = Result(info)
    while #res.rolls > MAX_RESULT_ROWS do table.remove(res.rolls) end
    target.result = res
    if target.state == "submitted" and res.mine and STATE_WORD[res.mine] == target.choice then target.placed = true end
    if target.state == "submitted" and (res.winner or res.allPassed) and target.placed then
        Ro.Resolve(target, "history")
    end
    Tell("updated", target)
end

-- Looks over the drops the history already holds for a roll that has none yet (the drop may be recorded before the roll starts).
local function Scan(roll)
    local H = C_LootHistory
    if not (H and H.GetAllEncounterInfos and H.GetSortedDropsForEncounter) or not roll.link then return end
    local ok, infos = Call(H.GetAllEncounterInfos)
    if not ok or type(infos) ~= "table" then return end
    for i = 1, math.min(#infos, 3) do
        local enc = infos[i]
        local id = type(enc) == "table" and Plain(enc.encounterID)
        if id then
            local ok2, drops = Call(H.GetSortedDropsForEncounter, id)
            if ok2 and type(drops) == "table" then
                for _, drop in ipairs(drops) do
                    local key = Plain(drop.lootListKey)
                    local taken = false
                    for _, r in ipairs(rolls) do
                        if r.hist and r.hist.encounterID == id and r.hist.key == key then taken = true end
                    end
                    -- a drop that already has its outcome belongs to an earlier roll of the same item
                    local open = not drop.winner and drop.allPassed ~= true
                    if not taken and open and key and Plain(drop.itemHyperlink) == roll.link then Absorb(id, key, drop) end
                    if roll.hist then return end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Ending
---------------------------------------------------------------------------
local function Schedule(roll, delay)
    roll.removeAt = Now() + delay
end

local function LingerFor(roll)
    if roll.state == "resolved" then
        if roll.choice and roll.showResult ~= false then return LR.Get("afterResult") end
        return 2
    end
    return 3
end

function Ro.Resolve(roll, why)
    if roll.state == "resolved" or roll.state == "ended" then return end
    roll.state, roll.endReason, roll.endedAt = "resolved", why or "complete", Now()
    roll.auto = nil
    Schedule(roll, LingerFor(roll))
    Tell("updated", roll)
end

function Ro.End(roll, why)
    if roll.state == "resolved" or roll.state == "ended" then return end
    if roll.state == "submitted" then return Ro.Resolve(roll, why) end
    roll.state, roll.endReason, roll.endedAt = "ended", why or "canceled", Now()
    roll.auto = nil
    Schedule(roll, LingerFor(roll))
    Tell("updated", roll)
end

local function Remove(roll)
    for i, r in ipairs(rolls) do
        if r == roll then
            table.remove(rolls, i)
            retryAt[roll.key] = nil
            Tell("removed", roll)
            return
        end
    end
end
Ro.Remove = Remove

-- Called by Cards (when it is about to let a card go) and by the timer below.
function Ro.Prune()
    local now = Now()
    for i = #rolls, 1, -1 do
        local r = rolls[i]
        if r.removeAt and now >= r.removeAt then Remove(r) end
        -- a sent roll waits only so long for results the game may never give
        if r.state == "submitted" and r.deadline and now > r.deadline + Ro.GRACE then Ro.Resolve(r, "timeout") end
    end
    while #rolls > Ro.MAX_RECORDS do
        local oldest
        for _, r in ipairs(rolls) do if not IsLive(r) then oldest = r break end end
        if not oldest then break end
        Remove(oldest)
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- One slow timer, only while there are records: it lets finished cards go and stops a sent roll waiting for results for ever.
local pruner
local function Pulse()
    pruner = nil
    if not active then return end
    Ro.Prune()
    if #rolls > 0 then pruner = C_Timer.NewTimer(1, Pulse) end
end
local function EnsurePulse()
    if active and not pruner and #rolls > 0 then pruner = C_Timer.NewTimer(1, Pulse) end
end

local function Begin(rollID, ms, handle)
    seq = seq + 1
    local now = Now()
    local duration = (tonumber(ms) or 0) / 1000
    local roll = {
        key = seq, rollID = rollID, handle = handle, started = now, duration = duration, deadline = now + duration,
        state = "pending", obs = {},
    }
    rolls[#rolls + 1] = roll
    Ro.Observe(roll)
    Scan(roll)
    Tell("added", roll)
    if not roll.obs.ready then retryAt[roll.key] = 0 end
    EnsurePulse()
    return roll
end

function Ro.OnStart(rollID, ms, handle)
    if type(rollID) ~= "number" then return end
    local existing = Ro.Find(rollID)
    if existing and IsLive(existing) then
        -- a repeated event for the roll already shown: nothing new (a reused id with another item is a new roll)
        local was = existing.link
        Ro.Observe(existing)
        if was and existing.link and was ~= existing.link then
            Ro.End(existing, "replaced")
        else
            return existing
        end
    end
    return Begin(rollID, ms, Plain(handle))
end

function Ro.OnCancel(rollID)
    local roll = Ro.Find(rollID)
    if not roll or not IsLive(roll) then return end
    if roll.state == "submitted" then
        roll.placed = true   -- the game closed the roll for a player who had sent a choice: it is in
        Tell("updated", roll)
        return
    end
    local left = roll.deadline - Now()
    Ro.End(roll, left <= 1.5 and "expired" or "canceled")
end

function Ro.OnCancelAll()
    for _, r in ipairs({ unpack(rolls) }) do
        if IsLive(r) then
            if r.state == "submitted" then r.placed = true; Ro.Resolve(r, "complete") else Ro.End(r, "canceled") end
        end
    end
end

function Ro.OnComplete(handle)
    if handle == nil then return end
    for _, r in ipairs({ unpack(rolls) }) do
        if r.handle == handle and IsLive(r) then
            if r.state == "submitted" then Ro.Resolve(r, "complete") else Ro.End(r, "complete") end
        end
    end
end

function Ro.OnConfirm(rollID, rollType)
    local roll = Ro.Find(rollID)
    if not roll or not IsLive(roll) then return end
    roll.needsConfirm = tonumber(rollType) or true
    Tell("updated", roll)
end

local function RefreshFacts(r)
    Ro.Observe(r)
    Scan(r)
    Tell("updated", r)
end

local function IsRecipe(r)
    return r.obs and r.obs.recipe and r.obs.recipe.isRecipe == true
end

-- Recipe tooltip/skill facts can arrive after the basic item is already ready.
-- Event-driven refreshes are limited to open choices, and a tooltip's own roll when known.
local function RefreshRecipes(dataID)
    for _, r in ipairs(rolls) do
        if (r.state == "pending" or r.state == "scheduled") and IsRecipe(r)
            and (dataID == nil or r.tooltipDataID == nil or r.tooltipDataID == dataID) then
            RefreshFacts(r)
        end
    end
end

-- Item data arrives late: read incomplete items a few times, plus open recipe facts.
local function Retry()
    RefreshRecipes()
    for _, r in ipairs(rolls) do
        if IsLive(r) and not r.obs.ready and not IsRecipe(r) then
            local n = (retryAt[r.key] or 0) + 1
            retryAt[r.key] = n
            if n <= 6 then
                RefreshFacts(r)
            end
        end
    end
end

local function OnEvent(_, event, a, b, c)
    if event == "START_LOOT_ROLL" then Ro.OnStart(a, b, c)
    elseif event == "CANCEL_LOOT_ROLL" then Ro.OnCancel(a)
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then Ro.OnCancelAll()
    elseif event == "LOOT_ROLLS_COMPLETE" then Ro.OnComplete(a)
    elseif event == "CONFIRM_LOOT_ROLL" then Ro.OnConfirm(a, b)
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then Absorb(a, b)
    elseif event == "GET_ITEM_INFO_RECEIVED" then Retry()
    elseif event == "TOOLTIP_DATA_UPDATE" then RefreshRecipes(Plain(a))
    elseif event == "SKILL_LINES_CHANGED" then Ro.ForgetProfessions(); RefreshRecipes()
    elseif event == "PLAYER_ENTERING_WORLD" then Ro.Adopt() end
end

local EVENTS = { "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "LOOT_ROLLS_COMPLETE", "CONFIRM_LOOT_ROLL",
    "LOOT_HISTORY_UPDATE_DROP", "GET_ITEM_INFO_RECEIVED", "TOOLTIP_DATA_UPDATE", "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }
Ro.EVENTS = EVENTS

-- Rolls already open when this starts (a reload, or the feature switched on mid-roll): taken in as they are, with the time they have left.
function Ro.Adopt()
    if not (active and GetActiveLootRollIDs) then return end
    local ok, ids = Call(GetActiveLootRollIDs)
    if not ok or type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        local known = Ro.Find(id)
        if not (known and IsLive(known)) then
            local left = GetLootRollTimeLeft and select(2, Call(GetLootRollTimeLeft, id))
            left = Plain(left)
            if type(left) == "number" and left > 0 then Begin(id, left, nil) end
        end
    end
end

function Ro.Enable()
    if active then return end
    active = true
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", R.Perf.Wrap("loot.event", function(self, event, ...) OnEvent(self, event, ...) end))
    end
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    Ro.Adopt()
end

-- Stops listening and forgets every record (the cards go with them). Nothing is sent or cancelled in the game.
function Ro.Disable()
    if not active then return end
    active = false
    if frame then frame:UnregisterAllEvents() end
    if pruner then pruner:Cancel(); pruner = nil end
    for i = #rolls, 1, -1 do local r = rolls[i]; rolls[i] = nil; Tell("removed", r) end
    wipe(retryAt)
end

function Ro.Listening() return frame ~= nil and active end
function Ro.EventCount() local n = 0 if active then n = #EVENTS end return n end

-- Display-only rules work with automation off/paused and never touch a countdown.
LR.Subscribe(function(what)
    if what ~= "rules" and what ~= "profile" then return end
    for _, roll in ipairs({ unpack(rolls) }) do
        if IsLive(roll) then Ro.RefreshDisplay(roll, true) end
    end
end)
