-- Synthetic EllesmereUI-shaped frames, real TwichUI controllers and addon artwork.
-- No third-party addon, native portrait model, combat or saved-variable persistence is claimed.
local R, params = TwichUI, SIMLAB_PARAMS or {}
local pose = params.pose or "boss"
A_Admin.SetManualClock(GetTime())
Lab.Solo()
R:SetEnabled("guildLocations", false)
local function Label(parent, text, x, y, size)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont("Fonts\\FRIZQT__.TTF", size or 16, "")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetText(text)
    return t
end
local function Fill(parent, r, g, b)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(parent); t:SetColorTexture(r,g,b,1)
    return t
end
local function UnitFrame(unit, h)
    local f = CreateFrame("Button", nil, UIParent)
    f:SetAttribute("unit", unit)
    f:SetSize(181,h)
    f:SetPoint("CENTER", UIParent, "CENTER", unit == "player" and 90 or 0, 0)
    f:SetScale(2.8)
    f:SetFrameStrata("DIALOG"); f:SetFrameLevel(10)
    Fill(f, 0.07,0.06,0.055)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(h,h)
    p:SetPoint(unit == "player" and "LEFT" or "RIGHT", f, unit == "player" and "LEFT" or "RIGHT", 0,0)
    p:SetFrameLevel(11)
    -- A colored square is intentional: it makes aperture containment directly visible.
    Fill(p,0.16,0.23,0.28)
    Label(p,"Portrait",3,-h/2+4,7)
    f.Portrait = { backdrop = p }
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint(unit == "player" and "TOPRIGHT" or "TOPLEFT", f, unit == "player" and "TOPRIGHT" or "TOPLEFT",0,-3)
    bar:SetSize(181-h-3,h-12); Fill(bar,0.20,0.34,0.18)
    local power = CreateFrame("Frame", nil, f)
    power:SetPoint("BOTTOMLEFT", bar,"BOTTOMLEFT",0,-8); power:SetSize(181-h-3,6); Fill(power,0.12,0.22,0.41)
    local text = CreateFrame("Frame",nil,f); text:SetAllPoints(f); text:SetFrameLevel(30)
    Label(text,unit == "player" and "Player" or "Target",unit == "player" and h+8 or 7,-8,9)
    Label(text,"8,400 / 10,000",unit == "player" and h+8 or 7,-h+19,7)
    return f,p
end
Lab.Step("synthetic portrait setup", function()
    Lab.Check("init","target controller loaded",true,R.TargetArtDisplay ~= nil)
    Lab.Check("init","class controller loaded",true,R.ClassPortraitDisplay ~= nil)
    if pose == "modern-settings" or pose == "legacy-settings" then
        R.TargetArt.Set("style", pose == "legacy-settings" and "legacy" or "modern")
        R:SetEnabled("targetArt", true)
        TwichUIDB.ui.settingsWindow = { w = 1240, h = 960 }
        local ok,_,view = Lab.Open("targetArt")
        Lab.Check("construct","target settings opened",true,ok == true)
        Lab.Check("construct","target settings view exists",true,view ~= nil)
        Lab.Check("state","requested style selected",pose == "legacy-settings" and "legacy" or "modern",R.TargetArt.Get("style"))
        local scale = assert(view.rows.targetArtScale, "legacy scale row retained")
        Lab.Check("construct", "legacy controls visible only for legacy style", pose == "legacy-settings", scale.frame:IsVisible())
        if pose == "legacy-settings" then Lab.Reveal("targetArt","targetArtScale"); Lab.Settle(0.2) end
        return
    end
    local h = pose == "compact" and 36 or pose == "tall" and 76 or 52
    local frame = UnitFrame(pose == "player" and "player" or "target",h)
    local title = CreateFrame("Frame",nil,UIParent); title:SetAllPoints(UIParent); title:SetFrameStrata("TOOLTIP")
    Label(title,"Target Portrait Decorations - " .. pose,70,-70,26)
    Label(title,"Synthetic unit frame / real TwichUI renderer and addon artwork",70,-112,17)
    Label(title,"No native game assets, EllesmereUI, input, combat or reload verification",70,-142,14)
    if pose == "player" then
        EllesmereUIUnitFrames_Player = frame
        R.ClassPortrait.Set("enabled",true)
        R.ClassPortraitDisplay.Refresh()
        Lab.Check("state","class decoration ready","ready",R.ClassPortraitDisplay.Status())
        Lab.Check("state","class texture visible",true,R.ClassPortraitDisplay.Texture():IsShown())
    else
        EllesmereUIUnitFrames_Target = frame
        local classification = pose == "elite" and "elite" or pose == "rare" and "rare" or "worldboss"
        local originalExists = UnitExists
        UnitExists = function(u) if u == "target" then return true end; return originalExists(u) end
        UnitClassification = function() return classification end
        UnitIsBossMob = function() return classification == "worldboss" end
        R.TargetArt.Set("style",pose == "legacy" and "legacy" or "modern")
        R:SetEnabled("targetArt",true)
        R.TargetArtDisplay.Refresh()
        local snap = R.TargetArtDisplay.Snapshot()
        Lab.Check("state","target decoration ready","ready",snap.status)
        Lab.Check("state","classification selected",pose == "elite" and "elite" or pose == "rare" and "rare" or "boss",snap.shown)
        Lab.Check("state","decoration texture visible",true,R.TargetArtDisplay.Texture():IsShown())
        Lab.Check("state","decoration takes no mouse",false,R.TargetArtDisplay.Holder():IsMouseEnabled())
    end
end)
Lab.Settle(0.6)
Lab.Finish()
