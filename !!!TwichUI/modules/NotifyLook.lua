-- TwichUI: notification card appearance
-- What a player can change about how the notification cards look: their fonts, size, text colors and
-- opacity, the accent rule, and an optional backdrop behind the text. The cards are the zone arrival
-- card, the new training card, the friend login card and the Welcome Back card (modules/Arrival.lua,
-- Training.lua, FriendLogin.lua and WelcomeBack.lua). They are drawn by different renderers with
-- different layouts, so this file decides only the look; each renderer still decides its own content,
-- geometry, animation and place, and asks for the look whenever it draws.
--
-- Saved in the profile in use, like TwichUI's other looks (Profiles.lua):
--   TwichUIDB.ui.notifyLook          the shared look: every card follows it
--   TwichUIDB.ui.notifyLook<Card>    a card's own look, used only while its `own` is true. It is a
--                                    complete look, copied from the shared one when it is turned on, so
--                                    it is what it says and later changes to the shared look don't reach
--                                    it. Turning it off keeps the values for next time; Reset forgets them.
-- A value that can't be used is read as its default without being erased, and nothing is saved that the
-- player did not change. The defaults are exactly the look the cards had before this file existed.
-- Frames, fonts, media paths and previews are never saved.
--
-- Nothing runs per frame. A change redraws a card that is showing, once, in a short coalesced pass and
-- without replaying its entrance; a card that is not showing is styled as it is shown.

local R = TwichUI
local N = R.Notify
local L = {}
R.NotifyLook = L

L.KINDS = { "arrival", "training", "friend", "welcome" }
L.LABELS = { arrival = "Zone arrival", training = "New training", friend = "Friend login", welcome = "Welcome Back" }

-- The roles each card really has. The title is its heading; the body is the main text (the spells, the last
-- place noted); the detail is the quieter text under it. A card with no body has no body color to set.
local ROLES = {
    arrival  = { title = true, detail = true },
    training = { title = true, body = true, detail = true },
    friend   = { title = true, detail = true },
    welcome  = { title = true, body = true, detail = true },
}

local SAVED = {
    shared = "notifyLook", arrival = "notifyLookArrival", training = "notifyLookTraining",
    friend = "notifyLookFriend", welcome = "notifyLookWelcome",
}
L.SAVED = SAVED

---------------------------------------------------------------------------
-- Defaults: the cards' own colors, as Chronicle style has them.
---------------------------------------------------------------------------
local FALLBACK = {
    text = { 0.93, 0.88, 0.76 }, stone = { 0.62, 0.58, 0.51 }, textDim = { 0.78, 0.74, 0.66 },
    bronze = { 0.55, 0.43, 0.22 }, bronzeLo = { 0.30, 0.23, 0.13 }, gold = { 0.79, 0.64, 0.29 },
    bg = { 0.150, 0.115, 0.082 },
}
local S = R.ChronicleStyle
local K = S and S.color or FALLBACK

local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
local function HexOf(c) return ("ff%02x%02x%02x"):format(Byte(c[1]), Byte(c[2]), Byte(c[3])) end

local DEFAULTS = {
    titleFont = "default", textFont = "default",
    textScale = 100, outline = "shadow",
    titleColor = HexOf(K.text), bodyColor = HexOf(K.text), detailColor = HexOf(K.stone),
    textOpacity = 100,
    accentColor = HexOf(K.bronze), accentOpacity = 100,
    bgColor = HexOf(K.bg), bgOpacity = 0, padding = 10,
}
-- The role colors the defaults stand for: a changed color is applied as a ratio to these, so a card's dimmer
-- text (a smaller place's name) stays dimmer than its title.
local ROLE_COLOR = { title = K.text, body = K.text, detail = K.stone }
local ROLE_KEY = { title = "titleColor", body = "bodyColor", detail = "detailColor" }

local LIMITS = {
    textScale = { 80, 140 },       -- percent of each card's usual text size
    textOpacity = { 30, 100 },     -- the text only; never the backdrop or the rule
    accentOpacity = { 0, 100 },
    bgOpacity = { 0, 100 },        -- 0: no backdrop, as the cards have always been
    padding = { 4, 20 },           -- screen units of backdrop beyond the text
}
local OUTLINES = { shadow = "", none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
L.OUTLINE_CHOICES = {
    { "shadow", "Shadow (default)" }, { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" },
}
local COLORS = { titleColor = true, bodyColor = true, detailColor = true, accentColor = true, bgColor = true }
L.DEFAULTS, L.LIMITS = DEFAULTS, LIMITS

-- The settings a card has: every role-free one, and a color for each role it has.
local function KeysFor(kind)
    local list = { "titleFont", "textFont", "textScale", "outline", "titleColor" }
    if ROLES[kind].body then list[#list + 1] = "bodyColor" end
    for _, key in ipairs({ "detailColor", "textOpacity", "accentColor", "accentOpacity", "bgColor", "bgOpacity", "padding" }) do
        list[#list + 1] = key
    end
    return list
end
local KEYS, KEY_SET = {}, {}
for _, kind in ipairs(L.KINDS) do
    KEYS[kind] = KeysFor(kind)
    KEY_SET[kind] = {}
    for _, key in ipairs(KEYS[kind]) do KEY_SET[kind][key] = true end
end

-- The saved keys of a card or of the shared look ("shared": every key).
function L.Keys(scope)
    if scope == "shared" then return KeysFor("welcome") end   -- the superset
    return KEYS[scope] or {}
end

-- Whether a card has this setting (the shared look has them all).
function L.Applies(scope, key)
    if scope == "shared" then return DEFAULTS[key] ~= nil end
    return KEY_SET[scope] ~= nil and KEY_SET[scope][key] == true
end

-- The sets the sharing schema reads: one flat table of keys per place it is kept (setup/TwichConfig.lua).
function L.Source(scope)
    local defaults = {}
    for key, value in pairs(DEFAULTS) do defaults[key] = value end
    if scope ~= "shared" then defaults.own = false end
    return { DEFAULTS = defaults, LIMITS = LIMITS }
end

local function ValidName(value)
    return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]")
end

local function Valid(key, value)
    local limit = LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif COLORS[key] then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif key == "titleFont" or key == "textFont" then return ValidName(value)
    elseif key == "outline" then return type(value) == "string" and OUTLINES[value] ~= nil
    elseif key == "own" then return type(value) == "boolean" end
    return false
end
L.Valid = Valid

---------------------------------------------------------------------------
-- State. Nothing here is saved.
---------------------------------------------------------------------------
local rev = 0                -- bumped whenever a setting, or what it resolves to, may have changed
local cache = {}             -- [kind] = { rev, look }
local scheduled = false      -- a coalesced pass is waiting on its timer
local token = 0
local stats = { passes = 0, requests = 0, coalesced = 0 }
local scope = "shared"       -- what the settings page is editing; a page state, not a setting

local function Saved(which)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui[SAVED[which]]
    return type(t) == "table" and t or nil
end

local Request   -- below

local function Changed()
    rev = rev + 1
    Request()
end

---------------------------------------------------------------------------
-- Reading and writing the settings
---------------------------------------------------------------------------
-- Whether a card has its own look turned on.
function L.Own(kind)
    local t = KEY_SET[kind] and Saved(kind)
    return t ~= nil and t.own == true
end

-- A value of the shared look: saved when usable, else the default.
function L.Shared(key)
    local t = Saved("shared")
    local v = t and t[key]
    if Valid(key, v) then return v end
    return DEFAULTS[key]
end

-- The value a card is drawn with: its own when it has one turned on, else the shared look's.
function L.Get(kind, key)
    if L.Own(kind) then
        local v = Saved(kind)[key]
        if Valid(key, v) then return v end
        return DEFAULTS[key]
    end
    return L.Shared(key)
end

-- What the settings page shows for a place: "shared", or one card (its own values while it has them turned on,
-- otherwise the shared look's, which is what it is drawn with).
function L.GetFor(which, key)
    if which == "shared" then return L.Shared(key) end
    return L.Get(which, key)
end

local function Ui()
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    return TwichUIDB.ui
end

local function Table(which)
    local ui = Ui()
    if type(ui[SAVED[which]]) ~= "table" then ui[SAVED[which]] = {} end
    return ui[SAVED[which]]
end

-- Saves one setting of the shared look, or of a card that has its own look on (a value that can't be used, or
-- one the card has no use for, is refused). Returns whether it was kept.
function L.Set(which, key, value)
    if not L.Applies(which, key) or not Valid(key, value) then return false end
    if which ~= "shared" and not L.Own(which) then return false end
    local t = Table(which)
    if t[key] == value then return true end
    t[key] = value
    Changed()
    return true
end

-- Turns a card's own look on or off. Turning it on gives it a complete look to start from: the values it kept
-- from before, and the shared look's for the rest. Turning it off keeps them, and the card follows the shared
-- look again. Returns whether it changed.
function L.SetOwn(kind, on)
    if not KEY_SET[kind] then return false end
    on = on and true or false
    if L.Own(kind) == on then return false end
    if on then
        local t = Table(kind)
        for _, key in ipairs(KEYS[kind]) do
            if not Valid(key, t[key]) then t[key] = L.Shared(key) end
        end
        t.own = true
    else
        Table(kind).own = false
    end
    Changed()
    return true
end

-- The shared look back to the defaults. A card's own look, and everything else, is left alone.
function L.ResetShared()
    local ui = TwichUIDB and TwichUIDB.ui
    if ui then ui[SAVED.shared] = nil end
    Changed()
end

-- A card back to following the shared look: its own values are forgotten.
function L.ResetCard(kind)
    local ui = TwichUIDB and TwichUIDB.ui
    if ui and SAVED[kind] and kind ~= "shared" then ui[SAVED[kind]] = nil end
    Changed()
end

-- What the settings page is editing (not saved).
function L.Scope() return scope end
function L.SetScope(which)
    if which ~= "shared" and not KEY_SET[which] then return false end
    scope = which
    return true
end

-- A profile change: the card in view is drawn for what is saved now, and previews are put away.
R.Profiles.OnApply("look", "notify-look", function()
    L.ClearPreviews()
    Changed()
end)

---------------------------------------------------------------------------
-- The look a card draws with, worked out once per change
---------------------------------------------------------------------------
local function Rgb(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- A saved color as numbers; the default's own hex gives the default's own numbers exactly.
local function Channels(hex, defaultHex, defaultColor)
    if hex == defaultHex then return { defaultColor[1], defaultColor[2], defaultColor[3] } end
    local r, g, b = Rgb(hex)
    return { r, g, b }
end

-- base scaled by how far color is from ref, channel by channel, never above 1: exactly base at the default.
local function Tint(base, color, ref)
    local out = {}
    for i = 1, 3 do
        local ratio = ref[i] > 0 and color[i] / ref[i] or 1
        local x = base[i] * ratio
        out[i] = x > 1 and 1 or x
    end
    return out
end

-- The look of one card: { scale, grow, flags, shadow, alpha, titleFont, textFont, color = { role = rgb },
-- accent, accentAlpha, bg, bgAlpha, pad }. Cached until a setting changes.
function L.Look(kind)
    local c = cache[kind]
    if c and c.rev == rev then return c.look end
    local function Get(key) return L.Get(kind, key) end
    local scale = Get("textScale") / 100
    local outline = Get("outline")
    local look = {
        scale = scale,
        grow = math.max(1, scale),     -- how much more room a card needs: it never gets less than it had
        flags = OUTLINES[outline] or "",
        shadow = outline == "shadow",
        alpha = Get("textOpacity") / 100,
        titleFont = Get("titleFont"), textFont = Get("textFont"),
        color = {}, ref = ROLE_COLOR,
        accentAlpha = Get("accentOpacity") / 100,
        bgAlpha = Get("bgOpacity") / 100,
        pad = Get("padding"),
    }
    for role, key in pairs(ROLE_KEY) do
        look.color[role] = Channels(Get(key), DEFAULTS[key], ROLE_COLOR[role])
    end
    look.accent = Channels(Get("accentColor"), DEFAULTS.accentColor, K.bronze)
    look.bg = Channels(Get("bgColor"), DEFAULTS.bgColor, K.bg)
    cache[kind] = { rev = rev, look = look }
    return look
end

-- How much room a card's geometry needs (1 at the default and below it).
function L.Grow(kind) return L.Look(kind).grow end

-- A size scaled by the card's text size, in whole units.
function L.Scaled(kind, size) return math.floor(size * L.Look(kind).scale + 0.5) end

-- The color a role is drawn in: base (the card's own tone for it, the role's default when nil) moved the way
-- the player moved the role's color.
function L.Color(kind, role, base)
    local look = L.Look(kind)
    local ref = look.ref[role]
    local c = look.color[role]
    return Tint(base or ref, c, ref)
end

-- "|cffRRGGBB" for text that carries its own colors inside a line.
function L.Hex(kind, role, base)
    local c = L.Color(kind, role, base)
    local function B(v) return math.floor(v * 255 + 0.0001) end
    return ("|cff%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- Gives a FontString the look: face, size, outline or shadow, color and opacity.
-- spec: { role = "title"|"body"|"detail", path = the card's own font file for it, size = its usual size,
--   fallback = the game's font object to borrow from when neither can be used,
--   color = the card's own tone for it when it isn't the role's default (nil: the role's),
--   fixed = true to leave its color to the caller (a meaningful tint, or a link's hover color),
--   alpha = text alpha inside the color (default 1) }
function L.Style(kind, fs, spec)
    local look = L.Look(kind)
    local A = R.Arrival
    local size = math.floor(spec.size * look.scale + 0.5)
    local id = spec.role == "title" and look.titleFont or look.textFont
    local MS = R.MenuStyle
    local drawn = false
    if id ~= "default" then
        -- A chosen font that is not there, or that the game can't draw, is drawn as the card's own and stays chosen.
        if MS and MS.Fonts then
            local path, state = MS.Fonts.Resolve(id, nil)
            drawn = state == "ok" and path ~= nil and fs:SetFont(path, size, look.flags) ~= false
        end
    end
    if not drawn then A.SetFont(fs, spec.path, size, spec.fallback, look.flags) end
    if look.shadow then
        fs:SetShadowColor(0, 0, 0, 0.85)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowColor(0, 0, 0, 0)
    end
    if spec.fixed then
        if spec.color then fs:SetTextColor(spec.color[1], spec.color[2], spec.color[3], spec.alpha or 1) end
    else
        local c = L.Color(kind, spec.role, spec.color)
        fs:SetTextColor(c[1], c[2], c[3], spec.alpha or 1)
    end
    fs:SetAlpha(look.alpha)
end

-- The divider's style, for every card: "classic" (the thin pixel rule, in the accent color) or "illustrated" (a
-- bronze ornamental divider, media/notify/divider.tga, made by tools/make_divider_art.py; it is a painting, so it
-- keeps its own colors and only the accent opacity reaches it). Saved in TwichUIDB.ui.notifyDivider; anything else
-- saved reads as classic, without being erased.
L.DIVIDER_STYLES = {
    { key = "classic", label = "Classic", tip = "The thin bronze rule the cards have always had, in the accent color." },
    { key = "illustrated", label = "Illustrated", tip = "A bronze ornamental divider with a diamond at its centre. It has its own colors, so the accent color doesn't change it; the accent opacity still does." },
}
L.DIVIDER_DEFAULT = "classic"
local DIVIDER_PATH = R.PATH .. [[media\notify\divider.tga]]   -- 512x64, shown whole at its width / 8 high
local dividerFailed = false
local dividerArt = setmetatable({}, { __mode = "k" })   -- [rule] = its divider texture, once made

function L.DividerStyle()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.notifyDivider
    for _, style in ipairs(L.DIVIDER_STYLES) do
        if style.key == saved then return saved end
    end
    return L.DIVIDER_DEFAULT
end

-- Saves the style (one of DIVIDER_STYLES; anything else is refused). Returns whether it was kept. Cards that are
-- up are drawn again, once, without replaying their entrance.
function L.SetDividerStyle(key)
    for _, style in ipairs(L.DIVIDER_STYLES) do
        if style.key == key then
            TwichUIDB.ui = TwichUIDB.ui or {}
            if TwichUIDB.ui.notifyDivider ~= key then
                TwichUIDB.ui.notifyDivider = key
                Request()
            end
            return true
        end
    end
    return false
end

-- A rule's divider texture, made the first time it is wanted (once per rule). nil if it can't be made.
local function DividerArt(rule)
    if dividerArt[rule] then return dividerArt[rule] end
    if dividerFailed then return nil end
    local ok, art = pcall(function()
        local t = rule:CreateTexture(nil, "ARTWORK")
        t:SetTexture(DIVIDER_PATH)
        return t
    end)
    if not (ok and art) then dividerFailed = true return nil end
    dividerArt[rule] = art
    return art
end

-- Colors a rule (Arrival.lua's A.Rule) with the accent, and sets how solid it is. baseAlpha: how solid the
-- card draws it at its own default (a smaller place's card has a quieter one). With the illustrated divider the
-- rule's own lines are put away and the painting is drawn centred on it, as wide as the rule; the rule's size,
-- and so the card's layout, is the same either way.
function L.PaintRule(kind, rule, baseAlpha)
    local look = L.Look(kind)
    local parts = rule.parts
    local art = L.DividerStyle() == "illustrated" and DividerArt(rule)
    if art then
        local width = rule:GetWidth()
        if type(width) ~= "number" or width ~= width or width <= 0 then width = 160 end
        art:ClearAllPoints()
        art:SetPoint("CENTER", rule, "CENTER", 0, 0)
        art:SetSize(width, width / 8)
        art:Show()
        for _, part in ipairs(parts or {}) do part.texture:Hide() end
    else
        if dividerArt[rule] then dividerArt[rule]:Hide() end
        if parts then
            local acc = look.accent
            local shadow = Tint(K.bronzeLo, acc, K.bronze)
            local mark = Tint(K.gold, acc, K.bronze)
            for _, part in ipairs(parts) do
                local c = part.tone == "shadow" and shadow or (part.tone == "mark" and mark or acc)
                part.texture:SetColorTexture(c[1], c[2], c[3], part.alpha)
                part.texture:Show()
            end
        end
    end
    rule:SetAlpha((baseAlpha or 1) * look.accentAlpha)
end

-- The width of the text a FontString holds, at most limit.
function L.TextWidth(fs, limit)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    if type(w) ~= "number" or w ~= w then w = 0 end
    if limit and w > limit then w = limit end
    return w
end

local backdrops = setmetatable({}, { __mode = "k" })   -- [card] = its backdrop texture, made the first time it is wanted

-- A card's backdrop texture, or nil while it has never had one (for tests and the report). Reads only.
function L.BackdropOf(card) return backdrops[card] end

-- The backdrop behind a card's text, sized to the text and not the frame: nothing when it is not solid at all
-- (the default). spec: { top, bottom = the frames or regions at the card's top and bottom edges,
-- width = the widest line, align = "CENTER" (default) or "LEFT" (anchored at both edges' left) }.

function L.Fit(kind, card, spec)
    local look = L.Look(kind)
    local bg = backdrops[card]
    if look.bgAlpha <= 0 then
        if bg then bg:Hide() end
        return
    end
    if not bg then
        bg = card:CreateTexture(nil, "BACKGROUND")
        backdrops[card] = bg
    end
    local pad = look.pad
    bg:SetColorTexture(look.bg[1], look.bg[2], look.bg[3], look.bgAlpha)
    bg:ClearAllPoints()
    if spec.align == "LEFT" then
        bg:SetPoint("TOPLEFT", spec.top, "TOPLEFT", -pad, pad)
        bg:SetPoint("BOTTOMLEFT", spec.bottom, "BOTTOMLEFT", -pad, -pad)
    else
        bg:SetPoint("TOP", spec.top, "TOP", 0, pad)
        bg:SetPoint("BOTTOM", spec.bottom, "BOTTOM", 0, -pad)
    end
    bg:SetWidth((spec.width or 0) + pad * 2)
    bg:Show()
end

---------------------------------------------------------------------------
-- When a change reaches a card that is showing
---------------------------------------------------------------------------
local function Run()
    scheduled = false
    stats.passes = stats.passes + 1
    if N and N.Restyle then N.Restyle() end
end

function Request()
    stats.requests = stats.requests + 1
    if scheduled then stats.coalesced = stats.coalesced + 1 return end
    scheduled = true
    local mine = token
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if mine ~= token then return end   -- put away since (settings closed, profile changed)
            Run()
        end)
    else
        Run()
    end
end

-- Draws a pass now, for tests.
function L.Apply() token = token + 1; Run() end

---------------------------------------------------------------------------
-- Previews. Through the coordinator and the real renderers; see modules/Notify.lua.
---------------------------------------------------------------------------
-- Shows a card's sample and keeps it up (silent, made-up details, no state read or changed) until it is put
-- away, a real notice needs its place, combat starts, the settings close or the profile changes. Showing
-- it again starts it over. Returns what N.Preview returns.
function L.Pin(kind)
    if not (N and N.Preview) then return false, "unknown" end
    return N.Preview(kind, nil, { pinned = true })
end

-- Puts one card's preview away.
function L.Unpin(kind)
    if N and N.DropPreviews then N.DropPreviews(kind) end
end

-- Whether a card's preview is up or waiting.
function L.Pinned(kind)
    return N ~= nil and N.PreviewShowing ~= nil and N.PreviewShowing(kind) or false
end

-- Puts every preview away (real notices are not touched), and forgets a waiting redraw.
function L.ClearPreviews()
    token = token + 1
    scheduled = false
    if N and N.ClearPreviews then N.ClearPreviews() end
end

R.OnSettingsClosed(L.ClearPreviews)

---------------------------------------------------------------------------
-- Fonts that arrive after a choice was made
---------------------------------------------------------------------------
R:OnInit(function()
    local MS = R.MenuStyle
    if MS and MS.Fonts and MS.Fonts.Subscribe then
        MS.Fonts.Subscribe(function()
            Changed()   -- a font a saved choice was waiting for may be there now
        end)
    end
end)

-- EllesmereUI loads after TwichUI: a font it offers may exist now.
R:On("ADDON_LOADED", function(name)
    if name == "EllesmereUI" then Changed() end
end)

-- Read only: what is held, for the troubleshooting report.
function L.Snapshot()
    local own, missing = {}, {}
    for _, kind in ipairs(L.KINDS) do
        if L.Own(kind) then own[#own + 1] = kind end
    end
    -- the fonts chosen anywhere that can't be drawn now (they stay chosen; the card's own is drawn)
    local MS = R.MenuStyle
    local seen = {}
    local function Check(which)
        for _, key in ipairs({ "titleFont", "textFont" }) do
            local id = L.GetFor(which, key)
            if id ~= "default" and not seen[id] then
                seen[id] = true
                local state = "missing"
                if MS and MS.Fonts then
                    local _, resolved = MS.Fonts.Resolve(id, nil)
                    state = resolved
                end
                if state ~= "ok" then missing[#missing + 1] = id end
            end
        end
    end
    Check("shared")
    for _, kind in ipairs(L.KINDS) do
        if L.Own(kind) then Check(kind) end
    end
    table.sort(missing)
    return {
        own = own, fallbackFonts = missing, scope = scope,
        passes = stats.passes, requests = stats.requests, coalesced = stats.coalesced, waiting = scheduled,
        shared = {
            titleFont = L.Shared("titleFont"), textFont = L.Shared("textFont"), textScale = L.Shared("textScale"),
            outline = L.Shared("outline"), backdrop = L.Shared("bgOpacity") > 0,
        },
    }
end
