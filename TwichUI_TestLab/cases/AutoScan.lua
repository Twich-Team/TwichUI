-- TwichUI Test Lab: the automatic price update probes (market data foundation 2.0, milestone A6; docs/testlab.md "Automatic price update probes").
-- OPT-IN and guided. These cases answer, in the real client, what the UI source does not say: may an addon make the whole-house request
-- (C_AuctionHouse.ReplicateItems) from an event handler without a click, or only from one; how long until the listings arrive; what the
-- throttle does; whether the player's own search right afterwards is delayed; whether an item's owner is filled in; what the client says about
-- buying stacks whole or in part. THE OUTCOME IS UNKNOWN until the owner runs them: nothing here proves the capability, and the Workshop
-- keeps asking for a click until R.WorkshopAuto.CAPABILITY is set from these results (WorkshopAuto.lua).
--
--   autoscan.state          (read only) the setting, the capability gate, the API, the throttle, the market this auction house is
--   autoscan.event.open     (guided) arm, then close and reopen the auction house: ONE request is made from the opening event handler, no click
--   autoscan.click.request  (guided) one request from a click on a Lab button, then (optionally) your own search straight after it
--   autoscan.market.identity (read only, auction house open) the market key and side the Workshop would use
--
-- SAFETY: the one request is made ONLY when the game says its message system is ready, at most ONCE per case, in one function (RequestOnce).
-- Nothing is retried, no click or event is simulated, nothing is bought, bid, posted or cancelled, and no saved data is touched (the Lab's own
-- saved-data fingerprint covers the Workshop's). A request the client refuses is RECORDED, not worked around. Only counts are kept: an
-- owner's name is never read into a fact (only whether the field is filled in), and no listing is stored. Run each case on its own.

local R = TwichUI
local TL = R.TestLab
local G, P = TL.Guided, TL.Probe

TL.Category{ id = "autoscan", label = "Automatic price update probes (opt-in)", guided = true, manual = true,
    blurb = "asks the real client whether the whole-house request is accepted without a click; run each case on its own, at an auction house, out of combat" }

local WAIT_FIRST = 90        -- seconds to wait for the first listing update after an accepted request
local ARM_WAIT = 45          -- seconds the event case waits for you to reopen the auction house
local QUIET = 2              -- seconds without an update before the listings are counted
local MAX_SAMPLE = 600       -- records inspected (counts only)
local AUCTIONEER = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer) or 21

local function Now() return TL.Runner.Now() end
local function Combat() return InCombatLockdown and InCombatLockdown() and true or false end
local function AHOpen()
    local f = AuctionHouseFrame
    return type(f) == "table" and f.IsShown ~= nil and f:IsShown() == true
end
local function Ready()
    local AH = C_AuctionHouse
    if not (AH and AH.IsThrottledMessageSystemReady) then return nil end
    local ok, v = pcall(AH.IsThrottledMessageSystemReady)
    return ok and v == true or false
end
local function Short(v) return tostring(v):sub(1, 120) end

local EVENTS = { "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }

-- One recorder for a case: every event with its time (counts and times only)
local function Recorder(role)
    local rec = { at = nil, updates = 0, sent = 0, dropped = 0, ready = 0, closed = 0, forbidden = 0, blocked = 0, searchSent = nil, searchResult = nil,
        firstUpdate = nil, lastUpdate = nil, readyAgain = nil, hook = nil }
    local f = P.Get(role, "Frame")
    if not f then return nil, "the Lab could not make its listener frame" end
    function rec.OnEvent(event)
        local now = Now()
        if event == "REPLICATE_ITEM_LIST_UPDATE" then
            if rec.requestAt then
                rec.updates = rec.updates + 1; rec.lastUpdate = now
                rec.firstUpdate = rec.firstUpdate or now
            end
        elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" then
            rec.sent = rec.sent + 1
            if rec.requestAt and now > rec.requestAt + 0.05 and not rec.searchSent then rec.searchSent = now end   -- a later request than ours: the player's search
        elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then rec.dropped = rec.dropped + 1
        elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            rec.ready = rec.ready + 1
            if rec.requestAt and not rec.readyAgain then rec.readyAgain = now end
        elseif event == "AUCTION_HOUSE_CLOSED" then rec.closed = rec.closed + 1
        elseif event == "ADDON_ACTION_FORBIDDEN" then rec.forbidden = rec.forbidden + 1
        elseif event == "ADDON_ACTION_BLOCKED" then rec.blocked = rec.blocked + 1
        elseif rec.searchSent and not rec.searchResult then rec.searchResult = now end   -- the first search answer after the player's search was sent
    end
    for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, event) rec.OnEvent(event) end)
    rec.frame = f
    return rec
end

local function Disarm(rec) if rec and rec.frame then pcall(rec.frame.UnregisterAllEvents, rec.frame) end end

-- THE ONE PLACE the whole-house request is made. Only when the game says the message system is ready (never forced, never repeated), out of
-- combat, with the auction house open. A refusal (no API, not ready, an error) is recorded and the request is not made again.
local function RequestOnce(rec, via)
    if rec.requested then return false end
    rec.requested, rec.via = true, via
    local AH = C_AuctionHouse
    if not (AH and AH.ReplicateItems) then rec.refused = "no API"; return false end
    if Combat() then rec.refused = "combat"; return false end
    if not AHOpen() then rec.refused = "auction house not open"; return false end
    local ready = Ready()
    rec.readyBefore = ready
    if ready ~= true then rec.refused = "the throttle was not ready"; return false end
    rec.requestAt = Now()
    local ok, err = pcall(AH.ReplicateItems)
    rec.returned = ok
    if not ok then rec.refused = "raised: " .. Short(err); rec.requestAt = nil; return false end
    rec.readyAfter = Ready()
    return true
end

-- After a request: wait for the first listing update, then for quiet, then count (never store) what the listings show
local function Observe(t, rec)
    local deadline = Now() + WAIT_FIRST
    while Now() < deadline and not rec.firstUpdate do
        if rec.closed > 0 or rec.forbidden > 0 or rec.blocked > 0 or rec.dropped > 0 then break end
        t:Progress(("waiting for the listings (%d s)"):format(math.floor(Now() - rec.requestAt)))
        t:Wait(0.25)
    end
    if rec.firstUpdate then
        -- quiet: no update for QUIET seconds (bounded)
        local limit = Now() + 12
        while Now() < limit and Now() - rec.lastUpdate < QUIET do t:Progress("receiving listings"); t:Wait(0.25) end
    end
    -- the throttle: how long until the game says ready again (reported, never used to ask a second time)
    local readyLimit = Now() + 10
    while Now() < readyLimit and Ready() ~= true do t:Wait(0.25) end
end

local function Report(t, tag, rec)
    local function ms(a, b) return (a and b) and ("%.0f"):format((a - b) * 1000) or "n/a" end
    t:Fact(tag .. ".via", rec.via)
    t:Fact(tag .. ".request_made", rec.requestAt ~= nil)
    t:Fact(tag .. ".refused", rec.refused or "no")
    t:Fact(tag .. ".ready_before", rec.readyBefore); t:Fact(tag .. ".ready_after_request", rec.readyAfter)
    t:Fact(tag .. ".call_returned_without_error", rec.returned)
    t:Fact(tag .. ".first_update_ms", ms(rec.firstUpdate, rec.requestAt))
    t:Fact(tag .. ".updates", rec.updates)
    t:Fact(tag .. ".ready_event_ms_after_request", ms(rec.readyAgain, rec.requestAt))
    t:Fact(tag .. ".message_sent_events", rec.sent); t:Fact(tag .. ".dropped_events", rec.dropped)
    t:Fact(tag .. ".action_forbidden_events", rec.forbidden); t:Fact(tag .. ".action_blocked_events", rec.blocked)
    t:Fact(tag .. ".closed_during", rec.closed)
    if rec.searchSent then
        t:Fact(tag .. ".search_sent_ms_after_request", ms(rec.searchSent, rec.requestAt))
        t:Fact(tag .. ".search_answer_ms_after_sent", ms(rec.searchResult, rec.searchSent))
    else
        t:Fact(tag .. ".search_sent_ms_after_request", "no search was made")
    end
    local verdict
    if not rec.requestAt then verdict = "NOT TESTED: no request was made (" .. tostring(rec.refused) .. ")"
    elseif rec.firstUpdate then verdict = "ACCEPTED: the listings began to arrive after the request"
    elseif rec.forbidden + rec.blocked > 0 then verdict = "BLOCKED: the client reported a blocked action"
    elseif rec.dropped > 0 then verdict = "DROPPED: the auction house turned the request down (throttle)"
    else verdict = "NO ANSWER within " .. WAIT_FIRST .. " s: not accepted, or the window closed, or the server did not answer" end
    t:Fact(tag .. ".verdict", verdict)
    return verdict
end

-- What the listings look like (counts only; no name is read into a fact, no listing is kept)
local function Count(t, tag)
    local AH = C_AuctionHouse
    if not (AH and AH.GetNumReplicateItems and AH.GetReplicateItemInfo) then return end
    local ok, n = pcall(AH.GetNumReplicateItems)
    if not (ok and type(n) == "number") then return end
    t:Fact(tag .. ".listings", n)
    local seen, owner, stacks, partial, sampleKeys = math.min(n, MAX_SAMPLE), 0, 0, 0, {}
    for i = 0, seen - 1 do
        local good, _, _, count, _, _, _, _, _, _, buyout, _, _, _, ownerName, _, _, itemID, hasAll = pcall(AH.GetReplicateItemInfo, i)
        if good then
            if type(ownerName) == "string" and ownerName ~= "" then owner = owner + 1 end
            if type(count) == "number" and count > 1 then stacks = stacks + 1 end
            if hasAll == false then partial = partial + 1 end
            if type(itemID) == "number" and type(count) == "number" and count > 1 and #sampleKeys < 5 then sampleKeys[#sampleKeys + 1] = itemID end
        end
    end
    t:Fact(tag .. ".inspected", seen)
    t:Fact(tag .. ".owner_filled_in", ("%d of %d"):format(owner, seen))
    t:Fact(tag .. ".stacks_over_one", ("%d of %d"):format(stacks, seen))
    t:Fact(tag .. ".without_all_info", ("%d of %d"):format(partial, seen))
    -- what the client says of buying stackable items: a commodity buys by quantity (partial stacks possible), an item by whole auction
    if AH.GetItemCommodityStatus then
        local out = {}
        for _, id in ipairs(sampleKeys) do
            local good, status = pcall(AH.GetItemCommodityStatus, { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
            out[#out + 1] = good and tostring(status) or "error"
        end
        t:Fact(tag .. ".commodity_status_of_stackables", #out > 0 and table.concat(out, ",") or "none sampled")
        t:Note("commodity status: Enum.ItemCommodityStatus (0 Unknown, 1 Item, 2 Commodity); a commodity is bought by quantity, an item by whole auction.")
    else
        t:Fact(tag .. ".commodity_status_of_stackables", "API absent")
    end
end

local function PromptStillOpen(t)
    local status = G.Status()
    if status == "skipped" then t:Skip("you skipped this step") end
    if status == "idle" then t:Skip("the request was closed") end
end

---------------------------------------------------------------------------
-- Read only
---------------------------------------------------------------------------
TL.Case{ id = "autoscan.state", cat = "autoscan", class = "readonly", budget = 4,
  about = "What the Workshop would do on opening the auction house, and what the client offers. Reads only.", run = function(t)
    local WA = R.WorkshopAuto
    t:Check(WA ~= nil, "the core detector exists")
    if not WA then return end
    local s = WA.Snapshot()
    t:Fact("autoscan.setting_on", s.enabled); t:Fact("autoscan.capability", s.capability)
    t:Fact("autoscan.visits", s.visits); t:Fact("autoscan.workshop_loads", s.loads); t:Fact("autoscan.started", s.started)
    t:Fact("autoscan.last_skip", s.skipped or "none"); t:Fact("autoscan.last_decision", s.last or "none")
    local AH = C_AuctionHouse
    for _, name in ipairs({ "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo", "IsThrottledMessageSystemReady", "GetItemCommodityStatus" }) do
        t:Fact("autoscan.api." .. name, type(AH) == "table" and type(AH[name]) or "no C_AuctionHouse")
    end
    t:Fact("autoscan.auction_house_open", AHOpen()); t:Fact("autoscan.throttle_ready", Ready())
    t:Fact("autoscan.in_combat", Combat())
    local W = R.Workshop
    if W and W.Auto then
        local a = W.Auto.Snapshot()
        t:Fact("autoscan.workshop.last_visit_action", ("%s %s"):format(tostring(a.action), tostring(a.why)))
        t:Fact("autoscan.workshop.backed_off_markets", a.backedOff)
    else
        t:Note("The Workshop is not loaded (it loads on the first Auction House visit that needs it, or when opened).")
    end
    t:Note("capability 'unknown' means: no automatic request is ever made; a due update is offered as one click. Set it from autoscan.event.open's verdict.")
end }

TL.Case{ id = "autoscan.market.identity", cat = "autoscan", class = "readonly", needs = { "workshop" }, budget = 4,
  about = "With an auction house open: the market key (realm and the auctioneer's side) the Workshop would use. Reads only.", run = function(t)
    if not AHOpen() then return t:Skip("open an auction house first") end
    local SC, PR = t.W.Scan, t.W.Prices
    local key, realm, side = SC.Market()
    t:Fact("autoscan.market.key", key); t:Fact("autoscan.market.realm", realm); t:Fact("autoscan.market.side", side)
    t:Check(type(key) == "string" and key:find("|", 1, true) ~= nil, "a market key was built")
    local info = key and PR.Market(key) or nil
    t:Fact("autoscan.market.saved", info ~= nil)
    t:Fact("autoscan.market.saved_age_minutes", info and info.at and ("%.0f"):format((time() - info.at) / 60) or "n/a")
    if side == "unknown" then t:Note("the game gave no side for the auctioneer: this is a market of its own ('unknown'); neutral and faction houses must not share a cooldown") end
end }

---------------------------------------------------------------------------
-- Guided
---------------------------------------------------------------------------
TL.Case{ id = "autoscan.event.open", cat = "autoscan", class = "guided", budget = 150,
  about = "Is the whole-house request accepted from the opening event, with no click? Arms a listener, you close and reopen the auction house, and ONE request is made from that event.", run = function(t)
    if Combat() then return t:Skip("not during combat") end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return t:Skip("this client has no whole-house request") end
    if Ready() ~= true then return t:Skip("the auction house's request system is not ready: wait a minute and run this case again") end
    local rec, why = Recorder("autoscan.listen")
    if not rec then return t:Skip(why) end
    local armed = true
    -- the opening event itself: the request is made inside this handler, nowhere else
    local opener = P.Get("autoscan.open", "Frame")
    if not opener then return t:Skip("the Lab could not make its second listener frame") end
    pcall(opener.RegisterEvent, opener, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    pcall(opener.RegisterEvent, opener, "AUCTION_HOUSE_SHOW")
    opener:SetScript("OnEvent", function(_, event, kind)
        if not armed then return end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and kind ~= AUCTIONEER then return end
        armed = false
        rec.openedBy = event
        -- the window may not be shown yet when the first event arrives: the request needs it, so wait for the next frame's look, bounded
        if AHOpen() then RequestOnce(rec, "event " .. event) else rec.pendingEvent = event end
    end)
    local ok, whyNot = G.Begin({ mode = "click", title = "Automatic update probe: opening the auction house",
        lines = { "Close the auction house window now (talk to the auctioneer again afterwards).", "Open it again within " .. ARM_WAIT .. " seconds. The Lab then makes ONE request from that opening, with no click, and watches what the game does.",
            "Do not search or click anything until the status line says it is done. Nothing is bought, bid, posted or changed." } })
    if not ok then return t:Skip(whyNot) end
    local deadline = Now() + ARM_WAIT
    while Now() < deadline and not rec.requested do
        PromptStillOpen(t)
        if rec.pendingEvent and AHOpen() then RequestOnce(rec, "event " .. rec.pendingEvent); break end
        if Combat() then Disarm(rec); return t:Skip("combat started") end
        t:Progress(("waiting for you to reopen the auction house (%d s)"):format(math.max(0, math.floor(deadline - Now()))))
        t:Wait(0.25)
    end
    if not rec.requested then return t:Skip("the auction house was not reopened in time") end
    G.Say("Request made from the opening event. Waiting for the game...")
    if rec.requestAt then Observe(t, rec) end
    Count(t, "autoscan.event")
    Disarm(rec)
    local verdict = Report(t, "autoscan.event", rec)
    G.Say(verdict)
    t:Note("verdict: " .. verdict)
    t:Note("If ACCEPTED, the owner may set R.WorkshopAuto.CAPABILITY = \"supported\" (WorkshopAuto.lua) to start updates on opening. Otherwise leave it, or set \"click\".")
end }

TL.Case{ id = "autoscan.click.request", cat = "autoscan", class = "guided", budget = 150,
  about = "Is the whole-house request accepted from a click? One click on a Lab button makes ONE request; optionally search for something straight after to see whether your search is delayed.", run = function(t)
    if Combat() then return t:Skip("not during combat") end
    if not AHOpen() then return t:Skip("open an auction house first") end
    if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return t:Skip("this client has no whole-house request") end
    if Ready() ~= true then return t:Skip("the auction house's request system is not ready: wait a minute and run this case again") end
    local rec, why = Recorder("autoscan.listen")
    if not rec then return t:Skip(why) end
    local btn = P.Get("autoscan.click", "Button")
    if not btn then return t:Skip("the Lab could not make its test button") end
    btn:SetSize(260, 36)
    btn:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    pcall(btn.SetFrameStrata, btn, "FULLSCREEN_DIALOG")
    if not btn.bg then
        btn.bg = btn:CreateTexture(nil, "BACKGROUND"); btn.bg:SetAllPoints(); btn.bg:SetColorTexture(0.1, 0.1, 0.1, 0.92)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal"); btn.label:SetPoint("CENTER")
    end
    btn.label:SetText("Request listings (Lab test)")
    btn:SetScript("OnClick", function() RequestOnce(rec, "click") end)
    btn:Show()
    local ok, whyNot = G.Begin({ mode = "click", title = "Automatic update probe: a click",
        lines = { "Click the button \"Request listings (Lab test)\" once.", "OPTIONAL, straight after clicking: search for any item in the auction house's own search box. The Lab records whether it was delayed.",
            "Nothing is bought, bid, posted or changed." } })
    if not ok then return t:Skip(whyNot) end
    local deadline = Now() + 60
    while Now() < deadline and not rec.requested do
        PromptStillOpen(t)
        if Combat() then Disarm(rec); return t:Skip("combat started") end
        t:Progress("waiting for your click")
        t:Wait(0.25)
    end
    if not rec.requested then return t:Skip("the button was not clicked in time") end
    btn:Hide()
    G.Say("Request made. Waiting for the game (you may search now)...")
    if rec.requestAt then Observe(t, rec) end
    Count(t, "autoscan.click")
    Disarm(rec)
    local verdict = Report(t, "autoscan.click", rec)
    G.Say(verdict)
    t:Note("verdict: " .. verdict)
    t:Note("Compare with autoscan.event.open. The throttle may allow one whole-house request in a while: if this case says the throttle was not ready, wait and run it again rather than clicking repeatedly.")
end }
