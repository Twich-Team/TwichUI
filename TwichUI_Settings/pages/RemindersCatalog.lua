-- TwichUI settings: the Reminders template catalog. A frame beside the settings window (R.SettingsAnchor, as the sample
-- previews do) listing the templates as cards: a picture, a name, a line about it and "Use template"; and "Custom
-- reminder" under them. Choosing one goes through the page's own P.Create, which makes the reminder by the same checked
-- path as before (reminders/Config.lua RM.Create: a fresh copy, its own id, turned off), selects it and opens its editor.
-- A refusal (the limit, a newer profile) is said here and the catalog stays open. Closing it, by its box, Esc or the
-- settings window closing, makes and changes nothing. Searching and filtering are not here yet.

local R = TwichUI
local C = {}
R.RemindersCatalog = C

local WIDTH, PAD, GAP = 420, 16, 10
local CARD_W = (WIDTH - PAD * 2 - GAP) / 2
local CARD_H, THUMB = 132, 40
local HEADER = 64
local NAME = "TwichUIReminderCatalog"

local f
local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end

-- The template's own picture: its artwork where it has some, else the feature's icon.
local function Picture(tex, kind)
    local d = RM().TemplateDisplay(kind) or {}
    tex:SetVertexColor(1, 1, 1, 1)
    if (d.mode == "artwork" or d.mode == "artworkText") and RM().Art(d.art) then
        local file, l, r, t, b, aspect = RM().ArtTexture(d.art, THUMB)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(math.max(1, math.floor(THUMB * math.min(1, aspect) + 0.5)), math.floor(THUMB / math.max(1, aspect) + 0.5))
        return
    end
    tex:SetSize(THUMB, THUMB)
    if d.iconSource == "item" then
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif R.Icons then
        R.Icons.Apply(tex, d.icon or "reminders", THUMB)
    end
end

function C.Say(text, tone)
    if not f then return end
    f.say:SetText(text or "")
    local G = Wg()
    G.Color(f.say, tone == "warn" and G.pal.danger.text or G.pal.textDim)
end

-- Used by the cards and the custom row. The page makes it; on success this goes away, on a refusal it stays and says why.
local function Use(kind)
    local P = R.RemindersPage
    if not P then return end
    local ok, why = P.Create(kind)
    if ok then C.Hide() else C.Say(why, "warn") end
end

local function Build()
    local G, F = Wg(), R.FrameLook
    f = CreateFrame("Frame", NAME, UIParent)
    f:SetSize(WIDTH, 100)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    if F and F.Ready() then f.shell = F.Shell(f, { below = true, follow = true }) end
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it, as it does any other frame there

    f.title = G.Text(f, "heading")
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetText("Create a reminder")
    f.sub = G.Text(f, "small")
    f.sub:SetPoint("TOPLEFT", PAD, -38)
    f.sub:SetText("Start with a template. Make it yours.")
    local close = F and F.Ready() and F.Close(f, function() C.Hide() end)
        or G.Button(f, "X", 24, "secondary", function() C.Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)

    f.cards = {}
    local n = 0
    for _, t in ipairs(RM().TEMPLATES) do
        if t[1] ~= "custom" then
            n = n + 1
            local kind = t[1]
            local card = CreateFrame("Frame", nil, f)
            card:SetSize(CARD_W, CARD_H)
            local col, row = (n - 1) % 2, math.floor((n - 1) / 2)
            card:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + col * (CARD_W + GAP), -(HEADER + row * (CARD_H + GAP)))
            card.kind = kind
            card.thumb = card:CreateTexture(nil, "ARTWORK")
            card.thumb:SetPoint("TOPLEFT", 8, -8)
            Picture(card.thumb, kind)
            card.name = G.Text(card, "body")
            card.name:SetPoint("TOPLEFT", THUMB + 18, -10)
            card.name:SetWidth(CARD_W - THUMB - 26)
            card.name:SetJustifyH("LEFT")
            card.name:SetText(t[2])
            card.brief = G.Text(card, "small")
            card.brief:SetPoint("TOPLEFT", 10, -(THUMB + 16))
            card.brief:SetWidth(CARD_W - 20)
            card.brief:SetJustifyH("LEFT")
            card.brief:SetText(t[4] or "")
            card.use = G.Button(card, "Use template", CARD_W - 20, "secondary", function() Use(kind) end)
            card.use:SetPoint("BOTTOMLEFT", 10, 10)
            R.Interact.Tip(card.use, t[2], t[3] .. " It starts turned off.")
            f.cards[#f.cards + 1] = card
        end
    end
    local rowsUsed = math.ceil(n / 2)
    local y = HEADER + rowsUsed * (CARD_H + GAP)
    f.custom = G.Button(f, "Custom reminder", WIDTH - PAD * 2, "secondary", function() Use("custom") end)
    f.custom:SetPoint("TOPLEFT", PAD, -y)
    R.Interact.Tip(f.custom, "Custom reminder", "Starts with your own conditions and words, with nothing chosen yet. It starts turned off.")
    f.customNote = G.Text(f, "small")
    f.customNote:SetPoint("TOPLEFT", PAD, -(y + 34))
    f.customNote:SetText("Start with your own conditions.")
    f.say = G.Text(f, "small")
    f.say:SetPoint("TOPLEFT", PAD, -(y + 58))
    f.say:SetWidth(WIDTH - PAD * 2)
    f.say:SetJustifyH("LEFT")
    f:SetHeight(y + 82)
end

function C.Shown() return f ~= nil and f:IsShown() end
function C.Frame() return f end

-- Away, and the page draws the preview for the selection again (the companion place is the catalog's until then).
function C.Hide()
    if not C.Shown() then return end
    f:Hide()
    if R.RemindersPage then R.RemindersPage.QueueRefresh() end
end

-- Opens it beside the settings window (centered if that is not up), or puts it away.
function C.Toggle()
    if C.Shown() then C.Hide() return end
    if not f then Build() end
    C.Say("")
    if R.RemindersPreview then R.RemindersPreview.Hide() end   -- the companion place holds one thing at a time
    if R.RemindersPreview then R.RemindersPreview.Place(f) end
    f:Show()
end

if R.OnSettingsClosed then R.OnSettingsClosed(C.Hide) end
