-- TwichUI Workshop: "What's it worth?" on item tooltips
-- Adds a short comparison (Worth.lua) to the tooltip of an item in the player's own bags or bank. Advice only: it sells, lists, buys and
-- disenchants nothing, and it never asks the auction house for anything (it reads the prices a scan the player started already saved).
--
-- LOAD ON DEMAND: this addon is not loaded at login, so the section exists only once the Workshop has been loaded in the session (the
-- first time the player opens it). Nothing here makes the Workshop load because an item tooltip appeared.
--
-- Which tooltips: GameTooltip only, for an item the tooltip data names by GUID that sits in a bag or bank slot (C_Item.GetItemLocation).
-- An item in a chat link, a vendor, an auction listing or a character slot gets nothing: the advice is about what the player holds.
--
-- What is shown, and in what order, is the player's layout (WorthLayout.lua, arranged in the settings window's Workshop page); "Enable tooltip" off
-- adds nothing. The same builder draws the designer's preview.
--
-- Shift: pressing or releasing Shift while the tooltip is up rebuilds it once (GameTooltip:RefreshData) so the details appear or go away;
-- the post call below runs on every rebuild and a rebuild starts from an empty tooltip, so lines are never added twice. Item information
-- that arrives late is waited for with one event, registered only while a tooltip is waiting for it.

local R = TwichUI
local W = R.Workshop
local WO, WL, PR, S, MK = W.Worth, W.WorthLayout, W.Prices, W.Session, W.Market
local Plain, Int = W.Plain, W.Int
local T = {}
W.WorthTip = T

T.registered = false
T.added = 0          -- sections added (a counter for tests)
T.faults = 0

local carrying       -- the tooltip that shows our section now (so a Shift change rebuilds it), or nil
local waiting        -- { tooltip, item } waiting for that item's information, or nil
local frame          -- the event frame (modifier changes; item information only while waiting)
local faulted = false

local function Shift() return IsShiftKeyDown and IsShiftKeyDown() == true end

-- Everything the evaluation needs, from the game. Returns facts, or nil (not an item of the player's: nothing is added), or nil and
-- "pending" (the item's information has not arrived yet).
function T.Read(data)
    local guid = Plain(data.guid)
    if type(guid) ~= "string" or not (C_Item and C_Item.GetItemLocation) then return nil end
    local loc = C_Item.GetItemLocation(guid)
    if not loc or not loc.IsBagAndSlot or not loc:IsBagAndSlot() then return nil end   -- not equipped items, not links, not listings
    if not C_Item.DoesItemExist(loc) then return nil end

    local link = Plain(C_Item.GetItemLink(loc))
    if type(link) ~= "string" then link = nil end
    local id = Int(C_Item.GetItemID(loc), 1, W.MAX_ID)
    if not id then return nil end

    local name, _, quality, _, _, _, _, _, equipLoc, _, sell, classID, _, bindType = C_Item.GetItemInfo(link or id)
    name = Plain(name)
    if not name then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return nil, "pending", id
    end

    local f = { item = id, sell = Plain(sell), quality = Plain(quality), classID = Plain(classID), bindType = Plain(bindType),
        equipLoc = Plain(equipLoc), now = time() }
    if C_Item.IsBound then f.bound = Plain(C_Item.IsBound(loc)) end
    if f.bound ~= true and f.bound ~= false then f.bound = nil end
    if C_Item.GetStackCount then f.count = Int(C_Item.GetStackCount(loc), 1, 100000) end

    f.variant = WO.LinkVariant(link)
    if not f.variant and link and C_Item.GetDetailedItemLevelInfo then
        local actual, _, base = C_Item.GetDetailedItemLevelInfo(link)
        actual, base = Plain(actual), Plain(base)
        if type(actual) == "number" and type(base) == "number" and actual ~= base then f.variant = "level" end
    end

    local src = S.PriceSource()
    local market = src.market
    if market then
        f.market = { label = src.label, side = market.side, at = market.at, complete = market.complete }
        f.marketTable = market
        f.price = MK.Price(id, { market = market, variant = f.variant ~= nil })   -- the one price service; a variant is never given the base item's price
        f.rate = PR.CutRate(market.side)
    end
    return f
end

local function Rebuild(tooltip)
    if tooltip and tooltip.RefreshData then tooltip:RefreshData() end
end

-- Draws lines in the tooltip: the heading first (after a blank line), then each line in the colour WorthLayout.Style names. The same
-- colours and the same style rules as the designer's preview.
local function Draw(tooltip, lines)
    local C = WL.COLORS
    for i, line in ipairs(lines) do
        local kind, a, b = WL.Style(line)
        if i == 1 then
            tooltip:AddLine(" ")
            tooltip:AddLine(line[1], C.title[1], C.title[2], C.title[3])
        elseif kind == "double" then
            tooltip:AddDoubleLine(a, b, C.left[1], C.left[2], C.left[3], C.right[1], C.right[2], C.right[3])
        else
            local c = C[kind]
            tooltip:AddLine(a, c[1], c[2], c[3], true)
        end
    end
end

local function Listen(on)
    if not frame then return end
    if on then frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") else frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local function Add(tooltip, data)
    local f, why, id = T.Read(data)
    if not f then
        if why == "pending" then waiting = { tooltip, id } Listen(true) end
        return
    end
    -- the player's layout: switched off, or arranged (WorthLayout.lua). Nothing about it changes the figures.
    local layout = WL.Get()
    if not layout.enabled then return end
    local r = WO.Evaluate(f)
    local ctx = { money = WL.Money, ageText = PR.AgeText, market = f.market, now = f.now, count = f.count }
    -- the market figures (A7), only when the layout has a line that uses them and there is a saved market; one cached read per item (MarketFacts),
    -- so a Shift rebuild of the same tooltip decodes nothing again. A variant is never priced from the base item's listings (facts say so).
    if W.Facts and f.market and WL.UsesMarket(layout) then
        ctx.facts = W.Facts.Of(f.item, { market = f.marketTable, variant = f.variant ~= nil, now = f.now })
    end
    local lines = WL.Lines(r, ctx, layout, Shift())
    carrying = tooltip   -- even with no lines now: a Shift change may bring some
    if not lines then return end
    Draw(tooltip, lines)
    T.added = T.added + 1
end

-- The post call for every item tooltip: never lets a fault here take other addons' lines or the item's own tooltip with it
function T.OnItem(tooltip, data)
    if tooltip ~= GameTooltip or type(data) ~= "table" then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local ok, err = pcall(Add, tooltip, data)
    if not ok then
        T.faults = T.faults + 1
        if not faulted then   -- reported once through the normal handler, not every refresh
            faulted = true
            if R.Fault then R.Fault("workshop.worth", err) end
        end
    end
end

local function OnEvent(_, event, a, b)
    if event == "MODIFIER_STATE_CHANGED" then
        -- only Shift changes what is shown; a=key ("LSHIFT"/"RSHIFT")
        if type(a) == "string" and a:find("SHIFT", 1, true) and carrying and carrying.IsShown and carrying:IsShown() then Rebuild(carrying) end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- a=itemID, b=success. Only the item being waited for counts, and it is waited for once.
        local w = waiting
        if not w or a ~= w[2] then return end
        waiting = nil
        Listen(false)
        if b ~= false and w[1].IsShown and w[1]:IsShown() then Rebuild(w[1]) end
    end
end

local function OnCleared()
    carrying, waiting = nil, nil
    Listen(false)
end

function T.Start()
    if T.registered or not CreateFrame then return end
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and GameTooltip) then return end
    T.registered = true
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    if GameTooltip.HookScript then GameTooltip:HookScript("OnTooltipCleared", OnCleared) end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, R.Perf.Wrap("workshop.worth", T.OnItem))
end

function T.Events() return frame and (waiting and 2 or 1) or 0 end

T.Start()
