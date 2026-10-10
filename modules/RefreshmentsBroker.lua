-- TwichUI: Mage refreshments on a data bar
-- A LibDataBroker data source, "TwichUI Mage Refreshments", for a data bar (for example EllesmereUI's
-- "Broker Plugin" block). Its text is how many of your group are supplied ("3/5 supplied"), the word
-- "Refreshments", or nothing, as the player chooses (TwichUIDB.ui.refreshmentsText). Its tooltip sums up
-- the plan: water and food prepared against what is needed, who is supplied, who is next. Click opens
-- the refreshments panel; right-click opens the Mage options page. It only reads the plan
-- (modules/Refreshments.lua) and opens the panel: it casts and moves nothing.
-- Made for a Mage once Mage refreshments is on (at login, or when it is turned on). A data object can't
-- be taken away again, so turned off it says "Off" until the next reload. TwichUI doesn't bundle
-- LibDataBroker: nothing happens without a data bar addon that provides it.

local R = TwichUI
local RF = R.Refreshments
local B = {}
R.RefreshmentsBroker = B

local NAME = "TwichUI Mage Refreshments"
local WATER_SPELL = 5504   -- Conjure Water (Rank 1): its icon is the launcher's
local obj
local loggedIn = false

B.TEXTS = { { "progress", "Supplied (3/5 supplied)" }, { "label", "Refreshments" }, { "none", "None (icon only)" } }
B.DEFAULT_TEXT = "progress"

local function Valid(value)
    for _, choice in ipairs(B.TEXTS) do
        if choice[1] == value then return true end
    end
    return false
end

function B.TextChoice()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.refreshmentsText
    return Valid(saved) and saved or B.DEFAULT_TEXT
end

local function BarText()
    local choice = B.TextChoice()
    if choice == "none" then return "" end
    if not RF.Enabled() then return "Off" end
    if choice == "label" then return "Refreshments" end
    local plan = RF.Plan()
    local c = plan and plan.counts
    local owed = c and (c.supplied + c.partial + c.pending) or 0
    if not plan or plan.context == "solo" or owed == 0 then return "Refreshments" end
    return ("%d/%d supplied"):format(c.supplied, owed)
end

-- Saves the choice (an unknown one is refused); the data bar follows at once.
function B.SetTextChoice(value)
    if not Valid(value) then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    TwichUIDB.ui.refreshmentsText = value
    B.Update()
    return true
end

function B.Update()
    if obj then obj.text = BarText() end
end

local function Color()
    local K = R.ChronicleStyle and R.ChronicleStyle.color
    return K or { text = { 1, 1, 1 }, textDim = { 0.8, 0.8, 0.8 }, stone = { 0.6, 0.6, 0.6 }, gold = { 0.8, 0.7, 0.3 } }
end

local function OnTooltipShow(tip)
    local K = Color()
    tip:AddLine("Mage refreshments", 1, 1, 1)
    if not RF.Enabled() then
        tip:AddLine("Turned off in TwichUI options (Mage page).", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    local plan = RF.Plan()
    if plan then
        if plan.context == "solo" then
            tip:AddLine("Not in a group: only what you keep for yourself.", K.textDim[1], K.textDim[2], K.textDim[3])
        end
        for _, kind in ipairs(RF.KINDS) do
            local t = plan.totals[kind]
            if t.need > 0 then
                local right = t.short > 0 and ("%d / %d, %d to conjure"):format(t.covered, t.need, t.short) or ("%d / %d, enough"):format(t.covered, t.need)
                tip:AddDoubleLine(RF.KIND_LABEL[kind], right, K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
            end
        end
        local c = plan.counts
        local owed = c.supplied + c.partial + c.pending
        if owed > 0 then
            tip:AddDoubleLine("Supplied", ("%d of %d"):format(c.supplied, owed), K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
        end
        local offered = 0
        for _, row in ipairs(plan.rows) do
            if RF.Unconfirmed(row.guid) then offered = offered + 1 end
            if row.guid == plan.next then tip:AddDoubleLine("Next", row.name or "Unknown", K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3]) end
        end
        if offered > 0 then
            tip:AddLine(("%d %s to confirm in the panel."):format(offered, offered == 1 and "trade" or "trades"), K.gold[1], K.gold[2], K.gold[3])
        end
    end
    tip:AddLine(" ")
    tip:AddLine("Click to open the refreshments panel", K.gold[1], K.gold[2], K.gold[3])
    tip:AddLine("Right-click for options", K.stone[1], K.stone[2], K.stone[3])
end

local function OnClick(_, button)
    if button == "RightButton" then
        if not (InCombatLockdown and InCombatLockdown()) then R:OpenSettings("mage") end
        return
    end
    if GameTooltip then GameTooltip:Hide() end
    if R.RefreshmentsPanel then R.RefreshmentsPanel.Toggle() end
end

local function Icon()
    local icon = C_Spell and C_Spell.GetSpellTexture and R.SpellMenu.Plain(C_Spell.GetSpellTexture(WATER_SPELL))
    return icon or R.ICON
end

-- Once, for a Mage with the feature on, when a data bar addon provides LibDataBroker.
local function Create()
    if obj or not RF.Enabled() then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject(NAME, {
        type = "data source",   -- not "launcher": many data bars show text only for a data source
        label = "Refreshments",
        text = BarText(),
        icon = Icon(),
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false while no addon provides LibDataBroker).
function B.Available() return obj ~= nil end

-- The plan, the shares or the switch changed: make it if it is wanted now, and refresh its text.
RF.OnChange(function()
    if loggedIn then Create() end
    B.Update()
end)

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    Create()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn then Create() end end)
