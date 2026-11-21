-- TwichUI Fishing: what the heads-up pieces of Fishing Mode share (Stage 2)
-- The cast bar (CastBar.lua), the catch list (CatchList.lua) and the catch notifications (Toast.lua) draw with these: the
-- artwork's paths and measurements (tools/make_fishing_art.py builds TwichUI_Fishing/media from the production texture pack),
-- the type, the colors, item names and icons as the game gives them, key names for the prompts, and dragging a piece to move
-- it. Nothing here runs per frame, reads the game's fishing state or writes anything but a piece's own position (Store.Set).
--
--   H.MEDIA, H.ART                 the textures and their measurements in their files (pixels)
--   H.Texture(tex, name, fallback) sets an artwork texture; a file the game refuses draws `fallback` (a color) instead
--   H.Font(fs, size, role)         Spectral ("serif") or Alegreya Sans ("strong", or the default) at `size`, with a soft shadow;
--                                  the game's own font for Korean, Chinese and Russian, or when a font file is refused
--   H.Item(id)                     name, icon, quality (name and quality nil until the game has the item; H.OnItem tells)
--   H.OnItem(fn)                   fn() when an item the pieces asked about has arrived (GET_ITEM_INFO_RECEIVED), once per burst
--   H.Duration(sec)                "42m 17s", "1h 02m", "38s"
--   H.Key(binding)                 the player's key for a binding as the game names it, gamepad buttons included; nil if none
--   H.Movable(frame, group, anchor) lets the player drag `frame` while the pieces are unlocked; saves group.x / group.y
--   H.Place(frame, group, anchor)  puts `frame` where group.x / group.y / group.scale say

local R = TwichUI
local F = R.Fishing
local S = F.Store
local H = {}
F.Hud = H

H.MEDIA = [[Interface\AddOns\TwichUI_Fishing\media\]]
-- Sizes are the files' (power-of-two canvases) and where the painted content sits in them, in pixels.
H.ART = {
    castbar = { file = "castbar", w = 512, h = 128, cw = 512, ch = 85, trough = { 102.8, 40, 460.1, 58 } },
    castfill = { file = "castfill", w = 512, h = 32, cw = 357, ch = 18 },
    castspark = { file = "castspark", w = 32, h = 32, cw = 32, ch = 32 },
    toast = { file = "toast", w = 512, h = 128, cw = 352, ch = 98, well = { 11, 10, 93, 86 }, band = { 120, 228 } },
    treasure = { file = "toast-treasure", w = 512, h = 128, cw = 330, ch = 94, well = { 11, 12, 85, 83 }, band = { 110, 210 } },
    glint = { file = "glint", w = 128, h = 64, cw = 128, ch = 61 },
    mark = { file = "mark", w = 64, h = 64, cw = 63, ch = 64 },
    scrim = { file = "scrim", w = 256, h = 128, cw = 256, ch = 128 },
    rowglow = { file = "rowglow", w = 256, h = 32, cw = 256, ch = 32 },
    logo = { file = "logo", w = 512, h = 256, cw = 488, ch = 196 },
    iconframe = { file = "iconframe", w = 64, h = 64, cw = 64, ch = 64, well = { 5.3, 5.4, 60.0, 57.2 } },
    rule = { file = "rule", w = 256, h = 32, cw = 256, ch = 30 },
    ["glyph-lure"] = { file = "glyph-lure", w = 64, h = 64, cw = 64, ch = 64 },
    ["glyph-time"] = { file = "glyph-time", w = 64, h = 64, cw = 64, ch = 64 },
}

H.IVORY = { 0.94, 0.90, 0.81 }
H.MUTED = { 0.78, 0.72, 0.62 }
H.SOFT = { 0.88, 0.83, 0.74 }
H.AMBERTEXT = { 0.88, 0.74, 0.52 }  -- the mockup's warm secondary lines ("24 caught", the quantity on a notice)      -- small text over the world (the prompts): muted, but still readable over snow
H.BRONZE = { 0.78, 0.58, 0.32 }
H.GOLD = { 0.96, 0.80, 0.46 }
H.WARN = { 1.00, 0.72, 0.42 }
H.QUESTION = [[Interface\Icons\INV_Misc_QuestionMark]]
H.SHADE = 0.6          -- how dark the shade under the catch list and the cast bar's lines is at its middle

-- The painted part of a file, as texture coordinates.
function H.Coords(name)
    local a = H.ART[name]
    return 0, a.cw / a.w, 0, a.ch / a.h
end

-- Sets artwork on a texture. A file the game refuses (SetTexture answers false) or a texture that can't take one is drawn as a
-- plain color instead, so a missing or damaged file never leaves a hole or a green square.
function H.Texture(tex, name, fallback)
    local a = H.ART[name]
    local ok = a and tex.SetTexture and tex:SetTexture(H.MEDIA .. a.file)
    if a and ok ~= false then
        tex:SetTexCoord(H.Coords(name))
        tex.twichArt = name
        return true
    end
    F.Note("art-missing", name)
    local c = fallback or { 0.1, 0.07, 0.05, 0.6 }
    if tex.SetColorTexture then tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    tex.twichArt = false
    return false
end

-- An artwork as an inline texture in text (|T...|t), `size` units square: the cast bar's stat glyphs.
function H.Glyph(name, size)
    local a = H.ART[name]
    if not a then return "" end
    return ("|T%s%s:%d:%d:0:0:%d:%d:0:%d:0:%d|t"):format(H.MEDIA, a.file, size, size, a.w, a.h, a.cw, a.ch)
end

-- An item icon in the bronze icon frame (iconframe: the notification's frame on its own), `size` units square. Returns the
-- frame texture and the icon texture; the icon sits in the frame's well, the frame's chamfers cover its corners.
function H.FramedIcon(parent, size, layer)
    local a = H.ART.iconframe
    local frameTex = parent:CreateTexture(nil, layer or "ARTWORK", nil, 2)
    frameTex:SetSize(size, size)
    local framed = H.Texture(frameTex, "iconframe", { 0.62, 0.45, 0.24, 0.95 })
    local icon = parent:CreateTexture(nil, layer or "ARTWORK", nil, 1)
    local k = size / a.cw
    local w = a.well
    if framed then
        icon:SetPoint("TOPLEFT", frameTex, "TOPLEFT", w[1] * k, -w[2] * k)
        icon:SetPoint("BOTTOMRIGHT", frameTex, "TOPLEFT", w[3] * k, -w[4] * k)
    else
        icon:SetPoint("TOPLEFT", frameTex, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", frameTex, "BOTTOMRIGHT", -1, 1)
    end
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return frameTex, icon
end

---------------------------------------------------------------------------
-- Type
---------------------------------------------------------------------------
local FONTS = { serif = "Spectral-SemiBold.ttf", strong = "AlegreyaSans-Bold.ttf", body = "AlegreyaSans-Medium.ttf" }

function H.Font(fs, size, role)
    local locale = GetLocale and GetLocale()
    local western = locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW" and locale ~= "ruRU"
    local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    local file = western and (R.PATH .. [[media\fonts\]] .. (FONTS[role or "body"] or FONTS.body)) or fallback
    if fs:SetFont(file, size, "") == false then fs:SetFont(fallback, size, "") end
    fs:SetShadowColor(0, 0, 0, 0.92)
    fs:SetShadowOffset(1, -1)
    return fs
end

function H.Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

---------------------------------------------------------------------------
-- Items, as the game gives them (nothing is assumed about an item the game hasn't described yet)
---------------------------------------------------------------------------
local waiting, itemListeners, flushing = {}, {}, false

function H.Item(id)
    local name, quality, icon
    if C_Item and C_Item.GetItemInfo then
        local n, _, q, _, _, _, _, _, _, tex = C_Item.GetItemInfo(id)
        name, quality, icon = n, q, tex
    elseif GetItemInfo then
        local n, _, q, _, _, _, _, _, _, tex = GetItemInfo(id)
        name, quality, icon = n, q, tex
    end
    name, quality, icon = F.Readable(name), F.Num(F.Readable(quality)), F.Readable(icon)
    if icon == nil then
        if C_Item and C_Item.GetItemIconByID then icon = F.Readable(C_Item.GetItemIconByID(id))
        elseif GetItemIcon then icon = F.Readable(GetItemIcon(id)) end
    end
    if type(name) ~= "string" then
        name = nil
        waiting[id] = true
        H.ListenItems()
    end
    return name, icon or H.QUESTION, quality
end

function H.OnItem(fn)
    for _, f in ipairs(itemListeners) do if f == fn then return end end
    itemListeners[#itemListeners + 1] = fn
end

local function OnItemInfo(itemID)
    itemID = F.Count(itemID)
    if not (itemID and waiting[itemID]) then return end
    waiting[itemID] = nil
    if next(waiting) == nil then H.ListenItems() end
    if flushing then return end
    flushing = true
    local function Flush()
        flushing = false
        for _, fn in ipairs(itemListeners) do
            local ok, err = pcall(fn)
            if not ok then R.Fault("fishing hud item", err) end
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Flush) else Flush() end
end

local listeningItems = false
function H.ListenItems()
    local want = next(waiting) ~= nil
    if want == listeningItems then return end
    listeningItems = want
    if want then R:On("GET_ITEM_INFO_RECEIVED", OnItemInfo) else R:Off("GET_ITEM_INFO_RECEIVED", OnItemInfo) end
end

function H.Waiting() local n = 0 for _ in pairs(waiting) do n = n + 1 end return n end

---------------------------------------------------------------------------
-- The session's records changed (subscribed here, before the pieces, so anything cached on the records is stale before they
-- redraw): Present.Value keeps a connected valuation's answer until then.
---------------------------------------------------------------------------
H.serial = 0
for _, e in ipairs({ "ITEM", "CONTAINER", "QUEUE", "CATCH", "SESSION_START", "SESSION_END" }) do
    F.Subscribe(e, function() H.serial = H.serial + 1 end)
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
function H.Duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    if sec >= 3600 then return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    if sec >= 60 then return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60) end
    return ("%ds"):format(sec)
end

-- Gamepad buttons as the game's key names spell them (Bindings: PAD1..PAD6, PADDUP.., PADLSHOULDER..). The game's own
-- GetBindingText names them first; these are only used when it gives back the raw key name.
local PAD = {
    PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PAD5 = "Pad 5", PAD6 = "Pad 6",
    PADDUP = "D-pad Up", PADDDOWN = "D-pad Down", PADDLEFT = "D-pad Left", PADDRIGHT = "D-pad Right",
    PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT",
    PADLSTICK = "Left Stick", PADRSTICK = "Right Stick", PADBACK = "Back", PADFORWARD = "Start",
    PADSOCIAL = "Share", PADSYSTEM = "Guide", PADPADDLE1 = "Paddle 1", PADPADDLE2 = "Paddle 2",
    PADPADDLE3 = "Paddle 3", PADPADDLE4 = "Paddle 4",
}
H.PAD = PAD

-- One key's name: modifiers kept ("SHIFT-PAD1" -> "Shift-A").
function H.KeyName(key)
    if type(key) ~= "string" or key == "" then return nil end
    if GetBindingText then
        local ok, text = pcall(GetBindingText, key, "KEY_")
        text = ok and F.Readable(text) or nil
        if type(text) == "string" and text ~= "" and text ~= key then return text end
    end
    local mods, base = key:match("^(.-)([^%-]+)$")
    base = PAD[base] or base
    mods = (mods or ""):gsub("SHIFT%-", "Shift-"):gsub("CTRL%-", "Ctrl-"):gsub("ALT%-", "Alt-")
    return mods .. base
end

function H.IsPadKey(key) return type(key) == "string" and key:find("PAD", 1, true) ~= nil end

-- The player's key for a binding, preferring a gamepad button while a gamepad is in use. nil when nothing is bound.
function H.Key(binding)
    if not GetBindingKey then return nil end
    local a, b = GetBindingKey(binding)
    a, b = F.Readable(a), F.Readable(b)
    local padActive = H.PadActive()
    local key = a
    if padActive and H.IsPadKey(b) and not H.IsPadKey(a) then key = b end
    if not padActive and H.IsPadKey(a) and type(b) == "string" and not H.IsPadKey(b) then key = b end
    return H.KeyName(key)
end

-- True while a gamepad is enabled and in use (C_GamePad, where the client has it). Read only.
function H.PadActive()
    local G = rawget(_G, "C_GamePad")
    if not (G and G.IsEnabled) then return false end
    local ok, on = pcall(G.IsEnabled)
    if not (ok and F.Readable(on) == true) then return false end
    if G.GetActiveDeviceID then
        local ok2, id = pcall(G.GetActiveDeviceID)
        return ok2 and F.Num(id) ~= nil and id >= 0
    end
    return true
end

---------------------------------------------------------------------------
-- Placing and moving the pieces (positions are saved through Store.Set: group.x, group.y, group.scale)
---------------------------------------------------------------------------
function H.Place(frame, group, anchor)
    local scale = S.Get(group .. ".scale") or 1
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, anchor, S.Get(group .. ".x") or 0, S.Get(group .. ".y") or 0)
end

-- The frame's offset from `anchor` of the screen, in the frame's own units (what SetPoint takes at its scale).
function H.Offset(frame, anchor)
    local s = frame:GetScale() or 1
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    if not (l and b and w and h and pw and ph) then return nil end
    local x, y
    if anchor:find("LEFT", 1, true) then x = l elseif anchor:find("RIGHT", 1, true) then x = l + w - pw / s else x = l + w / 2 - pw / s / 2 end
    if anchor:find("BOTTOM", 1, true) then y = b elseif anchor:find("TOP", 1, true) then y = b + h - ph / s else y = b + h / 2 - ph / s / 2 end
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

function H.Movable(frame, group, anchor)
    if frame.twichMove then return end
    frame.twichMove = { group = group, anchor = anchor }
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if self.twichUnlocked and not F.InCombat() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = H.Offset(self, anchor)
        if x then
            S.Set(group .. ".x", math.max(-2000, math.min(2000, x)))
            S.Set(group .. ".y", math.max(-2000, math.min(2000, y)))
        end
        H.Place(self, group, anchor)
    end)
    local outline = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    outline:SetAllPoints()
    outline:SetColorTexture(0.78, 0.58, 0.32, 0.18)
    outline:Hide()
    local label = frame:CreateFontString(nil, "OVERLAY")
    H.Font(label, 11, "strong")
    H.Color(label, H.GOLD)
    label:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    label:SetText("Drag to move")
    label:Hide()
    frame.twichMove.outline, frame.twichMove.label = outline, label
end

-- Unlocked: the frame takes the mouse and shows where it is. Locked: it never takes the mouse (clicks reach the world).
function H.SetUnlocked(frame, on)
    on = on and true or false
    frame.twichUnlocked = on
    frame:EnableMouse(on)
    local m = frame.twichMove
    if m then m.outline:SetShown(on); m.label:SetShown(on) end
end
