-- TwichUI: RestedXP skin
-- An optional look for the RestedXP Guides window: TwichUI's background and border, a warm text colour
-- and font of your choosing, and a scroll bar to match. It draws nothing of its own. It registers one
-- RestedXP theme named "TwichUI" through RestedXP's theme interface (the RXPGuides_Themes channel, then
-- RegisterTheme), and finishes RestedXP's own frames with the shared look in modules/MenuStyle.lua.
--
-- What it is, in short:
--   * The skin is active only while RestedXP's theme is TwichUI's. Turning it on selects that theme and
--     remembers the one it replaced; turning it off puts that one back and runs RestedXP's own refresh.
--     Picking another theme in RestedXP simply steps the skin aside.
--   * Nothing runs by itself: no polling, no OnUpdate. RestedXP's own refreshes (RenderFrame,
--     CurrentStepFrame.UpdateText, UpdateGuideFontSize, a frame's UpdateVisuals) are hooked once, each
--     hook doing a few comparisons and changing only what differs. Settings changes are coalesced into
--     one timer. Nothing is applied in combat; the latest request waits for it to end.
--   * Nothing about guide content, progress, step completion, positions or sizes is read or changed. Only
--     colours, fonts, borders and backgrounds of RestedXP's own frames, never a secure frame's functions.
--   * Frames and text are restored by looking, not by remembering: a string showing a colour or font this
--     skin applied is set to what RestedXP's own theme says, so there are no snapshots to go stale when
--     RestedXP recycles a frame. The only thing kept is the name of the theme to go back to.
--
-- Layout, in short (a cleaner, content-first window; nothing here changes what a step says or does):
--   * The header's two decorative textures (RestedXP's logo and the class badge) are hidden by default,
--     the space they reserved is given back to the title, and the header is as tall as the title needs.
--   * Text sizes follow RestedXP's Guide Font Size until the player sets their own; line spacing and step
--     padding are TwichUI's. Heights are never computed here: RestedXP's own UpdateText / UpdateFrame run
--     once more after a change, so wrapping, row heights and the scroll extent stay RestedXP's own.
--   * The scroll bar is RestedXP's own slider, restyled in place (flat thumb, small arrows, one track
--     texture); its range, wheel and arrow behaviour are untouched. The footer's version string can be
--     subdued or hidden (it is then in the menu button's tooltip). Header, footer and number tabs can draw
--     a lighter border than the window, so the borders don't stack.
--   * Only what this skin moved is put back, from a few anchors captured once before the first change
--     (origin) and from RestedXP's own refresh.
--
-- Not covered (RestedXP draws them itself or another addon owns them): the v2 guide window (beta; only
-- the theme's colours and font reach it), the map arrow and pins, RestedXP's right-click menus
-- (Blizzard's dropdown), tooltips, its options, the tracker, talent and importer windows.
--
-- Extensions: another part of RestedXP's window that follows this skin's switch registers with
-- Skin.Extend (install, finished, stripped, disabled). The countdown bars are one: modules/RestedXPTimers.lua.
--
-- Saved: TwichUIDB.modules.restedxpSkin (the switch, off by default), TwichUIDB.ui.restedxpSkin (the
-- background and border look; MenuStyle's), TwichUIDB.ui.restedxpSkinText (fonts, outlines, colours, sizes,
-- spacing and which decorations show; only values the player changed are saved, so a new setting takes
-- its default for everyone) and TwichUIDB.ui.restedxpSkinState (the name of the theme to go back to).
-- Frames and fonts are never saved.

local R = TwichUI
local Skin = {}
R.RestedXPSkin = Skin

local ADDON = "RXPGuides"
local THEME = "TwichUI"
local SWITCH = "restedxpSkin"
local WHITE = [[Interface\Buttons\WHITE8x8]]
-- Where RestedXP keeps the art its own DarkMode theme uses (banner, scroll bar, check boxes). Referenced
-- by path at run time, never copied: the files are RestedXP's.
local ART = [[Interface\AddOns\RXPGuides\Textures\DarkMode\]]
local DEBOUNCE = 0.2
local TOLERANCE = 0.004

local LOOK_DEFAULTS = {
    bgTexture = "solid", bgColor = "ff211a12", bgOpacity = 92,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
}
local TEXT_DEFAULTS = {
    titleFont = "default", titleOutline = "none", titleColor = "ffe3cf9a",
    bodyFont = "default", bodyOutline = "none", bodyColor = "ffe9e1cf",
    tintScrollbar = true,
    -- decoration RestedXP draws in the header: hidden in this look, back on request
    showLogo = false, showClassIcon = false,
    -- the guide's title in the header; hidden, the header is a slim strip and the title is in the cog's tooltip
    showTitle = true,
    -- the footer's menu button (the cog) and resize handle; RestedXP's own are shown. The menu is also
    -- the header's right click; the window can also be resized with Alt held while dragging it
    showCog = true, showResizeHandle = true,
    -- how far the guide list is dimmed, in percent (0: RestedXP's own)
    futureFade = 35,
    -- the waypoint arrow (RestedXP's RXPG_ARROW): its picture, colour and opacity, its size and its text's as
    -- a percentage of RestedXP's own (which RestedXP's Arrow Scale and Arrow Text Size options set)
    arrowShape = "bronze", arrowColor = "ffffffff", arrowOpacity = 100, arrowSize = 100,
    arrowTextShown = true, arrowTextSize = 100,
    -- text sizes: RestedXP's Guide Font Size governs until customSizes is on (the values are the sizes
    -- RestedXP itself uses at its default Guide Font Size of 9)
    customSizes = false, titleSize = 11, activeSize = 11, listSize = 9,
    lineSpacing = 1, stepPadding = 2,
    footer = "subtle", dividers = "subtle", scrollbar = "slim",
}
local TEXT_LIMITS = {
    titleSize = { 8, 24 }, activeSize = { 8, 22 }, listSize = { 8, 20 },
    lineSpacing = { 0, 6 }, stepPadding = { 0, 10 }, futureFade = { 0, 70 },
    arrowOpacity = { 20, 100 }, arrowSize = { 50, 250 }, arrowTextSize = { 60, 200 },
}
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local FOOTERS = { subtle = true, hidden = true, normal = true }
local DIVIDERS = { subtle = true, full = true }
local SCROLLBARS = { slim = true, original = true }
local FLAGS = {
    tintScrollbar = true, showLogo = true, showClassIcon = true, showTitle = true, customSizes = true,
    showCog = true, showResizeHandle = true, arrowTextShown = true,
}
Skin.OUTLINE_CHOICES = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } }
Skin.FOOTER_CHOICES = {
    { "subtle", "Subdued" }, { "hidden", "Hidden (it is in the menu button's tooltip)" },
    { "normal", "As RestedXP draws it" },
}
Skin.DIVIDER_CHOICES = { { "subtle", "Light" }, { "full", "Full border" } }
Skin.SCROLLBAR_CHOICES = { { "slim", "Slim" }, { "original", "RestedXP's own" } }
Skin.THEME, Skin.SWITCH = THEME, SWITCH

local Look = R.MenuStyle.New("restedxpSkin", LOOK_DEFAULTS)
Skin.Look = Look

---------------------------------------------------------------------------
-- Runtime state. Nothing here is saved.
---------------------------------------------------------------------------
local enabled = false           -- the switch is on and Start has run
local RXP                       -- RestedXP's addon object, once found and usable
local theme                     -- the one theme table registered with RestedXP (changed in place)
local hooks = { render = false, stepText = false, fontSize = false, arrow = false }
local hookedFrames = setmetatable({}, { __mode = "k" })
local owned = setmetatable({}, { __mode = "k" })   -- frame -> { info, origin, rev } for frames drawn on
local touched = false           -- anything has been drawn since the last strip
local rev = 0                   -- bumped when a look or text setting (or media) changes
local scheduled = false         -- a coalesced update is waiting on its timer
local wantTheme = false         -- the waiting update must go through RestedXP's own refresh
local waitingCombat = false     -- an update is held until combat ends
local pendingSelect = false     -- select the theme as soon as RestedXP is ready (turned on before it loaded)
local conflict                  -- nil, or "eui-restedxp" / "litetweaks"
local busy = false              -- re-entry guard for our own relayout call
local fallbacks = {}            -- role -> reason a saved font could not be used
local stats = { passes = 0, refreshes = 0, skipped = 0 }
local known = { n = 0 }         -- colours this skin applied earlier, so a change can find the strings it coloured
local origin = {}                -- layout RestedXP gave the few pieces this skin moves, captured before a change
local hiddenByUs = setmetatable({}, { __mode = "k" })   -- decorative regions this skin hid
local appliedSize = {}           -- role -> true while a string of that role may carry a size this skin set
local relayoutSteps = false      -- a step-card string changed size, face or spacing: RestedXP lays it out again
local relayoutList = false       -- the same for the guide list
local layoutRev = 0              -- bumped when a setting that moves or resizes something changes
local settledRev = -1            -- the layoutRev RestedXP's layouts were last settled for
local slimOn = false             -- the scroll bar is drawn slim right now
local slimFiles = {}             -- piece -> the file the game reports for what this skin set; a different one is seen

local FinishAll

-- Features that finish another part of RestedXP's window under this skin's switch (the timer bars:
-- modules/RestedXPTimers.lua) register here. Each may have install() (RestedXP is usable: hook what it
-- needs, once), finished() (a pass drew the skin), stripped() (the skin was taken off the frames) and
-- disabled() (the switch went off). Called in registration order, each guarded.
local extensions = {}

local function Notify(name)
    for i = 1, #extensions do
        local fn = extensions[i][name]
        if fn then
            local ok, err = pcall(fn)
            if not ok then R.Fault("RestedXP skin extension", err) end
        end
    end
end

---------------------------------------------------------------------------
-- Settings: the look is MenuStyle's; the text settings are here.
---------------------------------------------------------------------------
local function ValidText(key, value)
    local limit = TEXT_LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif key == "titleFont" or key == "bodyFont" then return R.Borders.ValidName(value)
    elseif key == "titleOutline" or key == "bodyOutline" then return type(value) == "string" and OUTLINES[value] ~= nil
    elseif key == "titleColor" or key == "bodyColor" then
        return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif FLAGS[key] then return type(value) == "boolean"
    elseif key == "arrowColor" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif key == "arrowShape" then return R.Borders.ValidName(value)
    elseif key == "footer" then return type(value) == "string" and FOOTERS[value] == true
    elseif key == "dividers" then return type(value) == "string" and DIVIDERS[value] == true
    elseif key == "scrollbar" then return type(value) == "string" and SCROLLBARS[value] == true end
    return false
end

local function SavedText()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.restedxpSkinText
    return type(saved) == "table" and saved or nil
end

local Text = { DEFAULTS = TEXT_DEFAULTS, LIMITS = TEXT_LIMITS }
Skin.Text = Text

function Text.Get(key)
    local saved = SavedText()
    local value = saved and saved[key]
    if ValidText(key, value) then return value end
    return TEXT_DEFAULTS[key]
end

-- Settings that move or resize something (the rest are colours and opacity, which no layout depends on).
local LAYOUT_KEYS = {
    titleFont = true, bodyFont = true, titleOutline = true, bodyOutline = true, showLogo = true, showClassIcon = true,
    showTitle = true, customSizes = true, titleSize = true, activeSize = true, listSize = true,
    lineSpacing = true, stepPadding = true, footer = true, scrollbar = true,
}

local function Changed(layout)
    rev = rev + 1
    if layout then layoutRev = layoutRev + 1 end
    if enabled and Skin.Request then Skin.Request(false) end
end

function Text.Set(key, value)
    if TEXT_DEFAULTS[key] == nil or not ValidText(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.restedxpSkinText) ~= "table" then TwichUIDB.ui.restedxpSkinText = {} end
    TwichUIDB.ui.restedxpSkinText[key] = value
    Changed(LAYOUT_KEYS[key])
    return true
end

function Text.Reset()
    if TwichUIDB and TwichUIDB.ui then TwichUIDB.ui.restedxpSkinText = nil end
    Changed(true)
end

Look.Subscribe(Changed)

-- Puts the whole RestedXP look (background, border, fonts, colours) back to the defaults. The switch, the
-- remembered theme and RestedXP's own settings are not touched.
function Skin.Reset()
    Look.Reset()
    Text.Reset()
end

local function State()
    local ui = TwichUIDB and TwichUIDB.ui
    local state = ui and ui.restedxpSkinState
    return type(state) == "table" and state or nil
end

local function RememberedTheme()
    local state = State()
    local name = state and state.previousTheme
    if R.Borders.ValidName(name) and name ~= THEME then return name end
end

local function Remember(name)
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.restedxpSkinState) ~= "table" then TwichUIDB.ui.restedxpSkinState = {} end
    TwichUIDB.ui.restedxpSkinState.previousTheme = name
end

---------------------------------------------------------------------------
-- RestedXP and who else skins it
---------------------------------------------------------------------------
local function AddonLoaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

-- RestedXP's addon object. It is not a global (the RXPGuides global is only a table of guide data); it is
-- registered with AceAddon, which RestedXP embeds. Nothing is assumed about its libraries here: without
-- AceAddon the answer is nil and the skin reports that it can't integrate.
local function FindRestedXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil end
    local ok, addon = pcall(ace.GetAddon, ace, ADDON, true)
    if ok and type(addon) == "table" then return addon end
end

-- Whether what this skin needs from RestedXP is there. Each name is one the source of RestedXP
-- v4.11.22 defines (GuideWindow.lua, Themes.lua); a different version may not have them.
local function Usable(addon)
    return type(addon) == "table" and type(addon.RenderFrame) == "function" and type(addon.RegisterTheme) == "function"
        and type(addon.themes) == "table" and type(addon.settings) == "table" and type(addon.settings.profile) == "table"
        and type(_G.RXPFrame) == "table"
end

local function V2Window()
    local v2 = RXP and RXP.v2
    return v2 and type(v2.IsGuideWindowEnabled) == "function" and v2:IsGuideWindowEnabled() and true or false
end

-- Another RestedXP skin that is drawing right now. Only the two this was written against can be
-- recognised; another provider's reskin can't be detected and may fight this one.
local function FindConflict()
    if AddonLoaded("EUI-RestedXP") then
        local db = rawget(_G, "EUIRestedxPCache")
        local on = type(db) ~= "table" or db.rxpEnabled ~= false
        local layout = type(db) == "table" and db.rxpLayout or nil
        if on and layout ~= "DEFAULT" then return "eui-restedxp" end
    end
    if AddonLoaded("LiteTweaks") then
        local db = rawget(_G, "LiteTweaksDB")
        if type(db) ~= "table" or db.rxpEnabled ~= false then return "litetweaks" end
    end
end

local function Active()
    return enabled and RXP ~= nil and theme ~= nil and conflict == nil and RXP.activeTheme == theme and not V2Window()
end

-- What an extension may read of this skin: whether it is drawing, RestedXP's addon object, and the font
-- file the guide's step text is drawn with.
Skin.Active = Active
function Skin.Addon() return RXP end
function Skin.Extend(extension)
    for i = 1, #extensions do
        if extensions[i] == extension then return end
    end
    extensions[#extensions + 1] = extension
    if enabled and Usable(RXP) and extension.install then extension.install() end
end

---------------------------------------------------------------------------
-- Fonts. Saved as LibSharedMedia names ("default" is RestedXP's own). A missing one is drawn as the
-- default and stays saved and listed, marked, until the player picks.
---------------------------------------------------------------------------
local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local fontList          -- the choices from LibSharedMedia; rebuilt only after it registers a font
local usable, usableCount = {}, 0
local probe

local function DefaultFont()
    local font = _G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont()
    return font or _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
end

-- Whether the game can draw a font file: asked once per file, with one hidden string.
local function UsableFont(path)
    local known_ = usable[path]
    if known_ ~= nil then return known_ end
    if not probe then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probe = holder:CreateFontString()
    end
    local ok, result = pcall(probe.SetFont, probe, path, 12, "")
    local good = ok and result ~= false
    if usableCount >= 16 then
        for k in pairs(usable) do usable[k] = nil end
        usableCount = 0
    end
    usable[path] = good
    usableCount = usableCount + 1
    return good
end

-- The file to draw a saved font with, and "missing" when it had to fall back.
local function ResolveFont(id)
    if id == "default" then return DefaultFont() end
    local LSM = SharedMedia()
    local list = LSM and LSM:HashTable("font")
    local path = list and list[id]
    if type(path) == "string" and path ~= "" and UsableFont(path) then return path end
    return DefaultFont(), "missing"
end

-- The file the guide's step text is drawn with (what a feature that follows it should use).
function Skin.BodyFont() return (ResolveFont(Text.Get("bodyFont"))) end

local function BuildFontList()
    local list = { { "default", "RestedXP's own font" } }
    local LSM = SharedMedia()
    local names = LSM and LSM:HashTable("font")
    local sorted = {}
    for name in pairs(names or {}) do
        if name ~= "default" and R.Borders.ValidName(name) then sorted[#sorted + 1] = name end
    end
    table.sort(sorted)
    for _, name in ipairs(sorted) do list[#list + 1] = { name, name } end
    return list
end

-- { { id, label }, ... }; the saved choice stays listed, marked, if it has gone.
function Skin.FontChoices(current)
    fontList = fontList or BuildFontList()
    for _, choice in ipairs(fontList) do
        if choice[1] == current then return fontList end
    end
    local out = {}
    for i, choice in ipairs(fontList) do out[i] = choice end
    out[#out + 1] = { current, tostring(current) .. " (not available)" }
    return out
end

R:OnInit(function()
    local LSM = SharedMedia()
    if not (LSM and LSM.RegisterCallback) then return end
    LSM.RegisterCallback(Skin, "LibSharedMedia_Registered", function(_, kind)
        if kind ~= "font" then return end
        fontList = nil
        for k in pairs(usable) do usable[k] = nil end
        usableCount = 0
        -- a saved font that was waiting for this pack can be drawn now
        if fallbacks.title or fallbacks.body then Changed(true) end
    end)
end)

---------------------------------------------------------------------------
-- The theme: one table, handed to RestedXP once and changed in place, so a settings change allocates
-- nothing. RestedXP reads it at its own refreshes.
---------------------------------------------------------------------------
local function Set(t, a, b, c, d)
    if t[1] ~= a or t[2] ~= b or t[3] ~= c or t[4] ~= d then
        t[1], t[2], t[3], t[4] = a, b, c, d
        return true
    end
    return false
end

local function BuildTheme()
    local edges = ART .. "rxp-borders"
    return {
        name = THEME, displayName = "TwichUI", author = "TwichUI", applicable = true,
        background = { 0, 0, 0, 1 }, bottomFrameBG = { 0, 0, 0, 1 }, bottomFrameHighlight = { 0, 0, 0, 0.5 },
        mapPins = { 1, 1, 1, 1 }, tooltip = "|cffc9a24a", textColor = { 1, 1, 1 },
        texturePath = ART, headerTexture = "rxp-banner", font = DefaultFont(),
        bgTextures = { edge = WHITE, bottom = WHITE },
        edges = { edge = edges, guideName = edges },
    }
end

local function Lighter(c) return math.min(1, c * 1.25 + 0.02) end

-- Writes the saved look into the theme's numbers. Returns true when anything differs from before.
local function FillTheme()
    local changed = false
    local br, bg, bb = Look.ParseColor(Look.Get("bgColor"))
    local er, eg, eb = Look.ParseColor(Look.Get("borderColor"))
    local tr, tg, tb = Look.ParseColor(Text.Get("bodyColor"))
    changed = Set(theme.background, br, bg, bb, Look.Get("bgOpacity") / 100) or changed
    changed = Set(theme.bottomFrameBG, Lighter(br), Lighter(bg), Lighter(bb), 1) or changed
    -- a row under the pointer: the row colour lifted a quarter of the way to the border colour (RestedXP
    -- paints the highlight as a plain fill, so the border colour itself would be a bright slab)
    local rr, rg, rb = Lighter(br), Lighter(bg), Lighter(bb)
    changed = Set(theme.bottomFrameHighlight, rr + (er - rr) * 0.25, rg + (eg - rg) * 0.25, rb + (eb - rb) * 0.25, 1)
        or changed
    local pins = theme.mapPins
    if Set(pins, er, eg, eb, 1) then
        theme.tooltip = ("|cff%02x%02x%02x"):format(er * 255 + 0.5, eg * 255 + 0.5, eb * 255 + 0.5)
        changed = true
    end
    local text = theme.textColor
    if text[1] ~= tr or text[2] ~= tg or text[3] ~= tb then
        text[1], text[2], text[3] = tr, tg, tb
        changed = true
    end
    local body, why = ResolveFont(Text.Get("bodyFont"))
    fallbacks.body = why
    if theme.font ~= body then theme.font = body; changed = true end
    local _, titleWhy = ResolveFont(Text.Get("titleFont"))
    fallbacks.title = titleWhy
    return changed
end

local function Publish()
    if not theme then theme = BuildTheme(); FillTheme() end
    if Usable(RXP) then
        if RXP.themes[THEME] ~= theme then RXP:RegisterTheme(theme) end
    else
        local channel = rawget(_G, "RXPGuides_Themes")
        if type(channel) ~= "table" then
            channel = {}
            _G.RXPGuides_Themes = channel
        end
        channel[THEME] = theme
    end
end

-- Takes the theme back out of RestedXP's lists (its dropdown, and the v2 copy). Nothing else of its is
-- touched; it has no call for this, so the entries are removed the way RegisterTheme added them.
local function Unpublish()
    local channel = rawget(_G, "RXPGuides_Themes")
    if type(channel) == "table" and channel[THEME] == theme then channel[THEME] = nil end
    if RXP and type(RXP.themes) == "table" and RXP.themes[THEME] == theme then RXP.themes[THEME] = nil end
    local v2 = RXP and RXP.v2
    if v2 and type(v2.themes) == "table" then v2.themes[THEME] = nil end
end

-- RestedXP's own refresh for a theme change: what its Choose Theme option runs (RenderFrame, and the v2
-- window's pieces when that is on). It reloads the guide window's text but not the guide or its progress.
local function RefreshRestedXP()
    if not Usable(RXP) then return end
    stats.refreshes = stats.refreshes + 1
    local v2 = V2Window()
    if v2 and RXP.v2 and type(RXP.v2.ConvertThemes) == "function" then pcall(RXP.v2.ConvertThemes, RXP.v2) end
    local ok, err = pcall(RXP.RenderFrame, true)
    if not ok then R.Fault("RestedXP skin refresh", err) end
    if v2 and type(RXP.ReloadTheme) == "function" then pcall(RXP.ReloadTheme, RXP) end
end

---------------------------------------------------------------------------
-- Drawing on RestedXP's frames. Each function compares what is there with what is wanted and changes
-- only what differs, so a pass over unchanged frames does no drawing and allocates nothing.
---------------------------------------------------------------------------
local function Near(r, g, b, tr, tg, tb)
    return math.abs(r - tr) < TOLERANCE and math.abs(g - tg) < TOLERANCE and math.abs(b - tb) < TOLERANCE
end

local want = {}   -- the targets: fonts and flags, colours, sizes and layout choices
local wantRev = -1
-- Read again only when a setting or the media has changed (rev), not on every pass.
local function Wants()
    if wantRev == rev and want.titlePath then return end
    wantRev = rev
    want.titlePath = ResolveFont(Text.Get("titleFont"))
    want.bodyPath = ResolveFont(Text.Get("bodyFont"))
    want.titleFlags = OUTLINES[Text.Get("titleOutline")]
    want.bodyFlags = OUTLINES[Text.Get("bodyOutline")]
    want.tr, want.tg, want.tb = Look.ParseColor(Text.Get("titleColor"))
    want.br, want.bg, want.bb = Look.ParseColor(Text.Get("bodyColor"))
    want.ar, want.ag, want.ab = Look.ParseColor(Look.Get("borderColor"))
    want.tint = Text.Get("tintScrollbar")
    want.logo, want.classIcon = Text.Get("showLogo"), Text.Get("showClassIcon")
    want.showTitle = Text.Get("showTitle")
    want.cog, want.grip = Text.Get("showCog"), Text.Get("showResizeHandle")
    -- with neither button there is nothing for the footer bar to hold: it goes, and the list takes its room
    want.bar = want.cog or want.grip
    want.fade = Text.Get("futureFade") / 100
    want.arrowShape = Text.Get("arrowShape")
    want.arR, want.arG, want.arB = Look.ParseColor(Text.Get("arrowColor"))
    want.arrowOpacity, want.arrowSize = Text.Get("arrowOpacity") / 100, Text.Get("arrowSize") / 100
    want.arrowTextShown, want.arrowTextSize = Text.Get("arrowTextShown"), Text.Get("arrowTextSize") / 100
    want.footer = Text.Get("footer")
    want.light = Text.Get("dividers") == "subtle"
    want.slim = Text.Get("scrollbar") == "slim"
    if Text.Get("customSizes") then
        want.title, want.active, want.list = Text.Get("titleSize"), Text.Get("activeSize"), Text.Get("listSize")
    else
        want.title, want.active, want.list = nil, nil, nil   -- RestedXP's Guide Font Size governs
    end
    want.spacing, want.pad = Text.Get("lineSpacing"), Text.Get("stepPadding")
end

-- Remembers a colour this skin has applied, so strings showing it can be found after the setting changes.
-- A ring of six: what a string was last coloured with is among the latest few.
local function Know(r, g, b)
    for i = 1, known.n do
        local c = known[i]
        if Near(r, g, b, c[1], c[2], c[3]) then return end
    end
    known.at = (known.at or 0) % 6 + 1
    local c = known[known.at] or {}
    c[1], c[2], c[3] = r, g, b
    known[known.at] = c
    if known.at > known.n then known.n = known.at end
end

-- A colour RestedXP itself uses for text: the base colour of one of its themes, or one this skin applied.
-- Strings with any other colour carry meaning and are left alone.
local function IsBaseColor(r, g, b)
    if Near(r, g, b, want.tr, want.tg, want.tb) or Near(r, g, b, want.br, want.bg, want.bb) then return true end
    for i = 1, known.n do
        local c = known[i]
        if Near(r, g, b, c[1], c[2], c[3]) then return true end
    end
    local themes = RXP and RXP.themes
    if type(themes) == "table" then
        for _, t in pairs(themes) do
            local c = type(t) == "table" and t.textColor
            if type(c) == "table" and type(c[1]) == "number" and Near(r, g, b, c[1], c[2], c[3]) then return true end
        end
    end
    return false
end

-- How RestedXP sizes each kind of string from its Guide Font Size (GuideWindow.lua v4.11.22:
-- UpdateGuideFontSize for the header and footer, SetStep for the step cards, LoadGuide for the list rows).
local RXP_OFFSET = { header = 2, footer = 0, label = 0, active = 2, list = 0, number = -1 }

local function RxpSize(role)
    local profile = RXP and RXP.settings and RXP.settings.profile
    local base = profile and tonumber(profile.guideFontSize) or 9
    return base + RXP_OFFSET[role]
end

local sizeBack = {}   -- roles put back to RestedXP's size in this pass; cleared when the pass ends

-- The size a string of a role should have: the player's; RestedXP's own for the one pass after the player's
-- was switched off (so recycled strings are put right); or nil, leave it as it is.
local function RoleSize(role)
    local size
    if role == "header" then size = want.title
    elseif role == "footer" then size = want.title and math.max(8, want.title - 2)
    elseif role == "label" then size = want.active and math.max(8, want.active - 2)
    elseif role == "active" then size = want.active
    elseif role == "list" then size = want.list
    elseif role == "number" then size = want.list and math.max(7, want.list - 1) end
    if role == "footer" and want.footer == "subtle" then size = math.max(8, (size or RxpSize("footer")) - 1) end
    if size then
        appliedSize[role] = true
        return size
    end
    if appliedSize[role] then
        sizeBack[role] = true
        return RxpSize(role)
    end
end

local canonPath, canonFlags = {}, {}   -- a font as the game reports it back, by the one asked for

-- Sets a string's face, outline and size; a nil part is left as it is. True if anything changed.
local function StyleFont(fs, path, flags, size)
    local current, currentSize, currentFlags = fs:GetFont()
    if not (current and currentSize) then return false end
    currentFlags = currentFlags or ""
    path, flags, size = path or current, flags or currentFlags, size or currentSize
    if (current == path or current == canonPath[path]) and (currentFlags == flags or currentFlags == canonFlags[flags])
        and currentSize == size then
        return false
    end
    if fs:SetFont(path, size, flags) == false then return false end
    local now, _, nowFlags = fs:GetFont()
    if now and now ~= path then canonPath[path] = now end
    if nowFlags and nowFlags ~= flags then canonFlags[flags] = nowFlags end
    return true
end

-- Which of RestedXP's own layouts a changed string asks to run again.
local function Flag(role)
    if role == "list" or role == "number" then relayoutList = true
    elseif role == "label" or role == "active" then relayoutSteps = true end
end

-- title: the header/footer/tab face and colour rather than the step text's; role: what the string is
-- (header, footer, label, active, list, number), which decides its size; nil for a tray's title.
local function StyleText(fs, title, role)
    if not (fs and fs.GetFont and fs.GetTextColor) then return end
    local size = role and RoleSize(role) or nil
    if StyleFont(fs, title and want.titlePath or want.bodyPath, title and want.titleFlags or want.bodyFlags, size) then
        Flag(role)
    end
    local r, g, b = fs:GetTextColor()
    if not r then return end
    local tr, tg, tb
    if title then tr, tg, tb = want.tr, want.tg, want.tb else tr, tg, tb = want.br, want.bg, want.bb end
    if not Near(r, g, b, tr, tg, tb) and IsBaseColor(r, g, b) then
        Know(r, g, b)
        fs:SetTextColor(tr, tg, tb)
    end
end

local function StyleSpacing(fs, role)
    if fs and fs.GetSpacing and fs:GetSpacing() ~= want.spacing then
        fs:SetSpacing(want.spacing)
        Flag(role)
    end
end

-- The small quest/objective icon beside a step line is a string of its own at a fixed size; its inline
-- picture scales with the string, so it follows the step text when that has a size of the player's.
local function StyleIcon(fs)
    if not (fs and fs.GetFont) then return end
    if want.active then
        appliedSize.icon = true
        StyleFont(fs, nil, nil, want.active)
    elseif appliedSize.icon then
        sizeBack.icon = true
        if fs.SetFontObject and _G.GameFontNormalSmall then fs:SetFontObject(_G.GameFontNormalSmall) end
    end
end

local function Dim(fs, alpha)
    if fs and fs.GetAlpha and math.abs(fs:GetAlpha() - alpha) > 0.01 then fs:SetAlpha(alpha) end
end

-- Dim, for a string RestedXP's timers hide (alpha 0) and show (alpha 1) themselves: one that is hidden stays
-- hidden.
local function DimLive(fs, alpha)
    if fs and fs.GetAlpha then
        local current = fs:GetAlpha()
        if current > 0.01 and math.abs(current - alpha) > 0.01 then fs:SetAlpha(alpha) end
    end
end

-- RestedXP's own backdrops: the tables its frames are given. Only a frame showing one of them is
-- drawn on (a frame RestedXP shows without a backdrop, such as the item frame with its background
-- hidden in its options, stays as it is).
local function RestedXPBackdrops()
    local frame = _G.RXPFrame
    local b = frame and frame.backdrop
    if type(b) == "table" then return b.edge, b.guideName end
end

-- A frame that sits inside the window (header, footer, a step's number tab) draws a lighter border than
-- the window itself, without the highlight and shade lines, so the borders don't stack.
local function Lighten(frame)
    local bevel = frame.twichBevel
    if bevel then
        if bevel.top then bevel.top:Hide() end
        if bevel.bottom then bevel.bottom:Hide() end
    end
    local info = frame.backdropInfo
    if info and info.edgeFile and frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(want.ar, want.ag, want.ab, Look.Get("borderOpacity") / 100 * 0.5)
    end
end

-- mode: nil, the window's own look; "inner", a frame that sits inside the window (see Lighten); "solid",
-- inner with a background that is fully opaque whatever the window's opacity (the step tab straddles the
-- card's edge and must hide what is under it); "hollow", no background or border at all (the header with its
-- title hidden: still there to be dragged and to open the menu, and the window's anchors hang from it).
local function StyleBackdrop(frame, edgeInfo, guideInfo, mode)
    if not (frame and type(frame.SetBackdrop) == "function") then return end
    local rec = owned[frame]
    local current = frame.backdropInfo
    local restedxps = current ~= nil and (current == edgeInfo or current == guideInfo)
    if rec then
        -- ours and untouched since: up to date (also when it was cleared on purpose, a texture of None
        -- and no border), or RestedXP drew its own again and it is ours to finish again
        if current == rec.info then
            if rec.rev == rev then return end
        elseif not restedxps then
            return   -- changed by something else; not ours to redraw
        end
    elseif not restedxps then
        return
    end
    local origin_ = current
    if rec and current == rec.info then origin_ = rec.origin end
    if mode == "hollow" then
        frame:ClearBackdrop()
        local bevel = frame.twichBevel
        if bevel then
            if bevel.top then bevel.top:Hide() end
            if bevel.bottom then bevel.bottom:Hide() end
        end
        if frame.twichBorders then R.Borders.Hide(frame.twichBorders) end
    else
        Look.Apply(frame)
        if mode and want.light then Lighten(frame) end
        if mode == "solid" and frame.backdropInfo and frame.backdropInfo.bgFile then
            local r, g, b = Look.ParseColor(Look.Get("bgColor"))
            frame:SetBackdropColor(r, g, b, 1)
        end
    end
    if not rec then
        rec = {}
        owned[frame] = rec
    end
    rec.info, rec.origin, rec.rev, rec.hollow = frame.backdropInfo, origin_, rev, mode == "hollow"

    touched = true
end

-- The window's header and footer art is a gradient banner; under this look the frame's own background
-- shows instead.
local function StyleBanner(holder)
    local bg = holder and holder.bg
    if bg and bg.GetAlpha and bg:GetAlpha() ~= 0 then bg:SetAlpha(0) touched = true end
end

---------------------------------------------------------------------------
-- Layout this skin moves. RestedXP sets these anchors and sizes once, when it builds the window, and does
-- not set them again, so they are captured once (origin) before the first change and put back from that.
---------------------------------------------------------------------------
local function Points(region)
    local list = {}
    for i = 1, region:GetNumPoints() do
        local point, rel, relPoint, x, y = region:GetPoint(i)
        list[i] = { point, rel, relPoint, x, y }
    end
    return list
end

local function RestorePoints(list, region)
    if not (list and region) then return end
    region:ClearAllPoints()
    for _, p in ipairs(list) do region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

local function Capture(key, region)
    if origin[key] == nil then origin[key] = Points(region) end
end

local function Restore(key, region)
    local list = origin[key]
    if list and region then
        RestorePoints(list, region)
        origin[key] = nil
    end
end

-- Hides or shows a decorative region. Only ever shows what this skin hid.
local function SetShownByUs(region, shown)
    if not (region and region.IsShown) then return end
    if shown then
        if hiddenByUs[region] then
            hiddenByUs[region] = nil
            region:Show()
        end
    elseif region:IsShown() then
        hiddenByUs[region] = true
        region:Hide()
        touched = true
    end
end

local HEADER_INSET, HEADER_PAD, HEADER_MIN, HEADER_MAX, HEADER_STRIP = 10, 7, 26, 84, 14
local BADGE_X = 16

local function InsetBoth(fs, inset)
    if fs:GetNumPoints() ~= 2 then return false end
    local _, _, _, x1 = fs:GetPoint(1)
    local _, _, _, x2 = fs:GetPoint(2)
    return (x1 == inset and x2 == -inset) or (x1 == -inset and x2 == inset)
end

-- The header is as tall as its title needs (RestedXP fixes it at 35, which clips a larger or longer title).
local function FitHeader(header, floor, strip)
    local text = header.text
    if not (text and text.GetStringHeight) then return end
    if origin.headerHeight == nil then origin.headerHeight = header:GetHeight() end
    local h
    if strip then
        h = math.max(HEADER_STRIP, floor or 0)   -- no title: a slim strip, still the window's handle and menu
    else
        h = math.ceil(text:GetStringHeight() or 0) + HEADER_PAD * 2
        h = math.min(HEADER_MAX, math.max(h, HEADER_MIN, floor or 0))
    end
    if math.abs(header:GetHeight() - h) >= 0.5 then header:SetHeight(h) end
end

-- The logo and the class badge are plain textures (no click action: the header's drag and right-click menu
-- belong to the header frame, and the cog opens the same menu). Hide() survives RestedXP's SetTexture
-- on every refresh, so nothing has to watch them.
local function StyleHeader(frame)
    local header = frame.GuideName
    if not header then return end
    local logo, badge, text = header.icon, header.classIcon, header.text
    SetShownByUs(logo, want.logo)
    SetShownByUs(badge, want.classIcon)
    SetShownByUs(text, want.showTitle)
    if text and text.GetNumPoints then
        if want.logo or want.classIcon then
            Restore("headerText", text)   -- the room RestedXP keeps for them
        else
            Capture("headerText", text)
            if not InsetBoth(text, HEADER_INSET) then
                text:ClearAllPoints()
                text:SetPoint("LEFT", header, HEADER_INSET, 0)
                text:SetPoint("RIGHT", header, -HEADER_INSET, 0)
            end
        end
    end
    -- the badge on its own sits at the header's left rather than hanging off a logo that isn't there
    if badge and badge.GetNumPoints then
        if want.classIcon and not want.logo then
            Capture("badge", badge)
            local point, _, _, x = badge:GetPoint(1)
            if not (badge:GetNumPoints() == 1 and point == "CENTER" and x == BADGE_X) then
                badge:ClearAllPoints()
                badge:SetPoint("CENTER", header, "LEFT", BADGE_X, 0)
            end
        else
            Restore("badge", badge)
        end
    end
    FitHeader(header, want.logo and 42 or (want.classIcon and 28 or 0), not want.showTitle)
end

-- The cog is the footer's menu button (it opens the same menu as the header's right click) and has no
-- tooltip of RestedXP's own; this gives it one, with the version string when that is not shown.
local function OnCogEnter(self)
    local tip = _G.GameTooltip
    if not Active() or not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
    tip:SetOwner(self, "ANCHOR_TOPLEFT")
    tip:AddLine("RestedXP menu", 1, 1, 1)
    tip:AddLine("Click to choose a guide, go to a step or open the options.", 0.8, 0.8, 0.8, true)
    local window = _G.RXPFrame
    local header = window and window.GuideName
    local title = header and header.text and header.text:GetText()
    if want.showTitle == false and type(title) == "string" and title ~= "" then
        tip:AddLine((title:gsub("\n", " - ")), 0.9, 0.85, 0.7, true)
    end
    local footer = window and window.Footer
    local version = footer and footer.text and footer.text:GetText()
    if want.footer ~= "normal" and type(version) == "string" and version ~= "" then
        tip:AddLine(version, 0.62, 0.62, 0.62)
    end
    tip:Show()
end

local function OnCogLeave(self)
    local tip = _G.GameTooltip
    if tip and tip.GetOwner and tip:GetOwner() == self then tip:Hide() end
end

local function HookCog(cog)
    if cog and type(cog.HookScript) == "function" and not hookedFrames[cog] then
        hookedFrames[cog] = true
        cog:HookScript("OnEnter", OnCogEnter)
        cog:HookScript("OnLeave", OnCogLeave)
    end
end

-- The footer's string is the addon version and the guide format range RestedXP supports (set by its own
-- BetaVersionCheck on every list update). It is information, not guide content: subdued by default, and
-- hidden on request (it is then in the menu button's tooltip).
local FOOTER_ALPHA = 0.7
local FOOTER_INSET = 8

local function StyleFooter(frame)
    local footer = frame.Footer
    if not footer then return end
    local text = footer.text
    SetShownByUs(footer, want.bar)
    SetShownByUs(text, want.footer ~= "hidden" and want.bar)
    -- the string belongs to the header's frame and the cog to the window's, so the list fade (below)
    -- reaches them here; RestedXP's timers set both to 0 or 1 themselves while a timer bar shows
    local fade = 1 - want.fade
    if text and want.footer ~= "hidden" and want.bar then
        DimLive(text, (want.footer == "subtle" and FOOTER_ALPHA or 1) * fade)
    end
    DimLive(footer.cog, fade)
    HookCog(footer.cog)
    -- The cog and the grip are only buttons: Hide() persists (RestedXP's timers change their strength, never
    -- their visibility), and a hidden one takes no clicks. The string takes the room they kept.
    SetShownByUs(footer.cog, want.cog)
    SetShownByUs(footer.icon, want.grip)
    if text and text.GetNumPoints then
        if want.cog and want.grip then
            Restore("footerText", text)
        else
            Capture("footerText", text)
            local saved = origin.footerText
            if saved and #saved == 2 and saved[1][1] == "LEFT" and saved[2][1] == "RIGHT" then
                local left = want.cog and saved[1][4] or FOOTER_INSET
                local right = want.grip and saved[2][4] or -FOOTER_INSET
                local _, _, _, x1 = text:GetPoint(1)
                local _, _, _, x2 = text:GetPoint(2)
                if not (text:GetNumPoints() == 2 and x1 == left and x2 == right) then
                    text:ClearAllPoints()
                    text:SetPoint("LEFT", saved[1][2], left, saved[1][5])
                    text:SetPoint("RIGHT", saved[2][2], right, saved[2][5])
                end
            end
        end
    end
end

-- RestedXP lets the list's frame run 6 px down behind the footer (its bottom edge is 14 above the window's,
-- the footer is 20 high). Opaque, that hides; both faded, the two borders and fills show through each
-- other. The list ends where the footer begins, or at the window's edge when the footer bar is gone. RestedXP
-- sets this anchor once, when it builds the window, and works the scroll range out from the list frame's own
-- height, so the range follows.
local function SeparateFooter(frame)
    local list, footer = frame.BottomFrame, frame.Footer
    if not (list and footer and list.GetNumPoints and footer.GetHeight) then return end
    local height = footer:GetHeight()
    if not (height and height > 0) then return end
    local target = want.bar and height or 0
    for i = 1, list:GetNumPoints() do
        local point, rel, relPoint, x, y = list:GetPoint(i)
        if point == "BOTTOMRIGHT" and rel == frame and y then
            if not origin.list then
                if y >= height then return end   -- not RestedXP's layout; left alone
                Capture("list", list)
            end
            if y ~= target then list:SetPoint(point, rel, relPoint, x, target) end
            touched = true
            return
        end
    end
end

-- The guide list as one piece fades: its background and border, the scroll bar, the rows, and the footer
-- with its menu button and resize grip. The header and the current-step panel stay as they are, so the step
-- being done stands out. RestedXP never sets the strength of the list's or the footer's own frame (only of
-- the footer's string, button and grip, for its timers), so there is nothing to follow.
local function FadeContainer(frame)
    local alpha = 1 - want.fade
    for _, holder in ipairs({ frame.BottomFrame or false, frame.Footer or false }) do
        if holder and holder.GetAlpha and math.abs(holder:GetAlpha() - alpha) > 0.005 then holder:SetAlpha(alpha) end
    end
end

local SCROLL_PIECES = { "Normal", "Highlight", "Pushed", "Disabled" }
local SCROLL_BUTTONS = { "ScrollUpButton", "ScrollDownButton" }
-- Without EllesmereUI the arrows are the game's own art for the same template (Blizzard_SharedXML
-- SecureUIPanelTemplates.xml), in place of RestedXP's round badges.
local ARROW_BASE = {
    ScrollUpButton = [[Interface\Buttons\UI-ScrollBar-ScrollUpButton-]],
    ScrollDownButton = [[Interface\Buttons\UI-ScrollBar-ScrollDownButton-]],
}
local ARROW_SUFFIX = { Normal = "Up", Pushed = "Down", Disabled = "Disabled", Highlight = "Highlight" }
-- With EllesmereUI: the way its own windows draw this template's bar (EllesmereUIBlizzardSkin_WindowPacks.lua:
-- the stock arrow art is faded out and the thumb becomes a thin strip), with its arrow icons on the buttons
-- the way its scroll bars draw theirs (EllesmereUI.lua AttachSmoothScrollbar). Only its published media
-- path (EllesmereUI.ICONS_PATH) is read; its smooth-scroll helper is not used, because it replaces the
-- frame's wheel and range scripts, which are RestedXP's own here.
local EUI_ARROWS = { ScrollUpButton = "eui-arrow-up3.png", ScrollDownButton = "eui-arrow-down3.png" }
-- RestedXP keeps 20 px right of the list for its bar. The slim bar is centred in it, with arrows that sit
-- clear of the header and footer. The list's own frame is not moved: RestedXP works out the scroll range
-- from the frames' heights, and a smaller viewport would cut off the last row.
local SLIM = { bar = 8, thumb = 5, button = 12, icon = 10, track = 5, edge = 12, inset = 16 }
-- Opacities: the thumb and track as EllesmereUI draws them (white, a third and almost nothing), a little
-- stronger when they carry the border colour; the arrow icons rest, hover and can't scroll.
local THUMB_ALPHA, THUMB_ALPHA_TINTED, TRACK_ALPHA = 0.3, 0.5, 0.08
local ARROW_REST, ARROW_HOVER, ARROW_OFF = 0.6, 1, 0.25

local function EllesmereIcons()
    local e = _G.EllesmereUI
    local path = type(e) == "table" and e.ICONS_PATH
    if type(path) == "string" and path ~= "" then return path end
end

local function Tint(texture, r, g, b)
    if not (texture and texture.GetVertexColor) then return end
    local cr, cg, cb = texture:GetVertexColor()
    if not (cr and Near(cr, cg, cb, r, g, b)) then texture:SetVertexColor(r, g, b) end
end

-- Colour and opacity together (a vertex colour has an alpha of its own).
local function TintAlpha(texture, r, g, b, a)
    if not (texture and texture.GetVertexColor) then return end
    local cr, cg, cb, ca = texture:GetVertexColor()
    if not (cr and Near(cr, cg, cb, r, g, b) and math.abs((ca or 1) - a) < TOLERANCE) then
        texture:SetVertexColor(r, g, b, a)
    end
end

local function TintScrollbar(r, g, b)
    local frame = _G.RXPFrame
    local bar = frame and frame.ScrollFrame and frame.ScrollFrame.ScrollBar
    if not bar then return end
    for k = 1, #SCROLL_BUTTONS do
        local button = bar[SCROLL_BUTTONS[k]]
        if button then
            for i = 1, #SCROLL_PIECES do Tint(button[SCROLL_PIECES[i]], r, g, b) end
        end
    end
    Tint(bar.GetThumbTexture and bar:GetThumbTexture(), r, g, b)
end

-- An arrow icon's opacity from the button's state. The template's buttons have no scripts of their own, so
-- these hooks are the only ones.
local function ArrowAlpha(button)
    local arrow = button.twichArrow
    if not arrow then return end
    local a = ARROW_REST
    if button.IsEnabled and not button:IsEnabled() then a = ARROW_OFF
    elseif button.twichHover then a = ARROW_HOVER end
    if math.abs(arrow:GetAlpha() - a) > 0.01 then arrow:SetAlpha(a) end
end
local function ArrowEnter(button) button.twichHover = true; ArrowAlpha(button) end
local function ArrowLeave(button) button.twichHover = false; ArrowAlpha(button) end

local function RestoreScrollbar(frame)
    slimOn = false
    for k in pairs(slimFiles) do slimFiles[k] = nil end
    local scroll = frame and frame.ScrollFrame
    local bar = scroll and scroll.ScrollBar
    local o = origin.scroll
    origin.scroll = nil
    if not (bar and o) then return end
    RestorePoints(o.bar, bar)
    if o.width then bar:SetWidth(o.width) end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
        if o.thumbW then thumb:SetSize(o.thumbW, o.thumbH) end
        if o.coords and #o.coords == 8 then thumb:SetTexCoord(unpack(o.coords)) end
        thumb:SetVertexColor(1, 1, 1, 1)
    end
    for key, size in pairs(o.buttons) do
        local button = bar[key]
        if button then
            button:SetSize(size[1], size[2])
            for i = 1, #SCROLL_PIECES do
                local piece = button[SCROLL_PIECES[i]]
                if piece then
                    if piece.SetAlpha then piece:SetAlpha(1) end
                    if piece.SetVertexColor then piece:SetVertexColor(1, 1, 1, 1) end
                end
            end
            if button.twichArrow then button.twichArrow:Hide() end
        end
    end
    if bar.twichTrack then bar.twichTrack:Hide() end
    -- RestedXP's own art for the arrows and the knob
    if type(frame.UpdateScrollBar) == "function" then pcall(frame.UpdateScrollBar) end
end

-- RestedXP's own slider, restyled in place: its range, wheel, thumb dragging and arrows are its own and
-- the template's. Only anchors, sizes and the files drawn change.
local function StyleScrollbar(frame)
    local scroll = frame.ScrollFrame
    local bar = scroll and scroll.ScrollBar
    if not bar then return end
    if not want.slim then
        if slimOn then RestoreScrollbar(frame) end
        if want.tint then TintScrollbar(want.ar, want.ag, want.ab) else TintScrollbar(1, 1, 1) end
        return
    end
    if not origin.scroll then
        local o = { bar = Points(bar), width = bar:GetWidth(), buttons = {} }
        local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
        if thumb then
            o.thumbW, o.thumbH = thumb:GetWidth(), thumb:GetHeight()
            o.coords = { thumb:GetTexCoord() }
        end
        for _, key in ipairs(SCROLL_BUTTONS) do
            local button = bar[key]
            if button then o.buttons[key] = { button:GetWidth(), button:GetHeight() } end
        end
        origin.scroll = o
    end
    slimOn = true
    touched = true
    local barPoint, barRel, _, barX, barY = bar:GetPoint(1)
    local placed = bar:GetNumPoints() == 2 and barPoint == "TOPRIGHT" and barRel == scroll
        and barX == SLIM.edge and barY == -SLIM.inset
    if not placed then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", SLIM.edge, -SLIM.inset)
        bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", SLIM.edge, SLIM.inset)
    end
    if bar:GetWidth() ~= SLIM.bar then bar:SetWidth(SLIM.bar) end

    -- the strip's colour: the border colour (the setting), else EllesmereUI's neutral white
    local r, g, b, thumbAlpha = 1, 1, 1, THUMB_ALPHA
    if want.tint then r, g, b, thumbAlpha = want.ar, want.ag, want.ab, THUMB_ALPHA_TINTED end

    local track = bar.twichTrack
    if not track then
        track = bar:CreateTexture(nil, "BACKGROUND")
        bar.twichTrack = track
        track:SetPoint("TOP")
        track:SetPoint("BOTTOM")
        track:SetWidth(SLIM.track)
    end
    if track.twichRev ~= rev then
        track:SetColorTexture(r, g, b, TRACK_ALPHA)
        track.twichRev = rev
    end
    if not track:IsShown() then track:Show() end

    -- RestedXP sets the knob file again whenever it refreshes the window; the file the game reports back
    -- for ours is remembered, so a different one is seen without any polling
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
        local file = thumb:GetTexture()
        if slimFiles.thumb == nil or file ~= slimFiles.thumb then
            thumb:SetTexture(WHITE)
            thumb:SetTexCoord(0, 1, 0, 1)
            slimFiles.thumb = thumb:GetTexture()
        end
        if thumb:GetWidth() ~= SLIM.thumb then thumb:SetSize(SLIM.thumb, origin.scroll.thumbH or thumb:GetHeight()) end
        TintAlpha(thumb, r, g, b, thumbAlpha)
    end

    local icons = EllesmereIcons()
    for _, key in ipairs(SCROLL_BUTTONS) do
        local button = bar[key]
        if button then
            if button:GetWidth() ~= SLIM.button then button:SetSize(SLIM.button, SLIM.button) end
            if icons then
                -- the stock art is faded out (nothing is hidden: the button keeps its clicks and states)
                for _, piece in ipairs(SCROLL_PIECES) do
                    local texture = button[piece]
                    if texture and texture.GetAlpha and texture:GetAlpha() ~= 0 then texture:SetAlpha(0) end
                end
                local arrow = button.twichArrow
                if not arrow then
                    arrow = button:CreateTexture(nil, "OVERLAY")
                    button.twichArrow = arrow
                    arrow:SetSize(SLIM.icon, SLIM.icon)
                    arrow:SetPoint("CENTER")
                    arrow:SetTexture(icons .. EUI_ARROWS[key])
                    if not hookedFrames[button] and type(button.HookScript) == "function" then
                        hookedFrames[button] = true
                        button:HookScript("OnEnter", ArrowEnter)
                        button:HookScript("OnLeave", ArrowLeave)
                        button:HookScript("OnEnable", ArrowAlpha)
                        button:HookScript("OnDisable", ArrowAlpha)
                    end
                end
                if not arrow:IsShown() then arrow:Show() end
                Tint(arrow, r, g, b)
                ArrowAlpha(button)
            else
                for _, piece in ipairs(SCROLL_PIECES) do
                    local texture = button[piece]
                    if texture and texture.GetTexture then
                        local id = key .. piece
                        local file = texture:GetTexture()
                        if slimFiles[id] == nil or file ~= slimFiles[id] then
                            texture:SetTexture(ARROW_BASE[key] .. ARROW_SUFFIX[piece])
                            slimFiles[id] = texture:GetTexture()
                        end
                        TintAlpha(texture, 1, 1, 1, 0.8)
                    end
                end
            end
        end
    end
end

local NUMBER_ALPHA = 0.7
local HOVER_LIFT = 0.4   -- how far a dimmed row rises toward full strength under the pointer (RestedXP: all of it)

-- RestedXP's row OnEnter raises the row to full strength; for a row dimmed because it is done, that is a
-- jump from half to bright. This runs RestedXP's own handler, then eases the jump. RestedXP's OnLeave
-- restores the strength it remembered, so nothing is stored for that.
local function RowEnter(row, ...)
    local original = row.twichEnter
    if original then original(row, ...) end
    local base = row.currentAlpha
    if type(base) == "number" and base < 1 and row:GetAlpha() > base then
        row:SetAlpha(base + (1 - base) * HOVER_LIFT)
    end
end

-- RestedXP sets a row's OnEnter again whenever it loads a guide; this puts ours back around the new one.
local function WrapRowEnter(row)
    if not (row.GetScript and row.SetScript) then return end
    local enter = row:GetScript("OnEnter")
    if enter ~= RowEnter then
        row.twichEnter = enter or false
        row:SetScript("OnEnter", RowEnter)
    end
end

local ROW_PAD_X, ROW_PAD_Y, ROW_NUMBER_X, ROW_NUMBER_Y, ROW_GAP = 6, 4, 6, 3, 3

-- A list row's text starts a little in from the row's edge, centred in the height RestedXP gives it
-- (text height + 8), and stops short of the number.
local function PlaceRowText(row)
    local text, number = row.text, row.number
    if not (text and text.GetNumPoints) then return end
    local point, rel, _, x, y = text:GetPoint(1)
    if text:GetNumPoints() == 2 and point == "TOPLEFT" and rel == row and x == ROW_PAD_X and y == -ROW_PAD_Y then
        return
    end
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", row, ROW_PAD_X, -ROW_PAD_Y)
    if number then text:SetPoint("RIGHT", number, "LEFT", -4, 0) else text:SetPoint("RIGHT", row, -ROW_PAD_X, 0) end
    relayoutList = true
end

-- The number is subordinate and sits in from the edge.
local function PlaceRowNumber(row)
    local number = row.number
    if not (number and number.GetNumPoints) then return end
    local point, rel, _, x, y = number:GetPoint(1)
    if number:GetNumPoints() == 1 and point == "BOTTOMRIGHT" and rel == row and x == -ROW_NUMBER_X
        and y == ROW_NUMBER_Y then
        return
    end
    number:ClearAllPoints()
    number:SetPoint("BOTTOMRIGHT", row, -ROW_NUMBER_X, ROW_NUMBER_Y)
    relayoutList = true
end

-- RestedXP hangs a shown row 3 below the one before it (a hidden row is pulled up 1); the gap is
-- widened by the step padding. RestedXP's own row list extent is read from the first and last row, so
-- the scroll range follows.
local function SpaceRow(row)
    if not (row.GetNumPoints and row:GetNumPoints() == 2) then return end
    local p1, rel1, rp1, x1, y1 = row:GetPoint(1)
    if p1 ~= "TOPLEFT" or rp1 ~= "BOTTOMLEFT" or not y1 or y1 >= 0 then return end
    local wanted = -(ROW_GAP + want.pad)
    if y1 == wanted then return end
    local p2, rel2, rp2, x2 = row:GetPoint(2)
    row:ClearAllPoints()
    row:SetPoint(p1, rel1, rp1, x1, wanted)
    row:SetPoint(p2, rel2, rp2, x2, wanted)
    relayoutList = true
end

local function FinishSteps(edgeInfo, guideInfo)
    local frame = _G.RXPFrame
    local pool = frame and frame.CurrentStepFrame and frame.CurrentStepFrame.framePool
    if type(pool) == "table" then
        for i = 1, #pool do
            local step = pool[i]
            StyleBackdrop(step, edgeInfo, guideInfo)
            local number = step.number
            if number then
                StyleBackdrop(number, edgeInfo, guideInfo, "solid")
                StyleText(number.text, true, "label")
                -- above everything the card draws, its lines and border included
                local level = step:GetFrameLevel() + 4
                if number:GetFrameLevel() ~= level then number:SetFrameLevel(level) end
            end
            local elements = step.elements
            if type(elements) == "table" then
                for j = 1, #elements do
                    local element = elements[j]
                    StyleText(element.text, false, "active")
                    StyleSpacing(element.text, "active")
                    StyleIcon(element.icon)
                end
            end
        end
    end
    local rows = frame and frame.ScrollChild and frame.ScrollChild.framePool
    if type(rows) == "table" then
        for i = 1, #rows do
            local row = rows[i]
            StyleText(row.text, false, "list")
            StyleSpacing(row.text, "list")
            PlaceRowText(row)
            if row.number then
                StyleText(row.number.text, false, "number")
                Dim(row.number.text, NUMBER_ALPHA)
                PlaceRowNumber(row)
            end
            if i > 1 then SpaceRow(row) end
            WrapRowEnter(row)
        end
    end
end

-- RestedXP lays the cards out as: a number tab 17 high at (7, 5), the first line 10 below the card's top,
-- and every line as high as its text. After RestedXP's own layout this adds the step padding under each
-- line and room for a taller tab. It must run only straight after RestedXP's layout (which sets every
-- height afresh); it is never run twice on the same layout.
local TAB_X, TAB_Y, TAB_H, TAB_CLEAR = 9, 5, 17, 4

local function PadSteps()
    local frame = _G.RXPFrame
    local csf = frame and frame.CurrentStepFrame
    local pool = csf and csf.framePool
    if type(pool) ~= "table" then return end
    local pad = want.pad
    local added = 0
    for i = 1, #pool do
        local card = pool[i]
        if card.IsShown and card:IsShown() and card:GetAlpha() > 0.01 then
            local extra = 0
            local tab = card.number
            -- the first line starts clear of the tab (RestedXP's own is flush against it), by the step
            -- padding and a little; with no padding it is RestedXP's own
            local push = pad > 0 and (TAB_CLEAR + pad) or 0
            if tab and tab.text and tab:GetAlpha() > 0.01 then
                local _, size = tab.text:GetFont()
                local h = math.max(TAB_H, math.ceil(size or 11) + 7)
                tab:SetSize(math.ceil(tab.text:GetStringWidth() or 0) + 16, h)
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", card, TAB_X, TAB_Y + math.floor((h - TAB_H) / 2))
                push = push + math.ceil((h - TAB_H) / 2)
            end
            local lines = card.elements
            if type(lines) == "table" then
                for j = 1, #lines do
                    local line = lines[j]
                    if type(line.IsShown) == "function" and line:IsShown() and line:GetAlpha() > 0.01 then
                        line:SetHeight(line:GetHeight() + pad)
                        extra = extra + pad
                    end
                end
                local first = lines[1]
                if push > 0 and type(first) == "table" and type(first.GetNumPoints) == "function" then
                    for k = 1, first:GetNumPoints() do
                        local point, rel, relPoint, x, y = first:GetPoint(k)
                        first:SetPoint(point, rel, relPoint, x, y - push)
                    end
                end
            end
            card:SetHeight(card:GetHeight() + extra + push)
            -- a tip window is its own, movable frame: it is not part of the panel's height
            if not (card.step and card.step.tip) then added = added + extra + push end
        end
    end
    if added > 0 then csf:SetHeight(csf:GetHeight() + added) end
end

-- RestedXP's own layouts, run once more after a change here. busy keeps our own hooks out of it.
local function RelayoutSteps()
    local csf = _G.RXPFrame and _G.RXPFrame.CurrentStepFrame
    if csf and type(csf.UpdateText) == "function" then pcall(csf.UpdateText) end
end

-- BottomFrame.UpdateFrame with a self that has no step is what RestedXP itself runs while the window is
-- being resized: it lays out every row from its text and refreshes the list's extent and scroll range,
-- without calling any guide step's own update.
local function RelayoutList()
    local bottom = _G.RXPFrame and _G.RXPFrame.BottomFrame
    if bottom and type(bottom.UpdateFrame) == "function" then pcall(bottom.UpdateFrame, bottom) end
end

local function FinishWindow(edgeInfo, guideInfo)
    local frame = _G.RXPFrame
    if not frame then return end
    StyleBackdrop(frame.BottomFrame, edgeInfo, guideInfo)
    StyleBackdrop(frame.GuideName, edgeInfo, guideInfo, want.showTitle and "inner" or "hollow")
    StyleBackdrop(frame.Footer, edgeInfo, guideInfo, "inner")
    StyleBanner(frame.GuideName)
    StyleBanner(frame.Footer)
    StyleText(frame.GuideName and frame.GuideName.text, true, "header")
    StyleText(frame.Footer and frame.Footer.text, true, "footer")
    StyleHeader(frame)
    StyleFooter(frame)
    FadeContainer(frame)
    SeparateFooter(frame)
    StyleScrollbar(frame)
end

local function FinishTray(tray, edgeInfo, guideInfo)
    if not tray then return end
    StyleBackdrop(tray, edgeInfo, guideInfo)
    local title = tray.title
    if title then
        StyleBackdrop(title, edgeInfo, guideInfo, "inner")
        StyleText(title.text, true)
    end
end

local OnTrayVisuals   -- set below: the hook for a tray's own UpdateVisuals

local function HookTray(tray)
    if tray and type(tray.UpdateVisuals) == "function" and not hookedFrames[tray] then
        hookedFrames[tray] = true
        hooksecurefunc(tray, "UpdateVisuals", OnTrayVisuals)
    end
end

local function FinishTrays(edgeInfo, guideInfo)
    local item = RXP and (RXP.activeItemFrame or (_G.RXPFrame and _G.RXPFrame.activeItemFrame))
    local targets = RXP and RXP.targeting and RXP.targeting.activeTargetFrame
    HookTray(item)
    HookTray(targets)
    FinishTray(item, edgeInfo, guideInfo)
    FinishTray(targets, edgeInfo, guideInfo)
end

---------------------------------------------------------------------------
-- The waypoint arrow (RestedXP's RXPG_ARROW): a 32 x 32 frame (times its Arrow Scale) whose one texture
-- RestedXP rotates every frame from its own OnUpdate, with a string below it for the step and distance.
-- Nothing here touches the rotation or the text: the picture, its colour and opacity, its size and the
-- string's size and visibility. RestedXP sets the picture in the arrow's UpdateVisuals (every theme
-- refresh), the size in SetSize (login, its option, a profile change) and the string's font in SetFont,
-- so those three are hooked, once, and what it just set is scaled; no polling.
---------------------------------------------------------------------------
-- (One table, not a dozen locals: a Lua function has at most 200.)
local Arrow = {
    FILE = "rxp_navigation_arrow-1",   -- what RestedXP adds to a theme's texture path (GetV1Texture)
    CHEVRON = "eui-chevron",
    BRONZE = "bronze",                 -- TwichUI's own: media/textures/arrow-bronze.tga (128 x 128)
    busy = false,                      -- our own change to the arrow is under way: its hooks stand aside
    file = nil,                        -- the file the game reports for the picture this skin set (nil: RestedXP's own)
    path = nil,                        -- the one that was asked for
}

function Arrow.Frame()
    local arrow = RXP and RXP.arrowFrame
    if type(arrow) == "table" and arrow.texture and arrow.text then return arrow end
end

-- The file for a saved shape: TwichUI's bronze plate, a RestedXP theme's own arrow (the theme's name), one of
-- its v2 theme's ("v2:" and the name), EllesmereUI's chevron, or nil for RestedXP's own for the theme
-- ("default": RestedXP draws it).
function Arrow.Path(style)
    if style == "default" then return nil end
    if style == Arrow.BRONZE then return R.PATH .. [[media\textures\arrow-bronze]] end
    if style == Arrow.CHEVRON then
        local icons = EllesmereIcons()
        return icons and (icons .. "eui-arrow-up3.png") or nil
    end
    local v2Name = style:match("^v2:(.+)$")
    if v2Name then
        local v2 = RXP and RXP.v2 and RXP.v2.themes
        local t = type(v2) == "table" and v2[v2Name]
        local path = type(t) == "table" and t.navigationArrow
        return type(path) == "string" and path or nil
    end
    local themes = RXP and RXP.themes
    local t = type(themes) == "table" and themes[style]
    local path = type(t) == "table" and t.texturePath
    if type(path) == "string" and path ~= "" then return path .. Arrow.FILE end
end

-- { { id, label }, ... } for the shape choices: what RestedXP's own themes draw, its v2 arrow, EllesmereUI's
-- chevron. Read when the list is opened, from what is there then. The saved choice stays listed, marked, if
-- it has gone.
function Skin.ArrowChoices(current)
    local list = { { Arrow.BRONZE, "Bronze plate (TwichUI)" }, { "default", "RestedXP's own pointer for its theme" } }
    local names = {}
    local themes = RXP and RXP.themes
    if type(themes) == "table" then
        for name, t in pairs(themes) do
            if name ~= THEME and type(t) == "table" and type(t.texturePath) == "string" and t.texturePath ~= ART
                and R.Borders.ValidName(name) then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local label = themes[name].displayName
        if not (type(label) == "string" and R.Borders.ValidName(label)) then label = name end
        list[#list + 1] = { name, label .. " pointer" }
    end
    local v2 = RXP and RXP.v2 and RXP.v2.themes
    if type(v2) == "table" then
        local v2Names = {}
        for name, t in pairs(v2) do
            if type(t) == "table" and type(t.navigationArrow) == "string" and R.Borders.ValidName(name) then
                v2Names[#v2Names + 1] = name
            end
        end
        table.sort(v2Names)
        for _, name in ipairs(v2Names) do list[#list + 1] = { "v2:" .. name, name .. " pointer" } end
    end
    if EllesmereIcons() then list[#list + 1] = { Arrow.CHEVRON, "Chevron (EllesmereUI)" } end
    for _, choice in ipairs(list) do
        if choice[1] == current then return list end
    end
    list[#list + 1] = { current, tostring(current) .. " (not available)" }
    return list
end

function Arrow.RxpSize()
    local profile = RXP and RXP.settings and RXP.settings.profile
    return 32 * (profile and tonumber(profile.arrowScale) or 1)
end

function Arrow.RxpTextSize()
    local profile = RXP and RXP.settings and RXP.settings.profile
    return profile and tonumber(profile.arrowText) or 9
end

function Arrow.TextSizeFor(base)
    return math.max(5, math.min(40, math.floor(base * want.arrowTextSize + 0.5)))
end

-- Puts the saved look on the arrow. Compares before it sets, so a pass over an arrow that is right does
-- nothing. In combat it waits (as everything here does).
function Arrow.Apply()
    local arrow = Arrow.Frame()
    if not (arrow and Active()) then return end
    if InCombatLockdown() then waitingCombat = true; return end
    Wants()
    Arrow.busy = true
    local texture = arrow.texture
    local path = Arrow.Path(want.arrowShape)
    if path then
        local file = texture:GetTexture()
        if Arrow.file == nil or Arrow.path ~= path or file ~= Arrow.file then
            texture:SetTexture(path)
            Arrow.path, Arrow.file = path, texture:GetTexture()
        end
        touched = true
    elseif Arrow.file ~= nil then
        Arrow.file, Arrow.path = nil, nil   -- back to RestedXP's own picture, which it sets itself
        if type(arrow.UpdateVisuals) == "function" then pcall(arrow.UpdateVisuals, arrow) end
    end
    TintAlpha(texture, want.arR, want.arG, want.arB, want.arrowOpacity)
    local size = Arrow.RxpSize() * want.arrowSize
    if math.abs(arrow:GetWidth() - size) > 0.01 then arrow:SetSize(size, size) end
    SetShownByUs(arrow.text, want.arrowTextShown)
    local face, current, flags = arrow.text:GetFont()
    if face and current then
        local target = Arrow.TextSizeFor(Arrow.RxpTextSize())
        if current ~= target then arrow.text:SetFont(face, target, flags or "") end
    end
    Arrow.busy = false
end

-- RestedXP's own arrow back: its picture (by its own refresh), no tint, its size and its string's size.
function Arrow.Restore()
    local arrow = Arrow.Frame()
    if not arrow then return end
    Arrow.busy = true
    if Arrow.file ~= nil then
        Arrow.file, Arrow.path = nil, nil
        if type(arrow.UpdateVisuals) == "function" then pcall(arrow.UpdateVisuals, arrow) end
    end
    TintAlpha(arrow.texture, 1, 1, 1, 1)
    SetShownByUs(arrow.text, true)
    local size = Arrow.RxpSize()
    if math.abs(arrow:GetWidth() - size) > 0.01 then arrow:SetSize(size, size) end
    local face, current, flags = arrow.text:GetFont()
    local textSize = Arrow.RxpTextSize()
    if face and current and current ~= textSize then arrow.text:SetFont(face, textSize, flags or "") end
    Arrow.busy = false
end

function Arrow.OnVisuals()
    if not Arrow.busy and enabled then Arrow.Apply() end
end

-- RestedXP sized the arrow (w x h): ours is that, scaled.
function Arrow.OnSize(arrow, width)
    if Arrow.busy or not (enabled and Active()) or type(width) ~= "number" then return end
    if InCombatLockdown() then waitingCombat = true; return end
    Wants()
    local size = width * want.arrowSize
    if math.abs(width - size) > 0.01 then
        Arrow.busy = true
        arrow:SetSize(size, size)
        Arrow.busy = false
    end
end

-- RestedXP set the string's font (face, size, flags): ours is that size, scaled.
function Arrow.OnFont(text, face, size, flags)
    if Arrow.busy or not (enabled and Active()) or type(size) ~= "number" then return end
    if InCombatLockdown() then waitingCombat = true; return end
    Wants()
    local target = Arrow.TextSizeFor(size)
    if target ~= size then
        Arrow.busy = true
        text:SetFont(face, target, flags or "")
        Arrow.busy = false
    end
end

local listPending = false   -- the list's layout has to run again, once it is safe to
local listTimer = false     -- ...and a zero-delay call to do that is waiting

-- Runs a frame after a pass made while RestedXP was laying the window out, when its own layout can no
-- longer be interrupted by ours.
local function SettleList()
    listTimer = false
    if not (listPending and enabled and Active()) then
        listPending = false
        return
    end
    if InCombatLockdown() then
        waitingCombat = true   -- the request that follows combat runs it
        return
    end
    listPending = false
    busy = true
    RelayoutList()
    busy = false
end

-- One pass over everything this skin touches. The frames are RestedXP's own: its window, its step
-- cards and rows (a pool it grows only as steps need), and its two small trays.
-- fresh: RestedXP has just laid the step cards out (the pass is its UpdateText hook).
function FinishAll(fresh)
    if InCombatLockdown() then waitingCombat = true; stats.skipped = stats.skipped + 1; return end
    stats.passes = stats.passes + 1
    local edgeInfo, guideInfo = RestedXPBackdrops()
    Wants()
    local dirty = settledRev ~= layoutRev   -- a layout setting changed since the layouts were last settled
    relayoutSteps, relayoutList = false, false
    FinishWindow(edgeInfo, guideInfo)
    FinishSteps(edgeInfo, guideInfo)
    FinishTrays(edgeInfo, guideInfo)
    Arrow.Apply()
    if not busy then
        -- A size, face, spacing or padding that differs changes how tall RestedXP's lines are: its own
        -- layout settles that, once. The padding goes on after it, never before and never twice.
        busy = true
        local laidOut = fresh
        if dirty or relayoutSteps then
            RelayoutSteps()
            laidOut = true
        end
        if dirty then listPending = true end
        if fresh then
            -- Inside RestedXP's own layout. When it is a guide load, the list is laid out by RestedXP right
            -- after this, with the rows as they are now; a setting that changed meanwhile is settled a
            -- moment later instead of in the middle of it.
            if listPending and not listTimer then
                listTimer = true
                C_Timer.After(0, SettleList)
            end
        elseif listPending or relayoutList then
            listPending = false
            RelayoutList()
        end
        busy = false
        if laidOut then PadSteps() end
        settledRev = layoutRev
    end
    for role in pairs(sizeBack) do
        appliedSize[role] = nil
        sizeBack[role] = nil
    end
    Notify("finished")
end

-- Gives a frame back its RestedXP look: our overlays go, and a backdrop of ours still on it is
-- replaced with the table RestedXP gave it. RestedXP's own refresh (run just before this) normally
-- has done that already.
local function Strip(frame, rec, background)
    local bevel = frame.twichBevel
    if bevel then
        if bevel.top then bevel.top:Hide() end
        if bevel.bottom then bevel.bottom:Hide() end
    end
    if frame.twichBorders then R.Borders.Hide(frame.twichBorders) end
    -- ours still on it (or, for a hollow one, nothing: RestedXP's refresh normally repainted it already)
    local ours = rec.info ~= nil and frame.backdropInfo == rec.info
    local hollow = rec.hollow and frame.backdropInfo == nil
    if (ours or hollow) and rec.origin and frame.SetBackdrop then
        frame:ClearBackdrop()
        frame:SetBackdrop(rec.origin)
        if background then frame:SetBackdropColor(background[1], background[2], background[3], background[4]) end
    end
end

-- role: as StyleText. The face and colour are put back only where they still show what this skin applied;
-- a size only for a role whose size this skin set.
local function UnstyleText(fs, title, role)
    if not (fs and fs.GetFont and fs.GetTextColor) then return end
    local themeFont = RXP and RXP.font
    local current, size, flags = fs:GetFont()
    local path = title and want.titlePath or want.bodyPath
    local f = title and want.titleFlags or want.bodyFlags
    local canonical = canonFlags[f]
    if current and size and themeFont and (current == path or current == canonPath[path])
        and ((flags or "") == f or (canonical ~= nil and (flags or "") == canonical)) then
        fs:SetFont(themeFont, size, "")
    end
    if role and appliedSize[role] then
        local face, now, outline = fs:GetFont()
        local target = RxpSize(role)
        if face and now and now ~= target then fs:SetFont(face, target, outline or "") end
    end
    if (role == "active" or role == "list") and fs.GetSpacing and fs:GetSpacing() ~= 0 then fs:SetSpacing(0) end
    if (role == "footer" or role == "number") and fs.GetAlpha and fs:GetAlpha() > 0.01 then fs:SetAlpha(1) end
    local r, g, b = fs:GetTextColor()
    local base = RXP and RXP.activeTheme and RXP.activeTheme.textColor
    if r and type(base) == "table" and base[1] ~= nil then
        local tr, tg, tb
        if title then tr, tg, tb = want.tr, want.tg, want.tb else tr, tg, tb = want.br, want.bg, want.bb end
        local isOurs = Near(r, g, b, tr, tg, tb)
        for i = 1, known.n do
            if Near(r, g, b, known[i][1], known[i][2], known[i][3]) then isOurs = true end
        end
        if isOurs and not Near(r, g, b, base[1], base[2], base[3]) then fs:SetTextColor(base[1], base[2], base[3]) end
    end
end

local function UnstyleTray(tray)
    if tray and tray.title then UnstyleText(tray.title.text, true) end
end

-- RestedXP's anchors for a list row (GuideWindow.lua v4.11.22, LoadGuide). Its own refresh sets the text
-- and the gap again when it reloads the guide; the number's anchor it sets only once, when it makes the row.
local function RestoreRow(row)
    local number, text = row.number, row.text
    if number and number.SetPoint then
        number:ClearAllPoints()
        number:SetPoint("BOTTOMRIGHT", row)
    end
    if text and text.SetPoint then
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", row, 0, -5)
        text:SetPoint("RIGHT", number or row, number and "LEFT" or "RIGHT", 0, 0)
    end
    if row.GetNumPoints and row:GetNumPoints() == 2 then
        local p1, rel1, rp1, x1, y1 = row:GetPoint(1)
        if p1 == "TOPLEFT" and rp1 == "BOTTOMLEFT" and y1 and y1 < 0 and y1 ~= -ROW_GAP then
            local p2, rel2, rp2, x2 = row:GetPoint(2)
            row:ClearAllPoints()
            row:SetPoint(p1, rel1, rp1, x1, -ROW_GAP)
            row:SetPoint(p2, rel2, rp2, x2, -ROW_GAP)
        end
    end
end

-- Takes the look off everything it was drawn on. Never changes what a frame shows or does.
local function StripAll()
    Wants()
    local background = RXP and RXP.colors and RXP.colors.background
    for frame, rec in pairs(owned) do Strip(frame, rec, background) end
    local frame = _G.RXPFrame
    if frame then
        for _, holder in ipairs({ frame.GuideName or false, frame.Footer or false }) do
            local bg = holder and holder.bg
            if bg and bg.GetAlpha and bg:GetAlpha() == 0 then bg:SetAlpha(1) end
        end
        Restore("list", frame.BottomFrame)
        local header = frame.GuideName
        if header then
            for _, region in ipairs({ header.icon or false, header.classIcon or false, header.text or false }) do
                if region and hiddenByUs[region] then
                    hiddenByUs[region] = nil
                    region:Show()
                end
            end
            Restore("headerText", header.text)
            Restore("badge", header.classIcon)
            if origin.headerHeight then
                header:SetHeight(origin.headerHeight)
                origin.headerHeight = nil
            end
        end
        local footer = frame.Footer
        if footer then
            for _, region in ipairs({ footer, footer.text or false, footer.cog or false, footer.icon or false }) do
                if region and hiddenByUs[region] then
                    hiddenByUs[region] = nil
                    region:Show()
                end
            end
            Restore("footerText", footer.text)
        end
        -- the list's fade (RestedXP's timers own the string's and the button's own strength: a hidden one stays so)
        for _, holder in ipairs({ frame.BottomFrame or false, footer or false }) do
            if holder and holder:GetAlpha() ~= 1 then holder:SetAlpha(1) end
        end
        if footer and footer.cog and footer.cog:GetAlpha() > 0.01 then footer.cog:SetAlpha(1) end
        UnstyleText(header and header.text, true, "header")
        UnstyleText(footer and footer.text, true, "footer")
        local pool = frame.CurrentStepFrame and frame.CurrentStepFrame.framePool
        for i = 1, type(pool) == "table" and #pool or 0 do
            local step = pool[i]
            if step.number then
                UnstyleText(step.number.text, true, "label")
                -- RestedXP sets the tab's anchor once, when it makes the card; its level is the card's + 1
                if step.number.SetPoint then
                    step.number:ClearAllPoints()
                    step.number:SetPoint("TOPLEFT", step, 7, 5)
                    step.number:SetFrameLevel(step:GetFrameLevel() + 1)
                end
            end
            for j = 1, type(step.elements) == "table" and #step.elements or 0 do
                local line = step.elements[j]
                UnstyleText(line.text, false, "active")
                if appliedSize.icon and line.icon and line.icon.SetFontObject and _G.GameFontNormalSmall then
                    line.icon:SetFontObject(_G.GameFontNormalSmall)
                end
            end
        end
        local rows = frame.ScrollChild and frame.ScrollChild.framePool
        for i = 1, type(rows) == "table" and #rows or 0 do
            UnstyleText(rows[i].text, false, "list")
            if rows[i].number then UnstyleText(rows[i].number.text, false, "number") end
            RestoreRow(rows[i])
            local row = rows[i]
            if row.twichEnter ~= nil then
                if row:GetScript("OnEnter") == RowEnter then row:SetScript("OnEnter", row.twichEnter or nil) end
                row.twichEnter = nil
            end
        end
        if slimOn or origin.scroll then RestoreScrollbar(frame) end
        TintScrollbar(1, 1, 1)
        Arrow.Restore()
    end
    if RXP then
        UnstyleTray(RXP.activeItemFrame)
        UnstyleTray(RXP.targeting and RXP.targeting.activeTargetFrame)
    end
    for key in pairs(owned) do owned[key] = nil end
    for role in pairs(appliedSize) do appliedSize[role] = nil end
    for role in pairs(sizeBack) do sizeBack[role] = nil end
    listPending = false
    settledRev = -1
    touched = false
    Notify("stripped")
end

---------------------------------------------------------------------------
-- Hooks: RestedXP's own refreshes, each installed once and gated.
---------------------------------------------------------------------------
local function OnRender()
    if not enabled then return end
    conflict = FindConflict()
    if Active() then FinishAll()
    elseif touched and not InCombatLockdown() then StripAll() end
end

-- RestedXP has just laid the step cards out (also from inside its own guide load). With no guide it
-- returns before laying anything out, and its heights are then not fresh: nothing is added to them.
local function OnStepText()
    if not busy and Active() then
        FinishAll(RXP.currentGuide ~= nil and RXP.currentGuide ~= false)
    end
end

local function OnFontSize()
    if Active() then FinishAll() end
end

function OnTrayVisuals()
    if not Active() or InCombatLockdown() then return end
    local edgeInfo, guideInfo = RestedXPBackdrops()
    Wants()
    FinishTrays(edgeInfo, guideInfo)
end

local function InstallHooks()
    if not Usable(RXP) then return false end
    if not hooks.render then
        hooks.render = true
        hooksecurefunc(RXP, "RenderFrame", OnRender)
    end
    local csf = _G.RXPFrame.CurrentStepFrame
    if not hooks.stepText and type(csf) == "table" and type(csf.UpdateText) == "function" then
        hooks.stepText = true
        hooksecurefunc(csf, "UpdateText", OnStepText)
    end
    local arrow = Arrow.Frame()
    if not hooks.arrow and arrow and type(arrow.UpdateVisuals) == "function" then
        hooks.arrow = true
        hooksecurefunc(arrow, "UpdateVisuals", Arrow.OnVisuals)
        hooksecurefunc(arrow, "SetSize", Arrow.OnSize)
        hooksecurefunc(arrow.text, "SetFont", Arrow.OnFont)
    end
    if not hooks.fontSize and type(RXP.UpdateGuideFontSize) == "function" then
        hooks.fontSize = true
        hooksecurefunc(RXP, "UpdateGuideFontSize", OnFontSize)
    end
    Notify("install")
    return true
end

---------------------------------------------------------------------------
-- Scheduling: setting changes (a slider drag is dozens) become one update, applied when it is safe.
---------------------------------------------------------------------------
local function Flush()
    scheduled = false
    if not enabled then wantTheme = false; return end
    if InCombatLockdown() then waitingCombat = true; return end
    local rebuild = wantTheme
    wantTheme = false
    conflict = FindConflict()
    if not Usable(RXP) then return end
    local changed = theme and FillTheme()
    if (changed or rebuild) and RXP.activeTheme == theme then
        RefreshRestedXP()   -- its refresh runs the hooks, which finish the frames
    elseif Active() then
        FinishAll()
    elseif touched then
        StripAll()
    end
end

-- Asks for an update. Many requests become one, applied with the settings as they are then.
-- themeToo: RestedXP's own refresh is wanted as well (the theme's colours or font changed).
function Skin.Request(themeToo)
    if themeToo then wantTheme = true end
    if scheduled or not enabled then return end
    scheduled = true
    C_Timer.After(DEBOUNCE, Flush)
end

local pendingTeardown = false   -- turned off in combat: RestedXP's refresh and the strip wait for it to end

-- Hands RestedXP its own look back: its refresh, then our overlays off. Out of combat only.
local function Teardown()
    pendingTeardown = false
    if Usable(RXP) then RefreshRestedXP() end
    if touched or next(owned) ~= nil then StripAll() end
    Unpublish()
end

local function OnRegenEnabled()
    if pendingTeardown and not enabled then
        Teardown()
    elseif waitingCombat then
        waitingCombat = false
        if enabled then Skin.Request(true) end
    end
    if not enabled and not pendingTeardown then R:Off("PLAYER_REGEN_ENABLED", OnRegenEnabled) end
end

local function Attach()
    if not enabled then return end
    RXP = RXP or FindRestedXP()
    conflict = FindConflict()
    if not Usable(RXP) then return end
    InstallHooks()
    Publish()
    if pendingSelect then
        pendingSelect = false
        Skin.UseTheme()
    elseif RXP.activeTheme == theme then
        Skin.Request(true)
    end
end

local function OnAddonLoaded(name)
    if name == ADDON then
        -- RestedXP sets itself up in its own handler for this same event: look once that has run.
        C_Timer.After(0, Attach)
    elseif name == "EUI-RestedXP" or name == "LiteTweaks" then
        conflict = FindConflict()
        if conflict and touched and not InCombatLockdown() then StripAll() end
    end
end

---------------------------------------------------------------------------
-- Turning it on and off
---------------------------------------------------------------------------
-- Makes TwichUI's theme RestedXP's, remembering the one it replaces (once), and has RestedXP refresh.
-- Returns true, or false and why ("not-ready", "conflict", "combat").
function Skin.UseTheme()
    if not (enabled and Usable(RXP)) then return false, "not-ready" end
    conflict = FindConflict()
    if conflict then return false, "conflict" end
    if InCombatLockdown() then waitingCombat = true; wantTheme = true; return false, "combat" end
    Publish()
    FillTheme()
    local profile = RXP.settings.profile
    if profile.activeTheme ~= THEME then
        local previous = profile.activeTheme
        if R.Borders.ValidName(previous) then Remember(previous) end
        profile.activeTheme = THEME
    end
    RefreshRestedXP()
    return true
end

local function Start()
    if enabled then return end
    enabled = true
    pendingTeardown = false
    RXP = FindRestedXP()
    conflict = FindConflict()
    if not theme then theme = BuildTheme(); FillTheme() end
    R:On("ADDON_LOADED", OnAddonLoaded)
    R:On("PLAYER_REGEN_ENABLED", OnRegenEnabled)
    if not (R.Life and R.Life.loggedIn) then R:On("PLAYER_LOGIN", Attach) end
    Publish()
    if Usable(RXP) then InstallHooks() end
end

local function Stop()
    if not enabled then return end
    enabled = false
    scheduled, wantTheme, waitingCombat, pendingSelect = false, false, false, false
    Notify("disabled")
    R:Off("ADDON_LOADED", OnAddonLoaded)
    R:Off("PLAYER_LOGIN", Attach)
    -- RestedXP's own setting goes back first (a plain value: allowed in combat)
    if Usable(RXP) then
        local profile = RXP.settings.profile
        if profile.activeTheme == THEME then
            local back = RememberedTheme()
            if not (back and RXP.themes[back]) then back = "RXP Blue" end
            profile.activeTheme = back
        end
    end
    if InCombatLockdown() then
        pendingTeardown = true   -- OnRegenEnabled stays registered until this is done
    else
        Teardown()
        R:Off("PLAYER_REGEN_ENABLED", OnRegenEnabled)
    end
end

-- The switch changed in Settings (or its value should be re-read).
function Skin.OnSwitch()
    if R:Enabled(SWITCH) then
        local first = not enabled
        Start()
        if first then
            if Usable(RXP) then Skin.UseTheme() else pendingSelect = true end
        end
    else
        Stop()
    end
end

R:OnInit(function()
    if not R:Enabled(SWITCH) then return end
    Start()
    -- RestedXP was already up (it loads after this addon unless something loaded it first)
    if _G.RXPFrame and AddonLoaded(ADDON) then C_Timer.After(0, Attach) end
end)

---------------------------------------------------------------------------
-- What it is doing, for the settings page and the troubleshooting report. Words and counts only.
---------------------------------------------------------------------------
-- Status: a code, and the facts behind it. Codes: off, restedxp-missing, restedxp-disabled, waiting,
-- unsupported, conflict, theme-not-selected, v2-window, active.
function Skin.Status()
    local state = R.Setups and R.Setups.AddonState and R.Setups.AddonState(ADDON) or (AddonLoaded(ADDON) and "ready" or "unknown")
    local s = {
        switchOn = R:Enabled(SWITCH) and true or false, enabled = enabled, addon = state,
        loaded = AddonLoaded(ADDON), integrated = enabled and Usable(RXP) or false,
        conflict = enabled and FindConflict() or nil, v2 = enabled and Usable(RXP) and V2Window() or false,
        selected = enabled and theme ~= nil and RXP ~= nil and RXP.activeTheme == theme or false,
        published = theme ~= nil and RXP ~= nil and type(RXP.themes) == "table" and RXP.themes[THEME] == theme or false,
    }
    local loggedIn = R.Life and R.Life.loggedIn
    local code
    if not s.switchOn then code = "off"
    elseif state == "missing" then code = "restedxp-missing"
    elseif state == "disabled" then code = "restedxp-disabled"
    elseif not s.integrated then code = (s.loaded and loggedIn) and "unsupported" or "waiting"
    elseif s.conflict then code = "conflict"
    elseif not s.selected then code = "theme-not-selected"
    elseif s.v2 then code = "v2-window"
    else code = "active" end
    s.code = code
    return s
end

local function CountOwned()
    local n = 0
    for _ in pairs(owned) do n = n + 1 end
    return n
end

-- Counts and flags only: no frames, text or settings values.
function Skin.Snapshot()
    local s = Skin.Status()
    local hookCount = 0
    for _, v in pairs(hooks) do if v then hookCount = hookCount + 1 end end
    local trays = 0
    for _ in pairs(hookedFrames) do trays = trays + 1 end
    s.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or nil
    s.hooks, s.trayHooks, s.owned = hookCount, trays, CountOwned()
    s.scheduled, s.waitingCombat, s.pendingSelect, s.touched = scheduled, waitingCombat, pendingSelect, touched
    s.pendingTeardown = pendingTeardown
    s.passes, s.refreshes, s.skipped = stats.passes, stats.refreshes, stats.skipped
    s.fallbackTitle, s.fallbackBody = fallbacks.title, fallbacks.body
    s.sharedMedia = SharedMedia() ~= nil
    s.ellesmere = R.Borders.Ellesmere() ~= nil
    s.remembered = RememberedTheme() ~= nil
    s.knownColors = known.n
    return s
end
