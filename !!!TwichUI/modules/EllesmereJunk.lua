-- TwichUI: the one place that talks to EllesmereUI's Bags Junk Marker
-- Used by Mage selling and Workshop's opt-in Vendor marking. Nothing here decides what is
-- worth marking; it only says whether EllesmereUI can be asked, and asks.
--
-- What was read, in EllesmereUI Bags 9.5.5 (EllesmereUIBags_Categories.lua, EllesmereUIBags.lua):
--   * The Junk Marker is part of the Bags module: _G.EUI_CategoryManager, a global the module sets while it
--     loads. There is no separate, documented API; this accessor is what the Bags' own UI calls.
--   * A mark is an item-ID assignment to the Junk category: AssignItem(itemID, JUNK_KEY). Every route in its UI
--     that marks (the header coin, a drop on the Junk row) goes through AssignItem and then asks the open bags
--     to repaint with EUI_Bags:RefreshInventory(). That is the path used here. ToggleJunk is not used: it
--     flips, so it is not safe to repeat.
--   * IsJunk(itemID, quality) is true for a marked item, and for an unfiled grey item. IsJunkMarkerEnabled()
--     is the Bag Top Bar "Junk Icon" switch; with it off nothing is junk and nothing is sold.
--   * Marks are kept per item ID in EllesmereUI's own saved data, for the whole account. They are not kept
--     per stack, per bag slot or per character. Selling (EUI_Bags:SellJunk, run at a merchant by
--     EllesmereUIQoL's Auto Sell Junk, or by the bag's Sell Junk button) takes every copy in the carried bags.
-- Workshop owns only marks it actually applied. Assignment hooks surrender that ownership to the player;
-- its IsJunk guard withholds those marks from selling until Workshop validates their current support.
-- Unmarking uses UnassignItem, which restores EllesmereUI's previous filing. No EllesmereUI saved writes,
-- sell calls or button clicks occur here. Ordinary Mage Sell marks retain the original behavior.
-- The one read of its saved data is bagItemAssignments[itemID], so an item the player filed in a category of
-- their own is left where they put it (AssignItem would replace that filing). No such read, no mark.

local R = TwichUI
local EJ = {}
R.EllesmereJunk = EJ

local PARENT, BAGS, QOL = "EllesmereUI", "EllesmereUIBags", "EllesmereUIQoL"
local OWNED_MAX = 2048
local guards = setmetatable({}, { __mode = "k" })
local allowOwned, manualChanged
local assignmentSource

local function ValidID(itemID)
    return type(itemID) == "number" and itemID == itemID and itemID >= 1 and itemID <= 2147483647 and itemID % 1 == 0
end
local function AssignmentTable()
    local db = _G.EllesmereUIDB
    return type(db) == "table" and type(db.bagItemAssignments) == "table" and db.bagItemAssignments or nil
end

local function OwnedData(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local owned = TwichUIDB.workshopJunkOwned
    if owned == nil and create then owned = {}; TwichUIDB.workshopJunkOwned = owned end
    local current = AssignmentTable()
    if assignmentSource and current ~= assignmentSource then
        -- A reset or replacement table is a new set of player assignments. Old ownership is not proof
        -- that a same-ID Junk assignment in that table belongs to Workshop.
        assignmentSource = current
        if type(owned) == "table" then
            for itemID, on in pairs(owned) do
                if on == true and ValidID(itemID) then
                    owned[itemID] = nil
                    if manualChanged then manualChanged(itemID) end
                end
            end
        end
    elseif current then assignmentSource = current end
    return type(owned) == "table" and owned or nil
end
local function Assignment(itemID)
    local assignments = AssignmentTable()
    return assignments and assignments[itemID] or nil
end
local function RawJunk(cm, itemID, quality)
    local g = guards[cm]
    return (g and g.original or cm.IsJunk)(cm, itemID, quality)
end

local function Install(cm)
    if not cm or type(hooksecurefunc) ~= "function" or type(cm.UnassignItem) ~= "function" then return false end
    local g = guards[cm]
    if not g then g = { original = cm.IsJunk, writing = 0 }; guards[cm] = g end
    if g.installed then return true end
    local function Manual(_, itemID)
        if g.writing > 0 or not ValidID(itemID) then return end
        local owned = OwnedData()
        if owned then owned[itemID] = nil end
        if manualChanged then manualChanged(itemID) end
    end
    if not g.assignHook then g.assignHook = pcall(hooksecurefunc, cm, "AssignItem", Manual) end
    if not g.unassignHook then g.unassignHook = pcall(hooksecurefunc, cm, "UnassignItem", Manual) end
    if not (g.assignHook and g.unassignHook) then return false end
    if not g.installed then
        cm.IsJunk = function(self, itemID, quality)
            local owned = OwnedData()
            if owned and owned[itemID] == true then
                if Assignment(itemID) ~= self.JUNK_KEY then
                    owned[itemID] = nil
                    if manualChanged then manualChanged(itemID) end
                else
                    local ok, allowed = false, false
                    if allowOwned then ok, allowed = pcall(allowOwned, itemID) end
                    if not ok or allowed ~= true then return false end
                end
            end
            return g.original(self, itemID, quality)
        end
        g.installed = true
    end
    return true
end

EJ.REASONS = {
    ready = "EllesmereUI's Junk Marker is ready.",
    ["not-installed"] = "EllesmereUI's Bags aren't installed.",
    ["disabled"] = "EllesmereUI's Bags are turned off in your addon list.",
    ["not-loaded"] = "EllesmereUI's Bags haven't loaded yet.",
    ["blocked"] = "EllesmereUI's Bags didn't start on this game version.",
    ["not-ready"] = "This version of EllesmereUI's Bags offers no Junk Marker TwichUI can use.",
    ["marker-off"] = "The Junk Marker is turned off in EllesmereUI's Bags (Bag Top Bar Icons: Junk Icon).",
}

local function Loaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) == true
end

local function Manager()
    local cm = _G.EUI_CategoryManager
    if type(cm) ~= "table" then return nil end
    if type(cm.AssignItem) ~= "function" or type(cm.IsJunk) ~= "function"
        or type(cm.IsJunkMarkerEnabled) ~= "function" or type(cm.JUNK_KEY) ~= "string" or cm.JUNK_KEY == "" then
        return nil
    end
    return cm
end

-- "ready", or why not: not-installed, disabled, not-loaded, blocked, not-ready, marker-off. Cheap enough to
-- ask on every bag change: it reads no bag and builds nothing.
function EJ.Status()
    if not (Loaded(PARENT) and Loaded(BAGS)) then
        local state = R.Setups and R.Setups.AddonState
        local parent = state and state(PARENT)
        local bags = state and state(BAGS)
        if parent == "missing" or bags == "missing" then return "not-installed" end
        if parent == "disabled" or bags == "disabled" then return "disabled" end
        return "not-loaded"
    end
    if _G.EUI_CLIENT_BLOCKED == true then return "blocked" end
    local cm = Manager()
    if not cm then return "not-ready" end
    Install(cm)
    if type(_G.EllesmereUIDB) ~= "table" then return "not-ready" end   -- its saved data isn't up yet
    local ok, on = pcall(cm.IsJunkMarkerEnabled, cm)
    if not ok then return "not-ready" end
    if on ~= true then return "marker-off" end
    return "ready"
end

function EJ.Ready() return EJ.Status() == "ready" end

-- What happens to a marked item at a merchant, as far as EllesmereUI's own settings say: "auto" (its Auto Sell
-- Junk is on and EllesmereUI's QoL module is loaded), "button" (marked items are sold only when you press Sell
-- Junk in the bags at a merchant) or "unknown". Read only.
function EJ.Selling()
    if EJ.Status() ~= "ready" then return "unknown" end
    local bags = _G.EUI_Bags
    if type(bags) ~= "table" or type(bags.SellJunk) ~= "function" then return "unknown" end
    local db = _G.EllesmereUIDB
    if Loaded(QOL) and type(db) == "table" and db.autoSellJunk ~= false then return "auto" end
    return "button"
end

-- What marking this item would do right now, without doing it: "already" (junk, marked or grey),
-- "filed-elsewhere" (the player put it in a category of their own), "markable", or "unavailable".
function EJ.Peek(itemID, quality)
    local cm = EJ.Ready() and Manager()
    if not cm then return "unavailable" end
    local ok, junk = pcall(RawJunk, cm, itemID, quality)
    if not ok then return "unavailable" end
    if junk == true then return "already" end
    local db = _G.EllesmereUIDB
    local filed = type(db) == "table" and type(db.bagItemAssignments) == "table" and db.bagItemAssignments[itemID]
    if filed ~= nil and filed ~= false and filed ~= cm.JUNK_KEY then return "filed-elsewhere" end
    return "markable"
end

-- Marks one item ID through EllesmereUI's own call. Returns "marked", "already", "filed-elsewhere", "failed"
-- or "unavailable". Safe to repeat: an item that is already junk is not touched. It is "marked" only when
-- EllesmereUI then says the item is junk.
function EJ.Mark(itemID, quality)
    if type(itemID) ~= "number" or itemID ~= itemID or itemID < 1 or itemID % 1 ~= 0 then return "failed" end
    local before = EJ.Peek(itemID, quality)
    if before ~= "markable" then return before end
    local cm = Manager()
    if not cm then return "unavailable" end
    local called = pcall(cm.AssignItem, cm, itemID, cm.JUNK_KEY)
    if not called then return "failed" end
    local ok, junk = pcall(RawJunk, cm, itemID, quality)
    if ok and junk == true then return "marked" end
    return "failed"
end

-- Hooks and the narrow classification guard are installed only once per manager. No guard result is cached
-- here: Workshop owns its bounded valuation snapshot and invalidates it on its existing events.
function EJ.Guard(fn)
    allowOwned = type(fn) == "function" and fn or nil
    return Install(Manager())
end
function EJ.OnManual(fn) manualChanged = type(fn) == "function" and fn or nil end
function EJ.Owned(itemID)
    local owned, cm = OwnedData(), Manager()
    if not (owned and owned[itemID] == true) then return false end
    if cm and Assignment(itemID) ~= cm.JUNK_KEY then
        owned[itemID] = nil
        if manualChanged then manualChanged(itemID) end
        return false
    end
    return true
end
function EJ.OwnedItems()
    local items = {}
    for itemID, owned in pairs(OwnedData() or {}) do
        if owned == true and ValidID(itemID) and #items < OWNED_MAX then items[#items + 1] = itemID end
    end
    return items
end
function EJ.MarkOwned(itemID, quality)
    if not ValidID(itemID) then return "failed" end
    if not EJ.Ready() then return "unavailable" end
    local cm = Manager()
    if not Install(cm) then return "unavailable" end
    local before = EJ.Peek(itemID, quality)
    if before ~= "markable" then return before end
    local owned = OwnedData(true)
    if not owned then return "unavailable" end
    local count = 0
    for _ in pairs(owned) do count = count + 1; if count >= OWNED_MAX then return "unavailable" end end
    -- Claim first: EllesmereUI's assignment callback can synchronously redraw its junk list.
    owned[itemID] = true
    local g = guards[cm]
    g.writing = g.writing + 1
    pcall(cm.AssignItem, cm, itemID, cm.JUNK_KEY)
    g.writing = g.writing - 1
    local ok, junk = pcall(RawJunk, cm, itemID, quality)
    -- A notification may throw after the assignment changed. Keep provenance
    -- for every observed Junk assignment, including one whose reader failed.
    if ok and junk == true and Assignment(itemID) == cm.JUNK_KEY then return "marked" end
    if Assignment(itemID) ~= cm.JUNK_KEY then owned[itemID] = nil end
    return "failed"
end
function EJ.UnmarkOwned(itemID)
    if not EJ.Owned(itemID) then return "unowned" end
    if not EJ.Ready() then return "unavailable" end
    local cm = Manager()
    if not Install(cm) then return "unavailable" end
    local g = guards[cm]
    g.writing = g.writing + 1
    pcall(cm.UnassignItem, cm, itemID)
    g.writing = g.writing - 1
    if Assignment(itemID) ~= cm.JUNK_KEY then
        local owned = OwnedData(); if owned then owned[itemID] = nil end
        return "unmarked"
    end
    return "failed"
end

-- Asks the open bags to draw again, as EllesmereUI's own marking routes do after they mark. It returns at once
-- when the bags are closed, and holds the repaint for after combat itself.
function EJ.Repaint()
    local bags = _G.EUI_Bags
    if type(bags) == "table" and type(bags.RefreshInventory) == "function" then
        local ok, err = pcall(bags.RefreshInventory, bags)
        if not ok and R.Diag then R.Diag.Error("mage sell mark", err) end
    end
end

-- Saved automatic marks are withheld from selling even before the optional Workshop addon loads.
-- Reuse core lifecycle dispatch; no additional bag listeners, frames or timers.
local function RestoreGuard()
    local owned = OwnedData()
    if owned and next(owned) then Install(Manager()) end
end
if R.OnInit then R:OnInit(RestoreGuard) end
if R.On then R:On("ADDON_LOADED", RestoreGuard) end
