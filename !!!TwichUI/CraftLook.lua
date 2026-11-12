-- TwichUI: the crafted look's shared pieces (painted sheets, quiet leather, controls)
-- The approved settings look (docs/settings-design-system.md) in the core, so a load-on-demand window can draw with it without the
-- settings window being loaded: the Workshop uses it directly, and TwichUI_Settings keeps its own names for the same functions
-- (R.SettingsCraft is this table; R.SettingsMaterial delegates its primitives here). Artwork owns relief; native frames own input and
-- geometry. Textures only: nothing here takes the mouse on its own, runs per frame, reads or writes saved data, or knows a page or a
-- feature. Nothing is made until a window asks for it.
--
--   CL.Sheet(host, skin, opts)          nine textures from a painted sheet (media\style-v2\craft\<skin>.tga): fixed corners, edges stretch
--                                       along their length. opts: layer, sub, corner, inset (number or { l, t, r, b }), bounds. :SetSkin,
--                                       :SetShown, :SetAlpha, :SetTint, :Show, :Hide
--   CL.Frame(host)                      the sculpted bronze window frame (the "frame" sheet) over a shell
--   CL.LegacyRails(shell, shown)        shows or hides FrameLook's original rails under it
--   CL.Control(control, kind, when)     paints a button / field / segment / chip from its sheet family with hover, pressed and disabled states;
--                                       kind: nil (button), "primary"/"confirmation", "danger", "field", "dropdown", "segment", "chip", "target"
--   CL.Thumb(texture)                   the painted slider / scroll thumb
--   CL.FILE                             the material files (style-v2 and the quiet Reminders materials)
--   CL.Tile(host, layer, sub, which, alpha, tint)   a tiled material over the host
--   CL.Slice(host, kind, layer, sub, ins, radius)   a rounded container from a nine-slice material sheet
--   CL.QuietTile(host, role, layer, sub), CL.QuietGrain(frame, role)   the quiet leather grain (whole / inside a rounded face)
--   CL.PanelFace(frame, kind)           a card ("card"/"walnut"), editor ("editor"), well ("canvas") or dark ("espresso") surface with its rim
--   CL.Font(text, size, ivory, role)    Spectral (headings, 17 and up, or role "serif") / Alegreya Sans (role "strong": bold) at `size`;
--                                       the game's own font for Korean, Chinese and Russian
--   CL.NavItem(item)                    item.sel / item.hover: the chosen and hovered navigation row
--   CL.Dress(control, kind)             CL.Control plus the control font (the settings window's ReminderControl)
--   CL.Segment(parent, label, w, onClick)   a tab / segment (b:SetSelected)
--   CL.Pill(parent, onToggle, small)    the switch (b:SetChecked, :GetChecked, :SetActive, :SetHot); under 26 units wide a square check
--   CL.SearchDecoration(box, placeholder)   a search field's magnifier and placeholder
--   CL.ScrollRail(scroll, active, motion)   paints a template scroll bar (native hit regions kept); motion(scroll, active) adds wheel easing

local R = TwichUI
local CL = {}
R.CraftLook = CL

local function Look() return R.Look end
local CRAFT = R.PATH .. [[media\style-v2\craft\]]
local DIR = R.PATH .. [[media\style-v2\]]

---------------------------------------------------------------------------
-- Painted sheets and controls (moved from TwichUI_Settings/Craft.lua; R.SettingsCraft is this table)
---------------------------------------------------------------------------
-- Fixed UI corners with independent horizontal/vertical source cuts. Edges stretch only along their length.
function CL.Sheet(host, skin, opts)
    opts = opts or {}
    local frame = skin == "frame"
    local selected = skin:find("selection", 1, true) ~= nil or skin:find("segment", 1, true) ~= nil
    local chip = skin:find("chip", 1, true) ~= nil
    local u = chip and 1 / 4 or frame and 1 / 8 or selected and 1 / 8 or 1 / 16
    local v = chip and 1 / 2 or frame and 1 / 8 or selected and 3 / 8 or 1 / 4
    local corner = opts.corner or (frame and 24 or 8)
    local ins = opts.inset or 0
    local left, top, right, bottom
    if type(ins) == "table" then left, top, right, bottom = ins[1], ins[2], ins[3], ins[4]
    else left, top, right, bottom = ins, ins, ins, ins end
    local uvx, uvy = { 0, u, 1 - u, 1 }, { 0, v, 1 - v, 1 }
    local x = { { "LEFT", left }, { "LEFT", left + corner }, { "RIGHT", -(right + corner) }, { "RIGHT", -right } }
    local y = { { "TOP", -top }, { "TOP", -(top + corner) }, { "BOTTOM", bottom + corner }, { "BOTTOM", bottom } }
    local group = { parts = {}, skin = nil }
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = host:CreateTexture(nil, opts.layer or "ARTWORK", nil, opts.sub or 1)
            texture:SetTexCoord(uvx[col], uvx[col + 1], uvy[row], uvy[row + 1])
            texture:SetPoint("TOPLEFT", host, y[row][1] .. x[col][1], x[col][2], y[row][2])
            texture:SetPoint("BOTTOMRIGHT", host, y[row + 1][1] .. x[col + 1][1], x[col + 1][2], y[row + 1][2])
            if opts.bounds then
                local b = opts.bounds
                local bx = { b[1], b[1] + corner, b[3] - corner, b[3] }
                local by = { b[2], b[2] - corner, b[4] + corner, b[4] }
                texture:ClearAllPoints()
                texture:SetPoint("TOPLEFT", host, "TOPLEFT", bx[col], by[row])
                texture:SetPoint("BOTTOMRIGHT", host, "TOPLEFT", bx[col + 1], by[row + 1])
            end
            group.parts[#group.parts + 1] = texture
        end
    end
    function group:SetSkin(value)
        if value == self.skin then return end
        self.skin = value
        for _, texture in ipairs(self.parts) do texture:SetTexture(CRAFT .. value .. ".tga") end
    end
    function group:SetShown(on) for _, texture in ipairs(self.parts) do texture:SetShown(on and true or false) end end
    function group:SetAlpha(alpha) for _, texture in ipairs(self.parts) do texture:SetAlpha(alpha) end end
    function group:SetTint(r, g, b, alpha)
        for _, texture in ipairs(self.parts) do texture:SetVertexColor(r, g, b, alpha or 1) end
    end
    function group:Show() self:SetShown(true) end
    function group:Hide() self:SetShown(false) end
    group:SetSkin(skin)
    return group
end

function CL.Frame(host)
    return CL.Sheet(host, "frame", { layer = "OVERLAY", sub = 5 })
end

-- The original shell is kept for restoration. SetAlpha avoids its resize hook reshowing old rails.
function CL.LegacyRails(shell, shown)
    for _, set in ipairs({ shell.corner or {}, shell.edge or {} }) do
        for _, texture in pairs(set) do texture:SetAlpha(shown and 1 or 0) end
    end
end

function CL.Control(control, kind, when)
    if control.twichCraft then
        if control.twichCraft.Retype then control.twichCraft.Retype(kind) end
        return control.twichCraft
    end
    local field = kind == "field" or kind == "dropdown" or kind == "drop" or kind == "target"
    local primary = kind == "primary" or kind == "confirmation"
    local danger = kind == "danger"
    local selectedFamily = kind == "segment"
    -- One silhouette per family, including disabled/pressed states. Selection has its own painted source.
    local sheet = CL.Sheet(control, kind == "chip" and "chip" or selectedFamily and "selection" or field and "field" or "button",
        { layer = "ARTWORK", sub = 4, corner = kind == "chip" and 12 or 8 })
    control.twichCraft = sheet
    if kind == "target" then
        -- Let a caller's dashed insertion outline carry the edge, rather than a solid button rim.
        for i, texture in ipairs(sheet.parts) do texture:SetAlpha(i == 5 and 0.55 or 0) end
        sheet.parts[5]:ClearAllPoints()
        sheet.parts[5]:SetAllPoints(control)
    end
    local bevel = control.twichLook and control.twichLook.bevel
    local function Bevel(alpha)
        for _, part in pairs(bevel or {}) do
            if part.SetAlpha then part:SetAlpha(alpha) else for _, texture in pairs(part) do texture:SetAlpha(alpha) end end
        end
    end
    local bg = control.GetBackdropColor and { control:GetBackdropColor() } or {}
    local edge = control.GetBackdropBorderColor and { control:GetBackdropBorderColor() } or {}
    local originalInk = kind == "field" and { control:GetTextColor() } or {}
    local over, down, wasActive = false, false, false
    local function Paint()
        if when and not when() then
            sheet:Hide()
            if wasActive then
                Bevel(1)
                if control.Repaint then control:Repaint()
                else
                    local pal = Look().pal
                    control:SetBackdropColor(unpack(bg[1] and bg or { pal.well[1], pal.well[2], pal.well[3], 1 }))
                    control:SetBackdropBorderColor(unpack(edge[1] and edge or { pal.control[1], pal.control[2], pal.control[3], 1 }))
                end
                if control.PaintEdge then control:PaintEdge() end
                if originalInk[1] then control:SetTextColor(unpack(originalInk)) end
                if control.twichLook then control.twichLook.State() end
            end
            wasActive = false
            return
        end
        wasActive = true
        sheet:Show()
        Bevel(0)
        for _, line in pairs(control.twichFieldRing or {}) do line:Hide() end
        control:SetBackdropColor(0, 0, 0, 0)
        control:SetBackdropBorderColor(0, 0, 0, 0)
        local enabled = control:IsEnabled()
        local focus = kind == "field" and control:HasFocus()
        local base = kind == "chip" and "chip" or field and "field" or danger and "danger" or primary and "primary" or "button"
        if selectedFamily then
            -- Inactive segments keep quiet leather; UVs remain those of the selected-source family.
            base = control.twichSelected or kind == "chip" and true
            base = base and "selection" or "segment"
        end
        local skin
        if not enabled then skin = kind == "chip" and "chip-off" or field and "field-off" or selectedFamily and "segment-off" or "button-off"
        elseif down and not field then skin = (base == "selection" and "segment" or base) .. "-down"
        elseif over or focus then skin = base .. "-hot"
        else skin = base end
        sheet:SetSkin(skin)
        local pal = Look().pal
        local ink = not enabled and pal.stone or danger and pal.danger.text or kind == "target" and pal.bronzeText or pal.text
        if kind == "field" then Look().Color(control, ink) end
        if control.text and type(control.text) ~= "string" then
            Look().Color(control.text, ink)
            if control.craftLabelInset then
                control.text:ClearAllPoints()
                control.text:SetPoint("LEFT", control.craftLabelInset, 0)
                control.text:SetPoint("RIGHT", -10, 0)
                control.text:SetJustifyH("LEFT")
            elseif kind == "dropdown" and not control.compactMenu then
                control.text:ClearAllPoints()
                control.text:SetPoint("LEFT", 10, 0)
                control.text:SetPoint("RIGHT", -26, 0)
                control.text:SetJustifyH("LEFT")
            elseif kind ~= "dropdown" then
                control.text:SetWidth(math.max(16, control:GetWidth() - 12))
            end
        end
    end
    control:HookScript("OnEnter", function() over = true; Paint() end)
    control:HookScript("OnLeave", function() over, down = false, false; Paint() end)
    control:HookScript("OnMouseDown", function() down = true; Paint() end)
    control:HookScript("OnMouseUp", function() down = false; Paint() end)
    control:HookScript("OnHide", function() over, down = false, false; Paint() end)
    control:HookScript("OnSizeChanged", Paint)
    if kind == "field" then
        control:HookScript("OnEditFocusGained", Paint)
        control:HookScript("OnEditFocusLost", Paint)
    end
    control:HookScript("OnEnable", Paint)
    control:HookScript("OnDisable", Paint)
    if kind == "segment" then
        function control:SetSelected(value) self.twichSelected = value; Paint() end
    end
    sheet.Refresh = Paint
    -- Settings defaults may be refined by an explicit action role (for example Save or Delete).
    -- These roles share the button silhouette and reuse its textures and listeners.
    function sheet.Retype(role)
        if field or selectedFamily or kind == "chip" or kind == "target" then return end
        if role == "field" or role == "dropdown" or role == "segment" or role == "chip" or role == "target" then return end
        kind = role
        primary = role == "primary" or role == "confirmation"
        danger = role == "danger"
        Paint()
    end
    Paint()
    if control.text and type(control.text) ~= "string" and kind ~= "dropdown" then
        control.text:SetWidth(math.max(16, control:GetWidth() - 12))
        control.text:SetWordWrap(false)
    end
    return sheet
end

function CL.Thumb(texture)
    texture:SetTexture(CRAFT .. "slider-thumb.tga")
    texture:SetVertexColor(1, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Quiet materials (moved from TwichUI_Settings/Material.lua, which keeps its names for them)
---------------------------------------------------------------------------
local FILE = {
    dark = DIR .. "dark.tga", warm = DIR .. "warm.tga",
    window = DIR .. "window-edge.tga", control = DIR .. "control-edge.tga",
    recess = DIR .. "round-recess.tga", raised = DIR .. "round-raised.tga",   -- rounded nine-slice sheets (tools/make_style_v2_art.py)
}
local QUIET_DIR = R.PATH .. [[media\reminders\materials\]]
for _, role in ipairs({ "outer", "header", "editor", "card", "recess", "button", "selected", "primary", "viewport", "chip" }) do
    FILE["quiet-" .. role] = QUIET_DIR .. "face-" .. role .. ".tga"
    FILE["grain-" .. role] = QUIET_DIR .. "grain-" .. role .. ".tga"
end
FILE.controlRim = QUIET_DIR .. "control-rim.tga"
FILE.frameRim = QUIET_DIR .. "frame-rim.tga"
CL.FILE = FILE
local CORNER = 6   -- a rounded container's corner, in units (12 texels of its 32 texel sheet)

function CL.Tile(host, layer, sub, which, alpha, tint)
    local t = host:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(FILE[which], "REPEAT", "REPEAT")
    t:SetHorizTile(true)
    t:SetVertTile(true)
    t:SetAllPoints(host)
    if type(tint) == "number" then tint = { tint, tint, tint } end
    tint = tint or { 1, 1, 1 }
    t:SetVertexColor(tint[1], tint[2], tint[3], alpha or 1)
    return t
end

-- A rounded container drawn from a nine-slice sheet (`kind`: "recess", "raised" or a "quiet-<role>" face): four corners at their own
-- size and the edges and middle stretched. `ins` = { left, top, right, bottom } sets it that many units inside the host.
function CL.Slice(host, kind, layer, sub, ins, radius)
    local C, u, parts = radius or CORNER, { 0, 12 / 32, 20 / 32, 1 }, {}
    local il, it, ir, ib = 0, 0, 0, 0
    if ins then il, it, ir, ib = ins[1], ins[2], ins[3], ins[4] end
    local cols = { { { "LEFT", il }, { "LEFT", il + C } }, { { "LEFT", il + C }, { "RIGHT", -(ir + C) } }, { { "RIGHT", -(ir + C) }, { "RIGHT", -ir } } }
    local rows = { { { "TOP", -it }, { "TOP", -(it + C) } }, { { "TOP", -(it + C) }, { "BOTTOM", ib + C } }, { { "BOTTOM", ib + C }, { "BOTTOM", ib } } }
    for r = 1, 3 do
        for c = 1, 3 do
            local t = host:CreateTexture(nil, layer, nil, sub)
            t:SetTexture(FILE[kind])
            t:SetTexCoord(u[c], u[c + 1], u[r], u[r + 1])
            local x1, x2, y1, y2 = cols[c][1], cols[c][2], rows[r][1], rows[r][2]
            t:SetPoint("TOPLEFT", host, y1[1] .. x1[1], x1[2], y1[2])
            t:SetPoint("BOTTOMRIGHT", host, y2[1] .. x2[1], x2[2], y2[2])
            parts[#parts + 1] = t
        end
    end
    return parts
end

-- Several textures moved as one (a hover fader's SetAlpha, a selection's SetShown).
local function Group(parts)
    local g = {}
    function g.SetAlpha(_, a) for _, p in ipairs(parts) do p:SetAlpha(a) end end
    function g.SetShown(_, v) for _, p in ipairs(parts) do p:SetShown(v) end end
    g.parts = parts
    return g
end
CL.Group = Group

function CL.QuietTile(host, role, layer, sub)
    return CL.Tile(host, layer or "BACKGROUND", sub or 0, "grain-" .. role, 1)
end

-- Darker editing wells and warmer cards over the same leather. Non-overlapping strips keep the rounded corners and avoid stacked grain.
function CL.QuietGrain(frame, role)
    local pieces = {}
    local middle = CL.QuietTile(frame, role, "BACKGROUND", 1)
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT", 1, -CORNER)
    middle:SetPoint("BOTTOMRIGHT", -1, CORNER)
    pieces[#pieces + 1] = middle
    for _, side in ipairs({ "TOP", "BOTTOM" }) do
        local tile = CL.QuietTile(frame, role, "BACKGROUND", 1)
        pieces[#pieces + 1] = tile
        tile:ClearAllPoints()
        tile:SetPoint(side .. "LEFT", CORNER, side == "TOP" and -1 or 1)
        tile:SetPoint(side .. "RIGHT", -CORNER, side == "TOP" and -1 or 1)
        tile:SetHeight(CORNER - 1)
    end
    return pieces
end

function CL.PanelFace(frame, kind)
    local role = (kind == "card" or kind == "walnut") and "card"
        or kind == "canvas" and "viewport" or kind == "espresso" and "outer" or "editor"
    local pieces = CL.Slice(frame, "quiet-" .. role, "BACKGROUND", 0)
    for _, tile in ipairs(CL.QuietGrain(frame, role)) do pieces[#pieces + 1] = tile end
    local fill = Group(pieces)
    fill.rim = CL.Sheet(frame, role == "card" and "card-rim" or "inset-rim", { layer = "BORDER", sub = 3 })
    return fill
end

function CL.Font(text, size, ivory, role)
    local file, _, flags = text:GetFont()
    local locale = GetLocale and GetLocale()
    local western = locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW" and locale ~= "ruRU"
    if western then
        local serif = role == "serif" or size >= 17 or (file and file:find("Cinzel", 1, true))
        local name = serif and "Spectral-SemiBold.ttf" or role == "strong" and "AlegreyaSans-Bold.ttf" or "AlegreyaSans-Medium.ttf"
        local chosen = R.PATH .. [[media\fonts\]] .. name
        if text:SetFont(chosen, size, "") == false and file then text:SetFont(file, size, flags or "") end
    elseif file then text:SetFont(file, size, flags or "") end
    if ivory then Look().Color(text, Look().pal.text) end
    return text
end

-- A navigation row: the chosen row's raised selection sheet (item.sel) and a fainter one under the pointer (item.hover).
local NAV_INSET = { 4, 1, 4, 1 }
function CL.NavItem(item)
    item.sel = CL.Sheet(item, "selection", { layer = "BACKGROUND", sub = 2, corner = 10, inset = NAV_INSET })
    item.sel:SetShown(false)
    item.hover = CL.Sheet(item, "selection-hot", { layer = "BACKGROUND", sub = 1, corner = 10, inset = NAV_INSET })
    item.hover:SetAlpha(0)
end

-- Rounded controls, opt-in: keep their existing scripts, labels and state handling.
function CL.Dress(control, kind)
    if not control or (control.twichReminderMaterial and not control.twichSharedDefault) then return end
    control.twichSharedDefault = nil
    control.twichReminderMaterial = true
    -- This adapter historically uses "primary" for quiet discovery actions; confirmation is the gold action.
    CL.Control(control, kind == "primary" and "action" or kind)
    if kind == "field" then
        control:SetJustifyH("LEFT")
        CL.Font(control, 14)
    end
    if control.text and type(control.text) ~= "string" then
        CL.Font(control.text, 14)
        if kind == "dropdown" then control.text:SetWordWrap(false)
        else control.text:SetWidth(math.max(1, control:GetWidth() - 12)) end
    end
end

function CL.Segment(parent, label, width, onClick)
    -- Choose the segment silhouette before any generic button adapter can claim the control.
    local b = R.FrameLook.Button(parent, label, width, "secondary", onClick)
    CL.Dress(b, "segment")
    return b
end

-- Same contract as the settings checkbox, with separate hit, track and thumb regions.
function CL.Pill(parent, onToggle, small)
    local b = CreateFrame("Button", nil, parent)
    local w, h = small and 32 or 42, small and 16 or 21
    b:SetSize(w, h)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetTexture(DIR .. "switch-track.tga")
    track:SetAllPoints()
    local thumb = b:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(DIR .. "switch-thumb.tga")
    thumb:SetSize(h - 4, h - 4)
    local checked, active, hot, down = false, true, false, false
    local function Paint()
        -- Dense tables retain their small square hit regions. A checkmark is clearer than squeezing a pill.
        local width = tonumber(b:GetWidth()) or w
        local dense = width < 26
        track:SetShown(not dense); thumb:SetShown(not dense)
        if dense and not b.denseFace then
            b.denseFace = CL.Sheet(b, "field", { layer = "ARTWORK", sub = 2, corner = 4 })
            b.denseMark = b:CreateTexture(nil, "OVERLAY")
            b.denseMark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            b.denseMark:SetPoint("TOPLEFT", 1, -1); b.denseMark:SetPoint("BOTTOMRIGHT", -1, 1)
        end
        if b.denseFace then
            b.denseFace:SetShown(dense)
            b.denseMark:SetShown(dense and checked)
        end
        if dense then
            b.denseFace:SetSkin(not active and "field-off" or hot and "field-hot" or "field")
            b.denseMark:SetVertexColor(.99, .93, .81, active and 1 or .5)
            return
        end
        local c = checked and { 0.93, 0.69, 0.36 } or { 0.55, 0.49, 0.43 }
        local light = down and 0.77 or (hot and 1 or 0.86)
        track:SetVertexColor(c[1] * light, c[2] * light, c[3] * light, active and 1 or 0.62)
        thumb:SetVertexColor(0.99, 0.93, 0.81, active and 1 or 0.62)
        thumb:ClearAllPoints()
        local side = checked and "RIGHT" or "LEFT"
        thumb:SetPoint(side, b, side, checked and -3 or 3, 0)
    end
    function b:SetChecked(v) checked = not not v; Paint() end
    function b:GetChecked() return checked end
    function b:SetActive(v) active = not not v; Paint() end
    function b:SetHot(v) hot = not not v; Paint() end
    b:HookScript("OnEnter", function() b:SetHot(true) end)
    b:HookScript("OnLeave", function() down = false; b:SetHot(false) end)
    b:HookScript("OnMouseDown", function() down = active; Paint() end)
    b:HookScript("OnMouseUp", function() down = false; Paint() end)
    b:HookScript("OnSizeChanged", Paint)
    b:SetScript("OnClick", function() if active and onToggle then onToggle(not checked) end end)
    Paint()
    return b
end

function CL.SearchDecoration(box, placeholder)
    box:SetTextInsets(26, 8, 0, 0)
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetAtlas("common-search-magnifyingglass")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetVertexColor(0.78, 0.71, 0.60)
    local hint = CL.Font(Look().Text(box, "small"), 14)
    hint:SetPoint("LEFT", 26, 0)
    hint:SetWidth(box:GetWidth() - 34)
    hint:SetText(placeholder)
    local function Paint()
        local focus = box:HasFocus()
        hint:SetShown(not focus and box:GetText() == "")
    end
    for _, event in ipairs({ "OnEnter", "OnLeave", "OnEditFocusGained", "OnEditFocusLost" }) do box:HookScript(event, Paint) end
    Paint()
    return hint
end

-- Skin the existing slider geometry. The native bar retains its full hit and drag region. `motion` (optional) adds wheel easing
-- (the settings window passes its own); `active` (optional) says when the painted rail applies.
function CL.ScrollRail(scroll, active, motion)
    if scroll.materialRail then return scroll.materialRail.Fit end
    local bar = scroll.ScrollBar
    if type(bar) ~= "table" then return end
    bar.scrollStep = 16
    if motion then motion(scroll, active) end
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    if not thumb then return end
    local Solid, pal = Look().Solid, Look().pal
    local track = Solid(bar, "BACKGROUND", { 0.070, 0.059, 0.048 }, 1)
    track:SetWidth(5)
    track:SetPoint("TOP", 0, -2)
    track:SetPoint("BOTTOM", 0, 2)
    thumb:SetAlpha(0)
    local face = Solid(bar, "OVERLAY", { 0.43, 0.36, 0.27 }, 0.9)
    CL.Thumb(face)
    face:SetVertexColor(0.80, 0.80, 0.80, 0.9)
    face:SetPoint("TOP", thumb, "TOP", 0, 0)
    face:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
    face:SetWidth(5)
    local bevel = Solid(bar, "OVERLAY", { 0.73, 0.64, 0.50 }, 0.44)
    bevel:SetWidth(1)
    bevel:SetPoint("TOPLEFT", face, "TOPLEFT")
    bevel:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT")
    local arrows = {}
    for i, arrow in pairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
        if type(arrow) == "table" then
            local old = {}
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local texture = arrow[getter] and arrow[getter](arrow)
                if type(texture) == "table" then old[#old + 1] = texture; texture:SetAlpha(0) end
            end
            local art = CL.Sheet(arrow, "button", { layer = "BACKGROUND", corner = 4 })
            local function Paint()
                local on = not active or active()
                art:SetShown(on)
                if on then art:SetSkin(not arrow:IsEnabled() and "button-off" or arrow:IsMouseOver() and "button-hot" or "button") end
            end
            for _, event in ipairs({ "OnEnter", "OnLeave", "OnEnable", "OnDisable" }) do arrow:HookScript(event, Paint) end
            arrow:HookScript("OnMouseDown", function() if not active or active() then art:SetSkin("button-down") end end)
            arrow:HookScript("OnMouseUp", Paint)
            Paint()
            local chevron = Look().Chevron(arrow, arrow, "CENTER", 0, 0, i == 2, pal.bronzeText)
            arrow:SetAlpha(.7)
            arrows[#arrows + 1] = { button = arrow, old = old, chevron = chevron, art = art }
        end
    end
    bar:HookScript("OnEnter", function() face:SetAlpha(1); bevel:SetAlpha(0.8) end)
    bar:HookScript("OnLeave", function() face:SetAlpha(0.9); bevel:SetAlpha(0.44) end)
    local full = 0
    local function Fit()
        local height = scroll:GetHeight()
        if height and height > 0 then bar:SetShown(full > height + 1) end
    end
    scroll:HookScript("OnSizeChanged", Fit)
    local rail = { Fit = function(contentHeight) full = contentHeight; Fit() end }
    function rail:SetShown(on)
        for _, piece in ipairs({ track, face, bevel }) do piece:SetShown(on) end
        thumb:SetAlpha(on and 0 or 1)
        for _, arrow in ipairs(arrows) do
            arrow.button:SetAlpha(on and .7 or 1)
            for _, texture in ipairs(arrow.old) do texture:SetAlpha(on and 0 or 1) end
            for _, piece in ipairs(arrow.chevron) do piece:SetShown(on) end
            arrow.art:SetShown(on)
        end
    end
    scroll.materialRail = rail
    return rail.Fit
end
