-- Real core/Host, real simulator frames/timers/control, optional real Workshop
-- load. FAKE auctioneer booleans, native root/display mode and native close
-- side effects. Core event handlers are driven directly so Blizzard's bootstrap
-- is not asked to create a real auctioneer. Not a server/input/taint proof.
local R, H = TwichUI, TwichUI.AuctionHost
Lab.BUDGET = 45 -- full 30-second lease plus the preceding transitions
A_Admin.SetManualClock(GetTime())
Lab.Solo()
local beforeLoads = R.WorkshopLauncher.Snapshot().attempts
if P.loaded then
    TwichUIDB.ui.workshopEnabled = true -- explicit fixture consent; preserve this catalog's single launcher load assertion
    Lab.Check("init", "Workshop loads through launcher", true, R.WorkshopLauncher.Load())
    Lab.Check("init", "Workshop stays unbuilt", false, R.Workshop.Snapshot().built)
end
local expectedLoads = beforeLoads + (P.loaded and 1 or 0)
local native = CreateFrame("Frame", nil, UIParent)
native:SetSize(800, 538)
native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -100)
native:SetScale(0.8)
local nativeScale = native:GetScale() -- frame API stores floats; compare the exact captured value
native:SetClampedToScreen(false)
local child = CreateFrame("EditBox", nil, native)
child:SetAutoFocus(false)
local available, valid, combat, hidden, shown, calls, faults = true, true, false, 0, 0, 0, 0
native:SetScript("OnHide", function() hidden = hidden + 1 end)
native:SetScript("OnShow", function() shown = shown + 1 end)
native:Show()
AuctionHouseFrame = native
AuctionHouseFrameDisplayMode = { Buy = {} }
native.GetDisplayMode = function() return AuctionHouseFrameDisplayMode.Buy end
local originalPIM, originalCombat = C_PlayerInteractionManager, InCombatLockdown
C_PlayerInteractionManager = {
    IsInteractingWithNpcOfType = function() return available end,
    IsValidNPCInteraction = function() return valid end,
}
InCombatLockdown = function() return combat end
local realFault = R.Fault
-- Observe intentional fault injection only; normal Blizzard errors still use
-- the untouched global error handler and fail the verdict.
R.Fault = function(source, err)
    if source == "auction proof activate" and tostring(err):find("injected AH-1a anchor failure", 1, true) then
        faults = faults + 1
        Lab.Say("injected-fault", source, tostring(err))
    else
        realFault(source, err)
    end
end
local originalAH = C_AuctionHouse
C_AuctionHouse = setmetatable({}, { __index = function(_, key)
    return function() calls = calls + 1; error("proof issued auction operation " .. key) end
end })
local function Event(e, ...)
    R.frame:GetScript("OnEvent")(R.frame, e, ...)
end
local function Restored(label)
    Lab.Check("state", label .. ": lease released", false, H.Snapshot().leased)
    Lab.Check("state", label .. ": watchdog cancelled", false, H.Snapshot().watching)
    Lab.Check("state", label .. ": native x", 30, select(4, native:GetPoint(1)))
    Lab.Check("state", label .. ": native scale", nativeScale, native:GetScale())
end
Lab.Step("default and opening", function()
    Lab.Check("init", "proof starts disabled", false, H.Snapshot().leased)
    Lab.Check("construct", "no default control", nil, H.Control())
    Event("AUCTION_HOUSE_SHOW")
    Lab.Check("state", "opening does not activate", false, H.Snapshot().leased)
end)
Lab.Step("explicit command and recovery button", function()
    SlashCmdList.TWICHUI("ahproof on")
    Lab.Check("interact", "explicit activation parks", "parked", H.Snapshot().mode)
    Lab.Check("state", "native stays visible", true, native:IsVisible())
    Lab.Check("state", "root beyond viewport", true, native:GetLeft() * native:GetEffectiveScale() > UIParent:GetRight() * UIParent:GetEffectiveScale())
    Lab.Check("construct", "recovery is on screen", true, H.Control():IsVisible())
    Lab.Check("state", "fake interaction remains available", true, available and valid)
    H.Control():Click()
    Restored("button")
end)
Lab.Step("repeated switching", function()
    for i = 1, 10 do
        Lab.Check("interact", "repeated on " .. i, true, H.Activate())
        SlashCmdList.TWICHUI("ahproof off")
        Restored("switch " .. i)
    end
    Lab.Check("state", "switching never hides native", 0, hidden)
    Lab.Check("state", "switching never reshows native", 0, shown)
end)
Lab.Step("close reopen and invalid context", function()
    Lab.Check("interact", "on before close", true, H.Activate())
    available = false; native:Hide(); Event("AUCTION_HOUSE_CLOSED")
    Restored("close")
    Lab.Check("state", "closed frame not resurrected", false, native:IsShown())
    available = true; native:Show(); Event("AUCTION_HOUSE_SHOW")
    Restored("reopen")
    Lab.Check("interact", "on after reopen", true, H.Activate())
    valid = false; Lab.Settle(0.4); Restored("invalid context"); valid = true
end)
Lab.Step("external position and scale", function()
    Lab.Check("interact", "on before external move", true, H.Activate())
    native:ClearAllPoints(); native:SetPoint("CENTER", UIParent, "CENTER", 55, 0)
    Lab.Settle(0.4)
    Lab.Check("state", "foreign position preserved", 55, select(4, native:GetPoint(1)))
    Lab.Check("state", "foreign move yields ownership", false, H.Snapshot().leased)
    native:ClearAllPoints(); native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -100)
    Lab.Check("interact", "on before external scale", true, H.Activate())
    native:SetScale(0.7)
    local externalScale = native:GetScale()
    Lab.Settle(0.4)
    Lab.Check("state", "external scale preserved", externalScale, native:GetScale())
    Lab.Check("state", "owned anchors restored", 30, select(4, native:GetPoint(1)))
    native:SetScale(0.8)
end)
Lab.Step("combat restrictions", function()
    combat = true
    Lab.Check("interact", "combat activation refused", false, H.Activate())
    combat = false
    Lab.Check("interact", "on before combat", true, H.Activate())
    combat = true; Event("PLAYER_REGEN_DISABLED")
    Lab.Check("state", "combat restoration deferred", "restore-pending", H.Snapshot().mode)
    Lab.Check("state", "combat leaves protected anchors alone", 4096, select(4, native:GetPoint(1)))
    combat = false; Event("PLAYER_REGEN_ENABLED"); Restored("combat end")
end)
Lab.Step("error recovery", function()
    local setPoint, fail = native.SetPoint, true
    native.SetPoint = function(self, ...)
        if fail then fail = false; error("injected AH-1a anchor failure") end
        return setPoint(self, ...)
    end
    Lab.Check("interact", "injected error refuses activation", false, H.Activate())
    native.SetPoint = setPoint
    Restored("error")
    Lab.Check("state", "intentional error reported", 1, faults)
end)
Lab.Step("coexistence and timeout", function()
    local isLoaded = C_AddOns.IsAddOnLoaded
    C_AddOns.IsAddOnLoaded = function(name) return name == "Auctionator" or isLoaded(name) end
    Lab.Check("interact", "known owner refuses takeover", false, H.Activate())
    C_AddOns.IsAddOnLoaded = isLoaded
    Lab.Check("interact", "on before timeout", true, H.Activate())
    Lab.Settle(30.4); Restored("timeout")
    Lab.Check("state", "no auction query scan or transaction", 0, calls)
    Lab.Check("state", "Host never loads Workshop", expectedLoads, R.WorkshopLauncher.Snapshot().attempts)
    if P.loaded then Lab.Check("state", "loaded Workshop remains unbuilt", false, R.Workshop.Snapshot().built) end
end)
-- Cleanup fixture boundaries; every process starts without saved variables.
H.Restore()
native:Hide()
AuctionHouseFrame = nil
C_PlayerInteractionManager, InCombatLockdown, C_AuctionHouse, R.Fault = originalPIM, originalCombat, originalAH, realFault
Lab.Finish()
