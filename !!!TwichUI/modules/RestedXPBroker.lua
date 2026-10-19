-- TwichUI: RestedXP guide on a data bar
-- A LibDataBroker data source, "TwichUI RestedXP Guide", for a data bar (for example EllesmereUI's
-- "Broker Plugin" block). Its text says whether RestedXP's guide is on ("Guide on" / "Guide off"); a click
-- opens a small menu (modules/RestedXPBrokerMenu.lua, drawn like the Mage launchers' menus): choose which
-- guide to load, show the guide (on or off), lock its windows, switch quest auto accept/turn in, flight
-- path automation and discarding junk when the bags are full on or off, and open RestedXP's guide import window.
-- Made only when RestedXP is loaded. TwichUI doesn't bundle LibDataBroker: nothing
-- happens without a data bar addon that provides it.
--
-- What RestedXP gives us (RXPGuides v4.11.22 source, SettingsPanel.lua; not a public interface, checked
-- on every use): its addon object is registered with AceAddon as "RXPGuides". settings.ToggleActive()
-- flips settings.profile.showEnabled and shows or hides every RestedXP frame (the guide window, arrow,
-- item and target buttons, flight timers). It is what RestedXP's own minimap button, its menu's
-- Show/Hide and "/rxp toggle" call, so the menu's switch does exactly what those do, combat included
-- (RestedXP itself leaves its secure buttons alone in combat). Lock is RestedXP's "Lock Frames" option,
-- settings.profile.lockFrames, a plain boolean RestedXP reads whenever a window is dragged (its options
-- page sets it with no other step). Import calls guideImporter:Open(), as its own menu and "/rxp import"
-- do; RestedXP puts that off itself during combat, so the menu entry is greyed out then. Choosing a guide
-- lists what RXPFrame:GenerateMenuTable({}) returns (the list its own guide menu and v2 window show,
-- already filtered for the character) and loads the pick by calling that entry's own click handler, which
-- is addon:LoadGuide; RestedXP has no combat check there, nor does its menu. Nothing else of RestedXP's
-- is changed.
-- Discard junk when the bags are full is profile.autoDiscardItems, set the way RestedXP's own option sets it.
-- ToggleActive and settings:RefreshProfile (a RestedXP profile change) are hooked, once, so the text
-- follows a toggle made anywhere.

local R = TwichUI
local B = {}
R.RestedXPBroker = B

local NAME = "TwichUI RestedXP Guide"
local ADDON = "RXPGuides"
local ICON = R.PATH .. [[media\textures\restedxp-broker]]   -- an open book with a guiding light (64 x 64)
local obj
local rxp
local hooked = false
local loggedIn = false

local function FindRestedXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil end
    local ok, addon = pcall(ace.GetAddon, ace, ADDON, true)
    if ok and type(addon) == "table" then return addon end
end

local function Usable(addon)
    local settings = type(addon) == "table" and addon.settings
    return type(settings) == "table" and type(settings.ToggleActive) == "function" and type(settings.profile) == "table"
end

-- true / false, or nil when RestedXP can't be read.
function B.GuideLocked()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.lockFrames and true or false
end

function B.GuideOn()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.showEnabled and true or false
end

-- RestedXP's "Quest auto accept/turn in" and "Flight Path automation" options (SettingsPanel.lua: plain profile
-- booleans, enableQuestAutomation and enableFPAutomation, read whenever a quest or taxi map is handled).
function B.QuestAutoOn()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.enableQuestAutomation and true or false
end

function B.FlightAutoOn()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.enableFPAutomation and true or false
end

-- RestedXP's "Discard junk items if bag is full" (SettingsPanel.lua: profile.autoDiscardItems, a plain boolean that
-- InventoryManager.lua reads as bag events come in). Its page shows the option only with the inventory manager on
-- (enableInventoryManager) and a bag addon it supports (inventoryManager.bagManager:IsAvailable(), the same check).
function B.DiscardOn()
    if not Usable(rxp) then return nil end
    return rxp.settings.profile.autoDiscardItems and true or false
end

-- nil when the switch can be used now, else the short reason the menu shows.
function B.DiscardBlocker()
    if not Usable(rxp) then return nil end
    if not rxp.settings.profile.enableInventoryManager then return "Inventory off" end
    local bags = type(rxp.inventoryManager) == "table" and rxp.inventoryManager.bagManager
    if not (type(bags) == "table" and type(bags.IsAvailable) == "function" and bags:IsAvailable()) then
        return "Unavailable"
    end
    return nil
end

local function BarText()
    local on = B.GuideOn()
    if on == nil then return "Guide" end
    return on and "Guide on" or "Guide off"
end

function B.Update()
    if obj then obj.text = BarText() end
    if R.RestedXPBrokerMenu then R.RestedXPBrokerMenu.Refresh() end
end

function B.GuideName()
    local guide = rxp and rxp.currentGuide
    if type(guide) ~= "table" or type(rxp.GetGuideName) ~= "function" then return nil end
    local ok, name = pcall(rxp.GetGuideName, guide)
    if ok and type(name) == "string" and name ~= "" then return guide.title or name end
end

local function Color()
    local K = R.ChronicleStyle and R.ChronicleStyle.color
    return K or { text = { 1, 1, 1 }, textDim = { 0.8, 0.8, 0.8 }, stone = { 0.6, 0.6, 0.6 }, gold = { 0.8, 0.7, 0.3 } }
end

local function OnTooltipShow(tip)
    local K = Color()
    B.Update()
    tip:AddLine("RestedXP guide", 1, 1, 1)
    local on = B.GuideOn()
    if on == nil then
        tip:AddLine("RestedXP can't be read (a version this wasn't written for?).", K.stone[1], K.stone[2], K.stone[3])
        return
    end
    tip:AddDoubleLine("Guide", on and "On" or "Off", K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    local name = B.GuideName()
    if name then tip:AddDoubleLine("Current", name, K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3]) end
    if on and rxp.settings.profile.hideGuideWindow then
        tip:AddLine("The guide window is hidden in RestedXP's options.", K.stone[1], K.stone[2], K.stone[3])
    end
    tip:AddDoubleLine("Windows", B.GuideLocked() and "Locked" or "Unlocked", K.textDim[1], K.textDim[2], K.textDim[3], K.text[1], K.text[2], K.text[3])
    tip:AddLine(" ")
    tip:AddLine("Click for options", K.gold[1], K.gold[2], K.gold[3])
end

---------------------------------------------------------------------------
-- What the menu does. Each asks RestedXP again at that moment.
---------------------------------------------------------------------------
function B.SetGuideOn(on)
    if not Usable(rxp) then return end
    if B.GuideOn() ~= (on and true or false) then rxp.settings.ToggleActive() end
    B.Update()
end

function B.SetLocked(locked)
    if not Usable(rxp) then return end
    rxp.settings.profile.lockFrames = locked and true or false
end

function B.SetQuestAuto(on)
    if not Usable(rxp) then return end
    rxp.settings.profile.enableQuestAutomation = on and true or false
end

function B.SetFlightAuto(on)
    if not Usable(rxp) then return end
    rxp.settings.profile.enableFPAutomation = on and true or false
end

-- Refused while RestedXP can't take it (its options page hides the option then). Like its own option, it takes
-- effect at the next bag event; nothing else of RestedXP's is called.
function B.SetDiscard(on)
    if not Usable(rxp) or B.DiscardBlocker() ~= nil then return end
    rxp.settings.profile.autoDiscardItems = on and true or false
end

function B.CanImport()
    local importer = type(rxp) == "table" and rxp.guideImporter
    return type(importer) == "table" and type(importer.Open) == "function"
        and not (InCombatLockdown and InCombatLockdown())
end

function B.OpenImport()
    if not B.CanImport() then return end
    rxp.guideImporter:Open()
end

---------------------------------------------------------------------------
-- Choosing a guide
---------------------------------------------------------------------------
local MAX_DEPTH = 6   -- RestedXP nests groups, sub-groups, guides and chapters; this only stops a loop

local function Plain(text)
    text = type(text) == "string" and text or ""
    return (text:gsub("[\r\n]+", " "))
end

-- RestedXP's own menu table (RXPFrame:GenerateMenuTable, the list its guide window's menu is shown from,
-- also called with a table of our own by its v2 window) as plain entries the data bar menu can draw:
--   { heading = true, text }                          a section title ("Available Guides")
--   { text, children = { ... }, current }             a group, sub-group or guide with chapters
--   { text, func, arg1, arg2, current, disabled }     a guide; func is RestedXP's own click handler
-- current marks the loaded guide and the groups on the way to it. The menu table ends where RestedXP
-- starts its own settings entries (an empty title); only what is before it is read.
local function Convert(list, depth, group, name)
    local out, onPath = {}, false
    for _, item in ipairs(list) do
        if type(item) == "table" then
            local text = Plain(item.text)
            if item.isTitle and text == "" and depth == 0 then break end
            if text ~= "" then
                if item.isTitle then
                    out[#out + 1] = depth == 0 and { heading = true, text = text } or { text = text, disabled = true }
                elseif type(item.menuList) == "table" and depth < MAX_DEPTH then
                    local children, hasCurrent = Convert(item.menuList, depth + 1, group, name)
                    if #children > 0 then
                        out[#out + 1] = { text = text, children = children, current = hasCurrent }
                        onPath = onPath or hasCurrent
                    end
                elseif type(item.func) == "function" then
                    local isCurrent = group ~= nil and item.arg1 == group and item.arg2 == name
                    out[#out + 1] = { text = text, func = item.func, arg1 = item.arg1, arg2 = item.arg2, current = isCurrent }
                    onPath = onPath or isCurrent
                end
            end
        end
    end
    return out, onPath
end

function B.CanChoose()
    local frame = type(rxp) == "table" and rxp.RXPFrame
    return Usable(rxp) and type(frame) == "table" and type(frame.GenerateMenuTable) == "function"
end

-- The guides RestedXP offers right now (its own filters: faction, level, season, "show unused guides"),
-- or nil when it can't be read. Read when asked, never at login: building it walks every guide's name.
function B.GuideTree()
    if not B.CanChoose() then return nil end
    local frame = rxp.RXPFrame
    local ok, list = xpcall(function() return frame:GenerateMenuTable({}) end, geterrorhandler())
    if not ok or type(list) ~= "table" then return nil end
    local current = rxp.currentGuide
    local tree = Convert(list, 0, type(current) == "table" and current.group or nil, type(current) == "table" and current.name or nil)
    return tree
end

-- Loads a guide entry the way RestedXP's own menu does (its click handler, which also closes its menu).
function B.LoadGuide(entry)
    if not (B.CanChoose() and type(entry) == "table" and type(entry.func) == "function") then return false end
    entry.func(entry, entry.arg1, entry.arg2)
    B.Update()
    return true
end

local function OnClick(frame)
    if not Usable(rxp) then return end
    if GameTooltip then GameTooltip:Hide() end   -- it would sit over the menu
    if R.RestedXPBrokerMenu then
        R.RestedXPBrokerMenu.Toggle(frame)
    else
        rxp.settings.ToggleActive()   -- no menu: the click keeps its old job
        B.Update()
    end
end

local function Hook()
    if hooked then return end
    hooked = true
    hooksecurefunc(rxp.settings, "ToggleActive", B.Update)
    if type(rxp.settings.RefreshProfile) == "function" then hooksecurefunc(rxp.settings, "RefreshProfile", B.Update) end
end

-- Once, when RestedXP is loaded and a data bar addon provides LibDataBroker.
local function Create()
    if obj then return end
    rxp = rxp or FindRestedXP()
    if not Usable(rxp) then return end
    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end
    Hook()
    obj = LDB:NewDataObject(NAME, {
        type = "data source",   -- not "launcher": many data bars show text only for a data source
        label = "RestedXP",
        text = BarText(),
        icon = ICON,
        OnClick = OnClick,
        OnTooltipShow = OnTooltipShow,
    })
end

-- Whether it is on a data bar's list (false without RestedXP or LibDataBroker).
function B.Available() return obj ~= nil end

R:On("PLAYER_LOGIN", function()
    loggedIn = true
    Create()
end)
-- A data bar addon loaded on demand after login can still bring LibDataBroker.
R:On("ADDON_LOADED", function() if loggedIn then Create() end end)
