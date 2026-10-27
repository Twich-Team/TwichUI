-- TwichUI Layout Setup: the full-size preview
-- The chosen layout drawn over the whole screen at the size and place it would really have, with sample content, so the
-- player can judge it on their own screen before anything is applied. It draws the same scene as the miniature
-- (Scene.lua: the engine's resolved geometry and the pieces inside it) in the same coordinates (UIParent's own units, from
-- the centre of the screen), so what is shown here is what the plan computes and what the install writes.
--
-- What it is, and what it never is:
--   * A preview, and says so: a banner on a bar of controls, a dimmed screen behind, "sample" on everything drawn. Nothing
--     here is a real frame of EllesmereUI's or the game's; the third-party look is illustrated, not reproduced.
--   * Click-through. The covering frame and everything drawn on it take no mouse and no keyboard; only the control bar
--     (Back, Switch layout, Exit, the scenario tabs) does. The game keeps working under it.
--   * Inert. No secure frame, no action button, no spell, no hook into the game; the mock buttons are textures. It writes
--     nothing: no profile, no pick, no saved variable (it reads the model; only a pick or a layout choice the player makes
--     with the controls is remembered, as in the wizard). It fakes no game event.
--   * Out of combat only. It will not open in combat and closes when combat starts. It does not hide or move the live
--     interface (that would mean touching protected frames, and a hidden UIParent hides the preview with it): the screen
--     behind it is dimmed instead, and the bar says so.
--   * Clean. It listens for three events only while it is shown, closes when the wizard closes, when combat starts and
--     when a profile changes, and re-draws on a screen or UI scale change. Its frames are made once and reused.
--
--   Overlay.Open() -> true | false, reason    Overlay.Close("back" | "exit")    Overlay.IsShown()    Overlay.Refresh()

local R = TwichUI
local WZ = R.LayoutWizard
local M = WZ.Model
local Ov = {}
WZ.Overlay = Ov

local FRAME_NAME = "TwichUILayoutOverlay"
local EVENTS = { "PLAYER_REGEN_DISABLED", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }
local MAX_BUTTONS = 14        -- the most button squares a bar element shows
local BAR_W, BAR_H = 700, 116  -- the control bar

local root, bar, scrim, evframe
local panels, elems = {}, {}
Ov.panels, Ov.elems = panels, elems   -- read by the tests
local pendingExit = false
Ov.frames = 0          -- frames and textures kept (for the report)
Ov.listening = 0       -- events registered now (0 while closed)
Ov.builds = 0
Ov.draws = 0
Ov.profileHooks = 0    -- times the profile-change listener was added (once per session)
Ov.last = nil          -- what the last draw put where (read by the tests)

local function Look() return R.Look end
local function Pal() return R.Look.pal end

function Ov.IsShown() return root ~= nil and root:IsShown() end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Tex(parent, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetColorTexture(1, 1, 1, 1)
    Ov.frames = Ov.frames + 1
    return t
end

local function Str(parent, kind)
    local fs = Look().Text(parent, kind or "small")
    fs:SetJustifyH("LEFT")
    Ov.frames = Ov.frames + 1
    return fs
end

local function Color(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or 1) end

local function Panel(id)
    local p = panels[id]
    if p then return p end
    local L, pal = Look(), Pal()
    p = CreateFrame("Frame", nil, root, "BackdropTemplate")
    p:SetFrameLevel(root:GetFrameLevel() + 2)
    p:EnableMouse(false)
    L.Surface(p, pal.surface, 0.55, pal.control, 1)
    p.tag = Str(p, "meta")
    p.tag:SetPoint("TOPLEFT", 4, -3)
    p.lines, p.bars, p.titles = {}, {}, {}
    p.warn = Str(p, "small")
    p.warn:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    p.dot = Tex(p)
    Ov.frames = Ov.frames + 1
    panels[id] = p
    return p
end

local function Elem(id)
    local e = elems[id]
    if e then return e end
    local L, pal = Look(), Pal()
    e = CreateFrame("Frame", nil, root, "BackdropTemplate")
    e:SetFrameLevel(root:GetFrameLevel() + 4)
    e:EnableMouse(false)
    L.Surface(e, pal.well, 0.85, pal.control, 1)
    e.label = Str(e, "meta")
    e.gauge, e.power = Tex(e), Tex(e)   -- (not `fill`: the stand-in frames keep their backdrop colour there)
    e.cells = {}
    Ov.frames = Ov.frames + 1
    elems[id] = e
    return e
end

-- Sample text lines kept in a pool on the panel: line i, made when first needed.
local function Line(p, i, kind)
    local fs = p.lines[i]
    if not fs then fs = Str(p, kind or "small"); p.lines[i] = fs end
    return fs
end

local function HideFrom(list, n)
    for i = n + 1, #list do list[i]:Hide() end
end

---------------------------------------------------------------------------
-- A component's sample content
---------------------------------------------------------------------------
local PAD = 6

local function FillPanel(p, c, acc)
    local pal = Pal()
    local r = c.rect
    p:ClearAllPoints()
    p:SetPoint("CENTER", root, "CENTER", r.x, r.y)
    p:SetSize(r.w, r.h)
    local edge = c.troubled and pal.danger.border or acc
    p:SetBackdropBorderColor(edge[1], edge[2], edge[3], c.troubled and 1 or 0.9)
    p.tag:SetText(c.label .. " (sample)" .. (c.troubled and " !" or "") .. (c.applied and " - not applied" or ""))
    p.tag:SetShown(r.w >= 70 and r.h >= 20)
    p.warn:Hide()
    p.dot:Hide()
    local used = 0   -- lines in use
    local nbar = 0
    local overflow = false
    local s = c.sample
    local top = 20
    if c.kind == "chat" and s then
        for i, text in ipairs(s.lines) do
            local fs = Line(p, i)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(top + (i - 1) * 14))
            fs:SetWidth(math.max(10, r.w - 2 * PAD))
            fs:SetWordWrap(false)
            fs:SetText(text)
            fs:SetTextColor(pal.textDim[1], pal.textDim[2], pal.textDim[3])
            fs:Show()
            used = i
        end
    elseif c.kind == "meter" and s then
        local rows = #s.rows
        local bh = math.max(4, math.min(18, (r.h - top - 4) / rows - 3))
        for i, row in ipairs(s.rows) do
            local t = p.bars[i]
            if not t then t = Tex(p); p.bars[i] = t end
            Color(t, acc, 0.7)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -(top + (i - 1) * (bh + 3)))
            t:SetSize(math.max(1, (r.w - 2 * PAD) * row.frac), bh)
            t:Show()
            nbar = i
            local fs = Line(p, i)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", t, "LEFT", 4, 0)
            fs:SetWidth(math.max(10, r.w - 2 * PAD - 8))
            fs:SetWordWrap(false)
            fs:SetText(row.name)
            fs:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
            fs:Show()
            used = i
        end
    elseif c.kind == "minimap" then
        Color(p.dot, acc, 0.9)
        p.dot:ClearAllPoints()
        p.dot:SetPoint("CENTER", p, "CENTER", 0, 0)
        p.dot:SetSize(10, 10)
        p.dot:Show()
    elseif c.kind == "objectives" and s then
        local y = top
        local n = 0
        local width = math.max(20, r.w - 2 * PAD)
        for _, q in ipairs(s.quests) do
            n = n + 1
            local title = Line(p, n, "body")
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -y)
            title:SetWidth(width)
            title:SetWordWrap(true)
            title:SetText(q.title)
            title:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
            title:Show()
            y = y + (title:GetStringHeight() or 14) + 2
            for _, text in ipairs(q.lines) do
                n = n + 1
                local fs = Line(p, n)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", p, "TOPLEFT", PAD + 8, -y)
                fs:SetWidth(math.max(10, width - 8))
                fs:SetWordWrap(true)
                fs:SetText(text)
                fs:SetTextColor(pal.textDim[1], pal.textDim[2], pal.textDim[3])
                fs:Show()
                y = y + (fs:GetStringHeight() or 12) + 2
            end
            y = y + 6
        end
        used = n
        -- the text asked for more height than the box has: said, not hidden (the box is where the layout leaves room)
        overflow = y - 6 > r.h
        if overflow then
            p.warn:ClearAllPoints()
            p.warn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, 3)
            p.warn:SetText("The text runs past this box.")
            p.warn:Show()
        end
    elseif c.kind == "notifications" then
        local fs = Line(p, 1)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", p, "CENTER", 0, 0)
        fs:SetWidth(math.max(10, r.w - 2 * PAD))
        fs:SetText("TwichUI's cards appear here")
        fs:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
        fs:Show()
        used = 1
    end
    HideFrom(p.lines, used)
    HideFrom(p.bars, nbar)
    p:Show()
    return overflow
end

---------------------------------------------------------------------------
-- A piece inside a component: a unit frame, a bar, a cast bar, the party frames, a TwichUI marker
---------------------------------------------------------------------------
local FILL = { unit = { "bronzeText", 0.40 }, cast = { "well", 0.9 }, bar = { "well", 0.85 }, party = { "well", 0.85 },
    marker = { "tealLo", 0.9 } }

local function FillElem(e, piece, acc)
    local pal = Pal()
    local r = piece.rect
    local fill = FILL[piece.kind] or FILL.bar
    e:ClearAllPoints()
    e:SetPoint("CENTER", root, "CENTER", r.x, r.y)
    e:SetSize(r.w, r.h)
    local f = pal[fill[1]] or pal.well
    e.gauge:Hide()
    e.power:Hide()
    HideFrom(e.cells, 0)
    local edge = piece.kind == "marker" and pal.tealHi or pal.control
    e:SetBackdropColor(f[1], f[2], f[3], fill[2])
    e:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    if piece.kind == "unit" then
        Color(e.gauge, acc, 0.7)
        e.gauge:ClearAllPoints()
        e.gauge:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -1)
        e.gauge:SetSize(math.max(1, (r.w - 2) * 0.72), math.max(1, (r.h - 2) * 0.78))
        e.gauge:Show()
        Color(e.power, pal.stone, 0.6)
        e.power:ClearAllPoints()
        e.power:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 1, 1)
        e.power:SetSize(math.max(1, r.w - 2), math.max(1, (r.h - 2) * 0.16))
        e.power:Show()
    elseif piece.kind == "cast" then
        Color(e.gauge, acc, 0.75)
        e.gauge:ClearAllPoints()
        e.gauge:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -1)
        e.gauge:SetSize(math.max(1, (r.w - 2) * 0.6), math.max(1, r.h - 2))
        e.gauge:Show()
    elseif piece.kind == "bar" then
        local horizontal = r.w >= r.h
        local long, short = horizontal and r.w or r.h, horizontal and r.h or r.w
        local n = math.max(1, math.min(MAX_BUTTONS, math.floor(long / math.max(1, short) + 0.5)))
        local step = long / n
        for i = 1, n do
            local t = e.cells[i]
            if not t then t = Tex(e); e.cells[i] = t end
            Color(t, pal.stone, 0.4)
            t:ClearAllPoints()
            if horizontal then
                t:SetPoint("TOPLEFT", e, "TOPLEFT", (i - 1) * step + 1, -1)
                t:SetSize(math.max(1, step - 2), math.max(1, short - 2))
            else
                t:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -((i - 1) * step + 1))
                t:SetSize(math.max(1, short - 2), math.max(1, step - 2))
            end
            t:Show()
        end
    elseif piece.kind == "party" then
        local horizontal = r.w > r.h
        local step = (horizontal and r.w or r.h) / 5
        for i = 1, 5 do
            local t = e.cells[i]
            if not t then t = Tex(e); e.cells[i] = t end
            Color(t, acc, 0.5)
            t:ClearAllPoints()
            if horizontal then
                t:SetPoint("TOPLEFT", e, "TOPLEFT", (i - 1) * step + 1, -1)
                t:SetSize(math.max(1, step - 2), math.max(1, r.h - 2))
            else
                t:SetPoint("TOPLEFT", e, "TOPLEFT", 1, -((i - 1) * step + 1))
                t:SetSize(math.max(1, r.w - 2), math.max(1, step - 2))
            end
            t:Show()
        end
    end
    -- the label: inside a piece that is big enough, beside a marker
    e.label:ClearAllPoints()
    if piece.kind == "marker" then
        e.label:SetPoint("LEFT", e, "RIGHT", 4, 0)
        e.label:SetText(piece.label)
        e.label:SetTextColor(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3])
        e.label:Show()
    elseif r.w >= 90 and r.h >= 18 and piece.kind ~= "party" then
        e.label:SetPoint("LEFT", e, "LEFT", 5, 0)
        e.label:SetText(piece.label)
        e.label:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
        e.label:Show()
    elseif piece.kind == "party" then
        e.label:SetPoint("BOTTOM", e, "TOP", 0, 2)
        e.label:SetText("Party frames (arrangement is a sample)")
        e.label:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
        e.label:Show()
    else
        e.label:Hide()
    end
    e:Show()
end

---------------------------------------------------------------------------
-- The tooltip, in the game's default place
---------------------------------------------------------------------------
local function FillTooltip(scene)
    local pal = Pal()
    local tip = panels.tooltip
    if not scene.tooltip then
        if tip then tip:Hide() end
        return
    end
    tip = Panel("tooltip")
    local r = scene.tooltip.rect
    tip:ClearAllPoints()
    tip:SetPoint("CENTER", root, "CENTER", r.x, r.y)
    tip:SetSize(r.w, r.h)
    tip:SetBackdropColor(pal.well[1], pal.well[2], pal.well[3], 0.97)
    tip:SetBackdropBorderColor(pal.stone[1], pal.stone[2], pal.stone[3], 1)
    tip.tag:SetText("Tooltip (sample)")
    tip.tag:Show()
    tip.warn:Hide()
    tip.dot:Hide()
    HideFrom(tip.bars, 0)
    for i, text in ipairs(scene.tooltip.lines) do
        local fs = Line(tip, i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", tip, "TOPLEFT", PAD, -(18 + (i - 1) * 14))
        fs:SetWidth(math.max(10, r.w - 2 * PAD))
        fs:SetWordWrap(false)
        fs:SetText(text)
        fs:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
        fs:Show()
    end
    HideFrom(tip.lines, #scene.tooltip.lines)
    tip:Show()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Draw(scene, acc)
    local pal = Pal()
    local last = { components = {}, elements = {}, overflow = {}, scenario = scene.scenario, variant = scene.variant,
        screen = { w = scene.screen.w, h = scene.screen.h } }
    for _, c in ipairs(scene.components) do
        local p = Panel(c.id)
        local overflow = FillPanel(p, c, acc)
        last.components[c.id] = { x = c.rect.x, y = c.rect.y, w = c.rect.w, h = c.rect.h }
        if overflow then last.overflow[c.id] = true end
    end
    for _, e in ipairs(scene.elements) do
        FillElem(Elem(e.id), e, acc)
        last.elements[e.id] = { x = e.rect.x, y = e.rect.y, w = e.rect.w, h = e.rect.h }
    end
    for id, p in pairs(panels) do
        if id ~= "tooltip" and not last.components[id] then p:Hide() end
    end
    for id, e in pairs(elems) do
        if not last.elements[id] then e:Hide() end
    end
    FillTooltip(scene)
    if scene.tooltip then last.tooltip = { x = scene.tooltip.rect.x, y = scene.tooltip.rect.y, w = scene.tooltip.rect.w, h = scene.tooltip.rect.h } end
    Ov.last = last
    Ov.draws = Ov.draws + 1
    return pal
end

local function PaintBar(scene)
    local pal = Pal()
    local layout = M.Layout()
    local other = M.OtherLayout()
    bar.banner:SetText("PREVIEW   " .. layout.title .. " - nothing is applied")
    bar.switch.text:SetText(other and ("Switch to " .. other.short) or "Switch layout")
    bar.switch:SetEnabled(other ~= nil)
    for id, tab in pairs(bar.tabs) do tab:SetSelected(id == scene.scenario) end
    if scene.fits then
        bar.fit:SetText("")
        bar.fit:Hide()
    else
        bar.fit:SetText("Doesn't fit this screen: " .. table.concat(M.FitLines(scene.geo, 2), " "))
        bar.fit:Show()
    end
    local hint = ""
    for _, sc in ipairs(WZ.Scene.SCENARIOS) do if sc.id == scene.scenario then hint = sc.hint end end
    bar.hint:SetText(hint .. (scene.hidden > 0 and (" (" .. scene.hidden .. " pieces stay out of this scene.)") or ""))
    return pal
end

function Ov.Refresh()
    if not Ov.IsShown() then return end
    if not M.Active() then Ov.Close("exit") return end
    local scene = M.Scene()
    if not scene then Ov.Close("back") return end
    local accent, o = M.Accent()
    if not accent and o and o.id == "class" then accent = WZ.ClassColor and WZ.ClassColor() end
    local acc = accent or Pal().teal
    R.Perf.Call("layoutwizard.overlay", Draw, scene, acc)
    PaintBar(scene)
end

---------------------------------------------------------------------------
-- Building, opening, closing
---------------------------------------------------------------------------
local function Listen(on)
    if not evframe then return end
    if on then
        if Ov.listening == 0 then
            for _, e in ipairs(EVENTS) do evframe:RegisterEvent(e) end
            Ov.listening = #EVENTS
        end
    elseif Ov.listening > 0 then
        for _, e in ipairs(EVENTS) do evframe:UnregisterEvent(e) end
        Ov.listening = 0
    end
end

local function OnEvent(_, event)
    if not Ov.IsShown() then return end
    if event == "PLAYER_REGEN_DISABLED" then
        Ov.Close("back")   -- no preview in combat; the wizard says why
    else
        M.Invalidate()
        Ov.Refresh()
    end
end

-- The player's profile changed under the open preview: what the wizard worked out is stale, so close and go back to it.
function Ov.OnProfileChange()
    if not Ov.IsShown() then return end
    M.Invalidate()
    Ov.Close("back")
end

local function Build()
    local L, pal = Look(), Pal()
    Ov.builds = Ov.builds + 1
    root = CreateFrame("Frame", FRAME_NAME, UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("FULLSCREEN_DIALOG")
    root:EnableMouse(false)            -- click-through: the game keeps working under the preview
    root:EnableKeyboard(false)
    root:Hide()
    scrim = root:CreateTexture(nil, "BACKGROUND")
    scrim:SetColorTexture(0.03, 0.025, 0.02, 0.78)
    scrim:SetAllPoints(root)
    Ov.frames = Ov.frames + 2
    -- Escape: the game's own list, once (the settings window's rule: never the game menu's Escape handler table). It is listed after the wizard's window, so
    -- one Escape closes the preview and the wizard it returns to is not closed by the same press.
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then listed = true end end
    if not listed then tinsert(UISpecialFrames, FRAME_NAME) end

    -- the control bar: the only part of the preview that takes the mouse
    bar = CreateFrame("Frame", nil, root, "BackdropTemplate")
    bar:SetSize(BAR_W, BAR_H)
    bar:SetPoint("TOP", root, "TOP", 0, -8)
    bar:SetFrameLevel(root:GetFrameLevel() + 20)
    bar:EnableMouse(true)
    L.Surface(bar, pal.band, 0.97, pal.rimLo, 1)
    bar.banner = L.Text(bar, "heading")
    bar.banner:SetPoint("TOPLEFT", 12, -10)
    bar.banner:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
    bar.note = L.Text(bar, "small")
    bar.note:SetWidth(BAR_W - 24)
    bar.note:SetWordWrap(true)
    bar.note:SetJustifyH("LEFT")
    bar.note:SetPoint("TOPLEFT", bar.banner, "BOTTOMLEFT", 0, -4)
    bar.note:SetText("Sample content at the size and place this layout would give it. Your interface is dimmed behind it, not hidden or moved, and you can click through it. EllesmereUI draws the real frames; nothing here acts.")
    bar.hint = L.Text(bar, "small")
    bar.hint:SetWidth(BAR_W - 24)
    bar.hint:SetJustifyH("LEFT")
    bar.hint:SetPoint("TOPLEFT", bar.note, "BOTTOMLEFT", 0, -3)
    bar.fit = L.Text(bar, "small")
    bar.fit:SetWidth(BAR_W - 24)
    bar.fit:SetWordWrap(true)
    bar.fit:SetJustifyH("LEFT")
    bar.fit:SetTextColor(pal.danger.text[1], pal.danger.text[2], pal.danger.text[3])
    bar.fit:SetPoint("TOPLEFT", bar.hint, "BOTTOMLEFT", 0, -3)
    bar.tabs = {}
    local x = 12
    local WIDTHS = { solo = 52, target = 62, party = 58, objectives = 88, tooltip = 66 }
    for _, sc in ipairs(WZ.Scene.SCENARIOS) do
        local w = WIDTHS[sc.id] or 64
        local tab = L.Tab(bar, sc.short, w, function() M.SetScenario(sc.id) Ov.Refresh() end)
        tab:SetPoint("BOTTOMLEFT", x, 10)
        R.Interact.Tip(tab, sc.label, sc.hint)
        bar.tabs[sc.id] = tab
        x = x + w + 2
    end
    bar.exit = L.Button(bar, "Exit", 64, "secondary", function() Ov.Close("exit") end)
    bar.exit:SetHeight(24)
    bar.exit:SetPoint("BOTTOMRIGHT", -12, 10)
    R.Interact.Tip(bar.exit, "Exit", "Closes the preview and the setup. Nothing was changed; your choices are remembered.")
    bar.switch = L.Button(bar, "Switch layout", 140, "secondary", function()
        local other = M.OtherLayout()
        if other then M.SetLayout(other.id) end
        Ov.Refresh()
    end)
    bar.switch:SetHeight(24)
    bar.switch:SetPoint("RIGHT", bar.exit, "LEFT", -6, 0)
    R.Interact.Tip(bar.switch, "Switch layout", "Shows the other layout here. This only changes what you are looking at (and which one the setup will offer to apply); nothing is applied.")
    bar.back = L.Button(bar, "Back", 64, "primary", function() Ov.Close("back") end)
    bar.back:SetHeight(24)
    bar.back:SetPoint("RIGHT", bar.switch, "LEFT", -6, 0)
    R.Interact.Tip(bar.back, "Back", "Returns to the setup, where you left it.")
    Ov.frames = Ov.frames + 14

    evframe = CreateFrame("Frame")
    evframe:SetScript("OnEvent", OnEvent)
    Ov.evframe = evframe   -- read by the tests
    Ov.root, Ov.bar = root, bar

    root:HookScript("OnHide", function()
        Listen(false)
        local exit = pendingExit
        pendingExit = false
        if not M.Active() then return end
        if exit then WZ.Window.Close() else WZ.Window.Resume() end
    end)

    -- a profile change closes the preview: one listener for the whole session, added once
    if R.Profiles and R.Profiles.OnChange and Ov.profileHooks == 0 then
        Ov.profileHooks = 1
        R.Profiles.OnChange(function() Ov.OnProfileChange() end)
    end
end

-- Opens the preview over the screen and sets the wizard's window aside (its session goes on). Returns true | false, reason.
function Ov.Open()
    local why = M.OverlayBlock()
    if why then return false, why end
    if not WZ.Window.IsShown() then return false, "The setup isn't open." end
    if not root then R.Perf.Call("layoutwizard.overlay.build", Build) end
    if not M.Scene() then return false, M.OverlayBlock() or "TwichUI couldn't work out the layout for this screen." end
    WZ.Window.Suspend()
    root:Show()
    Listen(true)
    Ov.Refresh()
    return true
end

-- how: "back" returns to the wizard where it was left; "exit" closes the wizard too. Changes nothing in the game.
function Ov.Close(how)
    if not root then return end
    pendingExit = how == "exit"
    if root:IsShown() then root:Hide() else pendingExit = false end
end

R.Perf.Gauge("layoutwizard.overlay.events", { label = "Layout setup preview: events registered (0 while closed)", unit = "count", kind = "listeners",
    group = "layouts", read = function() return Ov.listening end })
R.Perf.Gauge("layoutwizard.overlay.frames", { label = "Layout setup preview: frames and textures kept", unit = "count", kind = "pool",
    group = "layouts", read = function() return Ov.frames end })
