-- TwichUI settings: the Reminders live preview. A frame beside the settings window (the place the template catalog also
-- uses; only one of them is up at a time) showing how the chosen reminder looks, drawn by the reminder's own layout code
-- (reminders/Display.lua D.NewSurface and D.DrawSurface, the same drawing the inline preview used), with the explicit
-- "Show on screen" button that puts it in the world, marked Preview. It draws whatever the reminder's conditions or its
-- switch say: a turned-off reminder is previewed without being turned on, and nothing here plays a sound, reads a
-- condition or changes a setting. The page (Reminders.lua) shows it from its own redraw and hides it when it goes.
--
--   PV.Place(frame)         puts a companion frame beside the settings window (shared with the catalog)
--   PV.Show(view, hooks)    shows or redraws it for `view`; hooks = { Changed(), Say(text, tone) }
--   PV.Hide(), PV.Shown(), PV.Parts()

local R = TwichUI
local PV = {}
R.RemindersPreview = PV

local WIDTH, PAD, BOX_H = 360, 16, 200
local f, hooks

local function Wg() return R.SettingsWidgets end
local function D() return R.ReminderDisplay end

-- Beside the window on its right; on its left when there is no room on the right; centred when the window isn't up.
function PV.Place(frame)
    frame:ClearAllPoints()
    local anchor = R.SettingsAnchor and R.SettingsAnchor()
    if not anchor then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    local right, aScale, uiRight, uiScale = anchor.GetRight and anchor:GetRight(), anchor.GetEffectiveScale and anchor:GetEffectiveScale(),
        UIParent.GetRight and UIParent:GetRight(), UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    local fScale = frame.GetEffectiveScale and frame:GetEffectiveScale()
    local wide = frame:GetWidth() or WIDTH
    if type(right) == "number" and type(aScale) == "number" and type(uiRight) == "number" and type(uiScale) == "number"
        and type(fScale) == "number" and fScale > 0 and right * aScale + (8 + wide) * fScale > uiRight * uiScale then
        frame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -8, -48)
    else
        frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, -48)
    end
end

local function Build()
    local G, F = Wg(), R.FrameLook
    f = CreateFrame("Frame", "TwichUIReminderPreview", UIParent)
    f:SetSize(WIDTH, 100)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    if F and F.Ready() then f.shell = F.Shell(f, { below = true, follow = true }) end

    f.title = G.Text(f, "heading")
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetWidth(WIDTH - PAD * 2)
    f.title:SetJustifyH("LEFT")
    f.sub = G.Text(f, "small")
    f.sub:SetPoint("TOPLEFT", PAD, -38)
    f.sub:SetWidth(WIDTH - PAD * 2)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetText("Shown whatever its conditions say. Nothing about it changes.")

    f.box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.box:SetSize(WIDTH - PAD * 2, BOX_H)
    f.box:SetPoint("TOPLEFT", PAD, -62)
    G.Well(f.box)
    f.surface = D().NewSurface(f.box)
    f.surface:SetPoint("CENTER", f.box, "CENTER", 0, 0)
    f.tag = G.Tag(f.box, "PREVIEW")
    f.tag:SetPoint("TOPLEFT", 6, -6)
    f.caption = G.Text(f, "small")
    f.caption:SetPoint("TOPLEFT", PAD, -(62 + BOX_H + 8))
    f.caption:SetWidth(WIDTH - PAD * 2)
    f.caption:SetJustifyH("LEFT")

    f.show = G.Button(f, "Show on screen", 150, "secondary", function()
        local v = f.view
        if not v then return end
        if D().PreviewId() == v.id then D().PreviewStop()
        elseif not D().PreviewStart(v, false) and hooks and hooks.Say then
            hooks.Say("The preview waits until you are out of combat.", "warn")
        end
        if hooks and hooks.Changed then hooks.Changed() end
    end)
    R.Interact.Tip(f.show, "Show on screen", "Shows it where it sits, marked Preview, whatever its conditions say. Nothing about your equipment or its rules changes. It ends when you close these settings, enter combat, turn Reminders off or delete it.")
    f.state = G.Text(f, "small")
    f.state:SetWidth(WIDTH - PAD * 2 - 162)
    f.state:SetJustifyH("LEFT")
    f:SetHeight(62 + BOX_H + 8 + 44 + 44)
end

function PV.Shown() return f ~= nil and f:IsShown() end
function PV.Parts() return f end

function PV.Hide()
    if f then f.view = nil f:Hide() end
end

function PV.Show(view, h)
    if not view then PV.Hide() return end
    hooks = h or hooks
    if not f then Build() end
    local G = Wg()
    f.view = view
    f.title:SetText(view.name)
    local _, _, scale = D().DrawSurface(f.surface, view, WIDTH - PAD * 2 - 24, BOX_H - 24)
    f.surface:Show()
    local words = scale < 1 and ("Shown here at %d%% of its size, to fit the box."):format(math.floor(scale * 100)) or "Shown here at its own size."
    if not view.enabled then words = words .. " It is turned off; this is only how it looks." end
    if not view.valid then words = words .. " It can't show in the world until what is listed on the page is fixed." end
    f.caption:SetText(words)
    local on = D().PreviewId() == view.id
    f.show.text:SetText(on and "Hide preview" or "Show on screen")
    f.show:ClearAllPoints()
    f.show:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(62 + BOX_H + 8 + 40))
    f.state:ClearAllPoints()
    f.state:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 162, -(62 + BOX_H + 8 + 44))
    f.state:SetText(on and (D().Positioning() and "On screen now, with a handle to drag." or "On screen now, marked Preview.") or "")
    G.Color(f.state, G.pal.sage)
    if not f:IsShown() then
        PV.Place(f)
        f:Show()
    end
end

if R.OnSettingsClosed then R.OnSettingsClosed(PV.Hide) end
