-- Real addon shell and handler-level inputs over a synthetic native-frame sentinel.
-- No real auctioneer, server, pointer, combat, font or taint evidence.
local R = TwichUI
A_Admin.SetManualClock(GetTime())
Lab.Solo()
local native = CreateFrame("Frame", nil, UIParent)
native:SetSize(800, 500); native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 26, -90); native:SetScale(0.83); native:Show()
AuctionHouseFrame = native
local scale, hidden, shown, calls = native:GetScale(), 0, 0, 0
native:SetScript("OnHide", function() hidden = hidden + 1 end)
native:SetScript("OnShow", function() shown = shown + 1 end)
C_AuctionHouse = setmetatable({}, { __index = function(_, key)
    return function() calls = calls + 1; error("preview issued auction operation " .. key) end
end })
local A, f
Lab.Step("explicit preview", function()
    Lab.Check("init", "Workshop initially unloaded", false, R.WorkshopLauncher.Loaded())
    Lab.Check("init", "proof disabled", false, R.AuctionHost.Snapshot().leased)
    SlashCmdList.TWICHUI("ahpreview")
    A = R.Workshop.AuctionUI; f = A.Frame()
    Lab.Check("construct", "preview shown", true, f:IsShown())
    Lab.Check("construct", "Workshop window unbuilt", false, R.Workshop.Snapshot().built)
    Lab.Check("state", "Browse default", "browse", A.Mode())
end)
Lab.Step("navigation and lifecycle", function()
    for _, key in ipairs({"browse", "shopping", "sell", "owned", "market"}) do
        A.nav[key]:Click()
        Lab.Check("interact", "navigation " .. key, key, A.Mode())
        Lab.Check("state", "page shown " .. key, true, A.Page(key):IsVisible())
    end
    local pages = A.Snapshot().pages
    for i = 1, 12 do
        f.close:Click(); A.Show(); A.nav.shopping:Click(); A.nav.browse:Click()
    end
    Lab.Check("state", "bounded pages", pages, A.Snapshot().pages)
    for key,page in pairs(A.views) do Lab.Check("state", "exclusive reopened page " .. key, key=="browse", page:IsShown()) end
    f.blizzard:Click()
    Lab.Check("state", "Blizzard switch closes preview", false, f:IsShown())
    Lab.Check("state", "no hidden listeners", 0, A.Snapshot().events)
    A.Show()
end)
Lab.Step("native untouched and fit", function()
    Lab.Check("state", "native still shown", true, native:IsVisible())
    Lab.Check("state", "native scale retained", scale, native:GetScale())
    Lab.Check("state", "native anchor retained", 26, select(4, native:GetPoint(1)))
    Lab.Check("state", "native never hidden", 0, hidden)
    Lab.Check("state", "native never reshown", 0, shown)
    Lab.Check("state", "zero auction operations", 0, calls)
    Lab.Check("state", "proof still disabled", false, R.AuctionHost.Snapshot().leased)
    if P.scaled then UIParent:SetScale(0.8); f:GetScript("OnEvent")(f,"UI_SCALE_CHANGED") end
    R.FitToScreen(f)
    Lab.Check("construct", "close inside root", true, f.close:GetRight() <= f:GetRight())
    Lab.Check("construct", "Blizzard switch above pages", true, f.blizzard:GetBottom() > f.content:GetTop())
    Lab.Check("construct", "navigation at left", true, f.nav:GetRight() < f.content:GetLeft())
    Lab.Check("construct", "window within viewport", true, f:GetWidth()*f:GetEffectiveScale() <= UIParent:GetWidth()*UIParent:GetEffectiveScale())
end)
Lab.RunUntil(5.5)
Lab.Finish()
